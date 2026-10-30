-- Synthetic data for Trilium. Deterministic (no random()): values come from multiplicative hashes of the row number,
-- with different bit ranges per column. _cfg.scale multiplies the row counts. At scale 1: 20k notes in an 8-ary tree
-- under root (depth ~5) plus _hidden/_share, ~33k branches (10% clones), ~55k attributes, ~30k revisions, ~6k
-- attachments, ~60k blobs, ~190k entity_changes, 120 options, 500 recent notes.
-- IDs follow Trilium's shapes: 12-char random-looking note IDs whose first character (the sync "sector") varies,
-- branchId = parentNoteId || '_' || noteId, dates as 'YYYY-MM-DD HH:MM:SS.sssZ' (UTC) / '...+0100' (local).
BEGIN;

CREATE TEMP TABLE _a AS SELECT 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' AS a,
  'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Trilium keeps hierarchical notes with clones, attributes and revisions. '
  || 'Meeting notes for the quarterly planning review: budget, roadmap, hiring and the migration of the sync server. '
  || 'TODO: follow up with the design team about the canvas export and the mermaid diagram renderer. '
  || 'Recipe: two cups of flour, one egg, a pinch of salt; bake for twenty minutes at 180 degrees. '
  || 'Reading list: The Pragmatic Programmer, Designing Data-Intensive Applications, Structure and Interpretation. '
  || 'Journal: walked along the river, wrote some code for the calendar widget, fixed the protected session timeout. ' AS lorem;

-- note index i -> noteId, parent index p (8-ary heap: p = (i-1)/8, 0 = root)
CREATE TEMP TABLE _n AS
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20000*(SELECT scale FROM _cfg))
SELECT i, (i * 2654435761) % 4294967296 AS h, (i - 1) / 8 AS p,
       substr((SELECT a FROM _a), ((i * 2654435761) % 4294967296) % 62 + 1, 1) || printf('%011d', i) AS noteId
FROM n;
CREATE UNIQUE INDEX temp._n_i ON _n(i);
INSERT INTO _n(i, h, p, noteId) VALUES (0, 0, NULL, 'root');

-- deleted: whole sibling groups whose parent hashes to 0 mod 23 (one deleteId per group)
CREATE TEMP TABLE _nd AS
SELECT c.i, c.h, c.p, c.noteId, par.noteId AS parentNoteId,
       CASE WHEN c.i > 0 AND c.p > 0 AND (par.h / 131) % 23 = 0 THEN 1 ELSE 0 END AS isDeleted,
       CASE WHEN c.i > 0 AND c.p > 0 AND (par.h / 131) % 23 = 0 THEN 'del' || printf('%09d', c.p) END AS deleteId,
       1735689600 + c.i * 1300 / (SELECT scale FROM _cfg) AS ts
FROM _n c LEFT JOIN _n par ON par.i = c.p;
CREATE UNIQUE INDEX temp._nd_i ON _nd(i);
-- deleting a note deletes its subtree under the same deleteId: propagate two levels down
UPDATE _nd SET isDeleted = 1, deleteId = (SELECT par.deleteId FROM _nd par WHERE par.i = _nd.p)
WHERE isDeleted = 0 AND (SELECT par.isDeleted FROM _nd par WHERE par.i = _nd.p) = 1;
UPDATE _nd SET isDeleted = 1, deleteId = (SELECT par.deleteId FROM _nd par WHERE par.i = _nd.p)
WHERE isDeleted = 0 AND (SELECT par.isDeleted FROM _nd par WHERE par.i = _nd.p) = 1;

-- blobs for note bodies (book notes share one empty blob)
INSERT INTO blobs(blobId, content, textRepresentation, dateModified, utcDateModified)
SELECT substr(noteId, 1, 1) || 'B' || printf('%010d', i),
       '<p>' || printf('Note %d. ', i) || substr((SELECT lorem FROM _a), 1 + (h / 4096) % 200, 60 + (h / 64) % 300) || '</p>'
         || CASE WHEN (h / 1024) % 4 = 0 THEN '<ul><li>' || substr((SELECT lorem FROM _a), 1 + (h / 8) % 300, 80) || '</li></ul>' ELSE '' END,
       NULL,
       strftime('%Y-%m-%d %H:%M:%S.000+0100', ts + 3600 + (h / 16) % 2592000, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%S.000Z', ts + (h / 16) % 2592000, 'unixepoch')
FROM _nd;
INSERT INTO blobs VALUES ('Bempty', '', NULL, '2025-01-01 01:00:00.000+0100', '2025-01-01 00:00:00.000Z');

INSERT INTO notes(noteId, title, isProtected, type, mime, blobId, isDeleted, deleteId, dateCreated, dateModified, utcDateCreated, utcDateModified)
SELECT noteId,
       CASE WHEN i = 0 THEN 'root' ELSE
         (CASE (h / 2048) % 8 WHEN 0 THEN 'Meeting ' WHEN 1 THEN 'Idea ' WHEN 2 THEN 'Journal ' WHEN 3 THEN 'Recipe '
              WHEN 4 THEN 'Book ' WHEN 5 THEN 'Project ' WHEN 6 THEN 'Todo ' ELSE 'Reference ' END) || i END,
       CASE WHEN (h / 97) % 40 = 0 THEN 1 ELSE 0 END,
       t.type, t.mime,
       CASE WHEN t.type = 'book' THEN 'Bempty' ELSE substr(noteId, 1, 1) || 'B' || printf('%010d', i) END,
       isDeleted, deleteId,
       strftime('%Y-%m-%d %H:%M:%S.000+0100', ts + 3600, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%S.000+0100', ts + 3600 + (h / 16) % 2592000, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%S.000Z', ts, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%S.000Z', ts + (h / 16) % 2592000, 'unixepoch')
FROM _nd JOIN (SELECT column1 AS k, column2 AS type, column3 AS mime FROM (VALUES (0,'text','text/html'),(1,'text','text/html'),(2,'text','text/html'),(3,'text','text/html'),(4,'text','text/html'),
                      (5,'text','text/html'),(6,'text','text/html'),(7,'text','text/html'),(8,'text','text/html'),(9,'text','text/html'),
                      (10,'code','text/x-python'),(11,'code','application/javascript;env=frontend'),(12,'file','application/pdf'),
                      (13,'image','image/png'),(14,'book',''),(15,'search','application/json'),(16,'relationMap','application/json'),
                      (17,'canvas','application/json'),(18,'mermaid','text/mermaid'),(19,'text','text/html'))) AS t
  ON t.k = CASE WHEN i = 0 THEN 0 ELSE (h / 7) % 20 END;

-- system notes
INSERT INTO notes VALUES ('_hidden', 'Hidden Notes', 0, 'doc', '', 'Bempty', 0, NULL, '2025-01-01 01:00:00.000+0100', '2025-01-01 01:00:00.000+0100', '2025-01-01 00:00:00.000Z', '2025-01-01 00:00:00.000Z');
INSERT INTO notes VALUES ('_share', 'Shared Notes', 0, 'doc', '', 'Bempty', 0, NULL, '2025-01-01 01:00:00.000+0100', '2025-01-01 01:00:00.000+0100', '2025-01-01 00:00:00.000Z', '2025-01-01 00:00:00.000Z');

-- primary branches
INSERT INTO branches(branchId, noteId, parentNoteId, notePosition, prefix, isExpanded, isDeleted, deleteId, utcDateModified)
SELECT parentNoteId || '_' || noteId, noteId, parentNoteId, 10 * ((i - 1) % 8 + 1),
       CASE WHEN (h / 3001) % 50 = 0 THEN 'Archive' END,
       CASE WHEN (h / 5) % 4 = 0 THEN 1 ELSE 0 END, isDeleted, deleteId,
       strftime('%Y-%m-%d %H:%M:%S.000Z', ts, 'unixepoch')
FROM _nd WHERE i > 0;
INSERT INTO branches VALUES ('none_root', 'root', 'none', 0, NULL, 1, 0, NULL, '2025-01-01 00:00:00.000Z');
INSERT INTO branches VALUES ('root__hidden', '_hidden', 'root', 999999999, NULL, 0, 0, NULL, '2025-01-01 00:00:00.000Z');
INSERT INTO branches VALUES ('_hidden__share', '_share', '_hidden', 10, NULL, 0, 0, NULL, '2025-01-01 00:00:00.000Z');
-- shared subtrees: clones of three second-level notes into _share
INSERT INTO branches SELECT '_share_' || noteId, noteId, '_share', 10 * i, NULL, 0, 0, NULL, '2025-02-01 00:00:00.000Z'
FROM _nd WHERE i IN (9, 10, 11);
-- clones (10% of notes get a second parent elsewhere)
INSERT OR IGNORE INTO branches(branchId, noteId, parentNoteId, notePosition, prefix, isExpanded, isDeleted, deleteId, utcDateModified)
SELECT par.noteId || '_' || c.noteId, c.noteId, par.noteId, 1000 + (c.h / 77) % 90 * 10, CASE WHEN (c.h / 9) % 3 = 0 THEN 'clone' END,
       0, 0, NULL, strftime('%Y-%m-%d %H:%M:%S.000Z', c.ts + 86400, 'unixepoch')
FROM _nd c JOIN _nd par ON par.i = (c.h / 3) % c.i
WHERE c.i > 1 AND (c.h / 1999) % 10 = 0 AND c.isDeleted = 0 AND par.isDeleted = 0 AND par.i <> c.p;
-- a handful of duplicate branches (what the consistency check repairs)
INSERT INTO branches SELECT branchId || '_dup', noteId, parentNoteId, notePosition, prefix, isExpanded, 0, NULL, utcDateModified
FROM branches WHERE parentNoteId <> 'none' AND isDeleted = 0 AND rowid % 4999 = 7;

-- attributes: up to 3 slots per note, ~60% filled; kind picked from different hash bits per slot
INSERT INTO attributes(attributeId, noteId, type, name, value, position, utcDateModified, isDeleted, deleteId, isInheritable)
SELECT 'A' || printf('%011d', x.i * 3 + x.k), x.noteId,
       CASE WHEN x.kind >= 6 THEN 'relation' ELSE 'label' END,
       CASE x.kind WHEN 0 THEN 'iconClass' WHEN 1 THEN 'dateNote' WHEN 2 THEN 'todo' WHEN 3 THEN 'priority' WHEN 4 THEN 'color'
                   WHEN 5 THEN 'archived' WHEN 6 THEN 'internalLink' WHEN 7 THEN 'imageLink' ELSE 'template' END,
       CASE x.kind WHEN 0 THEN 'bx bx-' || CASE (x.h / 5) % 4 WHEN 0 THEN 'book' WHEN 1 THEN 'calendar' WHEN 2 THEN 'code' ELSE 'star' END
                   WHEN 1 THEN substr(x.dc, 1, 10)
                   WHEN 2 THEN '' WHEN 3 THEN CAST((x.h / 7) % 5 AS TEXT) WHEN 4 THEN '#' || printf('%06x', x.h % 16777216)
                   WHEN 5 THEN ''
                   ELSE (SELECT t.noteId FROM _n t WHERE t.i = (x.h / (x.k + 13)) % (SELECT count(*) FROM _n)) END,
       10 * x.k, x.um, x.isDeleted, x.deleteId,
       CASE WHEN x.kind IN (0, 8) AND (x.h / 11) % 3 = 0 THEN 1 ELSE 0 END
FROM (SELECT n.*, notes.dateCreated AS dc, notes.utcDateModified AS um, k.k,
             (n.h / (1 << (4 + k.k * 5))) % 9 AS kind, (n.h / (1 << (2 + k.k * 7))) % 10 AS keep
      FROM _nd n JOIN notes USING (noteId) JOIN (SELECT column1 AS k FROM (VALUES (0),(1),(2))) AS k WHERE n.i > 0) x
WHERE x.keep < 6;
-- an extra dateNote label on every journal-ish note so the calendar month query has dense hits
INSERT INTO attributes(attributeId, noteId, type, name, value, position, utcDateModified, isDeleted, deleteId, isInheritable)
SELECT 'D' || printf('%011d', _nd.i), notes.noteId, 'label', 'dateNote', substr(notes.dateCreated, 1, 10), 50, notes.utcDateModified,
       notes.isDeleted, notes.deleteId, 0
FROM notes JOIN _nd USING (noteId) WHERE notes.title LIKE 'Journal %';

-- revisions: half of the notes have 0-4 snapshots; a third of them reuse the note's blob (unchanged content)
CREATE TEMP TABLE _r AS
SELECT n.i, n.noteId, n.h, k.k, n.ts, notes.title, notes.type, notes.mime, notes.isProtected, notes.blobId AS noteBlob,
       ((n.i * 8 + k.k) * 2246822519) % 4294967296 AS rh
FROM _nd n JOIN notes USING (noteId) JOIN (SELECT column1 AS k FROM (VALUES (0),(1),(2),(3))) AS k
WHERE n.i > 0 AND (n.h / 11) % 2 = 0 AND k.k < (n.h / 13) % 5;
INSERT INTO blobs(blobId, content, textRepresentation, dateModified, utcDateModified)
SELECT substr((SELECT a FROM _a), rh % 62 + 1, 1) || 'R' || printf('%010d', i * 8 + k),
       '<p>' || printf('Note %d, revision %d. ', i, k) || substr((SELECT lorem FROM _a), 1 + (rh / 4096) % 200, 40 + (rh / 64) % 240) || '</p>',
       NULL,
       strftime('%Y-%m-%d %H:%M:%S.000+0100', ts + 3600 + (k + 1) * 86400, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%S.000Z', ts + (k + 1) * 86400, 'unixepoch')
FROM _r WHERE (rh / 32) % 3 <> 0;
INSERT INTO revisions(revisionId, noteId, type, mime, title, description, source, isProtected, blobId,
                      utcDateLastEdited, utcDateCreated, utcDateModified, dateLastEdited, dateCreated)
SELECT 'V' || printf('%011d', i * 8 + k), noteId, type, mime, title,
       CASE WHEN (rh / 1024) % 10 = 0 THEN 'before cleanup' ELSE '' END,
       CASE WHEN (rh / 1024) % 10 = 0 THEN 'manual' ELSE 'auto' END,
       isProtected,
       CASE WHEN (rh / 32) % 3 = 0 THEN noteBlob ELSE substr((SELECT a FROM _a), rh % 62 + 1, 1) || 'R' || printf('%010d', i * 8 + k) END,
       strftime('%Y-%m-%d %H:%M:%S.000Z', ts + (k + 1) * 86400 - 60, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%S.000Z', ts + (k + 1) * 86400, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%S.000Z', ts + (k + 1) * 86400, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%S.000+0100', ts + 3600 + (k + 1) * 86400 - 60, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%S.000+0100', ts + 3600 + (k + 1) * 86400, 'unixepoch')
FROM _r;

-- attachments: images on ~1/6 of the notes (1-2 each), plus some on revisions
CREATE TEMP TABLE _at AS
SELECT 'T' || printf('%011d', n.i * 2 + k.k) AS attachmentId, n.noteId AS ownerId, n.i, n.h, k.k, n.ts,
       ((n.i * 2 + k.k) * 3266489917) % 4294967296 AS ah, n.isDeleted AS ownerDeleted, n.deleteId
FROM _nd n JOIN (SELECT column1 AS k FROM (VALUES (0),(1))) AS k
WHERE n.i > 0 AND (n.h / 17) % 6 = 0 AND k.k <= (n.h / 19) % 2
UNION ALL
SELECT 'U' || printf('%011d', rowid), 'V' || printf('%011d', i * 8 + k), i, h, 0, ts, (rowid * 3266489917) % 4294967296, 0, NULL
FROM _r WHERE (rh / 4096) % 25 = 0;
INSERT INTO blobs(blobId, content, textRepresentation, dateModified, utcDateModified)
SELECT substr((SELECT a FROM _a), ah % 62 + 1, 1) || 'I' || attachmentId, 'PNG' || substr((SELECT lorem FROM _a), 1 + (ah / 8) % 300, 100 + (ah / 512) % 250),
       CASE WHEN (ah / 128) % 4 = 0 THEN 'scanned text: ' || substr((SELECT lorem FROM _a), 1 + (ah / 16) % 300, 60) END,
       strftime('%Y-%m-%d %H:%M:%S.000+0100', ts + 7200, 'unixepoch'), strftime('%Y-%m-%d %H:%M:%S.000Z', ts + 3600, 'unixepoch')
FROM _at;
INSERT INTO attachments(attachmentId, ownerId, role, mime, title, isProtected, position, blobId, dateModified, utcDateModified,
                        utcDateScheduledForErasureSince, isDeleted, deleteId)
SELECT attachmentId, ownerId, CASE WHEN (ah / 64) % 5 = 0 THEN 'file' ELSE 'image' END,
       CASE WHEN (ah / 64) % 5 = 0 THEN 'application/pdf' ELSE 'image/png' END,
       printf('image-%d.png', i * 2 + k), 0, 10 * k, substr((SELECT a FROM _a), ah % 62 + 1, 1) || 'I' || attachmentId,
       strftime('%Y-%m-%d %H:%M:%S.000+0100', ts + 7200, 'unixepoch'), strftime('%Y-%m-%d %H:%M:%S.000Z', ts + 3600, 'unixepoch'),
       CASE WHEN (ah / 2048) % 10 = 0 THEN strftime('%Y-%m-%d %H:%M:%S.000Z', ts + 864000, 'unixepoch') END,
       CASE WHEN ownerDeleted = 1 OR (ah / 65536) % 20 = 0 THEN 1 ELSE 0 END,
       CASE WHEN ownerDeleted = 1 THEN deleteId WHEN (ah / 65536) % 20 = 0 THEN 'att' || printf('%09d', i) END
FROM _at;

-- unreferenced blobs left behind by edits (what eraseUnusedBlobs collects)
INSERT INTO blobs(blobId, content, textRepresentation, dateModified, utcDateModified)
SELECT 'X' || printf('%011d', i), '<p>stale draft ' || i || '</p>', NULL, '2025-06-01 10:00:00.000+0100', '2025-06-01 09:00:00.000Z'
FROM _nd WHERE i > 0 AND (h / 23) % 100 = 0;

INSERT INTO options(name, value, isSynced, utcDateModified)
SELECT 'option' || i, CAST((i * 2654435761) % 1000 AS TEXT), i % 3 = 0, '2025-01-01 00:00:00.000Z'
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 118) SELECT i FROM n);
INSERT INTO etapi_tokens VALUES ('tok1', 'backup script', 'h1', '2025-01-01 00:00:00.000Z', '2025-01-01 00:00:00.000Z', 0),
                                ('tok2', 'phone', 'h2', '2025-02-01 00:00:00.000Z', '2025-02-01 00:00:00.000Z', 0),
                                ('tok3', 'old', 'h3', '2025-03-01 00:00:00.000Z', '2025-03-01 00:00:00.000Z', 1);

-- entity_changes: one per entity in creation order, as the app writes them
INSERT INTO entity_changes(entityName, entityId, hash, isErased, changeId, componentId, instanceId, isSynced, utcDateChanged)
SELECT entityName, entityId, printf('%08x', (rn * 2654435761) % 4294967296) || 'hash', 0,
       printf('%012x', (rn * 3266489917) % 281474976710655), CASE WHEN rn % 3 = 0 THEN 'NA' ELSE 'c' || (rn % 50) END,
       CASE WHEN (rn / 7) % 4 = 0 THEN 'otherInstance' ELSE 'thisInstance1' END, isSynced, d
FROM (SELECT row_number() OVER (ORDER BY d, entityName, entityId) AS rn, * FROM (
        SELECT 'notes' AS entityName, noteId AS entityId, 1 AS isSynced, utcDateModified AS d FROM notes
        UNION ALL SELECT 'blobs', blobId, 1, utcDateModified FROM blobs
        UNION ALL SELECT 'branches', branchId, 1, utcDateModified FROM branches
        UNION ALL SELECT 'attributes', attributeId, 1, utcDateModified FROM attributes WHERE rowid % 997 <> 5
        UNION ALL SELECT 'revisions', revisionId, 1, utcDateModified FROM revisions
        UNION ALL SELECT 'attachments', attachmentId, 1, utcDateModified FROM attachments
        UNION ALL SELECT 'options', name, isSynced, utcDateModified FROM options
        UNION ALL SELECT 'etapi_tokens', etapiTokenId, 1, utcDateModified FROM etapi_tokens
        UNION ALL SELECT 'note_reordering', noteId, 1, strftime('%Y-%m-%d %H:%M:%S.000Z', ts + 7200, 'unixepoch') FROM _nd WHERE (h / 29) % 40 = 0));
-- entities erased long ago (rows gone, change kept with isErased = 1)
INSERT INTO entity_changes(entityName, entityId, hash, isErased, changeId, componentId, instanceId, isSynced, utcDateChanged)
SELECT CASE i % 3 WHEN 0 THEN 'notes' WHEN 1 THEN 'branches' ELSE 'attributes' END, 'erased' || printf('%06d', i),
       'deadbeef', 1, printf('e%011d', i), 'NA', 'thisInstance1', 1, '2025-11-20 00:00:00.000Z'
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300) SELECT i FROM n);

INSERT INTO options(name, value, isSynced, utcDateModified)
VALUES ('lastSyncedPush', CAST((SELECT max(id) - 4000 FROM entity_changes) AS TEXT), 0, '2025-11-20 00:00:00.000Z'),
       ('lastSyncedPull', CAST((SELECT max(id) - 9000 FROM entity_changes) AS TEXT), 0, '2025-11-20 00:00:00.000Z');

-- recent notes: live notes picked by hash among the newest, with their full tree path from root
INSERT INTO recent_notes(noteId, notePath, utcDateCreated)
WITH RECURSIVE pick AS (
  SELECT i, noteId, h, ts FROM _nd c WHERE c.isDeleted = 0 AND c.i > 0 AND (c.h / 37) % 20 = 0 ORDER BY c.i DESC LIMIT 500),
up(i, cur, path) AS (
  SELECT pick.i, _nd.p, pick.noteId FROM pick JOIN _nd ON _nd.i = pick.i
  UNION ALL
  SELECT up.i, par.p, par.noteId || '/' || up.path FROM up JOIN _nd par ON par.i = up.cur WHERE up.cur IS NOT NULL)
SELECT pick.noteId, up.path, strftime('%Y-%m-%d %H:%M:%S.000Z', pick.ts + (pick.h / 16) % 86400, 'unixepoch')
FROM pick JOIN up ON up.i = pick.i AND up.cur IS NULL;

ANALYZE;

-- param_list as fillParamList() leaves it for the subtree of the 3rd top-level note
INSERT INTO param_list(paramId)
WITH RECURSIVE tree(noteId) AS (SELECT noteId FROM _n WHERE i = 3
  UNION SELECT branches.noteId FROM branches JOIN tree ON branches.parentNoteId = tree.noteId WHERE branches.isDeleted = 0)
SELECT noteId FROM tree;

-- blob_usage as withBlobUsage() fills it (services/space_usage.ts:520-532)
INSERT INTO blob_usage (blobId, size, kind)
SELECT blobs.blobId, COALESCE(octet_length(blobs.content), 0),
       CASE
           WHEN blobs.blobId IN (SELECT blobId FROM notes WHERE isDeleted = 0 AND blobId IS NOT NULL) THEN 4
           WHEN blobs.blobId IN (SELECT attachments.blobId FROM attachments JOIN notes ON notes.noteId = attachments.ownerId
                                 WHERE attachments.isDeleted = 0 AND notes.isDeleted = 0 AND attachments.blobId IS NOT NULL) THEN 3
           WHEN blobs.blobId IN (SELECT revisions.blobId FROM revisions JOIN notes ON notes.noteId = revisions.noteId
                                 WHERE notes.isDeleted = 0 AND revisions.blobId IS NOT NULL
                                 UNION SELECT attachments.blobId FROM attachments JOIN revisions ON revisions.revisionId = attachments.ownerId
                                 JOIN notes ON notes.noteId = revisions.noteId
                                 WHERE attachments.isDeleted = 0 AND notes.isDeleted = 0 AND attachments.blobId IS NOT NULL) THEN 2
           WHEN blobs.blobId IN (SELECT blobId FROM notes WHERE isDeleted = 1 AND blobId IS NOT NULL
                                 UNION SELECT blobId FROM attachments WHERE isDeleted = 1 AND blobId IS NOT NULL
                                 UNION SELECT revisions.blobId FROM revisions JOIN notes ON notes.noteId = revisions.noteId
                                 WHERE notes.isDeleted = 1 AND revisions.blobId IS NOT NULL) THEN 1
           ELSE 0
       END
FROM blobs;

COMMIT;
