-- Syncthing (syncthing/syncthing @ ed38528d7fba3dd6a42c9c9fc6780af432dc15d2, MPL-2.0). Go sqlx with `?`
-- placeholders. Statements are text/template strings rendered once at open (folderdb_open.go:57,
-- basedb.go:80-87); the template constants are resolved here: FlagLocalIgnored=2, FlagLocalReceiveOnly=8,
-- FlagLocalGlobal=16, FlagLocalNeeded=32, LocalInvalidFlags=79, LocalDeviceIdx=1. Placeholders are normalised to
-- ?N in argument order. All paths below are under internal/db/sqlite/.

-- ============================================================ global state / need

-- @id syncthing.global.get_global_file
-- @src internal/db/sqlite/folderdb_global.go:25-31
-- @style ? positional, template constants resolved
-- @tags hot-small,hotpath
-- @note Puller/GUI lookup of the global version of one file: name -> files (Global bit) -> fileinfos + LEFT JOIN blocklists.
-- @param ?1 'Archive/d96/file11.jpg'
SELECT fi.fiprotobuf, bl.blprotobuf FROM fileinfos fi
INNER JOIN files f on fi.sequence = f.sequence
LEFT JOIN blocklists bl ON bl.blocklist_hash = f.blocklist_hash
INNER JOIN file_names n ON f.name_idx = n.idx
WHERE n.name = ?1 AND f.local_flags & 16 != 0;

-- @id syncthing.global.availability
-- @src internal/db/sqlite/folderdb_global.go:49-56
-- @style ? positional, template constants resolved
-- @tags hotpath
-- @note Which remote devices have the global version of a file (puller picks block sources): self-join of files on (version_idx, name_idx) plus devices, ORDER BY device_id.
-- @param ?1 'Documents/d12/file16.pdf'
SELECT d.device_id FROM files f
INNER JOIN devices d ON d.idx = f.device_idx
INNER JOIN files g ON g.version_idx = f.version_idx AND g.name_idx = f.name_idx
INNER JOIN file_names n ON f.name_idx = n.idx
WHERE n.name = ?1 AND g.local_flags & 16 != 0 AND f.device_idx != 1 AND f.local_flags & 79 = 0
ORDER BY d.device_id;

-- @id syncthing.global.all_global_files_prefix
-- @src internal/db/sqlite/folderdb_global.go:97-102
-- @style ? positional; the upper bound is prefixEnd(prefix) computed in Go (util.go:116)
-- @tags hotpath
-- @note GUI directory browser (/rest/db/browse): name range scan over file_names joined to Global-flagged files, ordered by name.
-- @param ?1 'Photos/d5/'
-- @param ?2 'Photos/d50'
SELECT f.sequence, n.name, f.type, f.modified as modnanos, f.size, f.deleted, f.local_flags as localflags FROM files f
INNER JOIN file_names n ON f.name_idx = n.idx
WHERE n.name >= ?1 AND n.name < ?2 AND f.local_flags & 16 != 0
ORDER BY n.name;

-- @id syncthing.global.all_global_files
-- @src internal/db/sqlite/folderdb_global.go:77-82
-- @style no parameters, template constants resolved
-- @note Whole-folder global listing (browse at root, completion): bitmask filter over every files row, sorted by name via the file_names join.
SELECT f.sequence, n.name, f.type, f.modified as modnanos, f.size, f.deleted, f.local_flags as localflags FROM files f
INNER JOIN file_names n ON f.name_idx = n.idx
WHERE f.local_flags & 16 != 0
ORDER BY n.name;

-- @id syncthing.need.local_alphabetic
-- @src internal/db/sqlite/folderdb_global.go:139-148
-- @style ? positional; ORDER BY chosen from config.PullOrder at folderdb_global.go:110-130 and appended with LIMIT ? OFFSET ?
-- @tags hotpath,dynamic
-- @note Puller queue / GUI "out of sync" page for the local device: Need-bit scan, 3-way join to fileinfos/blocklists/names, alphabetic page.
-- @param ?1 100
-- @param ?2 0
SELECT fi.fiprotobuf, bl.blprotobuf, n.name, g.size, g.modified FROM fileinfos fi
INNER JOIN files g on fi.sequence = g.sequence
LEFT JOIN blocklists bl ON bl.blocklist_hash = g.blocklist_hash
INNER JOIN file_names n ON g.name_idx = n.idx
WHERE g.local_flags & 2 = 0 AND g.local_flags & 32 != 0
ORDER BY n.name ASC LIMIT ?1 OFFSET ?2;

-- @id syncthing.need.local_largest_first
-- @src internal/db/sqlite/folderdb_global.go:139-148
-- @style ? positional; PullOrderLargestFirst (folderdb_global.go:118), puller passes limit 0 -> -1
-- @tags hotpath,dynamic
-- @note Puller with pullOrder=largestFirst: the whole need list sorted by size (temp b-tree sort over a bitmask scan).
-- @param ?1 -1
-- @param ?2 0
SELECT fi.fiprotobuf, bl.blprotobuf, n.name, g.size, g.modified FROM fileinfos fi
INNER JOIN files g on fi.sequence = g.sequence
LEFT JOIN blocklists bl ON bl.blocklist_hash = g.blocklist_hash
INNER JOIN file_names n ON g.name_idx = n.idx
WHERE g.local_flags & 2 = 0 AND g.local_flags & 32 != 0
ORDER BY g.size DESC LIMIT ?1 OFFSET ?2;

-- @id syncthing.need.remote_newest_first
-- @src internal/db/sqlite/folderdb_global.go:160-187
-- @style ? positional; PullOrderNewestFirst (folderdb_global.go:122) appended after the UNION ALL
-- @tags hotpath,dynamic
-- @note What a remote device still needs (GUI remote-device completion page): UNION ALL of NOT EXISTS / EXISTS correlated self-joins on files+devices, newest-first page.
-- @param ?1 'P56IOI7-MZJNU2Y-IQGDREY-DM2MGTI-MGL3BXN-PQ6W5BM-TBBZ4TJ-XZWICQ2'
-- @param ?2 'P56IOI7-MZJNU2Y-IQGDREY-DM2MGTI-MGL3BXN-PQ6W5BM-TBBZ4TJ-XZWICQ2'
-- @param ?3 100
-- @param ?4 0
SELECT fi.fiprotobuf, bl.blprotobuf, n.name, g.size, g.modified FROM fileinfos fi
INNER JOIN files g on fi.sequence = g.sequence
LEFT JOIN blocklists bl ON bl.blocklist_hash = g.blocklist_hash
INNER JOIN file_names n ON g.name_idx = n.idx
WHERE g.local_flags & 16 != 0 AND NOT g.deleted AND g.local_flags & 79 = 0 AND NOT EXISTS (
  SELECT 1 FROM FILES f
  INNER JOIN devices d ON d.idx = f.device_idx
  WHERE f.name_idx = g.name_idx AND f.version_idx = g.version_idx AND d.device_id = ?1
)
UNION ALL
SELECT fi.fiprotobuf, bl.blprotobuf, n.name, g.size, g.modified FROM fileinfos fi
INNER JOIN files g on fi.sequence = g.sequence
LEFT JOIN blocklists bl ON bl.blocklist_hash = g.blocklist_hash
INNER JOIN file_names n ON g.name_idx = n.idx
WHERE g.local_flags & 16 != 0 AND g.deleted AND g.local_flags & 79 = 0 AND EXISTS (
  SELECT 1 FROM FILES f
  INNER JOIN devices d ON d.idx = f.device_idx
  WHERE f.name_idx = g.name_idx AND d.device_id = ?2 AND NOT f.deleted AND f.local_flags & 79 = 0
)
ORDER BY g.modified DESC LIMIT ?3 OFFSET ?4;

-- @id syncthing.need.remote_alphabetic_all
-- @src internal/db/sqlite/folderdb_global.go:160-187
-- @style ? positional; PullOrderAlphabetic (folderdb_global.go:115), no limit (-1)
-- @tags dynamic
-- @note The same remote-need UNION ALL fully materialised and sorted by name (index sender / completion recompute).
-- @param ?1 'AIR6LPZ-7K4PTTV-UXQSMUU-CPQ5YWH-OEDFIIQ-JUG777G-2YQXXR5-YD6AWQR'
-- @param ?2 'AIR6LPZ-7K4PTTV-UXQSMUU-CPQ5YWH-OEDFIIQ-JUG777G-2YQXXR5-YD6AWQR'
-- @param ?3 -1
-- @param ?4 0
SELECT fi.fiprotobuf, bl.blprotobuf, n.name, g.size, g.modified FROM fileinfos fi
INNER JOIN files g on fi.sequence = g.sequence
LEFT JOIN blocklists bl ON bl.blocklist_hash = g.blocklist_hash
INNER JOIN file_names n ON g.name_idx = n.idx
WHERE g.local_flags & 16 != 0 AND NOT g.deleted AND g.local_flags & 79 = 0 AND NOT EXISTS (
  SELECT 1 FROM FILES f
  INNER JOIN devices d ON d.idx = f.device_idx
  WHERE f.name_idx = g.name_idx AND f.version_idx = g.version_idx AND d.device_id = ?1
)
UNION ALL
SELECT fi.fiprotobuf, bl.blprotobuf, n.name, g.size, g.modified FROM fileinfos fi
INNER JOIN files g on fi.sequence = g.sequence
LEFT JOIN blocklists bl ON bl.blocklist_hash = g.blocklist_hash
INNER JOIN file_names n ON g.name_idx = n.idx
WHERE g.local_flags & 16 != 0 AND g.deleted AND g.local_flags & 79 = 0 AND EXISTS (
  SELECT 1 FROM FILES f
  INNER JOIN devices d ON d.idx = f.device_idx
  WHERE f.name_idx = g.name_idx AND d.device_id = ?2 AND NOT f.deleted AND f.local_flags & 79 = 0
)
ORDER BY n.name ASC LIMIT ?3 OFFSET ?4;

-- ============================================================ counts

-- @id syncthing.counts.need_remote
-- @src internal/db/sqlite/folderdb_counts.go:82-100
-- @style ? positional, template constants resolved
-- @tags hotpath
-- @note Remote completion percentage (GUI polls it per device): two grouped aggregates over correlated NOT EXISTS / EXISTS self-joins, UNION ALL.
-- @param ?1 'MFZWI3D-BONSGYC-YLTMRWG-C43ENR5-QXGZDMM-FZWI3DP-BONSGYY-LTMRWAD'
-- @param ?2 'MFZWI3D-BONSGYC-YLTMRWG-C43ENR5-QXGZDMM-FZWI3DP-BONSGYY-LTMRWAD'
SELECT g.type, count(*) as count, sum(g.size) as size, g.local_flags, g.deleted FROM files g
WHERE g.local_flags & 16 != 0 AND NOT g.deleted AND g.local_flags & 79 = 0 AND NOT EXISTS (
  SELECT 1 FROM FILES f
  INNER JOIN devices d ON d.idx = f.device_idx
  WHERE f.name_idx = g.name_idx AND f.version_idx = g.version_idx AND d.device_id = ?1
)
GROUP BY g.type, g.local_flags, g.deleted
UNION ALL
SELECT g.type, count(*) as count, sum(g.size) as size, g.local_flags, g.deleted FROM files g
WHERE g.local_flags & 16 != 0 AND g.deleted AND g.local_flags & 79 = 0 AND EXISTS (
  SELECT 1 FROM FILES f
  INNER JOIN devices d ON d.idx = f.device_idx
  WHERE f.name_idx = g.name_idx AND d.device_id = ?2 AND NOT f.deleted AND f.local_flags & 79 = 0
)
GROUP BY g.type, g.local_flags, g.deleted;

-- @id syncthing.counts.local
-- @src internal/db/sqlite/folderdb_counts.go:24-28
-- @style ? positional, template constants resolved
-- @tags hotpath
-- @note Folder summary (local state) from the trigger-maintained counts table, filtered through the devices join.
-- @param ?1 '7777777-777777N-7777777-777777N-7777777-777777N-7777777-77777Q4'
SELECT s.type, s.count, s.size, s.local_flags, s.deleted FROM counts s
INNER JOIN devices d ON d.idx = s.device_idx
WHERE d.device_id = ?1 AND s.local_flags & 2 = 0;

-- @id syncthing.counts.global
-- @src internal/db/sqlite/folderdb_counts.go:43-46
-- @style no parameters, template constants resolved
-- @tags hotpath
-- @note Folder summary (global state): bitmask predicates over the counts table.
SELECT s.type, s.count, s.size, s.local_flags, s.deleted FROM counts s
WHERE s.local_flags & 16 != 0 AND s.local_flags & 79 = 0;

-- @id syncthing.local.list_devices_for_folder
-- @src internal/db/sqlite/folderdb_local.go:118-123
-- @style no parameters, template constants resolved
-- @note Remote devices that announced anything for this folder: DISTINCT over a counts/devices join.
SELECT DISTINCT d.device_id FROM counts s
INNER JOIN devices d ON d.idx = s.device_idx
WHERE s.count > 0 AND s.device_idx != 1
ORDER BY d.device_id;

-- ============================================================ local / per-device files

-- @id syncthing.local.get_device_file
-- @src internal/db/sqlite/folderdb_local.go:30-37
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Scanner/puller lookup of one device's copy of a file: 4-way join resolving device and name via their unique indexes.
-- @param ?1 '7777777-777777N-7777777-777777N-7777777-777777N-7777777-77777Q4'
-- @param ?2 'Projects/d31/file14.flac'
SELECT fi.fiprotobuf, bl.blprotobuf FROM fileinfos fi
INNER JOIN files f on fi.sequence = f.sequence
LEFT JOIN blocklists bl ON bl.blocklist_hash = f.blocklist_hash
INNER JOIN devices d ON f.device_idx = d.idx
INNER JOIN file_names n ON f.name_idx = n.idx
WHERE d.device_id = ?1 AND n.name = ?2;

-- @id syncthing.local.by_sequence
-- @src internal/db/sqlite/folderdb_local.go:66-73
-- @style ? positional
-- @tags hotpath
-- @note Index sender: the next batch of local files after the remote's acknowledged sequence, ORDER BY sequence LIMIT.
-- @param ?1 '7777777-777777N-7777777-777777N-7777777-777777N-7777777-77777Q4'
-- @param ?2 30000
-- @param ?3 1000
SELECT fi.fiprotobuf, bl.blprotobuf FROM fileinfos fi
INNER JOIN files f on fi.sequence = f.sequence
LEFT JOIN blocklists bl ON bl.blocklist_hash = f.blocklist_hash
INNER JOIN devices d ON d.idx = f.device_idx
WHERE d.device_id = ?1 AND f.sequence >= ?2
ORDER BY f.sequence LIMIT ?3;

-- @id syncthing.local.with_prefix
-- @src internal/db/sqlite/folderdb_local.go:85-92
-- @style ? positional; upper bound from prefixEnd (util.go:116)
-- @tags hotpath
-- @note Scanner walking a subdirectory: one device's files in a name range.
-- @param ?1 '7777777-777777N-7777777-777777N-7777777-777777N-7777777-77777Q4'
-- @param ?2 'Music/d1'
-- @param ?3 'Music/d2'
SELECT fi.fiprotobuf, bl.blprotobuf FROM fileinfos fi
INNER JOIN files f on fi.sequence = f.sequence
LEFT JOIN blocklists bl ON bl.blocklist_hash = f.blocklist_hash
INNER JOIN devices d ON d.idx = f.device_idx
INNER JOIN file_names n ON f.name_idx = n.idx
WHERE d.device_id = ?1 AND n.name >= ?2 AND n.name < ?3;

-- @id syncthing.local.with_blocks_hash
-- @src internal/db/sqlite/folderdb_local.go:97-101
-- @style ? positional, template constants resolved
-- @tags hot-small,hotpath
-- @note Rename/copy detection: local files with an identical blocklist via the partial index on blocklist_hash.
-- @param ?1 x'000000000000000A0000000000000001000000002E2AC0EA000000000012D687'
SELECT f.sequence, n.name, f.type, f.modified as modnanos, f.size, f.deleted, f.local_flags as localflags FROM files f
INNER JOIN file_names n ON f.name_idx = n.idx
WHERE f.device_idx = 1 AND f.blocklist_hash = ?1;

-- @id syncthing.local.blocks_with_hash
-- @src internal/db/sqlite/folderdb_local.go:108-113
-- @style ? positional, template constants resolved
-- @tags hotpath
-- @note Block reuse in the puller: where locally does a block with this hash live (blocks PK prefix -> files via blocklist_hash -> names).
-- @param ?1 x'0000000000000000000000000000000000000000000000000000000000000007'
SELECT f.blocklist_hash as blocklisthash, b.idx as blockindex, b.offset, b.size, n.name as filename FROM files f
INNER JOIN file_names n ON f.name_idx = n.idx
LEFT JOIN blocks b ON f.blocklist_hash = b.blocklist_hash
WHERE f.device_idx = 1 AND b.hash = ?1;

-- @id syncthing.debug.file_pattern
-- @src internal/db/sqlite/folderdb_local.go:174-182
-- @style ? positional; the pattern is wrapped in % in Go (folderdb_local.go:174)
-- @note Debug dump of every device's entries matching a name: LIKE '%x%' over file_names, 4-way join, ordered.
-- @param ?1 '%d42/file1%'
SELECT f.sequence, n.name, f.type, f.modified as modnanos, f.size, f.deleted, f.local_flags as localflags, v.version, f.blocklist_hash as blocklisthash, d.device_id as deviceid FROM files f
INNER JOIN devices d ON d.idx = f.device_idx
INNER JOIN file_names n ON n.idx = f.name_idx
INNER JOIN file_versions v ON v.idx = f.version_idx
WHERE n.name LIKE ?1
ORDER BY n.name, f.device_idx;

-- ============================================================ index IDs / sequences

-- @id syncthing.indexid.create_local
-- @src internal/db/sqlite/folderdb_indexid.go:53-58
-- @style ? positional, template constants resolved
-- @note New local index ID seeded with MAX(sequence) of local files: INSERT ... SELECT aggregate with ON CONFLICT DO UPDATE.
-- @param ?1 '3c6ef36200009999'
-- @param ?2 '3c6ef36200009999'
INSERT INTO indexids (device_idx, index_id, sequence)
SELECT 1, ?1, COALESCE(MAX(sequence), 0) FROM files
WHERE device_idx = 1
ON CONFLICT DO UPDATE SET index_id = ?2;

-- ============================================================ update path (folderdb_update.go Update, per file)

-- @id syncthing.update.insert_name
-- @src internal/db/sqlite/folderdb_update.go:51-57
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Name interning for every incoming FileInfo: UPSERT ... RETURNING idx (conflict path here).
-- @param ?1 'src/d42/file18.flac'
INSERT INTO file_names(name)
VALUES (?1)
ON CONFLICT(name) DO UPDATE
  SET name = excluded.name
RETURNING idx;

-- @id syncthing.update.insert_version
-- @src internal/db/sqlite/folderdb_update.go:63-69
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Version-vector interning for every incoming FileInfo (new version here).
-- @param ?1 '3333333333333333:91,0123456789abcdef:5'
INSERT INTO file_versions (version)
VALUES (?1)
ON CONFLICT(version) DO UPDATE
  SET version = excluded.version
RETURNING idx;

-- @id syncthing.update.insert_file
-- @src internal/db/sqlite/folderdb_update.go:75-79
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Index update for one remote file: INSERT OR REPLACE over the (device_idx, name_idx) unique index, firing the counts and indexids triggers (delete + insert upserts).
-- @param ?1 3
-- @param ?2 40001
-- @param ?3 0
-- @param ?4 1730000000000000000
-- @param ?5 4096
-- @param ?6 0
-- @param ?7 0
-- @param ?8 x'0000000000000012000000000000000100000000ABCDEF00000000000012D687'
-- @param ?9 18
-- @param ?10 7
INSERT OR REPLACE INTO files (device_idx, remote_sequence, type, modified, size, deleted, local_flags, blocklist_hash, name_idx, version_idx)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
RETURNING sequence;

-- @id syncthing.update.insert_blocks_chunk
-- @src internal/db/sqlite/folderdb_update.go:407-414
-- @style sqlx NamedExec over a slice: one multi-row VALUES per chunk of up to 1000 blocks; normalised to ?N, 4-block instance
-- @tags batch,dynamic
-- @note Block index insert for a scanned file: multi-row INSERT OR IGNORE into a WITHOUT ROWID table keyed on (hash, blocklist_hash, idx).
-- @param ?1 x'1111111111111111111111111111111111111111111111111111111111111111'
-- @param ?2 x'9999999999999999999999999999999999999999999999999999999999999999'
-- @param ?3 0
-- @param ?4 0
-- @param ?5 131072
-- @param ?6 x'2222222222222222222222222222222222222222222222222222222222222222'
-- @param ?7 x'9999999999999999999999999999999999999999999999999999999999999999'
-- @param ?8 1
-- @param ?9 131072
-- @param ?10 131072
-- @param ?11 x'0000000000000000000000000000000000000000000000000000000000000007'
-- @param ?12 x'9999999999999999999999999999999999999999999999999999999999999999'
-- @param ?13 2
-- @param ?14 262144
-- @param ?15 131072
-- @param ?16 x'4444444444444444444444444444444444444444444444444444444444444444'
-- @param ?17 x'9999999999999999999999999999999999999999999999999999999999999999'
-- @param ?18 3
-- @param ?19 393216
-- @param ?20 4711
INSERT OR IGNORE INTO blocks (hash, blocklist_hash, idx, offset, size)
VALUES (?1, ?2, ?3, ?4, ?5), (?6, ?7, ?8, ?9, ?10), (?11, ?12, ?13, ?14, ?15), (?16, ?17, ?18, ?19, ?20);

-- @id syncthing.update.recalc_select
-- @src internal/db/sqlite/folderdb_update.go:453-462
-- @style ? positional
-- @tags hot-small,hotpath
-- @note recalcGlobalForFile, run once per updated file: every device's entry for a name with its version vector.
-- @param ?1 'Archive/d106/file15.jpg'
SELECT n.name, f.device_idx, f.sequence, f.modified, v.version, f.deleted, f.local_flags FROM files f
INNER JOIN file_versions v ON v.idx = f.version_idx
INNER JOIN file_names n ON n.idx = f.name_idx
WHERE n.name = ?1;

-- @id syncthing.update.recalc_set_global
-- @src internal/db/sqlite/folderdb_update.go:498-505
-- @style ? positional
-- @tags hotpath
-- @note Set Global/Need on the winning entry; fires the counts_update trigger (upsert + update of counts).
-- @param ?1 48
-- @param ?2 3
-- @param ?3 68617
UPDATE files SET local_flags = ?1
WHERE device_idx = ?2 AND sequence = ?3;

-- @id syncthing.update.recalc_clear_others
-- @src internal/db/sqlite/folderdb_update.go:511-519
-- @style ? positional
-- @tags hotpath
-- @note Clear Need|Global on every other entry of the name: scalar subquery for name_idx, bitmask filter, counts trigger.
-- @param ?1 -49
-- @param ?2 'Archive/d106/file15.jpg'
-- @param ?3 68617
-- @param ?4 48
UPDATE files SET local_flags = local_flags & ?1
WHERE name_idx = (SELECT idx FROM file_names WHERE name = ?2) AND sequence != ?3 AND local_flags & ?4 != 0;

-- @id syncthing.update.drop_files_named
-- @src internal/db/sqlite/folderdb_update.go:286-295
-- @style sqlx.In expands IN (?) to the name list; 3-name instance
-- @tags dynamic
-- @note Delete one device's entries by name: IN-subquery over an IN-list, cascading the counts_delete trigger.
-- @param ?1 2
-- @param ?2 'Archive/d96/file11.jpg'
-- @param ?3 'Archive/d106/file15.jpg'
-- @param ?4 'src/d18/file29.pdf'
DELETE FROM files
WHERE device_idx = ?1 AND name_idx IN (
  SELECT idx FROM file_names WHERE name IN (?2, ?3, ?4)
);

-- @id syncthing.update.recalc_folder_names
-- @src internal/db/sqlite/folderdb_update.go:422-434
-- @style ? positional
-- @tags expect-empty
-- @note After DropDevice/DropAllFiles: names with no Global entry left, NOT EXISTS correlated scan + GROUP BY over all files (empty when consistent).
-- @param ?1 16
SELECT n.name FROM files f
INNER JOIN file_names n ON n.idx = f.name_idx
WHERE NOT EXISTS (
  SELECT 1 FROM files g
  WHERE g.name_idx = f.name_idx AND g.local_flags & ?1 != 0
)
GROUP BY n.name;

-- ============================================================ garbage collection

-- @id syncthing.gc.old_deleted
-- @src internal/db/sqlite/db_service.go:229-237
-- @style ? positional, template constants resolved
-- @note Periodic GC of processed deletions older than the retention: full scan with NOT IN subquery, cascading the counts trigger.
-- @param ?1 1234567890000000000
-- @param ?2 1710000000000000000
DELETE FROM files
WHERE deleted
  AND modified != ?1
  AND modified < ?2
  AND local_flags & 32 == 0
  AND sequence NOT IN (
    SELECT sequence FROM indexids WHERE device_idx = 1
  );

-- @id syncthing.gc.blocklists_chunk
-- @src internal/db/sqlite/db_service.go:301-305
-- @style fmt.Sprintf with a random blob range from randomBlobRanges (db_service.go:330); one chunk instance
-- @tags dynamic
-- @note Chunked blocklist GC: range over the WITHOUT ROWID PK plus NOT EXISTS against the partial blocklist_hash index.
DELETE FROM blocklists
WHERE blocklists.blocklist_hash >= x'00000000000000000000000000000000' AND blocklists.blocklist_hash < x'0000000000002000' AND NOT EXISTS (
  SELECT 1 FROM files WHERE files.blocklist_hash = blocklists.blocklist_hash
);

-- ============================================================ mtimes

-- @id syncthing.mtimes.get
-- @src internal/db/sqlite/folderdb_mtimes.go:18-21
-- @style ? positional
-- @tags hot-small,hotpath
-- @note MtimeFS lookup on every scanned file's stat.
-- @param ?1 'Documents/d12/file16.pdf'
SELECT m.ondisk, m.virtual FROM mtimes m
WHERE m.name = ?1;

