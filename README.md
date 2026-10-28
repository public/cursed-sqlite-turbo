# cursed-sqlite-turbo

A query specialiser for SQLite (formerly cursed-sqlite-jit; it generates no machine code, so "JIT" oversold it). It
reads the bytecode SQLite's planner produced for a prepared statement and runs a cheaper program with the same results:
- **qc** builds specialised plans when a statement is prepared, for the shapes it recognises (feed-like pages, joins,
  counts, general loops);
- **qvm** is a specialising executor for any other read-only bytecode, with type feedback and loop regions;
- a statement neither can reproduce exactly runs through SQLite's interpreter, as before.

The SQL is unchanged; there is no new language.

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

## Goal

Every change is judged against two bars:
1. **No slower on small queries.** Point lookups, short one-shot statements, writes, and anything turbo can't
   specialise strongly must run at **≤ 1.02× stock SQLite**, never worse. That covers speedtest1, Gitea's page mix
   and the corpus's small shapes.
   - **How:** the default is conservative. Turbo takes over a statement only when it's likely to win (cost or size,
     a run count, the measured tier choice). Everything else stays on SQLite's interpreter with near-zero overhead.
2. **Substantial wins on complex queries.** These are loops, aggregation, DISTINCT, top-N, joins, scans with
   expressions, and DOOMQL-style computation in SQL.

A query class that is consistently slower is a bug to fix or a class to exclude, not something to average away.

Where it stands (turbo-bench's map by query shape, docs/BENCH.md on the bench branch; RESULTS §16–18):
- **Wins:**
  - DISTINCT and count(DISTINCT): 0.39–0.91×.
  - top-N: Gitea's activity feed 0.86×.
  - compute (DOOMQL 0.62–0.91×, windows and recursive CTEs −27 to −52 %).
  - repeated statements through the embedded API (−13 to −82 %).
- **Parity:** large joins, aggregates, subqueries, LIKE and expression scans, at 1.01–1.05×.
- **Losses, still open:**
  - short one-shot statements through the drop-in path, 1.26×: an autocommit transaction around each call and copying
    the values back out.
  - plan tiers picking worse than qvm: speedtest1 145 at 1.76×, Gitea's join counts at 1.13–1.17×, ClickBench Q00.
  - a full sort and EXCEPT in speedtest1, 1.10–1.23×.

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

**As a drop-in, through SQLite's own API:** build the program against `build/gen/sqlite3.c` with `qc.c` included
after it, and run with `QC_SERVE=1`, or call `sqlite3_qc_serve(1)`, or build with `-DQC_SERVE_DEFAULT=1`.
- **Unchanged programs:** `sqlite3_step` runs every read-only statement qc takes through qc, and hands its rows out
  through the statement's own result row. `sqlite3_column_*`, `sqlite3_reset` and `sqlite3_finalize` work as always.
- **Everything else** runs in SQLite's interpreter, as before: writes, statements qc refuses, and connections with a
  trace or progress callback.
- **Tests:** `make serve` checks served rows against SQLite's, value by value. It also covers resets and finalizes
  part way, nested statements, and both autocommit and explicit transactions.
- **Known differences:** a served statement's `sqlite3_stmt_status` counters (VM steps, full-scan steps, sorts)
  stay 0. qc's process-wide run state, a few hundred KB, counts in `sqlite3_memory_used` until
  `sqlite3_qc_release()`.

**Through qc's own API**, as below, for the most speed: rows handed to a callback zero-copy, or a JSON body written by
the plan.

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
- **Transactions:** in autocommit mode `sqlite3_qc_exec` begins the read transaction itself and ends it after the run,
  as the interpreter does. Inside an explicit transaction it runs in that one. Plans keep their cursors open for the
  rest of a transaction, and a hook closes them when it ends.
- **A re-prepared statement** (schema change, `PRAGMA foreign_keys`, …) is lifted again on its next execution, and
  keeps its template.
- **Statements whose plan looked at a bound value** (`LIKE ?`, for instance) are lifted as SQLite planned them. A new
  binding expires such a statement, as it does in SQLite; the re-prepared program is lifted again (the plan cache
  catches an identical one). qc used to re-prepare them under the query-planner stability guarantee, but that plan
  could be far worse than SQLite's, and it stayed even when the lift was refused (RESULTS §22).

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

The tables are in [docs/RESULTS.md](docs/RESULTS.md) §6, §7, §7b–§7e and §8–§14.

qc never changes a result. Anything it can't reproduce exactly falls back to `sqlite3_step()` before any row is
handed out.

## Build

```sh
make          # fetches SQLite 3.54.1 (pinned, SHA-256 checked), patches a copy, generates the decoders
make test     # builds a 50k-user / 200k-post / 800k-like test database and runs the differential test
make bench
```

Needs a C compiler and Python 3. Tested on macOS arm64 (clang), Linux arm64 (gcc 13: the suites) and Linux x86-64
(clang 18/19; gcc 13 since RESULTS §16, which fixed a wrong result only gcc on x86-64 produced). `make regress` runs
every wrong result found so far; `make topn` the top-N sorter.

Build-time knobs (`CFLAGS`):
- `-DQV_MAXPINS=N` (default 65536, at least 256): how many distinct database pages one qvm execution may keep
  pinned while text or blob values point into them. Each page is pinned once per execution. Past the limit, the
  execution falls back to the interpreter. A pinned page holds a page-cache reference until the execution ends, so
  the worst case is N × page size.
- `-DQV_PIN_CHEAP=N` (default 128): past this many pinned pages in one execution, qvm copies text and blobs into
  their registers, as vdbe.c does, instead of pinning more pages. A long scan then doesn't pay a pin per page for
  values that ResultRow or an insert copies anyway. `0` copies always.
- `-DQV_TOPN_MAX=N` (default 256): the most entries qvm's top-N sorter (`ORDER BY … LIMIT N`) keeps in a sorted array.
  Past that it moves them into an ephemeral B-tree, as SQLite would have used. `QV_NOTOPN=1` at run time always uses
  the B-tree.
- `-DQV_SPILL_COPY_MAX=N` (default 256 MB): a sort that outgrows memory runs in SQLite's own sorter, and qvm copies
  the rows it reads back. Past N bytes in one run, the statement falls back to the interpreter.
- `-DQC_MAXPLANS=N` (default 1024, per tier): how many statements can hold a lifted plan at once in one process.
  Beyond that, a statement isn't lifted and runs in the interpreter. A transaction's end closes only the cursors of
  the plans it used, so a large cap costs nothing per transaction.
- `-DQC_CACHE_PLANS=N` (default 256, 0 to compile it out; `QC_NOCACHE=1` at run time): the plan cache across
  prepares.
  - **Detach:** when a statement is finalized, its plan (general or qvm) is kept, keyed by connection and SQL text.
  - **Reuse:** the next prepare of the same text gets the plan back if its program has the same signature: every
    opcode and operand, with P4 compared by value. A qvm plan keeps its type feedback and loop regions.
  - **Bounds:** least recently used out, purged when the connection closes. It is per process, one thread at a time,
    as qc's run state is.
  - **Tip:** statements whose plan depends on a bound value are re-prepared by SQLite whenever a binding changes,
    and then lifted again. `SQLITE_DBCONFIG_ENABLE_QPSG` on the connection avoids that, at the cost of plans that
    ignore the bound values.
- `-DQV_NO_THREADED`: qvm dispatches with a switch instead of computed gotos.
- `-DQC_ADAPT_MIN_US=N` (default 50), `-DQC_ADAPT_WARM=N` (default 3): the adaptive tier choice (RESULTS §17).
  - **What it does:** a general or qvm plan run with a row callback is timed after its first N executions. Plans
    that take N µs or more are compared with SQLite's interpreter, which qc then runs itself on a few executions and
    whose rows it hands to the same callback.
  - **Parking:** a statement the interpreter runs at least 5 % faster is parked: `sqlite3_qc_exec` returns
    QC_FALLBACK ("parked") and the caller steps it. It is measured again after 64 × 2^R executions.
  - **Turning it off:** `QC_NOADAPT=1` at run time.

Run-time switches for measurement:
- `QC_NOREOFFER=1`: a statement re-prepared inside `sqlite3_step` (a new binding its plan looked at, a schema change)
  runs in SQLite's interpreter, as before c85cc3b (an A/B of the re-offer).
- `QC_STATS=1`: counts printed to stderr at exit (or by `sqlite3_qc_stats()`):
  - executions by tier;
  - fallbacks and failed lifts by reason;
  - the type-feedback masks of Column and comparison opcodes;
  - region nodes widened, plan cache hits;
  - the adaptive tier choice's samples, kept and parked plans.
- `QV_NUMCOL=int`: region Columns speculate on integers only, as before RESULTS §17 (A/B runs).

On x86-64 the Makefile adds `-mbranches-within-32B-boundaries` when the compiler takes it. On Cascade Lake, the
JCC-erratum microcode otherwise lets any edit move a hot loop onto a 32-byte boundary and cost it up to 15 %
(RESULTS §13).

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
| `tests/regress.c` | every wrong result found so far (SQLancer, the replays, the suites), each against the interpreter |
| `tests/topn.c` | qvm's top-N sorter: random `ORDER BY … LIMIT` queries against the interpreter |
| `wasm/` | the opt-in WebAssembly build: `build.sh`, `run-tests.sh`, the JS API glue (`qc_wasm.c`, `qc.mjs`), `bench.mjs` |
| `scripts/` | the pinned SQLite fetch, the test database generator |
| `docs/` | prior art (SQLite JITs, query compilation, copy-and-patch) and the measurements behind the numbers |
