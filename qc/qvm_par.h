/* qvm_par.h: helper threads for one statement's scan (QV_PAR=n: n helper threads; QV_PAR=0: the same page at a time
** on the statement's own thread; unset, the default: off).
** #included by qvm.c before qv_region.
**
** One connection, one statement: the thread inside sqlite3_step is the only one that calls SQLite. It walks the
** region's table B-tree a leaf page at a time, pins a window of pages and hands them out; the helpers and the main
** thread then decode the pages' cells and run the region's body on them, each page into its own partial result, and
** the main thread merges those in page order. A helper reads nothing but pinned page images and the kernel built
** here; it never takes a lock of SQLite's, allocates, or touches the connection.
**
** The shape (qv_par_build, from the region's nodes and feedback): a loop on a table cursor whose body is only
**   Column (feedback integers and NULL) and Rowid on the loop's cursor,
**   Eq/Ne/Lt/Le/Gt/Ge on those and loop invariants, jumping to the loop's Next (a WHERE term that skips the row),
**   AggStep of count() and of sum()/total()/avg() kept natively (isCnt, isSum),
**   Next;
** and whose Column and Rowid registers nothing outside the loop reads.
**
** Exact by construction, or not at all:
**   a page whose cells don't fit (an overflow record, a value that isn't an integer or NULL, a record shorter than
**   the fields read, a field past an overflow record's local part, anything malformed) is a miss. So is a page whose integer sum would overflow at some row: the
**   partial result keeps its lowest and highest running sum, so the merge sees whether SQLite's running sum would
**   leave the int64 range anywhere in it. At the first miss in page order, the pages before it are merged, the cursor
**   is moved to the miss's first cell (by rowid) and the region goes on row by row from there, as without helpers,
**   until its Next enters the next page: the helpers take the loop again from that page's first row (G->parOn).
**   A row's effects are a count and a sum, so merging page results in page order gives SQLite's exact totals.
**
** One statement at a time uses the helpers (process-wide); another that finds them busy runs its pages on its own
** thread, the same code. */
#if defined(__SIZEOF_INT128__) && !defined(QV_NO_PAR)
#define QV_PAR_ON 1
#define QV_PK_OPS 32       /* a kernel's ops, */
#define QV_PK_SLOTS 16     /* values (the row's and the invariants'), */
#define QV_PK_ACC 4        /* accumulators */
#define QV_PK_FIELDS 64    /* and the fields its Columns may read */
#define QV_PAR_MAX 64      /* helper threads at most */
enum { PK_COL, PK_ROWID, PK_CMP, PK_CNT, PK_SUM };
typedef struct QvPkOp { u8 k, a, b, lt, eq, gt, jnull, acc; int f; } QvPkOp;   /* COL: field f into slot a; ROWID: into a; CMP: slots a (P1)
                                                                                  and b (P3), skip the row by lt/eq/gt, or jnull on a NULL;
                                                                                  CNT: acc, counting a non-NULL slot a (255: count(*)); SUM: acc += a */
typedef struct QvParPg { const u8 *a; DbPage *dp; u32 usable; u16 ix, n, cellOffset, maskPage, maxLocal, minLocal; } QvParPg;   /* a page's image and the
                                                                                  MemPage fields the cells need, copied: helpers read no MemPage */
typedef struct QvParRes { u8 miss; u32 rows; i64 cnt[QV_PK_ACC]; __int128 sum[QV_PK_ACC], lo[QV_PK_ACC], hi[QV_PK_ACC]; } QvParRes;
typedef struct QvPar {
  int nop, nslot, nacc, maxf;
  QvPkOp op[QV_PK_OPS];
  int inv[QV_PK_SLOTS];                    /* by slot: the invariant's register, or -1 (the row's) */
  int accReg[QV_PK_ACC]; u8 accSum[QV_PK_ACC];
  QvParPg *pg; QvParRes *res; int cap;     /* the window (the main thread's) */
} QvPar;

/* ---- one page's cells through the kernel (helpers and the main thread) */
static inline int qv_pk_v32(const u8 *p, const u8 *e, u32 *v) {   /* a varint below 2^32 within [p, e): its length, or 0 */
  u32 x = 0;
  for (int i = 0; i < 5 && p + i < e; i++) { x = (x << 7) | (p[i] & 0x7f); if (!(p[i] & 0x80)) { *v = x; return i + 1; } }
  return 0;
}
static inline int qv_pk_v64(const u8 *p, const u8 *e, u64 *v) {   /* sqlite3GetVarint, bounded by e */
  if (e - p >= 9) return sqlite3GetVarint(p, v);
  u64 x = 0;
  for (int i = 0; i < 8 && p + i < e; i++) { x = (x << 7) | (p[i] & 0x7f); if (!(p[i] & 0x80)) { *v = x; return i + 1; } }
  return 0;
}
static const u8 qv_pk_len[12] = {0, 1, 2, 3, 4, 6, 8, 8, 0, 0, 255, 255};
static void qv_par_page(const QvPar *K, const QvParPg *g, QvParRes *o, const i64 *base) {
  i64 v[QV_PK_SLOTS]; u8 nul[QV_PK_SLOTS]; u32 ty[QV_PK_FIELDS], of[QV_PK_FIELDS]; __int128 run[QV_PK_ACC];
  memset(o, 0, sizeof *o);
  for (int s = 0; s < K->nslot; s++) { v[s] = base[s]; nul[s] = 0; }
  for (int a = 0; a < K->nacc; a++) run[a] = 0;
  const u8 *A = g->a, *E = g->a + g->usable;
  for (u32 i = g->ix; i < g->n; i++) {
    u32 co = (((u32)A[g->cellOffset + 2 * i] << 8) | A[g->cellOffset + 2 * i + 1]) & g->maskPage;
    if (co < (u32)g->cellOffset + 2u * g->n || co >= g->usable) goto miss;
    const u8 *p = A + co; u32 np; u64 rowid; int k;
    if (!(k = qv_pk_v32(p, E, &np))) goto miss;
    p += k;
    if (!(k = qv_pk_v64(p, E, &rowid))) goto miss;
    p += k;
    u32 nl = np;   /* the record's bytes on this page: all of it, or an overflow record's local part (btreeParseCellAdjustSizeForOverflow) */
    if (np > g->maxLocal) { nl = g->minLocal + (np - g->minLocal) % (g->usable - 4); if (nl > g->maxLocal) nl = g->minLocal; }
    if (nl > (u32)(E - p)) goto miss;
    const u8 *rec = p, *re = p + nl; u32 h;
    if (!(k = qv_pk_v32(rec, re, &h)) || h > nl || h < (u32)k) goto miss;   /* (a header past the local part: row by row) */
    if (K->maxf >= 0) {
      const u8 *hp = rec + k, *he = rec + h; u32 d = h;
      for (int f = 0; f <= K->maxf; f++) {
        u32 t;
        if (hp >= he) goto miss;   /* (a record shorter than the fields read: the column's default, row by row) */
        if (*hp < 0x80) t = *hp++; else { if (!(k = qv_pk_v32(hp, he, &t))) goto miss; hp += k; }
        u32 len = t < 12 ? qv_pk_len[t] : (t - 12) >> 1;
        if (len == 255) goto miss;
        ty[f] = t; of[f] = d; d += len;
        if (d > nl) goto miss;   /* (a field read past the local part: row by row) */
      }
    }
    for (int j = 0; j < K->nop; j++) {
      const QvPkOp *x = &K->op[j];
      switch (x->k) {
        case PK_COL: {
          u32 t = ty[x->f];
          if (t == 0) nul[x->a] = 1;
          else if (t <= 6 || t == 8 || t == 9) { v[x->a] = qc_int(t, rec + of[x->f]); nul[x->a] = 0; }
          else goto miss;   /* (a real, text or blob: row by row) */
          break;
        }
        case PK_ROWID: v[x->a] = (i64)rowid; nul[x->a] = 0; break;
        case PK_CMP: {
          if (nul[x->a] | nul[x->b]) { if (x->jnull) goto skip; break; }
          i64 a = v[x->a], b = v[x->b]; int res = b > a ? 1 : b < a ? -1 : 0;   /* (RG_CMPI's: P3 against P1) */
          if (res < 0 ? x->lt : res ? x->gt : x->eq) goto skip;
          break;
        }
        case PK_CNT: if (x->a == 255 || !nul[x->a]) o->cnt[x->acc]++; break;
        case PK_SUM:
          if (!nul[x->a]) {
            int c = x->acc; run[c] += v[x->a]; o->cnt[c]++;
            if (run[c] < o->lo[c]) o->lo[c] = run[c];
            if (run[c] > o->hi[c]) o->hi[c] = run[c];
          }
          break;
      }
    }
  skip:
    o->rows++;
  }
  for (int a = 0; a < K->nacc; a++) o->sum[a] = run[a];
  return;
miss:
  o->miss = 1;
}

/* ---- the helpers */
static struct QvPool {
  pthread_mutex_t mu, own; pthread_cond_t go, fin;
  int n, active; u64 gen;                  /* helpers; those inside the current job; the job's number */
  const QvPar *K; const QvParPg *pg; QvParRes *res; const i64 *base; int npg;   /* the job: set under mu while active == 0 */
  int next;                                /* the next page to take (atomic) */
} qvp = { PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER, PTHREAD_COND_INITIALIZER };
static void qv_par_work(void) {
  int i;
  while ((i = __atomic_fetch_add(&qvp.next, 1, __ATOMIC_RELAXED)) < qvp.npg) qv_par_page(qvp.K, &qvp.pg[i], &qvp.res[i], qvp.base);
}
static void *qv_par_thread(void *u) {
  (void)u; u64 seen = 0;
  pthread_mutex_lock(&qvp.mu);
  for (;;) {
    while (qvp.gen == seen) pthread_cond_wait(&qvp.go, &qvp.mu);
    seen = qvp.gen; qvp.active++;
    pthread_mutex_unlock(&qvp.mu);
    qv_par_work();
    pthread_mutex_lock(&qvp.mu);
    if (--qvp.active == 0) pthread_cond_broadcast(&qvp.fin);
  }
  return 0;
}
static void qv_par_init(int n) {   /* (qc_init_once's, with QV_PAR=n) */
  if (n > QV_PAR_MAX) n = QV_PAR_MAX;
  for (int i = 0; i < n; i++) {
    pthread_t t; pthread_attr_t at; pthread_attr_init(&at); pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    if (pthread_create(&t, &at, qv_par_thread, 0) == 0) qvp.n++;
    pthread_attr_destroy(&at);
  }
}
/* the window's pages through the kernel: with the helpers when there are enough pages and nobody else has them */
static void qv_par_job(const QvPar *K, const QvParPg *pg, QvParRes *res, const i64 *base, int n) {
  if (!qvp.n || n < 4 || pthread_mutex_trylock(&qvp.own)) { for (int i = 0; i < n; i++) qv_par_page(K, &pg[i], &res[i], base); return; }
  pthread_mutex_lock(&qvp.mu);
  while (qvp.active) pthread_cond_wait(&qvp.fin, &qvp.mu);   /* (a helper that woke for the last job after it ended: out first) */
  qvp.K = K; qvp.pg = pg; qvp.res = res; qvp.base = base; qvp.npg = n; qvp.next = 0; qvp.gen++;
  pthread_cond_broadcast(&qvp.go);
  pthread_mutex_unlock(&qvp.mu);
  qv_par_work();
  pthread_mutex_lock(&qvp.mu);
  while (qvp.active) pthread_cond_wait(&qvp.fin, &qvp.mu);   /* (every page taken; the helpers still on one finish it) */
  pthread_mutex_unlock(&qvp.mu);
  pthread_mutex_unlock(&qvp.own);
}

/* ---- the kernel, from a region (qv_rg_build's, with QV_PAR set) */
/* might an op outside [B, N] read register r? Each opcode's registers read, for the ones around a loop like this; any
   other opcode counts as reading every register */
static int qv_par_read(const Op *aOp, int nOp, int r, int B, int N) {
  for (int pc = 0; pc < nOp; pc++) {
    if (pc >= B && pc <= N) continue;
    const Op *o = &aOp[pc]; int lo = -1, n = 1;
    switch (o->opcode) {
      case OP_Init: case OP_Goto: case OP_Halt: case OP_Transaction: case OP_OpenRead: case OP_ReopenIdx: case OP_TableLock:
      case OP_Noop: case OP_Explain: case OP_Integer: case OP_Int64: case OP_Real: case OP_String: case OP_String8:
      case OP_Null: case OP_Variable: case OP_Once: case OP_Rewind: case OP_Last: case OP_Close: case OP_ColumnsUsed:
      case OP_CursorHint: case OP_Next: case OP_Prev: case OP_Column: case OP_Rowid:
        continue;   /* (no register read: their outputs, cursors, page numbers) */
      case OP_SeekGT: case OP_SeekGE: case OP_SeekLT: case OP_SeekLE: lo = o->p3; n = o->p4type == P4_INT32 ? o->p4.i : 1; break;
      case OP_SeekRowid: case OP_NotExists: lo = o->p3; break;
      case OP_AggFinal: case OP_SCopy: case OP_MustBeInt: case OP_IsNull: case OP_NotNull: case OP_If: case OP_IfNot:
      case OP_IfPos: case OP_IfNotZero: case OP_DecrJumpZero: case OP_AddImm: lo = o->p1; break;
      case OP_Copy: lo = o->p1; n = o->p3 + 1; break;
      case OP_ResultRow: case OP_Affinity: lo = o->p1; n = o->p2; break;
      case OP_Eq: case OP_Ne: case OP_Lt: case OP_Le: case OP_Gt: case OP_Ge: case OP_OffsetLimit: if (r == o->p3) return 1; lo = o->p1; break;
      default: return 1;
    }
    if (r >= lo && r < lo + n) return 1;
  }
  return 0;
}
/* register r's slot: w, written by the row (a Column or Rowid); otherwise read. An invariant is read before anything in the
   body writes it and never written after; a row value is written before it's read */
static int qv_pk_slot(QvPar *K, int *reg, int *wrote, int r, int w) {
  int s = 0;
  while (s < K->nslot && reg[s] != r) s++;
  if (s < K->nslot) { if (w && !wrote[s]) return -1; return s; }   /* (an invariant written later: no) */
  if (s >= QV_PK_SLOTS) return -1;
  reg[s] = r; wrote[s] = w; K->nslot++;
  return s;
}
static QvPar *qv_par_build(QvPlan *P, const Op *aOp, const QvRegion *G) {
  QvPar K; int reg[QV_PK_SLOTS], wrote[QV_PK_SLOTS];   /* by slot: the register; written in the body (the row's) */
  memset(&K, 0, sizeof K); K.maxf = -1;
  if (aOp[G->N].opcode != OP_Next || G->cur < 0 || G->cur >= P->nCur) return 0;
#define PK_SLOT(r, w) qv_pk_slot(&K, reg, wrote, (r), (w))
  for (int pc = G->B; pc < G->N; pc++) {
    const Op *x = &aOp[pc]; QvPkOp *o = &K.op[K.nop]; int s;
    if (K.nop >= QV_PK_OPS) return 0;
    switch (x->opcode) {
      case OP_Noop: case OP_Explain: case OP_CursorHint: case OP_ColumnsUsed: continue;
      case OP_Column: {
        u8 m = P->fb[pc];
        if (x->p1 != G->cur || x->p5 || x->p2 >= QV_PK_FIELDS || !(m & QV_FB_INT) || (m & ~(QV_FB_INT | QV_FB_NULL))) return 0;
        if (P->isCnt[x->p3] || P->isSum[x->p3] || (s = PK_SLOT(x->p3, 1)) < 0) return 0;
        o->k = PK_COL; o->f = x->p2; o->a = (u8)s; if (x->p2 > K.maxf) K.maxf = x->p2;
        break;
      }
      case OP_Rowid:
        if (x->p1 != G->cur || P->isCnt[x->p2] || P->isSum[x->p2] || (s = PK_SLOT(x->p2, 1)) < 0) return 0;
        o->k = PK_ROWID; o->a = (u8)s;
        break;
      case OP_Eq: case OP_Ne: case OP_Lt: case OP_Le: case OP_Gt: case OP_Ge: {
        u8 m = P->fb[pc]; int a, b;
        if (x->p2 != G->N || (x->p5 & SQLITE_NULLEQ) || !(m & QV_FB_INT) || (m & ~(QV_FB_INT | QV_FB_NULL))) return 0;
        if ((a = PK_SLOT(x->p1, 0)) < 0 || (b = PK_SLOT(x->p3, 0)) < 0) return 0;
        o->k = PK_CMP; o->a = (u8)a; o->b = (u8)b; o->jnull = (x->p5 & SQLITE_JUMPIFNULL) != 0;
        o->lt = qv_LT[x->opcode]; o->eq = qv_EQ[x->opcode]; o->gt = qv_GT[x->opcode];
        break;
      }
      case OP_AggStep: case OP_AggStep1: {
        int r = x->p3, c = 0;
        if (x->opcode == OP_AggStep1 && x->p1) return 0;   /* (an inverse) */
        while (c < K.nacc && K.accReg[c] != r) c++;
        if (c < K.nacc || c >= QV_PK_ACC) return 0;   /* (one step per accumulator) */
        if (P->isCnt[r] && x->p5 <= 1) { o->k = PK_CNT; o->a = 255; if (x->p5 && (s = PK_SLOT(x->p2, 0)) < 0) return 0; if (x->p5) o->a = (u8)s; }
        else if (P->isSum[r] && x->p5 == 1) { if ((s = PK_SLOT(x->p2, 0)) < 0) return 0; o->k = PK_SUM; o->a = (u8)s; K.accSum[c] = 1; }
        else return 0;
        o->acc = (u8)c; K.accReg[c] = r; K.nacc++;
        break;
      }
      default: return 0;
    }
    K.nop++;
  }
#undef PK_SLOT
  if (!K.nacc) return 0;
  for (int s = 0; s < K.nslot; s++) {
    K.inv[s] = wrote[s] ? -1 : reg[s];
    if (wrote[s] && qv_par_read(aOp, P->nOp, reg[s], G->B, G->N)) return 0;   /* (the last row's value, read after the loop) */
  }
  QvPar *k = sqlite3_malloc(sizeof *k); if (k) *k = K;
  return k;
}
static void qv_par_free(QvPar *K) { if (K) { sqlite3_free(K->pg); sqlite3_free(K->res); sqlite3_free(K); } }

/* ---- a run: at the region's entry, from the cursor's row on. 2: the loop is done (the cursor at its end); 1: on row by
   row from the cursor's row (all of it, or from a miss); 0: fallback (qv_why) */
static int qv_par_run(QvX *X, QvRegion *G) {
  QvPar *K = G->par; QvPlan *P = X->P; QvCur *C = &X->c[G->cur]; BtCursor *bc = C->bc; i64 base[QV_PK_SLOTS];
  G->parOn = 0;   /* (set again when the helpers leave at a miss: the next page is theirs) */
  if (C->kind != QVC_BT || !C->isTable || C->deferred || !bc || bc->eState != CURSOR_VALID || !bc->pPage || !bc->pPage->intKeyLeaf) return 1;
  for (int s = 0; s < K->nslot; s++) {
    if (K->inv[s] < 0) { base[s] = 0; continue; }
    const Mem *m = &X->r[K->inv[s]]; if (!(m->flags & MEM_Int)) return 1;   /* (a NULL or another type bound: row by row) */
    base[s] = m->u.i;
  }
  for (int c = 0; c < K->nacc; c++) if (K->accSum[c] && P->sacc[K->accReg[c]].spilled) return 1;
  int W = 32 * (qvp.n + 1); if (W > 256) W = 256;
  if (K->cap < W) {
    QvParPg *pg = sqlite3_realloc64(K->pg, sizeof *pg * (u64)W); if (pg) K->pg = pg;
    QvParRes *rs = sqlite3_realloc64(K->res, sizeof *rs * (u64)W); if (rs) K->res = rs;
    if (!pg || !rs) return 1;
    K->cap = W;
  }
  if (QC_ST) QC_INC(qcs.par);
  int first = 1, eof = 0;
  while (!eof) {
    int n = 0;
    while (n < W) {   /* the window: the leaves from the cursor's on, each pinned, the cursor moved to the next leaf's first cell */
      MemPage *pp = bc->pPage; QvParPg *g = &K->pg[n];
      g->a = pp->aData; g->dp = pp->pDbPage; g->usable = X->usable; g->ix = first ? bc->ix : 0; g->n = pp->nCell;
      g->cellOffset = pp->cellOffset; g->maskPage = pp->maskPage; g->maxLocal = pp->maxLocal; g->minLocal = pp->minLocal;
      sqlite3PagerRef(g->dp); n++; first = 0;
      bc->ix = (u16)(pp->nCell - 1);
      int rc = sqlite3BtreeNext(bc, 0);
      if (rc == SQLITE_DONE) { eof = 1; break; }
      if (rc != SQLITE_OK || !qv_tick_check(X)) {   /* (an error, an interrupt, the progress handler: qv_tick_check's why) */
        for (int i = 0; i < n; i++) sqlite3PagerUnref(K->pg[i].dp);
        if (rc != SQLITE_OK) qv_why = "next";
        return 0;
      }
    }
    qv_par_job(K, K->pg, K->res, base, n);
    for (int i = 0; i < n; i++) {   /* merged in page order: the first miss and the rest row by row */
      QvParRes *o = &K->res[i]; int ok = !o->miss;
      for (int c = 0; c < K->nacc && ok; c++) if (K->accSum[c]) {
        __int128 s0 = P->sacc[K->accReg[c]].iSum;
        if (s0 + o->lo[c] < SMALLEST_INT64 || s0 + o->hi[c] > LARGEST_INT64) ok = 0;   /* (SQLite's running sum overflows in it) */
      }
      if (!ok) {
        const QvParPg *g = &K->pg[i]; const u8 *p = g->a + ((((u32)g->a[g->cellOffset + 2 * g->ix] << 8) | g->a[g->cellOffset + 2 * g->ix + 1]) & g->maskPage);
        u32 np; u64 rowid; int k = qv_pk_v32(p, g->a + g->usable, &np), res = 1;
        int k2 = k ? qv_pk_v64(p + k, g->a + g->usable, &rowid) : 0;
        for (int j = 0; j < n; j++) sqlite3PagerUnref(K->pg[j].dp);
        if (QC_ST) QC_INC(qcs.parMiss);
        if (!k2 || sqlite3BtreeTableMoveto(bc, (i64)rowid, 0, &res) != SQLITE_OK || res) { qv_why = "par: seek"; return 0; }
        C->nullRow = 0; qv_stale(C); G->parOn = 1;
        return 1;
      }
      for (int c = 0; c < K->nacc; c++) {
        int r = K->accReg[c];
        if (K->accSum[c]) { P->sacc[r].iSum += (i64)o->sum[c]; P->sacc[r].cnt += o->cnt[c]; }
        else P->cnt[r] += o->cnt[c];
      }
      G->iters += o->rows;
    }
    for (int i = 0; i < n; i++) sqlite3PagerUnref(K->pg[i].dp);
    if (QC_ST) __atomic_fetch_add(&qcs.parPages, (unsigned long long)n, __ATOMIC_RELAXED);
  }
  C->nullRow = 1; qv_stale(C);
  return 2;
}
#else
#define QV_PAR_ON 0
typedef struct QvPar QvPar;
static void qv_par_init(int n) { (void)n; }
static void qv_par_free(QvPar *K) { (void)K; }
#endif
