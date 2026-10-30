-- louislam/uptime-kuma @ 6da8aa12b128f519f1de72920aaf1d8b9e01987b (MIT).
-- Uptime Kuma's SQLite path (server/database.js) copies the template db/kuma.db, applies db/old_migrations/patch1-10.sql
-- and the patchList files, then runs the knex migrations in db/knex_migrations. Part 1 is the CREATE statements dumped
-- from db/kuma.db after the SQL patches; part 2 translates the knex migrations that touch these tables (column
-- additions/renames, the stat_* tables, the partial heartbeat indexes) into SQLite DDL.

-- == part 1: db/kuma.db + db/old_migrations
CREATE TABLE [user](
  [id] INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, 
  [username] VARCHAR(255) NOT NULL UNIQUE, 
  [password] VARCHAR(255), 
  [active] BOOLEAN NOT NULL DEFAULT 1, 
  [timezone] VARCHAR(150), twofa_secret VARCHAR(64), twofa_status BOOLEAN default 0 NOT NULL, twofa_last_token VARCHAR(6));
CREATE TABLE tag (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
	name VARCHAR(255) NOT NULL,
    color VARCHAR(255) NOT NULL,
	created_date DATETIME DEFAULT (DATETIME('now')) NOT NULL
);
CREATE TABLE "monitor" (
	id INTEGER not null primary key autoincrement,
	name VARCHAR(150),
	active BOOLEAN default 1 not null,
	user_id INTEGER references user on update cascade on delete
	set
		null,
		interval INTEGER default 20 not null,
		url TEXT,
		type VARCHAR(20),
		weight INTEGER default 2000,
		hostname VARCHAR(255),
		port INTEGER,
		created_date DATETIME default (DATETIME('now')) not null,
		keyword VARCHAR(255),
		maxretries INTEGER NOT NULL DEFAULT 0,
		ignore_tls BOOLEAN default 0 not null,
		upside_down BOOLEAN default 0 not null,
        maxredirects INTEGER default 10 not null,
        accepted_statuscodes_json TEXT default '["200-299"]' not null
, dns_resolve_type VARCHAR(5), dns_resolve_server VARCHAR(255), dns_last_result VARCHAR(255), retry_interval INTEGER default 0 not null, push_token VARCHAR(20) DEFAULT NULL, method TEXT default 'GET' not null, body TEXT default null, headers TEXT default null, basic_auth_user TEXT default null, basic_auth_pass TEXT default null, docker_host INTEGER REFERENCES docker_host(id), docker_container VARCHAR(255), proxy_id INTEGER REFERENCES proxy(id), expiry_notification BOOLEAN default 1, mqtt_topic TEXT, mqtt_success_message VARCHAR(255), mqtt_username VARCHAR(255), mqtt_password VARCHAR(255), database_connection_string VARCHAR(2000), database_query TEXT, auth_method VARCHAR(250), auth_domain TEXT, auth_workstation TEXT, grpc_url VARCHAR(255) default null, grpc_protobuf TEXT default null, grpc_body TEXT default null, grpc_metadata TEXT default null, grpc_method VARCHAR(255) default null, grpc_service_name VARCHAR(255) default null, grpc_enable_tls BOOLEAN default 0 not null, radius_username VARCHAR(255), radius_password VARCHAR(255), radius_calling_station_id VARCHAR(50), radius_called_station_id VARCHAR(50), radius_secret VARCHAR(255), resend_interval INTEGER default 0 not null, packet_size INTEGER DEFAULT 56 NOT NULL, game VARCHAR(255), http_body_encoding VARCHAR(25), description TEXT default null, tls_ca TEXT default null, tls_cert TEXT default null, tls_key TEXT default null, parent INTEGER REFERENCES [monitor] ([id]) ON DELETE SET NULL ON UPDATE CASCADE, invert_keyword BOOLEAN default 0 not null, json_path TEXT, expected_value VARCHAR(255), kafka_producer_topic VARCHAR(255), kafka_producer_brokers TEXT, kafka_producer_sasl_options TEXT, kafka_producer_message TEXT, oauth_client_id TEXT default null, oauth_client_secret TEXT default null, oauth_token_url TEXT default null, oauth_scopes TEXT default null, oauth_auth_method TEXT default null, timeout DOUBLE default 0 not null, gamedig_given_port_only BOOLEAN default 1 not null, kafka_producer_ssl BOOLEAN default 0 NOT NULL, kafka_producer_allow_auto_topic_creation BOOLEAN default 0 NOT NULL);
CREATE INDEX proxy_id ON monitor (proxy_id);
CREATE INDEX user_id on monitor (user_id);
CREATE TABLE monitor_tag (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
	monitor_id INTEGER NOT NULL,
	tag_id INTEGER NOT NULL,
	value TEXT,
	CONSTRAINT FK_tag FOREIGN KEY (tag_id) REFERENCES tag(id) ON DELETE CASCADE ON UPDATE CASCADE,
	CONSTRAINT FK_monitor FOREIGN KEY (monitor_id) REFERENCES monitor(id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX monitor_tag_monitor_id_index ON monitor_tag (monitor_id);
CREATE INDEX monitor_tag_tag_id_index ON monitor_tag (tag_id);
CREATE TABLE [notification](
  [id] INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, 
  [name] VARCHAR(255), 
  [active] BOOLEAN NOT NULL DEFAULT 1, 
  [user_id] INTEGER NOT NULL, is_default BOOLEAN default 0 NOT NULL, config TEXT);
CREATE TABLE [monitor_notification](
  [id] INTEGER PRIMARY KEY NOT NULL, 
  [monitor_id] INTEGER NOT NULL REFERENCES [monitor]([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
  [notification_id] INTEGER NOT NULL REFERENCES [notification]([id]) ON DELETE CASCADE ON UPDATE CASCADE);
CREATE INDEX [monitor_notification_index]
ON [monitor_notification](
  [monitor_id], 
  [notification_id]);
CREATE TABLE [heartbeat](
  [id] INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, 
  [important] BOOLEAN NOT NULL DEFAULT 0, 
  [monitor_id] INTEGER NOT NULL REFERENCES [monitor]([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
  [status] SMALLINT NOT NULL, 
  [msg] TEXT, 
  [time] DATETIME NOT NULL, 
  [ping] INTEGER, 
  [duration] INTEGER NOT NULL DEFAULT 0, down_count INTEGER default 0 not null);
CREATE INDEX [important] ON [heartbeat]([important]);
CREATE INDEX [monitor_id] ON [heartbeat]([monitor_id]);
CREATE INDEX monitor_important_time_index ON heartbeat (monitor_id, important,time);
CREATE INDEX monitor_time_index ON heartbeat (monitor_id, time);
CREATE TABLE [status_page](
    [id] INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    [slug] VARCHAR(255) NOT NULL UNIQUE,
    [title] VARCHAR(255) NOT NULL,
    [description] TEXT,
    [icon] VARCHAR(255) NOT NULL,
    [theme] VARCHAR(30) NOT NULL,
    [published] BOOLEAN NOT NULL DEFAULT 1,
    [search_engine_index] BOOLEAN NOT NULL DEFAULT 1,
    [show_tags] BOOLEAN NOT NULL DEFAULT 0,
    [password] VARCHAR,
    [created_date] DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    [modified_date] DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
, footer_text TEXT, custom_css TEXT, show_powered_by BOOLEAN NOT NULL DEFAULT 1, google_analytics_tag_id VARCHAR, show_certificate_expiry BOOLEAN default 0 NOT NULL);
CREATE UNIQUE INDEX [slug] ON [status_page]([slug]);
CREATE TABLE `group`
(
    id           INTEGER      not null
        constraint group_pk
            primary key autoincrement,
    name         VARCHAR(255) not null,
    created_date DATETIME              default (DATETIME('now')) not null,
    public       BOOLEAN               default 0 not null,
    active       BOOLEAN               default 1 not null,
    weight       BOOLEAN      NOT NULL DEFAULT 1000
, status_page_id INTEGER);
CREATE TABLE [monitor_group]
(
    [id]         INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    [monitor_id] INTEGER                           NOT NULL REFERENCES [monitor] ([id]) ON DELETE CASCADE ON UPDATE CASCADE,
    [group_id]   INTEGER                           NOT NULL REFERENCES [group] ([id]) ON DELETE CASCADE ON UPDATE CASCADE,
    weight BOOLEAN NOT NULL DEFAULT 1000
, send_url BOOLEAN DEFAULT 0 NOT NULL);
CREATE INDEX [fk]
    ON [monitor_group] (
                        [monitor_id],
                        [group_id]);
CREATE TABLE incident
(
    id INTEGER not null
        constraint incident_pk
            primary key autoincrement,
    title VARCHAR(255) not null,
    content TEXT not null,
    style VARCHAR(30) default 'warning' not null,
    created_date DATETIME default (DATETIME('now')) not null,
    last_updated_date DATETIME,
    pin BOOLEAN default 1 not null,
    active BOOLEAN default 1 not null
, status_page_id INTEGER);
CREATE TABLE [maintenance] (
    [id] INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    [title] VARCHAR(150) NOT NULL,
    [description] TEXT NOT NULL,
    [user_id] INTEGER REFERENCES [user]([id]) ON DELETE SET NULL ON UPDATE CASCADE,
    [active] BOOLEAN NOT NULL DEFAULT 1,
    [strategy] VARCHAR(50) NOT NULL DEFAULT 'single',
    [start_date] DATETIME,
    [end_date] DATETIME,
    [start_time] TIME,
    [end_time] TIME,
    [weekdays] VARCHAR2(250) DEFAULT '[]',
    [days_of_month] TEXT DEFAULT '[]',
    [interval_day] INTEGER
, cron TEXT, timezone VARCHAR(255), duration INTEGER);
CREATE INDEX [active] ON [maintenance] ([active]);
CREATE INDEX [maintenance_user_id] ON [maintenance] ([user_id]);
CREATE INDEX [manual_active] ON [maintenance] (
    [strategy],
    [active]
);
CREATE TABLE monitor_maintenance (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    monitor_id INTEGER NOT NULL,
    maintenance_id INTEGER NOT NULL,
    CONSTRAINT FK_maintenance FOREIGN KEY (maintenance_id) REFERENCES maintenance (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT FK_monitor FOREIGN KEY (monitor_id) REFERENCES monitor (id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX [maintenance_id_index2] ON [monitor_maintenance]([maintenance_id]);
CREATE INDEX [monitor_id_index] ON [monitor_maintenance]([monitor_id]);

-- == part 2: db/knex_migrations (translated)
-- 2023-08-16-0000-create-uptime.js, 2023-12-21-0000-stat-ping-min-max.js, 2023-12-22-0000-hourly-uptime.js,
-- 2024-01-22-0000-stats-extras.js, 2025-10-15-0000-stat-table-fix.js, 2026-01-10-0000-convert-float-precision.js,
-- 2026-07-22-0000-fix-stat-daily-overflow.js (final shapes)
CREATE TABLE `stat_minutely` (`id` integer not null primary key autoincrement, `monitor_id` integer not null, `timestamp` integer not null, `ping` float(20, 2) not null, `up` smallint not null, `down` smallint not null, `ping_min` float(20, 2) not null default '0', `ping_max` float(20, 2) not null default '0', `extras` text default null, foreign key(`monitor_id`) references `monitor`(`id`) on delete CASCADE on update CASCADE);
CREATE UNIQUE INDEX `stat_minutely_monitor_id_timestamp_unique` on `stat_minutely` (`monitor_id`, `timestamp`);
CREATE TABLE `stat_hourly` (`id` integer not null primary key autoincrement, `monitor_id` integer not null, `timestamp` integer not null, `ping` float(20, 2) not null, `ping_min` float(20, 2) not null default '0', `ping_max` float(20, 2) not null default '0', `up` smallint not null, `down` smallint not null, `extras` text default null, foreign key(`monitor_id`) references `monitor`(`id`) on delete CASCADE on update CASCADE);
CREATE UNIQUE INDEX `stat_hourly_monitor_id_timestamp_unique` on `stat_hourly` (`monitor_id`, `timestamp`);
CREATE TABLE `stat_daily` (`id` integer not null primary key autoincrement, `monitor_id` integer not null, `timestamp` integer not null, `ping` float(20, 2) not null, `up` integer not null, `down` integer not null, `ping_min` float(20, 2) not null default '0', `ping_max` float(20, 2) not null default '0', `extras` text default null, foreign key(`monitor_id`) references `monitor`(`id`) on delete CASCADE on update CASCADE);
CREATE UNIQUE INDEX `stat_daily_monitor_id_timestamp_unique` on `stat_daily` (`monitor_id`, `timestamp`);

-- heartbeat: 2023-08-18-0301-heartbeat.js, 2023-09-29-0000-heartbeat-retires.js, 2025-10-15-0002-add-response-to-heartbeat.js,
-- 2025-12-22-0121-optimize-important-indexes.js (partial indexes replace the plain ones on SQLite)
ALTER TABLE `heartbeat` ADD COLUMN `end_time` datetime null default null;
ALTER TABLE `heartbeat` ADD COLUMN `retries` integer not null default '0';
ALTER TABLE `heartbeat` ADD COLUMN `response` text null default null;
DROP INDEX IF EXISTS monitor_important_time_index;
DROP INDEX IF EXISTS heartbeat_important_index;
CREATE INDEX `monitor_important_time_index` on `heartbeat` (`monitor_id`, `time`) where important = 1;
CREATE INDEX `heartbeat_important_index` on `heartbeat` (`important`) where important = 1;

-- monitor: column additions from the knex migrations, in migration order
ALTER TABLE `monitor` ADD COLUMN `mqtt_check_type` varchar(255) not null default 'keyword';
ALTER TABLE `monitor` ADD COLUMN `remote_browser` integer default null references `remote_browser`(`id`);
ALTER TABLE `monitor` ADD COLUMN `snmp_oid` varchar(255) default null;
ALTER TABLE `monitor` ADD COLUMN `snmp_version` text check (`snmp_version` in ('1', '2c', '3')) default '2c';
ALTER TABLE `monitor` ADD COLUMN `json_path_operator` varchar(255) default null;
ALTER TABLE `monitor` ADD COLUMN `cache_bust` boolean not null default '0';
ALTER TABLE `monitor` ADD COLUMN `conditions` text not null default '[]';
ALTER TABLE `monitor` ADD COLUMN `rabbitmq_nodes` text;
ALTER TABLE `monitor` ADD COLUMN `rabbitmq_username` varchar(255);
ALTER TABLE `monitor` ADD COLUMN `rabbitmq_password` varchar(255);
ALTER TABLE `monitor` ADD COLUMN `smtp_security` varchar(255) default null;
ALTER TABLE `monitor` ADD COLUMN `ws_ignore_sec_websocket_accept_header` boolean not null default '0';
ALTER TABLE `monitor` ADD COLUMN `ws_subprotocol` varchar(255) not null default '';
ALTER TABLE `monitor` ADD COLUMN `ping_count` integer not null default '1';
ALTER TABLE `monitor` ADD COLUMN `ping_numeric` boolean not null default '1';
ALTER TABLE `monitor` ADD COLUMN `ping_per_request_timeout` integer not null default '2';
ALTER TABLE `monitor` ADD COLUMN `ip_family` varchar(4) default null;
ALTER TABLE `monitor` ADD COLUMN `manual_status` smallint default null;
ALTER TABLE `monitor` ADD COLUMN `oauth_audience` varchar(255) null default null;
ALTER TABLE `monitor` ADD COLUMN `mqtt_websocket_path` varchar(255) null;
ALTER TABLE `monitor` ADD COLUMN `domain_expiry_notification` boolean default '0';
ALTER TABLE `monitor` ADD COLUMN `save_response` boolean not null default '0';
ALTER TABLE `monitor` ADD COLUMN `save_error_response` boolean not null default '1';
ALTER TABLE `monitor` ADD COLUMN `response_max_length` integer not null default '1024';
ALTER TABLE `monitor` ADD COLUMN `subtype` varchar(10) null;
ALTER TABLE `monitor` ADD COLUMN `location` varchar(255) null;
ALTER TABLE `monitor` ADD COLUMN `protocol` varchar(20) null;
ALTER TABLE `monitor` ADD COLUMN `snmp_v3_username` varchar(255);
ALTER TABLE `monitor` ADD COLUMN `expected_tls_alert` varchar(50) default null;
ALTER TABLE `monitor` ADD COLUMN `retry_only_on_status_code_failure` boolean not null default '0';
ALTER TABLE `monitor` ADD COLUMN `screenshot_delay` integer not null default '0';
ALTER TABLE `monitor` ADD COLUMN `ntp_stratum_threshold` integer default '5';
ALTER TABLE `monitor` ADD COLUMN `ntp_time_offset_threshold` integer default '1000';
ALTER TABLE `monitor` ADD COLUMN `ntp_root_dispersion_threshold` integer default '500';
ALTER TABLE `monitor` ADD COLUMN `bearer_token` text default null;
ALTER TABLE `monitor` ADD COLUMN `gamedig_token` text default null;
ALTER TABLE `monitor` ADD COLUMN `ssh_username` varchar(255);
ALTER TABLE `monitor` ADD COLUMN `ssh_password` varchar(255);
ALTER TABLE `monitor` ADD COLUMN `sftp_path` varchar(255);
ALTER TABLE `monitor` ADD COLUMN `ssh_private_key` text;
ALTER TABLE `monitor` ADD COLUMN `ssh_passphrase` varchar(255);
ALTER TABLE `monitor` ADD COLUMN `ssh_auth_method` varchar(255) default 'password';
ALTER TABLE `monitor` ADD COLUMN `config` text not null default '{}';

-- status_page / monitor_group: 2023-12-20, 2025-02-17, 2025-10-24, 2026-01-05 (rss), 2026-08-18; 2025-05-09-0000-add-custom-url.js
ALTER TABLE `status_page` ADD COLUMN `auto_refresh_interval` integer default '300';
ALTER TABLE `status_page` RENAME COLUMN `google_analytics_tag_id` TO `analytics_id`;
ALTER TABLE `status_page` ADD COLUMN `analytics_script_url` varchar(255);
ALTER TABLE `status_page` ADD COLUMN `analytics_type` varchar(255) null default null;
ALTER TABLE `status_page` ADD COLUMN `show_only_last_heartbeat` boolean not null default '0';
ALTER TABLE `status_page` ADD COLUMN `rss_title` varchar(255);
ALTER TABLE `monitor_group` ADD COLUMN `custom_url` text;
