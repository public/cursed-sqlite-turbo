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

Two kinds of plan:
- **The specialised plan** (`qc/qc.c`) covers the feed and post-by-id family: an index scan with a constant `LIMIT`
  or a rowid lookup, inner joins by rowid, and correlated `count(*)` subqueries. It decorrelates the counts into one
  range walk and batches the join seeks. The table above measures this plan.
- **General plans** (`qc/qcg.c`) cover whatever loop nest the planner emitted:
  - scans, seeks with end tests, rowid and UNIQUE points, `IN (...)` lists;
  - inner joins and LEFT JOINs on rowid points;
  - correlated `count(*)` and `EXISTS` subqueries;
  - filters, including deterministic built-in functions such as `LIKE`, `length` and `substr`;
  - `count`/`min`/`max` aggregates;
  - GROUP BY over index order, with HAVING and bare columns;
  - ORDER BY through the sorter or a top-N index;
  - `LIMIT`.

`make corpus` runs 32 common query shapes. On the Xeon (exp162) all 32 compile and none differs from the interpreter.
31 of the 32 are 9–82 % faster, and one, a filter on a non-indexed computed value, is 7 % slower. The table is in
[docs/RESULTS.md](docs/RESULTS.md) §6.

Every operand that matters is checked against SQLite's own bytecode, and any other statement is refused at
`sqlite3_qc()`, so SQLite runs it unchanged. Still refused: window functions, compound SELECTs, recursive CTEs,
DISTINCT, GROUP BY that needs a sorter, and other subqueries.

## Build

```sh
make          # fetches SQLite 3.54.1 (pinned, SHA-256 checked), patches a copy, generates the decoders
make test     # builds a 50k-user / 200k-post / 800k-like test database and runs the differential test
make bench
```

Needs a C compiler and Python 3. Tested on macOS arm64 (clang) and Linux x86-64 (gcc 13, clang 18/19).

## Files

| | |
|---|---|
| `qc/qc.c` | the specialised lifter and executor, the JSON writer, the public API (`#include` after the patched `sqlite3.c`) |
| `qc/qcg.c` | general plans: the loop-nest lifter and executor (included by `qc.c`) |
| `qc/patch.py` | the three hooks in the amalgamation (`struct Vdbe` fields, `sqlite3VdbeSwap`, `btreeEndTransaction`) |
| `qc/gen_decoders.py` | the unrolled per-shape record decoders (generated into `build/gen/qc_dec.h`) |
| `tests/qtest.c` | differential test against the interpreter: rows and JSON, odd values, schema changes |
| `bench/qbench.c` | interpreter vs qc |
| `tests/corpus.c` | 32 query shapes: compiled or why not, results against the interpreter, µs |
| `scripts/` | the pinned SQLite fetch, the test database generator |
| `docs/` | prior art (SQLite JITs, query compilation, copy-and-patch) and the measurements behind the numbers |
