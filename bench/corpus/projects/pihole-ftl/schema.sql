-- pi-hole/FTL @ 29c8b13f4bba0c4f4f47598e45a65cbf1cedac88 (EUPL-1.2). Only the CREATE statements the queries need.
-- FTL keeps two databases; both live in this one schema (no table names clash):
--   * gravity.db: test/gravity.db.sql (the template copy of pi-hole's advanced/Templates/gravity.db.sql)
--   * pihole-FTL.db / in-memory query DB: src/database/query-table.h (CREATE_QUERY_STORAGE_TABLE, CREATE_*_BY_ID,
--     CREATE_QUERIES_VIEW, index_creation[]), src/database/network-table.c, src/database/aliasclients.c,
--     src/database/message-table.c, src/database/common.c
-- disk_query_storage stands in for the ATTACHed disk.query_storage (same DDL) so the export query can run in one DB.

-- ===================================================================== gravity.db (test/gravity.db.sql:4-209)
CREATE TABLE "group"
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	enabled BOOLEAN NOT NULL DEFAULT 1,
	name TEXT UNIQUE NOT NULL,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	description TEXT
);

CREATE TABLE domainlist
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	type INTEGER NOT NULL DEFAULT 0,
	domain TEXT NOT NULL,
	enabled BOOLEAN NOT NULL DEFAULT 1,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	comment TEXT,
	UNIQUE(domain, type)
);

CREATE TABLE adlist
(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  address TEXT NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT 1,
  date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
  date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
  comment TEXT,
  date_updated INTEGER,
  number INTEGER NOT NULL DEFAULT 0,
  invalid_domains INTEGER NOT NULL DEFAULT 0,
  status INTEGER NOT NULL DEFAULT 0,
  abp_entries INTEGER NOT NULL DEFAULT 0,
  type INTEGER NOT NULL DEFAULT 0,
  UNIQUE(address, type)
);

CREATE TABLE adlist_by_group
(
	adlist_id INTEGER NOT NULL REFERENCES adlist (id) ON DELETE CASCADE,
	group_id INTEGER NOT NULL REFERENCES "group" (id) ON DELETE CASCADE,
	PRIMARY KEY (adlist_id, group_id)
) WITHOUT ROWID;

CREATE TABLE gravity
(
	domain TEXT NOT NULL,
	adlist_id INTEGER NOT NULL REFERENCES adlist (id)
);

CREATE TABLE antigravity
(
	domain TEXT NOT NULL,
	adlist_id INTEGER NOT NULL REFERENCES adlist (id)
);

CREATE TABLE info
(
	property TEXT PRIMARY KEY,
	value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE domainlist_by_group
(
	domainlist_id INTEGER NOT NULL REFERENCES domainlist (id) ON DELETE CASCADE,
	group_id INTEGER NOT NULL REFERENCES "group" (id) ON DELETE CASCADE,
	PRIMARY KEY (domainlist_id, group_id)
) WITHOUT ROWID;

CREATE TABLE client
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	ip TEXT NOT NULL UNIQUE,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	comment TEXT
);

CREATE TABLE client_by_group
(
	client_id INTEGER NOT NULL REFERENCES client (id) ON DELETE CASCADE,
	group_id INTEGER NOT NULL REFERENCES "group" (id) ON DELETE CASCADE,
	PRIMARY KEY (client_id, group_id)
) WITHOUT ROWID;

CREATE TRIGGER tr_adlist_update AFTER UPDATE OF address,enabled,comment ON adlist
    BEGIN
      UPDATE adlist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE id = NEW.id;
    END;

CREATE TRIGGER tr_client_update AFTER UPDATE ON client
    BEGIN
      UPDATE client SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE id = NEW.id;
    END;

CREATE TRIGGER tr_domainlist_update AFTER UPDATE ON domainlist
    BEGIN
      UPDATE domainlist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE id = NEW.id;
    END;

CREATE VIEW vw_allowlist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 0;

CREATE VIEW vw_denylist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 1;

CREATE VIEW vw_regex_allowlist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 2;

CREATE VIEW vw_regex_denylist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 3;

CREATE VIEW vw_gravity AS SELECT domain, adlist.id AS adlist_id, adlist_by_group.group_id AS group_id
    FROM gravity
    LEFT JOIN adlist_by_group ON adlist_by_group.adlist_id = gravity.adlist_id
    LEFT JOIN adlist ON adlist.id = gravity.adlist_id
    LEFT JOIN "group" ON "group".id = adlist_by_group.group_id
    WHERE adlist.enabled = 1 AND (adlist_by_group.group_id IS NULL OR "group".enabled = 1);

CREATE VIEW vw_antigravity AS SELECT domain, adlist.id AS adlist_id, adlist_by_group.group_id AS group_id
    FROM antigravity
    LEFT JOIN adlist_by_group ON adlist_by_group.adlist_id = antigravity.adlist_id
    LEFT JOIN adlist ON adlist.id = antigravity.adlist_id
    LEFT JOIN "group" ON "group".id = adlist_by_group.group_id
    WHERE adlist.enabled = 1 AND (adlist_by_group.group_id IS NULL OR "group".enabled = 1) AND adlist.type = 1;

CREATE VIEW vw_adlist AS SELECT DISTINCT address, id, type
    FROM adlist
    WHERE enabled = 1
    ORDER BY id;

CREATE TRIGGER tr_domainlist_add AFTER INSERT ON domainlist
    BEGIN
      INSERT INTO domainlist_by_group (domainlist_id, group_id) VALUES (NEW.id, 0);
    END;

CREATE TRIGGER tr_client_add AFTER INSERT ON client
    BEGIN
      INSERT INTO client_by_group (client_id, group_id) VALUES (NEW.id, 0);
    END;

CREATE TRIGGER tr_adlist_add AFTER INSERT ON adlist
    BEGIN
      INSERT INTO adlist_by_group (adlist_id, group_id) VALUES (NEW.id, 0);
    END;

CREATE TRIGGER tr_group_update AFTER UPDATE ON "group"
    BEGIN
      UPDATE "group" SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE id = NEW.id;
    END;

CREATE TRIGGER tr_group_zero AFTER DELETE ON "group"
    BEGIN
      INSERT OR IGNORE INTO "group" (id,enabled,name) VALUES (0,1,'Default');
    END;

CREATE TRIGGER tr_domainlist_delete AFTER DELETE ON domainlist
    BEGIN
      DELETE FROM domainlist_by_group WHERE domainlist_id = OLD.id;
    END;

CREATE TRIGGER tr_adlist_delete AFTER DELETE ON adlist
    BEGIN
      DELETE FROM adlist_by_group WHERE adlist_id = OLD.id;
    END;

CREATE TRIGGER tr_client_delete AFTER DELETE ON client
    BEGIN
      DELETE FROM client_by_group WHERE client_id = OLD.id;
    END;

CREATE INDEX idx_adlist_by_group_gid ON adlist_by_group (group_id, adlist_id);
CREATE INDEX idx_domainlist_by_group_gid ON domainlist_by_group (group_id, domainlist_id);
CREATE INDEX idx_gravity ON gravity (domain, adlist_id);
CREATE INDEX idx_antigravity ON antigravity (domain, adlist_id);

-- ===================================================================== query database (src/database/query-table.h:27-108)
CREATE TABLE query_storage ( id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, type INTEGER NOT NULL,
  status INTEGER NOT NULL, domain INTEGER NOT NULL, client INTEGER NOT NULL, forward INTEGER, additional_info INTEGER,
  reply_type INTEGER, reply_time REAL, dnssec INTEGER, list_id INTEGER, ede INTEGER );
CREATE TABLE domain_by_id (id INTEGER PRIMARY KEY, domain TEXT NOT NULL);
CREATE TABLE client_by_id (id INTEGER PRIMARY KEY, ip TEXT NOT NULL, name TEXT);
CREATE TABLE forward_by_id (id INTEGER PRIMARY KEY, forward TEXT NOT NULL);
CREATE TABLE addinfo_by_id (id INTEGER PRIMARY KEY, type INTEGER NOT NULL, content NOT NULL);
CREATE VIEW queries AS SELECT id, timestamp, type, status,
  CASE typeof(domain) WHEN 'integer' THEN (SELECT domain FROM domain_by_id d WHERE d.id = q.domain) ELSE domain END domain,
  CASE typeof(client) WHEN 'integer' THEN (SELECT ip FROM client_by_id c WHERE c.id = q.client) ELSE client END client,
  CASE typeof(forward) WHEN 'integer' THEN (SELECT forward FROM forward_by_id f WHERE f.id = q.forward) ELSE forward END forward,
  CASE typeof(additional_info) WHEN 'integer' THEN (SELECT content FROM addinfo_by_id a WHERE a.id = q.additional_info) ELSE additional_info END additional_info,
  reply_type, reply_time, dnssec, list_id FROM query_storage q;

CREATE UNIQUE INDEX idx_query_storage_id ON query_storage (id);
CREATE INDEX idx_query_storage_timestamp ON query_storage (timestamp);
CREATE INDEX idx_query_storage_type ON query_storage (type);
CREATE INDEX idx_query_storage_status ON query_storage (status);
CREATE INDEX idx_query_storage_domain ON query_storage (domain);
CREATE INDEX idx_query_storage_client ON query_storage (client);
CREATE INDEX idx_query_storage_forward ON query_storage (forward);
CREATE INDEX idx_query_storage_reply_type ON query_storage (reply_type);
CREATE INDEX idx_query_storage_reply_time ON query_storage (reply_time);
CREATE INDEX idx_query_storage_dnssec ON query_storage (dnssec);
CREATE UNIQUE INDEX domain_by_id_domain_idx ON domain_by_id(domain);
CREATE UNIQUE INDEX client_by_id_client_idx ON client_by_id(ip,name);
CREATE UNIQUE INDEX forward_by_id_forward_idx ON forward_by_id(forward);
CREATE UNIQUE INDEX addinfo_by_id_idx ON addinfo_by_id(type,content);

-- stand-in for the ATTACHed disk.query_storage (same DDL and timestamp index)
CREATE TABLE disk_query_storage ( id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, type INTEGER NOT NULL,
  status INTEGER NOT NULL, domain INTEGER NOT NULL, client INTEGER NOT NULL, forward INTEGER, additional_info INTEGER,
  reply_type INTEGER, reply_time REAL, dnssec INTEGER, list_id INTEGER, ede INTEGER );
CREATE INDEX idx_disk_query_storage_timestamp ON disk_query_storage (timestamp);

-- ===================================================================== pihole-FTL.db side tables
-- network / network_addresses: src/database/network-table.c:148-217 (v8 rebuild + v20 index), aliasclient_id from
-- src/database/aliasclients.c:29-35
CREATE TABLE network ( id INTEGER PRIMARY KEY NOT NULL, hwaddr TEXT UNIQUE NOT NULL, interface TEXT NOT NULL,
  firstSeen INTEGER NOT NULL, lastQuery INTEGER NOT NULL, numQueries INTEGER NOT NULL, macVendor TEXT,
  aliasclient_id INTEGER);
CREATE TABLE network_addresses ( network_id INTEGER NOT NULL, ip TEXT UNIQUE NOT NULL,
  lastSeen INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), name TEXT, nameUpdated INTEGER,
  FOREIGN KEY(network_id) REFERENCES network(id));
CREATE INDEX network_addresses_network_id_index ON network_addresses (network_id);
CREATE TABLE aliasclient (id INTEGER PRIMARY KEY NOT NULL, name TEXT NOT NULL, comment TEXT);
-- src/database/message-table.c:290-298
CREATE TABLE message ( id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, type TEXT NOT NULL,
  message TEXT NOT NULL, blob1 BLOB, blob2 BLOB, blob3 BLOB, blob4 BLOB, blob5 BLOB );
