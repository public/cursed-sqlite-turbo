-- Synthetic data for joplin. Deterministic (no random()): values come from multiplicative hashes of the row number,
-- with different columns taken from different bits. Times are Unix milliseconds, as in Joplin.
-- Scale 1: 300 folders (nested), 20k notes, 400 tags, ~30k note_tags, 8k resources, ~9k note_resources,
-- ~50k sync_items (target 10 = Joplin Cloud), 20k item_changes, 15k revisions, notes_normalized/notes_fts for
-- every indexable note, items_normalized/items_fts for OCRed resources.
-- IDs are 32 hex chars with a per-table prefix: f0 folders, a1 notes, b2 tags, c3 note_tags, d4 resources, e5 revisions.
BEGIN;

CREATE TEMP TABLE _w(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO _w VALUES (0,'meeting'),(1,'budget'),(2,'recipe'),(3,'travel'),(4,'project'),(5,'garden'),(6,'invoice'),(7,'kernel'),
  (8,'python'),(9,'review'),(10,'family'),(11,'doctor'),(12,'paris'),(13,'roadmap'),(14,'backup'),(15,'release'),
  (16,'shopping'),(17,'book'),(18,'movie'),(19,'workout'),(20,'tax'),(21,'insurance'),(22,'database'),(23,'sqlite'),
  (24,'deadline'),(25,'idea'),(26,'draft'),(27,'archive'),(28,'journal'),(29,'birthday'),(30,'server'),(31,'migration');

-- folders: 40 roots, the rest hang under an earlier folder (random tree, depth up to ~6)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO folders(id, title, created_time, updated_time, user_created_time, user_updated_time, parent_id, is_shared, share_id, icon, deleted_time)
SELECT printf('f0%030x', i),
       upper(substr((SELECT w FROM _w WHERE k = (h / 8) % 32), 1, 1)) || substr((SELECT w FROM _w WHERE k = (h / 8) % 32), 2) || ' ' || i,
       1600000000000 + i * 3600000, 1600000000000 + i * 3600000 + (h % 1000) * 60000,
       1600000000000 + i * 3600000, 1600000000000 + i * 3600000 + (h % 1000) * 60000,
       CASE WHEN i <= 40 THEN '' ELSE printf('f0%030x', ((h / 256) % (i - 1)) + 1) END,
       CASE WHEN (h / 4096) % 23 = 0 THEN 1 ELSE 0 END,
       CASE WHEN i <= 40 AND i % 9 = 4 THEN printf('%032x', i * 7777) ELSE '' END,
       CASE WHEN (h / 65536) % 5 = 0 THEN json_object('emoji', '📁', 'name', '', 'type', 1) ELSE '' END,
       CASE WHEN i > 40 AND (h / 1048576) % 41 = 0 THEN 1700000000000 + i * 1000 ELSE 0 END
FROM m;

-- shared folders propagate their share_id to the subtree
WITH RECURSIVE t(id, share_id) AS (
  SELECT id, share_id FROM folders WHERE share_id != ''
  UNION ALL SELECT f.id, t.share_id FROM folders f JOIN t ON f.parent_id = t.id)
UPDATE folders SET share_id = (SELECT t.share_id FROM t WHERE t.id = folders.id) WHERE id IN (SELECT id FROM t);

-- notes: skewed towards the first 30 folders; 25% to-dos; 1% conflicts; 3% trashed; 0.5% locked
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h, (i * 40503 + 12345) % 65536 AS g FROM n),
p AS (SELECT i, h, g,
             CASE WHEN h % 10 < 4 THEN (h / 16) % 30 + 1 ELSE (h / 16) % (300*(SELECT scale FROM _cfg)) + 1 END AS fi,
             1600000000000 + i * 90000 / (SELECT scale FROM _cfg) AS ct
      FROM m)
INSERT INTO notes(id, parent_id, title, body, created_time, updated_time, is_conflict, latitude, longitude, author, source_url,
                  is_todo, todo_due, todo_completed, source_application, `order`, user_created_time, user_updated_time,
                  markup_language, is_shared, conflict_original_id, deleted_time, is_locked)
SELECT printf('a1%030x', i),
       printf('f0%030x', fi),
       upper(substr((SELECT w FROM _w WHERE k = (g / 4) % 32), 1, 1)) || substr((SELECT w FROM _w WHERE k = (g / 4) % 32), 2)
         || ' ' || (SELECT w FROM _w WHERE k = (h / 1024) % 32) || ' notes ' || (i % 997),
       printf('# %s %s\n\nToday we discussed the %s and the %s. Next step: %s for the %s, then %s.\n\n- [ ] %s\n- [x] %s\n\n%s',
              (SELECT w FROM _w WHERE k = (g / 4) % 32), (SELECT w FROM _w WHERE k = (h / 1024) % 32),
              (SELECT w FROM _w WHERE k = (h / 32768) % 32), (SELECT w FROM _w WHERE k = (g / 128) % 32),
              (SELECT w FROM _w WHERE k = (h / 1048576) % 32), (SELECT w FROM _w WHERE k = (g / 2048) % 32),
              (SELECT w FROM _w WHERE k = (h / 33554432) % 32), (SELECT w FROM _w WHERE k = (i * 7) % 32),
              (SELECT w FROM _w WHERE k = (i * 13 + 5) % 32),
              substr('Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.', 1 + h % 120, 40 + (h / 7) % 200)),
       ct, ct + (h % 2000) * 60000,
       CASE WHEN (h / 512) % 97 = 0 THEN 1 ELSE 0 END,
       CASE WHEN (g / 64) % 7 = 0 THEN 48.85 + (h % 100) / 1000.0 ELSE 0 END,
       CASE WHEN (g / 64) % 7 = 0 THEN 2.35 + (h % 77) / 1000.0 ELSE 0 END,
       CASE WHEN (g / 8) % 5 = 0 THEN 'Kim' ELSE '' END,
       CASE WHEN (h / 128) % 6 = 0 THEN 'https://example.org/article/' || (h % 5000) ELSE '' END,
       CASE WHEN (h / 64) % 4 = 0 THEN 1 ELSE 0 END,
       CASE WHEN (h / 64) % 4 = 0 AND (g / 512) % 3 = 0 THEN ct + 86400000 * ((g / 16) % 60) ELSE 0 END,
       CASE WHEN (h / 64) % 4 = 0 AND (g / 4096) % 2 = 0 THEN ct + 3600000 * ((g / 32) % 48) ELSE 0 END,
       'net.cozic.joplin-desktop',
       ct + (g % 1000),
       ct, ct + (h % 2000) * 60000,
       CASE WHEN (g / 32768) = 1 AND (h / 4) % 9 = 0 THEN 2 ELSE 1 END,
       0,
       CASE WHEN (h / 512) % 97 = 0 AND (g / 16) % 3 != 0 THEN printf('a1%030x', CASE WHEN i > 1 THEN i - 1 ELSE 2 END) ELSE '' END,
       CASE WHEN (g / 256) % 33 = 0 THEN ct + 86400000 * 30 ELSE 0 END,
       CASE WHEN (h / 8192) % 200 = 0 THEN 1 ELSE 0 END
FROM p;

-- share_id follows the parent folder except for a few stale rows (what updateNoteShareIds fixes)
UPDATE notes SET share_id = (SELECT folders.share_id FROM folders WHERE folders.id = notes.parent_id)
WHERE rowid % 37 != 0 AND is_conflict = 0;
UPDATE notes SET share_id = printf('%032x', 31108) WHERE rowid % 211 = 5;
UPDATE notes SET is_shared = 1 WHERE rowid % 53 = 0;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 400*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO tags(id, title, created_time, updated_time, user_created_time, user_updated_time)
SELECT printf('b2%030x', i),
       CASE WHEN i <= 32 THEN (SELECT w FROM _w WHERE k = i - 1) ELSE (SELECT w FROM _w WHERE k = (h / 32) % 32) || '-' || i END,
       1600000000000 + i * 7200000, 1600000000000 + i * 7200000 + (h % 500) * 60000,
       1600000000000 + i * 7200000, 1600000000000 + i * 7200000 + (h % 500) * 60000
FROM m;

-- note_tags: each note gets 0-3 tags, tag popularity is skewed (the first 32 tags carry most notes)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20000*(SELECT scale FROM _cfg)),
k(k) AS (VALUES (0),(1),(2)),
m AS (SELECT i, k.k, ((i * 3 + k.k) * 2654435761) % 4294967296 AS h FROM n, k WHERE ((i * 2246822519) % 4294967296 / 16) % 4 > k.k)
INSERT INTO note_tags(id, note_id, tag_id, created_time, updated_time, user_created_time, user_updated_time)
SELECT printf('c3%030x', i * 4 + k),
       printf('a1%030x', i),
       printf('b2%030x', CASE WHEN h % 4 != 0 THEN (h / 4) % 32 + 1 ELSE (h / 4) % (400*(SELECT scale FROM _cfg)) + 1 END),
       1600000000000 + i * 90000, 1600000000000 + i * 90000, 1600000000000 + i * 90000, 1600000000000 + i * 90000
FROM m;

-- resources: images and PDFs, PDFs have OCR text
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 8000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO resources(id, title, mime, filename, created_time, updated_time, user_created_time, user_updated_time, file_extension,
                      encryption_blob_encrypted, `size`, is_shared, share_id, blob_updated_time, ocr_text, ocr_status)
SELECT printf('d4%030x', i),
       CASE (h / 16) % 4 WHEN 0 THEN 'scan_' || i || '.pdf' WHEN 1 THEN 'Screenshot ' || i || '.png' ELSE 'IMG_' || (1000 + i) || '.jpg' END,
       CASE (h / 16) % 4 WHEN 0 THEN 'application/pdf' WHEN 1 THEN 'image/png' ELSE 'image/jpeg' END,
       '',
       1600000000000 + i * 300000, 1600000000000 + i * 300000 + (h % 300) * 60000,
       1600000000000 + i * 300000, 1600000000000 + i * 300000 + (h % 300) * 60000,
       CASE (h / 16) % 4 WHEN 0 THEN 'pdf' WHEN 1 THEN 'png' ELSE 'jpg' END,
       CASE WHEN (h / 1024) % 50 = 0 THEN 1 ELSE 0 END,
       CASE WHEN (h / 2048) % 40 = 0 THEN -1 ELSE 2000 + (h % 4000000) END,
       CASE WHEN (h / 65536) % 31 = 0 THEN 1 ELSE 0 END,
       '',
       1600000000000 + i * 300000,
       CASE WHEN (h / 16) % 4 = 0 THEN 'Invoice ' || (SELECT w FROM _w WHERE k = (h / 256) % 32) || ' total amount due ' || (h % 900) || ' EUR ' || (SELECT w FROM _w WHERE k = (h / 8192) % 32) ELSE '' END,
       CASE WHEN (h / 16) % 4 = 0 THEN CASE WHEN (h / 131072) % 5 = 0 THEN 0 ELSE 2 END ELSE CASE WHEN (h / 131072) % 3 = 0 THEN 0 ELSE 2 END END
FROM m;

-- note_resources: each resource linked to one note, 1 in 7 linked to a second note too; 8% no longer associated
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 8000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO note_resources(note_id, resource_id, is_associated, last_seen_time)
SELECT printf('a1%030x', (h % (20000*(SELECT scale FROM _cfg))) + 1), printf('d4%030x', i),
       CASE WHEN (h / 64) % 12 = 0 THEN 0 ELSE 1 END,
       CASE WHEN (h / 64) % 12 = 0 THEN 1650000000000 + i * 1000 ELSE 0 END
FROM m
UNION ALL
SELECT printf('a1%030x', ((h / 7) % (20000*(SELECT scale FROM _cfg))) + 1), printf('d4%030x', i), 1, 0
FROM m WHERE (h / 4096) % 7 = 0;

INSERT INTO resource_local_states(resource_id, fetch_status, fetch_error)
SELECT id, CASE WHEN rowid % 10 = 3 THEN 0 WHEN rowid % 50 = 7 THEN 3 WHEN rowid % 97 = 11 THEN 1 ELSE 2 END,
       CASE WHEN rowid % 50 = 7 THEN 'Request timed out' ELSE '' END
FROM resources;

INSERT INTO resources_to_download(resource_id, updated_time, created_time)
SELECT resource_id, 1700000000000 + id * 1000, 1700000000000 + id * 1000 FROM resource_local_states WHERE fetch_status = 0 AND id % 2 = 1;

-- sync_items for target 10: ~90% of items synced, ~6% changed since, a few force_sync / disabled
INSERT INTO sync_items(sync_target, sync_time, item_type, item_id, sync_disabled, sync_disabled_reason, force_sync, item_location,
                       remote_item_updated_time, base_body, base_title)
SELECT 10,
       CASE WHEN (rowid * 2654435761) % 4294967296 / 16 % 16 = 0 THEN updated_time - 60000 ELSE updated_time + 5000 END,
       t, id,
       CASE WHEN rowid % 211 = 3 THEN 1 ELSE 0 END,
       CASE WHEN rowid % 211 = 3 THEN 'Item is too large' ELSE '' END,
       CASE WHEN rowid % 149 = 2 THEN 1 ELSE 0 END,
       1, updated_time,
       CASE WHEN t = 1 AND rowid % 16 = 0 THEN body ELSE '' END,
       CASE WHEN t = 1 AND rowid % 16 = 0 THEN title ELSE '' END
FROM (SELECT rowid, 1 AS t, id, updated_time, body, title FROM notes
      UNION ALL SELECT rowid, 2, id, updated_time, '', title FROM folders
      UNION ALL SELECT rowid, 5, id, updated_time, '', title FROM tags
      UNION ALL SELECT rowid, 6, id, updated_time, '', '' FROM note_tags
      UNION ALL SELECT rowid, 4, id, updated_time, '', title FROM resources)
WHERE (rowid * 2246822519) % 4294967296 / 256 % 10 != 0;
-- a few duplicate rows for the same item (what updateSyncTimeQueries' DELETE cleans up)
INSERT INTO sync_items(sync_target, sync_time, item_type, item_id, item_location)
SELECT sync_target, sync_time - 1000, item_type, item_id, item_location FROM sync_items WHERE id % 503 = 1;
-- orphans: synced items that no longer exist locally
INSERT INTO sync_items(sync_target, sync_time, item_type, item_id, item_location)
SELECT 10, 1650000000000 + i, 1, printf('a1%030x', 900000000 + i), 1
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300) SELECT i FROM n);

INSERT INTO deleted_items(item_type, item_id, deleted_time, sync_target)
SELECT 1, printf('a1%030x', 800000000 + i), 1700000000000 + i * 60000, CASE WHEN i % 4 = 0 THEN 7 ELSE 10 END
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 600*(SELECT scale FROM _cfg)) SELECT i FROM n);

-- item_changes: the change log the search engine and revision service walk
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO item_changes(item_type, item_id, type, created_time, source, before_change_item)
SELECT CASE WHEN h % 10 < 8 THEN 1 WHEN h % 10 = 8 THEN 2 ELSE 6 END,
       CASE WHEN h % 10 < 8 THEN printf('a1%030x', ((h / 16) % (20000*(SELECT scale FROM _cfg))) + 1)
            WHEN h % 10 = 8 THEN printf('f0%030x', ((h / 16) % (300*(SELECT scale FROM _cfg))) + 1)
            ELSE printf('c3%030x', ((h / 16) % (20000*(SELECT scale FROM _cfg))) * 4 + 4) END,
       CASE WHEN (h / 65536) % 10 = 0 THEN 1 WHEN (h / 65536) % 10 = 1 THEN 3 ELSE 2 END,
       1700000000000 + i * 30000,
       CASE WHEN (h / 1048576) % 3 = 0 THEN 2 ELSE 1 END,
       CASE WHEN h % 10 < 8 AND (h / 1048576) % 3 != 0 THEN json_object('id', printf('a1%030x', ((h / 16) % 20000) + 1), 'title', 'Old title ' || i, 'body', 'Old body') ELSE '' END
FROM m;

-- revisions: 5 per note for the first 3000 notes, each one chained to the previous
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 15000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i - 1) / 5 + 1 AS ni, (i - 1) % 5 AS r FROM n)
INSERT INTO revisions(id, parent_id, item_type, item_id, item_updated_time, title_diff, body_diff, metadata_diff, updated_time, created_time)
SELECT printf('e5%030x', i), CASE WHEN r = 0 THEN '' ELSE printf('e5%030x', i - 1) END, 1, printf('a1%030x', ni),
       1600000000000 + ni * 90000 + r * 86400000 * 7,
       json_array(json_object('diffs', json_array(json_array(1, 'v' || r)), 'start1', 0, 'start2', 0, 'length1', 0, 'length2', 2)),
       json_array(json_object('diffs', json_array(json_array(0, 'Today we '), json_array(1, 'changed line ' || r)), 'start1', 10, 'start2', 10, 'length1', 9, 'length2', 23)),
       json_object('new', json_object('todo_completed', r % 2), 'deleted', json_array()),
       1600000000000 + ni * 90000 + r * 86400000 * 7 + 600000, 1600000000000 + ni * 90000 + r * 86400000 * 7 + 600000
FROM m;

INSERT INTO key_values(`key`, `value`, `type`, updated_time)
SELECT CASE WHEN i % 3 = 0 THEN 'ResourceService::lastProcessedChangeId::' || i
            WHEN i % 3 = 1 THEN 'RevisionService::lastProcessedChangeId::' || i
            ELSE 'sync.10.lockStatus.' || i END,
       CAST(i * 37 AS TEXT), 1, 1700000000000 + i
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300) SELECT i FROM n);

-- search index (SearchEngine.doInitialNoteIndexing_), the triggers fill notes_fts
INSERT INTO notes_normalized(id, title, body, user_created_time, user_updated_time, is_todo, todo_completed, todo_due, parent_id, latitude, longitude, altitude, source_url)
SELECT id, lower(title), lower(body), user_created_time, user_updated_time, is_todo, todo_completed, todo_due, parent_id, latitude, longitude, altitude, source_url
FROM notes WHERE is_conflict = 0 AND encryption_applied = 0 AND is_locked = 0 AND deleted_time = 0;

INSERT INTO items_normalized(item_id, item_type, title, body, user_updated_time)
SELECT id, 4, lower(title), lower(ocr_text), updated_time FROM resources WHERE ocr_text != '' AND ocr_status = 2;

DROP TABLE _w;
COMMIT;
