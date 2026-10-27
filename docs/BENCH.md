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

**Reproducing.** `tests/sqlancer/repro.sh <file>` replays a SQLancer log (`replay.c`) on a file database through
stock, turbo, qvm, diff and diffvm, and shows what differs. `reduce.py` minimises a log with ddmin, against a test
script such as `crashes.sh`.

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
  care.
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
