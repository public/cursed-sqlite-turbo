#!/usr/bin/env python3
"""bench.py [DB] [--rounds N]: tests/corpus.c statements end to end through Python (execute, bind, step, build every
row's tuple, fetchall), µs per execution:
  stdlib     the running Python's sqlite3 (its own SQLite build)
  turbo off  turbo_sqlite3 with enable_turbo(False): the same SQLite as turbo on, interpreter only
  turbo on   turbo_sqlite3

DB defaults to the repository's build/test.db (`make db`: 50k users, 200k posts, 800k likes). Each round times every
statement's parameter list once per column, in rotating order; the table gives each column's median round.
"""
import argparse, os, statistics, sys, time

import sqlite3
import turbo_sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tests"))
from conftest import ROOT, Params, corpus  # noqa: E402

PICK = ["pk point", "join 1-n via index", "feed (spec query)", "group by index", "order by, top-n", "union",
        "window rank, partition", "count distinct", "group by, sorter", "in (subselect)"]


def run(con, sql, params):
    for p in params:
        con.execute(sql, p).fetchall()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("db", nargs="?", default=os.path.join(ROOT, "build", "test.db"))
    ap.add_argument("--rounds", type=int, default=9)
    ap.add_argument("--n", type=int, default=200, help="executions per statement per round")
    a = ap.parse_args()
    if not os.path.exists(a.db):
        sys.exit(f"bench: no {a.db} (make db)")
    qs = {name: (sql, kinds) for name, sql, kinds in corpus()}
    stock, tc = sqlite3.connect(a.db), turbo_sqlite3.connect(a.db)
    cols = [("stdlib", stock, None), ("turbo off", tc, False), ("turbo on", tc, True)]
    print(f"Python {sys.version.split()[0]}; stdlib SQLite {sqlite3.sqlite_version}, turbo_sqlite3 SQLite "
          f"{turbo_sqlite3.sqlite_version}; {a.db}; {a.rounds} rounds of {a.n} executions\n")
    print("| statement | rows | stdlib µs | turbo off µs | turbo on µs | on / stdlib | on / off |")
    print("|---|---:|---:|---:|---:|---:|---:|")
    for name in PICK:
        sql, kinds = qs[name]
        gen = Params(tc, seed=1)
        params = [gen(kinds) for _ in range(a.n)]
        rows = sum(len(tc.execute(sql, p).fetchall()) for p in params) / a.n
        times = {c[0]: [] for c in cols}
        for c in cols:   # (warm: plans lifted, statements cached, pages read)
            turbo_sqlite3.enable_turbo(c[2] is not False)
            run(c[1], sql, params[:20])
        for r in range(a.rounds):
            for k in range(len(cols)):
                label, con, on = cols[(k + r) % len(cols)]
                turbo_sqlite3.enable_turbo(on is not False)
                t0 = time.perf_counter_ns()
                run(con, sql, params)
                times[label].append((time.perf_counter_ns() - t0) / 1000 / a.n)
        turbo_sqlite3.enable_turbo(True)
        m = {k: statistics.median(v) for k, v in times.items()}
        print(f"| {name} | {rows:.0f} | {m['stdlib']:.2f} | {m['turbo off']:.2f} | {m['turbo on']:.2f} | "
              f"{m['turbo on'] / m['stdlib']:.2f}× | {m['turbo on'] / m['turbo off']:.2f}× |")


if __name__ == "__main__":
    main()
