-- Synthetic data for calibre. Deterministic (no random()): values come from multiplicative hashes of the row number.
-- Scale 1: 20k books, 6k authors, 1.5k tags, 2k series, 400 publishers, 30 languages, ~27k format rows, ~30k
-- identifiers, 15k comments, 20k annotations (FTS-indexed by trigger), 12k full-text rows, 3 custom columns.
BEGIN;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 6000*(SELECT scale FROM _cfg)),
f(j, f) AS (VALUES (0,'Anna'),(1,'Boris'),(2,'Chiara'),(3,'David'),(4,'Elena'),(5,'Fyodor'),(6,'Grace'),(7,'Haruki'),(8,'Isabel'),(9,'Jorge')),
l(j, l) AS (VALUES (0,'Austen'),(1,'Borges'),(2,'Calvino'),(3,'Dickens'),(4,'Eco'),(5,'Faulkner'),(6,'Gaiman'),(7,'Hesse'),(8,'Ishiguro'),(9,'Joyce'),(10,'Kafka'),(11,'Le Guin'))
INSERT INTO authors(id, name, sort, link)
SELECT i, (SELECT f FROM f WHERE j = i % 10) || ' ' || (SELECT l FROM l WHERE j = (i / 10) % 12) || CASE WHEN i > 120 THEN ' ' || (i / 120) ELSE '' END,
       (SELECT l FROM l WHERE j = (i / 10) % 12) || CASE WHEN i > 120 THEN ' ' || (i / 120) ELSE '' END || ', ' || (SELECT f FROM f WHERE j = i % 10),
       CASE WHEN i % 9 = 0 THEN 'https://en.wikipedia.org/wiki/Author_' || i ELSE '' END
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 1500),
w(j, w) AS (VALUES (0,'Fiction'),(1,'Science Fiction'),(2,'Fantasy'),(3,'History'),(4,'Mystery'),(5,'Romance'),(6,'Biography'),(7,'Philosophy'),(8,'News'),(9,'Poetry'))
INSERT INTO tags(id, name, link)
SELECT i, CASE WHEN i <= 10 THEN (SELECT w FROM w WHERE j = i - 1) ELSE (SELECT w FROM w WHERE j = i % 10) || ' / sub ' || i END, '' FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000)
INSERT INTO series(id, name, sort, link) SELECT i, 'The ' || CASE i % 4 WHEN 0 THEN 'Chronicles' WHEN 1 THEN 'Saga' WHEN 2 THEN 'Trilogy' ELSE 'Cycle' END || ' of Realm ' || i,
                                                 CASE i % 4 WHEN 0 THEN 'Chronicles' WHEN 1 THEN 'Saga' WHEN 2 THEN 'Trilogy' ELSE 'Cycle' END || ' of Realm ' || i || ', The', '' FROM n;
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 400)
INSERT INTO publishers(id, name, sort, link) SELECT i, 'Publisher House ' || i, 'Publisher House ' || i, '' FROM n;
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 10)
INSERT INTO ratings(id, rating, link) SELECT i + 1, i, '' FROM n;
INSERT INTO languages(id, lang_code, link)
SELECT k, c, '' FROM (SELECT 1 AS k, 'eng' AS c UNION ALL SELECT 2, 'deu' UNION ALL SELECT 3, 'fra' UNION ALL SELECT 4, 'spa' UNION ALL SELECT 5, 'ita'
                      UNION ALL SELECT 6, 'jpn' UNION ALL SELECT 7, 'rus' UNION ALL SELECT 8, 'por' UNION ALL SELECT 9, 'nld' UNION ALL SELECT 10, 'zho');

-- books (books_insert_trg sets sort/uuid, books_pages_link_create_trigger adds the pages row)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20000*(SELECT scale FROM _cfg)),
w(j, w) AS (VALUES (0,'Night'),(1,'River'),(2,'Garden'),(3,'Empire'),(4,'Shadow'),(5,'Glass'),(6,'Winter'),(7,'Memory'),(8,'Machine'),(9,'Island'),(10,'Silence'),(11,'Crown')),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO books(id, title, timestamp, pubdate, series_index, author_sort, path, has_cover, last_modified)
SELECT i,
       CASE WHEN (h / 8) % 5 = 0 THEN 'The ' ELSE '' END || (SELECT w FROM w WHERE j = (h / 16) % 12) || ' of ' || (SELECT w FROM w WHERE j = (h / 256) % 12) || ' ' || i,
       datetime(1500000000 + i * 15000, 'unixepoch') || '+00:00',
       printf('%04d-%02d-%02d 12:00:00+00:00', 1850 + (h / 4096) % 175, 1 + (h / 65536) % 12, 1 + (h / 1024) % 28),
       CASE WHEN (h / 32) % 3 = 0 THEN 1 + (h / 128) % 9 ELSE 1.0 END,
       'Author, Sort ' || ((h / 64) % 6000),
       'Author ' || ((h / 64) % 6000) || '/Book ' || i || ' (' || i || ')',
       CASE WHEN (h / 2) % 10 < 9 THEN 1 ELSE 0 END,
       datetime(1600000000 + i * 9000 + (h % 100000), 'unixepoch') || '+00:00'
FROM m;

INSERT INTO books_authors_link(book, author)
SELECT id, ((id * 2654435761) % 4294967296 / 64) % (6000*(SELECT scale FROM _cfg)) + 1 FROM books
UNION
SELECT id, ((id * 40503) % (6000*(SELECT scale FROM _cfg))) + 1 FROM books WHERE id % 6 = 0;
INSERT INTO books_tags_link(book, tag)
SELECT b.id, CASE WHEN k.k = 0 THEN 1 + b.id % 10 ELSE 11 + (b.id * 7 + k.k * 131) % 1490 END
FROM books b, (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3) k
WHERE k.k <= (b.id * 2246822519 / 64) % 4
UNION
SELECT id, 9 FROM books WHERE id % 50 = 3;
INSERT INTO books_series_link(book, series) SELECT id, ((id * 2654435761) % 4294967296 / 128) % 2000 + 1 FROM books WHERE ((id * 2654435761) % 4294967296 / 32) % 3 = 0;
INSERT INTO books_publishers_link(book, publisher) SELECT id, (id * 7919) % 400 + 1 FROM books WHERE id % 5 != 0;
INSERT INTO books_ratings_link(book, rating) SELECT id, 1 + (id * 3) % 11 FROM books WHERE id % 3 != 0;
INSERT INTO books_languages_link(book, lang_code, item_order) SELECT id, 1 + (id / 7) % 10 * (id % 4 = 0), 0 FROM books WHERE id % 8 != 0;
INSERT INTO comments(book, text) SELECT id, '<p>A novel about ' || title || '. It explores memory, loss and the long shadow of empire.</p>' FROM books WHERE id % 4 != 0;
INSERT INTO identifiers(book, type, val)
SELECT id, 'isbn', '978' || printf('%010d', (id * 2654435761) % 10000000000) FROM books WHERE id % 10 < 8
UNION ALL SELECT id, 'goodreads', CAST(1000000 + id * 37 AS TEXT) FROM books WHERE id % 3 = 0
UNION ALL SELECT id, 'amazon', printf('B%09d', id * 13) FROM books WHERE id % 5 = 1;
INSERT INTO data(book, format, uncompressed_size, name)
SELECT id, 'EPUB', 200000 + (id * 7919) % 3000000, 'Book ' || id FROM books WHERE id % 10 < 9
UNION ALL SELECT id, 'AZW3', 300000 + (id * 104729) % 4000000, 'Book ' || id FROM books WHERE id % 4 = 0
UNION ALL SELECT id, 'PDF', 1000000 + (id * 15485863) % 20000000, 'Book ' || id FROM books WHERE id % 7 = 0;
UPDATE books_pages_link SET pages = 100 + (book * 37) % 900, algorithm = 1, format = 'EPUB', needs_scan = CASE WHEN book % 20 = 0 THEN 1 ELSE 0 END WHERE book % 3 != 0;

INSERT INTO last_read_positions(book, format, user, device, cfi, epoch, pos_frac)
SELECT id, 'EPUB', CASE WHEN id % 2 = 0 THEN '*' ELSE 'alice' END, CASE WHEN id % 3 = 0 THEN 'kobo' ELSE 'browser' END,
       'epubcfi(/6/' || (id % 40) * 2 || '!/4/2/1:0)', 1700000000 + id * 100.5, ((id * 37) % 100) / 100.0
FROM books WHERE id % 4 = 1;

-- annotations (annotations_fts_insert_trg indexes searchable_text)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20000*(SELECT scale FROM _cfg)),
w(j, w) AS (VALUES (0,'memory'),(1,'river'),(2,'empire'),(3,'garden'),(4,'running'),(5,'silence'),(6,'winter'),(7,'machines'),(8,'kingdom'),(9,'glass')),
m AS (SELECT i, (i * 2246822519) % 4294967296 AS h FROM n)
INSERT INTO annotations(id, book, format, user_type, user, timestamp, annot_id, annot_type, annot_data, searchable_text)
SELECT i, (h / 16) % 4000 * 5 + 1, 'EPUB', CASE WHEN i % 5 = 0 THEN 'web' ELSE 'local' END, CASE WHEN i % 5 = 0 THEN '*' ELSE 'viewer' END,
       1700000000 + i * 1000.25, printf('a%08x', h),
       CASE WHEN i % 6 = 0 THEN 'bookmark' ELSE 'highlight' END,
       CASE WHEN i % 6 = 0 THEN json_object('type', 'bookmark', 'title', 'Bookmark ' || i, 'pos', 'epubcfi(/6/4)', 'pos_type', 'epubcfi', 'timestamp', '2025-01-01T00:00:00Z')
            ELSE json_object('type', 'highlight', 'uuid', printf('u%08x', h), 'highlighted_text', 'The ' || (SELECT w FROM w WHERE j = (h / 64) % 10) || ' of the ' || (SELECT w FROM w WHERE j = (h / 1024) % 10) || ' was ' || (SELECT w FROM w WHERE j = (h / 32768) % 10),
                             'notes', CASE WHEN i % 4 = 0 THEN 'note about ' || (SELECT w FROM w WHERE j = (h / 8) % 10) END,
                             'style', CASE WHEN i % 9 = 0 THEN json_object('type', 'custom', 'kind', 'color', 'which', '#ff00aa')
                                           ELSE json_object('type', 'builtin', 'kind', 'color', 'which', CASE i % 3 WHEN 0 THEN 'yellow' WHEN 1 THEN 'green' ELSE 'blue' END) END,
                             'removed', CASE WHEN i % 40 = 0 THEN json('true') END,
                             'start_cfi', '/2/4', 'end_cfi', '/2/6', 'spine_index', i % 30) END,
       CASE WHEN i % 6 = 0 THEN 'Bookmark ' || i
            ELSE 'The ' || (SELECT w FROM w WHERE j = (h / 64) % 10) || ' of the ' || (SELECT w FROM w WHERE j = (h / 1024) % 10) || ' was ' || (SELECT w FROM w WHERE j = (h / 32768) % 10)
                 || CASE WHEN i % 4 = 0 THEN char(10) || 'note about ' || (SELECT w FROM w WHERE j = (h / 8) % 10) ELSE '' END END
FROM m;
INSERT INTO annotations_dirtied(book) SELECT DISTINCT book FROM annotations WHERE id % 97 = 0;
INSERT INTO metadata_dirtied(book) SELECT id FROM books WHERE id % 131 = 0;
INSERT INTO books_plugin_data(book, name, val) SELECT id, 'kobo_reading_state', json_object('status', id % 3, 'last_read', 1700000000 + id) FROM books WHERE id % 5 = 2;

-- custom columns: #genre (tags-like, '|' separated), #universe (series-like), #read_count (int)
INSERT INTO custom_columns(id, label, name, datatype, mark_for_delete, editable, display, is_multiple, normalized) VALUES
 (1, 'genre', 'Genre', 'text', 0, 1, '{"is_names": false}', 1, 1),
 (2, 'universe', 'Universe', 'series', 0, 1, '{}', 0, 1),
 (3, 'read_count', 'Times read', 'int', 0, 1, '{}', 0, 0);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 60)
INSERT INTO custom_column_1(id, value) SELECT i, 'genre-' || i FROM n;
INSERT INTO books_custom_column_1_link(book, value)
SELECT id, 1 + (id * 7) % 60 FROM books WHERE id % 3 != 2
UNION SELECT id, 1 + (id * 11 + 5) % 60 FROM books WHERE id % 4 = 0;
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 80)
INSERT INTO custom_column_2(id, value) SELECT i, 'Universe ' || i FROM n;
INSERT INTO books_custom_column_2_link(book, value, extra) SELECT id, 1 + (id * 13) % 80, 1 + (id % 12) FROM books WHERE id % 5 = 0;
INSERT INTO custom_column_3(book, value) SELECT id, (id * 7) % 6 FROM books WHERE id % 2 = 0;

-- full-text index of book formats (books_fts_insert_trg indexes searchable_text)
WITH w(j, w) AS (VALUES (0,'memory'),(1,'river'),(2,'empire'),(3,'garden'),(4,'running'),(5,'silence'),(6,'winter'),(7,'machines'),(8,'kingdom'),(9,'glass'),(10,'harbour'),(11,'lantern'))
INSERT INTO books_text(book, timestamp, format, format_hash, format_size, searchable_text, text_size, text_hash)
SELECT d.book, 1700000000 + d.book, d.format, printf('%016x', d.book * 2654435761), d.uncompressed_size,
       'Chapter one. ' || (SELECT w FROM w WHERE j = d.book % 12) || ' and ' || (SELECT w FROM w WHERE j = (d.book / 12) % 12) ||
       ' were all she remembered of the ' || (SELECT w FROM w WHERE j = (d.book / 144) % 12) || '. Chapter two. The ' || (SELECT w FROM w WHERE j = (d.book * 7) % 12) || ' returned.',
       180, printf('%016x', d.book * 40503)
FROM data d WHERE d.format = 'EPUB' AND d.book % 3 != 0;
INSERT OR IGNORE INTO dirtied_formats(book, format) SELECT book, format FROM data WHERE format = 'PDF' AND book % 2 = 0;

COMMIT;
