#!/usr/bin/env python3
"""serve.py [--port 8765] [--scale 1] [--results DIR [--label TEXT]]: the query corpus explorer as a local app, at
http://127.0.0.1:8765/. The page is build.py's, plus a Run panel on every query and a console on every application:
SQL (edited or as recorded) and its parameters run on that application's database, built on first use from its
schema.sql and data.sql (ANALYZE unless meta.json says not; build/corpus-explorer/<project>-s<scale>.db, rebuilt when
the corpus files are newer), with the application's connection pragmas and TZ=UTC, as tools/run.py runs them.
Every statement runs inside BEGIN ... ROLLBACK, so writes never stick. The engine is Python's sqlite3 module (its
SQLite version is on the page) with regexp() and percentile()/median() added where the shell would have them.
Compare (stock vs turbo): the statement through bench/corpus/corpus.c, as the benchmark runs it, built natively
against stock SQLite 3.54.1 and against turbo (qc from this tree, or from --turbo-ref; bench/lib.sh's options; built on
first use under build/corpus-explorer/bin-*, about half a minute): its rows checked against stock's, then timed hot
(prepared once) and prep (prepared each run), the arms alternating over 3 rounds. turbo is the shipped defaults
(QC_SERVE=1); "turbo, adapt off" serves every run. On macOS there are no perf counters, so times only. Compare needs
the bench harness (bench/lib.sh, bench/build-sqlite.sh, bench/corpus/corpus.c, on the bench branch); without it the page
hides the button.
Listens on 127.0.0.1 only."""
import argparse, json, os, re, shutil, sqlite3, statistics, subprocess, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent)); import build
H = build.H; ROOT = H.parent.parent; DBDIR = ROOT / 'build' / 'corpus-explorer'
os.environ['TZ'] = 'UTC'; time.tzset()
locks, built = {}, {}

def add_functions(c):   # (the CLI's regexp and percentile family, which the corpus's anki, mlflow and phoenix use)
    def regexp(pat, s):
        if pat is None or s is None: return None
        return 1 if re.search(pat, s if isinstance(s, str) else str(s)) else 0
    c.create_function('regexp', 2, regexp, deterministic=True)
    class Pct:
        def __init__(self): self.v, self.p = [], None
        def step(self, y, p=50.0):
            if y is not None: self.v.append(float(y))
            self.p = p
        def finalize(self):
            if not self.v: return None
            v = sorted(self.v); k = (len(v) - 1) * float(self.p) / 100; f = int(k)
            return v[f] if f + 1 >= len(v) else v[f] + (v[f + 1] - v[f]) * (k - f)
    class Cont(Pct):
        def step(self, y, p=0.5): super().step(y, float(p) * 100)
    class Median(Pct):
        def step(self, y): super().step(y, 50.0)
    c.create_aggregate('percentile', 2, Pct); c.create_aggregate('percentile_cont', 2, Cont); c.create_aggregate('median', 1, Median)

def db_for(p, scale):
    """The project's database, built (or rebuilt when the corpus files are newer) under a per-project lock."""
    pdir = H / 'projects' / p
    if not (pdir / 'schema.sql').exists(): raise ValueError(f'no project {p!r}')
    db = DBDIR / f'{p}-s{scale}.db'
    with locks.setdefault(p, threading.Lock()):
        src = max((pdir / f).stat().st_mtime for f in ('schema.sql', 'data.sql', 'meta.json'))
        if not db.exists() or db.stat().st_mtime < src:
            DBDIR.mkdir(parents=True, exist_ok=True); tmp = db.with_suffix('.tmp')
            if tmp.exists(): tmp.unlink()
            meta = json.loads((pdir / 'meta.json').read_text()); t = time.time()
            c = sqlite3.connect(tmp, isolation_level=None); add_functions(c)
            c.executescript(f"PRAGMA journal_mode=OFF;\nCREATE TEMP TABLE _cfg AS SELECT {int(scale)} AS scale;\n"
                            + (pdir / 'schema.sql').read_text() + '\n' + (pdir / 'data.sql').read_text()
                            + ('\nANALYZE;\n' if meta.get('analyze', True) else '\n'))
            c.close(); tmp.replace(db); built[p] = round(time.time() - t, 2)
    return db

def bindings(c, params):
    """The manifest's parameters are SQL literals (e.g. 'abc', 42, char(31)): each is evaluated once, then bound by
    name (:a @a $a) or by number (?1)."""
    named, numbered = {}, {}
    for k, lit in (params or {}).items():
        v = c.execute(f'SELECT {lit}').fetchone()[0]
        if re.fullmatch(r'\?\d+', k): numbered[int(k[1:])] = v
        else: named[k[1:] if k[:1] in ':@$' else k] = v
    if numbered and named: raise ValueError('mixed ?NNN and named parameters are not supported here')
    if numbered: return [numbered.get(i) for i in range(1, max(numbered) + 1)]
    return named

def show(v):
    if isinstance(v, bytes): return {'blob': len(v), 'hex': v[:48].hex()}
    if isinstance(v, float) and (v != v or v in (float('inf'), float('-inf'))): return str(v)
    return v

def run(req, scale):
    p, sql = req.get('project', ''), req.get('sql', '')
    if not sql.strip(): raise ValueError('nothing to run')
    limit = max(1, min(int(req.get('limit', 200)), 5000))
    db = db_for(p, scale); meta = json.loads((H / 'projects' / p / 'meta.json').read_text())
    c = sqlite3.connect(db, isolation_level=None, check_same_thread=False, timeout=30)
    try:
        add_functions(c)
        for pr in meta.get('pragmas', []): c.execute(pr)
        args = bindings(c, req.get('params'))
        out = {'project': p, 'db': str(db.relative_to(ROOT)), 'sqlite': sqlite3.sqlite_version, 'built_s': built.get(p)}
        if req.get('plan', True):
            try: out['plan'] = [list(r) for r in c.execute('EXPLAIN QUERY PLAN ' + sql, args)]
            except sqlite3.Error as e: out['plan_error'] = str(e)
            try: out['ops'] = sum(1 for _ in c.execute('EXPLAIN ' + sql, args))
            except sqlite3.Error: pass
        c.execute('BEGIN'); ch0 = c.total_changes; t = time.perf_counter()
        try:
            cur = c.execute(sql, args); rows = []; n = 0
            for r in cur:
                if n < limit: rows.append([show(v) for v in r])
                n += 1
            ms = (time.perf_counter() - t) * 1000
            out.update(columns=[d[0] for d in cur.description or []], rows=rows, count=n, truncated=n > limit,
                       changes=c.total_changes - ch0, ms=round(ms, 3))
        finally: c.execute('ROLLBACK')
        reps = int(req.get('reps', 0))
        if reps > 0:   # (a timing: the statement prepared once and run reps times, each inside BEGIN ... ROLLBACK)
            ts = []
            for _ in range(min(reps, 1000)):
                c.execute('BEGIN'); ch0 = c.total_changes; t = time.perf_counter()
                for _r in c.execute(sql, args): pass
                ts.append((time.perf_counter() - t) * 1000); c.execute('ROLLBACK')
                if sum(ts) > 5000: break
            out['timing'] = {'runs': len(ts), 'median_ms': round(statistics.median(ts), 4), 'min_ms': round(min(ts), 4)}
        return out
    finally: c.close()

ARMS = {'stock': ('stock', {}), 'turbo': ('native', {'QC_SERVE': '1'}), 'turbo, adapt off': ('native', {'QC_SERVE': '1', 'QC_NOADAPT': '1'})}
cmp_lock, bin_lock = threading.Lock(), threading.Lock()
HARNESS = all((ROOT / f).exists() for f in ('bench/lib.sh', 'bench/build-sqlite.sh', 'bench/corpus/corpus.c'))
turbo = {'ref': None, 'desc': '', 'tree': ROOT, 'bin': None}

def turbo_setup(ref):
    """Where turbo's qc comes from: this tree (ref None), or a git ref's qc/ unpacked under build/corpus-explorer."""
    git = lambda *a: subprocess.run(['git', '-C', str(ROOT), *a], capture_output=True, text=True).stdout.strip()
    if not ref:
        dirty = ' + uncommitted changes' if git('status', '--porcelain', '--', 'qc') else ''
        turbo.update(desc=f"qc from this tree ({git('log', '-1', '--format=%h', '--', 'qc')}{dirty})", bin=DBDIR / 'bin'); return
    sha = git('rev-parse', '--short', ref)
    if not sha: sys.exit(f'serve: no git ref {ref!r}')
    tree = DBDIR / f'src-{sha}'
    if not (tree / 'qc').exists():
        tree.mkdir(parents=True, exist_ok=True)
        a = subprocess.run(['git', '-C', str(ROOT), 'archive', sha, 'qc'], capture_output=True)   # (the ref's engine;
        if a.returncode: sys.exit(f'serve: {ref} has no qc/: {a.stderr.decode().strip()}')            #  the build scripts are this tree's)
        subprocess.run(['tar', '-x', '-C', str(tree)], input=a.stdout, check=True)
        for f in ('bench/lib.sh', 'bench/build-sqlite.sh', 'bench/qc_serve.c', 'scripts/fetch-sqlite.sh', 'tests/tcl_qc.c'):
            (tree / f).parent.mkdir(parents=True, exist_ok=True); shutil.copy2(ROOT / f, tree / f)
        (tree / 'third_party').symlink_to(ROOT / 'third_party')
    turbo.update(ref=ref, desc=f'qc from {ref} ({sha})', tree=tree, bin=DBDIR / f'bin-{sha}')

def bins():
    """corpus.c linked against stock and turbo (bench/lib.sh's options and corpus/run.sh's additions), once per server
    run (bench/lib.sh recompiles SQLite only when qc's sources are newer than its object)."""
    b = turbo['bin']
    with bin_lock:
        if not turbo.get('linked'):
            b.mkdir(parents=True, exist_ok=True)
            sh = ('. "$BR/bench/lib.sh"; BENCH_SQLOPTS="$(echo "$BENCH_SQLOPTS" | sed s/-DSQLITE_DQS=0/-DSQLITE_DQS=3/) '
                  '-DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_PERCENTILE"; '
                  'bench_link stock "$BB/corpus-stock" "$SRC" && bench_link native "$BB/corpus-native" "$SRC"')
            r = subprocess.run(['sh', '-c', sh], capture_output=True, text=True,
                               env={**os.environ, 'BR': str(turbo['tree']), 'BENCH_BUILD': str(b), 'SRC': str(H / 'corpus.c')})
            if r.returncode: raise ValueError('building the stock and turbo programs failed:\n' + r.stderr[-3000:])
            turbo['linked'] = True
    return b

def cdb_for(p, scale):
    """The project's database as the benchmark builds it (by the stock program), next to the Run one."""
    pdir = H / 'projects' / p; db = DBDIR / f'{p}-s{scale}.cdb'
    with locks.setdefault(p, threading.Lock()):
        src = max((pdir / f).stat().st_mtime for f in ('schema.sql', 'data.sql', 'meta.json'))
        if not db.exists() or db.stat().st_mtime < src:
            meta = json.loads((pdir / 'meta.json').read_text()); DBDIR.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile('w', suffix='.sql', dir=DBDIR, delete=False) as f:
                f.write(f"PRAGMA journal_mode=OFF;\nCREATE TEMP TABLE _cfg AS SELECT {int(scale)} AS scale;\n" + (pdir / 'schema.sql').read_text()
                        + '\n' + (pdir / 'data.sql').read_text() + ('\nANALYZE;\n' if meta.get('analyze', True) else '\n'))
            tmp = db.with_suffix('.ctmp')
            if tmp.exists(): tmp.unlink()
            r = subprocess.run([str(bins() / 'corpus-stock'), 'build', str(tmp), f.name], capture_output=True, text=True)
            os.unlink(f.name)
            if r.returncode: raise ValueError('building the database failed: ' + r.stderr[-2000:])
            tmp.replace(db)
    return db

def tline(out):
    for l in out.splitlines():
        x = l.split('\t')
        if x[0] in ('T', 'C'): return x
    return None

def compare(req, scale):
    p, sql = req.get('project', ''), req.get('sql', '').strip()
    if not HARNESS: raise ValueError('comparing needs the bench harness (bench/lib.sh, bench/build-sqlite.sh, bench/corpus/corpus.c), which this tree lacks')
    if not sql: raise ValueError('nothing to compare')
    if not (H / 'projects' / p / 'meta.json').exists(): raise ValueError(f'no project {p!r}')
    arms = [a for a in req.get('arms', ['stock', 'turbo']) if a in ARMS]
    if 'stock' not in arms: arms.insert(0, 'stock')
    reps, budget = max(3, min(int(req.get('reps', 200)), 2000)), max(10, min(float(req.get('budget', 300)), 3000))
    meta = json.loads((H / 'projects' / p / 'meta.json').read_text())
    first = sql.lstrip('( \n').split(None, 1)[0].upper() if sql.lstrip('( \n') else ''
    write = 0 if first in ('SELECT', 'WITH', 'VALUES') else 1
    q = ''.join(f'@@X {x.rstrip(";")};\n' for x in meta.get('pragmas', []))
    q += f'@@Q explorer 0 {write} -\n' + ''.join(f'@@P {k} {v}\n' for k, v in (req.get('params') or {}).items())
    q += (sql if sql.endswith(';') else sql + ';') + '\n'
    b = bins(); db = cdb_for(p, scale)
    with cmp_lock, tempfile.TemporaryDirectory(dir=DBDIR) as t:
        qf = Path(t) / 'q.q'; qf.write_text(q)
        def go(arm, mode, *a):
            prog, env = ARMS[arm]
            r = subprocess.run([str(b / f'corpus-{prog}'), mode, str(db), str(qf), *a], capture_output=True, text=True, timeout=600,
                               env={**{k: v for k, v in os.environ.items() if not k.startswith('QC_')}, **env, 'TZ': 'UTC'})
            x = tline(r.stdout)
            if not x: raise ValueError(f'{arm} {mode}: no result ({r.stderr.strip()[-400:] or "exit " + str(r.returncode)})')
            return x
        res = {a: {} for a in arms}
        for a in arms:   # (check: rows, changes, error and hashes over 8 runs, against stock's)
            c = go(a, 'check')
            res[a]['check'] = dict(status=c[2], rows=int(c[3]), changes=int(c[4]), hash=c[5], mset=c[6], served=c[7], error=c[8])
        s0 = res['stock']['check']
        for a in arms:
            c = res[a]['check']
            c['agrees'] = (c['status'] == s0['status'] and c['rows'] == s0['rows'] and c['changes'] == s0['changes']
                           and c['error'] == s0['error'] and c['mset'] == s0['mset'])
            c['same_order'] = c['hash'] == s0['hash']
        for mode in ('hot', 'prep'):
            runs = {a: [] for a in arms}
            for rnd in range(3):
                for a in (arms if rnd % 2 == 0 else arms[::-1]):
                    x = go(a, mode, str(reps), str(budget))
                    sv, n = x[10].split('/')
                    runs[a].append(dict(first=float(x[4]), median=float(x[5]), mean=float(x[6]), n=int(x[7]), sv=int(sv), err=x[11]))
            for a in arms:
                v = runs[a]
                res[a][mode] = dict(ms=statistics.median(r['mean'] for r in v), median_ms=statistics.median(r['median'] for r in v), first_ms=v[0]['first'],
                                    runs=sum(r['n'] for r in v), served=sum(r['sv'] for r in v), error=v[0]['err'])
        for a in arms:
            for mode in ('hot', 'prep'):
                s, m = res['stock'][mode]['ms'], res[a][mode]['ms']   # (means: corpus.c prints them to 10 ns, medians to 100 ns)
                res[a][mode]['ratio'] = round(m / s, 3) if s > 0 else None
    return dict(arms=arms, results=res, turbo=turbo['desc'], reps=reps, budget=budget, write=bool(write), db=str(db.relative_to(ROOT)))

class Handler(BaseHTTPRequestHandler):
    page = b''
    def send(self, code, body, ctype='application/json'):
        b = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code); self.send_header('Content-Type', ctype); self.send_header('Content-Length', str(len(b)))
        self.send_header('Cache-Control', 'no-store'); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path.split('?')[0] in ('/', '/index.html'): return self.send(200, Handler.page, 'text/html; charset=utf-8')
        if self.path == '/api/status':
            return self.send(200, {'sqlite': sqlite3.sqlite_version, 'scale': self.server.scale, 'turbo': turbo['desc'],
                                   'built': sorted(f.name for f in DBDIR.glob('*.db')) if DBDIR.exists() else []})
        self.send(404, {'error': 'not found'})
    def do_POST(self):
        if self.path not in ('/api/run', '/api/compare'): return self.send(404, {'error': 'not found'})
        if self.headers.get('Origin') not in (None, f'http://127.0.0.1:{self.server.server_port}', f'http://localhost:{self.server.server_port}'):
            return self.send(403, {'error': 'cross-origin request refused'})
        try:
            req = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
            self.send(200, (run if self.path == '/api/run' else compare)(req, self.server.scale))
        except subprocess.TimeoutExpired:
            self.send(200, {'error': 'the comparison took over 10 minutes; lower the repetitions or the budget'})
        except (sqlite3.Error, ValueError, KeyError) as e:
            self.send(200, {'error': f'{type(e).__name__}: {e}'})
    def log_message(self, fmt, *a): sys.stderr.write('serve: ' + (fmt % a) + '\n')

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--port', type=int, default=8765); ap.add_argument('--scale', type=int, default=1)
    ap.add_argument('--results', help='a corpus/run.sh speed directory, for turbo-vs-stock ratios')
    ap.add_argument('--label', default='', help='how to describe those results on the page')
    ap.add_argument('--turbo-ref', help="a git ref whose qc/ is turbo in comparisons (default: this tree's)")
    a = ap.parse_args()
    if a.turbo_ref and not HARNESS: sys.exit('serve: --turbo-ref is for Compare, which needs the bench harness this tree lacks')
    turbo_setup(a.turbo_ref)
    d = build.make(a.results, a.label); d['turbo'] = turbo['desc']; d['compare'] = HARNESS
    Handler.page = build.render(d, api=True).encode()
    try: srv = ThreadingHTTPServer(('127.0.0.1', a.port), Handler)
    except OSError as e: sys.exit(f'serve: port {a.port} is in use ({e.strerror}); stop the other server or pass --port {a.port + 1}')
    srv.scale = a.scale
    print(f'serve: http://127.0.0.1:{a.port}/  (SQLite {sqlite3.sqlite_version}, scale {a.scale}, databases in {DBDIR.relative_to(ROOT)})', flush=True)
    try: srv.serve_forever()
    except KeyboardInterrupt: pass
