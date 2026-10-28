#!/usr/bin/env python3
"""compare.py <dir> [arms...]: corpus/run.sh check's <arm>.check.tsv against stock's, statement by statement. A
statement agrees when status, row count, changes and error text are the same and its rows hash the same: in order
when it has ORDER BY (prep.py's ordered flag), as a multiset otherwise. Prints the disagreements (each one a bug to
reduce), statements that fail or disagree with themselves in stock too, and how many executions each arm served."""
import sys, os, glob, collections
d = sys.argv[1]; arms = sys.argv[2:] or ['stock', 'serve']
ordered, tags = {}, {}
for f in glob.glob(os.path.join(d, 'q', '*.q')):
    for l in open(f):
        if l.startswith('@@Q '):
            p = l.split(); ordered[p[1]] = p[2] == '1'; tags[p[1]] = p[4].split(',')
def load(arm):
    r = {}
    for l in open(os.path.join(d, f'{arm}.check.tsv'), errors='replace'):
        p = l.rstrip('\n').split('\t')
        if p[0] == 'C' and len(p) >= 9: r[p[1]] = dict(st=p[2], rows=p[3], ch=p[4], h=p[5], hs=p[6], served=p[7], err=p[8])
    return r
S = load('stock')
print(f'stock: {len(S)} statements; {sum(x["st"] == "err" for x in S.values())} errors, '
      f'{sum(x["st"] == "unstable" for x in S.values())} unstable (runs disagree)')
for i, x in S.items():
    if x['st'] != 'ok': print(f'  stock {x["st"]}: {i}: {x["err"][:160]}')
bad = 0
for arm in arms:
    if arm == 'stock': continue
    A = load(arm); diff = []
    for i, s in S.items():
        a = A.get(i)
        if a is None: diff.append((i, 'missing')); continue
        key = 'h' if ordered.get(i) else 'hs'
        why = [k for k in ('st', 'rows', 'ch', 'err') if a[k] != s[k]]
        if a[key] != s[key] and 'rows' not in why: why.append('rows differ' + (' (in order)' if key == 'h' else ''))
        if why: diff.append((i, ', '.join(why) + f'; stock {s["st"]} {s["rows"]} rows {s["err"][:80]} / {arm} {a["st"]} {a["rows"]} rows {a["err"][:120]}'))
    served = [int(a['served'].split('/')[0]) for a in A.values()]
    full = sum(1 for a in A.values() if a['served'].split('/')[0] == a['served'].split('/')[1] and a['served'] != '0/0')
    part = sum(1 for a in A.values() if 0 < int(a['served'].split('/')[0]) < int(a['served'].split('/')[1]))
    print(f'\n{arm}: {len(A)} statements; {len(diff)} disagree with stock; served: {full} statements every run, {part} some runs, '
          f'{sum(1 for v in served if v == 0)} never')
    for i, w in diff: print(f'  DIFF {i}: {w}')
    bad += len(diff)
    by = collections.Counter(); tot = collections.Counter()
    for i, a in A.items():
        for t in tags.get(i, []): tot[t] += 1; by[t] += a['served'].split('/')[0] != '0'
    print(f'  served by tag (statements served at least once / all): ' + ', '.join(f'{t} {by[t]}/{tot[t]}' for t, _ in tot.most_common(30)))
sys.exit(1 if bad else 0)
