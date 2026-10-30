-- MLflow tracking store schema (mlflow/mlflow @ d0b397f = v3.17.2, Apache-2.0): the tables the queries touch, as
-- SqlAlchemyStore's own alembic migrations leave them on SQLite (mlflow 3.17.2 from PyPI, dumped with .schema).
-- Note: runs has no index on experiment_id; only the PK (run_uuid).
CREATE TABLE "experiments" (
	experiment_id INTEGER NOT NULL, 
	name VARCHAR(256) NOT NULL, 
	artifact_location VARCHAR(256), 
	lifecycle_stage VARCHAR(32), 
	creation_time BIGINT, 
	last_update_time BIGINT, 
	workspace VARCHAR(63) DEFAULT 'default' NOT NULL, 
	CONSTRAINT experiment_pk PRIMARY KEY (experiment_id), 
	CONSTRAINT experiments_lifecycle_stage CHECK (lifecycle_stage IN ('active', 'deleted')), 
	CONSTRAINT uq_experiments_workspace_name UNIQUE (workspace, name)
);
CREATE INDEX idx_experiments_workspace ON experiments (workspace);
CREATE INDEX idx_experiments_workspace_creation_time ON experiments (workspace, creation_time);
CREATE TABLE "experiment_tags" (
	"key" VARCHAR(250) NOT NULL, 
	value TEXT, 
	experiment_id INTEGER NOT NULL, 
	CONSTRAINT experiment_tag_pk PRIMARY KEY ("key", experiment_id), 
	FOREIGN KEY(experiment_id) REFERENCES experiments (experiment_id)
);
CREATE TABLE "runs" (
	run_uuid VARCHAR(32) NOT NULL, 
	name VARCHAR(250), 
	source_type VARCHAR(20), 
	source_name VARCHAR(500), 
	entry_point_name VARCHAR(50), 
	user_id VARCHAR(256), 
	status VARCHAR(9), 
	start_time BIGINT, 
	end_time BIGINT, 
	source_version VARCHAR(50), 
	lifecycle_stage VARCHAR(20), 
	artifact_uri VARCHAR(200), 
	experiment_id INTEGER, deleted_time BIGINT, 
	CONSTRAINT run_pk PRIMARY KEY (run_uuid), 
	CONSTRAINT runs_lifecycle_stage CHECK (lifecycle_stage IN ('active', 'deleted')), 
	CONSTRAINT source_type CHECK (source_type IN ('NOTEBOOK', 'JOB', 'LOCAL', 'UNKNOWN', 'PROJECT')), 
	FOREIGN KEY(experiment_id) REFERENCES experiments (experiment_id), 
	CHECK (status IN ('SCHEDULED', 'FAILED', 'FINISHED', 'RUNNING', 'KILLED'))
);
CREATE TABLE "metrics" (
	"key" VARCHAR(250) NOT NULL, 
	value FLOAT NOT NULL, 
	timestamp BIGINT NOT NULL, 
	run_uuid VARCHAR(32) NOT NULL, 
	step BIGINT DEFAULT '0' NOT NULL, 
	is_nan BOOLEAN DEFAULT '0' NOT NULL, 
	CONSTRAINT metric_pk PRIMARY KEY ("key", timestamp, step, run_uuid, value, is_nan), 
	FOREIGN KEY(run_uuid) REFERENCES runs (run_uuid), 
	CHECK (is_nan IN (0, 1))
);
CREATE INDEX index_metrics_run_uuid ON metrics (run_uuid);
CREATE INDEX index_metrics_run_uuid_key_step ON metrics (run_uuid, "key", step);
CREATE TABLE "latest_metrics" (
	"key" VARCHAR(250) NOT NULL, 
	value FLOAT NOT NULL, 
	timestamp BIGINT, 
	step BIGINT NOT NULL, 
	is_nan BOOLEAN NOT NULL, 
	run_uuid VARCHAR(32) NOT NULL, 
	CONSTRAINT latest_metric_pk PRIMARY KEY ("key", run_uuid), 
	FOREIGN KEY(run_uuid) REFERENCES runs (run_uuid), 
	CHECK (is_nan IN (0, 1))
);
CREATE INDEX index_latest_metrics_run_uuid ON latest_metrics (run_uuid);
CREATE TABLE "params" (
	"key" VARCHAR(250) NOT NULL, 
	value VARCHAR(8000) NOT NULL, 
	run_uuid VARCHAR(32) NOT NULL, 
	CONSTRAINT param_pk PRIMARY KEY ("key", run_uuid), 
	FOREIGN KEY(run_uuid) REFERENCES runs (run_uuid)
);
CREATE INDEX index_params_run_uuid ON params (run_uuid);
CREATE TABLE "tags" (
	"key" VARCHAR(250) NOT NULL, 
	value VARCHAR(8000), 
	run_uuid VARCHAR(32) NOT NULL, 
	CONSTRAINT tag_pk PRIMARY KEY ("key", run_uuid), 
	FOREIGN KEY(run_uuid) REFERENCES runs (run_uuid)
);
CREATE INDEX index_tags_run_uuid ON tags (run_uuid);
CREATE TABLE "datasets" (
	dataset_uuid VARCHAR(36) NOT NULL, 
	experiment_id INTEGER NOT NULL, 
	name VARCHAR(500) NOT NULL, 
	digest VARCHAR(36) NOT NULL, 
	dataset_source_type VARCHAR(36) NOT NULL, 
	dataset_source TEXT NOT NULL, 
	dataset_schema TEXT, 
	dataset_profile TEXT, 
	CONSTRAINT dataset_pk PRIMARY KEY (experiment_id, name, digest), 
	CONSTRAINT fk_datasets_experiment_id_experiments FOREIGN KEY(experiment_id) REFERENCES experiments (experiment_id) ON DELETE CASCADE
);
CREATE INDEX index_datasets_experiment_id_dataset_source_type ON datasets (experiment_id, dataset_source_type);
CREATE INDEX index_datasets_dataset_uuid ON datasets (dataset_uuid);
CREATE TABLE inputs (
	input_uuid VARCHAR(36) NOT NULL, 
	source_type VARCHAR(36) NOT NULL, 
	source_id VARCHAR(36) NOT NULL, 
	destination_type VARCHAR(36) NOT NULL, 
	destination_id VARCHAR(36) NOT NULL, step BIGINT DEFAULT '0' NOT NULL, 
	CONSTRAINT inputs_pk PRIMARY KEY (source_type, source_id, destination_type, destination_id)
);
CREATE INDEX index_inputs_destination_type_destination_id_source_type ON inputs (destination_type, destination_id, source_type);
CREATE INDEX index_inputs_input_uuid ON inputs (input_uuid);
CREATE TABLE input_tags (
	input_uuid VARCHAR(36) NOT NULL, 
	name VARCHAR(255) NOT NULL, 
	value VARCHAR(500) NOT NULL, 
	CONSTRAINT input_tags_pk PRIMARY KEY (input_uuid, name)
);
CREATE TABLE "trace_info" (
	request_id VARCHAR(50) NOT NULL, 
	experiment_id INTEGER NOT NULL, 
	timestamp_ms BIGINT NOT NULL, 
	execution_time_ms BIGINT, 
	status VARCHAR(50) NOT NULL, 
	client_request_id VARCHAR(50), 
	request_preview VARCHAR(1000), 
	response_preview VARCHAR(1000), 
	db_payload_generation INTEGER DEFAULT '0' NOT NULL, trace_name VARCHAR(4096), session_id VARCHAR(250), input_tokens BIGINT, output_tokens BIGINT, total_tokens BIGINT, cache_read_input_tokens BIGINT, cache_creation_input_tokens BIGINT, cache_creation_input_tokens_above_1hr BIGINT, input_cost FLOAT, output_cost FLOAT, total_cost FLOAT, 
	CONSTRAINT trace_info_pk PRIMARY KEY (request_id), 
	CONSTRAINT fk_trace_info_experiment_id FOREIGN KEY(experiment_id) REFERENCES experiments (experiment_id) ON DELETE CASCADE
);
CREATE INDEX index_trace_info_experiment_id_timestamp_ms ON trace_info (experiment_id, timestamp_ms);
CREATE INDEX index_trace_info_timestamp_ms_request_id ON trace_info (timestamp_ms, request_id);
CREATE INDEX index_trace_info_experiment_id_session_id ON trace_info (experiment_id, session_id);
CREATE TABLE "trace_tags" (
	"key" VARCHAR(250) NOT NULL, 
	value VARCHAR(8000), 
	request_id VARCHAR(50) NOT NULL, 
	CONSTRAINT trace_tag_pk PRIMARY KEY ("key", request_id), 
	CONSTRAINT fk_trace_tags_request_id FOREIGN KEY(request_id) REFERENCES trace_info (request_id) ON DELETE CASCADE
);
CREATE INDEX index_trace_tags_request_id ON trace_tags (request_id);
CREATE TABLE "trace_request_metadata" (
	"key" VARCHAR(250) NOT NULL, 
	value VARCHAR(8000), 
	request_id VARCHAR(50) NOT NULL, 
	CONSTRAINT trace_request_metadata_pk PRIMARY KEY ("key", request_id), 
	CONSTRAINT fk_trace_request_metadata_request_id FOREIGN KEY(request_id) REFERENCES trace_info (request_id) ON DELETE CASCADE
);
CREATE INDEX index_trace_request_metadata_request_id ON trace_request_metadata (request_id);
CREATE TABLE "spans" (
	trace_id VARCHAR(50) NOT NULL, 
	experiment_id INTEGER NOT NULL, 
	span_id VARCHAR(50) NOT NULL, 
	parent_span_id VARCHAR(50), 
	name TEXT, 
	type VARCHAR(500), 
	status VARCHAR(50) NOT NULL, 
	start_time_unix_nano BIGINT NOT NULL, 
	end_time_unix_nano BIGINT, 
	duration_ns BIGINT GENERATED ALWAYS AS (end_time_unix_nano - start_time_unix_nano) STORED, 
	content TEXT NOT NULL, 
	input_cost FLOAT, 
	output_cost FLOAT, 
	total_cost FLOAT, 
	model_name VARCHAR(500), 
	model_provider VARCHAR(500), 
	CONSTRAINT spans_pk PRIMARY KEY (trace_id, span_id), 
	CONSTRAINT fk_spans_experiment_id FOREIGN KEY(experiment_id) REFERENCES experiments (experiment_id), 
	CONSTRAINT fk_spans_trace_id FOREIGN KEY(trace_id) REFERENCES trace_info (request_id) ON DELETE CASCADE
);
CREATE INDEX index_spans_experiment_id_status_type ON spans (experiment_id, status, type);
CREATE INDEX index_spans_experiment_id_type_status ON spans (experiment_id, type, status);
CREATE INDEX index_spans_experiment_id_start_time ON spans (experiment_id, start_time_unix_nano);
CREATE INDEX index_spans_experiment_id_duration ON spans (experiment_id, duration_ns);
CREATE INDEX idx_spans_cost_trace_time_cover ON spans (trace_id, start_time_unix_nano);
CREATE INDEX idx_spans_cost_exp_time_cover ON spans (experiment_id, start_time_unix_nano);
CREATE TABLE "assessments" (
	assessment_id VARCHAR(50) NOT NULL, 
	trace_id VARCHAR(50) NOT NULL, 
	name VARCHAR(250) NOT NULL, 
	assessment_type VARCHAR(20) NOT NULL, 
	value TEXT NOT NULL, 
	error TEXT, 
	created_timestamp BIGINT NOT NULL, 
	last_updated_timestamp BIGINT NOT NULL, 
	source_type VARCHAR(50) NOT NULL, 
	source_id VARCHAR(250), 
	run_id VARCHAR(32), 
	span_id VARCHAR(50), 
	rationale TEXT, 
	overrides VARCHAR(50), 
	valid BOOLEAN NOT NULL, 
	assessment_metadata TEXT, 
	experiment_id INTEGER, 
	trace_timestamp_ms BIGINT, 
	aggregate_value FLOAT, 
	is_numeric_value BOOLEAN DEFAULT 0 NOT NULL, 
	CONSTRAINT assessments_pk PRIMARY KEY (assessment_id), 
	CONSTRAINT fk_assessments_trace_id FOREIGN KEY(trace_id) REFERENCES trace_info (request_id) ON DELETE CASCADE
);
CREATE INDEX index_assessments_trace_id_created_timestamp ON assessments (trace_id, created_timestamp);
CREATE INDEX index_assessments_run_id_created_timestamp ON assessments (run_id, created_timestamp);
CREATE INDEX index_assessments_last_updated_timestamp ON assessments (last_updated_timestamp);
CREATE INDEX index_assessments_assessment_type ON assessments (assessment_type);
CREATE INDEX idx_assessments_exp_trace_ts ON assessments (experiment_id, trace_timestamp_ms);
CREATE INDEX idx_assessments_exp_trace_ts_name ON assessments (experiment_id, trace_timestamp_ms, name);
CREATE INDEX idx_assessments_exp_name_valid ON assessments (experiment_id, name, valid);
