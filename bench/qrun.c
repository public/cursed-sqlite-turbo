/* qrun.c: run a file of named queries against a database and time them; linked with any bench/build-sqlite.sh variant.
**
**   qrun <db> <queries.sql> [reps] [budget-s]
**
** The file holds queries separated by lines "-- name: <name>" (anything before the first is ignored). Each query is
** prepared once and run 1 + reps times (all rows stepped, then reset); the first execution is reported apart (it
** includes qc's lift), the others by their median and minimum. A query whose executions pass budget-s seconds (default
** 60) in all stops repeating. Every execution's rows are hashed (type, then the exact integer, the double's bits or
** the bytes), and executions must agree with each other; arms are compared by bench/compare.py on the hashes.
** Output, one tab-separated line per query:
**   Q <name> <rows> <hash> <first-ms> <median-ms> <min-ms> <runs> <tier> <why> <sqlite-runs>
** tier: which executor ran the last execution (the serve build only; bench/qc_serve.c): 1 specialised plan, 2 loop
** plan, 3 qvm, 0 SQLite (why: qc's refusal or fallback reason); sqlite-runs: how many executions SQLite ran (refused
** or fallen back). "ERR" lines carry SQLite's error. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "sqlite3.h"

__attribute__((weak)) int qcs_info(sqlite3_stmt *, const char **);

static double now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }
static unsigned long long fnv(unsigned long long h, const void *p, size_t n) {
  const unsigned char *c = p; for (size_t i = 0; i < n; i++) h = (h ^ c[i]) * 1099511628211ULL; return h;
}
static int cmpd(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }

/* one execution: rows and their hash */
static int run(sqlite3_stmt *st, long *rows, unsigned long long *hash) {
  unsigned long long h = 1469598103934665603ULL; long n = 0; int rc;
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) {
    int nc = sqlite3_column_count(st);
    for (int i = 0; i < nc; i++) {
      int t = sqlite3_column_type(st, i); h = fnv(h, &t, sizeof t);
      if (t == SQLITE_INTEGER) { sqlite3_int64 v = sqlite3_column_int64(st, i); h = fnv(h, &v, sizeof v); }
      else if (t == SQLITE_FLOAT) { double v = sqlite3_column_double(st, i); h = fnv(h, &v, sizeof v); }
      else if (t == SQLITE_TEXT) { const unsigned char *z = sqlite3_column_text(st, i); h = fnv(h, z, (size_t)sqlite3_column_bytes(st, i)); }
      else if (t == SQLITE_BLOB) { const void *z = sqlite3_column_blob(st, i); h = fnv(h, z, (size_t)sqlite3_column_bytes(st, i)); }
    }
    n++;
  }
  sqlite3_reset(st);
  *rows = n; *hash = h;
  return rc == SQLITE_DONE ? SQLITE_OK : rc;
}

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: qrun <db> <queries.sql> [reps] [budget-s]\n"); return 2; }
  int reps = argc > 3 ? atoi(argv[3]) : 3; double budget = (argc > 4 ? atof(argv[4]) : 60) * 1e3;
  FILE *f = fopen(argv[2], "rb"); if (!f) { perror(argv[2]); return 1; }
  fseek(f, 0, SEEK_END); long L = ftell(f); fseek(f, 0, SEEK_SET);
  char *buf = malloc((size_t)L + 1); if (fread(buf, 1, (size_t)L, f) != (size_t)L) return 1; buf[L] = 0; fclose(f);
  sqlite3 *db;
  if (sqlite3_open_v2(argv[1], &db, SQLITE_OPEN_READWRITE, 0) != SQLITE_OK) { fprintf(stderr, "open %s: %s\n", argv[1], sqlite3_errmsg(db)); return 1; }
  const char *setup = getenv("QRUN_SETUP");   /* e.g. "PRAGMA cache_size=-1000000" */
  if (setup && sqlite3_exec(db, setup, 0, 0, 0) != SQLITE_OK) { fprintf(stderr, "setup: %s\n", sqlite3_errmsg(db)); return 1; }
  int bad = 0;
  for (char *p = strstr(buf, "-- name: "); p; ) {
    char *name = p + 9, *e = strchr(name, '\n'); if (!e) break; *e = 0;
    char *sql = e + 1, *next = strstr(sql, "-- name: "); if (next) next[-1] = 0;
    while (*name == ' ') name++;
    for (char *c = name + strlen(name); c > name && (c[-1] == '\r' || c[-1] == ' '); ) *--c = 0;
    sqlite3_stmt *st = 0; const char *tail = 0;
    if (sqlite3_prepare_v3(db, sql, -1, SQLITE_PREPARE_PERSISTENT, &st, &tail) != SQLITE_OK || !st) {
      printf("ERR\t%s\tprepare: %s\n", name, sqlite3_errmsg(db)); bad = 1; p = next; continue;
    }
    double t[1024]; int nt = 0; long rows = 0, r2; unsigned long long hash = 0, h2; int rc = 0;
    double t0 = now_ms(); rc = run(st, &rows, &hash); double first = now_ms() - t0, spent = first;
    int tier = 0, fb = 0; const char *why = "";
    if (qcs_info) { tier = qcs_info(st, &why); fb += !tier; }
    for (int k = 0; rc == SQLITE_OK && k < reps && k < 1024 && spent < budget; k++) {
      t0 = now_ms(); rc = run(st, &r2, &h2); t[nt] = now_ms() - t0; spent += t[nt++];
      if (qcs_info) fb += !qcs_info(st, 0);
      if (rc == SQLITE_OK && (r2 != rows || h2 != hash)) { printf("ERR\t%s\texecutions disagree: %ld rows %016llx vs %ld rows %016llx\n", name, rows, hash, r2, h2); bad = 1; }
    }
    if (rc != SQLITE_OK) { printf("ERR\t%s\tstep: %s\n", name, sqlite3_errmsg(db)); bad = 1; sqlite3_finalize(st); p = next; continue; }
    if (qcs_info) tier = qcs_info(st, &why);
    qsort(t, (size_t)nt, sizeof *t, cmpd);
    printf("Q\t%s\t%ld\t%016llx\t%.3f\t%.3f\t%.3f\t%d\t%d\t%s\t%d\n", name, rows, hash, first, nt ? t[nt / 2] : first,
           nt ? t[0] : first, nt + 1, tier, tier ? "-" : (why && *why ? why : "-"), fb);
    fflush(stdout);
    sqlite3_finalize(st);
    p = next;
  }
  sqlite3_close(db);
  return bad;
}
