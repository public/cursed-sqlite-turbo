-- Datasette (simonw/datasette @ a8e13cc, Apache-2.0). Python sqlite3 with :name parameters (Datasette's own
-- filters use :p0, :p1, ...; FK label lookups and a few catalog reads use positional ?, normalised to ?N). Nearly all
-- SQL is generated per request from the table, its columns and the query string, so most queries are one
-- representative instantiation (tagged dynamic) for the scaled-up fixtures database: facetable with
-- ?planet_int__gt=0&state=CA&_sort_desc=created, facets on state/_city_id/tags/created, searchable with FTS5.
-- Paths are repo-relative.

-- @id datasette.table.page_default
-- @src datasette/views/table.py:2085-2251
-- @style no params; select list and order by built from the table's columns and primary key
-- @tags hotpath,dynamic
-- @note Default table page: every column, primary-key order, page size 100 + 1.
select pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n from facetable order by pk limit 101;

-- @id datasette.table.page_filtered_sorted_next
-- @src datasette/views/table.py:2120-2251
-- @style :pN named; where clauses from Filters.build_where_clauses (filters.py:453), keyset from compound_keys_after_sql (utils/__init__.py:314)
-- @tags hotpath,dynamic
-- @note Page 2 of ?planet_int__gt=0&state=CA&_sort_desc=created: quoted-column filters plus the sort_desc keyset predicate (value < :p3 or null or tie with pk > :p2), ordered by created desc, pk.
-- @param :p0 0
-- @param :p1 'CA'
-- @param :p2 '99559'
-- @param :p3 '2020-12-28 02:28:49'
select pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n from facetable where "planet_int" > :p0 and "state" = :p1 and (created < :p3 or created is null or (created = :p3 and ((pk > :p2)))) order by created desc, pk limit 101;

-- @id datasette.table.filtered_count
-- @src datasette/views/table.py:2131-2140
-- @style :pN named
-- @tags hotpath,dynamic
-- @note "N rows where ..." count for the filtered table page.
-- @param :p0 0
-- @param :p1 'CA'
select count(*) from facetable where "planet_int" > :p0 and "state" = :p1 ;

-- @id datasette.database.table_count_limited
-- @src datasette/database.py:858-870
-- @style no params; table name spliced in, count_limit 10000 + 1
-- @tags hotpath,dynamic
-- @note Database page table counts, capped by a LIMIT inside a derived table.
select count(*) from (select * from facetable limit 10001);

-- @id datasette.facets.column_state
-- @src datasette/facets.py:216-240
-- @style :pN named; inner SQL is the table's sql_no_order_no_limit (views/table.py:2243)
-- @tags hotpath,dynamic
-- @note Column facet: GROUP BY over a derived table of the filtered rows (?planet_int__gt=0), count desc, top 31.
-- @param :p0 0
select state as value, count(*) as count from (
    select pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n from facetable where "planet_int" > :p0
)
where state is not null
group by state order by count desc, value limit 31;

-- @id datasette.facets.column_city_id
-- @src datasette/facets.py:216-240
-- @style :pN named
-- @tags hotpath,dynamic
-- @note Column facet on the foreign-key column (labels are fetched next).
-- @param :p0 'CA'
select _city_id as value, count(*) as count from (
    select pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n from facetable where "state" = :p0
)
where _city_id is not null
group by _city_id order by count desc, value limit 31;

-- @id datasette.facets.expand_fk_labels
-- @src datasette/app.py:2331-2342
-- @style ? positional, one placeholder per distinct value
-- @tags hot-small,hotpath,dynamic
-- @note Label lookup for facet/foreign-key values against the label column of facet_cities.
-- @param ?1 3
-- @param ?2 2
-- @param ?3 1
-- @param ?4 4
-- @param ?5 209
-- @param ?6 71
select id, name
from facet_cities
where id in (?1, ?2, ?3, ?4, ?5, ?6);

-- @id datasette.facets.array_tags
-- @src datasette/facets.py:385-415
-- @style :pN named
-- @tags hotpath,dynamic
-- @note Array facet: CTE over the filtered rows, json_each per row joined back with DISTINCT to dedupe items, grouped and ranked.
-- @param :p0 'CA'
with inner as (select pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n from facetable where "state" = :p0 ),
deduped_array_items as (
    select
        distinct j.value,
        inner.*
    from
        json_each([inner].tags) j
        join inner
)
select
    value as value,
    count(*) as count
from
    deduped_array_items
group by
    value
order by
    count(*) desc, value limit 31;

-- @id datasette.facets.date_created
-- @src datasette/facets.py:510-535
-- @style :pN named
-- @tags hotpath,dynamic
-- @note Date facet: date() applied in WHERE, GROUP BY and the result over the filtered rows.
-- @param :p0 'CA'
select date(created) as value, count(*) as count from (
    select pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n from facetable where "state" = :p0
)
where date(created) is not null
group by date(created) order by count desc, value limit 31;

-- @id datasette.facets.suggest_column
-- @src datasette/facets.py:155-175
-- @style no params (unfiltered table); run once per column
-- @tags hotpath,dynamic
-- @note Suggested facets probe: CTE limited to 1000 rows, grouped distinct values with a WHERE on the alias.
with limited as (select * from (select pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n from facetable ) limit 1000)
select _neighborhood as value, count(*) as n from limited
where value is not null
group by value
limit 31;

-- @id datasette.facets.suggest_row_count
-- @src datasette/facets.py:204-213
-- @style no params
-- @tags hotpath,dynamic
-- @note Row count of the limited sample for facet suggestions.
select count(*) from (select * from (select pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n from facetable ) limit 1000);

-- @id datasette.facets.suggest_array_types
-- @src datasette/facets.py:315-335
-- @style no params; run once per column
-- @tags hotpath,dynamic
-- @note Array facet suggestion: DISTINCT json_type() over a 1000-row sample.
with limited as (select * from (select pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n from facetable ) limit 1000)
select distinct json_type(tags)
from limited
where tags is not null and tags != '';

-- @id datasette.facets.suggest_array_first_100
-- @src datasette/facets.py:340-352
-- @style no params
-- @tags hotpath,dynamic
-- @note Follow-up probe: first 100 non-empty JSON arrays (json_array_length filter).
select tags from (select pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n from facetable ) where tags is not null and tags != '' and json_array_length(tags) > 0 limit 100;

-- @id datasette.facets.suggest_date
-- @src datasette/facets.py:470-488
-- @style no params; run once per column
-- @tags hotpath,dynamic
-- @note Date facet suggestion: date() over a 100-row sample filtered by GLOB (a double-quoted string literal, as Datasette writes it).
select date(created) from (
    select * from (select pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n from facetable ) limit 100
) where created glob "????-??-*";

-- @id datasette.search.fts_table_page
-- @src datasette/filters.py:91-104
-- @style :search named; rowid IN (FTS5 MATCH subquery), escaped mode
-- @tags hotpath,dynamic,modified
-- @note ?_search=dog on searchable: rowid IN a MATCH subquery on the external-content FTS5 table, pk order, top 101.
-- @modified escape_fts(:search) is a Python function Datasette registers (utils/__init__.py:1148); the parameter is passed already escaped ('"dog"') and the call removed
-- @param :search '"dog"'
select pk, text1, text2, "name with . and spaces" from searchable where rowid in (select rowid from searchable_fts where searchable_fts match :search) order by pk limit 101;

-- @id datasette.search.fts_count
-- @src datasette/views/table.py:2131-2140
-- @style :search named
-- @tags hotpath,dynamic,modified
-- @note Count for the search results page.
-- @modified escape_fts(:search) replaced by a pre-escaped parameter, as above
-- @param :search '"dog" "night"'
select count(*) from searchable where rowid in (select rowid from searchable_fts where searchable_fts match :search) ;

-- @id datasette.search.fts_column_raw
-- @src datasette/filters.py:105-125
-- @style :search_0 named; ?_search_text2=weasel OR otter&_searchmode=raw, combined with a filter
-- @tags hotpath,dynamic
-- @note Column-scoped raw FTS5 query (column name as the MATCH target) plus a LIKE filter, pk order.
-- @param :p0 'barry%'
-- @param :search_0 'weasel OR otter'
select pk, text1, text2, "name with . and spaces" from searchable where "text1" like :p0 and rowid in (select rowid from searchable_fts where text2 match :search_0) order by pk limit 101;

-- @id datasette.row.select_by_pk
-- @src datasette/utils/__init__.py:1562-1580
-- @style :p0 named
-- @tags hot-small,hotpath,dynamic
-- @note Row page lookup by primary key.
-- @param :p0 '4242'
select * from facetable where "pk"=:p0;

-- @id datasette.row.incoming_fk_counts
-- @src datasette/views/row.py:658-690
-- @style :id named; one scalar subquery per incoming foreign key
-- @tags hotpath,dynamic
-- @note Row page for a city: counts of referencing rows via a scalar subquery (no index on _city_id).
-- @param :id '3'
select (select count(*) from facetable where _city_id=:id);

-- @id datasette.table.autocomplete
-- @src datasette/views/table.py:1560-1640
-- @style :q, :like, :prefix named
-- @tags hotpath,dynamic
-- @note FK autocomplete: LIKE ... escape char(92) on pk and label, CASE-ranked order (exact pk, label match, label length), top 10.
-- @param :q 'spr'
-- @param :like '%spr%'
-- @param :prefix 'spr%'
select id, name
from facet_cities
where id like :like escape char(92) or name like :like escape char(92)
order by case when cast(id as text) = :q then 0 else 1 end, case when name like :like escape char(92) then 0 else 1 end, case when name like :like escape char(92) then length(cast(name as text)) end, id
limit 10;

-- @id datasette.database.detect_fts
-- @src datasette/utils/__init__.py:831-851
-- @style :named
-- @tags hotpath
-- @note FTS table detection on every table page: LIKE ... ESCAPE over sqlite_master.
-- @param :fts_double_quoted '%VIRTUAL TABLE%USING FTS%content="searchable"%'
-- @param :fts_bracket_quoted '%VIRTUAL TABLE%USING FTS%content=[searchable]%'
-- @param :table 'searchable'
select name from sqlite_master
    where rootpage = 0
    and (
        sql like :fts_double_quoted escape char(92)
        or sql like :fts_bracket_quoted escape char(92)
        or (
            tbl_name = :table
            and sql like '%VIRTUAL TABLE%USING FTS%'
        )
    );

-- @id datasette.permissions.allowed_tables_page
-- @src datasette/utils/actions_sql.py:141-450
-- @style :named; built by _build_single_action_sql for view-table, anonymous actor, two datasette.yaml deny rules (default_permissions/config.py) plus the default allow (default_permissions/defaults.py); keyset + LIMIT added by allowed_resources (app.py:1960-2000)
-- @tags hotpath,dynamic
-- @note Which tables can this actor see: catalog UNION ALL base, rule UNION with COLLATE NOCASE, three aggregate CTEs (MAX(CASE), json_group_array), a CASE cascade over LEFT/CROSS joins, wrapped with a keyset filter and LIMIT.
-- @param :cfg_0_parent 'council'
-- @param :cfg_0_child 'contracts_2001'
-- @param :cfg_0_allow 0
-- @param :cfg_0_reason 'config deny allow for view-table on council/contracts_2001'
-- @param :cfg_1_parent 'scratch'
-- @param :cfg_1_child NULL
-- @param :cfg_1_allow 0
-- @param :cfg_1_reason 'config deny allow for view-table on scratch'
-- @param :reason_3 'default allow for view-table'
-- @param :filter_parent 'council'
-- @param :keyset_parent 'council'
-- @param :keyset_child 'agenda_items_2010'
-- @param :limit 101
SELECT * FROM (WITH
base AS (

            SELECT database_name AS parent, table_name AS child
            FROM catalog_tables
            UNION ALL
            SELECT database_name AS parent, view_name AS child
            FROM catalog_views

),
all_rules AS (
  SELECT parent, child COLLATE NOCASE AS child, allow, reason, 'datasette.default_permissions' AS source_plugin FROM (
                SELECT :cfg_0_parent AS parent, :cfg_0_child AS child, :cfg_0_allow AS allow, :cfg_0_reason AS reason
UNION ALL
SELECT :cfg_1_parent AS parent, :cfg_1_child AS child, :cfg_1_allow AS allow, :cfg_1_reason AS reason
            ) UNION ALL SELECT parent, child COLLATE NOCASE AS child, allow, reason, 'datasette.default_permissions' AS source_plugin FROM (
                SELECT NULL AS parent, NULL AS child, 1 AS allow, :reason_3 AS reason
            )
),
child_agg AS (
  SELECT parent, child,
         MAX(CASE WHEN allow = 0 THEN 1 ELSE 0 END) AS any_deny,
         MAX(CASE WHEN allow = 1 THEN 1 ELSE 0 END) AS any_allow,
         json_group_array(CASE WHEN allow = 0 THEN source_plugin || ': ' || reason END) AS deny_reasons,
         json_group_array(CASE WHEN allow = 1 THEN source_plugin || ': ' || reason END) AS allow_reasons
  FROM all_rules WHERE parent IS NOT NULL AND child IS NOT NULL
  GROUP BY parent, child
),
parent_agg AS (
  SELECT parent,
         MAX(CASE WHEN allow = 0 THEN 1 ELSE 0 END) AS any_deny,
         MAX(CASE WHEN allow = 1 THEN 1 ELSE 0 END) AS any_allow,
         json_group_array(CASE WHEN allow = 0 THEN source_plugin || ': ' || reason END) AS deny_reasons,
         json_group_array(CASE WHEN allow = 1 THEN source_plugin || ': ' || reason END) AS allow_reasons
  FROM all_rules WHERE parent IS NOT NULL AND child IS NULL
  GROUP BY parent
),
global_agg AS (
  SELECT
         MAX(CASE WHEN allow = 0 THEN 1 ELSE 0 END) AS any_deny,
         MAX(CASE WHEN allow = 1 THEN 1 ELSE 0 END) AS any_allow,
         json_group_array(CASE WHEN allow = 0 THEN source_plugin || ': ' || reason END) AS deny_reasons,
         json_group_array(CASE WHEN allow = 1 THEN source_plugin || ': ' || reason END) AS allow_reasons
  FROM all_rules WHERE parent IS NULL AND child IS NULL
),
decisions AS (
  SELECT
    b.parent, b.child,
    CASE
      WHEN ca.any_deny = 1 THEN 0
      WHEN ca.any_allow = 1 THEN 1
      WHEN pa.any_deny = 1 THEN 0
      WHEN pa.any_allow = 1 THEN 1
      WHEN ga.any_deny = 1 THEN 0
      WHEN ga.any_allow = 1 THEN 1
      ELSE 0
    END AS is_allowed,
    CASE
      WHEN ca.any_deny = 1 THEN ca.deny_reasons
      WHEN ca.any_allow = 1 THEN ca.allow_reasons
      WHEN pa.any_deny = 1 THEN pa.deny_reasons
      WHEN pa.any_allow = 1 THEN pa.allow_reasons
      WHEN ga.any_deny = 1 THEN ga.deny_reasons
      WHEN ga.any_allow = 1 THEN ga.allow_reasons
      ELSE '[]'
    END AS reason
  FROM base b
  LEFT JOIN child_agg ca ON ca.parent = b.parent AND ca.child = b.child
  LEFT JOIN parent_agg pa ON pa.parent = b.parent
  CROSS JOIN global_agg ga
)
SELECT parent, child, reason
FROM decisions
WHERE is_allowed = 1
  AND parent = :filter_parent
ORDER BY parent, child) WHERE
                        (parent > :keyset_parent OR
                         (parent = :keyset_parent AND child > :keyset_child))
                     LIMIT :limit;

-- @id datasette.permissions.check_table_allowed
-- @src datasette/utils/actions_sql.py:517-665
-- @style :named; check_permissions_for_actions for ["view-table"] with params namespaced a0_, same rules as above
-- @tags hot-small,hotpath,dynamic
-- @note Per-request permission verdict: rules CTE, a scalar subquery ranking matching rules by specificity (CASE depth), deny-first, top-1, inside a VALUES row.
-- @param :_check_parent 'fixtures'
-- @param :_check_child 'facetable'
-- @param :a0_cfg_0_parent 'council'
-- @param :a0_cfg_0_child 'contracts_2001'
-- @param :a0_cfg_0_allow 0
-- @param :a0_cfg_0_reason 'config deny allow for view-table on council/contracts_2001'
-- @param :a0_cfg_1_parent 'scratch'
-- @param :a0_cfg_1_child NULL
-- @param :a0_cfg_1_allow 0
-- @param :a0_cfg_1_reason 'config deny allow for view-table on scratch'
-- @param :a0_reason_3 'default allow for view-table'
WITH
a0_rules AS (
SELECT parent, child COLLATE NOCASE AS child, allow, reason, 'datasette.default_permissions' AS source_plugin FROM (
SELECT :a0_cfg_0_parent AS parent, :a0_cfg_0_child AS child, :a0_cfg_0_allow AS allow, :a0_cfg_0_reason AS reason
UNION ALL
SELECT :a0_cfg_1_parent AS parent, :a0_cfg_1_child AS child, :a0_cfg_1_allow AS allow, :a0_cfg_1_reason AS reason
)
UNION ALL
SELECT parent, child COLLATE NOCASE AS child, allow, reason, 'datasette.default_permissions' AS source_plugin FROM (
SELECT NULL AS parent, NULL AS child, 1 AS allow, :a0_reason_3 AS reason
)
),
results(action_idx, is_allowed) AS (VALUES
(0, (COALESCE((
  SELECT allow FROM (
    SELECT allow, source_plugin,
      CASE
        WHEN child IS NOT NULL THEN 2
        WHEN parent IS NOT NULL THEN 1
        ELSE 0
      END AS depth
    FROM a0_rules
    WHERE (parent IS NULL OR parent = :_check_parent)
      AND (child IS NULL OR child = :_check_child)
    ORDER BY
      depth DESC,
      CASE WHEN allow = 0 THEN 0 ELSE 1 END,
      source_plugin
    LIMIT 1
  )
), 0)))
)
SELECT action_idx, is_allowed FROM results;

-- @id datasette.internal.catalog_schema_versions
-- @src datasette/app.py:735-739
-- @style no params
-- @tags hot-small,hotpath
-- @note Schema-version check against the internal catalog before refreshing it.
select database_name, schema_version from catalog_databases;

-- @id datasette.internal.column_types_for_resource
-- @src datasette/app.py:1405-1412
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Column type assignments for a table, looked up on every table render.
-- @param ?1 'fixtures'
-- @param ?2 'facetable'
SELECT column_name, column_type, config FROM column_types WHERE database_name = ?1 AND resource_name = ?2;
