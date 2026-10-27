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

## 7. qvm: any read-only statement (Xeon exp165–199)

§6's plans recognise shapes. `qc/qvm.c` runs everything else read-only: the statement's own VDBE program, opcode by
opcode, with SQLite `Mem` registers. That covers:
- coroutines and compound SELECTs (UNION, INTERSECT, EXCEPT);
- CTEs, flattened, materialized and recursive;
- window functions;
- DISTINCT and GROUP BY through the sorter;
- subqueries of every kind.

`sqlite3_qc()` tries the specialised plan first, then the general plans, then qvm, so every corpus statement compiles.

The opcode bodies follow vdbe.c on the registers. Comparisons and affinities call its helpers. Ephemeral tables are
SQLite's in-memory B-trees with SQLite records. Functions and aggregates, window ones included, take the registers as
arguments. Anything qvm can't reproduce exactly (an error, a write to a real table, a zeroblob) returns QC_FALLBACK
before any row is handed out.

What makes it cheaper than vdbe.c, in the order the profiles found it:

| change | what it saves | where it showed |
|---|---|---|
| rows handed out in one batch at Halt | `sqlite3_step` and `sqlite3_column_*` per row and value | every multi-row shape |
| database text and blobs as `MEM_Static` pointers into pages, pinned only when such a value is made | OP_Column's copy of every string | text-heavy shapes; LIKE −29 % |
| registers, cursors, function contexts and their buffers kept between executions | per-run setup, `MemGrow` per argument | group_concat +45 % → 0 |
| ephemeral B-trees kept open and emptied with ClearTable on the next OpenEphemeral; cursor memory pooled | `BtreeOpen`, `BeginTrans` and `BtreeClose` per run (about 20 % of a window query) | windows −7…−37 %, materialized CTE −22 % |
| threaded dispatch (computed goto; `-DQV_NO_THREADED` or other compilers: the switch) | the switch's bounds check and its single indirect jump | feed −16 % → −19 % |
| `count()` in a plain integer; `length()` in line, 8 ASCII bytes at a time | `countStep` / finalize; `lengthFunc`'s byte loop | count distinct, sorter GROUP BY, ties |
| index end tests through `sqlite3VdbeFindCompare`'s comparator (in-page records) | the generic record compare | integer-key loops |
| `OP_String8` turned into `OP_String` at lift, as vdbe.c does on first run | a `strlen` per execution | constant arguments |

One earlier design held registers as qc's 16-byte values and converted them to Mems at every function, aggregate,
seek and slow-path comparison. Those conversions were the whole of its losses, which is why qvm moved to Mem
registers.

The corpus has 61 shapes, run in two modes:
- **plans first:** the normal path, which reports the path it took;
- **qvm alone:** every statement forced through qvm (`QC_VM_ONLY=1`).

Every execution binds fresh random parameters, and each result is compared value by value with the interpreter's.
That covers kept ephemeral tables too: one that wasn't emptied would show up as a mismatch. µs per execution on box1,
150 executions per shape (exp198):

| query | interpreter µs | plans first: path | µs | vs interp | qvm alone: µs | vs interp |
|---|---:|---|---:|---:|---:|---:|
| pk point | 0.853 | plan | 0.562 | -34 % | 0.673 | -22 % |
| pk point, one column | 0.759 | plan | 0.595 | -22 % | 0.663 | -11 % |
| unique index point | 1.372 | loops | 1.173 | -15 % | 1.182 | -12 % |
| pk range | 4.668 | loops | 3.094 | -34 % | 2.979 | -34 % |
| pk range, order desc | 3.773 | loops | 2.505 | -34 % | 2.258 | -35 % |
| pk IN list | 5.703 | loops | 3.364 | -41 % | 3.939 | -28 % |
| index eq, limit | 3.973 | loops | 2.784 | -30 % | 3.394 | -13 % |
| index eq, all rows | 1.180 | loops | 0.949 | -20 % | 0.900 | -24 % |
| index order, limit | 2.535 | loops | 1.296 | -49 % | 1.435 | -45 % |
| index range text | 2.318 | loops | 1.680 | -28 % | 1.471 | -36 % |
| count by index eq | 1.076 | loops | 0.779 | -28 % | 0.909 | -15 % |
| count by pk range | 2.136 | loops | 1.846 | -14 % | 2.135 | -12 % |
| exists by index | 0.997 | loops | 0.879 | -12 % | 0.886 | -11 % |
| join 1-1 by pk | 1.306 | plan | 0.991 | -24 % | 1.168 | -12 % |
| join 1-n via index | 4.827 | loops | 3.501 | -27 % | 4.432 | -14 % |
| left join | 1.263 | loops | 1.076 | -15 % | 1.110 | -11 % |
| feed (spec query) | 75.337 | plan | 14.221 | -81 % | 68.507 | -8 % |
| post with count | 2.251 | plan | 1.659 | -26 % | 1.991 | -12 % |
| user's posts + counts | 5.132 | loops | 3.840 | -25 % | 4.335 | -15 % |
| filter non-indexed | 4.266 | loops | 3.499 | -18 % | 3.538 | -24 % |
| filter LIKE | 17.913 | loops | 15.639 | -13 % | 13.065 | -27 % |
| projection expr | 1.172 | loops | 1.012 | -14 % | 0.980 | -16 % |
| group by index | 10.433 | loops | 6.968 | -33 % | 8.182 | -22 % |
| group by, having | 20.188 | loops | 15.640 | -23 % | 18.093 | -12 % |
| group by, bare col, limit | 18.905 | loops | 13.908 | -26 % | 17.594 | -8 % |
| order by, top-n | 5.976 | loops | 3.086 | -48 % | 4.593 | -23 % |
| order by desc, sorter | 4.732 | loops | 3.102 | -34 % | 4.047 | -10 % |
| order by, ties (sorter) | 5.153 | loops | 3.015 | -41 % | 4.472 | -11 % |
| order by, ties (top-n) | 5.699 | loops | 2.813 | -51 % | 4.760 | -21 % |
| order by, join | 5.380 | loops | 3.761 | -30 % | 4.981 | -10 % |
| union all | 3.823 | vm | 2.759 | -28 % | 2.770 | -27 % |
| union | 4.993 | vm | 4.055 | -19 % | 4.035 | -18 % |
| intersect | 4.159 | vm | 4.335 | +4 % | 4.317 | +4 % |
| except | 5.638 | vm | 5.163 | -8 % | 5.155 | -10 % |
| cte, flattened | 1.938 | loops | 1.556 | -20 % | 1.543 | -20 % |
| cte, materialized | 5.500 | vm | 4.165 | -24 % | 4.235 | -22 % |
| subquery in FROM | 3.572 | vm | 3.213 | -10 % | 3.236 | -10 % |
| recursive cte, counter | 4.011 | vm | 2.648 | -34 % | 2.663 | -33 % |
| recursive cte, walk | 5.322 | vm | 3.084 | -42 % | 3.093 | -42 % |
| window row_number | 4.611 | vm | 3.366 | -27 % | 3.330 | -28 % |
| window rank, partition | 33.744 | vm | 29.910 | -11 % | 28.845 | -13 % |
| window sum, rows frame | 28.913 | vm | 27.033 | -7 % | 25.994 | -7 % |
| window lag/lead | 36.918 | vm | 6.669 | -82 % | 6.621 | -20 % |
| window count over () | 7.614 | vm | 5.879 | -23 % | 5.638 | -21 % |
| window avg, range frame | 33.330 | vm | 30.286 | -9 % | 30.661 | -10 % |
| window dense_rank/ntile | 55.496 | vm | 50.194 | -10 % | 50.433 | -9 % |
| distinct | 74.145 | vm | 68.886 | -7 % | 70.237 | -7 % |
| in (subselect) | 39.730 | vm | 11.908 | -70 % | 11.832 | -72 % |
| scalar subquery max | 4.611 | vm | 4.328 | -6 % | 4.294 | -7 % |
| not exists | 4.088 | loops | 4.010 | -2 % | 3.794 | -7 % |
| group by, sorter | 194.111 | vm | 190.442 | -2 % | 193.453 | -7 % |
| count distinct | 76.602 | vm | 77.452 | +1 % | 74.952 | -1 % |
| case expression | 7.511 | vm | 5.450 | -27 % | 5.810 | -28 % |
| limit offset | 1.088 | vm | 0.877 | -19 % | 0.879 | -18 % |
| left join, coalesce | 1.455 | vm | 1.263 | -13 % | 1.331 | -13 % |
| arithmetic | 5.812 | vm | 3.192 | -45 % | 2.869 | -48 % |
| concat | 0.737 | vm | 0.634 | -14 % | 0.641 | -13 % |
| avg/sum/total | 5.535 | vm | 4.810 | -13 % | 4.534 | -10 % |
| group_concat | 2.867 | vm | 2.937 | +2 % | 2.945 | -0 % |
| min/max by index | 3.784 | loops | 2.880 | -24 % | 3.540 | -6 % |
| likes of user | 12.866 | loops | 7.864 | -39 % | 12.206 | -6 % |

**Correctness:**
- 61 of 61 shapes compile and are equal in both modes.
- A pre-built ASan + UBSan corpus (exp188) ran both modes with no reports.
- qtest is unchanged.

**Bugs found and fixed on the way:**
- `BTREE_SINGLE` ephemeral trees close with their last cursor, so qvm's own close freed them twice;
- any ephemeral write must drop every ephemeral cursor's cached row, as vdbe.c's `colCacheCtr` does;
- the sorter's arrays have to be sorted in place to keep their capacity across ResetSorter;
- the output buffer is shared by plans of different widths, so its capacity is counted in values;
- SQLite 3.54 keeps `OP_Int64`/`OP_Real` constants in P1/P3. This also affected §6's plans.

**Speed:** the corpus takes the best of 5 rounds of about 50 ms each, which is only good to a few percent. The shapes
it puts close to the interpreter were timed again in alternating 200 ms rounds (`QAB=`), as the median ratio:

| shape (qvm) | A/B rounds | vs interpreter, median (range) |
|---|---:|---|
| count distinct | 25 | −4.3 % (−30.8 … +9.4) |
| group_concat | 25 | 0.0 % (−7.1 … +4.9) |
| intersect | 25 | +1.9 % (−8.6 … +8.4) |
| window lag/lead | 5 | −36.8 % (−82.4 … −19.1) |
| window dense_rank/ntile | 5 | −15.9 % |
| window sum, rows frame | 5 | −8.1 % |
| materialized CTE | 5 | −22.2 % |
| in (subselect) | 5 | −16.7 % |
| union all / union | 5 | −28.2 % / −18.7 % |
| feed (exp196) | 7 | −18.6 % |

qvm alone beats the interpreter on 59 of 61 shapes in the corpus run. The other two are intersect, a tie in A/B
(+1.9 % median, range across zero), and group_concat, an A/B tie.

With plans first, 58 of 61 are faster. The three close ones (intersect, count distinct, group_concat) are qvm shapes
within ±4 %.

### 7b. Middle tier, part 1: vectors, native aggregates (Xeon exp200–201)

The first pieces of the tier planned in [IR.md](IR.md), applied directly in qvm:

- **Vectors for ephemeral rowid tables.** All 12 rowid-table families in the corpus qualify at lift time: window
  frames, and materialized and recursive CTEs.
  - Records stay in the arena and are read zero-copy.
  - Appends, rowid seeks and deletes (tombstones, with SQLite's cursor-position rules) need no B-tree.
  - A run that meets anything the vector doesn't reproduce deoptimises the plan to B-trees. None did in these runs.
- **Native `sum`/`total`/`avg`:** integers natively. The first non-integer or overflow hands the state to SQLite's
  `SumCtx`.
- **Generic opcode fast paths:**
  - OP_Compare on two integers compares them in line;
  - Copy/SCopy of numbers and NULLs is a plain field copy.

A/B medians against the interpreter, qvm alone:

| shape | before (exp195–199) | now (exp200–201) |
|---|---:|---:|
| window lag/lead | −36.8 % | −43.7 % |
| window avg, range frame | | −42.2 % |
| window rank, partition | | −28.3 % |
| window sum, rows frame | −8.1 % | −27.2 % |
| materialized CTE | −22.2 % | −34.3 % |
| recursive CTE (walk) | | −52.2 % |
| avg/sum/total | | −16.1 % |
| union all / union / except | −28.2 % / −18.7 % / | −29.4 % / −21.1 % / −14.5 % |
| intersect | +1.9 % | −3.1 % |
| group_concat | 0.0 % | −0.9 % |
| count distinct | −4.3 % | −6.6 % |

All 61 shapes are equal in both modes. In the corpus run, 59 of 61 are faster with qvm alone and 58 of 61 with plans
first. The rest read 0 to +3 % in the corpus and ahead in A/B.

### 7c. Middle tier, part 2: type feedback and loop regions (Xeon exp213–221)

Steps 1 and 4 of [IR.md](IR.md).

- **Type feedback.** For each opcode, qvm records the value classes it sees (NULL, integer, real, text, blob):
  - for Column, the value it produced;
  - for comparisons and arithmetic, both operands;
  - for AggStep, its argument.

  It records them only for a plan's first two runs. `qv_run` is compiled twice from `qvm_run.h`: a variant that
  records, and the plain loop every later run takes. So the feedback costs nothing once regions are built.
  `QFB=1 corpus` prints the masks and the regions.
- **Regions.** On the third run, every loop whose body is closed (a Next/Prev on one cursor, no inner loop, seek or
  coroutine inside) becomes a region.
  - Each opcode becomes a node: a handler chosen from the opcode, its operands and the feedback, with the operands
    resolved to pointers.
  - The nodes run direct-threaded.
  - The handlers are qv_run's own opcode bodies, now shared helpers, or in-line fast paths that check their
    preconditions and otherwise call the same body. So a region writes exactly what qv_run would, and leaving it at any
    opcode is free.
  - The loop's Next fetches the next row and parses its header through the last field the body reads. That is one
    decode per row, not one per Column.
  - A Column the feedback says is always an integer reads its field directly, and a comparison of two speculated
    integers is a machine compare. A failed guess turns the node into the generic one for good. No run is abandoned.
  - An opcode without a node returns to qv_run, which re-enters at the loop's next Next. A region that does this on
    more than a quarter of its rows turns itself off.

Correctness: every corpus run of this code (exp213, 216, 218) was 61/61 equal in both modes with 0 mismatches.

A/B medians against the interpreter, qvm alone, with regions on and off in the same run (`QV_NOREGION=1`):

| shape | regions | no regions | run |
|---|---:|---:|---|
| count by pk range | −15.0 % | −1.7 % | exp216 |
| case expression | −31.9 % | −22.6 % | exp216 |
| arithmetic | −46.8 % | −38.2 % | exp216 |
| filter LIKE | −27.5 % | −22.0 % | exp216 |
| concat | −11.6 % | −6.6 % | exp216 |
| pk range | −28.7 % | −24.6 % | exp216 |
| group by, having | −3.4 % | +3.5 % | exp218 |
| group by index | −10.3 % | −7.1 % | exp218 |
| index range text | −34.3 % | −30.4 % | exp218 |
| index lookups, avg/sum, sorter, joins | within ±2.5 pts | | exp218 |

The first builds slowed every other path, by up to 12 points on group by index and 6.5 on feed against the
previous commit (exp219). Two things caused it: feedback stores on every run, and opcode bodies that were no longer
inlined into qv_run. The two-variant loop and forced inlining remove that cost. Against the previous commit, built
side by side in the same run (exp221):

| shape | previous commit | regions |
|---|---:|---:|
| feed (spec query) | −17.8 % | −15.9 % |
| group by index | −23.8 % | −22.6 % |
| count by index eq | −14.3 % | −12.7 % |
| avg/sum/total | −11.8 % | −13.6 % |
| intersect | −0.2 % | +2.2 % |
| group_concat | −2.2 % | −0.6 % |

Counters settled the remaining gap (root perf stat, exp223–229, per execution, qvm alone). The plain loop still ran
~6 % more instructions than the previous commit. perf record (exp227) showed why: `qv_column` and `qv_serial_mem` were
no longer inlined, since they now had more call sites. Forcing them in line restores the old instruction count. The
region's Column slow path calls an out-of-line copy instead, so the region's code stays small. With both changes
(exp229):

| query | previous commit, cycles | regions, cycles | change |
|---|---:|---:|---:|
| feed (spec query) | 198.6k | 191.0k | −3.8 % |
| group by index | 25.3k | 25.1k | −0.9 % |
| intersect | 13.1k | 12.9k | −1.5 % |
| group_concat | 9.2k | 9.3k | +0.8 % |
| count distinct (hash sets, §7d) | 235.5k | 202.1k | −14 % |

Regions on group by index run fewer instructions (63.4k against 65.7k), but they take more L1i misses (87 against 62
per execution), because the body hands over to qv_run once per group.

### 7d. Hash sets for DISTINCT (Xeon exp226, 229)

Step 2 of [IR.md](IR.md). An ephemeral index becomes a hash set of its keys (`QVC_HASH`) when its cursor is touched
only by OpenEphemeral, Found/NotFound on N registers, IdxInsert of a MakeRecord of N fields (reached from nowhere
else), Close and ResetSorter, and every key collation is BINARY.
- Equality is the index's own: sqlite3VdbeRecordCompare with default_rc 0. NULL equals NULL, numbers compare by value
  (an integer equals an integral real, so the two hash alike), and text and blobs by their bytes.
- A 64-bit hash match is confirmed by decoding the stored record.
- The set lives in the run's arena, like the vectors. A key it can't represent (another encoding, a zeroblob)
  deoptimises the plan to the B-tree.

A/B medians against the interpreter, qvm alone, hash sets on and off (`QV_NOHASH=1`) in the same run (exp226):

| shape | hash set | B-tree |
|---|---:|---:|
| count distinct | −11.0 % | +1.2 % |
| distinct | −13.3 % | −5.6 % |
| union / union all / except (no hash set; control) | −17.4 / −27.4 / −10.1 % | −19.4 / −28.9 / −7.3 % |

Corpus 61/61 equal in both modes (exp226). Intersect gets nothing from this: SQLite plans it here as a merge of two
coroutines, with no ephemeral table.

## 8. sqllogictest: qc against SQLite's own corpus (2026-10-26)

[sqllogictest](https://sqlite.org/sqllogictest) is SQLite's public corpus of 622 files and about 5.9 million SQL
statements: SELECTs with joins, subqueries, compound selects, aggregates, views and mixed types, plus the statements that
build their tables. `tests/slt_qc.c` replaces the harness's SQLite engine. `scripts/fetch-slt.sh` pins the corpus to
check-in `ab599cbd`, the same one explore/sqlite-conformance used for stock SQLite. For every query record:
1. The interpreter runs the query as the harness normally does, and its values are kept.
2. A second handle is compiled with `sqlite3_qc` and run 4 times inside a transaction: two feedback runs, the run that
   builds regions, then the plain loop. Each run's values are compared with the interpreter's: type and exact value,
   with reals compared bit for bit.
3. The harness gets qc's rows, rendered through SQLite's own value conversions. So the corpus's expected results check
   qc's output independently of the comparison.

Each file runs with the optimizer on and off, and integrity_check on (`tests/build-slt.sh`, `tests/run-slt.sh`). At
disconnect the harness checks that no memory is still allocated, which checks that qc frees its plans.

**Result** (Docker on the M5, arm64, gcc -O2; the same in both modes, plans first and `QC_VM_ONLY=1`):

| | |
|---|---:|
| harness | 1244 invocations, **0 errors out of 11,879,758 tests** |
| query records | 11,458,186 |
| compiled by qc | 11,458,186 (100 %) |
| qc runs compared with the interpreter | 45,832,744 |
| value differences | **0** |
| runs handed back to SQLite | 8: `sum()` overflowing, a real SQLite error |
| leaks, crashes, non-zero exits | 0 |

On the Xeon (x86, clang), smaller subsets give the same result (exp239, 242).

**What the corpus found:**
- **A wrong result** (19,113 differing runs in the second full run). OR terms that reuse one index cursor reopen it with
  `ReopenIdx`. When the cursor is already open on that index, vdbe.c clears it and sets its seek hints again from P5.
  qvm cleared it but kept the previous `OPFLAG_SEEKEQ`. So a range term after an equality term was run as an
  equality seek, and rows were missing. Fixed.
  - Before RowSet support, these plans reached qvm only for OR over a WITHOUT ROWID table, which uses an ephemeral
    table instead of a RowSet. The 61-query corpus has no such query.
- **Lost speed, with results still right:**
  - min()/max() marks a row that changes nothing by setting `isError = -1` (sqlite3SkipAccumulatorLoad). vdbe.c errors
    only on `isError > 0`, but qvm took any non-zero value as an error and handed the statement back. That happened on
    ~5 % of all runs. Fixed.
  - OR across indexes (OP_RowSetAdd/Read/Test) wasn't supported: 372,242 queries (3.2 %) were never compiled. These
    opcodes now run in qvm through SQLite's own RowSet.
  - A general plan whose result grew past its 256-row buffer handed back on every run. It now re-lifts the statement
    for qvm.
- **Plan lifetime:** qc kept every plan forever, capped at 64 per tier, because it was written for a server with a
  fixed set of statements. A patch hook in `sqlite3VdbeClearObject` now frees a statement's plan and JSON template when
  its program is deleted, at finalize or for the old program of a re-prepare. `sqlite3_qc_release()` frees the run state
  kept between executions.

TH3, SQLite's proprietary branch-coverage suite, isn't public and wasn't run. Neither was the TCL suite, which needs a
build where `sqlite3_step` itself goes through qc.

### 7e. Index range end tests read the key from the page (Xeon exp245–247)

A profile of qvm with regions (exp245) put 37 % of feed's cycles in SQLite's index end tests: vdbeRecordCompareInt,
getCellInfo and btreeParseCellPtrIndex. Each IdxGT/IdxGE/IdxLT/IdxLE built an UnpackedRecord, parsed the cell and ran
the generic record compare.
- With one integer key against an ascending first field, `qv_idxcmp` now reads the field from the cell instead. It
  uses `qc_idx_cmp`, which the specialised plans already use. That gives SQLite's order (NULL < numbers < text < blob,
  with reals between the integers), and handles interior cells.
- Equal keys give the opcode's `default_rc`, as in vdbe.c.
- Anything else falls back to the generic compare: an overflow cell, a type it doesn't handle, a descending index, or
  more than one key field.

Per execution, qvm alone, against fbed591 (exp247, perf stat):

| query | cycles, fbed591 | cycles, now | instructions, fbed591 → now |
|---|---:|---:|---|
| feed (spec query) | 204.7k | 159.4k (−22 %) | 515.7k → 432.9k |
| count by index eq | 2.91k | 2.82k (−3 %) | 4.39k → 4.19k |
| index eq, all rows / group by index / index range text | level | level | |

(join 1-n via index is left out: the fbed591 side ran for only 0.34 s of CPU time in that run, so its per-execution numbers are mostly a cold start.)

A/B against the interpreter (exp246): feed −35.2 % (−17.9 % in exp241, same box), index eq all rows −22.5 %, count
by index eq −19.1 %.

Checked: the corpus is 61/61 in both modes (exp246), qtest is OK, all of sqllogictest still passes with 0
differences in 45.8M qc runs, and ASan/UBSan is clean (exp251, with the §9 fixes).

## 9. SQLite's TCL test suite with a differential sqlite3_step (2026-10-26)

`tests/tcl_qc.c` builds into SQLite's own testfixture (`tests/build-tcl.sh`, from the canonical 3.54.1 tree pinned by
`scripts/fetch-sqlite-src.sh`; `qc/patch.py --step-hook` renames `sqlite3_step` so a wrapper sees every step, including
`sqlite3_exec`'s and TCL's `db eval`).
- When a read-only statement starts and nothing else is running on its connection, the wrapper prepares a copy with
  the same bindings, compiles it with qc and runs it inside BEGIN…COMMIT.
- The connection's trace, profile, authorizer and progress callbacks and the global log are off meanwhile, so the
  test sees none of this.
- Every row the interpreter then returns is compared, value by value, with qc's, then the row counts. The test only
  ever sees SQLite's results.
- It skips what two runs can't agree on, and counts each kind:
  - statements calling non-deterministic or time-dependent functions;
  - virtual tables;
  - statements run while a progress handler is set;
  - statements written to by the test while it reads them.

The selection is 408 files about query execution (`tests/tcl-files.txt`; run with `tests/run-tcl.sh`): select*, where*, join*, window*, with*, in*, distinct, orderby*, limit*, minmax*, aggregates,
func*, collate*, the json and date tests, rowvalue*, affinity*, index*, misc*, tkt-*, e_select, e_expr and others.
Left out: fault injection, malloc, I/O, crash, locking, threads, WAL, FTS, R-tree, sessions and virtual-table tests,
plus withM (an OOM test) and misc7 (over 20 minutes even without qc).

**Result** (Docker on the M5, 4 cores; plans first and `QC_VM_ONLY=1` give the same):

| | |
|---|---:|
| test files / tests | 408 / 295,492 |
| read-only statements seen | 313,312 |
| compiled by qc and compared | 253,247 (2.93M rows; with built-in aggregates, see §10) |
| **differences** | **0** |
| tests that fail with qc and pass without | 14, all in like.test: it counts LIKE calls (`sqlite_like_count`), and qc's copy calls LIKE too |

The baseline with the hook off (`QCT_OFF=1`, same binary) is 0 errors out of 295,443 tests.

**What it found** (all fixed; sqllogictest, the corpus and qtest pass again afterwards):
- **LIKE/GLOB prefix ranges returned rows twice.** Without `SQLITE_LIKE_DOESNT_MATCH_BLOBS`, SQLite's plan scans the
  index range twice, the second time with the key made a BLOB by `String8 … P3`. qvm's lifter turned String8 into
  String and dropped that, so the second pass scanned the text range again. The general plans ignored it too.
  - qvm now applies it, and the general plans refuse that form.
  - The server builds with `SQLITE_LIKE_DOESNT_MATCH_BLOBS`, so it never sees this code.
- **The general plans passed REAL and BLOB values to functions as NULL** (`qg_mem`). So `typeof`, `quote`, `substr`,
  `abs`, `instr` and the JSON functions were wrong on such columns. The same conversion built their seek keys, so a
  REAL key became NULL there too.
- **Function auxdata leaked.** `sqlite3_set_auxdata` is what the JSON functions use to cache parsed arguments. vdbe.c
  frees it when a statement halts or resets, but qvm and the general plans never do either. They now free it at the
  end of each run.
- **ORDER BY ties past SQLite's sort memory.** When vdbesort.c's records outgrow `mxPmaSize` (the cache size), it
  writes sorted runs to disk and merges them, and equal keys can come out in another order than one in-memory sort.
  qvm's sorter now counts the same memory, at least as SQLite does, and hands the statement back where SQLite would
  write its first run.
- **qv_lift leaked a partial plan on out-of-memory** (found by a fault-injection test). It now frees it.

## 10. SQLite's fuzz corpora (fuzzcheck) with the differential sqlite3_step (2026-10-26)

TH3, SQLite's own branch-coverage suite, isn't public. The closest public substitute is `test/fuzzdata1–8.db`: years of
fuzzer-found SQL and corrupt databases, run by SQLite's `fuzzcheck`, with its time limits and memory limits.
`tests/build-tcl.sh <dir> fuzzcheck-asan` builds fuzzcheck with the same hook as the TCL suite (§9), under ASan, UBSan
and LeakSanitizer. In fuzz mode (`QCT_FUZZ=1`) the hook keeps fuzzcheck's progress handler, which is its time limit, and
counts the interpreter's failures after qc returned rows separately.

**Result** (Docker on the M5; plans first and `QC_VM_ONLY=1` give the same): all 8 corpora pass, with no sanitizer
reports. 15,656 statements were compiled and compared against the interpreter, over 126,851 rows, with **0
differences**. Three interpreter failures after qc had returned rows were fuzzcheck's time limit stopping the
interpreter. On the same database without the limit, the interpreter returns exactly qc's rows. The baseline with the
hook off is clean too.

**What it found** (all fixed):
- **Interrupts and progress handlers were ignored.** A runaway statement, such as a recursive CTE without an end,
  would run forever under qc, where SQLite stops it. qvm now checks `sqlite3_interrupt()` and calls the progress
  handler where vdbe.c does: on a loop's back edge in qv_run every 64 iterations, and in a region once per B-tree page
  it enters. A stopped run goes back to SQLite, which reports it.
- **Corrupt index pages passed the fast end test (§7e).** It read cells without checking their offsets, so qc returned
  rows where SQLite reports corruption.
  - Cells are now checked against the page's cell content area: btreeCellSizeCheck's bounds, with the usable size, not
    the page end.
  - The generic path compares exactly as vdbe.c's `sqlite3VdbeIdxKeyCompare` does (payload size check, then
    `RecordCompareWithSkip`), so it hands back on what SQLite reports.
- **`CAST(zeroblob(n) AS BLOB)` gave 0 bytes.** qvm's Cast didn't expand the zeroblob first, as vdbe.c's does.
- **A Blob opcode without data** gave a zero-length blob with a NULL pointer, where vdbe.c gives NULL.
- **Undefined behaviour in 48-bit integer decoding** (a signed shift overflow, found by UBSan; the results were right in
  practice) in two decoders.

**Also in this round** (found by the session integrating qc into Gitea):
- **Shared cache:** qvm took no table lock for `OP_TableLock`, so under `cache=shared` it could read another connection's
  uncommitted data. It now takes the lock vdbe.c takes, unless `read_uncommitted` is on, and hands back on a conflict.
- **Locks:** `sqlite3_qc` and `sqlite3_qc_exec` now hold the connection mutex and the B-tree locks, as `sqlite3_step`
  does. qc's own run state is still per process: one thread at a time.
- **The hook** had skipped every statement with a built-in aggregate as non-deterministic, because those carry no
  SQLITE_FUNC_CONSTANT. With them included (the figures above and in §9 are with them), the TCL selection compares
  253,247 statements over 2.93M rows, with 0 differences.

**What the fixes cost** (Xeon, perf stat per execution, qvm alone, against a949f16, exp253–262):
- feed: +9.6 % instructions and +7 % cycles. Of that, the cell bounds are ~10k instructions per execution and the
  interrupt checks ~5k. About 30k more go to the per-page bounds cache's upkeep and the fast path's extra branches.
- The index lookups: +1–3 %.
- feed is still 28 % faster than the interpreter (exp262).
- Tried and dropped: putting the cell compare out of line (+14 % instructions, exp261).

## 11. qvm on DOOMQL: in-line fast paths, one pin per page, cursor layout (2026-10-26)

Two DOOMQL frame queries on SQLite (explore/doomql-jit in cursed-http):
- Peter Gostev's, 7,491 opcodes;
- Lukas Vogel's (cedardb/DOOMQL, ported), 94,856 opcodes, 581 cursors.

Both are float-heavy: short REAL records written to sorters and materialized CTEs and read back, arithmetic, compares
and min/max/floor/abs/cos. Before this round, qvm was 15 % slower than the interpreter on Peter's query. On Lukas's,
every frame from 38 to 47 fell back.

**Xeon, median ms per frame, frame checksums identical to the interpreter in every run** (exp270–275, 279):

| | interpreter | qvm before (0e7c019) | **qvm now** |
|---|---:|---:|---:|
| Peter's DOOMQL, 100 frames | 47.8 | 57.4 | **45.9 (−4 %)** |
| DOOMQL frames 0–19 | 854 | 802 | **581 (−32 %)** |
| DOOMQL frames 38–44 | 726 | 1,543 (every frame falls back) | **480 (−34 %)** |
| DOOMQL frames 150–159 | 115 | 120 | **95 (−17 %)** |

On Peter's query qvm now runs 2.8 % fewer instructions than the interpreter. Before this round it ran 22 % more.

**What changed** (each change reproduces the interpreter exactly; the profile is exp269's perf record):
- **Arithmetic and compares in line.** Add, Subtract, Multiply, Divide and Remainder on plain integers, and Add to
  Divide on plain integers and reals, now run in qv_run. So do Eq to Ge on two numbers, in sqlite3MemCompare's
  order. Overflow, NaN, division by zero and anything with text go to the old out-of-line handlers. qv_arith had been
  10 % of qvm's cycles, and qv_compare_op 3 %.
- **Column.** A repeated read of an unchanged row (pseudo, vector, sorter or B-tree) no longer calls qv_row. A
  record's double is read with one byte swap (qv_real had been 3 %, out of line). MakeRecord counts one-byte varint
  lengths in line and stores doubles with a byte swap.
- **Built-in functions in line on numbers:** min()/max() with two or more arguments, abs(), and ceil(), floor() and
  the one-argument math functions (cos, sin and the rest), when every argument is a plain integer, a plain real or
  NULL. This is about 1 % by itself (exp270).
- **Register writes:** one byte per register now says whether it is a native count or sum accumulator, instead of two
  tests on every write. BitAnd, BitOr and the shifts read plain integers directly.
- **Cursor layout.** OP_Column's first touch of a cursor was the top line in qv_run, at 11 %. That is a cache miss
  on QvCur, with 360–581 cursors here.
  - What Column and the region nodes read now comes first: state, B-tree cursor, row, header arrays.
  - QvCur is 256 bytes, and the cursor array is 64-byte aligned, so that block is one cache line per cursor.
  - An intermediate layout without the alignment, with the B-tree cursor outside the first line, cost the feed 3 %
    cycles at lower IPC (exp277, 278). The aligned one doesn't.
- **One pin per page.** A text or blob value that points into a database page pins that page until the run ends.
  qvm used to skip only a repeat of the last page pinned. The ray march alternates between a few pages, so a long
  frame reached the 65,536-pin limit and fell back. Past eight pins there is now a hash set of pinned pages, so each
  page is pinned once. `-DQV_MAXPINS=N` overrides the limit (README, Build).
- **Vector tables** keep a list of their cursors: the owner and up to seven OpenDups. Each insert and delete into a
  materialized or recursive CTE used to scan every cursor of the program to invalidate cached rows (581 here, about
  1.4M times a frame). The list, and the vecstale patch it is based on, are from the doomql-jit session.

**Everything else** (exp276, 280, qvm alone, perf stat per execution against 0e7c019):

| query | instructions | cycles |
|---|---:|---:|
| recursive cte, walk | −10.2 % | −8.3 % |
| arithmetic | −4.4 % | −3.2 % |
| group by index | −2.4 % | −3.8 % |
| the other six | −1.5 to +0.6 % | −2.4 to +1.5 % |
| feed (4 alternated runs each) | −0.8 % | **+0.7 %** |

feed is the one small loss. Under qvm alone it uses 0.7 % more cycles with fewer instructions; the four runs of each
build don't overlap. The server's feed runs through qc's specialised plan (§1–§5), not qvm, so it's unaffected.

**Not changed:** Turso's Doom VDBE program (explore/doom-jit) is straight-line integer code and user-function calls,
with no records. qvm stays about 20 % behind the interpreter there (16.1–16.5 frames/s against 16.0–16.2 before;
exp275).

**Checks** (Docker on the M5, 4 cores; plans first and `QC_VM_ONLY=1`):
- sqllogictest: 11.88M tests, 0 errors, 0 differences.
- TCL suite: 253,421 statements compared, 0 differences.
- fuzz corpora under ASan/UBSan: 0 differences, no sanitizer reports.
- corpus 61/61 and qtest OK.

## 12. qvm on Turso's Doom VDBE program, native and in WebAssembly (2026-10-26)

Turso's Doom VDBE program comes from explore/doom-jit and explore/doom-wasm in cursed-http. It is 538k opcodes of
straight-line integer code plus user-function calls (get_byte, set_byte, blob_read, blob_write), with no cursors,
running as one statement that never ends.

**Natively** (Xeon, all 243 frames, frames identical to Turso's hashes; exp281, 284, 285, 295):

| | frames/s | vs interpreter |
|---|---:|---:|
| interpreter | 20.08 | |
| qvm before (6334ad8) | 16.77 | −16 % |
| **qvm now** | **20.02** | **level** |

What closed the gap:
- **Ordinary function calls in line.** The first call at a call site decides whether its function is one of the
  built-ins that qvm runs in line: min/max, abs, ceil/floor, the one-argument math functions, length. If it isn't,
  later calls go straight to xSFunc through the context built for that opcode.
  - qv_function had been 17.6 % of qvm's samples, and a third of that was its own prologue and epilogue. Its frame
    was large because the in-line built-ins were compiled into it.
- **Integer overflow checks** in qvm's in-line arithmetic now use the compiler builtins. Under clang the amalgamation
  uses its portable sqlite3MulInt64, which divides.
- **Tried and dropped natively:**
  - Handing the feedback loop over to the plain loop partway through one long execution: about 1 %.
  - Keeping qv_run's `pc` out of memory.
  - Each changed clang's register allocation for the whole loop and added 2–7 % instructions on other queries
    (exp286–294). Both exist only in the wasm build now.

**In WebAssembly** (Chrome 155 headless, M5, doom-wasm's bench: frames 50–299, median of the rounds, frames
identical to Turso's):

| | frames/s | vs interpreter |
|---|---:|---:|
| interpreter (stock sqlite3.wasm) | 36.9–38.5 | |
| qvm before, as built | 16.8 | 0.44× |
| **qvm now** (threaded dispatch, the default) | **33.1** | **0.90×** |
| qvm now, `-DQV_NO_THREADED` | 35.6 | 0.96× |

- **The cause was V8's tiering.** V8 runs a wasm function first in its baseline compiler (Liftoff) and switches to
  the optimised code (TurboFan) only on the next call. There is no on-stack replacement.
  - qvm runs an execution inside one qv_run call, and this execution never ends, so it never got the optimised code.
    Under Node it ran at 21 frames/s, against 33 with `--no-liftoff`.
  - The interpreter returns from sqlite3_step at every row, so it is re-entered.
  - In wasm, qv_run now returns every 2^20 jumps and qv_exec calls it again from where it stopped (`QV_REENTER_OPS`).
  - The fast paths above count too: under Node, before the re-entry, they took qvm from 19 to 23 frames/s.
- **Dispatch.** doom-wasm had measured switch dispatch 17 % faster, but that was in Liftoff's code.
  - With TurboFan it is 7 % faster on Doom in Chrome, and a tie under Node.
  - With qvm alone it is 2.7 % slower over the corpus by geometric mean, because the switch has no regions: scans
    lose 10–28 %.
  - Threaded dispatch stays the default; `-DQV_NO_THREADED` is the choice for programs like this one.

**Everywhere else** (Xeon, qvm alone, perf stat per execution against 6334ad8, exp294, 296):
- The corpus is flat or better: arithmetic −4 % instructions, window sum −0.8 %, recursive CTE −0.6 %, feed level.
- Peter Gostev's DOOMQL: 43.9 ms per frame, against the interpreter's 47.0.
- DOOMQL frames 0–11: 450 ms against 730.

**Checks:**
- sqllogictest, both modes, plus a native vm pass built to re-enter every 29 jumps.
- The TCL suite and the fuzz corpora under ASan/UBSan, both modes.
- 0 differences and no sanitizer reports.
- The corpus and qtest with the hand-over and re-entry forced every 29–37 jumps, both dispatch modes.
- wasm/run-tests.sh (corpus both modes, qtest, the JS API): all pass.

## 13. Plan caps, transaction ends, and a code-alignment trap (2026-10-26)

**Plan caps.** gitea-jit put a statement cache under go-sqlite3, so Gitea's handles are reused and keep their plans.
One test package then hit qc's fixed limit of 64 live plans per tier: 986 statements were refused with "plans".
- **The cap** is now `-DQC_MAXPLANS=N`, default 1024.
- **Transaction ends:** each tier used to walk all its plans at every transaction end. Now it walks only the plans
  used in that transaction; a plan joins that list when its schema check passes.
- **Finalize:** a plan leaves both lists in O(1), using its slot index.
- **Tests:** sqllogictest, with a cap of 3 and at the default, the TCL suite and the fuzz corpora, both modes:
  0 differences, no leaks or sanitizer reports.
- **Speed:** level on the corpus, plans first (Xeon, exp307). feed was 48.4k / 50.2k cycles per execution against
  48.1k / 48.8k before, at the same instructions.

**The trap** (exp297–303). The first version made feed 17–18 % slower in cycles at identical instructions. The data
counters (L1d misses, branch misses, store forwarding, 4K aliasing, memory-ordering clears) didn't move, and the
time was inside `qc_counts`, which the change didn't touch.
- **Cause:** code alignment. The Xeon is Cascade Lake, which has the JCC-erratum microcode: a jump that crosses or
  ends on a 32-byte boundary runs from the legacy decoders, not the uop cache. Code added earlier in qc.c had moved
  `qc_counts`' loop branch onto a boundary.
- **Fix:** `qc_counts` and `qc_seek_batch` now start on a 64-byte boundary (`QC_HOT`).
- **The alternative:** building with clang's `-mbranches-within-32B-boundaries` also makes the build insensitive. It
  adds about 6 % instructions of padding, but cycles don't change (48.4–49.1k on feed, old and new alike).
- **Lesson:** any change can move hot loops on the scored box. A cycles regression with the same instruction count
  is the sign to check.

## 14. The plan cache across prepares (2026-10-26)

ORMs such as Gitea's (Go's database/sql with xorm) prepare, run and finalize every statement. So every execution
paid a lift plus a plan's first run, which made one-shot statements slower through qc than through the interpreter
(gitea-jit: +9.8 % in total over Gitea's pages).

**What it does:**
- **Detach:** when a statement is finalized, its general or qvm plan goes into a cache keyed by its connection and SQL
  text, with a signature of the program it was lifted from.
- **The signature:** every opcode and operand. P4 is taken by value (text, blobs, KeyInfo, Mem values, integer arrays,
  subroutine signatures) or by the connection-owned object it names (FuncDef, CollSeq). Programs with other P4 kinds
  aren't cached.
- **Reuse:** the next prepare of the same text on the same connection gets the plan back if its program has the same
  signature and the schema generation is unchanged. Otherwise the entry is dropped and the program lifted afresh.
- **No pointers into the statement:**
  - General plans copy their text constants and take references on their KeyInfos.
  - qvm plans close their B-tree cursors and kept ephemeral tables on the way in, because those hold KeyInfos.
  - On the way out, qvm's region nodes and function contexts are pointed at the new program.
- **Not cached:** the specialised (feed-shaped) plans, which lift in about 0.2 µs.
- **Bounds:** 256 entries by default (`QC_CACHE_PLANS`), least recently used out, purged by a new hook when the
  connection closes. One thread at a time, as the rest of qc.

**One-shot statements** (Xeon, µs per prepare + lift + run + finalize, against the interpreter doing prepare + step +
finalize, exp319):

| query | QPSG | before | **with the cache** |
|---|---|---:|---:|
| index eq, all rows | off | +53 % | **+7 %** |
| count by index eq | off | +32 % | **−4 %** |
| group by index | off | −11 % | **−21 %** |
| left join, coalesce | off | +101 % | +68 % |
| left join, coalesce | on | +44 % | **+9 %** |
| join 1-n via index | on | +3 % | **−10 %** |
| feed (specialised plan, not cached) | off | −67 % | −65 % |

**The LEFT JOINs depend on a bound value.** SQLite's planner looked at a bound value, so the statement's `expmask` is
set and qc re-prepares it under QPSG at every lift: a full second prepare.
- The cache can't save that, because the fresh program isn't the one the plan came from.
- With `SQLITE_DBCONFIG_ENABLE_QPSG` on the connection there's no re-prepare.
- qc wants plans that ignore bound values anyway: results never depend on them.

**Reused statements** are unchanged: identical instructions on every corpus query, plans first and qvm alone, with
feed's cycles within 1 % (exp320).

**Checks:**
- `tests/qcache.c` (`make qcache`) runs random prepare → qc → finalize cycles over 18 statement shapes. Between
  them it changes things at random: ADD COLUMN and CREATE/DROP INDEX from this connection and a second one,
  ANALYZE, data changes, a user function and a collation redefined, the connection closed and reopened, and two live
  handles of one text.
- Every result is compared with the interpreter: 0 differences under ASan/UBSan, both modes.
- With no changes, every re-prepare hits the cache. With changes, roughly 15k hits and 2k misses per 20k steps.
- The first version missed on statements with string constants. qvm's lift rewrites String8 into String, as vdbe.c
  does on a first run. The signature now records the rewritten form, and attach applies the rewrite to the new
  program.
- sqllogictest, both modes, plus a pass with a 4-entry cache that evicts constantly; the TCL suite and the fuzz
  corpora: 0 differences, no leaks.

## 15. Gitea's big queries: copies past a pin budget, adaptive Bloom filters, lazier row decoding (2026-10-26)

gitea-jit captured Gitea's slowest statements, with their bindings, and replays them hot against a seeded Gitea
database: 39 statements, one read transaction, the median of 5 blocks each. These are the statements qc should win
on. Before this change, qc lost on them:
- the activity feed's top-N sort ran at 1.6× the interpreter's time;
- the `LOWER(…) LIKE` scans over issues and the `IN (subquery)` counts ran at 1.15–1.35×;
- a `count(*)` over issues fell back to the interpreter every time.

**What changed:**
- **A pin budget (`QV_PIN_CHEAP`, 128 pages).** qvm pins each page a text or blob value points into, until the
  execution ends. A scan over tens of thousands of rows pinned every page it read, so most of its time went to pins
  and to unpinning at the end. Past the budget, a value is copied into its register, as vdbe.c copies it.
- **Bloom filters.** OP_FilterAdd and OP_Filter run as vdbe.c runs them, where they used to end a loop region. A
  data-less OP_Blob now makes a zeroblob of P1 bytes, as in vdbe.c; qvm had made it NULL.
  - **Adaptive:** a filter that probed 1024 times in one run and rejected nothing is skipped in the next runs, and
    so is its FilterAdd once no filter reads its register. Every 16th run checks them all again.
  - **Why between runs:** a first rule that decided within a run, after 256 probes, switched off a filter whose
    rejections came late in the scan.
- **Lazier row decoding in loop regions.** A region used to parse each row's header through the last column it
  reads. Now it parses up to the first branch that skips the row (the WHERE term, the OFFSET) and the rest only when
  a later Column needs it.
- **Demotion.** A general plan that fails a run (`g rows`, `g run`) now demotes the statement to qvm, which re-lifts
  it. It used to fall back to the interpreter; this was the `count(*)`.

**Gitea's 39 statements** (Xeon, total ms over one execution of each, exp336):

| build | run by qc | interpreter | qc | qc / interpreter | median per statement | faster / slower |
|---|---:|---:|---:|---:|---:|---|
| before (f6bba18) | 38 / 39 | 261.5 | 337.2 | 1.29 | 1.07 | 14 / 23 |
| **after** | **39 / 39** | 272.5 | 290.2 | **1.065** | **1.02** | 17 / 22 |

- **The activity feed's top-N sort** went from 1.60× to 1.15×. It is still the largest gap: 10.5 ms of the 17.7 ms
  left.
- **The best statement** is one issue/repository select at 0.83×.
- **Apple M5 Pro**, the five worst shapes alone: the top-N sort at 1.07× (from 1.83×), the LIKE scans at 1.03×,
  the IN-subquery count at 1.08×, the `count(*)` at 1.01× (from falling back), and the 64-row OFFSET page at
  1.10× (from 3.99×).
- 0 row differences.

So qc now runs Gitea's big statements at about parity, but doesn't yet win on them.
- **Where the time goes:** in the top-N sort, both sides spend most of it in the B-tree (the table seek per index
  entry, inserts into and deletes from the sorter) and in `pread`. The database is larger than the page cache.
- **The one qc-only cost** in the profile is `qv_make_record`, the record for each sorter insert.

**DOOMQL (exp333):** Peter's frame runs in 41.6 ms against 42.1 ms before this change and 45.6 ms in the
interpreter. Lukas's frame runs in 436 ms against the interpreter's 695 ms. Instructions changed by +0.09 %.

**The corpus** (Xeon, user-mode perf counters per execution, both builds with `-mbranches-within-32B-boundaries`,
exp334/335):
- **Plans first,** the server's mode: instructions within 0.5 % on every query.
- **qvm alone:**
  - group by index: +1.2 % instructions and +0.5 % cycles. Always-on Bloom filters had cost +6.5 % here, and the
    adaptive ones +2.6 % before the header-parse split.
  - feed: −0.3 % instructions.

**Checks:** sqllogictest in both modes plus a pass with `QV_PIN_CHEAP=0` (copy always), the TCL suite, the fuzz
corpora under ASan/UBSan, and `qcache`: 0 differences.

## 16. A top-N sorter for qvm: Gitea's big queries won (2026-10-27)

After §15, Gitea's activity-feed top-N was the largest remaining loss, at 1.15× the interpreter's time:
`… WHERE user_id = ? AND is_deleted = ? ORDER BY created_unix DESC LIMIT 20`.
- **How SQLite runs it:** an ephemeral index of at most 20 entries. For each row: Last, an IdxLE against the last
  entry, Delete, MakeRecord, IdxInsert.
- **Why that's expensive here:** `created_unix` grows with the rowid, so every one of the 79k rows displaces an entry.
  In both the interpreter and qvm, most of the time went to B-tree inserts and deletes on the 20-entry tree
  (`freeSpace`, `pageFindSlot`, `sqlite3BtreeInsert`, `sqlite3BtreeDelete`).

**What changed:**
- **The cursor kind (`QVC_TOPN`):** an ephemeral index whose cursor sees only what a top-N sorter does becomes a
  sorted array of records in the execution's arena. "What a top-N sorter does" means the lifter checks that the
  program has at least one Last on it, and otherwise only these opcodes: OpenEphemeral, IdxInsert, Last, Delete,
  IdxLE/LT/GE/GT, Sort/Rewind, Next/Prev, Column, Sequence, NullRow, ResetSorter and Close.
- **IdxInsert** is a binary search with the comparator a B-tree seek would use (`sqlite3VdbeFindCompare`). A
  descending top-N's new row is checked against the first entry before the search. An equal key replaces the entry,
  as in a B-tree.
- **Last and Delete** are an index and a memmove of at most N pointers.
- **The Idx compares** compare the entry's record directly.
- **Past `QV_TOPN_MAX` entries (256),** for a large LIMIT, the array moves into an ephemeral B-tree, as SQLite would
  have used, and the run carries on there. Later runs of the plan open that kept B-tree directly. Nothing falls back.
- **`QV_NOTOPN=1`** turns it off for A/B runs.

**Gitea's 39 statements** (Xeon, total ms, exp338):

| build | interpreter | qc | qc / interpreter |
|---|---:|---:|---:|
| da4c75d | 255.2 | 268.2 | 1.051 |
| **top-N sorter** | 256.2 | 244.3 | **0.954** |

- **The activity feed** went from 1.10× to **0.86×** (−10 ms per run). It was the largest loss and is now the
  largest win.
- **The issue lists** (`ORDER BY created_unix DESC, id DESC LIMIT 20 / 50 / 1`) went from 1.13–1.14× to
  0.85–0.96×. The `IN (…)` top-N queries went from 1.04–1.08× to 0.87–0.94×.
- **On the M5 Pro** the feed runs at 0.79× and all 39 at 0.96–0.97×. There are 0 row differences.
- **Still losing:** the `count(*) FROM issue INNER JOIN repository WHERE repo_id = ? …` counts, at 1.13–1.17×
  (about 0.7 ms in all). They run as loop plans (kind 2), and qvm runs them at 1.02–1.04×.
  - **Not the cause:** I/O. With the whole database cached, the gap stays at 1.18× (exp350). Pinning loop-plan pages
    only for text values changed nothing (exp343/344), and was dropped.
  - **The cause:** the loop plan's generic row evaluation (`qg_rowval`, `qc_decode`, `qg_fetch`). It runs 25 % more
    user-mode instructions than `sqlite3VdbeExec` on this shape.

**The corpus** (Xeon, perf counters per execution, exp337/344, both builds with `-mbranches-within-32B-boundaries`):
- **qvm alone:** order by top-n is −11 to −13 % instructions and −6 to −10 % cycles; ties (top-n) is −10 %
  instructions.
- **Everything else** is within ±0.6 % instructions, both modes.

**Checks:**
- **`tests/topn.c` (`make topn`)** runs random `ORDER BY … LIMIT [OFFSET]` queries over NULLs, integers, reals and
  text, both modes. It covers ASC/DESC, NULLS FIRST/LAST, NOCASE, ties, expressions and GROUP BY, with LIMITs past
  the array's size.
  - Each statement runs three times.
  - Also built with a 4-entry array, which moves into a B-tree on almost every run.
  - Under ASan/UBSan: 0 differences.
- **The suites:** sqllogictest (both modes and copy-always), TCL, the fuzz corpora, qcache and `make regress`: 0
  differences. x86-64 gcc (emulated) runs qtest, the corpus, regress and topn, both modes: 0 differences.
- **A bug found on the way:** TCL's `collate1` OOM test caught the lifter reading the hash-set array before the
  lift's allocation check. Under an injected malloc failure it was NULL. Fixed.

**Two wrong results in earlier commits, fixed here.** Each is now a case in `tests/regress.c` (`make regress`):
- **gcc on x86-64 only** (found by spec-policy-study's replay, exp357):
  - **Where:** qvm's integer fast path for IdxLE/GT/LT/GE, against an ascending integer index.
  - **The bug:** it passed the cell's key to the comparison in the same argument list as the call that decodes it,
    `qc_idx_cmp_kind(qc_idxkey_at(…, &v), v, key)`. C leaves argument evaluation order unspecified, and gcc on x86-64
    reads `v` first, so it compared the previous cell's key. A range scan then ran past its end: Gitea's comment
    query returned 6,576 rows instead of 4.
  - **Why it hid:** clang, and gcc on arm64, evaluate left to right. No flag, -O level or sanitizer changes it,
    because it isn't undefined behaviour.
  - **Fix:** two statements. All of qc was checked for the same pattern; there was no other instance.
- **Loop plans (kind 2), any compiler** (found by SQLancer's TLP oracle in turbo-bench):
  - **The bug:** a blob passed to a built-in function had a Mem encoding of 0, so `unicode()`, `upper()`, `ltrim()`
    and the like read its bytes as UTF-16.
  - **Fix:** every value from `qg_mem` is now UTF-8, as qvm's already were.
- **A crash with memory-mapped I/O, every tier** (SQLancer's PQS oracle, turbo-bench):
  - **The bug:** with `PRAGMA mmap_size` above 0 on a file database, qc segfaulted on the first statement that read a
    page. Pinning a page calls `sqlite3PagerRef`, but a memory-mapped page has no page-cache entry to count the
    reference on.
  - **Fix:** qvm now copies text and blobs out of a memory-mapped page (as past `QV_PIN_CHEAP`) instead of pinning
    it. The specialised and loop plans, whose batched seeks and lanes also add page references, hand such
    statements to qvm.
  - **Why it hid:** sqllogictest and the TCL suite run without mmap.

**Which compilers the earlier results cover:** this repo's own results, before this section, were measured with
clang, on the Xeon and on macOS. The suites ran with gcc on arm64 Linux. x86-64 gcc wasn't tested at all, and every
build of the integer fast path got the bug above. The suites now include an x86-64 gcc pass (emulated) of qtest,
the corpus, regress and topn, both modes.
## 17. Counters, numeric Columns in regions, and a measured tier choice (2026-10-27)

From cursed-http's `explore/spec-policy-study` (how other systems decide what to specialise on and when to stop;
the full results are in its REPORT.md §8).

**Counters (`QC_STATS=1`).** Printed at exit or by `sqlite3_qc_stats()`:
- executions by tier;
- fallbacks and failed lifts by reason;
- the type-feedback masks of Column and comparison opcodes;
- region nodes widened, plan cache hits;
- the tier choice's samples and parks.

Off, they cost one test per execution. What they showed:
- No deopt and no fallback on Gitea's 39 statements, DOOMQL or the corpus, so there was no case for more failure
  memory.
- Gitea's columns are `{int}` or `{text}`.
- Peter Gostev's DOOMQL has 716 `{real}` Column sites, which regions ran through the generic Column.

**Numeric Columns.** A region's speculated Column now also takes serial types 7 (real; NaN reads as NULL) and 0
(NULL), after the integer cases. It is chosen when the feedback is numbers and NULL.
- **Xeon** (exp346, exp380; frames equal to stock): Peter's frame 42.6 → 41.3–41.4 ms (−2.8 %), Lukas Vogel's
  515 → 503–509 ms.
- **Corpus:** instructions unchanged (exp399). `QV_NUMCOL=int` gives the old choice.

**Measured tier choice (`qc_adapt`, `QC_NOADAPT=1` to turn off).** A general or qvm plan run with a row callback is
timed after 3 executions.
- **Fast plans:** under 50 µs, it is kept and timed again 256 executions later.
- **Slow plans:** 4 timed plan runs alternate with 4 interpreter runs. qc steps the statement with `sqlite3Step` and
  hands the interpreter's rows to the callback.
- **Early keep:** two interpreter runs over 1.25 × the slowest plan run end it.
- **Park:** if the interpreter's median is more than 5 % faster, with every interpreter run under the plan's median,
  `sqlite3_qc_exec` returns QC_FALLBACK ("parked") for 64 × 2^R executions; after 10 parks it stays parked.
- **Re-measure:** kept plans are measured again after 256 × 2^K executions.
- **Persistence:** the state survives the plan cache.

Results:
- **Gitea's 39 statements hot (Xeon, clang, exp357):** 1.055 → 1.046× the interpreter. Nine statements at
  1.10–1.18× were parked and now run at parity. The largest ones, at 1.03–1.10×, mostly weren't.
- **Cost:** the sampled interpreter runs. On a statement qc wins by a lot, that's the gap per sample: Lukas Vogel's
  DOOMQL in a 13-frame window is +10 % (2 samples), and over long runs it amortises.
- **Corpus:** +0.1 to +0.8 % instructions (exp399).

**Checks**, with sampling forced on every plan (`-DQC_ADAPT_MIN_US=0 -DQC_ADAPT_WARM=0`):
- corpus, both modes, under ASan/UBSan: 0 mismatches;
- qtest: OK;
- `qcache` under ASan: 0 differences (8,246 samples, 136 parks);
- a sqllogictest subset (2.83M tests): 0 differences, no leaks.

The default build passes corpus, qtest and `qcache`.

**Found along the way:** the measurements for this section found the gcc-only wrong result that §16 fixed (exp342,
exp357). With the tier choice on, that run looked healthy, because the statements whose qc time had blown up were
parked. Run timing comparisons with `QC_NOADAPT=1` and `QC_STATS=1`, and read the park count.
