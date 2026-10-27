# A Lean model of the semantics turbo specialises

A pilot (2026-10-27) of AWS Cedar's verification-guided development applied to turbo. It has three parts: a small
Lean 4 model of the SQLite semantics turbo's fast paths rely on, proofs that those fast paths as written agree with the
model, and the model used as a differential test oracle against SQLite and turbo.

The bugs found in turbo so far were C-level (argument evaluation order, a blob read as UTF-16, locking, mmap, OOM),
and a model can't catch those. What the model adds is a proof that the *rules* the fast paths assume are right, plus an
oracle that is independent of both SQLite and turbo.

**Result:** every proof closes. On valid data, no wrong result was found. On corrupt data there is one robustness bug:
qc's table-record decoders accept records SQLite reports as corrupt, so qc plans return rows where SQLite returns
SQLITE_CORRUPT (finding 6). It was found by modelling OP_Column, and the model proves the fix sound. The pilot also
found:
- one comment that contradicts its code, one non-monotone policy choice, and two benign counter wraps;
- one SQLite NOCASE quirk that a future fast path must copy;
- an index-vs-scan inconsistency in SQLite's LIKE optimisation on invalid UTF-8, which makes qc and the interpreter
  disagree on bound LIKE patterns;
- that qc never lifts a LIKE statement under `PRAGMA case_sensitive_like`.

It also proved two things correct before they are written or changed:
- the planned sort-key prefix, including the exact ties that need the full compare;
- SQLite's `patternCompare`, including its early-exit optimisation.

## Running it

```
cd lean && lake build          # the model, the proofs, the oracle (12 s clean on an M-series Mac)
make lean-oracle               # oracle cases -> build/lean-cases.txt, then tests/lean_oracle.c, as is and QC_VM_ONLY=1
make lean-oracle SEED=7 N=50000 TABLES=400 RECORDS=10000 LIKES=1000
```

`make lean-oracle` fails on any disagreement except the two known ones, which it reports: finding 6 (set
`LEAN_ORACLE_STRICT=1` to fail on it once fixed) and the LIKE range on invalid UTF-8 (finding 7). `LEAN_WHY=1` prints
why qc fell back.

- **Toolchain:** Lean is pinned to `leanprover/lean4:v4.34.1` (`lean/lean-toolchain`). Install it with elan (`brew
  install elan-init`).
- **Dependencies:** core Lean only, no Mathlib. Core's `Rat` with its floor and ceiling lemmas, plus `grind`'s
  linear arithmetic over ordered fields, was enough.
- **Checks:** `#print axioms` on the main theorems shows only `propext`, `Classical.choice` and `Quot.sound`. There is
  no `sorry` anywhere.

| file | what |
|---|---|
| `lean/Turbo/Value.lean` | values, doubles by exact value, the documented order (`order`), `sqlite3MemCompare` and `sqlite3IntFloatCompare` as C writes them, BINARY, NOCASE |
| `lean/Turbo/Compare.lean` | the two C functions equal the documented order |
| `lean/Turbo/FastPaths.lean` | turbo's comparison fast paths, each modelled as written, proved equal to the order or to the opcode |
| `lean/Turbo/SortKey.lean` | the planned 64-bit sort-key prefix and its proofs |
| `lean/Turbo/Policy.lean` | type-feedback masks, region widening, `qc_adapt`'s parking and backoff |
| `lean/Turbo/Affinity.lean` | type affinity: numeric text, storage, read-back, comparison affinity (executable, two theorems) |
| `lean/Turbo/Record.lean` | the record format: OP_Column's header walk and corruption test, `qc_decode` as written and fixed |
| `lean/Turbo/Like.lean` | LIKE/ESCAPE: `patternCompare` as written against the pattern's meaning; the LIKE optimisation's range |
| `lean/Oracle.lean` | the oracle executable |
| `tests/lean_oracle.c` | runs the oracle's cases through SQLite and turbo |

## What the proofs assume (the trusted base)

- **Doubles** are modelled by their exact value: -∞, +∞ or a rational. C's `<` and `==` on two non-NaN doubles are
  exact comparisons, and -0.0 == +0.0. NaN isn't a value, because SQLite never holds one (`sqlite3VdbeMemSetDouble`
  and `sqlite3VdbeSerialGet` turn it into NULL, and so do qc's decoders).
- **Facts about binary64** are hypotheses rather than a bit-level model (`Fmt` in `Value.lean`):
  - a double of magnitude at least 2^53 is an integer;
  - `(double)i` is exact for any integer the format represents, in every rounding mode: every |i| ≤ 2^53, and every
    integer that is a double.

  `Fmt.toy` shows the hypotheses are consistent.
- **Registers have one type each.** There are no `MEM_Int|MEM_Str` registers; qvm's `QV_NUM` checks select exactly
  the single-type cases. Text is UTF-8, with no zeroblobs.
- **The C is transcribed by hand.** Nothing is extracted from the C. The oracle covers the gap between the C and its
  transcription: it runs the real functions on the model's cases.

## What is proved

**SQLite's rules** (`Compare.lean`):

- `intFloatCompare_exact`: `sqlite3IntFloatCompare` returns the sign of the exact comparison i − r. The algorithm is
  range checks, truncation `(i64)r`, then `(double)i` against r. The result holds for every int64 and non-NaN double,
  in every rounding mode, including beyond 2^53 where `(double)i` rounds and at ±2^63.
- `memCompare_spec`: `sqlite3MemCompare` (flag-structured as in C) is the documented order. That order is NULL, then
  numbers by exact value, then TEXT by collation, then BLOB by `memcmp` and length.
- `memcmpLen_eq_lex`: `binCollFunc`/`sqlite3BlobCompare` (`memcmp` over the shorter length, then the length
  difference) is the lexicographic order.

**turbo's fast paths** (`FastPaths.lean`, at c3ebcb0), each equal to the order on the preconditions its builder
checks:

| theorem | C |
|---|---|
| `qvCmp_spec` | `qv_cmp`: two integers and BINARY text in line, else `sqlite3MemCompare` |
| `qvNumcmp_spec` | `qv_numcmp` (plain integers and reals; also `minmaxFunc` in line) |
| `qvCompareOp_spec`, `rgCmpi_spec`, `tables_ok` | `qv_compare_op` and `rg_cmpi` decide OP_Eq…OP_Ge as `vdbe.c` does: no affinity applies to two numbers. vdbe's aLTb/aEQb/aGTb tables mean what the opcodes say |
| `qgCmpJump_spec` | `qg_cmp_jump` (qcg filters): whenever it doesn't fall back, its jump is the opcode's |
| `flip_same`, `field_step`, `keyCmp_spec` | `qv_keycmp`/`qg_sort_cmp` (vdbeRecordCompare's DESC/BIGNULL rule) and `qv_cmpvec` (OP_Compare's) are the same rule, and give ORDER BY with NULLS FIRST/LAST |
| `idxCmp_spec` (`idxKey_int`, `idxKey_frac`) | `qc_idxkey_at`'s first field plus `qc_idx_cmp_kind`, i.e. the integer index probe in qc and `qv_idxcmp`. It orders a cell's field as SQLite does against an integer key: NULL, an integral real equal to its integer, a non-integral real by its floor, reals beyond int64 at the ends, text and blobs last |
| `idxJump_spec` | the `default_rc`/parity/`res++` encoding of OP_IdxLE/GT/LT/GE, with SQLite 3.54.1's opcode numbers |
| `qgOrder_spec`, `qgAggCmp_spec` | `qg_order` (qcg's sort) and `qg_aggstep`'s min/max compare |
| `hk_eq_iff` | the hash set's key (`qv_hk_mem`/`qv_hk_val`) is equal exactly when the index's comparison says equal, so DISTINCT through the hash set keeps the same rows |

**The sort-key prefix** (`SortKey.lean`), for REPORT §3.5 ("idea 5", cursed-http `explore/pg-jit-study`). The layout:

- bits 63-62: the class (NULL, number, TEXT, BLOB);
- numbers: the integer floor clamped to int64, biased, then shifted right by 2;
- TEXT and BLOB: the first 7 bytes big-endian, times 8, plus min(length, 7);
- DESC: the complement.

Theorems:

- `key_mono`, `key_lt_order`: the prefix is monotone, so a strict prefix order implies the full order.
- `prefixCmp_asc`, `prefixCmp_desc`: comparing prefixes first, and only on equal prefixes the full KeyInfo compare, is
  the same comparator as the full compare. The sort result is the same with any algorithm.
- `tie_text`, `tie_num`: equal prefixes of unequal values happen only in these cases:
  - two texts or blobs, both at least 7 bytes long, that share their first 7 bytes;
  - numbers whose clamped floors fall in the same aligned block of 4.
- `exact_mode`, `keyInt_exact`: with an all-integer first key, the biased i64 orders exactly and ties only equal
  integers, so the remaining key fields decide.
- `order_swap`: the order is antisymmetric.

Not covered: NOCASE and other collations (keep the prefix off for them), and BIGNULL on the first key (NULL would need
the top class).

**The policy** (`Policy.lean`; `qc_adapt` and `qv_fb_num` from `claude/spec-policy`, b383531):

- `observe_widens`, `widenings_bounded`: feedback only widens, so a site's mask changes at most 5 times.
- `level_mono`: the documented lattice int → int|real|null → any is monotone in the feedback.
- `widen_once`: a region node (`rg_coli` → `rg_col`, `rg_cmpi` → `rg_cmp`) is re-specialised at most once.
- `parks_bounded`: `qc_adapt` parks a plan at most 11 times.
- `learn_progress`: a learning phase times at most 8 runs. This is checked exhaustively by `decide`.
- `intervals`: re-measurement is 256–65536 executions after a keep, and 128–65536 (or never) after a park.

**Affinity** (`Affinity.lean`):

- `store_numeric_text`: a numeric column never stores text that looks like a number.
- `store_text_no_num`: a TEXT column stores no numbers.

So comparing two values of the same column needs no conversion. The conversions themselves (`textToNum`, `roundD`,
`numToText`, `storeAff`, `readAff`, `cmpWithAff`) are executable and tested against SQLite, not proved.

**The record format** (`Record.lean`):

- `qc_decode_lenient`: three minimal records `qc_decode` accepts and OP_Column reports corrupt (finding 6).
- `qcDecode_sound`: `qc_decode` with OP_Column's three missing checks (a header size whose own varint doesn't fill
  it, types ending inside the header and within 32 bits, a header read to its end whose fields end exactly at the
  payload) is sound. Whatever it accepts, OP_Column reads the same value for every requested field and doesn't report
  corruption. The supporting lemmas:
  - `walk_take`: OP_Column's lazy walk to field p is a prefix of the walk to any later field;
  - `walk_inner`: every field before the last ends inside the header;
  - `qcLoop_walk`: the fixed loop reads exactly the walk's fields;
  - `qcLoop_past`: past the header's end, the loop yields only NULLs.

**LIKE** (`Like.lean`), on characters after `sqlite3Utf8Read`, where a NUL ends both strings:

- `like_spec`: `patternCompare` as written returns SQLITE_MATCH exactly when the string matches the pattern's
  declarative meaning: `%` any characters, `_` one, an escaped character literal, ASCII-only case folding, and a
  trailing ESCAPE matching nothing. The C covered includes the `%_` run skipping, the strcspn search on both cases for
  ASCII, the character loop otherwise, and likeFunc's disabling of a wildcard that equals the ESCAPE character.
- `like_nowild`: its early exit is sound. SQLITE_NOWILDCARDMATCH is returned only when no suffix of the string
  matches, which is what lets an enclosing `%` stop searching.
- `range_ok`: a string whose bytes start with the prefix P lies in [P, incremented P) under BINARY, including the 0xBF
  carry.
- `range_overlong`: a string can match the prefix by its characters without having its bytes (finding 7).

**Open (not claimed):**

- `qv_sort`'s merge sort is stable, and equals any stable sort by the comparator.
- NOCASE is a total preorder. It is, despite the NUL rule below, but that isn't proved.
- Transitivity of `order`. None of the theorems above needs it.
- The affinity conversions are exact as SQLite computes them. The oracle checks this instead.
- `qc_decode_fast` and the generated `qc_dec_*`: they share finding 6, but only `qc_decode` is modelled. The oracle
  runs the shaped decoders end to end.
- NOCASE LIKE ranges: `range_ok` covers the case-sensitive, BINARY range.
- `sqlite3Utf8Read`'s decoding is modelled, but its agreement with byte order on valid UTF-8 isn't proved.
- GLOB (`[...]` sets).

## The oracle

`lean/Oracle.lean` generates values weighted to the edges:

- integers at ±2^53 ± 1 and near ±2^63;
- the doubles around them, ±0.0, ±∞, NaN, subnormals, and integers converted to doubles;
- case variants, text with embedded NULs, the bytes between 'Z' and 'a', and strings sharing 7-byte prefixes;
- numeric-looking text and blobs;
- records: valid ones from those values, then mutated. Mutations include a trailing byte, one byte short, the header
  size off by one or set to 0, 1 or a 2-byte varint, a type replaced, a continuation byte inserted, a type beyond 32
  bits, and any byte changed;
- LIKE: patterns made from their strings piece by piece (kept, case-swapped, `_`, `%`, escaped, dropped). The pieces
  include letters in both cases, wildcards, escapes, é/É, U+0080 both canonical and overlong, a lone continuation
  byte and NUL. ESCAPE is none, `\`, `%`, `_` or `a`, with and without case folding.

For these values it writes out what the model says SQLite does. `tests/lean_oracle.c` (`make lean-oracle`) checks
them in two parts.

**Value by value:**

- `sqlite3MemCompare`, `qv_cmp`, `qv_numcmp`, `qg_order`, `qg_cmp_jump` and `qv_compare_op` under BINARY and NOCASE;
- the integer probe `qc_idxkey_at`/`qc_idx_cmp_kind` on a cell built for each value, which also exercises the
  serial-type fast path, and SQLite's own record compare on the same cell;
- `qv_hk_eq` and `qv_hk_hash`;
- a C reference implementation of the prefix, which must match the Lean definition, with a strict prefix order
  implying `sqlite3MemCompare`'s.

**Through SQL**, on the interpreter and on qc (plan, feedback, regions), against the model. Each table comes indexed
and not indexed (sorter, index, top-N):

- columns: one of any values, one of NULL/INTEGER/TEXT (qcg's general plans), one of integers (region
  speculation), and typed columns of INTEGER, REAL, NUMERIC, TEXT and BLOB affinity;
- queries: ORDER BY ASC/DESC/NULLS LAST/NULLS FIRST, also with LIMIT; self-joins on all six comparisons; integer
  ranges through the index; `col op ?` with bound values of every type through the column's affinity; read-back
  values, type and value exact; count(DISTINCT); min/max; ORDER BY and `<` under NOCASE.

**Records:**

- `qc_decode` is checked against its model directly.
- Each record is written as the only cell of two tables' leaf pages with `sqlite_dbpage`: one table untyped, one
  with INTEGER and TEXT columns, which engages the shaped and generated decoders.
- Each table is read by four queries (all columns, one column, a rowid lookup of the last column, a rowid lookup of
  all), on the interpreter and on qc.

**LIKE:**

- `like()` per row on the interpreter.
- `s LIKE p` through SQL on the interpreter and on qc.
- One pattern, bound and as a literal, against every row of an indexed column: the LIKE optimisation's range.

**Results** at 20,000 cases and 400 tables per seed, seeds 1–6, as is and with `QC_VM_ONLY=1`; records and LIKE at
3,000 records and 400 blocks, seeds 1–3:

- about 327,000 value-level checks and 59,500 queries (177,000 qc runs) per seed and mode: **0 disagreements** among
  the model, SQLite and turbo;
- records:
  - the model of OP_Column matches the real interpreter on all 24,000 record queries per seed, corrupt records
    included, so the model of SQLite's corruption test is validated;
  - the model of `qc_decode` matches the C on every record;
  - `qc_decode` accepts about 1,300–1,400 of 3,000 records that OP_Column reports corrupt, and never returns a wrong
    value for a field SQLite reads fine;
  - end to end in default mode, qc returned rows where SQLite reports corruption 0 to 48 times per seed: most corrupt
    runs fall back, and a fallback is safe. With `QC_VM_ONLY=1` it never did;
- LIKE:
  - the model's `like()` matches SQLite's on all ~5,200 rows per seed;
  - SQL through qc and the interpreter agree with the model, except the index range on rows with invalid UTF-8
    (finding 7);
- seed 1 under ASan/UBSan, both modes, records and LIKE included: clean.

The checker is known to catch corrupted expectations: flipped signs, a swapped order, a wrong count or a wrong key
are each reported, both for SQLite and for qc.

**Coverage** (clang source coverage, both modes, seed 1):

| path | hits |
|---|---|
| `qv_compare_op` | 30.2M |
| `rg_cmpi` | 3.5M |
| `qv_numcmp` | 2.9M |
| `rg_coli` | 2.8M |
| `qv_cmp` | 2.4M |
| `qv_keycmp` | 2.2M |
| `qg_order` | 1.1M |
| `qg_sort_cmp` | 948k |
| `qg_cmp_jump` | 723k |
| `qv_idxcmp`'s integer fast path | 462k |
| `qv_cmpvec` | 197k |
| `qv_hk_eq` | 95k |
| `qg_aggstep` | 72k |

The top-N array is exercised throughout. Not reached: `qc_idx_lb`, the special plans' lanes (off by default).

Under `PRAGMA case_sensitive_like` qc lifts no LIKE statement (finding 8), so those blocks test only the interpreter.

**Lean's own model was checked too.** The typed tables compare the model's affinity rules against the interpreter as
well as against qc. That is how they were validated, including -0.0 into a TEXT column (SQLite writes "0.0") and
9007199254740993 into a REAL column (read back as 9007199254740992.0).

## Findings

Findings 1–5 and 7–8 aren't wrong results. Finding 6 is one, on corrupt databases.

1. **Comment vs code in `qc_adapt`** (spec-policy, b383531, `qc/qc.c`; `park_schedule`). The comment says the plan is
   parked "for the next 64 × 2^R executions … after 10 parks it stays parked". The code increments R before using it:
   `if (A->R < 255) A->R++; A->next = A->R > 10 ? ~0u : A->n + (64u << A->R)`. So the first park lasts 128
   executions, the 10th still has a finite end (65,536), and the plan stays parked only after the **11th** park.
   Repro: any plan the interpreter beats in every measurement parks at n+128, n+256, … and is parked for good at the
   11th decision. Fix the comment ("64 × 2^R with R counting this park"; "after 11 parks"), or test `A->R >= 10`.
2. **The speculation choice isn't monotone at the bottom** (`qv_fb_num`, spec-policy; `fbNum_not_antitone`). A Column
   whose feedback is NULL only gets the generic `RG_COL`. One that has also seen an integer gets `RG_COLI`, so more
   feedback gives more specialisation. This is harmless today: regions are built once, at the third run, and
   `rg_coli` handles serial types 0–9 itself. But a rebuild of regions from later feedback would not be one-way.
   Worth a comment, or speculate on `{NULL}` too.
3. **32-bit counters in `qc_adapt`** (benign). `~0u` ("parked for good") ends after 2^32 executions, when `n < next`
   fails. Near 2^32, `n + (64u << R)` wraps and causes an early re-measure. Both only cost a measurement.
4. **SQLite's NOCASE stops at the first NUL** (`strnicmp` in `Value.lean`, confirmed by the oracle and in SQL). For
   example, `SELECT ('a'||char(0)||'x') = ('a'||char(0)||'y') COLLATE NOCASE` gives 1, while BINARY gives 0. Bytes
   after an embedded NUL in the shorter length are never compared, then the lengths decide. turbo has no NOCASE fast
   path (qvm calls `sqlite3MemCompare`, and qcg refuses non-BINARY collations), so nothing is wrong today. Any future
   one, such as a lower-cased `memcmp`, a NOCASE hash set, or a NOCASE sort prefix, must copy this rule.
5. **The prefix design, sharpened.** REPORT §3.5 puts "the biased i64" behind class bits. That can't be lossless in
   64 bits. Here the numeric payload loses its 2 low bits, so integers tie within aligned blocks of 4 (`tie_num`),
   and exact mode drops the class bits when feedback says the key is always an integer. Also, NULLS LAST on the first
   key needs NULL mapped above BLOB, which the report doesn't mention.

6. **qc's table-record decoders accept records SQLite reports corrupt** (`qc/qc.c` `qc_decode`, `qc_decode_fast`,
   the generated `qc_dec_*`; `qc_decode_lenient`). On a corrupt database, qc's special and general plans return rows
   where SQLite returns SQLITE_CORRUPT. qvm is not affected: `qv_hdr` copies OP_Column's checks. The decoders skip two
   of OP_Column's tests:
   - When the header has been read to its end, OP_Column requires the field lengths to end exactly at the payload
     size. The decoders only check that they don't pass it (`d <= rec + sz`).
   - `qc_decode` reads type varints without bounding them by the header. It accepts a header of size 1 with a body,
     and a type varint running past the header. It also accepts a 64-bit type that `qc_stlen` truncates to 32 bits,
     where `getVarint32` would clamp it to 0xffffffff, which OP_Column reports as corrupt.

   Repro (default mode, `-DSQLITE_ENABLE_DBPAGE_VTAB`):
   ```sql
   CREATE TABLE t(a INTEGER, b INTEGER); INSERT INTO t VALUES (7, 5), (2, 6);
   ```
   Then, with `sqlite_dbpage`, patch the first record from `03 01 01 07 05` to `03 01 00 07 05` (b's type set to
   NULL). Now `SELECT a, b FROM t` gives qc rows `(7, NULL), (2, 6)`, while the interpreter says "database disk
   image is malformed".

   The fix is `qcDecode true`, proved sound by `qcDecode_sound`. For the fast and generated decoders,
   `return h < he ? d <= rec + sz : d == rec + sz` is enough.
7. **SQLite's LIKE optimisation disagrees with `like()` on invalid UTF-8** (`range_overlong`; stock SQLite 3.53/3.54).
   The range compares bytes, but `like()` compares characters after `sqlite3Utf8Read`, which accepts overlong forms
   and folds stray continuation bytes into the character before. It goes wrong in both directions:
   - With `case_sensitive_like` and an index, `x LIKE 'a\u0080%'` misses a row stored as `61 E0 82 80` (overlong
     U+0080), which `NOT INDEXED` finds.
   - A row `C3 89 80 …` is inside the range of `'É%'` but decodes to U+3240. When the pattern is a complete prefix,
     SQLite drops the LIKE term and returns the row anyway.

   This matters to turbo because qc re-prepares a statement whose plan looked at a bound LIKE pattern as QPSG, which
   doesn't use the range, so qc and the interpreter return different rows for `x LIKE ?` over such data. On valid
   UTF-8 there is no difference: the oracle fails on any.
8. **qc never lifts LIKE under `PRAGMA case_sensitive_like`** (`LEAN_WHY=1`: "Function"). The pragma re-registers
   `like()` with `sqlite3CreateFunc`, without SQLITE_FUNC_BUILTIN, and `qv_policy` lifts only built-ins and
   deterministic user functions. This costs performance and is safe. Accepting the two LIKE FuncDefs SQLite registers
   for the pragma (`likeInfoAlt`) would fix it.

## Extending it

- **More of LIKE.** Three remaining pieces:
  - prove the NOCASE range;
  - prove `sqlite3Utf8Read` order-preserving on valid UTF-8, which would close the gap `range_ok` leaves;
  - add GLOB.

  Any LIKE fast path qc grows (prefix, suffix, contains) should be proved equal to `pc` on its preconditions.
- **More of the record format.** Model `qc_decode_fast`, and have `gen_decoders.py` emit the generated decoders' Lean
  twins, then prove them equal to `qcDecode` on their shapes. Other targets: overflow pages, the index-record compare
  (`sqlite3VdbeRecordCompare`, which `qc_idxkey_at` copies), and an encoder with `decode (encode vs) = vs`. The
  oracle already writes records into pages, so overflow cells are the next mutation.
- **Whole opcodes.** A small-step model of the VDBE subset qvm lifts would allow proofs of plan-level rewrites (the
  feed/get plans, the top-N array against `OP_IdxInsert` into an ephemeral index). That is a much larger effort.
  Cedar's experience says to do it only for the rewrites that keep changing.

## Verdict on the pilot

- **Cost:** about 3,900 lines across Lean and C, from one session. The proofs took the most time. The build adds 12 s
  (no Mathlib), and the oracle about 20 s for both modes.
- **Value:**
  - The proofs pin down the assumptions in turbo's comment-level reasoning: "reals between the integers", "no affinity
    applies to two numbers", "equality is byte equality", "after 10 parks". One of those assumptions turned out to be
    wrong.
  - Modelling the record format found a real robustness bug (finding 6) in an hour, and proved the fix.
  - The sort-key prefix can now be implemented against a proved spec and a tested C reference.
- **Limits:** none of turbo's past bugs would have been caught. Finding 6 is the first C-level one the model reached,
  and it did so because the model followed SQLite's own checks.
- **Recommendation:**
  - Keep `make lean-oracle` as a cheap suite, and make it strict once finding 6 is fixed.
  - Extend the model where turbo encodes a semantic rule in C: the shaped decoders, any LIKE fast path, and the sort
    prefix when it lands.
