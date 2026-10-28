-- Synthetic data for kodi (video + music library in one database). Deterministic: values come from
-- multiplicative hashes of the row number, different bits per column. Scale 1:
--   video: 5000 movies (+500 extra versions/extras), 400 sets, 300 TV shows, 15000 episodes, ~1500 seasons,
--          20000 actors, ~42k cast links, ~10k genre links, ~1.2k tag links, ~1k resume bookmarks
--   music: 3000 artists, 4000 albums, 40000 songs, ~50k song-artist links, ~52k song-genre links
--   shared: ~24k path rows, ~25k art rows, 40 genres (20 video, 20 music)
BEGIN;

CREATE TEMP TABLE _n AS
  WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40000*(SELECT scale FROM _cfg)) SELECT i FROM n;
CREATE TEMP TABLE _k AS
  SELECT (SELECT scale FROM _cfg) AS s, 5000*(SELECT scale FROM _cfg) AS M, 500*(SELECT scale FROM _cfg) AS V,
         300*(SELECT scale FROM _cfg) AS T, 15000*(SELECT scale FROM _cfg) AS E,
         3000*(SELECT scale FROM _cfg) AS AR, 4000*(SELECT scale FROM _cfg) AS AL, 40000*(SELECT scale FROM _cfg) AS SG,
         20000*(SELECT scale FROM _cfg) AS ACT;
CREATE TEMP TABLE _w(k INTEGER PRIMARY KEY, adj TEXT, noun TEXT, first TEXT, last TEXT);
INSERT INTO _w VALUES
 (0,'Dark','Star','Anna','Smith'),(1,'Silent','River','Ben','Jones'),(2,'Lost','City','Clara','Brown'),
 (3,'Red','Night','David','Miller'),(4,'Last','Kingdom','Emma','Davis'),(5,'Broken','Road','Frank','Garcia'),
 (6,'Golden','Heart','Grace','Wilson'),(7,'Hidden','Storm','Henry','Moore'),(8,'Wild','Ocean','Iris','Taylor'),
 (9,'Cold','Fire','Jack','Thomas'),(10,'Electric','Dream','Kate','White'),(11,'Final','Game','Leo','Martin'),
 (12,'Crimson','Shadow','Mia','Clark'),(13,'Eternal','Garden','Noah','Lewis'),(14,'Iron','Sky','Olga','Walker'),
 (15,'Midnight','Song','Paul','Young');

-- ---------------------------------------------------------------- video
INSERT INTO genre(genre_id, name) VALUES
 (1,'Action'),(2,'Adventure'),(3,'Animation'),(4,'Comedy'),(5,'Crime'),(6,'Documentary'),(7,'Drama'),(8,'Family'),
 (9,'Fantasy'),(10,'History'),(11,'Horror'),(12,'Music'),(13,'Mystery'),(14,'Romance'),(15,'Science Fiction'),
 (16,'Thriller'),(17,'War'),(18,'Western'),(19,'TV Movie'),(20,'Sci-Fi & Fantasy'),
 (21,'Rock'),(22,'Pop'),(23,'Jazz'),(24,'Blues'),(25,'Classical'),(26,'Electronic'),(27,'Hip-Hop'),(28,'Folk'),
 (29,'Metal'),(30,'Soul'),(31,'Reggae'),(32,'Country'),(33,'Punk'),(34,'Ambient'),(35,'Indie'),(36,'R&B'),
 (37,'Latin'),(38,'Soundtrack'),(39,'Funk'),(40,'');

INSERT INTO videoversiontype(id, name, owner, itemType) VALUES
 (40400,'Standard Edition',0,1),(40401,'Director''s Cut',0,1),(40402,'Extended Edition',0,1),(40403,'Theatrical',0,1),
 (40500,'Trailer',0,2),(40501,'Behind the scenes',0,2),(40502,'Deleted scenes',0,2),(40800,'Interview',2,2);

INSERT INTO `sets`(idSet, strSet, strOverview, strOriginalSet, strSortSet)
SELECT i, 'Collection ' || i, 'Overview of collection ' || i, 'Collection ' || i, NULL FROM _n WHERE i <= 400*(SELECT s FROM _k);

-- paths: one folder per movie, per TV show, per album
INSERT INTO path(idPath, strPath, strContent, strScraper, strHash, scanRecursive, useFolderNames, noUpdate, exclude, allAudio, dateAdded, idParentPath)
SELECT i, printf('smb://nas/movies/%05d/', i), 'movies', 'metadata.themoviedb.org', printf('%08x', (i*2654435761) % 4294967296), 0, 1, 0, 0, 0,
       datetime(1514764800 + i*30000, 'unixepoch'), NULL
FROM _n WHERE i <= (SELECT M FROM _k);
INSERT INTO path(idPath, strPath, strContent, strScraper, strHash, scanRecursive, useFolderNames, noUpdate, exclude, allAudio, dateAdded, idParentPath)
SELECT (SELECT M FROM _k) + i, printf('smb://nas/tv/show%04d/', i), 'tvshows', 'metadata.tvshows.themoviedb.org', NULL, 0, 0, 0, 0, 0,
       datetime(1514764800 + i*400000, 'unixepoch'), NULL
FROM _n WHERE i <= (SELECT T FROM _k);
INSERT INTO path(idPath, strPath, strHash)
SELECT (SELECT M + T FROM _k) + i, printf('smb://nas/music/%05d/', i), printf('%08x', (i*40503) % 4294967296)
FROM _n WHERE i <= (SELECT AL FROM _k);

-- movie files (idFile = idMovie), then 300 alternate versions and 200 extras
INSERT INTO files(idFile, idPath, strFilename, playCount, lastPlayed, dateAdded)
SELECT i, i, printf('movie-%05d.mkv', i),
       CASE WHEN (h / 16) % 5 < 2 THEN (h / 64) % 3 + 1 END,
       CASE WHEN (h / 16) % 5 < 2 THEN datetime(1600000000 + (h / 4) % 120000000, 'unixepoch') END,
       datetime(1514764800 + i*30000, 'unixepoch')
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM _n WHERE i <= (SELECT M FROM _k));
INSERT INTO files(idFile, idPath, strFilename, playCount, lastPlayed, dateAdded)
SELECT (SELECT M FROM _k) + i, ((i * 97) % (SELECT M FROM _k)) + 1,
       CASE WHEN i <= 300*(SELECT s FROM _k) THEN printf('movie-%05d.directors-cut.mkv', ((i * 97) % (SELECT M FROM _k)) + 1)
            ELSE printf('movie-%05d-trailer.mkv', ((i * 97) % (SELECT M FROM _k)) + 1) END,
       NULL, NULL, datetime(1520000000 + i*200000, 'unixepoch')
FROM _n WHERE i <= (SELECT V FROM _k);

INSERT INTO movie(idMovie, idFile, c00, c01, c02, c03, c05, c06, c09, c10, c11, c12, c14, c15, c16, c18, c19, c20, c21, c22, c23, idSet, userrating, premiered, originalLanguage)
SELECT i, i,
       CASE WHEN (h / 8) % 9 = 0 THEN 'The ' ELSE '' END || a.adj || ' ' || b.noun || CASE WHEN (h / 65536) % 3 = 0 THEN ' ' || (i % 7 + 2) ELSE '' END,
       'A film about ' || lower(b.noun) || ' and ' || lower(a.adj) || ' things, number ' || i || '.',
       'Outline ' || i, 'Tagline ' || i,
       i, 'Writer ' || (h % 900), i,
       NULL, (h / 32) % 80 + 80,
       CASE (h / 2048) % 5 WHEN 0 THEN 'Rated G' WHEN 1 THEN 'Rated PG' WHEN 2 THEN 'Rated PG-13' WHEN 3 THEN 'Rated R' ELSE 'NR' END,
       'Drama / Action', 'Director ' || (h % 700),
       a.adj || ' ' || b.noun || ' (original)', 'Studio ' || (h / 512) % 60,
       'https://trailer.example/' || i, '<fanart/>', CASE (h / 128) % 4 WHEN 0 THEN 'France' WHEN 1 THEN 'Japan' ELSE 'United States' END,
       printf('smb://nas/movies/%05d/', i), i,
       CASE WHEN (h / 1024) % 5 = 0 THEN ((h / 32768) % (400*(SELECT s FROM _k))) + 1 END,
       (h / 4096) % 11,
       printf('%04d-%02d-%02d', 1950 + (h / 65536) % 75, 1 + (h / 8) % 12, 1 + (h / 128) % 28),
       CASE (h / 64) % 6 WHEN 0 THEN 'fr' WHEN 1 THEN 'ja' ELSE 'en' END
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM _n WHERE i <= (SELECT M FROM _k)) m
JOIN _w a ON a.k = (m.h / 256) % 16
JOIN _w b ON b.k = (m.h / 4096) % 16;

INSERT INTO videoversion(idFile, idMedia, media_type, itemType, idType)
SELECT idMovie, idMovie, 'movie', 1, 40400 FROM movie;
INSERT INTO videoversion(idFile, idMedia, media_type, itemType, idType)
SELECT (SELECT M FROM _k) + i, ((i * 97) % (SELECT M FROM _k)) + 1, 'movie',
       CASE WHEN i <= 300*(SELECT s FROM _k) THEN 1 ELSE 2 END,
       CASE WHEN i <= 300*(SELECT s FROM _k) THEN 40401 + i % 3 ELSE 40500 + i % 3 END
FROM _n WHERE i <= (SELECT V FROM _k);

-- TV shows, episodes, seasons
INSERT INTO tvshow(idShow, c00, c01, c02, c04, c05, c06, c08, c09, c10, c12, c13, c14, c15, userrating, duration, originalLanguage, tagLine)
SELECT i, a.adj || ' ' || b.noun || ' Chronicles ' || i, 'A series about ' || lower(b.noun) || '.', CASE WHEN i % 4 = 0 THEN 'Ended' ELSE 'Continuing' END,
       (SELECT M FROM _k) + i, printf('%04d-%02d-%02d', 1990 + (h / 65536) % 35, 1 + (h / 8) % 12, 1 + (h / 128) % 28), '<thumb/>',
       CASE (h / 2) % 4 WHEN 0 THEN 'Drama' WHEN 1 THEN 'Comedy' WHEN 2 THEN 'Sci-Fi & Fantasy' ELSE 'Crime / Drama' END,
       a.adj || ' ' || b.noun, '<episodeguide/>', (SELECT M FROM _k) + i,
       CASE (h / 2048) % 3 WHEN 0 THEN 'TV-14' WHEN 1 THEN 'TV-MA' ELSE 'TV-PG' END, 'Network ' || (h / 512) % 20, NULL,
       (h / 4096) % 11, 45, 'en', 'Tagline ' || i
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM _n WHERE i <= (SELECT T FROM _k)) t
JOIN _w a ON a.k = (t.h / 256) % 16
JOIN _w b ON b.k = (t.h / 4096) % 16;

INSERT INTO tvshowlinkpath(idShow, idPath) SELECT idShow, (SELECT M FROM _k) + idShow FROM tvshow;

-- 50 episodes per show, split into 1..6 seasons, the last episode of every 5th show is a special (season 0);
-- every 3rd show is part-watched, every 7th fully watched, the rest untouched
INSERT INTO files(idFile, idPath, strFilename, playCount, lastPlayed, dateAdded)
SELECT (SELECT M + V FROM _k) + i, (SELECT M FROM _k) + sh, printf('S%02dE%02d.mkv', 1 + j * ns / 50, j + 1),
       CASE WHEN (sh % 3 = 0 AND j < (sh * 13) % 50) OR sh % 7 = 1 THEN 1 END,
       CASE WHEN (sh % 3 = 0 AND j < (sh * 13) % 50) OR sh % 7 = 1 THEN datetime(1650000000 + sh * 86400 + j * 3600, 'unixepoch') END,
       datetime(1546300800 + i * 9000, 'unixepoch')
FROM (SELECT i, (i - 1) % (SELECT T FROM _k) + 1 AS sh, (i - 1) / (SELECT T FROM _k) AS j,
             1 + ((((i - 1) % (SELECT T FROM _k) + 1) * 7) % 6) AS ns
      FROM _n WHERE i <= (SELECT E FROM _k));

INSERT INTO episode(idEpisode, idFile, c00, c01, c03, c04, c05, c09, c10, c12, c13, c15, c16, c17, c18, c19, c20, idShow, userrating)
SELECT i, (SELECT M + V FROM _k) + i, 'Episode ' || (j + 1) || ': ' || w.adj || ' ' || w.noun, 'Plot of episode ' || i,
       (SELECT M + T FROM _k) + i, 'Writer ' || (i % 300),
       date('1990-01-01', '+' || ((sh * 97) % 9000 + j * 7) || ' days'), 2700, 'Director ' || (i % 200),
       CASE WHEN j = 49 AND sh % 5 = 0 THEN 0 ELSE 1 + j * ns / 50 END, j + 1, -1, -1, -1,
       printf('smb://nas/tv/show%04d/', sh), (SELECT M FROM _k) + sh, (SELECT M + T FROM _k) + i, sh, (i / 7) % 11
FROM (SELECT i, (i - 1) % (SELECT T FROM _k) + 1 AS sh, (i - 1) / (SELECT T FROM _k) AS j,
             1 + ((((i - 1) % (SELECT T FROM _k) + 1) * 7) % 6) AS ns
      FROM _n WHERE i <= (SELECT E FROM _k)) e
JOIN _w w ON w.k = (e.i * 7) % 16;

INSERT INTO seasons(idShow, season, name, userrating, plot)
SELECT DISTINCT idShow, CAST(c12 AS INTEGER), CASE WHEN CAST(c12 AS INTEGER) = 0 THEN 'Specials' ELSE 'Season ' || c12 END, NULL, NULL
FROM episode ORDER BY idShow, CAST(c12 AS INTEGER);
UPDATE episode SET idSeason = (SELECT idSeason FROM seasons WHERE seasons.idShow = episode.idShow AND seasons.season = CAST(episode.c12 AS INTEGER));

-- ratings and unique ids: movies 1..M, shows M+1..M+T, episodes M+T+1..
INSERT INTO rating(rating_id, media_id, media_type, rating_type, rating, votes)
SELECT idMovie, idMovie, 'movie', 'themoviedb', ((idMovie * 2654435761) % 4294967296) % 60 / 10.0 + 4.0, (idMovie * 37) % 20000 FROM movie
UNION ALL SELECT (SELECT M FROM _k) + idShow, idShow, 'tvshow', 'tmdb', (idShow * 13) % 50 / 10.0 + 5.0, idShow * 11 FROM tvshow
UNION ALL SELECT (SELECT M + T FROM _k) + idEpisode, idEpisode, 'episode', 'tmdb', (idEpisode * 7) % 40 / 10.0 + 6.0, idEpisode % 300 FROM episode;
INSERT INTO uniqueid(uniqueid_id, media_id, media_type, value, type)
SELECT idMovie, idMovie, 'movie', 'tt' || printf('%07d', idMovie * 13), 'imdb' FROM movie
UNION ALL SELECT (SELECT M FROM _k) + idShow, idShow, 'tvshow', CAST(70000 + idShow AS TEXT), 'tmdb' FROM tvshow
UNION ALL SELECT (SELECT M + T FROM _k) + idEpisode, idEpisode, 'episode', CAST(900000 + idEpisode AS TEXT), 'tmdb' FROM episode;

-- resume points on ~5% of movie files and of the part-watched shows' episodes
INSERT INTO bookmark(idFile, timeInSeconds, totalTimeInSeconds, thumbNailImage, player, playerState, type)
SELECT idFile, ((idFile * 2654435761) % 4294967296) % 5000 + 60.0, 7200.0, '', 'VideoPlayer', '<state/>', 1
FROM files WHERE ((idFile * 2654435761) % 4294967296 / 2048) % 20 = 0
  AND (idFile <= (SELECT M + V FROM _k) OR ((idFile - (SELECT M + V FROM _k) - 1) % (SELECT T FROM _k) + 1) % 3 = 0);

-- genres: two per movie and show
INSERT OR IGNORE INTO genre_link(genre_id, media_id, media_type)
SELECT (h / 2) % 19 + 1, idMovie, 'movie' FROM (SELECT idMovie, (idMovie * 2654435761) % 4294967296 AS h FROM movie)
UNION ALL SELECT (h / 4096) % 19 + 1, idMovie, 'movie' FROM (SELECT idMovie, (idMovie * 2654435761) % 4294967296 AS h FROM movie)
UNION ALL SELECT (idShow * 3) % 20 + 1, idShow, 'tvshow' FROM tvshow
UNION ALL SELECT (idShow * 11 + 5) % 20 + 1, idShow, 'tvshow' FROM tvshow;

-- tags on a quarter of the movies
INSERT INTO tag(tag_id, name) SELECT i, 'tag-' || i FROM _n WHERE i <= 30;
INSERT OR IGNORE INTO tag_link(tag_id, media_id, media_type)
SELECT (h / 512) % 30 + 1, idMovie, 'movie' FROM (SELECT idMovie, (idMovie * 2654435761) % 4294967296 AS h FROM movie) WHERE (h / 8) % 4 = 0;

-- actors: 8 per movie and per show; the first two cast slots come from a pool of 500 busy actors
INSERT INTO actor(actor_id, name, art_urls)
SELECT i, w1.first || ' ' || w2.last || ' ' || i, '<thumb>https://image.tmdb.org/p/' || i || '.jpg</thumb>'
FROM _n JOIN _w w1 ON w1.k = (i * 7) % 16 JOIN _w w2 ON w2.k = (i / 16) % 16
WHERE i <= (SELECT ACT FROM _k);
INSERT OR IGNORE INTO actor_link(actor_id, media_id, media_type, role, cast_order)
SELECT CASE WHEN k < 2 THEN (hk % 500) + 1 ELSE (hk % (SELECT ACT FROM _k)) + 1 END, m, t, 'Role ' || k, k
FROM (SELECT idMovie AS m, 'movie' AS t, k.i - 1 AS k, ((idMovie * 8 + k.i) * 2654435761) % 4294967296 / 16 AS hk
        FROM movie, (SELECT i FROM _n WHERE i <= 8) k
      UNION ALL
      SELECT idShow, 'tvshow', k.i - 1, ((idShow * 8 + k.i + 7777777) * 2654435761) % 4294967296 / 16
        FROM tvshow, (SELECT i FROM _n WHERE i <= 8) k);

-- ---------------------------------------------------------------- music
INSERT INTO role(idRole, strRole) VALUES (1,'Artist'),(2,'Composer'),(3,'Conductor');

INSERT INTO artist(idArtist, strArtist, strMusicBrainzArtistID, strSortName, strType, strGenres, strBiography, dateAdded, dateNew, dateModified)
SELECT 1, '[Missing Tag]', 'Artist Tag Missing', '[Missing Tag]', NULL, NULL, NULL, NULL, NULL, NULL;
INSERT INTO artist(idArtist, strArtist, strMusicBrainzArtistID, strSortName, strType, strGenres, strBiography, dateAdded, dateNew, dateModified)
SELECT i,
       CASE WHEN (h / 16) % 10 = 0 THEN 'The ' ELSE '' END || w1.first || ' ' || w2.last || CASE WHEN (h / 16) % 10 = 0 THEN 's' ELSE '' END || ' ' || i,
       CASE WHEN (h / 4) % 3 = 0 THEN NULL ELSE printf('%08x-0000-4000-8000-%012d', h, i) END,
       CASE WHEN (h / 256) % 7 = 0 THEN w2.last || ', ' || w1.first ELSE NULL END,
       CASE WHEN (h / 16) % 10 = 0 THEN 'Group' ELSE 'Person' END, 'Rock / Pop', 'Bio ' || i,
       datetime(1483228800 + i * 26000, 'unixepoch'), datetime(1483228800 + i * 26000, 'unixepoch'), datetime(1483228800 + i * 26000, 'unixepoch')
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM _n WHERE i BETWEEN 2 AND (SELECT AR FROM _k)) a
JOIN _w w1 ON w1.k = (a.h / 1024) % 16 JOIN _w w2 ON w2.k = (a.h / 65536) % 16;

CREATE TEMP TABLE _alb AS
SELECT i AS idAlbum, h,
       CASE WHEN (h / 8) % 4 = 0 THEN (h / 32) % 100 + 2 ELSE (h / 32) % ((SELECT AR FROM _k) - 1) + 2 END AS idArtist
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM _n WHERE i <= (SELECT AL FROM _k));

INSERT INTO album(idAlbum, strAlbum, strMusicBrainzAlbumID, strReleaseGroupMBID, strArtistDisp, strArtistSort, strGenres, strReleaseDate, strOrigReleaseDate,
                  bBoxedSet, bCompilation, strMoods, strStyles, strThemes, strReview, strImage, strLabel, strType, strReleaseStatus,
                  fRating, iVotes, iUserrating, strReleaseType, iDiscTotal, iAlbumDuration, dateAdded, dateNew, dateModified)
SELECT x.idAlbum,
       CASE WHEN (x.h / 4096) % 8 = 0 THEN 'The ' ELSE '' END || w1.adj || ' ' || w2.noun || CASE WHEN (x.h / 64) % 3 = 0 THEN ' Vol. ' || (x.idAlbum % 4 + 1) ELSE '' END,
       CASE WHEN (x.h / 2) % 4 = 0 THEN NULL ELSE printf('%08x-1111-4000-8000-%012d', x.h, x.idAlbum) END, NULL,
       ar.strArtist, ar.strSortName, g.name,
       CASE WHEN (x.h / 1024) % 2 = 0 THEN printf('%04d', 1960 + (x.h / 2048) % 65) ELSE printf('%04d-%02d-%02d', 1960 + (x.h / 2048) % 65, 1 + (x.h / 8) % 12, 1 + (x.h / 128) % 28) END,
       printf('%04d', 1960 + (x.h / 2048) % 65),
       CASE WHEN (x.h / 512) % 40 = 0 THEN 1 ELSE 0 END, CASE WHEN (x.h / 16) % 20 = 0 THEN 1 ELSE 0 END,
       'Energetic', 'Alternative', NULL, 'Review ' || x.idAlbum, NULL,
       'Label ' || (x.h / 8192) % 150, CASE (x.h / 4) % 3 WHEN 0 THEN 'Album' WHEN 1 THEN 'EP' ELSE 'Live' END, 'Official',
       (x.h / 16384) % 50 / 10.0 + 5.0, (x.h / 8) % 500, (x.h / 32) % 11,
       CASE WHEN (x.h / 65536) % 7 = 0 THEN 'single' ELSE 'album' END, 1, 2400 + (x.h % 1800),
       datetime(1483228800 + x.idAlbum * 20000, 'unixepoch'), datetime(1483228800 + x.idAlbum * 20000, 'unixepoch'), datetime(1483228800 + x.idAlbum * 20000, 'unixepoch')
FROM _alb x JOIN artist ar ON ar.idArtist = x.idArtist
JOIN _w w1 ON w1.k = (x.h / 256) % 16 JOIN _w w2 ON w2.k = (x.h / 1048576) % 16
JOIN genre g ON g.genre_id = (x.h / 4) % 19 + 21;

INSERT OR IGNORE INTO album_artist(idArtist, idAlbum, iOrder, strArtist)
SELECT x.idArtist, x.idAlbum, 0, a.strArtist FROM _alb x JOIN artist a ON a.idArtist = x.idArtist
UNION ALL
SELECT ((x.h / 4096) % ((SELECT AR FROM _k) - 1)) + 2, x.idAlbum, 1, 'Guest' FROM _alb x WHERE (x.h / 128) % 10 = 0;

-- 10 songs per album
INSERT INTO song(idSong, idAlbum, idPath, strArtistDisp, strArtistSort, strGenres, strTitle, iTrack, iDuration, strReleaseDate, strOrigReleaseDate,
                 strDiscSubtitle, strFileName, strMusicBrainzTrackID, iTimesPlayed, iStartOffset, iEndOffset, lastplayed, rating, votes, userrating,
                 comment, mood, iBPM, iBitRate, iSampleRate, iChannels, strVideoURL, strReplayGain, dateAdded, dateNew, dateModified)
SELECT s.i, al.idAlbum, (SELECT M + T FROM _k) + al.idAlbum, al.strArtistDisp, al.strArtistSort, al.strGenres,
       w1.adj || ' ' || w2.noun || CASE WHEN (s.h / 64) % 4 = 0 THEN ' (Remix)' ELSE '' END,
       65536 + (s.i - 1) % 10 + 1, 120 + s.h % 300, al.strReleaseDate, al.strOrigReleaseDate, '',
       printf('%02d-%05d.flac', (s.i - 1) % 10 + 1, s.i),
       CASE WHEN (s.h / 2) % 4 = 0 THEN NULL ELSE printf('%08x-2222-4000-8000-%012d', s.h, s.i) END,
       CASE WHEN (s.h / 16) % 10 < 3 THEN (s.h / 256) % 40 + 1 ELSE 0 END, 0, 0,
       CASE WHEN (s.h / 16) % 10 < 3 THEN datetime(1600000000 + (s.h / 8) % 100000000, 'unixepoch') END,
       0, 0, (s.h / 1024) % 11, NULL, NULL, 90 + s.h % 80, 900000, 44100, 2, NULL, NULL,
       al.dateAdded, al.dateAdded, al.dateAdded
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM _n WHERE i <= (SELECT SG FROM _k)) s
JOIN album al ON al.idAlbum = (s.i - 1) / 10 + 1
JOIN _w w1 ON w1.k = (s.h / 4096) % 16 JOIN _w w2 ON w2.k = (s.h / 131072) % 16;

INSERT OR IGNORE INTO song_artist(idArtist, idSong, idRole, iOrder, strArtist)
SELECT x.idArtist, s.idSong, 1, 0, s.strArtistDisp FROM song s JOIN _alb x ON x.idAlbum = s.idAlbum
UNION ALL
SELECT ((h / 64) % ((SELECT AR FROM _k) - 1)) + 2, idSong, 1, 1, 'Featured' FROM (SELECT idSong, (idSong * 2654435761) % 4294967296 AS h FROM song) WHERE (h / 32) % 5 = 0
UNION ALL
SELECT ((h / 8192) % 300) + 2, idSong, 2, 0, 'Composer' FROM (SELECT idSong, (idSong * 2654435761) % 4294967296 AS h FROM song) WHERE (h / 1024) % 8 = 0;

INSERT OR IGNORE INTO song_genre(idGenre, idSong, iOrder)
SELECT (x.h / 4) % 19 + 21, s.idSong, 0 FROM song s JOIN _alb x ON x.idAlbum = s.idAlbum
UNION ALL
SELECT (h / 512) % 19 + 21, idSong, 1 FROM (SELECT idSong, (idSong * 2654435761) % 4294967296 AS h FROM song) WHERE (h / 8) % 10 < 3;

-- ---------------------------------------------------------------- art (shared table)
INSERT INTO art(media_id, media_type, type, url)
SELECT idMovie, 'movie', 'poster', 'https://image.tmdb.org/t/p/original/m' || idMovie || '.jpg' FROM movie
UNION ALL SELECT idMovie, 'movie', 'fanart', 'https://image.tmdb.org/t/p/original/f' || idMovie || '.jpg' FROM movie
UNION ALL SELECT idShow, 'tvshow', t.v, 'https://image.tmdb.org/t/p/original/' || t.v || idShow || '.jpg' FROM tvshow, (SELECT 'poster' AS v UNION ALL SELECT 'fanart' UNION ALL SELECT 'banner') t
UNION ALL SELECT idSeason, 'season', 'poster', 'https://image.tmdb.org/t/p/original/s' || idSeason || '.jpg' FROM seasons
UNION ALL SELECT actor_id, 'actor', 'thumb', 'https://image.tmdb.org/t/p/original/a' || actor_id || '.jpg' FROM actor WHERE actor_id % 3 = 0
UNION ALL SELECT idAlbum, 'album', 'thumb', printf('smb://nas/music/%05d/cover.jpg', idAlbum) FROM album
UNION ALL SELECT idArtist, 'artist', 'thumb', 'https://fanart.example/a' || idArtist || '.jpg' FROM artist WHERE idArtist % 2 = 0;

DROP TABLE _alb;
DROP TABLE _w;
DROP TABLE _k;
DROP TABLE _n;
COMMIT;
