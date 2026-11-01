// topn [iterations] [seed]: qvm's top-N sorter (ORDER BY ... LIMIT N as a sorted array) against the interpreter. Random
// ORDER BY ... LIMIT [OFFSET] queries over a table of NULLs, integers, reals and text: ASC/DESC, NULLS FIRST/LAST,
// a collation, ties, expressions, GROUP BY; LIMITs past QV_TOPN_MAX (the array moved into a B-tree). Each statement
// runs three times (its plan, its feedback, its regions); every result must equal the interpreter's, value by value.
// Build with -DQV_TOPN_MAX=4 to move into the B-tree on almost every run.
#include "sqlite3.c"
#include "qc.c"
#if QC_STOCK   /* (stock SQLite: no hook frees a statement's plan with it) */
#define sqlite3_finalize sqlite3_qc_finalize
#endif
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
int main(int argc, char **argv) {
  int N = argc > 1 ? atoi(argv[1]) : 2000; if (argc > 2) rs ^= (u64)strtoull(argv[2], 0, 10) * 0x9e3779b97f4a7c15ULL; sqlite3 *db; sqlite3_open(":memory:", &db);
  ex(db, "CREATE TABLE t(a INTEGER PRIMARY KEY, b, c TEXT, d REAL, e INT); CREATE INDEX tb ON t(b); CREATE INDEX te ON t(e)");
  ex(db, "BEGIN");
  for (int i = 1; i <= 3000; i++) {
    char q[256]; int k = (int)(rnd() % 10);
    const char *b = k == 0 ? "NULL" : k < 4 ? "'x'" : k < 7 ? "1" : "2.5";
    snprintf(q, sizeof q, "INSERT INTO t VALUES (%d, %s, %s, %s, %d)", i, b, rnd() % 7 ? "printf('s%d', abs(random()) % 50)" : "NULL",
             rnd() % 5 ? "(abs(random()) % 1000) / 7.0" : "NULL", (int)(rnd() % 30)); ex(db, q);
  }
  ex(db, "COMMIT");
  static const char *ord[] = {"c", "c DESC", "d", "d DESC, a", "b, c DESC", "e DESC, d", "c COLLATE NOCASE DESC", "b DESC NULLS LAST", "d NULLS FIRST, c", "length(c), a DESC", "e", "a DESC"};
  static const char *wh[] = {"1", "e = 3", "e < 10", "b IS NOT NULL", "c > 's2'", "d > 50", "e IN (1, 2, 5)", "a % 3 = 0"};
  long cmp = 0, fell = 0, diffs = 0;
  for (int it = 0; it < N; it++) {
    char q[512]; int lim = (int)(rnd() % 6 == 0 ? 200 + rnd() % 300 : rnd() % 30), off = rnd() % 3 ? 0 : (int)(rnd() % 40);
    const char *cols = rnd() % 2 ? "a, b, c, d, e" : "c, count(*) OVER (), a";
    if (rnd() % 3 == 0) cols = "a, c";
    snprintf(q, sizeof q, "SELECT %s FROM t WHERE %s ORDER BY %s LIMIT %d%s", cols, wh[rnd() % 8], ord[rnd() % 12], lim, off ? " OFFSET 7" : "");
    if (rnd() % 4 == 0) snprintf(q, sizeof q, "SELECT e, max(d), min(c) FROM t WHERE %s GROUP BY e ORDER BY %s LIMIT %d", wh[rnd() % 8], rnd() % 2 ? "2 DESC" : "3", lim);
    sqlite3_stmt *s, *p; Acc a = {0, -1}, b = {1469598103934665603ULL, 0};
    if (sqlite3_prepare_v2(db, q, -1, &s, 0) || sqlite3_prepare_v2(db, q, -1, &p, 0)) { fprintf(stderr, "prepare %s: %s\n", q, sqlite3_errmsg(db)); return 2; }
    int lifted = 0;
    for (int rep = 0; rep < 3; rep++) {   /* (several runs: the plan, its feedback, a deoptimisation) */
      ex(db, "BEGIN"); int rc = QC_FALLBACK; a.rows = -1;
      if (rep == 0) lifted = sqlite3_qc(s);
      if (lifted) rc = sqlite3_qc_exec(s, cb, &a);
      b.h = 1469598103934665603ULL; b.rows = 0;
      while (sqlite3_step(p) == SQLITE_ROW) { b.rows++; for (int c = 0; c < sqlite3_column_count(p); c++) { int t = sqlite3_column_type(p, c);
        b.h = hv(b.h, t, t == SQLITE_TEXT ? (const void *)sqlite3_column_text(p, c) : sqlite3_column_blob(p, c), sqlite3_column_bytes(p, c), sqlite3_column_int64(p, c), sqlite3_column_double(p, c)); } }
      sqlite3_reset(p); ex(db, "COMMIT");
      if (rc != SQLITE_OK) { fell++; if (getenv("TOPN_WHY")) fprintf(stderr, "WHY %s | %s\n", qc_why, q); continue; }
      cmp++; if (a.h != b.h || a.rows != b.rows) { diffs++; fprintf(stderr, "DIFF %s: qc %d rows, interp %d\n", q, a.rows, b.rows); }
    }
    sqlite3_finalize(s); sqlite3_finalize(p);
  }
  printf("topn: %ld compared, %ld fell back, %ld differences\n", cmp, fell, diffs);
  sqlite3_close(db); return diffs != 0;
}
