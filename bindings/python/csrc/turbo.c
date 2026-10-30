/* turbo.c: turbo_sqlite3's SQLite, in one translation unit: turbo's patched amalgamation (build/gen/sqlite3.c) with qc
** after it, as tests/serve.c builds it, and what Python needs on top:
**
** - Threads. qc's run state is per process (qc/qc.c: "one thread at a time runs qc"), and Python releases the GIL in
**   sqlite3_step, so two threads can step two connections at once. Every qc hook (patch.py's sqlite3QcStart, Serve,
**   Reset, Free, TxnEnd, Close) runs under one process-wide lock here:
**   - a statement starting while another thread is inside qc is not waited for: it runs in SQLite's interpreter, as
**     a statement qc refused does (its results are SQLite's either way);
**   - every other hook waits for the lock, releasing the GIL first if this thread holds it (the thread inside qc may
**     be calling a Python function, which needs the GIL);
**   - no busy wait sleeps while the lock is held: the VFSes' xSleep returns at once inside qc, so qc's own read
**     transaction gives up on a lock another connection holds, and the statement runs in the interpreter, which
**     waits for it (busy_timeout) outside the lock.
**   qc.c assigns its hooks itself (at startup, and at every lift); here its assignments land in shadow pointers, and
**   SQLite's hooks are the locked wrappers below.
** - Streaming is off (QV_STREAM_DEFAULT=0, set by setup.py): a suspended stream is drained by whichever statement
**   runs next, on any connection, which would reach into another thread's connection.
** - A runtime switch (turbo_enable) and three counters for tests (turbo_counts).
*/
#include "sqlite3.c"

#define sqlite3QcStart turbo_qcStart
#define sqlite3QcServe turbo_qcServe
#define sqlite3QcReset turbo_qcReset
#define sqlite3QcFree turbo_qcFree
#define sqlite3QcTxnEnd turbo_qcTxnEnd
#define sqlite3QcClose turbo_qcClose
static void (*turbo_qcStart)(Vdbe *);
static int (*turbo_qcServe)(Vdbe *);
static void (*turbo_qcReset)(Vdbe *);
static void (*turbo_qcFree)(Vdbe *);
static void (*turbo_qcTxnEnd)(Btree *);
static void (*turbo_qcClose)(sqlite3 *);
#include "qc.c"
#undef sqlite3QcStart
#undef sqlite3QcServe
#undef sqlite3QcReset
#undef sqlite3QcFree
#undef sqlite3QcTxnEnd
#undef sqlite3QcClose

#include <pthread.h>


void *turbo_gil_release(void);     /* turbo_gil.c: the GIL released if this thread holds it (0 if not) */
void turbo_gil_restore(void *);

static pthread_mutex_t turbo_mu = PTHREAD_MUTEX_INITIALIZER;
static _Thread_local int turbo_depth;   /* this thread's nesting inside qc (a Python function qc calls may step again) */
static int turbo_on = 1;
static long long turbo_runs, turbo_rows, turbo_passed;   /* served runs and rows; starts left to the interpreter as
                                                          another thread was inside qc (atomics: read outside the lock) */

static void turbo_lock(void) {
  if (turbo_depth++ || pthread_mutex_trylock(&turbo_mu) == 0) return;
  void *g = turbo_gil_release();
  pthread_mutex_lock(&turbo_mu);
  turbo_gil_restore(g);
}
static int turbo_trylock(void) {
  if (turbo_depth) { turbo_depth++; return 1; }
  if (pthread_mutex_trylock(&turbo_mu)) return 0;
  turbo_depth = 1; return 1;
}
static void turbo_unlock(void) { if (--turbo_depth == 0) pthread_mutex_unlock(&turbo_mu); }

static void turbo_start(Vdbe *v) {
  if (!turbo_on || !turbo_qcStart) { v->qcServe = 0; return; }
  if (!turbo_trylock()) { v->qcServe = 0; __atomic_fetch_add(&turbo_passed, 1, __ATOMIC_RELAXED); return; }   /* (the interpreter's run, as qcStart's refusals) */
  turbo_qcStart(v);
  if (v->qcServe) __atomic_fetch_add(&turbo_runs, 1, __ATOMIC_RELAXED);
  turbo_unlock();
}
static int turbo_serve(Vdbe *v) {
  if (!turbo_qcServe) { v->qcServe = 0; return sqlite3VdbeExec(v); }
  turbo_lock(); int rc = turbo_qcServe(v); turbo_unlock();
  if (rc == SQLITE_ROW) __atomic_fetch_add(&turbo_rows, 1, __ATOMIC_RELAXED);
  return rc;
}
static void turbo_reset(Vdbe *v) { if (turbo_qcReset) { turbo_lock(); turbo_qcReset(v); turbo_unlock(); } }
static void turbo_free(Vdbe *v) { if (turbo_qcFree) { turbo_lock(); turbo_qcFree(v); turbo_unlock(); } }
static void turbo_txn_end(Btree *b) { if (turbo_qcTxnEnd) { turbo_lock(); turbo_qcTxnEnd(b); turbo_unlock(); } }
static void turbo_close(sqlite3 *db) { if (turbo_qcClose) { turbo_lock(); turbo_qcClose(db); turbo_unlock(); } }

/* every registered VFS's xSleep: no sleep inside qc (a busy handler's back-off would hold the lock) */
#define TURBO_NVFS 16
static struct { sqlite3_vfs *vfs; int (*xSleep)(sqlite3_vfs *, int); } turbo_vfs[TURBO_NVFS];
static int turbo_sleep(sqlite3_vfs *vfs, int us) {
  if (turbo_depth) return us;
  for (int i = 0; i < TURBO_NVFS && turbo_vfs[i].vfs; i++) if (turbo_vfs[i].vfs == vfs) return turbo_vfs[i].xSleep(vfs, us);
  return us;
}

__attribute__((constructor)) static void turbo_init(void) {   /* when the extension is loaded (its VFSes registered first) */
  if (sqlite3_initialize() != SQLITE_OK) return;   /* (the module's init reports it) */
  sqlite3_mutex_enter(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN));
  int n = 0;
  for (sqlite3_vfs *p = vfsList; p && n < TURBO_NVFS; p = p->pNext)
    if (p->xSleep && p->xSleep != turbo_sleep) { turbo_vfs[n].vfs = p; turbo_vfs[n].xSleep = p->xSleep; p->xSleep = turbo_sleep; n++; }
  sqlite3_mutex_leave(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN));
  sqlite3QcStart = turbo_start; sqlite3QcServe = turbo_serve; sqlite3QcReset = turbo_reset;
  sqlite3QcFree = turbo_free; sqlite3QcTxnEnd = turbo_txn_end; sqlite3QcClose = turbo_close;
}
/* on: 1 serve read-only statements through qc, 0 SQLite's interpreter only (statements already being served finish);
   -1 only asks. The previous state. (QC_SERVE=0 in the environment: qc's own startup installed nothing, so off) */
int turbo_enable(int on) {
  turbo_lock();
  int was = turbo_on && turbo_qcStart;
  if (on > 0 && !turbo_qcStart) sqlite3_qc_serve(1);   /* (off at startup: qc's hooks installed now) */
  if (on >= 0) turbo_on = on > 0;
  turbo_unlock();
  return was;
}
void turbo_counts(long long *runs, long long *rows, long long *passed) {
  *runs = __atomic_load_n(&turbo_runs, __ATOMIC_RELAXED); *rows = __atomic_load_n(&turbo_rows, __ATOMIC_RELAXED);
  *passed = __atomic_load_n(&turbo_passed, __ATOMIC_RELAXED);
}
