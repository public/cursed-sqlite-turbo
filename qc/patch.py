#!/usr/bin/env python3
"""patch.py [--step-hook] <sqlite3.c> <out.c>: the amalgamation with the hooks qc needs, each found by an exact anchor (the
script fails if an anchor is missing or appears twice, so a new SQLite version is caught at build time):
  1. struct Vdbe: pQc (the compiled plan), qcWant (lift again after a re-prepare), pQcTmpl (the JSON template);
  2. sqlite3VdbeSwap (a re-prepare swaps programs between two handles): qcWant and pQcTmpl stay with the handle;
  3. btreeEndTransaction: sqlite3QcTxnEnd closes the cursors plans keep open within a transaction;
  4. sqlite3VdbeClearObject (a statement's program is deleted): sqlite3QcFree frees its plan and template;
  5. sqlite3LeaveMutexAndCloseZombie (a connection is freed): sqlite3QcClose drops its plans from the plan cache.
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
             '\n  void *pQcTmpl;           /* the JSON output template (kept on the handle too) */') + s[j:]
s = s.replace('\nstruct Vdbe {\n', '\nstatic void (*sqlite3QcTxnEnd)(Btree*);   /* cursed-sqlite-turbo: closes cached cursors */\nstruct Vdbe;\nstatic void (*sqlite3QcFree)(struct Vdbe*);   /* cursed-sqlite-turbo: frees a deleted program\'s plan */\nstatic void (*sqlite3QcClose)(sqlite3*);   /* cursed-sqlite-turbo: a connection is freed: its cached plans go */\nstruct Vdbe {\n', 1)
old = '  pB->aCounter[SQLITE_STMTSTATUS_REPREPARE]++;\n}'
once(s, old, 'sqlite3VdbeSwap end')
s = s.replace(old, '  pB->aCounter[SQLITE_STMTSTATUS_REPREPARE]++;\n'
              '  { u8 t = pA->qcWant; pA->qcWant = pB->qcWant; pB->qcWant = t;\n'
              '    void *x = pA->pQcTmpl; pA->pQcTmpl = pB->pQcTmpl; pB->pQcTmpl = x; }   /* cursed-sqlite-turbo */\n}')
old = 'static void btreeEndTransaction(Btree *p){\n  BtShared *pBt = p->pBt;\n'
once(s, old, 'btreeEndTransaction')
s = s.replace(old, old + '  if( sqlite3QcTxnEnd ) sqlite3QcTxnEnd(p);   /* cursed-sqlite-turbo */\n')
old = 'static void sqlite3VdbeClearObject(sqlite3 *db, Vdbe *p){\n  SubProgram *pSub, *pNext;\n'
once(s, old, 'sqlite3VdbeClearObject')
s = s.replace(old, old + '  if( sqlite3QcFree && (p->pQc || p->pQcTmpl) ) sqlite3QcFree(p);   /* cursed-sqlite-turbo */\n')
old = '  /* If we reach this point, it means that the database connection has\n  ** closed all sqlite3_stmt and sqlite3_backup objects and has been\n'
once(s, old, 'sqlite3LeaveMutexAndCloseZombie')
s = s.replace(old, '  if( sqlite3QcClose ) sqlite3QcClose(db);   /* cursed-sqlite-turbo */\n' + old)
if step_hook:
  old = 'SQLITE_API int sqlite3_step(sqlite3_stmt *pStmt){\n'
  once(s, old, 'sqlite3_step')
  s = s.replace(old, 'static int sqlite3_step_orig(sqlite3_stmt *pStmt){   /* cursed-sqlite-turbo tests: wrapped by tests/tcl_qc.c */\n')
open(out, 'w', encoding='latin-1').write(s)
