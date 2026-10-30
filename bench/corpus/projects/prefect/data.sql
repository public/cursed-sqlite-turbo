-- Synthetic data for a self-hosted Prefect server on its default SQLite database. Deterministic (no random()):
-- values come from multiplicative hashes of the row number. "Now" is 2026-10-30 12:00:00 UTC (julianday 2461344.0).
-- Timestamps use Prefect's SQLite storage format 'YYYY-MM-DD HH:MM:SS.ffffff'; intervals (total_run_time) are stored
-- as timestamps offset from 1970-01-01, as SQLAlchemy does. Ids are UUID-shaped text: printf('%08x-0000-4000-8000-%012x',
-- table_code, n), so the same id can be rebuilt anywhere.
--
-- Scale 1: 6 work pools, 18 work queues, 30 workers, 60 flows, 120 deployments with 120 schedules; 12k past flow runs
-- over 30 days, recency-skewed (age = 30 d * (1 - i/n)^3: ~3.9k in the last 24 h, ~7.4k in the last 7 days), 46 % from
-- the 10 hot deployments, 8 % ad-hoc, ~500 subflows; 380 scheduled runs (future ones plus 60 late); 36k flow run
-- states (3 per run); 36k task runs (5 per hot-deployment run, 1 otherwise, 600 for one run in 3000) with one state
-- each; 16k logs; 1.2k artifacts in 142 collections; 7.2k flow-run events over 8.5 days (retention is 7) with 27.6k
-- event_resources; 20 v2 concurrency limits. About 150 MB. _cfg.scale multiplies the flow runs (and everything hanging
-- off them, so the events too).
BEGIN;

CREATE TEMP TABLE _c AS SELECT 2461344.0 AS now_jd, 12000 * (SELECT scale FROM _cfg) AS n_fr;

-- work pools and queues ---------------------------------------------------------------------------------
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 6)
INSERT INTO work_pool(id, created, updated, name, description, type, base_job_template, is_paused, concurrency_limit,
                      default_queue_id, status, last_transitioned_status_at, storage_configuration)
SELECT printf('%08x-0000-4000-8000-%012x', 4, i), '2026-03-01 09:00:00.000000', '2026-10-30 11:59:00.000000',
  CASE i WHEN 1 THEN 'default-process' WHEN 2 THEN 'docker-etl' WHEN 3 THEN 'k8s-prod' WHEN 4 THEN 'k8s-ml'
         WHEN 5 THEN 'ecs-batch' ELSE 'local-dev' END,
  NULL, CASE WHEN i IN (3,4) THEN 'kubernetes' WHEN i = 2 THEN 'docker' WHEN i = 5 THEN 'ecs' ELSE 'process' END,
  '{"job_configuration": {"command": "{{ command }}", "env": "{{ env }}", "labels": "{{ labels }}", "name": "{{ name }}"}, "variables": {"properties": {"command": {"type": "string"}, "env": {"type": "object"}}}}',
  0, CASE WHEN i = 3 THEN 500 * (SELECT scale FROM _cfg) ELSE NULL END,
  printf('%08x-0000-4000-8000-%012x', 5, (i-1)*3+1), CASE WHEN i = 6 THEN 'NOT_READY' ELSE 'READY' END,
  '2026-10-29 08:00:00.000000', '{}'
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 18)
INSERT INTO work_queue(id, created, updated, name, filter, description, is_paused, concurrency_limit, last_polled, priority,
                       work_pool_id, status)
SELECT printf('%08x-0000-4000-8000-%012x', 5, i), '2026-03-01 09:00:00.000000', '2026-10-30 11:59:00.000000',
  CASE (i-1) % 3 WHEN 0 THEN 'default' WHEN 1 THEN 'high-priority' ELSE 'backfill' END, NULL, '', 0,
  CASE WHEN (i-1) % 3 = 2 THEN 5 ELSE NULL END,
  CASE WHEN i > 15 THEN '2026-10-28 10:00:00.000000' ELSE '2026-10-30 11:59:50.000000' END,
  (i-1) % 3 + 1, printf('%08x-0000-4000-8000-%012x', 4, (i-1)/3+1),
  CASE WHEN i > 15 THEN 'NOT_READY' ELSE 'READY' END
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 30)
INSERT INTO worker(id, created, updated, name, last_heartbeat_time, work_pool_id, heartbeat_interval_seconds, status)
SELECT printf('%08x-0000-4000-8000-%012x', 6, i), '2026-10-01 00:00:00.000000', '2026-10-30 11:59:40.000000',
  printf('worker-%04x', (i * 40503) % 65536),
  CASE WHEN i % 7 = 0 THEN '2026-10-30 10:30:00.000000' ELSE strftime('%Y-%m-%d %H:%M:%f000', 2461344.0 - (i % 30) / 86400.0) END,
  printf('%08x-0000-4000-8000-%012x', 4, (i-1) % 5 + 1), 30, 'ONLINE'
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20)
INSERT INTO concurrency_limit_v2(id, created, updated, active, name, "limit", active_slots, denied_slots,
                                 slot_decay_per_second, avg_slot_occupancy_seconds)
SELECT printf('%08x-0000-4000-8000-%012x', 16, i), '2026-05-01 00:00:00.000000', '2026-10-30 11:59:00.000000', 1,
  CASE WHEN i <= 10 THEN 'deployment:' || printf('%08x-0000-4000-8000-%012x', 2, i) ELSE 'tag:db-' || i END,
  CASE WHEN i <= 10 THEN 4 ELSE 10 END, i % 4, 0, 0.0, 2.0
FROM n;

-- flows, deployments, schedules ------------------------------------------------------------------------
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 60)
INSERT INTO flow(id, created, updated, name, tags, labels)
SELECT printf('%08x-0000-4000-8000-%012x', 1, i), strftime('%Y-%m-%d %H:%M:%f000', 2461344.0 - 240 + i),
  strftime('%Y-%m-%d %H:%M:%f000', 2461344.0 - 60 + i / 2.0),
  CASE i % 6 WHEN 0 THEN 'etl' WHEN 1 THEN 'ingest' WHEN 2 THEN 'train-model' WHEN 3 THEN 'report'
             WHEN 4 THEN 'sync' ELSE 'cleanup' END || '-' || printf('%02d', i),
  '[]', '{}'
FROM n;

-- deployment d belongs to flow (d+1)/2 and queue (d-1)%15+1; deployments 1-10 are the hot ones.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 120)
INSERT INTO deployment(id, created, updated, name, tags, parameters, flow_id, description, version, infra_overrides, path,
                       entrypoint, work_queue_name, created_by, work_queue_id, pull_steps, enforce_parameter_schema,
                       last_polled, paused, status, concurrency_limit, concurrency_limit_id, labels)
SELECT printf('%08x-0000-4000-8000-%012x', 2, i), strftime('%Y-%m-%d %H:%M:%f000', 2461344.0 - 200 + i),
  CASE WHEN i % 40 = 1 THEN '2026-10-30 11:59:58.000000' ELSE strftime('%Y-%m-%d %H:%M:%f000', 2461344.0 - 30 + i / 5.0) END,
  CASE WHEN i % 2 = 1 THEN 'prod' ELSE 'hourly' END || '-' || i,
  CASE WHEN i % 3 = 0 THEN '["prod", "critical"]' WHEN i % 3 = 1 THEN '["prod"]' ELSE '["staging"]' END,
  json_object('date', NULL, 'full_refresh', json('false'), 'region', CASE i % 3 WHEN 0 THEN 'eu' WHEN 1 THEN 'us' ELSE 'ap' END),
  printf('%08x-0000-4000-8000-%012x', 1, (i+1)/2), 'Deployment ' || i, printf('v%d.%d', i % 4 + 1, i % 9),
  '{}', '.', 'flows/pipeline.py:main',
  CASE (((i-1) % 15)) % 3 WHEN 0 THEN 'default' WHEN 1 THEN 'high-priority' ELSE 'backfill' END,
  NULL, printf('%08x-0000-4000-8000-%012x', 5, (i-1) % 15 + 1), NULL, 0,
  '2026-10-30 11:59:30.000000', CASE WHEN i % 25 = 0 THEN 1 ELSE 0 END, 'READY',
  CASE WHEN i <= 10 THEN 4 ELSE NULL END,
  CASE WHEN i <= 10 THEN printf('%08x-0000-4000-8000-%012x', 16, i) ELSE NULL END, '{}'
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 120)
INSERT INTO deployment_schedule(id, created, updated, schedule, active, deployment_id, max_scheduled_runs, parameters, slug)
SELECT printf('%08x-0000-4000-8000-%012x', 3, i), '2026-06-01 00:00:00.000000', '2026-10-01 00:00:00.000000',
  CASE WHEN i <= 10 THEN '{"interval": 300.0, "anchor_date": "2026-01-01T00:00:00Z", "timezone": "UTC"}'
       ELSE '{"cron": "0 * * * *", "timezone": "UTC", "day_or": true}' END,
  CASE WHEN i % 8 = 0 THEN 0 ELSE 1 END, printf('%08x-0000-4000-8000-%012x', 2, i), NULL, '{}', 'sched-' || i
FROM n;

-- flow runs ----------------------------------------------------------------------------------------------
-- Past runs: i = 1..n_fr, i grows with time; age (days) = 60 * (1 - i/n)^2, so recent days are densest.
CREATE TEMP TABLE _fr AS
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT n_fr FROM _c)),
h AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n),
d AS (SELECT i, h,
        CASE WHEN (h / 8192) % 12 = 0 THEN NULL
             WHEN (h / 2) % 2 = 0 THEN (h / 4) % 10 + 1 ELSE (h / 64) % 110 + 11 END AS dep,
        (SELECT now_jd FROM _c) - 30.0 * (1.0 - (i - 0.5) / (SELECT n_fr FROM _c)) * (1.0 - (i - 0.5) / (SELECT n_fr FROM _c))
            * (1.0 - (i - 0.5) / (SELECT n_fr FROM _c))
          - ((h / 1048576) % 60) / 86400.0 AS exp_jd
      FROM h),
s AS (SELECT i, h, dep, exp_jd,
        CASE WHEN dep IS NULL THEN (h / 16384) % 60 + 1 ELSE (dep + 1) / 2 END AS flow,
        CASE WHEN (h / 4096) % 33 = 0 THEN ((h / 65536) % 1800) + 120 ELSE (h / 65536) % 25 + 1 END AS late_s,
        CASE WHEN dep <= 10 THEN (h / 1024) % 1500 + 60 ELSE (h / 1024) % 240 + 5 END AS dur_s,
        CASE WHEN exp_jd > (SELECT now_jd FROM _c) - 1.0 / 24 AND (h / 131072) % 8 = 0 THEN 'RUNNING'
             WHEN (h / 131072) % 100 < 84 THEN 'COMPLETED'
             WHEN (h / 131072) % 100 < 93 THEN 'FAILED'
             WHEN (h / 131072) % 100 < 95 THEN 'CRASHED'
             ELSE 'CANCELLED' END AS st
      FROM d)
SELECT i, h, dep, flow, exp_jd, exp_jd + late_s / 86400.0 AS start_jd,
  CASE WHEN st = 'RUNNING' OR exp_jd + (late_s + dur_s) / 86400.0 > (SELECT now_jd FROM _c) THEN NULL
       ELSE exp_jd + (late_s + dur_s) / 86400.0 END AS end_jd,
  CASE WHEN st <> 'RUNNING' AND exp_jd + (late_s + dur_s) / 86400.0 > (SELECT now_jd FROM _c) THEN 'RUNNING' ELSE st END AS st,
  dur_s
FROM s;

INSERT INTO flow_run(id, created, updated, name, state_type, run_count, expected_start_time, next_scheduled_start_time,
                     start_time, end_time, total_run_time, flow_version, parameters, idempotency_key, context,
                     empirical_policy, tags, auto_scheduled, flow_id, deployment_id, parent_task_run_id, state_id,
                     state_name, infrastructure_document_id, work_queue_name, state_timestamp, created_by,
                     infrastructure_pid, work_queue_id, job_variables, deployment_version, labels)
SELECT printf('%08x-0000-4000-8000-%012x', 7, i),
  strftime('%Y-%m-%d %H:%M:%f000', exp_jd - 0.01), strftime('%Y-%m-%d %H:%M:%f000', coalesce(end_jd, start_jd)),
  (SELECT group_concat(w, '-') FROM (SELECT CASE (h / 7) % 8 WHEN 0 THEN 'amber' WHEN 1 THEN 'brisk' WHEN 2 THEN 'cosmic'
       WHEN 3 THEN 'daring' WHEN 4 THEN 'eager' WHEN 5 THEN 'fluffy' WHEN 6 THEN 'gentle' ELSE 'hidden' END AS w
     UNION ALL SELECT CASE (h / 61) % 8 WHEN 0 THEN 'otter' WHEN 1 THEN 'heron' WHEN 2 THEN 'badger' WHEN 3 THEN 'lynx'
       WHEN 4 THEN 'falcon' WHEN 5 THEN 'marmot' WHEN 6 THEN 'ibis' ELSE 'walrus' END)) || '-' || i,
  st, 1, strftime('%Y-%m-%d %H:%M:%f000', exp_jd), strftime('%Y-%m-%d %H:%M:%f000', exp_jd),
  strftime('%Y-%m-%d %H:%M:%f000', start_jd),
  CASE WHEN end_jd IS NULL THEN NULL ELSE strftime('%Y-%m-%d %H:%M:%f000', end_jd) END,
  CASE WHEN end_jd IS NULL THEN '1970-01-01 00:00:00.000000'
       ELSE strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + dur_s / 86400.0) END,
  printf('%x', (h / 3) % 4096),
  json_object('date', strftime('%Y-%m-%d', exp_jd), 'full_refresh', json(CASE WHEN h % 13 = 0 THEN 'true' ELSE 'false' END)),
  CASE WHEN dep IS NOT NULL THEN 'scheduled ' || printf('%08x-0000-4000-8000-%012x', 2, dep) || ' ' || printf('%08x-0000-4000-8000-%012x', 3, dep) || ' ' || strftime('%Y-%m-%dT%H:%M:%f+00:00', exp_jd) ELSE NULL END,
  '{}', '{"retries": 0, "retry_delay": 0, "pause_keys": [], "resuming": false}',
  CASE WHEN dep IS NULL THEN '[]' WHEN dep % 3 = 0 THEN '["prod", "critical", "auto-scheduled"]'
       WHEN dep % 3 = 1 THEN '["prod", "auto-scheduled"]' ELSE '["staging", "auto-scheduled"]' END,
  CASE WHEN dep IS NOT NULL THEN 1 ELSE 0 END,
  printf('%08x-0000-4000-8000-%012x', 1, flow),
  CASE WHEN dep IS NULL THEN NULL ELSE printf('%08x-0000-4000-8000-%012x', 2, dep) END,
  CASE WHEN dep IS NULL AND (h / 32) % 2 = 0 AND i > 40 THEN printf('%08x-0000-4000-8000-%012x', 9, (i - 17) * 1024 + 1) ELSE NULL END,
  printf('%08x-0000-4000-8000-%012x', 8, i * 3),
  CASE st WHEN 'COMPLETED' THEN 'Completed' WHEN 'FAILED' THEN 'Failed' WHEN 'CRASHED' THEN 'Crashed'
          WHEN 'CANCELLED' THEN 'Cancelled' ELSE 'Running' END,
  NULL,
  CASE WHEN dep IS NULL THEN NULL WHEN ((dep - 1) % 15) % 3 = 0 THEN 'default' WHEN ((dep - 1) % 15) % 3 = 1 THEN 'high-priority' ELSE 'backfill' END,
  strftime('%Y-%m-%d %H:%M:%f000', coalesce(end_jd, start_jd)),
  CASE WHEN dep IS NULL THEN NULL ELSE json_object('id', printf('%08x-0000-4000-8000-%012x', 3, dep), 'type', 'SCHEDULE', 'display_value', NULL) END,
  CASE WHEN dep IS NULL THEN NULL ELSE printf('%d', 1000 + h % 60000) END,
  CASE WHEN dep IS NULL THEN NULL ELSE printf('%08x-0000-4000-8000-%012x', 5, (dep - 1) % 15 + 1) END,
  '{}', NULL, '{}'
FROM _fr;

-- Future scheduled runs (3 per active schedule) and 60 late ones the late-runs service has not caught yet.
-- Ids continue after the past runs.
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 420),
f AS (SELECT k, (SELECT n_fr FROM _c) + k AS i, ((k - 1) % 120) + 1 AS dep,
        CASE WHEN k <= 360 THEN (SELECT now_jd FROM _c) + ((k - 1) / 120 + 1) / 24.0 + ((k - 1) % 120) / 1440.0
             ELSE (SELECT now_jd FROM _c) - (k - 350) / 1440.0 END AS jd
      FROM n)
INSERT INTO flow_run(id, created, updated, name, state_type, run_count, expected_start_time, next_scheduled_start_time,
                     total_run_time, parameters, idempotency_key, tags, auto_scheduled, flow_id, deployment_id, state_id,
                     state_name, work_queue_name, state_timestamp, created_by, work_queue_id, job_variables, empirical_policy, context)
SELECT printf('%08x-0000-4000-8000-%012x', 7, i), '2026-10-30 10:00:00.000000', '2026-10-30 10:00:00.000000',
  'scheduled-run-' || i, 'SCHEDULED', 0, strftime('%Y-%m-%d %H:%M:%f000', jd), strftime('%Y-%m-%d %H:%M:%f000', jd),
  '1970-01-01 00:00:00.000000', '{}',
  'scheduled ' || printf('%08x-0000-4000-8000-%012x', 2, dep) || ' ' || printf('%08x-0000-4000-8000-%012x', 3, dep) || ' ' || strftime('%Y-%m-%dT%H:%M:%S+00:00', jd),
  '["auto-scheduled"]', 1, printf('%08x-0000-4000-8000-%012x', 1, (dep + 1) / 2), printf('%08x-0000-4000-8000-%012x', 2, dep),
  printf('%08x-0000-4000-8000-%012x', 8, i * 3), 'Scheduled',
  CASE ((dep - 1) % 15) % 3 WHEN 0 THEN 'default' WHEN 1 THEN 'high-priority' ELSE 'backfill' END,
  '2026-10-30 10:00:00.000000',
  json_object('id', printf('%08x-0000-4000-8000-%012x', 3, dep), 'type', 'SCHEDULE', 'display_value', NULL),
  printf('%08x-0000-4000-8000-%012x', 5, (dep - 1) % 15 + 1), '{}', '{"retries": 0, "retry_delay": 0}', '{}'
FROM f WHERE NOT (dep > 100 AND k > 120 AND k <= 360);

-- flow run states: Scheduled (or Pending for ad-hoc runs), Running, then the final state; state_id points at the third.
-- Running runs get Scheduled, Pending, Running. Future runs get only their Scheduled state (as the 3rd slot).
INSERT INTO flow_run_state(id, created, updated, type, timestamp, name, message, state_details, data, flow_run_id)
SELECT printf('%08x-0000-4000-8000-%012x', 8, i * 3 - 2 + k), strftime('%Y-%m-%d %H:%M:%f000', ts), strftime('%Y-%m-%d %H:%M:%f000', ts),
  typ, strftime('%Y-%m-%d %H:%M:%f000', ts), nm,
  CASE WHEN typ = 'FAILED' THEN 'Flow run encountered an exception: ValueError(''bad row ' || (h % 997) || ''')'
       WHEN typ = 'CRASHED' THEN 'Flow run infrastructure exited with non-zero status code 137.' ELSE NULL END,
  json_object('flow_run_id', printf('%08x-0000-4000-8000-%012x', 7, i), 'scheduled_time', CASE WHEN k = 0 THEN strftime('%Y-%m-%dT%H:%M:%S+00:00', exp_jd) END,
              'pause_reschedule', json('false'), 'untrackable_result', json('false')),
  NULL, printf('%08x-0000-4000-8000-%012x', 7, i)
FROM (SELECT i, h, k, exp_jd,
        CASE k WHEN 0 THEN exp_jd - 0.01 WHEN 1 THEN start_jd - 2.0 / 86400 ELSE coalesce(end_jd, start_jd) END AS ts,
        CASE WHEN k = 0 THEN CASE WHEN dep IS NULL THEN 'PENDING' ELSE 'SCHEDULED' END
             WHEN k = 1 THEN CASE WHEN st = 'RUNNING' THEN 'PENDING' ELSE 'RUNNING' END ELSE st END AS typ,
        CASE WHEN k = 0 THEN CASE WHEN dep IS NULL THEN 'Pending' ELSE 'Scheduled' END
             WHEN k = 1 THEN CASE WHEN st = 'RUNNING' THEN 'Pending' ELSE 'Running' END
             ELSE CASE st WHEN 'COMPLETED' THEN 'Completed' WHEN 'FAILED' THEN 'Failed' WHEN 'CRASHED' THEN 'Crashed'
                          WHEN 'CANCELLED' THEN 'Cancelled' ELSE 'Running' END END AS nm
      FROM _fr, (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2));

INSERT INTO flow_run_state(id, created, updated, type, timestamp, name, state_details, flow_run_id)
SELECT state_id, created, created, 'SCHEDULED', created, 'Scheduled',
  json_object('flow_run_id', id, 'scheduled_time', next_scheduled_start_time), id
FROM flow_run WHERE state_type = 'SCHEDULED';

-- task runs ----------------------------------------------------------------------------------------------
-- Task run id = (flow run i) * 1024 + k. Hot deployments run 8 tasks, others 2, one run in 2000 fans out to 600.
-- Task k > 1 takes task k-1 (and task 1) as inputs, so the run graph has edges.
CREATE TEMP TABLE _k(k INTEGER PRIMARY KEY);
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 600) INSERT INTO _k SELECT k FROM n;

INSERT INTO task_run(id, created, updated, name, state_type, run_count, expected_start_time, start_time, end_time,
                     total_run_time, task_key, dynamic_key, cache_key, task_version, empirical_policy, task_inputs, tags,
                     flow_run_id, state_id, state_name, state_timestamp, flow_run_run_count, labels)
SELECT printf('%08x-0000-4000-8000-%012x', 9, i * 1024 + k),
  strftime('%Y-%m-%d %H:%M:%f000', ts), strftime('%Y-%m-%d %H:%M:%f000', coalesce(te, ts)),
  tname || '-' || printf('%03x', (h / (k + 3)) % 4096), tst, CASE WHEN tst = 'PENDING' THEN 0 ELSE 1 END,
  strftime('%Y-%m-%d %H:%M:%f000', ts), CASE WHEN tst = 'PENDING' THEN NULL ELSE strftime('%Y-%m-%d %H:%M:%f000', ts) END,
  CASE WHEN te IS NULL THEN NULL ELSE strftime('%Y-%m-%d %H:%M:%f000', te) END,
  CASE WHEN te IS NULL THEN '1970-01-01 00:00:00.000000' ELSE strftime('%Y-%m-%d %H:%M:%f000', 2440587.5 + (te - ts)) END,
  'pipeline.' || tname || '-' || printf('%08x', (k * 2654435761) % 4294967296), CAST(k - 1 AS TEXT),
  CASE WHEN k % 4 = 0 THEN 'cache-' || printf('%x', h % 65536) ELSE NULL END, NULL,
  '{"max_retries": 0, "retry_delay_seconds": 0.0, "retries": 2, "retry_delay": 10, "retry_jitter_factor": null}',
  CASE WHEN k = 1 THEN '{"__parents__": []}'
       ELSE json_object('rows', json_array(json_object('input_type', 'task_run', 'id', printf('%08x-0000-4000-8000-%012x', 9, i * 1024 + CASE WHEN k > 3 AND k % 2 = 0 THEN 1 ELSE k - 1 END))),
                        '__parents__', json_array()) END,
  CASE WHEN k % 3 = 0 THEN '["io"]' ELSE '[]' END,
  printf('%08x-0000-4000-8000-%012x', 7, i), printf('%08x-0000-4000-8000-%012x', 10, i * 1024 + k),
  CASE tst WHEN 'COMPLETED' THEN CASE WHEN k % 4 = 0 THEN 'Cached' ELSE 'Completed' END WHEN 'FAILED' THEN 'Failed'
           WHEN 'CRASHED' THEN 'Crashed' WHEN 'CANCELLED' THEN 'Cancelled' WHEN 'RUNNING' THEN 'Running' ELSE 'Pending' END,
  strftime('%Y-%m-%d %H:%M:%f000', coalesce(te, ts)), 1, '{}'
FROM (SELECT f.i, f.h, _k.k, nk,
        CASE _k.k % 5 WHEN 0 THEN 'extract' WHEN 1 THEN 'load' WHEN 2 THEN 'transform' WHEN 3 THEN 'validate' ELSE 'publish' END AS tname,
        f.start_jd + (f.dur_s * (_k.k - 1.0) / nk) / 86400.0 AS ts,
        CASE WHEN f.end_jd IS NULL AND _k.k > nk / 2 THEN NULL ELSE f.start_jd + (f.dur_s * (_k.k - 0.2) / nk) / 86400.0 END AS te,
        CASE WHEN f.end_jd IS NULL THEN CASE WHEN _k.k > nk / 2 + 1 THEN 'PENDING' WHEN _k.k > nk / 2 THEN 'RUNNING' ELSE 'COMPLETED' END
             WHEN f.st = 'COMPLETED' THEN 'COMPLETED'
             WHEN _k.k = nk THEN f.st
             ELSE 'COMPLETED' END AS tst
      FROM (SELECT _fr.*, CASE WHEN i % 3000 = 0 THEN 600 WHEN dep <= 10 THEN 5 ELSE 1 END AS nk FROM _fr) f
      JOIN _k ON _k.k <= f.nk);

INSERT INTO task_run_state(id, created, updated, type, timestamp, name, state_details, data, task_run_id)
SELECT state_id, state_timestamp, state_timestamp, state_type, state_timestamp, state_name,
  json_object('cache_key', cache_key, 'untrackable_result', json('false')),
  NULL, id
FROM task_run;

-- logs: 3 per past flow run, the last one at the task level ------------------------------------------------
INSERT INTO log(id, created, updated, name, level, flow_run_id, task_run_id, message, timestamp)
SELECT printf('%08x-0000-4000-8000-%012x', 11, i * 4 + k), strftime('%Y-%m-%d %H:%M:%f000', start_jd + k / 86400.0),
  strftime('%Y-%m-%d %H:%M:%f000', start_jd + k / 86400.0),
  CASE k WHEN 2 THEN 'prefect.task_runs' ELSE 'prefect.flow_runs' END,
  CASE WHEN k = 2 AND st IN ('FAILED', 'CRASHED') THEN 40 WHEN (h / (k + 5)) % 9 = 0 THEN 30 ELSE 20 END,
  printf('%08x-0000-4000-8000-%012x', 7, i),
  CASE k WHEN 2 THEN printf('%08x-0000-4000-8000-%012x', 9, i * 1024 + 1) ELSE NULL END,
  CASE k WHEN 0 THEN 'Beginning flow run ''' || i || ''' for flow ''pipeline-' || flow || ''''
         WHEN 1 THEN 'Loaded ' || (h % 50000) || ' rows from s3://bucket/raw/' || strftime('%Y/%m/%d', exp_jd) || '/part-' || (h % 64) || '.parquet'
         ELSE CASE WHEN st IN ('FAILED', 'CRASHED') THEN 'Task run failed with exception: ValueError(''bad row'') - Retries are exhausted'
                   ELSE 'Finished in state Completed()' END END,
  strftime('%Y-%m-%d %H:%M:%f000', start_jd + k / 86400.0)
FROM _fr, (SELECT 1 AS k UNION ALL SELECT 2)
WHERE k = 2 OR i % 3 = 0;

-- artifacts: one per 10 runs, keyed by deployment ---------------------------------------------------------
INSERT INTO artifact(id, created, updated, key, type, data, metadata_, task_run_id, flow_run_id, description)
SELECT printf('%08x-0000-4000-8000-%012x', 12, i), strftime('%Y-%m-%d %H:%M:%f000', start_jd), strftime('%Y-%m-%d %H:%M:%f000', start_jd),
  CASE WHEN h % 5 = 0 THEN NULL ELSE 'report-' || ((h / 8) % 150) END, CASE WHEN h % 2 = 0 THEN 'markdown' ELSE 'table' END,
  '"| metric | value |\n|---|---|\n| rows | ' || (h % 50000) || ' |"', NULL,
  printf('%08x-0000-4000-8000-%012x', 9, i * 1024 + 1), printf('%08x-0000-4000-8000-%012x', 7, i), 'Run summary'
FROM _fr WHERE i % 10 = 0;

INSERT INTO artifact_collection(id, created, updated, key, latest_id, task_run_id, flow_run_id, type, data, description, metadata_)
SELECT printf('%08x-0000-4000-8000-%012x', 13, row_number() OVER (ORDER BY key)), min(created), max(created), key,
  (SELECT a2.id FROM artifact a2 WHERE a2.key = a.key ORDER BY a2.created DESC LIMIT 1), NULL, NULL, 'markdown', NULL, 'Run summary', NULL
FROM artifact a WHERE key IS NOT NULL GROUP BY key;

-- events: the flow run state-change events of the last 10 days (retention is 7) ----------------------------
-- Each event has related flow, deployment (if any) and work-queue resources; event_resources holds the primary
-- resource plus the related ones, as _write_sqlite_events does.
CREATE TEMP TABLE _ev AS
SELECT s.rowid AS n, s.flow_run_id AS fr_id, fr.flow_id, fr.deployment_id, fr.work_queue_id, fr.name AS fr_name,
  s.timestamp AS occurred, 'prefect.flow-run.' || s.name AS event, s.type, s.name AS state_name, s.id AS state_id
FROM flow_run_state s JOIN flow_run fr ON fr.id = s.flow_run_id
WHERE s.timestamp >= strftime('%Y-%m-%d %H:%M:%f000', 2461344.0 - 8.5) AND s.timestamp <= '2026-10-30 12:00:00.000000'
  AND s.type NOT IN ('SCHEDULED', 'PENDING', 'RUNNING');

INSERT INTO events(occurred, event, resource_id, resource, related_resource_ids, related, payload, received, recorded, follows, id, created, updated)
SELECT occurred, event, 'prefect.flow-run.' || fr_id,
  json_object('prefect.resource.id', 'prefect.flow-run.' || fr_id, 'prefect.resource.name', fr_name,
              'prefect.state-message', '', 'prefect.state-name', state_name, 'prefect.state-timestamp', occurred,
              'prefect.state-type', type),
  CASE WHEN deployment_id IS NULL THEN json_array('prefect.flow.' || flow_id)
       ELSE json_array('prefect.flow.' || flow_id, 'prefect.deployment.' || deployment_id, 'prefect.work-queue.' || work_queue_id) END,
  CASE WHEN deployment_id IS NULL THEN json_array(json_object('prefect.resource.id', 'prefect.flow.' || flow_id, 'prefect.resource.role', 'flow', 'prefect.resource.name', 'pipeline'))
       ELSE json_array(json_object('prefect.resource.id', 'prefect.flow.' || flow_id, 'prefect.resource.role', 'flow', 'prefect.resource.name', 'pipeline'),
                       json_object('prefect.resource.id', 'prefect.deployment.' || deployment_id, 'prefect.resource.role', 'deployment', 'prefect.resource.name', 'prod'),
                       json_object('prefect.resource.id', 'prefect.work-queue.' || work_queue_id, 'prefect.resource.role', 'work-queue', 'prefect.resource.name', 'default')) END,
  json_object('intended', json_object('from', NULL, 'to', type), 'initial_state', NULL, 'validated_state', json_object('type', type, 'name', state_name)),
  occurred, occurred, NULL, printf('%08x-0000-4000-8000-%012x', 14, n), occurred, occurred
FROM _ev;

INSERT INTO event_resources(occurred, resource_id, resource_role, resource, event_id, id, created, updated)
SELECT occurred, rid, role, res, printf('%08x-0000-4000-8000-%012x', 14, n), printf('%08x-0000-4000-8000-%012x', 15, n * 4 + r), occurred, occurred
FROM (SELECT n, occurred, 0 AS r, 'prefect.flow-run.' || fr_id AS rid, '' AS role, json_object('prefect.resource.name', fr_name) AS res FROM _ev
      UNION ALL SELECT n, occurred, 1, 'prefect.flow.' || flow_id, 'flow', '{"prefect.resource.name": "pipeline"}' FROM _ev
      UNION ALL SELECT n, occurred, 2, 'prefect.deployment.' || deployment_id, 'deployment', '{"prefect.resource.name": "prod"}' FROM _ev WHERE deployment_id IS NOT NULL
      UNION ALL SELECT n, occurred, 3, 'prefect.work-queue.' || work_queue_id, 'work-queue', '{"prefect.resource.name": "default"}' FROM _ev WHERE deployment_id IS NOT NULL);

DROP TABLE _ev;
DROP TABLE _fr;
DROP TABLE _k;
DROP TABLE _c;
COMMIT;
