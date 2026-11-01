# n8n: licensing of this directory

**Third-party:** `queries.sql` and `schema.sql` quote SQL from [n8n-io/n8n](https://github.com/n8n-io/n8n) at commit
`02cb18e19c8626adbc2d50122a71e7cb230dd856`, as do this project's 32 entries in `../../manifest.jsonl` (their `sql`
field). Copyright belongs to that project's authors. That SQL is licensed under the project's own licence,
**Sustainable Use License**, not under cursed-sqlite-turbo's MIT licence. LICENSE is the repository's LICENSE.md,
copied unchanged.

**Changes from the original:**
- The statements were extracted from the application's code, and the `CREATE` statements from its migrations, in
  October 2026.
- Parameters are written as SQLite parameters, and values the application interpolates are filled in. The statements
  are reformatted.
- 3 statements are changed further, as `queries.sql` notes beside each one (`@modified`).

Each statement's source file and line range is in `queries.sql` and the manifest.

**This repository's own work:** `data.sql` (synthetic data), `meta.json`, `expected.json` and `timings.json` are
cursed-sqlite-turbo's own. They're under its MIT licence (`../../../../LICENSE`).
