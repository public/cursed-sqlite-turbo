-- Synthetic data for claude-mem. Deterministic (no random()): values come from multiplicative hashes of the row number,
-- each column from different bits. Scale 1: 2k sessions over 20 projects (skewed; three worktree projects merged into
-- their parent), 40k observations (20 per session), 4k summaries, 10k prompts, 20k tool uses, ~100k observation_files.
-- Epochs are milliseconds, as the app stores Date.now().
BEGIN;

CREATE TEMP TABLE _proj(k INTEGER PRIMARY KEY, name TEXT, merged TEXT);
INSERT INTO _proj VALUES
 (0,'claude-mem',NULL),(1,'webapp',NULL),(2,'infra',NULL),(3,'api-gateway',NULL),(4,'mobile-app',NULL),
 (5,'docs-site',NULL),(6,'data-pipeline',NULL),(7,'billing',NULL),(8,'search-svc',NULL),(9,'auth-svc',NULL),
 (10,'cli-tools',NULL),(11,'design-system',NULL),(12,'ml-experiments',NULL),(13,'dotfiles',NULL),(14,'blog',NULL),
 (15,'game-jam',NULL),(16,'Claude-Mem',NULL),(17,'claude-mem-wt-fts','claude-mem'),(18,'claude-mem-wt-hooks','claude-mem'),
 (19,'webapp-wt-auth','webapp');

CREATE TEMP TABLE _w(kind TEXT, k INTEGER, w TEXT);
INSERT INTO _w VALUES
 ('verb',0,'Fixed'),('verb',1,'Added'),('verb',2,'Refactored'),('verb',3,'Discovered'),('verb',4,'Changed'),('verb',5,'Documented'),
 ('noun',0,'retry limit'),('noun',1,'auth token refresh'),('noun',2,'FTS5 index rebuild'),('noun',3,'worker port binding'),
 ('noun',4,'session timeout'),('noun',5,'context injection'),('noun',6,'pending queue drain'),('noun',7,'schema migration'),
 ('noun',8,'hook timeout'),('noun',9,'sqlite busy lock'),
 ('comp',0,'SessionStore'),('comp',1,'worker-service'),('comp',2,'SessionSearch'),('comp',3,'ObservationCompiler'),
 ('comp',4,'hooks'),('comp',5,'cli'),('comp',6,'viewer'),('comp',7,'transcript-watch'),('comp',8,'sync'),
 ('comp',9,'dedup-store'),('comp',10,'tool-uses'),('comp',11,'paths'),
 ('type',0,'discovery'),('type',1,'bugfix'),('type',2,'feature'),('type',3,'refactor'),('type',4,'change'),('type',5,'decision'),
 ('concept',0,'how-it-works'),('concept',1,'gotcha'),('concept',2,'pattern'),('concept',3,'problem-solution'),
 ('concept',4,'trade-off'),('concept',5,'why-it-exists'),('concept',6,'what-changed'),
 ('tool',0,'Read'),('tool',1,'Edit'),('tool',2,'Bash'),('tool',3,'Grep'),('tool',4,'Read'),('tool',5,'Write'),('tool',6,'Glob'),
 ('tool',7,'Read'),('tool',8,'Bash'),('tool',9,'WebFetch'),('tool',10,'Task'),('tool',11,'Edit');
CREATE INDEX temp._w_i ON _w(kind, k);

-- sessions: 1 per hour from 2026-01-01; every 50th belongs to the observer's own project
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO sdk_sessions(id, content_session_id, memory_session_id, project, platform_source, user_prompt, started_at,
  started_at_epoch, completed_at, completed_at_epoch, status, worker_port, prompt_counter, custom_title, observed_model, cwd)
SELECT i, printf('cs-%08x-%04d', h, i), 'mem-' || i,
       CASE WHEN i % 50 = 0 THEN 'observer-sessions'
            ELSE (SELECT name FROM _proj WHERE k = (((h / 8) % 20) * ((h / 256) % 20)) / 20) END,
       CASE (h / 65536) % 10 WHEN 8 THEN 'codex' WHEN 9 THEN 'cursor' ELSE 'claude' END,
       'Help me with ' || (SELECT w FROM _w WHERE kind='noun' AND k = (h / 4096) % 10),
       strftime('%Y-%m-%dT%H:%M:%fZ', (1767225600000 + i * 3600000) / 1000.0, 'unixepoch'),
       1767225600000 + i * 3600000,
       CASE WHEN i > 2000*(SELECT scale FROM _cfg) - 20 THEN NULL
            ELSE strftime('%Y-%m-%dT%H:%M:%fZ', (1767225600000 + i * 3600000 + 2400000) / 1000.0, 'unixepoch') END,
       CASE WHEN i > 2000*(SELECT scale FROM _cfg) - 20 THEN NULL ELSE 1767225600000 + i * 3600000 + 2400000 END,
       CASE WHEN i > 2000*(SELECT scale FROM _cfg) - 20 THEN 'active' WHEN (h / 1048576) % 40 = 0 THEN 'failed' ELSE 'completed' END,
       37777, 5,
       CASE WHEN (h / 32) % 7 = 0 THEN 'Session ' || i ELSE NULL END,
       CASE (h / 2048) % 3 WHEN 0 THEN 'claude-sonnet-4-5' WHEN 1 THEN 'claude-haiku-4-5' ELSE 'claude-opus-4-1' END,
       '/Users/dev/code/project-' || ((h / 8) % 20)
FROM m;

-- observations: 20 per session, one a minute after the session starts
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h, (i - 1) / 20 + 1 AS sid FROM n),
x AS (
  SELECT m.i, m.h, s.memory_session_id, s.project, s.started_at_epoch + ((m.i - 1) % 20) * 60000 AS ep,
         (SELECT w FROM _w WHERE kind='verb' AND k = (m.h / 16) % 6) AS verb,
         (SELECT w FROM _w WHERE kind='noun' AND k = (m.h / 128) % 10) AS noun,
         (SELECT w FROM _w WHERE kind='comp' AND k = (m.h / 2048) % 12) AS comp,
         (SELECT w FROM _w WHERE kind='comp' AND k = (m.h / 65536) % 12) AS comp2,
         (SELECT w FROM _w WHERE kind='type' AND k = (m.h / 8) % 6) AS typ,
         (SELECT w FROM _w WHERE kind='concept' AND k = (m.h / 524288) % 7) AS c1,
         (SELECT w FROM _w WHERE kind='concept' AND k = (m.h / 4194304) % 7) AS c2
  FROM m JOIN sdk_sessions s ON s.id = m.sid
)
INSERT INTO observations(id, memory_session_id, project, text, type, title, subtitle, facts, narrative, concepts,
  files_read, files_modified, prompt_number, discovery_tokens, created_at, created_at_epoch, content_hash,
  generated_by_model, agent_type, agent_id, occurrence_count, title_norm_key, reinforcement_dates, last_reinforced,
  merged_into_project)
SELECT i, memory_session_id, project, NULL, typ,
       verb || ' ' || noun || ' in ' || comp,
       'The ' || noun || ' path in ' || comp || ' now talks to ' || comp2,
       json_array(comp || ' owns the ' || noun, 'Retries back off after ' || (h % 5 + 1) || ' attempts',
                  CASE WHEN (h / 32) % 3 = 0 THEN 'Bun SQLite surfaces SQLITE_BUSY as an exception' ELSE 'Port ' || (37000 + h % 1000) || ' is the worker default' END),
       'While investigating the ' || noun || ', found that ' || comp || ' calls ' || comp2 ||
         ' before the transaction commits. ' ||
         CASE (h / 1024) % 4 WHEN 0 THEN 'The fix moves the write behind the lock and adds a regression test.'
                             WHEN 1 THEN 'This explains the intermittent timeout seen during SessionStart.'
                             WHEN 2 THEN 'Documented the trade-off between latency and durability.'
                             ELSE 'The migration now runs idempotently on every worker start.' END,
       CASE WHEN (h / 33554432) % 23 = 0 THEN c1 ELSE json_array(c1, c2) END,
       json_array('src/services/' || comp || '.ts', 'src/services/' || comp2 || '.ts'),
       CASE WHEN (h / 64) % 3 = 0 THEN json_array('/Users/dev/code/project/src/services/' || comp || '.ts') ELSE '[]' END,
       (i - 1) % 20 / 4 + 1, 200 + h % 3000,
       strftime('%Y-%m-%dT%H:%M:%fZ', ep / 1000.0, 'unixepoch'), ep,
       printf('%016x', (h * 40503) % 281474976710656),
       'claude-haiku-4-5',
       CASE WHEN (h / 512) % 10 = 0 THEN 'general-purpose' ELSE NULL END,
       CASE WHEN (h / 512) % 10 = 0 THEN 'agent-' || (h % 997) WHEN (h / 512) % 20 = 1 THEN 'seat-' || (h % 13) ELSE NULL END,
       1 + (CASE WHEN h % 17 = 0 THEN h % 4 ELSE 0 END),
       lower(project || '|' || verb || ' ' || noun || ' in ' || comp),
       json_array(date(ep / 1000, 'unixepoch')), date(ep / 1000, 'unixepoch'),
       (SELECT merged FROM _proj WHERE name = x.project)
FROM x;

-- two summaries per session
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 4000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2246822519) % 4294967296 AS h, (i - 1) / 2 + 1 AS sid FROM n),
x AS (
  SELECT m.i, m.h, s.memory_session_id, s.project, s.started_at_epoch + 600000 + ((m.i - 1) % 2) * 1200000 AS ep,
         (SELECT w FROM _w WHERE kind='noun' AND k = (m.h / 128) % 10) AS noun,
         (SELECT w FROM _w WHERE kind='comp' AND k = (m.h / 2048) % 12) AS comp
  FROM m JOIN sdk_sessions s ON s.id = m.sid
)
INSERT INTO session_summaries(id, memory_session_id, project, request, investigated, learned, completed, next_steps,
  files_read, files_edited, notes, prompt_number, discovery_tokens, created_at, created_at_epoch, merged_into_project)
SELECT i, memory_session_id, project,
       'Investigate the ' || noun || ' in ' || comp,
       'Read ' || comp || '.ts and the related tests; traced the ' || noun || ' through the worker.',
       'The ' || noun || ' depends on the shared connection in ' || comp || '.',
       CASE WHEN h % 3 = 0 THEN 'Fixed the ' || noun || ' and added a test.' ELSE 'Partial fix for the ' || noun || '.' END,
       'Verify the ' || noun || ' on Windows; follow up on ' || comp || ' logging.',
       json_array('src/services/' || comp || '.ts', 'tests/' || comp || '.test.ts'),
       json_array('src/services/' || comp || '.ts'),
       CASE WHEN (h / 8) % 4 = 0 THEN NULL ELSE 'Watch for regressions in ' || comp END,
       (i - 1) % 2 * 3 + 2, 1500 + h % 5000,
       strftime('%Y-%m-%dT%H:%M:%fZ', ep / 1000.0, 'unixepoch'), ep,
       (SELECT merged FROM _proj WHERE name = x.project)
FROM x;

-- five prompts per session
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 10000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 3266489917) % 4294967296 AS h, (i - 1) / 5 + 1 AS sid FROM n)
INSERT INTO user_prompts(id, session_db_id, content_session_id, prompt_number, prompt_text, created_at, created_at_epoch)
SELECT m.i, s.id, s.content_session_id, (m.i - 1) % 5 + 1,
       CASE (m.h / 16) % 4 WHEN 0 THEN 'why does the ' WHEN 1 THEN 'please fix the ' WHEN 2 THEN 'can you explain the ' ELSE 'add a test for the ' END
         || (SELECT w FROM _w WHERE kind='noun' AND k = (m.h / 256) % 10) || ' in '
         || (SELECT w FROM _w WHERE kind='comp' AND k = (m.h / 4096) % 12),
       strftime('%Y-%m-%dT%H:%M:%fZ', (s.started_at_epoch + ((m.i - 1) % 5) * 300000) / 1000.0, 'unixepoch'),
       s.started_at_epoch + ((m.i - 1) % 5) * 300000
FROM m JOIN sdk_sessions s ON s.id = m.sid;

-- ten tool uses per session
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h, (i - 1) / 10 + 1 AS sid FROM n)
INSERT INTO tool_uses(id, tool_use_id, content_session_id, memory_session_id, session_db_id, project, platform_source,
  tool_name, tool_input, tool_response, cwd, prompt_number, agent_type, agent_id, observation_id, content_hash,
  created_at, created_at_epoch)
SELECT m.i, printf('toolu_%012x', m.h * 7 % 281474976710656), s.content_session_id, s.memory_session_id, s.id, s.project,
       s.platform_source, t.w,
       json_object('file_path', '/Users/dev/code/project/src/services/' || (SELECT w FROM _w WHERE kind='comp' AND k = (m.h / 4096) % 12) || '.ts'),
       CASE WHEN (m.h / 64) % 9 = 0 THEN NULL ELSE '{"ok":true,"bytes":' || (m.h % 40000) || '}' END,
       s.cwd, (m.i - 1) % 10 / 2 + 1,
       CASE WHEN (m.h / 1024) % 12 = 0 THEN 'general-purpose' ELSE NULL END,
       CASE WHEN (m.h / 1024) % 12 = 0 THEN 'agent-' || (m.h % 997) ELSE NULL END,
       CASE WHEN (m.h / 32) % 3 = 0 THEN NULL ELSE (m.sid - 1) * 20 + (m.i - 1) % 10 + 1 END,
       printf('%016x', m.h * 31 % 281474976710656),
       strftime('%Y-%m-%dT%H:%M:%fZ', (s.started_at_epoch + ((m.i - 1) % 10) * 120000) / 1000.0, 'unixepoch'),
       s.started_at_epoch + ((m.i - 1) % 10) * 120000
FROM m JOIN sdk_sessions s ON s.id = m.sid
JOIN _w t ON t.kind = 'tool' AND t.k = (m.h / 16) % 12;

-- v68 path index, expanded the way ensureObservationFileIndex does it
INSERT OR IGNORE INTO observation_files(observation_id, path)
SELECT o.id, je.value FROM observations o, json_each(o.files_read) je
 WHERE json_valid(o.files_read) AND json_type(o.files_read) = 'array' AND je.type = 'text'
UNION
SELECT o.id, je.value FROM observations o, json_each(o.files_modified) je
 WHERE json_valid(o.files_modified) AND json_type(o.files_modified) = 'array' AND je.type = 'text';

-- dedup IDF model: title tokens per project
INSERT INTO token_df(project, token, df)
SELECT p.name, lower(w.w), 1 + (p.k * 7 + w.k * 13) % 400
FROM _proj p, _w w WHERE w.kind IN ('verb', 'comp');

INSERT INTO schema_versions(id, version, applied_at) VALUES (1, 68, '2026-10-01T00:00:00.000Z');

COMMIT;
