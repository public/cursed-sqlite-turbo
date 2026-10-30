#!/usr/bin/env python3
"""serve.py [--port 8765] [--scale 1] [--results DIR [--label TEXT]]: the query corpus explorer as a local app, at
http://127.0.0.1:8765/. The page is build.py's, plus a Run panel on every query and a console on every application:
SQL (edited or as recorded) and its parameters run on that application's database, built on first use from its
schema.sql and data.sql (ANALYZE unless meta.json says not; build/corpus-explorer/<project>-s<scale>.db, rebuilt when
the corpus files are newer), with the application's connection pragmas and TZ=UTC, as tools/run.py runs them.
Every statement runs inside BEGIN ... ROLLBACK, so writes never stick. The engine is Python's sqlite3 module (its
SQLite version is on the page) with regexp() and percentile()/median() added where the shell would have them.
Listens on 127.0.0.1 only."""
import argparse, json, os, re, sqlite3, statistics, sys, threading, time
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

class Handler(BaseHTTPRequestHandler):
    page = b''
    def send(self, code, body, ctype='application/json'):
        b = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code); self.send_header('Content-Type', ctype); self.send_header('Content-Length', str(len(b)))
        self.send_header('Cache-Control', 'no-store'); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path.split('?')[0] in ('/', '/index.html'): return self.send(200, Handler.page, 'text/html; charset=utf-8')
        if self.path == '/api/status':
            return self.send(200, {'sqlite': sqlite3.sqlite_version, 'scale': self.server.scale,
                                   'built': sorted(f.name for f in DBDIR.glob('*.db')) if DBDIR.exists() else []})
        self.send(404, {'error': 'not found'})
    def do_POST(self):
        if self.path != '/api/run': return self.send(404, {'error': 'not found'})
        if self.headers.get('Origin') not in (None, f'http://127.0.0.1:{self.server.server_port}', f'http://localhost:{self.server.server_port}'):
            return self.send(403, {'error': 'cross-origin request refused'})
        try:
            req = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
            self.send(200, run(req, self.server.scale))
        except (sqlite3.Error, ValueError, KeyError) as e:
            self.send(200, {'error': f'{type(e).__name__}: {e}'})
    def log_message(self, fmt, *a): sys.stderr.write('serve: ' + (fmt % a) + '\n')

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--port', type=int, default=8765); ap.add_argument('--scale', type=int, default=1)
    ap.add_argument('--results', help='a corpus/run.sh speed directory, for turbo-vs-stock ratios')
    ap.add_argument('--label', default='', help='how to describe those results on the page')
    a = ap.parse_args()
    Handler.page = build.render(build.make(a.results, a.label), api=True).encode()
    srv = ThreadingHTTPServer(('127.0.0.1', a.port), Handler); srv.scale = a.scale
    print(f'serve: http://127.0.0.1:{a.port}/  (SQLite {sqlite3.sqlite_version}, scale {a.scale}, databases in {DBDIR.relative_to(ROOT)})', flush=True)
    try: srv.serve_forever()
    except KeyboardInterrupt: pass
