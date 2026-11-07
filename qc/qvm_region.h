/* qvm_region.h: qv_region, #included by qvm.c, twice when built with -DQV_RGSEEK=1: QV_RG_FN qv_region_s with QV_RG_SEEK 1 runs the regions with point
   lookups (G->seek: SeekRowid, NotExists, DeferredSeek, NullRow and RG_IDXLOAD nodes, a Column's row load through n->hf);
   qv_region with QV_RG_SEEK 0 runs the others and hands those to qv_region_s. One function with every node compiled
   qv_region's other nodes worse under gcc -O2: sqlite3VdbeMemClearAndResize no longer in line in qv_colval's copy,
   atuin store.status 1.02 of its instructions natively, 1.06-1.09 of its cycles on box2 (exp1326) */
#if QV_RG_SEEK
#define QV_RG_EAGER && !G->lazy
#else
#define QV_RG_EAGER
#endif
static int QV_RG_FN(QvX *X, QvRegion *G, int *pcOut) {
  static const void *const L[RG_N] = {
    [RG_EXIT] = &&rg_exit, [RG_NOP] = &&rg_nop, [RG_GOTO] = &&rg_goto, [RG_COL] = &&rg_col, [RG_COLI] = &&rg_coli,
    [RG_ROWID] = &&rg_rowid, [RG_IDXROWID] = &&rg_idxrowid, [RG_CMP] = &&rg_cmp, [RG_CMPI] = &&rg_cmpi, [RG_CMPT] = &&rg_cmpt, [RG_REALAFF] = &&rg_realaff, [RG_COLLSEQ] = &&rg_collseq, [RG_ONCE] = &&rg_once, [RG_IF] = &&rg_if,
    [RG_IFNOT] = &&rg_ifnot, [RG_ISNULL] = &&rg_isnull, [RG_NOTNULL] = &&rg_notnull, [RG_INT] = &&rg_int, [RG_INT64] = &&rg_int64,
    [RG_STR] = &&rg_str, [RG_NULL] = &&rg_null, [RG_SCOPY] = &&rg_scopy, [RG_COPY] = &&rg_copy, [RG_ARITH] = &&rg_arith,
    [RG_FUNC] = &&rg_func, [RG_AGG] = &&rg_agg, [RG_RESULT] = &&rg_result, [RG_IFPOS] = &&rg_ifpos, [RG_IFNZ] = &&rg_ifnz,
    [RG_DJZ] = &&rg_djz, [RG_IDXCMP] = &&rg_idxcmp, [RG_MKREC] = &&rg_mkrec, [RG_SORTINS] = &&rg_sortins,
    [RG_COMPARE] = &&rg_compare, [RG_JUMPCMP] = &&rg_jumpcmp, [RG_MOVE] = &&rg_move, [RG_BITOP] = &&rg_bitop, [RG_PERM] = &&rg_perm, [RG_GOSUB] = &&rg_gosub, [RG_NEXT] = &&rg_next, [RG_RESULTS] = &&rg_results,
    [RG_SORTERDATA] = &&rg_sorterdata, [RG_PCOL] = &&rg_pcol, [RG_SORTERNEXT] = &&rg_sorternext,
#if QV_RG_SEEK
    [RG_SEEKROWID] = &&rg_seekrowid, [RG_DSEEK] = &&rg_dseek, [RG_NULLROW] = &&rg_nullrow, [RG_IDXLOAD] = &&rg_idxload };
  if (!G) { qv_rgl_s = L; return 1; }
#else
    [RG_SEEKROWID] = &&rg_exit, [RG_DSEEK] = &&rg_exit, [RG_NULLROW] = &&rg_exit, [RG_IDXLOAD] = &&rg_exit };   /* (qv_region_s's kinds) */
#if QV_RGSEEK
  if (!G) { qv_rgl = L; qv_region_s(0, 0, 0); return 1; }
  if (G->seek) return qv_region_s(X, G, pcOut);   /* (a region with point lookups: qv_run's calls stay as they were) */
#else
  if (!G) { qv_rgl = L; return 1; }
#endif
#if QV_PAR_ON
  if (G->par && *pcOut == G->B) { int r = qv_par_run(X, G); if (r != 1) { if (r == 2) *pcOut = G->N + 1; return r == 2; } }   /* (1: on from its row) */
#endif
#endif
  QvNode *n = &G->n[*pcOut - G->B]; Mem *R = X->r; QvCur *Cs = X->c;
#define RG_GO(i) do { n = &G->n[i]; QV_TRACE_AT(n->pc, n->op->opcode); goto *n->h; } while (0)
#define RG_NEXT do { n++; QV_TRACE_AT(n->pc, n->op->opcode); goto *n->h; } while (0)
#define RG_JUMP do { if (n->jn >= 0) RG_GO(n->jn); *pcOut = n->op->p2; return 1; } while (0)   /* (out of the body: the loop ends) */
#define RG_OUT(r) (n->plain ? qv_rel(n->o) : qv_out(X, (r)))
  /* the region cursor's header parsed through the body's last field, the first time a Column needs one not yet parsed; its row loaded first
     if rg_next didn't (no Column before the branch that skips a row: an OFFSET's rows cost a cursor step, as in SQLite) */
#define RG_HDR(C, p2) do { if ((p2) >= (C)->nHdr && n->op->p1 == G->rc && !(C)->nullRow && !(C)->deferred && (C)->kind == QVC_BT) { \
    if (!(C)->rowOk && !qv_row(X, (C))) return 0;   /* (rg_next's unloaded row: its nHdr 0) */ \
    if (!(C)->nullRow && (p2) >= (C)->nHdr) { \
      int f_ = G->maxfAll < (C)->nField ? G->maxfAll : (C)->nField - 1; if (f_ < (p2)) f_ = (p2); if (!qv_hdr((C), f_)) return 0; } } } while (0)
  QV_TRACE_AT(n->pc, n->op->opcode);
  goto *n->h;
rg_exit:   /* an opcode without a node: qv_run's, and back at the next Next */
  *pcOut = n->pc;
#if QV_RGSEEK
  if (++G->exits > 64 && G->exits > G->iters / 4) { G->off = 1; X->P->rgAt[G->N] = 0; }   /* it leaves too often: qv_run's from now on (its Next
                                                                                              as with no region: testing off cost wakapi entity_set_machines
                                                                                              +0.18 %, its DeferredSeek loop's region off) */
#else
  if (++G->exits > 64 && G->exits > G->iters / 4) G->off = 1;   /* it leaves too often: qv_run's from now on */
#endif
  return 1;
rg_nop: RG_NEXT;
rg_goto: RG_JUMP;
rg_col: {
    QvCur *C = n->C; int p2 = n->op->p2;
    RG_HDR(C, p2);
    if (C->rowOk && !C->nullRow && !C->deferred && C->kind == QVC_BT && p2 < C->nHdr) {   /* the row's header is parsed: qv_column's last step */
#if QV_RG_SEEK
    rg_col_at:;
#endif
      Mem *o = RG_OUT(n->op->p3); u32 t = C->aType[p2];
      if (!qv_colval(X, C, t, C->row + C->aOff[p2], o)) return 0;
      RG_NEXT;
    }
#if QV_RG_SEEK
    if (n->hf >= 0 && C->kind == QVC_BT && !(C->deferred && C->altMap) && p2 < C->nField) {   /* another cursor's row, just positioned (a point
                                                                                                 lookup, a deferred seek): loaded, and its header parsed
                                                                                                 through the region's last field on it, once */
      if (C->nullRow) { RG_OUT(n->op->p3)->flags = MEM_Null; RG_NEXT; }   /* (a LEFT JOIN's missing row) */
      if (!qv_row(X, C)) return 0;
      if (!C->nullRow) {
        int f = n->hf < C->nField ? n->hf : C->nField - 1;
        if (C->nHdr <= f && !qv_hdr(C, f)) return 0;
        if (p2 < C->nHdr) goto rg_col_at;
      }
    }
#endif
    if (!qv_colop_cold(X, R, Cs, n->op)) return 0;
    RG_NEXT;
  }
rg_coli: {   /* speculated: a number or NULL (serial types 0-9; integers tested first) */
    QvCur *C = n->C; int p2 = n->op->p2;
    RG_HDR(C, p2);
    if (C->rowOk && !C->nullRow && !C->deferred && C->kind == QVC_BT && p2 < C->nHdr) {
      u32 t = C->aType[p2];
      if (t - 1 < 6) { qv_int(qv_rel(n->o), qc_int(t, C->row + C->aOff[p2])); RG_NEXT; }
      if (t - 8 < 2) { qv_int(qv_rel(n->o), (i64)t - 8); RG_NEXT; }
      if (t == 7) { double r = qv_real(C->row + C->aOff[p2]); Mem *o = qv_rel(n->o); if (r != r) o->flags = MEM_Null; else { o->flags = MEM_Real; o->u.r = r; } RG_NEXT; }   /* (NaN reads as NULL) */
      if (t == 0) { qv_rel(n->o)->flags = MEM_Null; RG_NEXT; }
      n->h = L[RG_COL]; G->misses++; if (QC_ST) QC_INC(qcs.widen);   /* the guess failed: a generic Column from now on */
    }
    goto rg_col;
  }
rg_rowid: {
    QvCur *C = n->C;
#if QV_RG_SEEK
    if (C->kind != QVC_BT) goto rg_exit;
    if (C->nullRow) { RG_OUT(n->op->p2)->flags = MEM_Null; RG_NEXT; }   /* (qv_run's: a LEFT JOIN's missing row) */
    if (C->deferred || sqlite3BtreeCursorHasMoved(C->bc)) goto rg_exit;   /* (a deferred seek's target: SQLite reads its index's rowid instead) */
#else
    if (C->kind != QVC_BT || C->nullRow || C->deferred || sqlite3BtreeCursorHasMoved(C->bc)) goto rg_exit;
#endif
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
    n->h = L[RG_CMP]; G->misses++; if (QC_ST) QC_INC(qcs.widen);
    goto rg_cmp;
  }
rg_cmpt: {   /* speculated: two plain UTF-8 strings, the op's collation BINARY or none and its affinity TEXT or below (checked when
                the node was made): qv_compare_str's memcmp, without its call and its checks of the op (D1) */
    const Mem *a = n->a, *b = n->b;
    if (QV_TXT(a->flags) && QV_TXT(b->flags) && a->enc == SQLITE_UTF8 && b->enc == SQLITE_UTF8) {
      int k = b->n < a->n ? b->n : a->n, res = memcmp(b->z, a->z, (size_t)k); if (!res) res = b->n - a->n;
      X->iCompare = res;
      if (res < 0 ? n->lt : res ? n->gt : n->eq) RG_JUMP;
      RG_NEXT;
    }
    if (((a->flags | b->flags) & MEM_Null) && !(n->op->p5 & SQLITE_NULLEQ)) {   /* a NULL (feedback of text or NULL): qv_compare_slow's
                                                                                   result without its call (a NULL bound to a scan's filter) */
      X->iCompare = 1;
      if (n->op->p5 & SQLITE_JUMPIFNULL) RG_JUMP;
      RG_NEXT;
    }
    n->h = L[RG_CMP]; G->misses++; if (QC_ST) QC_INC(qcs.widen);
    goto rg_cmp;
  }
rg_realaff: if (n->a->flags & (MEM_Int | MEM_IntReal)) sqlite3VdbeMemRealify(n->a); RG_NEXT;   /* (qv_run's: a REAL column's integer, a float) */
rg_collseq: if (n->op->p1) qv_int(RG_OUT(n->op->p1), 0); RG_NEXT;   /* (qv_run's: min()'s and max()'s flag, set by their AggStep) */
rg_once: if (X->once[n->pc >> 3] & (1 << (n->pc & 7))) RG_JUMP; X->once[n->pc >> 3] |= (u8)(1 << (n->pc & 7)); RG_NEXT;   /* (qv_run's) */
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
      i64 iB = b->u.i; int ovf = n->ar == 1 ? QV_ADD64(&iB, a->u.i) : n->ar == 2 ? QV_SUB64(&iB, a->u.i) : QV_MUL64(&iB, a->u.i);
      if (!ovf) { qv_int(qv_rel(n->o), iB); RG_NEXT; }
    }
    if (!qv_arith_fast(X, n->op)) qv_arith(X, n->op);
    RG_NEXT;
  }
rg_func: if (!qv_function(X, n->op, n->pc)) return 0; RG_NEXT;
rg_agg: if (!qv_aggop(X, R, Cs, n->op, n->pc)) return 0; RG_NEXT;
rg_result: if (!qv_result(X, R, Cs, n->op)) return 0; RG_NEXT;
rg_results:   /* streamed: the row handed out, the region entered again at the next node (qv_stream_resume) */
  if (!qv_strm_term(&R[n->op->p1], n->op->p2)) return 0;
  *pcOut = X->pc0 = n->pc + 1; X->res = &R[n->op->p1]; X->rgRes = G; X->nrow++; return 3;
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
rg_gosub: qv_int(qv_out(X, n->op->p1), n->pc); if (G->rc != G->cur) X->rgRet = G; RG_JUMP;   /* a subroutine (a group's output): qv_run's,
                                                                                                back at the next Next, or a sorter loop's at the Return */
rg_next: {   /* the loop's Next / Prev (qv_run's B-tree case), then the next row fetched and decoded */
    QvCur *C = n->C; const Op *op = n->op; int rc;
    G->iters++;
    if (C->kind != QVC_BT && C->kind != QVC_EPH) goto rg_exit;
    rc = op->opcode == OP_Next ? sqlite3BtreeNext(C->bc, op->p3) : sqlite3BtreePrevious(C->bc, op->p3);
    qv_stale(C);
    if (rc == SQLITE_OK) {
      C->nullRow = 0;
      if (C->bc->ix == 0) {
        if (!qv_tick_check(X)) return 0;   /* (a region walks a finite B-tree: checked per page it enters, not per row) */
#if QV_PAR_ON
        if (G->parOn) { int r = qv_par_run(X, G); if (r != 1) { if (r == 2) *pcOut = n->pc + 1; return r == 2; } }   /* (the helpers' again, past a miss) */
#endif
      }
      if (G->maxf >= 0 && C->kind == QVC_BT QV_RG_EAGER) {   /* the row loaded for the Columns before the body's first branch that skips it,
                                                                 its header parsed through those */
        if (!qv_row(X, C)) return 0;
        int f = G->maxf < C->nField ? G->maxf : C->nField - 1;
        if (f >= 0 && !C->nullRow && C->nHdr <= f && !qv_hdr(C, f)) return 0;
      } else C->nHdr = 0;   /* without any, not loaded: RG_HDR loads it for a row that gets past, its first test seeing nHdr 0 (technitium
                               last_page: each of the 250k rows its OFFSET skips was loaded, 2.5x SQLite's instructions). (Stale, so
                               harmless on any cursor: qv_row sets nHdr again) */
      RG_GO(0);
    }
    if (rc != SQLITE_DONE) { qv_why = "next"; return 0; }
    C->nullRow = 1; *pcOut = n->pc + 1;
    return 1;
  }
rg_sorterdata:   /* qv_run's; the region's record also loaded into its pseudo cursor, its header parsed as rg_next's */
  if (!qv_sorterdata(X, Cs, n->op)) return 0;
  if (n->ar) {
    QvCur *C = n->C;
    if (C->kind == QVC_PSEUDO && C->pseudoReg == n->op->p2) {
      if (!qv_row(X, C)) return 0;
      int f = G->maxf < C->nField ? G->maxf : C->nField - 1;
      if (f >= 0 && !qv_hdr(C, f)) return 0;
    }
  }
  RG_NEXT;
rg_pcol: {   /* a Column on the sorter loop's pseudo cursor: the record still in its register (qv_row_ok's test) and parsed, qv_column's last step */
    QvCur *C = n->C; int p2 = n->op->p2; const Mem *r = &R[C->pseudoReg];
    if (C->rowOk && p2 < C->nHdr && C->kind == QVC_PSEUDO && C->row == (const u8 *)r->z && C->szRow == (u32)r->n && (r->flags & MEM_Blob)
        && n->op->p3 != C->pseudoReg) {
      if (!qv_colval(X, C, C->aType[p2], C->row + C->aOff[p2], RG_OUT(n->op->p3))) return 0;
      RG_NEXT;
    }
    if (!qv_colop_cold(X, R, Cs, n->op)) return 0;
    RG_NEXT;
  }
#if QV_RG_SEEK
rg_idxload: {   /* a lazy region's first node: its Idx bound, then the row rg_next didn't load (not the one past the range's end: a join's
                   inner loop ends once per outer row, zotero load_tags) */
    int r = qv_idxcmp(X, R, Cs, n->op); if (r < 0) return 0; if (r) RG_JUMP;
    QvCur *C = n->C;
    if (G->maxfAll >= 0 && C->kind == QVC_BT && !C->rowOk && !C->nullRow && !qv_rg_rowload(X, C, G->maxf)) return 0;
    RG_NEXT;
  }
rg_seekrowid: { int r = qv_seekrowid(X, R, Cs, n->op); if (r < 0) return 0; if (!r) RG_JUMP; RG_NEXT; }   /* (another cursor's: a join's point lookup) */
rg_dseek: if (!qv_dseek(X, R, Cs, n->op)) return 0; RG_NEXT;
rg_nullrow: qv_nullrow(X, Cs, n->op); RG_NEXT;   /* (a LEFT JOIN's row with no match) */
#endif
rg_sorternext: {   /* the loop's SorterNext (qv_run's), then the next record */
    G->iters++;
    int r = qv_sorternext(X, n->C);
    if (r > 0) { if (!qv_tick(X)) return 0; RG_GO(0); }
    if (r < 0) return 0;
    *pcOut = n->pc + 1;
    return 1;
  }
#undef RG_GO
#undef RG_NEXT
#undef RG_JUMP
#undef RG_OUT
#undef RG_HDR
}
#undef QV_RG_EAGER
