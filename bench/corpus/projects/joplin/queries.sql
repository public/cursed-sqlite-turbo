-- Joplin (laurent22/joplin @ b613d00, AGPL-3.0-or-later). Client-side SQL from packages/lib: the models build most
-- statements at runtime (field lists from previewFields()/fieldNames(), WHERE lists from option objects, ORDER BY
-- from paginationToSql, IN lists from escapeIdsForSql), so those are one representative instantiation each (tagged
-- dynamic). The app binds with `?`; placeholders are normalised to ?N in argument order. Paths are repo-relative. Model type ids: 1 note, 2 folder, 4 resource, 5 tag, 6 note_tag. Sync target 10 = Joplin Cloud.

-- @id joplin.notes.previews_folder
-- @src packages/lib/models/Note.ts:425-560
-- @style ? positional; Note.previews() -> BaseModel.search() (BaseModel.ts:374-394) + applySqlOptions/paginationToSql (BaseModel.ts:320-336)
-- @tags hotpath,dynamic
-- @note The note list for the selected notebook (default sort): 18 preview fields, 4-key ORDER BY. `notes` has no secondary index in a real profile (the v30 table rebuild dropped them), so this is a full scan + sort.
-- @param ?1 'f0000000000000000000000000000003'
SELECT `id`,`title`,`is_todo`,`todo_completed`,`todo_due`,`parent_id`,`encryption_applied`,`is_locked`,`order`,`markup_language`,`is_conflict`,`conflict_original_id`,`is_shared`,`share_id`,`deleted_time`,`updated_time`,`user_updated_time`,`user_created_time`
FROM `notes`
WHERE is_conflict = 0 AND deleted_time = 0 AND parent_id = ?1
ORDER BY `user_updated_time` DESC, `user_created_time` DESC, `title` DESC, `id` DESC;

-- @id joplin.notes.previews_custom_order_todos_on_top
-- @src packages/lib/models/Note.ts:425-526
-- @style ? positional; first of the two searches previews() runs with uncompletedTodosOnTop, order from customOrderByColumns() (Note.ts:1261)
-- @tags hotpath,dynamic
-- @note Custom-order note list with "uncompleted to-dos on top" and completed to-dos hidden: the uncompleted-to-do half, ordered by the float `order` column.
-- @param ?1 'f0000000000000000000000000000003'
SELECT `id`,`title`,`is_todo`,`todo_completed`,`todo_due`,`parent_id`,`encryption_applied`,`is_locked`,`order`,`markup_language`,`is_conflict`,`conflict_original_id`,`is_shared`,`share_id`,`deleted_time`,`updated_time`,`user_updated_time`,`user_created_time`
FROM `notes`
WHERE is_conflict = 0 AND deleted_time = 0 AND parent_id = ?1 AND todo_completed <= 0 AND is_todo = 1 AND (todo_completed <= 0 OR todo_completed IS NULL)
ORDER BY `order` DESC, `user_created_time` DESC;

-- @id joplin.search.basic_search
-- @src packages/lib/services/search/SearchEngine.ts:665-681
-- @style ? positional; basicSearch() -> Note.previews(null, { anywherePattern }) (Note.ts:477-482)
-- @tags hotpath,dynamic
-- @note Basic (non-FTS) search, used when FTS is unavailable: every live note, title LIKE OR body LIKE '%term%', sorted by the default 4-key order.
-- @param ?1 '%paris%'
-- @param ?2 '%paris%'
SELECT `id`,`title`,`is_todo`,`todo_completed`,`todo_due`,`parent_id`,`encryption_applied`,`is_locked`,`order`,`markup_language`,`is_conflict`,`conflict_original_id`,`is_shared`,`share_id`,`deleted_time`,`updated_time`,`user_updated_time`,`user_created_time`
FROM `notes`
WHERE is_conflict = 0 AND deleted_time = 0 AND (title LIKE ?1 OR body LIKE ?2)
ORDER BY `user_updated_time` DESC, `user_created_time` DESC, `title` DESC, `id` DESC;

-- @id joplin.folders.all_for_display
-- @src packages/lib/folders-screen-utils.ts:10-24
-- @style no params; Folder.all() -> BaseModel.all() (BaseModel.ts:344-356) with caseInsensitive title order
-- @tags hotpath,dynamic
-- @note Sidebar notebook list: SELECT * ordered by title COLLATE NOCASE.
SELECT * FROM `folders` ORDER BY `title` COLLATE NOCASE ASC;

-- @id joplin.folders.add_note_counts
-- @src packages/lib/models/Folder.ts:247-283
-- @style no params; WHERE list built at runtime (includeCompletedTodos = false)
-- @tags hotpath,dynamic
-- @note Sidebar note counts: folders LEFT JOIN notes on parent_id with GROUP BY; the counts are then rolled up the folder tree in JS.
SELECT folders.id as folder_id, count(notes.parent_id) as note_count
FROM folders LEFT JOIN notes ON notes.parent_id = folders.id
WHERE is_conflict = 0 AND notes.deleted_time = 0 AND (notes.is_todo = 0 OR notes.todo_completed = 0)
GROUP BY folders.id;

-- @id joplin.folders.order_by_last_modified
-- @src packages/lib/models/Folder.ts:315-318
-- @style no params
-- @tags hotpath
-- @note Sidebar sorted by "updated date": max(user_updated_time) per parent over the whole notes table.
select parent_id, max(user_updated_time) content_updated_time from notes where parent_id != '' group by parent_id;

-- @id joplin.notes.has_locked_note_in_folder_trees
-- @src packages/lib/models/Note.ts:612-642
-- @style id list inlined by escapeIdsForSql
-- @tags dynamic
-- @note Recursive UNION CTE over several notebook subtrees feeding an EXISTS(... LIMIT 1) join against notes (export guard for locked notes).
WITH RECURSIVE folder_tree(id) AS (
	SELECT id
	FROM folders
	WHERE id IN ('f0000000000000000000000000000004','f0000000000000000000000000000009','f000000000000000000000000000000d','f0000000000000000000000000000016')
	UNION
	SELECT folder.id
	FROM folders folder
	INNER JOIN folder_tree parent
		ON folder.parent_id = parent.id
	WHERE folder.deleted_time = 0
)
SELECT EXISTS (
	SELECT 1
	FROM notes note
	INNER JOIN folder_tree folder
		ON note.parent_id = folder.id
	WHERE note.is_locked = 1
		AND note.is_conflict = 0
		AND note.deleted_time = 0
	LIMIT 1
) AS value;

-- @id joplin.folders.update_note_share_ids
-- @src packages/lib/models/Folder.ts:583-594
-- @style no params
-- @note Share maintenance on every sync: notes LEFT JOIN folders with the same CASE expression in the result and in the WHERE.
SELECT
	notes.id,
	CASE WHEN notes.is_conflict = 1 THEN '' ELSE folders.share_id END AS share_id,
	notes.parent_id
FROM notes
LEFT JOIN folders ON notes.parent_id = folders.id
WHERE notes.share_id != CASE WHEN notes.is_conflict = 1 THEN '' ELSE folders.share_id END;

-- @id joplin.folders.update_resource_share_ids
-- @src packages/lib/models/Folder.ts:656-668
-- @style no params
-- @note Three-way LEFT JOIN note_resources -> resources/notes looking for share_id/is_shared mismatches.
SELECT
	r.id,
	n.share_id,
	n.is_shared,
	r.is_shared as resource_is_shared,
	r.share_id as resource_share_id
FROM note_resources nr
LEFT JOIN resources r ON nr.resource_id = r.id
LEFT JOIN notes n ON nr.note_id = n.id
WHERE (
	n.share_id != r.share_id
	OR n.is_shared != r.is_shared
) AND nr.is_associated = 1;

-- @id joplin.tags.all_with_notes
-- @src packages/lib/models/Tag.ts:137-139
-- @style no params; reads the tags_with_note_count view (services/database/migrations/46.ts)
-- @tags hotpath
-- @note Sidebar tag list: view with tags LEFT JOIN note_tags LEFT JOIN notes, COUNT + SUM(CASE) per tag.
SELECT * FROM tags_with_note_count;

-- @id joplin.tags.search_all_with_notes
-- @src packages/lib/models/Tag.ts:141-146
-- @style ? positional; BaseModel.search() with titlePattern and a caseInsensitive title order
-- @tags dynamic
-- @note Tag autocomplete: IN (SELECT DISTINCT id FROM <aggregating view>) plus title LIKE.
-- @param ?1 'pro%'
SELECT * FROM `tags` WHERE id IN (SELECT distinct id FROM tags_with_note_count) AND title LIKE ?1 ORDER BY `title` COLLATE NOCASE ASC;

-- @id joplin.tags.note_ids
-- @src packages/lib/models/Tag.ts:20-32
-- @style ? positional
-- @tags hotpath
-- @note Notes of a tag (the tag's note list): note_tags LEFT JOIN notes filtered on the joined side.
-- @param ?1 'b2000000000000000000000000000005'
SELECT note_id
FROM note_tags
LEFT JOIN notes ON notes.id = note_tags.note_id
WHERE tag_id = ?1 AND notes.deleted_time = 0;

-- @id joplin.tags.load_by_title
-- @src packages/lib/models/Tag.ts:173-189
-- @style ? positional
-- @tags hot-small
-- @note Tag lookup by title when tagging a note: COLLATE NOCASE equality against a BINARY index, ordered by created_time.
-- @param ?1 'Project'
SELECT * FROM tags WHERE title = ?1 COLLATE NOCASE ORDER BY created_time ASC;

-- @id joplin.sync.items_that_need_sync_never_synced
-- @src packages/lib/models/BaseItem.ts:759-808
-- @style sprintf: field list from fieldNames('items'), sync target and limit inlined
-- @tags hotpath,dynamic
-- @note Sync upload step 1 for notes: NOT IN (SELECT item_id FROM sync_items WHERE sync_target = 10), conflict/encryption filters, newest first LIMIT 100.
SELECT items.`id`,items.`parent_id`,items.`title`,items.`body`,items.`created_time`,items.`updated_time`,items.`is_conflict`,items.`latitude`,items.`longitude`,items.`altitude`,items.`author`,items.`source_url`,items.`is_todo`,items.`todo_due`,items.`todo_completed`,items.`source`,items.`source_application`,items.`application_data`,items.`order`,items.`user_created_time`,items.`user_updated_time`,items.`encryption_cipher_text`,items.`encryption_applied`,items.`markup_language`,items.`is_shared`,items.`share_id`,items.`conflict_original_id`,items.`master_key_id`,items.`user_data`,items.`deleted_time`,items.`is_locked`,items.`extracted_resource_ids`
FROM `notes` items
WHERE id NOT IN (
	SELECT item_id FROM sync_items WHERE sync_target = 10
)
AND (is_conflict = 0 OR (conflict_original_id != '' AND share_id = '')) AND encryption_applied = 0
ORDER BY items.updated_time DESC
LIMIT 100;

-- @id joplin.sync.items_that_need_sync_changed
-- @src packages/lib/models/BaseItem.ts:813-839
-- @style sprintf: field list from fieldNames('items'), sync target and limit inlined
-- @tags hotpath,dynamic
-- @note Sync upload step 2: notes JOIN sync_items where the local copy is newer than the last sync (or force_sync), newest first.
SELECT items.`id`,items.`parent_id`,items.`title`,items.`body`,items.`created_time`,items.`updated_time`,items.`is_conflict`,items.`latitude`,items.`longitude`,items.`altitude`,items.`author`,items.`source_url`,items.`is_todo`,items.`todo_due`,items.`todo_completed`,items.`source`,items.`source_application`,items.`application_data`,items.`order`,items.`user_created_time`,items.`user_updated_time`,items.`encryption_cipher_text`,items.`encryption_applied`,items.`markup_language`,items.`is_shared`,items.`share_id`,items.`conflict_original_id`,items.`master_key_id`,items.`user_data`,items.`deleted_time`,items.`is_locked`,items.`extracted_resource_ids`
FROM `notes` items
JOIN sync_items s ON s.item_id = items.id
WHERE sync_target = 10
AND (s.sync_time < items.updated_time OR force_sync = 1)
AND s.sync_disabled = 0
AND (is_conflict = 0 OR (conflict_original_id != '' AND share_id = '')) AND encryption_applied = 0
ORDER BY items.updated_time DESC
LIMIT 100;

-- @id joplin.sync.update_sync_time_insert
-- @src packages/lib/models/BaseItem.ts:920-947
-- @style ? positional; base = null branch (base columns carried over from the existing row)
-- @tags hotpath,batch
-- @note Per-item after upload: INSERT ... SELECT from a one-row seed LEFT JOINed to the newest existing sync_items row (scalar MAX subquery in the ON), COALESCE carry-over of the merge base.
-- @param ?1 10
-- @param ?2 1
-- @param ?3 'a1000000000000000000000000000011'
-- @param ?4 1
-- @param ?5 1702000000000
-- @param ?6 1701999990000
-- @param ?7 0
-- @param ?8 ''
-- @param ?9 10
-- @param ?10 1
-- @param ?11 'a1000000000000000000000000000011'
INSERT INTO sync_items (sync_target, item_type, item_id, item_location, sync_time, remote_item_updated_time, sync_disabled, sync_disabled_reason, base_body, base_title, base_conflict_note_id)
SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8,
	COALESCE(existing.base_body, ''),
	COALESCE(existing.base_title, ''),
	COALESCE(existing.base_conflict_note_id, '')
FROM (SELECT 1) AS seed
LEFT JOIN sync_items AS existing ON existing.id = (
	SELECT MAX(candidate.id) FROM sync_items AS candidate
	WHERE candidate.sync_target = ?9 AND candidate.item_type = ?10 AND candidate.item_id = ?11
);

-- @id joplin.sync.update_sync_time_dedupe
-- @src packages/lib/models/BaseItem.ts:948-951
-- @style ? positional
-- @tags hotpath
-- @note Companion of the insert: delete every older sync_items row for the item, `id != (SELECT MAX(id) ...)`.
-- @param ?1 10
-- @param ?2 1
-- @param ?3 'a1000000000000000000000000000002'
-- @param ?4 10
-- @param ?5 1
-- @param ?6 'a1000000000000000000000000000002'
DELETE FROM sync_items WHERE sync_target = ?1 AND item_type = ?2 AND item_id = ?3 AND id != (SELECT MAX(id) FROM sync_items WHERE sync_target = ?4 AND item_type = ?5 AND item_id = ?6);

-- @id joplin.sync.sync_item
-- @src packages/lib/models/BaseItem.ts:233-239
-- @style ? positional; field list from options (Note.syncBaseContent asks for base_body, base_title)
-- @tags hot-small,dynamic
-- @note Point lookup of an item's sync row (merge base for conflict handling).
-- @param ?1 10
-- @param ?2 'a1000000000000000000000000000010'
SELECT `base_body`,`base_title` FROM sync_items WHERE sync_target = ?1 AND item_id = ?2;

-- @id joplin.search.process_changes
-- @src packages/lib/services/search/SearchEngine.ts:226-237
-- @style ? positional
-- @tags hot-small
-- @note Search indexer polling the change log: id > last processed, ORDER BY id LIMIT 10 (runs every few seconds).
-- @param ?1 1
-- @param ?2 15000
SELECT id, item_id, type
FROM item_changes
WHERE item_type = ?1
AND id > ?2
ORDER BY id ASC
LIMIT 10;

-- @id joplin.search.index_note
-- @src packages/lib/services/search/SearchEngine.ts:257-260
-- @style ? positional
-- @tags hot-small
-- @note Indexing one note: a 13-column insert into notes_normalized whose AFTER INSERT trigger copies the row into the external-content FTS4 table.
-- @param ?1 'a1000000000000000000000000099999'
-- @param ?2 'weekly meeting notes'
-- @param ?3 'today we discussed the budget and the roadmap. next step: release for the server.'
-- @param ?4 1702000000000
-- @param ?5 1702000000000
-- @param ?6 0
-- @param ?7 0
-- @param ?8 0
-- @param ?9 'f0000000000000000000000000000003'
-- @param ?10 0
-- @param ?11 0
-- @param ?12 0
-- @param ?13 ''
INSERT INTO notes_normalized(id, title, body, user_created_time, user_updated_time, is_todo, todo_completed, todo_due, parent_id, latitude, longitude, altitude, source_url)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13);

-- @id joplin.search.fts_notebook_tag_text
-- @src packages/lib/services/search/queryBuilder.ts:447-509
-- @style ? positional; queryBuilder(terms, useFts = true) for `notebook:Recipe* tag:project meeting` (_notebookFilter :26, tagFilter :193, filterByTableName :85, textFilter :348)
-- @tags hotpath,dynamic
-- @note Full-text search with filters: two CTEs (a recursive notebook-subtree walk and an INTERSECT of tagged notes) feeding ROWID IN joins against notes_normalized, FTS4 MATCH, offsets() and matchinfo('pcnalx') per hit.
-- @param ?1 'Recipe%'
-- @param ?2 'project'
-- @param ?3 'meeting'
WITH RECURSIVE
	notebooks_in_scope(id)
	AS (
		SELECT folders.id
		FROM folders
		WHERE id
		IN (
			SELECT id
			FROM folders
			WHERE folders.title LIKE ?1
		)
		UNION ALL
		SELECT folders.id
		FROM folders
		JOIN notebooks_in_scope
		ON folders.parent_id=notebooks_in_scope.id
	),
	notes_with_INCLUSION_tags
	AS (
		SELECT note_tags.note_id as id
		FROM note_tags
		WHERE
		1 INTERSECT
		SELECT note_tags.note_id AS id
		FROM note_tags
		WHERE note_tags.tag_id IN (
			SELECT tags.id
			FROM tags
			WHERE tags.title
			LIKE ?2)
	)
SELECT
	notes_fts.id,
	notes_fts.title,
	offsets(notes_fts) AS offsets, matchinfo(notes_fts, 'pcnalx') AS matchinfo,
	notes_fts.user_created_time,
	notes_fts.user_updated_time,
	notes_fts.is_todo,
	notes_fts.todo_completed,
	notes_fts.parent_id
FROM notes_fts
WHERE 1
	AND ROWID IN (
		SELECT notes_normalized.ROWID
		FROM notebooks_in_scope
		JOIN notes_normalized
		ON notebooks_in_scope.id=notes_normalized.parent_id
	)
	AND ROWID IN (
		SELECT notes_normalized.ROWID
		FROM notes_with_INCLUSION_tags
		JOIN notes_normalized
		ON notes_with_INCLUSION_tags.id=notes_normalized.id
	)
	AND notes_fts MATCH ?3;

-- @id joplin.search.fts_filters_exclusion
-- @src packages/lib/services/search/queryBuilder.ts:447-509
-- @style ? positional; queryBuilder(terms, useFts = true) for `deadline* type:todo iscompleted:0 created:<date> -tag:archive -body:draft`
-- @tags hotpath,dynamic
-- @note FTS search with negated filters: a UNION CTE of excluded-tag notes under ROWID NOT IN, a NOT IN over a second MATCH, is_todo/todo_completed checks on FTS columns, a date range subquery on notes_normalized.
-- @param ?1 'archive'
-- @param ?2 'deadline*'
-- @param ?3 'draft'
-- @param ?4 1600900000000
WITH RECURSIVE
	notes_with_EXCLUSION_tags
	AS (
		SELECT note_tags.note_id as id
		FROM note_tags
		WHERE
		0 UNION
		SELECT note_tags.note_id AS id
		FROM note_tags
		WHERE note_tags.tag_id IN (
			SELECT tags.id
			FROM tags
			WHERE tags.title
			LIKE ?1)
	)
SELECT
	notes_fts.id,
	notes_fts.title,
	offsets(notes_fts) AS offsets, matchinfo(notes_fts, 'pcnalx') AS matchinfo,
	notes_fts.user_created_time,
	notes_fts.user_updated_time,
	notes_fts.is_todo,
	notes_fts.todo_completed,
	notes_fts.parent_id
FROM notes_fts
WHERE 1
	AND ROWID NOT IN (
		SELECT notes_normalized.ROWID
		FROM notes_with_EXCLUSION_tags
		JOIN notes_normalized
		ON notes_with_EXCLUSION_tags.id=notes_normalized.id
	)
	AND notes_fts MATCH ?2
	AND ROWID NOT IN (
		SELECT ROWID
		FROM notes_fts
		WHERE notes_fts.body MATCH ?3
	)
	AND notes_fts.is_todo IS 1
	AND notes_fts.is_todo IS 1 AND notes_fts.todo_completed IS 0
	AND ( ROWID IN (
		SELECT ROWID
		FROM notes_normalized
		WHERE notes_normalized.user_created_time >= ?4
	));

-- @id joplin.search.nonlatin_like
-- @src packages/lib/services/search/queryBuilder.ts:447-509
-- @style ? positional; queryBuilder(terms, useFts = false), the path SearchEngine takes for CJK/Thai queries (SearchEngine.ts:753)
-- @tags dynamic
-- @note Non-FTS search on `notes` with `any:1`: OR-connected LIKE predicates plus an OR'ed tag-inclusion CTE (UNION of tagged notes).
-- @modified the search terms are Latin words so they match the synthetic data; the app sends this shape for ja/zh/ko/th text
-- @param ?1 'travel'
-- @param ?2 '%paris%'
-- @param ?3 '%paris%'
WITH RECURSIVE
	notes_with_INCLUSION_tags
	AS (
		SELECT note_tags.note_id as id
		FROM note_tags
		WHERE
		0 UNION
		SELECT note_tags.note_id AS id
		FROM note_tags
		WHERE note_tags.tag_id IN (
			SELECT tags.id
			FROM tags
			WHERE tags.title
			LIKE ?1)
	)
SELECT
	notes.id,
	notes.title,
	notes.user_created_time,
	notes.user_updated_time,
	notes.is_todo,
	notes.todo_completed,
	notes.parent_id
FROM notes
WHERE ROWID=-1
	OR ROWID IN (
		SELECT notes.ROWID
		FROM notes_with_INCLUSION_tags
		JOIN notes
		ON notes_with_INCLUSION_tags.id=notes.id
	)
	OR (
		notes.body LIKE ?2
		OR
		notes.title LIKE ?3 );

-- @id joplin.search.resources_items_fts
-- @src packages/lib/services/search/SearchEngine.ts:884-895
-- @style ? positional
-- @tags hotpath
-- @note OCR-text search over resources: FTS4 column MATCH OR column MATCH, with offsets()/matchinfo().
-- @param ?1 'paris'
-- @param ?2 'paris'
SELECT
	id,
	title,
	user_updated_time,
	offsets(items_fts) AS offsets,
	matchinfo(items_fts, 'pcnalx') AS matchinfo,
	item_id,
	item_type
FROM items_fts
WHERE title MATCH ?1 OR body MATCH ?2;

-- @id joplin.revisions.latest_revision
-- @src packages/lib/models/Revision.ts:205-207
-- @style ? positional
-- @tags hot-small
-- @note Latest revision of a note (checked on every note save by the revision service): top-1 by item_updated_time.
-- @param ?1 1
-- @param ?2 'a1000000000000000000000000000011'
SELECT * FROM revisions WHERE item_type = ?1 AND item_id = ?2 ORDER BY item_updated_time DESC LIMIT 1;

-- @id joplin.revisions.revisions_to_keep
-- @src packages/lib/models/Revision.ts:303-318
-- @style ? positional
-- @note Revision pruning: self-join child -> parent on parent_id straddling the cut-off date.
-- @param ?1 1
-- @param ?2 'a1000000000000000000000000000011'
-- @param ?3 1601211130000
-- @param ?4 1
-- @param ?5 'a1000000000000000000000000000011'
-- @param ?6 1601211130000
SELECT child.*
FROM revisions AS child
JOIN revisions AS parent
ON child.parent_id = parent.id
WHERE child.item_type = ?1
AND child.item_id = ?2
AND child.item_updated_time >= ?3
AND parent.item_type = ?4
AND parent.item_id = ?5
AND parent.item_updated_time < ?6
ORDER BY child.item_updated_time ASC;

-- @id joplin.resources.need_to_be_fetched
-- @src packages/lib/models/Resource.ts:111-119
-- @style ? positional; resourceDownloadMode != 'always' adds the resources_to_download clause, limit inlined
-- @tags dynamic
-- @note Resource fetcher queue: two IN subqueries over side tables, newest first.
-- @param ?1 0
SELECT * FROM resources WHERE encryption_applied = 0 AND id IN (SELECT resource_id FROM resource_local_states WHERE fetch_status = ?1) AND resources.id IN (SELECT resource_id FROM resources_to_download) ORDER BY updated_time DESC LIMIT 100;

-- @id joplin.resources.note_resources_page
-- @src packages/lib/models/Resource.ts:644-669
-- @style ? positional; WHERE/ORDER BY assembled at runtime (search query set, sort by title asc)
-- @tags dynamic
-- @note Attachments screen: LOWER(COALESCE()) LIKE on two columns, ORDER BY an expression, LIMIT/OFFSET page.
-- @param ?1 '%scan_1%'
-- @param ?2 '%scan_1%'
-- @param ?3 51
-- @param ?4 0
SELECT id, title, size, file_extension, mime
FROM resources
WHERE (LOWER(COALESCE(id, '')) LIKE ?1 OR LOWER(COALESCE(title, '')) LIKE ?2)
ORDER BY LOWER(COALESCE(title, '')) ASC, id ASC
LIMIT ?3 OFFSET ?4;

-- @id joplin.kv.set_value
-- @src packages/lib/services/KvStore.ts:76-79
-- @style ? positional
-- @tags hot-small
-- @note Key/value store write (services store their change cursors here): INSERT OR REPLACE against a unique key index.
-- @param ?1 'ResourceService::lastProcessedChangeId::3'
-- @param ?2 15123
-- @param ?3 1
-- @param ?4 1702000000000
INSERT OR REPLACE INTO key_values (`key`, `value`, `type`, `updated_time`) VALUES (?1, ?2, ?3, ?4);

-- @id joplin.notes.load
-- @src packages/lib/BaseModel.ts:442-449
-- @style ? positional; loadByField('id', ...) via Note.load()
-- @tags hot-small
-- @note Note.load(): SELECT * by primary key, the most frequent statement in the app.
-- @param ?1 'a1000000000000000000000000000011'
SELECT * FROM `notes` WHERE `id` = ?1;
