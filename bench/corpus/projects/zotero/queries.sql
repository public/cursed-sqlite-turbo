-- Zotero (zotero/zotero @ 584cef6, AGPL-3.0-or-later). Zotero.DB (mozStorage) with `?` positional parameters; most
-- SQL is assembled by string concatenation in chrome/content/zotero/xpcom/data/*.js, so the builders below are one
-- representative instantiation each (tagged dynamic), with placeholders numbered ?N in argument order. Item-type,
-- field and creator-type ids come from the global schema at runtime; see data.sql for the ids used here.

-- @id zotero.items.primary_data
-- @src chrome/content/zotero/xpcom/data/items.js:37-100 (+ _getFirstCreatorSQL 1549-1604, _getSortCreatorSQL 1610-1665), chrome/content/zotero/xpcom/data/dataObjects.js:540-556, 1076-1081
-- @style ? positional, SELECT list and FROM assembled from _primaryDataSQLParts
-- @tags hotpath,dynamic
-- @note Library load for the item tree: 10-way LEFT JOIN plus firstCreator/sortCreator built as COALESCE over 4 CASE blocks, each a correlated COUNT with up to 3 correlated ORDER BY/LIMIT-offset subqueries and PRINTF -- dozens of correlated subqueries per row.
-- @param ?1 1
SELECT O.itemID, O.itemTypeID, O.dateAdded, O.dateModified, O.libraryID, O.key, O.version, O.clientVersion, O.synced, createdByUserID, lastModifiedByUserID, COALESCE(CASE (SELECT COUNT(*) FROM itemCreators IC LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1) WHEN 0 THEN NULL WHEN 1 THEN (SELECT lastName FROM itemCreators IC NATURAL JOIN creators LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1) WHEN 2 THEN (SELECT PRINTF('%s and %s', (SELECT '⁨' || lastName || '⁩' FROM itemCreators IC NATURAL JOIN creators LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1 ORDER BY orderIndex LIMIT 1), (SELECT '⁨' || lastName || '⁩' FROM itemCreators IC NATURAL JOIN creators LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1 ORDER BY orderIndex LIMIT 1,1) )) ELSE (SELECT (SELECT lastName FROM itemCreators IC NATURAL JOIN creators LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1 ORDER BY orderIndex LIMIT 1) || ' et al.' ) END, CASE (SELECT COUNT(*) FROM itemCreators IC WHERE itemID=O.itemID AND creatorTypeID=3) WHEN 0 THEN NULL WHEN 1 THEN (SELECT lastName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=3) WHEN 2 THEN (SELECT PRINTF('%s and %s', (SELECT '⁨' || lastName || '⁩' FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=3 ORDER BY orderIndex LIMIT 1), (SELECT '⁨' || lastName || '⁩' FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=3 ORDER BY orderIndex LIMIT 1,1) )) ELSE (SELECT (SELECT lastName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=3 ORDER BY orderIndex LIMIT 1) || ' et al.' ) END, CASE (SELECT COUNT(*) FROM itemCreators IC WHERE itemID=O.itemID AND creatorTypeID=10) WHEN 0 THEN NULL WHEN 1 THEN (SELECT lastName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=10) WHEN 2 THEN (SELECT PRINTF('%s and %s', (SELECT '⁨' || lastName || '⁩' FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=10 ORDER BY orderIndex LIMIT 1), (SELECT '⁨' || lastName || '⁩' FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=10 ORDER BY orderIndex LIMIT 1,1) )) ELSE (SELECT (SELECT lastName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=10 ORDER BY orderIndex LIMIT 1) || ' et al.' ) END, CASE (SELECT COUNT(*) FROM itemCreators IC WHERE itemID=O.itemID AND creatorTypeID=2) WHEN 0 THEN NULL WHEN 1 THEN (SELECT lastName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=2) WHEN 2 THEN (SELECT PRINTF('%s and %s', (SELECT '⁨' || lastName || '⁩' FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=2 ORDER BY orderIndex LIMIT 1), (SELECT '⁨' || lastName || '⁩' FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=2 ORDER BY orderIndex LIMIT 1,1) )) ELSE (SELECT (SELECT lastName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=2 ORDER BY orderIndex LIMIT 1) || ' et al.' ) END) AS firstCreator, COALESCE(CASE (SELECT COUNT(*) FROM itemCreators IC LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1) WHEN 0 THEN NULL WHEN 1 THEN (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1) WHEN 2 THEN (SELECT (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1 ORDER BY orderIndex LIMIT 1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1 ORDER BY orderIndex LIMIT 1,1)) ELSE (SELECT (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1 ORDER BY orderIndex LIMIT 1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1 ORDER BY orderIndex LIMIT 1,1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators LEFT JOIN itemTypeCreatorTypes ITCT ON (IC.creatorTypeID=ITCT.creatorTypeID AND ITCT.itemTypeID=O.itemTypeID) WHERE itemID=O.itemID AND primaryField=1 ORDER BY orderIndex LIMIT 2,1)) END, CASE (SELECT COUNT(*) FROM itemCreators IC WHERE itemID=O.itemID AND creatorTypeID=3) WHEN 0 THEN NULL WHEN 1 THEN (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=3) WHEN 2 THEN (SELECT (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=3 ORDER BY orderIndex LIMIT 1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=3 ORDER BY orderIndex LIMIT 1,1)) ELSE (SELECT (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=3 ORDER BY orderIndex LIMIT 1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=3 ORDER BY orderIndex LIMIT 1,1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=3 ORDER BY orderIndex LIMIT 2,1)) END, CASE (SELECT COUNT(*) FROM itemCreators IC WHERE itemID=O.itemID AND creatorTypeID=10) WHEN 0 THEN NULL WHEN 1 THEN (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=10) WHEN 2 THEN (SELECT (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=10 ORDER BY orderIndex LIMIT 1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=10 ORDER BY orderIndex LIMIT 1,1)) ELSE (SELECT (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=10 ORDER BY orderIndex LIMIT 1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=10 ORDER BY orderIndex LIMIT 1,1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=10 ORDER BY orderIndex LIMIT 2,1)) END, CASE (SELECT COUNT(*) FROM itemCreators IC WHERE itemID=O.itemID AND creatorTypeID=2) WHEN 0 THEN NULL WHEN 1 THEN (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=2) WHEN 2 THEN (SELECT (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=2 ORDER BY orderIndex LIMIT 1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=2 ORDER BY orderIndex LIMIT 1,1)) ELSE (SELECT (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=2 ORDER BY orderIndex LIMIT 1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=2 ORDER BY orderIndex LIMIT 1,1) || ' ' || (SELECT lastName || ' ' || firstName FROM itemCreators IC NATURAL JOIN creators WHERE itemID=O.itemID AND creatorTypeID=2 ORDER BY orderIndex LIMIT 2,1)) END) AS sortCreator, DI.itemID IS NOT NULL AS deleted, PI.itemID IS NOT NULL AS inPublications, (CASE O.itemTypeID WHEN 3 THEN IAP.itemID WHEN 27 THEN INoP.itemID WHEN 1 THEN IAnP.itemID END) AS parentID, (CASE O.itemTypeID WHEN 3 THEN IAP.key WHEN 27 THEN INoP.key WHEN 1 THEN IAnP.key END) AS parentKey, CS.charset AS attachmentCharset, IA.linkMode AS attachmentLinkMode, IA.contentType AS attachmentContentType, IA.path AS attachmentPath, IA.syncState AS attachmentSyncState, IA.storageModTime AS attachmentSyncedModificationTime, IA.storageHash AS attachmentSyncedHash, IA.lastProcessedModificationTime AS attachmentLastProcessedModificationTime, IA.lastRead AS attachmentLastRead FROM items O LEFT JOIN itemAttachments IA USING (itemID) LEFT JOIN items IAP ON (IA.parentItemID=IAP.itemID) LEFT JOIN itemNotes INo ON (O.itemID=INo.itemID) LEFT JOIN items INoP ON (INo.parentItemID=INoP.itemID) LEFT JOIN itemAnnotations IAn ON (O.itemID=IAn.itemID) LEFT JOIN items IAnP ON (IAn.parentItemID=IAnP.itemID) LEFT JOIN deletedItems DI ON (O.itemID=DI.itemID) LEFT JOIN publicationsItems PI ON (O.itemID=PI.itemID) LEFT JOIN charsets CS ON (IA.charsetID=CS.charsetID)LEFT JOIN groupItems GI ON (O.itemID=GI.itemID) WHERE 1 AND O.libraryID=?1;

-- @id zotero.items.load_item_data
-- @src chrome/content/zotero/xpcom/data/items.js:259-265
-- @style ? positional, idSQL suffix empty for a full-library load
-- @tags hotpath,dynamic
-- @note Field values for every non-note item in the library: three-way join through itemDataValues.
-- @param ?1 1
-- @param ?2 27
SELECT itemID, fieldID, value FROM items JOIN itemData USING (itemID) JOIN itemDataValues USING (valueID) WHERE libraryID=?1 AND itemTypeID!=?2;

-- @id zotero.items.load_note_titles
-- @src chrome/content/zotero/xpcom/data/items.js:329-331
-- @style ? positional
-- @tags hotpath
-- @note Note titles for the item tree, excluding attachment notes via NOT IN.
-- @param ?1 1
SELECT itemID, title FROM items JOIN itemNotes USING (itemID) WHERE libraryID=?1 AND itemID NOT IN (SELECT itemID FROM itemAttachments);

-- @id zotero.items.load_creators
-- @src chrome/content/zotero/xpcom/data/items.js:397-401
-- @style ? positional
-- @tags hotpath
-- @note Creators of every item in the library, LEFT JOIN with ORDER BY itemID, orderIndex.
-- @param ?1 1
SELECT itemID, creatorID, creatorTypeID, orderIndex FROM items LEFT JOIN itemCreators USING (itemID) WHERE libraryID=?1 ORDER BY itemID, orderIndex;

-- @id zotero.items.child_attachments
-- @src chrome/content/zotero/xpcom/data/items.js:693-707
-- @style ? positional, title fieldID inlined, IN list of parents appended
-- @tags hotpath,dynamic
-- @note Child attachments of the visible parents with their title (LEFT JOIN itemData/itemDataValues on an inlined fieldID) and a trashed CASE flag.
-- @param ?1 1
SELECT parentItemID, A.itemID, value AS title, CASE WHEN DI.itemID IS NULL THEN 0 ELSE 1 END AS trashed FROM itemAttachments A JOIN items I ON (A.parentItemID=I.itemID) LEFT JOIN itemData ID ON (fieldID=1 AND A.itemID=ID.itemID) LEFT JOIN itemDataValues IDV USING (valueID) LEFT JOIN deletedItems DI USING (itemID) WHERE libraryID=?1 AND parentItemID IN (12, 33, 54, 75, 96, 117, 138, 159, 180, 201, 222, 243, 264, 285, 306, 327, 348, 369, 390, 411, 432, 453, 474, 495, 516, 537, 558, 579, 600, 621, 642, 663, 684, 705, 726, 747, 768, 789, 810, 831) ORDER BY parentItemID;

-- @id zotero.items.child_notes
-- @src chrome/content/zotero/xpcom/data/items.js:745-755
-- @style ? positional, sortNotesChronologically pref adds ", dateAdded"
-- @tags dynamic
-- @note Child notes of every parent in the library (no id list: full load), ordered chronologically.
-- @param ?1 1
SELECT parentItemID, N.itemID, title, CASE WHEN DI.itemID IS NULL THEN 0 ELSE 1 END AS trashed FROM itemNotes N JOIN items I ON (N.parentItemID=I.itemID) LEFT JOIN deletedItems DI USING (itemID) WHERE libraryID=?1 ORDER BY parentItemID, dateAdded;

-- @id zotero.items.child_annotations
-- @src chrome/content/zotero/xpcom/data/items.js:799-807
-- @style ? positional
-- @tags dynamic
-- @note Annotations per attachment with a concatenated title, ordered by parent then the text sortIndex.
-- @param ?1 1
SELECT parentItemID, IAn.itemID, text || ' - ' || comment AS title, CASE WHEN DI.itemID IS NULL THEN 0 ELSE 1 END AS trashed FROM itemAnnotations IAn JOIN items I ON (IAn.parentItemID=I.itemID) LEFT JOIN deletedItems DI USING (itemID) WHERE libraryID=?1 ORDER BY parentItemID, sortIndex;

-- @id zotero.items.load_tags
-- @src chrome/content/zotero/xpcom/data/items.js:865-868
-- @style ? positional
-- @tags hotpath
-- @note Tags of every item: LEFT JOIN chain items -> itemTags -> tags.
-- @param ?1 1
SELECT itemID, name, type FROM items LEFT JOIN itemTags USING (itemID) LEFT JOIN tags USING (tagID) WHERE libraryID=?1;

-- @id zotero.items.load_relations
-- @src chrome/content/zotero/xpcom/data/dataObjects.js:613-622
-- @style ? positional, table names by string concatenation
-- @tags dynamic
-- @note Relations load: LEFT JOIN through itemRelations and relationPredicates.
-- @param ?1 1
SELECT itemID, predicate, object FROM items LEFT JOIN itemRelations USING (itemID) LEFT JOIN relationPredicates USING (predicateID) WHERE libraryID=?1;

-- @id zotero.collections.primary_data
-- @src chrome/content/zotero/xpcom/data/collections.js:35-57, chrome/content/zotero/xpcom/data/dataObjects.js:540-556
-- @style ? positional, assembled from _primaryDataSQLParts
-- @tags hotpath,dynamic
-- @note Collection tree load: self LEFT JOIN for the parent key plus two correlated COUNT(*) != 0 flags per collection.
-- @param ?1 1
SELECT O.collectionID, O.collectionName AS name, O.libraryID, O.key, O.version, O.clientVersion, O.synced, DC.collectionID IS NOT NULL AS deleted, O.parentCollectionID AS parentID, CP.key AS parentKey, (SELECT COUNT(*) FROM collections WHERE parentCollectionID=O.collectionID) != 0 AS hasChildCollections, (SELECT COUNT(*) FROM collectionItems WHERE collectionID=O.collectionID) != 0 AS hasChildItems FROM collections O LEFT JOIN deletedCollections DC ON (O.collectionID=DC.collectionID)LEFT JOIN collections CP ON (O.parentCollectionID=CP.collectionID)  WHERE 1 AND O.libraryID=?1;

-- @id zotero.collections.load_child_items
-- @src chrome/content/zotero/xpcom/data/collections.js:273-276
-- @style ? positional
-- @tags hotpath
-- @note Item membership of every collection in the library (feeds the per-collection item sets).
-- @param ?1 1
SELECT collectionID, itemID FROM collections LEFT JOIN collectionItems USING (collectionID) WHERE libraryID=?1;

-- @id zotero.search.collection_scope
-- @src chrome/content/zotero/xpcom/data/search.js:1017-1340, 2215-2228 (_buildQuery, _deletedItemsSQL), scope from chrome/content/zotero/xpcom/collectionTreeRow.js:451-461
-- @style ? positional, built by Zotero.Search._buildQuery
-- @tags hotpath,dynamic
-- @note Item-tree scope for a collection with recursiveCollections on: NOT IN a 5-branch UNION of trashed items and their children, three NOT IN child filters, library and collection IN subqueries.
-- @modified the app runs this as "CREATE TEMPORARY TABLE tmpSearchResults_<random> AS <this>" (search.js:629); the bare SELECT is kept here and its result is preloaded into tmpSearchResults_scope
-- @param ?1 1
SELECT itemID FROM items WHERE (itemID NOT  IN (SELECT itemID FROM deletedItems UNION SELECT itemID FROM itemNotes WHERE parentItemID IS NOT NULL AND parentItemID IN (SELECT itemID FROM deletedItems) UNION SELECT itemID FROM itemAttachments WHERE parentItemID IS NOT NULL AND parentItemID IN (SELECT itemID FROM deletedItems)UNION SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM deletedItems)UNION SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID IN (SELECT itemID FROM deletedItems)))) AND (itemID NOT IN (SELECT itemID FROM itemNotes WHERE parentItemID IS NOT NULL) AND itemID NOT IN (SELECT itemID FROM itemAttachments WHERE parentItemID IS NOT NULL) AND itemID NOT IN (SELECT itemID FROM itemAnnotations WHERE parentItemID IS NOT NULL)) AND (itemID IN (SELECT itemID FROM items WHERE libraryID=?1)) AND itemID IN (SELECT itemID FROM collectionItems WHERE (collectionID IN (5, 52, 82, 112)));

-- @id zotero.search.quicksearch_title_creator_year
-- @src chrome/content/zotero/xpcom/data/search.js:315-375 (quicksearch expansion), 1017-2068 (_buildQuery), 2111-2210 (combineConditions), 636-656 (scoped search)
-- @style ? positional, built by Zotero.Search._buildQuery; the outer statement wraps it in the scope temp table
-- @tags hotpath,dynamic
-- @note Typing "smith" in the item tree's Title/Creator/Year box inside a collection: GROUP_CONCAT over items IN (base search AND (7-way OR of itemData/creator IN-subqueries with LIKE)), intersected with the scope table and its children.
-- @param ?1 1
-- @param ?2 1
-- @param ?3 25
-- @param ?4 26
-- @param ?5 27
-- @param ?6 '%smith%'
-- @param ?7 8
-- @param ?8 50
-- @param ?9 52
-- @param ?10 '%smith%'
-- @param ?11 10
-- @param ?12 '%smith%'
-- @param ?13 20
-- @param ?14 '%smith%'
-- @param ?15 6
-- @param ?16 30
-- @param ?17 31
-- @param ?18 32
-- @param ?19 '%smith%'
-- @param ?20 40
-- @param ?21 '%smith%'
-- @param ?22 '%smith%'
SELECT GROUP_CONCAT(itemID) FROM items WHERE itemID IN (SELECT itemID FROM items WHERE (itemID NOT  IN (SELECT itemID FROM deletedItems UNION SELECT itemID FROM itemNotes WHERE parentItemID IS NOT NULL AND parentItemID IN (SELECT itemID FROM deletedItems) UNION SELECT itemID FROM itemAttachments WHERE parentItemID IS NOT NULL AND parentItemID IN (SELECT itemID FROM deletedItems)UNION SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM deletedItems)UNION SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID IN (SELECT itemID FROM deletedItems)))) AND (itemID NOT IN (SELECT itemID FROM itemNotes WHERE parentItemID IS NOT NULL) AND itemID NOT IN (SELECT itemID FROM itemAttachments WHERE parentItemID IS NOT NULL) AND itemID NOT IN (SELECT itemID FROM itemAnnotations WHERE parentItemID IS NOT NULL)) AND (itemID IN (SELECT itemID FROM items WHERE libraryID=?1)) AND (itemID IN (SELECT itemID FROM itemData WHERE (fieldID IN (?2,?3,?4,?5) AND valueID IN (SELECT valueID FROM itemDataValues WHERE COALESCE(valueNormalized, value) LIKE ?6))) OR itemID IN (SELECT itemID FROM itemData WHERE (fieldID IN (?7,?8,?9) AND valueID IN (SELECT valueID FROM itemDataValues WHERE COALESCE(valueNormalized, value) LIKE ?10))) OR itemID IN (SELECT itemID FROM itemData WHERE (fieldID=?11 AND valueID IN (SELECT valueID FROM itemDataValues WHERE COALESCE(valueNormalized, value) LIKE ?12))) OR itemID IN (SELECT itemID FROM itemData WHERE (fieldID=?13 AND valueID IN (SELECT valueID FROM itemDataValues WHERE COALESCE(valueNormalized, value) LIKE ?14))) OR itemID IN (SELECT itemID FROM itemData WHERE (fieldID IN (?15,?16,?17,?18) AND valueID IN (SELECT valueID FROM itemDataValues WHERE SUBSTR(value, 1, 4) LIKE ?19))) OR itemID IN (SELECT itemID FROM itemData WHERE (fieldID=?20 AND valueID IN (SELECT valueID FROM itemDataValues WHERE COALESCE(valueNormalized, value) LIKE ?21))) OR itemID IN (SELECT itemID FROM itemCreators WHERE (creatorID IN (SELECT creatorID FROM creators WHERE TRIM(COALESCE(firstNameNormalized, firstName) || ' ' || COALESCE(lastNameNormalized, lastName)) LIKE ?22))))) AND (itemID IN (SELECT itemID FROM tmpSearchResults_scope) OR itemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID IN (SELECT itemID FROM tmpSearchResults_scope)) OR itemID IN (SELECT itemID FROM itemNotes WHERE parentItemID IN (SELECT itemID FROM tmpSearchResults_scope)) OR itemID IN ( SELECT itemID FROM itemAnnotations WHERE  parentItemID IN ( SELECT itemID FROM itemAttachments WHERE  parentItemID IN ( SELECT itemID FROM tmpSearchResults_scope))) OR itemID IN (SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM tmpSearchResults_scope)));

-- @id zotero.search.tag_selector_two_tags
-- @src chrome/content/zotero/xpcom/data/search.js:1017-2068 (tag condition at search.js:1645-1648), chrome/content/zotero/xpcom/collectionTreeRow.js:487-506
-- @style ? positional, built by Zotero.Search._buildQuery
-- @tags hotpath,dynamic
-- @note Two tags selected in the tag selector: ANDed IN-subqueries on itemTags/tags with COLLATE NOCASE equality, scoped to the collection's items and their children.
-- @param ?1 1
-- @param ?2 'to-read'
-- @param ?3 'review'
SELECT GROUP_CONCAT(itemID) FROM items WHERE itemID IN (SELECT itemID FROM items WHERE (itemID NOT  IN (SELECT itemID FROM deletedItems UNION SELECT itemID FROM itemNotes WHERE parentItemID IS NOT NULL AND parentItemID IN (SELECT itemID FROM deletedItems) UNION SELECT itemID FROM itemAttachments WHERE parentItemID IS NOT NULL AND parentItemID IN (SELECT itemID FROM deletedItems)UNION SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM deletedItems)UNION SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID IN (SELECT itemID FROM deletedItems)))) AND (itemID IN (SELECT itemID FROM items WHERE libraryID=?1)) AND itemID IN (SELECT itemID FROM itemTags WHERE (tagID IN (SELECT tagID FROM tags WHERE COALESCE(nameNormalized, name)=?2 COLLATE NOCASE))) AND itemID IN (SELECT itemID FROM itemTags WHERE (tagID IN (SELECT tagID FROM tags WHERE COALESCE(nameNormalized, name)=?3 COLLATE NOCASE)))) AND (itemID IN (SELECT itemID FROM tmpSearchResults_scope) OR itemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID IN (SELECT itemID FROM tmpSearchResults_scope)) OR itemID IN (SELECT itemID FROM itemNotes WHERE parentItemID IN (SELECT itemID FROM tmpSearchResults_scope)) OR itemID IN ( SELECT itemID FROM itemAnnotations WHERE  parentItemID IN ( SELECT itemID FROM itemAttachments WHERE  parentItemID IN ( SELECT itemID FROM tmpSearchResults_scope))) OR itemID IN (SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM tmpSearchResults_scope)));

-- @id zotero.search.quicksearch_all_fields_fts
-- @src chrome/content/zotero/xpcom/data/search.js:340-352, 1694-1705 (note via FTS), chrome/content/zotero/xpcom/fulltext.js:2528-2610 (getNoteContentSQL)
-- @style ? positional, built by Zotero.Search._buildQuery; stale-note ids inlined by getNoteContentSQL
-- @tags hotpath,dynamic,fts
-- @note "All Fields & Tags" quick search: OR of six predicates, including a trigram FTS5 MATCH on the contentless note index with inlined stale-note exclusions, LIKE on annotation text/comment, tags and creators.
-- @modified the app's FTS tables live in the attached `ftindex` database (ftindex.fulltextNotes); the prefix is dropped here
-- @param ?1 1
-- @param ?2 '%neural%'
-- @param ?3 '%neural%'
-- @param ?4 '"neural"'
-- @param ?5 '%neural%'
-- @param ?6 '%neural%'
-- @param ?7 '%neural%'
SELECT GROUP_CONCAT(itemID) FROM items WHERE itemID IN (SELECT itemID FROM items WHERE (itemID NOT  IN (SELECT itemID FROM deletedItems UNION SELECT itemID FROM itemNotes WHERE parentItemID IS NOT NULL AND parentItemID IN (SELECT itemID FROM deletedItems) UNION SELECT itemID FROM itemAttachments WHERE parentItemID IS NOT NULL AND parentItemID IN (SELECT itemID FROM deletedItems)UNION SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM deletedItems)UNION SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID IN (SELECT itemID FROM deletedItems)))) AND (itemID IN (SELECT itemID FROM items WHERE libraryID=?1)) AND (itemID IN (SELECT itemID FROM itemData WHERE (valueID IN (SELECT valueID FROM itemDataValues WHERE COALESCE(valueNormalized, value) LIKE ?2))) OR itemID IN (SELECT itemID FROM itemTags WHERE (tagID IN (SELECT tagID FROM tags WHERE COALESCE(nameNormalized, name) LIKE ?3))) OR itemID IN (SELECT itemID FROM itemNotes WHERE (((itemID NOT IN (18079,18180,18281,18382,18483,18584,18685,18786,18887,18988,19089,19190,19291,19392,19493,19594,19695,19796,19897,19998,20099,20200,20301,20402,20503,20604,20705,20806,20907) AND itemID IN (SELECT rowid FROM fulltextNotes WHERE fulltextNotes MATCH ?4)) OR itemID IN (18180,18483,18584,18887,18988,19392,19493,19998,20099,20200,20503,20806)))) OR itemID IN (SELECT itemID FROM itemAnnotations WHERE (COALESCE(textNormalized, text) LIKE ?5)) OR itemID IN (SELECT itemID FROM itemAnnotations WHERE (COALESCE(commentNormalized, comment) LIKE ?6)) OR itemID IN (SELECT itemID FROM itemCreators WHERE (creatorID IN (SELECT creatorID FROM creators WHERE TRIM(COALESCE(firstNameNormalized, firstName) || ' ' || COALESCE(lastNameNormalized, lastName)) LIKE ?7))))) AND (itemID IN (SELECT itemID FROM tmpSearchResults_scope) OR itemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID IN (SELECT itemID FROM tmpSearchResults_scope)) OR itemID IN (SELECT itemID FROM itemNotes WHERE parentItemID IN (SELECT itemID FROM tmpSearchResults_scope)) OR itemID IN ( SELECT itemID FROM itemAnnotations WHERE  parentItemID IN ( SELECT itemID FROM itemAttachments WHERE  parentItemID IN ( SELECT itemID FROM tmpSearchResults_scope))) OR itemID IN (SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM tmpSearchResults_scope)));

-- @id zotero.fulltext.find_items_with_content
-- @src chrome/content/zotero/xpcom/fulltext.js:2632-2642
-- @style ? positional, table name from getWordMatchClause
-- @tags hotpath,dynamic,fts
-- @note Full-text content search: prefix-phrase MATCH on the contentless unicode61 index joined to items by rowid.
-- @modified `ftindex.fulltextContent` -> `fulltextContent` (the app attaches the index as a separate database)
-- @param ?1 '"archive"*'
-- @param ?2 1
SELECT C.rowid FROM fulltextContent C JOIN items I ON (I.itemID = C.rowid) WHERE C.fulltextContent MATCH ?1 AND I.libraryID=?2;

-- @id zotero.tags.get_all_within_scope
-- @src chrome/content/zotero/xpcom/data/tags.js:166-196 (getAllWithin with tmpTable)
-- @style string-built, temp table name inlined
-- @tags hotpath,dynamic
-- @note Tag selector contents for the current view: DISTINCT string-concatenated tagID:type over a UNION'd item set, NOCASE sort.
SELECT DISTINCT tagID || ':' || type FROM itemTags JOIN tags USING (tagID) WHERE 1 AND itemID IN (SELECT itemID FROM tmpSearchResults_scope UNION SELECT itemID FROM itemAnnotations WHERE parentItemID IN (SELECT itemID FROM tmpSearchResults_scope)) ORDER BY name COLLATE NOCASE;

-- @id zotero.tags.count_items
-- @src chrome/content/zotero/xpcom/data/tags.js:243-246
-- @style ? positional
-- @tags hot-small
-- @note Per-tag item count for the API/JSON response.
-- @param ?1 6
-- @param ?2 0
-- @param ?3 1
SELECT COUNT(itemID) FROM tags JOIN itemTags USING (tagID) JOIN items USING (itemID) WHERE tagID = ?1 AND type = ?2 AND libraryID = ?3;

-- @id zotero.sync.get_unsynced_items
-- @src chrome/content/zotero/xpcom/sync/syncLocal.js:788-800
-- @style ? positional, joins added for objectType 'item'
-- @tags hotpath,dynamic
-- @note Upload phase: locally modified items, excluding external annotations, via three LEFT JOINs.
-- @param ?1 1
SELECT O.itemID FROM items O LEFT JOIN itemAttachments IA USING (itemID) LEFT JOIN itemNotes INo ON (O.itemID=INo.itemID) LEFT JOIN itemAnnotations IAn ON (O.itemID=IAn.itemID) WHERE libraryID=?1 AND synced=0 AND (IAn.isExternal IS NULL OR IAN.isExternal=0);

-- @id zotero.sync.latest_cache_versions
-- @src chrome/content/zotero/xpcom/sync/syncLocal.js:855-870
-- @style ? positional, key IN list in chunks
-- @tags hotpath,dynamic
-- @note Download phase: newest cached version per key via MAX(version) GROUP BY with an IN (SELECT ... name=?) type filter.
-- @param ?1 1
-- @param ?2 'item'
-- @param ?3 'D8331840'
-- @param ?4 '89464158'
-- @param ?5 '3A596A70'
-- @param ?6 'EB6C9388'
SELECT key, MAX(version) AS version FROM syncCache WHERE libraryID=?1 AND syncObjectTypeID IN (SELECT syncObjectTypeID FROM syncObjectTypes WHERE name=?2) AND key IN (?3, ?4, ?5, ?6) GROUP BY libraryID, key;

-- @id zotero.sync.latest_cache_version_one
-- @src chrome/content/zotero/xpcom/sync/syncLocal.js:897-902
-- @style ? positional
-- @tags hot-small
-- @note Single-object newest cache version: top-1 on the syncCache primary key.
-- @param ?1 1
-- @param ?2 'D8331840'
-- @param ?3 'item'
SELECT version FROM syncCache WHERE libraryID=?1 AND key=?2 AND syncObjectTypeID IN (SELECT syncObjectTypeID FROM syncObjectTypes WHERE name=?3) ORDER BY VERSION DESC LIMIT 1;

-- @id zotero.sync.get_cache_objects
-- @src chrome/content/zotero/xpcom/sync/syncLocal.js:926-944
-- @style ? positional, key/version pairs inlined as a UNION SELECT derived table (chunks of 240)
-- @tags hotpath,dynamic
-- @note Conflict resolution: JOIN against a compound-SELECT derived table of (key, version) literal pairs.
-- @param ?1 1
-- @param ?2 'item'
SELECT data FROM syncCache SC JOIN (SELECT 'D8331840' AS key, 2141 AS version UNION SELECT '89464158' AS key, 1156 AS version UNION SELECT '3A596A70' AS key, 170 AS version UNION SELECT 'EB6C9388' AS key, 3186 AS version) AS pairs ON (pairs.key=SC.key AND pairs.version=SC.version) WHERE libraryID=?1 AND syncObjectTypeID IN (SELECT syncObjectTypeID FROM syncObjectTypes WHERE name=?2);

-- @id zotero.sync.purge_cache
-- @src chrome/content/zotero/xpcom/sync/syncLocal.js:1609-1619
-- @style ? positional, object table by string concatenation
-- @tags dynamic
-- @note After sync: delete stale cache rows via ROWID IN (LEFT JOIN USING (libraryID, key, version) anti-join).
-- @param ?1 3
-- @param ?2 1
DELETE FROM syncCache WHERE ROWID IN (SELECT SC.ROWID FROM syncCache SC LEFT JOIN items O USING (libraryID, key, version) WHERE syncObjectTypeID=?1 AND SC.libraryID=?2 AND (O.libraryID IS NULL OR SC.version < O.version));

-- @id zotero.duplicates.titles
-- @src chrome/content/zotero/xpcom/duplicates.js:278-287
-- @style ? positional, field and type ids inlined
-- @tags dynamic
-- @note Duplicate detection: every title-like field value outside notes/attachments and the trash.
-- @param ?1 1
SELECT itemID, value FROM items JOIN itemData USING (itemID) JOIN itemDataValues USING (valueID) WHERE libraryID=?1 AND fieldID IN (25, 1) AND itemTypeID NOT IN (3, 27) AND itemID NOT IN (SELECT itemID FROM deletedItems);

-- @id zotero.duplicates.creators
-- @src chrome/content/zotero/xpcom/duplicates.js:304-309
-- @style ? positional, type ids inlined
-- @tags dynamic
-- @note Duplicate detection: all creators by item and order (4-way join, NOT IN trash, ORDER BY).
-- @param ?1 1
SELECT itemID, lastName, firstName, fieldMode FROM items JOIN itemCreators USING (itemID) JOIN creators USING (creatorID) WHERE libraryID=?1 AND itemTypeID NOT IN (3, 27) AND itemID NOT IN (SELECT itemID FROM deletedItems)ORDER BY itemID, orderIndex;

-- @id zotero.duplicates.years
-- @src chrome/content/zotero/xpcom/duplicates.js:257-268
-- @style ? positional
-- @tags dynamic
-- @note Duplicate detection: SUBSTR year of every date field, sorted by value.
-- @param ?1 1
-- @param ?2 6
-- @param ?3 30
-- @param ?4 31
-- @param ?5 32
SELECT itemID, SUBSTR(value, 1, 4) AS year FROM items JOIN itemData USING (itemID) JOIN itemDataValues USING (valueID) WHERE libraryID=?1 AND fieldID IN (?2,?3,?4,?5) AND SUBSTR(value, 1, 4) != '0000' AND itemID NOT IN (SELECT itemID FROM deletedItems) ORDER BY value;

-- @id zotero.item.value_id_lookup
-- @src chrome/content/zotero/xpcom/data/item.js:1748
-- @style ? positional
-- @tags hot-small
-- @note Saving a field: find the existing value row through the UNIQUE(value) index.
-- @param ?1 'Syntax networks and the galaxy of Smith 515'
SELECT valueID FROM itemDataValues WHERE value=?1;

-- @id zotero.item.next_collection_order_index
-- @src chrome/content/zotero/xpcom/data/item.js:2331-2333
-- @style ? positional
-- @tags hot-small
-- @note Adding an item to a collection: IFNULL(MAX(orderIndex)+1, 0) over one collection.
-- @param ?1 5
SELECT IFNULL(MAX(orderIndex)+1, 0) FROM collectionItems WHERE collectionID=?1;

-- @id zotero.item.add_to_collection
-- @src chrome/content/zotero/xpcom/data/item.js:2335-2337
-- @style ? positional
-- @tags hot-small
-- @note Short INSERT OR IGNORE that fires two BEFORE INSERT triggers (library check, UNION child-item check).
-- @param ?1 5
-- @param ?2 7577
-- @param ?3 10
INSERT OR IGNORE INTO collectionItems (collectionID, itemID, orderIndex) VALUES (?1, ?2, ?3);

-- @id zotero.creators.id_from_data
-- @src chrome/content/zotero/xpcom/data/creators.js:105-109
-- @style ? positional
-- @tags hot-small
-- @note Creator dedup on save: lookup on the UNIQUE (lastName, firstName, fieldMode) index.
-- @param ?1 'Hiro'
-- @param ?2 'Müller'
-- @param ?3 0
SELECT creatorID FROM creators WHERE firstName=?1 AND lastName=?2 AND fieldMode=?3;
