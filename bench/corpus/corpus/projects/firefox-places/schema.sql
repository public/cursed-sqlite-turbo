-- Firefox Places (mozilla-firefox/firefox @ be3847db4e2bcc52fa3f078b8b4a1ff167ad158f, MPL-2.0).
-- Reconstructed from the C macros in toolkit/components/places/nsPlacesTables.h (CREATE_MOZ_*) and
-- nsPlacesIndexes.h (CREATE_PLACES_IDX expansions): string literals concatenated, comments dropped.
-- Deviations: moz_openpages_temp and moz_updateoriginsdelete_temp are TEMP tables in Firefox (one per
-- connection); they are created as ordinary tables here so they persist across the runner's CLI processes.
-- expiration_notify is PlacesExpiration.sys.mjs:488-497's TEMP table, also made ordinary. The triggers in
-- nsPlacesTriggers.h are TEMP triggers that call app-registered functions (store_last_inserted_id,
-- get_prefix, hash, note_sync_change, ...), so they are omitted; data.sql maintains the derived columns
-- (visit_count, last_visit_date, foreign_count, origin_id) itself.

-- nsPlacesTables.h CREATE_MOZ_PLACES
CREATE TABLE moz_places ( id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR, rev_host LONGVARCHAR, visit_count INTEGER DEFAULT 0, hidden INTEGER DEFAULT 0 NOT NULL, typed INTEGER DEFAULT 0 NOT NULL, frecency INTEGER DEFAULT -1 NOT NULL, last_visit_date INTEGER , guid TEXT, foreign_count INTEGER DEFAULT 0 NOT NULL, url_hash INTEGER DEFAULT 0 NOT NULL , description TEXT, preview_image_url TEXT, site_name TEXT, origin_id INTEGER REFERENCES moz_origins(id), recalc_frecency INTEGER NOT NULL DEFAULT 0, alt_frecency INTEGER, recalc_alt_frecency INTEGER NOT NULL DEFAULT 0);
-- nsPlacesTables.h CREATE_MOZ_HISTORYVISITS
CREATE TABLE moz_historyvisits ( id INTEGER PRIMARY KEY, from_visit INTEGER, place_id INTEGER, visit_date INTEGER, visit_type INTEGER, session INTEGER, source INTEGER DEFAULT 0 NOT NULL, triggeringPlaceId INTEGER, userContextId INTEGER NOT NULL DEFAULT 0);
-- nsPlacesTables.h CREATE_MOZ_PLACES_EXTRA
CREATE TABLE moz_places_extra ( place_id INTEGER PRIMARY KEY NOT NULL, sync_json TEXT, FOREIGN KEY (place_id) REFERENCES moz_places(id) ON DELETE CASCADE );
-- nsPlacesTables.h CREATE_MOZ_HISTORYVISITS_EXTRA
CREATE TABLE moz_historyvisits_extra ( visit_id INTEGER PRIMARY KEY NOT NULL, sync_json TEXT, FOREIGN KEY (visit_id) REFERENCES moz_historyvisits(id) ON DELETE CASCADE);
-- nsPlacesTables.h CREATE_MOZ_INPUTHISTORY
CREATE TABLE moz_inputhistory ( place_id INTEGER NOT NULL, input LONGVARCHAR NOT NULL, use_count INTEGER, PRIMARY KEY (place_id, input));
-- nsPlacesTables.h CREATE_MOZ_ANNOS
CREATE TABLE moz_annos ( id INTEGER PRIMARY KEY, place_id INTEGER NOT NULL, anno_attribute_id INTEGER, content LONGVARCHAR, flags INTEGER DEFAULT 0, expiration INTEGER DEFAULT 0, type INTEGER DEFAULT 0, dateAdded INTEGER DEFAULT 0, lastModified INTEGER DEFAULT 0);
-- nsPlacesTables.h CREATE_MOZ_ANNO_ATTRIBUTES
CREATE TABLE moz_anno_attributes ( id INTEGER PRIMARY KEY, name VARCHAR(32) UNIQUE NOT NULL);
-- nsPlacesTables.h CREATE_MOZ_ITEMS_ANNOS
CREATE TABLE moz_items_annos ( id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL, anno_attribute_id INTEGER, content LONGVARCHAR, flags INTEGER DEFAULT 0, expiration INTEGER DEFAULT 0, type INTEGER DEFAULT 0, dateAdded INTEGER DEFAULT 0, lastModified INTEGER DEFAULT 0);
-- nsPlacesTables.h CREATE_MOZ_BOOKMARKS
CREATE TABLE moz_bookmarks ( id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER DEFAULT NULL, parent INTEGER, position INTEGER, title LONGVARCHAR, keyword_id INTEGER, folder_type TEXT, dateAdded INTEGER, lastModified INTEGER, guid TEXT, syncStatus INTEGER NOT NULL DEFAULT 0, syncChangeCounter INTEGER NOT NULL DEFAULT 1);
-- nsPlacesTables.h CREATE_MOZ_BOOKMARKS_DELETED
CREATE TABLE moz_bookmarks_deleted ( guid TEXT PRIMARY KEY, dateRemoved INTEGER NOT NULL DEFAULT 0);
-- nsPlacesTables.h CREATE_MOZ_KEYWORDS
CREATE TABLE moz_keywords ( id INTEGER PRIMARY KEY AUTOINCREMENT, keyword TEXT UNIQUE, place_id INTEGER, post_data TEXT);
-- nsPlacesTables.h CREATE_MOZ_ORIGINS
CREATE TABLE moz_origins ( id INTEGER PRIMARY KEY, prefix TEXT NOT NULL, host TEXT NOT NULL, frecency INTEGER NOT NULL, recalc_frecency INTEGER NOT NULL DEFAULT 0, alt_frecency INTEGER, recalc_alt_frecency INTEGER NOT NULL DEFAULT 0, block_until_ms INTEGER, block_pages_until_ms INTEGER, UNIQUE (host, prefix) );
-- nsPlacesTables.h CREATE_MOZ_OPENPAGES_TEMP
CREATE TABLE moz_openpages_temp ( url TEXT NOT NULL, userContextId INTEGER NOT NULL, groupId TEXT NOT NULL, open_count INTEGER, PRIMARY KEY (url, userContextId, groupId));
-- nsPlacesTables.h CREATE_UPDATEORIGINSDELETE_TEMP
CREATE TABLE moz_updateoriginsdelete_temp ( prefix TEXT NOT NULL, host TEXT NOT NULL, PRIMARY KEY (prefix, host) ) WITHOUT ROWID;
-- nsPlacesTables.h CREATE_MOZ_PAGES_W_ICONS
CREATE TABLE moz_pages_w_icons ( id INTEGER PRIMARY KEY, page_url TEXT NOT NULL, page_url_hash INTEGER NOT NULL );
-- nsPlacesTables.h CREATE_MOZ_ICONS
CREATE TABLE moz_icons ( id INTEGER PRIMARY KEY, icon_url TEXT NOT NULL, fixed_icon_url_hash INTEGER NOT NULL, width INTEGER NOT NULL DEFAULT 0, root INTEGER NOT NULL DEFAULT 0, color INTEGER, expire_ms INTEGER NOT NULL DEFAULT 0, flags INTEGER NOT NULL DEFAULT 0, data BLOB );
-- nsPlacesTables.h CREATE_MOZ_ICONS_TO_PAGES
CREATE TABLE moz_icons_to_pages ( page_id INTEGER NOT NULL, icon_id INTEGER NOT NULL, expire_ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (page_id, icon_id), FOREIGN KEY (page_id) REFERENCES moz_pages_w_icons ON DELETE CASCADE, FOREIGN KEY (icon_id) REFERENCES moz_icons ON DELETE CASCADE ) WITHOUT ROWID;
-- nsPlacesTables.h CREATE_MOZ_META
CREATE TABLE moz_meta (key TEXT PRIMARY KEY, value NOT NULL) WITHOUT ROWID;
-- nsPlacesTables.h CREATE_MOZ_PLACES_METADATA
CREATE TABLE moz_places_metadata (id INTEGER PRIMARY KEY, place_id INTEGER NOT NULL, referrer_place_id INTEGER, created_at INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0, total_view_time INTEGER NOT NULL DEFAULT 0, typing_time INTEGER NOT NULL DEFAULT 0, key_presses INTEGER NOT NULL DEFAULT 0, scrolling_time INTEGER NOT NULL DEFAULT 0, scrolling_distance INTEGER NOT NULL DEFAULT 0, document_type INTEGER NOT NULL DEFAULT 0, search_query_id INTEGER, FOREIGN KEY (place_id) REFERENCES moz_places(id) ON DELETE CASCADE, FOREIGN KEY (referrer_place_id) REFERENCES moz_places(id) ON DELETE CASCADE, FOREIGN KEY(search_query_id) REFERENCES moz_places_metadata_search_queries(id) ON DELETE CASCADE CHECK(place_id != referrer_place_id) );
-- nsPlacesTables.h CREATE_MOZ_PLACES_METADATA_SEARCH_QUERIES
CREATE TABLE IF NOT EXISTS moz_places_metadata_search_queries ( id INTEGER PRIMARY KEY, terms TEXT NOT NULL UNIQUE );
-- nsPlacesTables.h CREATE_MOZ_PREVIEWS_TOMBSTONES
CREATE TABLE IF NOT EXISTS moz_previews_tombstones ( hash TEXT PRIMARY KEY ) WITHOUT ROWID;
-- nsPlacesTables.h CREATE_MOZ_NEWTAB_STORY_CLICK
CREATE TABLE moz_newtab_story_click ( feature TEXT NOT NULL, timestamp_s INTEGER NOT NULL, card_format_enum INTEGER NOT NULL, position INTEGER NOT NULL, section_position INTEGER NOT NULL, feature_value REAL NOT NULL DEFAULT 1 );
-- nsPlacesTables.h CREATE_MOZ_NEWTAB_STORY_IMPRESSION
CREATE TABLE moz_newtab_story_impression ( feature TEXT NOT NULL, timestamp_s INTEGER NOT NULL, card_format_enum INTEGER NOT NULL, position INTEGER NOT NULL, section_position INTEGER NOT NULL, feature_value REAL NOT NULL DEFAULT 1 );
-- nsPlacesTables.h CREATE_MOZ_NEWTAB_SHORTCUTS_INTERACTION
CREATE TABLE moz_newtab_shortcuts_interaction ( id INTEGER PRIMARY KEY, place_id INTEGER NOT NULL REFERENCES moz_places(id) ON DELETE CASCADE, event_type INTEGER NOT NULL, timestamp_s INTEGER NOT NULL, pinned INTEGER NOT NULL CHECK (pinned IN (0, 1)), tile_position INTEGER NOT NULL);

-- PlacesExpiration.sys.mjs:488-497 (TEMP in Firefox)
CREATE TABLE expiration_notify ( id INTEGER PRIMARY KEY, v_id INTEGER, p_id INTEGER, url TEXT NOT NULL, guid TEXT NOT NULL, visit_date INTEGER, expected_results INTEGER NOT NULL DEFAULT 0, reason TEXT NOT NULL DEFAULT "expired" );

CREATE INDEX IF NOT EXISTS moz_places_url_hashindex ON moz_places (url_hash);  -- CREATE_IDX_MOZ_PLACES_URL_HASH
CREATE INDEX IF NOT EXISTS moz_places_hostindex ON moz_places (rev_host);  -- CREATE_IDX_MOZ_PLACES_REVHOST
CREATE INDEX IF NOT EXISTS moz_places_visitcount ON moz_places (visit_count);  -- CREATE_IDX_MOZ_PLACES_VISITCOUNT
CREATE INDEX IF NOT EXISTS moz_places_frecencyindex ON moz_places (frecency);  -- CREATE_IDX_MOZ_PLACES_FRECENCY
CREATE INDEX IF NOT EXISTS moz_places_lastvisitdateindex ON moz_places (last_visit_date);  -- CREATE_IDX_MOZ_PLACES_LASTVISITDATE
CREATE UNIQUE INDEX IF NOT EXISTS moz_places_guid_uniqueindex ON moz_places (guid);  -- CREATE_IDX_MOZ_PLACES_GUID
CREATE INDEX IF NOT EXISTS moz_places_originidindex ON moz_places (origin_id);  -- CREATE_IDX_MOZ_PLACES_ORIGIN_ID
CREATE INDEX IF NOT EXISTS moz_places_altfrecencyindex ON moz_places (alt_frecency);  -- CREATE_IDX_MOZ_PLACES_ALT_FRECENCY
CREATE INDEX IF NOT EXISTS moz_historyvisits_placedateindex ON moz_historyvisits (place_id, visit_date);  -- CREATE_IDX_MOZ_HISTORYVISITS_PLACEDATE
CREATE INDEX IF NOT EXISTS moz_historyvisits_fromindex ON moz_historyvisits (from_visit);  -- CREATE_IDX_MOZ_HISTORYVISITS_FROMVISIT
CREATE INDEX IF NOT EXISTS moz_historyvisits_dateindex ON moz_historyvisits (visit_date);  -- CREATE_IDX_MOZ_HISTORYVISITS_VISITDATE
CREATE INDEX IF NOT EXISTS moz_bookmarks_itemindex ON moz_bookmarks (fk, type);  -- CREATE_IDX_MOZ_BOOKMARKS_PLACETYPE
CREATE INDEX IF NOT EXISTS moz_bookmarks_parentindex ON moz_bookmarks (parent, position);  -- CREATE_IDX_MOZ_BOOKMARKS_PARENTPOSITION
CREATE INDEX IF NOT EXISTS moz_bookmarks_itemlastmodifiedindex ON moz_bookmarks (fk, lastModified);  -- CREATE_IDX_MOZ_BOOKMARKS_PLACELASTMODIFIED
CREATE INDEX IF NOT EXISTS moz_bookmarks_dateaddedindex ON moz_bookmarks (dateAdded);  -- CREATE_IDX_MOZ_BOOKMARKS_DATEADDED
CREATE UNIQUE INDEX IF NOT EXISTS moz_bookmarks_guid_uniqueindex ON moz_bookmarks (guid);  -- CREATE_IDX_MOZ_BOOKMARKS_GUID
CREATE UNIQUE INDEX IF NOT EXISTS moz_annos_placeattributeindex ON moz_annos (place_id, anno_attribute_id);  -- CREATE_IDX_MOZ_ANNOS_PLACEATTRIBUTE
CREATE UNIQUE INDEX IF NOT EXISTS moz_items_annos_itemattributeindex ON moz_items_annos (item_id, anno_attribute_id);  -- CREATE_IDX_MOZ_ITEMSANNOS_PLACEATTRIBUTE
CREATE UNIQUE INDEX IF NOT EXISTS moz_keywords_placepostdata_uniqueindex ON moz_keywords (place_id, post_data);  -- CREATE_IDX_MOZ_KEYWORDS_PLACEPOSTDATA
CREATE INDEX IF NOT EXISTS moz_pages_w_icons_urlhashindex ON moz_pages_w_icons (page_url_hash);  -- CREATE_IDX_MOZ_PAGES_W_ICONS_ICONURLHASH
CREATE INDEX IF NOT EXISTS moz_icons_iconurlhashindex ON moz_icons (fixed_icon_url_hash);  -- CREATE_IDX_MOZ_ICONS_ICONURLHASH
CREATE UNIQUE INDEX IF NOT EXISTS moz_places_metadata_placecreated_uniqueindex ON moz_places_metadata (place_id, created_at);  -- CREATE_IDX_MOZ_PLACES_METADATA_PLACECREATED
CREATE INDEX IF NOT EXISTS moz_places_metadata_referrerindex ON moz_places_metadata (referrer_place_id);  -- CREATE_IDX_MOZ_PLACES_METADATA_REFERRER
CREATE INDEX IF NOT EXISTS moz_newtab_story_click_newtab_click_timestampindex ON moz_newtab_story_click (timestamp_s);  -- CREATE_IDX_MOZ_NEWTAB_STORY_CLICK_TIMESTAMP
CREATE INDEX IF NOT EXISTS moz_newtab_story_impression_newtab_impression_timestampindex ON moz_newtab_story_impression (timestamp_s);  -- CREATE_IDX_MOZ_NEWTAB_IMPRESSION_TIMESTAMP
CREATE INDEX IF NOT EXISTS moz_newtab_shortcuts_interaction_timestampindex ON moz_newtab_shortcuts_interaction (timestamp_s);  -- CREATE_IDX_MOZ_NEWTAB_SHORTCUTS_TIMESTAMP
CREATE INDEX IF NOT EXISTS moz_newtab_shortcuts_interaction_placeidindex ON moz_newtab_shortcuts_interaction (place_id);  -- CREATE_IDX_MOZ_NEWTAB_SHORTCUTS_PLACEID
