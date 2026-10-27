#!/usr/bin/env python3
"""compare.py <dir>: bench/qrun.c outputs (<arm>.<round>.tsv) as a Markdown table. Per query: rows, the median over
rounds of each arm's median ms (warm: plans built, feedback in), turbo and qvm relative to stock, which executor ran it
(P specialised plan, L loop plan, V qvm, S SQLite with qc's reason) and whether every arm and round produced the same
rows (hash). Then the geometric means, the first (cold, lift included) executions' totals, and qc's counters.
Exit status 1 if any result differs or any query failed."""
import sys, os, glob, statistics, math
d = sys.argv[1]
res, order, errs = {}, [], []
for f in sorted(glob.glob(os.path.join(d, '*.tsv'))):
    arm, rnd = os.path.basename(f)[:-4].rsplit('.', 1)
    for line in open(f, errors='replace'):
        p = line.rstrip('\n').split('\t')
        if p[0] == 'ERR': errs.append(f'{arm}.{rnd} {p[1]}: {" ".join(p[2:])}'); continue
        if p[0] != 'Q': continue
        name = p[1]
        if name not in order: order.append(name)
        res.setdefault(name, {}).setdefault(arm, []).append(dict(rows=int(p[2]), hash=p[3], first=float(p[4]), med=float(p[5]),
                                                                 min=float(p[6]), runs=int(p[7]), tier=int(p[8]), why=p[9], fb=int(p[10]) if len(p) > 10 else 0))
arms = [a for a in ('stock', 'turbo', 'qvm', 'off', 'main', 'notxn', 'direct') if any(a in r for r in res.values())]
TIER = {0: 'S', 1: 'P', 2: 'L', 3: 'V'}
bad = 0
xs = [a for a in arms if a != 'stock']
print('| query | rows | ' + ' | '.join(f'{a} ms' for a in arms) + ''.join(f' | {a}/stock' for a in xs) + ''.join(f' | {a}' for a in xs) + ' | same rows |')
print('|---|---:|' + '---:|' * len(arms) + '---:|' * len(xs) + '---|' * len(xs) + '---|')
logs = {a: [] for a in arms}; first = {a: 0.0 for a in arms}
for q in order:
    r = res[q]
    hashes = {(x['rows'], x['hash']) for a in r for x in r[a]}
    same = 'yes' if len(hashes) == 1 and all(a in r for a in arms) else '**NO**'
    if same != 'yes': bad = 1
    med = {a: statistics.median(x['med'] for x in r[a]) for a in arms if a in r}
    for a in med:
        first[a] += statistics.median(x['first'] for x in r[a])
        if med.get('stock', 0) > 0: logs[a].append(math.log(med[a] / med['stock']))
    def rel(a): return f'{med[a] / med["stock"]:.3f}' if a in med and med.get('stock', 0) > 0 else '–'
    def tier(a):
        if a not in r: return '–'
        x = r[a][-1]; t = x['tier']; fb = sum(y['fb'] for y in r[a]); n = sum(y['runs'] for y in r[a])
        return TIER[t] + ('' if t else f' ({x["why"]})') + (f' {fb}/{n} by SQLite' if t and fb else '')
    rows = next(iter(hashes))[0] if hashes else 0
    print(f'| {q} | {rows} | ' + ' | '.join(f'{med[a]:.2f}' if a in med else '–' for a in arms) + ''.join(f' | {rel(a)}' for a in xs) + ''.join(f' | {tier(a)}' for a in xs) + f' | {same} |')
gm = {a: math.exp(sum(logs[a]) / len(logs[a])) for a in arms if logs[a]}
print(f'| **geomean vs stock** | | ' + ' | '.join('' for a in arms) + ''.join(f' | {gm.get(a, float("nan")):.3f}' for a in xs) + ' |' * len(xs) + ' |')
print()
print('first executions (cold, lift included), sum of medians: ' + ', '.join(f'{a} {first[a]:.1f} ms' for a in arms))
for a in arms:
    st = sorted(glob.glob(os.path.join(d, f'{a}.*.stats')))
    for line in (open(st[0]) if st else []):
        if line.startswith('QCSSTAT'): print(f'{a}: ' + line.split('\t', 1)[1].strip().replace('\t', ', '))
# an error every arm reports the same way (ClickBench's Q28 uses REGEXP_REPLACE, which SQLite lacks) is the query's
# result, not a difference
eq = {}
for e in errs:
    who, rest = e.split(' ', 1); eq.setdefault(rest, set()).add(who.split('.')[0])
for rest, who in eq.items():
    if who >= set(arms): print(f'same error in every arm: {rest}')
    else: print(f'ERROR in {", ".join(sorted(who))} only: {rest}'); bad = 1
sys.exit(bad)
