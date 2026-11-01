# Prefect (server: dashboard, runs, scheduler, workers, events): licensing of this directory

**Third-party:** `queries.sql` and `schema.sql` quote SQL from
[PrefectHQ/prefect](https://github.com/PrefectHQ/prefect) at commit `f20489df2e281525d7bcf3bc9de65e086853b6b1`, as do
this project's 30 entries in `../../manifest.jsonl` (their `sql` field). Copyright belongs to that project's authors.
That SQL is licensed under the project's own licence, **Apache-2.0**, not under cursed-sqlite-turbo's MIT licence.
LICENSE is the repository's LICENSE, copied unchanged.

**Changes from the original:**
- The statements were extracted from the application's code, and the `CREATE` statements from its migrations, in
  October 2026.
- Parameters are written as SQLite parameters, and values the application interpolates are filled in. The statements
  are reformatted.
- 7 statements are changed further, as `queries.sql` notes beside each one (`@modified`).

Each statement's source file and line range is in `queries.sql` and the manifest.

**This repository's own work:** `data.sql` (synthetic data), `meta.json`, `expected.json` and `timings.json` are
cursed-sqlite-turbo's own. They're under its MIT licence (`../../../../LICENSE`).
