-- Navidrome (navidrome/navidrome @ ec2e0a9, GPL-3.0). Go, Masterminds/squirrel builders plus raw SQL strings in
-- persistence/*.go. squirrel renders `?`; sqlRepository.toSQL (persistence/sql_base_repository.go:358) rewrites them
-- to dbx named params {:p0},{:p1}... in order, normalised here to ?N in argument order. Nearly every statement is
-- assembled at runtime from QueryOptions (sort mappings, filter maps, per-user annotation/library joins), so most
-- blocks are one representative instantiation (dynamic). Defaults assumed: PreferSortTags=false,
-- EnableNaturalSorting=false, AlbumPlayCountMode=absolute, Search.Backend=fts. Users: usr1 is admin; usr2 is a
-- regular user who sees libraries 1 and 2 of 3 (so applyLibraryFilter adds its user_library subquery); usr3/usr6 see
-- all libraries (filter skipped). Go time.Time binds as 'YYYY-MM-DD HH:MM:SS.fffffffff+00:00' text (go-sqlite3).

-- @id navidrome.album_list.newest
-- @src persistence/album_repository.go:227-255
-- @style ? -> dbx {:pN}, squirrel; sort/filters from server/filter/filters.go:25 (AlbumsByNewest), library filter persistence/sql_base_repository.go:261
-- @tags hotpath,dynamic
-- @note getAlbumList2 type=newest for a library-restricted user: album LEFT JOIN library and the per-user annotation row, duplicated default missing filter (addDefaultFilters applied twice), user_library IN-subquery, top-10 by created_at.
-- @param ?1 'album'
-- @param ?2 'usr2'
-- @param ?3 0
-- @param ?4 0
-- @param ?5 'usr2'
SELECT album.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       album.average_rating
FROM album
LEFT JOIN library on album.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = album.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
WHERE (missing = ?3 AND missing = ?4)
  AND album.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?5)
ORDER BY album.created_at desc, album.id desc
LIMIT 10;

-- @id navidrome.album_list.recently_played
-- @src persistence/album_repository.go:227-255
-- @style ? -> dbx {:pN}, squirrel; options from server/filter/filters.go:29 (AlbumsByRecent: Gt{play_date: time.Time{}})
-- @tags hotpath,dynamic
-- @note getAlbumList2 type=recent for the admin: filter and sort on the LEFT JOINed annotation's play_date (zero-time literal), so the join drives the plan; top-10.
-- @param ?1 'album'
-- @param ?2 'usr1'
-- @param ?3 0
-- @param ?4 '0001-01-01 00:00:00+00:00'
SELECT album.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       album.average_rating
FROM album
LEFT JOIN library on album.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = album.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
WHERE (missing = ?3 AND play_date > ?4)
ORDER BY play_date desc
LIMIT 10;

-- @id navidrome.album_list.random
-- @src persistence/album_repository.go:227-255
-- @style ? -> dbx {:pN}, squirrel; random sort rewritten by resetSeededRandom (persistence/sql_base_repository.go:320)
-- @tags hotpath,dynamic,modified
-- @note getAlbumList2 type=random: full scan of album ordered by a per-row seeded hash, top-10.
-- @modified The app orders by SEEDEDRAND('album|<xxh3 of user id>', CAST(album.id AS TEXT)), a Go function registered in db/db.go:46; replaced by a core-SQL multiplicative hash of the rowid with a fixed seed so the order is deterministic.
-- @param ?1 'album'
-- @param ?2 'usr3'
-- @param ?3 0
SELECT album.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       album.average_rating
FROM album
LEFT JOIN library on album.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = album.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
WHERE missing = ?3
ORDER BY ((album.rowid * 2654435761 + 40503) % 4294967296) asc
LIMIT 10;

-- @id navidrome.album_list.by_genre
-- @src persistence/album_repository.go:227-255
-- @style ? -> dbx {:pN}, squirrel; genre filter persistence/sql_tags.go:100 (genreFilterDef.ByName), options server/filter/filters.go:179
-- @tags hotpath,dynamic
-- @note getAlbumList2 type=byGenre, second page: IN-subquery over album_tags JOIN tag with a LIKE on the genre name, library IN-subquery, sorted by name with OFFSET.
-- @param ?1 'album'
-- @param ?2 'usr2'
-- @param ?3 0
-- @param ?4 'genre'
-- @param ?5 'Jazz'
-- @param ?6 'usr2'
SELECT album.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       album.average_rating
FROM album
LEFT JOIN library on album.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = album.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
WHERE (missing = ?3 AND album.id IN (SELECT jt.album_id FROM album_tags jt JOIN tag on tag.id = jt.tag_id
                                     WHERE (tag.tag_name = ?4 AND tag.tag_value LIKE ?5)))
  AND album.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?6)
ORDER BY order_album_name asc, order_album_artist_name asc
LIMIT 20 OFFSET 20;

-- @id navidrome.album_list.by_year
-- @src persistence/album_repository.go:227-255
-- @style ? -> dbx {:pN}, squirrel; options server/filter/filters.go:73 (AlbumsByYear, reversed range), sort mapping album_repository.go:115
-- @tags hotpath,dynamic
-- @note getAlbumList2 type=byYear from 2010 to 1995: OR of two year ranges, ORDER BY a coalesce(nullif(...), cast(...)) expression plus release_date and name, descending.
-- @param ?1 'album'
-- @param ?2 'usr6'
-- @param ?3 0
-- @param ?4 1995
-- @param ?5 2010
-- @param ?6 1995
-- @param ?7 2010
SELECT album.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       album.average_rating
FROM album
LEFT JOIN library on album.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = album.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
WHERE (missing = ?3 AND ((min_year >= ?4 AND min_year <= ?5) OR (max_year >= ?6 AND max_year <= ?7)))
ORDER BY coalesce(nullif(original_date,''), cast(max_year as text)) desc, release_date desc, album.name desc
LIMIT 10;

-- @id navidrome.album_list.starred
-- @src persistence/album_repository.go:227-255
-- @style ? -> dbx {:pN}, squirrel; options server/filter/filters.go:221 (ByStarred), sort mapping album_repository.go:118
-- @tags hotpath,dynamic
-- @note getStarred2 / type=starred: equality on the joined annotation's starred flag, sorted by starred, starred_at.
-- @param ?1 'album'
-- @param ?2 'usr6'
-- @param ?3 0
-- @param ?4 1
SELECT album.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       album.average_rating
FROM album
LEFT JOIN library on album.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = album.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
WHERE (missing = ?3 AND starred = ?4)
ORDER BY starred desc, starred_at desc
LIMIT 10;

-- @id navidrome.album_list.by_artist
-- @src persistence/album_repository.go:227-255
-- @style ? -> dbx {:pN}, squirrel; participant filter persistence/sql_participations.go:37, options server/filter/filters.go:49 (AlbumsByArtistID)
-- @tags hotpath,dynamic
-- @note getArtist discography: album.id IN (SELECT album_id FROM album_artists WHERE artist_id = ? AND role IN (?)), library filter, year-expression sort, no LIMIT.
-- @param ?1 'album'
-- @param ?2 'usr2'
-- @param ?3 0
-- @param ?4 'ar00005'
-- @param ?5 'albumartist'
-- @param ?6 'usr2'
SELECT album.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       album.average_rating
FROM album
LEFT JOIN library on album.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = album.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
WHERE (missing = ?3 AND album.id IN (SELECT album_id FROM album_artists WHERE artist_id = ?4 AND role IN (?5)))
  AND album.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?6)
ORDER BY coalesce(nullif(original_date,''), cast(max_year as text)) asc, release_date asc, album.name asc;

-- @id navidrome.artist.index
-- @src persistence/artist_repository.go:327-368
-- @style ? -> dbx {:pN}, squirrel; selectArtist artist_repository.go:207, library join artist_repository.go:191, role filter artist_repository.go:163
-- @tags hotpath,dynamic
-- @note getArtists/getIndexes: artist JOIN library_artist JOIN user_library, JSON_EXTRACT role predicate on the stats JSON, GROUP BY artist with JSON_GROUP_OBJECT(..., JSONB(stats)) per row, annotation LEFT JOIN, sorted by name. Returns every album artist.
-- @param ?1 'usr2'
-- @param ?2 'artist'
-- @param ?3 'usr2'
-- @param ?4 0
-- @param ?5 1
-- @param ?6 2
SELECT artist.*, JSON_GROUP_OBJECT(library_artist.library_id, JSONB(library_artist.stats)) as library_stats_json,
       coalesce(starred, 0) as starred, coalesce(rating, 0) as rating, starred_at, play_date, rated_at,
       coalesce(play_count, 0) as play_count, artist.average_rating
FROM artist
JOIN library_artist on library_artist.artist_id = artist.id
JOIN user_library on user_library.library_id = library_artist.library_id AND user_library.user_id = ?1
LEFT JOIN annotation on (annotation.item_id = artist.id AND annotation.item_type = ?2 AND annotation.user_id = ?3)
WHERE (((JSON_EXTRACT(library_artist.stats, '$.albumartist.m') IS NOT NULL) AND artist.missing = ?4)
       AND library_artist.library_id IN (?5,?6))
GROUP BY artist.id
ORDER BY order_artist_name asc;

-- @id navidrome.artist.list_by_song_count
-- @src persistence/artist_repository.go:746-750
-- @style ? -> dbx {:pN}, squirrel; role-specific sort mapping artist_repository.go:730, REST filters sql_restful.go:20
-- @tags hotpath,dynamic
-- @note Web UI artist list filtered to album artists, sorted by sum(stats->>'albumartist'->>'m') desc: chained ->> JSON extraction inside an aggregate ORDER BY over a grouped join, top-15.
-- @param ?1 'artist'
-- @param ?2 'usr1'
SELECT artist.*, JSON_GROUP_OBJECT(library_artist.library_id, JSONB(library_artist.stats)) as library_stats_json,
       coalesce(starred, 0) as starred, coalesce(rating, 0) as rating, starred_at, play_date, rated_at,
       coalesce(play_count, 0) as play_count, artist.average_rating
FROM artist
JOIN library_artist on library_artist.artist_id = artist.id
LEFT JOIN annotation on (annotation.item_id = artist.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
WHERE ((JSON_EXTRACT(library_artist.stats, '$.albumartist.m') IS NOT NULL))
GROUP BY artist.id
ORDER BY sum(stats->>'albumartist'->>'m') desc
LIMIT 15;

-- @id navidrome.songs.by_album
-- @src persistence/mediafile_repository.go:204-242
-- @style ? -> dbx {:pN}, squirrel; bookmark join sql_bookmarks.go:18 (user id inlined), options server/filter/filters.go:95 (SongsByAlbum)
-- @tags hotpath,dynamic
-- @note getAlbum track list: media_file with library, annotation and bookmark LEFT JOINs plus the library IN-subquery, six-key album sort.
-- @param ?1 'media_file'
-- @param ?2 'usr2'
-- @param ?3 0
-- @param ?4 'al00042'
-- @param ?5 'usr2'
SELECT media_file.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       media_file.average_rating, coalesce(position, 0) as bookmark_position
FROM media_file
LEFT JOIN library on media_file.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = media_file.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
LEFT JOIN bookmark on (bookmark.item_id = media_file.id AND bookmark.user_id = 'usr2')
WHERE (missing = ?3 AND album_id = ?4)
  AND media_file.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?5)
ORDER BY order_album_name asc, album_id asc, disc_number asc, track_number asc, order_artist_name asc, media_file.title asc;

-- @id navidrome.songs.random_by_genre_year
-- @src persistence/mediafile_repository.go:250-266
-- @style ? -> dbx {:pN}, squirrel; filters server/filter/filters.go:111 (SongsByGenreAndYearRange), genre filter sql_tags.go:100
-- @tags hotpath,dynamic,modified
-- @note getRandomSongs?genre=Rock&fromYear=1990&toYear=2005 rowid phase: genre IN-subquery (media_file_tags JOIN tag, LIKE), year range, library filter, shuffled top-20.
-- @modified The app orders by random(); replaced by a core-SQL hash of the rowid with a fixed seed so results are deterministic.
-- @param ?1 0
-- @param ?2 'genre'
-- @param ?3 'Rock'
-- @param ?4 1990
-- @param ?5 2005
-- @param ?6 'usr2'
SELECT media_file.rowid
FROM media_file
WHERE (missing = ?1 AND (media_file.id IN (SELECT jt.media_file_id FROM media_file_tags jt JOIN tag on tag.id = jt.tag_id
                                           WHERE (tag.tag_name = ?2 AND tag.tag_value LIKE ?3))
                         AND year >= ?4 AND year <= ?5))
  AND media_file.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?6)
ORDER BY ((media_file.rowid * 2654435761 + 40503) % 4294967296)
LIMIT 20;

-- @id navidrome.search.media_file_fts
-- @src persistence/sql_search.go:95-130
-- @style ? -> dbx {:pN}, squirrel; FTS strategy persistence/sql_search_fts.go:274 and :359 (buildFTS5Query, column filter, bm25 weights)
-- @tags hotpath,dynamic
-- @note search3 songs for "love song", two-phase: inner FTS5 MATCH with a {column} filter, bm25 with 11 weights, LIMIT 20, numbered with row_number() OVER () and joined back to media_file + library/annotation/bookmark, ordered by that rank.
-- @param ?1 'media_file'
-- @param ?2 'usr2'
-- @param ?3 '{title album artist album_artist sort_title sort_album_name sort_artist_name sort_album_artist_name disc_subtitle search_participants search_normalized} : ((love OR love*) AND (song OR song*))'
-- @param ?4 0
-- @param ?5 'usr2'
-- @param ?6 'usr2'
-- @param ?7 0
SELECT media_file.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       media_file.average_rating, coalesce(position, 0) as bookmark_position
FROM media_file
LEFT JOIN library on media_file.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = media_file.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
LEFT JOIN bookmark on (bookmark.item_id = media_file.id AND bookmark.user_id = 'usr2')
JOIN (SELECT rowid as _rid, row_number() OVER () AS _rn FROM (
        SELECT media_file.rowid FROM media_file
        JOIN media_file_fts ON media_file_fts.rowid = media_file.rowid AND media_file_fts MATCH ?3
        WHERE media_file.missing = ?4
          AND media_file.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?5)
        ORDER BY bm25(media_file_fts, 10.0, 5.0, 3.0, 3.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0), media_file.title
        LIMIT 20)) AS _ranked ON media_file.rowid = _ranked._rid
WHERE media_file.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?6)
  AND media_file.missing = ?7
ORDER BY _ranked._rn;

-- @id navidrome.search.album_fts
-- @src persistence/sql_search.go:95-130
-- @style ? -> dbx {:pN}, squirrel; FTS strategy persistence/sql_search_fts.go:274, album search config album_repository.go:446
-- @tags hotpath,dynamic
-- @note search3 albums for "midnight" (admin): single-token FTS5 prefix query over 8 columns, bm25 then album.name, top-20 rowids joined back in rank order.
-- @param ?1 'album'
-- @param ?2 'usr1'
-- @param ?3 '{name sort_album_name album_artist search_participants discs catalog_num album_version search_normalized} : ((midnight OR midnight*))'
-- @param ?4 0
-- @param ?5 0
SELECT album.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       album.average_rating
FROM album
LEFT JOIN library on album.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = album.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
JOIN (SELECT rowid as _rid, row_number() OVER () AS _rn FROM (
        SELECT album.rowid FROM album
        JOIN album_fts ON album_fts.rowid = album.rowid AND album_fts MATCH ?3
        WHERE album.missing = ?4
        ORDER BY bm25(album_fts, 10.0, 1.0, 3.0, 2.0, 1.0, 1.0, 1.0, 1.0), album.name
        LIMIT 20)) AS _ranked ON album.rowid = _ranked._rid
WHERE album.missing = ?5
ORDER BY _ranked._rn;

-- @id navidrome.search.artist_fts
-- @src persistence/artist_repository.go:652-671
-- @style ? -> dbx {:pN}, squirrel; artist search scope artist_repository.go:618-650, two-phase hydrate sql_search.go:117
-- @tags hotpath,dynamic
-- @note search3 artists for "the ghost" as a restricted user: FTS5 MATCH plus a correlated EXISTS ... LIMIT 1 library scope in the rowid phase, then the grouped artist/library_artist/user_library join with JSON_GROUP_OBJECT, ordered by FTS rank.
-- @param ?1 'usr2'
-- @param ?2 'artist'
-- @param ?3 'usr2'
-- @param ?4 '{name sort_artist_name search_normalized} : ((the OR the*) AND (ghost OR ghost*))'
-- @param ?5 0
-- @param ?6 1
-- @param ?7 2
-- @param ?8 0
SELECT artist.*, JSON_GROUP_OBJECT(library_artist.library_id, JSONB(library_artist.stats)) as library_stats_json,
       coalesce(starred, 0) as starred, coalesce(rating, 0) as rating, starred_at, play_date, rated_at,
       coalesce(play_count, 0) as play_count, artist.average_rating
FROM artist
JOIN library_artist on library_artist.artist_id = artist.id
JOIN user_library on user_library.library_id = library_artist.library_id AND user_library.user_id = ?1
LEFT JOIN annotation on (annotation.item_id = artist.id AND annotation.item_type = ?2 AND annotation.user_id = ?3)
JOIN (SELECT rowid as _rid, row_number() OVER () AS _rn FROM (
        SELECT artist.rowid FROM artist
        JOIN artist_fts ON artist_fts.rowid = artist.rowid AND artist_fts MATCH ?4
        WHERE artist.missing = ?5
          AND EXISTS (SELECT 1 FROM library_artist WHERE (library_artist.artist_id = artist.id AND library_artist.library_id IN (?6,?7)) LIMIT 1)
        ORDER BY bm25(artist_fts, 10.0, 1.0, 10.0), artist.name
        LIMIT 20)) AS _ranked ON artist.rowid = _ranked._rid
WHERE artist.missing = ?8
GROUP BY artist.id
ORDER BY _ranked._rn;

-- @id navidrome.search.media_file_like_cjk
-- @src persistence/sql_search_like.go:24-28
-- @style ? -> dbx {:pN}, squirrel; LIKE strategy chosen for CJK input (sql_search.go:45), predicate sql_search_like.go:85
-- @tags hotpath,dynamic
-- @note search3 for a CJK query (FTS5's unicode61 tokenizer can't split it): per-word OR of four %LIKE% columns over the full join, sorted by title, top-20.
-- @param ?1 'media_file'
-- @param ?2 'usr2'
-- @param ?3 'usr2'
-- @param ?4 0
-- @param ?5 '%恋の歌%'
-- @param ?6 '%恋の歌%'
-- @param ?7 '%恋の歌%'
-- @param ?8 '%恋の歌%'
SELECT media_file.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       media_file.average_rating, coalesce(position, 0) as bookmark_position
FROM media_file
LEFT JOIN library on media_file.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = media_file.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
LEFT JOIN bookmark on (bookmark.item_id = media_file.id AND bookmark.user_id = 'usr2')
WHERE media_file.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?3)
  AND media_file.missing = ?4
  AND ((media_file.title LIKE ?5 OR media_file.album LIKE ?6 OR media_file.artist LIKE ?7 OR media_file.album_artist LIKE ?8))
ORDER BY title
LIMIT 20;

-- @id navidrome.smart_playlist.refresh_tag_annotation
-- @src persistence/smart_playlist_repository.go:58-66
-- @style ? -> dbx {:pN}, squirrel; criteria -> SQL persistence/criteria_sql.go:133 (periodExpr, annotationCond, tagCondGroup merge at :604), query shape smart_playlist_repository.go:181
-- @tags dynamic,batch
-- @note Smart playlist {"all":[inTheLast lastPlayed 90, gt rating 3, any[contains genre Rock, contains genre Jazz]], sort playCount desc, limit 100}: INSERT ... SELECT with row_number() OVER (ORDER BY ...), annotation LEFT JOIN, merged EXISTS over json_tree(tags,'$.genre') with OR'd LIKEs.
-- @param ?1 'usr2'
-- @param ?2 'usr2'
-- @param ?3 '2026-07-29'
-- @param ?4 3
-- @param ?5 '%Rock%'
-- @param ?6 '%Jazz%'
INSERT INTO playlist_tracks (id,playlist_id,media_file_id)
SELECT row_number() over (order by COALESCE(annotation.play_count, 0) desc) as id, 'sp0001' as playlist_id,
       media_file.id as media_file_id
FROM media_file
LEFT JOIN annotation on (annotation.item_id = media_file.id AND annotation.item_type = 'media_file' AND annotation.user_id = ?1)
WHERE media_file.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?2)
  AND (annotation.play_date > ?3 AND annotation.rating > ?4
       AND (exists (select 1 from json_tree(media_file.tags, '$.genre') where key='value' and (value LIKE ?5 OR value LIKE ?6))))
ORDER BY COALESCE(annotation.play_count, 0) desc
LIMIT 100 OFFSET 0;

-- @id navidrome.smart_playlist.refresh_album_rating
-- @src persistence/smart_playlist_repository.go:58-66
-- @style ? -> dbx {:pN}, squirrel; criteria_sql.go:347 (inList), :293 (rangeExpr), :837 (applyJoins)
-- @tags dynamic,batch
-- @note Smart playlist {"all":[gt albumRating 2, notInPlaylist pl0001, inTheRange year 1990-1999], sort "-albumRating,title", limit 200}: second annotation alias joined on album_id, NOT IN (playlist_tracks LEFT JOIN playlist with owner/public check), window numbering over a COALESCE sort.
-- @param ?1 'usr2'
-- @param ?2 'usr2'
-- @param ?3 'usr2'
-- @param ?4 2
-- @param ?5 'pl0001'
-- @param ?6 1
-- @param ?7 'usr2'
-- @param ?8 1990
-- @param ?9 1999
INSERT INTO playlist_tracks (id,playlist_id,media_file_id)
SELECT row_number() over (order by COALESCE(album_annotation.rating, 0) desc, media_file.title asc) as id,
       'sp0002' as playlist_id, media_file.id as media_file_id
FROM media_file
LEFT JOIN annotation on (annotation.item_id = media_file.id AND annotation.item_type = 'media_file' AND annotation.user_id = ?1)
LEFT JOIN annotation AS album_annotation ON (album_annotation.item_id = media_file.album_id AND album_annotation.item_type = 'album' AND album_annotation.user_id = ?2)
WHERE media_file.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?3)
  AND (album_annotation.rating > ?4
       AND media_file.id NOT IN (SELECT media_file_id FROM playlist_tracks pl LEFT JOIN playlist on pl.playlist_id = playlist.id
                                 WHERE (pl.playlist_id = ?5 AND (playlist.public = ?6 OR playlist.owner_id = ?7)))
       AND (media_file.year >= ?8 AND media_file.year <= ?9))
ORDER BY COALESCE(album_annotation.rating, 0) desc, media_file.title asc
LIMIT 200 OFFSET 0;

-- @id navidrome.playlist.load_tracks
-- @src persistence/playlist_repository.go:373-408
-- @style ? -> dbx {:pN}, squirrel; caller GetWithTracks playlist_repository.go:152 (user id inlined in the annotation join)
-- @tags hotpath,dynamic
-- @note getPlaylist: playlist_tracks JOIN media_file JOIN library with the annotation LEFT JOIN on media_file_id, library filter on the joined alias f, ordered by position.
-- @param ?1 0
-- @param ?2 'usr2'
-- @param ?3 'pl0007'
SELECT coalesce(starred, 0) as starred, starred_at, coalesce(play_count, 0) as play_count, play_date,
       coalesce(rating, 0) as rating, rated_at, f.*, playlist_tracks.*, library.path as library_path,
       library.name as library_name
FROM playlist_tracks
LEFT JOIN annotation on (annotation.item_id = media_file_id AND annotation.item_type = 'media_file' AND annotation.user_id = 'usr2')
JOIN media_file f on f.id = media_file_id
JOIN library on f.library_id = library.id
WHERE missing = ?1
  AND f.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?2)
  AND playlist_id = ?3
ORDER BY playlist_tracks.id;

-- @id navidrome.scan.album_refresh_play_counts
-- @src persistence/album_repository.go:411-428
-- @style raw SQL (squirrel Expr), no params
-- @tags batch
-- @note Post-scan album play counts: CTE aggregating every track annotation per (user, album), then INSERT ... SELECT ... ON CONFLICT DO UPDATE into annotation.
WITH play_counts AS (
    select user_id, album_id, sum(play_count) as total_play_count, max(play_date) as last_play_date
    from media_file
             join annotation on item_id = media_file.id
    group by user_id, album_id
)
insert into annotation (user_id, item_id, item_type, play_count, play_date)
select user_id, album_id, 'album', total_play_count, last_play_date
from play_counts
where total_play_count > 0
on conflict (user_id, item_id, item_type) do update
    set play_count = excluded.play_count,
        play_date  = excluded.play_date;

-- @id navidrome.scan.artist_refresh_play_counts
-- @src persistence/artist_repository.go:441-460
-- @style raw SQL (squirrel Expr), no params
-- @tags batch
-- @note Post-scan artist play counts: annotation join fanned out through json_tree(participants, '$.artist'), grouped on the tree's atom, upserted into annotation.
with play_counts as (
    select user_id, atom as artist_id, sum(play_count) as total_play_count, max(play_date) as last_play_date
    from media_file
    join annotation on item_id = media_file.id
    left join json_tree(participants, '$.artist') as jt
    where atom is not null and key = 'id'
    group by user_id, atom
)
insert into annotation (user_id, item_id, item_type, play_count, play_date)
select user_id, artist_id, 'artist', total_play_count, last_play_date
from play_counts
where total_play_count > 0
on conflict (user_id, item_id, item_type) do update
    set play_count = excluded.play_count,
        play_date  = excluded.play_date;

-- @id navidrome.scan.artist_refresh_stats
-- @src persistence/artist_repository.go:494-587
-- @style ? positional, IN list built per batch (ROLE_IDS_PLACEHOLDER replaced 4 times, up to 1000 ids)
-- @tags batch,dynamic
-- @note Artist stats refresh for 4 touched artists: five CTEs (three COUNT(DISTINCT) aggregations, UNION ALL, json_group_object of json_object) feeding a correlated UPDATE of library_artist.stats.
-- @param ?1 'ar00001'
-- @param ?2 'ar00002'
-- @param ?3 'ar00005'
-- @param ?4 'ar00008'
-- @param ?5 'ar00001'
-- @param ?6 'ar00002'
-- @param ?7 'ar00005'
-- @param ?8 'ar00008'
-- @param ?9 'ar00001'
-- @param ?10 'ar00002'
-- @param ?11 'ar00005'
-- @param ?12 'ar00008'
-- @param ?13 'ar00001'
-- @param ?14 'ar00002'
-- @param ?15 'ar00005'
-- @param ?16 'ar00008'
WITH artist_role_counters AS (
    SELECT mfa.artist_id, mf.library_id, mfa.role, count(DISTINCT mf.album_id) AS album_count,
           count(DISTINCT mf.id) AS count, sum(mf.size) AS size
    FROM media_file_artists mfa
    JOIN media_file mf ON mfa.media_file_id = mf.id
    WHERE mfa.artist_id IN (?1,?2,?3,?4)
    GROUP BY mfa.artist_id, mf.library_id, mfa.role
),
artist_total_counters AS (
    SELECT mfa.artist_id, mf.library_id, 'total' AS role, count(DISTINCT mf.album_id) AS album_count,
           count(DISTINCT mf.id) AS count, sum(mf.size) AS size
    FROM media_file_artists mfa
    JOIN media_file mf ON mfa.media_file_id = mf.id
    WHERE mfa.artist_id IN (?5,?6,?7,?8)
    GROUP BY mfa.artist_id, mf.library_id
),
artist_participant_counter AS (
    SELECT mfa.artist_id, mf.library_id, 'maincredit' AS role, count(DISTINCT mf.album_id) AS album_count,
           count(DISTINCT mf.id) AS count, sum(mf.size) AS size
    FROM media_file_artists mfa
    JOIN media_file mf ON mfa.media_file_id = mf.id
    WHERE mfa.artist_id IN (?9,?10,?11,?12)
    AND mfa.role IN ('albumartist', 'artist')
    GROUP BY mfa.artist_id, mf.library_id
),
combined_counters AS (
    SELECT artist_id, library_id, role, album_count, count, size FROM artist_role_counters
    UNION ALL
    SELECT artist_id, library_id, role, album_count, count, size FROM artist_total_counters
    UNION ALL
    SELECT artist_id, library_id, role, album_count, count, size FROM artist_participant_counter
),
library_artist_counters AS (
    SELECT artist_id, library_id,
           json_group_object(role, json_object('a', album_count, 'm', count, 's', size)) AS counters
    FROM combined_counters
    GROUP BY artist_id, library_id
)
UPDATE library_artist
SET stats = coalesce((SELECT counters FROM library_artist_counters lac
                     WHERE lac.artist_id = library_artist.artist_id
                     AND lac.library_id = library_artist.library_id), '{}')
WHERE library_artist.artist_id IN (?13,?14,?15,?16);

-- @id navidrome.scan.tag_update_counts
-- @src persistence/tag_repository.go:54-75
-- @style raw SQL via fmt.Sprintf(template, table), no params; album instantiation
-- @tags batch,dynamic
-- @note Per-library genre counts: every album's tags JSON walked with json_tree('$.genre'), joined to tag, COUNT(DISTINCT) grouped by (tag, library), upserted into library_tag.
INSERT INTO library_tag (tag_id, library_id, album_count)
SELECT jt.value as tag_id, album.library_id, count(distinct album.id) as album_count
FROM album
JOIN json_tree(album.tags, '$.genre') as jt ON jt.atom IS NOT NULL AND jt.key = 'id'
JOIN tag ON tag.id = jt.value
GROUP BY jt.value, album.library_id
ON CONFLICT (tag_id, library_id)
DO UPDATE SET album_count = excluded.album_count;

-- @id navidrome.scan.update_participants
-- @src persistence/sql_participations.go:109-123
-- @style ? positional, table name via fmt.Sprintf (media_file instantiation); arg 2 is a JSON array marshalled in Go
-- @tags batch,dynamic
-- @note Scanner track upsert, participants step: INSERT ... SELECT over json_each(?) JOIN artist (drops unknown ids) ... ON CONFLICT DO NOTHING.
-- @param ?1 'mf000123'
-- @param ?2 '[{"artist_id":"ar00005","role":"albumartist"},{"artist_id":"ar00005","role":"artist"},{"artist_id":"ar00777","role":"composer"},{"artist_id":"ar00031","role":"producer"},{"artist_id":"ar99999","role":"mixer","sub_role":"remix"}]'
INSERT INTO media_file_artists (media_file_id, artist_id, role, sub_role)
SELECT ?1,
       json_extract(value, '$.artist_id') as artist_id,
       json_extract(value, '$.role') as role,
       COALESCE(json_extract(value, '$.sub_role'), '') as sub_role
FROM json_each(?2)
JOIN artist ON artist.id = json_extract(value, '$.artist_id')
ON CONFLICT (artist_id, media_file_id, role, sub_role) DO NOTHING;

-- @id navidrome.genre.list
-- @src persistence/genre_repository.go:22-31
-- @style ? -> dbx {:pN}, squirrel; base tag select persistence/sql_tags.go:180, caller server/subsonic/browsing.go:267
-- @tags hotpath,dynamic
-- @note getGenres: tag LEFT JOIN library_tag JOIN user_library, SUM aggregates grouped per tag, ordered by the aggregate aliases.
-- @param ?1 'usr2'
-- @param ?2 'genre'
SELECT tag.id, tag.tag_name, tag.tag_value, COALESCE(SUM(library_tag.album_count), 0) as album_count,
       COALESCE(SUM(library_tag.media_file_count), 0) as song_count, tag.tag_value as name
FROM tag
LEFT JOIN library_tag on library_tag.tag_id = tag.id
JOIN user_library on user_library.library_id = library_tag.library_id AND user_library.user_id = ?1
WHERE tag.tag_name = ?2
GROUP BY tag.id, tag.tag_name, tag.tag_value
ORDER BY song_count desc, album_count desc, name asc;

-- @id navidrome.user.find_by_username
-- @src persistence/user_repository.go:201-209
-- @style ? -> dbx {:pN}, squirrel; selectUserWithLibraries user_repository.go:72
-- @tags hot-small,hotpath,dynamic
-- @note Subsonic auth on every request: user by name COLLATE NOCASE, LEFT JOIN user_library/library, json_group_array(json_object(...)) FILTER (WHERE ...) grouped per user.
-- @param ?1 'User2'
SELECT user.*, COALESCE(json_group_array(json_object(
         'id', library.id,
         'name', library.name,
         'path', library.path,
         'remote_path', library.remote_path,
         'last_scan_at', library.last_scan_at,
         'last_scan_started_at', library.last_scan_started_at,
         'full_scan_in_progress', library.full_scan_in_progress,
         'updated_at', library.updated_at,
         'created_at', library.created_at
       )) FILTER (WHERE library.id IS NOT NULL), '[]') AS libraries_json
FROM user
LEFT JOIN user_library ul ON user.id = ul.user_id
LEFT JOIN library ON ul.library_id = library.id
WHERE user.user_name = ?1 COLLATE NOCASE
GROUP BY user.id;

-- @id navidrome.album.get
-- @src persistence/album_repository.go:234-243
-- @style ? -> dbx {:pN}, squirrel; via GetAll + selectAlbum (album_repository.go:227)
-- @tags hot-small,hotpath,dynamic
-- @note Album by id (getAlbum, cover art, scrobble paths): primary-key lookup with library and annotation LEFT JOINs and the library IN-subquery.
-- @param ?1 'album'
-- @param ?2 'usr2'
-- @param ?3 'al00042'
-- @param ?4 'usr2'
SELECT album.*, library.path as library_path, library.name as library_name, coalesce(starred, 0) as starred,
       coalesce(rating, 0) as rating, starred_at, play_date, rated_at, coalesce(play_count, 0) as play_count,
       album.average_rating
FROM album
LEFT JOIN library on album.library_id = library.id
LEFT JOIN annotation on (annotation.item_id = album.id AND annotation.item_type = ?1 AND annotation.user_id = ?2)
WHERE album.id = ?3
  AND album.library_id IN (SELECT ul.library_id FROM user_library ul WHERE ul.user_id = ?4);

-- @id navidrome.artwork.hydrate_items
-- @src persistence/artwork_repository.go:159-182
-- @style ? -> dbx {:pN}, squirrel; called for every album/track/artist page by artwork_hydration.go:58
-- @tags hot-small,hotpath,dynamic
-- @note Batched artwork metadata for one page of albums: item_artwork PK IN-list LEFT JOIN artwork.
-- @param ?1 'al'
-- @param ?2 'primary'
-- @param ?3 'al00041'
-- @param ?4 'al00042'
-- @param ?5 'al00043'
-- @param ?6 'al00044'
-- @param ?7 'al00045'
-- @param ?8 'al00046'
-- @param ?9 'al00047'
-- @param ?10 'al00048'
-- @param ?11 'al00049'
-- @param ?12 'al00050'
SELECT ia.item_id, ia.hash, COALESCE(a.blur_hash, '') as blur_hash, COALESCE(a.thumb_hash, '') as thumb_hash,
       COALESCE(a.dominant_color, '') as dominant_color, COALESCE(a.width, 0) as width, COALESCE(a.height, 0) as height
FROM item_artwork ia
LEFT JOIN artwork a ON a.hash = ia.hash
WHERE (ia.item_kind = ?1 AND ia.image_type = ?2 AND ia.item_id IN (?3,?4,?5,?6,?7,?8,?9,?10,?11,?12));

-- @id navidrome.annotation.inc_play_count
-- @src persistence/sql_annotations.go:162-183
-- @style ? -> dbx {:pN}, squirrel Update; the INSERT fallback runs only when no row matched
-- @tags hot-small,hotpath,dynamic
-- @note Scrobble: bump play_count and keep the max play_date for one (user, item_type, item_id) annotation row.
-- @param ?1 '2026-10-27 18:04:05.123456789+00:00'
-- @param ?2 'usr1'
-- @param ?3 'media_file'
-- @param ?4 'mf000001'
UPDATE annotation SET play_count = play_count+1, play_date = max(ifnull(play_date,''),?1)
WHERE (annotation.user_id = ?2 AND annotation.item_type = ?3 AND annotation.item_id IN (?4));

-- @id navidrome.scrobble.record
-- @src persistence/scrobble_repository.go:46-57
-- @style ? -> dbx {:pN}, squirrel Insert SetMap (columns sorted by name)
-- @tags hot-small,hotpath
-- @note Scrobble history insert, one per played track.
-- @param ?1 'mf000123'
-- @param ?2 1793110000
-- @param ?3 'usr2'
INSERT INTO scrobbles (media_file_id,submission_time,user_id) VALUES (?1,?2,?3);

-- @id navidrome.user.update_last_access
-- @src persistence/user_repository.go:226-231
-- @style ? -> dbx {:pN}, squirrel Update
-- @tags hot-small,hotpath
-- @note Touch on authenticated requests: single-row UPDATE by primary key.
-- @param ?1 '2026-10-27 18:04:05.123456789+00:00'
-- @param ?2 'usr2'
UPDATE user SET last_access_at = ?1 WHERE id = ?2;
