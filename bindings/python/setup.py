"""turbo_sqlite3's build: CPython's own sqlite3 module, for the Python running this, on turbo's patched amalgamation.

Before setuptools runs,
  1. scripts/fetch_cpython_sqlite.py fetches this Python's Modules/_sqlite and Lib/sqlite3 (pinned, SHA-256-checked)
     and scripts/patch_cpython_sqlite.py makes them turbo_sqlite3 (build/turbo_sqlite3-X.Y/{c,turbo_sqlite3});
then build_ext runs the repository's `make all` (fetches SQLite, pinned; writes build/gen/sqlite3.c and qc_dec.h) and
compiles the module with csrc/turbo.c (the amalgamation and qc in one unit) into turbo_sqlite3._sqlite3.

TURBO_ROOT names the repository when this directory isn't bindings/python inside it.
"""
import os, subprocess, sys, sysconfig

from setuptools import Extension, setup
from setuptools.command.build_ext import build_ext

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.environ.get("TURBO_ROOT") or os.path.join(HERE, "..", ".."))
GEN = os.path.join(ROOT, "build", "gen")
MINOR = "%d.%d" % sys.version_info[:2]
OUT = os.path.join(HERE, "build", f"turbo_sqlite3-{MINOR}")
CSRC, PKG = os.path.join(OUT, "c"), os.path.join(OUT, "turbo_sqlite3")
MODULE_SOURCES = ["module.c", "connection.c", "cursor.c", "microprotocols.c", "prepare_protocol.c", "statement.c",
                  "util.c", "row.c", "blob.c", "cache.c"]

sys.path.insert(0, os.path.join(HERE, "scripts"))
import fetch_cpython_sqlite, patch_cpython_sqlite  # noqa: E402

cpy = fetch_cpython_sqlite.fetch(MINOR, os.path.join(HERE, "build", f"cpython-{MINOR}"))
patch_cpython_sqlite.patch_c(cpy, CSRC)
patch_cpython_sqlite.patch_py(cpy, PKG)


class turbo_build_ext(build_ext):
    def run(self):
        if not os.path.exists(os.path.join(ROOT, "qc", "qc.c")):
            sys.exit(f"turbo_sqlite3: no qc/qc.c under {ROOT} (set TURBO_ROOT to the cursed-sqlite-turbo checkout)")
        subprocess.check_call(["make", "-C", ROOT, "all", f"PYTHON={sys.executable}"])
        super().run()


SQLITE_OPTS = [
    ("SQLITE_THREADSAFE", "1"),          # serialized, as CPython's own builds: Python releases the GIL in step
    ("SQLITE_DEFAULT_MEMSTATUS", "0"),
    ("SQLITE_ENABLE_FTS3", "1"), ("SQLITE_ENABLE_FTS3_PARENTHESIS", "1"), ("SQLITE_ENABLE_FTS4", "1"),
    ("SQLITE_ENABLE_FTS5", "1"), ("SQLITE_ENABLE_RTREE", "1"), ("SQLITE_ENABLE_MATH_FUNCTIONS", "1"),
    ("QC_SERVE_DEFAULT", "1"),           # turbo serves read-only statements through sqlite3_step (QC_SERVE=0: off)
]
inc = sysconfig.get_paths()["include"]

ext = Extension(
    "turbo_sqlite3._sqlite3",
    sources=[os.path.join(CSRC, f) for f in MODULE_SOURCES if os.path.exists(os.path.join(CSRC, f))]
            + ["csrc/turbo.c"],
    include_dirs=[GEN, os.path.join(ROOT, "qc"), os.path.join(inc, "internal")],
    # the module is built as CPython builds it (its internal headers: argument clinic's parsers, for one)
    define_macros=[("Py_BUILD_CORE_MODULE", "1")] + SQLITE_OPTS,
    extra_compile_args=["-O2", "-fvisibility=hidden", "-w"],
    libraries=["m", "pthread"] + (["dl"] if sys.platform.startswith("linux") else []),
    depends=[os.path.join(ROOT, "qc", f) for f in ("qc.c", "qcg.c", "qvm.c", "qvm_run.h")],
)

setup(
    packages=["turbo_sqlite3"],
    package_dir={"turbo_sqlite3": os.path.relpath(PKG, HERE)},
    package_data={"turbo_sqlite3": ["LICENSE.cpython"]},
    ext_modules=[ext],
    cmdclass={"build_ext": turbo_build_ext},
)
