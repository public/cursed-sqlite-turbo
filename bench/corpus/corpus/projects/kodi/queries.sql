-- Kodi (xbmc/xbmc @ 3294b709ca23b3fd67a7784951246fefecc1dd34, GPL-2.0-or-later). Each statement is quoted
-- individually with attribution. Kodi builds SQL text with PrepareSQL (printf-style %i/%s/%u/%f/%02d, quoting
-- strings itself); column numbers (c%02d), media type names and enum values are resolved to the literals Kodi
-- produces, and values that vary per call (ids, paths, search text, timestamps) become ?N bind parameters.
-- Library list pages are assembled at runtime from CVideoDbUrl/CMusicDbUrl options by GetFilter, Filter::Append*
-- and ExistsSubQuery (xbmc/dbwrappers/Database.cpp); those are one representative instantiation, tagged dynamic.
-- Video and music queries share one database (see schema.sql).

-- ============================================================ video: hot small statements

-- @id kodi.video.path_id
-- @src xbmc/video/VideoDatabase.cpp:226
-- @style PrepareSQL '%s' inlined; normalised to ?1
-- @tags hot-small,hotpath
-- @note GetPathId: runs for every file the player opens or the scanner sees (ix_path lookup).
-- @param ?1 'smb://nas/movies/00042/'
select idPath from path where strPath=?1;

-- @id kodi.video.file_id
-- @src xbmc/video/VideoDatabase.cpp:989
-- @style PrepareSQL '%s'/%i inlined; normalised to ?1/?2
-- @tags hot-small,hotpath
-- @note GetFileId: second half of every path -> idFile resolution (ix_files on idPath, strFilename).
-- @param ?1 'movie-00042.mkv'
-- @param ?2 42
select idFile from files where strFileName=?1 and idPath=?2;

-- @id kodi.video.art_for_item
-- @src xbmc/dbwrappers/Database.cpp:984
-- @style PrepareSQL %i/'%s'; id normalised to ?1, media type kept literal
-- @tags hot-small,hotpath
-- @note CDatabase::GetArtForItem: per list item when the thumb loader fills artwork.
-- @param ?1 42
SELECT type,url FROM art WHERE media_id=?1 AND media_type='movie';

-- @id kodi.video.set_playcount
-- @src xbmc/video/VideoDatabase.cpp:6711
-- @style PrepareSQL %i/'%s'/%i; normalised to ?1..?3
-- @tags hot-small,hotpath
-- @note SetPlayCount: marks a file watched at the end of playback or from the context menu.
-- @param ?1 1
-- @param ?2 '2026-10-28 20:15:00'
-- @param ?3 42
update files set playCount=?1,lastPlayed=?2 where idFile=?3;

-- @id kodi.video.add_bookmark
-- @src xbmc/video/VideoDatabase.cpp:4086-4091
-- @style PrepareSQL %i/%f/'%s'; normalised to ?1..?7
-- @tags hot-small,hotpath
-- @note AddBookMarkToFile: saves the resume point when playback stops (no existing bookmark for the file).
-- @param ?1 43
-- @param ?2 1834.5
-- @param ?3 7012.0
-- @param ?4 ''
-- @param ?5 'VideoPlayer'
-- @param ?6 '<state><audiostream>0</audiostream></state>'
-- @param ?7 1
insert into bookmark (idBookmark, idFile, timeInSeconds, totalTimeInSeconds, thumbNailImage, player, playerState, type) values(NULL,?1,?2,?3,?4,?5,?6, ?7);

-- ============================================================ video: library pages

-- @id kodi.video.cast
-- @src xbmc/video/VideoDatabase.cpp:5490-5502
-- @style PrepareSQL %i/'%s'; id normalised to ?1
-- @tags hotpath
-- @note GetCast: cast list on every movie info dialog; link join + LEFT JOIN art with a 3-column match, ordered by cast_order.
-- @param ?1 42
SELECT actor.name,  actor_link.role,  actor_link.cast_order,  actor.art_urls,  art.url
FROM actor_link
  JOIN actor ON actor_link.actor_id=actor.actor_id
  LEFT JOIN art ON art.media_id=actor.actor_id AND art.media_type='actor' AND art.type='thumb'
WHERE actor_link.media_id=?1 AND actor_link.media_type='movie'ORDER BY actor_link.cast_order;

-- @id kodi.video.movie_info
-- @src xbmc/video/VideoDatabase.cpp:2205
-- @style PrepareSQL %i; normalised to ?1
-- @tags hotpath
-- @note GetMovieInfo: one movie through movie_view (8 joins incl. videoversion/videoversiontype, two correlated EXISTS, CASE isDefaultVersion filtered on).
-- @param ?1 42
SELECT * FROM movie_view WHERE idMovie = ?1 AND isDefaultVersion = 1;

-- @id kodi.video.movies.by_genre
-- @src xbmc/video/VideoDatabase.cpp:8279-8299
-- @style dynamic: GetMoviesByWhere + GetFilter (VideoDatabase.cpp:12810 AppendIdLinkFilter, :12891 isDefaultVersion), Filter::AppendWhere parenthesises
-- @tags hotpath,dynamic
-- @note Movies > Genres > Drama: the whole movie_view joined to genre_link; Kodi sorts in C++, so no ORDER BY.
-- @param ?1 7
select * from movie_view JOIN genre_link ON genre_link.media_id=movie_view.idMovie AND genre_link.media_type='movie' WHERE (genre_link.genre_id = ?1) AND (isDefaultVersion = 1);

-- @id kodi.video.movies.recently_added
-- @src xbmc/video/VideoDatabase.cpp:8676-8682
-- @style dynamic: GetRecentlyAddedMoviesNav sets filter.order/limit, GetMoviesByWhere (:8279) builds the text; limit = advancedsettings default 25
-- @tags hotpath,dynamic
-- @note Home screen "Recently added movies" widget: top-N over movie_view by files.dateAdded.
select * from movie_view WHERE isDefaultVersion = 1 ORDER BY dateAdded desc, idMovie desc LIMIT 25;

-- @id kodi.video.nav.genres
-- @src xbmc/video/VideoDatabase.cpp:6941-7060
-- @style dynamic: GetNavCommon (unlocked profile, MOVIES) + BuildSQL/GetFilter adds isDefaultVersion
-- @tags hotpath,dynamic
-- @note Movies > Genres node: genre -> genre_link -> movie_view -> files, GROUP BY with count(1)/count(playCount) to flag fully watched genres.
SELECT genre.genre_id, genre.name, count(1), count(files.playCount) FROM genre JOIN genre_link ON genre.genre_id = genre_link.genre_id JOIN movie_view ON genre_link.media_id = movie_view.idMovie AND genre_link.media_type='movie' JOIN files ON files.idFile = movie_view.idFile WHERE isDefaultVersion = 1 GROUP BY genre.genre_id;

-- @id kodi.video.nav.actors
-- @src xbmc/video/VideoDatabase.cpp:7409-7550
-- @style dynamic: GetPeopleNav (unlocked profile, MOVIES) + GetFilter isDefaultVersion
-- @tags hotpath,dynamic
-- @note Movies > Actors node: 20k actors x 40k links through movie_view, GROUP BY actor with watched counts.
SELECT actor.actor_id, actor.name, actor.art_urls, count(1), count(files.playCount) FROM actor JOIN actor_link on actor.actor_id = actor_link.actor_id JOIN movie_view on actor_link.media_id = movie_view.idMovie AND actor_link.media_type='movie' JOIN files ON files.idFile=movie_view.idFile WHERE isDefaultVersion = 1 GROUP BY actor.actor_id;

-- @id kodi.video.search.movies
-- @src xbmc/video/VideoDatabase.cpp:9773-9779
-- @style PrepareSQL '%%%s%%' inlined three times; normalised to ?1 = '%text%'
-- @tags hotpath
-- @note GetMoviesByName (global search): double LIKE '%..%' over title/original title plus a LIKE in the result set.
-- @param ?1 '%star%'
SELECT movie.idMovie,movie.c00, movie.c16, movie.c00 LIKE ?1, movie.idSet FROM movie WHERE movie.c00 like ?1 OR movie.c16 LIKE ?1;

-- @id kodi.video.tvshows.list
-- @src xbmc/video/VideoDatabase.cpp:8398-8448
-- @style dynamic: GetTvShowsNav adds the hide-empty-shows where (setting default), GetTvShowsByWhere builds the text
-- @tags hotpath,dynamic
-- @note TV shows title list: tvshow_view = tvshow + MIN(idPath) view + tvshowcounts (aggregate over all 15k episodes/files/bookmarks) + rating + uniqueid.
SELECT * FROM tvshow_view WHERE totalCount IS NOT NULL AND totalCount > 0;

-- @id kodi.video.tvshows.by_id
-- @src xbmc/video/VideoDatabase.cpp:2250
-- @style PrepareSQL %i; normalised to ?1
-- @tags hotpath
-- @note GetTvShowInfo: one show through tvshow_view; whether idShow=? reaches inside the two GROUP BY views decides the cost.
-- @param ?1 5
SELECT * FROM tvshow_view WHERE idShow=?1 GROUP BY idShow;

-- @id kodi.video.tvshows.in_progress
-- @src xbmc/video/VideoDatabase.cpp:8700-8708
-- @style dynamic: GetInProgressTvShowsNav filter (order c%02d -> c00) through GetTvShowsByWhere (:8436)
-- @tags hotpath,dynamic
-- @note Home screen "In progress TV shows" widget: predicates on the aggregate columns of tvshowcounts, sorted by title.
SELECT * FROM tvshow_view WHERE totalCount != watchedCount AND (inProgressCount > 0 OR watchedCount != 0) ORDER BY c00;

-- @id kodi.video.seasons.for_show
-- @src xbmc/video/VideoDatabase.cpp:7924-7935
-- @style dynamic: GetFilter seasons branch (VideoDatabase.cpp:12930) appends season_view.idShow = %i
-- @tags hotpath,dynamic
-- @note Seasons of a show: season_view groups seasons x tvshow_view (itself over two aggregate views) x episode x files x bookmark by 13 columns.
-- @param ?1 5
SELECT * FROM season_view WHERE season_view.idShow = ?1;

-- @id kodi.video.episodes.for_season
-- @src xbmc/video/VideoDatabase.cpp:8565-8580
-- @style dynamic: GetFilter episodes branch (VideoDatabase.cpp:12960-12996), season > 0 case with specials sorted into the season
-- @tags hotpath,dynamic
-- @note Episodes of season 2: episode_view (6 joins) with an OR over season / sort-season columns stored as varchar.
-- @param ?1 5
-- @param ?2 2
select * from episode_view WHERE (episode_view.idShow = ?1) AND ((episode_view.c12 = ?2 or (episode_view.c12 = 0 and (episode_view.c15 = 0 or episode_view.c15 = ?2))));

-- @id kodi.video.delete_movie
-- @src xbmc/video/VideoDatabase.cpp:4291
-- @style PrepareSQL %i; normalised to ?1
-- @note DeleteMovie (library clean / remove from library): one row delete fires delete_movie's 12 DELETEs, and each tag_link delete fires delete_tag's NOT IN check.
-- @param ?1 44
DELETE FROM movie WHERE idMovie=?1;

-- ============================================================ music: hot small statements

-- @id kodi.music.song_id_from_path
-- @src xbmc/music/MusicDatabase.cpp:11539-11541
-- @style PrepareSQL '%s' x2; normalised to ?1/?2
-- @tags hot-small,hotpath
-- @note GetSongIDFromPath: resolves the playing file to a song on every track start.
-- @param ?1 '03-01233.flac'
-- @param ?2 'smb://nas/music/00124/'
SELECT idSong FROM song JOIN path ON song.idPath = path.idPath WHERE song.strFileName=?1 AND path.strPath=?2;

-- @id kodi.music.increment_playcount
-- @src xbmc/music/MusicDatabase.cpp:4098-4100
-- @style PrepareSQL '%s'/%i; normalised to ?1/?2
-- @tags hot-small,hotpath
-- @note IncrementPlayCount: every finished track; tgrUpdateSong's WHEN clause is evaluated per row.
-- @param ?1 '2026-10-28 20:15:00'
-- @param ?2 1233
UPDATE song SET iTimesPlayed = iTimesPlayed+1, lastplayed =?1 WHERE idSong=?2;

-- ============================================================ music: library pages

-- @id kodi.music.top100.songs
-- @src xbmc/music/MusicDatabase.cpp:3628-3631
-- @style static
-- @tags hotpath
-- @note Top 100 songs node: songview (song x album x path) top-N by play count.
SELECT * FROM songview WHERE iTimesPlayed>0 ORDER BY iTimesPlayed DESC LIMIT 100;

-- @id kodi.music.top100.albums
-- @src xbmc/music/MusicDatabase.cpp:3673-3679
-- @style static
-- @tags hotpath
-- @note Top 100 albums: albumview's correlated AVG/MAX subqueries per album, used in an IN (ORDER BY ... LIMIT 100) subquery, the join to albumartistview and the outer sort.
SELECT albumview.*, albumartistview.* FROM albumview JOIN albumartistview ON albumview.idAlbum = albumartistview.idAlbum WHERE albumartistview.idAlbum IN (SELECT albumview.idAlbum FROM albumview WHERE albumview.strAlbum != '' AND albumview.iTimesPlayed>0 ORDER BY albumview.iTimesPlayed DESC LIMIT 100) ORDER BY albumview.iTimesPlayed DESC, albumartistview.iOrder;

-- @id kodi.music.recently_added.albums
-- @src xbmc/music/MusicDatabase.cpp:3946-3956
-- @style PrepareSQL %u; limit = advancedsettings default 25
-- @tags hotpath
-- @note Home screen "Recently added albums" widget: derived table with top-N, joined back to albumview (correlated subqueries) and albumartistview.
SELECT albumview.*, albumartistview.* FROM (SELECT idAlbum FROM album WHERE strAlbum != '' ORDER BY dateAdded DESC LIMIT 25) AS recentalbums JOIN albumview ON albumview.idAlbum = recentalbums.idAlbum JOIN albumartistview ON albumview.idAlbum = albumartistview.idAlbum ORDER BY dateAdded DESC, albumview.idAlbum desc, albumartistview.iOrder ;

-- @id kodi.music.artists.list
-- @src xbmc/music/MusicDatabase.cpp:5600-5700
-- @style dynamic: GetFilter artists branch (MusicDatabase.cpp:13314-13448, role 1, song and album artists), GetOrderFilter + SortnameBuildSQL/GetIgnoreArticleSQL (:8338-8421) for sort by artist ignoring "the"; JSON-RPC limits 0-50
-- @tags hotpath,dynamic
-- @modified ORDER BY uses COLLATE NOCASE: Kodi registers its own ALPHANUM collation (natural number order) on SQLite connections.
-- @note Artists node / AudioLibrary.GetArtists: two correlated EXISTS over link tables OR-ed, a CASE/LIKE/SUBSTR sort key, top-N.
SELECT artistview.*, CASE WHEN artistview.strArtist LIKE 'the %' OR artistview.strArtist LIKE 'the.%' OR artistview.strArtist LIKE 'the_%' ESCAPE '_' THEN SUBSTR(artistview.strArtist, 5) ELSE artistview.strArtist END AS artistsortname FROM artistview WHERE (EXISTS (SELECT 1 FROM `song_artist` WHERE song_artist.idArtist = artistview.idArtist AND song_artist.idRole = 1) OR EXISTS (SELECT 1 FROM `album_artist` WHERE album_artist.idArtist = artistview.idArtist)) AND (artistview.strArtist != '') ORDER BY artistsortname COLLATE NOCASE LIMIT 50;

-- @id kodi.music.artists.in_genre
-- @src xbmc/music/MusicDatabase.cpp:5600-5700
-- @style dynamic: GetArtistsNav(genreid) -> GetFilter artists branch (MusicDatabase.cpp:13314-13448): song artist EXISTS with song_genre join OR album artist EXISTS with a nested genre EXISTS
-- @tags hotpath,dynamic
-- @modified ORDER BY uses COLLATE NOCASE in place of Kodi's app-registered ALPHANUM collation.
-- @note Genres > Jazz > artists: three levels of correlated EXISTS (artist -> album_artist -> song/song_genre), sorted by the ignore-article key.
-- @param ?1 23
SELECT artistview.*, CASE WHEN artistview.strArtist LIKE 'the %' OR artistview.strArtist LIKE 'the.%' OR artistview.strArtist LIKE 'the_%' ESCAPE '_' THEN SUBSTR(artistview.strArtist, 5) ELSE artistview.strArtist END AS artistsortname FROM artistview WHERE (EXISTS (SELECT 1 FROM `song_artist` JOIN song_genre ON song_genre.idSong = song_artist.idSong WHERE song_artist.idArtist = artistview.idArtist AND song_artist.idRole = 1 AND song_genre.idGenre = ?1) OR EXISTS (SELECT 1 FROM `album_artist` WHERE album_artist.idArtist = artistview.idArtist AND EXISTS(SELECT 1 FROM song JOIN song_genre ON song_genre.idSong = song.idSong WHERE song.idAlbum = album_artist.idAlbum AND song_genre.idGenre = ?1))) AND (artistview.strArtist != '') ORDER BY artistsortname COLLATE NOCASE;

-- @id kodi.music.albums.list
-- @src xbmc/music/MusicDatabase.cpp:5840-5933
-- @style dynamic: GetFilter albums branch without artist/genre (MusicDatabase.cpp:13558 strReleaseType), GetOrderFilter sort by album ignoring articles; JSON-RPC limits 0-50
-- @tags hotpath,dynamic
-- @modified ORDER BY uses COLLATE NOCASE in place of Kodi's app-registered ALPHANUM collation.
-- @note Albums node: albumview (two correlated aggregate subqueries per row) top-N on a CASE/LIKE/SUBSTR title key.
SELECT albumview.*, CASE WHEN albumview.strAlbum LIKE 'the %' OR albumview.strAlbum LIKE 'the.%' OR albumview.strAlbum LIKE 'the_%' ESCAPE '_' THEN SUBSTR(albumview.strAlbum, 5) ELSE albumview.strAlbum END AS titlesortname FROM albumview WHERE albumview.strReleaseType = 'album' ORDER BY titlesortname COLLATE NOCASE LIMIT 50;

-- @id kodi.music.albums.by_artist
-- @src xbmc/music/MusicDatabase.cpp:5840-5933
-- @style dynamic: GetAlbumsNav(artistid) -> GetFilter albums branch (MusicDatabase.cpp:13481-13547, role 1, not album-artists-only); GetOrderFilter sort by year with iYear -> CAST(strReleaseDate AS INTEGER)
-- @tags hotpath,dynamic
-- @note Artist page discography: song-artist EXISTS (join song) OR album-artist EXISTS, both correlated to albumview, sorted by the integer year.
-- @param ?1 42
SELECT albumview.* FROM albumview WHERE EXISTS (SELECT 1 FROM `song_artist` JOIN song ON song.idSong = song_artist.idSong WHERE song.idAlbum = albumview.idAlbum AND song_artist.idArtist = ?1 AND song_artist.idRole = 1) OR EXISTS (SELECT 1 FROM `album_artist` WHERE album_artist.idAlbum = albumview.idAlbum AND album_artist.idArtist = ?1) ORDER BY CAST(strReleaseDate AS INTEGER);

-- @id kodi.music.songs.in_genre
-- @src xbmc/music/MusicDatabase.cpp:6330-6367
-- @style dynamic: GetSongsNav(genreid) -> GetSongsFullByWhere with artist data, unlimited; GetFilter songs branch (MusicDatabase.cpp:13708) IN subquery
-- @tags hotpath,dynamic
-- @note Genres > Jazz > songs: songview x songartistview (song_artist x artist x role) with an IN (song_genre) filter, ordered for the C++ row grouping.
-- @param ?1 23
SELECT songview.*, songartistview.* FROM songview JOIN songartistview ON songartistview.idSong = songview.idSong WHERE songview.idSong IN (SELECT song_genre.idSong FROM song_genre WHERE song_genre.idGenre = ?1) ORDER BY songartistview.idRole, songartistview.iOrder;

-- @id kodi.music.search.songs
-- @src xbmc/music/MusicDatabase.cpp:4219-4221
-- @style PrepareSQL '%s%%' / '%% %s%%'; normalised to ?1 = 'text%', ?2 = '% text%'
-- @tags hotpath
-- @note Global search, songs: prefix LIKE or word-start LIKE over songview, capped at 1000.
-- @param ?1 'fire%'
-- @param ?2 '% fire%'
SELECT * FROM songview WHERE strTitle LIKE ?1 or strTitle LIKE ?2 LIMIT 1000;

-- @id kodi.music.nav.years
-- @src xbmc/music/MusicDatabase.cpp:5287-5330
-- @style dynamic: GetYearsNav (release date setting default) + BuildSQL
-- @tags hotpath
-- @note Years node: DISTINCT CAST over albumview with a TRIM predicate; the view's correlated subqueries are unused and should be dropped.
SELECT DISTINCT CAST(strReleaseDate AS INTEGER) AS year FROM albumview WHERE (TRIM(strReleaseDate) <> '' AND strReleaseDate IS NOT NULL);
