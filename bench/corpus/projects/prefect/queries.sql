-- Prefect server on SQLite (PrefectHQ/prefect @ f20489d, Apache-2.0).
-- Every statement was captured, not reconstructed: the pinned server package was installed in a venv, pointed at a
-- copy of this corpus database, and the real API endpoint functions and service loops (dashboard, runs, flows,
-- deployments, workers, scheduler, foreman, events, db_vacuum) were called with the payloads ui-v2 and the services send,
-- while a SQLAlchemy before_cursor_execute listener recorded each statement and its parameters. Python's clock was
-- frozen at 2026-10-30 12:00:00 UTC (the data's "now"); SQL that read 'now' itself is pinned to the same instant (@modified).
-- The aiosqlite dialect sends named binds, so :name placeholders are kept. Timestamps are text
-- 'YYYY-MM-DD HH:MM:SS.ffffff'; intervals are timestamps offset from 1970-01-01.

-- @id prefect.dashboard.any_flow_run
-- @src src/prefect/server/api/flow_runs.py:601-641; src/prefect/server/models/flow_runs.py:282-343
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hot-small,hotpath
-- @note Dashboard loader's emptiness probe (ui-v2 ANY_FLOW_RUNS_FILTER: sort ID_DESC, limit 1), a primary-key walk; the guard. Captured from the pinned server with an event listener.
-- @param :param_1 1
-- @param :param_2 0
SELECT flow_run.flow_id, flow_run.deployment_id, flow_run.work_queue_name, flow_run.flow_version, flow_run.deployment_version, flow_run.parameters, flow_run.idempotency_key, flow_run.context, flow_run.empirical_policy, flow_run.tags, flow_run.labels, flow_run.created_by, flow_run.infrastructure_pid, flow_run.job_variables, flow_run.infrastructure_document_id, flow_run.parent_task_run_id, flow_run.auto_scheduled, flow_run.state_id, flow_run.work_queue_id, flow_run.name, flow_run.state_type, flow_run.state_name, flow_run.state_timestamp, flow_run.run_count, flow_run.expected_start_time, flow_run.next_scheduled_start_time, flow_run.start_time, flow_run.end_time, flow_run.total_run_time, flow_run.id, flow_run.created, flow_run.updated
FROM flow_run ORDER BY flow_run.id DESC
 LIMIT :param_1 OFFSET :param_2;

-- @id prefect.dashboard.flow_runs_last_24h
-- @src src/prefect/server/api/flow_runs.py:601-641; src/prefect/server/models/flow_runs.py:209-343
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics
-- @note Dashboard flow-runs card exactly as ui-v2 sends it (expected_start_time window = last 24 h, sort EXPECTED_START_TIME_DESC, default limit 200): the window is the densest part of a recency-skewed table. Captured from the pinned server with an event listener.
-- @param :expected_start_time_1 '2026-10-30 12:00:00.000000'
-- @param :expected_start_time_2 '2026-10-29 12:00:00.000000'
-- @param :param_1 200
-- @param :param_2 0
SELECT flow_run.flow_id, flow_run.deployment_id, flow_run.work_queue_name, flow_run.flow_version, flow_run.deployment_version, flow_run.parameters, flow_run.idempotency_key, flow_run.context, flow_run.empirical_policy, flow_run.tags, flow_run.labels, flow_run.created_by, flow_run.infrastructure_pid, flow_run.job_variables, flow_run.infrastructure_document_id, flow_run.parent_task_run_id, flow_run.auto_scheduled, flow_run.state_id, flow_run.work_queue_id, flow_run.name, flow_run.state_type, flow_run.state_name, flow_run.state_timestamp, flow_run.run_count, flow_run.expected_start_time, flow_run.next_scheduled_start_time, flow_run.start_time, flow_run.end_time, flow_run.total_run_time, flow_run.id, flow_run.created, flow_run.updated
FROM flow_run
WHERE flow_run.expected_start_time <= :expected_start_time_1 AND flow_run.expected_start_time >= :expected_start_time_2 ORDER BY flow_run.expected_start_time DESC
 LIMIT :param_1 OFFSET :param_2;

-- @id prefect.dashboard.flow_runs_start_time_desc
-- @src src/prefect/server/api/flow_runs.py:601-641; src/prefect/server/models/flow_runs.py:209-343
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,cpu-evidence
-- @note The v1 dashboard query from https://github.com/PrefectHQ/prefect/issues/22916 : 24 h expected_start_time window sorted by coalesce(start_time, expected_start_time) DESC LIMIT 41; no index serves both, so every row in the window is read and top-N sorted. Captured from the pinned server with an event listener.
-- @param :expected_start_time_1 '2026-10-30 12:00:00.000000'
-- @param :expected_start_time_2 '2026-10-29 12:00:00.000000'
-- @param :param_1 41
-- @param :param_2 0
SELECT flow_run.flow_id, flow_run.deployment_id, flow_run.work_queue_name, flow_run.flow_version, flow_run.deployment_version, flow_run.parameters, flow_run.idempotency_key, flow_run.context, flow_run.empirical_policy, flow_run.tags, flow_run.labels, flow_run.created_by, flow_run.infrastructure_pid, flow_run.job_variables, flow_run.infrastructure_document_id, flow_run.parent_task_run_id, flow_run.auto_scheduled, flow_run.state_id, flow_run.work_queue_id, flow_run.name, flow_run.state_type, flow_run.state_name, flow_run.state_timestamp, flow_run.run_count, flow_run.expected_start_time, flow_run.next_scheduled_start_time, flow_run.start_time, flow_run.end_time, flow_run.total_run_time, flow_run.id, flow_run.created, flow_run.updated
FROM flow_run
WHERE flow_run.expected_start_time <= :expected_start_time_1 AND flow_run.expected_start_time >= :expected_start_time_2 ORDER BY coalesce(flow_run.start_time, flow_run.expected_start_time) DESC
 LIMIT :param_1 OFFSET :param_2;

-- @id prefect.dashboard.count_flow_runs_24h
-- @src src/prefect/server/api/flow_runs.py:255-277; src/prefect/server/models/flow_runs.py:435-514
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics
-- @note Dashboard total for the 24 h window (/flow_runs/count): count(*) over an expected_start_time range. Captured from the pinned server with an event listener.
-- @param :expected_start_time_1 '2026-10-30 12:00:00.000000'
-- @param :expected_start_time_2 '2026-10-29 12:00:00.000000'
SELECT count(*) AS count_1
FROM flow_run
WHERE flow_run.expected_start_time <= :expected_start_time_1 AND flow_run.expected_start_time >= :expected_start_time_2;

-- @id prefect.dashboard.failed_runs_prod_tag_no_subflows
-- @src src/prefect/server/api/flow_runs.py:601-641; src/prefect/server/models/flow_runs.py:209-343; src/prefect/server/schemas/filters.py
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics,dynamic
-- @note Dashboard Failed/Crashed tab with the tag filter (all_ ['prod']) and hide-subflows on: the SQLite tags filter is an EXISTS over json_each(flow_run.tags) per row in the window. Captured from the pinned server with an event listener.
-- @param :param_1 'prod'
-- @param :state_type_1_1 'FAILED'
-- @param :state_type_1_2 'CRASHED'
-- @param :expected_start_time_1 '2026-10-30 12:00:00.000000'
-- @param :expected_start_time_2 '2026-10-29 12:00:00.000000'
-- @param :param_2 200
-- @param :param_3 0
SELECT flow_run.flow_id, flow_run.deployment_id, flow_run.work_queue_name, flow_run.flow_version, flow_run.deployment_version, flow_run.parameters, flow_run.idempotency_key, flow_run.context, flow_run.empirical_policy, flow_run.tags, flow_run.labels, flow_run.created_by, flow_run.infrastructure_pid, flow_run.job_variables, flow_run.infrastructure_document_id, flow_run.parent_task_run_id, flow_run.auto_scheduled, flow_run.state_id, flow_run.work_queue_id, flow_run.name, flow_run.state_type, flow_run.state_name, flow_run.state_timestamp, flow_run.run_count, flow_run.expected_start_time, flow_run.next_scheduled_start_time, flow_run.start_time, flow_run.end_time, flow_run.total_run_time, flow_run.id, flow_run.created, flow_run.updated
FROM flow_run
WHERE (SELECT count(DISTINCT anon_1.value) AS count_1
FROM json_each(flow_run.tags) AS anon_1 JOIN json_each(json_array(:param_1)) AS anon_2 ON anon_1.value = anon_2.value) >= (SELECT count(DISTINCT anon_2.value) AS count_2
FROM json_each(json_array(:param_1)) AS anon_2) AND flow_run.state_type IN (:state_type_1_1, :state_type_1_2) AND flow_run.expected_start_time <= :expected_start_time_1 AND flow_run.expected_start_time >= :expected_start_time_2 AND flow_run.parent_task_run_id IS NULL ORDER BY flow_run.expected_start_time DESC
 LIMIT :param_2 OFFSET :param_3;

-- @id prefect.dashboard.task_runs_count_completed
-- @src src/prefect/server/api/task_runs.py:112-131; src/prefect/server/models/task_runs.py:361-416
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics,cpu-evidence
-- @note Dashboard task-run card count (one of four: total/completed/failed/running) over a 24 h start_time window, excluding subflow task runs (NOT EXISTS flow_run.parent_task_run_id). https://github.com/PrefectHQ/prefect/issues/17895 (6M+ task runs, very slow dashboard; PR #20940 added ix_task_run__state_type_start_time). Captured from the pinned server with an event listener.
-- @param :state_type_1_1 'COMPLETED'
-- @param :start_time_1 '2026-10-30 12:00:00.000000'
-- @param :start_time_2 '2026-10-29 12:00:00.000000'
SELECT count(*) AS count_1
FROM task_run
WHERE task_run.state_type IN (:state_type_1_1) AND task_run.start_time <= :start_time_1 AND task_run.start_time >= :start_time_2 AND NOT (EXISTS (SELECT 1
FROM flow_run
WHERE flow_run.parent_task_run_id = task_run.id));

-- @id prefect.dashboard.task_runs_count_total_tagged
-- @src src/prefect/server/api/task_runs.py:112-131; src/prefect/server/models/task_runs.py:361-416
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics,cpu-evidence,dynamic
-- @note Dashboard task-run total with a flow-run tag filter: the JOIN form PR #19548 introduced for https://github.com/PrefectHQ/prefect/issues/19347 (/task_runs/count 10+ s on SQLite), plus the json_each tag EXISTS per joined flow run. Captured from the pinned server with an event listener.
-- @param :param_1 'critical'
-- @param :state_type_1_1 'COMPLETED'
-- @param :state_type_1_2 'FAILED'
-- @param :state_type_1_3 'CRASHED'
-- @param :state_type_1_4 'RUNNING'
-- @param :start_time_1 '2026-10-30 12:00:00.000000'
-- @param :start_time_2 '2026-10-29 12:00:00.000000'
SELECT count(*) AS count_1
FROM task_run JOIN flow_run ON task_run.flow_run_id = flow_run.id
WHERE EXISTS (SELECT *
FROM json_each(flow_run.tags) AS anon_1, json_each(json_array(:param_1)) AS anon_2
WHERE CASE WHEN (json_type(flow_run.tags) = 'object') THEN anon_1."key" ELSE anon_1.value END = anon_2.value) AND task_run.state_type IN (:state_type_1_1, :state_type_1_2, :state_type_1_3, :state_type_1_4) AND task_run.start_time <= :start_time_1 AND task_run.start_time >= :start_time_2 AND NOT (EXISTS (SELECT 1
FROM flow_run
WHERE flow_run.parent_task_run_id = task_run.id));

-- @id prefect.dashboard.task_runs_history_24h
-- @src src/prefect/server/api/run_history.py:26-160; src/prefect/server/database/query_components.py:801-815
-- @modified 'now' pinned to '2026-10-30 12:00:00', the data's \"now\" (data.sql header), so results don't drift with the clock
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics
-- @note Dashboard task-run trend chart (/task_runs/history, 24 h in 20 buckets of 4320 s): SQLite bucket index = floor(round((julianday(ts) - julianday(start)) * 86400, 3) / interval), GROUP BY bucket, state; estimated_run_time / lateness are correlated CASE expressions with strftime('%s'). Captured from the pinned server with an event listener.
-- @param :greatest_1 0
-- @param :greatest_2 0
-- @param :state_type_1 'RUNNING'
-- @param :state_type_2_1 'CRASHED'
-- @param :state_type_2_2 'CANCELLED'
-- @param :state_type_2_3 'FAILED'
-- @param :state_type_2_4 'COMPLETED'
-- @param :param_4 '1970-01-01 00:00:00.000000'
-- @param :param_5 '2026-10-29 12:00:00.000000'
-- @param :round_1 3
-- @param :round_2 4320.0
-- @param :expected_start_time_1 '2026-10-29 12:00:00.000000'
-- @param :expected_start_time_2 '2026-10-30 12:00:00.000000'
-- @param :start_time_1 '2026-10-30 12:00:00.000000'
-- @param :start_time_2 '2026-10-29 12:00:00.000000'
SELECT runs.bucket_index, runs.state_type, runs.state_name, count(runs.id) AS count_runs, sum(max(:greatest_1, CAST(STRFTIME('%s', runs.estimated_run_time) AS INTEGER))) AS sum_estimated_run_time, sum(max(:greatest_2, CAST(STRFTIME('%s', runs.estimated_start_time_delta) AS INTEGER))) AS sum_estimated_lateness
FROM (SELECT task_run.id AS id, task_run.expected_start_time AS expected_start_time, (SELECT CASE WHEN (task_run.state_type = :state_type_1) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(task_run.total_run_time) - 2440587.5) + (julianday(strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) - julianday(task_run.state_timestamp)))) - 2440587.5)) ELSE task_run.total_run_time END AS anon_1) AS estimated_run_time, CASE WHEN (task_run.start_time > task_run.expected_start_time) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(task_run.start_time) - julianday(task_run.expected_start_time))) WHEN (task_run.start_time IS NULL AND (task_run.state_type NOT IN (:state_type_2_1, :state_type_2_2, :state_type_2_3, :state_type_2_4)) AND task_run.expected_start_time < strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) - julianday(task_run.expected_start_time))) ELSE :param_4 END AS estimated_start_time_delta, task_run.state_type AS state_type, task_run.state_name AS state_name, CAST(floor(round((julianday(task_run.expected_start_time) - julianday(:param_5)) * 86400.0, :round_1) / (:round_2 + 0.0)) AS INTEGER) AS bucket_index
FROM task_run
WHERE task_run.expected_start_time >= :expected_start_time_1 AND task_run.expected_start_time < :expected_start_time_2 AND task_run.start_time <= :start_time_1 AND task_run.start_time >= :start_time_2 AND (EXISTS (SELECT flow_run.flow_id, flow_run.deployment_id, flow_run.work_queue_name, flow_run.flow_version, flow_run.deployment_version, flow_run.parameters, flow_run.idempotency_key, flow_run.context, flow_run.empirical_policy, flow_run.tags, flow_run.labels, flow_run.created_by, flow_run.infrastructure_pid, flow_run.job_variables, flow_run.infrastructure_document_id, flow_run.parent_task_run_id, flow_run.auto_scheduled, flow_run.state_id, flow_run.work_queue_id, flow_run.name, flow_run.state_type, flow_run.state_name, flow_run.state_timestamp, flow_run.run_count, flow_run.expected_start_time, flow_run.next_scheduled_start_time, flow_run.start_time, flow_run.end_time, flow_run.total_run_time, flow_run.id, flow_run.created, flow_run.updated
FROM flow_run
WHERE flow_run.id = task_run.flow_run_id))) AS runs GROUP BY runs.bucket_index, runs.state_type, runs.state_name;

-- @id prefect.dashboard.task_run_dashboard_counts
-- @src src/prefect/server/api/ui/task_runs.py:42-161
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics
-- @note v1 UI dashboard task-run counts (/ui/task_runs/dashboard/counts): terminal task runs in 20 time buckets, inner GROUP BY (bucket, start_time) then re-aggregated per bucket, ordered by min(end_time). Captured from the pinned server with an event listener.
-- @param :param_1 '2026-10-29 12:00:00.000000'
-- @param :date_diff_seconds_1 4323.0
-- @param :state_type_1_1 'CRASHED'
-- @param :state_type_1_2 'FAILED'
-- @param :param_3 1
-- @param :param_4 0
-- @param :state_type_2_1 'CRASHED'
-- @param :state_type_2_2 'FAILED'
-- @param :param_5 1
-- @param :param_6 0
-- @param :state_type_3_1 'CRASHED'
-- @param :state_type_3_2 'CANCELLED'
-- @param :state_type_3_3 'FAILED'
-- @param :state_type_3_4 'COMPLETED'
-- @param :start_time_1 '2026-10-30 12:00:00.000000'
-- @param :start_time_2 '2026-10-29 12:00:00.000000'
SELECT anon_1.bucket AS bucket, min(anon_1.oldest) AS oldest, sum(anon_1.failed_count) AS failed_count, sum(anon_1.successful_count) AS successful_count
FROM (SELECT floor((julianday(task_run.start_time) - julianday(:param_1)) * 86400.0 / (:date_diff_seconds_1 + 0.0)) AS bucket, min(task_run.end_time) AS oldest, sum(CASE WHEN (task_run.state_type IN (:state_type_1_1, :state_type_1_2)) THEN :param_3 ELSE :param_4 END) AS failed_count, sum(CASE WHEN ((task_run.state_type NOT IN (:state_type_2_1, :state_type_2_2))) THEN :param_5 ELSE :param_6 END) AS successful_count
FROM task_run
WHERE task_run.state_type IN (:state_type_3_1, :state_type_3_2, :state_type_3_3, :state_type_3_4) AND task_run.start_time <= :start_time_1 AND task_run.start_time >= :start_time_2 AND (EXISTS (SELECT flow_run.flow_id, flow_run.deployment_id, flow_run.work_queue_name, flow_run.flow_version, flow_run.deployment_version, flow_run.parameters, flow_run.idempotency_key, flow_run.context, flow_run.empirical_policy, flow_run.tags, flow_run.labels, flow_run.created_by, flow_run.infrastructure_pid, flow_run.job_variables, flow_run.infrastructure_document_id, flow_run.parent_task_run_id, flow_run.auto_scheduled, flow_run.state_id, flow_run.work_queue_id, flow_run.name, flow_run.state_type, flow_run.state_name, flow_run.state_timestamp, flow_run.run_count, flow_run.expected_start_time, flow_run.next_scheduled_start_time, flow_run.start_time, flow_run.end_time, flow_run.total_run_time, flow_run.id, flow_run.created, flow_run.updated
FROM flow_run
WHERE flow_run.id = task_run.flow_run_id)) GROUP BY bucket, task_run.start_time) AS anon_1 GROUP BY anon_1.bucket ORDER BY oldest ASC;

-- @id prefect.dashboard.flow_run_history_24h_5min
-- @src src/prefect/server/api/flow_runs.py:341-386; src/prefect/server/api/run_history.py:26-160
-- @modified 'now' pinned to '2026-10-30 12:00:00', the data's \"now\" (data.sql header), so results don't drift with the clock
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics,cpu-evidence
-- @note /flow_runs/history at the 24 h / 5-minute view (288 buckets) from https://github.com/PrefectHQ/prefect/issues/22876 (times out on Postgres with 5.2M rows, 96k in 24 h). The SQLite branch has no generate_series join: it buckets each run with julianday arithmetic and groups. Captured from the pinned server with an event listener.
-- @param :greatest_1 0
-- @param :greatest_2 0
-- @param :state_type_1 'RUNNING'
-- @param :state_type_2_1 'CRASHED'
-- @param :state_type_2_2 'CANCELLED'
-- @param :state_type_2_3 'FAILED'
-- @param :state_type_2_4 'COMPLETED'
-- @param :param_4 '1970-01-01 00:00:00.000000'
-- @param :param_5 '2026-10-29 12:00:00.000000'
-- @param :round_1 3
-- @param :round_2 300.0
-- @param :expected_start_time_1 '2026-10-29 12:00:00.000000'
-- @param :expected_start_time_2 '2026-10-30 12:00:00.000000'
SELECT runs.bucket_index, runs.state_type, runs.state_name, count(runs.id) AS count_runs, sum(max(:greatest_1, CAST(STRFTIME('%s', runs.estimated_run_time) AS INTEGER))) AS sum_estimated_run_time, sum(max(:greatest_2, CAST(STRFTIME('%s', runs.estimated_start_time_delta) AS INTEGER))) AS sum_estimated_lateness
FROM (SELECT flow_run.id AS id, flow_run.expected_start_time AS expected_start_time, (SELECT CASE WHEN (flow_run.state_type = :state_type_1) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(flow_run.total_run_time) - 2440587.5) + (julianday(strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) - julianday(flow_run.state_timestamp)))) - 2440587.5)) ELSE flow_run.total_run_time END AS anon_1) AS estimated_run_time, CASE WHEN (flow_run.start_time > flow_run.expected_start_time) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(flow_run.start_time) - julianday(flow_run.expected_start_time))) WHEN (flow_run.start_time IS NULL AND (flow_run.state_type NOT IN (:state_type_2_1, :state_type_2_2, :state_type_2_3, :state_type_2_4)) AND flow_run.expected_start_time < strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) - julianday(flow_run.expected_start_time))) ELSE :param_4 END AS estimated_start_time_delta, flow_run.state_type AS state_type, flow_run.state_name AS state_name, CAST(floor(round((julianday(flow_run.expected_start_time) - julianday(:param_5)) * 86400.0, :round_1) / (:round_2 + 0.0)) AS INTEGER) AS bucket_index
FROM flow_run
WHERE flow_run.expected_start_time >= :expected_start_time_1 AND flow_run.expected_start_time < :expected_start_time_2) AS runs GROUP BY runs.bucket_index, runs.state_type, runs.state_name;

-- @id prefect.deployment.flow_run_history_7d
-- @src src/prefect/server/api/flow_runs.py:341-386; src/prefect/server/api/run_history.py:26-160
-- @modified 'now' pinned to '2026-10-30 12:00:00', the data's \"now\" (data.sql header), so results don't drift with the clock
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics
-- @note Deployment page activity chart: 7 days in hourly buckets, filtered to one hot deployment through EXISTS on deployment.id. Captured from the pinned server with an event listener.
-- @param :greatest_1 0
-- @param :greatest_2 0
-- @param :state_type_1 'RUNNING'
-- @param :state_type_2_1 'CRASHED'
-- @param :state_type_2_2 'CANCELLED'
-- @param :state_type_2_3 'FAILED'
-- @param :state_type_2_4 'COMPLETED'
-- @param :param_4 '1970-01-01 00:00:00.000000'
-- @param :param_5 '2026-10-23 12:00:00.000000'
-- @param :round_1 3
-- @param :round_2 3600.0
-- @param :expected_start_time_1 '2026-10-23 12:00:00.000000'
-- @param :expected_start_time_2 '2026-10-30 12:00:00.000000'
-- @param :id_1_1 '00000002-0000-4000-8000-000000000003'
SELECT runs.bucket_index, runs.state_type, runs.state_name, count(runs.id) AS count_runs, sum(max(:greatest_1, CAST(STRFTIME('%s', runs.estimated_run_time) AS INTEGER))) AS sum_estimated_run_time, sum(max(:greatest_2, CAST(STRFTIME('%s', runs.estimated_start_time_delta) AS INTEGER))) AS sum_estimated_lateness
FROM (SELECT flow_run.id AS id, flow_run.expected_start_time AS expected_start_time, (SELECT CASE WHEN (flow_run.state_type = :state_type_1) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(flow_run.total_run_time) - 2440587.5) + (julianday(strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) - julianday(flow_run.state_timestamp)))) - 2440587.5)) ELSE flow_run.total_run_time END AS anon_1) AS estimated_run_time, CASE WHEN (flow_run.start_time > flow_run.expected_start_time) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(flow_run.start_time) - julianday(flow_run.expected_start_time))) WHEN (flow_run.start_time IS NULL AND (flow_run.state_type NOT IN (:state_type_2_1, :state_type_2_2, :state_type_2_3, :state_type_2_4)) AND flow_run.expected_start_time < strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) - julianday(flow_run.expected_start_time))) ELSE :param_4 END AS estimated_start_time_delta, flow_run.state_type AS state_type, flow_run.state_name AS state_name, CAST(floor(round((julianday(flow_run.expected_start_time) - julianday(:param_5)) * 86400.0, :round_1) / (:round_2 + 0.0)) AS INTEGER) AS bucket_index
FROM flow_run
WHERE flow_run.expected_start_time >= :expected_start_time_1 AND flow_run.expected_start_time < :expected_start_time_2 AND (EXISTS (SELECT deployment.name, deployment.version, deployment.description, deployment.work_queue_name, deployment.infra_overrides, deployment.path, deployment.entrypoint, deployment.last_polled, deployment.status, deployment.flow_id, deployment.work_queue_id, deployment.paused, deployment.concurrency_limit, deployment.concurrency_limit_id, deployment.concurrency_options, deployment.tags, deployment.labels, deployment.parameters, deployment.pull_steps, deployment.parameter_openapi_schema, deployment.enforce_parameter_schema, deployment.created_by, deployment.updated_by, deployment.infrastructure_document_id, deployment.storage_document_id, deployment.id, deployment.created, deployment.updated
FROM deployment
WHERE deployment.id = flow_run.deployment_id AND deployment.id IN (:id_1_1)))) AS runs GROUP BY runs.bucket_index, runs.state_type, runs.state_name;

-- @id prefect.flow.task_runs_history_7d
-- @src src/prefect/server/api/task_runs.py:133-175; src/prefect/server/api/run_history.py:26-160
-- @modified 'now' pinned to '2026-10-30 12:00:00', the data's \"now\" (data.sql header), so results don't drift with the clock
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics
-- @note Flow detail stats (ui-v2 buildTaskRunsHistoryFilterForFlow): task-run history for one flow over 7 days in 20 buckets, the flow filter is an EXISTS through flow_run. Captured from the pinned server with an event listener.
-- @param :greatest_1 0
-- @param :greatest_2 0
-- @param :state_type_1 'RUNNING'
-- @param :state_type_2_1 'CRASHED'
-- @param :state_type_2_2 'CANCELLED'
-- @param :state_type_2_3 'FAILED'
-- @param :state_type_2_4 'COMPLETED'
-- @param :param_4 '1970-01-01 00:00:00.000000'
-- @param :param_5 '2026-10-23 12:00:00.000000'
-- @param :round_1 3
-- @param :round_2 30240.0
-- @param :expected_start_time_1 '2026-10-23 12:00:00.000000'
-- @param :expected_start_time_2 '2026-10-30 12:00:00.000000'
-- @param :start_time_1 '2026-10-30 12:00:00.000000'
-- @param :start_time_2 '2026-10-23 12:00:00.000000'
-- @param :id_1_1 '00000001-0000-4000-8000-000000000002'
SELECT runs.bucket_index, runs.state_type, runs.state_name, count(runs.id) AS count_runs, sum(max(:greatest_1, CAST(STRFTIME('%s', runs.estimated_run_time) AS INTEGER))) AS sum_estimated_run_time, sum(max(:greatest_2, CAST(STRFTIME('%s', runs.estimated_start_time_delta) AS INTEGER))) AS sum_estimated_lateness
FROM (SELECT task_run.id AS id, task_run.expected_start_time AS expected_start_time, (SELECT CASE WHEN (task_run.state_type = :state_type_1) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(task_run.total_run_time) - 2440587.5) + (julianday(strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) - julianday(task_run.state_timestamp)))) - 2440587.5)) ELSE task_run.total_run_time END AS anon_1) AS estimated_run_time, CASE WHEN (task_run.start_time > task_run.expected_start_time) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(task_run.start_time) - julianday(task_run.expected_start_time))) WHEN (task_run.start_time IS NULL AND (task_run.state_type NOT IN (:state_type_2_1, :state_type_2_2, :state_type_2_3, :state_type_2_4)) AND task_run.expected_start_time < strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) THEN strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (julianday(strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00')) - julianday(task_run.expected_start_time))) ELSE :param_4 END AS estimated_start_time_delta, task_run.state_type AS state_type, task_run.state_name AS state_name, CAST(floor(round((julianday(task_run.expected_start_time) - julianday(:param_5)) * 86400.0, :round_1) / (:round_2 + 0.0)) AS INTEGER) AS bucket_index
FROM task_run
WHERE task_run.expected_start_time >= :expected_start_time_1 AND task_run.expected_start_time < :expected_start_time_2 AND task_run.start_time <= :start_time_1 AND task_run.start_time >= :start_time_2 AND (EXISTS (SELECT flow_run.flow_id, flow_run.deployment_id, flow_run.work_queue_name, flow_run.flow_version, flow_run.deployment_version, flow_run.parameters, flow_run.idempotency_key, flow_run.context, flow_run.empirical_policy, flow_run.tags, flow_run.labels, flow_run.created_by, flow_run.infrastructure_pid, flow_run.job_variables, flow_run.infrastructure_document_id, flow_run.parent_task_run_id, flow_run.auto_scheduled, flow_run.state_id, flow_run.work_queue_id, flow_run.name, flow_run.state_type, flow_run.state_name, flow_run.state_timestamp, flow_run.run_count, flow_run.expected_start_time, flow_run.next_scheduled_start_time, flow_run.start_time, flow_run.end_time, flow_run.total_run_time, flow_run.id, flow_run.created, flow_run.updated
FROM flow_run JOIN flow ON flow.id = flow_run.flow_id
WHERE flow_run.id = task_run.flow_run_id AND flow.id IN (:id_1_1)))) AS runs GROUP BY runs.bucket_index, runs.state_type, runs.state_name;

-- @id prefect.dashboard.work_pool_average_lateness
-- @src src/prefect/server/api/flow_runs.py:280-338
-- @modified 'now' pinned to '2026-10-30 12:00:00', the data's \"now\" (data.sql header), so results don't drift with the clock
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics
-- @note Dashboard work-pool card average lateness (/flow_runs/lateness): avg of a CASE over julianday/strftime interval arithmetic for one pool's runs in the window. Captured from the pinned server with an event listener.
-- @param :strftime_1 '%s'
-- @param :strftime_2 '%s'
-- @param :state_type_1_1 'CRASHED'
-- @param :state_type_1_2 'CANCELLED'
-- @param :state_type_1_3 'FAILED'
-- @param :state_type_1_4 'COMPLETED'
-- @param :datetime_1 '2026-10-30 12:00:00'
-- @param :strftime_3 '%s'
-- @param :datetime_2 '2026-10-30 12:00:00'
-- @param :strftime_4 '%s'
-- @param :param_1 0
-- @param :expected_start_time_1 '2026-10-30 12:00:00.000000'
-- @param :expected_start_time_2 '2026-10-29 12:00:00.000000'
-- @param :id_1_1 '00000004-0000-4000-8000-000000000003'
SELECT avg(CASE WHEN (flow_run.start_time > flow_run.expected_start_time) THEN strftime(:strftime_1, flow_run.start_time) - strftime(:strftime_2, flow_run.expected_start_time) WHEN (flow_run.start_time IS NULL AND (flow_run.state_type NOT IN (:state_type_1_1, :state_type_1_2, :state_type_1_3, :state_type_1_4)) AND flow_run.expected_start_time < datetime(:datetime_1)) THEN strftime(:strftime_3, datetime(:datetime_2)) - strftime(:strftime_4, flow_run.expected_start_time) ELSE :param_1 END) AS avg_1
FROM flow_run
WHERE flow_run.expected_start_time <= :expected_start_time_1 AND flow_run.expected_start_time >= :expected_start_time_2 AND (EXISTS (SELECT work_pool.name, work_pool.description, work_pool.type, work_pool.base_job_template, work_pool.is_paused, work_pool.default_queue_id, work_pool.concurrency_limit, work_pool.status, work_pool.last_transitioned_status_at, work_pool.last_status_event_id, work_pool.storage_configuration, work_pool.id, work_pool.created, work_pool.updated
FROM work_pool, work_queue
WHERE work_queue.id = flow_run.work_queue_id AND work_pool.id = work_queue.work_pool_id AND work_pool.id IN (:id_1_1)));

-- @id prefect.dashboard.work_pool_total_runs
-- @src src/prefect/server/api/flow_runs.py:255-277; src/prefect/server/models/flow_runs.py:435-514
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics
-- @note Dashboard work-pool card total: count of terminal runs in the window joined through work_queue to work_pool by name. Captured from the pinned server with an event listener.
-- @param :state_type_1_1 'COMPLETED'
-- @param :state_type_1_2 'FAILED'
-- @param :state_type_1_3 'CRASHED'
-- @param :expected_start_time_1 '2026-10-30 12:00:00.000000'
-- @param :expected_start_time_2 '2026-10-29 12:00:00.000000'
-- @param :name_1_1 'k8s-prod'
SELECT count(*) AS count_1
FROM flow_run JOIN work_queue ON work_queue.id = flow_run.work_queue_id JOIN work_pool ON work_pool.id = work_queue.work_pool_id
WHERE flow_run.state_type IN (:state_type_1_1, :state_type_1_2, :state_type_1_3) AND flow_run.expected_start_time <= :expected_start_time_1 AND flow_run.expected_start_time >= :expected_start_time_2 AND work_pool.name IN (:name_1_1);

-- @id prefect.dashboard.work_pool_recent_runs
-- @src src/prefect/server/api/flow_runs.py:601-641; src/prefect/server/models/flow_runs.py:209-343
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,cpu-evidence
-- @note Work-pool mini bar chart: the pool's 24 most recent runs in the window. Work pool pages listing a busy pool's runs got slower until they stopped loading: https://github.com/PrefectHQ/prefect/issues/16643 . Captured from the pinned server with an event listener.
-- @param :expected_start_time_1 '2026-10-30 12:00:00.000000'
-- @param :expected_start_time_2 '2026-10-29 12:00:00.000000'
-- @param :id_1_1 '00000004-0000-4000-8000-000000000003'
-- @param :param_1 24
-- @param :param_2 0
SELECT flow_run.flow_id, flow_run.deployment_id, flow_run.work_queue_name, flow_run.flow_version, flow_run.deployment_version, flow_run.parameters, flow_run.idempotency_key, flow_run.context, flow_run.empirical_policy, flow_run.tags, flow_run.labels, flow_run.created_by, flow_run.infrastructure_pid, flow_run.job_variables, flow_run.infrastructure_document_id, flow_run.parent_task_run_id, flow_run.auto_scheduled, flow_run.state_id, flow_run.work_queue_id, flow_run.name, flow_run.state_type, flow_run.state_name, flow_run.state_timestamp, flow_run.run_count, flow_run.expected_start_time, flow_run.next_scheduled_start_time, flow_run.start_time, flow_run.end_time, flow_run.total_run_time, flow_run.id, flow_run.created, flow_run.updated
FROM flow_run
WHERE flow_run.expected_start_time <= :expected_start_time_1 AND flow_run.expected_start_time >= :expected_start_time_2 AND (EXISTS (SELECT work_pool.name, work_pool.description, work_pool.type, work_pool.base_job_template, work_pool.is_paused, work_pool.default_queue_id, work_pool.concurrency_limit, work_pool.status, work_pool.last_transitioned_status_at, work_pool.last_status_event_id, work_pool.storage_configuration, work_pool.id, work_pool.created, work_pool.updated
FROM work_pool, work_queue
WHERE work_queue.id = flow_run.work_queue_id AND work_pool.id = work_queue.work_pool_id AND work_pool.id IN (:id_1_1))) ORDER BY flow_run.expected_start_time DESC
 LIMIT :param_1 OFFSET :param_2;

-- @id prefect.runs.paginate_name_search
-- @src src/prefect/server/api/flow_runs.py:1000-1068; src/prefect/server/models/flow_runs.py:209-343
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,dynamic,cpu-evidence
-- @note Runs page search box: lower(name) LIKE lower('%otter%') with a state-name filter, START_TIME_DESC, page 3 (OFFSET 20); a full scan with a top-N sort. The Runs page took up to 35 s on a SQLite server in https://github.com/PrefectHQ/prefect/issues/16304 . Captured from the pinned server with an event listener.
-- @param :name_1 '%otter%'
-- @param :state_name_1_1 'Completed'
-- @param :state_name_1_2 'Failed'
-- @param :param_1 10
-- @param :param_2 20
SELECT flow_run.flow_id, flow_run.deployment_id, flow_run.work_queue_name, flow_run.flow_version, flow_run.deployment_version, flow_run.parameters, flow_run.idempotency_key, flow_run.context, flow_run.empirical_policy, flow_run.tags, flow_run.labels, flow_run.created_by, flow_run.infrastructure_pid, flow_run.job_variables, flow_run.infrastructure_document_id, flow_run.parent_task_run_id, flow_run.auto_scheduled, flow_run.state_id, flow_run.work_queue_id, flow_run.name, flow_run.state_type, flow_run.state_name, flow_run.state_timestamp, flow_run.run_count, flow_run.expected_start_time, flow_run.next_scheduled_start_time, flow_run.start_time, flow_run.end_time, flow_run.total_run_time, flow_run.id, flow_run.created, flow_run.updated
FROM flow_run
WHERE lower(flow_run.name) LIKE lower(:name_1) AND flow_run.state_name IN (:state_name_1_1, :state_name_1_2) ORDER BY coalesce(flow_run.start_time, flow_run.expected_start_time) DESC
 LIMIT :param_1 OFFSET :param_2;

-- @id prefect.runs.paginate_name_search_count
-- @src src/prefect/server/api/flow_runs.py:1000-1068; src/prefect/server/models/flow_runs.py:435-514
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics
-- @note The count half of the same /flow_runs/paginate call: every row's lower(name) LIKE is evaluated. Captured from the pinned server with an event listener.
-- @param :name_1 '%otter%'
-- @param :state_name_1_1 'Completed'
-- @param :state_name_1_2 'Failed'
SELECT count(*) AS count_1
FROM flow_run
WHERE lower(flow_run.name) LIKE lower(:name_1) AND flow_run.state_name IN (:state_name_1_1, :state_name_1_2);

-- @id prefect.runs.flow_run_graph_v2
-- @src src/prefect/server/database/query_components.py:908-1060
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,cpu-evidence
-- @note Flow run graph (graph-v2), SQLite builder: edges CTE over task_run x json_each(task_inputs) x json_each(argument), three json_group_array CTEs, DISTINCT, for a 600-task run. Polled every second by open run pages; 68 % of DB time in https://github.com/PrefectHQ/prefect/issues/23430 . Captured from the pinned server with an event listener.
-- @param :param_1 'flow-run'
-- @param :param_2 'task-run'
-- @param :name_1 ' / '
-- @param :state_type_1 'COMPLETED'
-- @param :json_extract_1 '$.id'
-- @param :key_1 '__parents__'
-- @param :flow_run_id '00000007-0000-4000-8000-000000002ee0'
-- @param :since '0001-01-01 00:00:00.000000'
-- @param :max_nodes 10001
-- @param :param_3 0
WITH edges AS
(SELECT CASE WHEN (flow_run.id IS NOT NULL) THEN :param_1 ELSE :param_2 END AS kind, coalesce(flow_run.id, task_run.id) AS id, coalesce(flow.name || :name_1 || flow_run.name, task_run.name) AS label, coalesce(flow_run.state_type, task_run.state_type) AS state_type, coalesce(flow_run.start_time, flow_run.expected_start_time, task_run.start_time, task_run.expected_start_time) AS start_time, coalesce(flow_run.end_time, task_run.end_time, CASE WHEN (task_run.state_type = :state_type_1) THEN task_run.expected_start_time ELSE NULL END) AS end_time, json_extract(argument.value, :json_extract_1) AS parent, input."key" = :key_1 AS has_encapsulating_task
FROM task_run LEFT OUTER JOIN json_each(task_run.task_inputs) AS input ON 1 = 1 LEFT OUTER JOIN json_each(input.value) AS argument ON 1 = 1 LEFT OUTER JOIN flow_run ON flow_run.parent_task_run_id = task_run.id LEFT OUTER JOIN flow ON flow.id = flow_run.flow_id
WHERE task_run.flow_run_id = :flow_run_id AND coalesce(flow_run.start_time, flow_run.expected_start_time, task_run.start_time, task_run.expected_start_time) IS NOT NULL ORDER BY coalesce(flow_run.id, task_run.id)),
with_parents AS
(SELECT children.id AS id, json_group_array(parents.id) AS parent_ids
FROM edges AS children JOIN edges AS parents ON parents.id = children.parent
WHERE children.has_encapsulating_task IS NOT 1 GROUP BY children.id),
with_children AS
(SELECT parents.id AS id, json_group_array(children.id) AS child_ids
FROM edges AS parents JOIN edges AS children ON children.parent = parents.id
WHERE children.has_encapsulating_task IS NOT 1 GROUP BY parents.id),
with_encapsulating AS
(SELECT children.id AS id, json_group_array(parents.id) AS encapsulating_ids
FROM edges AS children JOIN edges AS parents ON parents.id = children.parent
WHERE children.has_encapsulating_task IS 1 GROUP BY children.id),
nodes AS
(SELECT DISTINCT edges.kind AS kind, edges.id AS id, edges.label AS label, edges.state_type AS state_type, edges.start_time AS start_time, edges.end_time AS end_time, with_parents.parent_ids AS parent_ids, with_children.child_ids AS child_ids, with_encapsulating.encapsulating_ids AS encapsulating_ids
FROM edges LEFT OUTER JOIN with_parents ON with_parents.id = edges.id LEFT OUTER JOIN with_children ON with_children.id = edges.id LEFT OUTER JOIN with_encapsulating ON with_encapsulating.id = edges.id)
 SELECT nodes.kind, nodes.id, nodes.label, nodes.state_type, nodes.start_time, nodes.end_time, nodes.parent_ids AS parent_ids, nodes.child_ids AS child_ids, nodes.encapsulating_ids AS encapsulating_ids
FROM nodes
WHERE nodes.end_time IS NULL OR nodes.end_time >= :since ORDER BY nodes.start_time, nodes.end_time
 LIMIT :max_nodes OFFSET :param_3;

-- @id prefect.runs.logs_for_flow_run
-- @src src/prefect/server/api/logs.py:44-60; src/prefect/server/models/logs.py:91-120
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hot-small,hotpath
-- @note Flow run page log pane: logs of one run at level >= INFO by timestamp (ix_log__flow_run_id_timestamp). Captured from the pinned server with an event listener.
-- @param :level_1 20
-- @param :flow_run_id_1_1 '00000007-0000-4000-8000-000000002ed6'
-- @param :param_1 200
-- @param :param_2 0
SELECT log.name, log.level, log.flow_run_id, log.task_run_id, log.message, log.timestamp, log.id, log.created, log.updated
FROM log
WHERE log.level >= :level_1 AND log.flow_run_id IN (:flow_run_id_1_1) ORDER BY log.timestamp ASC
 LIMIT :param_1 OFFSET :param_2;

-- @id prefect.flows.next_runs
-- @src src/prefect/server/api/ui/flows.py:111-178
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics
-- @note Flows page next-run column, the SQLite-specific text query: min(next_scheduled_start_time) per flow in a CTE, then a window-ranked join back to flow_run to pick the run. Captured from the pinned server with an event listener.
-- @param :flow_ids_1 '00000001-0000-4000-8000-000000000001'
-- @param :flow_ids_2 '00000001-0000-4000-8000-000000000002'
-- @param :flow_ids_3 '00000001-0000-4000-8000-000000000003'
-- @param :flow_ids_4 '00000001-0000-4000-8000-000000000004'
-- @param :flow_ids_5 '00000001-0000-4000-8000-000000000005'
-- @param :flow_ids_6 '00000001-0000-4000-8000-000000000006'
-- @param :flow_ids_7 '00000001-0000-4000-8000-000000000007'
-- @param :flow_ids_8 '00000001-0000-4000-8000-000000000008'
-- @param :flow_ids_9 '00000001-0000-4000-8000-000000000009'
-- @param :flow_ids_10 '00000001-0000-4000-8000-00000000000a'
WITH min_times AS (
            SELECT flow_id, MIN(next_scheduled_start_time) AS min_next_scheduled_start_time
            FROM flow_run
            WHERE flow_id IN (:flow_ids_1, :flow_ids_2, :flow_ids_3, :flow_ids_4, :flow_ids_5, :flow_ids_6, :flow_ids_7, :flow_ids_8, :flow_ids_9, :flow_ids_10)
            AND state_type = 'SCHEDULED'
            GROUP BY flow_id
        )
        SELECT fr.id, fr.name, fr.flow_id, fr.state_name, fr.state_type, fr.next_scheduled_start_time
        FROM flow_run fr
        JOIN min_times mt ON fr.flow_id = mt.flow_id AND fr.next_scheduled_start_time = mt.min_next_scheduled_start_time
        WHERE fr.state_type = 'SCHEDULED';;

-- @id prefect.deployments.filter_by_failed_runs
-- @src src/prefect/server/api/deployments.py:519-556; src/prefect/server/models/deployments.py:507-624
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags dynamic
-- @note Deployments that have a FAILED flow run: an EXISTS per deployment over flow_run by deployment_id with a state_type predicate. Captured from the pinned server with an event listener.
-- @param :state_type_1_1 'FAILED'
-- @param :param_1 200
-- @param :param_2 0
SELECT deployment.name, deployment.version, deployment.description, deployment.work_queue_name, deployment.infra_overrides, deployment.path, deployment.entrypoint, deployment.last_polled, deployment.status, deployment.flow_id, deployment.work_queue_id, deployment.paused, deployment.concurrency_limit, deployment.concurrency_limit_id, deployment.concurrency_options, deployment.tags, deployment.labels, deployment.parameters, deployment.pull_steps, deployment.parameter_openapi_schema, deployment.enforce_parameter_schema, deployment.created_by, deployment.updated_by, deployment.infrastructure_document_id, deployment.storage_document_id, deployment.id, deployment.created, deployment.updated
FROM deployment
WHERE EXISTS (SELECT flow_run.flow_id, flow_run.deployment_id, flow_run.work_queue_name, flow_run.flow_version, flow_run.deployment_version, flow_run.parameters, flow_run.idempotency_key, flow_run.context, flow_run.empirical_policy, flow_run.tags, flow_run.labels, flow_run.created_by, flow_run.infrastructure_pid, flow_run.job_variables, flow_run.infrastructure_document_id, flow_run.parent_task_run_id, flow_run.auto_scheduled, flow_run.state_id, flow_run.work_queue_id, flow_run.name, flow_run.state_type, flow_run.state_name, flow_run.state_timestamp, flow_run.run_count, flow_run.expected_start_time, flow_run.next_scheduled_start_time, flow_run.start_time, flow_run.end_time, flow_run.total_run_time, flow_run.id, flow_run.created, flow_run.updated
FROM flow_run
WHERE deployment.id = flow_run.deployment_id AND flow_run.state_type IN (:state_type_1_1)) ORDER BY deployment.name ASC
 LIMIT :param_1 OFFSET :param_2;

-- @id prefect.workers.get_scheduled_flow_runs
-- @src src/prefect/server/database/sql/sqlite/get-runs-from-worker-queues.sql.jinja; src/prefect/server/database/query_components.py:255-350
-- @style Jinja-rendered SQL text executed through SQLAlchemy text(); :name binds as sent, IN list expanded per call
-- @tags hotpath,analytics
-- @note Worker poll (/work_pools/{name}/get_scheduled_flow_runs), rendered from the SQLite Jinja template: pool and queue slot counts via LEFT JOIN flow_run GROUP BY, two ROW_NUMBER() windows over scheduled runs. Every worker sends it every few seconds. Captured from the pinned server with an event listener.
-- @param :scheduled_before '2026-10-30 12:00:10.000000'
-- @param :queue_limit 1000
-- @param :work_pool_ids_1 '00000004-0000-4000-8000-000000000003'
-- @param :worker_limit 1000
-- @param :limit 10
WITH worker_slots AS (
    SELECT
        wp.id,
        MAX(0, wp.concurrency_limit - count(fr.id)) AS available_slots
    FROM
        work_pool wp
        JOIN work_queue wq ON wq.work_pool_id = wp.id
        LEFT JOIN flow_run fr ON wq.id = fr.work_queue_id
            AND fr.state_type in('RUNNING', 'PENDING')
    WHERE
        wp.is_paused IS FALSE
        AND wp.concurrency_limit IS NOT NULL
    GROUP BY
        wp.id
),
-- compute available slots under worker pool queue concurrency limits
queue_slots AS (
    SELECT
        wq.id,
        MAX(0, wq.concurrency_limit - count(fr.id)) AS available_slots
    FROM
        work_queue wq
    LEFT JOIN flow_run fr ON wq.id = fr.work_queue_id
        AND fr.state_type in('RUNNING', 'PENDING')
WHERE
    wq.is_paused IS FALSE
    AND wq.concurrency_limit IS NOT NULL
GROUP BY
    wq.id
),
-- CTE that loads flow runs and applies worker pool queue limits
scheduled_flow_runs AS (
    SELECT
        wp.id AS run_work_pool_id,
        wq.id AS run_work_queue_id,
        fr.*,
        worker_slots.available_slots as available_worker_slots,
        ROW_NUMBER() OVER (PARTITION BY wp.id ORDER BY wq.priority ASC, fr.next_scheduled_start_time) AS work_pool_rank
    FROM
        work_pool wp
        JOIN work_queue wq ON wq.work_pool_id = wp.id
        LEFT JOIN worker_slots ON wp.id = worker_slots.id
        LEFT JOIN queue_slots ON wq.id = queue_slots.id
        JOIN (
            SELECT
                fr.*,
                ROW_NUMBER() OVER (PARTITION BY work_queue_id ORDER BY next_scheduled_start_time) AS work_queue_rank
            FROM flow_run fr
            WHERE fr.state_type = 'SCHEDULED'
            AND (json_extract(fr.empirical_policy, '$.retry_type') IS NULL OR json_extract(fr.empirical_policy, '$.retry_type') != 'in_process')
                                    AND fr.next_scheduled_start_time <= :scheduled_before
                        ) fr
        ON
            fr.work_queue_id = wq.id
            AND work_queue_rank <= MIN(COALESCE(queue_slots.available_slots, :queue_limit), :queue_limit)
    WHERE
        wp.is_paused IS FALSE
        AND wq.is_paused IS FALSE
                -- optionally filter for specific worker pool IDs
        AND wp.id IN (:work_pool_ids_1)
            )
SELECT
    *
FROM scheduled_flow_runs
WHERE
    work_pool_rank <= MIN(COALESCE(available_worker_slots, :worker_limit), :worker_limit)
ORDER BY
    work_pool_rank ASC,
        next_scheduled_start_time ASC
LIMIT :limit;

-- @id prefect.scheduler.deployments_to_schedule
-- @src src/prefect/server/services/scheduler.py:35-127
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags analytics,cpu-evidence
-- @note Scheduler service loop: deployments with an active schedule that has < 3 future auto-scheduled runs or whose last is < 1 h out, two correlated count/max subqueries per schedule on json_extract(created_by, '$.id'). The scheduler loop timing out on big state tables: https://github.com/PrefectHQ/prefect/issues/15045 . Captured from the pinned server with an event listener.
-- @param :param_1 1
-- @param :state_type_1 'SCHEDULED'
-- @param :next_scheduled_start_time_1 '2026-10-30 12:00:00.000000'
-- @param :param_2 '$."id"'
-- @param :param_3 3
-- @param :state_type_2 'SCHEDULED'
-- @param :next_scheduled_start_time_2 '2026-10-30 12:00:00.000000'
-- @param :param_4 '2026-10-30 13:00:00.000000'
-- @param :param_5 100
-- @param :param_6 0
SELECT deployment.id
FROM deployment
WHERE deployment.paused IS NOT 1 AND (EXISTS (SELECT :param_1 AS anon_1
FROM deployment_schedule
WHERE deployment_schedule.deployment_id = deployment.id AND deployment_schedule.active IS 1 AND ((SELECT count(*) AS count_1
FROM flow_run
WHERE flow_run.deployment_id = deployment_schedule.deployment_id AND flow_run.state_type = :state_type_1 AND flow_run.next_scheduled_start_time >= :next_scheduled_start_time_1 AND flow_run.auto_scheduled = 1 AND CAST(JSON_EXTRACT(flow_run.created_by, :param_2) AS VARCHAR) = CAST(deployment_schedule.id AS VARCHAR)) < :param_3 OR (SELECT max(flow_run.next_scheduled_start_time) AS max_1
FROM flow_run
WHERE flow_run.deployment_id = deployment_schedule.deployment_id AND flow_run.state_type = :state_type_2 AND flow_run.next_scheduled_start_time >= :next_scheduled_start_time_2 AND flow_run.auto_scheduled = 1 AND CAST(JSON_EXTRACT(flow_run.created_by, :param_2) AS VARCHAR) = CAST(deployment_schedule.id AS VARCHAR)) < :param_4))) ORDER BY deployment.id
 LIMIT :param_5 OFFSET :param_6;

-- @id prefect.scheduler.recent_deployments
-- @src src/prefect/server/services/scheduler.py:130-167
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags cpu-evidence
-- @note RecentDeploymentsScheduler loop (every 5 s): deployments updated in the last 6 s with an active schedule. It overran its interval (7.5 s vs 5 s) in https://github.com/PrefectHQ/prefect/issues/16299 . Captured from the pinned server with an event listener.
-- @param :updated_1 '2026-10-30 11:59:54.000000'
-- @param :param_1 100
-- @param :param_2 0
SELECT deployment.id
FROM deployment
WHERE deployment.paused IS NOT 1 AND deployment.updated >= :updated_1 AND (EXISTS (SELECT deployment_schedule.deployment_id
FROM deployment_schedule
WHERE deployment_schedule.deployment_id = deployment.id AND deployment_schedule.active IS 1)) ORDER BY deployment.id
 LIMIT :param_1 OFFSET :param_2;

-- @id prefect.events.count_by_hour
-- @src src/prefect/server/events/counting.py:110-265; src/prefect/server/events/storage/database.py:72-95
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,analytics
-- @note Event feed histogram (/events/count-by/time, hourly, 7 days): strftime('%s') bucketing in SQLite, GROUP BY value+label, first_value() window over the groups, re-aggregated. Captured from the pinned server with an event listener.
-- @param :strftime_1 '%s'
-- @param :strftime_2 '%s'
-- @param :strftime_3 '2024-04-01 00:00:00'
-- @param :param_1 3600.0
-- @param :strftime_4 '%Y-%m-%dT%H:%M:%SZ'
-- @param :strftime_5 '%s'
-- @param :param_2 3600.0
-- @param :param_3 3600.0
-- @param :datetime_1 'unixepoch'
-- @param :occurred_1 '2026-10-23 12:00:00.000000'
-- @param :occurred_2 '2026-10-30 12:00:00.000000'
SELECT with_latest_labels.value AS value, with_latest_labels.label AS label, sum(with_latest_labels.count) AS count, min(with_latest_labels.oldest) AS start_time, max(with_latest_labels.latest) AS end_time
FROM (SELECT fundamental_counts.value AS value, first_value(fundamental_counts.label) OVER (PARTITION BY fundamental_counts.value ORDER BY fundamental_counts.latest DESC) AS label, fundamental_counts.latest AS latest, fundamental_counts.oldest AS oldest, fundamental_counts.count AS count
FROM (SELECT CAST(floor(CAST(strftime(:strftime_1, events.occurred) - strftime(:strftime_2, :strftime_3) AS INTEGER) / (:param_1 + 0.0)) AS TEXT) AS value, strftime(:strftime_4, datetime(CAST((CAST(strftime(:strftime_5, events.occurred) AS INTEGER) / (:param_2 + 0.0)) * :param_3 AS INTEGER), :datetime_1)) AS label, max(events.occurred) AS latest, min(events.occurred) AS oldest, count(*) AS count
FROM events
WHERE events.occurred >= :occurred_1 AND events.occurred <= :occurred_2 GROUP BY value, label) AS fundamental_counts) AS with_latest_labels GROUP BY with_latest_labels.value, with_latest_labels.label ORDER BY start_time ASC;

-- @id prefect.events.read_for_deployment
-- @src src/prefect/server/events/storage/database.py:130-198; src/prefect/server/events/filters.py
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hotpath,dynamic
-- @note Event feed filtered to flow-run events related to one deployment in the last 24 h: resource_id LIKE prefix plus an IN-subquery over event_resources by resource_id and role. Captured from the pinned server with an event listener.
-- @param :occurred_1 '2026-10-29 12:00:00.000000'
-- @param :occurred_2 '2026-10-30 12:00:00.000000'
-- @param :resource_id_1 'prefect.flow-run.'
-- @param :occurred_3 '2026-10-29 12:00:00.000000'
-- @param :occurred_4 '2026-10-30 12:00:00.000000'
-- @param :resource_id_2_1 'prefect.deployment.00000002-0000-4000-8000-000000000003'
-- @param :resource_role_1 ''
-- @param :param_1 50
-- @param :param_2 0
SELECT events.occurred, events.event, events.resource_id, events.resource, events.related_resource_ids, events.related, events.payload, events.received, events.recorded, events.follows, events.id, events.created, events.updated
FROM events
WHERE events.occurred >= :occurred_1 AND events.occurred <= :occurred_2 AND (events.resource_id LIKE :resource_id_1 || '%') AND events.id IN (SELECT event_resources.event_id
FROM event_resources
WHERE event_resources.occurred >= :occurred_3 AND event_resources.occurred <= :occurred_4 AND event_resources.resource_id IN (:resource_id_2_1) AND event_resources.resource_role != :resource_role_1) ORDER BY events.occurred DESC
 LIMIT :param_1 OFFSET :param_2;

-- @id prefect.vacuum.old_event_resources
-- @src src/prefect/server/services/db_vacuum.py:385-424,594-616
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags batch
-- @note Event retention (db_vacuum, 7-day default): delete event_resources older than the cutoff in batches of 200 via id IN (SELECT ... LIMIT). Captured from the pinned server with an event listener.
-- @param :occurred_1 '2026-10-23 12:00:00.000000'
-- @param :param_1 200
-- @param :param_2 0
DELETE FROM event_resources WHERE event_resources.id IN (SELECT event_resources.id
FROM event_resources
WHERE event_resources.occurred < :occurred_1
 LIMIT :param_1 OFFSET :param_2) RETURNING id;

-- @id prefect.vacuum.old_flow_run_batch
-- @src src/prefect/server/services/db_vacuum.py:264-329,426-457
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags analytics
-- @note Flow-run retention (db_vacuum flow_runs, here with a 30-day retention): top-level terminal runs that ended before the cutoff, ordered by id, LIMIT 200 (FOR UPDATE SKIP LOCKED drops out on SQLite). Captured from the pinned server with an event listener.
-- @param :state_type_1_1 'CRASHED'
-- @param :state_type_1_2 'CANCELLED'
-- @param :state_type_1_3 'FAILED'
-- @param :state_type_1_4 'COMPLETED'
-- @param :end_time_1 '2026-10-10 12:00:00.000000'
-- @param :param_1 200
-- @param :param_2 0
SELECT flow_run.id
FROM flow_run
WHERE flow_run.parent_task_run_id IS NULL AND flow_run.state_type IN (:state_type_1_1, :state_type_1_2, :state_type_1_3, :state_type_1_4) AND flow_run.end_time IS NOT NULL AND flow_run.end_time < :end_time_1 ORDER BY flow_run.id
 LIMIT :param_1 OFFSET :param_2;

-- @id prefect.foreman.mark_workers_offline
-- @src src/prefect/server/services/foreman.py:71-109
-- @modified 'now' pinned to '2026-10-30 12:00:00', the data's \"now\" (data.sql header), so results don't drift with the clock
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hot-small
-- @note Foreman loop: mark ONLINE workers whose last heartbeat is older than 3 heartbeat intervals OFFLINE (julianday('now') arithmetic). Captured from the pinned server with an event listener.
-- @param :status 'OFFLINE'
-- @param :default_interval 30
-- @param :multiplier 3
-- @param :status_1 'ONLINE'
UPDATE worker SET status=:status, updated=strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00') WHERE (julianday('2026-10-30 12:00:00') - julianday(worker.last_heartbeat_time)) * 86400.0 > coalesce(worker.heartbeat_interval_seconds, :default_interval) * :multiplier AND worker.status = :status_1 RETURNING id;

-- @id prefect.concurrency.bulk_increment_active_slots
-- @src src/prefect/server/models/concurrency_limits_v2.py:254-280
-- @modified 'now' pinned to '2026-10-30 12:00:00', the data's \"now\" (data.sql header), so results don't drift with the clock
-- @style SQLAlchemy 2.0 Core compiled by the sqlite dialect (aiosqlite); :name binds as sent, IN lists expanded per call
-- @tags hot-small,hotpath
-- @note Global concurrency slot acquire: decay active slots by elapsed time, then add 1 if under the limit, for two limits in one UPDATE. Captured from the pinned server with an event listener.
-- @param :greatest_1 0
-- @param :greatest_2 1
-- @param :greatest_3 0
-- @param :slot_decay_per_second_1 0.0
-- @param :greatest_4 1.0
-- @param :param_3 0.1
-- @param :name_1 'tag:%'
-- @param :param_4 10.0
-- @param :param_5 30.0
-- @param :id_1_1 '00000010-0000-4000-8000-000000000001'
-- @param :id_1_2 '00000010-0000-4000-8000-00000000000b'
-- @param :greatest_5 1
UPDATE concurrency_limit_v2 SET active_slots=(max(:greatest_1, concurrency_limit_v2.active_slots - floor(concurrency_limit_v2.slot_decay_per_second * (julianday('2026-10-30 12:00:00') - julianday(concurrency_limit_v2.updated)) * 86400.0)) + :greatest_2), denied_slots=max(:greatest_3, concurrency_limit_v2.denied_slots - floor(CASE WHEN (concurrency_limit_v2.slot_decay_per_second > :slot_decay_per_second_1) THEN concurrency_limit_v2.slot_decay_per_second ELSE :greatest_4 / (max(:param_3, min(CAST(concurrency_limit_v2.avg_slot_occupancy_seconds AS FLOAT), CASE WHEN (concurrency_limit_v2.name LIKE :name_1) THEN :param_4 ELSE :param_5 END)) + 0.0) END * (julianday('2026-10-30 12:00:00') - julianday(concurrency_limit_v2.updated)) * 86400.0)), updated=strftime('%Y-%m-%d %H:%M:%f000', '2026-10-30 12:00:00') WHERE concurrency_limit_v2.id IN (:id_1_1, :id_1_2) AND concurrency_limit_v2.active = 1 AND max(:greatest_1, concurrency_limit_v2.active_slots - floor(concurrency_limit_v2.slot_decay_per_second * (julianday('2026-10-30 12:00:00') - julianday(concurrency_limit_v2.updated)) * 86400.0)) + :greatest_5 <= concurrency_limit_v2."limit";
