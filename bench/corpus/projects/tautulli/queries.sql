-- Tautulli (Tautulli/Tautulli @ c0f0120, GPL-3.0). Raw SQL built with Python %-formatting and the DataTables helper
-- (plexpy/datatables.py), executed through python sqlite3 with ? placeholders (numbered ?N here in argument order).
-- Reconstructed by hand from the pinned source text: the app could not be imported and run to capture its SQL in this
-- environment, so each statement follows the string building for one representative request (default config:
-- GROUP_HISTORY_TABLES=1, HISTORY_TABLE_ACTIVITY=1, WATCHED_MARKER=3, 85 % thresholds; 3 archived users, 1 archived
-- library). "Now" is 1790000000; literal timestamps are now minus the range, as helpers.timestamp() would give.
-- Graph queries bucket by date(..., 'localtime'), so their bucket edges depend on the machine's time zone (tagged wallclock).

-- @id tautulli.history.page_bound_scan
-- @src plexpy/datafactory.py:88-153
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,cpu-evidence
-- @note History page draw, step 1 (build_history_page_bound): walk the started index newest-first with a NOT EXISTS 'last row of its group' anti-join over the reference_id index to find the date of the 25th group, inside a 25000-row window. Added on nightly as the follow-up to https://github.com/Tautulli/Tautulli/issues/1962 (20 s history page at 350k rows).
-- @param ?1 1300922
-- @param ?2 1308841
-- @param ?3 1316760
-- @param ?4 6
-- @param ?5 25
SELECT MIN(started) AS cutoff, COUNT(*) AS found
FROM (SELECT started
FROM session_history
LEFT OUTER JOIN session_history_metadata ON session_history_metadata.id = session_history.id
WHERE session_history.user_id NOT IN (?1,?2,?3) AND session_history.section_id NOT IN (?4) AND NOT EXISTS (SELECT 1
FROM session_history AS g
WHERE g.reference_id = session_history.reference_id AND (g.started > session_history.started OR (g.started = session_history.started AND g.id > session_history.id))) AND session_history.started >= (SELECT MIN(started)
FROM (SELECT started
FROM session_history
ORDER BY started DESC
LIMIT 25000))
ORDER BY started DESC
LIMIT ?5);

-- @id tautulli.history.filtered_count
-- @src plexpy/datafactory.py:418-458; plexpy/datatables.py:122-127
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,cpu-evidence
-- @note History draw, step 2: the 'cheap' recordsFiltered count, COUNT(DISTINCT reference_id) over all history plus the live sessions, run on every page change. Replaced the COUNT(*) over the grouped join from https://github.com/Tautulli/Tautulli/pull/2728/https://github.com/Tautulli/Tautulli/pull/2752.
-- @param ?1 1300922
-- @param ?2 1308841
-- @param ?3 1316760
-- @param ?4 6
-- @param ?5 1300922
-- @param ?6 1308841
-- @param ?7 1316760
-- @param ?8 6
SELECT (SELECT c
FROM (SELECT COUNT(DISTINCT session_history.reference_id) AS c
FROM session_history
WHERE session_history.user_id NOT IN (?1,?2,?3) AND session_history.section_id NOT IN (?4))) + (SELECT c
FROM (SELECT COUNT(DISTINCT session_key) AS c, (CASE WHEN live = 1 THEN 'live' ELSE media_type END) AS media_type_live
FROM sessions
WHERE user_id NOT IN (?5,?6,?7) AND section_id NOT IN (?8))) AS filtered_count;

-- @id tautulli.history.page1_grouped_bounded
-- @src plexpy/datafactory.py:241-500; plexpy/datatables.py:38-130
-- @modified strftime('%s', 'now') in the live-sessions branch pinned to 1790000000, data.sql's \"now\", so play_duration and the hash stop drifting with the clock
-- @style ? positional (python sqlite3); string-built by DataTables.ssp_query from column/join/where lists
-- @tags hotpath,dynamic,cpu-evidence
-- @note History page 1 (grouped plays, live sessions UNION ALL'd in, date DESC): the 55-column GROUP BY reference_id over session_history LEFT JOIN users/metadata, restricted by the page bound's reference_id IN (...) subquery; outer ORDER BY date COLLATE NOCASE + LIMIT/OFFSET. The query from https://github.com/Tautulli/Tautulli/issues/1962, as it is after https://github.com/Tautulli/Tautulli/pull/2728.
-- @param ?1 1300922
-- @param ?2 1308841
-- @param ?3 1316760
-- @param ?4 6
-- @param ?5 1300922
-- @param ?6 1308841
-- @param ?7 1316760
-- @param ?8 6
-- @param ?9 1789982381
-- @param ?10 1300922
-- @param ?11 1308841
-- @param ?12 1316760
-- @param ?13 6
-- @param ?14 25
-- @param ?15 0
SELECT *
FROM (SELECT session_history.reference_id, session_history.id AS row_id, MAX(started) AS date, MIN(started) AS started, MAX(stopped) AS stopped, SUM(CASE WHEN stopped > 0 THEN (stopped - started) ELSE 0 END) - SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS play_duration, SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS paused_counter, session_history.view_offset, session_history.user_id, session_history.user, (CASE WHEN users.friendly_name IS NULL OR TRIM(users.friendly_name) = '' THEN users.username ELSE users.friendly_name END) AS friendly_name, users.thumb AS user_thumb, users.custom_avatar_url AS custom_thumb, users.is_archived AS user_is_archived, (SELECT MAX(is_archived)
FROM library_sections
WHERE library_sections.section_id = session_history.section_id) AS library_is_archived, platform, product, player, ip_address, machine_id, location, secure, relayed, session_history.media_type, (CASE WHEN session_history.live = 1 THEN 'live' ELSE session_history.media_type END) AS media_type_live, session_history_metadata.rating_key, session_history_metadata.parent_rating_key, session_history_metadata.grandparent_rating_key, session_history_metadata.full_title, session_history_metadata.title, session_history_metadata.parent_title, session_history_metadata.grandparent_title, session_history_metadata.original_title, session_history_metadata.year, session_history_metadata.media_index, session_history_metadata.parent_media_index, session_history_metadata.thumb, session_history_metadata.parent_thumb, session_history_metadata.grandparent_thumb, session_history.live, session_history_metadata.added_at, session_history_metadata.originally_available_at, session_history_metadata.guid, MAX((CASE WHEN (view_offset IS NULL OR view_offset = '') THEN 0.1 ELSE view_offset * 1.0 END) / (CASE WHEN session_history_metadata.id IS NULL THEN NULL WHEN (session_history_metadata.duration IS NULL OR session_history_metadata.duration = '') THEN 1.0 ELSE session_history_metadata.duration * 1.0 END) * 100) AS percent_complete, session_history_metadata.duration, session_history_metadata.marker_credits_first, session_history_metadata.marker_credits_final, session_history.transcode_decision, COUNT(*) AS group_count, GROUP_CONCAT(session_history.id) AS group_ids, NULL AS state, NULL AS session_key
FROM session_history
LEFT OUTER JOIN users ON session_history.user_id = users.user_id
LEFT OUTER JOIN session_history_metadata ON session_history.id = session_history_metadata.id
WHERE session_history.user_id NOT IN (?1,?2,?3) AND session_history.section_id NOT IN (?4) AND session_history.reference_id IN (SELECT reference_id
FROM session_history
LEFT OUTER JOIN session_history_metadata ON session_history_metadata.id = session_history.id
WHERE session_history.user_id NOT IN (?5,?6,?7) AND session_history.section_id NOT IN (?8) AND started >= ?9)
GROUP BY session_history.reference_id
UNION ALL SELECT NULL AS reference_id, NULL AS row_id, started AS date, started, stopped, SUM(CASE WHEN stopped > 0 THEN (stopped - started) ELSE (1790000000 - started) END) - SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS play_duration, SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS paused_counter, view_offset, user_id, user, (CASE WHEN friendly_name IS NULL OR TRIM(friendly_name) = '' THEN user ELSE friendly_name END) AS friendly_name, NULL AS user_thumb, NULL AS custom_thumb, (SELECT is_archived
FROM users
WHERE users.user_id = sessions.user_id) AS user_is_archived, (SELECT MAX(is_archived)
FROM library_sections
WHERE library_sections.section_id = sessions.section_id) AS library_is_archived, platform, product, player, ip_address, machine_id, location, secure, relayed, media_type, (CASE WHEN live = 1 THEN 'live' ELSE media_type END) AS media_type_live, rating_key, parent_rating_key, grandparent_rating_key, full_title, title, parent_title, grandparent_title, original_title, year, media_index, parent_media_index, thumb, parent_thumb, grandparent_thumb, live, added_at, originally_available_at, guid, MAX((CASE WHEN (view_offset IS NULL OR view_offset = '') THEN 0.1 ELSE view_offset * 1.0 END) / (CASE WHEN (duration IS NULL OR duration = '') THEN 1.0 ELSE duration * 1.0 END) * 100) AS percent_complete, duration, NULL AS marker_credits_first, NULL AS marker_credits_final, transcode_decision, NULL AS group_count, NULL AS group_ids, state, session_key
FROM sessions
WHERE user_id NOT IN (?10,?11,?12) AND section_id NOT IN (?13)
GROUP BY session_key)
ORDER BY date COLLATE NOCASE DESC
LIMIT ?14 OFFSET ?15;

-- @id tautulli.history.sorted_by_duration_unbounded
-- @src plexpy/datafactory.py:241-500; plexpy/datatables.py:38-130
-- @modified strftime('%s', 'now') in the live-sessions branch pinned to 1790000000, data.sql's \"now\", so play_duration and the hash stop drifting with the clock
-- @style ? positional (python sqlite3); string-built by DataTables.ssp_query from column/join/where lists
-- @tags hotpath,dynamic,cpu-evidence
-- @note History sorted by play duration: no page bound applies (the order is not a run of the started index), so every history row is joined, grouped by reference_id and sorted to return 25 rows. This is the https://github.com/Tautulli/Tautulli/issues/1962 worst case (20 s at 350k rows, 70 s reported for the home stats on a 7950X3D).
-- @param ?1 1300922
-- @param ?2 1308841
-- @param ?3 1316760
-- @param ?4 6
-- @param ?5 1300922
-- @param ?6 1308841
-- @param ?7 1316760
-- @param ?8 6
-- @param ?9 25
-- @param ?10 0
SELECT *
FROM (SELECT session_history.reference_id, session_history.id AS row_id, MAX(started) AS date, MIN(started) AS started, MAX(stopped) AS stopped, SUM(CASE WHEN stopped > 0 THEN (stopped - started) ELSE 0 END) - SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS play_duration, SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS paused_counter, session_history.view_offset, session_history.user_id, session_history.user, (CASE WHEN users.friendly_name IS NULL OR TRIM(users.friendly_name) = '' THEN users.username ELSE users.friendly_name END) AS friendly_name, users.thumb AS user_thumb, users.custom_avatar_url AS custom_thumb, users.is_archived AS user_is_archived, (SELECT MAX(is_archived)
FROM library_sections
WHERE library_sections.section_id = session_history.section_id) AS library_is_archived, platform, product, player, ip_address, machine_id, location, secure, relayed, session_history.media_type, (CASE WHEN session_history.live = 1 THEN 'live' ELSE session_history.media_type END) AS media_type_live, session_history_metadata.rating_key, session_history_metadata.parent_rating_key, session_history_metadata.grandparent_rating_key, session_history_metadata.full_title, session_history_metadata.title, session_history_metadata.parent_title, session_history_metadata.grandparent_title, session_history_metadata.original_title, session_history_metadata.year, session_history_metadata.media_index, session_history_metadata.parent_media_index, session_history_metadata.thumb, session_history_metadata.parent_thumb, session_history_metadata.grandparent_thumb, session_history.live, session_history_metadata.added_at, session_history_metadata.originally_available_at, session_history_metadata.guid, MAX((CASE WHEN (view_offset IS NULL OR view_offset = '') THEN 0.1 ELSE view_offset * 1.0 END) / (CASE WHEN session_history_metadata.id IS NULL THEN NULL WHEN (session_history_metadata.duration IS NULL OR session_history_metadata.duration = '') THEN 1.0 ELSE session_history_metadata.duration * 1.0 END) * 100) AS percent_complete, session_history_metadata.duration, session_history_metadata.marker_credits_first, session_history_metadata.marker_credits_final, session_history.transcode_decision, COUNT(*) AS group_count, GROUP_CONCAT(session_history.id) AS group_ids, NULL AS state, NULL AS session_key
FROM session_history
LEFT OUTER JOIN users ON session_history.user_id = users.user_id
LEFT OUTER JOIN session_history_metadata ON session_history.id = session_history_metadata.id
WHERE session_history.user_id NOT IN (?1,?2,?3) AND session_history.section_id NOT IN (?4)
GROUP BY session_history.reference_id
UNION ALL SELECT NULL AS reference_id, NULL AS row_id, started AS date, started, stopped, SUM(CASE WHEN stopped > 0 THEN (stopped - started) ELSE (1790000000 - started) END) - SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS play_duration, SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS paused_counter, view_offset, user_id, user, (CASE WHEN friendly_name IS NULL OR TRIM(friendly_name) = '' THEN user ELSE friendly_name END) AS friendly_name, NULL AS user_thumb, NULL AS custom_thumb, (SELECT is_archived
FROM users
WHERE users.user_id = sessions.user_id) AS user_is_archived, (SELECT MAX(is_archived)
FROM library_sections
WHERE library_sections.section_id = sessions.section_id) AS library_is_archived, platform, product, player, ip_address, machine_id, location, secure, relayed, media_type, (CASE WHEN live = 1 THEN 'live' ELSE media_type END) AS media_type_live, rating_key, parent_rating_key, grandparent_rating_key, full_title, title, parent_title, grandparent_title, original_title, year, media_index, parent_media_index, thumb, parent_thumb, grandparent_thumb, live, added_at, originally_available_at, guid, MAX((CASE WHEN (view_offset IS NULL OR view_offset = '') THEN 0.1 ELSE view_offset * 1.0 END) / (CASE WHEN (duration IS NULL OR duration = '') THEN 1.0 ELSE duration * 1.0 END) * 100) AS percent_complete, duration, NULL AS marker_credits_first, NULL AS marker_credits_final, transcode_decision, NULL AS group_count, NULL AS group_ids, state, session_key
FROM sessions
WHERE user_id NOT IN (?5,?6,?7) AND section_id NOT IN (?8)
GROUP BY session_key)
ORDER BY play_duration COLLATE NOCASE DESC
LIMIT ?9 OFFSET ?10;

-- @id tautulli.history.search_window_count
-- @src plexpy/datafactory.py:174-230,241-500; plexpy/datatables.py:131-148
-- @modified strftime('%s', 'now') in the live-sessions branch pinned to 1790000000, data.sql's \"now\", so play_duration and the hash stop drifting with the clock
-- @style ? positional (python sqlite3); string-built by DataTables.ssp_query from column/join/where lists
-- @tags hotpath,dynamic,cpu-evidence
-- @note History search box ('office'): a search bound prunes to reference_ids with a matching row (six-way LIKE OR over a 3-table join), then the grouped draw is filtered by the same LIKEs on the outer query and counted with COUNT(*) OVER () in the same pass (https://github.com/Tautulli/Tautulli/pull/2752). #2728 measured searches getting slower (+17 %) at 35k rows.
-- @param ?1 1300922
-- @param ?2 1308841
-- @param ?3 1316760
-- @param ?4 6
-- @param ?5 '%office%'
-- @param ?6 '%office%'
-- @param ?7 '%office%'
-- @param ?8 '%office%'
-- @param ?9 '%office%'
-- @param ?10 '%office%'
-- @param ?11 1300922
-- @param ?12 1308841
-- @param ?13 1316760
-- @param ?14 6
-- @param ?15 '%office%'
-- @param ?16 '%office%'
-- @param ?17 '%office%'
-- @param ?18 '%office%'
-- @param ?19 '%office%'
-- @param ?20 '%office%'
-- @param ?21 25
-- @param ?22 0
SELECT *, COUNT(*) OVER () AS __filtered_count
FROM (SELECT session_history.reference_id, session_history.id AS row_id, MAX(started) AS date, MIN(started) AS started, MAX(stopped) AS stopped, SUM(CASE WHEN stopped > 0 THEN (stopped - started) ELSE 0 END) - SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS play_duration, SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS paused_counter, session_history.view_offset, session_history.user_id, session_history.user, (CASE WHEN users.friendly_name IS NULL OR TRIM(users.friendly_name) = '' THEN users.username ELSE users.friendly_name END) AS friendly_name, users.thumb AS user_thumb, users.custom_avatar_url AS custom_thumb, users.is_archived AS user_is_archived, (SELECT MAX(is_archived)
FROM library_sections
WHERE library_sections.section_id = session_history.section_id) AS library_is_archived, platform, product, player, ip_address, machine_id, location, secure, relayed, session_history.media_type, (CASE WHEN session_history.live = 1 THEN 'live' ELSE session_history.media_type END) AS media_type_live, session_history_metadata.rating_key, session_history_metadata.parent_rating_key, session_history_metadata.grandparent_rating_key, session_history_metadata.full_title, session_history_metadata.title, session_history_metadata.parent_title, session_history_metadata.grandparent_title, session_history_metadata.original_title, session_history_metadata.year, session_history_metadata.media_index, session_history_metadata.parent_media_index, session_history_metadata.thumb, session_history_metadata.parent_thumb, session_history_metadata.grandparent_thumb, session_history.live, session_history_metadata.added_at, session_history_metadata.originally_available_at, session_history_metadata.guid, MAX((CASE WHEN (view_offset IS NULL OR view_offset = '') THEN 0.1 ELSE view_offset * 1.0 END) / (CASE WHEN session_history_metadata.id IS NULL THEN NULL WHEN (session_history_metadata.duration IS NULL OR session_history_metadata.duration = '') THEN 1.0 ELSE session_history_metadata.duration * 1.0 END) * 100) AS percent_complete, session_history_metadata.duration, session_history_metadata.marker_credits_first, session_history_metadata.marker_credits_final, session_history.transcode_decision, COUNT(*) AS group_count, GROUP_CONCAT(session_history.id) AS group_ids, NULL AS state, NULL AS session_key
FROM session_history
LEFT OUTER JOIN users ON session_history.user_id = users.user_id
LEFT OUTER JOIN session_history_metadata ON session_history.id = session_history_metadata.id
WHERE session_history.user_id NOT IN (?1,?2,?3) AND session_history.section_id NOT IN (?4) AND session_history.reference_id IN (SELECT session_history.reference_id
FROM session_history
LEFT OUTER JOIN users ON session_history.user_id = users.user_id
LEFT OUTER JOIN session_history_metadata ON session_history.id = session_history_metadata.id
WHERE (CASE WHEN users.friendly_name IS NULL OR TRIM(users.friendly_name) = '' THEN users.username ELSE users.friendly_name END) LIKE ?5 OR ip_address LIKE ?6 OR platform LIKE ?7 OR product LIKE ?8 OR player LIKE ?9 OR session_history_metadata.full_title LIKE ?10)
GROUP BY session_history.reference_id
UNION ALL SELECT NULL AS reference_id, NULL AS row_id, started AS date, started, stopped, SUM(CASE WHEN stopped > 0 THEN (stopped - started) ELSE (1790000000 - started) END) - SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS play_duration, SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS paused_counter, view_offset, user_id, user, (CASE WHEN friendly_name IS NULL OR TRIM(friendly_name) = '' THEN user ELSE friendly_name END) AS friendly_name, NULL AS user_thumb, NULL AS custom_thumb, (SELECT is_archived
FROM users
WHERE users.user_id = sessions.user_id) AS user_is_archived, (SELECT MAX(is_archived)
FROM library_sections
WHERE library_sections.section_id = sessions.section_id) AS library_is_archived, platform, product, player, ip_address, machine_id, location, secure, relayed, media_type, (CASE WHEN live = 1 THEN 'live' ELSE media_type END) AS media_type_live, rating_key, parent_rating_key, grandparent_rating_key, full_title, title, parent_title, grandparent_title, original_title, year, media_index, parent_media_index, thumb, parent_thumb, grandparent_thumb, live, added_at, originally_available_at, guid, MAX((CASE WHEN (view_offset IS NULL OR view_offset = '') THEN 0.1 ELSE view_offset * 1.0 END) / (CASE WHEN (duration IS NULL OR duration = '') THEN 1.0 ELSE duration * 1.0 END) * 100) AS percent_complete, duration, NULL AS marker_credits_first, NULL AS marker_credits_final, transcode_decision, NULL AS group_count, NULL AS group_ids, state, session_key
FROM sessions
WHERE user_id NOT IN (?11,?12,?13) AND section_id NOT IN (?14)
GROUP BY session_key)
WHERE friendly_name LIKE ?15 OR ip_address LIKE ?16 OR platform LIKE ?17 OR product LIKE ?18 OR player LIKE ?19 OR full_title LIKE ?20
ORDER BY date COLLATE NOCASE DESC
LIMIT ?21 OFFSET ?22;

-- @id tautulli.history.total_duration
-- @src plexpy/datafactory.py:1939-1980
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics
-- @note The 'total duration' footer of the history table: SUM over every history row outside archived users/libraries (cached per history version, recomputed after every new play).
-- @param ?1 1300922
-- @param ?2 1308841
-- @param ?3 1316760
-- @param ?4 6
SELECT SUM(CASE WHEN stopped > 0 THEN (stopped - started) ELSE 0 END) - SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS total_duration
FROM session_history
WHERE session_history.user_id NOT IN (?1,?2,?3) AND session_history.section_id NOT IN (?4);

-- @id tautulli.home_stats.movies_pair_rows
-- @src plexpy/datafactory.py:699-716,727-731
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics,cpu-evidence
-- @note Home page 'Most Watched / Most Popular Movies' (30 days): per-play duration grouped by reference_id, joined to metadata and regrouped by title+year; the cards sort in Python. The home stats page is reported at 70 s in https://github.com/Tautulli/Tautulli/issues/1962.
-- @param ?1 1787408000
SELECT sh.id, shm.full_title, shm.year, sh.rating_key, shm.thumb, sh.section_id, shm.art, sh.media_type, shm.content_rating, shm.rating, shm.labels, sh.started, shm.live, shm.guid, COUNT(DISTINCT sh.user_id) AS users_watched, MAX(sh.started) AS last_watch, COUNT(sh.id) AS total_plays, SUM(sh.d) AS total_duration
FROM (SELECT id, media_type, section_id, started, user_id, rating_key, SUM(CASE WHEN stopped > 0 THEN (stopped - started) - (CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) ELSE 0 END) AS d
FROM session_history
WHERE session_history.media_type = 'movie' AND session_history.stopped >= ?1 AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1) AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1)
GROUP BY session_history.reference_id) AS sh
JOIN session_history_metadata AS shm ON shm.id = sh.id
GROUP BY shm.full_title, shm.year;

-- @id tautulli.home_stats.tv_pair_rows
-- @src plexpy/datafactory.py:699-716,732-737
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics,cpu-evidence
-- @note Home page 'Most Watched / Most Popular TV Shows' (30 days): episodes grouped per play, then per show title. The home stats page is reported at 70 s in https://github.com/Tautulli/Tautulli/issues/1962.
-- @param ?1 1787408000
SELECT sh.id, shm.grandparent_title, sh.grandparent_rating_key, shm.grandparent_thumb, sh.section_id, shm.year, sh.rating_key, shm.art, sh.media_type, shm.content_rating, shm.rating, shm.labels, sh.started, shm.live, shm.guid, COUNT(DISTINCT sh.user_id) AS users_watched, MAX(sh.started) AS last_watch, COUNT(sh.id) AS total_plays, SUM(sh.d) AS total_duration
FROM (SELECT id, media_type, section_id, started, user_id, grandparent_rating_key, rating_key, SUM(CASE WHEN stopped > 0 THEN (stopped - started) - (CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) ELSE 0 END) AS d
FROM session_history
WHERE session_history.media_type = 'episode' AND session_history.stopped >= ?1 AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1) AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1)
GROUP BY session_history.reference_id) AS sh
JOIN session_history_metadata AS shm ON shm.id = sh.id
GROUP BY shm.grandparent_title;

-- @id tautulli.home_stats.music_pair_rows
-- @src plexpy/datafactory.py:699-716,738-743
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics
-- @note Home page 'Most Played / Most Popular Artists' (30 days): tracks grouped per play, then per (original_title, grandparent_title).
-- @param ?1 1787408000
SELECT sh.id, shm.grandparent_title, shm.original_title, shm.year, sh.grandparent_rating_key, shm.grandparent_thumb, sh.section_id, shm.art, sh.media_type, shm.content_rating, shm.rating, shm.labels, sh.started, shm.live, shm.guid, COUNT(DISTINCT sh.user_id) AS users_watched, MAX(sh.started) AS last_watch, COUNT(sh.id) AS total_plays, SUM(sh.d) AS total_duration
FROM (SELECT id, media_type, section_id, started, user_id, grandparent_rating_key, SUM(CASE WHEN stopped > 0 THEN (stopped - started) - (CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) ELSE 0 END) AS d
FROM session_history
WHERE session_history.media_type = 'track' AND session_history.stopped >= ?1 AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1) AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1)
GROUP BY session_history.reference_id) AS sh
JOIN session_history_metadata AS shm ON shm.id = sh.id
GROUP BY shm.original_title, shm.grandparent_title;

-- @id tautulli.home_stats.top_libraries
-- @src plexpy/datafactory.py:977-999
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics
-- @note Home page 'Most Active Libraries': per-play durations grouped by section, joined to metadata and the non-deleted library_sections, top-N by plays.
-- @param ?1 1787408000
SELECT sh.id, shm.title, shm.grandparent_title, shm.full_title, shm.year, shm.media_index, shm.parent_media_index, sh.rating_key, shm.grandparent_rating_key, shm.thumb, shm.grandparent_thumb, sh.user, sh.user_id, sh.player, sh.section_id, shm.art, sh.media_type, shm.content_rating, shm.labels, shm.live, shm.guid, ls.section_name, ls.section_type, ls.thumb AS library_thumb, ls.custom_thumb_url AS custom_thumb, ls.art AS library_art, ls.custom_art_url AS custom_art, sh.started, MAX(sh.started) AS last_watch, COUNT(sh.id) AS total_plays, SUM(sh.d) AS total_duration
FROM (SELECT id, media_type, player, rating_key, section_id, started, user, user_id, SUM(CASE WHEN stopped > 0 THEN (stopped - started) - (CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) ELSE 0 END) AS d
FROM session_history
WHERE session_history.stopped >= ?1 AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1) AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1)
GROUP BY session_history.reference_id) AS sh
JOIN session_history_metadata AS shm ON shm.id = sh.id
LEFT OUTER JOIN (SELECT *
FROM library_sections
WHERE deleted_section = 0) AS ls ON sh.section_id = ls.section_id
GROUP BY sh.section_id
ORDER BY total_plays DESC, sh.started DESC
LIMIT 10 OFFSET 0;

-- @id tautulli.home_stats.top_users
-- @src plexpy/datafactory.py:1065-1087
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics
-- @note Home page 'Most Active Users': per-play durations grouped by user with the friendly-name CASE, top-N by plays.
-- @param ?1 1787408000
SELECT sh.id, shm.title, shm.grandparent_title, shm.full_title, shm.year, shm.media_index, shm.parent_media_index, sh.rating_key, shm.grandparent_rating_key, shm.thumb, shm.grandparent_thumb, sh.user, sh.user_id, sh.player, sh.section_id, shm.art, sh.media_type, shm.content_rating, shm.labels, shm.live, shm.guid, u.thumb AS user_thumb, u.custom_avatar_url AS custom_thumb, sh.started, (CASE WHEN u.friendly_name IS NULL OR TRIM(u.friendly_name) = '' THEN u.username ELSE u.friendly_name END) AS friendly_name, MAX(sh.started) AS last_watch, COUNT(sh.id) AS total_plays, SUM(sh.d) AS total_duration
FROM (SELECT id, media_type, player, rating_key, section_id, started, user, user_id, SUM(CASE WHEN stopped > 0 THEN (stopped - started) - (CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) ELSE 0 END) AS d
FROM session_history
WHERE session_history.stopped >= ?1 AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1) AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1)
GROUP BY session_history.reference_id) AS sh
JOIN session_history_metadata AS shm ON shm.id = sh.id
LEFT OUTER JOIN users AS u ON sh.user_id = u.user_id
GROUP BY sh.user_id
ORDER BY total_plays DESC, sh.started DESC
LIMIT 10 OFFSET 0;

-- @id tautulli.home_stats.last_watched
-- @src plexpy/datafactory.py:1187-1257
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics
-- @note Home page 'Recently Watched' (WATCHED_MARKER=3, the default): movies and episodes grouped per play over a metadata join, then rejoined to metadata to compare the view offset against MIN(credits marker, 85 % of duration).
-- @param ?1 1787408000
SELECT sh.id, shm.title, shm.grandparent_title, shm.full_title, shm.year, shm.media_index, shm.parent_media_index, sh.rating_key, shm.grandparent_rating_key, shm.thumb, shm.grandparent_thumb, sh.user, sh.user_id, u.custom_avatar_url as user_thumb, sh.player, sh.section_id, shm.art, sh.media_type, shm.content_rating, shm.rating, shm.labels, shm.live, shm.guid, (CASE WHEN u.friendly_name IS NULL OR TRIM(u.friendly_name) = '' THEN u.username ELSE u.friendly_name END) AS friendly_name, MAX(sh.started) AS last_watch, sh._view_offset, sh._duration, (sh._view_offset / sh._duration * 100) AS percent_complete, MIN((CASE WHEN shm.marker_credits_first IS NULL THEN sh._duration * (CASE WHEN sh.media_type = 'movie' THEN 85 ELSE 85 END) / 100.0 ELSE shm.marker_credits_first END), sh._duration * (CASE WHEN sh.media_type = 'movie' THEN 85 ELSE 85 END) / 100.0) AS watched_threshold
FROM (SELECT session_history.id, session_history.rating_key, session_history.user, session_history.user_id, session_history.player, session_history.section_id, session_history.media_type, session_history.started, MAX(session_history.id), (CASE WHEN view_offset IS NULL THEN 0.1 ELSE view_offset * 1.0 END) AS _view_offset, (CASE WHEN duration IS NULL THEN 1.0 ELSE duration * 1.0 END) AS _duration
FROM session_history
JOIN session_history_metadata ON session_history_metadata.id = session_history.id
WHERE (session_history.media_type = 'movie' OR session_history.media_type = 'episode') AND session_history.stopped >= ?1 AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1) AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1)
GROUP BY session_history.reference_id) AS sh
JOIN session_history_metadata AS shm ON shm.id = sh.id
LEFT OUTER JOIN users AS u ON sh.user_id = u.user_id
WHERE _view_offset >= watched_threshold
GROUP BY sh.id
ORDER BY last_watch DESC
LIMIT 10 OFFSET 0;

-- @id tautulli.home_stats.most_concurrent_scan
-- @src plexpy/datafactory.py:1337-1346
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics
-- @note Home page 'Most Concurrent Streams': every play of the last 30 days with its transcode decision; the sweep-line over start/stop times runs in Python.
-- @param ?1 1787408000
SELECT sh.started, sh.stopped, shmi.transcode_decision
FROM session_history AS sh
JOIN session_history_media_info AS shmi ON sh.id = shmi.id
WHERE sh.stopped >= ?1 AND sh.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND sh.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1);

-- @id tautulli.library_stats.last_played_per_section
-- @src plexpy/datafactory.py:1398-1403
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics
-- @note Home page library cards: last play per section via the bare-column MAX(started) trick, IN list over the shown sections.
-- @param ?1 1
-- @param ?2 2
-- @param ?3 3
-- @param ?4 4
-- @param ?5 5
-- @param ?6 7
SELECT section_id, id AS last_id, MAX(started)
FROM session_history
WHERE section_id IN (?1,?2,?3,?4,?5,?6) AND user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1)
GROUP BY section_id;

-- @id tautulli.library_stats.history_rows_by_id
-- @src plexpy/datafactory.py:1411-1421
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hot-small,dynamic
-- @note Library cards, second step: fetch the last-played rows by primary key (IN list) with their metadata.
-- @param ?1 134998
-- @param ?2 134999
-- @param ?3 135000
-- @param ?4 134967
-- @param ?5 134981
-- @param ?6 134952
SELECT sh.section_id, sh.id, shm.title, shm.grandparent_title, shm.full_title, shm.year, shm.media_index, shm.parent_media_index, sh.rating_key, shm.grandparent_rating_key, shm.thumb, shm.grandparent_thumb, sh.user, sh.user_id, sh.player, shm.art, sh.media_type, shm.content_rating, shm.labels, shm.live, shm.guid, sh.started AS last_watch
FROM session_history AS sh
LEFT OUTER JOIN session_history_metadata AS shm ON sh.id = shm.id
WHERE sh.id IN (?1,?2,?3,?4,?5,?6);

-- @id tautulli.item.watch_time_stats_show
-- @src plexpy/datafactory.py:1501-1570
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags dynamic,analytics
-- @note Show page 'Global Stats': 24 h / 7 d / 30 d / all-time watch time and distinct plays in one pass, CASE-filtered SUMs and COUNT(DISTINCT CASE ...), over a 3-way OR of rating-key IN lists (multi-index OR).
-- @param ?1 50000
-- @param ?2 50000
-- @param ?3 50000
SELECT SUM(CASE WHEN stopped >= 1789913600 THEN (stopped - started) - (CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) ELSE 0 END) AS total_time_0, COUNT(DISTINCT CASE WHEN stopped >= 1789913600 THEN session_history.reference_id END) AS total_plays_0, SUM(CASE WHEN stopped >= 1789395200 THEN (stopped - started) - (CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) ELSE 0 END) AS total_time_1, COUNT(DISTINCT CASE WHEN stopped >= 1789395200 THEN session_history.reference_id END) AS total_plays_1, SUM(CASE WHEN stopped >= 1787408000 THEN (stopped - started) - (CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) ELSE 0 END) AS total_time_2, COUNT(DISTINCT CASE WHEN stopped >= 1787408000 THEN session_history.reference_id END) AS total_plays_2, (SUM(stopped - started) - SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END)) AS total_time_3, COUNT(DISTINCT session_history.reference_id) AS total_plays_3, GROUP_CONCAT(DISTINCT section_id) AS section_ids
FROM session_history
WHERE (session_history.grandparent_rating_key IN (?1) OR session_history.parent_rating_key IN (?2) OR session_history.rating_key IN (?3)) AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1);

-- @id tautulli.item.user_stats_show
-- @src plexpy/datafactory.py:1594-1640
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags dynamic,analytics
-- @note Show page 'User Stats': plays and time per user for one show, multi-index OR over the three rating-key columns, joined to users and sorted.
-- @param ?1 50000
-- @param ?2 50000
-- @param ?3 50000
SELECT (CASE WHEN users.friendly_name IS NULL OR TRIM(users.friendly_name) = '' THEN users.username ELSE users.friendly_name END) AS friendly_name, users.user_id, users.username, users.thumb, users.custom_avatar_url AS custom_thumb, COUNT(DISTINCT session_history.reference_id) AS total_plays, (SUM(stopped - started) - SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END)) AS total_time, section_id
FROM session_history
JOIN users ON users.user_id = session_history.user_id
WHERE (session_history.grandparent_rating_key IN (?1) OR session_history.parent_rating_key IN (?2) OR session_history.rating_key IN (?3)) AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
GROUP BY users.user_id
ORDER BY total_plays DESC, total_time DESC;

-- @id tautulli.users.datatable_list
-- @src plexpy/users.py:127-229; plexpy/datatables.py:131-148
-- @style ? positional (python sqlite3); string-built by DataTables.ssp_query from column/join/where lists
-- @tags hotpath,dynamic,analytics
-- @note Users page: per-user plays/duration/last-seen aggregated over all history in a derived table (with a correlated latest-row subquery per user), LEFT JOINed back to the last play's history, metadata and media_info rows; COUNT(*) OVER () for the filtered count.
-- @param ?1 0
-- @param ?2 0
-- @param ?3 25
-- @param ?4 0
SELECT *, COUNT(*) OVER () AS __filtered_count
FROM (SELECT users.id AS row_id, users.user_id, users.username, (CASE WHEN users.friendly_name IS NULL OR TRIM(users.friendly_name) = '' THEN users.username ELSE users.friendly_name END) AS friendly_name, users.title, users.email, users.thumb AS user_thumb, users.custom_avatar_url AS custom_thumb, COALESCE(history_agg.plays, 0) AS plays, COALESCE(history_agg.duration, 0) AS duration, history_agg.last_seen, history_agg.history_row_id, session_history_metadata.full_title AS last_played, session_history.ip_address, session_history.platform, session_history.player, session_history.rating_key, session_history_metadata.media_type, session_history_metadata.thumb, session_history_metadata.parent_thumb, session_history_metadata.grandparent_thumb, session_history_metadata.parent_title, session_history_metadata.year, session_history_metadata.media_index, session_history_metadata.parent_media_index, session_history_metadata.live, session_history_metadata.added_at, session_history_metadata.originally_available_at, session_history_metadata.guid, session_history_media_info.transcode_decision, users.keep_history AS keep_history, users.allow_guest AS allow_guest, users.is_active AS is_active, users.is_archived AS is_archived, users.deleted_user AS deleted_user
FROM users
LEFT OUTER JOIN (SELECT user_id, COUNT(DISTINCT reference_id) AS plays, SUM(CASE WHEN stopped > 0 THEN (stopped - started) ELSE 0 END) - SUM(CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) AS duration, MAX(started) AS last_seen, (SELECT s2.id
FROM session_history AS s2
WHERE s2.user_id = session_history.user_id AND s2.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
ORDER BY s2.started DESC, s2.id DESC
LIMIT 1) AS history_row_id
FROM session_history
WHERE session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
GROUP BY user_id) AS history_agg ON history_agg.user_id = users.user_id
LEFT OUTER JOIN session_history ON session_history.id = history_agg.history_row_id
LEFT OUTER JOIN session_history_metadata ON session_history_metadata.id = history_agg.history_row_id
LEFT OUTER JOIN session_history_media_info ON session_history_media_info.id = history_agg.history_row_id
WHERE users.deleted_user = ?1 AND users.is_archived = ?2)
ORDER BY friendly_name COLLATE NOCASE ASC
LIMIT ?3 OFFSET ?4;

-- @id tautulli.graphs.plays_per_day
-- @src plexpy/graphs.py:37-63
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics,wallclock
-- @note Graphs 'Daily Play Count' (30 days): SELECT * grouped by (localtime date, reference_id), then regrouped by date with per-media-type CASE sums; date buckets use 'localtime', so bucket boundaries follow the machine's time zone.
SELECT sh.date_played, SUM(CASE WHEN sh.media_type = 'episode' AND sh.live = 0 THEN 1 ELSE 0 END) AS tv_count, SUM(CASE WHEN sh.media_type = 'movie' AND sh.live = 0 THEN 1 ELSE 0 END) AS movie_count, SUM(CASE WHEN sh.media_type = 'track' AND sh.live = 0 THEN 1 ELSE 0 END) AS music_count, SUM(sh.live) AS live_count
FROM (SELECT *, date(started, 'unixepoch', 'localtime') AS date_played
FROM session_history
WHERE session_history.stopped >= 1787408000 AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
GROUP BY date_played, session_history.reference_id) AS sh
GROUP BY sh.date_played
ORDER BY sh.started;

-- @id tautulli.graphs.duration_per_dayofweek_365d
-- @src plexpy/graphs.py:150-214
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags dynamic,analytics,wallclock
-- @note Graphs 'Play Duration by Day of Week' over the 365-day range: strftime('%w') of a localtime date for every row of the year, per-play duration SUM, regrouped with an 8-way CASE day name; date buckets use 'localtime', so bucket boundaries follow the machine's time zone.
SELECT sh.daynumber, (CASE sh.daynumber WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday' WHEN 2 THEN 'Tuesday' WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday' ELSE 'Saturday' END) AS dayofweek, SUM(CASE WHEN sh.media_type = 'episode' AND sh.live = 0 THEN sh.d ELSE 0 END) AS tv_count, SUM(CASE WHEN sh.media_type = 'movie' AND sh.live = 0 THEN sh.d ELSE 0 END) AS movie_count, SUM(CASE WHEN sh.media_type = 'track' AND sh.live = 0 THEN sh.d ELSE 0 END) AS music_count, SUM(CASE WHEN sh.live = 1 THEN sh.d ELSE 0 END) AS live_count
FROM (SELECT *, CAST(strftime('%w', date(started, 'unixepoch', 'localtime')) AS INTEGER) AS daynumber, SUM(CASE WHEN stopped > 0 THEN (stopped - started) - (CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) ELSE 0 END) AS d
FROM session_history
WHERE session_history.stopped >= 1758464000 AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
GROUP BY daynumber, session_history.reference_id) AS sh
GROUP BY dayofweek
ORDER BY sh.daynumber;

-- @id tautulli.graphs.plays_per_hourofday
-- @src plexpy/graphs.py:274-300
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics,wallclock
-- @note Graphs 'Plays by Hour of Day' (30 days): strftime('%H', datetime(..., 'localtime')) per row; date buckets use 'localtime', so bucket boundaries follow the machine's time zone.
SELECT sh.hourofday, SUM(CASE WHEN sh.media_type = 'episode' AND sh.live = 0 THEN 1 ELSE 0 END) AS tv_count, SUM(CASE WHEN sh.media_type = 'movie' AND sh.live = 0 THEN 1 ELSE 0 END) AS movie_count, SUM(CASE WHEN sh.media_type = 'track' AND sh.live = 0 THEN 1 ELSE 0 END) AS music_count, SUM(sh.live) AS live_count
FROM (SELECT *, strftime('%H', datetime(started, 'unixepoch', 'localtime')) AS hourofday
FROM session_history
WHERE session_history.stopped >= 1787408000 AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
GROUP BY hourofday, session_history.reference_id) AS sh
GROUP BY sh.hourofday
ORDER BY sh.hourofday;

-- @id tautulli.graphs.plays_per_month_12m
-- @src plexpy/graphs.py:380-406
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics,wallclock
-- @note Graphs 'Plays by Month' (12 months from the start of the month, about 40 % of all history): strftime('%Y-%m') bucket per row; date buckets use 'localtime', so bucket boundaries follow the machine's time zone.
SELECT sh.datestring, SUM(CASE WHEN sh.media_type = 'episode' AND sh.live = 0 THEN 1 ELSE 0 END) AS tv_count, SUM(CASE WHEN sh.media_type = 'movie' AND sh.live = 0 THEN 1 ELSE 0 END) AS movie_count, SUM(CASE WHEN sh.media_type = 'track' AND sh.live = 0 THEN 1 ELSE 0 END) AS music_count, SUM(sh.live) AS live_count
FROM (SELECT *, strftime('%Y-%m', datetime(started, 'unixepoch', 'localtime')) AS datestring
FROM session_history
WHERE session_history.stopped >= 1756684800 AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
GROUP BY datestring, session_history.reference_id) AS sh
GROUP BY sh.datestring
ORDER BY sh.datestring;

-- @id tautulli.graphs.top10_platforms
-- @src plexpy/graphs.py:494-521
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics
-- @note Graphs 'Plays by Top 10 Platforms' (30 days): SELECT * grouped per play then per platform, top 10.
SELECT sh.platform, SUM(CASE WHEN sh.media_type = 'episode' AND sh.live = 0 THEN 1 ELSE 0 END) AS tv_count, SUM(CASE WHEN sh.media_type = 'movie' AND sh.live = 0 THEN 1 ELSE 0 END) AS movie_count, SUM(CASE WHEN sh.media_type = 'track' AND sh.live = 0 THEN 1 ELSE 0 END) AS music_count, SUM(sh.live) AS live_count, COUNT(sh.id) AS total_count
FROM (SELECT *
FROM session_history
WHERE session_history.stopped >= 1787408000 AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
GROUP BY session_history.reference_id) AS sh
GROUP BY sh.platform
ORDER BY total_count DESC, sh.platform ASC
LIMIT 10;

-- @id tautulli.graphs.top10_users_duration
-- @src plexpy/graphs.py:588-644
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics
-- @note Graphs 'Play Duration by Top 10 Users' (30 days): per-play duration, joined to users, regrouped per user.
SELECT u.user_id, u.username, (CASE WHEN u.friendly_name IS NULL OR TRIM(u.friendly_name) = '' THEN u.username ELSE u.friendly_name END) AS friendly_name, SUM(CASE WHEN sh.media_type = 'episode' AND sh.live = 0 THEN sh.d ELSE 0 END) AS tv_count, SUM(CASE WHEN sh.media_type = 'movie' AND sh.live = 0 THEN sh.d ELSE 0 END) AS movie_count, SUM(CASE WHEN sh.media_type = 'track' AND sh.live = 0 THEN sh.d ELSE 0 END) AS music_count, SUM(CASE WHEN sh.live = 1 THEN sh.d ELSE 0 END) AS live_count, SUM(sh.d) AS total_duration
FROM (SELECT *, SUM(CASE WHEN stopped > 0 THEN (stopped - started) - (CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) ELSE 0 END) AS d
FROM session_history
WHERE session_history.stopped >= 1787408000 AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
GROUP BY session_history.reference_id) AS sh
JOIN users AS u ON u.user_id = sh.user_id
GROUP BY sh.user_id
ORDER BY total_duration DESC
LIMIT 10;

-- @id tautulli.graphs.stream_type_per_day
-- @src plexpy/graphs.py:693-718
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags hotpath,dynamic,analytics,wallclock
-- @note Graphs 'Daily Stream Type Breakdown' (30 days): direct play / direct stream / transcode CASE counts per localtime date; date buckets use 'localtime', so bucket boundaries follow the machine's time zone.
SELECT sh.date_played, SUM(CASE WHEN sh.transcode_decision = 'direct play' THEN 1 ELSE 0 END) AS dp_count, SUM(CASE WHEN sh.transcode_decision = 'copy' THEN 1 ELSE 0 END) AS ds_count, SUM(CASE WHEN sh.transcode_decision = 'transcode' THEN 1 ELSE 0 END) AS tc_count
FROM (SELECT *, date(started, 'unixepoch', 'localtime') AS date_played
FROM session_history
WHERE session_history.stopped >= 1787408000 AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
GROUP BY date_played, session_history.reference_id) AS sh
GROUP BY sh.date_played
ORDER BY sh.started;

-- @id tautulli.graphs.concurrent_streams_scan
-- @src plexpy/graphs.py:779-819
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags dynamic,analytics,wallclock
-- @note Graphs 'Daily Concurrent Stream Count': every play of the range with its localtime date, ordered by +started (unary plus keeps the planner off the started index); the per-day sweep runs in Python; date buckets use 'localtime', so bucket boundaries follow the machine's time zone.
SELECT date(session_history.started, 'unixepoch', 'localtime') AS date_played, session_history.started, session_history.stopped, session_history.transcode_decision
FROM session_history
WHERE session_history.stopped >= 1787408000 AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
ORDER BY +session_history.started;

-- @id tautulli.graphs.source_resolution
-- @src plexpy/graphs.py:875-903
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags dynamic,analytics
-- @note Graphs 'Plays by Source Resolution' (30 days): movies and episodes grouped per play, joined to media_info and regrouped by resolution.
SELECT shmi.video_full_resolution AS resolution, SUM(CASE WHEN shmi.transcode_decision = 'direct play' THEN 1 ELSE 0 END) AS dp_count, SUM(CASE WHEN shmi.transcode_decision = 'copy' THEN 1 ELSE 0 END) AS ds_count, SUM(CASE WHEN shmi.transcode_decision = 'transcode' THEN 1 ELSE 0 END) AS tc_count, COUNT(sh.id) AS total_count
FROM (SELECT *
FROM session_history
WHERE session_history.stopped >= 1787408000 AND session_history.media_type IN ('movie', 'episode') AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
GROUP BY session_history.reference_id) AS sh
JOIN session_history_media_info AS shmi ON shmi.id = sh.id
GROUP BY resolution
ORDER BY total_count DESC
LIMIT 10;

-- @id tautulli.graphs.stream_resolution_duration
-- @src plexpy/graphs.py:953-1027
-- @style ? positional (python sqlite3); %-formatted string, literals inlined by the app
-- @tags dynamic,analytics
-- @note Graphs 'Play Duration by Stream Resolution' (30 days): nested CASE ladder on transcode height as the GROUP BY key, per-play duration sums.
SELECT (CASE WHEN shmi.stream_video_full_resolution IS NULL THEN (CASE WHEN shmi.video_decision = 'transcode' THEN (CASE WHEN shmi.transcode_height <= 360 THEN 'SD' WHEN shmi.transcode_height <= 480 THEN '480' WHEN shmi.transcode_height <= 576 THEN '576' WHEN shmi.transcode_height <= 720 THEN '720' WHEN shmi.transcode_height <= 1080 THEN '1080' WHEN shmi.transcode_height <= 1440 THEN 'QHD' WHEN shmi.transcode_height <= 2160 THEN '4k' ELSE 'unknown' END) ELSE shmi.video_full_resolution END) ELSE shmi.stream_video_full_resolution END) AS resolution, SUM(CASE WHEN shmi.transcode_decision = 'direct play' THEN sh.d ELSE 0 END) AS dp_count, SUM(CASE WHEN shmi.transcode_decision = 'copy' THEN sh.d ELSE 0 END) AS ds_count, SUM(CASE WHEN shmi.transcode_decision = 'transcode' THEN sh.d ELSE 0 END) AS tc_count, SUM(sh.d) AS total_duration
FROM (SELECT *, SUM(CASE WHEN stopped > 0 THEN (stopped - started) - (CASE WHEN paused_counter IS NULL THEN 0 ELSE paused_counter END) ELSE 0 END) AS d
FROM session_history
WHERE session_history.stopped >= 1787408000 AND session_history.media_type IN ('movie', 'episode') AND session_history.user_id NOT IN (SELECT user_id
FROM users
WHERE is_archived = 1) AND session_history.section_id NOT IN (SELECT section_id
FROM library_sections
WHERE is_archived = 1)
GROUP BY session_history.reference_id) AS sh
JOIN session_history_media_info AS shmi ON shmi.id = sh.id
GROUP BY resolution
ORDER BY total_duration DESC
LIMIT 10;

-- @id tautulli.activity.group_history_lookup
-- @src plexpy/activity_processor.py:517-525
-- @style ? positional (python sqlite3), constant text
-- @tags hot-small
-- @note On every stopped stream: the user's last two plays of this item (user_id/rating_key index, id DESC LIMIT 2) to decide the reference_id grouping.
-- @param ?1 134991
-- @param ?2 1015838
-- @param ?3 305157
SELECT session_history.id, session_history.rating_key, session_history.view_offset, session_history.reference_id, session_history_metadata.guid, session_history_metadata.duration, session_history_metadata.marker_credits_first, session_history_metadata.marker_credits_final
FROM session_history LEFT
JOIN session_history_metadata ON session_history.id == session_history_metadata.id
WHERE session_history.id <= ?1 AND session_history.user_id = ?2 AND session_history.rating_key = ?3
ORDER BY session_history.id DESC
LIMIT 2;

-- @id tautulli.activity.is_initial_stream
-- @src plexpy/activity_processor.py:723-729
-- @style ? positional (python sqlite3), constant text
-- @tags hot-small
-- @note On every new stream: last stop time for this user/device/media type from sessions_continued (unique index).
-- @param ?1 1007919
-- @param ?2 'm9e3779b1-3'
-- @param ?3 'episode'
SELECT stopped
FROM sessions_continued
WHERE user_id = ?1 AND machine_id = ?2 AND media_type = ?3
ORDER BY stopped DESC;
