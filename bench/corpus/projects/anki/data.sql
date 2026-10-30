-- Synthetic data for anki. Deterministic (no random()): values come from multiplicative hashes of the row number.
-- Clock used by the queries: collection day 1500 (days_elapsed), now = 1767200000, next_day_at = 1767240000.
-- Scale 1: 41 decks + 1 filtered deck, 4 notetypes, 20k notes, ~29k cards, 120k revlog rows, 600 graves.
BEGIN;

INSERT INTO col VALUES (1, 1767240000 - 1500*86400, 1767200000000, 1767000000000, 18, 0, 0, 0, '{}', '{}', '{}', '{}', '{}');

-- decks: Default, 5 top-level decks, 15 children, 20 grandchildren, plus one filtered deck
WITH RECURSIVE k(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM k WHERE k < 39),
g(g, gname) AS (VALUES (0,'Spanish'),(1,'Japanese'),(2,'Medicine'),(3,'Geography'),(4,'History'))
INSERT INTO decks(id, name, mtime_secs, usn, common, kind)
SELECT 1, 'Default', 1700000000, 0, x'0801', x'0a00'
UNION ALL
SELECT 1600000000001 + k, CASE WHEN k < 5 THEN gname
                              WHEN k < 20 THEN gname || char(31) || 'Unit ' || k
                              ELSE gname || char(31) || 'Unit ' || (k - 20 + CASE WHEN k - 20 < 5 THEN 5 ELSE 0 END) || char(31) || 'Part ' || k END,
       1700000000 + k*1000, CASE WHEN k % 7 = 0 THEN -1 ELSE k END, x'0801', x'0a020801'
FROM k JOIN g ON g.g = k.k % 5
UNION ALL
SELECT 1600000000100, 'Filtered Deck 1', 1767000000, -1, x'0801', x'12080a0464756520';

INSERT INTO deck_config VALUES (1, 'Default', 1700000000, 0, x'0a00'), (2, 'Intensive', 1700000000, 0, x'0a01');
INSERT INTO config VALUES ('curDeck', 0, 1700000000, '1600000000001'), ('sortType', 0, 1700000000, '"noteFld"');

INSERT INTO notetypes(id, name, mtime_secs, usn, config) VALUES
 (1500000000001, 'Basic', 1700000000, 0, x'1a00'),
 (1500000000002, 'Basic (and reversed card)', 1700000000, 0, x'1a00'),
 (1500000000003, 'Cloze', 1700000000, 0, x'0801'),
 (1500000000004, 'Vocab', 1700000000, 0, x'1a00');
INSERT INTO fields(ntid, ord, name, config) VALUES
 (1500000000001, 0, 'Front', x''), (1500000000001, 1, 'Back', x''),
 (1500000000002, 0, 'Front', x''), (1500000000002, 1, 'Back', x''),
 (1500000000003, 0, 'Text', x''), (1500000000003, 1, 'Back Extra', x''),
 (1500000000004, 0, 'Word', x''), (1500000000004, 1, 'Meaning', x''), (1500000000004, 2, 'Reading', x''), (1500000000004, 3, 'Example', x'');
INSERT INTO templates(ntid, ord, name, mtime_secs, usn, config) VALUES
 (1500000000001, 0, 'Card 1', 1700000000, 0, x''),
 (1500000000002, 0, 'Card 1', 1700000000, 0, x''), (1500000000002, 1, 'Card 2', 1700000000, 0, x''),
 (1500000000003, 0, 'Cloze', 1700000000, 0, x''),
 (1500000000004, 0, 'Recognition', 1700000000, 0, x''), (1500000000004, 1, 'Recall', 1700000000, 0, x'');

-- notes: newest id is ~1 day before now, 40 minutes apart
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20000*(SELECT scale FROM _cfg)),
w(k, w) AS (VALUES (0,'casa'),(1,'perro'),(2,'gato'),(3,'heart'),(4,'kidney'),(5,'Paris'),(6,'Tokyo'),(7,'river'),(8,'battle'),(9,'empire'),(10,'taberu'),(11,'nomu')),
t(k, t) AS (VALUES (0,'spanish::verbs'),(1,'spanish::nouns'),(2,'japanese::n5'),(3,'med::cardio'),(4,'med::renal'),(5,'geo'),(6,'history::rome'),(7,'leech')),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO notes(id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data)
SELECT 1767100000000 - (20000*(SELECT scale FROM _cfg) - i) * 2400000,
       printf('g%010x', h),
       1500000000001 + (h / 8) % 4,
       1767100000 - (20000*(SELECT scale FROM _cfg) - i) * 2400 + (h / 32) % 864000,
       CASE WHEN (h / 4096) % 50 = 0 THEN -1 ELSE 100 + (h / 4096) % 40 END,
       CASE WHEN (h / 512) % 6 = 0 THEN '' ELSE ' ' || (SELECT t FROM t WHERE k = (h / 512) % 8) ||
            CASE WHEN (h / 65536) % 3 = 0 THEN ' ' || (SELECT t FROM t WHERE k = (h / 1048576) % 8) ELSE '' END || ' ' END,
       CASE (h / 8) % 4
         WHEN 2 THEN 'The {{c1::' || (SELECT w FROM w WHERE k = (h / 128) % 12) || '}} is number ' || i || char(31) || 'extra ' || (h % 1000)
         WHEN 3 THEN (SELECT w FROM w WHERE k = (h / 128) % 12) || i || char(31) || 'meaning of ' || (SELECT w FROM w WHERE k = (h / 128) % 12) || char(31) || 'reading' || (h % 97) || char(31) || 'Example sentence ' || i
         ELSE (SELECT w FROM w WHERE k = (h / 128) % 12) || ' ' || i || char(31) || 'Answer <b>' || (SELECT w FROM w WHERE k = (h / 2048) % 12) || '</b> ' || (h % 1000) END,
       CASE (h / 8) % 4
         WHEN 2 THEN 'The {{c1::' || (SELECT w FROM w WHERE k = (h / 128) % 12) || '}} is number ' || i
         WHEN 3 THEN (SELECT w FROM w WHERE k = (h / 128) % 12) || i
         ELSE (SELECT w FROM w WHERE k = (h / 128) % 12) || ' ' || i END,
       CASE WHEN i % 200 = 0 THEN 12345 ELSE (h / 3) % 2000000000 END,
       0, ''
FROM m;

-- cards: one per template (cloze notes get 1-3 cards)
WITH nt(mid, ord) AS (SELECT ntid, ord FROM templates
                      UNION ALL SELECT 1500000000003, 1 UNION ALL SELECT 1500000000003, 2),
c AS (SELECT n.id AS nid, nt.ord, n.mid, ((n.id / 2400000 + nt.ord * 7919) * 2654435761) % 4294967296 AS h,
             row_number() OVER (ORDER BY n.id, nt.ord) AS rn
      FROM notes n JOIN nt ON nt.mid = n.mid
      WHERE nt.ord = 0 OR n.mid != 1500000000003 OR nt.ord <= (n.id / 2400000) % 3),
s AS (SELECT *, CASE WHEN (h / 16) % 100 < 30 THEN 0       -- new
                     WHEN (h / 16) % 100 < 38 THEN 1       -- learning
                     WHEN (h / 16) % 100 < 41 THEN 3       -- day learning (type 1)
                     WHEN (h / 16) % 100 < 90 THEN 2       -- review
                     WHEN (h / 16) % 100 < 93 THEN 4       -- relearning (type 3, queue 1)
                     WHEN (h / 16) % 100 < 97 THEN -1      -- suspended review
                     WHEN (h / 16) % 100 < 99 THEN -2 ELSE -3 END AS st,
                (h / 4096) % 41 AS dk, (h / 262144) % 50 = 0 AS filt
      FROM c)
INSERT INTO cards(id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data)
SELECT nid + ord,
       nid,
       CASE WHEN filt THEN 1600000000100 WHEN dk = 40 THEN 1 ELSE 1600000000001 + dk END,
       ord,
       1767200000 - (h / 64) % 5000000,
       CASE WHEN (h / 128) % 40 = 0 THEN -1 ELSE 100 + (h / 128) % 40 END,
       CASE st WHEN 0 THEN 0 WHEN 1 THEN 1 WHEN 3 THEN 1 WHEN 4 THEN 3 ELSE 2 END,
       CASE st WHEN 4 THEN 1 ELSE st END,
       CASE st WHEN 0 THEN rn
               WHEN 1 THEN 1767200000 - 3000 + (h / 1024) % 6000
               WHEN 4 THEN 1767200000 - 3000 + (h / 1024) % 6000
               WHEN 3 THEN 1500 - 2 + (h / 1024) % 5
               ELSE 1500 - 60 + (h / 1024) % 300 END,
       CASE WHEN st IN (0, 1) THEN 0 ELSE 1 + (h / 2048) % 365 END,
       CASE WHEN st = 0 THEN 0 ELSE 1300 + ((h / 8192) % 18) * 100 END,
       CASE WHEN st = 0 THEN 0 ELSE 1 + (h / 32768) % 40 END,
       CASE WHEN st = 0 THEN 0 ELSE (h / 65536) % 6 END,
       CASE WHEN st IN (1, 3, 4) THEN 1002 ELSE 0 END,
       CASE WHEN filt THEN CASE st WHEN 0 THEN rn ELSE 1500 - 60 + (h / 1024) % 300 END ELSE 0 END,
       CASE WHEN filt THEN 1600000000001 + dk % 40 ELSE 0 END,
       CASE WHEN (h / 524288) % 20 = 0 THEN 1 + (h / 8) % 4 ELSE 0 END,
       CASE WHEN st = 0 THEN '{"pos":' || rn || '}'
            WHEN (h / 1048576) % 3 = 0 THEN json_object('s', round(1 + ((h / 64) % 3000) / 10.0, 1), 'd', round(1 + ((h / 32) % 90) / 10.0, 1), 'dr', 0.9)
            ELSE '' END
FROM s;

-- revlog: 120k reviews over the last ~2 years, newest at "now"
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 120000*(SELECT scale FROM _cfg)),
rc AS (SELECT id, row_number() OVER (ORDER BY id) - 1 AS k FROM cards WHERE type != 0),
m AS (SELECT i, (i * 2246822519) % 4294967296 AS h FROM n)
INSERT INTO revlog(id, cid, usn, ease, ivl, lastIvl, factor, time, type)
SELECT 1767200000000 - (i - 1) * 525000 - (h % 1000),
       (SELECT id FROM rc WHERE k = (h / 1024) % (SELECT count(*) FROM rc)),
       CASE WHEN i < 200 THEN -1 ELSE 100 + (h / 64) % 40 END,
       CASE WHEN (h / 8) % 50 = 0 THEN 0 ELSE 1 + (h / 16) % 4 END,
       CASE WHEN (h / 128) % 4 = 0 THEN -600 ELSE 1 + (h / 256) % 200 END,
       CASE WHEN (h / 128) % 4 = 0 THEN 0 ELSE (h / 512) % 150 END,
       CASE WHEN (h / 8) % 50 = 0 THEN 0 ELSE 1300 + ((h / 2048) % 18) * 100 END,
       1000 + (h / 4096) % 40000,
       CASE WHEN (h / 8) % 50 = 0 THEN 4 ELSE (h / 32768) % 4 END
FROM m;

INSERT INTO tags(tag, usn, collapsed, config)
VALUES ('spanish', 0, 0, NULL), ('spanish::verbs', 0, 0, NULL), ('spanish::nouns', 0, 1, NULL), ('japanese', 0, 0, NULL),
       ('japanese::n5', -1, 0, NULL), ('med', 0, 0, NULL), ('med::cardio', 0, 0, NULL), ('med::renal', 0, 0, NULL),
       ('geo', 0, 0, NULL), ('history', 0, 0, NULL), ('history::rome', -1, 0, NULL), ('leech', 0, 0, NULL);

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 600*(SELECT scale FROM _cfg))
INSERT INTO graves(oid, type, usn)
SELECT 1700000000000 + i * 7919, i % 3, CASE WHEN i % 4 = 0 THEN -1 ELSE 50 + i % 60 END FROM n;

-- session temp tables: the current deck is "Spanish" (and its children), a browser search hit ~1/15 of cards
INSERT INTO active_decks(id) SELECT id FROM decks WHERE name = 'Spanish' OR (name >= 'Spanish' || char(31) AND name < 'Spanish' || char(32)) ORDER BY name;
INSERT INTO search_cids(cid) SELECT id FROM cards WHERE ((id / 2400000) * 7 + ord) % 15 = 0;
INSERT INTO search_nids(nid) SELECT id FROM notes WHERE (id / 2400000) % 20 = 3;
INSERT INTO sort_order(did) SELECT id FROM decks ORDER BY name;

COMMIT;
