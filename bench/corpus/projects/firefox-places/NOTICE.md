# Firefox Places: licensing of this directory

**Third-party:** `queries.sql` and `schema.sql` quote SQL from
[mozilla-firefox/firefox](https://github.com/mozilla-firefox/firefox) at commit
`be3847db4e2bcc52fa3f078b8b4a1ff167ad158f`, as do this project's 35 entries in `../../manifest.jsonl` (their `sql`
field). Copyright belongs to that project's authors. That SQL is licensed under the project's own licence,
**MPL-2.0**, not under cursed-sqlite-turbo's MIT licence. The repository's root LICENSE points to
toolkit/content/license.html; the code quoted here (toolkit/components/places, browser/components) is under the
Mozilla Public License 2.0, whose text is in LICENSE.

**Changes from the original:**
- The statements were extracted from the application's code, and the `CREATE` statements from its migrations, in
  October 2026.
- Parameters are written as SQLite parameters, and values the application interpolates are filled in. The statements
  are reformatted.
- 18 statements are changed further, as `queries.sql` notes beside each one (`@modified`).

Each statement's source file and line range is in `queries.sql` and the manifest.

**This repository's own work:** `data.sql` (synthetic data), `meta.json`, `expected.json` and `timings.json` are
cursed-sqlite-turbo's own. They're under its MIT licence (`../../../../LICENSE`).
