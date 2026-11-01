// qbench <db> [rounds]: interpreter vs qc on the two example queries, µs per execution (16 per transaction, median
// of N interleaved rounds, hot cache):
//   interp   sqlite3_step + sqlite3_column_* for every value
//   qc rows  sqlite3_qc_exec with a callback (zero-copy values)
//   qc json  sqlite3_qc_exec writing the JSON body from a template
#include "sqlite3.c"
#include "qc.c"
#if QC_STOCK   /* (stock SQLite: no hook frees a statement's plan with it) */
#define sqlite3_finalize sqlite3_qc_finalize
#endif
#include <stdlib.h>
#include <time.h>
static double now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e9 + t.tv_nsec; }
static int cmpd(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }
static volatile size_t sink;
static char buf[1 << 16];
static const char *QF = "SELECT p.id, p.body, p.created_at, u.username, (SELECT count(*) FROM likes l WHERE l.post_id = p.id) "
                        "FROM posts p JOIN users u ON u.id = p.user_id ORDER BY p.created_at DESC, p.id DESC LIMIT 20";
static const char *QG = "SELECT p.id, p.body, p.created_at, u.username, (SELECT count(*) FROM likes l WHERE l.post_id = p.id) "
                        "FROM posts p JOIN users u ON u.id = p.user_id WHERE p.id = ?1";
static const QcJson JF = {"{\"posts\":[", "]}", ",", 5, "isssi", {"{\"id\":", ",\"body\":", ",\"created_at\":", ",\"author\":", ",\"like_count\":", "}"}};
static const QcJson JG = {"{\"post\":", "}", ",", 5, "isssi", {"{\"id\":", ",\"body\":", ",\"created_at\":", ",\"author\":", ",\"like_count\":", "}"}};
static int rows_cb(void *ctx, int nrow, int ncol, const QcVal *v) { size_t s = 0; for (int i = 0; i < nrow * ncol; i++) s += (size_t)v[i].n; sink += s; (void)ctx; return 0; }
static void interp(sqlite3_stmt *s) {
  while (sqlite3_step(s) == SQLITE_ROW) for (int c = 0; c < 5; c++) sink += (size_t)sqlite3_column_bytes(s, c) + (size_t)sqlite3_column_text(s, c)[0];
  sqlite3_reset(s);
}
int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: qbench <db> [rounds]\n"); return 2; }
  int R = argc > 2 ? atoi(argv[2]) : 9;
  sqlite3 *db; if (sqlite3_open(argv[1], &db)) return 1;
  sqlite3_exec(db, "PRAGMA cache_size=-16384; PRAGMA locking_mode=EXCLUSIVE", 0, 0, 0);
  sqlite3_stmt *f[2], *g[2];
  for (int k = 0; k < 2; k++) { sqlite3_prepare_v3(db, QF, -1, SQLITE_PREPARE_PERSISTENT, &f[k], 0); sqlite3_prepare_v3(db, QG, -1, SQLITE_PREPARE_PERSISTENT, &g[k], 0); }
  if (!sqlite3_qc(f[1]) || !sqlite3_qc(g[1]) || !sqlite3_qc_json(f[1], &JF) || !sqlite3_qc_json(g[1], &JG)) { fprintf(stderr, "not compiled (%s)\n", qc_why); return 1; }
  sqlite3_exec(db, "BEGIN", 0, 0, 0); i64 ids[20]; int n = 0;
  { sqlite3_stmt *s; sqlite3_prepare_v2(db, "SELECT p.id FROM posts p ORDER BY p.created_at DESC, p.id DESC LIMIT 20", -1, &s, 0);
    while (sqlite3_step(s) == SQLITE_ROW && n < 20) ids[n++] = sqlite3_column_int64(s, 0); sqlite3_finalize(s); }
  sqlite3_exec(db, "COMMIT", 0, 0, 0);
  printf("| query | interp µs | qc rows µs | qc json µs | qc json vs interp |\n|---|---:|---:|---:|---:|\n");
  for (int which = 0; which < 2; which++) {
    double t[3][64]; int it = which ? 32000 : 4000;
    for (int r = 0; r < R + 1; r++) for (int m = 0; m < 3; m++) {
      double t0 = now_ns();
      for (int i = 0; i < it; i += 16) {
        sqlite3_exec(db, "BEGIN", 0, 0, 0);
        for (int k = 0; k < 16; k++) {
          i64 id = ids[(i + k) % n];
          sqlite3_stmt *s = which ? g[m ? 1 : 0] : f[m ? 1 : 0];
          if (which && m == 0) sqlite3_bind_int64(s, 1, id);
          if (m == 0) interp(s);
          else if (m == 1) { if (which) sqlite3_bind_int64(s, 1, id); if (sqlite3_qc_exec(s, rows_cb, 0) != SQLITE_OK) interp(s); }
          else { QcOut o = {buf, sizeof buf, 0, 0, which ? &id : 0, which}; if (sqlite3_qc_exec(s, 0, &o) == SQLITE_OK) sink += o.n; else interp(s); }
        }
        sqlite3_exec(db, "COMMIT", 0, 0, 0);
      }
      if (r) t[m][r - 1] = (now_ns() - t0) / it / 1000;
    }
    for (int m = 0; m < 3; m++) qsort(t[m], R, sizeof(double), cmpd);
    printf("| %s | %.3f | %.3f | %.3f | %+.0f %% |\n", which ? "post by id" : "feed (20 rows)", t[0][R / 2], t[1][R / 2], t[2][R / 2], 100 * (t[2][R / 2] / t[0][R / 2] - 1));
  }
  return 0;
}
