"""turbo_sqlite3's own surface: the off switch, the statement cache, install(), and the DB-API basics it shares with
sqlite3."""
import os, subprocess, sys

import turbo_sqlite3


def served(fn):   # (qc's adapt runs some executions through the interpreter to time it: counts are "most", not "all")
    before = turbo_sqlite3.turbo_counts()[0]
    fn()
    return turbo_sqlite3.turbo_counts()[0] - before


def table(con, n=2000):
    con.execute("CREATE TABLE t(a INTEGER PRIMARY KEY, g INT, s TEXT)")
    con.executemany("INSERT INTO t VALUES (?,?,?)", ((i, i % 7, "s%d" % i) for i in range(n)))
    con.commit()


Q = "SELECT g, count(*), sum(a) FROM t GROUP BY g ORDER BY 2 DESC, 1"


def test_surface():
    assert turbo_sqlite3.sqlite_version_info >= (3, 54, 0)
    assert turbo_sqlite3.threadsafety in (1, 3)   # (3: SQLITE_THREADSAFE=1, serialized)
    assert turbo_sqlite3.apilevel == "2.0" and turbo_sqlite3.paramstyle == "qmark"
    for name in ("connect", "Connection", "Cursor", "Row", "Blob", "Error", "OperationalError", "PARSE_DECLTYPES"):
        assert hasattr(turbo_sqlite3, name), name


def test_served_and_off_switch():
    con = turbo_sqlite3.connect(":memory:")
    table(con)
    expect = con.execute(Q).fetchall()
    assert turbo_sqlite3.turbo_enabled()
    assert served(lambda: [con.execute(Q).fetchall() for _ in range(5)]) > 0
    assert turbo_sqlite3.enable_turbo(False) is True
    assert not turbo_sqlite3.turbo_enabled()
    assert served(lambda: [con.execute(Q).fetchall() for _ in range(3)]) == 0
    assert con.execute(Q).fetchall() == expect
    turbo_sqlite3.enable_turbo(True)
    assert served(lambda: [con.execute(Q).fetchall() for _ in range(5)]) > 0


def test_off_from_environment():
    code = ("import turbo_sqlite3 as t; c = t.connect(':memory:'); c.execute('create table x(a)');"
            "[c.execute('select count(*) from x').fetchall() for _ in range(3)];"
            "print(t.turbo_enabled(), t.turbo_counts()[0]); t.enable_turbo(True);"
            "[c.execute('select count(*) from x').fetchall() for _ in range(3)]; print(t.turbo_counts()[0] > 0)")
    out = subprocess.run([sys.executable, "-c", code], env=dict(os.environ, QC_SERVE="0"), capture_output=True,
                         text=True, check=True).stdout.split()
    assert out == ["False", "0", "True"]


def test_statement_cache_keeps_plans():
    """Python's statement cache hands the same prepared statement back, so turbo's plan stays with it; with the cache
    off every execute prepares afresh, and qc's plan cache (by text and connection) still finds the plan."""
    for cached in (128, 0):
        con = turbo_sqlite3.connect(":memory:", cached_statements=cached)
        table(con)
        expect = con.execute(Q).fetchall()
        n = served(lambda: [con.execute(Q).fetchall() == expect or 1 / 0 for _ in range(20)])
        assert n >= 10, f"cached_statements={cached}: {n} of 20 served"
        con.close()


def test_writes_and_transactions_unchanged():
    con = turbo_sqlite3.connect(":memory:")
    table(con, 100)
    con.execute("UPDATE t SET g = g + 100 WHERE a < 10")
    assert con.execute("SELECT count(*) FROM t WHERE g >= 100").fetchone() == (10,)   # (read inside the transaction)
    con.rollback()
    assert con.execute("SELECT count(*) FROM t WHERE g >= 100").fetchone() == (0,)
    with con:
        con.execute("DELETE FROM t WHERE a % 2")
    assert con.execute("SELECT count(*), sum(a) FROM t").fetchone() == (50, sum(range(0, 100, 2)))


def test_python_functions_in_served_statements():
    con = turbo_sqlite3.connect(":memory:")
    table(con, 500)
    con.create_function("twice", 1, lambda x: x * 2, deterministic=True)
    q = "SELECT g, sum(twice(a)) FROM t GROUP BY g ORDER BY g"
    expect = [(g, 2 * sum(a for a in range(500) if a % 7 == g)) for g in range(7)]
    for _ in range(5):
        assert con.execute(q).fetchall() == expect


def test_install():
    code = ("import turbo_sqlite3; turbo_sqlite3.install(); import sqlite3, sqlite3.dbapi2;"
            "print(sqlite3 is turbo_sqlite3, sqlite3.dbapi2 is turbo_sqlite3.dbapi2, sqlite3.connect(':memory:').__class__.__module__)")
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=True).stdout.split()
    assert out == ["True", "True", "turbo_sqlite3"]
