# Benchmarks: where turbo is faster, and where it isn't

Turbo's goal has two halves, and every number below is read against both:
1. **Parity on small queries.** Point lookups, short statements, writes, and anything turbo can't specialise well
   should run at **≤ 1.02× stock SQLite**. Turbo gets there by handing those statements back to SQLite's own
   interpreter, not by averaging them against wins elsewhere.
2. **Big wins on complex queries:** window functions, CTEs, compound selects, GROUP BY and aggregates, top-N, joins
   with expressions.

All ratios here are **turbo / stock**, so below 1 means turbo is faster. Unless a section says otherwise, they come
from one x86 Xeon box (described under [How it was measured](#how-it-was-measured)). Local Apple-silicon timings are
left out on purpose: they don't predict the Xeon well enough to decide anything.

**The harness:** every number here was produced with **sqlgauntlet**, turbo's benchmark and test harness, which
lives in its own project (to be published). [Reproducing](#reproducing) says what it runs.

## Summary

| run | statements | hot time | hot instructions | prep time | prep instructions |
|---|---:|---:|---:|---:|---:|
| corpus9, wave 1 (apps' everyday statements) | 802 of 803 | **0.953** | 0.970 | **0.979** | 0.987 |
| corpus9, wave 2 (apps' analytics statements) | 490 of 498 | **0.999** | 0.975 | **1.011** | 0.979 |
| both waves | 1,292 | 0.970 | 0.972 | 0.991 | 0.984 |
| steady-state rerun of 120 slow-looking statements, executions 21–40 | 120 | 0.981 (median-based), 0.987 (mean-based) | 1.006 | 0.994 (median), 0.991 (mean) | 1.005 |

- **Geomeans:** each is over statements, of each statement's own serve / stock ratio. The prep columns prepare,
  step and finalize the statement on every execution, so they include prepare's cost.
- **"of 803":** statements are left out when stock and turbo returned different results between runs. Wave 1 drops
  `memos.upsert_reaction`, a write turbo never serves, whose result differs from run to run in both arms. Wave 2
  drops 8 grocy statements: their data is anchored to the current date, and the two arms' databases were built at
  different times. A local check on one database finds all 26 grocy statements identical.
- **Typical statement:** level. The median statement is at 0.99–1.00 in every mode. The geomeans move because of a
  tail of statements that are 10–35 % faster, and a smaller tail that is a few per cent slower.
- **What to expect:** a mixed application workload should see a few per cent overall. Workloads dominated by the
  shapes in [Where turbo wins](#where-turbo-wins) see 10–30 %, and some statements see more. Small point lookups
  that are prepared every time can be up to about 4 % slower.

## How it was measured

**The box and the build:**
- **CPU and kernel:** an Intel Xeon Platinum 8260 (Cascade Lake), one vCPU under KVM, 2 GB of RAM, 16 MB of L3.
  Ubuntu's 6.8.0-117 kernel.
- **Compiler:** clang 18.1.3, `-O2 -march=native -mbranches-within-32B-boundaries`. The last flag avoids
  Cascade Lake's JCC-erratum penalty, which otherwise moves timings by up to 15 % from edit to edit
  (RESULTS §13).
- **SQLite:** 3.54.1 in both arms, with the same compile-time options. Both arms are built from the same
  amalgamation. "Stock" is that amalgamation unpatched. "Turbo" is it patched by `qc/patch.py` with qc
  included, serving through `sqlite3_step` with the shipped defaults (adapt on, streaming on).
- **Corpus9:** qc at `ae88c7e` (2026-10-31).
- **Steady-state rerun and margin sweep:** qc at `ceb2c29` (2026-10-31). `main` is a few commits past that.

**The workload:**
- **Statements:** 1,301 statements taken from 44 open-source applications. Each comes with its source location and
  pinned commit, the app's schema, and deterministic synthetic data at the app's realistic shape. They live in
  [sqlgauntlet](https://github.com/public/sqlgauntlet)'s `corpus/` (this repository's `bench/corpus/` until it moved,
  at 0c63afa).
  - **Changed since:** these runs include screenpipe's 30 statements (wave 2), taken from a commit under its current
    licence, which doesn't allow redistribution. The repository now has 31 statements taken from screenpipe's last
    MIT-licensed commit instead. They haven't been benchmarked yet, so the corpus in the repository (1,307
    statements) isn't exactly the one measured.
  - **Wave 1** is 803 everyday statements from 27 applications: page loads, lookups, syncs and writes.
  - **Wave 2** is 503 statements added later from 17 more applications, mostly analytics and reporting. Five were
    too slow for a round and were left out.

**Two modes:**
- **hot:** prepare once, then execute repeatedly on the same handle. Each timed execution steps to the end and
  resets.
- **prep:** each timed execution prepares, steps and finalizes a fresh handle. This is how code that doesn't keep
  statements open, and ORMs without a statement cache, use SQLite.

**Counts and metrics:**
- **Executions:** one untimed execution first, then executions until a 30 ms budget per statement and mode is spent.
  That's at least 10 and at most 200.
- **Metrics:**
  - wall time, as the mean per execution;
  - user-mode instructions and cycles, from `perf_event_open` (root on the box only for the counters).
- **Ratios:** per statement, serve / stock; the tables give the geomean over statements.

**Runs:**
- **One arm per run.** A run builds and runs one arm for a group of applications, and the stock and turbo runs
  alternate. For each project the latest pair of runs counts (exp1202–1223).
- **Correctness first.** Every statement's row count and an order-sensitive hash of every value are compared
  between arms before any time is reported.

**Caveats you need to read the numbers right:**
- **Single-round time on microsecond statements is noisy.** One round's time ratio on a 10 µs statement can swing
  ±50 % while its instructions stay flat. Read instructions as the reliable signal for small statements, and time
  as the deciding one for large statements.
- **Arms differ slightly even when they run the same code.** Writes are never served by turbo, and their
  instructions are 1.000–1.004 of stock's. Their time still reads 0.975–0.994. So a geomean time difference of
  2–3 % between arms is within the setup's bias, in both directions.
- **Learning phase.** About half of corpus9's statements (649 of 1,292 hot, 661 prep) ran fewer than 22 times,
  because each takes more than about 1.2 ms. That's every statement over ~1.2 ms stock. adapt, turbo's measured
  tier choice, needs about 20 executions to reach its verdict, and half of those run on SQLite's interpreter (see
  [ARCHITECTURE.md](ARCHITECTURE.md#adapt-measure-then-keep-or-park)). For those statements corpus9 mostly
  measures the learning phase, not what turbo settles on. The [steady-state rerun](#steady-state-executions-2140)
  counts only executions 21–40.

## Where turbo wins

Corpus9, both waves, by the shape of the statement. The shapes overlap: one statement can be a GROUP BY over a
three-way join with a CTE.
- **Wins / losses:** "clear wins" are statements at both time < 0.90 and instructions < 0.95. "Clear losses" are at
  both > 1.02.
- **Two subsets:** the first table has every statement. The second has only those with 22 or more executions per
  mode (stock under about 1.2 ms), so most of their executions come after adapt's verdict.

### Every statement (1,292 compared)

| shape | n | hot time | hot instr | hot time p10 / p50 / p90 | hot clear wins / losses | prep time | prep instr | prep clear wins / losses |
|---|---:|---:|---:|---|---:|---:|---:|---:|
| Window functions | 38 | **0.904** | 0.908 | 0.72 / 0.94 / 1.05 | 15 / 1 | **0.926** | 0.911 | 11 / 1 |
| Recursive CTEs | 16 | **0.826** | 0.909 | 0.26 / 0.99 / 1.26 | 5 / 2 | **0.839** | 0.962 | 4 / 1 |
| CTEs (any) | 89 | **0.909** | 0.934 | 0.66 / 0.98 / 1.15 | 25 / 6 | **0.931** | 0.956 | 15 / 4 |
| UNION / INTERSECT / EXCEPT | 79 | **0.915** | 0.958 | 0.73 / 1.01 / 1.19 | 14 / 11 | 0.966 | 0.987 | 7 / 9 |
| GROUP BY | 297 | 0.950 | 0.946 | 0.85 / 0.98 / 1.10 | 47 / 20 | 0.976 | 0.954 | 36 / 20 |
| Aggregates | 428 | 0.947 | 0.947 | 0.83 / 0.98 / 1.09 | 64 / 35 | 0.980 | 0.955 | 52 / 38 |
| Subqueries (any) | 492 | 0.951 | 0.961 | 0.81 / 0.98 / 1.11 | 68 / 45 | 0.978 | 0.973 | 47 / 39 |
| Correlated subqueries | 184 | 0.960 | 0.963 | 0.82 / 0.97 / 1.08 | 26 / 9 | 0.995 | 0.972 | 16 / 13 |
| ORDER BY … LIMIT (top-N) | 381 | 0.951 | 0.963 | 0.80 / 0.99 / 1.08 | 55 / 29 | 0.984 | 0.977 | 34 / 33 |
| Joins of 3+ tables | 527 | 0.959 | 0.966 | 0.82 / 0.99 / 1.11 | 62 / 51 | 0.984 | 0.978 | 45 / 56 |
| Full scans | 506 | 0.963 | 0.964 | 0.82 / 0.99 / 1.11 | 71 / 52 | 0.979 | 0.972 | 57 / 49 |
| LIKE | 127 | 0.967 | 0.967 | 0.88 / 0.98 / 1.07 | 17 / 5 | 0.982 | 0.972 | 13 / 8 |
| COLLATE / NOCASE | 62 | 0.966 | 0.973 | 0.82 / 0.99 / 1.12 | 6 / 2 | 0.994 | 0.985 | 4 / 5 |
| String functions | 164 | 0.970 | 0.953 | 0.85 / 1.00 / 1.07 | 27 / 11 | 0.985 | 0.964 | 18 / 10 |
| DISTINCT | 97 | 0.977 | 0.977 | 0.84 / 0.98 / 1.13 | 10 / 3 | 1.029 | 0.980 | 8 / 9 |
| IN lists | 338 | 0.977 | 0.975 | 0.85 / 1.00 / 1.18 | 31 / 44 | 1.007 | 0.992 | 16 / 51 |
| ORDER BY (full sort, no LIMIT) | 275 | 0.990 | 0.971 | 0.82 / 1.00 / 1.12 | 32 / 32 | 0.993 | 0.976 | 30 / 38 |
| JSON functions | 75 | 0.987 | 0.989 | 0.90 / 0.99 / 1.09 | 4 / 5 | 1.000 | 0.994 | 2 / 5 |
| Date functions | 77 | 1.000 | 0.975 | 0.90 / 0.99 / 1.10 | 4 / 7 | 1.017 | 0.976 | 4 / 5 |
| FTS | 31 | 0.995 | 0.998 | 0.92 / 0.99 / 1.14 | 0 / 0 | 1.001 | 0.998 | 0 / 0 |
| Virtual tables | 57 | 0.990 | 0.997 | 0.91 / 0.99 / 1.14 | 0 / 0 | 0.994 | 0.997 | 0 / 0 |
| Writes (INSERT / UPDATE / DELETE / upsert) | 182 | 0.990 | 1.002 | 0.85 / 0.99 / 1.16 | 0 / 1 | 0.994 | 1.000 | 0 / 0 |
| **All** | 1,292 | **0.970** | 0.972 | 0.82 / 0.99 / 1.12 | 133 / 127 | **0.991** | 0.984 | 94 / 158 |

### Statements with 22 or more executions (stock under about 1.2 ms)

| shape | hot n | hot time | hot instr | prep n | prep time | prep instr |
|---|---:|---:|---:|---:|---:|---:|
| Window functions | 10 | **0.821** | 0.907 | 10 | **0.891** | 0.918 |
| Recursive CTEs | 9 | **0.712** | 0.875 | 9 | **0.751** | 0.969 |
| CTEs (any) | 30 | **0.774** | 0.895 | 28 | **0.847** | 0.957 |
| UNION / INTERSECT / EXCEPT | 32 | **0.781** | 0.919 | 32 | 0.927 | 0.994 |
| GROUP BY | 62 | **0.839** | 0.934 | 56 | 0.918 | 0.975 |
| Aggregates | 118 | **0.869** | 0.920 | 110 | 0.939 | 0.946 |
| Subqueries (any) | 165 | 0.894 | 0.947 | 154 | 0.961 | 0.983 |
| Joins of 3+ tables | 168 | 0.906 | 0.956 | 159 | 0.966 | 0.994 |
| String functions | 48 | 0.922 | 0.933 | 47 | 0.972 | 0.973 |
| Full scans | 168 | 0.924 | 0.952 | 158 | 0.956 | 0.974 |
| ORDER BY … LIMIT (top-N) | 162 | 0.933 | 0.961 | 159 | 0.989 | 0.994 |
| COLLATE / NOCASE | 24 | 0.939 | 0.959 | 23 | 0.997 | 0.998 |
| LIKE | 32 | 0.951 | 0.968 | 30 | 0.992 | 0.986 |
| IN lists | 161 | 0.952 | 0.967 | 153 | 1.000 | 1.002 |
| JSON functions | 34 | 0.970 | 0.984 | 33 | 1.004 | 0.997 |
| Correlated subqueries | 54 | 0.972 | 0.958 | 49 | 1.010 | 0.982 |
| DISTINCT | 30 | 0.984 | 0.972 | 29 | 1.109 | 0.983 |
| ORDER BY (full sort, no LIMIT) | 101 | 1.010 | 0.976 | 98 | 1.002 | 0.991 |
| Date functions | 10 | 1.042 | 1.001 | 10 | 1.011 | 1.010 |
| Writes | 120 | 0.975 | 1.004 | 118 | 0.978 | 1.001 |
| **All** | 643 | **0.956** | 0.970 | 631 | **0.985** | 0.994 |

### What the tables say

**Wins, in order of size:**
1. **Recursive CTEs, CTEs, window functions and compound selects** (UNION / INTERSECT / EXCEPT): 0.71–0.82× hot
   once adapt has settled, 0.90–0.92× over every statement. These programs spend their time in the VDBE itself
   (coroutines, ephemeral tables, window steps), which is what qvm replaces.
2. **GROUP BY and aggregates:** 0.84–0.87× hot past the learning phase, about 0.95× overall. The parts of qvm
   aimed at these are hash sets for DISTINCT aggregates, native `sum`/`avg`/`min`/`max`, and loop regions that
   decode each row once. These measurements don't split the gain between them.
3. **Subqueries, multi-way joins, full scans and string functions:** 0.89–0.92× hot past the learning phase, about
   0.95–0.97× overall.

**Level (within about 3 %):**
- top-N, LIKE, COLLATE / NOCASE compares, IN lists, JSON and date functions and full sorts, in both modes;
- the big scans and joins over 10 ms (0.975 hot, 0.980 prep): their time is in B-tree page reads and record decoding,
  which turbo does about as the interpreter does.

**Not served at all, so level by construction:**
- **FTS and virtual-table statements:** turbo refuses virtual-table cursors.
- **Writes:** turbo serves only read-only statements. Their instructions are 1.000–1.004 of stock's. That's the
  cost of the hooks when nothing is served.

**Losing, or parked back to stock:**
- **Small point lookups, prepared every time.** Reads under 20 µs in prep mode are at 1.039× time and 1.027×
  instructions, with 21 clear losses among 65. On a 5–20 µs statement, turbo's per-statement work (looking up a
  cached plan, and its first executions before adapt parks it) costs more than any plan can save. Hot, the same
  band is at 0.980.
- **Prepare-dominated statements in general.** In prep mode the 20–100 µs band has 46 clear losses and 4 clear
  wins. Wins in prep mode are smaller in every shape than hot.
- **DISTINCT in prep mode** reads 1.03–1.11× in time, but its instructions are 0.98. That is a time-only effect
  on fewer than 100 statements, not a confirmed loss.
- **Date functions and full sorts** are level to slightly behind (1.00–1.04). `docs/TOUGH_PROBLEMS.md` §2 C
  describes text sorts and big-record sorts.

### By statement size (stock time per execution)

Each mode is banded by its own stock time, so the counts differ between modes.

| reads, stock time | hot n | hot time | hot instr | prep n | prep time | prep instr | prep clear wins / losses |
|---|---:|---:|---:|---:|---:|---:|---:|
| < 20 µs | 196 | 0.980 | 0.963 | 65 | **1.039** | **1.027** | 1 / 21 |
| 20–100 µs | 102 | 0.962 | 0.981 | 180 | 0.999 | 1.009 | 4 / 46 |
| 0.1–1 ms | 192 | **0.935** | 0.964 | 232 | 0.981 | 0.983 | 21 / 15 |
| 1–10 ms | 271 | 0.972 | 0.976 | 278 | 0.996 | 0.979 | 19 / 35 |
| ≥ 10 ms | 349 | 0.975 | 0.960 | 355 | 0.980 | 0.960 | 49 / 41 |

In the 1–10 ms band, the 33 hot statements with 22 or more executions are at **0.859** time (0.898 instructions).
The band's 0.972 over all its statements is mostly learning-phase executions.

## Steady state: executions 21–40

**Which statements:** the 120 statements that looked slow in corpus9 (over 1.02× in some mode) but had run fewer
than 22 times there, so their corpus9 figures were learning-phase figures. They are 38 applications' statements.

**How they ran:** box1, qc `ceb2c29`, exp1261–1265. Stock and turbo ran in the same process run, alternating, for
40 executions each, in both modes. **Only executions 21–40 count**, the ones after adapt's verdict. Per statement,
the ratio is the median execution's (or the mean's) time, and the mean's instructions and cycles.

| | statements | time (median-based) | time (mean-based) | instructions | cycles | over 1.02× (time) | under 0.98× (time) |
|---|---:|---:|---:|---:|---:|---:|---:|
| hot | 120 | **0.981** | 0.987 | 1.006 | 0.992 | 43 | 52 |
| prep | 120 | **0.994** | 0.991 | 1.005 | 1.001 | 40 | 56 |

- **Results:** every statement's rows and hash match stock in both modes.
- **Verdicts:**
  - **Hot:** 55 statements were kept (every post-verdict execution served), 64 were parked or refused (none served),
    and 1 was mixed.
  - **Prep:** 50 kept and 70 parked or refused.
  - **Parked and refused statements** run at 0.993 hot and 0.994 prep: SQLite's own interpreter plus the hooks'
    cost.
  - **Kept statements** are at 0.965 hot (median-based) and 0.995 prep.
- **Big wins that held in steady state:**

  | statement | stock | hot | prep |
  |---|---:|---:|---:|
  | grocy `recipes.selected_positions` | 161 ms | **0.66** | |
  | grocy `recipes.positions_not_nested` | 171 ms | **0.68** | |
  | grocy `stock.overview` | 76 ms | **0.72** | |
  | uptime-kuma `client.latest_heartbeat_per_monitor` | 1.6 ms | **0.79** | **0.86** |
  | koreader `stats.days_of_month` | 1.9 s | **0.84** | **0.85** |
  | crowdsec `alerts.count_since_24h` | 17 ms | 0.86 | |
  | frigate `review.summary_time_range` | 4.4 ms | | 0.87 |

- **What still loses:**
  - **Kept plans inside adapt's margin.** adapt keeps a plan unless the interpreter's fastest run beats the plan's
    fastest by more than its margin. These runs used 1.03, so a plan up to 3 % slower stayed (`main` now uses
    0.98; see below). In hot mode 12 kept statements were over 1.02×, mostly 1.04–1.11 (wakapi
    `activity.populate_items_per_day_cross_join` 1.11, zotero `duplicates.creators` 1.07, zotero
    `items.load_item_data` 1.06).
  - **Parked statements over 1.02×.** These run on stock's interpreter, so their excess is the hooks' fixed cost
    plus noise. The worst is grafana `unified.resource_list` at 1.33× time on 1.00× instructions, which is a
    time-only reading.

## The adapt margin

**The question:** what margin adapt should use. The sweep compared margins 1.03 (the default then), 1.00 and
0.98. At 0.98, a plan is kept only if it beats the interpreter by at least 2 %.

**How it ran:**
- **Statements:** 209 statements, all of seven whole projects: darktable, grafana, netalertx, phoenix, prefect,
  tautulli and wakapi. That's a chosen set, not the corpus.
- **Box and code:** box2, qc `ceb2c29`.
- **Arms:** stock and the three margins in each run, interleaved, 40 executions each, in both modes. Executions
  21–40 count. Sweep runs exp1266–1271.

Per statement-mode (209 × 2 = 418):

| margin | cycles geomean | hot time (median-based) | prep time (median-based) | kept | kept but over 1.02× in cycles |
|---|---:|---:|---:|---:|---:|
| 1.03 (then the default) | 0.967 | 0.946 | 0.983 | 237 | **51** |
| 1.00 | 0.965 | 0.941 | 0.970 | 206 | 24 |
| 0.98 | **0.952** | **0.926** | **0.970** | 173 | **13** |

- **The confirmation:** a check of 0.98 alone against stock on the same 209 statements (exp1272–1277, 2 rounds
  each, arm order alternating). It gives 0.952 in cycles, 0.936 hot time and 0.972 prep time, with 11 kept
  statement-modes over 1.02×.
- **Results:** identical to stock in every arm.
- **Reading:** a stricter margin parks the plans that were winning by too little to be worth their risk. It costs
  nothing overall, and it cuts the kept-but-losing statements by about three quarters.
- **Status:** 0.98 is the default since `1a50b2d`. `QC_ADAPT_MARGIN=1.03` at run time gives the old behaviour.

## Other benchmarks (older commits)

These ran before the corpus existed, on the same Xeon, through sqlgauntlet's drop-in harness. They predate
`73a78a9`, `6811c02`, `05821a2`, per-connection thread safety, and about a hundred other commits. **They have not
been rerun on `main`**, so read them as history, not as current figures. The speedtest1, TPC-H, ClickBench and
SQLancer harnesses are part of sqlgauntlet.

| benchmark | commit | rounds | turbo / stock | notes |
|---|---|---:|---:|---|
| TPC-H SF0.1, 22 queries | `905fb05` | 3 | **1.000** (geomean) | All in qvm. Q18 about 1.10, Q12 1.07. Rows identical. |
| ClickBench, first 300k rows of `hits` | `905fb05` | 2 | 1.041 (geomean) | Per-query deltas under ~20 % are noise on this setup. Q04 / Q05 (count DISTINCT) 0.73–0.79. |
| speedtest1 `--size 100`, total time | `dcc102e` | 6 | **0.966** [0.931, 1.001] | 95 % interval over rounds. main/520 (DISTINCT) 0.42×. Its losers: main/320 1.12, fp/150 1.11, star/130 1.07. |
| 18 small statements on TPC-H, autocommit | `dcc102e` | 6 | 1.017 [0.971, 1.069] time | Point lookups were 1.158× in instructions in autocommit and 0.769× inside one transaction. Later commits (the B1 size gate, the cheaper read transaction) target exactly this. |

**qc's own API on a single hand-picked query.** This is the best case, not a typical one. The feed query of the
original application (20 rows, 3 tables, a correlated `count(*)` per row) was run hot on the Xeon through
`sqlite3_qc_exec`, with the plan writing the JSON body. It took 23.8 µs in SQLite's interpreter and 5.7 µs with
qc. A post-by-id lookup took 1.39 µs and 0.62 µs. These were measured in cursed-http, the HTTP server qc was first
built for, with clang 19. RESULTS §5 follows qc's development on the same query.

## When to use turbo, and when not to

**Use it when:**
- **Your app runs a set of read queries over and over:** dashboards, reports, feeds, sync endpoints, analytics
  pages. Turbo needs about 20 executions of a statement to decide whether to keep its plan.
- **The statements do real work in the VDBE:** CTEs (recursive or not), window functions, compound selects,
  GROUP BY and aggregates, multi-way joins with expressions, subqueries. These are 10–30 % faster past the learning
  phase, and a few are 30 %+ faster.
- **Your code keeps prepared statements open** (hot mode), or uses a statement cache: Python's `sqlite3` caches
  statements by default, as do most ORMs' drivers. Prepare-each-time gains are smaller.

**Expect no difference when:**
- **The work is in the B-tree, not the VDBE:** big scans and joins over 10 ms, FTS, virtual tables.
- **The workload is mostly writes.** Turbo serves only reads. Writes cost what they cost in stock SQLite.

**Don't use it, or expect a small loss, when:**
- **The workload is tiny point lookups prepared once per call:** under 20 µs, about 1.04× in prep mode.
  Statements that are prepared once and run hot are level.
- **Each distinct statement runs only a handful of times.** For its first ~20 executions turbo alternates its
  plan with SQLite's interpreter and times both, so a statement that never gets past that pays for the learning.
- **You need `sqlite3_stmt_status` counters, or a trace or progress callback, on served statements.** See
  [Known limitations](../README.md#known-limitations).

## Reproducing

**sqlgauntlet** ([public/sqlgauntlet](https://github.com/public/sqlgauntlet), private for now) holds the corpus and
the harness that run these benchmarks: the driver, the interleaved arms, the reports, TPC-H, ClickBench,
speedtest1 and SQLancer. `make gauntlet` runs it against this working tree (`scripts/gauntlet.sh`). It clones
sqlgauntlet at the commit the script pins, builds turbo from this checkout, and compares it with stock SQLite 3.54.1:

```bash
make gauntlet
```

```bash
make gauntlet MODE=speed GAUNTLET="--rounds 3 --exec-lines"
```

```bash
make gauntlet GAUNTLET="--corpus build/sqlgauntlet/build/workloads/tpch-sf0.1"
```

- **The first** checks every statement's rows against SQLite.
- **The second** times both arms, interleaved, per execution.
- **The third** runs TPC-H, after `python3 build/sqlgauntlet/workloads/tpch/make.py 0.1`.
- **Your own checkout:** `SQLGAUNTLET_DIR=<checkout>` uses it as it is instead of the pinned clone.
- **More arms:** turbo's switches go in `ARMS`, e.g. `ARMS="sqlite turbo vm=turbo:QC_VM_ONLY=1"`.

**What changed since these figures were measured:**
- **The harness:** they were measured with turbo's own `bench/corpus/corpus.c`, which is now sqlgauntlet's driver.
  On the full corpus, its lines are identical to that driver's for both arms (sqlgauntlet's `tools/identity.py`).
- **The Xeon runs:** these went through cursed-scratchpad's broker. Their payloads aren't part of sqlgauntlet.
- **Decisions:** wall times on a laptop are a data point. Decisions use Linux instruction counts, with same-run
  interleaved arms.

**This repository** keeps `make corpus`, `make bench`, `make stock-bench` and the differential tests (`make test`,
`regress`, `qcache`, `topn`, `threads`, `stock`, `lean-oracle`). None of them needs sqlgauntlet.

**Provenance of the figures above:**
- **Runs:** the broker experiment ids (exp1202–1223, exp1261–1277) and the qc commits are given with each table.
- **Corpus9:** each run was one arm and a group of applications, with a 30 ms budget per statement and mode.
- **Steady-state and margin runs:** each run recorded one line per execution, so that executions 21–40 could be
  selected.

Times from a laptop are useful for finding problems, not for claiming speed-ups.
