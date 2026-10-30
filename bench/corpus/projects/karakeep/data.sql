-- Synthetic data for Karakeep, shaped after karakeep-app/karakeep#3088 (one heavy user with ~42k bookmarks,
-- ~348k tag links, 40 smart lists). Deterministic: values come from multiplicative hashes of the row number.
-- "Now" is 1790000000 (epoch seconds; drizzle's mode:"timestamp" columns store seconds).
-- Scale 1: 5 users, 40k bookmarks (u1 owns ~90 %), 80 % links / 12 % texts / 8 % assets, ~5.9k tags (u1: 3.5k used
-- + 300 never attached), ~300k tagsOnBookmarks with a Zipf-like tag popularity (AI-tagging shape: 75 % attachedBy
-- 'ai'), 30 manual + 40 smart lists for u1, ~17k list memberships, ~60k assets, 7k highlights. Bookmarks span six
-- years with most of them recent. _cfg.scale multiplies bookmarks (and so tag links, assets, list memberships,
-- highlights); tag and list counts stay fixed.
BEGIN;

INSERT INTO user(id, name, email, emailVerified, role, timezone, createdAt) VALUES
  ('u1', 'Heavy Hoarder', 'u1@example.com', 1600000000, 'admin', 'Europe/Amsterdam', 1600000000),
  ('u2', 'User Two', 'u2@example.com', 1650000000, 'user', 'UTC', 1650000000),
  ('u3', 'User Three', 'u3@example.com', 1700000000, 'user', 'America/New_York', 1700000000),
  ('u4', 'User Four', 'u4@example.com', 1720000000, 'user', 'UTC', 1720000000),
  ('u5', 'User Five', 'u5@example.com', 1750000000, 'user', 'Asia/Tokyo', 1750000000);

CREATE TEMP TABLE _dom(k INTEGER PRIMARY KEY, d TEXT);
INSERT INTO _dom VALUES (0,'github.com'),(1,'news.ycombinator.com'),(2,'www.youtube.com'),(3,'medium.com'),
  (4,'en.wikipedia.org'),(5,'www.reddit.com'),(6,'arxiv.org'),(7,'dev.to'),(8,'www.nytimes.com'),
  (9,'stackoverflow.com'),(10,'blog.rust-lang.org'),(11,'www.theverge.com'),(12,'substack.com'),(13,'lwn.net'),
  (14,'docs.python.org'),(15,'www.bbc.co.uk');

-- 40 named tags occupy the most popular ranks of u1's tag list; everything else is "<Word> <n>" (AI-tagger style).
CREATE TEMP TABLE _tn(r INTEGER PRIMARY KEY, n TEXT);
INSERT INTO _tn VALUES (1,'AI'),(2,'Programming'),(3,'News'),(4,'Design'),(5,'UI'),(6,'Productivity'),(7,'Web Development'),
  (8,'MachineLearning'),(9,'Python'),(10,'JavaScript'),(11,'Tutorial'),(12,'LLM'),(13,'Startups'),(14,'Security'),
  (15,'Open Source'),(16,'Databases'),(17,'Science'),(18,'Career'),(19,'Video'),(20,'Archive'),(21,'Self-Hosting'),
  (22,'Linux'),(23,'Product Management'),(24,'Recipes'),(25,'Finance'),(26,'Health'),(27,'Music'),(28,'Books'),
  (29,'History'),(30,'Rust'),(31,'Go'),(32,'DevOps'),(33,'Kubernetes'),(34,'SQLite'),(35,'Typography'),
  (36,'Photography'),(37,'Travel'),(38,'Climate'),(39,'Economics'),(40,'Privacy');
CREATE TEMP TABLE _w(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO _w VALUES (0,'Project'),(1,'Software'),(2,'Productivity'),(3,'Research'),(4,'Programming'),(5,'Marketing'),
  (6,'Hardware'),(7,'Process'),(8,'Education'),(9,'Gaming'),(10,'Politics'),(11,'Architecture');

-- bookmarks: age skewed towards now (age = 6 years * (1 - x)^2). Column "createdAt" is the first-save time,
-- "lastSavedAt" is what the API calls createdAt (equal unless re-saved).
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40000*(SELECT scale FROM _cfg)),
g AS (SELECT i, h, CAST(1790000000 - 189216000.0 * (1.0 - x) * (1.0 - x) - (h % 86400) AS INTEGER) AS ts
      FROM (SELECT i, (i * 2654435761) % 4294967296 AS h, i * 1.0 / (40000*(SELECT scale FROM _cfg)) AS x FROM n))
INSERT INTO bookmarks(id, createdAt, archived, favourited, userId, taggingStatus, note, title, type, summary,
                      modifiedAt, summarizationStatus, source, embeddingStatus, lastSavedAt)
SELECT 'b' || i, ts,
  CASE WHEN (h / 16) % 10 < 3 THEN 1 ELSE 0 END,
  CASE WHEN (h / 256) % 25 < 2 THEN 1 ELSE 0 END,
  CASE WHEN h % 100 < 90 THEN 'u1' ELSE 'u' || (2 + (h / 100) % 4) END,
  CASE WHEN (h / 4096) % 50 = 0 THEN 'failure' ELSE 'success' END,
  CASE WHEN (h / 8192) % 10 = 0 THEN 'Note ' || i || ': worth re-reading, see the section on caching' ELSE NULL END,
  CASE WHEN (h / 1024) % 100 < 80 THEN NULL ELSE 'Saved item ' || i END,
  CASE WHEN (h / 1024) % 100 < 80 THEN 'link' WHEN (h / 1024) % 100 < 92 THEN 'text' ELSE 'asset' END,
  CASE WHEN (h / 65536) % 4 = 0 THEN 'This article discusses topic ' || (h % 977) || ' and how it relates to modern software.' ELSE NULL END,
  ts + (h % 3600),
  CASE WHEN (h / 65536) % 4 = 0 THEN 'success' ELSE 'pending' END,
  CASE (h / 32768) % 20 WHEN 0 THEN 'api' WHEN 1 THEN 'cli' WHEN 2 THEN 'mobile' WHEN 3 THEN 'mobile'
    WHEN 4 THEN 'rss' WHEN 5 THEN 'rss' WHEN 6 THEN 'import' WHEN 7 THEN 'import' WHEN 8 THEN 'singlefile'
    WHEN 9 THEN 'extension' WHEN 10 THEN 'extension' WHEN 11 THEN 'extension' WHEN 12 THEN 'extension'
    WHEN 13 THEN 'extension' ELSE 'web' END,
  'done',
  CASE WHEN (h / 131072) % 20 = 0 THEN ts + 86400 * (1 + h % 30) ELSE ts END
FROM g;

-- link details: Zipf-ish domains (16 named, ~400 more), 4 % plain http, ~3 % of titles mention Rust.
INSERT INTO bookmarkLinks(id, url, title, description, imageUrl, favicon, crawledAt, crawlStatus, crawlStatusCode,
                          author, publisher, readerViewStatus, readerViewScore)
SELECT b.id,
  CASE WHEN (h / 8) % 25 = 0 THEN 'http://' ELSE 'https://' END ||
  CASE WHEN dk < 16 THEN (SELECT d FROM _dom WHERE k = dk) ELSE 'site' || dk || '.example.com' END ||
  '/' || CASE (h / 64) % 4 WHEN 0 THEN 'posts/' WHEN 1 THEN 'blog/' WHEN 2 THEN 'watch?v=' ELSE '' END || 'item-' || (h % 1000003),
  CASE WHEN (h / 512) % 33 = 0 THEN 'Why Rust makes systems programming fun, part ' || (h % 50)
       ELSE 'How to think about topic ' || (h % 9973) || ' in ' || (2018 + h % 9) END,
  'A long-form piece on topic ' || (h % 9973) || '. It covers background, trade-offs and a worked example.',
  'https://cdn.example.com/img/' || (h % 100000) || '.jpg',
  'https://' || CASE WHEN dk < 16 THEN (SELECT d FROM _dom WHERE k = dk) ELSE 'site' || dk || '.example.com' END || '/favicon.ico',
  b.createdAt + 60,
  CASE WHEN (h / 2048) % 100 < 6 THEN 'failure' ELSE 'success' END,
  CASE WHEN (h / 2048) % 100 < 6 THEN 404 WHEN (h / 2048) % 100 < 8 THEN 403 ELSE 200 END,
  CASE WHEN (h / 4) % 3 = 0 THEN 'Author ' || (h % 500) ELSE NULL END,
  CASE WHEN dk < 16 THEN (SELECT d FROM _dom WHERE k = dk) ELSE NULL END,
  CASE WHEN (h / 16384) % 3 = 0 THEN 'unavailable' ELSE 'available' END, (h / 16) % 100
FROM (SELECT id, createdAt, h, CAST(416.0 * x * x * x AS INTEGER) AS dk
      FROM (SELECT id, createdAt, h, ((h / 1048576) % 10000) / 10000.0 AS x
            FROM (SELECT id, createdAt, (CAST(substr(id, 2) AS INTEGER) * 2246822519) % 4294967296 AS h
                  FROM bookmarks WHERE type = 'link'))) AS b;

INSERT INTO bookmarkTexts(id, text, sourceUrl)
SELECT id, 'Quick note ' || substr(id, 2) || ': remember to compare the two approaches before deciding. ' ||
           'Pros and cons listed below, with links to the design docs.', NULL
FROM bookmarks WHERE type = 'text';

INSERT INTO bookmarkAssets(id, assetType, assetId, content, fileName, sourceUrl)
SELECT id, CASE WHEN CAST(substr(id, 2) AS INTEGER) % 3 = 0 THEN 'pdf' ELSE 'image' END, 'as' || substr(id, 2) || '_0',
  NULL, 'upload-' || substr(id, 2) || CASE WHEN CAST(substr(id, 2) AS INTEGER) % 3 = 0 THEN '.pdf' ELSE '.png' END,
  CASE WHEN CAST(substr(id, 2) AS INTEGER) % 4 = 0 THEN 'https://files.example.com/' || substr(id, 2) ELSE NULL END
FROM bookmarks WHERE type = 'asset';

-- assets: main asset for asset bookmarks; screenshot (70 %), banner (80 %), html content (15 %) for links.
INSERT INTO assets(id, assetType, bookmarkId, userId, size, contentType, fileName)
SELECT 'as' || substr(b.id, 2) || '_' || k.k, k.t, b.id, b.userId,
  CASE k.t WHEN 'linkScreenshot' THEN 150000 + (CAST(substr(b.id, 2) AS INTEGER) * 7919) % 400000
           WHEN 'linkBannerImage' THEN 20000 + (CAST(substr(b.id, 2) AS INTEGER) * 7919) % 200000
           WHEN 'linkHtmlContent' THEN 60000 + (CAST(substr(b.id, 2) AS INTEGER) * 7919) % 300000
           ELSE 300000 + (CAST(substr(b.id, 2) AS INTEGER) * 7919) % 5000000 END,
  CASE k.t WHEN 'linkHtmlContent' THEN 'text/html' WHEN 'bookmarkAsset' THEN 'application/pdf' ELSE 'image/png' END,
  NULL
FROM bookmarks b JOIN (SELECT 0 AS k, 'bookmarkAsset' AS t UNION ALL SELECT 1, 'linkScreenshot'
                       UNION ALL SELECT 2, 'linkBannerImage' UNION ALL SELECT 3, 'linkHtmlContent') k
WHERE (k.k = 0 AND b.type = 'asset')
   OR (k.k = 1 AND b.type = 'link' AND (CAST(substr(b.id, 2) AS INTEGER) * 2654435761) % 10 < 7)
   OR (k.k = 2 AND b.type = 'link' AND (CAST(substr(b.id, 2) AS INTEGER) * 40503) % 10 < 8)
   OR (k.k = 3 AND b.type = 'link' AND (CAST(substr(b.id, 2) AS INTEGER) * 97) % 20 < 3);

-- tags: u1 has ranks 1..3500 (t1..t3500) plus 300 never-attached tags (t3501..t3800); u2..u5 have 500 each.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 5800)
INSERT INTO bookmarkTags(id, name, createdAt, userId)
SELECT 't' || i,
  CASE WHEN i <= 3800 THEN coalesce((SELECT n FROM _tn WHERE r = i), (SELECT w FROM _w WHERE k = i % 12) || ' ' || i)
       ELSE coalesce((SELECT n FROM _tn WHERE r = (i - 3800 - 1) % 500 + 1), (SELECT w FROM _w WHERE k = i % 12) || ' ' || ((i - 3800 - 1) % 500 + 1)) END,
  1600000000 + i * 30000,
  CASE WHEN i <= 3800 THEN 'u1' ELSE 'u' || (2 + (i - 3801) / 500) END
FROM n;

-- tag links: each bookmark draws 3..14 tags (avg ~8.5); rank = 1 + 3500 * x^2 (u1) or 1 + 500 * x^2 (others).
WITH RECURSIVE j(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM j WHERE k < 14),
bb AS (SELECT id, userId, lastSavedAt, CAST(substr(id, 2) AS INTEGER) AS i FROM bookmarks),
d AS (SELECT bb.id, bb.userId, bb.lastSavedAt, bb.i, j.k,
             ((bb.i * 14 + j.k) * 2654435761) % 4294967296 AS h
      FROM bb JOIN j ON j.k <= 3 + (bb.i * 40503) % 12)
INSERT OR IGNORE INTO tagsOnBookmarks(bookmarkId, tagId, attachedAt, attachedBy)
SELECT id,
  CASE WHEN userId = 'u1' THEN 't' || (1 + CAST(3500 * x * x AS INTEGER))
       ELSE 't' || (3800 + (CAST(substr(userId, 2) AS INTEGER) - 2) * 500 + 1 + CAST(500 * x * x AS INTEGER)) END,
  lastSavedAt + 120,
  CASE WHEN (h / 1024) % 4 = 0 THEN 'human' ELSE 'ai' END
FROM (SELECT id, userId, lastSavedAt, h, ((h / 4096) % 100000) / 100000.0 AS x FROM d);

-- lists: u1 has 30 manual lists (l1..l30; l3 is 'Reading') and 40 smart lists (s1..s40); the others 3 manual each.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 30)
INSERT INTO bookmarkLists(id, name, icon, createdAt, userId, parentId, type, query, description, public)
SELECT 'l' || i, CASE i WHEN 3 THEN 'Reading' WHEN 1 THEN 'Inbox' WHEN 2 THEN 'Work' ELSE 'Collection ' || i END,
  '📁', 1600000000 + i * 86400, 'u1', CASE WHEN i > 20 THEN 'l2' ELSE NULL END, 'manual', NULL, NULL, i % 7 = 0
FROM n;
CREATE TEMP TABLE _sq(k INTEGER PRIMARY KEY, q TEXT);
INSERT INTO _sq VALUES (0,'#UI'),(1,'#AI or #MachineLearning or #LLM'),(2,'#Programming -#Archive'),(3,'is:fav #Design'),
  (4,'age:<1y #News -is:archived'),(5,'url:github.com or title:rust'),(6,'-is:tagged'),(7,'has:highlights list:Reading'),
  (8,'-is:inlist is:link after:2025-01-01'),(9,'#Python #Tutorial'),(10,'#Rust or #Go'),(11,'#Security -is:archived'),
  (12,'#Recipes'),(13,'#Video is:link'),(14,'#Books or #History'),(15,'#SQLite');
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40)
INSERT INTO bookmarkLists(id, name, icon, createdAt, userId, parentId, type, query, description, public)
SELECT 's' || i, 'Smart ' || i, '✨', 1650000000 + i * 86400, 'u1', NULL, 'smart',
  CASE WHEN i <= 16 THEN (SELECT q FROM _sq WHERE k = i - 1) ELSE '#' || (SELECT n FROM _tn WHERE r = i - 16 + 6) END,
  NULL, 0
FROM n;
INSERT INTO bookmarkLists(id, name, icon, createdAt, userId, type, public)
SELECT 'l' || (30 + (u - 2) * 3 + k), 'List ' || k, '📁', 1700000000, 'u' || u, 'manual', 0
FROM (SELECT 2 AS u UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5)
JOIN (SELECT 1 AS k UNION ALL SELECT 2 UNION ALL SELECT 3);

INSERT INTO listCollaborators(id, listId, userId, role, createdAt, addedBy) VALUES
  ('lc1', 'l1', 'u2', 'viewer', 1700000000, 'u1'), ('lc2', 'l2', 'u3', 'editor', 1700000000, 'u1'),
  ('lc3', 'l7', 'u2', 'viewer', 1700000000, 'u1');

-- memberships: ~35 % of bookmarks in one list (skewed: Reading is the biggest), 8 % in a second one.
INSERT OR IGNORE INTO bookmarksInLists(bookmarkId, listId, addedAt)
SELECT id, CASE WHEN userId = 'u1' THEN 'l' || CASE 1 + CAST(30 * x * x AS INTEGER) WHEN 1 THEN 3 WHEN 3 THEN 1 ELSE 1 + CAST(30 * x * x AS INTEGER) END
                ELSE 'l' || (30 + (CAST(substr(userId, 2) AS INTEGER) - 2) * 3 + 1 + (h % 3)) END,
  lastSavedAt + 300
FROM (SELECT id, userId, lastSavedAt, h, ((h / 4096) % 10000) / 10000.0 AS x
      FROM (SELECT id, userId, lastSavedAt, (CAST(substr(id, 2) AS INTEGER) * 2246822519) % 4294967296 AS h FROM bookmarks))
WHERE h % 100 < 35;
INSERT OR IGNORE INTO bookmarksInLists(bookmarkId, listId, addedAt)
SELECT id, 'l' || (4 + h % 27), lastSavedAt + 900
FROM (SELECT id, userId, lastSavedAt, (CAST(substr(id, 2) AS INTEGER) * 3266489917) % 4294967296 AS h FROM bookmarks)
WHERE userId = 'u1' AND h % 100 < 8;

-- highlights: 7k per scale unit on link bookmarks, 4 % mention "design".
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 7000*(SELECT scale FROM _cfg))
INSERT INTO highlights(id, bookmarkId, userId, startOffset, endOffset, color, note, createdAt, text)
SELECT 'h' || n.i, b.id, b.userId, (n.i * 37) % 5000, (n.i * 37) % 5000 + 40 + n.i % 300,
  CASE n.i % 4 WHEN 0 THEN 'yellow' WHEN 1 THEN 'red' WHEN 2 THEN 'green' ELSE 'blue' END,
  CASE WHEN n.i % 9 = 0 THEN 'follow up on this' ELSE NULL END,
  b.lastSavedAt + 3600 + n.i % 7200,
  CASE WHEN n.i % 25 = 0 THEN 'Good design is as little design as possible, item ' || n.i
       ELSE 'The key insight is that the cost model changes once the data no longer fits, item ' || n.i END
FROM n JOIN bookmarks b ON b.id = 'b' || (1 + (n.i * 2654435761) % (40000*(SELECT scale FROM _cfg)));

COMMIT;
