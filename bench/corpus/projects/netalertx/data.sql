-- Synthetic data for NetAlertX: a home/small-office network watched for 90 days (DAYS_TO_KEEP_EVENTS default).
-- Deterministic (no random()): values come from multiplicative hashes of row numbers. "Now" is 2026-09-21 14:13:20 UTC
-- (epoch 1790000000); timestamps are UTC 'YYYY-MM-DD HH:MM:SS' text as the app stores them.
-- Scale 1: 400 devices (35 % phones/laptops that come and go several times a day, 40 % stationary, IoT, 20 switches/APs,
-- 20 servers with NIC children; 7 archived, 11 new), ~46k connect/disconnect sessions -> ~93k Events, Sessions rebuilt
-- from Convert_Events_to_Sessions as the app does, the last 6 hours left unpaired for pair_sessions_events(), one
-- in-flight CurrentScan (ARPSCAN/NSLOOKUP/DHCPLSS rows, 6 unknown MACs, devices appearing, vanishing and changing IP),
-- 75k Plugins_History rows over 6 plugins (some past PLUGINS_KEEP_HIST=10000), ~760 Plugins_Objects with duplicates,
-- 6000 AppEvents, 2000 Online_History rows, 30 days of per-minute Resource_History. _cfg.scale multiplies devices
-- (and so events), Plugins_History and AppEvents.
BEGIN;

CREATE TEMP TABLE _n(j INTEGER PRIMARY KEY);
WITH RECURSIVE n(j) AS (SELECT 0 UNION ALL SELECT j + 1 FROM n WHERE j < 299) INSERT INTO _n SELECT j FROM n;

CREATE TEMP TABLE _dev AS
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k + 1 FROM n WHERE k < 400 * (SELECT scale FROM _cfg))
SELECT k, k % 20 AS c, (k * 2654435761) % 4294967296 AS h,
  printf('%02x:%02x:%02x:%02x:%02x:%02x', CASE k % 4 WHEN 0 THEN 0 WHEN 1 THEN 28 WHEN 2 THEN 184 ELSE 218 END,
         (k * 7) % 256, (k * 13) % 256, k / 256 % 256, k % 256, (k * 31) % 256) AS mac,
  '192.168.' || (1 + k / 250) || '.' || (2 + k % 250) AS ip,
  CASE WHEN k % 20 < 7 THEN 300 WHEN k % 20 < 15 THEN 12 WHEN k % 20 < 17 THEN 40 WHEN k % 20 = 17 THEN 3
       WHEN k % 20 = 18 THEN 5 ELSE 4 END AS m,
  CASE WHEN k % 37 = 0 THEN 1 ELSE 0 END AS isnew,
  CASE WHEN k % 20 IN (17, 19) OR k % 23 = 0 THEN 1 ELSE 0 END AS alertdown,
  CASE WHEN (k * 2654435761) % 4294967296 % 10 < 6 OR k % 20 IN (17, 19) THEN 1 ELSE 0 END AS present
FROM n;

-- Sessions per device: m slots over 90 days (2 days for new devices), one connect/disconnect pair each.
CREATE TEMP TABLE _ses AS
SELECT d.k, d.mac, d.ip, d.c, d.alertdown, d.present, d.isnew, d.m, n.j,
  ((d.k * 40503 + n.j * 2654435761) % 4294967296) AS hs,
  (1790000000 - CASE WHEN d.isnew = 1 THEN 2 ELSE 90 END * 86400) AS t0,
  (CASE WHEN d.isnew = 1 THEN 2 ELSE 90 END * 86400) / d.m AS slot
FROM _dev AS d JOIN _n AS n ON n.j < d.m;

CREATE TEMP TABLE _ev(mac, ip, t, type, info, pending);
-- connections
INSERT INTO _ev
SELECT mac, ip, t0 + j * slot + hs % (slot / 3 + 1) AS t,
  CASE WHEN j = 0 THEN 'New Device'
       WHEN alertdown = 1 AND ((k * 40503 + (j - 1) * 2654435761) % 4294967296) % 5 = 0 THEN 'Down Reconnected'
       ELSE 'Connected' END, '', 0
FROM _ses;
-- disconnections (the last session of a present device stays open)
INSERT INTO _ev
SELECT mac, ip, t0 + j * slot + hs % (slot / 3 + 1) + slot * (20 + hs / 7 % 40) / 100,
  CASE WHEN alertdown = 1 AND hs % 5 = 0 THEN 'Device Down' ELSE 'Disconnected' END, '', 0
FROM _ses WHERE NOT (j = m - 1 AND present = 1);
-- occasional IP changes mid-session
INSERT INTO _ev
SELECT mac, '192.168.9.' || (hs % 250), t0 + j * slot + hs % (slot / 3 + 1) + 60,
  'IP Changed', 'Previous IP: ' || ip || ' | New IP(s): 192.168.9.' || (hs % 250), 0
FROM _ses WHERE hs % 61 = 0;

INSERT OR IGNORE INTO Events(eveMac, eveIp, eveDateTime, eveEventType, eveAdditionalInfo, evePendingAlertEmail)
SELECT mac, ip, datetime(t, 'unixepoch'), type, info,
  CASE WHEN t > 1790000000 - 86400 AND (t % 3) = 0 THEN 1 ELSE 0 END
FROM _ev ORDER BY t;

-- the app's own pairing (server/scan/session_events.py pair_sessions_events), then unpair the last 6 hours
UPDATE Events SET evePairEventRowid =
   (SELECT ROWID FROM Events AS EVE2
    WHERE EVE2.eveEventType IN ('New Device', 'Connected', 'Down Reconnected', 'Device Down', 'Disconnected')
      AND EVE2.eveMac = Events.eveMac AND EVE2.eveDateTime > Events.eveDateTime
    ORDER BY EVE2.eveDateTime ASC LIMIT 1)
WHERE eveEventType IN ('New Device', 'Connected', 'Down Reconnected') AND evePairEventRowid IS NULL;
UPDATE Events SET evePairEventRowid = (SELECT ROWID FROM Events AS EVE2 WHERE EVE2.evePairEventRowid = Events.ROWID)
WHERE eveEventType IN ('Device Down', 'Disconnected') AND evePairEventRowid IS NULL;
UPDATE Events SET evePairEventRowid = NULL WHERE eveDateTime >= '2026-09-21 08:13:20';
INSERT INTO Sessions SELECT * FROM Convert_Events_to_Sessions;

INSERT INTO Devices(devMac, devName, devOwner, devType, devVendor, devFavorite, devGroup, devComments,
  devFirstConnection, devLastConnection, devLastIP, devPrimaryIPv4, devStaticIP, devScan, devLogEvents, devAlertEvents,
  devAlertDown, devSkipRepeated, devPresentLastScan, devIsNew, devLocation, devIsArchived, devParentMAC, devParentPort,
  devParentRelType, devIcon, devGUID, devSite, devSSID, devSyncHubNode, devSourcePlugin, devFQDN, devMacSource,
  devNameSource, devLastIPSource, devVendorSource, devCustomProps, devReqNicsOnline, devCanSleep)
SELECT d.mac,
  CASE WHEN d.k % 11 = 0 THEN '(unknown)' WHEN d.k % 29 = 0 THEN '(name not found)'
       ELSE (CASE WHEN d.c < 7 THEN 'phone-' WHEN d.c < 15 THEN 'pc-' WHEN d.c < 17 THEN 'iot-' WHEN d.c = 17 THEN 'sw-'
                  WHEN d.c = 18 THEN 'nic-' ELSE 'srv-' END) || d.k END,
  CASE d.h % 5 WHEN 0 THEN 'Alice' WHEN 1 THEN 'Bob' WHEN 2 THEN 'House' WHEN 3 THEN 'Office' ELSE '(unknown)' END,
  CASE WHEN d.c < 4 THEN 'Phone' WHEN d.c < 7 THEN 'Laptop' WHEN d.c < 11 THEN 'PC' WHEN d.c < 13 THEN 'Smart TV'
       WHEN d.c < 15 THEN 'Printer' WHEN d.c < 17 THEN 'IoT' WHEN d.c = 17 THEN (CASE WHEN d.k % 3 = 0 THEN 'Switch' ELSE 'AP' END)
       WHEN d.c = 18 THEN 'USB LAN Adapter' ELSE 'Server' END,
  CASE d.h / 8 % 6 WHEN 0 THEN 'Apple, Inc.' WHEN 1 THEN 'Samsung Electronics' WHEN 2 THEN 'Intel Corporate'
       WHEN 3 THEN 'Espressif Inc.' WHEN 4 THEN 'Ubiquiti Inc' ELSE '(unknown)' END,
  CASE WHEN d.k % 17 = 1 THEN 1 ELSE 0 END,
  CASE d.c % 4 WHEN 0 THEN 'Always on' WHEN 1 THEN 'Personal' WHEN 2 THEN 'Friends' ELSE 'Others' END, '',
  (SELECT MIN(eveDateTime) FROM Events WHERE eveMac = d.mac),
  (SELECT MAX(eveDateTime) FROM Events WHERE eveMac = d.mac),
  d.ip, d.ip, CASE WHEN d.c >= 17 THEN 1 ELSE 0 END, 1, 1, 1, d.alertdown, 0, d.present, d.isnew,
  CASE d.k % 7 WHEN 0 THEN 'Kitchen' WHEN 1 THEN 'Office' WHEN 2 THEN 'Living room' WHEN 3 THEN 'Garage' ELSE 'Upstairs' END,
  CASE WHEN d.k % 53 = 0 THEN 1 ELSE 0 END,
  CASE WHEN d.c = 17 THEN 'internet' WHEN d.c = 18 THEN (SELECT mac FROM _dev AS p WHERE p.k = d.k + 1)
       ELSE (SELECT mac FROM _dev AS p WHERE p.k = (d.k / 20) * 20 + 17) END,
  d.k % 24 + 1, CASE WHEN d.c = 18 THEN 'nic' ELSE 'default' END, 'PGkgY2xhc3M9ImZhIGZhLWxhcHRvcCI+PC9pPg==',
  printf('%08x-%04x-4%03x-a%03x-%012x', d.h, d.k % 65536, d.k % 4096, d.h % 4096, d.k * 2654435761 % 281474976710656),
  CASE WHEN d.k % 5 = 0 THEN 'branch' ELSE 'home' END, CASE WHEN d.c < 7 THEN 'HomeWiFi' ELSE '' END, 'nax-main',
  CASE WHEN d.k % 3 = 0 THEN 'NSLOOKUP' ELSE 'ARPSCAN' END, CASE WHEN d.k % 3 = 0 THEN 'host' || d.k || '.lan' ELSE '' END,
  'ARPSCAN', CASE WHEN d.k % 3 = 0 THEN 'NSLOOKUP' ELSE 'NEWDEV' END, 'ARPSCAN', 'VNDRPDT', '',
  CASE WHEN d.c = 19 THEN 1 ELSE 0 END, CASE WHEN d.c < 4 AND d.k % 2 = 0 THEN 1 ELSE 0 END
FROM _dev AS d;

-- One scan cycle in flight. ARPSCAN for present devices except every 17th; offline devices k % 13 = 0 reappear;
-- every 29th present device shows up on a new IP; NSLOOKUP and DHCPLSS (presence 0) rows for a third / half.
INSERT INTO CurrentScan(scanMac, scanLastIP, scanVendor, scanSourcePlugin, scanName, scanLastQuery, scanLastConnection,
  scanSyncHubNode, scanSite, scanSSID, scanVlan, scanParentMAC, scanType, scanCreatesDevice, scanNotificationMode, scanPresence)
SELECT mac, CASE WHEN k % 29 = 0 THEN '192.168.200.' || (k % 250) ELSE ip END, 'Vendor ' || (h % 50), 'ARPSCAN', '',
  'arp-scan: 192.168.1.0/24', '2026-09-21 14:13:20', 'nax-main', 'home', '', '', '', '', 1,
  CASE WHEN k % 41 = 0 THEN 'quiet' ELSE 'normal' END, 1
FROM _dev WHERE (present = 1 AND k % 17 <> 0) OR (present = 0 AND k % 13 = 0);
INSERT INTO CurrentScan(scanMac, scanLastIP, scanSourcePlugin, scanName, scanLastConnection, scanCreatesDevice, scanPresence)
SELECT mac, ip, 'NSLOOKUP', 'host' || k || '.lan', '2026-09-21 14:13:19', 0, 0 FROM _dev WHERE k % 3 = 0 AND present = 1;
INSERT INTO CurrentScan(scanMac, scanLastIP, scanSourcePlugin, scanName, scanLastConnection, scanCreatesDevice, scanPresence)
SELECT mac, ip, 'DHCPLSS', 'dhcp-' || k, '2026-09-21 14:12:00', 1, 0 FROM _dev WHERE k % 2 = 0;
INSERT INTO CurrentScan(scanMac, scanLastIP, scanVendor, scanSourcePlugin, scanLastConnection, scanPresence)
SELECT printf('02:42:ac:11:00:%02x', k), '192.168.7.' || k, '(unknown)', 'ARPSCAN', '2026-09-21 14:13:20', 1
FROM (SELECT 1 AS k UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6);

-- Plugin tables
INSERT INTO Plugins_Objects(plugin, objectPrimaryId, objectSecondaryId, dateTimeCreated, dateTimeChanged, watchedValue1,
  watchedValue2, watchedValue3, watchedValue4, status, extra, userData, foreignKey, syncHubNodeName, objectGuid)
SELECT p.plugin, d.mac, d.ip, '2026-06-23 10:00:00', datetime(1790000000 - d.h % 86400, 'unixepoch'),
  CASE p.plugin WHEN 'ARPSCAN' THEN d.ip WHEN 'NSLOOKUP' THEN 'host' || d.k || '.lan' ELSE 'dhcp-' || d.k END,
  'Vendor ' || (d.h % 50), '', '', CASE WHEN d.present = 1 THEN 'watched-not-changed' ELSE 'missing-in-last-scan' END,
  '', '', d.mac, 'nax-main', printf('%08x-%04x', d.h, p.n)
FROM _dev AS d JOIN (SELECT 'ARPSCAN' AS plugin, 1 AS n UNION ALL SELECT 'NSLOOKUP', 2 UNION ALL SELECT 'DHCPLSS', 3) AS p
WHERE p.plugin = 'ARPSCAN' OR (p.plugin = 'NSLOOKUP' AND d.k % 3 = 0) OR (p.plugin = 'DHCPLSS' AND d.k % 2 = 0)
UNION ALL
SELECT 'ARPSCAN', d.mac, d.ip, '2026-07-01 10:00:00', '2026-09-20 10:00:00', d.ip, '', '', '', 'watched-changed',
  '', '', d.mac, 'nax-main', printf('%08x-dup', d.h)
FROM _dev AS d WHERE d.k % 19 = 0;

INSERT INTO Plugins_Events(plugin, objectPrimaryId, objectSecondaryId, dateTimeCreated, dateTimeChanged, watchedValue1,
  watchedValue2, watchedValue3, watchedValue4, status, extra, userData, foreignKey)
SELECT CASE k % 3 WHEN 0 THEN 'ARPSCAN' WHEN 1 THEN 'NSLOOKUP' ELSE 'DHCPLSS' END, mac, ip, '2026-09-21 14:00:00',
  '2026-09-21 14:13:20', ip, '', '', '', 'new', '', '', mac
FROM _dev WHERE k % 4 = 0;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 75000 * (SELECT scale FROM _cfg))
INSERT INTO Plugins_History(plugin, objectPrimaryId, objectSecondaryId, dateTimeCreated, dateTimeChanged, watchedValue1,
  watchedValue2, watchedValue3, watchedValue4, status, extra, userData, foreignKey, syncHubNodeName, objectGuid)
SELECT p, d.mac, d.ip, datetime(t - 600, 'unixepoch'), datetime(t, 'unixepoch'), d.ip, 'Vendor ' || (d.h % 50),
  CASE WHEN p = 'NMAPDEV' THEN '22,80,443' ELSE '' END, '',
  CASE x.h % 4 WHEN 0 THEN 'new' WHEN 1 THEN 'watched-changed' WHEN 2 THEN 'watched-not-changed' ELSE 'missing-in-last-scan' END,
  CASE WHEN p = 'INTRNT' THEN '{"isp":"Example ISP","ip":"203.0.113.' || (x.h % 250) || '"}' ELSE '' END, '', d.mac,
  'nax-main', printf('%08x', x.h)
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h,
             CASE WHEN i % 25 < 10 THEN 'ARPSCAN' WHEN i % 25 < 14 THEN 'NSLOOKUP' WHEN i % 25 < 19 THEN 'DHCPLSS'
                  WHEN i % 25 < 22 THEN 'INTRNT' WHEN i % 25 < 23 THEN 'NMAPDEV' ELSE 'AVAHISCAN' END AS p,
             1790000000 - 90 * 86400 + i * (90 * 86400 / (75000 * (SELECT scale FROM _cfg))) AS t FROM n) AS x
JOIN _dev AS d ON d.k = 1 + x.h % (400 * (SELECT scale FROM _cfg));

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 6000 * (SELECT scale FROM _cfg))
INSERT INTO AppEvents(guid, appEventProcessed, dateTimeCreated, objectType, objectGuid, objectPlugin, objectPrimaryId,
  objectSecondaryId, objectForeignKey, objectIndex, objectIsNew, objectIsArchived, objectStatusColumn, objectStatus,
  appEventType, helper1, helper2, helper3, extra)
SELECT printf('%08x-%04x-4000-8000-%012x', i * 2654435761 % 4294967296, i % 65536, i), 1,
  datetime(1790000000 - (6000 * (SELECT scale FROM _cfg) - i) * 120, 'unixepoch'), 'Devices', printf('%08x', i), 'ARPSCAN',
  d.mac, d.ip, d.mac, CAST(d.k AS TEXT), 0, 0, 'devPresentLastScan', CASE i % 2 WHEN 0 THEN '1' ELSE '0' END,
  CASE i % 3 WHEN 0 THEN 'update' WHEN 1 THEN 'insert' ELSE 'delete' END, '', '', '', ''
FROM n JOIN _dev AS d ON d.k = 1 + (i * 7) % (400 * (SELECT scale FROM _cfg));

WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < 1999)
INSERT INTO Online_History(scanDate, onlineDevices, downDevices, allDevices, archivedDevices, offlineDevices)
SELECT datetime(1790000000 - i * 300, 'unixepoch'), 230 + i % 40, 2 + i % 3, 400, 7, 163 - i % 40 FROM n;

WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < 43199)
INSERT INTO Resource_History(resDateTime, resCpuPercent, resRssMb, resIoReadBytes, resIoWriteBytes, resScanDurationMs, resTickFailed)
SELECT datetime(1790000000 - (43199 - i) * 60, 'unixepoch'), 3.0 + (i * 2654435761 % 1000) / 100.0, 180 + i % 60,
  (i * 40503) % 200000, (i * 2654435761) % 900000, CASE WHEN i % 5 = 0 THEN 4000 + i % 3000 END,
  CASE WHEN i % 997 = 0 THEN 1 ELSE 0 END
FROM n;

-- Settings last, so the DevicesHistory triggers stay off while Devices is loaded.
INSERT INTO Settings(setKey, setName, setDescription, setType, setOptions, setGroup, setValue, setEvents, setOverriddenByEnv)
VALUES ('UI_MY_DEVICES', 'My devices', '', '{"dataType":"array"}', '[]', 'UI', '[''online'', ''offline'', ''archived'', ''new'', ''down'']', '[]', 0),
  ('DEV_HIST_DAYS', 'Device history retention (days)', '', '{"dataType":"integer"}', '[]', 'General', '1', '[]', 0),
  ('DEV_HIST_TRACKED', 'Device history tracked fields', '', '{"dataType":"array"}', '[]', 'General',
   '[''devMac'', ''devName'', ''devOwner'', ''devType'', ''devVendor'', ''devFavorite'', ''devGroup'', ''devComments'', ''devLastIP'', ''devFQDN'', ''devPrimaryIPv4'', ''devPrimaryIPv6'', ''devVlan'', ''devForceStatus'', ''devStaticIP'', ''devScan'', ''devAlertDown'', ''devCanSleep'', ''devSkipRepeated'', ''devLocation'', ''devIsArchived'', ''devParentMAC'', ''devParentPort'', ''devParentRelType'', ''devReqNicsOnline'', ''devIcon'', ''devSite'', ''devSSID'', ''devSyncHubNode'']', '[]', 0),
  ('NTFPRCS_sleep_time', 'Sleep time', '', '{"dataType":"integer"}', '[]', 'NTFPRCS', '30', '[]', 0),
  ('DAYS_TO_KEEP_EVENTS', 'Delete events', '', '{"dataType":"integer"}', '[]', 'DBCLNP', '90', '[]', 0),
  ('PLUGINS_KEEP_HIST', 'Keep history entries', '', '{"dataType":"integer"}', '[]', 'General', '10000', '[]', 0);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 300)
INSERT INTO Settings(setKey, setName, setDescription, setType, setOptions, setGroup, setValue, setEvents, setOverriddenByEnv)
SELECT 'PLUGIN' || (i / 10) || '_setting' || i, 'Setting ' || i, 'Description of setting ' || i, '{"dataType":"string"}', '[]',
  'PLUGIN' || (i / 10), CAST(i AS TEXT), '[]', 0 FROM n;

DROP TABLE _n; DROP TABLE _dev; DROP TABLE _ses; DROP TABLE _ev;
COMMIT;
