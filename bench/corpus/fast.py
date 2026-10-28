#!/usr/bin/env python3
"""fast.py <dir> [losers.tsv] [base-dir]: the fast loop's report (run.sh cg locally, the corpusfast Xeon workload): each
arm's instructions per execution against stock's, as the geometric mean by cause (losers.tsv's third column) for hot
and prep, how many are over 1.02, then every statement over 1.02 or, with base-dir (an earlier run, say the last
commit's), every statement whose ratio moved by more than 1 % against it. Means over rounds when there are several."""
import sys, os, glob, math, statistics, collections
d = sys.argv[1]; L = sys.argv[2] if len(sys.argv) > 2 else None; base = sys.argv[3] if len(sys.argv) > 3 else None
cause = {}
if L:
    for l in open(L):
        if l.strip() and not l.startswith('#'): p = l.rstrip('\n').split('\t'); cause[p[0]] = p[2] if len(p) > 2 else '-'
def load(dd):
    r = collections.defaultdict(lambda: collections.defaultdict(list))   # (arm, mode) -> id -> [instr]
    for f in glob.glob(os.path.join(dd, '*.*.*.tsv')):
        arm, mode = os.path.basename(f).split('.')[:2]
        for l in open(f, errors='replace'):
            p = l.rstrip('\n').split('\t')
            if p[0] == 'T' and len(p) >= 12 and p[11] == '-' and float(p[8]) > 0: r[arm, mode][p[1]].append(float(p[8]))
    return {k: {i: statistics.fmean(v) for i, v in x.items()} for k, x in r.items()}
def ratios(R):
    out = {}
    for (arm, mode), x in R.items():
        if arm == 'stock' or ('stock', mode) not in R: continue
        S = R['stock', mode]; out[arm, mode] = {i: x[i] / S[i] for i in x if i in S}
    return out
gm = lambda v: math.exp(sum(map(math.log, v)) / len(v)) if v else float('nan')
X = ratios(load(d)); B = ratios(load(base)) if base else {}
causes = list(dict.fromkeys(cause.values())) or ['-']
for (arm, mode) in sorted(X):
    r = X[arm, mode]; b = B.get((arm, mode), {})
    print(f'\n{arm} / stock, {mode}, instructions ({len(r)} statements)' + (f'; base {os.path.basename(base.rstrip("/"))}' if base else ''))
    print(f'  {"cause":14s} {"n":>3s} {"geomean":>8s} {"over1.02":>8s}' + (f' {"base":>8s}' if b else ''))
    for c in causes + ['all']:
        ids = [i for i in r if c == 'all' or cause.get(i, '-') == c]
        if not ids: continue
        line = f'  {c:14s} {len(ids):3d} {gm([r[i] for i in ids]):8.3f} {sum(r[i] > 1.02 for i in ids):8d}'
        if b: line += f' {gm([b[i] for i in ids if i in b]):8.3f}'
        print(line)
    if b: show = sorted((i for i in r if i in b and abs(r[i] / b[i] - 1) > 0.01), key=lambda i: r[i] / b[i]); hdr = 'moved more than 1 % against base'
    else: show = sorted((i for i in r if r[i] > 1.02), key=lambda i: -r[i]); hdr = 'over 1.02'
    print(f'  {hdr} ({len(show)}):')
    for i in show: print(f'    {i:58s} {cause.get(i, "-"):13s} {r[i]:.3f}' + (f'  (base {b[i]:.3f})' if b else ''))
