// qcache <db file> [iterations] [seed]: the plan cache across prepares against the interpreter. Each step prepares a
// statement (one of QS, a random parameter), runs it through qc (sqlite3_qc + sqlite3_qc_exec) and finalizes it, then
// runs the same text through the interpreter; the two results must be equal, value by value. Between steps, at
// random: schema changes from this connection and from a second one (ADD COLUMN, CREATE / DROP INDEX), ANALYZE, data
// changes, a user function and a collation redefined, the connection closed and reopened, two handles of one text
// alive at once. Prints the cache's hits and misses; any difference fails. Builds a fresh database at <db file>.
#include "sqlite3.c"
#include "qc.c"
#if QC_STOCK   /* (stock SQLite: no hook frees a statement's plan with it) */
#define sqlite3_finalize sqlite3_qc_finalize
#endif
#include <stdio.h>
#include <stdlib.h>

static u64 rs = 88172645463325252ULL;
static u64 rnd(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }
static int fk = 3;   /* myf(x) = x * fk: redefined (in place) between steps */
static void myf(sqlite3_context *c, int n, sqlite3_value **a) {
  (void)n; if (sqlite3_value_type(a[0]) == SQLITE_NULL) return;
  sqlite3_result_int64(c, sqlite3_value_int64(a[0]) * fk);
}
static int rev = 0;   /* the "flip" collation: binary, reversed when rev */
static int flipcmp(void *u, int na, const void *a, int nb, const void *b) {
  (void)u; int n = na < nb ? na : nb, c = memcmp(a, b, (size_t)n); if (!c) c = na - nb;
  return rev ? -c : c;
}
static const char *QS[] = {
  "SELECT a, b, c FROM t WHERE a = ?1",
  "SELECT * FROM t WHERE a BETWEEN ?1 AND ?1 + 20 ORDER BY a",
  "SELECT b, count(*), sum(c) FROM t WHERE a > ?1 GROUP BY b ORDER BY b",
  "SELECT t.a, u.y FROM t JOIN u ON u.x = t.a WHERE t.a < ?1 + 30 ORDER BY t.a, u.y",
  "SELECT a FROM t WHERE b = 'k' || (?1 % 7) ORDER BY a DESC LIMIT 5",
  "SELECT myf(a), myf(c) FROM t WHERE a % 13 = ?1 % 13 ORDER BY a",
  "SELECT b FROM t WHERE a < ?1 ORDER BY b COLLATE flip, a LIMIT 10",
  "SELECT a, (SELECT count(*) FROM u WHERE u.x = t.a) FROM t WHERE a > ?1 ORDER BY a LIMIT 8",
  "SELECT a, row_number() OVER (PARTITION BY b ORDER BY a) FROM t WHERE a < ?1 ORDER BY a",
  "WITH RECURSIVE r(n) AS (SELECT ?1 % 10 UNION ALL SELECT n + 1 FROM r WHERE n < 40) SELECT sum(n), count(*) FROM r",
  "SELECT DISTINCT b FROM t WHERE c > ?1 / 10.0 ORDER BY 1",
  "SELECT a FROM t WHERE a IN (SELECT x FROM u WHERE y > ?1 % 50) ORDER BY a",
  "SELECT upper(b), length(b), abs(c - ?1) FROM t WHERE a = ?1 + 1",
  "SELECT * FROM u WHERE x = ?1 ORDER BY y",
  "SELECT a, b FROM t WHERE b LIKE 'k' || (?1 % 3) || '%' ORDER BY a LIMIT 7",
  "SELECT count(*) FROM t WHERE a > ?1 AND b IS NOT NULL",
  "SELECT max(a), min(c), avg(a) FROM t WHERE a < ?1",
  "SELECT a FROM t WHERE a > ?1 UNION SELECT x FROM u WHERE x < ?1 ORDER BY 1 LIMIT 12",
};
#define NQ ((int)(sizeof QS / sizeof QS[0]))

static sqlite3 *db, *db2; static const char *path;
static void exec(sqlite3 *d, const char *sql) {
  char *e = 0; if (sqlite3_exec(d, sql, 0, 0, &e) != SQLITE_OK) { fprintf(stderr, "qcache: %s: %s\n", sql, e ? e : "?"); exit(2); }
}
static void open_main(void) {
  if (sqlite3_open(path, &db) != SQLITE_OK) exit(2);
  sqlite3_create_function(db, "myf", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, 0, myf, 0, 0);
  sqlite3_create_collation(db, "flip", SQLITE_UTF8, 0, flipcmp);
}
static u64 hval(u64 h, int type, const void *z, int n, i64 iv, double rv) {
  h = (h ^ (unsigned)type) * 1099511628211ULL;
  if (type == SQLITE_INTEGER) { for (int k = 0; k < 8; k++) h = (h ^ ((u64)iv >> (8 * k) & 255)) * 1099511628211ULL; }
  else if (type == SQLITE_FLOAT) { u64 b; memcpy(&b, &rv, 8); for (int k = 0; k < 8; k++) h = (h ^ (b >> (8 * k) & 255)) * 1099511628211ULL; }
  else if (type == SQLITE_TEXT || type == SQLITE_BLOB) for (int k = 0; k < n; k++) h = (h ^ ((const u8 *)z)[k]) * 1099511628211ULL;
  return h;
}
typedef struct { u64 h; int rows; } Acc;
static int qc_cb(void *ctx, int nrow, int ncol, const QcVal *v) {
  Acc *a = ctx; a->h = 1469598103934665603ULL; a->rows = nrow;
  for (int i = 0; i < nrow * ncol; i++) a->h = hval(a->h, v[i].type, v[i].z, v[i].n, v[i].i, v[i].r);
  return 0;
}
static int interp(const char *sql, i64 p, Acc *a) {
  sqlite3_stmt *s; if (sqlite3_prepare_v2(db, sql, -1, &s, 0) != SQLITE_OK) return -1;
  sqlite3_bind_int64(s, 1, p); a->h = 1469598103934665603ULL; a->rows = 0; int rc;
  while ((rc = sqlite3_step(s)) == SQLITE_ROW) {
    a->rows++;
    for (int c = 0; c < sqlite3_column_count(s); c++) {
      int t = sqlite3_column_type(s, c);
      a->h = hval(a->h, t, t == SQLITE_TEXT ? (const void *)sqlite3_column_text(s, c) : sqlite3_column_blob(s, c), sqlite3_column_bytes(s, c),
                  sqlite3_column_int64(s, c), sqlite3_column_double(s, c));
    }
  }
  sqlite3_finalize(s); return rc == SQLITE_DONE ? 0 : -1;
}
static int ncol = 0, nix = 0;
static void change(void) {   /* one random change between steps */
  char q[256];
  switch (rnd() % 9) {
    case 0: snprintf(q, sizeof q, "ALTER TABLE t ADD COLUMN d%d INTEGER DEFAULT %d", ncol, ncol); ncol++; exec(rnd() % 2 ? db : db2, q); break;
    case 1: snprintf(q, sizeof q, "CREATE INDEX IF NOT EXISTS ix%d ON t(b, a)", nix % 3); nix++; exec(rnd() % 2 ? db : db2, q); break;
    case 2: snprintf(q, sizeof q, "DROP INDEX IF EXISTS ix%d", (int)(rnd() % 3)); exec(rnd() % 2 ? db : db2, q); break;
    case 3: exec(db, rnd() % 2 ? "ANALYZE" : "DROP TABLE IF EXISTS sqlite_stat1"); break;
    case 4: snprintf(q, sizeof q, "UPDATE t SET c = c + 1, b = 'k' || (a %% %d) WHERE a %% 17 = %d", 5 + (int)(rnd() % 4), (int)(rnd() % 17)); exec(db2, q); break;
    case 5: fk = 1 + (int)(rnd() % 9); sqlite3_create_function(db, "myf", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, 0, myf, 0, 0); break;
    case 6: rev = !rev; sqlite3_create_collation(db, "flip", SQLITE_UTF8, 0, flipcmp); break;
    case 7: sqlite3_close(db); open_main(); break;
    case 8: snprintf(q, sizeof q, "INSERT INTO u(x, y) VALUES (%d, %d)", (int)(rnd() % 300), (int)(rnd() % 100)); exec(db2, q); break;
  }
}
int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: qcache <db file> [iterations] [seed]\n"); return 2; }
  path = argv[1]; int N = argc > 2 ? atoi(argv[2]) : 20000; if (argc > 3) rs ^= (u64)strtoull(argv[3], 0, 10) * 0x9e3779b97f4a7c15ULL;
  remove(path);
  open_main(); if (sqlite3_open(path, &db2) != SQLITE_OK) return 2;
  exec(db, "CREATE TABLE t(a INTEGER PRIMARY KEY, b TEXT, c REAL); CREATE TABLE u(x INTEGER, y INTEGER); CREATE INDEX ux ON u(x)");
  exec(db, "BEGIN");
  for (int i = 1; i <= 400; i++) { char q[128]; snprintf(q, sizeof q, "INSERT INTO t VALUES (%d, 'k%d', %d.5)", i, i % 7, i % 23); exec(db, q); }
  for (int i = 0; i < 800; i++) { char q[128]; snprintf(q, sizeof q, "INSERT INTO u VALUES (%d, %d)", i % 300, i % 97); exec(db, q); }
  exec(db, "COMMIT");
  long compared = 0, fell = 0, diffs = 0;
  for (int it = 0; it < N; it++) {
    if (!getenv("QCACHE_NOCHANGE") && rnd() % 40 == 0) change();
    int q = (int)(rnd() % NQ); i64 p = (i64)(rnd() % 400);
    exec(db, "BEGIN");
    sqlite3_stmt *s, *s2 = 0;
    if (sqlite3_prepare_v2(db, QS[q], -1, &s, 0) != SQLITE_OK) { fprintf(stderr, "qcache: prepare %s: %s\n", QS[q], sqlite3_errmsg(db)); return 2; }
    if (rnd() % 8 == 0) sqlite3_prepare_v2(db, QS[q], -1, &s2, 0);   /* a second live handle of the same text */
    sqlite3_bind_int64(s, 1, p);
    Acc a = {0, -1}, b; int rc = QC_FALLBACK;
    if (sqlite3_qc(s)) rc = sqlite3_qc_exec(s, qc_cb, &a);
    if (s2) { sqlite3_bind_int64(s2, 1, p); if (sqlite3_qc(s2)) { Acc a2 = {0, -1}; if (sqlite3_qc_exec(s2, qc_cb, &a2) == SQLITE_OK && rc == SQLITE_OK && (a2.h != a.h || a2.rows != a.rows)) { diffs++; fprintf(stderr, "DIFF (two handles) %s ?1=%lld\n", QS[q], (long long)p); } } }
    sqlite3_finalize(s); if (s2) sqlite3_finalize(s2);
    if (interp(QS[q], p, &b)) { fprintf(stderr, "qcache: interpreter failed on %s: %s\n", QS[q], sqlite3_errmsg(db)); return 2; }
    exec(db, "COMMIT");
    if (rc != SQLITE_OK) { fell++; if (getenv("QCACHE_WHY")) fprintf(stderr, "WHY %s | %s\n", qc_why, QS[q]); continue; }
    compared++;
    if (a.h != b.h || a.rows != b.rows) { diffs++; fprintf(stderr, "DIFF %s ?1=%lld: qc %d rows, interpreter %d\n", QS[q], (long long)p, a.rows, b.rows); }
  }
  printf("qcache: %d steps, %ld compared, %ld fell back, %ld differences; cache: %llu hits, %llu misses (signature changed)\n",
         N, compared, fell, diffs, (unsigned long long)qv_cache_hits, (unsigned long long)qv_cache_misses);
  sqlite3_close(db); sqlite3_close(db2); sqlite3_qc_release();
  return diffs ? 1 : 0;
}
