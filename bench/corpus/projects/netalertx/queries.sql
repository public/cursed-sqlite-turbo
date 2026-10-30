-- NetAlertX (netalertx/NetAlertX @ 6f3cb9b, GPL-3.0). Raw SQL run through python sqlite3: constant strings in
-- server/const.py, and statements assembled with f-strings from helper fragments (current_scan_presence_condition(),
-- nic_derived_presence_condition(), get_device_conditions(), NULL_EQUIVALENTS_SQL) in server/scan, server/db and
-- server/models. Reconstructed by hand from the pinned source: the helpers were re-typed to render one instantiation
-- each (default settings; scan time inlined as '2026-09-21 14:13:20' as timeNowUTC() would). ? binds are numbered ?N.
-- Statements that read date('now', ...) for a reporting window are pinned to the data's "now" and marked @modified.

-- @id netalertx.scan.print_scan_stats
-- @src server/scan/device_handling.py:586-612
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,dynamic,analytics,cpu-evidence
-- @note Every scan cycle: diagnostic counts with 7 scalar subqueries (two over DevicesView, whose CTE runs a per-device EXISTS over Events) beside a GROUP BY over CurrentScan. Part of the always-on per-cycle load in https://github.com/netalertx/NetAlertX/issues/769, https://github.com/netalertx/NetAlertX/issues/1555 and https://github.com/netalertx/NetAlertX/issues/1144.
SELECT (SELECT COUNT(*)
FROM CurrentScan) AS devices_detected, (SELECT COUNT(*)
FROM CurrentScan
WHERE NOT EXISTS (SELECT 1
FROM Devices
WHERE devMac = scanMac)) AS new_devices, (SELECT COUNT(*)
FROM DevicesView
WHERE devAlertDown != 0 AND devIsSleeping = 0 AND NOT EXISTS (SELECT 1
FROM CurrentScan
WHERE scanMac = devMac)) AS down_alerts, (SELECT COUNT(*)
FROM DevicesView
WHERE devAlertDown != 0 AND devCanSleep = 0 AND devPresentLastScan = 1 AND NOT EXISTS (SELECT 1
FROM CurrentScan
WHERE scanMac = devMac) ) AS new_down_alerts, (SELECT COUNT(*)
FROM Devices
WHERE devPresentLastScan = 0) AS new_connections, (SELECT COUNT(*)
FROM Devices
WHERE devPresentLastScan = 1 AND NOT EXISTS (SELECT 1
FROM CurrentScan
WHERE devMac = scanMac)) AS disconnections, (SELECT COUNT(*)
FROM Devices, CurrentScan
WHERE devMac = scanMac AND scanLastIP IS NOT NULL AND scanLastIP NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND scanLastIP <> COALESCE(devPrimaryIPv4, '') AND scanLastIP <> COALESCE(devPrimaryIPv6, '') AND scanLastIP <> COALESCE(devLastIP, '') ) AS ip_changes, scanSourcePlugin, COUNT(*) AS scan_method_count
FROM CurrentScan
GROUP BY scanSourcePlugin;

-- @id netalertx.scan.events_device_down
-- @src server/scan/session_events.py:243-254
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,dynamic,batch,cpu-evidence
-- @note Every scan cycle, insert_events() 1a: INSERT OR IGNORE 'Device Down' rows for alerting devices that vanished, selected from DevicesView with the CurrentScan presence EXISTS OR'd with the nested NIC-derived presence EXISTS. Per-cycle load from https://github.com/netalertx/NetAlertX/issues/769/https://github.com/netalertx/NetAlertX/issues/1555.
INSERT OR IGNORE INTO Events (eveMac, eveIp, eveDateTime, eveEventType, eveAdditionalInfo, evePendingAlertEmail) SELECT devMac, devLastIP, '2026-09-21 14:13:20', 'Device Down', '', 1
FROM DevicesView
WHERE devAlertDown != 0 AND devCanSleep = 0 AND devPresentLastScan = 1 AND LOWER(COALESCE(devForceStatus, '')) != 'online' AND NOT (EXISTS ( SELECT 1
FROM CurrentScan AS presence_scan
WHERE presence_scan.scanMac = devMac AND presence_scan.scanPresence = 1 ) OR EXISTS ( SELECT 1
FROM Devices AS nic_presence_parent
WHERE nic_presence_parent.devMac = DevicesView.devMac AND ( ( IFNULL(CAST(nic_presence_parent.devReqNicsOnline AS TEXT), '') = '1' AND EXISTS (SELECT 1
FROM Devices AS any_nic
WHERE any_nic.devParentMAC = nic_presence_parent.devMac AND any_nic.devParentRelType = 'nic') AND NOT EXISTS ( SELECT 1
FROM Devices AS nic
WHERE nic.devParentMAC = nic_presence_parent.devMac AND nic.devParentRelType = 'nic' AND NOT EXISTS ( SELECT 1
FROM CurrentScan AS presence_scan
WHERE presence_scan.scanMac = nic.devMac AND presence_scan.scanPresence = 1 ) ) ) OR ( IFNULL(CAST(nic_presence_parent.devReqNicsOnline AS TEXT), '') != '1' AND EXISTS ( SELECT 1
FROM Devices AS nic
WHERE nic.devParentMAC = nic_presence_parent.devMac AND nic.devParentRelType = 'nic' AND EXISTS ( SELECT 1
FROM CurrentScan AS presence_scan
WHERE presence_scan.scanMac = nic.devMac AND presence_scan.scanPresence = 1 ) ) ) ) ));

-- @id netalertx.scan.events_new_connections
-- @src server/scan/session_events.py:277-317
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,dynamic,batch,cpu-evidence
-- @note Every scan cycle, insert_events() 2: new connections. LEFT JOIN LatestEventsPerMAC, a view that ranks every Events row with ROW_NUMBER() OVER (PARTITION BY eveMac ORDER BY eveDateTime DESC) and joins Devices and CurrentScan, so the whole 90-day event table is windowed on every cycle (https://github.com/netalertx/NetAlertX/issues/769: constant high CPU with a 1.7 GB db).
INSERT OR IGNORE INTO Events (eveMac, eveIp, eveDateTime, eveEventType, eveAdditionalInfo, evePendingAlertEmail) SELECT present_agg.scanMac, present_agg.scanLastIP, '2026-09-21 14:13:20', CASE WHEN last_event.eveEventType = 'Device Down' AND last_event.evePendingAlertEmail = 0 THEN 'Down Reconnected' ELSE 'Connected' END, '', CASE WHEN quiet_agg.scanQuiet = 1 THEN 0 ELSE 1 END
FROM ( SELECT scanMac, MIN(scanLastIP) AS scanLastIP
FROM CurrentScan
WHERE scanPresence = 1
GROUP BY scanMac ) present_agg
JOIN ( SELECT scanMac, MAX(CASE WHEN scanNotificationMode = 'quiet' THEN 1 ELSE 0 END) AS scanQuiet, MAX(scanCreatesDevice) AS scanCreates
FROM CurrentScan
GROUP BY scanMac ) quiet_agg ON quiet_agg.scanMac = present_agg.scanMac LEFT
JOIN LatestEventsPerMAC AS last_event ON present_agg.scanMac = last_event.eveMac
WHERE (last_event.devPresentLastScan = 0 OR last_event.eveMac IS NULL) AND ( quiet_agg.scanCreates = 1 OR EXISTS (SELECT 1
FROM Devices
WHERE devMac = present_agg.scanMac) );

-- @id netalertx.scan.events_disconnections
-- @src server/scan/session_events.py:356-367
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,dynamic,batch
-- @note Every scan cycle, insert_events() 3: 'Disconnected' events for non-alerting devices no longer present (CurrentScan EXISTS OR NIC-derived presence).
INSERT OR IGNORE INTO Events (eveMac, eveIp, eveDateTime, eveEventType, eveAdditionalInfo, evePendingAlertEmail) SELECT devMac, devLastIP, '2026-09-21 14:13:20', 'Disconnected', '', devAlertEvents
FROM Devices
WHERE devAlertDown = 0 AND devPresentLastScan = 1 AND LOWER(COALESCE(devForceStatus, '')) != 'online' AND NOT (EXISTS ( SELECT 1
FROM CurrentScan AS presence_scan
WHERE presence_scan.scanMac = devMac AND presence_scan.scanPresence = 1 ) OR EXISTS ( SELECT 1
FROM Devices AS nic_presence_parent
WHERE nic_presence_parent.devMac = Devices.devMac AND ( ( IFNULL(CAST(nic_presence_parent.devReqNicsOnline AS TEXT), '') = '1' AND EXISTS (SELECT 1
FROM Devices AS any_nic
WHERE any_nic.devParentMAC = nic_presence_parent.devMac AND any_nic.devParentRelType = 'nic') AND NOT EXISTS ( SELECT 1
FROM Devices AS nic
WHERE nic.devParentMAC = nic_presence_parent.devMac AND nic.devParentRelType = 'nic' AND NOT EXISTS ( SELECT 1
FROM CurrentScan AS presence_scan
WHERE presence_scan.scanMac = nic.devMac AND presence_scan.scanPresence = 1 ) ) ) OR ( IFNULL(CAST(nic_presence_parent.devReqNicsOnline AS TEXT), '') != '1' AND EXISTS ( SELECT 1
FROM Devices AS nic
WHERE nic.devParentMAC = nic_presence_parent.devMac AND nic.devParentRelType = 'nic' AND EXISTS ( SELECT 1
FROM CurrentScan AS presence_scan
WHERE presence_scan.scanMac = nic.devMac AND presence_scan.scanPresence = 1 ) ) ) ) ));

-- @id netalertx.scan.events_ip_changes
-- @src server/scan/session_events.py:370-435
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,dynamic,batch
-- @note Every scan cycle, insert_events() 4: IP Changed events via a 4-CTE pipeline (DISTINCT present addresses, quiet flags, addresses unknown to the device, GROUP_CONCAT per MAC). Instantiated with all_plugins=None, so the Plugins_Objects known-address NOT EXISTS is omitted.
INSERT OR IGNORE INTO Events (eveMac, eveIp, eveDateTime, eveEventType, eveAdditionalInfo, evePendingAlertEmail) WITH present_addrs AS ( SELECT DISTINCT scanMac, scanLastIP
FROM CurrentScan
WHERE scanPresence = 1 AND scanLastIP IS NOT NULL AND scanLastIP NOT IN ('','null','(unknown)','(Unknown)','(name not found)') ), quiet_agg AS ( SELECT scanMac, MAX(CASE WHEN scanNotificationMode = 'quiet' THEN 1 ELSE 0 END) AS scanQuiet
FROM CurrentScan
GROUP BY scanMac ), new_addrs AS ( SELECT present_addrs.scanMac, present_addrs.scanLastIP
FROM present_addrs
JOIN Devices ON Devices.devMac = present_addrs.scanMac
WHERE present_addrs.scanLastIP <> COALESCE(Devices.devPrimaryIPv4, '') AND present_addrs.scanLastIP <> COALESCE(Devices.devPrimaryIPv6, '') AND present_addrs.scanLastIP <> COALESCE(Devices.devLastIP, '') ), new_addrs_agg AS ( SELECT scanMac, MIN(scanLastIP) AS firstNewIP, GROUP_CONCAT(scanLastIP, ', ') AS allNewIPs
FROM new_addrs
GROUP BY scanMac ) SELECT new_addrs_agg.scanMac, new_addrs_agg.firstNewIP, '2026-09-21 14:13:20', 'IP Changed', 'Previous IP: ' || Devices.devLastIP || ' | New IP(s): ' || new_addrs_agg.allNewIPs, CASE WHEN quiet_agg.scanQuiet = 1 THEN 0 ELSE Devices.devAlertEvents END
FROM new_addrs_agg
JOIN Devices ON Devices.devMac = new_addrs_agg.scanMac
JOIN quiet_agg ON quiet_agg.scanMac = new_addrs_agg.scanMac;

-- @id netalertx.scan.presence_mark_absent
-- @src server/scan/device_handling.py:218-222
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,dynamic
-- @note Every scan cycle: UPDATE Devices SET devPresentLastScan = 0 for every device without a presence-asserting CurrentScan row. Each changed row fires trg_devhist_update, 41 audit INSERT ... SELECTs each reading Settings twice.
UPDATE Devices SET devPresentLastScan = 0
WHERE NOT EXISTS ( SELECT 1
FROM CurrentScan AS presence_scan
WHERE presence_scan.scanMac = devMac AND presence_scan.scanPresence = 1 );

-- @id netalertx.scan.latest_device_scan
-- @src server/scan/device_handling.py:296-302
-- @style python sqlite3, ? positional
-- @tags hotpath,dynamic
-- @note Every scan cycle, per reporting plugin: SELECT * FROM LatestDeviceScan, a view ranking CurrentScan rows with ROW_NUMBER() per (MAC, plugin) and joining Devices, filtered to one plugin.
-- @param ?1 'ARPSCAN'
SELECT *
FROM LatestDeviceScan
WHERE scanSourcePlugin = ?1;

-- @id netalertx.scan.pair_connection_events
-- @src server/scan/session_events.py:181-199
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,cpu-evidence
-- @note Every scan cycle, pair_sessions_events() step 1: for each unpaired connection event, a correlated ORDER BY ... LIMIT 1 subquery finds the next session event of the same MAC. Per-cycle load from https://github.com/netalertx/NetAlertX/issues/769.
UPDATE Events SET evePairEventRowid = (SELECT ROWID
FROM Events AS EVE2
WHERE EVE2.eveEventType IN ('New Device', 'Connected', 'Down Reconnected', 'Device Down', 'Disconnected') AND EVE2.eveMac = Events.eveMac AND EVE2.eveDateTime > Events.eveDateTime
ORDER BY EVE2.eveDateTime ASC
LIMIT 1)
WHERE eveEventType IN ('New Device', 'Connected', 'Down Reconnected') AND evePairEventRowid IS NULL;

-- @id netalertx.scan.sessions_snapshot
-- @src server/scan/session_events.py:215-226
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,batch,analytics,cpu-evidence
-- @note Every scan cycle, create_sessions_snapshot(): after DELETE FROM SESSIONS, rebuild the whole Sessions table from Convert_Events_to_Sessions, a self-join of all 90 days of Events on evePairEventRowid = RowID UNIONed (with dedup) with unpaired disconnections. Rewriting ~46k rows every 5 minutes is the steady CPU and WAL churn behind https://github.com/netalertx/NetAlertX/issues/769 and https://github.com/netalertx/NetAlertX/issues/1220.
INSERT INTO Sessions SELECT *
FROM Convert_Events_to_Sessions;

-- @id netalertx.scan.online_history_counts
-- @src server/scan/session_events.py:440-453
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,analytics
-- @note Every scan cycle, insertOnlineHistory(): COUNT and CASE sums over DevicesView (per-device flapping EXISTS included) for the presence graph.
SELECT COUNT(*) AS allDevices, COALESCE(SUM(CASE WHEN devIsArchived = 1 THEN 1 ELSE 0 END), 0) AS archivedDevices, COALESCE(SUM(CASE WHEN devPresentLastScan = 1 THEN 1 ELSE 0 END), 0) AS onlineDevices, COALESCE(SUM(CASE WHEN devPresentLastScan = 0 AND devAlertDown = 1 AND devIsSleeping = 0 THEN 1 ELSE 0 END), 0) AS downDevices
FROM DevicesView;

-- @id netalertx.api.devices_all
-- @src server/const.py:66-70; server/api.py:72-110
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,cpu-evidence
-- @note update_api() export table_devices.json (also what the GraphQL device list reads): every column of DevicesView, i.e. ~50 IFNULLs, a CASE status and a correlated EXISTS ... GROUP BY ... HAVING over Events per device. https://github.com/netalertx/NetAlertX/issues/1254: Devices page 12+ s with 9k devices; https://github.com/netalertx/NetAlertX/issues/1555 lists sql_devices_all among the idle-CPU queries.
SELECT *
FROM DevicesView;

-- @id netalertx.api.events_all
-- @src server/const.py:88; server/api.py:72-110
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,cpu-evidence
-- @note update_api() export table_events.json: the entire Events table, newest first, on every API refresh. https://github.com/netalertx/NetAlertX/issues/1555 (idle CPU) names sql_events_all; https://github.com/netalertx/NetAlertX/issues/1220 shows the PHP JSON reader exhausting 128 MB on these exports.
SELECT rowid, *
FROM Events
ORDER BY eveDateTime DESC;

-- @id netalertx.api.plugins_history_all
-- @src server/const.py:139; server/api.py:72-110
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,cpu-evidence
-- @note update_api() export table_plugins_history.json: all Plugins_History rows ordered by dateTimeChanged DESC (the index leads with plugin, so this sorts). Up to PLUGINS_KEEP_HIST per plugin; https://github.com/netalertx/NetAlertX/issues/1220.
SELECT *
FROM Plugins_History
ORDER BY dateTimeChanged DESC;

-- @id netalertx.api.plugins_stats
-- @src server/const.py:91-95
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,analytics
-- @note update_api() export: row counts per plugin over Plugins_Objects, Plugins_Events and Plugins_History, UNION ALL of three GROUP BYs.
SELECT 'objects' AS tableName, plugin, COUNT(*) AS cnt
FROM Plugins_Objects
GROUP BY plugin
UNION ALL SELECT 'events', plugin, COUNT(*)
FROM Plugins_Events
GROUP BY plugin
UNION ALL SELECT 'history', plugin, COUNT(*)
FROM Plugins_History
GROUP BY plugin;

-- @id netalertx.api.devices_tiles
-- @src server/db/db_helper.py:70-120
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,dynamic,analytics
-- @note update_api() export table_devices_tiles.json (dashboard tiles): one pass over DevicesView cross-joined with the UI_MY_DEVICES setting, nine conditional-aggregate SUM(CASE ...) columns including instr() tests on the setting text.
WITH Statuses AS ( SELECT setValue
FROM Settings
WHERE setKey = 'UI_MY_DEVICES' ) SELECT COALESCE(SUM(CASE WHEN devPresentLastScan=1 THEN 1 ELSE 0 END), 0) AS "connected", COALESCE(SUM(CASE WHEN devIsArchived=0 AND devPresentLastScan=0 THEN 1 ELSE 0 END), 0) AS "offline", COALESCE(SUM(CASE WHEN devIsArchived=0 AND devAlertDown != 0 AND devPresentLastScan=0 AND devIsSleeping=0 THEN 1 ELSE 0 END), 0) AS "down", COALESCE(SUM(CASE WHEN devIsArchived=0 AND devIsNew=1 THEN 1 ELSE 0 END), 0) AS "new", COALESCE(SUM(CASE WHEN devIsArchived=1 THEN 1 ELSE 0 END), 0) AS "archived", COALESCE(SUM(CASE WHEN devIsArchived=0 AND devFavorite=1 THEN 1 ELSE 0 END), 0) AS "favorites", COALESCE(SUM(CASE WHEN devIsArchived=0 THEN 1 ELSE 0 END), 0) AS "all", COUNT(*) AS "all_devices", COALESCE(SUM(CASE WHEN (instr(Statuses.setValue, 'online') > 0 AND devPresentLastScan=1) OR (instr(Statuses.setValue, 'offline') > 0 AND devIsArchived=0 AND devPresentLastScan=0) OR (instr(Statuses.setValue, 'down') > 0 AND devIsArchived=0 AND devAlertDown != 0 AND devPresentLastScan=0 AND devIsSleeping=0) OR (instr(Statuses.setValue, 'new') > 0 AND devIsArchived=0 AND devIsNew=1) OR (instr(Statuses.setValue, 'archived') > 0 AND devIsArchived=1) THEN 1 ELSE 0 END), 0) AS "my_devices"
FROM DevicesView, Statuses;

-- @id netalertx.api.devices_filters
-- @src server/db/device_filter_columns.py:35-64; server/const.py:73
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,dynamic
-- @note update_api() export table_devices_filters.json: 12-way UNION (deduplicating) of DISTINCT column values for the device list filter dropdowns, one block with a LOWER()=LOWER() self-join for parent names, ORDER BY columnName.
SELECT DISTINCT 'devOwner' AS columnName, devOwner AS columnValue, devOwner AS columnLabel
FROM Devices
WHERE devOwner NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND devOwner IS NOT NULL UNION SELECT DISTINCT 'devType' AS columnName, devType AS columnValue, devType AS columnLabel
FROM Devices
WHERE devType NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND devType IS NOT NULL UNION SELECT DISTINCT 'devGroup' AS columnName, devGroup AS columnValue, devGroup AS columnLabel
FROM Devices
WHERE devGroup NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND devGroup IS NOT NULL UNION SELECT DISTINCT 'devLocation' AS columnName, devLocation AS columnValue, devLocation AS columnLabel
FROM Devices
WHERE devLocation NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND devLocation IS NOT NULL UNION SELECT DISTINCT 'devVendor' AS columnName, devVendor AS columnValue, devVendor AS columnLabel
FROM Devices
WHERE devVendor NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND devVendor IS NOT NULL UNION SELECT DISTINCT 'devSyncHubNode' AS columnName, devSyncHubNode AS columnValue, devSyncHubNode AS columnLabel
FROM Devices
WHERE devSyncHubNode NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND devSyncHubNode IS NOT NULL UNION SELECT DISTINCT 'devSite' AS columnName, devSite AS columnValue, devSite AS columnLabel
FROM Devices
WHERE devSite NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND devSite IS NOT NULL UNION SELECT DISTINCT 'devSSID' AS columnName, devSSID AS columnValue, devSSID AS columnLabel
FROM Devices
WHERE devSSID NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND devSSID IS NOT NULL UNION SELECT DISTINCT 'devSourcePlugin' AS columnName, devSourcePlugin AS columnValue, devSourcePlugin AS columnLabel
FROM Devices
WHERE devSourcePlugin NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND devSourcePlugin IS NOT NULL UNION SELECT DISTINCT 'devParentRelType' AS columnName, devParentRelType AS columnValue, devParentRelType AS columnLabel
FROM Devices
WHERE devParentRelType NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND devParentRelType IS NOT NULL UNION SELECT 'devParentMAC' AS columnName, d.devParentMAC AS columnValue, COALESCE(p.devName, d.devParentMAC) AS columnLabel
FROM Devices d LEFT
JOIN Devices p ON LOWER(p.devMac) = LOWER(d.devParentMAC)
WHERE d.devParentMAC NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND d.devParentMAC IS NOT NULL
GROUP BY d.devParentMAC COLLATE NOCASE UNION SELECT DISTINCT 'devVlan' AS columnName, devVlan AS columnValue, devVlan AS columnLabel
FROM Devices
WHERE devVlan NOT IN ('','null','(unknown)','(Unknown)','(name not found)') AND devVlan IS NOT NULL
ORDER BY columnName;

-- @id netalertx.api.devices_stats
-- @src server/const.py:75-86
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hot-small
-- @note Devices header counters: the latest Online_History row plus two COUNT subqueries over Devices.
SELECT onlineDevices as online, downDevices as down, allDevices as 'all', archivedDevices as archived, (SELECT COUNT(*)
FROM Devices a
WHERE devIsNew = 1) as new, (SELECT COUNT(*)
FROM Devices a
WHERE devName IN ('','null','(unknown)','(Unknown)','(name not found)') OR devName IS NULL) as unknown
FROM Online_History
ORDER BY scanDate DESC
LIMIT 1;

-- @id netalertx.api.resource_history_month
-- @src server/const.py:122-138
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,analytics
-- @note update_api() export resource_history_month (System Info -> Performance): 30 days of per-tick rows rolled up into hourly buckets with strftime GROUP BY, AVG/SUM/MAX.
-- @modified datetime('now', '-30 day') pinned to the data's now (2026-09-21 14:13:20 UTC) so the window keeps matching the synthetic data
SELECT strftime('%Y-%m-%d %H:00:00', resDateTime) AS bucket, AVG(resCpuPercent) AS resCpuPercent, AVG(resRssMb) AS resRssMb, SUM(resIoReadBytes) AS resIoReadBytes, SUM(resIoWriteBytes) AS resIoWriteBytes, AVG(resScanDurationMs) AS resScanDurationMs, MAX(resTickFailed) AS resTickFailed
FROM Resource_History
WHERE resDateTime >= datetime('2026-09-21 14:13:20', '-30 day')
GROUP BY bucket
ORDER BY bucket;

-- @id netalertx.ui.device_details
-- @src server/models/device_instance.py:586-626
-- @style python sqlite3, f-string with the period expression inlined; ? positional for the MAC
-- @tags hotpath,dynamic,analytics,cpu-evidence
-- @note Device details page: DevicesView filtered by LOWER(devMac) = LOWER(?) OR CAST(rowid AS TEXT) = ? (the OR defeats the index, so the whole view is computed), plus four correlated COUNT/SUM subqueries over Sessions and Events for the month, including julianday() presence hours. https://github.com/netalertx/NetAlertX/issues/1252: 10 s of spinner and a CPU spike per device view with 6k devices.
-- @modified get_date_from_period('1 month') renders date('now', '-30 day'); pinned to the data's now (2026-09-21 14:13:20 UTC), and timeNowUTC() inlined as the same instant
-- @param ?1 '1c:07:0d:00:01:1f'
-- @param ?2 '1c:07:0d:00:01:1f'
SELECT d.*, LOWER(d.devMac) AS devMac, LOWER(d.devParentMAC) AS devParentMAC, (SELECT COUNT(*)
FROM Sessions
WHERE LOWER(sesMac) = LOWER(d.devMac) AND ( sesDateTimeConnection >= date('2026-09-21 14:13:20', '-30 day') OR sesDateTimeDisconnection >= date('2026-09-21 14:13:20', '-30 day') OR sesStillConnected = 1 )) AS devSessions, (SELECT COUNT(*)
FROM Events
WHERE LOWER(eveMac) = LOWER(d.devMac) AND eveDateTime >= date('2026-09-21 14:13:20', '-30 day') AND eveEventType NOT IN ('Connected','Disconnected')) AS devEvents, (SELECT COUNT(*)
FROM Events
WHERE LOWER(eveMac) = LOWER(d.devMac) AND eveDateTime >= date('2026-09-21 14:13:20', '-30 day') AND eveEventType = 'Device Down') AS devDownAlerts, (SELECT CAST(MAX(0, SUM( julianday(IFNULL(sesDateTimeDisconnection,'2026-09-21 14:13:20')) - julianday(CASE WHEN sesDateTimeConnection < date('2026-09-21 14:13:20', '-30 day') THEN date('2026-09-21 14:13:20', '-30 day') ELSE sesDateTimeConnection END) ) * 24) AS INT)
FROM Sessions
WHERE LOWER(sesMac) = LOWER(d.devMac) AND sesDateTimeConnection IS NOT NULL AND (sesDateTimeDisconnection IS NOT NULL OR sesStillConnected = 1) AND (sesDateTimeConnection >= date('2026-09-21 14:13:20', '-30 day') OR sesDateTimeDisconnection >= date('2026-09-21 14:13:20', '-30 day') OR sesStillConnected = 1) ) AS devPresenceHours
FROM DevicesView d
WHERE LOWER(d.devMac) = LOWER(?1) OR CAST(d.rowid AS TEXT) = ?2;

-- @id netalertx.ui.device_totals
-- @src server/models/device_instance.py:432-462
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,dynamic,analytics,cpu-evidence
-- @note Device totals (presence page, /devices/totals, homepage widgets): six independent scalar COUNT(*) subqueries over DevicesView, so the view and its per-device Events EXISTS are evaluated six times. Dashboard slowness in https://github.com/netalertx/NetAlertX/issues/1254.
SELECT (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0) AS "all", (SELECT COUNT(*)
FROM DevicesView
WHERE devPresentLastScan=1) AS "connected", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devFavorite=1) AS "favorites", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devIsNew=1) AS "new", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devAlertDown != 0 AND devPresentLastScan=0 AND devIsSleeping=0) AS "down", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=1) AS "archived";

-- @id netalertx.ui.named_totals
-- @src server/models/device_instance.py:464-484
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags dynamic,analytics
-- @note /devices/totals/named: one scalar COUNT(*) subquery over DevicesView per status condition (18), including the devFlapping and network-type IN-list conditions.
SELECT (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0) AS "all", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0) AS "my", (SELECT COUNT(*)
FROM DevicesView
WHERE devPresentLastScan=1) AS "connected", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devFavorite=1) AS "favorites", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devIsNew=1) AS "new", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devIsSleeping=1) AS "sleeping", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devAlertDown != 0 AND devPresentLastScan=0 AND devIsSleeping=0) AS "down", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devPresentLastScan=0) AS "offline", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=1) AS "archived", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devType IN ('AP','Access Point','Gateway','Firewall','Hypervisor','Powerline','Switch','WLAN','PLC','Router','USB LAN Adapter','USB WIFI Adapter','internet')) AS "network_devices", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devType IN ('AP','Access Point','Gateway','Firewall','Hypervisor','Powerline','Switch','WLAN','PLC','Router','USB LAN Adapter','USB WIFI Adapter','internet') AND devPresentLastScan=0) AS "network_devices_down", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devName IN ('','null','(unknown)','(Unknown)','(name not found)')) AS "unknown", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devName NOT IN ('','null','(unknown)','(Unknown)','(name not found)')) AS "known", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devFavorite=1 AND devPresentLastScan=0) AS "favorites_offline", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devIsNew=1 AND devPresentLastScan=1) AS "new_online", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devFlapping=1) AS "unstable_devices", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devFavorite=1 AND devFlapping=1) AS "unstable_favorites", (SELECT COUNT(*)
FROM DevicesView
WHERE devIsArchived=0 AND devType IN ('AP','Access Point','Gateway','Firewall','Hypervisor','Powerline','Switch','WLAN','PLC','Router','USB LAN Adapter','USB WIFI Adapter','internet') AND devFlapping=1) AS "unstable_network_devices";

-- @id netalertx.ui.sessions_calendar
-- @src server/api_server/sessions_endpoint.py:107-152
-- @style python sqlite3, ? positional
-- @tags hotpath,dynamic,analytics
-- @note Presence calendar for all devices over a week: sessions overlapping the range or still connected, each with two correlated MIN/MAX subqueries over Sessions to repair '<missing event>' ends; MAC filter passed as NULL.
-- @param ?1 '2026-09-14'
-- @param ?2 '2026-09-22'
-- @param ?3 '2026-09-14'
-- @param ?4 '2026-09-22'
-- @param ?5 '2026-09-14'
-- @param ?6 '2026-09-22'
-- @param ?7 '2026-09-14'
-- @param ?8 '2026-09-22'
-- @param ?9 NULL
-- @param ?10 NULL
SELECT SES1.sesMac, SES1.sesEventTypeConnection, SES1.sesDateTimeConnection, SES1.sesEventTypeDisconnection, SES1.sesDateTimeDisconnection, SES1.sesIp, SES1.sesAdditionalInfo, SES1.sesStillConnected, CASE WHEN SES1.sesEventTypeConnection = '<missing event>' THEN IFNULL( ( SELECT MAX(SES2.sesDateTimeDisconnection)
FROM Sessions AS SES2
WHERE SES2.sesMac = SES1.sesMac AND SES2.sesDateTimeDisconnection < SES1.sesDateTimeDisconnection AND SES2.sesDateTimeDisconnection BETWEEN Date(?1) AND Date(?2) ), DATETIME(SES1.sesDateTimeDisconnection, '-1 hour') ) ELSE SES1.sesDateTimeConnection END AS sesDateTimeConnectionCorrected, CASE WHEN SES1.sesEventTypeDisconnection = '<missing event>' THEN ( SELECT MIN(SES2.sesDateTimeConnection)
FROM Sessions AS SES2
WHERE SES2.sesMac = SES1.sesMac AND SES2.sesDateTimeConnection > SES1.sesDateTimeConnection AND SES2.sesDateTimeConnection BETWEEN Date(?3) AND Date(?4) ) ELSE SES1.sesDateTimeDisconnection END AS sesDateTimeDisconnectionCorrected
FROM Sessions AS SES1
WHERE ( (SES1.sesDateTimeConnection BETWEEN Date(?5) AND Date(?6)) OR (SES1.sesDateTimeDisconnection BETWEEN Date(?7) AND Date(?8)) OR SES1.sesStillConnected = 1 ) AND (?9 IS NULL OR SES1.sesMac = ?10);

-- @id netalertx.ui.sessions_month
-- @src server/api_server/sessions_endpoint.py:335-364
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,dynamic
-- @note Events page, Sessions tab (1 month): Sessions_Devices (Sessions LEFT JOIN Devices) filtered by an OR of connection/disconnection dates and still-connected; the app formats, sorts, searches and pages in Python.
-- @modified get_date_from_period('1 month') renders date('now', '-30 day'); pinned to the data's now (2026-09-21 14:13:20 UTC), and timeNowUTC() inlined as the same instant
SELECT IFNULL(sesDateTimeConnection, sesDateTimeDisconnection) AS sesDateTimeOrder, devName, devOwner, NULL, NULL, sesDateTimeConnection, sesDateTimeDisconnection, NULL, NULL, sesIp, NULL, sesAdditionalInfo, sesStillConnected, devMac, 0 AS sesPendingAlertEmail
FROM Sessions_Devices
WHERE ( sesDateTimeConnection >= date('2026-09-21 14:13:20', '-30 day') OR sesDateTimeDisconnection >= date('2026-09-21 14:13:20', '-30 day') OR sesStillConnected = 1 );

-- @id netalertx.ui.events_down_week
-- @src server/api_server/sessions_endpoint.py:314-332,382
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags hotpath,dynamic
-- @note Events page, Down alerts tab (7 days): Events_Devices (Events LEFT JOIN Devices) for a date range plus the app's double-quoted string literal "Device Down" (accepted by SQLite's DQS fallback).
-- @modified get_date_from_period('7 days') renders date('now', '-7 day'); pinned to the data's now (2026-09-21 14:13:20 UTC)
SELECT eveDateTime AS eveDateTimeOrder, devName, devOwner, eveDateTime, eveEventType, NULL, NULL, NULL, NULL, eveIp, NULL, eveAdditionalInfo, NULL, devMac, evePendingAlertEmail
FROM Events_Devices
WHERE eveDateTime >= date('2026-09-21 14:13:20', '-7 day') AND eveEventType = "Device Down";

-- @id netalertx.ui.device_children
-- @src server/models/device_instance.py:643-646
-- @style python sqlite3, ? positional
-- @tags hot-small
-- @note Device details: the device's children through the LOWER(devParentMAC) expression index.
-- @param ?1 '1c:77:dd:00:11:0f'
SELECT *
FROM Devices
WHERE LOWER(devParentMAC) = LOWER(?1)
ORDER BY devPresentLastScan DESC;

-- @id netalertx.ui.device_by_mac
-- @src server/models/device_instance.py:102-105
-- @style python sqlite3, ? positional
-- @tags hot-small
-- @note Point lookup of one device by primary key (COLLATE NOCASE).
-- @param ?1 'b8:0e:1a:00:02:3e'
SELECT *
FROM Devices
WHERE devMac = ?1;

-- @id netalertx.cleanup.plugins_history_trim
-- @src server/plugins/db_cleanup/script.py:131-142
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags dynamic,batch,cpu-evidence
-- @note DBCLNP: keep the newest PLUGINS_KEEP_HIST (10000) rows per plugin, NOT IN over a ROW_NUMBER() OVER (PARTITION BY plugin ORDER BY dateTimeChanged DESC) ranking of the whole table. https://github.com/netalertx/NetAlertX/issues/769: this step took ~15 s before the plugin hit its 30 s timeout on a 1.7 GB database.
DELETE
FROM Plugins_History
WHERE "Index" NOT IN ( SELECT "Index"
FROM ( SELECT "Index", ROW_NUMBER() OVER(PARTITION BY plugin
ORDER BY dateTimeChanged DESC) AS row_num
FROM Plugins_History ) AS ranked_objects
WHERE row_num <= 10000 );

-- @id netalertx.cleanup.plugins_objects_dedupe
-- @src server/plugins/db_cleanup/script.py:215-226
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags batch,cpu-evidence
-- @note DBCLNP: delete duplicate Plugins_Objects rows with a correlated MIN(rowid) subquery over four columns per row. https://github.com/netalertx/NetAlertX/issues/769: the plugin was killed by its timeout right after logging this step.
DELETE
FROM Plugins_Objects
WHERE rowid > ( SELECT MIN(rowid)
FROM Plugins_Objects p2
WHERE Plugins_Objects.plugin = p2.plugin AND Plugins_Objects.objectPrimaryId = p2.objectPrimaryId AND Plugins_Objects.objectSecondaryId = p2.objectSecondaryId AND Plugins_Objects.userData = p2.userData );

-- @id netalertx.cleanup.events_retention
-- @src server/plugins/db_cleanup/script.py:101
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags dynamic,batch
-- @note DBCLNP: delete Events older than DAYS_TO_KEEP_EVENTS (here 60 days, against data spanning 90), range on the eveDateTime index, maintaining 12 Events indexes per deleted row.
-- @modified date('now', '-60 day') pinned to the data's now (2026-09-21 14:13:20 UTC); 60 instead of the default 90 so the delete has rows to remove
DELETE
FROM Events
WHERE eveDateTime <= date('2026-09-21 14:13:20', '-60 day');

-- @id netalertx.cleanup.appevents_trim
-- @src server/plugins/db_cleanup/script.py:161-169
-- @style python sqlite3, SQL built with f-strings (constants and helper fragments inlined); no binds
-- @tags dynamic,batch
-- @note DBCLNP: trim AppEvents to WORKFLOWS_AppEvents_hist (5000) via a scalar ORDER BY dateTimeCreated DESC LIMIT 1 OFFSET 5000 subquery (no index on dateTimeCreated).
DELETE
FROM AppEvents
WHERE "Index" < ( SELECT "Index"
FROM AppEvents
ORDER BY dateTimeCreated DESC
LIMIT 1 OFFSET 5000 );
