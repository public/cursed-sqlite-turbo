-- Optuna RDBStorage schema (optuna/optuna @ 01ddd17 = v5.0.0, MIT): optuna/storages/_rdb/models.py created by
-- RDBStorage itself (SQLAlchemy metadata.create_all on SQLite) and dumped with .schema. Alembic head v3.2.0.a.
CREATE TABLE studies (
	study_id INTEGER NOT NULL, 
	study_name VARCHAR(512) NOT NULL, 
	PRIMARY KEY (study_id)
);
CREATE UNIQUE INDEX ix_studies_study_name ON studies (study_name);
CREATE TABLE version_info (
	version_info_id INTEGER NOT NULL, 
	schema_version INTEGER, 
	library_version VARCHAR(256), 
	PRIMARY KEY (version_info_id), 
	CHECK (version_info_id=1)
);
CREATE TABLE study_directions (
	study_direction_id INTEGER NOT NULL, 
	direction VARCHAR(8) NOT NULL, 
	study_id INTEGER NOT NULL, 
	objective INTEGER NOT NULL, 
	PRIMARY KEY (study_direction_id), 
	UNIQUE (study_id, objective), 
	FOREIGN KEY(study_id) REFERENCES studies (study_id)
);
CREATE TABLE study_user_attributes (
	study_user_attribute_id INTEGER NOT NULL, 
	study_id INTEGER, 
	"key" VARCHAR(512), 
	value_json TEXT, 
	PRIMARY KEY (study_user_attribute_id), 
	UNIQUE (study_id, "key"), 
	FOREIGN KEY(study_id) REFERENCES studies (study_id)
);
CREATE TABLE study_system_attributes (
	study_system_attribute_id INTEGER NOT NULL, 
	study_id INTEGER, 
	"key" VARCHAR(512), 
	value_json TEXT, 
	PRIMARY KEY (study_system_attribute_id), 
	UNIQUE (study_id, "key"), 
	FOREIGN KEY(study_id) REFERENCES studies (study_id)
);
CREATE TABLE trials (
	trial_id INTEGER NOT NULL, 
	number INTEGER, 
	study_id INTEGER, 
	state VARCHAR(8) NOT NULL, 
	datetime_start DATETIME, 
	datetime_complete DATETIME, 
	PRIMARY KEY (trial_id), 
	FOREIGN KEY(study_id) REFERENCES studies (study_id)
);
CREATE INDEX ix_trials_study_id ON trials (study_id);
CREATE TABLE trial_user_attributes (
	trial_user_attribute_id INTEGER NOT NULL, 
	trial_id INTEGER, 
	"key" VARCHAR(512), 
	value_json TEXT, 
	PRIMARY KEY (trial_user_attribute_id), 
	UNIQUE (trial_id, "key"), 
	FOREIGN KEY(trial_id) REFERENCES trials (trial_id)
);
CREATE TABLE trial_system_attributes (
	trial_system_attribute_id INTEGER NOT NULL, 
	trial_id INTEGER, 
	"key" VARCHAR(512), 
	value_json TEXT, 
	PRIMARY KEY (trial_system_attribute_id), 
	UNIQUE (trial_id, "key"), 
	FOREIGN KEY(trial_id) REFERENCES trials (trial_id)
);
CREATE TABLE trial_params (
	param_id INTEGER NOT NULL, 
	trial_id INTEGER, 
	param_name VARCHAR(512), 
	param_value FLOAT, 
	distribution_json TEXT, 
	PRIMARY KEY (param_id), 
	UNIQUE (trial_id, param_name), 
	FOREIGN KEY(trial_id) REFERENCES trials (trial_id)
);
CREATE TABLE trial_values (
	trial_value_id INTEGER NOT NULL, 
	trial_id INTEGER NOT NULL, 
	objective INTEGER NOT NULL, 
	value FLOAT, 
	value_type VARCHAR(7) NOT NULL, 
	PRIMARY KEY (trial_value_id), 
	UNIQUE (trial_id, objective), 
	FOREIGN KEY(trial_id) REFERENCES trials (trial_id)
);
CREATE TABLE trial_intermediate_values (
	trial_intermediate_value_id INTEGER NOT NULL, 
	trial_id INTEGER NOT NULL, 
	step INTEGER NOT NULL, 
	intermediate_value FLOAT, 
	intermediate_value_type VARCHAR(7) NOT NULL, 
	PRIMARY KEY (trial_intermediate_value_id), 
	UNIQUE (trial_id, step), 
	FOREIGN KEY(trial_id) REFERENCES trials (trial_id)
);
CREATE TABLE trial_heartbeats (
	trial_heartbeat_id INTEGER NOT NULL, 
	trial_id INTEGER NOT NULL, 
	heartbeat DATETIME NOT NULL, 
	PRIMARY KEY (trial_heartbeat_id), 
	UNIQUE (trial_id), 
	FOREIGN KEY(trial_id) REFERENCES trials (trial_id)
);
CREATE TABLE alembic_version (
	version_num VARCHAR(32) NOT NULL, 
	CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);
