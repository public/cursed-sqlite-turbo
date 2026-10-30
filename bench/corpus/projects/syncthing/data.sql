-- Synthetic data for syncthing: one shared folder replicated with four remote devices. Deterministic (no random()):
-- attributes come from multiplicative hashes of the name number, with different bits per attribute.
-- Scale 1: 40k file names, ~160 distinct version vectors, ~150k files rows (local + 4 remotes), matching
-- fileinfos, ~32k blocklists, ~85k blocks, 5k mtimes, 300 kv rows. Flags follow folderdb_update.go's rules: one
-- Global-flagged entry per name, Need set on it when the local device lacks that version.
BEGIN;

INSERT INTO folders(idx, folder_id, database_name) VALUES
  (1, 'default', 'folder.0001-default.db'), (2, 'photos-ab12c', 'folder.0002-photos.db'), (3, 'docs-x9q2w', 'folder.0003-docs.db'),
  (4, 'music', 'folder.0004-music.db'), (5, 'backup-k3m', NULL);

-- idx 1 is the LocalDeviceID (protocol.repeatedDeviceID(0xff)); opened first, as folderdb_open.go does
INSERT INTO devices(idx, device_id) VALUES
  (1, '7777777-777777N-7777777-777777N-7777777-777777N-7777777-77777Q4'),
  (2, 'MFZWI3D-BONSGYC-YLTMRWG-C43ENR5-QXGZDMM-FZWI3DP-BONSGYY-LTMRWAD'),
  (3, 'P56IOI7-MZJNU2Y-IQGDREY-DM2MGTI-MGL3BXN-PQ6W5BM-TBBZ4TJ-XZWICQ2'),
  (4, 'AIR6LPZ-7K4PTTV-UXQSMUU-CPQ5YWH-OEDFIIQ-JUG777G-2YQXXR5-YD6AWQR'),
  (5, 'XQ7NRZS-PB5HLJD-ROPFHCS-CHDUUEC-SKZEHZK-AW5YHJE-TFPTBUS-ADQ7PAK');

-- per-name attributes
CREATE TEMP TABLE _n AS
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40000*(SELECT scale FROM _cfg)),
h AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
SELECT i, h,
       printf('%s/%s/%s%d.%s',
              CASE (h / 3) % 6 WHEN 0 THEN 'Photos' WHEN 1 THEN 'Documents' WHEN 2 THEN 'Music' WHEN 3 THEN 'src' WHEN 4 THEN 'Projects' ELSE 'Archive' END,
              'd' || ((h / 19) % 120),
              CASE (h / 7) % 100 WHEN 0 THEN 'dir' WHEN 1 THEN 'dir' WHEN 2 THEN 'dir' WHEN 3 THEN 'dir' WHEN 4 THEN 'dir' WHEN 5 THEN 'dir' WHEN 6 THEN 'dir' WHEN 7 THEN 'dir' WHEN 8 THEN 'link' ELSE 'file' END,
              i,
              CASE (h / 1777) % 5 WHEN 0 THEN 'jpg' WHEN 1 THEN 'txt' WHEN 2 THEN 'go' WHEN 3 THEN 'flac' ELSE 'pdf' END) AS name,
       CASE WHEN (h / 7) % 100 < 8 THEN 1 WHEN (h / 7) % 100 = 8 THEN 4 ELSE 0 END AS type,
       CASE WHEN (h / 131) % 20 = 0 THEN 1 ELSE 0 END AS gdel,
       (h / 1031) % 100 AS lpick,                         -- <85 local has global, 85..96 older, >=97 missing
       (h / 4099) % 4 AS vdev, 1 + (h / 13) % 40 AS vctr, -- version vector shape (shared across many names)
       1700000000 + i * 600 + (h % 600) AS mod_s,
       1000 + (h / 97) % 5000000 AS fsize
FROM h;

INSERT INTO file_names(idx, name) SELECT i, name FROM _n;

-- version vectors are shared between files, as in the real file_versions table: '<8-byte id hex>:<counter>,...'
CREATE TEMP TABLE _v AS
SELECT DISTINCT vdev, vctr, g,
       printf('%016x:%d', (vdev + 1) * 1229782938247303441, vctr * 2 + g) ||
       CASE WHEN vdev % 2 = 0 THEN printf(',%016x:%d', 81985529216486895, (vctr * 7) % 23 + 1) ELSE '' END AS version
FROM _n, (SELECT 0 AS g UNION ALL SELECT 1);
INSERT INTO file_versions(version) SELECT version FROM _v ORDER BY vdev, vctr, g;

-- one row per (name, device): device 1 = local, 2..5 remote
CREATE TEMP TABLE _f AS
SELECT n.i, d.idx AS dev, n.type, n.gdel, n.vdev, n.vctr,
       ((n.i * 31 + d.idx * 1000003) * 2654435761) % 4294967296 AS hk,
       CASE WHEN d.idx = 1 THEN (CASE WHEN n.lpick < 85 THEN 1 ELSE 0 END)
            WHEN d.idx = 2 AND n.lpick >= 85 THEN 1
            ELSE (CASE WHEN ((((n.i * 31 + d.idx * 1000003) * 2654435761) % 4294967296) / 16) % 5 = 0 THEN 0 ELSE 1 END) END AS isg,
       n.mod_s, n.fsize, n.lpick
FROM _n n, devices d
WHERE (d.idx = 1 AND n.lpick < 97)
   OR (d.idx = 2 AND n.lpick >= 85)
   OR (d.idx > 1 AND ((((n.i * 31 + d.idx * 1000003) * 2654435761) % 4294967296) % 10) < 7);

-- the Global holder: the local entry when it has the global version, else device 2 (always present then)
INSERT INTO files(device_idx, remote_sequence, name_idx, type, modified, size, version_idx, deleted, local_flags, blocklist_hash)
SELECT f.dev,
       CASE WHEN f.dev = 1 THEN NULL ELSE f.i END,
       f.i, f.type,
       (f.mod_s - CASE WHEN f.isg THEN 0 ELSE 86400 END) * 1000000000,
       CASE WHEN f.isg AND f.gdel THEN 0 WHEN f.type = 0 THEN f.fsize - CASE WHEN f.isg THEN 0 ELSE 777 END ELSE 0 END,
       v.rowid,
       CASE WHEN f.isg AND f.gdel THEN 1 ELSE 0 END,
       (CASE WHEN f.dev = 1 AND (f.hk / 50021) % 50 = 0 THEN 2 ELSE 0 END)
     | (CASE WHEN f.dev = 1 AND (f.hk / 70001) % 100 = 0 THEN 8 ELSE 0 END)
     | (CASE WHEN f.dev > 1 AND (f.hk / 333) % 100 = 0 THEN 64 ELSE 0 END)
     | (CASE WHEN f.isg AND ((f.dev = 1) OR (f.dev = 2 AND f.lpick >= 85)) THEN 16 ELSE 0 END)
     | (CASE WHEN f.isg AND f.dev = 2 AND f.lpick >= 85 THEN 32 ELSE 0 END),
       CASE WHEN f.type = 0 AND NOT (f.isg AND f.gdel)
            THEN unhex(printf('%016x%016x%016x%016x', f.i, f.isg, (f.i * 2654435761) % 4294967296, 1234567)) END
FROM _f f
JOIN _v vv ON vv.vdev = f.vdev AND vv.vctr = f.vctr AND vv.g = f.isg
JOIN file_versions v ON v.version = vv.version
ORDER BY f.dev, f.i;

INSERT INTO fileinfos(sequence, fiprotobuf)
SELECT f.sequence, CAST(printf('\n%s\x10%d\x18%d(%d:%s', n.name, f.type, f.size, f.modified / 1000000000, hex(substr(coalesce(f.blocklist_hash, x'00'), 1, 12))) AS BLOB)
FROM files f JOIN file_names n ON n.idx = f.name_idx;

INSERT INTO blocklists(blocklist_hash, blprotobuf)
SELECT DISTINCT blocklist_hash, CAST(printf('\n$%s\x10%d', hex(blocklist_hash), size) AS BLOB) FROM files WHERE blocklist_hash IS NOT NULL;

-- blocklists of superseded versions that no file refers to any more: GC is deferred, so these linger
INSERT INTO blocklists(blocklist_hash, blprotobuf)
SELECT unhex(printf('%016x%016x%016x%016x', i, 2, (i * 2654435761) % 4294967296, 1234567)), CAST(printf('\n$old%d', i) AS BLOB)
FROM _n WHERE i % 9 = 4;

-- block index for local files: 1..4 blocks each; every 10th block hash comes from a pool of 500 shared hashes
INSERT OR IGNORE INTO blocks(hash, blocklist_hash, idx, offset, size)
SELECT CASE WHEN ((f.sequence * 7 + k.k) * 2654435761 / 64) % 10 = 0
            THEN unhex(printf('%064x', ((f.sequence * 7 + k.k) * 2654435761 / 1024) % 500))
            ELSE unhex(printf('%016x%016x%016x%016x', f.sequence, k.k, (f.sequence * 2654435761) % 4294967296, 99)) END,
       f.blocklist_hash, k.k, k.k * 131072, CASE WHEN (k.k + 1) * 131072 < f.size THEN 131072 ELSE max(f.size - k.k * 131072, 1) END
FROM files f, (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3) k
WHERE f.device_idx = 1 AND f.blocklist_hash IS NOT NULL AND k.k <= f.size / 1048576;

-- index IDs: the insert trigger left the max sequence per device; give them IDs as the index exchange does
UPDATE indexids SET index_id = printf('%08x%08x', (device_idx * 2654435761) % 4294967296, 12345 + device_idx);

INSERT INTO mtimes(name, ondisk, virtual)
SELECT name, mod_s * 1000000000 + 123, mod_s * 1000000000 FROM _n WHERE i % 8 = 0;

INSERT INTO kv(key, value)
SELECT 'folderMeta/' || f.folder_id || '/' || k.k, CAST('meta-' || f.idx || '-' || k.k AS BLOB)
FROM folders f, (WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 40) SELECT k FROM n) k
UNION ALL
SELECT 'device/' || d.device_id || '/lastSeen', CAST(1730000000 + d.idx AS BLOB) FROM devices d
UNION ALL
SELECT 'misc/' || k, CAST(k AS BLOB) FROM (WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 95) SELECT k FROM n);

INSERT INTO schemamigrations VALUES (1, 1740000000000000000, 'v2.0.0'), (2, 1750000000000000000, 'v2.0.3'), (5, 1760000000000000000, 'v2.0.10');

COMMIT;
