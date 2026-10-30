-- KOReader (koreader/koreader @ 801277394b7fdb77da5580459a9827e9d95e95a4, AGPL-3.0). Only the CREATE statements the
-- queries need, quoted from:
--   plugins/statistics.koplugin/main.lua:405-484   (statistics.sqlite3: page_stat_data, numbers, page_stat view, book)
--   plugins/vocabbuilder.koplugin/db.lua:10-31,107 (vocabulary_builder.sqlite3: vocabulary, title)
--   plugins/coverbrowser.koplugin/bookinfomanager.lua:25-68 (bookinfo_cache.sqlite3: bookinfo)
-- On a device these are three separate database files; here they share one database (no name clashes).
-- The statistics sync (main.lua:3115-3246) ATTACHes the other device's DB as income_db and the last synced copy as
-- cached_db. The runner can't attach, so income_book/income_page_stat_data and cached_book/cached_page_stat_data are
-- main-schema copies of the same DDL, and the sync's TEMP table book_id_map is a plain table (see queries @modified).
-- The full files are fetched by tools/fetch.sh (meta.json fetch_paths).

-- statistics.koplugin/main.lua:405-420
CREATE TABLE IF NOT EXISTS page_stat_data
    (
        id_book     integer,
        page        integer NOT NULL DEFAULT 0,
        start_time  integer NOT NULL DEFAULT 0,
        duration    integer NOT NULL DEFAULT 0,
        total_pages integer NOT NULL DEFAULT 0,
        UNIQUE (id_book, page, start_time),
        FOREIGN KEY(id_book) REFERENCES book(id)
    );
CREATE INDEX IF NOT EXISTS page_stat_data_start_time ON page_stat_data(start_time);

-- statistics.koplugin/main.lua:422-452 (the numbers rows are inserted by data.sql, as the same script does)
CREATE TABLE IF NOT EXISTS numbers
    (
        number INTEGER PRIMARY KEY
    );
CREATE VIEW IF NOT EXISTS page_stat AS
    SELECT id_book, first_page + idx - 1 AS page, start_time, duration / (last_page - first_page + 1) AS duration
    FROM (
        SELECT id_book, page, total_pages, pages, start_time, duration,
            -- First page_number for this page after rescaling single row
            ((page - 1) * pages) / total_pages + 1 AS first_page,
            -- Last page_number for this page after rescaling single row
            max(((page - 1) * pages) / total_pages + 1, (page * pages) / total_pages) AS last_page,
            idx
        FROM page_stat_data
        JOIN book ON book.id = id_book
        -- Duplicate rows for multiple pages as needed (as a result of rescaling)
        JOIN (SELECT number as idx FROM numbers) AS N ON idx <= (last_page - first_page + 1)
    );

-- statistics.koplugin/main.lua:462-484 (the index is made UNIQUE by the migration at main.lua:541-569)
CREATE TABLE IF NOT EXISTS book
    (
        id integer PRIMARY KEY autoincrement,
        title text,
        authors text,
        notes      integer,
        last_open  integer,
        highlights integer,
        pages      integer,
        series text,
        language text,
        md5 text,
        total_read_time  integer,
        total_read_pages integer
    );
CREATE UNIQUE INDEX book_title_authors_md5 ON book(title, authors, md5);

-- Stand-ins for the attached income_db / cached_db (same DDL as above)
CREATE TABLE income_book (id integer PRIMARY KEY autoincrement, title text, authors text, notes integer, last_open integer,
    highlights integer, pages integer, series text, language text, md5 text, total_read_time integer, total_read_pages integer);
CREATE UNIQUE INDEX income_book_title_authors_md5 ON income_book(title, authors, md5);
CREATE TABLE income_page_stat_data (id_book integer, page integer NOT NULL DEFAULT 0, start_time integer NOT NULL DEFAULT 0,
    duration integer NOT NULL DEFAULT 0, total_pages integer NOT NULL DEFAULT 0, UNIQUE (id_book, page, start_time),
    FOREIGN KEY(id_book) REFERENCES book(id));
CREATE INDEX income_page_stat_data_start_time ON income_page_stat_data(start_time);
CREATE TABLE cached_book (id integer PRIMARY KEY autoincrement, title text, authors text, notes integer, last_open integer,
    highlights integer, pages integer, series text, language text, md5 text, total_read_time integer, total_read_pages integer);
CREATE UNIQUE INDEX cached_book_title_authors_md5 ON cached_book(title, authors, md5);
CREATE TABLE cached_page_stat_data (id_book integer, page integer NOT NULL DEFAULT 0, start_time integer NOT NULL DEFAULT 0,
    duration integer NOT NULL DEFAULT 0, total_pages integer NOT NULL DEFAULT 0, UNIQUE (id_book, page, start_time),
    FOREIGN KEY(id_book) REFERENCES book(id));
CREATE INDEX cached_page_stat_data_start_time ON cached_page_stat_data(start_time);
-- main.lua:3195-3199 creates this as a TEMP table during the sync
CREATE TABLE book_id_map (mid, iid);

-- vocabbuilder.koplugin/db.lua:10-31,107
CREATE TABLE IF NOT EXISTS vocabulary (
    word          TEXT NOT NULL UNIQUE,
    title_id      INTEGER,
    create_time   INTEGER NOT NULL,
    review_time   INTEGER,
    due_time      INTEGER NOT NULL,
    review_count  INTEGER NOT NULL DEFAULT 0,
    prev_context  TEXT,
    next_context  TEXT,
    streak_count  INTEGER NOT NULL DEFAULT 0,
    highlight     TEXT,
    PRIMARY KEY(word)
);
CREATE TABLE IF NOT EXISTS title (
    id            INTEGER NOT NULL UNIQUE,
    name          TEXT UNIQUE,
    filter        INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY(id)
);
CREATE INDEX IF NOT EXISTS due_time_index ON vocabulary(due_time);
CREATE INDEX IF NOT EXISTS title_name_index ON title(name);
CREATE INDEX IF NOT EXISTS title_id_index ON vocabulary(title_id);

-- coverbrowser.koplugin/bookinfomanager.lua:25-68
CREATE TABLE IF NOT EXISTS bookinfo (
    bcid                INTEGER PRIMARY KEY AUTOINCREMENT,
    directory           TEXT NOT NULL,
    filename            TEXT NOT NULL,
    filesize            INTEGER,
    filemtime           INTEGER,
    in_progress         INTEGER,
    unsupported         TEXT,
    cover_fetched       TEXT,
    has_meta            TEXT,
    has_cover           TEXT,
    cover_sizetag       TEXT,
    ignore_meta         TEXT,
    ignore_cover        TEXT,
    pages               INTEGER,
    title               TEXT,
    authors             TEXT,
    series              TEXT,
    series_index        REAL,
    language            TEXT,
    keywords            TEXT,
    description         TEXT,
    cover_w             INTEGER,
    cover_h             INTEGER,
    cover_bb_type       INTEGER,
    cover_bb_stride     INTEGER,
    cover_bb_data       BLOB
);
CREATE UNIQUE INDEX IF NOT EXISTS dir_filename ON bookinfo(directory, filename);
