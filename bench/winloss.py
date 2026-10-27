#!/usr/bin/env python3
"""winloss.py <speedtest1-dir> <tpch-dir> <clickbench-dir> [clickbench-queries.sql]: the win/loss map by query shape.
Each query or test gets turbo/stock and qvm/stock (medians over rounds, as summarise.py / compare.py compute them) and
a class from bench/classes.tsv (ClickBench: from its SQL text). Prints one Markdown row per class: how many items,
the geometric means of turbo/stock and qvm/stock, turbo's range, and the items. Items that take stock under 0.5 ms
(ClickBench's empty filters at 300k rows) are left out: their ratios are timer noise."""
import sys, os, re, glob, math, statistics
here = os.path.dirname(os.path.abspath(__file__))
cls = {}
for l in open(os.path.join(here, 'classes.tsv')):
    if l.startswith('#') or not l.strip(): continue
    s, q, c = l.rstrip('\n').split('\t'); cls[(s, q)] = c

def sp_medians(d):   # speedtest1: test number -> arm -> median seconds
    r = {}
    for f in glob.glob(os.path.join(d, '*.txt')):
        arm = os.path.basename(f).split('.')[0]
        for l in open(f, errors='replace'):
            m = re.match(r'\s*(\d+) - .*?\s+(\d+\.\d+)s\s*$', l)
            if m: r.setdefault(m.group(1), {}).setdefault(arm, []).append(float(m.group(2)))
    return {t: {a: statistics.median(v) for a, v in x.items()} for t, x in r.items()}
def q_medians(d):    # qrun tsv: query -> arm -> median of per-round medians (ms)
    r = {}
    for f in glob.glob(os.path.join(d, '*.tsv')):
        arm = os.path.basename(f).split('.')[0]
        for l in open(f):
            p = l.rstrip('\n').split('\t')
            if p[0] == 'Q': r.setdefault(p[1], {}).setdefault(arm, []).append(float(p[5]))
    return {q: {a: statistics.median(v) for a, v in x.items()} for q, x in r.items()}
def cb_class(sql):
    s = sql.upper()
    if ' LIKE ' in s: return 'scan-expr'
    if 'DISTINCT' in s: return 'distinct'
    if 'GROUP BY' in s: return 'agg'
    if 'ORDER BY' in s and 'LIMIT' in s: return 'topn'
    if 'WHERE' in s and re.search(r'= -?\d+\s*;?\s*$', s.strip()): return 'point'
    return 'agg'

items = []   # (class, source, name, stock, turbo, qvm)
for t, x in sp_medians(sys.argv[1]).items():
    c = cls.get(('speedtest1', t))
    if c and 'stock' in x: items.append((c, 'speedtest1', t, x['stock'], x.get('turbo'), x.get('qvm')))
for q, x in q_medians(sys.argv[2]).items():
    c = cls.get(('tpch', q))
    if c and 'stock' in x: items.append((c, 'TPC-H', q, x['stock'], x.get('turbo'), x.get('qvm')))
cbq = {}
if len(sys.argv) > 4:
    s = open(sys.argv[4]).read()
    for m in re.finditer(r'-- name: (\S+)\n(.*?)(?=\n-- name: |\Z)', s, re.S): cbq[m.group(1)] = m.group(2)
for q, x in q_medians(sys.argv[3]).items():
    if 'stock' not in x or x['stock'] < 0.5: continue
    items.append((cb_class(cbq.get(q, '')), 'ClickBench', q, x['stock'], x.get('turbo'), x.get('qvm')))

order = ['point', 'short', 'range', 'scan-expr', 'agg', 'join', 'subquery', 'topn', 'sort', 'distinct', 'setop', 'compute', 'write', 'maint']
gm = lambda v: math.exp(sum(math.log(a) for a in v) / len(v)) if v else float('nan')
print('| class | n | turbo / stock (geomean) | qvm / stock (geomean) | turbo range | items (turbo / stock) |')
print('|---|---:|---:|---:|---|---|')
for c in order:
    xs = [i for i in items if i[0] == c and i[4] and i[5]]
    if not xs: continue
    t = [i[4] / i[3] for i in xs]; v = [i[5] / i[3] for i in xs]
    names = ', '.join(f'{i[1]} {i[2]} {i[4] / i[3]:.2f}' for i in sorted(xs, key=lambda i: i[4] / i[3]))
    print(f'| {c} | {len(xs)} | {gm(t):.3f} | {gm(v):.3f} | {min(t):.2f}–{max(t):.2f} | {names} |')
