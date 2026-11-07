/* turbo_lib.c: the benchmarks' SQLite, in one translation unit: turbo's patched amalgamation (build/gen/sqlite3.c) with
** qc after it, as tests/serve.c and bindings/python/csrc/turbo.c build it. The C++ benchmarks (bench/turbo_bench.cpp)
** use SQLite's plain API through sqlite3.h and the three functions below.
**
** - turbo_bench_init: qc's process-wide state, with adapt's timing off (QC_NOADAPT=1) unless the environment already
**   says otherwise. Adapt decides between turbo's plan and the interpreter by timing both, which is not reproducible
**   under CodSpeed's CPU simulation; with it off, a plan turbo lifts always serves.
** - turbo_bench_serve: 1 serve read-only statements through turbo, 0 SQLite's interpreter only (stock).
** - turbo_bench_runs: how many executions turbo served so far (a counter in the benchmarks' output).
*/
#include "sqlite3.c"

#define sqlite3QcStart turbo_qcStart
#define sqlite3QcServe turbo_qcServe
static void (*turbo_qcStart)(Vdbe *);
static int (*turbo_qcServe)(Vdbe *);
#include "qc.c"
#undef sqlite3QcStart
#undef sqlite3QcServe

static int turbo_on = 1;
static long long turbo_runs;

static void turbo_start(Vdbe *v) {
  if (!turbo_on) {   /* off: SQLite's interpreter, after a stream suspended while it was on is drained */
    if (v->db->qcBusy) { u8 no = v->qcNo; v->qcNo = 1; turbo_qcStart(v); v->qcNo = no; }
    v->qcServe = 0; return;
  }
  turbo_qcStart(v);
  if (v->qcServe) turbo_runs++;
}

void turbo_bench_init(void) {
  static int done;
  if (done) return;
  done = 1;
  setenv("QC_NOADAPT", "1", 0);
  qc_init();
  sqlite3_qc_serve(1);   /* (qc's hooks in the shadows: turbo_on decides) */
  sqlite3QcStart = turbo_start; sqlite3QcServe = turbo_qcServe;
}
void turbo_bench_serve(int on) { turbo_on = on != 0; }
long long turbo_bench_runs(void) { return turbo_runs; }
