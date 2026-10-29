// serve [iterations] [seed]: qc serving through sqlite3_step (sqlite3_qc_serve) against SQLite alone, through the plain
// API only: prepare, bind, step, column_*, reset, finalize. Each query runs with serving on, then off, and the two
// runs' rows must be equal value by value, including what the column_* conversions return (text of an integer, an
// integer of a text). Also: a statement stepped part way and reset, or finalized, before its rows are all read;
// statements stepped inside another's loop; autocommit and explicit transactions; a schema change between runs.
#include "sqlite3.c"
#include "qc.c"
#include <stdio.h>
#include <stdlib.h>

static u64 rs = 88172645463325252ULL;
static u64 rnd(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }
static u64 hb(u64 h, const void *z, int n) { for (int k = 0; k < n; k++) h = (h ^ ((const u8 *)z)[k]) * 1099511628211ULL; return h; }
static u64 hi(u64 h, i64 v) { return hb(h, &v, 8); }
static void ex(sqlite3 *db, const char *q) { char *e = 0; if (sqlite3_exec(db, q, 0, 0, &e)) { fprintf(stderr, "serve: %s: %s\n", q, e); exit(2); } }
static const char *QS[] = {
  "SELECT a, b, c FROM t WHERE a = ?1", "SELECT * FROM t WHERE a BETWEEN ?1 AND ?1 + 30 ORDER BY a", "SELECT b, count(*), sum(c), avg(c) FROM t GROUP BY b ORDER BY b",
  "SELECT t.a, u.y FROM t JOIN u ON u.x = t.a WHERE t.a < ?1 ORDER BY t.a, u.y", "SELECT a, b FROM t WHERE b LIKE ?2 ORDER BY a LIMIT 7",
  "SELECT a FROM t ORDER BY c DESC, a LIMIT 5", "SELECT DISTINCT b FROM t ORDER BY 1", "SELECT count(*) FROM t", "SELECT max(a), min(b), total(c) FROM t WHERE a > ?1",
  "SELECT a, (SELECT count(*) FROM u WHERE u.x = t.a) FROM t WHERE a > ?1 ORDER BY a LIMIT 9", "SELECT a, row_number() OVER (ORDER BY c) FROM t WHERE a < ?1 + 50",
  "WITH RECURSIVE r(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < ?1 % 40 + 2) SELECT n, n * n FROM r", "SELECT 1 + ?1, 'x' || ?2",
  "SELECT a, upper(b), length(b), substr(b, 2), c * 2 FROM t WHERE a % 7 = ?1 % 7 ORDER BY a", "SELECT b, group_concat(a) FROM t GROUP BY b",
};
#define NQ ((int)(sizeof QS / sizeof QS[0]))
/* one run of q: every row's values, read through every column_* accessor in turn; stop: rows to read before stopping
   (reset or finalize mid-run), -1 all */
static sqlite3 *db2;   /* a second connection to the same file: a statement on it mid-run too (qc's state is one for all) */
static u64 run(sqlite3 *db, const char *q, i64 p1, const char *p2, int stop, int *rows, int fin, int nested) {
  sqlite3_stmt *s; if (sqlite3_prepare_v2(db, q, -1, &s, 0) != SQLITE_OK) { fprintf(stderr, "serve: prepare %s: %s\n", q, sqlite3_errmsg(db)); exit(2); }
  sqlite3_bind_int64(s, 1, p1); if (sqlite3_bind_parameter_count(s) >= 2) sqlite3_bind_text(s, 2, p2, -1, SQLITE_STATIC);
  u64 h = 1469598103934665603ULL; int n = 0, rc;
  for (int rep = 0; rep < 2; rep++) {   /* (twice per handle: a reused handle) */
    while ((rc = sqlite3_step(s)) == SQLITE_ROW) {
      int nc = sqlite3_column_count(s); h = hi(h, nc); h = hi(h, sqlite3_data_count(s));
      for (int c = 0; c < nc; c++) {
        int t = sqlite3_column_type(s, c); h = hi(h, t);
        switch ((n + c) % 3) {   /* (the accessors in turn: conversions of every kind) */
          case 0: { const unsigned char *z = sqlite3_column_text(s, c); int b = sqlite3_column_bytes(s, c); h = hi(h, b); if (z) h = hb(h, z, b); break; }
          case 1: h = hi(h, sqlite3_column_int64(s, c)); { double r = sqlite3_column_double(s, c); h = hb(h, &r, 8); } break;
          default: { const void *z = sqlite3_column_blob(s, c); int b = sqlite3_column_bytes(s, c); h = hi(h, b); if (z) h = hb(h, z, b); h = hi(h, sqlite3_column_type(s, c)); }
        }
      }
      if (nested && n % 5 == 0) { int r2; h ^= run((n / 5) % 3 == 2 && db2 ? db2 : db, QS[(n / 5) % NQ], n, "%a%", -1, &r2, 0, 0) * 31; }   /* another statement while this one is mid-run */
      if (nested == 2 && n % 3 == 1) { char w[80]; snprintf(w, sizeof w, "INSERT INTO w VALUES (%d, 'w%d')", n, n); ex(db, w); }   /* a write mid-run (to a table it doesn't read) */
      n++;
      if (stop >= 0 && n >= stop) break;
    }
    h = hi(h, rc == SQLITE_ROW ? 100 : rc);
    if (fin && rep == 0 && stop >= 0) break;   /* finalized with rows left */
    sqlite3_reset(s);
  }
  sqlite3_finalize(s); *rows = n; return h;
}
/* julianday('now') of a served statement, prepared fresh after a statement with a binding (bench, 2026-10-28: qc ran
   before sqlite3Step reset the statement's time, and a new statement read uninitialised memory: -4712-11-06) */
static int now_ok(sqlite3 *db) {
  const char *q = "SELECT a, strftime('%Y-%m-%d %H:%M:%f', 'now'), date('now'), julianday('now') FROM t WHERE a <= 1";
  int ok = 1;
  for (int rep = 0; rep < 3; rep++) {
    sqlite3_stmt *s;
    if (rep) { sqlite3_prepare_v2(db, "SELECT a FROM t WHERE b = ?1 ORDER BY a DESC LIMIT 2", -1, &s, 0); sqlite3_bind_text(s, 1, "k3", -1, SQLITE_STATIC); while (sqlite3_step(s) == SQLITE_ROW) {} sqlite3_finalize(s); }
    sqlite3_prepare_v2(db, q, -1, &s, 0);
    while (sqlite3_step(s) == SQLITE_ROW) if (sqlite3_column_double(s, 3) < 2459000.5) { ok = 0; fprintf(stderr, "DIFF julianday('now') served as %f (%s)\n", sqlite3_column_double(s, 3), sqlite3_column_text(s, 1)); }
    sqlite3_finalize(s);
  }
  return ok;
}
/* statements whose plan looks at a binding (expmask), one handle rebound again and again, against SQLite alone: a GLOB
   prefix (baked into SQLite's program: the QPSG program differs, and is dropped), a bound LIMIT and a bound 0/1 (the
   QPSG program is the same, kept: no more re-prepares) */
static u64 qp_run(sqlite3_stmt *s, const char *g, int lim, int b01) {
  sqlite3_reset(s); sqlite3_bind_text(s, 1, g, -1, SQLITE_TRANSIENT); sqlite3_bind_int(s, 2, lim); sqlite3_bind_int(s, 3, b01);
  u64 h = 1469598103934665603ULL; int rc;
  while ((rc = sqlite3_step(s)) == SQLITE_ROW)
    for (int c = 0; c < sqlite3_column_count(s); c++) { const unsigned char *z = sqlite3_column_text(s, c); h = hi(h, sqlite3_column_type(s, c)); if (z) h = hb(h, z, sqlite3_column_bytes(s, c)); }
  return hi(h, rc);
}
static int qpsg_ok(sqlite3 *db) {
  static const char *Q[] = {"SELECT a, b FROM t WHERE b GLOB ?1 ORDER BY b, a LIMIT ?2", "SELECT a, c FROM t WHERE b = ?1 AND (a % 2) = ?3 LIMIT ?2",
                            "SELECT t.a, u.y FROM t JOIN u ON u.x = t.a WHERE (u.y % 2) = ?3 AND t.b >= ?1 ORDER BY t.a LIMIT ?2"};
  static const char *G[] = {"k1*", "k3zz*", "k*", "zz*", "k5", "k1"};
  int bad = 0;
  for (int q = 0; q < 3; q++) {
    sqlite3_stmt *s1, *s2; sqlite3_prepare_v2(db, Q[q], -1, &s1, 0); sqlite3_prepare_v2(db, Q[q], -1, &s2, 0);
    for (int it = 0; it < 60; it++) {
      const char *g = G[it % 6]; int lim = (it * 7) % 13 - 1, b01 = it % 3;
      sqlite3_qc_serve(1); u64 h1 = qp_run(s1, g, lim, b01);
      sqlite3_qc_serve(0); u64 h2 = qp_run(s2, g, lim, b01);
      if (h1 != h2) { bad++; fprintf(stderr, "DIFF rebound %s: ?1=%s ?2=%d ?3=%d\n", Q[q], g, lim, b01); }
    }
    sqlite3_finalize(s1); sqlite3_finalize(s2);
  }
  sqlite3_qc_serve(1); return !bad;
}
/* finalized statements' plans, kept in the plan cache, hold none of the connection's lookaside slots (bench's corpus,
   2026-10-28: 116 slots held after vaultwarden's statements, stock 6, and SQLite's own prepares went to malloc) */
static int lookaside_ok(sqlite3 *db) {
  int cur0 = 0, cur = 0, hi = 0;
  sqlite3_db_status(db, SQLITE_DBSTATUS_LOOKASIDE_USED, &cur0, &hi, 0);
  for (int q = 0; q < NQ; q++) for (int k = 0; k < 2; k++) { int r; run(db, QS[q], 100 + q, "%k3%", -1, &r, 0, 0); }
  sqlite3_db_status(db, SQLITE_DBSTATUS_LOOKASIDE_USED, &cur, &hi, 0);
  if (cur > cur0) { fprintf(stderr, "DIFF lookaside: %d slots held after %d statements, %d before\n", cur, NQ, cur0); return 0; }
  return 1;
}
int main(int argc, char **argv) {
  int N = argc > 1 ? atoi(argv[1]) : 3000; if (argc > 2) rs ^= (u64)strtoull(argv[2], 0, 10) * 0x9e3779b97f4a7c15ULL;
  const char *path = "build/serve.db"; remove(path);
  sqlite3 *db; if (sqlite3_open(path, &db) != SQLITE_OK) return 2;
  ex(db, "CREATE TABLE t(a INTEGER PRIMARY KEY, b TEXT, c REAL); CREATE TABLE u(x INT, y INT); CREATE INDEX ux ON u(x); CREATE INDEX tb ON t(b); CREATE TABLE w(k INT, v TEXT)");
  ex(db, "BEGIN");
  for (int i = 1; i <= 600; i++) { char q[160]; snprintf(q, sizeof q, "INSERT INTO t VALUES (%d, 'k%d%s', %d.25)", i, i % 9, i % 4 ? "" : "zz", i % 31); ex(db, q); }
  for (int i = 0; i < 900; i++) { char q[96]; snprintf(q, sizeof q, "INSERT INTO u VALUES (%d, %d)", i % 400, i % 53); ex(db, q); }
  ex(db, "COMMIT");
  if (sqlite3_open(path, &db2) != SQLITE_OK) return 2;
  long cmp = 0, diffs = 0, served0 = 0;
  sqlite3_qc_serve(1); if (!now_ok(db)) diffs++; if (!qpsg_ok(db)) diffs++; if (!lookaside_ok(db)) diffs++;
  for (int it = 0; it < N; it++) {
    int q = (int)(rnd() % NQ); i64 p1 = (i64)(rnd() % 600); const char *p2 = rnd() % 2 ? "%k3%" : "k1%";
    int stop = rnd() % 4 == 0 ? (int)(rnd() % 5) : -1, fin = rnd() % 2, nested = rnd() % 6 == 0 ? 1 + (int)(rnd() % 2) : 0, txn = rnd() % 3 == 0;
    if (rnd() % 200 == 0) { char a[64]; snprintf(a, sizeof a, "ALTER TABLE t ADD COLUMN d%d INT DEFAULT %d", it, it); ex(db, a); }
    int r1, r2; u64 h1, h2;
    sqlite3_qc_serve(1); if (txn) ex(db, "BEGIN"); h1 = run(db, QS[q], p1, p2, stop, &r1, fin, nested); if (txn) ex(db, "COMMIT");
    sqlite3_qc_serve(0); if (txn) ex(db, "BEGIN"); h2 = run(db, QS[q], p1, p2, stop, &r2, fin, nested); if (txn) ex(db, "COMMIT");
    cmp++;
    if (!sqlite3_get_autocommit(db)) { diffs++; fprintf(stderr, "DIFF a transaction left open: %s\n", QS[q]); ex(db, "ROLLBACK"); }
    if (sqlite3_txn_state(db, 0) != SQLITE_TXN_NONE || sqlite3_txn_state(db2, 0) != SQLITE_TXN_NONE) { diffs++; fprintf(stderr, "DIFF a read transaction left open: %s\n", QS[q]); }
    if (h1 != h2 || r1 != r2) { diffs++; fprintf(stderr, "DIFF %s ?1=%lld stop %d fin %d nested %d txn %d: served %d rows, SQLite %d\n", QS[q], (long long)p1, stop, fin, nested, txn, r1, r2); }
  }
  (void)served0;
  printf("serve: %ld compared, %ld differences\n", cmp, diffs);
  sqlite3_close(db2); sqlite3_close(db); remove(path); sqlite3_qc_release();
  return diffs ? 1 : 0;
}
