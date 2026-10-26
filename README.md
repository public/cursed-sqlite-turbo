# cursed-sqlite-jit

**qc** is a run-time query compiler for SQLite. It reads the bytecode SQLite's planner produced for a prepared
statement, lifts it into a plan, and executes a cheaper program with the same results. The SQL is unchanged; there is
no new language. A statement it can't handle runs through SQLite's interpreter as before.

What the cheaper program does differently:
- **Correlated `count(*)` subqueries** become one range walk of the index for all rows, instead of one subquery
  (cursor open, seek, `AggStep` per entry) per row.
- **Joins by rowid** become one batched B-tree descent for all rows, level by level with prefetching and
  interpolation search.
- **Values are decoded straight from the database pages**, by decoders specialised to each record's shape (chosen
  from the schema at compile time, guarded, with a generic fallback). Nothing goes through `Mem`.
- **Output:** rows as zero-copy values, or the plan writes the response body itself from a JSON template (one vector
  pass per string, escaping only fields that need it).

Results are SQLite's: `make test` runs every compiled statement next to the interpreter on the same connection and
compares every value and every JSON body. Anything the plan can't reproduce exactly (a NULL or non-integer join key,
a missing joined row under LIMIT, an overflow record, a value of an unexpected type, an expired statement) is
detected before a row is handed out, and the call returns `QC_FALLBACK` so the caller steps the statement normally.

## Numbers

From cursed-http, where qc was built (Intel Xeon Platinum 8260, clang 19, µs per execution, hot cache; the feed is
the 20-row query below, "post by id" the single-row one):

| | SQLite interpreter | **qc** (JSON body) | hand-written B-tree code | hand-written + shape-specialised |
|---|---:|---:|---:|---:|
| feed (20 rows, 3 tables, count subquery) | 23.8 | **5.7** | 6.2 | 5.2 |
| post by id | 1.39 | **0.62** | 0.62 | 0.56 |

So qc runs the feed **4× faster than SQLite's interpreter** and 9–10 % faster than the hand-written B-tree code it was
compared with, within 6–11 % of the most specialised hand-written version.

`make bench` on this repo's generated database (Apple M5 Pro, clang, µs per execution):

| query | SQLite interpreter | qc rows | qc JSON body |
|---|---:|---:|---:|
| feed (20 rows) | 22.67 | 4.18 | 4.36 (−81 %) |
| post by id | 1.26 | 0.46 | 0.48 (−62 %) |

(The interpreter column reads every value through `sqlite3_column_*` without formatting JSON, so the JSON column does
more work than the interpreter does.)

## Using it

```c
#include "sqlite3.c"          /* build/gen/sqlite3.c: the amalgamation with qc's three hooks (qc/patch.py) */
#include "qc.c"

sqlite3_stmt *feed;
sqlite3_prepare_v3(db,
  "SELECT p.id, p.body, p.created_at, u.username,"
  "       (SELECT count(*) FROM likes l WHERE l.post_id = p.id)"
  "  FROM posts p JOIN users u ON u.id = p.user_id"
  " ORDER BY p.created_at DESC, p.id DESC LIMIT 20",
  -1, SQLITE_PREPARE_PERSISTENT, &feed, 0);
sqlite3_qc(feed);                       /* 1 = compiled; 0 = not a shape qc handles (nothing changes) */

static const QcJson tmpl = { "{\"posts\":[", "]}", ",", 5, "isssi",
  { "{\"id\":", ",\"body\":", ",\"created_at\":", ",\"author\":", ",\"like_count\":", "}" } };
sqlite3_qc_json(feed, &tmpl);           /* optional: the plan writes the body */

/* per request, inside a transaction */
QcOut o = { buf, sizeof buf };          /* keep ~64 bytes of slack at the end of buf */
if (sqlite3_qc_exec(feed, 0, &o) == SQLITE_OK) send(buf, o.n);
else { /* QC_FALLBACK: step the statement as usual */ }
```

- **Zero-copy rows instead of JSON:** pass a callback, `sqlite3_qc_exec(stmt, cb, ctx)`. It receives every row at
  once as `QcVal`s (type, integer, or pointer + length into the database pages, valid during the call).
- **Parameters** can be passed as plain values (`QcOut.param`) instead of `sqlite3_bind_*`.
- **Executions must run inside a transaction** (`BEGIN` … `COMMIT`); in autocommit mode `sqlite3_qc_exec` falls
  back. Plans keep their cursors open for the rest of a transaction, and a hook closes them when it ends.
- **A re-prepared statement** (schema change, `PRAGMA foreign_keys`, …) is lifted again on its next execution, and
  keeps its template.
- **Statements whose plan looked at a bound value** (`LIKE ?`, for instance) are re-prepared once by `sqlite3_qc()`
  under the query-planner stability guarantee, so new bindings no longer expire them.

## What it compiles today

Every read-only statement. `sqlite3_qc()` tries three executors in order, and the first that accepts the statement
runs it:
1. **The specialised plan** (`qc/qc.c`) covers the feed and post-by-id family: an index scan with a constant `LIMIT`
   or a rowid lookup, inner joins by rowid, and correlated `count(*)` subqueries. It decorrelates the counts into one
   range walk and batches the join seeks.
2. **General plans** (`qc/qcg.c`) cover whatever loop nest the planner emitted:
   - scans, seeks with end tests, rowid and UNIQUE points, `IN (...)` lists;
   - inner and LEFT JOINs;
   - correlated `count(*)` / `EXISTS`;
   - filters and deterministic functions;
   - `count`/`min`/`max`, GROUP BY over index order, ORDER BY through the sorter or a top-N index, `LIMIT`.

   Table rows are fetched in batches behind index levels.
3. **qvm** (`qc/qvm.c`) covers anything else read-only: coroutines, UNION / INTERSECT / EXCEPT, CTEs (recursive
   ones included), window functions, DISTINCT, sorter GROUP BY, and any subquery. It runs the VDBE program itself on
   SQLite `Mem` registers. Text stays in the pinned database pages, rows are handed out in one batch, and cursors and
   registers are kept between executions.

`make corpus` runs 61 common query shapes and compares every result with the interpreter's. On the Xeon (exp198):
- **plans first (normal):** all 61 compile and are equal. 58 are faster than the interpreter, by up to 82 % (the
  feed), and the other 3 are within ±4 %.
- **qvm alone:** 59 of the 61 are faster, including:
  - window functions, by 7–37 %;
  - UNION, by 19–28 %;
  - materialized CTEs, by 22 %.
- **The close shapes:** in alternating A/B timing, no shape is behind the interpreter.
- **Middle tier, part 1:** vectors for ephemeral rowid tables and native `sum`/`avg` (exp200–201). Window functions
  are now 27–44 % faster than the interpreter and recursive CTEs 52 %. The plan for the rest of the tier, a typed IR
  with record-shape speculation, is in [docs/IR.md](docs/IR.md).
- **Middle tier, part 2:** type feedback and loop regions (exp213–221). Single-cursor loop bodies become direct-threaded
  nodes, specialised by the feedback, that decode each row once. qvm alone gets 4–13 points faster on scans, filters,
  expressions and GROUP BY over an index, and is level with the previous commit elsewhere.
- **Hash sets** for DISTINCT and count(DISTINCT) (exp226): 8–12 points faster than with ephemeral B-trees.
- **sqllogictest:** every query in SQLite's public corpus (11.46M queries, 11.88M tests) compiles, runs 4 times through
  qc and matches the interpreter value for value: 0 harness errors and 0 differences in 45.8M runs, in both modes
  (`tests/build-slt.sh`, RESULTS §8).
- **SQLite's TCL test suite:** 408 query-execution test files (295k tests), with a differential `sqlite3_step` that
  runs each read-only statement through qc as well: 253k statements compiled, 0 differences (`tests/build-tcl.sh`,
  RESULTS §9).
- **SQLite's fuzz corpora** (fuzzcheck, `test/fuzzdata1–8.db`), under ASan/UBSan with the same hook: 15.7k statements
  compared, 0 differences, no sanitizer reports (RESULTS §10). TH3 isn't public.

- **DOOMQL** (two frame queries, 7.5k and 95k opcodes, float-heavy): qvm is 4–34 % faster than the interpreter, with
  frames identical (RESULTS §11). Turso's Doom VDBE program: level with the interpreter natively, 0.90–0.96× in
  Chrome's WebAssembly (it was 0.44×), RESULTS §12.

The tables are in [docs/RESULTS.md](docs/RESULTS.md) §6, §7, §7b–§7e and §8–§12.

qc never changes a result. Anything it can't reproduce exactly falls back to `sqlite3_step()` before any row is
handed out.

## Build

```sh
make          # fetches SQLite 3.54.1 (pinned, SHA-256 checked), patches a copy, generates the decoders
make test     # builds a 50k-user / 200k-post / 800k-like test database and runs the differential test
make bench
```

Needs a C compiler and Python 3. Tested on macOS arm64 (clang) and Linux x86-64 (gcc 13, clang 18/19).

Build-time knobs (`CFLAGS`):
- `-DQV_MAXPINS=N` (default 65536, at least 256): how many distinct database pages one qvm execution may keep
  pinned while text or blob values point into them. Each page is pinned once per execution. Past the limit, the
  execution falls back to the interpreter. A pinned page holds a page-cache reference until the execution ends, so
  the worst case is N × page size.
- `-DQV_NO_THREADED`: qvm dispatches with a switch instead of computed gotos.

**WebAssembly (opt-in):** `wasm/build.sh` builds qc + qvm with Emscripten (pinned Docker image). It produces the test
programs for Node, and SQLite's own JS API bundle (`ext/wasm`) both stock and with qc, with `wasm/qc.mjs` adding
`stmt.qc()` / `stmt.qcAll()` to oo1 statements. `wasm/build.sh wasi` builds the corpus with wasi-sdk.
`wasm/run-tests.sh` runs the corpus, qtest, sqllogictest and the JS API comparison under Node: 0 differences, as
natively. The native build is unchanged. See [docs/WASM.md](docs/WASM.md).

## Files

| | |
|---|---|
| `qc/qc.c` | the specialised lifter and executor, the JSON writer, the public API (`#include` after the patched `sqlite3.c`) |
| `qc/qcg.c` | general plans: the loop-nest lifter and executor (included by `qc.c`) |
| `qc/qvm.c` | qvm: the executor for any other read-only VDBE program (included by `qc.c`) |
| `qc/patch.py` | the three hooks in the amalgamation (`struct Vdbe` fields, `sqlite3VdbeSwap`, `btreeEndTransaction`) |
| `qc/gen_decoders.py` | the unrolled per-shape record decoders (generated into `build/gen/qc_dec.h`) |
| `tests/qtest.c` | differential test against the interpreter: rows and JSON, odd values, schema changes |
| `bench/qbench.c` | interpreter vs qc |
| `tests/corpus.c` | 61 query shapes: which executor, results against the interpreter, µs (`QC_VM_ONLY=1`: everything through qvm) |
| `wasm/` | the opt-in WebAssembly build: `build.sh`, `run-tests.sh`, the JS API glue (`qc_wasm.c`, `qc.mjs`), `bench.mjs` |
| `scripts/` | the pinned SQLite fetch, the test database generator |
| `docs/` | prior art (SQLite JITs, query compilation, copy-and-patch) and the measurements behind the numbers |
