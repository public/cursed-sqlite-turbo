#!/usr/bin/env python3
"""parity.py <dir> [arms...]: the parity bar (turbo within 1.02x of stock on small statements) with 95 % intervals.

Reads, from one directory:
  <arm>.<mode>.<round>.tsv   bench/small/run.sh (bench/qrun.c lines: mean ms, user instructions and cycles per execution)
  <arm>.<round>.txt          speedtest1 output (bench/speedtest1/run.sh), per-test seconds
  perf-<arm>.<round>.txt     perf stat -x, output around speedtest1 (instructions:u, cycles:u)
Each round of an arm is one process (one broker run, all on one box). A ratio arm/stock is the ratio of the means over
rounds; its interval is a percentile bootstrap that resamples the rounds of each arm independently (2,000 draws). A
class's ratio is the geometric mean of its statements' ratios, bootstrapped the same way, the rounds drawn once per
draw for all statements, so a run that was slow overall stays slow in every statement. Prints Markdown tables."""
import sys, os, glob, re, math, random, statistics
d = sys.argv[1]; want = sys.argv[2:] or ['turbo', 'qvm']
random.seed(1); B = 2000

def gm(v): return math.exp(sum(math.log(x) for x in v) / len(v))
def ci(samples):
    s = sorted(samples); return s[int(0.025 * len(s))], s[int(0.975 * len(s)) - 1]
def fmt(r, lo, hi):
    flag = '' if hi <= 1.02 else (' ✗' if lo > 1.02 else ' ?')
    return f'{r:.3f} [{lo:.3f}, {hi:.3f}]{flag}'

def table(data, metric_names, title):
    """data[arm][item] = {round: (m1, m2, ...)}: one table per metric, rows = items then classes."""
    arms = [a for a in want if a in data]
    if 'stock' not in data or not arms: return
    items = sorted(set.intersection(*(set(data[a]) for a in arms + ['stock'])))
    rounds = {a: sorted(set(r for i in items for r in data[a][i])) for a in arms + ['stock']}
    classes = sorted(set(i.split(':')[0] for i in items if ':' in i))
    for mi, mname in enumerate(metric_names):
        vals = {a: {i: {r: data[a][i][r][mi] for r in data[a][i]} for i in items} for a in arms + ['stock']}
        if any(v < 0 for a in vals for i in vals[a] for v in vals[a][i].values()): continue   # (no counters)
        def mean_over(a, i, rs): return statistics.fmean(vals[a][i][r] for r in rs if r in vals[a][i])
        print(f'\n#### {title}: {mname}, arm / stock, mean over rounds [95 % interval]\n')
        print('| statement | ' + ' | '.join(arms) + ' |'); print('|---|' + '---:|' * len(arms))
        boot = {a: [] for a in arms}   # per draw: {item: ratio}
        for a in arms:
            for _ in range(B):
                ra = [random.choice(rounds[a]) for _ in rounds[a]]; rs = [random.choice(rounds['stock']) for _ in rounds['stock']]
                boot[a].append({i: mean_over(a, i, ra) / mean_over('stock', i, rs) for i in items})
        for i in items:
            cells = []
            for a in arms:
                r = mean_over(a, i, rounds[a]) / mean_over('stock', i, rounds['stock'])
                lo, hi = ci([b[i] for b in boot[a]]); cells.append(fmt(r, lo, hi))
            print(f'| {i} | ' + ' | '.join(cells) + ' |')
        for c in classes + ['all']:
            its = [i for i in items if c == 'all' or i.split(':')[0] == c]
            cells = []
            for a in arms:
                r = gm([mean_over(a, i, rounds[a]) / mean_over('stock', i, rounds['stock']) for i in its])
                lo, hi = ci([gm([b[i] for i in its]) for b in boot[a]]); cells.append(fmt(r, lo, hi))
            print(f'| **{c}** ({len(its)}) | ' + ' | '.join(cells) + ' |')
    print('\n✗: the whole interval is above 1.02 (fails the bar); ?: the interval straddles 1.02; none: within the bar.')
    print('rounds: ' + ', '.join(f'{a} {len(rounds[a])}' for a in ['stock'] + arms))

# small statements: per mode
for mode, label in (('ac', 'autocommit (drop-in: a transaction per statement)'), ('tx', 'inside one transaction')):
    data = {}
    for f in glob.glob(os.path.join(d, f'*.{mode}.*.tsv')):
        arm, _, rnd = os.path.basename(f)[:-4].split('.')
        for l in open(f):
            p = l.rstrip('\n').split('\t')
            if p[0] == 'Q' and len(p) >= 14:
                data.setdefault(arm, {}).setdefault(p[1], {})[int(rnd)] = (float(p[11]), float(p[12]), float(p[13]))
    if data: table(data, ['time', 'user instructions', 'user cycles'], f'Small statements, {label}')

# speedtest1: per test (time) and the whole run (perf stat)
data = {}
for f in glob.glob(os.path.join(d, '*.txt')):
    m = re.match(r'(\w+)\.(\d+)\.txt$', os.path.basename(f))
    if not m: continue
    arm, rnd = m.group(1), int(m.group(2))
    for l in open(f, errors='replace'):
        t = re.match(r'\s*(\d+) - (.*?)\.*\s+(\d+\.\d+)s\s*$', l)
        if t: data.setdefault(arm, {}).setdefault(f'{t.group(1)} {t.group(2)[:40]}', {})[rnd] = (float(t.group(3)),)
        t = re.match(r'\s*TOTAL\.*\s+(\d+\.\d+)s', l)
        if t: data.setdefault(arm, {}).setdefault('TOTAL', {})[rnd] = (float(t.group(1)),)
for f in glob.glob(os.path.join(d, 'perf-*.txt')):
    m = re.match(r'perf-(\w+)\.(\d+)\.txt$', os.path.basename(f))
    if not m: continue
    v = {}
    for l in open(f):
        p = l.strip().split(',')
        if len(p) > 2 and p[0].replace('.', '').isdigit():
            v[p[2].split(':')[0]] = float(p[0])
    if 'instructions' in v and 'cycles' in v:
        data.setdefault(m.group(1), {})
        data[m.group(1)].setdefault('perf: whole run, instructions', {})[int(m.group(2))] = (v['instructions'],)
        data[m.group(1)].setdefault('perf: whole run, cycles', {})[int(m.group(2))] = (v['cycles'],)
if data: table(data, ['value'], 'speedtest1 (per test: seconds; perf: user-mode counts)')
