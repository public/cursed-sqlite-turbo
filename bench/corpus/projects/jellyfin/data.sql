-- Synthetic data for jellyfin (10.10.x SqliteItemRepository schema). Deterministic: values come from multiplicative
-- hashes of a row counter, different columns from different bits. _cfg.scale multiplies the counts.
-- Scale 1: 4 libraries (Movies, TV Shows, Music, Kids), 4k movies, 200 series / 800 seasons / 9.6k episodes,
-- 200 artists / 800 albums / 8k tracks, 2k persons, 20 genres, 12 music genres, 40 studios; ~55k ItemValues,
-- ~34k People rows, ~70k AncestorIds, ~5k UserDatas for 5 users, ~35k mediastreams, 32k chapters.
-- Guids are 16-byte blobs (as Microsoft.Data.Sqlite binds System.Guid); TopParentId / AncestorIdText hold the
-- lower-case "N" hex form; dates use the app's "yyyy-MM-dd HH:mm:ss.FFFFFFFK" text format.
PRAGMA cache_size = -262144;
BEGIN;

CREATE TEMP TABLE ids(kind INT, i INT, guid BLOB, hx TEXT, h INT, PRIMARY KEY (kind, i)) WITHOUT ROWID;
CREATE TEMP TABLE cnt(kind INT PRIMARY KEY, n INT);
INSERT INTO cnt VALUES (1, 4), (2, 4000*(SELECT scale FROM _cfg)), (3, 200*(SELECT scale FROM _cfg)),
  (4, 800*(SELECT scale FROM _cfg)), (5, 9600*(SELECT scale FROM _cfg)), (6, 200*(SELECT scale FROM _cfg)),
  (7, 800*(SELECT scale FROM _cfg)), (8, 8000*(SELECT scale FROM _cfg)), (9, 20), (10, 12), (11, 40),
  (12, 2000*(SELECT scale FROM _cfg));
-- kinds: 1 library, 2 movie, 3 series, 4 season, 5 episode, 6 artist, 7 album, 8 track, 9 genre, 10 music genre,
--        11 studio, 12 person
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT max(n) FROM cnt))
INSERT INTO ids(kind, i, guid, hx, h)
SELECT kind, i, unhex(x), lower(x), h FROM (
  SELECT c.kind, n.i, ((n.i * 2654435761 + c.kind * 40503) % 4294967296) AS h,
         printf('%08x%04x4%03x%04x%012x', (n.i * 2654435761 + c.kind * 97) % 4294967296, c.kind,
                (n.i * 40503) % 4096, 32768 + (n.i * 7919) % 16384, n.i) AS x
  FROM cnt c JOIN n ON n.i <= c.n);

CREATE TEMP TABLE words(k INT PRIMARY KEY, w TEXT, noun TEXT);
INSERT INTO words VALUES (0,'Star','Kingdom'),(1,'Night','Road'),(2,'Shadow','Empire'),(3,'River','Garden'),
  (4,'Last','Machine'),(5,'Dark','Horizon'),(6,'Golden','Island'),(7,'Silent','Protocol'),(8,'Lost','Legacy'),
  (9,'Iron','Witness'),(10,'Wild','Harbor'),(11,'Broken','Signal'),(12,'Crimson','Frontier'),(13,'Hidden','Tide'),
  (14,'Frozen','Station'),(15,'Electric','Requiem');
CREATE TEMP TABLE genres(k INT PRIMARY KEY, name TEXT);
INSERT INTO genres VALUES (0,'Action'),(1,'Adventure'),(2,'Animation'),(3,'Comedy'),(4,'Crime'),(5,'Documentary'),
  (6,'Drama'),(7,'Family'),(8,'Fantasy'),(9,'History'),(10,'Horror'),(11,'Music'),(12,'Mystery'),(13,'Romance'),
  (14,'Science Fiction'),(15,'Thriller'),(16,'War'),(17,'Western'),(18,'Sci-Fi & Fantasy'),(19,'Kids');
CREATE TEMP TABLE mgenres(k INT PRIMARY KEY, name TEXT);
INSERT INTO mgenres VALUES (0,'Rock'),(1,'Jazz'),(2,'Electronic'),(3,'Hip-Hop'),(4,'Classical'),(5,'Pop'),(6,'Folk'),
  (7,'Metal'),(8,'Soul'),(9,'Ambient'),(10,'Blues'),(11,'Reggae');
CREATE TEMP TABLE ratings(k INT PRIMARY KEY, r TEXT, v INT);
INSERT INTO ratings VALUES (0,'G',1),(1,'PG',5),(2,'PG-13',7),(3,'R',9),(4,'NC-17',10),(5,NULL,NULL);

-- ---------------------------------------------------------------- libraries (CollectionFolder)
INSERT INTO TypedBaseItems(guid, type, data, ParentId, Path, Name, SortName, CleanName, IsFolder, IsVirtualItem,
  DateCreated, DateModified, PresentationUniqueKey, UserDataKey, TopParentId, InheritedParentalRatingValue)
SELECT guid, 'MediaBrowser.Controller.Entities.CollectionFolder',
       json_object('CollectionType', CASE i WHEN 1 THEN 'movies' WHEN 2 THEN 'tvshows' WHEN 3 THEN 'music' ELSE 'movies' END),
       NULL, '/config/root/default/' || CASE i WHEN 1 THEN 'Movies' WHEN 2 THEN 'TV Shows' WHEN 3 THEN 'Music' ELSE 'Kids' END,
       CASE i WHEN 1 THEN 'Movies' WHEN 2 THEN 'TV Shows' WHEN 3 THEN 'Music' ELSE 'Kids' END,
       CASE i WHEN 1 THEN 'movies' WHEN 2 THEN 'tv shows' WHEN 3 THEN 'music' ELSE 'kids' END,
       CASE i WHEN 1 THEN 'movies' WHEN 2 THEN 'tv shows' WHEN 3 THEN 'music' ELSE 'kids' END,
       1, 0, '2022-01-01 00:00:00Z', '2022-01-01 00:00:00Z', hx, hx, hx, 0
FROM ids WHERE kind = 1;

-- ---------------------------------------------------------------- movies (every 6th one lives in the Kids library)
INSERT INTO TypedBaseItems(guid, type, data, ParentId, Path, CommunityRating, IndexNumber, IsLocked, Name,
  OfficialRating, MediaType, Overview, PremiereDate, ProductionYear, Genres, InheritedParentalRatingValue, SortName,
  RunTimeTicks, Size, DateCreated, DateModified, Width, Height, DateLastRefreshed, DateLastSaved, IsInMixedFolder,
  Studios, IsFolder, TopParentId, CriticRating, CleanName, PresentationUniqueKey, OriginalTitle, IsVirtualItem,
  UserDataKey, ProviderIds, Images, TotalBitrate, Tags)
SELECT m.guid, 'MediaBrowser.Controller.Entities.Movies.Movie',
       json_object('Id', m.hx, 'VideoType', 'VideoFile', 'IsHD', json(CASE WHEN wid >= 1200 THEN 'true' ELSE 'false' END),
                   'Container', 'mkv', 'HasSubtitles', json(CASE WHEN (m.h / 64) % 2 = 0 THEN 'true' ELSE 'false' END)),
       lib.guid, '/media/' || lib.hx || '/' || nm || ' (' || yr || ')/' || nm || '.mkv',
       1 + ((m.h / 7) % 90) / 10.0, NULL, 0, nm,
       rt.r, 'Video', 'A film about ' || lower(wd.noun) || ' and ' || lower(wd2.w) || ' things.',
       printf('%d-%02d-%02d 00:00:00Z', yr, 1 + (m.h / 11) % 12, 1 + (m.h / 13) % 28), yr,
       g1.name || '|' || g2.name, rt.v, lower(nm),
       (5400 + (m.h / 17) % 3600) * 10000000, 1000000000 + (m.h % 900000000), dc, dc, wid, wid * 9 / 16, dc, dc, 0,
       'Studio ' || ((m.h / 19) % 40), 0, lib.hx, ((m.h / 23) % 100), lower(nm),
       CASE WHEN m.i % 50 = 7 THEN (SELECT hx FROM ids p WHERE p.kind = 2 AND p.i = m.i - 1) ELSE m.hx END,
       CASE WHEN (m.h / 29) % 10 = 0 THEN 'Le ' || wd.noun || ' ' || m.i END, 0,
       CAST(100000 + m.i AS TEXT), 'Tmdb=' || (100000 + m.i) || '|Imdb=tt' || printf('%07d', m.i * 7),
       '/config/metadata/library/' || substr(m.hx, 1, 2) || '/' || m.hx || '/poster.jpg*638400000000000000*Primary*1000*1500*eLJ8',
       8000000 + (m.h % 20000000), NULL
FROM (SELECT ids.*, CASE WHEN i % 6 = 0 THEN 4 ELSE 1 END AS libi,
             (SELECT w FROM words WHERE k = (h / 1024) % 16) || ' ' || (SELECT noun FROM words WHERE k = (h / 16384) % 16) || ' ' || i AS nm,
             1960 + (h / 131072) % 64 AS yr,
             CASE (h / 4) % 4 WHEN 0 THEN 3840 WHEN 1 THEN 1280 ELSE 1920 END AS wid,
             strftime('%Y-%m-%d %H:%M:%S', 1600000000 + i * (100000000 / (SELECT n FROM cnt WHERE kind = 2)) + (h % 3600), 'unixepoch') || '.0000000Z' AS dc
      FROM ids WHERE kind = 2) m
JOIN ids lib ON lib.kind = 1 AND lib.i = m.libi
JOIN words wd ON wd.k = (m.h / 1024) % 16 JOIN words wd2 ON wd2.k = (m.h / 256) % 16
JOIN genres g1 ON g1.k = CASE WHEN m.libi = 4 THEN 2 + ((m.h / 32) % 2) * 5 ELSE (m.h / 32) % 20 END
JOIN genres g2 ON g2.k = (m.h / 640) % 20
JOIN ratings rt ON rt.k = CASE WHEN m.libi = 4 THEN (m.h / 8192) % 2 ELSE (m.h / 8192) % 6 END;

-- ---------------------------------------------------------------- series / seasons / episodes (TV library)
INSERT INTO TypedBaseItems(guid, type, data, ParentId, Path, CommunityRating, Name, OfficialRating, Overview,
  PremiereDate, ProductionYear, Genres, InheritedParentalRatingValue, SortName, DateCreated, DateModified,
  DateLastMediaAdded, Studios, IsFolder, TopParentId, CleanName, PresentationUniqueKey, IsVirtualItem, UserDataKey,
  ProviderIds, Images)
SELECT s.guid, 'MediaBrowser.Controller.Entities.TV.Series',
       json_object('Id', s.hx, 'Status', CASE WHEN (s.h / 8) % 3 = 0 THEN 'Continuing' ELSE 'Ended' END, 'AirDays', json_array('Sunday')),
       lib.guid, '/media/tv/' || nm, 1 + ((s.h / 7) % 90) / 10.0, nm, rt.r, 'A show about ' || lower(wd.noun) || '.',
       printf('%d-01-01 00:00:00Z', 1990 + (s.h / 131072) % 34), 1990 + (s.h / 131072) % 34,
       g1.name || '|' || g2.name, rt.v, lower(nm), dc, dc, dc, 'Network ' || ((s.h / 19) % 40), 1, lib.hx, lower(nm),
       s.hx, 0, CAST(300000 + s.i AS TEXT), 'Tvdb=' || (300000 + s.i) || '|Tmdb=' || (500000 + s.i),
       '/config/metadata/library/' || substr(s.hx, 1, 2) || '/' || s.hx || '/poster.jpg*638400000000000000*Primary*680*1000*'
FROM (SELECT ids.*, (SELECT w FROM words WHERE k = (h / 1024) % 16) || ' ' || (SELECT noun FROM words WHERE k = (h / 16384) % 16) || ' Chronicles ' || i AS nm,
             strftime('%Y-%m-%d %H:%M:%S', 1550000000 + i * 400000, 'unixepoch') || '.0000000Z' AS dc
      FROM ids WHERE kind = 3) s
JOIN ids lib ON lib.kind = 1 AND lib.i = 2
JOIN words wd ON wd.k = (s.h / 1024) % 16
JOIN genres g1 ON g1.k = (s.h / 32) % 20 JOIN genres g2 ON g2.k = (s.h / 640) % 20
JOIN ratings rt ON rt.k = (s.h / 8192) % 5;

INSERT INTO TypedBaseItems(guid, type, data, ParentId, Path, IndexNumber, Name, SortName, DateCreated, DateModified,
  IsFolder, TopParentId, CleanName, PresentationUniqueKey, IsVirtualItem, SeriesName, UserDataKey, SeriesId,
  SeriesPresentationUniqueKey, InheritedParentalRatingValue)
SELECT se.guid, 'MediaBrowser.Controller.Entities.TV.Season', json_object('Id', se.hx), sr.guid, sr.Path || '/Season ' || k,
       k, 'Season ' || k, 'season ' || printf('%03d', k), sr.DateCreated, sr.DateCreated, 1, sr.TopParentId,
       'season ' || k, sr.PresentationUniqueKey || '-' || printf('%03d', k), 0, sr.Name, sr.UserDataKey || printf('%03d', k),
       sr.guid, sr.PresentationUniqueKey, sr.InheritedParentalRatingValue
FROM (SELECT ids.*, (i - 1) / 4 + 1 AS si, (i - 1) % 4 + 1 AS k FROM ids WHERE kind = 4) se
JOIN ids sid ON sid.kind = 3 AND sid.i = se.si
JOIN TypedBaseItems sr ON sr.guid = sid.guid;

INSERT INTO TypedBaseItems(guid, type, data, ParentId, Path, CommunityRating, IndexNumber, Name, OfficialRating,
  MediaType, Overview, ParentIndexNumber, PremiereDate, ProductionYear, InheritedParentalRatingValue, SortName,
  RunTimeTicks, Size, DateCreated, DateModified, Width, Height, IsInMixedFolder, IsFolder, TopParentId, CleanName,
  PresentationUniqueKey, IsVirtualItem, SeriesName, UserDataKey, SeasonName, SeasonId, SeriesId,
  SeriesPresentationUniqueKey, Images)
SELECT e.guid, 'MediaBrowser.Controller.Entities.TV.Episode',
       json_object('Id', e.hx, 'VideoType', 'VideoFile', 'AirsBeforeSeasonNumber', NULL),
       sn.guid, CASE WHEN virt THEN NULL ELSE sn.Path || printf('/S%02dE%02d.mkv', sn.IndexNumber, ep) END,
       5 + ((e.h / 7) % 50) / 10.0, ep, 'Episode ' || ep || ' ' || wd.noun, sr.OfficialRating, 'Video',
       'Things happen to the ' || lower(wd.noun) || '.', sn.IndexNumber,
       strftime('%Y-%m-%d 00:00:00Z', 1100000000 + e.i * 40000, 'unixepoch'), 2004 + e.i * 40000 / 31536000,
       sr.InheritedParentalRatingValue, printf('%03d - %04d - episode %d', sn.IndexNumber, ep, ep),
       (2400 + (e.h / 17) % 1200) * 10000000, 400000000 + (e.h % 300000000), dc, dc, 1920, 1080, 0, 0, sr.TopParentId,
       lower('episode ' || ep || ' ' || wd.noun), e.hx, virt, sr.Name, sr.UserDataKey || printf('%03d%03d', sn.IndexNumber, ep),
       sn.Name, sn.guid, sr.guid, sr.PresentationUniqueKey,
       CASE WHEN virt THEN NULL ELSE '/config/metadata/library/' || substr(e.hx, 1, 2) || '/' || e.hx || '/thumb.jpg*638400000000000000*Primary*1920*1080*' END
FROM (SELECT ids.*, (i - 1) / 12 + 1 AS sni, (i - 1) % 12 + 1 AS ep,
             CASE WHEN (i - 1) % 12 >= 10 AND (h / 4) % 3 = 0 THEN 1 ELSE 0 END AS virt,
             strftime('%Y-%m-%d %H:%M:%S', 1580000000 + i * (110000000 / (SELECT n FROM cnt WHERE kind = 5)), 'unixepoch') || '.0000000Z' AS dc
      FROM ids WHERE kind = 5) e
JOIN ids snid ON snid.kind = 4 AND snid.i = e.sni
JOIN TypedBaseItems sn ON sn.guid = snid.guid
JOIN TypedBaseItems sr ON sr.guid = sn.SeriesId
JOIN words wd ON wd.k = (e.h / 1024) % 16;

-- ---------------------------------------------------------------- music: artists, albums, tracks
INSERT INTO TypedBaseItems(guid, type, data, ParentId, Path, Name, SortName, DateCreated, DateModified, IsFolder,
  TopParentId, CleanName, PresentationUniqueKey, IsVirtualItem, UserDataKey, ProviderIds)
SELECT a.guid, 'MediaBrowser.Controller.Entities.Audio.MusicArtist', json_object('Id', a.hx), lib.guid,
       '/media/music/' || nm, nm, lower(nm), '2023-01-01 00:00:00Z', '2023-01-01 00:00:00Z', 1, lib.hx, lower(nm),
       'MusicArtist-' || lower(nm), 0, 'Artist-Musicbrainz-' || a.hx, 'MusicBrainzArtist=' || a.hx
FROM (SELECT ids.*, (SELECT w FROM words WHERE k = (h / 1024) % 16) || ' ' || (SELECT noun FROM words WHERE k = (h / 64) % 16) || ' Band ' || i AS nm
      FROM ids WHERE kind = 6) a
JOIN ids lib ON lib.kind = 1 AND lib.i = 3;

INSERT INTO TypedBaseItems(guid, type, data, ParentId, Path, Name, SortName, ProductionYear, PremiereDate, Genres,
  DateCreated, DateModified, IsFolder, TopParentId, CleanName, PresentationUniqueKey, IsVirtualItem, UserDataKey,
  Artists, AlbumArtists, Album, Images, CommunityRating)
SELECT al.guid, 'MediaBrowser.Controller.Entities.Audio.MusicAlbum', json_object('Id', al.hx), ar.guid,
       ar.Path || '/' || nm, nm, lower(nm), 1970 + (al.h / 64) % 54, printf('%d-01-01 00:00:00Z', 1970 + (al.h / 64) % 54),
       mg.name, dc, dc, 1, ar.TopParentId, lower(nm), al.hx, 0, al.hx, ar.Name, ar.Name, NULL,
       '/config/metadata/library/' || substr(al.hx, 1, 2) || '/' || al.hx || '/folder.jpg*638400000000000000*Primary*600*600*',
       ((al.h / 7) % 50) / 10.0
FROM (SELECT ids.*, 'Album ' || (SELECT noun FROM words WHERE k = (h / 1024) % 16) || ' ' || i AS nm,
             (i * 7) % (SELECT n FROM cnt WHERE kind = 6) + 1 AS ari,
             strftime('%Y-%m-%d %H:%M:%S', 1650000000 + i * (60000000 / (SELECT n FROM cnt WHERE kind = 7)), 'unixepoch') || '.0000000Z' AS dc
      FROM ids WHERE kind = 7) al
JOIN ids arid ON arid.kind = 6 AND arid.i = al.ari
JOIN TypedBaseItems ar ON ar.guid = arid.guid
JOIN mgenres mg ON mg.k = (al.h / 4096) % 12;

INSERT INTO TypedBaseItems(guid, type, data, ParentId, Path, IndexNumber, Name, MediaType, ParentIndexNumber,
  ProductionYear, Genres, SortName, RunTimeTicks, Size, DateCreated, DateModified, IsFolder, TopParentId, CleanName,
  PresentationUniqueKey, IsVirtualItem, UserDataKey, Artists, AlbumArtists, Album, LUFS, NormalizationGain)
SELECT t.guid, 'MediaBrowser.Controller.Entities.Audio.Audio', json_object('Id', t.hx), al.guid,
       al.Path || printf('/%02d - Track %d.flac', tr, t.i), tr, 'Track ' || t.i, 'Audio', 1, al.ProductionYear, al.Genres,
       printf('%04d - track %d', tr, t.i), (1800 + (t.h / 17) % 2400) * 10000000, 20000000 + (t.h % 40000000),
       al.DateCreated, al.DateCreated, 0, al.TopParentId, 'track ' || t.i, t.hx, 0, al.Album || t.hx,
       al.Artists || CASE WHEN (t.h / 32) % 9 = 0 THEN '|' || (SELECT Name FROM TypedBaseItems x WHERE x.guid = (SELECT guid FROM ids WHERE kind = 6 AND i = (t.h / 512) % (SELECT n FROM cnt WHERE kind = 6) + 1)) ELSE '' END,
       al.AlbumArtists, al.Name, -14 - ((t.h / 8) % 60) / 10.0, -2.5
FROM (SELECT ids.*, (i - 1) / 10 + 1 AS ali, (i - 1) % 10 + 1 AS tr FROM ids WHERE kind = 8) t
JOIN ids alid ON alid.kind = 7 AND alid.i = t.ali
JOIN TypedBaseItems al ON al.guid = alid.guid;

-- ---------------------------------------------------------------- items-by-name: genres, music genres, studios, persons
INSERT INTO TypedBaseItems(guid, type, data, Path, Name, SortName, CleanName, DateCreated, DateModified, IsFolder,
  PresentationUniqueKey, IsVirtualItem, UserDataKey)
SELECT ids.guid, 'MediaBrowser.Controller.Entities.Genre', json_object('Id', ids.hx), '/config/metadata/Genre/' || g.name,
       g.name, lower(g.name), lower(g.name), '2022-01-01 00:00:00Z', '2022-01-01 00:00:00Z', 1, 'Genre-' || lower(g.name), 0,
       'Genre-' || g.name
FROM ids JOIN genres g ON g.k = ids.i - 1 WHERE ids.kind = 9
UNION ALL
SELECT ids.guid, 'MediaBrowser.Controller.Entities.Audio.MusicGenre', json_object('Id', ids.hx), '/config/metadata/MusicGenre/' || g.name,
       g.name, lower(g.name), lower(g.name), '2022-01-01 00:00:00Z', '2022-01-01 00:00:00Z', 1, 'MusicGenre-' || lower(g.name), 0,
       'MusicGenre-' || g.name
FROM ids JOIN mgenres g ON g.k = ids.i - 1 WHERE ids.kind = 10
UNION ALL
SELECT guid, 'MediaBrowser.Controller.Entities.Studio', json_object('Id', hx), '/config/metadata/Studio/Studio ' || (i - 1),
       'Studio ' || (i - 1), 'studio ' || (i - 1), 'studio ' || (i - 1), '2022-01-01 00:00:00Z', '2022-01-01 00:00:00Z', 1,
       'Studio-studio ' || (i - 1), 0, 'Studio-Studio ' || (i - 1)
FROM ids WHERE kind = 11
UNION ALL
SELECT guid, 'MediaBrowser.Controller.Entities.Person', json_object('Id', hx), '/config/metadata/People/' || nm, nm, lower(nm),
       lower(nm), '2022-06-01 00:00:00Z', '2022-06-01 00:00:00Z', 1, 'Person-' || nm, 0, 'Person-' || nm
FROM (SELECT ids.*, (SELECT w FROM words WHERE k = (h / 1024) % 16) || ' ' || (SELECT noun FROM words WHERE k = (h / 32) % 16) || ' ' || i AS nm
      FROM ids WHERE kind = 12);

-- ---------------------------------------------------------------- ItemValues (0 Artists, 1 AlbumArtists, 2 Genres, 3 Studios, 4 Tags, 6 InheritedTags)
INSERT INTO ItemValues(ItemId, Type, Value, CleanValue)
SELECT guid, 2, v, lower(v) FROM (
  SELECT guid, substr(Genres, 1, instr(Genres, '|') - 1) AS v FROM TypedBaseItems
   WHERE type IN ('MediaBrowser.Controller.Entities.Movies.Movie', 'MediaBrowser.Controller.Entities.TV.Series')
  UNION
  SELECT guid, substr(Genres, instr(Genres, '|') + 1) FROM TypedBaseItems
   WHERE type IN ('MediaBrowser.Controller.Entities.Movies.Movie', 'MediaBrowser.Controller.Entities.TV.Series')
  UNION ALL
  SELECT guid, Genres FROM TypedBaseItems
   WHERE type IN ('MediaBrowser.Controller.Entities.Audio.MusicAlbum', 'MediaBrowser.Controller.Entities.Audio.Audio'));

INSERT INTO ItemValues(ItemId, Type, Value, CleanValue)
SELECT guid, 3, Studios, lower(Studios) FROM TypedBaseItems WHERE Studios IS NOT NULL;

INSERT INTO ItemValues(ItemId, Type, Value, CleanValue)
SELECT guid, 1, AlbumArtists, lower(AlbumArtists) FROM TypedBaseItems WHERE AlbumArtists IS NOT NULL
UNION ALL
SELECT guid, 0, substr(Artists, 1, CASE WHEN instr(Artists, '|') > 0 THEN instr(Artists, '|') - 1 ELSE length(Artists) END),
       lower(substr(Artists, 1, CASE WHEN instr(Artists, '|') > 0 THEN instr(Artists, '|') - 1 ELSE length(Artists) END))
FROM TypedBaseItems WHERE Artists IS NOT NULL
UNION ALL
SELECT guid, 0, substr(Artists, instr(Artists, '|') + 1), lower(substr(Artists, instr(Artists, '|') + 1))
FROM TypedBaseItems WHERE instr(Artists, '|') > 0;

-- tags on ~1/8 of movies and series, plus the inherited copies (type 6) that UpdateInheritedValues maintains
INSERT INTO ItemValues(ItemId, Type, Value, CleanValue)
SELECT guid, t, v, lower(v) FROM (
  SELECT guid, CASE (CAST(substr(PresentationUniqueKey, 1, 6) AS INT) + length(Name)) % 4
                 WHEN 0 THEN 'Gore' WHEN 1 THEN 'Christmas' WHEN 2 THEN '4K Remaster' ELSE 'Based on a Book' END AS v
  FROM TypedBaseItems
  WHERE type IN ('MediaBrowser.Controller.Entities.Movies.Movie', 'MediaBrowser.Controller.Entities.TV.Series')
    AND (unicode(substr(hex(guid), 3, 1)) + length(Name)) % 8 = 0) x,
  (SELECT 4 AS t UNION ALL SELECT 6);

-- ---------------------------------------------------------------- AncestorIds
INSERT INTO AncestorIds(ItemId, AncestorId, AncestorIdText)
SELECT guid, ParentId, lower(hex(ParentId)) FROM TypedBaseItems WHERE ParentId IS NOT NULL
UNION ALL
SELECT guid, unhex(TopParentId), TopParentId FROM TypedBaseItems
 WHERE TopParentId IS NOT NULL AND ParentId IS NOT NULL AND unhex(TopParentId) <> ParentId
   AND type NOT IN ('MediaBrowser.Controller.Entities.CollectionFolder')
UNION ALL
SELECT guid, SeriesId, lower(hex(SeriesId)) FROM TypedBaseItems WHERE type = 'MediaBrowser.Controller.Entities.TV.Episode'
UNION ALL
SELECT t.guid, al.ParentId, lower(hex(al.ParentId)) FROM TypedBaseItems t JOIN TypedBaseItems al ON al.guid = t.ParentId
 WHERE t.type = 'MediaBrowser.Controller.Entities.Audio.Audio';

-- ---------------------------------------------------------------- People
INSERT INTO People(ItemId, Name, Role, PersonType, SortOrder, ListOrder)
SELECT it.guid, p.Name, CASE WHEN k.k < 6 THEN 'Character ' || k.k END,
       CASE WHEN k.k < 6 THEN 'Actor' WHEN k.k = 6 THEN 'Director' ELSE 'Writer' END, CASE WHEN k.k < 6 THEN k.k END, k.k
FROM (SELECT guid, CAST(substr(UserDataKey, 1, 9) AS INT) AS seed FROM TypedBaseItems
       WHERE type IN ('MediaBrowser.Controller.Entities.Movies.Movie', 'MediaBrowser.Controller.Entities.TV.Series')) it
CROSS JOIN (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
      UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) k
CROSS JOIN ids pid ON pid.kind = 12
            AND pid.i = 1 + CASE WHEN k.k < 2 THEN ((it.seed * 13 + k.k * 7) % 150)
                                 ELSE ((it.seed * 2654435761 / (k.k + 1)) % (SELECT n FROM cnt WHERE kind = 12)) END
CROSS JOIN TypedBaseItems p ON p.guid = pid.guid
WHERE k.k < 8 OR it.seed >= 300000;

-- ---------------------------------------------------------------- UserDatas (user 1 = heavy viewer, 2 = kid profile, 3-5 light)
-- user 1: episodes of 2 in 5 series watched up to a per-series point, the next one in progress for half of those
INSERT INTO UserDatas(key, userId, rating, played, playCount, isFavorite, playbackPositionTicks, lastPlayedDate)
SELECT e.UserDataKey, 1, NULL, CASE WHEN pos <= w THEN 1 ELSE 0 END, CASE WHEN pos <= w THEN 1 ELSE 0 END, 0,
       CASE WHEN pos = w + 1 THEN 9000000000 + si * 1000000 ELSE 0 END,
       strftime('%Y-%m-%d %H:%M:%S', 1690000000 + si * 97003 + pos * 2400, 'unixepoch') || '.0000000Z'
FROM (SELECT e.UserDataKey, s.si, (e.ParentIndexNumber - 1) * 12 + e.IndexNumber AS pos, (s.si * 37) % 40 + 1 AS w
      FROM TypedBaseItems e JOIN (SELECT i AS si, guid FROM ids WHERE kind = 3) s ON s.guid = e.SeriesId
      WHERE e.type = 'MediaBrowser.Controller.Entities.TV.Episode' AND s.si % 5 IN (0, 1) AND e.IsVirtualItem = 0) e
WHERE pos <= w OR (pos = w + 1 AND si % 5 = 0);

-- user 1 movies: played / in progress / favourite; user 2 (kid) kids-library movies; users 3-5 a few played movies
INSERT INTO UserDatas(key, userId, rating, played, playCount, isFavorite, playbackPositionTicks, lastPlayedDate)
SELECT key, u, CASE WHEN m % 11 = 0 THEN (m % 10) * 1.0 END, pl, pl + (m % 3) * pl, fav, pos,
       CASE WHEN pl = 1 OR pos > 0 THEN strftime('%Y-%m-%d %H:%M:%S', 1680000000 + m * 3511 + u * 7, 'unixepoch') || '.0000000Z' END
FROM (SELECT UserDataKey AS key, CAST(UserDataKey AS INT) - 100000 AS m, u.u,
             CASE WHEN u.u = 1 THEN ((CAST(UserDataKey AS INT) - 100000) % 7 = 0)
                  WHEN u.u = 2 THEN ((CAST(UserDataKey AS INT) - 100000) % 5 = 0)
                  ELSE ((CAST(UserDataKey AS INT) * u.u) % 97 = 0) END AS pl,
             CASE WHEN u.u IN (1, 2) AND (CAST(UserDataKey AS INT) - 100000) % 31 = 0 THEN 1 ELSE 0 END AS fav,
             CASE WHEN u.u IN (1, 2) AND (CAST(UserDataKey AS INT) - 100000) % 7 <> 0 AND (CAST(UserDataKey AS INT) - 100000) % 13 = 0
                  THEN 30000000000 + (CAST(UserDataKey AS INT) % 1000) * 10000000 ELSE 0 END AS pos
      FROM TypedBaseItems JOIN (SELECT 1 AS u UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5) u
      WHERE type = 'MediaBrowser.Controller.Entities.Movies.Movie'
        AND (u.u <> 2 OR TopParentId = (SELECT hx FROM ids WHERE kind = 1 AND i = 4)))
WHERE pl OR fav OR pos > 0;

-- user 1: favourite series, persons, albums
INSERT INTO UserDatas(key, userId, rating, played, playCount, isFavorite, playbackPositionTicks, lastPlayedDate)
SELECT UserDataKey, 1, NULL, 0, 0, 1, 0, NULL FROM TypedBaseItems
WHERE (type = 'MediaBrowser.Controller.Entities.TV.Series' AND CAST(UserDataKey AS INT) % 9 = 0)
   OR (type = 'MediaBrowser.Controller.Entities.Person' AND length(Name) % 7 = 0)
   OR (type = 'MediaBrowser.Controller.Entities.Audio.MusicAlbum' AND (unicode(substr(UserDataKey, 5, 1)) + length(Name)) % 9 = 0);

-- ---------------------------------------------------------------- mediastreams (movies + episodes) and chapters (movies)
INSERT INTO mediastreams(ItemId, StreamIndex, StreamType, Codec, Language, ChannelLayout, Profile, AspectRatio, Path,
  IsInterlaced, BitRate, Channels, SampleRate, IsDefault, IsForced, IsExternal, Height, Width, AverageFrameRate,
  RealFrameRate, Level, PixelFormat, BitDepth, IsAnamorphic, RefFrames, IsAvc, TimeBase, ColorPrimaries, ColorSpace,
  ColorTransfer, IsHearingImpaired)
SELECT guid, s, CASE s WHEN 0 THEN 'Video' WHEN 1 THEN 'Audio' WHEN 2 THEN 'Audio' ELSE 'Subtitle' END,
       CASE s WHEN 0 THEN CASE WHEN Width >= 3840 THEN 'hevc' ELSE 'h264' END WHEN 1 THEN 'eac3' WHEN 2 THEN 'aac' ELSE 'subrip' END,
       CASE s WHEN 0 THEN NULL WHEN 1 THEN 'eng' WHEN 2 THEN CASE WHEN length(Name) % 2 = 0 THEN 'fre' ELSE 'ger' END ELSE 'eng' END,
       CASE WHEN s IN (1, 2) THEN '5.1' END, CASE WHEN s = 0 THEN 'High' END, CASE WHEN s = 0 THEN '16:9' END, NULL,
       0, CASE s WHEN 0 THEN 8000000 WHEN 3 THEN NULL ELSE 640000 END, CASE WHEN s IN (1, 2) THEN 6 END,
       CASE WHEN s IN (1, 2) THEN 48000 END, CASE WHEN s IN (0, 1) THEN 1 ELSE 0 END, 0, 0,
       CASE WHEN s = 0 THEN Height END, CASE WHEN s = 0 THEN Width END, CASE WHEN s = 0 THEN 23.976 END,
       CASE WHEN s = 0 THEN 23.976 END, CASE WHEN s = 0 THEN 41 END, CASE WHEN s = 0 THEN 'yuv420p' END,
       CASE WHEN s = 0 THEN 8 END, 0, CASE WHEN s = 0 THEN 1 END, CASE WHEN s = 0 THEN 1 END, '1/1000',
       CASE WHEN s = 0 THEN 'bt709' END, CASE WHEN s = 0 THEN 'bt709' END, CASE WHEN s = 0 THEN 'bt709' END, 0
FROM TypedBaseItems, (SELECT 0 AS s UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3)
WHERE (type = 'MediaBrowser.Controller.Entities.Movies.Movie')
   OR (type = 'MediaBrowser.Controller.Entities.TV.Episode' AND IsVirtualItem = 0 AND s < 2);

INSERT INTO Chapters2(ItemId, ChapterIndex, StartPositionTicks, Name, ImagePath, ImageDateModified)
SELECT guid, c, c * (RunTimeTicks / 8), 'Chapter ' || (c + 1),
       CASE WHEN length(Name) % 3 = 0 THEN '/config/data/chapters/' || lower(hex(guid)) || '/' || c || '.jpg' END,
       CASE WHEN length(Name) % 3 = 0 THEN DateCreated END
FROM TypedBaseItems, (SELECT 0 AS c UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                      UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7)
WHERE type = 'MediaBrowser.Controller.Entities.Movies.Movie';

COMMIT;
