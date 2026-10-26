/* tcl_qc.c: qc against SQLite's TCL test suite. Appended, with qc.c, to an amalgamation whose sqlite3_step was renamed
** sqlite3_step_orig (qc/patch.py --step-hook); tests/build-tcl.sh builds testfixture from it.
**
** Every sqlite3_step (testfixture's `db eval`, sqlite3_exec, the C test helpers) comes through the wrapper below.
** When a read-only statement starts and no other statement is running on its connection, the wrapper prepares a
** copy of its SQL with the same bindings, compiles it with sqlite3_qc and runs it inside BEGIN...COMMIT, with the
** connection's trace, profile, authorizer and progress callbacks off, so the test sees none of this. Each row the
** interpreter then returns is compared, value by value, with qc's; at SQLITE_DONE the row counts are compared.
** The test only ever sees SQLite's own results. Differences and totals go to $QCT_DIR/qct.<pid>.txt (QCTDIFF and
** QCTSTAT lines, QCTWHY for the reasons qc declined). QC_VM_ONLY=1 sends every compiled statement through qvm;
** QCT_OFF=1 turns the comparison off (a baseline with the same binary). */
#include <unistd.h>

typedef struct QctVal { int type; i64 i; double r; char *z; int n; } QctVal;
typedef struct QctRun {   /* qc's rows for one statement, compared as the interpreter steps it */
  Vdbe *v; u32 gen; QctVal *val; int nrow, ncol, pos, bad; i64 changes;   /* changes: total_changes when it started */
} QctRun;
#define QCT_MAXRUN 64
static QctRun qct_run[QCT_MAXRUN]; static u32 qct_gen;
static int qct_busy, qct_off = -1;
static long qct_stmt, qct_compiled, qct_kind[4], qct_fallback, qct_rows, qct_diff, qct_shown, qct_nondet, qct_vtab, qct_progress, qct_written;
static FILE *qct_log;
static struct { const char *why; long n; } qct_why[64]; static int qct_nwhy;

static void qct_note_why(const char *w) {
  if (!w || !*w) w = "(none)";
  for (int i = 0; i < qct_nwhy; i++) if (!strcmp(qct_why[i].why, w)) { qct_why[i].n++; return; }
  if (qct_nwhy < 64) { qct_why[qct_nwhy].why = w; qct_why[qct_nwhy++].n = 1; }
}
static FILE *qct_out(void) {
  if (!qct_log) {
    const char *d = getenv("QCT_DIR"); char p[512];
    snprintf(p, sizeof p, "%s/qct.%d.txt", d ? d : ".", (int)getpid());
    qct_log = fopen(p, "a"); if (!qct_log) qct_log = stderr;
  }
  return qct_log;
}
static void qct_atexit(void) {
  if (!qct_stmt) return;
  FILE *f = qct_out();
  fprintf(f, "QCTSTAT statements %ld compiled %ld plan %ld loops %ld vm %ld fallbacks %ld rows %ld differences %ld"
          " skipped-nondeterministic %ld skipped-vtab %ld skipped-progress %ld written-while-read %ld\n",
          qct_stmt, qct_compiled, qct_kind[1], qct_kind[2], qct_kind[3], qct_fallback, qct_rows, qct_diff,
          qct_nondet, qct_vtab, qct_progress, qct_written);
  for (int i = 0; i < qct_nwhy; i++) fprintf(f, "QCTWHY %ld %s\n", qct_why[i].n, qct_why[i].why);
  fflush(f);
}
static void qct_free(QctRun *r) {
  for (int k = 0; k < r->nrow * r->ncol; k++) free(r->val[k].z);
  free(r->val); memset(r, 0, sizeof *r);   /* (plain malloc: the suite counts sqlite3_malloc'd memory left at exit, and a run the test stops early is only freed when its handle starts again) */
}
static QctRun *qct_find(Vdbe *v) { for (int i = 0; i < QCT_MAXRUN; i++) if (qct_run[i].v == v) return &qct_run[i]; return 0; }
static int qct_collect(void *ctx, int nrow, int ncol, const QcVal *x) {
  QctRun *r = ctx;
  r->val = malloc(sizeof *r->val * (size_t)(nrow * ncol + 1)); if (!r->val) return SQLITE_NOMEM;
  r->nrow = nrow; r->ncol = ncol;
  for (int k = 0; k < nrow * ncol; k++) {
    QctVal *o = &r->val[k]; memset(o, 0, sizeof *o); o->type = x[k].type;
    if (o->type == SQLITE_INTEGER) o->i = x[k].i;
    else if (o->type == SQLITE_FLOAT) o->r = x[k].r;
    else if (o->type == SQLITE_TEXT || o->type == SQLITE_BLOB) {
      o->n = x[k].n; o->z = malloc((size_t)o->n + 1); if (!o->z) return SQLITE_NOMEM;
      if (o->n) memcpy(o->z, x[k].z, (size_t)o->n);
      o->z[o->n] = 0;
    }
  }
  return SQLITE_OK;
}
static void qct_report(Vdbe *v, const char *what, int row, int col) {
  qct_diff++;
  if (qct_shown++ >= 50) return;
  fprintf(qct_out(), "QCTDIFF %s (row %d col %d): %s\n", what, row, col, v->zSql ? v->zSql : "?");
  fflush(qct_out());
}

/* the statement is about to start: qc's rows for it, if qc compiles it */
static void qct_start(Vdbe *v) {
  sqlite3 *db = v->db;
  if (!v->zSql || !v->readOnly || v->explain || db->nVdbeActive > 0 || !db->autoCommit) return;
  qct_stmt++;
  if (db->xProgress) { qct_progress++; return; }   /* (a test that aborts statements from its progress handler) */
  for (int pc = 0; pc < v->nOp; pc++) {   /* two runs of these can differ legitimately, or the test counts their calls */
    const Op *o = &v->aOp[pc];
    if (o->opcode == OP_VOpen || o->opcode == OP_VFilter || o->opcode == OP_VColumn) { qct_vtab++; return; }
    const FuncDef *f = (o->opcode == OP_Function || o->opcode == OP_PureFunc) && o->p4type == P4_FUNCCTX ? o->p4.pCtx->pFunc
                     : (o->opcode == OP_AggStep || o->opcode == OP_AggStep1) && o->p4type == P4_FUNCDEF ? o->p4.pFunc : 0;
    if (f && (!(f->funcFlags & SQLITE_FUNC_CONSTANT) || (f->funcFlags & SQLITE_FUNC_SLOCHNG))) { qct_nondet++; return; }
  }
  /* the connection's callbacks, off while this runs: the test must not see the copy or the BEGIN/COMMIT */
  __typeof__(db->trace) tr = db->trace; u8 mt = db->mTrace; sqlite3_xauth au = db->xAuth; int (*pr)(void *) = db->xProgress;
#ifndef SQLITE_OMIT_DEPRECATED
  void (*pf)(void *, const char *, u64) = db->xProfile; db->xProfile = 0;
#endif
  u64 fl = db->flags & SQLITE_EnableQPSG;
  db->trace.xV2 = 0; db->mTrace = 0; db->xAuth = 0; db->xProgress = 0;
  void (*lg)(void *, int, const char *) = sqlite3GlobalConfig.xLog; sqlite3GlobalConfig.xLog = 0;   /* (prepare logs warnings the test may count) */
  sqlite3_stmt *c = 0; QctRun tmp; memset(&tmp, 0, sizeof tmp);
  if (sqlite3_prepare_v3(db, v->zSql, -1, 0, &c, 0) != SQLITE_OK || !c) goto out;
  for (int i = 1; i <= sqlite3_bind_parameter_count(c) && i <= v->nVar; i++) sqlite3_bind_value(c, i, &v->aVar[i - 1]);
  qc_why = "";
  if (!sqlite3_qc(c)) { qct_note_why(qc_why); goto out; }
  qct_compiled++; qct_kind[*(int *)((Vdbe *)c)->pQc & 3]++;
  if (sqlite3_exec(db, "BEGIN", 0, 0, 0) != SQLITE_OK) goto out;
  qc_why = "";
  int rc = sqlite3_qc_exec(c, qct_collect, &tmp);
  sqlite3_exec(db, "COMMIT", 0, 0, 0);
  if (rc == QC_FALLBACK) { qct_fallback++; qct_note_why(qc_why); qct_free(&tmp); goto out; }
  if (rc != SQLITE_OK) { qct_free(&tmp); goto out; }
  QctRun *r = qct_find(v); if (!r) r = qct_find(0);
  if (!r) { qct_free(&tmp); goto out; }   /* (too many statements in flight: this one isn't compared) */
  qct_free(r); *r = tmp; r->v = v; r->gen = ++qct_gen; r->changes = sqlite3_total_changes64(db);
out:
  sqlite3_finalize(c);   /* (frees the copy's plan) */
  sqlite3_qc_release();   /* and qc's run state: the suite counts any memory left allocated as an error */
  db->trace = tr; db->mTrace = mt; db->xAuth = au; db->xProgress = pr; sqlite3GlobalConfig.xLog = lg;
#ifndef SQLITE_OMIT_DEPRECATED
  db->xProfile = pf;
#endif
  db->flags = (db->flags & ~(u64)SQLITE_EnableQPSG) | fl;   /* (sqlite3_qc may re-prepare with QPSG; it restores it, but to be sure) */
}
static int qct_val_eq(sqlite3_value *x, const QctVal *q) {
  int t = sqlite3_value_type(x);
  if (t != q->type) return 0;
  switch (t) {
    case SQLITE_INTEGER: return sqlite3_value_int64(x) == q->i;
    case SQLITE_FLOAT: { double d = sqlite3_value_double(x); return memcmp(&d, &q->r, sizeof d) == 0; }
    case SQLITE_TEXT: { const unsigned char *z = sqlite3_value_text(x); int n = sqlite3_value_bytes(x); return n == q->n && (!n || !memcmp(z, q->z, (size_t)n)); }
    case SQLITE_BLOB: { const void *z = sqlite3_value_blob(x); int n = sqlite3_value_bytes(x); return n == q->n && (!n || !memcmp(z, q->z, (size_t)n)); }
  }
  return 1;
}

static int sqlite3_step_orig(sqlite3_stmt *pStmt);
SQLITE_API int sqlite3_step(sqlite3_stmt *pStmt) {
  Vdbe *v = (Vdbe *)pStmt;
  if (qct_off < 0) { qct_off = getenv("QCT_OFF") != 0; atexit(qct_atexit); }
  if (qct_off || qct_busy || !v || !v->db) return sqlite3_step_orig(pStmt);
  if (v->eVdbeState == VDBE_READY_STATE) {   /* starting: forget what an earlier run of this handle left, then run qc */
    QctRun *old = qct_find(v); if (old) qct_free(old);
    qct_busy = 1; qct_start(v); qct_busy = 0;
  }
  int rc = sqlite3_step_orig(pStmt);
  QctRun *r = qct_find(v);
  if (!r || r->bad) return rc;
  qct_busy = 1;
  if (rc == SQLITE_ROW && sqlite3_total_changes64(v->db) != r->changes) { qct_written++; qct_free(r); qct_busy = 0; return rc; }   /* the test wrote while reading: qc's rows are a snapshot */
  if (rc == SQLITE_ROW) {
    qct_rows++;
    if (r->pos >= r->nrow) { qct_report(v, "the interpreter returned more rows", r->pos, -1); r->bad = 1; }
    else if (sqlite3_data_count(pStmt) != r->ncol) { qct_report(v, "column counts differ", r->pos, -1); r->bad = 1; }
    else {
      for (int i = 0; i < r->ncol; i++)
        if (!qct_val_eq(sqlite3_column_value(pStmt, i), &r->val[r->pos * r->ncol + i])) { qct_report(v, "values differ", r->pos, i); r->bad = 1; break; }
      r->pos++;
    }
  } else if (sqlite3_total_changes64(v->db) != r->changes) { qct_written++; qct_free(r);   /* (written while read, seen at the end) */
  } else {
    if (rc == SQLITE_DONE && r->pos != r->nrow) qct_report(v, "qc returned more rows", r->pos, -1);
    else if (rc != SQLITE_DONE && rc != SQLITE_ROW && r->nrow > r->pos) qct_report(v, "the interpreter failed where qc returned rows", r->pos, -1);
    qct_free(r);
  }
  qct_busy = 0;
  return rc;
}
