// lean_oracle: the Lean model's answers (lean/Oracle.lean) against SQLite and turbo. Reads the oracle's cases and
// checks, value by value: sqlite3MemCompare, qv_cmp, qv_numcmp, qg_order, qg_cmp_jump, qv_compare_op (C lines); the
// integer index probe qc_idxkey_at / qc_idx_cmp_kind on a built cell, and SQLite's record compare (I); the hash set's
// key equality and hash (H); a C reference of the planned sort-key prefix, and that a strict prefix order implies
// sqlite3MemCompare's (K, with the C pairs). Then each table (T) through SQL, by the interpreter and by qc (plan,
// feedback, regions), against the model, for a column of any values, one of NULL/INTEGER/TEXT (qcg's general plans) and
// one of integers (the regions' speculation): ORDER BY (sorter and index, top-N), joins on comparisons, an integer
// index range, count(DISTINCT), min/max; and ORDER BY / < under NOCASE. Records (X): qc_decode against its model, and
// each record written into a table page (sqlite_dbpage) and read by SQL, the interpreter and qc against the model of
// OP_Column, corrupt records included. LIKE (LT): like() against the model, and LIKE through SQL by the interpreter
// and qc, with and without case folding, every ESCAPE choice, and one pattern against an indexed column (the LIKE
// optimisation's range). Run as is and with QC_VM_ONLY=1 (LEAN_WHY=1: why qc fell back).
//   lean_oracle CASES
#include "sqlite3.c"
#include "qc.c"
#include <stdio.h>
#include <stdlib.h>

typedef struct { int t; i64 i; double r; u8 z[256]; int n; } V;   /* t: SQLITE_NULL ... ; NaN reals are kept (r) */

static int hexv(int c) { return c <= '9' ? c - '0' : c - 'a' + 10; }
static int parse(const char *s, V *v) {
  memset(v, 0, sizeof *v);
  switch (s[0]) {
    case 'n': v->t = SQLITE_NULL; return 1;
    case 'i': v->t = SQLITE_INTEGER; v->i = strtoll(s + 1, 0, 10); return 1;
    case 'r': { u64 b = strtoull(s + 1, 0, 16); memcpy(&v->r, &b, 8); v->t = SQLITE_FLOAT; return 1; }
    case 't': case 'b':
      v->t = s[0] == 't' ? SQLITE_TEXT : SQLITE_BLOB;
      for (const char *p = s + 1; p[0] && p[1] && v->n < 256; p += 2) v->z[v->n++] = (u8)(hexv(p[0]) * 16 + hexv(p[1]));
      return 1;
  }
  return 0;
}
static int isnan_v(const V *v) { return v->t == SQLITE_FLOAT && v->r != v->r; }
static void fmt(const V *v, char *o, size_t n) {
  switch (v->t) {
    case SQLITE_NULL: snprintf(o, n, "NULL"); break;
    case SQLITE_INTEGER: snprintf(o, n, "%lld", (long long)v->i); break;
    case SQLITE_FLOAT: snprintf(o, n, "%.17g", v->r); break;
    default: { int k = snprintf(o, n, "%s'", v->t == SQLITE_TEXT ? "x" : "X"); for (int j = 0; j < v->n && k + 3 < (int)n; j++) k += snprintf(o + k, n - k, "%02x", v->z[j]); snprintf(o + k, n - k, "'%s", v->t == SQLITE_TEXT ? "(text)" : ""); }
  }
}
static void to_mem(Mem *m, const V *v, sqlite3 *db) {
  sqlite3VdbeMemInit(m, db, MEM_Null);
  switch (v->t) {
    case SQLITE_INTEGER: sqlite3VdbeMemSetInt64(m, v->i); break;
    case SQLITE_FLOAT: sqlite3VdbeMemSetDouble(m, v->r); break;   /* (NaN: NULL) */
    case SQLITE_TEXT: sqlite3VdbeMemSetStr(m, (const char *)v->z, v->n, SQLITE_UTF8, SQLITE_STATIC); break;
    case SQLITE_BLOB: sqlite3VdbeMemSetStr(m, (const char *)v->z, v->n, 0, SQLITE_STATIC); break;
  }
}
static void to_qc(QcVal *q, const V *v) {   /* as qc's decoders hand values out: NaN reads as NULL */
  memset(q, 0, sizeof *q); q->type = v->t;
  if (v->t == SQLITE_INTEGER) q->i = v->i;
  else if (v->t == SQLITE_FLOAT) { if (isnan_v(v)) q->type = SQLITE_NULL; else q->r = v->r; }
  else if (v->t == SQLITE_TEXT || v->t == SQLITE_BLOB) { q->z = v->z; q->n = v->n; }
}
static int sgn(i64 x) { return x < 0 ? -1 : x > 0; }
static int isnum(const V *v) { return v->t == SQLITE_INTEGER || (v->t == SQLITE_FLOAT && !isnan_v(v)); }
static int isnull(const V *v) { return v->t == SQLITE_NULL || isnan_v(v); }

/* the planned sort-key prefix (lean/Turbo/SortKey.lean), as C would write it */
static u64 key_ref(const V *v) {
  if (isnull(v)) return 0;
  if (isnum(v)) {
    i64 n;
    if (v->t == SQLITE_INTEGER) n = v->i;
    else if (v->r >= 9223372036854775808.0) n = INT64_MAX;
    else if (v->r < -9223372036854775808.0) n = INT64_MIN;
    else n = (i64)floor(v->r);
    return (1ull << 62) | (((u64)n ^ (1ull << 63)) >> 2);
  }
  u64 be = 0;
  for (int j = 0; j < 7; j++) be = (be << 8) | (j < v->n ? v->z[j] : 0);
  return ((v->t == SQLITE_TEXT ? 2ull : 3ull) << 62) | (be << 3) | (u64)(v->n < 7 ? v->n : 7);
}

/* a leaf index cell holding v as its only field: [payload size][header size][serial type][body] */
static int cell(const V *v, u8 *c) {
  u8 body[300]; int nb = 0; u64 t;
  if (v->t == SQLITE_NULL) t = 0;
  else if (v->t == SQLITE_INTEGER) {
    i64 x = v->i; u64 u = x < 0 ? ~(u64)x : (u64)x;
    if (x == 0) t = 8; else if (x == 1) t = 9;
    else if (u <= 127) t = 1; else if (u <= 32767) t = 2; else if (u <= 8388607) t = 3; else if (u <= 2147483647) t = 4;
    else if (u <= 140737488355327LL) t = 5; else t = 6;
    static const int W[] = {0, 1, 2, 3, 4, 6, 8, 8, 0, 0};
    for (int k = W[t] - 1; k >= 0; k--) body[nb++] = (u8)((u64)x >> (8 * k));
  } else if (v->t == SQLITE_FLOAT) { u64 b; memcpy(&b, &v->r, 8); t = 7; for (int k = 7; k >= 0; k--) body[nb++] = (u8)(b >> (8 * k)); }   /* (a NaN as is: a crafted record) */
  else { t = (u64)(v->t == SQLITE_TEXT ? 13 : 12) + 2u * (u64)v->n; memcpy(body, v->z, (size_t)v->n); nb = v->n; }
  u8 hdr[12]; int nh = sqlite3PutVarint(hdr + 1, t) + 1; hdr[0] = (u8)nh;   /* (header < 128 bytes) */
  int sz = nh + nb, k = sqlite3PutVarint(c, (u64)sz);
  memcpy(c + k, hdr, (size_t)nh); memcpy(c + k + nh, body, (size_t)nb);
  return k + sz;
}

static long nchk, nbad;
#define BAD(...) do { nbad++; if (nbad <= 60) { fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static const u8 OPS[6] = {OP_Lt, OP_Le, OP_Eq, OP_Ne, OP_Gt, OP_Ge};
static const char *OPN[6] = {"<", "<=", "=", "<>", ">", ">="};
static int holds(int op, int c) { switch (op) { case OP_Lt: return c < 0; case OP_Le: return c <= 0; case OP_Eq: return c == 0; case OP_Ne: return c != 0; case OP_Gt: return c > 0; default: return c >= 0; } }

static sqlite3 *db; static CollSeq *nocase; static KeyInfo *ki1; static QvX X;

static void check_pair(char coll, const V *a, const V *b, int exp) {
  char sa[700], sb[700]; fmt(a, sa, sizeof sa); fmt(b, sb, sizeof sb);
  const CollSeq *cs = coll == 'N' ? nocase : 0;
  Mem ma, mb; to_mem(&ma, a, db); to_mem(&mb, b, db);
  int c = sgn(sqlite3MemCompare(&ma, &mb, cs)); nchk++;
  if (c != exp) BAD("sqlite3MemCompare(%s, %s, %s) = %d, model %d", sa, sb, coll == 'N' ? "NOCASE" : "BINARY", c, exp);
  QcVal qa, qb; to_qc(&qa, a); to_qc(&qb, b);
  c = sgn(qv_cmp(&X, &qa, &qb, cs)); nchk++;
  if (c != exp) BAD("qv_cmp(%s, %s, %s) = %d, model %d", sa, sb, coll == 'N' ? "NOCASE" : "BINARY", c, exp);
  if (isnum(a) && isnum(b)) { c = sgn(qv_numcmp(&ma, &mb)); nchk++; if (c != exp) BAD("qv_numcmp(%s, %s) = %d, model %d", sa, sb, c, exp); }
  int simple = (qa.type == SQLITE_NULL || qa.type == SQLITE_INTEGER || qa.type == SQLITE_TEXT) && (qb.type == SQLITE_NULL || qb.type == SQLITE_INTEGER || qb.type == SQLITE_TEXT);
  if (coll == 'B' && simple) { c = sgn(qg_order(&qa, &qb)); nchk++; if (c != exp) BAD("qg_order(%s, %s) = %d, model %d", sa, sb, c, exp); }
  int anynull = isnull(a) || isnull(b);
  for (int k = 0; k < 6; k++) {
    if (coll == 'B') {
      static const u8 P5[3] = {SQLITE_AFF_BLOB, SQLITE_AFF_TEXT, SQLITE_AFF_BLOB | SQLITE_JUMPIFNULL};
      for (int p = 0; p < 3; p++) {
        int j = qg_cmp_jump(OPS[k], P5[p], &qa, &qb); if (j < 0) continue;
        int e = anynull ? (P5[p] & SQLITE_JUMPIFNULL) != 0 : holds(OPS[k], exp); nchk++;
        if (j != e) BAD("qg_cmp_jump(%s %s %s, p5 %#x) = %d, model %d", sa, OPN[k], sb, P5[p], j, e);
      }
    }
    Mem R[2]; to_mem(&R[1], a, db); to_mem(&R[0], b, db);   /* r[P3] = a, r[P1] = b: a <op> b */
    Op op; memset(&op, 0, sizeof op); op.opcode = OPS[k]; op.p1 = 0; op.p3 = 1; op.p5 = SQLITE_AFF_BLOB;
    if (cs) { op.p4type = P4_COLLSEQ; op.p4.pColl = (CollSeq *)cs; }
    X.r = R;
    int j = qv_compare_op(&X, &op), e = anynull ? 0 : holds(OPS[k], exp); nchk++;
    if (j != e) BAD("qv_compare_op(%s %s %s, %s) = %d, model %d", sa, OPN[k], sb, cs ? "NOCASE" : "BINARY", j, e);
    sqlite3VdbeMemRelease(&R[0]); sqlite3VdbeMemRelease(&R[1]);
  }
  if (coll == 'B') {
    u64 ka = key_ref(a), kb = key_ref(b); nchk++;
    if ((ka < kb && exp >= 0) || (ka > kb && exp <= 0)) BAD("sort key: key(%s) = %016llx, key(%s) = %016llx, model order %d", sa, (unsigned long long)ka, sb, (unsigned long long)kb, exp);
  }
  sqlite3VdbeMemRelease(&ma); sqlite3VdbeMemRelease(&mb);
}

static void check_idx(const V *v, i64 key, int exp) {
  char sv[700]; fmt(v, sv, sizeof sv);
  u8 buf[400]; memset(buf, 0, sizeof buf); int n = cell(v, buf);
  MemPage pg; memset(&pg, 0, sizeof pg); pg.leaf = 1; pg.maxLocal = 4000;
  i64 k = 0; int kind = qc_idxkey_at(&pg, buf, buf + n + 8, &k);
  int c = qc_idx_cmp_kind(kind, k, key); nchk++;
  if (c != exp) BAD("qc_idx_cmp(cell %s, key %lld) = %d (kind %d, %lld), model %d", sv, (long long)key, c, kind, (long long)k, exp);
  Mem m; sqlite3VdbeMemInit(&m, db, MEM_Int); m.u.i = key;
  UnpackedRecord r; memset(&r, 0, sizeof r); r.pKeyInfo = ki1; r.nField = 1; r.aMem = &m; r.default_rc = 0;
  int hs; u32 sz = 0; hs = getVarint32(buf, sz);
  c = sgn(sqlite3VdbeFindCompare(&r)((int)sz, buf + hs, &r)); nchk++;
  if (c != exp) BAD("SQLite's record compare (cell %s, key %lld) = %d, model %d", sv, (long long)key, c, exp);
}

static void check_hk(const V *a, const V *b, int exp) {
  char sa[700], sb[700]; fmt(a, sa, sizeof sa); fmt(b, sb, sizeof sb);
  QcVal qa, qb; to_qc(&qa, a); to_qc(&qb, b); QvHk ka, kb; qv_hk_val(&qa, &ka); qv_hk_val(&qb, &kb);
  int e = qv_hk_eq(&ka, &kb, 1); nchk++;
  if (e != exp) BAD("qv_hk_eq(%s, %s) = %d, model %d", sa, sb, e, exp);
  if (e && qv_hk_hash(&ka, 1) != qv_hk_hash(&kb, 1)) { nchk++; BAD("qv_hk_hash differs for equal keys %s, %s", sa, sb); }
}

/* ---------------------------------------------------------------- tables through SQL */
typedef struct { int n, cap; V *v; int ncol; } Rows;
static void rows_add(Rows *r, const V *v) { if (r->n == r->cap) { r->cap = r->cap ? 2 * r->cap : 64; r->v = realloc(r->v, sizeof *r->v * (size_t)r->cap); } r->v[r->n++] = *v; }
static int qc_cb(void *ctx, int nrow, int ncol, const QcVal *val) {
  Rows *r = ctx; r->n = 0; r->ncol = ncol;
  for (int i = 0; i < nrow * ncol; i++) {
    V v; memset(&v, 0, sizeof v); v.t = val[i].type;
    if (v.t == SQLITE_INTEGER) v.i = val[i].i; else if (v.t == SQLITE_FLOAT) v.r = val[i].r;
    else if (v.t == SQLITE_TEXT || v.t == SQLITE_BLOB) { v.n = val[i].n < 256 ? val[i].n : 256; memcpy(v.z, val[i].z, (size_t)v.n); }
    rows_add(r, &v);
  }
  return 0;
}
static void ex(const char *q) { char *e = 0; if (sqlite3_exec(db, q, 0, 0, &e)) { fprintf(stderr, "lean_oracle: %s: %s\n", q, e); exit(2); } }
static void interp_rows(sqlite3_stmt *p, Rows *r) {
  r->n = 0; r->ncol = sqlite3_column_count(p);
  while (sqlite3_step(p) == SQLITE_ROW)
    for (int i = 0; i < r->ncol; i++) {
      V v; memset(&v, 0, sizeof v); v.t = sqlite3_column_type(p, i);
      if (v.t == SQLITE_INTEGER) v.i = sqlite3_column_int64(p, i); else if (v.t == SQLITE_FLOAT) v.r = sqlite3_column_double(p, i);
      else if (v.t != SQLITE_NULL) { v.n = sqlite3_column_bytes(p, i); const void *z = v.t == SQLITE_TEXT ? (const void *)sqlite3_column_text(p, i) : sqlite3_column_blob(p, i); if (v.n > 256) v.n = 256; memcpy(v.z, z, (size_t)v.n); }
      rows_add(r, &v);
    }
  sqlite3_reset(p);
}
/* the check a query's rows must pass: ids (in order), count + FNV of id pairs, one count, min/max by order */
typedef enum { X_IDS, X_PAIRS, X_COUNT, X_MINMAX, X_VALS } Kind;   /* X_VALS: these values, type and value */
typedef struct { Kind k; int ids[64], nids; long cnt; u64 h; V mm[2]; V vals[64]; int nvals; } Exp;
static int same_v(const V *a, const V *b) {
  if (a->t != b->t) return 0;
  switch (a->t) {
    case SQLITE_INTEGER: return a->i == b->i;
    case SQLITE_FLOAT: return a->r == b->r;
    case SQLITE_NULL: return 1;
    default: return a->n == b->n && !memcmp(a->z, b->z, (size_t)a->n);
  }
}
static int rows_ok(const Rows *r, const Exp *e) {
  switch (e->k) {
    case X_IDS:
      if (r->n != e->nids) return 0;
      for (int i = 0; i < r->n; i++) if (r->v[i].t != SQLITE_INTEGER || r->v[i].i != e->ids[i]) return 0;
      return 1;
    case X_PAIRS: {
      if (r->n != 2 * e->cnt) return 0;
      u64 h = 14695981039346656037ULL;
      for (int i = 0; i < r->n; i++) h = (h ^ (u64)r->v[i].i) * 1099511628211ULL;
      return h == e->h;
    }
    case X_COUNT: return r->n == 1 && r->v[0].t == SQLITE_INTEGER && r->v[0].i == e->cnt;
    case X_VALS:
      if (r->n != e->nvals) return 0;
      for (int i = 0; i < r->n; i++) if (!same_v(&r->v[i], &e->vals[i])) {
        char x[700], y[700]; fmt(&r->v[i], x, sizeof x); fmt(&e->vals[i], y, sizeof y);
        fprintf(stderr, "  row %d: %s, model %s\n", i + 1, x, y); return 0;
      }
      return 1;
    default: {
      if (r->n != 2) return 0;
      for (int j = 0; j < 2; j++) {
        Mem a, b; to_mem(&a, &r->v[j], db); to_mem(&b, &e->mm[j], db);
        int c = sqlite3MemCompare(&a, &b, 0); sqlite3VdbeMemRelease(&a); sqlite3VdbeMemRelease(&b);
        if (c || (r->v[j].t == SQLITE_NULL) != isnull(&e->mm[j])) return 0;
      }
      return 1;
    }
  }
}
static long qcmp, qfell, qdiff, idiff, nq;
static void bind_v(sqlite3_stmt *s, int i, const V *v) {
  switch (v->t) {
    case SQLITE_INTEGER: sqlite3_bind_int64(s, i, v->i); break;
    case SQLITE_FLOAT: sqlite3_bind_double(s, i, v->r); break;   /* (NaN binds as NULL) */
    case SQLITE_TEXT: sqlite3_bind_text(s, i, (const char *)v->z, v->n, SQLITE_TRANSIENT); break;
    case SQLITE_BLOB: sqlite3_bind_blob(s, i, v->z, v->n, SQLITE_TRANSIENT); break;
    default: sqlite3_bind_null(s, i);
  }
}
static void run_query(const char *sql, const Exp *e, int nbind, const V *bv) {
  sqlite3_stmt *s, *p;
  if (sqlite3_prepare_v2(db, sql, -1, &s, 0) || sqlite3_prepare_v2(db, sql, -1, &p, 0)) { fprintf(stderr, "lean_oracle: prepare %s: %s\n", sql, sqlite3_errmsg(db)); exit(2); }
  for (int i = 0; i < nbind; i++) { bind_v(s, i + 1, &bv[i]); bind_v(p, i + 1, &bv[i]); }
  char bs[2][700] = {"", ""}; for (int i = 0; i < nbind && i < 2; i++) fmt(&bv[i], bs[i], sizeof bs[i]);
  nq++;
  Rows a = {0}, b = {0}; int lifted = 0;
  for (int rep = 0; rep < 3; rep++) {   /* the plan, its feedback, its regions */
    ex("BEGIN"); int rc = QC_FALLBACK;
    if (rep == 0) lifted = sqlite3_qc(s);
    if (lifted) rc = sqlite3_qc_exec(s, qc_cb, &a);
    interp_rows(p, &b); ex("COMMIT");
    if (rep == 0 && !rows_ok(&b, e)) {
      idiff++;
      if (idiff <= 20) fprintf(stderr, "SQLite vs model: %s (%s %s): %d values\n", sql, bs[0], bs[1], b.n);
    }
    if (rc != SQLITE_OK) { qfell++; if (getenv("LEAN_WHY")) fprintf(stderr, "fell back (%s%s): %s\n", lifted ? "" : "not lifted: ", qc_why, sql); continue; }
    qcmp++;
    if (!rows_ok(&a, e)) { qdiff++; if (qdiff <= 20) fprintf(stderr, "qc vs model (run %d): %s (%s %s): %d values\n", rep, sql, bs[0], bs[1], a.n); }
  }
  free(a.v); free(b.v); sqlite3_finalize(s); sqlite3_finalize(p);
}
static void parse_ids(char *rest, Exp *e) { e->k = X_IDS; e->nids = 0; for (char *t = strtok(rest, " \n"); t && e->nids < 64; t = strtok(0, " \n")) e->ids[e->nids++] = atoi(t); }

/* ---------------------------------------------------------------- records (X lines) */
/* the record written as the only cell of a table's leaf page (page `pgno`, rowid 1), through sqlite_dbpage */
static sqlite3 *rdb; static int rpgsz;
static void rex(const char *q) { char *e = 0; if (sqlite3_exec(rdb, q, 0, 0, &e)) { fprintf(stderr, "lean_oracle: %s: %s\n", q, e); exit(2); } }
static void put_page(int pgno, const u8 *rec, int n) {
  u8 *pg = calloc(1, (size_t)rpgsz), cell[600]; int k = sqlite3PutVarint(cell, (u64)n); k += sqlite3PutVarint(cell + k, 1);
  memcpy(cell + k, rec, (size_t)n); k += n;
  int at = rpgsz - k; memcpy(pg + at, cell, (size_t)k);
  pg[0] = 0x0d; pg[3] = 0; pg[4] = 1; pg[5] = (u8)(at >> 8); pg[6] = (u8)at; pg[8] = (u8)(at >> 8); pg[9] = (u8)at;
  sqlite3_stmt *s; sqlite3_prepare_v2(rdb, "UPDATE sqlite_dbpage SET data = ?2 WHERE pgno = ?1", -1, &s, 0);
  sqlite3_bind_int(s, 1, pgno); sqlite3_bind_blob(s, 2, pg, rpgsz, SQLITE_STATIC);
  if (sqlite3_step(s) != SQLITE_DONE) { fprintf(stderr, "lean_oracle: dbpage: %s\n", sqlite3_errmsg(rdb)); exit(2); }
  sqlite3_finalize(s); free(pg);
}
static long xrec, xfid, xlen, xwrong, xe2e, xsq, xqlen, xqwrong, xqcmp, xqfell;
static int vals_eq(const V *a, int na, const V *b, int nb) { if (na != nb) return 0; for (int i = 0; i < na; i++) if (!same_v(&a[i], &b[i])) return 0; return 1; }
/* one query of the record's table: the interpreter (rows or an error) and qc against the model (`spec`, c = corrupt) */
static void rec_query(const char *sql, const int *cols, int nc, char spec[6][700]) {
  int corrupt = 0; V want[6];
  for (int j = 0; j < nc; j++) { if (spec[cols[j]][0] == 'c') corrupt = 1; else parse(spec[cols[j]], &want[j]); }
  sqlite3_stmt *p, *s; sqlite3_prepare_v2(rdb, sql, -1, &p, 0); sqlite3_prepare_v2(rdb, sql, -1, &s, 0);
  Rows b = {0}; b.ncol = nc; int rc;
  while ((rc = sqlite3_step(p)) == SQLITE_ROW)
    for (int i = 0; i < nc; i++) {
      V v; memset(&v, 0, sizeof v); v.t = sqlite3_column_type(p, i);
      if (v.t == SQLITE_INTEGER) v.i = sqlite3_column_int64(p, i); else if (v.t == SQLITE_FLOAT) v.r = sqlite3_column_double(p, i);
      else if (v.t != SQLITE_NULL) { v.n = sqlite3_column_bytes(p, i); memcpy(v.z, v.t == SQLITE_TEXT ? (const void *)sqlite3_column_text(p, i) : sqlite3_column_blob(p, i), (size_t)v.n); }
      rows_add(&b, &v);
    }
  int interr = rc != SQLITE_DONE; xe2e++;
  if (interr != corrupt || (!corrupt && !vals_eq(b.v, b.n, want, nc))) { xsq++; if (xsq <= 10) fprintf(stderr, "record: SQLite vs model: %s: %s, model %s\n", sql, interr ? sqlite3_errmsg(rdb) : "rows", corrupt ? "corrupt" : "rows"); }
  sqlite3_finalize(p);
  for (int rep = 0; rep < 3; rep++) {
    rex("BEGIN"); Rows a = {0}; int st = QC_FALLBACK;
    if (sqlite3_qc(s)) st = sqlite3_qc_exec(s, qc_cb, &a);
    rex("COMMIT");
    if (st != SQLITE_OK) { xqfell++; free(a.v); continue; }
    xqcmp++;
    if (corrupt) { xqlen++; if (xqlen <= 5) fprintf(stderr, "record: qc returned %d values where SQLite reports corruption: %s\n", a.n, sql); }
    else if (!vals_eq(a.v, a.n, want, nc)) { xqwrong++; if (xqwrong <= 10) fprintf(stderr, "record: qc's values differ from SQLite's: %s\n", sql); }
    free(a.v);
  }
  sqlite3_finalize(s); free(b.v);
}
static void check_record(char *line) {
  char *bar = strchr(line, '|'); if (!bar) return; *bar = 0;
  char *tok = strtok(line + 2, " \n"); u8 rec[600]; int n = 0;
  for (const char *p = tok; p[0] && p[1] && n < 600; p += 2) rec[n++] = (u8)(hexv(p[0]) * 16 + hexv(p[1]));
  char spec[6][700]; for (int j = 0; j < 6; j++) { tok = strtok(0, " \n"); snprintf(spec[j], sizeof spec[j], "%s", tok ? tok : "c"); }
  V qm[6]; int nqm = 0, qmf = 0;
  for (char *t = strtok(bar + 1, " \n"); t; t = strtok(0, " \n")) { if (!strcmp(t, "f")) qmf = 1; else if (nqm < 6) parse(t, &qm[nqm++]); }
  xrec++;
  /* qc_decode itself (the record padded with zeros, as a cell is followed by more page) against the model of it */
  u8 buf[700]; memset(buf, 0, sizeof buf); memcpy(buf, rec, (size_t)n);
  QcVal cv[6]; int ok = qc_decode(buf, (u32)n, 0x3f, cv);
  V got[6]; for (int j = 0; ok && j < 6; j++) { memset(&got[j], 0, sizeof got[j]); got[j].t = cv[j].type; if (cv[j].type == SQLITE_INTEGER) got[j].i = cv[j].i; else if (cv[j].type == SQLITE_FLOAT) got[j].r = cv[j].r; else if (cv[j].type == SQLITE_TEXT || cv[j].type == SQLITE_BLOB) { got[j].n = cv[j].n; memcpy(got[j].z, cv[j].z, (size_t)cv[j].n); } }
  if (ok == qmf || (ok && !vals_eq(got, 6, qm, nqm))) xfid++;   /* (the model reads nothing past the record) */
  if (ok) {
    int anyc = 0, wrong = 0;
    for (int j = 0; j < 6; j++) { if (spec[j][0] == 'c') anyc = 1; else { V w; parse(spec[j], &w); if (!same_v(&got[j], &w)) wrong = 1; } }
    if (anyc) xlen++;
    if (wrong) { xwrong++; if (xwrong <= 5) fprintf(stderr, "record: qc_decode's value differs from OP_Column's: %s\n", line + 2); }
  }
  /* end to end: the record in two tables (untyped; INTEGER/TEXT columns: the shaped decoders) */
  if (!rdb) {
    remove("build/lean-rec.db"); if (sqlite3_open("build/lean-rec.db", &rdb) != SQLITE_OK) exit(2);
    rex("CREATE TABLE r(c0, c1, c2, c3, c4, c5); CREATE TABLE r2(c0 INTEGER, c1 TEXT, c2 INTEGER, c3 TEXT, c4 INTEGER, c5);"
        "INSERT INTO r VALUES (1, 2, 3, 4, 5, 6); INSERT INTO r2 VALUES (1, 2, 3, 4, 5, 6)");
    sqlite3_stmt *s; sqlite3_prepare_v2(rdb, "PRAGMA page_size", -1, &s, 0); sqlite3_step(s); rpgsz = sqlite3_column_int(s, 0); sqlite3_finalize(s);
  }
  if (n > 500) return;
  put_page(2, rec, n); put_page(3, rec, n);
  static const int ALL[6] = {0, 1, 2, 3, 4, 5}, ONE[1] = {1}, LAST[1] = {5};
  static const char *TQ[2][4] = {{"SELECT c0, c1, c2, c3, c4, c5 FROM r", "SELECT c1 FROM r", "SELECT c5 FROM r WHERE rowid = 1", "SELECT c0, c1, c2, c3, c4, c5 FROM r WHERE rowid = 1"},
                                 {"SELECT c0, c1, c2, c3, c4, c5 FROM r2", "SELECT c1 FROM r2", "SELECT c5 FROM r2 WHERE rowid = 1", "SELECT c0, c1, c2, c3, c4, c5 FROM r2 WHERE rowid = 1"}};
  for (int t = 0; t < 2; t++) {
    rec_query(TQ[t][0], ALL, 6, spec); rec_query(TQ[t][1], ONE, 1, spec); rec_query(TQ[t][2], LAST, 1, spec); rec_query(TQ[t][3], ALL, 6, spec);
  }
}

/* ---------------------------------------------------------------- LIKE (LT / LR / LP blocks) */
static int valid_utf8(const u8 *z, int n) {   /* well-formed UTF-8 (no overlong forms, surrogates or stray continuation bytes) */
  for (int i = 0; i < n;) {
    u8 c = z[i]; int k = c < 0x80 ? 0 : (c & 0xe0) == 0xc0 ? 1 : (c & 0xf0) == 0xe0 ? 2 : (c & 0xf8) == 0xf0 ? 3 : -1;
    if (k < 0 || i + k >= n + (k == 0)) { if (k) return 0; }
    u32 v = k == 0 ? c : k == 1 ? (c & 0x1f) : k == 2 ? (c & 0x0f) : (c & 0x07);
    for (int j = 1; j <= k; j++) { if (i + j >= n || (z[i + j] & 0xc0) != 0x80) return 0; v = (v << 6) | (z[i + j] & 0x3f); }
    if ((k == 1 && v < 0x80) || (k == 2 && (v < 0x800 || (v >= 0xd800 && v < 0xe000))) || (k == 3 && (v < 0x10000 || v > 0x10ffff))) return 0;
    i += k + 1;
  }
  return 1;
}
static sqlite3 *ldb[2];   /* [0] LIKE folds ASCII case (likeInfoNorm), [1] PRAGMA case_sensitive_like = 1 */
static long lrows, lfn, lq, lqrange, lqrangeqc;
static void lex_(sqlite3 *d, const char *q) { char *e = 0; if (sqlite3_exec(d, q, 0, 0, &e)) { fprintf(stderr, "lean_oracle: %s: %s\n", q, e); exit(2); } }
static void like_block(FILE *f, char *head) {
  int nc, esc, n; sscanf(head, "LT %d %d %d", &nc, &esc, &n);
  sqlite3 *d = ldb[nc ? 0 : 1];
  lex_(d, "DROP TABLE IF EXISTS lk"); lex_(d, nc ? "CREATE TABLE lk(id INTEGER PRIMARY KEY, p, s TEXT COLLATE NOCASE); CREATE INDEX lks ON lk(s)"
                                                  : "CREATE TABLE lk(id INTEGER PRIMARY KEY, p, s TEXT); CREATE INDEX lks ON lk(s)");
  char escsql[16] = ""; if (esc) snprintf(escsql, sizeof escsql, " ESCAPE '%c'", esc);
  static char line[1 << 16]; Exp e; memset(&e, 0, sizeof e); e.k = X_IDS; int invalid = 0;
  for (int i = 1; i <= n; i++) {
    char pp[1200], tt[1200]; int want;
    if (!fgets(line, sizeof line, f) || sscanf(line, "LR %1199s %1199s %d", pp, tt, &want) != 3) { fprintf(stderr, "lean_oracle: bad LIKE row\n"); exit(2); }
    V vp, vt; pp[0] = 't'; parse(pp, &vp); parse(tt, &vt);   /* (p<hex>: a pattern, as text) */
    sqlite3_stmt *st; sqlite3_prepare_v2(d, "INSERT INTO lk VALUES (?1, ?2, ?3)", -1, &st, 0);
    sqlite3_bind_int(st, 1, i); bind_v(st, 2, &vp); bind_v(st, 3, &vt);
    if (sqlite3_step(st) != SQLITE_DONE) { fprintf(stderr, "lean_oracle: like insert: %s\n", sqlite3_errmsg(d)); exit(2); }
    sqlite3_finalize(st);
    char q[80]; snprintf(q, sizeof q, "SELECT s LIKE p%s FROM lk WHERE id = %d", escsql, i);
    sqlite3_prepare_v2(d, q, -1, &st, 0); int got = sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int(st, 0) : -1; sqlite3_finalize(st);
    lrows++;
    if (got != want) { lfn++; if (lfn <= 10) { char a[700], b[700]; fmt(&vp, a, sizeof a); fmt(&vt, b, sizeof b); fprintf(stderr, "like: SQLite's like(%s, %s%s) = %d, model %d\n", a, b, escsql, got, want); } }
    if (want && e.nids < 64) e.ids[e.nids++] = i;
    if (!valid_utf8(vp.z, vp.n) || !valid_utf8(vt.z, vt.n)) invalid = 1;
  }
  sqlite3 *save = db; db = d;
  char q[400]; snprintf(q, sizeof q, "SELECT id FROM lk WHERE s LIKE p%s ORDER BY id", escsql);
  long qd0 = qdiff, id0 = idiff; run_query(q, &e, 0, 0); lq++;
  if (!fgets(line, sizeof line, f) || strncmp(line, "LP ", 3)) { fprintf(stderr, "lean_oracle: bad LP\n"); exit(2); }
  char pp[1200]; int off; sscanf(line, "LP %1199s%n", pp, &off); V vp; pp[0] = 't'; parse(pp, &vp);
  Exp ep; memset(&ep, 0, sizeof ep); char *rest = strdup(line + off); parse_ids(rest, &ep); free(rest);
  /* one pattern against every row: bound, and as a literal when it can be one (the LIKE optimisation's range) */
  snprintf(q, sizeof q, "SELECT id FROM lk WHERE s LIKE ?1%s ORDER BY id", escsql);
  long i0 = idiff, q0 = qdiff; run_query(q, &ep, 1, &vp);
  int lit = vp.n < 200; for (int j = 0; j < vp.n; j++) if (vp.z[j] == 0 || vp.z[j] == '\'') lit = 0;
  if (lit) {
    char *o = q + snprintf(q, sizeof q, "SELECT id FROM lk WHERE s LIKE '"); memcpy(o, vp.z, (size_t)vp.n); o += vp.n;
    snprintf(o, sizeof q - (size_t)(o - q), "'%s ORDER BY id", escsql); run_query(q, &ep, 0, 0);
  }
  /* the LIKE optimisation's range compares bytes, like() characters: on invalid UTF-8 they differ (docs/LEAN.md), which
     is SQLite's own behaviour (the interpreter's index range against its like()), and qc, which scans a bound pattern
     (re-prepared as QPSG), can then differ from the interpreter. Counted apart; on valid UTF-8 any difference counts */
  if (invalid) { lqrange += idiff - i0; lqrangeqc += qdiff - q0; idiff = i0; qdiff = q0; }
  (void)qd0; (void)id0;
  db = save;
}

/* a table's checks, one line each (O P R D M ON PN, and for typed tables Y F), against tables TB[0] (indexed) and TB[1] */
static void table_lines(FILE *f, const char *const TB[2]) {
  static char line[1 << 16]; char a[1200], b[1200];
  while (fgets(line, sizeof line, f) && line[0] != 'E') {
        Exp e; memset(&e, 0, sizeof e); char q[400], *rest;
        for (int t = 0; t < 2; t++) {
          const char *T = TB[t];
          if (!strncmp(line, "O ", 2)) {
            char dir[4], cn[4]; int off; sscanf(line + 2, "%3s %3s%n", dir, cn, &off); rest = strdup(line + 2 + off); parse_ids(rest, &e); free(rest);
            const char *ob = !strcmp(dir, "A") ? "" : !strcmp(dir, "D") ? " DESC" : !strcmp(dir, "AL") ? " NULLS LAST" : " DESC NULLS FIRST";
            snprintf(q, sizeof q, "SELECT id FROM %s ORDER BY %s%s, id", T, cn, ob); run_query(q, &e, 0, 0);
            Exp e5 = e; if (e5.nids > 5) e5.nids = 5;
            snprintf(q, sizeof q, "SELECT id FROM %s ORDER BY %s%s, id LIMIT 5", T, cn, ob); run_query(q, &e5, 0, 0);   /* top-N */
          } else if (!strncmp(line, "ON ", 3)) {
            rest = strdup(line + 3); parse_ids(rest, &e); free(rest);
            snprintf(q, sizeof q, "SELECT id FROM %s ORDER BY y COLLATE NOCASE, id", T); run_query(q, &e, 0, 0);
          } else if (!strncmp(line, "P ", 2)) {
            char opn[4], cn[4]; unsigned long long h; sscanf(line, "P %3s %3s %ld %llu", opn, cn, &e.cnt, &h); e.h = h; e.k = X_PAIRS;
            const char *o = !strcmp(opn, "lt") ? "<" : !strcmp(opn, "le") ? "<=" : !strcmp(opn, "eq") ? "=" : !strcmp(opn, "ne") ? "<>" : !strcmp(opn, "gt") ? ">" : ">=";
            snprintf(q, sizeof q, "SELECT a.id, b.id FROM %s a, %s b WHERE a.%s %s b.%s ORDER BY a.id, b.id", T, T, cn, o, cn); run_query(q, &e, 0, 0);
          } else if (!strncmp(line, "PN ", 3)) {
            unsigned long long h; sscanf(line, "PN %ld %llu", &e.cnt, &h); e.h = h; e.k = X_PAIRS;
            snprintf(q, sizeof q, "SELECT a.id, b.id FROM %s a, %s b WHERE a.y < b.y COLLATE NOCASE ORDER BY a.id, b.id", T, T); run_query(q, &e, 0, 0);
          } else if (!strncmp(line, "R ", 2)) {
            long long k1, k2; int off; char cn[4]; sscanf(line, "R %3s %lld %lld%n", cn, &k1, &k2, &off); rest = strdup(line + off); parse_ids(rest, &e); free(rest);
            V bd[2]; memset(bd, 0, sizeof bd); bd[0].t = bd[1].t = SQLITE_INTEGER; bd[0].i = k1; bd[1].i = k2;
            snprintf(q, sizeof q, "SELECT id FROM %s WHERE %s >= ?1 AND %s < ?2 ORDER BY id", T, cn, cn); run_query(q, &e, 2, bd);
            snprintf(q, sizeof q, "SELECT count(*), min(id) FROM %s WHERE %s >= ?1 AND %s < ?2", T, cn, cn);   /* (a count: an aggregate loop) */
            Exp ec; memset(&ec, 0, sizeof ec); ec.k = X_MINMAX; ec.mm[0].t = SQLITE_INTEGER; ec.mm[0].i = e.nids;
            if (e.nids) { ec.mm[1].t = SQLITE_INTEGER; ec.mm[1].i = e.ids[0]; } else ec.mm[1].t = SQLITE_NULL;
            run_query(q, &ec, 2, bd);
          } else if (!strncmp(line, "D ", 2)) {
            char cn[4]; e.k = X_COUNT; sscanf(line, "D %3s %ld", cn, &e.cnt);
            snprintf(q, sizeof q, "SELECT count(DISTINCT %s) FROM %s", cn, T); run_query(q, &e, 0, 0);
            snprintf(q, sizeof q, "SELECT count(*) FROM (SELECT DISTINCT %s FROM %s WHERE %s IS NOT NULL)", cn, T, cn); run_query(q, &e, 0, 0);
          } else if (!strncmp(line, "Y ", 2)) {
            char cn[4]; int off; sscanf(line, "Y %3s%n", cn, &off); e.k = X_VALS; e.nvals = 0;
            rest = strdup(line + off);
            for (char *tk = strtok(rest, " \n"); tk && e.nvals < 64; tk = strtok(0, " \n")) parse(tk, &e.vals[e.nvals++]);
            free(rest);
            snprintf(q, sizeof q, "SELECT %s FROM %s ORDER BY id", cn, T); run_query(q, &e, 0, 0);
          } else if (!strncmp(line, "F ", 2)) {
            char cn[4], opn[4], pv[1200]; int off; sscanf(line, "F %3s %3s %1199s%n", cn, opn, pv, &off);
            V bv; parse(pv, &bv); rest = strdup(line + off); parse_ids(rest, &e); free(rest);
            const char *o = !strcmp(opn, "lt") ? "<" : !strcmp(opn, "le") ? "<=" : !strcmp(opn, "eq") ? "=" : !strcmp(opn, "ne") ? "<>" : !strcmp(opn, "gt") ? ">" : ">=";
            snprintf(q, sizeof q, "SELECT id FROM %s WHERE %s %s ?1 ORDER BY id", T, cn, o); run_query(q, &e, 1, &bv);
          } else if (!strncmp(line, "M ", 2)) {
            char cn[4]; e.k = X_MINMAX; sscanf(line, "M %3s %1199s %1199s", cn, a, b); parse(a, &e.mm[0]); parse(b, &e.mm[1]);
            snprintf(q, sizeof q, "SELECT min(%s), max(%s) FROM %s", cn, cn, T); run_query(q, &e, 0, 0);
          }
        }
  }
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: lean_oracle CASES\n"); return 2; }
  FILE *f = fopen(argv[1], "r"); if (!f) { perror(argv[1]); return 2; }
  if (sqlite3_open(":memory:", &db) != SQLITE_OK) return 2;
  nocase = sqlite3FindCollSeq(db, SQLITE_UTF8, "NOCASE", 0);
  ki1 = sqlite3KeyInfoAlloc(db, 1, 0);
  X.db = db;
  static char line[1 << 16]; long npair = 0, nidx = 0, nhk = 0, nkey = 0, ntab = 0;
  static const char *TB[2] = {"v", "u"};   /* v has an index on x, u none (the sorter) */
  while (fgets(line, sizeof line, f)) {
    char a[1200], b[1200], c[8]; int exp; V va, vb;
    if (line[0] == 'X') { check_record(line); continue; }
    if (line[0] == 'L' && line[1] == 'T') {
      if (!ldb[0]) {
        for (int j = 0; j < 2; j++) if (sqlite3_open(":memory:", &ldb[j]) != SQLITE_OK) return 2;
        lex_(ldb[1], "PRAGMA case_sensitive_like = 1");
      }
      like_block(f, line); continue;
    }
    if (line[0] == 'C' && sscanf(line, "C %7s %1199s %1199s %d", c, a, b, &exp) == 4) { parse(a, &va); parse(b, &vb); check_pair(c[0], &va, &vb, exp); npair++; }
    else if (line[0] == 'I') { long long key; if (sscanf(line, "I %1199s %lld %d", a, &key, &exp) == 3) { parse(a, &va); check_idx(&va, key, exp); nidx++; } }
    else if (line[0] == 'H' && sscanf(line, "H %1199s %1199s %d", a, b, &exp) == 3) { parse(a, &va); parse(b, &vb); check_hk(&va, &vb, exp); nhk++; }
    else if (line[0] == 'K') {
      unsigned long long kh;
      if (sscanf(line, "K %1199s %llx", a, &kh) == 2) { parse(a, &va); nchk++; nkey++; if (key_ref(&va) != kh) { char sv[700]; fmt(&va, sv, sizeof sv); BAD("sort key of %s: C %016llx, Lean %016llx", sv, (unsigned long long)key_ref(&va), kh); } }
    } else if (line[0] == 'T' && line[1] == ' ') {
      int n = atoi(line + 2); ntab++;
      ex("DROP TABLE IF EXISTS v; DROP TABLE IF EXISTS u; CREATE TABLE v(id INTEGER PRIMARY KEY, x, y TEXT, z, k);"
         "CREATE INDEX vx ON v(x); CREATE INDEX vz ON v(z); CREATE INDEX vk ON v(k); CREATE TABLE u(id INTEGER PRIMARY KEY, x, y TEXT, z, k)");
      for (int id = 1; id <= n; id++) {
        char zc[1200], kc[1200]; V vz, vk;
        if (!fgets(line, sizeof line, f) || sscanf(line, "V %1199s %1199s %1199s %1199s", a, b, zc, kc) != 4) { fprintf(stderr, "lean_oracle: bad table\n"); return 2; }
        parse(a, &va); parse(b, &vb); parse(zc, &vz); parse(kc, &vk);
        for (int t = 0; t < 2; t++) {
          char q[64]; snprintf(q, sizeof q, "INSERT INTO %s VALUES (?1, ?2, ?3, ?4, ?5)", TB[t]); sqlite3_stmt *s; sqlite3_prepare_v2(db, q, -1, &s, 0);
          sqlite3_bind_int(s, 1, id);
          bind_v(s, 2, &va); bind_v(s, 4, &vz); bind_v(s, 5, &vk);
          sqlite3_bind_text(s, 3, (const char *)vb.z, vb.n, SQLITE_TRANSIENT);
          if (sqlite3_step(s) != SQLITE_DONE) { fprintf(stderr, "lean_oracle: insert: %s\n", sqlite3_errmsg(db)); return 2; }
          sqlite3_finalize(s);
        }
      }
      table_lines(f, TB);
    } else if (line[0] == 'T' && line[1] == 'T') {
      int n = atoi(line + 3); ntab++;
      static const char *TT[2] = {"t", "tu"};
      ex("DROP TABLE IF EXISTS t; DROP TABLE IF EXISTS tu;"
         "CREATE TABLE t(id INTEGER PRIMARY KEY, ci INTEGER, cr REAL, cn NUMERIC, ct TEXT, cb BLOB);"
         "CREATE INDEX tci ON t(ci); CREATE INDEX tcr ON t(cr); CREATE INDEX tcn ON t(cn); CREATE INDEX tct ON t(ct); CREATE INDEX tcb ON t(cb);"
         "CREATE TABLE tu(id INTEGER PRIMARY KEY, ci INTEGER, cr REAL, cn NUMERIC, ct TEXT, cb BLOB)");
      for (int id = 1; id <= n; id++) {
        char w[5][1200]; V cv[5];
        if (!fgets(line, sizeof line, f) || sscanf(line, "W %1199s %1199s %1199s %1199s %1199s", w[0], w[1], w[2], w[3], w[4]) != 5) { fprintf(stderr, "lean_oracle: bad typed table\n"); return 2; }
        for (int j = 0; j < 5; j++) parse(w[j], &cv[j]);
        for (int t = 0; t < 2; t++) {
          char q[80]; snprintf(q, sizeof q, "INSERT INTO %s VALUES (?1, ?2, ?3, ?4, ?5, ?6)", TT[t]); sqlite3_stmt *s; sqlite3_prepare_v2(db, q, -1, &s, 0);
          sqlite3_bind_int(s, 1, id);
          for (int j = 0; j < 5; j++) bind_v(s, j + 2, &cv[j]);
          if (sqlite3_step(s) != SQLITE_DONE) { fprintf(stderr, "lean_oracle: insert: %s\n", sqlite3_errmsg(db)); return 2; }
          sqlite3_finalize(s);
        }
      }
      table_lines(f, TT);
    }
  }
  fclose(f);
  printf("lean_oracle%s: %ld pairs, %ld index probes, %ld hash keys, %ld sort keys: %ld checks, %ld disagreements\n",
         getenv("QC_VM_ONLY") ? " (QC_VM_ONLY)" : "", npair, nidx, nhk, nkey, nchk, nbad);
  printf("lean_oracle%s: %ld tables, %ld queries: qc ran %ld (%ld fell back), %ld differ from the model; the interpreter differs on %ld\n",
         getenv("QC_VM_ONLY") ? " (QC_VM_ONLY)" : "", ntab, nq, qcmp, qfell, qdiff, idiff);
  if (xrec)
    printf("lean_oracle%s: %ld records: qc_decode against its model: %ld differ; accepts %ld that OP_Column reports corrupt, wrong values in %ld\n"
           "lean_oracle%s: records through SQL: %ld queries, the interpreter differs from the model on %ld; qc ran %ld (%ld fell back): rows where SQLite reports corruption %ld, wrong values %ld\n",
           getenv("QC_VM_ONLY") ? " (QC_VM_ONLY)" : "", xrec, xfid, xlen, xwrong, getenv("QC_VM_ONLY") ? " (QC_VM_ONLY)" : "", xe2e, xsq, xqcmp, xqfell, xqlen, xqwrong);
  if (lrows)
    printf("lean_oracle%s: LIKE: %ld rows, SQLite's like() differs from the model on %ld; %ld blocks through SQL (in the query totals above): one pattern against the column, rows with invalid UTF-8: the index range differs from like() in %ld queries (SQLite), %ld runs (qc)\n",
           getenv("QC_VM_ONLY") ? " (QC_VM_ONLY)" : "", lrows, lfn, lq, lqrange, lqrangeqc);
  if (rdb) { sqlite3_close(rdb); remove("build/lean-rec.db"); }
  for (int j = 0; j < 2; j++) if (ldb[j]) sqlite3_close(ldb[j]);
  sqlite3KeyInfoUnref(ki1); sqlite3_close(db); sqlite3_qc_release();
  /* (qc's rows where SQLite reports a corrupt record: a known finding, docs/LEAN.md; LEAN_ORACLE_STRICT=1 fails on it) */
  int strict = getenv("LEAN_ORACLE_STRICT") != 0;
  return nbad || qdiff || idiff || xfid || xwrong || xsq || xqwrong || lfn || (strict && xqlen) ? 1 : 0;
}
