#!/usr/bin/env python3
"""Load a project's schema and data into a fresh database and run its queries.

    tools/run.py PROJECT...          run, print one line per query (rows / changes)
    tools/run.py --all               every project under projects/
    tools/run.py --record ...        also write projects/P/expected.json
    tools/run.py --manifest          rebuild manifest.jsonl + STATS.md from recorded results
    tools/run.py --scale N ...       data scale multiplier (default 1; data.sql reads _cfg.scale)
    tools/run.py --keep DIR ...      keep the built databases in DIR

Everything goes through the sqlite3 CLI (override with $SQLITE3). Each query runs in its own CLI process
inside BEGIN ... ROLLBACK, so writes never leak into the next query. Parameters are bound through
temp.sqlite_parameters, so ?N, :name, @name and $name all work.
"""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, tempfile, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJ = ROOT / "projects"
SQLITE3 = os.environ.get("SQLITE3", "sqlite3")
COL, ROW = "\x1f", "\x1e"


# --- queries.sql parsing --------------------------------------------------------------------------------

def parse_queries(path):
    """Blocks start with `-- @id NAME`; `-- @key value` lines are metadata, other lines are the SQL."""
    out, cur = [], None
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        m = re.match(r"\s*--\s*@(\w+)\s?(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            if key == "id":
                cur = {"id": val, "line": lineno, "sql": [], "params": [], "tags": [], "meta": {}}
                out.append(cur)
            elif cur is None:
                continue  # file-level header metadata
            elif key == "param":
                name, _, lit = val.partition(" ")
                cur["params"].append((name, lit.strip()))
            elif key == "tags":
                cur["tags"] += [t.strip() for t in val.split(",") if t.strip()]
            else:
                cur["meta"][key] = (cur["meta"].get(key, "") + " " + val).strip()
            continue
        if cur is not None:
            if re.match(r"\s*--", line) and not cur["sql"]:
                continue
            cur["sql"].append(line)
    for q in out:
        q["sql"] = "\n".join(q["sql"]).strip()
        if not q["sql"].endswith(";"):
            q["sql"] += ";"
    return out


# --- automatic tags ---------------------------------------------------------------------------------------

def strip_literals(sql):
    sql = re.sub(r"'(?:[^']|'')*'", "''", sql)
    sql = re.sub(r"--[^\n]*", " ", sql)
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    return sql.upper()


def auto_tags(sql, eqp):
    s = strip_literals(sql)
    t = set()
    kind = first_kw(s)
    t.add({"SELECT": "read", "WITH": "read", "VALUES": "read"}.get(kind, kind.lower()))
    if re.search(r"\bWITH\s+RECURSIVE\b", s): t.add("recursive-cte")
    if re.search(r"(^|\(|\s)WITH\s+(RECURSIVE\s+)?[\w\"`\[]", s.strip()): t.add("cte")
    if re.search(r"\bOVER\s*(\(|\w)", s): t.add("window")
    if re.search(r"\bJOIN\b", s): t.add("join")
    if len(re.findall(r"\(\s*SELECT\b", s)): t.add("subquery")
    if re.search(r"\bGROUP\s+BY\b", s): t.add("groupby")
    if re.search(r"\bHAVING\b", s): t.add("having")
    if re.search(r"\bDISTINCT\b", s): t.add("distinct")
    if re.search(r"\b(UNION|INTERSECT|EXCEPT)\b", s): t.add("compound")
    if re.search(r"\bORDER\s+BY\b", s) and re.search(r"\bLIMIT\b", s): t.add("topn")
    elif re.search(r"\bORDER\s+BY\b", s): t.add("orderby")
    if re.search(r"\bLIKE\b", s): t.add("like")
    if re.search(r"\bGLOB\b", s): t.add("glob")
    if re.search(r"\bREGEXP\b", s): t.add("regexp")
    if re.search(r"\bJSONB?(_\w+)?\s*\(|->>?", s): t.add("json")
    if re.search(r"\bMATCH\b|\bBM25\s*\(|\bSNIPPET\s*\(|\bHIGHLIGHT\s*\(", s): t.add("fts")
    if re.search(r"\bCASE\b", s): t.add("case")
    if re.search(r"\b(PRINTF|FORMAT|SUBSTR|SUBSTRING|REPLACE|INSTR|GROUP_CONCAT|STRING_AGG|LOWER|UPPER|LTRIM|RTRIM|TRIM|HEX|CHAR|UNICODE)\s*\(|\|\|", s): t.add("string")
    if re.search(r"\b(DATE|DATETIME|STRFTIME|JULIANDAY|UNIXEPOCH|TIME|TIMEDIFF)\s*\(|CURRENT_TIMESTAMP", s): t.add("date")
    if re.search(r"\b(COUNT|SUM|AVG|MIN|MAX|TOTAL|GROUP_CONCAT|STRING_AGG|JSON_GROUP_ARRAY|JSON_GROUP_OBJECT)\s*\(", s): t.add("aggregate")
    if re.search(r"\bON\s+CONFLICT\b.*\bDO\b|\bOR\s+REPLACE\b|^\s*REPLACE\b", s, re.S): t.add("upsert")
    if re.search(r"\bOR\s+IGNORE\b", s): t.add("insert-ignore")
    if re.search(r"\bRETURNING\b", s): t.add("returning")
    if re.search(r"\bEXISTS\s*\(", s): t.add("exists")
    if re.search(r"\bIN\s*\(\s*(?!SELECT\b)", s): t.add("in-list")
    if re.search(r"\bIN\s*\(\s*SELECT\b", s): t.add("in-subquery")
    if re.search(r"\bCOLLATE\b", s): t.add("collate")
    if CLOCK.search(sql):
        t.add("wallclock")
    if re.search(r"\bOFFSET\b|\bLIMIT\s+[\w?:@$]+\s*,", s): t.add("offset")
    tables = set()
    for line in eqp:
        if "CORRELATED" in line: t.add("correlated")
        if "TEMP B-TREE" in line: t.add("temp-btree")
        if "AUTOMATIC" in line: t.add("auto-index")
        if "MULTI-INDEX OR" in line: t.add("multi-index-or")
        if "VIRTUAL TABLE" in line: t.add("vtab")
        m = re.search(r"\b(?:SCAN|SEARCH)\s+(\w+)", line)
        if m and m.group(1) not in ("CONSTANT",): tables.add(line.strip())
        if re.search(r"\bSCAN\s+\w+(?!.*\bUSING\b)", line) and "SUBQUERY" not in line and "CONSTANT" not in line:
            t.add("full-scan")
    accesses = sum(1 for l in eqp if re.search(r"\b(SCAN|SEARCH)\s", l) and "CONSTANT ROW" not in l)
    if accesses >= 3: t.add("join3")
    return t, accesses


CLOCK = re.compile(r"'(now|localtime)'|\bCURRENT_(TIMESTAMP|DATE|TIME)\b|\brandom\s*\("
                   r"|\b(date|time|datetime|julianday|unixepoch)\s*\(\s*\)|\bstrftime\s*\(\s*'[^']*'\s*\)", re.I)


def clock_views(schema):
    """Views whose result depends on the clock, directly or through another such view."""
    views = {m.group(1).lower(): m.group(2) for m in re.finditer(
        r"CREATE\s+(?:TEMP\w*\s+)?VIEW\s+(?:IF\s+NOT\s+EXISTS\s+)?[\"`\[]?(\w+)[\"`\]]?\s+AS\b(.*?)(?=\bCREATE\s|\Z)",
        schema, re.I | re.S)}
    clock = {v for v, body in views.items() if CLOCK.search(body)}
    while True:
        more = {v for v, body in views.items() if v not in clock
                and any(re.search(rf"\b{c}\b", body, re.I) for c in clock)}
        if not more:
            return clock
        clock |= more


def clock_dependent(q, views):
    """A clock-reading parameter value, or a read from a clock-dependent view (CLOCK in the text is auto_tags' job)."""
    return (any(CLOCK.search(lit) for _, lit in q["params"])
            or any(re.search(rf"\b{v}\b", q["sql"], re.I) for v in views))


def first_kw(s):
    m = re.match(r"\s*(\w+)", s)
    kw = m.group(1) if m else "?"
    if kw == "WITH":
        # WITH ... INSERT/UPDATE/DELETE: find the first top-level DML keyword after the CTEs
        depth, i = 0, 0
        for tok in re.finditer(r"\(|\)|\b(SELECT|INSERT|UPDATE|DELETE|REPLACE)\b", s):
            if tok.group(0) == "(": depth += 1
            elif tok.group(0) == ")": depth -= 1
            elif depth == 0: return tok.group(1)
        return "SELECT"
    return kw


# --- execution ----------------------------------------------------------------------------------------

def cli(db, script, timeout=1800):
    # TZ=UTC so 'localtime' date maths (Tautulli, KOReader) gives the same rows on every machine
    p = subprocess.run([SQLITE3, "-bail", "-batch", str(db)], input=script, capture_output=True,
                       text=True, errors="replace", timeout=timeout, env={**os.environ, "TZ": "UTC"})
    return p.returncode, p.stdout, p.stderr


def conn_sql(q):
    """Connection settings the app applies (meta.json "pragmas"), replayed before every query."""
    return "".join(p.rstrip(";") + ";\n" for p in q.get("pragmas", []))


def param_sql(params):
    if not params:
        return ""
    vals = ",".join(f"('{n}',{lit})" for n, lit in params)
    return (".parameter init\n"
            f"INSERT INTO temp.sqlite_parameters(key,value) VALUES {vals};\n")


def build_db(pdir, db, scale):
    if db.exists():
        db.unlink()
    # meta.json "analyze": false mirrors apps that never run ANALYZE, so the planner sees what real installs see
    analyze = json.loads((pdir / "meta.json").read_text()).get("analyze", True)
    script = (f"PRAGMA journal_mode=OFF;\nCREATE TEMP TABLE _cfg AS SELECT {scale} AS scale;\n"
              + (pdir / "schema.sql").read_text() + "\n"
              + (pdir / "data.sql").read_text() + ("\nANALYZE;\n" if analyze else "\n"))
    t = time.time()
    rc, out, err = cli(db, script, timeout=1800)
    if rc:
        raise SystemExit(f"{pdir.name}: schema/data failed: {err.strip()[:2000]}")
    return time.time() - t


def run_query(db, q):
    pre = conn_sql(q) + param_sql(q["params"])
    sql = q["sql"]
    eqp_rc, eqp_out, _ = cli(db, pre + ".mode list\nEXPLAIN QUERY PLAN " + sql + "\n")
    eqp = [l for l in eqp_out.splitlines() if l.strip()]
    _, ops_out, _ = cli(db, pre + ".mode list\nEXPLAIN " + sql + "\n")
    ops = sum(1 for l in ops_out.splitlines() if l.strip())
    script = (pre + ".headers off\n.mode list\n.nullvalue NULL\n"
              + f".separator \"\\037\" \"\\036\"\nBEGIN;\n{sql}\n"
              + ".print\n.print @@CHANGES\nSELECT changes();\nROLLBACK;\n")
    t = time.time()
    rc, out, err = cli(db, script)
    ms = (time.time() - t) * 1000
    if rc:
        return {"ok": False, "error": err.strip()[:500], "eqp": eqp, "ops": ops}
    body, _, tail = out.rpartition("\n@@CHANGES\n")
    # every row ends with the row separator, so the last piece is what .print added; a row can be empty ('')
    rows = [r.lstrip("\n") for r in body.split(ROW)[:-1]]
    changes = int(tail.strip(ROW + "\n") or 0)
    return {"ok": True, "rows": len(rows), "changes": changes, "ms": round(ms, 1), "eqp": eqp, "ops": ops,
            "hash": hashlib.md5(ROW.join(rows).encode()).hexdigest()[:12],
            "hash_sorted": hashlib.md5(ROW.join(sorted(rows)).encode()).hexdigest()[:12]}


def run_project(name, scale, keepdir, record):
    pdir = PROJ / name
    meta = json.loads((pdir / "meta.json").read_text())
    queries = parse_queries(pdir / "queries.sql")
    for q in queries:
        q["pragmas"] = meta.get("pragmas", [])
    clock_views_ = clock_views((pdir / "schema.sql").read_text())
    # a data recipe anchored to the clock (Grocy: dates relative to today) makes every result date-dependent
    data_clock = bool(CLOCK.search("\n".join(l.split("--")[0] for l in (pdir / "data.sql").read_text().splitlines())))
    ids = [q["id"] for q in queries]
    dups = {i for i in ids if ids.count(i) > 1}
    if dups:
        raise SystemExit(f"{name}: duplicate ids {sorted(dups)}")
    tmp = Path(keepdir) if keepdir else Path(tempfile.mkdtemp(prefix="corpus-"))
    tmp.mkdir(parents=True, exist_ok=True)
    db = tmp / f"{name}.db"
    secs = build_db(pdir, db, scale)
    size = db.stat().st_size
    print(f"== {name}: {len(queries)} queries, db {size/1e6:.1f} MB built in {secs:.1f}s (scale {scale})")
    results, fails, empty = {}, 0, 0
    for q in queries:
        r = run_query(db, q)
        tags, acc = auto_tags(q["sql"], r.get("eqp", []))
        if data_clock or clock_dependent(q, clock_views_):
            tags.add("wallclock")
        r["tags"] = sorted(tags | set(q["tags"]) | ({"modified"} if q["meta"].get("modified") else set()))
        r["accesses"] = acc
        results[q["id"]] = r
        if not r["ok"]:
            fails += 1
            print(f"  FAIL {q['id']}: {r['error']}")
        else:
            is_read = "read" in tags
            if is_read and r["rows"] == 0 and "expect-empty" not in q["tags"]:
                empty += 1
            what = f"{r['rows']} rows" if is_read or r["rows"] else f"{r['changes']} changes"
            print(f"  ok   {q['id']}: {what}  ({r['ops']} ops, {r['ms']:.0f} ms)")
    print(f"  -- {name}: {len(queries)-fails}/{len(queries)} ok, {fails} failed, {empty} reads returned 0 rows")
    if record:
        exp = {"scale": scale, "sqlite_version": cli(":memory:", "select sqlite_version();")[1].strip(),
               "db_bytes": size, "queries": {k: {kk: v[kk] for kk in v if kk not in ("eqp", "ms")} | {"eqp": v["eqp"]}
                                             for k, v in results.items()}}
        (pdir / "expected.json").write_text(json.dumps(exp, indent=1) + "\n")
    if not keepdir:
        shutil.rmtree(tmp, ignore_errors=True)
    return fails, empty


# --- manifest ------------------------------------------------------------------------------------------

def build_manifest():
    rows, stats = [], {}
    for pdir in sorted(p for p in PROJ.iterdir() if (p / "queries.sql").exists()):
        meta = json.loads((pdir / "meta.json").read_text())
        expf = pdir / "expected.json"
        exp = json.loads(expf.read_text())["queries"] if expf.exists() else {}
        tf = pdir / "timings.json"
        tim = json.loads(tf.read_text())["ms"] if tf.exists() else {}
        for q in parse_queries(pdir / "queries.sql"):
            e = exp.get(q["id"], {})
            tags = e.get("tags") or sorted(auto_tags(q["sql"], [])[0] | set(q["tags"]))
            if q["meta"].get("modified"):
                tags = sorted(set(tags) | {"modified"})
            if (tim.get(q["id"]) or 0) >= 1000:
                tags = sorted(set(tags) | {"heavy"})
            rows.append({
                "project": pdir.name, "id": q["id"], "repo": meta["repo"], "sha": meta["sha"],
                "license": meta["license"], "src": q["meta"].get("src", ""),
                "src_url": src_url(meta, q["meta"].get("src", "")),
                "param_style": q["meta"].get("style", meta.get("param_style", "")),
                "params": {n: lit for n, lit in q["params"]}, "tags": tags,
                "note": q["meta"].get("note", ""), "modified": q["meta"].get("modified", ""),
                "sql": q["sql"], "vdbe_ops": e.get("ops"), "table_accesses": e.get("accesses"),
                "rows": e.get("rows"), "changes": e.get("changes"), "ok": e.get("ok"),
                "hash": e.get("hash"), "hash_sorted": e.get("hash_sorted"),
                "stock_ms_indicative": tim.get(q["id"]),
            })
    with open(ROOT / "manifest.jsonl", "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"manifest.jsonl: {len(rows)} queries from {len({r['project'] for r in rows})} projects")
    return rows


def src_url(meta, src):
    # first "path[:line[-line]]" token; anything after it (extra ranges, notes) stays in the src text
    m = re.match(r"\s*([^\s:;,()]+)(?::(\d+)(?:-(\d+))?)?", src or "")
    if not m or not src:
        return ""
    base = meta["repo"].rstrip("/")
    url = f"{base}/blob/{meta['sha']}/{m.group(1)}"
    if m.group(2):
        url += f"#L{m.group(2)}" + (f"-L{m.group(3)}" if m.group(3) else "")
    return url


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("projects", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--record", action="store_true")
    ap.add_argument("--manifest", action="store_true")
    ap.add_argument("--scale", default="1")
    ap.add_argument("--keep")
    a = ap.parse_args()
    names = sorted(p.name for p in PROJ.iterdir() if (p / "queries.sql").exists()) if a.all else a.projects
    tf = te = 0
    for n in names:
        f, e = run_project(n, a.scale, a.keep, a.record)
        tf += f; te += e
    if names:
        print(f"TOTAL: {tf} failed, {te} empty reads")
    if a.manifest:
        build_manifest()
    sys.exit(1 if tf else 0)


if __name__ == "__main__":
    main()
