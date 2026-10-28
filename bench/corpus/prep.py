#!/usr/bin/env python3
"""prep.py <out-dir> [scale] [projects...]: bench/corpus/corpus (a copy of cursed-http's sqlite-query-corpus) as flat
files for bench/corpus/corpus.c, one pair per project:
  <p>.build.sql   the database: journal_mode OFF, temp _cfg(scale), schema.sql, data.sql, ANALYZE (tools/run.py's build)
  <p>.q           the queries, each a header line, its parameters, then its SQL:
                    @@Q <id> <ordered> <write> <tags,...>
                    @@P <name> <SQL literal>
                    <SQL lines>
ordered = 1 when the statement has ORDER BY (its rows are compared in order, else as a multiset); write = 1 when it is
not a read (it then runs inside BEGIN ... ROLLBACK, as tools/run.py runs every statement). Tags are the manifest's.
IDS=<file>: only the statements whose ids are its lines' first fields (# comments; e.g. bench/corpus/losers.tsv), and
only the projects that have one."""
import sys, os, json
from pathlib import Path
H = Path(__file__).resolve().parent / 'corpus'
out = Path(sys.argv[1]); scale = sys.argv[2] if len(sys.argv) > 2 else '1'; want = set(sys.argv[3:])
out.mkdir(parents=True, exist_ok=True)
ids = {l.split('\t')[0].split()[0] for l in open(os.environ['IDS']) if l.strip() and not l.startswith('#')} if os.environ.get('IDS') else None

def parse_queries(path):   # (tools/run.py's parser: blocks start with -- @id)
    import re
    res, cur = [], None
    for line in path.read_text().splitlines():
        m = re.match(r"\s*--\s*@(\w+)\s?(.*)$", line)
        if m:
            k, v = m.group(1), m.group(2).strip()
            if k == 'id': cur = {'id': v, 'sql': [], 'params': []}; res.append(cur)
            elif cur is not None and k == 'param':
                n, _, lit = v.partition(' '); cur['params'].append((n, lit.strip()))
            continue
        if cur is not None:
            if re.match(r"\s*--", line) and not cur['sql']: continue
            cur['sql'].append(line)
    for q in res:
        q['sql'] = '\n'.join(q['sql']).strip()
        if not q['sql'].endswith(';'): q['sql'] += ';'
    return res

def put(path, text):   # (unchanged files keep their time: run.sh rebuilds a database only when its build.sql is newer)
    if not path.exists() or path.read_text() != text: path.write_text(text)

man = {}
for l in open(H / 'manifest.jsonl'):
    r = json.loads(l); man[r['id']] = r
n = 0
for pdir in sorted((H / 'projects').iterdir()):
    p = pdir.name
    if want and p not in want: continue
    qs = [q for q in parse_queries(pdir / 'queries.sql') if ids is None or q['id'] in ids]
    if not qs: continue
    put(out / f'{p}.build.sql', f"PRAGMA journal_mode=OFF;\nCREATE TEMP TABLE _cfg AS SELECT {scale} AS scale;\n"
                                        + (pdir / 'schema.sql').read_text() + '\n' + (pdir / 'data.sql').read_text()
                                        + '\nANALYZE;\n')
    f = []
    for q in qs:
        tags = man.get(q['id'], {}).get('tags', [])
        ordered = int('orderby' in tags or 'topn' in tags)
        write = int('read' not in tags)
        f.append(f"@@Q {q['id']} {ordered} {write} {','.join(tags) or '-'}\n")
        for nm, lit in q['params']: f.append(f'@@P {nm} {lit}\n')
        f.append(q['sql'] + '\n'); n += 1
    put(out / f'{p}.q', ''.join(f))
if ids is not None and n < len(ids): print(f'prep: {len(ids) - n} of IDS not in the corpus', file=sys.stderr)
print(f'prep: {n} queries in {out}', file=sys.stderr)
