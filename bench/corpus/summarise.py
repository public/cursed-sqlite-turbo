#!/usr/bin/env python3
"""summarise.py <dir> [arm]: corpus/run.sh speed's <arm>.<hot|prep>.<round>.tsv against stock's, per statement, per
tag and per application, for time (mean ms per execution), user instructions and user cycles. A statement's ratio is
arm / stock of the means over rounds; its 95 % interval is a percentile bootstrap over rounds (each arm's rounds
resampled independently, 1,000 draws). A group's ratio is the geometric mean of its statements', bootstrapped with the
rounds drawn once per draw for every statement. Statements whose rows differ from stock's, that error, or that stock
times at 0 are left out (listed). Prints Markdown: the summary by mode, by tag and by application, every statement over
1.02x stock time (point estimate; ✗ when the whole interval is above 1.02), and the 25 largest wins."""
import sys, os, glob, math, random, statistics, collections
d = sys.argv[1]; ARM = sys.argv[2] if len(sys.argv) > 2 else 'serve'
random.seed(1); B = 1000
tags, app, wall = {}, {}, set()
for f in glob.glob(os.path.join(d, 'q', '*.q')):
    for l in open(f):
        if l.startswith('@@Q '):
            p = l.split(); tags[p[1]] = p[4].split(','); app[p[1]] = os.path.basename(f)[:-2]
            if 'wallclock' in tags[p[1]]: wall.add(p[1])
def gm(v): return math.exp(sum(math.log(x) for x in v) / len(v))
def ci(s): s = sorted(s); return s[int(0.025 * len(s))], s[int(0.975 * len(s)) - 1]
def load(arm, mode):
    r = {}   # id -> round -> (ms, instr, cycles, rows, hash, served, runs, err)
    for f in glob.glob(os.path.join(d, f'{arm}.{mode}.*.tsv')):
        rnd = int(f.rsplit('.', 2)[-2])
        for l in open(f, errors='replace'):
            p = l.rstrip('\n').split('\t')
            if p[0] != 'T' or len(p) < 12: continue
            sv, n = p[10].split('/')
            r.setdefault(p[1], {})[rnd] = (float(p[6]), float(p[8]), float(p[9]), p[2], p[3], int(sv), int(n), p[11])
    return r
for mode, label in (('hot', 'hot: prepared once, executed repeatedly'), ('prep', 'prepare + step + finalize each time')):
    S, A = load('stock', mode), load(ARM, mode)
    if not S or not A: continue
    left, items = [], []
    for i in S:
        if i not in A: left.append((i, 'missing')); continue
        s0 = next(iter(S[i].values())); a0 = next(iter(A[i].values()))
        if s0[7] != '-' or a0[7] != '-': left.append((i, f'error: {(s0[7] if s0[7] != "-" else a0[7])[:80]}')); continue
        if (s0[3], s0[4]) != (a0[3], a0[4]) and i not in wall: left.append((i, 'rows differ')); continue
        if min(v[0] for v in S[i].values()) <= 0 or min(v[0] for v in A[i].values()) <= 0: left.append((i, 'timed at 0')); continue
        items.append(i)
    rs, ra = sorted(set(r for i in items for r in S[i])), sorted(set(r for i in items for r in A[i]))
    print(f'\n### {label} ({ARM} / stock; rounds: stock {len(rs)}, {ARM} {len(ra)}; {len(items)} statements)\n')
    def m(X, i, rr, k): return statistics.fmean(X[i][r][k] for r in rr if r in X[i])
    ratio, boot = {}, {}
    for k, kn in ((0, 'time'), (1, 'instructions'), (2, 'cycles')):
        if k and any(v[k] < 0 for i in items for v in S[i].values()): continue
        ratio[kn] = {i: m(A, i, ra, k) / m(S, i, rs, k) for i in items}
        bs = []
        for _ in range(B):
            dr = [random.choice(ra) for _ in ra]; ds = [random.choice(rs) for _ in rs]
            bs.append({i: m(A, i, dr, k) / m(S, i, ds, k) for i in items})
        boot[kn] = bs
    def cell(kn, its):
        r = gm([ratio[kn][i] for i in its]); lo, hi = ci([gm([b[i] for i in its]) for b in boot[kn]])
        return f'{r:.3f} [{lo:.3f}, {hi:.3f}]'
    kns = list(ratio)
    served = {i: sum(v[5] for v in A[i].values()) / max(1, sum(v[6] for v in A[i].values())) for i in items}
    def row(name, its):
        sv = sum(1 for i in its if served[i] > 0.5)
        print(f'| {name} | {len(its)} | {sv} | ' + ' | '.join(cell(kn, its) for kn in kns) + f' | {sum(1 for i in its if ratio["time"][i] > 1.02)} |')
    hdr = '| group | statements | served | ' + ' | '.join(kns) + ' | over 1.02 (time) |'
    print(hdr); print('|---|---:|---:|' + '---:|' * len(kns) + '---:|')
    row('**all**', items)
    row('served (most executions)', [i for i in items if served[i] > 0.5])
    row('not served', [i for i in items if served[i] <= 0.5])
    print('\nBy tag:\n'); print(hdr); print('|---|---:|---:|' + '---:|' * len(kns) + '---:|')
    tc = collections.Counter(t for i in items for t in tags[i])
    for t, n in tc.most_common():
        if n >= 5: row(t, [i for i in items if t in tags[i]])
    print('\nBy application:\n'); print(hdr); print('|---|---:|---:|' + '---:|' * len(kns) + '---:|')
    for a in sorted(set(app[i] for i in items)): row(a, [i for i in items if app[i] == a])
    def one(i):
        out = []
        for kn in kns:
            lo, hi = ci([b[i] for b in boot[kn]]); r = ratio[kn][i]
            out.append(f'{r:.3f} [{lo:.3f}, {hi:.3f}]' + (' ✗' if kn == 'time' and lo > 1.02 else ''))
        return out
    worse = sorted((i for i in items if ratio['time'][i] > 1.02), key=lambda i: -ratio['time'][i])
    print(f'\nOver 1.02x stock time ({len(worse)}; ✗: the whole interval above 1.02):\n')
    print('| statement | stock ms | served | ' + ' | '.join(kns) + ' | tags |'); print('|---|---:|---:|' + '---:|' * len(kns) + '---|')
    for i in worse:
        print(f'| {i} | {m(S, i, rs, 0):.4f} | {served[i]:.0%} | ' + ' | '.join(one(i)) + f' | {",".join(t for t in tags[i] if t not in ("read", "dynamic", "modified"))} |')
    wins = sorted(items, key=lambda i: ratio['time'][i])[:25]
    print('\nThe 25 largest wins:\n')
    print('| statement | stock ms | served | ' + ' | '.join(kns) + ' | tags |'); print('|---|---:|---:|' + '---:|' * len(kns) + '---|')
    for i in wins:
        print(f'| {i} | {m(S, i, rs, 0):.4f} | {served[i]:.0%} | ' + ' | '.join(one(i)) + f' | {",".join(t for t in tags[i] if t not in ("read", "dynamic", "modified"))} |')
    if left: print(f'\nLeft out ({len(left)}): ' + '; '.join(f'{i} ({w})' for i, w in left))
