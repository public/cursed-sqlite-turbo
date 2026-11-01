# Vaultwarden: licensing of this directory

**Third-party:** `queries.sql` and `schema.sql` quote SQL from [dani-garcia/vaultwarden](https://github.com/dani-
garcia/vaultwarden) at commit `0f44744ef86a2a7bea615af1c024044ce5736187`, as do this project's 27 entries in
`../../manifest.jsonl` (their `sql` field). Copyright belongs to that project's authors. That SQL is licensed under
the project's own licence, **AGPL-3.0**, not under cursed-sqlite-turbo's MIT licence. LICENSE is the repository's
LICENSE.txt, copied unchanged.

**Changes from the original:**
- The statements were extracted from the application's code, and the `CREATE` statements from its migrations, in
  October 2026.
- Parameters are written as SQLite parameters, and values the application interpolates are filled in. The statements
  are reformatted.
- 0 statements are changed further, as `queries.sql` notes beside each one (`@modified`).

Each statement's source file and line range is in `queries.sql` and the manifest.

**This repository's own work:** `data.sql` (synthetic data), `meta.json`, `expected.json` and `timings.json` are
cursed-sqlite-turbo's own. They're under its MIT licence (`../../../../LICENSE`).
