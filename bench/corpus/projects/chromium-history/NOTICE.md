# Chromium History: licensing of this directory

**Third-party:** `queries.sql` and `schema.sql` quote SQL from
[chromium/chromium](https://github.com/chromium/chromium) at commit `f7be3cef8a9d088c63aced58e025afdceaf2aede`, as do
this project's 35 entries in `../../manifest.jsonl` (their `sql` field). Copyright belongs to that project's authors.
That SQL is licensed under the project's own licence, **BSD-3-Clause**, not under cursed-sqlite-turbo's MIT licence.
LICENSE is the repository's LICENSE, copied unchanged.

**Changes from the original:**
- The statements were extracted from the application's code, and the `CREATE` statements from its migrations, in
  October 2026.
- Parameters are written as SQLite parameters, and values the application interpolates are filled in. The statements
  are reformatted.
- 0 statements are changed further, as `queries.sql` notes beside each one (`@modified`).

Each statement's source file and line range is in `queries.sql` and the manifest.

**This repository's own work:** `data.sql` (synthetic data), `meta.json`, `expected.json` and `timings.json` are
cursed-sqlite-turbo's own. They're under its MIT licence (`../../../../LICENSE`).
