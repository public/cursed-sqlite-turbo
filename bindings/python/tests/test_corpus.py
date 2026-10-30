"""tests/corpus.c's statements through turbo_sqlite3, against turbo off on the same connection (row for row) and against
the stdlib's sqlite3 (as a multiset: two SQLite versions may order unordered results differently)."""
import sqlite3, zlib

import pytest

import turbo_sqlite3
from conftest import Params, corpus

RUNS = 6   # parameter sets per statement; each set runs twice through turbo (a plan's first run and a cached one)


def norm(rows):
    return sorted(rows, key=repr)


@pytest.mark.parametrize("name,sql,kinds", corpus(), ids=[q[0] for q in corpus()])
def test_statement(corpus_db, name, sql, kinds):
    tc = turbo_sqlite3.connect(corpus_db)
    sc = sqlite3.connect(corpus_db)
    params = Params(tc, seed=zlib.crc32(name.encode()))
    for _ in range(RUNS):
        args = params(kinds)
        turbo_sqlite3.enable_turbo(True)
        on = [tc.execute(sql, args).fetchall() for _ in range(2)]
        turbo_sqlite3.enable_turbo(False)
        off = tc.execute(sql, args).fetchall()
        turbo_sqlite3.enable_turbo(True)
        assert on[0] == off and on[1] == off, f"{name} {args}: turbo differs from SQLite's interpreter"
        stock = sc.execute(sql, args).fetchall()
        if "bare col" not in name:   # (a bare column of a GROUP BY is any row's: versions may pick another)
            assert norm(on[0]) == norm(stock), f"{name} {args}: turbo_sqlite3 differs from stdlib sqlite3"
    tc.close(), sc.close()


def test_corpus_is_served(corpus_db):
    """Most of the corpus is actually served by turbo (else the comparisons above prove little)."""
    tc = turbo_sqlite3.connect(corpus_db)
    params, served = Params(tc, seed=7), 0
    for name, sql, kinds in corpus():
        args = params(kinds)
        before = turbo_sqlite3.turbo_counts()[0]
        for _ in range(3):
            tc.execute(sql, args).fetchall()
        served += turbo_sqlite3.turbo_counts()[0] > before
    print(f"served {served} of {len(corpus())}")
    assert served >= len(corpus()) * 3 // 4, f"only {served} of {len(corpus())} statements served"
