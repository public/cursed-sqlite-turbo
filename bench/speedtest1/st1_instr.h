/* st1_instr.h: hooks for the instrumented copy of speedtest1.c (bench/speedtest1/instrument.py). The unchanged
** speedtest1.c stays the headline benchmark; this copy reports, per test, to $ST1I_OUT (default stderr):
**   ST1I <test> <instr> <cycles> <prep-ns> <first-ns> <loop-ns> <exec-ns> <nprep> <nrun> <nexec> <t0> <t1>
** instr, cycles: user-mode, the whole test (perf_event_open; -1 without root or perf_event_paranoid <= 2);
** prep: sqlite3_prepare_v2 in speedtest1_prepare; first: the first speedtest1_run after each prepare (qc lifts the
** statement there); loop: the other runs; exec: speedtest1_exec (one-shot statements, prepare included);
** t0, t1: CLOCK_MONOTONIC seconds at the test's start and end (perf record -k CLOCK_MONOTONIC; perf report --time).
**   ST1SQL <test> <prep|exec> <sql>   every statement a test prepares or executes (joined with QCS_STATS). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#ifdef __linux__
#include <linux/perf_event.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif
static FILE *st1i_f; static int st1i_fd[2] = { -2, -2 }, st1i_test, st1i_first;
static long long st1i_prep, st1i_firstns, st1i_loop, st1i_exec, st1i_t, st1i_t0; static int st1i_np, st1i_nr, st1i_ne;
static long long st1i_now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000000000LL + t.tv_nsec; }
static FILE *st1i_out(void) {
  if (!st1i_f) { const char *p = getenv("ST1I_OUT"); st1i_f = p ? fopen(p, "w") : 0; if (!st1i_f) st1i_f = stderr; }
  return st1i_f;
}
static void st1i_counters(int on) {
#ifdef __linux__
  if (st1i_fd[0] == -2) {
    static const unsigned long long cfg[2] = { PERF_COUNT_HW_INSTRUCTIONS, PERF_COUNT_HW_CPU_CYCLES };
    for (int i = 0; i < 2; i++) {
      struct perf_event_attr a; memset(&a, 0, sizeof a);
      a.size = sizeof a; a.type = PERF_TYPE_HARDWARE; a.config = cfg[i]; a.disabled = 1; a.exclude_kernel = 1; a.exclude_hv = 1;
      st1i_fd[i] = (int)syscall(SYS_perf_event_open, &a, 0, -1, -1, 0);
    }
  }
  for (int i = 0; i < 2; i++) if (st1i_fd[i] >= 0) {
    if (on) { ioctl(st1i_fd[i], PERF_EVENT_IOC_RESET, 0); ioctl(st1i_fd[i], PERF_EVENT_IOC_ENABLE, 0); }
    else ioctl(st1i_fd[i], PERF_EVENT_IOC_DISABLE, 0);
  }
#endif
}
static long long st1i_read(int i) { long long v = -1; if (st1i_fd[i] < 0 || read(st1i_fd[i], &v, sizeof v) != sizeof v) v = -1; return v; }
static void st1i_begin(int test) {
  st1i_test = test; st1i_prep = st1i_firstns = st1i_loop = st1i_exec = 0; st1i_np = st1i_nr = st1i_ne = 0; st1i_first = 0;
  st1i_t0 = st1i_now(); st1i_counters(1);
}
static void st1i_end(void) {
  st1i_counters(0); long long t1 = st1i_now();
  fprintf(st1i_out(), "ST1I %d %lld %lld %lld %lld %lld %lld %d %d %d %lld.%09lld %lld.%09lld\n", st1i_test, st1i_read(0), st1i_read(1),
          st1i_prep, st1i_firstns, st1i_loop, st1i_exec, st1i_np, st1i_nr, st1i_ne,
          st1i_t0 / 1000000000LL, st1i_t0 % 1000000000LL, t1 / 1000000000LL, t1 % 1000000000LL);
  fflush(st1i_out());
}
static void st1i_sql(const char *kind, const char *sql) {
  fprintf(st1i_out(), "ST1SQL %d %s ", st1i_test, kind);
  for (const char *c = sql; *c; c++) fputc(*c == '\n' || *c == '\t' || *c == '\r' ? ' ' : *c, st1i_out());
  fputc('\n', st1i_out());
}
static void st1i_prep_start(void) { st1i_t = st1i_now(); }
static void st1i_prep_end(const char *sql) { st1i_prep += st1i_now() - st1i_t; st1i_np++; st1i_first = 1; st1i_sql("prep", sql); }
static void st1i_run_start(void) { st1i_t = st1i_now(); }
static void st1i_run_end(void) { long long d = st1i_now() - st1i_t; if (st1i_first) { st1i_firstns += d; st1i_first = 0; } else st1i_loop += d; st1i_nr++; }
static void st1i_exec_start(void) { st1i_t = st1i_now(); }
static void st1i_exec_end(const char *sql) { st1i_exec += st1i_now() - st1i_t; st1i_ne++; st1i_sql("exec", sql); }
