/* corpus.c: the query corpus statements (bench/corpus/prep.py's <project>.q, from bench/corpus/projects) through SQLite's plain API, so
** the same program measures stock and turbo serving inside sqlite3_step (QC_SERVE=1, the native build).
**   corpus build <db> <project.build.sql>          make the database (run once, by the stock build; arms get copies)
**   corpus check <db> <project.q> [only-id]        each statement 6 times on one handle, then twice freshly prepared:
**        C id status rows changes hash msethash served/runs error       status ok | err | unstable (runs disagree)
**   corpus hot|prep <db> <project.q> [reps] [budget-ms] [only-id]   timing:
**        T id rows hash first-ms median-ms mean-ms runs instr cycles served/runs error
**     hot: prepared once, then 1 + reps executions (sqlite3_reset between); prep: every execution prepares, binds,
**     steps and finalizes. reps stop early when budget-ms is spent (at least 3). instr, cycles: user-mode, per
**     execution (Linux perf_event_open, -1 without).
**     After each T line: L <id> <lookaside slots in use> <lookaside misses (slot pool full) since the last L line>.
**     Built with -DCORPUS_CALLGRIND (run.sh cg) the counted regions are callgrind's instead: collection toggled on and
**     off around them, zeroed per statement, and dumped with the label "<id> <hot|prep> <executions>".
**   corpus explain <db> <project.q> [only-id]     EXPLAIN QUERY PLAN and EXPLAIN with the bindings bound (a plan that
**        looks at a binding is re-prepared with its value at the first step, as the statement itself is), first as
**        SQLite plans it, then under SQLITE_DBCONFIG_ENABLE_QPSG:  E id qpsg|plain plan|program <the row, tab-separated>
** Reads run in autocommit (the drop-in path); writes inside BEGIN ... ROLLBACK, outside the timed span, as
** tools/run.py runs them. hash: the rows in order; msethash: the rows as a multiset (statements without ORDER BY).
** CORPUS_ROWS=1 prints every row to stderr. served: executions that never stepped SQLite's VM (qc served them: SQLITE_STMTSTATUS_VM_STEP stays 0). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <regex.h>
#include "sqlite3.h"
#ifdef CORPUS_CALLGRIND   /* (run.sh cg: the counters are callgrind's, one dump per statement and mode, read by cg.py) */
#include <valgrind/callgrind.h>
#endif
#ifdef __linux__
#include <linux/perf_event.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#endif

static double now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }
static unsigned long long fnv(unsigned long long h, const void *p, size_t n) {
  const unsigned char *c = p; for (size_t i = 0; i < n; i++) h = (h ^ c[i]) * 1099511628211ULL; return h;
}
static int cmpd(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }

/* CORPUS_EXTRA=1: four more counters, and SQLite's allocation calls, over the same spans as instr and cycles: after each
** T line an X line, per execution:  X id cache-misses LLC-load-misses dTLB-load-misses page-faults allocs
** (user-mode hardware events; page faults counted in the kernel's handling of them too; allocs: sqlite3_malloc and
** sqlite3_realloc calls through SQLITE_CONFIG_MALLOC, so not a direct malloc by qc). -1 where unavailable. */
#define NPERF 6
static int perf_fd[NPERF] = { -1, -1, -1, -1, -1, -1 }, extra, counting;
static long long allocs;
static sqlite3_mem_methods mem0;
static void *count_malloc(int n) { if (counting) allocs++; return mem0.xMalloc(n); }
static void *count_realloc(void *p, int n) { if (counting) allocs++; return mem0.xRealloc(p, n); }
static void perf_open(void) {
#ifdef __linux__
  static const unsigned type[NPERF] = { PERF_TYPE_HARDWARE, PERF_TYPE_HARDWARE, PERF_TYPE_HARDWARE, PERF_TYPE_HW_CACHE,
                                        PERF_TYPE_HW_CACHE, PERF_TYPE_SOFTWARE };
  static const unsigned long long cfg[NPERF] = { PERF_COUNT_HW_INSTRUCTIONS, PERF_COUNT_HW_CPU_CYCLES, PERF_COUNT_HW_CACHE_MISSES,
    PERF_COUNT_HW_CACHE_LL | PERF_COUNT_HW_CACHE_OP_READ << 8 | PERF_COUNT_HW_CACHE_RESULT_MISS << 16,
    PERF_COUNT_HW_CACHE_DTLB | PERF_COUNT_HW_CACHE_OP_READ << 8 | PERF_COUNT_HW_CACHE_RESULT_MISS << 16,
    PERF_COUNT_SW_PAGE_FAULTS };
  for (int i = 0; i < (extra ? NPERF : 2); i++) {
    struct perf_event_attr a; memset(&a, 0, sizeof a);
    a.size = sizeof a; a.type = type[i]; a.config = cfg[i]; a.disabled = 1; a.exclude_kernel = i < 5; a.exclude_hv = 1;
    perf_fd[i] = (int)syscall(SYS_perf_event_open, &a, 0, -1, -1, 0);
    if (perf_fd[i] < 0 && i < 2) { fprintf(stderr, "corpus: perf_event_open: counters unavailable\n"); perf_fd[0] = perf_fd[1] = -1; return; }
    if (perf_fd[i] < 0) fprintf(stderr, "corpus: perf_event_open: extra counter %d unavailable\n", i);
  }
#endif
}
static void perf_on(int on) {
#ifdef CORPUS_CALLGRIND
  static int cg; if (on != cg) { CALLGRIND_TOGGLE_COLLECT; cg = on; }
#elif defined(__linux__)
  for (int i = 0; i < NPERF; i++) if (perf_fd[i] >= 0) ioctl(perf_fd[i], on ? PERF_EVENT_IOC_ENABLE : PERF_EVENT_IOC_DISABLE, 0);
  counting = on;
#else
  (void)on;
#endif
}
static long long perf_read(int i) { long long v = -1; if (perf_fd[i] >= 0 && read(perf_fd[i], &v, sizeof v) != sizeof v) v = -1; return v; }
static void perf_reset(void) {
#ifdef CORPUS_CALLGRIND
  CALLGRIND_ZERO_STATS;
#elif defined(__linux__)
  for (int i = 0; i < NPERF; i++) if (perf_fd[i] >= 0) ioctl(perf_fd[i], PERF_EVENT_IOC_RESET, 0);
#endif
  allocs = 0;
}

typedef struct Q { char *id; int ordered, write; char *tags; int np; char *pn[64], *pl[64]; char *sql; } Q;
typedef struct R { long rows, changes; unsigned long long h, hs; int served; char err[256]; } R;

static sqlite3 *db;
static sqlite3_stmt *s_begin, *s_rollback;
static sqlite3_value *pv[64];   /* the current statement's parameter values (each literal evaluated once) */

static void regex_free(void *p) { regfree(p); free(p); }
static void regexp_fn(sqlite3_context *c, int argc, sqlite3_value **v) {   /* X REGEXP Y = regexp(Y, X), as the CLI's (POSIX
                                                                          ** extended here: both arms run the same one) */
  (void)argc;
  const char *pat = (const char *)sqlite3_value_text(v[0]), *s = (const char *)sqlite3_value_text(v[1]);
  if (!pat || !s) return;
  regex_t *re = sqlite3_get_auxdata(c, 0);
  if (re) { sqlite3_result_int(c, regexec(re, s, 0, 0, 0) == 0); return; }
  re = malloc(sizeof *re);
  if (!re || regcomp(re, pat, REG_EXTENDED | REG_NOSUB)) { free(re); sqlite3_result_error(c, "regexp: bad pattern", -1); return; }
  sqlite3_result_int(c, regexec(re, s, 0, 0, 0) == 0);
  sqlite3_set_auxdata(c, 0, re, regex_free);   /* (kept across rows only for a constant pattern; freed at once otherwise) */
}

static char *slurp(const char *f) {
  FILE *fp = fopen(f, "rb"); if (!fp) { perror(f); exit(2); }
  fseek(fp, 0, SEEK_END); long n = ftell(fp); fseek(fp, 0, SEEK_SET);
  char *b = malloc((size_t)n + 1); if (fread(b, 1, (size_t)n, fp) != (size_t)n) { perror(f); exit(2); } b[n] = 0; fclose(fp); return b;
}
static char *pragma[16]; static int npragma;   /* the project's @@X lines: connection settings, run before the statements */
static int parse(char *b, Q **out) {   /* prep.py's format, in place */
  int n = 0, cap = 64; Q *q = malloc(sizeof *q * cap); char *p = b;
  while (*p) {
    char *nl = strchr(p, '\n'); if (nl) *nl = 0;
    if (!strncmp(p, "@@Q ", 4)) {
      if (n == cap) q = realloc(q, sizeof *q * (cap *= 2));
      Q *x = &q[n++]; memset(x, 0, sizeof *x);
      x->id = strtok(p + 4, " "); x->ordered = atoi(strtok(0, " ")); x->write = atoi(strtok(0, " ")); x->tags = strtok(0, " ");
    } else if (!strncmp(p, "@@X ", 4) && !n) {
      if (npragma < 16) pragma[npragma++] = p + 4;
    } else if (!strncmp(p, "@@P ", 4) && n) {
      Q *x = &q[n - 1]; char *sp = strchr(p + 4, ' ');
      if (sp && x->np < 64) { *sp = 0; x->pn[x->np] = p + 4; x->pl[x->np++] = sp + 1; }
    } else if (n) {
      Q *x = &q[n - 1];
      if (!x->sql) x->sql = p; else p[-1] = '\n';   /* (rejoin the SQL lines) */
    }
    if (!nl) break; p = nl + 1;
  }
  *out = q; return n;
}

static void params_eval(Q *q) {
  for (int i = 0; i < q->np; i++) {
    sqlite3_value_free(pv[i]); pv[i] = 0;
    char *s = sqlite3_mprintf("SELECT %s", q->pl[i]); sqlite3_stmt *st;
    if (sqlite3_prepare_v2(db, s, -1, &st, 0) == SQLITE_OK && sqlite3_step(st) == SQLITE_ROW) pv[i] = sqlite3_value_dup(sqlite3_column_value(st, 0));
    sqlite3_finalize(st); sqlite3_free(s);
  }
}
static void bind(Q *q, sqlite3_stmt *st) {
  for (int i = 0; i < q->np; i++) {
    int k = sqlite3_bind_parameter_index(st, q->pn[i]);
    if (k > 0 && pv[i]) sqlite3_bind_value(st, k, pv[i]);
  }
}

/* one execution of a prepared statement (timed: steps and row reads only); writes inside BEGIN ... ROLLBACK */
static double t_exec;
static int show;   /* CORPUS_ROWS=1: every row to stderr (for repros) */
static int exec1(Q *q, sqlite3_stmt *st, R *r) {
  if (q->write) { sqlite3_step(s_begin); sqlite3_reset(s_begin); }
  sqlite3_stmt_status(st, SQLITE_STMTSTATUS_VM_STEP, 1);
  unsigned long long h = 1469598103934665603ULL, hs = 0; long n = 0; int rc;
  perf_on(1); double t0 = now_ms();
  while ((rc = sqlite3_step(st)) == SQLITE_ROW) {
    unsigned long long rh = 1469598103934665603ULL; int nc = sqlite3_column_count(st);
    for (int i = 0; i < nc; i++) {
      int t = sqlite3_column_type(st, i); rh = fnv(rh, &t, sizeof t);
      if (t == SQLITE_INTEGER) { sqlite3_int64 v = sqlite3_column_int64(st, i); rh = fnv(rh, &v, sizeof v); }
      else if (t == SQLITE_FLOAT) { double v = sqlite3_column_double(st, i); rh = fnv(rh, &v, sizeof v); }
      else if (t == SQLITE_TEXT) { const unsigned char *z = sqlite3_column_text(st, i); rh = fnv(rh, z, (size_t)sqlite3_column_bytes(st, i)); }
      else if (t == SQLITE_BLOB) { const void *z = sqlite3_column_blob(st, i); rh = fnv(rh, z, (size_t)sqlite3_column_bytes(st, i)); }
    }
    if (show) { for (int i = 0; i < nc; i++) fprintf(stderr, "%s%s", i ? "|" : "ROW ", sqlite3_column_text(st, i) ? (const char *)sqlite3_column_text(st, i) : "NULL"); fputc('\n', stderr); }
    h = fnv(h, &rh, sizeof rh); hs += rh * 0x9E3779B97F4A7C15ULL + (rh >> 29); n++;
  }
  t_exec = now_ms() - t0; perf_on(0);
  r->rows = n; r->h = h; r->hs = hs; r->changes = sqlite3_changes(db);
  r->served = sqlite3_stmt_status(st, SQLITE_STMTSTATUS_VM_STEP, 0) == 0 && rc == SQLITE_DONE;
  r->err[0] = 0;
  if (rc != SQLITE_DONE) snprintf(r->err, sizeof r->err, "%s", sqlite3_errmsg(db));
  sqlite3_reset(st);
  if (q->write) { sqlite3_step(s_rollback); sqlite3_reset(s_rollback); }
  return rc == SQLITE_DONE ? 0 : 1;
}
static int prep(Q *q, sqlite3_stmt **st, R *r) {
  if (sqlite3_prepare_v2(db, q->sql, -1, st, 0) != SQLITE_OK) { snprintf(r->err, sizeof r->err, "prepare: %s", sqlite3_errmsg(db)); return 1; }
  bind(q, *st); return 0;
}
static void clean(char *s) { for (; *s; s++) if (*s == '\t' || *s == '\n') *s = ' '; }
static void explain(Q *q) {
  for (int g = 0; g < 2; g++) {
    sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_QPSG, g, (int *)0);
    for (int k = 0; k < 2; k++) {
      char *s = sqlite3_mprintf("EXPLAIN %s%s", k ? "" : "QUERY PLAN ", q->sql); sqlite3_stmt *st;
      if (sqlite3_prepare_v2(db, s, -1, &st, 0) != SQLITE_OK) { printf("E\t%s\t%s\terror\t%s\n", q->id, g ? "qpsg" : "plain", sqlite3_errmsg(db)); sqlite3_free(s); continue; }
      bind(q, st);
      while (sqlite3_step(st) == SQLITE_ROW) {
        printf("E\t%s\t%s\t%s", q->id, g ? "qpsg" : "plain", k ? "program" : "plan");
        for (int i = 0; i < sqlite3_column_count(st); i++) { char *v = sqlite3_mprintf("%s", sqlite3_column_text(st, i) ? (const char *)sqlite3_column_text(st, i) : ""); clean(v); printf("\t%s", v); sqlite3_free(v); }
        putchar('\n');
      }
      sqlite3_finalize(st); sqlite3_free(s);
    }
  }
  sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_QPSG, 0, (int *)0);
}

int main(int argc, char **argv) {
  if (argc < 4) { fprintf(stderr, "usage: corpus build|check|hot|prep|explain <db> <file> ...\n"); return 2; }
  const char *mode = argv[1]; show = getenv("CORPUS_ROWS") != 0;
  if ((extra = getenv("CORPUS_EXTRA") != 0)) {
    sqlite3_mem_methods m; sqlite3_config(SQLITE_CONFIG_GETMALLOC, &mem0); m = mem0;
    m.xMalloc = count_malloc; m.xRealloc = count_realloc; sqlite3_config(SQLITE_CONFIG_MALLOC, &m);
  }
  if (sqlite3_open(argv[2], &db) != SQLITE_OK) { fprintf(stderr, "corpus: open %s: %s\n", argv[2], sqlite3_errmsg(db)); return 2; }
  sqlite3_create_function(db, "regexp", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC, 0, regexp_fn, 0, 0);
  if (!strcmp(mode, "build")) {
    char *e = 0, *sql = slurp(argv[3]);
    if (sqlite3_exec(db, sql, 0, 0, &e) != SQLITE_OK) { fprintf(stderr, "corpus: build %s: %s\n", argv[3], e); return 1; }
    sqlite3_close(db); return 0;
  }
  sqlite3_prepare_v2(db, "BEGIN", -1, &s_begin, 0); sqlite3_prepare_v2(db, "ROLLBACK", -1, &s_rollback, 0);
  Q *qs; int nq = parse(slurp(argv[3]), &qs);
  for (int i = 0; i < npragma; i++) {
    char *e = 0;
    if (sqlite3_exec(db, pragma[i], 0, 0, &e) != SQLITE_OK) { fprintf(stderr, "corpus: %s: %s\n", pragma[i], e); return 1; }
  }
  if (!strcmp(mode, "explain")) {
    for (int i = 0; i < nq; i++) if (argc <= 4 || !strcmp(argv[4], qs[i].id)) { params_eval(&qs[i]); explain(&qs[i]); }
    sqlite3_finalize(s_begin); sqlite3_finalize(s_rollback); sqlite3_close(db); return 0;
  }
  int check = !strcmp(mode, "check"), hot = !strcmp(mode, "hot");
  int reps = argc > 4 && !check ? atoi(argv[4]) : 200; double budget = argc > 5 && !check ? atof(argv[5]) : 100;
  const char *only = check ? (argc > 4 ? argv[4] : 0) : (argc > 6 ? argv[6] : 0);
  if (!check) perf_open();
  double *t = malloc(sizeof *t * (size_t)(reps + 1));
  for (int i = 0; i < nq; i++) {
    Q *q = &qs[i]; if (only && strcmp(only, q->id)) continue;
    int nr = reps;   /* CORPUS_FEW="<id> <id> ...": those statements get CORPUS_FEW_REPS (default 5) executions instead */
    { const char *f = getenv("CORPUS_FEW"); size_t n = strlen(q->id);
      for (const char *x = f ? strstr(f, q->id) : 0; x; x = strstr(x + 1, q->id))
        if ((x == f || x[-1] == ' ') && (x[n] == ' ' || !x[n])) { nr = getenv("CORPUS_FEW_REPS") ? atoi(getenv("CORPUS_FEW_REPS")) : 5; break; } }
    params_eval(q);
    R r0, r; memset(&r0, 0, sizeof r0); sqlite3_stmt *st = 0;
    if (check) {
      const char *status = "ok"; int served = 0, runs = 0;
      if (prep(q, &st, &r0)) status = "err";
      else {
        for (int k = 0; k < 8; k++) {   /* 6 runs on one handle, then 2 on fresh handles */
          if (k >= 6) { sqlite3_finalize(st); if (prep(q, &st, &r)) { status = "unstable"; break; } }
          R *x = k ? &r : &r0; exec1(q, st, x); served += x->served; runs++;
          if (k && (r.rows != r0.rows || r.h != r0.h || r.changes != r0.changes || strcmp(r.err, r0.err))) {
            status = "unstable"; snprintf(r0.err + strlen(r0.err), sizeof r0.err - strlen(r0.err), " [run %d: %ld rows %016llx %s]", k, r.rows, r.h, r.err);
            break;
          }
        }
        if (!strcmp(status, "ok") && r0.err[0]) status = "err";
      }
      sqlite3_finalize(st); clean(r0.err);
      printf("C\t%s\t%s\t%ld\t%ld\t%016llx\t%016llx\t%d/%d\t%s\n", q->id, status, r0.rows, r0.changes, r0.h, r0.hs, served, runs, r0.err[0] ? r0.err : "-");
    } else {
      int nt = 0, served = 0; double spent = 0, first;
      if (hot) {
        if (prep(q, &st, &r0)) goto bad;
        exec1(q, st, &r0); first = t_exec;
        perf_reset();
        for (int k = 0; k < nr && (k < 3 || spent < budget) && !r0.err[0]; k++) { exec1(q, st, &r); t[nt++] = t_exec; spent += t_exec; served += r.served; }
        sqlite3_finalize(st);
      } else {
        double t0 = now_ms(); if (prep(q, &st, &r0)) goto bad;
        exec1(q, st, &r0); sqlite3_finalize(st); first = now_ms() - t0;
        perf_reset();
        for (int k = 0; k < nr && (k < 3 || spent < budget) && !r0.err[0]; k++) {
          perf_on(1); t0 = now_ms(); prep(q, &st, &r); double tp = now_ms() - t0; perf_on(0);
          exec1(q, st, &r);   /* (its BEGIN/ROLLBACK for a write untimed, as in hot) */
          perf_on(1); t0 = now_ms(); sqlite3_finalize(st); t[nt] = tp + t_exec + (now_ms() - t0); perf_on(0);
          spent += t[nt++]; served += r.served;
        }
      }
      { double sum = 0; for (int k = 0; k < nt; k++) sum += t[k];
        long long ins = perf_read(0), cyc = perf_read(1);
#ifdef CORPUS_CALLGRIND
        { char lb[300]; snprintf(lb, sizeof lb, "%s %s %d", q->id, hot ? "hot" : "prep", nt); CALLGRIND_DUMP_STATS_AT(lb); }
#endif
        qsort(t, (size_t)nt, sizeof *t, cmpd); clean(r0.err);
        printf("T\t%s\t%ld\t%016llx\t%.4f\t%.4f\t%.5f\t%d\t%.1f\t%.1f\t%d/%d\t%s\n", q->id, r0.rows, r0.h, first, nt ? t[nt / 2] : first,
               nt ? sum / nt : first, nt, ins >= 0 && nt ? (double)ins / nt : -1.0, cyc >= 0 && nt ? (double)cyc / nt : -1.0,
               served, nt, r0.err[0] ? r0.err : "-");
        int lu, lh, mf, mh; sqlite3_db_status(db, SQLITE_DBSTATUS_LOOKASIDE_USED, &lu, &lh, 0);   /* (after the statement, its
                                         lookaside slots still held, and its misses for want of a free slot) */
        sqlite3_db_status(db, SQLITE_DBSTATUS_LOOKASIDE_MISS_FULL, &mf, &mh, 1);
        printf("L\t%s\t%d\t%d\n", q->id, lu, mh);
        if (extra) {
          printf("X\t%s", q->id);
          for (int k = 2; k < NPERF; k++) { long long v = perf_read(k); printf("\t%.1f", v >= 0 && nt ? (double)v / nt : -1.0); }
          printf("\t%.1f\n", nt ? (double)allocs / nt : -1.0);
        } }
      fflush(stdout); continue;
    bad:
      clean(r0.err); printf("T\t%s\t0\t0\t0\t0\t0\t0\t-1\t-1\t0/0\t%s\n", q->id, r0.err); continue;
    }
    fflush(stdout);
  }
  sqlite3_finalize(s_begin); sqlite3_finalize(s_rollback); sqlite3_close(db);
  return 0;
}
