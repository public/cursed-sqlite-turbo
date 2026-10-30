-- Synthetic data for zotero. Deterministic (no random()): values come from multiplicative hashes of the row number.
-- Lookup ids (normally from the global schema JSON): itemTypes annotation=1, attachment=3, book=7, bookSection=8,
-- case=9, conferencePaper=11, journalArticle=21, note=27, thesis=33, webpage=34; fields title=1, abstractNote=2,
-- date=6, publicationTitle=8, shortTitle=10, url=11, DOI=13, ISBN=14, court=20, caseName=25, nameOfAct=26,
-- subject=27, dateDecided=30, dateEnacted=31, issueDate=32, citationKey=40, accessDate=41, websiteTitle=50,
-- blogTitle=51, proceedingsTitle=52; creatorTypes author=1, contributor=2, editor=3, translator=4, bookAuthor=8,
-- director=10.
-- Scale 1: 12k regular items (90% in the user library, 10% in a group), 6k attachments, 3k notes, 6k annotations,
-- 3k creators, 150 collections, 400 tags, ~25k sync-cache rows.
BEGIN;

INSERT INTO libraries(libraryID, type, editable, filesEditable, version, storageVersion, lastSync)
VALUES (1, 'user', 1, 1, 4210, 4100, 1767200000), (2, 'group', 1, 1, 1880, 1800, 1767100000);
INSERT INTO users VALUES (1001, 'alice'), (1002, 'bob'), (1003, 'carol');
INSERT INTO groups VALUES (55501, 2, 'Lab Group', 'Shared references', 1880);
INSERT INTO version VALUES ('lastsync', 1767200000), ('userdata', 130), ('triggers', 30);
INSERT INTO charsets VALUES (1, 'utf-8'), (2, 'big5'), (3, 'windows-1252');
INSERT INTO syncObjectTypes VALUES (1, 'collection'), (2, 'creator'), (3, 'item'), (4, 'search'), (5, 'tag'), (6, 'relation'), (7, 'setting');
INSERT INTO relationPredicates VALUES (1, 'dc:relation'), (2, 'owl:sameAs'), (3, 'dc:replaces');

INSERT INTO itemTypesCombined(itemTypeID, typeName, display, custom) VALUES
 (1,'annotation',0,0),(3,'attachment',0,0),(7,'book',2,0),(8,'bookSection',2,0),(9,'case',1,0),(11,'conferencePaper',1,0),
 (21,'journalArticle',2,0),(27,'note',0,0),(33,'thesis',1,0),(34,'webpage',1,0);
INSERT INTO fieldsCombined(fieldID, fieldName, label, fieldFormatID, custom) VALUES
 (1,'title',NULL,NULL,0),(2,'abstractNote',NULL,NULL,0),(6,'date',NULL,NULL,0),(8,'publicationTitle',NULL,NULL,0),
 (10,'shortTitle',NULL,NULL,0),(11,'url',NULL,NULL,0),(13,'DOI',NULL,NULL,0),(14,'ISBN',NULL,NULL,0),(20,'court',NULL,NULL,0),
 (25,'caseName',NULL,NULL,0),(26,'nameOfAct',NULL,NULL,0),(27,'subject',NULL,NULL,0),(30,'dateDecided',NULL,NULL,0),
 (31,'dateEnacted',NULL,NULL,0),(32,'issueDate',NULL,NULL,0),(40,'citationKey',NULL,NULL,0),(41,'accessDate',NULL,NULL,0),
 (50,'websiteTitle',NULL,NULL,0),(51,'blogTitle',NULL,NULL,0),(52,'proceedingsTitle',NULL,NULL,0);
INSERT INTO baseFieldMappingsCombined(itemTypeID, baseFieldID, fieldID) VALUES
 (9,1,25),(9,6,30),(34,8,50),(11,8,52);
INSERT INTO creatorTypes VALUES (1,'author'),(2,'contributor'),(3,'editor'),(4,'translator'),(8,'bookAuthor'),(10,'director');
INSERT INTO itemTypeCreatorTypes(itemTypeID, creatorTypeID, primaryField)
SELECT t.itemTypeID, c.creatorTypeID, CASE WHEN c.creatorTypeID = 1 THEN 1 ELSE 0 END
FROM itemTypesCombined t, creatorTypes c
WHERE t.itemTypeID NOT IN (1, 3, 27) AND c.creatorTypeID IN (1, 2, 3, 4) OR (t.itemTypeID = 8 AND c.creatorTypeID = 8);

-- regular items 1..12000
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 12000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO items(itemID, itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key, version, clientVersion, synced)
SELECT i,
       CASE (h / 16) % 20 WHEN 0 THEN 7 WHEN 1 THEN 7 WHEN 2 THEN 8 WHEN 3 THEN 9 WHEN 4 THEN 11 WHEN 5 THEN 11 WHEN 6 THEN 33
                           WHEN 7 THEN 34 WHEN 8 THEN 34 ELSE 21 END,
       datetime(1600000000 + i * 13000, 'unixepoch'),
       datetime(1600000000 + i * 13000 + (h / 64) % 9000000, 'unixepoch'),
       datetime(1600000000 + i * 13000 + (h / 64) % 9000000, 'unixepoch'),
       CASE WHEN (h / 1024) % 10 = 0 THEN 2 ELSE 1 END,
       printf('%08X', (h * 40503 + i) % 4294967296),
       1 + (h / 4096) % 4000, 0,
       CASE WHEN (h / 8192) % 25 = 0 THEN 0 ELSE 1 END
FROM m;

-- attachments: 90% children of a regular item, PDFs mostly
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 6000*(SELECT scale FROM _cfg)),
m AS (SELECT k, (k * 2246822519) % 4294967296 AS h, (SELECT count(*) FROM items) AS nreg FROM n)
INSERT INTO items(itemID, itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key, version, clientVersion, synced)
SELECT nreg + k, 3,
       datetime(1600000000 + ((k * 7919) % nreg + 1) * 13000 + 600, 'unixepoch'),
       datetime(1600000000 + ((k * 7919) % nreg + 1) * 13000 + 600, 'unixepoch'),
       datetime(1600000000 + ((k * 7919) % nreg + 1) * 13000 + 600, 'unixepoch'),
       (SELECT libraryID FROM items WHERE itemID = (k * 7919) % nreg + 1),
       printf('A%07X', (h * 3 + k) % 268435456), 1 + (h / 4096) % 4000, 0, CASE WHEN (h / 8192) % 25 = 0 THEN 0 ELSE 1 END
FROM m;
INSERT INTO itemAttachments(itemID, parentItemID, linkMode, contentType, charsetID, path, syncState, storageModTime, storageHash, lastProcessedModificationTime, lastRead)
SELECT itemID,
       CASE WHEN itemID % 10 = 0 THEN NULL ELSE ((itemID - 12000*(SELECT scale FROM _cfg)) * 7919) % (12000*(SELECT scale FROM _cfg)) + 1 END,
       CASE WHEN itemID % 7 = 0 THEN 3 WHEN itemID % 11 = 0 THEN 2 ELSE 1 END,
       CASE WHEN itemID % 4 = 0 THEN 'text/html' WHEN itemID % 7 = 0 THEN NULL ELSE 'application/pdf' END,
       CASE WHEN itemID % 4 = 0 THEN 1 END,
       CASE WHEN itemID % 7 = 0 THEN NULL WHEN itemID % 11 = 0 THEN '/home/alice/papers/p' || itemID || '.pdf' ELSE 'storage:paper' || itemID || '.pdf' END,
       itemID % 3, 1700000000000 + itemID * 1000, printf('%032x', itemID * 2654435761), 1700000000 + itemID,
       CASE WHEN itemID % 5 = 0 THEN 1767000000 + itemID * 7 END
FROM items WHERE itemTypeID = 3;

-- notes: 80% child notes
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 3000*(SELECT scale FROM _cfg)),
w(j, w) AS (VALUES (0,'neural'),(1,'climate'),(2,'protein'),(3,'theorem'),(4,'archive'),(5,'syntax'),(6,'market'),(7,'galaxy')),
m AS (SELECT k, (k * 3266489917) % 4294967296 AS h, (SELECT max(itemID) FROM items) AS base, 12000*(SELECT scale FROM _cfg) AS nreg FROM n)
INSERT INTO items(itemID, itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key, version, clientVersion, synced)
SELECT base + k, 27, datetime(1700000000 + k * 9000, 'unixepoch'), datetime(1700000000 + k * 9000 + 50, 'unixepoch'),
       datetime(1700000000 + k * 9000 + 50, 'unixepoch'),
       CASE WHEN k % 5 = 0 THEN 1 ELSE (SELECT libraryID FROM items WHERE itemID = (k * 104729) % nreg + 1) END,
       printf('N%07X', (h * 5 + k) % 268435456), 1 + (h / 4096) % 4000, 0, 1
FROM m;
WITH w(j, w) AS (VALUES (0,'neural'),(1,'climate'),(2,'protein'),(3,'theorem'),(4,'archive'),(5,'syntax'),(6,'market'),(7,'galaxy'))
INSERT INTO itemNotes(itemID, parentItemID, note, title)
SELECT itemID,
       CASE WHEN o.itemID % 5 = 0 THEN NULL ELSE ((o.itemID * 104729) % (12000*(SELECT scale FROM _cfg))) + 1 END,
       '<div data-schema-version="9"><h1>Notes on ' || (SELECT w FROM w WHERE j = o.itemID % 8) || '</h1><p>Key finding about ' ||
         (SELECT w FROM w WHERE j = (o.itemID / 8) % 8) || ' and ' || (SELECT w FROM w WHERE j = (o.itemID / 64) % 8) || ' in item ' || o.itemID || '.</p></div>',
       'Notes on ' || (SELECT w FROM w WHERE j = o.itemID % 8)
FROM items o WHERE o.itemTypeID = 27;
-- standalone notes are in library 1; fix child notes to their parent's library
UPDATE items SET libraryID = (SELECT p.libraryID FROM itemNotes n JOIN items p ON p.itemID = n.parentItemID WHERE n.itemID = items.itemID)
WHERE itemTypeID = 27 AND itemID IN (SELECT itemID FROM itemNotes WHERE parentItemID IS NOT NULL);
UPDATE items SET libraryID = 1 WHERE itemTypeID = 27 AND itemID IN (SELECT itemID FROM itemNotes WHERE parentItemID IS NULL);
-- attachments' libraries follow their parents (standalone ones stay as generated)
UPDATE items SET libraryID = (SELECT p.libraryID FROM itemAttachments a JOIN items p ON p.itemID = a.parentItemID WHERE a.itemID = items.itemID)
WHERE itemTypeID = 3 AND itemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID IS NOT NULL);

-- annotations on PDF attachments
CREATE TEMP TABLE _pdf(r INTEGER PRIMARY KEY, itemID INT);
INSERT INTO _pdf(r, itemID) SELECT row_number() OVER (ORDER BY itemID) - 1, itemID FROM itemAttachments WHERE contentType = 'application/pdf';
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 6000*(SELECT scale FROM _cfg)),
m AS (SELECT k, (k * 2654435761) % 4294967296 AS h, (SELECT max(itemID) FROM items) AS base FROM n)
INSERT INTO items(itemID, itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key, version, clientVersion, synced)
SELECT base + k, 1, datetime(1720000000 + k * 3000, 'unixepoch'), datetime(1720000000 + k * 3000, 'unixepoch'),
       datetime(1720000000 + k * 3000, 'unixepoch'), p.libraryID,
       printf('X%07X', (h * 7 + k) % 268435456), 1 + (h / 4096) % 4000, 0, CASE WHEN (h / 8192) % 25 = 0 THEN 0 ELSE 1 END
FROM m JOIN _pdf pdf ON pdf.r = (m.h / 16) % (SELECT count(*) FROM _pdf) JOIN items p ON p.itemID = pdf.itemID;
WITH w(j, w) AS (VALUES (0,'neural'),(1,'climate'),(2,'protein'),(3,'theorem'),(4,'archive'),(5,'syntax'),(6,'market'),(7,'galaxy'))
INSERT INTO itemAnnotations(itemID, parentItemID, type, authorName, text, textNormalized, comment, commentNormalized, color, pageLabel, sortIndex, position, isExternal)
SELECT a.itemID,
       (SELECT pdf.itemID FROM _pdf pdf WHERE pdf.r = (((a.itemID - b.base) * 2654435761) % 4294967296 / 16) % (SELECT count(*) FROM _pdf)),
       1 + a.itemID % 4, CASE WHEN a.libraryID = 2 THEN 'bob' END,
       CASE WHEN a.itemID % 4 = 2 THEN NULL ELSE 'The ' || (SELECT w FROM w WHERE j = a.itemID % 8) || ' result holds for ' || (SELECT w FROM w WHERE j = (a.itemID / 8) % 8) END,
       NULL,
       CASE WHEN a.itemID % 3 = 0 THEN 'Compare with ' || (SELECT w FROM w WHERE j = (a.itemID / 3) % 8) ELSE '' END, NULL,
       CASE a.itemID % 4 WHEN 0 THEN '#ffd400' WHEN 1 THEN '#ff6666' WHEN 2 THEN '#5fb236' ELSE '#2ea8e5' END,
       CAST(1 + a.itemID % 30 AS TEXT),
       printf('%05d|%06d|%05d', a.itemID % 30, (a.itemID * 37) % 100000, (a.itemID * 11) % 800),
       json_object('pageIndex', a.itemID % 30, 'rects', json_array(json_array(100, 200 + a.itemID % 400, 300, 212 + a.itemID % 400))),
       CASE WHEN a.itemID % 50 = 0 THEN 1 ELSE 0 END
FROM items a, (SELECT min(itemID) - 1 AS base FROM items WHERE itemTypeID = 1) b
WHERE a.itemTypeID = 1;

-- item fields, staged then deduplicated into itemDataValues
CREATE TEMP TABLE _vals(itemID INT, fieldID INT, value);
WITH w(j, w) AS (VALUES (0,'Neural'),(1,'Climate'),(2,'Protein'),(3,'Theorem'),(4,'Archive'),(5,'Syntax'),(6,'Market'),(7,'Galaxy'),(8,'Smith'),(9,'Learning'),(10,'Dynamics'),(11,'Networks')),
j(j, jn) AS (VALUES (0,'Nature'),(1,'Science'),(2,'Journal of Applied Things'),(3,'PLOS ONE'),(4,'Annual Review of Stuff')),
r AS (SELECT itemID, itemTypeID, (itemID * 2654435761) % 4294967296 AS h,
             CASE WHEN itemID % 33 = 0 THEN itemID - 1 ELSE itemID END AS t FROM items WHERE itemTypeID NOT IN (1, 3, 27))
INSERT INTO _vals
SELECT itemID, CASE WHEN itemTypeID = 9 THEN 25 ELSE 1 END,
       (SELECT w FROM w WHERE j = (t * 7) % 12) || ' ' || (SELECT lower(w) FROM w WHERE j = (t * 13 / 3) % 12) || ' and the ' ||
       (SELECT lower(w) FROM w WHERE j = (t / 5) % 12) || ' of ' || (SELECT w FROM w WHERE j = (t / 61) % 12) || ' ' || (t % 997)
FROM r
UNION ALL
SELECT itemID, CASE WHEN itemTypeID = 9 THEN 30 ELSE 6 END,
       printf('%04d-%02d-00 %s %d', 1990 + (h / 16) % 36, 1 + (h / 1024) % 12, 'month', 1990 + (h / 16) % 36) FROM r WHERE (h / 32768) % 15 != 0
UNION ALL
SELECT itemID, CASE itemTypeID WHEN 34 THEN 50 WHEN 11 THEN 52 ELSE 8 END, (SELECT jn FROM j WHERE j = (h / 64) % 5) FROM r WHERE itemTypeID IN (21, 11, 34, 8)
UNION ALL
SELECT itemID, 13, '10.' || (1000 + (h / 128) % 9000) || '/' || lower(printf('%x', h % 1048576)) FROM r WHERE itemTypeID = 21 AND (h / 4) % 5 < 3
UNION ALL
SELECT itemID, 14, '978' || printf('%010d', (h * 7) % 10000000000) FROM r WHERE itemTypeID = 7
UNION ALL
SELECT itemID, 11, 'https://example.org/papers/' || itemID FROM r WHERE (h / 256) % 3 = 0
UNION ALL
SELECT itemID, 2, 'We study ' || (SELECT lower(w) FROM w WHERE j = (h / 512) % 12) || ' and show improved results on ' || (SELECT lower(w) FROM w WHERE j = (h / 4096) % 12) || ' benchmarks.' FROM r WHERE (h / 2) % 2 = 0
UNION ALL
SELECT itemID, 10, (SELECT w FROM w WHERE j = (t * 7) % 12) || ' ' || (SELECT lower(w) FROM w WHERE j = (t * 13 / 3) % 12) FROM r WHERE (h / 8) % 4 = 0
UNION ALL
SELECT itemID, 20, 'Supreme Court' FROM r WHERE itemTypeID = 9
UNION ALL
SELECT itemID, 40, 'key' || itemID FROM r WHERE (h / 65536) % 20 = 0
UNION ALL
SELECT a.itemID, 1, CASE WHEN a.contentType = 'application/pdf' THEN 'Full Text PDF' WHEN a.contentType = 'text/html' THEN 'Snapshot' ELSE 'Link ' || a.itemID END FROM itemAttachments a
UNION ALL
SELECT a.itemID, 41, datetime(1700000000 + a.itemID * 100, 'unixepoch') FROM itemAttachments a WHERE a.contentType = 'text/html';
INSERT OR IGNORE INTO itemDataValues(value, valueNormalized) SELECT DISTINCT value, lower(value) FROM _vals;
INSERT INTO itemData(itemID, fieldID, valueID) SELECT v.itemID, v.fieldID, d.valueID FROM _vals v JOIN itemDataValues d ON d.value = v.value;
DROP TABLE _vals;

-- creators: 3000 people, 0-5 per regular item
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 3000*(SELECT scale FROM _cfg)),
f(j, f) AS (VALUES (0,'Anna'),(1,'Ben'),(2,'Chen'),(3,'Dana'),(4,'Emil'),(5,'Fatima'),(6,'Goran'),(7,'Hiro'),(8,'Ines'),(9,'José')),
l(j, l) AS (VALUES (0,'Smith'),(1,'Müller'),(2,'Wang'),(3,'García'),(4,'Okafor'),(5,'Kowalski'),(6,'Tanaka'),(7,'Rossi'),(8,'Novak'),(9,'Silva'),(10,'Smithson'),(11,'Ivanova'))
INSERT INTO creators(creatorID, firstName, lastName, fieldMode, firstNameNormalized, lastNameNormalized)
SELECT i, CASE WHEN i % 40 = 0 THEN '' ELSE (SELECT f FROM f WHERE j = i % 10) END,
       CASE WHEN i % 40 = 0 THEN 'Institute ' || i ELSE (SELECT l FROM l WHERE j = (i / 10) % 12) || CASE WHEN i >= 120 THEN '-' || (i / 120) ELSE '' END END,
       CASE WHEN i % 40 = 0 THEN 1 ELSE 0 END, NULL, NULL
FROM n;
WITH k(k) AS (VALUES (0),(1),(2),(3),(4)),
r AS (SELECT itemID, itemTypeID, (itemID * 2246822519) % 4294967296 AS h FROM items WHERE itemTypeID NOT IN (1, 3, 27))
INSERT INTO itemCreators(itemID, creatorID, creatorTypeID, orderIndex)
SELECT itemID, ((h / 8 + k * 7919) % (3000*(SELECT scale FROM _cfg))) + 1,
       CASE WHEN itemTypeID = 8 AND k = 0 AND (h / 2) % 3 = 0 THEN 3 WHEN (h / 4) % 17 = 0 THEN 3 WHEN itemTypeID = 34 THEN 2 WHEN k = 3 AND (h / 16) % 2 = 0 THEN 4 ELSE 1 END,
       k
FROM r, k WHERE k < (h / 65536) % 6;

-- collections: 140 in the user library (two levels), 10 in the group
WITH RECURSIVE n(c) AS (SELECT 1 UNION ALL SELECT c+1 FROM n WHERE c < 150)
INSERT INTO collections(collectionID, collectionName, parentCollectionID, clientDateModified, libraryID, key, version, synced)
SELECT c, 'Collection ' || c, CASE WHEN c > 30 AND c <= 140 THEN ((c * 7) % 30) + 1 END, datetime(1700000000 + c * 86400, 'unixepoch'),
       CASE WHEN c > 140 THEN 2 ELSE 1 END, printf('C%07X', c * 2654435761 % 268435456), c * 3, CASE WHEN c % 23 = 0 THEN 0 ELSE 1 END
FROM n;
INSERT INTO deletedCollections(collectionID, dateDeleted) VALUES (77, '2026-09-01 10:00:00');
-- the child-item trigger rebuilds a UNION per inserted row; suspend it for the bulk load (recreated below)
DROP TRIGGER fki_collectionItems_itemID_parentItemID;
WITH k(k) AS (VALUES (0),(1),(2))
INSERT OR IGNORE INTO collectionItems(collectionID, itemID, orderIndex)
SELECT CASE WHEN i.libraryID = 2 THEN 141 + (i.itemID * 7 + k) % 10 ELSE 1 + ((i.itemID * 2654435761 / 64 + k * 31) % 140) END, i.itemID, k
FROM items i, k
WHERE i.itemTypeID NOT IN (1, 3, 27) AND k <= (i.itemID * 40503 / 16) % 3
UNION ALL
SELECT 5, i.itemID, 9 FROM items i JOIN itemNotes n USING (itemID) WHERE n.parentItemID IS NULL AND i.libraryID = 1 AND i.itemID % 3 = 0;
CREATE TRIGGER fki_collectionItems_itemID_parentItemID
  BEFORE INSERT ON collectionItems
  FOR EACH ROW BEGIN
    SELECT RAISE(ABORT, 'insert on table "collectionItems" violates foreign key constraint "fki_collectionItems_itemID_parentItemID"')
    WHERE NEW.itemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID IS NOT NULL UNION SELECT itemID FROM itemNotes WHERE parentItemID IS NOT NULL);
  END;

-- tags: 400 names, 0-4 per regular item, some on annotations
WITH RECURSIVE n(t) AS (SELECT 1 UNION ALL SELECT t+1 FROM n WHERE t < 400),
w(j, w) AS (VALUES (0,'machine learning'),(1,'climate'),(2,'to-read'),(3,'methods'),(4,'review'),(5,'ML'),(6,'genomics'),(7,'Important'))
INSERT INTO tags(tagID, name, nameNormalized)
SELECT t, CASE WHEN t <= 8 THEN (SELECT w FROM w WHERE j = t - 1) ELSE 'topic/' || (SELECT w FROM w WHERE j = t % 8) || '-' || t END, NULL FROM n;
WITH k(k) AS (VALUES (0),(1),(2),(3))
INSERT OR IGNORE INTO itemTags(itemID, tagID, type)
SELECT itemID, CASE WHEN k = 0 THEN 1 + (itemID * 7) % 8 WHEN k = 1 AND itemID % 2 = 0 THEN 1 + (itemID / 3) % 8 ELSE 9 + (itemID * 13 + k * 101) % 392 END, CASE WHEN k = 3 THEN 1 ELSE 0 END
FROM items, k
WHERE (itemTypeID NOT IN (1, 3, 27) AND k < (itemID * 2654435761 / 32) % 5) OR (itemTypeID = 1 AND k = 0 AND itemID % 4 = 0);

INSERT INTO itemRelations(itemID, predicateID, object)
SELECT itemID, CASE WHEN itemID % 3 = 0 THEN 2 ELSE 1 END, 'http://zotero.org/users/1001/items/' || printf('%08X', itemID * 7) FROM items WHERE itemID % 37 = 0 AND itemTypeID NOT IN (1, 3, 27);

INSERT INTO deletedItems(itemID, dateDeleted) SELECT itemID, datetime(1765000000 + itemID, 'unixepoch') FROM items WHERE itemID % 53 = 0;
INSERT INTO publicationsItems(itemID) SELECT itemID FROM items WHERE libraryID = 1 AND itemTypeID = 21 AND itemID % 97 = 0;
INSERT INTO groupItems(itemID, createdByUserID, lastModifiedByUserID) SELECT itemID, 1001 + itemID % 3, 1001 + (itemID / 3) % 3 FROM items WHERE libraryID = 2;

-- sync cache: 1-3 versions of every synced item, collection and tag-less settings
INSERT INTO syncCache(libraryID, key, syncObjectTypeID, version, data)
SELECT libraryID, key, 3, version - v.v, json_object('key', key, 'version', version - v.v, 'itemType', itemTypeID, 'dateAdded', dateAdded, 'tags', json_array(), 'relations', json_object())
FROM items, (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2) v
WHERE synced = 1 AND v.v <= itemID % 3 AND version - v.v > 0
UNION ALL
SELECT libraryID, key, 1, version, json_object('key', key, 'version', version, 'name', collectionName) FROM collections WHERE synced = 1;

-- full-text index: attachment content (word index) and note text (trigram index)
WITH w(j, w) AS (VALUES (0,'neural'),(1,'climate'),(2,'protein'),(3,'theorem'),(4,'archive'),(5,'syntax'),(6,'market'),(7,'galaxy'),(8,'network'),(9,'archives'))
INSERT INTO fulltextContent(rowid, text)
SELECT itemID, 'abstract introduction ' || (SELECT w FROM w WHERE j = itemID % 10) || ' methods ' || (SELECT w FROM w WHERE j = (itemID / 10) % 10) ||
       ' results discussion ' || (SELECT w FROM w WHERE j = (itemID / 100) % 10) || ' references page ' || itemID
FROM itemAttachments WHERE contentType IN ('application/pdf', 'text/html');
INSERT INTO fulltextIndexState(itemID, version) SELECT itemID, 3 FROM itemAttachments WHERE contentType IN ('application/pdf', 'text/html');
INSERT INTO noteText(itemID, text) SELECT itemID, lower(replace(replace(replace(replace(note, '<div data-schema-version="9"><h1>', ''), '</h1><p>', ' '), '</p></div>', ''), '.', '')) FROM itemNotes;
INSERT INTO fulltextNotes(rowid, text) SELECT itemID, text FROM noteText;
INSERT INTO fulltextNoteIndexState(itemID, version) SELECT itemID, CASE WHEN itemID % 101 = 0 THEN 0 ELSE 3 END FROM itemNotes;

-- scope of the item-tree search for collection 5 and its subcollections (recursiveCollections on)
INSERT INTO tmpSearchResults_scope(itemID)
SELECT itemID FROM items WHERE (itemID NOT IN (SELECT itemID FROM deletedItems))
  AND (itemID NOT IN (SELECT itemID FROM itemNotes WHERE parentItemID IS NOT NULL) AND itemID NOT IN (SELECT itemID FROM itemAttachments WHERE parentItemID IS NOT NULL))
  AND libraryID = 1
  AND itemID IN (SELECT itemID FROM collectionItems WHERE collectionID IN (SELECT 5 UNION ALL SELECT collectionID FROM collections WHERE parentCollectionID = 5));

COMMIT;
