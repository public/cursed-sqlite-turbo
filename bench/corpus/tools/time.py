#!/usr/bin/env python3
"""Indicative stock-SQLite timings, for triage only (which queries are CPU-bound), not benchmarking.

    tools/time.py PROJECT... [--all] [--scale N] [--reps 3]

Builds each project's database like run.py, then runs every query --reps times in one sqlite3 CLI process
(each inside BEGIN ... ROLLBACK) with `.timer on`, and keeps the minimum wall time. Results go to
projects/P/timings.json as {"host", "sqlite_version", "scale", "reps", "ms": {id: min_ms}}.
The numbers come from whatever machine runs this; turbo's real measurements live with the bench sessions.
"""
import argparse, json, platform, sys, tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run  # noqa: E402

MARK = "@@T"


def time_project(name, scale, reps):
    pdir = run.PROJ / name
    queries = run.parse_queries(pdir / "queries.sql")
    meta = json.loads((pdir / "meta.json").read_text())
    for q in queries:
        q["pragmas"] = meta.get("pragmas", [])
    with tempfile.TemporaryDirectory(prefix="corpus-time-") as tmp:
        db = Path(tmp) / f"{name}.db"
        run.build_db(pdir, db, scale)
        out = Path(tmp) / "out.txt"
        ms = {}
        for q in queries:
            script = run.conn_sql(q) + run.param_sql(q["params"]) + f".output {out}\n.timer on\n"
            for _ in range(reps):
                script += f"BEGIN;\n.print {MARK}\n{q['sql']}\nROLLBACK;\n"
            rc, _, err = run.cli(db, script, timeout=1800)
            if rc:
                print(f"  FAIL {q['id']}: {err.strip()[:200]}")
                continue
            times, armed = [], False
            for line in out.read_text(errors="replace").splitlines():
                if line == MARK:
                    armed = True
                elif armed and line.startswith("Run Time: real "):
                    times.append(float(line.split()[3]) * 1000)
                    armed = False
            ms[q["id"]] = round(min(times), 3) if times else None
            print(f"  {ms[q['id']]:>10.2f} ms  {q['id']}")
    res = {"host": f"{platform.machine()} {platform.system()}",
           "sqlite_version": run.cli(":memory:", "select sqlite_version();")[1].strip(),
           "scale": scale, "reps": reps, "ms": ms}
    (pdir / "timings.json").write_text(json.dumps(res, indent=1) + "\n")
    return ms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("projects", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--scale", default="1")
    ap.add_argument("--reps", type=int, default=3)
    a = ap.parse_args()
    names = sorted(p.name for p in run.PROJ.iterdir() if (p / "queries.sql").exists()) if a.all else a.projects
    for n in names:
        print(f"== {n}")
        time_project(n, a.scale, a.reps)


if __name__ == "__main__":
    main()
