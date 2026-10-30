-- Synthetic data for Grafana. Deterministic (no random()): values come from multiplicative hashes of row numbers.
-- Scale 1: 2 orgs, 2000 users (100 service accounts), 100 teams (~6k memberships), ~1.2k roles with ~16k
-- permissions, 3450 legacy dashboard rows (300 folders, 150 deleted) with ~15k versions, the same objects in unified
-- storage (resource + ~16k resource_history rows), 50k annotations with ~90k tag links, 500 alert rules with 3000
-- versions, 3000 stars. _cfg.scale multiplies users, dashboards/resources, annotations and alert rules.
-- Times: "now" is 1790000000 s; annotation epochs are ms; resource versions are µs-style snowflakes.
BEGIN;

INSERT INTO org(id, version, name, created, updated) VALUES
  (1, 0, 'Main Org.', '2024-01-01 00:00:00', '2024-01-01 00:00:00'),
  (2, 0, 'Partner Org', '2025-03-01 00:00:00', '2025-03-01 00:00:00');

-- users: 1 is the server admin; the last 5 % are service accounts.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000*(SELECT scale FROM _cfg)),
u AS (SELECT i, (i * 2654435761) % 4294967296 AS h, i > 1900*(SELECT scale FROM _cfg) AS sa FROM n)
INSERT INTO `user`(id, version, login, email, name, org_id, is_admin, email_verified, created, updated, help_flags1,
                   last_seen_at, is_disabled, is_service_account, uid, is_provisioned)
SELECT i, 0,
  CASE WHEN sa THEN 'sa-1-svc' || i ELSE CASE WHEN i % 17 = 0 THEN 'ops' ELSE 'user' END || i END,
  CASE WHEN sa THEN 'sa-' || i ELSE CASE WHEN i % 17 = 0 THEN 'ops' ELSE 'user' END || i || '@example.com' END,
  CASE WHEN sa THEN 'Service account ' || i ELSE 'User ' || i END,
  CASE WHEN i % 10 = 0 THEN 2 ELSE 1 END,
  i = 1, 1,
  datetime(1790000000 - 86400 * 400 + i * 600, 'unixepoch'), datetime(1790000000 - 86400 * 30 + (h % 86400), 'unixepoch'),
  0, datetime(1790000000 - (h / 16) % (86400 * 60), 'unixepoch'),
  (h / 4096) % 40 = 0, sa, printf('u%05d', i), (h / 65536) % 20 = 0
FROM u;

-- every user is in org 1 (service accounts too), every 10th is also in org 2
INSERT INTO org_user(org_id, user_id, role, created, updated)
SELECT 1, id, CASE WHEN id = 1 OR id % 50 = 0 THEN 'Admin' WHEN id % 4 = 0 THEN 'Editor' ELSE 'Viewer' END, created, created FROM `user`
UNION ALL
SELECT 2, id, CASE WHEN id % 40 = 0 THEN 'Admin' ELSE 'Viewer' END, created, created FROM `user` WHERE id % 10 = 0;

-- user_auth: 75 % of users logged in via oauth/ldap; every 5th of those has an older second row
INSERT INTO user_auth(user_id, auth_module, auth_id, created, external_uid, user_uid)
SELECT id, CASE WHEN id % 3 = 0 THEN 'ldap' ELSE 'oauth_generic_oauth' END, 'ext-' || id,
       datetime(1790000000 - 86400 * 10 - id * 60, 'unixepoch'), 'x' || id, uid
FROM `user` WHERE id % 4 <> 0 AND is_service_account = 0
UNION ALL
SELECT id, 'oauth_github', 'gh-' || id, datetime(1790000000 - 86400 * 200 - id * 60, 'unixepoch'), 'g' || id, uid
FROM `user` WHERE id % 5 = 0 AND id % 4 <> 0 AND is_service_account = 0;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 100)
INSERT INTO team(id, name, org_id, created, updated, uid, external_uid, is_provisioned, email)
SELECT i, (SELECT w FROM (SELECT 0 k, 'Platform' w UNION ALL SELECT 1, 'Operations' UNION ALL SELECT 2, 'Frontend'
             UNION ALL SELECT 3, 'Backend' UNION ALL SELECT 4, 'Data' UNION ALL SELECT 5, 'Security'
             UNION ALL SELECT 6, 'DevOps' UNION ALL SELECT 7, 'Mobile' UNION ALL SELECT 8, 'QA' UNION ALL SELECT 9, 'Design')
           WHERE k = i % 10) || ' ' || i,
       1, datetime(1790000000 - 86400 * 300 + i * 3600, 'unixepoch'), datetime(1790000000 - 86400 * 300 + i * 3600, 'unixepoch'),
       printf('t%03d', i), NULL, i % 9 = 0, 'team' || i || '@example.com'
FROM n;

-- team_member: each human user in up to 3 teams
INSERT INTO team_member(org_id, team_id, user_id, created, updated, external, permission, uid)
SELECT 1, team_id, user_id, '2025-06-01 00:00:00', '2025-06-01 00:00:00', (user_id + team_id) % 7 = 0,
       CASE WHEN (user_id + team_id) % 23 = 0 THEN 4 ELSE 0 END, 'tm-' || user_id || '-' || team_id
FROM (SELECT DISTINCT u.id AS user_id, ((u.id * m.m + m.o) % 100) + 1 AS team_id
      FROM `user` u, (SELECT 7 AS m, 0 AS o UNION ALL SELECT 13, 5 UNION ALL SELECT 29, 11) m
      WHERE u.is_service_account = 0);

-- roles: managed basic-role roles per org (1-6), global basic/fixed roles (7-40), managed user roles (100+user),
-- managed team roles (5000+team), one extsvc role
INSERT INTO role(id, name, description, version, org_id, uid, created, updated, display_name, group_name, hidden)
SELECT id, name, NULL, 1, org_id, 'r' || id, '2025-01-01 00:00:00', '2025-01-01 00:00:00', NULL, NULL, 0 FROM (
  SELECT 1 AS id, 'managed:builtins:viewer:permissions' AS name, 1 AS org_id UNION ALL
  SELECT 2, 'managed:builtins:editor:permissions', 1 UNION ALL SELECT 3, 'managed:builtins:admin:permissions', 1 UNION ALL
  SELECT 4, 'managed:builtins:viewer:permissions', 2 UNION ALL SELECT 5, 'managed:builtins:editor:permissions', 2 UNION ALL
  SELECT 6, 'managed:builtins:admin:permissions', 2 UNION ALL
  SELECT 7, 'basic:viewer', 0 UNION ALL SELECT 8, 'basic:editor', 0 UNION ALL SELECT 9, 'basic:admin', 0 UNION ALL
  SELECT 10, 'basic:grafana_admin', 0 UNION ALL SELECT 11, 'extsvc:grafana-oncall-app-permissions', 1);
WITH RECURSIVE n(i) AS (SELECT 12 UNION ALL SELECT i+1 FROM n WHERE i < 40)
INSERT INTO role(id, name, version, org_id, uid, created, updated, hidden)
SELECT i, 'fixed:role' || i || ':reader', 1, 0, 'fixed_' || i, '2025-01-01 00:00:00', '2025-01-01 00:00:00', 0 FROM n;
INSERT INTO role(id, name, version, org_id, uid, created, updated, hidden)
SELECT 100 + id, 'managed:users:' || id || ':permissions', 1, 1, 'mu' || id, created, created, 0 FROM `user` WHERE id <= 800;
INSERT INTO role(id, name, version, org_id, uid, created, updated, hidden)
SELECT 5000 + id, 'managed:teams:' || id || ':permissions', 1, 1, 'mt' || id, created, created, 0 FROM team;

INSERT INTO builtin_role(role, role_id, created, updated, org_id) VALUES
  ('Viewer', 1, '2025-01-01', '2025-01-01', 1), ('Editor', 2, '2025-01-01', '2025-01-01', 1), ('Admin', 3, '2025-01-01', '2025-01-01', 1),
  ('Viewer', 4, '2025-01-01', '2025-01-01', 2), ('Editor', 5, '2025-01-01', '2025-01-01', 2), ('Admin', 6, '2025-01-01', '2025-01-01', 2),
  ('Viewer', 7, '2025-01-01', '2025-01-01', 0), ('Editor', 8, '2025-01-01', '2025-01-01', 0), ('Admin', 9, '2025-01-01', '2025-01-01', 0),
  ('Grafana Admin', 10, '2025-01-01', '2025-01-01', 0), ('Editor', 11, '2025-01-01', '2025-01-01', 1);
INSERT INTO user_role(org_id, user_id, role_id, created, group_mapping_uid)
SELECT 1, id - 100, id, created, '' FROM role WHERE id BETWEEN 101 AND 900;
INSERT INTO team_role(org_id, team_id, role_id, created)
SELECT 1, id - 5000, id, created FROM role WHERE id > 5000;

-- permissions. Managed roles hold dashboard/folder grants (action sets plus the redundant individual actions).
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40),
acts(a, kind, k) AS (VALUES ('dashboards:view','dashboards',0),('dashboards:read','dashboards',1),('dashboards:edit','dashboards',2),
  ('dashboards:write','dashboards',3),('dashboards:delete','dashboards',4),('folders:view','folders',5),('folders:read','folders',6),
  ('folders:edit','folders',7),('dashboards:create','folders',8),('annotations:read','annotations',9))
INSERT OR IGNORE INTO permission(role_id, action, scope, created, updated, kind, attribute, identifier)
SELECT r.id, acts.a,
       CASE WHEN acts.kind = 'folders' THEN 'folders:uid:' || printf('f%04d', ((r.id * 31 + n.i * 7) % 300) + 1)
            WHEN acts.kind = 'annotations' THEN 'annotations:type:dashboard'
            ELSE 'dashboards:uid:' || printf('d%05d', ((r.id * 131 + n.i * 17) % 3000) + 301) END,
       '2025-01-01', '2025-01-01', acts.kind, 'uid',
       CASE WHEN acts.kind = 'folders' THEN printf('f%04d', ((r.id * 31 + n.i * 7) % 300) + 1)
            WHEN acts.kind = 'annotations' THEN 'dashboard'
            ELSE printf('d%05d', ((r.id * 131 + n.i * 17) % 3000) + 301) END
FROM role r, n, acts
WHERE r.name LIKE 'managed:%'
  AND n.i <= CASE WHEN r.id <= 6 THEN 40 WHEN r.id > 5000 THEN 6 ELSE 2 END
  AND (acts.k + n.i + r.id) % 3 <> 0;
INSERT OR IGNORE INTO permission(role_id, action, scope, created, updated, kind, attribute, identifier)
SELECT r.id, a.a, a.s, '2025-01-01', '2025-01-01', substr(a.a, 1, instr(a.a, ':') - 1), '*', '*'
FROM role r, (SELECT 'datasources:query' AS a, 'datasources:*' AS s UNION ALL SELECT 'datasources:read', 'datasources:*'
              UNION ALL SELECT 'alert.rules:read', 'folders:*' UNION ALL SELECT 'users:read', 'global.users:*'
              UNION ALL SELECT 'teams:read', 'teams:*') a
WHERE r.name LIKE 'fixed:%' OR r.name LIKE 'basic:%' OR r.name LIKE 'extsvc:%';

-- legacy dashboard table: ids 1-300 are folders, 301-3300 dashboards, 3301-3450 deleted dashboards
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 3450*(SELECT scale FROM _cfg)),
d AS (SELECT i, (i * 2654435761) % 4294967296 AS h, i <= 300 AS folder,
             i > 3300*(SELECT scale FROM _cfg) AS gone FROM n)
INSERT INTO dashboard(id, version, slug, title, data, org_id, created, updated, updated_by, created_by, gnet_id, plugin_id,
                      folder_id, is_folder, has_acl, uid, is_public, deleted, api_version, folder_uid)
SELECT i, 1 + (h % 8), CASE WHEN folder THEN 'folder-' || i ELSE 'dashboard-' || i END,
  CASE WHEN folder THEN 'Folder ' || i ELSE 'Service ' || (h % 97) || ' overview ' || i END,
  CASE WHEN folder THEN json_object('title', 'Folder ' || i, 'uid', printf('f%04d', i))
       ELSE json_object('title', 'Service ' || (h % 97) || ' overview ' || i, 'uid', printf('d%05d', i), 'schemaVersion', 41,
         'tags', json_array('svc' || (h % 13), CASE WHEN h % 2 = 0 THEN 'prod' ELSE 'staging' END),
         'panels', json_array(json_object('id', 1, 'type', 'timeseries', 'title', 'Requests',
                                          'targets', json_array(json_object('expr', 'sum(rate(http_requests_total[5m]))'))),
                              json_object('id', 2, 'type', 'stat', 'title', 'Errors'))) END,
  CASE WHEN i % 10 = 0 THEN 2 ELSE 1 END,
  datetime(1790000000 - 86400 * 365 + i * 3600, 'unixepoch'), datetime(1790000000 - (h / 8) % (86400 * 90), 'unixepoch'),
  ((h / 1024) % 1900) + 1, ((h / 65536) % 1900) + 1, NULL, NULL, 0, folder, 0,
  CASE WHEN folder THEN printf('f%04d', i) ELSE printf('d%05d', i) END, 0,
  CASE WHEN gone THEN datetime(1790000000 - (h % 86400) * 20, 'unixepoch') END,
  CASE WHEN folder THEN NULL ELSE 'v1' END,
  CASE WHEN folder THEN NULL WHEN (h / 32) % 10 = 0 THEN NULL ELSE printf('f%04d', ((h / 512) % 300) + 1) END
FROM d;

WITH RECURSIVE v(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM v WHERE k < 8)
INSERT INTO dashboard_version(dashboard_id, parent_version, restored_from, version, created, created_by, message, data, api_version)
SELECT d.id, v.k - 1, 0, v.k, datetime(strftime('%s', d.created) + v.k * 86400 * 7, 'unixepoch'),
       ((d.id * 7 + v.k) % 1900) + 1, CASE WHEN v.k % 3 = 0 THEN 'tweak thresholds' ELSE '' END,
       json_set(d.data, '$.version', v.k), d.api_version
FROM dashboard d, v WHERE d.is_folder = 0 AND v.k <= d.version;

INSERT INTO dashboard_provisioning(dashboard_id, name, external_id, updated, check_sum)
SELECT id, 'default', '/etc/grafana/dashboards/' || uid || '.json', 1790000000 - id, hex(id * 2654435761)
FROM dashboard WHERE is_folder = 0 AND id % 15 = 0;

-- unified storage: history rows per object (8 versions for hot ids, else 1-5); deleted dashboards end with action 3
WITH RECURSIVE v(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM v WHERE k < 30),
o AS (SELECT id, uid, title, is_folder, folder_uid, deleted IS NOT NULL AS gone, org_id,
             CASE WHEN id % 100 = 21 THEN 30 ELSE 1 + (id * 2654435761 / 64) % 5 END + (deleted IS NOT NULL) AS nv FROM dashboard),
h AS (SELECT o.*, v.k, 1780000000000000 + v.k * 100000000000 + o.id * 1000 AS rv FROM o, v WHERE v.k <= o.nv)
INSERT INTO resource_history(guid, resource_version, `group`, resource, namespace, name, value, action, label_set,
                             previous_resource_version, folder, generation, key_path)
SELECT printf('%08x-%04x-4%03x-a%03x-%012x', (id * 2654435761) % 4294967296, k, id % 4096, k % 4096, rv),
  rv,
  CASE WHEN is_folder THEN 'folder.grafana.app' ELSE 'dashboard.grafana.app' END,
  CASE WHEN is_folder THEN 'folders' ELSE 'dashboards' END,
  CASE WHEN org_id = 2 THEN 'org-2' ELSE 'default' END,
  uid,
  json_object('apiVersion', CASE WHEN is_folder THEN 'folder.grafana.app/v1beta1' ELSE 'dashboard.grafana.app/v1beta1' END,
    'kind', CASE WHEN is_folder THEN 'Folder' ELSE 'Dashboard' END,
    'metadata', json_object('name', uid, 'namespace', CASE WHEN org_id = 2 THEN 'org-2' ELSE 'default' END,
                            'resourceVersion', CAST(rv AS TEXT), 'generation', k,
                            'annotations', json_object('grafana.app/folder', coalesce(folder_uid, ''),
                                                       'grafana.app/updatedBy', 'user:u' || printf('%05d', (id + k) % 1900 + 1))),
    'spec', json_object('title', title, 'schemaVersion', 41, 'version', k,
                        'panels', json_array(json_object('id', 1, 'type', 'timeseries', 'title', 'Requests'),
                                             json_object('id', 2, 'type', 'stat', 'title', 'Errors')))),
  CASE WHEN gone AND k = nv THEN 3 WHEN k = 1 THEN 1 ELSE 2 END,
  NULL,
  CASE WHEN k = 1 THEN 0 ELSE rv - 100000000000 END,
  coalesce(folder_uid, ''), k,
  printf('unified/data/%s/%s/%s/%s/%d~%s~%s',
         CASE WHEN is_folder THEN 'folder.grafana.app' ELSE 'dashboard.grafana.app' END,
         CASE WHEN is_folder THEN 'folders' ELSE 'dashboards' END,
         CASE WHEN org_id = 2 THEN 'org-2' ELSE 'default' END, uid, rv,
         CASE WHEN gone AND k = nv THEN 'deleted' WHEN k = 1 THEN 'created' ELSE 'updated' END, coalesce(folder_uid, ''))
FROM h ORDER BY rv;

-- resource = latest non-deleted history row per object (what resource_insert_from_history.sql builds)
INSERT INTO resource(guid, resource_version, `group`, resource, namespace, name, value, action, label_set,
                     previous_resource_version, folder)
SELECT kv.guid, kv.resource_version, kv.`group`, kv.resource, kv.namespace, kv.name, kv.value, kv.action, kv.label_set,
       kv.previous_resource_version, kv.folder
FROM resource_history kv
JOIN (SELECT namespace, `group`, resource, name, max(resource_version) AS rv FROM resource_history
      GROUP BY namespace, `group`, resource, name) m
  ON m.namespace = kv.namespace AND m.`group` = kv.`group` AND m.resource = kv.resource AND m.name = kv.name
 AND m.rv = kv.resource_version
WHERE kv.action <> 3;

-- tags and annotations (epochs in ms over the last 30 days)
INSERT INTO tag(id, `key`, `value`)
SELECT row_number() OVER (), k, v FROM (
  SELECT 'env' AS k, v FROM (SELECT 'prod' AS v UNION ALL SELECT 'staging' UNION ALL SELECT 'dev')
  UNION ALL SELECT 'service', v FROM (SELECT 'api' AS v UNION ALL SELECT 'web' UNION ALL SELECT 'db' UNION ALL SELECT 'worker' UNION ALL SELECT 'auth')
  UNION ALL SELECT 'team', v FROM (SELECT 'platform' AS v UNION ALL SELECT 'payments' UNION ALL SELECT 'search')
  UNION ALL SELECT 'deploy', '' UNION ALL SELECT 'incident', '' UNION ALL SELECT 'release', '');

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 50000*(SELECT scale FROM _cfg)),
a AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO annotation(id, org_id, alert_id, user_id, dashboard_id, panel_id, category_id, type, title, text, metric,
                       prev_state, new_state, data, epoch, region_id, tags, created, updated, epoch_end, dashboard_uid)
SELECT i, 1,
  CASE WHEN (h / 8) % 10 = 0 THEN ((h / 64) % 500) + 1 ELSE 0 END,
  CASE WHEN (h / 8) % 10 = 0 THEN 0 ELSE ((h / 4096) % 1900) + 1 END,
  CASE WHEN (h / 16) % 10 = 1 THEN 0 ELSE ((h / 128) % 300) + 301 END,
  CASE WHEN (h / 16) % 10 = 1 THEN 0 ELSE ((h / 2) % 12) + 1 END,
  0, '', '',
  CASE WHEN (h / 8) % 10 = 0 THEN 'Alert state changed' ELSE 'Deployed build ' || (h % 9000) END,
  NULL,
  CASE WHEN (h / 8) % 10 = 0 THEN 'Normal' ELSE '' END,
  CASE WHEN (h / 8) % 10 = 0 THEN 'Alerting' ELSE '' END,
  CASE WHEN (h / 8) % 10 = 0 THEN json_object('values', json_object('B', (h % 1000) / 10.0)) ELSE '{}' END,
  1790000000000 - 86400000 * 30 + i * (86400000 * 30 / (50000*(SELECT scale FROM _cfg))),
  0,
  json_array('env:' || CASE (h / 32) % 3 WHEN 0 THEN 'prod' WHEN 1 THEN 'staging' ELSE 'dev' END,
             'service:' || CASE (h / 256) % 5 WHEN 0 THEN 'api' WHEN 1 THEN 'web' WHEN 2 THEN 'db' WHEN 3 THEN 'worker' ELSE 'auth' END),
  1790000000000 - 86400000 * 30 + i * (86400000 * 30 / (50000*(SELECT scale FROM _cfg))),
  1790000000000 - 86400000 * 30 + i * (86400000 * 30 / (50000*(SELECT scale FROM _cfg))),
  1790000000000 - 86400000 * 30 + i * (86400000 * 30 / (50000*(SELECT scale FROM _cfg)))
    + CASE WHEN (h / 1024) % 4 = 0 THEN (h % 3600) * 1000 ELSE 0 END,
  CASE WHEN (h / 16) % 10 = 1 THEN NULL ELSE printf('d%05d', ((h / 128) % 300) + 301) END
FROM a;

INSERT INTO annotation_tag(annotation_id, tag_id)
SELECT a.id, t.id FROM annotation a JOIN tag t
  ON (t.`key` = 'env' AND t.`value` = substr(json_extract(a.tags, '$[0]'), 5))
  OR (t.`key` = 'service' AND t.`value` = substr(json_extract(a.tags, '$[1]'), 9))
  OR (t.`key` = 'deploy' AND a.alert_id = 0 AND a.id % 3 = 0);

-- alerting: 500 rules in 40 folders, k8s_status JSON with state/health; 6 versions each
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 500*(SELECT scale FROM _cfg)),
r AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO alert_rule(id, org_id, title, condition, data, updated, interval_seconds, version, uid, namespace_uid, rule_group,
                       no_data_state, exec_err_state, `for`, annotations, labels, dashboard_uid, panel_id, rule_group_idx,
                       is_paused, notification_settings, record, metadata, updated_by, guid, keep_firing_for,
                       missing_series_evals_to_resolve, folder_fullpath, alert_routing_policy, k8s_status)
SELECT i, 1, 'High error rate ' || i, 'C',
  json_array(json_object('refId', 'A', 'datasourceUid', 'prom', 'model', json_object('expr', 'rate(errors_total[5m])')),
             json_object('refId', 'C', 'datasourceUid', '__expr__', 'model', json_object('type', 'threshold'))),
  datetime(1790000000 - (h % 864000), 'unixepoch'), 60, 6, printf('rule%04d', i), printf('f%04d', (i % 40) + 1),
  'group-' || ((i / 5) % 30), 'NoData', 'Error', 300000000000, json_object('summary', 'Errors on ' || i),
  json_object('severity', CASE (h / 8) % 3 WHEN 0 THEN 'critical' WHEN 1 THEN 'warning' ELSE 'info' END, 'team', 'team' || (i % 7)),
  CASE WHEN i % 3 = 0 THEN printf('d%05d', 301 + i) END, CASE WHEN i % 3 = 0 THEN 2 END, i % 5 + 1,
  i % 50 = 0, '', '', '{}', 'u00001', printf('g-%08x', h), 0, NULL, 'Folder ' || ((i % 40) + 1), NULL,
  json_object('state', CASE (h / 64) % 5 WHEN 0 THEN 'firing' WHEN 1 THEN 'pending' ELSE 'inactive' END,
              'health', CASE (h / 1024) % 8 WHEN 0 THEN 'error' WHEN 1 THEN 'nodata' ELSE 'ok' END)
FROM r;

WITH RECURSIVE v(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM v WHERE k < 6)
INSERT INTO alert_rule_version(rule_org_id, rule_uid, rule_namespace_uid, rule_group, parent_version, restored_from, version,
                               created, title, condition, data, interval_seconds, no_data_state, exec_err_state, `for`,
                               annotations, labels, rule_group_idx, is_paused, message, notification_settings, record,
                               metadata, created_by, rule_guid, keep_firing_for)
SELECT r.org_id, r.uid, r.namespace_uid, r.rule_group, v.k - 1, 0, v.k,
       datetime(1790000000 - (7 - v.k) * 86400 * 5, 'unixepoch'), r.title, r.condition, r.data, r.interval_seconds,
       r.no_data_state, r.exec_err_state, r.`for`, r.annotations, r.labels, r.rule_group_idx, r.is_paused, '', '', '',
       '{}', 'u00001', r.guid, 0
FROM alert_rule r, v;

INSERT OR IGNORE INTO star(user_id, dashboard_id, dashboard_uid, org_id, updated)
SELECT u.id, d.id, d.uid, 1, '2026-01-01 00:00:00'
FROM `user` u, (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2) k
JOIN dashboard d ON d.id = 301 + ((u.id * 37 + k.k * 101) % 3000)
WHERE u.is_service_account = 0 AND u.id % 2 = 1;

COMMIT;
