/* slt_qc.c: sqllogictest's SQLite engine (third_party/slt/src/slt_sqlite.c, public domain) with every query also run
** through qc and compared, value by value, with the interpreter. Built by tests/build-slt.sh as the harness's
** slt_sqlite.c, so sqllogictest.c compiles it with the amalgamation and qc in one unit (as the corpus does).
**
** For each query record:
**   1. the interpreter runs it as upstream does, and its values are kept (type and value);
**   2. a second handle is compiled (sqlite3_qc) and run QC_RUNS times (default 4: feedback, the regions' build, then
**      the plain loop) inside a transaction, as qc requires; each run's values are compared with the interpreter's;
**   3. the harness gets qc's rows (when it ran) rendered by SQLite's own value conversions, so sqllogictest's expected
**      results check qc's output too, independently of the comparison.
** A difference is printed as QCDIFF (the first QC_SHOW of them in full); at disconnect a QCSTAT line counts queries,
** what compiled into which tier, fallbacks and differences, and QCWHY lines give the reasons qc declined.
** QC_VM_ONLY=1 sends every compiled statement through qvm, as in the corpus. */
#include "sqlite3.c"
#include "qc.c"
#include <ctype.h>
#include <stdio.h>

typedef struct SQLiteConn { sqlite3 *db; unsigned flags; } SQLiteConn;
#define FG_INTEGRITY_CHECK 0x0001

static const char *skipWhitespace(const char *z) { while (isspace((unsigned char)*z)) z++; return z; }
static const char *skipToNextParameter(const char *z) { while (z[0] && z[0] != ';') z++; if (z[0] == ';') z++; return skipWhitespace(z); }

/* ---------------------------------------------------------------- statistics */
static long st_query, st_compiled, st_kind[4], st_runs, st_fallback, st_diff, st_diffq, st_interr, st_shown;
#define QC_NWHY 64
static struct { const char *why; long n; } st_why[QC_NWHY]; static int st_nwhy;
static void why_count(const char *w) {
  if (!w || !*w) w = "(none)";
  for (int i = 0; i < st_nwhy; i++) if (!strcmp(st_why[i].why, w)) { st_why[i].n++; return; }
  if (st_nwhy < QC_NWHY) { st_why[st_nwhy].why = w; st_why[st_nwhy++].n = 1; }   /* (qc_why strings are static) */
}

/* ---------------------------------------------------------------- values */
typedef struct Val { int type; i64 i; double r; char *z; int n; } Val;   /* z: malloced copy (text, blob) */
typedef struct Vals { Val *v; int n, cap; } Vals;
static void vals_push(Vals *a, int type, i64 i, double r, const void *z, int n) {
  if (a->n == a->cap) { a->cap = a->cap ? a->cap * 2 : 64; a->v = realloc(a->v, sizeof *a->v * (size_t)a->cap); if (!a->v) { fprintf(stderr, "oom\n"); exit(1); } }
  Val *x = &a->v[a->n++]; x->type = type; x->i = i; x->r = r; x->n = n; x->z = 0;
  if (type == SQLITE_TEXT || type == SQLITE_BLOB) { x->z = malloc((size_t)n + 1); if (n) memcpy(x->z, z, (size_t)n); x->z[n] = 0; }
}
static void vals_clear(Vals *a) { for (int k = 0; k < a->n; k++) free(a->v[k].z); a->n = 0; }
static void vals_free(Vals *a) { vals_clear(a); free(a->v); a->v = 0; a->cap = 0; }
static int val_eq(const Val *a, const Val *b) {
  if (a->type != b->type) return 0;
  switch (a->type) {
    case SQLITE_INTEGER: return a->i == b->i;
    case SQLITE_FLOAT: return memcmp(&a->r, &b->r, sizeof a->r) == 0;
    case SQLITE_TEXT: case SQLITE_BLOB: return a->n == b->n && (a->n == 0 || memcmp(a->z, b->z, (size_t)a->n) == 0);
  }
  return 1;
}
static const char *val_str(const Val *a, char *buf, int cap) {
  switch (a->type) {
    case SQLITE_INTEGER: snprintf(buf, (size_t)cap, "int %lld", (long long)a->i); break;
    case SQLITE_FLOAT: snprintf(buf, (size_t)cap, "real %.17g", a->r); break;
    case SQLITE_TEXT: snprintf(buf, (size_t)cap, "text '%.*s'", a->n < 60 ? a->n : 60, a->z); break;
    case SQLITE_BLOB: snprintf(buf, (size_t)cap, "blob(%d)", a->n); break;
    default: snprintf(buf, (size_t)cap, "null");
  }
  return buf;
}
static int qc_collect(void *ctx, int nrow, int ncol, const QcVal *v) {   /* qc's rows (valid during the call) */
  Vals *a = ctx;
  for (int k = 0; k < nrow * ncol; k++) {
    const QcVal *x = &v[k];
    vals_push(a, x->type, x->type == SQLITE_INTEGER ? x->i : 0, x->type == SQLITE_FLOAT ? x->r : 0, (x->type == SQLITE_TEXT || x->type == SQLITE_BLOB) ? x->z : 0, x->n);
  }
  return SQLITE_OK;
}

/* ---------------------------------------------------------------- the harness's rendering, from a value */
typedef struct ResAccum { char **azValue; int nAlloc, nUsed; } ResAccum;
static void appendValue(ResAccum *p, const char *zValue) {
  char *z = 0;
  if (zValue && !(z = sqlite3_mprintf("%s", zValue))) { fprintf(stderr, "out of memory at %s:%d\n", __FILE__, __LINE__); exit(1); }
  if (p->nUsed >= p->nAlloc) {
    p->nAlloc += 200;
    char **az = sqlite3_realloc(p->azValue, p->nAlloc * (int)sizeof(p->azValue[0]));
    if (!az) { fprintf(stderr, "out of memory at %s:%d\n", __FILE__, __LINE__); exit(1); }
    p->azValue = az;
  }
  p->azValue[p->nUsed++] = z;
}
/* as upstream's sqliteQuery formats sqlite3_column_*: the value in a Mem, read back through sqlite3_value_* */
static int render(sqlite3 *db, ResAccum *res, const Val *x, char t) {
  char zBuffer[200]; Mem m; sqlite3VdbeMemInit(&m, db, MEM_Null);
  if (x->type == SQLITE_NULL) { appendValue(res, "NULL"); return 0; }
  switch (x->type) {
    case SQLITE_INTEGER: sqlite3VdbeMemSetInt64(&m, x->i); break;
    case SQLITE_FLOAT: sqlite3VdbeMemSetDouble(&m, x->r); break;
    case SQLITE_TEXT: sqlite3VdbeMemSetStr(&m, x->z, x->n, SQLITE_UTF8, SQLITE_TRANSIENT); break;
    default: sqlite3VdbeMemSetStr(&m, x->z, x->n, 0, SQLITE_TRANSIENT); break;
  }
  switch (t) {
    case 'T': {
      const char *zValue = (const char *)sqlite3_value_text(&m);
      if (!zValue || zValue[0] == 0) zValue = "(empty)";
      appendValue(res, zValue);
      for (char *z = res->azValue[res->nUsed - 1]; *z; z++) if (*z < ' ' || *z > '~') *z = '@';
      break;
    }
    case 'I': sqlite3_snprintf(sizeof zBuffer, zBuffer, "%d", sqlite3_value_int(&m)); appendValue(res, zBuffer); break;
    case 'R': sqlite3_snprintf(sizeof zBuffer, zBuffer, "%.3f", sqlite3_value_double(&m)); appendValue(res, zBuffer); break;
    default: sqlite3VdbeMemRelease(&m); fprintf(stderr, "unknown character in type-string: %c\n", t); return 1;
  }
  sqlite3VdbeMemRelease(&m);
  return 0;
}

/* ---------------------------------------------------------------- the engine */
static int sqliteConnect(void *NotUsed, const char *zConnectStr, void **ppConn, const char *zParam) {
  (void)NotUsed;
  if (zConnectStr == 0) zConnectStr = "test.db";
  if (zConnectStr[0]) unlink(zConnectStr);
  SQLiteConn *p = sqlite3_malloc(sizeof *p); if (!p) return 1;
  memset(p, 0, sizeof *p);
  if (sqlite3_open(zConnectStr, &p->db) != SQLITE_OK) { sqlite3_free(p); return 1; }
  if (zParam) {
    zParam = skipWhitespace(zParam);
    while (zParam[0]) {
      if (strncmp(zParam, "optimizer=", 10) == 0) sqlite3_test_control(SQLITE_TESTCTRL_OPTIMIZATIONS, p->db, atoi(&zParam[10]));
      else if (strncmp(zParam, "integrity_check", 15) == 0) p->flags |= FG_INTEGRITY_CHECK;
      else { fprintf(stderr, "unknown parameter: [%s]\n", zParam); exit(1); }
      zParam = skipToNextParameter(zParam);
    }
  }
  sqlite3_exec(p->db, "PRAGMA synchronous=OFF", 0, 0, 0);
  *ppConn = p;
  return 0;
}
static int sqliteStatement(void *pConn, const char *zSql, int bQuiet) {
  SQLiteConn *p = pConn; (void)bQuiet;
  int rc = sqlite3_exec(p->db, zSql, 0, 0, 0);
  if (rc == SQLITE_OK && (p->flags & FG_INTEGRITY_CHECK)) {
    sqlite3_stmt *pStmt;
    if (sqlite3_prepare_v2(p->db, "PRAGMA integrity_check;", -1, &pStmt, 0) != SQLITE_OK) { fprintf(stderr, "cannot prepare integrity_check\n"); return 1; }
    const char *z;
    if (sqlite3_step(pStmt) != SQLITE_ROW) { fprintf(stderr, "cannot run integrity_check\n"); rc = 1; }
    else if (!(z = (const char *)sqlite3_column_text(pStmt, 0)) || strcmp(z, "ok")) { fprintf(stderr, "integrity_check returns: %s\n", z); rc = 1; }
    sqlite3_finalize(pStmt);
  }
  return rc != SQLITE_OK;
}
static void report(const char *zSql, int kind, int run, const char *what, const Vals *a, const Vals *b, int at) {
  st_diff++;
  if (st_shown >= (getenv("QC_SHOW") ? atoi(getenv("QC_SHOW")) : 20)) return;
  st_shown++;
  char x[128], y[128];
  fprintf(stderr, "QCDIFF tier %d run %d: %s\n  sql: %s\n", kind, run, what, zSql);
  if (at >= 0) fprintf(stderr, "  value %d: interp %s, qc %s (interp %d values, qc %d)\n", at,
                       at < a->n ? val_str(&a->v[at], x, sizeof x) : "-", at < b->n ? val_str(&b->v[at], y, sizeof y) : "-", a->n, b->n);
}
static int sqliteQuery(void *pConn, const char *zSql, const char *zType, char ***pazResult, int *pnResult) {
  SQLiteConn *p = pConn; sqlite3 *db = p->db; sqlite3_stmt *pStmt, *q = 0; ResAccum res; memset(&res, 0, sizeof res);
  Vals ia = {0}, qa = {0}, qk = {0}; int ncol = (int)strlen(zType), rc, ok = 0;
  if (sqlite3_prepare_v2(db, zSql, -1, &pStmt, 0) != SQLITE_OK) { sqlite3_finalize(pStmt); return 1; }
  if (ncol != sqlite3_column_count(pStmt)) {
    fprintf(stderr, "wrong number of result columns: expected %d but got %d\n", ncol, sqlite3_column_count(pStmt));
    sqlite3_finalize(pStmt); return 1;
  }
  st_query++;
  while ((rc = sqlite3_step(pStmt)) == SQLITE_ROW)   /* 1: the interpreter */
    for (int i = 0; i < ncol; i++) {
      int t = sqlite3_column_type(pStmt, i);
      if (t == SQLITE_INTEGER) vals_push(&ia, t, sqlite3_column_int64(pStmt, i), 0, 0, 0);
      else if (t == SQLITE_FLOAT) vals_push(&ia, t, 0, sqlite3_column_double(pStmt, i), 0, 0);
      else if (t == SQLITE_TEXT) { const unsigned char *z = sqlite3_column_text(pStmt, i); vals_push(&ia, t, 0, 0, z, sqlite3_column_bytes(pStmt, i)); }
      else if (t == SQLITE_BLOB) { const void *z = sqlite3_column_blob(pStmt, i); vals_push(&ia, t, 0, 0, z, sqlite3_column_bytes(pStmt, i)); }
      else vals_push(&ia, SQLITE_NULL, 0, 0, 0, 0);
    }
  int interpOk = rc == SQLITE_DONE;
  sqlite3_finalize(pStmt);
  /* 2: qc, on its own handle */
  int kind = 0, runs = getenv("QC_RUNS") ? atoi(getenv("QC_RUNS")) : 4;
  if (sqlite3_prepare_v2(db, zSql, -1, &q, 0) == SQLITE_OK && q) {
    qc_why = "";
    if (sqlite3_qc(q)) {
      st_compiled++; kind = *(int *)((Vdbe *)q)->pQc & 3; st_kind[kind]++;
      for (int r = 0; r < runs; r++) {
        int began = sqlite3_get_autocommit(db) && sqlite3_exec(db, "BEGIN", 0, 0, 0) == SQLITE_OK;
        vals_clear(&qa); qc_why = "";
        int qrc = sqlite3_qc_exec(q, qc_collect, &qa);
        if (began) sqlite3_exec(db, "COMMIT", 0, 0, 0);
        st_runs++;
        if (qrc == QC_FALLBACK) {
          st_fallback++; why_count(qc_why);
          const char *ws = getenv("QC_WHYSQL");   /* the SQL behind one fallback reason (the first 5) */
          static int nws; if (ws && strstr(qc_why, ws) && nws++ < 5) fprintf(stderr, "QCWHYSQL %s run %d: %s\n", qc_why, r, zSql);
          continue;
        }
        if (qrc != SQLITE_OK) { report(zSql, kind, r, "qc returned an error code", &ia, &qa, -1); st_diffq++; break; }
        if (!interpOk) { report(zSql, kind, r, "qc returned rows where the interpreter failed", &ia, &qa, -1); st_interr++; st_diffq++; break; }
        int at = -1;
        for (int k = 0; k < ia.n || k < qa.n; k++) if (k >= ia.n || k >= qa.n || !val_eq(&ia.v[k], &qa.v[k])) { at = k; break; }
        if (at >= 0) { report(zSql, kind, r, "values differ", &ia, &qa, at); st_diffq++; break; }
        if (!ok) { ok = 1; Vals t = qk; qk = qa; qa = t; }   /* the first run that ran: what the harness checks */
      }
    } else {
      why_count(qc_why);
      const char *ws = getenv("QC_WHYSQL");
      static int nwl; if (ws && strstr(qc_why, ws) && nwl++ < 5) fprintf(stderr, "QCWHYSQL %s (not compiled): %s\n", qc_why, zSql);
    }
  }
  sqlite3_finalize(q);
  /* 3: rows for the harness: qc's when it ran (sqllogictest then checks them against its expected results) */
  const Vals *out = ok ? &qk : &ia;
  for (int k = 0; k + ncol <= out->n; k += ncol)
    for (int i = 0; i < ncol; i++) if (render(db, &res, &out->v[k + i], zType[i])) { vals_free(&ia); vals_free(&qa); vals_free(&qk); return 1; }
  vals_free(&ia); vals_free(&qa); vals_free(&qk);
  *pazResult = res.azValue; *pnResult = res.nUsed;
  return 0;
}
static int sqliteFreeResults(void *pConn, char **azResult, int nResult) {
  (void)pConn;
  for (int i = 0; i < nResult; i++) sqlite3_free(azResult[i]);
  sqlite3_free(azResult);
  return 0;
}
static int sqliteDisconnect(void *pConn) {
  SQLiteConn *p = pConn;
  fprintf(stderr, "QCSTAT queries %ld compiled %ld plan %ld loops %ld vm %ld runs %ld fallbacks %ld differences %ld diff-queries %ld interp-errors %ld\n",
          st_query, st_compiled, st_kind[1], st_kind[2], st_kind[3], st_runs, st_fallback, st_diff, st_diffq, st_interr);
  for (int i = 0; i < st_nwhy; i++) fprintf(stderr, "QCWHY %ld %s\n", st_why[i].n, st_why[i].why);
  int rc = sqlite3_close(p->db);
  sqlite3_free(p);
  sqlite3_qc_release();
  if (sqlite3_memory_used() > 0) { fprintf(stderr, "memory leak after connection close: %lld bytes\n", (long long)sqlite3_memory_used()); rc = 1; }
  return rc;
}
static int sqliteGetEngineName(void *pConn, const char **zName) { (void)pConn; *zName = "SQLite"; return 0; }
void registerSqlite(void) {
  static const DbEngine sqliteDbEngine = {
    "SQLite", 0, sqliteConnect, sqliteGetEngineName, sqliteStatement, sqliteQuery, sqliteFreeResults, sqliteDisconnect
  };
  sqllogictestRegisterEngine(&sqliteDbEngine);
}
