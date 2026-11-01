# Kodi: licensing of this directory

**Third-party:** `queries.sql` and `schema.sql` quote SQL from [xbmc/xbmc](https://github.com/xbmc/xbmc) at commit
`3294b709ca23b3fd67a7784951246fefecc1dd34`, as do this project's 30 entries in `../../manifest.jsonl` (their `sql`
field). Copyright belongs to that project's authors. That SQL is licensed under the project's own licence,
**GPL-2.0-or-later**, not under cursed-sqlite-turbo's MIT licence. The repository's root LICENSE.md (copied as
LICENSE.upstream) names GPL-2.0-or-later and points to LICENSES/GPL-2.0-or-later, which is LICENSE here.

**Changes from the original:**
- The statements were extracted from the application's code, and the `CREATE` statements from its migrations, in
  October 2026.
- Parameters are written as SQLite parameters, and values the application interpolates are filled in. The statements
  are reformatted.
- 3 statements are changed further, as `queries.sql` notes beside each one (`@modified`).

Each statement's source file and line range is in `queries.sql` and the manifest.

**This repository's own work:** `data.sql` (synthetic data), `meta.json`, `expected.json` and `timings.json` are
cursed-sqlite-turbo's own. They're under its MIT licence (`../../../../LICENSE`).
