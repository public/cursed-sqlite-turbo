-- Grafana (grafana/grafana @ 05e78bb, AGPL-3.0). Each statement is quoted from the pinned source with attribution.
-- Most of Grafana's SQL is text/template files (sqltemplate: {{ .Ident }} quotes with "..." on SQLite, {{ .Arg }}
-- becomes a ? placeholder) or Go string building; each query below is one rendered instantiation (tagged dynamic),
-- with placeholders numbered ?N in argument order. Rendered-SQL golden files for SQLite live next to each template
-- (testdata/sqlite--*.sql) and were used to check the rendering. Template table names carry no schema prefix at
-- runtime (the golden files use "grafana"/"test_schema" only because the tests set one).

-- ===== unified storage (pkg/storage/unified/sql): dashboards and folders live in resource / resource_history =====

-- @id grafana.unified.resource_read
-- @src pkg/storage/unified/sql/data/resource_read.sql:1-16
-- @style sqltemplate, ? positional
-- @tags hot-small,hotpath,dynamic
-- @note Open a dashboard: point read of the current object by (namespace, group, resource, name) on the unique index.
-- @param ?1 'default'
-- @param ?2 'dashboard.grafana.app'
-- @param ?3 'dashboards'
-- @param ?4 'd00421'
SELECT
    "guid",
    "namespace",
    "group",
    "resource",
    "name",
    "folder",
    "resource_version",
    "value"
    FROM "resource"
    WHERE 1 = 1
        AND "namespace" = ?1
        AND "group"     = ?2
        AND "resource"  = ?3
        AND "name"      = ?4
;

-- @id grafana.unified.resource_list
-- @src pkg/storage/unified/sql/data/resource_list.sql:1-27
-- @style sqltemplate, ? positional, optional key filters
-- @tags hotpath,dynamic
-- @note List all dashboards of an org (namespace + group + resource), ordered by namespace, name; returns the JSON values.
-- @param ?1 'default'
-- @param ?2 'dashboard.grafana.app'
-- @param ?3 'dashboards'
SELECT
    "guid",
    "resource_version",
    "namespace",
    "group",
    "resource",
    "name",
    "folder",
    "value"
    FROM "resource"
    WHERE 1 = 1
            AND "namespace" = ?1
            AND "group"     = ?2
            AND "resource"  = ?3
    ORDER BY "namespace" ASC, "name" ASC
;

-- @id grafana.unified.resource_history_list
-- @src pkg/storage/unified/sql/data/resource_history_list.sql:1-57
-- @style sqltemplate, ? positional, key filters repeated inside and outside the derived table
-- @tags hotpath,dynamic
-- @note List at a past resourceVersion: GROUP BY max(resource_version) per object in a derived table, joined back on 5 columns, deletes excluded, paged.
-- @param ?1 1780300000000000
-- @param ?2 'default'
-- @param ?3 'dashboard.grafana.app'
-- @param ?4 'dashboards'
-- @param ?5 'default'
-- @param ?6 'dashboard.grafana.app'
-- @param ?7 'dashboards'
-- @param ?8 50
-- @param ?9 0
SELECT
    kv."guid",
    kv."resource_version",
    kv."namespace",
    kv."group",
    kv."resource",
    kv."name",
    kv."folder",
    kv."value"
    FROM "resource_history" as kv
    INNER JOIN  (
        SELECT "namespace", "group", "resource", "name",  max("resource_version") AS "resource_version"
        FROM "resource_history" AS mkv
        WHERE 1 = 1
            AND "resource_version" <=  ?1
                AND "namespace" = ?2
                AND "group"     = ?3
                AND "resource"  = ?4
        GROUP BY mkv."namespace", mkv."group", mkv."resource", mkv."name"
    ) AS maxkv
    ON
        maxkv."resource_version"  = kv."resource_version"
        AND maxkv."namespace"     = kv."namespace"
        AND maxkv."group"         = kv."group"
        AND maxkv."resource"      = kv."resource"
        AND maxkv."name"          = kv."name"
    WHERE kv."action"  != 3
        AND kv."namespace" = ?5
        AND kv."group"     = ?6
        AND kv."resource"  = ?7
    ORDER BY kv."namespace" ASC, kv."name" ASC
    LIMIT ?8 OFFSET ?9
;

-- @id grafana.unified.resource_history_poll
-- @src pkg/storage/unified/sql/data/resource_history_poll.sql:1-19
-- @style sqltemplate, ? positional
-- @tags hotpath,dynamic
-- @note Watch poller (runs every ~100 ms per group/resource): all history rows after the last seen resource_version.
-- @param ?1 'dashboard.grafana.app'
-- @param ?2 'dashboards'
-- @param ?3 1780500000000000
SELECT
    "guid",
    "resource_version",
    "namespace",
    "group",
    "resource",
    "name",
    "folder",
    "value",
    "action",
    "previous_resource_version"

    FROM "resource_history"
    WHERE 1 = 1
    AND "group" = ?1
    AND "resource" = ?2
    AND "resource_version" > ?3
    ORDER BY "resource_version" ASC
;

-- @id grafana.unified.resource_stats.folders
-- @src pkg/storage/unified/sql/data/resource_stats.sql:1-24
-- @style sqltemplate, ? positional, folder IN list
-- @tags dynamic
-- @note Folder view counts (dashboards/alert rules/... per folder set): COUNT and MAX(resource_version) grouped by namespace, group, resource.
-- @param ?1 'default'
-- @param ?2 'f0011'
-- @param ?3 'f0012'
-- @param ?4 'f0013'
-- @param ?5 'f0014'
-- @param ?6 'f0015'
SELECT
  "namespace",
  "group",
  "resource",
  COUNT(*),
  MAX("resource_version")
FROM "resource"
WHERE 1 = 1
  AND "namespace" = ?1
  AND "folder" IN (?2, ?3, ?4, ?5, ?6)
GROUP BY
  "namespace",
  "group",
  "resource"
;

-- @id grafana.unified.resource_history_read
-- @src pkg/storage/unified/sql/data/resource_history_read.sql:1-24
-- @style sqltemplate, ? positional
-- @tags hot-small,dynamic
-- @note Read an object at a given resourceVersion: newest history row at or below it (top-1 on the unique index).
-- @param ?1 'default'
-- @param ?2 'dashboard.grafana.app'
-- @param ?3 'dashboards'
-- @param ?4 'd00421'
-- @param ?5 1781500000000000
SELECT
    "guid",
    "namespace",
    "group",
    "resource",
    "name",
    "folder",
    "resource_version",
    "action",
    "value"

    FROM "resource_history"

    WHERE 1 = 1
        AND "namespace" = ?1
        AND "group"     = ?2
        AND "resource"  = ?3
        AND "name"      = ?4
        AND "resource_version" <= ?5
    ORDER BY "resource_version" DESC
    LIMIT 1
;

-- @id grafana.unified.resource_update
-- @src pkg/storage/unified/sql/data/resource_update.sql:1-14
-- @style sqltemplate, ? positional
-- @tags hot-small,dynamic
-- @note Save a dashboard: optimistic-concurrency UPDATE of the current row (WHERE resource_version = previous RV).
-- @param ?1 '0c2f8a52-001f-41a5-a01f-065b7a3c6d10'
-- @param ?2 '{"apiVersion":"dashboard.grafana.app/v1beta1","kind":"Dashboard","metadata":{"name":"d00421","namespace":"default","generation":31},"spec":{"title":"Service 7 overview 421","schemaVersion":41,"panels":[]}}'
-- @param ?3 'f0101'
-- @param ?4 2
-- @param ?5 1783000100000000
-- @param ?6 'dashboard.grafana.app'
-- @param ?7 'dashboards'
-- @param ?8 'default'
-- @param ?9 'd00421'
-- @param ?10 1783000000421000
UPDATE "resource"
    SET
        "guid"   = ?1,
        "value"  = ?2,
        "folder"  = ?3,
        "action" = ?4,
        "resource_version" = ?5
    WHERE 1 = 1
        AND "group"     = ?6
        AND "resource"  = ?7
        AND "namespace" = ?8
        AND "name"      = ?9
        AND "resource_version" = ?10
;

-- @id grafana.unified.resource_history_insert
-- @src pkg/storage/unified/sql/data/resource_history_insert.sql:1-35
-- @style sqltemplate, ? positional (resource_version branch taken)
-- @tags hot-small,dynamic
-- @note Every write appends a history row (same transaction as resource_update).
-- @param ?1 '0c2f8a52-001f-41a5-a01f-065b7a3c6d10'
-- @param ?2 'dashboard.grafana.app'
-- @param ?3 'dashboards'
-- @param ?4 'default'
-- @param ?5 'd00421'
-- @param ?6 'f0101'
-- @param ?7 1783000100000000
-- @param ?8 1783000000421000
-- @param ?9 31
-- @param ?10 '{"apiVersion":"dashboard.grafana.app/v1beta1","kind":"Dashboard","metadata":{"name":"d00421","namespace":"default","generation":31},"spec":{"title":"Service 7 overview 421","schemaVersion":41,"panels":[]}}'
-- @param ?11 2
-- @param ?12 'unified/data/dashboard.grafana.app/dashboards/default/d00421/1783000100000000~updated~f0101'
INSERT INTO "resource_history"
    (
        "guid",
        "group",
        "resource",
        "namespace",
        "name",
        "folder",
        "resource_version",
        "previous_resource_version",
        "generation",
        "value",
        "action",
        "key_path"
    )

    VALUES (
        ?1,
        ?2,
        ?3,
        ?4,
        ?5,
        ?6,
        ?7,
        ?8,
        ?9,
        ?10,
        ?11,
        ?12
    )
;

-- @id grafana.unified.resource_trash
-- @src pkg/storage/unified/sql/data/resource_trash.sql:1-54
-- @style sqltemplate, ? positional
-- @tags dynamic
-- @note "Recently deleted" page: newest delete event per name (GROUP BY derived table) whose object no longer exists (correlated NOT EXISTS).
-- @param ?1 'default'
-- @param ?2 'dashboard.grafana.app'
-- @param ?3 'dashboards'
-- @param ?4 'default'
-- @param ?5 'dashboard.grafana.app'
-- @param ?6 'dashboards'
SELECT
  h."guid",
  h."resource_version",
  h."namespace",
  h."group",
  h."resource",
  h."name",
  h."folder",
  h."value"
FROM "resource_history" h
INNER JOIN (
  SELECT "name", MAX("resource_version") as max_rv
  FROM "resource_history"
  WHERE 1 = 1
    AND "namespace" = ?1
    AND "group"     = ?2
    AND "resource"  = ?3
    AND "action" = 3
  GROUP BY "name"
) max_versions ON h."name" = max_versions."name"
  AND h."resource_version" = max_versions.max_rv
WHERE 1 = 1
  AND h."namespace" = ?4
  AND h."group"     = ?5
  AND h."resource"  = ?6
  AND h."action" = 3
  AND NOT EXISTS (
    SELECT 1 FROM "resource" r
    WHERE r."namespace" = h."namespace"
      AND r."group" = h."group"
      AND r."resource" = h."resource"
      AND r."name" = h."name"
  )
ORDER BY h."resource_version" DESC
;

-- @id grafana.unified.resource_history_prune
-- @src pkg/storage/unified/sql/data/resource_history_prune.sql:1-27
-- @style sqltemplate, ? positional (PartitionByGeneration false)
-- @tags dynamic
-- @note After each write: keep the newest N versions of one object, DELETE ... WHERE guid IN (ROW_NUMBER() OVER (PARTITION BY ...) > N).
-- @param ?1 'default'
-- @param ?2 'dashboard.grafana.app'
-- @param ?3 'dashboards'
-- @param ?4 'd00421'
-- @param ?5 20
DELETE FROM "resource_history"
WHERE "guid" IN (
  SELECT "guid"
  FROM (
  SELECT
    "guid",
    ROW_NUMBER() OVER (
      PARTITION BY "namespace"
        , "group"
        , "resource"
        , "name"
      ORDER BY "resource_version" DESC
    ) AS "rn"
  FROM "resource_history"
  WHERE "namespace" = ?1
    AND "group" = ?2
    AND "resource" = ?3
    AND "name" = ?4
  ) AS "ranked"
  WHERE "rn" > ?5
);

-- @id grafana.unified.history_gc_candidates
-- @src pkg/storage/unified/sql/data/resource_history_gc_get_candidates.sql:1-16
-- @style sqltemplate, ? positional
-- @tags dynamic
-- @note History GC: DISTINCT (namespace, name) of objects deleted before a cutoff that are gone from resource (NOT EXISTS), batched.
-- @param ?1 'dashboard.grafana.app'
-- @param ?2 'dashboards'
-- @param ?3 1785000000000000
-- @param ?4 100
SELECT DISTINCT "namespace",
                "name"
FROM "resource_history" h
WHERE h."group" = ?1
  AND h."resource" = ?2
  AND h."action" = 3
  AND h."resource_version" < ?3
  AND NOT EXISTS (
    SELECT 1 FROM "resource" r
    WHERE r."namespace" = h."namespace"
      AND r."group" = h."group"
      AND r."resource" = h."resource"
      AND r."name" = h."name"
  )
LIMIT ?4;

-- ===== legacy dashboard tables (read by the dashboard API's legacy storage / migration to unified storage) =====

-- @id grafana.legacy.dashboards_page
-- @src pkg/registry/apis/dashboard/legacy/query_dashboards.sql:1-94
-- @style sqltemplate, ? positional; plain-table branch with MaxRows and LastID
-- @tags hotpath,dynamic
-- @note List dashboards from the legacy table: 4-way LEFT JOIN (provisioning, created/updated user), keyset page id < ? ORDER BY id DESC LIMIT.
-- @param ?1 0
-- @param ?2 1
-- @param ?3 2000
-- @param ?4 100
SELECT
  dashboard.org_id,
  dashboard.id,
  dashboard.uid,
  dashboard.title,
  dashboard.folder_uid,
  dashboard.deleted,
  plugin_id,
  provisioning.name        as repo_name,
  provisioning.external_id as repo_path,
  provisioning.check_sum   as repo_hash,
  provisioning.updated     as repo_ts,
  dashboard.created,
  created_user.uid         as created_by,
  dashboard.created_by     as created_by_id,
  dashboard.updated,
  updated_user.uid       as updated_by,
  dashboard.updated_by   as updated_by_id,
  dashboard.version,
  '' as message,
  dashboard.data,
  dashboard.api_version
FROM "dashboard" as dashboard
LEFT OUTER JOIN "dashboard_provisioning" as provisioning ON dashboard.id = provisioning.dashboard_id
LEFT OUTER JOIN "user" as created_user ON dashboard.created_by = created_user.id
LEFT OUTER JOIN "user" as updated_user ON dashboard.updated_by = updated_user.id
WHERE dashboard.is_folder = ?1
  AND dashboard.org_id = ?2
  AND dashboard.id < ?3
  AND dashboard.deleted IS NULL
  ORDER BY dashboard.id DESC
  LIMIT ?4;

-- @id grafana.legacy.dashboard_history
-- @src pkg/registry/apis/dashboard/legacy/query_dashboards.sql:1-94
-- @style sqltemplate, ? positional; history branch (GetHistory, UID, Order DESC, MaxRows)
-- @tags hotpath,dynamic
-- @note Dashboard "Versions" tab: dashboard JOIN dashboard_version with provisioning and two user joins, ordered by version created DESC.
-- @param ?1 0
-- @param ?2 1
-- @param ?3 'd00427'
-- @param ?4 20
SELECT
  dashboard.org_id,
  dashboard.id,
  dashboard.uid,
  dashboard.title,
  dashboard.folder_uid,
  dashboard.deleted,
  plugin_id,
  provisioning.name        as repo_name,
  provisioning.external_id as repo_path,
  provisioning.check_sum   as repo_hash,
  provisioning.updated     as repo_ts,
  dashboard.created,
  created_user.uid         as created_by,
  dashboard.created_by     as created_by_id,
  dashboard_version.created as updated,
  updated_user.uid       as updated_by,
  dashboard_version.created_by as updated_by_id,
  dashboard_version.version,
  dashboard_version.message,
  dashboard_version.data,
  dashboard_version.api_version
FROM "dashboard" as dashboard
LEFT OUTER JOIN "dashboard_version" as dashboard_version ON dashboard.id = dashboard_version.dashboard_id
LEFT OUTER JOIN "dashboard_provisioning" as provisioning ON dashboard.id = provisioning.dashboard_id
LEFT OUTER JOIN "user" as created_user ON dashboard.created_by = created_user.id
LEFT OUTER JOIN "user" as updated_user ON dashboard_version.created_by = updated_user.id
WHERE dashboard.is_folder = ?1
  AND dashboard.org_id = ?2
  AND dashboard.uid = ?3
  ORDER BY
    dashboard_version.created DESC,
    dashboard_version.version DESC,
    dashboard.uid ASC
  LIMIT ?4;

-- ===== annotations (pkg/services/annotations/annotationsimpl/xorm_store.go) =====

-- @id grafana.annotations.dashboard_range
-- @src pkg/services/annotations/annotationsimpl/xorm_store.go:321-466
-- @style ? positional, Go string building (bytes.Buffer) plus getAccessControlFilter
-- @tags hotpath,dynamic
-- @note Annotations overlay on a dashboard over 7 days: inner id subquery (org, dashboard_uid, epoch range, access filter, top-N by epoch_end DESC) joined back to annotation, user and alert_rule.
-- @param ?1 1
-- @param ?2 'd00342'
-- @param ?3 1790000000000
-- @param ?4 1789395200000
-- @param ?5 'd00342'
SELECT
  annotation.id,
  annotation.epoch as time,
  annotation.epoch_end as time_end,
  annotation.dashboard_uid,
  annotation.dashboard_id,
  annotation.panel_id,
  annotation.new_state,
  annotation.prev_state,
  annotation.alert_id,
  annotation.text,
  annotation.tags,
  annotation.data,
  annotation.created,
  annotation.updated,
  usr.email,
  usr.login,
  usr.uid as user_uid,
  r.title as alert_name
FROM annotation
LEFT OUTER JOIN `user` as usr on usr.id = annotation.user_id
LEFT OUTER JOIN alert_rule as r on r.id = annotation.alert_id
INNER JOIN (
  SELECT a.id from annotation a
  WHERE a.org_id = ?1 AND a.dashboard_uid = ?2 AND a.epoch <= ?3 AND a.epoch_end >= ?4
   AND (a.dashboard_id = 0 OR a.dashboard_uid = ?5)
   ORDER BY a.org_id, a.epoch_end DESC, a.epoch DESC LIMIT 100 OFFSET 0 ) dt on dt.id = annotation.id;

-- @id grafana.annotations.org_tags_match_all
-- @src pkg/services/annotations/annotationsimpl/xorm_store.go:321-466
-- @style ? positional, Go string building; tag filter subquery with matchAny=false
-- @tags hotpath,dynamic
-- @note Annotation query by tags (env:prod AND service:api) for the org: correlated SUM(1) over annotation_tag JOIN tag compared to the tag count, access filter with dashboard_uid IN list.
-- @param ?1 1
-- @param ?2 1790000000000
-- @param ?3 1789395200000
-- @param ?4 'env'
-- @param ?5 'prod'
-- @param ?6 'service'
-- @param ?7 'api'
-- @param ?8 'd00301'
-- @param ?9 'd00305'
-- @param ?10 'd00310'
-- @param ?11 'd00342'
-- @param ?12 'd00377'
-- @param ?13 'd00420'
SELECT
  annotation.id,
  annotation.epoch as time,
  annotation.epoch_end as time_end,
  annotation.dashboard_uid,
  annotation.dashboard_id,
  annotation.panel_id,
  annotation.new_state,
  annotation.prev_state,
  annotation.alert_id,
  annotation.text,
  annotation.tags,
  annotation.data,
  annotation.created,
  annotation.updated,
  usr.email,
  usr.login,
  usr.uid as user_uid,
  r.title as alert_name
FROM annotation
LEFT OUTER JOIN `user` as usr on usr.id = annotation.user_id
LEFT OUTER JOIN alert_rule as r on r.id = annotation.alert_id
INNER JOIN (
  SELECT a.id from annotation a
  WHERE a.org_id = ?1 AND a.epoch <= ?2 AND a.epoch_end >= ?3 AND a.alert_id = 0 AND (
    SELECT SUM(1) FROM annotation_tag `at`
    INNER JOIN tag on tag.id = `at`.tag_id
    WHERE `at`.annotation_id = a.id
      AND (
      (tag.`key` = ?4 AND tag.`value` = ?5) OR (tag.`key` = ?6 AND tag.`value` = ?7)
      )
  ) = 2  AND (a.dashboard_id = 0 OR a.dashboard_uid IN (?8,?9,?10,?11,?12,?13))
   ORDER BY a.org_id, a.epoch_end DESC, a.epoch DESC LIMIT 100 OFFSET 0 ) dt on dt.id = annotation.id;

-- @id grafana.annotations.get_tags
-- @src pkg/services/annotations/annotationsimpl/xorm_store.go:579-645
-- @style ? positional, Go string building; LikeOperator adds the % wildcards to the arguments
-- @tags dynamic
-- @note Tag autocomplete: tag JOIN annotation_tag JOIN annotation, LIKE on key or value, GROUP BY key, value with count(*), LIMIT.
-- @param ?1 1
-- @param ?2 '%ser%'
-- @param ?3 '%ser%'
SELECT
  tag.`key`,
  tag.`value`,
  count(*) as count
FROM tag
INNER JOIN annotation_tag ON tag.id = annotation_tag.tag_id
INNER JOIN annotation ON annotation.id = annotation_tag.annotation_id
WHERE annotation.org_id = ?1 AND (tag.`key` LIKE ?2 OR tag.`value` LIKE ?3) GROUP BY tag.`key`,tag.`value` ORDER BY tag.`key`,tag.`value` LIMIT 100;

-- ===== access control (pkg/services/accesscontrol) =====

-- @id grafana.accesscontrol.user_permissions
-- @src pkg/services/accesscontrol/database/database.go:60-104
-- @style ? positional, Go string building: UserRolesFilter + RolePrefixesFilter + ManagedPermissionsActionSetsFilter (pkg/services/accesscontrol/filter.go:136-220)
-- @tags hotpath,dynamic
-- @note Loaded on every request with a cold permission cache: permission JOIN role JOIN a UNION of user, team and basic-role assignments; LIKE role prefixes and a NOT(... NOT IN ...) action-set filter.
-- @param ?1 42
-- @param ?2 1
-- @param ?3 0
-- @param ?4 95
-- @param ?5 52
-- @param ?6 30
-- @param ?7 1
-- @param ?8 'Viewer'
-- @param ?9 1
-- @param ?10 0
-- @param ?11 'managed:%'
-- @param ?12 'extsvc:%'
SELECT
  permission.action,
  permission.scope
  FROM permission
  INNER JOIN role ON role.id = permission.role_id
INNER JOIN (
  SELECT ur.role_id
  FROM user_role AS ur
  WHERE ur.user_id = ?1
  AND (ur.org_id = ?2 OR ur.org_id = ?3)
UNION
  SELECT tr.role_id FROM team_role as tr
  WHERE tr.team_id IN(?4, ?5, ?6)
  AND tr.org_id = ?7
UNION
  SELECT br.role_id FROM builtin_role AS br
  WHERE br.role IN (?8)
  AND (br.org_id = ?9 OR br.org_id = ?10)
) as all_role ON role.id = all_role.role_id WHERE ( role.name LIKE ?11 OR role.name LIKE ?12 ) AND NOT (
    role.name LIKE 'managed:%'
    AND permission.kind IN ('dashboards', 'folders')
    AND permission.action NOT IN (
      'dashboards:view', 'dashboards:edit', 'dashboards:admin',
      'folders:view', 'folders:edit', 'folders:admin'
    )
  );

-- @id grafana.accesscontrol.teams_permissions
-- @src pkg/services/accesscontrol/database/database.go:140-209
-- @style ? positional, Go string building (team IN list, RolePrefixesFilter, ManagedPermissionsActionSetsFilter)
-- @tags dynamic
-- @note Team permission cache fill: permission JOIN role JOIN team_role derived table, with the role-prefix LIKEs and action-set exclusion.
-- @param ?1 95
-- @param ?2 52
-- @param ?3 30
-- @param ?4 1
-- @param ?5 'managed:%'
-- @param ?6 'extsvc:%'
SELECT
  permission.action,
  permission.scope,
  all_role.team_id
FROM permission
INNER JOIN role ON role.id = permission.role_id
INNER JOIN (
  SELECT tr.role_id, tr.team_id FROM team_role as tr
  WHERE tr.team_id IN(?1, ?2, ?3)
    AND tr.org_id = ?4
) as all_role ON role.id = all_role.role_id
 WHERE ( role.name LIKE ?5 OR role.name LIKE ?6 ) AND NOT (
    role.name LIKE 'managed:%'
    AND permission.kind IN ('dashboards', 'folders')
    AND permission.action NOT IN (
      'dashboards:view', 'dashboards:edit', 'dashboards:admin',
      'folders:view', 'folders:edit', 'folders:admin'
    )
  );

-- ===== users, teams, orgs (sqltemplate files) =====

-- @id grafana.user.signed_in_user
-- @src pkg/services/user/userimpl/queries/get_signed_in_user.sql:1-28
-- @style sqltemplate, ? positional (UserID branch, explicit OrgID)
-- @tags hot-small,hotpath,dynamic
-- @note Resolve the signed-in user for a request (session cache miss): user LEFT JOIN org_user (org-scoped) LEFT JOIN org, by id.
-- @param ?1 1
-- @param ?2 42
SELECT
  u.id AS user_id,
  u.uid AS user_uid,
  u.is_admin AS is_grafana_admin,
  u.email AS email,
  u.email_verified AS email_verified,
  u.login AS login,
  u.name AS name,
  u.is_disabled AS is_disabled,
  u.help_flags1 AS help_flags1,
  u.last_seen_at AS last_seen_at,
  org.name AS org_name,
  org_user.role AS org_role,
  org.id AS org_id,
  u.is_service_account AS is_service_account
FROM "user" AS u
LEFT OUTER JOIN "org_user" AS org_user
  ON org_user.org_id = ?1
  AND org_user.user_id = u.id
LEFT OUTER JOIN "org" AS org
  ON org.id = org_user.org_id
WHERE u.id = ?2;

-- @id grafana.user.signed_in_user_by_login
-- @src pkg/services/user/userimpl/queries/get_signed_in_user.sql:1-28
-- @style sqltemplate, ? positional (Login branch, OrgID 0 so the join uses u.org_id)
-- @tags dynamic
-- @note Login / auth-proxy lookup: case-insensitive LOWER(login) = LOWER(?) (not indexable) with the org joins.
-- @param ?1 'Ops17'
SELECT
  u.id AS user_id,
  u.uid AS user_uid,
  u.is_admin AS is_grafana_admin,
  u.email AS email,
  u.email_verified AS email_verified,
  u.login AS login,
  u.name AS name,
  u.is_disabled AS is_disabled,
  u.help_flags1 AS help_flags1,
  u.last_seen_at AS last_seen_at,
  org.name AS org_name,
  org_user.role AS org_role,
  org.id AS org_id,
  u.is_service_account AS is_service_account
FROM "user" AS u
LEFT OUTER JOIN "org_user" AS org_user
  ON org_user.org_id = u.org_id
  AND org_user.user_id = u.id
LEFT OUTER JOIN "org" AS org
  ON org.id = org_user.org_id
WHERE LOWER(u.login) = LOWER(?1);

-- @id grafana.user.search
-- @src pkg/services/user/userimpl/queries/search_users.sql:1-68
-- @style sqltemplate, ? positional; server-admin user list (AccessAll, query "ops", page 1 of 50)
-- @tags hotpath,dynamic
-- @note Admin users page: LEFT JOIN user_auth ON id = correlated (ORDER BY created DESC LIMIT 1) subquery, 3-way LIKE '%q%', ORDER BY login, email, paged.
-- @param ?1 '%ops%'
-- @param ?2 '%ops%'
-- @param ?3 '%ops%'
-- @param ?4 50
-- @param ?5 0
SELECT
  u.id,
  u.uid,
  u.email,
  u.name,
  u.login,
  u.is_admin,
  u.is_disabled,
  u.last_seen_at,
  user_auth.auth_module,
  u.is_provisioned,
  u.created
FROM "user" AS u
LEFT JOIN "user_auth" AS user_auth ON user_auth.id = (
  SELECT id
  FROM "user_auth" AS user_auth
  WHERE user_auth.user_id = u.id
  ORDER BY user_auth.created DESC
  LIMIT 1
)
WHERE u.is_service_account = FALSE
AND (
    u.email LIKE ?1
    OR u.name LIKE ?2
    OR u.login LIKE ?3
  )
ORDER BY u.login ASC, u.email ASC
LIMIT ?4 OFFSET ?5;

-- @id grafana.team.search
-- @src pkg/services/team/teamimpl/queries/search_teams.sql:1-47
-- @style sqltemplate, ? positional; teams page (AccessAll, name pattern, default sort, page of 30)
-- @tags hotpath,dynamic
-- @note Teams list: correlated COUNT(*) member_count subquery per team, LIKE on name, ORDER BY name, paged.
-- @param ?1 1
-- @param ?2 '%op%'
-- @param ?3 30
-- @param ?4 0
SELECT
  team.id AS id,
  team.uid,
  team.org_id,
  team.name AS name,
  team.email AS email,
  team.external_uid AS external_uid,
  team.is_provisioned AS is_provisioned,
  (
    SELECT COUNT(*)
    FROM "team_member" AS team_member
    WHERE team_member.team_id = team.id
  ) AS member_count
FROM "team" AS team
WHERE team.org_id = ?1
  AND team.name LIKE ?2
ORDER BY
  team.name ASC
LIMIT ?3 OFFSET ?4;

-- @id grafana.team.members
-- @src pkg/services/team/teamimpl/queries/get_team_members.sql:1-45
-- @style sqltemplate, ? positional (AccessAll, OrgID, TeamID)
-- @tags hotpath,dynamic
-- @note Team members tab: team_member JOIN user JOIN team, LEFT JOIN user_auth via correlated latest-row subquery, ordered by login, email.
-- @param ?1 0
-- @param ?2 1
-- @param ?3 30
SELECT
  team_member.org_id,
  team_member.team_id,
  team_member.user_id,
  team_member.uid,
  team_user.email,
  team_user.name,
  team_user.login,
  team_user.uid AS user_uid,
  team_member.external,
  team_member.permission,
  user_auth.auth_module,
  team.uid AS team_uid
FROM "team_member" AS team_member
INNER JOIN "user" AS team_user ON team_member.user_id = team_user.id
INNER JOIN "team" AS team ON team.id = team_member.team_id
LEFT JOIN "user_auth" AS user_auth ON user_auth.id = (
  SELECT id
  FROM "user_auth" AS user_auth
  WHERE user_auth.user_id = team_member.user_id
  ORDER BY user_auth.created DESC
  LIMIT 1
)
WHERE team_user.is_service_account = ?1
  AND team_member.org_id = ?2
  AND team_member.team_id = ?3
ORDER BY team_user.login ASC, team_user.email ASC;

-- @id grafana.team.ids_by_user
-- @src pkg/services/team/teamimpl/queries/get_team_ids_by_user.sql:1-6
-- @style sqltemplate, ? positional
-- @tags hot-small,hotpath,dynamic
-- @note Per-request identity resolution: the signed-in user's team ids and uids.
-- @param ?1 42
-- @param ?2 1
SELECT team_member.team_id, team.uid
FROM "team_member" AS team_member
INNER JOIN "team" AS team ON team.id = team_member.team_id
WHERE team_member.user_id = ?1
  AND team_member.org_id = ?2
ORDER BY team_member.team_id ASC;

-- @id grafana.org.search_users
-- @src pkg/services/org/orgimpl/queries/search_org_users.sql:1-44
-- @style sqltemplate, ? positional (AccessAll, query "ops", default sort, page of 30)
-- @tags hotpath,dynamic
-- @note Org users page: org_user JOIN user, 3-way LIKE, ORDER BY login, email, paged.
-- @param ?1 1
-- @param ?2 '%ops%'
-- @param ?3 '%ops%'
-- @param ?4 '%ops%'
-- @param ?5 30
-- @param ?6 0
SELECT
  org_user.org_id,
  org_user.user_id,
  u.email,
  u.uid,
  u.name,
  u.login,
  org_user.role,
  u.last_seen_at,
  u.created,
  u.updated,
  u.is_disabled,
  u.is_provisioned
FROM "org_user" AS org_user
INNER JOIN "user" AS u ON org_user.user_id = u.id
WHERE org_user.org_id = ?1
  AND u.is_service_account = FALSE
  AND (
    u.email LIKE ?2
    OR u.name LIKE ?3
    OR u.login LIKE ?4
  )
ORDER BY
  u.login ASC, u.email ASC
LIMIT ?5 OFFSET ?6;

-- @id grafana.org.user_org_list
-- @src pkg/services/org/orgimpl/queries/get_user_org_list.sql:1-7
-- @style sqltemplate, ? positional
-- @tags dynamic
-- @note Org switcher: the user's orgs with role, 3-way join ordered by org name.
-- @param ?1 40
SELECT org.name, org_user.role, org_user.org_id
FROM "org_user" AS org_user
INNER JOIN "org" AS org ON org_user.org_id = org.id
INNER JOIN "user" AS u ON org_user.user_id = u.id
WHERE org_user.user_id = ?1
  AND u.is_service_account = FALSE
ORDER BY org.name;

-- @id grafana.star.is_starred
-- @src pkg/services/star/starimpl/xorm_store.go:24-38
-- @style ? positional, raw SQL
-- @tags hot-small,hotpath
-- @note Dashboard header star icon: existence check on the (user_id, dashboard_uid, org_id) unique index.
-- @param ?1 41
-- @param ?2 'd01818'
-- @param ?3 1
SELECT 1 from star where user_id=?1 and dashboard_uid=?2 and org_id=?3;

-- ===== alerting (pkg/services/ngalert/store/rules) =====

-- @id grafana.alerting.list_rules
-- @src pkg/services/ngalert/store/rules/alert_rule.go:1332-1595
-- @style xorm session builder (Where/And chains, ? positional); jsonValueIn from pkg/services/ngalert/store/rules/json.go:45-75
-- @tags hotpath,dynamic
-- @note Alert list filtered by folders and state=firing|pending: json_extract(NULLIF(k8s_status,''), '$."' || ? || '"') IN (...), ordered by namespace_uid, rule_group, rule_group_idx, id.
-- @modified reconstructed from the xorm builder: column list from the alertRule struct (pkg/services/ngalert/store/rules/models.go:19-51), xorm's parenthesised AND chain and backtick quoting
-- @param ?1 1
-- @param ?2 'f0002'
-- @param ?3 'f0003'
-- @param ?4 'f0005'
-- @param ?5 'f0008'
-- @param ?6 'state'
-- @param ?7 'firing'
-- @param ?8 'pending'
SELECT `id`, `guid`, `org_id`, `title`, `condition`, `data`, `updated`, `updated_by`, `interval_seconds`, `version`, `uid`,
       `namespace_uid`, `folder_fullpath`, `dashboard_uid`, `panel_id`, `rule_group`, `rule_group_idx`, `record`,
       `no_data_state`, `exec_err_state`, `for`, `keep_firing_for`, `annotations`, `labels`, `is_paused`,
       `notification_settings`, `alert_routing_policy`, `metadata`, `missing_series_evals_to_resolve`, `k8s_status`
FROM `alert_rule`
WHERE (org_id = ?1) AND (namespace_uid IN (?2,?3,?4,?5))
  AND (json_extract(NULLIF(k8s_status, ''), '$."' || ?6 || '"') IN (?7,?8))
ORDER BY `namespace_uid` ASC, `rule_group` ASC, `rule_group_idx` ASC, `id` ASC;

-- @id grafana.alerting.latest_versions_by_uid
-- @src pkg/services/ngalert/store/rules/alert_rule.go:178-192
-- @style ? positional, fmt.Sprintf with an IN list
-- @tags dynamic
-- @note Latest version row per rule: alert_rule_version JOIN (GROUP BY rule_guid MAX(id)) derived table, rule_uid IN list.
-- @param ?1 1
-- @param ?2 'rule0007'
-- @param ?3 'rule0042'
-- @param ?4 'rule0101'
-- @param ?5 'rule0250'
-- @param ?6 'rule0333'
SELECT v1.* FROM alert_rule_version AS v1
  INNER JOIN (
      SELECT rule_guid, MAX(id) AS id
      FROM alert_rule_version
      WHERE rule_org_id = ?1
        AND rule_uid IN (?2,?3,?4,?5,?6)
      GROUP BY rule_guid
  ) AS v2 ON v1.rule_guid = v2.rule_guid AND v1.id = v2.id;
