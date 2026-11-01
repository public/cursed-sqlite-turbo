# Synapse: licensing of this directory

**Third-party:** `queries.sql` and `schema.sql` quote SQL from [element-hq/synapse](https://github.com/element-
hq/synapse) at commit `b20ae98cc5ead16212de01f00dff8862f1766bb3`, as do this project's 35 entries in
`../../manifest.jsonl` (their `sql` field). Copyright belongs to that project's authors. That SQL is licensed under
the project's own licence, **AGPL-3.0**, not under cursed-sqlite-turbo's MIT licence. Synapse is dual-licensed:
AGPL-3.0 (LICENSE-AGPL-3.0, which is LICENSE here) or a commercial licence from Element. This corpus uses it under the
AGPL-3.0.

**Changes from the original:**
- The statements were extracted from the application's code, and the `CREATE` statements from its migrations, in
  October 2026.
- Parameters are written as SQLite parameters, and values the application interpolates are filled in. The statements
  are reformatted.
- 2 statements are changed further, as `queries.sql` notes beside each one (`@modified`).

Each statement's source file and line range is in `queries.sql` and the manifest.

**This repository's own work:** `data.sql` (synthetic data), `meta.json`, `expected.json` and `timings.json` are
cursed-sqlite-turbo's own. They're under its MIT licence (`../../../../LICENSE`).
