#!/usr/bin/env python3
"""patch.py [--step-hook] <sqlite3.c> <out.c>: the amalgamation with the hooks qc needs, each found by an exact anchor (the
script fails if an anchor is missing or appears twice, so a new SQLite version is caught at build time):
  1. struct Vdbe: pQc (the compiled plan), qcWant (lift again after a re-prepare), pQcTmpl (the JSON template);
  2. sqlite3VdbeSwap (a re-prepare swaps programs between two handles): qcWant and pQcTmpl stay with the handle;
  3. btreeEndTransaction: sqlite3QcTxnEnd closes the cursors plans keep open within a transaction;
  4. sqlite3VdbeClearObject (a statement's program is deleted): sqlite3QcFree frees its plan and template;
  5. sqlite3LeaveMutexAndCloseZombie (a connection is freed): sqlite3QcClose drops its plans from the plan cache;
  6. sqlite3_step and sqlite3Step: sqlite3QcStart (a statement about to start, and again after the re-prepare a new
     binding forces on a statement whose plan looked at one) and sqlite3QcServe (in place of
     sqlite3VdbeExec), for serving qc's rows through SQLite's own API (qc.c, sqlite3_qc_serve). Both are 0 unless
     serving is turned on; struct Vdbe gets pQcRows (the rows being served, kept with the handle), qcServe (this run
     is served: otherwise sqlite3Step calls sqlite3VdbeExec directly) and qcNo (refused: sqlite3QcStart isn't called;
     a re-prepare's new program starts at 0, so a schema change tries it again). sqlite3Step is marked always_inline:
     qc's interpreter samples call it too, which made compilers stop inlining it into sqlite3_step.
  7. sqlite3VdbeReset (sqlite3_reset, finalize): sqlite3QcReset ends a streamed run the statement leaves; while a
     stream is suspended (sqlite3QcBusy) sqlite3_step calls sqlite3QcStart for refused (qcNo) statements too, so the
     stream is drained before any other statement runs (QC_STREAM). struct Vdbe gets qcPark: a parked plan's executions
     left, run without sqlite3QcStart (qc's adapt counted them when it parked it).
  8. sqlite3ExpirePreparedStatements (a function, collation or module changed, ANALYZE, a schema change): sqlite3QcEpoch
     counts the calls, so qc's plan cache knows when a program generated from the same text may differ.
Nothing else in SQLite changes; a statement that is not compiled runs exactly as before."""
import sys

def once(s, anchor, what):
    n = s.count(anchor)
    if n != 1: sys.exit(f'qc/patch.py: {what}: anchor found {n} times')

args = [a for a in sys.argv[1:] if not a.startswith('--')]
step_hook = '--step-hook' in sys.argv   # tests only (tests/tcl_qc.c): sqlite3_step becomes sqlite3_step_orig, wrapped
src, out = args[0], args[1]
s = open(src, encoding='latin-1').read()
once(s, '\nstruct Vdbe {\n', 'struct Vdbe')
i = s.index('\nstruct Vdbe {\n'); j = s.index('\n};', i)
s = s[:j] + ('\n  void *pQc;               /* cursed-sqlite-turbo: the compiled plan, or 0 */'
             '\n  u8 qcWant;               /* lift again after a re-prepare (kept on the handle by sqlite3VdbeSwap) */'
             '\n  void *pQcTmpl;           /* the JSON output template (kept on the handle too) */'
             '\n  void *pQcRows;           /* rows qc is serving through sqlite3_step (kept on the handle too) */'
             '\n  u8 qcServe;              /* this run\'s rows come from pQcRows (sqlite3Step calls sqlite3QcServe) */'
             '\n  u8 qcNo;                 /* qc refused this program: sqlite3_step does not call sqlite3QcStart */'
             '\n  u32 qcPark;              /* parked: executions sqlite3_step still runs without calling sqlite3QcStart */') + s[j:]
s = s.replace('\nstruct Vdbe {\n', '\nstatic void (*sqlite3QcTxnEnd)(Btree*);   /* cursed-sqlite-turbo: closes cached cursors */\nstruct Vdbe;\nstatic void (*sqlite3QcFree)(struct Vdbe*);   /* cursed-sqlite-turbo: frees a deleted program\'s plan */\nstatic void (*sqlite3QcClose)(sqlite3*);   /* cursed-sqlite-turbo: a connection is freed: its cached plans go */\nstatic void (*sqlite3QcStart)(struct Vdbe*);   /* cursed-sqlite-turbo: a statement about to start (serving) */\nstatic int (*sqlite3QcServe)(struct Vdbe*);   /* cursed-sqlite-turbo: in place of sqlite3VdbeExec (serving) */\nstatic void (*sqlite3QcReset)(struct Vdbe*);   /* cursed-sqlite-turbo: a statement reset or finalized (a stream ends) */\nstatic int sqlite3QcBusy;   /* cursed-sqlite-turbo: a stream is suspended: sqlite3QcStart for every statement */\nstatic unsigned sqlite3QcEpoch;   /* cursed-sqlite-turbo: counts sqlite3ExpirePreparedStatements calls (for the plan cache) */\nstruct Vdbe {\n', 1)
old = '  pB->aCounter[SQLITE_STMTSTATUS_REPREPARE]++;\n}'
once(s, old, 'sqlite3VdbeSwap end')
s = s.replace(old, '  pB->aCounter[SQLITE_STMTSTATUS_REPREPARE]++;\n'
              '  { u8 t = pA->qcWant; pA->qcWant = pB->qcWant; pB->qcWant = t;\n'
              '    void *x = pA->pQcTmpl; pA->pQcTmpl = pB->pQcTmpl; pB->pQcTmpl = x;\n'
              '    x = pA->pQcRows; pA->pQcRows = pB->pQcRows; pB->pQcRows = x; }   /* cursed-sqlite-turbo */\n}')
old = 'static void btreeEndTransaction(Btree *p){\n  BtShared *pBt = p->pBt;\n'
once(s, old, 'btreeEndTransaction')
s = s.replace(old, old + '  if( sqlite3QcTxnEnd ) sqlite3QcTxnEnd(p);   /* cursed-sqlite-turbo */\n')
old = 'static void sqlite3VdbeClearObject(sqlite3 *db, Vdbe *p){\n  SubProgram *pSub, *pNext;\n'
once(s, old, 'sqlite3VdbeClearObject')
s = s.replace(old, old + '  if( sqlite3QcFree && (p->pQc || p->pQcTmpl || p->pQcRows) ) sqlite3QcFree(p);   /* cursed-sqlite-turbo */\n')
old = '    db->nVdbeExec++;\n    rc = sqlite3VdbeExec(p);\n    db->nVdbeExec--;\n'
once(s, old, 'sqlite3Step: sqlite3VdbeExec')
s = s.replace(old, '    db->nVdbeExec++;\n    rc = p->qcServe && sqlite3QcServe ? sqlite3QcServe(p) : sqlite3VdbeExec(p);   /* cursed-sqlite-turbo */\n    db->nVdbeExec--;\n')
old = '  db = v->db;\n  sqlite3_mutex_enter(db->mutex);\n  while( (rc = sqlite3Step(v))==SQLITE_SCHEMA\n'
once(s, old, 'sqlite3_step: the loop')
s = s.replace(old, '  db = v->db;\n  sqlite3_mutex_enter(db->mutex);\n  if( sqlite3QcStart && v->eVdbeState==VDBE_READY_STATE ){ if( v->qcPark && !sqlite3QcBusy ) v->qcPark--; else if( !v->qcNo || sqlite3QcBusy ) sqlite3QcStart(v); }   /* cursed-sqlite-turbo */\n  while( (rc = sqlite3Step(v))==SQLITE_SCHEMA\n')
old = '    assert( v->expired==0 );\n  }\n  sqlite3_mutex_leave(db->mutex);\n'
once(s, old, 'sqlite3_step: after a re-prepare')   # (a statement whose plan looked at a binding is expired by every new binding: served after its re-prepare)
s = s.replace(old, '    assert( v->expired==0 );\n    if( sqlite3QcStart && v->eVdbeState==VDBE_READY_STATE ){ if( v->qcPark && !sqlite3QcBusy ) v->qcPark--; else if( !v->qcNo || sqlite3QcBusy ) sqlite3QcStart(v); }   /* cursed-sqlite-turbo */\n  }\n  sqlite3_mutex_leave(db->mutex);\n')
old = '  ** it now.\n  */\n  if( p->eVdbeState==VDBE_RUN_STATE ) sqlite3VdbeHalt(p);\n'
once(s, old, 'sqlite3VdbeReset: halt')
s = s.replace(old, '  ** it now.\n  */\n  if( sqlite3QcBusy && sqlite3QcReset && p->pQcRows ) sqlite3QcReset(p);   /* cursed-sqlite-turbo */\n  if( p->eVdbeState==VDBE_RUN_STATE ) sqlite3VdbeHalt(p);\n')
old = 'SQLITE_PRIVATE void sqlite3ExpirePreparedStatements(sqlite3 *db, int iCode){\n  Vdbe *p;\n'
once(s, old, 'sqlite3ExpirePreparedStatements')
s = s.replace(old, old + '  sqlite3QcEpoch++;   /* cursed-sqlite-turbo */\n')
old = 'static int sqlite3Step(Vdbe *p){\n'
once(s, old, 'sqlite3Step')   # (qc calls it too, for its interpreter samples: kept inlined into sqlite3_step, as in stock)
s = s.replace(old, '#if defined(__GNUC__)\n__attribute__((always_inline)) inline   /* cursed-sqlite-turbo */\n#endif\nstatic int sqlite3Step(Vdbe *p){\n')
old = '  /* If we reach this point, it means that the database connection has\n  ** closed all sqlite3_stmt and sqlite3_backup objects and has been\n'
once(s, old, 'sqlite3LeaveMutexAndCloseZombie')
s = s.replace(old, '  if( sqlite3QcClose ) sqlite3QcClose(db);   /* cursed-sqlite-turbo */\n' + old)
if step_hook:
  old = 'SQLITE_API int sqlite3_step(sqlite3_stmt *pStmt){\n'
  once(s, old, 'sqlite3_step')
  s = s.replace(old, 'static int sqlite3_step_orig(sqlite3_stmt *pStmt){   /* cursed-sqlite-turbo tests: wrapped by tests/tcl_qc.c */\n')
open(out, 'w', encoding='latin-1').write(s)
