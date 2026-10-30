-- Synthetic data for MLflow's SQLAlchemy tracking store. Deterministic (no random()): values come from
-- multiplicative hashes of the row number. "Now" is 1793000000000 ms (2026-10-26); runs span 120 days, traces 14 days,
-- both skewed towards recent. Scale 1: 10 experiments, 15k runs (10k in the churn sweep), 75k params, 75k tags, 60k
-- latest_metrics, ~196k metric points (8 long training runs carry 2 x 5000 steps, one system-metrics run 6k points
-- all on step 0), 16k dataset inputs; the LLM-agent experiment holds 9k traces with ~45k spans (one runaway agent trace
-- has 5000 spans), 27k trace tags, 54k request-metadata rows and ~7.7k assessments. _cfg.scale multiplies runs and
-- traces.
BEGIN;

INSERT INTO experiments(experiment_id, name, artifact_location, lifecycle_stage, creation_time, last_update_time, workspace)
VALUES
 (0, 'Default', 'mlflow-artifacts:/0', 'active', 1780000000000, 1780000000000, 'default'),
 (1, 'churn-model', 'mlflow-artifacts:/1', 'active', 1782600000000, 1792990000000, 'default'),
 (2, 'fraud-xgb', 'mlflow-artifacts:/2', 'active', 1783000000000, 1792900000000, 'default'),
 (3, 'cv-resnet50', 'mlflow-artifacts:/3', 'active', 1784000000000, 1792500000000, 'default'),
 (4, 'support-agent', 'mlflow-artifacts:/4', 'active', 1791000000000, 1792999000000, 'default'),
 (5, '/Users/dana@corp.example/forecast', 'mlflow-artifacts:/5', 'active', 1785000000000, 1790000000000, 'default'),
 (6, 'ranker-ltr', 'mlflow-artifacts:/6', 'active', 1786000000000, 1791000000000, 'default'),
 (7, 'churn-model-old', 'mlflow-artifacts:/7', 'deleted', 1779000000000, 1781000000000, 'default'),
 (8, 'nlp-intent', 'mlflow-artifacts:/8', 'active', 1787000000000, 1792000000000, 'default'),
 (9, 'tmp-debug', 'mlflow-artifacts:/9', 'deleted', 1788000000000, 1788100000000, 'default');
INSERT INTO experiment_tags("key", value, experiment_id) VALUES
 ('mlflow.note.content', 'Weekly churn retrain sweep', 1), ('team', 'growth', 1), ('team', 'risk', 2),
 ('mlflow.experimentKind', 'genai_development', 4), ('team', 'support', 4), ('team', 'vision', 3);

-- Runs. e = experiment from a per-row hash (stable across scales); u = recency in [0,1) (squared: most runs are recent).
CREATE TEMP TABLE _r(i INTEGER PRIMARY KEY, run_uuid TEXT, e INT, h INT, st INT, n INT);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 15000*(SELECT scale FROM _cfg)),
g AS (SELECT i, (i * 2654435761) % 4294967296 AS h, ((i * 40503) % 65537) / 65537.0 AS f FROM n)
INSERT INTO _r(i, run_uuid, e, h)
SELECT i, printf('%08x%08x%08x%08x', h, (i * 2246822519) % 4294967296, (i * 3266489917) % 4294967296, (i * 668265263) % 4294967296),
  CASE WHEN f < 0.6667 THEN 1 WHEN f < 0.8667 THEN 2 WHEN f < 0.9067 THEN 3 WHEN f < 0.91 THEN 4
       ELSE 5 + (i % 5) END, h
FROM g;
UPDATE _r SET st = 1793000000000 - CAST(10368000000.0 * ((h % 1000003) / 1000003.0) * ((h % 1000003) / 1000003.0) AS INT)
             - (h / 7) % 60000;
UPDATE _r SET n = w.rn FROM (SELECT i, row_number() OVER (PARTITION BY e ORDER BY st) AS rn FROM _r) w WHERE w.i = _r.i;

INSERT INTO runs(run_uuid, name, source_type, source_name, entry_point_name, user_id, status, start_time, end_time,
                 source_version, lifecycle_stage, artifact_uri, experiment_id, deleted_time)
SELECT run_uuid,
  CASE WHEN e = 1 THEN 'sweep-' || n
       ELSE (SELECT value FROM json_each('["bold","calm","brave","shy","wise","merry","sly","zany"]') WHERE key = h % 8) || '-' ||
            (SELECT value FROM json_each('["hen","owl","fox","eel","yak","ant","doe","ram","cod"]') WHERE key = (h / 8) % 9) || '-' || (h / 128) % 1000 END,
  CASE (h / 64) % 5 WHEN 0 THEN 'NOTEBOOK' WHEN 1 THEN 'JOB' ELSE 'LOCAL' END,
  CASE e WHEN 1 THEN 'train_churn.py' WHEN 2 THEN 'xgb/train.py' WHEN 3 THEN 'train.py' ELSE '/Repos/ml/notebook' END,
  NULL,
  CASE WHEN (h / 512) % 10 < 5 THEN 'alice' WHEN (h / 512) % 10 < 7 THEN 'bob' ELSE 'user' || ((h / 512) % 23) END,
  CASE WHEN st > 1793000000000 - 3600000 AND (h / 4096) % 3 = 0 THEN 'RUNNING'
       WHEN (h / 4096) % 100 < 8 THEN 'FAILED' WHEN (h / 4096) % 100 < 10 THEN 'KILLED' ELSE 'FINISHED' END,
  st,
  CASE WHEN st > 1793000000000 - 3600000 AND (h / 4096) % 3 = 0 THEN NULL ELSE st + 20000 + (h / 16) % 3600000 END,
  printf('%07x', (h / 3) % 268435456),
  CASE WHEN (h / 65536) % 100 < 3 OR e IN (7, 9) THEN 'deleted' ELSE 'active' END,
  'mlflow-artifacts:/' || e || '/' || run_uuid || '/artifacts',
  e,
  CASE WHEN (h / 65536) % 100 < 3 OR e IN (7, 9) THEN st + 86400000 ELSE NULL END
FROM _r ORDER BY i;

-- Params: 5 per run, names by experiment family.
INSERT INTO params("key", value, run_uuid)
SELECT p.k,
  CASE p.k WHEN 'lr' THEN printf('%g', 0.0001 * (1 + (r.h / 32) % 100))
           WHEN 'optimizer' THEN CASE (r.h / 8) % 3 WHEN 0 THEN 'adam' WHEN 1 THEN 'sgd' ELSE 'adamw' END
           WHEN 'batch_size' THEN CAST(32 * (1 << ((r.h / 16) % 4)) AS TEXT)
           WHEN 'n_estimators' THEN CAST(100 * (1 + (r.h / 256) % 10) AS TEXT)
           WHEN 'max_depth' THEN CAST(3 + (r.h / 1024) % 9 AS TEXT)
           WHEN 'model_type' THEN CASE (r.h / 2048) % 3 WHEN 0 THEN 'lightgbm' WHEN 1 THEN 'xgboost' ELSE 'catboost' END
           WHEN 'epochs' THEN CAST(10 * (1 + (r.h / 64) % 5) AS TEXT)
           WHEN 'dataset_version' THEN 'v' || (1 + (r.h / 4096) % 7)
           ELSE printf('%.3f', ((r.h / 128) % 1000) / 1000.0) END,
  r.run_uuid
FROM _r r JOIN (SELECT 'lr' AS k, 0 AS fam UNION ALL SELECT 'optimizer', 0 UNION ALL SELECT 'batch_size', 0
                UNION ALL SELECT 'epochs', 0 UNION ALL SELECT 'dataset_version', 0
                UNION ALL SELECT 'lr', 1 UNION ALL SELECT 'n_estimators', 1 UNION ALL SELECT 'max_depth', 1
                UNION ALL SELECT 'model_type', 1 UNION ALL SELECT 'dataset_version', 1) p
  ON p.fam = CASE WHEN r.e IN (1, 2, 6) THEN 1 ELSE 0 END
ORDER BY r.i;

-- Tags: 4 of the system tags every fluent run gets plus a user 'stage' tag.
INSERT INTO tags("key", value, run_uuid)
SELECT t.k,
  CASE t.k WHEN 'mlflow.runName' THEN rn.name WHEN 'mlflow.user' THEN rn.user_id
           WHEN 'mlflow.source.name' THEN rn.source_name WHEN 'mlflow.source.type' THEN rn.source_type
           WHEN 'mlflow.source.git.commit' THEN printf('%08x%08x', r.h, (r.h * 7) % 4294967296)
           ELSE CASE (r.h / 8192) % 10 WHEN 0 THEN 'prod-candidate' WHEN 1 THEN 'baseline' ELSE 'sweep' END END,
  r.run_uuid
FROM _r r JOIN runs rn ON rn.run_uuid = r.run_uuid
JOIN (SELECT 'mlflow.runName' AS k UNION ALL SELECT 'mlflow.user' UNION ALL SELECT 'mlflow.source.name'
      UNION ALL SELECT 'mlflow.source.git.commit' UNION ALL SELECT 'stage') t
ORDER BY r.i;

-- Metrics. Every run logs 4 final metrics; churn runs also log val_loss per epoch (10); 1 in 75 cv-resnet50 runs
-- (~8) are long trainings with loss/val_loss over 5000 steps; one cv run streams system metrics (6k points, step 0).
CREATE TEMP TABLE _m(k INT PRIMARY KEY, name TEXT);
INSERT INTO _m VALUES (0, 'loss'), (1, 'val_loss'), (2, 'accuracy'), (3, 'auc');
CREATE TEMP TABLE _fin AS
SELECT r.run_uuid, r.i, r.e, r.h, r.st, m.name AS key,
  CASE m.k WHEN 0 THEN 0.05 + ((r.h / 32) % 6000) / 10000.0 WHEN 1 THEN 0.08 + ((r.h / 64) % 7000) / 10000.0
           WHEN 2 THEN 0.55 + ((r.h / 128) % 4400) / 10000.0 ELSE 0.6 + ((r.h / 256) % 3990) / 10000.0 END AS value,
  CASE WHEN r.e = 3 AND (r.h / 1024) % 75 = 0 THEN 4999 WHEN r.e = 1 THEN 4 ELSE 0 END AS step,
  CASE WHEN m.k = 3 AND (r.h / 16384) % 211 = 0 THEN 1 ELSE 0 END AS is_nan
FROM _r r JOIN _m m;
INSERT INTO latest_metrics("key", value, timestamp, step, is_nan, run_uuid)
SELECT key, CASE WHEN is_nan THEN 0.0 ELSE value END, st + 600000 + step * 1000, step, is_nan, run_uuid FROM _fin ORDER BY i;
INSERT INTO metrics("key", value, timestamp, run_uuid, step, is_nan)
SELECT key, CASE WHEN is_nan THEN 0.0 ELSE value END, st + 600000 + step * 1000, run_uuid, step, is_nan FROM _fin
WHERE NOT (e = 1 AND key = 'val_loss') ORDER BY i;
WITH RECURSIVE s(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM s WHERE k < 4)
INSERT INTO metrics("key", value, timestamp, run_uuid, step, is_nan)
SELECT 'val_loss', f.value + (4 - s.k) * 0.05 + ((f.h / (s.k + 3)) % 100) / 5000.0, f.st + 60000 * (s.k + 1), f.run_uuid, s.k, 0
FROM _fin f JOIN s WHERE f.e = 1 AND f.key = 'val_loss' ORDER BY f.i, s.k;
WITH RECURSIVE s(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM s WHERE k < 4998)
INSERT INTO metrics("key", value, timestamp, run_uuid, step, is_nan)
SELECT f.key, f.value + 2.0 * exp(-s.k / 800.0) + ((s.k * 2654435761 + f.h) % 1000) / 20000.0,
       f.st + 1000 * s.k, f.run_uuid, s.k, 0
FROM _fin f JOIN s WHERE f.step = 4999 AND f.key IN ('loss', 'val_loss') ORDER BY f.i, f.key, s.k;
WITH RECURSIVE s(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM s WHERE k < 5999)
INSERT INTO metrics("key", value, timestamp, run_uuid, step, is_nan)
SELECT 'system/gpu_0_utilization_percentage', 40 + (s.k * 2654435761 % 6000) / 100.0, f.st + 10000 * s.k, f.run_uuid, 0, 0
FROM (SELECT * FROM _fin WHERE step = 4999 AND key = 'loss' ORDER BY i LIMIT 1) f JOIN s;
INSERT INTO latest_metrics("key", value, timestamp, step, is_nan, run_uuid)
SELECT 'system/gpu_0_utilization_percentage', 77.5, st + 99990000, 0, 0, run_uuid
FROM (SELECT * FROM _fin WHERE step = 4999 AND key = 'loss' ORDER BY i LIMIT 1);

-- Dataset inputs: every churn run logs its training table (5 dataset versions), fraud runs log train + eval.
INSERT INTO datasets(dataset_uuid, experiment_id, name, digest, dataset_source_type, dataset_source, dataset_schema, dataset_profile)
SELECT printf('ds%030x', k), CASE WHEN k < 5 THEN 1 ELSE 2 END,
  CASE WHEN k < 5 THEN 'churn_features_v' || (k + 1) WHEN k = 5 THEN 'fraud_train' ELSE 'fraud_eval' END,
  printf('%08x', k * 2654435761 % 4294967296), 'delta',
  '{"path": "s3://lake/ml/' || k || '", "delta_table_version": ' || (10 + k) || '}',
  '{"mlflow_colspec": [{"type": "double", "name": "tenure"}, {"type": "long", "name": "n_calls"}, {"type": "string", "name": "plan"}]}',
  '{"num_rows": ' || (100000 + k * 5000) || ', "num_elements": ' || (300000 + k * 15000) || '}'
FROM (WITH RECURSIVE n(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM n WHERE k < 6) SELECT k FROM n);
INSERT INTO inputs(input_uuid, source_type, source_id, destination_type, destination_id, step)
SELECT printf('in%030x', r.i * 2 + d.j), 'DATASET',
  printf('ds%030x', CASE WHEN r.e = 1 THEN (r.h / 64) % 5 ELSE 5 + d.j END), 'RUN', r.run_uuid, 0
FROM _r r JOIN (SELECT 0 AS j UNION ALL SELECT 1) d ON (r.e = 1 AND d.j = 0) OR r.e = 2 ORDER BY r.i;
INSERT INTO input_tags(input_uuid, name, value)
SELECT input_uuid, 'mlflow.data.context', CASE WHEN substr(source_id, -1) = '6' THEN 'eval' ELSE 'training' END FROM inputs;

-- Traces of the support agent (experiment 4): 14 days, recent-heavy; sessions of 6 consecutive traces ~45 s apart;
-- 8 % errors.
CREATE TEMP TABLE _tr(i INTEGER PRIMARY KEY, rid TEXT, h INT, ts INT, ex INT, nsp INT);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 9000*(SELECT scale FROM _cfg)),
g AS (SELECT i, (i * 2246822519) % 4294967296 AS h FROM n)
INSERT INTO _tr
SELECT i, 'tr-' || printf('%08x%08x%08x%08x', h, (i * 2654435761) % 4294967296, (i * 3266489917) % 4294967296, (i * 374761393) % 4294967296),
  h, 1793000000000 - 400000 - CAST(1209600000.0 * ((((i + 5) / 6) * 2654435761 % 999983) / 999983.0)
                                               * ((((i + 5) / 6) * 2654435761 % 999983) / 999983.0) AS INT)
     + ((i + 5) % 6) * 45000 + (h / 4) % 30000,
  CASE WHEN i = 777 THEN 1850000 WHEN (h / 8) % 50 = 0 THEN 30000 + (h / 16) % 90000 ELSE 300 + ((h / 16) % 1000) * ((h / 16384) % 12 + 1) END,
  CASE WHEN i = 777 THEN 5000 ELSE 3 + (h / 32) % 4 END
FROM g;
INSERT INTO trace_info(request_id, experiment_id, timestamp_ms, execution_time_ms, status, client_request_id, request_preview,
                       response_preview, db_payload_generation, trace_name, session_id, input_tokens, output_tokens, total_tokens,
                       cache_read_input_tokens, cache_creation_input_tokens, cache_creation_input_tokens_above_1hr, input_cost,
                       output_cost, total_cost)
SELECT rid, 4, ts, ex, CASE WHEN (h / 1024) % 100 < 8 THEN 'ERROR' WHEN i % 4001 = 0 THEN 'IN_PROGRESS' ELSE 'OK' END, NULL,
  '{"messages": [{"role": "user", "content": "' ||
    (SELECT value FROM json_each('["Where is my refund for order","How do I reset my password on","Cancel subscription plan","Invoice shows a double charge for","Upgrade to the team plan for"]') WHERE key = (h / 64) % 5)
    || ' #' || (h % 100000) || '?"}]}',
  '{"role": "assistant", "content": "' ||
    (SELECT value FROM json_each('["I have opened a refund request","Here are the steps to reset","Your subscription has been cancelled","I can see two charges on","I have upgraded your workspace"]') WHERE key = (h / 64) % 5)
    || ' (ticket ' || (h % 9973) || ')."}',
  4,
  CASE (h / 4096) % 10 WHEN 0 THEN 'rag_chain' WHEN 1 THEN 'triage_classifier' ELSE 'support_agent' END,
  'sess-' || ((i + 5) / 6),
  600 * (nsp - 2) + (h / 8) % 900, 60 * (nsp - 2) + (h / 32) % 200, NULL, CASE WHEN (h / 128) % 3 = 0 THEN 512 ELSE NULL END,
  NULL, NULL, NULL, NULL, NULL
FROM _tr ORDER BY i;
UPDATE trace_info SET total_tokens = input_tokens + output_tokens, input_cost = input_tokens * 1.5e-07,
                      output_cost = output_tokens * 6e-07, total_cost = input_tokens * 1.5e-07 + output_tokens * 6e-07;

INSERT INTO trace_tags("key", value, request_id)
SELECT k.k, CASE k.k WHEN 'mlflow.artifactLocation' THEN 'mlflow-artifacts:/4/traces/' || t.rid || '/artifacts'
                     WHEN 'mlflow.trace.spansLocation' THEN 'TRACKING_STORE'
                     ELSE CASE WHEN (t.h / 2048) % 4 = 0 THEN 'staging' ELSE 'prod' END END, t.rid
FROM _tr t JOIN (SELECT 'mlflow.artifactLocation' AS k UNION ALL SELECT 'mlflow.trace.spansLocation' UNION ALL SELECT 'env') k
ORDER BY t.i;
INSERT INTO trace_request_metadata("key", value, request_id)
SELECT k.k, CASE k.k WHEN 'mlflow.trace_schema.version' THEN '3'
                     WHEN 'mlflow.trace.session' THEN ti.session_id
                     WHEN 'mlflow.trace.user' THEN 'customer-' || (t.h / 4) % 1500
                     WHEN 'mlflow.user' THEN 'svc-support'
                     WHEN 'mlflow.source.name' THEN 'app/agent.py'
                     WHEN 'mlflow.source.type' THEN 'LOCAL'
                     WHEN 'mlflow.trace.sizeBytes' THEN CAST(900 * t.nsp + t.h % 500 AS TEXT)
                     WHEN 'mlflow.traceInputs' THEN substr(ti.request_preview, 1, 120)
                     ELSE substr(ti.response_preview, 1, 120) END, t.rid
FROM _tr t JOIN trace_info ti ON ti.request_id = t.rid
JOIN (SELECT 'mlflow.trace_schema.version' AS k UNION ALL SELECT 'mlflow.trace.session' UNION ALL SELECT 'mlflow.trace.user'
      UNION ALL SELECT 'mlflow.source.name' UNION ALL SELECT 'mlflow.trace.sizeBytes' UNION ALL SELECT 'mlflow.traceInputs') k
ORDER BY t.i;

-- Spans: span 0 is the root AGENT/CHAIN, then alternating RETRIEVER / CHAT_MODEL / TOOL children. Model and cost
-- columns are set on CHAT_MODEL spans, as the store denormalises them from the span attributes.
CREATE TEMP TABLE _k AS WITH RECURSIVE s(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM s WHERE k < 4999) SELECT k FROM s;
CREATE INDEX _k_k ON _k(k);
CREATE TEMP TABLE _sp AS
SELECT t.rid, t.i, t.h, t.ts, t.ex, t.nsp, s.k,
  printf('%016x', (t.i * 7919 + s.k) * 2654435761 % 18446744073709551) AS span_id,
  CASE WHEN s.k = 0 THEN CASE WHEN (t.h / 4096) % 10 = 0 THEN 'CHAIN' ELSE 'AGENT' END
       WHEN s.k % 3 = 1 THEN 'CHAT_MODEL' WHEN s.k % 3 = 2 THEN 'TOOL' ELSE 'RETRIEVER' END AS type,
  CASE (t.h / 256 + s.k) % 4 WHEN 0 THEN 'gpt-4o' WHEN 3 THEN 'claude-sonnet-4-5' ELSE 'gpt-4o-mini' END AS model
FROM _tr t JOIN _k s ON s.k < t.nsp;
INSERT INTO spans(trace_id, experiment_id, span_id, parent_span_id, name, type, status, start_time_unix_nano, end_time_unix_nano,
                  content, input_cost, output_cost, total_cost, model_name, model_provider)
SELECT rid, 4, span_id,
  CASE WHEN k = 0 THEN NULL ELSE printf('%016x', (i * 7919) * 2654435761 % 18446744073709551) END,
  CASE type WHEN 'AGENT' THEN 'support_agent' WHEN 'CHAIN' THEN 'rag_chain' WHEN 'CHAT_MODEL' THEN 'ChatOpenAI'
            WHEN 'TOOL' THEN CASE (h / 16 + k) % 3 WHEN 0 THEN 'lookup_order' WHEN 1 THEN 'issue_refund' ELSE 'search_kb' END
            ELSE 'VectorStoreRetriever' END,
  type,
  CASE WHEN k = 0 AND (h / 1024) % 100 < 8 THEN 'ERROR' WHEN k > 0 AND (h / 1024 + k) % 100 = 0 THEN 'ERROR' ELSE 'OK' END,
  ts * 1000000 + (CASE WHEN k = 0 THEN 0 ELSE (ex * 1000000 / (nsp + 1)) * k END),
  ts * 1000000 + (CASE WHEN k = 0 THEN ex * 1000000 ELSE (ex * 1000000 / (nsp + 1)) * (k + 1) END),
  '{"span_id": "' || span_id || '", "name": "' || type ||
   '", "events": [], "status": {"code": "STATUS_CODE_OK", "message": ""}, "attributes": {"mlflow.traceRequestId": "\"' || rid ||
   '\"", "mlflow.spanType": "\"' || type || '\""' ||
   CASE type WHEN 'CHAT_MODEL' THEN ', "mlflow.llm.model": "\"' || model || '\"", "mlflow.chat.tokenUsage": "{\"input_tokens\": ' || (400 + h % 900) ||
                                    ', \"output_tokens\": ' || (40 + h % 300) || '}"'
             WHEN 'RETRIEVER' THEN ', "mlflow.spanOutputs": "[{\"page_content\": \"Refunds are issued within 5 business days\", \"metadata\": {\"doc_id\": ' || (h % 800) || '}}]"'
             WHEN 'TOOL' THEN ', "mlflow.spanInputs": "{\"order_id\": ' || (h % 100000) || '}"'
             ELSE ', "mlflow.spanInputs": "{\"q\": \"customer question\"}"' END || '}, "links": []}',
  CASE WHEN type = 'CHAT_MODEL' THEN (400 + h % 900) * 1.5e-07 END,
  CASE WHEN type = 'CHAT_MODEL' THEN (40 + h % 300) * 6e-07 END,
  CASE WHEN type = 'CHAT_MODEL' THEN (400 + h % 900) * 1.5e-07 + (40 + h % 300) * 6e-07 END,
  CASE WHEN type = 'CHAT_MODEL' THEN model END,
  CASE WHEN type = 'CHAT_MODEL' THEN CASE WHEN model LIKE 'claude%' THEN 'anthropic' ELSE 'openai' END END
FROM _sp sp ORDER BY i, k;

-- Assessments: an LLM judge scores 55 % of traces for correctness (pass/fail), 20 % get a numeric relevance score,
-- 6 % a human thumbs label (some overriding the judge), 5 % carry an expected answer.
INSERT INTO assessments(assessment_id, trace_id, name, assessment_type, value, error, created_timestamp, last_updated_timestamp,
                        source_type, source_id, run_id, span_id, rationale, overrides, valid, assessment_metadata, experiment_id,
                        trace_timestamp_ms, aggregate_value, is_numeric_value)
SELECT printf('a-%08x%08x%04x', t.h, t.i, a.j), t.rid, a.name,
  CASE WHEN a.name = 'expected_answer' THEN 'expectation' ELSE 'feedback' END,
  CASE a.name WHEN 'correctness' THEN CASE WHEN (t.h / 16) % 100 < 81 THEN 'true' ELSE 'false' END
              WHEN 'relevance' THEN CAST(1 + (t.h / 64) % 5 AS TEXT)
              WHEN 'user_thumbs' THEN CASE WHEN (t.h / 32) % 3 = 0 THEN '"down"' ELSE '"up"' END
              ELSE '"The refund was issued"' END,
  NULL, t.ts + 60000 + a.j * 1000, t.ts + 60000 + a.j * 1000,
  CASE WHEN a.name IN ('correctness', 'relevance') THEN 'LLM_JUDGE' ELSE 'HUMAN' END,
  CASE WHEN a.name IN ('correctness', 'relevance') THEN 'gpt-4o' ELSE 'agent-' || (t.h % 12) END,
  NULL, NULL,
  CASE WHEN a.name = 'correctness' THEN 'The response addresses the customer request and cites the policy.' END,
  NULL, 1,
  CASE WHEN a.name = 'correctness' THEN '{"mlflow.assessment.judgeCost": "0.0004", "mlflow.assessment.sourceRunId": "' || (SELECT run_uuid FROM _r WHERE e = 4 ORDER BY i LIMIT 1) || '"}' END,
  4, t.ts,
  CASE a.name WHEN 'correctness' THEN CASE WHEN (t.h / 16) % 100 < 81 THEN 1.0 ELSE 0.0 END
              WHEN 'relevance' THEN 1 + (t.h / 64) % 5 END,
  CASE WHEN a.name = 'relevance' THEN 1 ELSE 0 END
FROM _tr t JOIN (SELECT 0 AS j, 'correctness' AS name, 55 AS pct UNION ALL SELECT 1, 'relevance', 20
                 UNION ALL SELECT 2, 'user_thumbs', 6 UNION ALL SELECT 3, 'expected_answer', 5) a
  ON (t.h / (128 + a.j)) % 100 < a.pct
ORDER BY t.i, a.j;

COMMIT;
