-- simonw/datasette @ a8e13cc489b41f2f9a5aa691f5eb1bedf99a0e0b (Apache-2.0).
-- Part 1: user tables, copied from datasette/fixtures.py (the published fixtures database Datasette's tests and docs
-- use): facet_cities, facetable, searchable (+ FTS5 external-content index), tags, searchable_tags.
-- Part 2: the internal catalog/permissions schema, INTERNAL_DB_SCHEMA_SQL from datasette/utils/internal_db.py.
-- Datasette keeps the internal database in a separate file; both share one database here.

-- == part 1: datasette/fixtures.py
CREATE TABLE tags (
    tag TEXT PRIMARY KEY
);

CREATE TABLE searchable (
  pk integer primary key,
  text1 text,
  text2 text,
  [name with . and spaces] text
);

CREATE TABLE searchable_tags (
    searchable_id integer,
    tag text,
    PRIMARY KEY (searchable_id, tag),
    FOREIGN KEY (searchable_id) REFERENCES searchable(pk),
    FOREIGN KEY (tag) REFERENCES tags(tag)
);

CREATE TABLE facet_cities (
    id integer primary key,
    name text
);

CREATE TABLE facetable (
    pk integer primary key,
    created text,
    planet_int integer,
    on_earth integer,
    state text,
    _city_id integer,
    _neighborhood text,
    tags text,
    complex_array text,
    distinct_some_null,
    n text,
    FOREIGN KEY ("_city_id") REFERENCES [facet_cities](id)
);

CREATE VIRTUAL TABLE "searchable_fts"
    USING FTS5 (text1, text2, [name with . and spaces], content="searchable", content_rowid="pk");

-- == part 2: datasette/utils/internal_db.py INTERNAL_DB_SCHEMA_SQL
CREATE TABLE IF NOT EXISTS catalog_databases (
    database_name TEXT PRIMARY KEY,
    path TEXT,
    is_memory INTEGER,
    schema_version INTEGER
);
CREATE TABLE IF NOT EXISTS catalog_tables (
    database_name TEXT,
    table_name TEXT,
    rootpage INTEGER,
    sql TEXT,
    PRIMARY KEY (database_name, table_name),
    FOREIGN KEY (database_name) REFERENCES catalog_databases(database_name)
);
CREATE TABLE IF NOT EXISTS catalog_views (
    database_name TEXT,
    view_name TEXT,
    rootpage INTEGER,
    sql TEXT,
    PRIMARY KEY (database_name, view_name),
    FOREIGN KEY (database_name) REFERENCES catalog_databases(database_name)
);
CREATE TABLE IF NOT EXISTS catalog_columns (
    database_name TEXT,
    table_name TEXT,
    cid INTEGER,
    name TEXT,
    type TEXT,
    "notnull" INTEGER,
    default_value TEXT, -- renamed from dflt_value
    is_pk INTEGER, -- renamed from pk
    hidden INTEGER,
    PRIMARY KEY (database_name, table_name, name),
    FOREIGN KEY (database_name) REFERENCES catalog_databases(database_name),
    FOREIGN KEY (database_name, table_name) REFERENCES catalog_tables(database_name, table_name)
);
CREATE TABLE IF NOT EXISTS catalog_indexes (
    database_name TEXT,
    table_name TEXT,
    seq INTEGER,
    name TEXT,
    "unique" INTEGER,
    origin TEXT,
    partial INTEGER,
    PRIMARY KEY (database_name, table_name, name),
    FOREIGN KEY (database_name) REFERENCES catalog_databases(database_name),
    FOREIGN KEY (database_name, table_name) REFERENCES catalog_tables(database_name, table_name)
);
CREATE TABLE IF NOT EXISTS catalog_foreign_keys (
    database_name TEXT,
    table_name TEXT,
    id INTEGER,
    seq INTEGER,
    "table" TEXT,
    "from" TEXT,
    "to" TEXT,
    on_update TEXT,
    on_delete TEXT,
    match TEXT,
    PRIMARY KEY (database_name, table_name, id, seq),
    FOREIGN KEY (database_name) REFERENCES catalog_databases(database_name),
    FOREIGN KEY (database_name, table_name) REFERENCES catalog_tables(database_name, table_name)
);

CREATE TABLE IF NOT EXISTS metadata_instance (
    key text,
    value text,
    unique(key)
);

CREATE TABLE IF NOT EXISTS metadata_databases (
    database_name text,
    key text,
    value text,
    unique(database_name, key)
);

CREATE TABLE IF NOT EXISTS metadata_resources (
    database_name text,
    resource_name text,
    key text,
    value text,
    unique(database_name, resource_name, key)
);

CREATE TABLE IF NOT EXISTS metadata_columns (
    database_name text,
    resource_name text,
    column_name text,
    key text,
    value text,
    unique(database_name, resource_name, column_name, key)
);

CREATE TABLE IF NOT EXISTS column_types (
    database_name TEXT NOT NULL,
    resource_name TEXT NOT NULL,
    column_name TEXT NOT NULL,
    column_type TEXT NOT NULL,
    config TEXT,
    PRIMARY KEY (database_name, resource_name, column_name)
);

CREATE TABLE IF NOT EXISTS queries (
    database_name TEXT NOT NULL,
    name TEXT NOT NULL,
    sql TEXT NOT NULL,
    title TEXT,
    description TEXT,
    description_html TEXT,
    options TEXT NOT NULL DEFAULT '{}',
    parameters TEXT NOT NULL DEFAULT '[]',
    is_write INTEGER NOT NULL DEFAULT 0 CHECK (is_write IN (0, 1)),
    is_private INTEGER NOT NULL DEFAULT 0 CHECK (is_private IN (0, 1)),
    is_trusted INTEGER NOT NULL DEFAULT 0 CHECK (is_trusted IN (0, 1)),
    source TEXT NOT NULL DEFAULT 'user',
    owner_id TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (database_name, name)
);

CREATE INDEX IF NOT EXISTS queries_owner_idx
    ON queries(owner_id);
