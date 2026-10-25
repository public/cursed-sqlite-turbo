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
** Everything else is vdbe.c's own code path: the opcode bodies follow vdbe.c, comparisons and affinities call its
** helpers on the registers, ephemeral tables are SQLite's in-memory B-trees with SQLite records, functions and
** aggregates (window ones included) are called through their FuncDefs with the registers as arguments.
** The program is checked opcode by opcode when the statement is lifted; at run time anything not reproduced exactly
** (an error, a write to a real table, a zeroblob, an oversized result) returns QC_FALLBACK before any row is handed
** out, so the caller steps the statement instead. Ephemeral state is private to the execution: nothing to undo. */

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
  u8 kind, isTable, nullRow, deferred, eqOnly, rowOk, copyVals, noReuse, owner;   /* owner: opened the ephemeral B-tree */
  u16 ep5;                                /* OpenEphemeral's P5 (B-tree flags) */
  BtCursor *bc; KeyInfo *ki; int nField;
  Btree *ebt; Pgno eroot;                 /* ephemeral: its B-tree (BTREE_SINGLE: closed with its last cursor) */
  i64 movetoTarget; struct QvCur *alt; const int *altMap;
  int pseudoReg, seekResult, seekHit; i64 seqCount;
  QvSort *srt;
  /* the current row: its record, how far its header is parsed */
  const u8 *row; u32 szRow, payload, hdrOff; int nHdr; u32 *aType, *aOff; DbPage *pinned;
  DbPage *rowPage;                        /* the database page the row's record is in (pinned once a value points into it) */
  int capField;                           /* aType / aOff are kept (malloc) between executions */
  u32 rowGen;                             /* ephemeral: the X->ephGen the cached row was read at */
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
} QvPlan;
typedef struct QvX {
  QvPlan *P; Vdbe *v; sqlite3 *db; const QcOut *O;
  Mem *r; QvCur *c; u8 *once; void **octx;
  QvArena A;
  DbPage **pins; int npin, cpin;
  QcVal *out; int nrow; size_t cout;     /* rows handed out; capacity in values (shared by every plan: widths differ) */
  int iCompare; const u32 *aPermute;
  u32 ephGen;                             /* bumped by every ephemeral write: cached ephemeral rows older than it are stale */
} QvX;
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
static int qv_serial_mem(QvX *X, u32 t, const u8 *d, Mem *m, int copy) {
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
static inline void qv_stale_eph(QvX *X) { X->ephGen++; }   /* a write moved cells: no cached ephemeral row is valid (vdbe.c: colCacheCtr++) */
/* the cursor's position is final and its row's record is at C->row (header not yet parsed): 0 = fallback,
   with C->nullRow set when the row turned out to be gone */
static int qv_row(QvX *X, QvCur *C) {
  if (C->kind == QVC_PSEUDO) {   /* the register's record, whenever it changes */
    Mem *r = &X->r[C->pseudoReg];
    if (!(r->flags & MEM_Blob)) { qv_why = "pseudo"; return 0; }
    if (C->rowOk && C->row == (const u8 *)r->z && C->szRow == (u32)r->n) return 1;
    C->row = (const u8 *)r->z; C->payload = C->szRow = (u32)r->n;
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
/* OP_Column: field p2 of the cursor's current row into register m (released); 0 = fallback */
static int qv_column(QvX *X, QvCur *C, int p2, const Op *op, Mem *m) {
  for (;;) {
    if (C->nullRow && C->kind != QVC_PSEUDO) { m->flags = MEM_Null; return 1; }
    if (C->deferred && C->altMap && C->altMap[1 + p2] > 0) { p2 = C->altMap[1 + p2] - 1; C = C->alt; continue; }
    break;
  }
  if (!qv_row(X, C)) return 0;
  if (C->nullRow && C->kind != QVC_PSEUDO) { m->flags = MEM_Null; return 1; }
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
static int qv_aggstep(QvX *X, const Op *op, int pc, int inverse) {   /* OP_AggStep1 */
  FuncDef *f = op->p4type == P4_FUNCDEF ? op->p4.pFunc : op->p4.pCtx->pFunc; int argc = op->p5;
  Mem *acc = &X->r[op->p3];
  QvCtx *k = qv_ctx(X, pc, f, argc, op->p2); if (!k) return 0;
  k->u.c.pMem = acc; k->u.c.pOut = &k->res;
  acc->n++;
  if (inverse) f->xInverse(&k->u.c, argc, k->u.c.argv); else f->xSFunc(&k->u.c, argc, k->u.c.argv);
  int ok = !k->u.c.isError && !X->db->mallocFailed;
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
  if (!P->r || !P->c || !P->octx || !P->once || !P->isCnt || !P->cnt || !P->keep || qv_nplans >= 64) { qc_why = "plans"; return 0; }   /* (leaks on this rare path) */
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
static int qv_open_eph(QvX *X, const Op *op, QvCur *C) {
  static const int vfsFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXCLUSIVE | SQLITE_OPEN_DELETEONCLOSE | SQLITE_OPEN_TRANSIENT_DB;
  KeyInfo *ki = op->p4type == P4_KEYINFO ? op->p4.pKeyInfo : 0;
  if (op->p3 > 0) { Mem *e = qv_out(X, op->p3); qv_static(e, "", 0, 0, 0); }   /* an empty record for Insert */
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
static int qv_run(QvX *X) {
  Vdbe *v = X->v; Op *aOp = v->aOp; Mem *R = X->r; QvCur *Cs = X->c; int pc = 0, res, rc; Op *op;
#if defined(__GNUC__) && !defined(QV_NO_THREADED)
  static const void *const qv_disp[256] = { [0 ... 255] = &&L_default,
    [OP_Add] = &&L_OP_Add, [OP_AddImm] = &&L_OP_AddImm, [OP_Affinity] = &&L_OP_Affinity, [OP_AggFinal] = &&L_OP_AggFinal,
    [OP_AggInverse] = &&L_OP_AggInverse, [OP_AggStep] = &&L_OP_AggStep, [OP_AggStep1] = &&L_OP_AggStep1, [OP_AggValue] = &&L_OP_AggValue,
    [OP_And] = &&L_OP_And, [OP_BeginSubrtn] = &&L_OP_BeginSubrtn, [OP_BitAnd] = &&L_OP_BitAnd, [OP_BitNot] = &&L_OP_BitNot,
    [OP_BitOr] = &&L_OP_BitOr, [OP_Blob] = &&L_OP_Blob, [OP_Cast] = &&L_OP_Cast, [OP_Close] = &&L_OP_Close,
    [OP_CollSeq] = &&L_OP_CollSeq, [OP_Column] = &&L_OP_Column, [OP_ColumnsUsed] = &&L_OP_ColumnsUsed, [OP_Compare] = &&L_OP_Compare,
    [OP_Concat] = &&L_OP_Concat, [OP_Copy] = &&L_OP_Copy, [OP_Count] = &&L_OP_Count, [OP_CursorHint] = &&L_OP_CursorHint,
    [OP_DecrJumpZero] = &&L_OP_DecrJumpZero, [OP_DeferredSeek] = &&L_OP_DeferredSeek, [OP_Delete] = &&L_OP_Delete, [OP_Divide] = &&L_OP_Divide,
    [OP_ElseEq] = &&L_OP_ElseEq, [OP_EndCoroutine] = &&L_OP_EndCoroutine, [OP_Eq] = &&L_OP_Eq, [OP_Explain] = &&L_OP_Explain,
    [OP_Filter] = &&L_OP_Filter, [OP_FilterAdd] = &&L_OP_FilterAdd, [OP_FinishSeek] = &&L_OP_FinishSeek, [OP_Found] = &&L_OP_Found,
    [OP_Function] = &&L_OP_Function, [OP_Ge] = &&L_OP_Ge, [OP_Gosub] = &&L_OP_Gosub, [OP_Goto] = &&L_OP_Goto,
    [OP_Gt] = &&L_OP_Gt, [OP_Halt] = &&L_OP_Halt, [OP_IdxGE] = &&L_OP_IdxGE, [OP_IdxGT] = &&L_OP_IdxGT,
    [OP_IdxInsert] = &&L_OP_IdxInsert, [OP_IdxLE] = &&L_OP_IdxLE, [OP_IdxLT] = &&L_OP_IdxLT, [OP_IdxRowid] = &&L_OP_IdxRowid,
    [OP_If] = &&L_OP_If, [OP_IfEmpty] = &&L_OP_IfEmpty, [OP_IfNoHope] = &&L_OP_IfNoHope, [OP_IfNot] = &&L_OP_IfNot,
    [OP_IfNotZero] = &&L_OP_IfNotZero, [OP_IfNullRow] = &&L_OP_IfNullRow, [OP_IfPos] = &&L_OP_IfPos, [OP_Init] = &&L_OP_Init,
    [OP_InitCoroutine] = &&L_OP_InitCoroutine, [OP_Insert] = &&L_OP_Insert, [OP_Int64] = &&L_OP_Int64, [OP_IntCopy] = &&L_OP_IntCopy,
    [OP_Integer] = &&L_OP_Integer, [OP_IsNull] = &&L_OP_IsNull, [OP_IsTrue] = &&L_OP_IsTrue, [OP_Jump] = &&L_OP_Jump,
    [OP_Last] = &&L_OP_Last, [OP_Le] = &&L_OP_Le, [OP_Lt] = &&L_OP_Lt, [OP_MakeRecord] = &&L_OP_MakeRecord,
    [OP_Move] = &&L_OP_Move, [OP_Multiply] = &&L_OP_Multiply, [OP_MustBeInt] = &&L_OP_MustBeInt, [OP_Ne] = &&L_OP_Ne,
    [OP_NewRowid] = &&L_OP_NewRowid, [OP_Next] = &&L_OP_Next, [OP_NoConflict] = &&L_OP_NoConflict, [OP_Noop] = &&L_OP_Noop,
    [OP_Not] = &&L_OP_Not, [OP_NotExists] = &&L_OP_NotExists, [OP_NotFound] = &&L_OP_NotFound, [OP_NotNull] = &&L_OP_NotNull,
    [OP_Null] = &&L_OP_Null, [OP_NullRow] = &&L_OP_NullRow, [OP_OffsetLimit] = &&L_OP_OffsetLimit, [OP_Once] = &&L_OP_Once,
    [OP_OpenAutoindex] = &&L_OP_OpenAutoindex, [OP_OpenDup] = &&L_OP_OpenDup, [OP_OpenEphemeral] = &&L_OP_OpenEphemeral, [OP_OpenPseudo] = &&L_OP_OpenPseudo,
    [OP_OpenRead] = &&L_OP_OpenRead, [OP_Or] = &&L_OP_Or, [OP_Permutation] = &&L_OP_Permutation, [OP_Prev] = &&L_OP_Prev,
    [OP_PureFunc] = &&L_OP_PureFunc, [OP_Real] = &&L_OP_Real, [OP_RealAffinity] = &&L_OP_RealAffinity, [OP_Remainder] = &&L_OP_Remainder,
    [OP_ReopenIdx] = &&L_OP_ReopenIdx, [OP_ResetSorter] = &&L_OP_ResetSorter, [OP_ResultRow] = &&L_OP_ResultRow, [OP_Return] = &&L_OP_Return,
    [OP_Rewind] = &&L_OP_Rewind, [OP_RowData] = &&L_OP_RowData, [OP_Rowid] = &&L_OP_Rowid, [OP_SCopy] = &&L_OP_SCopy,
    [OP_SeekGE] = &&L_OP_SeekGE, [OP_SeekGT] = &&L_OP_SeekGT, [OP_SeekHit] = &&L_OP_SeekHit, [OP_SeekLE] = &&L_OP_SeekLE,
    [OP_SeekLT] = &&L_OP_SeekLT, [OP_SeekRowid] = &&L_OP_SeekRowid, [OP_SeekScan] = &&L_OP_SeekScan, [OP_Sequence] = &&L_OP_Sequence,
    [OP_SequenceTest] = &&L_OP_SequenceTest, [OP_ShiftLeft] = &&L_OP_ShiftLeft, [OP_ShiftRight] = &&L_OP_ShiftRight, [OP_SoftNull] = &&L_OP_SoftNull,
    [OP_Sort] = &&L_OP_Sort, [OP_SorterCompare] = &&L_OP_SorterCompare, [OP_SorterData] = &&L_OP_SorterData, [OP_SorterInsert] = &&L_OP_SorterInsert,
    [OP_SorterNext] = &&L_OP_SorterNext, [OP_SorterOpen] = &&L_OP_SorterOpen, [OP_SorterSort] = &&L_OP_SorterSort, [OP_String] = &&L_OP_String,
    [OP_String8] = &&L_OP_String8, [OP_Subtract] = &&L_OP_Subtract, [OP_TableLock] = &&L_OP_TableLock, [OP_Transaction] = &&L_OP_Transaction,
    [OP_Variable] = &&L_OP_Variable, [OP_Yield] = &&L_OP_Yield, [OP_ZeroOrNull] = &&L_OP_ZeroOrNull };
  QJUMP;
#endif
  for (;;) {
  qv_top: QV_UNUSED_LABEL;
    op = &aOp[pc];
    QV_TRACE_AT(pc, op->opcode);
    switch (op->opcode) {
      case OP_Init: QL(OP_Init) pc = op->p2; QJUMP;
      case OP_Transaction: QL(OP_Transaction) case OP_TableLock: QL(OP_TableLock) case OP_Noop: QL(OP_Noop) case OP_Explain: QL(OP_Explain) case OP_ColumnsUsed: QL(OP_ColumnsUsed) case OP_CursorHint: QL(OP_CursorHint)
      case OP_FilterAdd: QL(OP_FilterAdd) case OP_SeekScan: QL(OP_SeekScan) case OP_Filter: QL(OP_Filter)   /* the bloom filter can only skip work: never jump */
        QNEXT;
      case OP_Goto: QL(OP_Goto) pc = op->p2; QJUMP;
      case OP_Gosub: QL(OP_Gosub) qv_int(qv_out(X, op->p1), pc); pc = op->p2; QJUMP;
      case OP_Return: QL(OP_Return)
        if (R[op->p1].flags & MEM_Int) { pc = (int)R[op->p1].u.i + 1; QJUMP; }
        QNEXT;
      case OP_InitCoroutine: QL(OP_InitCoroutine)
        qv_int(qv_out(X, op->p1), op->p3 - 1);
        if (op->p2) { pc = op->p2; QJUMP; }
        QNEXT;
      case OP_Yield: QL(OP_Yield) { int dest = (int)R[op->p1].u.i; qv_int(&R[op->p1], pc); pc = dest + 1; QJUMP; }
      case OP_EndCoroutine: QL(OP_EndCoroutine) { Op *caller = &aOp[R[op->p1].u.i]; qv_int(&R[op->p1], pc - 1); pc = caller->p2; QJUMP; }
      case OP_Halt: QL(OP_Halt)
        if (op->p1) { qv_why = "halt with error"; return 0; }
        return 1;
      case OP_Integer: QL(OP_Integer) qv_int(qv_out(X, op->p2), op->p1); QNEXT;
      case OP_Int64: QL(OP_Int64) qv_int(qv_out(X, op->p2), INT32_TO_64(op->p1, op->p3)); QNEXT;
      case OP_Real: QL(OP_Real) { u64 ii = (u64)INT32_TO_64(op->p1, op->p3); swapMixedEndianFloat(ii); Mem *o = qv_out(X, op->p2); o->flags = MEM_Real; memcpy(&o->u.r, &ii, 8); QNEXT; }
      case OP_String8: QL(OP_String8) qv_static(qv_out(X, op->p2), op->p4.z, (int)strlen(op->p4.z), 1, 1); QNEXT;
      case OP_String: QL(OP_String) qv_static(qv_out(X, op->p2), op->p4.z, op->p1, 1, op->p4.z[op->p1] == 0); QNEXT;
      case OP_Blob: QL(OP_Blob) qv_static(qv_out(X, op->p2), op->p4.z, op->p1, 0, 0); QNEXT;
      case OP_Variable: QL(OP_Variable) {
        Mem *o = qv_out(X, op->p2);
        if (X->O && X->O->param && op->p1 <= X->O->nparam) { qv_int(o, X->O->param[op->p1 - 1]); QNEXT; }
        Mem *pVar = &v->aVar[op->p1 - 1];
        if (pVar->flags & MEM_Zero) { qv_why = "zeroblob parameter"; return 0; }
        memcpy(o, pVar, MEMCELLSIZE); o->flags &= ~(MEM_Dyn | MEM_Ephem); o->flags |= MEM_Static | MEM_FromBind;   /* as vdbe.c */
        QNEXT;
      }
      case OP_Copy: QL(OP_Copy)
        for (int k = 0; k <= op->p3; k++) {
          Mem *o = qv_out(X, op->p2 + k);
          sqlite3VdbeMemShallowCopy(o, &R[op->p1 + k], MEM_Ephem);
          if ((o->flags & MEM_Ephem) && sqlite3VdbeMemMakeWriteable(o)) return 0;   /* Deephemeralize */
          if ((o->flags & MEM_Subtype) && (op->p5 & 0x0002)) o->flags &= ~MEM_Subtype;
        }
        QNEXT;
      case OP_SCopy: QL(OP_SCopy) sqlite3VdbeMemShallowCopy(qv_out(X, op->p2), &R[op->p1], MEM_Ephem); QNEXT;
      case OP_IntCopy: QL(OP_IntCopy) sqlite3VdbeMemSetInt64(qv_out(X, op->p2), R[op->p1].u.i); QNEXT;
      case OP_Move: QL(OP_Move)
        for (int k = 0; k < op->p3; k++) {
          Mem *o = qv_out(X, op->p2 + k);
          if (X->P->isCnt[op->p1 + k]) { qv_why = "move of a counter"; return 0; }
          sqlite3VdbeMemMove(o, &R[op->p1 + k]);
          if ((o->flags & MEM_Ephem) && sqlite3VdbeMemMakeWriteable(o)) return 0;
        }
        QNEXT;
      case OP_SoftNull: QL(OP_SoftNull) { Mem *o = qv_out(X, op->p1); o->flags = (o->flags & ~(MEM_Undefined | MEM_AffMask)) | MEM_Null; QNEXT; }
      case OP_BeginSubrtn: QL(OP_BeginSubrtn) case OP_Null: QL(OP_Null) {
        u16 nf = op->p1 ? (MEM_Null | MEM_Cleared) : MEM_Null;
        for (int k = op->p2; k <= (op->p3 > op->p2 ? op->p3 : op->p2); k++) { Mem *o = qv_out(X, k); o->flags = nf; o->n = 0; }
        QNEXT;
      }
      case OP_ResultRow: QL(OP_ResultRow) {
        size_t need = ((size_t)X->nrow + 1) * (size_t)op->p2;
        if (need > X->cout) {
          size_t nc = X->cout ? X->cout * 2 : 256; while (nc < need) nc *= 2;
          if (nc > ((size_t)1 << 22)) { qv_why = "rows"; return 0; }
          QcVal *no = sqlite3_realloc64(X->out, sizeof *no * (u64)nc); if (!no) return 0;
          X->out = no; X->cout = nc;
        }
        QcVal *o = &X->out[(size_t)X->nrow * (size_t)op->p2];
        for (int k = 0; k < op->p2; k++) {
          if (!qv_val(X, &R[op->p1 + k], &o[k])) return 0;
        }
        X->nrow++;
        QNEXT;
      }
      case OP_Once: QL(OP_Once) {
        int bit = 1 << (pc & 7);
        if (X->once[pc >> 3] & bit) { pc = op->p2; QJUMP; }
        X->once[pc >> 3] |= (u8)bit;
        QNEXT;
      }
      case OP_If: QL(OP_If) if (sqlite3VdbeBooleanValue(&R[op->p1], op->p3)) { pc = op->p2; QJUMP; } QNEXT;
      case OP_IfNot: QL(OP_IfNot) if (!sqlite3VdbeBooleanValue(&R[op->p1], !op->p3)) { pc = op->p2; QJUMP; } QNEXT;
      case OP_IsNull: QL(OP_IsNull) if (qv_isnull(&R[op->p1])) { pc = op->p2; QJUMP; } QNEXT;
      case OP_NotNull: QL(OP_NotNull) if (!qv_isnull(&R[op->p1])) { pc = op->p2; QJUMP; } QNEXT;
      case OP_ZeroOrNull: QL(OP_ZeroOrNull)
        if (qv_isnull(&R[op->p1]) || qv_isnull(&R[op->p3])) qv_out(X, op->p2)->flags = MEM_Null; else qv_int(qv_out(X, op->p2), 0);
        QNEXT;
      case OP_IfPos: QL(OP_IfPos) if (R[op->p1].u.i > 0) { R[op->p1].u.i -= op->p3; pc = op->p2; QJUMP; } QNEXT;
      case OP_IfNotZero: QL(OP_IfNotZero) if (R[op->p1].u.i) { if (R[op->p1].u.i > 0) R[op->p1].u.i--; pc = op->p2; QJUMP; } QNEXT;
      case OP_DecrJumpZero: QL(OP_DecrJumpZero)
        if (R[op->p1].u.i > SMALLEST_INT64) R[op->p1].u.i--;
        if (R[op->p1].u.i == 0) { pc = op->p2; QJUMP; }
        QNEXT;
      case OP_OffsetLimit: QL(OP_OffsetLimit) {
        i64 x = R[op->p1].u.i, off = R[op->p3].u.i;
        qv_int(qv_out(X, op->p2), (x <= 0 || sqlite3AddInt64(&x, off > 0 ? off : 0)) ? -1 : x);
        QNEXT;
      }
      case OP_AddImm: QL(OP_AddImm) { Mem *x = &R[op->p1]; sqlite3VdbeMemIntegerify(x); *(u64 *)&x->u.i += (u64)op->p2; QNEXT; }
      case OP_MustBeInt: QL(OP_MustBeInt) {
        Mem *x = &R[op->p1];
        if (!(x->flags & MEM_Int)) {
          if (x->flags & MEM_Real) {
            i64 ix;
            if (x->u.r >= -9223372036854775808.0 && x->u.r < 9223372036854775808.0 && (double)(ix = sqlite3RealToI64(x->u.r)) == x->u.r) { x->u.i = ix; MemSetTypeFlag(x, MEM_Int); }
          } else applyAffinity(x, SQLITE_AFF_NUMERIC, SQLITE_UTF8);
          if (!(x->flags & MEM_Int)) { if (!op->p2) { qv_why = "mismatch"; return 0; } pc = op->p2; QJUMP; }
        }
        MemSetTypeFlag(x, MEM_Int);
        QNEXT;
      }
      case OP_RealAffinity: QL(OP_RealAffinity) if (R[op->p1].flags & (MEM_Int | MEM_IntReal)) sqlite3VdbeMemRealify(&R[op->p1]); QNEXT;
      case OP_Cast: QL(OP_Cast)
        if (sqlite3VdbeMemCast(&R[op->p1], (u8)op->p2, SQLITE_UTF8) != SQLITE_OK) { qv_why = "cast"; return 0; }
        QNEXT;
      case OP_Affinity: QL(OP_Affinity) {
        const char *z = op->p4.z; Mem *x = &R[op->p1];
        for (; z[0]; z++, x++) {   /* (no break inside: the dispatch below is threaded) */
          applyAffinity(x, z[0], SQLITE_UTF8);
          if (z[0] == SQLITE_AFF_REAL && (x->flags & MEM_Int)) { x->u.r = (double)x->u.i; x->flags |= MEM_Real; x->flags &= ~(MEM_Int | MEM_Str); }
        }
        QNEXT;
      }
      case OP_Eq: QL(OP_Eq) case OP_Ne: QL(OP_Ne) case OP_Lt: QL(OP_Lt) case OP_Le: QL(OP_Le) case OP_Gt: QL(OP_Gt) case OP_Ge: QL(OP_Ge)
        if (qv_compare_op(X, op)) { pc = op->p2; QJUMP; }
        QNEXT;
      case OP_ElseEq: QL(OP_ElseEq) if (X->iCompare == 0) { pc = op->p2; QJUMP; } QNEXT;
      case OP_Permutation: QL(OP_Permutation) X->aPermute = (const u32 *)op->p4.ai + 1; QNEXT;
      case OP_Compare: QL(OP_Compare) {
        const u32 *perm = (op->p5 & OPFLAG_PERMUTE) ? X->aPermute : 0; const KeyInfo *ki = op->p4.pKeyInfo;
        int done = 0;
        for (int i = 0; i < op->p3 && !done; i++) {
          u32 idx = perm ? perm[i] : (u32)i;
          X->iCompare = sqlite3MemCompare(&R[op->p1 + idx], &R[op->p2 + idx], ki->aColl[i]);
          if (X->iCompare) {
            if ((ki->aSortFlags[i] & KEYINFO_ORDER_BIGNULL) && ((R[op->p1 + idx].flags & MEM_Null) || (R[op->p2 + idx].flags & MEM_Null))) X->iCompare = -X->iCompare;
            if (ki->aSortFlags[i] & KEYINFO_ORDER_DESC) X->iCompare = -X->iCompare;
            done = 1;
          }
        }
        QNEXT;
      }
      case OP_Jump: QL(OP_Jump) pc = X->iCompare < 0 ? op->p1 : X->iCompare == 0 ? op->p2 : op->p3; QJUMP;
      case OP_Not: QL(OP_Not) {
        Mem *x = &R[op->p1];
        if (!qv_isnull(x)) { int b = !sqlite3VdbeBooleanValue(x, 0); sqlite3VdbeMemSetInt64(qv_out(X, op->p2), b); }
        else qv_out(X, op->p2)->flags = MEM_Null;
        QNEXT;
      }
      case OP_BitNot: QL(OP_BitNot) {
        Mem *x = &R[op->p1];
        if (!qv_isnull(x)) { i64 b = ~sqlite3VdbeIntValue(x); sqlite3VdbeMemSetInt64(qv_out(X, op->p2), b); }
        else qv_out(X, op->p2)->flags = MEM_Null;
        QNEXT;
      }
      case OP_IsTrue: QL(OP_IsTrue) { int b = sqlite3VdbeBooleanValue(&R[op->p1], op->p3) ^ op->p4.i; sqlite3VdbeMemSetInt64(qv_out(X, op->p2), b); QNEXT; }
      case OP_And: QL(OP_And) case OP_Or: QL(OP_Or) {
        static const u8 and_logic[] = {0, 0, 0, 0, 1, 2, 0, 2, 2}, or_logic[] = {0, 1, 2, 1, 1, 1, 2, 1, 2};
        int v1 = sqlite3VdbeBooleanValue(&R[op->p1], 2), v2 = sqlite3VdbeBooleanValue(&R[op->p2], 2);
        v1 = op->opcode == OP_And ? and_logic[v1 * 3 + v2] : or_logic[v1 * 3 + v2];
        Mem *o = qv_out(X, op->p3);
        if (v1 == 2) o->flags = MEM_Null; else qv_int(o, v1);
        QNEXT;
      }
      case OP_BitAnd: QL(OP_BitAnd) case OP_BitOr: QL(OP_BitOr) case OP_ShiftLeft: QL(OP_ShiftLeft) case OP_ShiftRight: QL(OP_ShiftRight) {
        Mem *pIn1 = &R[op->p1], *pIn2 = &R[op->p2];
        if ((pIn1->flags | pIn2->flags) & MEM_Null) { qv_out(X, op->p3)->flags = MEM_Null; QNEXT; }
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
        QNEXT;
      }
      case OP_Add: QL(OP_Add) case OP_Subtract: QL(OP_Subtract) case OP_Multiply: QL(OP_Multiply) case OP_Divide: QL(OP_Divide) case OP_Remainder: QL(OP_Remainder) qv_arith(X, op); QNEXT;
      case OP_Concat: QL(OP_Concat) {   /* P3 = P2 || P1, into the arena */
        Mem *pIn1 = &R[op->p1], *pIn2 = &R[op->p2];
        if ((pIn1->flags | pIn2->flags) & MEM_Null) { qv_out(X, op->p3)->flags = MEM_Null; QNEXT; }
        u16 flags1 = pIn1->flags, flags2;
        if (!(flags1 & (MEM_Str | MEM_Blob))) { if (sqlite3VdbeMemStringify(pIn1, SQLITE_UTF8, 0)) return 0; flags1 = pIn1->flags & ~MEM_Str; }
        else if (flags1 & MEM_Zero) { if (sqlite3VdbeMemExpandBlob(pIn1)) return 0; flags1 = pIn1->flags & ~MEM_Str; }
        flags2 = pIn2->flags;
        if (!(flags2 & (MEM_Str | MEM_Blob))) { if (sqlite3VdbeMemStringify(pIn2, SQLITE_UTF8, 0)) return 0; flags2 = pIn2->flags & ~MEM_Str; }
        else if (flags2 & MEM_Zero) { if (sqlite3VdbeMemExpandBlob(pIn2)) return 0; flags2 = pIn2->flags & ~MEM_Str; }
        i64 n = (i64)pIn1->n + pIn2->n;
        if (n > X->db->aLimit[SQLITE_LIMIT_LENGTH]) { qv_why = "too big"; return 0; }
        char *d = qv_alloc(&X->A, (size_t)n + 1); if (!d) { qv_why = "arena"; return 0; }
        memcpy(d, pIn2->z, (size_t)pIn2->n); memcpy(d + pIn2->n, pIn1->z, (size_t)pIn1->n); d[n] = 0;
        pIn1->flags = flags1; if (pIn1 != pIn2) pIn2->flags = flags2;   /* as vdbe.c: the stringified inputs keep their types */
        qv_static(qv_out(X, op->p3), d, (int)n, 1, 1);
        QNEXT;
      }
      case OP_Function: QL(OP_Function) case OP_PureFunc: QL(OP_PureFunc) if (!qv_function(X, op, pc)) return 0; QNEXT;
      case OP_AggStep: QL(OP_AggStep) case OP_AggStep1: QL(OP_AggStep1) case OP_AggInverse: QL(OP_AggInverse) {
        int inv = op->opcode == OP_AggInverse || (op->opcode == OP_AggStep1 && op->p1);
        if (X->P->isCnt[op->p3]) {   /* count(*) / count(x) */
          if (op->p5 == 0 || !qv_isnull(&R[op->p2])) X->P->cnt[op->p3] += inv ? -1 : 1;
          QNEXT;
        }
        if (!qv_aggstep(X, op, pc, inv)) return 0;
        QNEXT;
      }
      case OP_AggValue: QL(OP_AggValue) case OP_AggFinal: QL(OP_AggFinal)
        if (X->P->isCnt[op->p1]) {
          i64 n = X->P->cnt[op->p1];
          if (op->p3) qv_int(qv_out(X, op->p3), n); else qv_int(qv_out(X, op->p1), n);   /* (qv_out restarts the counter) */
          QNEXT;
        }
        if (!qv_aggfinal(X, op)) return 0;
        QNEXT;
      case OP_CollSeq: QL(OP_CollSeq) if (op->p1) qv_int(qv_out(X, op->p1), 0); QNEXT;
      /* ---- cursors */
      case OP_OpenRead: QL(OP_OpenRead) case OP_ReopenIdx: QL(OP_ReopenIdx) {
        QvCur *C = &Cs[op->p1];
        if (op->opcode == OP_ReopenIdx && C->kind == QVC_BT && X->P->bcRoot[op->p1] == (Pgno)op->p2) { C->nullRow = 1; qv_stale(C); sqlite3BtreeClearCursor(C->bc); QNEXT; }
        if (C->kind && C->kind != QVC_BT) qv_cur_close(C);
        if (!qv_cursor_db(X, op, C)) return 0;
        QNEXT;
      }
      case OP_OpenEphemeral: QL(OP_OpenEphemeral) case OP_OpenAutoindex: QL(OP_OpenAutoindex) if (!qv_open_eph(X, op, &Cs[op->p1])) return 0; QNEXT;
      case OP_OpenDup: QL(OP_OpenDup) {
        QvCur *O = &Cs[op->p2], *C = &Cs[op->p1];
        if (O->kind != QVC_EPH) { qv_why = "opendup"; return 0; }
        if (C->kind) qv_cur_close(C);
        O->noReuse = 1;
        C->kind = QVC_EPH; C->ebt = O->ebt; C->eroot = O->eroot; C->ki = O->ki; C->isTable = O->isTable; C->copyVals = 1; C->nullRow = 1; C->noReuse = 1;
        if (!(C->bc = qv_bc_alloc())) return 0;
        if (sqlite3BtreeCursor(C->ebt, C->eroot, BTREE_WRCSR, C->ki, C->bc) != SQLITE_OK) { qv_why = "opendup cursor"; return 0; }
        if (!qv_cur_alloc(X, C, O->nField)) return 0;
        QNEXT;
      }
      case OP_OpenPseudo: QL(OP_OpenPseudo) {
        QvCur *C = &Cs[op->p1]; if (C->kind) qv_cur_close(C);
        C->kind = QVC_PSEUDO; C->nullRow = 1; C->pseudoReg = op->p2; C->isTable = 1;
        if (!qv_cur_alloc(X, C, op->p3)) return 0;
        QNEXT;
      }
      case OP_SorterOpen: QL(OP_SorterOpen) {
        QvCur *C = &Cs[op->p1]; if (C->kind) qv_cur_close(C);
        C->kind = QVC_SORT; C->ki = op->p4.pKeyInfo; C->nullRow = 1;
        if (!(C->srt = qv_alloc(&X->A, sizeof *C->srt))) return 0;
        memset(C->srt, 0, sizeof *C->srt); C->srt->ki = C->ki; C->srt->nk = C->ki->nKeyField;
        if (!qv_cur_alloc(X, C, op->p2)) return 0;
        QNEXT;
      }
      case OP_Close: QL(OP_Close) { QvCur *C = &Cs[op->p1]; if (C->kind == QVC_BT) qv_cur_reset(C); else if (C->kind) qv_cur_close(C); QNEXT; }
      case OP_NullRow: QL(OP_NullRow) {
        QvCur *C = &Cs[op->p1];
        if (!C->kind) { C->kind = QVC_NULLONLY; C->isTable = 1; }
        C->nullRow = op->p2 == 0; qv_stale(C);
        if ((C->kind == QVC_BT || C->kind == QVC_EPH) && C->bc) sqlite3BtreeClearCursor(C->bc);
        QNEXT;
      }
      case OP_IfNullRow: QL(OP_IfNullRow) {
        QvCur *C = &Cs[op->p1];
        if (C->kind && C->nullRow) { qv_out(X, op->p3)->flags = MEM_Null; pc = op->p2; QJUMP; }
        QNEXT;
      }
      case OP_Rewind: QL(OP_Rewind) case OP_Sort: QL(OP_Sort) case OP_SorterSort: QL(OP_SorterSort) {
        QvCur *C = &Cs[op->p1];
        if (C->kind == QVC_SORT) {
          if (!qv_sort(X, C->srt)) return 0;
          C->srt->pos = 0; res = C->srt->n == 0;
        } else {
          if (sqlite3BtreeFirst(C->bc, &res) != SQLITE_OK) { qv_why = "rewind"; return 0; }
          C->deferred = 0;
        }
        qv_stale(C); C->nullRow = (u8)res;
        if (op->p2 > 0 && res) { pc = op->p2; QJUMP; }
        QNEXT;
      }
      case OP_Last: QL(OP_Last) {
        QvCur *C = &Cs[op->p1];
        if (C->kind == QVC_SORT) { qv_why = "last on sorter"; return 0; }
        if (sqlite3BtreeLast(C->bc, &res) != SQLITE_OK) { qv_why = "last"; return 0; }
        C->nullRow = (u8)res; C->deferred = 0; qv_stale(C);
        if (op->p2 > 0 && res) { pc = op->p2; QJUMP; }
        QNEXT;
      }
      case OP_IfEmpty: QL(OP_IfEmpty) {
        QvCur *C = &Cs[op->p1];
        if (sqlite3BtreeIsEmpty(C->bc, &res) != SQLITE_OK) { qv_why = "ifempty"; return 0; }
        if (res) { pc = op->p2; QJUMP; }
        QNEXT;
      }
      case OP_Next: QL(OP_Next) case OP_Prev: QL(OP_Prev) {
        QvCur *C = &Cs[op->p1];
        rc = op->opcode == OP_Next ? sqlite3BtreeNext(C->bc, op->p3) : sqlite3BtreePrevious(C->bc, op->p3);
        qv_stale(C);
        if (rc == SQLITE_OK) { C->nullRow = 0; pc = op->p2; QJUMP; }
        if (rc != SQLITE_DONE) { qv_why = "next"; return 0; }
        C->nullRow = 1;
        QNEXT;
      }
      case OP_SorterNext: QL(OP_SorterNext) {
        QvCur *C = &Cs[op->p1]; qv_stale(C);
        if (++C->srt->pos < C->srt->n) { C->nullRow = 0; pc = op->p2; QJUMP; }
        C->nullRow = 1;
        QNEXT;
      }
      case OP_SorterInsert: QL(OP_SorterInsert) {
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
        if (!qv_decode(rec, (u32)x->n, S->nk, &S->key[(size_t)S->n * S->nk])) { qv_why = "sorter key"; return 0; }
        S->rec[S->n] = rec; S->len[S->n] = (u32)x->n; S->n++;
        QNEXT;
      }
      case OP_SorterData: QL(OP_SorterData) {
        QvCur *C = &Cs[op->p1]; QvSort *S = C->srt;
        if (S->pos >= S->n) { qv_why = "sorter data"; return 0; }
        qv_static(qv_out(X, op->p2), S->rec[S->pos], (int)S->len[S->pos], 0, 0);
        qv_stale(&Cs[op->p3]);
        QNEXT;
      }
      case OP_SorterCompare: QL(OP_SorterCompare) {
        QvCur *C = &Cs[op->p1]; QvSort *S = C->srt; Mem *x = &R[op->p3]; int nk = op->p4.i;
        if (S->pos >= S->n || !(x->flags & MEM_Blob)) { qv_why = "sorter compare"; return 0; }
        UnpackedRecord *u = sqlite3VdbeAllocUnpackedRecord(C->ki); if (!u) return 0;
        u->nField = (u16)nk; sqlite3VdbeRecordUnpack((int)S->len[S->pos], S->rec[S->pos], u);
        res = 0; for (int i = 0; i < nk && !res; i++) if (u->aMem[i].flags & MEM_Null) res = -1;
        if (!res) res = sqlite3VdbeRecordCompare(x->n, x->z, u);
        sqlite3DbFree(X->db, u);
        if (res) { pc = op->p2; QJUMP; }
        QNEXT;
      }
      case OP_Sequence: QL(OP_Sequence) qv_int(qv_out(X, op->p2), Cs[op->p1].seqCount++); QNEXT;
      case OP_SequenceTest: QL(OP_SequenceTest) if ((Cs[op->p1].seqCount++) == 0) { pc = op->p2; QJUMP; } QNEXT;
      case OP_SeekLT: QL(OP_SeekLT) case OP_SeekLE: QL(OP_SeekLE) case OP_SeekGE: QL(OP_SeekGE) case OP_SeekGT: QL(OP_SeekGT) {
        QvCur *C = &Cs[op->p1]; int oc = op->opcode, eqOnly = 0;
        C->nullRow = 0; C->deferred = 0; qv_stale(C);
        if (C->isTable) {
          Mem *pIn3 = &R[op->p3]; u16 flags3 = pIn3->flags, newType; i64 iKey;
          if ((flags3 & (MEM_Int | MEM_Real | MEM_IntReal | MEM_Str)) == MEM_Str) applyNumericAffinity(pIn3, 0);
          iKey = sqlite3VdbeIntValue(pIn3); newType = pIn3->flags; pIn3->flags = flags3;
          if ((newType & (MEM_Int | MEM_IntReal)) == 0) {
            if ((newType & MEM_Real) == 0) {
              if ((newType & MEM_Null) || oc >= OP_SeekGE) { pc = op->p2; QJUMP; }
              if (sqlite3BtreeLast(C->bc, &res) != SQLITE_OK) { qv_why = "seek"; return 0; }
              goto seek_not_found;
            }
            int c = sqlite3IntFloatCompare(iKey, pIn3->u.r);
            if (c > 0) { if ((oc & 0x0001) == (OP_SeekGT & 0x0001)) oc--; }
            else if (c < 0) { if ((oc & 0x0001) == (OP_SeekLT & 0x0001)) oc++; }
          }
          if (sqlite3BtreeTableMoveto(C->bc, (u64)iKey, 0, &res) != SQLITE_OK) { qv_why = "seek"; return 0; }
          C->movetoTarget = iKey;
        } else {
          eqOnly = C->eqOnly;
          UnpackedRecord r; memset(&r, 0, sizeof r);
          r.pKeyInfo = C->ki; r.nField = (u16)op->p4.i; r.default_rc = ((1 & (oc - OP_SeekLT)) ? -1 : +1); r.aMem = &R[op->p3];
          if (sqlite3BtreeIndexMoveto(C->bc, &r, &res) != SQLITE_OK) { qv_why = "seek"; return 0; }
          if (eqOnly && !r.eqSeen) goto seek_not_found;
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
        if (res) { pc = op->p2; QJUMP; }
        if (eqOnly) pc++;   /* skip the IdxGT / IdxLT that follows */
        QNEXT;
      }
      case OP_SeekRowid: QL(OP_SeekRowid) case OP_NotExists: QL(OP_NotExists) {
        QvCur *C = &Cs[op->p1]; Mem *pIn3 = &R[op->p3]; i64 iKey;
        if (op->opcode == OP_SeekRowid && !(pIn3->flags & (MEM_Int | MEM_IntReal))) {
          Mem x = pIn3[0];
          if (x.flags & MEM_Str) applyNumericAffinity(&x, 1);
          if (x.flags & MEM_Int) iKey = x.u.i;
          else if (!(x.flags & MEM_Real) || x.u.r < -9223372036854775808.0 || x.u.r > 9223372036854774784.0 || (double)(iKey = sqlite3RealToI64(x.u.r)) != x.u.r) { pc = op->p2; QJUMP; }
        } else iKey = pIn3->u.i;
        if (sqlite3BtreeTableMoveto(C->bc, iKey, 0, &res) != SQLITE_OK) { qv_why = "seekrowid"; return 0; }
        C->movetoTarget = iKey; C->nullRow = 0; qv_stale(C); C->deferred = 0; C->seekResult = res;
        if (res) { if (!op->p2) { qv_why = "corrupt"; return 0; } pc = op->p2; QJUMP; }
        QNEXT;
      }
      case OP_IdxLE: QL(OP_IdxLE) case OP_IdxGT: QL(OP_IdxGT) case OP_IdxLT: QL(OP_IdxLT) case OP_IdxGE: QL(OP_IdxGE) {
        QvCur *C = &Cs[op->p1]; UnpackedRecord r; memset(&r, 0, sizeof r);
        r.pKeyInfo = C->ki; r.nField = (u16)op->p4.i; r.default_rc = op->opcode < OP_IdxLT ? -1 : 0; r.aMem = &R[op->p3];
        u32 sz = sqlite3BtreePayloadSize(C->bc), amt; const u8 *rec = sqlite3BtreePayloadFetch(C->bc, &amt);
        if (amt < sz) {   /* an overflow record, copied: the generic comparison (the specialised ones may read past it) */
          u8 *buf = qv_alloc(&X->A, sz + 1); if (!buf || sqlite3BtreePayload(C->bc, 0, sz, buf) != SQLITE_OK) { qv_why = "idx payload"; return 0; }
          res = sqlite3VdbeRecordCompareWithSkip((int)sz, buf, &r, 0);
        } else res = sqlite3VdbeFindCompare(&r)((int)sz, rec, &r);   /* the comparison IndexMoveto would use (an int key: vdbeRecordCompareInt); in-page records have the padding it reads into */
        if (r.errCode) { qv_why = "idx compare"; return 0; }
        if ((op->opcode & 1) == (OP_IdxLT & 1)) res = -res; else res++;
        if (res > 0) { pc = op->p2; QJUMP; }
        QNEXT;
      }
      case OP_DeferredSeek: QL(OP_DeferredSeek) case OP_IdxRowid: QL(OP_IdxRowid) {
        QvCur *C = &Cs[op->p1];
        if (C->kind == QVC_BT && sqlite3BtreeCursorHasMoved(C->bc)) { int d = 0; if (sqlite3BtreeCursorRestore(C->bc, &d) != SQLITE_OK) return 0; if (d) C->nullRow = 1; }
        if (!C->nullRow) {
          i64 rowid = 0;
          if (sqlite3VdbeIdxRowid(X->db, C->bc, &rowid) != SQLITE_OK) { qv_why = "idxrowid"; return 0; }
          if (op->opcode == OP_DeferredSeek) {
            QvCur *T = &Cs[op->p3];
            T->nullRow = 0; T->movetoTarget = rowid; T->deferred = 1; qv_stale(T);
            T->altMap = op->p4type == P4_INTARRAY ? (const int *)op->p4.ai : 0; T->alt = C;
          } else qv_int(qv_out(X, op->p2), rowid);
        } else if (op->opcode == OP_IdxRowid) qv_out(X, op->p2)->flags = MEM_Null;
        QNEXT;
      }
      case OP_FinishSeek: QL(OP_FinishSeek) { QvCur *C = &Cs[op->p1]; if (C->deferred && !qv_row(X, C)) return 0; QNEXT; }
      case OP_Rowid: QL(OP_Rowid) {
        QvCur *C = &Cs[op->p1]; Mem *o = qv_out(X, op->p2);
        if (C->nullRow) { o->flags = MEM_Null; QNEXT; }
        if (C->deferred) { qv_int(o, C->movetoTarget); QNEXT; }
        if (C->kind != QVC_BT && C->kind != QVC_EPH) { qv_why = "rowid cursor"; return 0; }
        if (sqlite3BtreeCursorHasMoved(C->bc)) { int d = 0; if (sqlite3BtreeCursorRestore(C->bc, &d) != SQLITE_OK) return 0; if (d) { C->nullRow = 1; o->flags = MEM_Null; QNEXT; } }
        qv_int(o, sqlite3BtreeIntegerKey(C->bc));
        QNEXT;
      }
      case OP_Column: QL(OP_Column) {
        QvCur *C = &Cs[op->p1];
        if (!C->kind) { qv_why = "column cursor"; return 0; }
        Mem *o = qv_out(X, op->p3);
        if (C->kind == QVC_PSEUDO && C->pseudoReg == op->p3) { qv_why = "column into its record"; return 0; }
        if (!qv_column(X, C, op->p2, op, o)) return 0;
        QNEXT;
      }
      case OP_RowData: QL(OP_RowData) {
        QvCur *C = &Cs[op->p1];
        if (!qv_row(X, C)) return 0;
        u8 *d = qv_alloc(&X->A, C->payload + 1); if (!d) { qv_why = "arena"; return 0; }
        memcpy(d, C->row, C->payload);
        qv_static(qv_out(X, op->p2), d, (int)C->payload, 0, 0);
        QNEXT;
      }
      case OP_MakeRecord: QL(OP_MakeRecord) {
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
        QNEXT;
      }
      case OP_IdxInsert: QL(OP_IdxInsert) {
        QvCur *C = &Cs[op->p1]; Mem *k = &R[op->p2];
        if (C->kind != QVC_EPH || !(k->flags & MEM_Blob) || (k->flags & MEM_Zero)) { qv_why = "idxinsert"; return 0; }
        BtreePayload x; memset(&x, 0, sizeof x); x.pKey = k->z; x.nKey = k->n;
        rc = sqlite3BtreeInsert(C->bc, &x, op->p5 & (OPFLAG_APPEND | OPFLAG_SAVEPOSITION), (op->p5 & OPFLAG_USESEEKRESULT) ? C->seekResult : 0);
        qv_stale_eph(X);
        if (rc) { qv_why = "idxinsert"; return 0; }
        QNEXT;
      }
      case OP_Insert: QL(OP_Insert) {
        QvCur *C = &Cs[op->p1]; Mem *d = &R[op->p2], *k = &R[op->p3];
        if (C->kind != QVC_EPH || !(k->flags & MEM_Int) || (!(d->flags & MEM_Blob) && !qv_isnull(d)) || (d->flags & MEM_Zero)) { qv_why = "insert"; return 0; }
        BtreePayload x; memset(&x, 0, sizeof x); x.nKey = k->u.i; x.pData = qv_isnull(d) ? 0 : d->z; x.nData = qv_isnull(d) ? 0 : d->n;
        rc = sqlite3BtreeInsert(C->bc, &x, op->p5 & (OPFLAG_APPEND | OPFLAG_SAVEPOSITION), (op->p5 & OPFLAG_USESEEKRESULT) ? C->seekResult : 0);
        C->deferred = 0; qv_stale_eph(X);
        if (rc) { qv_why = "insert"; return 0; }
        QNEXT;
      }
      case OP_NewRowid: QL(OP_NewRowid) {
        QvCur *C = &Cs[op->p1]; i64 nv = 1;
        if (C->kind != QVC_EPH) { qv_why = "newrowid"; return 0; }
        if (sqlite3BtreeLast(C->bc, &res) != SQLITE_OK) { qv_why = "newrowid"; return 0; }
        if (!res) { nv = sqlite3BtreeIntegerKey(C->bc); if (nv >= LARGEST_INT64) { qv_why = "rowid range"; return 0; } nv++; }
        qv_int(qv_out(X, op->p2), nv);
        QNEXT;
      }
      case OP_Delete: QL(OP_Delete) {
        QvCur *C = &Cs[op->p1];
        if (C->kind != QVC_EPH) { qv_why = "delete"; return 0; }
        rc = sqlite3BtreeDelete(C->bc, op->p5); qv_stale_eph(X); C->seekResult = 0;
        if (rc) { qv_why = "delete"; return 0; }
        QNEXT;
      }
      case OP_ResetSorter: QL(OP_ResetSorter) {
        QvCur *C = &Cs[op->p1];
        if (C->kind == QVC_SORT) { C->srt->n = 0; C->srt->pos = 0; }
        else if (C->kind == QVC_EPH) { if (sqlite3BtreeClearTableOfCursor(C->bc) != SQLITE_OK) { qv_why = "reset"; return 0; } qv_stale_eph(X); }
        else { qv_why = "reset cursor"; return 0; }
        qv_stale(C);
        QNEXT;
      }
      case OP_IfNoHope: QL(OP_IfNoHope) if (Cs[op->p1].seekHit >= op->p4.i) QNEXT; /* fall through */
      case OP_NoConflict: QL(OP_NoConflict) case OP_NotFound: QL(OP_NotFound) case OP_Found: QL(OP_Found) {
        QvCur *C = &Cs[op->p1];
        if (!qv_found(X, C, op)) return 0;
        int exists = C->seekResult == 0;
        C->nullRow = (u8)!exists; C->deferred = 0; qv_stale(C);
        if (op->opcode == OP_Found) { if (exists) { pc = op->p2; QJUMP; } }
        else {
          if (!exists) { pc = op->p2; QJUMP; }
          if (op->opcode == OP_NoConflict) {
            int jn = 0; for (int i = 0; i < op->p4.i; i++) if (qv_isnull(&R[op->p3 + i])) jn = 1;
            if (jn) { pc = op->p2; QJUMP; }
          }
          if (op->opcode == OP_IfNoHope) C->seekHit = op->p4.i;
        }
        QNEXT;
      }
      case OP_SeekHit: QL(OP_SeekHit) {
        QvCur *C = &Cs[op->p1];
        if (C->seekHit < op->p2) C->seekHit = op->p2; else if (C->seekHit > op->p3) C->seekHit = op->p3;
        QNEXT;
      }
      case OP_Count: QL(OP_Count) {
        QvCur *C = &Cs[op->p1]; i64 n = 0;
        if (op->p3) n = sqlite3BtreeRowCountEst(C->bc);
        else if (sqlite3BtreeCount(X->db, C->bc, &n) != SQLITE_OK) { qv_why = "count"; return 0; }
        qv_int(qv_out(X, op->p2), n);
        QNEXT;
      }
      default: QL(default) qv_why = sqlite3OpcodeName(op->opcode); return 0;
    }
  qv_next: QV_UNUSED_LABEL;
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
  QvX *X = &qv_x; QvArena A = X->A; DbPage **pins = X->pins; int cpin = X->cpin; QcVal *out = X->out; size_t cout = X->cout;
  memset(X, 0, sizeof *X);
  X->A = A; X->pins = pins; X->cpin = cpin; X->out = out; X->cout = cout;
  X->P = P; X->v = v; X->db = db; X->O = cb ? 0 : ctx; qv_why = "";
  X->r = P->r; X->c = P->c; X->once = P->once; X->octx = P->octx;
  int st = QC_FALLBACK;
  memset(X->once, 0, (size_t)(P->nOp / 8 + 1));
  memset(P->cnt, 0, sizeof(i64) * (size_t)(P->nMem + 1));
  if (!qv_run(X)) { qc_why = *qv_why ? qv_why : "v run"; goto out; }
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
  return st;
}
