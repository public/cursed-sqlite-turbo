"""turbo_sqlite3's own functions (re-exported by the package): cursed-sqlite-turbo's qc and qvm serve read-only
statements inside sqlite3_step when they can reproduce SQLite's results exactly, and SQLite's interpreter runs the rest.
"""
import sys

from turbo_sqlite3._sqlite3 import _turbo_counts, _turbo_enable


def enable_turbo(on=True):
    """Serve read-only statements through turbo (True) or through SQLite's interpreter only (False), process-wide.
    Statements already being served finish. Returns the previous state. QC_SERVE=0 in the environment starts off."""
    return _turbo_enable(1 if on else 0)


def turbo_enabled():
    return _turbo_enable(-1)


def turbo_counts():
    """(statement runs served by turbo, rows they handed out, runs left to SQLite's interpreter because another thread
    was inside turbo at their start) in this process so far."""
    return _turbo_counts()


def install():
    """Make `import sqlite3` return turbo_sqlite3 (Django, and anything else that imports sqlite3 by name). Call it
    before the first `import sqlite3`: a module that already imported the stdlib's keeps it."""
    pkg = sys.modules["turbo_sqlite3"]
    sys.modules["sqlite3"] = pkg
    sys.modules["sqlite3.dbapi2"] = sys.modules["turbo_sqlite3.dbapi2"]
    import turbo_sqlite3.dump
    sys.modules["sqlite3.dump"] = turbo_sqlite3.dump
