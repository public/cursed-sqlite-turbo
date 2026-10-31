/* turbo.c: turbo_sqlite3's SQLite, in one translation unit: turbo's patched amalgamation (build/gen/sqlite3.c) with qc
** after it, as tests/serve.c builds it, and what Python needs on top:
**
** - Threads need nothing here. Python releases the GIL in sqlite3_step, so threads step their connections at once;
**   qc keeps its run state with the connection (QcConn) and every hook runs under the connection's mutex
**   (SQLITE_THREADSAFE=1, serialized), so turbo serves on every thread, streaming included, as SQLite runs them.
** - A runtime switch (turbo_enable) and counters for tests (turbo_counts): qc's sqlite3QcStart and sqlite3QcServe land
**   in shadow pointers, and SQLite's are the counting wrappers below.
*/
#include "sqlite3.c"

#define sqlite3QcStart turbo_qcStart
#define sqlite3QcServe turbo_qcServe
static void (*turbo_qcStart)(Vdbe *);
static int (*turbo_qcServe)(Vdbe *);
#include "qc.c"
#undef sqlite3QcStart
#undef sqlite3QcServe

static int turbo_on = 1;   /* (atomics: any thread reads it, enable_turbo writes it) */
static long long turbo_runs, turbo_rows;   /* served runs and rows */

static void turbo_start(Vdbe *v) {
  if (!__atomic_load_n(&turbo_on, __ATOMIC_RELAXED)) { v->qcServe = 0; return; }
  turbo_qcStart(v);
  if (v->qcServe) __atomic_fetch_add(&turbo_runs, 1, __ATOMIC_RELAXED);
}
static int turbo_serve(Vdbe *v) {
  int rc = turbo_qcServe(v);
  if (rc == SQLITE_ROW) __atomic_fetch_add(&turbo_rows, 1, __ATOMIC_RELAXED);
  return rc;
}

__attribute__((constructor)) static void turbo_init(void) {   /* when the extension is loaded */
  const char *e = getenv("QC_SERVE");   /* (as qc's own startup reads it: off unless 1, else QC_SERVE_DEFAULT) */
  turbo_on = e ? *e == '1' : QC_SERVE_DEFAULT;
  sqlite3_qc_serve(1);   /* (qc's hooks in the shadows, whatever QC_SERVE says: turbo_on decides) */
  sqlite3QcStart = turbo_start; sqlite3QcServe = turbo_serve;
}
/* on: 1 serve read-only statements through qc, 0 SQLite's interpreter only (statements already being served finish);
   -1 only asks. The previous state. (QC_SERVE=0 in the environment: off at startup) */
int turbo_enable(int on) {
  return on >= 0 ? __atomic_exchange_n(&turbo_on, on > 0, __ATOMIC_RELAXED) : __atomic_load_n(&turbo_on, __ATOMIC_RELAXED);
}
void turbo_counts(long long *runs, long long *rows, long long *passed) {
  *runs = __atomic_load_n(&turbo_runs, __ATOMIC_RELAXED); *rows = __atomic_load_n(&turbo_rows, __ATOMIC_RELAXED);
  *passed = 0;   /* (no start is left to the interpreter for another thread's sake any more) */
}
