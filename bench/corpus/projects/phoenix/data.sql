-- Synthetic data for Arize Phoenix's SQLite database. Deterministic (no random()): values come from multiplicative
-- hashes of the row number. "Now" is 2026-10-30 00:00:00 UTC; traces cover the last 30 days, skewed towards recent.
-- Timestamps are stored the way Phoenix's UtcTimeStamp type writes them on SQLite: 'YYYY-MM-DD HH:MM:SS.ffffff' (UTC).
-- Scale 1: 24 projects; 'support-bot' holds 22k agent traces of 5 spans (110k spans) in ~3.7k sessions, 'rag-eval'
-- 5k traces of 3 spans, 'playground' 2k single LLM spans, 'default' 200 small traces, and 20 'Experiment-*' projects
-- hold one task span per experiment run. ~157k spans, ~49k span_costs with 2 cost details each, ~24k span
-- annotations, 1.3k trace annotations, 12k document annotations, 600 session annotations. Datasets: 'support-golden'
-- (1000 examples, 3 versions) with 20 experiments (19.5k runs, 2 evaluations each), plus 2 small datasets with 3
-- experiments each. _cfg.scale multiplies the traces and the golden dataset's examples.
-- The generative_models / annotation_configs / 'default' project rows are the ones Phoenix seeds at startup (same ids),
-- inserted OR IGNORE so the script also applies on top of a database Phoenix itself migrated.
BEGIN;

INSERT OR IGNORE INTO generative_models(id, name, provider, name_pattern, is_built_in, start_time, created_at, updated_at, deleted_at) VALUES
 (4, 'claude-haiku-4-5', '', 'claude-haiku-4-5', 1, NULL, '2026-09-01 00:00:00', '2026-09-01 00:00:00', NULL),
 (19, 'claude-sonnet-4-5', '', 'claude-sonnet-4-5', 1, NULL, '2026-09-01 00:00:00', '2026-09-01 00:00:00', NULL),
 (91, 'gpt-4o', '', 'gpt-4o', 1, NULL, '2026-09-01 00:00:00', '2026-09-01 00:00:00', NULL),
 (97, 'gpt-4o-mini', '', 'gpt-4o-mini', 1, NULL, '2026-09-01 00:00:00', '2026-09-01 00:00:00', NULL);
INSERT OR IGNORE INTO annotation_configs(id, name, config) VALUES
 (1, 'user_feedback', '{"name":null,"description":"User feedback labels for traces.","type":"CATEGORICAL","optimization_direction":"MAXIMIZE","values":[{"label":"positive","score":1.0},{"label":"negative","score":0.0}]}'),
 (2, 'correctness', '{"name":null,"description":"LLM judge: is the answer correct?","type":"CATEGORICAL","optimization_direction":"MAXIMIZE","values":[{"label":"correct","score":1.0},{"label":"incorrect","score":0.0}]}');
INSERT OR IGNORE INTO projects(id, name, description, gradient_start_color, gradient_end_color, created_at, updated_at, trace_retention_policy_id)
VALUES (1, 'default', 'Default project', '#5bdbff', '#1c76fc', '2026-09-01 00:00:00', '2026-09-01 00:00:00', NULL);
INSERT INTO projects(id, name, description, gradient_start_color, gradient_end_color, created_at, updated_at, trace_retention_policy_id) VALUES
 (2, 'support-bot', 'Customer support agent (prod)', '#8B5CF6', '#EC4899', '2026-09-20 10:00:00', '2026-09-20 10:00:00', NULL),
 (3, 'rag-eval', NULL, '#22C55E', '#0EA5E9', '2026-09-25 08:00:00', '2026-09-25 08:00:00', NULL),
 (4, 'playground', NULL, '#F59E0B', '#EF4444', '2026-09-26 08:00:00', '2026-09-26 08:00:00', NULL);
INSERT INTO project_annotation_configs(project_id, annotation_config_id) VALUES (2, 1), (2, 2), (3, 2);

-- Trace skeleton. p = project, nsp = spans per trace; ts = start epoch (float seconds), dur = trace duration (s).
CREATE TEMP TABLE _t(id INTEGER PRIMARY KEY, p INT, h INT, ts REAL, dur REAL, nsp INT, sess INT);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 29200*(SELECT scale FROM _cfg)),
g AS (SELECT i, (i * 2654435761) % 4294967296 AS h, i * 1.0 / (29200*(SELECT scale FROM _cfg)) AS f FROM n)
INSERT INTO _t(id, p, h, ts, dur, nsp)
SELECT i,
  CASE WHEN f < 0.00685 THEN 1 WHEN f < 0.76027 THEN 2 WHEN f < 0.93151 THEN 3 ELSE 4 END,
  h,
  unixepoch('2026-10-30') - 2592000.0 * ((h % 1000003) / 1000003.0) * ((h % 1000003) / 1000003.0) - ((h / 16) % 3600) - 30,
  CASE WHEN (h / 64) % 40 = 0 THEN 20 + (h / 128) % 90 ELSE 0.4 + ((h / 128) % 8000) / 1000.0 END,
  CASE WHEN f < 0.00685 THEN 2 WHEN f < 0.76027 THEN 5 WHEN f < 0.93151 THEN 3 ELSE 1 END
FROM g;
-- support-bot sessions: 6 traces per session, placed within a few minutes of the session's first trace.
UPDATE _t SET sess = (id - 200) / 6 + 1 WHERE p = 2;
UPDATE _t SET ts = (SELECT min(ts) FROM _t t2 WHERE t2.p = 2 AND t2.id BETWEEN ((_t.id - 200) / 6) * 6 + 200 AND _t.id) + ((_t.id - 200) % 6) * 75
WHERE p = 2;

CREATE TEMP VIEW _fmt AS SELECT 1;  -- placeholder (formatting is inlined below)
INSERT INTO project_sessions(id, session_id, project_id, start_time, end_time)
SELECT sess, 'sess-' || printf('%08x', (sess * 2246822519) % 4294967296), 2,
  strftime('%Y-%m-%d %H:%M:%S', min(ts), 'unixepoch') || printf('.%06d', CAST((min(ts) - CAST(min(ts) AS INT)) * 1000000 AS INT)),
  strftime('%Y-%m-%d %H:%M:%S', max(ts + dur), 'unixepoch') || printf('.%06d', CAST((max(ts + dur) - CAST(max(ts + dur) AS INT)) * 1000000 AS INT))
FROM _t WHERE p = 2 GROUP BY sess ORDER BY sess;

INSERT INTO traces(id, project_rowid, trace_id, start_time, end_time, project_session_rowid)
SELECT id, p, printf('%08x%08x%08x%08x', h, (id * 2246822519) % 4294967296, (id * 3266489917) % 4294967296, (id * 668265263) % 4294967296),
  strftime('%Y-%m-%d %H:%M:%S', ts, 'unixepoch') || printf('.%06d', CAST((ts - CAST(ts AS INT)) * 1000000 AS INT)),
  strftime('%Y-%m-%d %H:%M:%S', ts + dur, 'unixepoch') || printf('.%06d', CAST((ts + dur - CAST(ts + dur AS INT)) * 1000000 AS INT)),
  sess
FROM _t ORDER BY id;

-- Spans. k = position in the trace. support-bot: AGENT root, RETRIEVER, LLM (plan), TOOL, LLM (answer);
-- rag-eval: CHAIN root, RETRIEVER, LLM; playground: one LLM span; default: CHAIN + LLM.
CREATE TEMP TABLE _k(k INTEGER PRIMARY KEY);
INSERT INTO _k VALUES (0), (1), (2), (3), (4);
CREATE TEMP TABLE _s AS
SELECT t.id AS trace_rowid, t.p, t.h, t.ts, t.dur, t.nsp, t.sess, k.k,
  CASE WHEN t.p = 2 THEN CASE k.k WHEN 0 THEN 'AGENT' WHEN 1 THEN 'RETRIEVER' WHEN 3 THEN 'TOOL' ELSE 'LLM' END
       WHEN t.p = 3 THEN CASE k.k WHEN 0 THEN 'CHAIN' WHEN 1 THEN 'RETRIEVER' ELSE 'LLM' END
       WHEN t.p = 4 THEN 'LLM'
       ELSE CASE k.k WHEN 0 THEN 'CHAIN' ELSE 'LLM' END END AS kind,
  CASE WHEN t.p = 3 THEN CASE (t.h / 32) % 3 WHEN 0 THEN 'claude-haiku-4-5' ELSE 'gpt-4o-mini' END
       WHEN k.k = 4 AND (t.h / 8) % 4 = 0 THEN 'gpt-4o' WHEN k.k = 4 AND (t.h / 8) % 4 = 1 THEN 'claude-sonnet-4-5'
       ELSE 'gpt-4o-mini' END AS model,
  CASE WHEN t.p = 2 AND k.k > 0 AND (t.h / 1024 + k.k) % 61 = 0 THEN 1 ELSE 0 END AS err,
  400 + (t.h / (16 + k.k)) % 2600 AS ptok, 30 + (t.h / (64 + k.k)) % 600 AS ctok
FROM _t t JOIN _k k ON k.k < t.nsp;
CREATE INDEX _s_t ON _s(trace_rowid);

INSERT INTO spans(id, trace_rowid, span_id, parent_id, name, span_kind, start_time, end_time, attributes, events, status_code,
                  status_message, cumulative_error_count, cumulative_llm_token_count_prompt, cumulative_llm_token_count_completion,
                  llm_token_count_prompt, llm_token_count_completion)
SELECT trace_rowid * 5 + k - 4,
  trace_rowid, printf('%016x', ((trace_rowid * 5 + k) * 2654435761) % 18446744073709551),
  CASE WHEN k = 0 THEN NULL ELSE printf('%016x', ((trace_rowid * 5) * 2654435761) % 18446744073709551) END,
  CASE kind WHEN 'AGENT' THEN 'support_agent' WHEN 'CHAIN' THEN CASE p WHEN 3 THEN 'rag_pipeline' ELSE 'chain' END
            WHEN 'RETRIEVER' THEN 'retrieve_docs' WHEN 'TOOL' THEN CASE (h / 4) % 3 WHEN 0 THEN 'lookup_order' WHEN 1 THEN 'issue_refund' ELSE 'escalate' END
            ELSE 'ChatCompletion' END,
  kind,
  strftime('%Y-%m-%d %H:%M:%S', ts + k * dur / (nsp + 1.0), 'unixepoch') || printf('.%06d', CAST((ts + k * dur / (nsp + 1.0) - CAST(ts + k * dur / (nsp + 1.0) AS INT)) * 1000000 AS INT)),
  strftime('%Y-%m-%d %H:%M:%S', ts + CASE WHEN k = 0 THEN dur ELSE (k + 1) * dur / (nsp + 1.0) END, 'unixepoch') ||
    printf('.%06d', CAST((ts + CASE WHEN k = 0 THEN dur ELSE (k + 1) * dur / (nsp + 1.0) END - CAST(ts + CASE WHEN k = 0 THEN dur ELSE (k + 1) * dur / (nsp + 1.0) END AS INT)) * 1000000 AS INT)),
  CASE kind
    WHEN 'LLM' THEN json_object('llm', json_object('model_name', model, 'provider', CASE WHEN model LIKE 'claude%' THEN 'anthropic' ELSE 'openai' END,
                                  'token_count', json_object('prompt', ptok, 'completion', ctok, 'total', ptok + ctok),
                                  'invocation_parameters', '{"temperature": 0.2}'),
                     'input', json_object('value', 'You are a helpful support agent. Customer: where is order #' || (h % 100000) || '?', 'mime_type', 'text/plain'),
                     'output', json_object('value', 'Order #' || (h % 100000) || ' ships tomorrow.', 'mime_type', 'text/plain'),
                     'openinference', json_object('span', json_object('kind', 'LLM')))
    WHEN 'RETRIEVER' THEN json_object('input', json_object('value', 'refund policy order ' || (h % 100000)),
                     'retrieval', json_object('documents', json_array(
                        json_object('document', json_object('id', 'kb-' || (h % 900), 'content', 'Refunds are issued within 5 business days.', 'score', 0.5 + (h % 50) / 100.0)),
                        json_object('document', json_object('id', 'kb-' || (h % 700), 'content', 'Orders ship in 2 days.', 'score', 0.3 + (h % 40) / 100.0)),
                        json_object('document', json_object('id', 'kb-' || (h % 500), 'content', 'Contact support for damaged items.', 'score', 0.1 + (h % 30) / 100.0)))),
                     'openinference', json_object('span', json_object('kind', 'RETRIEVER')))
    WHEN 'TOOL' THEN json_object('tool', json_object('name', 'lookup_order'), 'input', json_object('value', '{"order_id": ' || (h % 100000) || '}', 'mime_type', 'application/json'),
                     'output', json_object('value', '{"status": "shipped"}', 'mime_type', 'application/json'),
                     'openinference', json_object('span', json_object('kind', 'TOOL')))
    ELSE json_object('input', json_object('value', json_object('question', 'Where is my order #' || (h % 100000) || '?'), 'mime_type', 'application/json'),
                     'output', json_object('value', 'Your order #' || (h % 100000) || ' ships tomorrow.'),
                     'session', CASE WHEN p = 2 THEN json_object('id', 'sess-' || printf('%08x', (sess * 2246822519) % 4294967296)) END,
                     'user', CASE WHEN p = 2 THEN json_object('id', 'customer-' || ((h / 4) % 1500)) END,
                     'metadata', json_object('env', CASE WHEN (h / 2048) % 5 = 0 THEN 'staging' ELSE 'prod' END, 'app_version', '1.' || ((h / 4096) % 9)),
                     'openinference', json_object('span', json_object('kind', kind)))
  END,
  CASE WHEN err = 1 THEN '[{"name":"exception","timestamp":"' || strftime('%Y-%m-%dT%H:%M:%S', ts, 'unixepoch') || '+00:00","attributes":{"exception.type":"RateLimitError","exception.message":"429 Too Many Requests"}}]' ELSE '[]' END,
  CASE WHEN err = 1 THEN 'ERROR' WHEN kind = 'LLM' THEN 'OK' ELSE 'UNSET' END,
  CASE WHEN err = 1 THEN 'RateLimitError: 429 Too Many Requests' ELSE '' END,
  CASE WHEN k = 0 THEN (SELECT sum(err) FROM _s c WHERE c.trace_rowid = _s.trace_rowid) ELSE err END,
  CASE WHEN k = 0 THEN (SELECT coalesce(sum(ptok), 0) FROM _s c WHERE c.trace_rowid = _s.trace_rowid AND c.kind = 'LLM') WHEN kind = 'LLM' THEN ptok ELSE 0 END,
  CASE WHEN k = 0 THEN (SELECT coalesce(sum(ctok), 0) FROM _s c WHERE c.trace_rowid = _s.trace_rowid AND c.kind = 'LLM') WHEN kind = 'LLM' THEN ctok ELSE 0 END,
  CASE WHEN kind = 'LLM' THEN ptok END,
  CASE WHEN kind = 'LLM' THEN ctok END
FROM _s ORDER BY trace_rowid, k;

-- Span costs for LLM spans (prices per token as Phoenix's built-in table: gpt-4o-mini 1.5e-7 / 6e-7 etc.).
CREATE TEMP TABLE _price(model TEXT PRIMARY KEY, mid INT, pin REAL, pout REAL);
INSERT INTO _price VALUES ('gpt-4o-mini', 97, 1.5e-07, 6e-07), ('gpt-4o', 91, 2.5e-06, 1e-05),
  ('claude-sonnet-4-5', 19, 3e-06, 1.5e-05), ('claude-haiku-4-5', 4, 1e-06, 5e-06);
INSERT INTO span_costs(id, span_rowid, trace_rowid, model_id, span_start_time, total_cost, total_tokens, prompt_cost, prompt_tokens,
                       completion_cost, completion_tokens)
SELECT row_number() OVER (ORDER BY s.trace_rowid, s.k), s.trace_rowid * 5 + s.k - 4, s.trace_rowid, pr.mid,
  strftime('%Y-%m-%d %H:%M:%S', s.ts + s.k * s.dur / (s.nsp + 1.0), 'unixepoch') || printf('.%06d', CAST((s.ts + s.k * s.dur / (s.nsp + 1.0) - CAST(s.ts + s.k * s.dur / (s.nsp + 1.0) AS INT)) * 1000000 AS INT)),
  s.ptok * pr.pin + s.ctok * pr.pout, s.ptok + s.ctok, s.ptok * pr.pin, s.ptok, s.ctok * pr.pout, s.ctok
FROM _s s JOIN _price pr ON pr.model = s.model WHERE s.kind = 'LLM' ORDER BY s.trace_rowid, s.k;
INSERT INTO span_cost_details(span_cost_id, token_type, is_prompt, cost, tokens, cost_per_token)
SELECT c.id, 'input', 1, c.prompt_cost, c.prompt_tokens, c.prompt_cost / c.prompt_tokens FROM span_costs c
UNION ALL
SELECT c.id, 'output', 0, c.completion_cost, c.completion_tokens, c.completion_cost / c.completion_tokens FROM span_costs c
ORDER BY 1, 2;

-- Annotations. LLM-judge evals on 35 % of support-bot answer spans (correctness + hallucination) and on 40 % of
-- rag-eval LLM spans; human user_feedback on 6 % of support-bot traces; document relevance on rag-eval retrievals.
INSERT INTO span_annotations(span_rowid, name, label, score, explanation, metadata, annotator_kind, created_at, updated_at, user_id, identifier, source)
SELECT s.trace_rowid * 5 + s.k - 4, a.name,
  CASE a.name WHEN 'correctness' THEN CASE WHEN (s.h / 32) % 100 < 78 THEN 'correct' ELSE 'incorrect' END
              ELSE CASE WHEN (s.h / 64) % 100 < 9 THEN 'hallucinated' ELSE 'factual' END END,
  CASE a.name WHEN 'correctness' THEN CASE WHEN (s.h / 32) % 100 < 78 THEN 1.0 ELSE 0.0 END
              ELSE CASE WHEN (s.h / 64) % 100 < 9 THEN 1.0 ELSE 0.0 END END,
  CASE WHEN a.name = 'correctness' THEN 'The answer matches the order status returned by the tool.' END,
  '{}', 'LLM',
  strftime('%Y-%m-%d %H:%M:%S', s.ts + 600, 'unixepoch'), strftime('%Y-%m-%d %H:%M:%S', s.ts + 600, 'unixepoch'), NULL, '', 'API'
FROM _s s JOIN (SELECT 'correctness' AS name UNION ALL SELECT 'hallucination') a
WHERE s.kind = 'LLM' AND ((s.p = 2 AND s.k = 4 AND (s.h / 512) % 100 < 35) OR (s.p = 3 AND (s.h / 512) % 100 < 40))
ORDER BY s.trace_rowid, a.name;
INSERT INTO trace_annotations(trace_rowid, name, label, score, explanation, metadata, annotator_kind, created_at, updated_at, user_id, identifier, source)
SELECT id, 'user_feedback', CASE WHEN (h / 8) % 4 = 0 THEN 'negative' ELSE 'positive' END,
  CASE WHEN (h / 8) % 4 = 0 THEN 0.0 ELSE 1.0 END, NULL, '{}', 'HUMAN',
  strftime('%Y-%m-%d %H:%M:%S', ts + 120, 'unixepoch'), strftime('%Y-%m-%d %H:%M:%S', ts + 120, 'unixepoch'), NULL, '', 'APP'
FROM _t WHERE p = 2 AND (h / 4096) % 100 < 6 ORDER BY id;
INSERT INTO document_annotations(span_rowid, document_position, name, label, score, explanation, metadata, annotator_kind, created_at, updated_at, user_id, identifier, source)
SELECT s.trace_rowid * 5 + s.k - 4, d.pos, 'relevance', CASE WHEN (s.h / (8 + d.pos)) % 3 = 0 THEN 'unrelated' ELSE 'relevant' END,
  CASE WHEN (s.h / (8 + d.pos)) % 3 = 0 THEN 0.0 ELSE 1.0 END, NULL, '{}', 'LLM',
  strftime('%Y-%m-%d %H:%M:%S', s.ts + 900, 'unixepoch'), strftime('%Y-%m-%d %H:%M:%S', s.ts + 900, 'unixepoch'), NULL, '', 'API'
FROM _s s JOIN (SELECT 0 AS pos UNION ALL SELECT 1 UNION ALL SELECT 2) d
WHERE s.kind = 'RETRIEVER' AND s.p = 3 AND (s.h / 256) % 100 < 80 ORDER BY s.trace_rowid, d.pos;
INSERT INTO project_session_annotations(project_session_id, name, label, score, explanation, metadata, annotator_kind, user_id, identifier, source, created_at, updated_at)
SELECT id, 'resolved', CASE WHEN id % 5 = 0 THEN 'no' ELSE 'yes' END, CASE WHEN id % 5 = 0 THEN 0.0 ELSE 1.0 END, NULL, '{}', 'LLM', NULL, '', 'API',
  end_time, end_time
FROM project_sessions WHERE (id * 2654435761) % 100 < 16 ORDER BY id;

-- Datasets, versions, examples and revisions. Golden set: v1 creates examples 1..900, v2 patches 1..150 and adds
-- 901..1000, v3 deletes 951..1000. Two small datasets of 100 examples, one version each.
INSERT INTO datasets(id, name, description, metadata, created_at, updated_at, user_id) VALUES
 (1, 'support-golden', 'Curated support conversations', '{"owner": "qa"}', '2026-09-28 09:00:00', '2026-10-20 09:00:00', NULL),
 (2, 'refund-edge-cases', NULL, '{}', '2026-10-02 09:00:00', '2026-10-02 09:00:00', NULL),
 (3, 'rag-smoke', NULL, '{}', '2026-10-05 09:00:00', '2026-10-05 09:00:00', NULL);
INSERT INTO dataset_versions(id, dataset_id, description, metadata, created_at, user_id) VALUES
 (1, 1, 'initial import', '{}', '2026-09-28 09:00:00', NULL), (2, 1, 'fix labels, add 100', '{}', '2026-10-10 09:00:00', NULL),
 (3, 1, 'drop duplicates', '{}', '2026-10-20 09:00:00', NULL), (4, 2, NULL, '{}', '2026-10-02 09:00:00', NULL),
 (5, 3, NULL, '{}', '2026-10-05 09:00:00', NULL);
CREATE TEMP TABLE _ex(id INTEGER PRIMARY KEY, ds INT, n INT, h INT);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 1000*(SELECT scale FROM _cfg) + 200)
INSERT INTO _ex SELECT i, CASE WHEN i <= 1000*(SELECT scale FROM _cfg) THEN 1 WHEN i <= 1000*(SELECT scale FROM _cfg) + 100 THEN 2 ELSE 3 END,
  CASE WHEN i <= 1000*(SELECT scale FROM _cfg) THEN i ELSE (i - 1000*(SELECT scale FROM _cfg) - 1) % 100 + 1 END, (i * 2654435761) % 4294967296 FROM n;
INSERT INTO dataset_examples(id, dataset_id, span_rowid, created_at, external_id)
SELECT id, ds, CASE WHEN ds = 1 AND n % 4 = 0 THEN (SELECT max(id) FROM spans) - n * 7 END,
  CASE WHEN ds = 1 AND n > 900*(SELECT scale FROM _cfg) THEN '2026-10-10 09:00:00' WHEN ds = 1 THEN '2026-09-28 09:00:00'
       WHEN ds = 2 THEN '2026-10-02 09:00:00' ELSE '2026-10-05 09:00:00' END, NULL
FROM _ex ORDER BY id;
INSERT INTO dataset_example_revisions(dataset_example_id, dataset_version_id, input, output, metadata, revision_kind, created_at, content_hash)
SELECT id, v.ver,
  json_object('messages', json_array(json_object('role', 'user', 'content', 'Where is my order #' || (h % 100000) || '? It was due ' || (1 + h % 9) || ' days ago.'))),
  json_object('answer', CASE WHEN v.ver = 2 THEN 'Corrected: order #' || (h % 100000) || ' ships tomorrow.' ELSE 'Order #' || (h % 100000) || ' ships tomorrow.' END),
  json_object('category', CASE h % 4 WHEN 0 THEN 'refund' WHEN 1 THEN 'shipping' WHEN 2 THEN 'billing' ELSE 'account' END),
  v.kind,
  CASE v.ver WHEN 1 THEN '2026-09-28 09:00:00' WHEN 2 THEN '2026-10-10 09:00:00' WHEN 3 THEN '2026-10-20 09:00:00'
             WHEN 4 THEN '2026-10-02 09:00:00' ELSE '2026-10-05 09:00:00' END,
  unhex(printf('%08x%08x', h, (id * 40503) % 4294967296))
FROM _ex e JOIN (SELECT 1 AS ver, 'CREATE' AS kind UNION ALL SELECT 2, 'PATCH' UNION ALL SELECT 2, 'CREATE'
                 UNION ALL SELECT 3, 'DELETE' UNION ALL SELECT 4, 'CREATE' UNION ALL SELECT 5, 'CREATE') v
  ON (e.ds = 1 AND v.ver = 1 AND v.kind = 'CREATE' AND e.n <= 900*(SELECT scale FROM _cfg))
  OR (e.ds = 1 AND v.ver = 2 AND v.kind = 'PATCH' AND e.n <= 150*(SELECT scale FROM _cfg))
  OR (e.ds = 1 AND v.ver = 2 AND v.kind = 'CREATE' AND e.n > 900*(SELECT scale FROM _cfg))
  OR (e.ds = 1 AND v.ver = 3 AND v.kind = 'DELETE' AND e.n > 950*(SELECT scale FROM _cfg))
  OR (e.ds = 2 AND v.ver = 4) OR (e.ds = 3 AND v.ver = 5)
ORDER BY e.id, v.ver;

-- Experiments: 20 on the golden set (5 on v1, 15 on v2, the newest last), 3 on each small dataset. Each has its
-- own 'Experiment-<hex>' project holding one task trace per run.
CREATE TEMP TABLE _x(id INTEGER PRIMARY KEY, ds INT, ver INT, proj INT, created REAL);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 26)
INSERT INTO _x SELECT i, CASE WHEN i <= 20 THEN 1 WHEN i <= 23 THEN 2 ELSE 3 END,
  CASE WHEN i <= 5 THEN 1 WHEN i <= 20 THEN 2 WHEN i <= 23 THEN 4 ELSE 5 END, 4 + i,
  unixepoch('2026-09-29') + i * 120000.0 FROM n;
INSERT INTO projects(id, name, description, gradient_start_color, gradient_end_color, created_at, updated_at, trace_retention_policy_id)
SELECT proj, 'Experiment-' || printf('%08x%08x%08x', (id * 2654435761) % 4294967296, (id * 2246822519) % 4294967296, (id * 3266489917) % 4294967296),
  NULL, '#9CA3AF', '#4B5563', strftime('%Y-%m-%d %H:%M:%S', created, 'unixepoch'), strftime('%Y-%m-%d %H:%M:%S', created, 'unixepoch'), NULL
FROM _x;
INSERT INTO experiments(id, dataset_id, dataset_version_id, name, description, repetitions, metadata, project_name, created_at, updated_at, user_id, is_ephemeral)
SELECT x.id, x.ds, x.ver,
  CASE WHEN x.ds = 1 THEN 'agent-' || (SELECT value FROM json_each('["gpt-4o-mini","gpt-4o","claude-sonnet-4-5","claude-haiku-4-5"]') WHERE key = x.id % 4) || '-run' || x.id
       ELSE 'baseline-' || x.id END,
  NULL, 1, json_object('prompt_version', 'v' || (x.id % 7), 'temperature', 0.1 * (x.id % 5)), p.name,
  strftime('%Y-%m-%d %H:%M:%S', x.created, 'unixepoch'), strftime('%Y-%m-%d %H:%M:%S', x.created + 3600, 'unixepoch'), NULL, 0
FROM _x x JOIN projects p ON p.id = x.proj;
-- Examples in each experiment's version snapshot, with the revision that was current at that version.
INSERT INTO experiments_dataset_examples(experiment_id, dataset_example_id, dataset_example_revision_id)
SELECT x.id, r.dataset_example_id, max(r.id)
FROM _x x JOIN dataset_example_revisions r ON r.dataset_version_id <= x.ver
  AND r.dataset_example_id IN (SELECT id FROM dataset_examples WHERE dataset_id = x.ds)
GROUP BY x.id, r.dataset_example_id
HAVING max(CASE WHEN r.revision_kind = 'DELETE' THEN r.id END) IS NULL OR max(CASE WHEN r.revision_kind = 'DELETE' THEN r.id END) < max(r.id)
ORDER BY 1, 2;
CREATE TEMP TABLE _run AS
SELECT row_number() OVER (ORDER BY ede.experiment_id, ede.dataset_example_id) AS rid, ede.experiment_id AS x, ede.dataset_example_id AS ex,
  ((ede.experiment_id * 1000003 + ede.dataset_example_id) * 2654435761) % 4294967296 AS h, xx.created + ede.dataset_example_id * 1.7 AS ts, xx.proj
FROM experiments_dataset_examples ede JOIN _x xx ON xx.id = ede.experiment_id;
-- Task traces in the experiment projects (ids after the regular traces), one CHAIN span each.
INSERT INTO traces(id, project_rowid, trace_id, start_time, end_time, project_session_rowid)
SELECT 1000000 + rid, proj, printf('%08x%08x%08x%08x', h, ((x * 7919 + ex) * 2246822519) % 4294967296, ((x * 7919 + ex) * 3266489917) % 4294967296, ((x * 7919 + ex) * 374761393) % 4294967296),
  strftime('%Y-%m-%d %H:%M:%S', ts, 'unixepoch') || printf('.%06d', CAST((ts - CAST(ts AS INT)) * 1000000 AS INT)),
  strftime('%Y-%m-%d %H:%M:%S', ts + 0.8 + (h % 4000) / 1000.0, 'unixepoch') || printf('.%06d', CAST((ts + 0.8 + (h % 4000) / 1000.0 - CAST(ts + 0.8 + (h % 4000) / 1000.0 AS INT)) * 1000000 AS INT)),
  NULL
FROM _run ORDER BY rid;
INSERT INTO spans(id, trace_rowid, span_id, parent_id, name, span_kind, start_time, end_time, attributes, events, status_code,
                  status_message, cumulative_error_count, cumulative_llm_token_count_prompt, cumulative_llm_token_count_completion,
                  llm_token_count_prompt, llm_token_count_completion)
SELECT 5000000 + r.rid, t.id, printf('%016x', ((5000000 + r.rid) * 2654435761) % 18446744073709551), NULL, 'Task: run_agent', 'CHAIN',
  t.start_time, t.end_time,
  json_object('input', json_object('value', '{"messages": "..."}', 'mime_type', 'application/json'),
              'output', json_object('value', 'Order ships tomorrow.'), 'openinference', json_object('span', json_object('kind', 'CHAIN'))),
  '[]', CASE WHEN (r.h / 64) % 33 = 0 THEN 'ERROR' ELSE 'OK' END, '', CASE WHEN (r.h / 64) % 33 = 0 THEN 1 ELSE 0 END, 0, 0, NULL, NULL
FROM _run r JOIN traces t ON t.id = 1000000 + r.rid ORDER BY r.rid;
INSERT INTO experiment_runs(id, experiment_id, dataset_example_id, repetition_number, trace_id, output, start_time, end_time,
                            prompt_token_count, completion_token_count, error)
SELECT r.rid, r.x, r.ex, 1, t.trace_id,
  CASE WHEN (r.h / 64) % 33 = 0 THEN '{"task_output": null}' ELSE json_object('task_output', json_object('answer', 'Order #' || (r.h % 100000) || ' ships tomorrow.')) END,
  t.start_time, t.end_time, 600 + r.h % 1500, 40 + (r.h / 16) % 300,
  CASE WHEN (r.h / 64) % 33 = 0 THEN 'RateLimitError: 429 Too Many Requests' END
FROM _run r JOIN traces t ON t.id = 1000000 + r.rid ORDER BY r.rid;
INSERT INTO experiment_run_annotations(experiment_run_id, name, annotator_kind, label, score, explanation, trace_id, error, metadata, start_time, end_time)
SELECT r.rid, a.name, a.kind,
  CASE WHEN a.name = 'qa_correctness' THEN CASE WHEN (r.h / (256 + r.x)) % 100 < 60 + r.x THEN 'correct' ELSE 'incorrect' END END,
  CASE WHEN a.name = 'exact_match' THEN CASE WHEN (r.h / (128 + r.x)) % 100 < 30 + r.x THEN 1.0 ELSE 0.0 END
       ELSE CASE WHEN (r.h / (256 + r.x)) % 100 < 60 + r.x THEN 1.0 ELSE 0.0 END END,
  CASE WHEN a.name = 'qa_correctness' THEN 'Compared the answer with the reference.' END,
  NULL, NULL, '{}',
  strftime('%Y-%m-%d %H:%M:%S', r.ts + 10, 'unixepoch') || '.000000', strftime('%Y-%m-%d %H:%M:%S', r.ts + 11, 'unixepoch') || '.500000'
FROM _run r JOIN (SELECT 'exact_match' AS name, 'CODE' AS kind UNION ALL SELECT 'qa_correctness', 'LLM') a
ORDER BY r.rid, a.name;

DROP VIEW _fmt;
COMMIT;
