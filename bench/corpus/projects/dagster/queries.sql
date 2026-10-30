-- Dagster storage queries (dagster-io/dagster @ 05ed5f2cd6ae62c880740265978ccd23aaddb507, Apache-2.0).
-- Every statement was captured, not written by hand: the pinned storage classes (SqliteRunStorage,
-- SqliteScheduleStorage, SqliteEventLogStorage) were called with the corpus's parameter values and each SQL string
-- and its bind parameters were recorded with a SQLAlchemy before_cursor_execute listener. The sqlite dialect sends
-- ? placeholders; they are numbered ?N in order. Timestamps bind as 'YYYY-MM-DD HH:MM:SS.ffffff' strings, as
-- SQLAlchemy's SQLite DateTime type stores them. "Now" is 2026-10-30 00:00:00 UTC.

-- @id dagster.ticks.batch_latest_per_sensor
-- @src python_modules/dagster/dagster/_core/storage/schedules/sql_schedule_storage.py:287-335
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics,cpu-evidence
-- @note Automation page: latest tick of all 11 sensors in one statement, rank() OVER (PARTITION BY selector_id ORDER BY timestamp DESC) over every retained tick of every sensor (~57k rows), then rank <= 1. The Automation page taking 3-6 minutes on SQLite is https://github.com/dagster-io/dagster/issues/30172. Captured SQL (compiled by the real builder).
-- @param ?1 '9e3779b185ebca7ec2b2ae4827d4eb3c165667c2'
-- @param ?2 '3c6ef3620bd794f585655c854fa9d66b2caccf73'
-- @param ?3 'daa66d1391c35f6c48180ac2777ec19a43033724'
-- @param ?4 '78dde6c417af29e30acab8ff9f53acc959599ed5'
-- @param ?5 '171560759d9af45acd7d673cc72897f86fb00686'
-- @param ?6 'b54cda262386bed190301579eefd832786066e37'
-- @param ?7 '538453d7a972894852e2c3b616d26e569c5cd5e8'
-- @param ?8 'f1bbcd882f5e53bf159571f33ea75985b2b33d99'
-- @param ?9 '8ff34739b54a1e36d8482030667c44b4c909a54a'
-- @param ?10 '2e2ac0ea3b35e8ad9aface6d8e512fe3df600cfb'
-- @param ?11 'cc623a9bc121b3245dad7caab6261b12f5b674ac'
-- @param ?12 1
SELECT subquery.id, subquery.selector_id, subquery.tick_body
FROM (SELECT job_ticks.id AS id, job_ticks.selector_id AS selector_id, job_ticks.tick_body AS tick_body, rank() OVER (PARTITION BY job_ticks.selector_id ORDER BY job_ticks.timestamp DESC) AS rank
FROM job_ticks
WHERE job_ticks.selector_id IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)) AS subquery
WHERE subquery.rank <= ?12 ORDER BY subquery.rank ASC;

-- @id dagster.ticks.latest_or_legacy_origin
-- @src python_modules/dagster/dagster/_core/storage/schedules/sql_schedule_storage.py:427-461
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,cpu-evidence
-- @note Latest tick for one sensor (sensor page, daemon each iteration). The OR with the legacy selector_id IS NULL branch stops idx_tick_selector_timestamp from being read in order, so all ~20k ticks of the 30 s sensor are sorted for LIMIT 1. Timeouts in https://github.com/dagster-io/dagster/issues/15102 and https://github.com/dagster-io/dagster/issues/27745; fix proposed in https://github.com/dagster-io/dagster/pull/34265; SQLite slowness in https://github.com/dagster-io/dagster/issues/30172. Captured SQL (compiled by the real builder).
-- @param ?1 '9e3779b185ebca7ec2b2ae4827d4eb3c165667c2'
-- @param ?2 '1656681627d4eb96c2b2aea885ebcae49e377a22'
-- @param ?3 1
-- @param ?4 0
SELECT job_ticks.id, job_ticks.tick_body
FROM job_ticks
WHERE job_ticks.selector_id = ?1 OR job_ticks.selector_id IS NULL AND job_ticks.job_origin_id = ?2 ORDER BY job_ticks.timestamp DESC
 LIMIT ?3 OFFSET ?4;

-- @id dagster.ticks.history_success_failure
-- @src python_modules/dagster/dagster/_core/storage/schedules/sql_schedule_storage.py:427-461
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,cpu-evidence
-- @note Sensor page tick history filtered to SUCCESS/FAILURE, 25 rows: the same OR predicate plus a status IN filter, tick bodies sorted by timestamp. Same _ticks_query as https://github.com/dagster-io/dagster/pull/34265. Captured SQL (compiled by the real builder).
-- @param ?1 '9e3779b185ebca7ec2b2ae4827d4eb3c165667c2'
-- @param ?2 '1656681627d4eb96c2b2aea885ebcae49e377a22'
-- @param ?3 'SUCCESS'
-- @param ?4 'FAILURE'
-- @param ?5 25
-- @param ?6 0
SELECT job_ticks.id, job_ticks.tick_body
FROM job_ticks
WHERE (job_ticks.selector_id = ?1 OR job_ticks.selector_id IS NULL AND job_ticks.job_origin_id = ?2) AND job_ticks.status IN (?3, ?4) ORDER BY job_ticks.timestamp DESC
 LIMIT ?5 OFFSET ?6;

-- @id dagster.ticks.summaries_24h
-- @src python_modules/dagster/dagster/_core/storage/schedules/sql_schedule_storage.py:427-461
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics,cpu-evidence
-- @note Sensor tick timeline for the last 24 h (get_tick_summaries, no LIMIT): ~2900 ticks of a 30 s sensor through the OR predicate with a timestamp range, sorted DESC. _ticks_query is the subject of https://github.com/dagster-io/dagster/pull/34265. Captured SQL (compiled by the real builder).
-- @param ?1 '9e3779b185ebca7ec2b2ae4827d4eb3c165667c2'
-- @param ?2 '1656681627d4eb96c2b2aea885ebcae49e377a22'
-- @param ?3 '2026-10-29 00:00:00.000000'
SELECT job_ticks.id, job_ticks.job_origin_id, job_ticks.type, job_ticks.status, job_ticks.timestamp
FROM job_ticks
WHERE (job_ticks.selector_id = ?1 OR job_ticks.selector_id IS NULL AND job_ticks.job_origin_id = ?2) AND job_ticks.timestamp > ?3 ORDER BY job_ticks.timestamp DESC;

-- @id dagster.ticks.purge_skipped
-- @src python_modules/dagster/dagster/_core/storage/schedules/sql_schedule_storage.py:507-540
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic
-- @note Sensor daemon retention: delete this sensor's SKIPPED ticks older than 7 days (default sensor retention), with the same OR on selector/origin. The daemon runs it after every tick, so it removes the one tick that has just aged out, but it still has to find the candidates through the OR. Captured SQL (compiled by the real builder).
-- @param ?1 '2026-10-23 00:00:00.000000'
-- @param ?2 'SKIPPED'
-- @param ?3 '9e3779b185ebca7ec2b2ae4827d4eb3c165667c2'
-- @param ?4 '1656681627d4eb96c2b2aea885ebcae49e377a22'
DELETE FROM job_ticks WHERE job_ticks.timestamp < ?1 AND job_ticks.status IN (?2) AND (job_ticks.selector_id = ?3 OR job_ticks.selector_id IS NULL AND job_ticks.job_origin_id = ?4);

-- @id dagster.instigators.sensor_states
-- @src python_modules/dagster/dagster/_core/storage/schedules/sql_schedule_storage.py:76-109
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hot-small,hotpath
-- @note Instigator states for a repository's sensors (Automation page, sensor daemon). Small table, no index on repository_selector_id: a guard. Captured SQL (compiled by the real builder).
-- @param ?1 '6f1c0e4a3b9d2f7e8a5c4b3d2e1f0a9b8c7d6e5f'
-- @param ?2 'SENSOR'
SELECT instigators.instigator_body
FROM instigators
WHERE instigators.repository_selector_id = ?1 AND instigators.instigator_type = ?2;

-- @id dagster.runs.sensor_runs_by_tags
-- @src python_modules/dagster/dagster/_core/storage/runs/sql_run_storage.py:379-397
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,join,cpu-evidence
-- @note Sensor page 'latest run': runs JOIN run_tags twice (dagster/sensor_name, .dagster/repository), ORDER BY runs.id DESC LIMIT 1. sqlite_stat1 says ~5 rows per (key, value) on idx_run_tags, but .dagster/repository is on every run, so the planner probes the second alias through idx_run_tags (key, value) once per sensor run: ~700 x 3.5k = 2.5M index rows at scale 1, 16x more at scale 4 (seconds), where probing by run_id would read ~5 rows each. This exact statement timed out in https://github.com/dagster-io/dagster/issues/27745; slow Last Run column in https://github.com/dagster-io/dagster/issues/30172. Captured SQL (compiled by the real builder).
-- @param ?1 'dagster/sensor_name'
-- @param ?2 's3_landing_sensor'
-- @param ?3 '.dagster/repository'
-- @param ?4 '__repository__@analytics_pipelines'
-- @param ?5 1
-- @param ?6 0
SELECT runs.id, runs.run_body, runs.status, runs.create_timestamp, runs.update_timestamp, runs.start_time, runs.end_time
FROM runs JOIN run_tags AS run_tags_filter0 ON runs.run_id = run_tags_filter0.run_id AND run_tags_filter0."key" = ?1 AND run_tags_filter0.value = ?2 JOIN run_tags AS run_tags_filter1 ON runs.run_id = run_tags_filter1.run_id AND run_tags_filter1."key" = ?3 AND run_tags_filter1.value = ?4 ORDER BY runs.id DESC
 LIMIT ?5 OFFSET ?6;

-- @id dagster.runs.sensor_runs_count
-- @src python_modules/dagster/dagster/_core/storage/runs/sql_run_storage.py:421-426
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics,cpu-evidence
-- @note runsCount for a sensor: count(*) over a subquery that still carries ORDER BY runs.id DESC and run_body. Same sensor page as https://github.com/dagster-io/dagster/issues/27745. Captured SQL (compiled by the real builder).
-- @param ?1 'dagster/sensor_name'
-- @param ?2 's3_landing_sensor'
SELECT count(*) AS count
FROM (SELECT runs.run_body AS run_body, runs.status AS status
FROM runs JOIN run_tags AS run_tags_filter0 ON runs.run_id = run_tags_filter0.run_id AND run_tags_filter0."key" = ?1 AND run_tags_filter0.value = ?2 ORDER BY runs.id DESC) AS subquery;

-- @id dagster.runs.list_latest
-- @src python_modules/dagster/dagster/_core/storage/runs/sql_run_storage.py:273-296
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hot-small,hotpath
-- @note Runs page first page: 26 newest runs by id. Guard. Captured SQL (compiled by the real builder).
-- @param ?1 26
-- @param ?2 0
SELECT runs.id, runs.run_body, runs.status, runs.create_timestamp, runs.update_timestamp, runs.start_time, runs.end_time
FROM runs ORDER BY runs.id DESC
 LIMIT ?1 OFFSET ?2;

-- @id dagster.runs.count_in_progress
-- @src python_modules/dagster/dagster/_core/storage/runs/sql_run_storage.py:421-426
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics
-- @note In-progress run count polled by the UI (run status badge) and the run coordinator: count over status IN via idx_run_status. Captured SQL (compiled by the real builder).
-- @param ?1 'QUEUED'
-- @param ?2 'STARTING'
-- @param ?3 'STARTED'
-- @param ?4 'CANCELING'
SELECT count(*) AS count
FROM (SELECT runs.run_body AS run_body, runs.status AS status
FROM runs
WHERE runs.status IN (?1, ?2, ?3, ?4) ORDER BY runs.id DESC) AS subquery;

-- @id dagster.runs.timeline_24h
-- @src python_modules/dagster/dagster/_core/storage/runs/sql_run_storage.py:304-350
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics
-- @note Overview run timeline: every run created in the last 24 h (no LIMIT) with bodies, ORDER BY id DESC. create_timestamp has no index of its own, so it scans runs. Captured SQL (compiled by the real builder).
-- @param ?1 '2026-10-29 00:00:00.000000'
-- @param ?2 '2026-10-30 00:00:00.000000'
SELECT runs.id, runs.run_body, runs.status, runs.create_timestamp, runs.update_timestamp, runs.start_time, runs.end_time
FROM runs
WHERE runs.create_timestamp > ?1 AND runs.create_timestamp < ?2 ORDER BY runs.id DESC;

-- @id dagster.runs.tag_values_typeahead
-- @src python_modules/dagster/dagster/_core/storage/runs/sql_run_storage.py:483-503
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics
-- @note Runs page filter typeahead: DISTINCT (key, value) for three tag keys, ordered. Captured SQL (compiled by the real builder).
-- @param ?1 'dagster/sensor_name'
-- @param ?2 'dagster/schedule_name'
-- @param ?3 'team'
SELECT DISTINCT run_tags."key", run_tags.value
FROM run_tags
WHERE run_tags."key" IN (?1, ?2, ?3) ORDER BY run_tags."key", run_tags.value;

-- @id dagster.runs.tag_keys
-- @src python_modules/dagster/dagster/_core/storage/runs/sql_run_storage.py:505-508
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,analytics
-- @note All distinct run tag keys (filter menu): DISTINCT over run_tags. Captured SQL (compiled by the real builder).
SELECT DISTINCT run_tags."key"
FROM run_tags ORDER BY run_tags."key";

-- @id dagster.runs.job_partition_status
-- @src python_modules/dagster/dagster/_core/storage/runs/sql_run_storage.py:702-743
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics,cpu-evidence
-- @note Job partitions page: every run of partitioned_job_1 with its partition (~410 runs: daily schedule plus a 365-partition backfill), via the partition_set tag join; deduplicated in Python. Very slow partitions page: https://github.com/dagster-io/dagster/issues/10330. Captured SQL (compiled by the real builder).
-- @param ?1 'dagster/partition_set'
-- @param ?2 'partitioned_job_1_partition_set'
-- @param ?3 'partitioned_job_1'
SELECT runs.run_id, runs.status, runs.start_time, runs.end_time, runs.partition
FROM runs JOIN run_tags AS run_tags_filter0 ON runs.run_id = run_tags_filter0.run_id AND run_tags_filter0."key" = ?1 AND run_tags_filter0.value = ?2
WHERE runs.pipeline_name = ?3 ORDER BY runs.id DESC;

-- @id dagster.runs.backfill_runs
-- @src python_modules/dagster/dagster/_core/storage/runs/sql_run_storage.py:379-397
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath
-- @note Backfill page: all runs of backfill bfkqzrtw (365) via the dagster/backfill tag join, ordered by id DESC, with bodies. Captured SQL (compiled by the real builder).
-- @param ?1 'dagster/backfill'
-- @param ?2 'bfkqzrtw'
SELECT runs.id, runs.run_body, runs.status, runs.create_timestamp, runs.update_timestamp, runs.start_time, runs.end_time
FROM runs JOIN run_tags AS run_tags_filter0 ON runs.run_id = run_tags_filter0.run_id AND run_tags_filter0."key" = ?1 AND run_tags_filter0.value = ?2 ORDER BY runs.id DESC;

-- @id dagster.events.run_stats
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:616-679
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics
-- @note Run stats: count(*) and max(timestamp) per event type for one run, event types in a 14-item IN list. Captured SQL (compiled by the real builder).
-- @param ?1 'e532fe4a-dfc6-4977-a676-8a4a4b78c442'
-- @param ?2 'STEP_EXPECTATION_RESULT'
-- @param ?3 'RUN_RESUMED'
-- @param ?4 'PIPELINE_FAILURE'
-- @param ?5 'PIPELINE_CANCELED'
-- @param ?6 'ASSET_MATERIALIZATION'
-- @param ?7 'RUN_SUSPENDED'
-- @param ?8 'PIPELINE_STARTING'
-- @param ?9 'PIPELINE_START'
-- @param ?10 'PIPELINE_DEQUEUED'
-- @param ?11 'PIPELINE_CANCELING'
-- @param ?12 'STEP_FAILURE'
-- @param ?13 'PIPELINE_ENQUEUED'
-- @param ?14 'STEP_SUCCESS'
-- @param ?15 'PIPELINE_SUCCESS'
SELECT event_logs.dagster_event_type, count(*) AS n_events_of_type, max(event_logs.timestamp) AS last_event_timestamp
FROM event_logs
WHERE event_logs.run_id = ?1 AND event_logs.dagster_event_type IN (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15) GROUP BY event_logs.dagster_event_type;

-- @id dagster.events.run_step_stats_events
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:681-722
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath
-- @note Step stats for a run: every step event body of the run (step_key IS NOT NULL, 14 event types), ordered by id. Captured SQL (compiled by the real builder).
-- @param ?1 'e532fe4a-dfc6-4977-a676-8a4a4b78c442'
-- @param ?2 'STEP_EXPECTATION_RESULT'
-- @param ?3 'ENGINE_EVENT'
-- @param ?4 'STEP_WORKER_STARTED'
-- @param ?5 'STEP_SKIPPED'
-- @param ?6 'RESOURCE_INIT_SUCCESS'
-- @param ?7 'STEP_START'
-- @param ?8 'STEP_RESTARTED'
-- @param ?9 'STEP_UP_FOR_RETRY'
-- @param ?10 'RESOURCE_INIT_STARTED'
-- @param ?11 'ASSET_MATERIALIZATION'
-- @param ?12 'STEP_WORKER_STARTING'
-- @param ?13 'RESOURCE_INIT_FAILURE'
-- @param ?14 'STEP_SUCCESS'
-- @param ?15 'STEP_FAILURE'
SELECT event_logs.event
FROM event_logs
WHERE event_logs.run_id = ?1 AND event_logs.step_key IS NOT NULL AND event_logs.dagster_event_type IN (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15) ORDER BY event_logs.id ASC;

-- @id dagster.events.run_log
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:419-510
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath
-- @note Run logs page: the run's events in id order, LIMIT 1000. Captured SQL (compiled by the real builder).
-- @param ?1 'e532fe4a-dfc6-4977-a676-8a4a4b78c442'
-- @param ?2 1000
-- @param ?3 0
SELECT event_logs.id, event_logs.event
FROM event_logs
WHERE event_logs.run_id = ?1 ORDER BY event_logs.id ASC
 LIMIT ?2 OFFSET ?3;

-- @id dagster.events.asset_materializations_latest
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:1018-1070
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath
-- @note Asset page: 25 latest materializations of a daily-partitioned asset via idx_events_by_asset. Captured SQL (compiled by the real builder).
-- @param ?1 'ASSET_MATERIALIZATION'
-- @param ?2 '["warehouse", "fct_customers_1"]'
-- @param ?3 25
-- @param ?4 0
SELECT event_logs.id, event_logs.event
FROM event_logs
WHERE event_logs.dagster_event_type = ?1 AND event_logs.asset_key = ?2 ORDER BY event_logs.id DESC
 LIMIT ?3 OFFSET ?4;

-- @id dagster.events.asset_materialized_partitions
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:1963-1998
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics
-- @note Partition status: max(id) per partition of the asset's materializations (~410 partitions). Captured SQL (compiled by the real builder).
-- @param ?1 '["warehouse", "fct_customers_1"]'
-- @param ?2 'ASSET_MATERIALIZATION'
SELECT event_logs.partition, max(event_logs.id) AS max_1
FROM event_logs
WHERE event_logs.asset_key = ?1 AND event_logs.partition IS NOT NULL AND event_logs.dagster_event_type = ?2 GROUP BY event_logs.partition;

-- @id dagster.events.latest_storage_id_by_partition
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:2045-2083
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,analytics
-- @note Asset daemon / partition health: latest materialization storage id per partition, a GROUP BY subquery over the asset's events. Captured SQL (compiled by the real builder).
-- @param ?1 '["warehouse", "fct_customers_1"]'
-- @param ?2 'ASSET_MATERIALIZATION'
SELECT latest_event_ids_by_partition_subquery.partition, latest_event_ids_by_partition_subquery.id
FROM (SELECT event_logs.dagster_event_type AS dagster_event_type, event_logs.partition AS partition, max(event_logs.id) AS id
FROM event_logs
WHERE event_logs.asset_key = ?1 AND event_logs.partition IS NOT NULL AND event_logs.dagster_event_type IN (?2) GROUP BY event_logs.dagster_event_type, event_logs.partition) AS latest_event_ids_by_partition_subquery;

-- @id dagster.events.latest_data_version_by_partition
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:2085-2142
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,analytics,join
-- @note Data versions per partition: GROUP BY latest event per partition, joined to asset_event_tags for dagster/data_version. Captured SQL (compiled by the real builder).
-- @param ?1 '["warehouse", "fct_customers_1"]'
-- @param ?2 'ASSET_MATERIALIZATION'
-- @param ?3 'dagster/data_version'
SELECT latest_event_ids_by_partition_subquery.partition, asset_event_tags."key", asset_event_tags.value
FROM (SELECT event_logs.dagster_event_type AS dagster_event_type, event_logs.partition AS partition, max(event_logs.id) AS id
FROM event_logs
WHERE event_logs.asset_key = ?1 AND event_logs.partition IS NOT NULL AND event_logs.dagster_event_type IN (?2) GROUP BY event_logs.dagster_event_type, event_logs.partition) AS latest_event_ids_by_partition_subquery JOIN asset_event_tags ON asset_event_tags.event_id = latest_event_ids_by_partition_subquery.id
WHERE asset_event_tags."key" IN (?3);

-- @id dagster.events.planned_without_materialization
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:2144-2223
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics
-- @note In-progress/failed partitions: latest ASSET_MATERIALIZATION and ASSET_MATERIALIZATION_PLANNED per partition, joined back to event_logs, filtered to planned-without-materialization. Two nested GROUP BY subqueries. Captured SQL (compiled by the real builder).
-- @param ?1 '["warehouse", "fct_customers_1"]'
-- @param ?2 'ASSET_MATERIALIZATION'
-- @param ?3 'ASSET_MATERIALIZATION_PLANNED'
-- @param ?4 'ASSET_MATERIALIZATION_PLANNED'
SELECT latest_events_subquery.dagster_event_type, latest_events_subquery.partition, latest_events_subquery.run_id, latest_events_subquery.id
FROM (SELECT event_logs.dagster_event_type AS dagster_event_type, event_logs.partition AS partition, event_logs.run_id AS run_id, event_logs.id AS id
FROM (SELECT event_logs.dagster_event_type AS dagster_event_type, event_logs.partition AS partition, max(event_logs.id) AS id
FROM event_logs
WHERE event_logs.asset_key = ?1 AND event_logs.partition IS NOT NULL AND event_logs.dagster_event_type IN (?2, ?3) GROUP BY event_logs.dagster_event_type, event_logs.partition) AS latest_event_ids_by_partition_subquery JOIN event_logs ON event_logs.id = latest_event_ids_by_partition_subquery.id) AS latest_events_subquery
WHERE latest_events_subquery.dagster_event_type = ?4;

-- @id dagster.events.asset_records_backcompat_latest
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:1283-1364
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics,join
-- @note Asset catalog: for assets whose asset_keys row has no stored last materialization (10 observed sources, 2 legacy rows), max(id) per asset_key over materializations, joined back to event_logs for the body. Captured SQL (compiled by the real builder).
-- @param ?1 '["marts", "customers_61"]'
-- @param ?2 '["marts", "payments_62"]'
-- @param ?3 '["sources", "clicks_118"]'
-- @param ?4 '["sources", "events_112"]'
-- @param ?5 '["sources", "inventory_113"]'
-- @param ?6 '["sources", "invoices_116"]'
-- @param ?7 '["sources", "orders_120"]'
-- @param ?8 '["sources", "products_117"]'
-- @param ?9 '["sources", "refunds_115"]'
-- @param ?10 '["sources", "sessions_111"]'
-- @param ?11 '["sources", "shipments_114"]'
-- @param ?12 '["sources", "subscriptions_119"]'
-- @param ?13 'ASSET_MATERIALIZATION'
SELECT event_logs.asset_key, event_logs.id, event_logs.event
FROM (SELECT event_logs.asset_key AS asset_key, max(event_logs.id) AS id
FROM event_logs
WHERE event_logs.asset_key IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12) AND event_logs.dagster_event_type = ?13 GROUP BY event_logs.asset_key) AS latest_event_subquery JOIN event_logs ON event_logs.asset_key = latest_event_subquery.asset_key AND event_logs.id = latest_event_subquery.id;

-- @id dagster.events.data_version_changes_by_partition
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:3626-3713
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,analytics,window
-- @note Asset daemon staleness: rank() OVER (PARTITION BY partition ORDER BY id DESC) over materializations/observations of 30 partitions after a storage id, joined to asset_event_tags data versions. Captured SQL (compiled by the real builder).
-- @param ?1 'ASSET_MATERIALIZATION'
-- @param ?2 'ASSET_OBSERVATION'
-- @param ?3 '["warehouse", "fct_customers_1"]'
-- @param ?4 '2026-10-28'
-- @param ?5 '2026-10-27'
-- @param ?6 '2026-10-26'
-- @param ?7 '2026-10-25'
-- @param ?8 '2026-10-24'
-- @param ?9 '2026-10-23'
-- @param ?10 '2026-10-22'
-- @param ?11 '2026-10-21'
-- @param ?12 '2026-10-20'
-- @param ?13 '2026-10-19'
-- @param ?14 '2026-10-18'
-- @param ?15 '2026-10-17'
-- @param ?16 '2026-10-16'
-- @param ?17 '2026-10-15'
-- @param ?18 '2026-10-14'
-- @param ?19 '2026-10-13'
-- @param ?20 '2026-10-12'
-- @param ?21 '2026-10-11'
-- @param ?22 '2026-10-10'
-- @param ?23 '2026-10-09'
-- @param ?24 '2026-10-08'
-- @param ?25 '2026-10-07'
-- @param ?26 '2026-10-06'
-- @param ?27 '2026-10-05'
-- @param ?28 '2026-10-04'
-- @param ?29 '2026-10-03'
-- @param ?30 '2026-10-02'
-- @param ?31 '2026-10-01'
-- @param ?32 '2026-09-30'
-- @param ?33 '2026-09-29'
-- @param ?34 115211
-- @param ?35 'dagster/data_version'
-- @param ?36 '["warehouse", "fct_customers_1"]'
-- @param ?37 115211
-- @param ?38 1
SELECT data_version_by_partition_subquery.partition, data_version_by_partition_subquery.value
FROM (SELECT partition_subquery.partition AS partition, data_version_subquery.value AS value, rank() OVER (PARTITION BY partition_subquery.partition ORDER BY partition_subquery.id DESC) AS rank
FROM (SELECT event_logs.partition AS partition, event_logs.id AS id
FROM event_logs
WHERE (event_logs.dagster_event_type = ?1 OR event_logs.dagster_event_type = ?2) AND event_logs.asset_key = ?3 AND event_logs.partition IN (?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33) AND event_logs.id > ?34) AS partition_subquery JOIN (SELECT asset_event_tags.event_id AS event_id, asset_event_tags.value AS value
FROM asset_event_tags
WHERE asset_event_tags."key" = ?35 AND asset_event_tags.asset_key = ?36 AND asset_event_tags.event_id > ?37) AS data_version_subquery ON data_version_subquery.event_id = partition_subquery.id) AS data_version_by_partition_subquery
WHERE data_version_by_partition_subquery.rank = ?38 ORDER BY data_version_by_partition_subquery.rank ASC;

-- @id dagster.checks.latest_execution_per_check
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:3407-3469
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath,analytics
-- @note Asset check status: max(id) GROUP BY asset_key, check_name over 10 check keys, joined back to asset_check_executions. Captured SQL (compiled by the real builder).
-- @param ?1 '["marts", "customers_61"]'
-- @param ?2 '["marts", "customers_61"]'
-- @param ?3 '["marts", "payments_62"]'
-- @param ?4 '["marts", "payments_62"]'
-- @param ?5 '["marts", "sessions_63"]'
-- @param ?6 '["marts", "sessions_63"]'
-- @param ?7 '["marts", "events_64"]'
-- @param ?8 '["marts", "events_64"]'
-- @param ?9 '["marts", "inventory_65"]'
-- @param ?10 '["marts", "inventory_65"]'
-- @param ?11 'not_null'
-- @param ?12 'freshness_within_2h'
-- @param ?13 'not_null'
-- @param ?14 'freshness_within_2h'
-- @param ?15 'not_null'
-- @param ?16 'freshness_within_2h'
-- @param ?17 'not_null'
-- @param ?18 'freshness_within_2h'
-- @param ?19 'not_null'
-- @param ?20 'freshness_within_2h'
SELECT asset_check_executions.id, asset_check_executions.asset_key, asset_check_executions.check_name, asset_check_executions.run_id, asset_check_executions.execution_status, asset_check_executions.evaluation_event, asset_check_executions.create_timestamp, asset_check_executions.partition
FROM asset_check_executions JOIN (SELECT max(asset_check_executions.id) AS id
FROM asset_check_executions
WHERE asset_check_executions.asset_key IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10) AND asset_check_executions.check_name IN (?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20) GROUP BY asset_check_executions.asset_key, asset_check_executions.check_name) AS subquery ON asset_check_executions.id = subquery.id;

-- @id dagster.events.materializations_after_cursor
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:1018-1070
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hotpath
-- @note Sensors and the asset daemon consuming new materializations after a storage-id cursor, 1000 at a time, via idx_event_type. Captured SQL (compiled by the real builder).
-- @param ?1 'ASSET_MATERIALIZATION'
-- @param ?2 112438
-- @param ?3 1000
-- @param ?4 0
SELECT event_logs.id, event_logs.event
FROM event_logs
WHERE event_logs.dagster_event_type = ?1 AND event_logs.id > ?2 ORDER BY event_logs.id ASC
 LIMIT ?3 OFFSET ?4;

-- @id dagster.events.max_storage_id
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:1247-1253
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hot-small
-- @note Max storage id (cursor initialisation). Guard. Captured SQL (compiled by the real builder).
SELECT max(event_logs.id) AS max_1
FROM event_logs;

-- @id dagster.events.delete_run_events
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:805-829
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic
-- @note Run deletion: delete the run's events (a backfill run, ~50 rows) via idx_events_by_run_id. Captured SQL (compiled by the real builder).
-- @param ?1 '1d184c36-19ba-459a-bf0a-c0369e1ea43e'
DELETE FROM event_logs WHERE event_logs.run_id = ?1;

-- @id dagster.assets.asset_details_lookup
-- @src python_modules/dagster/dagster/_core/storage/event_log/sql_event_log.py:1757-1782
-- @style SQLAlchemy Core, captured from the pinned storage method (sqlite dialect, ? positional, IN lists expanded)
-- @tags dynamic,hot-small,hotpath
-- @note Asset details lookup that precedes every asset-scoped event query (wipe timestamps). Guard. Captured SQL (compiled by the real builder).
-- @param ?1 '["warehouse", "fct_customers_1"]'
SELECT asset_keys.asset_key, asset_keys.asset_details
FROM asset_keys
WHERE asset_keys.asset_key IN (?1);
