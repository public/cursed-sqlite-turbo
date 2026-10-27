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
**   Q <name> <rows> <hash> <first-ms> <median-ms> <min-ms> <runs> <tier> <why> <sqlite-runs> <mean-ms> <instr> <cycles>
** mean-ms: over the repeated executions; instr, cycles: user-mode instructions and cycles per repeated execution
** (QRUN_PERF=1, Linux perf_event_open, which needs perf_event_paranoid <= 2 or root; -1 without).
** QRUN_TXN=1: each query's repeated executions run inside one BEGIN ... COMMIT (otherwise autocommit).
** QRUN_DIRECT=1 (a turbo build): through qc's embedded API, not sqlite3_step (run_direct below).
** tier: which executor ran the last execution (the serve build only; bench/qc_serve.c): 1 specialised plan, 2 loop
** plan, 3 qvm, 0 SQLite (why: qc's refusal or fallback reason); sqlite-runs: how many executions SQLite ran (refused
** or fallen back). "ERR" lines carry SQLite's error. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "sqlite3.h"
#include <unistd.h>
#ifdef __linux__
#include <linux/perf_event.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

__attribute__((weak)) int qcs_info(sqlite3_stmt *, const char **);
/* QRUN_DIRECT=1 (a turbo build): qc's embedded API instead of sqlite3_step, as an application written for it would
   call it: sqlite3_qc once, then sqlite3_qc_exec with a row callback, inside a transaction (in autocommit, a BEGIN
   and COMMIT prepared once, around each execution; with QCS_NOTXN=1, none: sqlite3_qc_exec opens the read
   transaction itself). A fallback steps the statement. The layout is qc.c's QcVal. */
typedef struct QrVal { union { sqlite3_int64 i; double r; const unsigned char *z; }; int n, type; } QrVal;
__attribute__((weak)) int sqlite3_qc(sqlite3_stmt *);
__attribute__((weak)) int sqlite3_qc_exec(sqlite3_stmt *, int (*)(void *, int, int, const QrVal *), void *);

static double now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }
static unsigned long long fnv(unsigned long long h, const void *p, size_t n) {
  const unsigned char *c = p; for (size_t i = 0; i < n; i++) h = (h ^ c[i]) * 1099511628211ULL; return h;
}
static int cmpd(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }

/* QRUN_PERF=1: user-mode instructions and cycles, counted around each repeated execution */
static int perf_fd[2] = { -1, -1 };
static void perf_open(void) {
#ifdef __linux__
  static const unsigned long long cfg[2] = { PERF_COUNT_HW_INSTRUCTIONS, PERF_COUNT_HW_CPU_CYCLES };
  for (int i = 0; i < 2; i++) {
    struct perf_event_attr a; memset(&a, 0, sizeof a);
    a.size = sizeof a; a.type = PERF_TYPE_HARDWARE; a.config = cfg[i]; a.disabled = 1; a.exclude_kernel = 1; a.exclude_hv = 1;
    perf_fd[i] = (int)syscall(SYS_perf_event_open, &a, 0, -1, -1, 0);
    if (perf_fd[i] < 0) { fprintf(stderr, "qrun: perf_event_open: counters unavailable\n"); perf_fd[0] = perf_fd[1] = -1; return; }
  }
#endif
}
static void perf_on(int on) {
#ifdef __linux__
  for (int i = 0; i < 2; i++) if (perf_fd[i] >= 0) ioctl(perf_fd[i], on ? PERF_EVENT_IOC_ENABLE : PERF_EVENT_IOC_DISABLE, 0);
#endif
}
static long long perf_read(int i) { long long v = -1; if (perf_fd[i] >= 0 && read(perf_fd[i], &v, sizeof v) != sizeof v) v = -1; return v; }
static void perf_reset(void) {
#ifdef __linux__
  for (int i = 0; i < 2; i++) if (perf_fd[i] >= 0) ioctl(perf_fd[i], PERF_EVENT_IOC_RESET, 0);
#endif
}

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

typedef struct DirectCtx { long rows; unsigned long long h; } DirectCtx;
static int direct_cb(void *ctx, int nrow, int ncol, const QrVal *v) {   /* the same hash run() computes */
  DirectCtx *c = ctx;
  for (int r = 0; r < nrow; r++, c->rows++)
    for (int i = 0; i < ncol; i++) {
      const QrVal *x = &v[r * ncol + i]; int t = x->type; c->h = fnv(c->h, &t, sizeof t);
      if (t == SQLITE_INTEGER) c->h = fnv(c->h, &x->i, sizeof x->i);
      else if (t == SQLITE_FLOAT) c->h = fnv(c->h, &x->r, sizeof x->r);
      else if (t == SQLITE_TEXT || t == SQLITE_BLOB) c->h = fnv(c->h, x->z, (size_t)x->n);
    }
  return SQLITE_OK;
}
static sqlite3_stmt *d_begin, *d_commit; static int d_fb;
static int run_direct(sqlite3 *db, sqlite3_stmt *st, long *rows, unsigned long long *hash) {
  static int notxn = -1; if (notxn < 0) notxn = getenv("QCS_NOTXN") != 0;
  int ac = sqlite3_get_autocommit(db) && !notxn;
  if (ac) { if (!d_begin) { sqlite3_prepare_v2(db, "BEGIN", -1, &d_begin, 0); sqlite3_prepare_v2(db, "COMMIT", -1, &d_commit, 0); }
            sqlite3_step(d_begin); sqlite3_reset(d_begin); }
  DirectCtx c = { 0, 1469598103934665603ULL };
  int rc = sqlite3_qc_exec(st, direct_cb, &c);
  if (ac) { sqlite3_step(d_commit); sqlite3_reset(d_commit); }
  if (rc == SQLITE_OK) { *rows = c.rows; *hash = c.h; return SQLITE_OK; }
  d_fb++; return run(st, rows, hash);   /* (QC_FALLBACK or an error: SQLite runs it, and reports any error) */
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
  if (getenv("QRUN_PERF")) perf_open();
  int direct = getenv("QRUN_DIRECT") && sqlite3_qc && sqlite3_qc_exec;
  if (getenv("QRUN_DIRECT") && !direct) { fprintf(stderr, "qrun: QRUN_DIRECT needs a turbo build\n"); return 2; }
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
    double *t = malloc(sizeof *t * (size_t)(reps > 0 ? reps : 1)); int nt = 0; long rows = 0, r2; unsigned long long hash = 0, h2; int rc = 0;
    int lifted = direct ? sqlite3_qc(st) : 0; d_fb = 0;
    #define RUN(r, h) (direct && lifted ? run_direct(db, st, r, h) : run(st, r, h))
    double t0 = now_ms(); rc = RUN(&rows, &hash); double first = now_ms() - t0, spent = first;
    int tier = 0, fb = 0; const char *why = "";
    if (qcs_info) { tier = qcs_info(st, &why); fb += !tier; }
    int txn = getenv("QRUN_TXN") != 0;   /* QRUN_TXN=1: the repeated executions inside one transaction */
    if (txn) sqlite3_exec(db, "BEGIN", 0, 0, 0);
    perf_reset();
    for (int k = 0; rc == SQLITE_OK && k < reps && spent < budget; k++) {
      perf_on(1); t0 = now_ms(); rc = RUN(&r2, &h2); t[nt] = now_ms() - t0; perf_on(0); spent += t[nt++];
      if (qcs_info) fb += !qcs_info(st, 0);
      if (rc == SQLITE_OK && (r2 != rows || h2 != hash)) { printf("ERR\t%s\texecutions disagree: %ld rows %016llx vs %ld rows %016llx\n", name, rows, hash, r2, h2); bad = 1; }
    }
    if (txn) sqlite3_exec(db, "COMMIT", 0, 0, 0);
    if (rc != SQLITE_OK) { printf("ERR\t%s\tstep: %s\n", name, sqlite3_errmsg(db)); bad = 1; sqlite3_finalize(st); free(t); p = next; continue; }
    if (qcs_info) tier = qcs_info(st, &why);
    if (direct) { tier = lifted && d_fb <= nt ? 3 : 0; fb = d_fb; why = lifted ? (d_fb ? "fallback" : "-") : "not lifted"; }   /* (direct: 3 = qc ran it) */
    double sum = 0; for (int k = 0; k < nt; k++) sum += t[k];
    long long ins = perf_read(0), cyc = perf_read(1);
    qsort(t, (size_t)nt, sizeof *t, cmpd);
    printf("Q\t%s\t%ld\t%016llx\t%.4f\t%.4f\t%.4f\t%d\t%d\t%s\t%d\t%.5f\t%.1f\t%.1f\n", name, rows, hash, first, nt ? t[nt / 2] : first,
           nt ? t[0] : first, nt + 1, tier, tier ? "-" : (why && *why ? why : "-"), fb, nt ? sum / nt : first,
           ins >= 0 && nt ? (double)ins / nt : -1.0, cyc >= 0 && nt ? (double)cyc / nt : -1.0);
    free(t);
    fflush(stdout);
    sqlite3_finalize(st);
    p = next;
  }
  sqlite3_finalize(d_begin); sqlite3_finalize(d_commit);
  sqlite3_close(db);
  return bad;
}
