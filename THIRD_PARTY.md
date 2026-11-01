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
- **sqllogictest** (sqlite.org/sqllogictest), public domain, for `tests/build-slt.sh`. Not vendored:
  `scripts/fetch-slt.sh` clones it at one pinned check-in into `third_party/slt/` (ignored by git).
- **SQLite's source tree** (for the TCL test suite and fuzzcheck), public domain. Not vendored:
  `scripts/fetch-sqlite-src.sh` downloads it, pinned by version and SHA-256, into `build/`.
- **The query corpus** (`bench/corpus/`) quotes SQL statements, and the `CREATE` statements they need, from 43
  open-source applications.
  - **Licence:** the quoted SQL is not under this repository's MIT licence; it keeps each application's own licence.
  - **Each project directory** has the application's licence, unchanged, as `LICENSE`, and a `NOTICE.md` saying
    which files are quoted, from which commit, and what was changed.
  - **n8n:** `projects/n8n/` is under n8n's Sustainable Use License: free, non-commercial redistribution only.
  - **The rest:** the corpus's data generators, tools and summaries are this repository's own, under MIT.
    `bench/corpus/README.md` has the details.
