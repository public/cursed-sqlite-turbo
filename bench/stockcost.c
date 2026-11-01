// stockcost <db> <feed|get> <json|rows|interp> <n> [txn]: n executions of the feed (20 rows) or a post by id, the
// queries of qbench (the spec's), for callgrind: run at two n, and (total(B) - total(A)) / (B - A) is one execution's
// cost, the prepare and the lift cancelling. The same file builds patched and with -DQC_STOCK=1 (make stock-bench).
//   json    sqlite3_qc_exec writing the JSON body; rows: with a row callback; interp: sqlite3_step + sqlite3_column_*
//   txn     executions per transaction (default 1: autocommit, one read per request, as the server runs them)
// After 200 untimed executions (a constant: callgrind's difference cancels it), prints the n executions' µs each.
#include "sqlite3.c"
#include "qc.c"
#if QC_STOCK
#define sqlite3_finalize sqlite3_qc_finalize
#endif
#include <stdlib.h>
#include <time.h>
static double now_us(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e6 + t.tv_nsec / 1e3; }
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
  if (argc < 5) { fprintf(stderr, "usage: stockcost <db> <feed|get> <json|rows|interp> <n> [txn]\n"); return 2; }
  int get = !strcmp(argv[2], "get"), m = !strcmp(argv[3], "interp") ? 0 : !strcmp(argv[3], "rows") ? 1 : 2;
  long n = atol(argv[4]); int txn = argc > 5 ? atoi(argv[5]) : 1;
  sqlite3 *db; if (sqlite3_open_v2(argv[1], &db, SQLITE_OPEN_READWRITE, 0)) return 1;
  sqlite3_exec(db, "PRAGMA cache_size=-16384", 0, 0, 0);
  i64 ids[20]; int nid = 0;
  { sqlite3_stmt *s; sqlite3_prepare_v2(db, "SELECT p.id FROM posts p ORDER BY p.created_at DESC, p.id DESC LIMIT 20", -1, &s, 0);
    while (sqlite3_step(s) == SQLITE_ROW && nid < 20) ids[nid++] = sqlite3_column_int64(s, 0); sqlite3_finalize(s); }
  sqlite3_stmt *s; sqlite3_prepare_v3(db, get ? QG : QF, -1, SQLITE_PREPARE_PERSISTENT, &s, 0);
  if (m && (!sqlite3_qc(s) || !sqlite3_qc_json(s, get ? &JG : &JF))) { fprintf(stderr, "not compiled (%s)\n", qc_why); return 1; }
  long fb = 0; double t0 = 0;
  for (long i = -200; i < n; i++) {
    if (i == 0) t0 = now_us();
    if (txn > 1 && i >= 0 && i % txn == 0) sqlite3_exec(db, "BEGIN", 0, 0, 0);
    i64 id = ids[(i + 200) % nid];
    if (get) sqlite3_bind_int64(s, 1, id);
    if (m == 0) interp(s);
    else if (m == 1) { if (sqlite3_qc_exec(s, rows_cb, 0) != SQLITE_OK) { fb++; interp(s); } }
    else { QcOut o = {buf, sizeof buf, 0, 0, get ? &id : 0, get}; if (sqlite3_qc_exec(s, 0, &o) == SQLITE_OK) sink += o.n; else { fb++; interp(s); } }
    if (txn > 1 && i >= 0 && (i % txn == txn - 1 || i == n - 1)) sqlite3_exec(db, "COMMIT", 0, 0, 0);
  }
  double us = n ? (now_us() - t0) / (double)n : 0;
  sqlite3_finalize(s); sqlite3_close(db);
  printf("stockcost: %s %s %ld runs (%d per transaction), %ld fell back, %.3f us each\n", argv[2], argv[3], n, txn, fb, us);
  return 0;
}
