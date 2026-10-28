-- Synthetic data for FreshRSS (one user's SQLite database). Deterministic: values come from multiplicative hashes of
-- the row number, different bits per column. "Now" is 1761600000 (2025-10-27 21:20 UTC); entry ids are microsecond
-- receive timestamps, like uTimeString(). Scale 1: 20 categories, 300 feeds, 100k entries over ~70 days (a few heavy
-- feeds, ~80 % of older entries read), 15 labels, ~25k label links, 2k pending rows in entrytmp.
BEGIN;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20)
INSERT INTO category(id, name, kind, lastUpdate, error, attributes)
SELECT i,
       CASE WHEN i = 1 THEN 'Uncategorized' ELSE printf('%s %d', CASE i % 7 WHEN 0 THEN 'News' WHEN 1 THEN 'Tech' WHEN 2 THEN 'Science' WHEN 3 THEN 'Sports' WHEN 4 THEN 'Blogs' WHEN 5 THEN 'Comics' ELSE 'Podcasts' END, i) END,
       CASE WHEN i % 9 = 0 THEN 2 ELSE 0 END,
       CASE WHEN i % 9 = 0 THEN 1761600000 - i * 4000 ELSE 0 END,
       0,
       json_object('position', CASE WHEN i % 3 = 0 THEN i END, 'opml_url', CASE WHEN i % 9 = 0 THEN 'https://example.org/opml/' || i || '.xml' END)
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300*(SELECT scale FROM _cfg)),
f AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n),
w(k, w) AS (VALUES (0,'Linux'),(1,'Rust'),(2,'Privacy'),(3,'Election'),(4,'Climate'),(5,'Football'),(6,'SQLite'),(7,'Kernel'),
                   (8,'Browser'),(9,'Space'),(10,'Economy'),(11,'Music'),(12,'Android'),(13,'Security'),(14,'Recipes'),(15,'Travel'))
INSERT INTO feed(id, url, kind, category, name, website, description, lastUpdate, priority, pathEntries, httpAuth, error, ttl, attributes,
                 cache_nbEntries, cache_nbUnreads)
SELECT i,
       printf('https://site%d.example.org/feed.xml', i),
       CASE WHEN (h / 8) % 23 = 0 THEN 10 ELSE 0 END,
       ((i * 7) % 20) + 1,
       printf('%s Weekly %d', (SELECT w FROM w WHERE k = (h / 16) % 16), i),
       printf('https://site%d.example.org/', i),
       'Feed number ' || i,
       1761600000 - ((h / 256) % 7200),
       CASE (h / 4096) % 15 WHEN 0 THEN 20 WHEN 1 THEN 0 WHEN 2 THEN -10 WHEN 3 THEN 0 ELSE 10 END,
       NULL, '',
       CASE WHEN (h / 65536) % 25 = 0 THEN 1761600000 - ((h / 256) % 3600) ELSE 0 END,
       CASE WHEN (h / 1048576) % 10 = 0 THEN 7200 WHEN (h / 1048576) % 10 = 1 THEN -3600 ELSE 0 END,
       json_object('archiving', json_object('keep_period', 'P3M', 'keep_max', 200, 'keep_min', 50,
                                            'keep_favourites', json('true'), 'keep_labels', json('true'), 'keep_unreads', json('false'))),
       0, 0
FROM f;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 100000*(SELECT scale FROM _cfg)),
cfg AS (SELECT scale AS s, 100000*scale AS total, 300*scale AS nf FROM _cfg),
e AS (SELECT i, (i * 2654435761) % 4294967296 AS h, (i * 40503 + 7919) % 65536 AS g FROM n),
w(k, w) AS (VALUES (0,'linux'),(1,'rust'),(2,'privacy'),(3,'election'),(4,'climate'),(5,'football'),(6,'sqlite'),(7,'kernel'),
                   (8,'browser'),(9,'space'),(10,'economy'),(11,'music'),(12,'android'),(13,'security'),(14,'recipe'),(15,'travel')),
r AS (
  SELECT i, h, g,
         1761600000 * 1000000 - (cfg.total - i) * 60000000 / cfg.s AS id,
         -- a quarter of entries come from 10 heavy feeds
         CASE WHEN (h / 32) % 4 = 0 THEN ((h / 128) % 10) * 29 + 1 ELSE ((h / 128) % cfg.nf) + 1 END AS id_feed,
         (SELECT w FROM w WHERE k = (h / 2048) % 16) AS w1,
         (SELECT w FROM w WHERE k = g % 16) AS w2,
         (SELECT w FROM w WHERE k = (g / 16) % 16) AS w3,
         cfg.total AS total
  FROM e, cfg)
INSERT INTO entry(id, guid, title, author, content, link, date, lastSeen, lastModified, lastUserModified, hash, is_read, is_favorite,
                  id_feed, tags, attributes)
SELECT id,
       printf('https://site%d.example.org/posts/%d', id_feed, i),
       printf('%s: %s update number %d on %s', upper(substr(w1, 1, 1)) || substr(w1, 2), w2, i % 977, w3),
       CASE WHEN (h / 8192) % 5 = 0 THEN printf('Author %d; Author %d', (h / 65536) % 400, (g / 256) % 400) ELSE printf('Author %d', (h / 65536) % 400) END,
       printf('<p>Today in %s: a long read about %s and %s.</p><p>Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua %d.</p>%s',
              w1, w2, w3, i, CASE WHEN g % 7 = 0 THEN '<p><a href="https://github.com/example/' || w2 || '">source</a></p>' ELSE '' END),
       printf('https://site%d.example.org/%s/%d.html', id_feed, w1, i),
       id / 1000000 - (h % 5400),
       CASE WHEN (g / 4) % 50 = 0 THEN 1761600000 - (h % 1800) ELSE id / 1000000 + (g % 600) END,
       CASE WHEN (g / 8) % 3 = 0 THEN NULL ELSE id / 1000000 + (g % 900) END,
       NULL,
       unhex(printf('%08x%08x%08x%08x', h, (g * 65521) % 4294967296, (h + g * 3) % 4294967296, i)),
       CASE WHEN i < total * 4 / 5 THEN (h / 1048576) % 10 < 9 ELSE (h / 1048576) % 10 < 3 END,
       (h / 33554432) % 40 = 0,
       id_feed,
       CASE WHEN g % 3 = 0 THEN '' ELSE '#' || w2 || ' #' || w3 END,
       CASE WHEN g % 11 = 0 THEN json_object('enclosures', json_array(json_object('url', 'https://cdn.example.org/' || i || '.jpg', 'type', 'image/jpeg')))
            ELSE '{}' END
FROM r;

-- read/favorite entries carry a user-modification time
UPDATE entry SET lastUserModified = lastSeen + 120 WHERE is_read = 1 AND (id / 1000000) % 4 <> 0;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 15)
INSERT INTO tag(id, name, attributes)
SELECT i, json_extract('["read later","work","reference","to share","cooking","long reads","tools","videos","ideas","papers","security","fun","archive","watchlist","inbox"]', '$[' || (i - 1) || ']'),
       json_object('color', printf('#%06x', (i * 2654435761) % 16777216))
FROM n;

INSERT OR IGNORE INTO entrytag(id_tag, id_entry)
SELECT ((rowid * 2654435761) / 65536) % 15 + 1, id FROM entry WHERE ((rowid * 2654435761) / 4096) % 5 = 0
UNION ALL
SELECT ((rowid * 40503) / 64) % 15 + 1, id FROM entry WHERE ((rowid * 40503) / 1024) % 13 = 0;

-- pending entries fetched by the last refresh: ids above entry's, a few duplicates of existing guids
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000*(SELECT scale FROM _cfg)),
e AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT OR IGNORE INTO entrytmp(id, guid, title, author, content, link, date, lastSeen, hash, is_read, is_favorite, id_feed, tags, attributes)
SELECT 1761600000 * 1000000 + i * 1500000,
       CASE WHEN i % 50 = 0 THEN (SELECT guid FROM entry WHERE id_feed = ((e.h / 128) % 300) + 1 LIMIT 1)
            ELSE printf('https://site%d.example.org/posts/new-%d', ((h / 128) % 300) + 1, i) END,
       printf('Fresh item %d about sqlite and linux', i),
       printf('Author %d', (h / 65536) % 400),
       printf('<p>New content %d. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p>', i),
       printf('https://site%d.example.org/new/%d.html', ((h / 128) % 300) + 1, i),
       1761600000 - (h % 7200),
       1761600000 + i,
       unhex(printf('%08x%08x%08x%08x', h, i, h / 3, i * 7)),
       0, 0,
       ((h / 128) % 300) + 1,
       '#sqlite',
       '{}'
FROM e;

UPDATE feed SET cache_nbEntries = (SELECT COUNT(*) FROM entry e WHERE e.id_feed = feed.id),
                cache_nbUnreads = (SELECT COUNT(*) FROM entry e WHERE e.id_feed = feed.id AND e.is_read = 0);

COMMIT;
