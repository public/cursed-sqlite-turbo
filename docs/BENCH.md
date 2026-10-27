# External tests and benchmarks

Four outside sources, run against three arms of the same SQLite 3.54.1 build options:
- **stock:** the plain amalgamation;
- **turbo:** qc with plans first (specialised plan, then loop plan, then qvm);
- **qvm:** the same build with `QC_VM_ONLY=1`, every lifted statement through qvm.

A fast wrong answer is worthless, so every benchmark checks that the arms return the same rows before it reports a
time.

## How turbo is plugged in: `bench/qc_serve.c`

The benchmarks and SQLancer are unmodified SQLite programs: speedtest1, a query runner, and SQLancer through
sqlite-jdbc. `bench/build-sqlite.sh <variant> <dir>` makes one self-contained translation unit, `<dir>/sqlite3.c`,
that links in place of the amalgamation:

| variant | what it is |
|---|---|
| `stock` | the amalgamation, unchanged |
| `serve` | `qc/patch.py --step-hook`, `sqlite3_reset` and `sqlite3_finalize` renamed `*_orig`, then `qc.c` and `bench/qc_serve.c` appended |
| `diff` | `qc/patch.py --step-hook`, then `qc.c` and `tests/tcl_qc.c` appended (the TCL suite's differential hook) |

How `serve` runs a statement:
- **Start:** when a read-only statement with result columns starts on a connection with nothing else running, it is
  lifted once per handle (`sqlite3_qc`).
- **Run:** `sqlite3_qc_exec` executes it. In autocommit mode this happens inside `BEGIN … COMMIT`, since qc needs a
  transaction; trace and authorizer callbacks are off while it runs.
- **Rows:** qc's rows are copied and handed out through the statement's own result row. `sqlite3_column_*` read them,
  and the VDBE program never runs.
- **Refusal or fallback:** the statement is stepped by SQLite as before.

`QCS_STATS=<file>` writes totals at exit, plus one line per SQL text: executions, tier, served, fallbacks and why,
refusals and why. `qcs_info()` gives a program the same information for one handle; `bench/qrun.c` reports it per
query.

**Fallback cost.** A fallback here means qc ran and gave up, and then SQLite runs the statement from the start. A
fallback that comes late (after a scan) costs the scan twice. That is the main finding below.

## Layout and running

All of it runs in `bench/docker.sh`: Debian bookworm pinned by digest, on CPUs 8–11 only. Data lives in the Docker
volume `cursed-turbo-bench-data`. Datasets, jars and binaries never enter the repo (`build/`, `third_party/`).

| | |
|---|---|
| `bench/speedtest1/run.sh [rounds]` | SQLite's `test/speedtest1.c` from the pinned source tree, `--verify --size 100`, arms alternated |
| `bench/tpch/run.sh [SF] [rounds] [reps]` | dbgen (gregrahn/tpch-kit, pinned, SHA-256-checked), `load.c`, the 22 queries in `queries.sql` |
| `bench/clickbench/run.sh [rows] [rounds] [reps]` | ClickBench's `sqlite/` entry (pinned commit) on a checksummed prefix of `hits.csv` |
| `bench/compare.py <dir>` | per-query table: rows, ms per arm, ratios, executor, same rows across arms and rounds |
| `bench/xeon/payload.sh` | a broker payload for the Xeon: one workload, one arm, one round |
| `tests/sqlancer/build.sh` | SQLancer (pinned commit, Maven, strict checksums) and sqlite-jdbc 3.49.1.0's JNI library rebuilt for each variant |
| `tests/sqlancer/campaign.sh [s] [jobs]` | arms × oracles, then `summarise.py` |

```bash
bench/docker.sh sh bench/speedtest1/run.sh 3
```
```bash
bench/docker.sh sh bench/tpch/run.sh 0.1 3 3
```
```bash
bench/docker.sh sh bench/clickbench/run.sh 1000000 3 2
```
```bash
bench/docker.sh sh -c 'sh tests/sqlancer/build.sh && sh tests/sqlancer/campaign.sh 600 4'
```

> **Correction (speedtest1 per-test rows):**
> - **What went wrong:** speedtest1's default testset in 3.54.1 is `mix1`. It runs main, orm, cte, json, fp,
>   parsenumber, star and app (70 tests), whose test numbers repeat. Until this fix, the summaries keyed tests by
>   number alone, so per-test rows in the tables below mixed different tests that share a number. The totals were
>   not affected.
> - **Which tables are right:** tests are keyed `testset/number` from here on. The 905fb05 map and everything after
>   it use the corrected keys. The older per-test speedtest1 tables keep their totals, but their rows are superseded.

## Win/loss map by query shape (2026-10-27)

**Question:** where turbo wins big, where it's at parity, and where it loses.

**The data:**

| source | where | build | how turbo is plugged in |
|---|---|---|---|
| speedtest1 | Xeon, 3 rounds | c3ebcb0 | drop-in (bench/qc_serve.c, autocommit) |
| TPC-H SF0.1 | Xeon, 3 rounds | spill-fix snapshot | drop-in |
| ClickBench, first 300k rows | Xeon, 2 rounds | spill-fix snapshot | drop-in |
| the repo's corpus | Xeon (RESULTS §6, §7 and §16) | | embedded: `sqlite3_qc_exec` on reused statements in a transaction, hot |
| Gitea | Xeon | | drop-in |
| DOOMQL / Doom | Xeon | | drop-in |

`bench/winloss.py` builds the per-class numbers from `bench/classes.tsv`; ClickBench queries are classified from
their SQL text. The other sources were classified by hand. Ratios are turbo's time over stock SQLite's: below 1 is
faster.

### Drop-in benchmarks on the Xeon, by class

| class | n | turbo / stock (geomean) | qvm / stock (geomean) | turbo range | items (turbo / stock) |
|---|---:|---:|---:|---|---|
| point | 3 | 1.063 | 1.013 | 1.05–1.07 | ClickBench Q19 1.05, speedtest1 410 1.06, speedtest1 510 1.07 |
| short | 5 | 1.256 | 1.372 | 0.94–2.00 | speedtest1 200 0.94, speedtest1 110 1.04, speedtest1 210 1.20, speedtest1 260 1.33, speedtest1 141 2.00 |
| range | 2 | 1.055 | 1.019 | 1.04–1.07 | speedtest1 161 1.04, speedtest1 170 1.07 |
| scan-expr | 6 | 1.005 | 1.015 | 0.94–1.07 | TPC-H Q06 0.94, ClickBench Q23 0.97, ClickBench Q22 1.00, ClickBench Q20 1.02, ClickBench Q21 1.04, speedtest1 150 1.07 |
| agg | 25 | 1.046 | 1.083 | 0.91–1.35 | ClickBench Q16 0.91, ClickBench Q32 0.94, ClickBench Q27 0.95, ClickBench Q02 0.98, TPC-H Q01 0.98, ClickBench Q34 0.98, ClickBench Q01 1.00, ClickBench Q33 1.02, ClickBench Q17 1.02, ClickBench Q18 1.02, ClickBench Q12 1.03, ClickBench Q14 1.03, ClickBench Q30 1.03, TPC-H Q13 1.04, ClickBench Q31 1.04, ClickBench Q35 1.06, TPC-H Q11 1.06, TPC-H Q15 1.06, ClickBench Q28 1.06, ClickBench Q07 1.10, ClickBench Q29 1.11, ClickBench Q03 1.13, ClickBench Q06 1.14, ClickBench Q15 1.20, ClickBench Q00 1.35 |
| join | 12 | 1.023 | 1.008 | 0.97–1.11 | TPC-H Q14 0.97, TPC-H Q03 0.97, TPC-H Q05 0.97, speedtest1 310 0.99, TPC-H Q07 0.99, TPC-H Q08 1.01, TPC-H Q10 1.04, TPC-H Q09 1.04, TPC-H Q19 1.05, speedtest1 140 1.07, TPC-H Q12 1.09, speedtest1 130 1.11 |
| subquery | 8 | 1.035 | 1.032 | 0.98–1.14 | TPC-H Q02 0.98, TPC-H Q22 0.99, TPC-H Q21 0.99, TPC-H Q04 1.00, TPC-H Q20 1.04, TPC-H Q17 1.04, TPC-H Q18 1.12, speedtest1 320 1.14 |
| topn | 4 | 1.203 | 1.114 | 1.01–1.76 | ClickBench Q25 1.01, ClickBench Q24 1.07, ClickBench Q26 1.10, speedtest1 145 1.76 |
| sort | 1 | 1.225 | 1.219 | 1.23–1.23 | speedtest1 142 1.23 |
| distinct | 9 | 0.849 | 0.913 | 0.39–1.07 | speedtest1 520 0.39, ClickBench Q05 0.70, ClickBench Q04 0.78, ClickBench Q10 0.98, ClickBench Q11 0.99, ClickBench Q08 0.99, ClickBench Q09 1.03, ClickBench Q13 1.03, TPC-H Q16 1.07 |
| setop | 1 | 1.095 | 1.155 | 1.10–1.10 | speedtest1 400 1.10 |
| compute | 1 | 1.065 | 1.053 | 1.07–1.07 | speedtest1 300 1.07 |
| write | 12 | 1.020 | 1.044 | 0.93–1.26 | speedtest1 190 0.93, speedtest1 160 0.93, speedtest1 120 0.95, speedtest1 180 0.95, speedtest1 240 0.96, speedtest1 290 0.96, speedtest1 500 0.99, speedtest1 230 1.01, speedtest1 270 1.04, speedtest1 280 1.05, speedtest1 100 1.26, speedtest1 250 1.26 |
| maint | 3 | 1.088 | 1.182 | 0.96–1.25 | speedtest1 980 0.96, speedtest1 990 1.07, speedtest1 999 1.25 |

### Verdict per class, all sources

| class | drop-in benchmarks (Xeon), turbo / qvm | embedded API, hot (corpus) | real applications | verdict |
|---|---|---|---|---|
| **DISTINCT, count(DISTINCT)** | **0.85 / 0.91** (speedtest1 520: 0.39; ClickBench Q04/Q05: 0.70–0.78) | hash sets, 8–12 points faster | – | **win: niche** |
| **top-N (ORDER BY … LIMIT)** | 1.20 / 1.11: qvm wins or is level; speedtest1 145 is 1.76 as a loop plan against 1.05 in qvm | −47 % | Gitea activity feed **0.86**, issue lists 0.85–0.96, `IN` top-N 0.87–0.94 | **win in qvm** (the top-N sorter); the loss is the plan tier's choice |
| **compute-heavy** (recursive CTEs, windows) | 1.07 / 1.05 (Mandelbrot, one-shot) | windows −27…−44 %, recursive CTE −52 % | DOOMQL **0.91**, Peter's DOOMQL frames **0.62**, Turso's Doom VDBE 1.00 | **win where the work is in the VDBE** |
| **hot repeated small and medium queries** (point, range, joins by key, correlated counts) | point 1.06 / 1.01, range 1.06 / 1.02 | point −13…−34 %, range −30…−40 %, join −15…−27 %, the feed's correlated counts **−82 %** | Gitea: serving every small statement costs +170–220 % | **win only through the embedded API**: the drop-in path's per-statement cost is larger than the gain |
| join + aggregate (large) | 1.02 / 1.01 | | Gitea joined counts ≈1.0 | parity: B-tree-bound |
| aggregation / GROUP BY (large) | 1.05 / 1.08 (ClickBench Q00 `count(*)` 1.35 in turbo, 1.05 in qvm) | GROUP BY by index −32 % | Gitea counts as loop plans 1.13–1.17, qvm 1.02–1.04 | parity in qvm; **the loop plans lose** |
| subqueries (large: EXISTS, IN, correlated) | 1.04 / 1.03 | post with count −27 % | | parity |
| filtered / expression / LIKE scans | 1.01 / 1.02 | LIKE −11 %, unindexed filter +7 % | Gitea `LOWER() LIKE` ≈1.0 | parity |
| full sort (ORDER BY, no LIMIT) | 1.23 / 1.22 (speedtest1 142) | sorter −33 % | | loss drop-in (one test) |
| set operations | 1.10 / 1.16 (speedtest1 400 EXCEPT) | UNION −19…−28 % | | loss drop-in (one test) |
| **short one-shot statements** | **1.26 / 1.37** (constant SELECTs, json_type, tiny scans) | – | Gitea: about 27 µs per served statement against SQLite's 2–3 µs | **loss: exclude** |
| writes, DDL, maintenance | 1.02 / 1.04, noise | not run by qc | – | not qc's (the build itself costs nothing: `off` 0.98) |

### What it says

**Niche candidates, where turbo wins big:**
1. **DISTINCT and count(DISTINCT):** qvm's hash sets, 0.4–0.8×.
2. **Top-N in qvm:** the new top-N sorter. Gitea's feed went 1.86 → 0.86 over the series.
3. **Compute-heavy programs:** recursive CTEs, windows, DOOMQL. 0.6–0.9× when the time is in VDBE dispatch, not in
   B-tree reads.
4. **Hot, repeated small and medium queries through the embedded API:** prepared once, run inside a transaction,
   rows taken from the callback. 13–82 % faster.

**Parity:** large scans, joins, aggregations and subqueries (TPC-H, ClickBench, Gitea's big queries). There the time
is B-tree descents and record reads, which qvm does the same way the interpreter does. After the spill fix nothing
here loses more than about 10 %: TPC-H 1.02×, ClickBench 1.04×.

**Losses, and what would remove them:**
- **Per-statement cost on short statements, through the drop-in path:** about 0.3–1 µs on the Xeon. That is an
  autocommit `BEGIN`/`COMMIT` around `sqlite3_qc_exec`, copying every row value, and the bookkeeping. It's larger than
  what qc saves on a 1–5 µs statement.
  - Fix in the integration: route a statement to qc only once it's proven expensive. Gitea's `QCT_SERVE_MIN_US` gate
    does this, and with it Gitea is level.
  - Fix in the engine: open the read transaction in `sqlite3_qc_exec` without `BEGIN`/`COMMIT` statements, and hand
    rows to `sqlite3_column_*` without a copy.
- **The plan tiers choosing worse than qvm:**
  - speedtest1 145 (top-N, loop plan, 1.76 against qvm's 1.05);
  - Gitea's joined counts (loop plans 1.13–1.17, qvm 1.02–1.04);
  - ClickBench Q00 `count(*)` (1.35 against 1.05).

  Fix: a policy that sends these shapes to qvm, or measures before it commits to a plan.
- **No correctness bugs open:** the two SQLancer bugs and the gcc x86-64 bug are fixed (c3ebcb0). The spill fix is
  pending.

### The map on 905fb05: the spill fix, QC_STATS and the adaptive tier choice

The same three benchmarks on the Xeon (exp450–473, one arm per run, rotated). Rows are identical to stock everywhere.

| | turbo / stock | qvm / stock | before (c3ebcb0, or the spill snapshot) |
|---|---:|---:|---|
| TPC-H SF0.1, geomean (3 rounds) | **1.000** | **1.000** | 1.074 / 1.077; snapshot 1.018 / 1.013 |
| ClickBench 300k, geomean (2 rounds) | 1.041 | 1.095 | snapshot 1.042 / 1.10 |
| speedtest1 total (3 rounds) | 1.087 | 1.119 | 1.075 / 1.101 |

| class | n | turbo / stock (geomean) | qvm / stock (geomean) | turbo range | items (turbo / stock) |
|---|---:|---:|---:|---|---|
| point | 4 | 1.038 | 1.099 | 0.71–1.27 | ClickBench Q19 0.71, speedtest1 main/410 1.13, speedtest1 main/510 1.15, speedtest1 orm/110 1.27 |
| short | 5 | 1.419 | 1.546 | 1.20–1.60 | speedtest1 parsenumber/100 1.20, speedtest1 parsenumber/210 1.33, speedtest1 parsenumber/110 1.50, speedtest1 json/141 1.50, speedtest1 parsenumber/200 1.60 |
| range | 4 | 1.039 | 1.058 | 1.00–1.10 | speedtest1 fp/130 1.00, speedtest1 main/160 1.02, speedtest1 main/161 1.04, speedtest1 main/170 1.10 |
| scan-expr | 12 | 1.147 | 1.142 | 0.93–2.59 | ClickBench Q22 0.93, TPC-H Q06 0.96, ClickBench Q21 0.98, ClickBench Q23 1.00, speedtest1 main/130 1.00, speedtest1 fp/110 1.00, ClickBench Q20 1.01, speedtest1 main/140 1.14, speedtest1 fp/150 1.21, speedtest1 fp/140 1.25, speedtest1 main/260 1.33, speedtest1 json/140 2.59 |
| agg | 25 | 1.029 | 1.065 | 0.93–1.18 | ClickBench Q15 0.93, ClickBench Q00 0.94, ClickBench Q32 0.94, TPC-H Q13 0.95, ClickBench Q18 0.97, ClickBench Q27 0.98, ClickBench Q33 0.99, ClickBench Q16 1.00, ClickBench Q02 1.00, TPC-H Q15 1.00, TPC-H Q01 1.00, ClickBench Q17 1.01, ClickBench Q07 1.02, ClickBench Q34 1.02, TPC-H Q11 1.02, ClickBench Q30 1.04, ClickBench Q12 1.04, ClickBench Q35 1.07, ClickBench Q01 1.08, ClickBench Q14 1.08, ClickBench Q28 1.09, ClickBench Q31 1.10, ClickBench Q29 1.15, ClickBench Q06 1.16, ClickBench Q03 1.18 |
| join | 12 | 1.006 | 1.032 | 0.95–1.07 | TPC-H Q14 0.95, TPC-H Q07 0.96, TPC-H Q09 0.97, TPC-H Q19 0.98, TPC-H Q08 0.99, speedtest1 star/140 1.00, TPC-H Q05 1.00, TPC-H Q03 1.01, TPC-H Q10 1.02, speedtest1 star/130 1.05, TPC-H Q12 1.07, speedtest1 main/310 1.07 |
| subquery | 8 | 1.023 | 1.031 | 0.94–1.13 | TPC-H Q20 0.94, TPC-H Q21 0.96, TPC-H Q02 0.99, TPC-H Q17 1.00, TPC-H Q22 1.03, TPC-H Q04 1.05, TPC-H Q18 1.10, speedtest1 main/320 1.13 |
| topn | 4 | 1.160 | 1.153 | 1.02–1.57 | ClickBench Q26 1.02, ClickBench Q24 1.03, ClickBench Q25 1.09, speedtest1 main/145 1.57 |
| sort | 1 | 1.259 | 1.272 | 1.26–1.26 | speedtest1 main/142 1.26 |
| distinct | 9 | 0.862 | 0.867 | 0.40–1.05 | speedtest1 main/520 0.40, ClickBench Q05 0.73, ClickBench Q04 0.79, ClickBench Q08 0.99, ClickBench Q11 1.00, ClickBench Q13 1.02, ClickBench Q10 1.03, ClickBench Q09 1.05, TPC-H Q16 1.05 |
| setop | 1 | 0.859 | 0.962 | 0.86–0.86 | speedtest1 cte/400 0.86 |
| compute | 3 | 0.975 | 0.999 | 0.82–1.07 | speedtest1 cte/300 0.82, speedtest1 cte/100 1.06, speedtest1 cte/200 1.07 |
| write | 29 | 1.034 | 0.985 | 0.68–1.36 | speedtest1 star/110 0.68, speedtest1 star/100 0.85, speedtest1 main/110 0.94, speedtest1 main/180 0.95, speedtest1 fp/120 0.97, speedtest1 main/240 0.97, speedtest1 json/160 0.97, speedtest1 main/230 0.99, speedtest1 json/120 1.00, speedtest1 json/130 1.00, speedtest1 fp/100 1.00, speedtest1 main/190 1.01, speedtest1 orm/100 1.03, speedtest1 main/120 1.03, speedtest1 main/270 1.03, speedtest1 main/280 1.04, speedtest1 main/150 1.04, speedtest1 star/120 1.06, speedtest1 app/100 1.07, speedtest1 main/290 1.07, speedtest1 json/100 1.09, speedtest1 main/100 1.10, speedtest1 main/500 1.10, speedtest1 json/150 1.12, speedtest1 main/400 1.14, speedtest1 main/300 1.18, speedtest1 json/110 1.19, speedtest1 main/250 1.25, speedtest1 main/210 1.36 |
| maint | 8 | 1.029 | 0.882 | 0.98–1.11 | speedtest1 main/200 0.98, speedtest1 orm/999 1.00, speedtest1 json/999 1.00, speedtest1 main/999 1.01, speedtest1 main/980 1.02, speedtest1 main/990 1.05, speedtest1 fp/999 1.08, speedtest1 star/999 1.11 |

What changed:
- **TPC-H:** 0 fallbacks; 132 of 132 executions run in qvm. The residue is Q18 at about 1.10 and Q12 at 1.07.
- **ClickBench:**
  - Q36–Q41 return 0 rows in about 10 µs at 300k rows, so their ratios are noise.
  - The real outlier is Q33 under qvm-only: 1.52 (279 → 424 ms), while turbo runs it at 0.99.
- **Adaptive choice ("parked"):** it now hands some statements back to SQLite. In speedtest1 that's 127 executions
  of test 310 (the four-way join) or 510 (TEXT-PK lookups) in four of six runs. It's timing-based, so the count
  varies between runs.
- **Still losing:**
  - **Point lookups (410/510, 1.13–1.15):** too cheap for the adaptive comparison (it times plans of 50 µs or more:
    `cheap 725` in QC_STATS), so they stay in qc. That's the drop-in path's per-statement cost.
  - **Short one-shot statements:** 1.23.
  - **Top-N 145 (loop plan):** 1.57.
  - **Full sort 142:** 1.26.

### The tier-choice snapshot (sqlite-jit's working tree on e5d68ff, Xeon exp478–513)

Three changes to which tier gets a statement, in `qcg.c` only:
- loop plans that call a function on a column value go to qvm;
- full scans without LIMIT go to qvm;
- the loop-plan top-N drops rows behind the N-th entry before evaluating them.

The runs had four arms: stock, turbo and qvm-only from the snapshot, and `main` (e5d68ff). There were 3 rounds per
benchmark, and this was the first series with the shim's one-block row copy. Rows are identical to stock everywhere.

| | turbo | qvm | main | |
|---|---:|---:|---:|---|
| speedtest1 total | 1.067 | 1.062 | 1.043 | 145 (top-N): **1.03** (main 1.66); 142 (full sort): 1.18 (main 1.21; bench4 1.26); joins 130/140/310: 0.97–1.10 |
| TPC-H SF0.1 geomean | 1.016 | 1.025 | 1.014 | Q18 1.16 / 1.13 / 1.08 and Q12 1.06–1.07, all in qvm: within noise of each other |
| ClickBench 300k geomean | 1.090 | 1.052 | 1.117 | Q00 0.96–0.98 everywhere; Q06 1.38 / 1.18 / 1.18 |

**Noise:** box placement moves these numbers.
- **Stock alone:** ClickBench's total ranges 6,286–6,713 ms over its three runs (7 %).
- **The same executor in two arms:** turbo and qvm-only both run Q06, Q14 and Q19 in qvm, yet differ by up to
  ±20 % (Q19: 1.25 against 0.92).
- **What that means:** ClickBench per-query deltas under about 20 % and geomean deltas under about 5 % aren't
  signal on this setup.

The clear result is test 145: the loop-plan top-N goes from 1.66 to 1.03. A firmer comparison of small effects needs
every arm of a series on one box.

### The parity bar, round 1 (Xeon box1 only, exp517–540, e5d68ff + the shim)

The bar is turbo within **1.02×** of stock on small statements.
- **Setup:** 8 rounds × stock / turbo / qvm-only, one arm per run, alternated, all on box1.
- **The suite:** 18 small statements on TPC-H SF0.1 (`bench/small`), each run 20,000 times per round. They run in
  autocommit (the drop-in path, a transaction per statement) and again inside one transaction. Then speedtest1.
- **What's measured:** time, plus user instructions and cycles (`perf_event_open`, root).
- **Intervals:** 95 % percentile bootstrap over rounds (`bench/parity.py`).
- **Marks:** ✗ means the interval is entirely above 1.02; ? means it straddles 1.02.
- **Result:** rows identical in every arm.

#### Small statements, autocommit (drop-in: a transaction per statement): time, arm / stock, mean over rounds [95 % interval]

| statement | turbo | qvm |
|---|---:|---:|
| **agg** (2) | 1.068 [1.008, 1.130] ? | 1.084 [1.042, 1.134] ✗ |
| **distinct** (1) | 0.948 [0.918, 0.978] | 0.947 [0.923, 0.973] |
| **point** (4) | 1.104 [1.033, 1.190] ✗ | 1.099 [1.025, 1.188] ✗ |
| **range** (3) | 1.030 [0.986, 1.080] ? | 1.032 [0.986, 1.083] ? |
| **scan-expr** (2) | 1.184 [1.113, 1.257] ✗ | 1.160 [1.112, 1.214] ✗ |
| **short** (2) | 2.777 [2.569, 3.018] ✗ | 2.699 [2.501, 2.901] ✗ |
| **subquery** (2) | 1.070 [1.014, 1.139] ? | 1.071 [1.019, 1.131] ? |
| **topn** (2) | 1.003 [0.953, 1.057] ? | 1.051 [1.003, 1.104] ? |
| **all** (18) | 1.187 [1.130, 1.249] ✗ | 1.188 [1.141, 1.244] ✗ |

#### Small statements, autocommit (drop-in: a transaction per statement): user instructions, arm / stock, mean over rounds [95 % interval]

| statement | turbo | qvm |
|---|---:|---:|
| **agg** (2) | 1.021 [1.021, 1.022] ✗ | 1.054 [1.053, 1.054] ✗ |
| **distinct** (1) | 1.006 [1.006, 1.006] | 1.007 [1.007, 1.007] |
| **point** (4) | 1.485 [1.485, 1.485] ✗ | 1.504 [1.504, 1.504] ✗ |
| **range** (3) | 1.059 [1.059, 1.060] ✗ | 1.060 [1.060, 1.060] ✗ |
| **scan-expr** (2) | 1.310 [1.309, 1.310] ✗ | 1.277 [1.277, 1.277] ✗ |
| **short** (2) | 2.479 [2.479, 2.481] ✗ | 2.495 [2.494, 2.497] ✗ |
| **subquery** (2) | 1.117 [1.116, 1.117] ✗ | 1.131 [1.131, 1.132] ✗ |
| **topn** (2) | 1.166 [1.166, 1.166] ✗ | 1.179 [1.179, 1.179] ✗ |
| **all** (18) | 1.297 [1.297, 1.298] ✗ | 1.307 [1.307, 1.307] ✗ |

#### Small statements, inside one transaction: time, arm / stock, mean over rounds [95 % interval]

| statement | turbo | qvm |
|---|---:|---:|
| **agg** (2) | 0.979 [0.945, 1.014] | 1.097 [1.060, 1.129] ✗ |
| **distinct** (1) | 0.872 [0.846, 0.897] | 0.885 [0.858, 0.912] |
| **point** (4) | 1.119 [1.043, 1.203] ✗ | 1.196 [1.144, 1.259] ✗ |
| **range** (3) | 1.044 [1.017, 1.069] ? | 1.058 [1.036, 1.076] ✗ |
| **scan-expr** (2) | 1.261 [1.219, 1.304] ✗ | 1.296 [1.235, 1.360] ✗ |
| **short** (2) | 1.984 [1.799, 2.180] ✗ | 2.068 [1.861, 2.280] ✗ |
| **subquery** (2) | 1.044 [0.973, 1.116] ? | 1.089 [1.020, 1.164] ? |
| **topn** (2) | 0.984 [0.945, 1.028] ? | 1.117 [1.083, 1.157] ✗ |
| **all** (18) | 1.136 [1.089, 1.184] ✗ | 1.202 [1.165, 1.240] ✗ |

#### Small statements, inside one transaction: user instructions, arm / stock, mean over rounds [95 % interval]

| statement | turbo | qvm |
|---|---:|---:|
| **agg** (2) | 0.979 [0.979, 0.979] | 1.014 [1.014, 1.014] |
| **distinct** (1) | 0.996 [0.996, 0.996] | 0.996 [0.996, 0.996] |
| **point** (4) | 1.044 [1.044, 1.044] ✗ | 1.070 [1.070, 1.070] ✗ |
| **range** (3) | 1.024 [1.024, 1.024] ✗ | 1.025 [1.025, 1.025] ✗ |
| **scan-expr** (2) | 1.271 [1.271, 1.271] ✗ | 1.222 [1.221, 1.222] ✗ |
| **short** (2) | 1.996 [1.996, 1.996] ✗ | 2.014 [2.014, 2.015] ✗ |
| **subquery** (2) | 1.037 [1.036, 1.037] ✗ | 1.054 [1.054, 1.054] ✗ |
| **topn** (2) | 1.132 [1.132, 1.132] ✗ | 1.145 [1.145, 1.145] ✗ |
| **all** (18) | 1.141 [1.141, 1.141] ✗ | 1.152 [1.152, 1.152] ✗ |

#### speedtest1 (per test: seconds; perf: user-mode counts): value, arm / stock, mean over rounds [95 % interval]

| statement | turbo | qvm |
|---|---:|---:|
| TOTAL | 1.059 [1.024, 1.096] ✗ | 1.090 [1.057, 1.123] ✗ |
| perf: whole run, cycles | 1.061 [1.048, 1.074] ✗ | 1.055 [1.045, 1.066] ✗ |
| perf: whole run, instructions | 1.053 [1.053, 1.053] ✗ | 1.044 [1.044, 1.044] ✗ |

**What it says:**
- **The bar fails broadly in the drop-in path.** Instruction counts are deterministic: their intervals are under
  ±0.1 %, so they settle what wall time can't.
- **Per execution, turbo adds a roughly fixed cost on top of SQLite's work:**
  - about +2,750 user instructions per primary-key lookup in autocommit (stock: 4,724);
  - about +480 inside a transaction (stock: 3,376);
  - +1,700 to +2,800 on a constant `SELECT` (stock: about 1,450).
- **Short statements** (constants, functions) are 2–2.9×. **Point lookups** are 1.36–1.59× in autocommit and
  1.01–1.18× inside a transaction.
- **Wins:** the correlated count (0.85×), the week's count over an index (0.86×), the per-customer top-N (0.90–0.94×)
  and DISTINCT (0.88–0.95× in time).
- **Caveat:** round 1 ran with the shim's per-statement stats on. That means a `getenv` and a hash of the SQL text on
  every start, which is harness cost charged to turbo. Round 2 (below, when in) takes it out, and adds a `direct` arm
  that calls qc's embedded API (`sqlite3_qc_exec` with a row callback) without the shim, so engine cost and
  integration cost come apart.

## Results (2026-10-27, turbo at da4c75d)

### Summary

| source | correctness | speed vs stock SQLite 3.54.1 |
|---|---|---|
| **SQLancer** (NoREC, TLP, PQS; 5 arms; about 65M queries) | **2 turbo bugs** (below). Stock: none | – |
| **speedtest1** (`--size 100`, Xeon, 6 rounds) | one verification hash across all 18 runs | turbo 1.11×, qvm 1.14×, `off` 0.98× |
| **TPC-H SF0.1** (22 queries, Xeon, 3 rounds) | all 22 identical, every arm and round | geomean turbo 1.08×, qvm 1.04×; Q09/Q10 1.7–1.8× (sorter spill) |
| **TPC-H SF1** (Docker on the M5, 3 rounds) | all 22 identical | geomean turbo 1.02×, qvm 1.05× (noisy); Q13 1.70× (sorter spill) |
| **ClickBench** (first 1M rows, Docker on the M5, 3 rounds) | all 43 identical | geomean turbo 1.07×, qvm 1.08×; with `temp_store=MEMORY` 0.94× and 0.95× |

Above 1.0 is slower than stock. The two findings that matter, both sent to the engine session:
- **Correctness:**
  - a BLOB passed to a scalar function in a loop plan reads as UTF-16;
  - any read under memory-mapped I/O segfaults.
- **Speed:** the "sorter would spill" fallback runs the whole query twice, which accounts for every TPC-H and ClickBench
  query where turbo loses badly.

How these were measured:
- **Xeon** numbers: cursed-http's broker, one arm per run in rotated order, clang 18 `-O2 -march=native
  -mbranches-within-32B-boundaries` on every arm, ccache by relative paths (`bench/xeon/`).
- **Local** numbers: the Apple M5 Pro in Docker on CPUs 8–11, clang 14 `-O2 -mcpu=native`. Treat them as indicative
  only: other sessions share the machine.

### SQLancer

**Route.** SQLancer (pinned commit 1d797ee, built with Maven `-C`) talks to SQLite through xerial's sqlite-jdbc
3.49.1.0. `tests/sqlancer/build.sh` rebuilds that driver's JNI library three times:
- **what it compiles:** sqlite-jdbc's own `NativeDB.c`, its compile options and its amalgamation edits (extension
  functions, `JDBC_EXTENSIONS`), against this repo's SQLite 3.54.1;
- **the variants:** `stock`, `serve` and `diff`;
- **how it's loaded:** `-Dorg.sqlite.lib.path`/`-Dorg.sqlite.lib.name`, so the jar's bundled SQLite is never used.
  Every log reports `Database version: 3.54.1`.

No Java code changes, and SQLancer's generator and oracles are its own. Arms:
- **stock**;
- **turbo**: qc serves every statement it takes, so SQLancer's oracles judge qc's rows;
- **qvm**: the same with `QC_VM_ONLY=1`;
- **diff**: every read-only statement is run again through qc and compared with SQLite value by value, so any
  difference shows up, not only those an oracle notices;
- **diffvm**: diff with `QC_VM_ONLY=1`.

Each arm is one JVM with one thread (qc's run state is per process). Seed 1 for 10 minutes per oracle. The PQS crash
hunt added seeds 2–4 on the diff arm.

| arm | oracle | seed | queries | bug logs | qc |
|---|---|---|---:|---:|---|
| diff | NoREC | 1 | 6,663k | 0 | compiled 1679766, fallbacks 36030, rows compared 2827433, differences 0 |
| diff | PQS | 1 | crashed | 0 |  |
| diff | PQS | 2 | crashed | 0 |  |
| diff | PQS | 3 | 4,213k | 0 | compiled 1347476, fallbacks 22706, rows compared 1324556, differences 0 |
| diff | PQS | 4 | crashed | 0 |  |
| diff | QUERY_PARTITIONING | 1 | 2,332k | 0 | compiled 592067, fallbacks 22392, rows compared 8367156, differences 3 |
| diffvm | NoREC | 1 | 5,854k | 0 | compiled 1586874, fallbacks 34949, rows compared 2752631, differences 0 |
| diffvm | PQS | 1 | 5,237k | 0 | compiled 1508584, fallbacks 25571, rows compared 1482811, differences 0 |
| diffvm | QUERY_PARTITIONING | 1 | 2,573k | 0 | compiled 592067, fallbacks 22392, rows compared 8242863, differences 0 |
| qvm | NoREC | 1 | 6,699k | 0 | served 1711996, fallbacks 37502, refused 12116301 |
| qvm | PQS | 1 | 4,250k | 0 | served 2338496, fallbacks 16331, refused 7153971 |
| qvm | QUERY_PARTITIONING | 1 | 1,381k | 0 | served 536744, fallbacks 22310, refused 1297939 |
| stock | NoREC | 1 | 7,382k | 0 |  |
| stock | PQS | 1 | 4,336k | 0 |  |
| stock | QUERY_PARTITIONING | 1 | 2,627k | 0 |  |
| turbo | NoREC | 1 | 6,306k | 0 | served 1663727, fallbacks 36632, refused 11352605 |
| turbo | PQS | 1 | 3,098k | 0 | served 1215809, fallbacks 9709, refused 5675782 |
| turbo | QUERY_PARTITIONING | 1 | 3,793k | 1 | served 1102447, fallbacks 14528, refused 3715867 |

- diff/PQS/1: native crash: C  [libsqlitejdbc.so+0xa5d34]  qv_pin+0x40
- diff/PQS/2: native crash: C  [libsqlitejdbc.so+0x47988]  qg_fetch+0x1a4
- diff/PQS/4: native crash: C  [libsqlitejdbc.so+0xa5d34]  qv_pin+0x40
- diff/QUERY_PARTITIONING/1: QCTDIFF values differ (row 0 col 0): SELECT MAX(UNICODE(t0.c0) COLLATE NOCASE COLLATE BINARY) FROM t0;
- diff/QUERY_PARTITIONING/1: QCTDIFF values differ (row 0 col 0): SELECT MAX(LTRIM(t0.c0)) FROM t0;
- diff/QUERY_PARTITIONING/1: QCTDIFF values differ (row 0 col 0): SELECT ALL MAX(LOWER(DISTINCT t0.c0)) FROM t0;
- turbo/QUERY_PARTITIONING/1: database0.log: --java.lang.AssertionError

**Finding 1: BLOB arguments to functions in loop plans (wrong result).** `tests/sqlancer/repros/blob-func-arg.sql`.
- **Cause:** `qg_mem` (`qc/qcg.c:857`) builds a BLOB `Mem` with `enc` 0. When the built-in calls
  `sqlite3_value_text()` on it, the bytes go through an encoding conversion, as if they were UTF-16.
- **What you see:** `unicode(x'eece')` returns 61134 instead of 65533; `ltrim`, `upper` and `lower` of a blob return
  `''`.
- **How it was found:** TLP's aggregate oracle (an AssertionError on `MAX(LTRIM(c0))`), and three QCTDIFFs in the
  differential arm.
- **Scope and fix:** qvm-only is unaffected. Setting `m->enc = SQLITE_UTF8` fixes all three repros (checked on a
  scratch copy).

**Finding 2: SIGSEGV under memory-mapped I/O (crash).** `tests/sqlancer/repros/mmap-pin-crash.sql`.
- **What you see:** `PRAGMA mmap_size = 268435456` on a file database of more than two pages, then any qc read of a
  page, crashes with SIGSEGV at 0x18.
- **Cause:** `qv_pin` and `qg_pin` call `sqlite3PagerRef()` on a `PGHDR_MMAP` page, whose `pCache` is NULL, so
  `pCache->nRefSum++` faults.
- **Scope:** both tiers, both shims. The PQS oracle sets `mmap_size` often, so 3 of 4 differential PQS seeds crashed
  within about 10k queries.
- **Why it was missed:** sqllogictest and the TCL suite never turn on mmap.

**Stock SQLite 3.54.1:** SQLancer reported nothing in about 14M queries.

**Status:** the engine session has fixed both findings in its working tree, and both are in its new `tests/regress.c`
(`make regress`):
- `qg_mem` sets `enc` for every value;
- qvm copies values out of `PGHDR_MMAP` pages instead of pinning them;
- specialised and loop plans demote to qvm when the pager uses mmap.

The commit was pending when this was written. Rerun the campaign on it, with more seeds; until it lands, PQS crashes
early.

**Nested statements:** the harness shims, not qc, decide what gets lifted. Both lift any read-only statement that
starts with nothing else running on its connection. That includes statements SQLite's own modules step inside a
prepare, such as R-Tree's `getIntFromStmt` during `UPDATE rt0 …`, which is how the second crash surfaced there.

**Reproducing.** `tests/sqlancer/repro.sh <file>` replays a SQLancer log (`replay.c`) on a file database through
stock, turbo, qvm, diff and diffvm, and shows what differs. `reduce.py` minimises a log with ddmin, against a test
script such as `crashes.sh`.

### SQLancer campaign 2: the fixed commit (c3ebcb0)

The same matrix on c3ebcb0, which has both SQLancer fixes and the gcc x86-64 fix: 5 arms × 3 oracles × seeds 2 and 3,
10 minutes each, PQS included.
- **Coverage:** 125M queries; the differential arms compared 57M rows.
- **Result:** 0 bugs logged, 0 differences, 0 crashes.

| arm | oracle | seed | queries | bug logs | qc |
|---|---|---|---:|---:|---|
| diff | NoREC | 2 | 4,696k | 0 | compiled 960438, fallbacks 17769, rows compared 4396999, differences 0 |
| diff | NoREC | 3 | 5,389k | 0 | compiled 1017738, fallbacks 17397, rows compared 1742465, differences 0 |
| diff | PQS | 2 | 4,235k | 0 | compiled 1073965, fallbacks 18169, rows compared 1055663, differences 0 |
| diff | PQS | 3 | 4,594k | 0 | compiled 662995, fallbacks 11028, rows compared 651877, differences 0 |
| diff | QUERY_PARTITIONING | 2 | 4,249k | 0 | compiled 999001, fallbacks 11510, rows compared 8272619, differences 0 |
| diff | QUERY_PARTITIONING | 3 | 3,882k | 0 | compiled 634103, fallbacks 6708, rows compared 12725150, differences 0 |
| diffvm | NoREC | 2 | 2,461k | 0 | compiled 641842, fallbacks 11657, rows compared 3938303, differences 0 |
| diffvm | NoREC | 3 | 5,593k | 0 | compiled 1027735, fallbacks 17646, rows compared 1757307, differences 0 |
| diffvm | PQS | 2 | 4,046k | 0 | compiled 882920, fallbacks 15017, rows compared 867775, differences 0 |
| diffvm | PQS | 3 | 4,685k | 0 | compiled 921573, fallbacks 15600, rows compared 905831, differences 0 |
| diffvm | QUERY_PARTITIONING | 2 | 4,247k | 0 | compiled 999001, fallbacks 11510, rows compared 7865687, differences 0 |
| diffvm | QUERY_PARTITIONING | 3 | 2,925k | 0 | compiled 592459, fallbacks 6370, rows compared 12487825, differences 0 |
| qvm | NoREC | 2 | 4,677k | 0 | served 987667, fallbacks 18456, refused 8607905 |
| qvm | NoREC | 3 | 5,700k | 0 | served 1056169, fallbacks 18415, refused 10635757 |
| qvm | PQS | 2 | 3,470k | 0 | served 1820264, fallbacks 13009, refused 6173198 |
| qvm | PQS | 3 | 2,949k | 0 | served 1794149, fallbacks 14005, refused 4731134 |
| qvm | QUERY_PARTITIONING | 2 | 2,682k | 0 | served 537943, fallbacks 7121, refused 2819967 |
| qvm | QUERY_PARTITIONING | 3 | 4,129k | 0 | served 641773, fallbacks 6889, refused 4533602 |
| stock | NoREC | 2 | 5,064k | 0 |  |
| stock | NoREC | 3 | 6,479k | 0 |  |
| stock | PQS | 2 | 3,486k | 0 |  |
| stock | PQS | 3 | 3,862k | 0 |  |
| stock | QUERY_PARTITIONING | 2 | 4,182k | 0 |  |
| stock | QUERY_PARTITIONING | 3 | 4,565k | 0 |  |
| turbo | NoREC | 2 | 4,611k | 0 | served 987633, fallbacks 18456, refused 8472776 |
| turbo | NoREC | 3 | 5,140k | 0 | served 1009984, fallbacks 17314, refused 9530854 |
| turbo | PQS | 2 | 2,529k | 0 | served 2231874, fallbacks 17036, refused 4069246 |
| turbo | PQS | 3 | 3,160k | 0 | served 1503846, fallbacks 11989, refused 5606954 |
| turbo | QUERY_PARTITIONING | 2 | 3,170k | 0 | served 669379, fallbacks 8729, refused 3299954 |
| turbo | QUERY_PARTITIONING | 3 | 4,144k | 0 | served 641773, fallbacks 6889, refused 4553146 |

### SQLancer campaign 3: 905fb05 (spill fix, adaptive tier choice)

The same matrix on 905fb05, with seeds 4 and 5.
- **Coverage:** 139M queries; the differential arms compared 41M rows.
- **Result:** 0 bugs logged, 0 differences, 0 crashes.

| arm | oracle | seed | queries | bug logs | qc |
|---|---|---|---:|---:|---|
| diff | NoREC | 4 | 5,872k | 0 | compiled 1327040, fallbacks 29744, rows compared 1831604, differences 0 |
| diff | NoREC | 5 | 5,403k | 0 | compiled 1802832, fallbacks 35394, rows compared 3358859, differences 0 |
| diff | PQS | 4 | 6,884k | 0 | compiled 1480950, fallbacks 25346, rows compared 1455449, differences 0 |
| diff | PQS | 5 | 5,408k | 0 | compiled 1750911, fallbacks 29256, rows compared 1721419, differences 0 |
| diff | QUERY_PARTITIONING | 4 | 4,550k | 0 | compiled 1112287, fallbacks 13529, rows compared 5550009, differences 0 |
| diff | QUERY_PARTITIONING | 5 | 4,714k | 0 | compiled 946253, fallbacks 8394, rows compared 6776429, differences 0 |
| diffvm | NoREC | 4 | 3,755k | 0 | compiled 480999, fallbacks 10853, rows compared 896394, differences 0 |
| diffvm | NoREC | 5 | 5,370k | 0 | compiled 1802832, fallbacks 35394, rows compared 3358859, differences 0 |
| diffvm | PQS | 4 | 6,292k | 0 | compiled 1930985, fallbacks 32686, rows compared 1898079, differences 0 |
| diffvm | PQS | 5 | 5,742k | 0 | compiled 1233069, fallbacks 20900, rows compared 1212009, differences 0 |
| diffvm | QUERY_PARTITIONING | 4 | 4,563k | 0 | compiled 1112287, fallbacks 13529, rows compared 6342633, differences 0 |
| diffvm | QUERY_PARTITIONING | 5 | 4,430k | 0 | compiled 946253, fallbacks 8394, rows compared 6462096, differences 0 |
| qvm | NoREC | 4 | 4,755k | 0 | served 1116075, fallbacks 25326, refused 8639856 |
| qvm | NoREC | 5 | 5,958k | 0 | served 2017259, fallbacks 40999, refused 10170788 |
| qvm | PQS | 4 | 5,990k | 0 | served 4740265, fallbacks 36342, refused 9190692 |
| qvm | PQS | 5 | 2,348k | 0 | served 1796712, fallbacks 13356, refused 3404063 |
| qvm | QUERY_PARTITIONING | 4 | 2,780k | 0 | served 743766, fallbacks 8815, refused 2745079 |
| qvm | QUERY_PARTITIONING | 5 | 4,694k | 0 | served 951475, fallbacks 8733, refused 4907316 |
| stock | NoREC | 4 | 5,881k | 0 |  |
| stock | NoREC | 5 | 4,853k | 0 |  |
| stock | PQS | 4 | 6,101k | 0 |  |
| stock | PQS | 5 | 2,786k | 0 |  |
| stock | QUERY_PARTITIONING | 4 | 3,367k | 0 |  |
| stock | QUERY_PARTITIONING | 5 | 4,841k | 0 |  |
| turbo | NoREC | 4 | 4,701k | 0 | served 1116075, fallbacks 25326, refused 8529596 |
| turbo | NoREC | 5 | 4,627k | 0 | served 1599882, fallbacks 32553, refused 7869240 |
| turbo | PQS | 4 | 3,496k | 0 | served 1834318, fallbacks 13076, refused 6279453 |
| turbo | PQS | 5 | 1,797k | 0 | served 1379281, fallbacks 9766, refused 2799638 |
| turbo | QUERY_PARTITIONING | 4 | 2,704k | 0 | served 740483, fallbacks 9029, refused 2652094 |
| turbo | QUERY_PARTITIONING | 5 | 4,702k | 0 | served 951585, fallbacks 8623, refused 4916372 |

### speedtest1 (Xeon Platinum 8260, 1 vCPU)

SQLite's own benchmark, unchanged:
- **options:** `--verify --size 100`, file database;
- **values:** median seconds per test over the runs: 6 each for stock and turbo, 3 for qvm and `off`;
- **`off`:** the turbo binary with `QCS_OFF=1`, so qc never runs. It separates qc's work from the build itself
  (patch hooks, code size).

| test | stock | turbo | qvm | off | turbo/stock | qvm/stock | off/stock |
|---|---:|---:|---:|---:|---:|---:|---:|
| 100 Generate a Fossil-like database schema | 0.025 | 0.027 | 0.029 | 0.028 | 1.080 | 1.180 | 1.100 |
| 110 Open and use the database 300 times | 0.074 | 0.082 | 0.090 | 0.072 | 1.101 | 1.208 | 0.966 |
| 120 Create dimension tables | 0.071 | 0.076 | 0.083 | 0.070 | 1.077 | 1.176 | 0.986 |
| 130 Star query over the entire fact table | 0.039 | 0.038 | 0.043 | 0.042 | 0.974 | 1.090 | 1.064 |
| 140 Star query with LEFT JOINs | 0.057 | 0.061 | 0.058 | 0.057 | 1.052 | 1.009 | 0.983 |
| 142 10 SELECTS w/ORDER BY, unindexed | 0.160 | 0.191 | 0.180 | 0.165 | 1.191 | 1.125 | 1.031 |
| 145 10 SELECTS w/ORDER BY and LIMIT, unindexed | 0.079 | 0.137 | 0.084 | 0.077 | 1.734 | 1.063 | 0.975 |
| 150 60000 printf() calls | 0.141 | 0.152 | 0.150 | 0.145 | 1.085 | 1.068 | 1.032 |
| 160 json_insert()/set()/remove() on every row of J2 | 0.134 | 0.132 | 0.144 | 0.133 | 0.989 | 1.079 | 0.996 |
| 161 10000 SELECTS, numeric BETWEEN, PK | 0.052 | 0.055 | 0.054 | 0.052 | 1.048 | 1.029 | 0.990 |
| 170 10000 SELECTS, text BETWEEN, indexed | 0.140 | 0.150 | 0.145 | 0.143 | 1.075 | 1.039 | 1.025 |
| 180 50000 INSERTS with three indexes | 0.175 | 0.165 | 0.197 | 0.178 | 0.940 | 1.126 | 1.017 |
| 190 DELETE and REFILL one table | 0.177 | 0.171 | 0.191 | 0.182 | 0.969 | 1.079 | 1.028 |
| 200 parsing 2500 small reals | 0.015 | 0.018 | 0.016 | 0.015 | 1.200 | 1.067 | 1.000 |
| 210 parsing 2500 large reals | 0.011 | 0.015 | 0.017 | 0.011 | 1.364 | 1.545 | 1.000 |
| 230 10000 UPDATES, numeric BETWEEN, indexed | 0.095 | 0.099 | 0.108 | 0.095 | 1.042 | 1.143 | 1.005 |
| 240 50000 UPDATES of individual rows | 0.156 | 0.152 | 0.163 | 0.154 | 0.978 | 1.045 | 0.987 |
| 250 One big UPDATE of the whole 50000-row table | 0.047 | 0.058 | 0.063 | 0.053 | 1.234 | 1.340 | 1.128 |
| 260 Query added column after filling | 0.003 | 0.004 | 0.003 | 0.003 | 1.167 | 1.000 | 1.000 |
| 270 10000 DELETEs, numeric BETWEEN, indexed | 0.307 | 0.315 | 0.331 | 0.328 | 1.024 | 1.076 | 1.067 |
| 280 50000 DELETEs of individual rows | 0.220 | 0.229 | 0.244 | 0.230 | 1.041 | 1.109 | 1.045 |
| 290 Refill two 50000-row tables using REPLACE | 0.400 | 0.413 | 0.431 | 0.431 | 1.034 | 1.077 | 1.077 |
| 300 Mandelbrot Set with spacing=0.250000 | 0.119 | 0.122 | 0.126 | 0.124 | 1.025 | 1.054 | 1.038 |
| 310 10000 four-ways joins | 0.371 | 0.378 | 0.378 | 0.375 | 1.019 | 1.019 | 1.011 |
| 320 subquery in result set | 0.363 | 0.403 | 0.396 | 0.371 | 1.107 | 1.089 | 1.021 |
| 400 EXCEPT operator on 200000-element tables | 0.084 | 0.097 | 0.098 | 0.090 | 1.148 | 1.160 | 1.071 |
| 410 70000 SELECTS on an IPK | 0.379 | 0.407 | 0.421 | 0.381 | 1.074 | 1.111 | 1.005 |
| 500 70000 REPLACE on TEXT PK | 0.111 | 0.115 | 0.112 | 0.113 | 1.036 | 1.009 | 1.018 |
| 510 70000 SELECTS on a TEXT PK | 0.418 | 0.447 | 0.465 | 0.421 | 1.067 | 1.111 | 1.006 |
| 520 70000 SELECT DISTINCT | 0.049 | 0.024 | 0.018 | 0.056 | 0.490 | 0.367 | 1.143 |
| 980 PRAGMA integrity_check | 0.319 | 0.324 | 0.319 | 0.329 | 1.017 | 1.002 | 1.033 |
| 990 ANALYZE | 0.040 | 0.041 | 0.046 | 0.039 | 1.025 | 1.150 | 0.975 |
| 999 Reset the database | 0.017 | 0.019 | 0.020 | 0.017 | 1.121 | 1.212 | 1.030 |
| 141 queries involving json_type() | 0.002 | 0.004 | 0.003 | 0.002 | 2.000 | 1.500 | 1.000 |
| **total** | 8.145 | 9.046 | 9.300 | 8.004 | 1.111 | 1.142 | 0.983 |

- verification hashes: 1 distinct
  - 34084118 e81c2a91014ffa5f11e7d345457245c385ae79beaa182b11: off.4, off.5, off.6, qvm.1, qvm.2, qvm.3, stock.1, stock.2, stock.3, stock.4, stock.5, stock.6, turbo.1, turbo.2, turbo.3, turbo.4, turbo.5, turbo.6
- turbo: starts 197864, served 191010, rows 472956, refused 6852, fallbacks 2, errors 0, skipped 0, plan 70000, loops 70010, vm 51000
- qvm: starts 197864, served 191010, rows 472956, refused 6852, fallbacks 2, errors 0, skipped 0, plan 0, loops 0, vm 191010
- off: starts 0, served 0, rows 0, refused 0, fallbacks 0, errors 0, skipped 0, plan 0, loops 0, vm 0

What it shows:
- **The serve build itself costs nothing:** `off` is 0.98× stock.
- **qc's work loses on this mix:**
  - turbo (plans first) 1.11×, qvm 1.14×;
  - speedtest1 is mostly writes and tiny one-shot statements;
  - the per-execution overhead of lifting and running a plan in its own transaction shows on statements of a few
    microseconds: 200/210 are 2,500 constant `SELECT`s, 410/510 are 70,000 point lookups.
- **Wins:** 520 (DISTINCT, 0.49× / 0.37×, hash sets).
- **The plan tier losing to qvm:** 145 (`ORDER BY a LIMIT 10`, loop plan: 1.73× against qvm's 1.06×).
- **Two runs on the same box disagree by up to ±10 %:** stock alone ranged 7.76–8.81 s, so read single tests with
  care. Same-box pairs (the broker's reading of `meta.json`'s host):
  - turbo against stock: +15 % (box2) and +20 % (box1) in rounds 1 and 3;
  - turbo against `off`: +12 %, +13 % and −2 % in rounds 4–6.

  So turbo's cost on speedtest1 is real, somewhere around +5–15 %. It concentrates in many short statements (schema
  creation and reset, 70,000 point SELECTs) and in test 145.
- **Compiler:** every Xeon arm was built with clang 18 (`out/cflags-*.txt`). The gcc-only x86-64 wrong-rows bug in
  `qv_idxcmp` (exp357) doesn't affect these numbers.
- **On the M5 (local) the same build is faster:** turbo 0.81–0.89× stock.

### TPC-H SF0.1 (Xeon)

What was run:
- **Data:** dbgen (tpch-kit 852ad0a), loaded by `bench/tpch/load.c`. DECIMAL is REAL, dates are TEXT, primary keys,
  and foreign-key and date indexes, then ANALYZE (`schema.sql`, `indexes.sql`).
- **Queries:** the 22 queries with the spec's validation parameters, in SQLite's dialect (`queries.sql`).
- **Values:** median ms over 3 runs, each run the median of 3 executions after a first one.
- **Executor column:** P specialised plan, L loop plan, V qvm, S SQLite, with qc's reason.

| query | rows | stock ms | turbo ms | qvm ms | turbo/stock | qvm/stock | turbo | qvm | same rows |
|---|---:|---:|---:|---:|---:|---:|---|---|---|
| Q01 | 4 | 1576.17 | 1593.93 | 1540.83 | 1.011 | 0.978 | S (sorter would spill) | S (sorter would spill) | yes |
| Q02 | 44 | 34.48 | 33.91 | 32.01 | 0.983 | 0.928 | V | V | yes |
| Q03 | 10 | 198.73 | 200.21 | 186.40 | 1.007 | 0.938 | V | V | yes |
| Q04 | 5 | 27.40 | 28.26 | 27.00 | 1.032 | 0.985 | V | V | yes |
| Q05 | 5 | 86.53 | 87.43 | 81.40 | 1.010 | 0.941 | V | V | yes |
| Q06 | 1 | 145.90 | 136.69 | 139.23 | 0.937 | 0.954 | V | V | yes |
| Q07 | 4 | 899.92 | 920.60 | 861.81 | 1.023 | 0.958 | V | V | yes |
| Q08 | 2 | 225.26 | 232.63 | 217.65 | 1.033 | 0.966 | V | V | yes |
| Q09 | 175 | 274.09 | 492.31 | 476.19 | 1.796 | 1.737 | S (sorter would spill) | S (sorter would spill) | yes |
| Q10 | 20 | 55.78 | 96.87 | 93.96 | 1.737 | 1.684 | S (sorter would spill) | S (sorter would spill) | yes |
| Q11 | 22 | 10.91 | 11.39 | 10.95 | 1.044 | 1.004 | V | V | yes |
| Q12 | 2 | 190.13 | 210.01 | 206.91 | 1.105 | 1.088 | V | V | yes |
| Q13 | 37 | 239.31 | 244.49 | 233.74 | 1.022 | 0.977 | V | V | yes |
| Q14 | 1 | 21.20 | 20.53 | 19.96 | 0.968 | 0.942 | V | V | yes |
| Q15 | 1 | 42.70 | 44.00 | 42.98 | 1.031 | 1.007 | V | V | yes |
| Q16 | 2762 | 16.68 | 17.75 | 17.57 | 1.064 | 1.054 | V | V | yes |
| Q17 | 1 | 8.74 | 9.00 | 8.82 | 1.030 | 1.009 | V | V | yes |
| Q18 | 5 | 121.88 | 131.33 | 132.19 | 1.078 | 1.085 | V | V | yes |
| Q19 | 1 | 5.55 | 5.96 | 5.83 | 1.075 | 1.051 | V | V | yes |
| Q20 | 9 | 13.68 | 14.10 | 13.09 | 1.031 | 0.957 | V | V | yes |
| Q21 | 47 | 92.47 | 91.57 | 87.74 | 0.990 | 0.949 | V | V | yes |
| Q22 | 7 | 8.13 | 8.27 | 8.28 | 1.018 | 1.019 | V | V | yes |
| **geomean vs stock** | |  |  |  | 1.076 | 1.039 | | | |

- first executions (cold, lift included), sum of medians: stock 4328.1 ms, turbo 4687.7 ms, qvm 4553.5 ms
- turbo: starts 88, served 76, rows 11864, refused 0, fallbacks 12, errors 0, skipped 0, plan 0, loops 0, vm 76
- qvm: starts 88, served 76, rows 11864, refused 0, fallbacks 12, errors 0, skipped 0, plan 0, loops 0, vm 76

Every query is either qvm (V) or falls back (S):
- **The fallbacks:** Q01, Q09 and Q10, each with "sorter would spill". qvm builds the whole sort, finds it larger than
  SQLite's in-memory sorter budget (cache_size bytes, 2 MB by default), and hands back. SQLite then runs the statement
  from the beginning: Q09 at 1.80× and Q10 at 1.74× are that double run.
- **The rest:** qvm-only is 0.93–1.09× stock, turbo 0.94–1.11×.

**SF1:**
- **Doesn't fit the Xeon:** 1.9 GB RAM and 180 s per run, build included, with nothing kept between runs. Generating
  and loading SF1 alone takes longer than that.
- **So it ran locally:** Docker on the M5, 3 rounds, the median of 2 executions after the first.

| query | rows | stock ms | turbo ms | qvm ms | turbo/stock | qvm/stock | turbo | qvm | same rows |
|---|---:|---:|---:|---:|---:|---:|---|---|---|
| Q01 | 4 | 14761.82 | 14384.63 | 15283.98 | 0.974 | 1.035 | S (sorter would spill) | S (sorter would spill) | yes |
| Q02 | 100 | 363.38 | 331.51 | 424.59 | 0.912 | 1.168 | V | V | yes |
| Q03 | 10 | 2454.96 | 2457.13 | 3135.69 | 1.001 | 1.277 | V | V | yes |
| Q04 | 5 | 360.04 | 307.08 | 542.53 | 0.853 | 1.507 | V | V | yes |
| Q05 | 5 | 1244.75 | 1417.18 | 1886.95 | 1.139 | 1.516 | V | V | yes |
| Q06 | 1 | 1802.99 | 1771.71 | 1656.38 | 0.983 | 0.919 | V | V | yes |
| Q07 | 4 | 11255.47 | 9903.61 | 13397.84 | 0.880 | 1.190 | V | V | yes |
| Q08 | 2 | 2644.10 | 2453.77 | 2466.38 | 0.928 | 0.933 | V | V | yes |
| Q09 | 175 | 3653.49 | 3693.61 | 3808.46 | 1.011 | 1.042 | S (sorter would spill) | S (sorter would spill) | yes |
| Q10 | 20 | 604.45 | 603.35 | 637.53 | 0.998 | 1.055 | S (sorter would spill) | S (sorter would spill) | yes |
| Q11 | 1048 | 88.44 | 81.77 | 104.34 | 0.925 | 1.180 | V | V | yes |
| Q12 | 2 | 1015.45 | 1018.59 | 1121.75 | 1.003 | 1.105 | V | V | yes |
| Q13 | 42 | 2371.49 | 4035.65 | 4089.95 | 1.702 | 1.725 | S (sorter would spill) | S (sorter would spill) | yes |
| Q14 | 1 | 237.84 | 302.10 | 238.02 | 1.270 | 1.001 | V | V | yes |
| Q15 | 1 | 530.85 | 717.37 | 545.66 | 1.351 | 1.028 | S (sorter would spill) | S (sorter would spill) | yes |
| Q16 | 18314 | 94.72 | 114.56 | 107.89 | 1.209 | 1.139 | S (sorter would spill) | S (sorter would spill) | yes |
| Q17 | 1 | 68.53 | 65.36 | 67.28 | 0.954 | 0.982 | V | V | yes |
| Q18 | 57 | 804.85 | 877.07 | 640.95 | 1.090 | 0.796 | V | V | yes |
| Q19 | 1 | 78.35 | 70.15 | 53.34 | 0.895 | 0.681 | V | V | yes |
| Q20 | 186 | 326.02 | 248.83 | 192.82 | 0.763 | 0.591 | V | V | yes |
| Q21 | 100 | 1290.85 | 1129.28 | 1062.74 | 0.875 | 0.823 | V | V | yes |
| Q22 | 7 | 42.18 | 44.11 | 43.66 | 1.046 | 1.035 | V | V | yes |
| **geomean vs stock** | |  |  |  | 1.018 | 1.048 | | | |

- first executions (cold, lift included), sum of medians: stock 46943.6 ms, turbo 48462.5 ms, qvm 52599.1 ms
- turbo: starts 66, served 48, rows 4590, refused 0, fallbacks 18, errors 0, skipped 0, plan 0, loops 0, vm 48
- qvm: starts 66, served 48, rows 4590, refused 0, fallbacks 18, errors 0, skipped 0, plan 0, loops 0, vm 48

What SF1 shows:
- **Spill fallbacks:** Q01, Q09, Q10, Q13, Q15 and Q16 fall back with "sorter would spill". Q13 costs 1.70× (the
  double run).
- **Q09 and Q10 at SF1:** these fall back early enough to cost almost nothing.
- **Noise:** this run shared the M5 with other sessions. Q04 runs in qvm in both arms and still comes out 0.85×
  in one and 1.51× in the other, so read single SF1 rows as noisy; the Xeon SF0.1 table is the careful one.

### ClickBench (SQLite entry, first 1M rows)

ClickBench has a SQLite entry (`sqlite/` at db61f6ad: `create.sql`, 43 queries, every field imported as text).
Published numbers, 2025-07-12:
- **c6a.xlarge:** load 3,496 s, a 75.8 GB database, hot runs summing to 12,433 s;
- **c6a.large:** 19,920 s;
- **Q28:** not run, because it used REGEXP_REPLACE then; today's file uses SUBSTR/INSTR.

The full table isn't feasible here: about 14 hours a run for each of 3 arms, and 75 GB. So we run the first 1,000,000
records of `hits.csv`:
- **The data:** an HTTP range of the .gz, cut at a record boundary, SHA-256 pinned. 841 MB of CSV, loaded the way
  ClickBench loads SQLite.
- **Scaling:** stock SQLite on the M5 takes 14.5 s cold for all 43 queries. Scaled ×100 rows, that's about 1,450 s,
  against the published 12,433 s on c6a.xlarge, which is I/O-bound with 75 GB on an 8 GB machine.
- **What it compares:** like with like (stock vs turbo, same machine, same data), not against the published table.

Default settings, ClickBench's own (median ms over 3 runs of the median of 2):

| query | rows | stock ms | turbo ms | qvm ms | turbo/stock | qvm/stock | turbo | qvm | same rows |
|---|---:|---:|---:|---:|---:|---:|---|---|---|
| Q00 | 1 | 16.02 | 13.92 | 21.79 | 0.869 | 1.360 | V | V | yes |
| Q01 | 1 | 218.07 | 205.60 | 275.02 | 0.943 | 1.261 | V | V | yes |
| Q02 | 1 | 250.22 | 203.40 | 227.25 | 0.813 | 0.908 | V | V | yes |
| Q03 | 1 | 38.53 | 39.04 | 50.84 | 1.013 | 1.319 | V | V | yes |
| Q04 | 1 | 88.71 | 61.11 | 53.06 | 0.689 | 0.598 | V | V | yes |
| Q05 | 1 | 315.93 | 250.68 | 280.59 | 0.793 | 0.888 | V | V | yes |
| Q06 | 1 | 47.41 | 57.17 | 66.34 | 1.206 | 1.399 | V | V | yes |
| Q07 | 5 | 223.52 | 234.23 | 258.72 | 1.048 | 1.157 | V | V | yes |
| Q08 | 10 | 347.56 | 398.36 | 397.76 | 1.146 | 1.144 | S (sorter would spill) | S (sorter would spill) | yes |
| Q09 | 10 | 468.53 | 465.22 | 520.23 | 0.993 | 1.110 | S (sorter would spill) | S (sorter would spill) | yes |
| Q10 | 10 | 267.86 | 222.53 | 222.84 | 0.831 | 0.832 | V | V | yes |
| Q11 | 10 | 246.57 | 239.86 | 226.27 | 0.973 | 0.918 | V | V | yes |
| Q12 | 10 | 249.77 | 270.55 | 342.19 | 1.083 | 1.370 | S (sorter would spill) | S (sorter would spill) | yes |
| Q13 | 10 | 279.31 | 291.43 | 285.69 | 1.043 | 1.023 | S (sorter would spill) | S (sorter would spill) | yes |
| Q14 | 10 | 276.41 | 344.05 | 315.91 | 1.245 | 1.143 | S (sorter would spill) | S (sorter would spill) | yes |
| Q15 | 10 | 128.75 | 131.97 | 149.22 | 1.025 | 1.159 | S (sorter would spill) | S (sorter would spill) | yes |
| Q16 | 10 | 436.29 | 438.76 | 396.72 | 1.006 | 0.909 | S (sorter would spill) | S (sorter would spill) | yes |
| Q17 | 10 | 324.16 | 370.14 | 291.53 | 1.142 | 0.899 | S (sorter would spill) | S (sorter would spill) | yes |
| Q18 | 10 | 560.91 | 677.06 | 633.03 | 1.207 | 1.129 | S (sorter would spill) | S (sorter would spill) | yes |
| Q19 | 0 | 29.51 | 35.03 | 34.30 | 1.187 | 1.162 | V | V | yes |
| Q20 | 1 | 299.75 | 276.74 | 293.09 | 0.923 | 0.978 | V | V | yes |
| Q21 | 1 | 277.59 | 299.00 | 255.85 | 1.077 | 0.922 | V | V | yes |
| Q22 | 10 | 246.78 | 290.48 | 270.38 | 1.177 | 1.096 | V | V | yes |
| Q23 | 10 | 264.04 | 292.51 | 296.14 | 1.108 | 1.122 | S (qvm program) | S (qvm program) | yes |
| Q24 | 10 | 241.22 | 224.74 | 253.84 | 0.932 | 1.052 | V | V | yes |
| Q25 | 10 | 243.78 | 212.63 | 230.71 | 0.872 | 0.946 | V | V | yes |
| Q26 | 10 | 237.23 | 224.53 | 255.65 | 0.946 | 1.078 | V | V | yes |
| Q27 | 2 | 317.06 | 284.74 | 277.80 | 0.898 | 0.876 | V | V | yes |
| Q28 | 2 | 1286.11 | 1477.25 | 1235.62 | 1.149 | 0.961 | S (sorter would spill) | S (sorter would spill) | yes |
| Q29 | 1 | 1269.85 | 1274.75 | 1247.94 | 1.004 | 0.983 | S (qvm program) | S (qvm program) | yes |
| Q30 | 10 | 286.06 | 526.50 | 419.89 | 1.841 | 1.468 | S (sorter would spill) | S (sorter would spill) | yes |
| Q31 | 10 | 298.92 | 390.32 | 389.75 | 1.306 | 1.304 | S (sorter would spill) | S (sorter would spill) | yes |
| Q32 | 10 | 614.81 | 713.84 | 608.64 | 1.161 | 0.990 | S (sorter would spill) | S (sorter would spill) | yes |
| Q33 | 10 | 583.07 | 689.03 | 627.78 | 1.182 | 1.077 | S (sorter would spill) | S (sorter would spill) | yes |
| Q34 | 10 | 764.40 | 797.74 | 765.13 | 1.044 | 1.001 | S (sorter would spill) | S (sorter would spill) | yes |
| Q35 | 10 | 365.45 | 451.19 | 510.53 | 1.235 | 1.397 | S (sorter would spill) | S (sorter would spill) | yes |
| Q36 | 10 | 240.26 | 293.16 | 321.11 | 1.220 | 1.337 | S (sorter would spill) | S (sorter would spill) | yes |
| Q37 | 10 | 191.05 | 267.15 | 210.63 | 1.398 | 1.103 | S (sorter would spill) | S (sorter would spill) | yes |
| Q38 | 10 | 133.22 | 248.63 | 220.27 | 1.866 | 1.653 | S (sorter would spill) | S (sorter would spill) | yes |
| Q39 | 10 | 665.51 | 597.52 | 594.70 | 0.898 | 0.894 | S (sorter would spill) | S (sorter would spill) | yes |
| Q40 | 10 | 137.97 | 143.57 | 133.06 | 1.041 | 0.964 | V | V | yes |
| Q41 | 0 | 133.11 | 139.98 | 117.65 | 1.052 | 0.884 | V | V | yes |
| Q42 | 0 | 186.73 | 253.55 | 236.57 | 1.358 | 1.267 | S (sorter would spill) | S (sorter would spill) | yes |
| **geomean vs stock** | |  |  |  | 1.071 | 1.075 | | | |

- first executions (cold, lift included), sum of medians: stock 14480.7 ms, turbo 15610.5 ms, qvm 15506.4 ms
- turbo: starts 129, served 60, rows 258, refused 6, fallbacks 63, errors 0, skipped 0, plan 0, loops 0, vm 60
- qvm: starts 129, served 60, rows 258, refused 6, fallbacks 63, errors 0, skipped 0, plan 0, loops 0, vm 60

The same with `QRUN_SETUP="PRAGMA temp_store=MEMORY"`, which lifts qvm's sorter budget (the in-memory temp store never
spills):

| query | rows | stock ms | turbo ms | qvm ms | turbo/stock | qvm/stock | turbo | qvm | same rows |
|---|---:|---:|---:|---:|---:|---:|---|---|---|
| Q00 | 1 | 17.20 | 16.49 | 17.29 | 0.959 | 1.005 | V | V | yes |
| Q01 | 1 | 195.94 | 226.45 | 221.34 | 1.156 | 1.130 | V | V | yes |
| Q02 | 1 | 211.75 | 247.19 | 218.98 | 1.167 | 1.034 | V | V | yes |
| Q03 | 1 | 44.41 | 38.04 | 40.34 | 0.857 | 0.908 | V | V | yes |
| Q04 | 1 | 99.13 | 49.84 | 50.37 | 0.503 | 0.508 | V | V | yes |
| Q05 | 1 | 294.07 | 204.52 | 215.78 | 0.695 | 0.734 | V | V | yes |
| Q06 | 1 | 49.03 | 52.91 | 53.24 | 1.079 | 1.086 | V | V | yes |
| Q07 | 5 | 193.88 | 204.68 | 240.08 | 1.056 | 1.238 | V | V | yes |
| Q08 | 10 | 386.62 | 304.50 | 303.40 | 0.788 | 0.785 | V | V | yes |
| Q09 | 10 | 407.67 | 347.93 | 346.00 | 0.853 | 0.849 | V | V | yes |
| Q10 | 10 | 194.58 | 189.24 | 230.12 | 0.973 | 1.183 | V | V | yes |
| Q11 | 10 | 214.53 | 198.73 | 206.59 | 0.926 | 0.963 | V | V | yes |
| Q12 | 10 | 230.22 | 200.20 | 221.05 | 0.870 | 0.960 | V | V | yes |
| Q13 | 10 | 213.01 | 239.14 | 239.25 | 1.123 | 1.123 | V | V | yes |
| Q14 | 10 | 240.66 | 242.48 | 277.66 | 1.008 | 1.154 | V | V | yes |
| Q15 | 10 | 111.98 | 97.88 | 111.70 | 0.874 | 0.997 | V | V | yes |
| Q16 | 10 | 375.61 | 320.48 | 322.74 | 0.853 | 0.859 | V | V | yes |
| Q17 | 10 | 290.76 | 302.55 | 300.05 | 1.041 | 1.032 | V | V | yes |
| Q18 | 10 | 457.39 | 436.90 | 458.66 | 0.955 | 1.003 | V | V | yes |
| Q19 | 0 | 41.74 | 34.09 | 35.00 | 0.817 | 0.839 | V | V | yes |
| Q20 | 1 | 281.28 | 251.41 | 224.92 | 0.894 | 0.800 | V | V | yes |
| Q21 | 1 | 243.15 | 263.78 | 225.43 | 1.085 | 0.927 | V | V | yes |
| Q22 | 10 | 205.83 | 213.97 | 207.00 | 1.040 | 1.006 | V | V | yes |
| Q23 | 10 | 265.32 | 235.10 | 222.95 | 0.886 | 0.840 | S (qvm program) | S (qvm program) | yes |
| Q24 | 10 | 253.52 | 268.73 | 211.22 | 1.060 | 0.833 | V | V | yes |
| Q25 | 10 | 189.96 | 250.10 | 204.32 | 1.317 | 1.076 | V | V | yes |
| Q26 | 10 | 195.11 | 291.14 | 211.45 | 1.492 | 1.084 | V | V | yes |
| Q27 | 2 | 263.91 | 364.05 | 275.42 | 1.379 | 1.044 | V | V | yes |
| Q28 | 2 | 1167.31 | 1244.35 | 1190.58 | 1.066 | 1.020 | V | V | yes |
| Q29 | 1 | 1141.20 | 1255.45 | 1106.90 | 1.100 | 0.970 | S (qvm program) | S (qvm program) | yes |
| Q30 | 10 | 267.88 | 292.24 | 261.81 | 1.091 | 0.977 | V | V | yes |
| Q31 | 10 | 366.86 | 278.91 | 229.58 | 0.760 | 0.626 | V | V | yes |
| Q32 | 10 | 1200.48 | 781.48 | 662.23 | 0.651 | 0.552 | V | V | yes |
| Q33 | 10 | 1068.14 | 908.84 | 814.62 | 0.851 | 0.763 | V | V | yes |
| Q34 | 10 | 1081.71 | 955.51 | 952.11 | 0.883 | 0.880 | V | V | yes |
| Q35 | 10 | 518.05 | 386.40 | 491.19 | 0.746 | 0.948 | V | V | yes |
| Q36 | 10 | 436.07 | 369.87 | 467.03 | 0.848 | 1.071 | V | V | yes |
| Q37 | 10 | 304.51 | 256.29 | 357.12 | 0.842 | 1.173 | V | V | yes |
| Q38 | 10 | 119.25 | 92.00 | 114.52 | 0.771 | 0.960 | V | V | yes |
| Q39 | 10 | 666.20 | 958.27 | 937.09 | 1.438 | 1.407 | V | V | yes |
| Q40 | 10 | 122.87 | 123.71 | 154.31 | 1.007 | 1.256 | V | V | yes |
| Q41 | 0 | 138.91 | 126.91 | 163.53 | 0.914 | 1.177 | V | V | yes |
| Q42 | 0 | 303.69 | 233.06 | 253.36 | 0.767 | 0.834 | V | V | yes |
| **geomean vs stock** | |  |  |  | 0.943 | 0.949 | | | |

- first executions (cold, lift included), sum of medians: stock 15081.0 ms, turbo 15136.8 ms, qvm 14139.9 ms
- turbo: starts 129, served 123, rows 834, refused 6, fallbacks 0, errors 0, skipped 0, plan 0, loops 0, vm 123
- qvm: starts 129, served 123, rows 834, refused 6, fallbacks 0, errors 0, skipped 0, plan 0, loops 0, vm 123

What it shows:
- **At default settings:** 21 of 43 queries fall back with "sorter would spill" after doing the work, and turbo is
  1.07× stock overall.
- **Without the spill limit:** nothing falls back, every query runs in qvm, and turbo is 0.94× stock. The executor is
  faster on these scans and aggregations; the fallback policy costs it the difference.
- **Refusals:** Q23 (`SELECT * … ORDER BY EventTime LIMIT 10`, 105 columns) and Q29 (90 `SUM`s), both "qvm
  program".

### Fallback and refusal reasons (`QCS_STATS`)

| source | statements started | served | fell back (why) | refused (why) |
|---|---:|---:|---|---|
| speedtest1 | 197,864 | 191,010 | 2 | 6,852: "qvm program" (6,250: the 100-column Fossil schema query), "VOpen" (600: `pragma_table_*` table-valued functions) |
| TPC-H SF0.1 | 88 | 76 | 12: sorter would spill (Q01, Q09, Q10) | 0 |
| ClickBench 1M | 129 | 60 | 63: sorter would spill (21 queries) | 6: qvm program (Q23, Q29) |
| ClickBench 1M, temp_store=MEMORY | 129 | 123 | 0 | 6: as above |
| SQLancer NoREC, turbo | 13.0M | 1.66M | 36.6k: function error, vec deopt | 11.4M: mostly "Function" (built-ins qvm doesn't call); this run predates the shim reporting qvm's lift-time reasons, so the rest have none |

The engine's own per-statement counters (rebuilds, deopts, widenings, fallbacks) weren't on `main` when this ran. These
counts come from `bench/qc_serve.c`.

### Notes for whoever runs this next

- **One arm per Xeon run.** Paired arms showed a second-arm effect, and box1 and box2 differ by a few percent, so arms
  are rotated across rounds. Six stock runs ranged 7.76–8.81 s.
- **The first serve shim** re-parsed `BEGIN`/`COMMIT` with `sqlite3_exec` for every autocommit statement. That cost
  turbo on point lookups (Xeon test 510: 1.29× in exp364 against 1.07× now). It is fixed, and those Xeon runs (exp360–377)
  are not in these tables.
- **SQLancer's PQS** sets `mmap_size`, so until finding 2 is fixed every PQS campaign crashes early. NoREC and TLP
  reach mmap less often.
