#!/usr/bin/env python3
"""fetch_cpython_sqlite.py: CPython's own sqlite3 module (Modules/_sqlite and Lib/sqlite3, PSF licence) for one
Python version, from python.org's source release, pinned and SHA-256-checked.

  python3 scripts/fetch_cpython_sqlite.py [X.Y] [DEST]    (default: the running Python's; build/cpython-X.Y)

Each minor version builds from its latest patch release below: the module only uses interfaces that are stable
within a minor version (it is built as a shared extension in CPython's own tree). DEST gets Modules/_sqlite/ and
Lib/sqlite3/ (without its tests) and a VERSION file; nothing is fetched when VERSION matches.
"""
import hashlib, io, lzma, os, sys, tarfile, urllib.request

PINS = {
    "3.10": ("3.10.22", "c61fe9b1a1a7ec2a0b0388e664187c378a5325a89e3606d220abf5bdfccb2543"),
    "3.11": ("3.11.18", "9120e0a653868f6e3698d36cdd99e5a58903ec9469e448f21d98f7b16d8fa290"),
    "3.12": ("3.12.16", "b5796915dc45ff745cfb4e990a7e7c93d6f546328a102ce31448d69ebc37575c"),
    "3.13": ("3.13.18", "abb0102e6d4ae027509bcb82327d9dd85515b44a3ba8ad538cfc5e9847029f68"),
    "3.14": ("3.14.10", "de414a57119abef52784d8993e341d53aed635fc2b05c2607d9f98a2c5b72032"),
    "3.15": ("3.15.2", "8b5536d280142ecf6cdfe15d12a21ba1c65e300bbf7b28a8d0cdb849575797de"),
}


def fetch(minor, dest):
    if minor not in PINS:
        sys.exit(f"fetch_cpython_sqlite: no pinned CPython release for Python {minor} (have {', '.join(PINS)})")
    v, sha = PINS[minor]
    stamp = os.path.join(dest, "VERSION")
    if os.path.exists(stamp) and open(stamp).read().strip() == f"{v} {sha}":
        return dest
    url = f"https://www.python.org/ftp/python/{v}/Python-{v}.tar.xz"
    data = urllib.request.urlopen(url, timeout=120).read()
    got = hashlib.sha256(data).hexdigest()
    if got != sha:
        sys.exit(f"fetch_cpython_sqlite: checksum mismatch for {url}: {got}")
    with tarfile.open(fileobj=io.BytesIO(lzma.decompress(data))) as t:
        for m in t.getmembers():
            rel = m.name.split("/", 1)[1] if "/" in m.name else ""
            keep = rel.startswith("Modules/_sqlite/") or (rel.startswith("Lib/sqlite3/") and rel.count("/") == 2)
            if rel == "LICENSE" or (keep and m.isfile()):
                os.makedirs(os.path.join(dest, os.path.dirname(rel)), exist_ok=True)
                with open(os.path.join(dest, rel), "wb") as f:
                    f.write(t.extractfile(m).read())
    with open(stamp, "w") as f:
        f.write(f"{v} {sha}\n")
    print(f"fetch_cpython_sqlite: CPython {v}'s sqlite3 module in {dest}")
    return dest


if __name__ == "__main__":
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    minor = sys.argv[1] if len(sys.argv) > 1 else "%d.%d" % sys.version_info[:2]
    fetch(minor, sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "build", f"cpython-{minor}"))
