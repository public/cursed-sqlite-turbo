# Third-party credits

- **SQLite** 3.54.1 (amalgamation), public domain. Not vendored: `scripts/fetch-sqlite.sh` downloads it from
  sqlite.org, pinned by version and SHA-256, into `third_party/sqlite/` (ignored by git). `qc/patch.py` adds three
  hooks to a copy at build time (see its header).
- **Batched, prefetching B-tree descent** with interpolation search (`qc_seek_batch`, `qc_lower_bound`): from the
  author's cursed-http engine (explore/sqlite-simd, explore/db), not third-party.
