-- beets (beetbox/beets @ ab4bdfd, MIT). Python sqlite3 with `?` placeholders. Library queries are built by
-- Database._get_results from the parsed beets query tree (FieldQuery.col_clause / AndQuery / OrQuery) and Sort.order_clause,
-- so most statements below are one representative instantiation of a `beet ls` / API call (tagged dynamic).
-- beets registers regexp(), unidecode() and bytelower(); none of the queries below need them (regexp `:` queries and
-- case-insensitive-FS path queries are left out). Whitespace is kept as beets builds it, including trailing spaces.

-- @id beets.ls.items_default
-- @src beets/dbcore/db.py:1399-1475; sort beets/dbcore/sort.py:191-243; config sort_item 'artist+ album+ disc+ track+'
-- @style no binds; Database._get_results string-built
-- @tags hotpath,dynamic
-- @note `beet ls` with no query: AndQuery([TrueQuery]) = '(1)', GROUP BY id in a derived table, then the default 4-key case-insensitive sort (SmartArtistSort COALESCE/NULLIF COLLATE NOCASE + TYPEOF CASE chains) over the whole library.
SELECT items.* FROM (SELECT items.* FROM (items) WHERE (1) GROUP BY items.id ) items ORDER BY COALESCE(NULLIF(artist_sort, ''), artist) COLLATE NOCASE ASC, (CASE WHEN TYPEOF(album)='text' THEN LOWER(album) WHEN TYPEOF(album)='blob' THEN LOWER(album) ELSE album END) ASC, (CASE WHEN TYPEOF(disc)='text' THEN LOWER(disc) WHEN TYPEOF(disc)='blob' THEN LOWER(disc) ELSE disc END) ASC, (CASE WHEN TYPEOF(track)='text' THEN LOWER(track) WHEN TYPEOF(track)='blob' THEN LOWER(track) ELSE track END) ASC ;

-- @id beets.ls.items_anyfield
-- @src beets/dbcore/db.py:1399-1475; any_field_query beets/library/models.py:163-169; SubstringQuery beets/dbcore/query.py:253
-- @style ? positional, WHERE from the query tree
-- @tags hotpath,dynamic
-- @note `beet ls beatles`: free-text term becomes a 6-way OR of LIKE '%beatles%' ESCAPE over item search fields (shared fields table-qualified), default sort.
-- @param ?1 '%beatles%'
-- @param ?2 '%beatles%'
-- @param ?3 '%beatles%'
-- @param ?4 '%beatles%'
-- @param ?5 '%beatles%'
-- @param ?6 '%beatles%'
SELECT items.* FROM (SELECT items.* FROM (items) WHERE (((artist like ? escape '\') or (title like ? escape '\') or (comments like ? escape '\') or (items.album like ? escape '\') or (items.albumartist like ? escape '\') or (items.genres like ? escape '\'))) GROUP BY items.id ) items ORDER BY COALESCE(NULLIF(artist_sort, ''), artist) COLLATE NOCASE ASC, (CASE WHEN TYPEOF(album)='text' THEN LOWER(album) WHEN TYPEOF(album)='blob' THEN LOWER(album) ELSE album END) ASC, (CASE WHEN TYPEOF(disc)='text' THEN LOWER(disc) WHEN TYPEOF(disc)='blob' THEN LOWER(disc) ELSE disc END) ASC, (CASE WHEN TYPEOF(track)='text' THEN LOWER(track) WHEN TYPEOF(track)='blob' THEN LOWER(track) ELSE track END) ASC ;

-- @id beets.ls.items_anyfield_flex
-- @src beets/dbcore/db.py:1399-1475 (flex_sql)
-- @style ? positional; the main statement nested as IN (SELECT id FROM (...))
-- @tags hotpath,dynamic
-- @note Flexible-attribute fetch for `beet ls beatles`: the whole sorted main query re-run as an IN subquery over item_attributes (beets fetches flexattrs for all hits in one statement).
-- @param ?1 '%beatles%'
-- @param ?2 '%beatles%'
-- @param ?3 '%beatles%'
-- @param ?4 '%beatles%'
-- @param ?5 '%beatles%'
-- @param ?6 '%beatles%'
SELECT * FROM item_attributes WHERE entity_id IN (SELECT id FROM (SELECT items.* FROM (SELECT items.* FROM (items) WHERE (((artist like ? escape '\') or (title like ? escape '\') or (comments like ? escape '\') or (items.album like ? escape '\') or (items.albumartist like ? escape '\') or (items.genres like ? escape '\'))) GROUP BY items.id ) items ORDER BY COALESCE(NULLIF(artist_sort, ''), artist) COLLATE NOCASE ASC, (CASE WHEN TYPEOF(album)='text' THEN LOWER(album) WHEN TYPEOF(album)='blob' THEN LOWER(album) ELSE album END) ASC, (CASE WHEN TYPEOF(disc)='text' THEN LOWER(disc) WHEN TYPEOF(disc)='blob' THEN LOWER(disc) ELSE disc END) ASC, (CASE WHEN TYPEOF(track)='text' THEN LOWER(track) WHEN TYPEOF(track)='blob' THEN LOWER(track) ELSE track END) ASC ));

-- @id beets.ls.items_flexattr_filter
-- @src beets/dbcore/db.py:1399-1475; FieldQuery.clause beets/dbcore/query.py:147-151
-- @style no binds
-- @tags hotpath,dynamic
-- @note `beet ls mood:happy`: a flexattr predicate is 'slow' (no SQL), so the whole AndQuery collapses to WHERE 1 and beets filters in Python: full library, fully sorted.
SELECT items.* FROM (SELECT items.* FROM (items) WHERE 1 GROUP BY items.id ) items ORDER BY COALESCE(NULLIF(artist_sort, ''), artist) COLLATE NOCASE ASC, (CASE WHEN TYPEOF(album)='text' THEN LOWER(album) WHEN TYPEOF(album)='blob' THEN LOWER(album) ELSE album END) ASC, (CASE WHEN TYPEOF(disc)='text' THEN LOWER(disc) WHEN TYPEOF(disc)='blob' THEN LOWER(disc) ELSE disc END) ASC, (CASE WHEN TYPEOF(track)='text' THEN LOWER(track) WHEN TYPEOF(track)='blob' THEN LOWER(track) ELSE track END) ASC ;

-- @id beets.ls.items_flexattr_filter_flex
-- @src beets/dbcore/db.py:1399-1475 (flex_sql)
-- @style no binds
-- @tags hotpath,dynamic
-- @note Flex fetch paired with the slow flexattr filter: every item_attributes row whose entity is in the full sorted library (IN over a sorted derived table).
SELECT * FROM item_attributes WHERE entity_id IN (SELECT id FROM (SELECT items.* FROM (SELECT items.* FROM (items) WHERE 1 GROUP BY items.id ) items ORDER BY COALESCE(NULLIF(artist_sort, ''), artist) COLLATE NOCASE ASC, (CASE WHEN TYPEOF(album)='text' THEN LOWER(album) WHEN TYPEOF(album)='blob' THEN LOWER(album) ELSE album END) ASC, (CASE WHEN TYPEOF(disc)='text' THEN LOWER(disc) WHEN TYPEOF(disc)='blob' THEN LOWER(disc) ELSE disc END) ASC, (CASE WHEN TYPEOF(track)='text' THEN LOWER(track) WHEN TYPEOF(track)='blob' THEN LOWER(track) ELSE track END) ASC ));

-- @id beets.ls.items_flexattr_sort
-- @src beets/dbcore/db.py:1399-1475; SlowFieldSort beets/dbcore/sort.py:205-211
-- @style ? positional
-- @tags hotpath,dynamic
-- @note `beet ls artist:beatles play_count-`: sorting by a flexattr is a slow sort, so no ORDER BY is emitted; GROUP BY id over a LIKE filter.
-- @param ?1 '%beatles%'
SELECT items.* FROM (items) WHERE ((artist like ? escape '\')) GROUP BY items.id ;

-- @id beets.ls.items_path_prefix
-- @src beets/dbcore/db.py:1399-1475; PathQuery.col_clause beets/dbcore/query.py:342-359
-- @style ? positional, BLOB binds
-- @tags hotpath,dynamic
-- @note `beet ls path:'The Beatles'` (case-sensitive FS): exact-or-prefix match on a BLOB path; beets joins the two comparisons with || (string concat, '01'/'10' truthy) rather than OR, defeating the index-free OR optimisation.
-- @param ?1 CAST('The Beatles' AS BLOB)
-- @param ?2 12
-- @param ?3 CAST('The Beatles/' AS BLOB)
SELECT items.* FROM (SELECT items.* FROM (items) WHERE ((path = ?) || (substr(path, 1, ?) = ?)) GROUP BY items.id ) items ORDER BY COALESCE(NULLIF(artist_sort, ''), artist) COLLATE NOCASE ASC, (CASE WHEN TYPEOF(album)='text' THEN LOWER(album) WHEN TYPEOF(album)='blob' THEN LOWER(album) ELSE album END) ASC, (CASE WHEN TYPEOF(disc)='text' THEN LOWER(disc) WHEN TYPEOF(disc)='blob' THEN LOWER(disc) ELSE disc END) ASC, (CASE WHEN TYPEOF(track)='text' THEN LOWER(track) WHEN TYPEOF(track)='blob' THEN LOWER(track) ELSE track END) ASC ;

-- @id beets.ls.items_or_groups
-- @src beets/dbcore/db.py:1399-1475; parse_sorted_query beets/dbcore/queryparse.py:205-247
-- @style ? positional
-- @tags dynamic
-- @note `beet ls artist:radiohead , genres:jazz year:1970..1979`: comma splits into an OrQuery of AndQueries.
-- @param ?1 '%radiohead%'
-- @param ?2 '%Jazz%'
-- @param ?3 1970
-- @param ?4 1979
SELECT items.* FROM (SELECT items.* FROM (items) WHERE ((artist like ? escape '\')) or ((items.genres like ? escape '\') and (items.year >= ? AND items.year <= ?)) GROUP BY items.id ) items ORDER BY COALESCE(NULLIF(artist_sort, ''), artist) COLLATE NOCASE ASC, (CASE WHEN TYPEOF(album)='text' THEN LOWER(album) WHEN TYPEOF(album)='blob' THEN LOWER(album) ELSE album END) ASC, (CASE WHEN TYPEOF(disc)='text' THEN LOWER(disc) WHEN TYPEOF(disc)='blob' THEN LOWER(disc) ELSE disc END) ASC, (CASE WHEN TYPEOF(track)='text' THEN LOWER(track) WHEN TYPEOF(track)='blob' THEN LOWER(track) ELSE track END) ASC ;

-- @id beets.ls.items_not_singleton
-- @src beets/dbcore/db.py:1399-1475; NotQuery beets/dbcore/query.py:624-630; SingletonQuery :920
-- @style ? positional
-- @tags dynamic
-- @note `beet ls ^genres:rock singleton:true format:MP3`: NOT LIKE, album_id IS NULL, LIKE.
-- @param ?1 '%Rock%'
-- @param ?2 '%MP3%'
SELECT items.* FROM (SELECT items.* FROM (items) WHERE (not (items.genres like ? escape '\')) and (album_id IS NULL) and (format like ? escape '\') GROUP BY items.id ) items ORDER BY COALESCE(NULLIF(artist_sort, ''), artist) COLLATE NOCASE ASC, (CASE WHEN TYPEOF(album)='text' THEN LOWER(album) WHEN TYPEOF(album)='blob' THEN LOWER(album) ELSE album END) ASC, (CASE WHEN TYPEOF(disc)='text' THEN LOWER(disc) WHEN TYPEOF(disc)='blob' THEN LOWER(disc) ELSE disc END) ASC, (CASE WHEN TYPEOF(track)='text' THEN LOWER(track) WHEN TYPEOF(track)='blob' THEN LOWER(track) ELSE track END) ASC ;

-- @id beets.ls.albums_item_field_join
-- @src beets/dbcore/db.py:1399-1475; Album.relation_join beets/library/models.py:358-368
-- @style ? positional
-- @tags hotpath,dynamic
-- @note `beet ls -a format:FLAC`: album query on an item-only field pulls in albums LEFT JOIN items, dedups with GROUP BY albums.id, then sorts in an outer query.
-- @param ?1 '%FLAC%'
SELECT albums.* FROM (SELECT albums.* FROM (albums LEFT JOIN items ON albums.id = items.album_id) WHERE (format like ? escape '\') GROUP BY albums.id ) albums ORDER BY COALESCE(NULLIF(albumartist_sort, ''), albumartist) COLLATE NOCASE ASC, (CASE WHEN TYPEOF(album)='text' THEN LOWER(album) WHEN TYPEOF(album)='blob' THEN LOWER(album) ELSE album END) ASC ;

-- @id beets.ls.albums_sort_item_field
-- @src beets/dbcore/db.py:1399-1475 (outer relation_join when sorting on the other model); field_sort beets/library/models.py:119-134
-- @style no binds
-- @tags dynamic
-- @note `beet ls -a mtime-`: sorting albums by an item field re-joins items in the outer query (one row per track, as beets emits it) and sorts on a TYPEOF CASE.
SELECT albums.* FROM (SELECT albums.* FROM (albums) WHERE (1) GROUP BY albums.id ) albums LEFT JOIN items ON albums.id = items.album_id ORDER BY (CASE WHEN TYPEOF(items.mtime)='text' THEN LOWER(items.mtime) WHEN TYPEOF(items.mtime)='blob' THEN LOWER(items.mtime) ELSE items.mtime END) DESC ;

-- @id beets.album.items
-- @src beets/dbcore/db.py:1399-1475; Album.items beets/library/models.py:383-395
-- @style ? positional
-- @tags hotpath,dynamic
-- @note album.items(): tracks of one album (MatchQuery album_id) with the default item sort; runs for every album on import, move, write, art fetch.
-- @param ?1 42
SELECT items.* FROM (SELECT items.* FROM (items) WHERE album_id = ? GROUP BY items.id ) items ORDER BY COALESCE(NULLIF(artist_sort, ''), artist) COLLATE NOCASE ASC, (CASE WHEN TYPEOF(album)='text' THEN LOWER(album) WHEN TYPEOF(album)='blob' THEN LOWER(album) ELSE album END) ASC, (CASE WHEN TYPEOF(disc)='text' THEN LOWER(disc) WHEN TYPEOF(disc)='blob' THEN LOWER(disc) ELSE disc END) ASC, (CASE WHEN TYPEOF(track)='text' THEN LOWER(track) WHEN TYPEOF(track)='blob' THEN LOWER(track) ELSE track END) ASC ;

-- @id beets.get_item
-- @src beets/dbcore/db.py:1399-1475; Database._get beets/dbcore/db.py:1478-1480
-- @style ? positional
-- @tags hot-small,hotpath,dynamic
-- @note lib.get_item(id): point lookup through the generic GROUP BY wrapper, no sort.
-- @param ?1 1234
SELECT items.* FROM (items) WHERE id = ? GROUP BY items.id ;

-- @id beets.get_item_flex
-- @src beets/dbcore/db.py:1399-1475 (flex_sql)
-- @style ? positional
-- @tags hot-small,hotpath,dynamic
-- @note Flexattrs for lib.get_item(id): IN over the point-lookup subquery.
-- @param ?1 1236
SELECT * FROM item_attributes WHERE entity_id IN (SELECT id FROM (SELECT items.* FROM (items) WHERE id = ? GROUP BY items.id ));

-- @id beets.get_album
-- @src beets/dbcore/db.py:1399-1475; Library.get_album beets/library/library.py:237-246
-- @style ? positional
-- @tags hot-small,hotpath,dynamic
-- @note item.get_album(): album point lookup, called per item when formatting album-level fields.
-- @param ?1 77
SELECT albums.* FROM (albums) WHERE id = ? GROUP BY albums.id ;

-- @id beets.import.album_duplicates
-- @src beets/dbcore/db.py:1399-1475; duplicates_query beets/library/models.py:180-187; beets/importer/tasks.py:586
-- @style ? positional
-- @tags hotpath,dynamic
-- @note Import-time duplicate check: exact albumartist + album match on albums, default album sort.
-- @param ?1 'Radiohead'
-- @param ?2 'Album 48 Sessions'
SELECT albums.* FROM (SELECT albums.* FROM (albums) WHERE (albums.albumartist = ?) and (albums.album = ?) GROUP BY albums.id ) albums ORDER BY COALESCE(NULLIF(albumartist_sort, ''), albumartist) COLLATE NOCASE ASC, (CASE WHEN TYPEOF(album)='text' THEN LOWER(album) WHEN TYPEOF(album)='blob' THEN LOWER(album) ELSE album END) ASC ;

-- @id beets.store.insert_flex
-- @src beets/dbcore/db.py:616-626
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Model.store() per dirty flexattr; the UNIQUE(entity_id,key) ON CONFLICT REPLACE makes this an upsert (play_count bumps from mpdstats/lastimport).
-- @param ?1 1234
-- @param ?2 'play_count'
-- @param ?3 '17'
INSERT INTO item_attributes (entity_id, key, value) VALUES (?, ?, ?);

-- @id beets.add.insert_default
-- @src beets/dbcore/db.py:670
-- @style no binds
-- @tags hot-small,hotpath
-- @note Model.add(): allocate the row id first, then store() fills it in.
INSERT INTO items DEFAULT VALUES;

-- @id beets.add.store_all_fields
-- @src beets/dbcore/db.py:597-614,672-680
-- @style ? positional, SET list of all non-null fields in sorted order
-- @tags hotpath,dynamic
-- @note Model.add() -> store(): one wide UPDATE of every non-null field on the freshly inserted row (34 columns here), per imported track.
-- @param ?1 1700000123.25
-- @param ?2 'New Album'
-- @param ?3 42
-- @param ?4 'Radiohead'
-- @param ?5 ''
-- @param ?6 'Radiohead'
-- @param ?7 'album'
-- @param ?8 'album'
-- @param ?9 'Radiohead'
-- @param ?10 ''
-- @param ?11 'Radiohead'
-- @param ?12 24
-- @param ?13 1411000
-- @param ?14 ''
-- @param ?15 2
-- @param ?16 0
-- @param ?17 'GB'
-- @param ?18 4
-- @param ?19 1
-- @param ?20 1
-- @param ?21 'FLAC'
-- @param ?22 'Rock'
-- @param ?23 'Label 3'
-- @param ?24 245.3
-- @param ?25 'aaaaaaaa-1111-4000-8000-000000000001'
-- @param ?26 'aaaaaaaa-4444-4000-8000-000000000001'
-- @param ?27 6
-- @param ?28 1700000123.0
-- @param ?29 CAST('Radiohead/New Album/01 New Song.flac' AS BLOB)
-- @param ?30 96000
-- @param ?31 'New Song'
-- @param ?32 1
-- @param ?33 10
-- @param ?34 2026
-- @param ?35 1
UPDATE items SET added=?,album=?,album_id=?,albumartist=?,albumartist_sort=?,albumartists=?,albumtype=?,albumtypes=?,artist=?,artist_sort=?,artists=?,bitdepth=?,bitrate=?,bitrate_mode=?,channels=?,comp=?,country=?,day=?,disc=?,disctotal=?,format=?,genres=?,label=?,length=?,mb_albumid=?,mb_trackid=?,month=?,mtime=?,path=?,samplerate=?,title=?,track=?,tracktotal=?,year=? WHERE id=?;

-- @id beets.bpd.list_albums_by_artist
-- @src beetsplug/bpd/__init__.py:1542-1570
-- @style ? positional
-- @tags hotpath,dynamic
-- @note bpd `list Album <artist>` (MPD clients browse this): DISTINCT + ORDER BY over an exact match.
-- @param ?1 'The Beatles'
SELECT DISTINCT album FROM items WHERE (artist = ?) ORDER BY album;
