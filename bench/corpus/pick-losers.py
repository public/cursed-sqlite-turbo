#!/usr/bin/env python3
"""pick-losers.py <series-dir> [older-series-dir] > bench/corpus/losers.tsv: the loser micro-corpus for the fast loop
(run.sh cg locally, the corpusfast Xeon workload), from Xeon corpus series (corpus/run.sh speed's TSVs and q/, as
gathered for summarise.py). A loser is consistently over 1.02x stock in hot or prep: its time's bootstrap interval is
above 1.02 in the newer series and its instructions over 1.02 in both. Each is given one cause:
  unserved      never served, so it pays serving's checks for nothing (writes, vtabs, FTS)
  small         served, hot loser, stock under 100k instructions: serving's fixed cost on a small lookup
  sort          served, hot loser, larger, with ORDER BY / a temp B-tree / GROUP BY / top-N
  big           served, hot loser, larger, otherwise
  prep-reoffer  a prep-only loser in the newer series that the older did not serve (a binding's re-prepare, c85cc3b;
                the newer series alone decides, as the older one never served it)
  prep          any other prep-only loser (prepare + finalize cost)
and two kinds of guard, which must not get worse:
  win           clear wins, hot (instructions under 0.9 in both series)
  parity        served hot-small statements that are not losers (at most 1.05 instructions), closest to 1 first
Named statements (NAMED) are kept whatever their rank. Within a cause the largest instruction excess comes first, at
most 2 per application, statements over MAXMS stock ms (hot) left out so a callgrind pass stays in minutes.
Output, from the newer series: id, project, cause, then instructions per execution (stock hot, serve hot, stock prep,
serve prep) and stock's hot ms: the baseline. The statements themselves, in corpus order with their projects'
databases: IDS=bench/corpus/losers.tsv python3 bench/corpus/prep.py <dir> (<project>.q and <project>.build.sql, which
corpus.c runs as they are)."""
import sys, glob, os, math, statistics, random, collections
NEW = sys.argv[1]; OLD = sys.argv[2] if len(sys.argv) > 2 else None
MAXMS = 15.0
QUOTA = dict(unserved=12, small=18, sort=14, big=10, **{'prep-reoffer': 12}, prep=8, win=14, parity=10)
NAMED = {'vaultwarden.users.find_by_uuid': 'prep-reoffer', 'vaultwarden.ciphers.find_by_uuid': 'prep-reoffer',
         'vaultwarden.groups.orgs_with_full_access': 'big', 'vaultwarden.devices.find_by_refresh_token': 'small',
         'navidrome.user.find_by_username': 'prep'}   # (zotero items.primary_data, the re-offer's 0.65x, is 385 ms: collections.primary_data stands in)
random.seed(1)
tags, app = {}, {}
for f in glob.glob(os.path.join(NEW, 'q', '*.q')):
    for l in open(f):
        if l.startswith('@@Q '): p = l.split(); tags[p[1]] = p[4].split(','); app[p[1]] = os.path.basename(f)[:-2]
def load(d, arm, mode):
    r = {}
    for f in glob.glob(os.path.join(d, f'{arm}.{mode}.*.tsv')):
        for l in open(f, errors='replace'):
            p = l.rstrip('\n').split('\t')
            if p[0] == 'T' and len(p) >= 12 and p[11] == '-':
                sv, n = p[10].split('/'); r.setdefault(p[1], []).append((float(p[6]), float(p[8]), int(sv), int(n)))
    return r
def stats(d, mode):
    S, A = load(d, 'stock', mode), load(d, 'serve', mode); o = {}
    for i in S:
        if i not in A or min(x[0] for x in S[i]) <= 0: continue
        ts, ta = [x[0] for x in S[i]], [x[0] for x in A[i]]
        bs = sorted(statistics.fmean(random.choice(ta) for _ in ta) / statistics.fmean(random.choice(ts) for _ in ts) for _ in range(400))
        o[i] = dict(i=statistics.fmean(x[1] for x in A[i]) / statistics.fmean(x[1] for x in S[i]), si=statistics.fmean(x[1] for x in S[i]),
                    ai=statistics.fmean(x[1] for x in A[i]),
                    ms=statistics.fmean(ts), lo=bs[10], sv=sum(x[2] for x in A[i]) / max(1, sum(x[3] for x in A[i])) > 0.5)
    return o
N = {m: stats(NEW, m) for m in ('hot', 'prep')}
O = {m: stats(OLD, m) for m in ('hot', 'prep')} if OLD else N
def loser(i, m): return i in N[m] and i in O[m] and N[m][i]['lo'] > 1.02 and N[m][i]['i'] > 1.02 and O[m][i]['i'] > 1.02
ids = [i for i in N['hot'] if i in N['prep']]
cause = {}
for i in ids:
    h, p = N['hot'][i], N['prep'][i]
    if loser(i, 'hot'):
        if not h['sv']: cause[i] = 'unserved'
        elif h['si'] < 100e3: cause[i] = 'small'
        elif set(tags[i]) & {'orderby', 'temp-btree', 'groupby', 'topn'}: cause[i] = 'sort'
        else: cause[i] = 'big'
    elif p['sv'] and i in O['prep'] and not O['prep'][i]['sv'] and p['lo'] > 1.02 and p['i'] > 1.02: cause[i] = 'prep-reoffer'
    elif loser(i, 'prep'): cause[i] = 'unserved' if not p['sv'] else 'prep'
    elif h['sv'] and h['i'] < 0.9 and O['hot'].get(i, h)['i'] < 0.9: cause[i] = 'win'
    elif h['sv'] and 'hot-small' in tags[i] and h['i'] <= 1.05: cause[i] = 'parity'
def excess(i):   # (losers: the worse mode's excess; wins: the size of the win; parity: closest to 1 first)
  r = N['hot'][i]['i'] if cause[i] in ('win', 'parity') else max(N['hot'][i]['i'], N['prep'][i]['i'])
  return abs(math.log(r))
out = dict((i, c) for i, c in NAMED.items() if i in N['hot'])
for c, q in QUOTA.items():
    per = collections.Counter(app[i] for i in out if out[i] == c); k = sum(1 for i in out if out[i] == c)
    for i in sorted((i for i in ids if cause.get(i) == c and i not in out), key=excess, reverse=(c != 'parity')):
        if k >= q: break
        if N['hot'][i]['ms'] > MAXMS or per[app[i]] >= 2: continue
        out[i] = c; per[app[i]] += 1; k += 1
print('# id\tproject\tcause\tstock hot\tserve hot\tstock prep\tserve prep\tstock hot ms   (instructions per execution; '
      'bench/corpus/pick-losers.py ' + ' '.join(os.path.basename(a.rstrip('/')) for a in sys.argv[1:]) + ')')
for c in QUOTA:
    for i in sorted(i for i in out if out[i] == c):
        h, p = N['hot'][i], N['prep'][i]
        print(f"{i}\t{app[i]}\t{c}\t{h['si']:.0f}\t{h['ai']:.0f}\t{p['si']:.0f}\t{p['ai']:.0f}\t{h['ms']:.3f}")
cc = collections.Counter(cause.values())
print(f'pick-losers: {len(out)} statements; candidates by cause: ' + ', '.join(f'{c} {cc[c]}' for c in QUOTA), file=sys.stderr)
