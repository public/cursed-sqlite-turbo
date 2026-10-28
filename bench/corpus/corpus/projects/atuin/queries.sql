-- Atuin (atuinsh/atuin @ a9fa414, MIT). sqlx with ?N placeholders for fixed statements; search/list/stats are built
-- with the sql_builder crate (3.1.1), which inlines quoted values and wraps each WHERE condition in parentheses when
-- there is more than one. Builder output is reproduced from sql_builder's query() format; those queries are tagged
-- dynamic. Paths are repo-relative.

-- @id atuin.search.fuzzy_global_dedup
-- @src crates/atuin-client/src/database.rs:714-886
-- @style sql_builder, values inlined; dedup wrapper format! at database.rs:874
-- @tags hotpath,dynamic
-- @note Every keystroke in the interactive TUI (fuzzy "gst", global filter): the filtered inner query is embedded twice, a correlated NOT EXISTS with a row-value (timestamp, id) comparison keeps the newest row per command, top-200.
SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind
FROM (SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind FROM history WHERE (command LIKE '%g%s%t%') AND (deleted_at IS NULL)) f
WHERE NOT EXISTS ( SELECT 1 FROM (SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind FROM history WHERE (command LIKE '%g%s%t%') AND (deleted_at IS NULL)) f2
                   WHERE f2.command = f.command AND (f2.timestamp, f2.id) > (f.timestamp, f.id) )
ORDER BY f.timestamp DESC LIMIT 200;

-- @id atuin.search.fulltext_directory_exit
-- @src crates/atuin-client/src/database.rs:714-886
-- @style sql_builder, values inlined; Directory filter (and_where_eq cwd), FullText tokens, exit filter
-- @tags hotpath,dynamic
-- @note Directory-scoped full-text search for two terms with an exit-code IN filter, deduplicated by NOT EXISTS, top-200.
SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind
FROM (SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind FROM history WHERE (cwd = '/home/alex/src/atuin') AND (command LIKE '%cargo%') AND (command LIKE '%test%') AND (exit in (0, 1)) AND (deleted_at IS NULL)) f
WHERE NOT EXISTS ( SELECT 1 FROM (SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind FROM history WHERE (cwd = '/home/alex/src/atuin') AND (command LIKE '%cargo%') AND (command LIKE '%test%') AND (exit in (0, 1)) AND (deleted_at IS NULL)) f2
                   WHERE f2.command = f.command AND (f2.timestamp, f2.id) > (f.timestamp, f.id) )
ORDER BY f.timestamp DESC LIMIT 200;

-- @id atuin.search.prefix_host
-- @src crates/atuin-client/src/database.rs:714-886
-- @style sql_builder, values inlined; Host filter from origin_sql_filter (database.rs:209), Prefix mode (and_where_like_left)
-- @tags hotpath,dynamic
-- @note Host-scoped prefix search: lower(hostname) equality OR a half-open range on the expression index, LIKE 'git c%', dedup, top-200.
SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind
FROM (SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind FROM history WHERE ((lower(hostname) = 'workstation' OR (lower(hostname) >= 'workstation:' AND lower(hostname) < 'workstation;'))) AND (command LIKE 'git c%') AND (deleted_at IS NULL)) f
WHERE NOT EXISTS ( SELECT 1 FROM (SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind FROM history WHERE ((lower(hostname) = 'workstation' OR (lower(hostname) >= 'workstation:' AND lower(hostname) < 'workstation;'))) AND (command LIKE 'git c%') AND (deleted_at IS NULL)) f2
                   WHERE f2.command = f.command AND (f2.timestamp, f2.id) > (f.timestamp, f.id) )
ORDER BY f.timestamp DESC LIMIT 200;

-- @id atuin.search.workspace_glob_authors_shells
-- @src crates/atuin-client/src/database.rs:714-886
-- @style sql_builder, values inlined; Workspace filter (LIKE git_root%), uppercase token switches to GLOB, apply_author_filter (database.rs:122) with $all-user, apply_shell_filter (database.rs:170)
-- @tags hotpath,dynamic
-- @note Workspace search with smart-case GLOB, the human-only author predicate (nested CASE over instr/substr/trim, an IN list of known agents), shell IN-or-NULL, dedup.
SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind
FROM (SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind FROM history WHERE (cwd LIKE '/home/alex/src/atuin%') AND (command GLOB '*T*O*D*O*') AND ((NOT (CASE WHEN author_kind IN (1, 2) THEN author_kind = 2 WHEN author IS NULL OR trim(author) = '' THEN 0 ELSE author IN ('claude-code', 'codex', 'copilot', 'omp', 'opencode', 'pi') AND author <> CASE WHEN instr(hostname, ':') = 0 THEN hostname WHEN substr(hostname, instr(hostname, ':') + 1) = 'unknown-user' THEN substr(hostname, 1, instr(hostname, ':') - 1) ELSE substr(hostname, instr(hostname, ':') + 1) END END))) AND (shell in ('zsh', 'bash') OR shell IS NULL) AND (deleted_at IS NULL)) f
WHERE NOT EXISTS ( SELECT 1 FROM (SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind FROM history WHERE (cwd LIKE '/home/alex/src/atuin%') AND (command GLOB '*T*O*D*O*') AND ((NOT (CASE WHEN author_kind IN (1, 2) THEN author_kind = 2 WHEN author IS NULL OR trim(author) = '' THEN 0 ELSE author IN ('claude-code', 'codex', 'copilot', 'omp', 'opencode', 'pi') AND author <> CASE WHEN instr(hostname, ':') = 0 THEN hostname WHEN substr(hostname, instr(hostname, ':') + 1) = 'unknown-user' THEN substr(hostname, 1, instr(hostname, ':') - 1) ELSE substr(hostname, instr(hostname, ':') + 1) END END))) AND (shell in ('zsh', 'bash') OR shell IS NULL) AND (deleted_at IS NULL)) f2
                   WHERE f2.command = f.command AND (f2.timestamp, f2.id) > (f.timestamp, f.id) )
ORDER BY f.timestamp DESC LIMIT 200;

-- @id atuin.search.session_preload_include_dups
-- @src crates/atuin-client/src/database.rs:714-886
-- @style sql_builder, values inlined; SessionPreload filter (and_where_eq session + or_where_lt timestamp), include_duplicates
-- @tags hotpath,dynamic
-- @note Up-arrow in a new shell: this session OR anything before it started, fuzzy match, no dedup, top-200 by time.
SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind
FROM (SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind FROM history WHERE (session = '0199fdd1a9007b548b5407004c6e8914' OR timestamp < 1760900000000000000) AND (command LIKE '%k%u%b%') AND (deleted_at IS NULL)) f
ORDER BY f.timestamp DESC LIMIT 200;

-- @id atuin.list.unique_global
-- @src crates/atuin-client/src/database.rs:598-657
-- @style sql_builder, values inlined; unique=true adds GROUP BY command HAVING max(timestamp)
-- @tags hotpath,dynamic
-- @note `atuin history list --unique`: GROUP BY command with a bare-column max(timestamp) HAVING, newest first, limit.
SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind
FROM `history` AS h WHERE deleted_at IS NULL GROUP BY command HAVING max(timestamp) ORDER BY timestamp DESC LIMIT 100;

-- @id atuin.list.session_cwd_range
-- @src crates/atuin-client/src/database.rs:598-657
-- @style sql_builder, values inlined; Session and Directory filters plus an inclusive range
-- @tags hotpath,dynamic
-- @note Filtered listing over four parenthesised conditions plus the range bounds, newest first.
SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind
FROM `history` AS h WHERE (deleted_at IS NULL) AND (session = '0199fdd1a9007b548b5407004c6e8914') AND (cwd = '/home/alex/src/atuin/crates/atuin-client') AND (timestamp >= 1750000000000000000) AND (timestamp <= 1770000000000000000) ORDER BY timestamp DESC;

-- @id atuin.history.load
-- @src crates/atuin-client/src/database.rs:498-510
-- @style ?N positional
-- @tags hot-small,hotpath
-- @note Point lookup by primary key.
-- @param ?1 '0199db3f91d07b208a191d27625cc2e0'
select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind from history where id = ?1;

-- @id atuin.history.load_active
-- @src crates/atuin-client/src/database.rs:519-566
-- @style ? positional, one per id (chunks of 500)
-- @tags hotpath,dynamic
-- @note Batched load of live rows by id after a sync download.
-- @param ?1 '0199db3f91d07b208a191d27625cc2e0'
-- @param ?2 '0192cf1828cf7c0f924218d01047b401'
-- @param ?3 '018bcfed5a3979b18e70131e360d5a3f'
-- @param ?4 '018bcff547627362aca7074d6c1ab47e'
-- @param ?5 '00000000000000000000000000000000'
select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind from history where id in (?1,?2,?3,?4,?5) and deleted_at is null;

-- @id atuin.history.save
-- @src crates/atuin-client/src/database.rs:414-439
-- @style ?N positional
-- @tags hot-small,hotpath
-- @note Insert-or-ignore on every command the shell hook records (four indexes plus the unique constraint to maintain).
-- @param ?1 '019a5b2c00007000800000000000abcd'
-- @param ?2 1762400100000000000
-- @param ?3 1200000000
-- @param ?4 0
-- @param ?5 'cargo test -p atuin-client'
-- @param ?6 '/home/alex/src/atuin'
-- @param ?7 '0199fdd1a9007b548b5407004c6e8914'
-- @param ?8 'laptop:alex'
-- @param ?9 'alex'
-- @param ?10 NULL
-- @param ?11 NULL
-- @param ?12 'zsh'
-- @param ?13 1
insert or ignore into history(
    id, timestamp, duration, exit, command, cwd, session, hostname, author, intent,
    deleted_at, shell, author_kind
) values(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13);

-- @id atuin.history.save_bulk
-- @src crates/atuin-client/src/database.rs:451-495
-- @style sqlx QueryBuilder::push_values, ? positional; 3 rows shown (real batches fill the bind limit)
-- @tags batch,dynamic
-- @note Multi-row insert-or-ignore used by import and record-store rebuilds.
-- @param ?1 '019a5b2c00007000800000000000a001'
-- @param ?2 1762400100000000001
-- @param ?3 '019a5b2c00007000800000000000a002'
-- @param ?4 1762400100000000002
-- @param ?5 '019a5b2c00007000800000000000a003'
-- @param ?6 1762400100000000003
insert or ignore into history(
    id, timestamp, duration, exit, command, cwd, session, hostname, author, intent,
    deleted_at, shell, author_kind
) VALUES (?1, ?2, 1000000, 0, 'ls -la', '/home/alex', '0199fdd1a9007b548b5407004c6e8914', 'laptop:alex', 'alex', NULL, NULL, 'zsh', 1),
         (?3, ?4, 2000000, 1, 'make -j8', '/home/alex/src/atuin', '0199fdd1a9007b548b5407004c6e8914', 'laptop:alex', 'alex', NULL, NULL, 'zsh', 1),
         (?5, ?6, 3000000, 0, 'git status', '/home/alex/src/atuin', '0199fdd1a9007b548b5407004c6e8914', 'laptop:alex', 'claude-code', 'check tree', NULL, 'zsh', 2);

-- @id atuin.history.update
-- @src crates/atuin-client/src/database.rs:569-595
-- @style ?N positional
-- @tags hot-small,hotpath
-- @note Shell hook end-of-command update (duration and exit) by primary key.
-- @param ?1 '0199db3f91d07b208a191d27625cc2e0'
-- @param ?2 1760320000464000000
-- @param ?3 4500000000
-- @param ?4 1
-- @param ?5 'npm run dev'
-- @param ?6 '/home/alex/src/atuin/crates/atuin-client'
-- @param ?7 '0199fdd1a9007b548b5407004c6e8914'
-- @param ?8 'server1:root'
-- @param ?9 'alex'
-- @param ?10 NULL
-- @param ?11 NULL
-- @param ?12 1
update history
    set timestamp = ?2, duration = ?3, exit = ?4, command = ?5, cwd = ?6, session = ?7, hostname = ?8, author = ?9, intent = ?10, deleted_at = ?11, author_kind = ?12
    where id = ?1;

-- @id atuin.history.last
-- @src crates/atuin-client/src/database.rs:676-686
-- @style no params
-- @tags hot-small,hotpath
-- @note Most recent finished command: filter on duration, top-1 by timestamp.
select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind from history where duration >= 0 order by timestamp desc limit 1;

-- @id atuin.history.count_active
-- @src crates/atuin-client/src/database.rs:702-711
-- @style no params
-- @tags hotpath
-- @note Live-row count, served by the partial timestamp index.
select count(1) from history where deleted_at is null;

-- @id atuin.inspector.runs_window
-- @src crates/atuin-client/src/database.rs:897-918
-- @style ?N positional
-- @tags hotpath
-- @note Inspector: UNION ALL of two row-value-bounded top-N windows around one entry of a command, re-sorted.
-- @param ?1 'git status'
-- @param ?2 1730051320015000000
-- @param ?3 '0192cf1828cf7c0f924218d01047b401'
select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind from (
     select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind from history
     where command = ?1 and deleted_at is null and (timestamp, id) <= (?2, ?3)
     order by timestamp desc, id desc limit 101)
 union all
 select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind from (
     select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind from history
     where command = ?1 and deleted_at is null and (timestamp, id) > (?2, ?3)
     order by timestamp, id limit 100)
 order by timestamp, id;

-- @id atuin.inspector.session_window
-- @src crates/atuin-client/src/database.rs:920-945
-- @style ?N positional
-- @tags hotpath
-- @note Same windowed UNION ALL keyed on session, served by the partial session index.
-- @param ?1 '0199fdd1a9007b548b5407004c6e8914'
-- @param ?2 1760320000464000000
-- @param ?3 '0199db3f91d07b208a191d27625cc2e0'
select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind from (
     select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind from history
     where session = ?1 and deleted_at is null and (timestamp, id) <= (?2, ?3)
     order by timestamp desc, id desc limit 101)
 union all
 select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind from (
     select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind from history
     where session = ?1 and deleted_at is null and (timestamp, id) > (?2, ?3)
     order by timestamp, id limit 100)
 order by timestamp, id;

-- @id atuin.history.all_with_count
-- @src crates/atuin-client/src/database.rs:948-982
-- @style sql_builder, no values
-- @tags dynamic
-- @note Whole-table GROUP BY command, exit with three group_concat aggregates, max() and count, sorted by the aggregate alias.
SELECT id, max(timestamp) as timestamp, max(duration) as duration, exit, command, deleted_at, null as author, null as intent, null as author_kind, group_concat(cwd, ':') as cwd, group_concat(session) as session, group_concat(hostname, ',') as hostname, count(*) as count FROM `history` AS h WHERE deleted_at is null GROUP BY command, exit ORDER BY timestamp DESC;

-- @id atuin.stats.day_of_week
-- @src crates/atuin-client/src/database.rs:1048-1058
-- @style sql_builder with a ?1 bind
-- @tags dynamic
-- @note Inspector stats: strftime('%w') over nanosecond timestamps (ROUND division), grouped.
-- @param ?1 'git status'
SELECT strftime('%w', ROUND(timestamp / 1000000000), 'unixepoch') AS day_of_week, count(1) as count FROM history WHERE (command = ?1) AND (deleted_at IS NULL) GROUP BY day_of_week;

-- @id atuin.stats.duration_over_time
-- @src crates/atuin-client/src/database.rs:1062-1074
-- @style sql_builder with a ?1 bind
-- @tags dynamic
-- @note Monthly average duration: strftime month bucket, avg, HAVING on the aggregate alias.
-- @param ?1 'cargo build --release'
SELECT strftime('01-%m-%Y', ROUND(timestamp / 1000000000), 'unixepoch') AS month_year, avg(duration) as duration FROM history WHERE (command = ?1) AND (deleted_at IS NULL) AND (duration >= 0) GROUP BY month_year HAVING duration > 0;

-- @id atuin.history.get_dups
-- @src crates/atuin-client/src/database.rs:1115-1135
-- @style ?N positional
-- @tags dynamic
-- @note `atuin history dedup`: ROW_NUMBER() OVER (PARTITION BY command, cwd, hostname ORDER BY timestamp DESC) over the whole table, filter rn.
-- @param ?1 3
-- @param ?2 1720000000000000000
SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind FROM (
    SELECT id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind, ROW_NUMBER()
      OVER (PARTITION BY command, cwd, hostname ORDER BY timestamp DESC)
      AS rn
      FROM history
    ) sub
  WHERE rn > ?1 and timestamp < ?2;

-- @id atuin.store.first_gap
-- @src crates/atuin-client/src/record/sqlite_store.rs:408-425
-- @style ?N positional
-- @tags hotpath
-- @note Sync: smallest missing idx >= from: UNION of idx+1 and the start, filtered by NOT IN a correlated-free subquery, min().
-- @param ?1 '0190c1e2-7a1b-7c3d-8e4f-111111111111'
-- @param ?2 'history'
-- @param ?3 100
select min(idx) from (
     select idx + 1 as idx from store where host = ?1 and tag = ?2 and idx >= ?3
     union
     select ?3
 ) as candidates
 where idx not in (select idx from store where host = ?1 and tag = ?2 and idx >= ?3);

-- @id atuin.store.next
-- @src crates/atuin-client/src/record/sqlite_store.rs:449-470
-- @style ?N positional
-- @tags hotpath
-- @note Sync download page: range on the (host, tag, idx) unique index, top-N.
-- @param ?1 9000
-- @param ?2 '0190c1e2-7a1b-7c3d-8e4f-111111111111'
-- @param ?3 'history'
-- @param ?4 100
select id, idx, host, tag, timestamp, version, data, cek from store where idx >= ?1 and host = ?2 and tag = ?3 order by idx asc limit ?4;

-- @id atuin.store.last
-- @src crates/atuin-client/src/record/sqlite_store.rs:347-360
-- @style ?N positional
-- @tags hot-small,hotpath
-- @note Tail of a (host, tag) series, top-1 by idx.
-- @param ?1 '0190c1e2-7a1b-7c3d-8e4f-111111111111'
-- @param ?2 'kv'
select id, idx, host, tag, timestamp, version, data, cek from store where host=?1 and tag=?2 order by idx desc limit 1;

-- @id atuin.store.status
-- @src crates/atuin-client/src/record/sqlite_store.rs:494-500
-- @style no params
-- @tags hotpath
-- @note Sync status: max(idx) per (host, tag) over the whole store.
select host, tag, max(idx) from store group by host, tag;

-- @id atuin.store.save
-- @src crates/atuin-client/src/record/sqlite_store.rs:140-163
-- @style ?N positional
-- @tags hot-small,hotpath
-- @note Insert-or-ignore of one encrypted record.
-- @param ?1 '019a5b2c-0000-7000-8000-00000000abcd'
-- @param ?2 10670
-- @param ?3 '0190c1e2-7a1b-7c3d-8e4f-111111111111'
-- @param ?4 'history'
-- @param ?5 1762400100000000000
-- @param ?6 'v0'
-- @param ?7 x'76340000000000000000000000000000'
-- @param ?8 x'00000000000000000000000000000000'
insert or ignore into store(id, idx, host, tag, timestamp, version, data, cek)
    values(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8);
