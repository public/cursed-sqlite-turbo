-- Synthetic data for n8n. Deterministic (no random()): values come from multiplicative hashes of the row number, each
-- column from different bits. "Now" for the data is 2026-10-28. Scale 1: 40 users with personal projects + 10 team
-- projects, 1.5k workflows (skewed ownership, some shared as editor), 200 folders, 30 tags, 80k executions over 60
-- days with execution_data/metadata/annotations, 1.2k webhooks, insights (hourly/daily/weekly periods + raw backlog).
BEGIN;

-- users / projects: projects 1..40 personal (owned by user i), 41..50 team
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 50)
INSERT INTO "project"("id", "name", "type", "createdAt", "updatedAt", "icon", "creatorId")
SELECT printf('p%015d', i),
       CASE WHEN i <= 40 THEN 'User ' || i || ' <user' || i || '@example.com>' ELSE 'Team ' || (i - 40) END,
       CASE WHEN i <= 40 THEN 'personal' ELSE 'team' END,
       '2025-01-01 00:00:00.000', '2025-01-01 00:00:00.000',
       CASE WHEN i > 40 THEN '{"type":"icon","value":"layers"}' ELSE NULL END,
       printf('00000000-0000-4000-8000-%012d', CASE WHEN i <= 40 THEN i ELSE 1 END)
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40)
INSERT OR IGNORE INTO "project_relation"("projectId", "userId", "role")
SELECT printf('p%015d', i), printf('00000000-0000-4000-8000-%012d', i), 'project:personalOwner' FROM n
UNION ALL
-- team members: user u is in team project 41 + (u*k) % 10 for k in 1..3; user 3 is in 41, 43, 45 explicitly
SELECT DISTINCT printf('p%015d', 41 + (u.i * k.k + k.k) % 10), printf('00000000-0000-4000-8000-%012d', u.i),
       CASE (u.i + k.k) % 4 WHEN 0 THEN 'project:admin' WHEN 3 THEN 'project:viewer' ELSE 'project:editor' END
FROM n u, (SELECT 1 AS k UNION ALL SELECT 2 UNION ALL SELECT 3) k
WHERE u.i <> 3
UNION ALL
SELECT printf('p%015d', t), printf('00000000-0000-4000-8000-%012d', 3), 'project:editor'
FROM (SELECT 41 AS t UNION ALL SELECT 43 UNION ALL SELECT 45);

-- folders in team projects
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 200)
INSERT INTO "folder"("id", "name", "parentFolderId", "projectId", "createdAt", "updatedAt")
SELECT printf('f%015d', i), 'Folder ' || i,
       CASE WHEN i > 50 THEN printf('f%015d', (i - 1) % 50 + 1) ELSE NULL END,
       printf('p%015d', 41 + ((CASE WHEN i > 50 THEN (i - 1) % 50 + 1 ELSE i END) % 10)),
       '2025-02-01 00:00:00.000', '2025-02-01 00:00:00.000'
FROM n;

CREATE TEMP TABLE _wf(i INTEGER PRIMARY KEY, id TEXT, h INTEGER, project INTEGER);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 1500*(SELECT scale FROM _cfg))
INSERT INTO _wf
SELECT i, printf('wf%014d', i), (i * 2654435761) % 4294967296,
       CASE WHEN ((i * 2654435761) % 4294967296) / 16 % 10 < 6 THEN 41 + ((i * 2654435761) % 4294967296) / 256 % 10
            ELSE 1 + ((i * 2654435761) % 4294967296) / 4096 % 40 END
FROM n;

INSERT INTO "workflow_entity"("id", "name", "active", "nodes", "connections", "createdAt", "updatedAt", "settings",
  "staticData", "pinData", "versionId", "triggerCount", "meta", "parentFolderId", "isArchived", "versionCounter",
  "description", "activeVersionId")
SELECT w.id,
       CASE (w.h / 65536) % 8 WHEN 0 THEN 'Sync CRM contacts' WHEN 1 THEN 'Slack alert on error' WHEN 2 THEN 'Daily report email'
            WHEN 3 THEN 'Webhook to Postgres' WHEN 4 THEN 'Invoice processing' WHEN 5 THEN 'AI agent support triage'
            WHEN 6 THEN 'GitHub issue labeler' ELSE 'Lead enrichment' END || ' #' || w.i,
       CASE WHEN (w.h / 1024) % 3 = 0 THEN 1 ELSE 0 END,
       '[{"id":"n1","name":"Trigger","type":"n8n-nodes-base.' ||
         CASE (w.h / 128) % 4 WHEN 0 THEN 'webhook' WHEN 1 THEN 'scheduleTrigger' WHEN 2 THEN 'manualTrigger' ELSE 'webhook' END ||
         '","typeVersion":1,"position":[0,0],"parameters":{}},{"id":"n2","name":"HTTP Request","type":"n8n-nodes-base.httpRequest","typeVersion":4,"position":[200,0],"parameters":{"url":"https://api.example.com/v1/items"}}]',
       '{"Trigger":{"main":[[{"node":"HTTP Request","type":"main","index":0}]]}}',
       strftime('%Y-%m-%d %H:%M:%f', unixepoch('2025-03-01') + w.i * 7200, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%f', unixepoch('2026-04-01') + (w.h % 15552000), 'unixepoch'),
       json_object('executionOrder', 'v1', 'saveManualExecutions', json('true'), 'callerPolicy', 'workflowsFromSameOwner',
                   'availableInMCP', CASE WHEN (w.h / 8192) % 5 = 0 THEN json('true') ELSE json('false') END),
       NULL, NULL,
       printf('%08x-0000-4000-8000-%012d', w.h, w.i),
       CASE WHEN (w.h / 1024) % 3 = 0 THEN 1 ELSE 0 END,
       '{"templateCredsSetupCompleted":true}',
       CASE WHEN w.project > 40 AND (w.h / 32768) % 2 = 0 THEN printf('f%015d', (w.project - 41) + 10 * ((w.h / 131072) % 5) + 1) ELSE NULL END,
       CASE WHEN (w.h / 2097152) % 25 = 0 THEN 1 ELSE 0 END,
       1 + (w.h % 7),
       CASE WHEN (w.h / 524288) % 3 = 0 THEN 'Pulls new rows and posts a summary to the ops channel' ELSE NULL END,
       CASE WHEN (w.h / 1024) % 3 = 0 THEN printf('%08x-0000-4000-8000-%012d', w.h, w.i) ELSE NULL END
FROM _wf w;

INSERT INTO "shared_workflow"("workflowId", "projectId", "role", "createdAt", "updatedAt")
SELECT w.id, printf('p%015d', w.project), 'workflow:owner', '2025-03-01 00:00:00.000', '2025-03-01 00:00:00.000' FROM _wf w
UNION ALL
SELECT w.id, printf('p%015d', 1 + (w.h / 64) % 40), 'workflow:editor', '2025-04-01 00:00:00.000', '2025-04-01 00:00:00.000'
FROM _wf w WHERE (w.h / 8) % 7 = 0 AND 1 + (w.h / 64) % 40 <> w.project;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 30)
INSERT INTO "tag_entity"("id", "name", "createdAt", "updatedAt")
SELECT printf('t%015d', i),
       CASE i WHEN 1 THEN 'production' WHEN 2 THEN 'staging' WHEN 3 THEN 'crm' WHEN 4 THEN 'ai' WHEN 5 THEN 'finance' ELSE 'tag-' || i END,
       strftime('%Y-%m-%d %H:%M:%f', unixepoch('2025-01-01') + i * 86400, 'unixepoch'), '2025-01-01 00:00:00.000'
FROM n;

INSERT INTO "workflows_tags"("workflowId", "tagId")
SELECT w.id, printf('t%015d', 1 + (w.h / 4) % 5) FROM _wf w
UNION
SELECT w.id, printf('t%015d', 1 + (w.h / 512) % 30) FROM _wf w WHERE (w.h / 16) % 2 = 0;

-- executions: 80k over the 60 days before 2026-10-28, popular workflows run far more often
CREATE TEMP TABLE _ex(i INTEGER PRIMARY KEY, h INTEGER, wf INTEGER, ts INTEGER, status TEXT);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 80000*(SELECT scale FROM _cfg))
INSERT INTO _ex
SELECT i, h,
       1 + ((h / 16) % 1500) * ((h / 65536) % 1500) / 1500 * (SELECT scale FROM _cfg),
       unixepoch('2026-08-29') + i * 64 / (SELECT scale FROM _cfg) + (h % 60),
       CASE WHEN i > 80000*(SELECT scale FROM _cfg) - 30 THEN 'running'
            ELSE CASE (h / 1024) % 100 WHEN 0 THEN 'crashed' WHEN 1 THEN 'canceled' WHEN 2 THEN 'waiting' WHEN 3 THEN 'waiting'
                 WHEN 4 THEN 'error' WHEN 5 THEN 'error' WHEN 6 THEN 'error' WHEN 7 THEN 'error' WHEN 8 THEN 'error'
                 WHEN 9 THEN 'error' WHEN 10 THEN 'error' WHEN 11 THEN 'error' WHEN 12 THEN 'error' WHEN 13 THEN 'error'
                 ELSE 'success' END END
FROM (SELECT i, (i * 2246822519) % 4294967296 AS h FROM n);

INSERT INTO "execution_entity"("id", "workflowId", "finished", "mode", "retryOf", "retrySuccessId", "startedAt", "stoppedAt",
  "waitTill", "status", "deletedAt", "createdAt", "storedAt", "jsonSizeBytes", "workflowVersionId", "binaryDataSizeBytes",
  "usedPrivateCredentials")
SELECT e.i, printf('wf%014d', e.wf),
       CASE WHEN e.status = 'success' THEN 1 ELSE 0 END,
       CASE (e.h / 128) % 40 WHEN 0 THEN 'evaluation' WHEN 1 THEN 'retry' WHEN 2 THEN 'integrated' WHEN 3 THEN 'integrated'
            WHEN 4 THEN 'manual' WHEN 5 THEN 'manual' WHEN 6 THEN 'manual' WHEN 7 THEN 'manual' WHEN 8 THEN 'manual' WHEN 9 THEN 'manual'
            ELSE CASE WHEN (e.h / 4096) % 3 = 0 THEN 'webhook' ELSE 'trigger' END END,
       CASE WHEN (e.h / 128) % 40 = 1 THEN CAST(e.i - 7 AS TEXT) ELSE NULL END,
       NULL,
       strftime('%Y-%m-%d %H:%M:%f', e.ts + 0.05, 'unixepoch'),
       CASE WHEN e.status IN ('running', 'waiting') THEN NULL
            ELSE strftime('%Y-%m-%d %H:%M:%f', e.ts + 0.05 + (e.h % 9000) / 1000.0 + CASE WHEN (e.h / 8) % 50 = 0 THEN 120 ELSE 0 END, 'unixepoch') END,
       CASE WHEN e.status = 'waiting' THEN strftime('%Y-%m-%d %H:%M:%f', unixepoch('2026-10-28') - 7200 + (e.h % 14400), 'unixepoch') ELSE NULL END,
       e.status,
       CASE WHEN e.status IN ('success', 'error') AND (e.h / 262144) % 50 = 0 THEN strftime('%Y-%m-%d %H:%M:%f', e.ts + 1209600, 'unixepoch') ELSE NULL END,
       strftime('%Y-%m-%d %H:%M:%f', e.ts, 'unixepoch'),
       'db', 200 + (e.h % 50000),
       printf('%08x-0000-4000-8000-%012d', (e.wf * 2654435761) % 4294967296, e.wf),
       CASE WHEN (e.h / 32) % 10 = 0 THEN e.h % 2000000 ELSE 0 END,
       CASE WHEN (e.h / 1048576) % 30 = 0 THEN 1 ELSE 0 END
FROM _ex e;

INSERT INTO "execution_data"("executionId", "workflowData", "data", "workflowVersionId")
SELECT e.i,
       '{"id":"' || printf('wf%014d', e.wf) || '","name":"wf ' || e.wf || '","nodes":[{"name":"Trigger"},{"name":"HTTP Request"}],"connections":{}}',
       '[{"version":1,"startData":"1","resultData":"2","executionData":"3"},{},{"runData":"4","lastNodeExecuted":"5"},{"nodeExecutionStack":[]},{"HTTP Request":"6"},"HTTP Request",[{"startTime":' || (e.ts * 1000) || ',"executionTime":' || (e.h % 900) || '}]]',
       printf('%08x-0000-4000-8000-%012d', (e.wf * 2654435761) % 4294967296, e.wf)
FROM _ex e;

INSERT INTO "execution_metadata"("executionId", "key", "value")
SELECT e.i, 'orderId', 'ORD-' || (e.h % 100000) FROM _ex e WHERE e.i % 5 = 0
UNION ALL
SELECT e.i, 'customer', CASE (e.h / 64) % 4 WHEN 0 THEN 'Acme Corp' WHEN 1 THEN 'Globex' WHEN 2 THEN 'Initech' ELSE 'Umbrella' END FROM _ex e WHERE e.i % 5 = 0
UNION ALL
SELECT e.i, 'source', CASE (e.h / 8) % 3 WHEN 0 THEN 'shopify' WHEN 1 THEN 'stripe' ELSE 'hubspot' END FROM _ex e WHERE e.i % 15 = 0;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 8)
INSERT INTO "annotation_tag_entity"("id", "name")
SELECT printf('at%014d', i), CASE i WHEN 1 THEN 'regression' WHEN 2 THEN 'flaky' WHEN 3 THEN 'reviewed' WHEN 4 THEN 'customer' ELSE 'label-' || i END FROM n;

INSERT INTO "execution_annotations"("id", "executionId", "vote", "note", "createdAt", "updatedAt")
SELECT e.i / 20, e.i, CASE (e.h / 16) % 3 WHEN 0 THEN 'up' WHEN 1 THEN 'down' ELSE NULL END,
       CASE WHEN (e.h / 16) % 5 = 0 THEN 'checked by ops' ELSE NULL END,
       strftime('%Y-%m-%d %H:%M:%f', e.ts + 3600, 'unixepoch'), strftime('%Y-%m-%d %H:%M:%f', e.ts + 3600, 'unixepoch')
FROM _ex e WHERE e.i % 20 = 0;

INSERT INTO "execution_annotation_tags"("annotationId", "tagId")
SELECT a.id, printf('at%014d', 1 + a.id % 4) FROM "execution_annotations" a WHERE a.id % 3 <> 0
UNION
SELECT a.id, printf('at%014d', 1 + (a.id / 3) % 8) FROM "execution_annotations" a WHERE a.id % 2 = 0;

-- webhooks: static paths for webhook-triggered workflows, a few dynamic ones with :params
INSERT INTO "webhook_entity"("workflowId", "webhookPath", "method", "node", "webhookId", "pathLength")
SELECT w.id, printf('%08x-%04x-4%03x-8%03x-%012x', w.h, w.i, w.i % 4096, (w.h / 7) % 4096, w.i * 7919),
       CASE (w.h / 2) % 4 WHEN 0 THEN 'GET' ELSE 'POST' END, 'Webhook', NULL, NULL
FROM _wf w WHERE (w.h / 128) % 4 IN (0, 3)
UNION ALL
SELECT w.id, printf('%08x-0000-4000-8000-%012d', w.h, w.i) || '/orders/:id', 'GET', 'Webhook',
       printf('%08x-0000-4000-8000-%012d', w.h, w.i), 2
FROM _wf w WHERE (w.h / 128) % 4 = 0 AND w.i % 5 = 0;

-- insights
INSERT INTO "insights_metadata"("metaId", "workflowId", "projectId", "workflowName", "projectName")
SELECT w.i, w.id, printf('p%015d', w.project), 'Workflow ' || w.i,
       CASE WHEN w.project <= 40 THEN 'User ' || w.project ELSE 'Team ' || (w.project - 40) END
FROM _wf w;

CREATE TEMP TABLE _ty(t INTEGER PRIMARY KEY);
INSERT INTO _ty VALUES (0), (1), (2), (3), (4);

-- hourly for the last 7 days for 50 busy workflows
WITH RECURSIVE hrs(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM hrs WHERE k < 167)
INSERT INTO "insights_by_period"("metaId", "type", "value", "periodUnit", "periodStart")
SELECT m, t, CASE t WHEN 0 THEN (m * 7 + k) % 30 WHEN 1 THEN 500 + (m * 131 + k * 17) % 20000 WHEN 2 THEN 1 + (m + k) % 12
                    WHEN 3 THEN (m * k) % 3 ELSE 1 + (m + k) % 13 END,
       0, strftime('%Y-%m-%d %H:00:00.000', unixepoch('2026-10-28') - 3600 * (k + 1), 'unixepoch')
FROM hrs, (SELECT 1 + i * 30 AS m FROM (WITH RECURSIVE x(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM x WHERE i < 49) SELECT i FROM x)), _ty;

-- daily for days 8..90 for 100 workflows
WITH RECURSIVE days(k) AS (SELECT 8 UNION ALL SELECT k+1 FROM days WHERE k < 90)
INSERT INTO "insights_by_period"("metaId", "type", "value", "periodUnit", "periodStart")
SELECT m, t, CASE t WHEN 0 THEN (m * 3 + k) % 200 WHEN 1 THEN 10000 + (m * 977 + k * 131) % 400000 WHEN 2 THEN 5 + (m + k) % 200
                    WHEN 3 THEN (m * k) % 15 ELSE 5 + (m + k) % 210 END,
       1, strftime('%Y-%m-%d 00:00:00.000', unixepoch('2026-10-28') - 86400 * k, 'unixepoch')
FROM days, (SELECT 1 + i * 15 AS m FROM (WITH RECURSIVE x(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM x WHERE i < 99) SELECT i FROM x)), _ty;

-- weekly for weeks 14..52 for 100 workflows
WITH RECURSIVE wks(k) AS (SELECT 14 UNION ALL SELECT k+1 FROM wks WHERE k < 52)
INSERT INTO "insights_by_period"("metaId", "type", "value", "periodUnit", "periodStart")
SELECT m, t, CASE t WHEN 0 THEN (m + k) % 900 WHEN 1 THEN 90000 + (m * 31 + k * 7) % 900000 WHEN 2 THEN 50 + (m + k) % 900
                    WHEN 3 THEN (m * k) % 60 ELSE 50 + (m + k) % 950 END,
       2, strftime('%Y-%m-%d 00:00:00.000', date(unixepoch('2026-10-26') - 604800 * k, 'unixepoch'))
FROM wks, (SELECT 1 + i * 15 AS m FROM (WITH RECURSIVE x(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM x WHERE i < 99) SELECT i FROM x)), _ty;

-- uncompacted hourly backlog from 2025 (older than any compaction threshold)
WITH RECURSIVE hrs(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM hrs WHERE k < 719)
INSERT INTO "insights_by_period"("metaId", "type", "value", "periodUnit", "periodStart")
SELECT m, t, 1 + (m * 13 + k * 7 + t) % 50, 0, strftime('%Y-%m-%d %H:00:00.000', unixepoch('2025-06-01') + 3600 * k, 'unixepoch')
FROM hrs, (SELECT 7 AS m UNION ALL SELECT 307 UNION ALL SELECT 607), _ty WHERE t IN (1, 2);

-- raw events not yet compacted
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 5000*(SELECT scale FROM _cfg))
INSERT INTO "insights_raw"("metaId", "type", "value", "timestamp")
SELECT 1 + ((i * 2654435761) % 4294967296 / 16) % 1500, ((i * 2654435761) % 4294967296 / 4096) % 5,
       1 + (i * 2654435761) % 4294967296 % 3000,
       strftime('%Y-%m-%d %H:%M:%f', unixepoch('2026-10-27') + i * 17, 'unixepoch')
FROM n;

-- The compaction batch lives in a TEMPORARY table inside the app's transaction
-- (insights-by-period.repository.ts:304: CREATE TEMPORARY TABLE rows_to_compact AS <batch query>).
-- Temp tables do not survive into the per-query CLI process, so the batch is materialised here as a
-- regular table holding exactly what the raw->hour batch query (insights-raw.repository.ts:12) returns.
CREATE TABLE rows_to_compact AS
SELECT "id", "metaId", "type", "value", "timestamp" AS "periodStart" FROM "insights_raw" "insightsRaw"
ORDER BY timestamp ASC, id ASC LIMIT 500;

COMMIT;
