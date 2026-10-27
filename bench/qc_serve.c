/* qc_serve.c: qc behind SQLite's own API, for unmodified programs (speedtest1, bench/qrun.c, sqlite-jdbc under
** SQLancer). Appended, with qc.c, to an amalgamation whose sqlite3_step, sqlite3_reset and sqlite3_finalize were renamed
** *_orig (qc/patch.py --step-hook, then bench/build-sqlite.sh); adapted from the serve mode of cursed-http's
** explore/gitea-jit/qc_gitea.c, single-threaded like tests/tcl_qc.c.
**
** A read-only statement starting on a connection with nothing else running is lifted (sqlite3_qc, once per handle)
** and executed by qc (sqlite3_qc_exec, inside BEGIN ... COMMIT when the connection is in autocommit, as qc requires).
** Its rows are handed to the program through the statement's own result row (pResultRow), so sqlite3_column_* read
** qc's values; the statement's program never runs. On a refusal (qc doesn't take the statement), a fallback or an
** error, the statement is stepped by SQLite as usual, and produces whatever SQLite produces.
**
** QC_VM_ONLY=1 (read by qc.c): every lifted statement through qvm. QCS_OFF=1: SQLite only (same binary).
** QCS_STATS=<file>: at exit, the totals and one line per SQL text (executions, which tier, served, fallbacks and why,
** refusals and why), tab-separated (bench/qcs-report.py summarises it). qcs_info() gives a program the same for one
** handle. */
#include <stdio.h>

typedef struct QcsVal { int type; i64 i; double r; char *z; int n; } QcsVal;
typedef struct QcsRun { Vdbe *v; QcsVal *val; int nrow, ncol, pos; Mem *mem; } QcsRun;   /* a handle being served */
#define QCS_NRUN 4096   /* (open addressing, by handle) */
static QcsRun qcs_run[QCS_NRUN]; static int qcs_nserving;
static int qcs_busy, qcs_off = -1;
static const char *qcs_last_why = ""; static Vdbe *qcs_last_v; static int qcs_last_served;   /* (qcs_info) */
static long qcs_starts, qcs_served, qcs_rows, qcs_refused, qcs_fallback, qcs_err, qcs_kind[4], qcs_skip;

/* per SQL text (QCS_STATS): what happened to it */
typedef struct QcsText { char *sql; unsigned h; long n, served, refused, fallback, rows; int kind; const char *why; } QcsText;
#define QCS_NTEXT (1 << 18)   /* (speedtest1 runs ~200k statements, many with literal values) */
static QcsText *qcs_text;
static int qcs_ntext;
static QcsText *qcs_txt(const char *sql) {
  if (!qcs_text) { qcs_text = calloc(QCS_NTEXT, sizeof *qcs_text); if (!qcs_text) return 0; }
  size_t L = strlen(sql); unsigned h = 2166136261u ^ (unsigned)L;
  for (size_t i = 0; i < L; i++) h = (h ^ (unsigned char)sql[i]) * 16777619u;
  for (unsigned i = 0; i < QCS_NTEXT; i++) {
    QcsText *p = &qcs_text[(h + i) % QCS_NTEXT];
    if (!p->sql) { if (qcs_ntext >= QCS_NTEXT * 3 / 4) return 0; p->sql = strdup(sql); p->h = h; qcs_ntext++; return p; }
    if (p->h == h && !strcmp(p->sql, sql)) return p;
  }
  return 0;
}
static void qcs_atexit(void) {
  const char *f = getenv("QCS_STATS"); if (!f || !*f) return;
  FILE *o = fopen(f, "a"); if (!o) return;
  fprintf(o, "QCSSTAT\tstarts %ld\tserved %ld\trows %ld\trefused %ld\tfallbacks %ld\terrors %ld\tskipped %ld\tplan %ld\tloops %ld\tvm %ld\n",
          qcs_starts, qcs_served, qcs_rows, qcs_refused, qcs_fallback, qcs_err, qcs_skip, qcs_kind[1], qcs_kind[2], qcs_kind[3]);
  for (int i = 0; qcs_text && i < QCS_NTEXT; i++) {
    QcsText *p = &qcs_text[i]; if (!p->sql) continue;
    fprintf(o, "QCSTEXT\t%ld\t%d\t%ld\t%ld\t%ld\t%ld\t%s\t", p->n, p->kind, p->served, p->fallback, p->refused, p->rows, p->why && *p->why ? p->why : "-");
    for (const char *c = p->sql; *c; c++) fputc(*c == '\t' || *c == '\n' || *c == '\r' ? ' ' : *c, o);
    fputc('\n', o);
  }
  fclose(o);
}

/* BEGIN and COMMIT, prepared once per connection (sqlite3_exec would parse them on every autocommit statement);
   finalized when the connection closes (sqlite3_close* are wrapped too) */
#define QCS_NTXN 64
static struct { sqlite3 *db; sqlite3_stmt *begin, *commit; } qcs_txn[QCS_NTXN];
static int qcs_exec_txn(sqlite3 *db, int commit) {
  int i, f = -1;
  for (i = 0; i < QCS_NTXN && qcs_txn[i].db != db; i++) if (f < 0 && !qcs_txn[i].db) f = i;
  if (i == QCS_NTXN) {
    if (f < 0) return sqlite3_exec(db, commit ? "COMMIT" : "BEGIN", 0, 0, 0);
    i = f; qcs_txn[i].db = db;
    if (sqlite3_prepare_v3(db, "BEGIN", -1, SQLITE_PREPARE_PERSISTENT, &qcs_txn[i].begin, 0) != SQLITE_OK
        || sqlite3_prepare_v3(db, "COMMIT", -1, SQLITE_PREPARE_PERSISTENT, &qcs_txn[i].commit, 0) != SQLITE_OK) {
      sqlite3_finalize_orig(qcs_txn[i].begin); sqlite3_finalize_orig(qcs_txn[i].commit); memset(&qcs_txn[i], 0, sizeof qcs_txn[i]);
      return sqlite3_exec(db, commit ? "COMMIT" : "BEGIN", 0, 0, 0);
    }
  }
  sqlite3_stmt *st = commit ? qcs_txn[i].commit : qcs_txn[i].begin;
  int rc = sqlite3_step_orig(st); sqlite3_reset_orig(st);
  return rc == SQLITE_DONE ? SQLITE_OK : rc;
}
static void qcs_close_txn(sqlite3 *db) {
  for (int i = 0; i < QCS_NTXN; i++) if (qcs_txn[i].db == db) {
    sqlite3_finalize_orig(qcs_txn[i].begin); sqlite3_finalize_orig(qcs_txn[i].commit); memset(&qcs_txn[i], 0, sizeof qcs_txn[i]);
  }
}

static QcsRun *qcs_find(Vdbe *v) {   /* v's slot, or 0 */
  unsigned h = (unsigned)(((uintptr_t)v >> 4) * 2654435761u) % QCS_NRUN;
  for (unsigned i = 0; i < QCS_NRUN; i++) { QcsRun *x = &qcs_run[(h + i) % QCS_NRUN]; if (x->v == v) return x; if (!x->v) return 0; }
  return 0;
}
static QcsRun *qcs_slot(Vdbe *v) {   /* a free slot for v (no tombstones: qcs_drop re-inserts the cluster after a hole) */
  unsigned h = (unsigned)(((uintptr_t)v >> 4) * 2654435761u) % QCS_NRUN;
  if (qcs_nserving >= QCS_NRUN / 2) return 0;
  for (unsigned i = 0; i < QCS_NRUN; i++) { QcsRun *x = &qcs_run[(h + i) % QCS_NRUN]; if (!x->v) return x; }
  return 0;
}
static void qcs_free_vals(QcsRun *x) {   /* (one block: the values, then their text and blob bytes) */
  free(x->val); x->val = 0; x->nrow = x->ncol = x->pos = 0;
}
static void qcs_drop(QcsRun *x) {
  Vdbe *v = x->v;
  if (v && v->pResultRow == x->mem) v->pResultRow = 0;
  if (x->mem) { for (int i = 0; i < x->ncol; i++) sqlite3VdbeMemRelease(&x->mem[i]); sqlite3_free(x->mem); }
  qcs_free_vals(x); memset(x, 0, sizeof *x); qcs_nserving--;
  unsigned j = (unsigned)(x - qcs_run);   /* re-insert the rest of the cluster */
  for (j = (j + 1) % QCS_NRUN; qcs_run[j].v; j = (j + 1) % QCS_NRUN) {
    QcsRun t = qcs_run[j]; memset(&qcs_run[j], 0, sizeof t); qcs_nserving--;
    QcsRun *y = qcs_slot(t.v); *y = t; qcs_nserving++;
  }
}
static int qcs_collect(void *ctx, int nrow, int ncol, const QcVal *x) {   /* qc's rows (valid during the call), copied
                                                                            into one block: no allocation per value */
  QcsRun *r = ctx; size_t nv = (size_t)nrow * (size_t)ncol, bytes = 0;
  for (size_t k = 0; k < nv; k++) if (x[k].type == SQLITE_TEXT || x[k].type == SQLITE_BLOB) bytes += (size_t)x[k].n + 1;
  r->val = malloc(sizeof *r->val * (nv + 1) + bytes); if (!r->val) return SQLITE_NOMEM;
  r->nrow = nrow; r->ncol = ncol;
  char *z = (char *)(r->val + nv + 1);
  for (size_t k = 0; k < nv; k++) {
    QcsVal *o = &r->val[k]; memset(o, 0, sizeof *o); o->type = x[k].type;
    if (o->type == SQLITE_INTEGER) o->i = x[k].i;
    else if (o->type == SQLITE_FLOAT) o->r = x[k].r;
    else if (o->type == SQLITE_TEXT || o->type == SQLITE_BLOB) {
      o->n = x[k].n; o->z = z;
      if (o->n) memcpy(z, x[k].z, (size_t)o->n);
      z[o->n] = 0; z += o->n + 1;
    }
  }
  return SQLITE_OK;
}
static int qcs_row(QcsRun *x) {   /* the next row into the result row, or SQLITE_DONE */
  Vdbe *v = x->v;
  if (x->pos >= x->nrow) { qcs_drop(x); return SQLITE_DONE; }
  for (int i = 0; i < x->ncol; i++) {
    Mem *m = &x->mem[i]; const QcsVal *q = &x->val[x->pos * x->ncol + i];
    sqlite3VdbeMemRelease(m); m->flags = MEM_Null;
    if (q->type == SQLITE_INTEGER) sqlite3VdbeMemSetInt64(m, q->i);
    else if (q->type == SQLITE_FLOAT) sqlite3VdbeMemSetDouble(m, q->r);
    else if (q->type == SQLITE_TEXT) sqlite3VdbeMemSetStr(m, q->z, q->n, SQLITE_UTF8, SQLITE_STATIC);
    else if (q->type == SQLITE_BLOB) sqlite3VdbeMemSetStr(m, q->z, q->n, 0, SQLITE_STATIC);
  }
  x->pos++; qcs_rows++;
  v->pResultRow = x->mem;
  return SQLITE_ROW;
}

/* v is starting: qc's rows for it, first row handed out; -1: SQLite steps it */
static int qcs_start(Vdbe *v) {
  sqlite3 *db = v->db;
  if (!v->zSql || !v->readOnly || v->explain || db->nVdbeActive > 0 || db->xProgress) return -1;
  if (v->nResColumn == 0) return -1;   /* (BEGIN, COMMIT, PRAGMA without rows: nothing to serve) */
  qcs_starts++; qcs_last_v = v; qcs_last_served = 0; qcs_last_why = "not lifted";
  QcsText *t = getenv("QCS_STATS") ? qcs_txt(v->zSql) : 0;
  if (t) t->n++;
  if (!v->pQc && !v->qcWant) {
    qc_why = ""; qv_why = "";
    if (!sqlite3_qc((sqlite3_stmt *)v)) {
      if (!*qc_why) qc_why = *qv_why ? qv_why : "(no reason given)";   /* (qvm's lift keeps its reason in qv_why) */
      qcs_refused++; qcs_last_why = qc_why; if (t) { t->refused++; t->why = qc_why; } v->qcWant = 2; return -1; }
  } else if (!v->pQc && v->qcWant == 2) {   /* refused before (qcWant 2: this file's mark) */
    qcs_refused++; qcs_last_why = t && t->why ? t->why : "refused at an earlier lift"; if (t) t->refused++; return -1;
  }
  int began = 0, rc;
  QcsRun r; memset(&r, 0, sizeof r);
  /* the connection's trace and authorizer callbacks off while BEGIN/COMMIT run: the program must not see them */
  __typeof__(db->trace) tr = db->trace; u8 mt = db->mTrace; sqlite3_xauth au = db->xAuth;
  db->trace.xV2 = 0; db->mTrace = 0; db->xAuth = 0;
  if (db->autoCommit) {
    if (qcs_exec_txn(db, 0) != SQLITE_OK) { db->trace = tr; db->mTrace = mt; db->xAuth = au; qcs_err++; return -1; }
    began = 1;
  }
  qc_why = "";
  rc = sqlite3_qc_exec((sqlite3_stmt *)v, qcs_collect, &r);
  if (began) qcs_exec_txn(db, 1);
  db->trace = tr; db->mTrace = mt; db->xAuth = au;
  if (v->pQc) { int k = *(int *)v->pQc & 3; if (t) t->kind = k; }
  if (rc != SQLITE_OK) {
    qcs_free_vals(&r);
    if (rc == QC_FALLBACK) { qcs_fallback++; qcs_last_why = qc_why && *qc_why ? qc_why : "fallback"; if (t) { t->fallback++; t->why = qc_why; } }
    else { qcs_err++; qcs_last_why = "qc error"; }
    sqlite3_reset_orig((sqlite3_stmt *)v);   /* (clears an error qc may have left on the handle) */
    return -1;
  }
  QcsRun *x = qcs_slot(v);
  if (!x || !(r.mem = sqlite3_malloc64(sizeof(Mem) * (size_t)(r.ncol + 1)))) { qcs_free_vals(&r); qcs_skip++; return -1; }
  for (int i = 0; i < r.ncol; i++) { memset(&r.mem[i], 0, sizeof(Mem)); r.mem[i].db = db; r.mem[i].flags = MEM_Null; }
  r.v = v; *x = r; qcs_nserving++;
  qcs_served++; qcs_kind[*(int *)v->pQc & 3]++; qcs_last_served = 1;
  if (t) { t->served++; t->rows += r.nrow; }
  db->errCode = SQLITE_OK;
  return qcs_row(x);
}

static int sqlite3_step_orig(sqlite3_stmt *pStmt);
SQLITE_API int sqlite3_step(sqlite3_stmt *pStmt) {
  Vdbe *v = (Vdbe *)pStmt;
  if (qcs_off < 0) { qcs_off = getenv("QCS_OFF") != 0; atexit(qcs_atexit); }
  if (qcs_off || qcs_busy || !v || !v->db) return sqlite3_step_orig(pStmt);
  if (qcs_nserving) { QcsRun *x = qcs_find(v); if (x) return qcs_row(x); }
  if (v->eVdbeState != VDBE_READY_STATE) return sqlite3_step_orig(pStmt);   /* SQLite is stepping it */
  qcs_busy = 1; int rc = qcs_start(v); qcs_busy = 0;
  return rc >= 0 ? rc : sqlite3_step_orig(pStmt);
}
SQLITE_API int sqlite3_reset(sqlite3_stmt *pStmt) {
  if (qcs_nserving && pStmt) { QcsRun *x = qcs_find((Vdbe *)pStmt); if (x) qcs_drop(x); }
  return sqlite3_reset_orig(pStmt);
}
SQLITE_API int sqlite3_finalize(sqlite3_stmt *pStmt) {
  if (qcs_nserving && pStmt) { QcsRun *x = qcs_find((Vdbe *)pStmt); if (x) qcs_drop(x); }
  return sqlite3_finalize_orig(pStmt);
}
static int sqlite3_close_orig(sqlite3 *db);
static int sqlite3_close_v2_orig(sqlite3 *db);
SQLITE_API int sqlite3_close(sqlite3 *db) { qcs_close_txn(db); return sqlite3_close_orig(db); }
SQLITE_API int sqlite3_close_v2(sqlite3 *db) { qcs_close_txn(db); return sqlite3_close_v2_orig(db); }
/* for programs (bench/qrun.c): how pStmt's last start went. 1 specialised plan, 2 loop plan, 3 qvm: qc served it;
   0: SQLite ran it, *why says why (qc refused it, or fell back: qc's reason) */
SQLITE_API int qcs_info(sqlite3_stmt *pStmt, const char **why) {
  Vdbe *v = (Vdbe *)pStmt;
  if (v != qcs_last_v) { if (why) *why = "not started through qc (busy connection, no rows or not read-only)"; return 0; }
  if (why) *why = qcs_last_why;
  return qcs_last_served && v->pQc ? *(int *)v->pQc & 3 : 0;
}
