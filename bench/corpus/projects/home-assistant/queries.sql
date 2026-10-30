-- Home Assistant recorder / history / logbook (home-assistant/core @ e7bccf5, Apache-2.0).
-- All statements are SQLAlchemy 2.0 Core / lambda_stmt builders. They were imported from the pinned source
-- (with the rest of Home Assistant stubbed out) and compiled for the sqlite dialect with IN lists expanded,
-- exactly as the recorder sends them; ? placeholders are numbered ?N in order. Every query is tagged dynamic.
-- Timestamps are float epoch seconds; the synthetic data is anchored at 1790000000 (now).

-- @id ha.history.significant_states.multi_entity
-- @src homeassistant/components/recorder/history/__init__.py:175-239
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note History graph card for 5 entities over 24 h: UNION ALL of the start-time state per entity (correlated reverse-index LIMIT 1 in the JOIN condition over states_meta) and the significant changes, attributes via LEFT JOIN, CASE fallback to legacy attributes.
-- @param ?1 0
-- @param ?2 1789913600.0
-- @param ?3 1
-- @param ?4 0
-- @param ?5 4
-- @param ?6 13
-- @param ?7 20
-- @param ?8 21
-- @param ?9 33
-- @param ?10 20
-- @param ?11 4
-- @param ?12 13
-- @param ?13 20
-- @param ?14 21
-- @param ?15 33
-- @param ?16 1789913600.0
SELECT anon_1.metadata_id, anon_1.state, anon_1.last_updated_ts, anon_1.attributes
FROM (SELECT anon_2.metadata_id AS metadata_id, anon_2.state AS state, anon_2.last_updated_ts AS last_updated_ts, anon_2.attributes AS attributes
FROM (SELECT states.metadata_id AS metadata_id, states.state AS state, ?1 AS last_updated_ts, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes
FROM states_meta JOIN states ON states.last_updated_ts = (SELECT states.last_updated_ts
FROM states
WHERE states_meta.metadata_id = states.metadata_id AND states.last_updated_ts < ?2 ORDER BY states.last_updated_ts DESC
 LIMIT ?3 OFFSET ?4) AND states.metadata_id = states_meta.metadata_id LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id
WHERE states_meta.metadata_id IN (?5, ?6, ?7, ?8, ?9)) AS anon_2 UNION ALL SELECT anon_3.metadata_id AS metadata_id, anon_3.state AS state, anon_3.last_updated_ts AS last_updated_ts, anon_3.attributes AS attributes
FROM (SELECT states.metadata_id AS metadata_id, states.state AS state, states.last_updated_ts AS last_updated_ts, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes
FROM states LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id
WHERE (states.metadata_id IN (?10) OR states.last_changed_ts = states.last_updated_ts OR states.last_changed_ts IS NULL) AND states.metadata_id IN (?11, ?12, ?13, ?14, ?15) AND states.last_updated_ts > ?16) AS anon_3) AS anon_1 ORDER BY anon_1.metadata_id, anon_1.last_updated_ts;

-- @id ha.history.significant_states.minimal_no_attributes
-- @src homeassistant/components/recorder/history/__init__.py:175-239
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note History panel with no_attributes (minimal response), 12 sensors over a 3-day window with end time; start states via the dependent subquery, no attribute join.
-- @param ?1 0
-- @param ?2 1789654400.0
-- @param ?3 1
-- @param ?4 0
-- @param ?5 13
-- @param ?6 14
-- @param ?7 15
-- @param ?8 16
-- @param ?9 17
-- @param ?10 18
-- @param ?11 19
-- @param ?12 33
-- @param ?13 34
-- @param ?14 35
-- @param ?15 36
-- @param ?16 37
-- @param ?17 13
-- @param ?18 14
-- @param ?19 15
-- @param ?20 16
-- @param ?21 17
-- @param ?22 18
-- @param ?23 19
-- @param ?24 33
-- @param ?25 34
-- @param ?26 35
-- @param ?27 36
-- @param ?28 37
-- @param ?29 1789654400.0
-- @param ?30 1789913600.0
SELECT anon_1.metadata_id, anon_1.state, anon_1.last_updated_ts
FROM (SELECT anon_2.metadata_id AS metadata_id, anon_2.state AS state, anon_2.last_updated_ts AS last_updated_ts
FROM (SELECT states.metadata_id AS metadata_id, states.state AS state, ?1 AS last_updated_ts
FROM states_meta JOIN states ON states.last_updated_ts = (SELECT states.last_updated_ts
FROM states
WHERE states_meta.metadata_id = states.metadata_id AND states.last_updated_ts < ?2 ORDER BY states.last_updated_ts DESC
 LIMIT ?3 OFFSET ?4) AND states.metadata_id = states_meta.metadata_id
WHERE states_meta.metadata_id IN (?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)) AS anon_2 UNION ALL SELECT anon_3.metadata_id AS metadata_id, anon_3.state AS state, anon_3.last_updated_ts AS last_updated_ts
FROM (SELECT states.metadata_id AS metadata_id, states.state AS state, states.last_updated_ts AS last_updated_ts
FROM states
WHERE (states.last_changed_ts = states.last_updated_ts OR states.last_changed_ts IS NULL) AND states.metadata_id IN (?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28) AND states.last_updated_ts > ?29 AND states.last_updated_ts < ?30) AS anon_3) AS anon_1 ORDER BY anon_1.metadata_id, anon_1.last_updated_ts;

-- @id ha.history.significant_states.single_entity
-- @src homeassistant/components/recorder/history/__init__.py:175-239
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note More-info dialog history for one entity over 24 h: single-entity start state (ORDER BY last_updated_ts DESC LIMIT 1) UNION ALL the changes, ordered.
-- @param ?1 0
-- @param ?2 1789913600.0
-- @param ?3 13
-- @param ?4 1
-- @param ?5 0
-- @param ?6 13
-- @param ?7 1789913600.0
SELECT anon_1.metadata_id, anon_1.state, anon_1.last_updated_ts, anon_1.attributes
FROM (SELECT anon_2.metadata_id AS metadata_id, anon_2.state AS state, anon_2.last_updated_ts AS last_updated_ts, anon_2.attributes AS attributes
FROM (SELECT states.metadata_id AS metadata_id, states.state AS state, ?1 AS last_updated_ts, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes
FROM states LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id
WHERE states.last_updated_ts < ?2 AND states.metadata_id = ?3 ORDER BY states.last_updated_ts DESC
 LIMIT ?4 OFFSET ?5) AS anon_2 UNION ALL SELECT anon_3.metadata_id AS metadata_id, anon_3.state AS state, anon_3.last_updated_ts AS last_updated_ts, anon_3.attributes AS attributes
FROM (SELECT states.metadata_id AS metadata_id, states.state AS state, states.last_updated_ts AS last_updated_ts, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes
FROM states LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id
WHERE (states.last_changed_ts = states.last_updated_ts OR states.last_changed_ts IS NULL) AND states.metadata_id IN (?6) AND states.last_updated_ts > ?7) AS anon_3) AS anon_1 ORDER BY anon_1.metadata_id, anon_1.last_updated_ts;

-- @id ha.history.significant_states.all_updates
-- @src homeassistant/components/recorder/history/__init__.py:175-239
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note significant_changes_only=False (attribute-change graphs, e.g. climate): includes last_changed_ts, no start-time state, attribute join, ordered by metadata_id, last_updated_ts.
-- @param ?1 20
-- @param ?2 40
-- @param ?3 60
-- @param ?4 1789978400.0
-- @param ?5 1790000000.0
SELECT states.metadata_id, states.state, states.last_updated_ts, states.last_changed_ts, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes
FROM states LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id
WHERE states.metadata_id IN (?1, ?2, ?3) AND states.last_updated_ts > ?4 AND states.last_updated_ts < ?5 ORDER BY states.metadata_id, states.last_updated_ts;

-- @id ha.history.state_changes_during_period
-- @src homeassistant/components/recorder/history/__init__.py:417-478
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note state_changes_during_period for one entity (used by history stats, statistics sensors): start state UNION ALL changes, attributes joined, ordered by time and state_id.
-- @param ?1 0
-- @param ?2 0
-- @param ?3 1789913600.0
-- @param ?4 21
-- @param ?5 1
-- @param ?6 0
-- @param ?7 1789913600.0
-- @param ?8 21
-- @param ?9 1790000000.0
SELECT anon_1.metadata_id, anon_1.state, anon_1.last_updated_ts, anon_1.last_reported_ts, anon_1.attributes
FROM (SELECT anon_2.metadata_id AS metadata_id, anon_2.state AS state, anon_2.last_updated_ts AS last_updated_ts, anon_2.last_reported_ts AS last_reported_ts, anon_2.attributes AS attributes, anon_2.state_id AS state_id
FROM (SELECT states.metadata_id AS metadata_id, states.state AS state, ?1 AS last_updated_ts, ?2 AS last_reported_ts, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes, states.state_id AS state_id
FROM states LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id
WHERE states.last_updated_ts < ?3 AND states.metadata_id = ?4 ORDER BY states.last_updated_ts DESC, states.state_id DESC
 LIMIT ?5 OFFSET ?6) AS anon_2 UNION ALL SELECT anon_3.metadata_id AS metadata_id, anon_3.state AS state, anon_3.last_updated_ts AS last_updated_ts, anon_3.last_reported_ts AS last_reported_ts, anon_3.attributes AS attributes, anon_3.state_id AS state_id
FROM (SELECT states.metadata_id AS metadata_id, states.state AS state, states.last_updated_ts AS last_updated_ts, states.last_reported_ts AS last_reported_ts, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes, states.state_id AS state_id
FROM states LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id
WHERE (states.last_changed_ts = states.last_updated_ts OR states.last_changed_ts IS NULL) AND states.last_updated_ts > ?7 AND states.metadata_id = ?8 AND states.last_updated_ts < ?9 ORDER BY states.metadata_id, states.last_updated_ts, states.state_id) AS anon_3) AS anon_1 ORDER BY anon_1.last_updated_ts, anon_1.state_id;

-- @id ha.history.state_changes_during_period.descending_limit
-- @src homeassistant/components/recorder/history/__init__.py:417-478
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic
-- @note Newest 50 changes for one entity: inner ORDER BY ... DESC LIMIT in a subquery, re-sorted ascending outside; no start state.
-- @param ?1 1789568000.0
-- @param ?2 13
-- @param ?3 50
-- @param ?4 0
SELECT anon_1.metadata_id, anon_1.state, anon_1.last_updated_ts, anon_1.last_reported_ts, anon_1.state_id
FROM (SELECT states.metadata_id AS metadata_id, states.state AS state, states.last_updated_ts AS last_updated_ts, states.last_reported_ts AS last_reported_ts, states.state_id AS state_id
FROM states
WHERE (states.last_changed_ts = states.last_updated_ts OR states.last_changed_ts IS NULL) AND states.last_updated_ts > ?1 AND states.metadata_id = ?2 ORDER BY states.last_updated_ts DESC, states.state_id DESC
 LIMIT ?3 OFFSET ?4) AS anon_1 ORDER BY anon_1.last_updated_ts, anon_1.state_id;

-- @id ha.history.last_state_changes.single
-- @src homeassistant/components/recorder/history/__init__.py:548-573
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hot-small
-- @note get_last_state_changes(1): GROUP BY max(last_updated_ts) subquery joined back to states and state_attributes.
-- @param ?1 33
SELECT states.metadata_id, states.state, states.last_updated_ts, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes
FROM states JOIN (SELECT states.metadata_id AS max_metadata_id, max(states.last_updated_ts) AS max_last_updated
FROM states
WHERE states.metadata_id = ?1 GROUP BY states.metadata_id) AS anon_1 ON states.metadata_id = anon_1.max_metadata_id AND states.last_updated_ts = anon_1.max_last_updated LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id ORDER BY states.state_id DESC;

-- @id ha.history.last_state_changes.multiple
-- @src homeassistant/components/recorder/history/__init__.py:576-595
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic
-- @note get_last_state_changes(n>1): state_id equal to a column of a LIMIT subquery (SQLAlchemy renders it as an implicit cross join with the derived table).
-- @param ?1 33
-- @param ?2 10
-- @param ?3 0
SELECT states.metadata_id, states.state, states.last_updated_ts, states.last_reported_ts, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes
FROM states LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id, (SELECT states.state_id AS state_id
FROM states
WHERE states.metadata_id = ?1 ORDER BY states.last_updated_ts DESC
 LIMIT ?2 OFFSET ?3) AS anon_1
WHERE states.state_id = anon_1.state_id ORDER BY states.state_id DESC;

-- @id ha.statistics.compile_hourly.summary_mean
-- @src homeassistant/components/recorder/statistics.py:507-528
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic
-- @note Hourly compile of 5-minute stats: GROUP BY metadata_id, mean_type with CASE over arithmetic avg vs circular mean (atan2/sin/cos/radians/sqrt/power of weighted sums).
-- @param ?1 1
-- @param ?2 2
-- @param ?3 2
-- @param ?4 2
-- @param ?5 2
-- @param ?6 1789995600.0
-- @param ?7 1789999200.0
SELECT statistics_short_term.metadata_id, min(statistics_short_term.min) AS min_1, max(statistics_short_term.max) AS max_1, CASE WHEN (statistics_meta.mean_type = ?1) THEN avg(statistics_short_term.mean) WHEN (statistics_meta.mean_type = ?2) THEN degrees(atan2(sum(sin(radians(statistics_short_term.mean)) * statistics_short_term.mean_weight), sum(cos(radians(statistics_short_term.mean)) * statistics_short_term.mean_weight))) END AS anon_1, CASE WHEN (statistics_meta.mean_type = ?3) THEN sqrt(power(sum(sin(radians(statistics_short_term.mean)) * statistics_short_term.mean_weight), ?4) + power(sum(cos(radians(statistics_short_term.mean)) * statistics_short_term.mean_weight), ?5)) END AS anon_2, statistics_meta.mean_type
FROM statistics_short_term JOIN statistics_meta ON statistics_short_term.metadata_id = statistics_meta.id
WHERE statistics_short_term.start_ts >= ?6 AND statistics_short_term.start_ts < ?7 GROUP BY statistics_short_term.metadata_id, statistics_meta.mean_type ORDER BY statistics_short_term.metadata_id;

-- @id ha.statistics.compile_hourly.last_sum
-- @src homeassistant/components/recorder/statistics.py:531-548
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic
-- @note Hourly compile: row_number() OVER (PARTITION BY metadata_id ORDER BY start_ts DESC) = 1 to take the last 5-minute sum of the hour.
-- @param ?1 1789995600.0
-- @param ?2 1789999200.0
-- @param ?3 1
SELECT anon_1.metadata_id, anon_1.start_ts, anon_1.last_reset_ts, anon_1.state, anon_1.sum, anon_1.rownum
FROM (SELECT statistics_short_term.metadata_id AS metadata_id, statistics_short_term.start_ts AS start_ts, statistics_short_term.last_reset_ts AS last_reset_ts, statistics_short_term.state AS state, statistics_short_term.sum AS sum, row_number() OVER (PARTITION BY statistics_short_term.metadata_id ORDER BY statistics_short_term.start_ts DESC) AS rownum
FROM statistics_short_term
WHERE statistics_short_term.start_ts >= ?1 AND statistics_short_term.start_ts < ?2) AS anon_1
WHERE anon_1.rownum = ?3 ORDER BY anon_1.metadata_id;

-- @id ha.statistics.during_period.hourly
-- @src homeassistant/components/recorder/statistics.py:1463-1483
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note Statistics graph card / energy dashboard: hourly rows for 8 statistics over 7 days, metadata_id IN list, ordered by metadata_id, start_ts.
-- @param ?1 1789394400.0
-- @param ?2 1789999200.0
-- @param ?3 1
-- @param ?4 2
-- @param ?5 3
-- @param ?6 4
-- @param ?7 5
-- @param ?8 6
-- @param ?9 7
-- @param ?10 8
SELECT statistics.metadata_id, statistics.start_ts, statistics.max, statistics.mean, statistics.mean_weight, statistics.min, statistics.state, statistics.sum
FROM statistics
WHERE statistics.start_ts >= ?1 AND statistics.start_ts < ?2 AND statistics.metadata_id IN (?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10) ORDER BY statistics.metadata_id, statistics.start_ts;

-- @id ha.statistics.during_period.short_term
-- @src homeassistant/components/recorder/statistics.py:1463-1483
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note 5-minute statistics for 3 sensors over the last 24 h (statistics graph at 5-minute period).
-- @param ?1 1789912800.0
-- @param ?2 2
-- @param ?3 4
-- @param ?4 10
SELECT statistics_short_term.metadata_id, statistics_short_term.start_ts, statistics_short_term.max, statistics_short_term.mean, statistics_short_term.mean_weight, statistics_short_term.min
FROM statistics_short_term
WHERE statistics_short_term.start_ts >= ?1 AND statistics_short_term.metadata_id IN (?2, ?3, ?4) ORDER BY statistics_short_term.metadata_id, statistics_short_term.start_ts;

-- @id ha.statistics.during_period.energy_sum
-- @src homeassistant/components/recorder/statistics.py:1463-1483
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note Energy dashboard: sum-only hourly rows for the energy statistics over 30 days.
-- @param ?1 1787407200.0
-- @param ?2 1789999200.0
-- @param ?3 3
-- @param ?4 6
-- @param ?5 9
-- @param ?6 12
-- @param ?7 15
SELECT statistics.metadata_id, statistics.start_ts, statistics.sum
FROM statistics
WHERE statistics.start_ts >= ?1 AND statistics.start_ts < ?2 AND statistics.metadata_id IN (?3, ?4, ?5, ?6, ?7) ORDER BY statistics.metadata_id, statistics.start_ts;

-- @id ha.statistics.at_time.dependent_subquery
-- @src homeassistant/components/recorder/statistics.py:2491-2528
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note Last known statistic before the period start for each requested id: statistics_meta JOIN statistics ON start_ts = correlated reverse-index LIMIT 1 subquery.
-- @param ?1 1789394400.0
-- @param ?2 1
-- @param ?3 0
-- @param ?4 1
-- @param ?5 2
-- @param ?6 3
-- @param ?7 4
-- @param ?8 5
-- @param ?9 6
-- @param ?10 7
-- @param ?11 8
SELECT statistics.metadata_id, statistics.start_ts, statistics.max, statistics.mean, statistics.mean_weight, statistics.min, statistics.state, statistics.sum
FROM statistics_meta JOIN statistics ON statistics.start_ts = (SELECT statistics.start_ts
FROM statistics
WHERE statistics_meta.id = statistics.metadata_id AND statistics.start_ts < ?1 ORDER BY statistics.start_ts DESC
 LIMIT ?2 OFFSET ?3) AND statistics.metadata_id = statistics_meta.id
WHERE statistics.metadata_id IN (?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11);

-- @id ha.statistics.period.max_mean_min_arithmetic
-- @src homeassistant/components/recorder/statistics.py:1511-1562
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note statistic_during_period (statistic card): max/avg/count/min aggregate of one statistic over the main hourly sub-period.
-- @param ?1 2
-- @param ?2 1787407200.0
-- @param ?3 1789999200.0
SELECT max(statistics.max) AS max_1, avg(statistics.mean) AS avg_1, count(statistics.mean) AS count_1, min(statistics.min) AS min_1
FROM statistics
WHERE statistics.metadata_id = ?1 AND statistics.start_ts >= ?2 AND statistics.start_ts < ?3;

-- @id ha.statistics.period.max_mean_min_circular
-- @src homeassistant/components/recorder/statistics.py:1511-1562
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic
-- @note Same for a circular-mean statistic (wind direction): weighted sin/cos sums, atan2, degrees, sqrt(power+power).
-- @param ?1 2
-- @param ?2 2
-- @param ?3 10
-- @param ?4 1789912800.0
-- @param ?5 1789999200.0
SELECT max(statistics_short_term.max) AS max_1, degrees(atan2(sum(sin(radians(statistics_short_term.mean)) * statistics_short_term.mean_weight), sum(cos(radians(statistics_short_term.mean)) * statistics_short_term.mean_weight))) AS mean, sqrt(power(sum(sin(radians(statistics_short_term.mean)) * statistics_short_term.mean_weight), ?1) + power(sum(cos(radians(statistics_short_term.mean)) * statistics_short_term.mean_weight), ?2)) AS mean_weight, min(statistics_short_term.min) AS min_1
FROM statistics_short_term
WHERE statistics_short_term.metadata_id = ?3 AND statistics_short_term.start_ts >= ?4 AND statistics_short_term.start_ts < ?5;

-- @id ha.statistics.period.newest_sum
-- @src homeassistant/components/recorder/statistics.py:1769-1832
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hot-small
-- @note statistic_during_period change: newest non-NULL sum in the window (top-1 by start_ts DESC on the (metadata_id, start_ts) index).
-- @param ?1 3
-- @param ?2 1787407200.0
-- @param ?3 1789999200.0
-- @param ?4 1
-- @param ?5 0
SELECT statistics.sum
FROM statistics
WHERE statistics.metadata_id = ?1 AND statistics.sum IS NOT NULL AND statistics.start_ts >= ?2 AND statistics.start_ts < ?3 ORDER BY statistics.start_ts DESC
 LIMIT ?4 OFFSET ?5;

-- @id ha.statistics.last_short_term
-- @src homeassistant/components/recorder/statistics.py:2283-2300
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hot-small
-- @note get_last_short_term_statistics(1): sensor platform compile fetches the previous 5-minute row per statistic.
-- @param ?1 3
-- @param ?2 1
-- @param ?3 0
SELECT statistics_short_term.metadata_id, statistics_short_term.start_ts, statistics_short_term.mean, statistics_short_term.min, statistics_short_term.max, statistics_short_term.last_reset_ts, statistics_short_term.state, statistics_short_term.sum
FROM statistics_short_term
WHERE statistics_short_term.metadata_id = ?1 ORDER BY statistics_short_term.metadata_id, statistics_short_term.start_ts DESC
 LIMIT ?2 OFFSET ?3;

-- @id ha.statistics.latest_short_term_by_ids
-- @src homeassistant/components/recorder/statistics.py:2385-2393
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note Energy dashboard live values: latest 5-minute rows by primary-key IN list (ids from the run cache).
-- @param ?1 11
-- @param ?2 21
-- @param ?3 31
-- @param ?4 41
-- @param ?5 51
-- @param ?6 61
-- @param ?7 71
-- @param ?8 81
-- @param ?9 91
-- @param ?10 101
-- @param ?11 111
-- @param ?12 121
-- @param ?13 131
-- @param ?14 141
-- @param ?15 151
-- @param ?16 161
-- @param ?17 171
-- @param ?18 181
-- @param ?19 191
-- @param ?20 201
SELECT statistics_short_term.metadata_id, statistics_short_term.start_ts, statistics_short_term.mean, statistics_short_term.min, statistics_short_term.max, statistics_short_term.last_reset_ts, statistics_short_term.state, statistics_short_term.sum
FROM statistics_short_term
WHERE statistics_short_term.id IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20);

-- @id ha.statistics.find_latest_short_term_id
-- @src homeassistant/components/recorder/statistics.py:2991-3017
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hot-small
-- @note Run-cache miss: id of the newest 5-minute row for one metadata_id (top-1 reverse index scan).
-- @param ?1 7
-- @param ?2 1
-- @param ?3 0
SELECT statistics_short_term.id
FROM statistics_short_term
WHERE statistics_short_term.metadata_id = ?1 ORDER BY statistics_short_term.start_ts DESC
 LIMIT ?2 OFFSET ?3;

-- @id ha.statistics_meta.get_many
-- @src homeassistant/components/recorder/table_managers/statistics_meta.py:46-78
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hot-small
-- @note statistics_meta lookup by statistic_id IN list with mean_type/unit_class columns (schema >= 51).
-- @param ?1 'sensor.stat_2'
-- @param ?2 'sensor.stat_10'
-- @param ?3 'sensor.stat_3'
SELECT statistics_meta.id, statistics_meta.statistic_id, statistics_meta.source, statistics_meta.unit_of_measurement, statistics_meta.has_sum, statistics_meta.name, statistics_meta.mean_type, statistics_meta.unit_class
FROM statistics_meta
WHERE statistics_meta.statistic_id IN (?1, ?2, ?3);

-- @id ha.statistics_meta.list_sum
-- @src homeassistant/components/recorder/table_managers/statistics_meta.py:46-78
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic
-- @note list_statistic_ids(statistic_type='sum'): all sum statistics for the energy config UI.
SELECT statistics_meta.id, statistics_meta.statistic_id, statistics_meta.source, statistics_meta.unit_of_measurement, statistics_meta.has_sum, statistics_meta.name, statistics_meta.mean_type, statistics_meta.unit_class
FROM statistics_meta
WHERE statistics_meta.has_sum = 1;

-- @id ha.recorder.states_meta.find_ids
-- @src homeassistant/components/recorder/queries.py:69-75
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hot-small
-- @note states_meta_manager cache miss: metadata_id for entity_ids (unique index lookup).
-- @param ?1 'sensor.e13'
-- @param ?2 'light.e21'
-- @param ?3 'climate.e20'
SELECT states_meta.metadata_id, states_meta.entity_id
FROM states_meta
WHERE states_meta.entity_id IN (?1, ?2, ?3);

-- @id ha.recorder.state_attributes.by_hash
-- @src homeassistant/components/recorder/queries.py:38-40
-- @style SQLAlchemy select with bindparam('hash'); ? positional
-- @tags dynamic,hot-small
-- @note Write path: dedupe new state attributes by fnv1a hash (plain statement, runs per cache miss).
-- @param ?1 2175734977
SELECT state_attributes.attributes_id, state_attributes.shared_attrs
FROM state_attributes
WHERE state_attributes.hash = ?1;

-- @id ha.recorder.states.insert
-- @src homeassistant/components/recorder/db_schema.py:478-516
-- @style SQLAlchemy ORM unit-of-work INSERT; ? positional
-- @tags dynamic,hot-small
-- @note Every recorded state change: ORM flush of States.from_event plus metadata_id/attributes_id/old_state_id set by the recorder.
-- @modified reconstructed from the ORM model (States.from_event and core.py session.add); the ORM may batch rows with insertmanyvalues + RETURNING
-- @param ?1 '21.5'
-- @param ?2 NULL
-- @param ?3 NULL
-- @param ?4 1790000001.25
-- @param ?5 1
-- @param ?6 17
-- @param ?7 0
-- @param ?8 X'0199A1B2C3D4E5F60718293A4B5C6D7E'
-- @param ?9 NULL
-- @param ?10 NULL
-- @param ?11 13
INSERT INTO states (state, last_changed_ts, last_reported_ts, last_updated_ts, old_state_id, attributes_id, origin_idx, context_id_bin, context_user_id_bin, context_parent_id_bin, metadata_id) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11);

-- @id ha.purge.find_states_to_purge
-- @src homeassistant/components/recorder/queries.py:284-294
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic
-- @note Nightly purge (keep 10 days): next batch of (state_id, attributes_id) older than the cutoff, LIMIT max_bind_vars.
-- @param ?1 1789222400.0
-- @param ?2 4000
-- @param ?3 0
SELECT states.state_id, states.attributes_id
FROM states
WHERE states.last_updated_ts < ?1
 LIMIT ?2 OFFSET ?3;

-- @id ha.purge.attributes_ids_in_states
-- @src homeassistant/components/recorder/queries.py:78-88
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic
-- @note Purge: DISTINCT attributes_id IN (batch) still referenced by states; SQLite path (covering index).
-- @param ?1 1
-- @param ?2 51
-- @param ?3 101
-- @param ?4 151
-- @param ?5 201
-- @param ?6 251
-- @param ?7 301
-- @param ?8 351
-- @param ?9 401
-- @param ?10 451
-- @param ?11 501
-- @param ?12 551
-- @param ?13 601
-- @param ?14 651
-- @param ?15 701
-- @param ?16 751
-- @param ?17 801
-- @param ?18 851
-- @param ?19 901
-- @param ?20 951
-- @param ?21 1001
-- @param ?22 1051
-- @param ?23 1101
-- @param ?24 1151
-- @param ?25 1201
-- @param ?26 1251
-- @param ?27 1301
-- @param ?28 1351
-- @param ?29 1401
-- @param ?30 1451
-- @param ?31 1501
-- @param ?32 1551
-- @param ?33 1601
-- @param ?34 1651
-- @param ?35 1701
-- @param ?36 1751
-- @param ?37 1801
-- @param ?38 1851
-- @param ?39 1901
-- @param ?40 1951
-- @param ?41 2001
-- @param ?42 2051
-- @param ?43 2101
-- @param ?44 2151
-- @param ?45 2201
-- @param ?46 2251
-- @param ?47 2301
-- @param ?48 2351
-- @param ?49 2401
-- @param ?50 2451
-- @param ?51 2501
-- @param ?52 2551
-- @param ?53 2601
-- @param ?54 2651
SELECT DISTINCT states.attributes_id
FROM states
WHERE states.attributes_id IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48, ?49, ?50, ?51, ?52, ?53, ?54);

-- @id ha.purge.disconnect_states
-- @src homeassistant/components/recorder/queries.py:170-179
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,batch
-- @note Purge: NULL out old_state_id pointing at the batch being deleted (UPDATE ... WHERE old_state_id IN (...)).
-- @param ?1 NULL
-- @param ?2 1
-- @param ?3 2
-- @param ?4 3
-- @param ?5 4
-- @param ?6 5
-- @param ?7 6
-- @param ?8 7
-- @param ?9 8
-- @param ?10 9
-- @param ?11 10
-- @param ?12 11
-- @param ?13 12
-- @param ?14 13
-- @param ?15 14
-- @param ?16 15
-- @param ?17 16
-- @param ?18 17
-- @param ?19 18
-- @param ?20 19
-- @param ?21 20
-- @param ?22 21
-- @param ?23 22
-- @param ?24 23
-- @param ?25 24
-- @param ?26 25
-- @param ?27 26
-- @param ?28 27
-- @param ?29 28
-- @param ?30 29
-- @param ?31 30
-- @param ?32 31
-- @param ?33 32
-- @param ?34 33
-- @param ?35 34
-- @param ?36 35
-- @param ?37 36
-- @param ?38 37
-- @param ?39 38
-- @param ?40 39
-- @param ?41 40
-- @param ?42 41
-- @param ?43 42
-- @param ?44 43
-- @param ?45 44
-- @param ?46 45
-- @param ?47 46
-- @param ?48 47
-- @param ?49 48
-- @param ?50 49
-- @param ?51 50
-- @param ?52 51
-- @param ?53 52
-- @param ?54 53
-- @param ?55 54
-- @param ?56 55
-- @param ?57 56
-- @param ?58 57
-- @param ?59 58
-- @param ?60 59
-- @param ?61 60
-- @param ?62 61
-- @param ?63 62
-- @param ?64 63
-- @param ?65 64
-- @param ?66 65
-- @param ?67 66
-- @param ?68 67
-- @param ?69 68
-- @param ?70 69
-- @param ?71 70
-- @param ?72 71
-- @param ?73 72
-- @param ?74 73
-- @param ?75 74
-- @param ?76 75
-- @param ?77 76
-- @param ?78 77
-- @param ?79 78
-- @param ?80 79
-- @param ?81 80
-- @param ?82 81
-- @param ?83 82
-- @param ?84 83
-- @param ?85 84
-- @param ?86 85
-- @param ?87 86
-- @param ?88 87
-- @param ?89 88
-- @param ?90 89
-- @param ?91 90
-- @param ?92 91
-- @param ?93 92
-- @param ?94 93
-- @param ?95 94
-- @param ?96 95
-- @param ?97 96
-- @param ?98 97
-- @param ?99 98
-- @param ?100 99
-- @param ?101 100
UPDATE states SET old_state_id=?1 WHERE states.old_state_id IN (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48, ?49, ?50, ?51, ?52, ?53, ?54, ?55, ?56, ?57, ?58, ?59, ?60, ?61, ?62, ?63, ?64, ?65, ?66, ?67, ?68, ?69, ?70, ?71, ?72, ?73, ?74, ?75, ?76, ?77, ?78, ?79, ?80, ?81, ?82, ?83, ?84, ?85, ?86, ?87, ?88, ?89, ?90, ?91, ?92, ?93, ?94, ?95, ?96, ?97, ?98, ?99, ?100, ?101);

-- @id ha.purge.delete_states
-- @src homeassistant/components/recorder/queries.py:182-190
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,batch
-- @note Purge: DELETE states by state_id IN-list batch.
-- @param ?1 1
-- @param ?2 2
-- @param ?3 3
-- @param ?4 4
-- @param ?5 5
-- @param ?6 6
-- @param ?7 7
-- @param ?8 8
-- @param ?9 9
-- @param ?10 10
-- @param ?11 11
-- @param ?12 12
-- @param ?13 13
-- @param ?14 14
-- @param ?15 15
-- @param ?16 16
-- @param ?17 17
-- @param ?18 18
-- @param ?19 19
-- @param ?20 20
-- @param ?21 21
-- @param ?22 22
-- @param ?23 23
-- @param ?24 24
-- @param ?25 25
-- @param ?26 26
-- @param ?27 27
-- @param ?28 28
-- @param ?29 29
-- @param ?30 30
-- @param ?31 31
-- @param ?32 32
-- @param ?33 33
-- @param ?34 34
-- @param ?35 35
-- @param ?36 36
-- @param ?37 37
-- @param ?38 38
-- @param ?39 39
-- @param ?40 40
-- @param ?41 41
-- @param ?42 42
-- @param ?43 43
-- @param ?44 44
-- @param ?45 45
-- @param ?46 46
-- @param ?47 47
-- @param ?48 48
-- @param ?49 49
-- @param ?50 50
-- @param ?51 51
-- @param ?52 52
-- @param ?53 53
-- @param ?54 54
-- @param ?55 55
-- @param ?56 56
-- @param ?57 57
-- @param ?58 58
-- @param ?59 59
-- @param ?60 60
-- @param ?61 61
-- @param ?62 62
-- @param ?63 63
-- @param ?64 64
-- @param ?65 65
-- @param ?66 66
-- @param ?67 67
-- @param ?68 68
-- @param ?69 69
-- @param ?70 70
-- @param ?71 71
-- @param ?72 72
-- @param ?73 73
-- @param ?74 74
-- @param ?75 75
-- @param ?76 76
-- @param ?77 77
-- @param ?78 78
-- @param ?79 79
-- @param ?80 80
-- @param ?81 81
-- @param ?82 82
-- @param ?83 83
-- @param ?84 84
-- @param ?85 85
-- @param ?86 86
-- @param ?87 87
-- @param ?88 88
-- @param ?89 89
-- @param ?90 90
-- @param ?91 91
-- @param ?92 92
-- @param ?93 93
-- @param ?94 94
-- @param ?95 95
-- @param ?96 96
-- @param ?97 97
-- @param ?98 98
-- @param ?99 99
-- @param ?100 100
DELETE FROM states WHERE states.state_id IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48, ?49, ?50, ?51, ?52, ?53, ?54, ?55, ?56, ?57, ?58, ?59, ?60, ?61, ?62, ?63, ?64, ?65, ?66, ?67, ?68, ?69, ?70, ?71, ?72, ?73, ?74, ?75, ?76, ?77, ?78, ?79, ?80, ?81, ?82, ?83, ?84, ?85, ?86, ?87, ?88, ?89, ?90, ?91, ?92, ?93, ?94, ?95, ?96, ?97, ?98, ?99, ?100);

-- @id ha.purge.find_entity_ids_to_purge
-- @src homeassistant/components/recorder/queries.py:554-585
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic
-- @note Purge: states_meta rows with no remaining states: NOT IN over a join whose ON clause holds a correlated LIMIT 1 subquery.
-- @param ?1 1
-- @param ?2 0
SELECT states_meta.metadata_id, states_meta.entity_id
FROM states_meta
WHERE (states_meta.metadata_id NOT IN (SELECT states_meta.metadata_id
FROM states_meta JOIN states ON states_meta.metadata_id = states.metadata_id AND states.last_updated_ts = (SELECT states.last_updated_ts
FROM states
WHERE states.metadata_id = states_meta.metadata_id
 LIMIT ?1 OFFSET ?2)));

-- @id ha.logbook.all
-- @src homeassistant/components/logbook/queries/all.py:17-45
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note Logbook page, all entities, 24 h: events UNION ALL states-as-events with old_state self-join, NOT LIKE domain filters, LIKE on shared_attrs for unit_of_measurement, JSON icon extraction.
-- @param ?1 NULL
-- @param ?2 NULL
-- @param ?3 NULL
-- @param ?4 NULL
-- @param ?5 NULL
-- @param ?6 1789913600.0
-- @param ?7 1790000000.0
-- @param ?8 1
-- @param ?9 2
-- @param ?10 3
-- @param ?11 4
-- @param ?12 5
-- @param ?13 6
-- @param ?14 NULL
-- @param ?15 NULL
-- @param ?16 '$."icon"'
-- @param ?17 '$."icon"'
-- @param ?18 '$."icon"'
-- @param ?19 NULL
-- @param ?20 1789913600.0
-- @param ?21 1790000000.0
-- @param ?22 'counter.%'
-- @param ?23 'image.%'
-- @param ?24 'proximity.%'
-- @param ?25 'sensor.%'
-- @param ?26 'sensor.%'
-- @param ?27 '%"unit_of_measurement":%'
-- @param ?28 '%"unit_of_measurement":%'
SELECT events.event_id AS row_id, event_types.event_type AS event_type, CASE WHEN (event_data.shared_data IS NULL) THEN events.event_data ELSE event_data.shared_data END AS event_data, events.time_fired_ts AS time_fired_ts, events.context_id_bin AS context_id_bin, events.context_user_id_bin AS context_user_id_bin, events.context_parent_id_bin AS context_parent_id_bin, ?1 AS state, ?2 AS entity_id, ?3 AS icon, ?4 AS attributes, ?5 AS context_only
FROM events LEFT OUTER JOIN event_types ON events.event_type_id = event_types.event_type_id LEFT OUTER JOIN event_data ON events.data_id = event_data.data_id
WHERE events.time_fired_ts > ?6 AND events.time_fired_ts < ?7 AND events.event_type_id IN (?8, ?9, ?10, ?11, ?12, ?13) UNION ALL SELECT states.state_id AS row_id, ?14 AS event_type, ?15 AS event_data, states.last_updated_ts AS time_fired_ts, states.context_id_bin AS context_id_bin, states.context_user_id_bin AS context_user_id_bin, states.context_parent_id_bin AS context_parent_id_bin, states.state AS state, states_meta.entity_id AS entity_id, CASE WHEN (JSON_QUOTE(JSON_EXTRACT(CAST(state_attributes.shared_attrs AS TEXT), ?16)) IS NULL) THEN JSON_EXTRACT(CAST(states.attributes AS TEXT), ?17) ELSE JSON_EXTRACT(CAST(state_attributes.shared_attrs AS TEXT), ?18) END AS icon, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes, ?19 AS context_only
FROM states LEFT OUTER JOIN states AS old_state ON states.old_state_id = old_state.state_id LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id LEFT OUTER JOIN states_meta ON states.metadata_id = states_meta.metadata_id
WHERE states.last_updated_ts > ?20 AND states.last_updated_ts < ?21 AND old_state.state_id IS NOT NULL AND states.state != old_state.state AND states.state IS NOT NULL AND ((states_meta.entity_id NOT LIKE ?22 AND states_meta.entity_id NOT LIKE ?23 AND states_meta.entity_id NOT LIKE ?24 AND states_meta.entity_id NOT LIKE ?25) OR ((states_meta.entity_id LIKE ?26) AND (state_attributes.shared_attrs NOT LIKE ?27 OR states.attributes NOT LIKE ?28))) AND (states.last_updated_ts = states.last_changed_ts OR states.last_changed_ts IS NULL) ORDER BY time_fired_ts, time_fired_ts;

-- @id ha.logbook.entities
-- @src homeassistant/components/logbook/queries/entities.py:94-113
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note Logbook for 3 entities: CTE of context ids (UNION ALL of events matched by JSON entity_id and states) GROUP BY, then 4-way UNION ALL of events, states and context-linked rows.
-- @param ?1 1789913600.0
-- @param ?2 1790000000.0
-- @param ?3 1
-- @param ?4 2
-- @param ?5 3
-- @param ?6 4
-- @param ?7 5
-- @param ?8 6
-- @param ?9 '$."entity_id"'
-- @param ?10 '$."entity_id"'
-- @param ?11 '"light.e21"'
-- @param ?12 '"switch.e3"'
-- @param ?13 '"binary_sensor.e4"'
-- @param ?14 '$."entity_id"'
-- @param ?15 '$."entity_id"'
-- @param ?16 '"light.e21"'
-- @param ?17 '"switch.e3"'
-- @param ?18 '"binary_sensor.e4"'
-- @param ?19 1789913600.0
-- @param ?20 1790000000.0
-- @param ?21 21
-- @param ?22 3
-- @param ?23 4
-- @param ?24 NULL
-- @param ?25 NULL
-- @param ?26 NULL
-- @param ?27 NULL
-- @param ?28 NULL
-- @param ?29 1789913600.0
-- @param ?30 1790000000.0
-- @param ?31 1
-- @param ?32 2
-- @param ?33 3
-- @param ?34 4
-- @param ?35 5
-- @param ?36 6
-- @param ?37 '$."entity_id"'
-- @param ?38 '$."entity_id"'
-- @param ?39 '"light.e21"'
-- @param ?40 '"switch.e3"'
-- @param ?41 '"binary_sensor.e4"'
-- @param ?42 '$."entity_id"'
-- @param ?43 '$."entity_id"'
-- @param ?44 '"light.e21"'
-- @param ?45 '"switch.e3"'
-- @param ?46 '"binary_sensor.e4"'
-- @param ?47 NULL
-- @param ?48 NULL
-- @param ?49 '$."icon"'
-- @param ?50 '$."icon"'
-- @param ?51 '$."icon"'
-- @param ?52 NULL
-- @param ?53 1789913600.0
-- @param ?54 1790000000.0
-- @param ?55 'counter.%'
-- @param ?56 'image.%'
-- @param ?57 'proximity.%'
-- @param ?58 'sensor.%'
-- @param ?59 'sensor.%'
-- @param ?60 '%"unit_of_measurement":%'
-- @param ?61 '%"unit_of_measurement":%'
-- @param ?62 21
-- @param ?63 3
-- @param ?64 4
-- @param ?65 NULL
-- @param ?66 NULL
-- @param ?67 NULL
-- @param ?68 NULL
-- @param ?69 '1'
-- @param ?70 NULL
-- @param ?71 NULL
-- @param ?72 NULL
-- @param ?73 NULL
-- @param ?74 '1'
WITH anon_1 AS
(SELECT anon_2.context_id_bin AS context_id_bin
FROM (SELECT events.context_id_bin AS context_id_bin
FROM events LEFT OUTER JOIN event_types ON events.event_type_id = event_types.event_type_id LEFT OUTER JOIN event_data ON events.data_id = event_data.data_id
WHERE events.time_fired_ts > ?1 AND events.time_fired_ts < ?2 AND events.event_type_id IN (?3, ?4, ?5, ?6, ?7, ?8) AND (JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?9)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?10)) AS TEXT) IN (?11, ?12, ?13) OR JSON_QUOTE(JSON_EXTRACT(CAST(events.event_data AS TEXT), ?14)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(events.event_data AS TEXT), ?15)) AS TEXT) IN (?16, ?17, ?18)) UNION ALL SELECT states.context_id_bin AS context_id_bin
FROM states
WHERE states.last_updated_ts > ?19 AND states.last_updated_ts < ?20 AND states.metadata_id IN (?21, ?22, ?23)) AS anon_2 GROUP BY anon_2.context_id_bin)
 SELECT events.event_id AS row_id, event_types.event_type AS event_type, CASE WHEN (event_data.shared_data IS NULL) THEN events.event_data ELSE event_data.shared_data END AS event_data, events.time_fired_ts AS time_fired_ts, events.context_id_bin AS context_id_bin, events.context_user_id_bin AS context_user_id_bin, events.context_parent_id_bin AS context_parent_id_bin, ?24 AS state, ?25 AS entity_id, ?26 AS icon, ?27 AS attributes, ?28 AS context_only
FROM events LEFT OUTER JOIN event_types ON events.event_type_id = event_types.event_type_id LEFT OUTER JOIN event_data ON events.data_id = event_data.data_id
WHERE events.time_fired_ts > ?29 AND events.time_fired_ts < ?30 AND events.event_type_id IN (?31, ?32, ?33, ?34, ?35, ?36) AND (JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?37)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?38)) AS TEXT) IN (?39, ?40, ?41) OR JSON_QUOTE(JSON_EXTRACT(CAST(events.event_data AS TEXT), ?42)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(events.event_data AS TEXT), ?43)) AS TEXT) IN (?44, ?45, ?46)) UNION ALL SELECT states.state_id AS row_id, ?47 AS event_type, ?48 AS event_data, states.last_updated_ts AS time_fired_ts, states.context_id_bin AS context_id_bin, states.context_user_id_bin AS context_user_id_bin, states.context_parent_id_bin AS context_parent_id_bin, states.state AS state, states_meta.entity_id AS entity_id, CASE WHEN (JSON_QUOTE(JSON_EXTRACT(CAST(state_attributes.shared_attrs AS TEXT), ?49)) IS NULL) THEN JSON_EXTRACT(CAST(states.attributes AS TEXT), ?50) ELSE JSON_EXTRACT(CAST(state_attributes.shared_attrs AS TEXT), ?51) END AS icon, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes, ?52 AS context_only
FROM states LEFT OUTER JOIN states AS old_state ON states.old_state_id = old_state.state_id LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id LEFT OUTER JOIN states_meta ON states.metadata_id = states_meta.metadata_id
WHERE states.last_updated_ts > ?53 AND states.last_updated_ts < ?54 AND old_state.state_id IS NOT NULL AND states.state != old_state.state AND states.state IS NOT NULL AND ((states_meta.entity_id NOT LIKE ?55 AND states_meta.entity_id NOT LIKE ?56 AND states_meta.entity_id NOT LIKE ?57 AND states_meta.entity_id NOT LIKE ?58) OR ((states_meta.entity_id LIKE ?59) AND (state_attributes.shared_attrs NOT LIKE ?60 OR states.attributes NOT LIKE ?61))) AND (states.last_updated_ts = states.last_changed_ts OR states.last_changed_ts IS NULL) AND states.metadata_id IN (?62, ?63, ?64) UNION ALL SELECT events.event_id AS row_id, event_types.event_type AS event_type, CASE WHEN (event_data.shared_data IS NULL) THEN events.event_data ELSE event_data.shared_data END AS event_data, events.time_fired_ts AS time_fired_ts, events.context_id_bin AS context_id_bin, events.context_user_id_bin AS context_user_id_bin, events.context_parent_id_bin AS context_parent_id_bin, ?65 AS state, ?66 AS entity_id, ?67 AS icon, ?68 AS attributes, ?69 AS context_only
FROM anon_1 LEFT OUTER JOIN events ON anon_1.context_id_bin = events.context_id_bin LEFT OUTER JOIN event_types ON events.event_type_id = event_types.event_type_id LEFT OUTER JOIN event_data ON events.data_id = event_data.data_id UNION ALL SELECT states.state_id AS row_id, ?70 AS event_type, ?71 AS event_data, states.last_updated_ts AS time_fired_ts, states.context_id_bin AS context_id_bin, states.context_user_id_bin AS context_user_id_bin, states.context_parent_id_bin AS context_parent_id_bin, states.state AS state, states_meta.entity_id AS entity_id, ?72 AS icon, ?73 AS attributes, ?74 AS context_only
FROM anon_1 LEFT OUTER JOIN states ON anon_1.context_id_bin = states.context_id_bin LEFT OUTER JOIN states_meta ON states.metadata_id = states_meta.metadata_id ORDER BY time_fired_ts;

-- @id ha.logbook.devices
-- @src homeassistant/components/logbook/queries/devices.py:76-93
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic,hotpath
-- @note Logbook for 2 devices: events matched by JSON device_id, context CTE, linked events and states.
-- @param ?1 1789913600.0
-- @param ?2 1790000000.0
-- @param ?3 1
-- @param ?4 2
-- @param ?5 3
-- @param ?6 4
-- @param ?7 5
-- @param ?8 6
-- @param ?9 '$."device_id"'
-- @param ?10 '$."device_id"'
-- @param ?11 '"dev0003"'
-- @param ?12 '"dev0007"'
-- @param ?13 NULL
-- @param ?14 NULL
-- @param ?15 NULL
-- @param ?16 NULL
-- @param ?17 NULL
-- @param ?18 1789913600.0
-- @param ?19 1790000000.0
-- @param ?20 1
-- @param ?21 2
-- @param ?22 3
-- @param ?23 4
-- @param ?24 5
-- @param ?25 6
-- @param ?26 '$."device_id"'
-- @param ?27 '$."device_id"'
-- @param ?28 '"dev0003"'
-- @param ?29 '"dev0007"'
-- @param ?30 NULL
-- @param ?31 NULL
-- @param ?32 NULL
-- @param ?33 NULL
-- @param ?34 '1'
-- @param ?35 NULL
-- @param ?36 NULL
-- @param ?37 NULL
-- @param ?38 NULL
-- @param ?39 '1'
WITH anon_1 AS
(SELECT anon_2.context_id_bin AS context_id_bin
FROM (SELECT events.context_id_bin AS context_id_bin
FROM events LEFT OUTER JOIN event_types ON events.event_type_id = event_types.event_type_id LEFT OUTER JOIN event_data ON events.data_id = event_data.data_id
WHERE events.time_fired_ts > ?1 AND events.time_fired_ts < ?2 AND events.event_type_id IN (?3, ?4, ?5, ?6, ?7, ?8) AND JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?9)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?10)) AS TEXT) IN (?11, ?12)) AS anon_2 GROUP BY anon_2.context_id_bin)
 SELECT events.event_id AS row_id, event_types.event_type AS event_type, CASE WHEN (event_data.shared_data IS NULL) THEN events.event_data ELSE event_data.shared_data END AS event_data, events.time_fired_ts AS time_fired_ts, events.context_id_bin AS context_id_bin, events.context_user_id_bin AS context_user_id_bin, events.context_parent_id_bin AS context_parent_id_bin, ?13 AS state, ?14 AS entity_id, ?15 AS icon, ?16 AS attributes, ?17 AS context_only
FROM events LEFT OUTER JOIN event_types ON events.event_type_id = event_types.event_type_id LEFT OUTER JOIN event_data ON events.data_id = event_data.data_id
WHERE events.time_fired_ts > ?18 AND events.time_fired_ts < ?19 AND events.event_type_id IN (?20, ?21, ?22, ?23, ?24, ?25) AND JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?26)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?27)) AS TEXT) IN (?28, ?29) UNION ALL SELECT events.event_id AS row_id, event_types.event_type AS event_type, CASE WHEN (event_data.shared_data IS NULL) THEN events.event_data ELSE event_data.shared_data END AS event_data, events.time_fired_ts AS time_fired_ts, events.context_id_bin AS context_id_bin, events.context_user_id_bin AS context_user_id_bin, events.context_parent_id_bin AS context_parent_id_bin, ?30 AS state, ?31 AS entity_id, ?32 AS icon, ?33 AS attributes, ?34 AS context_only
FROM anon_1 LEFT OUTER JOIN events ON anon_1.context_id_bin = events.context_id_bin LEFT OUTER JOIN event_types ON events.event_type_id = event_types.event_type_id LEFT OUTER JOIN event_data ON events.data_id = event_data.data_id UNION ALL SELECT states.state_id AS row_id, ?35 AS event_type, ?36 AS event_data, states.last_updated_ts AS time_fired_ts, states.context_id_bin AS context_id_bin, states.context_user_id_bin AS context_user_id_bin, states.context_parent_id_bin AS context_parent_id_bin, states.state AS state, states_meta.entity_id AS entity_id, ?37 AS icon, ?38 AS attributes, ?39 AS context_only
FROM anon_1 LEFT OUTER JOIN states ON anon_1.context_id_bin = states.context_id_bin LEFT OUTER JOIN states_meta ON states.metadata_id = states_meta.metadata_id ORDER BY time_fired_ts;

-- @id ha.logbook.entities_and_devices
-- @src homeassistant/components/logbook/queries/entities_and_devices.py:102-125
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic
-- @note Logbook for an area (entities + devices): combined JSON entity_id/device_id matchers in a context-id CTE, 4-way UNION ALL.
-- @param ?1 1789913600.0
-- @param ?2 1790000000.0
-- @param ?3 1
-- @param ?4 2
-- @param ?5 3
-- @param ?6 4
-- @param ?7 5
-- @param ?8 6
-- @param ?9 '$."entity_id"'
-- @param ?10 '$."entity_id"'
-- @param ?11 '"light.e21"'
-- @param ?12 '"light.e41"'
-- @param ?13 '$."entity_id"'
-- @param ?14 '$."entity_id"'
-- @param ?15 '"light.e21"'
-- @param ?16 '"light.e41"'
-- @param ?17 '$."device_id"'
-- @param ?18 '$."device_id"'
-- @param ?19 '"dev0003"'
-- @param ?20 1789913600.0
-- @param ?21 1790000000.0
-- @param ?22 21
-- @param ?23 41
-- @param ?24 NULL
-- @param ?25 NULL
-- @param ?26 NULL
-- @param ?27 NULL
-- @param ?28 NULL
-- @param ?29 1789913600.0
-- @param ?30 1790000000.0
-- @param ?31 1
-- @param ?32 2
-- @param ?33 3
-- @param ?34 4
-- @param ?35 5
-- @param ?36 6
-- @param ?37 '$."entity_id"'
-- @param ?38 '$."entity_id"'
-- @param ?39 '"light.e21"'
-- @param ?40 '"light.e41"'
-- @param ?41 '$."entity_id"'
-- @param ?42 '$."entity_id"'
-- @param ?43 '"light.e21"'
-- @param ?44 '"light.e41"'
-- @param ?45 '$."device_id"'
-- @param ?46 '$."device_id"'
-- @param ?47 '"dev0003"'
-- @param ?48 NULL
-- @param ?49 NULL
-- @param ?50 '$."icon"'
-- @param ?51 '$."icon"'
-- @param ?52 '$."icon"'
-- @param ?53 NULL
-- @param ?54 1789913600.0
-- @param ?55 1790000000.0
-- @param ?56 'counter.%'
-- @param ?57 'image.%'
-- @param ?58 'proximity.%'
-- @param ?59 'sensor.%'
-- @param ?60 'sensor.%'
-- @param ?61 '%"unit_of_measurement":%'
-- @param ?62 '%"unit_of_measurement":%'
-- @param ?63 21
-- @param ?64 41
-- @param ?65 NULL
-- @param ?66 NULL
-- @param ?67 NULL
-- @param ?68 NULL
-- @param ?69 '1'
-- @param ?70 NULL
-- @param ?71 NULL
-- @param ?72 NULL
-- @param ?73 NULL
-- @param ?74 '1'
WITH anon_1 AS
(SELECT anon_2.context_id_bin AS context_id_bin
FROM (SELECT events.context_id_bin AS context_id_bin
FROM events LEFT OUTER JOIN event_types ON events.event_type_id = event_types.event_type_id LEFT OUTER JOIN event_data ON events.data_id = event_data.data_id
WHERE events.time_fired_ts > ?1 AND events.time_fired_ts < ?2 AND events.event_type_id IN (?3, ?4, ?5, ?6, ?7, ?8) AND (JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?9)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?10)) AS TEXT) IN (?11, ?12) OR JSON_QUOTE(JSON_EXTRACT(CAST(events.event_data AS TEXT), ?13)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(events.event_data AS TEXT), ?14)) AS TEXT) IN (?15, ?16) OR JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?17)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?18)) AS TEXT) IN (?19)) UNION ALL SELECT states.context_id_bin AS context_id_bin
FROM states
WHERE states.last_updated_ts > ?20 AND states.last_updated_ts < ?21 AND states.metadata_id IN (?22, ?23)) AS anon_2 GROUP BY anon_2.context_id_bin)
 SELECT events.event_id AS row_id, event_types.event_type AS event_type, CASE WHEN (event_data.shared_data IS NULL) THEN events.event_data ELSE event_data.shared_data END AS event_data, events.time_fired_ts AS time_fired_ts, events.context_id_bin AS context_id_bin, events.context_user_id_bin AS context_user_id_bin, events.context_parent_id_bin AS context_parent_id_bin, ?24 AS state, ?25 AS entity_id, ?26 AS icon, ?27 AS attributes, ?28 AS context_only
FROM events LEFT OUTER JOIN event_types ON events.event_type_id = event_types.event_type_id LEFT OUTER JOIN event_data ON events.data_id = event_data.data_id
WHERE events.time_fired_ts > ?29 AND events.time_fired_ts < ?30 AND events.event_type_id IN (?31, ?32, ?33, ?34, ?35, ?36) AND (JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?37)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?38)) AS TEXT) IN (?39, ?40) OR JSON_QUOTE(JSON_EXTRACT(CAST(events.event_data AS TEXT), ?41)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(events.event_data AS TEXT), ?42)) AS TEXT) IN (?43, ?44) OR JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?45)) IS NOT NULL AND CAST(JSON_QUOTE(JSON_EXTRACT(CAST(event_data.shared_data AS TEXT), ?46)) AS TEXT) IN (?47)) UNION ALL SELECT states.state_id AS row_id, ?48 AS event_type, ?49 AS event_data, states.last_updated_ts AS time_fired_ts, states.context_id_bin AS context_id_bin, states.context_user_id_bin AS context_user_id_bin, states.context_parent_id_bin AS context_parent_id_bin, states.state AS state, states_meta.entity_id AS entity_id, CASE WHEN (JSON_QUOTE(JSON_EXTRACT(CAST(state_attributes.shared_attrs AS TEXT), ?50)) IS NULL) THEN JSON_EXTRACT(CAST(states.attributes AS TEXT), ?51) ELSE JSON_EXTRACT(CAST(state_attributes.shared_attrs AS TEXT), ?52) END AS icon, CASE WHEN (state_attributes.shared_attrs IS NULL) THEN states.attributes ELSE state_attributes.shared_attrs END AS attributes, ?53 AS context_only
FROM states LEFT OUTER JOIN states AS old_state ON states.old_state_id = old_state.state_id LEFT OUTER JOIN state_attributes ON states.attributes_id = state_attributes.attributes_id LEFT OUTER JOIN states_meta ON states.metadata_id = states_meta.metadata_id
WHERE states.last_updated_ts > ?54 AND states.last_updated_ts < ?55 AND old_state.state_id IS NOT NULL AND states.state != old_state.state AND states.state IS NOT NULL AND ((states_meta.entity_id NOT LIKE ?56 AND states_meta.entity_id NOT LIKE ?57 AND states_meta.entity_id NOT LIKE ?58 AND states_meta.entity_id NOT LIKE ?59) OR ((states_meta.entity_id LIKE ?60) AND (state_attributes.shared_attrs NOT LIKE ?61 OR states.attributes NOT LIKE ?62))) AND (states.last_updated_ts = states.last_changed_ts OR states.last_changed_ts IS NULL) AND states.metadata_id IN (?63, ?64) UNION ALL SELECT events.event_id AS row_id, event_types.event_type AS event_type, CASE WHEN (event_data.shared_data IS NULL) THEN events.event_data ELSE event_data.shared_data END AS event_data, events.time_fired_ts AS time_fired_ts, events.context_id_bin AS context_id_bin, events.context_user_id_bin AS context_user_id_bin, events.context_parent_id_bin AS context_parent_id_bin, ?65 AS state, ?66 AS entity_id, ?67 AS icon, ?68 AS attributes, ?69 AS context_only
FROM anon_1 LEFT OUTER JOIN events ON anon_1.context_id_bin = events.context_id_bin LEFT OUTER JOIN event_types ON events.event_type_id = event_types.event_type_id LEFT OUTER JOIN event_data ON events.data_id = event_data.data_id UNION ALL SELECT states.state_id AS row_id, ?70 AS event_type, ?71 AS event_data, states.last_updated_ts AS time_fired_ts, states.context_id_bin AS context_id_bin, states.context_user_id_bin AS context_user_id_bin, states.context_parent_id_bin AS context_parent_id_bin, states.state AS state, states_meta.entity_id AS entity_id, ?72 AS icon, ?73 AS attributes, ?74 AS context_only
FROM anon_1 LEFT OUTER JOIN states ON anon_1.context_id_bin = states.context_id_bin LEFT OUTER JOIN states_meta ON states.metadata_id = states_meta.metadata_id ORDER BY time_fired_ts;

-- @id ha.logbook.context_user_ids
-- @src homeassistant/components/logbook/queries/common.py:129-146
-- @style SQLAlchemy 2.0 lambda_stmt compiled for the sqlite dialect; ? positional, IN lists expanded per call
-- @tags dynamic
-- @note Logbook context augmenter: (context_id_bin, context_user_id_bin) for parent contexts from events UNION ALL states.
-- @param ?1 X'019900000000000000000000000F4243'
-- @param ?2 X'019900000000000000000000000F4261'
-- @param ?3 X'019900000000000000000000000F438D'
-- @param ?4 X'019900000000000000000000000F4F45'
-- @param ?5 X'019900000000000000000000000F4243'
-- @param ?6 X'019900000000000000000000000F4261'
-- @param ?7 X'019900000000000000000000000F438D'
-- @param ?8 X'019900000000000000000000000F4F45'
SELECT events.context_id_bin, events.context_user_id_bin
FROM events
WHERE events.context_id_bin IN (?1, ?2, ?3, ?4) AND events.context_user_id_bin IS NOT NULL UNION ALL SELECT states.context_id_bin, states.context_user_id_bin
FROM states
WHERE states.context_id_bin IN (?5, ?6, ?7, ?8) AND states.context_user_id_bin IS NOT NULL;
