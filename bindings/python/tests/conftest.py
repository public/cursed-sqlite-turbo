"""Shared fixtures: the repository's test database (scripts/gen-db.py, small) and its query corpus (tests/corpus.c)."""
import os, random, re, subprocess, sys

import pytest

ROOT = os.path.abspath(os.environ.get("TURBO_ROOT") or os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CORPUS_C = os.path.join(ROOT, "tests", "corpus.c")
GEN_DB = os.path.join(ROOT, "scripts", "gen-db.py")


def corpus():
    """tests/corpus.c's statements: [(name, sql, params)] (params: one letter per ?N, as its bind_params)."""
    if not os.path.exists(CORPUS_C):
        pytest.skip(f"no {CORPUS_C} (TURBO_ROOT names the repository)")
    src = open(CORPUS_C).read()
    block = src[src.index("QS[] = {"):src.index("};", src.index("QS[] = {"))]
    out = []
    for entry in re.findall(r"\{((?:\s*\"(?:[^\"\\]|\\.)*\"\s*,?)+)\}", block):
        lits = [bytes(s, "utf-8").decode("unicode_escape") for s in re.findall(r"\"((?:[^\"\\]|\\.)*)\"", entry)]
        out.append((lits[0], "".join(lits[1:-1]), lits[-1]))
    assert len(out) > 40, "corpus.c's QS[] not parsed"
    return out


class Params:
    """bind_params' values, from a seeded generator, for the database's sizes."""
    WORDS = ["%alpha%", "%sqlite%", "%feed%", "b%", "%x%"]

    def __init__(self, con, seed):
        self.rng = random.Random(seed)
        self.nu = con.execute("SELECT max(id) FROM users").fetchone()[0]
        self.np = con.execute("SELECT max(id) FROM posts").fetchone()[0]
        self.names = [r[0] for r in con.execute("SELECT username FROM users")]

    def __call__(self, kinds):
        r, out = self.rng, []
        for k in kinds:
            out.append({"p": lambda: r.randint(1, self.np),
                        "P": lambda: r.randint(1, self.np) if r.random() < 7 / 8 else self.np + r.randint(1, 10),
                        "u": lambda: r.randint(1, self.nu),
                        "r": lambda: r.randint(1, self.np - 25),
                        "k": lambda: r.randint(1, 20),
                        "n": lambda: r.choice(self.names) if r.random() < 7 / 8 else "user%05d_" % r.randint(1, self.nu),
                        "t": lambda: "2025-%02d-%02dT00:00:00.000Z" % (r.randint(1, 12), r.randint(1, 28)),
                        "w": lambda: r.choice(self.WORDS)}[k]())
        return out


@pytest.fixture(scope="session")
def corpus_db(tmp_path_factory):
    """A 2,000-user / 8,000-post / 32,000-like database from scripts/gen-db.py (stdlib sqlite3 writes it)."""
    if not os.path.exists(GEN_DB):
        pytest.skip(f"no {GEN_DB} (TURBO_ROOT names the repository)")
    path = str(tmp_path_factory.mktemp("db") / "corpus.db")
    subprocess.check_call([sys.executable, GEN_DB, path, "2000", "8000", "32000"], stdout=subprocess.DEVNULL)
    return path
