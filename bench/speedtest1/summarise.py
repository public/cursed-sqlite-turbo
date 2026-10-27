#!/usr/bin/env python3
"""summarise.py <dir>: speedtest1 runs (<arm>.<round>.txt, .stats) as a Markdown table: median seconds per test and
arm, turbo and qvm relative to stock, the verification hashes (must be one value), and qc's counters per arm."""
import re, sys, os, glob, statistics
d = sys.argv[1]
runs, hashes, order, names = {}, {}, [], {}
for f in sorted(glob.glob(os.path.join(d, '*.txt'))):
    arm, rnd = os.path.basename(f)[:-4].rsplit('.', 1)
    for line in open(f, errors='replace'):
        m = re.match(r'\s*(\d+) - (.*?)\.*\s+(\d+\.\d+)s\s*$', line)
        if m:
            t = int(m.group(1)); names[t] = m.group(2).strip()
            if t not in order: order.append(t)
            runs.setdefault(arm, {}).setdefault(t, []).append(float(m.group(3)))
        m = re.match(r'\s*TOTAL\.*\s+(\d+\.\d+)s', line)
        if m: runs.setdefault(arm, {}).setdefault('TOTAL', []).append(float(m.group(1)))
        m = re.match(r'Verification Hash: (.*)', line)
        if m: hashes.setdefault(m.group(1).strip(), []).append(f'{arm}.{rnd}')
arms = [a for a in ('stock', 'turbo', 'qvm') if a in runs]
med = lambda a, t: statistics.median(runs[a][t]) if a in runs and t in runs[a] else float('nan')
print('| test | ' + ' | '.join(arms) + ' | turbo/stock | qvm/stock |')
print('|---|' + '---:|' * (len(arms) + 2))
for t in order + ['TOTAL']:
    s = med('stock', t)
    rel = lambda a: f'{med(a, t) / s:.3f}' if a in runs and s > 0 else '–'   # (nan > 0 is False)
    label = f'{t} {names[t]}' if t != 'TOTAL' else '**total**'
    print(f'| {label} | ' + ' | '.join(f'{med(a, t):.3f}' for a in arms) + f' | {rel("turbo")} | {rel("qvm")} |')
print()
print(f'verification hashes: {len(hashes)} distinct' + ('' if len(hashes) == 1 else ' (MISMATCH)'))
for h, w in hashes.items(): print(f'  {h}: {", ".join(w)}')
for a in arms:
    st = sorted(glob.glob(os.path.join(d, f'{a}.*.stats')))
    if st:
        for line in open(st[0]):
            if line.startswith('QCSSTAT'): print(f'{a}: ' + line.split('\t', 1)[1].strip().replace('\t', ', '))
