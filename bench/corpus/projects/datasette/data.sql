-- Synthetic data for datasette. Deterministic (no random()): values come from multiplicative hashes of row numbers.
-- User data, scale 1: a scaled-up fixtures database: 300 facet_cities, 100k facetable rows (dates over two years, a
-- JSON tags array, skewed states/cities), 40k searchable rows indexed by FTS5, 12 tags, ~60k searchable_tags.
-- Internal catalog: the fixtures database (catalog rows taken from the real schema via pragma functions), a
-- 'council' database of 250 tables and 20 views with ~8 columns each, a 'scratch' database, and 60 stored queries.
BEGIN;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300)
INSERT INTO facet_cities(id, name)
SELECT i, CASE i WHEN 1 THEN 'San Francisco' WHEN 2 THEN 'Los Angeles' WHEN 3 THEN 'Detroit' WHEN 4 THEN 'Memnonia'
              ELSE (SELECT column2 FROM (VALUES (0,'Spring'),(1,'Oak'),(2,'River'),(3,'Lake'),(4,'Mill'),(5,'Fair')) WHERE column1 = i % 6)
                   || (SELECT column2 FROM (VALUES (0,'field'),(1,'ton'),(2,'view'),(3,'dale'),(4,'wood')) WHERE column1 = (i / 6) % 5) || ' ' || i END
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 100000*(SELECT scale FROM _cfg)),
h AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO facetable(pk, created, planet_int, on_earth, state, _city_id, _neighborhood, tags, complex_array, distinct_some_null, n)
SELECT i,
       strftime('%Y-%m-%d %H:%M:%S', 1546300800 + (i * 631) % 63072000, 'unixepoch'),
       CASE WHEN (h / 8) % 50 = 0 THEN 2 ELSE 1 END,
       CASE WHEN (h / 8) % 50 = 0 THEN 0 ELSE 1 END,
       (SELECT column2 FROM (VALUES (0,'CA'),(1,'CA'),(2,'CA'),(3,'NY'),(4,'TX'),(5,'MI'),(6,'WA'),(7,'MC')) WHERE column1 = (h / 64) % 8),
       CASE WHEN (h / 512) % 3 = 0 THEN (h / 512) % 4 + 1 ELSE (h / 2048) % 300 + 1 END,
       (SELECT column2 FROM (VALUES (0,'Mission'),(1,'Dogpatch'),(2,'SOMA'),(3,'Tenderloin'),(4,'Bernal Heights'),(5,'Hayes Valley'),(6,'Hollywood'),(7,'Downtown'),(8,'Los Feliz'),(9,'Corktown'),(10,'Mexicantown'),(11,'Arcadia Planitia')) WHERE column1 = (h / 1048576) % 12),
       CASE (h / 16384) % 6 WHEN 0 THEN '["tag1", "tag2"]' WHEN 1 THEN '["tag1", "tag3"]' WHEN 2 THEN '["tag2"]' WHEN 3 THEN '["tag3", "tag4", "tag1"]' ELSE '[]' END,
       CASE WHEN (h / 16384) % 6 = 0 THEN '[{"foo": "bar"}]' ELSE '[]' END,
       CASE (h / 131072) % 4 WHEN 0 THEN 'one' WHEN 1 THEN 'two' END,
       CASE WHEN (h / 131072) % 4 < 2 THEN 'n' || ((h / 524288) % 50) END
FROM h;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40000*(SELECT scale FROM _cfg)),
h AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n),
w(k, w) AS (SELECT column1, column2 FROM (VALUES (0,'barry'),(1,'terry'),(2,'sara'),(3,'cat'),(4,'dog'),(5,'weasel'),(6,'panther'),(7,'puma'),(8,'otter'),(9,'heron'),(10,'river'),(11,'forest'),(12,'night'),(13,'garden'),(14,'harbour'),(15,'meadow')))
INSERT INTO searchable(pk, text1, text2, [name with . and spaces])
SELECT i,
       (SELECT w FROM w WHERE k = h % 16) || ' ' || (SELECT w FROM w WHERE k = (h / 16) % 16) || ' ' || (SELECT w FROM w WHERE k = (h / 256) % 16),
       (SELECT w FROM w WHERE k = (h / 4096) % 16) || ' ' || (SELECT w FROM w WHERE k = (h / 65536) % 16) || ' notes ' || i,
       (SELECT w FROM w WHERE k = (h / 1048576) % 16)
FROM h;
INSERT INTO searchable_fts(searchable_fts) VALUES ('rebuild');

INSERT INTO tags(tag) SELECT column1 FROM (VALUES ('canine'),('feline'),('mustelid'),('bird'),('aquatic'),('nocturnal'),('urban'),('rural'),('endangered'),('pet'),('wild'),('fixture'));
INSERT OR IGNORE INTO searchable_tags(searchable_id, tag)
SELECT s.pk, (SELECT tag FROM (SELECT tag, row_number() OVER (ORDER BY tag) - 1 AS rn FROM tags) WHERE rn = (s.pk * 7 + k.k * 5) % 12)
FROM searchable s, (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2) k WHERE k.k < 1 + s.pk % 3;

-- ===== internal database (catalog, metadata, stored queries)
INSERT INTO catalog_databases(database_name, path, is_memory, schema_version) VALUES
  ('fixtures', '/data/fixtures.db', 0, 37), ('council', '/data/council.db', 0, 512), ('scratch', NULL, 1, 3);

INSERT INTO catalog_tables(database_name, table_name, rootpage, sql)
SELECT 'fixtures', name, rootpage, sql FROM sqlite_master
WHERE type = 'table' AND name IN ('facet_cities', 'facetable', 'searchable', 'searchable_fts', 'tags', 'searchable_tags',
                                  'searchable_fts_data', 'searchable_fts_idx', 'searchable_fts_docsize', 'searchable_fts_config');
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 250)
INSERT INTO catalog_tables(database_name, table_name, rootpage, sql)
SELECT 'council', (SELECT column2 FROM (VALUES (0,'meetings'),(1,'votes'),(2,'agenda_items'),(3,'members'),(4,'motions'),(5,'budget_lines'),(6,'contracts'),(7,'Planning_Applications'),(8,'wards'),(9,'minutes')) WHERE column1 = i % 10) || '_' || (2000 + i / 10),
       i + 10, 'CREATE TABLE t' || i || ' (id integer primary key, name text, created text)'
FROM n;
INSERT INTO catalog_tables(database_name, table_name, rootpage, sql) VALUES ('scratch', 'notes', 2, 'CREATE TABLE notes (id integer primary key, body text)');
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20)
INSERT INTO catalog_views(database_name, view_name, rootpage, sql)
SELECT 'council', 'v_summary_' || i, 0, 'CREATE VIEW v_summary_' || i || ' AS SELECT 1' FROM n;
INSERT INTO catalog_views(database_name, view_name, rootpage, sql) VALUES ('fixtures', 'searchable_view', 0, 'CREATE VIEW searchable_view AS SELECT * FROM searchable');

INSERT INTO catalog_columns(database_name, table_name, cid, name, type, "notnull", default_value, is_pk, hidden)
SELECT 'fixtures', t.table_name, c.cid, c.name, c.type, c."notnull", c.dflt_value, c.pk, 0
FROM catalog_tables t, pragma_table_info(t.table_name) c WHERE t.database_name = 'fixtures';
INSERT INTO catalog_columns(database_name, table_name, cid, name, type, "notnull", default_value, is_pk, hidden)
SELECT t.database_name, t.table_name, k.cid, k.name, k.type, 0, NULL, k.cid = 0, 0
FROM catalog_tables t,
     (SELECT column1 AS cid, column2 AS name, column3 AS type FROM (VALUES (0,'id','INTEGER'),(1,'name','TEXT'),(2,'created','TEXT'),(3,'ward_id','INTEGER'),(4,'amount','REAL'),(5,'status','TEXT'),(6,'notes','TEXT'),(7,'url','TEXT'))) k
WHERE t.database_name <> 'fixtures' AND (k.cid < 4 OR (t.rootpage + k.cid) % 3 <> 0);
INSERT INTO catalog_foreign_keys(database_name, table_name, id, seq, "table", "from", "to", on_update, on_delete, match)
SELECT 'fixtures', t.table_name, f.id, f.seq, f."table", f."from", f."to", f.on_update, f.on_delete, f.match
FROM catalog_tables t, pragma_foreign_key_list(t.table_name) f WHERE t.database_name = 'fixtures';
INSERT INTO catalog_indexes(database_name, table_name, seq, name, "unique", origin, partial)
SELECT 'fixtures', t.table_name, i.seq, i.name, i."unique", i.origin, i.partial
FROM catalog_tables t, pragma_index_list(t.table_name) i WHERE t.database_name = 'fixtures';

INSERT INTO metadata_instance(key, value) VALUES ('title', 'City data portal'), ('license', 'CC BY 4.0');
INSERT INTO metadata_resources(database_name, resource_name, key, value) VALUES
  ('fixtures', 'facetable', 'description', 'Facetable demo data'), ('fixtures', 'searchable', 'title', 'Searchable things');
INSERT INTO column_types(database_name, resource_name, column_name, column_type, config) VALUES
  ('fixtures', 'facetable', 'created', 'datetime', NULL), ('fixtures', 'facetable', 'tags', 'json', NULL),
  ('fixtures', 'facetable', 'n', 'text', '{"truncate": 20}'), ('council', 'contracts_2001', 'url', 'url', NULL);

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 60)
INSERT INTO queries(database_name, name, sql, title, description, options, parameters, is_write, is_private, is_trusted, source, owner_id, created_at, updated_at)
SELECT CASE WHEN i % 3 = 0 THEN 'fixtures' ELSE 'council' END, 'query_' || i,
       'select * from facetable where state = :state limit ' || i, 'Query ' || i, NULL, '{}',
       CASE WHEN i % 2 = 0 THEN '["state"]' ELSE '[]' END, i % 10 = 0, i % 4 = 0, 0,
       CASE WHEN i <= 10 THEN 'config' ELSE 'user' END, CASE WHEN i > 10 THEN 'user' || (i % 5) END,
       '2025-01-01 00:00:00', '2025-01-02 00:00:00'
FROM n;
COMMIT;
