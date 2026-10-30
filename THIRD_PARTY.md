# Third-party credits

- **SQLite** 3.54.1 (amalgamation), public domain. Not vendored: `scripts/fetch-sqlite.sh` downloads it from
  sqlite.org, pinned by version and SHA-256, into `third_party/sqlite/` (ignored by git). `qc/patch.py` adds three
  hooks to a copy at build time (see its header).
- **Batched, prefetching B-tree descent** with interpolation search (`qc_seek_batch`, `qc_lower_bound`): from the
  author's cursed-http engine (explore/sqlite-simd, explore/db), not third-party.
- **CPython's sqlite3 module** (`Modules/_sqlite`, `Lib/sqlite3`), PSF licence, for `bindings/python`'s
  turbo_sqlite3. Not vendored: `bindings/python/scripts/fetch_cpython_sqlite.py` downloads the building Python's
  minor version's release from python.org, pinned by version and SHA-256, into `bindings/python/build/` (ignored by
  git); `patch_cpython_sqlite.py` renames it at build time and the wheel carries CPython's LICENSE.
