#!/usr/bin/env python3
"""reduce.py <sql-file> <out-file> <test command...>: delta-debugging (ddmin) over the statements of a replay file (one
a line), keeping the last statement, until no single statement or chunk can be removed and the test still "fails".
The test command gets the candidate file as its last argument and fails with exit status 1 (anything else passes),
e.g. tests/sqlancer/crashes.sh, which exits 1 when turbo crashes on the file and stock doesn't."""
import sys, subprocess, os, tempfile
src, out, cmd = sys.argv[1], sys.argv[2], sys.argv[3:]
lines = [l for l in open(src, encoding='utf-8', errors='surrogateescape') if l.strip() and not l.startswith('--')]
last = lines[-1]; body = lines[:-1]
def fails(b):
    fd, p = tempfile.mkstemp(suffix='.sql'); os.close(fd)
    open(p, 'w', encoding='utf-8', errors='surrogateescape').writelines(b + [last])
    r = subprocess.run(cmd + [p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    os.unlink(p); return r == 1
assert fails(body), 'the full file does not fail the test'
n = 2
while len(body) >= 1:
    chunk = max(1, len(body) // n); removed = False
    for i in range(0, len(body), chunk):
        cand = body[:i] + body[i + chunk:]
        if fails(cand): body = cand; n = max(n - 1, 2); removed = True; break
    if not removed:
        if chunk == 1: break
        n = min(len(body), n * 2)
open(out, 'w', encoding='utf-8', errors='surrogateescape').writelines(body + [last])
print(f'reduce: {len(lines)} -> {len(body) + 1} statements in {out}')
