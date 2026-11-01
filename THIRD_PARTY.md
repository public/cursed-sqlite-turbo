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
- **The query corpus** (`bench/corpus/`) quotes short SQL statements, and the `CREATE` statements those statements
  need, from 44 open-source applications.
  - **Attribution:** every statement carries its repository, the pinned commit and its file and line range
    (`manifest.jsonl`, each project's `queries.sql` and `meta.json`).
  - **Licences:** the applications' licences are recorded per project. They include MIT, Apache-2.0, BSD-3-Clause,
    MPL-2.0, GPL-2.0/3.0, AGPL-3.0, EUPL-1.2, the Elastic License 2.0, n8n's Sustainable Use License and
    screenpipe's source-available licence.
  - **What's quoted and what's fetched:** for GPL, AGPL and EUPL projects, `schema.sql` holds only the `CREATE`
    statements the queries use. The original files are fetched by `bench/corpus/tools/fetch.sh` from pinned paths
    rather than committed.
  - **Not third-party:** the data generators (`data.sql`) are written for this repository. They produce synthetic
    data, not the applications' data.
