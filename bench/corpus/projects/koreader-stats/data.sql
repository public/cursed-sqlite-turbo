-- Synthetic data for KOReader's statistics, vocabulary builder and cover browser databases. Deterministic (no
-- random()): values come from multiplicative hashes of the row number. "Now" is 2026-10-31 23:59:59 UTC (1793491199;
-- today starts at 1793404800); reading history covers the 4 years before it.
-- Scale 1: 430 books (150-900 pages; 30 only glanced at), 200k page_stat_data rows in 8k evening reading sessions of 25 page turns;
-- books are read mostly in sequence (75 % of sessions go to the "current" book, 12 % to 8 favourites that are
-- re-read all the time and carry ~3k rows each, the rest to an earlier book). A third of the books were partly read at another layout (total_pages = 80 % of today's
-- page count) and every 7th at twice the page count, so the page_stat view really rescales.
-- Sync stand-ins: income_* is the other device's DB (same books under other ids, minus the newest 2 % of rows, plus
-- 25 books and ~10k rows only it has); cached_* is the last synced copy (rows before 2026-10-01, plus 3 books since
-- deleted locally). Vocabulary: 3k words from 150 titles; bookinfo: 600 files.
-- _cfg.scale multiplies page_stat_data rows (sessions), words and files; the book count stays 430 (the sync joins an
-- unindexed book_id_map per remote row, so books x rows would grow quadratically).
BEGIN;

CREATE TEMP TABLE _s AS SELECT (SELECT scale FROM _cfg) AS s, 400 AS nb,
  200000 * (SELECT scale FROM _cfg) AS nr, 8000 * (SELECT scale FROM _cfg) AS ns;

-- main.lua:427-432
WITH RECURSIVE counter AS
    (
        SELECT 1 as N UNION ALL
        SELECT N + 1 FROM counter WHERE N < 1000
    )
    INSERT INTO numbers SELECT N AS number FROM counter;

INSERT INTO book (id, title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT nb FROM _s) + 30)
SELECT i,
  (CASE (h / 16) % 8 WHEN 0 THEN 'The ' WHEN 1 THEN 'A History of ' WHEN 2 THEN 'Notes on ' WHEN 3 THEN '' WHEN 4 THEN 'Return to '
     WHEN 5 THEN 'The Last ' WHEN 6 THEN 'Letters from ' ELSE 'On ' END) || 'Book ' || i,
  CASE WHEN i % 13 = 0 THEN '' ELSE 'Author ' || (1 + (h / 256) % 180) || CASE WHEN i % 11 = 0 THEN char(10) || 'Co Author ' || (i % 40) ELSE '' END END,
  (h / 4096) % 6, 0, (h / 65536) % 30,
  150 + (h / 1024) % 750,
  CASE WHEN i % 4 = 0 THEN 'Series ' || (i % 37) || ' #' || (1 + i % 5) END,
  CASE (h / 8) % 5 WHEN 0 THEN 'de' WHEN 1 THEN 'fr' ELSE 'en' END,
  printf('%08x%08x%08x%08x', h, (i * 2246822519) % 4294967296, (i * 3266489917) % 4294967296, i),
  0, 0
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n);

-- Sessions: session k starts in the evening of day k*1461/ns; 85 % go to the "current" book (books read in order),
-- the rest to an earlier book. Each session is 25 consecutive page turns.
CREATE TEMP TABLE _sess AS
WITH RECURSIVE n(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM n WHERE k < (SELECT ns FROM _s) - 1)
SELECT k, h,
  CASE WHEN h % 100 < 75 THEN 1 + (k * (SELECT nb FROM _s)) / (SELECT ns FROM _s)
       WHEN h % 100 < 87 THEN 1 + 25 * ((h / 128) % 8)
       ELSE 1 + ((h / 128) % (1 + (k * (SELECT nb FROM _s)) / (SELECT ns FROM _s))) END AS b,
  1667260800 + (k * 1461 / (SELECT ns FROM _s)) * 86400 + 64800 + (h / 1024) % 14400 - 7200 * ((h / 64) % 2) AS t0
FROM (SELECT k, (k * 2654435761) % 4294967296 AS h FROM n);
CREATE TEMP TABLE _sess2 AS
SELECT s.k, s.h, s.b, s.t0, bk.pages,
  row_number() OVER (PARTITION BY s.b ORDER BY s.k) - 1 AS nth,
  CASE WHEN s.b % 7 = 0 THEN bk.pages * 2
       WHEN s.b % 3 = 0 AND (s.h / 4096) % 2 = 0 THEN (bk.pages * 4) / 5
       ELSE bk.pages END AS tp
FROM _sess s JOIN book bk ON bk.id = s.b;

INSERT OR IGNORE INTO page_stat_data (id_book, page, start_time, duration, total_pages)
WITH RECURSIVE j(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM j WHERE j < 24)
SELECT b, 1 + (nth * 25 + j) % tp, t0 + j * 47 + (h / (j + 1)) % 40,
  CASE WHEN (h / (j + 3)) % 50 = 0 THEN 240 + (h / 7) % 300 ELSE 8 + ((h / (j + 2)) % 112) END, tp
FROM _sess2, j
ORDER BY t0, j;

-- 30 books only glanced at (a few page turns each): candidates for "delete books read for less than N seconds"
INSERT OR IGNORE INTO page_stat_data (id_book, page, start_time, duration, total_pages)
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 149)
SELECT (SELECT nb FROM _s) + 1 + i / 5, 1 + i % 5, 1700000000 + i * 86400 + (i % 5) * 50, 30 + i % 40,
  (SELECT pages FROM book WHERE id = (SELECT nb FROM _s) + 1 + i / 5)
FROM n;

UPDATE book SET last_open = (SELECT max(start_time) FROM page_stat_data WHERE id_book = book.id);
UPDATE book SET last_open = 1667260800 - 86400 * (id % 90) WHERE last_open IS NULL;
UPDATE book SET (total_read_pages, total_read_time) =
  (SELECT count(DISTINCT page), sum(duration) FROM page_stat_data WHERE id_book = book.id);

-- Other device: same books under shifted ids (minus 2 it deleted, and ~1 % of rows it dropped), plus 25 books only it has
INSERT INTO income_book (id, title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages)
SELECT id + 5000, title, authors, notes, last_open + CASE WHEN id % 5 = 0 THEN 3600 ELSE 0 END, highlights, pages, series,
  language, md5, total_read_time, total_read_pages FROM book WHERE id % 199 != 0;
INSERT INTO income_book (id, title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 25)
SELECT 9000 + i, 'Phone Book ' || i, 'Author ' || i, 0, 1793300000 + i * 600, 0, 300 + i * 7, NULL, 'en',
  printf('%032x', i * 7919), 0, 0 FROM n;
INSERT INTO income_page_stat_data (id_book, page, start_time, duration, total_pages)
SELECT id_book + 5000, page, start_time, duration + CASE WHEN start_time % 17 = 0 THEN 5 ELSE 0 END, total_pages
FROM page_stat_data WHERE start_time < 1793491199 - 86400 * 30 AND id_book % 199 != 0 AND start_time % 101 != 0;
INSERT OR IGNORE INTO income_page_stat_data (id_book, page, start_time, duration, total_pages)
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 9999)
SELECT CASE WHEN i % 2 = 0 THEN 9001 + (i / 400) % 25 ELSE 5000 + 1 + ((i * 2654435761) % 4294967296) % (SELECT nb FROM _s) END,
  1 + i % 280, 1790812800 + i * 233, 20 + i % 90, 300 + (i / 400) % 25 * 7
FROM n;

-- Last synced copy: main ids, rows before 2026-10-01, plus 3 books deleted locally since
INSERT INTO cached_book SELECT * FROM book;
INSERT INTO cached_book (id, title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages)
VALUES (7001, 'Deleted Book 1', 'X', 0, 1780000000, 0, 200, NULL, 'en', 'd1', 100, 10),
       (7002, 'Deleted Book 2', 'X', 0, 1780000000, 0, 200, NULL, 'en', 'd2', 100, 10),
       (7003, 'Deleted Book 3', 'X', 0, 1780000000, 0, 200, NULL, 'en', 'd3', 100, 10);
INSERT INTO cached_page_stat_data SELECT * FROM page_stat_data WHERE start_time < 1790812800;
INSERT INTO income_book (id, title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages)
SELECT id + 1000, title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages
FROM cached_book WHERE id > 7000 AND id < 7003;

-- main.lua:3197-3200, as it stands after the new books were inserted
INSERT INTO book_id_map
SELECT m.id as mid, i.id as iid FROM book m
INNER JOIN income_book i
ON (m.title, m.authors, m.md5) = (i.title, i.authors, i.md5);

-- Vocabulary builder
INSERT INTO title (id, name, filter)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 150)
SELECT i, 'The Book ' || i, CASE WHEN i % 10 = 0 THEN 0 ELSE 1 END FROM n;
INSERT INTO vocabulary (word, title_id, create_time, review_time, due_time, review_count, prev_context, next_context, streak_count, highlight)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 3000 * (SELECT s FROM _s))
SELECT 'word' || printf('%05d', i) || substr('abcdefghij', 1 + i % 10, 1), 1 + (h / 16) % 150,
  1667260800 + i * (1461 * 86400 / (3000 * (SELECT s FROM _s))),
  CASE WHEN i % 4 = 0 THEN NULL ELSE 1667260800 + i * (1461 * 86400 / (3000 * (SELECT s FROM _s))) + 86400 * (1 + i % 30) END,
  1667260800 + i * (1461 * 86400 / (3000 * (SELECT s FROM _s))) + 86400 * (1 + (h / 256) % 400),
  (h / 64) % 8, 'the sentence before the word ' || i, 'and the rest of the sentence', (h / 512) % 5,
  CASE WHEN i % 6 = 0 THEN 'highlighted passage ' || i END
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n);

-- Cover browser cache (cover blobs left out)
INSERT INTO bookinfo (directory, filename, filesize, filemtime, in_progress, unsupported, cover_fetched, has_meta, has_cover,
  cover_sizetag, pages, title, authors, series, series_index, language, keywords, description, cover_w, cover_h)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 600 * (SELECT s FROM _s))
SELECT '/mnt/onboard/Books/' || (CASE i % 6 WHEN 0 THEN 'Fiction/' WHEN 1 THEN 'Non-fiction/' WHEN 2 THEN 'Comics/' ELSE '' END),
  'book_' || i || CASE WHEN i % 9 = 0 THEN '.pdf' ELSE '.epub' END, 200000 + (h % 5000000), 1700000000 + h % 90000000,
  CASE WHEN i % 97 = 0 THEN 1 ELSE 0 END, CASE WHEN i % 151 = 0 THEN 'no engine' END, 'Y', 'Y', CASE WHEN i % 8 = 0 THEN NULL ELSE 'Y' END,
  '1072x1448', 100 + h % 800, 'Book ' || i, 'Author ' || (1 + h % 180), NULL, NULL, 'en', NULL, 'A description.', 300, 400
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n);

DROP TABLE _sess;
DROP TABLE _sess2;
COMMIT;
