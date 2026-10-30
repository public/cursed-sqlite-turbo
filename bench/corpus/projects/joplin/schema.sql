-- laurent22/joplin @ b613d0064d018c2f68d983c907ab88e2712da116 (AGPL-3.0-or-later)
-- Reconstructed final shape of the client database after all migrations in packages/lib/JoplinDatabase.ts
-- (structureSql + upgradeDatabase v1..v41) and packages/lib/services/database/migrations/42.ts..54.ts.
-- Only the CREATE statements the queries in queries.sql need. Column order follows the order in which the
-- migrations add the columns. Note: v14 (resources) and v30 (notes) rebuild their table through
-- Database.alterColumnQueries (CREATE/INSERT/DROP), which drops the secondary indexes created before them, so in a
-- real profile `notes` has no secondary index at all and `resources` only has resources_size (v28).

-- folders: structureSql + v5, v9, v12, v26, v36, v40, v41, m43, m46
CREATE TABLE folders (
	id TEXT PRIMARY KEY,
	title TEXT NOT NULL DEFAULT "",
	created_time INT NOT NULL,
	updated_time INT NOT NULL,
	user_created_time INT NOT NULL DEFAULT 0,
	user_updated_time INT NOT NULL DEFAULT 0,
	encryption_cipher_text TEXT NOT NULL DEFAULT "",
	encryption_applied INT NOT NULL DEFAULT 0,
	parent_id TEXT NOT NULL DEFAULT "",
	is_shared INT NOT NULL DEFAULT 0,
	share_id TEXT NOT NULL DEFAULT "",
	master_key_id TEXT NOT NULL DEFAULT "",
	icon TEXT NOT NULL DEFAULT "",
	user_data TEXT NOT NULL DEFAULT "",
	deleted_time INT NOT NULL DEFAULT 0
);
CREATE INDEX folders_title ON folders (title);
CREATE INDEX folders_updated_time ON folders (updated_time);
CREATE INDEX folders_user_updated_time ON folders (user_updated_time);
CREATE INDEX folders_encryption_applied ON folders (encryption_applied);

-- notes: rebuilt by v30 (alterColumnQueries, no indexes survive), then v36, v39, v40, m43, m46, m50
CREATE TABLE notes (
	`id` TEXT PRIMARY KEY,
	`parent_id` TEXT NOT NULL DEFAULT "",
	`title` TEXT NOT NULL DEFAULT "",
	`body` TEXT NOT NULL DEFAULT "",
	`created_time` INT NOT NULL,
	`updated_time` INT NOT NULL,
	`is_conflict` INT NOT NULL DEFAULT 0,
	`latitude` NUMERIC NOT NULL DEFAULT 0,
	`longitude` NUMERIC NOT NULL DEFAULT 0,
	`altitude` NUMERIC NOT NULL DEFAULT 0,
	`author` TEXT NOT NULL DEFAULT "",
	`source_url` TEXT NOT NULL DEFAULT "",
	`is_todo` INT NOT NULL DEFAULT 0,
	`todo_due` INT NOT NULL DEFAULT 0,
	`todo_completed` INT NOT NULL DEFAULT 0,
	`source` TEXT NOT NULL DEFAULT "",
	`source_application` TEXT NOT NULL DEFAULT "",
	`application_data` TEXT NOT NULL DEFAULT "",
	`order` NUMERIC NOT NULL DEFAULT 0,
	`user_created_time` INT NOT NULL DEFAULT 0,
	`user_updated_time` INT NOT NULL DEFAULT 0,
	`encryption_cipher_text` TEXT NOT NULL DEFAULT "",
	`encryption_applied` INT NOT NULL DEFAULT 0,
	`markup_language` INT NOT NULL DEFAULT 1,
	`is_shared` INT NOT NULL DEFAULT 0,
	share_id TEXT NOT NULL DEFAULT "",
	conflict_original_id TEXT NOT NULL DEFAULT "",
	master_key_id TEXT NOT NULL DEFAULT "",
	`user_data` TEXT NOT NULL DEFAULT "",
	`deleted_time` INT NOT NULL DEFAULT 0,
	is_locked INT NOT NULL DEFAULT 0,
	extracted_resource_ids TEXT NOT NULL DEFAULT ""
);

-- tags: structureSql + v5, v9, v26, v31, m43
CREATE TABLE tags (
	id TEXT PRIMARY KEY,
	title TEXT NOT NULL DEFAULT "",
	created_time INT NOT NULL,
	updated_time INT NOT NULL,
	user_created_time INT NOT NULL DEFAULT 0,
	user_updated_time INT NOT NULL DEFAULT 0,
	encryption_cipher_text TEXT NOT NULL DEFAULT "",
	encryption_applied INT NOT NULL DEFAULT 0,
	is_shared INT NOT NULL DEFAULT 0,
	parent_id TEXT NOT NULL DEFAULT "",
	`user_data` TEXT NOT NULL DEFAULT ""
);
CREATE INDEX tags_title ON tags (title);
CREATE INDEX tags_updated_time ON tags (updated_time);
CREATE INDEX tags_user_updated_time ON tags (user_updated_time);
CREATE INDEX tags_encryption_applied ON tags (encryption_applied);

-- note_tags: structureSql + v5, v9, v26
CREATE TABLE note_tags (
	id TEXT PRIMARY KEY,
	note_id TEXT NOT NULL,
	tag_id TEXT NOT NULL,
	created_time INT NOT NULL,
	updated_time INT NOT NULL,
	user_created_time INT NOT NULL DEFAULT 0,
	user_updated_time INT NOT NULL DEFAULT 0,
	encryption_cipher_text TEXT NOT NULL DEFAULT "",
	encryption_applied INT NOT NULL DEFAULT 0,
	is_shared INT NOT NULL DEFAULT 0
);
CREATE INDEX note_tags_note_id ON note_tags (note_id);
CREATE INDEX note_tags_tag_id ON note_tags (tag_id);
CREATE INDEX note_tags_updated_time ON note_tags (updated_time);
CREATE INDEX note_tags_user_updated_time ON note_tags (user_updated_time);
CREATE INDEX note_tags_encryption_applied ON note_tags (encryption_applied);

-- resources: rebuilt by v14 (alterColumnQueries), then v20, v26, v28, v36, v40, m43, m44, m45, m48, m50
CREATE TABLE resources (
	`id` TEXT PRIMARY KEY,
	`title` TEXT NOT NULL DEFAULT "",
	`mime` TEXT NOT NULL,
	`filename` TEXT NOT NULL DEFAULT "",
	`created_time` INT NOT NULL,
	`updated_time` INT NOT NULL,
	`user_created_time` INT NOT NULL DEFAULT 0,
	`user_updated_time` INT NOT NULL DEFAULT 0,
	`file_extension` TEXT NOT NULL DEFAULT "",
	`encryption_cipher_text` TEXT NOT NULL DEFAULT "",
	`encryption_applied` INT NOT NULL DEFAULT 0,
	`encryption_blob_encrypted` INT NOT NULL DEFAULT 0,
	`size` INT NOT NULL DEFAULT -1,
	is_shared INT NOT NULL DEFAULT 0,
	share_id TEXT NOT NULL DEFAULT "",
	master_key_id TEXT NOT NULL DEFAULT "",
	`user_data` TEXT NOT NULL DEFAULT "",
	blob_updated_time INT NOT NULL DEFAULT 0,
	`ocr_text` TEXT NOT NULL DEFAULT "",
	`ocr_details` TEXT NOT NULL DEFAULT "",
	`ocr_status` INT NOT NULL DEFAULT 0,
	`ocr_error` TEXT NOT NULL DEFAULT "",
	`ocr_driver_id` INT NOT NULL DEFAULT "1",
	is_locked INT NOT NULL DEFAULT 0
);
CREATE INDEX resources_size ON resources(size);

-- sync_items: structureSql + v8, v9, v21, m47, m49, m51
CREATE TABLE sync_items (
	id INTEGER PRIMARY KEY,
	sync_target INT NOT NULL,
	sync_time INT NOT NULL DEFAULT 0,
	item_type INT NOT NULL,
	item_id TEXT NOT NULL,
	sync_disabled INT NOT NULL DEFAULT "0",
	sync_disabled_reason TEXT NOT NULL DEFAULT "",
	force_sync INT NOT NULL DEFAULT 0,
	item_location INT NOT NULL DEFAULT 1,
	sync_warning_ignored INT NOT NULL DEFAULT "0",
	remote_item_updated_time INT NOT NULL DEFAULT 0,
	base_body TEXT NOT NULL DEFAULT "",
	base_title TEXT NOT NULL DEFAULT "",
	base_conflict_note_id TEXT NOT NULL DEFAULT ""
);
CREATE INDEX sync_items_sync_time ON sync_items (sync_time);
CREATE INDEX sync_items_sync_target ON sync_items (sync_target);
CREATE INDEX sync_items_item_type ON sync_items (item_type);
CREATE INDEX sync_items_item_id ON sync_items (item_id);

-- deleted_items: v2
CREATE TABLE deleted_items (
	id INTEGER PRIMARY KEY,
	item_type INT NOT NULL,
	item_id TEXT NOT NULL,
	deleted_time INT NOT NULL,
	sync_target INT NOT NULL
);
CREATE INDEX deleted_items_sync_target ON deleted_items (sync_target);

-- item_changes: v10/v11 + v19
CREATE TABLE item_changes (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	item_type INT NOT NULL,
	item_id TEXT NOT NULL,
	type INT NOT NULL,
	created_time INT NOT NULL,
	source INT NOT NULL DEFAULT 1,
	before_change_item TEXT NOT NULL DEFAULT ""
);
CREATE INDEX item_changes_item_id ON item_changes (item_id);
CREATE INDEX item_changes_created_time ON item_changes (created_time);
CREATE INDEX item_changes_item_type ON item_changes (item_type);

-- note_resources: v10/v11
CREATE TABLE note_resources (
	id INTEGER PRIMARY KEY,
	note_id TEXT NOT NULL,
	resource_id TEXT NOT NULL,
	is_associated INT NOT NULL,
	last_seen_time INT NOT NULL
);
CREATE INDEX note_resources_note_id ON note_resources (note_id);
CREATE INDEX note_resources_resource_id ON note_resources (resource_id);

-- resource_local_states: v14
CREATE TABLE resource_local_states (
	id INTEGER PRIMARY KEY,
	resource_id TEXT NOT NULL,
	fetch_status INT NOT NULL DEFAULT "2",
	fetch_error TEXT NOT NULL DEFAULT ""
);
CREATE INDEX resource_local_states_resource_id ON resource_local_states (resource_id);
CREATE INDEX resource_local_states_resource_fetch_status ON resource_local_states (fetch_status);

-- revisions: v19 + m50
CREATE TABLE revisions (
	id TEXT PRIMARY KEY,
	parent_id TEXT NOT NULL DEFAULT "",
	item_type INT NOT NULL,
	item_id TEXT NOT NULL,
	item_updated_time INT NOT NULL,
	title_diff TEXT NOT NULL DEFAULT "",
	body_diff TEXT NOT NULL DEFAULT "",
	metadata_diff TEXT NOT NULL DEFAULT "",
	encryption_cipher_text TEXT NOT NULL DEFAULT "",
	encryption_applied INT NOT NULL DEFAULT 0,
	updated_time INT NOT NULL,
	created_time INT NOT NULL,
	is_locked INT NOT NULL DEFAULT 0
);
CREATE INDEX revisions_parent_id ON revisions (parent_id);
CREATE INDEX revisions_item_type ON revisions (item_type);
CREATE INDEX revisions_item_id ON revisions (item_id);
CREATE INDEX revisions_item_updated_time ON revisions (item_updated_time);
CREATE INDEX revisions_updated_time ON revisions (updated_time);

-- resources_to_download: v22
CREATE TABLE resources_to_download (
	id INTEGER PRIMARY KEY,
	resource_id TEXT NOT NULL,
	updated_time INT NOT NULL,
	created_time INT NOT NULL
);
CREATE INDEX resources_to_download_resource_id ON resources_to_download (resource_id);
CREATE INDEX resources_to_download_updated_time ON resources_to_download (updated_time);

-- key_values: v23
CREATE TABLE key_values (
	id INTEGER PRIMARY KEY,
	`key` TEXT NOT NULL,
	`value` TEXT NOT NULL,
	`type` INT NOT NULL,
	updated_time INT NOT NULL
);
CREATE UNIQUE INDEX key_values_key ON key_values (key);

-- tags_with_note_count: migrations/46.ts
CREATE VIEW tags_with_note_count AS
	SELECT
		tags.id as id,
		tags.title as title,
		tags.created_time as created_time,
		tags.updated_time as updated_time,
		COUNT(notes.id) as note_count,
		SUM(CASE WHEN notes.todo_completed > 0 THEN 1 ELSE 0 END) AS todo_completed_count
	FROM tags
		LEFT JOIN note_tags nt on nt.tag_id = tags.id
		LEFT JOIN notes on notes.id = nt.note_id
	WHERE
		notes.id IS NOT NULL
		AND notes.deleted_time = 0
	GROUP BY tags.id;

-- notes_normalized + notes_fts (FTS4, external content): v33 + v35
CREATE TABLE notes_normalized (
	id TEXT NOT NULL,
	title TEXT NOT NULL DEFAULT "",
	body TEXT NOT NULL DEFAULT "",
	user_created_time INT NOT NULL DEFAULT 0,
	user_updated_time INT NOT NULL DEFAULT 0,
	is_todo INT NOT NULL DEFAULT 0,
	todo_completed INT NOT NULL DEFAULT 0,
	parent_id TEXT NOT NULL DEFAULT "",
	latitude NUMERIC NOT NULL DEFAULT 0,
	longitude NUMERIC NOT NULL DEFAULT 0,
	altitude NUMERIC NOT NULL DEFAULT 0,
	source_url TEXT NOT NULL DEFAULT "",
	todo_due INT NOT NULL DEFAULT 0
);
CREATE INDEX notes_normalized_id ON notes_normalized (id);
CREATE INDEX notes_normalized_user_created_time ON notes_normalized (user_created_time);
CREATE INDEX notes_normalized_user_updated_time ON notes_normalized (user_updated_time);
CREATE INDEX notes_normalized_is_todo ON notes_normalized (is_todo);
CREATE INDEX notes_normalized_todo_completed ON notes_normalized (todo_completed);
CREATE INDEX notes_normalized_parent_id ON notes_normalized (parent_id);
CREATE INDEX notes_normalized_latitude ON notes_normalized (latitude);
CREATE INDEX notes_normalized_longitude ON notes_normalized (longitude);
CREATE INDEX notes_normalized_altitude ON notes_normalized (altitude);
CREATE INDEX notes_normalized_source_url ON notes_normalized (source_url);
CREATE INDEX notes_normalized_todo_due ON notes_normalized (todo_due);

CREATE VIRTUAL TABLE notes_fts USING fts4(
	content="notes_normalized",
	notindexed="id",
	notindexed="user_created_time",
	notindexed="user_updated_time",
	notindexed="is_todo",
	notindexed="todo_completed",
	notindexed="parent_id",
	notindexed="latitude",
	notindexed="longitude",
	notindexed="altitude",
	notindexed="source_url",
	id, title, body, user_created_time, user_updated_time, is_todo, todo_completed, parent_id, latitude, longitude, altitude, source_url
);
CREATE TRIGGER notes_fts_before_update BEFORE UPDATE ON notes_normalized BEGIN
	DELETE FROM notes_fts WHERE docid=old.rowid;
END;
CREATE TRIGGER notes_fts_before_delete BEFORE DELETE ON notes_normalized BEGIN
	DELETE FROM notes_fts WHERE docid=old.rowid;
END;
CREATE TRIGGER notes_after_update AFTER UPDATE ON notes_normalized BEGIN
	INSERT INTO notes_fts(docid, id, title, body, user_created_time, user_updated_time, is_todo, todo_completed, parent_id, latitude, longitude, altitude, source_url) SELECT rowid, id, title, body, user_created_time, user_updated_time, is_todo, todo_completed, parent_id, latitude, longitude, altitude, source_url FROM notes_normalized WHERE new.rowid = notes_normalized.rowid;
END;
CREATE TRIGGER notes_after_insert AFTER INSERT ON notes_normalized BEGIN
	INSERT INTO notes_fts(docid, id, title, body, user_created_time, user_updated_time, is_todo, todo_completed, parent_id, latitude, longitude, altitude, source_url) SELECT rowid, id, title, body, user_created_time, user_updated_time, is_todo, todo_completed, parent_id, latitude, longitude, altitude, source_url FROM notes_normalized WHERE new.rowid = notes_normalized.rowid;
END;

-- items_normalized + items_fts (resource OCR text): migrations/45.ts
CREATE TABLE items_normalized (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	title TEXT NOT NULL DEFAULT "",
	body TEXT NOT NULL DEFAULT "",
	item_id TEXT NOT NULL,
	item_type INT NOT NULL,
	user_updated_time INT NOT NULL DEFAULT 0,
	reserved1 INT NULL,
	reserved2 INT NULL,
	reserved3 INT NULL,
	reserved4 INT NULL,
	reserved5 INT NULL,
	reserved6 INT NULL
);
CREATE INDEX items_normalized_id ON items_normalized (id);
CREATE INDEX items_normalized_item_id ON items_normalized (item_id);
CREATE INDEX items_normalized_item_type ON items_normalized (item_type);
CREATE VIRTUAL TABLE items_fts USING fts4(
	content="items_normalized",
	notindexed="id",
	notindexed="item_id",
	notindexed="item_type",
	notindexed="user_updated_time",
	notindexed="reserved1",
	notindexed="reserved2",
	notindexed="reserved3",
	notindexed="reserved4",
	notindexed="reserved5",
	notindexed="reserved6",
	id, title, body, item_id, item_type, user_updated_time, reserved1, reserved2, reserved3, reserved4, reserved5, reserved6
);
CREATE TRIGGER items_fts_before_update BEFORE UPDATE ON items_normalized BEGIN
	DELETE FROM items_fts WHERE docid=old.rowid;
END;
CREATE TRIGGER items_fts_before_delete BEFORE DELETE ON items_normalized BEGIN
	DELETE FROM items_fts WHERE docid=old.rowid;
END;
CREATE TRIGGER items_after_update AFTER UPDATE ON items_normalized BEGIN
	INSERT INTO items_fts(docid, id, title, body, item_id, item_type, user_updated_time, reserved1, reserved2, reserved3, reserved4, reserved5, reserved6) SELECT rowid, id, title, body, item_id, item_type, user_updated_time, reserved1, reserved2, reserved3, reserved4, reserved5, reserved6 FROM items_normalized WHERE new.rowid = items_normalized.rowid;
END;
CREATE TRIGGER items_after_insert AFTER INSERT ON items_normalized BEGIN
	INSERT INTO items_fts(docid, id, title, body, item_id, item_type, user_updated_time, reserved1, reserved2, reserved3, reserved4, reserved5, reserved6) SELECT rowid, id, title, body, item_id, item_type, user_updated_time, reserved1, reserved2, reserved3, reserved4, reserved5, reserved6 FROM items_normalized WHERE new.rowid = items_normalized.rowid;
END;
