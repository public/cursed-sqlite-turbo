#!/usr/bin/env python3
"""build.py <out.html> [results-dir [label]]: the query corpus explorer, one self-contained page. Reads bench/corpus's
manifest.jsonl and projects/*/{meta.json,schema.sql,data.sql} and fills explorer/page.html's /*DATA*/ with them. With a
corpus/run.sh speed directory (stock and serve <mode>.<round>.tsv, e.g. a corpus series merged), each statement also
gets turbo's serve/stock ratios (instructions, time; means over rounds) and how many executions qc served."""
import sys, os, re, ast, json, glob, collections
from pathlib import Path
H = Path(__file__).resolve().parent.parent
WAVE1 = ast.literal_eval(re.search(r'WAVE1 = (\{.*?\})', (H / 'prep.py').read_text(), re.S).group(1))   # (prep.py's 27 wave-1 projects)
out = Path(sys.argv[1]); res = sys.argv[2] if len(sys.argv) > 2 else None
label = sys.argv[3] if len(sys.argv) > 3 else (os.path.basename(os.path.normpath(res)) if res else '')

projects = {}
for pdir in sorted((H / 'projects').iterdir()):
    m = json.loads((pdir / 'meta.json').read_text())
    projects[pdir.name] = dict(
        name=m.get('name', pdir.name), category=m.get('category', ''), repo=m.get('repo', ''), sha=m.get('sha', ''),
        license=m.get('license', ''), stars=m.get('stars'), interest=m.get('interest_note', ''),
        visibility=m.get('visibility_note', ''), reach=m.get('reach_note', ''), scale=m.get('data_scale', ''),
        schema_source=m.get('schema_source', ''), param_style=m.get('param_style', ''),
        evidence=m.get('cpu_evidence', []), analyze=m.get('analyze', True), analyze_note=m.get('analyze_note', ''),
        pragmas=m.get('pragmas', []), wave=1 if pdir.name in WAVE1 else 2,
        schema=(pdir / 'schema.sql').read_text(), data=(pdir / 'data.sql').read_text())

turbo = {}
if res:
    def load(arm, mode):
        acc = collections.defaultdict(list)
        for f in glob.glob(os.path.join(res, f'{arm}.{mode}.*.tsv')):
            for l in open(f, errors='replace'):
                p = l.rstrip('\n').split('\t')
                if p[0] == 'T' and len(p) >= 12:
                    sv, n = p[10].split('/'); acc[p[1]].append((float(p[6]), float(p[8]), int(sv), int(n), p[3]))
        return acc
    for mode in ('hot', 'prep'):
        s, v = load('stock', mode), load('serve', mode)
        for k in s:
            if k not in v: continue
            a, b = s[k], v[k]
            ms, mi = sum(x[0] for x in a) / len(a), sum(x[1] for x in a) / len(a)
            if ms <= 0 or mi <= 0 or a[0][4] != b[0][4]: continue
            turbo.setdefault(k, {})[mode] = dict(
                i=round(sum(x[1] for x in b) / len(b) / mi, 3), t=round(sum(x[0] for x in b) / len(b) / ms, 3),
                sv=sum(x[2] for x in b), n=sum(x[3] for x in b), ms=round(ms, 4))

qs = []
for l in open(H / 'manifest.jsonl'):
    r = json.loads(l)
    q = dict(id=r['id'], p=r['project'], tags=r.get('tags', []), note=r.get('note', ''), mod=r.get('modified', ''),
             sql=r.get('sql', ''), params=r.get('params', {}), src=r.get('src', ''), url=r.get('src_url', ''),
             ops=r.get('vdbe_ops'), acc=r.get('table_accesses'), rows=r.get('rows'), ch=r.get('changes'),
             ms=r.get('stock_ms_indicative'), hash=r.get('hash', ''))
    if r['id'] in turbo: q['tb'] = turbo[r['id']]
    qs.append(q)

data = dict(projects=projects, queries=qs, results=bool(turbo), results_label=label)
page = (Path(__file__).parent / 'page.html').read_text()
out.write_text(page.replace('/*DATA*/null', json.dumps(data, separators=(',', ':')).replace('</', '<\\/')))
print(f'{out}: {len(qs)} queries, {len(projects)} projects, {len(turbo)} with results, {out.stat().st_size // 1024} KB')
