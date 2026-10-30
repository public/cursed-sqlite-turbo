-- Syncthing (syncthing/syncthing @ ed38528d7fba3dd6a42c9c9fc6780af432dc15d2, MPL-2.0)
-- Concatenation of internal/db/sqlite/sql/schema/{common,main,folder}/*.sql, verbatim. In the app the main
-- database (folders, kv) and each per-folder database (everything else) are separate files; here they share one.

-- ==== common/10-schema.sql
-- Copyright (C) 2025 The Syncthing Authors.
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at https://mozilla.org/MPL/2.0/.

-- Schema migrations hold the list of historical migrations applied
CREATE TABLE IF NOT EXISTS schemamigrations (
    schema_version INTEGER NOT NULL PRIMARY KEY,
    applied_at INTEGER NOT NULL, -- unix nanos
    syncthing_version TEXT NOT NULL COLLATE BINARY
) STRICT
;

-- ==== common/70-kv.sql
-- Copyright (C) 2025 The Syncthing Authors.
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at https://mozilla.org/MPL/2.0/.

--- Simple KV store. This backs the "miscDB" we use for certain minor pieces
--  of data.
CREATE TABLE IF NOT EXISTS kv (
    key TEXT NOT NULL PRIMARY KEY COLLATE BINARY,
    value BLOB NOT NULL
) STRICT, WITHOUT ROWID
;

-- ==== main/00-folders.sql
-- Copyright (C) 2025 The Syncthing Authors.
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at https://mozilla.org/MPL/2.0/.

-- folders map folder IDs as used by Syncthing to database folder indexes
CREATE TABLE IF NOT EXISTS folders (
    idx INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    folder_id TEXT NOT NULL UNIQUE COLLATE BINARY,
    database_name TEXT COLLATE BINARY -- initially null
) STRICT
;
-- The database_name is unique, when set
CREATE INDEX IF NOT EXISTS folders_database_name ON folders (database_name) WHERE database_name IS NOT NULL
;

-- ==== folder/00-devices.sql
-- Copyright (C) 2025 The Syncthing Authors.
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at https://mozilla.org/MPL/2.0/.

-- devices map device IDs as used by Syncthing to database device indexes
CREATE TABLE IF NOT EXISTS devices (
    idx INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL UNIQUE COLLATE BINARY
) STRICT
;

-- ==== folder/20-files.sql
-- Copyright (C) 2025 The Syncthing Authors.
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at https://mozilla.org/MPL/2.0/.

-- Files
--
-- The files table contains all files announced by any device. Files present
-- on this device are filed under the LocalDeviceID, not the actual current
-- device ID, for simplicity, consistency and portability. One announced
-- version of each file is considered the "global" version - the latest one,
-- that all other devices strive to replicate. This instance gets the Global
-- flag bit set. There may be other identical instances of this file
-- announced by other devices, but only one instance gets the Global flag;
-- this simplifies accounting. If the current device has the Global version,
-- the LocalDeviceID instance of the file is the one that has the Global
-- bit.
--
-- If the current device does not have that version of the file it gets the
-- Need bit set. Only Global files announced by another device can have the
-- Need bit. This allows for very efficient lookup of files needing handling
-- on this device, which is a common query.
CREATE TABLE IF NOT EXISTS files (
    device_idx INTEGER NOT NULL, -- actual device ID or LocalDeviceID
    sequence INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, -- our local database sequence, for each and every entry
    remote_sequence INTEGER, -- remote device's sequence number, null for local or synthetic entries
    name_idx INTEGER NOT NULL,
    type INTEGER NOT NULL, -- protocol.FileInfoType
    modified INTEGER NOT NULL, -- Unix nanos
    size INTEGER NOT NULL,
    version_idx INTEGER NOT NULL,
    deleted INTEGER NOT NULL, -- boolean
    local_flags INTEGER NOT NULL,
    blocklist_hash BLOB, -- null when there are no blocks
    FOREIGN KEY(device_idx) REFERENCES devices(idx) ON DELETE CASCADE,
    FOREIGN KEY(name_idx) REFERENCES file_names(idx),
    FOREIGN KEY(version_idx) REFERENCES file_versions(idx)
) STRICT
;
CREATE TABLE IF NOT EXISTS file_names (
    idx INTEGER NOT NULL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE COLLATE BINARY
) STRICT
;
CREATE TABLE IF NOT EXISTS file_versions (
    idx INTEGER NOT NULL PRIMARY KEY,
    version TEXT NOT NULL UNIQUE COLLATE BINARY
) STRICT
;
-- FileInfos store the actual protobuf object. We do this separately to keep
-- the files rows smaller and more efficient.
CREATE TABLE IF NOT EXISTS fileinfos (
    sequence INTEGER NOT NULL PRIMARY KEY, -- our local database sequence from the files table
    fiprotobuf BLOB NOT NULL,
    FOREIGN KEY(sequence) REFERENCES files(sequence) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
) STRICT
;
-- There can be only one file per folder, device, and remote sequence number
CREATE UNIQUE INDEX IF NOT EXISTS files_remote_sequence ON files (device_idx, remote_sequence)
    WHERE remote_sequence IS NOT NULL
;
-- There can be only one file per folder, device, and name
CREATE UNIQUE INDEX IF NOT EXISTS files_device_name ON files (device_idx, name_idx)
;
-- We want to be able to look up & iterate files based on blocks hash
CREATE INDEX IF NOT EXISTS files_blocklist_hash_only ON files (blocklist_hash, device_idx) WHERE blocklist_hash IS NOT NULL
;
-- We need to look by name_idx or version_idx for garbage collection.
-- This will fail pre-migration for v4 schemas, which is fine.
-- syncthing:ignore-failure
CREATE INDEX IF NOT EXISTS files_name_idx_only ON files (name_idx)
;
-- This will fail pre-migration for v4 schemas, which is fine.
-- syncthing:ignore-failure
CREATE INDEX IF NOT EXISTS files_version_idx_only ON files (version_idx)
;

-- ==== folder/30-indexids.sql
-- Copyright (C) 2025 The Syncthing Authors.
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at https://mozilla.org/MPL/2.0/.

-- indexids holds the index ID and maximum sequence for a given device and folder
CREATE TABLE IF NOT EXISTS indexids (
    device_idx INTEGER NOT NULL PRIMARY KEY,
    index_id TEXT NOT NULL COLLATE BINARY,
    sequence INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY(device_idx) REFERENCES devices(idx) ON DELETE CASCADE
) STRICT, WITHOUT ROWID
;
CREATE TRIGGER IF NOT EXISTS indexids_seq AFTER INSERT ON files
BEGIN
    INSERT INTO indexids (device_idx, index_id, sequence)
        VALUES (NEW.device_idx, "", COALESCE(NEW.remote_sequence, NEW.sequence))
        ON CONFLICT DO UPDATE SET sequence = COALESCE(NEW.remote_sequence, NEW.sequence);
END
;

-- ==== folder/40-counts.sql
-- Copyright (C) 2025 The Syncthing Authors.
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at https://mozilla.org/MPL/2.0/.

-- Counts
--
-- Counts and sizes are maintained for each device, folder, type, flag bits
-- combination.
CREATE TABLE IF NOT EXISTS counts (
    device_idx INTEGER NOT NULL,
    type INTEGER NOT NULL,
    local_flags INTEGER NOT NULL,
    deleted INTEGER NOT NULL, -- boolean
    count INTEGER NOT NULL,
    size INTEGER NOT NULL,
    PRIMARY KEY(device_idx, type, local_flags, deleted),
    FOREIGN KEY(device_idx) REFERENCES devices(idx) ON DELETE CASCADE
) STRICT, WITHOUT ROWID
;

--- Maintain counts when files are added and removed using triggers

CREATE TRIGGER IF NOT EXISTS counts_insert AFTER INSERT ON files
BEGIN
    INSERT INTO counts (device_idx, type, local_flags, deleted, count, size)
        VALUES (NEW.device_idx, NEW.type, NEW.local_flags, NEW.deleted, 1, NEW.size)
        ON CONFLICT DO UPDATE SET count = count + 1, size = size + NEW.size;
END
;
CREATE TRIGGER IF NOT EXISTS counts_delete AFTER DELETE ON files
BEGIN
    UPDATE counts SET count = count - 1, size = size - OLD.size
        WHERE device_idx = OLD.device_idx AND type = OLD.type AND local_flags = OLD.local_flags AND deleted = OLD.deleted;
END
;
CREATE TRIGGER IF NOT EXISTS counts_update AFTER UPDATE OF local_flags ON files
WHEN NEW.local_flags != OLD.local_flags
BEGIN
    INSERT INTO counts (device_idx, type, local_flags, deleted, count, size)
        VALUES (NEW.device_idx, NEW.type, NEW.local_flags, NEW.deleted, 1, NEW.size)
        ON CONFLICT DO UPDATE SET count = count + 1, size = size + NEW.size;
    UPDATE counts SET count = count - 1, size = size - OLD.size
        WHERE device_idx = OLD.device_idx AND type = OLD.type AND local_flags = OLD.local_flags AND deleted = OLD.deleted;
END
;

-- ==== folder/50-blocks.sql
-- Copyright (C) 2025 The Syncthing Authors.
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at https://mozilla.org/MPL/2.0/.

-- Block lists
--
-- The block lists are extracted from FileInfos and stored separately. This
-- reduces the database size by reusing the same block list entry for all
-- devices announcing the same file. Doing it for all block lists instead of
-- using a size cutoff simplifies queries. Block lists are garbage collected
-- "manually", not using a trigger as that was too performance impacting.
CREATE TABLE IF NOT EXISTS blocklists (
    blocklist_hash BLOB NOT NULL PRIMARY KEY,
    blprotobuf BLOB NOT NULL
) STRICT, WITHOUT ROWID
;

-- Blocks
--
-- For all local files we store the blocks individually for quick lookup. A
-- given block can exist in multiple blocklists and at multiple offsets in a
-- blocklist. We eschew most indexes here as inserting millions of blocks is
-- common and performance is critical.
CREATE TABLE IF NOT EXISTS blocks (
    hash BLOB NOT NULL,
    blocklist_hash BLOB NOT NULL,
    idx INTEGER NOT NULL,
    offset INTEGER NOT NULL,
    size INTEGER NOT NULL,
    PRIMARY KEY(hash, blocklist_hash, idx)
) STRICT, WITHOUT ROWID
;

-- ==== folder/50-mtimes.sql
-- Copyright (C) 2025 The Syncthing Authors.
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at https://mozilla.org/MPL/2.0/.

--- Backing for the MtimeFS
CREATE TABLE IF NOT EXISTS mtimes (
    name TEXT NOT NULL PRIMARY KEY,
    ondisk INTEGER NOT NULL, -- unix nanos
    virtual INTEGER NOT NULL -- unix nanos
) STRICT, WITHOUT ROWID
;

