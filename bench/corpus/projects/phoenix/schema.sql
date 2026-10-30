-- Arize Phoenix schema (Arize-ai/phoenix @ 6359d63 = arize-phoenix v21.0.0, Elastic License 2.0): the tables the
-- queries use, as Phoenix's own alembic migrations (src/phoenix/db/migrations, models in src/phoenix/db/models.py)
-- leave them on SQLite (phoenix serve against an empty file, dumped with .schema).
CREATE TABLE "projects" (
	id INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	description VARCHAR, 
	gradient_start_color VARCHAR DEFAULT '#5bdbff' NOT NULL, 
	gradient_end_color VARCHAR DEFAULT '#1c76fc' NOT NULL, 
	created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	updated_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	trace_retention_policy_id INTEGER, 
	CONSTRAINT pk_projects PRIMARY KEY (id), 
	CONSTRAINT uq_projects_name UNIQUE (name), 
	CONSTRAINT fk_projects_trace_retention_policy_id_project_trace_retention_policies FOREIGN KEY(trace_retention_policy_id) REFERENCES project_trace_retention_policies (id) ON DELETE SET NULL
);
CREATE INDEX ix_projects_trace_retention_policy_id ON projects (trace_retention_policy_id);
CREATE TABLE "traces" (
	id INTEGER NOT NULL, 
	project_rowid INTEGER NOT NULL, 
	trace_id VARCHAR NOT NULL, 
	start_time TIMESTAMP NOT NULL, 
	end_time TIMESTAMP NOT NULL, 
	project_session_rowid INTEGER, 
	CONSTRAINT pk_traces PRIMARY KEY (id), 
	CONSTRAINT fk_traces_project_rowid_projects FOREIGN KEY(project_rowid) REFERENCES projects (id) ON DELETE CASCADE, 
	CONSTRAINT uq_traces_trace_id UNIQUE (trace_id), 
	CONSTRAINT fk_traces_project_session_rowid_project_sessions FOREIGN KEY(project_session_rowid) REFERENCES project_sessions (id) ON DELETE CASCADE
);
CREATE INDEX ix_traces_project_session_rowid ON traces (project_session_rowid);
CREATE INDEX ix_traces_project_rowid_start_time ON traces (project_rowid, start_time DESC);
CREATE TABLE spans (
	id INTEGER NOT NULL, 
	trace_rowid INTEGER NOT NULL, 
	span_id VARCHAR NOT NULL, 
	parent_id VARCHAR, 
	name VARCHAR NOT NULL, 
	span_kind VARCHAR NOT NULL, 
	start_time TIMESTAMP NOT NULL, 
	end_time TIMESTAMP NOT NULL, 
	attributes JSONB NOT NULL, 
	events JSONB NOT NULL, 
	status_code VARCHAR DEFAULT 'UNSET' NOT NULL CONSTRAINT "ck_spans_`valid_status`" CHECK (status_code IN ('OK', 'ERROR', 'UNSET')), 
	status_message VARCHAR NOT NULL, 
	cumulative_error_count INTEGER NOT NULL, 
	cumulative_llm_token_count_prompt INTEGER NOT NULL, 
	cumulative_llm_token_count_completion INTEGER NOT NULL, llm_token_count_prompt INTEGER, llm_token_count_completion INTEGER, 
	CONSTRAINT pk_spans PRIMARY KEY (id), 
	CONSTRAINT fk_spans_trace_rowid_traces FOREIGN KEY(trace_rowid) REFERENCES traces (id) ON DELETE CASCADE, 
	CONSTRAINT uq_spans_span_id UNIQUE (span_id)
);
CREATE INDEX ix_spans_parent_id ON spans (parent_id);
CREATE INDEX ix_spans_start_time ON spans (start_time);
CREATE INDEX ix_spans_trace_rowid ON spans (trace_rowid);
CREATE INDEX ix_cumulative_llm_token_count_total ON spans ((cumulative_llm_token_count_prompt + cumulative_llm_token_count_completion));
CREATE INDEX ix_spans_session_id ON spans (CAST(JSON_EXTRACT(attributes, '$."session"."id"') AS VARCHAR)) WHERE CAST(JSON_EXTRACT(attributes, '$."session"."id"') AS VARCHAR) IS NOT NULL;
CREATE INDEX ix_spans_user_id ON spans (CAST(JSON_EXTRACT(attributes, '$."user"."id"') AS VARCHAR)) WHERE CAST(JSON_EXTRACT(attributes, '$."user"."id"') AS VARCHAR) IS NOT NULL;
CREATE TABLE project_sessions (
	id INTEGER NOT NULL, 
	session_id VARCHAR NOT NULL, 
	project_id INTEGER NOT NULL, 
	start_time TIMESTAMP NOT NULL, 
	end_time TIMESTAMP NOT NULL, 
	CONSTRAINT pk_project_sessions PRIMARY KEY (id), 
	CONSTRAINT uq_project_sessions_session_id UNIQUE (session_id), 
	CONSTRAINT fk_project_sessions_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id) ON DELETE CASCADE
);
CREATE INDEX ix_project_sessions_project_id_start_time ON project_sessions (project_id, start_time DESC);
CREATE INDEX ix_project_sessions_project_id_end_time ON project_sessions (project_id, end_time DESC);
CREATE TABLE span_costs (
	id INTEGER NOT NULL, 
	span_rowid INTEGER NOT NULL, 
	trace_rowid INTEGER NOT NULL, 
	model_id INTEGER, 
	span_start_time TIMESTAMP NOT NULL, 
	total_cost FLOAT, 
	total_tokens FLOAT, 
	prompt_cost FLOAT, 
	prompt_tokens FLOAT, 
	completion_cost FLOAT, 
	completion_tokens FLOAT, 
	CONSTRAINT pk_span_costs PRIMARY KEY (id), 
	CONSTRAINT fk_span_costs_span_rowid_spans FOREIGN KEY(span_rowid) REFERENCES spans (id) ON DELETE CASCADE, 
	CONSTRAINT fk_span_costs_trace_rowid_traces FOREIGN KEY(trace_rowid) REFERENCES traces (id) ON DELETE CASCADE, 
	CONSTRAINT fk_span_costs_model_id_generative_models FOREIGN KEY(model_id) REFERENCES generative_models (id) ON DELETE RESTRICT
);
CREATE INDEX ix_span_costs_span_rowid ON span_costs (span_rowid);
CREATE INDEX ix_span_costs_span_start_time ON span_costs (span_start_time);
CREATE INDEX ix_span_costs_trace_rowid ON span_costs (trace_rowid);
CREATE INDEX ix_span_costs_model_id_span_start_time ON span_costs (model_id, span_start_time);
CREATE TABLE span_cost_details (
	id INTEGER NOT NULL, 
	span_cost_id INTEGER NOT NULL, 
	token_type VARCHAR NOT NULL, 
	is_prompt BOOLEAN NOT NULL, 
	cost FLOAT, 
	tokens FLOAT, 
	cost_per_token FLOAT, 
	CONSTRAINT pk_span_cost_details PRIMARY KEY (id), 
	CONSTRAINT uq_span_cost_details_span_cost_id_token_type_is_prompt UNIQUE (span_cost_id, token_type, is_prompt), 
	CONSTRAINT fk_span_cost_details_span_cost_id_span_costs FOREIGN KEY(span_cost_id) REFERENCES span_costs (id) ON DELETE CASCADE
);
CREATE INDEX ix_span_cost_details_token_type ON span_cost_details (token_type);
CREATE TABLE "span_annotations" (
	id INTEGER NOT NULL, 
	span_rowid INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	label VARCHAR, 
	score FLOAT, 
	explanation VARCHAR, 
	metadata JSONB NOT NULL, 
	annotator_kind VARCHAR NOT NULL, 
	created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	updated_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	user_id INTEGER, 
	identifier VARCHAR DEFAULT ('') NOT NULL, 
	source VARCHAR NOT NULL, 
	CONSTRAINT pk_span_annotations PRIMARY KEY (id), 
	CONSTRAINT uq_span_annotations_name_span_rowid_identifier UNIQUE (name, span_rowid, identifier), 
	CONSTRAINT fk_span_annotations_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_span_annotations_span_rowid_spans FOREIGN KEY(span_rowid) REFERENCES spans (id) ON DELETE CASCADE, 
	CONSTRAINT "ck_span_annotations_`valid_source`" CHECK (source IN ('API', 'APP'))
, CONSTRAINT "ck_span_annotations_`valid_annotator_kind`" CHECK (annotator_kind IN ('LLM', 'CODE', 'HUMAN', 'DECISION', 'AGENT')));
CREATE INDEX ix_span_annotations_span_rowid ON span_annotations (span_rowid);
CREATE INDEX ix_span_annotations_user_id ON span_annotations (user_id);
CREATE TABLE "trace_annotations" (
	id INTEGER NOT NULL, 
	trace_rowid INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	label VARCHAR, 
	score FLOAT, 
	explanation VARCHAR, 
	metadata JSONB NOT NULL, 
	annotator_kind VARCHAR NOT NULL, 
	created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	updated_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	user_id INTEGER, 
	identifier VARCHAR DEFAULT ('') NOT NULL, 
	source VARCHAR NOT NULL, 
	CONSTRAINT pk_trace_annotations PRIMARY KEY (id), 
	CONSTRAINT fk_trace_annotations_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT uq_trace_annotations_name_trace_rowid_identifier UNIQUE (name, trace_rowid, identifier), 
	CONSTRAINT fk_trace_annotations_trace_rowid_traces FOREIGN KEY(trace_rowid) REFERENCES traces (id) ON DELETE CASCADE, 
	CONSTRAINT "ck_trace_annotations_`valid_source`" CHECK (source IN ('API', 'APP'))
, CONSTRAINT "ck_trace_annotations_`valid_annotator_kind`" CHECK (annotator_kind IN ('LLM', 'CODE', 'HUMAN', 'DECISION', 'AGENT')));
CREATE INDEX ix_trace_annotations_trace_rowid ON trace_annotations (trace_rowid);
CREATE INDEX ix_trace_annotations_user_id ON trace_annotations (user_id);
CREATE TABLE "document_annotations" (
	id INTEGER NOT NULL, 
	span_rowid INTEGER NOT NULL, 
	document_position INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	label VARCHAR, 
	score FLOAT, 
	explanation VARCHAR, 
	metadata JSONB NOT NULL, 
	annotator_kind VARCHAR NOT NULL, 
	created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	updated_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	user_id INTEGER, 
	identifier VARCHAR DEFAULT ('') NOT NULL, 
	source VARCHAR NOT NULL, 
	CONSTRAINT pk_document_annotations PRIMARY KEY (id), 
	CONSTRAINT uq_document_annotations_name_span_rowid_document_pos_identifier UNIQUE (name, span_rowid, document_position, identifier), 
	CONSTRAINT fk_document_annotations_span_rowid_spans FOREIGN KEY(span_rowid) REFERENCES spans (id) ON DELETE CASCADE, 
	CONSTRAINT fk_document_annotations_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT "ck_document_annotations_`valid_source`" CHECK (source IN ('API', 'APP'))
, CONSTRAINT "ck_document_annotations_`valid_annotator_kind`" CHECK (annotator_kind IN ('LLM', 'CODE', 'HUMAN', 'DECISION', 'AGENT')));
CREATE INDEX ix_document_annotations_span_rowid ON document_annotations (span_rowid);
CREATE INDEX ix_document_annotations_user_id ON document_annotations (user_id);
CREATE TABLE project_session_annotations (
	id INTEGER NOT NULL, 
	project_session_id INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	label VARCHAR, 
	score FLOAT, 
	explanation VARCHAR, 
	metadata JSONB NOT NULL, 
	annotator_kind VARCHAR NOT NULL, 
	user_id INTEGER, 
	identifier VARCHAR DEFAULT '' NOT NULL, 
	source VARCHAR NOT NULL CONSTRAINT "ck_project_session_annotations_`valid_source`" CHECK (source IN ('API', 'APP')), 
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, 
	updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, 
	CONSTRAINT pk_project_session_annotations PRIMARY KEY (id), 
	CONSTRAINT uq_project_session_annotations_name_project_session_id_identifier UNIQUE (name, project_session_id, identifier), 
	CONSTRAINT fk_project_session_annotations_project_session_id_project_sessions FOREIGN KEY(project_session_id) REFERENCES project_sessions (id) ON DELETE CASCADE, 
	CONSTRAINT fk_project_session_annotations_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL
, CONSTRAINT "ck_project_session_annotations_`valid_annotator_kind`" CHECK (annotator_kind IN ('LLM', 'CODE', 'HUMAN', 'DECISION', 'AGENT')));
CREATE INDEX ix_project_session_annotations_project_session_id ON project_session_annotations (project_session_id);
CREATE INDEX ix_project_session_annotations_user_id ON project_session_annotations (user_id);
CREATE TABLE generative_models (
	id INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	provider VARCHAR NOT NULL, 
	name_pattern VARCHAR NOT NULL, 
	is_built_in BOOLEAN NOT NULL, 
	start_time TIMESTAMP, 
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, 
	updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, 
	deleted_at TIMESTAMP, 
	CONSTRAINT pk_generative_models PRIMARY KEY (id)
);
CREATE UNIQUE INDEX ix_generative_models_match_criteria ON generative_models (name_pattern, provider, is_built_in) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX ix_generative_models_name_is_built_in ON generative_models (name, is_built_in) WHERE deleted_at IS NULL;
CREATE INDEX ix_generative_models_updated_at ON generative_models (updated_at);
CREATE TABLE annotation_configs (
	id INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	config JSONB NOT NULL, 
	CONSTRAINT pk_annotation_configs PRIMARY KEY (id), 
	CONSTRAINT uq_annotation_configs_name UNIQUE (name)
);
CREATE TABLE project_annotation_configs (
	id INTEGER NOT NULL, 
	project_id INTEGER NOT NULL, 
	annotation_config_id INTEGER NOT NULL, 
	CONSTRAINT pk_project_annotation_configs PRIMARY KEY (id), 
	CONSTRAINT uq_project_annotation_configs_project_id_annotation_config_id UNIQUE (project_id, annotation_config_id), 
	CONSTRAINT fk_project_annotation_configs_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id) ON DELETE CASCADE, 
	CONSTRAINT fk_project_annotation_configs_annotation_config_id_annotation_configs FOREIGN KEY(annotation_config_id) REFERENCES annotation_configs (id) ON DELETE CASCADE
);
CREATE INDEX ix_project_annotation_configs_annotation_config_id ON project_annotation_configs (annotation_config_id);
CREATE TABLE "datasets" (
	id INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	description VARCHAR, 
	metadata JSONB NOT NULL, 
	created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	updated_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	user_id INTEGER, 
	CONSTRAINT pk_datasets PRIMARY KEY (id), 
	CONSTRAINT uq_datasets_name UNIQUE (name), 
	CONSTRAINT fk_datasets_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL
);
CREATE INDEX ix_datasets_user_id ON datasets (user_id);
CREATE TABLE "dataset_versions" (
	id INTEGER NOT NULL, 
	dataset_id INTEGER NOT NULL, 
	description VARCHAR, 
	metadata JSONB NOT NULL, 
	created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	user_id INTEGER, 
	CONSTRAINT pk_dataset_versions PRIMARY KEY (id), 
	CONSTRAINT fk_dataset_versions_dataset_id_datasets FOREIGN KEY(dataset_id) REFERENCES datasets (id) ON DELETE CASCADE, 
	CONSTRAINT fk_dataset_versions_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL
);
CREATE INDEX ix_dataset_versions_dataset_id ON dataset_versions (dataset_id);
CREATE INDEX ix_dataset_versions_user_id ON dataset_versions (user_id);
CREATE TABLE "dataset_examples" (
	id INTEGER NOT NULL, 
	dataset_id INTEGER NOT NULL, 
	span_rowid INTEGER, 
	created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	external_id VARCHAR, 
	CONSTRAINT pk_dataset_examples PRIMARY KEY (id), 
	CONSTRAINT fk_dataset_examples_span_rowid_spans FOREIGN KEY(span_rowid) REFERENCES spans (id) ON DELETE SET NULL, 
	CONSTRAINT fk_dataset_examples_dataset_id_datasets FOREIGN KEY(dataset_id) REFERENCES datasets (id) ON DELETE CASCADE, 
	CONSTRAINT uq_dataset_examples_dataset_id_external_id UNIQUE (dataset_id, external_id)
);
CREATE INDEX ix_dataset_examples_span_rowid ON dataset_examples (span_rowid);
CREATE TABLE dataset_example_revisions (
	id INTEGER NOT NULL, 
	dataset_example_id INTEGER NOT NULL, 
	dataset_version_id INTEGER NOT NULL, 
	input JSONB NOT NULL, 
	output JSONB NOT NULL, 
	metadata JSONB NOT NULL, 
	revision_kind VARCHAR NOT NULL CONSTRAINT "ck_dataset_example_revisions_`valid_revision_kind`" CHECK (revision_kind IN ('CREATE', 'PATCH', 'DELETE')), 
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, content_hash BLOB, 
	CONSTRAINT pk_dataset_example_revisions PRIMARY KEY (id), 
	CONSTRAINT uq_dataset_example_revisions_dataset_example_id_dataset_version_id UNIQUE (dataset_example_id, dataset_version_id), 
	CONSTRAINT fk_dataset_example_revisions_dataset_example_id_dataset_examples FOREIGN KEY(dataset_example_id) REFERENCES dataset_examples (id) ON DELETE CASCADE, 
	CONSTRAINT fk_dataset_example_revisions_dataset_version_id_dataset_versions FOREIGN KEY(dataset_version_id) REFERENCES dataset_versions (id) ON DELETE CASCADE
);
CREATE INDEX ix_dataset_example_revisions_dataset_version_id ON dataset_example_revisions (dataset_version_id);
CREATE INDEX ix_dataset_example_revisions_content_hash ON dataset_example_revisions (content_hash);
CREATE TABLE dataset_splits (
	id INTEGER NOT NULL, 
	user_id INTEGER, 
	name VARCHAR NOT NULL, 
	description VARCHAR, 
	color VARCHAR NOT NULL, 
	metadata JSONB NOT NULL, 
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, 
	updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, 
	CONSTRAINT pk_dataset_splits PRIMARY KEY (id), 
	CONSTRAINT fk_dataset_splits_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT uq_dataset_splits_name UNIQUE (name)
);
CREATE INDEX ix_dataset_splits_user_id ON dataset_splits (user_id);
CREATE TABLE dataset_splits_dataset_examples (
	dataset_split_id INTEGER NOT NULL, 
	dataset_example_id INTEGER NOT NULL, 
	CONSTRAINT pk_dataset_splits_dataset_examples PRIMARY KEY (dataset_split_id, dataset_example_id), 
	CONSTRAINT fk_dataset_splits_dataset_examples_dataset_split_id_dataset_splits FOREIGN KEY(dataset_split_id) REFERENCES dataset_splits (id) ON DELETE CASCADE, 
	CONSTRAINT fk_dataset_splits_dataset_examples_dataset_example_id_dataset_examples FOREIGN KEY(dataset_example_id) REFERENCES dataset_examples (id) ON DELETE CASCADE
);
CREATE INDEX ix_dataset_splits_dataset_examples_dataset_example_id ON dataset_splits_dataset_examples (dataset_example_id);
CREATE TABLE dataset_labels (
	id INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	description VARCHAR, 
	color VARCHAR NOT NULL, 
	user_id INTEGER, 
	CONSTRAINT pk_dataset_labels PRIMARY KEY (id), 
	CONSTRAINT uq_dataset_labels_name UNIQUE (name), 
	CONSTRAINT fk_dataset_labels_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL
);
CREATE INDEX ix_dataset_labels_user_id ON dataset_labels (user_id);
CREATE TABLE datasets_dataset_labels (
	dataset_id INTEGER NOT NULL, 
	dataset_label_id INTEGER NOT NULL, 
	CONSTRAINT pk_datasets_dataset_labels PRIMARY KEY (dataset_id, dataset_label_id), 
	CONSTRAINT fk_datasets_dataset_labels_dataset_id_datasets FOREIGN KEY(dataset_id) REFERENCES datasets (id) ON DELETE CASCADE, 
	CONSTRAINT fk_datasets_dataset_labels_dataset_label_id_dataset_labels FOREIGN KEY(dataset_label_id) REFERENCES dataset_labels (id) ON DELETE CASCADE
);
CREATE INDEX ix_datasets_dataset_labels_dataset_label_id ON datasets_dataset_labels (dataset_label_id);
CREATE TABLE "experiments" (
	id INTEGER NOT NULL, 
	dataset_id INTEGER NOT NULL, 
	dataset_version_id INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	description VARCHAR, 
	repetitions INTEGER NOT NULL, 
	metadata JSONB NOT NULL, 
	project_name VARCHAR, 
	created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	updated_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	user_id INTEGER, 
	is_ephemeral BOOLEAN DEFAULT 0 NOT NULL, 
	CONSTRAINT pk_experiments PRIMARY KEY (id), 
	CONSTRAINT fk_experiments_dataset_version_id_dataset_versions FOREIGN KEY(dataset_version_id) REFERENCES dataset_versions (id) ON DELETE CASCADE, 
	CONSTRAINT fk_experiments_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_experiments_dataset_id_datasets FOREIGN KEY(dataset_id) REFERENCES datasets (id) ON DELETE CASCADE
);
CREATE INDEX ix_experiments_dataset_version_id ON experiments (dataset_version_id);
CREATE INDEX ix_experiments_project_name ON experiments (project_name);
CREATE INDEX ix_experiments_dataset_id ON experiments (dataset_id);
CREATE INDEX ix_experiments_ephemeral_updated_at ON experiments (updated_at) WHERE is_ephemeral IS TRUE;
CREATE INDEX ix_experiments_user_id ON experiments (user_id);
CREATE TABLE experiments_dataset_examples (
	experiment_id INTEGER NOT NULL, 
	dataset_example_id INTEGER NOT NULL, 
	dataset_example_revision_id INTEGER NOT NULL, 
	CONSTRAINT pk_experiments_dataset_examples PRIMARY KEY (experiment_id, dataset_example_id), 
	CONSTRAINT fk_experiments_dataset_examples_experiment_id_experiments FOREIGN KEY(experiment_id) REFERENCES experiments (id) ON DELETE CASCADE, 
	CONSTRAINT fk_experiments_dataset_examples_dataset_example_id_dataset_examples FOREIGN KEY(dataset_example_id) REFERENCES dataset_examples (id) ON DELETE CASCADE, 
	CONSTRAINT fk_experiments_dataset_examples_dataset_example_revision_id_dataset_example_revisions FOREIGN KEY(dataset_example_revision_id) REFERENCES dataset_example_revisions (id) ON DELETE CASCADE
);
CREATE INDEX ix_experiments_dataset_examples_dataset_example_revision_id ON experiments_dataset_examples (dataset_example_revision_id);
CREATE INDEX ix_experiments_dataset_examples_dataset_example_id ON experiments_dataset_examples (dataset_example_id);
CREATE TABLE experiments_dataset_splits (
	experiment_id INTEGER NOT NULL, 
	dataset_split_id INTEGER NOT NULL, 
	CONSTRAINT pk_experiments_dataset_splits PRIMARY KEY (experiment_id, dataset_split_id), 
	CONSTRAINT fk_experiments_dataset_splits_experiment_id_experiments FOREIGN KEY(experiment_id) REFERENCES experiments (id) ON DELETE CASCADE, 
	CONSTRAINT fk_experiments_dataset_splits_dataset_split_id_dataset_splits FOREIGN KEY(dataset_split_id) REFERENCES dataset_splits (id) ON DELETE CASCADE
);
CREATE INDEX ix_experiments_dataset_splits_dataset_split_id ON experiments_dataset_splits (dataset_split_id);
CREATE TABLE experiment_runs (
	id INTEGER NOT NULL, 
	experiment_id INTEGER NOT NULL, 
	dataset_example_id INTEGER NOT NULL, 
	repetition_number INTEGER NOT NULL, 
	trace_id VARCHAR, 
	output JSONB NOT NULL, 
	start_time TIMESTAMP NOT NULL, 
	end_time TIMESTAMP NOT NULL, 
	prompt_token_count INTEGER, 
	completion_token_count INTEGER, 
	error VARCHAR, 
	CONSTRAINT pk_experiment_runs PRIMARY KEY (id), 
	CONSTRAINT uq_experiment_runs_experiment_id_dataset_example_id_repetition_number UNIQUE (experiment_id, dataset_example_id, repetition_number), 
	CONSTRAINT fk_experiment_runs_experiment_id_experiments FOREIGN KEY(experiment_id) REFERENCES experiments (id) ON DELETE CASCADE, 
	CONSTRAINT fk_experiment_runs_dataset_example_id_dataset_examples FOREIGN KEY(dataset_example_id) REFERENCES dataset_examples (id) ON DELETE CASCADE
);
CREATE INDEX ix_experiment_runs_dataset_example_id ON experiment_runs (dataset_example_id);
CREATE TABLE experiment_run_annotations (
	id INTEGER NOT NULL, 
	experiment_run_id INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	annotator_kind VARCHAR NOT NULL, 
	label VARCHAR, 
	score FLOAT, 
	explanation VARCHAR, 
	trace_id VARCHAR, 
	error VARCHAR, 
	metadata JSONB NOT NULL, 
	start_time TIMESTAMP NOT NULL, 
	end_time TIMESTAMP NOT NULL, 
	CONSTRAINT pk_experiment_run_annotations PRIMARY KEY (id), 
	CONSTRAINT uq_experiment_run_annotations_experiment_run_id_name UNIQUE (experiment_run_id, name), 
	CONSTRAINT fk_experiment_run_annotations_experiment_run_id_experiment_runs FOREIGN KEY(experiment_run_id) REFERENCES experiment_runs (id) ON DELETE CASCADE
, CONSTRAINT "ck_experiment_run_annotations_`valid_annotator_kind`" CHECK (annotator_kind IN ('LLM', 'CODE', 'HUMAN', 'DECISION', 'AGENT')));
CREATE TABLE experiment_tags (
	id INTEGER NOT NULL, 
	experiment_id INTEGER NOT NULL, 
	dataset_id INTEGER NOT NULL, 
	user_id INTEGER, 
	name VARCHAR NOT NULL, 
	description VARCHAR, 
	CONSTRAINT pk_experiment_tags PRIMARY KEY (id), 
	CONSTRAINT uq_experiment_tags_dataset_id_name UNIQUE (dataset_id, name), 
	CONSTRAINT fk_experiment_tags_experiment_id_experiments FOREIGN KEY(experiment_id) REFERENCES experiments (id) ON DELETE CASCADE, 
	CONSTRAINT fk_experiment_tags_dataset_id_datasets FOREIGN KEY(dataset_id) REFERENCES datasets (id) ON DELETE CASCADE, 
	CONSTRAINT fk_experiment_tags_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL
);
CREATE INDEX ix_experiment_tags_experiment_id ON experiment_tags (experiment_id);
CREATE INDEX ix_experiment_tags_user_id ON experiment_tags (user_id);
CREATE TABLE dataset_evaluators (
	id INTEGER NOT NULL, 
	dataset_id INTEGER NOT NULL, 
	evaluator_id INTEGER NOT NULL, 
	name VARCHAR NOT NULL, 
	description VARCHAR, 
	output_configs JSONB NOT NULL, 
	input_mapping JSONB NOT NULL, 
	user_id INTEGER, 
	project_id INTEGER NOT NULL, 
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, 
	updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, 
	CONSTRAINT pk_dataset_evaluators PRIMARY KEY (id), 
	CONSTRAINT uq_dataset_evaluators_dataset_id_name UNIQUE (dataset_id, name), 
	CONSTRAINT fk_dataset_evaluators_dataset_id_datasets FOREIGN KEY(dataset_id) REFERENCES datasets (id) ON DELETE CASCADE, 
	CONSTRAINT fk_dataset_evaluators_evaluator_id_evaluators FOREIGN KEY(evaluator_id) REFERENCES evaluators (id) ON DELETE CASCADE, 
	CONSTRAINT fk_dataset_evaluators_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL, 
	CONSTRAINT fk_dataset_evaluators_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id) ON DELETE RESTRICT
);
CREATE INDEX ix_dataset_evaluators_project_id ON dataset_evaluators (project_id);
CREATE INDEX ix_dataset_evaluators_evaluator_id ON dataset_evaluators (evaluator_id);
CREATE INDEX ix_dataset_evaluators_user_id ON dataset_evaluators (user_id);
CREATE TABLE "users" (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, 
	user_role_id INTEGER NOT NULL, 
	username VARCHAR NOT NULL, 
	email VARCHAR, 
	profile_picture_url VARCHAR, 
	password_hash BLOB, 
	password_salt BLOB, 
	reset_password BOOLEAN NOT NULL, 
	oauth2_client_id VARCHAR, 
	oauth2_user_id VARCHAR, 
	created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	updated_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP) NOT NULL, 
	auth_method VARCHAR NOT NULL, 
	ldap_unique_id VARCHAR, 
	CONSTRAINT fk_users_user_role_id_user_roles FOREIGN KEY(user_role_id) REFERENCES user_roles (id) ON DELETE CASCADE, 
	CONSTRAINT "ck_users_`valid_auth_method`" CHECK (auth_method IN ('LOCAL', 'OAUTH2', 'LDAP')), 
	CONSTRAINT "ck_users_`local_auth_has_password_no_oauth`" CHECK (auth_method != 'LOCAL' OR (password_hash IS NOT NULL AND password_salt IS NOT NULL AND oauth2_client_id IS NULL AND oauth2_user_id IS NULL AND ldap_unique_id IS NULL)), 
	CONSTRAINT "ck_users_`ldap_auth_valid`" CHECK (auth_method != 'LDAP' OR (oauth2_client_id IS NULL AND oauth2_user_id IS NULL AND (email IS NOT NULL OR ldap_unique_id IS NOT NULL))), 
	CONSTRAINT "ck_users_`oauth2_auth_no_ldap_fields`" CHECK (auth_method != 'OAUTH2' OR ldap_unique_id IS NULL), 
	CONSTRAINT "ck_users_`non_local_auth_has_no_password`" CHECK (auth_method = 'LOCAL' OR (password_hash IS NULL AND password_salt IS NULL)), 
	CONSTRAINT "ck_users_`non_ldap_auth_has_email`" CHECK (auth_method = 'LDAP' OR email IS NOT NULL)
);
CREATE INDEX ix_users_user_role_id ON users (user_role_id);
CREATE UNIQUE INDEX ix_users_username ON users (username);
CREATE UNIQUE INDEX ix_users_email ON users (email);
CREATE UNIQUE INDEX ix_users_oauth2_unique ON users (oauth2_client_id, oauth2_user_id) WHERE auth_method = 'OAUTH2';
CREATE UNIQUE INDEX ix_users_ldap_unique_id ON users (ldap_unique_id) WHERE auth_method = 'LDAP' AND ldap_unique_id IS NOT NULL;
