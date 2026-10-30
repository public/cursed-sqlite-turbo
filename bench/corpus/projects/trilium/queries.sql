-- Trilium Notes (TriliumNext/Trilium @ 5285da2, AGPL-3.0). better-sqlite3 with `?` placeholders (a few named @x).
-- The server code lives in packages/trilium-core/src (shared by server and desktop) and apps/server/src. Most reads
-- of the note tree happen in memory (becca); the SQL is the cache load, sync, recent changes, revisions, sizes and
-- consistency checks. `???` placeholders (getManyRows) and ${...} fragments are resolved to one instantiation.

-- @id trilium.becca_load.notes_bulk
-- @src packages/trilium-core/src/becca/becca_loader.ts:44-45
-- @style no params; text built by getRawRowsBulk() (services/sql/sql.ts:264) from NOTE_COLUMNS (becca_loader.ts:87)
-- @tags hotpath,dynamic
-- @note Startup cache load: the whole live notes table aggregated into one JSON document of positional arrays (json_group_array(json_array(...))).
SELECT json_group_array(json_array(noteId, title, type, mime, isProtected, blobId, dateCreated, dateModified, utcDateCreated, utcDateModified))
FROM notes WHERE isDeleted = 0;

-- @id trilium.share.subtree_recursive
-- @src packages/trilium-core/src/share/shaca/shaca_loader.ts:18-30
-- @style ? positional
-- @tags hotpath
-- @note Share cache load: recursive CTE (UNION, so clones are visited once) over branches from the share root.
-- @param ?1 '_share'
WITH RECURSIVE
tree(noteId) AS (
    SELECT ?1
    UNION
    SELECT branches.noteId FROM branches
    JOIN tree ON branches.parentNoteId = tree.noteId
    WHERE branches.isDeleted = 0
)
SELECT noteId FROM tree;

-- @id trilium.share.branches_in_list
-- @src packages/trilium-core/src/share/shaca/shaca_loader.ts:44-49
-- @style literal IN list spliced from the subtree note IDs
-- @tags dynamic
-- @note Branches of the shared subtree: long literal IN list on parentNoteId, ordered by notePosition (25 IDs here; the app splices the whole subtree).
SELECT branchId, noteId, parentNoteId, prefix, isExpanded, utcDateModified
FROM branches
WHERE isDeleted = 0
AND parentNoteId IN ('_share','Z00000000009','W00000000010','X00000000011','r00000000073','s00000000074','p00000000075','q00000000076','n00000000077','k00000000078','l00000000079','i00000000080','n00000007069','f00000000081','g00000000082','d00000000083','e00000000084','b00000000085','800000000086','900000000087','600000000088','R00000000013','300000000089','400000000090','100000000091')
ORDER BY notePosition;

-- @id trilium.recent_changes.revisions
-- @src packages/trilium-core/src/routes/api/recent_changes.ts:21-32
-- @style no params
-- @tags hotpath
-- @note Recent Changes page: every revision joined to its note via USING (the ancestor filter and top-500 cut happen in JS).
SELECT
    notes.noteId,
    notes.isDeleted AS current_isDeleted,
    notes.deleteId AS current_deleteId,
    notes.title AS current_title,
    notes.isProtected AS current_isProtected,
    revisions.title,
    revisions.utcDateCreated AS utcDate,
    revisions.dateCreated AS date
FROM
    revisions
    JOIN notes USING(noteId);

-- @id trilium.etapi.recent_changes_root
-- @src apps/server/src/etapi/revisions.ts:22-59
-- @style no params
-- @tags hotpath
-- @note ETAPI recent changes for root: three-way UNION ALL (revisions, creations, deletions) sorted by a result alias, top 500.
SELECT
    notes.noteId,
    notes.isDeleted AS current_isDeleted,
    notes.deleteId AS current_deleteId,
    notes.title AS current_title,
    notes.isProtected AS current_isProtected,
    revisions.title,
    revisions.utcDateCreated AS utcDate,
    revisions.dateCreated AS date
FROM revisions
JOIN notes USING(noteId)
UNION ALL
SELECT
    notes.noteId,
    notes.isDeleted AS current_isDeleted,
    notes.deleteId AS current_deleteId,
    notes.title AS current_title,
    notes.isProtected AS current_isProtected,
    notes.title,
    notes.utcDateCreated AS utcDate,
    notes.dateCreated AS date
FROM notes
UNION ALL
SELECT
    notes.noteId,
    notes.isDeleted AS current_isDeleted,
    notes.deleteId AS current_deleteId,
    notes.title AS current_title,
    notes.isProtected AS current_isProtected,
    notes.title,
    notes.utcDateModified AS utcDate,
    notes.dateModified AS date
FROM notes
WHERE notes.isDeleted = 1
ORDER BY utcDate DESC
LIMIT 500;

-- @id trilium.etapi.recent_changes_subtree
-- @src apps/server/src/etapi/revisions.ts:63-108
-- @style ? positional
-- @tags hotpath
-- @note Recent changes under an ancestor: recursive descendants CTE (including deleted branches) feeding three IN-subquery arms of a UNION ALL, top 500.
-- @param ?1 '900000000003'
WITH RECURSIVE descendants(noteId) AS (
    SELECT ?1
    UNION
    SELECT branches.noteId
    FROM branches
    JOIN descendants ON branches.parentNoteId = descendants.noteId
)
SELECT
    notes.noteId,
    notes.isDeleted AS current_isDeleted,
    notes.deleteId AS current_deleteId,
    notes.title AS current_title,
    notes.isProtected AS current_isProtected,
    revisions.title,
    revisions.utcDateCreated AS utcDate,
    revisions.dateCreated AS date
FROM revisions
JOIN notes USING(noteId)
WHERE notes.noteId IN (SELECT noteId FROM descendants)
UNION ALL
SELECT
    notes.noteId,
    notes.isDeleted AS current_isDeleted,
    notes.deleteId AS current_deleteId,
    notes.title AS current_title,
    notes.isProtected AS current_isProtected,
    notes.title,
    notes.utcDateCreated AS utcDate,
    notes.dateCreated AS date
FROM notes
WHERE notes.noteId IN (SELECT noteId FROM descendants)
UNION ALL
SELECT
    notes.noteId,
    notes.isDeleted AS current_isDeleted,
    notes.deleteId AS current_deleteId,
    notes.title AS current_title,
    notes.isProtected AS current_isProtected,
    notes.title,
    notes.utcDateModified AS utcDate,
    notes.dateModified AS date
FROM notes
WHERE notes.isDeleted = 1 AND notes.noteId IN (SELECT noteId FROM descendants)
ORDER BY utcDate DESC
LIMIT 500;

-- @id trilium.sync.pull_page
-- @src packages/trilium-core/src/routes/api/sync.ts:186-195
-- @style ? positional
-- @tags hotpath
-- @note Sync server pull endpoint: next 1000 synced entity changes after the client's cursor (index range on isSynced, id).
-- @param ?1 130000
SELECT *
FROM entity_changes
WHERE isSynced = 1
AND id > ?1
ORDER BY id
LIMIT 1000;

-- @id trilium.sync.pending_push_exists
-- @src packages/trilium-core/src/services/sync.ts:565
-- @style ? positional
-- @tags hotpath,hot-small
-- @note Before the content-hash check: is anything still waiting to be pushed? EXISTS over an index range.
-- @param ?1 142260
SELECT EXISTS(SELECT 1 FROM entity_changes WHERE isSynced = 1 AND id > ?1);

-- @id trilium.entity_changes.sector
-- @src packages/trilium-core/src/services/entity_changes.ts:128
-- @style ? positional
-- @note Re-queue one sync sector after a hash mismatch: entity changes of one type whose ID starts with the sector character (SUBSTR predicate, not indexable).
-- @param ?1 'notes'
-- @param ?2 'B'
SELECT * FROM entity_changes WHERE entityName = ?1 AND SUBSTR(entityId, 1, 1) = ?2;

-- @id trilium.entity_changes.depending_entity
-- @src packages/trilium-core/src/services/entity_changes.ts:149-155
-- @style ? positional, table and key names spliced in (tableName = notes, primaryKeyColumn = noteId)
-- @tags dynamic
-- @note Blob sector mismatch: self-join of entity_changes through notes (blob -> owning note -> that note's change row), SUBSTR sector filter.
-- @param ?1 'B'
SELECT dep_change.*
FROM entity_changes orig_sector
JOIN notes ON notes.blobId = orig_sector.entityId
JOIN entity_changes dep_change ON dep_change.entityName = 'notes' AND dep_change.entityId = notes.noteId
WHERE orig_sector.entityName = 'blobs' AND SUBSTR(orig_sector.entityId, 1, 1) = ?1;

-- @id trilium.entity_changes.put
-- @src packages/trilium-core/src/services/entity_changes.ts:50-63
-- @style ? positional; text built by sql.insert(..., replace = true) (services/sql/sql.ts:87-104) from the object's keys
-- @tags hotpath,hot-small,dynamic
-- @note Every entity save writes its change row: INSERT OR REPLACE on the (entityName, entityId) unique index, 4 secondary indexes.
-- @param ?1 'notes'
-- @param ?2 'W00000000010'
-- @param ?3 'a1b2c3d4e5f6a7b8c9d0'
-- @param ?4 0
-- @param ?5 '2025-11-21 10:00:00.000Z'
-- @param ?6 1
-- @param ?7 'Xk3pQ9zLm2Aa'
-- @param ?8 'c17'
-- @param ?9 'thisInstance1'
INSERT
OR REPLACE INTO
entity_changes
(
entityName, entityId, hash, isErased, utcDateChanged, isSynced, changeId, componentId, instanceId
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9);

-- @id trilium.sync_update.change_applied
-- @src packages/trilium-core/src/services/sync_update.ts:33
-- @style ? positional
-- @tags hotpath,hot-small
-- @note Per pulled change: was this changeId already applied? Point lookup on IDX_entity_changes_changeId.
-- @param ?1 '024ef052d725'
SELECT 1 FROM entity_changes WHERE changeId = ?1;

-- @id trilium.sync_update.local_change
-- @src packages/trilium-core/src/services/sync_update.ts:86
-- @style ? positional
-- @tags hotpath,hot-small
-- @note Per pulled change: the local change row for the same entity, to compare utcDateChanged.
-- @param ?1 'branches'
-- @param ?2 'r00000000031_d00000000251'
SELECT * FROM entity_changes WHERE entityName = ?1 AND entityId = ?2;

-- @id trilium.entity.upsert_note
-- @src packages/trilium-core/src/becca/entities/abstract_becca_entity.ts:138
-- @style @named; text built by sql.upsert() (services/sql/sql.ts:114-128) from BNote.getPojo() keys (becca/entities/bnote.ts:1507)
-- @tags hotpath,hot-small,dynamic
-- @note Note save: INSERT ... ON CONFLICT (noteId) DO UPDATE SET every column, with named parameters reused in both lists.
-- @param @noteId 'W00000000010'
-- @param @title 'Project 10 (renamed)'
-- @param @isProtected 0
-- @param @type 'text'
-- @param @mime 'text/html'
-- @param @blobId 'WB0000000010'
-- @param @isDeleted 0
-- @param @dateCreated '2025-01-01 01:21:40.000+0100'
-- @param @dateModified '2025-11-21 11:00:00.000+0100'
-- @param @utcDateCreated '2025-01-01 00:21:40.000Z'
-- @param @utcDateModified '2025-11-21 10:00:00.000Z'
INSERT INTO notes (noteId, title, isProtected, type, mime, blobId, isDeleted, dateCreated, dateModified, utcDateCreated, utcDateModified)
VALUES (@noteId, @title, @isProtected, @type, @mime, @blobId, @isDeleted, @dateCreated, @dateModified, @utcDateCreated, @utcDateModified)
ON CONFLICT (noteId) DO UPDATE SET noteId = @noteId, title = @title, isProtected = @isProtected, type = @type, mime = @mime,
    blobId = @blobId, isDeleted = @isDeleted, dateCreated = @dateCreated, dateModified = @dateModified,
    utcDateCreated = @utcDateCreated, utcDateModified = @utcDateModified;

-- @id trilium.becca.get_attachment
-- @src packages/trilium-core/src/becca/becca-interface.ts:184-190
-- @style ? positional
-- @tags hotpath,hot-small
-- @note Attachment by ID with its content length: PK lookup joined to blobs via USING.
-- @param ?1 'T00000000002'
SELECT attachments.*, LENGTH(blobs.content) AS contentLength
FROM attachments
JOIN blobs USING (blobId)
WHERE attachmentId = ?1 AND isDeleted = 0;

-- @id trilium.revisions.list_for_note
-- @src packages/trilium-core/src/routes/api/revisions.ts:41-51
-- @style ? positional
-- @tags hotpath
-- @note Revisions dialog: a note's revisions with blob content lengths, newest first.
-- @param ?1 'W00000000010'
SELECT revisions.*,
        LENGTH(blobs.content) AS contentLength
FROM revisions
JOIN blobs ON revisions.blobId = blobs.blobId
WHERE revisions.noteId = ?1
ORDER BY revisions.utcDateCreated DESC;

-- @id trilium.revisions.edited_on_date
-- @src packages/trilium-core/src/routes/api/revisions.ts:210-226
-- @style :named
-- @tags hotpath
-- @note Day note's "edited notes" list: LIKE prefix on two local date columns OR'd, NOT LIKE with ESCAPE, UNION ALL with revisions inside IN, ordered top 50.
-- @param :date '2025-03-17%'
SELECT notes.*
FROM notes
WHERE noteId IN (
        SELECT noteId FROM notes
        WHERE
            (notes.dateCreated LIKE :date OR notes.dateModified LIKE :date)
            AND (notes.noteId NOT LIKE  '\_%' ESCAPE '\')
    UNION ALL
        SELECT noteId FROM revisions
        WHERE revisions.dateCreated LIKE :date
)
ORDER BY isDeleted
LIMIT 50;

-- @id trilium.calendar.day_notes_for_month
-- @src packages/trilium-core/src/routes/api/special_notes.ts:46-56
-- @style ? positional
-- @tags hotpath
-- @note Calendar widget: dateNote labels whose value starts with the month (LIKE ? || '%' on a bound parameter), joined to live notes.
-- @param ?1 '2025-03'
SELECT
    attr.value AS date,
    notes.noteId
FROM notes
JOIN attributes attr USING(noteId)
WHERE notes.isDeleted = 0
    AND attr.isDeleted = 0
    AND attr.type = 'label'
    AND attr.name = 'dateNote'
    AND attr.value LIKE ?1 || '%';

-- @id trilium.autocomplete.recent_notes
-- @src packages/trilium-core/src/routes/api/autocomplete.ts:49-73
-- @style ? positional; hoisted-note LIKE and LIMIT spliced in
-- @tags hotpath,dynamic
-- @note Jump-to-note dialog with a hoisted note: recent notes joined to live notes, notePath LIKE '%id%', newest 200.
-- @param ?1 'W00000000010'
-- @param ?2 '%w00000000028%'
SELECT
    recent_notes.*
FROM
    recent_notes
    JOIN notes USING(noteId)
WHERE
    notes.isDeleted = 0
    AND notes.noteId != ?1
    AND recent_notes.notePath LIKE ?2
ORDER BY
    utcDateCreated DESC
LIMIT 200;

-- @id trilium.notes.undeleted_parent_branches
-- @src packages/trilium-core/src/services/notes.ts:1458-1469
-- @style ? positional
-- @tags hotpath,hot-small
-- @note Per deleted row on the recent-changes page: can the note be undeleted? Deleted branches of the note whose parent is live.
-- @param ?1 'B00000000193'
-- @param ?2 'del000000024'
SELECT branches.branchId
FROM branches
JOIN notes AS parentNote ON parentNote.noteId = branches.parentNoteId
WHERE branches.noteId = ?1
AND branches.isDeleted = 1
AND branches.deleteId = ?2
AND parentNote.isDeleted = 0;

-- @id trilium.notes.undelete_child_branches
-- @src packages/trilium-core/src/services/notes.ts:1440-1448
-- @style ? positional
-- @note Undelete recursion step: the children deleted in the same operation (same deleteId).
-- @param ?1 'del000000024'
-- @param ?2 'B00000000193'
SELECT branches.branchId
FROM branches
WHERE branches.isDeleted = 1
AND branches.deleteId = ?1
AND branches.parentNoteId = ?2;

-- @id trilium.stats.note_size
-- @src packages/trilium-core/src/routes/api/stats.ts:9-19
-- @style ? positional
-- @tags hotpath
-- @note Note info widget: three LEFT JOINs with the parameter in each ON clause, OR of IS NOT NULL in WHERE (a full scan of blobs).
-- @param ?1 'W00000000010'
-- @param ?2 'W00000000010'
-- @param ?3 'W00000000010'
SELECT blobs.blobId, LENGTH(content)
FROM blobs
LEFT JOIN notes ON notes.blobId = blobs.blobId AND notes.noteId = ?1 AND notes.isDeleted = 0
LEFT JOIN attachments ON attachments.blobId = blobs.blobId AND attachments.ownerId = ?2 AND attachments.isDeleted = 0
LEFT JOIN revisions ON revisions.blobId = blobs.blobId AND revisions.noteId = ?3
WHERE notes.noteId IS NOT NULL
    OR attachments.attachmentId IS NOT NULL
    OR revisions.revisionId IS NOT NULL;

-- @id trilium.stats.subtree_size
-- @src packages/trilium-core/src/routes/api/stats.ts:35-41
-- @style no params; param_list pre-filled with the subtree note IDs (sql.fillParamList)
-- @tags hotpath
-- @note Subtree size: param_list driving two LEFT JOINs and a join to blobs on a three-way OR (multi-index OR).
SELECT blobs.blobId, LENGTH(content)
FROM param_list
JOIN notes ON notes.noteId = param_list.paramId AND notes.isDeleted = 0
LEFT JOIN attachments ON attachments.ownerId = param_list.paramId AND attachments.isDeleted = 0
LEFT JOIN revisions ON revisions.noteId = param_list.paramId
JOIN blobs ON blobs.blobId = notes.blobId OR blobs.blobId = attachments.blobId OR blobs.blobId = revisions.blobId;

-- @id trilium.space_usage.measure_blobs
-- @src packages/trilium-core/src/services/space_usage.ts:520-532
-- @style no params; the blob-set subqueries are ${...} constants (space_usage.ts:437-478) and kinds are inlined numbers
-- @note Content manager measuring pass: octet_length per blob and a CASE ladder of four IN-subqueries (two of them UNIONs over 3-way joins).
-- @modified the app runs this as INSERT INTO blob_usage (blobId, size, kind) SELECT ...; only the SELECT is kept because data.sql pre-fills blob_usage with the same statement
SELECT blobs.blobId,
       COALESCE(octet_length(blobs.content), 0),
       CASE
           WHEN blobs.blobId IN (SELECT blobId FROM notes WHERE isDeleted = 0 AND blobId IS NOT NULL) THEN 4
           WHEN blobs.blobId IN (
    SELECT attachments.blobId FROM attachments
    JOIN notes ON notes.noteId = attachments.ownerId
    WHERE attachments.isDeleted = 0 AND notes.isDeleted = 0 AND attachments.blobId IS NOT NULL) THEN 3
           WHEN blobs.blobId IN (
    SELECT revisions.blobId FROM revisions
    JOIN notes ON notes.noteId = revisions.noteId
    WHERE notes.isDeleted = 0 AND revisions.blobId IS NOT NULL
    UNION
    SELECT attachments.blobId FROM attachments
    JOIN revisions ON revisions.revisionId = attachments.ownerId
    JOIN notes ON notes.noteId = revisions.noteId
    WHERE attachments.isDeleted = 0 AND notes.isDeleted = 0 AND attachments.blobId IS NOT NULL) THEN 2
           WHEN blobs.blobId IN (
    SELECT blobId FROM notes WHERE isDeleted = 1 AND blobId IS NOT NULL
    UNION SELECT blobId FROM attachments WHERE isDeleted = 1 AND blobId IS NOT NULL
    UNION SELECT revisions.blobId FROM revisions
        JOIN notes ON notes.noteId = revisions.noteId
        WHERE notes.isDeleted = 1 AND revisions.blobId IS NOT NULL) THEN 1
           ELSE 0
       END
FROM blobs;

-- @id trilium.space_usage.collect_sizes
-- @src packages/trilium-core/src/services/space_usage.ts:370-403
-- @style no params
-- @note Per-note own/attachment/revision byte totals: four-arm UNION ALL of joins against blob_usage, then SUM ... GROUP BY noteId.
SELECT noteId,
       SUM(own) AS ownSize,
       SUM(attachment) AS attachmentsSize,
       SUM(revision) AS revisionsSize
FROM (
    SELECT notes.noteId AS noteId, blob_usage.size AS own, 0 AS attachment, 0 AS revision
    FROM notes
    JOIN blob_usage ON blob_usage.blobId = notes.blobId
    WHERE notes.isDeleted = 0

    UNION ALL
    SELECT attachments.ownerId, 0, blob_usage.size, 0
    FROM attachments
    JOIN blob_usage ON blob_usage.blobId = attachments.blobId
    WHERE attachments.isDeleted = 0

    UNION ALL
    SELECT revisions.noteId, 0, 0, blob_usage.size
    FROM revisions
    JOIN blob_usage ON blob_usage.blobId = revisions.blobId

    UNION ALL
    SELECT revisions.noteId, 0, 0, blob_usage.size
    FROM attachments
    JOIN revisions ON revisions.revisionId = attachments.ownerId
    JOIN blob_usage ON blob_usage.blobId = attachments.blobId
    WHERE attachments.isDeleted = 0
)
GROUP BY noteId;

-- @id trilium.space_usage.excess_revisions_size
-- @src packages/trilium-core/src/services/space_usage.ts:638-685
-- @style no params; snapshotsToKeep = 2 and keepNamedSnapshots = true spliced in, kinds inlined
-- @tags dynamic
-- @note "Erase excess revisions" estimate: ROW_NUMBER() OVER (PARTITION BY noteId) in a CTE that is referenced four times, IN/NOT IN over UNIONs.
WITH doomed AS (
        SELECT revisionId, blobId FROM (
            SELECT revisions.revisionId, revisions.blobId,
                   ROW_NUMBER() OVER (
                       PARTITION BY revisions.noteId
                       ORDER BY revisions.utcDateCreated DESC, revisions.revisionId DESC
                   ) AS age
            FROM revisions
            JOIN param_list ON param_list.paramId = revisions.noteId
            WHERE revisions.description IS NULL OR revisions.description = ''
        )
        WHERE age > 2)
SELECT SUM(blob_usage.size)
FROM blob_usage
WHERE blob_usage.blobId IN (
    SELECT blobId FROM doomed WHERE blobId IS NOT NULL
    UNION SELECT attachments.blobId FROM attachments
        JOIN doomed ON doomed.revisionId = attachments.ownerId
        WHERE attachments.isDeleted = 0 AND attachments.blobId IS NOT NULL
)
AND blob_usage.kind NOT IN (4, 3)
AND blob_usage.blobId NOT IN (
    SELECT revisions.blobId FROM revisions
    JOIN notes ON notes.noteId = revisions.noteId
    WHERE notes.isDeleted = 0 AND revisions.blobId IS NOT NULL
    AND revisions.revisionId NOT IN (SELECT revisionId FROM doomed)
    UNION
    SELECT attachments.blobId FROM attachments
    JOIN revisions ON revisions.revisionId = attachments.ownerId
    JOIN notes ON notes.noteId = revisions.noteId
    WHERE attachments.isDeleted = 0 AND notes.isDeleted = 0 AND attachments.blobId IS NOT NULL
    AND revisions.revisionId NOT IN (SELECT revisionId FROM doomed));

-- @id trilium.space_usage.unused_attachments_size
-- @src packages/trilium-core/src/services/space_usage.ts:722-731
-- @style no params; blob-set constants from space_usage.ts:457-478 spliced in, kind inlined
-- @note Reclaimable size of attachments scheduled for erasure: one IN and two NOT IN subqueries over joins, against the blob tags.
SELECT SUM(blob_usage.size)
FROM blob_usage
WHERE blob_usage.blobId IN (
    SELECT attachments.blobId FROM attachments
    JOIN notes ON notes.noteId = attachments.ownerId
    WHERE attachments.isDeleted = 0 AND notes.isDeleted = 0 AND attachments.blobId IS NOT NULL
    AND attachments.utcDateScheduledForErasureSince IS NOT NULL)
AND blob_usage.kind != 4
AND blob_usage.blobId NOT IN (
    SELECT attachments.blobId FROM attachments
    JOIN notes ON notes.noteId = attachments.ownerId
    WHERE attachments.isDeleted = 0 AND notes.isDeleted = 0 AND attachments.blobId IS NOT NULL
    AND attachments.utcDateScheduledForErasureSince IS NULL)
AND blob_usage.blobId NOT IN (
    SELECT revisions.blobId FROM revisions
    JOIN notes ON notes.noteId = revisions.noteId
    WHERE notes.isDeleted = 0 AND revisions.blobId IS NOT NULL
    UNION
    SELECT attachments.blobId FROM attachments
    JOIN revisions ON revisions.revisionId = attachments.ownerId
    JOIN notes ON notes.noteId = revisions.noteId
    WHERE attachments.isDeleted = 0 AND notes.isDeleted = 0 AND attachments.blobId IS NOT NULL);

-- @id trilium.search.revision_content_lengths
-- @src packages/trilium-core/src/services/search/services/search.ts:241-261
-- @style no params
-- @note Search "orderBy revisionsSize" prep: UNION ALL of a 3-way and a 4-way join (notes, revisions, attachments, blobs) with LENGTH(content).
SELECT
    noteId,
    revisions.blobId,
    LENGTH(content) AS length,
    1 AS isNoteRevision
FROM notes
    JOIN revisions USING(noteId)
    JOIN blobs ON revisions.blobId = blobs.blobId
WHERE notes.isDeleted = 0
UNION ALL
SELECT
    noteId,
    revisions.blobId,
    LENGTH(content) AS length,
    0 AS isNoteRevision -- it's attachment not counting towards revision count
FROM notes
    JOIN revisions USING(noteId)
    JOIN attachments ON attachments.ownerId = revisions.revisionId
    JOIN blobs ON attachments.blobId = blobs.blobId
WHERE notes.isDeleted = 0;

-- @id trilium.search.fulltext_candidates
-- @src packages/trilium-core/src/services/search/expressions/note_content_fulltext.ts:107-113
-- @style ? positional (a JSON array of note IDs); type list and size limit spliced in
-- @tags hotpath,dynamic
-- @note Full-text search content pass: notes JOIN blobs filtered by a type IN list, LENGTH(content) and noteId IN json_each(?) of the candidate set.
-- @param ?1 '["q00000000160","900000000171","700000000173","S00000000182","Q00000000184","O00000000186","Q00000000100","K00000000102","I00000000104","G00000000106","E00000000108","B00000000109","C00000000110","z00000000111","x00000000113","r00000000115","p00000000117","n00000000119","k00000000120","l00000000121","i00000000122","g00000000124","e00000000126","800000000128","600000000130","400000000132","100000000133","200000000134","Z00000000135","X00000000137","V00000000139","P00000000141","N00000000143","L00000000145","I00000000146","J00000000147","G00000000148","E00000000150","C00000000152","w00000000154","u00000000156","r00000000157","s00000000158","p00000000159","n00000000161","l00000000163","j00000000165","d00000000167","b00000000169","800000000170","600000000172","400000000174","200000000176","W00000000178","U00000000180","P00000000183","N00000000185","L00000000187","J00000000189","D00000000191"]'
SELECT noteId, type, mime, content, isProtected
FROM notes JOIN blobs USING (blobId)
WHERE type IN ('text', 'code', 'mermaid', 'canvas', 'mindMap', 'spreadsheet', 'llmChat')
  AND isDeleted = 0
  AND LENGTH(content) < 2097152
  AND noteId IN (SELECT value FROM json_each(?1));

-- @id trilium.consistency.duplicate_branches
-- @src packages/trilium-core/src/services/consistency_checks.ts:386-394
-- @style no params
-- @note Consistency check: duplicate (parentNoteId, noteId) branches via GROUP BY ... HAVING COUNT(1) > 1.
SELECT noteId,
        parentNoteId
FROM branches
WHERE branches.isDeleted = 0
GROUP BY branches.parentNoteId,
        branches.noteId
HAVING COUNT(1) > 1;

-- @id trilium.consistency.missing_entity_changes
-- @src packages/trilium-core/src/services/consistency_checks.ts:745-752
-- @style no params; entityName = attributes and key = attributeId spliced in
-- @tags dynamic
-- @note Consistency check: anti-join from attributes to entity_changes on a constant entityName plus the key column.
SELECT attributeId as entityId
FROM attributes
LEFT JOIN entity_changes ec ON ec.entityName = 'attributes' AND ec.entityId = attributes.attributeId
WHERE ec.id IS NULL;

-- @id trilium.erase.unused_blobs
-- @src packages/trilium-core/src/services/erase.ts:100-108
-- @style no params
-- @note Periodic erase: blobs referenced by no note, attachment or revision (three LEFT JOIN anti-joins).
SELECT blobs.blobId
FROM blobs
LEFT JOIN notes ON notes.blobId = blobs.blobId
LEFT JOIN attachments ON attachments.blobId = blobs.blobId
LEFT JOIN revisions ON revisions.blobId = blobs.blobId
WHERE notes.noteId IS NULL
AND attachments.attachmentId IS NULL
AND revisions.revisionId IS NULL;

-- @id trilium.ws.entity_changes_by_ids
-- @src packages/trilium-core/src/services/ws.ts:149
-- @style ??? expanded by getManyRows() into a ? list (services/sql/sql.ts:342)
-- @tags hotpath,dynamic
-- @note Frontend update push: the entity changes of a transaction by id, a short IN list on the rowid.
-- @param ?1 142001
-- @param ?2 142002
-- @param ?3 142003
-- @param ?4 142010
-- @param ?5 142011
-- @param ?6 142050
SELECT * FROM entity_changes WHERE id IN (?1, ?2, ?3, ?4, ?5, ?6);
