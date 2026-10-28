/* qc.c: a runtime query compiler for SQLite prepared statements. #include after sqlite3.c (SQLite internals).
**
**   int sqlite3_qc(sqlite3_stmt *)          lift the statement's VDBE program into a plan; 1 = compiled, 0 = not this class
**   int sqlite3_qc_exec(stmt, cb, ctx)      run the plan: all rows at once, zero-copy (pointers into the database pages,
**                                           valid during the callback). QC_FALLBACK = run the statement normally instead
**
** The lifter reads the bytecode SQLite's planner produced and recognises one class of programs, checking every operand
** that matters and refusing anything else:
**   driver:   an index scan with a constant LIMIT (Rewind/Next on an index cursor, DecrJumpZero), or a rowid lookup on a
**             bound parameter (Variable + SeekRowid)
**   row:      the table row behind the driver (DeferredSeek + IdxRowid, or the SeekRowid itself)
**   joins:    inner joins by rowid on a column of that row (SeekRowid, a miss skips the row)
**   scalars:  correlated count(*) subqueries over an index equality on the row's rowid (BeginSubrtn ... Return)
**   output:   ResultRow of rowids, columns and counts
** The plan then runs a cheaper program with the same result:
**   - the driver's rows are collected first, then the table rows are fetched (stepping back one row when rowids
**     descend by one), keeping their pages pinned;
**   - each join is one batched B-tree descent for all rows, prefetching child pages level by level;
**   - each count is one range walk of the index over [min, max] of the keys (per-key seeks if the range is wide);
**   - values are decoded straight from the records, never through Mem.
** Every execution reads the live tables under the statement's transaction (no state is kept between executions).
** Anything unexpected at run time (a NULL or non-integer join key, a missing row, an overflow record, a value whose type
** the lifted program would have converted) returns QC_FALLBACK before any row is handed out, and the caller steps the
** statement through the VDBE, which produces whatever SQLite produces (including errors). */

#define QC_FALLBACK (-1)
static const char *qc_why = "";   /* the last fallback's reason (tests) */
#define QC_FB(w) (qc_why = (w), QC_FALLBACK)
/* QC_STATS=1: process-wide counts, printed at exit or by sqlite3_qc_stats(): executions by tier, fallbacks and failed
   lifts by reason, the type-feedback masks of Column and comparison opcodes (once per plan, when its feedback runs
   are over), region nodes widened, plan cache outcomes. Off, they cost one test per execution */
typedef struct QcWhy { const char *why; unsigned long long n; } QcWhy;
static struct QcStats {
  int on; unsigned long long exec[4], ok, lift, liftOk, relift, reliftFail, widen, mask[2][32];
  unsigned long long sample, cheap, keep, park, unpark;
  QcWhy fb[64], lf[64];
} qcs = { -1 };
#define QC_ST (qcs.on > 0)
static void qc_st_why(QcWhy *w, const char *why) {
  int i = 0; while (i < 63 && w[i].why && w[i].why != why && strcmp(w[i].why, why)) i++;
  if (!w[i].why) w[i].why = why;
  w[i].n++;
}
/* a general or qvm plan measured against the interpreter (qc_adapt): executions through it, its state (learning,
   kept, parked), the execution at which that next changes, how often it was parked (R) and kept (K), the samples (µs) */
typedef struct QcAdapt { unsigned n, next; unsigned char st, R, K, nq, ni; double tq[4], ti[4]; } QcAdapt;
#define QC_STR2(x) #x
#define QC_STR(x) QC_STR2(x)
#define QC_MAXROWS 64
#define QC_MAXOUT 16
#define QC_MAXJOIN 4
#define QC_MAXCNT 4
#define QC_MAXCOL 16
#define QC_RANGE_MAX 1024

typedef struct QcVal { union { i64 i; double r; const u8 *z; }; int n, type; } QcVal;   /* 16 bytes; type: SQLITE_INTEGER ... SQLITE_NULL */
typedef int (*qc_row_cb)(void *ctx, int nrow, int ncol, const QcVal *vals);
/* sqlite3_qc_exec(stmt, 0, &out): the body. param: the integer parameters ?1.. as plain values (a compiled query is
   called like a function), or 0 to use the statement's bindings */
typedef struct QcOut { char *buf; size_t cap, n; int rows; const i64 *param; int nparam; } QcOut;

enum { S_NONE, S_INT, S_PARAM, S_NULL, S_ROWID, S_COL, S_COUNT };   /* symbolic register values */
typedef struct { u8 kind; i8 src; i16 col; i64 v; u8 real; } QcSym;   /* src: -1 the driver index, 0 the row, 1+j join j; count c for S_COUNT; real: OP_RealAffinity applied */

/* expected layout of a record source, from the schema: one class per column up to the last one needed */
enum { K_ANY, K_NUL, K_INT, K_TXT, K_REAL };   /* (K_REAL: no generated decoder, qc_decode_fast) */
typedef struct { u8 ok, n; u8 cls[QC_MAXCOL]; } QcShape;
typedef struct QcPlan {
  int kind;                  /* 1: this specialised plan (2: a general plan, qcg.c) */
  int scan;                  /* 1: index scan with limit; 0: rowid = ?param, or = key (param 0: an integer literal) */
  Pgno idxRoot; KeyInfo *idxKi; int limit; int param; i64 key;
  Pgno tabRoot;
  int njoin; struct { Pgno root; int keycol; } join[QC_MAXJOIN];
  int ncnt; struct { Pgno root; KeyInfo *ki; UnpackedRecord *uk; } cnt[QC_MAXCNT];
  int nout; QcSym out[QC_MAXOUT];
  u32 idxCols, tabCols, joinCols[QC_MAXJOIN];   /* bitmasks of the columns each side needs (< QC_MAXCOL) */
  QcShape idxShape, tabShape, joinShape[QC_MAXJOIN];  /* idxShape also covers the index's last field, the rowid */
  int idxRowidField;                                 /* that field's number, or -1 */
  int idxW, tabW, joinW[QC_MAXJOIN];   /* row widths in the run state */
  int (*idxDec)(const u8 *, u32, QcVal *), (*tabDec)(const u8 *, u32, QcVal *), (*joinDec[QC_MAXJOIN])(const u8 *, u32, QcVal *);
  u32 idxCode, tabCode, joinCode[QC_MAXJOIN];   /* the same decoders by signature (qc_dec_run: inlined, no pointer call) */
  int iDb, cookie, gen, nTxn;
  /* cursors kept open between executions while the transaction lasts (closed by sqlite3QcTxnEnd, at its end) */
  Btree *bt; BtCursor *ci, *ct, *cj[QC_MAXJOIN], *cc[QC_MAXCNT]; u8 oi, ot, oj[QC_MAXJOIN], oc[QC_MAXCNT];
  u8 txnChecked;   /* the schema cookie was checked in this transaction (cleared at its end, like the cursors) */
  int slot, act;   /* QC_LIST: index + 1 in qc_plans, in qc_act (0: not in it) */
  u8 lanes;        /* overlapped descents for the rows and counts (QC_LANES=1 at lift time; off by default: RESULTS 5e) */
} QcPlan;
/* the feed's hot loops start on a 64-byte boundary, so code added before them doesn't move their branches: on the Xeon
   (Cascade Lake, JCC erratum microcode) a jump that crosses a 32-byte boundary runs from the legacy decoders, and an
   unrelated change had made the feed 18 % slower in cycles at the same instructions (RESULTS §13) */
#if defined(__GNUC__)
#define QC_HOT __attribute__((aligned(64)))
#else
#define QC_HOT
#endif
#ifndef QC_MAXPLANS   /* live plans per tier, per process (-DQC_MAXPLANS=N); past it a statement is not lifted ("plans") */
#define QC_MAXPLANS 1024
#endif
/* a tier's plans (slot) and, of those, the ones used in the current transaction (act), whose cursors its end closes:
   index + 1 in the array, 0 when not in it; removal moves the last one into the gap */
#define QC_LIST_ADD(a, n, P, f) do { (a)[(n)] = (P); (P)->f = ++(n); } while (0)
#define QC_LIST_DEL(a, n, P, f) do { if ((P)->f) { int k_ = (P)->f - 1; (a)[k_] = (a)[--(n)]; (a)[k_]->f = k_ + 1; (P)->f = 0; } } while (0)
static QcPlan *qc_plans[QC_MAXPLANS], *qc_act[QC_MAXPLANS]; static int qc_nplans, qc_nact;
static void qc_close(BtCursor *c, u8 *open) { if (*open) { sqlite3BtreeCloseCursor(c); *open = 0; } }
static void qc_txn_end(Btree *bt) {
  for (int k = 0; k < qc_nact; ) {
    QcPlan *P = qc_act[k]; if (P->bt != bt) { k++; continue; }
    P->txnChecked = 0;
    qc_close(P->ci, &P->oi); qc_close(P->ct, &P->ot);
    for (int j = 0; j < P->njoin; j++) qc_close(P->cj[j], &P->oj[j]);   /* (only a plan's own joins and counts open theirs) */
    for (int c = 0; c < P->ncnt; c++) qc_close(P->cc[c], &P->oc[c]);
    QC_LIST_DEL(qc_act, qc_nact, P, act);   /* (the last one moves to k) */
  }
}

/* ---------------------------------------------------------------- shapes */
static int qc_class(Table *t, int col) {
  if (col < 0) return col == XN_ROWID ? K_INT : K_ANY;
  if (col == t->iPKey) return K_NUL;   /* an INTEGER PRIMARY KEY is stored as NULL: the value is the rowid */
  if (col >= t->nCol) return K_ANY;
  char a = t->aCol[col].affinity;
  return a == SQLITE_AFF_INTEGER ? K_INT : a == SQLITE_AFF_TEXT ? K_TXT : a == SQLITE_AFF_REAL ? K_REAL : K_ANY;
}
/* the table or index whose b-tree is root; *pIdx is set for an index */
static Table *qc_find(Schema *sc, Pgno root, Index **pIdx) {
  *pIdx = 0;
  for (HashElem *k = sqliteHashFirst(&sc->tblHash); k; k = sqliteHashNext(k)) {
    Table *t = sqliteHashData(k);
    if (IsVirtual(t) || IsView(t)) continue;
    if (t->tnum == root) return HasRowid(t) ? t : 0;
    for (Index *ix = t->pIndex; ix; ix = ix->pNext) if (ix->tnum == root) { *pIdx = ix; return HasRowid(t) ? t : 0; }
  }
  return 0;
}
/* the shape of the columns in mask (+ field extra, if >= 0); ok only if each of them has a definite class */
static void qc_shape(QcShape *sh, Table *t, Index *ix, u32 mask, int extra) {
  memset(sh, 0, sizeof *sh);
  if (!t) return;
  u32 all = mask | (extra >= 0 ? 1u << extra : 0); int n = 0;
  for (int c = 0; c < QC_MAXCOL; c++) if (all & (1u << c)) n = c + 1;
  for (int c = 0; c < n; c++) {
    int col = ix ? (c < ix->nColumn ? ix->aiColumn[c] : XN_EXPR) : c;
    /* in an index the INTEGER PRIMARY KEY column holds the integer itself (only the table row stores it as NULL) */
    sh->cls[c] = (u8)(ix && col >= 0 && col == t->iPKey ? K_INT : qc_class(t, col));
    if ((all & (1u << c)) && sh->cls[c] == K_ANY) return;
    if (sh->cls[c] == K_ANY) return;   /* a column we skip over still needs a known width class */
  }
  sh->n = (u8)n; sh->ok = n > 0;
}

static int (*qc_dec_pick(const QcShape *sh))(const u8 *, u32, QcVal *);   /* qc_dec.h */
static u32 qc_dec_code(const QcShape *sh);

/* ---------------------------------------------------------------- lifter */
static int qc_fail(const char *why, int pc) { qc_why = why; (void)pc; return 0; }
#define QC_REFUSE(why) return qc_fail(why, pc)
#define OPN(k) (&aOp[k])

static int qc_lift_special(Vdbe *v) {
  Op *aOp = v->aOp; int nOp = v->nOp, pc = 0;
  if (v->nMem > 200) return 0;
  QcPlan P; memset(&P, 0, sizeof P); P.kind = 1; P.iDb = -1;
  QcSym reg[201]; memset(reg, 0, sizeof reg);
  struct { Pgno root; KeyInfo *ki; int open; } cur[16]; memset(cur, 0, sizeof cur);
  int curRole[16]; for (int k = 0; k < 16; k++) curRole[k] = -1;   /* -2 driver index, -3 row table, j>=0 join j, 100+c count c */
  /* Init -> Transaction(s) -> Goto back */
  if (aOp[0].opcode != OP_Init) QC_REFUSE("init");
  int t = aOp[0].p2;
  while (t < nOp && aOp[t].opcode == OP_Transaction) {
    Op *o = OPN(t);
    if (o->p2 != 0 || o->p5 != 1 || P.nTxn) QC_REFUSE("transaction");   /* one read transaction, schema checked */
    if (o->p4type != P4_INT32) QC_REFUSE("transaction p4");
    P.iDb = o->p1; P.cookie = o->p3; P.gen = o->p4.i; P.nTxn++; t++;
  }
  if (!P.nTxn || t >= nOp || aOp[t].opcode != OP_Goto || aOp[t].p2 != 1) QC_REFUSE("preamble");
  int endPreamble = aOp[0].p2;
  pc = 1;
  int haltPc = -1, loopHead = -1, limitReg = -1, idxCur = -1, tabCur = -1;
  /* setup: Noop, Integer (limit), Variable, OpenRead */
  for (;; pc++) {
    if (pc >= endPreamble) QC_REFUSE("no body");
    Op *o = OPN(pc);
    if (o->opcode == OP_Noop) continue;
    if (o->opcode == OP_Integer) { if (o->p2 > v->nMem) QC_REFUSE("reg"); reg[o->p2] = (QcSym){S_INT, 0, 0, o->p1}; continue; }
    if (o->opcode == OP_Variable) { if (o->p2 > v->nMem) QC_REFUSE("reg"); reg[o->p2] = (QcSym){S_PARAM, 0, 0, o->p1}; continue; }
    if (o->opcode == OP_OpenRead) {
      if (o->p1 < 0 || o->p1 >= 16 || o->p3 != P.iDb || (o->p5 & ~OPFLAG_SEEKEQ) || (o->p4type != P4_INT32 && o->p4type != P4_KEYINFO)) QC_REFUSE("openread");
      cur[o->p1].root = (Pgno)o->p2; cur[o->p1].ki = o->p4type == P4_KEYINFO ? o->p4.pKeyInfo : 0; cur[o->p1].open = 1; continue;
    }
    break;
  }
  Op *o = OPN(pc);
  if (o->opcode == OP_Rewind) {                 /* index scan driver */
    if (!cur[o->p1].open || !cur[o->p1].ki) QC_REFUSE("rewind");
    P.scan = 1; idxCur = o->p1; haltPc = o->p2; P.idxRoot = cur[idxCur].root; P.idxKi = cur[idxCur].ki; curRole[idxCur] = -2;
    loopHead = ++pc;
    o = OPN(pc);
    /* DeferredSeek P1 = the index cursor, P3 = its table's cursor, no P4 alternate column map */
    if (o->opcode != OP_DeferredSeek || o->p1 != idxCur || o->p3 < 0 || o->p3 >= 16 || !cur[o->p3].open || cur[o->p3].ki || o->p4type != P4_NOTUSED)
      QC_REFUSE("deferredseek");
    tabCur = o->p3; P.tabRoot = cur[tabCur].root; curRole[tabCur] = -3; pc++;
  } else if (o->opcode == OP_SeekRowid) {       /* rowid = ?param driver */
    if (!cur[o->p1].open || cur[o->p1].ki || (reg[o->p3].kind != S_PARAM && reg[o->p3].kind != S_INT)) QC_REFUSE("seekrowid driver");
    P.scan = 0; if (reg[o->p3].kind == S_PARAM) P.param = (int)reg[o->p3].v; else P.key = reg[o->p3].v; tabCur = o->p1; P.tabRoot = cur[tabCur].root; curRole[tabCur] = -3; haltPc = o->p2; pc++;
  } else QC_REFUSE("driver");
  if (haltPc < 0 || haltPc >= nOp || aOp[haltPc].opcode != OP_Halt || aOp[haltPc].p1 != 0 || aOp[haltPc].p2 != 0) QC_REFUSE("halt");
  int nextPc = -1;   /* where a skipped row continues: the Next of the scan, or Halt */
  for (; pc < endPreamble; pc++) {
    o = OPN(pc);
    switch (o->opcode) {
      case OP_Column: {
        if (o->p5 || o->p4type != P4_NOTUSED || o->p3 > v->nMem || o->p2 >= QC_MAXCOL) QC_REFUSE("column");
        int r = curRole[o->p1];
        if (r == -3) { reg[o->p3] = (QcSym){S_COL, 0, (i16)o->p2, 0}; P.tabCols |= 1u << o->p2; }
        else if (r == -2) { reg[o->p3] = (QcSym){S_COL, -1, (i16)o->p2, 0}; P.idxCols |= 1u << o->p2; }   /* a covered column */
        else if (r >= 0 && r < QC_MAXJOIN) { reg[o->p3] = (QcSym){S_COL, (i8)(1 + r), (i16)o->p2, 0}; P.joinCols[r] |= 1u << o->p2; }
        else QC_REFUSE("column cursor");
        break;
      }
      case OP_IdxRowid: case OP_Rowid: {
        int r = curRole[o->p1];
        if (!((o->opcode == OP_IdxRowid && r == -2) || (o->opcode == OP_Rowid && r == -3)) || o->p2 > v->nMem) QC_REFUSE("rowid");
        reg[o->p2] = (QcSym){S_ROWID, 0, 0, 0}; break;
      }
      case OP_SeekRowid: {                     /* inner join by rowid */
        QcSym k = reg[o->p3];
        if (!cur[o->p1].open || cur[o->p1].ki || curRole[o->p1] != -1 || P.njoin >= QC_MAXJOIN || k.kind != S_COL || k.src != 0 || k.real) QC_REFUSE("join");
        if (nextPc < 0) nextPc = o->p2; else if (nextPc != o->p2) QC_REFUSE("join target");
        P.join[P.njoin].root = cur[o->p1].root; P.join[P.njoin].keycol = k.col; curRole[o->p1] = P.njoin++;
        break;
      }
      case OP_BeginSubrtn: {                   /* scalar count(*) over an index equality on the row's rowid */
        int rRet = o->p2, b = pc;
        Op *q = &aOp[b];
        /* the exact shape SQLite emits for (SELECT count(*) FROM t WHERE t.c = outer.rowid) */
        int rRes = q[1].p2;
        if (b + 14 >= nOp) QC_REFUSE("subquery length");
        if (o->p1 != 0) QC_REFUSE("subquery shape 1");
        if (q[1].opcode != OP_Null) QC_REFUSE("subquery shape 2");
        if (q[1].p3 != rRes) QC_REFUSE("subquery shape 3");
        if (q[2].opcode != OP_Integer) QC_REFUSE("subquery shape 4");
        if (q[2].p1 != 1) QC_REFUSE("subquery shape 5");
        if (q[3].opcode != OP_Null) QC_REFUSE("subquery shape 6");
        if (q[3].p2 != q[3].p3) QC_REFUSE("subquery shape 7");
        if (q[4].opcode != OP_OpenRead) QC_REFUSE("subquery shape 8");
        if (q[4].p4type != P4_KEYINFO) QC_REFUSE("subquery shape 9");
        if (q[4].p3 != P.iDb) QC_REFUSE("subquery shape 10");
        if ((q[5].opcode != OP_IdxRowid && q[5].opcode != OP_Rowid)) QC_REFUSE("subquery shape 11");
        if (q[6].opcode != OP_SeekGE) QC_REFUSE("subquery shape 12");
        if (q[6].p1 != q[4].p1) QC_REFUSE("subquery shape 13");
        if (q[6].p3 != q[5].p2) QC_REFUSE("subquery shape 14");
        if (q[6].p4type != P4_INT32) QC_REFUSE("subquery shape 15");
        if (q[6].p4.i != 1) QC_REFUSE("subquery shape 16");
        if (q[7].opcode != OP_IdxGT) QC_REFUSE("subquery shape 17");
        if (q[7].p1 != q[4].p1) QC_REFUSE("subquery shape 18");
        if (q[7].p3 != q[5].p2) QC_REFUSE("subquery shape 19");
        if (q[7].p4.i != 1) QC_REFUSE("subquery shape 20");
        if (q[7].p2 != q[6].p2) QC_REFUSE("subquery shape 21");
        /* AggStep turns itself into AggStep1, with a context in P4, the first time it runs */
        if (!((q[8].opcode == OP_AggStep && q[8].p4type == P4_FUNCDEF) || (q[8].opcode == OP_AggStep1 && q[8].p4type == P4_FUNCCTX)))
          QC_REFUSE("subquery aggstep");
        if (q[8].p1 != 0) QC_REFUSE("subquery shape 24");
        if (q[8].p3 != q[3].p2) QC_REFUSE("subquery shape 25");
        if (q[9].opcode != OP_Next) QC_REFUSE("subquery shape 26");
        if (q[9].p1 != q[4].p1) QC_REFUSE("subquery shape 27");
        if (q[9].p2 != b + 7) QC_REFUSE("subquery shape 28");
        if (q[10].opcode != OP_AggFinal) QC_REFUSE("subquery shape 29");
        if (q[10].p1 != q[3].p2) QC_REFUSE("subquery shape 30");
        if (q[10].p2 != 0) QC_REFUSE("subquery shape 31");
        if (q[6].p2 != b + 10) QC_REFUSE("subquery shape 32");
        if (q[11].opcode != OP_Copy) QC_REFUSE("subquery shape 33");
        if (q[11].p1 != q[3].p2) QC_REFUSE("subquery shape 34");
        if (q[11].p2 != rRes) QC_REFUSE("subquery shape 35");
        if (q[11].p3 != 0) QC_REFUSE("subquery shape 36");
        if (q[12].opcode != OP_DecrJumpZero) QC_REFUSE("subquery shape 37");
        if (q[12].p1 != q[2].p2) QC_REFUSE("subquery shape 38");
        if (q[12].p2 != b + 13) QC_REFUSE("subquery shape 39");
        if (q[13].opcode != OP_Return) QC_REFUSE("subquery shape 40");
        if (q[13].p1 != rRet) QC_REFUSE("subquery shape 41");
        if (q[13].p3 != 1) QC_REFUSE("subquery shape 42");
        if (q[13].p2 != b + 1) QC_REFUSE("subquery shape 43");
        /* AggStep turns into AggStep1 (P4 a context) once it has run */
        FuncDef *f = q[8].opcode == OP_AggStep ? q[8].p4.pFunc : q[8].p4.pCtx->pFunc;
        if (sqlite3StrICmp(f->zName, "count") || f->nArg != 0 || q[8].p5 != 0) QC_REFUSE("not count(*)");
        QcSym key = reg[q[5].p2];
        if ((q[5].opcode == OP_IdxRowid && curRole[q[5].p1] != -2) || (q[5].opcode == OP_Rowid && curRole[q[5].p1] != -3)) QC_REFUSE("subquery key");
        (void)key;
        KeyInfo *ki = q[4].p4.pKeyInfo;
        if (P.ncnt >= QC_MAXCNT || ki->nKeyField < 1 || ki->aSortFlags[0] || (ki->aColl[0] && sqlite3StrICmp(ki->aColl[0]->zName, "BINARY")))
          QC_REFUSE("count index");
        P.cnt[P.ncnt].root = (Pgno)q[4].p2; P.cnt[P.ncnt].ki = ki;
        reg[rRes] = (QcSym){S_COUNT, (i8)P.ncnt, 0, 0}; P.ncnt++;
        pc = b + 13;
        break;
      }
      case OP_Copy: {
        if (o->p3 != 0 || o->p1 > v->nMem || o->p2 > v->nMem) QC_REFUSE("copy");
        reg[o->p2] = reg[o->p1]; break;
      }
      case OP_RealAffinity:   /* a REAL column: an integer stored for it reads as a float (the output stage converts) */
        if (o->p1 > v->nMem || reg[o->p1].kind != S_COL) QC_REFUSE("realaffinity");
        reg[o->p1].real = 1; break;
      case OP_ResultRow: {
        if (o->p2 > QC_MAXOUT) QC_REFUSE("too many columns");
        for (int k = 0; k < o->p2; k++) {
          QcSym s = reg[o->p1 + k];
          if (s.kind != S_ROWID && s.kind != S_COL && s.kind != S_COUNT) QC_REFUSE("output");
          P.out[k] = s;
        }
        P.nout = o->p2;
        /* after the row: scan -> DecrJumpZero limit -> Next idx -> loop; point -> Halt */
        Op *a = OPN(pc + 1);
        if (P.scan) {
          Op *n = OPN(pc + 2);
          if (a->opcode != OP_DecrJumpZero || a->p2 != haltPc || reg[a->p1].kind != S_INT || reg[a->p1].v < 1 || reg[a->p1].v > QC_MAXROWS ||
              n->opcode != OP_Next || n->p1 != idxCur || n->p2 != loopHead || pc + 3 != haltPc || (nextPc >= 0 && nextPc != pc + 2))
            QC_REFUSE("scan tail");
          P.limit = (int)reg[a->p1].v; limitReg = a->p1;
        } else {
          if (pc + 1 != haltPc || (nextPc >= 0 && nextPc != haltPc)) QC_REFUSE("point tail");
          P.limit = 1;
        }
        goto lifted;
      }
      default: QC_REFUSE("opcode");
    }
  }
  QC_REFUSE("no result row");
lifted:
  (void)limitReg;
  for (int j = 0; j < P.njoin; j++) if (P.join[j].keycol >= QC_MAXCOL) QC_REFUSE("key col");
  for (int c = 0; c < P.ncnt; c++) if (!(P.cnt[c].uk = sqlite3VdbeAllocUnpackedRecord(P.cnt[c].ki))) return 0;
  {   /* record shapes for the fast decoders (an unknown layout keeps the generic decoder) */
    Schema *sc = v->db->aDb[P.iDb].pSchema; Index *ix; Table *t;
    P.idxRowidField = -1;
    if (P.scan && (t = qc_find(sc, P.idxRoot, &ix)) && ix && ix->nColumn == ix->nKeyCol + 1 && ix->nColumn <= QC_MAXCOL &&
        ix->aiColumn[ix->nColumn - 1] == XN_ROWID) {
      qc_shape(&P.idxShape, t, ix, P.idxCols, ix->nColumn - 1);
      if (P.idxShape.ok) P.idxRowidField = ix->nColumn - 1;
    }
    if ((t = qc_find(sc, P.tabRoot, &ix)) && !ix) qc_shape(&P.tabShape, t, 0, P.tabCols, -1);
    for (int j = 0; j < P.njoin; j++) if ((t = qc_find(sc, P.join[j].root, &ix)) && !ix) qc_shape(&P.joinShape[j], t, 0, P.joinCols[j], -1);
    /* the unrolled decoder for each shape, where one was generated (up to 4 columns) */
    P.idxDec = P.idxRowidField >= 0 ? qc_dec_pick(&P.idxShape) : 0; P.tabDec = qc_dec_pick(&P.tabShape);
    /* widths: the widest column any decoder writes (generic: the highest needed one; unrolled: the shape's n) */
    #define QC_HI(m) (32 - __builtin_clz((m) | 1))
    P.idxW = QC_HI(P.idxCols); P.tabW = QC_HI(P.tabCols); if (P.tabShape.n > P.tabW) P.tabW = P.tabShape.n;
    for (int j = 0; j < P.njoin; j++) { P.joinW[j] = QC_HI(P.joinCols[j]); if (P.joinShape[j].n > P.joinW[j]) P.joinW[j] = P.joinShape[j].n; }
    for (int j = 0; j < P.njoin; j++) P.joinDec[j] = qc_dec_pick(&P.joinShape[j]);
    P.idxCode = P.idxDec ? qc_dec_code(&P.idxShape) : 0; P.tabCode = P.tabDec ? qc_dec_code(&P.tabShape) : 0;
    for (int j = 0; j < P.njoin; j++) P.joinCode[j] = P.joinDec[j] ? qc_dec_code(&P.joinShape[j]) : 0;
  }
  P.lanes = getenv("QC_LANES") != 0;   /* off: slower on the Xeon hot and cold (RESULTS 5e) */
  if (qc_nplans >= QC_MAXPLANS) return 0;
  QcPlan *pp = sqlite3_malloc(sizeof P); if (!pp) return 0;
  *pp = P; v->pQc = pp; QC_LIST_ADD(qc_plans, qc_nplans, pp, slot);
  return 1;
}

/* ---------------------------------------------------------------- run time: records */
static inline u64 qc_varint(const u8 *p, int *n) {
  if (!(p[0] & 0x80)) { *n = 1; return p[0]; }
  if (!(p[1] & 0x80)) { *n = 2; return ((u64)(p[0] & 0x7f) << 7) | p[1]; }
  u64 x; *n = sqlite3GetVarint(p, &x); return x;
}
static inline __attribute__((always_inline)) u64 qc_be64(const u8 *d) {   /* a record's 8-byte big-endian field */
#if SQLITE_BYTEORDER == 1234
  u64 x; memcpy(&x, d, 8); return __builtin_bswap64(x);
#elif SQLITE_BYTEORDER == 4321
  u64 x; memcpy(&x, d, 8); return x;
#else
  u64 x = 0; for (int k = 0; k < 8; k++) x = (x << 8) | d[k]; return x;
#endif
}
/* field value from serial type t at d; 0 = a type the lifted program would not have handed out as is */
static inline __attribute__((always_inline)) int qc_value(u64 t, const u8 *d, QcVal *o) {
  switch (t) {
    case 0: o->type = SQLITE_NULL; return 1;
    case 1: o->type = SQLITE_INTEGER; o->i = (i8)d[0]; return 1;
    case 2: o->type = SQLITE_INTEGER; o->i = (i16)((d[0] << 8) | d[1]); return 1;
    case 3: o->type = SQLITE_INTEGER; o->i = ((int32_t)((u32)d[0] << 24 | (u32)d[1] << 16 | (u32)d[2] << 8)) >> 8; return 1;
    case 4: o->type = SQLITE_INTEGER; o->i = (int32_t)((u32)d[0] << 24 | (u32)d[1] << 16 | (u32)d[2] << 8 | d[3]); return 1;
    case 5: { u64 x = 0; for (int k = 0; k < 6; k++) x = (x << 8) | d[k]; o->type = SQLITE_INTEGER; o->i = (i64)(x ^ 0x800000000000ull) - (i64)0x800000000000ll; return 1; }
    case 6: o->type = SQLITE_INTEGER; o->i = (i64)qc_be64(d); return 1;
    case 7: { u64 x = qc_be64(d); double r; memcpy(&r, &x, 8);
              if (r != r) { o->type = SQLITE_NULL; return 1; }   /* sqlite3VdbeSerialGet: NaN reads as NULL */
              o->type = SQLITE_FLOAT; o->r = r; return 1; }
    case 8: o->type = SQLITE_INTEGER; o->i = 0; return 1;
    case 9: o->type = SQLITE_INTEGER; o->i = 1; return 1;
    case 10: case 11: return 0;
  }
  o->type = (t & 1) ? SQLITE_TEXT : SQLITE_BLOB; o->z = d; o->n = (int)((t - 12) >> 1); return 1;
}
static const u8 qc_stl[12] = {0, 1, 2, 3, 4, 6, 8, 8, 0, 0, 0, 0};
static inline u32 qc_stlen(u64 t) { return t < 12 ? qc_stl[t] : (u32)((t - 12) >> 1); }
/* decode the columns in mask from a table record (rec, sz all local); missing trailing columns are NULL (no defaults:
   the lifter refused Column with a P4 default). 0 = malformed or an unusable type. OP_Column's corruption checks, so
   a record SQLite calls malformed isn't read here (0: the statement runs in the interpreter, which reports it): a
   header size within the header, every type varint inside it and at most 0xffffffff, and once the header is read to
   its end, the fields ending exactly at the payload's end */
static int qc_decode(const u8 *rec, u32 sz, u32 mask, QcVal *cols) {
  int n; u64 hdr = qc_varint(rec, &n); const u8 *h = rec + n, *he = rec + hdr, *d = rec + hdr, *end = rec + sz;
  if (hdr > sz || (u64)n >= hdr || hdr > 0xffffffffu) return 0;
  for (int c = 0; mask; c++, mask >>= 1) {
    if (h >= he) { if (mask & 1) cols[c].type = SQLITE_NULL; continue; }
    u32 t = *h, len;
    if (t < 0x80) { h++; len = t < 12 ? qc_stl[t] : (t - 12) >> 1; }   /* (a one-byte type: most of them, and every one skipped over) */
    else { u64 w = qc_varint(h, &n); h += n; if (h > he || w > 0xffffffffu) return 0; t = (u32)w; len = qc_stlen(w); }
    if (mask & 1) { if (d + len > end || !qc_value(t, d, &cols[c])) return 0; }
    d += len;
  }
  return h < he ? d <= end : d == end;
}
/* qc_decode for a record of the expected shape: one pass over the header, no per-type dispatch beyond the class.
   0 = not that shape (a different type in some column, a long header, a short record): use qc_decode. The values are
   the ones qc_decode would give for the same record. */
static const u8 qc_iw[10] = {0, 1, 2, 3, 4, 6, 8, 0, 0, 0};
static const u8 qc_ikw[256] = {[1] = 2, [2] = 3, [3] = 4, [4] = 5, [5] = 7, [6] = 9, [8] = 1, [9] = 1};   /* integer serial types: width + 1 */
/* a big-endian integer of serial type t (1-6, 8, 9), inline */
static inline __attribute__((always_inline)) i64 qc_int(u32 t, const u8 *d) {
  switch (t) {
    case 1: return (i8)d[0];
    case 2: return (i16)((d[0] << 8) | d[1]);
    case 3: return ((int32_t)((u32)d[0] << 24 | (u32)d[1] << 16 | (u32)d[2] << 8)) >> 8;
    case 4: return (int32_t)((u32)d[0] << 24 | (u32)d[1] << 16 | (u32)d[2] << 8 | d[3]);
    case 8: return 0;
    case 9: return 1;
    case 5: { u64 x = 0; for (int k = 0; k < 6; k++) x = (x << 8) | d[k]; return (i64)(x ^ 0x800000000000ull) - (i64)0x800000000000ll; }   /* (48-bit sign extension without shifting into the sign bit) */
    default: return (i64)qc_be64(d);
  }
}
static inline __attribute__((always_inline)) int qc_decode_fast(const u8 *rec, u32 sz, const QcShape *sh, u32 mask, QcVal *cols) {
  u32 hl = rec[0]; if (hl >= 0x80 || hl > sz) return 0;
  const u8 *h = rec + 1, *he = rec + hl, *d = rec + hl;
  for (int c = 0; c < sh->n; c++, mask >>= 1) {
    if (h >= he) return 0;
    u32 t = *h++;
    switch (sh->cls[c]) {
      case K_NUL:
        if (t) return 0;
        if (mask & 1) cols[c].type = SQLITE_NULL;
        break;
      case K_INT:
        if (t == 0 || t == 7 || t > 9) return 0;
        if (mask & 1) { cols[c].type = SQLITE_INTEGER; cols[c].i = qc_int(t, d); }
        d += qc_iw[t];
        break;
      case K_REAL:   /* a float, or an integer stored for an integral value */
        if (t == 7) {
          if (mask & 1) { u64 x = qc_be64(d); double r; memcpy(&r, &x, 8); if (r != r) return 0; cols[c].type = SQLITE_FLOAT; cols[c].r = r; }   /* (NaN: qc_decode's NULL) */
          d += 8;
        } else {
          if (t == 0 || t > 9) return 0;
          if (mask & 1) { cols[c].type = SQLITE_INTEGER; cols[c].i = qc_int(t, d); }
          d += qc_iw[t];
        }
        break;
      default: {   /* K_TXT */
        if (t >= 0x80) { if (h >= he || (*h & 0x80)) return 0; t = ((t & 0x7f) << 7) | *h++; }
        if (t < 13 || !(t & 1)) return 0;
        u32 len = (t - 13) >> 1;
        if (mask & 1) { cols[c].type = SQLITE_TEXT; cols[c].z = d; cols[c].n = (int)len; }
        d += len;
      }
    }
  }
  return h < he ? d <= rec + sz : d == rec + sz;   /* (qc_decode's end check: a header read to its end accounts for the payload exactly) */
}

/* straight-line decoders per shape signature (qc/gen_decoders.py, generated at build time) */
#include "qc_dec.h"

/* the first field of an index cell, compared as SQLite compares it with an integer key: kind 1 = numerically an integer
   (*key; integral REALs compare equal to integers), 0 = never equal but sorts among the numbers (NULL, non-integral
   REAL: *key = floor for the range test, or INT64_MIN for NULL), 2 = sorts after every number (TEXT/BLOB), -1 = malformed */
/* the first field of the index cell at c, which lies in the page's cell content area (ce: the end of its usable
   part); see qc_idxkey */
static inline __attribute__((always_inline)) int qc_idxkey_at(const MemPage *pg, const u8 *c, const u8 *ce, i64 *key) {
  if (!pg->leaf) { c += 4; if (c + 3 > ce) return -1; }   /* (a leaf cell's first 4 bytes are inside: the caller checked c <= ce - 4) */
  /* the common leaf cell of an integer index: [size < 128][header size < 128][int type][...][key] */
  u32 sz0 = c[0], hl = c[1], w = qc_ikw[c[2]];   /* w: an integer serial type's width + 1, 0 for any other type */
  if (__builtin_expect(((sz0 | hl) & 0x80) == 0 && w && hl >= 2 && hl + w - 1 <= sz0 && c + 1 + sz0 <= ce, 1)) {
    *key = qc_int(c[2], c + 1 + hl); return 1;
  }
  int n; u64 sz = qc_varint(c, &n); c += n;
  if (sz > pg->maxLocal || c + sz > ce) return -1;
  u64 hdr = qc_varint(c, &n); u64 t = qc_varint(c + n, &n);
  if (hdr > sz) return -1;
  if (t == 0) { *key = INT64_MIN; return 0; }
  if (t >= 12) return 2;
  if (t == 10 || t == 11) return -1;
  QcVal v; qc_value(t, c + hdr, &v);
  if (v.type == SQLITE_INTEGER) { *key = v.i; return 1; }
  if (v.type == SQLITE_NULL) { *key = INT64_MIN; return 0; }
  double r = v.r;
  if (r >= 9223372036854775808.0) { *key = INT64_MAX; return 0; }
  if (r < -9223372036854775808.0) { *key = INT64_MIN; return 0; }
  i64 f = (i64)r; if ((double)f > r) f--;
  *key = f; return (double)f == r ? 1 : 0;
}
/* the cell must lie in the page's cell content area (btreeCellSizeCheck's bounds); a corrupt page goes to SQLite's
   own code, which reports it */
static inline __attribute__((always_inline)) const u8 *qc_cell_lo(const MemPage *pg) { return pg->aCellIdx + 2 * pg->nCell; }
static inline __attribute__((always_inline)) const u8 *qc_cell_end(const MemPage *pg) { return pg->aData + pg->pBt->usableSize; }   /* (not aDataEnd: reserved bytes are no cell's) */
static inline __attribute__((always_inline)) int qc_idxkey(const MemPage *pg, int ix, i64 *key) {
  const u8 *c = pg->aData + get2byteAligned(&pg->aCellIdx[2 * ix]), *ce = qc_cell_end(pg);
  if (c < qc_cell_lo(pg) || c > ce - 4) return -1;
  return qc_idxkey_at(pg, c, ce, key);
}

/* ---------------------------------------------------------------- run time: batched rowid seeks (from explore/sqlite-simd) */
typedef struct { MemPage *leaf; int ix; int found; } qc_res;
#define QC_PF(p) __builtin_prefetch((const void *)(p), 0, 3)
/* sqlite3VarintValue's own algorithm, inlined here: a call from qc as well made gcc stop inlining SQLite's copy into
   sqlite3BtreeTableMoveto, its one caller (+90 instructions per point lookup through SQLite's seek) */
static inline __attribute__((always_inline)) i64 qc_varint_value(const u8 *p) {
  u64 k = p[0]; u8 x;
  if (k < 0x80) return (i64)k;
  k = (k << 7) ^ (x = *++p);
  if (x < 0x80) return (i64)(k ^ 0x4000);
  k = (k << 7) ^ (x = *++p);
  if (x < 0x80) return (i64)(k ^ 0x204000);
  k = (k << 7) ^ 0x10204000 ^ (x = *++p);
  for (int j = 0; j < 4 && x >= 0x80; j++) k = (k << 7) ^ 0x4000 ^ (x = *++p);
  if (x >= 0x80) k = (k << 8) ^ 0x8000 ^ (*++p);
  return (i64)k;
}
static inline i64 qc_cellkey(MemPage *pg, int i) {
  u8 *c = findCellPastPtr(pg, i);
  if (pg->intKeyLeaf) while (0x80 <= *(c++)) {}
  return qc_varint_value(c);
}
/* first cell with key >= k (nCell if none). Interpolation first: dense rowids put k almost where a linear guess says,
   so 6-10 binary-search probes become 1-3 (from engine.c's ms_lower_bound). */
static inline int qc_lower_bound(MemPage *pg, i64 k) {
  int n = pg->nCell, lo = 0, len = n;
  if (n >= 8) {
    i64 k0 = qc_cellkey(pg, 0), kn = qc_cellkey(pg, n - 1);
    if (k <= k0) return 0;
    if (k > kn) return n;
    int g = (int)((double)(k - k0) * (n - 1) / (double)(kn - k0));
    if (g < 1) g = 1; if (g > n - 1) g = n - 1;
    if (qc_cellkey(pg, g) >= k) {
      for (int s = 0; s < 4; s++) { if (qc_cellkey(pg, g - 1) < k) return g; g--; }
      lo = 1; len = g;
    } else {
      for (int s = 0; s < 4; s++) { g++; if (qc_cellkey(pg, g) >= k) return g; }
      lo = g + 1; len = n - 1 - g;
    }
  }
  while (len > 0) { int h = len >> 1; if (qc_cellkey(pg, lo + h) < k) { lo += h + 1; len -= h + 1; } else len = h; }
  return lo;
}
static inline PgHdr1 **qc_bucket(BtShared *bt, Pgno pg) { PCache1 *pc = (PCache1 *)bt->pPager->pPCache->pCache; return &pc->apHash[pg % pc->nHash]; }
QC_HOT static int qc_seek_batch(Btree *p, Pgno root, const i64 *keys_in, int n, qc_res *r) {
  BtShared *bt = p->pBt; MemPage *cur[QC_MAXROWS]; Pgno ch[QC_MAXROWS]; int rc, ord[QC_MAXROWS]; i64 keys[QC_MAXROWS];
  int pcache = bt->pPager->xGet == getPageNormal;   /* the prefetch peeks at pcache1's hash: not with mmap */
  for (int i = 0; i < n; i++) { int j = i; while (j > 0 && keys_in[ord[j - 1]] > keys_in[i]) { ord[j] = ord[j - 1]; j--; } ord[j] = i; }
  for (int i = 0; i < n; i++) keys[i] = keys_in[ord[i]];
  if ((rc = getAndInitPage(bt, root, &cur[0], PAGER_GET_READONLY))) return rc;
  if (cur[0]->nCell == 0 && cur[0]->leaf) { for (int i = 0; i < n; i++) { r[i].leaf = 0; r[i].found = 0; } releasePage(cur[0]); return SQLITE_OK; }
  for (int i = 1; i < n; i++) { sqlite3PagerRef(cur[0]->pDbPage); cur[i] = cur[0]; }
  for (int depth = 0; !cur[0]->leaf; depth++) {
    if (depth > 20) { rc = SQLITE_CORRUPT_BKPT; goto fail; }
    for (int i = 0; i < n; i++) {
      MemPage *pg = cur[i]; int lb = qc_lower_bound(pg, keys[i]);
      ch[i] = lb >= pg->nCell ? get4byte(&pg->aData[pg->hdrOffset + 8]) : get4byte(findCell(pg, lb));
      if (pcache && (!i || ch[i] != ch[i - 1])) QC_PF(qc_bucket(bt, ch[i]));
    }
    if (pcache) for (int i = 0; i < n; i++) {
      if (i && ch[i] == ch[i - 1]) continue;
      PgHdr1 *h = *qc_bucket(bt, ch[i]); while (h && h->iKey != ch[i]) h = h->pNext;
      if (h) { u8 *d = h->page.pBuf; QC_PF(d); QC_PF(d + 64); QC_PF(h->page.pExtra); }
    }
    for (int i = 0; i < n; i++) { releasePage(cur[i]); cur[i] = 0; }
    for (int i = 0; i < n; i++) {
      if (i && ch[i] == ch[i - 1]) { sqlite3PagerRef(cur[i - 1]->pDbPage); cur[i] = cur[i - 1]; continue; }
      if ((rc = getAndInitPage(bt, ch[i], &cur[i], PAGER_GET_READONLY))) goto fail;
      if (cur[i]->nCell < 1 || cur[i]->intKey != 1 || cur[i]->leaf != cur[0]->leaf) { rc = SQLITE_CORRUPT_PGNO(ch[i]); goto fail; }
    }
  }
  for (int i = 0; i < n; i++) {
    MemPage *pg = cur[i]; int lb = qc_lower_bound(pg, keys[i]), found = 0;
    if (lb < pg->nCell) found = qc_cellkey(pg, lb) == keys[i];
    qc_res *o = &r[ord[i]]; o->leaf = pg; o->ix = lb; o->found = found;
  }
  return SQLITE_OK;
fail:
  for (int i = 0; i < n; i++) if (cur[i]) releasePage(cur[i]);
  return rc;
}

/* ---------------------------------------------------------------- run time: the plan */
/* the plan's cursor for root: kept open (and positioned) from the last execution in this transaction, or opened now */
static BtCursor *qc_cursor(QcPlan *P, Btree *bt, Pgno root, KeyInfo *ki, BtCursor **slot, u8 *open) {
  if (*open) return *slot;
  if (!*slot && !(*slot = sqlite3MallocZero(sqlite3BtreeCursorSize()))) return 0;
  sqlite3BtreeCursorZero(*slot);
  if (sqlite3BtreeCursor(bt, root, 0, ki, *slot) != SQLITE_OK) return 0;
  *open = 1; P->bt = bt; return *slot;
}
typedef struct QcRun {
  DbPage *pins[QC_MAXROWS]; int npin;
  qc_res jr[QC_MAXJOIN][QC_MAXROWS]; int jn[QC_MAXJOIN];
  u32 counts[QC_RANGE_MAX];
  /* decoded values: here rather than on the stack (~200 KB: stack-clash probing alone cost ~0.3 µs per call on the Xeon) */
  /* rows of each source at the plan's own width (its widest decoded column), so a request touches few cache lines */
  QcVal ivf[QC_MAXROWS * QC_MAXCOL], tvf[QC_MAXROWS * QC_MAXCOL], jvf[QC_MAXJOIN][QC_MAXROWS * QC_MAXCOL], outv[QC_MAXROWS * QC_MAXOUT];
  i64 cnt[QC_MAXCNT][QC_MAXROWS];
  QcVal rv[QC_MAXROWS][1], cv[QC_MAXCNT][QC_MAXROWS][1];   /* rowids and counts as values, for the flat writer */
} QcRun;
static QcRun *qc_run_r;   /* one connection, one thread */
static QcRun *qc_run_alloc(void) { if (!qc_run_r) qc_run_r = sqlite3MallocZero(sizeof *qc_run_r); return qc_run_r; }

/* count of index entries equal to integer key, for keys[] (n rows); 0 ok */
/* one key (GET /posts/:id): the seek and the walk, nothing else. 0 ok, 1 = take the fallback */
static inline __attribute__((always_inline)) int qc_count1(Btree *bt, QcPlan *P, int c, i64 key, i64 *out) {
  BtCursor *cur = P->oc[c] ? P->cc[c] : qc_cursor(P, bt, P->cnt[c].root, P->cnt[c].ki, &P->cc[c], &P->oc[c]); if (!cur) return 1;
  UnpackedRecord *uk = P->cnt[c].uk;
  uk->nField = 1; uk->default_rc = +1; uk->eqSeen = 0; uk->errCode = 0; uk->aMem[0].flags = MEM_Int; uk->aMem[0].u.i = key;
  int res; if (sqlite3BtreeIndexMoveto(cur, uk, &res) != SQLITE_OK) return 1;
  i64 cnt = 0;
  if (cur->eState == CURSOR_VALID) {
    if (res < 0) { int r = sqlite3BtreeNext(cur, 0); if (r == SQLITE_DONE) { *out = 0; return 0; } if (r) return 1; }
    for (;;) {
      MemPage *pg = cur->pPage; int ix = cur->ix, end = pg->leaf ? pg->nCell : ix + 1;
      for (; ix < end; ix++) {
        i64 k; int kind = qc_idxkey(pg, ix, &k);
        if (kind < 0) return 1;
        if (kind == 2 || k > key) { *out = cnt; return 0; }
        cnt += kind == 1 && k == key;
      }
      if (pg->leaf) cur->ix = (u16)(pg->nCell - 1);
      int r = sqlite3BtreeNext(cur, 0);
      if (r == SQLITE_DONE) break;
      if (r) return 1;
    }
  }
  *out = cnt; return 0;
}
QC_HOT static int qc_counts(QcRun *R, Btree *bt, QcPlan *P, int c, const i64 *keys, int n, i64 *out) {
  i64 lo = INT64_MAX, hi = INT64_MIN;
  for (int i = 0; i < n; i++) { if (keys[i] < lo) lo = keys[i]; if (keys[i] > hi) hi = keys[i]; }
  int ranged = n > 1 && (u64)(hi - lo) < QC_RANGE_MAX;   /* one key: counted directly */
  BtCursor *cur = qc_cursor(P, bt, P->cnt[c].root, P->cnt[c].ki, &P->cc[c], &P->oc[c]); if (!cur) return 1;
  UnpackedRecord *uk = P->cnt[c].uk; int rc = 0;
  for (int pass = 0; pass < (ranged ? 1 : n); pass++) {
    i64 a = ranged ? lo : keys[pass], b = ranged ? hi : keys[pass];
    if (ranged) memset(R->counts, 0, sizeof(u32) * (size_t)(hi - lo + 1));
    uk->nField = 1; uk->default_rc = +1; uk->eqSeen = 0; uk->errCode = 0; uk->aMem[0].flags = MEM_Int; uk->aMem[0].u.i = a;
    int res; if (sqlite3BtreeIndexMoveto(cur, uk, &res) != SQLITE_OK) { rc = 1; break; }
    i64 cnt = 0;
    if (cur->eState == CURSOR_VALID) {
      if (res < 0 && (rc = sqlite3BtreeNext(cur, 0)) != SQLITE_OK) { if (rc == SQLITE_DONE) rc = 0; else { rc = 1; break; } goto done1; }
      for (;;) {
        MemPage *pg = cur->pPage; int ix = cur->ix, stop = 0, end = pg->leaf ? pg->nCell : ix + 1;   /* interior: this one cell */
        for (; ix < end; ix++) {
          i64 k; int kind = qc_idxkey(pg, ix, &k);
          if (kind < 0) { rc = 1; stop = 1; break; }
          if (kind == 2 || k > b) { stop = 1; break; }
          if (kind == 1 && k >= a) { if (ranged) R->counts[k - lo]++; else cnt++; }
        }
        if (stop) break;
        if (pg->leaf) cur->ix = (u16)(pg->nCell - 1);
        int r2 = sqlite3BtreeNext(cur, 0);
        if (r2 == SQLITE_DONE) break;
        if (r2) { rc = 1; break; }
      }
      if (rc) break;
    }
  done1:
    if (!ranged) out[pass] = cnt;
  }
  if (!rc && ranged) for (int i = 0; i < n; i++) out[i] = R->counts[keys[i] - lo];
  return rc;
}

/* ---------------------------------------------------------------- JSON output: the plan writes the response body itself
** A template is the body's prefix and suffix, the separator between rows, and per row the literal fragments around the
** columns: frag[0] col0 frag[1] col1 ... frag[n]. A column is 'i' (an INTEGER, written in decimal) or 's' (TEXT, written
** as a JSON string with JSON.stringify's escapes). Anything else (NULL, REAL, BLOB, an INTEGER in an 's' column) returns
** QC_FALLBACK before a byte is written, so the caller's own formatting decides those. */
typedef struct QcJson { const char *open, *close, *sep; int ncol; const char *kind; const char *frag[QC_MAXOUT + 1]; } QcJson;
/* fragments live in 32-byte zero-padded slots: each is copied with two fixed 16-byte moves (no memcpy call) */
#define QC_FRAG 32
typedef struct QcTmpl { char kind[QC_MAXOUT]; int ncol; char open[QC_FRAG], close[QC_FRAG], sep[QC_FRAG], frag[QC_MAXOUT + 1][QC_FRAG];
                        u32 lopen, lclose, lsep, lfrag[QC_MAXOUT + 1], lrow; } QcTmpl;
static int qc_slot(char *dst, u32 *len, const char *src) {
  size_t n = strlen(src); if (n > QC_FRAG) return 0;
  memset(dst, 0, QC_FRAG); memcpy(dst, src, n); *len = (u32)n; return 1;
}
static inline char *qc_frag(char *p, const char *slot, u32 len) {   /* writes 32 bytes, advances len (<= 32) */
  memcpy(p, slot, 16); memcpy(p + 16, slot + 16, 16); return p + len;
}
static int qc_plan_nout(const void *plan);
static void qc_free(Vdbe *v);
SQLITE_API int sqlite3_qc_json(sqlite3_stmt *pStmt, const QcJson *j) {
  Vdbe *v = (Vdbe *)pStmt; void *P = v ? v->pQc : 0;
  if (!P || j->ncol != qc_plan_nout(P) || j->ncol > QC_MAXOUT) return 0;
  sqlite3QcFree = qc_free;   /* (frees the template with the handle) */
  QcTmpl *t = v->pQcTmpl ? v->pQcTmpl : sqlite3_malloc(sizeof *t); if (!t) return 0;   /* on the handle: survives re-prepares */
  t->ncol = j->ncol; t->lrow = 0;
  int ok = qc_slot(t->open, &t->lopen, j->open) && qc_slot(t->close, &t->lclose, j->close) && qc_slot(t->sep, &t->lsep, j->sep);
  for (int k = 0; ok && k <= j->ncol; k++) { ok = qc_slot(t->frag[k], &t->lfrag[k], j->frag[k]); t->lrow += t->lfrag[k]; }
  if (!ok) { if (t != v->pQcTmpl) sqlite3_free(t); return 0; }
  for (int k = 0; k < j->ncol; k++) { if (j->kind[k] != 'i' && j->kind[k] != 's') { sqlite3_free(t); return 0; } t->kind[k] = j->kind[k]; }
  v->pQcTmpl = t; return 1;
}
static const char QC_HEX[] = "0123456789abcdef";
static inline char *qc_esc1(char *o, unsigned char c) {   /* JSON.stringify's escapes */
  switch (c) {
    case '"': o[0] = '\\'; o[1] = '"'; return o + 2;
    case '\\': o[0] = '\\'; o[1] = '\\'; return o + 2;
    case '\b': o[0] = '\\'; o[1] = 'b'; return o + 2;
    case '\f': o[0] = '\\'; o[1] = 'f'; return o + 2;
    case '\n': o[0] = '\\'; o[1] = 'n'; return o + 2;
    case '\r': o[0] = '\\'; o[1] = 'r'; return o + 2;
    case '\t': o[0] = '\\'; o[1] = 't'; return o + 2;
    default: memcpy(o, "\\u00", 4); o[4] = QC_HEX[c >> 4]; o[5] = QC_HEX[c & 15]; return o + 6;
  }
}
static inline char *qc_escape(char *o, const u8 *s, u32 n) {
  for (u32 i = 0; i < n; i++) { unsigned c = s[i]; if (c < 0x20 || c == '"' || c == '\\') o = qc_esc1(o, (unsigned char)c); else *o++ = (char)c; }
  return o;
}
/* the string at s as a JSON string. vec: s may be read up to 15 bytes past its end (pcache page or scratch); the copy
   is 16 bytes at a time with the escape mask OR-ed up, and a field that needs escaping is rewritten. Writes up to 15
   bytes past the result (the caller keeps 32 bytes of slack). */
#if defined(__aarch64__) && defined(__ARM_NEON)
#include <arm_neon.h>
typedef uint8x16_t qc_v16;
static inline qc_v16 qc_ld(const u8 *p) { return vld1q_u8(p); }
static inline void qc_st(char *p, qc_v16 v) { vst1q_u8((uint8_t *)p, v); }
static inline uint64_t qc_mask(qc_v16 v) {
  uint8x16_t m = vorrq_u8(vorrq_u8(vceqq_u8(v, vdupq_n_u8('"')), vceqq_u8(v, vdupq_n_u8('\\'))), vcltq_u8(v, vdupq_n_u8(0x20)));
  return vget_lane_u64(vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(m), 4)), 0);
}
#define QC_LANE 4
#define QC_VEC 1
#elif defined(__SSE2__)
#include <emmintrin.h>
typedef __m128i qc_v16;
static inline qc_v16 qc_ld(const u8 *p) { return _mm_loadu_si128((const __m128i *)p); }
static inline void qc_st(char *p, qc_v16 v) { _mm_storeu_si128((__m128i *)p, v); }
static inline uint64_t qc_mask(qc_v16 v) {
  __m128i m = _mm_or_si128(_mm_or_si128(_mm_cmpeq_epi8(v, _mm_set1_epi8('"')), _mm_cmpeq_epi8(v, _mm_set1_epi8('\\'))),
                           _mm_cmpeq_epi8(_mm_min_epu8(v, _mm_set1_epi8(0x1f)), v));
  return (uint64_t)(unsigned)_mm_movemask_epi8(m);
}
#define QC_LANE 1
#define QC_VEC 1
#else
#define QC_VEC 0
#endif
static inline __attribute__((always_inline)) char *qc_jstr(char *p, const u8 *s, u32 n, int vec) {
  *p++ = '"';
#if QC_VEC
  if (vec) {
    uint64_t acc = 0; u32 i = 0;
    for (; i + 16 <= n; i += 16) { qc_v16 x = qc_ld(s + i); qc_st(p + i, x); acc |= qc_mask(x); }
    if (i < n) { qc_v16 x = qc_ld(s + i); qc_st(p + i, x); acc |= qc_mask(x) & ((1ull << (QC_LANE * (n - i))) - 1); }
    p = acc ? qc_escape(p, s, n) : p + n;
    *p++ = '"'; return p;
  }
#endif
  (void)vec; p = qc_escape(p, s, n); *p++ = '"'; return p;
}
static const char QC_D2[] = "00010203040506070809101112131415161718192021222324252627282930313233343536373839"
                            "40414243444546474849505152535455565758596061626364656667686970717273747576777879"
                            "8081828384858687888990919293949596979899";
static inline __attribute__((always_inline)) char *qc_jint(char *p, i64 v) {
  u64 u; if (v < 0) { *p++ = '-'; u = (u64)0 - (u64)v; } else u = (u64)v;
  char t[40]; int k = 20;   /* digits end at t[20]; the copy moves a fixed 20 bytes into the output's slack */
  while (u >= 100) { u64 q = u / 100; k -= 2; memcpy(t + k, QC_D2 + 2 * (u - q * 100), 2); u = q; }
  if (u >= 10) { k -= 2; memcpy(t + k, QC_D2 + 2 * u, 2); } else t[--k] = (char)('0' + u);
  memcpy(p, t + k, 16); memcpy(p + 16, t + k + 16, 4); return p + 20 - k;
}


/* QC_ORACLE (an experiment, not a mode): the feed/get plan's decoders called directly and its writer unrolled with
   literal keys, i.e. what per-plan code generation would produce for exactly this plan, to measure its ceiling. A
   plan of any other shape takes the normal path. */
static inline __attribute__((always_inline)) int qc_dec_idx(QcPlan *P, const u8 *rec, u32 sz, QcVal *tmp) {
#ifdef QC_ORACLE
  if (P->idxDec == qc_dec_TII) return qc_dec_TII(rec, sz, tmp);
#endif
  return P->idxDec ? P->idxDec(rec, sz, tmp) : qc_decode_fast(rec, sz, &P->idxShape, P->idxCols | (1u << P->idxRowidField), tmp);
}
#ifdef QC_ORACLE
#define QC_DEC_TAB(rec, sz, out) (P->tabDec == qc_dec_NIT ? qc_dec_NIT(rec, sz, out) : P->tabDec && P->tabDec(rec, sz, out))
#define QC_DEC_JOIN(j, rec, sz, out) (P->joinDec[j] == qc_dec_NT ? qc_dec_NT(rec, sz, out) : P->joinDec[j] && P->joinDec[j](rec, sz, out))
#else
#define QC_DEC_TAB(rec, sz, out) (P->tabDec && P->tabDec(rec, sz, out))
#define QC_DEC_JOIN(j, rec, sz, out) (P->joinDec[j] && P->joinDec[j](rec, sz, out))
#endif

/* ---------------------------------------------------------------- run time: overlapped descents ("lanes")
** One level-by-level pass over several B-tree descents at once: every lane's page is searched, every next child page is
** prefetched (pcache hash bucket, then the page and its header), and only then are the children fetched. Misses of
** independent descents (the post rows and the likes index in GET /posts/:id, the 20 post rows and the likes range in the
** feed) overlap instead of queueing. A table lane ends at the leaf cell of its rowid; an index lane keeps its whole path,
** from which qc_idx_walk counts entries in key order without a BtCursor. */
#define QC_MAXDEPTH 20
#define QC_MAXLANE (QC_MAXROWS + QC_MAXCNT)
typedef struct QcLane {
  Pgno root; u8 isIdx, found, done; i64 key;
  int depth;                                   /* index lanes: pg[0] root .. pg[depth-1] leaf; table lanes: pg[0] only */
  MemPage *pg[QC_MAXDEPTH]; int ix[QC_MAXDEPTH];   /* ix: the child taken at each interior level, the position at the leaf */
  Pgno ch;                                     /* the next child (during the descent) */
} QcLane;
/* sign of (the first field of index cell i) - key, as SQLite orders values; 2 = a cell we do not handle */
/* a cell's first field (qc_idxkey's kind and value) against an integer key: -1 0 1, or 2 for a cell not handled */
static inline __attribute__((always_inline)) int qc_idx_cmp_kind(int kind, i64 k, i64 key) {
  if (kind < 0) return 2;
  if (kind == 2) return 1;                                   /* TEXT/BLOB: after every number */
  if (kind == 1) return k < key ? -1 : k > key;
  if (k == INT64_MIN) return -1;                             /* NULL (or a REAL below every integer) */
  return k >= key ? 1 : -1;                                  /* a non-integral REAL r: r > key iff floor(r) >= key */
}
static inline int qc_idx_cmp(const MemPage *pg, int i, i64 key) { i64 k; int kind = qc_idxkey(pg, i, &k); return qc_idx_cmp_kind(kind, k, key); }
/* first cell whose first field is >= key (nCell if none); -1 on a cell we do not handle */
static inline int qc_idx_lb(const MemPage *pg, i64 key) {
  int lo = 0, len = pg->nCell;
  while (len > 0) {
    int h = len >> 1, c = qc_idx_cmp(pg, lo + h, key);
    if (c == 2) return -1;
    if (c < 0) { lo += h + 1; len -= h + 1; } else len = h;
  }
  return lo;
}
static inline Pgno qc_child(const MemPage *pg, int i) { return i >= pg->nCell ? get4byte(&pg->aData[pg->hdrOffset + 8]) : get4byte(findCell(pg, i)); }
static void qc_lanes_release(QcLane *L, int n) {
  for (int l = 0; l < n; l++) { for (int d = 0; d < L[l].depth; d++) if (L[l].pg[d]) releasePage(L[l].pg[d]); L[l].depth = 0; }
}
/* run n lanes to their leaves; SQLITE_OK, or an error / an unexpected page (the caller falls back) */
static int qc_descend(BtShared *bt, QcLane *L, int n) {
  int pcache = bt->pPager->xGet == getPageNormal, rc;
  for (int l = 0; l < n; l++) {
    L[l].depth = 0; L[l].found = 0; L[l].done = 0; L[l].ch = 0;
    if (l && L[l - 1].root == L[l].root && L[l - 1].depth) { sqlite3PagerRef(L[l - 1].pg[0]->pDbPage); L[l].pg[0] = L[l - 1].pg[0]; }
    else if ((rc = getAndInitPage(bt, L[l].root, &L[l].pg[0], PAGER_GET_READONLY))) { qc_lanes_release(L, l); return rc; }
    L[l].depth = 1;
    if (L[l].pg[0]->intKey != !L[l].isIdx) { qc_lanes_release(L, l + 1); return SQLITE_CORRUPT_BKPT; }
  }
  for (int round = 0;; round++) {
    int active = 0;
    if (round > QC_MAXDEPTH - 2) { qc_lanes_release(L, n); return SQLITE_CORRUPT_BKPT; }
    for (int l = 0; l < n; l++) {          /* 1. search this level; leaves finish here */
      QcLane *x = &L[l]; MemPage *pg = x->pg[x->depth - 1];
      if (x->done) { x->ch = 0; continue; }
      int lb = x->isIdx ? qc_idx_lb(pg, x->key) : qc_lower_bound(pg, x->key);
      if (lb < 0) { qc_lanes_release(L, n); return SQLITE_CORRUPT_BKPT; }
      x->ix[x->depth - 1] = lb;
      if (pg->leaf) { if (!x->isIdx) x->found = lb < pg->nCell && qc_cellkey(pg, lb) == x->key; x->ch = 0; x->done = 1; continue; }
      x->ch = qc_child(pg, lb); active++;
      if (pcache && (!l || x->ch != L[l - 1].ch)) QC_PF(qc_bucket(bt, x->ch));
    }
    if (!active) return SQLITE_OK;
    if (pcache) for (int l = 0; l < n; l++) {   /* 2. the children's pages and headers */
      if (!L[l].ch || (l && L[l].ch == L[l - 1].ch)) continue;
      PgHdr1 *h = *qc_bucket(bt, L[l].ch); while (h && h->iKey != L[l].ch) h = h->pNext;
      if (h) { u8 *d = h->page.pBuf; QC_PF(d); QC_PF(d + 64); QC_PF(h->page.pExtra); }
    }
    for (int l = 0; l < n; l++) {          /* 3. fetch (shared with the previous lane when it took the same child) */
      QcLane *x = &L[l]; if (!x->ch) continue;
      MemPage *c;
      if (l && L[l - 1].ch == x->ch && L[l - 1].root == x->root) { c = L[l - 1].pg[L[l - 1].depth - 1]; sqlite3PagerRef(c->pDbPage); }
      else if ((rc = getAndInitPage(bt, x->ch, &c, PAGER_GET_READONLY))) { qc_lanes_release(L, n); return rc; }
      if (c->intKey != !x->isIdx || c->nCell < (x->isIdx ? 0 : 1)) { releasePage(c); qc_lanes_release(L, n); return SQLITE_CORRUPT_PGNO(x->ch); }
      if (x->isIdx) { if (x->depth >= QC_MAXDEPTH) { releasePage(c); qc_lanes_release(L, n); return SQLITE_CORRUPT_BKPT; } x->pg[x->depth++] = c; }
      else { releasePage(x->pg[0]); x->pg[0] = c; }   /* a table lane needs only its current page */
    }
  }
}
/* count the entries of an index lane, from its position on, whose first field is an integer in [lo, hi]: counts[k - lo]
   (counts != 0) or *one. Stops at the first entry above hi. 0 ok, 1 = a cell or page we do not handle */
static int qc_idx_walk(BtShared *bt, QcLane *x, i64 lo, i64 hi, u32 *counts, i64 *one) {
  int d = x->depth - 1, ix = x->ix[d];
  for (;;) {
    MemPage *pg = x->pg[d];
    for (; ix < pg->nCell; ix++) {
      i64 k; int kind = qc_idxkey(pg, ix, &k);
      if (kind < 0) return 1;
      if (kind == 2 || (kind == 1 && k > hi) || (kind == 0 && k != INT64_MIN && k >= hi)) return 0;
      if (kind == 1 && k >= lo) { if (counts) counts[k - lo]++; else (*one)++; }
    }
    for (;;) {   /* up to the first ancestor with an entry after the child we came from */
      if (d == 0) return 0;
      d--;
      if (x->ix[d] < x->pg[d]->nCell) break;
    }
    pg = x->pg[d]; ix = x->ix[d];
    { i64 k; int kind = qc_idxkey(pg, ix, &k);        /* the interior entry itself */
      if (kind < 0) return 1;
      if (kind == 2 || (kind == 1 && k > hi) || (kind == 0 && k != INT64_MIN && k >= hi)) return 0;
      if (kind == 1 && k >= lo) { if (counts) counts[k - lo]++; else (*one)++; } }
    x->ix[d] = ix + 1;                                 /* then the leftmost leaf of the next child */
    for (int e = d + 1; e < x->depth; e++) { releasePage(x->pg[e]); x->pg[e] = 0; }
    x->depth = d + 1;
    Pgno ch = qc_child(pg, ix + 1);
    for (;;) {
      MemPage *c; if (x->depth >= QC_MAXDEPTH || getAndInitPage(bt, ch, &c, PAGER_GET_READONLY)) return 1;
      x->pg[x->depth] = c; x->ix[x->depth] = 0; x->depth++;
      if (c->intKey) return 1;
      if (c->leaf) break;
      ch = qc_child(c, 0);
    }
    d = x->depth - 1; ix = 0;
  }
}

static int qc_own_txn;   /* sqlite3_qc_exec began the read transaction for this run (in autocommit): the plans run in it */
#define QG_DEMOTE (-2)   /* (qcg.c's: this plan can't run it, qvm takes the statement) */
static int qc_exec_special(Vdbe *v, qc_row_cb cb, void *ctx) {
  QcPlan *P = v->pQc; sqlite3 *db = v->db;
  if (!P || v->eVdbeState != VDBE_READY_STATE || (db->autoCommit && !qc_own_txn) || P->iDb >= db->nDb) return QC_FB("L1");
  Btree *bt = db->aDb[P->iDb].pBt; if (!bt) return QC_FB("L2");
  if (bt->pBt->pPager->bUseFetch) { qc_why = "mmap"; return QG_DEMOTE; }   /* (as qg_exec: its lanes, batched seeks and pins add page references a memory-mapped page can't take) */
  /* OP_Transaction's read path: begin (or join) the read transaction, then the schema cookie check. Within one
     transaction the schema changes only by this connection's own DDL, which expires the statement (checked below), so
     the cookie is read once per transaction */
  if (sqlite3BtreeTxnState(bt) == SQLITE_TXN_NONE) { P->txnChecked = 0;
    int iMeta; if (sqlite3BtreeBeginTrans(bt, 0, &iMeta) != SQLITE_OK) return QC_FB("L3");
  }
  if (v->expired) return QC_FB("L5");
  if (!P->txnChecked || P->bt != bt) {
    int iMeta; sqlite3BtreeGetMeta(bt, BTREE_SCHEMA_VERSION, (u32 *)&iMeta);
    if (iMeta != P->cookie || db->aDb[P->iDb].pSchema->iGeneration != P->gen) return QC_FB("L4");   /* SQLITE_SCHEMA: SQLite re-prepares */
    P->txnChecked = 1; P->bt = bt;   /* (P->bt also names the btree the hook clears this for) */
    if (!P->act) QC_LIST_ADD(qc_act, qc_nact, P, act);
  }
  QcRun *R = qc_run_alloc(); if (!R) return QC_FB("L6");
  i64 rowid[QC_MAXROWS]; int nrow = 0, st = QC_FALLBACK;
  R->npin = 0; for (int j = 0; j < P->njoin; j++) R->jn[j] = 0;
  QcVal *outv = R->outv;
#define IV(i) (R->ivf + (size_t)(i) * P->idxW)
#define TV(i) (R->tvf + (size_t)(i) * P->tabW)
#define JV(j, i) (R->jvf[j] + (size_t)(i) * P->joinW[j])
  i64 (*cnt)[QC_MAXROWS] = R->cnt;
  /* 1. driver */
  if (P->scan) {
    BtCursor *ci = qc_cursor(P, bt, P->idxRoot, P->idxKi, &P->ci, &P->oi); if (!ci) return QC_FB("L7");
    int res;
    if (sqlite3BtreeFirst(ci, &res) != SQLITE_OK) { sqlite3BtreeCloseCursor(ci); return QC_FB("L8"); }
    if (!res) do {
      i64 r; u32 sz = sqlite3BtreePayloadSize(ci), amt; const u8 *rec = sqlite3BtreePayloadFetch(ci, &amt);
      int fast = 0;
      if (P->idxRowidField >= 0 && amt >= sz) {   /* the covered columns and the rowid in one pass */
        QcVal tmp[QC_MAXCOL];
        if (qc_dec_idx(P, rec, sz, tmp)) {
          for (int c = 0; c < P->idxRowidField && c < P->idxW; c++) IV(nrow)[c] = tmp[c];
          r = tmp[P->idxRowidField].i; fast = 1;
        }
      }
      if (!fast && sqlite3VdbeIdxRowid(db, ci, &r) != SQLITE_OK) goto out_ci;
      if (P->idxCols) {   /* covered columns straight from the index record; its page stays pinned */
        if (amt < sz || (!fast && !qc_decode(rec, sz, P->idxCols, IV(nrow)))) goto out_ci;
        DbPage *pg = ci->pPage->pDbPage;
        if (!R->npin || R->pins[R->npin - 1] != pg) { sqlite3PagerRef(pg); R->pins[R->npin++] = pg; }
      }
      rowid[nrow++] = r;
    } while (nrow < P->limit && sqlite3BtreeNext(ci, 0) == SQLITE_OK);
    if (0) { out_ci: for (int i = 0; i < R->npin; i++) sqlite3PagerUnref(R->pins[i]); return QC_FB("L9"); }
  } else {
    const QcOut *O = cb ? 0 : ctx;
    if (!P->param) rowid[nrow++] = P->key;
    else if (O && O->param) {
      if (P->param > O->nparam) return QC_FB("param");
      rowid[nrow++] = O->param[P->param - 1];
    } else {
      Mem *m = &v->aVar[P->param - 1];
      if (!(m->flags & MEM_Int) || (m->flags & (MEM_Null | MEM_Str | MEM_Real | MEM_Blob))) return QC_FB("L10");   /* SeekRowid would convert */
      rowid[nrow++] = m->u.i;
    }
  }
  /* 2. table rows (and, overlapped with them, the start of every count's index range) */
  static QcLane lanes[QC_MAXLANE]; int nl = 0, cntLane[QC_MAXCNT]; i64 clo[QC_MAXCNT], chi[QC_MAXCNT];
  for (int c = 0; c < P->ncnt; c++) cntLane[c] = -1;
  if (P->lanes && nrow) {
    for (int i = 0; i < nrow; i++) { lanes[nl].root = P->tabRoot; lanes[nl].isIdx = 0; lanes[nl].key = rowid[i]; nl++; }
    for (int c = 0; c < P->ncnt; c++) {
      i64 lo = INT64_MAX, hi = INT64_MIN;
      for (int i = 0; i < nrow; i++) { if (rowid[i] < lo) lo = rowid[i]; if (rowid[i] > hi) hi = rowid[i]; }
      if ((u64)(hi - lo) >= QC_RANGE_MAX) continue;          /* a wide range: per-key cursor seeks below */
      clo[c] = lo; chi[c] = hi; cntLane[c] = nl;
      lanes[nl].root = P->cnt[c].root; lanes[nl].isIdx = 1; lanes[nl].key = lo; nl++;
    }
    if (qc_descend(bt->pBt, lanes, nl) != SQLITE_OK) return QC_FB("descend");
    for (int i = 0; i < nrow; i++) {
      QcLane *x = &lanes[i];
      if (!x->found) { if (P->scan) { qc_why = "lane miss"; goto out; } nrow = 0; break; }   /* point: no such row */
      MemPage *pg = x->pg[0]; CellInfo info; pg->xParseCell(pg, findCell(pg, x->ix[0]), &info);
      if (info.nLocal != info.nPayload ||
          !((QC_DEC_TAB(info.pPayload, info.nPayload, TV(i))) || (P->tabShape.ok && qc_decode_fast(info.pPayload, info.nPayload, &P->tabShape, P->tabCols, TV(i))) ||
            qc_decode(info.pPayload, info.nPayload, P->tabCols, TV(i)))) { qc_why = "lane row"; goto out; }
    }
    goto rows_done;
  }
  BtCursor *ct = qc_cursor(P, bt, P->tabRoot, 0, &P->ct, &P->ot); if (!ct) return QC_FB("L11");
  int nkept = 0; i64 prev = INT64_MIN;
  for (int i = 0; i < nrow; i++) {
    int found = 0, res;
    if (prev == rowid[i] + 1 && ct->eState == CURSOR_VALID) {
      int rc = sqlite3BtreePrevious(ct, 0);
      if (rc == SQLITE_OK && sqlite3BtreeIntegerKey(ct) == rowid[i]) found = 1; else if (rc != SQLITE_OK && rc != SQLITE_DONE) { qc_why = "out@" QC_STR(__LINE__); goto out; }
    }
    if (!found) { if (sqlite3BtreeTableMoveto(ct, rowid[i], 0, &res) != SQLITE_OK) { qc_why = "out@" QC_STR(__LINE__); goto out; } found = res == 0 && ct->eState == CURSOR_VALID; }
    prev = rowid[i];
    if (!found) { if (P->scan) { qc_why = "out@" QC_STR(__LINE__); goto out; } nrow = 0; break; }     /* scan: a dangling index entry (corrupt): SQLite decides */
    u32 sz = sqlite3BtreePayloadSize(ct), amt; const u8 *rec = sqlite3BtreePayloadFetch(ct, &amt);
    if (amt < sz || !((QC_DEC_TAB(rec, sz, TV(i))) || (P->tabShape.ok && qc_decode_fast(rec, sz, &P->tabShape, P->tabCols, TV(i))) || qc_decode(rec, sz, P->tabCols, TV(i)))) { qc_why = "out@" QC_STR(__LINE__); goto out; }
    if (P->scan) {   /* the cursor moves on to the next row: keep this page; a single lookup leaves the cursor (and page) here */
      DbPage *pg = ct->pPage->pDbPage;
      if (!R->npin || R->pins[R->npin - 1] != pg) { sqlite3PagerRef(pg); R->pins[R->npin++] = pg; }
    }
    nkept++;
  }
  (void)nkept;
rows_done:
  /* 3. joins: one batched descent per join */
  for (int j = 0; j < P->njoin && nrow; j++) {
    i64 keys[QC_MAXROWS];
    for (int i = 0; i < nrow; i++) {
      QcVal *k = &TV(i)[P->join[j].keycol];
      if (k->type != SQLITE_INTEGER) { qc_why = "out@" QC_STR(__LINE__); goto out; }           /* NULL, real or text key: SeekRowid's conversions, not ours */
      keys[i] = k->i;
    }
    if (nrow == 1) {   /* one row: a plain seek on the plan's cursor, which stays where it is until the next execution */
      BtCursor *cj = qc_cursor(P, bt, P->join[j].root, 0, &P->cj[j], &P->oj[j]); int res;
      if (!cj || sqlite3BtreeTableMoveto(cj, keys[0], 0, &res) != SQLITE_OK) { qc_why = "out@" QC_STR(__LINE__); goto out; }
      if (res != 0 || cj->eState != CURSOR_VALID) { if (P->scan) goto out; nrow = 0; break; }
      u32 sz = sqlite3BtreePayloadSize(cj), amt; const u8 *rec = sqlite3BtreePayloadFetch(cj, &amt);
      if (amt < sz || !((QC_DEC_JOIN(j, rec, sz, JV(j, 0))) || (P->joinShape[j].ok && qc_decode_fast(rec, sz, &P->joinShape[j], P->joinCols[j], JV(j, 0))) || qc_decode(rec, sz, P->joinCols[j], JV(j, 0)))) { qc_why = "out@" QC_STR(__LINE__); goto out; }
      continue;
    }
    if (qc_seek_batch(bt, P->join[j].root, keys, nrow, R->jr[j]) != SQLITE_OK) { qc_why = "out@" QC_STR(__LINE__); goto out; }
    R->jn[j] = nrow;
    for (int i = 0; i < nrow; i++) {
      qc_res *q = &R->jr[j][i];
      if (!q->found) { if (P->scan) { qc_why = "out@" QC_STR(__LINE__); goto out; } nrow = 0; break; }   /* inner join drops the row: LIMIT would read further */
      MemPage *pg = q->leaf; CellInfo info; pg->xParseCell(pg, findCell(pg, q->ix), &info);
      if (info.nLocal != info.nPayload || !((QC_DEC_JOIN(j, info.pPayload, info.nPayload, JV(j, i))) || (P->joinShape[j].ok && qc_decode_fast(info.pPayload, info.nPayload, &P->joinShape[j], P->joinCols[j], JV(j, i))) ||
                                            qc_decode(info.pPayload, info.nPayload, P->joinCols[j], JV(j, i)))) { qc_why = "out@" QC_STR(__LINE__); goto out; }
    }
  }
  /* 4. counts: from the lane's position (one in-order walk of the range), or cursor seeks */
  for (int c = 0; c < P->ncnt && nrow; c++) {
    if (cntLane[c] >= 0) {
      if (nrow == 1) { i64 one = 0; if (qc_idx_walk(bt->pBt, &lanes[cntLane[c]], clo[c], chi[c], 0, &one)) { qc_why = "walk"; goto out; } cnt[c][0] = one; }
      else {
        memset(R->counts, 0, sizeof(u32) * (size_t)(chi[c] - clo[c] + 1));
        if (qc_idx_walk(bt->pBt, &lanes[cntLane[c]], clo[c], chi[c], R->counts, 0)) { qc_why = "walk"; goto out; }
        for (int i = 0; i < nrow; i++) cnt[c][i] = R->counts[rowid[i] - clo[c]];
      }
    } else if (nrow == 1 ? qc_count1(bt, P, c, rowid[0], &cnt[c][0]) : qc_counts(R, bt, P, c, rowid, nrow, cnt[c])) { qc_why = "out@" QC_STR(__LINE__); goto out; }
  }
  /* 5. rows out: the response body (template), or zero-copy rows to the callback */
  if (!cb) {
    QcTmpl *T = v->pQcTmpl; QcOut *O = ctx;
    if (!T || T->ncol != P->nout) goto out;   /* (a re-lifted plan with a different column count keeps the fallback) */
    int vec = bt->pBt->pPager->xGet == getPageNormal;   /* page-resident values: reading past a field stays in the page's allocation */
    /* flat: each output column is a base and a stride into the run state, fixed for this plan (no per-value dispatch).
       One pass: each value is checked as it is written (a fallback leaves a partial body the caller discards), and each
       row first checks its worst case against the room left (+64: the fixed 32-byte fragment moves and vector tails) */
#ifdef QC_ORACLE
    /* the unrolled writer for exactly (rowid, row col 2, index col 0, join 0 col 1, count 0) as i s s s i */
    if (T->ncol == 5 && P->out[0].kind == S_ROWID && P->out[1].kind == S_COL && P->out[1].src == 0 && P->out[1].col == 2 &&
        P->out[2].kind == S_COL && P->out[2].src == -1 && P->out[2].col == 0 && P->out[3].kind == S_COL && P->out[3].src == 1 &&
        P->out[3].col == 1 && P->out[4].kind == S_COUNT && P->out[4].src == 0 && !strcmp(T->kind, "isssi") &&
        !strcmp(T->frag[0], "{\"id\":") && !strcmp(T->frag[1], ",\"body\":") && !strcmp(T->frag[2], ",\"created_at\":") &&
        !strcmp(T->frag[3], ",\"author\":") && !strcmp(T->frag[4], ",\"like_count\":") && !strcmp(T->frag[5], "}")) {
      char *p = O->buf, *end = O->buf + O->cap;
      #define QC_W(lit) (memcpy(p, lit, sizeof(lit) - 1), p += sizeof(lit) - 1)
      if ((size_t)(end - p) < T->lopen + T->lclose + 64) goto out;
      p = qc_frag(p, T->open, T->lopen);
      for (int i = 0; i < nrow; i++) {
        const QcVal *b = &TV(i)[2], *c = &IV(i)[0], *a = &JV(0, i)[1];
        if (b->type != SQLITE_TEXT || c->type != SQLITE_TEXT || a->type != SQLITE_TEXT ||
            (size_t)(end - p) < 200 + 6 * ((size_t)b->n + (size_t)c->n + (size_t)a->n)) goto out;
        if (i) *p++ = ',';
        QC_W("{\"id\":"); p = qc_jint(p, rowid[i]);
        QC_W(",\"body\":"); p = qc_jstr(p, b->z, (u32)b->n, vec);
        QC_W(",\"created_at\":"); p = qc_jstr(p, c->z, (u32)c->n, vec);
        QC_W(",\"author\":"); p = qc_jstr(p, a->z, (u32)a->n, vec);
        QC_W(",\"like_count\":"); p = qc_jint(p, cnt[0][i]); *p++ = '}';
      }
      p = qc_frag(p, T->close, T->lclose);
      O->n = (size_t)(p - O->buf); O->rows = nrow; st = SQLITE_OK; goto out;
    }
#endif
    /* one compact op per output column: where its values are, how they are written, its fragment */
    struct { const char *frag; u32 lfrag; u8 op; const QcVal *v; const i64 *iv; size_t stride; } ops[QC_MAXOUT];
    for (int k = 0; k < T->ncol; k++) {
      QcSym sy = P->out[k]; ops[k].frag = T->frag[k]; ops[k].lfrag = T->lfrag[k]; ops[k].v = 0; ops[k].iv = 0; ops[k].stride = 0;
      if (sy.kind == S_ROWID || sy.kind == S_COUNT) {
        if (T->kind[k] != 'i') goto out;
        ops[k].op = 0; ops[k].iv = sy.kind == S_ROWID ? rowid : cnt[sy.src];
      } else {
        if (sy.real) goto out;   /* (the body writer has no float form) */
        ops[k].op = T->kind[k] == 'i' ? 1 : 2;
        if (sy.src < 0) { ops[k].v = &IV(0)[sy.col]; ops[k].stride = (size_t)P->idxW; }
        else if (sy.src == 0) { ops[k].v = &TV(0)[sy.col]; ops[k].stride = (size_t)P->tabW; }
        else { ops[k].v = &JV(sy.src - 1, 0)[sy.col]; ops[k].stride = (size_t)P->joinW[sy.src - 1]; }
      }
    }
    char *p = O->buf, *end = O->buf + O->cap; const int ncol = T->ncol;
    if ((size_t)(end - p) < T->lopen + T->lclose + 64) goto out;
    p = qc_frag(p, T->open, T->lopen);
    /* room: checked before each value against its worst case + the fixed fragment moves (QC_FRAG) + 64 */
    for (int i = 0; i < nrow; i++) {
      if ((size_t)(end - p) < T->lsep + QC_FRAG + 64) goto out;
      if (i) p = qc_frag(p, T->sep, T->lsep);
      for (int k = 0; k < ncol; k++) {
        if (ops[k].op == 0) {   /* a rowid or a count: always an integer */
          if ((size_t)(end - p) < 2 * QC_FRAG + 21 + 64) goto out;
          p = qc_frag(p, ops[k].frag, ops[k].lfrag); p = qc_jint(p, ops[k].iv[i]); continue;
        }
        const QcVal *x = ops[k].v + i * ops[k].stride;
        if (ops[k].op == 1) {
          if (x->type != SQLITE_INTEGER || (size_t)(end - p) < 2 * QC_FRAG + 21 + 64) goto out;
          p = qc_frag(p, ops[k].frag, ops[k].lfrag); p = qc_jint(p, x->i);
        } else {
          if (x->type != SQLITE_TEXT || (size_t)(end - p) < 2 * QC_FRAG + 2 + 6 * (size_t)x->n + 64) goto out;
          p = qc_frag(p, ops[k].frag, ops[k].lfrag); p = qc_jstr(p, x->z, (u32)x->n, vec);
        }
      }
      if ((size_t)(end - p) < 2 * QC_FRAG + 64) goto out;
      p = qc_frag(p, T->frag[ncol], T->lfrag[ncol]);
    }
    if ((size_t)(end - p) < QC_FRAG + 64) goto out;
    p = qc_frag(p, T->close, T->lclose);
    O->n = (size_t)(p - O->buf); O->rows = nrow; st = SQLITE_OK;
  } else {
    for (int i = 0; i < nrow; i++) for (int k = 0; k < P->nout; k++) {
      QcSym s = P->out[k]; QcVal *o = &outv[i * P->nout + k];
      if (s.kind == S_ROWID) { o->type = SQLITE_INTEGER; o->i = rowid[i]; }
      else if (s.kind == S_COUNT) { o->type = SQLITE_INTEGER; o->i = cnt[s.src][i]; }
      else {
        *o = s.src < 0 ? IV(i)[s.col] : s.src == 0 ? TV(i)[s.col] : JV(s.src - 1, i)[s.col];
        if (s.real && o->type == SQLITE_INTEGER) { o->type = SQLITE_FLOAT; o->r = (double)o->i; }   /* OP_RealAffinity */
      }
    }
    st = cb(ctx, nrow, P->nout, outv);
  }
out:
  if (nl) qc_lanes_release(lanes, nl);
  for (int j = 0; j < P->njoin; j++) for (int i = 0; i < R->jn[j]; i++) if (R->jr[j][i].leaf) releasePage(R->jr[j][i].leaf);
  for (int i = 0; i < R->npin; i++) sqlite3PagerUnref(R->pins[i]);
  return st;
}

/* ---------------------------------------------------------------- general plans, and the public entry points */
/* length()'s count of a text value (lengthFunc): characters up to the first NUL, a lead byte >= 0xc0 swallowing the
   continuation bytes after it; 8 bytes at a time while they are ASCII and not NUL (each one character) */
static inline i64 qc_utf8_chars(const u8 *z, int n) {
  const u8 *e = z + n; i64 len = 0;
  while (z < e) {
    if (e - z >= 8) {
      u64 w; memcpy(&w, z, 8);
      if (!((w | (w - 0x0101010101010101ULL)) & 0x8080808080808080ULL)) { len += 8; z += 8; continue; }
    }
    if (!*z) break;
    len++; if (*z++ >= 0xc0) while (z < e && (*z & 0xc0) == 0x80) z++;
  }
  return len;
}
/* ---------------------------------------------------------------- program signatures (the plan cache, qv_cache_*)
** Every opcode and operand of a program, P4 by value (text, blobs, KeyInfo, Mem, integer arrays) or by the
** connection-owned object it names (FuncDef, CollSeq): two programs with equal signatures run alike, and a plan lifted
** from one runs the other once re-pointed at it. 0: a P4 it cannot compare (then the plan is not cached). */
/* what vdbe.c's OP_String8 does on its first run (UTF-8): an OP_String with the length. qv_lift does it to the
   program, and qv_cache_get to a program that gets a cached plan (whose region nodes read the length) */
static int qv_str8_ok(const Op *o, const sqlite3 *db) { return o->opcode == OP_String8 && o->p4.z && strlen(o->p4.z) <= (size_t)db->aLimit[SQLITE_LIMIT_LENGTH]; }
static void qv_str8(Vdbe *v) {
  for (int pc = 0; pc < v->nOp; pc++) if (qv_str8_ok(&v->aOp[pc], v->db)) { v->aOp[pc].p1 = sqlite3Strlen30(v->aOp[pc].p4.z); v->aOp[pc].opcode = OP_String; }
}
typedef struct QvSig { u8 *b; u32 n, cap; const u8 *cmp; u32 ncmp; } QvSig;   /* cmp: compare with it instead of building (no copy) */
static __attribute__((noinline)) int qv_sig_grow(QvSig *s, u32 n);
/* (inlined: QV_SIG's sizes are constants, so each compare and copy is a load or two, not a call) */
static inline __attribute__((always_inline)) int qv_sig_put(QvSig *s, const void *p, u32 n) {
  if (s->cmp) { if (s->n + n > s->ncmp || memcmp(s->cmp + s->n, p, n)) return 0; s->n += n; return 1; }
  if (s->n + n > s->cap && !qv_sig_grow(s, n)) return 0;
  memcpy(s->b + s->n, p, n); s->n += n; return 1;
}
static __attribute__((noinline)) int qv_sig_grow(QvSig *s, u32 n) {
  u32 c = s->cap ? s->cap : 1024; while (c < s->n + n) c *= 2;
  u8 *b = sqlite3_realloc64(s->b, c); if (!b) return 0;
  s->b = b; s->cap = c; return 1;
}
#define QV_SIG(x) qv_sig_put(&s, &(x), sizeof(x))
static int qv_sig(Vdbe *v, QvSig *out) {   /* out->cmp set: 1 = v's signature is that one */
  QvSig s = {0, 0, 0, out->cmp, out->ncmp}; int ok = 1;
  ok &= QV_SIG(v->nOp) & QV_SIG(v->nMem) & QV_SIG(v->nCursor) & QV_SIG(v->nResColumn) & QV_SIG(v->prepFlags);
  ok &= QV_SIG(v->db->flags) & QV_SIG(v->db->enc);
  for (int pc = 0; ok && pc < v->nOp; pc++) {
    const Op *o = &v->aOp[pc]; i8 t = o->p4type; u8 opc = o->opcode; int p1 = o->p1;
    if (qv_str8_ok(o, v->db)) { opc = OP_String; p1 = sqlite3Strlen30(o->p4.z); }   /* (as qv_str8 leaves it: equal before and after) */
    u8 rec[16]; rec[0] = opc; rec[1] = (u8)t; memcpy(rec + 2, &o->p5, 2); memcpy(rec + 4, &p1, 4); memcpy(rec + 8, &o->p2, 4); memcpy(rec + 12, &o->p3, 4);
    ok &= qv_sig_put(&s, rec, 16);   /* (one record per op: one bounds check, one 16-byte compare) */
    switch (t) {
      case P4_NOTUSED: break;
      case P4_INT32: ok &= QV_SIG(o->p4.i); break;
      case P4_STATIC: case P4_DYNAMIC: {   /* text, or for Blob and String P1 bytes */
        u32 n = (opc == OP_Blob || opc == OP_String) ? (u32)p1 : o->p4.z ? (u32)strlen(o->p4.z) : 0;
        ok &= QV_SIG(n) && (!n || qv_sig_put(&s, o->p4.z, n)); break;
      }
      case P4_COLLSEQ: ok &= QV_SIG(o->p4.pColl); break;
      case P4_FUNCDEF: ok &= QV_SIG(o->p4.pFunc); break;
      case P4_FUNCCTX: ok &= QV_SIG(o->p4.pCtx->pFunc) & QV_SIG(o->p4.pCtx->argc); break;
      case P4_KEYINFO: {
        const KeyInfo *k = o->p4.pKeyInfo;
        ok &= QV_SIG(k->enc) & QV_SIG(k->nKeyField) & QV_SIG(k->nAllField);
        ok &= qv_sig_put(&s, k->aSortFlags, k->nKeyField) && qv_sig_put(&s, k->aColl, sizeof(CollSeq *) * k->nAllField);
        break;
      }
      case P4_MEM: {
        const Mem *m = o->p4.pMem; u16 f = m->flags & (MEM_Null | MEM_Str | MEM_Int | MEM_Real | MEM_Blob | MEM_IntReal);
        ok &= QV_SIG(f) & QV_SIG(m->enc);
        if (f & (MEM_Str | MEM_Blob)) ok &= QV_SIG(m->n) && qv_sig_put(&s, m->z, (u32)m->n);
        else if (f & (MEM_Int | MEM_IntReal)) ok &= QV_SIG(m->u.i);
        else if (f & MEM_Real) ok &= QV_SIG(m->u.r);
        if (m->flags & MEM_Zero) ok = 0;
        break;
      }
      case P4_INTARRAY: ok &= qv_sig_put(&s, o->p4.ai, sizeof(u32) * (o->p4.ai[0] + 1)); break;
      case P4_SUBRTNSIG: {
        const SubrtnSig *g = o->p4.pSubrtnSig; u32 n = g->zAff ? (u32)strlen(g->zAff) : 0;
        ok &= QV_SIG(g->selId) & QV_SIG(g->iTable) & QV_SIG(g->iAddr) & QV_SIG(g->regReturn) & QV_SIG(n) && (!n || qv_sig_put(&s, g->zAff, n));
        break;
      }
      default: ok = 0;   /* tables, indexes, subprograms, virtual tables, expressions: not compared */
    }
  }
  if (s.cmp) return ok && s.n == s.ncmp;
  if (!ok) { sqlite3_free(s.b); return 0; }
  *out = s; return 1;
}
#undef QV_SIG
#include "qcg.c"
#include "qvm.c"

static int qc_plan_nout(const void *plan) {
  int k = *(const int *)plan;
  return k == 1 ? ((const QcPlan *)plan)->nout : k == 2 ? ((const QcGPlan *)plan)->nout : ((const QvPlan *)plan)->nout;
}
static void qc_txn_end_all(Btree *bt) { qc_txn_end(bt); qg_txn_end(bt); qv_txn_end(bt); }
static void qc_free_special(QcPlan *P) {
  qc_close(P->ci, &P->oi); qc_close(P->ct, &P->ot); sqlite3_free(P->ci); sqlite3_free(P->ct);
  for (int j = 0; j < QC_MAXJOIN; j++) { qc_close(P->cj[j], &P->oj[j]); sqlite3_free(P->cj[j]); }
  for (int c = 0; c < QC_MAXCNT; c++) { qc_close(P->cc[c], &P->oc[c]); sqlite3_free(P->cc[c]); }
  QC_LIST_DEL(qc_plans, qc_nplans, P, slot); QC_LIST_DEL(qc_act, qc_nact, P, act);
  sqlite3_free(P);
}
/* ---------------------------------------------------------------- serving through sqlite3_step (drop-in)
** With the amalgamation patched by qc/patch.py, two hooks let an unchanged program use qc through SQLite's own API:
**   sqlite3QcStart, at the top of sqlite3_step (the connection's mutex held): a statement about to start (READY) is
**     lifted if it isn't yet, and run by qc in a read transaction of its own (sqlite3_qc_exec's); its rows are kept with
**     the statement (QcServe, reused by every execution of the handle);
**   sqlite3QcServe, where sqlite3Step would call sqlite3VdbeExec: the kept rows are handed out one per call through the
**     statement's result row, and the last call halts the statement as OP_Halt does. Everything around them (the
**     statement's state, the connection's counters, errors, the profile callback) is sqlite3Step's own.
** A statement qc doesn't take, or that falls back, runs in sqlite3VdbeExec from its first opcode, as before. Not taken
** at all: writes, EXPLAIN, a connection with a trace or progress callback, and a statement qc refused (remembered on
** the handle until the schema changes). On by sqlite3_qc_serve(1) or QC_SERVE=1 at startup; QC_SERVE=0 off. */
typedef struct QcServe {
  QcVal *val; char *buf; size_t cval, cbuf; int nrow, ncol, pos;   /* the kept rows: values, their text and blob bytes */
  Mem *mem; int nmem;                                              /* the result row they are handed out through */
  u8 ready, active;                                                /* rows waiting / being served */
} QcServe;
static int qc_lift(Vdbe *v);
SQLITE_API int sqlite3_qc_exec(sqlite3_stmt *pStmt, qc_row_cb cb, void *ctx);
static int qc_serving;   /* in sqlite3QcStart: qc's own interpreter samples (qc_interp_rows) step the statement normally */
static void qc_serve_free(Vdbe *v) {
  QcServe *S = v->pQcRows; if (!S) return;
  for (int i = 0; i < S->nmem; i++) sqlite3VdbeMemRelease(&S->mem[i]);
  sqlite3_free(S->mem); sqlite3_free(S->val); sqlite3_free(S->buf); sqlite3_free(S); v->pQcRows = 0;
}
static int qc_serve_rows(void *ctx, int nrow, int ncol, const QcVal *x) {   /* qc's rows (valid during the call), kept */
  QcServe *S = ctx; size_t nv = (size_t)nrow * (size_t)ncol, nb = 0;
  if (nv > S->cval) { size_t c = nv * 2; QcVal *t = sqlite3_realloc64(S->val, c * sizeof *t); if (!t) return SQLITE_NOMEM; S->val = t; S->cval = c; }
  for (size_t k = 0; k < nv; k++) {   /* (one pass: a text or blob value keeps its offset in buf, which may still move) */
    QcVal *o = &S->val[k]; *o = x[k];
    if (o->type == SQLITE_TEXT || o->type == SQLITE_BLOB) {
      size_t n = (size_t)o->n;
      if (nb + n + 1 > S->cbuf) { size_t c = (nb + n + 1) * 2 + 64; char *t = sqlite3_realloc64(S->buf, c); if (!t) return SQLITE_NOMEM; S->buf = t; S->cbuf = c; }
      if (n) memcpy(S->buf + nb, o->z, n);
      S->buf[nb + n] = 0; o->i = (i64)nb; nb += n + 1;
    }
  }
  S->nrow = nrow; S->ncol = ncol;
  return SQLITE_OK;
}
static void qc_serve_start(Vdbe *v) {   /* sqlite3QcStart (v is READY, the connection's mutex is held) */
  sqlite3 *db = v->db; QcServe *S = v->pQcRows;
  v->qcServe = 0; if (S) S->ready = 0;
  if (qc_serving) return;
  if (!v->readOnly || !v->zSql) { v->qcNo = 1; return; }   /* (for good: fixed for this program) */
  if (v->explain || v->expired || db->xProgress || db->mTrace || v->nResColumn == 0) return;
  int ok = v->pQc != 0;
  if (!ok) { qc_serving = 1; sqlite3BtreeEnterAll(db); ok = qc_lift(v); sqlite3BtreeLeaveAll(db); qc_serving = 0; }
  if (!ok) { v->qcNo = 1; return; }   /* refused: not tried again until a re-prepare (a schema change) gives a new program */
  if (!S) { if (!(S = sqlite3MallocZero(sizeof *S))) return; v->pQcRows = S; }
  qc_serving = 1;
  if (S->nmem < v->nResColumn) {
    Mem *m = sqlite3_realloc64(S->mem, sizeof *m * (u64)v->nResColumn); if (!m) { qc_serving = 0; return; }
    for (int i = S->nmem; i < v->nResColumn; i++) sqlite3VdbeMemInit(&m[i], db, MEM_Null);
    S->mem = m; S->nmem = v->nResColumn;
  }
  S->nrow = 0;
  int rc = sqlite3_qc_exec((sqlite3_stmt *)v, qc_serve_rows, S);
  qc_serving = 0;
  if (rc == SQLITE_OK && S->ncol == v->nResColumn) { S->ready = 1; S->pos = 0; v->qcServe = 1; }
  else if (rc != QC_FALLBACK) sqlite3_reset((sqlite3_stmt *)v);   /* (an error in qc's own run: the statement starts afresh in the interpreter) */
}
static int qc_serve_step(Vdbe *p) {   /* sqlite3QcServe: in sqlite3Step, in place of sqlite3VdbeExec */
  QcServe *S = p->pQcRows;
  if (!S || qc_serving) { p->qcServe = 0; return sqlite3VdbeExec(p); }   /* (sqlite3Step calls this only while qcServe is set) */
  if (p->pc == 0) {   /* a fresh run: the rows qc_serve_start kept, if any */
    if (!S->ready) { S->active = 0; p->qcServe = 0; return sqlite3VdbeExec(p); }
    S->ready = 0; S->active = 1; S->pos = 0; p->pc = 1;   /* (pc 1: being served; sqlite3Step sets 0 at every start) */
  } else if (!S->active || p->pc != 1) { p->qcServe = 0; return sqlite3VdbeExec(p); }
  if (S->pos < S->nrow) {
    const QcVal *x = &S->val[(size_t)S->pos * (size_t)S->ncol]; Mem *m = S->mem; char *b = S->buf;
    for (int i = 0, nc = S->ncol; i < nc; i++, m++) {   /* (m->db is the connection's since sqlite3VdbeMemInit) */
      if (VdbeMemDynamic(m)) vdbeMemClearExternAndSetNull(m);
      m->enc = SQLITE_UTF8;   /* (column_text16 may have translated it) */
      switch (x[i].type) {
        case SQLITE_INTEGER: m->flags = MEM_Int; m->u.i = x[i].i; break;
        case SQLITE_FLOAT: m->flags = MEM_Real; m->u.r = x[i].r; break;
        case SQLITE_TEXT: m->flags = MEM_Str | MEM_Static | MEM_Term; m->z = b + x[i].i; m->n = x[i].n; break;
        case SQLITE_BLOB: m->flags = MEM_Blob | MEM_Static; m->z = b + x[i].i; m->n = x[i].n; break;
        default: m->flags = MEM_Null;
      }
    }
    S->pos++;
    p->pResultRow = S->mem;
    return SQLITE_ROW;
  }
  S->active = 0; p->qcServe = 0;   /* done: halted as OP_Halt halts it */
  p->rc = SQLITE_OK; p->errorAction = OE_Abort;
  int rc = sqlite3VdbeHalt(p);
  if (rc == SQLITE_BUSY) { p->rc = SQLITE_BUSY; return SQLITE_BUSY; }
  return p->rc ? SQLITE_ERROR : SQLITE_DONE;
}
SQLITE_API void sqlite3_qc_serve(int on) { sqlite3QcStart = on ? qc_serve_start : 0; sqlite3QcServe = on ? qc_serve_step : 0; }
#ifndef QC_SERVE_DEFAULT
#define QC_SERVE_DEFAULT 0
#endif
__attribute__((constructor)) static void qc_serve_init(void) {   /* QC_SERVE=1 / 0 at startup, else QC_SERVE_DEFAULT */
  const char *e = getenv("QC_SERVE"); int on = e ? *e == '1' : QC_SERVE_DEFAULT;
  if (on) { sqlite3QcFree = qc_free; sqlite3QcTxnEnd = qc_txn_end_all; sqlite3QcClose = qv_cache_close; sqlite3_qc_serve(1); }
}
/* sqlite3QcFree: a statement's program is being deleted (finalize, or the old program of a re-prepare) */
static void qc_free(Vdbe *v) {
  void *P = v->pQc; v->pQc = 0;
  if (P) { int k = *(int *)P; if (k == 1) qc_free_special(P); else if (qv_cache_put(v, P)) {} else if (k == 2) qg_free(P, v->db); else qv_free(P); }   /* (general and qvm plans go to the plan cache) */
  sqlite3_free(v->pQcTmpl); v->pQcTmpl = 0;
  qc_serve_free(v);
}
/* QC_STATS=1: the counts so far, to stderr (also at exit) */
static void qc_st_print_why(const char *what, const QcWhy *w) {
  for (int i = 0; i < 64 && w[i].why; i++) fprintf(stderr, "qc stats: %s %-28s %llu\n", what, w[i].why, w[i].n);
}
static void qc_st_print(void) {
  if (!QC_ST) return;
  fprintf(stderr, "qc stats: exec special %llu general %llu qvm %llu none %llu; ok %llu\n",
          qcs.exec[1], qcs.exec[2], qcs.exec[3], qcs.exec[0], qcs.ok);
  fprintf(stderr, "qc stats: lifts %llu (ok %llu); lifts on execution %llu (failed %llu); cache hits %llu misses %llu; nodes widened %llu\n",
          qcs.lift, qcs.liftOk, qcs.relift, qcs.reliftFail, qv_cache_hits, qv_cache_misses, qcs.widen);
  fprintf(stderr, "qc stats: against the interpreter: %llu samples; kept %llu (cheap %llu); parked %llu, unparked %llu\n",
          qcs.sample, qcs.keep, qcs.cheap, qcs.park, qcs.unpark);
  qc_st_print_why("fallback", qcs.fb); qc_st_print_why("no lift ", qcs.lf);
  static const char *K[2] = {"column ", "compare"};
  for (int k = 0; k < 2; k++)
    for (int m = 1; m < 32; m++) if (qcs.mask[k][m])
      fprintf(stderr, "qc stats: mask %s %s%s%s%s%s %llu\n", K[k], m & QV_FB_NULL ? "n" : "", m & QV_FB_INT ? "i" : "",
              m & QV_FB_REAL ? "r" : "", m & QV_FB_TEXT ? "t" : "", m & QV_FB_BLOB ? "b" : "", qcs.mask[k][m]);
}
SQLITE_API void sqlite3_qc_stats(void) { qc_st_print(); }
/* the memory qc keeps between executions (run state, arenas, cursor pools), for a leak check at shutdown */
SQLITE_API void sqlite3_qc_release(void) { qv_cache_release(); sqlite3_free(qc_run_r); qc_run_r = 0; qg_release(); qv_release(); }

/* compile a prepared statement: the specialised feed-shaped plan first, then a general plan. 1 = compiled */
static int qc_lift(Vdbe *v);
SQLITE_API int sqlite3_qc(sqlite3_stmt *pStmt) {   /* (under the connection's locks, as sqlite3_qc_exec) */
  Vdbe *v = (Vdbe *)pStmt; if (!v || !v->db) return 0;
  sqlite3 *db = v->db; sqlite3_mutex_enter(db->mutex); sqlite3BtreeEnterAll(db);
  int ok = qc_lift(v);
  sqlite3BtreeLeaveAll(db); sqlite3_mutex_leave(db->mutex);
  return ok;
}
static int qc_lift_do(Vdbe *v);
static void qc_st_print(void);
static int qc_lift(Vdbe *v) {
  if (qcs.on < 0) { qcs.on = getenv("QC_STATS") != 0; if (QC_ST) atexit(qc_st_print); }
  qc_why = "";
  int ok = qc_lift_do(v);
  if (QC_ST) { qcs.lift++; if (ok) qcs.liftOk++; else qc_st_why(qcs.lf, *qc_why ? qc_why : "lift"); }
  return ok;
}
/* every field of a program, P4's values too (pointers only where they name a schema object or a built-in, the same in
   two prepares on one connection); 0: a P4 not compared (a subprogram, an expression, a vtab) */
static u64 qc_prog_mix(u64 h, u64 w) { h = (h ^ w) * 0xff51afd7ed558ccdull; return h ^ (h >> 31); }
static u64 qc_prog_hash(const Vdbe *v) {
  u64 h = 0x9e3779b97f4a7c15ull ^ (u64)v->nOp;
  for (int pc = 0; pc < v->nOp; pc++) {
    const Op *o = &v->aOp[pc];
    h = qc_prog_mix(h, (u64)o->opcode | (u64)(u8)o->p4type << 8 | (u64)o->p5 << 16);
    h = qc_prog_mix(h, (u64)(u32)o->p1 | (u64)(u32)o->p2 << 32); h = qc_prog_mix(h, (u64)(u32)o->p3);
    switch (o->p4type) {
      case P4_NOTUSED: break;
      case P4_INT32: h = qc_prog_mix(h, (u64)(u32)o->p4.i); break;
      case P4_STATIC: case P4_DYNAMIC: { const char *z = o->p4.z; size_t n = z ? strlen(z) : 0; h = qc_prog_mix(h, n);
        for (size_t i = 0; i < n; i++) h = qc_prog_mix(h, (u8)z[i]); break; }
      case P4_COLLSEQ: case P4_TABLE: case P4_INDEX: case P4_FUNCDEF: h = qc_prog_mix(h, (u64)(uintptr_t)o->p4.p); break;
      case P4_FUNCCTX: h = qc_prog_mix(h, (u64)(uintptr_t)o->p4.pCtx->pFunc); h = qc_prog_mix(h, (u64)o->p4.pCtx->argc); break;
      case P4_KEYINFO: { const KeyInfo *k = o->p4.pKeyInfo; h = qc_prog_mix(h, (u64)k->nKeyField | (u64)k->nAllField << 16 | (u64)k->enc << 32);
        for (int i = 0; i < k->nAllField; i++) { h = qc_prog_mix(h, (u64)(uintptr_t)k->aColl[i]); h = qc_prog_mix(h, k->aSortFlags[i]); } break; }
      case P4_MEM: { const Mem *m = o->p4.pMem; h = qc_prog_mix(h, m->flags);
        if (m->flags & (MEM_Int | MEM_IntReal)) h = qc_prog_mix(h, (u64)m->u.i);
        else if (m->flags & MEM_Real) { u64 w; memcpy(&w, &m->u.r, 8); h = qc_prog_mix(h, w); }
        else if (m->flags & (MEM_Str | MEM_Blob)) { if (m->flags & MEM_Zero) return 0; h = qc_prog_mix(h, (u64)m->n); for (int i = 0; i < m->n; i++) h = qc_prog_mix(h, (u8)m->z[i]); }
        break; }
      default: return 0;
    }
  }
  return h | 1;
}
/* A statement whose plan looked at a binding (expmask: a LIKE pattern, a bound LIMIT, a 0/1 integer) is re-prepared at
   each new binding, by stock too. Once per text, qc re-prepares it under QPSG's rule (a plan that looks at no binding):
   that program is kept as a hash, and whenever SQLite's own program for the text is that one to the last field (now, or
   at a later re-prepare: one that baked a bound LIMIT in differs) no binding changes it, and expmask is cleared. A
   different program is discarded for SQLite's own (a re-prepare): kept, it could be far worse (bench's corpus, claude-mem's observations_newest_per_key 7.95x stock). bench,
   vaultwarden orgs_with_full_access (access_all = ?3, bound 1): a re-prepare every run, 1.044x stock on x86. */
typedef struct QcQpsg { sqlite3 *db; u32 h; u64 prog; } QcQpsg;   /* prog: the QPSG program's qc_prog_hash */
static QcQpsg qc_qpsg_seen[256];
static void qc_qpsg(Vdbe *v) {
  sqlite3 *db = v->db; int n = (int)strlen(v->zSql); u32 th = qv_hash(v->zSql, n); QcQpsg *e = &qc_qpsg_seen[th & 255];
  u64 ph = qc_prog_hash(v); if (!ph) return;
  if (e->db == db && e->h == th) { if (e->prog == ph) v->expmask = v->smimask = 0; return; }
  u64 f = db->flags; db->flags |= SQLITE_EnableQPSG; int rc = sqlite3Reprepare(v); db->flags = f;
  if (rc != SQLITE_OK) return;
  u64 q = qc_prog_hash(v); if (!q) return;
  *e = (QcQpsg){db, th, q};
  if (q == ph) { v->expmask = v->smimask = 0; return; }   /* (sqlite3VdbeSwap carries the old masks over) */
  sqlite3Reprepare(v);   /* SQLite's own plan back */
}
static int qc_lift_do(Vdbe *v) {
  if (!v || v->pQc || v->explain || ENC(v->db) != SQLITE_UTF8) return 0;
  v->qcWant = 1;   /* lifted again after a re-prepare */
  sqlite3QcTxnEnd = qc_txn_end_all; sqlite3QcFree = qc_free; sqlite3QcClose = qv_cache_close;
  if (v->expmask && v->aCounter[SQLITE_STMTSTATUS_REPREPARE] >= 2 && v->zSql && !(v->db->flags & SQLITE_EnableQPSG) && v->eVdbeState == VDBE_READY_STATE)
    qc_qpsg(v);   /* (a handle bound again and again: a fresh prepare's first binding re-prepares it once, by stock too, and a handle bound once never again) */
  static int onlyVm = -1;   /* QC_VM_ONLY=1 (tests): every statement through the general executor */
  if (onlyVm < 0) onlyVm = getenv("QC_VM_ONLY") != 0;
  if (qv_cache_get(v)) return 1;   /* this text's plan, kept from an earlier prepare whose program had the same signature */
  if (qv_neg_get(v)) return 0;     /* refused before: qc_why is why */
  {   /* a program that opens no cursor (a constant SELECT, SELECT of parameters or functions): the interpreter's, as a
         lift and a plan cost more than such a statement does (speedtest1's parsenumber tests: one-shot constant SELECTs) */
    int any = 0;
    for (int pc = 0; pc < v->nOp && !any; pc++) switch (v->aOp[pc].opcode) {
      case OP_OpenRead: case OP_ReopenIdx: case OP_OpenEphemeral: case OP_OpenAutoindex: case OP_SorterOpen: case OP_OpenPseudo: case OP_OpenDup: any = 1;
    }
    if (!any) { qc_why = "no table"; return 0; }
  }
  if (!onlyVm) {
    if (qc_lift_special(v)) return 1;
    if (qc_lift_general(v)) return 1;
  }
  if (qv_lift(v)) return 1;   /* any other read-only program */
  qv_neg_put(v, *qv_why ? qv_why : *qc_why ? qc_why : "refused");
  return 0;
}
static int qc_exec_locked(Vdbe *v, qc_row_cb cb, void *ctx);
static int qc_exec_plan(Vdbe *v, qc_row_cb cb, void *ctx);
static int qc_adapt_on(void);
static int qc_adapt(Vdbe *v, qc_row_cb cb, void *ctx);
/* as sqlite3_step: under the connection's mutex and its B-trees' (shared cache), which are no-ops when SQLite is
   built single-threaded. qc's own run state is per process: one thread at a time runs qc. */
SQLITE_API int sqlite3_qc_exec(sqlite3_stmt *pStmt, qc_row_cb cb, void *ctx) {
  Vdbe *v = (Vdbe *)pStmt; if (!v || !v->db) return QC_FALLBACK;
  sqlite3 *db = v->db; sqlite3_mutex_enter(db->mutex); sqlite3BtreeEnterAll(db);
  if (v->eVdbeState == VDBE_READY_STATE) v->iCurrentTime = 0;   /* as sqlite3Step at a start: 'now' is read afresh once per run
                                                                  (left alone, a new statement read uninitialised memory) */
  /* in autocommit, the read transaction a read-only program needs is begun here and ended after the run, on the
     B-trees that had none, as vdbe.c's OP_Transaction and Halt do: no BEGIN and COMMIT statements around every call
     (a point lookup through a drop-in wrapper: two extra statement runs per lookup) */
  Btree *own[8]; int nown = 0, rc;
  if (db->autoCommit && v->readOnly && v->eVdbeState == VDBE_READY_STATE) {
    int ok = 1, t = v->aOp[0].opcode == OP_Init ? v->aOp[0].p2 : v->nOp;
    if (v->pQc && t + 1 < v->nOp && v->aOp[t].opcode == OP_Transaction && v->aOp[t + 1].opcode != OP_Transaction) {
      /* a lifted program: every tier takes exactly one OP_Transaction, the Init block's, so no scan of the program */
      const Op *o = &v->aOp[t]; Btree *bt = o->p1 >= 0 && o->p1 < db->nDb ? db->aDb[o->p1].pBt : 0;
      if (!bt || o->p2 != 0) ok = 0;
      else if (sqlite3BtreeTxnState(bt) == SQLITE_TXN_NONE) { if (sqlite3BtreeBeginTrans(bt, 0, 0) != SQLITE_OK) ok = 0; else own[nown++] = bt; }
    } else for (int pc = 0; pc < v->nOp && ok; pc++) {
      const Op *o = &v->aOp[pc]; if (o->opcode != OP_Transaction) continue;
      Btree *bt = o->p1 >= 0 && o->p1 < db->nDb ? db->aDb[o->p1].pBt : 0;
      if (!bt || o->p2 != 0 || nown == 8) { ok = 0; break; }
      if (sqlite3BtreeTxnState(bt) == SQLITE_TXN_NONE) {
        if (sqlite3BtreeBeginTrans(bt, 0, 0) != SQLITE_OK) { ok = 0; break; }
        own[nown++] = bt;
      }
    }
    if (!ok) { for (int i = 0; i < nown; i++) sqlite3BtreeCommit(own[i]); nown = 0; qc_why = "txn"; rc = QC_FALLBACK; goto done; }
    qc_own_txn = 1;
  }
  rc = qc_exec_locked(v, cb, ctx);
  qc_own_txn = 0;
  for (int i = 0; i < nown; i++) sqlite3BtreeCommit(own[i]);   /* (a read transaction: its locks released, qc's cursors closed by the end hook) */
done:
  if (QC_ST) {
    qcs.exec[v->pQc ? *(int *)v->pQc & 3 : 0]++;
    if (rc == QC_FALLBACK) qc_st_why(qcs.fb, *qc_why ? qc_why : "?"); else qcs.ok++;
  }
  sqlite3BtreeLeaveAll(db); sqlite3_mutex_leave(db->mutex);
  return rc;
}
static int qc_exec_locked(Vdbe *v, qc_row_cb cb, void *ctx) {
  qc_why = "";
  if (!v->pQc && v->qcWant && v->eVdbeState == VDBE_READY_STATE && !v->expired) {   /* re-prepared (the locks are held) */
    int ok = qc_lift(v);
    if (QC_ST) { qcs.relift++; if (!ok) qcs.reliftFail++; }
    if (!ok) { if (!*qc_why) qc_why = "lift"; return QC_FALLBACK; }
  }
  if (!v->pQc) return QC_FB("no plan");
  int k = *(int *)v->pQc;
  if (k != 1 && cb && v->eVdbeState == VDBE_READY_STATE && qc_adapt_on()) return qc_adapt(v, cb, ctx);
  return qc_exec_plan(v, cb, ctx);
}
static int qc_exec_plan(Vdbe *v, qc_row_cb cb, void *ctx) {
  int k = *(int *)v->pQc;
  if (k == 2) {
    int st = qg_exec(v, v->pQc, cb, ctx);
    if (st != QG_DEMOTE) return st;
    qg_free(v->pQc, v->db); v->pQc = 0;   /* more rows than a general plan buffers: qvm has no such limit */
    if (!qv_lift(v)) return QC_FALLBACK;
    return qv_exec(v, v->pQc, cb, ctx);
  }
  if (k == 1) {
    int st = qc_exec_special(v, cb, ctx);
    if (st != QG_DEMOTE) return st;
    qc_free_special(v->pQc); v->pQc = 0;   /* a memory-mapped database: qvm */
    if (!qv_lift(v)) return QC_FALLBACK;
    return qv_exec(v, v->pQc, cb, ctx);
  }
  return qv_exec(v, v->pQc, cb, ctx);
}
/* The statement run by SQLite's interpreter, here, with its rows handed to cb as a plan hands them (copied out of the
   interpreter's registers): qc_adapt's other arm. Any error: QC_FALLBACK before a row is handed out, and the caller
   steps the statement again, which reports it */
static int qc_interp_rows(Vdbe *v, qc_row_cb cb, void *ctx) {
  sqlite3_stmt *s = (sqlite3_stmt *)v; int nc = v->nResColumn, rc, st = QC_FALLBACK;
  QcVal *val = 0; char *buf = 0; size_t nv = 0, cv = 0, nb = 0, cb_ = 0;
  while ((rc = sqlite3Step(v)) == SQLITE_ROW) {
    if (nv + (size_t)nc > cv) { cv = cv ? cv * 2 : (size_t)nc * 64; QcVal *t = sqlite3_realloc64(val, cv * sizeof *val); if (!t) goto out; val = t; }
    for (int i = 0; i < nc; i++) {
      QcVal *o = &val[nv++]; int t = sqlite3_column_type(s, i); o->type = t; o->n = 0; o->i = 0;
      if (t == SQLITE_INTEGER) o->i = sqlite3_column_int64(s, i);
      else if (t == SQLITE_FLOAT) o->r = sqlite3_column_double(s, i);
      else if (t == SQLITE_TEXT || t == SQLITE_BLOB) {
        const void *z = t == SQLITE_TEXT ? (const void *)sqlite3_column_text(s, i) : sqlite3_column_blob(s, i);
        int n = sqlite3_column_bytes(s, i);
        if (nb + (size_t)n > cb_) { cb_ = (nb + (size_t)n) * 2 + 256; char *b = sqlite3_realloc64(buf, cb_); if (!b) goto out; buf = b; }
        if (n) memcpy(buf + nb, z, (size_t)n);
        o->i = (i64)nb; o->n = n; nb += (size_t)n;   /* (an offset until the buffer stops moving) */
      }
    }
  }
  if (rc != SQLITE_DONE) goto out;
  for (size_t i = 0; i < nv; i++) if (val[i].type == SQLITE_TEXT || val[i].type == SQLITE_BLOB) val[i].z = (const u8 *)buf + val[i].i;
  st = cb(ctx, nc ? (int)(nv / (size_t)nc) : 0, nc, val);
out:
  sqlite3_reset(s);
  sqlite3_free(val); sqlite3_free(buf);
  if (st == QC_FALLBACK) qc_why = "sample";
  return st;
}
/* Is the plan faster than SQLite's interpreter? A general or qvm plan run with a row callback is measured: after its
   first QC_ADAPT_WARM executions (type feedback, regions), one execution is timed. A plan under QC_ADAPT_MIN_US µs is
   kept without more measurement (and timed again after 256 executions, in case its data grew). Otherwise the next
   executions alternate between four timed runs of the plan and four of the interpreter (qc_interp_rows); two
   interpreter runs both over 1.25 times the slowest plan run end it early. If the interpreter's median is more than
   5 % faster and each of its runs beats the plan's median, the statement is parked: QC_FALLBACK ("parked": the
   caller steps it) for the next 64 × 2^R executions, then measured again; after 10 parks it stays parked. A kept plan
   is measured again after 256 × 2^K executions (K up to 8). The state belongs to the plan, so it survives the plan
   cache. QC_NOADAPT=1: off */
#ifndef QC_ADAPT_WARM
#define QC_ADAPT_WARM 3
#endif
#ifndef QC_ADAPT_MIN_US
#define QC_ADAPT_MIN_US 50
#endif
enum { QA_LEARN, QA_KEEP, QA_PARK };
static int qc_adapt_on(void) { static int on = -1; if (on < 0) on = getenv("QC_NOADAPT") == 0; return on; }
static double qc_now_us(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (double)t.tv_sec * 1e6 + (double)t.tv_nsec / 1e3; }
static double qc_med4(const double *a) {
  double s[4]; memcpy(s, a, sizeof s);
  for (int i = 1; i < 4; i++) for (int j = i; j > 0 && s[j] < s[j - 1]; j--) { double t = s[j]; s[j] = s[j - 1]; s[j - 1] = t; }
  return (s[1] + s[2]) / 2;
}
static int qc_adapt(Vdbe *v, qc_row_cb cb, void *ctx) {
  QcAdapt *A = *(int *)v->pQc == 2 ? &((QcGPlan *)v->pQc)->ad : &((QvPlan *)v->pQc)->ad;
  A->n++;
  if (A->st == QA_PARK) {
    if (A->n < A->next) return QC_FB("parked");
    A->st = QA_LEARN; A->nq = A->ni = 0; if (QC_ST) qcs.unpark++;
  } else if (A->st == QA_KEEP) {
    if (A->n < A->next) return qc_exec_plan(v, cb, ctx);
    A->st = QA_LEARN; A->nq = A->ni = 0;
  }
  if (A->n <= QC_ADAPT_WARM) return qc_exec_plan(v, cb, ctx);
  if (A->nq > A->ni) {   /* the interpreter's turn */
    double t = qc_now_us(); int st = qc_interp_rows(v, cb, ctx); t = qc_now_us() - t;
    if (st == QC_FALLBACK) return st;
    A->ti[A->ni++] = t; if (QC_ST) qcs.sample++;
    double qmax = 0, imin = 1e300, imax = 0;
    for (int j = 0; j < A->nq; j++) if (A->tq[j] > qmax) qmax = A->tq[j];
    for (int j = 0; j < A->ni; j++) { if (A->ti[j] < imin) imin = A->ti[j]; if (A->ti[j] > imax) imax = A->ti[j]; }
    if (A->ni == 2 && imin > qmax * 1.25) A->ni = 4, imax = 0, imin = 1e300;   /* clearly slower: keep the plan now */
    if (A->ni == 4) {
      double q = qc_med4(A->tq), i = imin > imax ? 1e300 : qc_med4(A->ti);
      if (i * 1.05 < q && imax < q) {   /* faster by 5 % in the median, and every interpreter run under the plan's median */
        A->st = QA_PARK; if (A->R < 255) A->R++;
        A->next = A->R >= 10 ? ~0u : A->n + (64u << (A->R - 1)); if (QC_ST) qcs.park++;   /* (the R-th park: 64 x 2^(R-1) executions; the 10th for good) */
      } else {
        A->st = QA_KEEP; A->next = A->n + (256u << (A->K < 8 ? A->K : 8)); if (A->K < 255) A->K++;
        if (QC_ST) qcs.keep++;
      }
    }
    return st;
  }
  void *P0 = v->pQc;
  double t = qc_now_us(); int st = qc_exec_plan(v, cb, ctx); t = qc_now_us() - t;
  if (st == QC_FALLBACK || v->pQc != P0) return st;   /* (a general plan that demoted to qvm was freed with its state) */
  if (A->nq == 0 && t < QC_ADAPT_MIN_US) { A->st = QA_KEEP; A->next = A->n + 256; if (QC_ST) qcs.cheap++; return st; }
  A->tq[A->nq++] = t;
  return st;
}
