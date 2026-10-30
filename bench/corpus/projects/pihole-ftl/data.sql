-- Synthetic data for pi-hole/FTL. Deterministic (no random()): values come from multiplicative hashes of row numbers.
-- _cfg.scale multiplies the big tables. Scale 1: 100k queries over 7 days (90k also in disk_query_storage),
-- 6k domains, 60 client names, 300 network devices; gravity 150k domains in 30 adlists, 3k domainlist entries.
BEGIN;

-- ---------------------------------------------------------------- gravity.db
INSERT INTO "group"(id, enabled, name, date_added, date_modified, description) VALUES
  (0, 1, 'Default', 1700000000, 1700000000, 'The default group'),
  (1, 1, 'kids', 1700000100, 1700000100, 'Kids devices'),
  (2, 1, 'iot', 1700000200, 1700000200, 'Smart home'),
  (3, 1, 'guests', 1700000300, 1700000300, NULL),
  (4, 1, 'work', 1700000400, 1700000400, 'Work laptops'),
  (5, 0, 'tv', 1700000500, 1700000500, 'Disabled for now'),
  (6, 1, 'phones', 1700000600, 1700000600, NULL),
  (7, 1, 'lab', 1700000700, 1700000700, 'Homelab'),
  (8, 0, 'blocked-all', 1700000800, 1700000800, 'Strict');

-- 27 blocklists + 3 allowlists (type 1, feed antigravity); the tr_adlist_add trigger puts every list in group 0
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 30)
INSERT INTO adlist(id, address, enabled, date_added, date_modified, comment, date_updated, number, invalid_domains, status, abp_entries, type)
SELECT i, printf('https://lists.example.org/%s/list%d.txt', CASE WHEN i > 27 THEN 'allow' ELSE 'block' END, i),
       CASE WHEN i % 11 = 0 THEN 0 ELSE 1 END, 1700000000 + i * 86400, 1700000000 + i * 86400,
       CASE WHEN i % 4 = 0 THEN NULL ELSE 'List ' || i END, 1761000000 - i * 3600, 5000 + (i * 7919) % 50000, i % 7,
       1 + i % 4, CASE WHEN i % 5 = 0 THEN 100 + i ELSE 0 END, CASE WHEN i > 27 THEN 1 ELSE 0 END
FROM n;
INSERT INTO adlist_by_group(adlist_id, group_id) SELECT id, 1 + id % 8 FROM adlist WHERE id % 3 = 0;
INSERT INTO adlist_by_group(adlist_id, group_id) SELECT id, 1 + (id * 5) % 8 FROM adlist WHERE id % 4 = 1 AND 1 + (id * 5) % 8 <> 1 + id % 8;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 150000*(SELECT scale FROM _cfg))
INSERT INTO gravity(domain, adlist_id)
SELECT printf('ad%d.track%d.net', i, i % 97), 1 + ((i * 2654435761) % 4294967296) % 27 FROM n;
-- a slice of domains is listed by a second blocklist too
INSERT INTO gravity(domain, adlist_id)
SELECT domain, 1 + (adlist_id + 13) % 27 FROM gravity WHERE rowid % 9 = 0;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000*(SELECT scale FROM _cfg))
INSERT INTO antigravity(domain, adlist_id)
SELECT printf('ad%d.track%d.net', i * 7, (i * 7) % 97), 28 + i % 3 FROM n;

-- domainlist: 30% exact allow (0), 40% exact deny (1), 10% regex allow (2), 20% regex deny (3)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 3000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n),
t AS (SELECT i, h, CASE WHEN (h / 32) % 10 < 3 THEN 0 WHEN (h / 32) % 10 < 7 THEN 1 WHEN (h / 32) % 10 < 8 THEN 2 ELSE 3 END AS ty FROM m)
INSERT INTO domainlist(id, type, domain, enabled, date_added, date_modified, comment)
SELECT i, ty,
       CASE ty WHEN 0 THEN printf('host%d.%s', 1501 + (h / 1024) % 4500, CASE (h / 8) % 5 WHEN 0 THEN 'example.com' WHEN 1 THEN 'cdn.net' WHEN 2 THEN 'apple.com' WHEN 3 THEN 'google.com' ELSE 'netflix.com' END)
               WHEN 1 THEN printf('ad%d.track%d.net', 1 + (h / 4096) % 150000, (1 + (h / 4096) % 150000) % 97)
               WHEN 2 THEN printf('(^|\.)allowed%d\.example\.com$', i)
               ELSE printf('(^|\.)tracker%d\.(com|net)$', i) END,
       CASE WHEN i % 17 = 0 THEN 0 ELSE 1 END, 1700000000 + i * 3600, 1700000000 + i * 3600 + (h % 86400),
       CASE WHEN i % 3 = 0 THEN NULL WHEN i % 3 = 1 THEN 'Added from query log' ELSE 'Imported ' || i END
FROM t
WHERE true
ON CONFLICT(domain, type) DO NOTHING;
INSERT INTO domainlist_by_group(domainlist_id, group_id) SELECT id, 1 + id % 8 FROM domainlist WHERE id % 4 = 0;
DELETE FROM domainlist_by_group WHERE group_id = 0 AND domainlist_id % 20 = 0;

-- clients: 50 IPs, 2 subnets, 10 MAC addresses (the first network devices)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 50)
INSERT INTO client(id, ip, date_added, date_modified, comment)
SELECT i, '192.168.1.' || (i + 1), 1700000000 + i * 600, 1700000000 + i * 600, CASE WHEN i % 3 = 0 THEN 'Device ' || i END FROM n;
INSERT INTO client(id, ip, date_added, date_modified, comment) VALUES
  (51, '10.0.0.0/24', 1700100000, 1700100000, 'VPN'), (52, 'fd00::/64', 1700100000, 1700100000, 'IPv6 LAN');
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 10)
INSERT INTO client(id, ip, date_added, date_modified, comment)
SELECT 52 + i, printf('02:00:00:%02X:%02X:%02X', i, (i * 7) % 256, (i * 13) % 256), 1700200000, 1700200000, 'by MAC' FROM n;
INSERT INTO client_by_group(client_id, group_id) SELECT id, 1 + id % 8 FROM client WHERE id % 2 = 0;
INSERT OR IGNORE INTO client_by_group(client_id, group_id) SELECT id, 1 + (id * 3) % 8 FROM client WHERE id % 5 = 0;

INSERT INTO info(property, value) VALUES ('version', '20'), ('updated', '1761000000'), ('gravity_count', '150000'),
  ('antigravity_count', '2000'), ('abp_domains', '0'), ('gravity_restored', 'false');

-- ---------------------------------------------------------------- query database
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 6000*(SELECT scale FROM _cfg))
INSERT INTO domain_by_id(id, domain)
SELECT i, CASE WHEN i <= 1500*(SELECT scale FROM _cfg) THEN printf('ad%d.track%d.net', i, i % 97)
               ELSE printf('host%d.%s', i, CASE i % 5 WHEN 0 THEN 'example.com' WHEN 1 THEN 'cdn.net' WHEN 2 THEN 'apple.com' WHEN 3 THEN 'google.com' ELSE 'netflix.com' END) END
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 60)
INSERT INTO client_by_id(id, ip, name)
SELECT i, '192.168.1.' || (CASE WHEN i <= 50 THEN i ELSE i - 50 END + 1),
       CASE WHEN i > 50 THEN 'renamed-' || i || '.lan' WHEN i % 7 = 0 THEN '' ELSE 'device-' || i || '.lan' END
FROM n;

INSERT INTO forward_by_id(id, forward) VALUES (1, '1.1.1.1#53'), (2, '9.9.9.9#53'), (3, '8.8.8.8#53'), (4, '2606:4700::1111#53');

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300)
INSERT INTO addinfo_by_id(id, type, content) SELECT i, 1, printf('edge%d.cdn%d.akamai.net', i, i % 13) FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 100000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n),
s AS (SELECT i, h,
        CASE WHEN (h / 7) % 100 < 15 THEN 1 WHEN (h / 7) % 100 < 18 THEN 4 WHEN (h / 7) % 100 < 20 THEN 5
             WHEN (h / 7) % 100 < 22 THEN 9 WHEN (h / 7) % 100 < 50 THEN 2 WHEN (h / 7) % 100 < 53 THEN 12
             WHEN (h / 7) % 100 < 78 THEN 3 WHEN (h / 7) % 100 < 82 THEN 17 WHEN (h / 7) % 100 < 97 THEN 2
             ELSE 13 END AS st,
        (((h / 1000) % 1000) * ((h / 1000000) % 1000)) / 1000 AS skew
      FROM m)
INSERT INTO query_storage(id, timestamp, type, status, domain, client, forward, additional_info, reply_type, reply_time, dnssec, list_id, ede)
SELECT i,
       1761000000 + i * 6 + (h % 6) + ((h / 64) % 1000) / 1000.0,
       CASE WHEN (h / 101) % 100 < 55 THEN 1 WHEN (h / 101) % 100 < 85 THEN 2 WHEN (h / 101) % 100 < 90 THEN 16
            WHEN (h / 101) % 100 < 95 THEN 6 WHEN (h / 101) % 100 < 98 THEN 7 ELSE 165 END,
       st,
       CASE WHEN st IN (1, 4, 5, 9) THEN 1 + skew % (1500*(SELECT scale FROM _cfg))
            ELSE 1500*(SELECT scale FROM _cfg) + 1 + (skew * 7 + (h / 3) % 11) % (4500*(SELECT scale FROM _cfg)) END,
       1 + ((((h / 13) % 60) * ((h / 811) % 60)) / 60 + (h / 5) % 3) % 60,
       CASE WHEN st IN (2, 12, 13) THEN 1 + (h / 29) % 4 END,
       CASE WHEN st = 9 OR (st = 2 AND (h / 37) % 10 = 0) THEN 1 + (h / 41) % 300 END,
       CASE WHEN st IN (1, 4, 5, 9) THEN CASE (h / 17) % 3 WHEN 0 THEN 4 WHEN 1 THEN 2 ELSE 1 END
            ELSE CASE (h / 17) % 6 WHEN 0 THEN 1 WHEN 1 THEN 3 WHEN 2 THEN 2 ELSE 4 END END,
       CASE WHEN st IN (2, 12, 13) THEN ((h / 3) % 20000) / 100000.0 ELSE ((h / 3) % 300) / 1000000.0 END,
       CASE WHEN (h / 23) % 4 = 0 THEN 1 + (h / 92) % 5 ELSE 0 END,
       CASE WHEN st IN (1, 9) THEN 1 + (h / 43) % 27 WHEN st IN (4, 5) THEN 1 + (h / 43) % 3000 END,
       CASE WHEN (h / 53) % 50 = 0 THEN 15 END
FROM s;

INSERT INTO disk_query_storage SELECT * FROM query_storage WHERE id <= 90000*(SELECT scale FROM _cfg);

-- ---------------------------------------------------------------- network table
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 10)
INSERT INTO aliasclient(id, name, comment) SELECT i, 'alias-' || i, CASE WHEN i % 2 = 0 THEN 'grouped devices' END FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO network(id, hwaddr, interface, firstSeen, lastQuery, numQueries, macVendor, aliasclient_id)
SELECT i,
       CASE WHEN i % 25 = 0 THEN 'ip-192.168.' || (i / 250 + 1) || '.' || (i % 250 + 1)
            ELSE printf('02:00:00:%02x:%02x:%02x', i % 256, (i * 7) % 256, (i * 13 + i / 256) % 256) END,
       CASE WHEN i % 4 = 0 THEN 'wlan0' ELSE 'eth0' END,
       1700000000 + (h % 5000000), 1761000000 + (h / 7) % 600000, (h / 11) % 50000,
       CASE (h / 3) % 5 WHEN 0 THEN 'Apple, Inc.' WHEN 1 THEN 'Raspberry Pi Trading Ltd' WHEN 2 THEN 'Espressif Inc.' WHEN 3 THEN NULL ELSE 'Samsung Electronics' END,
       CASE WHEN i % 30 = 0 THEN 1 + (i / 30) % 10 END
FROM m;

INSERT INTO network_addresses(network_id, ip, lastSeen, name, nameUpdated)
SELECT id, '192.168.' || (id / 250 + 1) || '.' || (id % 250 + 1), lastQuery,
       CASE WHEN id % 3 = 0 THEN NULL ELSE 'device-' || id || '.lan' END, CASE WHEN id % 3 = 0 THEN NULL ELSE lastQuery - 600 END
FROM network
UNION ALL
SELECT id, printf('fd00::%x', id), lastQuery - 3600, CASE WHEN id % 4 = 0 THEN 'device-' || id || '-v6.lan' END,
       CASE WHEN id % 4 = 0 THEN lastQuery - 4000 END
FROM network WHERE id % 2 = 0;

-- a few stale/duplicate rows: devices 1..20 also had an old IP
INSERT INTO network_addresses(network_id, ip, lastSeen, name, nameUpdated)
SELECT id, '10.0.0.' || id, lastQuery - 86400 * 3, 'old-' || id || '.lan', lastQuery - 86400 * 3 FROM network WHERE id <= 20;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 60)
INSERT INTO message(id, timestamp, type, message, blob1, blob2, blob3)
SELECT i, 1761000000 + i * 9000,
       CASE i % 6 WHEN 0 THEN 'DNSMASQ_WARN' WHEN 1 THEN 'RATE_LIMIT' WHEN 2 THEN 'CONNECTION_ERROR' WHEN 3 THEN 'LOAD' WHEN 4 THEN 'SUBNET' ELSE 'HOSTNAME' END,
       'message ' || i, '192.168.1.' || (i % 50 + 2), i * 10, NULL
FROM n;
COMMIT;
