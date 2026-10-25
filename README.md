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

## What it compiles today

One class of SELECT:
- **driver:** an index scan with a constant `LIMIT`, or a rowid lookup on a bound parameter;
- **inner joins** by rowid on a column of the driven row;
- **correlated `count(*)` subqueries** over an index equality on the row's rowid;
- **output:** plain columns (covered index columns included), rowids and counts.

Every operand that matters is checked against SQLite's own bytecode, and any other statement is refused at
`sqlite3_qc()`. Widening the class means teaching the lifter more bytecode idioms.

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
| `qc/qc.c` | the lifter, the plan executor, the JSON writer (`#include` after the patched `sqlite3.c`) |
| `qc/patch.py` | the three hooks in the amalgamation (`struct Vdbe` fields, `sqlite3VdbeSwap`, `btreeEndTransaction`) |
| `qc/gen_decoders.py` | the unrolled per-shape record decoders (generated into `build/gen/qc_dec.h`) |
| `tests/qtest.c` | differential test against the interpreter: rows and JSON, odd values, schema changes |
| `bench/qbench.c` | interpreter vs qc |
| `scripts/` | the pinned SQLite fetch, the test database generator |
| `docs/` | prior art (SQLite JITs, query compilation, copy-and-patch) and the measurements behind the numbers |
