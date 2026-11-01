# Survey

I surveyed more than 60 candidates on 2026-10-28, using GitHub repo metadata (stars, last push and licence from the API, read as the
"public" account), a topic search (`topic:sqlite stars:>3000`), five code searches (`WITH RECURSIVE` with
better-sqlite3, `ROW_NUMBER() OVER` with sqlite3 in Go, FTS5 `bm25(` in Rust, `json_each` with sqlite in Python, and
`ON CONFLICT … DO UPDATE` with modernc.org/sqlite), and the brief's list. 27 were selected; the ranking is in
[INDEX.md](INDEX.md).

## Selected (27)

| Project | Repo | Stars | Licence | Why it's in |
|---|---|---|---|---|
| Firefox Places | mozilla-firefox/firefox | 13.6k (mirror) | MPL-2.0 | Address-bar autofill and search, bookmarks tree CTEs, frecency |
| Home Assistant | home-assistant/core | 91.8k | Apache-2.0 | Recorder history and statistics and the logbook; SQL compiled from its real SQLAlchemy builders |
| n8n | n8n-io/n8n | 208.8k | Sustainable Use | Execution list and insights aggregates (TypeORM on SQLite by default) |
| Kodi | xbmc/xbmc | 21.4k | GPL-2.0+ | Views stacked on views, GROUP BY views and library browsing |
| Grafana | grafana/grafana | 77.6k | AGPL-3.0 | Unified-storage resource queries, annotations, RBAC unions |
| Jellyfin 10.10 | jellyfin/jellyfin | 58.7k | GPL-2.0 | The last raw-SQL release: SqliteItemRepository's giant item queries |
| Signal Desktop | signalapp/Signal-Desktop | 16.6k | AGPL-3.0 | Call history windows, FTS5 search, conversation pages |
| Pi-hole FTL | pi-hole/FTL (umbrella pi-hole/pi-hole 61.5k) | 1.7k | EUPL-1.2 | Gravity lookups on every DNS miss, query-log API |
| Syncthing | syncthing/syncthing | 89.8k | MPL-2.0 | v2's SQLite index: need/global and counts self-joins, upsert triggers |
| Navidrome | navidrome/navidrome | 24.4k | GPL-3.0 | FTS5 + window search, smart playlists over json_tree, CTE stats refresh |
| claude-mem | thedotmack/claude-mem | 103.8k | Apache-2.0 | FTS5 + json_each observation search, context assembly unions |
| Zotero | zotero/zotero | 15.8k | AGPL-3.0 | Item tree with dozens of correlated subqueries (1536 ops), compiled searches |
| Joplin | laurent22/joplin | 56.9k | AGPL-3.0 | FTS4 search with recursive notebook CTEs, note lists |
| Memos | usememos/memos | 64.1k | MIT | Timeline with stacked EXISTS access predicates, JSON tag filters |
| Anki | ankitects/anki | 32.4k | AGPL-3.0 | Browser search to SQL, deck-tree due counts, scheduler queues |
| Chromium History | chromium/chromium | 25.2k (mirror) | BSD-3-Clause | History page, omnibox prefix scans, clusters, most-visited segments |
| Trilium Notes | TriliumNext/Trilium | 38.6k | AGPL-3.0 | Recursive note-tree CTEs, ROW_NUMBER revision pruning, entity_changes sync |
| calibre | kovidgoyal/calibre | 26.3k | GPL-3.0 | The meta view (about 15 correlated link subqueries per book), FTS5 annotations |
| Uptime Kuma | louislam/uptime-kuma | 93.0k | MIT | Heartbeat lists, stat aggregate upserts, status pages |
| Vaultwarden | dani-garcia/vaultwarden | 69.8k | AGPL-3.0 | /api/sync cipher visibility: six LEFT JOINs and a five-way OR (Diesel) |
| Audiobookshelf | advplyr/audiobookshelf | 14.8k | GPL-3.0 | Library filters with literal subqueries and JSON, home shelves |
| darktable | darktable-org/darktable | 13.4k | GPL-3.0 | Lighttable collection builder, collect-module counts, tag suggestions |
| FreshRSS | FreshRSS/FreshRSS | 16.4k | AGPL-3.0 | Entry list keyset paging, unread counts, archiving deletes |
| Atuin | atuinsh/atuin | 32.1k | MIT | Shell-history search with dedup NOT EXISTS, stats, record-store gaps |
| beets | beetbox/beets | 15.9k | MIT | `beet ls` with flexible attributes (EAV), path-prefix tests |
| Synapse | element-hq/synapse | 4.7k (12k+ before moving from matrix-org) | AGPL-3.0 | Push-action unread counts, recursive relations, room pagination |
| Datasette | simonw/datasette | 11.5k | Apache-2.0 | Facets (json_each array facets), FTS search, permission CTEs |

## Not selected

| Project | Stars | Reason |
|---|---|---|
| Gitea (go-gitea/gitea) | 58.7k | Already covered by the turbo repo's `explore/gitea-jit` integration, so not duplicated |
| Immich | 117.5k | PostgreSQL only |
| Mattermost | 39.5k | No SQLite backend (PostgreSQL/MySQL) |
| Ghost | 55.6k | SQLite for development only; production needs MySQL. knex/bookshelf generic CRUD |
| Directus | 38.7k | SQLite through a generic knex builder; no app-specific SQL shape |
| NocoDB / Strapi | 65.4k / 73.4k | Same: generic knex CRUD over user-defined tables |
| Open WebUI | 157.0k | SQLite default, but simple ORM CRUD (SQLAlchemy/peewee) |
| PocketBase | 61.6k | Archived flag set on GitHub; dbx builder over user collections |
| Paperless-ngx / linkding | 47.2k / 11.4k | Django ORM; plausible future candidates via `connection.queries` capture |
| PhotoPrism | 40.4k | GORM; MySQL/MariaDB recommended. Its search builder is a future candidate |
| Harness (Gitness) | 38.7k | Supports SQLite (squirrel builder); future candidate |
| Sonarr / Radarr | 17.5k / 14.7k | SQLite default with a Dapper SqlBuilder; mostly simple joins. Future candidate |
| Stash | 13.3k | Heavy raw SQL filter builder (a good shape), but an adult-content app. Skipped for the corpus's audience |
| Kavita / Komga | 12.0k / 6.8k | EF Core / jOOQ; generated SQL only |
| Actual Budget | 29.8k | AQL compiles to rich SQL (subqueries, joins), but needs its compiler to instantiate. Strong future candidate |
| tdlib | 9.2k | SQLite message DB in C++; mostly key-range lookups |
| Kanboard | 9.9k | SQLite default via the PicoDb builder; small CRUD |
| Strawberry | 4.0k | Collection queries similar to Kodi/beets, lower visibility |
| Isso | 5.3k | A handful of small comment queries |
| Timelinize | 3.7k | Interesting SQLite-heavy design, low visibility |
| digiKam | 0.8k (archived mirror; real home invent.kde.org) | Good SQL, but the GitHub mirror is archived; would need KDE GitLab |
| Dendrite | 5.6k | Archived (2024) |
| osquery | 23.7k | The SQL is user-written over C++ virtual tables, which stock SQLite can't run |
| Fossil | 0.2k (mirror) | Low priority per brief; rich timeline SQL. Candidate if visibility matters less |
| Obsidian plugins (Dataview etc.) | — | No SQLite; Dataview has its own query engine |
| Plex / Emby | — | Closed source (Plex's library DB is SQLite, but no citable source) |
| Bitwarden server | — | MSSQL; Vaultwarden covers the SQLite side |
| Litestream / LiteFS / Turso-libSQL | 14.5k / — / 17.3k | Replication and engine infrastructure, no application queries |
| Rails 8 / Django SQLite-default apps | — | 37signals' ONCE apps (Campfire, Writebook) aren't open-source on GitHub; nothing else notable found |
| Hacker News clones | — | Lobsters is MySQL; no prominent SQLite clone |
| DBeaver / sqlitebrowser / Beekeeper / Chat2DB | 52k / 24.7k / 23.8k / 28.3k | Database clients; their SQL is catalog introspection, not workloads |
| ORMs (Prisma, Drizzle, TypeORM, Sequelize, Diesel, sqlx, Kysely, peewee) | — | Libraries; covered through the apps that use them (n8n: TypeORM, Vaultwarden: Diesel, Audiobookshelf: Sequelize, Atuin: sqlx) |
| Bluesky atproto PDS | 9.7k | SQLite per account via Kysely; future candidate |
| codebase-memory-mcp | 47.7k | Code-intelligence store; not investigated past metadata |

Code-search hits that were too small or too young to rank (for example cropflre/nowen-note, kenn-io/msgvault and
Southclaws/storyden) were noted but not pursued.

## Wave 2 (2026-10-30): CPU-bound and analytics workloads

The second hunt targeted apps whose SQLite queries are CPU-bound today. That means dashboards, reports, statistics,
retention jobs and big list pages, as opposed to point lookups. A candidate counted as CPU-bound when its issue
tracker reports real slowness on SQLite; I searched each one with `repo:X sqlite slow`. 45 more repos were checked,
and 17 were selected. Each selected project's `meta.json` has `cpu_evidence` with the issue links, and the queries
those issues implicate are tagged `cpu-evidence`.

### Selected (17)

| Project | Stars | Licence | Slowness on record (from `cpu_evidence`) |
|---|---|---|---|
| Grocy | 9.6k | MIT | SQLite 3.53's UNION sort-and-merge makes recipes_resolved take 15.7 s (0.3 s with UNION ALL); /recipes and /mealplan take 10-15 s |
| CrowdSec | 15.4k | MIT | GET /v1/alerts stuck in sqlite3_step for 3h+, pinning a core; the decisions stream took 26-37 min at 2.2M decisions |
| screenpipe | 22.2k | source-available | The /activity-summary statement took 20-63 s on a 148k-frame database (removed 2026-11-01: the Screenpipe Commercial License does not allow redistribution) |
| Tautulli | 6.6k | GPL-3.0 | History page about 20 s at 350k rows; home stats about 70 s |
| KOReader (statistics plugin) | 30.7k | AGPL-3.0 | Calendar view about 500 ms per query on a Kobo; the sync merge is pathological at scale |
| Wakapi | 4.5k | MIT | The one-year activity chart took 15-30 s (513k heartbeats) |
| Karakeep | 30.2k | AGPL-3.0 | lists.stats took 16.3 s on a Pi (42k bookmarks, 348k tag links) |
| Dagster | 16.4k | Apache-2.0 | The Automation page takes 3-6 min with long-running sensors; tick and run-tag lookups time out |
| Prefect | 24.1k | Apache-2.0 | The flow-run history time-bucket view times out |
| Phoenix (Arize) | 12.1k | Elastic-2.0 | The experiments page times out; compareExperiments isn't paginated |
| MLflow | 28.6k | Apache-2.0 | search_runs doesn't scale past thousands of runs; trace span loading times out |
| Optuna | 15.0k | MIT | 1000-trial study: 1m42s with SQLite storage vs 6.9 s in memory |
| Frigate | 37.1k | MIT | Event/timeline/recording counts take 0.9-6.9 s at 42 cameras |
| NetAlertX | 7.3k | GPL-3.0 | Constant high CPU at 1.7 GB; the cleanup job times out at 30 s |
| Actual Budget | 29.9k | MIT | Budget load stalls 10-20 s; the running balance took 802 ms before an index fix |
| Technitium DNS (Query Logs app) | 10.3k | GPL-3.0 | Query-log page "gets really slow" at 0.4-18 GB |
| GoatCounter | 6.1k | EUPL-1.2 | Path filters over many paths spent minutes planning |

### Checked, not selected

| Project | Stars | Reason |
|---|---|---|
| Firefly III | 25.0k | Laravel Eloquent; MySQL/Postgres recommended, SQLite secondary. Reports are a future candidate |
| Speedtest Tracker | 6.0k | Laravel; one perf issue (#2449), small query surface |
| Gatus | 12.4k | Go raw SQL on SQLite, but its slowness reports are about the UI, not the DB |
| Beszel | 26.7k | PocketBase; aggregation happens in Go |
| ActivityWatch (aw-server-rust) | 0.3k | Aggregation runs in its own query language, not SQL |
| lnav | 10.8k | Analytics over log virtual tables that stock SQLite can't load |
| GDAL GeoPackage / QGIS | 6.1k / 14.7k | R*Tree spatial filters are a different domain. A future candidate for spatial queries |
| imessage-exporter | 5.7k | Reads Apple's chat.db; joins are simple |
| LND / Core Lightning | 8.2k / 3.1k | OLTP-style payment and invoice lookups |
| Label Studio, AnythingLLM, promptfoo | 28.6k / 67.8k / 26.6k | ORM CRUD; slowness reports were about the app, not SQL |
| Kutt, Prowlarr, Mixxx, KMyMoney, GnuCash, GarminDB, Nextcloud | various | No SQLite slowness on record, or SQLite isn't the main backend |
| MoneyManagerEx | 2.3k | SQLite-only reports, but low visibility. A future candidate |
| Maloja | 1.9k | Scrobble charts on SQLite, but low visibility and little slowness on record |
| GoToSocial | n/a | Moved to Codeberg. Not followed up |
| Statistics for Strava | 0.0k | The repo was renamed or emptied. Not followed up |

Many newer self-hosted analytics tools (Liwan, Medama) chose DuckDB, and Plausible, Umami and Rybbit chose
ClickHouse or Postgres. That is the niche a faster SQLite would win back. The apps above are the ones still on
SQLite and visibly paying for it.
