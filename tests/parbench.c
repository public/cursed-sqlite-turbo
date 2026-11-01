// parbench db [rows] [runs]: filtered count / sum scans through sqlite3_step, served by turbo (QC_SERVE=1, the default
// here) or not (QC_SERVE=0), with QV_PAR helper threads or none. Builds db (a 5-column integer table, cached in full)
// when it has no table t. Each statement is prepared once and run `runs` times; prints the median of the second half,
// in ms, and checks every result against the first run's.
#include "sqlite3.c"
#include "qc.c"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static double now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }
static void ex(sqlite3 *db, const char *q) { char *e = 0; if (sqlite3_exec(db, q, 0, 0, &e)) { fprintf(stderr, "%s: %s\n", q, e); exit(2); } }
static int dcmp(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }
int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "parbench db [rows] [runs]\n"); return 2; }
  int rows = argc > 2 ? atoi(argv[2]) : 2000000, runs = argc > 3 ? atoi(argv[3]) : 40;
  sqlite3_qc_serve(getenv("QC_SERVE") ? atoi(getenv("QC_SERVE")) : 1);
  sqlite3 *db; sqlite3_open(argv[1], &db);
  ex(db, "PRAGMA cache_size=-1000000");
  sqlite3_stmt *s;
  sqlite3_prepare_v2(db, "SELECT count(*) FROM sqlite_schema WHERE name = 't'", -1, &s, 0); sqlite3_step(s);
  int have = sqlite3_column_int(s, 0); sqlite3_finalize(s);
  if (!have) {
    ex(db, "CREATE TABLE t(a INTEGER PRIMARY KEY, b INT, c INT, d INT, e TEXT)");
    char q[256]; snprintf(q, sizeof q, "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < %d) "
                                       "INSERT INTO t SELECT i, abs(random()) %% 100, abs(random()) %% 1000, (abs(random()) %% 2001) - 1000, 'e' || (i %% 7) FROM n", rows);
    ex(db, q);
  }
  ex(db, "SELECT count(e) FROM t");   /* (every page in the cache) */
  static const char *Q[] = {
    "SELECT count(*) FROM t WHERE b > 50",
    "SELECT sum(c) FROM t WHERE b < 30",
    "SELECT avg(b), count(c) FROM t WHERE c >= 500 AND b > 10",
    "SELECT total(c) FROM t WHERE a > 1000",
    "SELECT count(*) FROM t WHERE b = 7",
    "SELECT sum(b) FROM t WHERE d < 0",
  };
  double *ms = malloc(sizeof *ms * (size_t)runs);
  for (size_t k = 0; k < sizeof Q / sizeof *Q; k++) {
    sqlite3_prepare_v2(db, Q[k], -1, &s, 0);
    char first[128] = "", cur[128];
    for (int r = 0; r < runs; r++) {
      double t0 = now_ms(); int n = 0;
      cur[0] = 0;
      while (sqlite3_step(s) == SQLITE_ROW) for (int c = 0; c < sqlite3_column_count(s); c++) n += snprintf(cur + n, sizeof cur - (size_t)n, "%s|", (const char *)sqlite3_column_text(s, c));
      sqlite3_reset(s); ms[r] = now_ms() - t0;
      if (r == 0) strcpy(first, cur); else if (strcmp(first, cur)) { fprintf(stderr, "DIFF %s: %s vs %s\n", Q[k], first, cur); return 1; }
    }
    sqlite3_finalize(s);
    qsort(ms + runs / 2, (size_t)(runs - runs / 2), sizeof *ms, dcmp);
    printf("%8.3f ms  %s  = %s\n", ms[runs / 2 + (runs - runs / 2) / 2], Q[k], first);
  }
  sqlite3_close(db); return 0;
}
