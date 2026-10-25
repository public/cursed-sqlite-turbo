#!/usr/bin/env python3
"""patch.py <sqlite3.c> <out.c>: the amalgamation with the three hooks qc needs, each found by an exact anchor (the
script fails if an anchor is missing or appears twice, so a new SQLite version is caught at build time):
  1. struct Vdbe: pQc (the compiled plan), qcWant (lift again after a re-prepare), pQcTmpl (the JSON template);
  2. sqlite3VdbeSwap (a re-prepare swaps programs between two handles): qcWant and pQcTmpl stay with the handle;
  3. btreeEndTransaction: sqlite3QcTxnEnd closes the cursors plans keep open within a transaction.
Nothing else in SQLite changes; a statement that is not compiled runs exactly as before."""
import sys

def once(s, anchor, what):
    n = s.count(anchor)
    if n != 1: sys.exit(f'qc/patch.py: {what}: anchor found {n} times')

src, out = sys.argv[1], sys.argv[2]
s = open(src, encoding='latin-1').read()
once(s, '\nstruct Vdbe {\n', 'struct Vdbe')
i = s.index('\nstruct Vdbe {\n'); j = s.index('\n};', i)
s = s[:j] + ('\n  void *pQc;               /* cursed-sqlite-jit: the compiled plan, or 0 */'
             '\n  u8 qcWant;               /* lift again after a re-prepare (kept on the handle by sqlite3VdbeSwap) */'
             '\n  void *pQcTmpl;           /* the JSON output template (kept on the handle too) */') + s[j:]
s = s.replace('\nstruct Vdbe {\n', '\nstatic void (*sqlite3QcTxnEnd)(Btree*);   /* cursed-sqlite-jit: closes cached cursors */\nstruct Vdbe {\n', 1)
old = '  pB->aCounter[SQLITE_STMTSTATUS_REPREPARE]++;\n}'
once(s, old, 'sqlite3VdbeSwap end')
s = s.replace(old, '  pB->aCounter[SQLITE_STMTSTATUS_REPREPARE]++;\n'
              '  { u8 t = pA->qcWant; pA->qcWant = pB->qcWant; pB->qcWant = t;\n'
              '    void *x = pA->pQcTmpl; pA->pQcTmpl = pB->pQcTmpl; pB->pQcTmpl = x; }   /* cursed-sqlite-jit */\n}')
old = 'static void btreeEndTransaction(Btree *p){\n  BtShared *pBt = p->pBt;\n'
once(s, old, 'btreeEndTransaction')
s = s.replace(old, old + '  if( sqlite3QcTxnEnd ) sqlite3QcTxnEnd(p);   /* cursed-sqlite-jit */\n')
open(out, 'w', encoding='latin-1').write(s)
