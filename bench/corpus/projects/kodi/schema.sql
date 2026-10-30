-- Kodi (xbmc/xbmc @ 3294b709ca23b3fd67a7784951246fefecc1dd34, GPL-2.0-or-later).
-- Only the CREATE TABLE/INDEX/VIEW/TRIGGER statements the corpus queries need, quoted from:
--   xbmc/video/VideoDatabaseDDL.cpp  (CreateTables, CreateIndices, CreateTriggers, CreateViews)
--   xbmc/music/MusicDatabase.cpp     (CreateTables, CreateAnalytics, CreateViews)
-- Normalisation: printf-style column numbers (c%02d) and type names (NameOf(MOVIE), VideoAssetType)
-- are resolved; the MySQL-style index prefix lengths "name(255)" are dropped, exactly as Kodi's
-- SQLite dataset wrapper does before executing (xbmc/dbwrappers/sqlitedataset.cpp:854).
--
-- Kodi keeps video (MyVideos*.db) and music (MyMusic*.db) in two files. They are merged here into one
-- database. path and art have the same shape in both and are shared. genre differs: the video DB has
-- genre(genre_id, name), the music DB genre(idGenre, strGenre); the merged table carries the music
-- names as VIRTUAL generated aliases so every query runs verbatim.

-- ============================== video database ==============================

CREATE TABLE bookmark ( idBookmark integer primary key, idFile integer, timeInSeconds double, totalTimeInSeconds double, thumbNailImage text, player text, playerState text, type integer);

CREATE TABLE genre ( genre_id integer primary key AUTOINCREMENT, name TEXT,
  -- merged-DB aliases for the music database's genre(idGenre, strGenre); not in Kodi's video schema
  idGenre integer GENERATED ALWAYS AS (genre_id) VIRTUAL, strGenre varchar(256) GENERATED ALWAYS AS (name) VIRTUAL);
CREATE TABLE genre_link (genre_id integer, media_id integer, media_type TEXT);

CREATE TABLE country ( country_id integer primary key, name TEXT);
CREATE TABLE country_link (country_id integer, media_id integer, media_type TEXT);

CREATE TABLE movie ( idMovie integer primary key AUTOINCREMENT, idFile integer, c00 text, c01 text, c02 text, c03 text, c04 text, c05 text, c06 text, c07 text, c08 text, c09 text, c10 text, c11 text, c12 text, c13 text, c14 text, c15 text, c16 text, c17 text, c18 text, c19 text, c20 text, c21 text, c22 text, c23 text, idSet integer, userrating integer, premiered text, originalLanguage text);

CREATE TABLE actor ( actor_id INTEGER PRIMARY KEY, name TEXT, art_urls TEXT );
CREATE TABLE actor_link(actor_id INTEGER, media_id INTEGER, media_type TEXT, role TEXT, cast_order INTEGER);
CREATE TABLE director_link(actor_id INTEGER, media_id INTEGER, media_type TEXT);
CREATE TABLE writer_link(actor_id INTEGER, media_id INTEGER, media_type TEXT);

CREATE TABLE path ( idPath integer primary key, strPath text, strContent text, strScraper text, strHash text, scanRecursive integer, useFolderNames bool, strSettings text, noUpdate bool, exclude bool, allAudio bool, dateAdded text, idParentPath integer);

CREATE TABLE files ( idFile integer primary key, idPath integer, strFilename text, playCount integer, lastPlayed text, dateAdded text);

CREATE TABLE tvshow ( idShow integer primary key AUTOINCREMENT, c00 text, c01 text, c02 text, c03 text, c04 text, c05 text, c06 text, c07 text, c08 text, c09 text, c10 text, c11 text, c12 text, c13 text, c14 text, c15 text, c16 text, c17 text, c18 text, c19 text, c20 text, c21 text, c22 text, c23 text, userrating INTEGER, duration INTEGER, originalLanguage TEXT, tagLine TEXT);

CREATE TABLE episode ( idEpisode integer primary key AUTOINCREMENT, idFile integer, c00 text, c01 text, c02 text, c03 text, c04 text, c05 text, c06 text, c07 text, c08 text, c09 text, c10 text, c11 text, c12 varchar(24), c13 varchar(24), c14 text, c15 text, c16 text, c17 varchar(24), c18 text, c19 text, c20 text, c21 text, c22 text, c23 text, idShow integer, userrating integer, idSeason integer);

CREATE TABLE tvshowlinkpath (idShow integer, idPath integer);
CREATE TABLE movielinktvshow ( idMovie integer, IdShow integer);

CREATE TABLE studio ( studio_id integer primary key, name TEXT);
CREATE TABLE studio_link (studio_id integer, media_id integer, media_type TEXT);

CREATE TABLE `sets` ( idSet integer primary key AUTOINCREMENT, strSet text, strOverview text, strOriginalSet text, strSortSet text);

CREATE TABLE seasons ( idSeason integer primary key AUTOINCREMENT, idShow integer, season integer, name text, userrating integer, plot TEXT);

CREATE TABLE art(art_id INTEGER PRIMARY KEY, media_id INTEGER, media_type TEXT, type TEXT, url TEXT);

CREATE TABLE tag (tag_id integer primary key AUTOINCREMENT, name TEXT);
CREATE TABLE tag_link (tag_id integer, media_id integer, media_type TEXT);

CREATE TABLE rating (rating_id INTEGER PRIMARY KEY, media_id INTEGER, media_type TEXT, rating_type TEXT, rating FLOAT, votes INTEGER);

CREATE TABLE uniqueid (uniqueid_id INTEGER PRIMARY KEY, media_id INTEGER, media_type TEXT, value TEXT, type TEXT);

CREATE TABLE videoversiontype (id INTEGER PRIMARY KEY, name TEXT, owner INTEGER, itemType INTEGER);
CREATE TABLE videoversion (idFile INTEGER PRIMARY KEY, idMedia INTEGER, media_type TEXT, itemType INTEGER, idType INTEGER);

-- CreateIndices
CREATE INDEX ix_bookmark ON bookmark (idFile, type);
CREATE INDEX ix_path ON path ( strPath );
CREATE INDEX ix_path2 ON path ( idParentPath );
CREATE INDEX ix_files ON files ( idPath, strFilename );
CREATE UNIQUE INDEX ix_movie_file_1 ON movie (idFile, idMovie);
CREATE UNIQUE INDEX ix_movie_file_2 ON movie (idMovie, idFile);
CREATE UNIQUE INDEX ix_tvshowlinkpath_1 ON tvshowlinkpath ( idShow, idPath );
CREATE UNIQUE INDEX ix_tvshowlinkpath_2 ON tvshowlinkpath ( idPath, idShow );
CREATE UNIQUE INDEX ix_movielinktvshow_1 ON movielinktvshow ( idShow, idMovie);
CREATE UNIQUE INDEX ix_movielinktvshow_2 ON movielinktvshow ( idMovie, idShow);
CREATE UNIQUE INDEX ix_episode_file_1 on episode (idEpisode, idFile);
CREATE UNIQUE INDEX id_episode_file_2 on episode (idFile, idEpisode);
CREATE INDEX ix_episode_season_episode on episode (c12, c13);
CREATE INDEX ix_episode_bookmark on episode (c17);
CREATE INDEX ix_episode_show1 on episode(idEpisode,idShow);
CREATE INDEX ix_episode_show2 on episode(idShow,idEpisode);
CREATE INDEX ixMovieBasePath ON movie ( c23 );
CREATE INDEX ixEpisodeBasePath ON episode ( c19 );
CREATE INDEX ix_seasons ON seasons (idShow, season);
CREATE INDEX ix_art ON art(media_id, media_type, type);
CREATE INDEX ix_rating ON rating(media_id, media_type);
CREATE INDEX ix_uniqueid1 ON uniqueid(media_id, media_type, type);
CREATE INDEX ix_uniqueid2 ON uniqueid(media_type, value);
CREATE UNIQUE INDEX ix_actor_1 ON actor (name);
CREATE UNIQUE INDEX ix_actor_link_1 ON actor_link (actor_id, media_type, media_id, role);
CREATE INDEX ix_actor_link_2 ON actor_link (media_id, media_type, actor_id);
CREATE INDEX ix_actor_link_3 ON actor_link (media_type);
CREATE INDEX ix_videoversion ON videoversion (idMedia, media_type);
CREATE INDEX ix_movie_title ON movie (c00);
CREATE INDEX ix_tvshow_title ON tvshow (c00, c05);
-- CreateLinkIndex / CreateForeignLinkIndex
CREATE UNIQUE INDEX ix_tag_1 ON tag (name);
CREATE UNIQUE INDEX ix_tag_link_1 ON tag_link (tag_id, media_type, media_id);
CREATE UNIQUE INDEX ix_tag_link_2 ON tag_link (media_id, media_type, tag_id);
CREATE INDEX ix_tag_link_3 ON tag_link (media_type);
CREATE UNIQUE INDEX ix_director_link_1 ON director_link (actor_id, media_type, media_id);
CREATE UNIQUE INDEX ix_director_link_2 ON director_link (media_id, media_type, actor_id);
CREATE INDEX ix_director_link_3 ON director_link (media_type);
CREATE UNIQUE INDEX ix_writer_link_1 ON writer_link (actor_id, media_type, media_id);
CREATE UNIQUE INDEX ix_writer_link_2 ON writer_link (media_id, media_type, actor_id);
CREATE INDEX ix_writer_link_3 ON writer_link (media_type);
CREATE UNIQUE INDEX ix_studio_1 ON studio (name);
CREATE UNIQUE INDEX ix_studio_link_1 ON studio_link (studio_id, media_type, media_id);
CREATE UNIQUE INDEX ix_studio_link_2 ON studio_link (media_id, media_type, studio_id);
CREATE INDEX ix_studio_link_3 ON studio_link (media_type);
CREATE UNIQUE INDEX ix_genre_1 ON genre (name);
CREATE UNIQUE INDEX ix_genre_link_1 ON genre_link (genre_id, media_type, media_id);
CREATE UNIQUE INDEX ix_genre_link_2 ON genre_link (media_id, media_type, genre_id);
CREATE INDEX ix_genre_link_3 ON genre_link (media_type);
CREATE UNIQUE INDEX ix_country_1 ON country (name);
CREATE UNIQUE INDEX ix_country_link_1 ON country_link (country_id, media_type, media_id);
CREATE UNIQUE INDEX ix_country_link_2 ON country_link (media_id, media_type, country_id);
CREATE INDEX ix_country_link_3 ON country_link (media_type);

-- CreateTriggers (the ones a corpus write fires: DELETE FROM movie -> tag_link -> tag)
CREATE TRIGGER delete_movie AFTER DELETE ON movie FOR EACH ROW BEGIN DELETE FROM genre_link WHERE media_id=old.idMovie AND media_type='movie'; DELETE FROM actor_link WHERE media_id=old.idMovie AND media_type='movie'; DELETE FROM director_link WHERE media_id=old.idMovie AND media_type='movie'; DELETE FROM studio_link WHERE media_id=old.idMovie AND media_type='movie'; DELETE FROM country_link WHERE media_id=old.idMovie AND media_type='movie'; DELETE FROM writer_link WHERE media_id=old.idMovie AND media_type='movie'; DELETE FROM movielinktvshow WHERE idMovie=old.idMovie; DELETE FROM art WHERE media_id=old.idMovie AND media_type='movie'; DELETE FROM tag_link WHERE media_id=old.idMovie AND media_type='movie'; DELETE FROM rating WHERE media_id=old.idMovie AND media_type='movie'; DELETE FROM uniqueid WHERE media_id=old.idMovie AND media_type='movie'; DELETE FROM videoversion WHERE idFile=old.idFile AND idMedia=old.idMovie AND media_type='movie'; END;
CREATE TRIGGER delete_tag AFTER DELETE ON tag_link FOR EACH ROW BEGIN DELETE FROM tag WHERE tag_id=old.tag_id AND tag_id NOT IN (SELECT DISTINCT tag_id FROM tag_link); END;
CREATE TRIGGER delete_videoversion AFTER DELETE ON videoversion FOR EACH ROW BEGIN DELETE FROM art WHERE media_id=old.idFile AND media_type='videoversion'; DELETE FROM streamdetails WHERE idFile=old.idFile; DELETE FROM videoversiontype WHERE id=old.idType AND itemType=2 AND owner<>0 AND id NOT IN (SELECT idType FROM videoversion); END;
CREATE TABLE streamdetails (idFile integer, iStreamType integer, strVideoCodec text, fVideoAspect float, iVideoWidth integer, iVideoHeight integer, strAudioCodec text, iAudioChannels integer, strAudioLanguage text, strSubtitleLanguage text, iVideoDuration integer, strStereoMode text, strVideoLanguage text, strHdrType text, strHdrDetail text, iSource integer, iVersion integer, iFlags integer);
CREATE INDEX ix_streamdetails ON streamdetails (idFile);

-- CreateViews
CREATE VIEW episode_view AS SELECT   episode.*,  files.strFileName AS strFileName,  path.strPath AS strPath,  files.playCount AS playCount,  files.lastPlayed AS lastPlayed,  files.dateAdded AS dateAdded,  tvshow.c00 AS strTitle,  tvshow.c08 AS genre,  tvshow.c14 AS studio,  tvshow.c05 AS premiered,  tvshow.c13 AS mpaa,  tvshow.originalLanguage,   bookmark.timeInSeconds AS resumeTimeInSeconds,   bookmark.totalTimeInSeconds AS totalTimeInSeconds,   bookmark.playerState AS playerState,   rating.rating AS rating,   rating.votes AS votes,   rating.rating_type AS rating_type,   uniqueid.value AS uniqueid_value,   uniqueid.type AS uniqueid_type FROM episode  JOIN files ON    files.idFile=episode.idFile  JOIN tvshow ON    tvshow.idShow=episode.idShow  JOIN path ON    files.idPath=path.idPath  LEFT JOIN bookmark ON    bookmark.idFile=episode.idFile AND bookmark.type=1  LEFT JOIN rating ON    rating.rating_id=episode.c03  LEFT JOIN uniqueid ON    uniqueid.uniqueid_id=episode.c20;

CREATE VIEW tvshowcounts AS SELECT       tvshow.idShow AS idShow,      MAX(files.lastPlayed) AS lastPlayed,      NULLIF(COUNT(episode.c12), 0) AS totalCount,      COUNT(files.playCount) AS watchedcount,      NULLIF(COUNT(DISTINCT(episode.c12)), 0) AS totalSeasons,       MAX(files.dateAdded) as dateAdded,       COUNT(bookmark.type) AS inProgressCount     FROM tvshow      LEFT JOIN episode ON        episode.idShow=tvshow.idShow      LEFT JOIN files ON        files.idFile=episode.idFile       LEFT JOIN bookmark ON        bookmark.idFile=files.idFile AND bookmark.type=1 GROUP BY tvshow.idShow;

CREATE VIEW tvshowlinkpath_minview AS SELECT   idShow,   min(idPath) AS idPath FROM tvshowlinkpath GROUP BY idShow;

CREATE VIEW tvshow_view AS SELECT   tvshow.*,  path.idParentPath AS idParentPath,  path.strPath AS strPath,  tvshowcounts.dateAdded AS dateAdded,  lastPlayed, totalCount, watchedcount, totalSeasons,   rating.rating AS rating,   rating.votes AS votes,   rating.rating_type AS rating_type,   uniqueid.value AS uniqueid_value,   uniqueid.type AS uniqueid_type,   tvshowcounts.inProgressCount AS inProgressCount FROM tvshow  LEFT JOIN tvshowlinkpath_minview ON     tvshowlinkpath_minview.idShow=tvshow.idShow  LEFT JOIN path ON    path.idPath=tvshowlinkpath_minview.idPath  INNER JOIN tvshowcounts ON    tvshow.idShow = tvshowcounts.idShow   LEFT JOIN rating ON    rating.rating_id=tvshow.c04   LEFT JOIN uniqueid ON    uniqueid.uniqueid_id=tvshow.c12 ;

CREATE VIEW season_view AS SELECT   seasons.idSeason AS idSeason,  seasons.idShow AS idShow,  seasons.season AS season,  seasons.name AS name,  seasons.userrating AS userrating,  tvshow_view.strPath AS strPath,  tvshow_view.c00 AS showTitle,  tvshow_view.c01 AS plot,  tvshow_view.c05 AS premiered,  tvshow_view.c08 AS genre,  tvshow_view.c14 AS studio,  tvshow_view.c13 AS mpaa,  count(DISTINCT episode.idEpisode) AS episodes,  count(files.playCount) AS playCount,  min(episode.c05) AS aired,   count(bookmark.type) AS inProgressCount,   seasons.plot AS seasonPlot FROM seasons  JOIN tvshow_view ON    tvshow_view.idShow = seasons.idShow  JOIN episode ON    episode.idShow = seasons.idShow AND episode.c12 = seasons.season  JOIN files ON    files.idFile = episode.idFile   LEFT JOIN bookmark ON    bookmark.idFile = files.idFile AND bookmark.type = 1 GROUP BY seasons.idSeason,         seasons.idShow,         seasons.season,         seasons.name,         seasons.userrating,         tvshow_view.strPath,         tvshow_view.c00,         tvshow_view.c01,         tvshow_view.c05,         tvshow_view.c08,         tvshow_view.c14,         tvshow_view.c13,         seasons.plot ;

CREATE VIEW movie_view AS SELECT  movie.*,  `sets`.`strSet` AS strSet,  `sets`.`strOverview` AS strSetOverview,  `sets`.`strOriginalSet` as strOriginalSet,  `sets`.`strSortSet` AS strSetSortTitle,  files.strFileName AS strFileName,  path.strPath AS strPath,  files.playCount AS playCount,  files.lastPlayed AS lastPlayed,   files.dateAdded AS dateAdded,   bookmark.timeInSeconds AS resumeTimeInSeconds,   bookmark.totalTimeInSeconds AS totalTimeInSeconds,   bookmark.playerState AS playerState,   rating.rating AS rating,   rating.votes AS votes,   rating.rating_type AS rating_type,   uniqueid.value AS uniqueid_value,   uniqueid.type AS uniqueid_type,   EXISTS(     SELECT 1     FROM  videoversion vv     WHERE vv.idMedia = movie.idMovie     AND   vv.media_type = 'movie'     AND   vv.itemType = 1     AND   vv.idFile <> movie.idFile   ) AS hasVideoVersions,   EXISTS(     SELECT 1     FROM  videoversion vv     WHERE vv.idMedia = movie.idMovie     AND   vv.media_type = 'movie'     AND   vv.itemType = 2   ) AS hasVideoExtras,   CASE     WHEN vv.idFile = movie.idFile AND vv.itemType = 1 THEN 1     ELSE 0   END AS isDefaultVersion,   vv.idFile AS videoVersionIdFile,   vvt.id AS videoVersionTypeId,  vvt.name AS videoVersionTypeName,  vvt.itemType AS videoVersionTypeItemType FROM movie  LEFT JOIN `sets` ON    `sets`.idSet = movie.idSet  LEFT JOIN rating ON    rating.rating_id = movie.c05  LEFT JOIN uniqueid ON    uniqueid.uniqueid_id = movie.c09  LEFT JOIN videoversion vv ON    vv.idMedia = movie.idMovie AND vv.media_type = 'movie'   JOIN videoversiontype vvt ON    vvt.id = vv.idType AND vvt.itemType = vv.itemType  JOIN files ON    files.idFile = vv.idFile  JOIN path ON    path.idPath = files.idPath  LEFT JOIN bookmark ON    bookmark.idFile = vv.idFile AND bookmark.type = 1;

-- ============================== music database ==============================
-- (genre, path and art: shared with the video tables above)

CREATE TABLE artist ( idArtist integer primary key AUTOINCREMENT,  strArtist varchar(256), strMusicBrainzArtistID text,  strSortName text,  strType text, strGender text, strDisambiguation text,  strBorn text, strFormed text, strGenres text, strMoods text,  strStyles text, strInstruments text, strBiography text,  strDied text, strDisbanded text, strYearsActive text,  strImage text,  lastScraped varchar(20) default NULL,  bScrapedMBID INTEGER NOT NULL DEFAULT 0,  idInfoSetting INTEGER NOT NULL DEFAULT 0,  dateAdded TEXT, dateNew TEXT, dateModified TEXT);

CREATE TABLE album (idAlbum integer primary key AUTOINCREMENT,  strAlbum varchar(256), strMusicBrainzAlbumID text,  strReleaseGroupMBID text,  strArtistDisp text, strArtistSort text, strGenres text,  strReleaseDate TEXT, strOrigReleaseDate TEXT,  bBoxedSet INTEGER NOT NULL DEFAULT 0,  bCompilation integer not null default '0',  strMoods text, strStyles text, strThemes text,  strReview text, strImage text, strLabel text,  strType text,  strReleaseStatus TEXT,  fRating FLOAT NOT NULL DEFAULT 0,  iVotes INTEGER NOT NULL DEFAULT 0,  iUserrating INTEGER NOT NULL DEFAULT 0,  lastScraped varchar(20) default NULL,  bScrapedMBID INTEGER NOT NULL DEFAULT 0,  strReleaseType text,  iDiscTotal INTEGER NOT NULL DEFAULT 0,  iAlbumDuration INTEGER NOT NULL DEFAULT 0,  idInfoSetting INTEGER NOT NULL DEFAULT 0,  dateAdded TEXT, dateNew TEXT, dateModified TEXT);

CREATE TABLE album_artist (idArtist integer, idAlbum integer, iOrder integer, strArtist text);

CREATE TABLE song (idSong integer primary key AUTOINCREMENT,  idAlbum integer, idPath integer,  strArtistDisp text, strArtistSort text, strGenres text, strTitle varchar(512),  iTrack integer, iDuration integer,  strReleaseDate TEXT, strOrigReleaseDate TEXT,  strDiscSubtitle text, strFileName text, strMusicBrainzTrackID text,  iTimesPlayed integer, iStartOffset integer, iEndOffset integer,  lastplayed varchar(20) default NULL,  rating FLOAT NOT NULL DEFAULT 0, votes INTEGER NOT NULL DEFAULT 0,  userrating INTEGER NOT NULL DEFAULT 0,  comment text, mood text, iBPM INTEGER NOT NULL DEFAULT 0,  iBitRate INTEGER NOT NULL DEFAULT 0,  iSampleRate INTEGER NOT NULL DEFAULT 0, iChannels INTEGER NOT NULL DEFAULT 0,  strVideoURL TEXT,  strReplayGain text,  dateAdded TEXT, dateNew TEXT, dateModified TEXT);
CREATE TABLE song_artist (idArtist integer, idSong integer, idRole integer, iOrder integer, strArtist text);
CREATE TABLE song_genre (idGenre integer, idSong integer, iOrder integer);
CREATE TABLE role (idRole integer primary key AUTOINCREMENT, strRole text);

-- CreateAnalytics: indices (idxGenre/idxPath/ix_art duplicate the shared tables' video indices)
CREATE INDEX idxAlbum ON album(strAlbum);
CREATE INDEX idxAlbum_1 ON album(bCompilation);
CREATE UNIQUE INDEX idxAlbum_2 ON album(strMusicBrainzAlbumID);
CREATE INDEX idxAlbum_3 ON album(idInfoSetting);
CREATE UNIQUE INDEX idxAlbumArtist_1 ON album_artist ( idAlbum, idArtist );
CREATE UNIQUE INDEX idxAlbumArtist_2 ON album_artist ( idArtist, idAlbum );
CREATE INDEX idxArtist ON artist(strArtist);
CREATE UNIQUE INDEX idxArtist1 ON artist(strMusicBrainzArtistID);
CREATE INDEX idxArtist_2 ON artist(idInfoSetting);
CREATE INDEX idxSong ON song(strTitle);
CREATE INDEX idxSong1 ON song(iTimesPlayed);
CREATE INDEX idxSong2 ON song(lastplayed);
CREATE INDEX idxSong3 ON song(idAlbum);
CREATE INDEX idxSong6 ON song( idPath, strFileName );
CREATE UNIQUE INDEX idxSong7 ON song( idAlbum, iTrack, strMusicBrainzTrackID );
CREATE UNIQUE INDEX idxSongArtist_1 ON song_artist ( idSong, idArtist, idRole );
CREATE INDEX idxSongArtist_2 ON song_artist ( idSong, idRole );
CREATE INDEX idxSongArtist_3 ON song_artist ( idArtist, idRole );
CREATE INDEX idxSongArtist_4 ON song_artist ( idRole );
CREATE UNIQUE INDEX idxSongGenre_1 ON song_genre ( idSong, idGenre );
CREATE UNIQUE INDEX idxSongGenre_2 ON song_genre ( idGenre, idSong );
CREATE INDEX idxRole on role(strRole);

-- CreateAnalytics: the SQLite update trigger a corpus write fires (the insert triggers stamp DATETIME('now')
-- and are left out so the synthetic data stays deterministic)
CREATE TRIGGER tgrUpdateSong AFTER UPDATE ON song FOR EACH ROW WHEN NEW.dateModified <= OLD.dateModified BEGIN UPDATE song SET dateModified = DATETIME('now') WHERE idSong = OLD.idSong; END;

-- CreateViews
CREATE VIEW songview AS SELECT         song.idSong AS idSong,         song.strArtistDisp AS strArtists,        song.strArtistSort AS strArtistSort,        song.strGenres AS strGenres,        strTitle,         iTrack, iDuration,         song.strReleaseDate as strReleaseDate,         song.strOrigReleaseDate as strOrigReleaseDate,         song.strDiscSubtitle as strDiscSubtitle,         strFileName,         strMusicBrainzTrackID,         iTimesPlayed, iStartOffset, iEndOffset,         lastplayed,         song.rating,         song.userrating,         song.votes,         comment,         song.idAlbum AS idAlbum,         strAlbum,         strPath,         album.strReleaseStatus as strReleaseStatus,        album.bCompilation AS bCompilation,        album.bBoxedSet AS bBoxedSet,         album.strArtistDisp AS strAlbumArtists,        album.strArtistSort AS strAlbumArtistSort,        album.strReleaseType AS strAlbumReleaseType,        song.mood as mood,        song.strReplayGain,         iBPM,         iBitRate,         iSampleRate,         iChannels,         song.strVideoURL as strVideoURL,         album.iAlbumDuration AS iAlbumDuration,         album.iDiscTotal as iDiscTotal,         song.dateAdded as dateAdded,         song.dateNew AS dateNew,         song.dateModified AS dateModified FROM song  JOIN album ON    song.idAlbum=album.idAlbum  JOIN path ON    song.idPath=path.idPath;

CREATE VIEW albumview AS SELECT album.idAlbum AS idAlbum, strAlbum, strMusicBrainzAlbumID, strReleaseGroupMBID, album.strArtistDisp AS strArtists, album.strArtistSort AS strArtistSort, album.strGenres AS strGenres, album.strReleaseDate as strReleaseDate, album.strOrigReleaseDate as strOrigReleaseDate, album.bBoxedSet AS bBoxedSet, album.strMoods AS strMoods, album.strStyles AS strStyles, strThemes, strReview, strLabel, strType, strReleaseStatus, album.strImage as strImage, album.fRating, album.iUserrating, album.iVotes, bCompilation, bScrapedMBID,lastScraped,dateAdded, dateNew, dateModified, (SELECT ROUND(AVG(song.iTimesPlayed)) FROM song WHERE song.idAlbum = album.idAlbum) AS iTimesPlayed, strReleaseType, iDiscTotal, (SELECT MAX(song.lastplayed) FROM song WHERE song.idAlbum = album.idAlbum) AS lastplayed, iAlbumDuration FROM album;

CREATE VIEW artistview AS SELECT  idArtist, strArtist, strSortName,   strMusicBrainzArtistID,   strType, strGender, strDisambiguation,   strBorn, strFormed, strGenres,  strMoods, strStyles, strInstruments,   strBiography, strDied, strDisbanded,   strYearsActive, strImage,   bScrapedMBID, lastScraped,   dateAdded, dateNew, dateModified FROM artist;

CREATE VIEW albumartistview AS SELECT  album_artist.idAlbum AS idAlbum,   album_artist.idArtist AS idArtist,   0 AS idRole,   'AlbumArtist' AS strRole,   artist.strArtist AS strArtist,   artist.strSortName AS strSortName,  artist.strMusicBrainzArtistID AS strMusicBrainzArtistID,   album_artist.iOrder AS iOrder FROM album_artist JOIN artist ON      album_artist.idArtist = artist.idArtist;

CREATE VIEW songartistview AS SELECT  song_artist.idSong AS idSong,   song_artist.idArtist AS idArtist,   song_artist.idRole AS idRole,   role.strRole AS strRole,   artist.strArtist AS strArtist,   artist.strSortName AS strSortName,  artist.strMusicBrainzArtistID AS strMusicBrainzArtistID,   song_artist.iOrder AS iOrder FROM song_artist JOIN artist ON      song_artist.idArtist = artist.idArtist JOIN role ON      song_artist.idRole = role.idRole;
