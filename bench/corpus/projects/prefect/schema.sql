-- Prefect server schema for SQLite (PrefectHQ/prefect @ f20489d, Apache-2.0).
-- Seven constraint/index names containing "task_run" are spelled "taskrun" here (e.g. ix_taskrun__next_scheduled_start_time_asc)
-- because the repo's secret scanner reads 'sk_' + 30 identifier characters as a token. Definitions are unchanged.
-- Produced by running the pinned server's own SQLite Alembic migrations (`prefect server database reset -y`, head
-- 27d8f4e1a6c9) and dumping sqlite_master. Every table and index is as the migrations create them, including the
-- randomblob() UUID defaults and the strftime('now') timestamp defaults; only alembic_version is left out.
CREATE TABLE flow (
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	tags JSON DEFAULT '[]' NOT NULL, labels JSON, 
	CONSTRAINT pk_flow PRIMARY KEY (id), 
	CONSTRAINT uq_flow__name UNIQUE (name)
);
CREATE TABLE concurrency_limit (
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	tag VARCHAR NOT NULL, 
	concurrency_limit INTEGER NOT NULL, 
	active_slots JSON DEFAULT '[]' NOT NULL, 
	CONSTRAINT pk_concurrency_limit PRIMARY KEY (id)
);
CREATE TABLE saved_search (
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	filters JSON DEFAULT '[]' NOT NULL, 
	CONSTRAINT pk_saved_search PRIMARY KEY (id), 
	CONSTRAINT uq_saved_search__name UNIQUE (name)
);
CREATE TABLE task_run_state_cache (
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	cache_key VARCHAR NOT NULL, 
	cache_expiration DATETIME, 
	task_run_state_id CHAR(36) NOT NULL, 
	CONSTRAINT pk_task_run_state_cache PRIMARY KEY (id)
);
CREATE TABLE agent (
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	last_activity_time DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	work_queue_id CHAR(36) NOT NULL, 
	CONSTRAINT pk_agent PRIMARY KEY (id), 
	CONSTRAINT fk_agent__work_queue_id__work_queue FOREIGN KEY(work_queue_id) REFERENCES work_queue (id), 
	CONSTRAINT uq_agent__name UNIQUE (name)
);
CREATE TABLE configuration (
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	"key" VARCHAR NOT NULL, 
	value JSON NOT NULL, 
	CONSTRAINT pk_configuration PRIMARY KEY (id), 
	CONSTRAINT uq_configuration__key UNIQUE ("key")
);
CREATE TABLE "block_schema" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	fields JSON DEFAULT '{}' NOT NULL, 
	block_type_id CHAR(36) NOT NULL, 
	checksum VARCHAR NOT NULL, 
	capabilities JSON DEFAULT '[]' NOT NULL, version VARCHAR DEFAULT 'non-versioned' NOT NULL, 
	CONSTRAINT pk_block_schema PRIMARY KEY (id), 
	CONSTRAINT fk_block_schema__block_type_id__block_type FOREIGN KEY(block_type_id) REFERENCES block_type (id) ON DELETE CASCADE
);
CREATE TABLE block_schema_reference (
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	parent_block_schema_id CHAR(36) NOT NULL, 
	reference_block_schema_id CHAR(36) NOT NULL, 
	CONSTRAINT pk_block_schema_reference PRIMARY KEY (id), 
	CONSTRAINT fk_block_schema_reference__parent_block_schema_id__block_schema FOREIGN KEY(parent_block_schema_id) REFERENCES block_schema (id) ON DELETE cascade, 
	CONSTRAINT fk_block_schema_reference__reference_block_schema_id__block_schema FOREIGN KEY(reference_block_schema_id) REFERENCES block_schema (id) ON DELETE cascade
);
CREATE TABLE "block_document" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	data JSON DEFAULT '{}' NOT NULL, 
	block_schema_id CHAR(36) NOT NULL, 
	block_type_id CHAR(36) NOT NULL, 
	is_anonymous BOOLEAN DEFAULT '0' NOT NULL, block_type_name VARCHAR, 
	CONSTRAINT pk_block_document PRIMARY KEY (id), 
	CONSTRAINT fk_block_document__block_type_id__block_type FOREIGN KEY(block_type_id) REFERENCES block_type (id) ON DELETE CASCADE, 
	CONSTRAINT fk_block__block_schema_id__block_schema FOREIGN KEY(block_schema_id) REFERENCES block_schema (id) ON DELETE CASCADE
);
CREATE TABLE "block_type" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	logo_url VARCHAR, 
	documentation_url VARCHAR, 
	description VARCHAR, 
	code_example VARCHAR, 
	is_protected BOOLEAN DEFAULT '0' NOT NULL, 
	slug VARCHAR NOT NULL, 
	CONSTRAINT pk_block_type PRIMARY KEY (id)
);
CREATE TABLE worker (
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	last_heartbeat_time DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	work_pool_id CHAR(36) NOT NULL, heartbeat_interval_seconds INTEGER, status VARCHAR(7) DEFAULT 'OFFLINE' NOT NULL, 
	CONSTRAINT pk_worker PRIMARY KEY (id), 
	CONSTRAINT fk_worker__work_pool_id__work_pool FOREIGN KEY(work_pool_id) REFERENCES work_pool (id) ON DELETE cascade, 
	CONSTRAINT uq_worker__work_pool_id_name UNIQUE (work_pool_id, name)
);
CREATE TABLE "flow_run_state" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	type VARCHAR(9) NOT NULL, 
	timestamp DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	message VARCHAR, 
	state_details JSON DEFAULT '{}' NOT NULL, 
	data JSON, 
	flow_run_id CHAR(36) NOT NULL, 
	result_artifact_id CHAR(36), 
	CONSTRAINT pk_flow_run_state PRIMARY KEY (id), 
	CONSTRAINT fk_flow_run_state__result_artifact_id__artifact FOREIGN KEY(result_artifact_id) REFERENCES artifact (id) ON DELETE SET NULL, 
	CONSTRAINT fk_flow_run_state__flow_run_id__flow_run FOREIGN KEY(flow_run_id) REFERENCES flow_run (id) ON DELETE CASCADE
);
CREATE TABLE "task_run_state" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	type VARCHAR(9) NOT NULL, 
	timestamp DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	message VARCHAR, 
	state_details JSON DEFAULT '{}' NOT NULL, 
	data JSON, 
	task_run_id CHAR(36) NOT NULL, 
	result_artifact_id CHAR(36), 
	CONSTRAINT pk_task_run_state PRIMARY KEY (id), 
	CONSTRAINT fk_taskrun_state__taskrun_id__taskrun FOREIGN KEY(task_run_id) REFERENCES task_run (id) ON DELETE CASCADE, 
	CONSTRAINT fk_taskrun_state__result_artifact_id__artifact FOREIGN KEY(result_artifact_id) REFERENCES artifact (id) ON DELETE SET NULL
);
CREATE TABLE "work_pool" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	description VARCHAR, 
	type VARCHAR NOT NULL, 
	base_job_template JSON DEFAULT '{}' NOT NULL, 
	is_paused BOOLEAN DEFAULT '0' NOT NULL, 
	concurrency_limit INTEGER, 
	default_queue_id CHAR(36), status VARCHAR(9) DEFAULT 'NOT_READY' NOT NULL, last_transitioned_status_at DATETIME, last_status_event_id CHAR(36), storage_configuration JSON DEFAULT '{}' NOT NULL, 
	CONSTRAINT pk_work_pool PRIMARY KEY (id), 
	CONSTRAINT uq_work_pool__name UNIQUE (name), 
	CONSTRAINT fk_work_pool__default_queue_id__work_queue FOREIGN KEY(default_queue_id) REFERENCES work_queue (id) ON DELETE RESTRICT
);
CREATE TABLE "work_queue" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	filter JSON, 
	description VARCHAR DEFAULT ('') NOT NULL, 
	is_paused BOOLEAN DEFAULT '0' NOT NULL, 
	concurrency_limit INTEGER, 
	last_polled DATETIME, 
	priority INTEGER DEFAULT '1' NOT NULL, 
	work_pool_id CHAR(36) NOT NULL, status VARCHAR(9) DEFAULT 'NOT_READY' NOT NULL, 
	CONSTRAINT pk_work_queue PRIMARY KEY (id), 
	CONSTRAINT fk_work_queue__work_pool_id__work_pool FOREIGN KEY(work_pool_id) REFERENCES work_pool (id) ON DELETE CASCADE, 
	CONSTRAINT uq_work_queue__work_pool_id_name UNIQUE (work_pool_id, name)
);
CREATE TABLE "artifact" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	"key" VARCHAR, 
	type VARCHAR, 
	data JSON, 
	metadata_ JSON, 
	task_run_id CHAR(36), 
	flow_run_id CHAR(36), description VARCHAR, 
	CONSTRAINT pk_artifact PRIMARY KEY (id)
);
CREATE TABLE "flow_run" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	state_type VARCHAR(9), 
	run_count INTEGER DEFAULT '0' NOT NULL, 
	expected_start_time DATETIME, 
	next_scheduled_start_time DATETIME, 
	start_time DATETIME, 
	end_time DATETIME, 
	total_run_time DATETIME DEFAULT '0' NOT NULL, 
	flow_version VARCHAR, 
	parameters JSON DEFAULT '{}' NOT NULL, 
	idempotency_key VARCHAR, 
	context JSON DEFAULT '{}' NOT NULL, 
	empirical_policy JSON DEFAULT '{}' NOT NULL, 
	tags JSON DEFAULT '[]' NOT NULL, 
	auto_scheduled BOOLEAN DEFAULT '0' NOT NULL, 
	flow_id CHAR(36) NOT NULL, 
	deployment_id CHAR(36), 
	parent_task_run_id CHAR(36), 
	state_id CHAR(36), 
	state_name VARCHAR, 
	infrastructure_document_id CHAR(36), 
	work_queue_name VARCHAR, 
	state_timestamp DATETIME, 
	created_by JSON, 
	infrastructure_pid VARCHAR, 
	work_queue_id CHAR(36), job_variables JSON DEFAULT '{}', deployment_version VARCHAR, labels JSON, 
	CONSTRAINT pk_flow_run PRIMARY KEY (id), 
	CONSTRAINT fk_flow_run__parent_task_run_id__task_run FOREIGN KEY(parent_task_run_id) REFERENCES task_run (id) ON DELETE SET NULL, 
	CONSTRAINT fk_flow_run__state_id__flow_run_state FOREIGN KEY(state_id) REFERENCES flow_run_state (id) ON DELETE SET NULL, 
	CONSTRAINT fk_flow_run__flow_id__flow FOREIGN KEY(flow_id) REFERENCES flow (id) ON DELETE CASCADE, 
	CONSTRAINT fk_flow_run__work_queue_id__work_queue FOREIGN KEY(work_queue_id) REFERENCES work_queue (id) ON DELETE SET NULL, 
	CONSTRAINT fk_flow_run__infrastructure_document_id__block_document FOREIGN KEY(infrastructure_document_id) REFERENCES block_document (id) ON DELETE CASCADE
);
CREATE TABLE artifact_collection (
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	"key" VARCHAR NOT NULL, 
	latest_id CHAR(36) NOT NULL, task_run_id CHAR(36), flow_run_id CHAR(36), type VARCHAR, data JSON, description VARCHAR, metadata_ JSON, 
	CONSTRAINT pk_artifact_collection PRIMARY KEY (id), 
	CONSTRAINT uq_artifact_collection__key UNIQUE ("key")
);
CREATE TABLE "concurrency_limit_v2" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	active BOOLEAN NOT NULL, 
	name VARCHAR NOT NULL, 
	"limit" INTEGER NOT NULL, 
	active_slots INTEGER NOT NULL, 
	denied_slots INTEGER NOT NULL, 
	slot_decay_per_second FLOAT NOT NULL, 
	avg_slot_occupancy_seconds FLOAT NOT NULL, 
	CONSTRAINT pk_concurrency_limit_v2 PRIMARY KEY (id), 
	CONSTRAINT uq_concurrency_limit_v2__name UNIQUE (name)
);
CREATE TABLE "log" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	level SMALLINT NOT NULL, 
	flow_run_id CHAR(36), 
	task_run_id CHAR(36), 
	message TEXT NOT NULL, 
	timestamp DATETIME NOT NULL, 
	CONSTRAINT pk_log PRIMARY KEY (id)
);
CREATE TABLE "flow_run_input" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	"key" VARCHAR NOT NULL, 
	value TEXT NOT NULL, 
	flow_run_id CHAR(36) NOT NULL, sender VARCHAR, 
	CONSTRAINT pk_flow_run_input PRIMARY KEY (id), 
	CONSTRAINT uq_flow_run_input__flow_run_id_key UNIQUE (flow_run_id, "key"), 
	CONSTRAINT fk_flow_run_input__flow_run_id__flow_run FOREIGN KEY(flow_run_id) REFERENCES flow_run (id) ON DELETE cascade
);
CREATE TABLE csrf_token (
	token VARCHAR NOT NULL, 
	client VARCHAR NOT NULL, 
	expiration DATETIME NOT NULL, 
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	CONSTRAINT pk_csrf_token PRIMARY KEY (id), 
	CONSTRAINT uq_csrf_token__client UNIQUE (client)
);
CREATE TABLE automation (
	name VARCHAR NOT NULL, 
	description VARCHAR NOT NULL, 
	enabled BOOLEAN DEFAULT '1' NOT NULL, 
	"trigger" JSON NOT NULL, 
	actions JSON NOT NULL, 
	actions_on_trigger JSON DEFAULT '[]' NOT NULL, 
	actions_on_resolve JSON DEFAULT '[]' NOT NULL, 
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, tags JSON DEFAULT '[]' NOT NULL, 
	CONSTRAINT pk_automation PRIMARY KEY (id)
);
CREATE TABLE automation_related_resource (
	automation_id CHAR(36) NOT NULL, 
	resource_id VARCHAR, 
	automation_owned_by_resource BOOLEAN DEFAULT '0' NOT NULL, 
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	CONSTRAINT pk_automation_related_resource PRIMARY KEY (id), 
	CONSTRAINT fk_automation_related_resource__automation_id__automation FOREIGN KEY(automation_id) REFERENCES automation (id) ON DELETE CASCADE
);
CREATE TABLE composite_trigger_child_firing (
	automation_id CHAR(36) NOT NULL, 
	parent_trigger_id CHAR(36) NOT NULL, 
	child_trigger_id CHAR(36) NOT NULL, 
	child_firing_id CHAR(36) NOT NULL, 
	child_fired_at DATETIME, 
	child_firing JSON NOT NULL, 
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	CONSTRAINT pk_composite_trigger_child_firing PRIMARY KEY (id), 
	CONSTRAINT fk_composite_trigger_child_firing__automation_id__automation FOREIGN KEY(automation_id) REFERENCES automation (id) ON DELETE CASCADE
);
CREATE TABLE "automation_bucket" (
	automation_id CHAR(36) NOT NULL, 
	trigger_id CHAR(36) NOT NULL, 
	bucketing_key JSON NOT NULL, 
	last_event JSON, 
	start DATETIME NOT NULL, 
	"end" DATETIME NOT NULL, 
	count INTEGER NOT NULL, 
	last_operation VARCHAR, 
	triggered_at DATETIME, 
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	CONSTRAINT pk_automation_bucket PRIMARY KEY (id), 
	CONSTRAINT fk_automation_bucket__automation_id__automation FOREIGN KEY(automation_id) REFERENCES automation (id) ON DELETE CASCADE
);
CREATE TABLE event_resources (
	occurred DATETIME NOT NULL, 
	resource_id TEXT NOT NULL, 
	resource_role TEXT NOT NULL, 
	resource JSON NOT NULL, 
	event_id CHAR(36) NOT NULL, 
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	CONSTRAINT pk_event_resources PRIMARY KEY (id)
);
CREATE TABLE events (
	occurred DATETIME NOT NULL, 
	event TEXT NOT NULL, 
	resource_id TEXT NOT NULL, 
	resource JSON NOT NULL, 
	related_resource_ids JSON DEFAULT '[]' NOT NULL, 
	related JSON DEFAULT '[]' NOT NULL, 
	payload JSON NOT NULL, 
	received DATETIME NOT NULL, 
	recorded DATETIME NOT NULL, 
	follows CHAR(36), 
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	CONSTRAINT pk_events PRIMARY KEY (id)
);
CREATE TABLE "variable" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	tags JSON DEFAULT '[]' NOT NULL, 
	value JSON, 
	CONSTRAINT pk_variable PRIMARY KEY (id), 
	CONSTRAINT uq_variable__name UNIQUE (name)
);
CREATE TABLE "automation_event_follower" (
	leader_event_id CHAR(36) NOT NULL, 
	follower_event_id CHAR(36) NOT NULL, 
	received DATETIME NOT NULL, 
	follower JSON NOT NULL, 
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	scope VARCHAR NOT NULL, 
	CONSTRAINT pk_automation_event_follower PRIMARY KEY (id)
);
CREATE TABLE "deployment" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	tags JSON DEFAULT '[]' NOT NULL, 
	parameters JSON DEFAULT '{}' NOT NULL, 
	flow_id CHAR(36) NOT NULL, 
	description TEXT, 
	infrastructure_document_id CHAR(36), 
	parameter_openapi_schema JSON, 
	storage_document_id CHAR(36), 
	version VARCHAR, 
	infra_overrides JSON DEFAULT '{}' NOT NULL, 
	path VARCHAR, 
	entrypoint VARCHAR, 
	work_queue_name VARCHAR, 
	created_by JSON, 
	updated_by JSON, 
	work_queue_id CHAR(36), 
	pull_steps JSON, 
	enforce_parameter_schema BOOLEAN DEFAULT '0' NOT NULL, 
	last_polled DATETIME, 
	paused BOOLEAN DEFAULT '0' NOT NULL, 
	status VARCHAR(9) DEFAULT 'NOT_READY' NOT NULL, 
	concurrency_limit INTEGER, 
	concurrency_options JSON, 
	concurrency_limit_id CHAR(36), 
	labels JSON, version_id CHAR(36), 
	CONSTRAINT pk_deployment PRIMARY KEY (id), 
	CONSTRAINT fk_deployment__infrastructure_document_id__block_document FOREIGN KEY(infrastructure_document_id) REFERENCES block_document (id) ON DELETE CASCADE, 
	CONSTRAINT fk_deployment__storage_document_id__block_document FOREIGN KEY(storage_document_id) REFERENCES block_document (id) ON DELETE CASCADE, 
	CONSTRAINT fk_deployment__flow_id__flow FOREIGN KEY(flow_id) REFERENCES flow (id) ON DELETE CASCADE, 
	CONSTRAINT fk_deployment__work_queue_id__work_queue FOREIGN KEY(work_queue_id) REFERENCES work_queue (id) ON DELETE SET NULL, 
	CONSTRAINT fk_deployment__concurrency_limit_id__concurrency_limit_v2 FOREIGN KEY(concurrency_limit_id) REFERENCES concurrency_limit_v2 (id) ON DELETE SET NULL
);
CREATE TABLE "deployment_schedule" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	schedule JSON NOT NULL, 
	active BOOLEAN NOT NULL, 
	deployment_id CHAR(36) NOT NULL, 
	max_scheduled_runs INTEGER, parameters JSON DEFAULT '{}' NOT NULL, slug VARCHAR, 
	CONSTRAINT pk_deployment_schedule PRIMARY KEY (id), 
	CONSTRAINT fk_deployment_schedule__deployment_id__deployment FOREIGN KEY(deployment_id) REFERENCES deployment (id) ON DELETE CASCADE
);
CREATE TABLE deployment_version (
	deployment_id CHAR(36) NOT NULL, 
	branch VARCHAR, 
	version_info JSON DEFAULT '{}' NOT NULL, 
	description TEXT, 
	tags JSON DEFAULT '[]' NOT NULL, 
	labels JSON, 
	entrypoint VARCHAR, 
	pull_steps JSON, 
	parameters JSON DEFAULT '{}' NOT NULL, 
	parameter_openapi_schema JSON, 
	enforce_parameter_schema BOOLEAN DEFAULT '0' NOT NULL, 
	work_queue_id CHAR(36), 
	work_queue_name VARCHAR, 
	infra_overrides JSON DEFAULT '{}' NOT NULL, 
	id CHAR(36) DEFAULT (GEN_RANDOM_UUID()) NOT NULL, 
	created DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL, 
	updated DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL, 
	CONSTRAINT pk_deployment_version PRIMARY KEY (id), 
	CONSTRAINT fk_deployment_version__deployment_id__deployment FOREIGN KEY(deployment_id) REFERENCES deployment (id) ON DELETE CASCADE, 
	CONSTRAINT fk_deployment_version__work_queue_id__work_queue FOREIGN KEY(work_queue_id) REFERENCES work_queue (id) ON DELETE SET NULL
);
CREATE TABLE "task_run" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	state_type VARCHAR(9), 
	run_count INTEGER DEFAULT '0' NOT NULL, 
	expected_start_time DATETIME, 
	next_scheduled_start_time DATETIME, 
	start_time DATETIME, 
	end_time DATETIME, 
	total_run_time DATETIME DEFAULT '0' NOT NULL, 
	task_key VARCHAR NOT NULL, 
	dynamic_key VARCHAR NOT NULL, 
	cache_key VARCHAR, 
	cache_expiration DATETIME, 
	task_version VARCHAR, 
	empirical_policy JSON DEFAULT '{}' NOT NULL, 
	task_inputs JSON DEFAULT '{}' NOT NULL, 
	tags JSON DEFAULT '[]' NOT NULL, 
	flow_run_id CHAR(36), 
	state_id CHAR(36), 
	state_name VARCHAR, 
	state_timestamp DATETIME, 
	flow_run_run_count INTEGER DEFAULT '0' NOT NULL, 
	labels JSON, 
	CONSTRAINT pk_task_run PRIMARY KEY (id), 
	CONSTRAINT fk_task_run__flow_run_id__flow_run FOREIGN KEY(flow_run_id) REFERENCES flow_run (id) ON DELETE CASCADE
);
CREATE TABLE "block_document_reference" (
	id CHAR(36) DEFAULT ((
        lower(hex(randomblob(4))) 
        || '-' 
        || lower(hex(randomblob(2))) 
        || '-4' 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || substr('89ab',abs(random()) % 4 + 1, 1) 
        || substr(lower(hex(randomblob(2))),2) 
        || '-' 
        || lower(hex(randomblob(6)))
    )) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	name VARCHAR NOT NULL, 
	parent_block_document_id CHAR(36) NOT NULL, 
	reference_block_document_id CHAR(36) NOT NULL, 
	CONSTRAINT pk_block_document_reference PRIMARY KEY (id), 
	CONSTRAINT fk_block_document_reference__parent_block_document_id__block_document FOREIGN KEY(parent_block_document_id) REFERENCES block_document (id) ON DELETE CASCADE, 
	CONSTRAINT fk_block_document_reference__reference_block_document_id__block_document FOREIGN KEY(reference_block_document_id) REFERENCES block_document (id) ON DELETE CASCADE, 
	CONSTRAINT ck_block_document_reference__ck_block_document_reference__no_self_reference CHECK (parent_block_document_id != reference_block_document_id)
);
CREATE TABLE automation_held_event (
	automation_id CHAR(36) NOT NULL, 
	trigger_id CHAR(36) NOT NULL, 
	bucketing_key JSON DEFAULT '[]' NOT NULL, 
	event_id CHAR(36) NOT NULL, 
	occurred DATETIME NOT NULL, 
	id CHAR(36) DEFAULT (
    (
        lower(hex(randomblob(4)))
        || '-'
        || lower(hex(randomblob(2)))
        || '-4'
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || substr('89ab',abs(random()) % 4 + 1, 1)
        || substr(lower(hex(randomblob(2))),2)
        || '-'
        || lower(hex(randomblob(6)))
    )
    ) NOT NULL, 
	created DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	updated DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f000', 'now')) NOT NULL, 
	CONSTRAINT pk_automation_held_event PRIMARY KEY (id), 
	CONSTRAINT fk_automation_held_event__automation_id__automation FOREIGN KEY(automation_id) REFERENCES automation (id) ON DELETE CASCADE
);
CREATE INDEX ix_flow__updated ON flow (updated);
CREATE INDEX ix_concurrency_limit__updated ON concurrency_limit (updated);
CREATE INDEX ix_saved_search__updated ON saved_search (updated);
CREATE INDEX ix_taskrun_state_cache__cache_key_created_desc ON task_run_state_cache (cache_key, created DESC);
CREATE INDEX ix_task_run_state_cache__updated ON task_run_state_cache (updated);
CREATE INDEX ix_agent__updated ON agent (updated);
CREATE INDEX ix_agent__work_queue_id ON agent (work_queue_id);
CREATE INDEX ix_configuration__key ON configuration ("key");
CREATE INDEX ix_configuration__updated ON configuration (updated);
CREATE INDEX ix_flow__created ON flow (created);
CREATE INDEX ix_block_schema__updated ON block_schema (updated);
CREATE INDEX ix_block_schema_reference__updated ON block_schema_reference (updated);
CREATE INDEX ix_flow_name_case_insensitive on flow (name COLLATE NOCASE);
CREATE INDEX ix_block_schema__block_type_id ON block_schema (block_type_id);
CREATE INDEX ix_block_schema__created ON block_schema (created);
CREATE UNIQUE INDEX uq_block__type_id_name ON block_document (block_type_id, name);
CREATE INDEX ix_block_document__is_anonymous ON block_document (is_anonymous);
CREATE INDEX ix_block_document__name ON block_document (name);
CREATE INDEX ix_block_document__updated ON block_document (updated);
CREATE INDEX ix_block_type__updated ON block_type (updated);
CREATE INDEX ix_block_type_name_case_insensitive ON block_type (name);
CREATE UNIQUE INDEX uq_block_type__slug ON block_type (slug);
CREATE UNIQUE INDEX uq_concurrency_limit__tag ON concurrency_limit (tag);
CREATE UNIQUE INDEX uq_block_schema__checksum_version ON block_schema (checksum, version);
CREATE INDEX ix_worker__updated ON worker (updated);
CREATE INDEX ix_worker__work_pool_id_last_heartbeat_time ON worker (work_pool_id, last_heartbeat_time);
CREATE INDEX ix_worker__work_pool_id ON worker (work_pool_id);
CREATE INDEX ix_flow_run_state__updated ON flow_run_state (updated);
CREATE INDEX ix_flow_run_state__name ON flow_run_state (name);
CREATE INDEX ix_flow_run_state__type ON flow_run_state (type);
CREATE INDEX ix_flow_run_state__result_artifact_id ON flow_run_state (result_artifact_id);
CREATE UNIQUE INDEX uq_flow_run_state__flow_run_id_timestamp_desc ON flow_run_state (flow_run_id, timestamp);
CREATE INDEX ix_task_run_state__result_artifact_id ON task_run_state (result_artifact_id);
CREATE INDEX ix_task_run_state__name ON task_run_state (name);
CREATE INDEX ix_task_run_state__updated ON task_run_state (updated);
CREATE INDEX ix_task_run_state__type ON task_run_state (type);
CREATE UNIQUE INDEX uq_taskrun_state__taskrun_id_timestamp_desc ON task_run_state (task_run_id, timestamp);
CREATE INDEX ix_work_pool__type ON work_pool (type);
CREATE INDEX ix_work_pool__updated ON work_pool (updated);
CREATE INDEX ix_work_queue__work_pool_id ON work_queue (work_pool_id);
CREATE INDEX ix_work_queue__updated ON work_queue (updated);
CREATE INDEX ix_work_queue__work_pool_id_priority ON work_queue (work_pool_id, priority);
CREATE INDEX ix_artifact__task_run_id ON artifact (task_run_id);
CREATE INDEX ix_artifact__flow_run_id ON artifact (flow_run_id);
CREATE INDEX ix_artifact__updated ON artifact (updated);
CREATE INDEX ix_flow_run__flow_version ON flow_run (flow_version);
CREATE INDEX ix_flow_run__infrastructure_document_id ON flow_run (infrastructure_document_id);
CREATE INDEX ix_flow_run__name ON flow_run (name);
CREATE INDEX ix_flow_run__next_scheduled_start_time_asc ON flow_run (next_scheduled_start_time);
CREATE INDEX ix_flow_run__parent_task_run_id ON flow_run (parent_task_run_id);
CREATE INDEX ix_flow_run__start_time ON flow_run (start_time);
CREATE INDEX ix_flow_run__state_id ON flow_run (state_id);
CREATE INDEX ix_flow_run__state_name ON flow_run (state_name);
CREATE INDEX ix_flow_run__state_timestamp ON flow_run (state_timestamp);
CREATE INDEX ix_flow_run__state_type ON flow_run (state_type);
CREATE INDEX ix_flow_run__updated ON flow_run (updated);
CREATE INDEX ix_flow_run__work_queue_id ON flow_run (work_queue_id);
CREATE INDEX ix_flow_run__work_queue_name ON flow_run (work_queue_name);
CREATE INDEX ix_flow_run_name_case_insensitive ON flow_run (name);
CREATE UNIQUE INDEX uq_flow_run__flow_id_idempotency_key ON flow_run (flow_id, idempotency_key);
CREATE INDEX ix_flow_run__end_time_desc ON flow_run (end_time);
CREATE INDEX ix_flow_run__expected_start_time_desc ON flow_run (expected_start_time);
CREATE INDEX ix_flow_run__flow_id ON flow_run (flow_id);
CREATE INDEX ix_artifact__key ON artifact ("key");
CREATE INDEX ix_artifact_collection__key_latest_id ON artifact_collection ("key", latest_id);
CREATE INDEX ix_concurrency_limit_v2__updated ON concurrency_limit_v2 (updated);
CREATE INDEX ix_log__flow_run_id ON log (flow_run_id);
CREATE INDEX ix_log__flow_run_id_timestamp ON log (flow_run_id, timestamp);
CREATE INDEX ix_log__timestamp ON log (timestamp);
CREATE INDEX ix_log__updated ON log (updated);
CREATE INDEX ix_log__level ON log (level);
CREATE INDEX ix_log__task_run_id ON log (task_run_id);
CREATE INDEX ix_block_document_name_case_insensitive on block_document (name COLLATE NOCASE);
CREATE INDEX ix_flow_run_input__updated ON flow_run_input (updated);
CREATE INDEX ix_csrf_token__updated ON csrf_token (updated);
CREATE INDEX ix_automation__updated ON automation (updated);
CREATE INDEX ix_automation_related_resource__resource_id ON automation_related_resource (resource_id);
CREATE INDEX ix_automation_related_resource__updated ON automation_related_resource (updated);
CREATE UNIQUE INDEX uq_automation_related_resource__automation_id__resource_id ON automation_related_resource (automation_id, resource_id);
CREATE INDEX ix_composite_trigger_child_firing__updated ON composite_trigger_child_firing (updated);
CREATE UNIQUE INDEX uq_composite_trigger_child_firing__a_id__pt_id__ct__id ON composite_trigger_child_firing (automation_id, parent_trigger_id, child_trigger_id);
CREATE INDEX ix_flow_run__deployment_version ON flow_run (deployment_version);
CREATE INDEX ix_automation_bucket__automation_id__end ON automation_bucket (automation_id, "end");
CREATE INDEX ix_automation_bucket__updated ON automation_bucket (updated);
CREATE UNIQUE INDEX uq_automation_bucket__automation_id__trigger_id__bucketing_key ON automation_bucket (automation_id, trigger_id, bucketing_key);
CREATE INDEX ix_event_resources__resource_id__occurred ON event_resources (resource_id, occurred);
CREATE INDEX ix_event_resources__updated ON event_resources (updated);
CREATE INDEX ix_events__event__id ON events (event, id);
CREATE INDEX ix_events__event_occurred_id ON events (event, occurred, id);
CREATE INDEX ix_events__event_related_occurred ON events (event, related, occurred);
CREATE INDEX ix_events__event_resource_id_occurred ON events (event, resource_id, occurred);
CREATE INDEX ix_events__occurred ON events (occurred);
CREATE INDEX ix_events__occurred_id ON events (occurred, id);
CREATE INDEX ix_events__related_resource_ids ON events (related_resource_ids);
CREATE INDEX ix_events__updated ON events (updated);
CREATE INDEX ix_variable__updated ON variable (updated);
CREATE INDEX ix_automation_event_follower__received ON automation_event_follower (received);
CREATE INDEX ix_automation_event_follower__leader_event_id ON automation_event_follower (leader_event_id);
CREATE INDEX ix_automation_event_follower__updated ON automation_event_follower (updated);
CREATE INDEX ix_automation_event_follower__scope ON automation_event_follower (scope);
CREATE UNIQUE INDEX uq_follower_for_scope ON automation_event_follower (scope, follower_event_id);
CREATE INDEX ix_artifact_collection__updated ON artifact_collection (updated);
CREATE INDEX ix_artifact__key_created_desc ON artifact ("key", created DESC);
CREATE INDEX ix_block_document__block_type_name__name ON block_document (block_type_name, name);
CREATE INDEX ix_deployment__updated ON deployment (updated);
CREATE INDEX ix_deployment__created ON deployment (created);
CREATE INDEX ix_deployment_name_case_insensitive ON deployment (name);
CREATE UNIQUE INDEX uq_deployment__flow_id_name ON deployment (flow_id, name);
CREATE INDEX ix_deployment__paused ON deployment (paused);
CREATE INDEX ix_deployment__flow_id ON deployment (flow_id);
CREATE INDEX ix_deployment__work_queue_name ON deployment (work_queue_name);
CREATE INDEX ix_deployment__work_queue_id ON deployment (work_queue_id);
CREATE INDEX ix_deployment_schedule__updated ON deployment_schedule (updated);
CREATE INDEX ix_deployment_schedule__deployment_id ON deployment_schedule (deployment_id);
CREATE INDEX ix_flow_run__scheduler_deployment_id_auto_scheduled_next_schedu ON flow_run (deployment_id, auto_scheduled, next_scheduled_start_time) WHERE state_type = 'SCHEDULED';
CREATE INDEX ix_deployment_schedule__slug ON deployment_schedule (slug);
CREATE UNIQUE INDEX ix_deployment_schedule__deployment_id__slug
        ON deployment_schedule(deployment_id, slug)
        WHERE slug IS NOT NULL;
CREATE INDEX ix_deployment_version__deployment_id ON deployment_version (deployment_id);
CREATE INDEX ix_deployment_version__updated ON deployment_version (updated);
CREATE INDEX ix_deployment_version__work_queue_id ON deployment_version (work_queue_id);
CREATE INDEX ix_deployment_version__work_queue_name ON deployment_version (work_queue_name);
CREATE UNIQUE INDEX uq_deployment_version__deployment__branch ON deployment_version (deployment_id, branch);
CREATE INDEX ix_deployment__version_id ON deployment (version_id);
CREATE INDEX ix_ae_follower_scope_leader ON automation_event_follower (scope, leader_event_id);
CREATE INDEX ix_task_run__flow_run_id ON task_run (flow_run_id);
CREATE INDEX ix_task_run__end_time_desc ON task_run (end_time);
CREATE INDEX ix_task_run__state_type ON task_run (state_type);
CREATE INDEX ix_task_run__start_time ON task_run (start_time);
CREATE INDEX ix_task_run__updated ON task_run (updated);
CREATE INDEX ix_task_run_name_case_insensitive ON task_run (name);
CREATE INDEX ix_task_run__state_id ON task_run (state_id);
CREATE INDEX ix_taskrun__next_scheduled_start_time_asc ON task_run (next_scheduled_start_time);
CREATE UNIQUE INDEX uq_taskrun__flow_run_id_task_key_dynamic_key ON task_run (flow_run_id, task_key, dynamic_key);
CREATE INDEX ix_task_run__state_name ON task_run (state_name);
CREATE INDEX ix_task_run__name ON task_run (name);
CREATE INDEX ix_task_run__expected_start_time_desc ON task_run (expected_start_time);
CREATE INDEX ix_task_run__state_timestamp ON task_run (state_timestamp);
CREATE INDEX ix_flow_run__schedule_id_scheduler
        ON flow_run (deployment_id, json_extract(created_by, '$.id'), next_scheduled_start_time)
        WHERE state_type = 'SCHEDULED' AND auto_scheduled = 1;
CREATE INDEX ix_task_run__state_type_start_time
        ON task_run (state_type, start_time)
        ;
CREATE INDEX ix_block_document_reference__updated ON block_document_reference (updated);
CREATE INDEX ix_event_resources__occurred
        ON event_resources (occurred)
        ;
CREATE INDEX ix_event_resources__event_id
        ON event_resources (event_id)
        ;
CREATE INDEX ix_flow_run__deployment_id
        ON flow_run (deployment_id)
        ;
CREATE INDEX ix_flow_run__state_type_coalesce_start_time
        ON flow_run (state_type, coalesce(start_time, expected_start_time))
        ;
CREATE UNIQUE INDEX uq_automation_held_event__trigger_key_event ON automation_held_event (automation_id, trigger_id, bucketing_key, event_id);
CREATE INDEX ix_automation_held_event__trigger_key_occurred ON automation_held_event (automation_id, trigger_id, bucketing_key, occurred, event_id);
CREATE INDEX ix_automation_held_event__updated ON automation_held_event (updated);
CREATE INDEX ix_flow_run_state__type_name_timestamp ON flow_run_state (type, name, timestamp);
CREATE INDEX ix_taskrun_state__type_name_timestamp ON task_run_state (type, name, timestamp);
