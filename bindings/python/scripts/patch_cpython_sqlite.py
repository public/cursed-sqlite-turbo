#!/usr/bin/env python3
"""patch_cpython_sqlite.py SRC CDEST PYDEST: CPython's sqlite3 module (fetch_cpython_sqlite.py's SRC) as turbo_sqlite3.

  CDEST   Modules/_sqlite's C sources, with
          - MODULE_NAME "turbo_sqlite3" (iterdump imports MODULE_NAME ".dump"; types and exceptions are named by it);
          - two more module functions: _turbo_enable(on) (1 on, 0 off, -1 only asks; the previous state) and
            _turbo_counts() (served runs, served rows, starts left to
            the interpreter as another thread was inside qc), from csrc/turbo.c.
  PYDEST  the turbo_sqlite3 package: Lib/sqlite3's files importing turbo_sqlite3 and turbo_sqlite3._sqlite3 instead
          of sqlite3 and _sqlite3, src/_turbo.py, and __init__.py re-exporting _turbo's functions.

Each change is asserted, as qc/patch.py's are. The altered files say so in their first line (the PSF licence asks
for a summary of changes), and CPython's LICENSE goes into the package.
"""
import os, re, shutil, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOTE = "altered by cursed-sqlite-turbo's bindings/python/scripts/patch_cpython_sqlite.py: imports and names for turbo_sqlite3"


def sub(s, old, new, what, count=1):
    assert s.count(old) == count, f"patch_cpython_sqlite: {what}: expected {count} of {old!r}, found {s.count(old)}"
    return s.replace(old, new)


def patch_c(src, dest):
    shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(os.path.join(src, "Modules", "_sqlite"), dest)
    p = os.path.join(dest, "module.h")
    s = open(p).read()
    s = sub(s, '#define MODULE_NAME "sqlite3"', '#define MODULE_NAME "turbo_sqlite3"', "MODULE_NAME")
    open(p, "w").write(f"/* {NOTE} */\n" + s)
    p = os.path.join(dest, "module.c")
    s = open(p).read()
    s = sub(s, "static PyMethodDef module_methods[] = {\n",
            "int turbo_enable(int); void turbo_counts(long long *, long long *, long long *);\n"
            "static PyObject *module_turbo_enable(PyObject *self, PyObject *args) {\n"
            "    int on;\n"
            "    if (!PyArg_ParseTuple(args, \"i\", &on)) return NULL;\n"
            "    return PyBool_FromLong(turbo_enable(on));\n"
            "}\n"
            "static PyObject *module_turbo_counts(PyObject *self, PyObject *noargs) {\n"
            "    long long runs, rows, passed; turbo_counts(&runs, &rows, &passed);\n"
            "    return Py_BuildValue(\"(LLL)\", runs, rows, passed);\n"
            "}\n"
            "static PyMethodDef module_methods[] = {\n"
            "    {\"_turbo_enable\", (PyCFunction)module_turbo_enable, METH_VARARGS, NULL},\n"
            "    {\"_turbo_counts\", (PyCFunction)module_turbo_counts, METH_NOARGS, NULL},\n",
            "module methods")
    open(p, "w").write(f"/* {NOTE}; turbo's module functions */\n" + s)


def patch_py(src, dest):
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    lib = os.path.join(src, "Lib", "sqlite3")
    for f in sorted(os.listdir(lib)):
        if not f.endswith(".py"):
            continue
        s = open(os.path.join(lib, f), encoding="utf-8").read()
        n = 0
        for pat, rep in ((r"^from sqlite3\.", "from turbo_sqlite3."), (r"^import sqlite3$", "import turbo_sqlite3 as sqlite3"),
                         (r"^(\s*)from _sqlite3 import", r"\1from turbo_sqlite3._sqlite3 import")):
            s, k = re.subn(pat, rep, s, flags=re.M)
            n += k
        assert "import _sqlite3" not in s and not re.search(r"^(from|import) sqlite3\b", s, re.M), f"patch_cpython_sqlite: {f}: an import left"
        if f == "__init__.py":
            assert n, "patch_cpython_sqlite: __init__.py: no import rewritten"
            s += "\nfrom turbo_sqlite3._turbo import enable_turbo, turbo_enabled, turbo_counts, install\n"
        if n or f == "__init__.py":
            s = f"# {NOTE}\n" + s
        open(os.path.join(dest, f), "w", encoding="utf-8").write(s)
    shutil.copyfile(os.path.join(HERE, "src", "_turbo.py"), os.path.join(dest, "_turbo.py"))
    shutil.copyfile(os.path.join(src, "LICENSE"), os.path.join(dest, "LICENSE.cpython"))


if __name__ == "__main__":
    patch_c(sys.argv[1], sys.argv[2])
    patch_py(sys.argv[1], sys.argv[3])
