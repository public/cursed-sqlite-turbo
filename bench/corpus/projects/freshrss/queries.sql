-- FreshRSS (FreshRSS/FreshRSS @ fd3f75b3a225309d2255a7f221e10028d527edec, AGPL-3.0). PHP PDO with `?` positional or
-- `:name` parameters; the entry list, mark-read and archiving statements are concatenated at runtime from options and the
-- parsed search expression, so each one below is a single representative instantiation (tagged dynamic).
-- Normalisation: the app writes tables as `_entry`, `_feed`, ...; Minz_Pdo rewrites the leading `_` to the per-user
-- prefix, which is empty for SQLite, so they appear here as `entry`, `feed`, ... Positional `?` become ?N in order.
-- "Now" in the parameters is 1761600000 (entry ids are microsecond timestamps, so id_max is 1761600000000000);
-- the stats queries use a timezone offset of 3600 s.

-- @id freshrss.entry.list_where.main_stream_unread
-- @src app/Models/EntryDAO.php:1542-1772
-- @style ? positional; sqlListWhere (type 'a', state STATE_NOT_READ, sort id DESC) wrapped by listWhereRaw's late row lookup
-- @tags hotpath,dynamic
-- @note The main page: unread entries of main-stream feeds, newest first, as a top-N id subquery joined back to entry for the full rows.
-- @param ?1 '1761600000000000'
SELECT e0.id, e0.guid, e0.title, e0.author, e0.content, e0.link,
       e0.date, e0.`lastSeen`, e0.`lastModified`, e0.`lastUserModified`, hex(e0.hash) AS hash, e0.is_read, e0.is_favorite, e0.id_feed, e0.tags, e0.attributes
FROM `entry` e0 INNER JOIN (
  SELECT e.id FROM `entry` e INNER JOIN `feed` f ON f.id = e.id_feed
  WHERE f.priority >= 10 AND (e.is_read=0) AND e.id <= ?1
  ORDER BY e.id DESC LIMIT 21
) e2 ON e2.id=e0.id
ORDER BY e0.id DESC;

-- @id freshrss.entry.list_where.category_search_by_date_page2
-- @src app/Models/EntryDAO.php:1542-1772
-- @style ? positional; type 'c', state STATE_ALL, sort date DESC with keyset continuation (sqlListEntriesWhere:1401), search `linux` (sqlBooleanSearch:957)
-- @tags hotpath,dynamic
-- @note Second page of a free-text search inside one category, sorted by publication date: keyset OR-predicate on (date, id) plus title/content LIKE '%…%'.
-- @param ?1 5
-- @param ?2 '1761600000000000'
-- @param ?3 1761000000
-- @param ?4 1761000000
-- @param ?5 '1761000000000000'
-- @param ?6 '%linux%'
-- @param ?7 '%linux%'
SELECT e0.id, e0.guid, e0.title, e0.author, e0.content, e0.link,
       e0.date, e0.`lastSeen`, e0.`lastModified`, e0.`lastUserModified`, hex(e0.hash) AS hash, e0.is_read, e0.is_favorite, e0.id_feed, e0.tags, e0.attributes
FROM `entry` e0 INNER JOIN (
  SELECT e.id FROM `entry` e INNER JOIN `feed` f ON f.id = e.id_feed
  WHERE f.priority >= 0 AND f.category=?1
    AND e.id <= ?2
    AND (e.date < ?3 OR (e.date = ?4 AND e.id <= ?5))
    AND ((e.title LIKE ?6 OR e.content LIKE ?7))
  ORDER BY e.date DESC, e.id DESC LIMIT 21
) e2 ON e2.id=e0.id
ORDER BY e0.date DESC, e0.id DESC;

-- @id freshrss.entry.list_where.by_category_name_keyset
-- @src app/Models/EntryDAO.php:1542-1772
-- @style ? positional; type 'A', state STATE_NOT_READ|STATE_OR_FAVORITE, sort c.name ASC + secondary date DESC, keyset continuation
-- @tags hotpath,dynamic
-- @note Unread-or-starred entries grouped by category then feed name: 3-way join inside and outside the id subquery, a four-arm keyset OR over (c.name, f.name, date, id).
-- @param ?1 '1761600000000000'
-- @param ?2 'Blogs 11'
-- @param ?3 'Blogs 11'
-- @param ?4 'Linux Weekly 110'
-- @param ?5 'Blogs 11'
-- @param ?6 'Linux Weekly 110'
-- @param ?7 1761329966
-- @param ?8 'Blogs 11'
-- @param ?9 'Linux Weekly 110'
-- @param ?10 1761329966
-- @param ?11 '1761330840000000'
SELECT e0.id, e0.guid, e0.title, e0.author, e0.content, e0.link,
       e0.date, e0.`lastSeen`, e0.`lastModified`, e0.`lastUserModified`, hex(e0.hash) AS hash, e0.is_read, e0.is_favorite, e0.id_feed, e0.tags, e0.attributes
FROM `entry` e0 INNER JOIN (
  SELECT e.id FROM `entry` e INNER JOIN `feed` f ON f.id = e.id_feed INNER JOIN `category` c ON c.id = f.category
  WHERE f.priority >= 0 AND (e.is_read=0 OR e.is_favorite=1)
    AND e.id <= ?1
    AND ((c.name > ?2) OR (c.name = ?3 AND f.name > ?4) OR (c.name = ?5 AND f.name = ?6 AND e.date < ?7)
         OR (c.name = ?8 AND f.name = ?9 AND e.date = ?10 AND e.id >= ?11))
  ORDER BY c.name ASC, f.name ASC, e.date DESC, e.id ASC LIMIT 21
) e2 ON e2.id=e0.id
INNER JOIN `feed` f0 ON f0.id = e0.id_feed
INNER JOIN `category` c0 ON c0.id = f0.category
ORDER BY c0.name ASC, f0.name ASC, e0.date DESC, e0.id ASC;

-- @id freshrss.entry.list_where.any_label_by_title
-- @src app/Models/EntryDAO.php:1542-1772
-- @style ? positional; type 'T' (any label), state STATE_ALL, sort title ASC
-- @tags hotpath,dynamic
-- @note All labelled entries sorted by title: SELECT DISTINCT e.id, e.title over the entrytag join, then the late row lookup.
-- @param ?1 '1761600000000000'
SELECT e0.id, e0.guid, e0.title, e0.author, e0.content, e0.link,
       e0.date, e0.`lastSeen`, e0.`lastModified`, e0.`lastUserModified`, hex(e0.hash) AS hash, e0.is_read, e0.is_favorite, e0.id_feed, e0.tags, e0.attributes
FROM `entry` e0 INNER JOIN (
  SELECT DISTINCT e.id, e.title FROM `entry` e INNER JOIN `feed` f ON f.id = e.id_feed INNER JOIN `entrytag` et ON et.id_entry = e.id
  WHERE 1=1 AND e.id <= ?1
  ORDER BY e.title ASC, e.id ASC LIMIT 21
) e2 ON e2.id=e0.id
ORDER BY e0.title ASC, e0.id ASC;

-- @id freshrss.entry.list_where.label_boolean_search
-- @src app/Models/EntryDAO.php:1542-1772
-- @style ? positional; type 't' (one label), state STATE_NOT_READ, search `(intitle:linux OR author:"Author 1") date:2025-09-01/ -#football` via sqlBooleanSearch:957
-- @tags hotpath,dynamic
-- @note Nested boolean search inside a label: OR of LIKE groups AND a date-bounded NOT LIKE on the concatenated hashtag string.
-- @param ?1 2
-- @param ?2 '1761600000000000'
-- @param ?3 '%linux%'
-- @param ?4 '%Author 1%'
-- @param ?5 '1756684800000000'
-- @param ?6 '%football #%'
SELECT e0.id, e0.guid, e0.title, e0.author, e0.content, e0.link,
       e0.date, e0.`lastSeen`, e0.`lastModified`, e0.`lastUserModified`, hex(e0.hash) AS hash, e0.is_read, e0.is_favorite, e0.id_feed, e0.tags, e0.attributes
FROM `entry` e0 INNER JOIN (
  SELECT e.id FROM `entry` e INNER JOIN `feed` f ON f.id = e.id_feed INNER JOIN `entrytag` et ON et.id_entry = e.id
  WHERE et.id_tag=?1 AND (e.is_read=0) AND e.id <= ?2
    AND (((e.title LIKE ?3) OR (e.author LIKE ?4)) AND ((e.id >= ?5 AND TRIM(e.tags) || ' #' NOT LIKE ?6)))
  ORDER BY e.id DESC LIMIT 21
) e2 ON e2.id=e0.id
ORDER BY e0.id DESC;

-- @id freshrss.entry.list_ids_where.starred_or_labelled
-- @src app/Models/EntryDAO.php:1849-1871
-- @style ? positional; listIdsWhere -> sqlListWhere type 'ST', state STATE_NOT_READ, limit 1000 (Google Reader API stream/items/ids)
-- @tags hotpath,dynamic
-- @note Id-only stream for the API: `e.is_favorite=1 OR EXISTS(...)` is emitted unparenthesised, so the AND-ed state/id filters bind to the EXISTS arm only.
-- @param ?1 '1761600000000000'
SELECT e.id FROM `entry` e INNER JOIN `feed` f ON f.id = e.id_feed
WHERE e.is_favorite=1 OR EXISTS (SELECT et2.id_tag FROM `entrytag` et2 WHERE et2.id_entry = e.id) AND (e.is_read=0) AND e.id <= ?1
ORDER BY e.id DESC LIMIT 1000;

-- @id freshrss.entry.list_by_ids
-- @src app/Models/EntryDAO.php:1797-1832
-- @style ? positional, IN list sized at runtime (Google Reader API stream/items/contents)
-- @tags hotpath,dynamic
-- @note API fetch of 20 entries by id: IN-list point lookups with hex() of the hash.
-- @param ?1 '1761597600000000'
-- @param ?2 '1761597540000000'
-- @param ?3 '1761597480000000'
-- @param ?4 '1761597420000000'
-- @param ?5 '1761597360000000'
-- @param ?6 '1761597300000000'
-- @param ?7 '1761597240000000'
-- @param ?8 '1761597180000000'
-- @param ?9 '1761597120000000'
-- @param ?10 '1761597060000000'
-- @param ?11 '1761597000000000'
-- @param ?12 '1761596940000000'
-- @param ?13 '1761596880000000'
-- @param ?14 '1761596820000000'
-- @param ?15 '1761596760000000'
-- @param ?16 '1761596700000000'
-- @param ?17 '1761596640000000'
-- @param ?18 '1761596580000000'
-- @param ?19 '1761596520000000'
-- @param ?20 '1761596460000000'
SELECT id, guid, title, author, link, date, `lastModified`, `lastUserModified`,
       hex(hash) AS hash, is_read, is_favorite, id_feed, tags, attributes, content
FROM `entry`
WHERE id IN (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20)
ORDER BY id DESC;

-- @id freshrss.entry.list_feed_ids_matching
-- @src app/Models/EntryDAO.php:1873-1897
-- @style ? positional; sqlListEntriesWhere(state STATE_NOT_READ, search `sqlite`)
-- @tags hotpath,dynamic
-- @note Per-feed match counts for a search (sidebar counts of a user query): full scan with LIKE on title/content, GROUP BY feed.
-- @param ?1 '%sqlite%'
-- @param ?2 '%sqlite%'
SELECT e.id_feed, COUNT(*) AS count FROM `entry` e
WHERE 1=1 AND (e.is_read=0) AND ((e.title LIKE ?1 OR e.content LIKE ?2))
GROUP BY e.id_feed;

-- @id freshrss.entry.search_by_guid
-- @src app/Models/EntryDAO.php:912-928
-- @style :name
-- @tags hot-small,hotpath
-- @note Feed refresh: point lookup on the (id_feed, guid) unique index.
-- @param :id_feed 1
-- @param :guid 'https://site1.example.org/posts/99830'
SELECT id, guid, title, author, content, link, date, `lastSeen`, `lastModified`, `lastUserModified`,
       hex(hash) AS hash, is_read, is_favorite, id_feed, tags, attributes,
       LENGTH(content) AS content_length
FROM `entry` WHERE id_feed=:id_feed AND guid=:guid;

-- @id freshrss.entry.list_hash_for_feed_guids
-- @src app/Models/EntryDAO.php:1899-1939
-- @style ? positional, IN list sized at runtime
-- @tags hotpath,dynamic
-- @note Feed refresh dedup: which of the fetched guids exist already and with which content hash.
-- @param ?1 30
-- @param ?2 'https://site30.example.org/posts/99997'
-- @param ?3 'https://site30.example.org/posts/99932'
-- @param ?4 'https://site30.example.org/posts/99916'
-- @param ?5 'https://site30.example.org/posts/99851'
-- @param ?6 'https://site30.example.org/posts/99835'
-- @param ?7 'https://site30.example.org/posts/99831'
-- @param ?8 'https://site30.example.org/posts/99770'
-- @param ?9 'https://site30.example.org/posts/new-1'
-- @param ?10 'https://site30.example.org/posts/new-2'
-- @param ?11 'https://site30.example.org/posts/new-3'
SELECT guid, hex(hash) AS hex_hash
FROM `entry`
WHERE id_feed=?1 AND guid IN (?2,?3,?4,?5,?6,?7,?8,?9,?10,?11);

-- @id freshrss.entry.add_entry_tmp
-- @src app/Models/EntryDAO.php:192-263
-- @style :name; EntryDAOSQLite::sqlIgnoreConflict turns INSERT INTO into INSERT OR IGNORE INTO, sqlHexDecode is the identity
-- @tags hot-small,hotpath
-- @note Per-item insert into the staging table during a feed refresh.
-- @param :id '1761600000999000'
-- @param :guid 'https://site30.example.org/posts/new-9999'
-- @param :title 'A new post about sqlite'
-- @param :author 'Author 7'
-- @param :content '<p>New content.</p>'
-- @param :link 'https://site30.example.org/new/9999.html'
-- @param :date 1761599000
-- @param :last_seen 1761600000
-- @param :hash X'00112233445566778899aabbccddeeff'
-- @param :is_read 0
-- @param :is_favorite 0
-- @param :id_feed 30
-- @param :tags '#sqlite'
-- @param :attributes '{}'
INSERT OR IGNORE INTO `entrytmp` (id, guid, title, author, content, link, date, `lastSeen`, hash, is_read, is_favorite, id_feed, tags, attributes)
VALUES(:id, :guid, :title, :author, :content, :link, :date, :last_seen, :hash, :is_read, :is_favorite, :id_feed, :tags, :attributes);

-- @id freshrss.entry.commit_new_entries.insert
-- @src app/Models/EntryDAOSQLite.php:87-115
-- @style no parameters; one statement of a multi-statement exec() batch
-- @tags hotpath,batch
-- @note Commit of a refresh: staged rows renumbered in (date, id) order to fresh ids above MAX(id) and copied with INSERT OR IGNORE … SELECT … ORDER BY.
-- @modified The app first runs CREATE TEMP TABLE tmp AS SELECT … FROM entrytmp ORDER BY date, id and then numbers rows by tmp.rowid; here tmp is a CTE and rowid is row_number() OVER (ORDER BY date, id), which yields the same numbering in one statement.
WITH `tmp` AS (
  SELECT row_number() OVER (ORDER BY date, id) AS rowid_, id, guid, title, author, content, link, date, `lastSeen`, hash, is_read, is_favorite, id_feed, tags, attributes
  FROM `entrytmp`
)
INSERT OR IGNORE INTO `entry`
  (id, guid, title, author, content, link, date, `lastSeen`, hash, is_read, is_favorite, id_feed, tags, attributes)
SELECT rowid_ + (SELECT MAX(id) - COUNT(*) FROM `tmp`) AS id,
       guid, title, author, content, link, date, `lastSeen`, hash, is_read, is_favorite, id_feed, tags, attributes
FROM `tmp` t
ORDER BY t.date, t.id;

-- @id freshrss.entry.commit_new_entries.delete
-- @src app/Models/EntryDAOSQLite.php:87-115
-- @style no parameters; last DML statement of the commit batch
-- @tags hotpath
-- @note Clears the committed staging rows.
-- @modified The app reads MAX(id) from the temp copy `tmp` of entrytmp; it holds the same rows, so this reads entrytmp directly.
DELETE FROM `entrytmp` WHERE id <= (SELECT MAX(id) FROM `entrytmp`);

-- @id freshrss.entry.update_entry
-- @src app/Models/EntryDAO.php:297-399
-- @style :name; sqlHexDecode is the identity on SQLite
-- @tags hot-small,hotpath
-- @note Refresh of a changed item: unique-index point update with COALESCE keeps for user state.
-- @param :title 'Updated title about rust'
-- @param :author 'Author 12'
-- @param :content '<p>Updated content.</p>'
-- @param :link 'https://site1.example.org/linux/99830.html'
-- @param :date 1761589000
-- @param :last_seen 1761600000
-- @param :last_modified 1761600000
-- @param :last_user_modified NULL
-- @param :hash X'ffeeddccbbaa99887766554433221100'
-- @param :is_read NULL
-- @param :is_favorite NULL
-- @param :tags '#rust'
-- @param :attributes '{}'
-- @param :id_feed 1
-- @param :guid 'https://site1.example.org/posts/99830'
UPDATE `entry`
SET title=:title, author=:author, content=:content, link=:link, date=:date, `lastSeen`=:last_seen,
    `lastModified`=COALESCE(:last_modified, `lastModified`),
    `lastUserModified`=COALESCE(:last_user_modified, `lastUserModified`),
    hash=:hash,
    is_read=COALESCE(:is_read, is_read),
    is_favorite=COALESCE(:is_favorite, is_favorite),
    tags=:tags, attributes=:attributes
WHERE id_feed=:id_feed AND guid=:guid;

-- @id freshrss.entry.mark_read.single
-- @src app/Models/EntryDAOSQLite.php:125-160
-- @style :name (id bound as a string)
-- @tags hot-small,hotpath
-- @note Opening an article: the SQLite markRead path, one id at a time.
-- @param :is_read 1
-- @param :last_user_modified 1761600000
-- @param :id '1761599700000000'
-- @param :previous_is_read 0
UPDATE `entry` SET is_read=:is_read, `lastUserModified` = :last_user_modified
WHERE id=:id AND is_read=:previous_is_read;

-- @id freshrss.entry.mark_read.single_feed_cache
-- @src app/Models/EntryDAOSQLite.php:159-172
-- @style :name
-- @tags hot-small,hotpath
-- @note Second half of markRead: decrement the feed's cached unread count via a scalar subquery on the entry.
-- @param :id '1761599700000000'
UPDATE `feed` SET `cache_nbUnreads`=`cache_nbUnreads` -1
WHERE id=(SELECT e.id_feed FROM `entry` e WHERE e.id=:id);

-- @id freshrss.entry.mark_favorite
-- @src app/Models/EntryDAO.php:416-451
-- @style ? positional, IN list sized at runtime
-- @tags hotpath,dynamic
-- @note Star a selection of 10 entries (API edit-tag).
-- @param ?1 1
-- @param ?2 1761600000
-- @param ?3 '1761597600000000'
-- @param ?4 '1761597540000000'
-- @param ?5 '1761597480000000'
-- @param ?6 '1761597420000000'
-- @param ?7 '1761597360000000'
-- @param ?8 '1761597300000000'
-- @param ?9 '1761597240000000'
-- @param ?10 '1761597180000000'
-- @param ?11 '1761597120000000'
-- @param ?12 '1761597060000000'
UPDATE `entry`
SET is_favorite=?1, `lastUserModified`=?2
WHERE id IN (?3,?4,?5,?6,?7,?8,?9,?10,?11,?12);

-- @id freshrss.entry.update_cache_unreads.all
-- @src app/Models/EntryDAO.php:458-492
-- @style no parameters (catId and feedId both null)
-- @tags hotpath
-- @note After every bulk mark-read: every feed's cached unread count recomputed by a correlated COUNT on the (id_feed, is_read) index.
UPDATE `feed`
SET `cache_nbUnreads`=(
  SELECT COUNT(*) AS nbUnreads FROM `entry` e
  WHERE e.id_feed=`feed`.id AND e.is_read=0)
WHERE 1=1;

-- @id freshrss.entry.mark_read_entries.main_stream_search
-- @src app/Models/EntryDAO.php:592-643
-- @style ? positional; priorityMin set, state 0, search `intitle:rust` appended by sqlListEntriesWhere (alias '')
-- @tags hotpath,dynamic
-- @note "Mark all as read" on a search over the main stream: IN-subquery on feed priority plus title LIKE, bounded by the id_max fail-safe.
-- @param ?1 1
-- @param ?2 1761600000
-- @param ?3 1
-- @param ?4 '1761600000000000'
-- @param ?5 10
-- @param ?6 '%rust%'
UPDATE `entry` SET is_read = ?1, `lastUserModified`=?2 WHERE is_read <> ?3 AND id <= ?4
AND id_feed IN (SELECT f.id FROM `feed` f WHERE 1=1
AND f.priority >= ?5
)
AND ((title LIKE ?6));

-- @id freshrss.entry.mark_read_tag
-- @src app/Models/EntryDAOSQLite.php:190-220
-- @style ? positional; SQLite override (no UPDATE … JOIN), tag condition present, state 0
-- @tags hotpath,dynamic
-- @note Mark a label as read: IN-subquery over entrytag's primary key.
-- @param ?1 1
-- @param ?2 1761600000
-- @param ?3 1
-- @param ?4 '1761600000000000'
-- @param ?5 3
UPDATE `entry` SET is_read = ?1, `lastUserModified` = ?2 WHERE is_read <> ?3 AND id <= ?4
AND id IN (SELECT et.id_entry FROM `entrytag` et WHERE et.id_tag = ?5);

-- @id freshrss.entry.clean_old_entries
-- @src app/Models/EntryDAO.php:797-881
-- @style :name; every archiving option set (keep_favourites, keep_labels, keep_min, keep_period, keep_max)
-- @tags dynamic
-- @note Per-feed archiving after a refresh: NOT EXISTS on labels, three derived-table scalar subqueries (OFFSET :keep_min, MAX, OFFSET :keep_max) over the feed's entries.
-- @param :id_feed1 30
-- @param :id_feed2 30
-- @param :keep_min 50
-- @param :id_feed3 30
-- @param :max_last_seen 1753651200
-- @param :id_feed4 30
-- @param :keep_max 200
DELETE FROM `entry` WHERE id_feed = :id_feed1
AND is_favorite = 0
AND NOT EXISTS (SELECT 1 FROM `entrytag` WHERE id_entry = id)
AND `lastSeen` < (SELECT `lastSeen`
  FROM (SELECT e2.`lastSeen` FROM `entry` e2 WHERE e2.id_feed = :id_feed2
  ORDER BY e2.`lastSeen` DESC LIMIT 1 OFFSET :keep_min) last_seen2)
AND `lastSeen` < (SELECT maxlastseen
  FROM (SELECT MAX(e3.`lastSeen`) AS maxlastseen FROM `entry` e3 WHERE e3.id_feed = :id_feed3) last_seen3)
AND (1=0
OR `lastSeen` < :max_last_seen
OR `lastSeen` <= (SELECT `lastSeen`
  FROM (SELECT e4.`lastSeen` FROM `entry` e4 WHERE e4.id_feed = :id_feed4
  ORDER BY e4.`lastSeen` DESC LIMIT 1 OFFSET :keep_max) last_seen4)
);

-- @id freshrss.entry.update_last_seen
-- @src app/Models/EntryDAO.php:1941-1982
-- @style ? positional, IN list sized at runtime
-- @tags hotpath,dynamic
-- @note Feed refresh: bump lastSeen on the guids still present in the feed.
-- @param ?1 1761600000
-- @param ?2 30
-- @param ?3 'https://site30.example.org/posts/99997'
-- @param ?4 'https://site30.example.org/posts/99932'
-- @param ?5 'https://site30.example.org/posts/99916'
-- @param ?6 'https://site30.example.org/posts/99851'
-- @param ?7 'https://site30.example.org/posts/99835'
-- @param ?8 'https://site30.example.org/posts/99831'
-- @param ?9 'https://site30.example.org/posts/99770'
-- @param ?10 'https://site30.example.org/posts/99754'
-- @param ?11 'https://site30.example.org/posts/99689'
-- @param ?12 'https://site30.example.org/posts/99673'
UPDATE `entry`
SET `lastSeen`=?1 WHERE id_feed=?2 AND guid IN (?3,?4,?5,?6,?7,?8,?9,?10,?11,?12);

-- @id freshrss.entry.count_as_states
-- @src app/Models/EntryDAO.php:2010-2034
-- @style :name; minPriority set
-- @tags hotpath
-- @note Navigation counters: total/unread/favourite in one pass with COUNT(CASE …), joined to feed for visibility.
-- @param :priority -10
SELECT
  COUNT(*) AS total,
  COUNT(CASE WHEN e.is_read = 0 THEN 1 END) AS unread,
  COUNT(CASE WHEN e.is_favorite = 1 THEN 1 END) AS favorites
FROM `entry` e
INNER JOIN `feed` f ON e.id_feed = f.id
WHERE f.priority > :priority;

-- @id freshrss.category.list_categories_with_feeds
-- @src app/Models/CategoryDAO.php:326-358
-- @style no parameters; prePopulateFeeds, details=false
-- @tags hotpath
-- @note Sidebar: every category LEFT JOINed to its feeds with their cached counts, GROUP BY f.id, c_id, ordered by category and feed name.
SELECT c.id AS c_id, c.name AS c_name, c.kind AS c_kind, c.`lastUpdate` AS c_last_update, c.error AS c_error, c.attributes AS c_attributes,
       f.id, f.name, f.url, f.kind, f.website, f.priority, f.error, f.attributes, f.`cache_nbEntries`, f.`cache_nbUnreads`, f.ttl
FROM `category` c
LEFT OUTER JOIN `feed` f ON f.category=c.id
GROUP BY f.id, c_id
ORDER BY c.name, f.name;

-- @id freshrss.category.count_not_read
-- @src app/Models/CategoryDAO.php:444-453
-- @style :name
-- @tags hotpath
-- @note Unread count of one category through the feed join.
-- @param :id 5
-- @param :minPriority 0
SELECT COUNT(*) AS count FROM `entry` e
INNER JOIN `feed` f ON e.id_feed=f.id
WHERE f.category=:id AND e.is_read=0
AND f.priority>=:minPriority;

-- @id freshrss.feed.list_feeds_order_update
-- @src app/Models/FeedDAO.php:443-475
-- @style values interpolated into the text (TTL_DEFAULT=0, defaultCacheDuration=3600, refreshThreshold=now+60)
-- @tags hotpath,dynamic
-- @note The refresh scheduler: CASE-computed last attempt compared with a per-feed TTL CASE, ordered by the same expression.
SELECT * FROM `feed`
WHERE ttl >= 0
AND (CASE WHEN error > `lastUpdate` THEN error ELSE `lastUpdate` END) < (1761600060-(CASE WHEN ttl=0 THEN 3600 ELSE ttl END))
ORDER BY (CASE WHEN error > `lastUpdate` THEN error ELSE `lastUpdate` END) ASC;

-- @id freshrss.feed.update_cached_values
-- @src app/Models/FeedDAOPGSQL.php:15-56
-- @style ? positional, IN lists sized at runtime (FeedDAOSQLite extends FeedDAOPGSQL)
-- @tags hotpath,dynamic
-- @note After refreshing 3 feeds: CTE with grouped COUNT/SUM(CASE) feeding two correlated scalar subqueries in an UPDATE.
-- @param ?1 1
-- @param ?2 30
-- @param ?3 59
-- @param ?4 1
-- @param ?5 30
-- @param ?6 59
WITH entry_counts AS (
  SELECT
    id_feed,
    COUNT(*) AS total_entries,
    SUM(CASE WHEN is_read = 0 THEN 1 ELSE 0 END) AS unread_entries
  FROM `entry`
  WHERE id_feed IN (?1,?2,?3)
  GROUP BY id_feed
)
UPDATE `feed`
SET `cache_nbEntries` = COALESCE((
    SELECT c.total_entries
    FROM entry_counts AS c
    WHERE c.id_feed = `feed`.id
  ), 0),
  `cache_nbUnreads` = COALESCE((
    SELECT c.unread_entries
    FROM entry_counts AS c
    WHERE c.id_feed = `feed`.id
  ), 0)
WHERE id IN (?4,?5,?6);

-- @id freshrss.feed.mark_as_read_max_unread
-- @src app/Models/FeedDAO.php:596-620
-- @style :name
-- @tags dynamic
-- @note "Keep at most N unread" per feed: UPDATE bounded by a doubly-nested ORDER BY … LIMIT 1 OFFSET :limit subquery.
-- @param :id_feed1 30
-- @param :id_feed2 30
-- @param :limit 100
UPDATE `entry` SET is_read=1
WHERE id_feed=:id_feed1 AND is_read=0 AND id <= (SELECT e3.id FROM (
  SELECT e2.id FROM `entry` e2
  WHERE e2.id_feed=:id_feed2 AND e2.is_read=0
  ORDER BY e2.id DESC
  LIMIT 1
  OFFSET :limit) e3);

-- @id freshrss.tag.list_tags_with_unreads
-- @src app/Models/TagDAO.php:217-245
-- @style no parameters; precounts=true
-- @tags hotpath
-- @note Label list with unread counts: two LEFT JOINs (the second with is_read=0 in the ON clause), GROUP BY tag.
SELECT t.id, t.name, count(e.id) AS unreads
FROM `tag` t
LEFT OUTER JOIN `entrytag` et ON et.id_tag = t.id
LEFT OUTER JOIN `entry` e ON et.id_entry = e.id AND e.is_read = 0
GROUP BY t.id
ORDER BY t.name;

-- @id freshrss.tag.get_tags_for_entries
-- @src app/Models/TagDAO.php:391-430
-- @style ? positional, IN list appended to the join condition
-- @tags hotpath,dynamic
-- @note Labels of the 20 entries on screen: the IN list lands in the INNER JOIN's ON clause.
-- @param ?1 '1761597600000000'
-- @param ?2 '1761597540000000'
-- @param ?3 '1761597480000000'
-- @param ?4 '1761597420000000'
-- @param ?5 '1761597360000000'
-- @param ?6 '1761597300000000'
-- @param ?7 '1761597240000000'
-- @param ?8 '1761597180000000'
-- @param ?9 '1761597120000000'
-- @param ?10 '1761597060000000'
-- @param ?11 '1761597000000000'
-- @param ?12 '1761596940000000'
-- @param ?13 '1761596880000000'
-- @param ?14 '1761596820000000'
-- @param ?15 '1761596760000000'
-- @param ?16 '1761596700000000'
-- @param ?17 '1761596640000000'
-- @param ?18 '1761596580000000'
-- @param ?19 '1761596520000000'
-- @param ?20 '1761596460000000'
SELECT et.id_entry, et.id_tag, t.name
FROM `tag` t
INNER JOIN `entrytag` et ON et.id_tag = t.id
AND et.id_entry IN (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20);

-- @id freshrss.tag.tag_entries.batch
-- @src app/Models/TagDAO.php:331-353
-- @style values interpolated as integer literals; TagDAOSQLite::sqlIgnoreConflict adds OR IGNORE
-- @tags batch,dynamic
-- @note Bulk labelling (filter actions after a refresh): multi-row VALUES insert into the composite primary key.
INSERT OR IGNORE INTO `entrytag`(id_tag, id_entry) VALUES
(4,1761597600000000),(4,1761597540000000),(4,1761597480000000),(4,1761597420000000),(4,1761597360000000),
(4,1761597300000000),(4,1761597240000000),(4,1761597180000000),(4,1761597120000000),(4,1761597060000000),
(7,1761597600000000),(7,1761597540000000),(7,1761597480000000),(7,1761597420000000),(7,1761597360000000);

-- @id freshrss.tag.tag_entry
-- @src app/Models/TagDAO.php:304-325
-- @style :name; TagDAOSQLite::sqlIgnoreConflict adds OR IGNORE
-- @tags hot-small,hotpath
-- @note Label one entry from the UI.
-- @param :id_tag 9
-- @param :id_entry '1761599700000000'
INSERT OR IGNORE INTO `entrytag`(id_tag, id_entry) VALUES(:id_tag, :id_entry);

-- @id freshrss.stats.entry_count_per_day
-- @src app/Models/StatsDAO.php:88-116
-- @style values interpolated; sqlFloor from StatsDAOSQLite.php:24 (midnight 1761523200, 30-day window)
-- @tags dynamic
-- @note Stats page: entries per day over 30 days, bucketed by CAST arithmetic, GROUP BY + ORDER BY the bucket.
SELECT CAST(((date - 1761523200) / 86400) AS INT) AS day,
COUNT(*) as count
FROM `entry`
WHERE date >= 1758931200 AND date < 1761523200
GROUP BY day
ORDER BY day ASC;


-- @id freshrss.stats.top_feed
-- @src app/Models/StatsDAO.php:296-317
-- @style no parameters
-- @note Stats page: top 10 feeds by entry count, MAX() over grouped joins.
SELECT f.id AS id, MAX(f.name) AS name, MAX(c.name) AS category, COUNT(e.id) AS count
FROM `category` AS c, `feed` AS f, `entry` AS e
WHERE c.id = f.category
AND f.id = e.id_feed
GROUP BY f.id
ORDER BY count DESC
LIMIT 10;

-- @id freshrss.stats.max_unread_dates
-- @src app/Models/StatsDAO.php:388-411
-- @style :name; sqlDateToIsoGranularity from StatsDAOSQLite.php:6 (field id, precision 1000000, granularity day)
-- @tags dynamic
-- @note Days with the most unread entries: strftime over the microsecond id, GROUP BY, top-N by count.
-- @param :min_priority -10
-- @param :max 100
SELECT
  strftime('%Y-%m-%d', (e.id / 1000000) + 3600, 'unixepoch') AS granularity,
  COUNT(*) AS unread_count
FROM `entry` e
INNER JOIN `feed` f ON e.id_feed = f.id
WHERE e.is_read = 0 AND f.priority >= :min_priority
GROUP BY granularity
ORDER BY unread_count DESC, granularity DESC
LIMIT :max;
