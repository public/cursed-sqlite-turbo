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
