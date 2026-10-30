"""The README's one-liners: SQLAlchemy's module= and creator=, and Django through sys.modules["sqlite3"]. Skipped when
the framework isn't installed."""
import os, subprocess, sys, textwrap

import pytest

import turbo_sqlite3


def test_sqlalchemy(tmp_path):
    sa = pytest.importorskip("sqlalchemy")
    db = str(tmp_path / "sa.db")
    for engine in (sa.create_engine(f"sqlite:///{db}", module=turbo_sqlite3),
                   # (creator= alone leaves the dialect on the stdlib's module: its exception classes, not turbo's)
                   sa.create_engine("sqlite://", module=turbo_sqlite3,
                                    creator=lambda: turbo_sqlite3.connect(db, check_same_thread=False))):
        with engine.begin() as c:
            c.execute(sa.text("CREATE TABLE IF NOT EXISTS t(a INTEGER PRIMARY KEY, g INT)"))
            c.execute(sa.text("DELETE FROM t"))
            c.execute(sa.text("INSERT INTO t VALUES (:a, :g)"), [{"a": i, "g": i % 4} for i in range(400)])
        before = turbo_sqlite3.turbo_counts()[0]
        with engine.connect() as c:
            for _ in range(5):
                rows = c.execute(sa.text("SELECT g, count(*) FROM t GROUP BY g ORDER BY g")).all()
        assert [tuple(r) for r in rows] == [(g, 100) for g in range(4)]
        assert engine.dialect.dbapi is turbo_sqlite3
        assert turbo_sqlite3.turbo_counts()[0] > before
        with pytest.raises(sa.exc.OperationalError), engine.connect() as c:   # (turbo_sqlite3's errors, translated)
            c.execute(sa.text("SELECT * FROM missing"))
        engine.dispose()


def test_django(tmp_path):
    pytest.importorskip("django")
    code = textwrap.dedent(f"""
        import sys, turbo_sqlite3
        sys.modules["sqlite3"] = turbo_sqlite3          # the README's line, before Django imports sqlite3
        import django
        from django.conf import settings
        settings.configure(DATABASES={{"default": {{"ENGINE": "django.db.backends.sqlite3", "NAME": {str(tmp_path / 'dj.db')!r}}}}},
                           INSTALLED_APPS=["django.contrib.contenttypes", "django.contrib.auth"])
        django.setup()
        from django.core.management import call_command
        call_command("migrate", verbosity=0)
        from django.contrib.auth.models import User
        from django.db import connection
        for i in range(50):
            User.objects.create(username=f"u{{i}}")
        before = turbo_sqlite3.turbo_counts()[0]
        for _ in range(5):
            n = User.objects.filter(username__startswith="u1").count()
        print(type(connection.connection).__module__, n, turbo_sqlite3.turbo_counts()[0] > before)
    """)
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, out.stderr[-3000:]
    assert out.stdout.split() == ["turbo_sqlite3", "11", "True"]
