# SQLite query corpus: index

**803 queries from 27 real applications.** Each has its schema and synthetic data, and all of them run in the stock
`sqlite3` CLI (3.54), with no failures and no read returning zero rows (`tools/run.py --all`, 2026-10-28).
- **Shape:** 627 queries do real engine work; 176 are tagged `hot-small`, the regression guards. 293 compile to 100
  or more VDBE ops.
- **Data:** synthetic data builds every database in 0.1 to 4 s at scale 1 (15 to 93 MB). `--scale N` multiplies the row counts.
- **Elsewhere:** the format is in [README.md](README.md), every candidate and why it was or wasn't picked is in
  [SURVEY.md](SURVEY.md), and tag counts and complexity tables are in [STATS.md](STATS.md).
- **Machine-readable:** `manifest.jsonl` holds one query per line, with provenance, params, tags, VDBE op count,
  row count and output hash.

## Ranking

| # | Project | Stars | Reach | V | I | **Score** | Queries | hot-small | License | Category |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | [Firefox Places](projects/firefox-places/) | 13,627 | 3 | 6.6 | 9.9 | **65.3** | 35 | 6 | MPL-2.0 | web browser (history, bookmarks, address bar) |
| 2 | [Home Assistant (recorder, history, logbook)](projects/home-assistant/) | 91,791 | 2 | 7.4 | 8.4 | **62.2** | 35 | 8 | Apache-2.0 | home automation (time-series recorder) |
| 3 | [n8n](projects/n8n/) | 208,849 | 1 | 7.0 | 8.2 | **57.4** | 32 | 6 | Sustainable Use License | self-hosted server (workflow automation) |
| 4 | [Kodi](projects/kodi/) | 21,388 | 2 | 5.8 | 9.2 | **53.4** | 30 | 7 | GPL-2.0-or-later | media center (video + music library) |
| 5 | [Grafana](projects/grafana/) | 77,563 | 2 | 7.2 | 7.4 | **53.3** | 29 | 7 | AGPL-3.0 | self-hosted server (observability dashboards) |
| 6 | [Jellyfin](projects/jellyfin/) | 58,729 | 1 | 5.7 | 8.9 | **50.7** | 30 | 6 | GPL-2.0 | self-hosted server (media) |
| 7 | [Signal Desktop](projects/signal-desktop/) | 16,630 | 2 | 5.6 | 9.0 | **50.4** | 29 | 7 | AGPL-3.0-only | desktop app (end-to-end encrypted messenger) |
| 8 | [Pi-hole FTL](projects/pihole-ftl/) | 1,728 | 2 | 7.0 | 7.1 | **49.7** | 30 | 7 | EUPL-1.2 | network appliance (DNS sinkhole / ad blocker) |
| 9 | [Syncthing](projects/syncthing/) | 89,832 | 2 | 7.4 | 6.7 | **49.6** | 31 | 8 | MPL-2.0 | desktop/server sync daemon (continuous file synchronisation) |
| 10 | [Navidrome](projects/navidrome/) | 24,411 | 1 | 4.7 | 9.8 | **46.1** | 30 | 6 | GPL-3.0 | self-hosted server (music streaming, Subsonic API) |
| 11 | [claude-mem](projects/claude-mem/) | 103,845 | 0 | 5.0 | 9.1 | **45.5** | 32 | 6 | Apache-2.0 | developer tool (Claude Code memory plugin) |
| 12 | [Zotero](projects/zotero/) | 15,774 | 2 | 5.5 | 8.2 | **45.1** | 30 | 6 | AGPL-3.0-or-later | desktop app (reference manager, Firefox-platform JS over mozStorage) |
| 13 | [Joplin](projects/joplin/) | 56,910 | 1 | 5.6 | 7.6 | **42.6** | 30 | 7 | AGPL-3.0-or-later | desktop/mobile app (notes, sync) |
| 14 | [Memos](projects/memos/) | 64,136 | 1 | 5.8 | 7.3 | **42.3** | 24 | 8 | MIT | self-hosted server (notes) |
| 15 | [Anki](projects/anki/) | 32,356 | 2 | 6.3 | 6.6 | **41.6** | 30 | 7 | AGPL-3.0-or-later | desktop/mobile app (spaced-repetition flashcards; Rust core shared by desktop, AnkiDroid backend and sync server) |
| 16 | [Chromium History](projects/chromium-history/) | 25,164 | 3 | 7.3 | 5.4 | **39.4** | 35 | 7 | BSD-3-Clause | web browser (history, omnibox, NTP most visited) |
| 17 | [Trilium Notes](projects/trilium/) | 38,600 | 1 | 5.2 | 7.4 | **38.5** | 33 | 7 | AGPL-3.0 | desktop + self-hosted server (hierarchical notes) |
| 18 | [calibre](projects/calibre/) | 26,266 | 2 | 6.0 | 6.3 | **37.8** | 26 | 7 | GPL-3.0 | desktop app + content server (e-book library manager) |
| 19 | [Uptime Kuma](projects/uptime-kuma/) | 93,019 | 1 | 6.2 | 5.9 | **36.6** | 24 | 6 | MIT | self-hosted server (uptime monitoring) |
| 20 | [Vaultwarden](projects/vaultwarden/) | 69,812 | 1 | 5.9 | 6.1 | **36.0** | 27 | 5 | AGPL-3.0 | self-hosted server (password manager, Bitwarden-compatible) |
| 21 | [Audiobookshelf](projects/audiobookshelf/) | 14,827 | 1 | 4.2 | 8.5 | **35.7** | 31 | 6 | GPL-3.0 | self-hosted server (audiobooks and podcasts) |
| 22 | [darktable](projects/darktable/) | 13,350 | 1 | 4.1 | 8.2 | **33.6** | 30 | 7 | GPL-3.0 | desktop app (photo workflow / raw developer) |
| 23 | [FreshRSS](projects/freshrss/) | 16,434 | 1 | 4.3 | 7.8 | **33.5** | 35 | 6 | AGPL-3.0 | self-hosted server (feed reader) |
| 24 | [Atuin](projects/atuin/) | 32,111 | 0 | 3.8 | 7.4 | **28.1** | 25 | 6 | MIT | desktop CLI (shell history sync) |
| 25 | [beets](projects/beets/) | 15,857 | 0 | 3.0 | 8.8 | **26.4** | 20 | 5 | MIT | CLI / music library manager |
| 26 | [Synapse](projects/synapse/) | 4,738 | 1 | 2.9 | 9.1 | **26.4** | 35 | 7 | AGPL-3.0 | self-hosted server (Matrix homeserver) |
| 27 | [Datasette](projects/datasette/) | 11,525 | 0 | 2.7 | 7.3 | **19.7** | 25 | 5 | Apache-2.0 | data publishing tool (web UI/API over SQLite) |

### How the score works

**Score = Interest × Visibility**, each from 0 to 10. `tools/index.py` computes both, so the table above is
reproducible.

**Interest (I)** comes from the queries themselves:
- **Per-query complexity:** `cx = log2(VDBE ops) + feature weights`. The weights are: 2 for recursive CTE or window;
  1 for 3+ table accesses, correlated subquery, CTE, FTS or JSON; 0.5 for subquery, GROUP BY, HAVING, UPSERT, temp
  B-tree, compound, EXISTS, multi-index OR or automatic index; 0.25 for CASE, LIKE/GLOB, date or string building.
  VDBE ops come from `EXPLAIN`; the table accesses and plan features come from `EXPLAIN QUERY PLAN`.
- **Project interest:** the mean `cx` of the project's 15 most complex queries, scaled so the corpus best is 10. It is
  then weighted by `0.8 + 0.4 × (share of queries on a hot path)`, so apps whose heavy SQL runs on list pages, sync and
  search beat apps whose heavy SQL is admin-only.

**Visibility (V)** comes from GitHub plus real-world reach:
- **Stars:** `2·log10(stars/1000)`, clipped to 0–5 (1k scores 0, 10k scores 2, 100k scores 4). Pi-hole FTL uses its
  umbrella repo's stars.
- **Reach:** 0–3 points for installs that GitHub stars don't capture. Browsers get 3. Signal, Anki, Home Assistant,
  Kodi, calibre, Zotero, Syncthing, Pi-hole and Grafana get 2. Widely self-hosted servers get 1. Developer tools get 0.
  The reason for each is in `meta.json` as `reach_note`.
- **Staleness:** minus 1 if the last push is older than 180 days (none are).
- **Scale:** the total is scaled from a maximum of 8 to 10.

**Caveats:**
- **Reach is a judgement call.** Stars undercount browsers and messengers and overcount fashionable developer tools,
  claude-mem especially.
- **Interest only measures the queries captured.** Projects with a narrow SQL surface (Uptime Kuma, Chromium history)
  score lower even when those queries are very hot.

## Top 10

1. **Firefox Places:** the address bar runs SQL on every keystroke. The origin-autofill CTE has four window functions
   partitioned by a computed host plus a correlated subquery (1,200 ops). There are also recursive CTEs over the
   bookmarks tree and frecency-ordered top-N with correlated bookmark/tag subqueries. Firefox's own SQL functions
   (`hash`, `AUTOCOMPLETE_MATCH`, `fixup_url`) are replaced by core SQL, marked `@modified`.
2. **Home Assistant:** every query is compiled from the recorder's real SQLAlchemy builders at the pinned SHA, not
   rewritten by hand. Highlights: history (UNION ALL of start states joined to a correlated `LIMIT 1`), statistics
   (GROUP BY with a CASE switching to circular means via atan2/sin/cos) and the logbook (a CTE feeding a 4-way UNION
   ALL with JSON_EXTRACT). These sit behind every dashboard graph.
3. **n8n:** the execution list (correlated EXISTS for access, six joins, COALESCE-ordered top-N) and the insights
   aggregates (eight SUM(CASE) over a date CTE). TypeORM output reconstructed from the builder code.
4. **Kodi:** library browsing goes through views stacked on GROUP BY views. Genre filters use three levels of
   correlated EXISTS. One delete fires 12 trigger DELETEs.
5. **Grafana:** unified-storage resource listing (GROUP BY max version joined back, NOT EXISTS), annotation tag matching
   and the 3-way RBAC UNION.
6. **Jellyfin 10.10:** SqliteItemRepository's item queries: home "latest", resume, next-up, similar items (CASE plus
   correlated counts over shared genres and people), and a correlated MAX(LastPlayedDate) sort.
7. **Signal Desktop:** a call-history page with three correlated subqueries per row (JSON_GROUP_ARRAY, a LAG window,
   GROUP BY CASE), FTS5 search with a FULL OUTER JOIN of mentions, and conversation pages on partial indexes over
   generated columns.
8. **Pi-hole FTL:** a gravity lookup through 3 LEFT JOINs on every DNS cache miss, which is turbo's most important
   `hot-small` guard. Also the query-log API with filters and time-bucket GROUP BY.
9. **Syncthing:** the "need" and global-file queries (UNION ALL of correlated EXISTS/NOT EXISTS self-joins), plus the
   upsert triggers on every index update.
10. **Navidrome:** FTS5 bm25 ranking numbered with `row_number()` and joined back to annotations, smart playlists over
    `json_tree`, and a five-CTE stats refresh.

## Best targets for a query specialiser

Ranked by complexity among hot-path queries (the full list is in [STATS.md](STATS.md)). They fall into five families:

1. **Wide row construction with many correlated scalar subqueries:** `zotero.items.primary_data` (1,536 ops),
   `calibre.legacy.meta2_refresh`, `signal-desktop.calls.history_groups_page`, `jellyfin.browse.*`,
   `abs.home.continue_series`. The same subquery shapes repeat for every row. That's the ideal case for specialised
   plans: each subquery is a tiny indexed lookup, and SQLite's per-row interpreter overhead dominates.
2. **Top-N over filtered joins:** `memos.list_memos.home_feed`, `freshrss.entry.list_where.*`,
   `n8n.executions.list_*`, `kodi.video.*`, `navidrome.album.*`, `firefox.urlbar.places_default`. They run on every
   list page, hit stacked EXISTS predicates and sort with a temp B-tree under LIMIT. Specialised predicate evaluation
   and top-N sorting pay off directly.
3. **Window and CTE analytics:** `firefox.autofill.origin_*` (1,200 ops), `ha.statistics.*`, `ha.logbook.*`,
   `n8n.insights.*`, `trilium.space_usage.excess_revisions_size`, `datasette.permissions.allowed_tables_page`.
   Aggregate-heavy, with materialised CTEs and window functions. This is the niche where turbo should win big.
4. **FTS5 combined with relational filters:** `navidrome.search.*_fts`, `claude-mem.search.observations_fts_filtered`,
   `joplin.search.fts_*`, `zotero.search.quicksearch_all_fields_fts`, `signal-desktop.search.*`. The FTS virtual table
   is opaque, so the win comes from the joins and filters around it.
5. **EAV and JSON predicate scans:** `memos.list_memos.tag_filter` (correlated json_each),
   `beets.ls.items_flexattr_filter`, `audiobookshelf` library filters, `navidrome.smart_playlist.*` (json_tree). These
   are expression-heavy full scans where per-row interpretation cost dominates.

**Regression guards (`hot-small`, 176 queries):** point lookups and short inserts run thousands of times per
second. Turbo must stay at or under 1.02x stock on these. The most important are `ftl.gravity.lookup_gravity` (every
DNS miss), `syncthing.update.insert_file` (INSERT OR REPLACE … RETURNING with triggers), `ha.recorder.states.insert`,
`memos.get_user_by_pat_hash` (every API call), and the `*.by_id`/`*.get_*` lookups in every project.

## Fidelity notes

- **Taken from source:** every query is from the pinned source, with a `file:line` link. All 263 cited files resolve
  at their SHA. A 108-query sample of cited line ranges was checked against the source. 10 matched weakly, and those
  are generated SQL where table and column names come from data or the ORM.
- **Runtime-built queries (480, tagged `dynamic`):** each is one representative instantiation of SQL the app builds at
  runtime. Home Assistant's are compiled from the real builders. n8n (TypeORM), Vaultwarden (Diesel), Audiobookshelf
  (Sequelize), Atuin (sql_builder) and Uptime Kuma (knex) are reconstructed from the builder code: the structure
  follows the code, but exact quoting and parenthesisation are best-effort.
- **Modified queries (77, tagged `modified`, with the reason in `@modified`):** app-registered SQL functions,
  collations and FTS tokenizers were replaced with core SQL (Firefox, calibre, Anki, Kodi's ALPHANUM collation, Signal's
  tokenizer, Navidrome's SEEDEDRAND, Jellyfin's RANDOM). Attached-database prefixes were dropped (darktable, Zotero,
  calibre). TEMP tables became ordinary tables so they survive between runner processes.
- **Clock-dependent queries (5, tagged `wallclock`):** they read the clock. Compare row counts, not hashes, across
  days. The data itself never uses `'now'` or `random()`, and two consecutive runs reproduce every other hash.
- **Not core SQLite:** a few Anki queries need `REGEXP`, which the stock shell provides but core SQLite doesn't.
- **Licensing:** for GPL, AGPL and EUPL projects, `schema.sql` holds only the CREATE statements the queries need, and
  `tools/fetch.sh <project>` fetches the original files at the pinned SHA. No clones, binaries or databases are stored.
