-- Synthetic data for GoatCounter: one busy site (site 1) and one small site (site 2). Deterministic (no random()):
-- values come from multiplicative hashes of the row number. "Now" is 2026-10-30 23:59:59 UTC; hits cover the 180
-- days before it. Path, referrer, browser and system popularity are power-law skewed (x^3 of a uniform hash), so a
-- few paths and referrers carry most traffic and a long tail of ~20k paths is hit a handful of times.
-- Scale 1: 20k + 400 paths, 3k refs, 150 browsers, 60 systems, 60 locations, 25 languages, 20 campaigns,
-- 240k hits; hit_counts / ref_counts / *_stats are rolled up from hits exactly as the cron does (first visits
-- only, rows with a zero count skipped). One saved path filter ("blog", ~12k paths) in filters/filter_paths.
-- _cfg.scale multiplies paths, refs and hits.
BEGIN;

CREATE TEMP TABLE _s AS SELECT (SELECT scale FROM _cfg) AS s, 20000 * (SELECT scale FROM _cfg) AS p1,
  3000 * (SELECT scale FROM _cfg) AS nref, 200000 * (SELECT scale FROM _cfg) AS nhit;

-- Seed rows from db/schema.gotxt
INSERT INTO refs (ref, ref_scheme) VALUES ('', 'o');
INSERT INTO locations (country, country_name, region, region_name) VALUES ('', '(unknown)', '', '');
INSERT INTO languages (iso_639_3, name) VALUES ('', '(unknown)');

-- Paths: site 1 ids 1..p1, site 2 the next 400. ~60 % under /blog/, 3 % events.
INSERT INTO paths (path_id, site_id, path, title, event)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT p1 FROM _s) + 400)
SELECT i, CASE WHEN i <= (SELECT p1 FROM _s) THEN 1 ELSE 2 END,
  CASE WHEN i = 1 OR i = (SELECT p1 FROM _s) + 1 THEN '/'
       WHEN h % 100 < 3 THEN 'click-' || (CASE (h / 128) % 4 WHEN 0 THEN 'signup' WHEN 1 THEN 'download' WHEN 2 THEN 'share' ELSE 'outbound' END) || '-' || i
       WHEN h % 100 < 63 THEN '/blog/' || (2015 + (h / 256) % 12) || '/' || printf('%02d', 1 + (h / 4096) % 12) || '/post-' || i
       WHEN h % 100 < 80 THEN '/docs/' || (CASE (h / 64) % 5 WHEN 0 THEN 'api' WHEN 1 THEN 'install' WHEN 2 THEN 'config' WHEN 3 THEN 'faq' ELSE 'guide' END) || '/page-' || i
       WHEN h % 100 < 92 THEN '/tag/topic-' || i
       ELSE '/p/' || i || '?ref=feed' END,
  CASE WHEN h % 7 = 0 THEN '' ELSE 'Page ' || i || ' - ' || (CASE (h / 32) % 3 WHEN 0 THEN 'My Blog' WHEN 1 THEN 'Docs' ELSE 'Example' END) END,
  CASE WHEN h % 100 < 3 AND i != 1 AND i != (SELECT p1 FROM _s) + 1 THEN 1 ELSE 0 END
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n);

-- Referrers (ref_id 1 is the empty "direct" ref)
INSERT INTO refs (ref, ref_scheme)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT nref FROM _s))
SELECT CASE
    WHEN i <= 6 THEN (CASE i WHEN 1 THEN 'Google' WHEN 2 THEN 'Hacker News' WHEN 3 THEN 'Reddit' WHEN 4 THEN 'DuckDuckGo' WHEN 5 THEN 'Bing' ELSE 'Lobsters' END)
    WHEN i % 10 = 0 THEN 'news.ycombinator.com/item?id=' || (30000000 + i)
    WHEN i % 10 = 1 THEN 'www.reddit.com/r/programming/comments/' || printf('%x', i * 7919)
    WHEN i % 10 = 2 THEN 'utm-source-' || i
    ELSE 'site' || (i % 700) || '.example.' || (CASE i % 3 WHEN 0 THEN 'com' WHEN 1 THEN 'org' ELSE 'net' END) || '/' || (CASE WHEN i % 4 = 0 THEN 'links?page=' ELSE 'article/' END) || i
  END,
  CASE WHEN i <= 6 THEN 'g' WHEN i % 10 = 2 THEN 'c' ELSE 'h' END
FROM n;

INSERT INTO browsers (name, version)
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 149)
SELECT CASE i % 10 WHEN 0 THEN 'Chrome' WHEN 1 THEN 'Firefox' WHEN 2 THEN 'Safari' WHEN 3 THEN 'Edge' WHEN 4 THEN 'Chrome'
         WHEN 5 THEN 'Safari' WHEN 6 THEN 'Samsung Internet' WHEN 7 THEN 'Opera' WHEN 8 THEN 'Firefox' ELSE 'Yandex' END,
  CAST(140 - i / 10 AS TEXT) || CASE WHEN i % 10 IN (4, 8) THEN '.1' WHEN i % 10 = 5 THEN '.0.1' ELSE '' END
FROM n;
INSERT INTO systems (name, version)
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 59)
SELECT CASE i % 6 WHEN 0 THEN 'Windows' WHEN 1 THEN 'Android' WHEN 2 THEN 'iOS' WHEN 3 THEN 'macOS' WHEN 4 THEN 'Linux' ELSE 'ChromeOS' END,
  CASE i % 6 WHEN 0 THEN '10.0.' || (19045 + i / 6) WHEN 1 THEN CAST(16 - i / 6 AS TEXT) WHEN 2 THEN '18.' || (i / 6)
            WHEN 3 THEN '15.' || (i / 6) WHEN 4 THEN CASE WHEN i < 6 THEN '' ELSE 'Ubuntu ' || (i / 6) END ELSE CAST(130 + i / 6 AS TEXT) END
FROM n;

INSERT INTO locations (country, country_name, region, region_name) VALUES
  ('US','United States','',''),('US','United States','CA','California'),('US','United States','NY','New York'),
  ('US','United States','TX','Texas'),('US','United States','WA','Washington'),('DE','Germany','',''),
  ('DE','Germany','BY','Bayern'),('DE','Germany','BE','Berlin'),('GB','United Kingdom','',''),('GB','United Kingdom','ENG','England'),
  ('FR','France','',''),('FR','France','IDF','Île-de-France'),('NL','Netherlands','',''),('NL','Netherlands','NH','Noord-Holland'),
  ('IN','India','',''),('IN','India','KA','Karnataka'),('BR','Brazil','',''),('BR','Brazil','SP','São Paulo'),
  ('CA','Canada','',''),('CA','Canada','ON','Ontario'),('JP','Japan','',''),('JP','Japan','13','Tokyo'),
  ('AU','Australia','',''),('AU','Australia','NSW','New South Wales'),('SE','Sweden','',''),('PL','Poland','',''),
  ('ES','Spain','',''),('IT','Italy','',''),('CN','China','',''),('RU','Russia','',''),('KR','South Korea','',''),
  ('ID','Indonesia','',''),('MX','Mexico','',''),('CH','Switzerland','',''),('AT','Austria','',''),('BE','Belgium','',''),
  ('NO','Norway','',''),('FI','Finland','',''),('DK','Denmark','',''),('CZ','Czechia','',''),('UA','Ukraine','',''),
  ('TR','Turkey','',''),('VN','Vietnam','',''),('NZ','New Zealand','',''),('IE','Ireland','',''),('PT','Portugal','',''),
  ('AR','Argentina','',''),('ZA','South Africa','',''),('SG','Singapore','',''),('IL','Israel','','');
INSERT INTO languages (iso_639_3, name) VALUES
  ('eng','English'),('deu','German'),('fra','French'),('spa','Spanish'),('por','Portuguese'),('nld','Dutch'),
  ('jpn','Japanese'),('zho','Chinese'),('rus','Russian'),('ita','Italian'),('pol','Polish'),('swe','Swedish'),
  ('kor','Korean'),('hin','Hindi'),('tur','Turkish'),('ukr','Ukrainian'),('ces','Czech'),('fin','Finnish'),
  ('nob','Norwegian Bokmål'),('dan','Danish'),('vie','Vietnamese'),('ind','Indonesian'),('heb','Hebrew'),('ara','Arabic');

INSERT INTO campaigns (site_id, name)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20)
SELECT 1, CASE i % 4 WHEN 0 THEN 'newsletter-' || i WHEN 1 THEN 'launch-' || i WHEN 2 THEN 'spring-sale' || i ELSE 'feed' || i END FROM n;

CREATE TEMP TABLE _loc AS SELECT row_number() OVER (ORDER BY location_id) - 1 AS k, iso_3166_2 AS iso FROM locations WHERE location_id > 1;
CREATE TEMP TABLE _lang AS SELECT row_number() OVER (ORDER BY rowid) - 1 AS k, iso_639_3 AS iso FROM languages WHERE iso_639_3 != '';

-- Hits: 95 % site 1, 5 % site 2; 60 % first visits; ~2 % carry a campaign
INSERT INTO hits (site_id, path_id, ref_id, session, first_visit, browser_id, system_id, campaign, width, location, language, created_at)
SELECT site,
  CASE WHEN site = 1 THEN 1 + CAST((SELECT p1 FROM _s) * x * x * x * x * x AS INTEGER)
       ELSE (SELECT p1 FROM _s) + 1 + CAST(400 * x * x AS INTEGER) END,
  CASE WHEN h % 10 < 6 THEN 1 ELSE 2 + CAST(((SELECT nref FROM _s) - 1) * y * y * y * y AS INTEGER) END,
  unhex(printf('%08x%08x%08x%08x', h, h2, (k * 40503) % 4294967296, k)),
  CASE WHEN (h / 1024) % 10 < 6 THEN 1 ELSE 0 END,
  1 + CAST(149 * z * z * z AS INTEGER),
  1 + CAST(59 * w * w AS INTEGER),
  CASE WHEN (h2 / 1024) % 50 = 0 THEN 1 + (h2 / 65536) % 20 END,
  CASE WHEN (h / 65536) % 33 = 0 THEN NULL ELSE
    (CASE (h / 2048) % 12 WHEN 0 THEN 360 WHEN 1 THEN 375 WHEN 2 THEN 390 WHEN 3 THEN 412 WHEN 4 THEN 768 WHEN 5 THEN 1024
      WHEN 6 THEN 1280 WHEN 7 THEN 1366 WHEN 8 THEN 1440 WHEN 9 THEN 1536 WHEN 10 THEN 1920 ELSE 2560 END) END,
  CASE WHEN (h2 / 128) % 25 = 0 THEN '' ELSE (SELECT iso FROM _loc WHERE _loc.k = CAST(49 * w * z AS INTEGER)) END,
  CASE WHEN (h2 / 4096) % 9 = 0 THEN '' ELSE (SELECT iso FROM _lang WHERE _lang.k = CAST(23 * z * w * w AS INTEGER)) END,
  datetime('2026-05-04 00:00:00', '+' || (k * 15550000 / (SELECT nhit FROM _s) + (h2 % 1800)) || ' seconds')
FROM (
  WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < (SELECT nhit FROM _s))
  SELECT k, (k * 2654435761) % 4294967296 AS h, (k * 2246822519) % 4294967296 AS h2,
    CASE WHEN ((k * 2654435761) % 4294967296) % 100 < 95 THEN 1 ELSE 2 END AS site,
    (((k * 2246822519) % 4294967296) % 100003) / 100003.0 AS x,
    (((k * 3266489917) % 4294967296) % 99991) / 99991.0 AS y,
    (((k * 668265263) % 4294967296) % 9973) / 9973.0 AS z,
    (((k * 374761393) % 4294967296) % 9967) / 9967.0 AS w
  FROM n);

-- Roll-ups, as cron/*.go builds them from hits (first visits only, zero counts skipped)
INSERT INTO hit_counts (site_id, path_id, hour, total)
SELECT site_id, path_id, strftime('%Y-%m-%d %H:00:00', created_at), sum(first_visit)
FROM hits GROUP BY 1, 2, 3 HAVING sum(first_visit) > 0;
INSERT INTO ref_counts (site_id, path_id, ref_id, hour, total)
SELECT site_id, path_id, ref_id, strftime('%Y-%m-%d %H:00:00', created_at), sum(first_visit)
FROM hits GROUP BY 1, 2, 3, 4 HAVING sum(first_visit) > 0;
INSERT INTO browser_stats (site_id, path_id, browser_id, day, count)
SELECT site_id, path_id, browser_id, date(created_at), sum(first_visit) FROM hits GROUP BY 1, 2, 3, 4 HAVING sum(first_visit) > 0;
INSERT INTO system_stats (site_id, path_id, system_id, day, count)
SELECT site_id, path_id, system_id, date(created_at), sum(first_visit) FROM hits GROUP BY 1, 2, 3, 4 HAVING sum(first_visit) > 0;
INSERT INTO location_stats (site_id, path_id, day, location, count)
SELECT site_id, path_id, date(created_at), location, sum(first_visit) FROM hits GROUP BY 1, 2, 3, 4 HAVING sum(first_visit) > 0;
INSERT INTO size_stats (site_id, path_id, day, width, count)
SELECT site_id, path_id, date(created_at), coalesce(width, 0), sum(first_visit) FROM hits GROUP BY 1, 2, 3, 4 HAVING sum(first_visit) > 0;
INSERT INTO language_stats (site_id, path_id, day, language, count)
SELECT site_id, path_id, date(created_at), coalesce(language, ''), sum(first_visit) FROM hits GROUP BY 1, 2, 3, 4 HAVING sum(first_visit) > 0;
INSERT INTO campaign_stats (site_id, path_id, day, campaign_id, ref, count)
SELECT h.site_id, h.path_id, date(h.created_at), h.campaign, r.ref, sum(h.first_visit)
FROM hits h JOIN refs r USING (ref_id) WHERE h.campaign IS NOT NULL GROUP BY 1, 2, 3, 4, 5 HAVING sum(h.first_visit) > 0;

-- A saved filter: the dashboard search "blog" matched more than 10k paths, so PathFilterFromQuery stored the ids
INSERT INTO filters (filter_id, site_id, matches, invert, query, created_at, last_used_at)
VALUES (1, 1, 0, 0, 'blog', '2026-10-01 10:00:00', '2026-10-30 09:00:00');
INSERT INTO filter_paths (filter_id, path_id) SELECT 1, path_id FROM paths WHERE site_id = 1 AND lower(path) LIKE '%blog%' ORDER BY path_id;
UPDATE filters SET matches = (SELECT count(*) FROM filter_paths WHERE filter_id = 1) WHERE filter_id = 1;

DROP TABLE _loc;
DROP TABLE _lang;
COMMIT;
