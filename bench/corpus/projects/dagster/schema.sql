-- Dagster storage schema for SQLite (dagster-io/dagster @ 05ed5f2, Apache-2.0).
-- Produced by creating the pinned code's SqliteRunStorage, SqliteScheduleStorage and SqliteEventLogStorage
-- (python_modules/dagster/dagster/_core/storage/{runs,schedules,event_log}/schema.py, created via the storages'
-- own create_all + alembic stamp) and dumping sqlite_master. Dagster keeps these in three files (runs.db,
-- schedules.db, and the event log index shard history/runs/index.db, plus one shard per run); here they share one
-- database. secondary_indexes exists in all three with an identical definition and appears once; alembic_version is
-- left out. Indexes are exactly the app's.

-- ---- runs/runs.db
CREATE TABLE secondary_indexes (
	id INTEGER NOT NULL, 
	name VARCHAR(512), 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	migration_completed DATETIME, 
	PRIMARY KEY (id), 
	UNIQUE (name)
);
CREATE TABLE snapshots (
	id INTEGER NOT NULL, 
	snapshot_id VARCHAR(255) NOT NULL, 
	snapshot_body BLOB NOT NULL, 
	snapshot_type VARCHAR(63) NOT NULL, 
	PRIMARY KEY (id), 
	UNIQUE (snapshot_id)
);
CREATE TABLE daemon_heartbeats (
	id INTEGER NOT NULL, 
	daemon_type VARCHAR(255) NOT NULL, 
	daemon_id VARCHAR(255), 
	timestamp TIMESTAMP NOT NULL, 
	body TEXT, 
	PRIMARY KEY (id), 
	UNIQUE (daemon_type)
);
CREATE TABLE bulk_actions (
	id INTEGER NOT NULL, 
	"key" VARCHAR(32) NOT NULL, 
	status VARCHAR(255) NOT NULL, 
	timestamp TIMESTAMP NOT NULL, 
	body TEXT, 
	action_type VARCHAR(32), 
	selector_id TEXT, 
	job_name TEXT, 
	PRIMARY KEY (id), 
	UNIQUE ("key")
);
CREATE INDEX idx_bulk_actions_action_type ON bulk_actions (action_type);
CREATE INDEX idx_bulk_actions_selector_id ON bulk_actions (selector_id);
CREATE INDEX idx_bulk_actions_status ON bulk_actions (status);
CREATE INDEX idx_bulk_actions ON bulk_actions ("key");
CREATE TABLE backfill_tags (
	id INTEGER NOT NULL, 
	backfill_id VARCHAR(255), 
	"key" TEXT, 
	value TEXT, 
	PRIMARY KEY (id)
);
CREATE INDEX idx_backfill_tags_backfill_id ON backfill_tags (backfill_id, id);
CREATE TABLE instance_info (
	id INTEGER NOT NULL, 
	run_storage_id TEXT, 
	PRIMARY KEY (id)
);
CREATE TABLE kvs (
	id INTEGER NOT NULL, 
	"key" TEXT NOT NULL, 
	value TEXT, 
	PRIMARY KEY (id)
);
CREATE UNIQUE INDEX idx_kvs_keys_unique ON kvs ("key");
CREATE TABLE runs (
	id INTEGER NOT NULL, 
	run_id VARCHAR(255), 
	snapshot_id VARCHAR(255), 
	pipeline_name TEXT, 
	mode TEXT, 
	status VARCHAR(63), 
	run_body TEXT, 
	partition TEXT, 
	partition_set TEXT, 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	update_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	start_time FLOAT, 
	end_time FLOAT, 
	backfill_id VARCHAR(255), 
	PRIMARY KEY (id), 
	UNIQUE (run_id), 
	CONSTRAINT fk_runs_snapshot_id_snapshots_snapshot_id FOREIGN KEY(snapshot_id) REFERENCES snapshots (snapshot_id)
);
CREATE INDEX idx_run_status ON runs (status);
CREATE INDEX idx_run_partitions ON runs (partition_set, partition);
CREATE INDEX idx_run_range ON runs (status, update_timestamp, create_timestamp);
CREATE INDEX idx_runs_by_backfill_id ON runs (backfill_id, id);
CREATE INDEX idx_runs_by_job ON runs (pipeline_name, id);
CREATE TABLE run_tags (
	id INTEGER NOT NULL, 
	run_id VARCHAR(255), 
	"key" TEXT, 
	value TEXT, 
	PRIMARY KEY (id), 
	FOREIGN KEY(run_id) REFERENCES runs (run_id) ON DELETE CASCADE
);
CREATE INDEX idx_run_tags_run_idx ON run_tags (run_id, id);
CREATE INDEX idx_run_tags ON run_tags ("key", value);

-- ---- schedules/schedules.db
CREATE TABLE jobs (
	id INTEGER NOT NULL, 
	job_origin_id VARCHAR(255), 
	selector_id VARCHAR(255), 
	repository_origin_id VARCHAR(255), 
	status VARCHAR(63), 
	job_type VARCHAR(63), 
	job_body TEXT, 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	update_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id), 
	UNIQUE (job_origin_id)
);
CREATE INDEX ix_jobs_job_type ON jobs (job_type);
CREATE TABLE instigators (
	id INTEGER NOT NULL, 
	selector_id VARCHAR(255), 
	repository_selector_id VARCHAR(255), 
	status VARCHAR(63), 
	instigator_type VARCHAR(63), 
	instigator_body TEXT, 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	update_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id), 
	UNIQUE (selector_id)
);
CREATE INDEX ix_instigators_instigator_type ON instigators (instigator_type);
CREATE TABLE job_ticks (
	id INTEGER NOT NULL, 
	job_origin_id VARCHAR(255), 
	selector_id VARCHAR(255), 
	status VARCHAR(63), 
	type VARCHAR(63), 
	timestamp TIMESTAMP, 
	tick_body TEXT, 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	update_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id)
);
CREATE INDEX idx_job_tick_timestamp ON job_ticks (job_origin_id, timestamp);
CREATE INDEX ix_job_ticks_job_origin_id ON job_ticks (job_origin_id);
CREATE INDEX idx_tick_selector_timestamp ON job_ticks (selector_id, timestamp);
CREATE INDEX idx_job_tick_status ON job_ticks (job_origin_id, status);
CREATE TABLE asset_daemon_asset_evaluations (
	id INTEGER NOT NULL, 
	evaluation_id INTEGER, 
	asset_key TEXT, 
	asset_evaluation_body TEXT, 
	num_requested INTEGER, 
	num_skipped INTEGER, 
	num_discarded INTEGER, 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id)
);
CREATE INDEX ix_asset_daemon_asset_evaluations_evaluation_id ON asset_daemon_asset_evaluations (evaluation_id);
CREATE UNIQUE INDEX idx_asset_daemon_asset_evaluations_asset_key_evaluation_id ON asset_daemon_asset_evaluations (asset_key, evaluation_id);

-- ---- history/index.db
CREATE TABLE event_logs (
	id INTEGER NOT NULL, 
	run_id VARCHAR(255), 
	event TEXT NOT NULL, 
	dagster_event_type TEXT, 
	timestamp TIMESTAMP, 
	step_key TEXT, 
	asset_key TEXT, 
	partition TEXT, 
	PRIMARY KEY (id)
);
CREATE INDEX idx_step_key ON event_logs (step_key);
CREATE INDEX idx_event_type ON event_logs (dagster_event_type, id);
CREATE INDEX idx_events_by_asset ON event_logs (asset_key, dagster_event_type, id);
CREATE INDEX idx_events_by_asset_partition ON event_logs (asset_key, dagster_event_type, partition, id);
CREATE INDEX idx_events_by_run_id ON event_logs (run_id, id);
CREATE TABLE asset_keys (
	id INTEGER NOT NULL, 
	asset_key VARCHAR(512), 
	last_materialization TEXT, 
	last_run_id VARCHAR(255), 
	asset_details TEXT, 
	wipe_timestamp TIMESTAMP, 
	last_materialization_timestamp TIMESTAMP, 
	tags TEXT, 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	cached_status_data TEXT, 
	PRIMARY KEY (id), 
	UNIQUE (asset_key)
);
CREATE TABLE asset_event_tags (
	id INTEGER NOT NULL, 
	event_id INTEGER, 
	asset_key TEXT NOT NULL, 
	"key" TEXT NOT NULL, 
	value TEXT, 
	event_timestamp TIMESTAMP, 
	PRIMARY KEY (id)
);
CREATE INDEX idx_asset_event_tags_event_id ON asset_event_tags (event_id);
CREATE INDEX idx_asset_event_tags ON asset_event_tags (asset_key, "key", value);
CREATE TABLE dynamic_partitions (
	id INTEGER NOT NULL, 
	partitions_def_name TEXT NOT NULL, 
	partition TEXT NOT NULL, 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id)
);
CREATE UNIQUE INDEX idx_dynamic_partitions ON dynamic_partitions (partitions_def_name, partition);
CREATE TABLE concurrency_limits (
	id INTEGER NOT NULL, 
	concurrency_key VARCHAR(512) NOT NULL, 
	"limit" INTEGER NOT NULL, 
	using_default_limit BOOLEAN DEFAULT 0 NOT NULL, 
	update_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id), 
	UNIQUE (concurrency_key)
);
CREATE TABLE concurrency_slots (
	id INTEGER NOT NULL, 
	concurrency_key TEXT NOT NULL, 
	run_id TEXT, 
	step_key TEXT, 
	deleted BOOLEAN NOT NULL, 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id)
);
CREATE TABLE pending_steps (
	id INTEGER NOT NULL, 
	concurrency_key TEXT NOT NULL, 
	run_id TEXT, 
	step_key TEXT, 
	priority INTEGER, 
	assigned_timestamp DATETIME, 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id)
);
CREATE UNIQUE INDEX idx_pending_steps ON pending_steps (concurrency_key, run_id, step_key);
CREATE TABLE asset_check_executions (
	id INTEGER NOT NULL, 
	asset_key TEXT, 
	check_name TEXT, 
	partition TEXT, 
	run_id VARCHAR(255), 
	execution_status VARCHAR(255), 
	evaluation_event TEXT, 
	evaluation_event_timestamp DATETIME, 
	evaluation_event_storage_id INTEGER, 
	materialization_event_storage_id INTEGER, 
	create_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
	PRIMARY KEY (id)
);
CREATE UNIQUE INDEX idx_asset_check_executions_unique ON asset_check_executions (asset_key, check_name, run_id, partition);
CREATE INDEX idx_asset_check_executions ON asset_check_executions (asset_key, check_name, materialization_event_storage_id, partition);
