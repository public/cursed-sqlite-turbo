"""turbo_sqlite3 from several threads. Python releases the GIL in sqlite3_step, so threads step their connections at
once; qc's run state is the connection's, under its mutex, so turbo serves every thread (no lock of csrc/turbo.c's,
streaming on). Expected results come from turbo off, before the threads start."""
import shutil, threading, time


import turbo_sqlite3
from conftest import Params, corpus

THREADS, ROUNDS = 8, 3
JOIN = 120   # seconds: a thread still alive after this is a deadlock


def work(db, seed, n):
    con = turbo_sqlite3.connect(db)
    p = Params(con, seed)
    qs = corpus()
    out = [(sql, p(kinds)) for _ in range(n) for name, sql, kinds in qs]
    con.close()
    return out


def expected(db, items):
    con = turbo_sqlite3.connect(db)
    turbo_sqlite3.enable_turbo(False)
    try:
        return [con.execute(sql, args).fetchall() for sql, args in items]
    finally:
        turbo_sqlite3.enable_turbo(True)
        con.close()


def run_threads(targets):
    errors, ts = [], []
    def wrap(fn):
        def go():
            try:
                fn()
            except BaseException as e:   # noqa: B036 (reported below)
                errors.append(repr(e))
        return go
    ts = [threading.Thread(target=wrap(t), daemon=True) for t in targets]
    for t in ts:
        t.start()
    for t in ts:
        t.join(JOIN)
    assert not any(t.is_alive() for t in ts), "a thread is stuck (deadlock?)"
    assert not errors, errors[:5]


def test_own_connections(corpus_db):
    jobs = [work(corpus_db, s, ROUNDS) for s in range(THREADS)]
    want = [expected(corpus_db, j) for j in jobs]
    runs = turbo_sqlite3.turbo_counts()[0]

    def thread(i):
        def go():
            con = turbo_sqlite3.connect(corpus_db)
            for (sql, args), w in zip(jobs[i], want[i]):
                assert con.execute(sql, args).fetchall() == w, (sql, args)
        return go
    run_threads([thread(i) for i in range(THREADS)])
    runs2 = turbo_sqlite3.turbo_counts()[0]
    print(f"served {runs2 - runs} of {sum(map(len, jobs))}")
    assert runs2 - runs > sum(map(len, jobs)) // 2   # (every thread served: adapt leaves some runs to the interpreter)


def test_shared_connection(corpus_db):
    """One connection (check_same_thread=False) used by four threads in turn: its cached, served statements move
    between threads. In turn, because CPython's module itself (stdlib sqlite3 too) returns wrong rows and "API misuse"
    when two threads use one connection at the same moment: its statement cache hands both the same statement."""
    con = turbo_sqlite3.connect(corpus_db, check_same_thread=False)
    lock = threading.Lock()
    jobs = [work(corpus_db, 100 + s, 2) for s in range(4)]
    want = [expected(corpus_db, j) for j in jobs]

    def thread(i):
        def go():
            for (sql, args), w in zip(jobs[i], want[i]):
                with lock:
                    got = con.execute(sql, args).fetchall()
                assert got == w, (sql, args)
        return go
    run_threads([thread(i) for i in range(4)])


def test_python_functions_across_threads():
    """Python functions inside served statements on several threads at once: each needs the GIL from inside qc,
    while the other threads are inside qc on their own connections."""
    def thread(seed):
        def go():
            con = turbo_sqlite3.connect(":memory:")
            con.execute("CREATE TABLE t(a INTEGER PRIMARY KEY, g INT)")
            con.executemany("INSERT INTO t VALUES (?,?)", ((i, (i * seed) % 5) for i in range(3000)))
            con.create_function("slow", 1, lambda x: (sum(range(20)), x)[1] * 2, deterministic=True)
            q = "SELECT g, sum(slow(a)) FROM t GROUP BY g ORDER BY g"
            want = None
            for _ in range(30):
                got = con.execute(q).fetchall()
                assert want is None or got == want
                want = got
            assert sum(s for _, s in want) == 2 * sum(range(3000))
        return go
    run_threads([thread(s) for s in range(1, 7)])


def test_writers_and_readers(corpus_db, tmp_path):
    db = str(tmp_path / "rw.db")
    shutil.copyfile(corpus_db, db)   # (WAL, from gen-db.py; checkpointed, so the copy is whole)
    setup = turbo_sqlite3.connect(db)
    setup.execute("CREATE TABLE log(i INTEGER PRIMARY KEY, t INT, v TEXT)")
    setup.commit(), setup.close()
    jobs = [work(db, 200 + s, 1) for s in range(4)]
    want = [expected(db, j) for j in jobs]

    def reader(i):
        def go():
            con = turbo_sqlite3.connect(db, timeout=30)
            for (sql, args), w in zip(jobs[i], want[i]):
                assert con.execute(sql, args).fetchall() == w, (sql, args)
                con.execute("SELECT t, count(*), max(i) FROM log GROUP BY t").fetchall()
        return go

    def writer(t):
        def go():
            con = turbo_sqlite3.connect(db, timeout=30)
            for k in range(40):
                with con:
                    con.execute("INSERT INTO log(t, v) VALUES (?, ?)", (t, "x" * k))
                    con.execute("SELECT count(*) FROM log WHERE t = ?", (t,)).fetchone()   # (a read in the write txn)
        return go
    run_threads([reader(i) for i in range(4)] + [writer(t) for t in range(3)])
    con = turbo_sqlite3.connect(db)
    assert con.execute("SELECT t, count(*) FROM log GROUP BY t").fetchall() == [(0, 40), (1, 40), (2, 40)]


def test_reader_waits_for_writer(tmp_path):
    """Rollback journal: a writer's EXCLUSIVE lock blocks readers. The reader's statement is one qc serves: its read
    transaction waits out the busy timeout as the interpreter's would (the GIL released in sqlite3_step), so the
    writer, in another thread, can commit."""
    db = str(tmp_path / "j.db")
    con = turbo_sqlite3.connect(db)
    con.execute("PRAGMA journal_mode=DELETE")
    con.execute("CREATE TABLE t(a INTEGER PRIMARY KEY, g INT)")
    con.executemany("INSERT INTO t VALUES (?,?)", ((i, i % 3) for i in range(1000)))
    con.commit(), con.close()
    q = "SELECT g, count(*) FROM t GROUP BY g ORDER BY g"
    reader = turbo_sqlite3.connect(db, timeout=10, check_same_thread=False)
    for _ in range(3):
        reader.execute(q).fetchall()   # (lifted and served)
    locked, result = threading.Event(), {}

    def write():
        w = turbo_sqlite3.connect(db, isolation_level=None)
        w.execute("BEGIN EXCLUSIVE")
        w.execute("INSERT INTO t VALUES (1000, 0)")
        locked.set()
        time.sleep(0.5)
        w.execute("COMMIT")
        w.close()

    def read():
        locked.wait()
        t0 = time.monotonic()
        result["rows"] = reader.execute(q).fetchall()
        result["waited"] = time.monotonic() - t0
    run_threads([write, read])
    assert result["rows"] == [(0, 335), (1, 333), (2, 333)]
    assert 0.3 < result["waited"] < 5, result["waited"]
