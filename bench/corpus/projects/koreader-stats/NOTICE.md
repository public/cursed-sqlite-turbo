# KOReader (reading statistics, vocabulary builder, cover browser cache): licensing of this directory

**Third-party:** `queries.sql` and `schema.sql` quote SQL from
[koreader/koreader](https://github.com/koreader/koreader) at commit `801277394b7fdb77da5580459a9827e9d95e95a4`, as do
this project's 30 entries in `../../manifest.jsonl` (their `sql` field). Copyright belongs to that project's authors.
That SQL is licensed under the project's own licence, **AGPL-3.0**, not under cursed-sqlite-turbo's MIT licence.
LICENSE is the repository's COPYING, copied unchanged.

**Changes from the original:**
- The statements were extracted from the application's code, and the `CREATE` statements from its migrations, in
  October 2026.
- Parameters are written as SQLite parameters, and values the application interpolates are filled in. The statements
  are reformatted.
- 6 statements are changed further, as `queries.sql` notes beside each one (`@modified`).

Each statement's source file and line range is in `queries.sql` and the manifest.

**This repository's own work:** `data.sql` (synthetic data), `meta.json`, `expected.json` and `timings.json` are
cursed-sqlite-turbo's own. They're under its MIT licence (`../../../../LICENSE`).
