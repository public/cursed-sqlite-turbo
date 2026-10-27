#!/usr/bin/env python3
"""summarise.py <runs-dir>: tests/sqlancer/run.sh outputs as a Markdown table, one row per arm x oracle x seed:
queries SQLancer ran, the bugs it logged (logs/sqlite3/*.log other than the *-cur.log of the database in progress),
qc's counters (serve arms: statements served / fallbacks; diff arms: compared / differences), then each bug log's
last lines (the failing check) and every QCTDIFF line."""
import sys, os, glob, re
d = sys.argv[1]
print('| arm | oracle | seed | queries | bug logs | qc |')
print('|---|---|---|---:|---:|---|')
details = []
for w in sorted(glob.glob(os.path.join(d, '*-*-*'))):
    arm, oracle, seed = os.path.basename(w).split('-', 2)
    txt = open(os.path.join(w, 'sqlancer.txt'), errors='replace').read() if os.path.exists(os.path.join(w, 'sqlancer.txt')) else ''
    q = re.findall(r'([\d,.]+k?) queries', txt); q = q[-1] if q else '?'
    bugs = [b for b in glob.glob(os.path.join(w, 'logs', 'sqlite3', '*.log')) if not b.endswith('-cur.log')]
    qc = ''
    st = os.path.join(w, 'qcs.stats')
    if os.path.exists(st):
        for line in open(st):
            if line.startswith('QCSSTAT'):
                f = dict(x.split(' ', 1) for x in line.rstrip('\n').split('\t')[1:])
                qc = f'served {f["served"]}, fallbacks {f["fallbacks"]}, refused {f["refused"]}'
    for t in glob.glob(os.path.join(w, 'qct.*.txt')):
        for line in open(t, errors='replace'):
            if line.startswith('QCTSTAT'):
                f = line.split()
                kv = dict(zip(f[1::2], f[2::2]))
                qc = f'compiled {kv.get("compiled")}, fallbacks {kv.get("fallbacks")}, rows compared {kv.get("rows")}, differences {kv.get("differences")}'
            elif line.startswith('QCTDIFF') or line.startswith('QCTINTERR'):
                details.append(f'{arm}/{oracle}/{seed}: {line.strip()[:400]}')
    if 'Exception' in txt and not bugs:
        details.append(f'{arm}/{oracle}/{seed}: exception in sqlancer.txt: ' + next(l for l in txt.splitlines() if 'Exception' in l)[:300])
    for b in bugs:
        lines = [l for l in open(b, errors='replace').read().splitlines() if l.strip()]
        head = next((l for l in lines if l.startswith('--') and ('rror' in l or 'xception' in l or 'ssertion' in l)), lines[0] if lines else '')
        details.append(f'{arm}/{oracle}/{seed}: {os.path.basename(b)}: {head[:300]}')
    print(f'| {arm} | {oracle} | {seed} | {q} | {len(bugs)} | {qc} |')
print()
for x in details: print('- ' + x)
