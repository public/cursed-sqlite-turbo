-- CrowdSec LAPI database (crowdsecurity/crowdsec @ f4b4d9d, MIT).
-- DDL exactly as ent v0.14 + Atlas emit it for SQLite: database.NewClient() -> client.Schema.Create() against an
-- empty file with the mattn driver, then dumped with .schema (sqlite_sequence dropped). Source of truth is
-- pkg/database/ent/migrate/schema.go. Note there is no index on alerts.created_at / alerts.started_at.
CREATE TABLE `alerts` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `created_at` datetime NOT NULL, `updated_at` datetime NOT NULL, `scenario` text NOT NULL, `bucket_id` text NULL DEFAULT (''), `message` text NULL DEFAULT (''), `events_count` integer NULL DEFAULT (0), `started_at` datetime NULL, `stopped_at` datetime NULL, `source_ip` text NULL, `source_range` text NULL, `source_as_number` text NULL, `source_as_name` text NULL, `source_country` text NULL, `source_latitude` real NULL, `source_longitude` real NULL, `source_scope` text NULL, `source_value` text NULL, `capacity` integer NULL, `leak_speed` text NULL, `scenario_version` text NULL, `scenario_hash` text NULL, `simulated` bool NOT NULL DEFAULT (false), `uuid` text NULL, `remediation` bool NULL, `kind` text NULL, `machine_alerts` integer NULL, CONSTRAINT `alerts_machines_alerts` FOREIGN KEY (`machine_alerts`) REFERENCES `machines` (`id`) ON DELETE SET NULL);
CREATE INDEX `alert_id` ON `alerts` (`id`);
CREATE INDEX `alert_uuid` ON `alerts` (`uuid`);
CREATE INDEX `alert_scenario` ON `alerts` (`scenario`);
CREATE TABLE `allow_lists` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `created_at` datetime NOT NULL, `updated_at` datetime NOT NULL, `name` text NOT NULL, `from_console` bool NOT NULL, `description` text NULL, `allowlist_id` text NULL);
CREATE UNIQUE INDEX `allowlist_id` ON `allow_lists` (`id`);
CREATE UNIQUE INDEX `allowlist_name` ON `allow_lists` (`name`);
CREATE INDEX `allowlist_allowlist_id` ON `allow_lists` (`allowlist_id`);
CREATE TABLE `allow_list_items` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `created_at` datetime NOT NULL, `updated_at` datetime NOT NULL, `expires_at` datetime NULL, `comment` text NULL, `value` text NOT NULL, `start_ip` integer NULL, `end_ip` integer NULL, `start_suffix` integer NULL, `end_suffix` integer NULL, `ip_size` integer NULL);
CREATE INDEX `allowlistitem_id` ON `allow_list_items` (`id`);
CREATE INDEX `allowlistitem_start_ip_end_ip` ON `allow_list_items` (`start_ip`, `end_ip`);
CREATE INDEX `allowlistitem_expires_at` ON `allow_list_items` (`expires_at`);
CREATE TABLE `bouncers` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `created_at` datetime NOT NULL, `updated_at` datetime NOT NULL, `name` text NOT NULL, `api_key` text NOT NULL, `revoked` bool NOT NULL, `ip_address` text NULL DEFAULT (''), `type` text NULL, `version` text NULL, `last_pull` datetime NULL, `stream_cursor` integer NOT NULL DEFAULT (0), `auth_type` text NOT NULL DEFAULT ('api-key'), `osname` text NULL, `osfamily` text NULL, `osversion` text NULL, `featureflags` text NULL, `auto_created` bool NOT NULL DEFAULT (false));
CREATE UNIQUE INDEX `bouncers_name_key` ON `bouncers` (`name`);
CREATE INDEX `bouncer_api_key_auth_type` ON `bouncers` (`api_key`, `auth_type`);
CREATE INDEX `bouncer_api_key_ip_address` ON `bouncers` (`api_key`, `ip_address`);
CREATE INDEX `bouncer_last_pull_created_at` ON `bouncers` (`last_pull`, `created_at`);
CREATE TABLE `config_items` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `created_at` datetime NOT NULL, `updated_at` datetime NOT NULL, `name` text NOT NULL, `value` text NOT NULL);
CREATE UNIQUE INDEX `config_items_name_key` ON `config_items` (`name`);
CREATE TABLE `decisions` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `created_at` datetime NOT NULL, `updated_at` datetime NOT NULL, `until` datetime NULL, `scenario` text NOT NULL, `type` text NOT NULL, `start_ip` integer NULL, `end_ip` integer NULL, `start_suffix` integer NULL, `end_suffix` integer NULL, `ip_size` integer NULL, `scope` text NOT NULL, `value` text NOT NULL, `origin` text NOT NULL, `simulated` bool NOT NULL DEFAULT (false), `uuid` text NULL, `alert_decisions` integer NULL, CONSTRAINT `decisions_alerts_decisions` FOREIGN KEY (`alert_decisions`) REFERENCES `alerts` (`id`) ON DELETE CASCADE);
CREATE INDEX `decision_start_ip_end_ip` ON `decisions` (`start_ip`, `end_ip`);
CREATE INDEX `decision_value_type_scope_until_simulated` ON `decisions` (`value`, `type`, `scope`, `until`, `simulated`);
CREATE INDEX `decision_until` ON `decisions` (`until`);
CREATE INDEX `decision_alert_decisions` ON `decisions` (`alert_decisions`);
CREATE TABLE `events` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `created_at` datetime NOT NULL, `updated_at` datetime NOT NULL, `time` datetime NOT NULL, `serialized` text NOT NULL, `alert_events` integer NULL, CONSTRAINT `events_alerts_events` FOREIGN KEY (`alert_events`) REFERENCES `alerts` (`id`) ON DELETE CASCADE);
CREATE INDEX `event_alert_events` ON `events` (`alert_events`);
CREATE TABLE `locks` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `name` text NOT NULL, `created_at` datetime NOT NULL);
CREATE UNIQUE INDEX `locks_name_key` ON `locks` (`name`);
CREATE TABLE `machines` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `created_at` datetime NOT NULL, `updated_at` datetime NOT NULL, `last_push` datetime NULL, `last_heartbeat` datetime NULL, `machine_id` text NOT NULL, `password` text NOT NULL, `ip_address` text NOT NULL, `scenarios` text NULL, `version` text NULL, `is_validated` bool NOT NULL DEFAULT (false), `auth_type` text NOT NULL DEFAULT ('password'), `osname` text NULL, `osfamily` text NULL, `osversion` text NULL, `featureflags` text NULL, `hubstate` json NULL, `datasources` json NULL, `features` json NULL);
CREATE UNIQUE INDEX `machines_machine_id_key` ON `machines` (`machine_id`);
CREATE INDEX `machine_last_heartbeat_created_at` ON `machines` (`last_heartbeat`, `created_at`);
CREATE INDEX `machine_is_validated` ON `machines` (`is_validated`);
CREATE TABLE `meta` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `created_at` datetime NOT NULL, `updated_at` datetime NOT NULL, `key` text NOT NULL, `value` text NOT NULL, `alert_metas` integer NULL, CONSTRAINT `meta_alerts_metas` FOREIGN KEY (`alert_metas`) REFERENCES `alerts` (`id`) ON DELETE CASCADE);
CREATE INDEX `meta_alert_metas` ON `meta` (`alert_metas`);
CREATE TABLE `metrics` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `generated_type` text NOT NULL, `generated_by` text NOT NULL, `received_at` datetime NOT NULL, `pushed_at` datetime NULL, `payload` text NOT NULL);
CREATE INDEX `metric_received_at` ON `metrics` (`received_at`);
CREATE INDEX `metric_generated_type_generated_by_pushed_at` ON `metrics` (`generated_type`, `generated_by`, `pushed_at`);
CREATE TABLE `allow_list_allowlist_items` (`allow_list_id` integer NOT NULL, `allow_list_item_id` integer NOT NULL, PRIMARY KEY (`allow_list_id`, `allow_list_item_id`), CONSTRAINT `allow_list_allowlist_items_allow_list_id` FOREIGN KEY (`allow_list_id`) REFERENCES `allow_lists` (`id`) ON DELETE CASCADE, CONSTRAINT `allow_list_allowlist_items_allow_list_item_id` FOREIGN KEY (`allow_list_item_id`) REFERENCES `allow_list_items` (`id`) ON DELETE CASCADE);
