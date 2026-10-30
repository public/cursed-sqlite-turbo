"""CPython's own test_sqlite3 (the running Python's, from its `test` package) against turbo_sqlite3: sqlite3 is
turbo_sqlite3 in a subprocess, with turbo on and with QC_SERVE=0. Skipped where the Python has no test package."""
import importlib.util, json, os, subprocess, sys

import pytest

# failures with turbo on, each a qc bug reported upstream (the run with turbo off must have none)
KNOWN = {
    # qc serves a statement prepared before ALTER TABLE ADD COLUMN, inside a transaction, with the old columns
    # (repro: a SELECT * stepped once, BEGIN-ed DML, ALTER, the SELECT again; stock re-prepares on SQLITE_SCHEMA)
    "test.test_sqlite3.test_dbapi.CursorTests.test_column_count",
}

RUNNER = r"""
import json, sys, unittest, turbo_sqlite3
turbo_sqlite3.install()
suite = unittest.defaultTestLoader.loadTestsFromName("test.test_sqlite3")
r = unittest.TextTestRunner(stream=open("/dev/null", "w"), verbosity=0).run(suite)
json.dump({"run": r.testsRun, "skipped": len(r.skipped),
           "failed": {t.id(): tb.strip().splitlines()[-1] for t, tb in r.failures + r.errors}}, sys.stdout)
"""


def run_suite(env_extra):
    if importlib.util.find_spec("test.test_sqlite3") is None:
        pytest.skip("this Python has no test.test_sqlite3 (python-build-standalone and some distros leave it out)")
    env = dict(os.environ, **env_extra)
    out = subprocess.run([sys.executable, "-c", RUNNER], env=env, capture_output=True, text=True, timeout=900,
                         cwd=os.path.dirname(__file__))
    assert out.returncode == 0, out.stderr[-3000:]
    return json.loads(out.stdout.strip().splitlines()[-1])   # (the suite prints its SQLite version first)


def test_cpython_suite_turbo_on():
    r = run_suite({})
    assert r["run"] > 100
    unexpected = {t: why for t, why in r["failed"].items() if t not in KNOWN}
    assert not unexpected, json.dumps(unexpected, indent=1)


def test_cpython_suite_turbo_off():
    r = run_suite({"QC_SERVE": "0"})
    assert r["run"] > 100
    assert not r["failed"], json.dumps(r["failed"], indent=1)
