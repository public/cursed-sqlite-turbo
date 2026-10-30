-- Synthetic data for uptime-kuma. Deterministic (no random()): values come from multiplicative hashes of row numbers.
-- Scale 1: 100 monitors (10 of them group monitors acting as parents), 150k heartbeats (1500 per monitor at a 60 s
-- interval, ~2 % important status flips), 24 h of stat_minutely, 30 days of stat_hourly, 365 days of stat_daily,
-- 15 tags, 5 notifications, 5 status pages with groups, incidents and maintenance links.
-- Clock: heartbeats end at 2025-11-02 01:00 UTC; stat buckets are unix seconds.
BEGIN;

CREATE TEMP TABLE kp(nmon, nbeat, t0);
INSERT INTO kp SELECT 100 * scale, 1500, 1761955200 FROM _cfg;

INSERT INTO user(id, username, password, active, timezone) VALUES (1, 'admin', '$2a$10$hash', 1, 'Europe/London');

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT nmon FROM kp))
INSERT INTO monitor(id, name, active, user_id, interval, url, type, weight, hostname, port, created_date, keyword, maxretries,
                    retry_interval, push_token, method, parent, description, accepted_statuscodes_json, conditions, config)
SELECT i,
       CASE WHEN i <= 10 THEN 'Group ' || i
            ELSE (SELECT v FROM (SELECT column1 AS k, column2 AS v FROM (VALUES (0,'API'),(1,'Website'),(2,'Database'),(3,'DNS'),(4,'Mail'),(5,'CDN'),(6,'Auth'))) WHERE k = i % 7) || ' ' || i END,
       CASE WHEN i % 23 = 0 THEN 0 ELSE 1 END, 1,
       CASE WHEN i % 5 = 0 THEN 300 ELSE 60 END,
       CASE WHEN i > 10 AND i % 4 <> 3 THEN 'https://service' || i || '.example.org/health' END,
       CASE WHEN i <= 10 THEN 'group' WHEN i % 4 = 3 THEN 'ping' WHEN i % 9 = 0 THEN 'push' WHEN i % 6 = 0 THEN 'keyword' ELSE 'http' END,
       2000 - (i % 3) * 500,
       CASE WHEN i % 4 = 3 THEN 'host' || i || '.example.org' END,
       CASE WHEN i % 4 = 3 THEN NULL ELSE 443 END,
       datetime((SELECT t0 FROM kp) - 86400 * (400 - i), 'unixepoch'),
       CASE WHEN i % 6 = 0 THEN 'OK' END, i % 4, 60,
       CASE WHEN i % 9 = 0 THEN printf('pt%030d', i) END, 'GET',
       CASE WHEN i > 10 AND i % 3 <> 0 THEN (i % 10) + 1 END,
       CASE WHEN i % 8 = 0 THEN 'Production endpoint ' || i END,
       '["200-299"]', '[]', '{}'
FROM n;

INSERT INTO tag(id, name, color, created_date)
SELECT column1, column2, column3, '2025-01-01 00:00:00' FROM (VALUES
 (1,'prod','#059669'),(2,'staging','#2563EB'),(3,'eu-west','#7C3AED'),(4,'us-east','#DB2777'),(5,'critical','#DC2626'),
 (6,'internal','#4B5563'),(7,'customer','#D97706'),(8,'db','#0891B2'),(9,'edge','#65A30D'),(10,'k8s','#9333EA'),
 (11,'legacy','#78716C'),(12,'payments','#E11D48'),(13,'search','#0EA5E9'),(14,'batch','#A16207'),(15,'team-a','#16A34A'));
INSERT INTO monitor_tag(monitor_id, tag_id, value)
SELECT m.id, ((m.id * 7 + k.k * 5) % 15) + 1, CASE WHEN k.k = 1 THEN 'v' || (m.id % 4) ELSE '' END
FROM monitor m, (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2) k WHERE k.k < 2 OR m.id % 3 = 0;

INSERT INTO notification(id, name, active, user_id, is_default, config)
SELECT column1, column2, 1, 1, column1 = 1, json_object('name', column2, 'type', column3, 'isDefault', column1 = 1)
FROM (VALUES (1,'Ops email','smtp'),(2,'Slack #alerts','slack'),(3,'PagerDuty','PagerDuty'),(4,'Discord','discord'),(5,'Telegram','telegram'));
INSERT INTO monitor_notification(monitor_id, notification_id)
SELECT m.id, k.k FROM monitor m, (SELECT 1 AS k UNION ALL SELECT 2 UNION ALL SELECT 3) k WHERE k.k = 1 OR (m.id + k.k) % 3 = 0;

-- heartbeats: one per monitor per minute, newest at t0 + 25 h; outages flip status in streaks
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT nbeat FROM kp) - 1),
b AS (SELECT m.id AS mid, n.i, ((m.id * 2654435761 + n.i * 40503) % 4294967296) AS h,
             -- an outage window per monitor, ~1-3 % of the time
             CASE WHEN (n.i + m.id * 37) % 500 < 2 + m.id % 8 THEN 0 ELSE 1 END AS st,
             CASE WHEN ((n.i - 1) + m.id * 37) % 500 < 2 + m.id % 8 THEN 0 ELSE 1 END AS prev_st
      FROM monitor m CROSS JOIN n)
INSERT INTO heartbeat(important, monitor_id, status, msg, time, ping, duration, down_count, retries, end_time, response)
SELECT CASE WHEN st <> prev_st OR i = 0 THEN 1 ELSE 0 END, mid, st,
       CASE WHEN st = 1 THEN CASE WHEN mid % 4 = 3 THEN '' ELSE '200 - OK' END
            ELSE CASE h % 3 WHEN 0 THEN 'timeout of 48000ms exceeded' WHEN 1 THEN 'Request failed with status code 503' ELSE 'getaddrinfo ENOTFOUND service' || mid || '.example.org' END END,
       strftime('%Y-%m-%d %H:%M:%S', (SELECT t0 FROM kp) + i * 60 + mid % 50, 'unixepoch') || printf('.%03d', h % 1000),
       CASE WHEN st = 1 THEN 20 + (h / 16) % 180 + CASE WHEN (h / 4096) % 50 = 0 THEN 900 ELSE 0 END END,
       60, CASE WHEN st = 0 THEN 1 + (i + mid * 37) % 500 ELSE 0 END, CASE WHEN st = 0 THEN 1 ELSE 0 END,
       NULL, NULL
FROM b ORDER BY i, mid;

-- aggregate tables, in unix seconds; minutely covers 24 h, hourly 30 days, daily 365 days
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 1439)
INSERT INTO stat_minutely(monitor_id, timestamp, ping, up, down, ping_min, ping_max, extras)
SELECT m.id, (SELECT t0 FROM kp) + 3600 + n.i * 60,
       round(40 + ((m.id * 2654435761 + n.i * 7919) % 4294967296) % 160 + 0.25, 2),
       CASE WHEN (n.i + m.id * 37) % 500 < 2 + m.id % 8 THEN 0 ELSE 1 END,
       CASE WHEN (n.i + m.id * 37) % 500 < 2 + m.id % 8 THEN 1 ELSE 0 END,
       20, 200 + (n.i % 7) * 10, NULL
FROM monitor m, n WHERE m.id > 10;
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 719)
INSERT INTO stat_hourly(monitor_id, timestamp, ping, ping_min, ping_max, up, down, extras)
SELECT m.id, (SELECT t0 FROM kp) + 3600 - (719 - n.i) * 3600,
       round(50 + ((m.id * 40503 + n.i * 2654435761) % 4294967296) % 120 + 0.5, 2), 18, 650,
       60 - CASE WHEN (n.i * 13 + m.id) % 97 = 0 THEN 7 ELSE 0 END, CASE WHEN (n.i * 13 + m.id) % 97 = 0 THEN 7 ELSE 0 END,
       CASE WHEN m.id % 9 = 0 THEN json_object('push', 1) END
FROM monitor m, n WHERE m.id > 10;
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 364)
INSERT INTO stat_daily(monitor_id, timestamp, ping, up, down, ping_min, ping_max, extras)
SELECT m.id, (SELECT t0 FROM kp) - (364 - n.i) * 86400,
       round(55 + ((m.id * 2654435761 + n.i * 40503) % 4294967296) % 90 + 0.75, 2),
       1440 - ((n.i * 31 + m.id * 7) % 23), (n.i * 31 + m.id * 7) % 23, 15, 1200, NULL
FROM monitor m, n WHERE m.id > 10;

-- status pages, public groups, monitor membership, incidents
INSERT INTO status_page(id, slug, title, description, icon, theme, published, search_engine_index, show_tags, footer_text,
                        show_powered_by, show_certificate_expiry, auto_refresh_interval, show_only_last_heartbeat,
                        created_date, modified_date)
SELECT column1, column2, column3, 'Status of ' || column3, '/icon.svg', 'auto', 1, 1, column1 % 2, 'Powered by us', 1, 0, 300, 0,
       '2026-01-0' || column1 || ' 10:00:00', '2026-10-0' || column1 || ' 10:00:00'
FROM (VALUES (1,'status','Public status'),(2,'internal','Internal services'),(3,'eu','EU region'),(4,'us','US region'),(5,'payments','Payments'));
INSERT INTO `group`(id, name, created_date, public, active, weight, status_page_id)
SELECT (sp.id - 1) * 3 + k.k + 1, CASE k.k WHEN 0 THEN 'Services' WHEN 1 THEN 'Infrastructure' ELSE 'Third parties' END,
       '2025-01-01 00:00:00', CASE WHEN k.k = 2 AND sp.id = 2 THEN 0 ELSE 1 END, 1, k.k + 1, sp.id
FROM status_page sp, (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2) k;
INSERT INTO monitor_group(monitor_id, group_id, weight, send_url, custom_url)
SELECT m.id, (m.id * 7) % 15 + 1, m.id % 20 + 1, m.id % 5 = 0, CASE WHEN m.id % 10 = 0 THEN 'https://status.example.org/m' || m.id END
FROM monitor m WHERE m.id > 10
UNION ALL
SELECT m.id, (m.id * 11) % 15 + 1, m.id % 20 + 1, 0, NULL FROM monitor m WHERE m.id > 10 AND m.id % 4 = 0 AND (m.id * 11) % 15 <> (m.id * 7) % 15;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 120)
INSERT INTO incident(title, content, style, created_date, last_updated_date, pin, active, status_page_id)
SELECT 'Incident ' || i, 'We are investigating elevated error rates (#' || i || ').',
       CASE i % 4 WHEN 0 THEN 'danger' WHEN 1 THEN 'warning' WHEN 2 THEN 'info' ELSE 'primary' END,
       strftime('%Y-%m-%d %H:%M:%S', 1730000000 + i * 250000, 'unixepoch'), NULL,
       CASE WHEN i > 110 THEN 1 ELSE 0 END, CASE WHEN i > 100 THEN 1 ELSE 0 END, (i % 5) + 1
FROM n;

INSERT INTO maintenance(id, title, description, user_id, active, strategy, start_date, end_date, start_time, end_time, weekdays, days_of_month, interval_day)
VALUES (1, 'DB upgrade', 'Monthly patching', 1, 1, 'recurring-weekday', '2025-01-01 00:00:00', NULL, '02:00', '03:00', '[0]', '[]', 1),
       (2, 'Network work', 'Carrier maintenance', 1, 1, 'single', '2025-11-05 22:00:00', '2025-11-06 02:00:00', NULL, NULL, '[]', '[]', 1);
INSERT INTO monitor_maintenance(monitor_id, maintenance_id) SELECT id, 1 + id % 2 FROM monitor WHERE id % 6 = 0;
COMMIT;
