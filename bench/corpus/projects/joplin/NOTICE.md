# Joplin: licensing of this directory

**Third-party:** `queries.sql` and `schema.sql` quote SQL from [laurent22/joplin](https://github.com/laurent22/joplin)
at commit `b613d0064d018c2f68d983c907ab88e2712da116`, as do this project's 30 entries in `../../manifest.jsonl` (their
`sql` field). Copyright belongs to that project's authors. That SQL is licensed under the project's own licence,
**AGPL-3.0-or-later**, not under cursed-sqlite-turbo's MIT licence. The repository's root LICENSE is LICENSE here; the
code quoted (packages/lib) is under AGPL-3.0-or-later, whose text is in AGPL-3.0.txt.

**Changes from the original:**
- The statements were extracted from the application's code, and the `CREATE` statements from its migrations, in
  October 2026.
- Parameters are written as SQLite parameters, and values the application interpolates are filled in. The statements
  are reformatted.
- 1 statements are changed further, as `queries.sql` notes beside each one (`@modified`).

Each statement's source file and line range is in `queries.sql` and the manifest.

**This repository's own work:** `data.sql` (synthetic data), `meta.json`, `expected.json` and `timings.json` are
cursed-sqlite-turbo's own. They're under its MIT licence (`../../../../LICENSE`).
