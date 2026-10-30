-- Wakapi (muety/wakapi @ aba6a44, MIT). Hand-translated from the GORM models (models/user.go, heartbeat.go,
-- duration.go, summary.go, leaderboard.go) into the DDL that GORM v1.31 + glebarez/sqlite v1.11 AutoMigrate emits
-- on a fresh SQLite install: backtick quoting, integer PRIMARY KEY AUTOINCREMENT ids, `text` for Go strings,
-- `numeric` for untagged bools, and CustomTime as `integer` (Unix epoch milliseconds, models/shared.go;
-- see migrations/20260722_sqlite_convert_time_to_integer.go). Only the tables the queries touch.
-- Indexes are exactly the model tags at this SHA, after migrations 20261011 (idx_user_project_time replaces
-- idx_project/idx_user_project/idx_time_user), 20260929 (drops durations.idx_time_duration) and the #974 fix
-- (idx_summary_item_summary on summary_items.summary_id).

CREATE TABLE `users` (`id` text,`api_key` text UNIQUE DEFAULT NULL,`email` text DEFAULT null,`location` text,
  `start_of_week` integer DEFAULT 1,`password` text,`created_at` integer,`last_logged_in_at` integer,
  `share_data_max_days` integer,`share_editors` bool DEFAULT false,`share_languages` bool DEFAULT false,
  `share_projects` bool DEFAULT false,`share_oss` bool DEFAULT false,`share_machines` bool DEFAULT false,
  `share_labels` bool DEFAULT false,`share_activity_chart` bool DEFAULT false,`is_admin` bool DEFAULT false,
  `has_data` bool DEFAULT false,`wakatime_api_key` text,`wakatime_api_url` text,`reset_token` text,
  `unsubscribe_token` text,`reports_weekly` bool DEFAULT false,`public_leaderboard` bool DEFAULT false,
  `subscribed_until` integer,`subscription_renewal` integer,`stripe_customer_id` text,`invited_by` text,
  `exclude_unknown_projects` numeric,`heartbeats_timeout_sec` integer DEFAULT 600,`readme_stats_base_url` text DEFAULT '',
  `auth_type` text DEFAULT 'local',`sub` text DEFAULT null,`webauthn_id` text,PRIMARY KEY (`id`));
CREATE UNIQUE INDEX `idx_user_email` ON `users`(`email`);
CREATE UNIQUE INDEX `idx_oidc` ON `users`(`auth_type`,`sub`);

CREATE TABLE `heartbeats` (`id` integer PRIMARY KEY AUTOINCREMENT,`user_id` text NOT NULL,`entity` text NOT NULL,
  `type` text,`category` text,`project` text,`branch` text,`language` text,`is_write` numeric,`editor` text,
  `ai_model` text,`operating_system` text,`machine` text,`user_agent` varchar(255),`time` integer NOT NULL,
  `hash` varchar(17),`origin` varchar(255),`origin_id` varchar(255),`created_at` integer NOT NULL,`lines` integer,
  `line_no` integer,`cursor_pos` integer,`line_deletions` integer,`line_additions` integer,
  `project_root_count` integer,`ai_line_changes` integer,`ai_session` text,`ai_input_tokens` integer,
  `ai_output_tokens` integer,`ai_prompt_length` integer,`human_line_changes` integer,
  CONSTRAINT `fk_heartbeats_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE ON UPDATE CASCADE);
CREATE INDEX `idx_time_user_project_lang` ON `heartbeats`(`user_id`,`time`,`project`,`language`);
CREATE INDEX `idx_user_project_time` ON `heartbeats`(`user_id`,`project`,`time`);
CREATE INDEX `idx_branch` ON `heartbeats`(`branch`);
CREATE INDEX `idx_language` ON `heartbeats`(`language`);
CREATE INDEX `idx_editor` ON `heartbeats`(`editor`);
CREATE INDEX `idx_ai_model` ON `heartbeats`(`ai_model`);
CREATE INDEX `idx_operating_system` ON `heartbeats`(`operating_system`);
CREATE INDEX `idx_machine` ON `heartbeats`(`machine`);
CREATE INDEX `idx_time` ON `heartbeats`(`time`);
CREATE UNIQUE INDEX `idx_heartbeats_hash` ON `heartbeats`(`hash`);

-- durations: no FK on SQLite (migrations/20260925_drop_orphaned_durations.go); idx_time_duration_user is (user_id, time)
-- in struct-field order despite its name (see #976).
CREATE TABLE `durations` (`id` integer PRIMARY KEY AUTOINCREMENT,`user_id` text NOT NULL,`time` integer NOT NULL,
  `duration` integer NOT NULL,`project` text,`language` text,`editor` text,`operating_system` text,`machine` text,
  `category` text,`ai_model` text,`branch` text,`entity` text,`extension` text,`num_heartbeats` integer,
  `group_hash` varchar(17),`timeout` integer NOT NULL DEFAULT 600000000000);
CREATE INDEX `idx_time_duration_user` ON `durations`(`user_id`,`time`);

CREATE TABLE `summaries` (`id` integer PRIMARY KEY AUTOINCREMENT,`user_id` text NOT NULL,`from_time` integer NOT NULL,
  `to_time` integer NOT NULL,`num_heartbeats` integer,
  CONSTRAINT `fk_summaries_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE ON UPDATE CASCADE);
CREATE INDEX `idx_time_summary_user` ON `summaries`(`user_id`,`from_time`,`to_time`);

CREATE TABLE `summary_items` (`id` integer PRIMARY KEY AUTOINCREMENT,`summary_id` integer,`type` integer,`key` text,
  `total` integer,
  CONSTRAINT `fk_summaries_projects` FOREIGN KEY (`summary_id`) REFERENCES `summaries`(`id`) ON DELETE CASCADE ON UPDATE CASCADE);
CREATE INDEX `idx_summary_item_summary` ON `summary_items`(`summary_id`);
CREATE INDEX `idx_type` ON `summary_items`(`type`);

CREATE TABLE `leaderboard_items` (`id` integer PRIMARY KEY AUTOINCREMENT,`user_id` text NOT NULL,`interval` text NOT NULL,
  `by` integer,`total` integer NOT NULL,`key` text,`created_at` integer,
  CONSTRAINT `fk_leaderboard_items_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE ON UPDATE CASCADE);
CREATE INDEX `idx_leaderboard_user` ON `leaderboard_items`(`user_id`);
CREATE INDEX `idx_leaderboard_combined` ON `leaderboard_items`(`interval`,`by`);

-- migrations/20260722_sqlite_convert_time_to_integer.go (post-migration view)
CREATE VIEW IF NOT EXISTS user_heartbeats_range AS select u.id as user_id, min(h.time) as first, max(h.time) as last from users u left join heartbeats h on u.id = h.user_id group by u.id;
