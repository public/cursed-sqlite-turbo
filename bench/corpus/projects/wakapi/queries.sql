-- Wakapi (muety/wakapi @ aba6a44, MIT). GORM v1.31.2 + glebarez/sqlite v1.11 (modernc SQLite).
-- Hand-reconstructed from the repositories at the pinned SHA (Go is not installed, so GORM's SQL printer was not run).
-- The text follows GORM's builder rules: struct conditions render as `table`.`col` = ?, string conditions verbatim
-- (OR conditions wrapped in parentheses), Order/Joins/Select strings verbatim, single-identifier Group() quoted,
-- First() appends `,table`.`id`, Limit() binds LIMIT ?, IN ? expands to (?,?,...), Raw named args (@name) become ?.
-- Several statements are cross-checked against GORM's own SQL log quoted in muety/wakapi#983 (SQLite, 2026-10-05).
-- ? placeholders are numbered ?N in order. Times are Unix epoch ms; today starts at 1790985600000 and "now" is
-- 1791043200000 (16:00 UTC). 'alice' is the heavy user (40 % of heartbeats, three years of history, WakaTime imports).

-- @id wakapi.activity.summaries_per_day
-- @src repositories/summary.go:127-153
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,hot-small,analytics,cpu-evidence,dynamic
-- @note Activity chart (services/activity.go:78-106) still calls Retrieve once per day for ~371 days; each call starts with this summaries lookup on idx_time_summary_user. https://github.com/muety/wakapi/issues/974
-- @param ?1 'alice'
-- @param ?2 1788393600000
-- @param ?3 1788480000000
SELECT * FROM `summaries` WHERE user_id = ?1 AND from_time >= ?2 AND to_time <= ?3 ORDER BY from_time asc;

-- @id wakapi.activity.populate_items_per_day
-- @src repositories/summary.go:212-244
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,analytics,cpu-evidence,dynamic
-- @note Fixed populateItems (9f3d7d6 replaced the CROSS JOIN by INNER JOIN, d4b470f added idx_summary_item_summary): runs once per chart day after the summaries lookup. https://github.com/muety/wakapi/issues/974
-- @param ?1 0
-- @param ?2 'alice'
-- @param ?3 1788393600000
-- @param ?4 1788480000000
SELECT summary_items.* FROM `summary_items` inner join summaries on summary_items.summary_id = summaries.id WHERE num_heartbeats > ?1 AND user_id = ?2 AND from_time >= ?3 AND to_time <= ?4;

-- @id wakapi.activity.populate_items_per_day_cross_join
-- @src repositories/summary.go:212-244
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags analytics,cpu-evidence,dynamic
-- @note The pre-fix populateItems that #974 measured: CROSS JOIN pins summary_items as the outer loop, so every chart day scans all of summary_items (x371 per chart; 15-30 s with 30k items on a Celeron). https://github.com/muety/wakapi/issues/974
-- @modified text of populateItems before 9f3d7d6 (repositories/summary.go at 8143ca1: Joins("cross join summaries").Where("summary_items.summary_id = summaries.id")); the pinned SHA uses the inner join above. Kept to measure the CROSS JOIN plan against the current schema (which now has idx_summary_item_summary)
-- @param ?1 0
-- @param ?2 'alice'
-- @param ?3 1788393600000
-- @param ?4 1788480000000
SELECT summary_items.* FROM `summary_items` cross join summaries WHERE summary_items.summary_id = summaries.id AND num_heartbeats > ?1 AND user_id = ?2 AND from_time >= ?3 AND to_time <= ?4;

-- @id wakapi.activity.live_durations_per_day
-- @src repositories/duration.go:67-82
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,cpu-evidence,dynamic
-- @note getMissingIntervals -> DurationService.getCached for a chart day that has no aligned summary (the #975 time-zone case): one durations range read per day on idx_time_duration_user. https://github.com/muety/wakapi/issues/974
-- @param ?1 'alice'
-- @param ?2 1788361200000
-- @param ?3 1788447600000
SELECT * FROM `durations` WHERE `durations`.`user_id` = ?1 AND time >= ?2 AND time < ?3 ORDER BY time asc;

-- @id wakapi.summary.all_time_summaries
-- @src repositories/summary.go:127-153
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,analytics,cpu-evidence,dynamic
-- @note /summary?interval=any: every persisted summary of the user (GORM log in #983: 27 ms, 4736 rows); merged in Go. https://github.com/muety/wakapi/issues/983
-- @param ?1 'alice'
-- @param ?2 0
-- @param ?3 1791043200000
SELECT * FROM `summaries` WHERE user_id = ?1 AND from_time >= ?2 AND to_time <= ?3 ORDER BY from_time asc;

-- @id wakapi.summary.all_time_populate_items
-- @src repositories/summary.go:212-244
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,analytics,cpu-evidence,dynamic
-- @note populateItems for the all-time summary: join of every summary item of the user (#983 log: 237 ms, 28831 rows). https://github.com/muety/wakapi/issues/983
-- @param ?1 0
-- @param ?2 'alice'
-- @param ?3 0
-- @param ?4 1791043200000
SELECT summary_items.* FROM `summary_items` inner join summaries on summary_items.summary_id = summaries.id WHERE num_heartbeats > ?1 AND user_id = ?2 AND from_time >= ?3 AND to_time <= ?4;

-- @id wakapi.summary.all_time_durations
-- @src repositories/duration.go:67-82
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,cpu-evidence,dynamic
-- @note All-time summary falls back to cached durations for the span not covered by summaries (#983 log: 742 ms, 26640 rows). https://github.com/muety/wakapi/issues/983
-- @param ?1 'alice'
-- @param ?2 0
-- @param ?3 1790899200000
SELECT * FROM `durations` WHERE `durations`.`user_id` = ?1 AND time >= ?2 AND time < ?3 ORDER BY time asc;

-- @id wakapi.summary.project_filter_durations
-- @src repositories/duration.go:67-82; repositories/base.go:170-181
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,analytics,cpu-evidence,dynamic
-- @note /summary?interval=any&project=X: filtered queries bypass persisted summaries, so the whole user range of durations is read and filtered by project (index has no project column); #983 took ~30 s end to end with 420k heartbeats. https://github.com/muety/wakapi/issues/983
-- @param ?1 'alice'
-- @param ?2 0
-- @param ?3 1791043200000
-- @param ?4 'core-sdk'
SELECT * FROM `durations` WHERE `durations`.`user_id` = ?1 AND time >= ?2 AND time < ?3 AND project in (?4) ORDER BY time asc;

-- @id wakapi.summary.today_heartbeats_excluding
-- @src repositories/heartbeat.go:89-125,369-389
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,dynamic
-- @note Live 'today' summary: the user's heartbeats since the last duration, excluding AI-agent app heartbeats; the OR filter (heartbeat_exclusions) is applied on top of idx_time_user_project_lang.
-- @param ?1 'alice'
-- @param ?2 1790985600000
-- @param ?3 1791043200000
-- @param ?4 'app'
-- @param ?5 'ai coding'
SELECT * FROM `heartbeats` WHERE `heartbeats`.`user_id` = ?1 AND time >= ?2 AND time < ?3 AND (COALESCE(type, '') != ?4 OR COALESCE(category, '') != ?5) ORDER BY time asc;

-- @id wakapi.summary.user_project_stats
-- @src repositories/heartbeat.go:310-353
-- @style GORM Raw with sql.Named(@userid, @from, @to); GORM rewrites the named args to ? in order, @userid appears twice
-- @tags hotpath,analytics,cpu-evidence,dynamic
-- @note Projects page / all-time pre-warm: group by (project, language) then window sums, min/max and row_number per project over every heartbeat of the user. Code comment: ~7 s for ~500k heartbeats; #983 log: 525 ms. https://github.com/muety/wakapi/issues/983
-- @param ?1 'alice'
-- @param ?2 -62135596800000
-- @param ?3 1791072000000
-- @param ?4 'alice'
with lang_grouped as (select project, language, count(*) as lang_cnt, min(time) as lang_min, max(time) as lang_max from heartbeats where user_id = ?1 and project != '' and time between ?2 and ?3 and language is not null and language != '' group by project, language), ranked as (select project, language, lang_cnt, lang_min, lang_max, sum(lang_cnt) over (partition by project) as total_cnt, min(lang_min) over (partition by project) as overall_first, max(lang_max) over (partition by project) as overall_last, row_number() over (partition by project order by lang_cnt desc) as rn from lang_grouped) select project, overall_first as first, overall_last as last, total_cnt as count, language as top_language, ?4 as user_id from ranked where rn = 1;

-- @id wakapi.heartbeat.latest_by_user
-- @src repositories/heartbeat.go:37-48
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,hot-small
-- @note Latest heartbeat of a user (status bar / badge); reverse range on idx_time_user_project_lang.
-- @param ?1 'alice'
-- @param ?2 1
SELECT * FROM `heartbeats` WHERE `heartbeats`.`user_id` = ?1 ORDER BY time desc LIMIT ?2;

-- @id wakapi.heartbeat.latest_by_project
-- @src repositories/heartbeat.go:188-199
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,cpu-evidence,dynamic
-- @note Latest heartbeat per project (heartbeats API / project status). The top query in the MySQL slow log of #990 (several minutes before idx_user_project_time existed, ~400 ms after). https://github.com/muety/wakapi/issues/990
-- @param ?1 'alice'
-- @param ?2 'core-bot'
-- @param ?3 1
SELECT * FROM `heartbeats` WHERE `heartbeats`.`user_id` = ?1 AND project in (?2) ORDER BY time desc LIMIT ?3;

-- @id wakapi.heartbeat.latest_by_origin
-- @src repositories/heartbeat.go:50-64
-- @style ? positional (GORM chain, sqlite dialect)
-- @note Settings > import: latest heartbeat imported from WakaTime. origin has no index, so the plan walks the user's heartbeats newest-first until it meets an imported one (most of alice's recent history).
-- @param ?1 'alice'
-- @param ?2 'wakatime'
-- @param ?3 1
SELECT * FROM `heartbeats` WHERE `heartbeats`.`user_id` = ?1 AND `heartbeats`.`origin` = ?2 ORDER BY time desc LIMIT ?3;

-- @id wakapi.heartbeat.count_by_user
-- @src repositories/heartbeat.go:236-245
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags analytics
-- @note Heartbeat count of one user (settings / data export page).
-- @param ?1 'alice'
SELECT count(*) FROM `heartbeats` WHERE `heartbeats`.`user_id` = ?1;

-- @id wakapi.heartbeat.count_by_users
-- @src repositories/heartbeat.go:247-269
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags analytics,cpu-evidence,dynamic
-- @note Counts for a batch of users (summary pre-warm, admin); #983 log: 117 ms for 4 users. https://github.com/muety/wakapi/issues/983
-- @param ?1 'dev0047'
-- @param ?2 'alice'
-- @param ?3 'bob'
-- @param ?4 'dev0107'
SELECT user_id as `user`, count(id) as `count` FROM `heartbeats` WHERE user_id in (?1,?2,?3,?4) GROUP BY `user`;

-- @id wakapi.heartbeat.count_all
-- @src repositories/heartbeat.go:219-234
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags analytics
-- @note Total heartbeat count for the metrics endpoint / admin page (SQLite has no approximate path).
SELECT count(*) FROM `heartbeats`;

-- @id wakapi.heartbeat.entity_set_projects
-- @src repositories/heartbeat.go:271-281
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,analytics,cpu-evidence
-- @note Distinct projects of a user (filter dropdowns); #983 log: 67 ms, 188 rows. https://github.com/muety/wakapi/issues/983
-- @param ?1 'alice'
SELECT DISTINCT `project` FROM `heartbeats` WHERE `heartbeats`.`user_id` = ?1;

-- @id wakapi.heartbeat.entity_set_machines
-- @src repositories/heartbeat.go:271-281
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,analytics
-- @note Distinct machines of a user (filter dropdown): machine is not in a user-leading index, so every heartbeat row of the user is fetched.
-- @param ?1 'alice'
SELECT DISTINCT `machine` FROM `heartbeats` WHERE `heartbeats`.`user_id` = ?1;

-- @id wakapi.settings.user_agents
-- @src repositories/heartbeat.go:355-367
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags analytics
-- @note Settings > user agents: group the user's heartbeats by (user_agent, os, editor, ai_model) with first/last seen.
-- @param ?1 'alice'
SELECT user_agent as value, operating_system as os, editor, ai_model, min(time) as first_seen, max(time) as last_seen FROM `heartbeats` WHERE `heartbeats`.`user_id` = ?1 AND NOT user_agent = '' GROUP BY user_agent, operating_system, editor, ai_model;

-- @id wakapi.users.last_active_after
-- @src repositories/user.go:85-103
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags analytics,cpu-evidence
-- @note Users active in the last week (summary-cache pre-warm, leaderboard, reports): max(time) per user over the whole heartbeats table, filtered afterwards. #983 log: 2945 ms on 420k heartbeats. https://github.com/muety/wakapi/issues/983
-- @param ?1 1790438400000
SELECT user as `id` FROM (SELECT user_id as `user`, max(time) as time FROM `heartbeats` GROUP BY `user_id`) as q WHERE time >= ?1;

-- @id wakapi.aggregation.first_heartbeat_all
-- @src repositories/heartbeat.go:201-205
-- @style GORM Raw, no binds
-- @tags analytics,cpu-evidence
-- @note Nightly aggregation start (services/aggregation.go:91): first heartbeat per user through the user_heartbeats_range view (users LEFT JOIN heartbeats GROUP BY users.id); aggregation CPU spikes in https://github.com/muety/wakapi/issues/976
select user_id as user, first as time from user_heartbeats_range;

-- @id wakapi.aggregation.range_by_user
-- @src repositories/heartbeat.go:213-217
-- @style GORM Raw, ? positional
-- @tags hotpath,analytics
-- @note First/last heartbeat of one user through the same view; the WHERE must be pushed into the grouped view to avoid aggregating all users.
-- @param ?1 'alice'
select user_id as user, first, last from user_heartbeats_range where user_id = ?1;

-- @id wakapi.aggregation.last_summary_by_user
-- @src repositories/summary.go:155-163
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags analytics
-- @note Nightly aggregation: latest persisted summary end per user (users LEFT JOIN summaries GROUP BY users.id).
SELECT users.id as `user`, max(to_time) as time FROM `users` left join summaries on users.id = summaries.user_id GROUP BY `users`.`id`;

-- @id wakapi.aggregation.regenerate_durations_stream
-- @src repositories/heartbeat.go:141-155
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags cpu-evidence
-- @note Durations regeneration (forceAll during aggregation) streams every heartbeat of a user in time order and rebuilds durations; the aggregation CPU spikes and pool exhaustion of https://github.com/muety/wakapi/issues/976
-- @param ?1 'bob'
SELECT * FROM `heartbeats` WHERE `heartbeats`.`user_id` = ?1 ORDER BY time asc;

-- @id wakapi.housekeeping.delete_heartbeats_before
-- @src repositories/heartbeat.go:300-308
-- @style ? positional (GORM chain, sqlite dialect)
-- @note Data retention (services/housekeeping.go:60): delete a user's heartbeats older than the retention cutoff (2 years here); 10 secondary indexes to maintain.
-- @param ?1 1727913600000
-- @param ?2 'alice'
DELETE FROM `heartbeats` WHERE time <= ?1 AND user_id = ?2;

-- @id wakapi.duration.delete_after
-- @src repositories/duration.go:114-125,137-146
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath
-- @note Heartbeat ingest invalidates cached durations that end after the new heartbeat; the SQLite branch's time + duration arithmetic is not indexable, so a 12 h lower bound narrows the range.
-- @param ?1 'alice'
-- @param ?2 1790992800000
-- @param ?3 1791036000000
DELETE FROM `durations` WHERE user_id = ?1 AND time >= ?2 AND time + (duration / 1000000) >= ?3;

-- @id wakapi.duration.latest_by_user
-- @src repositories/duration.go:84-90
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,hot-small
-- @note Latest cached duration of a user (where live computation resumes); GORM First() appends the primary key to ORDER BY.
-- @param ?1 'alice'
-- @param ?2 1
SELECT * FROM `durations` WHERE `durations`.`user_id` = ?1 ORDER BY time desc,`durations`.`id` LIMIT ?2;

-- @id wakapi.heartbeat.insert_batch
-- @src repositories/heartbeat.go:33-35; repositories/base.go:94-129
-- @style ? positional, GORM batch Create, one placeholder group per row
-- @tags hotpath,hot-small,batch,dynamic
-- @note Heartbeat ingest (POST /api/heartbeats): chunked multi-row INSERT with OnConflict{DoNothing} on the unique hash and RETURNING id (glebarez/sqlite); 10 secondary indexes per row.
-- @param ?1 'alice'
-- @param ?2 '/home/alice/dev/core-sdk/src/client_7.rs'
-- @param ?3 'file'
-- @param ?4 'coding'
-- @param ?5 'core-sdk'
-- @param ?6 'main'
-- @param ?7 'Rust'
-- @param ?8 0
-- @param ?9 'Neovim'
-- @param ?10 ''
-- @param ?11 'Linux'
-- @param ?12 'machine-1-0'
-- @param ?13 'wakatime/v1.102.1 (linux-6.8.0-45-generic-x86_64) go1.22.5 neovim/0.10.1 vim-wakatime/11.2.0'
-- @param ?14 1791043201000
-- @param ?15 'f00dcafe000000001'
-- @param ?16 ''
-- @param ?17 ''
-- @param ?18 1791043201500
-- @param ?19 412
-- @param ?20 88
-- @param ?21 17
-- @param ?22 0
-- @param ?23 0
-- @param ?24 1
-- @param ?25 0
-- @param ?26 ''
-- @param ?27 0
-- @param ?28 0
-- @param ?29 0
-- @param ?30 0
-- @param ?31 'alice'
-- @param ?32 '/home/alice/dev/core-sdk/src/client_7.rs'
-- @param ?33 'file'
-- @param ?34 'coding'
-- @param ?35 'core-sdk'
-- @param ?36 'main'
-- @param ?37 'Rust'
-- @param ?38 1
-- @param ?39 'Neovim'
-- @param ?40 ''
-- @param ?41 'Linux'
-- @param ?42 'machine-1-0'
-- @param ?43 'wakatime/v1.102.1 (linux-6.8.0-45-generic-x86_64) go1.22.5 neovim/0.10.1 vim-wakatime/11.2.0'
-- @param ?44 1791043261000
-- @param ?45 'f00dcafe000000002'
-- @param ?46 ''
-- @param ?47 ''
-- @param ?48 1791043261500
-- @param ?49 415
-- @param ?50 91
-- @param ?51 4
-- @param ?52 0
-- @param ?53 3
-- @param ?54 1
-- @param ?55 0
-- @param ?56 ''
-- @param ?57 0
-- @param ?58 0
-- @param ?59 0
-- @param ?60 0
INSERT INTO `heartbeats` (`user_id`,`entity`,`type`,`category`,`project`,`branch`,`language`,`is_write`,`editor`,`ai_model`,`operating_system`,`machine`,`user_agent`,`time`,`hash`,`origin`,`origin_id`,`created_at`,`lines`,`line_no`,`cursor_pos`,`line_deletions`,`line_additions`,`project_root_count`,`ai_line_changes`,`ai_session`,`ai_input_tokens`,`ai_output_tokens`,`ai_prompt_length`,`human_line_changes`) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21,?22,?23,?24,?25,?26,?27,?28,?29,?30),(?31,?32,?33,?34,?35,?36,?37,?38,?39,?40,?41,?42,?43,?44,?45,?46,?47,?48,?49,?50,?51,?52,?53,?54,?55,?56,?57,?58,?59,?60) ON CONFLICT DO NOTHING RETURNING `id`;

-- @id wakapi.leaderboard.page_total
-- @src repositories/leaderboard.go:56-73,111-119; utils/db.go:38-43
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,analytics,dynamic
-- @note Public leaderboard page (7 days, overall): rank() window partitioned by lower(key) over the interval's rows, paged by rank in the outer query.
-- @param ?1 '7_days'
-- @param ?2 'last_7_days'
-- @param ?3 'Last 7 Days'
-- @param ?4 100
SELECT * FROM (SELECT *, rank() over (partition by lower("key") order by total desc) as "rank" FROM `leaderboard_items` WHERE "interval" in (?1,?2,?3) AND "by" is null) as ranked WHERE "rank" <= ?4;

-- @id wakapi.leaderboard.user_by_language
-- @src repositories/leaderboard.go:75-90; utils/db.go:38-43
-- @style ? positional (GORM chain, sqlite dialect)
-- @tags hotpath,analytics,dynamic
-- @note A user's rank per language (by = SummaryLanguage): the window runs over every user's language rows before the outer user filter.
-- @param ?1 '30_days'
-- @param ?2 'last_30_days'
-- @param ?3 'Last 30 Days'
-- @param ?4 1
-- @param ?5 'alice'
SELECT * FROM (SELECT *, rank() over (partition by lower("key") order by total desc) as "rank" FROM `leaderboard_items` WHERE "interval" in (?1,?2,?3) AND "by" = ?4) as ranked WHERE user_id = ?5;
