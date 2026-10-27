#!/usr/bin/env python3
"""diag.py <dir> [arm]: bench/speedtest1/diag.sh outputs for stock and one turbo arm (default turbo), per test:
  - time, user instructions and user cycles, arm / stock, at --size 100 and --size 1000 (means over rounds; 95 %
    bootstrap intervals for time);
  - fixed cost or per-execution: if the ratio's excess at size 1000 is under half its excess at size 100, the loss is
    mostly a fixed cost (prepare, lift, first run); otherwise it scales with the work (per execution);
  - where the extra time goes at size 100: prepare, first run (qc lifts there), the loop, one-shot exec;
  - which tier ran the test's statements (QCS_STATS: P specialised, L loop plan, V qvm, S SQLite) and why not;
  - with profiles (prof.<arm>.<round>/<test>.txt), the top symbols of stock and the arm.
Then the tests ranked by the time turbo loses at size 100, each with a suggested remedy and what fixing it would change
in speedtest1's total."""
import sys, os, glob, re, statistics, random
d = sys.argv[1]; ARM = sys.argv[2] if len(sys.argv) > 2 else 'turbo'
random.seed(1)

def load(arm, size):
    """test -> round -> dict; plus test names, SQL per test"""
    r, names = {}, {}
    for f in glob.glob(os.path.join(d, f'{arm}.s{size}.*.st1i')):
        rnd = int(f.rsplit('.', 2)[-2])
        for l in open(f, errors='replace'):
            p = l.split()
            if p and p[0] == 'ST1I':
                r.setdefault(p[1], {})[rnd] = dict(ins=float(p[2]), cyc=float(p[3]), prep=float(p[4]), first=float(p[5]),
                                                   loop=float(p[6]), exec=float(p[7]), nr=int(p[9]), t=(float(p[12]) - float(p[11])))
        t = f[:-5] + '.txt'
        if os.path.exists(t):
            for l in open(t, errors='replace'):
                m = re.match(r'\s*(\d+) - (.*?)\.*\s+\d+\.\d+s\s*$', l)
                if m: names[m.group(1)] = m.group(2).strip()
    return r, names
def sqls(arm, size):
    s = {}
    for f in glob.glob(os.path.join(d, f'{arm}.s{size}.*.st1i'))[:1]:
        for l in open(f, errors='replace'):
            p = l.rstrip('\n').split(' ', 3)
            if p[0] == 'ST1SQL' and len(p) == 4: s.setdefault(p[1], []).append((p[2], p[3]))
    return s
def tiers(arm, size):
    t = {}
    for f in glob.glob(os.path.join(d, f'{arm}.s{size}.*.stats'))[:1]:
        for l in open(f, errors='replace'):
            p = l.rstrip('\n').split('\t')
            if p[0] == 'QCSTEXT' and len(p) >= 9: t[norm(p[8])] = (int(p[2]), int(p[3]), int(p[4]), int(p[5]), p[7])
    return t
def norm(q):   # (the statement up to its ';': the prepared text can carry a trailing comment, v->zSql doesn't)
    return q.split(';')[0].strip()
def mean(rs, k): return statistics.fmean(x[k] for x in rs.values())
def ratio_ci(a, s, k):
    ra, rs = list(a.values()), list(s.values()); b = []
    for _ in range(2000):
        xa = [random.choice(ra)[k] for _ in ra]; xs = [random.choice(rs)[k] for _ in rs]
        b.append(statistics.fmean(xa) / statistics.fmean(xs))
    b.sort(); return b[50], b[1949]

S100, names = load('stock', 100); A100, _ = load(ARM, 100); S1k, _ = load('stock', 1000); A1k, _ = load(ARM, 1000)
sq = sqls(ARM, 100); ti = tiers(ARM, 100)
TIER = {0: 'S', 1: 'P', 2: 'L', 3: 'V'}
tests = sorted(set(S100) & set(A100), key=int)
total_stock = sum(mean(S100[t], 't') for t in tests if int(t) > 0)
rows = []
for t in tests:
    if int(t) == 0: continue
    s, a = S100[t], A100[t]
    rt = mean(a, 't') / mean(s, 't'); lo, hi = ratio_ci(a, s, 't')
    ri = mean(a, 'ins') / mean(s, 'ins') if mean(s, 'ins') > 0 else float('nan')
    rc = mean(a, 'cyc') / mean(s, 'cyc') if mean(s, 'cyc') > 0 else float('nan')
    rt1k = mean(A1k[t], 't') / mean(S1k[t], 't') if t in A1k and t in S1k else float('nan')
    kind = '–'
    if rt > 1.0 and rt1k == rt1k:
        kind = 'fixed cost' if (rt1k - 1) < 0.5 * (rt - 1) else 'per execution'
    delta = mean(a, 't') - mean(s, 't')
    split = {k: (mean(a, k) - mean(s, k)) / 1e9 for k in ('prep', 'first', 'loop', 'exec')}
    st = []
    for kindsql, q in sq.get(t, []):
        x = ti.get(norm(q))
        if x:   # (kind, served, fallbacks, refused, why)
            st.append((TIER.get(x[0], '?') if x[1] else f'S({x[4]})') + (f' {x[2]}fb({x[4]})' if x[2] else ''))
    tierstr = ', '.join(sorted(set(st))) or 'no qc statements'
    rows.append(dict(t=t, name=names.get(t, ''), s=mean(s, 't'), rt=rt, lo=lo, hi=hi, ri=ri, rc=rc, rt1k=rt1k, kind=kind,
                     delta=delta, split=split, tiers=tierstr, nr=mean(s, 'nr')))

print(f'| test | stock s | {ARM}/stock time [95 %] | instr | cycles | time at size 1000 | loss is | extra s: prep / first / loop / exec | tiers |')
print('|---|---:|---:|---:|---:|---:|---|---|---|')
for r in rows:
    sp = ' / '.join(f'{r["split"][k]:+.3f}' for k in ('prep', 'first', 'loop', 'exec'))
    print(f'| {r["t"]} {r["name"][:38]} | {r["s"]:.3f} | {r["rt"]:.3f} [{r["lo"]:.3f}, {r["hi"]:.3f}] | {r["ri"]:.3f} | {r["rc"]:.3f} | {r["rt1k"]:.3f} | {r["kind"]} | {sp} | {r["tiers"][:80]} |')
tot_a = sum(r['s'] + r['delta'] for r in rows)
print(f'\ntotal: stock {total_stock:.3f} s, {ARM} {tot_a:.3f} s ({tot_a / total_stock:.3f}); losing tests cost {sum(r["delta"] for r in rows if r["delta"] > 0):+.3f} s, winning tests save {sum(r["delta"] for r in rows if r["delta"] < 0):+.3f} s')
print('\nranked losses (size 100): test, seconds lost, share of stock total, where, tiers')
for r in sorted((r for r in rows if r['delta'] > 0 and r['lo'] > 1.0), key=lambda r: -r['delta']):
    where = max(r['split'], key=lambda k: r['split'][k])
    print(f'- {r["t"]} {r["name"][:40]}: {r["delta"]:+.3f} s ({100 * r["delta"] / total_stock:.1f} % of the total), mostly {where}, {r["kind"]}; {r["tiers"][:100]}')
print('\nwins (size 100):')
for r in sorted((r for r in rows if r['hi'] < 1.0), key=lambda r: r['delta']):
    print(f'- {r["t"]} {r["name"][:40]}: {r["delta"]:+.3f} s ({r["rt"]:.2f}x); {r["tiers"][:80]}')
profs = sorted(glob.glob(os.path.join(d, f'prof.{ARM}.*')))
if profs:
    print('\nprofiles: see prof.stock.*/<test>.txt and prof.' + ARM + '.*/<test>.txt (top symbols over each test\'s interval)')
