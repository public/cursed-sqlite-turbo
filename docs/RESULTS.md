# Measurements

qc was built inside cursed-http (a C server for a SQLite benchmark challenge), against that server's queries and its
hand-written engine. This is the log of how it got to its numbers, as recorded there.
- "direct" = cursed-http's hand-written B-tree reader for the same queries;
- "direct+spec.h" = that reader plus schema-specialised decoding and a one-pass JSON writer;
- "exp<N>" = runs on an Intel Xeon Platinum 8260 (1 vCPU);
- the "M5" is an Apple M5 Pro.

## The query compiler, step by step

An earlier copy-and-patch JIT of SQLite's bytecode (in cursed-http, not shipped here) compiled every opcode to native code and was no faster than the interpreter on the Xeon (±4 %), because it keeps every opcode's semantics. `qc/qc.c`
generates the cheaper program instead, from SQLite's own bytecode at run time:
- **Lifter** (`sqlite3_qc(stmt)`): reads the prepared program and recognises one class, checking every operand that
  matters and refusing anything else:
  - a driver: an index scan with a constant LIMIT, or a rowid lookup on a bound parameter;
  - the table row behind it (`DeferredSeek`, covered index columns included);
  - inner joins by rowid;
  - correlated `count(*)` subqueries over an index equality (`BeginSubrtn … Return`, `AggStep`/`AggStep1`);
  - `ResultRow`.
  The schema cookie and generation are checked as `OP_Transaction` does.
- **Rewrites:**
  - collect the driver's rows, then fetch the table rows, stepping back one row when rowids descend;
  - each join becomes one batched, prefetching B-tree descent (a plain seek for one row);
  - each count becomes one range walk over [min, max] of the keys, using SQLite's comparison rules: integral REALs
    count, NULLs and other REALs don't, and TEXT/BLOB end the walk;
  - values are decoded straight from the records, never through `Mem`.
- **Output** (`sqlite3_qc_exec(stmt, cb, ctx)`): all rows at once, zero-copy (pointers into pinned pages for the
  duration of the callback).
- **Lifetime:**
  - cursors stay open and positioned between executions within a transaction, and are closed by a hook in
    `btreeEndTransaction`;
  - a re-prepare (e.g. after `PRAGMA foreign_keys`) re-lifts the new program on its next execution.
- **Run-time guards:** anything the plan can't reproduce exactly returns `QC_FALLBACK` before a row is handed out,
  and the caller steps the statement through the VDBE. That covers a NULL/REAL/TEXT join key, a missing author with
  LIMIT, a dangling index entry, an overflow record, a parameter SeekRowid would convert, or an expired statement.

**Correctness** (`qtest`: the same statement prepared twice on one connection, interpreted vs compiled, value by value):

| run | comparisons | compiled | fallbacks |
|---|---:|---:|---:|
| M5, seed 1, 300 batches | 1,009,032 | 1,008,690 | 342 |
| M5, seed 7, 2,000 batches | 1,060,122 | 1,057,779 | 2,343 |
| Xeon exp131/132, 200 batches | 1,006,029 | 1,005,741 | 288 |

What's covered:
- every post id on the seed;
- the feed and the newest posts after each random batch;
- writes that exercise the semantics: likes with REAL, integral-REAL, TEXT and BLOB `post_id`, a missing author, a
  TEXT `user_id`.

The fallbacks are exactly those odd rows.

**Speed** (`qbench`: the same JSON body three ways: the spec SQL through `sqlite3_step`/`sqlite3_column_*`, the
compiled plan, and the hand-written engine. 16 requests per transaction, median of 9–15, hot cache; feed bodies
checked byte-identical three ways):

| request | M5: interp → qc (direct) | Xeon exp132: interp → qc (direct) |
|---|---|---|
| feed (spec query) | 7.62 → **2.03** (1.80): −73 %, +13 % vs direct | 22.9 → **7.48** (6.46): **−67 %**, +16 % vs direct |
| get post | 0.44 → **0.22** (0.19): −50 %, +16 % | 1.35 → **0.68** (0.57): **−50 %**, +19 % |

- The first Xeon run (exp131) had get at only −28 %. ~200 KB of per-call stack arrays cost ~0.3 µs per call under
  Ubuntu gcc's stack-clash probing; they now live in the plan's run state.
- **Remaining gap to the hand-written engine (13–19 %):**
  - the generic decoder (a column mask, a `QcVal` per value) against the engine's fixed-offset reads;
  - the engine's interpolation search and cursors reused across all ops of a batch.
  The next step is shape-specialised decoders chosen at plan time (as in `spec.h`), which would bring it level.
- **What this buys the submission:** nothing directly. The direct engine already reads this way. It's the generated
  equivalent: a query compiler that gives SQL statements direct-read speed without hand-written per-query code.
  - Use 1: `CURSED=lawful`/`boring` (SQL reads).
  - Use 2: deriving `engine.c`'s reads from the SQL instead of maintaining them by hand.
  - Grey level: the same internal B-tree API as the direct reads, plus three amalgamation hooks (a `Vdbe` field,
    `sqlite3VdbeSwap`, `btreeEndTransaction`). Every execution reads the live tables (rule 5).

### 5b. Shape-specialised decoders chosen at plan time

At lift time the plan looks up each record source in the schema (`qc_find`: the driver index, the table, each join
table) and records the expected class of every column it reads or skips over:
- NULL for the INTEGER PRIMARY KEY in a table row (an integer in an index);
- integer for INTEGER affinity;
- text for TEXT affinity;
- the rowid as the index's last field.

`qc_decode_fast` then reads a record in one pass over the header, checking each type byte against its class with
inline integer reads. The first mismatch hands the row to the generic `qc_decode`, so values can't differ. The
driver's index decode also yields the rowid, which saves `sqlite3VdbeIdxRowid`'s second parse. Integer index cells in
the count walk get the same fixed-layout fast path as `engine.c`'s `lpid_cell`.

| request | Xeon exp132 (generic decode): qc (direct) | **Xeon exp133 (shapes): qc (direct)** | vs interpreter |
|---|---|---|---|
| feed | 7.48 (6.46): +16 % | **6.89 (6.41): +7–8 %** | 23.2 → 6.89: −70 % |
| get post | 0.68 (0.57): +19 % | **0.66 (0.59): +11–13 %** | 1.35 → 0.66: −51 % |

Correctness unchanged on both machines (Xeon 1,006,029 comparisons, M5 1,009,018; same fallbacks).

What's left of the gap (by profile):
- the plan's generic structure (`QcVal` arrays, a callback, its per-execution checks);
- get's three seeks, the same B-tree work as the engine's.

The hand-written engine also has `spec.h` on top (Xeon feed 5.8 µs); the same one-pass JSON writer applies to `qc`'s
zero-copy output unchanged.

### 5c. Closing in on the hand-written engine: the plan writes the response

| step | what | Xeon feed qc (direct / direct+spec.h) |
|---|---|---|
| exp133 | shape decoders, rows to a callback, JSON by the caller | 6.89 (6.41 / —) |
| exp136 | **the plan writes the body**: a JSON template given at prepare time (literal fragments around typed columns); strings in one vector pass (copy 16 bytes, OR the escape mask, re-escape only a dirty field) | 7.02 (6.35 / 5.61): fragment `memcpy`s were libc calls |
| exp137 | fragments in 32-byte padded slots, moved with two fixed 16-byte stores; inlined int/string writers; parameters passed as plain values (no `sqlite3_bind`); no pin for single-row lookups | gcc 6.76, **clang 6.33** (6.32 / 5.10–5.6) |
| **exp140** | **unrolled decoders, one per shape signature** (`qc/gen_decoders.py`, generated at build time, picked by signature at lift time); a flat writer (base + stride per output column); the schema cookie checked once per transaction (reset by the transaction-end hook); single-key counts direct | gcc 6.36–6.40, **clang 5.89–5.94: −8 % vs direct**, +12 % vs direct+spec.h (5.25–5.32) |

Get post (exp140): 0.60–0.64 µs vs direct 0.55–0.61 (+4–9 %) and direct+spec.h 0.50–0.55 (+15–21 %).

Correctness, Xeon exp140 and M5:
- rows: 1,006,020 and 1,015,096 comparisons equal;
- **JSON bodies:** 1,005,844 and 1,014,701 equal to a reference rendering of the interpreter's rows;
- new cases: own DDL inside a transaction (expires the statements; they are re-lifted, and the template is kept on
  the handle), and schema changes from a second connection between transactions (the cookie check).

**Where it stands:** the generated program beats the plain hand-written engine on the feed (with clang) and is within
12–20 % of the most specialised hand-written version. The M5 profile shows no single hotspot left: plan code
(decode + write) 1.07×, counts 1.2×, batched seeks 0.93× of `spec.h`'s. What remains is generic structure spread over
every stage.

### 5d. Cold caches (Xeon exp147, clang): where spec.h still wins

`qbench POL=<KiB>` reads that much of an unrelated buffer before every request (the server's wakeups start cold
after the kernel's networking), subtracting the pollution loop's own time:

| pollution | feed qc vs direct / vs direct+spec.h | get qc vs direct / vs direct+spec.h |
|---|---|---|
| none | −8 % / +12 % | +5 % / +17 % |
| 256 KiB (L1d gone) | −9 % / +9 % | +3 % / +13 % |
| **1 MiB (L2 gone, as in production)** | +3 % / +16 % | **+22 % / +32 %** |
| 4 MiB | −10 % / +11 % | ~equal (noisy) |

Cold, the compiled plan loses more than the hand-written code: it touches more distinct cache lines per request
(plan struct, template slots, value arrays at a fixed 16-column stride). The value arrays now use each source's own
width (`idxW`/`tabW`/`joinW`); not yet measured on the Xeon.

### 5e. Overlapped multi-tree descents ("lanes"): tried, rejected

The idea: since the plan knows every lookup in advance, walk independent B-tree descents level by level together,
prefetching every next page before fetching any. For GET that's the post row and the likes-count seek; for the feed,
the 20 post rows and the likes range seek.
- `qc_descend` handles table lanes and index lanes (integer first field, SQLite's value ordering).
- `qc_idx_walk` counts in key order from an index lane's path without a BtCursor, climbing to interior entries and
  descending into the next child.
- Correct: rows and JSON identical to the cursor path over 1M comparisons, including walks across leaves and interior
  entries, and REAL/TEXT/BLOB keys.

Xeon exp149, clang build, qc json µs (direct / direct+spec.h unchanged between the two):

| pollution | feed: lanes / no lanes | get post: lanes / no lanes |
|---|---|---|
| none | 7.82 / **6.15** | 0.83 / **0.65** |
| 256 KiB | 8.25 / **6.48** | 1.07 / **0.91** |
| 1 MiB | 14.42 / **11.81** | 3.64 / **2.75** |

Lanes lose everywhere, cold included:
- Each of the feed's 20 row lanes searches every level from the root, where the cursor path steps back one cell per
  row.
- GET loses the cached cursor's shortcuts (it is usually already on the right leaf).
- Cold, the lanes touch more cache lines than a cursor that stays near its last position, so there's no miss
  overlap left to win.

Lanes are off by default (`QC_LANES=1` turns them on).

**Best qc vs the hand-written engines (exp149, no lanes; compact value arrays):**
- feed: −2…−3 % vs direct hot and at 256 KiB, +4 % at 1 MiB; **+14…20 % vs direct+spec.h** at every level;
- get: +7…12 % vs direct, **+13…21 % vs direct+spec.h**.

### 5f. Toward a tie with direct+spec.h (Xeon perf exp153/154, bench exp151/155)

`perf` on the Xeon (root runs, fixed request counts, ns per feed):
- the batched seeks are cheaper in qc (2.00 vs 2.13 µs: interpolation + level-wise prefetch);
- counts are equal (0.63 vs 0.63);
- the whole gap was the plan's own decode and write stages (2.37 vs 1.57 µs).

Removed since:
- index-key reads not inlined (`qc_idxkey`, 140 ns on the M5);
- a variable-length `memcpy@plt` in the integer writer, now two fixed moves into the slack;
- a 120-case decoder switch clang refused to inline (~70 KB, a call and a cold jump table per row), now small per-shape decoders by pointer;
- the writer's five parallel per-column arrays, now one compact op per column;
- the separate room pass, now checked per value;
- the schema cookie per execution, now per transaction;
- the single-key count through the range machinery, now direct.

| | M5 (clang) | Xeon exp155 (clang): hot ×2 / 256 KiB / 1 MiB |
|---|---|---|
| feed qc vs direct+spec.h | **+2 %** | +9…10 % / +10 % / +12 % |
| get qc vs direct+spec.h | +12 % | +10…11 % / +9 % / +14 % |
| feed qc vs direct | −17 % | −9…−10 % / −8 % / −5 % |

Correctness unchanged (Xeon: 1,006,020 comparisons, 1,005,844 JSON bodies equal).

**What's left on x86** (~0.5 µs per feed, ~60 cycles per row), and it's structural:
- three decoder calls through pointers per row (the plan picks them at run time; spec.h's are inlined);
- `QcVal` stores and copies between the stages;
- a per-column writer loop instead of spec.h's straight-line `sp_post` with literal keys.

Removing those means generating code per plan: stitched stencils with the decoders and the writer inlined for that
plan, the copy-and-patch backend applied to the executor. Everything that can be done with precompiled generic code is
done.

### 5g. The ceiling of per-plan code generation: an oracle (Xeon exp156)

Before building a stitcher for the plan's decode and write stages, `-DQC_ORACLE` hard-codes exactly what perfect
per-plan code generation would produce for the feed/get plan: its three decoders called directly (inlined) and the
writer unrolled with literal keys and fixed column kinds. The stages, guards and fallbacks stay the same.

| Xeon, clang, vs direct+spec.h | generic plan | oracle |
|---|---|---|
| feed, hot (×2) | +11 % | **+6–7 %** |
| feed, 256 KiB | +8…10 % | **+6 %** |
| feed, 1 MiB | +9…10 % | +9…12 % (noisy) |
| get, hot (×2) | +11…14 % | +15…16 % |

Per-plan codegen of the decode and write stages is worth ~4 points on the feed and nothing on GET, and does not reach
a tie. (On the M5 the oracle is no faster at all.) The rest of the gap is spread across the other stages:
- the driver and table-row loops around SQLite's cursor calls;
- the decoded values held in arrays between stages;
- per-execution setup.

That is the price of a plan assembled at run time from general stages, against `spec.h`'s single function the C
compiler sees whole. A stitcher was therefore not built: the oracle bounds what it could deliver.

**Final standing of the query compiler on the Xeon** (clang build): the feed is 9–10 % faster than the hand-written
direct engine and 6–11 % behind direct+spec.h; GET is level with direct and 10–15 % behind direct+spec.h. All from
the SQL's own bytecode at run time, with results and JSON bodies identical to SQLite over ~1M comparisons per run.

## 6. General plans: the query-flavour corpus (Xeon exp159–162)

The plans above handle one family of shapes (the feed and post-by-id). `qc/qcg.c` adds general plans: the lifter
reads any SELECT's bytecode as the loop nest the planner emitted and runs it on the same stages (seeks as vdbe.c
does them, decoders chosen from the schema, the JSON writer). `tests/corpus.c` (`make corpus`) has 32 common query
shapes over the test schema. For each one it reports whether qc compiles it and why not, compares 10,000 executions
value by value against the interpreter with the same parameters, and times both, interleaved. Each timing has the
cost of binding parameters and of the transaction (measured alone) subtracted.

How the shapes are run:
- **Seeks and scans** are the bytecode's own: Seek*/Idx* end tests (including computed bounds such as `?1 + 20`),
  rowid points, and UNIQUE points with no loop.
- **Correlated `count(*)` and `EXISTS` subqueries** are levels of their own, run in line when their value is needed.
- **`IN (?, ...)`** becomes a level over the values, sorted and de-duplicated as SQLite's ephemeral index would hold
  them.
- **LEFT JOIN** (rowid point levels) emits SQLite's NULL row when nothing matches.
- **Functions:** deterministic built-ins (`length`, `upper`, `substr`, `LIKE`, ...) are called through SQLite's own
  implementations.
- **Batched table seeks:** the table rows behind an index level whose filters read only the index are fetched in
  batches (`qc_seek_batch`, as the feed's joins are). A batch never reads past a LIMIT.
- **`count(*)` of one integer key**, as the query or as a correlated subquery, is a walk over the index cells.
- **GROUP BY over index order** follows SQLite's Compare/Jump/Gosub state machine, including HAVING and bare columns.
  A bare column comes from the group's first row, or, next to `min()`/`max()`, from the row that aggregate took:
  ties keep the earlier row, and NULLs are taken until the first value, as `minmaxStep` does.
- **ORDER BY** through the sorter, or through a top-N ephemeral index with LIMIT, is a stable sort on the key
  fields, with the KeyInfo's DESC/BIGNULL flags. SQLite's in-memory merge keeps insertion order on ties, and the
  top-N index orders ties by its sequence number. Two corpus queries are all ties, to check this.
- **Bound parameters the planner looked at** (a `LIKE ?` pattern, a 0/1 integer) would expire the statement on every
  new binding. qc re-prepares such a statement once under SQLITE_DBCONFIG_ENABLE_QPSG's rule, so the plan doesn't
  depend on bound values. The results never did.

Intel Xeon Platinum 8260 (box1), clang -O2 -march=native, test database from `scripts/gen-db.py` (50k users, 200k
posts, 800k likes), µs per execution:

| query | qc | equal / fallbacks | interp µs | qc µs | qc vs interp |
|---|---|---:|---:|---:|---:|
| pk point | yes | 10000 / 0 | 0.835 | 0.547 | -34 % |
| pk point, one column | yes | 10000 / 0 | 0.765 | 0.595 | -22 % |
| unique index point | yes | 10000 / 0 | 1.334 | 1.163 | -13 % |
| pk range | yes | 10000 / 0 | 4.437 | 2.758 | -38 % |
| pk range, order desc | yes | 10000 / 0 | 3.388 | 2.137 | -37 % |
| pk IN list | yes | 10000 / 0 | 5.291 | 3.161 | -40 % |
| index eq, limit | yes | 10000 / 0 | 3.825 | 2.670 | -30 % |
| index eq, all rows | yes | 10000 / 0 | 1.116 | 0.908 | -19 % |
| index order, limit | yes | 10000 / 0 | 2.357 | 1.206 | -49 % |
| index range text | yes | 10000 / 0 | 2.219 | 1.544 | -30 % |
| count by index eq | yes | 10000 / 0 | 1.070 | 0.756 | -29 % |
| count by pk range | yes | 10000 / 0 | 2.178 | 1.947 | -11 % |
| exists by index | yes | 10000 / 0 | 0.981 | 0.867 | -12 % |
| join 1-1 by pk | yes | 10000 / 0 | 1.312 | 1.000 | -24 % |
| join 1-n via index | yes | 10000 / 0 | 4.937 | 3.618 | -27 % |
| left join | yes | 10000 / 0 | 1.259 | 1.069 | -15 % |
| feed (spec query) | yes | 10000 / 0 | 78.695 | 14.503 | -82 % |
| post with count | yes | 10000 / 0 | 2.282 | 1.666 | -27 % |
| user's posts + counts | yes | 10000 / 0 | 5.037 | 3.778 | -25 % |
| filter non-indexed | yes | 10000 / 0 | 4.370 | 4.696 | +7 % |
| filter LIKE | yes | 10000 / 0 | 18.073 | 16.082 | -11 % |
| projection expr | yes | 10000 / 0 | 1.167 | 1.061 | -9 % |
| group by index | yes | 10000 / 0 | 10.471 | 7.106 | -32 % |
| group by, having | yes | 10000 / 0 | 20.573 | 16.757 | -19 % |
| group by, bare col, limit | yes | 10000 / 0 | 20.487 | 14.836 | -28 % |
| order by, top-n | yes | 10000 / 0 | 6.096 | 3.256 | -47 % |
| order by desc, sorter | yes | 10000 / 0 | 4.715 | 3.172 | -33 % |
| order by, ties (sorter) | yes | 10000 / 0 | 4.912 | 3.078 | -37 % |
| order by, ties (top-n) | yes | 10000 / 0 | 6.439 | 3.345 | -48 % |
| order by, join | yes | 10000 / 0 | 5.714 | 3.886 | -32 % |
| min/max by index | yes | 10000 / 0 | 3.761 | 2.800 | -26 % |
| likes of user | yes | 10000 / 0 | 13.373 | 8.222 | -39 % |


All 32 compile, and none differs from the interpreter: 320,000 executions compared, plus qtest's 406,043 comparisons
across writes and schema changes. The other 31 queries are 9–82 % faster than the interpreter. The one exception is a
filter on a non-indexed computed value (`length(body) > 100` over a range of posts, +7 %): both walk and decode every
row, and qc calls `length()` through SQLite's function interface for each one.

How much qc gains depends on where the interpreter spends its time:
- **Biggest gains (−37 % to −49 %):** queries that touch a few rows through an index and the table behind it, where
  the batched seeks pay off: likes of a user, index order + LIMIT, top-N sorts.
- **Smallest gains (−9 % to −15 %):** single-row queries whose cost is mostly the B-tree descents, which both do the
  same way.

GROUP BY with a LIMIT needed the batch cap: with 64-row batches, qc read every row in the range before the LIMIT
stopped it (exp161: +49 % against the interpreter). With 8-row batches it is −28 % (exp162).

The absolute times on this box are about 3× those of exps 131–156: a larger database and a different broker host. The
feed's interpreter time is 79 µs here against 23.8 µs there. Compare within a run only.

Not compiled yet (refused, so SQLite runs them):
- window functions and compound SELECTs (coroutines: `InitCoroutine` / `Yield`);
- recursive CTEs (queue tables);
- GROUP BY that needs a sorter;
- `DISTINCT`;
- subqueries other than correlated `count(*)` / `EXISTS` (a `max()` subquery, for instance);
- REAL and BLOB values in sort and group keys;
- LEFT JOIN over a loop level.

## 7. qvm: any read-only statement (Xeon exp165–189)

§6's plans recognise shapes. `qc/qvm.c` runs everything else read-only: the statement's own VDBE program, opcode by
opcode, with SQLite `Mem` registers. That covers:
- coroutines and compound SELECTs (UNION, INTERSECT, EXCEPT);
- CTEs, flattened, materialized and recursive;
- window functions;
- DISTINCT and GROUP BY through the sorter;
- subqueries of every kind.

`sqlite3_qc()` tries the specialised plan first, then the general plans, then qvm, so every corpus statement now
compiles.

What makes it cheaper than vdbe.c:
- **Columns:** text and blobs from the database are `MEM_Static` pointers into pages pinned until the execution
  ends, not copies.
- **Rows:** delivered in one batch at Halt, with no `sqlite3_step` or `sqlite3_column_*` per value.
- **State:** database cursors stay open for the transaction; registers and function contexts are kept between
  executions.
- **Native paths:**
  - `count()` accumulates in a plain integer;
  - `length()` of text runs in line;
  - the sorter is an in-memory stable merge sort on keys decoded once per row.

Everything else is vdbe.c's own code path. The opcode bodies follow vdbe.c on the registers. Ephemeral tables are
SQLite's in-memory B-trees with SQLite records. Functions and aggregates, window ones included, take the registers as
arguments. Anything qvm can't reproduce exactly (an error, a write to a real table, a zeroblob) returns QC_FALLBACK
before any row is handed out.

The corpus grew to 61 shapes. Each was run in two modes: plans first (the normal path, which reports the path it
took) and with every statement forced through qvm (`QC_VM_ONLY=1`). µs per execution on box1, 200 executions per
shape compared value by value:

| query | interpreter µs | plans first: path | µs | vs interp | qvm alone: µs | vs interp |
|---|---:|---|---:|---:|---:|---:|
| pk point | 0.876 | plan | 0.568 | -35 % | 0.687 | -20 % |
| pk point, one column | 0.764 | plan | 0.593 | -22 % | 0.668 | -11 % |
| unique index point | 1.360 | loops | 1.163 | -14 % | 1.193 | -11 % |
| pk range | 4.726 | loops | 3.059 | -35 % | 3.104 | -31 % |
| pk range, order desc | 3.627 | loops | 2.413 | -33 % | 2.383 | -31 % |
| pk IN list | 5.610 | loops | 3.218 | -43 % | 5.238 | -5 % |
| index eq, limit | 3.922 | loops | 2.711 | -31 % | 3.442 | -11 % |
| index eq, all rows | 1.177 | loops | 0.951 | -19 % | 0.923 | -21 % |
| index order, limit | 2.516 | loops | 1.299 | -48 % | 1.528 | -42 % |
| index range text | 2.289 | loops | 1.622 | -29 % | 1.501 | -34 % |
| count by index eq | 1.081 | loops | 0.774 | -28 % | 0.924 | -13 % |
| count by pk range | 2.098 | loops | 1.834 | -13 % | 1.969 | -9 % |
| exists by index | 0.987 | loops | 0.891 | -10 % | 0.912 | -7 % |
| join 1-1 by pk | 1.297 | plan | 0.986 | -24 % | 1.137 | -11 % |
| join 1-n via index | 4.911 | loops | 3.591 | -27 % | 4.349 | -13 % |
| left join | 1.258 | loops | 1.074 | -15 % | 1.128 | -9 % |
| feed (spec query) | 77.594 | plan | 14.183 | -82 % | 65.680 | -12 % |
| post with count | 2.328 | plan | 1.712 | -26 % | 2.054 | -14 % |
| user's posts + counts | 5.157 | loops | 3.831 | -26 % | 4.463 | -12 % |
| filter non-indexed | 4.284 | loops | 4.772 | +11 % | 4.071 | -4 % |
| filter LIKE | 17.595 | loops | 15.308 | -13 % | 12.303 | -32 % |
| projection expr | 1.171 | loops | 1.090 | -7 % | 1.041 | -10 % |
| group by index | 10.279 | loops | 7.122 | -31 % | 8.811 | -16 % |
| group by, having | 20.371 | loops | 16.943 | -17 % | 19.327 | -7 % |
| group by, bare col, limit | 19.702 | loops | 14.105 | -28 % | 18.009 | -5 % |
| order by, top-n | 6.082 | loops | 3.126 | -49 % | 5.940 | -2 % |
| order by desc, sorter | 4.678 | loops | 3.060 | -35 % | 4.531 | -11 % |
| order by, ties (sorter) | 4.895 | loops | 2.976 | -39 % | 4.596 | -7 % |
| order by, ties (top-n) | 5.788 | loops | 2.928 | -49 % | 5.966 | +3 % |
| order by, join | 5.330 | loops | 3.669 | -31 % | 5.020 | -9 % |
| union all | 3.874 | vm | 2.877 | -26 % | 3.081 | -24 % |
| union | 4.975 | vm | 4.135 | -17 % | 4.188 | -16 % |
| intersect | 4.114 | vm | 4.325 | +5 % | 4.321 | +5 % |
| except | 5.591 | vm | 5.146 | -8 % | 5.103 | -8 % |
| cte, flattened | 1.945 | loops | 1.587 | -18 % | 1.574 | -18 % |
| cte, materialized | 5.582 | vm | 5.382 | -4 % | 5.324 | -4 % |
| subquery in FROM | 3.567 | vm | 3.425 | -4 % | 3.438 | -4 % |
| recursive cte, counter | 4.101 | vm | 3.757 | -8 % | 3.724 | -8 % |
| recursive cte, walk | 5.635 | vm | 4.337 | -23 % | 4.135 | -23 % |
| window row_number | 4.791 | vm | 4.502 | -6 % | 4.482 | -5 % |
| window rank, partition | 33.689 | vm | 31.467 | -7 % | 31.756 | -4 % |
| window sum, rows frame | 31.134 | vm | 30.291 | -3 % | 29.390 | +2 % |
| window lag/lead | 36.581 | vm | 36.676 | +0 % | 39.410 | +1 % |
| window count over () | 8.219 | vm | 7.660 | -7 % | 7.041 | -3 % |
| window avg, range frame | 34.462 | vm | 34.563 | +0 % | 34.138 | +1 % |
| window dense_rank/ntile | 58.304 | vm | 56.792 | -3 % | 56.855 | +2 % |
| distinct | 77.043 | vm | 76.506 | -1 % | 80.461 | +1 % |
| in (subselect) | 13.882 | vm | 14.008 | +1 % | 14.026 | +2 % |
| scalar subquery max | 4.576 | vm | 4.405 | -4 % | 4.517 | -5 % |
| not exists | 4.079 | loops | 4.016 | -2 % | 3.978 | -3 % |
| group by, sorter | 203.587 | vm | 210.585 | +3 % | 203.100 | +3 % |
| count distinct | 77.591 | vm | 80.908 | +4 % | 75.460 | +4 % |
| case expression | 7.412 | vm | 6.724 | -9 % | 6.447 | -10 % |
| limit offset | 1.068 | vm | 0.910 | -15 % | 0.911 | -15 % |
| left join, coalesce | 1.389 | vm | 1.268 | -9 % | 1.285 | -8 % |
| arithmetic | 5.506 | vm | 3.170 | -42 % | 3.081 | -43 % |
| concat | 0.732 | vm | 0.640 | -12 % | 0.651 | -11 % |
| avg/sum/total | 5.372 | vm | 4.924 | -8 % | 4.656 | -8 % |
| group_concat | 2.904 | vm | 3.130 | +8 % | 3.084 | +7 % |
| min/max by index | 3.913 | loops | 2.905 | -26 % | 3.671 | -4 % |
| likes of user | 13.202 | loops | 7.944 | -40 % | 12.430 | -11 % |

**Correctness:**
- 61 of 61 shapes compile and are equal in both modes.
- A pre-built ASan + UBSan binary (exp188) ran both modes with no sanitizer reports.
- qtest is unchanged.

**Bugs found and fixed on the way:**
- ephemeral B-trees: `BTREE_SINGLE` trees close with their last cursor, so qvm's own close freed them twice;
- cached rows: any ephemeral write moves cells, so every ephemeral cursor's cached row has to be dropped, as
  vdbe.c's `colCacheCtr` does;
- the sorter's arrays have to be sorted in place to keep their capacity across ResetSorter;
- the output buffer is shared by plans of different widths, so its capacity is now counted in values, not rows;
- SQLite 3.54 keeps `OP_Int64`/`OP_Real` constants in P1/P3. This also affected §6's plans.

**Speed, qvm alone:** it beats the interpreter on 50 of 61 shapes, including:
- filter LIKE −32 % and arithmetic −43 %;
- UNION ALL −24 %, recursive CTEs −8 % and −23 %;
- the feed −12 %.

The other 11 are within 1–7 %:

| shape | vs interpreter |
|---|---:|
| group_concat | +7 % |
| intersect | +5 % |
| count distinct | +4 % |
| sorter GROUP BY | +3 % |
| top-n with ties | +3 % |
| in (subselect) | +2 % |
| window frames (sum, lag/lead, avg, dense_rank) | +1–2 % |
| distinct | +1 % |

All of these spend their time in the same B-tree, ephemeral-table and function code the interpreter calls.

**What made the difference:**
- An earlier qvm held registers as qc's 16-byte values and converted them to Mems at every function, aggregate,
  seek and slow-path comparison. That cost up to 45 % (group_concat).
- Persistent run state, native `count()` and Mem registers removed it: the feed went from +31 % through +16 % to
  −12 %, HAVING from +27 % to −7 %.

In plans-first mode one shape takes a slower path than qvm would: the loop plan for a filter on `length(body)` is
+11 % where qvm alone is −4 %.
