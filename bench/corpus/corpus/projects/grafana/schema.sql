-- Grafana (grafana/grafana @ 05e78bb47904d81c17b9db7542d7127da48ce434, AGPL-3.0). Only the tables the queries use.
-- Source: pkg/services/sqlstore/migrator/snapshot/00-schema.sql (the migrator's schema snapshot, a MySQL dump of the
-- final state of pkg/services/sqlstore/migrations and the unified-storage resource migrations), converted to the
-- SQLite types Grafana's sqlite dialect uses (pkg/services/sqlstore/migrator/sqlite_dialect.go: INTEGER/TEXT/
-- DATETIME/REAL/BLOB, `INTEGER PRIMARY KEY AUTOINCREMENT` ids, backtick quoting, UQE_/IDX_ indexes), plus the
-- k8s_status column added later by pkg/services/sqlstore/migrations/ualert/tables.go ("add k8s_status column to
-- alert_rule table").

CREATE TABLE `resource` (
  `guid` TEXT NOT NULL
, `resource_version` INTEGER DEFAULT NULL
, `group` TEXT NOT NULL
, `resource` TEXT NOT NULL
, `namespace` TEXT NOT NULL
, `name` TEXT NOT NULL
, `value` TEXT
, `action` INTEGER NOT NULL
, `label_set` TEXT DEFAULT NULL
, `previous_resource_version` INTEGER DEFAULT NULL
, `folder` TEXT NOT NULL DEFAULT ''
, PRIMARY KEY (`guid`)
);
CREATE UNIQUE INDEX `UQE_resource_namespace_group_resource_name` ON `resource` (`namespace`,`group`,`resource`,`name`);
CREATE INDEX `IDX_resource_group_resource` ON `resource` (`group`,`resource`);
CREATE TABLE `resource_history` (
  `guid` TEXT NOT NULL
, `resource_version` INTEGER DEFAULT NULL
, `group` TEXT NOT NULL
, `resource` TEXT NOT NULL
, `namespace` TEXT NOT NULL
, `name` TEXT NOT NULL
, `value` TEXT
, `action` INTEGER NOT NULL
, `label_set` TEXT DEFAULT NULL
, `previous_resource_version` INTEGER DEFAULT NULL
, `folder` TEXT NOT NULL DEFAULT ''
, `generation` INTEGER NOT NULL DEFAULT '0'
, `key_path` TEXT NOT NULL DEFAULT ''
, PRIMARY KEY (`guid`)
);
CREATE UNIQUE INDEX `UQE_resource_history_namespace_group_name_version` ON `resource_history` (`namespace`,`group`,`resource`,`name`,`resource_version`);
CREATE INDEX `IDX_resource_history_resource_version` ON `resource_history` (`resource_version`);
CREATE INDEX `IDX_resource_history_group_resource_resource_version` ON `resource_history` (`group`,`resource`,`resource_version`);
CREATE INDEX `IDX_resource_history_namespace_group_resource_action_version` ON `resource_history` (`namespace`,`group`,`resource`,`action`,`resource_version`);
CREATE INDEX `IDX_resource_history_namespace_group_resource_name_generation` ON `resource_history` (`namespace`,`group`,`resource`,`name`,`generation`);
CREATE INDEX `IDX_resource_history_key_path` ON `resource_history` (`key_path`);
CREATE INDEX `IDX_resource_history_resource_action_version_name` ON `resource_history` (`group`,`resource`,`action`,`resource_version`,`name`);
CREATE TABLE `dashboard` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `version` INTEGER NOT NULL
, `slug` TEXT NOT NULL
, `title` TEXT NOT NULL
, `data` TEXT NOT NULL
, `org_id` INTEGER NOT NULL
, `created` DATETIME NOT NULL
, `updated` DATETIME NOT NULL
, `updated_by` INTEGER DEFAULT NULL
, `created_by` INTEGER DEFAULT NULL
, `gnet_id` INTEGER DEFAULT NULL
, `plugin_id` TEXT DEFAULT NULL
, `folder_id` INTEGER NOT NULL DEFAULT '0'
, `is_folder` INTEGER NOT NULL DEFAULT '0'
, `has_acl` INTEGER NOT NULL DEFAULT '0'
, `uid` TEXT DEFAULT NULL
, `is_public` INTEGER NOT NULL DEFAULT '0'
, `deleted` DATETIME DEFAULT NULL
, `api_version` TEXT DEFAULT NULL
, `folder_uid` TEXT DEFAULT NULL
);
CREATE UNIQUE INDEX `UQE_dashboard_org_id_uid` ON `dashboard` (`org_id`,`uid`);
CREATE INDEX `IDX_dashboard_org_id` ON `dashboard` (`org_id`);
CREATE INDEX `IDX_dashboard_gnet_id` ON `dashboard` (`gnet_id`);
CREATE INDEX `IDX_dashboard_org_id_plugin_id` ON `dashboard` (`org_id`,`plugin_id`);
CREATE INDEX `IDX_dashboard_title` ON `dashboard` (`title`);
CREATE INDEX `IDX_dashboard_is_folder` ON `dashboard` (`is_folder`);
CREATE INDEX `IDX_dashboard_deleted` ON `dashboard` (`deleted`);
CREATE INDEX `IDX_dashboard_org_id_folder_id_title` ON `dashboard` (`org_id`,`folder_id`,`title`);
CREATE TABLE `dashboard_version` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `dashboard_id` INTEGER NOT NULL
, `parent_version` INTEGER NOT NULL
, `restored_from` INTEGER NOT NULL
, `version` INTEGER NOT NULL
, `created` DATETIME NOT NULL
, `created_by` INTEGER NOT NULL
, `message` TEXT NOT NULL
, `data` TEXT
, `api_version` TEXT DEFAULT NULL
);
CREATE UNIQUE INDEX `UQE_dashboard_version_dashboard_id_version` ON `dashboard_version` (`dashboard_id`,`version`);
CREATE INDEX `IDX_dashboard_version_dashboard_id` ON `dashboard_version` (`dashboard_id`);
CREATE TABLE `dashboard_provisioning` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `dashboard_id` INTEGER DEFAULT NULL
, `name` TEXT NOT NULL
, `external_id` TEXT NOT NULL
, `updated` INTEGER NOT NULL DEFAULT '0'
, `check_sum` TEXT DEFAULT NULL
);
CREATE INDEX `IDX_dashboard_provisioning_dashboard_id` ON `dashboard_provisioning` (`dashboard_id`);
CREATE INDEX `IDX_dashboard_provisioning_dashboard_id_name` ON `dashboard_provisioning` (`dashboard_id`,`name`);
CREATE TABLE `user` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `version` INTEGER NOT NULL
, `login` TEXT NOT NULL
, `email` TEXT NOT NULL
, `name` TEXT DEFAULT NULL
, `password` TEXT DEFAULT NULL
, `salt` TEXT DEFAULT NULL
, `rands` TEXT DEFAULT NULL
, `company` TEXT DEFAULT NULL
, `org_id` INTEGER NOT NULL
, `is_admin` INTEGER NOT NULL
, `email_verified` INTEGER DEFAULT NULL
, `theme` TEXT DEFAULT NULL
, `created` DATETIME NOT NULL
, `updated` DATETIME NOT NULL
, `help_flags1` INTEGER NOT NULL DEFAULT '0'
, `last_seen_at` DATETIME DEFAULT NULL
, `is_disabled` INTEGER NOT NULL DEFAULT '0'
, `is_service_account` INTEGER DEFAULT '0'
, `uid` TEXT DEFAULT NULL
, `is_provisioned` INTEGER NOT NULL DEFAULT '0'
);
CREATE UNIQUE INDEX `UQE_user_login` ON `user` (`login`);
CREATE UNIQUE INDEX `UQE_user_email` ON `user` (`email`);
CREATE UNIQUE INDEX `UQE_user_uid` ON `user` (`uid`);
CREATE INDEX `IDX_user_login_email` ON `user` (`login`,`email`);
CREATE INDEX `IDX_user_is_service_account_last_seen_at` ON `user` (`is_service_account`,`last_seen_at`);
CREATE TABLE `org` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `version` INTEGER NOT NULL
, `name` TEXT NOT NULL
, `address1` TEXT DEFAULT NULL
, `address2` TEXT DEFAULT NULL
, `city` TEXT DEFAULT NULL
, `state` TEXT DEFAULT NULL
, `zip_code` TEXT DEFAULT NULL
, `country` TEXT DEFAULT NULL
, `billing_email` TEXT DEFAULT NULL
, `created` DATETIME NOT NULL
, `updated` DATETIME NOT NULL
);
CREATE UNIQUE INDEX `UQE_org_name` ON `org` (`name`);
CREATE TABLE `org_user` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `org_id` INTEGER NOT NULL
, `user_id` INTEGER NOT NULL
, `role` TEXT NOT NULL
, `created` DATETIME NOT NULL
, `updated` DATETIME NOT NULL
);
CREATE UNIQUE INDEX `UQE_org_user_org_id_user_id` ON `org_user` (`org_id`,`user_id`);
CREATE INDEX `IDX_org_user_org_id` ON `org_user` (`org_id`);
CREATE INDEX `IDX_org_user_user_id` ON `org_user` (`user_id`);
CREATE TABLE `user_auth` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `user_id` INTEGER NOT NULL
, `auth_module` TEXT NOT NULL
, `auth_id` TEXT DEFAULT NULL
, `created` DATETIME NOT NULL
, `o_auth_access_token` TEXT
, `o_auth_refresh_token` TEXT
, `o_auth_token_type` TEXT
, `o_auth_expiry` DATETIME DEFAULT NULL
, `o_auth_id_token` TEXT
, `external_uid` TEXT
, `user_uid` TEXT DEFAULT NULL
);
CREATE INDEX `IDX_user_auth_auth_module_auth_id` ON `user_auth` (`auth_module`,`auth_id`);
CREATE INDEX `IDX_user_auth_user_id` ON `user_auth` (`user_id`);
CREATE TABLE `team` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `name` TEXT NOT NULL
, `org_id` INTEGER NOT NULL
, `created` DATETIME NOT NULL
, `updated` DATETIME NOT NULL
, `uid` TEXT DEFAULT NULL
, `external_uid` TEXT DEFAULT NULL
, `is_provisioned` INTEGER DEFAULT NULL
, `email` TEXT DEFAULT NULL
);
CREATE UNIQUE INDEX `UQE_team_org_id_name` ON `team` (`org_id`,`name`);
CREATE UNIQUE INDEX `UQE_team_org_id_uid` ON `team` (`org_id`,`uid`);
CREATE INDEX `IDX_team_org_id` ON `team` (`org_id`);
CREATE TABLE `team_member` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `org_id` INTEGER NOT NULL
, `team_id` INTEGER NOT NULL
, `user_id` INTEGER NOT NULL
, `created` DATETIME NOT NULL
, `updated` DATETIME NOT NULL
, `external` INTEGER DEFAULT NULL
, `permission` INTEGER DEFAULT NULL
, `uid` TEXT DEFAULT NULL
);
CREATE UNIQUE INDEX `UQE_team_member_org_id_team_id_user_id` ON `team_member` (`org_id`,`team_id`,`user_id`);
CREATE UNIQUE INDEX `UQE_team_member_uid` ON `team_member` (`uid`);
CREATE INDEX `IDX_team_member_org_id` ON `team_member` (`org_id`);
CREATE INDEX `IDX_team_member_team_id` ON `team_member` (`team_id`);
CREATE INDEX `IDX_team_member_user_id_org_id` ON `team_member` (`user_id`,`org_id`);
CREATE TABLE `team_role` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `org_id` INTEGER NOT NULL
, `team_id` INTEGER NOT NULL
, `role_id` INTEGER NOT NULL
, `created` DATETIME NOT NULL
);
CREATE UNIQUE INDEX `UQE_team_role_org_id_team_id_role_id` ON `team_role` (`org_id`,`team_id`,`role_id`);
CREATE INDEX `IDX_team_role_org_id` ON `team_role` (`org_id`);
CREATE INDEX `IDX_team_role_team_id` ON `team_role` (`team_id`);
CREATE TABLE `user_role` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `org_id` INTEGER NOT NULL
, `user_id` INTEGER NOT NULL
, `role_id` INTEGER NOT NULL
, `created` DATETIME NOT NULL
, `group_mapping_uid` TEXT DEFAULT ''
);
CREATE UNIQUE INDEX `UQE_user_role_org_id_user_id_role_id_group_mapping_uid` ON `user_role` (`org_id`,`user_id`,`role_id`,`group_mapping_uid`);
CREATE INDEX `IDX_user_role_org_id` ON `user_role` (`org_id`);
CREATE INDEX `IDX_user_role_user_id` ON `user_role` (`user_id`);
CREATE TABLE `builtin_role` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `role` TEXT NOT NULL
, `role_id` INTEGER NOT NULL
, `created` DATETIME NOT NULL
, `updated` DATETIME NOT NULL
, `org_id` INTEGER NOT NULL DEFAULT '0'
);
CREATE UNIQUE INDEX `UQE_builtin_role_org_id_role_id_role` ON `builtin_role` (`org_id`,`role_id`,`role`);
CREATE INDEX `IDX_builtin_role_role_id` ON `builtin_role` (`role_id`);
CREATE INDEX `IDX_builtin_role_role` ON `builtin_role` (`role`);
CREATE INDEX `IDX_builtin_role_org_id` ON `builtin_role` (`org_id`);
CREATE TABLE `role` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `name` TEXT NOT NULL
, `description` TEXT
, `version` INTEGER NOT NULL
, `org_id` INTEGER NOT NULL
, `uid` TEXT NOT NULL
, `created` DATETIME NOT NULL
, `updated` DATETIME NOT NULL
, `display_name` TEXT DEFAULT NULL
, `group_name` TEXT DEFAULT NULL
, `hidden` INTEGER NOT NULL DEFAULT '0'
);
CREATE UNIQUE INDEX `UQE_role_org_id_name` ON `role` (`org_id`,`name`);
CREATE UNIQUE INDEX `UQE_role_uid` ON `role` (`uid`);
CREATE INDEX `IDX_role_org_id` ON `role` (`org_id`);
CREATE TABLE `permission` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `role_id` INTEGER NOT NULL
, `action` TEXT NOT NULL
, `scope` TEXT NOT NULL
, `created` DATETIME NOT NULL
, `updated` DATETIME NOT NULL
, `kind` TEXT DEFAULT NULL
, `attribute` TEXT NOT NULL DEFAULT ''
, `identifier` TEXT NOT NULL DEFAULT ''
, `datasource_type` TEXT DEFAULT NULL
);
CREATE UNIQUE INDEX `UQE_permission_action_scope_role_id` ON `permission` (`action`,`scope`,`role_id`);
CREATE INDEX `IDX_permission_identifier` ON `permission` (`identifier`);
CREATE INDEX `IDX_permission_role_id_action` ON `permission` (`role_id`,`action`);
CREATE INDEX `IDX_permission_role_id_scope` ON `permission` (`role_id`,`scope`);
CREATE TABLE `annotation` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `org_id` INTEGER NOT NULL
, `alert_id` INTEGER DEFAULT NULL
, `user_id` INTEGER DEFAULT NULL
, `dashboard_id` INTEGER DEFAULT NULL
, `panel_id` INTEGER DEFAULT NULL
, `category_id` INTEGER DEFAULT NULL
, `type` TEXT NOT NULL
, `title` TEXT NOT NULL
, `text` TEXT NOT NULL
, `metric` TEXT DEFAULT NULL
, `prev_state` TEXT NOT NULL
, `new_state` TEXT NOT NULL
, `data` TEXT NOT NULL
, `epoch` INTEGER NOT NULL
, `region_id` INTEGER DEFAULT '0'
, `tags` TEXT DEFAULT NULL
, `created` INTEGER DEFAULT '0'
, `updated` INTEGER DEFAULT '0'
, `epoch_end` INTEGER NOT NULL DEFAULT '0'
, `dashboard_uid` TEXT DEFAULT NULL
);
CREATE INDEX `IDX_annotation_org_id_alert_id` ON `annotation` (`org_id`,`alert_id`);
CREATE INDEX `IDX_annotation_org_id_type` ON `annotation` (`org_id`,`type`);
CREATE INDEX `IDX_annotation_org_id_created` ON `annotation` (`org_id`,`created`);
CREATE INDEX `IDX_annotation_org_id_updated` ON `annotation` (`org_id`,`updated`);
CREATE INDEX `IDX_annotation_org_id_dashboard_id_epoch_end_epoch` ON `annotation` (`org_id`,`dashboard_id`,`epoch_end`,`epoch`);
CREATE INDEX `IDX_annotation_org_id_epoch_end_epoch` ON `annotation` (`org_id`,`epoch_end`,`epoch`);
CREATE INDEX `IDX_annotation_alert_id` ON `annotation` (`alert_id`);
CREATE TABLE `annotation_tag` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `annotation_id` INTEGER NOT NULL
, `tag_id` INTEGER NOT NULL
);
CREATE UNIQUE INDEX `UQE_annotation_tag_annotation_id_tag_id` ON `annotation_tag` (`annotation_id`,`tag_id`);
CREATE TABLE `tag` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `key` TEXT NOT NULL
, `value` TEXT NOT NULL
);
CREATE UNIQUE INDEX `UQE_tag_key_value` ON `tag` (`key`,`value`);
CREATE TABLE `alert_rule` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `org_id` INTEGER NOT NULL
, `title` TEXT NOT NULL
, `condition` TEXT NOT NULL
, `data` TEXT
, `updated` DATETIME NOT NULL
, `interval_seconds` INTEGER NOT NULL DEFAULT '60'
, `version` INTEGER NOT NULL DEFAULT '0'
, `uid` TEXT NOT NULL DEFAULT '0'
, `namespace_uid` TEXT NOT NULL
, `rule_group` TEXT NOT NULL
, `no_data_state` TEXT NOT NULL DEFAULT 'NoData'
, `exec_err_state` TEXT NOT NULL DEFAULT 'Alerting'
, `for` INTEGER NOT NULL DEFAULT '0'
, `annotations` TEXT
, `labels` TEXT
, `dashboard_uid` TEXT DEFAULT NULL
, `panel_id` INTEGER DEFAULT NULL
, `rule_group_idx` INTEGER DEFAULT NULL
, `is_paused` INTEGER NOT NULL DEFAULT '0'
, `notification_settings` TEXT
, `record` TEXT
, `metadata` TEXT
, `updated_by` TEXT DEFAULT NULL
, `guid` TEXT NOT NULL DEFAULT ''
, `keep_firing_for` INTEGER NOT NULL DEFAULT '0'
, `missing_series_evals_to_resolve` INTEGER DEFAULT NULL
, `folder_fullpath` TEXT DEFAULT NULL
, `alert_routing_policy` TEXT DEFAULT NULL
);
CREATE UNIQUE INDEX `UQE_alert_rule_org_id_uid` ON `alert_rule` (`org_id`,`uid`);
CREATE UNIQUE INDEX `UQE_alert_rule_guid` ON `alert_rule` (`guid`);
CREATE INDEX `IDX_alert_rule_org_id_namespace_uid_rule_group` ON `alert_rule` (`org_id`,`namespace_uid`,`rule_group`);
CREATE INDEX `IDX_alert_rule_org_id_dashboard_uid_panel_id` ON `alert_rule` (`org_id`,`dashboard_uid`,`panel_id`);
CREATE INDEX `IDX_alert_rule_org_id_namespace_uid_rule_group_rule_group_idx` ON `alert_rule` (`org_id`,`namespace_uid`,`rule_group`,`rule_group_idx`);
CREATE INDEX `IDX_alert_rule_org_id_folder_fullpath` ON `alert_rule` (`org_id`,`folder_fullpath`);
CREATE TABLE `alert_rule_version` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `rule_org_id` INTEGER NOT NULL
, `rule_uid` TEXT NOT NULL DEFAULT '0'
, `rule_namespace_uid` TEXT NOT NULL
, `rule_group` TEXT NOT NULL
, `parent_version` INTEGER NOT NULL
, `restored_from` INTEGER NOT NULL
, `version` INTEGER NOT NULL
, `created` DATETIME NOT NULL
, `title` TEXT NOT NULL
, `condition` TEXT NOT NULL
, `data` TEXT
, `interval_seconds` INTEGER NOT NULL
, `no_data_state` TEXT NOT NULL DEFAULT 'NoData'
, `exec_err_state` TEXT NOT NULL DEFAULT 'Alerting'
, `for` INTEGER NOT NULL DEFAULT '0'
, `annotations` TEXT
, `labels` TEXT
, `rule_group_idx` INTEGER DEFAULT NULL
, `is_paused` INTEGER NOT NULL DEFAULT '0'
, `message` TEXT
, `notification_settings` TEXT
, `record` TEXT
, `metadata` TEXT
, `created_by` TEXT DEFAULT NULL
, `rule_guid` TEXT NOT NULL DEFAULT ''
, `keep_firing_for` INTEGER NOT NULL DEFAULT '0'
, `missing_series_evals_to_resolve` INTEGER DEFAULT NULL
, `alert_routing_policy` TEXT DEFAULT NULL
);
CREATE UNIQUE INDEX `UQE_alert_rule_version_rule_org_id_rule_uid_rule_guid_version` ON `alert_rule_version` (`rule_org_id`,`rule_uid`,`rule_guid`,`version`);
CREATE UNIQUE INDEX `UQE_alert_rule_version_rule_guid_version` ON `alert_rule_version` (`rule_guid`,`version`);
CREATE INDEX `IDX_alert_rule_version_rule_org_id_rule_namespace_uid_rule_group` ON `alert_rule_version` (`rule_org_id`,`rule_namespace_uid`,`rule_group`);
CREATE TABLE `star` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `user_id` INTEGER NOT NULL
, `dashboard_id` INTEGER NOT NULL
, `dashboard_uid` TEXT DEFAULT NULL
, `org_id` INTEGER DEFAULT '1'
, `updated` DATETIME DEFAULT NULL
);
CREATE UNIQUE INDEX `UQE_star_user_id_dashboard_id` ON `star` (`user_id`,`dashboard_id`);
CREATE UNIQUE INDEX `UQE_star_user_id_dashboard_uid_org_id` ON `star` (`user_id`,`dashboard_uid`,`org_id`);

ALTER TABLE `alert_rule` ADD COLUMN `k8s_status` TEXT NULL;
