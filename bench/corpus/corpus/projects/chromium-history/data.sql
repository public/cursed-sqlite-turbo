-- Synthetic browsing history for chromium-history. Deterministic (no random()): values come from multiplicative
-- hashes of the row number, different bits per column. Times are Chromium internal values (microseconds since
-- 1601-01-01); the history spans 90 days from T0 = 13400000000000000 to "now" = 13407776000000000.
-- Scale 1: 800 hosts, 30k urls, 150k visits (with context annotations, sources, redirects, synced visits),
-- ~2.5k keyword search terms, 2k segments with daily usage rows, ~3.7k clusters, 3k omnibox shortcuts, 20 top sites.
BEGIN;

CREATE TEMP TABLE _host AS
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 799)
SELECT i AS hi,
       CASE i WHEN 0 THEN 'www.google.com' WHEN 1 THEN 'www.youtube.com' WHEN 2 THEN 'github.com'
              WHEN 3 THEN 'en.wikipedia.org' WHEN 4 THEN 'mail.google.com' WHEN 5 THEN 'www.google.co.uk'
              WHEN 6 THEN 'news.ycombinator.com' WHEN 7 THEN 'm.facebook.com' WHEN 8 THEN 'www.reddit.com'
              ELSE CASE i % 3 WHEN 0 THEN 'www.site' || i || '.com' WHEN 1 THEN 'blog' || i || '.example.org' ELSE 'shop' || i || '.example.net' END END AS host,
       CASE WHEN i % 23 = 11 THEN 'http' ELSE 'https' END AS scheme
FROM n;

CREATE TEMP TABLE _w(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO _w VALUES (0,'weather'),(1,'rust'),(2,'sqlite'),(3,'recipes'),(4,'Python'),(5,'flights'),(6,'news'),(7,'jit'),
  (8,'chromium'),(9,'Berlin'),(10,'hotels'),(11,'review'),(12,'tutorial'),(13,'linux'),(14,'football'),(15,'stock'),
  (16,'translate'),(17,'maps'),(18,'pizza'),(19,'cinema'),(20,'iphone'),(21,'kotlin'),(22,'error'),(23,'docker'),
  (24,'Weather'),(25,'calendar'),(26,'tax'),(27,'train'),(28,'music'),(29,'game');

-- urls 1..800 are host roots; the rest are pages, search result pages on the Google hosts
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 30000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO urls(id, url, title, visit_count, typed_count, last_visit_time, hidden)
SELECT m.i,
       CASE WHEN m.i <= 800 THEN hs.scheme || '://' || hs.host || '/'
            WHEN hs.hi IN (0, 5) THEN hs.scheme || '://' || hs.host || '/search?q=' ||
                 (SELECT w FROM _w WHERE k = (m.h / 64) % 30) || '+' || (SELECT w FROM _w WHERE k = (m.h / 4096) % 30) || '&sourceid=chrome&ie=UTF-8&n=' || m.i
            ELSE hs.scheme || '://' || hs.host || '/a/' || ((m.h / 13) % 500) || '/page-' || m.i || CASE WHEN (m.h / 31) % 7 = 0 THEN '?ref=feed' ELSE '' END END,
       CASE WHEN hs.hi IN (0, 5) AND m.i > 800 THEN (SELECT w FROM _w WHERE k = (m.h / 64) % 30) || ' ' || (SELECT w FROM _w WHERE k = (m.h / 4096) % 30) || ' - Google Search'
            ELSE 'Page ' || m.i || ' on ' || hs.host END,
       0,
       CASE WHEN m.i <= 800 AND m.i % 3 = 0 THEN 1 + (m.h / 7) % 40 WHEN (m.h / 11) % 10 = 0 THEN 1 + (m.h / 3) % 5 ELSE 0 END,
       0,
       CASE WHEN (m.h / 997) % 33 = 0 THEN 1 ELSE 0 END
FROM m JOIN _host hs ON hs.hi = CASE WHEN m.i <= 800 THEN m.i - 1 ELSE ((((m.h / 7) % 1000) * ((m.h / 7) % 1000)) / 1000) % 800 END;

-- visits: url ids skewed towards roots and early pages; ~10% are server redirects off the previous visit
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 150000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n),
v AS (SELECT i, h,
             1 + (((h / 3) % 30000) * ((h / 3) % 30000)) / (30000 * 30000 / (30000*(SELECT scale FROM _cfg))) AS url,
             CASE WHEN (h / 77) % 10 = 0 AND i > 1 THEN 1 ELSE 0 END AS redir,
             CASE (h / 5) % 20 WHEN 10 THEN 1 WHEN 11 THEN 1 WHEN 12 THEN 1 WHEN 13 THEN 1 WHEN 14 THEN 2 WHEN 15 THEN 3 WHEN 16 THEN 3
                               WHEN 17 THEN 4 WHEN 18 THEN 8 WHEN 19 THEN 5 ELSE 0 END AS core,
             (h / 1031) % 5 = 0 AS foreign_v
      FROM m)
INSERT INTO visits(id, url, visit_time, from_visit, external_referrer_url, transition, segment_id, visit_duration,
                   incremented_omnibox_typed_score, opener_visit, originator_cache_guid, originator_visit_id,
                   originator_from_visit, originator_opener_visit, is_known_to_sync, consider_for_ntp_most_visited,
                   visited_link_id, app_id)
SELECT i, url, 13400000000000000 + i * 51840000 / (SELECT scale FROM _cfg) + (h % 40000000),
       CASE WHEN redir THEN i - 1 ELSE 0 END, '',
       core | CASE WHEN redir THEN 1610612736 ELSE 805306368 END,
       CASE WHEN url <= 2000 AND core IN (0, 1, 2) THEN url ELSE 0 END,
       (h / 17) % 600000000, CASE WHEN core = 1 THEN 1 ELSE 0 END, 0,
       CASE WHEN foreign_v THEN CASE (h / 7) % 2 WHEN 0 THEN 'aWlHeY3Lm9xq8Kt1Zp0aRg==' ELSE 'Qm9vZ3VzQ2FjaGVHdWlkMg==' END ELSE '' END,
       CASE WHEN foreign_v THEN 5000000 + i ELSE 0 END,
       CASE WHEN foreign_v AND redir THEN 5000000 + i - 1 ELSE 0 END, 0,
       (h / 9) % 2, CASE WHEN core IN (0, 1, 2) AND NOT redir THEN 1 ELSE 0 END, 0,
       CASE WHEN (h / 8191) % 40 = 0 THEN CASE (h / 3) % 3 WHEN 0 THEN 'com.google.android.youtube' WHEN 1 THEN 'com.twitter.android' ELSE 'org.telegram.messenger' END END
FROM v;

UPDATE urls SET visit_count = (SELECT count(*) FROM visits WHERE visits.url = urls.id),
                last_visit_time = coalesce((SELECT max(visit_time) FROM visits WHERE visits.url = urls.id), 13399000000000000 - id * 1000000);

INSERT INTO visit_source(id, source)
SELECT id, CASE WHEN originator_cache_guid != '' THEN 0 WHEN (id * 2654435761 / 313) % 30 = 0 THEN 6 ELSE 2 END
FROM visits WHERE originator_cache_guid != '' OR (id * 2654435761 / 313) % 30 IN (0, 1);

INSERT INTO context_annotations(visit_id, context_annotation_flags, duration_since_last_visit, page_end_reason, total_foreground_duration,
                                browser_type, window_id, tab_id, task_id, root_task_id, parent_task_id, response_code)
SELECT id, (id * 40503) % 64, (id * 7919) % 86400000000, (id % 9), visit_duration, 1, 1 + id % 4, 100 + id % 50, id, id - id % 7, -1,
       CASE WHEN ((id * 2654435761) / 4099) % 50 = 0 THEN 404 ELSE 200 END
FROM visits WHERE id % 10 != 3;

INSERT INTO keyword_search_terms(keyword_id, url_id, term, normalized_term)
SELECT 2, id, replace(substr(url, instr(url, 'q=') + 2, instr(url, '&') - instr(url, 'q=') - 2), '+', ' '),
       lower(replace(substr(url, instr(url, 'q=') + 2, instr(url, '&') - instr(url, 'q=') - 2), '+', ' '))
FROM urls WHERE url LIKE '%/search?q=%';

-- most-visited segments: one per URL among the first 2000 (segment id = url id)
INSERT INTO segments(id, name, url_id)
SELECT id, replace(replace(replace(substr(url, 1, CASE WHEN instr(url, '?') > 0 THEN instr(url, '?') - 1 ELSE length(url) END), 'https://', 'http://'), '://www.', '://'), '://m.', '://'), id
FROM urls WHERE id <= 2000;

INSERT INTO segment_usage(segment_id, time_slot, visit_count)
SELECT segment_id, (visit_time / 86400000000) * 86400000000, count(*)
FROM visits WHERE segment_id > 0 GROUP BY 1, 2;

-- journeys: consecutive visits grouped into clusters of ~8
INSERT INTO clusters(cluster_id, should_show_on_prominent_ui_surfaces, label, raw_label, triggerability_calculated, originator_cache_guid, originator_cluster_id)
SELECT DISTINCT 1 + (id / 5) / 8, ((id / 5) / 8) % 6 != 0,
       '"' || (SELECT w FROM _w WHERE k = (((id / 5) / 8) * 7) % 30) || '"', (SELECT w FROM _w WHERE k = (((id / 5) / 8) * 7) % 30), 1, '', 0
FROM visits WHERE id % 5 = 0 AND (id / 5) / 8 % 13 != 7;
-- a few clusters whose visits have been deleted
INSERT INTO clusters(should_show_on_prominent_ui_surfaces, label, raw_label, triggerability_calculated, originator_cache_guid, originator_cluster_id)
SELECT 1, 'orphan', 'orphan', 0, 'Qm9vZ3VzQ2FjaGVHdWlkMg==', id FROM visits WHERE id <= 40;

INSERT INTO clusters_and_visits(cluster_id, visit_id, score, engagement_score, url_for_deduping, normalized_url, url_for_display, interaction_state)
SELECT 1 + (v.id / 5) / 8, v.id, ((v.id * 2654435761) % 1000) / 1000.0, ((v.id * 40503) % 100) / 10.0,
       u.url, u.url, substr(u.url, instr(u.url, '://') + 3), CASE WHEN v.id % 97 = 0 THEN 1 ELSE 0 END
FROM visits v JOIN urls u ON u.id = v.url
WHERE v.id % 5 = 0 AND (v.id / 5) / 8 % 13 != 7;

INSERT INTO cluster_keywords(cluster_id, keyword, type, score, collections)
SELECT cluster_id, (SELECT w FROM _w WHERE k = (cluster_id * 3 + j.j) % 30), j.j + 1, 0.5 + j.j / 4.0, '[]'
FROM clusters, (SELECT 0 AS j UNION ALL SELECT 1) j WHERE label != 'orphan';

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 3000*(SELECT scale FROM _cfg))
INSERT INTO omni_box_shortcuts(id, text, fill_into_edit, url, document_type, contents, contents_class, description, description_class,
                               transition, type, keyword, last_access_time, number_of_hits)
SELECT printf('%08X-%04X-4%03X-A%03X-%012X', (i * 2654435761) % 4294967296, i % 65536, i % 4096, (i * 7) % 4096, i * 40503),
       substr(u.url, instr(u.url, '://') + 3, 1 + i % 9), u.url, u.url, 0, substr(u.url, instr(u.url, '://') + 3), '0,1', u.title, '0,0',
       CASE WHEN i % 4 = 0 THEN 0 ELSE 1 END, CASE WHEN i % 5 = 0 THEN 5 ELSE 0 END, '',
       13407776000000000 - i * 2000000000, 1 + (i * 7) % 30
FROM n JOIN urls u ON u.id = 1 + (i * 2654435761) % 6000;

INSERT INTO top_sites(url, url_rank, title)
SELECT url, row_number() OVER (ORDER BY visit_count DESC, id) - 1, title FROM urls WHERE hidden = 0 ORDER BY visit_count DESC, id LIMIT 20;

COMMIT;
