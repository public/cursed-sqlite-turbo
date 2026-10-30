-- NetAlertX database (netalertx/NetAlertX @ 6f3cb9bd43855596da3e8c6185490abd5784f1dd, GPL-3.0).
-- Only the CREATE statements the queries need, as DB.initDB() leaves them: server/db/schema/app.sql tables, the two
-- Devices columns ensure_column() adds on top (devReqNicsOnline, devCanSleep), every index ensure_Indexes() (re)creates,
-- the views from ensure_views(), the MAC-lowercasing / dangling-parent triggers and the DevicesHistory audit triggers
-- (server/db/db_history.py, generated with the default 41 audited fields; DEV_HIST_DAYS defaults to 1, so they fire).
-- DevicesView's devIsSleeping/devFlapping read datetime('now'); with the data anchored in the past both are 0, which
-- keeps results stable, but the per-device EXISTS over Events still runs. Fetch originals with tools/fetch.sh netalertx.

CREATE TABLE Events (eveMac STRING (50) NOT NULL COLLATE NOCASE, eveIp STRING (50) NOT NULL COLLATE NOCASE, eveDateTime DATETIME NOT NULL, eveEventType STRING (30) NOT NULL COLLATE NOCASE, eveAdditionalInfo STRING (250) DEFAULT (''), evePendingAlertEmail BOOLEAN NOT NULL CHECK (evePendingAlertEmail IN (0, 1)) DEFAULT (1), evePairEventRowid INTEGER);
CREATE TABLE Sessions (sesMac STRING (50) COLLATE NOCASE, sesIp STRING (50) COLLATE NOCASE, sesEventTypeConnection STRING (30) COLLATE NOCASE, sesDateTimeConnection DATETIME, sesEventTypeDisconnection STRING (30) COLLATE NOCASE, sesDateTimeDisconnection DATETIME, sesStillConnected BOOLEAN, sesAdditionalInfo STRING (250));
CREATE TABLE IF NOT EXISTS Online_History (
            "index"     INTEGER,
            scanDate TEXT,
            onlineDevices    INTEGER,
            downDevices      INTEGER,
            allDevices       INTEGER,
            archivedDevices INTEGER,
            offlineDevices INTEGER,
            PRIMARY KEY("index" AUTOINCREMENT)
          );
CREATE TABLE IF NOT EXISTS Resource_History (
            "index"           INTEGER PRIMARY KEY AUTOINCREMENT,
            resDateTime       TEXT NOT NULL,
            resCpuPercent     REAL,
            resRssMb          REAL,
            resIoReadBytes    INTEGER,
            resIoWriteBytes   INTEGER,
            resScanDurationMs INTEGER,
            resTickFailed     INTEGER NOT NULL DEFAULT 0
          );
CREATE INDEX IF NOT EXISTS idx_reshist_datetime ON Resource_History(resDateTime);
CREATE TABLE Devices (
              devMac STRING (50) PRIMARY KEY NOT NULL COLLATE NOCASE,
              devName STRING (50) NOT NULL DEFAULT "(unknown)",
              devOwner STRING (30) DEFAULT "(unknown)" NOT NULL,
              devType STRING (30),
              devVendor STRING (250),
              devFavorite BOOLEAN CHECK (devFavorite IN (0, 1)) DEFAULT (0) NOT NULL,
              devGroup STRING (10),
              devComments TEXT,
              devFirstConnection DATETIME NOT NULL,
              devLastConnection DATETIME NOT NULL,
              devLastIP STRING (50) NOT NULL COLLATE NOCASE,
              devPrimaryIPv4 TEXT,
              devPrimaryIPv6 TEXT,
              devVlan TEXT,
              devForceStatus TEXT,
              devStaticIP BOOLEAN DEFAULT (0) NOT NULL CHECK (devStaticIP IN (0, 1)),
              devScan INTEGER DEFAULT (1) NOT NULL,
              devLogEvents BOOLEAN NOT NULL DEFAULT (1) CHECK (devLogEvents IN (0, 1)),
              devAlertEvents BOOLEAN NOT NULL DEFAULT (1) CHECK (devAlertEvents IN (0, 1)),
              devAlertDown BOOLEAN NOT NULL DEFAULT (0) CHECK (devAlertDown IN (0, 1)),
              devSkipRepeated INTEGER DEFAULT 0 NOT NULL,
              devLastNotification DATETIME,
              devPresentLastScan BOOLEAN NOT NULL DEFAULT (0) CHECK (devPresentLastScan IN (0, 1)),
              devIsNew BOOLEAN NOT NULL DEFAULT (1) CHECK (devIsNew IN (0, 1)),
              devLocation STRING (250) COLLATE NOCASE,
              devIsArchived BOOLEAN NOT NULL DEFAULT (0) CHECK (devIsArchived IN (0, 1)),
              devParentMAC TEXT,
              devParentPort INTEGER,
              devParentRelType TEXT,
              devIcon TEXT,
              devGUID TEXT,
              devSite TEXT,
              devSSID TEXT,
              devSyncHubNode TEXT,
              devSourcePlugin TEXT,
              devFQDN TEXT,
              devMacSource TEXT,
              devNameSource TEXT,
              devFQDNSource TEXT,
              devLastIPSource TEXT,
              devVendorSource TEXT,
              devSSIDSource TEXT,
              devParentMACSource TEXT,
              devParentPortSource TEXT,
              devParentRelTypeSource TEXT,
              devVlanSource TEXT,
              devCustomProps TEXT);
ALTER TABLE Devices ADD COLUMN devReqNicsOnline INTEGER;
ALTER TABLE Devices ADD COLUMN devCanSleep INTEGER;
CREATE TABLE "Settings" (
            "setKey"	        TEXT,
            "setName"	        TEXT,
            "setDescription"	TEXT,
            "setType"         TEXT,
            "setOptions"      TEXT,
            "setGroup"	          TEXT,
            "setValue"	      TEXT,
            "setEvents"	        TEXT,
            "setOverriddenByEnv" INTEGER
            );
CREATE TABLE Plugins_Objects(
                                    "index"               INTEGER,
                                    plugin TEXT NOT NULL,
                                    objectPrimaryId TEXT NOT NULL,
                                    objectSecondaryId TEXT NOT NULL,
                                    dateTimeCreated TEXT NOT NULL,
                                    dateTimeChanged TEXT NOT NULL,
                                    watchedValue1 TEXT NOT NULL,
                                    watchedValue2 TEXT NOT NULL,
                                    watchedValue3 TEXT NOT NULL,
                                    watchedValue4 TEXT NOT NULL,
                                    "status" TEXT NOT NULL,
                                    extra TEXT NOT NULL,
                                    userData TEXT NOT NULL,
                                    foreignKey TEXT NOT NULL,
                                    syncHubNodeName TEXT,
                                    helpVal1 TEXT,
                                    helpVal2 TEXT,
                                    helpVal3 TEXT,
                                    helpVal4 TEXT,
                                    objectGuid TEXT,
                                    PRIMARY KEY("index" AUTOINCREMENT)
                        );
CREATE TABLE Plugins_Events(
                                    "index"               INTEGER,
                                    plugin TEXT NOT NULL,
                                    objectPrimaryId TEXT NOT NULL,
                                    objectSecondaryId TEXT NOT NULL,
                                    dateTimeCreated TEXT NOT NULL,
                                    dateTimeChanged TEXT NOT NULL,
                                    watchedValue1 TEXT NOT NULL,
                                    watchedValue2 TEXT NOT NULL,
                                    watchedValue3 TEXT NOT NULL,
                                    watchedValue4 TEXT NOT NULL,
                                    "status" TEXT NOT NULL,
                                    extra TEXT NOT NULL,
                                    userData TEXT NOT NULL,
                                    foreignKey TEXT NOT NULL,
                                    syncHubNodeName TEXT,
                                    helpVal1 TEXT,
                                    helpVal2 TEXT,
                                    helpVal3 TEXT,
                                    helpVal4 TEXT,
                                    objectGuid TEXT,
                                    PRIMARY KEY("index" AUTOINCREMENT)
                        );
CREATE TABLE Plugins_History(
                                    "index"               INTEGER,
                                    plugin TEXT NOT NULL,
                                    objectPrimaryId TEXT NOT NULL,
                                    objectSecondaryId TEXT NOT NULL,
                                    dateTimeCreated TEXT NOT NULL,
                                    dateTimeChanged TEXT NOT NULL,
                                    watchedValue1 TEXT NOT NULL,
                                    watchedValue2 TEXT NOT NULL,
                                    watchedValue3 TEXT NOT NULL,
                                    watchedValue4 TEXT NOT NULL,
                                    "status" TEXT NOT NULL,
                                    extra TEXT NOT NULL,
                                    userData TEXT NOT NULL,
                                    foreignKey TEXT NOT NULL,
                                    syncHubNodeName TEXT,
                                    helpVal1 TEXT,
                                    helpVal2 TEXT,
                                    helpVal3 TEXT,
                                    helpVal4 TEXT,
                                    objectGuid TEXT,
                                    PRIMARY KEY("index" AUTOINCREMENT)
                        );
CREATE TABLE CurrentScan (
                                scanMac STRING(50) NOT NULL COLLATE NOCASE,
                                scanLastIP STRING(50) NOT NULL COLLATE NOCASE,
                                scanVendor STRING(250),
                                scanSourcePlugin STRING(10),
                                scanName STRING(250),
                                scanLastQuery STRING(250),
                                scanLastConnection STRING(250),
                                scanSyncHubNode STRING(50),
                                scanSite STRING(250),
                                scanSSID STRING(250),
                                scanVlan STRING(250),
                                scanParentMAC STRING(250),
                                scanParentPort STRING(250),
                                scanFQDN STRING(250),
                                scanType STRING(250),
                                scanCreatesDevice BOOLEAN NOT NULL DEFAULT (1) CHECK (scanCreatesDevice IN (0, 1)),
                                scanNotificationMode STRING(10) NOT NULL DEFAULT ('normal'),
                                scanPresence BOOLEAN NOT NULL DEFAULT (1) CHECK (scanPresence IN (0, 1))
                            );
CREATE INDEX IF NOT EXISTS idx_currentscan_scanmac ON CurrentScan(scanMac);
CREATE TABLE IF NOT EXISTS AppEvents (
                "index" INTEGER PRIMARY KEY AUTOINCREMENT,
                guid TEXT UNIQUE,
                appEventProcessed BOOLEAN,
                dateTimeCreated TEXT,
                objectType TEXT,
                objectGuid TEXT,
                objectPlugin TEXT,
                objectPrimaryId TEXT,
                objectSecondaryId TEXT,
                objectForeignKey TEXT,
                objectIndex TEXT,
                objectIsNew BOOLEAN,
                objectIsArchived BOOLEAN,
                objectStatusColumn TEXT,
                objectStatus TEXT,
                appEventType TEXT,
                helper1 TEXT,
                helper2 TEXT,
                helper3 TEXT,
                extra TEXT
            );
CREATE TABLE IF NOT EXISTS DevicesHistory (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                devGUID       TEXT NOT NULL,
                timestamp     DATETIME DEFAULT CURRENT_TIMESTAMP,
                changedBy     TEXT NOT NULL,
                changedColumn TEXT NOT NULL,
                oldValue      TEXT,
                newValue      TEXT,
                FOREIGN KEY (devGUID) REFERENCES Devices(devGUID) ON DELETE CASCADE
            );
CREATE INDEX IF NOT EXISTS idx_devhist_guid_column ON DevicesHistory(devGUID, changedColumn);
CREATE INDEX IF NOT EXISTS idx_devhist_timestamp ON DevicesHistory(timestamp);

-- app.sql indexes that ensure_Indexes() leaves alone (IDX_dev_Favorite is dropped by its case-insensitive twin idx_dev_favorite)
CREATE INDEX IDX_eve_DateTime ON Events (eveDateTime);
CREATE INDEX IDX_eve_EventType ON Events (eveEventType COLLATE NOCASE);
CREATE INDEX IDX_eve_MAC ON Events (eveMac COLLATE NOCASE);
CREATE INDEX IDX_eve_PairEventRowid ON Events (evePairEventRowid);
CREATE INDEX IDX_ses_EventTypeDisconnection ON Sessions (sesEventTypeDisconnection COLLATE NOCASE);
CREATE INDEX IDX_ses_EventTypeConnection ON Sessions (sesEventTypeConnection COLLATE NOCASE);
CREATE INDEX IDX_ses_DateTimeDisconnection ON Sessions (sesDateTimeDisconnection);
CREATE INDEX IDX_ses_MAC ON Sessions (sesMac COLLATE NOCASE);
CREATE INDEX IDX_ses_DateTimeConnection ON Sessions (sesDateTimeConnection);
CREATE INDEX IDX_dev_PresentLastScan ON Devices (devPresentLastScan);
CREATE INDEX IDX_dev_FirstConnection ON Devices (devFirstConnection);
CREATE INDEX IDX_dev_AlertDeviceDown ON Devices (devAlertDown);
CREATE INDEX IDX_dev_StaticIP ON Devices (devStaticIP);
CREATE INDEX IDX_dev_ScanCycle ON Devices (devScan);
CREATE INDEX IDX_dev_LastIP ON Devices (devLastIP);
CREATE INDEX IDX_dev_NewDevice ON Devices (devIsNew);
CREATE INDEX IDX_dev_Archived ON Devices (devIsArchived);
-- server/db/db_upgrade.py ensure_Indexes()
CREATE INDEX idx_ses_mac_date ON Sessions(sesMac, sesDateTimeConnection, sesDateTimeDisconnection, sesStillConnected);
CREATE INDEX idx_eve_mac_date_type ON Events(eveMac, eveDateTime, eveEventType);
CREATE INDEX idx_eve_alert_pending ON Events(evePendingAlertEmail);
CREATE INDEX idx_eve_mac_datetime_desc ON Events(eveMac, eveDateTime DESC);
CREATE INDEX idx_eve_pairevent ON Events(evePairEventRowid);
CREATE INDEX idx_eve_type_date ON Events(eveEventType, eveDateTime);
CREATE UNIQUE INDEX idx_events_unique ON Events (eveMac, eveIp, eveEventType, eveDateTime);
CREATE INDEX idx_dev_mac ON Devices(devMac);
CREATE INDEX idx_dev_present ON Devices(devPresentLastScan);
CREATE INDEX idx_dev_alertdown ON Devices(devAlertDown);
CREATE INDEX idx_dev_cansleep ON Devices(devCanSleep);
CREATE INDEX idx_dev_isnew ON Devices(devIsNew);
CREATE INDEX idx_dev_isarchived ON Devices(devIsArchived);
CREATE INDEX idx_dev_favorite ON Devices(devFavorite);
CREATE INDEX idx_dev_parentmac ON Devices(devParentMAC);
CREATE INDEX idx_ses_lower_mac_date ON Sessions(LOWER(sesMac), sesDateTimeConnection, sesDateTimeDisconnection, sesStillConnected);
CREATE INDEX idx_eve_lower_mac_date_type ON Events(LOWER(eveMac), eveDateTime, eveEventType);
CREATE INDEX idx_dev_lower_mac ON Devices(LOWER(devMac));
CREATE INDEX idx_dev_lower_parentmac ON Devices(LOWER(devParentMAC));
CREATE INDEX idx_dev_guid ON Devices(devGUID);
CREATE INDEX idx_plobj_guid ON Plugins_Objects(objectGuid);
CREATE INDEX idx_dev_site ON Devices(devSite);
CREATE INDEX idx_dev_group ON Devices(devGroup);
CREATE INDEX idx_dev_owner ON Devices(devOwner);
CREATE INDEX idx_dev_type ON Devices(devType);
CREATE INDEX idx_dev_vendor ON Devices(devVendor);
CREATE INDEX idx_dev_location ON Devices(devLocation);
CREATE INDEX idx_set_key ON Settings(setKey);
CREATE INDEX idx_plugins_plugin_mac_ip ON Plugins_Objects(plugin, objectPrimaryId, objectSecondaryId);
CREATE INDEX idx_plugins_history_plugin_dt ON Plugins_History(plugin, dateTimeChanged DESC);

-- server/db/db_upgrade.py ensure_views()
CREATE VIEW Events_Devices AS
                            SELECT *
                            FROM Events
                            LEFT JOIN Devices ON eveMac = devMac;
CREATE VIEW LatestEventsPerMAC AS
                                WITH RankedEvents AS (
                                    SELECT
                                        e.*,
                                        ROW_NUMBER() OVER (PARTITION BY e.eveMac ORDER BY e.eveDateTime DESC) AS row_num
                                    FROM Events AS e
                                )
                                SELECT
                                    e.*,
                                    d.*,
                                    c.*
                                FROM RankedEvents AS e
                                LEFT JOIN Devices AS d ON e.eveMac = d.devMac
                                INNER JOIN CurrentScan AS c ON e.eveMac = c.scanMac
                                WHERE e.row_num = 1;
CREATE VIEW Sessions_Devices AS SELECT * FROM Sessions LEFT JOIN "Devices" ON sesMac = devMac;
CREATE VIEW Convert_Events_to_Sessions AS  SELECT EVE1.eveMac,
                                      EVE1.eveIp,
                                      EVE1.eveEventType AS eveEventTypeConnection,
                                      EVE1.eveDateTime AS eveDateTimeConnection,
                                      CASE WHEN EVE2.eveEventType IN ('Disconnected', 'Device Down') OR
                                                EVE2.eveEventType IS NULL THEN EVE2.eveEventType ELSE '<missing event>' END AS eveEventTypeDisconnection,
                                      CASE WHEN EVE2.eveEventType IN ('Disconnected', 'Device Down') THEN EVE2.eveDateTime ELSE NULL END AS eveDateTimeDisconnection,
                                      CASE WHEN EVE2.eveEventType IS NULL THEN 1 ELSE 0 END AS eveStillConnected,
                                      EVE1.eveAdditionalInfo
                                  FROM Events AS EVE1
                                      LEFT JOIN
                                      Events AS EVE2 ON EVE1.evePairEventRowid = EVE2.RowID
                                WHERE EVE1.eveEventType IN ('New Device', 'Connected','Down Reconnected')
                            UNION
                                SELECT eveMac,
                                      eveIp,
                                      '<missing event>' AS eveEventTypeConnection,
                                      NULL AS eveDateTimeConnection,
                                      eveEventType AS eveEventTypeDisconnection,
                                      eveDateTime AS eveDateTimeDisconnection,
                                      0 AS eveStillConnected,
                                      eveAdditionalInfo
                                  FROM Events AS EVE1
                                WHERE (eveEventType = 'Device Down' OR
                                        eveEventType = 'Disconnected') AND
                                      EVE1.evePairEventRowid IS NULL;
CREATE VIEW LatestDeviceScan AS
                        WITH RankedScans AS (
                            SELECT
                                c.*,
                                ROW_NUMBER() OVER (
                                    PARTITION BY c.scanMac, c.scanSourcePlugin
                                    ORDER BY c.scanLastConnection DESC
                                ) AS rn
                            FROM CurrentScan c
                        )
                        SELECT
                            d.*,           -- all Device fields
                            r.*            -- all CurrentScan fields
                        FROM Devices d
                        LEFT JOIN RankedScans r
                            ON d.devMac = r.scanMac
                        WHERE r.rn = 1;
-- NTFPRCS_sleep_time 30 (default), FLAP_THRESHOLD 3, FLAP_WINDOW_HOURS 1
CREATE VIEW DevicesView AS
                    -- CTE computes devIsSleeping and devFlapping so devStatus can
                    -- reference them without duplicating the sub-expressions.
                    WITH base AS (
                        SELECT
                        rowid,
                        LOWER(IFNULL(devMac, '')) AS devMac,
                        IFNULL(devName, '') AS devName,
                        IFNULL(devOwner, '') AS devOwner,
                        IFNULL(devType, '') AS devType,
                        IFNULL(devVendor, '') AS devVendor,
                        IFNULL(devFavorite, '') AS devFavorite,
                        IFNULL(devGroup, '') AS devGroup,
                        IFNULL(devComments, '') AS devComments,
                        IFNULL(devFirstConnection, '') AS devFirstConnection,
                        IFNULL(devLastConnection, '') AS devLastConnection,
                        IFNULL(devLastIP, '') AS devLastIP,
                        IFNULL(devPrimaryIPv4, '') AS devPrimaryIPv4,
                        IFNULL(devPrimaryIPv6, '') AS devPrimaryIPv6,
                        IFNULL(devVlan, '') AS devVlan,
                        IFNULL(devForceStatus, '') AS devForceStatus,
                        IFNULL(devStaticIP, '') AS devStaticIP,
                        IFNULL(devScan, '') AS devScan,
                        IFNULL(devLogEvents, '') AS devLogEvents,
                        IFNULL(devAlertEvents, '') AS devAlertEvents,
                        IFNULL(devAlertDown, 0) AS devAlertDown,
                        IFNULL(devCanSleep, 0) AS devCanSleep,
                        IFNULL(devSkipRepeated, '') AS devSkipRepeated,
                        IFNULL(devLastNotification, '') AS devLastNotification,
                        IFNULL(devPresentLastScan, 0) AS devPresentLastScan,
                        IFNULL(devIsNew, '') AS devIsNew,
                        IFNULL(devLocation, '') AS devLocation,
                        IFNULL(devIsArchived, '') AS devIsArchived,
                        LOWER(IFNULL(devParentMAC, '')) AS devParentMAC,
                        IFNULL(devParentPort, '') AS devParentPort,
                        IFNULL(devIcon, '') AS devIcon,
                        IFNULL(devGUID, '') AS devGUID,
                        IFNULL(devSite, '') AS devSite,
                        IFNULL(devSSID, '') AS devSSID,
                        IFNULL(devSyncHubNode, '') AS devSyncHubNode,
                        IFNULL(devSourcePlugin, '') AS devSourcePlugin,
                        IFNULL(devCustomProps, '') AS devCustomProps,
                        IFNULL(devFQDN, '') AS devFQDN,
                        IFNULL(devParentRelType, '') AS devParentRelType,
                        IFNULL(devReqNicsOnline, '') AS devReqNicsOnline,
                        IFNULL(devMacSource, '') AS devMacSource,
                        IFNULL(devNameSource, '') AS devNameSource,
                        IFNULL(devFQDNSource, '') AS devFQDNSource,
                        IFNULL(devLastIPSource, '') AS devLastIPSource,
                        IFNULL(devVendorSource, '') AS devVendorSource,
                        IFNULL(devSSIDSource, '') AS devSSIDSource,
                        IFNULL(devParentMACSource, '') AS devParentMACSource,
                        IFNULL(devParentPortSource, '') AS devParentPortSource,
                        IFNULL(devParentRelTypeSource, '') AS devParentRelTypeSource,
                        IFNULL(devVlanSource, '') AS devVlanSource,
                        -- devIsSleeping: opted-in, absent, and still within the sleep window
                        CASE
                            WHEN devCanSleep = 1
                             AND devPresentLastScan = 0
                             AND devLastConnection >= datetime('now', '-30 minutes')
                            THEN 1
                            ELSE 0
                        END AS devIsSleeping,
                        -- devFlapping: toggling online/offline frequently within the flap window
                        CASE
                            WHEN EXISTS (
                                SELECT 1
                                FROM Events e
                                WHERE LOWER(e.eveMac) = LOWER(Devices.devMac)
                                AND e.eveEventType IN ('Connected','Disconnected','Device Down','Down Reconnected')
                                AND e.eveDateTime >= datetime('now', '-1 hours')
                                GROUP BY e.eveMac
                                HAVING COUNT(*) >= 3
                            )
                            THEN 1
                            ELSE 0
                        END AS devFlapping
                        FROM Devices
                    )
                    SELECT *,
                        -- devStatus references devIsSleeping from the CTE (no duplication)
                        CASE
                            WHEN devIsNew = 1          THEN 'New'
                            WHEN devPresentLastScan = 1 THEN 'On-line'
                            WHEN devIsSleeping = 1     THEN 'Sleeping'
                            WHEN devAlertDown != 0     THEN 'Down'
                            WHEN devIsArchived = 1     THEN 'Archived'
                            WHEN devPresentLastScan = 0 THEN 'Off-line'
                            ELSE 'Unknown status'
                        END AS devStatus
                    FROM base;

-- ensure_mac_lowercase_triggers(), ensure_dangling_parentmac_cleanup_trigger()
CREATE TRIGGER trg_lowercase_mac_insert
                AFTER INSERT ON Devices
                BEGIN
                    UPDATE Devices
                    SET devMac = LOWER(NEW.devMac),
                        devParentMAC = LOWER(NEW.devParentMAC)
                    WHERE rowid = NEW.rowid;
                END;
CREATE TRIGGER trg_lowercase_mac_update
                AFTER UPDATE OF devMac, devParentMAC ON Devices
                WHEN (NEW.devMac GLOB '*[A-Z]*') OR (NEW.devParentMAC GLOB '*[A-Z]*')
                BEGIN
                    UPDATE Devices
                    SET devMac = LOWER(NEW.devMac),
                        devParentMAC = LOWER(NEW.devParentMAC)
                    WHERE rowid = NEW.rowid;
                END;
CREATE TRIGGER trg_clear_dangling_parentmac_on_delete
                AFTER DELETE ON Devices
                FOR EACH ROW
                WHEN OLD.devMac IS NOT NULL AND OLD.devMac != ''
                BEGIN
                    UPDATE Devices
                    SET devParentMAC = '', devParentMACSource = ''
                    WHERE LOWER(devParentMAC) = LOWER(OLD.devMac);
                END;
-- server/db/db_history.py ensure_deviceshistory_triggers()
CREATE TRIGGER trg_devhist_update
AFTER UPDATE ON Devices
FOR EACH ROW
WHEN (SELECT CAST(COALESCE(setValue, '0') AS INTEGER) FROM Settings WHERE setKey = 'DEV_HIST_DAYS') > 0
BEGIN
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devMac', CAST(OLD.devMac AS TEXT), CAST(NEW.devMac AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devMacSource), ''), 'system'),
         datetime('now')
  WHERE (OLD.devMac IS NOT NEW.devMac)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devMac''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devName', CAST(OLD.devName AS TEXT), CAST(NEW.devName AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devNameSource), ''), 'system'),
         datetime('now')
  WHERE (OLD.devName IS NOT NEW.devName)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devName''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devFQDN', CAST(OLD.devFQDN AS TEXT), CAST(NEW.devFQDN AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devFQDNSource), ''), 'system'),
         datetime('now')
  WHERE (OLD.devFQDN IS NOT NEW.devFQDN)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devFQDN''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devLastIP', CAST(OLD.devLastIP AS TEXT), CAST(NEW.devLastIP AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devLastIPSource), ''), 'system'),
         datetime('now')
  WHERE (OLD.devLastIP IS NOT NEW.devLastIP)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devLastIP''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devVendor', CAST(OLD.devVendor AS TEXT), CAST(NEW.devVendor AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devVendorSource), ''), 'system'),
         datetime('now')
  WHERE (OLD.devVendor IS NOT NEW.devVendor)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devVendor''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSSID', CAST(OLD.devSSID AS TEXT), CAST(NEW.devSSID AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devSSIDSource), ''), 'system'),
         datetime('now')
  WHERE (OLD.devSSID IS NOT NEW.devSSID)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSSID''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentMAC', CAST(OLD.devParentMAC AS TEXT), CAST(NEW.devParentMAC AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devParentMACSource), ''), 'system'),
         datetime('now')
  WHERE (OLD.devParentMAC IS NOT NEW.devParentMAC)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentMAC''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentPort', CAST(OLD.devParentPort AS TEXT), CAST(NEW.devParentPort AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devParentPortSource), ''), 'system'),
         datetime('now')
  WHERE (OLD.devParentPort IS NOT NEW.devParentPort)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentPort''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentRelType', CAST(OLD.devParentRelType AS TEXT), CAST(NEW.devParentRelType AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devParentRelTypeSource), ''), 'system'),
         datetime('now')
  WHERE (OLD.devParentRelType IS NOT NEW.devParentRelType)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentRelType''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devVlan', CAST(OLD.devVlan AS TEXT), CAST(NEW.devVlan AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devVlanSource), ''), 'system'),
         datetime('now')
  WHERE (OLD.devVlan IS NOT NEW.devVlan)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devVlan''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devOwner', CAST(OLD.devOwner AS TEXT), CAST(NEW.devOwner AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devOwner IS NOT NEW.devOwner)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devOwner''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devType', CAST(OLD.devType AS TEXT), CAST(NEW.devType AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devType IS NOT NEW.devType)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devType''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devFavorite', CAST(OLD.devFavorite AS TEXT), CAST(NEW.devFavorite AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devFavorite IS NOT NEW.devFavorite)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devFavorite''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devGroup', CAST(OLD.devGroup AS TEXT), CAST(NEW.devGroup AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devGroup IS NOT NEW.devGroup)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devGroup''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devComments', CAST(OLD.devComments AS TEXT), CAST(NEW.devComments AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devComments IS NOT NEW.devComments)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devComments''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devForceStatus', CAST(OLD.devForceStatus AS TEXT), CAST(NEW.devForceStatus AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devForceStatus IS NOT NEW.devForceStatus)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devForceStatus''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devStaticIP', CAST(OLD.devStaticIP AS TEXT), CAST(NEW.devStaticIP AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devStaticIP IS NOT NEW.devStaticIP)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devStaticIP''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devScan', CAST(OLD.devScan AS TEXT), CAST(NEW.devScan AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devScan IS NOT NEW.devScan)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devScan''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devAlertDown', CAST(OLD.devAlertDown AS TEXT), CAST(NEW.devAlertDown AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devAlertDown IS NOT NEW.devAlertDown)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devAlertDown''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devCanSleep', CAST(OLD.devCanSleep AS TEXT), CAST(NEW.devCanSleep AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devCanSleep IS NOT NEW.devCanSleep)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devCanSleep''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSkipRepeated', CAST(OLD.devSkipRepeated AS TEXT), CAST(NEW.devSkipRepeated AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devSkipRepeated IS NOT NEW.devSkipRepeated)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSkipRepeated''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devLocation', CAST(OLD.devLocation AS TEXT), CAST(NEW.devLocation AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devLocation IS NOT NEW.devLocation)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devLocation''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devIsArchived', CAST(OLD.devIsArchived AS TEXT), CAST(NEW.devIsArchived AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devIsArchived IS NOT NEW.devIsArchived)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devIsArchived''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devReqNicsOnline', CAST(OLD.devReqNicsOnline AS TEXT), CAST(NEW.devReqNicsOnline AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devReqNicsOnline IS NOT NEW.devReqNicsOnline)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devReqNicsOnline''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devCustomProps', CAST(OLD.devCustomProps AS TEXT), CAST(NEW.devCustomProps AS TEXT),
         'user:api',
         datetime('now')
  WHERE (OLD.devCustomProps IS NOT NEW.devCustomProps)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devCustomProps''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devPrimaryIPv4', CAST(OLD.devPrimaryIPv4 AS TEXT), CAST(NEW.devPrimaryIPv4 AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devPrimaryIPv4 IS NOT NEW.devPrimaryIPv4)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devPrimaryIPv4''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devPrimaryIPv6', CAST(OLD.devPrimaryIPv6 AS TEXT), CAST(NEW.devPrimaryIPv6 AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devPrimaryIPv6 IS NOT NEW.devPrimaryIPv6)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devPrimaryIPv6''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devIcon', CAST(OLD.devIcon AS TEXT), CAST(NEW.devIcon AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devIcon IS NOT NEW.devIcon)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devIcon''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSite', CAST(OLD.devSite AS TEXT), CAST(NEW.devSite AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devSite IS NOT NEW.devSite)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSite''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSyncHubNode', CAST(OLD.devSyncHubNode AS TEXT), CAST(NEW.devSyncHubNode AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devSyncHubNode IS NOT NEW.devSyncHubNode)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSyncHubNode''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSourcePlugin', CAST(OLD.devSourcePlugin AS TEXT), CAST(NEW.devSourcePlugin AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devSourcePlugin IS NOT NEW.devSourcePlugin)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSourcePlugin''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devMacSource', CAST(OLD.devMacSource AS TEXT), CAST(NEW.devMacSource AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devMacSource IS NOT NEW.devMacSource)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devMacSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devNameSource', CAST(OLD.devNameSource AS TEXT), CAST(NEW.devNameSource AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devNameSource IS NOT NEW.devNameSource)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devNameSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devFQDNSource', CAST(OLD.devFQDNSource AS TEXT), CAST(NEW.devFQDNSource AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devFQDNSource IS NOT NEW.devFQDNSource)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devFQDNSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devLastIPSource', CAST(OLD.devLastIPSource AS TEXT), CAST(NEW.devLastIPSource AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devLastIPSource IS NOT NEW.devLastIPSource)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devLastIPSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devVendorSource', CAST(OLD.devVendorSource AS TEXT), CAST(NEW.devVendorSource AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devVendorSource IS NOT NEW.devVendorSource)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devVendorSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSSIDSource', CAST(OLD.devSSIDSource AS TEXT), CAST(NEW.devSSIDSource AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devSSIDSource IS NOT NEW.devSSIDSource)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSSIDSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentMACSource', CAST(OLD.devParentMACSource AS TEXT), CAST(NEW.devParentMACSource AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devParentMACSource IS NOT NEW.devParentMACSource)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentMACSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentPortSource', CAST(OLD.devParentPortSource AS TEXT), CAST(NEW.devParentPortSource AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devParentPortSource IS NOT NEW.devParentPortSource)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentPortSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentRelTypeSource', CAST(OLD.devParentRelTypeSource AS TEXT), CAST(NEW.devParentRelTypeSource AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devParentRelTypeSource IS NOT NEW.devParentRelTypeSource)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentRelTypeSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devVlanSource', CAST(OLD.devVlanSource AS TEXT), CAST(NEW.devVlanSource AS TEXT),
         'system',
         datetime('now')
  WHERE (OLD.devVlanSource IS NOT NEW.devVlanSource)
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devVlanSource''') > 0;
END;
CREATE TRIGGER trg_devhist_insert
AFTER INSERT ON Devices
FOR EACH ROW
WHEN (SELECT CAST(COALESCE(setValue, '0') AS INTEGER) FROM Settings WHERE setKey = 'DEV_HIST_DAYS') > 0
BEGIN
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devMac', NULL, CAST(NEW.devMac AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devMacSource), ''), 'system'),
         datetime('now')
  WHERE NEW.devMac IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devMac''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devName', NULL, CAST(NEW.devName AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devNameSource), ''), 'system'),
         datetime('now')
  WHERE NEW.devName IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devName''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devFQDN', NULL, CAST(NEW.devFQDN AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devFQDNSource), ''), 'system'),
         datetime('now')
  WHERE NEW.devFQDN IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devFQDN''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devLastIP', NULL, CAST(NEW.devLastIP AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devLastIPSource), ''), 'system'),
         datetime('now')
  WHERE NEW.devLastIP IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devLastIP''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devVendor', NULL, CAST(NEW.devVendor AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devVendorSource), ''), 'system'),
         datetime('now')
  WHERE NEW.devVendor IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devVendor''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSSID', NULL, CAST(NEW.devSSID AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devSSIDSource), ''), 'system'),
         datetime('now')
  WHERE NEW.devSSID IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSSID''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentMAC', NULL, CAST(NEW.devParentMAC AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devParentMACSource), ''), 'system'),
         datetime('now')
  WHERE NEW.devParentMAC IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentMAC''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentPort', NULL, CAST(NEW.devParentPort AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devParentPortSource), ''), 'system'),
         datetime('now')
  WHERE NEW.devParentPort IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentPort''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentRelType', NULL, CAST(NEW.devParentRelType AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devParentRelTypeSource), ''), 'system'),
         datetime('now')
  WHERE NEW.devParentRelType IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentRelType''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devVlan', NULL, CAST(NEW.devVlan AS TEXT),
         COALESCE(NULLIF(TRIM(NEW.devVlanSource), ''), 'system'),
         datetime('now')
  WHERE NEW.devVlan IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devVlan''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devOwner', NULL, CAST(NEW.devOwner AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devOwner IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devOwner''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devType', NULL, CAST(NEW.devType AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devType IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devType''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devFavorite', NULL, CAST(NEW.devFavorite AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devFavorite IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devFavorite''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devGroup', NULL, CAST(NEW.devGroup AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devGroup IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devGroup''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devComments', NULL, CAST(NEW.devComments AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devComments IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devComments''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devForceStatus', NULL, CAST(NEW.devForceStatus AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devForceStatus IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devForceStatus''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devStaticIP', NULL, CAST(NEW.devStaticIP AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devStaticIP IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devStaticIP''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devScan', NULL, CAST(NEW.devScan AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devScan IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devScan''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devAlertDown', NULL, CAST(NEW.devAlertDown AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devAlertDown IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devAlertDown''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devCanSleep', NULL, CAST(NEW.devCanSleep AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devCanSleep IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devCanSleep''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSkipRepeated', NULL, CAST(NEW.devSkipRepeated AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devSkipRepeated IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSkipRepeated''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devLocation', NULL, CAST(NEW.devLocation AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devLocation IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devLocation''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devIsArchived', NULL, CAST(NEW.devIsArchived AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devIsArchived IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devIsArchived''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devReqNicsOnline', NULL, CAST(NEW.devReqNicsOnline AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devReqNicsOnline IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devReqNicsOnline''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devCustomProps', NULL, CAST(NEW.devCustomProps AS TEXT),
         'user:api',
         datetime('now')
  WHERE NEW.devCustomProps IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devCustomProps''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devPrimaryIPv4', NULL, CAST(NEW.devPrimaryIPv4 AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devPrimaryIPv4 IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devPrimaryIPv4''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devPrimaryIPv6', NULL, CAST(NEW.devPrimaryIPv6 AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devPrimaryIPv6 IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devPrimaryIPv6''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devIcon', NULL, CAST(NEW.devIcon AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devIcon IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devIcon''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSite', NULL, CAST(NEW.devSite AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devSite IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSite''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSyncHubNode', NULL, CAST(NEW.devSyncHubNode AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devSyncHubNode IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSyncHubNode''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSourcePlugin', NULL, CAST(NEW.devSourcePlugin AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devSourcePlugin IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSourcePlugin''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devMacSource', NULL, CAST(NEW.devMacSource AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devMacSource IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devMacSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devNameSource', NULL, CAST(NEW.devNameSource AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devNameSource IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devNameSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devFQDNSource', NULL, CAST(NEW.devFQDNSource AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devFQDNSource IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devFQDNSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devLastIPSource', NULL, CAST(NEW.devLastIPSource AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devLastIPSource IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devLastIPSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devVendorSource', NULL, CAST(NEW.devVendorSource AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devVendorSource IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devVendorSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devSSIDSource', NULL, CAST(NEW.devSSIDSource AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devSSIDSource IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devSSIDSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentMACSource', NULL, CAST(NEW.devParentMACSource AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devParentMACSource IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentMACSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentPortSource', NULL, CAST(NEW.devParentPortSource AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devParentPortSource IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentPortSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devParentRelTypeSource', NULL, CAST(NEW.devParentRelTypeSource AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devParentRelTypeSource IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devParentRelTypeSource''') > 0;
  INSERT INTO DevicesHistory (devGUID, changedColumn, oldValue, newValue, changedBy, timestamp)
  SELECT NEW.devGUID, 'devVlanSource', NULL, CAST(NEW.devVlanSource AS TEXT),
         'system',
         datetime('now')
  WHERE NEW.devVlanSource IS NOT NULL
    AND COALESCE(NEW.devGUID, '') != ''
    AND instr((SELECT COALESCE(setValue, '') FROM Settings WHERE setKey = 'DEV_HIST_TRACKED'), '''devVlanSource''') > 0;
END;
