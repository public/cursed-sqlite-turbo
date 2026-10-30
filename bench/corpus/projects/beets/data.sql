-- Synthetic data for beets. Deterministic (no random()): values come from multiplicative hashes of the row number,
-- different columns from different bits. _cfg.scale multiplies the row counts: 2,000 albums, 20,000 items (5 %
-- singletons), ~31k item_attributes, ~3.3k album_attributes at scale 1.
-- Paths are stored as BLOBs relative to the library root (normalize_path_for_db), multi-value fields joined with
-- beets' MULTI_VALUE_DELIMITER "\␀" (types.py:19).
BEGIN;

CREATE TEMP TABLE _artists(k INTEGER PRIMARY KEY, name TEXT, sort TEXT);
INSERT INTO _artists VALUES
 (0,'The Beatles','Beatles, The'),(1,'Radiohead',NULL),(2,'Björk',NULL),(3,'Miles Davis','Davis, Miles'),
 (4,'Aphex Twin',NULL),(5,'The Rolling Stones','Rolling Stones, The'),(6,'Nina Simone','Simone, Nina'),
 (7,'Daft Punk',NULL),(8,'Kraftwerk',NULL),(9,'Pink Floyd',NULL),(10,'John Coltrane','Coltrane, John'),
 (11,'Boards of Canada',NULL),(12,'Portishead',NULL),(13,'Massive Attack',NULL),(14,'Joni Mitchell','Mitchell, Joni'),
 (15,'Talking Heads',NULL),(16,'Burial',NULL),(17,'Sigur Rós',NULL),(18,'Fela Kuti','Kuti, Fela'),(19,'Can',NULL);
WITH RECURSIVE n(k) AS (SELECT 20 UNION ALL SELECT k+1 FROM n WHERE k < 299)
INSERT INTO _artists SELECT k, printf('Artist %03d', k), CASE WHEN k % 4 = 0 THEN printf('%03d, Artist', k) END FROM n;

CREATE TEMP TABLE _genres(k INTEGER PRIMARY KEY, g TEXT);
INSERT INTO _genres VALUES (0,'Rock'),(1,'Rock' || char(92) || '␀' || 'Pop'),(2,'Jazz'),(3,'Electronic'),
 (4,'Electronic' || char(92) || '␀' || 'Ambient'),(5,'Hip-Hop'),(6,'Folk'),(7,'Classical'),(8,'Soul' || char(92) || '␀' || 'Funk'),(9,'');

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n),
a AS (SELECT m.i, m.h, ar.name, ar.sort, g.g, 1960 + (m.h / 4096) % 65 AS yr
      FROM m JOIN _artists ar ON ar.k = CASE WHEN (m.h / 64) % 4 = 0 THEN (m.h / 256) % 20 ELSE m.h % 300 END
             JOIN _genres g ON g.k = (m.h / 1048576) % 10)
INSERT INTO albums(id, added, album, albumartist, albumartist_credit, albumartist_sort, albumartists, albumartists_credit,
                   albumartists_sort, albumdisambig, albumstatus, albumtype, albumtypes, artpath, asin, barcode, catalognum,
                   comp, country, day, discogs_albumid, discogs_artistid, discogs_labelid, disctotal, genres, label, language,
                   mb_albumartistid, mb_albumartistids, mb_albumid, mb_releasegroupid, month, original_day, original_month,
                   original_year, r128_album_gain, release_group_title, releasegroupdisambig, rg_album_gain, rg_album_peak,
                   script, style, year)
SELECT i, 1600000000.0 + i * 41000 + (h % 3600), printf('Album %d %s', i, CASE (h / 32) % 4 WHEN 0 THEN 'Live' WHEN 1 THEN 'Sessions' WHEN 2 THEN 'Remastered' ELSE 'Vol. 1' END),
       name, name, coalesce(sort, ''), name, name, coalesce(sort, ''), CASE WHEN h % 7 = 0 THEN 'deluxe edition' ELSE '' END, 'Official',
       CASE (h / 8) % 6 WHEN 0 THEN 'ep' WHEN 1 THEN 'compilation' ELSE 'album' END,
       CASE (h / 8) % 6 WHEN 0 THEN 'ep' WHEN 1 THEN 'album; compilation' ELSE 'album' END,
       CASE WHEN (h / 16) % 3 = 0 THEN NULL ELSE CAST(printf('%s/Album %d/cover.jpg', name, i) AS BLOB) END,
       '', printf('%012d', h % 1000000000000), printf('CAT-%04d', h % 10000),
       CASE WHEN (h / 8) % 6 = 1 THEN 1 ELSE 0 END, CASE (h / 512) % 4 WHEN 0 THEN 'GB' WHEN 1 THEN 'US' WHEN 2 THEN 'DE' ELSE 'XW' END,
       1 + h % 28, 0, 0, 0, 1 + (h / 2) % 2, g, printf('Label %d', (h / 128) % 50), 'eng',
       printf('%08x-0000-4000-8000-%012x', (h * 7) % 4294967296, h), printf('%08x-0000-4000-8000-%012x', (h * 7) % 4294967296, h),
       printf('%08x-1111-4000-8000-%012x', h, i), printf('%08x-2222-4000-8000-%012x', h, i),
       1 + (h / 4) % 12, 1 + h % 28, 1 + (h / 4) % 12, yr, NULL, printf('Album %d', i), '', -6.5 + (h % 100) / 10.0, 0.98,
       'Latn', '', yr
FROM a;

-- 10 tracks per album, every 20th item a singleton
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2246822519) % 4294967296 AS h, (i - 1) / 10 + 1 AS aid, (i - 1) % 10 + 1 AS trk FROM n),
t AS (SELECT m.*, al.*, al.id AS al_id,
             CASE ((m.aid * 2246822519) % 4294967296 / 65536) % 10 WHEN 0 THEN 'FLAC' WHEN 1 THEN 'FLAC' WHEN 2 THEN 'FLAC' WHEN 3 THEN 'AAC' ELSE 'MP3' END AS fmt,
             printf('Song %d %s', m.i, CASE (m.h / 16) % 5 WHEN 0 THEN 'Love' WHEN 1 THEN 'Night' WHEN 2 THEN 'Revolution' WHEN 3 THEN 'Blue' ELSE 'Interlude' END) AS ttl
      FROM m JOIN albums al ON al.id = m.aid)
INSERT INTO items(id, acoustid_fingerprint, acoustid_id, added, album, album_id, albumartist, albumartist_credit, albumartist_sort,
                  albumartists, albumartists_credit, albumartists_sort, albumdisambig, albumstatus, albumtype, albumtypes,
                  arrangers, artist, artist_credit, artist_sort, artists, asin, barcode, bitdepth, bitrate, bitrate_mode, bpm,
                  catalognum, channels, comments, comp, composers, country, day, disc, disctitle, disctotal, encoder, format,
                  genres, grouping, initial_key, isrc, label, language, length, lyrics, mb_albumartistid, mb_albumid,
                  mb_artistid, mb_releasegroupid, mb_releasetrackid, mb_trackid, media, month, mtime, original_day,
                  original_month, original_year, path, rg_track_gain, rg_track_peak, rg_album_gain, rg_album_peak, samplerate,
                  script, style, subtitle, title, track, tracktotal, work, year)
SELECT i, '', '', added + trk, album, CASE WHEN i % 20 = 0 THEN NULL ELSE al_id END, albumartist, albumartist_credit, albumartist_sort,
       albumartists, albumartists_credit, albumartists_sort, albumdisambig, albumstatus, albumtype, albumtypes,
       '', CASE WHEN (h / 128) % 9 = 0 THEN albumartist || ' feat. Guest' ELSE albumartist END, albumartist, albumartist_sort, albumartist,
       '', barcode, CASE WHEN fmt = 'FLAC' THEN 16 + 8 * ((h / 4) % 2) ELSE 0 END,
       CASE WHEN fmt = 'FLAC' THEN 900000 + h % 500000 WHEN fmt = 'AAC' THEN 256000 ELSE 320000 - 128000 * ((h / 8) % 2) END,
       CASE WHEN fmt = 'MP3' THEN 'CBR' ELSE '' END, 80 + h % 100, catalognum, 2,
       CASE WHEN (h / 1024) % 13 = 0 THEN 'ripped from vinyl' ELSE '' END, comp, '', country, day,
       1 + (trk > 5 AND disctotal = 2), '', disctotal, CASE WHEN fmt = 'MP3' THEN 'LAME3.100' ELSE '' END, fmt,
       genres, '', CASE (h / 32) % 4 WHEN 0 THEN 'Am' WHEN 1 THEN 'C' WHEN 2 THEN 'F#m' ELSE '' END, printf('GB%010d', h % 10000000000),
       label, language, 120.0 + (h % 360) + (h / 7 % 1000) / 1000.0, CASE WHEN (h / 2048) % 5 = 0 THEN 'la la la ' || ttl ELSE '' END,
       mb_albumartistid, mb_albumid, mb_albumartistid, mb_releasegroupid, printf('%08x-3333-4000-8000-%012x', h, i),
       printf('%08x-4444-4000-8000-%012x', h, i), CASE WHEN (h / 4096) % 4 = 0 THEN 'Vinyl' ELSE 'CD' END, month,
       1650000000.0 + (h % 120000000), original_day, original_month, original_year,
       CAST(printf('%s/%s/%02d %s.%s', albumartist, album, trk, ttl, lower(CASE fmt WHEN 'AAC' THEN 'm4a' ELSE fmt END)) AS BLOB),
       -7.0 + (h % 80) / 10.0, 0.95, rg_album_gain, rg_album_peak, CASE WHEN fmt = 'FLAC' THEN 44100 + 51900 * ((h / 16) % 2) ELSE 44100 END,
       script, style, '', ttl, trk, 10, '', year
FROM t;

-- flexible attributes: every item from the MusicBrainz source; plays/ratings/moods on subsets
INSERT INTO item_attributes(entity_id, key, value)
SELECT id, 'data_source', CASE WHEN id % 17 = 0 THEN 'Discogs' ELSE 'MusicBrainz' END FROM items
UNION ALL
SELECT id, 'play_count', CAST(((id * 2654435761) % 4294967296) / 256 % 60 AS TEXT) FROM items WHERE ((id * 2654435761) % 4294967296) % 3 = 0
UNION ALL
SELECT id, 'rating', CAST(1 + ((id * 2654435761) % 4294967296) / 4096 % 5 AS TEXT) FROM items WHERE ((id * 2654435761) % 4294967296) / 16 % 4 = 0
UNION ALL
SELECT id, 'mood', CASE ((id * 2654435761) % 4294967296) / 65536 % 4 WHEN 0 THEN 'happy' WHEN 1 THEN 'sad' WHEN 2 THEN 'energetic' ELSE 'calm' END
FROM items WHERE ((id * 2654435761) % 4294967296) / 1024 % 5 = 0;

INSERT INTO album_attributes(entity_id, key, value)
SELECT id, 'data_source', 'MusicBrainz' FROM albums
UNION ALL
SELECT id, 'data_url', 'https://musicbrainz.org/release/' || mb_albumid FROM albums WHERE id % 3 = 0
UNION ALL
SELECT id, 'fetchart_source', 'coverart' FROM albums WHERE artpath IS NOT NULL AND id % 2 = 0;

INSERT INTO migrations(name, table_name) VALUES ('multi_genre_field', 'items'), ('multi_genre_field', 'albums'),
 ('relative_path', 'items'), ('relative_path', 'albums');

DROP TABLE _artists;
DROP TABLE _genres;
COMMIT;
