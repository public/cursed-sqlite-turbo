-- Synthetic data for audiobookshelf. Deterministic (no random()): values come from multiplicative hashes of the row
-- number, with different bits per column. _cfg.scale multiplies the row counts. Scale 1: 2 libraries, 25 users,
-- 12k books (+ library items), 2.5k authors, 1.8k series, ~6.6k bookSeries, ~13.8k bookAuthors, 150 podcasts with 6k
-- episodes, ~14k mediaProgresses, 5k playback sessions. "Now" is 2026-10-28; ~5% of books were added in the last
-- 60 days. Ids are UUID-shaped text with a per-table prefix, e.g. books b00cb00c-0000-4000-8000-000000000042.
-- Timestamps use Sequelize's SQLite DATETIME text format 'YYYY-MM-DD HH:MM:SS.SSS +00:00'.
BEGIN;

CREATE TEMP TABLE w_adj(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO w_adj VALUES (0,'Silent'),(1,'Broken'),(2,'Golden'),(3,'Hidden'),(4,'Last'),(5,'Crimson'),(6,'Iron'),
  (7,'Wandering'),(8,'Forgotten'),(9,'Burning'),(10,'Hollow'),(11,'Winter'),(12,'Shadow'),(13,'Glass'),(14,'Distant'),(15,'Quiet');
CREATE TEMP TABLE w_noun(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO w_noun VALUES (0,'Dragon'),(1,'Kingdom'),(2,'River'),(3,'Witness'),(4,'Empire'),(5,'Garden'),(6,'Throne'),
  (7,'Detective'),(8,'Ocean'),(9,'Mountain'),(10,'Signal'),(11,'Orchard'),(12,'Station'),(13,'Library'),(14,'Storm'),
  (15,'Machine'),(16,'Harbor'),(17,'Archive'),(18,'Crown'),(19,'Labyrinth');
CREATE TEMP TABLE w_first(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO w_first VALUES (0,'Anna'),(1,'Brandon'),(2,'Clara'),(3,'Daniel'),(4,'Elena'),(5,'Frank'),(6,'Grace'),
  (7,'Hiro'),(8,'Isabel'),(9,'James'),(10,'Kate'),(11,'Liam'),(12,'Maya'),(13,'Noah'),(14,'Olivia'),(15,'Peter'),
  (16,'Rosa'),(17,'Samuel'),(18,'Tara'),(19,'Victor'),(20,'Wen'),(21,'Yusuf'),(22,'Zoe'),(23,'Ursula');
CREATE TEMP TABLE w_last(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO w_last VALUES (0,'Abbott'),(1,'Becker'),(2,'Castillo'),(3,'Dumont'),(4,'Eriksen'),(5,'Fischer'),
  (6,'Gallagher'),(7,'Hughes'),(8,'Ivanova'),(9,'Jensen'),(10,'Kowalski'),(11,'Lindqvist'),(12,'Moreau'),
  (13,'Nakamura'),(14,'Okafor'),(15,'Petrov'),(16,'Quinn'),(17,'Rossi'),(18,'Sato'),(19,'Tanaka'),(20,'Varga'),
  (21,'Weber'),(22,'Young'),(23,'Zimmerman'),(24,'Novak'),(25,'Haddad'),(26,'Brennan'),(27,'Oyelaran'),(28,'Silva');
CREATE TEMP TABLE w_genre(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO w_genre VALUES (0,'Fantasy'),(1,'Science Fiction'),(2,'Mystery'),(3,'Thriller'),(4,'Romance'),
  (5,'Historical Fiction'),(6,'Biography'),(7,'History'),(8,'Self-Help'),(9,'Horror'),(10,'Young Adult'),
  (11,'Literary Fiction'),(12,'Science'),(13,'Business'),(14,'Humor');
CREATE TEMP TABLE w_tag(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO w_tag VALUES (0,'favorite'),(1,'to-reread'),(2,'kids'),(3,'book-club'),(4,'dnf'),(5,'award-winner'),
  (6,'commute'),(7,'sleep'),(8,'classic'),(9,'signed');
CREATE TEMP TABLE w_pub(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO w_pub VALUES (0,'Audible Studios'),(1,'Penguin Audio'),(2,'Recorded Books'),(3,'Tantor Audio'),
  (4,'Blackstone Publishing'),(5,'Podium Audio'),(6,'Brilliance Audio'),(7,'HarperAudio');

CREATE TEMP TABLE n(i INTEGER PRIMARY KEY);
WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM c WHERE i < 24000*(SELECT scale FROM _cfg)) INSERT INTO n SELECT i FROM c;

CREATE TEMP TABLE k(nb INTEGER, na INTEGER, ns INTEGER, nu INTEGER, np INTEGER, ne INTEGER, t0 INTEGER);
INSERT INTO k SELECT 12000*scale, 2500*scale, 1800*scale, 25, 150*scale, 40, 1698451200 FROM _cfg;  -- t0 = 2023-10-28

INSERT INTO libraries(id, name, displayOrder, icon, mediaType, provider, settings, extraData, createdAt, updatedAt) VALUES
 ('11111111-0000-4000-8000-000000000001', 'Audiobooks', 1, 'audiobookshelf', 'book', 'audible',
  '{"coverAspectRatio":1,"disableWatcher":false,"skipMatchingMediaWithAsin":false,"autoScanCronExpression":null,"hideSingleBookSeries":true,"onlyShowLaterBooksInContinueSeries":false,"metadataPrecedence":["folderStructure","audioMetatags","nfoFile","txtFiles","opfFile","absMetadata"]}',
  '{}', '2023-10-28 09:00:00.000 +00:00', '2026-10-27 22:00:00.000 +00:00'),
 ('11111111-0000-4000-8000-000000000002', 'Podcasts', 2, 'podcast', 'podcast', 'itunes',
  '{"coverAspectRatio":1,"disableWatcher":false,"autoScanCronExpression":null,"podcastSearchRegion":"us"}',
  '{}', '2023-10-28 09:05:00.000 +00:00', '2026-10-27 22:00:00.000 +00:00');

-- users: 1 root, 2 admins, the rest users; some restricted (no explicit content, tag allow/deny lists)
INSERT INTO users(id, username, email, pash, type, token, isActive, isLocked, lastSeen, permissions, bookmarks, extraData, createdAt, updatedAt)
SELECT printf('eeeeeeee-0000-4000-8000-%012d', i), 'user' || i, 'user' || i || '@example.org', '$2a$08$x',
       CASE WHEN i = 1 THEN 'root' WHEN i <= 3 THEN 'admin' ELSE 'user' END, NULL, 1, 0,
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + 94600000 - i * 7200, 'unixepoch') || ' +00:00',
       json_object('download', json('true'), 'update', json(CASE WHEN i <= 3 THEN 'true' ELSE 'false' END), 'delete', json('false'),
                   'upload', json('false'), 'accessAllLibraries', json('true'), 'accessAllTags', json(CASE WHEN i % 5 = 4 THEN 'false' ELSE 'true' END),
                   'accessExplicitContent', json(CASE WHEN i % 4 = 3 THEN 'false' ELSE 'true' END), 'selectedTagsNotAccessible', json('false'),
                   'librariesAccessible', json_array(), 'itemTagsSelected', CASE WHEN i % 5 = 4 THEN json_array('kids', 'favorite') ELSE json_array() END),
       '[]',
       json_object('seriesHideFromContinueListening',
                   CASE WHEN i % 3 = 2 THEN json_array(printf('5e5e5e5e-0000-4000-8000-%012d', i * 37), printf('5e5e5e5e-0000-4000-8000-%012d', 900000 + i))
                        ELSE json_array() END),
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + i * 86400, 'unixepoch') || ' +00:00',
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + 94600000 - i * 7200, 'unixepoch') || ' +00:00'
FROM n WHERE i <= (SELECT nu FROM k);

-- authors (book library)
INSERT INTO authors(id, name, lastFirst, asin, description, imagePath, createdAt, updatedAt, libraryId)
SELECT printf('a0a0a0a0-0000-4000-8000-%012d', i),
       (SELECT w FROM w_first WHERE k = h % 24) || ' ' || (SELECT w FROM w_last WHERE k = (h / 32) % 29) || CASE WHEN i > 696 THEN ' ' || i ELSE '' END,
       (SELECT w FROM w_last WHERE k = (h / 32) % 29) || CASE WHEN i > 696 THEN ' ' || i ELSE '' END || ', ' || (SELECT w FROM w_first WHERE k = h % 24),
       CASE WHEN (h / 1024) % 3 = 0 THEN printf('B%09X', h % 68719476736) END,
       CASE WHEN (h / 4096) % 4 = 0 THEN 'Bestselling author of many audiobooks.' END,
       CASE WHEN (h / 8192) % 2 = 0 THEN '/metadata/authors/' || i || '.jpg' END,
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + i * (94600000 / (SELECT na FROM k)), 'unixepoch') || ' +00:00',
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + i * (94600000 / (SELECT na FROM k)) + 3600, 'unixepoch') || ' +00:00',
       '11111111-0000-4000-8000-000000000001'
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n WHERE i <= (SELECT na FROM k));

-- series
INSERT INTO series(id, name, nameIgnorePrefix, description, createdAt, updatedAt, libraryId)
SELECT printf('5e5e5e5e-0000-4000-8000-%012d', i), nm, CASE WHEN nm LIKE 'The %' THEN substr(nm, 5) || ', The' ELSE nm END,
       NULL,
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + i * (94600000 / (SELECT ns FROM k)), 'unixepoch') || ' +00:00',
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + i * (94600000 / (SELECT ns FROM k)), 'unixepoch') || ' +00:00',
       '11111111-0000-4000-8000-000000000001'
FROM (SELECT i, CASE WHEN (h / 8) % 3 = 0 THEN 'The ' ELSE '' END || (SELECT w FROM w_adj WHERE k = (h / 64) % 16) || ' '
              || (SELECT w FROM w_noun WHERE k = (h / 1024) % 20) || ' Saga ' || i AS nm
      FROM (SELECT i, (i * 2246822519) % 4294967296 AS h FROM n WHERE i <= (SELECT ns FROM k)));

-- books
INSERT INTO books(id, title, titleIgnorePrefix, subtitle, publishedYear, publishedDate, publisher, description, isbn, asin,
                  language, explicit, abridged, coverPath, duration, narrators, audioFiles, ebookFile, chapters, tags, genres, createdAt, updatedAt)
SELECT printf('b00cb00c-0000-4000-8000-%012d', i), title,
       CASE WHEN title LIKE 'The %' THEN substr(title, 5) || ', The' ELSE title END,
       CASE WHEN (h / 16) % 4 = 0 THEN 'A ' || lower((SELECT w FROM w_noun WHERE k = (h / 32) % 20)) || ' novel' END,
       CAST(1950 + (h / 128) % 76 AS TEXT), NULL,
       CASE WHEN (h / 512) % 10 = 0 THEN NULL ELSE (SELECT w FROM w_pub WHERE k = (h / 4096) % 8) END,
       'An unabridged recording of book ' || i || '. ' || substr('Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.', 1, 40 + (h % 80)),
       CASE WHEN (h / 65536) % 3 = 0 THEN printf('978%010d', h % 10000000000) END,
       printf('B0%08X', (h * 7) % 4294967296),
       CASE (h / 32768) % 12 WHEN 0 THEN 'German' WHEN 1 THEN 'Spanish' ELSE 'English' END,
       CASE WHEN (h / 262144) % 20 = 0 THEN 1 ELSE 0 END,
       CASE WHEN (h / 524288) % 30 = 0 THEN 1 ELSE 0 END,
       CASE WHEN (h / 2) % 25 = 0 THEN NULL ELSE '/audiobooks/' || i || '/cover.jpg' END,
       dur,
       CASE WHEN nf = 0 THEN json_array() WHEN (h / 8) % 4 = 0
            THEN json_array((SELECT w FROM w_first WHERE k = (h / 64) % 24) || ' ' || (SELECT w FROM w_last WHERE k = (h / 2048) % 29),
                            (SELECT w FROM w_first WHERE k = (h / 3) % 24) || ' ' || (SELECT w FROM w_last WHERE k = (h / 5) % 29))
            ELSE json_array((SELECT w FROM w_first WHERE k = (h / 64) % 24) || ' ' || (SELECT w FROM w_last WHERE k = (h / 2048) % 29)) END,
       CASE nf WHEN 0 THEN json_array()
               WHEN 1 THEN json_array(json_object('index', 1, 'ino', CAST(h AS TEXT), 'metadata', json_object('filename', 'book.m4b', 'ext', '.m4b', 'size', dur * 8000), 'duration', dur, 'codec', 'aac', 'channels', 2))
               ELSE json_array(json_object('index', 1, 'ino', CAST(h AS TEXT), 'metadata', json_object('filename', 'part1.mp3', 'ext', '.mp3', 'size', dur * 4000), 'duration', dur / 3, 'codec', 'mp3', 'channels', 2),
                               json_object('index', 2, 'ino', CAST(h + 1 AS TEXT), 'metadata', json_object('filename', 'part2.mp3', 'ext', '.mp3', 'size', dur * 4000), 'duration', dur / 3, 'codec', 'mp3', 'channels', 2),
                               json_object('index', 3, 'ino', CAST(h + 2 AS TEXT), 'metadata', json_object('filename', 'part3.mp3', 'ext', '.mp3', 'size', dur * 4000), 'duration', dur / 3, 'codec', 'mp3', 'channels', 2)) END,
       CASE WHEN nf = 0 OR (h / 1048576) % 9 = 0 THEN json_object('ino', CAST(h + 9 AS TEXT), 'metadata', json_object('filename', 'book.epub', 'ext', '.epub'), 'ebookFormat', 'epub') END,
       json_array(json_object('id', 0, 'start', 0, 'end', dur / 3, 'title', 'Chapter 1'), json_object('id', 1, 'start', dur / 3, 'end', 2 * dur / 3, 'title', 'Chapter 2'),
                  json_object('id', 2, 'start', 2 * dur / 3, 'end', dur, 'title', 'Chapter 3')),
       CASE (h / 4194304) % 5 WHEN 0 THEN json_array((SELECT w FROM w_tag WHERE k = (h / 33554432) % 10))
                               WHEN 1 THEN json_array((SELECT w FROM w_tag WHERE k = (h / 33554432) % 10), (SELECT w FROM w_tag WHERE k = (h / 3355443) % 10))
                               ELSE json_array() END,
       CASE (h / 7) % 3 WHEN 0 THEN json_array((SELECT w FROM w_genre WHERE k = (h / 1000) % 15))
                        WHEN 1 THEN json_array((SELECT w FROM w_genre WHERE k = (h / 1000) % 15), (SELECT w FROM w_genre WHERE k = (h / 17000) % 15))
                        ELSE json_array((SELECT w FROM w_genre WHERE k = (h / 1000) % 15), (SELECT w FROM w_genre WHERE k = (h / 17000) % 15), (SELECT w FROM w_genre WHERE k = (h / 290000) % 15)) END,
       ts, ts
FROM (SELECT i, h,
             CASE WHEN (h / 8) % 5 = 0 THEN 'The ' ELSE '' END || (SELECT w FROM w_adj WHERE k = (h / 16) % 16) || ' '
               || (SELECT w FROM w_noun WHERE k = (h / 256) % 20) || CASE WHEN (h / 5120) % 3 = 0 THEN ' ' || (2 + (h / 15360) % 7) ELSE '' END AS title,
             3600 + (h / 100) % 90000 AS dur,
             CASE WHEN (h / 9) % 20 = 0 THEN 0 WHEN (h / 9) % 20 < 13 THEN 1 ELSE 3 END AS nf,
             strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + i * (94600000 / (SELECT nb FROM k)), 'unixepoch') || ' +00:00' AS ts
      FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n WHERE i <= (SELECT nb FROM k)));

INSERT INTO libraryItems(id, ino, path, relPath, mediaId, mediaType, isFile, isMissing, isInvalid, mtime, ctime, birthtime, size,
                         lastScan, lastScanVersion, libraryFiles, extraData, createdAt, updatedAt, libraryId, libraryFolderId, title, titleIgnorePrefix)
SELECT printf('1111aaaa-0000-4000-8000-%012d', i), CAST(h AS TEXT), '/audiobooks/' || i, CAST(i AS TEXT), b.id, 'book', 0,
       CASE WHEN (h / 3) % 100 = 0 THEN 1 ELSE 0 END, CASE WHEN (h / 5) % 200 = 0 THEN 1 ELSE 0 END,
       b.createdAt, b.createdAt, b.createdAt, CAST(b.duration * 8000 AS INTEGER) + (h % 100000),
       b.updatedAt, '2.30.0',
       CASE WHEN (h / 11) % 15 = 0
            THEN json_array(json_object('ino', CAST(h AS TEXT), 'metadata', json_object('filename', 'book.m4b', 'ext', '.m4b'), 'isSupplementary', NULL, 'fileType', 'audio'),
                            json_object('ino', CAST(h + 3 AS TEXT), 'metadata', json_object('filename', 'extras.pdf', 'ext', '.pdf'), 'isSupplementary', json('true'), 'fileType', 'ebook'))
            ELSE json_array(json_object('ino', CAST(h AS TEXT), 'metadata', json_object('filename', 'book.m4b', 'ext', '.m4b'), 'isSupplementary', NULL, 'fileType', 'audio')) END,
       '{}', b.createdAt, b.updatedAt, '11111111-0000-4000-8000-000000000001', '22222222-0000-4000-8000-000000000001',
       b.title, b.titleIgnorePrefix
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h, printf('b00cb00c-0000-4000-8000-%012d', i) AS bid FROM n WHERE i <= (SELECT nb FROM k)) x
JOIN books b ON b.id = x.bid;

-- bookAuthors: 1 author per book, 15% a co-author; 30% of books by the 200 prolific authors.
-- The insert trigger fills libraryItems.authorNamesFirstLast/LastFirst.
INSERT INTO bookAuthors(id, createdAt, bookId, authorId)
SELECT printf('ba000000-0000-4000-8000-%012d', i), b.createdAt, b.id,
       printf('a0a0a0a0-0000-4000-8000-%012d', CASE WHEN (h / 16) % 10 < 3 THEN (h / 64) % 200 + 1 ELSE (h / 64) % (SELECT na FROM k) + 1 END)
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n WHERE i <= (SELECT nb FROM k)) x
JOIN books b ON b.id = printf('b00cb00c-0000-4000-8000-%012d', i);
INSERT OR IGNORE INTO bookAuthors(id, createdAt, bookId, authorId)
SELECT printf('ba000000-0000-4000-8000-%012d', 500000 + i), b.createdAt, b.id,
       printf('a0a0a0a0-0000-4000-8000-%012d', (h / 1048576) % (SELECT na FROM k) + 1)
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n WHERE i <= (SELECT nb FROM k)) x
JOIN books b ON b.id = printf('b00cb00c-0000-4000-8000-%012d', i)
WHERE (h / 131072) % 20 < 3;

-- bookSeries: ~55% of books belong to a series; sequence by publication order inside the series, some fractional or missing
INSERT INTO bookSeries(id, sequence, createdAt, bookId, seriesId)
SELECT printf('b5000000-0000-4000-8000-%012d', i),
       CASE WHEN (h / 4) % 40 = 0 THEN NULL WHEN (h / 4) % 40 = 1 THEN rn || '.5' ELSE CAST(rn AS TEXT) END,
       ts, bid, sid
FROM (SELECT i, h, ts, bid, sid, row_number() OVER (PARTITION BY sid ORDER BY i) AS rn
      FROM (SELECT x.i, x.h, b.createdAt AS ts, b.id AS bid,
                   printf('5e5e5e5e-0000-4000-8000-%012d', ((x.h / 2048) * 7) % (SELECT ns FROM k) + 1) AS sid
            FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n WHERE i <= (SELECT nb FROM k)) x
            JOIN books b ON b.id = printf('b00cb00c-0000-4000-8000-%012d', x.i)
            WHERE (x.h / 1024) % 100 < 55));

-- podcasts (podcast library) with episodes
INSERT INTO podcasts(id, title, titleIgnorePrefix, author, releaseDate, feedURL, imageURL, description, language, podcastType, explicit,
                     autoDownloadEpisodes, autoDownloadSchedule, maxEpisodesToKeep, maxNewEpisodesToDownload, coverPath, tags, genres, createdAt, updatedAt, numEpisodes)
SELECT printf('cccccccc-0000-4000-8000-%012d', i), t, t, (SELECT w FROM w_first WHERE k = h % 24) || ' ' || (SELECT w FROM w_last WHERE k = (h / 32) % 29),
       '2024-01-01', 'https://feeds.example.org/' || i || '.xml', 'https://img.example.org/' || i || '.jpg', 'A weekly show.', 'en',
       CASE WHEN i % 7 = 0 THEN 'serial' ELSE 'episodic' END, CASE WHEN (h / 256) % 10 = 0 THEN 1 ELSE 0 END,
       (h / 512) % 2, '0 * * * *', 0, 3, '/podcasts/' || i || '/cover.jpg',
       CASE WHEN (h / 1024) % 3 = 0 THEN json_array((SELECT w FROM w_tag WHERE k = (h / 4096) % 10)) ELSE json_array() END,
       json_array((SELECT w FROM w_genre WHERE k = (h / 65536) % 15), (SELECT w FROM w_genre WHERE k = (h / 3) % 15)),
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + i * 300000, 'unixepoch') || ' +00:00',
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + i * 300000, 'unixepoch') || ' +00:00', (SELECT ne FROM k)
FROM (SELECT i, h, (SELECT w FROM w_adj WHERE k = (h / 16) % 16) || ' ' || (SELECT w FROM w_noun WHERE k = (h / 256) % 20) || ' Podcast ' || i AS t
      FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n WHERE i <= (SELECT np FROM k)));

INSERT INTO libraryItems(id, ino, path, relPath, mediaId, mediaType, isFile, isMissing, isInvalid, mtime, ctime, birthtime, size,
                         lastScan, libraryFiles, extraData, createdAt, updatedAt, libraryId, libraryFolderId, title, titleIgnorePrefix)
SELECT printf('1111aaaa-0000-4000-8000-%012d', 900000 + i), CAST(i AS TEXT), '/podcasts/' || i, CAST(i AS TEXT), p.id, 'podcast', 0, 0, 0,
       p.createdAt, p.createdAt, p.createdAt, 50000000 + i * 1000, p.updatedAt, '[]', '{}', p.createdAt, p.updatedAt,
       '11111111-0000-4000-8000-000000000002', '22222222-0000-4000-8000-000000000002', p.title, p.titleIgnorePrefix
FROM (SELECT i FROM n WHERE i <= (SELECT np FROM k)) x JOIN podcasts p ON p.id = printf('cccccccc-0000-4000-8000-%012d', x.i);

INSERT INTO podcastEpisodes(id, "index", season, episode, episodeType, title, subtitle, description, pubDate, enclosureURL, enclosureSize,
                            enclosureType, publishedAt, audioFile, chapters, extraData, createdAt, updatedAt, podcastId)
SELECT printf('ce000000-0000-4000-8000-%012d', i), e, '1', CAST(e AS TEXT), 'full', 'Episode ' || e || ': ' || (SELECT w FROM w_noun WHERE k = (h / 64) % 20),
       NULL, 'Show notes for episode ' || e, NULL, 'https://cdn.example.org/' || i || '.mp3', 30000000 + h % 50000000, 'audio/mpeg',
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + p * 300000 + e * 604800 + (h % 3600), 'unixepoch') || ' +00:00',
       json_object('index', 1, 'ino', CAST(h AS TEXT), 'metadata', json_object('filename', i || '.mp3', 'ext', '.mp3', 'size', 30000000 + h % 50000000),
                   'duration', 1200 + (h / 128) % 5400, 'codec', 'mp3'),
       '[]', '{}',
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + p * 300000 + e * 604800 + 7200, 'unixepoch') || ' +00:00',
       strftime('%Y-%m-%d %H:%M:%f', (SELECT t0 FROM k) + p * 300000 + e * 604800 + 7200, 'unixepoch') || ' +00:00',
       printf('cccccccc-0000-4000-8000-%012d', p)
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h, (i - 1) / (SELECT ne FROM k) + 1 AS p, (i - 1) % (SELECT ne FROM k) + 1 AS e
      FROM n WHERE i <= (SELECT np * ne FROM k));

-- mediaProgresses: user u has ~3000/u + 50 book progresses (distinct books per user), plus podcast episode progresses.
-- 50% finished, 30% in progress, 5% ebook-only progress, 15% in progress but hidden from continue listening.
INSERT INTO mediaProgresses(id, mediaItemId, mediaItemType, duration, currentTime, isFinished, hideFromContinueListening, ebookLocation,
                            ebookProgress, finishedAt, extraData, createdAt, updatedAt, userId, podcastId)
SELECT printf('dddddddd-0000-4000-8000-%06d%06d', u, j), printf('b00cb00c-0000-4000-8000-%012d', (j * 7919 + u * 104729) % (SELECT nb FROM k) + 1), 'book',
       10000, CASE WHEN f < 10 THEN 10000 WHEN f < 16 THEN 100 + (h / 64) % 9000 WHEN f = 16 THEN 0 ELSE 50 + (h / 64) % 5000 END,
       CASE WHEN f < 10 THEN 1 ELSE 0 END, CASE WHEN f >= 17 THEN 1 ELSE 0 END,
       CASE WHEN f = 16 THEN 'epubcfi(/6/4!/4/2)' END, CASE WHEN f = 16 THEN 0.35 ELSE 0 END,
       CASE WHEN f < 10 THEN strftime('%Y-%m-%d %H:%M:%f', ut, 'unixepoch') || ' +00:00' END,
       json_object('libraryItemId', printf('1111aaaa-0000-4000-8000-%012d', (j * 7919 + u * 104729) % (SELECT nb FROM k) + 1), 'progress', CASE WHEN f < 10 THEN 1 ELSE 0.4 END),
       strftime('%Y-%m-%d %H:%M:%f', ut - 864000, 'unixepoch') || ' +00:00', strftime('%Y-%m-%d %H:%M:%f', ut, 'unixepoch') || ' +00:00',
       printf('eeeeeeee-0000-4000-8000-%012d', u), NULL
FROM (SELECT u.i AS u, j.i AS j, ((u.i * 1000003 + j.i) * 2654435761) % 4294967296 AS h,
             (((u.i * 1000003 + j.i) * 2654435761) % 4294967296 / 16) % 20 AS f,
             (SELECT t0 FROM k) + 94600000 - j.i * 20000 - (((u.i * 1000003 + j.i) * 2654435761) % 4294967296) % 20000 AS ut
      FROM n u JOIN n j ON j.i <= 3000 / u.i + 50 WHERE u.i <= (SELECT nu FROM k));

INSERT INTO mediaProgresses(id, mediaItemId, mediaItemType, duration, currentTime, isFinished, hideFromContinueListening, ebookProgress,
                            finishedAt, extraData, createdAt, updatedAt, userId, podcastId)
SELECT printf('dddddddd-0000-4000-9000-%06d%06d', u, j), printf('ce000000-0000-4000-8000-%012d', ep), 'podcastEpisode', 3000,
       CASE WHEN f < 12 THEN 3000 ELSE 300 END, CASE WHEN f < 12 THEN 1 ELSE 0 END, 0, 0,
       CASE WHEN f < 12 THEN '2026-09-01 10:00:00.000 +00:00' END, '{}',
       '2026-08-01 10:00:00.000 +00:00', '2026-09-01 10:00:00.000 +00:00', printf('eeeeeeee-0000-4000-8000-%012d', u),
       printf('cccccccc-0000-4000-8000-%012d', (ep - 1) / (SELECT ne FROM k) + 1)
FROM (SELECT u.i AS u, j.i AS j, (j.i * 37 + u.i * 811) % (SELECT np * ne FROM k) + 1 AS ep, ((j.i * 2654435761) / 64) % 20 AS f
      FROM n u JOIN n j ON j.i <= 300 / u.i WHERE u.i <= 10);

-- playback sessions (listening history)
INSERT INTO playbackSessions(id, mediaItemId, mediaItemType, displayTitle, displayAuthor, duration, playMethod, mediaPlayer, startTime, currentTime,
                             serverVersion, coverPath, timeListening, mediaMetadata, date, dayOfWeek, extraData, createdAt, updatedAt, userId, deviceId, libraryId)
SELECT printf('fefefefe-0000-4000-8000-%012d', i), printf('b00cb00c-0000-4000-8000-%012d', (h / 32) % (SELECT nb FROM k) + 1), 'book',
       'Book ' || i, 'Author', 30000, (h / 8) % 4, 'html5', (h / 16) % 20000, (h / 16) % 20000 + 900, '2.30.0', NULL, 60 + (h / 1024) % 3000,
       '{}', date(ts, 'unixepoch'), CASE CAST(strftime('%w', ts, 'unixepoch') AS INTEGER) WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday' WHEN 2 THEN 'Tuesday'
         WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday' ELSE 'Saturday' END,
       '{}', strftime('%Y-%m-%d %H:%M:%f', ts, 'unixepoch') || ' +00:00', strftime('%Y-%m-%d %H:%M:%f', ts + 900, 'unixepoch') || ' +00:00',
       printf('eeeeeeee-0000-4000-8000-%012d', (h % 5) * (h % 5) + 1), NULL, '11111111-0000-4000-8000-000000000001'
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h, (SELECT t0 FROM k) + i * (94600000 / (5000 * (SELECT scale FROM _cfg))) AS ts
      FROM n WHERE i <= 5000 * (SELECT scale FROM _cfg));

-- binge listeners: users 1 and 4 finished every book of every 40th series
INSERT INTO mediaProgresses(id, mediaItemId, mediaItemType, duration, currentTime, isFinished, hideFromContinueListening, ebookProgress,
                            finishedAt, extraData, createdAt, updatedAt, userId)
SELECT printf('dddddddd-0000-4000-a000-%06d%s', u.i, substr(bs.id, 25, 12)), bs.bookId, 'book', 10000, 10000, 1, 0, 0,
       '2026-06-01 20:00:00.000 +00:00', '{"progress":1}', '2026-05-20 20:00:00.000 +00:00', '2026-06-01 20:00:00.000 +00:00',
       printf('eeeeeeee-0000-4000-8000-%012d', u.i)
FROM bookSeries bs, (SELECT 1 AS i UNION ALL SELECT 4) u
WHERE CAST(substr(bs.seriesId, 25) AS INTEGER) % 40 = 0
  AND NOT EXISTS (SELECT 1 FROM mediaProgresses mp WHERE mp.userId = printf('eeeeeeee-0000-4000-8000-%012d', u.i) AND mp.mediaItemId = bs.bookId);
UPDATE mediaProgresses SET isFinished = 1, currentTime = duration, finishedAt = updatedAt
WHERE userId IN ('eeeeeeee-0000-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000004')
  AND mediaItemId IN (SELECT bookId FROM bookSeries WHERE CAST(substr(seriesId, 25) AS INTEGER) % 40 = 0);

-- one duplicated progress row per heavy user (the startup cleanup query finds these)
INSERT INTO mediaProgresses(id, mediaItemId, mediaItemType, duration, currentTime, isFinished, hideFromContinueListening, ebookProgress, extraData, createdAt, updatedAt, userId)
SELECT 'dddddddd-ffff-4000-8000-' || substr(id, 25), mediaItemId, mediaItemType, duration, 1, 0, 0, 0, '{}', '2024-01-01 00:00:00.000 +00:00', '2024-01-01 00:00:00.000 +00:00', userId
FROM mediaProgresses WHERE mediaItemType = 'book' AND id LIKE 'dddddddd-0000-4000-8000-00000_000007';

DROP TABLE n; DROP TABLE k;
DROP TABLE w_adj; DROP TABLE w_noun; DROP TABLE w_first; DROP TABLE w_last; DROP TABLE w_genre; DROP TABLE w_tag; DROP TABLE w_pub;
COMMIT;
