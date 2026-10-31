# Tough problems: what turbo still loses, and what to try next

Written 2026-10-30 at `621e94c`. This is research only: nothing here is implemented.

## Sources

**corpus7 at `e170415`** (turbo-bench, box1, perf instructions; the session note `turbo-corpus7-e170415.md`):

| | hot | prep |
|---|---:|---:|
| all | 0.986 | 1.002 |
| faster / level / slower | 192 / 379 / 229 | |
| under 20 µs | 0.977 | 1.052 |
| unserved and >2 % slower | 85 | 134 |

**Local x86 callgrind at `621e94c`.** These are my own runs, since nobody has measured past corpus7 yet. Set-up:
- clang, `-O2 -march=x86-64-v2`, bench's `corpus.c` from `claude/bench-110a4d`, scale 1, in the `cursed-turbo-vg64` amd64 image;
- instructions per execution are `(cost(B) − cost(A)) / (B − A)`, so set-up and the first runs cancel out;
- **adapt off** unless the text says otherwise, which measures the plan's own cost;
- six batches of 5–12 statements;
- per-function profiles of 14 of them.

The scripts are `ss.sh`, `fs.sh` and `fdiff.py` (session scratchpad, not committed). They follow the recipe of the sqlite-jit session's `cq/`.

**Also used:**
- `docs/RESULTS.md` §16–22;
- `docs/IR.md`;
- `docs/PRIOR_ART.md`;
- the stale `bench/corpus/losers.tsv` (corpus3, branch `claude/bench-110a4d`);
- cursed-http's `explore/spec-policy-study/REPORT.md` and `explore/pg-jit-study/REPORT.md`.

All ratios below are serve / stock in instructions. The Xeon is what decides; these local numbers only rank the
problems. Every A/B proposed in §3 is meant for the broker, 5–10 statements a run.

## 1. What changed since corpus7

The commits after `e170415` fixed several of corpus7's worst statements outright. Local callgrind, hot, adapt off:

| statement | corpus7 | now | fixed by |
|---|---:|---:|---|
| chromium visit.google_search_visits | 1.594 | **0.949** | 4d69ac5 / 636b4a4 (LIKE `_` patterns, remembered rejects) |
| trilium entity_changes.depending_entity | 1.134 | **0.997** | 74d9a50 (substr in line) |
| kodi video.movies.by_genre | 1.19 (corpus3) | **0.991** | (between corpus3 and now; not attributed) |
| freshrss stats.entry_count_per_day | 1.114 | **0.890** | c4a3494 (radix sort of an integer key) |
| ha logbook.all | 1.048 (unserved) | **1.007** | (not attributed) |
| calibre annotations.count_for_book | 1.180 (fell back every run) | **1.017** | b376121 (auxdata isError −1) |
| syncthing update.insert_version (write) | 1.055 | 1.011 | (never served; the hook's cost only) |
| kodi music.increment_playcount (write) | 1.30 (corpus3) | 1.009 | |

Several statements are still at corpus7's level or worse:

| statement | stock µs | rows | corpus7 | now | class |
|---|---:|---:|---:|---:|---|
| atuin store.next | 98 | 100 | 1.23 (corpus3) | **1.215** | E: loop plan's top-N |
| beets get_album | 5.8 | 0 | 1.209 | 1.304 adapt on, 12 runs | B |
| chromium segment.usage_all | 4,890 | all | 1.205 | **1.132** | A |
| firefox utils.metadata_get | 5.6 | 1 | 1.115 | 1.137 / 1.054 parked | B |
| n8n executions.concurrent_count | 6,250 | 1 | 1.128 prep | **1.115** | D |
| calibre annotations.all_for_user | 18,700 | 13,333 | 1.141 | **1.114** | C + D |
| jellyfin browse.favorites | 881 | 20 | 1.045 | **1.098** | C |
| chromium url.get_row | 13.5 | 1 | 1.102 | 1.081 | B |
| vaultwarden sends.find_by_user | 186 | 100 | 1.10 | **1.080** | A |
| joplin resources.note_resources_page | 3,481 | 51 | 1.171 | **1.078** | D (LOWER + LIKE) |
| joplin folders.order_by_last_modified | 13,859 | 300 | 1.110 | **1.074** | C (GROUP BY a text key) |
| kodi music.top100.songs | 245 | 100 | 1.08 | 1.063 | A / C |
| calibre load.books_table_columns | 13,477 | 20,000 | 1.167 | **1.061** | A |
| trilium recent_changes.revisions | 18,338 | 19,994 | 1.114 | **1.061** | A |
| grafana unified.resource_list | 4,339 | | 1.061 | 1.057 | A |
| zotero collections.load_child_items | 2,555 | | 1.034 | 1.024 | A |

The wave-2 analytics apps have no turbo data in corpus7: it ran the 800 wave-1 statements. Six of their heaviest
statements, measured locally (scale 1, runs 1→2):

| statement | stock instructions | ratio |
|---|---:|---:|
| actual budget.sum_amounts_by_month | 775 M | 0.993 |
| karakeep tags.list.by_usage | 1,003 M | 0.999 |
| wakapi settings.user_agents | 1,187 M | 1.031 |
| crowdsec metrics.alerts_count_per_scenario | 1,139 M | 0.967 |
| frigate events.summary_per_day | 748 M | 0.964 |
| goatcounter stats.browsers | 477 M | 1.055 |
| tautulli graphs.plays_per_month_12m | 1,310 M | 0.973 |
| phoenix annotations.span_summary | 475 M | 0.966 |
| netalertx scan.events_new_connections | 934 M | 1.005, **not served** (0/2: falls back; cause not looked at) |
| dagster runs.sensor_runs_by_tags | 2,786 M | 1.028 |

They are served and close to level: turbo neither loses nor wins much on the corpus's most expensive statements. Per
§2 G, that is the gap columnar batches would close.

### How big each class is in corpus7

These counts come from turbo-bench's per-statement table (`turbo-corpus7-per-statement.tsv`: e170415, box1, adapt on,
streaming off, 801 statements). A statement is "slower" when its instruction ratio is over 1.02. "Served" means at
least half of its executions were served. Each class is a proxy built from the corpus's tags, so the counts are
approximate:

| class | proxy | hot: n, geomean | prep: n, geomean |
|---|---|---:|---:|
| B small | stock < 20 µs, slower | 73, 1.055 (61 of them mostly parked) | 47, 1.063 (43 parked) |
| A output-bound | served, slower, > 100 rows, no aggregate/group/sort/LIKE/window tag | 21, 1.053 | 20, 1.056 |
| C sort / group | served, slower, ≥ 20 µs, a groupby/orderby/topn tag | **92**, 1.052 | 92, 1.054 |
| G heavy | stock ≥ 10 ms (all) | 192, 0.992 | 188, 0.989 |
| G heavy with an aggregate or group | | 106, 0.981 | 104, 0.978 |
| F writes | an insert/update/delete/upsert tag | 131, 1.004 | 131, 1.001 |
| F FTS and virtual tables | | 46, 1.000 | 46, 1.000 |

What the table says:
- **Class C is the largest losing class,** and the one the hash GROUP BY (C1) and the text-key prefixes (C2) address.
- **Writes and FTS are at parity** on instructions, so class F needs nothing.
- **Within class B,** most of the losers are parked statements, which is B2's target. B1 takes all of them.

## 2. The classes, by root cause

### A. Output-bound scans: the plan's own loop is level with the interpreter, and serving adds glue per row

**Members:**

| statement | ratio | rows |
|---|---:|---:|
| calibre load.books_table_columns | 1.061 | 20,000 rows of 11 columns, no filter |
| trilium recent_changes.revisions | 1.061 | 20k rows, an index join |
| chromium segment.usage_all | 1.132 | every row, 3 integers, index order |
| vaultwarden sends.find_by_user | 1.080 | 19 columns |
| grafana unified.resource_list | 1.057 | |
| zotero collections.load_child_items | 1.024 | |
| kodi music.top100.songs | 1.063 | |

In corpus7 terms, these are most of the 66 served statements over 1.02 with more than 100 rows.

**Where the time goes** (x86, runs 3→4, instructions a run):

| statement | qvm's loop | interpreter (`sqlite3VdbeExec`) | the rest of the serve arm |
|---|---:|---:|---|
| books_table_columns | 34.93 M (`qv_run_rs`) | 34.58 M | +5.6 M |
| recent_changes.revisions | 36.30 M (`qv_run_rs`) | 36.37 M | `qv_row` 4.8 M, then glue |
| segment.usage_all | 14.6 M (`qv_run`) + 4.4 M (`qv_row`) | 18.5 M | +5.4 M |

The rest of the serve arm is:
- books_table_columns: `qv_row` 1.5 M, `qc_serve_step` 1.1 M, `sqlite3VdbeMemClearAndResize` 1.0 M,
  `qc_serve_stream` 0.9 M, about 1 M more elsewhere;
- segment.usage_all: `qc_serve_step` 2.9 M, `qv_sink_wide` 2.2 M (the kept rows' copy; it doesn't stream).

The B-tree work and the application's own `sqlite3_column_*` calls are identical in both arms.

**Diagnosis:**
- **No per-row work to win.** These loops are Column × n → ResultRow. qvm decodes the same fields the interpreter
  decodes, so its own loop can at best be level.
- **What's left is serving's cost per handed-out row:** 150–300 instructions. It comes from:
  - the resumable loop: `qv_run_rs`, about 7 % over `qv_run` (51be86c);
  - each step's `qc_serve_step` → `qc_serve_stream`;
  - registers re-sized for texts;
  - for kept results, the copy into the sink.
- **adapt doesn't park them.** Most run 5–9 times in bench's budget. That is too few for adapt's 8+ samples, and its
  1.03 margin is wider than their 2–6 % loss in time.

### B. Small point lookups (stock under 20 µs): fixed costs that exceed a 4–9 k-instruction statement

**Members:**
- corpus7's 75 slower statements under 20 µs, most of them unserved, so parked;
- firefox utils.metadata_get, grafana star.is_starred, kodi video.file_id, ftl querydb.client_id_lookup, chromium
  url.get_row, beets get_album, syncthing mtimes.get;
- in prep mode, zotero item.value_id_lookup, datasette internal.catalog_schema_versions and chromium
  clusters.visits_in_cluster, at 1.09–1.11.

**Where the time goes:**

| | metadata_get | url.get_row | is_starred | file_id | client_id_lookup |
|---|---:|---:|---:|---:|---:|
| adapt off, served | 1.137 | 1.081 | 1.046 | 1.086 | 1.079 |
| adapt on, 12 executions | 1.324 | | 1.152 | | |
| adapt on, runs 200→600 (parked; served 115/600) | **1.054** | | **1.041** | | |

beets get_album and syncthing mtimes.get read 1.30 and 1.23 with adapt on at 12 executions.

firefox utils.metadata_get, adapt off (3,677 instructions stock, 4,173 served):
- **Serve-only functions:**
  - `qv_run` 457;
  - `qv_exec` 358 (per-run set-up: resets, cursor table, sink);
  - `qc_serve_fast` 122;
  - `qc_serve_step` 114;
  - `qv_cursor_db` 103.
- **Stock-only:** `sqlite3VdbeExec` 718 and `sqlite3VdbeHalt` 121.
- **The rest is common to both:** the read transaction's begin and commit, the seek. The plan's opcode work is cheaper
  than the interpreter's: 457 against 718. Its fixed set-up is what loses.

**Diagnosis:** three costs stack up.
1. **Serving a lookup** costs +200 to +500 instructions of fixed set-up over a program qvm runs no faster.
2. **Parking isn't free.** A parked plan is unparked and re-sampled on a countdown: 115 of 600 executions were served
   (learning) in steady state. That costs 4–5 % for good. It's the floor under corpus7's "unserved and slower".
3. **Short-lived handles** (12 executions, or prep mode) pay the whole learning phase: 1.15–1.32.

### C. ORDER BY and GROUP BY through a sorter on text, or on big records

**Members:**
- joplin folders.order_by_last_modified (1.074): GROUP BY parent_id, a 32-character text, over 72k rows;
- calibre annotations.all_for_user (1.114): ORDER BY a REAL timestamp, with the big `annot_data` JSON in each record;
- jellyfin browse.favorites (1.098): GROUP BY + ORDER BY SortName + LIMIT 20;
- atuin history.all_with_count (1.134 in corpus7): GROUP BY two keys, three group_concat;
- the `orderby` tag's 1.042 time and the `having` tag's 1.085 in the ae2d546 series.

**Where the time goes:**

**joplin folders:**

| serve | instructions | stock | instructions |
|---|---:|---|---:|
| `qv_sort` | 22.2 M | `vdbeSorterCompareText` | 16.2 M |
| | | `vdbeSorterSort` | 5.6 M |
| `qv_region` | 17.7 M | `sqlite3VdbeExec` | 37.6 M |
| `qv_run` | 11.9 M | | |
| `qv_make_record` | 4.5 M | | |
| `qv_compare_slow` | 1.8 M | | |

- qvm's sort costs what SQLite's does, because it compares the same text keys one by one.
- On top of that, the region builds a record per row (MakeRecord) that is decoded again for the group compare.

**calibre all_for_user:**
- Both arms end in SQLite's sorter: `vdbeSorterCompareReal` 6.1 M in each, because qvm spilled.
- qvm also built the records itself (`qv_make_record` 7.1 M), compared its WHERE's three text equalities through
  `qv_compare_slow` (4.6 M), and wrote them to the sorter.

**Diagnosis:**
- **Text keys get no shortcut.** The radix sort (c4a3494) takes one-field integer keys only.
- **GROUP BY sorts every row** to find a few hundred groups (joplin: 72k rows, 300 groups).
- **Sorts carry full records.** A sort over a wide payload copies the payload, and once it spills, the work is done
  twice.

### D. Filters on text: equality, LIKE on an expression, IN over text

**Members:**
- n8n executions.concurrent_count (1.115): `status = ?1 AND mode IN (?2, ?3) AND deletedAt IS NULL` over a partial
  index and the table;
- calibre all_for_user's three text equalities;
- joplin resources.note_resources_page (1.078): `LOWER(COALESCE(x, '')) LIKE ?` on two columns;
- wakapi settings.user_agents (1.031): `user_id = ?1 AND NOT user_agent = ''`;
- the `like` tag's 1.027 and the `collate` tag's 1.023 in the ae2d546 series.

**Where the time goes:**
- **n8n:**
  - serve: `qv_run` 22.2 M, `qv_compare_slow` 7.0 M, `qv_row` 6.0 M;
  - stock: `sqlite3VdbeExec` 29.9 M.
  - The regions take integer compares in line (RG_CMPI). A text compare goes to `qv_compare_slow`, which calls
    `sqlite3MemCompare` with the collation, and is dearer than the interpreter's own OP_Eq.
- **joplin note_resources_page:**
  - serve: `qv_function_slow` 7.3 M and `lowerFunc` 2.4 M, plus a malloc and free per row for lower()'s result;
  - stock: `likeFunc` 1.36 M and `patternCompare` 1.48 M.
  - qvm's in-line LIKE never runs, because the LIKE's argument is a function result and the function goes to the slow
    path.

### E. The loop-plan tier on a small top-N

**Member:** atuin store.next (1.215, 100 rows): `idx >= ?1 AND host = ?2 AND tag = ?3 ORDER BY idx LIMIT ?4` on the
unique (host, tag, idx) index.

**Where the time goes:**

| serve, a run of 520–630 k | instructions |
|---|---:|
| `qg_rowval` | 55 k |
| `qc_lower_bound` | 43 k |
| `qc_decode` | 37 k |
| `qc_serve_mems` | 34 k |
| `qg_fetch` | 29 k |
| `qc_seek_batch` | 23 k |
| `qg_level` | 20 k |
| `qg_emit` | 19 k |

Stock spends 155 k in `sqlite3VdbeExec`.

**Diagnosis:**
- qcg's per-row machinery for a range of 100 rows of 8 columns costs more than the interpreter.
- d960693 demoted only single-row lookups to qvm. A short range is the same case one step further.

### F. What always falls back, or is never served

- **Writes:** INSERT, UPDATE, DELETE and UPSERT are refused at the hook (`qcNo`). They now cost 1.009–1.011 locally
  (insert_version, increment_playcount). That is close enough to parity that serving writes isn't worth its risk.
- **Never served:** FTS and virtual tables, 46 statements in the ae2d546 series at 1.02–1.03 time. The `fts` tag's
  25 never-served statements cost what the hook and the negative cache cost.
- **json_extract:** count_for_book now serves (b376121). The `json` tag still had 10 of 53 statements served at
  ae2d546. Most json shapes go through `qv_function_slow` with a parse per row.
- **Overflow records** are read through `qv_ovf` (RESULTS §19). No statement in this round lost because of them.

### G. The heavy analytics statements: level, where the big wins should be

**Members:** wave 2's `analytics` / `cpu-evidence` statements (actual, karakeep, wakapi, crowdsec, frigate, etc.),
plus wave 1's aggregates over 10k–300k rows. Examples: freshrss entry_count_per_day, anki scheduler.deck_due_counts,
atuin history.get_dups, ha statistics.compile_hourly.

**Where the time goes** (x86, runs 1→2, instructions a run):

**wakapi settings.user_agents** (1.187 G stock, 1.223 G served):
- **The GROUP BY's sort is about half of both arms:** `sqlite3VdbeRecordCompareWithSkip` 296 M,
  `sqlite3VdbeRecordUnpack` 119 M, `vdbeSorterCompareText` 91 M, `memcmp` 90 M, `sqlite3BinaryCompare` 45 M and
  `vdbeSorterSort` 21 M.
  - It groups on four text columns (user_agent, os, editor, ai_model).
  - The counts are the same in both arms: the input passed the PMA size, so qvm's sorter handed the records to
    SQLite's own sorter (`qv_sort_spill`, by design, for exactness), and neither c4a3494's radix nor qvm's own sort
    ran.
- **qvm's loop and SQLite's loop:** `qv_run` 205 M against `sqlite3VdbeExec` 249 M.
- **Extra in the serve arm:** `qv_make_record` 33 M, `qv_row` 17 M and `qv_aggstep` 15 M.

**actual budget.sum_amounts_by_month** (775 M stock):
- three nested views over a join;
- **B-tree seeks:** `sqlite3BtreeTableMoveto` 60 M, `sqlite3BtreeIndexMoveto` 57 M, `vdbeRecordCompareString` 51 M;
- **the GROUP BY's sort:** `vdbeSorterCompareText` 54 M and `vdbeSorterSort` 16 M;
- **qvm's loop and SQLite's loop:** `qv_run` 274 M against `sqlite3VdbeExec` 319 M.

**Diagnosis:**
- **The GROUP BY sort.** In the wave-2 profiles, the largest single item is the sort that SQLite's GROUP BY uses when
  no index orders the keys. It runs on text keys, and both arms pay it identically. C1 (hash aggregation) is aimed at
  exactly that.
- **What's left is mostly B-tree seeks of joins.** No executor change touches those.
- qvm's regions already take integer columns and compares in line, and count and sum natively.
- **Still paid on every row:**
  - the B-tree step;
  - the record header parse;
  - a `Mem` written per column;
  - dispatch per node;
  - text compares out of line.
- These statements are 10–1000 ms and run few times, which is exactly the class that a batch-at-a-time executor turns
  into wins.

## 3. Ideas, by class

Each idea gives:
- the mechanism;
- the statements it should help;
- the expected gain and why;
- the risk to the never-regress rule;
- the A/B that confirms or kills it.

### A1. A static "nothing to win" verdict at lift

**Mechanism:** at lift, mark a plan "never serve" when all of these hold:
- the program is a single loop nest whose body is only Column / Rowid / Copy → ResultRow;
- it has no filter that isn't an index bound, no function, no aggregate and no sorter;
- it is not a candidate for a later tier (no region gain possible).

Such a plan goes straight to `qcNo` and the negative cache, as writes do. This is spec-policy-study §5.3's "choose by
measurement", with a prior so that statements run 5–9 times never pay the learning.

**Helps:**
- calibre books_table_columns, trilium recent_changes, chromium segment.usage_all, vaultwarden sends.find_by_user,
  zotero load_child_items;
- probably 20–40 of corpus7's 66 served statements over 1.02 with more than 100 rows.

**Expected gain:** from 1.02–1.13 to the hook's floor of about 1.005, because their own loop is already level and the
excess is glue (§2 A).

**Risk:** low. It only gives up plans, and the statements it catches are level at best. The one way to lose is to
catch a statement that wins today, for example one whose seek work qvm does cheaper (kodi movies.by_genre at 0.991).
So the predicate must exclude joins with seeks, and exclude any program with a filter.

**A/B:** books_table_columns, recent_changes, usage_all, sends.find_by_user, load_child_items, and two guards
(movies.by_genre, zotero items.primary_data at 0.63). Hot and prep. Kill it if any guard moves above 1.0.

### A2. Hand-out without copies: result Mems that point into pinned pages

**Mechanism:**
- **Streaming (QC_STREAM) already pauses the loop at each ResultRow.** What's left:
  - `qc_serve_stream`;
  - `qv_run_rs`'s re-entry, 7 %;
  - the register re-size for each text.
- **Hand texts out as ephemeral Mems** (`MEM_Ephem`) pointing into the pinned page. qvm already pins one page per
  cursor (RESULTS §11). This is what OP_Column does for a value that lies within one page.
- **Keep the kept-rows path (`qv_sink_wide`) for statements that don't stream:** chromium usage_all's three
  integers, about 110 instructions a row. Fill `pResultRow` straight from the region's output registers when the row
  is all integers. The last attempt at this (RESULTS §22, "filling the result registers straight from qc's row saved
  nothing") was on 1-row results; a 20k-row result is the case where it pays.

**Helps:** class A whenever A1 doesn't catch it (a statement with a filter, a join), and every served statement with
more than 100 rows. corpus7's "rows >100" bucket: 66 slower out of 173.

**Expected gain:** 2–5 % on those, about half of the measured glue.

**Risk:**
- medium on correctness: a pinned page must outlive the row handed out (sqlite3_step's next call releases it);
- low on speed.

**A/B:** usage_all, recent_changes, all_for_user, sends.find_by_user, top100.songs, plus two 1-row guards (anki
card.get_by_id, zotero creators.id_from_data).

### B1. Don't lift what can't win: a size gate for point lookups

**Mechanism:** a program of one seek, with no loop, under about 40 ops and with no function, gets `qcNo` at its first
`sqlite3QcStart`:
- the parked path's cost, without parking's re-sampling;
- the plan cache keeps the verdict by SQL text, as the negative cache keeps "no table", so a re-prepare doesn't learn
  again.

An exception list, from the measured wins, keeps the lookups that qvm does win:
- they have a function or a subquery: memos count_user_memos (0.24), synapse relations.get_thread_id (0.48);
- or an aggregate: zotero latest_cache_version_one (0.50).

So the rule is "no aggregate, no subquery, no function, ≤ 1 cursor and 1 row out".

**Helps:** the 75 slower statements under 20 µs (corpus7 hot), and in prep the 47 slower of 50. From this round:
metadata_get, url.get_row, is_starred, file_id, client_id_lookup, get_album, mtimes.get.

**Expected gain:**

| | now | with B1 |
|---|---:|---:|
| served, hot (adapt off) | 1.04–1.14 | about 1.003 (the two-byte hook check) |
| parked, steady state | 1.04–1.05 | about 1.003 |
| short handles | 1.15–1.32 | about 1.003 |
| under-20 µs bucket | 0.977 | below 0.97: the wins stay, the losses go to parity |

**Risk:** low. The rule only gives statements back to SQLite. What could be lost is the few small lookups that win
today without a function or an aggregate. corpus7's best list has datasette permissions.check_table_allowed (0.646)
and ftl network.name_from_ip_fallback (0.705). Check both before trusting the rule, and keep them by an op-count or
shape exception.

**A/B:** the seven above plus datasette check_table_allowed, ftl name_from_ip_fallback, ha states_meta.find_ids
(0.635) and memos list_memos.by_uid (0.736) as guards. Hot and prep, 2000 executions. Kill it if a guard loses its
win.

**Result (sqlite-jit, landed):** `qc_gate_small` in `qc_serve_start` gives a program back to SQLite at its first start
(`qcNo`) when its body, under 40 ops, has no loop, function, aggregate, subquery, sorter or ephemeral table, at most one
result row, two cursors and **one seek**. The one-seek limit keeps chromium segment.url_for_segment, two rowid seeks that
qvm wins at 0.92–0.98. Across the 44 apps it gates 33 statements, and corpus7 measured every one of them slower served,
apart from url_for_segment, which the limit now excludes. The scan returns at the first op that disqualifies a program,
through a constant opcode table. `QC_NOGATE=1` turns it off. No verdict per SQL text was needed: the scan is cheaper than
a cache lookup.

Local callgrind (x86 / arm64, adapt on as shipped, against 3248ccb):

| | hot, before | hot, after | prep, before | prep, after |
|---|---:|---:|---:|---:|
| firefox metadata_get | 1.454 / 1.352 | 1.015 / 0.981 | 1.194 / 1.154 | 1.014 / 1.022 |
| grafana is_starred | 1.217 / 1.194 | 1.008 / 1.001 | 1.127 / 1.107 | 1.012 / 1.021 |
| chromium url.get_row | 1.193 / 1.238 | 1.018 / 1.012 | 1.078 / 1.084 | 1.018 / 1.011 |
| ftl client_id_lookup | 1.359 / 1.301 | 1.023 / 1.002 | 1.140 / 1.111 | 1.018 / 1.007 |
| syncthing mtimes.get | 1.312 / 1.281 | 1.017 / 1.016 | 1.140 / 1.113 | 1.016 / 1.017 |
| zotero value_id_lookup | 1.375 / 1.330 | 1.022 / 1.018 | 1.193 / 1.148 | 1.021 / 1.019 |

**Guards** (url_for_segment, check_table_allowed, name_from_ip_fallback, find_ids, list_memos.by_uid,
count_user_memos, kodi video.file_id) are level within 0.3 %, in hot and in prep. The exception is kodi file_id in prep,
+0.4–0.6 %; it was already at 1.11–1.14.

**One loss with adapt off:** with adapt off, which isn't the shipped setting, chromium url.get_row on x86 was a win at
0.943 and is now 1.021.

### B2. adapt's verdicts that stay: back-off, and a verdict per SQL text

**Mechanism:** spec-policy-study rules 2 and 4:
- **Park with back-off.** After the k-th park, unpark after 256·2^k executions, not on a fixed countdown. After three
  agreeing parks, the verdict is final until the schema changes.
- **Carry the verdict in the plan cache entry,** so a new handle on the same text starts parked. This covers
  prepare-per-execution ORMs, and short handles.

**Helps:** everything adapt parks:
- corpus7's 85 "unserved and slower" hot statements, at 1.02–1.12;
- the 134 in prep.

**Expected gain:**
- steady-state parked cost from 1.04–1.05 to about 1.005: 115 of 600 executions are learning runs today;
- in prep, the whole learning tax on a re-prepare.

**Risk:** low. A statement whose data changes so that the plan would win later is kept parked longer. The back-off
still re-checks it, and a schema change resets it.

**A/B:** metadata_get, is_starred, get_album, value_id_lookup, catalog_schema_versions, visits_in_cluster, with adapt
on, 2000 executions hot and prep. Guards: two kept wins (count_user_memos, team.search).

**Result (sqlite-jit, landed):** two changes in qc.c.
- **Back-off:** the R-th park lasts `QC_PARK_BASE` (256) × 2^(R−1) executions. A plan parked three times and never kept
  is parked for good (`QC_PARK_FINAL`); one that was ever kept still gets ten parks, as before (64 × 2^(R−1) then).
- **Verdict per SQL text:** when a statement whose plan is parked for good is freed, its text goes into the negative
  cache instead of the plan going into the plan cache. A new handle, a re-prepare, or an ORM's prepare per execution
  then gets `qcNo` at lift, until the schema changes.

Local callgrind (x86 / arm64, adapt on, against c4c5fbe). Up to 1,100 executions it barely moves (−0.2 to −0.6 %):
the final verdict comes after about 800 executions. Past it:

| | hot 2000→3000, before | after | prep 1500→2000, before | after |
|---|---:|---:|---:|---:|
| kodi video.file_id | 1.021 / 1.018 | 0.990 / 1.013 | 1.054 / 1.056 | 1.024 / 1.026 |
| datasette catalog_schema_versions | 1.022 / 1.015 | 1.019 / 1.011 | 1.067 / 1.068 | 1.029 / 1.029 |
| chromium visits_in_cluster | 1.020 / 1.000 | 1.018 / 0.998 | 1.076 / 1.070 | 1.022 / 1.014 |
| beets get_album | 1.013 / 1.010 | 1.015 / 1.009 | 1.026 / 1.026 | 1.001 / 1.026 |

**Guards:** the kept wins (ha find_ids, memos count_user_memos, grafana team.search) are level within 0.3 %.

**What's left:** in prep, a parked text pays about 2–3 %, for the cache and negative-cache lookups at each prepare. In
hot it pays about 1–2 %, the hook's cost on a 5 k-instruction statement.

### B3. Cheaper qv_exec set-up for one-row plans

**Mechanism:** qv_exec's 358 instructions a run for metadata_get are resets for the plan's cursors, registers and
sinks. Instead:
- record at build time which resets the plan needs (as `mayDyn` does in 6ad125a);
- generate a reset list;
- `qv_cursor_db`'s 103 instructions a run look up per run what is fixed per connection.

**Helps:** every served lookup that B1 doesn't take: those with a function, an aggregate or a join.

**Expected gain:** 150–300 instructions a run, which is 2–5 % of a 6 k-instruction statement.

**Risk:** low. It's the same work, done once.

**A/B:** count_user_memos, get_thread_id, latest_cache_version_one, card.get_by_id, users.find_by_uuid.

### C1. Hash aggregation, then a sort of the groups

**Mechanism:**
- **What SQLite emits:** for a GROUP BY that no index orders, a sorter over every input row (SorterInsert), then a
  scan comparing adjacent keys.
- **The replacement in qvm:** recognise SorterOpen … SorterInsert / SorterSort … SorterData + Compare/Jump + AggStep
  and run it as a hash table keyed by the group values, which RESULTS §7d's `QvHset` already hashes from registers.
  Each group holds its accumulators.
- **Order:** sort only the groups, stably by key, at the end, then emit them as the GROUP BY's output loop would.
- **Exactness, below the spill size:** the aggregates see each group's rows in the same order. The in-memory sort is
  stable, so a group's rows come in scan order, and a hash table fed by the scan sees them in scan order too. So sum
  over floats, group_concat, bare columns and the order of min/max ties are identical.
- **Exactness, past it:** SQLite's sorter writes PMAs and merges them, which "can order equal keys differently"
  (`qv_sort_limits`' comment). That is why qvm hands such sorts to SQLite's sorter.
- **So C1 needs one of two conditions:**
  - every aggregate doesn't depend on the order. That means count, min and max with no bare column, and sum and total
    over integers. A first non-integer value aborts the run (QC_FALLBACK before any row, as today).
  - Or the input stays under the spill size: `sqlite3TempInMemory`, or the previous run's bytes under `S->lim`, as
    streaming decides from the last run.
- **Which statements pass:**
  - wakapi user_agents (group keys, min(time) and max(time)) and joplin folders (max) pass the first rule;
  - atuin all_with_count (group_concat, bare columns) needs the second.
- **Fallback:** a non-BINARY collation, or a key type mix where the collation matters, falls back as today.

**Helps:**
- joplin folders.order_by_last_modified (72k rows, 300 groups), atuin history.all_with_count, jellyfin
  browse.favorites;
- wave 2's GROUP BY analytics: wakapi user_agents, karakeep tags.list.by_usage, actual sum_amounts_by_month (if no
  index orders it), tautulli and goatcounter stats;
- the `groupby` tag: 147 statements in wave 1, 0.98–1.01 now.

**Expected gain:** the sort goes from n·log n text compares to n hashes plus g·log g.
- **joplin folders:** the sort is about 22 M of 77 M. With no MakeRecord per row (4.5 M) and no decode back out of
  it, expect 0.75–0.85 of stock.
- **wakapi user_agents:** the four-key sort is about 660 M of 1,223 M (§2 G). Expect **0.5–0.6 of stock**. It's the
  largest single gain found in this round, on one of the corpus's most expensive statements.
- **actual sum_amounts_by_month:** about 70 M of 770 M, so about 0.9.
- **Statements where groups are far fewer than rows:** similar gains.

**The spill.** wakapi's GROUP BY went to SQLite's sorter (`qv_sort_spill`) because its input passed the PMA size.
That is by design, to keep the merge's order of equal keys. C1's hash table holds one entry per group, not per row,
so it doesn't reach the spill size where the sorter would. Its exactness rule is the one above.

This is HyPer and DuckDB's default aggregation. pg-jit-study #3 (hash from values) is the same idea.

**Risk:**
- **Speed, medium:** when nearly every row is its own group, the hash adds its own cost to a sort that is still
  needed. Guard with an adaptive cut-over: after N rows, if groups/rows > 0.5, hand the rows already in the table to
  the sorter path in scan order and continue there. Or decide from the previous run's ratio, as streaming does.
- **Exactness, low:** see above, given the stable order argument.

**A/B:** joplin folders, atuin all_with_count, jellyfin favorites, wakapi user_agents, karakeep by_usage. Guards: a
GROUP BY that is nearly unique (atuin history.get_dups, already at 0.80) and one GROUP BY in index order (anki
notetype.use_counts, 0.74).

### C2. Normalised key prefixes for text sorts and compares (abbreviated keys)

**Mechanism:**
- **Decoding:** when qvm's sorter decodes a record's keys, store for a BINARY text key the first 8 bytes big-endian
  in a u64. Ignoring endianness and length, that's just the bytes. (pg-jit-study #5, PostgreSQL's abbreviated keys.)
- **Comparing:** compare the u64s first, and the full text only on a tie.
- **Sorting:** an MSD radix sort on the prefix, falling back to a comparison sort inside the buckets that tie. This
  extends c4a3494 from integers to text.
- **NOCASE:** fold to lower case when the key is built.
- **DESC:** invert, as c4a3494 does.

**Helps:**
- ORDER BY a text column: jellyfin favorites' SortName, grafana resource_list's name, joplin note_resources_page's
  LOWER(title);
- C1's final sort of the groups;
- every top-N over text.

**Expected gain:**
- 30–60 % of the sort's compare cost on text keys with distinct prefixes;
- little on keys with long shared prefixes (paths, URLs). The give-up heuristic falls back when the first bucket
  holds more than half the keys.

**Risk:** low. It's exact by construction (a tie always goes to the full compare). The cost is building the prefix,
about 10 instructions a row. That loses only on sorts of a few rows: skip it under 64 records.

**A/B:** jellyfin favorites, grafana resource_list, joplin note_resources_page, chromium url sorted by title (any
ORDER BY text over more than 1k rows), joplin folders (with C1).

### C3. Late materialisation for sorts with a wide payload

**Mechanism:**
- Sort (key, rowid) or (key, pointer to the record in a pinned page) instead of whole records, then fetch the payload
  in sorted order.
- With LIMIT (top-N), only the survivors are fetched.
- This is DuckDB's and Umbra's row-ID sort.
- qvm has the cursor and can re-seek by rowid. For a table read in rowid order the re-seek is cheap, since the pages
  are hot.
- It must keep SQLite's behaviour that the sorter holds a snapshot: under qvm's read-only run with the read
  transaction held, the table can't change mid-statement, so a re-read sees the same row.

**Helps:**
- calibre annotations.all_for_user: `annot_data` in every sorter record; it spills to SQLite's sorter, then MakeRecord
  and the copies;
- signal-desktop and grafana list queries that carry JSON or blobs;
- TPC-H Q09, Q10 and Q13, and ClickBench's spilling sorts. Since RESULTS §18 these hand their records to SQLite's
  sorter instead of running twice (BENCH.md's 1.7×). They still pay qvm's MakeRecord on top of SQLite's sort.

**Expected gain:**
- all_for_user from 1.114 to about 0.95: the 7 M MakeRecord, the sorter writes and the spill go;
- large on spilling sorts: an in-memory sort of keys instead of a spill.

**Risk:**
- **Speed, medium:** for narrow rows the re-seek costs more than the copy it saves. Use it only when the payload
  averages more than about 64 bytes, a fact taken from the last run as streaming does.
- **Exactness, low:** the same rows, re-read under the same transaction.

**A/B:** all_for_user, calibre fts or annotations listings, signal conversation.older_page, grafana
legacy.dashboards_page, and one narrow-row sort as a guard (chromium usage_all).

### D1. Text comparisons in line in regions

**Mechanism:**
- **New node:** RG_CMPT, for Eq/Ne/Lt/… where the feedback says both sides are text and the collation is BINARY (P4
  is 0, or is `sqlite3StrBINARY`), with no affinity change (P5's affinity none or TEXT, both sides text).
- **What it does:** `memcmp(a, b, min(n1, n2))`, then the lengths. That is what `sqlite3MemCompare` does for that
  case, after its type dispatch and collation lookup.
- **Fallback:** a mixed type widens the node, as RG_CMPI does.
- **Constants:** a bound parameter or literal compared against a column every row has its length and its first 8 bytes
  hoisted, which rejects most rows with one u64 compare. This scalar form of D3 needs no SIMD.

**Helps:**
- n8n concurrent_count (`qv_compare_slow` 7.0 M of 54 M);
- calibre all_for_user (4.6 M);
- wakapi user_agents;
- crowdsec filters on scenario and origin;
- every `status = 'x'` / `type IN ('a', 'b')` scan: the `in-list` tag's 181 statements and `full-scan`'s 310.

**Expected gain:** n8n 1.115 → about 1.0, since the slow compare path is the whole loss. 2–8 % on the filtered text
scans generally.

**Risk:** low. It's exactly the BINARY branch of `sqlite3MemCompare`, and anything else takes the generic node.

**A/B:** n8n concurrent_count, calibre all_for_user, wakapi user_agents, crowdsec alerts_count_per_scenario, ha
logbook.all, plus a NOCASE-collation guard (any `COLLATE NOCASE` filter from the `collate` tag).

**Result (sqlite-jit, landed):** RG_CMPT, a region node for Eq/Ne/Lt/… The region builder makes one where the feedback
saw both sides as text, the collation is BINARY or none, and the affinity is TEXT or lower. At run time the node checks
only that both sides are plain UTF-8 strings, then compares them with memcmp and the lengths. Anything else widens it to
RG_CMP, as RG_CMPI does. The constant-prefix hoisting isn't done.

Outside regions, 60b0899 had already put the same compare in line in qv_run (qv_compare_str). That took n8n
concurrent_count from 1.115 to 1.017 before D1. Its loop has a DeferredSeek, so it gets no region and D1 doesn't change it.

Local callgrind (x86 / arm64, against 77dcbb1):
- **vaultwarden sends.find_by_user:** 0.961 / 0.964 → 0.838 / 0.842 with adapt off, and 0.997 / 0.979 → 0.948 / 0.931
  with adapt on.
- **calibre all_for_user:** level. Its region has the three cmp:text nodes, but it switches itself off: OP_RealAffinity
  (its REAL sort key) has no node, so every row that passes the filters leaves the region.
- **Guards:** n8n concurrent_count, ha logbook.all, beets items_flexattr_filter (NOCASE) and chromium
  google_search_visits are level to the instruction.

### D2. lower()/upper() in line, and LIKE(lower(x)) folded

**Mechanism:**
- **lower() and upper() in line** for UTF-8 text: ASCII-only folding, as core SQLite's lowerFunc and upperFunc do
  without ICU. Write into the output register's buffer, as 74d9a50 does for substr. The malloc and free per call go.
- **Fold the function into the LIKE.** When a LIKE's left argument is `lower(x)` or `upper(x)` and `case_sensitive_like`
  is off, LIKE folds ASCII itself, and lower() changes only ASCII. So `LIKE(p, lower(x))` ≡ `LIKE(p, x)` for every
  input, and qvm's in-line LIKE runs on x directly.
- **COALESCE(x, '')** is IfNotNull/String8 in the bytecode, so it doesn't stop the fold.

**Helps:**
- joplin resources.note_resources_page (`qv_function_slow` 7.3 M + `lowerFunc` 2.4 M of 21.7 M);
- the joplin and claude-mem search queries;
- every `LOWER(col) LIKE ?` an ORM emits for a case-insensitive search: the `like` tag has 85 statements.

**Expected gain:** note_resources_page 1.078 → about 0.8, as the other in-line LIKEs did (beets 1.23 → 0.94).

**Risk:**
- **Speed, low.**
- **Exactness, low:** with ICU, or a user-defined lower(), the function isn't the built-in one. Check the FuncDef
  pointer, as qv_function_slow does today.

**A/B:** note_resources_page, joplin search.*, claude-mem search.sessions_fts filters, beets items_anyfield_flex (a
guard: in-line LIKE already), any `lower(x) = ?` statement.

### E1. A short range demotes to qvm, as single-row lookups do

**Mechanism:** d960693 demotes a point lookup whose last run handed out at most one row. Extend it to:
- a loop plan of one level with a seek, no aggregate, and at most about 200 rows handed out;
- or simply time qcg against qvm once (spec-policy §5.3, tier by measurement). The plan cache keeps both.

**Helps:**
- atuin store.next (1.215);
- datasette table.page_default and autocomplete;
- signal unread.select_unseen;
- synapse linearized_receipts. These are corpus3's sort losers served by qcg.

**Expected gain:** qvm at about 1.0 against qcg's 1.2 on store.next. That's the gap d960693 measured for lookups
(1.215 → 1.097).

**Risk:** low with measurement, medium with a static row cap, since qcg wins big seeks of several rows.

**A/B:** store.next, select_unseen, linearized_receipts, page_default, autocomplete. Guards: qcg's wins (anki
deck_due_counts 0.76, zotero collections.primary_data 0.76).

### G1. Columnar batch execution with SIMD, in qvm's regions

This is the user's idea: decode one column for a batch of rows, scalar; then vectorise the filters, the aggregates
and the text compares.

#### Where it fits

**Inside qvm's loop regions (IR.md step 4), as a third execution mode beside the closure nodes.** A region is already:
- one cursor's Rewind/Seek … Next;
- with its body as nodes;
- with the fields it reads known (`maxf`);
- with type feedback per Column.

A batch region adds a header. The loop collects up to 256 rows' cell pointers from the current leaf page. A table
leaf holds 20–200 cells, and qvm already pins one page per cursor (RESULTS §11), so a page is a batch, with no copy.

The body then runs column-at-a-time over the batch.

#### The lowering

A region qualifies when its body is, in order:
1. Columns of the region's cursor;
2. filters: compares against constants or parameters, IsNull/NotNull, and LIKE/GLOB with a constant pattern;
3. a sink with no per-row output:
   - AggStep on count, sum, total, min or max;
   - MakeRecord + SorterInsert or IdxInsert (sort and GROUP BY input, DISTINCT);
   - a Gosub to a group-change compare (a GROUP BY in index order).

The lowered region runs in four steps:

**1. Decode, scalar.** For each column used, walk the batch's records once, and write:
- typed arrays: `i64 v[256]`, `f64`, or `(ptr, len)` for text pointing into the page;
- a class byte per row (null / int / real / text / blob);
- the walk uses the shape decoders the loop plans have (`gen_decoders.py`). One header parse per row feeds every
  column, the region's existing fused decode, laid out by column instead of into Mems.

**2. Filter.** Each filter turns the arrays into a selection bitmap of 256 bits:
- **int compares:** 4 lanes of i64 with AVX2 (`vpcmpgtq`), or 2 lanes with NEON;
- **text = constant:** a length compare (an i32 vector), then the first 8 bytes as a u64 compare against the
  constant's, then `memcmp` on the survivors only;
- **IN (a, b, …) over text:** the same, against each candidate's prefix;
- **prefix LIKE or GLOB** ('abc%', 'abc*'): a masked 8-byte compare (ASCII-folded for LIKE), with the long tail
  scalar;
- **IsNull and NotNull:** the class bytes compared, 32 at a time.

Filters AND into the bitmap in program order. A row a filter has already dropped is skipped, as the bytecode's jumps
skip it. A filter that could raise an error, or that needs affinity, isn't batched.

**3. Aggregate** over the selected rows:
- **count(*):** popcount of the bitmap;
- **count(x):** popcount of `bitmap & notnull`;
- **sum and total over integers:** a SIMD add with an overflow check per lane. Any overflow, or a non-integer row,
  sends the whole batch to the scalar path in row order, from that row.
- **sum over reals stays scalar.** Kahan-Babuska-Neumaier summation depends on order, and SIMD lanes reorder the
  additions, so the result wouldn't be bit-identical.
- **min and max over integers:** SIMD, exact.
- **min and max over reals or text:** find the extreme in SIMD, then take the *first* row equal to it. minmaxStep
  replaces only on a strict compare, so ties keep the first row, and −0.0 equals 0.0.

**4. Sort and group sinks:**
- the batch's keys go to qvm's sorter as decoded keys (QvSort's `key` array), so the radix sort (c4a3494) and C2's
  prefixes are fed without a MakeRecord and decode;
- for C1's hash aggregation, hash the batch's key columns vectorised (a multiply-xor per lane), then probe scalar.

#### Guards and deoptimisation

A batch whose column class doesn't match the speculation (a text in an `{int}` column):
- runs that batch through the region's existing scalar nodes, which are exact;
- clears the column's batch speculation for later runs (one-way, spec-policy rule 1).

Nothing is ever output from a batch except aggregate state and sorter input, so no row is handed out early.

#### What's left scalar

- the B-tree step between pages;
- the record header parse;
- overflow records (the batch ends at an overflow cell, which goes through `qv_ovf`);
- every non-BINARY collation, and every function except LIKE and GLOB.

#### Statements that would gain

| statement | stock | what batches |
|---|---:|---|
| freshrss stats.entry_count_per_day | 24.6 ms | `date` range filter, CAST arithmetic, then GROUP BY through the sorter (with C1: a hash) |
| n8n executions.concurrent_count | 6.2 ms | text = constant, IN of two texts, IS NULL, count |
| ha statistics.compile_hourly.summary_mean | 1.3 ms | range filter, avg/min/max per group |
| chromium visit.history_count | 3.8 ms | count over a range |
| karakeep tags.list.by_usage | about 160 ms | SUM(CASE WHEN text = 'ai'), the text compare vectorised into a count over the bitmap |
| wakapi settings.user_agents | about 160 ms | text = parameter, text != '', min/max(time) per group |
| crowdsec metrics.alerts_count_per_scenario | about 140 ms | the outer scan's filters (the EXISTS probes stay scalar) |
| frigate events.summary_per_day | about 90 ms | date bucket + count |
| tautulli graphs.* | 87–90 ms | |
| goatcounter stats.* | 36–89 ms | |
| actual budget.sum_amounts_by_month | about 100 ms | range filter + sum per group |
| ClickBench | | 43 queries of filters and aggregates over one table (bench's 1M-row prefix); the ideal case |

- In wave 1: anki scheduler.deck_due_counts, atuin history.get_dups, firefox frecency.origin_threshold and zotero
  items.primary_data. These win already; batches would win more.
- **Not:** class A (no filter or aggregate to batch, and output is per row), class B (one row), joins through seeks
  (the inner side is one row per probe).

#### Expected gain

- **The ceiling (oracle).** RESULTS 5g put dispatch and decode at a few percent. The real ceiling comes from the work
  a batch removes per row:
  - a `Mem` write and read per column (16–56 bytes);
  - the node dispatch per opcode;
  - the branchy compare per filter.
- **Plan's own loop:** IR.md's measured region gains are 13 points on scans and filters with integers only. A batch
  executor that also takes text compares and replaces per-row AggStep with vector reductions should take the plan's
  own loop by 2–4× on filter + aggregate bodies. DuckDB and Vectorwise report 2–10× over tuple-at-a-time
  interpretation on such loops.
- **Whole statement:** the B-tree step and the header parse stay, about 30–50 % of these statements in the
  profiles. So expect **0.6–0.8 of stock** on filter + aggregate scans over more than 10k rows of one table, against
  0.89–1.03 today.
- **The heaviest wave-2 statements gain less from G1 alone.** Their time is in the GROUP BY sort (C1's) and in join
  seeks (§2 G): wakapi's filter + min/max is under a fifth of its run. G1 pays most on:
  - one-table scans with filters and aggregates (freshrss, n8n, ha compile_hourly, chromium history_count);
  - ClickBench, the most to gain (1.07× today);
  - C1's input once both exist (step 5 below).

#### Risk

- **Never-regress:**
  - **Speed:** a batch region adds a pass per column. On a filter that keeps almost every row and a body that outputs
    per row, it's pure overhead, which is why output bodies aren't batched.
  - **Small statements:** a region must have had about 1,000 iterations in its feedback before it's lowered to batches,
    so small statements never see one.
- **Exactness:**
  - integer arithmetic must check overflow per lane;
  - real sums stay scalar;
  - min/max ties keep the first row;
  - NULL compares need the three-valued jumps (SQLITE_JUMPIFNULL, NULLEQ) in the bitmap: a NULL row takes the "false"
    branch unless P5 says jump;
  - affinity conversions on a compare (text against an INTEGER-affinity column) aren't batched.
- **Effort:** the largest of the ideas here (about 1.5–2 k lines):
  - the region lowering;
  - the column arrays;
  - eight to ten kernels (int cmp, text eq/prefix, null test, count, int sum, int min/max, hash);
  - x86 and NEON variants, with a scalar fallback that is the reference;
  - a new differential test that runs every corpus statement through batches of 1, 7 and 256 rows.

#### How to stage it, so each step is measurable alone

1. **Columns into arrays, no SIMD.** Lower qualifying regions to "decode the batch by column, then run the existing
   nodes per row over the arrays instead of Mems".
   - **Measures:** the cache and decode effect alone.
   - **A/B:** freshrss entry_count_per_day, n8n concurrent_count, ha compile_hourly, chromium history_count,
     karakeep by_usage.
2. **Bitmap filters,** scalar loops the compiler can auto-vectorise (`-O2 -march=x86-64-v2` vectorises simple
   compare loops). Same five statements.
3. **Vector count, sum and min/max over the bitmap.** Same five, plus actual sum_amounts_by_month and wakapi
   user_agents.
4. **Text = constant, IN and prefix LIKE/GLOB kernels.** n8n, wakapi, karakeep, crowdsec, beets items_anyfield_flex.
5. **Batches feeding the sorter and the hash aggregation** (with C1 and C2): joplin folders, atuin all_with_count,
   jellyfin favorites.
6. **ClickBench 1M on the Xeon,** against stock and against step 3.

Each step's guards: one class A statement (books_table_columns), one point lookup (card.get_by_id), and kodi
movies.by_genre (a join, which must stay out of batches).

#### SIMD for ORDER BY and GLOB beyond regions

- C2's u64 prefixes make text ORDER BY a radix or integer sort, which is where SIMD helps sorting (a vectorised
  histogram pass).
- `GLOB 'abc*'` in a WHERE uses the same masked-prefix kernel as LIKE, case-sensitive.
- SQLite turns `x GLOB 'abc*'` on an indexed column into a range scan, so only non-indexed GLOBs reach the kernel.

**Result (columnar session): stopped at stage 1, no code.** Stage 1 needs a single-cursor region with a batchable body.
None of the nine heavy wave-2 statements has one:
- their main loops are an index range with DeferredSeek (actual, wakapi, frigate, tautulli, phoenix), joins
  (karakeep, dagster, goatcounter) or correlated subqueries (crowdsec);
- four have no region at all.

A census of all 1,301 corpus statements (a region dump at finalize) found 108 with a live region of 1,000+ rows. Only
28 of them have a G1-shaped body: one-table scans with a filter and a count or sorter input, 3–30 ms. In those, the
nodes are about 13 % of the statement. The record header walk is about 40 % (atuin history.count_active, x86
callgrind), and G1's design keeps that walk scalar.

The SIMD went into the header walk instead (below; dropped on the Xeon). The region dump and census scripts are described in the
session-notes folder (`columnar-g1.md`).

**Result (columnar session): a vector header walk, dropped on the Xeon** (branch `claude/columnar-hdrvec`, 3919a8f).
- **What it was:** a region whose body reads 8 or more fields before a branch (`RG_NEXTV`) walked each row's header
  16 one-byte serial types at a time (SSE2 / NEON).
  - A probe for bytes from 0x80 came first. A block was taken only where it covered 8 fields or more.
  - A multi-byte type was walked one field at a time, then the probe ran again.
  - A region whose rows took no block turned back into the plain Next.
- **x86 callgrind:** atuin count_active −12.7 %, screenpipe maintenance.count_by_machine −20.8 %, sixteen guards within
  0.25 %. Exact: regress checks it against the loop on 400,000 random headers, and the corpus check is clean.
- **Xeon box2** (exp1127–1130: main, change, main, change; 10 statements, 4 rounds; serve/stock):
  - Instructions fell as predicted: screenpipe 1.008 → 0.859, atuin 0.954 → 0.875, about −2.5 % over all ten.
  - Time didn't follow. atuin went 1.000 → 1.035 and 0.990 → 1.004; screenpipe 1.049 → 1.008 and 1.005 → 0.991.
  - The overall time geomean went +0.4 % and +1.4 %, within the 0.8 % between the two main runs.
  - The scalar walk was not on the critical path: the instructions it saved overlapped the B-tree step's memory
    stalls.
- **Not landed:** the Xeon decides, and it shows no time win.
- **Also dropped on the way:** putting the walk in qv_hdr for every caller. The test on every short walk cost
  datasette filtered_count 1.6–2.2 % of instructions. Headers with a long text early wasted the kernel: joplin folders
  +4.2 %, crowdsec count_since_24h +5.5 %.
- **What this says for G1:** the row decode isn't where these scans spend time on the Xeon. The page walk and its
  memory stalls are, which no columnar layout of the decoded values changes.

### G2. Typed slots between region nodes (IR.md step 4's "next")

**Mechanism:** region nodes read and write a flat array of unboxed values and a class byte, instead of 56-byte
Mems; Column → compare → AggStep never builds a Mem. pg-jit-study #1 estimated 5–15 % on qvm scan, filter and
aggregate loops.

**Helps:** what G1 doesn't take: bodies with ResultRow per row and a filter, like the class A members with a filter
(sends.find_by_user), joins' outer loops, and the region of every wave-2 statement before G1 lands.

**Expected gain:** 3–10 % on scans with filters. This is the same value G1 has, without the batch.

**Risk:** low. The nodes' generic paths stay.

**A/B:** sends.find_by_user, n8n concurrent_count, wakapi user_agents, freshrss entry_count_per_day, joplin
folders.

**Result (columnar session): tried, dropped at its first step** (branch `claude/columnar-g2`, 39fd80a).
- **Where the Columns go:** in the corpus census, live regions (1,000+ rows) run about 4 Column nodes a row. Only about
  0.6 of them feed a compare (0.34 of those are an integer Column feeding an integer compare). Most feed MakeRecord,
  ResultRow or a function, which read Mems anyway.
- **The step:** `RG_COLCMPI` fuses the commonest chain, an integer Column and the integer compare that reads its
  register, into one node: no dispatch and no reload between them.
- **x86 callgrind** against e74c445 (with D1): at most −0.24 % on the statements that run the pair most (joplin
  previews −0.24 %, anki deck_due_counts −0.13 %, chromium significant_enumerator −0.08 %, datasette filtered_count
  level). The guards are level.
- **Not run on the Xeon:** that is a third of main's own run-to-run difference on box2 (0.8 %, exp1127/1129). The
  vector header walk also showed these loops don't turn saved instructions into time.
- **A full typed-slot version:** it would unbox the same few compare inputs, and the other Columns' consumers would
  still need Mems. Its A/B list mostly has no live region: only sends.find_by_user and joplin folders do. n8n and
  wakapi have DeferredSeek bodies, and freshrss's region turns itself off on Cast.
- **What would help these statements:** regions over their loops (IR.md step 5), not unboxing.

## 4. Ranking

Expected gain × breadth ÷ effort. Gain is in points of stock instructions on the statements it hits. Breadth is how
many corpus statements it moves. Effort is lines and risk.

| rank | idea | gain | breadth | effort | why here |
|---:|---|---|---|---|---|
| 1 | **B1** size gate for point lookups | 4–30 pts to parity | ~75 hot + ~45 prep under 20 µs | ~50 lines | the parity rule's biggest failure, for almost no code |
| 2 | **B2** adapt back-off + per-text verdict | 3–5 pts | 85 hot + 134 prep unserved-and-slower | ~100 lines | removes the floor under every parked statement |
| 3 | **C1** hash GROUP BY, then sort the groups | 15–50 pts (wins) | the 92 slower sort/group statements (with C2) + `groupby` 147 + wave-2 analytics | ~300 lines | the largest measured gain (wakapi: about half its run is the sort); turns level heavy statements into wins |
| 4 | **D1** text compares in regions | 2–11 pts | `full-scan` 310, `in-list` 181, n8n, calibre | ~80 lines | one node kind, exact, many statements |
| 5 | **A1** static "nothing to win" at lift | 2–13 pts to parity | ~21 big output scans (corpus7 proxy) | ~60 lines | output-bound scans can't win; stop paying for them |
| 6 | **D2** lower()/upper() in line + LIKE fold | 20–25 pts on hits | `like` 85 (the LOWER shapes) | ~80 lines | a known pattern (73f07ed, 74d9a50) |
| 7 | **E1** short ranges demote to qvm | 10–20 pts | ~5–10 qcg ranges | ~30 lines | d960693's rule, one step further |
| 8 | **G1** columnar batches + SIMD (staged) | 20–40 pts (wins) | wave-2 analytics, ClickBench, aggregates over 10k+ rows | ~1.5–2 k lines | the biggest wins in the corpus, but the most work; stage 1–3 first |
| 9 | **C2** normalised text-key prefixes | 5–15 pts | text ORDER BY, top-N, C1's group sort | ~250 lines | multiplies C1 and G1 step 5 |
| 10 | **C3** late materialisation for wide sorts | 10–15 pts, more on spills | a handful in the corpus; TPC-H, ClickBench spills | ~250 lines | big on few statements |
| 11 | **A2** zero-copy hand-out | 2–5 pts | served statements with >100 rows | ~200 lines, care | what A1 leaves |
| 12 | **G2** typed slots between nodes | 3–10 pts | most qvm loops | ~1 k lines | largely subsumed by G1 where G1 applies |
| 13 | **B3** cheaper qv_exec set-up | 2–5 pts | served lookups B1 keeps | ~100 lines | small, after B1 |

**Order of work:**
- **Ranks 1, 2, 4 and 5** are the never-regress items. They are cheap and they take corpus7's slower column from 229
  towards about 120.
- **Ranks 3, 6 and 8** are where the wins grow. C1 comes first among them because the wave-2 profiles put the GROUP
  BY sort, not filters, at the top of the heaviest statements.
- **G1 is the largest bet.** Step 1 (columns into arrays) answers within a day whether it's worth the rest.

## 5. Not measured here

- **Prep-mode function profiles** for the small statements: only their totals (§2 B).
- **atuin history.all_with_count** at HEAD: 300 ms stock, too slow for callgrind in this round.
- **Wave 2's other 11 apps** (dagster, phoenix, tautulli, goatcounter, netalertx, mlflow, optuna, prefect, screenpipe,
  koreader, grocy, technitium). grocy's 14 s views and koreader's delete are `heavy`, out of quick rounds.
- **Times on the Xeon:** every ratio here is instructions on a local x86 build. Class A's and B's losses were time
  losses in corpus7 too (1.05–1.79). Whether G1 does better than its instruction count on the Xeon depends on memory
  stalls, which callgrind doesn't see.
