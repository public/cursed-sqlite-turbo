-- Synthetic Places data for firefox-places. Deterministic (no random()): values come from multiplicative hashes of
-- the row number, different bits per column. Times are PRTime (microseconds since the Unix epoch); "now" is
-- 1792022400000000 (2026-10-14) and history spans 120 days back.
-- url_hash / page_url_hash / fixed_icon_url_hash hold a core-SQL stand-in for Places' hash() (see queries.sql
-- header): (length(url) * 4503599627370496 + unicode(substr(url, -1, 1)) * 859983745857 + unicode(substr(url, -2, 1)) * 620455851591 + unicode(substr(url, -3, 1)) * 380927957327 + unicode(substr(url, -4, 1)) * 141400063061 + unicode(substr(url, -5, 1)) * 1001383796573 + unicode(substr(url, -6, 1)) * 761855902307 + unicode(substr(url, -7, 1)) * 522328008043 + unicode(substr(url, -8, 1)) * 282800113777 + unicode(substr(url, -9, 1)) * 43272219513 + unicode(substr(url, -10, 1)) * 903255953023 + unicode(substr(url, -11, 1)) * 663728058759 + unicode(substr(url, -12, 1)) * 424200164493 + unicode(substr(url, -13, 1)) * 184672270229 + unicode(substr(url, -14, 1)) * 1044656003739 + unicode(substr(url, -15, 1)) * 805128109475 + unicode(substr(url, -16, 1)) * 565600215209).
-- Scale 1: 1000 hosts (www./bare pairs share a fixed host), 1000 origins, 40k places, 150k visits, ~3.3k bookmarks
-- in a 4-level folder tree, 40 tags with ~2k tag entries, 5k input-history rows, 300 open tabs, 3k favicon pages.
BEGIN;

CREATE TEMP TABLE _host AS
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 999)
SELECT i AS hi,
       CASE i WHEN 0 THEN 'www.mozilla.org' WHEN 1 THEN 'mozilla.org' WHEN 2 THEN 'developer.mozilla.org'
              WHEN 3 THEN 'github.com' WHEN 4 THEN 'www.github.com' WHEN 5 THEN 'en.wikipedia.org'
              WHEN 6 THEN 'www.google.com' WHEN 7 THEN 'news.ycombinator.com' WHEN 8 THEN 'www.sqlite.org' WHEN 9 THEN 'sqlite.org'
              ELSE CASE i % 4 WHEN 0 THEN 'www.site' || (i / 2) || '.com' WHEN 1 THEN 'site' || (i / 2) || '.com'
                              WHEN 2 THEN 'blog' || i || '.example.org' ELSE 'shop' || i || '.example.net' END END AS host,
       CASE WHEN i % 17 = 5 THEN 'http://' ELSE 'https://' END AS prefix
FROM n;

-- rev_host is the reversed host plus a trailing dot (no reverse() in core SQL, so reverse char by char)
CREATE TEMP TABLE _rev AS
WITH RECURSIVE r(hi, rest, acc) AS (
  SELECT hi, host, '' FROM _host
  UNION ALL SELECT hi, substr(rest, 2), substr(rest, 1, 1) || acc FROM r WHERE rest <> '')
SELECT hi, acc || '.' AS rev_host FROM r WHERE rest = '';

INSERT INTO moz_origins(id, prefix, host, frecency, recalc_frecency, alt_frecency, recalc_alt_frecency, block_until_ms, block_pages_until_ms)
SELECT hi + 1, prefix, host, 0, (hi % 20 = 3), NULL, 0, CASE WHEN hi % 97 = 13 THEN 1792022400000 + 86400000 END, NULL FROM _host;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n),
p AS (SELECT m.i, m.h, hs.hi, hs.host, hs.prefix,
             hs.prefix || hs.host || CASE WHEN m.i <= 1000 THEN '/'
               ELSE '/' || CASE (m.h / 5) % 4 WHEN 0 THEN 'docs' WHEN 1 THEN 'en-US/docs/Web' WHEN 2 THEN 'blog' ELSE 'p' END
                    || '/' || ((m.h / 13) % 300) || '/item-' || m.i || CASE WHEN (m.h / 31) % 9 = 0 THEN '?utm_source=feed&id=' || m.i ELSE '' END END AS url
      FROM m JOIN _host hs ON hs.hi = CASE WHEN m.i <= 1000 THEN m.i - 1 ELSE ((((m.h / 7) % 1000) * ((m.h / 7) % 1000)) / 1000) END)
INSERT INTO moz_places(id, url, title, rev_host, visit_count, hidden, typed, frecency, last_visit_date, guid, foreign_count, url_hash,
                       description, preview_image_url, site_name, origin_id, recalc_frecency, alt_frecency, recalc_alt_frecency)
SELECT p.i, p.url,
       CASE WHEN (p.h / 997) % 25 = 0 THEN NULL WHEN p.i <= 1000 THEN 'Home - ' || p.host ELSE 'Item ' || p.i || ' | ' || p.host END,
       r.rev_host, 0, CASE WHEN (p.h / 4093) % 40 = 0 THEN 1 ELSE 0 END, 0,
       CASE WHEN (p.h / 4093) % 40 = 0 THEN 0 WHEN (p.h / 8191) % 200 = 0 THEN -1
            ELSE 100 + ((p.h / 3) % 1000) * ((p.h / 3) % 1000) / (CASE WHEN p.i <= 1000 THEN 50 ELSE 400 END) END,
       NULL,
       substr(replace(replace(printf('%08x%08x', p.h, (p.i * 40503) % 4294967296), '0', 'A'), '1', '_'), 1, 12),
       0, (length(p.url) * 4503599627370496 + unicode(substr(p.url, -1, 1)) * 859983745857 + unicode(substr(p.url, -2, 1)) * 620455851591 + unicode(substr(p.url, -3, 1)) * 380927957327 + unicode(substr(p.url, -4, 1)) * 141400063061 + unicode(substr(p.url, -5, 1)) * 1001383796573 + unicode(substr(p.url, -6, 1)) * 761855902307 + unicode(substr(p.url, -7, 1)) * 522328008043 + unicode(substr(p.url, -8, 1)) * 282800113777 + unicode(substr(p.url, -9, 1)) * 43272219513 + unicode(substr(p.url, -10, 1)) * 903255953023 + unicode(substr(p.url, -11, 1)) * 663728058759 + unicode(substr(p.url, -12, 1)) * 424200164493 + unicode(substr(p.url, -13, 1)) * 184672270229 + unicode(substr(p.url, -14, 1)) * 1044656003739 + unicode(substr(p.url, -15, 1)) * 805128109475 + unicode(substr(p.url, -16, 1)) * 565600215209),
       CASE WHEN p.i % 11 = 0 THEN 'Description of item ' || p.i END, NULL, CASE WHEN p.i <= 1000 THEN p.host END,
       p.hi + 1, CASE WHEN (p.h / 65537) % 20 = 0 THEN 1 ELSE 0 END, NULL, 0
FROM p JOIN _rev r ON r.hi = p.hi;

-- visits: places skewed towards host roots; ~6% are redirect targets (types 5/6) of the previous visit
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 150000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO moz_historyvisits(id, from_visit, place_id, visit_date, visit_type, session, source, triggeringPlaceId, userContextId)
SELECT i,
       CASE WHEN (h / 77) % 16 = 0 AND i > 1 THEN i - 1 ELSE 0 END,
       1 + (((h / 3) % 40000) * ((h / 3) % 40000)) / (40000 * 40000 / (40000 * (SELECT scale FROM _cfg))),
       1792022400000000 - 120 * 86400000000 + i * (120 * 86400000000 / (150000 * (SELECT scale FROM _cfg))) + (h % 30000000),
       CASE WHEN (h / 77) % 16 = 0 AND i > 1 THEN 5 + (h / 5) % 2
            ELSE CASE (h / 5) % 20 WHEN 0 THEN 2 WHEN 1 THEN 2 WHEN 2 THEN 2 WHEN 3 THEN 3 WHEN 4 THEN 9 WHEN 5 THEN 8 WHEN 6 THEN 7 ELSE 1 END END,
       0, CASE WHEN (h / 1031) % 25 = 0 THEN 1 ELSE 0 END, NULL, CASE WHEN (h / 9) % 10 = 0 THEN 2 ELSE 0 END
FROM m;

UPDATE moz_places SET
  visit_count = (SELECT count(*) FROM moz_historyvisits v WHERE v.place_id = moz_places.id AND v.visit_type NOT IN (0, 4, 7, 8, 9)),
  last_visit_date = (SELECT max(visit_date) FROM moz_historyvisits v WHERE v.place_id = moz_places.id),
  typed = EXISTS (SELECT 1 FROM moz_historyvisits v WHERE v.place_id = moz_places.id AND v.visit_type = 2);
UPDATE moz_places SET frecency = 0 WHERE last_visit_date IS NULL AND frecency > 0 AND id % 3 = 0;

-- bookmarks: roots (ids 1-6 as created by Database.cpp), a folder tree under menu/toolbar/unfiled, tags
INSERT INTO moz_bookmarks(id, type, fk, parent, position, title, keyword_id, folder_type, dateAdded, lastModified, guid, syncStatus, syncChangeCounter) VALUES
  (1, 2, NULL, 0, 0, '', NULL, NULL, 1700000000000000, 1792000000000000, 'root________', 1, 1),
  (2, 2, NULL, 1, 0, 'menu', NULL, NULL, 1700000000000000, 1792000000000000, 'menu________', 1, 1),
  (3, 2, NULL, 1, 1, 'toolbar', NULL, NULL, 1700000000000000, 1792000000000000, 'toolbar_____', 1, 1),
  (4, 2, NULL, 1, 2, 'tags', NULL, NULL, 1700000000000000, 1792000000000000, 'tags________', 1, 1),
  (5, 2, NULL, 1, 3, 'unfiled', NULL, NULL, 1700000000000000, 1792000000000000, 'unfiled_____', 1, 1),
  (6, 2, NULL, 1, 4, 'mobile', NULL, NULL, 1700000000000000, 1792000000000000, 'mobile______', 1, 1);

-- 120 folders (ids 7..126): 1-12 hang off menu/toolbar/unfiled, the rest nest under earlier folders
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 120)
INSERT INTO moz_bookmarks(id, type, fk, parent, position, title, dateAdded, lastModified, guid, syncStatus, syncChangeCounter)
SELECT 6 + i, 2, NULL, CASE WHEN i <= 12 THEN 2 + (i % 3) * (CASE WHEN i % 3 = 2 THEN 1 ELSE 1 END) + (CASE WHEN i % 3 = 2 THEN 1 ELSE 0 END) ELSE 6 + (i / 3) END,
       0, 'Folder ' || i, 1700000000000000 + i * 1000000000, 1700000000000000 + i * 1000000000,
       printf('fold%08d', i), 2, 0
FROM n;

-- 3000 bookmarks of places, spread over the roots and folders
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 3000*(SELECT scale FROM _cfg))
INSERT INTO moz_bookmarks(id, type, fk, parent, position, title, dateAdded, lastModified, guid, syncStatus, syncChangeCounter)
SELECT 1000 + i, 1, 1 + ((i * 2654435761) % 4294967296) % (CASE WHEN i % 4 = 0 THEN 1000 ELSE 40000 * (SELECT scale FROM _cfg) END),
       CASE WHEN i % 10 = 0 THEN 3 WHEN i % 10 = 1 THEN 5 WHEN i % 10 = 2 THEN 2 ELSE 7 + (i * 7) % 120 END,
       0, CASE WHEN i % 13 = 0 THEN NULL ELSE 'Bookmark ' || i END,
       1720000000000000 + i * 20000000000, 1720000000000000 + i * 20000000000 + (i % 7) * 1000000000,
       printf('bkmk%08d', i), CASE WHEN i % 5 = 0 THEN 1 ELSE 2 END, i % 3 = 0
FROM n;
-- a few separators
INSERT INTO moz_bookmarks(id, type, fk, parent, position, title, dateAdded, lastModified, guid, syncStatus, syncChangeCounter)
SELECT 900 + i, 3, NULL, 6 + i, 0, NULL, 1710000000000000, 1710000000000000, printf('sepa%08d', i), 2, 0
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40) SELECT i FROM n);

-- 40 tag folders under tags________, ~2000 tag entries pointing at bookmarked places
INSERT INTO moz_bookmarks(id, type, fk, parent, position, title, dateAdded, lastModified, guid, syncStatus, syncChangeCounter)
SELECT 200 + k, 2, NULL, 4, k, CASE k % 8 WHEN 0 THEN 'Work' WHEN 1 THEN 'read-later' WHEN 2 THEN 'sqlite' WHEN 3 THEN 'Rust'
       WHEN 4 THEN 'recipes' WHEN 5 THEN 'travel' WHEN 6 THEN 'docs' ELSE 'music' END || CASE WHEN k >= 8 THEN '-' || k ELSE '' END,
       1715000000000000, 1715000000000000, printf('tagf%08d', k), 2, 0
FROM (WITH RECURSIVE n(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM n WHERE k < 39) SELECT k FROM n);
INSERT INTO moz_bookmarks(id, type, fk, parent, position, title, dateAdded, lastModified, guid, syncStatus, syncChangeCounter)
SELECT 20000 + b.id * 2 + t.j, 1, b.fk, 200 + ((b.id * 7 + t.j * 3) % (CASE WHEN t.j = 0 THEN 8 ELSE 40 END)), 0, NULL,
       b.dateAdded, b.dateAdded, printf('tagi%08d', b.id * 2 + t.j), 2, 0
FROM moz_bookmarks b, (SELECT 0 AS j UNION ALL SELECT 1) t
WHERE b.type = 1 AND b.parent NOT BETWEEN 200 AND 240 AND b.id < 20000 AND (b.id % 3 = 0 OR (t.j = 0 AND b.id % 3 = 1));

-- positions are dense per parent
UPDATE moz_bookmarks SET position = (SELECT count(*) FROM moz_bookmarks s WHERE s.parent = moz_bookmarks.parent AND s.id < moz_bookmarks.id)
WHERE id > 6;

INSERT INTO moz_keywords(keyword, place_id, post_data)
SELECT 'kw' || id, id, CASE WHEN id % 4 = 0 THEN 'q=%s' END FROM moz_places WHERE id BETWEEN 1 AND 30;

UPDATE moz_places SET foreign_count = (SELECT count(*) FROM moz_bookmarks WHERE fk = moz_places.id)
                                    + (SELECT count(*) FROM moz_keywords WHERE place_id = moz_places.id)
WHERE id IN (SELECT fk FROM moz_bookmarks WHERE fk NOT NULL UNION SELECT place_id FROM moz_keywords);
-- some bookmarked pages were never visited
UPDATE moz_places SET frecency = 1 WHERE frecency <= 0 AND foreign_count > 0;

-- origin frecency = sum of page frecencies (what the recalculator converges to for typed origins)
UPDATE moz_origins SET frecency = coalesce((SELECT sum(max(frecency, 0)) FROM moz_places WHERE origin_id = moz_origins.id), 0);
INSERT INTO moz_meta(key, value) VALUES ('origin_frecency_threshold', 2000), ('origin_alt_frecency_threshold', 2.0),
  ('page_frecency_threshold', 100), ('sync/bookmarks/lastSync', 1791900000);

-- adaptive history: inputs are prefixes of the host the user typed, use_count decayed floats
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 5000*(SELECT scale FROM _cfg))
INSERT OR IGNORE INTO moz_inputhistory(place_id, input, use_count)
SELECT pl.id, lower(substr(replace(o.host, 'www.', ''), 1, 1 + n.i % 5)), round(((n.i * 40503) % 1000) / 100.0, 2)
FROM n JOIN moz_places pl ON pl.id = 1 + ((n.i * 2654435761) % 4294967296) % 3000
JOIN moz_origins o ON o.id = pl.origin_id;

-- open tabs: mostly known places, some pages not in history (private-ish or never-stored URLs)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300)
INSERT OR IGNORE INTO moz_openpages_temp(url, userContextId, groupId, open_count)
SELECT CASE WHEN i % 6 = 0 THEN 'https://intranet.example.test/tab/' || i
            ELSE (SELECT url FROM moz_places WHERE id = 1 + (i * 2654435761) % 6000) END,
       CASE WHEN i % 9 = 0 THEN 2 ELSE 0 END, CASE WHEN i % 7 = 0 THEN 'group-' || (i % 3) ELSE '' END, 1 + i % 3
FROM n;

-- favicons: one page row per root + 2000 pages, icons per host plus root /favicon.ico icons, a few orphans
INSERT INTO moz_icons(id, icon_url, fixed_icon_url_hash, width, root, color, expire_ms, flags, data)
SELECT hi + 1, prefix || host || '/favicon.ico', (length((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico')) * 4503599627370496 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -1, 1)) * 859983745857 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -2, 1)) * 620455851591 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -3, 1)) * 380927957327 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -4, 1)) * 141400063061 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -5, 1)) * 1001383796573 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -6, 1)) * 761855902307 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -7, 1)) * 522328008043 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -8, 1)) * 282800113777 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -9, 1)) * 43272219513 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -10, 1)) * 903255953023 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -11, 1)) * 663728058759 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -12, 1)) * 424200164493 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -13, 1)) * 184672270229 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -14, 1)) * 1044656003739 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -15, 1)) * 805128109475 + unicode(substr((CASE WHEN substr(host,1,4)='www.' THEN substr(host,5) ELSE host END || '/favicon.ico'), -16, 1)) * 565600215209),
       32, 1, NULL, 1792022400000 - (hi % 400) * 86400000, 0, x'89504e47' FROM _host;
INSERT INTO moz_icons(id, icon_url, fixed_icon_url_hash, width, root, color, expire_ms, flags, data)
SELECT 2000 + hi, prefix || host || '/static/icon-' || hi || '.png', (length((host || '/static/icon-' || hi || '.png')) * 4503599627370496 + unicode(substr((host || '/static/icon-' || hi || '.png'), -1, 1)) * 859983745857 + unicode(substr((host || '/static/icon-' || hi || '.png'), -2, 1)) * 620455851591 + unicode(substr((host || '/static/icon-' || hi || '.png'), -3, 1)) * 380927957327 + unicode(substr((host || '/static/icon-' || hi || '.png'), -4, 1)) * 141400063061 + unicode(substr((host || '/static/icon-' || hi || '.png'), -5, 1)) * 1001383796573 + unicode(substr((host || '/static/icon-' || hi || '.png'), -6, 1)) * 761855902307 + unicode(substr((host || '/static/icon-' || hi || '.png'), -7, 1)) * 522328008043 + unicode(substr((host || '/static/icon-' || hi || '.png'), -8, 1)) * 282800113777 + unicode(substr((host || '/static/icon-' || hi || '.png'), -9, 1)) * 43272219513 + unicode(substr((host || '/static/icon-' || hi || '.png'), -10, 1)) * 903255953023 + unicode(substr((host || '/static/icon-' || hi || '.png'), -11, 1)) * 663728058759 + unicode(substr((host || '/static/icon-' || hi || '.png'), -12, 1)) * 424200164493 + unicode(substr((host || '/static/icon-' || hi || '.png'), -13, 1)) * 184672270229 + unicode(substr((host || '/static/icon-' || hi || '.png'), -14, 1)) * 1044656003739 + unicode(substr((host || '/static/icon-' || hi || '.png'), -15, 1)) * 805128109475 + unicode(substr((host || '/static/icon-' || hi || '.png'), -16, 1)) * 565600215209),
       CASE WHEN hi % 2 = 0 THEN 64 ELSE 16 END, 0, NULL, 1792022400000 - (hi % 300) * 86400000, hi % 2, x'89504e47' FROM _host;
INSERT INTO moz_pages_w_icons(id, page_url, page_url_hash)
SELECT id, url, url_hash FROM moz_places WHERE id <= 3000;
INSERT INTO moz_pages_w_icons(id, page_url, page_url_hash)
SELECT 100000 + i, 'https://gone.example.test/' || i, (length(('https://gone.example.test/' || i)) * 4503599627370496 + unicode(substr(('https://gone.example.test/' || i), -1, 1)) * 859983745857 + unicode(substr(('https://gone.example.test/' || i), -2, 1)) * 620455851591 + unicode(substr(('https://gone.example.test/' || i), -3, 1)) * 380927957327 + unicode(substr(('https://gone.example.test/' || i), -4, 1)) * 141400063061 + unicode(substr(('https://gone.example.test/' || i), -5, 1)) * 1001383796573 + unicode(substr(('https://gone.example.test/' || i), -6, 1)) * 761855902307 + unicode(substr(('https://gone.example.test/' || i), -7, 1)) * 522328008043 + unicode(substr(('https://gone.example.test/' || i), -8, 1)) * 282800113777 + unicode(substr(('https://gone.example.test/' || i), -9, 1)) * 43272219513 + unicode(substr(('https://gone.example.test/' || i), -10, 1)) * 903255953023 + unicode(substr(('https://gone.example.test/' || i), -11, 1)) * 663728058759 + unicode(substr(('https://gone.example.test/' || i), -12, 1)) * 424200164493 + unicode(substr(('https://gone.example.test/' || i), -13, 1)) * 184672270229 + unicode(substr(('https://gone.example.test/' || i), -14, 1)) * 1044656003739 + unicode(substr(('https://gone.example.test/' || i), -15, 1)) * 805128109475 + unicode(substr(('https://gone.example.test/' || i), -16, 1)) * 565600215209)
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 50) SELECT i FROM n);
INSERT INTO moz_icons_to_pages(page_id, icon_id, expire_ms)
SELECT pw.id, CASE WHEN j.j = 0 THEN p.origin_id ELSE 1999 + p.origin_id END, 1792022400000 - (pw.id % 400) * 86400000
FROM moz_pages_w_icons pw JOIN moz_places p ON p.id = pw.id, (SELECT 0 AS j UNION ALL SELECT 1) j
WHERE j.j = 0 OR (pw.id % 3 = 0 AND (p.origin_id % 5) <> 0);

INSERT INTO moz_anno_attributes(id, name) VALUES (1, 'URIProperties/characterSet'), (2, 'Places/SmartBookmark'), (3, 'downloads/destinationFileURI');
INSERT INTO moz_annos(place_id, anno_attribute_id, content, flags, expiration, type, dateAdded, lastModified)
SELECT id, 1, CASE WHEN id % 2 = 0 THEN 'UTF-8' ELSE 'windows-1252' END, 0, 4, 3, 1750000000000000, 1750000000000000 FROM moz_places WHERE id % 37 = 0
UNION ALL
SELECT 900000 + id, 3, 'file:///home/user/Downloads/file' || id || '.zip', 0, 4, 3, 1750000000000000, 1750000000000000 FROM moz_places WHERE id % 101 = 0;

COMMIT;

