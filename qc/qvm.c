/* qvm.c: qc's general executor. #included by qc.c after the general plans (qcg.c).
**
** The plans in qc.c and qcg.c lift known shapes into rewritten programs. Everything else read-only (coroutines,
** compound SELECTs, CTEs, window functions, DISTINCT, sorter GROUP BY, subqueries of any kind) runs here: the
** statement's own VDBE program, opcode by opcode, with registers that are SQLite Mems, as vdbe.c runs it. What
** makes it cheaper than vdbe.c:
**   columns    text and blobs read from the database stay in its pages, pinned until the execution ends, as
**              MEM_Static values: no copy into each register (vdbe.c's OP_Column copies them) and none on Copy;
**   rows       ResultRow appends to a row buffer that is handed out once, when the program halts: no
**              sqlite3_step() round trip and no sqlite3_column_*() call per value;
**   cursors    database cursors stay open for the whole read transaction, registers and function contexts for the
**              life of the statement;
**   natives    count() accumulates in a plain integer, length() of text runs in line, the sorter is an in-memory
**              stable merge sort on keys decoded once (what SQLite's in-memory sorter computes).
**   sets       an ephemeral index that is only probed and added to (DISTINCT) is a hash set of its keys;
**   regions    after two runs of type feedback, single-cursor loop bodies run as specialised direct-threaded nodes
**              (see the regions section below).
** Everything else is vdbe.c's own code path: the opcode bodies follow vdbe.c, comparisons and affinities call its
** helpers on the registers, ephemeral tables are SQLite's in-memory B-trees with SQLite records, functions and
** aggregates (window ones included) are called through their FuncDefs with the registers as arguments.
** The program is checked opcode by opcode when the statement is lifted; at run time anything not reproduced exactly
** (an error, a write to a real table, a zeroblob, an oversized result) returns QC_FALLBACK before any row is handed
** out, so the caller steps the statement instead. Ephemeral state is private to the execution: nothing to undo. */

#define QV_ARENA_MAX (256u << 20)
#define QV_MAXPINS 65536
#define QV_MAXARGS 32
#if defined(__GNUC__)
#define QV_INLINE inline __attribute__((always_inline))
#define QV_NOINLINE __attribute__((noinline))
#else
#define QV_INLINE inline
#define QV_NOINLINE
#endif

static const char *qv_why = "";

/* ---------------------------------------------------------------- arena */
typedef struct QvBlk { struct QvBlk *next; size_t used, cap; char d[]; } QvBlk;
typedef struct QvArena { QvBlk *head; size_t total; } QvArena;
static void *qv_alloc(QvArena *A, size_t n) {
  n = (n + 15) & ~(size_t)15;
  QvBlk *b = A->head;
  if (!b || b->used + n > b->cap) {
    size_t cap = n > (64u << 10) ? n : (64u << 10);
    if (A->total + cap > QV_ARENA_MAX) return 0;
    b = sqlite3_malloc64(sizeof *b + cap + 16); if (!b) return 0;   /* 16 bytes of slack: vector loads */
    b->next = A->head; b->used = 0; b->cap = cap; A->head = b; A->total += cap;
  }
  void *p = b->d + b->used; b->used += n; return p;
}
static void qv_arena_reset(QvArena *A) {   /* keep the newest block */
  QvBlk *b = A->head; if (!b) return;
  for (QvBlk *x = b->next, *y; x; x = y) { y = x->next; sqlite3_free(x); }
  b->next = 0; b->used = 0; A->total = b->cap;
}

/* ---------------------------------------------------------------- plan and run state */
enum { QVC_NONE, QVC_BT, QVC_EPH, QVC_SORT, QVC_PSEUDO, QVC_NULLONLY, QVC_VEC, QVC_HASH };
/* an ephemeral rowid table held as a vector (QVC_VEC): entries in rowid order, records in the arena, deletes as
   tombstones. Used for the tables whose cursors only append (NewRowid / Insert), scan, seek by rowid and delete:
   window frames, materialized and recursive CTEs. Anything outside what it reproduces deoptimises the plan to B-trees. */
typedef struct QvVecEnt { i64 rowid; const u8 *rec; u32 len, dead; } QvVecEnt;
typedef struct QvVec { QvVecEnt *e; int n, cap, first, live; } QvVec;
typedef struct QvHset { u64 *hv; const u8 **rec; u32 n, cap; } QvHset;   /* open addressing; rec: the inserted records (0: empty) */
typedef struct QvSort { const u8 **rec; u32 *len; QcVal *key; int n, cap, pos, nk; KeyInfo *ki; i64 mem, lim, mn; } QvSort;   /* key: nk decoded fields per record; mem, lim, mn: see qv_sort_limits */
typedef struct QvCur {
  u8 kind, isTable, nullRow, deferred, eqOnly, rowOk, copyVals, noReuse, owner;   /* owner: opened the ephemeral B-tree */
  u16 ep5;                                /* OpenEphemeral's P5 (B-tree flags) */
  QvVec *vec; int vi, rowVi; u8 vbad;     /* QVC_VEC: the entry the cursor is on; vbad: 1 past the end, 2 unknown position */
  BtCursor *bc; KeyInfo *ki; int nField;
  Btree *ebt; Pgno eroot;                 /* ephemeral: its B-tree (BTREE_SINGLE: closed with its last cursor) */
  i64 movetoTarget; struct QvCur *alt; const int *altMap;
  int pseudoReg, seekResult, seekHit; i64 seqCount;
  QvSort *srt;
  QvHset *hs; int hk;                     /* QVC_HASH: the set; its key's field count */
  /* the current row: its record, how far its header is parsed */
  const u8 *row; u32 szRow, payload, hdrOff; int nHdr; u32 *aType, *aOff; DbPage *pinned;
  DbPage *rowPage;                        /* the database page the row's record is in (pinned once a value points into it) */
  int capField;                           /* aType / aOff are kept (malloc) between executions */
  u32 rowGen;                             /* ephemeral: the X->ephGen the cached row was read at */
  const MemPage *cpg; Pgno cpgno; const u8 *clo, *cend;   /* QVC_BT: the page whose cell area [clo, cend) qv_idxcmp holds (cleared every run) */
} QvCur;
static void qv_cur_reset(QvCur *C) { u32 *t = C->aType, *o = C->aOff; int cap = C->capField; memset(C, 0, sizeof *C); C->aType = t; C->aOff = o; C->capField = cap; }
typedef struct QvPlan {
  int kind;                                /* 3 */
  int iDb, cookie, gen, nout;
  int nMem, nCur, nOp;
  Btree *bt; u8 txnChecked;
  BtCursor **bc; Pgno *bcRoot; u8 *bopen; /* database cursors by cursor number, open for the transaction */
  /* kept between executions, as a Vdbe keeps them: registers (with their buffers), cursors with their header
     arrays, per-opcode function contexts */
  Mem *r; struct QvCur *c; void **octx; u8 *once;
  u8 *isCnt; i64 *cnt;                    /* accumulators only ever count(): a native counter (countStep / countInverse) */
  /* ephemeral B-trees kept open between executions, by cursor number: emptied (ClearTable) when the program opens
     the cursor again, which is what vdbe.c does when a cursor is reopened within one run */
  struct QvEphKeep { Btree *bt; BtCursor *bc; Pgno root; KeyInfo *ki; u16 p5; } *keep;
  u8 *isVec, vecOff;                      /* cursor numbers whose ephemeral table can be a vector; vecOff: a run deoptimised */
  u8 *isHash, hashOff;                    /* ephemeral indexes only probed and added to: a hash set of keys of isHash[c] fields */
  /* accumulators only ever sum() / total() / avg() (1 2 3): integers natively; the first non-integer or overflow hands
     the state to SQLite's own SumCtx in the register and sumStep / sumInverse from then on */
  u8 *isSum; struct QvSum { i64 iSum, cnt; u8 spilled; } *sacc;
  /* type feedback, by opcode: the value classes (QV_FB_*) seen; Column: the value it produced; comparisons and
     arithmetic: both operands; AggStep: its argument */
  u8 *fb; u32 runs;
  struct QvRegion *rg; int nrg; int *rgAt;   /* loop regions (step 4 of docs/IR.md); rgAt: by the pc of the loop's Next, index + 1 */
} QvPlan;
typedef struct QvX {
  QvPlan *P; Vdbe *v; sqlite3 *db; const QcOut *O;
  Mem *r; QvCur *c; u8 *once; void **octx;
  QvArena A;
  DbPage **pins; int npin, cpin;
  QcVal *out; int nrow; size_t cout;     /* rows handed out; capacity in values (shared by every plan: widths differ) */
  int iCompare; const u32 *aPermute;
  u32 ephGen;                             /* bumped by every ephemeral write: cached ephemeral rows older than it are stale */
  u8 *fb; int *rgAt;                      /* the plan's feedback; its regions (0 until they are built) */
  unsigned nprog; int tick;               /* loop iterations since the progress handler last ran; until the next check */
  u32 usable;                             /* the database's usable page size */
} QvX;
/* feedback classes, by a Mem's flags & 0x1f (Null Str Int Real Blob; IntReal alone counts as real); the first one
   of Null, Int, Real, Str, Blob that is set wins */
#define QV_FB_NULL 1
#define QV_FB_INT 2
#define QV_FB_REAL 4
#define QV_FB_TEXT 8
#define QV_FB_BLOB 16
static const u8 qv_fbt[32] = {4, 1, 8, 1, 2, 1, 2, 1, 4, 1, 4, 1, 2, 1, 2, 1, 16, 1, 8, 1, 2, 1, 2, 1, 4, 1, 4, 1, 2, 1, 2, 1};
static inline u8 qv_fbc(const Mem *m) { return qv_fbt[m->flags & 0x1f]; }
static QvPlan *qv_plans[64]; static int qv_nplans;
static void qv_txn_end(Btree *bt) {
  for (int k = 0; k < qv_nplans; k++) {
    QvPlan *P = qv_plans[k]; if (P->bt != bt) continue;
    P->txnChecked = 0;
    for (int c = 0; c < P->nCur; c++) if (P->bopen[c]) { sqlite3BtreeCloseCursor(P->bc[c]); P->bopen[c] = 0; }
  }
}

/* ---------------------------------------------------------------- registers */
/* out2Prerelease: the register about to be written (an accumulator's context released, a counter reset) */
static inline Mem *qv_out(QvX *X, int r) {
  Mem *m = &X->r[r];
  if (X->P->isCnt[r]) X->P->cnt[r] = 0;
  if (X->P->isSum[r]) { X->P->sacc[r].iSum = X->P->sacc[r].cnt = 0; X->P->sacc[r].spilled = 0; }
  if (VdbeMemDynamic(m)) sqlite3VdbeMemSetNull(m);
  return m;
}
static inline void qv_int(Mem *m, i64 v) { m->flags = MEM_Int; m->u.i = v; }
static inline void qv_static(Mem *m, const void *z, int n, int text, int term) {   /* stable memory: pinned page, arena, P4 */
  m->flags = text ? (u16)(MEM_Str | MEM_Static | (term ? MEM_Term : 0)) : (MEM_Blob | MEM_Static);
  m->z = (char *)z; m->n = n; m->enc = SQLITE_UTF8;
}
static inline int qv_isnull(const Mem *m) { return (m->flags & MEM_Null) != 0; }
/* a register's value for the caller: stable memory as it is, anything else copied to the arena */
static int qv_val(QvX *X, const Mem *m, QcVal *o) {
  u16 f = m->flags;
  if (f & MEM_Null) { o->type = SQLITE_NULL; o->n = 0; o->i = 0; return 1; }
  if (f & MEM_Int) { o->type = SQLITE_INTEGER; o->i = m->u.i; return 1; }
  if (f & MEM_IntReal) { o->type = SQLITE_FLOAT; o->r = (double)m->u.i; return 1; }
  if (f & MEM_Real) { o->type = SQLITE_FLOAT; o->r = m->u.r; return 1; }
  if (f & (MEM_Str | MEM_Blob)) {
    if (f & MEM_Zero) { qv_why = "zeroblob"; return 0; }
    if ((f & MEM_Str) && m->enc != SQLITE_UTF8) { qv_why = "encoding"; return 0; }
    o->type = (f & MEM_Str) ? SQLITE_TEXT : SQLITE_BLOB; o->n = m->n;
    if (f & MEM_Static) { o->z = (const u8 *)m->z; return 1; }
    char *d = qv_alloc(&X->A, (size_t)m->n + 1); if (!d) { qv_why = "arena"; return 0; }
    if (m->n) memcpy(d, m->z, (size_t)m->n);
    d[m->n] = 0; o->z = (const u8 *)d; return 1;
  }
  qv_why = "value"; return 0;
}
/* a QcVal as a shallow Mem (the sorter's keys; nothing to release unless a conversion made one) */
static void qv_mem(Mem *m, const QcVal *x, sqlite3 *db) {
  m->szMalloc = 0; m->zMalloc = 0; m->eSubtype = 0; m->db = db; m->enc = SQLITE_UTF8; m->z = 0; m->n = 0; m->u.i = 0;
  switch (x->type) {
    case SQLITE_INTEGER: m->flags = MEM_Int; m->u.i = x->i; break;
    case SQLITE_FLOAT: m->flags = MEM_Real; m->u.r = x->r; break;
    case SQLITE_TEXT: m->flags = MEM_Str | MEM_Ephem; m->z = (char *)x->z; m->n = x->n; break;
    case SQLITE_BLOB: m->flags = MEM_Blob | MEM_Ephem; m->z = (char *)x->z; m->n = x->n; break;
    default: m->flags = MEM_Null;
  }
}
/* sqlite3MemCompare of two QcVals (the sorter) */
static int qv_cmp(QvX *X, const QcVal *a, const QcVal *b, const CollSeq *coll) {
  if (a->type == SQLITE_INTEGER && b->type == SQLITE_INTEGER) return a->i < b->i ? -1 : a->i > b->i;
  if (a->type == SQLITE_TEXT && b->type == SQLITE_TEXT && (!coll || coll->xCmp == sqlite3BinaryCompare)) {
    int n = a->n < b->n ? a->n : b->n, c = memcmp(a->z, b->z, (size_t)n); return c ? c : a->n - b->n;
  }
  Mem ma, mb; qv_mem(&ma, a, X->db); qv_mem(&mb, b, X->db);
  int c = sqlite3MemCompare(&ma, &mb, coll);
  sqlite3VdbeMemRelease(&ma); sqlite3VdbeMemRelease(&mb); return c;
}

/* ---------------------------------------------------------------- records */
static int qv_pin(QvX *X, DbPage *pg) {
  if (X->npin && X->pins[X->npin - 1] == pg) return 1;
  if (X->npin == X->cpin) {
    if (X->cpin >= QV_MAXPINS) { qv_why = "pins"; return 0; }
    int nc = X->cpin ? X->cpin * 2 : 256; DbPage **np = sqlite3_realloc64(X->pins, sizeof *np * (u64)nc);
    if (!np) return 0;
    X->pins = np; X->cpin = nc;
  }
  sqlite3PagerRef(pg); X->pins[X->npin++] = pg; return 1;
}
static inline double qv_real(const u8 *d) { u64 u = 0; for (int k = 0; k < 8; k++) u = (u << 8) | d[k]; double r; memcpy(&r, &u, 8); return r; }
/* the value of serial type t at d into a register (the register has been released); copy: text and blobs to the arena */
static QV_INLINE int qv_serial_mem(QvX *X, u32 t, const u8 *d, Mem *m, int copy) {
  switch (t) {
    case 0: m->flags = MEM_Null; return 1;
    case 1: case 2: case 3: case 4: case 5: case 6: qv_int(m, qc_int(t, d)); return 1;
    case 7: { double r = qv_real(d); if (r != r) { m->flags = MEM_Null; return 1; } m->flags = MEM_Real; m->u.r = r; return 1; }   /* NaN reads as NULL */
    case 8: case 9: qv_int(m, (i64)t - 8); return 1;
    case 10: case 11: qv_why = "serial type"; return 0;
  }
  u32 n = (t - 12) >> 1;
  if (copy) {
    char *p = qv_alloc(&X->A, n + 1); if (!p) { qv_why = "arena"; return 0; }
    memcpy(p, d, n); p[n] = 0; qv_static(m, p, (int)n, t & 1, 1);
  } else qv_static(m, d, (int)n, t & 1, 0);
  return 1;
}
/* the same into a QcVal (sorter keys; values point into the record) */
static int qv_serial_val(u32 t, const u8 *d, QcVal *o) {
  switch (t) {
    case 0: o->type = SQLITE_NULL; o->n = 0; return 1;
    case 1: case 2: case 3: case 4: case 5: case 6: o->type = SQLITE_INTEGER; o->i = qc_int(t, d); return 1;
    case 7: { double r = qv_real(d); if (r != r) { o->type = SQLITE_NULL; o->n = 0; return 1; } o->type = SQLITE_FLOAT; o->r = r; return 1; }
    case 8: case 9: o->type = SQLITE_INTEGER; o->i = (i64)t - 8; return 1;
    case 10: case 11: return 0;
  }
  o->type = (t & 1) ? SQLITE_TEXT : SQLITE_BLOB; o->n = (int)((t - 12) >> 1); o->z = d; return 1;
}
/* MakeRecord's serial types (minWriteFileFormat >= 4: 0 and 1 as types 8 and 9) */
static u32 qv_stype(const Mem *m, int ff4, u32 *len) {
  u16 f = m->flags;
  if (f & MEM_Null) { *len = 0; return 0; }
  if (f & (MEM_Int | MEM_IntReal)) {
    i64 i = m->u.i; u64 uu = i < 0 ? ~(u64)i : (u64)i;
    if (uu <= 127) { if ((i & 1) == i && ff4) { *len = 0; return 8 + (u32)uu; } *len = 1; return 1; }
    if (uu <= 32767) { *len = 2; return 2; }
    if (uu <= 8388607) { *len = 3; return 3; }
    if (uu <= 2147483647) { *len = 4; return 4; }
    if (uu <= 140737488355327LL) { *len = 6; return 5; }
    *len = 8; return (f & MEM_IntReal) ? 7 : 6;   /* an 8-byte IntReal is stored as a double */
  }
  if (f & MEM_Real) { *len = 8; return 7; }
  *len = (u32)m->n; return (u32)m->n * 2 + ((f & MEM_Str) ? 13 : 12);
}
static int qv_make_record(QvX *X, Mem *f, int n, Mem *out) {
  int ff4 = X->v->minWriteFileFormat >= 4; u32 nHdr = 0, nData = 0, st[256], ln[256];
  if (n > 256) { qv_why = "record width"; return 0; }
  for (int k = 0; k < n; k++) {
    if (f[k].flags & MEM_Zero) { qv_why = "zeroblob"; return 0; }
    st[k] = qv_stype(&f[k], ff4, &ln[k]); nHdr += (u32)sqlite3VarintLen(st[k]); nData += ln[k];
  }
  if (nHdr <= 126) nHdr += 1;   /* the header-size varint counts itself (as MakeRecord does) */
  else { int nv = sqlite3VarintLen(nHdr); nHdr += (u32)nv; if (nv < sqlite3VarintLen(nHdr)) nHdr++; }
  u8 *p = qv_alloc(&X->A, nHdr + nData + 1); if (!p) { qv_why = "arena"; return 0; }
  u8 *h = p + putVarint32(p, nHdr), *d = p + nHdr;
  for (int k = 0; k < n; k++) {
    Mem *x = &f[k];
    h += putVarint32(h, st[k]);
    switch (st[k]) {
      case 0: case 8: case 9: break;
      case 7: { u64 u; double r = (x->flags & MEM_Real) ? x->u.r : (double)x->u.i; memcpy(&u, &r, 8); for (int b = 7; b >= 0; b--) { d[b] = (u8)u; u >>= 8; } d += 8; break; }
      case 1: case 2: case 3: case 4: case 5: case 6: {
        u64 u = (u64)x->u.i; u32 len = ln[k];
        for (int b = (int)len - 1; b >= 0; b--) { d[b] = (u8)u; u >>= 8; }
        d += len; break;
      }
      default: if (ln[k]) memcpy(d, x->z, ln[k]); d += ln[k];
    }
  }
  qv_static(out, p, (int)(nHdr + nData), 0, 0); return 1;
}

/* ---------------------------------------------------------------- cursors */
static int qv_cur_alloc(QvX *X, QvCur *C, int nField) {
  C->nField = nField; (void)X;
  if (C->capField < nField + 2) {
    sqlite3_free(C->aType); sqlite3_free(C->aOff);
    C->aType = sqlite3_malloc64(sizeof(u32) * (u64)(nField + 2)); C->aOff = sqlite3_malloc64(sizeof(u32) * (u64)(nField + 2));
    if (!C->aType || !C->aOff) { C->capField = 0; qv_why = "oom"; return 0; }
    C->capField = nField + 2;
  }
  return 1;
}
static void *qv_bcpool[64]; static int qv_nbc;   /* BtCursor memory for ephemeral cursors, reused */
static BtCursor *qv_bc_alloc(void) {
  BtCursor *c = qv_nbc ? qv_bcpool[--qv_nbc] : sqlite3_malloc64(sqlite3BtreeCursorSize());
  if (c) sqlite3BtreeCursorZero(c);
  return c;
}
static void qv_bc_free(BtCursor *c) { if (qv_nbc < 64) qv_bcpool[qv_nbc++] = c; else sqlite3_free(c); }
static void qv_cur_close(QvCur *C) {   /* (closing the last cursor of a BTREE_SINGLE B-tree closes the B-tree) */
  if (C->kind == QVC_EPH && C->bc) { sqlite3BtreeCloseCursor(C->bc); qv_bc_free(C->bc); }
  qv_cur_reset(C);
}
static inline void qv_stale(QvCur *C) { C->rowOk = 0; }
static inline void qv_stale_eph(QvX *X) { X->ephGen++; }
static int qv_vec_grow(QvX *X, QvVec *V) {
  int nc = V->cap ? V->cap * 2 : 32; QvVecEnt *ne = qv_alloc(&X->A, sizeof *ne * (size_t)nc);
  if (!ne) { qv_why = "arena"; return 0; }
  if (V->n) memcpy(ne, V->e, sizeof *ne * (size_t)V->n);
  V->e = ne; V->cap = nc; return 1;
}
static int qv_vec_find(const QvVec *V, i64 rowid, int *at) {   /* binary search among [first, n); 1 found (maybe dead) */
  int lo = V->first, hi = V->n;
  while (lo < hi) { int m = (lo + hi) >> 1; if (V->e[m].rowid < rowid) lo = m + 1; else hi = m; }
  *at = lo; return lo < V->n && V->e[lo].rowid == rowid;
}
static inline int qv_vec_next(const QvVec *V, int i) { for (i++; i < V->n && V->e[i].dead; i++) {} return i; }
static inline int qv_vec_prev(const QvVec *V, int i) { for (i--; i >= V->first && V->e[i].dead; i--) {} return i; }
static void qv_vec_stale(QvX *X, const QvVec *V) { for (int c = 0; c < X->P->nCur; c++) if (X->c[c].kind == QVC_VEC && X->c[c].vec == V) X->c[c].rowOk = 0; }
#define QV_VEC_DEOPT(why) do { X->P->vecOff = 1; qv_why = "vec deopt: " why; return 0; } while (0)   /* a write moved cells: no cached ephemeral row is valid (vdbe.c: colCacheCtr++) */
/* the cursor's position is final and its row's record is at C->row (header not yet parsed): 0 = fallback,
   with C->nullRow set when the row turned out to be gone */
static int qv_row(QvX *X, QvCur *C) {
  if (C->kind == QVC_PSEUDO) {   /* the register's record, whenever it changes */
    Mem *r = &X->r[C->pseudoReg];
    if (!(r->flags & MEM_Blob)) { qv_why = "pseudo"; return 0; }
    if (C->rowOk && C->row == (const u8 *)r->z && C->szRow == (u32)r->n) return 1;
    C->row = (const u8 *)r->z; C->payload = C->szRow = (u32)r->n;
  } else if (C->kind == QVC_VEC) {
    QvVec *V = C->vec;
    if (C->vbad == 2) { X->P->vecOff = 1; qv_why = "vec deopt: row after a missed seek"; return 0; }
    if (C->vbad || C->vi < V->first || C->vi >= V->n || V->e[C->vi].dead) { C->nullRow = 1; return 1; }   /* deleted under us: vdbe.c's moved cursor, a NULL row */
    if (C->rowOk && C->rowVi == C->vi) return 1;
    C->row = V->e[C->vi].rec; C->payload = C->szRow = V->e[C->vi].len; C->rowVi = C->vi; C->rowPage = 0;
  } else if (C->rowOk && (C->kind != QVC_EPH || C->rowGen == X->ephGen)) return 1;
  else if (C->kind == QVC_SORT) {
    QvSort *S = C->srt; if (S->pos >= S->n) { qv_why = "sorter row"; return 0; }
    C->row = S->rec[S->pos]; C->payload = C->szRow = S->len[S->pos];
  } else {
    BtCursor *bc = C->bc;
    if (C->deferred) {   /* sqlite3VdbeFinishMoveto */
      int res; if (sqlite3BtreeTableMoveto(bc, C->movetoTarget, 0, &res) != SQLITE_OK || res) { qv_why = "deferred seek"; return 0; }
      C->deferred = 0;
    } else if (sqlite3BtreeCursorHasMoved(bc)) {
      int diff = 0; if (sqlite3BtreeCursorRestore(bc, &diff) != SQLITE_OK) { qv_why = "restore"; return 0; }
      if (diff) { C->nullRow = 1; return 1; }
    }
    u32 amt; C->payload = sqlite3BtreePayloadSize(bc); C->row = sqlite3BtreePayloadFetch(bc, &amt); C->szRow = amt;
    C->rowPage = 0;
    if (amt < C->payload) {   /* an overflow record: the whole payload, copied */
      u8 *buf = qv_alloc(&X->A, C->payload + 1); if (!buf) { qv_why = "arena"; return 0; }
      if (sqlite3BtreePayload(bc, 0, C->payload, buf) != SQLITE_OK) { qv_why = "payload"; return 0; }
      C->row = buf; C->szRow = C->payload;
    } else if (C->kind == QVC_BT) C->rowPage = bc->pPage->pDbPage;   /* pinned when a text or blob value points into it */
  }
  const u8 *z = C->row;
  if (C->szRow < 1) { qv_why = "empty record"; return 0; }
  u32 hdr; C->hdrOff = z[0] < 0x80 ? (hdr = z[0], 1) : sqlite3GetVarint32(z, &hdr);
  if (hdr > C->szRow || hdr > 98307) { qv_why = "corrupt record"; return 0; }
  C->aOff[0] = hdr; C->nHdr = 0; C->rowOk = 1; C->rowGen = X->ephGen;
  return 1;
}
/* the current row's header parsed through field p2, or to its end (fewer fields); 0 = corrupt */
static QV_INLINE int qv_hdr(QvCur *C, int p2) {
  const u8 *z = C->row, *zEnd = z + C->aOff[0];
  u32 i = (u32)C->nHdr; u64 off = C->aOff[i]; const u8 *h = z + C->hdrOff;
  while (i <= (u32)p2 && h < zEnd) {
    u32 t; if ((t = h[0]) < 0x80) h++; else h += sqlite3GetVarint32(h, &t);
    C->aType[i] = t; off += sqlite3VdbeSerialTypeLen(t); C->aOff[++i] = (u32)off;
  }
  if ((h >= zEnd && (h > zEnd || off != C->payload)) || off > C->payload) {
    if (C->aOff[0] != 0) { qv_why = "corrupt record"; return 0; }
    i = 0; h = zEnd;
  }
  C->nHdr = (int)i; C->hdrOff = (u32)(h - z);
  return 1;
}
/* OP_Column: field p2 of the cursor's current row into register m (released); 0 = fallback */
static QV_INLINE int qv_column(QvX *X, QvCur *C, int p2, const Op *op, Mem *m) {
  for (;;) {
    if (C->nullRow && C->kind != QVC_PSEUDO) { m->flags = MEM_Null; return 1; }
    if (C->deferred && C->altMap && C->altMap[1 + p2] > 0) { p2 = C->altMap[1 + p2] - 1; C = C->alt; continue; }
    break;
  }
  if (!qv_row(X, C)) return 0;
  if (C->nullRow && C->kind != QVC_PSEUDO) { m->flags = MEM_Null; return 1; }
  if (p2 >= C->nField) { qv_why = "column index"; return 0; }
  if (C->nHdr <= p2) {
    if (!qv_hdr(C, p2)) return 0;
    if (C->nHdr <= p2) {   /* fewer fields than the table now has: the column's default (ALTER TABLE ADD COLUMN) */
      if (op->p4type == P4_MEM) sqlite3VdbeMemShallowCopy(m, op->p4.pMem, MEM_Static);
      else m->flags = MEM_Null;
      return 1;
    }
  }
  u32 t = C->aType[p2];
  if (t >= 14 && C->rowPage && C->pinned != C->rowPage && !C->copyVals) {   /* a non-empty text or blob stays in the page: pin it */
    if (!qv_pin(X, C->rowPage)) return 0;
    C->pinned = C->rowPage;
  }
  return qv_serial_mem(X, t, C->row + C->aOff[p2], m, C->copyVals);
}

/* ---------------------------------------------------------------- sorter: stable, as vdbeSorterSort */
static int qv_decode(const u8 *z, u32 n, int nk, QcVal *o) {   /* the first nk fields of a record (values point into it) */
  u32 hdr, off, t; const u8 *h = z, *he;
  h += z[0] < 0x80 ? (hdr = z[0], 1) : sqlite3GetVarint32(z, &hdr);
  if (hdr > n) return 0;
  he = z + hdr; off = hdr;
  for (int k = 0; k < nk; k++) {
    if (h >= he) { for (; k < nk; k++) { o[k].type = SQLITE_NULL; o[k].n = 0; } return 1; }
    if ((t = *h) < 0x80) h++; else h += sqlite3GetVarint32(h, &t);
    u32 len = sqlite3VdbeSerialTypeLen(t);
    if (off + len > n || !qv_serial_val(t, z + off, &o[k])) return 0;
    off += len;
  }
  return 1;
}
/* vdbeRecordCompare on decoded keys: per field the value order under its collation, DESC and BIGNULL as the
   KeyInfo says; equal keys compare equal (the sort keeps them in insertion order) */
static int qv_keycmp(QvX *X, const KeyInfo *ki, const QcVal *a, const QcVal *b, int nk) {
  for (int i = 0; i < nk; i++) {
    int c = qv_cmp(X, &a[i], &b[i], ki->aColl[i]);
    if (!c) continue;
    int f = ki->aSortFlags[i];
    if (f && (!(f & KEYINFO_ORDER_BIGNULL) || ((f & KEYINFO_ORDER_DESC) != 0) != (a[i].type == SQLITE_NULL || b[i].type == SQLITE_NULL))) c = -c;
    return c;
  }
  return 0;
}
static int qv_sort(QvX *X, QvSort *S) {
  int n = S->n, nk = S->nk; if (n < 2) return 1;
  int *ix = qv_alloc(&X->A, sizeof *ix * (size_t)n), *tx = qv_alloc(&X->A, sizeof *tx * (size_t)n);
  const u8 **nr = qv_alloc(&X->A, sizeof *nr * (size_t)n); u32 *nl = qv_alloc(&X->A, sizeof *nl * (size_t)n);
  if (!ix || !tx || !nr || !nl) { qv_why = "arena"; return 0; }
  for (int i = 0; i < n; i++) ix[i] = i;
  for (int w = 1; w < n; w *= 2) {   /* bottom-up merge sort of indices; on ties the earlier insertion first */
    for (int lo = 0; lo < n; lo += 2 * w) {
      int mid = lo + w < n ? lo + w : n, hi = lo + 2 * w < n ? lo + 2 * w : n, i = lo, j = mid, k = lo;
      while (i < mid && j < hi) tx[k++] = qv_keycmp(X, S->ki, &S->key[(size_t)ix[i] * nk], &S->key[(size_t)ix[j] * nk], nk) <= 0 ? ix[i++] : ix[j++];
      while (i < mid) tx[k++] = ix[i++];
      while (j < hi) tx[k++] = ix[j++];
    }
    int *t = ix; ix = tx; tx = t;
  }
  for (int i = 0; i < n; i++) { nr[i] = S->rec[ix[i]]; nl[i] = S->len[ix[i]]; }
  memcpy(S->rec, nr, sizeof *nr * (size_t)n); memcpy(S->len, nl, sizeof *nl * (size_t)n);   /* in place: the arrays keep their capacity */
  return 1;   /* (the keys are not needed after the sort; a ResetSorter starts them again) */
}

/* ---------------------------------------------------------------- functions and aggregates */
static int qv_policy(const FuncDef *f) {   /* built-ins (not unsafe or direct-only), or deterministic user functions */
  if (f->funcFlags & (SQLITE_FUNC_UNSAFE | SQLITE_FUNC_DIRECT | SQLITE_FUNC_INTERNAL)) return 0;
  return (f->funcFlags & SQLITE_FUNC_BUILTIN) || (f->funcFlags & SQLITE_FUNC_CONSTANT);
}
/* a function's context, built once per opcode (vdbe.c keeps one in P4); the arguments are the registers */
typedef struct QvCtx { Mem res; union { sqlite3_context c; char b[sizeof(sqlite3_context) + QV_MAXARGS * sizeof(sqlite3_value *)]; } u; } QvCtx;
static QvCtx *qv_ctx(QvX *X, int iOp, FuncDef *f, int argc, int p2) {
  QvCtx *k = X->octx[iOp];
  if (!k) {
    if (!(k = sqlite3_malloc64(sizeof *k))) { qv_why = "oom"; return 0; }
    memset(&k->u.c, 0, sizeof k->u.c); sqlite3VdbeMemInit(&k->res, X->db, MEM_Null);
    k->u.c.pFunc = f; k->u.c.pVdbe = X->v; k->u.c.iOp = iOp; k->u.c.enc = SQLITE_UTF8; k->u.c.argc = (u16)argc;
    for (int i = 0; i < argc; i++) k->u.c.argv[i] = &X->r[p2 + i];
    X->octx[iOp] = k;
  }
  k->u.c.isError = 0; k->u.c.skipFlag = 0;
  return k;
}
/* length() of text or a blob in line (lengthFunc: characters up to the first NUL, a lead byte >= 0xc0 swallows the
   continuation bytes after it); numbers go to lengthFunc */
static int qv_length(const Mem *x, Mem *o) {
  u16 f = x->flags;
  if (f & MEM_Null) { o->flags = MEM_Null; return 1; }
  if ((f & (MEM_Int | MEM_Real | MEM_IntReal)) || (f & MEM_Zero)) return 0;
  if (f & MEM_Blob) { qv_int(o, x->n); return 1; }
  if (!(f & MEM_Str) || x->enc != SQLITE_UTF8) return 0;
  qv_int(o, qc_utf8_chars((const u8 *)x->z, x->n)); return 1;
}
static int qv_function(QvX *X, const Op *op, int pc) {   /* OP_Function: as vdbe.c, into register P3 */
  sqlite3_context *pc4 = op->p4.pCtx; FuncDef *f = pc4->pFunc; int argc = pc4->argc;
  Mem *out = qv_out(X, op->p3);
  if (f->xSFunc == lengthFunc && argc == 1 && qv_length(&X->r[op->p2], out)) return 1;
  QvCtx *k = qv_ctx(X, pc, f, argc, op->p2); if (!k) return 0;
  k->u.c.pOut = out; k->u.c.pMem = 0;
  MemSetTypeFlag(out, MEM_Null);
  f->xSFunc(&k->u.c, argc, k->u.c.argv);
  if (k->u.c.isError || X->db->mallocFailed) { qv_why = "function error"; return 0; }
  if ((out->flags & MEM_Str) && out->enc != SQLITE_UTF8) { qv_why = "encoding"; return 0; }
  return 1;
}
/* the native integer sum becomes SQLite's SumCtx in the accumulator register, as sumStep would have built it */
static int qv_sum_spill(QvX *X, const Op *op, int r) {
  struct QvSum *a = &X->P->sacc[r];
  sqlite3_context c; memset(&c, 0, sizeof c);
  c.pMem = &X->r[r]; c.pFunc = op->p4type == P4_FUNCDEF ? op->p4.pFunc : op->p4.pCtx->pFunc;
  if (c.pMem->flags & MEM_Agg) { qv_why = "sum state"; return 0; }
  SumCtx *p = sqlite3_aggregate_context(&c, sizeof *p);
  if (!p) { qv_why = "oom"; return 0; }
  p->iSum = a->iSum; p->cnt = a->cnt; p->approx = 0; p->ovrfl = 0;
  a->spilled = 1;
  return 1;
}
static int qv_aggstep(QvX *X, const Op *op, int pc, int inverse) {   /* OP_AggStep1 */
  FuncDef *f = op->p4type == P4_FUNCDEF ? op->p4.pFunc : op->p4.pCtx->pFunc; int argc = op->p5;
  Mem *acc = &X->r[op->p3];
  QvCtx *k = qv_ctx(X, pc, f, argc, op->p2); if (!k) return 0;
  k->u.c.pMem = acc; k->u.c.pOut = &k->res;
  acc->n++;
  if (inverse) f->xInverse(&k->u.c, argc, k->u.c.argv); else f->xSFunc(&k->u.c, argc, k->u.c.argv);
  int ok = k->u.c.isError <= 0 && !X->db->mallocFailed;   /* (-1: sqlite3SkipAccumulatorLoad, a min/max row that changed nothing) */
  if (!ok) qv_why = "aggregate error";
  if (ok && k->u.c.skipFlag && pc > 0 && X->v->aOp[pc - 1].opcode == OP_CollSeq && X->v->aOp[pc - 1].p1) qv_int(qv_out(X, X->v->aOp[pc - 1].p1), 1);
  if (VdbeMemDynamic(&k->res) || k->res.szMalloc) sqlite3VdbeMemRelease(&k->res);
  k->res.flags = MEM_Null;
  return ok;
}
static int qv_aggfinal(QvX *X, const Op *op) {   /* AggFinal, or AggValue (P3) */
  FuncDef *f = op->p4.pFunc; Mem *acc = &X->r[op->p1]; int rc;
  if (op->p3) rc = sqlite3VdbeMemAggValue(acc, qv_out(X, op->p3), f);
  else rc = sqlite3VdbeMemFinalize(acc, f);
  if (rc) { qv_why = "aggregate final"; return 0; }
  Mem *m = op->p3 ? &X->r[op->p3] : acc;
  if ((m->flags & MEM_Str) && m->enc != SQLITE_UTF8) { qv_why = "encoding"; return 0; }
  return 1;
}

/* ---------------------------------------------------------------- the lifter: is every opcode one qvm runs? */
static int qv_op_ok(Vdbe *v, const Op *o) {
  switch (o->opcode) {
    case OP_Init: case OP_Goto: case OP_Gosub: case OP_Return: case OP_BeginSubrtn: case OP_InitCoroutine:
    case OP_Yield: case OP_EndCoroutine: case OP_Halt: case OP_Integer: case OP_Int64: case OP_Real: case OP_String8:
    case OP_Blob: case OP_Variable: case OP_Copy: case OP_SCopy: case OP_IntCopy: case OP_Move: case OP_SoftNull:
    case OP_Null: case OP_ResultRow: case OP_Noop: case OP_Explain: case OP_Once: case OP_If: case OP_IfNot:
    case OP_IsNull: case OP_NotNull: case OP_ZeroOrNull: case OP_IfPos: case OP_IfNotZero: case OP_DecrJumpZero:
    case OP_OffsetLimit: case OP_AddImm: case OP_MustBeInt: case OP_RealAffinity: case OP_Cast: case OP_Affinity:
    case OP_Eq: case OP_Ne: case OP_Lt: case OP_Le: case OP_Gt: case OP_Ge: case OP_ElseEq: case OP_Compare:
    case OP_Jump: case OP_Permutation: case OP_Not: case OP_BitNot: case OP_And: case OP_Or: case OP_IsTrue:
    case OP_BitAnd: case OP_BitOr: case OP_ShiftLeft: case OP_ShiftRight: case OP_Add: case OP_Subtract:
    case OP_Multiply: case OP_Divide: case OP_Remainder: case OP_Concat: case OP_AggValue: case OP_AggFinal:
    case OP_CollSeq: case OP_OpenEphemeral: case OP_OpenAutoindex: case OP_OpenDup: case OP_OpenPseudo:
    case OP_SorterOpen: case OP_Close: case OP_ColumnsUsed: case OP_CursorHint: case OP_NullRow: case OP_IfNullRow:
    case OP_Rewind: case OP_Sort: case OP_SorterSort: case OP_Last: case OP_Next: case OP_Prev: case OP_SorterNext:
    case OP_SorterData: case OP_SorterInsert: case OP_SorterCompare: case OP_Sequence: case OP_SequenceTest:
    case OP_SeekGE: case OP_SeekGT: case OP_SeekLE: case OP_SeekLT: case OP_SeekRowid: case OP_NotExists:
    case OP_IdxGT: case OP_IdxGE: case OP_IdxLT: case OP_IdxLE: case OP_DeferredSeek: case OP_FinishSeek:
    case OP_IdxRowid: case OP_Rowid: case OP_Column: case OP_RowData: case OP_MakeRecord: case OP_IdxInsert:
    case OP_Insert: case OP_NewRowid: case OP_Delete: case OP_ResetSorter: case OP_Found: case OP_NotFound:
    case OP_NoConflict: case OP_IfNoHope: case OP_SeekHit: case OP_Filter: case OP_FilterAdd: case OP_Count:
    case OP_SeekScan: case OP_IfEmpty: case OP_Transaction: case OP_TableLock: case OP_RowSetAdd: case OP_RowSetRead:
    case OP_ClrSubtype:
      return 1;
    case OP_RowSetTest: return o->p4type == P4_INT32;
    case OP_String: return o->p3 == 0 || (o->p3 > 0 && o->p3 <= v->nMem);   /* P3: the LIKE optimization's blob pass (qv_str) */
    case OP_OpenRead: case OP_ReopenIdx: return o->p4type == P4_INT32 || o->p4type == P4_KEYINFO;
    case OP_Function: case OP_PureFunc:
      return o->p4type == P4_FUNCCTX && o->p4.pCtx->argc <= QV_MAXARGS && qv_policy(o->p4.pCtx->pFunc);
    case OP_AggStep: case OP_AggInverse: case OP_AggStep1: {
      const FuncDef *f = o->p4type == P4_FUNCDEF ? o->p4.pFunc : o->p4type == P4_FUNCCTX ? o->p4.pCtx->pFunc : 0;
      return f && o->p5 <= QV_MAXARGS && qv_policy(f) && (o->opcode != OP_AggInverse || f->xInverse);
    }
  }
  (void)v; return 0;
}
static int qv_cursor_op(int opc) {   /* opcodes whose P1 is a cursor */
  switch (opc) {
    case OP_Rewind: case OP_Last: case OP_Next: case OP_Prev: case OP_Column: case OP_Rowid: case OP_RowData: case OP_SeekRowid:
    case OP_NotExists: case OP_NewRowid: case OP_Insert: case OP_Delete: case OP_ResetSorter: case OP_NullRow: case OP_IfNullRow:
    case OP_IfEmpty: case OP_Close: case OP_Count: case OP_OpenDup: case OP_OpenEphemeral: case OP_Sort: case OP_SorterSort:
    case OP_Found: case OP_NotFound: case OP_IdxInsert: case OP_NoConflict: case OP_SeekGE: case OP_SeekGT: case OP_SeekLE:
    case OP_SeekLT: case OP_IdxGT: case OP_IdxGE: case OP_IdxLT: case OP_IdxLE: case OP_IdxRowid: case OP_OpenRead: case OP_ReopenIdx:
    case OP_OpenPseudo: case OP_SorterOpen: case OP_SorterInsert: case OP_SorterData: case OP_SorterNext: case OP_SorterCompare:
    case OP_Sequence: case OP_SequenceTest: case OP_IfNoHope: case OP_SeekHit: case OP_FinishSeek: case OP_OpenAutoindex:
    case OP_DeferredSeek: case OP_IdxDelete: case OP_SeekEnd: case OP_CursorHint: case OP_ColumnsUsed: case OP_Filter: case OP_FilterAdd:
      return 1;
  }
  return 0;
}
static void qv_free(QvPlan *P);
static int qv_lift(Vdbe *v) {
  Op *aOp = v->aOp; int nOp = v->nOp, ntx = 0, iDb = -1, cookie = 0, gen = 0, nout = -1;
  if (v->nMem > 65536 || v->nCursor > 1024 || aOp[0].opcode != OP_Init) { qc_why = "qvm size"; return 0; }
  for (int pc = 0; pc < nOp; pc++) {
    Op *o = &aOp[pc];
    if (!qv_op_ok(v, o)) { qc_why = sqlite3OpcodeName(o->opcode); return 0; }
    switch (o->opcode) {
      case OP_Transaction:
        if (o->p2 != 0 || ntx++ || o->p4type != P4_INT32) { qc_why = "qvm transaction"; return 0; }
        iDb = o->p1; cookie = o->p3; gen = o->p4.i; break;
      case OP_TableLock: if (o->p3) { qc_why = "write lock"; return 0; } break;
      case OP_ResultRow:
        if (nout >= 0 && nout != o->p2) { qc_why = "result widths"; return 0; }
        nout = o->p2; break;
      case OP_NewRowid: if (o->p3) { qc_why = "autoincrement"; return 0; } break;
    }
  }
  for (int pc = 0; pc < nOp; pc++)   /* what vdbe.c's OP_String8 does on its first run (UTF-8): an OP_String with the length */
    if (aOp[pc].opcode == OP_String8 && aOp[pc].p4.z && strlen(aOp[pc].p4.z) <= (size_t)v->db->aLimit[SQLITE_LIMIT_LENGTH]) {
      aOp[pc].p1 = sqlite3Strlen30(aOp[pc].p4.z); aOp[pc].opcode = OP_String;
    }
  if (nout < 0 || nout > QC_MAXOUT * 4) { qc_why = "qvm program"; return 0; }   /* no Transaction: a program that reads no table */
  for (int pc = 0; pc < nOp; pc++) if ((aOp[pc].opcode == OP_OpenRead || aOp[pc].opcode == OP_ReopenIdx) && aOp[pc].p3 != iDb) { qc_why = "qvm database"; return 0; }
  QvPlan *P = sqlite3MallocZero(sizeof *P + (sizeof(BtCursor *) + sizeof(Pgno) + 1) * (size_t)(v->nCursor + 1));
  if (!P) return 0;
  P->kind = 3; P->iDb = iDb; P->cookie = cookie; P->gen = gen; P->nout = nout; P->nMem = v->nMem; P->nCur = v->nCursor; P->nOp = nOp;
  P->bc = (BtCursor **)(P + 1); P->bcRoot = (Pgno *)(P->bc + v->nCursor + 1); P->bopen = (u8 *)(P->bcRoot + v->nCursor + 1);
  P->r = sqlite3MallocZero(sizeof(Mem) * (u64)(P->nMem + 1));
  P->c = sqlite3MallocZero(sizeof(QvCur) * (u64)(P->nCur + 1));
  P->octx = sqlite3MallocZero(sizeof(void *) * (u64)nOp);
  P->once = sqlite3MallocZero((u64)(nOp / 8 + 1));
  P->isCnt = sqlite3MallocZero((u64)(P->nMem + 1)); P->cnt = sqlite3MallocZero(sizeof(i64) * (u64)(P->nMem + 1));
  P->keep = sqlite3MallocZero(sizeof *P->keep * (u64)(P->nCur + 1));
  P->isVec = sqlite3MallocZero((u64)(P->nCur + 1));
  if (P->isVec) {   /* ephemeral rowid tables whose cursor family (OpenDup) only uses what a vector reproduces */
    int *fam = sqlite3MallocZero(sizeof(int) * (u64)(P->nCur + 1));
    if (fam) {
      for (int c = 0; c <= P->nCur; c++) fam[c] = -1;
      for (int pc = 0; pc < nOp; pc++) if ((aOp[pc].opcode == OP_OpenEphemeral) && aOp[pc].p4type != P4_KEYINFO && aOp[pc].p1 <= P->nCur) fam[aOp[pc].p1] = aOp[pc].p1;
      for (int pc = 0; pc < nOp; pc++) if (aOp[pc].opcode == OP_OpenDup && aOp[pc].p2 <= P->nCur && fam[aOp[pc].p2] >= 0) fam[aOp[pc].p1] = fam[aOp[pc].p2];
      for (int c = 0; c <= P->nCur; c++) if (fam[c] >= 0) P->isVec[c] = 1;
      for (int pc = 0; pc < nOp; pc++) {
        Op *o = &aOp[pc]; int c = -1, ok = 0;
        switch (o->opcode) {   /* opcodes whose P1 is a cursor */
          case OP_Rewind: case OP_Last: case OP_Next: case OP_Prev: case OP_Column: case OP_Rowid: case OP_RowData:
          case OP_SeekRowid: case OP_NotExists: case OP_NewRowid: case OP_Insert: case OP_Delete: case OP_ResetSorter:
          case OP_NullRow: case OP_IfNullRow: case OP_IfEmpty: case OP_Close: case OP_Count: case OP_OpenDup: case OP_OpenEphemeral:
            c = o->p1; ok = 1; break;
          case OP_Sort: case OP_SorterSort: case OP_Found: case OP_NotFound: case OP_IdxInsert: case OP_NoConflict: case OP_SeekGE:
          case OP_SeekGT: case OP_SeekLE: case OP_SeekLT: case OP_IdxGT: case OP_IdxGE: case OP_IdxLT: case OP_IdxLE: case OP_IdxRowid:
          case OP_OpenRead: case OP_ReopenIdx: case OP_OpenPseudo: case OP_SorterOpen: case OP_SorterInsert: case OP_SorterData:
          case OP_SorterNext: case OP_SorterCompare: case OP_Sequence: case OP_SequenceTest: case OP_IfNoHope: case OP_SeekHit:
          case OP_FinishSeek: case OP_OpenAutoindex:
            c = o->p1; ok = 0; break;
          case OP_DeferredSeek: c = o->p3; ok = 0; break;
        }
        if (c >= 0 && c <= P->nCur && fam[c] >= 0 && !ok) { int f = fam[c]; for (int k = 0; k <= P->nCur; k++) if (fam[k] == f) P->isVec[k] = 0; }
        if (o->opcode == OP_DeferredSeek && o->p1 <= P->nCur && fam[o->p1] >= 0) { int f = fam[o->p1]; for (int k = 0; k <= P->nCur; k++) if (fam[k] == f) P->isVec[k] = 0; }
      }
      sqlite3_free(fam);
    }
  }
  P->isHash = sqlite3MallocZero((u64)(P->nCur + 1));
  static int nohash = -1; if (nohash < 0) nohash = getenv("QV_NOHASH") != 0;   /* (A/B against the B-tree) */
  if (P->isHash && !nohash) {   /* an index whose cursor only sees OpenEphemeral, Found/NotFound on N registers, IdxInsert of a MakeRecord of N, Close, ResetSorter */
    for (int pc = 0; pc < nOp; pc++) {
      Op *o = &aOp[pc]; if (o->opcode != OP_OpenEphemeral || o->p4type != P4_KEYINFO || o->p1 > P->nCur) continue;
      int c = o->p1, n = 0, ok = 1; const KeyInfo *ki = o->p4.pKeyInfo;
      for (int q = 0; q < nOp && ok; q++) {
        Op *x = &aOp[q]; int on = -1;
        switch (x->opcode) {   /* (every opcode whose P1, or DeferredSeek's P3, can be a cursor) */
          case OP_OpenEphemeral: if (x->p1 == c && (x->p4type != P4_KEYINFO || x->p4.pKeyInfo != ki)) ok = 0; break;
          case OP_Close: case OP_ResetSorter: break;
          case OP_Found: case OP_NotFound: if (x->p1 == c) on = x->p4.i > 0 ? x->p4.i : 0; break;
          case OP_IdxInsert:
            if (x->p1 != c) break;
            on = (q > 0 && aOp[q - 1].opcode == OP_MakeRecord && aOp[q - 1].p3 == x->p2) ? aOp[q - 1].p2 : 0;
            for (int j = 0; j < nOp && on; j++) {   /* reached only from that MakeRecord */
              const Op *y = &aOp[j];
              if (((sqlite3OpcodeProperty[y->opcode] & OPFLG_JUMP) && y->p2 == q) || (y->opcode == OP_Jump && (y->p1 == q || y->p3 == q))) on = 0;
            }
            break;
          case OP_DeferredSeek: if (x->p3 == c || x->p1 == c) ok = 0; break;
          case OP_OpenDup: if (x->p2 == c || x->p1 == c) ok = 0; break;
          default: if (x->p1 == c && qv_cursor_op(x->opcode)) ok = 0; break;
        }
        if (on == 0) ok = 0;
        else if (on > 0) { if (n && n != on) ok = 0; n = on; }
      }
      if (ok && n > 0 && n <= QV_MAXARGS && n <= ki->nAllField) {
        for (int i = 0; i < n; i++) if (ki->aColl[i] && !sqlite3IsBinary(ki->aColl[i])) ok = 0;   /* equality is byte equality */
        if (ok) P->isHash[c] = (u8)n;
      }
    }
  }
  if (!P->r || !P->c || !P->octx || !P->once || !P->isCnt || !P->cnt || !P->keep || !P->isVec || !P->isHash || qv_nplans >= 64) { qc_why = "plans"; qv_free(P); return 0; }   /* (out of memory: what was allocated so far, freed) */
  for (int r = 0; r <= P->nMem; r++) sqlite3VdbeMemInit(&P->r[r], v->db, MEM_Null);
  for (int pc = 0; pc < nOp; pc++) {   /* a register is a native counter when every aggregate opcode on it is count() */
    Op *o = &aOp[pc]; int r = -1;
    if (o->opcode == OP_AggStep || o->opcode == OP_AggInverse || o->opcode == OP_AggStep1) r = o->p3;
    else if (o->opcode == OP_AggFinal || o->opcode == OP_AggValue) r = o->p1;
    if (r < 0) continue;
    const FuncDef *f = o->p4type == P4_FUNCDEF ? o->p4.pFunc : o->p4type == P4_FUNCCTX ? o->p4.pCtx->pFunc : 0;
    int isCount = f && f->xSFunc == countStep && f->xFinalize == countFinalize && (o->opcode == OP_AggFinal || o->opcode == OP_AggValue || o->p5 <= 1);
    P->isCnt[r] = P->isCnt[r] == 2 ? 2 : isCount ? 1 : 2;
  }
  for (int r = 0; r <= P->nMem; r++) if (P->isCnt[r] == 2) P->isCnt[r] = 0;
  P->isSum = sqlite3MallocZero((u64)(P->nMem + 1)); P->sacc = sqlite3MallocZero(sizeof *P->sacc * (u64)(P->nMem + 1));
  P->fb = sqlite3MallocZero((u64)nOp + 1);
  if (!P->isSum || !P->sacc || !P->fb) { qc_why = "plans"; qv_free(P); return 0; }
  for (int pc = 0; pc < nOp; pc++) {   /* sum / total / avg of one argument, the same function on every opcode of the register */
    Op *o = &aOp[pc]; int r = -1;
    if (o->opcode == OP_AggStep || o->opcode == OP_AggInverse || o->opcode == OP_AggStep1) r = o->p3;
    else if (o->opcode == OP_AggFinal || o->opcode == OP_AggValue) r = o->p1;
    if (r < 0) continue;
    const FuncDef *f = o->p4type == P4_FUNCDEF ? o->p4.pFunc : o->p4type == P4_FUNCCTX ? o->p4.pCtx->pFunc : 0;
    int k = 0;
    if (f && f->xSFunc == sumStep && (o->opcode == OP_AggFinal || o->opcode == OP_AggValue || o->p5 == 1))
      k = f->xFinalize == sumFinalize ? 1 : f->xFinalize == totalFinalize ? 2 : f->xFinalize == avgFinalize ? 3 : 0;
    P->isSum[r] = (P->isSum[r] == 255 || !k || (P->isSum[r] && P->isSum[r] != k)) ? 255 : (u8)k;
  }
  for (int r = 0; r <= P->nMem; r++) if (P->isSum[r] == 255 || P->isCnt[r]) P->isSum[r] = 0;
  v->pQc = P; v->qcWant = 1; qv_plans[qv_nplans++] = P;
  return 1;
}

/* ---------------------------------------------------------------- the interpreter */
static const u8 qv_LT[] = {[OP_Ne] = 1, [OP_Eq] = 0, [OP_Gt] = 0, [OP_Le] = 1, [OP_Lt] = 1, [OP_Ge] = 0};
static const u8 qv_EQ[] = {[OP_Ne] = 0, [OP_Eq] = 1, [OP_Gt] = 0, [OP_Le] = 1, [OP_Lt] = 0, [OP_Ge] = 1};
static const u8 qv_GT[] = {[OP_Ne] = 1, [OP_Eq] = 0, [OP_Gt] = 1, [OP_Le] = 0, [OP_Lt] = 0, [OP_Ge] = 1};
/* OP_Eq..OP_Ge as vdbe.c: 1 jump, 0 not; sets iCompare */
static int qv_compare_op(QvX *X, const Op *op) {
  Mem *pIn1 = &X->r[op->p1], *pIn3 = &X->r[op->p3];
  u16 flags1 = pIn1->flags, flags3 = pIn3->flags; int res;
  if (flags1 & flags3 & MEM_Int) {
    res = pIn3->u.i > pIn1->u.i ? 1 : pIn3->u.i < pIn1->u.i ? -1 : 0;
    X->iCompare = res;
    return res < 0 ? qv_LT[op->opcode] : res == 0 ? qv_EQ[op->opcode] : qv_GT[op->opcode];
  }
  if ((flags1 | flags3) & MEM_Null) {
    if (op->p5 & SQLITE_NULLEQ) {
      res = ((flags1 & flags3 & MEM_Null) && !(flags3 & MEM_Cleared)) ? 0 : ((flags3 & MEM_Null) ? -1 : +1);
    } else {
      X->iCompare = 1;
      return (op->p5 & SQLITE_JUMPIFNULL) ? 1 : 0;
    }
  } else {
    char affinity = op->p5 & SQLITE_AFF_MASK;
    if (affinity >= SQLITE_AFF_NUMERIC) {
      if ((flags1 | flags3) & MEM_Str) {
        if ((flags1 & (MEM_Int | MEM_IntReal | MEM_Real | MEM_Str)) == MEM_Str) { applyNumericAffinity(pIn1, 0); flags3 = pIn3->flags; }
        if ((flags3 & (MEM_Int | MEM_IntReal | MEM_Real | MEM_Str)) == MEM_Str) applyNumericAffinity(pIn3, 0);
      }
    } else if (affinity == SQLITE_AFF_TEXT && ((flags1 | flags3) & MEM_Str)) {
      if (flags1 & MEM_Str) pIn1->flags &= ~(MEM_Int | MEM_Real | MEM_IntReal);
      else if (flags1 & (MEM_Int | MEM_Real | MEM_IntReal)) {
        sqlite3VdbeMemStringify(pIn1, SQLITE_UTF8, 1);
        flags1 = (pIn1->flags & ~MEM_TypeMask) | (flags1 & MEM_TypeMask);
        if (pIn1 == pIn3) flags3 = flags1 | MEM_Str;
      }
      if (flags3 & MEM_Str) pIn3->flags &= ~(MEM_Int | MEM_Real | MEM_IntReal);
      else if (flags3 & (MEM_Int | MEM_Real | MEM_IntReal)) {
        sqlite3VdbeMemStringify(pIn3, SQLITE_UTF8, 1);
        flags3 = (pIn3->flags & ~MEM_TypeMask) | (flags3 & MEM_TypeMask);
      }
    }
    res = sqlite3MemCompare(pIn3, pIn1, op->p4type == P4_COLLSEQ ? op->p4.pColl : 0);
  }
  X->iCompare = res;
  pIn3->flags = flags3; pIn1->flags = flags1;   /* undo applyAffinity()'s changes */
  return res < 0 ? qv_LT[op->opcode] : res == 0 ? qv_EQ[op->opcode] : qv_GT[op->opcode];
}
/* OP_Add..OP_Remainder as vdbe.c */
static void qv_arith(QvX *X, const Op *op) {
  Mem *pIn1 = &X->r[op->p1], *pIn2 = &X->r[op->p2]; u16 type1 = pIn1->flags, type2 = pIn2->flags; i64 iA, iB; double rA, rB;
  Mem *pOut = qv_out(X, op->p3);
  if (type1 & type2 & MEM_Int) {
  int_math:
    iA = pIn1->u.i; iB = pIn2->u.i;
    switch (op->opcode) {
      case OP_Add: if (sqlite3AddInt64(&iB, iA)) goto fp_math; break;
      case OP_Subtract: if (sqlite3SubInt64(&iB, iA)) goto fp_math; break;
      case OP_Multiply: if (sqlite3MulInt64(&iB, iA)) goto fp_math; break;
      case OP_Divide: if (iA == 0) goto is_null; if (iA == -1 && iB == SMALLEST_INT64) goto fp_math; iB /= iA; break;
      default: if (iA == 0) goto is_null; if (iA == -1) iA = 1; iB %= iA; break;
    }
    qv_int(pOut, iB); return;
  } else if ((type1 | type2) & MEM_Null) goto is_null;
  type1 = numericType(pIn1); type2 = numericType(pIn2);
  if (type1 & type2 & MEM_Int) goto int_math;
fp_math:
  rA = sqlite3VdbeRealValue(pIn1); rB = sqlite3VdbeRealValue(pIn2);
  switch (op->opcode) {
    case OP_Add: rB += rA; break;
    case OP_Subtract: rB -= rA; break;
    case OP_Multiply: rB *= rA; break;
    case OP_Divide: if (rA == (double)0) goto is_null; rB /= rA; break;
    default: iA = sqlite3VdbeIntValue(pIn1); iB = sqlite3VdbeIntValue(pIn2); if (iA == 0) goto is_null; if (iA == -1) iA = 1; rB = (double)(iB % iA); break;
  }
  if (sqlite3IsNaN(rB)) goto is_null;
  pOut->u.r = rB; pOut->flags = MEM_Real; return;
is_null:
  pOut->flags = MEM_Null;
}
static int qv_cursor_db(QvX *X, const Op *op, QvCur *C) {   /* OpenRead / ReopenIdx: the plan's cursor for this number */
  QvPlan *P = X->P; int i = op->p1; Pgno root = (Pgno)op->p2; KeyInfo *ki = op->p4type == P4_KEYINFO ? op->p4.pKeyInfo : 0;
  if (P->bopen[i] && P->bcRoot[i] != root) { sqlite3BtreeCloseCursor(P->bc[i]); P->bopen[i] = 0; }
  if (!P->bopen[i]) {
    if (!P->bc[i] && !(P->bc[i] = sqlite3MallocZero(sqlite3BtreeCursorSize()))) return 0;
    sqlite3BtreeCursorZero(P->bc[i]);
    if (sqlite3BtreeCursor(P->bt, root, 0, ki, P->bc[i]) != SQLITE_OK) { qv_why = "cursor"; return 0; }
    P->bopen[i] = 1; P->bcRoot[i] = root;
  }
  qv_cur_reset(C);
  C->kind = QVC_BT; C->bc = P->bc[i]; C->ki = ki; C->isTable = !ki; C->nullRow = 1;
  C->eqOnly = (op->p5 & OPFLAG_SEEKEQ) != 0;
  return qv_cur_alloc(X, C, ki ? ki->nAllField : op->p4.i);
}
/* ---------------------------------------------------------------- hash sets
** A membership-only ephemeral index (DISTINCT, count(DISTINCT)) as a hash set of its keys. Equality is what the
** index's comparison (sqlite3VdbeRecordCompare, BINARY collations, default_rc 0) decides: NULL equals NULL, numbers
** by value (an integer and an integral real are equal), text and blobs by their bytes, no type equal to another. */
typedef struct QvHk { u8 c; i64 i; double r; const u8 *z; int n; } QvHk;   /* c: 0 null, 1 a number with an integer value, 2 another real, 3 text, 4 blob */
static inline void qv_hk_num(QvHk *k, double r) {
  if (r >= -9223372036854775808.0 && r < 9223372036854775808.0 && (double)(i64)r == r) { k->c = 1; k->i = (i64)r; } else { k->c = 2; k->r = r; }
}
static inline int qv_hk_mem(const Mem *m, QvHk *k) {   /* in RecordCompare's order of a register's types */
  u16 f = m->flags;
  if (f & (MEM_Int | MEM_IntReal)) { k->c = 1; k->i = m->u.i; }
  else if (f & MEM_Real) qv_hk_num(k, m->u.r);
  else if (f & MEM_Str) { if (m->enc != SQLITE_UTF8) return 0; k->c = 3; k->z = (const u8 *)m->z; k->n = m->n; }
  else if (f & MEM_Blob) { if (f & MEM_Zero) return 0; k->c = 4; k->z = (const u8 *)m->z; k->n = m->n; }
  else k->c = 0;
  return 1;
}
static inline void qv_hk_val(const QcVal *v, QvHk *k) {
  switch (v->type) {
    case SQLITE_INTEGER: k->c = 1; k->i = v->i; break;
    case SQLITE_FLOAT: qv_hk_num(k, v->r); break;
    case SQLITE_TEXT: k->c = 3; k->z = v->z; k->n = v->n; break;
    case SQLITE_BLOB: k->c = 4; k->z = v->z; k->n = v->n; break;
    default: k->c = 0;
  }
}
static inline u64 qv_hmix(u64 h, u64 v) { h = (h ^ v) * 0x9e3779b97f4a7c15ull; return h ^ (h >> 29); }
static u64 qv_hk_hash(const QvHk *k, int nk) {
  u64 h = 0x243f6a8885a308d3ull;
  for (int i = 0; i < nk; i++, k++) {
    h = qv_hmix(h, k->c);
    if (k->c == 1) h = qv_hmix(h, (u64)k->i);
    else if (k->c == 2) { u64 b; memcpy(&b, &k->r, 8); h = qv_hmix(h, b); }
    else if (k->c >= 3) {
      int j = 0; for (; j + 8 <= k->n; j += 8) { u64 w; memcpy(&w, k->z + j, 8); h = qv_hmix(h, w); }
      u64 w = 0; memcpy(&w, k->z + j, (size_t)(k->n - j)); h = qv_hmix(h, w ^ ((u64)k->n << 56));
    }
  }
  return h;
}
static inline int qv_hk_eq(const QvHk *a, const QvHk *b, int nk) {
  for (int i = 0; i < nk; i++) {
    if (a[i].c != b[i].c) return 0;
    if (a[i].c == 1 ? a[i].i != b[i].i : a[i].c == 2 ? a[i].r != b[i].r : a[i].c >= 3 && (a[i].n != b[i].n || memcmp(a[i].z, b[i].z, (size_t)a[i].n))) return 0;
  }
  return 1;
}
/* the slot of key k (hash h): 1 present, 0 the empty slot it would take; -1 a stored record that doesn't decode */
static int qv_hs_find(const QvHset *H, const QvHk *k, int nk, u64 h, u32 *slot) {
  if (!H->cap) { *slot = 0; return 0; }
  QcVal v[QV_MAXARGS]; QvHk s[QV_MAXARGS];
  for (u32 i = (u32)h & (H->cap - 1);; i = (i + 1) & (H->cap - 1)) {
    if (!H->rec[i]) { *slot = i; return 0; }
    if (H->hv[i] != h) continue;
    const u8 *z = H->rec[i]; u32 n = (u32)(H->hv[H->cap + i]);   /* (the length is kept after the hashes) */
    if (!qv_decode(z, n, nk, v)) return -1;
    for (int j = 0; j < nk; j++) qv_hk_val(&v[j], &s[j]);
    if (qv_hk_eq(k, s, nk)) { *slot = i; return 1; }
  }
}
static int qv_hs_insert(QvX *X, QvHset *H, const u8 *rec, u32 len, int nk) {
  QcVal v[QV_MAXARGS]; QvHk k[QV_MAXARGS]; u32 slot;
  if (!qv_decode(rec, len, nk, v)) { qv_why = "hash record"; return 0; }
  for (int j = 0; j < nk; j++) qv_hk_val(&v[j], &k[j]);
  u64 h = qv_hk_hash(k, nk);
  if ((H->n + 1) * 2 > H->cap) {   /* grown in the arena (a set lives for one execution) */
    u32 nc = H->cap ? H->cap * 2 : 64;
    u64 *nh = qv_alloc(&X->A, sizeof *nh * 2 * (size_t)nc); const u8 **nr = qv_alloc(&X->A, sizeof *nr * (size_t)nc);
    if (!nh || !nr) { qv_why = "arena"; return 0; }
    memset(nr, 0, sizeof *nr * (size_t)nc);
    for (u32 i = 0; i < H->cap; i++) if (H->rec[i]) {
      u32 j = (u32)H->hv[i] & (nc - 1); while (nr[j]) j = (j + 1) & (nc - 1);
      nh[j] = H->hv[i]; nh[nc + j] = H->hv[H->cap + i]; nr[j] = H->rec[i];
    }
    H->hv = nh; H->rec = nr; H->cap = nc;
  }
  int f = qv_hs_find(H, k, nk, h, &slot);
  if (f < 0) { qv_why = "hash record"; return 0; }
  if (f) return 1;   /* (an equal key: the index would replace it, a set already has it) */
  H->hv[slot] = h; H->hv[H->cap + slot] = len; H->rec[slot] = rec; H->n++;
  return 1;
}
static int qv_open_eph(QvX *X, const Op *op, QvCur *C) {
  static const int vfsFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXCLUSIVE | SQLITE_OPEN_DELETEONCLOSE | SQLITE_OPEN_TRANSIENT_DB;
  KeyInfo *ki = op->p4type == P4_KEYINFO ? op->p4.pKeyInfo : 0;
  if (op->p3 > 0) { Mem *e = qv_out(X, op->p3); qv_static(e, "", 0, 0, 0); }   /* an empty record for Insert */
  if (!ki && X->P->isVec[op->p1] && !X->P->vecOff) {   /* a vector table */
    if (C->kind == QVC_VEC && !C->noReuse) { QvVec *V = C->vec; V->n = V->first = V->live = 0; C->nullRow = 1; C->vbad = 1; qv_stale(C); C->seqCount = 0; return 1; }
    if (C->kind) qv_cur_close(C);
    if (!(C->vec = qv_alloc(&X->A, sizeof *C->vec))) { qv_why = "arena"; return 0; }
    memset(C->vec, 0, sizeof *C->vec);
    C->kind = QVC_VEC; C->isTable = 1; C->nullRow = 1; C->vbad = 1; C->owner = 1;
    return qv_cur_alloc(X, C, op->p2);
  }
  if (ki && X->P->isHash[op->p1] && !X->P->hashOff) {   /* a hash set */
    if (C->kind) qv_cur_close(C);
    if (!(C->hs = qv_alloc(&X->A, sizeof *C->hs))) { qv_why = "arena"; return 0; }
    memset(C->hs, 0, sizeof *C->hs);
    C->kind = QVC_HASH; C->ki = ki; C->hk = X->P->isHash[op->p1]; C->nullRow = 1;
    return 1;
  }
  if (C->kind == QVC_EPH && !C->noReuse && C->ebt) {   /* reopened, no duplicates: emptied (vdbe: ClearTable) */
    C->seqCount = 0; qv_stale(C); C->nullRow = 1;
    if (sqlite3BtreeClearTable(C->ebt, (int)C->eroot, 0) != SQLITE_OK) { qv_why = "eph clear"; return 0; }
    qv_stale_eph(X);
    return 1;
  }
  if (C->kind) qv_cur_close(C);
  struct QvEphKeep *k = &X->P->keep[op->p1];
  if (k->bt && k->ki == ki && k->p5 == op->p5) {   /* the one this statement kept from its last run: emptied */
    C->kind = QVC_EPH; C->copyVals = 1; C->ki = ki; C->isTable = !ki; C->nullRow = 1; C->owner = 1; C->ep5 = op->p5;
    C->ebt = k->bt; C->bc = k->bc; C->eroot = k->root; k->bt = 0;
    if (sqlite3BtreeClearTable(C->ebt, (int)C->eroot, 0) != SQLITE_OK) { qv_why = "eph clear"; return 0; }
    qv_stale_eph(X);
    return qv_cur_alloc(X, C, ki ? ki->nAllField : op->p2);
  }
  C->kind = QVC_EPH; C->copyVals = 1; C->ki = ki; C->isTable = !ki; C->nullRow = 1; C->owner = 1; C->ep5 = op->p5;
  if (!(C->bc = qv_bc_alloc())) return 0;
  if (sqlite3BtreeOpen(X->db->pVfs, 0, X->db, &C->ebt, BTREE_OMIT_JOURNAL | BTREE_SINGLE | op->p5, vfsFlags) != SQLITE_OK) { C->ebt = 0; qv_why = "eph open"; return 0; }
  if (sqlite3BtreeBeginTrans(C->ebt, 1, 0) != SQLITE_OK || (ki && sqlite3BtreeCreateTable(C->ebt, &C->eroot, BTREE_BLOBKEY | op->p5) != SQLITE_OK) ||
      sqlite3BtreeCursor(C->ebt, ki ? C->eroot : SCHEMA_ROOT, BTREE_WRCSR, ki, C->bc) != SQLITE_OK) {
    sqlite3BtreeClose(C->ebt); C->ebt = 0; qv_bc_free(C->bc); C->bc = 0; C->kind = 0; qv_why = "eph open"; return 0;   /* no cursor yet: closed here */
  }
  if (!ki) C->eroot = SCHEMA_ROOT;
  return qv_cur_alloc(X, C, ki ? ki->nAllField : op->p2);
}
static int qv_found(QvX *X, QvCur *C, const Op *op) {   /* Found / NotFound / NoConflict / IfNoHope: the seek; 1 ok */
  int nf = op->p4.i, rc;
  if (C->kind == QVC_HASH) {   /* (the lifter saw nf == the set's key width) */
    QvHk k[QV_MAXARGS]; u32 slot;
    for (int i = 0; i < nf; i++) if (!qv_hk_mem(&X->r[op->p3 + i], &k[i])) { X->P->hashOff = 1; qv_why = "hash deopt: key"; return 0; }
    rc = qv_hs_find(C->hs, k, nf, qv_hk_hash(k, nf), &slot);
    if (rc < 0) { qv_why = "hash record"; return 0; }
    C->seekResult = !rc;
    return 1;
  }
  if (nf > 0) {
    UnpackedRecord r; memset(&r, 0, sizeof r);
    r.pKeyInfo = C->ki; r.nField = (u16)nf; r.default_rc = 0; r.aMem = &X->r[op->p3];
    rc = sqlite3BtreeIndexMoveto(C->bc, &r, &C->seekResult);
  } else {
    Mem *x = &X->r[op->p3];
    if (!(x->flags & MEM_Blob) || (x->flags & MEM_Zero)) { qv_why = "found key"; return 0; }
    UnpackedRecord *pk = sqlite3VdbeAllocUnpackedRecord(C->ki); if (!pk) return 0;
    sqlite3VdbeRecordUnpack(x->n, x->z, pk); pk->default_rc = 0;
    rc = sqlite3BtreeIndexMoveto(C->bc, pk, &C->seekResult);
    sqlite3DbFree(X->db, pk);
  }
  if (rc) { qv_why = "found"; return 0; }
  return 1;
}

/* ---------------------------------------------------------------- opcode bodies shared by qv_run and the regions
   (in line in both: qv_run had them in its cases) */
/* OP_String (and String8, made String by the lifter) as vdbe.c: without SQLITE_LIKE_DOESNT_MATCH_BLOBS, register P3
   equal to P5 makes the value a BLOB (the second pass of the LIKE optimization's range over an index) */
static QV_INLINE void qv_str(QvX *X, Mem *R, const Op *op, Mem *o) {
  qv_static(o, op->p4.z, op->p1, 1, op->p4.z[op->p1] == 0);
#ifndef SQLITE_LIKE_DOESNT_MATCH_BLOBS
  if (op->p3 > 0 && R[op->p3].u.i == op->p5) o->flags = MEM_Blob | MEM_Static | MEM_Term;
#endif
  (void)X;
}
/* a loop's back edge, where vdbe.c checks too (jump_to_p2_and_check_for_interrupt): sqlite3_interrupt() and the
   progress handler stop the run, and the statement goes back to SQLite, which reports them as it would. The handler
   runs every nProgressOps iterations here, not opcodes: as a time limit that is the same thing. */
#define QV_TICK 64   /* iterations between checks: the loops stay cheap, and stopping 64 rows later is the same stop */
static QV_NOINLINE int qv_tick_check(QvX *X) {
  sqlite3 *db = X->db;
  X->tick = QV_TICK;
  if (AtomicLoad(&db->u1.isInterrupted)) { qv_why = "interrupted"; return 0; }
#ifndef SQLITE_OMIT_PROGRESS_CALLBACK
  if (db->xProgress) {
    for (X->nprog += QV_TICK; X->nprog >= db->nProgressOps; X->nprog -= db->nProgressOps)
      if (db->xProgress(db->pProgressArg)) { qv_why = "progress handler"; return 0; }
  }
#endif
  return 1;
}
static QV_INLINE int qv_tick(QvX *X) { return --X->tick > 0 || qv_tick_check(X); }
static QV_INLINE int qv_result(QvX *X, Mem *R, QvCur *Cs, const Op *op) {   /* OP_ResultRow: the row appended to the output */
  size_t need = ((size_t)X->nrow + 1) * (size_t)op->p2;
  if (need > X->cout) {
    size_t nc = X->cout ? X->cout * 2 : 256; while (nc < need) nc *= 2;
    if (nc > ((size_t)1 << 22)) { qv_why = "rows"; return 0; }
    QcVal *no = sqlite3_realloc64(X->out, sizeof *no * (u64)nc); if (!no) return 0;
    X->out = no; X->cout = nc;
  }
  QcVal *o = &X->out[(size_t)X->nrow * (size_t)op->p2]; const Mem *V = &R[op->p1];
  for (int k = 0; k < op->p2; k++) if (!qv_val(X, &V[k], &o[k])) return 0;
  X->nrow++;
  return 1;
}
static QV_INLINE int qv_aggop(QvX *X, Mem *R, QvCur *Cs, const Op *op, int pc) {   /* OP_AggStep / AggStep1 / AggInverse */
  int inv = op->opcode == OP_AggInverse || (op->opcode == OP_AggStep1 && op->p1); QvPlan *P = X->P;
  if (P->isCnt[op->p3]) {   /* count(*) / count(x) */
    if (op->p5 == 0 || !qv_isnull(&R[op->p2])) P->cnt[op->p3] += inv ? -1 : 1;
    return 1;
  }
  if (P->isSum[op->p3] && !P->sacc[op->p3].spilled) {   /* sum / total / avg of integers */
    struct QvSum *a = &P->sacc[op->p3]; Mem *x = &R[op->p2];
    if (x->flags & MEM_Null) return 1;
    if (x->flags & MEM_Int) {
      i64 t = a->iSum;
      if (!(inv ? sqlite3SubInt64(&t, x->u.i) : sqlite3AddInt64(&t, x->u.i))) { a->iSum = t; a->cnt += inv ? -1 : 1; return 1; }
    }
    if (!qv_sum_spill(X, op, op->p3)) return 0;   /* SQLite's own path from here on */
  }
  return qv_aggstep(X, op, pc, inv);
}
static QV_INLINE int qv_idxcmp(QvX *X, Mem *R, QvCur *Cs, const Op *op) {   /* OP_IdxLE / IdxGT / IdxLT / IdxGE: 1 jump, 0 not, -1 fallback */
  QvCur *C = &Cs[op->p1]; UnpackedRecord r; int res;
  BtCursor *bc = C->bc; const Mem *k = &R[op->p3];
  if (op->p4.i == 1 && (k->flags & MEM_Int) && bc && bc->eState == CURSOR_VALID && !bc->curIntKey && C->ki && C->ki->aSortFlags[0] == 0) {
    /* one integer key against an ascending first field: read it from the cell (qc_idx_cmp: NULL < numbers < text <
       blob, reals between the integers), as vdbeRecordCompareInt would; equal keys give default_rc */
    const MemPage *pg = bc->pPage; int c;
    if (C->kind == QVC_BT) {   /* a database page, read-only for the run: its cell area once per page (pointer and number: a reused buffer is another page) */
      if (C->cpg != pg || C->cpgno != pg->pgno) { C->cpg = pg; C->cpgno = pg->pgno; C->clo = qc_cell_lo(pg); C->cend = pg->aData + X->usable; }
      const u8 *cell = pg->aData + get2byteAligned(&pg->aCellIdx[2 * bc->ix]);
      i64 v; c = cell < C->clo || cell > C->cend - 4 ? 2 : qc_idx_cmp_kind(qc_idxkey_at(pg, cell, C->cend, &v), v, k->u.i);
    } else c = qc_idx_cmp(pg, bc->ix, k->u.i);
    if (c != 2) {
      res = c ? c : (op->opcode < OP_IdxLT ? -1 : 0);
      if ((op->opcode & 1) == (OP_IdxLT & 1)) res = -res; else res++;
      return res > 0;
    }
  }
  memset(&r, 0, sizeof r);   /* otherwise vdbe.c's own comparison (sqlite3VdbeIdxKeyCompare) */
  r.pKeyInfo = C->ki; r.nField = (u16)op->p4.i; r.default_rc = op->opcode < OP_IdxLT ? -1 : 0; r.aMem = &R[op->p3];
  i64 sz = sqlite3BtreePayloadSize(C->bc); u32 amt;
  if (sz <= 0 || sz > 0x7fffffff) { qv_why = "corrupt index record"; return -1; }
  const u8 *rec = sqlite3BtreePayloadFetch(C->bc, &amt);
  if (amt < sz) {   /* an overflow record, copied */
    u8 *buf = qv_alloc(&X->A, (size_t)sz + 1); if (!buf || sqlite3BtreePayload(C->bc, 0, (u32)sz, buf) != SQLITE_OK) { qv_why = "idx payload"; return -1; }
    rec = buf;
  }
  res = sqlite3VdbeRecordCompareWithSkip((int)sz, rec, &r, 0);
  if (r.errCode) { qv_why = "idx compare"; return -1; }
  if ((op->opcode & 1) == (OP_IdxLT & 1)) res = -res; else res++;
  return res > 0;
}
static QV_INLINE int qv_copy(QvX *X, Mem *R, QvCur *Cs, const Op *op) {   /* OP_Copy */
  for (int k = 0; k <= op->p3; k++) {
    Mem *o = qv_out(X, op->p2 + k), *in = &R[op->p1 + k];
    if (!(in->flags & (MEM_Str | MEM_Blob | MEM_Agg | MEM_Dyn | MEM_Subtype))) { o->flags = in->flags & ~(MEM_Ephem | MEM_Static); o->u = in->u; o->n = in->n; continue; }   /* a number or NULL: nothing to own */
    sqlite3VdbeMemShallowCopy(o, in, MEM_Ephem);
    if ((o->flags & MEM_Ephem) && sqlite3VdbeMemMakeWriteable(o)) return 0;   /* Deephemeralize */
    if ((o->flags & MEM_Subtype) && (op->p5 & 0x0002)) o->flags &= ~MEM_Subtype;
  }
  return 1;
}
static QV_INLINE void qv_scopy(QvX *X, Mem *R, QvCur *Cs, const Op *op) {   /* OP_SCopy */
  Mem *o = qv_out(X, op->p2), *in = &R[op->p1];
  if (!(in->flags & (MEM_Str | MEM_Blob | MEM_Agg | MEM_Dyn | MEM_Subtype))) { o->flags = in->flags & ~(MEM_Ephem | MEM_Static); o->u = in->u; o->n = in->n; return; }
  sqlite3VdbeMemShallowCopy(o, in, MEM_Ephem);
}
static QV_INLINE void qv_null(QvX *X, Mem *R, QvCur *Cs, const Op *op) {   /* OP_Null / BeginSubrtn */
  u16 nf = op->p1 ? (MEM_Null | MEM_Cleared) : MEM_Null;
  for (int k = op->p2; k <= (op->p3 > op->p2 ? op->p3 : op->p2); k++) { Mem *o = qv_out(X, k); o->flags = nf; o->n = 0; }
}
static QV_INLINE int qv_colop(QvX *X, Mem *R, QvCur *Cs, const Op *op) {   /* OP_Column */
  QvCur *C = &Cs[op->p1];
  if (!C->kind) { qv_why = "column cursor"; return 0; }
  Mem *o = qv_out(X, op->p3);
  if (C->kind == QVC_PSEUDO && C->pseudoReg == op->p3) { qv_why = "column into its record"; return 0; }
  return qv_column(X, C, op->p2, op, o);
}

static QV_INLINE int qv_mkrec(QvX *X, Mem *R, QvCur *Cs, const Op *op) {   /* OP_MakeRecord */
  if (op->p4type == P4_STATIC || op->p4type == P4_DYNAMIC) {
    const char *z = op->p4.z; Mem *x = &R[op->p1];
    for (int k = 0; z[k]; k++, x++) {
      applyAffinity(x, z[k], SQLITE_UTF8);
      if (z[k] == SQLITE_AFF_REAL && (x->flags & MEM_Int)) { x->flags |= MEM_IntReal; x->flags &= ~MEM_Int; }
    }
  }
  Mem rec; memset(&rec, 0, sizeof rec);
  if (!qv_make_record(X, &R[op->p1], op->p2, &rec)) return 0;
  Mem *o = qv_out(X, op->p3); qv_static(o, rec.z, rec.n, 0, 0);
  return 1;
}
/* vdbesort.c's limits: its records stay in memory while they fit in mxPmaSize (the cache size in bytes, at least
   szPma pages); past that it writes sorted runs to disk and merges them, which can order equal keys differently from
   one in-memory sort. qvm hands the statement back where SQLite would write its first run. No limit with an
   in-memory temp store, as vdbesort.c. */
static void qv_sort_limits(QvX *X, QvSort *S) {
  sqlite3 *db = X->db;
  if (sqlite3TempInMemory(db)) { S->lim = S->mn = 0; return; }
  i64 pgsz = sqlite3BtreeGetPageSize(db->aDb[0].pBt), mx = db->aDb[0].pSchema->cache_size;
  mx = mx < 0 ? mx * -1024 : mx * pgsz;
  if (mx > SQLITE_MAX_PMASZ) mx = SQLITE_MAX_PMASZ;
  S->mn = (i64)sqlite3GlobalConfig.szPma * pgsz;
  S->lim = mx > S->mn ? mx : S->mn;
}
static QV_INLINE int qv_sorterins(QvX *X, Mem *R, QvCur *Cs, const Op *op) {   /* OP_SorterInsert */
  QvCur *C = &Cs[op->p1]; QvSort *S = C->srt; Mem *x = &R[op->p2];
  if (!(x->flags & MEM_Blob) || (x->flags & MEM_Zero)) { qv_why = "sorter record"; return 0; }
  const u8 *rec = (const u8 *)x->z;
  if (!(x->flags & MEM_Static)) { u8 *c = qv_alloc(&X->A, (size_t)x->n + 1); if (!c) { qv_why = "arena"; return 0; } memcpy(c, x->z, (size_t)x->n); rec = c; }
  if (S->n == S->cap) {
    int nc = S->cap ? S->cap * 2 : 64;
    const u8 **nr = qv_alloc(&X->A, sizeof *nr * (size_t)nc); u32 *nl = qv_alloc(&X->A, sizeof *nl * (size_t)nc);
    QcVal *nk = qv_alloc(&X->A, sizeof *nk * (size_t)nc * (size_t)S->nk);
    if (!nr || !nl || !nk) { qv_why = "arena"; return 0; }
    if (S->n) { memcpy(nr, S->rec, sizeof *nr * (size_t)S->n); memcpy(nl, S->len, sizeof *nl * (size_t)S->n); memcpy(nk, S->key, sizeof *nk * (size_t)S->n * (size_t)S->nk); }
    S->rec = nr; S->len = nl; S->key = nk; S->cap = nc;
  }
  if (S->lim) {   /* (at least vdbesort's own count of the memory, so qvm hands back no later than it would spill) */
    S->mem += ((i64)x->n + (i64)sizeof(SorterRecord) + 7) & ~(i64)7;
    if (S->mem > S->lim || (S->mem > S->mn && sqlite3HeapNearlyFull())) { qv_why = "sorter would spill"; return 0; }
  }
  if (!qv_decode(rec, (u32)x->n, S->nk, &S->key[(size_t)S->n * S->nk])) { qv_why = "sorter key"; return 0; }
  S->rec[S->n] = rec; S->len[S->n] = (u32)x->n; S->n++;
  return 1;
}

static QV_INLINE void qv_cmpvec(QvX *X, Mem *R, QvCur *Cs, const Op *op) {   /* OP_Compare */
  const u32 *perm = (op->p5 & OPFLAG_PERMUTE) ? X->aPermute : 0; const KeyInfo *ki = op->p4.pKeyInfo;
  int done = 0;
  for (int i = 0; i < op->p3 && !done; i++) {
    u32 idx = perm ? perm[i] : (u32)i; Mem *a = &R[op->p1 + idx], *b = &R[op->p2 + idx];
    if ((a->flags & b->flags & MEM_Int) && !((a->flags | b->flags) & MEM_Null)) X->iCompare = a->u.i < b->u.i ? -1 : a->u.i > b->u.i;   /* sqlite3MemCompare's integer case */
    else X->iCompare = sqlite3MemCompare(a, b, ki->aColl[i]);
    if (X->iCompare) {
      if ((ki->aSortFlags[i] & KEYINFO_ORDER_BIGNULL) && ((R[op->p1 + idx].flags & MEM_Null) || (R[op->p2 + idx].flags & MEM_Null))) X->iCompare = -X->iCompare;
      if (ki->aSortFlags[i] & KEYINFO_ORDER_DESC) X->iCompare = -X->iCompare;
      done = 1;
    }
  }
}
static QV_INLINE int qv_move(QvX *X, Mem *R, QvCur *Cs, const Op *op) {   /* OP_Move */
  for (int k = 0; k < op->p3; k++) {
    Mem *o = qv_out(X, op->p2 + k);
    if (X->P->isCnt[op->p1 + k]) { qv_why = "move of a counter"; return 0; }
    sqlite3VdbeMemMove(o, &R[op->p1 + k]);
    if ((o->flags & MEM_Ephem) && sqlite3VdbeMemMakeWriteable(o)) return 0;
  }
  return 1;
}
static QV_INLINE void qv_bitop(QvX *X, Mem *R, QvCur *Cs, const Op *op) {   /* OP_BitAnd / BitOr / ShiftLeft / ShiftRight */
  Mem *pIn1 = &R[op->p1], *pIn2 = &R[op->p2];
  if ((pIn1->flags | pIn2->flags) & MEM_Null) { qv_out(X, op->p3)->flags = MEM_Null; return; }
  i64 iA = sqlite3VdbeIntValue(pIn2), iB = sqlite3VdbeIntValue(pIn1); u64 uA; u8 o = op->opcode;
  if (o == OP_BitAnd) iA &= iB;
  else if (o == OP_BitOr) iA |= iB;
  else if (iB != 0) {
    if (iB < 0) { o = 2 * OP_ShiftLeft + 1 - o; iB = iB > (-64) ? -iB : 64; }
    if (iB >= 64) iA = (iA >= 0 || o == OP_ShiftLeft) ? 0 : -1;
    else {
      memcpy(&uA, &iA, sizeof uA);
      if (o == OP_ShiftLeft) uA <<= iB; else { uA >>= iB; if (iA < 0) uA |= ((((u64)0xffffffff) << 32) | 0xffffffff) << (64 - iB); }
      memcpy(&iA, &uA, sizeof iA);
    }
  }
  qv_int(qv_out(X, op->p3), iA);
}

#ifdef QV_TRACE
static volatile int qv_trace_pc = -1, qv_trace_op = -1;   /* for a crash handler: where qvm was */
#define QV_TRACE_AT(pc, op) (qv_trace_pc = (pc), qv_trace_op = (op))
#else
#define QV_TRACE_AT(pc, op) ((void)0)
#endif
/* dispatch: threaded (each opcode jumps straight to the next one's code) where the compiler has labels as values,
   otherwise the switch */
#if defined(__GNUC__) && !defined(QV_NO_THREADED)
#define QL(x) L_##x:
#define QJUMP do { op = &aOp[pc]; QV_TRACE_AT(pc, op->opcode); goto *qv_disp[op->opcode]; } while (0)
#define QNEXT do { pc++; QJUMP; } while (0)
#define QV_UNUSED_LABEL __attribute__((unused))
#else
#define QL(x)
#define QJUMP goto qv_top
#define QNEXT goto qv_next
#define QV_UNUSED_LABEL
#endif
/* ---------------------------------------------------------------- regions: single-cursor loops, specialised
** A region is the body of a loop [B, N] whose N is a Next/Prev on one cursor, built once the plan has run a few
** times and has type feedback. Each opcode becomes a node: its handler (a label in qv_region, chosen for the opcode,
** its operands and the feedback) and its operands resolved to pointers. The handlers are the opcode bodies above, or
** in-line fast paths that check their preconditions and otherwise take that body: a region writes exactly what
** qv_run would, so leaving it is free at any opcode. The loop's own Next fetches the next row and parses its header
** through the last field the body reads (one decode per row instead of one per Column), and a Column the feedback
** says is always an integer reads its field directly; when that guess fails the node becomes the generic Column.
** An opcode without a node leaves the region (qv_run runs it and re-enters at the next Next); a region that leaves
** on more than a quarter of its rows turns itself off. */
enum { RG_EXIT, RG_NOP, RG_GOTO, RG_COL, RG_COLI, RG_ROWID, RG_IDXROWID, RG_CMP, RG_CMPI, RG_IF, RG_IFNOT, RG_ISNULL,
       RG_NOTNULL, RG_INT, RG_INT64, RG_STR, RG_NULL, RG_SCOPY, RG_COPY, RG_ARITH, RG_FUNC, RG_AGG, RG_RESULT, RG_IFPOS,
       RG_IFNZ, RG_DJZ, RG_IDXCMP, RG_MKREC, RG_SORTINS, RG_COMPARE, RG_JUMPCMP, RG_MOVE, RG_BITOP, RG_PERM, RG_GOSUB, RG_NEXT, RG_N };
typedef struct QvNode {
  const void *h; const Op *op; int pc, jn;   /* handler; the opcode; jn: the jump target's node, or -1 (leave at P2) */
  QvCur *C; Mem *a, *b, *o;                  /* cursor P1; inputs; the output register */
  u8 plain, ar, lt, eq, gt;                  /* plain: the output is no counter or sum; ar: + - * in line; the comparison's jumps */
  int jx[3];                                 /* OP_Jump: its three targets' nodes, or -1 */
} QvNode;
typedef struct QvRegion {
  int B, N, cur, maxf;                       /* N: the Next/Prev of cursor cur; maxf: the last field its Columns on cur read */
  QvNode *n;
  u64 iters, exits, misses; u8 off;
} QvRegion;
/* a region's slow path for Column: out of line, so the region's code stays small (qv_run has its own copy in line) */
static QV_NOINLINE int qv_colop_cold(QvX *X, Mem *R, QvCur *Cs, const Op *op) { return qv_colop(X, R, Cs, op); }
static const void *const *qv_rgl;            /* qv_region's handlers by kind (filled by a call without a region) */
static inline Mem *qv_rel(Mem *m) { if (VdbeMemDynamic(m)) sqlite3VdbeMemSetNull(m); return m; }
#if defined(__GNUC__) && !defined(QV_NO_THREADED)
static int qv_region(QvX *X, QvRegion *G, int *pcOut) {
  static const void *const L[RG_N] = {
    [RG_EXIT] = &&rg_exit, [RG_NOP] = &&rg_nop, [RG_GOTO] = &&rg_goto, [RG_COL] = &&rg_col, [RG_COLI] = &&rg_coli,
    [RG_ROWID] = &&rg_rowid, [RG_IDXROWID] = &&rg_idxrowid, [RG_CMP] = &&rg_cmp, [RG_CMPI] = &&rg_cmpi, [RG_IF] = &&rg_if,
    [RG_IFNOT] = &&rg_ifnot, [RG_ISNULL] = &&rg_isnull, [RG_NOTNULL] = &&rg_notnull, [RG_INT] = &&rg_int, [RG_INT64] = &&rg_int64,
    [RG_STR] = &&rg_str, [RG_NULL] = &&rg_null, [RG_SCOPY] = &&rg_scopy, [RG_COPY] = &&rg_copy, [RG_ARITH] = &&rg_arith,
    [RG_FUNC] = &&rg_func, [RG_AGG] = &&rg_agg, [RG_RESULT] = &&rg_result, [RG_IFPOS] = &&rg_ifpos, [RG_IFNZ] = &&rg_ifnz,
    [RG_DJZ] = &&rg_djz, [RG_IDXCMP] = &&rg_idxcmp, [RG_MKREC] = &&rg_mkrec, [RG_SORTINS] = &&rg_sortins,
    [RG_COMPARE] = &&rg_compare, [RG_JUMPCMP] = &&rg_jumpcmp, [RG_MOVE] = &&rg_move, [RG_BITOP] = &&rg_bitop, [RG_PERM] = &&rg_perm, [RG_GOSUB] = &&rg_gosub, [RG_NEXT] = &&rg_next };
  if (!G) { qv_rgl = L; return 1; }
  QvNode *n = &G->n[*pcOut - G->B]; Mem *R = X->r; QvCur *Cs = X->c;
#define RG_GO(i) do { n = &G->n[i]; QV_TRACE_AT(n->pc, n->op->opcode); goto *n->h; } while (0)
#define RG_NEXT do { n++; QV_TRACE_AT(n->pc, n->op->opcode); goto *n->h; } while (0)
#define RG_JUMP do { if (n->jn >= 0) RG_GO(n->jn); *pcOut = n->op->p2; return 1; } while (0)   /* (out of the body: the loop ends) */
#define RG_OUT(r) (n->plain ? qv_rel(n->o) : qv_out(X, (r)))
  QV_TRACE_AT(n->pc, n->op->opcode);
  goto *n->h;
rg_exit:   /* an opcode without a node: qv_run's, and back at the next Next */
  *pcOut = n->pc;
  if (++G->exits > 64 && G->exits > G->iters / 4) G->off = 1;   /* it leaves too often: qv_run's from now on */
  return 1;
rg_nop: RG_NEXT;
rg_goto: RG_JUMP;
rg_col: {
    QvCur *C = n->C; int p2 = n->op->p2;
    if (C->rowOk && !C->nullRow && !C->deferred && C->kind == QVC_BT && p2 < C->nHdr) {   /* the row's header is parsed: qv_column's last step */
      Mem *o = RG_OUT(n->op->p3); u32 t = C->aType[p2];
      if (t >= 14 && C->rowPage && C->pinned != C->rowPage && !C->copyVals) { if (!qv_pin(X, C->rowPage)) return 0; C->pinned = C->rowPage; }
      if (!qv_serial_mem(X, t, C->row + C->aOff[p2], o, C->copyVals)) return 0;
      RG_NEXT;
    }
    if (!qv_colop_cold(X, R, Cs, n->op)) return 0;
    RG_NEXT;
  }
rg_coli: {   /* speculated: an integer (serial types 1-6, 8, 9) */
    QvCur *C = n->C; int p2 = n->op->p2;
    if (C->rowOk && !C->nullRow && !C->deferred && C->kind == QVC_BT && p2 < C->nHdr) {
      u32 t = C->aType[p2];
      if (t - 1 < 6) { qv_int(qv_rel(n->o), qc_int(t, C->row + C->aOff[p2])); RG_NEXT; }
      if (t - 8 < 2) { qv_int(qv_rel(n->o), (i64)t - 8); RG_NEXT; }
      n->h = L[RG_COL]; G->misses++;   /* the guess failed: a generic Column from now on */
    }
    goto rg_col;
  }
rg_rowid: {
    QvCur *C = n->C;
    if (C->kind != QVC_BT || C->nullRow || C->deferred || sqlite3BtreeCursorHasMoved(C->bc)) goto rg_exit;
    qv_int(RG_OUT(n->op->p2), sqlite3BtreeIntegerKey(C->bc));
    RG_NEXT;
  }
rg_idxrowid: {
    QvCur *C = n->C; i64 rowid = 0;
    if (C->kind != QVC_BT || C->nullRow || sqlite3BtreeCursorHasMoved(C->bc)) goto rg_exit;
    if (sqlite3VdbeIdxRowid(X->db, C->bc, &rowid) != SQLITE_OK) { qv_why = "idxrowid"; return 0; }
    qv_int(RG_OUT(n->op->p2), rowid);
    RG_NEXT;
  }
rg_cmp: if (qv_compare_op(X, n->op)) RG_JUMP; RG_NEXT;
rg_cmpi: {   /* speculated: two integers (qv_compare_op's first case) */
    Mem *a = n->a, *b = n->b;
    if (a->flags & b->flags & MEM_Int) {
      int res = b->u.i > a->u.i ? 1 : b->u.i < a->u.i ? -1 : 0; X->iCompare = res;
      if (res < 0 ? n->lt : res ? n->gt : n->eq) RG_JUMP;
      RG_NEXT;
    }
    n->h = L[RG_CMP]; G->misses++;
    goto rg_cmp;
  }
rg_if: if (sqlite3VdbeBooleanValue(n->a, n->op->p3)) RG_JUMP; RG_NEXT;
rg_ifnot: if (!sqlite3VdbeBooleanValue(n->a, !n->op->p3)) RG_JUMP; RG_NEXT;
rg_isnull: if (qv_isnull(n->a)) RG_JUMP; RG_NEXT;
rg_notnull: if (!qv_isnull(n->a)) RG_JUMP; RG_NEXT;
rg_int: qv_int(RG_OUT(n->op->p2), n->op->p1); RG_NEXT;
rg_int64: qv_int(RG_OUT(n->op->p2), INT32_TO_64(n->op->p1, n->op->p3)); RG_NEXT;
rg_str: qv_str(X, R, n->op, RG_OUT(n->op->p2)); RG_NEXT;
rg_null: qv_null(X, R, Cs, n->op); RG_NEXT;
rg_scopy: qv_scopy(X, R, Cs, n->op); RG_NEXT;
rg_copy: if (!qv_copy(X, R, Cs, n->op)) return 0; RG_NEXT;
rg_arith: {
    Mem *a = n->a, *b = n->b;   /* P1, P2: P3 = P2 op P1 */
    if (n->ar && n->plain && (a->flags & b->flags & MEM_Int)) {
      i64 iB = b->u.i; int ovf = n->ar == 1 ? sqlite3AddInt64(&iB, a->u.i) : n->ar == 2 ? sqlite3SubInt64(&iB, a->u.i) : sqlite3MulInt64(&iB, a->u.i);
      if (!ovf) { qv_int(qv_rel(n->o), iB); RG_NEXT; }
    }
    qv_arith(X, n->op); RG_NEXT;
  }
rg_func: if (!qv_function(X, n->op, n->pc)) return 0; RG_NEXT;
rg_agg: if (!qv_aggop(X, R, Cs, n->op, n->pc)) return 0; RG_NEXT;
rg_result: if (!qv_result(X, R, Cs, n->op)) return 0; RG_NEXT;
rg_ifpos: { Mem *a = n->a; if (a->u.i > 0) { a->u.i -= n->op->p3; RG_JUMP; } RG_NEXT; }
rg_ifnz: { Mem *a = n->a; if (a->u.i) { if (a->u.i > 0) a->u.i--; RG_JUMP; } RG_NEXT; }
rg_djz: { Mem *a = n->a; if (a->u.i > SMALLEST_INT64) a->u.i--; if (a->u.i == 0) RG_JUMP; RG_NEXT; }
rg_idxcmp: { int r = qv_idxcmp(X, R, Cs, n->op); if (r < 0) return 0; if (r) RG_JUMP; RG_NEXT; }
rg_mkrec: if (!qv_mkrec(X, R, Cs, n->op)) return 0; RG_NEXT;
rg_sortins: if (!qv_sorterins(X, R, Cs, n->op)) return 0; RG_NEXT;
rg_compare: qv_cmpvec(X, R, Cs, n->op); RG_NEXT;
rg_jumpcmp: {   /* OP_Jump: P1 / P2 / P3 by the last Compare */
    int t = X->iCompare < 0 ? 0 : X->iCompare == 0 ? 1 : 2;
    if (n->jx[t] >= 0) RG_GO(n->jx[t]);
    *pcOut = t == 0 ? n->op->p1 : t == 1 ? n->op->p2 : n->op->p3;
    return 1;
  }
rg_move: if (!qv_move(X, R, Cs, n->op)) return 0; RG_NEXT;
rg_bitop: qv_bitop(X, R, Cs, n->op); RG_NEXT;
rg_perm: X->aPermute = (const u32 *)n->op->p4.ai + 1; RG_NEXT;
rg_gosub: qv_int(qv_out(X, n->op->p1), n->pc); RG_JUMP;   /* a subroutine (a group's output): qv_run's, back at the next Next */
rg_next: {   /* the loop's Next / Prev (qv_run's B-tree case), then the next row fetched and decoded */
    QvCur *C = n->C; const Op *op = n->op; int rc;
    G->iters++;
    if (C->kind != QVC_BT && C->kind != QVC_EPH) goto rg_exit;
    rc = op->opcode == OP_Next ? sqlite3BtreeNext(C->bc, op->p3) : sqlite3BtreePrevious(C->bc, op->p3);
    qv_stale(C);
    if (rc == SQLITE_OK) {
      C->nullRow = 0;
      if (C->bc->ix == 0 && !qv_tick_check(X)) return 0;   /* (a region walks a finite B-tree: checked per page it enters, not per row) */
      if (G->maxf >= 0 && C->kind == QVC_BT) {
        if (!qv_row(X, C)) return 0;
        int f = G->maxf < C->nField ? G->maxf : C->nField - 1;
        if (!C->nullRow && C->nHdr <= f && !qv_hdr(C, f)) return 0;
      }
      RG_GO(0);
    }
    if (rc != SQLITE_DONE) { qv_why = "next"; return 0; }
    C->nullRow = 1; *pcOut = n->pc + 1;
    return 1;
  }
#undef RG_GO
#undef RG_NEXT
#undef RG_JUMP
#undef RG_OUT
}
#else
static int qv_region(QvX *X, QvRegion *G, int *pcOut) { (void)X; (void)G; (void)pcOut; return 1; }   /* (regions need computed goto) */
#endif
/* the plan's regions, from its loops and its feedback so far */
static void qv_rg_build(QvPlan *P, Vdbe *v) {
  if (!qv_rgl) qv_region(0, 0, 0);
  if (!qv_rgl) return;
  Op *aOp = v->aOp; int nOp = P->nOp;
  int *at = sqlite3MallocZero(sizeof(int) * (u64)nOp); QvRegion *rg = sqlite3MallocZero(sizeof *rg * 64); int nrg = 0;
  if (!at || !rg) { sqlite3_free(at); sqlite3_free(rg); return; }
  for (int N = 1; N < nOp && nrg < 64; N++) {
    Op *o = &aOp[N]; int B = o->p2, ok = 1, cur = o->p1;
    if ((o->opcode != OP_Next && o->opcode != OP_Prev) || B <= 0 || B > N) continue;
    for (int pc = B; pc < N && ok; pc++) {
      Op *x = &aOp[pc];
      switch (x->opcode) {   /* inner loops, seeks into other tables, coroutines: not a single-cursor loop */
        case OP_Next: case OP_Prev: case OP_SorterNext: case OP_Rewind: case OP_Last: case OP_Sort: case OP_SorterSort:
        case OP_SeekGE: case OP_SeekGT: case OP_SeekLE: case OP_SeekLT: case OP_SeekRowid: case OP_NotExists:
        case OP_DeferredSeek: case OP_Yield: case OP_InitCoroutine: case OP_EndCoroutine: case OP_Return:
          ok = 0; break;
      }
      if ((sqlite3OpcodeProperty[x->opcode] & OPFLG_JUMP) && x->p2 >= B && x->p2 < pc) ok = 0;   /* a backward jump: another loop */
      if (x->opcode == OP_Jump && ((x->p1 >= B && x->p1 < pc) || (x->p3 >= B && x->p3 < pc))) ok = 0;
    }
    if (!ok) continue;
    QvNode *nd = sqlite3MallocZero(sizeof *nd * (u64)(N - B + 1)); if (!nd) break;
    QvRegion *G = &rg[nrg]; G->B = B; G->N = N; G->cur = cur; G->maxf = -1; G->n = nd;
    for (int pc = B; pc <= N; pc++) {
      Op *x = &aOp[pc]; QvNode *d = &nd[pc - B]; int k = RG_EXIT, out = -1;
      d->op = x; d->pc = pc; d->jn = (x->p2 >= B && x->p2 <= N) ? x->p2 - B : -1;
      if (x->p1 >= 0 && x->p1 < P->nCur) d->C = &P->c[x->p1];
      switch (x->opcode) {
        case OP_Noop: case OP_Explain: case OP_CursorHint: case OP_ColumnsUsed: case OP_Filter: case OP_FilterAdd: k = RG_NOP; break;
        case OP_Goto: k = RG_GOTO; break;
        case OP_Column:
          out = x->p3;
          k = (x->p1 == cur && P->fb[pc] == QV_FB_INT && !P->isCnt[out] && !P->isSum[out]) ? RG_COLI : RG_COL;
          if (x->p1 == cur && x->p2 > G->maxf) G->maxf = x->p2;
          break;
        case OP_Rowid: k = RG_ROWID; out = x->p2; break;
        case OP_IdxRowid: k = RG_IDXROWID; out = x->p2; break;
        case OP_Eq: case OP_Ne: case OP_Lt: case OP_Le: case OP_Gt: case OP_Ge:
          k = P->fb[pc] == QV_FB_INT ? RG_CMPI : RG_CMP;
          d->a = &P->r[x->p1]; d->b = &P->r[x->p3];
          d->lt = qv_LT[x->opcode]; d->eq = qv_EQ[x->opcode]; d->gt = qv_GT[x->opcode];
          break;
        case OP_If: k = RG_IF; d->a = &P->r[x->p1]; break;
        case OP_IfNot: k = RG_IFNOT; d->a = &P->r[x->p1]; break;
        case OP_IsNull: k = RG_ISNULL; d->a = &P->r[x->p1]; break;
        case OP_NotNull: k = RG_NOTNULL; d->a = &P->r[x->p1]; break;
        case OP_IfPos: k = RG_IFPOS; d->a = &P->r[x->p1]; break;
        case OP_IfNotZero: k = RG_IFNZ; d->a = &P->r[x->p1]; break;
        case OP_DecrJumpZero: k = RG_DJZ; d->a = &P->r[x->p1]; break;
        case OP_Integer: k = RG_INT; out = x->p2; break;
        case OP_Int64: k = RG_INT64; out = x->p2; break;
        case OP_String: k = RG_STR; out = x->p2; break;
        case OP_Null: case OP_BeginSubrtn: k = RG_NULL; break;
        case OP_SCopy: k = RG_SCOPY; break;
        case OP_Copy: k = RG_COPY; break;
        case OP_Add: case OP_Subtract: case OP_Multiply: case OP_Divide: case OP_Remainder:
          k = RG_ARITH; out = x->p3; d->a = &P->r[x->p1]; d->b = &P->r[x->p2];
          d->ar = x->opcode == OP_Add ? 1 : x->opcode == OP_Subtract ? 2 : x->opcode == OP_Multiply ? 3 : 0;
          break;
        case OP_Function: case OP_PureFunc: k = RG_FUNC; break;
        case OP_AggStep: case OP_AggStep1: case OP_AggInverse: k = RG_AGG; break;
        case OP_ResultRow: k = RG_RESULT; break;
        case OP_IdxLE: case OP_IdxGT: case OP_IdxLT: case OP_IdxGE: k = RG_IDXCMP; break;
        case OP_MakeRecord: k = RG_MKREC; break;
        case OP_SorterInsert: k = RG_SORTINS; break;
        case OP_Compare: k = RG_COMPARE; break;
        case OP_Jump:
          k = RG_JUMPCMP;
          for (int t = 0; t < 3; t++) { int to = t == 0 ? x->p1 : t == 1 ? x->p2 : x->p3; d->jx[t] = (to >= B && to <= N) ? to - B : -1; }
          break;
        case OP_Move: k = RG_MOVE; break;
        case OP_Permutation: k = RG_PERM; break;
        case OP_Gosub: k = RG_GOSUB; break;
        case OP_BitAnd: case OP_BitOr: case OP_ShiftLeft: case OP_ShiftRight: k = RG_BITOP; break;
      }
      if (pc == N) k = RG_NEXT;
      if (out >= 0) { d->o = &P->r[out]; d->plain = !P->isCnt[out] && !P->isSum[out]; }
      d->h = qv_rgl[k];
    }
    at[N] = ++nrg;
  }
  P->rg = rg; P->nrg = nrg; P->rgAt = at;
}
/* the feedback and regions of a qvm statement, for the corpus (QFB=1) */
static void qv_fb_dump(Vdbe *v, FILE *f) {
  QvPlan *P = v->pQc; if (!P || P->kind != 3) return;
  static const char *K[RG_N] = {"exit", "nop", "goto", "col", "col:int", "rowid", "idxrowid", "cmp", "cmp:int", "if", "ifnot", "isnull",
    "notnull", "int", "int64", "str", "null", "scopy", "copy", "arith", "func", "agg", "result", "ifpos", "ifnz", "djz", "idxcmp", "mkrec",
    "sortins", "compare", "jump", "move", "bitop", "perm", "gosub", "next"};
  fprintf(f, "    feedback (%u runs):", P->runs);
  for (int pc = 0; pc < P->nOp; pc++) {
    u8 m = P->fb[pc]; if (!m) continue;
    fprintf(f, " %d:%s=%s%s%s%s%s", pc, sqlite3OpcodeName(v->aOp[pc].opcode), m & QV_FB_NULL ? "n" : "", m & QV_FB_INT ? "i" : "",
            m & QV_FB_REAL ? "r" : "", m & QV_FB_TEXT ? "t" : "", m & QV_FB_BLOB ? "b" : "");
  }
  fprintf(f, "\n");
  for (int c = 0; c < P->nCur; c++) if (P->isHash[c]) fprintf(f, "    hash set: cursor %d, %d-field keys%s\n", c, P->isHash[c], P->hashOff ? " (deoptimised)" : "");
  for (int g = 0; g < P->nrg; g++) {
    QvRegion *G = &P->rg[g];
    fprintf(f, "    region [%d, %d] cursor %d%s: rows %llu, exits %llu, misses %llu:", G->B, G->N, G->cur, G->off ? " (off)" : "",
            (unsigned long long)G->iters, (unsigned long long)G->exits, (unsigned long long)G->misses);
    for (int i = 0; i <= G->N - G->B; i++) {
      int k = 0; while (k < RG_N && qv_rgl[k] != G->n[i].h) k++;
      fprintf(f, " %s", k < RG_N ? K[k] : "?");
      if (k == RG_EXIT) fprintf(f, "(%s)", sqlite3OpcodeName(G->n[i].op->opcode));
    }
    fprintf(f, "\n");
  }
}
static int qv_rg_on(void) { static int on = -1; if (on < 0) on = getenv("QV_NOREGION") == 0; return on; }

#define QV_RUN qv_run_fb
#define QV_FB 1
#include "qvm_run.h"
#undef QV_RUN
#undef QV_FB
#define QV_RUN qv_run
#define QV_FB 0
#include "qvm_run.h"
#undef QV_RUN
#undef QV_FB

static int qv_write_json(Vdbe *v, const QcVal *rows, int nrow, int ncol, QcOut *O, int vec) {
  QcTmpl *T = v->pQcTmpl;
  if (!T || T->ncol != ncol) return QC_FALLBACK;
  char *p = O->buf, *end = O->buf + O->cap;
  if ((size_t)(end - p) < T->lopen + T->lclose + 64) return QC_FALLBACK;
  p = qc_frag(p, T->open, T->lopen);
  for (int i = 0; i < nrow; i++) {
    if ((size_t)(end - p) < T->lsep + QC_FRAG + 64) return QC_FALLBACK;
    if (i) p = qc_frag(p, T->sep, T->lsep);
    for (int k = 0; k < ncol; k++) {
      const QcVal *x = &rows[(size_t)i * (size_t)ncol + k];
      if (T->kind[k] == 'i') { if (x->type != SQLITE_INTEGER || (size_t)(end - p) < 2 * QC_FRAG + 21 + 64) return QC_FALLBACK; p = qc_frag(p, T->frag[k], T->lfrag[k]); p = qc_jint(p, x->i); }
      else { if (x->type != SQLITE_TEXT || (size_t)(end - p) < 2 * QC_FRAG + 2 + 6 * (size_t)x->n + 64) return QC_FALLBACK; p = qc_frag(p, T->frag[k], T->lfrag[k]); p = qc_jstr(p, x->z, (u32)x->n, vec); }
    }
    if ((size_t)(end - p) < 2 * QC_FRAG + 64) return QC_FALLBACK;
    p = qc_frag(p, T->frag[ncol], T->lfrag[ncol]);
  }
  if ((size_t)(end - p) < QC_FRAG + 64) return QC_FALLBACK;
  p = qc_frag(p, T->close, T->lclose);
  O->n = (size_t)(p - O->buf); O->rows = nrow; return SQLITE_OK;
}

static void qv_free(QvPlan *P) {   /* the statement's program was deleted */
  for (int c = 0; c <= P->nCur; c++) { if (P->bopen[c]) sqlite3BtreeCloseCursor(P->bc[c]); sqlite3_free(P->bc[c]); }
  for (int c = 0; c <= P->nCur; c++) if (P->keep && P->keep[c].bt) { sqlite3BtreeCloseCursor(P->keep[c].bc); qv_bc_free(P->keep[c].bc); }   /* (the last cursor of a BTREE_SINGLE B-tree closes it) */
  if (P->r) for (int r = 0; r <= P->nMem; r++) sqlite3VdbeMemRelease(&P->r[r]);
  if (P->c) for (int c = 0; c <= P->nCur; c++) { sqlite3_free(P->c[c].aType); sqlite3_free(P->c[c].aOff); }
  if (P->octx) for (int pc = 0; pc < P->nOp; pc++) if (P->octx[pc]) { QvCtx *k = P->octx[pc]; sqlite3VdbeMemRelease(&k->res); sqlite3_free(k); }
  for (int g = 0; g < P->nrg; g++) sqlite3_free(P->rg[g].n);
  sqlite3_free(P->rg); sqlite3_free(P->rgAt);
  sqlite3_free(P->r); sqlite3_free(P->c); sqlite3_free(P->octx); sqlite3_free(P->once); sqlite3_free(P->isCnt); sqlite3_free(P->cnt);
  sqlite3_free(P->keep); sqlite3_free(P->isVec); sqlite3_free(P->isHash); sqlite3_free(P->isSum); sqlite3_free(P->sacc); sqlite3_free(P->fb);
  for (int k = 0; k < qv_nplans; k++) if (qv_plans[k] == P) { qv_plans[k] = qv_plans[--qv_nplans]; break; }
  sqlite3_free(P);
}

static QvX qv_x;   /* one connection, one thread (as the rest of qc) */
static void qv_release(void) {   /* qvm's memory kept between executions (sqlite3_qc_release) */
  QvX *X = &qv_x;
  for (QvBlk *b = X->A.head, *n; b; b = n) { n = b->next; sqlite3_free(b); }
  sqlite3_free(X->pins); sqlite3_free(X->out); memset(X, 0, sizeof *X);
  while (qv_nbc) sqlite3_free(qv_bcpool[--qv_nbc]);
}
static int qv_exec(Vdbe *v, QvPlan *P, qc_row_cb cb, void *ctx) {
  sqlite3 *db = v->db;
  if (v->eVdbeState != VDBE_READY_STATE) return QC_FB("v not ready");
  if (db->autoCommit) return QC_FB("v autocommit");
  if (P->iDb >= db->nDb || v->expired) return QC_FB("v expired");
  Btree *bt = P->iDb >= 0 ? db->aDb[P->iDb].pBt : 0; if (P->iDb >= 0 && !bt) return QC_FB("v btree");
  if (bt && sqlite3BtreeTxnState(bt) == SQLITE_TXN_NONE) { int m; P->txnChecked = 0; if (sqlite3BtreeBeginTrans(bt, 0, &m) != SQLITE_OK) return QC_FB("v txn"); }
  if (bt && (!P->txnChecked || P->bt != bt)) {
    for (int c = 0; c < P->nCur; c++) if (P->bopen[c] && P->bt != bt) { sqlite3BtreeCloseCursor(P->bc[c]); P->bopen[c] = 0; }
    int iMeta; sqlite3BtreeGetMeta(bt, BTREE_SCHEMA_VERSION, (u32 *)&iMeta);
    if (iMeta != P->cookie || db->aDb[P->iDb].pSchema->iGeneration != P->gen) return QC_FB("v schema");
    P->txnChecked = 1; P->bt = bt;
  }
  QvX *X = &qv_x; QvArena A = X->A; DbPage **pins = X->pins; int cpin = X->cpin; QcVal *out = X->out; size_t cout = X->cout;
  memset(X, 0, sizeof *X);
  X->A = A; X->pins = pins; X->cpin = cpin; X->out = out; X->cout = cout;
  X->P = P; X->v = v; X->db = db; X->O = cb ? 0 : ctx; qv_why = "";
  X->r = P->r; X->c = P->c; X->once = P->once; X->octx = P->octx;
  if (++P->runs == 3 && !P->rgAt && qv_rg_on()) qv_rg_build(P, v);   /* two runs of feedback first */
  X->tick = QV_TICK; X->usable = bt ? bt->pBt->usableSize : 0;
  X->fb = P->runs <= 2 ? P->fb : 0; X->rgAt = P->rgAt;   /* (feedback only until the regions are built) */
  int st = QC_FALLBACK;
  memset(X->once, 0, (size_t)(P->nOp / 8 + 1));
  memset(P->cnt, 0, sizeof(i64) * (size_t)(P->nMem + 1));
  memset(P->sacc, 0, sizeof *P->sacc * (size_t)(P->nMem + 1));
  if (!(X->fb ? qv_run_fb(X) : qv_run(X))) { qc_why = *qv_why ? qv_why : "v run"; goto out; }
  if (cb) st = cb(ctx, X->nrow, P->nout, X->out);
  else st = qv_write_json(v, X->out, X->nrow, P->nout, ctx, bt && bt->pBt->pPager->xGet == getPageNormal);
out:
  /* registers: aggregate contexts finalized and freed, dynamic values released, buffers (zMalloc) kept */
  for (int r = 0; r <= P->nMem; r++) { Mem *m = &P->r[r]; if (VdbeMemDynamic(m)) sqlite3VdbeMemSetNull(m); m->flags = MEM_Null; }
  for (int c = 0; c < P->nCur; c++)   /* duplicates first: then an owner's cursor is its B-tree's only one */
    if (X->c[c].kind == QVC_EPH && !X->c[c].owner) qv_cur_close(&X->c[c]);
  for (int c = 0; c < P->nCur; c++) {
    QvCur *C = &X->c[c];
    if (C->kind == QVC_EPH && st == SQLITE_OK && !P->keep[c].bt) {   /* kept for the next run (a failed run closes everything) */
      P->keep[c].bt = C->ebt; P->keep[c].bc = C->bc; P->keep[c].root = C->eroot; P->keep[c].ki = C->ki; P->keep[c].p5 = C->ep5;
      qv_cur_reset(C);
    } else if (C->kind && C->kind != QVC_BT) qv_cur_close(C);
    else qv_cur_reset(C);
  }
  for (int i = 0; i < X->npin; i++) sqlite3PagerUnref(X->pins[i]);
  X->npin = 0;
  qv_arena_reset(&X->A);
  if (v->pAuxData) sqlite3VdbeDeleteAuxData(db, &v->pAuxData, -1, 0);   /* functions' auxdata (sqlite3_set_auxdata), freed as vdbe.c's Cleanup frees it */
  return st;
}
