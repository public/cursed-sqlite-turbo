-- Synthetic data for a busy CrowdSec LAPI on SQLite. Deterministic (no random()): values come from multiplicative
-- hashes of the row number. "Now" is 2026-10-30 12:00:00 UTC (epoch 1793361600). Times are stored the way
-- mattn/go-sqlite3 binds time.Time: 'YYYY-MM-DD HH:MM:SS.ffffff+00:00' text (ent `datetime` columns).
-- IPs use crowdsec's csnet encoding: start_ip/end_ip = -9223372036854775807 + address (IPv4) or + upper 64 bits
-- (IPv6, with start_suffix/end_suffix for the low 64 bits).
--
-- Shape at scale 1 (row counts multiply by _cfg.scale), flush max_age 7d, alerts spanning 8 days:
--   5 machines, 12 bouncers (4 never pulled: last_pull NULL), 50k alerts:
--     ~49.7k local alerts from 5 agents (16 scenarios, skewed: ssh-bf ~30 %, 300 repeat-offender IPs get ~30 % of
--     alerts, 5 % IPv6), one 4h ban each (2 % simulated, 5 % 7-day bans for repeat offenders);
--     84 `cscli decisions import` alerts (a 1500-entry blocklist re-imported every 2 h, 4h duration: ~84 rows per
--     value, the #4613 shape), 84 CAPI community-blocklist pulls (latest carries 6000 decisions, older ones ~40
--     leftovers each), 12-13 `lists:firehol_cruzit_web_attacks` pulls with 800 decisions each.
--   ~196k decisions (~90 % expired), ~100k events (1-3 per local alert), ~85k meta rows, 1 allowlist with 40 items,
--   2k bouncer/agent usage metrics.
BEGIN;

CREATE TEMP TABLE _scen(k INTEGER PRIMARY KEY, name TEXT, kind TEXT, log_type TEXT);
INSERT INTO _scen VALUES
 (0,'crowdsecurity/ssh-bf','crowdsec','ssh_failed-auth'),(1,'crowdsecurity/ssh-bf','crowdsec','ssh_failed-auth'),
 (2,'crowdsecurity/ssh-bf','crowdsec','ssh_failed-auth'),(3,'crowdsecurity/ssh-bf','crowdsec','ssh_failed-auth'),
 (4,'crowdsecurity/ssh-bf','crowdsec','ssh_failed-auth'),(5,'crowdsecurity/ssh-slow-bf','crowdsec','ssh_failed-auth'),
 (6,'crowdsecurity/http-probing','crowdsec','http_access-log'),(7,'crowdsecurity/http-probing','crowdsec','http_access-log'),
 (8,'crowdsecurity/http-probing','crowdsec','http_access-log'),(9,'crowdsecurity/http-crawl-non_statics','crowdsec','http_access-log'),
 (10,'crowdsecurity/http-crawl-non_statics','crowdsec','http_access-log'),(11,'crowdsecurity/http-bad-user-agent','crowdsec','http_access-log'),
 (12,'crowdsecurity/http-sensitive-files','crowdsec','http_access-log'),(13,'crowdsecurity/http-admin-interface-probing','crowdsec','http_access-log'),
 (14,'crowdsecurity/http-wordpress-scan','crowdsec','http_access-log'),(15,'crowdsecurity/vpatch-env-access','waf','appsec-info'),
 (16,'crowdsecurity/vpatch-CVE-2017-9841','waf','appsec-info'),(17,'crowdsecurity/appsec-vpatch','waf','appsec-info'),
 (18,'crowdsecurity/postfix-spam','crowdsec','spam-attempt'),(19,'crowdsecurity/nginx-req-limit-exceeded','crowdsec','http_access-log');

CREATE TEMP TABLE _geo(k INTEGER PRIMARY KEY, cn TEXT, asn TEXT, asname TEXT, lat REAL, lon REAL);
INSERT INTO _geo VALUES
 (0,'CN','4134','Chinanet',39.9,116.4),(1,'CN','4837','CHINA UNICOM China169 Backbone',31.2,121.5),
 (2,'US','14061','DIGITALOCEAN-ASN',40.7,-74.0),(3,'US','16509','AMAZON-02',39.0,-77.5),
 (4,'DE','24940','Hetzner Online GmbH',50.5,12.4),(5,'RU','49505','JSC Selectel',59.9,30.3),
 (6,'NL','14061','DIGITALOCEAN-ASN',52.4,4.9),(7,'FR','16276','OVH SAS',50.7,3.2),
 (8,'BR','28573','Claro NXT Telecomunicacoes Ltda',-23.5,-46.6),(9,'IN','9829','National Internet Backbone',28.6,77.2),
 (10,'VN','45899','VNPT Corp',21.0,105.8),(11,'KR','4766','Korea Telecom',37.6,127.0),
 (12,'US','396982','GOOGLE-CLOUD-PLATFORM',41.3,-95.9),(13,'SG','14061','DIGITALOCEAN-ASN',1.3,103.8),
 (14,'GB','212238','Datacamp Limited',51.5,-0.1),(15,'IR','58224','Iran Telecommunication Company PJS',35.7,51.4);

-- attacker / blocklist address pools: n -> IPv4 number (or an IPv6 /64 for every 20th attacker)
CREATE TEMP TABLE _ip(pool INTEGER, n INTEGER, v6 INTEGER, num INTEGER, sfx INTEGER, value TEXT, rng INTEGER,
                      PRIMARY KEY(pool, n));
-- pool 0: local attackers (40k * scale), pool 1: import blocklist (3000 * scale), pool 2: CAPI (6000 * scale + extra),
-- pool 3: firehol list (1200 * scale)
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 40000*(SELECT scale FROM _cfg) + 20000)
INSERT INTO _ip(pool, n, v6, num, sfx, value, rng)
SELECT p.pool, i,
  CASE WHEN p.pool = 0 AND i % 20 = 0 THEN 1 ELSE 0 END,
  CASE WHEN p.pool = 0 AND i % 20 = 0 THEN (0x2a0104f8 << 32) + ((i * 40503) % 65536 << 16) + (i / 20) % 65536
       WHEN p.pool = 1 AND i % 25 = 0 THEN (16777216 + (i * 2246822519 + 7919 * p.pool) % 3741319167) / 256 * 256
       ELSE 16777216 + (i * 2246822519 + 104729 * p.pool + p.pool * p.pool * 7) % 3741319167 END,
  CASE WHEN p.pool = 0 AND i % 20 = 0 THEN 1 + i % 4000 END,
  NULL,
  CASE WHEN p.pool = 1 AND i % 25 = 0 THEN 1 ELSE 0 END
FROM n JOIN (SELECT 0 AS pool, 40000 AS sz UNION ALL SELECT 1, 1500 UNION ALL SELECT 2, 6000 UNION ALL SELECT 3, 1200) p
  ON i < p.sz * (SELECT scale FROM _cfg) + CASE p.pool WHEN 2 THEN 20000 ELSE 0 END;
UPDATE _ip SET value = CASE
  WHEN v6 = 1 THEN printf('%x:%x:%x:%x::%x', num >> 48, (num >> 32) & 65535, (num >> 16) & 65535, num & 65535, sfx)
  ELSE ((num >> 24) & 255) || '.' || ((num >> 16) & 255) || '.' || ((num >> 8) & 255) || '.' || (num & 255)
       || CASE WHEN rng = 1 THEN '/24' ELSE '' END END;
-- CAPI shares its first 200 entries with the busiest local attackers (same value, Ip scope, ban type)
UPDATE _ip SET num = (SELECT num FROM _ip x WHERE x.pool = 0 AND x.n = _ip.n * 20 + 1),
               value = (SELECT value FROM _ip x WHERE x.pool = 0 AND x.n = _ip.n * 20 + 1)
 WHERE pool = 2 AND n < 200;

INSERT INTO machines(id, created_at, updated_at, last_push, last_heartbeat, machine_id, password, ip_address, scenarios,
                     version, is_validated, auth_type, osname, osfamily, osversion, featureflags, hubstate, datasources, features)
SELECT k, '2025-03-02 10:11:12.123457+00:00', '2026-10-30 11:59:41.20431+00:00', '2026-10-30 11:59:' || (10 + k * 7) || '.5517+00:00',
       '2026-10-30 11:59:' || (20 + k * 6) || '.88213+00:00', m, '$2a$10$' || printf('%040X', k * 2654435761),
       ip, (SELECT group_concat(name, ',') FROM (SELECT DISTINCT name FROM _scen)), 'v1.7.8-debian-pragmatic-amd64-63227459',
       1, CASE WHEN k = 5 THEN 'tls' ELSE 'password' END, 'Ubuntu', 'debian', '24.04', '',
       '{"collections":[{"name":"crowdsecurity/linux","status":"enabled","version":"0.2"},{"name":"crowdsecurity/sshd","status":"enabled","version":"0.6"},{"name":"crowdsecurity/nginx","status":"enabled","version":"0.2"}]}',
       '{"file":' || (2 + k) || ',"journalctl":1}', '[]'
FROM (SELECT 1 AS k, 'localhost' AS m, '127.0.0.1' AS ip UNION ALL SELECT 2, 'web-01', '10.0.1.11' UNION ALL
      SELECT 3, 'web-02', '10.0.1.12' UNION ALL SELECT 4, 'mail-01', '10.0.2.21' UNION ALL SELECT 5, 'edge-waf', '10.0.3.5');

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 12)
INSERT INTO bouncers(id, created_at, updated_at, name, api_key, revoked, ip_address, type, version, last_pull, stream_cursor,
                     auth_type, osname, osfamily, osversion, featureflags, auto_created)
SELECT i, '2025-0' || (1 + i % 9) || '-1' || (i % 10) || ' 08:00:00.5+00:00', '2026-10-30 11:59:50.1+00:00',
       CASE WHEN i <= 6 THEN 'cs-firewall-bouncer-' || i WHEN i <= 9 THEN 'traefik-bouncer-' || i ELSE 'nginx-bouncer-' || i END,
       printf('%016x%016x%016x%016x', i * 2654435761, i * 40503 + 7, i * 2246822519, i * 3266489917),
       0, '10.0.' || (i % 4) || '.' || (100 + i),
       CASE WHEN i <= 6 THEN 'crowdsec-firewall-bouncer' WHEN i <= 9 THEN 'traefik-plugin' ELSE 'crowdsec-nginx-bouncer' END,
       'v0.0.31', CASE WHEN i % 3 = 0 THEN NULL ELSE '2026-10-30 11:59:' || (30 + i) || '.401+00:00' END,
       CASE WHEN i % 3 = 0 THEN 0 ELSE 300000 END, 'api-key', 'Debian GNU/Linux', 'debian', '12', '', 0
FROM n;

-- one row per alert: i is the alert id (ascending with time). t spans the last 8 days.
CREATE TEMP TABLE _a(i INTEGER PRIMARY KEY, h INTEGER, t INTEGER, typ TEXT, seq INTEGER, att INTEGER, sc INTEGER, geo INTEGER,
                     machine INTEGER, sim INTEGER, longban INTEGER);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 50000*(SELECT scale FROM _cfg)),
c AS (SELECT i, (i * 2654435761) % 4294967296 AS h, 50000*(SELECT scale FROM _cfg) AS tot FROM n)
INSERT INTO _a
SELECT i, h, 1793361600 - 8*86400 + (i * 8 * 86400) / tot - (h % 40),
  CASE WHEN (tot - i) % (595*(SELECT scale FROM _cfg)) = 37 THEN 'capi' WHEN (tot - i) % (595*(SELECT scale FROM _cfg)) = 335 THEN 'import'
       WHEN (tot - i) % (4000*(SELECT scale FROM _cfg)) = 1500 THEN 'lists' ELSE 'local' END,
  0,
  CASE WHEN h % 10 < 3 THEN ((h / 16) % 300) * 20 + 1 ELSE (h / 16) % (40000*(SELECT scale FROM _cfg)) END,
  (h / 64) % 20, (h / 2048) % 16,
  CASE WHEN (h / 8192) % 100 < 50 THEN 2 WHEN (h / 8192) % 100 < 75 THEN 3 WHEN (h / 8192) % 100 < 90 THEN 4
       WHEN (h / 8192) % 100 < 97 THEN 5 ELSE 1 END,
  CASE WHEN (h / 1048576) % 50 = 0 THEN 1 ELSE 0 END,
  CASE WHEN h % 10 < 3 AND (h / 4096) % 6 = 0 THEN 1 ELSE 0 END
FROM c;
UPDATE _a SET seq = (SELECT count(*) FROM _a b WHERE b.typ = _a.typ AND b.i <= _a.i) WHERE typ <> 'local';

INSERT INTO alerts(id, created_at, updated_at, scenario, bucket_id, message, events_count, started_at, stopped_at, source_ip,
  source_range, source_as_number, source_as_name, source_country, source_latitude, source_longitude, source_scope,
  source_value, capacity, leak_speed, scenario_version, scenario_hash, simulated, uuid, remediation, kind, machine_alerts)
SELECT a.i, (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'),
  CASE a.typ WHEN 'local' THEN s.name
    WHEN 'import' THEN 'import blocklist-' || strftime('%Y%m%d%H', a.t, 'unixepoch') || '.txt: ' || (1500*(SELECT scale FROM _cfg)) || ' IPs'
    WHEN 'capi' THEN CASE WHEN a.seq = (SELECT max(seq) FROM _a WHERE typ = 'capi') THEN 'update : +' || (6000*(SELECT scale FROM _cfg)) || '/-0 IPs'
                          ELSE 'update : +' || (300 + a.h % 200) || '/-' || (280 + a.h % 150) || ' IPs' END
    ELSE 'update : +' || (800*(SELECT scale FROM _cfg)) || '/-0 IPs' END,
  CASE a.typ WHEN 'local' THEN printf('%s-%s', CASE a.h % 6 WHEN 0 THEN 'quiet' WHEN 1 THEN 'wild' WHEN 2 THEN 'young' WHEN 3 THEN 'cold' WHEN 4 THEN 'dark' ELSE 'small' END,
                                       CASE (a.h / 6) % 6 WHEN 0 THEN 'river' WHEN 1 THEN 'forest' WHEN 2 THEN 'wave' WHEN 3 THEN 'snow' WHEN 4 THEN 'meadow' ELSE 'brook' END) ELSE '' END,
  CASE a.typ WHEN 'local' THEN (CASE WHEN ip.v6 = 1 THEN 'Ip ' ELSE 'Ip ' END) || ip.value || ' performed ''' || s.name || ''' (' || (5 + a.h % 20) || ' events over '
       || (1 + (a.h / 32) % 59) || 's) at ' || strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || ' +0000 UTC' ELSE '' END,
  CASE a.typ WHEN 'local' THEN 5 + a.h % 20 WHEN 'import' THEN 1500*(SELECT scale FROM _cfg) ELSE 0 END,
  (strftime('%Y-%m-%d %H:%M:%S', a.t - 1 - (a.h / 32) % 59, 'unixepoch') || '.' || printf('%06d', ((a.h / 3) % 99999) * 10 + 1 + ((a.h / 3) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'),
  CASE a.typ WHEN 'local' THEN ip.value END,
  CASE WHEN a.typ = 'local' AND ip.v6 = 0 THEN ((ip.num >> 24) & 255) || '.' || ((ip.num >> 16) & 255) || '.0.0/16' END,
  CASE a.typ WHEN 'local' THEN g.asn END, CASE a.typ WHEN 'local' THEN g.asname END, CASE a.typ WHEN 'local' THEN g.cn END,
  CASE a.typ WHEN 'local' THEN g.lat END, CASE a.typ WHEN 'local' THEN g.lon END,
  CASE a.typ WHEN 'local' THEN 'Ip' WHEN 'import' THEN '' WHEN 'capi' THEN 'crowdsecurity/community-blocklist'
       ELSE 'lists:firehol_cruzit_web_attacks' END,
  CASE a.typ WHEN 'local' THEN ip.value ELSE '' END,
  CASE a.typ WHEN 'local' THEN 5 ELSE 0 END, CASE a.typ WHEN 'local' THEN '10s' ELSE '' END,
  CASE a.typ WHEN 'local' THEN '0.' || (1 + a.sc % 4) ELSE '' END,
  CASE a.typ WHEN 'local' THEN printf('%016x%016x%016x%016x', a.sc * 2654435761, a.sc * 40503, a.sc * 97, a.sc * 2246822519) ELSE '' END,
  a.sim,
  printf('%08x-%04x-4%03x-a%03x-%012x', a.h, a.i % 65536, a.i % 4096, (a.h / 4096) % 4096, a.i * 2654435761 % 281474976710656),
  1,
  CASE a.typ WHEN 'local' THEN s.kind WHEN 'import' THEN 'cscli' ELSE 'capi' END
    || '',
  CASE a.typ WHEN 'local' THEN a.machine WHEN 'import' THEN 1 END
FROM _a a JOIN _scen s ON s.k = a.sc JOIN _geo g ON g.k = a.geo LEFT JOIN _ip ip ON ip.pool = 0 AND ip.n = a.att
ORDER BY a.i;
-- alerts created before the kind column existed keep NULL
UPDATE alerts SET kind = NULL WHERE id < 50000*(SELECT scale FROM _cfg) / 25 AND kind = 'crowdsec';

-- decisions are staged in _d and written in alert order, so ids rise with time as they do on a live LAPI
CREATE TEMP TABLE _d AS SELECT * FROM decisions WHERE 0;

-- local decisions: one per local alert (4h ban, 7 days for some repeat offenders; 8 % captcha on http scenarios)
INSERT INTO _d(created_at, updated_at, until, scenario, type, start_ip, end_ip, start_suffix, end_suffix, ip_size,
                      scope, value, origin, simulated, uuid, alert_decisions)
SELECT (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t + CASE WHEN a.longban = 1 THEN 7*86400 ELSE 4*3600 END, 'unixepoch') || '.' || printf('%06d', ((a.h / 5) % 99999) * 10 + 1 + ((a.h / 5) / 7) % 9) || '+00:00'), s.name,
  CASE WHEN s.log_type = 'http_access-log' AND (a.h / 512) % 12 = 0 THEN 'captcha' ELSE 'ban' END,
  -9223372036854775807 + ip.num, -9223372036854775807 + ip.num,
  CASE ip.v6 WHEN 1 THEN -9223372036854775807 + ip.sfx END, CASE ip.v6 WHEN 1 THEN -9223372036854775807 + ip.sfx END,
  CASE ip.v6 WHEN 1 THEN 16 ELSE 4 END, 'Ip', ip.value, 'crowdsec', a.sim,
  printf('%08x-%04x-4%03x-b%03x-%012x', a.h / 3, a.i % 65536, (a.i * 7) % 4096, (a.h / 8192) % 4096, a.i * 40503 % 281474976710656),
  a.i
FROM _a a JOIN _scen s ON s.k = a.sc JOIN _ip ip ON ip.pool = 0 AND ip.n = a.att
WHERE a.typ = 'local' ORDER BY a.i;

-- cscli decisions import: the whole blocklist every 2 h, 4h duration
WITH RECURSIVE n(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM n WHERE k < 1500*(SELECT scale FROM _cfg) - 1)
INSERT INTO _d(created_at, updated_at, until, scenario, type, start_ip, end_ip, start_suffix, end_suffix, ip_size,
                      scope, value, origin, simulated, uuid, alert_decisions)
SELECT (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t + 4*3600, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), 'manual', 'ban',
  -9223372036854775807 + ip.num, -9223372036854775807 + ip.num + CASE ip.rng WHEN 1 THEN 255 ELSE 0 END, NULL, NULL, 4,
  CASE ip.rng WHEN 1 THEN 'Range' ELSE 'Ip' END, ip.value, 'cscli-import', 0,
  printf('%08x-%04x-4%03x-c%03x-%012x', (a.h + n.k * 2654435761) % 4294967296, n.k % 65536, a.i % 4096, n.k % 4096, (a.i * 1000003 + n.k) * 40503 % 281474976710656),
  a.i
FROM _a a JOIN n JOIN _ip ip ON ip.pool = 1 AND ip.n = n.k
WHERE a.typ = 'import' ORDER BY a.i, n.k;

-- CAPI: the latest pull carries the full community blocklist, earlier pulls keep ~40 values that were not re-sent
WITH RECURSIVE n(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM n WHERE k < 6000*(SELECT scale FROM _cfg) - 1)
INSERT INTO _d(created_at, updated_at, until, scenario, type, start_ip, end_ip, start_suffix, end_suffix, ip_size,
                      scope, value, origin, simulated, uuid, alert_decisions)
SELECT (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t + 4*86400 + (ip.num % 3) * 86400 + (n.k % 3600), 'unixepoch') || '.' || printf('%06d', ((a.h + n.k) % 99999) * 10 + 1 + ((a.h + n.k) / 7) % 9) || '+00:00'), (SELECT name FROM _scen WHERE k = (n.k * 7) % 15), 'ban',
  -9223372036854775807 + ip.num, -9223372036854775807 + ip.num, NULL, NULL, 4, 'Ip', ip.value, 'CAPI', 0, '', a.i
FROM _a a JOIN n JOIN _ip ip ON ip.pool = 2 AND ip.n = CASE WHEN a.seq = (SELECT max(seq) FROM _a WHERE typ = 'capi') THEN n.k
                                                            ELSE 6000*(SELECT scale FROM _cfg) + (a.seq * 211 + n.k * 37) % 20000 END
WHERE a.typ = 'capi' AND (a.seq = (SELECT max(seq) FROM _a WHERE typ = 'capi') OR n.k < 30 + a.h % 20)
ORDER BY a.i, n.k;

-- lists: firehol_cruzit_web_attacks, 800 values per pull drawn from a 1200-entry pool (heavy overlap between pulls)
WITH RECURSIVE n(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM n WHERE k < 800*(SELECT scale FROM _cfg) - 1)
INSERT INTO _d(created_at, updated_at, until, scenario, type, start_ip, end_ip, start_suffix, end_suffix, ip_size,
                      scope, value, origin, simulated, uuid, alert_decisions)
SELECT (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t + 86400 + 3600, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), 'firehol_cruzit_web_attacks', 'ban',
  -9223372036854775807 + ip.num, -9223372036854775807 + ip.num, NULL, NULL, 4, 'Ip', ip.value, 'lists', 0, '', a.i
FROM _a a JOIN n JOIN _ip ip ON ip.pool = 3 AND ip.n = (n.k + a.seq * 50) % (1200*(SELECT scale FROM _cfg))
WHERE a.typ = 'lists' ORDER BY a.i, n.k;

-- a few hundred manual cscli decisions with no alert left (orphans, the FlushOrphans target)
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 300*(SELECT scale FROM _cfg))
INSERT INTO _d(created_at, updated_at, until, scenario, type, start_ip, end_ip, start_suffix, end_suffix, ip_size,
                      scope, value, origin, simulated, uuid, alert_decisions)
SELECT (strftime('%Y-%m-%d %H:%M:%S', 1793361600 - 20*86400 + k * 3600, 'unixepoch') || '.' || printf('%06d', ((k * 2654435761) % 99999) * 10 + 1 + ((k * 2654435761) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', 1793361600 - 20*86400 + k * 3600, 'unixepoch') || '.' || printf('%06d', ((k * 2654435761) % 99999) * 10 + 1 + ((k * 2654435761) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', 1793361600 - 20*86400 + k * 3600 + 86400, 'unixepoch') || '.' || printf('%06d', ((k * 40503) % 99999) * 10 + 1 + ((k * 40503) / 7) % 9) || '+00:00'), 'manual ''ban'' from ''localhost''', 'ban',
  -9223372036854775807 + ip.num, -9223372036854775807 + ip.num, NULL, NULL, 4, 'Ip', ip.value, 'cscli', 0,
  printf('%08x-0000-4000-8000-%012x', k * 2654435761 % 4294967296, k), NULL
FROM n JOIN _ip ip ON ip.pool = 2 AND ip.n = 6000*(SELECT scale FROM _cfg) + 15000 + k % 5000;

INSERT INTO decisions(created_at, updated_at, until, scenario, type, start_ip, end_ip, start_suffix, end_suffix, ip_size,
                      scope, value, origin, simulated, uuid, alert_decisions)
SELECT created_at, updated_at, until, scenario, type, start_ip, end_ip, start_suffix, end_suffix, ip_size,
       scope, value, origin, simulated, uuid, alert_decisions
FROM _d ORDER BY coalesce(alert_decisions, 0), rowid;
DROP TABLE _d;

-- events: 1-3 per local alert; serialized is the JSON of the event's meta list
WITH RECURSIVE e(j) AS (SELECT 1 UNION ALL SELECT j+1 FROM e WHERE j < 6)
INSERT INTO events(created_at, updated_at, time, serialized, alert_events)
SELECT (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t - 60 + e.j * 9, 'unixepoch') || '.' || printf('%06d', ((a.h + e.j) % 99999) * 10 + 1 + ((a.h + e.j) / 7) % 9) || '+00:00'),
  '[{"key":"log_type","value":"' || s.log_type
  || '"},{"key":"source_ip","value":"' || ip.value || '"},'
  || CASE WHEN s.log_type = 'ssh_failed-auth' THEN '{"key":"target_user","value":"' || CASE (a.h + e.j) % 5 WHEN 0 THEN 'root' WHEN 1 THEN 'admin' WHEN 2 THEN 'ubuntu' WHEN 3 THEN 'test' ELSE 'oracle' END || '"},'
          ELSE '{"key":"http_path","value":"' || CASE (a.h + e.j) % 5 WHEN 0 THEN '/wp-login.php' WHEN 1 THEN '/.env' WHEN 2 THEN '/admin/config.php' WHEN 3 THEN '/phpmyadmin/' ELSE '/vendor/phpunit/src/Util/PHP/eval-stdin.php' END || '"},' END
  || '{"key":"service","value":"' || CASE WHEN s.log_type = 'ssh_failed-auth' THEN 'ssh' ELSE 'http' END || '"},{"key":"timestamp","value":"'
  || strftime('%Y-%m-%dT%H:%M:%SZ', a.t - 60 + e.j * 9, 'unixepoch') || '"}]',
  a.i
FROM _a a JOIN e ON e.j <= 1 + a.h % 3 JOIN _scen s ON s.k = a.sc JOIN _geo g ON g.k = a.geo JOIN _ip ip ON ip.pool = 0 AND ip.n = a.att
WHERE a.typ = 'local' ORDER BY a.i, e.j;

-- alert context metas: target_user for ssh alerts, target_uri + user_agent for the others
WITH RECURSIVE e(j) AS (SELECT 1 UNION ALL SELECT 2)
INSERT INTO meta(created_at, updated_at, key, value, alert_metas)
SELECT (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'), (strftime('%Y-%m-%d %H:%M:%S', a.t, 'unixepoch') || '.' || printf('%06d', ((a.h) % 99999) * 10 + 1 + ((a.h) / 7) % 9) || '+00:00'),
  CASE WHEN s.log_type = 'ssh_failed-auth' THEN CASE e.j WHEN 1 THEN 'target_user' ELSE 'service' END
       ELSE CASE e.j WHEN 1 THEN 'target_uri' ELSE 'user_agent' END END,
  CASE WHEN s.log_type = 'ssh_failed-auth' THEN CASE e.j WHEN 1 THEN '["root","admin","ubuntu"]' ELSE '["ssh"]' END
       ELSE CASE e.j WHEN 1 THEN '["/wp-login.php","/.env","/xmlrpc.php"]'
                 ELSE '["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/' || (100 + a.h % 30) || '.0.0.0 Safari/537.36"]' END END,
  a.i
FROM _a a JOIN e JOIN _scen s ON s.k = a.sc WHERE a.typ = 'local' AND (e.j = 1 OR s.log_type <> 'ssh_failed-auth') ORDER BY a.i, e.j;

-- some orphan metas left by pre-1.8 inserts (flushOrphanMetas target)
INSERT INTO meta(created_at, updated_at, key, value, alert_metas)
SELECT created_at, updated_at, key, value, NULL FROM meta WHERE id % 50 = 7;

INSERT INTO allow_lists(id, created_at, updated_at, name, from_console, description, allowlist_id)
VALUES (1, '2026-01-12 09:00:00.25+00:00', '2026-10-01 09:00:00.25+00:00', 'office-and-partners', 0, 'office egress and partner scanners', NULL);
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 40)
INSERT INTO allow_list_items(id, created_at, updated_at, expires_at, comment, value, start_ip, end_ip, start_suffix, end_suffix, ip_size)
SELECT k, '2026-01-12 09:00:00.25+00:00', '2026-01-12 09:00:00.25+00:00',
  CASE WHEN k % 4 = 0 THEN '2026-11-0' || (1 + k % 9) || ' 00:00:00.5+00:00' WHEN k % 7 = 0 THEN '2026-09-01 00:00:00.5+00:00' END,
  'partner ' || k, ip.value || CASE WHEN k % 5 = 0 THEN '' ELSE '' END,
  -9223372036854775807 + ip.num, -9223372036854775807 + ip.num, NULL, NULL, 4
FROM n JOIN _ip ip ON ip.pool = 0 AND ip.n = k * 997 + 3;
INSERT INTO allow_list_allowlist_items SELECT 1, id FROM allow_list_items;

WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 2000)
INSERT INTO metrics(id, generated_type, generated_by, received_at, pushed_at, payload)
SELECT k, CASE WHEN k % 3 = 0 THEN 'LP' ELSE 'RC' END,
  CASE WHEN k % 3 = 0 THEN 'web-0' || (1 + k % 2) ELSE 'cs-firewall-bouncer-' || (1 + k % 6) END,
  (strftime('%Y-%m-%d %H:%M:%S', 1793361600 - (2000 - k) * 300, 'unixepoch') || '.' || printf('%06d', ((k * 2654435761) % 99999) * 10 + 1 + ((k * 2654435761) / 7) % 9) || '+00:00'), CASE WHEN k < 1900 THEN (strftime('%Y-%m-%d %H:%M:%S', 1793361600 - (2000 - k) * 300, 'unixepoch') || '.' || printf('%06d', ((k * 2654435761) % 99999) * 10 + 1 + ((k * 2654435761) / 7) % 9) || '+00:00') END,
  '{"metrics":[{"items":[{"name":"dropped","unit":"packet","value":' || (k * 37 % 5000) || ',"labels":{"origin":"CAPI","ip_type":"ipv4"}},{"name":"dropped","unit":"byte","value":' || (k * 977 % 400000) || ',"labels":{"origin":"crowdsec","ip_type":"ipv4"}}],"meta":{"utc_now_timestamp":' || (1793361600 - (2000 - k) * 300) || ',"window_size_seconds":1800}}],"remediation_components":[{"type":"crowdsec-firewall-bouncer","version":"v0.0.31"}]}'
FROM n;

DROP TABLE _a; DROP TABLE _ip; DROP TABLE _scen; DROP TABLE _geo;
COMMIT;
