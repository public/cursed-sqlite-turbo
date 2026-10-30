-- zotero/zotero @ 584cef63b5a9349e508185cbcdc5840530a23704 (AGPL-3.0-or-later). Only the CREATE statements the
-- queries need:
--   * tables and indexes from resource/schema/userdata.sql (verbatim, in file order)
--   * charsets and syncObjectTypes from resource/schema/system.sql
--   * the collectionItems triggers from resource/schema/triggers.sql (the ";---" executeSQLFile hack is dropped)
--   * the full-text index tables that chrome/content/zotero/xpcom/fulltext.js creates in the attached `ftindex`
--     database; here they live in the main database (queries drop the `ftindex.` prefix, see @modified)
--   * tmpSearchResults_scope: stands in for the per-search "CREATE TEMPORARY TABLE tmpSearchResults_<random> AS
--     <scope search>" + "CREATE INDEX ..._itemID" in chrome/content/zotero/xpcom/data/search.js:629-633

CREATE TABLE itemTypesCombined (
    itemTypeID INT NOT NULL,
    typeName TEXT NOT NULL,
    display INT DEFAULT 1 NOT NULL,
    custom INT NOT NULL,
    PRIMARY KEY (itemTypeID)
);
CREATE TABLE fieldsCombined (
    fieldID INT NOT NULL,
    fieldName TEXT NOT NULL,
    label TEXT,
    fieldFormatID INT,
    custom INT NOT NULL,
    PRIMARY KEY (fieldID)
);
CREATE TABLE itemTypeFieldsCombined (
    itemTypeID INT NOT NULL,
    fieldID INT NOT NULL,
    hide INT,
    orderIndex INT NOT NULL,
    PRIMARY KEY (itemTypeID, orderIndex),
    UNIQUE (itemTypeID, fieldID)
);
CREATE INDEX itemTypeFieldsCombined_fieldID ON itemTypeFieldsCombined(fieldID);
CREATE TABLE baseFieldMappingsCombined (
    itemTypeID INT,
    baseFieldID INT,
    fieldID INT,
    PRIMARY KEY (itemTypeID, baseFieldID, fieldID)
);
CREATE INDEX baseFieldMappingsCombined_baseFieldID ON baseFieldMappingsCombined(baseFieldID);
CREATE INDEX baseFieldMappingsCombined_fieldID ON baseFieldMappingsCombined(fieldID);
CREATE TABLE creatorTypes (
    creatorTypeID INTEGER PRIMARY KEY,
    creatorType TEXT
);
CREATE TABLE itemTypeCreatorTypes (
    itemTypeID INT,
    creatorTypeID INT,
    primaryField INT,
    PRIMARY KEY (itemTypeID, creatorTypeID),
    FOREIGN KEY (itemTypeID) REFERENCES itemTypes(itemTypeID),
    FOREIGN KEY (creatorTypeID) REFERENCES creatorTypes(creatorTypeID)
);
CREATE INDEX itemTypeCreatorTypes_creatorTypeID ON itemTypeCreatorTypes(creatorTypeID);
CREATE TABLE version (
    schema TEXT PRIMARY KEY,
    version INT NOT NULL
);
CREATE INDEX schema ON version(schema);
CREATE TABLE items (
    itemID INTEGER PRIMARY KEY,
    itemTypeID INT NOT NULL,
    dateAdded TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    dateModified TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    clientDateModified TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    libraryID INT NOT NULL,
    key TEXT NOT NULL,
    version INT NOT NULL DEFAULT 0,
    clientVersion INT NOT NULL DEFAULT 0,
    synced INT NOT NULL DEFAULT 0,
    UNIQUE (libraryID, key),
    FOREIGN KEY (libraryID) REFERENCES libraries(libraryID) ON DELETE CASCADE
);
CREATE INDEX items_synced ON items(synced);
CREATE TABLE itemDataValues (
    valueID INTEGER PRIMARY KEY,
    value UNIQUE,
    valueNormalized TEXT
);
CREATE TABLE itemData (
    itemID INT,
    fieldID INT,
    valueID,
    PRIMARY KEY (itemID, fieldID),
    FOREIGN KEY (itemID) REFERENCES items(itemID) ON DELETE CASCADE,
    FOREIGN KEY (fieldID) REFERENCES fieldsCombined(fieldID),
    FOREIGN KEY (valueID) REFERENCES itemDataValues(valueID)
);
CREATE INDEX itemData_fieldID ON itemData(fieldID);
CREATE INDEX itemData_valueID ON itemData(valueID);
CREATE TABLE itemNotes (
    itemID INTEGER PRIMARY KEY,
    parentItemID INT,
    note TEXT,
    title TEXT,
    FOREIGN KEY (itemID) REFERENCES items(itemID) ON DELETE CASCADE,
    FOREIGN KEY (parentItemID) REFERENCES items(itemID) ON DELETE CASCADE
);
CREATE INDEX itemNotes_parentItemID ON itemNotes(parentItemID);
CREATE TABLE itemAttachments (
    itemID INTEGER PRIMARY KEY,
    parentItemID INT,
    linkMode INT,
    contentType TEXT,
    charsetID INT,
    path TEXT,
    syncState INT DEFAULT 0,
    storageModTime INT,
    storageHash TEXT,
    lastProcessedModificationTime INT,
    lastRead INT,
    FOREIGN KEY (itemID) REFERENCES items(itemID) ON DELETE CASCADE,
    FOREIGN KEY (parentItemID) REFERENCES items(itemID) ON DELETE CASCADE,
    FOREIGN KEY (charsetID) REFERENCES charsets(charsetID) ON DELETE SET NULL
);
CREATE INDEX itemAttachments_parentItemID ON itemAttachments(parentItemID);
CREATE INDEX itemAttachments_charsetID ON itemAttachments(charsetID);
CREATE INDEX itemAttachments_contentType ON itemAttachments(contentType);
CREATE INDEX itemAttachments_syncState ON itemAttachments(syncState);
CREATE INDEX itemAttachments_lastProcessedModificationTime ON itemAttachments(lastProcessedModificationTime);
CREATE INDEX itemAttachments_lastRead ON itemAttachments(lastRead);
CREATE TABLE itemAnnotations (
    itemID INTEGER PRIMARY KEY,
    parentItemID INT NOT NULL,
    type INTEGER NOT NULL,
    authorName TEXT,
    text TEXT,
    textNormalized TEXT,
    comment TEXT,
    commentNormalized TEXT,
    color TEXT,
    pageLabel TEXT,
    sortIndex TEXT NOT NULL,
    position TEXT NOT NULL,
    isExternal INT NOT NULL,
    FOREIGN KEY (itemID) REFERENCES items(itemID) ON DELETE CASCADE,
    FOREIGN KEY (parentItemID) REFERENCES itemAttachments(itemID)
);
CREATE INDEX itemAnnotations_parentItemID ON itemAnnotations(parentItemID);
CREATE TABLE tags (
    tagID INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    nameNormalized TEXT
);
CREATE TABLE itemRelations (
    itemID INT NOT NULL,
    predicateID INT NOT NULL,
    object TEXT NOT NULL,
    PRIMARY KEY (itemID, predicateID, object),
    FOREIGN KEY (itemID) REFERENCES items(itemID) ON DELETE CASCADE,
    FOREIGN KEY (predicateID) REFERENCES relationPredicates(predicateID) ON DELETE CASCADE
);
CREATE INDEX itemRelations_predicateID ON itemRelations(predicateID);
CREATE INDEX itemRelations_object ON itemRelations(object);
CREATE TABLE itemTags (
    itemID INT NOT NULL,
    tagID INT NOT NULL,
    type INT NOT NULL,
    PRIMARY KEY (itemID, tagID),
    FOREIGN KEY (itemID) REFERENCES items(itemID) ON DELETE CASCADE,
    FOREIGN KEY (tagID) REFERENCES tags(tagID) ON DELETE CASCADE
);
CREATE INDEX itemTags_tagID ON itemTags(tagID);
CREATE TABLE creators (
    creatorID INTEGER PRIMARY KEY,
    firstName TEXT,
    lastName TEXT,
    fieldMode INT,
    firstNameNormalized TEXT,
    lastNameNormalized TEXT,
    UNIQUE (lastName, firstName, fieldMode)
);
CREATE TABLE itemCreators (
    itemID INT NOT NULL,
    creatorID INT NOT NULL,
    creatorTypeID INT NOT NULL DEFAULT 1,
    orderIndex INT NOT NULL DEFAULT 0,
    PRIMARY KEY (itemID, creatorID, creatorTypeID, orderIndex),
    UNIQUE (itemID, orderIndex),
    FOREIGN KEY (itemID) REFERENCES items(itemID) ON DELETE CASCADE,
    FOREIGN KEY (creatorID) REFERENCES creators(creatorID) ON DELETE CASCADE,
    FOREIGN KEY (creatorTypeID) REFERENCES creatorTypes(creatorTypeID)
);
CREATE INDEX itemCreators_creatorTypeID ON itemCreators(creatorTypeID);
CREATE TABLE collections (
    collectionID INTEGER PRIMARY KEY,
    collectionName TEXT NOT NULL,
    parentCollectionID INT DEFAULT NULL,
    clientDateModified TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    libraryID INT NOT NULL,
    key TEXT NOT NULL,
    version INT NOT NULL DEFAULT 0,
    clientVersion INT NOT NULL DEFAULT 0,
    synced INT NOT NULL DEFAULT 0,
    UNIQUE (libraryID, key),
    FOREIGN KEY (libraryID) REFERENCES libraries(libraryID) ON DELETE CASCADE,
    FOREIGN KEY (parentCollectionID) REFERENCES collections(collectionID) ON DELETE CASCADE
);
CREATE INDEX collections_synced ON collections(synced);
CREATE TABLE collectionItems (
    collectionID INT NOT NULL,
    itemID INT NOT NULL,
    orderIndex INT NOT NULL DEFAULT 0,
    PRIMARY KEY (collectionID, itemID),
    FOREIGN KEY (collectionID) REFERENCES collections(collectionID) ON DELETE CASCADE,
    FOREIGN KEY (itemID) REFERENCES items(itemID) ON DELETE CASCADE
);
CREATE INDEX collectionItems_itemID ON collectionItems(itemID);
CREATE TABLE deletedCollections (
    collectionID INTEGER PRIMARY KEY,
    dateDeleted DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (collectionID) REFERENCES collections(collectionID) ON DELETE CASCADE
);
CREATE INDEX deletedCollections_dateDeleted ON deletedCollections(dateDeleted);
CREATE TABLE deletedItems (
    itemID INTEGER PRIMARY KEY,
    dateDeleted DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (itemID) REFERENCES items(itemID) ON DELETE CASCADE
);
CREATE INDEX deletedItems_dateDeleted ON deletedItems(dateDeleted);
CREATE INDEX deletedSearches_dateDeleted ON deletedItems(dateDeleted);
CREATE TABLE libraries (
    libraryID INTEGER PRIMARY KEY,
    type TEXT NOT NULL,
    editable INT NOT NULL,
    filesEditable INT NOT NULL,
    version INT NOT NULL DEFAULT 0,
    clientVersion INT NOT NULL DEFAULT 0,
    storageVersion INT NOT NULL DEFAULT 0,
    lastSync INT NOT NULL DEFAULT 0,
    archived INT NOT NULL DEFAULT 0,
    isAdmin INT NOT NULL DEFAULT 0
);
CREATE TABLE users (
    userID INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);
CREATE TABLE groups (
    groupID INTEGER PRIMARY KEY,
    libraryID INT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    version INT NOT NULL,
    FOREIGN KEY (libraryID) REFERENCES libraries(libraryID) ON DELETE CASCADE
);
CREATE TABLE groupItems (
    itemID INTEGER PRIMARY KEY,
    createdByUserID INT,
    lastModifiedByUserID INT,
    FOREIGN KEY (itemID) REFERENCES items(itemID) ON DELETE CASCADE,
    FOREIGN KEY (createdByUserID) REFERENCES users(userID) ON DELETE SET NULL,
    FOREIGN KEY (lastModifiedByUserID) REFERENCES users(userID) ON DELETE SET NULL
);
CREATE TABLE publicationsItems (
    itemID INTEGER PRIMARY KEY
);
CREATE TABLE syncCache (
    libraryID INT NOT NULL,
    key TEXT NOT NULL,
    syncObjectTypeID INT NOT NULL,
    version INT NOT NULL,
    data TEXT,
    PRIMARY KEY (libraryID, key, syncObjectTypeID, version),
    FOREIGN KEY (libraryID) REFERENCES libraries(libraryID) ON DELETE CASCADE,
    FOREIGN KEY (syncObjectTypeID) REFERENCES syncObjectTypes(syncObjectTypeID)
);
CREATE TABLE relationPredicates (
    predicateID INTEGER PRIMARY KEY,
    predicate TEXT UNIQUE
);

-- resource/schema/system.sql
CREATE TABLE charsets (
    charsetID INTEGER PRIMARY KEY,
    charset TEXT UNIQUE
);
CREATE INDEX charsets_charset ON charsets(charset);
CREATE TABLE syncObjectTypes (
    syncObjectTypeID INTEGER PRIMARY KEY,
    name TEXT
);
CREATE INDEX syncObjectTypes_name ON syncObjectTypes(name);

-- resource/schema/triggers.sql
CREATE TRIGGER fki_collectionItems_libraryID
  BEFORE INSERT ON collectionItems
  FOR EACH ROW BEGIN
    SELECT RAISE(ABORT, 'insert on table "collectionItems" violates foreign key constraint "fki_collectionItems_libraryID"')
    WHERE (SELECT libraryID FROM collections WHERE collectionID = NEW.collectionID) != (SELECT libraryID FROM items WHERE itemID = NEW.itemID);
  END;
CREATE TRIGGER fki_collectionItems_itemID_parentItemID
  BEFORE INSERT ON collectionItems
  FOR EACH ROW BEGIN
    SELECT RAISE(ABORT, 'insert on table "collectionItems" violates foreign key constraint "fki_collectionItems_itemID_parentItemID"')
    WHERE NEW.itemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID IS NOT NULL UNION SELECT itemID FROM itemNotes WHERE parentItemID IS NOT NULL);
  END;

-- chrome/content/zotero/xpcom/fulltext.js:158-213 (ftindex database)
CREATE VIRTUAL TABLE fulltextContent USING fts5(text, tokenize='unicode61', content='', contentless_delete=1);
CREATE VIRTUAL TABLE fulltextNotes USING fts5(text, tokenize='trigram', content='', contentless_delete=1);
CREATE TABLE fulltextIndexState (
    itemID INTEGER PRIMARY KEY,
    version INT NOT NULL
);
CREATE TABLE fulltextNoteIndexState (
    itemID INTEGER PRIMARY KEY,
    version INT NOT NULL
);
CREATE INDEX fulltextNoteIndexState_stale ON fulltextNoteIndexState(itemID) WHERE version=0;
CREATE TABLE noteText (
    itemID INTEGER PRIMARY KEY,
    text TEXT
);

-- search.js temp table stand-in
CREATE TABLE tmpSearchResults_scope (itemID INT);
CREATE INDEX tmpSearchResults_scope_itemID ON tmpSearchResults_scope(itemID);
