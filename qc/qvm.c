/* qvm.c: qc's general executor. #included by qc.c after the general plans (qcg.c).
**
** The plans in qc.c and qcg.c lift known shapes into rewritten programs. Everything else read-only (coroutines,
** compound SELECTs, CTEs, window functions, DISTINCT, sorter GROUP BY, subqueries of any kind) runs here: the
** statement's own VDBE program, opcode by opcode, as vdbe.c runs it, with three differences that make it cheaper:
**   values     registers are QcVals: an integer, a double, or a pointer + length. Text and blobs read from the
**              database stay in its pages (pinned until the execution ends) instead of being copied into each
**              register, and Copy / SCopy / Move are plain struct copies;
**   rows       ResultRow appends to a row buffer that is handed out once, when the program halts: no
**              sqlite3_step() round trip and no sqlite3_column_*() call per value;
**   cursors    database cursors stay open for the whole read transaction.
** Everything that is semantics is SQLite's own: comparisons, affinities and arithmetic beyond the integer and text
** fast paths go through Mem copies into vdbe.c's helpers (sqlite3MemCompare, applyAffinity, numericType, ...);
** ephemeral tables are SQLite's own in-memory B-trees with SQLite records; functions and aggregates (window ones
** included) are called through their FuncDefs. The sorter is a stable merge sort under the KeyInfo, which is what
** SQLite's in-memory sorter does.
** The program is checked opcode by opcode when the statement is lifted; at run time anything not reproduced exactly
** (an error, a write to a real table, a zeroblob, an oversized result) returns QC_FALLBACK before any row is handed
** out, so the caller steps the statement instead. Ephemeral state is private to the execution: nothing to undo. */

#define QV_CLEARED  0x100       /* QcVal.type flags above the SQLite type: MEM_Cleared NULL */
#define QV_INTREAL  0x200       /*   a REAL held as an integer (MEM_IntReal) */
#define QV_SUBTYPE  0x400       /*   a subtype in bits 16..23 */
#define QVT(x) ((x)->type & 0xff)
#define QV_ARENA_MAX (256u << 20)
#define QV_MAXPINS 65536
#define QV_MAXARGS 32

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
enum { QVC_NONE, QVC_BT, QVC_EPH, QVC_SORT, QVC_PSEUDO, QVC_NULLONLY };
typedef struct QvSort { const u8 **rec; u32 *len; QcVal *key; int n, cap, pos, nk; KeyInfo *ki; } QvSort;   /* key: nk decoded fields per record */
typedef struct QvCur {
  u8 kind, isTable, nullRow, deferred, eqOnly, rowOk, copyVals, noReuse;
  BtCursor *bc; KeyInfo *ki; int nField;
  Btree *ebt; Pgno eroot;                 /* ephemeral: its B-tree (BTREE_SINGLE: closed with its last cursor) */
  i64 movetoTarget; struct QvCur *alt; const int *altMap;
  int pseudoReg, seekResult, seekHit; i64 seqCount;
  QvSort *srt;
  /* the current row: its record, how far its header is parsed */
  const u8 *row; u32 szRow, payload, hdrOff; int nHdr; u32 *aType, *aOff; DbPage *pinned;
} QvCur;
typedef struct QvPlan {
  int kind;                                /* 3 */
  int iDb, cookie, gen, nout;
  int nMem, nCur, nOp; u8 *isAcc;
  Btree *bt; u8 txnChecked;
  BtCursor **bc; Pgno *bcRoot; u8 *bopen; /* database cursors by cursor number, open for the transaction */
} QvPlan;
typedef struct QvX {
  QvPlan *P; Vdbe *v; sqlite3 *db; const QcOut *O;
  QcVal *r; Mem *acc; QvCur *c; u8 *once;
  QvArena A;
  DbPage **pins; int npin, cpin;
  QcVal *out; int nrow, crow;
  int iCompare; const u32 *aPermute;
  void **octx;                            /* per opcode: its function context, built on first use */
} QvX;
static QvPlan *qv_plans[64]; static int qv_nplans;
static void qv_txn_end(Btree *bt) {
  for (int k = 0; k < qv_nplans; k++) {
    QvPlan *P = qv_plans[k]; if (P->bt != bt) continue;
    P->txnChecked = 0;
    for (int c = 0; c < P->nCur; c++) if (P->bopen[c]) { sqlite3BtreeCloseCursor(P->bc[c]); P->bopen[c] = 0; }
  }
}

/* ---------------------------------------------------------------- values */
static void qv_mem(Mem *m, const QcVal *x, sqlite3 *db) {   /* a shallow Mem of x (released with sqlite3VdbeMemRelease) */
  memset(m, 0, sizeof *m); m->db = db; m->enc = SQLITE_UTF8;
  switch (QVT(x)) {
    case SQLITE_INTEGER: m->flags = MEM_Int; m->u.i = x->i; break;
    case SQLITE_FLOAT: if (x->type & QV_INTREAL) { m->flags = MEM_IntReal; m->u.i = (i64)x->r; } else { m->flags = MEM_Real; m->u.r = x->r; } break;
    case SQLITE_TEXT: m->flags = MEM_Str | MEM_Ephem; m->z = (char *)x->z; m->n = x->n; break;
    case SQLITE_BLOB: m->flags = MEM_Blob | MEM_Ephem; m->z = (char *)x->z; m->n = x->n; break;
    default: m->flags = (x->type & QV_CLEARED) ? (MEM_Null | MEM_Cleared) : MEM_Null;
  }
  if (x->type & QV_SUBTYPE) { m->flags |= MEM_Subtype; m->eSubtype = (u8)(x->type >> 16); }
}
static int qv_from_mem(QvX *X, const Mem *m, QcVal *o) {   /* m's value into o, text and blobs copied to the arena */
  u16 f = m->flags; int sub = (f & MEM_Subtype) ? (QV_SUBTYPE | ((int)m->eSubtype << 16)) : 0;
  if (f & MEM_Null) { o->type = SQLITE_NULL | ((f & MEM_Cleared) ? QV_CLEARED : 0) | sub; o->n = 0; o->i = 0; return 1; }
  if (f & MEM_Int) { o->type = SQLITE_INTEGER | sub; o->i = m->u.i; return 1; }
  if (f & MEM_IntReal) { o->type = SQLITE_FLOAT | QV_INTREAL | sub; o->r = (double)m->u.i; return 1; }
  if (f & MEM_Real) { o->type = SQLITE_FLOAT | sub; o->r = m->u.r; return 1; }
  if (f & (MEM_Str | MEM_Blob)) {
    if (f & MEM_Zero) { qv_why = "zeroblob"; return 0; }
    if ((f & MEM_Str) && m->enc != SQLITE_UTF8) { qv_why = "encoding"; return 0; }
    char *d = qv_alloc(&X->A, (size_t)m->n + 1); if (!d) { qv_why = "arena"; return 0; }
    if (m->n) memcpy(d, m->z, (size_t)m->n);
    d[m->n] = 0;
    o->type = ((f & MEM_Str) ? SQLITE_TEXT : SQLITE_BLOB) | sub; o->z = (const u8 *)d; o->n = m->n; return 1;
  }
  qv_why = "value"; return 0;
}
static inline int qv_null(const QcVal *x) { return QVT(x) == SQLITE_NULL; }
static int qv_text_of(QvX *X, const QcVal *x, QcVal *o) {   /* a number as text (sqlite3VdbeMemStringify), in the arena */
  Mem m; qv_mem(&m, x, X->db); int ok = 0;
  if (!sqlite3VdbeMemStringify(&m, SQLITE_UTF8, 0)) {
    char *d = qv_alloc(&X->A, (size_t)m.n + 1);
    if (d) { memcpy(d, m.z, (size_t)m.n); d[m.n] = 0; o->type = SQLITE_TEXT; o->z = (const u8 *)d; o->n = m.n; ok = 1; } else qv_why = "arena";
  }
  sqlite3VdbeMemRelease(&m); return ok;
}
static inline void qv_setint(QcVal *x, i64 v) { x->type = SQLITE_INTEGER; x->i = v; }
static inline void qv_setnull(QcVal *x) { x->type = SQLITE_NULL; x->n = 0; x->i = 0; }
/* sqlite3VdbeBooleanValue */
static int qv_bool(QvX *X, const QcVal *x, int ifNull) {
  if (QVT(x) == SQLITE_INTEGER) return x->i != 0;
  if (qv_null(x)) return ifNull;
  Mem m; qv_mem(&m, x, X->db); int b = sqlite3VdbeBooleanValue(&m, ifNull); sqlite3VdbeMemRelease(&m); return b;
}
static i64 qv_int(QvX *X, const QcVal *x) {   /* sqlite3VdbeIntValue */
  if (QVT(x) == SQLITE_INTEGER) return x->i;
  Mem m; qv_mem(&m, x, X->db); i64 v = sqlite3VdbeIntValue(&m); sqlite3VdbeMemRelease(&m); return v;
}
/* applyAffinity (+ OP_Affinity's REAL step when real), in place; 0 = fallback */
static int qv_affinity(QvX *X, QcVal *x, char aff, int realStep) {
  int t = QVT(x);
  if (t == SQLITE_NULL || aff < SQLITE_AFF_TEXT) return 1;
  if (aff >= SQLITE_AFF_NUMERIC && t == SQLITE_INTEGER) {
    if (realStep && aff == SQLITE_AFF_REAL) { x->type = SQLITE_FLOAT | (x->type & ~0xff & ~QV_INTREAL); x->r = (double)x->i; }
    return 1;
  }
  if (aff == SQLITE_AFF_TEXT && (t == SQLITE_TEXT || t == SQLITE_BLOB)) return 1;
  if (aff >= SQLITE_AFF_NUMERIC && t == SQLITE_BLOB) return 1;
  Mem m; qv_mem(&m, x, X->db);
  applyAffinity(&m, aff, SQLITE_UTF8);
  if (realStep && aff == SQLITE_AFF_REAL && (m.flags & MEM_Int)) { m.u.r = (double)m.u.i; m.flags = (m.flags | MEM_Real) & ~(MEM_Int | MEM_Str); }
  int ok = qv_from_mem(X, &m, x); sqlite3VdbeMemRelease(&m); return ok;
}
/* sqlite3MemCompare of two values under a collation */
static int qv_cmp(QvX *X, const QcVal *a, const QcVal *b, const CollSeq *coll) {
  int ta = QVT(a), tb = QVT(b);
  if (ta == SQLITE_INTEGER && tb == SQLITE_INTEGER) return a->i < b->i ? -1 : a->i > b->i;
  if (ta == SQLITE_TEXT && tb == SQLITE_TEXT && (!coll || coll->xCmp == sqlite3BinaryCompare)) {
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
/* the value of serial type t at d (len bytes) */
static int qv_serial(QvX *X, u32 t, const u8 *d, QcVal *o, int copy) {   /* X: only when copy */
  switch (t) {
    case 0: qv_setnull(o); return 1;
    case 1: case 2: case 3: case 4: case 5: case 6: qv_setint(o, qc_int(t, d)); return 1;
    case 7: { double r = qv_real(d); if (r != r) { qv_setnull(o); return 1; } o->type = SQLITE_FLOAT; o->r = r; return 1; }   /* NaN reads as NULL */
    case 8: case 9: qv_setint(o, (i64)t - 8); return 1;
    case 10: case 11: qv_why = "serial type"; return 0;
  }
  u32 n = (t - 12) >> 1;
  o->type = (t & 1) ? SQLITE_TEXT : SQLITE_BLOB; o->n = (int)n;
  if (copy) { char *p = qv_alloc(&X->A, n + 1); if (!p) { qv_why = "arena"; return 0; } memcpy(p, d, n); p[n] = 0; o->z = (const u8 *)p; }
  else o->z = d;
  return 1;
}
/* MakeRecord's serial types (minWriteFileFormat >= 4: 0 and 1 as types 8 and 9) */
static u32 qv_stype(const QcVal *x, int ff4, u32 *len) {
  switch (QVT(x)) {
    case SQLITE_NULL: *len = 0; return 0;
    case SQLITE_FLOAT:
      if (!(x->type & QV_INTREAL)) { *len = 8; return 7; }
      { i64 i = (i64)x->r; u64 uu = i < 0 ? ~(u64)i : (u64)i;
        if (uu > 140737488355327LL) { *len = 8; return 7; }   /* an 8-byte IntReal is stored as a double */
        QcVal t = {.i = i, .type = SQLITE_INTEGER}; return qv_stype(&t, ff4, len); }
    case SQLITE_INTEGER: {
      i64 i = x->i; u64 uu = i < 0 ? ~(u64)i : (u64)i;
      if (uu <= 127) { if ((i & 1) == i && ff4) { *len = 0; return 8 + (u32)uu; } *len = 1; return 1; }
      if (uu <= 32767) { *len = 2; return 2; }
      if (uu <= 8388607) { *len = 3; return 3; }
      if (uu <= 2147483647) { *len = 4; return 4; }
      if (uu <= 140737488355327LL) { *len = 6; return 5; }
      *len = 8; return 6;
    }
    case SQLITE_TEXT: *len = (u32)x->n; return (u32)x->n * 2 + 13;
    default: *len = (u32)x->n; return (u32)x->n * 2 + 12;
  }
}
static int qv_make_record(QvX *X, const QcVal *f, int n, QcVal *out) {
  int ff4 = X->v->minWriteFileFormat >= 4; u32 nHdr = 0, nData = 0, st[256], ln[256];
  if (n > 256) { qv_why = "record width"; return 0; }
  for (int k = 0; k < n; k++) { st[k] = qv_stype(&f[k], ff4, &ln[k]); nHdr += (u32)sqlite3VarintLen(st[k]); nData += ln[k]; }
  if (nHdr <= 126) nHdr += 1;   /* the header-size varint counts itself (as MakeRecord does) */
  else { int nv = sqlite3VarintLen(nHdr); nHdr += (u32)nv; if (nv < sqlite3VarintLen(nHdr)) nHdr++; }
  u8 *p = qv_alloc(&X->A, nHdr + nData + 1); if (!p) { qv_why = "arena"; return 0; }
  u8 *h = p + putVarint32(p, nHdr), *d = p + nHdr;
  for (int k = 0; k < n; k++) {
    h += putVarint32(h, st[k]);
    const QcVal *x = &f[k];
    switch (st[k]) {
      case 0: case 8: case 9: break;
      case 7: { u64 u; double r = x->r; memcpy(&u, &r, 8); for (int b = 7; b >= 0; b--) { d[b] = (u8)u; u >>= 8; } d += 8; break; }
      case 1: case 2: case 3: case 4: case 5: case 6: {
        u64 u = (u64)(QVT(x) == SQLITE_INTEGER ? x->i : (i64)x->r); u32 len = ln[k];
        for (int b = (int)len - 1; b >= 0; b--) { d[b] = (u8)u; u >>= 8; }
        d += len; break;
      }
      default: if (ln[k]) memcpy(d, x->z, ln[k]); d += ln[k];
    }
  }
  out->type = SQLITE_BLOB; out->z = p; out->n = (int)(nHdr + nData); return 1;
}

/* ---------------------------------------------------------------- cursors */
static int qv_cur_alloc(QvX *X, QvCur *C, int nField) {
  C->nField = nField;
  C->aType = qv_alloc(&X->A, sizeof(u32) * (size_t)(nField + 1));
  C->aOff = qv_alloc(&X->A, sizeof(u32) * (size_t)(nField + 2));
  if (!C->aType || !C->aOff) { qv_why = "arena"; return 0; }
  return 1;
}
static void qv_cur_close(QvCur *C) {
  if (C->kind == QVC_EPH && C->bc) { sqlite3BtreeCloseCursor(C->bc); sqlite3_free(C->bc); }
  memset(C, 0, sizeof *C);
}
/* the cursor's position is final and its row's record is at C->row (header not yet parsed): 0 = fallback,
   with C->nullRow set when the row turned out to be gone */
static int qv_row(QvX *X, QvCur *C) {
  if (C->kind == QVC_PSEUDO) {   /* the register's record, whenever it changes */
    QcVal *r = &X->r[C->pseudoReg];
    if (QVT(r) != SQLITE_BLOB) { qv_why = "pseudo"; return 0; }
    if (C->rowOk && C->row == r->z && C->szRow == (u32)r->n) return 1;
    C->row = r->z; C->payload = C->szRow = (u32)r->n;
  } else if (C->rowOk) return 1;
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
    if (amt < C->payload) {   /* an overflow record: the whole payload, copied */
      u8 *buf = qv_alloc(&X->A, C->payload + 1); if (!buf) { qv_why = "arena"; return 0; }
      if (sqlite3BtreePayload(bc, 0, C->payload, buf) != SQLITE_OK) { qv_why = "payload"; return 0; }
      C->row = buf; C->szRow = C->payload;
    } else if (C->kind == QVC_BT && C->pinned != bc->pPage->pDbPage) {
      if (!qv_pin(X, bc->pPage->pDbPage)) return 0;
      C->pinned = bc->pPage->pDbPage;
    }
  }
  const u8 *z = C->row;
  if (C->szRow < 1) { qv_why = "empty record"; return 0; }
  u32 hdr; C->hdrOff = z[0] < 0x80 ? (hdr = z[0], 1) : sqlite3GetVarint32(z, &hdr);
  if (hdr > C->szRow || hdr > 98307) { qv_why = "corrupt record"; return 0; }
  C->aOff[0] = hdr; C->nHdr = 0; C->rowOk = 1;
  return 1;
}
/* column p2 of the cursor's current row into o; 0 = fallback */
static int qv_column(QvX *X, QvCur *C, int p2, const Op *op, QcVal *o) {
  for (;;) {
    if (C->nullRow && !(C->kind == QVC_PSEUDO)) { qv_setnull(o); return 1; }
    if (C->deferred && C->altMap && C->altMap[1 + p2] > 0) { p2 = C->altMap[1 + p2] - 1; C = C->alt; continue; }
    break;
  }
  if (!qv_row(X, C)) return 0;
  if (C->nullRow && C->kind != QVC_PSEUDO) { qv_setnull(o); return 1; }
  if (p2 >= C->nField) { qv_why = "column index"; return 0; }
  if (C->nHdr <= p2) {
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
    if (C->nHdr <= p2) {   /* fewer fields than the table now has: the column's default (ALTER TABLE ADD COLUMN) */
      if (op->p4type == P4_MEM) { Mem *m = op->p4.pMem; Mem t = *m; t.flags = (u16)((t.flags & ~(MEM_Dyn | MEM_Ephem)) | MEM_Static); return qv_from_mem(X, &t, o); }
      qv_setnull(o); return 1;
    }
  }
  u32 t = C->aType[p2];
  return qv_serial(X, t, C->row + C->aOff[p2], o, C->copyVals);
}
static inline void qv_stale(QvCur *C) { C->rowOk = 0; }
static void qv_stale_eph(QvX *X) {   /* a write moved cells: no ephemeral cursor's cached row is valid (vdbe.c: colCacheCtr++) */
  for (int c = 0; c < X->P->nCur; c++) if (X->c[c].kind == QVC_EPH) X->c[c].rowOk = 0;
}

/* ---------------------------------------------------------------- sorter: stable, as vdbeSorterSort */
/* the first nk fields of a record (values point into it) */
static int qv_decode(const u8 *z, u32 n, int nk, QcVal *o) {
  u32 hdr, off, t; const u8 *h = z, *he;
  h += z[0] < 0x80 ? (hdr = z[0], 1) : sqlite3GetVarint32(z, &hdr);
  if (hdr > n) return 0;
  he = z + hdr; off = hdr;
  for (int k = 0; k < nk; k++) {
    if (h >= he) { for (; k < nk; k++) qv_setnull(&o[k]); return 1; }
    if ((t = *h) < 0x80) h++; else h += sqlite3GetVarint32(h, &t);
    u32 len = sqlite3VdbeSerialTypeLen(t);
    if (off + len > n || !qv_serial(0, t, z + off, &o[k], 0)) return 0;
    off += len;
  }
  return 1;
}
/* vdbeRecordCompare on decoded keys: per field the value order (sqlite3MemCompare) under its collation, DESC and
   BIGNULL as the KeyInfo says; equal keys compare equal (the sort keeps them in insertion order) */
static int qv_keycmp(QvX *X, const KeyInfo *ki, const QcVal *a, const QcVal *b, int nk) {
  for (int i = 0; i < nk; i++) {
    int c = qv_cmp(X, &a[i], &b[i], ki->aColl[i]);
    if (!c) continue;
    int f = ki->aSortFlags[i];
    if (f && (!(f & KEYINFO_ORDER_BIGNULL) || ((f & KEYINFO_ORDER_DESC) != 0) != (qv_null(&a[i]) || qv_null(&b[i])))) c = -c;
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
  S->rec = nr; S->len = nl;   /* the keys are not needed after the sort */
  return 1;
}

/* ---------------------------------------------------------------- functions and aggregates */
static int qv_policy(const FuncDef *f) {   /* built-ins (not unsafe or direct-only), or deterministic user functions */
  if (f->funcFlags & (SQLITE_FUNC_UNSAFE | SQLITE_FUNC_DIRECT | SQLITE_FUNC_INTERNAL)) return 0;
  return (f->funcFlags & SQLITE_FUNC_BUILTIN) || (f->funcFlags & SQLITE_FUNC_CONSTANT);
}
/* a function's context and argument Mems, built once per opcode (as vdbe.c keeps one in P4) */
typedef struct QvCtx { Mem argv[QV_MAXARGS]; Mem res; union { sqlite3_context c; char b[sizeof(sqlite3_context) + QV_MAXARGS * sizeof(sqlite3_value *)]; } u; } QvCtx;
static QvCtx *qv_ctx(QvX *X, int iOp, FuncDef *f, int argc) {
  QvCtx *k = X->octx[iOp];
  if (!k) {
    if (!(k = qv_alloc(&X->A, sizeof *k))) { qv_why = "arena"; return 0; }
    memset(&k->u.c, 0, sizeof k->u.c); memset(k->argv, 0, sizeof(Mem) * (size_t)argc); sqlite3VdbeMemInit(&k->res, X->db, MEM_Null);
    k->u.c.pFunc = f; k->u.c.pVdbe = X->v; k->u.c.iOp = iOp; k->u.c.enc = SQLITE_UTF8; k->u.c.argc = (u16)argc;
    for (int i = 0; i < argc; i++) k->u.c.argv[i] = &k->argv[i];
    X->octx[iOp] = k;
  }
  k->res.flags = MEM_Null;
  k->u.c.pOut = &k->res; k->u.c.isError = 0; k->u.c.skipFlag = 0;
  return k;
}
/* x into m, keeping m's buffer (zMalloc) for conversions the function makes, as a vdbe.c register would */
static void qv_mem_keep(Mem *m, const QcVal *x) {
  if (m->flags & (MEM_Dyn | MEM_Agg)) sqlite3VdbeMemRelease(m);
  char *zm = m->zMalloc; int sz = m->szMalloc; sqlite3 *db = m->db;
  qv_mem(m, x, db); m->zMalloc = zm; m->szMalloc = sz;
}
static void qv_args(QvX *X, QvCtx *k, const QcVal *args, int argc) {
  for (int i = 0; i < argc; i++) { if (!k->argv[i].db) k->argv[i].db = X->db; qv_mem_keep(&k->argv[i], &args[i]); }
}
static void qv_args_free(QvCtx *k, int argc) {   /* only what the call made dynamic; buffers stay for the next call */
  for (int i = 0; i < argc; i++) if (k->argv[i].flags & (MEM_Agg | MEM_Dyn)) sqlite3VdbeMemRelease(&k->argv[i]);
  if (k->res.flags & (MEM_Agg | MEM_Dyn)) sqlite3VdbeMemRelease(&k->res);
}
static void qv_ctx_free(QvCtx *k) {   /* at the end of the execution */
  for (int i = 0; i < k->u.c.argc; i++) if (k->argv[i].db) sqlite3VdbeMemRelease(&k->argv[i]);
  sqlite3VdbeMemRelease(&k->res);
}
/* length() natively for text and blobs (lengthFunc: characters up to the first NUL, a lead byte >= 0xc0 swallows
   the continuation bytes after it) */
static int qv_length(const QcVal *x, QcVal *o) {
  if (QVT(x) == SQLITE_BLOB) { qv_setint(o, x->n); return 1; }
  if (QVT(x) == SQLITE_NULL) { qv_setnull(o); return 1; }
  if (QVT(x) != SQLITE_TEXT) return 0;
  const u8 *z = x->z, *e = z + x->n; i64 len = 0;
  while (z < e && *z) { len++; if (*z++ >= 0xc0) while (z < e && (*z & 0xc0) == 0x80) z++; }
  qv_setint(o, len); return 1;
}
static int qv_function(QvX *X, const Op *op, int pc) {
  sqlite3_context *pc4 = op->p4.pCtx; FuncDef *f = pc4->pFunc; int argc = pc4->argc;
  QcVal *args = &X->r[op->p2], *out = &X->r[op->p3];
  if (f->xSFunc == lengthFunc && argc == 1 && qv_length(args, out)) return 1;
  QvCtx *k = qv_ctx(X, pc, f, argc); if (!k) return 0;
  k->u.c.pMem = 0; qv_args(X, k, args, argc);
  f->xSFunc(&k->u.c, argc, k->u.c.argv);
  int ok = !k->u.c.isError && !X->db->mallocFailed && qv_from_mem(X, &k->res, out);
  if (k->u.c.isError) qv_why = "function error";
  qv_args_free(k, argc);
  return ok;
}
static Mem *qv_acc(QvX *X, int r) {
  Mem *m = &X->acc[r];
  if (!m->db) sqlite3VdbeMemInit(m, X->db, MEM_Null);
  return m;
}
static int qv_aggstep(QvX *X, const Op *op, int pc, int inverse) {
  FuncDef *f = op->p4type == P4_FUNCDEF ? op->p4.pFunc : op->p4.pCtx->pFunc; int argc = op->p5;
  Mem *acc = qv_acc(X, op->p3);
  QvCtx *k = qv_ctx(X, pc, f, argc); if (!k) return 0;
  k->u.c.pMem = acc; qv_args(X, k, &X->r[op->p2], argc);
  acc->n++;
  if (inverse) f->xInverse(&k->u.c, argc, k->u.c.argv); else f->xSFunc(&k->u.c, argc, k->u.c.argv);
  int ok = !k->u.c.isError && !X->db->mallocFailed;
  if (!ok) qv_why = "aggregate error";
  if (ok && k->u.c.skipFlag && pc > 0 && X->v->aOp[pc - 1].opcode == OP_CollSeq && X->v->aOp[pc - 1].p1) qv_setint(&X->r[X->v->aOp[pc - 1].p1], 1);
  qv_args_free(k, argc);
  return ok;
}
static int qv_aggfinal(QvX *X, const Op *op) {   /* AggFinal, or AggValue (P3) */
  FuncDef *f = op->p4.pFunc; Mem *acc = qv_acc(X, op->p1); int ok;
  if (op->p3) {
    Mem res; sqlite3VdbeMemInit(&res, X->db, MEM_Null);
    ok = sqlite3VdbeMemAggValue(acc, &res, f) == SQLITE_OK && qv_from_mem(X, &res, &X->r[op->p3]);
    sqlite3VdbeMemRelease(&res);
  } else {
    ok = sqlite3VdbeMemFinalize(acc, f) == SQLITE_OK && qv_from_mem(X, acc, &X->r[op->p1]);
    sqlite3VdbeMemSetNull(acc);
  }
  if (!ok && !*qv_why) qv_why = "aggregate final";
  return ok;
}
static void qv_clobber(QvX *X, int r) {   /* writing an accumulator register drops its aggregate context */
  if (X->P->isAcc[r] && X->acc[r].db) sqlite3VdbeMemSetNull(&X->acc[r]);
}
#define OUTR(k) (X->P->isAcc[k] ? qv_clobber(X, k) : (void)0, &R[k])

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
    case OP_SeekScan: case OP_IfEmpty: case OP_Transaction: case OP_TableLock:
      return 1;
    case OP_String: return o->p3 == 0;
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
      case OP_OpenRead: case OP_ReopenIdx:
        if (o->p3 != iDb && iDb >= 0) { qc_why = "qvm database"; return 0; }
        break;
      case OP_TableLock: if (o->p3) { qc_why = "write lock"; return 0; } break;
      case OP_ResultRow:
        if (nout >= 0 && nout != o->p2) { qc_why = "result widths"; return 0; }
        nout = o->p2; break;
      case OP_NewRowid: if (o->p3) { qc_why = "autoincrement"; return 0; } break;
    }
  }
  if (nout < 0 || nout > QC_MAXOUT * 4) { qc_why = "qvm program"; return 0; }   /* no Transaction: a program that reads no table */
  for (int pc = 0; pc < nOp; pc++) if ((aOp[pc].opcode == OP_OpenRead || aOp[pc].opcode == OP_ReopenIdx) && aOp[pc].p3 != iDb) { qc_why = "qvm database"; return 0; }
  QvPlan *P = sqlite3MallocZero(sizeof *P + (size_t)(v->nMem + 1) + (sizeof(BtCursor *) + sizeof(Pgno) + 1) * (size_t)(v->nCursor + 1));
  if (!P) return 0;
  P->kind = 3; P->iDb = iDb; P->cookie = cookie; P->gen = gen; P->nout = nout; P->nMem = v->nMem; P->nCur = v->nCursor; P->nOp = nOp;
  P->bc = (BtCursor **)(P + 1); P->bcRoot = (Pgno *)(P->bc + v->nCursor + 1); P->bopen = (u8 *)(P->bcRoot + v->nCursor + 1);
  P->isAcc = P->bopen + v->nCursor + 1;
  for (int pc = 0; pc < nOp; pc++) {
    Op *o = &aOp[pc];
    if (o->opcode == OP_AggStep || o->opcode == OP_AggInverse || o->opcode == OP_AggStep1) P->isAcc[o->p3] = 1;
    if (o->opcode == OP_AggFinal || o->opcode == OP_AggValue) P->isAcc[o->p1] = 1;
  }
  if (qv_nplans >= 64) { sqlite3_free(P); qc_why = "plans"; return 0; }
  v->pQc = P; v->qcWant = 1; qv_plans[qv_nplans++] = P;
  return 1;
}

/* ---------------------------------------------------------------- the interpreter */
static const u8 qv_LT[] = {[OP_Ne] = 1, [OP_Eq] = 0, [OP_Gt] = 0, [OP_Le] = 1, [OP_Lt] = 1, [OP_Ge] = 0};
static const u8 qv_EQ[] = {[OP_Ne] = 0, [OP_Eq] = 1, [OP_Gt] = 0, [OP_Le] = 1, [OP_Lt] = 0, [OP_Ge] = 1};
static const u8 qv_GT[] = {[OP_Ne] = 1, [OP_Eq] = 0, [OP_Gt] = 1, [OP_Le] = 0, [OP_Lt] = 0, [OP_Ge] = 1};
/* OP_Eq..OP_Ge: 1 jump, 0 not, -1 fallback; sets iCompare */
static int qv_compare_op(QvX *X, const Op *op) {
  QcVal *a = &X->r[op->p1], *b = &X->r[op->p3];   /* vdbe: pIn1 = P1, pIn3 = P3; res = cmp(P3, P1) */
  int ta = QVT(a), tb = QVT(b), res;
  if (ta == SQLITE_INTEGER && tb == SQLITE_INTEGER) {
    res = b->i > a->i ? 1 : b->i < a->i ? -1 : 0;
  } else if (ta == SQLITE_NULL || tb == SQLITE_NULL) {
    if (op->p5 & SQLITE_NULLEQ) {
      res = (ta == SQLITE_NULL && tb == SQLITE_NULL && !(b->type & QV_CLEARED)) ? 0 : (tb == SQLITE_NULL ? -1 : 1);
    } else {
      X->iCompare = 1;
      return (op->p5 & SQLITE_JUMPIFNULL) ? 1 : 0;
    }
  } else {
    char aff = op->p5 & SQLITE_AFF_MASK; CollSeq *coll = op->p4type == P4_COLLSEQ ? op->p4.pColl : 0;
    if (ta == SQLITE_TEXT && tb == SQLITE_TEXT && aff <= SQLITE_AFF_TEXT && (!coll || coll->xCmp == sqlite3BinaryCompare)) {
      int n = a->n < b->n ? a->n : b->n, c = memcmp(b->z, a->z, (size_t)n); res = c ? c : b->n - a->n;
    } else {   /* vdbe.c's general case on copies (the registers keep their types) */
      Mem m1, m3; qv_mem(&m1, a, X->db); qv_mem(&m3, b, X->db);
      u16 flags1 = m1.flags, flags3 = m3.flags;
      if (aff >= SQLITE_AFF_NUMERIC) {
        if ((flags1 | flags3) & MEM_Str) {
          if ((flags1 & (MEM_Int | MEM_IntReal | MEM_Real | MEM_Str)) == MEM_Str) applyNumericAffinity(&m1, 0);
          if ((flags3 & (MEM_Int | MEM_IntReal | MEM_Real | MEM_Str)) == MEM_Str) applyNumericAffinity(&m3, 0);
        }
      } else if (aff == SQLITE_AFF_TEXT && ((flags1 | flags3) & MEM_Str)) {
        if (flags1 & MEM_Str) m1.flags &= ~(MEM_Int | MEM_Real | MEM_IntReal);
        else if (flags1 & (MEM_Int | MEM_Real | MEM_IntReal)) sqlite3VdbeMemStringify(&m1, SQLITE_UTF8, 1);
        if (flags3 & MEM_Str) m3.flags &= ~(MEM_Int | MEM_Real | MEM_IntReal);
        else if (flags3 & (MEM_Int | MEM_Real | MEM_IntReal)) sqlite3VdbeMemStringify(&m3, SQLITE_UTF8, 1);
      }
      res = sqlite3MemCompare(&m3, &m1, coll);
      sqlite3VdbeMemRelease(&m1); sqlite3VdbeMemRelease(&m3);
    }
  }
  X->iCompare = res;
  return res < 0 ? qv_LT[op->opcode] : res == 0 ? qv_EQ[op->opcode] : qv_GT[op->opcode];
}
/* OP_Add..OP_Remainder; 0 = fallback */
static int qv_arith(QvX *X, const Op *op) {
  QcVal *a = &X->r[op->p1], *b = &X->r[op->p2], *o = &X->r[op->p3];   /* P3 = P2 op P1 */
  int oc = op->opcode;
  if (QVT(a) == SQLITE_INTEGER && QVT(b) == SQLITE_INTEGER) {
    i64 iA = a->i, iB = b->i;
    switch (oc) {
      case OP_Add: if (!__builtin_add_overflow(iB, iA, &iB)) { qv_setint(o, iB); return 1; } break;
      case OP_Subtract: if (!__builtin_sub_overflow(iB, iA, &iB)) { qv_setint(o, iB); return 1; } break;
      case OP_Multiply: if (!__builtin_mul_overflow(iB, iA, &iB)) { qv_setint(o, iB); return 1; } break;
      case OP_Divide: if (iA == 0) { qv_setnull(o); return 1; } if (iA == -1 && iB == SMALLEST_INT64) break; qv_setint(o, iB / iA); return 1;
      default: if (iA == 0) { qv_setnull(o); return 1; } if (iA == -1) iA = 1; qv_setint(o, iB % iA); return 1;
    }
  } else if (QVT(a) == SQLITE_NULL || QVT(b) == SQLITE_NULL) { qv_setnull(o); return 1; }
  /* vdbe.c's path on copies */
  Mem m1, m2; qv_mem(&m1, a, X->db); qv_mem(&m2, b, X->db);
  u16 t1 = numericType(&m1), t2 = numericType(&m2); int ok = 1;
  if ((t1 & t2 & MEM_Int) && !((QVT(a) == SQLITE_INTEGER && QVT(b) == SQLITE_INTEGER))) {
    i64 iA = sqlite3VdbeIntValue(&m1), iB = sqlite3VdbeIntValue(&m2); int fp = 0;
    switch (oc) {
      case OP_Add: fp = sqlite3AddInt64(&iB, iA); break;
      case OP_Subtract: fp = sqlite3SubInt64(&iB, iA); break;
      case OP_Multiply: fp = sqlite3MulInt64(&iB, iA); break;
      case OP_Divide: if (iA == 0) { qv_setnull(o); goto done; } if (iA == -1 && iB == SMALLEST_INT64) fp = 1; else iB /= iA; break;
      default: if (iA == 0) { qv_setnull(o); goto done; } if (iA == -1) iA = 1; iB %= iA; break;
    }
    if (!fp) { qv_setint(o, iB); goto done; }
  }
  {
    double rA = sqlite3VdbeRealValue(&m1), rB = sqlite3VdbeRealValue(&m2);
    switch (oc) {
      case OP_Add: rB += rA; break;
      case OP_Subtract: rB -= rA; break;
      case OP_Multiply: rB *= rA; break;
      case OP_Divide: if (rA == 0.0) { qv_setnull(o); goto done; } rB /= rA; break;
      default: { i64 iA = sqlite3VdbeIntValue(&m1), iB = sqlite3VdbeIntValue(&m2); if (iA == 0) { qv_setnull(o); goto done; } if (iA == -1) iA = 1; rB = (double)(iB % iA); }
    }
    if (sqlite3IsNaN(rB)) qv_setnull(o); else { o->type = SQLITE_FLOAT; o->r = rB; }
  }
done:
  sqlite3VdbeMemRelease(&m1); sqlite3VdbeMemRelease(&m2);
  return ok;
}
static int qv_keys(QvX *X, UnpackedRecord *r, Mem *m, const QcVal *regs, int n) {
  for (int k = 0; k < n; k++) qv_mem(&m[k], &regs[k], X->db);
  r->aMem = m; r->nField = (u16)n; r->eqSeen = 0; r->errCode = 0;
  return 1;
}
static void qv_keys_free(Mem *m, int n) { for (int k = 0; k < n; k++) sqlite3VdbeMemRelease(&m[k]); }
static int qv_cursor_db(QvX *X, const Op *op, QvCur *C) {   /* OpenRead / ReopenIdx: the plan's cursor for this number */
  QvPlan *P = X->P; int i = op->p1; Pgno root = (Pgno)op->p2; KeyInfo *ki = op->p4type == P4_KEYINFO ? op->p4.pKeyInfo : 0;
  if (P->bopen[i] && P->bcRoot[i] != root) { sqlite3BtreeCloseCursor(P->bc[i]); P->bopen[i] = 0; }
  if (!P->bopen[i]) {
    if (!P->bc[i] && !(P->bc[i] = sqlite3MallocZero(sqlite3BtreeCursorSize()))) return 0;
    sqlite3BtreeCursorZero(P->bc[i]);
    if (sqlite3BtreeCursor(P->bt, root, 0, ki, P->bc[i]) != SQLITE_OK) { qv_why = "cursor"; return 0; }
    P->bopen[i] = 1; P->bcRoot[i] = root;
  }
  memset(C, 0, sizeof *C);
  C->kind = QVC_BT; C->bc = P->bc[i]; C->ki = ki; C->isTable = !ki; C->nullRow = 1;
  C->eqOnly = (op->p5 & OPFLAG_SEEKEQ) != 0;
  return qv_cur_alloc(X, C, ki ? ki->nAllField : op->p4.i);
}
static int qv_open_eph(QvX *X, const Op *op, QvCur *C) {
  static const int vfsFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXCLUSIVE | SQLITE_OPEN_DELETEONCLOSE | SQLITE_OPEN_TRANSIENT_DB;
  KeyInfo *ki = op->p4type == P4_KEYINFO ? op->p4.pKeyInfo : 0;
  if (C->kind == QVC_EPH && !C->noReuse && C->ebt) {   /* reopened, no duplicates: emptied (vdbe: ClearTable) */
    C->seqCount = 0; qv_stale(C); C->nullRow = 1;
    if (sqlite3BtreeClearTable(C->ebt, (int)C->eroot, 0) != SQLITE_OK) { qv_why = "eph clear"; return 0; }
    qv_stale_eph(X);
    if (op->p3 > 0) { QcVal *e = &X->r[op->p3]; e->type = SQLITE_BLOB; e->z = (const u8 *)""; e->n = 0; }
    return 1;
  }
  if (C->kind) qv_cur_close(C);
  C->kind = QVC_EPH; C->copyVals = 1; C->ki = ki; C->isTable = !ki; C->nullRow = 1;
  if (!(C->bc = sqlite3MallocZero(sqlite3BtreeCursorSize()))) return 0;
  sqlite3BtreeCursorZero(C->bc);
  if (sqlite3BtreeOpen(X->db->pVfs, 0, X->db, &C->ebt, BTREE_OMIT_JOURNAL | BTREE_SINGLE | op->p5, vfsFlags) != SQLITE_OK) { C->ebt = 0; qv_why = "eph open"; return 0; }
  if (sqlite3BtreeBeginTrans(C->ebt, 1, 0) != SQLITE_OK || (ki && sqlite3BtreeCreateTable(C->ebt, &C->eroot, BTREE_BLOBKEY | op->p5) != SQLITE_OK) ||
      sqlite3BtreeCursor(C->ebt, ki ? C->eroot : SCHEMA_ROOT, BTREE_WRCSR, ki, C->bc) != SQLITE_OK) {
    sqlite3BtreeClose(C->ebt); C->ebt = 0; sqlite3_free(C->bc); C->bc = 0; C->kind = 0; qv_why = "eph open"; return 0;   /* no cursor yet: closed here */
  }
  if (!ki) C->eroot = SCHEMA_ROOT;
  if (op->p3 > 0) { QcVal *e = &X->r[op->p3]; e->type = SQLITE_BLOB; e->z = (const u8 *)""; e->n = 0; }
  return qv_cur_alloc(X, C, ki ? ki->nAllField : op->p2);
}

#ifdef QV_TRACE
static volatile int qv_trace_pc = -1, qv_trace_op = -1;   /* for a crash handler: where qvm was */
#define QV_TRACE_AT(pc, op) (qv_trace_pc = (pc), qv_trace_op = (op))
#else
#define QV_TRACE_AT(pc, op) ((void)0)
#endif
static int qv_run(QvX *X) {
  Vdbe *v = X->v; Op *aOp = v->aOp; QcVal *R = X->r; QvCur *Cs = X->c; int pc = 0, res, rc;
  for (;;) {
    Op *op = &aOp[pc];
    QV_TRACE_AT(pc, op->opcode);
    switch (op->opcode) {
      case OP_Init: pc = op->p2; continue;
      case OP_Transaction: case OP_TableLock: case OP_Noop: case OP_Explain: case OP_ColumnsUsed: case OP_CursorHint:
      case OP_FilterAdd: case OP_SeekScan: case OP_Filter:   /* the bloom filter can only skip work: never jump */
        break;
      case OP_Goto: pc = op->p2; continue;
      case OP_Gosub: qv_setint(OUTR(op->p1), pc); pc = op->p2; continue;
      case OP_Return:
        if (QVT(&R[op->p1]) == SQLITE_INTEGER) { pc = (int)R[op->p1].i + 1; continue; }
        break;
      case OP_InitCoroutine:
        qv_setint(OUTR(op->p1), op->p3 - 1);
        if (op->p2) { pc = op->p2; continue; }
        break;
      case OP_Yield: { int dest = (int)R[op->p1].i; qv_setint(&R[op->p1], pc); pc = dest + 1; continue; }
      case OP_EndCoroutine: { Op *caller = &aOp[R[op->p1].i]; qv_setint(&R[op->p1], pc - 1); pc = caller->p2; continue; }
      case OP_Halt:
        if (op->p1) { qv_why = "halt with error"; return 0; }
        return 1;
      case OP_Integer: qv_setint(OUTR(op->p2), op->p1); break;
      case OP_Int64: qv_setint(OUTR(op->p2), INT32_TO_64(op->p1, op->p3)); break;
      case OP_Real: { u64 ii = (u64)INT32_TO_64(op->p1, op->p3); swapMixedEndianFloat(ii); QcVal *o = OUTR(op->p2); o->type = SQLITE_FLOAT; memcpy(&o->r, &ii, 8); break; }
      case OP_String8: { QcVal *o = OUTR(op->p2); o->type = SQLITE_TEXT; o->z = (const u8 *)op->p4.z; o->n = (int)strlen(op->p4.z); break; }
      case OP_String: { QcVal *o = OUTR(op->p2); o->type = SQLITE_TEXT; o->z = (const u8 *)op->p4.z; o->n = op->p1; break; }
      case OP_Blob: { QcVal *o = OUTR(op->p2); o->type = SQLITE_BLOB; o->z = (const u8 *)op->p4.z; o->n = op->p1; break; }
      case OP_Variable: {
        QcVal *o = OUTR(op->p2);
        if (X->O && X->O->param && op->p1 <= X->O->nparam) { qv_setint(o, X->O->param[op->p1 - 1]); break; }
        Mem *m = &v->aVar[op->p1 - 1];
        u16 f = m->flags;
        if (f & MEM_Null) qv_setnull(o);
        else if (f & MEM_Int) qv_setint(o, m->u.i);
        else if (f & MEM_Real) { o->type = SQLITE_FLOAT; o->r = m->u.r; }
        else if ((f & (MEM_Str | MEM_Blob)) && !(f & MEM_Zero) && (!(f & MEM_Str) || m->enc == SQLITE_UTF8)) {
          o->type = (f & MEM_Str) ? SQLITE_TEXT : SQLITE_BLOB; o->z = (const u8 *)m->z; o->n = m->n;   /* stable while bound */
        } else { qv_why = "parameter"; return 0; }
        break;
      }
      case OP_Copy: {
        for (int k = 0; k <= op->p3; k++) {
          QcVal *o = OUTR(op->p2 + k); *o = R[op->p1 + k];
          if ((op->p5 & 0x0002) && (o->type & QV_SUBTYPE)) o->type &= 0xffff & ~QV_SUBTYPE;
        }
        break;
      }
      case OP_SCopy: *OUTR(op->p2) = R[op->p1]; break;
      case OP_IntCopy: qv_setint(OUTR(op->p2), R[op->p1].i); break;
      case OP_Move:
        for (int k = 0; k < op->p3; k++) { *OUTR(op->p2 + k) = R[op->p1 + k]; qv_setnull(OUTR(op->p1 + k)); }
        break;
      case OP_SoftNull: qv_setnull(OUTR(op->p1)); break;
      case OP_BeginSubrtn: case OP_Null: {
        int cl = op->p1 ? QV_CLEARED : 0;
        for (int k = op->p2; k <= (op->p3 > op->p2 ? op->p3 : op->p2); k++) { QcVal *o = OUTR(k); qv_setnull(o); o->type |= cl; }
        break;
      }
      case OP_ResultRow: {
        if (X->nrow == X->crow) {
          int nc = X->crow ? X->crow * 2 : 64;
          if ((i64)nc * op->p2 > (1 << 22)) { qv_why = "rows"; return 0; }
          QcVal *no = sqlite3_realloc64(X->out, sizeof *no * (u64)nc * (u64)(op->p2 ? op->p2 : 1)); if (!no) return 0;
          X->out = no; X->crow = nc;
        }
        QcVal *o = &X->out[(size_t)X->nrow * (size_t)op->p2];
        for (int k = 0; k < op->p2; k++) { o[k] = R[op->p1 + k]; o[k].type &= 0xff; if (QVT(&o[k]) == SQLITE_NULL) o[k].n = 0; }
        X->nrow++;
        break;
      }
      case OP_Once: {
        int bit = 1 << (pc & 7);
        if (X->once[pc >> 3] & bit) { pc = op->p2; continue; }
        X->once[pc >> 3] |= (u8)bit;
        break;
      }
      case OP_If: if (qv_bool(X, &R[op->p1], op->p3)) { pc = op->p2; continue; } break;
      case OP_IfNot: if (!qv_bool(X, &R[op->p1], !op->p3)) { pc = op->p2; continue; } break;
      case OP_IsNull: if (qv_null(&R[op->p1])) { pc = op->p2; continue; } break;
      case OP_NotNull: if (!qv_null(&R[op->p1])) { pc = op->p2; continue; } break;
      case OP_ZeroOrNull:
        if (qv_null(&R[op->p1]) || qv_null(&R[op->p3])) qv_setnull(OUTR(op->p2)); else qv_setint(OUTR(op->p2), 0);
        break;
      case OP_IfPos: if (R[op->p1].i > 0) { R[op->p1].i -= op->p3; pc = op->p2; continue; } break;
      case OP_IfNotZero: if (R[op->p1].i) { if (R[op->p1].i > 0) R[op->p1].i--; pc = op->p2; continue; } break;
      case OP_DecrJumpZero:
        if (R[op->p1].i > SMALLEST_INT64) R[op->p1].i--;
        if (R[op->p1].i == 0) { pc = op->p2; continue; }
        break;
      case OP_OffsetLimit: {
        i64 x = R[op->p1].i, off = R[op->p3].i;
        qv_setint(OUTR(op->p2), (x <= 0 || sqlite3AddInt64(&x, off > 0 ? off : 0)) ? -1 : x);
        break;
      }
      case OP_AddImm: { QcVal *x = &R[op->p1]; i64 i = qv_int(X, x); qv_setint(x, (i64)((u64)i + (u64)op->p2)); break; }
      case OP_MustBeInt: {
        QcVal *x = &R[op->p1];
        if (QVT(x) != SQLITE_INTEGER) {
          Mem m; qv_mem(&m, x, X->db);
          if (m.flags & MEM_Real) {
            i64 ix;
            if (m.u.r >= -9223372036854775808.0 && m.u.r < 9223372036854775808.0 && (double)(ix = sqlite3RealToI64(m.u.r)) == m.u.r) { m.u.i = ix; m.flags = MEM_Int; }
          } else if (m.flags & MEM_IntReal) { m.flags = MEM_Int; }
          else applyAffinity(&m, SQLITE_AFF_NUMERIC, SQLITE_UTF8);
          int isInt = (m.flags & MEM_Int) != 0; i64 iv = m.u.i;
          sqlite3VdbeMemRelease(&m);
          if (!isInt) { if (!op->p2) { qv_why = "mismatch"; return 0; } pc = op->p2; continue; }
          qv_setint(x, iv);
        }
        break;
      }
      case OP_RealAffinity: {
        QcVal *x = &R[op->p1];
        if (QVT(x) == SQLITE_INTEGER) { double r = (double)x->i; x->type = SQLITE_FLOAT | (x->type & ~0xff & ~QV_INTREAL); x->r = r; }
        else if (x->type & QV_INTREAL) x->type &= ~QV_INTREAL;
        break;
      }
      case OP_Cast: {
        QcVal *x = &R[op->p1]; Mem m; qv_mem(&m, x, X->db);
        rc = sqlite3VdbeMemCast(&m, (u8)op->p2, SQLITE_UTF8);
        int ok = rc == SQLITE_OK && qv_from_mem(X, &m, x); sqlite3VdbeMemRelease(&m);
        if (!ok) return 0;
        break;
      }
      case OP_Affinity: {
        const char *z = op->p4.z;
        for (int k = 0; z[k]; k++) if (!qv_affinity(X, &R[op->p1 + k], z[k], 1)) return 0;
        break;
      }
      case OP_Eq: case OP_Ne: case OP_Lt: case OP_Le: case OP_Gt: case OP_Ge: {
        int j = qv_compare_op(X, op);
        if (j < 0) return 0;
        if (j) { pc = op->p2; continue; }
        break;
      }
      case OP_ElseEq: if (X->iCompare == 0) { pc = op->p2; continue; } break;
      case OP_Permutation: X->aPermute = (const u32 *)op->p4.ai + 1; break;
      case OP_Compare: {
        const u32 *perm = (op->p5 & OPFLAG_PERMUTE) ? X->aPermute : 0; const KeyInfo *ki = op->p4.pKeyInfo;
        for (int i = 0; i < op->p3; i++) {
          u32 idx = perm ? perm[i] : (u32)i;
          int c = qv_cmp(X, &R[op->p1 + idx], &R[op->p2 + idx], ki->aColl[i]);
          X->iCompare = c;
          if (c) {
            if ((ki->aSortFlags[i] & KEYINFO_ORDER_BIGNULL) && (qv_null(&R[op->p1 + idx]) || qv_null(&R[op->p2 + idx]))) X->iCompare = -c;
            if (ki->aSortFlags[i] & KEYINFO_ORDER_DESC) X->iCompare = -X->iCompare;
            break;
          }
        }
        break;
      }
      case OP_Jump: pc = X->iCompare < 0 ? op->p1 : X->iCompare == 0 ? op->p2 : op->p3; continue;
      case OP_Not: { QcVal *x = &R[op->p1]; if (qv_null(x)) qv_setnull(OUTR(op->p2)); else qv_setint(OUTR(op->p2), !qv_bool(X, x, 0)); break; }
      case OP_BitNot: { QcVal *x = &R[op->p1]; if (qv_null(x)) qv_setnull(OUTR(op->p2)); else qv_setint(OUTR(op->p2), ~qv_int(X, x)); break; }
      case OP_IsTrue: qv_setint(OUTR(op->p2), qv_bool(X, &R[op->p1], op->p3) ^ op->p4.i); break;
      case OP_And: case OP_Or: {
        static const u8 and_logic[] = {0, 0, 0, 0, 1, 2, 0, 2, 2}, or_logic[] = {0, 1, 2, 1, 1, 1, 2, 1, 2};
        int v1 = qv_bool(X, &R[op->p1], 2), v2 = qv_bool(X, &R[op->p2], 2);
        v1 = op->opcode == OP_And ? and_logic[v1 * 3 + v2] : or_logic[v1 * 3 + v2];
        if (v1 == 2) qv_setnull(OUTR(op->p3)); else qv_setint(OUTR(op->p3), v1);
        break;
      }
      case OP_BitAnd: case OP_BitOr: case OP_ShiftLeft: case OP_ShiftRight: {
        if (qv_null(&R[op->p1]) || qv_null(&R[op->p2])) { qv_setnull(OUTR(op->p3)); break; }
        i64 iA = qv_int(X, &R[op->p2]), iB = qv_int(X, &R[op->p1]); u64 uA; u8 o = op->opcode;
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
        qv_setint(OUTR(op->p3), iA);
        break;
      }
      case OP_Add: case OP_Subtract: case OP_Multiply: case OP_Divide: case OP_Remainder:
        if (X->P->isAcc[op->p3]) qv_clobber(X, op->p3);
        if (!qv_arith(X, op)) return 0;
        break;
      case OP_Concat: {   /* P3 = P2 || P1 */
        QcVal *a = &R[op->p1], *b = &R[op->p2];
        if (qv_null(a) || qv_null(b)) { qv_setnull(OUTR(op->p3)); break; }
        QcVal sa = *a, sb = *b;
        if ((QVT(&sa) != SQLITE_TEXT && QVT(&sa) != SQLITE_BLOB && !qv_text_of(X, a, &sa)) || (QVT(&sb) != SQLITE_TEXT && QVT(&sb) != SQLITE_BLOB && !qv_text_of(X, b, &sb))) return 0;
        i64 n = (i64)sa.n + sb.n;
        if (n > X->db->aLimit[SQLITE_LIMIT_LENGTH]) { qv_why = "too big"; return 0; }
        char *d = qv_alloc(&X->A, (size_t)n + 1); if (!d) { qv_why = "arena"; return 0; }
        memcpy(d, sb.z, (size_t)sb.n); memcpy(d + sb.n, sa.z, (size_t)sa.n); d[n] = 0;
        QcVal *o = OUTR(op->p3); o->type = SQLITE_TEXT; o->z = (const u8 *)d; o->n = (int)n;
        break;
      }
      case OP_Function: case OP_PureFunc:
        if (X->P->isAcc[op->p3]) qv_clobber(X, op->p3);
        if (!qv_function(X, op, pc)) return 0;
        break;
      case OP_AggStep: case OP_AggStep1: case OP_AggInverse:
        if (!qv_aggstep(X, op, pc, op->opcode == OP_AggInverse || (op->opcode == OP_AggStep1 && op->p1))) return 0;
        break;
      case OP_AggValue: case OP_AggFinal: if (!qv_aggfinal(X, op)) return 0; break;
      case OP_CollSeq: if (op->p1) qv_setint(OUTR(op->p1), 0); break;
      /* ---- cursors */
      case OP_OpenRead: case OP_ReopenIdx: {
        QvCur *C = &Cs[op->p1];
        if (op->opcode == OP_ReopenIdx && C->kind == QVC_BT && X->P->bcRoot[op->p1] == (Pgno)op->p2) { C->nullRow = 1; qv_stale(C); sqlite3BtreeClearCursor(C->bc); break; }
        if (C->kind && C->kind != QVC_BT) qv_cur_close(C);
        if (!qv_cursor_db(X, op, C)) return 0;
        break;
      }
      case OP_OpenEphemeral: case OP_OpenAutoindex: if (!qv_open_eph(X, op, &Cs[op->p1])) return 0; break;
      case OP_OpenDup: {
        QvCur *O = &Cs[op->p2], *C = &Cs[op->p1];
        if (O->kind != QVC_EPH) { qv_why = "opendup"; return 0; }
        if (C->kind) qv_cur_close(C);
        O->noReuse = 1;
        C->kind = QVC_EPH; C->ebt = O->ebt; C->eroot = O->eroot; C->ki = O->ki; C->isTable = O->isTable; C->copyVals = 1; C->nullRow = 1; C->noReuse = 1;
        if (!(C->bc = sqlite3MallocZero(sqlite3BtreeCursorSize()))) return 0;
        sqlite3BtreeCursorZero(C->bc);
        if (sqlite3BtreeCursor(C->ebt, C->eroot, BTREE_WRCSR, C->ki, C->bc) != SQLITE_OK) { qv_why = "opendup cursor"; return 0; }
        if (!qv_cur_alloc(X, C, O->nField)) return 0;
        break;
      }
      case OP_OpenPseudo: {
        QvCur *C = &Cs[op->p1]; if (C->kind) qv_cur_close(C);
        C->kind = QVC_PSEUDO; C->nullRow = 1; C->pseudoReg = op->p2; C->isTable = 1;
        if (!qv_cur_alloc(X, C, op->p3)) return 0;
        break;
      }
      case OP_SorterOpen: {
        QvCur *C = &Cs[op->p1]; if (C->kind) qv_cur_close(C);
        C->kind = QVC_SORT; C->ki = op->p4.pKeyInfo; C->nullRow = 1;
        if (!(C->srt = qv_alloc(&X->A, sizeof *C->srt))) return 0;
        memset(C->srt, 0, sizeof *C->srt); C->srt->ki = C->ki; C->srt->nk = C->ki->nKeyField;
        if (!qv_cur_alloc(X, C, op->p2)) return 0;
        break;
      }
      case OP_Close: { QvCur *C = &Cs[op->p1]; if (C->kind == QVC_BT) memset(C, 0, sizeof *C); else if (C->kind) qv_cur_close(C); break; }
      case OP_NullRow: {
        QvCur *C = &Cs[op->p1];
        if (!C->kind) { C->kind = QVC_NULLONLY; C->isTable = 1; }
        C->nullRow = op->p2 == 0; qv_stale(C);
        if ((C->kind == QVC_BT || C->kind == QVC_EPH) && C->bc) sqlite3BtreeClearCursor(C->bc);
        break;
      }
      case OP_IfNullRow: {
        QvCur *C = &Cs[op->p1];
        if (C->kind && C->nullRow) { qv_setnull(OUTR(op->p3)); pc = op->p2; continue; }
        break;
      }
      case OP_Rewind: case OP_Sort: case OP_SorterSort: {
        QvCur *C = &Cs[op->p1];
        if (C->kind == QVC_SORT) {
          if (!qv_sort(X, C->srt)) return 0;
          C->srt->pos = 0; res = C->srt->n == 0;
        } else {
          if (sqlite3BtreeFirst(C->bc, &res) != SQLITE_OK) { qv_why = "rewind"; return 0; }
          C->deferred = 0;
        }
        qv_stale(C); C->nullRow = (u8)res;
        if (op->p2 > 0 && res) { pc = op->p2; continue; }
        break;
      }
      case OP_Last: {
        QvCur *C = &Cs[op->p1];
        if (C->kind == QVC_SORT) { qv_why = "last on sorter"; return 0; }
        if (sqlite3BtreeLast(C->bc, &res) != SQLITE_OK) { qv_why = "last"; return 0; }
        C->nullRow = (u8)res; C->deferred = 0; qv_stale(C);
        if (op->p2 > 0 && res) { pc = op->p2; continue; }
        break;
      }
      case OP_IfEmpty: {
        QvCur *C = &Cs[op->p1];
        if (sqlite3BtreeIsEmpty(C->bc, &res) != SQLITE_OK) { qv_why = "ifempty"; return 0; }
        if (res) { pc = op->p2; continue; }
        break;
      }
      case OP_Next: case OP_Prev: {
        QvCur *C = &Cs[op->p1];
        rc = op->opcode == OP_Next ? sqlite3BtreeNext(C->bc, op->p3) : sqlite3BtreePrevious(C->bc, op->p3);
        qv_stale(C);
        if (rc == SQLITE_OK) { C->nullRow = 0; pc = op->p2; continue; }
        if (rc != SQLITE_DONE) { qv_why = "next"; return 0; }
        C->nullRow = 1;
        break;
      }
      case OP_SorterNext: {
        QvCur *C = &Cs[op->p1]; qv_stale(C);
        if (++C->srt->pos < C->srt->n) { C->nullRow = 0; pc = op->p2; continue; }
        C->nullRow = 1;
        break;
      }
      case OP_SorterInsert: {
        QvCur *C = &Cs[op->p1]; QvSort *S = C->srt; QcVal *x = &R[op->p2];
        if (QVT(x) != SQLITE_BLOB) { qv_why = "sorter record"; return 0; }
        if (S->n == S->cap) {
          int nc = S->cap ? S->cap * 2 : 64;
          const u8 **nr = qv_alloc(&X->A, sizeof *nr * (size_t)nc); u32 *nl = qv_alloc(&X->A, sizeof *nl * (size_t)nc);
          QcVal *nk = qv_alloc(&X->A, sizeof *nk * (size_t)nc * (size_t)S->nk);
          if (!nr || !nl || !nk) { qv_why = "arena"; return 0; }
          if (S->n) { memcpy(nr, S->rec, sizeof *nr * (size_t)S->n); memcpy(nl, S->len, sizeof *nl * (size_t)S->n); memcpy(nk, S->key, sizeof *nk * (size_t)S->n * (size_t)S->nk); }
          S->rec = nr; S->len = nl; S->key = nk; S->cap = nc;
        }
        if (!qv_decode(x->z, (u32)x->n, S->nk, &S->key[(size_t)S->n * S->nk])) { qv_why = "sorter key"; return 0; }
        S->rec[S->n] = x->z; S->len[S->n] = (u32)x->n; S->n++;
        break;
      }
      case OP_SorterData: {
        QvCur *C = &Cs[op->p1]; QvSort *S = C->srt;
        if (S->pos >= S->n) { qv_why = "sorter data"; return 0; }
        QcVal *o = OUTR(op->p2); o->type = SQLITE_BLOB; o->z = S->rec[S->pos]; o->n = (int)S->len[S->pos];
        qv_stale(&Cs[op->p3]);
        break;
      }
      case OP_SorterCompare: {
        QvCur *C = &Cs[op->p1]; QvSort *S = C->srt; QcVal *x = &R[op->p3]; int nk = op->p4.i;
        if (S->pos >= S->n || QVT(x) != SQLITE_BLOB) { qv_why = "sorter compare"; return 0; }
        UnpackedRecord *u = sqlite3VdbeAllocUnpackedRecord(C->ki); if (!u) return 0;
        u->nField = (u16)nk; sqlite3VdbeRecordUnpack((int)S->len[S->pos], S->rec[S->pos], u);
        res = 0; for (int i = 0; i < nk; i++) if (u->aMem[i].flags & MEM_Null) { res = -1; break; }
        if (!res) res = sqlite3VdbeRecordCompare(x->n, x->z, u);
        sqlite3DbFree(X->db, u);
        if (res) { pc = op->p2; continue; }
        break;
      }
      case OP_Sequence: qv_setint(OUTR(op->p2), Cs[op->p1].seqCount++); break;
      case OP_SequenceTest: if ((Cs[op->p1].seqCount++) == 0) { pc = op->p2; continue; } break;
      case OP_SeekLT: case OP_SeekLE: case OP_SeekGE: case OP_SeekGT: {
        QvCur *C = &Cs[op->p1]; int oc = op->opcode, eqOnly = 0;
        C->nullRow = 0; C->deferred = 0; qv_stale(C);
        if (C->isTable) {
          QcVal *k = &R[op->p3]; i64 iKey;
          if (QVT(k) == SQLITE_INTEGER) iKey = k->i;
          else {
            Mem m; qv_mem(&m, k, X->db);
            if ((m.flags & (MEM_Int | MEM_Real | MEM_IntReal | MEM_Str)) == MEM_Str) applyNumericAffinity(&m, 0);
            iKey = sqlite3VdbeIntValue(&m); u16 nt = m.flags; double rv = m.u.r;
            sqlite3VdbeMemRelease(&m);
            if ((nt & (MEM_Int | MEM_IntReal)) == 0) {
              if ((nt & MEM_Real) == 0) {
                if ((nt & MEM_Null) || oc >= OP_SeekGE) { pc = op->p2; continue; }
                if (sqlite3BtreeLast(C->bc, &res) != SQLITE_OK) { qv_why = "seek"; return 0; }
                goto seek_not_found;
              }
              int c = sqlite3IntFloatCompare(iKey, rv);
              if (c > 0) { if ((oc & 0x0001) == (OP_SeekGT & 0x0001)) oc--; }
              else if (c < 0) { if ((oc & 0x0001) == (OP_SeekLT & 0x0001)) oc++; }
            }
          }
          if (sqlite3BtreeTableMoveto(C->bc, (u64)iKey, 0, &res) != SQLITE_OK) { qv_why = "seek"; return 0; }
          C->movetoTarget = iKey;
        } else {
          eqOnly = C->eqOnly;
          UnpackedRecord r; Mem m[64]; int nf = op->p4.i;
          if (nf > 64) { qv_why = "seek width"; return 0; }
          memset(&r, 0, sizeof r); r.pKeyInfo = C->ki; qv_keys(X, &r, m, &R[op->p3], nf);
          r.default_rc = ((1 & (oc - OP_SeekLT)) ? -1 : +1);
          rc = sqlite3BtreeIndexMoveto(C->bc, &r, &res);
          int eqSeen = r.eqSeen; qv_keys_free(m, nf);
          if (rc != SQLITE_OK) { qv_why = "seek"; return 0; }
          if (eqOnly && !eqSeen) goto seek_not_found;
        }
        if (oc >= OP_SeekGE) {
          if (res < 0 || (res == 0 && oc == OP_SeekGT)) {
            res = 0; rc = sqlite3BtreeNext(C->bc, 0);
            if (rc != SQLITE_OK) { if (rc == SQLITE_DONE) res = 1; else { qv_why = "seek"; return 0; } }
          } else res = 0;
        } else {
          if (res > 0 || (res == 0 && oc == OP_SeekLT)) {
            res = 0; rc = sqlite3BtreePrevious(C->bc, 0);
            if (rc != SQLITE_OK) { if (rc == SQLITE_DONE) res = 1; else { qv_why = "seek"; return 0; } }
          } else res = sqlite3BtreeEof(C->bc);
        }
      seek_not_found:
        if (res) { pc = op->p2; continue; }
        if (eqOnly) pc++;   /* skip the IdxGT / IdxLT that follows */
        break;
      }
      case OP_SeekRowid: case OP_NotExists: {
        QvCur *C = &Cs[op->p1]; QcVal *k = &R[op->p3]; i64 iKey;
        if (QVT(k) == SQLITE_INTEGER || (k->type & QV_INTREAL)) iKey = QVT(k) == SQLITE_INTEGER ? k->i : (i64)k->r;
        else if (op->opcode == OP_NotExists) { qv_why = "notexists key"; return 0; }
        else {
          Mem x; qv_mem(&x, k, X->db);
          if (x.flags & MEM_Str) applyNumericAffinity(&x, 1);
          int ok = 0;
          if (x.flags & MEM_Int) { iKey = x.u.i; ok = 1; }
          else if ((x.flags & MEM_Real) && x.u.r >= -9223372036854775808.0 && x.u.r <= 9223372036854774784.0 && (double)(iKey = sqlite3RealToI64(x.u.r)) == x.u.r) ok = 1;
          sqlite3VdbeMemRelease(&x);
          if (!ok) { pc = op->p2; continue; }
        }
        if (sqlite3BtreeTableMoveto(C->bc, iKey, 0, &res) != SQLITE_OK) { qv_why = "seekrowid"; return 0; }
        C->movetoTarget = iKey; C->nullRow = 0; qv_stale(C); C->deferred = 0; C->seekResult = res;
        if (res) { if (!op->p2) { qv_why = "corrupt"; return 0; } pc = op->p2; continue; }
        break;
      }
      case OP_IdxLE: case OP_IdxGT: case OP_IdxLT: case OP_IdxGE: {
        QvCur *C = &Cs[op->p1]; int nf = op->p4.i; UnpackedRecord r; Mem m[64];
        if (nf > 64) { qv_why = "idx width"; return 0; }
        memset(&r, 0, sizeof r); r.pKeyInfo = C->ki; qv_keys(X, &r, m, &R[op->p3], nf);
        r.default_rc = op->opcode < OP_IdxLT ? -1 : 0;
        u32 sz = sqlite3BtreePayloadSize(C->bc), amt; const u8 *rec = sqlite3BtreePayloadFetch(C->bc, &amt);
        if (amt < sz) {
          u8 *buf = qv_alloc(&X->A, sz + 1); if (!buf || sqlite3BtreePayload(C->bc, 0, sz, buf) != SQLITE_OK) { qv_keys_free(m, nf); qv_why = "idx payload"; return 0; }
          rec = buf;
        }
        res = sqlite3VdbeRecordCompareWithSkip((int)sz, rec, &r, 0);
        int err = r.errCode; qv_keys_free(m, nf);
        if (err) { qv_why = "idx compare"; return 0; }
        if ((op->opcode & 1) == (OP_IdxLT & 1)) res = -res; else res++;
        if (res > 0) { pc = op->p2; continue; }
        break;
      }
      case OP_DeferredSeek: case OP_IdxRowid: {
        QvCur *C = &Cs[op->p1];
        if (C->kind == QVC_BT && sqlite3BtreeCursorHasMoved(C->bc)) { int d = 0; if (sqlite3BtreeCursorRestore(C->bc, &d) != SQLITE_OK) return 0; if (d) C->nullRow = 1; }
        if (!C->nullRow) {
          i64 rowid = 0;
          if (sqlite3VdbeIdxRowid(X->db, C->bc, &rowid) != SQLITE_OK) { qv_why = "idxrowid"; return 0; }
          if (op->opcode == OP_DeferredSeek) {
            QvCur *T = &Cs[op->p3];
            T->nullRow = 0; T->movetoTarget = rowid; T->deferred = 1; qv_stale(T);
            T->altMap = op->p4type == P4_INTARRAY ? (const int *)op->p4.ai : 0; T->alt = C;
          } else qv_setint(OUTR(op->p2), rowid);
        } else if (op->opcode == OP_IdxRowid) qv_setnull(OUTR(op->p2));
        break;
      }
      case OP_FinishSeek: { QvCur *C = &Cs[op->p1]; if (C->deferred && !qv_row(X, C)) return 0; break; }
      case OP_Rowid: {
        QvCur *C = &Cs[op->p1]; QcVal *o = OUTR(op->p2);
        if (C->nullRow) { qv_setnull(o); break; }
        if (C->deferred) { qv_setint(o, C->movetoTarget); break; }
        if (C->kind != QVC_BT && C->kind != QVC_EPH) { qv_why = "rowid cursor"; return 0; }
        if (sqlite3BtreeCursorHasMoved(C->bc)) { int d = 0; if (sqlite3BtreeCursorRestore(C->bc, &d) != SQLITE_OK) return 0; if (d) { C->nullRow = 1; qv_setnull(o); break; } }
        qv_setint(o, sqlite3BtreeIntegerKey(C->bc));
        break;
      }
      case OP_Column: {
        QvCur *C = &Cs[op->p1]; QcVal tmp;
        if (!C->kind) { qv_why = "column cursor"; return 0; }
        if (!qv_column(X, C, op->p2, op, &tmp)) return 0;
        *OUTR(op->p3) = tmp;
        break;
      }
      case OP_RowData: {
        QvCur *C = &Cs[op->p1];
        if (!qv_row(X, C)) return 0;
        u8 *d = qv_alloc(&X->A, C->payload + 1); if (!d) { qv_why = "arena"; return 0; }
        memcpy(d, C->row, C->payload);
        QcVal *o = OUTR(op->p2); o->type = SQLITE_BLOB; o->z = d; o->n = (int)C->payload;
        break;
      }
      case OP_MakeRecord: {
        if (op->p4type == P4_STATIC || op->p4type == P4_DYNAMIC) {
          const char *z = op->p4.z;
          for (int k = 0; z[k]; k++) {
            QcVal *x = &R[op->p1 + k];
            if (!qv_affinity(X, x, z[k], 0)) return 0;
            if (z[k] == SQLITE_AFF_REAL && QVT(x) == SQLITE_INTEGER) { double rv = (double)x->i; x->type = SQLITE_FLOAT | QV_INTREAL | (x->type & ~0xff & ~QV_INTREAL); x->r = rv; }
          }
        }
        QcVal rec; if (!qv_make_record(X, &R[op->p1], op->p2, &rec)) return 0;
        *OUTR(op->p3) = rec;
        break;
      }
      case OP_IdxInsert: {
        QvCur *C = &Cs[op->p1]; QcVal *k = &R[op->p2];
        if (C->kind != QVC_EPH || QVT(k) != SQLITE_BLOB) { qv_why = "idxinsert"; return 0; }
        BtreePayload x; memset(&x, 0, sizeof x); x.pKey = k->z; x.nKey = k->n;
        rc = sqlite3BtreeInsert(C->bc, &x, op->p5 & (OPFLAG_APPEND | OPFLAG_SAVEPOSITION), (op->p5 & OPFLAG_USESEEKRESULT) ? C->seekResult : 0);
        qv_stale_eph(X);
        if (rc) { qv_why = "idxinsert"; return 0; }
        break;
      }
      case OP_Insert: {
        QvCur *C = &Cs[op->p1]; QcVal *d = &R[op->p2], *k = &R[op->p3];
        if (C->kind != QVC_EPH || QVT(k) != SQLITE_INTEGER || (QVT(d) != SQLITE_BLOB && !qv_null(d))) { qv_why = "insert"; return 0; }
        BtreePayload x; memset(&x, 0, sizeof x); x.nKey = k->i; x.pData = qv_null(d) ? 0 : d->z; x.nData = qv_null(d) ? 0 : d->n;
        rc = sqlite3BtreeInsert(C->bc, &x, op->p5 & (OPFLAG_APPEND | OPFLAG_SAVEPOSITION), (op->p5 & OPFLAG_USESEEKRESULT) ? C->seekResult : 0);
        C->deferred = 0; qv_stale_eph(X);
        if (rc) { qv_why = "insert"; return 0; }
        break;
      }
      case OP_NewRowid: {
        QvCur *C = &Cs[op->p1]; i64 nv = 1;
        if (C->kind != QVC_EPH) { qv_why = "newrowid"; return 0; }
        if (sqlite3BtreeLast(C->bc, &res) != SQLITE_OK) { qv_why = "newrowid"; return 0; }
        if (!res) { nv = sqlite3BtreeIntegerKey(C->bc); if (nv >= LARGEST_INT64) { qv_why = "rowid range"; return 0; } nv++; }
        qv_setint(OUTR(op->p2), nv);
        break;
      }
      case OP_Delete: {
        QvCur *C = &Cs[op->p1];
        if (C->kind != QVC_EPH) { qv_why = "delete"; return 0; }
        rc = sqlite3BtreeDelete(C->bc, op->p5); qv_stale_eph(X); C->seekResult = 0;
        if (rc) { qv_why = "delete"; return 0; }
        break;
      }
      case OP_ResetSorter: {
        QvCur *C = &Cs[op->p1];
        if (C->kind == QVC_SORT) { C->srt->n = 0; C->srt->pos = 0; }
        else if (C->kind == QVC_EPH) { if (sqlite3BtreeClearTableOfCursor(C->bc) != SQLITE_OK) { qv_why = "reset"; return 0; } qv_stale_eph(X); }
        else { qv_why = "reset cursor"; return 0; }
        qv_stale(C);
        break;
      }
      case OP_IfNoHope: if (Cs[op->p1].seekHit >= op->p4.i) break; /* fall through */
      case OP_NoConflict: case OP_NotFound: case OP_Found: {
        QvCur *C = &Cs[op->p1]; int nf = op->p4.i; UnpackedRecord r, *pk = 0; Mem m[64];
        if (nf > 64) { qv_why = "found width"; return 0; }
        if (nf > 0) {
          memset(&r, 0, sizeof r); r.pKeyInfo = C->ki; r.default_rc = 0; qv_keys(X, &r, m, &R[op->p3], nf);
          rc = sqlite3BtreeIndexMoveto(C->bc, &r, &C->seekResult);
          qv_keys_free(m, nf);
        } else {
          QcVal *x = &R[op->p3];
          if (QVT(x) != SQLITE_BLOB) { qv_why = "found key"; return 0; }
          if (!(pk = sqlite3VdbeAllocUnpackedRecord(C->ki))) return 0;
          sqlite3VdbeRecordUnpack(x->n, x->z, pk); pk->default_rc = 0;
          rc = sqlite3BtreeIndexMoveto(C->bc, pk, &C->seekResult);
          sqlite3DbFree(X->db, pk);
        }
        if (rc) { qv_why = "found"; return 0; }
        int exists = C->seekResult == 0;
        C->nullRow = (u8)!exists; C->deferred = 0; qv_stale(C);
        if (op->opcode == OP_Found) { if (exists) { pc = op->p2; continue; } }
        else {
          if (!exists) { pc = op->p2; continue; }
          if (op->opcode == OP_NoConflict) {
            int jn = 0; for (int i = 0; i < nf; i++) if (qv_null(&R[op->p3 + i])) jn = 1;
            if (jn) { pc = op->p2; continue; }
          }
          if (op->opcode == OP_IfNoHope) C->seekHit = op->p4.i;
        }
        break;
      }
      case OP_SeekHit: {
        QvCur *C = &Cs[op->p1];
        if (C->seekHit < op->p2) C->seekHit = op->p2; else if (C->seekHit > op->p3) C->seekHit = op->p3;
        break;
      }
      case OP_Count: {
        QvCur *C = &Cs[op->p1]; i64 n = 0;
        if (op->p3) n = sqlite3BtreeRowCountEst(C->bc);
        else if (sqlite3BtreeCount(X->db, C->bc, &n) != SQLITE_OK) { qv_why = "count"; return 0; }
        qv_setint(OUTR(op->p2), n);
        break;
      }
      default: qv_why = sqlite3OpcodeName(op->opcode); return 0;
    }
    pc++;
  }
}

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

static QvX qv_x;   /* one connection, one thread (as the rest of qc) */
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
  QvX *X = &qv_x; QvArena A = X->A; DbPage **pins = X->pins; int cpin = X->cpin; QcVal *out = X->out; int crow = X->crow;
  memset(X, 0, sizeof *X);
  X->A = A; X->pins = pins; X->cpin = cpin; X->out = out; X->crow = crow;
  X->P = P; X->v = v; X->db = db; X->O = cb ? 0 : ctx; qv_why = "";
  X->r = qv_alloc(&X->A, sizeof(QcVal) * (size_t)(P->nMem + 1));
  X->c = qv_alloc(&X->A, sizeof(QvCur) * (size_t)(P->nCur + 1));
  X->once = qv_alloc(&X->A, (size_t)(P->nOp / 8 + 1));
  X->octx = qv_alloc(&X->A, sizeof(void *) * (size_t)P->nOp);
  int needAcc = 0; for (int r = 0; r <= P->nMem && !needAcc; r++) needAcc = P->isAcc[r];
  X->acc = needAcc ? qv_alloc(&X->A, sizeof(Mem) * (size_t)(P->nMem + 1)) : 0;
  int st = QC_FALLBACK;
  if (!X->r || !X->c || !X->once || !X->octx || (needAcc && !X->acc)) { qc_why = "v arena"; goto out; }
  memset(X->octx, 0, sizeof(void *) * (size_t)P->nOp);
  memset(X->r, 0, sizeof(QcVal) * (size_t)(P->nMem + 1));
  memset(X->c, 0, sizeof(QvCur) * (size_t)(P->nCur + 1));
  memset(X->once, 0, (size_t)(P->nOp / 8 + 1));
  if (X->acc) memset(X->acc, 0, sizeof(Mem) * (size_t)(P->nMem + 1));
  if (!qv_run(X)) { qc_why = *qv_why ? qv_why : "v run"; goto out; }
  if (cb) st = cb(ctx, X->nrow, P->nout, X->out);
  else st = qv_write_json(v, X->out, X->nrow, P->nout, ctx, bt && bt->pBt->pPager->xGet == getPageNormal);
out:
  if (X->acc) for (int r = 0; r <= P->nMem; r++) if (X->acc[r].db) sqlite3VdbeMemRelease(&X->acc[r]);
  if (X->octx) for (int i = 0; i < P->nOp; i++) if (X->octx[i]) qv_ctx_free(X->octx[i]);
  if (X->c) for (int c = 0; c < P->nCur; c++) if (X->c[c].kind && X->c[c].kind != QVC_BT) qv_cur_close(&X->c[c]);
  for (int i = 0; i < X->npin; i++) sqlite3PagerUnref(X->pins[i]);
  X->npin = 0;
  qv_arena_reset(&X->A);
  return st;
}
