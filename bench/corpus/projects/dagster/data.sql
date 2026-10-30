-- Synthetic data for Dagster's SQLite storage (runs, schedules/ticks, event log index). Deterministic: values come
-- from multiplicative hashes of row counters, no random(). "Now" is 2026-10-30 00:00:00 UTC (1793318400).
-- One code location (__repository__@analytics_pipelines) with 11 sensors and 6 schedules:
--   * 2 heavy sensors tick every 30 s (as in dagster#30172), a third every 2 min; each launches 10-12 runs/day;
--   * 4 medium sensors tick every 5-15 min, 4 light ones hourly; one medium sensor observes 10 source assets;
--   * an hourly schedule (5 assets + asset checks), 4 daily partitioned schedules (6 daily-partitioned assets each),
--     a weekly schedule; plus a 365-partition backfill (one run per partition) and a cancelled 120-partition one.
-- Scale 1 keeps 45 days of runs/events (history days = 45 * scale). Ticks follow Dagster's default retention:
-- schedule ticks and SUCCESS/FAILURE sensor ticks are kept forever, SKIPPED sensor ticks for 7 days; the two fastest
-- sensors tick every 30/scale seconds. Rough scale-1 counts: ~5.5k runs, ~33k run_tags, ~190k
-- event_logs (incl. ~40k asset materializations/observations), ~40k asset_event_tags, ~7k asset check executions,
-- ~75k job_ticks. Event and tick bodies are serdes JSON in Dagster's shape but trimmed (~250-450 bytes instead of
-- ~1-2 KB) to keep the database small; no query parses them.
BEGIN;

CREATE TEMP TABLE _k AS SELECT 1793318400 AS now_s, 45 * (SELECT scale FROM _cfg) AS days,
  '__repository__@analytics_pipelines' AS repo_label,
  '6f1c0e4a3b9d2f7e8a5c4b3d2e1f0a9b8c7d6e5f' AS repo_selector;

-- ---- instigators -------------------------------------------------------------------------------------------
-- run_every_s: spacing of the runs it launches (0 = never launches runs). first_asset/nassets: the job's assets.
CREATE TEMP TABLE _inst(n INTEGER PRIMARY KEY, name TEXT, kind TEXT, interval_s INTEGER, run_every_s INTEGER,
                        job TEXT, first_asset INTEGER, nassets INTEGER, team TEXT);
INSERT INTO _inst VALUES
 (1,'s3_landing_sensor','SENSOR',30,8640,'ingest_landing_job',31,3,'data-eng'),
 (2,'kafka_offsets_sensor','SENSOR',30,8640,'ingest_kafka_job',34,3,'data-eng'),
 (3,'api_poll_sensor','SENSOR',120,7200,'ingest_api_job',37,3,'data-eng'),
 (4,'dbt_freshness_sensor','SENSOR',300,43200,'dbt_staging_job',40,4,'analytics'),
 (5,'warehouse_sla_sensor','SENSOR',900,43200,'staging_rebuild_job',44,4,'analytics'),
 (6,'file_drop_sensor','SENSOR',900,43200,'observe_sources_job',111,10,'data-eng'),
 (7,'slack_alert_sensor','SENSOR',300,0,NULL,0,0,'platform'),
 (8,'run_failure_alert_sensor','SENSOR',3600,0,NULL,0,0,'platform'),
 (9,'cleanup_sensor','SENSOR',3600,86400,'cleanup_job',48,2,'platform'),
 (10,'model_registry_sensor','SENSOR',3600,86400,'model_registry_job',50,3,'ml'),
 (11,'quarterly_report_sensor','SENSOR',3600,0,NULL,0,0,'analytics'),
 (12,'hourly_refresh_schedule','SCHEDULE',3600,3600,'refresh_job',61,5,'analytics'),
 (13,'daily_partitioned_schedule_1','SCHEDULE',86400,86400,'partitioned_job_1',1,6,'analytics'),
 (14,'daily_partitioned_schedule_2','SCHEDULE',86400,86400,'partitioned_job_2',7,6,'analytics'),
 (15,'daily_partitioned_schedule_3','SCHEDULE',86400,86400,'partitioned_job_3',13,6,'finance'),
 (16,'daily_partitioned_schedule_4','SCHEDULE',86400,86400,'partitioned_job_4',19,6,'finance'),
 (17,'weekly_report_schedule','SCHEDULE',604800,604800,'weekly_report_job',53,4,'finance');

CREATE TEMP TABLE _ih AS
SELECT n, name, kind, interval_s, run_every_s, job, first_asset, nassets, team,
  printf('%08x%08x%08x%08x%08x', (n*2654435761)%4294967296, (n*2246822519+7)%4294967296,
         (n*3266489917+11)%4294967296, (n*668265263+13)%4294967296, (n*374761393+17)%4294967296) AS selector_id,
  printf('%08x%08x%08x%08x%08x', (n*374761393+101)%4294967296, (n*668265263+103)%4294967296,
         (n*3266489917+107)%4294967296, (n*2246822519+109)%4294967296, (n*2654435761+113)%4294967296) AS origin_id
FROM _inst;

-- ---- assets ------------------------------------------------------------------------------------------------
-- 1-24 daily-partitioned warehouse facts; 31-39 raw ingests; 40-60 staging/ml; 61-65 marts (with checks);
-- 111-120 observable source assets (observations only, no materializations).
CREATE TEMP TABLE _nm(i INTEGER PRIMARY KEY, w TEXT);
INSERT INTO _nm VALUES (0,'orders'),(1,'customers'),(2,'payments'),(3,'sessions'),(4,'events'),(5,'inventory'),
  (6,'shipments'),(7,'refunds'),(8,'invoices'),(9,'products'),(10,'clicks'),(11,'subscriptions');
CREATE TEMP TABLE _asset(k INTEGER PRIMARY KEY, prefix TEXT, name TEXT, akey TEXT, step_key TEXT,
                         partitioned INTEGER, observable INTEGER);
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 120)
INSERT INTO _asset
SELECT k, pfx, nm, '["' || pfx || '", "' || nm || '"]', pfx || '__' || nm, k <= 24, k > 110
FROM (SELECT k,
        CASE WHEN k <= 24 THEN 'warehouse' WHEN k <= 39 THEN 'raw' WHEN k <= 49 THEN 'staging'
             WHEN k <= 52 THEN 'ml' WHEN k <= 60 THEN 'reporting' WHEN k <= 65 THEN 'marts' ELSE 'sources' END AS pfx,
        CASE WHEN k <= 24 THEN 'fct_' ELSE '' END || (SELECT w FROM _nm WHERE i = k % 12) || '_' || k AS nm
      FROM n)
WHERE k <= 65 OR k > 110;

-- ---- runs --------------------------------------------------------------------------------------------------
-- _r0: one row per launched run (instigated, then backfills), ordered by creation time below.
CREATE TEMP TABLE _r0(inst INTEGER, ts REAL, part TEXT, backfill TEXT, h INTEGER);
WITH RECURSIVE n(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM n WHERE k < 45*24*(SELECT scale FROM _cfg))
INSERT INTO _r0
SELECT inst, ts, CASE WHEN inst BETWEEN 13 AND 16 THEN date(ts - 86400, 'unixepoch') END, NULL, h
FROM (SELECT inst, h, (SELECT now_s - days * 86400 FROM _k) + k * run_every_s
             + CASE WHEN kind = 'SCHEDULE' THEN 0 ELSE (h / 64) % (run_every_s / 2) END AS ts
      FROM (SELECT i.n AS inst, i.kind, i.run_every_s, n.k, ((i.n * 7919 + n.k) * 2654435761) % 4294967296 AS h
            FROM _inst i JOIN n ON i.run_every_s > 0 AND n.k <= (SELECT days FROM _k) * 86400 / i.run_every_s))
WHERE ts < (SELECT now_s FROM _k) - 60;
-- backfill bfkqzrtw: partitioned_job_1, one run per partition for 365*scale days before the schedule history,
-- launched 20 days ago over ~6 hours. bfcanc01: partitioned_job_3, 120 partitions, cancelled after 70 runs.
WITH RECURSIVE n(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM n WHERE k < 365*(SELECT scale FROM _cfg) - 1)
INSERT INTO _r0
SELECT 13, (SELECT now_s - 20*86400 FROM _k) + k * (21600.0 / (365*(SELECT scale FROM _cfg))),
  date((SELECT now_s - (days + 365*(SELECT scale FROM _cfg)) * 86400 FROM _k) + k * 86400, 'unixepoch'),
  'bfkqzrtw', ((k + 50000) * 2654435761) % 4294967296 FROM n;
WITH RECURSIVE n(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM n WHERE k < 69)
INSERT INTO _r0
SELECT 15, (SELECT now_s - 9*86400 FROM _k) + k * 90.0,
  date((SELECT now_s - (days + 120) * 86400 FROM _k) + k * 86400, 'unixepoch'),
  'bfcanc01', ((k + 90000) * 2654435761) % 4294967296 FROM n;

CREATE TEMP TABLE _r(id INTEGER PRIMARY KEY, inst INTEGER, ts REAL, part TEXT, backfill TEXT, h INTEGER,
                     run_id TEXT, status TEXT, dur REAL);
INSERT INTO _r(id, inst, ts, part, backfill, h)
SELECT NULL, inst, ts, part, backfill, h FROM _r0 ORDER BY ts;
UPDATE _r SET
  run_id = printf('%08x-%04x-4%03x-%04x-%04x%08x', (id * 2654435761) % 4294967296, (id * 40503) % 65536,
                  (id * 2246822519 / 7) % 4096, 32768 + (id * 668265263) % 16384, (id * 374761393) % 65536,
                  (id * 3266489917) % 4294967296),
  status = CASE
    WHEN ts > (SELECT now_s - 300 FROM _k) AND (SELECT kind FROM _inst WHERE n = inst) = 'SENSOR' THEN 'QUEUED'
    WHEN ts > (SELECT now_s - 1800 FROM _k) THEN 'STARTED'
    WHEN backfill = 'bfcanc01' AND id % 10 = 0 THEN 'CANCELED'
    WHEN (h / 1024) % 100 < 6 THEN 'FAILURE'
    WHEN (h / 1024) % 100 = 6 THEN 'CANCELED'
    ELSE 'SUCCESS' END,
  dur = CASE WHEN inst <= 11 THEN 20 + (h / 131072) % 400 WHEN inst = 12 THEN 300 + (h / 131072) % 600
             ELSE 600 + (h / 131072) % 1800 END;

INSERT INTO snapshots(snapshot_id, snapshot_body, snapshot_type)
SELECT printf('%08x%08x%08x%08x%08x', (n*12345701)%4294967296, (n*2654435761)%4294967296, (n*97)%4294967296,
              (n*2246822519)%4294967296, (n*31)%4294967296),
  CAST('{"__class__": "PipelineSnapshot", "name": "' || job || '", "tags": {}, "description": null, "solid_definitions_snapshot": {"__class__": "SolidDefinitionsSnapshot", "solid_def_snaps": []}, "config_schema_snapshot": {"__class__": "ConfigSchemaSnapshot", "all_config_snaps_by_key": {}}}' AS BLOB),
  'PIPELINE'
FROM _inst WHERE job IS NOT NULL;

INSERT INTO runs(id, run_id, snapshot_id, pipeline_name, mode, status, run_body, partition, partition_set,
                 create_timestamp, update_timestamp, start_time, end_time, backfill_id)
SELECT r.id, r.run_id,
  printf('%08x%08x%08x%08x%08x', (i.n*12345701)%4294967296, (i.n*2654435761)%4294967296, (i.n*97)%4294967296,
         (i.n*2246822519)%4294967296, (i.n*31)%4294967296),
  i.job, NULL, r.status,
  '{"__class__": "PipelineRun", "asset_selection": {"__frozenset__": []}, "execution_plan_snapshot_id": "'
    || printf('%08x%08x', r.h, r.id) || '", "has_repository_load_data": true, "mode": null, "parent_run_id": null, '
    || '"pipeline_name": "' || i.job || '", "root_run_id": null, "run_config": {}, "run_id": "' || r.run_id
    || '", "status": {"__enum__": "PipelineRunStatus.' || r.status || '"}, "tags": {".dagster/repository": "'
    || (SELECT repo_label FROM _k) || '", "dagster/' || lower(i.kind) || '_name": "' || i.name || '"'
    || CASE WHEN r.part IS NOT NULL THEN ', "dagster/partition": "' || r.part || '"' ELSE '' END
    || CASE WHEN r.backfill IS NOT NULL THEN ', "dagster/backfill": "' || r.backfill || '"' ELSE '' END
    || ', "team": "' || i.team || '"}}',
  r.part, CASE WHEN r.part IS NOT NULL THEN i.job || '_partition_set' END,
  strftime('%Y-%m-%d %H:%M:%S', r.ts, 'unixepoch') || printf('.%06d', (r.h / 4096) % 1000000),
  strftime('%Y-%m-%d %H:%M:%S', CASE WHEN r.status IN ('QUEUED', 'STARTED') THEN r.ts + 6 ELSE r.ts + 5 + r.dur END,
           'unixepoch') || printf('.%06d', (r.h / 8192) % 1000000),
  CASE WHEN r.status <> 'QUEUED' THEN r.ts + 5 END,
  CASE WHEN r.status NOT IN ('QUEUED', 'STARTED') THEN r.ts + 5 + r.dur END,
  r.backfill
FROM _r r JOIN _inst i ON i.n = r.inst ORDER BY r.id;

-- run_tags: the repository label and instigator tag on every run, then partition/backfill/run-key/schedule-time
-- tags where Dagster sets them, and one user tag (team).
INSERT INTO run_tags(run_id, "key", value)
SELECT run_id, k, v FROM (
  SELECT r.id AS id, 1 AS o, r.run_id, '.dagster/repository' AS k, (SELECT repo_label FROM _k) AS v FROM _r r
  UNION ALL SELECT r.id, 2, r.run_id, 'dagster/' || lower(i.kind) || '_name', i.name FROM _r r JOIN _inst i ON i.n = r.inst
  UNION ALL SELECT r.id, 3, r.run_id, 'dagster/run_key', i.name || ':' || printf('%x', r.h)
            FROM _r r JOIN _inst i ON i.n = r.inst WHERE i.kind = 'SENSOR'
  UNION ALL SELECT r.id, 3, r.run_id, 'dagster/scheduled_execution_time',
            strftime('%Y-%m-%dT%H:%M:%S+00:00', r.ts, 'unixepoch')
            FROM _r r JOIN _inst i ON i.n = r.inst WHERE i.kind = 'SCHEDULE' AND r.backfill IS NULL
  UNION ALL SELECT r.id, 4, r.run_id, 'dagster/partition', r.part FROM _r r WHERE r.part IS NOT NULL
  UNION ALL SELECT r.id, 5, r.run_id, 'dagster/partition_set', i.job || '_partition_set'
            FROM _r r JOIN _inst i ON i.n = r.inst WHERE r.part IS NOT NULL
  UNION ALL SELECT r.id, 6, r.run_id, 'dagster/backfill', r.backfill FROM _r r WHERE r.backfill IS NOT NULL
  UNION ALL SELECT r.id, 7, r.run_id, 'team', i.team FROM _r r JOIN _inst i ON i.n = r.inst
) ORDER BY id, o;

-- ---- event log ---------------------------------------------------------------------------------------------
-- Event template. phase 0 = run start (per_asset rows are ASSET_MATERIALIZATION_PLANNED), 1 = per step,
-- 2 = run end. cond: all | mat (step finished) | lastfail (the failing step of a failed run) | end_ok | end_fail
-- | end_cancel. Queued runs only get seq <= 2, started runs only phase 0.
CREATE TEMP TABLE _tpl(seq INTEGER, phase INTEGER, per_asset INTEGER, typ TEXT, cond TEXT);
INSERT INTO _tpl VALUES
 (1,0,1,'ASSET_MATERIALIZATION_PLANNED','all'), (2,0,0,'PIPELINE_ENQUEUED','all'), (3,0,0,'PIPELINE_DEQUEUED','all'),
 (4,0,0,'PIPELINE_STARTING','all'), (5,0,0,'PIPELINE_START','all'), (6,0,0,'ENGINE_EVENT','all'),
 (7,0,0,'LOGS_CAPTURED','all'),
 (10,1,1,'STEP_START','all'), (11,1,1,NULL,'all'), (12,1,1,'STEP_OUTPUT','mat'), (13,1,1,'ASSET_MATERIALIZATION','mat'),
 (14,1,1,'HANDLED_OUTPUT','mat'), (15,1,1,'STEP_SUCCESS','mat'), (16,1,1,'STEP_FAILURE','lastfail'),
 (20,2,0,'ENGINE_EVENT','all'), (21,2,0,'PIPELINE_SUCCESS','end_ok'), (22,2,0,'PIPELINE_FAILURE','end_fail'),
 (23,2,0,'PIPELINE_CANCELED','end_cancel');

WITH RECURSIVE a(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM a WHERE j < 9)
INSERT INTO event_logs(run_id, event, dagster_event_type, timestamp, step_key, asset_key, partition)
SELECT run_id,
  '{"__class__": "EventLogEntry", "dagster_event": ' ||
  CASE WHEN typ IS NULL THEN 'null' ELSE
    '{"__class__": "DagsterEvent", "event_specific_data": ' ||
    CASE WHEN typ = 'ASSET_MATERIALIZATION' THEN
           '{"__class__": "StepMaterializationData", "materialization": {"__class__": "AssetMaterialization", "asset_key": {"__class__": "AssetKey", "path": ["' || prefix || '", "' || name || '"]}, "metadata": {"rows": ' || ((h / 32) % 900000) || '}, "partition": ' || coalesce('"' || part || '"', 'null') || ', "tags": {"dagster/data_version": "' || printf('%08x%08x', h, ev) || '"}}}'
         WHEN typ = 'ASSET_OBSERVATION' THEN
           '{"__class__": "AssetObservationData", "asset_observation": {"__class__": "AssetObservation", "asset_key": {"__class__": "AssetKey", "path": ["' || prefix || '", "' || name || '"]}, "tags": {"dagster/data_version": "' || printf('%08x', (h / 4 + ev) % 4294967296) || '"}}}'
         WHEN typ = 'ASSET_MATERIALIZATION_PLANNED' THEN
           '{"__class__": "AssetMaterializationPlannedData", "asset_key": {"__class__": "AssetKey", "path": ["' || prefix || '", "' || name || '"]}, "partition": ' || coalesce('"' || part || '"', 'null') || '}'
         WHEN typ IN ('STEP_FAILURE', 'PIPELINE_FAILURE') THEN
           '{"__class__": "StepFailureData", "error": {"__class__": "SerializableErrorInfo", "cls_name": "OperationalError", "message": "upstream timed out", "stack": []}}'
         ELSE 'null' END ||
    ', "event_type_value": "' || typ || '", "step_key": ' ||
    coalesce('"' || step_key || '"', 'null') || '}' END ||
  ', "level": ' || CASE WHEN typ IS NULL THEN 20 ELSE 10 END || ', "pipeline_name": "' || job || '", "run_id": "' ||
  run_id || '", "step_key": ' || coalesce('"' || step_key || '"', 'null') || ', "timestamp": ' || printf('%.6f', ets) ||
  ', "user_message": "' || CASE WHEN typ IS NULL THEN 'Loaded ' || ((h / 32) % 900000) || ' rows' ELSE '' END || '"}',
  typ, strftime('%Y-%m-%d %H:%M:%S', ets, 'unixepoch') || printf('.%06d', (ev * 7919 + h) % 1000000),
  step_key, CASE WHEN typ IN ('ASSET_MATERIALIZATION', 'ASSET_OBSERVATION', 'ASSET_MATERIALIZATION_PLANNED') THEN akey END,
  CASE WHEN typ IN ('ASSET_MATERIALIZATION', 'ASSET_OBSERVATION', 'ASSET_MATERIALIZATION_PLANNED') THEN part END
FROM (
  SELECT r.run_id, r.h, r.part, i.job, x.prefix, x.name, x.akey,
    CASE WHEN t.per_asset = 1 THEN x.step_key END AS step_key,
    CASE WHEN t.typ = 'ASSET_MATERIALIZATION' AND x.observable THEN 'ASSET_OBSERVATION' ELSE t.typ END AS typ,
    r.id * 1000 + t.seq * 20 + coalesce(a.j, 0) AS ev,
    CASE t.phase WHEN 0 THEN r.ts + t.seq * 0.5 + coalesce(a.j, 0) * 0.01
                 WHEN 1 THEN r.ts + 5 + (coalesce(a.j, 0) + 0.5) * r.dur / i.nassets + (t.seq - 10) * 0.2
                 ELSE r.ts + 5 + r.dur + (t.seq - 20) * 0.1 END AS ets
  FROM _r r JOIN _inst i ON i.n = r.inst
  JOIN _tpl t
  LEFT JOIN a ON t.per_asset = 1 AND a.j < i.nassets
  LEFT JOIN _asset x ON x.k = i.first_asset + a.j
  WHERE (t.per_asset = 0 OR a.j IS NOT NULL)
    AND NOT (t.typ = 'ASSET_MATERIALIZATION_PLANNED' AND x.observable)
    AND CASE r.status WHEN 'QUEUED' THEN t.seq <= 2 WHEN 'STARTED' THEN t.phase = 0 ELSE 1 END
    AND CASE t.cond
          WHEN 'all' THEN 1
          WHEN 'mat' THEN r.status = 'SUCCESS' OR (r.status IN ('FAILURE', 'CANCELED') AND a.j < i.nassets - 1)
          WHEN 'lastfail' THEN r.status = 'FAILURE' AND a.j = i.nassets - 1
          WHEN 'end_ok' THEN r.status = 'SUCCESS'
          WHEN 'end_fail' THEN r.status = 'FAILURE'
          WHEN 'end_cancel' THEN r.status = 'CANCELED' END
) ORDER BY ets;

-- asset_event_tags: the data version of each materialization/observation (what store_asset_event_tags writes).
INSERT INTO asset_event_tags(event_id, asset_key, "key", value, event_timestamp)
SELECT id, asset_key, 'dagster/data_version', printf('%08x%08x%08x', (id * 2654435761) % 4294967296,
       (id * 40503) % 4294967296, (id * 2246822519) % 4294967296), timestamp
FROM event_logs WHERE dagster_event_type IN ('ASSET_MATERIALIZATION', 'ASSET_OBSERVATION') ORDER BY id;

-- asset_keys: one row per asset; last_materialization holds the serialized latest record. Observable sources
-- and two marts assets created before the column was backfilled have NULL, so get_asset_records falls back to
-- the event log for them.
INSERT INTO asset_keys(asset_key, last_materialization, last_run_id, asset_details, wipe_timestamp,
                       last_materialization_timestamp, tags, create_timestamp, cached_status_data)
SELECT x.akey,
  CASE WHEN x.observable OR x.k IN (61, 62) THEN NULL ELSE
    '{"__class__": "EventLogRecord", "event_log_entry": ' || e.event || ', "storage_id": ' || e.id || '}' END,
  e.run_id, NULL, NULL, e.timestamp, NULL, '2026-06-01 00:00:00',
  CASE WHEN x.partitioned THEN '{"__class__": "AssetStatusCacheValue", "latest_storage_id": ' || e.id ||
    ', "partitions_def_id": "' || printf('%08x', x.k * 2654435761 % 4294967296) ||
    '", "serialized_materialized_partition_subset": "{\"version\": 1, \"time_windows\": []}"}' END
FROM _asset x
JOIN event_logs e ON e.id = (SELECT max(id) FROM event_logs WHERE asset_key = x.akey
                               AND dagster_event_type IN ('ASSET_MATERIALIZATION', 'ASSET_OBSERVATION'))
ORDER BY x.k;

-- asset checks on the 5 marts assets: not_null on every hourly refresh run, freshness_within_2h on about 1 in 6.
INSERT INTO asset_check_executions(asset_key, check_name, partition, run_id, execution_status, evaluation_event,
  evaluation_event_timestamp, evaluation_event_storage_id, materialization_event_storage_id, create_timestamp)
SELECT e.asset_key, c.check_name, NULL, e.run_id,
  CASE WHEN (e.id * 2654435761 / 64) % 100 < 4 THEN 'FAILED' ELSE 'SUCCEEDED' END,
  '{"__class__": "EventLogEntry", "dagster_event": {"__class__": "DagsterEvent", "event_specific_data": {"__class__": "AssetCheckEvaluation", "asset_key": {"__class__": "AssetKey", "path": ' || e.asset_key || '}, "check_name": "' || c.check_name || '", "passed": ' || CASE WHEN (e.id * 2654435761 / 64) % 100 < 4 THEN 'false' ELSE 'true' END || ', "target_materialization_data": {"storage_id": ' || e.id || '}}, "event_type_value": "ASSET_CHECK_EVALUATION"}, "run_id": "' || e.run_id || '"}',
  e.timestamp, e.id + 1, e.id, e.timestamp
FROM event_logs e JOIN (SELECT 'not_null' AS check_name UNION ALL SELECT 'freshness_within_2h') c
WHERE e.dagster_event_type = 'ASSET_MATERIALIZATION' AND (c.check_name = 'not_null' OR e.id % 6 = 0)
  AND e.asset_key IN (SELECT akey FROM _asset WHERE k BETWEEN 61 AND 65)
ORDER BY e.id, c.check_name;

-- ---- schedules / sensors -----------------------------------------------------------------------------------
INSERT INTO instigators(selector_id, repository_selector_id, status, instigator_type, instigator_body,
                        create_timestamp, update_timestamp)
SELECT selector_id, (SELECT repo_selector FROM _k), CASE WHEN n IN (11) THEN 'STOPPED' ELSE 'RUNNING' END, kind,
  '{"__class__": "JobState", "job_specific_data": {"__class__": "' ||
  CASE kind WHEN 'SENSOR' THEN 'SensorJobData", "last_tick_timestamp": 1793318370.0, "min_interval": ' || interval_s
            ELSE 'ScheduleJobData", "cron_schedule": "' || CASE interval_s WHEN 3600 THEN '0 * * * *' WHEN 86400 THEN '0 2 * * *' ELSE '0 6 * * 1' END || '", "start_timestamp": null' END ||
  '}, "job_type": {"__enum__": "JobType.' || kind || '"}, "origin": {"__class__": "ExternalJobOrigin", "job_name": "' ||
  name || '", "external_repository_origin": {"__class__": "ExternalRepositoryOrigin", "repository_name": "__repository__", "repository_location_origin": {"__class__": "ManagedGrpcPythonEnvRepositoryLocationOrigin", "location_name": "analytics_pipelines"}}}, "status": {"__enum__": "JobStatus.' ||
  CASE WHEN n IN (11) THEN 'STOPPED' ELSE 'RUNNING' END || '"}}',
  '2026-06-01 00:00:00', '2026-10-29 23:59:30'
FROM _ih ORDER BY n;
INSERT INTO jobs(job_origin_id, selector_id, repository_origin_id, status, job_type, job_body, create_timestamp,
                 update_timestamp)
SELECT h.origin_id, h.selector_id, 'c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00', i.status, i.instigator_type,
       i.instigator_body, i.create_timestamp, i.update_timestamp
FROM _ih h JOIN instigators i ON i.selector_id = h.selector_id ORDER BY h.n;

-- ticks: (a) a SKIPPED (0.4 % FAILURE) tick per interval for sensors over the 7-day retained window, plus the one
-- tick that has just aged out and that the next purge_ticks call removes. The two 30 s sensors tick every
-- 30/scale s (7.5 s at scale 4; dagster#30172's sensors ran every 10 s), so tick volume grows with scale;
-- (b) a SUCCESS tick for every run an instigator launched, over the whole history (never purged); (c) every
-- schedule tick is a run tick. Inserted in time order, like the daemon writes them.
CREATE TEMP TABLE _t0(n INTEGER, ts REAL, status TEXT, run_id TEXT, h INTEGER);
WITH RECURSIVE k(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM k WHERE j < 7*86400*(SELECT scale FROM _cfg)/30 + 1),
iv AS (SELECT n, kind, CASE WHEN interval_s = 30 THEN 30.0 / (SELECT scale FROM _cfg) ELSE interval_s END AS ei FROM _inst)
INSERT INTO _t0
SELECT i.n, (SELECT now_s FROM _k) - (k.j + 1) * i.ei + (i.n % 7),
  CASE WHEN ((i.n * 1000003 + k.j) * 2654435761 / 256) % 1000 < 4 THEN 'FAILURE' ELSE 'SKIPPED' END, NULL,
  ((i.n * 1000003 + k.j) * 2654435761) % 4294967296
FROM iv i JOIN k ON i.kind = 'SENSOR' AND k.j <= 7*86400 / i.ei;
INSERT INTO _t0 SELECT r.inst, r.ts - 1, 'SUCCESS', r.run_id, r.h FROM _r r WHERE r.backfill IS NULL;

INSERT INTO job_ticks(job_origin_id, selector_id, status, type, timestamp, tick_body, create_timestamp,
                      update_timestamp)
SELECT h.origin_id, h.selector_id, t.status, h.kind,
  strftime('%Y-%m-%d %H:%M:%S', t.ts, 'unixepoch') || printf('.%06d', (t.h / 16) % 1000000),
  '{"__class__": "JobTickData", "cursor": ' || CASE WHEN h.kind = 'SENSOR' THEN '"' || printf('%x', t.h) || '"' ELSE 'null' END ||
  ', "job_name": "' || h.name || '", "job_type": {"__enum__": "JobType.' || h.kind ||
  '"}, "origin_run_ids": [], "run_ids": [' || coalesce('"' || t.run_id || '"', '') || '], "run_keys": [' ||
  CASE WHEN t.run_id IS NOT NULL AND h.kind = 'SENSOR' THEN '"' || h.name || ':' || printf('%x', t.h) || '"' ELSE '' END ||
  '], "selector_id": "' || h.selector_id || '", "skip_reason": ' ||
  CASE t.status WHEN 'SKIPPED' THEN '"Sensor function returned an empty result"' ELSE 'null' END ||
  ', "error": ' || CASE t.status WHEN 'FAILURE' THEN '{"__class__": "SerializableErrorInfo", "cls_name": "TimeoutError", "message": "gRPC deadline exceeded"}' ELSE 'null' END ||
  ', "status": {"__enum__": "TickStatus.' || t.status || '"}, "timestamp": ' || printf('%.6f', t.ts) || '}',
  strftime('%Y-%m-%d %H:%M:%S', t.ts, 'unixepoch'), strftime('%Y-%m-%d %H:%M:%S', t.ts + 1, 'unixepoch')
FROM _t0 t JOIN _ih h ON h.n = t.n ORDER BY t.ts;

-- ---- backfills, heartbeats, kvs, migration markers ---------------------------------------------------------
INSERT INTO bulk_actions("key", status, timestamp, body, action_type, selector_id, job_name) VALUES
 ('bfkqzrtw', 'COMPLETED_SUCCESS', '2026-10-10 00:00:00.000000', '{"__class__": "PartitionBackfill", "backfill_id": "bfkqzrtw", "status": {"__enum__": "BulkActionStatus.COMPLETED_SUCCESS"}, "from_failure": false, "tags": {"team": "analytics"}, "backfill_timestamp": 1791590400.0, "partition_set_origin": {"__class__": "ExternalPartitionSetOrigin", "partition_set_name": "partitioned_job_1_partition_set"}}', 'PARTITION_BACKFILL', 'aa01aa01aa01aa01aa01aa01aa01aa01aa01aa01', 'partitioned_job_1'),
 ('bfcanc01', 'CANCELED', '2026-10-21 00:00:00.000000', '{"__class__": "PartitionBackfill", "backfill_id": "bfcanc01", "status": {"__enum__": "BulkActionStatus.CANCELED"}, "from_failure": false, "tags": {}, "backfill_timestamp": 1792540800.0, "partition_set_origin": {"__class__": "ExternalPartitionSetOrigin", "partition_set_name": "partitioned_job_3_partition_set"}}', 'PARTITION_BACKFILL', 'aa03aa03aa03aa03aa03aa03aa03aa03aa03aa03', 'partitioned_job_3'),
 ('bfreq777', 'REQUESTED', '2026-10-29 22:00:00.000000', '{"__class__": "PartitionBackfill", "backfill_id": "bfreq777", "status": {"__enum__": "BulkActionStatus.REQUESTED"}, "from_failure": false, "tags": {}, "backfill_timestamp": 1793311200.0, "asset_backfill_data": {"__class__": "AssetBackfillData"}}', 'PARTITION_BACKFILL', NULL, NULL);
INSERT INTO backfill_tags(backfill_id, "key", value) VALUES ('bfkqzrtw', 'team', 'analytics');
INSERT INTO daemon_heartbeats(daemon_type, daemon_id, timestamp, body) VALUES
 ('SENSOR', 'd1', '2026-10-29 23:59:50', '{"__class__": "DaemonHeartbeat", "daemon_type": "SENSOR", "errors": []}'),
 ('SCHEDULER', 'd1', '2026-10-29 23:59:50', '{"__class__": "DaemonHeartbeat", "daemon_type": "SCHEDULER", "errors": []}'),
 ('QUEUED_RUN_COORDINATOR', 'd1', '2026-10-29 23:59:55', '{"__class__": "DaemonHeartbeat", "daemon_type": "QUEUED_RUN_COORDINATOR", "errors": []}'),
 ('BACKFILL', 'd1', '2026-10-29 23:59:52', '{"__class__": "DaemonHeartbeat", "daemon_type": "BACKFILL", "errors": []}'),
 ('ASSET', 'd1', '2026-10-29 23:59:41', '{"__class__": "DaemonHeartbeat", "daemon_type": "ASSET", "errors": []}');
INSERT INTO kvs("key", value) VALUES ('ASSET_DAEMON_CURSOR', '{"evaluation_id": 4411}'),
 ('EVENT_LOG_CONSUMER_CURSOR', '12345'), ('run_monitoring_cursor', '0');
INSERT INTO instance_info(run_storage_id) VALUES ('5b0f4bd2-1c3e-4c8e-9a51-0f8a2d7c6e11');
INSERT INTO secondary_indexes(name, create_timestamp, migration_completed) VALUES
 ('run_partitions', '2026-06-01 00:00:00', '2026-06-01 00:00:00.000000'),
 ('run_repo_label_tags', '2026-06-01 00:00:00', '2026-06-01 00:00:00.000000'),
 ('bulk_action_types', '2026-06-01 00:00:00', '2026-06-01 00:00:00.000000'),
 ('run_backfill_id', '2026-06-01 00:00:00', '2026-06-01 00:00:00.000000'),
 ('backfill_job_name_and_tags', '2026-06-01 00:00:00', '2026-06-01 00:00:00.000000'),
 ('backfill_end_timestamp', '2026-06-01 00:00:00', '2026-06-01 00:00:00.000000'),
 ('run_start_end_overwritten', '2026-06-01 00:00:00', '2026-06-01 00:00:00.000000'),
 ('schedule_jobs_selector_id', '2026-06-01 00:00:00', '2026-06-01 00:00:00.000000'),
 ('schedule_ticks_selector_id', '2026-06-01 00:00:00', '2026-06-01 00:00:00.000000'),
 ('asset_key_table', '2026-06-01 00:00:00', '2026-06-01 00:00:00.000000'),
 ('asset_key_index_columns', '2026-06-01 00:00:00', '2026-06-01 00:00:00.000000');

DROP TABLE _k; DROP TABLE _inst; DROP TABLE _ih; DROP TABLE _nm; DROP TABLE _asset; DROP TABLE _r0; DROP TABLE _r;
DROP TABLE _tpl; DROP TABLE _t0;
COMMIT;
