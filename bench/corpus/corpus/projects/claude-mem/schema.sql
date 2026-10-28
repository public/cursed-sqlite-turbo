-- thedotmack/claude-mem @ 8e91e3abb0f4536d374095193c18d72fa9d92b05 (Apache-2.0)
-- Final-state DDL reconstructed from the in-code migration chain: src/services/sqlite/SessionStore.ts
-- (initializeSchema + the observations_new/session_summaries_new/sdk_sessions_new/user_prompts_new rebuilds and the
-- later ALTER TABLE ADD COLUMN / CREATE INDEX steps), src/services/sqlite/SessionSearch.ts (FTS5 tables + triggers)
-- and src/services/sqlite/tool-uses.ts (tool_uses, v51). Only the tables the queries touch. Column order after the
-- rebuilds follows the migration order in SessionStore.ts.

CREATE TABLE schema_versions (
  id INTEGER PRIMARY KEY,
  version INTEGER UNIQUE NOT NULL,
  applied_at TEXT NOT NULL
);

-- sdk_sessions: rebuildSdkSessionsWithCompositeIdentity (SessionStore.ts:575) + later ALTERs
CREATE TABLE sdk_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_session_id TEXT NOT NULL,
  memory_session_id TEXT UNIQUE,
  project TEXT NOT NULL,
  platform_source TEXT NOT NULL DEFAULT 'claude',
  user_prompt TEXT,
  started_at TEXT NOT NULL,
  started_at_epoch INTEGER NOT NULL,
  completed_at TEXT,
  completed_at_epoch INTEGER,
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active', 'completed', 'failed')),
  worker_port INTEGER,
  prompt_counter INTEGER DEFAULT 0,
  custom_title TEXT,
  observed_model TEXT,
  observed_billing TEXT,
  project_key_source TEXT,
  cwd TEXT
);
CREATE INDEX idx_sdk_sessions_claude_id ON sdk_sessions(content_session_id);
CREATE INDEX idx_sdk_sessions_sdk_id ON sdk_sessions(memory_session_id);
CREATE INDEX idx_sdk_sessions_project ON sdk_sessions(project);
CREATE INDEX idx_sdk_sessions_status ON sdk_sessions(status);
CREATE INDEX idx_sdk_sessions_started ON sdk_sessions(started_at_epoch DESC);
CREATE INDEX idx_sdk_sessions_platform_source ON sdk_sessions(platform_source);
CREATE UNIQUE INDEX ux_sdk_sessions_platform_content ON sdk_sessions(platform_source, content_session_id);
CREATE INDEX idx_sdk_sessions_cwd ON sdk_sessions(cwd);
CREATE INDEX idx_sdk_sessions_project_nocase ON sdk_sessions(project COLLATE NOCASE);

-- observations: observations_new rebuild (SessionStore.ts:1868) + ALTERs (content_hash v22, generated_by_model,
-- relevance_count v26, agent_type/agent_id, metadata, occurrence_count/title_norm_key, reinforcement, merged_into_project)
CREATE TABLE observations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  memory_session_id TEXT NOT NULL,
  project TEXT NOT NULL,
  text TEXT,
  type TEXT NOT NULL,
  title TEXT,
  subtitle TEXT,
  facts TEXT,
  narrative TEXT,
  concepts TEXT,
  files_read TEXT,
  files_modified TEXT,
  prompt_number INTEGER,
  discovery_tokens INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  created_at_epoch INTEGER NOT NULL,
  content_hash TEXT,
  generated_by_model TEXT,
  relevance_count INTEGER DEFAULT 0,
  agent_type TEXT,
  agent_id TEXT,
  metadata TEXT,
  occurrence_count INTEGER NOT NULL DEFAULT 1,
  title_norm_key TEXT,
  reinforcement_dates TEXT,
  last_reinforced TEXT,
  merged_into_project TEXT,
  FOREIGN KEY(memory_session_id) REFERENCES sdk_sessions(memory_session_id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX idx_observations_sdk_session ON observations(memory_session_id);
CREATE INDEX idx_observations_project ON observations(project);
CREATE INDEX idx_observations_type ON observations(type);
CREATE INDEX idx_observations_created ON observations(created_at_epoch DESC);
CREATE INDEX idx_observations_content_hash ON observations(content_hash, created_at_epoch);
CREATE UNIQUE INDEX ux_observations_session_hash ON observations(memory_session_id, content_hash);
CREATE INDEX idx_observations_agent_type ON observations(agent_type);
CREATE INDEX idx_observations_agent_id ON observations(agent_id);
CREATE INDEX idx_observations_title_norm ON observations(project, title_norm_key);
CREATE INDEX idx_observations_merged_into ON observations(merged_into_project);
CREATE INDEX idx_observations_project_nocase ON observations(project COLLATE NOCASE);
CREATE INDEX idx_observations_merged_into_nocase ON observations(merged_into_project COLLATE NOCASE);
CREATE INDEX idx_observations_project_nocase_recent ON observations(project COLLATE NOCASE, created_at_epoch DESC);
CREATE INDEX idx_observations_merged_into_nocase_recent ON observations(merged_into_project COLLATE NOCASE, created_at_epoch DESC);
CREATE INDEX idx_observations_merged_into_nocase_project ON observations(merged_into_project COLLATE NOCASE, project);

-- session_summaries: session_summaries_new rebuild (SessionStore.ts:1900) + merged_into_project
CREATE TABLE session_summaries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  memory_session_id TEXT NOT NULL,
  project TEXT NOT NULL,
  request TEXT,
  investigated TEXT,
  learned TEXT,
  completed TEXT,
  next_steps TEXT,
  files_read TEXT,
  files_edited TEXT,
  notes TEXT,
  prompt_number INTEGER,
  discovery_tokens INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  created_at_epoch INTEGER NOT NULL,
  merged_into_project TEXT,
  FOREIGN KEY(memory_session_id) REFERENCES sdk_sessions(memory_session_id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX idx_session_summaries_sdk_session ON session_summaries(memory_session_id);
CREATE INDEX idx_session_summaries_project ON session_summaries(project);
CREATE INDEX idx_session_summaries_created ON session_summaries(created_at_epoch DESC);
CREATE INDEX idx_summaries_merged_into ON session_summaries(merged_into_project);
CREATE INDEX idx_summaries_project_nocase ON session_summaries(project COLLATE NOCASE);
CREATE INDEX idx_summaries_merged_into_nocase ON session_summaries(merged_into_project COLLATE NOCASE);
CREATE INDEX idx_summaries_project_nocase_recent ON session_summaries(project COLLATE NOCASE, created_at_epoch DESC);
CREATE INDEX idx_summaries_merged_into_nocase_recent ON session_summaries(merged_into_project COLLATE NOCASE, created_at_epoch DESC);
CREATE INDEX idx_summaries_merged_into_nocase_project ON session_summaries(merged_into_project COLLATE NOCASE, project);

-- user_prompts: user_prompts_new rebuild (SessionStore.ts:679) + ensureNativePromptIdentity (SessionStore.ts:369)
CREATE TABLE user_prompts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_db_id INTEGER,
  content_session_id TEXT NOT NULL,
  prompt_number INTEGER NOT NULL,
  prompt_text TEXT NOT NULL,
  created_at TEXT NOT NULL,
  created_at_epoch INTEGER NOT NULL,
  native_prompt_id TEXT,
  native_prompt_hash TEXT,
  FOREIGN KEY(session_db_id) REFERENCES sdk_sessions(id) ON DELETE CASCADE
);
CREATE INDEX idx_user_prompts_session ON user_prompts(session_db_id);
CREATE INDEX idx_user_prompts_claude_session ON user_prompts(content_session_id);
CREATE INDEX idx_user_prompts_created ON user_prompts(created_at_epoch DESC);
CREATE INDEX idx_user_prompts_prompt_number ON user_prompts(prompt_number);
CREATE INDEX idx_user_prompts_lookup ON user_prompts(session_db_id, prompt_number);
CREATE INDEX idx_user_prompts_content_lookup ON user_prompts(content_session_id, prompt_number);
CREATE UNIQUE INDEX idx_user_prompts_native_identity
  ON user_prompts(session_db_id, native_prompt_id) WHERE native_prompt_id IS NOT NULL;

-- observation_files (v68, SessionStore.ts:337)
CREATE TABLE observation_files (
  path TEXT NOT NULL,
  observation_id INTEGER NOT NULL REFERENCES observations(id) ON DELETE CASCADE,
  PRIMARY KEY (path, observation_id)
);
CREATE INDEX idx_observation_files_observation ON observation_files(observation_id);

-- dedup IDF model (SessionStore.ts:464)
CREATE TABLE token_df (
  project TEXT    NOT NULL,
  token   TEXT    NOT NULL,
  df      INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (project, token)
);
CREATE INDEX idx_token_df_project ON token_df(project);

-- tool_uses (v51, src/services/sqlite/tool-uses.ts:145)
CREATE TABLE tool_uses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tool_use_id TEXT NOT NULL,
  content_session_id TEXT NOT NULL,
  memory_session_id TEXT,
  session_db_id INTEGER,
  project TEXT NOT NULL,
  platform_source TEXT NOT NULL DEFAULT 'claude',
  tool_name TEXT NOT NULL,
  tool_input TEXT,
  tool_response TEXT,
  cwd TEXT,
  prompt_number INTEGER,
  agent_type TEXT,
  agent_id TEXT,
  observation_id INTEGER,
  or_generation_id TEXT,
  or_session_id TEXT,
  content_hash TEXT,
  created_at TEXT NOT NULL,
  created_at_epoch INTEGER NOT NULL,
  UNIQUE(content_session_id, tool_use_id)
);
CREATE INDEX idx_tool_uses_project ON tool_uses(project);
CREATE INDEX idx_tool_uses_project_nocase_created ON tool_uses(project COLLATE NOCASE, created_at_epoch DESC, id DESC);
CREATE INDEX idx_tool_uses_memory_session ON tool_uses(memory_session_id);
CREATE INDEX idx_tool_uses_content_session ON tool_uses(content_session_id);
CREATE INDEX idx_tool_uses_session_db_id ON tool_uses(session_db_id);
CREATE INDEX idx_tool_uses_tool_name ON tool_uses(tool_name);
CREATE INDEX idx_tool_uses_created_at_epoch ON tool_uses(created_at_epoch);
CREATE INDEX idx_tool_uses_observation_id ON tool_uses(observation_id);
CREATE INDEX idx_tool_uses_or_generation_id ON tool_uses(or_generation_id);

-- FTS5 external-content indexes + sync triggers (SessionSearch.ts:55-93, 255-290)
CREATE VIRTUAL TABLE observations_fts USING fts5(
  title, subtitle, narrative, text, facts, concepts,
  content='observations', content_rowid='id'
);
CREATE VIRTUAL TABLE session_summaries_fts USING fts5(
  request, investigated, learned, completed, next_steps, notes,
  content='session_summaries', content_rowid='id'
);

CREATE TRIGGER observations_ai AFTER INSERT ON observations BEGIN
  INSERT INTO observations_fts(rowid, title, subtitle, narrative, text, facts, concepts)
  VALUES (new.id, new.title, new.subtitle, new.narrative, new.text, new.facts, new.concepts);
END;
CREATE TRIGGER observations_ad AFTER DELETE ON observations BEGIN
  INSERT INTO observations_fts(observations_fts, rowid, title, subtitle, narrative, text, facts, concepts)
  VALUES('delete', old.id, old.title, old.subtitle, old.narrative, old.text, old.facts, old.concepts);
END;
CREATE TRIGGER observations_au
AFTER UPDATE OF title, subtitle, narrative, text, facts, concepts ON observations BEGIN
  INSERT INTO observations_fts(observations_fts, rowid, title, subtitle, narrative, text, facts, concepts)
  VALUES('delete', old.id, old.title, old.subtitle, old.narrative, old.text, old.facts, old.concepts);
  INSERT INTO observations_fts(rowid, title, subtitle, narrative, text, facts, concepts)
  VALUES (new.id, new.title, new.subtitle, new.narrative, new.text, new.facts, new.concepts);
END;

CREATE TRIGGER session_summaries_ai AFTER INSERT ON session_summaries BEGIN
  INSERT INTO session_summaries_fts(rowid, request, investigated, learned, completed, next_steps, notes)
  VALUES (new.id, new.request, new.investigated, new.learned, new.completed, new.next_steps, new.notes);
END;
CREATE TRIGGER session_summaries_ad AFTER DELETE ON session_summaries BEGIN
  INSERT INTO session_summaries_fts(session_summaries_fts, rowid, request, investigated, learned, completed, next_steps, notes)
  VALUES('delete', old.id, old.request, old.investigated, old.learned, old.completed, old.next_steps, old.notes);
END;
CREATE TRIGGER session_summaries_au
AFTER UPDATE OF request, investigated, learned, completed, next_steps, notes ON session_summaries BEGIN
  INSERT INTO session_summaries_fts(session_summaries_fts, rowid, request, investigated, learned, completed, next_steps, notes)
  VALUES('delete', old.id, old.request, old.investigated, old.learned, old.completed, old.next_steps, old.notes);
  INSERT INTO session_summaries_fts(rowid, request, investigated, learned, completed, next_steps, notes)
  VALUES (new.id, new.request, new.investigated, new.learned, new.completed, new.next_steps, new.notes);
END;
