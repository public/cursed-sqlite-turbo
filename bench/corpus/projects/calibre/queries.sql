-- calibre (kovidgoyal/calibre @ e850e21, GPL-3.0). apsw/sqlite3 with `?` positional parameters; table and column
-- names are spliced in with str.format/f-strings from field metadata, so those statements are one instantiation each
-- (tagged dynamic). Calibre registers aggregates (sortconcat, concat, aum_sortconcat, identifiers_concat), scalar
-- functions (title_sort, uuid4, books_list_filter) and a `calibre` FTS5 tokenizer; substitutions are marked @modified.

-- @id calibre.view.meta
-- @src resources/metadata_sqlite.sql:210-227 (CREATE VIEW meta; queried by src/calibre/library/database.py:935-984)
-- @style none (view body)
-- @tags hotpath
-- @note The `meta` view over every book: nine correlated subqueries per row (ordered author concat, publisher/rating/tags/series via nested IN, MAX size, format concat).
-- @modified sortconcat(bal.id, name) -> group_concat(name, ',' ORDER BY bal.id); concat(x) -> group_concat(x, ',') (app-registered aggregates)
SELECT id, title,
       (SELECT group_concat(name, ',' ORDER BY bal.id) FROM books_authors_link AS bal JOIN authors ON(author = authors.id) WHERE book = books.id) authors,
       (SELECT name FROM publishers WHERE publishers.id IN (SELECT publisher from books_publishers_link WHERE book=books.id)) publisher,
       (SELECT rating FROM ratings WHERE ratings.id IN (SELECT rating from books_ratings_link WHERE book=books.id)) rating,
       timestamp,
       (SELECT MAX(uncompressed_size) FROM data WHERE book=books.id) size,
       (SELECT group_concat(name, ',') FROM tags WHERE tags.id IN (SELECT tag from books_tags_link WHERE book=books.id)) tags,
       (SELECT text FROM comments WHERE book=books.id) comments,
       (SELECT name FROM series WHERE series.id IN (SELECT series FROM books_series_link WHERE book=books.id)) series,
       series_index,
       sort,
       author_sort,
       (SELECT group_concat(format, ',') FROM data WHERE data.book=books.id) formats,
       path,
       pubdate,
       uuid
FROM books;

-- @id calibre.legacy.meta_authors_by_id
-- @src src/calibre/library/database.py:947
-- @style ? positional
-- @tags hotpath
-- @note Point read through the meta view: the optimizer has to flatten the view and evaluate just the authors subquery for one book.
-- @modified the view's sortconcat aggregate is group_concat(... ORDER BY bal.id) in schema.sql
-- @param ?1 4242
SELECT authors FROM meta WHERE id=?1;

-- @id calibre.legacy.meta2_refresh
-- @src src/calibre/library/database2.py:423-520 (CREATE TEMP VIEW meta2, read by src/calibre/library/caches.py:1156 "SELECT * FROM meta2"), custom columns from src/calibre/library/custom_columns.py:652-681
-- @style none; column list assembled from a template per field plus one line per custom column
-- @tags hotpath,dynamic
-- @note Legacy library refresh: the meta2 view body with ~15 correlated subqueries per book (6 link-table INNER JOIN aggregates, identifiers, languages, pages, three custom columns incl. a series index).
-- @modified app aggregates replaced: sortconcat(link.id, x) -> group_concat(x, ',' ORDER BY link.id); sortconcat_bar -> group_concat(x, '|' ORDER BY link.id); aum_sortconcat(link.id, name, sort, link) -> group_concat(name || ':::' || sort || ':::' || link, ':#:' ORDER BY link.id); identifiers_concat(type, val) -> group_concat(type || ':' || val, ',')
SELECT
id,
title,
(SELECT group_concat(name, ',' ORDER BY link.id) FROM books_authors_link AS link INNER JOIN
    authors ON(link.author=authors.id) WHERE link.book=books.id)
    authors,
timestamp,
(SELECT MAX(uncompressed_size) FROM data WHERE book=books.id) size,
(SELECT ratings.rating FROM books_ratings_link AS link INNER JOIN
    ratings ON(link.rating=ratings.id) WHERE link.book=books.id)
    rating,
(SELECT group_concat(name) FROM books_tags_link AS link INNER JOIN
    tags ON(link.tag=tags.id) WHERE link.book=books.id)
    tags,
(SELECT text FROM comments WHERE book=books.id) comments,
(SELECT name FROM books_series_link AS link INNER JOIN
    series ON(link.series=series.id) WHERE link.book=books.id)
    series,
(SELECT name FROM books_publishers_link AS link INNER JOIN
    publishers ON(link.publisher=publishers.id) WHERE link.book=books.id)
    publisher,
series_index,
sort,
author_sort,
(SELECT group_concat(format) FROM data WHERE data.book=books.id) formats,
path,
pubdate,
uuid,
has_cover,
(SELECT group_concat(authors.name || ':::' || authors.sort || ':::' || authors.link, ':#:' ORDER BY link.id) FROM books_authors_link AS link INNER JOIN
    authors ON(link.author=authors.id) WHERE link.book=books.id)
    au_map,
last_modified,
(SELECT group_concat(type || ':' || val, ',') FROM identifiers WHERE identifiers.book=books.id) identifiers,
(SELECT group_concat(languages.lang_code, ',' ORDER BY link.id) FROM books_languages_link AS link INNER JOIN
    languages ON(link.lang_code=languages.id) WHERE link.book=books.id)
    languages,
(SELECT pages FROM books_pages_link WHERE books_pages_link.book=books.id) pages,
(SELECT group_concat(custom_column_1.value, '|' ORDER BY link.id) FROM books_custom_column_1_link AS link INNER JOIN
    custom_column_1 ON(link.value=custom_column_1.id) WHERE link.book=books.id)
    custom_1,
(SELECT custom_column_2.value FROM books_custom_column_2_link AS link INNER JOIN
    custom_column_2 ON(link.value=custom_column_2.id) WHERE link.book=books.id)
    custom_2,(SELECT extra FROM books_custom_column_2_link WHERE books_custom_column_2_link.book=books.id)
    custom_index_2,
(SELECT value FROM custom_column_3 WHERE book=books.id) custom_3
FROM books;

-- @id calibre.view.tag_browser_tags
-- @src resources/metadata_sqlite.sql:328-337 (CREATE VIEW tag_browser_tags)
-- @style none (view body)
-- @note Tag browser counts: per tag a correlated COUNT on the link table and a correlated 3-way join AVG(rating).
SELECT id, name,
       (SELECT COUNT(id) FROM books_tags_link WHERE tag=tags.id) count,
       (SELECT AVG(ratings.rating)
        FROM books_tags_link AS tl, books_ratings_link AS bl, ratings
        WHERE tl.tag=tags.id AND bl.book=tl.book AND
        ratings.id = bl.rating AND ratings.rating <> 0) avg_rating,
       name AS sort
FROM tags;

-- @id calibre.view.tag_browser_authors
-- @src resources/metadata_sqlite.sql:228-237 (CREATE VIEW tag_browser_authors)
-- @style none (view body)
-- @note Same shape over 6k authors: correlated COUNT plus correlated AVG over a link-link-ratings join.
SELECT id, name,
       (SELECT COUNT(id) FROM books_authors_link WHERE author=authors.id) count,
       (SELECT AVG(ratings.rating)
        FROM books_authors_link AS tl, books_ratings_link AS bl, ratings
        WHERE tl.author=authors.id AND bl.book=tl.book AND
        ratings.id = bl.rating AND ratings.rating <> 0) avg_rating,
       sort AS sort
FROM authors;

-- @id calibre.view.tag_browser_custom_column
-- @src src/calibre/db/backend.py:1590-1601 (CREATE VIEW tag_browser_{table} for a normalized custom column)
-- @style none (view body), table names by f-string
-- @tags dynamic
-- @note Custom-column tag browser view body: correlated COUNT and AVG over the custom link table joined to ratings.
SELECT id, value,
       (SELECT COUNT(id) FROM books_custom_column_1_link WHERE value=custom_column_1.id) count,
       (SELECT AVG(r.rating)
        FROM books_custom_column_1_link, books_ratings_link as bl, ratings as r
        WHERE books_custom_column_1_link.value=custom_column_1.id and bl.book=books_custom_column_1_link.book and
              r.id = bl.rating and r.rating <> 0) avg_rating,
       value AS sort
FROM custom_column_1;

-- @id calibre.legacy.tag_browser_news
-- @src src/calibre/library/database2.py:1929-1930 (view defined at src/calibre/library/database2.py:390-404)
-- @style f-string table/column names
-- @tags dynamic
-- @note News category: SELECT DISTINCT from a view with a three-level nested IN (SELECT DISTINCT ...) chain over books_tags_link plus a correlated COUNT.
SELECT id, name, count, avg_rating, sort
FROM tag_browser_news;

-- @id calibre.view.tag_browser_ratings
-- @src resources/metadata_sqlite.sql:308-317 (CREATE VIEW tag_browser_ratings)
-- @style none (view body)
-- @note Ratings browser: correlated COUNT plus a correlated self-join of books_ratings_link with ratings, where the inner `ratings` shadows the outer one.
SELECT id, rating,
       (SELECT COUNT(id) FROM books_ratings_link WHERE rating=ratings.id) count,
       (SELECT AVG(ratings.rating)
        FROM books_ratings_link AS tl, books_ratings_link AS bl, ratings
        WHERE tl.rating=ratings.id AND bl.book=tl.book AND
        ratings.id = bl.rating AND ratings.rating <> 0) avg_rating,
       rating AS sort
FROM ratings;

-- @id calibre.load.books_table_columns
-- @src src/calibre/db/tables.py:140-162 (read_books_table_columns)
-- @style column list by str.format from field metadata
-- @tags hotpath,dynamic
-- @note Library open: one scan of books for every books-table field.
SELECT id, title, sort, timestamp, pubdate, series_index, author_sort, path, uuid, has_cover, last_modified FROM books;

-- @id calibre.load.sizes
-- @src src/calibre/db/tables.py:180-186 (SizeTable.read)
-- @style none
-- @tags hotpath
-- @note Library open: LEFT JOIN of books to a GROUP BY MAX() derived table over data.
SELECT books.id, s.size FROM books LEFT JOIN (SELECT book, MAX(uncompressed_size) AS size FROM data GROUP BY book) AS s ON s.book=books.id;

-- @id calibre.items.ids_for_names
-- @src src/calibre/db/tables.py:325 (item_ids_for_names, case-sensitive)
-- @style ? positional, IN list sized to the names
-- @tags hot-small,dynamic
-- @note Resolving tag names to ids when editing metadata: IN list on the UNIQUE NOCASE name.
-- @param ?1 'Fantasy'
-- @param ?2 'History'
-- @param ?3 'Poetry / sub 19'
SELECT name, id FROM tags WHERE name IN (?1,?2,?3);

-- @id calibre.annotations.fts_search_snippet
-- @src src/calibre/db/backend.py:2800-2833 (search_annotations)
-- @style ? positional, table and snippet size by f-string
-- @tags hotpath,dynamic
-- @note Annotation search in the viewer/browser: FTS5 MATCH joined back to the content table, snippet(), user and type filters, ORDER BY rank.
-- @param ?1 '>>>'
-- @param ?2 '<<<'
-- @param ?3 'empire'
-- @param ?4 'local'
-- @param ?5 'viewer'
-- @param ?6 'highlight'
SELECT annotations.id, annotations.book, annotations.format, annotations.user_type, annotations.user, annotations.annot_data, snippet(annotations_fts, 0, ?1, ?2, '…', 30) FROM annotations  JOIN annotations_fts ON annotations.id = annotations_fts.rowid WHERE annotations_fts MATCH ?3 AND annotations.user_type = ?4 AND annotations.user = ?5 AND annotations.annot_type = ?6  ORDER BY annotations_fts.rank ;

-- @id calibre.annotations.fts_search_stemmed_highlight
-- @src src/calibre/db/backend.py:2800-2833 (search_annotations, use_stemming, no snippet size)
-- @style ? positional, table by f-string
-- @tags dynamic
-- @note Stemmed (porter) FTS5 variant with highlight() and a boolean MATCH expression.
-- @param ?1 '<b>'
-- @param ?2 '</b>'
-- @param ?3 'run* OR machine'
SELECT annotations.id, annotations.book, annotations.format, annotations.user_type, annotations.user, annotations.annot_data, highlight(annotations_fts_stemmed, 0, ?1, ?2) FROM annotations  JOIN annotations_fts_stemmed ON annotations.id = annotations_fts_stemmed.rowid WHERE annotations_fts_stemmed MATCH ?3 ORDER BY annotations_fts_stemmed.rank ;

-- @id calibre.annotations.all_for_user
-- @src src/calibre/db/backend.py:2921-2933 (all_annotations)
-- @style ? positional, WHERE assembled from optional clauses
-- @tags hotpath,dynamic
-- @note Annotations browser default listing: filtered scan sorted by timestamp DESC.
-- @param ?1 'local'
-- @param ?2 'viewer'
-- @param ?3 'highlight'
SELECT id, book, format, user_type, user, annot_data FROM annotations WHERE  user_type = ?1 AND user = ?2 AND  annot_type = ?3  ORDER BY timestamp DESC ;

-- @id calibre.annotations.custom_styles
-- @src src/calibre/db/backend.py:2983-2985
-- @style none
-- @note Discovering custom highlight styles: two json_extract predicates over every annotation's JSON.
SELECT annot_data FROM annotations WHERE json_extract(annot_data, '$.style.type') = 'custom' AND json_extract(annot_data, '$.removed') IS NULL;

-- @id calibre.annotations.count_for_book
-- @src src/calibre/db/backend.py:3021-3029
-- @style ? positional
-- @tags hot-small
-- @note Per-book annotation count excluding removed ones (json_extract on the book's rows).
-- @param ?1 1006
SELECT count(id) FROM annotations
WHERE book=?1 AND json_extract(annot_data, '$.removed') IS NULL;

-- @id calibre.annotations.for_book
-- @src src/calibre/db/backend.py:344-349 (annotations_for_book)
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Opening a book in the viewer: its annotations for one format and user.
-- @param ?1 1006
-- @param ?2 'EPUB'
-- @param ?3 'local'
-- @param ?4 'viewer'
SELECT annot_data FROM annotations WHERE book=?1 AND format=?2 AND user_type=?3 AND user=?4;

-- @id calibre.annotations.merge_dirtied
-- @src src/calibre/db/backend.py:3015
-- @style none
-- @tags batch
-- @note Periodic flush: INSERT OR IGNORE ... SELECT from annotations_dirtied into metadata_dirtied.
INSERT or IGNORE INTO metadata_dirtied(book) SELECT book FROM annotations_dirtied;

-- @id calibre.fts.search_books
-- @src src/calibre/db/fts/connect.py:155-200 (FTS.search)
-- @style ? positional, table and snippet size by f-string
-- @tags hotpath,dynamic
-- @note Full-text book search: external-content FTS5 MATCH joined to books_text, snippet() with markers, ORDER BY rank.
-- @modified `fts_db.books_text` -> `books_text` (the app attaches the FTS database as fts_db); books_fts uses unicode61 instead of the app's `calibre` tokenizer (schema.sql)
-- @param ?1 char(29)
-- @param ?2 char(29)
-- @param ?3 'harbour AND lantern'
SELECT books_text.id, books_text.book, books_text.format , snippet("books_fts", 0, ?1, ?2, '…', 30) FROM books_text  JOIN books_fts ON books_text.id = books_fts.rowid WHERE  "books_fts" MATCH ?3 ORDER BY books_fts.rank ;

-- @id calibre.fts.search_books_one_book_stemmed
-- @src src/calibre/db/fts/connect.py:155-200 (FTS.search with use_stemming and a single restrict_to_book_ids entry)
-- @style ? positional, book id inlined by f-string
-- @tags dynamic
-- @note Search inside one book (viewer): stemmed external-content FTS5 MATCH plus an inlined book filter, highlight() and rank ordering.
-- @modified `fts_db.books_text` -> `books_text`; books_fts_stemmed uses porter unicode61 instead of the app's `calibre` tokenizer
-- @param ?1 '<b>'
-- @param ?2 '</b>'
-- @param ?3 'remember*'
SELECT books_text.id, books_text.book, books_text.format , highlight("books_fts_stemmed", 0, ?1, ?2) FROM books_text  JOIN books_fts_stemmed ON books_text.id = books_fts_stemmed.rowid WHERE  books_text.book == 4241 AND  "books_fts_stemmed" MATCH ?3 ORDER BY books_fts_stemmed.rank ;

-- @id calibre.fts.dirty_all_formats
-- @src src/calibre/db/fts/connect.py:60-66 (dirty_existing)
-- @style none
-- @tags batch
-- @note Enabling full-text indexing: queue every format with INSERT OR IGNORE ... SELECT from main.data.
-- @modified `fts_db.dirtied_formats` -> `dirtied_formats` (attached database in the app)
INSERT OR IGNORE INTO dirtied_formats(book, format)
SELECT book, format FROM main.data;

-- @id calibre.stats.books_by_month
-- @src src/calibre/db/cache.py:1089-1115 (books_by_month, restricted)
-- @style f-string column/table, ? IN list in batches
-- @tags dynamic
-- @note Books-by-date report for a virtual library: CAST(substr()) year/month extraction with an IN list of book ids.
-- @param ?1 3
-- @param ?2 6
-- @param ?3 9
-- @param ?4 12
-- @param ?5 15
-- @param ?6 18
-- @param ?7 21
-- @param ?8 24
SELECT
    CAST(substr(pubdate, 1, 4) AS INTEGER),
    CAST(substr(pubdate, 6, 2) AS INTEGER),
    id
FROM books
 WHERE id IN (?1,?2,?3,?4,?5,?6,?7,?8);

-- @id calibre.pages.set_upsert
-- @src src/calibre/db/cache.py:2151-2162 (set_pages)
-- @style ? positional
-- @tags hot-small
-- @note Background page counter result: INSERT ... ON CONFLICT(book) DO UPDATE with excluded.*.
-- @param ?1 4243
-- @param ?2 312
-- @param ?3 1
-- @param ?4 'EPUB'
-- @param ?5 524288
-- @param ?6 '2026-10-28 10:00:00+00:00'
INSERT INTO books_pages_link (book, pages, algorithm, format, format_size, timestamp, needs_scan) VALUES
                 (?1,?2,?3,?4,?5,?6,0)
ON CONFLICT(book) DO UPDATE SET
    pages = excluded.pages, algorithm = excluded.algorithm,
    format = excluded.format, format_size = excluded.format_size,
    timestamp = excluded.timestamp, needs_scan = excluded.needs_scan;

-- @id calibre.books.insert
-- @src src/calibre/db/cache.py:2747
-- @style ? positional
-- @tags hot-small
-- @note Adding a book: short INSERT that fires books_insert_trg (UPDATE of sort/uuid) and books_pages_link_create_trigger.
-- @modified the trigger's title_sort()/uuid4() are replaced in schema.sql (see its header)
-- @param ?1 'A New Book'
-- @param ?2 1.0
-- @param ?3 'Doe, Jane'
INSERT INTO books(title, series_index, author_sort) VALUES (?1, ?2, ?3);

-- @id calibre.books.fields_by_id
-- @src src/calibre/db/cache.py:2793
-- @style ? positional
-- @tags hot-small
-- @note Re-reading the books-table fields of one book by primary key.
-- @param ?1 4242
SELECT sort, series_index, author_sort, uuid, has_cover FROM books WHERE id=?1;

-- @id calibre.last_read.positions
-- @src src/calibre/db/cache.py:3873-3885 (get_last_read_positions)
-- @style ? positional, optional clauses appended
-- @tags hot-small,dynamic
-- @note Viewer opening a book: last read positions for book + format.
-- @param ?1 4241
-- @param ?2 'EPUB'
SELECT device,cfi,epoch,pos_frac,format,user FROM last_read_positions WHERE book=?1 AND format=?2;
