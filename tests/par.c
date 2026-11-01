// par [iterations] [seed]: qvm's scans on helper threads (QV_PAR, qvm_par.h) against the interpreter. A table over many
// pages of integers and NULLs, with a few reals, texts, overflow records and sums near the int64 limits, so that pages
// miss and the loop goes on row by row from them; random filtered count / sum / total / avg statements, some with bound
// values (a NULL among them), others of shapes the helpers don't take. Each statement runs five times (its plan, its
// feedback, its regions with and without the helpers); every result must equal the interpreter's, value by value.
// Rows change between rounds. Run with QV_PAR=n; prints how many loops went to the helpers.
#include "sqlite3.c"
#include "qc.c"
#include <stdio.h>
#include <stdlib.h>
static u64 rs = 88172645463325252ULL;
static u64 rnd(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }
static u64 hv(u64 h, int t, const void *z, int n, i64 iv, double rv) {
  h = (h ^ (unsigned)t) * 1099511628211ULL;
  if (t == SQLITE_INTEGER) { for (int k = 0; k < 8; k++) h = (h ^ ((u64)iv >> (8 * k) & 255)) * 1099511628211ULL; }
  else if (t == SQLITE_FLOAT) { u64 b; memcpy(&b, &rv, 8); for (int k = 0; k < 8; k++) h = (h ^ (b >> (8 * k) & 255)) * 1099511628211ULL; }
  else if (t == SQLITE_TEXT || t == SQLITE_BLOB) for (int k = 0; k < n; k++) h = (h ^ ((const u8 *)z)[k]) * 1099511628211ULL;
  return h;
}
typedef struct { u64 h; int rows; } Acc;
static int cb(void *ctx, int nrow, int ncol, const QcVal *v) { Acc *a = ctx; a->h = 1469598103934665603ULL; a->rows = nrow; for (int i = 0; i < nrow * ncol; i++) a->h = hv(a->h, v[i].type, v[i].z, v[i].n, v[i].i, v[i].r); return 0; }
static void ex(sqlite3 *db, const char *q) { char *e = 0; if (sqlite3_exec(db, q, 0, 0, &e)) { fprintf(stderr, "%s: %s\n", q, e); exit(2); } }
static void fill(sqlite3 *db, int from, int to) {
  ex(db, "BEGIN");
  for (int i = from; i <= to; i++) {
    char q[256], d[64]; int k = (int)(rnd() % 1000);
    if (k == 0) snprintf(d, sizeof d, "%.3f", (double)(rnd() % 1000) / 7);   /* a real: the page misses for d */
    else if (k == 1) snprintf(d, sizeof d, "'x%d'", (int)(rnd() % 9));       /* text */
    else snprintf(d, sizeof d, "%d", (int)(rnd() % 100000) - 50000);
    long long c = rnd() % 50 == 0 ? (long long)(rnd() >> 2) * (rnd() % 2 ? 1 : -1) : (long long)(rnd() % 1000);   /* a few near 2^62 */
    snprintf(q, sizeof q, "INSERT INTO t VALUES (%d, %s, %lld, %s, %s)", i, rnd() % 10 ? "abs(random()) % 100" : "NULL", c, d,
             rnd() % 400 == 0 ? "printf('%.5000c', 'z')" : rnd() % 3 ? "'e'" : "NULL");   /* (5000 bytes: an overflow record) */
    ex(db, q);
  }
  ex(db, "COMMIT");
}
int main(int argc, char **argv) {
  int N = argc > 1 ? atoi(argv[1]) : 300; if (argc > 2) rs ^= (u64)strtoull(argv[2], 0, 10) * 0x9e3779b97f4a7c15ULL;
  const char *path = getenv("PAR_DB") ? getenv("PAR_DB") : ":memory:"; sqlite3 *db;
  if (strcmp(path, ":memory:")) remove(path);
  sqlite3_open(path, &db);
  if (getenv("PAR_CACHE")) { char q[64]; snprintf(q, sizeof q, "PRAGMA cache_size=%s", getenv("PAR_CACHE")); ex(db, q); }
  ex(db, "CREATE TABLE t(a INTEGER PRIMARY KEY, b INT, c INT, d, e TEXT)");
  int rows = 40000; fill(db, 1, rows);
  static const char *sel[] = {"count(*)", "sum(b)", "sum(c)", "total(b), count(b)", "avg(c), count(*)", "sum(d)", "sum(b), sum(c), count(c)", "count(d), total(c)", "b, sum(c)", "count(*), c, a"};   /* (the last two: bare columns, the last row's) */
  static const char *wh[] = {"b > %d", "b <= %d", "c < %d AND b >= 3", "a > %d", "b = %d", "b != %d", "a < %d AND b > 10", "c >= %d", "%d < b",
                             "e IS NULL AND b > %d", "b > %d OR c < 5", "abs(b) > %d", "b > ?1", "a >= ?1 AND c < ?2"};   /* (the last five: not the helpers') */
  long cmp = 0, fell = 0, diffs = 0;
  for (int it = 0; it < N; it++) {
    char w[128], q[256]; int k = (int)(rnd() % 100);
    snprintf(w, sizeof w, wh[rnd() % 14], it % 7 == 0 ? (int)(rnd() % rows) : k);
    snprintf(q, sizeof q, "SELECT %s FROM t WHERE %s", sel[rnd() % 10], w);
    sqlite3_stmt *s, *p; Acc a = {0, -1}, b = {1469598103934665603ULL, 0};
    if (sqlite3_prepare_v2(db, q, -1, &s, 0) || sqlite3_prepare_v2(db, q, -1, &p, 0)) { fprintf(stderr, "prepare %s: %s\n", q, sqlite3_errmsg(db)); return 2; }
    int lifted = 0;
    for (int rep = 0; rep < 5; rep++) {
      for (int x = 1; x <= 2; x++) {   /* bound values: a NULL now and then (the helpers leave the loop row by row) */
        if (rnd() % 8 == 0) { sqlite3_bind_null(s, x); sqlite3_bind_null(p, x); }
        else { int v = (int)(rnd() % 100); sqlite3_bind_int(s, x, v); sqlite3_bind_int(p, x, v); }
      }
      ex(db, "BEGIN"); int rc = QC_FALLBACK, prc; a.rows = -1;
      if (rep == 0) lifted = sqlite3_qc(s);
      if (lifted) rc = sqlite3_qc_exec(s, cb, &a);
      b.h = 1469598103934665603ULL; b.rows = 0;
      while ((prc = sqlite3_step(p)) == SQLITE_ROW) { b.rows++; for (int c = 0; c < sqlite3_column_count(p); c++) { int t = sqlite3_column_type(p, c);
        b.h = hv(b.h, t, t == SQLITE_TEXT ? (const void *)sqlite3_column_text(p, c) : sqlite3_column_blob(p, c), sqlite3_column_bytes(p, c), sqlite3_column_int64(p, c), sqlite3_column_double(p, c)); } }
      if (prc != SQLITE_DONE) b.rows = -prc;   /* (an error: integer overflow) */
      sqlite3_reset(p); sqlite3_reset(s); ex(db, "COMMIT");
      if (rc != SQLITE_OK) { fell++; if (getenv("PAR_WHY")) fprintf(stderr, "WHY %s | %s\n", qc_why, q); continue; }
      cmp++; if (a.h != b.h || a.rows != b.rows) { diffs++; fprintf(stderr, "DIFF %s: qc %d rows, interp %d\n", q, a.rows, b.rows); }
    }
    sqlite3_finalize(s); sqlite3_finalize(p);
    if (it % 50 == 49) {   /* rows change: updates, deletes, a few more misses */
      char u[160]; snprintf(u, sizeof u, "UPDATE t SET b = b + 1, d = CASE WHEN abs(random()) %% 500 = 0 THEN 'y' ELSE d END WHERE a %% %d = 0", 2 + (int)(rnd() % 9)); ex(db, u);
      snprintf(u, sizeof u, "DELETE FROM t WHERE a %% %d = 1", 50 + (int)(rnd() % 50)); ex(db, u);
      fill(db, rows + 1, rows + 2000); rows += 2000;
    }
  }
  printf("par: %ld compared, %ld fell back, %ld differences; on helpers %llu loops, %llu pages, %llu left row by row (%s, %d helpers)\n",
         cmp, fell, diffs, qcs.par, qcs.parPages, qcs.parMiss, qcf.par ? "on" : "off", qvp.n);
  sqlite3_close(db); return diffs != 0;
}
