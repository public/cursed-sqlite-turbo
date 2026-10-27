"""cut.py <rows> <out.csv>: the first <rows> CSV records of stdin (hits.csv, decompressed), byte for byte. A newline
inside double quotes doesn't end a record (RFC 4180, as the sqlite3 shell's .import --csv reads it). Exit 1 if stdin
ends first."""
import sys
want = int(sys.argv[1]); out = open(sys.argv[2], 'wb'); src = sys.stdin.buffer
n = 0; inq = False
while n < want:
    b = src.read(1 << 20)
    if not b: break
    i = 0; L = len(b)
    while i < L and n < want:
        if inq:
            j = b.find(b'"', i)
            if j < 0: i = L; break
            inq = False; i = j + 1   # ("" inside quotes: closes and reopens, same state)
        else:
            q = b.find(b'"', i); nl = b.find(b'\n', i)
            if nl >= 0 and (q < 0 or nl < q): n += 1; i = nl + 1
            elif q >= 0: inq = True; i = q + 1
            else: i = L
    out.write(b[:i])
out.close()
sys.exit(0 if n == want else 1)
