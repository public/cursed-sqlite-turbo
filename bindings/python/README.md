# turbo_sqlite3

`sqlite3` for Python on cursed-sqlite-turbo's SQLite. It is CPython's own `sqlite3` module (`Modules/_sqlite` and
`Lib/sqlite3`, for the Python building it), compiled against turbo's patched amalgamation with qc and qvm. Read-only
statements are served by turbo inside `sqlite3_step` when it can reproduce SQLite's results exactly; everything else
runs in SQLite's interpreter. The API is the standard library's, release for release: same classes, arguments,
exceptions, `autocommit`, `blobopen`, `iterdump`, `cached_statements`. The only additions are four functions listed
below.

```sh
pip install ./bindings/python        # from the repository root; Python 3.10–3.15 (not free-threaded), macOS or Linux
```

The build needs a C compiler, `make`, `curl` and `unzip`, and network access. It runs the repository's `make all`
(SQLite 3.54.1, pinned) and fetches the running Python's `sqlite3` module source from python.org
(`scripts/fetch_cpython_sqlite.py`: one pinned, SHA-256-checked release per minor version). Nothing fetched is
committed.

## Using it

```python
import turbo_sqlite3 as sqlite3
```

**Code that imports `sqlite3` itself** (Django, for one): put turbo_sqlite3 in its place before the first
`import sqlite3`, at the top of `manage.py` / `wsgi.py` / `asgi.py`:

```python
import sys, turbo_sqlite3; sys.modules["sqlite3"] = turbo_sqlite3     # or: turbo_sqlite3.install()
```

`install()` also maps `sqlite3.dbapi2` and `sqlite3.dump`. A module that imported the stdlib's `sqlite3` before
this line keeps it.

**SQLAlchemy:**

```python
engine = create_engine("sqlite:///app.db", module=turbo_sqlite3)
engine = create_engine("sqlite://", module=turbo_sqlite3,
                       creator=lambda: turbo_sqlite3.connect("app.db", check_same_thread=False))
```

Pass `module=` together with `creator=`. With `creator=` alone the dialect stays on the stdlib's module, and
turbo_sqlite3's exceptions are not translated into SQLAlchemy's.

**Turning turbo off,** to rule it out:
- `QC_SERVE=0` in the environment: turbo's own switch. The module is then the stdlib's on SQLite 3.54.1.
- `turbo_sqlite3.enable_turbo(False)` at run time, process-wide (`True` turns it back on). It returns the previous
  state. Statements already being served finish.
- `turbo_sqlite3.turbo_enabled()` tells which applies.
- `turbo_sqlite3.turbo_counts()` returns three counts for this process: runs served by turbo, rows they handed out,
  and runs left to the interpreter because another thread was inside turbo.

**Statement cache:** `cached_statements` works as in the stdlib. A cached statement keeps turbo's plan with it.
With the cache off (`cached_statements=0`), turbo's own plan cache finds the plan again by statement text and
connection.

## Threads

Python releases the GIL inside `sqlite3_step`, and turbo's run state is per process, not per connection. So
`csrc/turbo.c` runs turbo's hooks under one process-wide lock:
- A statement that starts while another thread is inside turbo doesn't wait: it runs in SQLite's interpreter.
  Its results are the same either way, and threads never queue behind each other.
- The lock is never held while sleeping on a busy lock. Turbo's read transaction gives up at once, and the
  interpreter waits out `timeout` outside the lock, so a writer in another thread can still commit.
- Turbo's streaming (results handed out while the plan runs) is built off, because a paused stream is finished by
  whichever statement runs next, on any connection.

`check_same_thread=False` works as in the stdlib, with the same caveat: use a connection from one thread at a time.
CPython's module, stdlib included, returns wrong rows and "bad parameter or other API misuse" errors when two threads
use one connection at the same moment, because its statement cache hands both threads the same statement.

There is one deadlock that stock doesn't have. It needs all of these at once:
- a Python function or collation, called from a statement turbo serves,
- which runs SQL on a second connection,
- while another thread is using that second connection.

## Differences from the stdlib

- SQLite is 3.54.1 with turbo's patches, built with `SQLITE_THREADSAFE=1`, FTS3/4/5, R*Tree and math functions,
  and without STAT4. The query planner can choose differently from your system's SQLite build: the benchmark's
  `count distinct` is 130× faster here than on Homebrew's STAT4 build, which is a plan choice, not turbo.
- A served statement's `sqlite3_stmt_status` counters stay 0 (no Python API reads them).

## Tests

```sh
pip install pytest && pytest bindings/python/tests
```

- **CPython's own `test_sqlite3`,** from the running Python's `test` package, with `sqlite3` replaced by
  turbo_sqlite3. It runs once with turbo on and once with `QC_SERVE=0`. On 3.14: 513 tests, 0 failures, both on and off. It is skipped where Python ships without `test`, such as uv's python-build-standalone.
- **tests/corpus.c's 61 statements** on a small `scripts/gen-db.py` database, with generated parameters. Each runs
  through turbo, compared row for row with turbo off on the same connection, and as a multiset with the stdlib's
  `sqlite3`. All 61 are served.
- **Threads:** eight threads with their own connections; a shared connection handed between threads; Python
  functions inside served statements; writers alongside readers; a reader blocked by another thread's EXCLUSIVE
  lock.
- **Basics:** the off switch, the statement cache, `install()`, transactions, and SQLAlchemy and Django (skipped if
  they aren't installed).

## Benchmark

`bench/bench.py` times corpus statements end to end through Python, binding overhead included: execute, bind, step,
a tuple per row, `fetchall`. It reads the repository's `build/test.db` (`make db`: 50k users, 200k posts, 800k
likes) and reports µs per execution, the median of rounds that rotate the order of the three columns.

The "on / off" column is turbo's own effect: the same module and SQLite, with turbo on and off. The stdlib column
adds the effect of a different SQLite build.

Apple M5 Pro, macOS, Python 3.14.8 (Homebrew; its stdlib SQLite is 3.53.4 with STAT4), 21 rounds of 200
executions:

| statement | rows | stdlib µs | turbo off µs | turbo on µs | on / stdlib | on / off |
|---|---:|---:|---:|---:|---:|---:|
| pk point | 1 | 3.78 | 3.55 | 3.25 | 0.86× | 0.92× |
| join 1-n via index | 4 | 13.21 | 13.01 | 12.74 | 0.96× | 0.98× |
| feed (spec query) | 20 | 36.19 | 34.70 | 13.99 | 0.39× | 0.40× |
| group by index | 20 | 13.47 | 8.99 | 8.48 | 0.63× | 0.94× |
| order by, top-n | 3 | 14.26 | 10.40 | 8.75 | 0.61× | 0.84× |
| union | 20 | 12.39 | 6.64 | 6.01 | 0.48× | 0.90× |
| window rank, partition | 16 | 53.82 | 59.76 | 44.08 | 0.82× | 0.74× |
| count distinct | 1 | 17644.76 | 153.41 | 139.80 | 0.01× | 0.91× |
| group by, sorter | 10 | 367.49 | 344.43 | 307.89 | 0.84× | 0.89× |
| in (subselect) | 12 | 27.55 | 20.34 | 18.17 | 0.66× | 0.89× |

The machine was busy (load average around 10) during three runs (9, 15 and 21 rounds), so treat single
numbers as rough. The on / off ratio was stable for the feed (0.40–0.45×), top-N (0.79–0.84×), the point
lookup (0.91–0.97×), `count distinct` (0.91–0.95×) and `in (subselect)` (0.89–0.94×). It moved between runs for
`window rank` (0.74–1.16×), `union` (0.90–1.09×) and `group by index` (0.94–1.02×): rerun on a quiet machine
before reading a win or a loss into those. As expected, the per-row cost of building Python tuples hides most
of turbo's gain on small results; the feed, with its correlated count subquery, keeps most of it.

## Wheels

`pyproject.toml` has a cibuildwheel configuration for these targets, CPython 3.10–3.15:
- manylinux_2_28 x86_64 and aarch64;
- musllinux_1_2 x86_64 and aarch64;
- macOS arm64 and x86_64.

Run it from the repository root, because the build needs `qc/`, `scripts/` and the Makefile:

```sh
cibuildwheel bindings/python --platform linux --archs aarch64
```

Wheels are built per Python version: the module uses CPython's internal headers, as the stdlib's does, so there is
no abi3 wheel. Nothing is published.

## Licences

- CPython's `sqlite3` module: PSF licence. Its `LICENSE` ships in the package as `LICENSE.cpython`, and the altered
  files say so in their first line.
- SQLite: public domain.
- turbo (qc, qvm, the patch and `csrc/`): MIT, the repository's licence.
