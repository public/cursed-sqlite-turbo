/* qcg.c: qc's general plans. #included by qc.c after its specialised (feed-shaped) plans.
**
** The lifter reads a SELECT's bytecode as the loop nest SQLite's planner emitted:
**   level   an access path on one cursor: a scan (Rewind/Last), a seek with an optional end test (Seek{GE,GT,LE,LT} +
**           Idx{GT,GE,LT,LE} on an index, or Rowid + Gt/Ge/Lt/Le on a table), or a rowid point (SeekRowid). The level
**           closes with Next/Prev on its cursor; that address is where "skip this row" jumps go. A DeferredSeek binds
**           the table row behind an index cursor.
**   body    Column / Rowid / IdxRowid / Copy into symbolic registers, filters (compare ops and IsNull/NotNull jumping
**           to a level's continue address), nested levels (joins), and either ResultRow or AggStep.
**   tail    DecrJumpZero (LIMIT); for aggregates, AggFinal + Copy + ResultRow after the loops.
** Seeks and end tests run exactly as vdbe.c runs them (sqlite3BtreeIndexMoveto / TableMoveto with the opcode's
** default_rc and Next/Previous fix-up; sqlite3VdbeRecordCompareWithSkip for Idx* end tests). Values are decoded from
** the records directly. Anything the bytecode would have converted (a key of the wrong type for its affinity, a
** mixed-type comparison, a non-BINARY collation, an overflow record, too many rows) returns QC_FALLBACK before any row
** is handed out. */

#define QG_MAXLVL 4
#define QG_MAXKEY 6
#define QG_MAXFILT 8
#define QG_MAXROWS 256
#define QG_MAXAGG 4

enum { G_NONE, G_PARAM, G_INT, G_NULL, G_TEXT, G_ADD, G_SUB, G_COL, G_ROWID, G_AGG };
typedef struct GSym { u8 kind; i8 lvl; i16 col; i64 v; const char *z; int a, b; } GSym;   /* a,b: operands of G_ADD/G_SUB (indices into P->ex) */
enum { GL_SCAN = 1, GL_SEEK, GL_ROWID };
typedef struct GFilt { u8 op, p5, nulljump; GSym l, r; } GFilt;   /* skip the row when r <op> l (vdbe's P3 <op> P1) */
typedef struct GLevel {
  u8 kind, isIdx, dir, once;           /* dir: 1 Next, 0 Prev; once: no loop (at most one row) */
  int cur; Pgno root; KeyInfo *ki;
  u8 seekOp; int nkey; GSym key[QG_MAXKEY]; char aff[QG_MAXKEY + 1]; u8 keyNullExit;   /* IsNull on a key: no rows */
  u8 endOp; int nend; GSym end[QG_MAXKEY];        /* index end test: OP_IdxGT..; table end test: OP_Gt.. against the rowid */
  u8 endP5;
  GSym rowidKey;                                   /* GL_ROWID */
  int tabCur; Pgno tabRoot;                        /* DeferredSeek: the table row behind this index cursor, or -1 */
  int nfilt; GFilt filt[QG_MAXFILT];
  int head, cont, exitPc;                          /* addresses (lifter only) */
  u32 needTab, needIdx;                            /* columns decoded from the table / index record */
  QcShape tabShape, idxShape; int (*tabDec)(const u8 *, u32, QcVal *), (*idxDec)(const u8 *, u32, QcVal *);
} GLevel;
typedef struct GAgg { u8 fn; GSym arg; int reg; } GAgg;   /* fn: 1 count(*), 2 min, 3 max */
typedef struct QcGPlan {
  int kind;                                        /* QC_KIND_GENERAL */
  int iDb, cookie, gen;
  int nlvl; GLevel lvl[QG_MAXLVL];
  int nout; GSym out[QC_MAXOUT];
  int nagg; GAgg agg[QG_MAXAGG];
  int hasLimit; GSym limit;
  int nex; GSym ex[16];                            /* operands of computed values */
  int ncur; struct { int cur; Pgno root; KeyInfo *ki; int lvl; u8 isTab; } curs[QG_MAXLVL * 2];
  Btree *bt; BtCursor *bc[QG_MAXLVL * 2]; u8 bopen[QG_MAXLVL * 2]; u8 txnChecked;
  UnpackedRecord *uk[QG_MAXLVL];
} QcGPlan;

static QcGPlan *qg_plans[64]; static int qg_nplans;
static void qg_txn_end(Btree *bt) {
  for (int k = 0; k < qg_nplans; k++) {
    QcGPlan *P = qg_plans[k]; if (P->bt != bt) continue;
    P->txnChecked = 0;
    for (int c = 0; c < P->ncur; c++) if (P->bopen[c]) { sqlite3BtreeCloseCursor(P->bc[c]); P->bopen[c] = 0; }
  }
}

/* ---------------------------------------------------------------- lifter */
#define QG_REFUSE(why) do { qc_why = (why); return 0; } while (0)
static int qg_curslot(QcGPlan *P, int cur) { for (int k = 0; k < P->ncur; k++) if (P->curs[k].cur == cur) return k; return -1; }
static int qg_value_sym(const GSym *s) { return s->kind == G_PARAM || s->kind == G_INT || s->kind == G_NULL || s->kind == G_TEXT || s->kind == G_ADD || s->kind == G_SUB; }
static int qg_row_sym(const GSym *s) { return s->kind == G_COL || s->kind == G_ROWID; }

static int qc_lift_general(Vdbe *v) {
  Op *aOp = v->aOp; int nOp = v->nOp, nMem = v->nMem;
  if (nMem > 255) QG_REFUSE("registers");
  QcGPlan P; memset(&P, 0, sizeof P); P.kind = 2; P.iDb = -1;
  GSym reg[256]; memset(reg, 0, sizeof reg);
  int lvlOfCur[64]; for (int k = 0; k < 64; k++) lvlOfCur[k] = -1;   /* cursor -> level (index or table cursor of it) */
  int tabOfCur[64]; for (int k = 0; k < 64; k++) tabOfCur[k] = 0;
  /* init block: Transaction, then constants, then Goto 1 */
  if (aOp[0].opcode != OP_Init) QG_REFUSE("init");
  int t = aOp[0].p2, ntx = 0;
  for (; t < nOp; t++) {
    Op *o = &aOp[t];
    if (o->opcode == OP_Transaction) {
      if (o->p2 != 0 || o->p5 != 1 || ntx++ || o->p4type != P4_INT32) QG_REFUSE("transaction");
      P.iDb = o->p1; P.cookie = o->p3; P.gen = o->p4.i;
    } else if (o->opcode == OP_Variable && o->p2 <= nMem) reg[o->p2] = (GSym){G_PARAM, 0, 0, o->p1};
    else if (o->opcode == OP_Integer && o->p2 <= nMem) reg[o->p2] = (GSym){G_INT, 0, 0, o->p1};
    else if (o->opcode == OP_Int64 && o->p2 <= nMem) reg[o->p2] = (GSym){G_INT, 0, 0, *(i64 *)o->p4.p};   /* P4_INT64 */
    else if (o->opcode == OP_Goto && o->p2 == 1) break;
    else QG_REFUSE("init op");
  }
  if (!ntx || t >= nOp) QG_REFUSE("preamble");
  int endInit = aOp[0].p2;
  /* main section: setup, levels, body, tail */
  int depth = 0;           /* open levels */
  int aggMode = 0, haveOut = 0, haltPc = -1, limitPc = -1, aggEndPc = -1;
  for (int pc = 1; pc < endInit; pc++) {
    Op *o = &aOp[pc];
    switch (o->opcode) {
      case OP_Noop: break;
      case OP_Integer: if (o->p2 > nMem) QG_REFUSE("reg"); reg[o->p2] = (GSym){G_INT, 0, 0, o->p1}; break;
      case OP_Variable: if (o->p2 > nMem) QG_REFUSE("reg"); reg[o->p2] = (GSym){G_PARAM, 0, 0, o->p1}; break;
      case OP_Null:
        if (o->p1 != 0 || o->p3 > nMem) QG_REFUSE("null");
        for (int r = o->p2; r <= (o->p3 > o->p2 ? o->p3 : o->p2); r++) reg[r] = (GSym){G_NULL};
        break;
      case OP_OpenRead: {
        if (o->p1 < 0 || o->p1 >= 64 || o->p3 != P.iDb || (o->p5 & ~OPFLAG_SEEKEQ) || P.ncur >= QG_MAXLVL * 2 ||
            (o->p4type != P4_INT32 && o->p4type != P4_KEYINFO)) QG_REFUSE("openread");
        int k = P.ncur++; P.curs[k].cur = o->p1; P.curs[k].root = (Pgno)o->p2; P.curs[k].ki = o->p4type == P4_KEYINFO ? o->p4.pKeyInfo : 0;
        P.curs[k].lvl = -1; P.curs[k].isTab = o->p4type != P4_KEYINFO;
        if (P.curs[k].ki && (P.curs[k].ki->nAllField > QG_MAXKEY + 2)) QG_REFUSE("wide index");
        break;
      }
      case OP_IsNull: {   /* before a seek: a NULL key means no rows at that level */
        Op *n = o + 1; while (n < aOp + endInit && (n->opcode == OP_Affinity || n->opcode == OP_Variable)) n++;
        if (!(n->opcode >= OP_SeekLT && n->opcode <= OP_SeekGT) || o->p2 != n->p2) QG_REFUSE("isnull");
        break;   /* recorded when the seek is parsed (keyNullExit) */
      }
      case OP_Affinity: break;   /* recorded when the seek is parsed */
      case OP_Add: case OP_Subtract: {
        if (!qg_value_sym(&reg[o->p1]) || !qg_value_sym(&reg[o->p2]) || P.nex + 2 > 16) QG_REFUSE("expr");
        int a = P.nex++, b = P.nex++; P.ex[a] = reg[o->p1]; P.ex[b] = reg[o->p2];   /* P3 = P2 + P1 / P2 - P1 */
        reg[o->p3] = (GSym){(u8)(o->opcode == OP_Add ? G_ADD : G_SUB), 0, 0, 0, 0, b, a};
        break;
      }
      case OP_Rewind: case OP_Last:
      case OP_SeekGE: case OP_SeekGT: case OP_SeekLE: case OP_SeekLT:
      case OP_SeekRowid: {
        int k = qg_curslot(&P, o->p1);
        if (k < 0 || depth >= QG_MAXLVL || aggMode || haveOut) QG_REFUSE("level");
        GLevel *L = &P.lvl[P.nlvl]; memset(L, 0, sizeof *L);
        L->cur = o->p1; L->root = P.curs[k].root; L->ki = P.curs[k].ki; L->isIdx = !P.curs[k].isTab; L->tabCur = -1;
        L->exitPc = o->p2;
        if (o->opcode == OP_SeekRowid) {
          if (L->isIdx || !qg_value_sym(&reg[o->p3]) && !qg_row_sym(&reg[o->p3])) QG_REFUSE("seekrowid key");
          L->kind = GL_ROWID; L->rowidKey = reg[o->p3]; L->head = pc + 1; L->cont = o->p2; L->dir = 1;
        } else if (o->opcode == OP_Rewind || o->opcode == OP_Last) {
          L->kind = GL_SCAN; L->head = pc + 1; L->dir = o->opcode == OP_Rewind;
        } else {
          L->kind = GL_SEEK; L->seekOp = (u8)o->opcode; L->head = pc + 1;
          L->dir = o->opcode == OP_SeekGE || o->opcode == OP_SeekGT;
          if (L->isIdx) {
            if (o->p4type != P4_INT32 || o->p4.i < 1 || o->p4.i > QG_MAXKEY) QG_REFUSE("seek keys");
            L->nkey = o->p4.i;
          } else L->nkey = 1;
          for (int j = 0; j < L->nkey; j++) {
            GSym s = reg[o->p3 + j];
            if (!qg_value_sym(&s) && !qg_row_sym(&s)) QG_REFUSE("seek key");
            L->key[j] = s;
          }
          /* affinity and IsNull applied to the key registers just before the seek */
          for (Op *q = o - 1; q > aOp && (q->opcode == OP_Affinity || q->opcode == OP_IsNull || q->opcode == OP_Variable); q--) {
            if (q->opcode == OP_IsNull && q->p1 >= o->p3 && q->p1 < o->p3 + L->nkey && q->p2 == o->p2) L->keyNullExit = 1;
            int strp4 = q->p4type == P4_STATIC || q->p4type == P4_DYNAMIC;
            if (q->opcode == OP_Affinity && q->p1 == o->p3 && q->p2 <= L->nkey && strp4) {
              for (int j = 0; j < q->p2; j++) L->aff[j] = q->p4.z[j];
            }
            if (q->opcode == OP_Affinity && (q->p1 != o->p3 || !strp4)) QG_REFUSE("affinity");
          }
          /* the end test right at the loop head */
          Op *h = &aOp[pc + 1];
          if (L->isIdx && h->opcode >= OP_IdxLE && h->opcode <= OP_IdxGE && h->p1 == o->p1 && h->p2 == o->p2) {
            if (h->p4type != P4_INT32 || h->p4.i < 1 || h->p4.i > QG_MAXKEY) QG_REFUSE("end keys");
            L->endOp = (u8)h->opcode; L->nend = h->p4.i;
            for (int j = 0; j < L->nend; j++) { GSym s = reg[h->p3 + j]; if (!qg_value_sym(&s) && !qg_row_sym(&s)) QG_REFUSE("end key"); L->end[j] = s; }
            L->head = pc + 1; pc++;   /* Next/Prev jumps back to the end test itself */
          } else if (!L->isIdx) {
            /* computed bounds may sit between the seek and the loop head (Add); then Rowid + Gt/Ge/Lt/Le */
            int q = pc + 1;
            while (aOp[q].opcode == OP_Add || aOp[q].opcode == OP_Subtract) {
              Op *e = &aOp[q];
              if (!qg_value_sym(&reg[e->p1]) || !qg_value_sym(&reg[e->p2]) || P.nex + 2 > 16) QG_REFUSE("expr");
              int a = P.nex++, b = P.nex++; P.ex[a] = reg[e->p1]; P.ex[b] = reg[e->p2];
              reg[e->p3] = (GSym){(u8)(e->opcode == OP_Add ? G_ADD : G_SUB), 0, 0, 0, 0, b, a}; q++;
            }
            if (aOp[q].opcode == OP_Rowid && aOp[q].p1 == o->p1 && aOp[q + 1].opcode >= OP_Gt && aOp[q + 1].opcode <= OP_Ge &&
                aOp[q + 1].p3 == aOp[q].p2 && aOp[q + 1].p2 == o->p2 && qg_value_sym(&reg[aOp[q + 1].p1])) {
              L->endOp = (u8)aOp[q + 1].opcode; L->end[0] = reg[aOp[q + 1].p1]; L->nend = 1; L->endP5 = aOp[q + 1].p5;
              L->head = q; pc = q + 1;   /* the Rowid at the head is re-read by the body if it uses it */
              reg[aOp[q].p2] = (GSym){G_ROWID, (i8)P.nlvl};
            } else L->head = q;
          }
        }
        /* the closer: the first Next/Prev on this cursor after the head that jumps back to the head. A seek on a
           UNIQUE index with every key column equal has none (at most one row): it runs once, like a point level */
        if (L->kind != GL_ROWID) {
          int c = -1;
          for (int q = L->head; q < endInit; q++)
            if ((aOp[q].opcode == OP_Next || aOp[q].opcode == OP_Prev) && aOp[q].p1 == o->p1) { c = q; break; }
          if (c < 0 && L->kind == GL_SEEK && L->isIdx && L->endOp) { L->once = 1; L->cont = L->exitPc; }
          else if (c < 0 || aOp[c].p2 != L->head || (aOp[c].opcode == OP_Next) != L->dir) QG_REFUSE("closer");
          else L->cont = c;
        }
        P.curs[k].lvl = P.nlvl; lvlOfCur[o->p1] = P.nlvl;
        P.nlvl++; depth++;
        break;
      }
      case OP_DeferredSeek: {
        int l = lvlOfCur[o->p1]; int k = qg_curslot(&P, o->p3);
        if (l < 0 || k < 0 || !P.curs[k].isTab || o->p4type != P4_NOTUSED || P.lvl[l].tabCur >= 0) QG_REFUSE("deferredseek");
        P.lvl[l].tabCur = o->p3; P.lvl[l].tabRoot = P.curs[k].root; P.curs[k].lvl = l; lvlOfCur[o->p3] = l; tabOfCur[o->p3] = 1;
        break;
      }
      case OP_Column: {
        int l = lvlOfCur[o->p1];
        if (l < 0 || o->p5 || o->p4type != P4_NOTUSED || o->p3 > nMem || o->p2 >= QC_MAXCOL) QG_REFUSE("column");
        GLevel *L = &P.lvl[l];
        if (L->isIdx && o->p1 == L->cur) reg[o->p3] = (GSym){G_COL, (i8)l, (i16)(o->p2 | 0x100)};   /* 0x100: a field of the index record */
        else if ((L->isIdx && o->p1 == L->tabCur) || (!L->isIdx && o->p1 == L->cur)) reg[o->p3] = (GSym){G_COL, (i8)l, (i16)o->p2};
        else QG_REFUSE("column cursor");
        break;
      }
      case OP_Rowid: case OP_IdxRowid: {
        int l = lvlOfCur[o->p1]; if (l < 0 || o->p2 > nMem) QG_REFUSE("rowid");
        if ((o->opcode == OP_IdxRowid) != (P.lvl[l].isIdx && !tabOfCur[o->p1])) QG_REFUSE("rowid kind");
        reg[o->p2] = (GSym){G_ROWID, (i8)l};
        break;
      }
      case OP_Copy: case OP_SCopy:
        if (o->p2 > nMem || o->p1 > nMem || (o->opcode == OP_Copy && o->p3 != 0)) QG_REFUSE("copy");
        reg[o->p2] = reg[o->p1]; break;
      case OP_Eq: case OP_Ne: case OP_Lt: case OP_Le: case OP_Gt: case OP_Ge: {
        /* a filter: jumps to a level's continue address (skip the row) */
        int l = -1; for (int k = 0; k < P.nlvl; k++) if (P.lvl[k].cont == o->p2) l = k;
        if (l < 0 || P.lvl[l].nfilt >= QG_MAXFILT) QG_REFUSE("compare target");
        if (o->p4type != P4_NOTUSED && !(o->p4type == P4_COLLSEQ && !sqlite3StrICmp(o->p4.pColl->zName, "BINARY"))) QG_REFUSE("collation");
        if (o->p5 & ~(SQLITE_AFF_MASK | SQLITE_JUMPIFNULL)) QG_REFUSE("compare flags");
        GFilt *f = &P.lvl[l].filt[P.lvl[l].nfilt++]; f->op = (u8)o->opcode; f->p5 = (u8)o->p5; f->l = reg[o->p1]; f->r = reg[o->p3];
        break;
      }
      case OP_AggStep: {
        if (o->p4type != P4_FUNCDEF || P.nagg >= QG_MAXAGG) QG_REFUSE("aggstep");
        FuncDef *f = o->p4.pFunc; GAgg *a = &P.agg[P.nagg++]; a->reg = o->p3;
        if (!sqlite3StrICmp(f->zName, "count") && o->p5 == 0) a->fn = 1;
        else if ((!sqlite3StrICmp(f->zName, "min") || !sqlite3StrICmp(f->zName, "max")) && o->p5 == 1 && f->nArg == 1) {
          a->fn = sqlite3StrICmp(f->zName, "min") ? 3 : 2; a->arg = reg[o->p2];
          if (!qg_row_sym(&a->arg)) QG_REFUSE("agg arg");
        } else QG_REFUSE("aggregate");
        aggMode = 1; break;
      }
      case OP_CollSeq:
        if (o->p4type != P4_COLLSEQ || sqlite3StrICmp(o->p4.pColl->zName, "BINARY")) QG_REFUSE("collseq");
        break;
      case OP_AggFinal: {
        int a = -1; for (int k = 0; k < P.nagg; k++) if (P.agg[k].reg == o->p1) a = k;
        while (depth && (P.lvl[depth - 1].kind == GL_ROWID || P.lvl[depth - 1].once)) depth--;
        if (a < 0 || depth) QG_REFUSE("aggfinal");
        if (aggEndPc < 0) aggEndPc = pc;
        reg[o->p1] = (GSym){G_AGG, 0, (i16)a};
        break;
      }
      case OP_ResultRow: {
        if (o->p2 > QC_MAXOUT || haveOut || (aggMode && depth) || (!aggMode && depth != P.nlvl)) QG_REFUSE("resultrow");
        for (int k = 0; k < o->p2; k++) {
          GSym s = reg[o->p1 + k];
          if (!qg_row_sym(&s) && s.kind != G_AGG && !(aggMode && s.kind == G_NULL)) QG_REFUSE("output");
          P.out[k] = s;
        }
        P.nout = o->p2; haveOut = 1;
        break;
      }
      case OP_DecrJumpZero: {
        if (P.hasLimit || reg[o->p1].kind != G_INT || reg[o->p1].v < 1 || !haveOut) QG_REFUSE("limit");
        P.hasLimit = 1; P.limit = reg[o->p1]; limitPc = o->p2;
        break;
      }
      case OP_Next: case OP_Prev: {
        while (depth && (P.lvl[depth - 1].kind == GL_ROWID || P.lvl[depth - 1].once)) depth--;   /* point levels inside this loop close here */
        if (!depth) QG_REFUSE("closer");
        GLevel *L = &P.lvl[depth - 1];
        if (o->p1 != L->cur || pc != L->cont) QG_REFUSE("closer order");
        depth--;
        break;
      }
      case OP_Halt:
        if (o->p1 || o->p2) QG_REFUSE("halt");
        haltPc = pc; pc = endInit; break;
      default: qc_why = sqlite3OpcodeName(o->opcode); return 0;
    }
  }
  if (haltPc < 0 || !haveOut) QG_REFUSE("no result");
  /* each level exits to its enclosing loop's continue address; through point levels (no loop) to theirs; the
     outermost to Halt. A point level's own continue is its exit. LIMIT exits to Halt. */
  if (limitPc >= 0 && limitPc != haltPc) QG_REFUSE("limit target");
  for (int l = 0; l < P.nlvl; l++) {
    int e = l - 1; while (e >= 0 && (P.lvl[e].kind == GL_ROWID || P.lvl[e].once)) e--;
    int want = e < 0 ? (aggMode ? aggEndPc : haltPc) : P.lvl[e].cont;
    if (P.lvl[l].exitPc != want) QG_REFUSE("level exits");
    if (P.lvl[l].kind == GL_ROWID || P.lvl[l].once) P.lvl[l].cont = P.lvl[l].exitPc;
  }
  for (int l = 0; l < P.nlvl; l++) if (P.lvl[l].isIdx && !(P.uk[l] = sqlite3VdbeAllocUnpackedRecord(P.lvl[l].ki))) return 0;
  /* what each level decodes, and the decoder for that record shape (from the schema) */
  {
    #define QG_NEED(sy) do { const GSym *q_ = (sy); if (q_->kind == G_COL) { GLevel *z_ = &P.lvl[q_->lvl]; \
        if (q_->col & 0x100) z_->needIdx |= 1u << (q_->col & 0xff); else z_->needTab |= 1u << q_->col; } \
        else if (q_->kind == G_ROWID && P.lvl[q_->lvl].isIdx) P.lvl[q_->lvl].needIdx |= 1u << (P.lvl[q_->lvl].ki->nAllField - 1); } while (0)
    for (int k = 0; k < P.nout; k++) QG_NEED(&P.out[k]);
    for (int a = 0; a < P.nagg; a++) if (P.agg[a].fn != 1) QG_NEED(&P.agg[a].arg);
    for (int l = 0; l < P.nlvl; l++) {
      GLevel *L = &P.lvl[l];
      for (int f = 0; f < L->nfilt; f++) { QG_NEED(&L->filt[f].l); QG_NEED(&L->filt[f].r); }
      for (int j = 0; j < L->nkey; j++) QG_NEED(&L->key[j]);
      for (int j = 0; j < L->nend; j++) QG_NEED(&L->end[j]);
      if (L->kind == GL_ROWID) QG_NEED(&L->rowidKey);
      if (L->isIdx && L->tabCur >= 0) L->needIdx |= 1u << (L->ki->nAllField - 1);   /* the deferred seek reads the rowid */
    }
    Schema *sc = v->db->aDb[P.iDb].pSchema;
    for (int l = 0; l < P.nlvl; l++) {
      GLevel *L = &P.lvl[l]; Index *ix; Table *t;
      if (L->needIdx >> QC_MAXCOL || L->needTab >> QC_MAXCOL) QG_REFUSE("wide record");
      if (L->isIdx && (t = qc_find(sc, L->root, &ix)) && ix) { qc_shape(&L->idxShape, t, ix, L->needIdx, -1); L->idxDec = qc_dec_pick(&L->idxShape); }
      Pgno tr = L->isIdx ? (L->tabCur >= 0 ? L->tabRoot : 0) : L->root;
      if (tr && (t = qc_find(sc, tr, &ix)) && !ix) { qc_shape(&L->tabShape, t, 0, L->needTab, -1); L->tabDec = qc_dec_pick(&L->tabShape); }
    }
  }
  if (qg_nplans >= 64) return 0;
  QcGPlan *pp = sqlite3_malloc(sizeof P); if (!pp) return 0;
  *pp = P; v->pQc = pp; v->qcWant = 1; qg_plans[qg_nplans++] = pp;
  return 1;
}

/* ---------------------------------------------------------------- run time */
typedef struct QgRun {
  QcVal pv[32];                               /* parameters and computed values */
  QcVal out[QG_MAXROWS * QC_MAXOUT]; int nrow;
  DbPage *pins[QG_MAXROWS * 2]; int npin;
  QcVal col[QG_MAXLVL][2][QC_MAXCOL]; u8 have[QG_MAXLVL][2]; i64 rowid[QG_MAXLVL];   /* [0] table record, [1] index record */
  i64 aggCnt[QG_MAXAGG]; QcVal aggV[QG_MAXAGG]; u8 aggSet[QG_MAXAGG];
  i64 limit;
} QgRun;
static QgRun *qg_run;

static int qg_cursor(QcGPlan *P, Btree *bt, int slot, BtCursor **out) {
  if (P->bopen[slot]) { *out = P->bc[slot]; return 0; }
  if (!P->bc[slot] && !(P->bc[slot] = sqlite3MallocZero(sqlite3BtreeCursorSize()))) return 1;
  sqlite3BtreeCursorZero(P->bc[slot]);
  if (sqlite3BtreeCursor(bt, P->curs[slot].root, 0, P->curs[slot].ki, P->bc[slot]) != SQLITE_OK) return 1;
  P->bopen[slot] = 1; P->bt = bt; *out = P->bc[slot]; return 0;
}
static void qg_pin(QgRun *R, BtCursor *c) {
  DbPage *pg = c->pPage->pDbPage;
  for (int k = R->npin - 1; k >= 0 && k >= R->npin - 4; k--) if (R->pins[k] == pg) return;
  if (R->npin < (int)(sizeof R->pins / sizeof *R->pins)) { sqlite3PagerRef(pg); R->pins[R->npin++] = pg; }
}
/* value of a value-kind symbol; 0 = a type the bytecode would convert, or an overflow */
static int qg_eval(QcGPlan *P, Vdbe *v, const QcOut *O, const GSym *s, QcVal *o) {
  switch (s->kind) {
    case G_INT: o->type = SQLITE_INTEGER; o->i = s->v; return 1;
    case G_NULL: o->type = SQLITE_NULL; return 1;
    case G_PARAM: {
      if (O && O->param && s->v <= O->nparam) { o->type = SQLITE_INTEGER; o->i = O->param[s->v - 1]; return 1; }
      Mem *m = &v->aVar[s->v - 1];
      if (m->flags & MEM_Null) { o->type = SQLITE_NULL; return 1; }
      if ((m->flags & (MEM_Int | MEM_Real | MEM_Str | MEM_Blob)) == MEM_Int) { o->type = SQLITE_INTEGER; o->i = m->u.i; return 1; }
      if ((m->flags & (MEM_Int | MEM_Real | MEM_Str | MEM_Blob)) == MEM_Str && m->enc == SQLITE_UTF8) {
        o->type = SQLITE_TEXT; o->z = (const u8 *)m->z; o->n = m->n; return 1; }
      return 0;
    }
    case G_ADD: case G_SUB: {
      QcVal a, b; if (!qg_eval(P, v, O, &P->ex[s->a], &a) || !qg_eval(P, v, O, &P->ex[s->b], &b)) return 0;
      if (a.type == SQLITE_NULL || b.type == SQLITE_NULL) { o->type = SQLITE_NULL; return 1; }
      if (a.type != SQLITE_INTEGER || b.type != SQLITE_INTEGER) return 0;   /* text arithmetic: SQLite's conversions */
      i64 r; if (s->kind == G_ADD ? __builtin_add_overflow(a.i, b.i, &r) : __builtin_sub_overflow(a.i, b.i, &r)) return 0;
      o->type = SQLITE_INTEGER; o->i = r; return 1;
    }
  }
  return 0;
}
/* apply a key's affinity the way OP_Affinity would, or refuse when it would change the value's type */
static int qg_aff_ok(char aff, const QcVal *x) {
  if (x->type == SQLITE_NULL) return 1;
  switch (aff) {
    case 0: case SQLITE_AFF_BLOB: case SQLITE_AFF_NONE: return 1;
    case SQLITE_AFF_TEXT: return x->type == SQLITE_TEXT;
    case SQLITE_AFF_INTEGER: case SQLITE_AFF_NUMERIC: case SQLITE_AFF_REAL: return x->type == SQLITE_INTEGER;
  }
  return 0;
}
static void qg_mem(Mem *m, const QcVal *x) {
  memset(m, 0, sizeof *m);
  if (x->type == SQLITE_INTEGER) { m->flags = MEM_Int; m->u.i = x->i; }
  else if (x->type == SQLITE_TEXT) { m->flags = MEM_Str | MEM_Ephem; m->z = (char *)x->z; m->n = x->n; m->enc = SQLITE_UTF8; }
  else m->flags = MEM_Null;
}
/* decode what the row needs at level l: the table record ([0]) or the index record ([1]); 0 = fallback */
static int qg_fetch(QcGPlan *P, QgRun *R, BtCursor *c, int which, int l) {
  if (R->have[l][which]) return 1;
  GLevel *L = &P->lvl[l]; u32 need = which ? L->needIdx : L->needTab;
  int (*dec)(const u8 *, u32, QcVal *) = which ? L->idxDec : L->tabDec;
  u32 sz = sqlite3BtreePayloadSize(c), amt; const u8 *rec = sqlite3BtreePayloadFetch(c, &amt);
  if (amt < sz || !((dec && dec(rec, sz, R->col[l][which])) || qc_decode(rec, sz, need, R->col[l][which]))) return 0;
  qg_pin(R, c); R->have[l][which] = 1; return 1;
}
typedef struct QgCtx { QcGPlan *P; Vdbe *v; const QcOut *O; Btree *bt; QgRun *R; BtCursor *cur[QG_MAXLVL], *tab[QG_MAXLVL]; int err; int done; } QgCtx;
/* value of a row symbol at the current position; 0 = fallback */
static int qg_rowval(QgCtx *X, const GSym *s, QcVal *o) {
  QgRun *R = X->R; int l = s->lvl; GLevel *L = &X->P->lvl[l];
  if (s->kind == G_ROWID) {
    if (L->isIdx) {   /* IdxRowid: the index record's last field */
      if (!qg_fetch(X->P, R, X->cur[l], 1, l)) return 0;
      int nf = L->ki->nAllField - 1; QcVal *f = &R->col[l][1][nf];
      if (nf >= QC_MAXCOL || f->type != SQLITE_INTEGER) return 0;
      *o = *f; return 1;
    }
    o->type = SQLITE_INTEGER; o->i = sqlite3BtreeIntegerKey(X->cur[l]); return 1;
  }
  if (s->col & 0x100) { if (!qg_fetch(X->P, R, X->cur[l], 1, l)) return 0; *o = R->col[l][1][s->col & 0xff]; return 1; }
  BtCursor *c = L->isIdx ? X->tab[l] : X->cur[l];
  if (L->isIdx) {   /* the deferred seek of the table row behind the index entry */
    if (!R->have[l][0]) {
      QcVal rid; GSym rs = {G_ROWID, (i8)l}; if (!qg_rowval(X, &rs, &rid)) return 0;
      int res; if (sqlite3BtreeTableMoveto(c, rid.i, 0, &res) != SQLITE_OK || res != 0) return 0;
    }
  }
  if (!qg_fetch(X->P, R, c, 0, l)) return 0;
  *o = R->col[l][0][s->col]; return 1;
}
static int qg_val(QgCtx *X, const GSym *s, QcVal *o) { return qg_row_sym(s) ? qg_rowval(X, s, o) : qg_eval(X->P, X->v, X->O, s, o); }
/* vdbe compare semantics for INTEGER/TEXT (BINARY) and NULL: 1 jump, 0 no jump, -1 fallback */
static int qg_cmp_jump(u8 op, u8 p5, const QcVal *r3, const QcVal *r1) {
  if (r3->type == SQLITE_NULL || r1->type == SQLITE_NULL) return (p5 & SQLITE_JUMPIFNULL) ? 1 : 0;
  int c;
  if (r3->type == SQLITE_INTEGER && r1->type == SQLITE_INTEGER) c = r3->i < r1->i ? -1 : r3->i > r1->i;
  else if (r3->type == SQLITE_TEXT && r1->type == SQLITE_TEXT && (p5 & SQLITE_AFF_MASK) <= SQLITE_AFF_TEXT) {
    int n = r3->n < r1->n ? r3->n : r1->n; c = memcmp(r3->z, r1->z, (size_t)n); if (!c) c = r3->n - r1->n;
  } else return -1;
  switch (op) { case OP_Eq: return c == 0; case OP_Ne: return c != 0; case OP_Lt: return c < 0; case OP_Le: return c <= 0; case OP_Gt: return c > 0; default: return c >= 0; }
}
static int qg_level(QgCtx *X, int l);
/* the row at level l is positioned: filters, then the next level or the output. 1 continue, 0 stop */
static int qg_row(QgCtx *X, int l) {
  QcGPlan *P = X->P; QgRun *R = X->R; GLevel *L = &P->lvl[l];
  R->have[l][0] = R->have[l][1] = 0;
  for (int f = 0; f < L->nfilt; f++) {
    QcVal a, b; if (!qg_val(X, &L->filt[f].r, &a) || !qg_val(X, &L->filt[f].l, &b)) { X->err = 1; return 0; }
    int j = qg_cmp_jump(L->filt[f].op, L->filt[f].p5, &a, &b); if (j < 0) { X->err = 1; return 0; }
    if (j) return 1;   /* skip this row */
  }
  if (l + 1 < P->nlvl) return qg_level(X, l + 1);
  if (P->nagg) {
    for (int a = 0; a < P->nagg; a++) {
      GAgg *g = &P->agg[a];
      if (g->fn == 1) { R->aggCnt[a]++; continue; }
      QcVal x; if (!qg_rowval(X, &g->arg, &x)) { X->err = 1; return 0; }
      if (x.type == SQLITE_NULL) continue;
      if (x.type != SQLITE_INTEGER && x.type != SQLITE_TEXT) { X->err = 1; return 0; }
      if (!R->aggSet[a]) { R->aggV[a] = x; R->aggSet[a] = 1; continue; }
      QcVal *cur = &R->aggV[a]; int c;
      if (cur->type != x.type) c = x.type == SQLITE_INTEGER ? -1 : 1;   /* numbers sort before text */
      else if (x.type == SQLITE_INTEGER) c = x.i < cur->i ? -1 : x.i > cur->i;
      else { int n = x.n < cur->n ? x.n : cur->n; c = memcmp(x.z, cur->z, (size_t)n); if (!c) c = x.n - cur->n; }
      if ((g->fn == 2 && c < 0) || (g->fn == 3 && c > 0)) *cur = x;
    }
    return 1;
  }
  if (R->nrow >= QG_MAXROWS) { X->err = 1; return 0; }
  QcVal *o = &R->out[(size_t)R->nrow * P->nout];
  for (int k = 0; k < P->nout; k++) if (!qg_rowval(X, &P->out[k], &o[k])) { X->err = 1; return 0; }
  R->nrow++;
  if (P->hasLimit && --R->limit == 0) { X->done = 1; return 0; }
  return 1;
}
/* run level l to its end (or until stop); 1 = carry on with the enclosing level, 0 = stop everything */
static int qg_level(QgCtx *X, int l) {
  QcGPlan *P = X->P; GLevel *L = &P->lvl[l]; BtCursor *c = X->cur[l]; int res, rc;
  if (L->kind == GL_ROWID) {
    QcVal k; if (!qg_val(X, &L->rowidKey, &k)) { X->err = 1; return 0; }
    if (k.type == SQLITE_NULL) return 1;                                   /* SeekRowid on NULL: not found */
    if (k.type != SQLITE_INTEGER) { X->err = 1; return 0; }
    if (sqlite3BtreeTableMoveto(c, k.i, 0, &res) != SQLITE_OK) { X->err = 1; return 0; }
    if (res != 0 || c->eState != CURSOR_VALID) return 1;
    return qg_row(X, l);
  }
  if (L->kind == GL_SCAN) {
    rc = L->dir ? sqlite3BtreeFirst(c, &res) : sqlite3BtreeLast(c, &res);
    if (rc != SQLITE_OK) { X->err = 1; return 0; }
    if (res) return 1;
  } else {
    /* the seek, as OP_Seek* */
    QcVal kv[QG_MAXKEY]; int oc = L->seekOp;
    for (int j = 0; j < L->nkey; j++) {
      if (!qg_val(X, &L->key[j], &kv[j])) { X->err = 1; return 0; }
      if (kv[j].type == SQLITE_NULL && L->keyNullExit) return 1;
      if (!qg_aff_ok(L->aff[j], &kv[j])) { X->err = 1; return 0; }
    }
    if (!L->isIdx) {
      if (kv[0].type != SQLITE_INTEGER) { X->err = 1; return 0; }        /* applyNumericAffinity / real keys: SQLite's path */
      if (sqlite3BtreeTableMoveto(c, kv[0].i, 0, &res) != SQLITE_OK) { X->err = 1; return 0; }
    } else {
      UnpackedRecord *r = P->uk[l]; r->nField = (u16)L->nkey; r->default_rc = ((1 & (oc - OP_SeekLT)) ? -1 : +1);
      r->eqSeen = 0; r->errCode = 0;
      for (int j = 0; j < L->nkey; j++) qg_mem(&r->aMem[j], &kv[j]);
      if (sqlite3BtreeIndexMoveto(c, r, &res) != SQLITE_OK) { X->err = 1; return 0; }
    }
    if (oc >= OP_SeekGE) {
      if (res < 0 || (res == 0 && oc == OP_SeekGT)) { rc = sqlite3BtreeNext(c, 0); if (rc == SQLITE_DONE) return 1; if (rc) { X->err = 1; return 0; } }
    } else {
      if (res > 0 || (res == 0 && oc == OP_SeekLT)) { rc = sqlite3BtreePrevious(c, 0); if (rc == SQLITE_DONE) return 1; if (rc) { X->err = 1; return 0; } }
      else if (sqlite3BtreeEof(c)) return 1;
    }
  }
  QcVal ev[QG_MAXKEY];
  for (int j = 0; j < L->nend; j++) if (!qg_val(X, &L->end[j], &ev[j])) { X->err = 1; return 0; }
  if (L->isIdx && L->endOp) {
    UnpackedRecord *r = P->uk[l]; r->nField = (u16)L->nend; r->default_rc = L->endOp < OP_IdxLT ? -1 : 0; r->eqSeen = 0; r->errCode = 0;
    for (int j = 0; j < L->nend; j++) { if (!qg_aff_ok(0, &ev[j])) { X->err = 1; return 0; } qg_mem(&r->aMem[j], &ev[j]); }
  }
  for (;;) {
    /* the end test at the loop head */
    if (L->endOp) {
      if (L->isIdx) {
        u32 sz = sqlite3BtreePayloadSize(c), amt; const u8 *rec = sqlite3BtreePayloadFetch(c, &amt);
        if (amt < sz) { X->err = 1; return 0; }
        UnpackedRecord *r = P->uk[l]; r->nField = (u16)L->nend; r->default_rc = L->endOp < OP_IdxLT ? -1 : 0; r->eqSeen = 0; r->errCode = 0;
        for (int j = 0; j < L->nend; j++) qg_mem(&r->aMem[j], &ev[j]);
        int cr = sqlite3VdbeRecordCompareWithSkip((int)sz, rec, r, 0);
        if (r->errCode) { X->err = 1; return 0; }
        if ((L->endOp & 1) == (OP_IdxLT & 1)) cr = -cr; else cr++;
        if (cr > 0) return 1;
      } else {
        QcVal rid = {.type = SQLITE_INTEGER}; rid.i = sqlite3BtreeIntegerKey(c);
        int j = qg_cmp_jump(L->endOp, L->endP5, &rid, &ev[0]); if (j < 0) { X->err = 1; return 0; }
        if (j) return 1;
      }
    }
    if (!qg_row(X, l)) return 0;
    if (L->once) return 1;
    rc = L->dir ? sqlite3BtreeNext(c, 0) : sqlite3BtreePrevious(c, 0);
    if (rc == SQLITE_DONE) return 1;
    if (rc) { X->err = 1; return 0; }
  }
}

static int qg_exec(Vdbe *v, QcGPlan *P, qc_row_cb cb, void *ctx) {
  sqlite3 *db = v->db;
  if (v->eVdbeState != VDBE_READY_STATE) return QC_FB("g not ready"); if (db->autoCommit) return QC_FB("g autocommit"); if (P->iDb >= db->nDb || v->expired) return QC_FB("g expired");   /* e.g. a re-bound parameter the plan depends on (expmask): SQLite re-prepares */
  Btree *bt = db->aDb[P->iDb].pBt; if (!bt) return QC_FB("g btree");
  if (sqlite3BtreeTxnState(bt) == SQLITE_TXN_NONE) { int m; P->txnChecked = 0; if (sqlite3BtreeBeginTrans(bt, 0, &m) != SQLITE_OK) return QC_FB("g txn"); }
  if (!P->txnChecked || P->bt != bt) {
    int iMeta; sqlite3BtreeGetMeta(bt, BTREE_SCHEMA_VERSION, (u32 *)&iMeta);
    if (iMeta != P->cookie || db->aDb[P->iDb].pSchema->iGeneration != P->gen) return QC_FB("g schema");
    P->txnChecked = 1; P->bt = bt;
  }
  if (!qg_run && !(qg_run = sqlite3MallocZero(sizeof *qg_run))) return QC_FB("g oom");
  QgRun *R = qg_run; R->nrow = 0; R->npin = 0;
  QgCtx X; memset(&X, 0, sizeof X); X.P = P; X.v = v; X.O = cb ? 0 : ctx; X.bt = bt; X.R = R;
  for (int l = 0; l < P->nlvl; l++) {
    int k = qg_curslot(P, P->lvl[l].cur); if (k < 0 || qg_cursor(P, bt, k, &X.cur[l])) return QC_FB("g cursor");
    if (P->lvl[l].tabCur >= 0) { int t = qg_curslot(P, P->lvl[l].tabCur); if (t < 0 || qg_cursor(P, bt, t, &X.tab[l])) return QC_FB("g cursor"); }
  }
  for (int a = 0; a < P->nagg; a++) { R->aggCnt[a] = 0; R->aggSet[a] = 0; }
  R->limit = P->hasLimit ? P->limit.v : 0;
  int st = QC_FALLBACK;
  if (P->nlvl) qg_level(&X, 0);
  if (X.err) { qc_why = "g run"; goto out; }
  if (P->nagg) {   /* one output row from the aggregates */
    QcVal *o = R->out;
    for (int k = 0; k < P->nout; k++) {
      GSym s = P->out[k];
      if (s.kind == G_NULL) { o[k].type = SQLITE_NULL; o[k].n = 0; continue; }
      if (s.kind != G_AGG) { qc_why = "g agg out"; goto out; }
      GAgg *g = &P->agg[s.col];
      if (g->fn == 1) { o[k].type = SQLITE_INTEGER; o[k].i = R->aggCnt[s.col]; }
      else if (R->aggSet[s.col]) o[k] = R->aggV[s.col]; else { o[k].type = SQLITE_NULL; o[k].n = 0; }
    }
    R->nrow = 1;
  }
  if (cb) st = cb(ctx, R->nrow, P->nout, R->out);
  else {   /* the JSON template, from the rows */
    QcOut *O = ctx; QcTmpl *T = v->pQcTmpl;
    if (!T || T->ncol != P->nout) goto out;
    int vec = bt->pBt->pPager->xGet == getPageNormal;
    char *p = O->buf, *end = O->buf + O->cap;
    if ((size_t)(end - p) < T->lopen + T->lclose + 64) goto out;
    p = qc_frag(p, T->open, T->lopen);
    for (int i = 0; i < R->nrow; i++) {
      if ((size_t)(end - p) < T->lsep + QC_FRAG + 64) goto out;
      if (i) p = qc_frag(p, T->sep, T->lsep);
      for (int k = 0; k < T->ncol; k++) {
        const QcVal *x = &R->out[(size_t)i * P->nout + k];
        if (T->kind[k] == 'i') { if (x->type != SQLITE_INTEGER || (size_t)(end - p) < 2 * QC_FRAG + 21 + 64) goto out; p = qc_frag(p, T->frag[k], T->lfrag[k]); p = qc_jint(p, x->i); }
        else { if (x->type != SQLITE_TEXT || (size_t)(end - p) < 2 * QC_FRAG + 2 + 6 * (size_t)x->n + 64) goto out; p = qc_frag(p, T->frag[k], T->lfrag[k]); p = qc_jstr(p, x->z, (u32)x->n, vec); }
      }
      if ((size_t)(end - p) < 2 * QC_FRAG + 64) goto out;
      p = qc_frag(p, T->frag[T->ncol], T->lfrag[T->ncol]);
    }
    if ((size_t)(end - p) < QC_FRAG + 64) goto out;
    p = qc_frag(p, T->close, T->lclose);
    O->n = (size_t)(p - O->buf); O->rows = R->nrow; st = SQLITE_OK;
  }
out:
  for (int i = 0; i < R->npin; i++) sqlite3PagerUnref(R->pins[i]);
  return st;
}
