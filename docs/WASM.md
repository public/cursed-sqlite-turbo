# WebAssembly

qc and qvm build for WebAssembly with no source changes, as an opt-in build next to the native one: `wasm/` holds the
build script, a small C glue for SQLite's JS API, its JS wrapper and the Node test drivers. Nothing in `qc/`, the
Makefile or the native build changes.

## Building

```sh
make                     # the patched amalgamation and decoders in build/gen, as for the native build
wasm/build.sh            # = wasm/build.sh tests jsapi
wasm/build.sh wasi       # optional: the corpus for WASI
wasm/run-tests.sh        # = corpus qtest jsapi; also: slt, wasi
```

Needs Docker; the toolchains are pinned images (by digest), run on CPUs 8-11 (`WASM_CPUS`; at most 4 cores locally, as the sqllogictest jobs):
- **Emscripten 6.0.12** (`emscripten/emsdk`, clang 24): the test programs and the JS API bundles. `EMCC=emcc` uses an
  emcc on the PATH instead.
- **wasi-sdk 34** (clang 23): the WASI corpus.

Output goes to `build/wasm/` (not in git):

| target | what | files |
|---|---|---|
| `tests` | the corpus, qtest, qbench and sqllogictest (when `SLT_DIR`, default `third_party/slt`, has its sources), for Node with the host's files (`-sNODERAWFS`) | `corpus.js`, `qtest.js`, `qbench.js`, `slt/sqllogictest.js` (+ `.wasm`) |
| `jsapi` | SQLite's own JS API (`ext/wasm` of the pinned source tree, `scripts/fetch-sqlite-src.sh`), both `-O2`: stock, and with qc | `jsapi/stock/`, `jsapi/jit/`: `sqlite3.mjs` + `sqlite3.wasm` |
| `wasi` | the corpus for WASI preview 1 | `wasi/corpus.wasm` |

Options: `QC_WASM_SIMD=1` builds with SIMD128 (below); `WASM_OUT=dir` puts a build somewhere else (to keep a SIMD and a
scalar build side by side).

## Using qc from JavaScript

The `jsapi/jit` bundle is `ext/wasm`'s `sqlite3.mjs` with the patched amalgamation, `qc.c` and `wasm/qc_wasm.c` in
its one compilation unit; everything `ext/wasm` offers is unchanged. `wasm/qc.mjs` adds two methods to oo1 statements:

```js
import sqlite3InitModule from './build/wasm/jsapi/jit/sqlite3.mjs';
import { installQc } from './wasm/qc.mjs';
const sqlite3 = await sqlite3InitModule();
installQc(sqlite3);
const db = new sqlite3.oo1.DB('/feed.db');
const st = db.prepare('SELECT ... WHERE p.id = ?1');
st.qc();                      // true: compiled (false: not a shape qc handles; nothing changes)
db.exec('BEGIN');             // plans run inside a transaction, as in C
st.bind([42]);
const rows = st.qcAll();      // [[...], ...]: the values stmt.get([]) would give, row by row
db.exec('COMMIT');
```

`qcAll()` runs the plan and decodes its rows from one buffer (`wasm/qc_wasm.c` copies qc's zero-copy values into it).
When the statement isn't compiled, or the plan falls back (autocommit, a value it can't reproduce), `qcAll()` steps
it. Either way the statement is reset afterwards and keeps its bindings.

Node: the bundles are `ext/wasm`'s default browser ESM build, which fetches its `.wasm`. Under Node, give it a
`fetch` for `file:` URLs, as `wasm/bench.mjs` does. `ext/wasm`'s own extra `wasm-opt --all-features` pass is skipped:
with binaryen 133 it writes the compact import section, which Node 24's V8 rejects ("unknown import kind 0x7f").
Emscripten's own `-O2` wasm-opt pass still runs.

## What is supported

Everything the native build does: the specialised plans, the general plans and qvm. That includes:
- **Threaded dispatch:** clang accepts labels as values on wasm32 and lowers the computed gotos to a `br_table` per
  dispatch site (LLVM's `IndirectBrExpand`). So `qv_run` and the loop regions build unchanged. `QFB=1` shows regions
  being built and run under Node, and `QV_NO_THREADED` is not needed.
- **SIMD:** without SIMD qc takes its scalar paths: `QC_VEC` is 0, and the JSON escaper goes byte by byte.
  `QC_WASM_SIMD=1` adds `-msimd128 -msse2`, so qc's SSE2 escaper compiles through Emscripten's SSE2-on-SIMD128
  headers (`_mm_movemask_epi8` becomes `i8x16.bitmask`) and the compiler may vectorise elsewhere. The tests pass both
  ways.
- **Threads:** single-threaded (`SQLITE_THREADSAFE=0`, which is also `ext/wasm`'s setting). qc's run state is per
  process, as natively.
- **Prefetching** (`__builtin_prefetch`) is a no-op in WebAssembly.

## Tests

All under Node 24 (`wasm/run-tests.sh`), against the interpreter in the same binary. Results are on `main` at 0e7c019
+ `wasm/`. On 71b7f04 (qvm's DOOMQL work) the corpus (both modes), qtest, the JS API and WASI were run again with the
same results.

| test | Emscripten (Node) | native, for comparison |
|---|---|---|
| corpus, plans first / `QC_VM_ONLY=1` (2000 executions per query) | 61/61 compiled, 0 mismatches / the same, all 61 in qvm | the same |
| qtest (300 write batches, seed 1) | OK: 409,053 comparisons, 408,615 equal JSON bodies, 461 fallbacks | identical counts |
| sqllogictest, whole corpus, plans first | 11,879,758 tests, 0 errors; 45,832,744 qc runs, **0 differences**; 8 handed back (`sum()` overflow); no leaks; 919 s on 4 jobs | identical counts |
| sqllogictest, `QC_VM_ONLY=1` | the same, all 11,458,186 queries in qvm; 992 s | identical counts |
| JS API: the jit bundle's `qcAll()` against stock `sqlite3.wasm` (500 executions per corpus query) | 61/61 compiled, 0 mismatches | — |
| corpus with `QC_WASM_SIMD=1`, both modes; qtest | 61/61, 0 mismatches; qtest OK, identical counts | — |
| corpus for WASI (wasi-sdk 34, `node:wasi`), both modes | 61/61, 0 mismatches | — |

In the JS API comparison, the values are decoded on each side: `step()` + `get([])`, against `qcAll()`. Integers
compare as Numbers (BigInts outside the safe range), reals bit for bit through JSON, and blobs byte for byte.

## Speed

Apple M5 Pro, Node 24.22.1, both bundles -O2 from the same source tree and flags. µs per execution, 16 per
transaction, best of 5 rounds of ~50 ms, the corpus's queries and parameters (`node wasm/bench.mjs build/wasm/test.db 500`):
- **stock:** stock `sqlite3.wasm`, `bind`, then `step()` + `get([])` per row.
- **jit, stepped:** the jit bundle without qc.
- **jit, qc:** `qcAll()`, every value decoded into JS.

| query | stock | jit, stepped | jit, qc | qc vs stock |
|---|---:|---:|---:|---:|
| feed (20 rows, 3 tables, count subquery) | 87.0 | 79.8 | **12.8** | −85 % |
| post with count (1 row) | 4.82 | 4.63 | **2.27** | −53 % |
| pk point | 3.78 | 3.72 | **1.87** | −51 % |
| index order, limit 20 | 20.2 | 19.0 | **3.09** | −85 % |
| join 1-n via index | 13.0 | 13.0 | **5.41** | −58 % |
| group by index | 24.1 | 23.7 | **5.13** | −79 % |
| union all | 16.9 | 16.4 | **3.34** | −80 % |
| recursive cte, walk | 10.2 | 9.63 | **2.52** | −75 % |
| window avg, range frame | 35.2 | 35.3 | **11.5** | −67 % |
| distinct | 137 | 134 | **68.6** | −50 % |
| group by, sorter | 188 | 189 | **159** | −15 % |
| count distinct | 68.0 | 73.7 | 71.7 | +5 % |
| **all 61, geometric mean** | | | | **−58 %** |

- **Stepping:** the jit bundle stepped normally costs the same as stock (within noise). The hooks cost nothing when qc
  isn't used.
- **Most queries:** 60 of 61 are faster through qc.
- **Close ones:** count distinct is +5 % and intersect −1 %, both within run-to-run noise.
- **Why JS gains more:** the gains through JS are larger than inside the binary. qc hands all rows over in one buffer,
  where `step()` + `get([])` crosses the JS↔wasm boundary per row and per value.

Inside the wasm binary (`corpus.js`, interpreter against qc in the same program, values read in C, 2000 executions):
- all 61 queries are faster;
- geometric mean −44 %, range −9 % to −88 %;
- feed 55.8 → 6.97 µs (−88 %), pk point 4.32 → 1.81 µs.

That is a larger gain than natively (README: feed −81 % on the same machine), because the interpreter loses more to
WebAssembly than qc's tight loops do.

The other sessions' work was running on the machine during these runs, so single rows are ±10 %.

## Gaps

- **Node and the browser bundle:** `ext/wasm` doesn't support Node officially. The bench loads the browser ESM build
  with a `file:` fetch, and with `ext/wasm`'s extra wasm-opt pass skipped (above). Browsers are untested here.
- **WASI timings:** the WASI corpus is a correctness target. Under `node:wasi` both sides run 10–20× slower than the
  Emscripten build, for the interpreter as much as for qc, and the cause hasn't been investigated (syscalls through
  the WASI shim are the first suspect; wasmtime not tried). Its µs aren't reported here.
- **No OPFS/worker tests:** the qc bundle runs anything `ext/wasm` runs, but only the in-memory file system (Node) was
  tested.
- **Memory64** (`sqlite3-64bit.wasm`) is built by `ext/wasm` but not tested with qc.
