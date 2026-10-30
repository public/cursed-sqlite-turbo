-- Synthetic data for Technitium DNS Server's Query Logs (Sqlite) app. Deterministic (no random()): values come from
-- multiplicative hashes of the row number. "Now" is 2026-10-30 00:00:00 UTC; the log covers the 10 days before it,
-- so a maxLogDays = 7 cleanup has 3 days to remove. Timestamps use the app's own text format
-- ("yyyy-MM-dd HH:mm:ss.FFFFFFF", trailing zeros trimmed) and dlid follows time order, as the bulk inserter writes.
-- Scale 1: 250k log rows (13 secondary indexes make that ~110 MB), 120 clients (one smart TV/IoT-style client sends
-- ~20 %), 6k + 2k*scale domains with a heavy head (top 40 names ~25 % of traffic), ~12 % blocked (ad/tracker
-- domains), ~5 % NXDOMAIN. _cfg.scale multiplies the log rows and grows the domain tail.
BEGIN;

CREATE TEMP TABLE _head(k INTEGER PRIMARY KEY, name TEXT, kind TEXT);
INSERT INTO _head VALUES
 (0,'connectivitycheck.gstatic.com','ok'),(1,'www.google.com','ok'),(2,'graph.facebook.com','ok'),
 (3,'doubleclick.net','ad'),(4,'api.amazon.com','ok'),(5,'time.apple.com','ok'),(6,'googleads.g.doubleclick.net','ad'),
 (7,'gateway.icloud.com','ok'),(8,'www.youtube.com','ok'),(9,'i.ytimg.com','ok'),(10,'clients4.google.com','ok'),
 (11,'app-measurement.com','ad'),(12,'settings-win.data.microsoft.com','ad'),(13,'login.microsoftonline.com','ok'),
 (14,'netflix.com','ok'),(15,'api-global.netflix.com','ok'),(16,'ocsp.digicert.com','ok'),(17,'push.prod.netflix.com','ok'),
 (18,'mask.icloud.com','nx'),(19,'ssl.google-analytics.com','ad'),(20,'www.googleapis.com','ok'),(21,'github.com','ok'),
 (22,'api.github.com','ok'),(23,'wpad.lan','nx'),(24,'_dns.resolver.arpa','nx'),(25,'logs.roku.com','ad'),
 (26,'scribe.logs.roku.com','ad'),(27,'device-metrics-us.amazon.com','ad'),(28,'ntp.ubuntu.com','ok'),
 (29,'api.spotify.com','ok'),(30,'spclient.wg.spotify.com','ok'),(31,'mobile.events.data.microsoft.com','ad'),
 (32,'edge.microsoft.com','ok'),(33,'www.bing.com','ok'),(34,'cdn.jsdelivr.net','ok'),(35,'fonts.gstatic.com','ok'),
 (36,'play.googleapis.com','ok'),(37,'mtalk.google.com','ok'),(38,'samsungads.com','ad'),(39,'lan','nx');

-- 120 clients: 110 on 192.168.1.0/24, 8 on 10.0.0.0/24, 2 IPv6 ULA. Client k=0 is the heavy one.
CREATE TEMP TABLE _cli(k INTEGER PRIMARY KEY, ip TEXT);
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 119)
INSERT INTO _cli SELECT i, CASE WHEN i < 110 THEN '192.168.1.' || (10 + (i * 37) % 200)
                                WHEN i < 118 THEN '10.0.0.' || (i - 108)
                                ELSE 'fd00::1:' || (i - 117) END FROM n;

-- Domains: the 40 head names, then a synthetic tail of <sub>.<site>.<tld>; ~15 % of tail sites are ad/tracker hosts
-- (blocked), ~5 % don't exist (NXDOMAIN).
CREATE TEMP TABLE _dom(k INTEGER PRIMARY KEY, name TEXT, kind TEXT);
INSERT INTO _dom SELECT k, name, kind FROM _head;
WITH RECURSIVE n(i) AS (SELECT 40 UNION ALL SELECT i+1 FROM n WHERE i < 6000 + 2000 * (SELECT scale FROM _cfg) - 1)
INSERT INTO _dom
SELECT i,
  CASE (h / 7) % 12 WHEN 0 THEN 'www' WHEN 1 THEN 'api' WHEN 2 THEN 'cdn' WHEN 3 THEN 'static' WHEN 4 THEN 'img'
    WHEN 5 THEN 'edge' WHEN 6 THEN 'm' WHEN 7 THEN 'login' WHEN 8 THEN 'telemetry' WHEN 9 THEN 'update'
    WHEN 10 THEN 'assets' ELSE 'tracker' END
  || '.' || CASE WHEN h % 100 < 15 THEN 'adserv' WHEN h % 100 < 20 THEN 'gone' ELSE 'site' END || ((h / 1024) % 3000)
  || CASE (h / 65536) % 6 WHEN 0 THEN '.net' WHEN 1 THEN '.io' WHEN 2 THEN '.de' ELSE '.com' END,
  CASE WHEN h % 100 < 15 THEN 'ad' WHEN h % 100 < 20 THEN 'nx' ELSE 'ok' END
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n);

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 250000 * (SELECT scale FROM _cfg)),
cfg AS (SELECT 250000 * scale AS rows, (SELECT count(*) FROM _dom) AS ndom FROM _cfg),
r AS (
  SELECT i,
    (i * 2654435761) % 4294967296 AS h1,
    (i * 2246822519 + 374761393) % 4294967296 AS h2,
    (i * 3266489917 + 668265263) % 4294967296 AS h3,
    -- seconds since 2026-10-20 00:00:00 UTC; monotone in i
    (i - 1) * 864000.0 / cfg.rows + ((i * 40503) % 1000) * 0.000999 * 864000.0 / cfg.rows / 1000 AS secs,
    cfg.ndom AS ndom
  FROM n, cfg
),
p AS (
  SELECT r.*,
    CAST(ndom * (h1 / 4294967296.0) * (h1 / 4294967296.0) * (h1 / 4294967296.0) * (h1 / 4294967296.0) AS INTEGER) AS dk,
    CAST(120 * (h2 / 4294967296.0) * (h2 / 4294967296.0) * (h2 / 4294967296.0) AS INTEGER) AS ck,
    h3 % 100 AS qt, (h3 / 128) % 100 AS rt, (h2 / 64) % 100 AS pr, (h1 / 8) % 1000 AS ex
  FROM r
),
q AS (
  SELECT p.*, d.name AS dname, d.kind AS dkind, c.ip AS ip,
    CASE WHEN i % 5000 = 0 THEN 16
         WHEN qt < 52 THEN 1 WHEN qt < 80 THEN 28 WHEN qt < 90 THEN 65 WHEN qt < 93 THEN 12 WHEN qt < 95 THEN 16
         WHEN qt < 96 THEN 33 WHEN qt < 97 THEN 15 WHEN qt < 98 THEN 6 WHEN qt < 99 THEN 2 ELSE 5 END AS qtype
  FROM p JOIN _dom d ON d.k = p.dk JOIN _cli c ON c.k = p.ck
),
s AS (
  SELECT q.*,
    CASE WHEN i % 5000 = 0 THEN 1 WHEN dkind = 'ad' AND rt < 92 THEN 4 WHEN dkind = 'ad' AND rt < 96 THEN 5
         WHEN rt < 55 THEN 3 WHEN rt < 87 THEN 2 WHEN rt < 98 THEN 1 ELSE 7 END AS rtype,
    CASE WHEN i % 5000 = 0 THEN 0 WHEN dkind = 'nx' THEN 3 WHEN dkind = 'ad' THEN 0
         WHEN ex < 15 THEN 2 WHEN ex < 20 THEN 5 WHEN ex < 45 THEN 3 ELSE 0 END AS rc
  FROM q
)
INSERT INTO dns_logs (dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer)
SELECT i,
  rtrim(rtrim(strftime('%Y-%m-%d %H:%M:%S', 1792454400 + CAST(secs AS INTEGER), 'unixepoch')
        || '.' || printf('%07d', CAST((secs - CAST(secs AS INTEGER)) * 10000000 AS INTEGER)), '0'), '.'),
  ip,
  CASE WHEN ck >= 118 THEN 3 WHEN pr < 88 THEN 0 WHEN pr < 91 THEN 1 WHEN pr < 93 THEN 2 WHEN pr < 99 THEN 3 ELSE 5 END,
  rtype,
  CASE WHEN rtype = 2 THEN round(4.0 + (h3 % 997) / 31.0 + CASE WHEN h3 % 50 = 0 THEN (h3 / 50) % 1500 ELSE 0 END, 2) END,
  rc,
  CASE WHEN i % 5000 = 0 THEN 'version.bind'
       WHEN qtype = 12 THEN (h2 % 250 + 2) || '.1.168.192.in-addr.arpa'
       ELSE dname END,
  qtype,
  CASE WHEN i % 5000 = 0 THEN 3 ELSE 1 END,
  CASE WHEN rc <> 0 OR rtype = 7 THEN NULL
       WHEN rtype IN (4, 5) AND qtype = 1 THEN 'A 0.0.0.0'
       WHEN rtype IN (4, 5) AND qtype = 28 THEN 'AAAA ::'
       WHEN rtype IN (4, 5) THEN NULL
       WHEN i % 5000 = 0 THEN 'TXT "Technitium DNS Server"'
       WHEN qtype = 1 AND h1 % 3 = 0 THEN 'CNAME ' || dname || '.edgekey.net, CNAME e' || (h3 % 9000) || '.a.akamaiedge.net, A 23.' || (h3 % 200) || '.' || ((h3 / 256) % 256) || '.' || ((h3 / 65536) % 256)
       WHEN qtype = 1 THEN 'A ' || (h3 % 200 + 13) || '.' || ((h3 / 256) % 256) || '.' || ((h3 / 65536) % 256) || '.' || ((h3 / 16777216) % 256)
       WHEN qtype = 28 THEN 'AAAA 2a00:1450:4001:' || printf('%x', h3 % 4096) || '::' || printf('%x', (h3 / 4096) % 65536)
       WHEN qtype = 65 AND h1 % 2 = 0 THEN 'HTTPS 1 . alpn="h2,h3"'
       WHEN qtype = 65 THEN NULL
       WHEN qtype = 12 THEN 'PTR host-' || (h2 % 250 + 2) || '.lan'
       WHEN qtype = 16 THEN 'TXT "v=spf1 include:_spf.' || dname || ' ~all"'
       WHEN qtype = 33 THEN 'SRV 0 5 5223 courier.' || dname
       WHEN qtype = 15 THEN 'MX 10 mx.' || dname
       ELSE NULL END
FROM s;

DROP TABLE _head; DROP TABLE _cli; DROP TABLE _dom;
COMMIT;
