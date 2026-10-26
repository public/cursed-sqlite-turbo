// bench.mjs <db> [executions] [name-filter]: SQLite's JS API in Node, stock sqlite3.wasm against the qc one (jsapi/jit; both from
// wasm/build.sh jsapi, both -O2), on the corpus's queries (read from tests/corpus.c, with its parameter kinds).
// For each query, with the same parameters on both sides:
//   1. correctness: every execution's rows from the qc bundle's qcAll() equal the stock bundle's step()/get([]) rows;
//   2. speed: µs per execution, 16 per transaction, best of 5 rounds of ~50 ms:
//        stock   stock sqlite3.wasm: bind, step() and get([]) for every row (what an oo1 application does)
//        qc/st   the qc bundle stepped the same way (no qc: the patched build's own cost)
//        qc/qc   the qc bundle's qcAll(): the plan, every row decoded into JS values
// The database is copied into each bundle's in-memory file system; the page cache holds all of it.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { installQc } from './qc.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const [dbPath, nArg, filt] = process.argv.slice(2);
if (!dbPath) { console.error('usage: node wasm/bench.mjs <db> [executions] [name-filter]'); process.exit(2); }
const N = +(nArg || 500);
const B = process.env.WASM_BUILD || path.join(here, '..', 'build', 'wasm', 'jsapi');

// the queries: {"name", "sql" "sql"..., "params"} entries of QS[] in tests/corpus.c
const src = fs.readFileSync(path.join(here, '..', 'tests', 'corpus.c'), 'utf8');
const qs = src.slice(src.indexOf('static const Q QS[]'), src.indexOf('#define NQ'));
const QS = [...qs.matchAll(/\{\s*"([^"]*)",\s*((?:"(?:[^"\\]|\\.)*"\s*)+),\s*"([^"]*)"\s*\}/g)]
  .map(m => ({ name: m[1], sql: [...m[2].matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(s => s[1]).join(''), params: m[3] }))
  .filter(q => !filt || q.name.includes(filt));

// the bundles are ext/wasm's default (browser) ESM build, which fetches its .wasm next to the .mjs: from a file here
const webFetch = globalThis.fetch;
globalThis.fetch = (uri, opt) => {
  const s = String(uri);
  if (!s.startsWith('file:') && !s.startsWith('/')) return webFetch(uri, opt);
  const f = s.startsWith('file:') ? fileURLToPath(s) : s;
  return Promise.resolve(new Response(fs.readFileSync(f), { headers: { 'content-type': 'application/wasm' } }));
};
const buf = fs.readFileSync(dbPath), bytes = new Uint8Array(buf.buffer, buf.byteOffset, buf.length);   // (not a Buffer: the API checks)
async function open(dir) {
  const { default: init } = await import(path.join(B, dir, 'sqlite3.mjs'));
  const w = console.warn, e = console.error; console.warn = console.error = () => {};   // (the OPFS VFSes say Node has no OPFS)
  const sqlite3 = await init({ print: () => {}, printErr: () => {} }).finally(() => { console.warn = w; console.error = e; });
  const rc = sqlite3.capi.sqlite3_js_posix_create_file('/test.db', bytes);
  if (rc) throw new Error(`${dir}: create_file ${rc}`);
  const db = new sqlite3.oo1.DB('/test.db', 'w');
  db.exec('PRAGMA cache_size=-262144; PRAGMA journal_mode=DELETE; SELECT count(*) FROM posts, users WHERE 0');
  return { sqlite3, db };
}
const stock = await open('stock'), jit = await open('jit');
installQc(jit.sqlite3);
for (const s of [stock, jit]) s.db.exec('SELECT sum(length(body)) FROM posts; SELECT count(*) FROM likes; SELECT count(*) FROM users');   // warm the caches

// parameters as tests/corpus.c makes them (xorshift64, same kinds)
const one = sql => stock.db.selectValue(sql);
const NU = one('SELECT max(id) FROM users'), NP = one('SELECT max(id) FROM posts');
const NAMES = stock.db.selectValues('SELECT username FROM users');
const WORDS = ['%alpha%', '%sqlite%', '%feed%', 'b%', '%x%'];
let rng = 0x9E3779B97F4A7C15n;
const M = (1n << 64n) - 1n;
const rnd = () => { rng ^= (rng << 13n) & M; rng ^= rng >> 7n; rng ^= (rng << 17n) & M; return rng; };
const ri = n => Number(rnd() % BigInt(n));
function params(ps) {
  return [...ps].map(k => {
    switch (k) {
      case 'p': return 1 + ri(NP);
      case 'P': return ri(8) ? 1 + ri(NP) : NP + 1 + ri(10);
      case 'u': return 1 + ri(NU);
      case 'r': return 1 + ri(NP - 25);
      case 'k': return 1 + ri(20);
      case 'n': return ri(8) ? NAMES[ri(NAMES.length)] : `user${String(1 + ri(NU)).padStart(5, '0')}_`;
      case 't': return `2025-${String(1 + ri(12)).padStart(2, '0')}-${String(1 + ri(28)).padStart(2, '0')}T00:00:00.000Z`;
      case 'w': return WORDS[ri(5)];
    }
  });
}
const key = rows => JSON.stringify(rows, (k, v) => typeof v === 'bigint' ? `${v}n` : v instanceof Uint8Array ? [...v] : v);
function stepAll(st) { const rows = []; while (st.step()) rows.push(st.get([])); st.reset(); return rows; }

const now = () => Number(process.hrtime.bigint()) / 1e3;
function time(side, st, sets, run) {   // µs per execution: 16 per transaction, best of 5 rounds of ~50 ms
  let best = Infinity, it = 16;
  for (let r = 0; r < 6; r++) {
    const t0 = now();
    for (let i = 0; i < it; i += 16) {
      side.db.exec('BEGIN');
      for (let k = 0; k < 16; k++) { const p = sets[(i + k) % sets.length]; if (p.length) st.bind(p); run(st); }
      side.db.exec('COMMIT');
    }
    const us = (now() - t0) / it;
    if (r === 0) it = Math.max(16, Math.min(8000, Math.round(50000 / us / 16) * 16));   // the first round sizes the others
    else best = Math.min(best, us);
  }
  return best;
}

console.log('| query | qc | equal | stock µs | qc/st µs | qc/qc µs | qc/qc vs stock |\n|---|---|---:|---:|---:|---:|---:|');
let bad = 0, ncomp = 0; const ratios = [];
for (const q of QS) {
  const a = stock.db.prepare(q.sql), b = jit.db.prepare(q.sql), c = jit.db.prepare(q.sql);
  const compiled = c.qc(); ncomp += compiled;
  const sets = Array.from({ length: Math.min(N, 512) }, () => params(q.params));
  let eq = 0;
  stock.db.exec('BEGIN'); jit.db.exec('BEGIN');
  for (let i = 0; i < N; i++) {
    const p = sets[i % sets.length];
    if (p.length) { a.bind(p); b.bind(p); c.bind(p); }
    const ra = key(stepAll(a)), rb = key(stepAll(b)), rc = key(c.qcAll());
    if (ra !== rc || ra !== rb) {
      bad++; console.log(`| ${q.name} | **MISMATCH** at execution ${i}, params ${JSON.stringify(p)} | | | | | |\n    stock ${ra.slice(0, 300)}\n    qc    ${rc.slice(0, 300)}`);
      break;
    }
    eq++;
  }
  stock.db.exec('COMMIT'); jit.db.exec('COMMIT');
  if (eq === N) {
    const ts = time(stock, a, sets, stepAll), tb = time(jit, b, sets, stepAll), tq = time(jit, c, sets, st => st.qcAll());
    ratios.push(tq / ts);
    console.log(`| ${q.name} | ${compiled ? 'yes' : 'no: ' + jit.sqlite3.qcWhy()} | ${eq} | ${ts.toFixed(2)} | ${tb.toFixed(2)} | ${tq.toFixed(2)} | ${((tq / ts - 1) * 100).toFixed(0)} % |`);
  }
  a.finalize(); b.finalize(); c.finalize();
}
const gm = ratios.length ? Math.exp(ratios.reduce((s, r) => s + Math.log(r), 0) / ratios.length) : 1;
console.log(`\n${ncomp} of ${QS.length} queries compiled; ${bad} mismatches; qc/qc vs stock, geometric mean ${((gm - 1) * 100).toFixed(0)} %`);
process.exit(bad ? 1 : 0);
