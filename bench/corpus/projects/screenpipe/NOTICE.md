# screenpipe: licensing of this directory

**Third-party:** `queries.sql` and `schema.sql` quote SQL from
[screenpipe/screenpipe](https://github.com/screenpipe/screenpipe) at commit `892199f742e46d0c5d9e8c06687b35ca7c2b6547`
(2026-06-10), as do this project's 31 entries in `../../manifest.jsonl` (their `sql` field). Copyright belongs to that
project's authors. That SQL is licensed under the project's own licence, **MIT**, not under cursed-sqlite-turbo's MIT
licence. LICENSE is the repository's LICENSE.md at that commit, copied unchanged.

**Why this commit:** it is the last one before screenpipe moved its code to the Screenpipe Commercial License
(`81e412f`, 2026-06-10), which grants no right to redistribute. That licence states that versions released under MIT
remain available under MIT. The files quoted here (`crates/screenpipe-db`, `crates/screenpipe-engine`) are outside the
`ee/` directory, which had its own proprietary licence at this commit.

**Changes from the original:**
- The statements were extracted from the application's code, and the `CREATE` statements from its migrations, on
  2026-11-01. An earlier version of this project was taken from a later commit (`2431cbf`) and was replaced.
- Parameters are written as SQLite parameters, and values the application interpolates are filled in. The statements
  are reformatted.

Each statement's source file and line range is in `queries.sql` and the manifest.

**This repository's own work:** `data.sql` (synthetic data), `meta.json`, `expected.json` and `timings.json` are
cursed-sqlite-turbo's own. They're under its MIT licence (`../../../../LICENSE`).
