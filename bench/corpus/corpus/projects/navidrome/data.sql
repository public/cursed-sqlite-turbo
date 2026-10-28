-- Synthetic data for navidrome. Deterministic (no random()): values come from multiplicative hashes of the row
-- number, different columns from different bits. _cfg.scale multiplies the row counts.
-- Scale 1: 3 libraries, 20 users, 1000 artists, 3000 albums, 30k tracks (10 per album), 16 genres,
-- ~36k track/album/artist annotations, 60 playlists (+2 smart), 40k scrobbles, 2.4k album artwork rows.
-- The FTS5 tables are filled by the app's own triggers (schema.sql) as rows are inserted.
BEGIN;

CREATE TEMP TABLE w(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO w VALUES (0,'Love'),(1,'Song'),(2,'Night'),(3,'Blue'),(4,'Dream'),(5,'Fire'),(6,'Heart'),(7,'Road'),
  (8,'Rain'),(9,'Light'),(10,'City'),(11,'Summer'),(12,'Midnight'),(13,'River'),(14,'Gold'),(15,'Echo'),
  (16,'Shadow'),(17,'Ocean'),(18,'Morning'),(19,'Wild'),(20,'Silver'),(21,'Desert'),(22,'Electric'),(23,'Home'),
  (24,'Stone'),(25,'Glass'),(26,'Winter'),(27,'Satellite'),(28,'Ghost'),(29,'Paper'),(30,'Velvet'),(31,'Machine');
CREATE TEMP TABLE cjk(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO cjk VALUES (0,'夜の歌'),(1,'青い空'),(2,'恋の歌'),(3,'雨の街'),(4,'光と影'),(5,'春の風');
CREATE TEMP TABLE genre(k INTEGER PRIMARY KEY, name TEXT);
INSERT INTO genre VALUES (0,'Rock'),(1,'Jazz'),(2,'Pop'),(3,'Electronic'),(4,'Hip-Hop'),(5,'Classical'),(6,'Folk'),
  (7,'Blues'),(8,'Metal'),(9,'Soul'),(10,'Reggae'),(11,'Country'),(12,'Ambient'),(13,'Punk'),(14,'Funk'),(15,'Indie Rock');

INSERT INTO library(id, name, path, last_scan_at, last_scan_started_at, updated_at, created_at)
VALUES (1, 'Music', '/music', '2026-10-20 03:00:00', '2026-10-20 02:00:00', '2026-10-20 03:00:00', '2023-01-01 00:00:00'),
       (2, 'Classical', '/classical', '2026-10-21 03:00:00', '2026-10-21 02:00:00', '2026-10-21 03:00:00', '2023-01-01 00:00:00'),
       (3, 'Shared', '/nas/shared', '2026-10-22 03:00:00', '2026-10-22 02:00:00', '2026-10-22 03:00:00', '2024-05-01 00:00:00');

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20)
INSERT INTO user(id, user_name, name, email, password, is_admin, last_login_at, last_access_at, created_at, updated_at)
SELECT 'usr' || i, 'user' || i, 'User ' || i, 'user' || i || '@example.org', 'enc:' || hex(i), i = 1,
       '2026-10-2' || (i % 8) || ' 10:00:00', '2026-10-27 1' || (i % 10) || ':00:00', '2023-01-01 00:00:00', '2026-10-01 00:00:00'
FROM n;

-- usr1 is admin; every third user sees all three libraries, the others only libraries 1 and 2
INSERT INTO user_library(user_id, library_id)
SELECT u.id, l.id FROM user u, library l
WHERE l.id < 3 OR u.is_admin OR CAST(substr(u.id, 4) AS INTEGER) % 3 = 0;

-- artists
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 1000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO artist(id, name, order_artist_name, sort_artist_name, mbz_artist_id, missing, similar_artists,
                   updated_at, created_at, average_rating, search_normalized, full_text)
SELECT printf('ar%05d', i), nm, lower(CASE WHEN nm LIKE 'The %' THEN substr(nm, 5) ELSE nm END),
       CASE WHEN (h / 64) % 9 = 0 THEN 'Sorted, ' || nm ELSE '' END,
       printf('%08x-%04x-4%03x-8%03x-%012x', h, (h / 7) % 65536, (h / 11) % 4096, (h / 13) % 4096, h * 31),
       (h / 2048) % 50 = 0, '[]',
       datetime(1672531200 + (h % 120000000), 'unixepoch'), datetime(1672531200 + (h % 60000000), 'unixepoch'),
       ((h / 4096) % 50) / 10.0, '', ''
FROM (SELECT i, h, CASE (h / 3) % 3
          WHEN 0 THEN 'The ' || (SELECT w FROM w WHERE k = (h / 32) % 32) || ' ' || (SELECT w FROM w WHERE k = (h / 1024) % 32) || 's'
          WHEN 1 THEN (SELECT w FROM w WHERE k = (h / 32) % 32) || ' ' || (SELECT w FROM w WHERE k = (h / 1024) % 32) || ' ' || i
          ELSE 'DJ ' || (SELECT w FROM w WHERE k = (h / 1024) % 32) || i END AS nm FROM m);

-- albums: album artists skewed towards low ids (a few prolific artists)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 3000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n),
a AS (SELECT i, h, 1 + ((h % 1000) * ((h / 1000) % 1000)) / 1000 AS aa,
             (SELECT w FROM w WHERE k = (h / 8) % 32) || ' ' || (SELECT w FROM w WHERE k = (h / 256) % 32) AS nm,
             1960 + (h / 17) % 66 AS y, (h / 23) % 16 AS g
      FROM m)
INSERT INTO album(id, name, album_artist, album_artist_id, min_year, max_year, compilation, genre, created_at, updated_at,
                  imported_at, library_id, date, original_date, release_date, order_album_name, order_album_artist_name,
                  sort_album_name, mbz_album_id, mbz_release_group_id, missing, participants, tags, folder_ids, discs,
                  average_rating, search_participants, catalog_num, full_text)
SELECT printf('al%05d', a.i), a.nm, ar.name, ar.id,
       CASE WHEN (a.h / 19) % 4 = 0 THEN a.y - 1 ELSE a.y END, a.y, (a.h / 13) % 20 = 0, (SELECT name FROM genre WHERE k = a.g),
       datetime(1672531200 + (a.i * 117000000) / (3000*(SELECT scale FROM _cfg)), 'unixepoch'),
       datetime(1672531200 + (a.i * 117000000) / (3000*(SELECT scale FROM _cfg)) + (a.h % 9000000), 'unixepoch'),
       datetime(1672531200 + (a.i * 117000000) / (3000*(SELECT scale FROM _cfg)) + (a.h % 9000000), 'unixepoch'),
       1 + (a.h / 7) % 3, a.y || '-03-01', CASE WHEN (a.h / 31) % 6 = 0 THEN (a.y - 5) || '-01-01' ELSE '' END, a.y || '-03-01',
       lower(a.nm), ar.order_artist_name, '',
       printf('%08x-%04x-4%03x-9%03x-%012x', a.h, (a.h / 5) % 65536, (a.h / 9) % 4096, (a.h / 15) % 4096, a.h * 17),
       printf('%08x-%04x-4%03x-a%03x-%012x', a.h * 3 % 4294967296, (a.h / 3) % 65536, (a.h / 21) % 4096, (a.h / 25) % 4096, a.h * 7),
       (a.h / 29) % 50 = 0,
       json_object('albumartist', json_array(json_object('id', ar.id, 'name', ar.name)),
                   'artist', json_array(json_object('id', ar.id, 'name', ar.name))),
       json_object('genre', json_array(json_object('id', printf('tg%02d', a.g), 'value', (SELECT name FROM genre WHERE k = a.g)))),
       json_array(printf('fo%06d', a.i)), '{"1":""}',
       ((a.h / 4096) % 50) / 10.0, ar.name, CASE WHEN (a.h / 37) % 4 = 0 THEN 'CAT-' || (a.h % 100000) ELSE '' END, ''
FROM a JOIN artist ar ON ar.rowid = a.aa;

-- tracks: 10 per album; 20% have a featured track artist, 30% a composer, 2% CJK titles
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 30000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h, (i - 1) / 10 + 1 AS alr, (i - 1) % 10 + 1 AS tn FROM n),
t AS (SELECT m.*, al.id AS album_id, al.name AS album, al.album_artist, al.album_artist_id, al.max_year, al.library_id,
             al.created_at AS al_created, al.missing AS al_missing, al.tags AS al_tags, al.genre, al.compilation,
             al.order_album_name, al.order_album_artist_name, al.release_date, al.mbz_album_id,
             CASE WHEN (m.h / 5) % 5 = 0 THEN 1 + (m.h / 64) % (1000*(SELECT scale FROM _cfg)) ELSE NULL END AS feat,
             CASE WHEN (m.h / 9) % 10 < 3 THEN 1 + (m.h / 4096) % (1000*(SELECT scale FROM _cfg)) ELSE NULL END AS comp,
             CASE WHEN (m.h / 11) % 50 = 0 THEN (SELECT w FROM cjk WHERE k = (m.h / 128) % 6)
                  ELSE (SELECT w FROM w WHERE k = (m.h / 16) % 32) || ' ' || (SELECT w FROM w WHERE k = (m.h / 512) % 32)
                       || CASE WHEN (m.h / 3) % 3 = 0 THEN ' ' || (SELECT w FROM w WHERE k = (m.h / 16384) % 32) ELSE '' END END AS title
      FROM m JOIN album al ON al.rowid = m.alr),
u AS (SELECT t.*, coalesce(fa.id, t.album_artist_id) AS artist_id, coalesce(fa.name, t.album_artist) AS artist,
             coalesce(fa.order_artist_name, t.order_album_artist_name) AS order_artist_name, ca.id AS comp_id, ca.name AS comp_name
      FROM t LEFT JOIN artist fa ON fa.rowid = t.feat LEFT JOIN artist ca ON ca.rowid = t.comp)
INSERT INTO media_file(id, path, title, album, artist, artist_id, album_artist, album_id, album_artist_id, has_cover_art,
                       track_number, disc_number, year, size, suffix, duration, bit_rate, genre, compilation, created_at,
                       updated_at, birth_time, date, release_date, order_title, order_album_name, order_album_artist_name,
                       order_artist_name, library_id, folder_id, pid, missing, tags, participants, mbz_recording_id,
                       mbz_release_track_id, mbz_album_id, lyrics, sample_rate, channels, codec, average_rating,
                       search_participants, full_text, bpm)
SELECT printf('mf%06d', i), album_artist || '/' || album || '/' || printf('%02d', tn) || ' - ' || title || CASE WHEN (h / 7) % 10 < 3 THEN '.flac' ELSE '.mp3' END,
       title, album, artist, artist_id, album_artist, album_id, album_artist_id, 1,
       tn, 1, max_year, 3000000 + (h % 40000000), CASE WHEN (h / 7) % 10 < 3 THEN 'flac' ELSE 'mp3' END,
       120 + (h / 13) % 300 + ((h / 17) % 1000) / 1000.0, CASE WHEN (h / 7) % 10 < 3 THEN 900 + (h / 19) % 600 ELSE 320 END,
       genre, compilation,
       datetime(al_created, '+' || tn || ' seconds'), datetime(al_created, '+' || ((h / 23) % 5000000) || ' seconds'),
       datetime(al_created, '+' || tn || ' seconds'),
       max_year || '-03-01', release_date, lower(title), order_album_name, order_album_artist_name, order_artist_name,
       library_id, printf('fo%06d', alr), printf('mf%06d', i), al_missing OR (h / 29) % 200 = 0, al_tags,
       json_object('albumartist', json_array(json_object('id', album_artist_id, 'name', album_artist)),
                   'artist', json_array(json_object('id', artist_id, 'name', artist))),
       printf('%08x-%04x-4%03x-b%03x-%012x', h, (h / 3) % 65536, (h / 5) % 4096, (h / 7) % 4096, h * 13),
       CASE WHEN (h / 31) % 8 = 0 THEN '' ELSE printf('%08x-%04x-4%03x-c%03x-%012x', h * 5 % 4294967296, (h / 9) % 65536, (h / 11) % 4096, (h / 13) % 4096, h * 11) END,
       mbz_album_id, CASE WHEN (h / 37) % 6 = 0 THEN '[{"lang":"eng","line":[{"value":"la la"}],"synced":false}]' ELSE '[]' END,
       CASE WHEN (h / 7) % 10 < 3 THEN 96000 ELSE 44100 END, 2, CASE WHEN (h / 7) % 10 < 3 THEN 'FLAC' ELSE 'MP3' END,
       ((h / 4096) % 50) / 10.0,
       album_artist || CASE WHEN artist <> album_artist THEN ' ' || artist ELSE '' END || coalesce(' ' || comp_name, ''),
       '', CASE WHEN (h / 41) % 3 = 0 THEN 80 + (h / 43) % 100 END
FROM u;

-- composer participants
UPDATE media_file SET participants = json_set(participants, '$.composer',
       json_array(json_object('id', printf('ar%05d', 1 + ((rowid * 2654435761) % 4294967296 / 4096) % (1000*(SELECT scale FROM _cfg))),
                              'name', (SELECT name FROM artist WHERE rowid = 1 + ((media_file.rowid * 2654435761) % 4294967296 / 4096) % (1000*(SELECT scale FROM _cfg))))))
WHERE ((rowid * 2654435761) % 4294967296 / 9) % 10 < 3;

-- album totals from tracks
UPDATE album SET (song_count, duration, size) =
  (SELECT count(*), sum(duration), sum(size) FROM media_file WHERE media_file.album_id = album.id);

-- participation tables, from the participants JSON (same shape updateParticipants writes)
INSERT OR IGNORE INTO media_file_artists(media_file_id, artist_id, role, sub_role)
SELECT mf.id, json_extract(p.value, '$.id'), r.key, ''
FROM media_file mf, json_each(mf.participants) r, json_each(r.value) p;

INSERT OR IGNORE INTO album_artists(album_id, artist_id, role, sub_role)
SELECT mf.album_id, mfa.artist_id, mfa.role, ''
FROM media_file_artists mfa JOIN media_file mf ON mf.id = mfa.media_file_id;

-- genres
INSERT INTO tag(id, tag_name, tag_value) SELECT printf('tg%02d', k), 'genre', name FROM genre;
INSERT INTO album_tags(album_id, tag_id) SELECT id, printf('tg%02d', (SELECT k FROM genre WHERE name = album.genre)) FROM album;
INSERT INTO media_file_tags(media_file_id, tag_id) SELECT id, printf('tg%02d', (SELECT k FROM genre WHERE name = media_file.genre)) FROM media_file;
INSERT INTO library_tag(tag_id, library_id, album_count, media_file_count)
SELECT t.id, l.id,
       (SELECT count(*) FROM album_tags x JOIN album a ON a.id = x.album_id WHERE x.tag_id = t.id AND a.library_id = l.id),
       (SELECT count(*) FROM media_file_tags x JOIN media_file m ON m.id = x.media_file_id WHERE x.tag_id = t.id AND m.library_id = l.id)
FROM tag t, library l;

-- library_artist with per-role stats (the shape artistRepository.RefreshStats writes)
INSERT OR IGNORE INTO library_artist(library_id, artist_id)
SELECT DISTINCT mf.library_id, mfa.artist_id FROM media_file_artists mfa JOIN media_file mf ON mf.id = mfa.media_file_id;
WITH c AS (
  SELECT mfa.artist_id, mf.library_id, mfa.role, count(DISTINCT mf.album_id) AS a, count(DISTINCT mf.id) AS m, sum(mf.size) AS s
  FROM media_file_artists mfa JOIN media_file mf ON mfa.media_file_id = mf.id GROUP BY 1, 2, 3
  UNION ALL
  SELECT mfa.artist_id, mf.library_id, 'total', count(DISTINCT mf.album_id), count(DISTINCT mf.id), sum(mf.size)
  FROM media_file_artists mfa JOIN media_file mf ON mfa.media_file_id = mf.id GROUP BY 1, 2
  UNION ALL
  SELECT mfa.artist_id, mf.library_id, 'maincredit', count(DISTINCT mf.album_id), count(DISTINCT mf.id), sum(mf.size)
  FROM media_file_artists mfa JOIN media_file mf ON mfa.media_file_id = mf.id WHERE mfa.role IN ('albumartist', 'artist') GROUP BY 1, 2),
j AS (SELECT artist_id, library_id, json_group_object(role, json_object('a', a, 'm', m, 's', s)) AS st FROM c GROUP BY 1, 2)
UPDATE library_artist SET stats = j.st FROM j WHERE j.artist_id = library_artist.artist_id AND j.library_id = library_artist.library_id;

-- annotations: users 1-5 are heavy listeners
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 12000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT OR IGNORE INTO annotation(user_id, item_id, item_type, play_count, play_date, rating, starred, starred_at, rated_at)
SELECT 'usr' || u.k, printf('mf%06d', 1 + ((h / 4) * (u.k * 7 + 1)) % (30000*(SELECT scale FROM _cfg))), 'media_file',
       1 + ((h / 64) % 30) * ((h / 2048) % 3), datetime(1793059200 - ((h / 8) % 31000000), 'unixepoch'),
       CASE WHEN (h / 128) % 5 < 2 THEN 1 + (h / 512) % 5 ELSE 0 END, (h / 1024) % 12 = 0,
       CASE WHEN (h / 1024) % 12 = 0 THEN datetime(1793059200 - ((h / 16) % 20000000), 'unixepoch') END,
       CASE WHEN (h / 128) % 5 < 2 THEN datetime(1793059200 - ((h / 32) % 25000000), 'unixepoch') END
FROM m, (SELECT 1 AS k UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
         UNION ALL SELECT 6 UNION ALL SELECT 9 UNION ALL SELECT 12) u
WHERE u.k <= 5 OR m.i % 5 = 0;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 1000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2246822519) % 4294967296 AS h FROM n)
INSERT OR IGNORE INTO annotation(user_id, item_id, item_type, play_count, play_date, rating, starred, starred_at, rated_at)
SELECT 'usr' || u.k, printf('al%05d', 1 + ((h / 4) * (u.k * 5 + 3)) % (3000*(SELECT scale FROM _cfg))), 'album',
       (h / 64) % 40, CASE WHEN (h / 64) % 40 > 0 THEN datetime(1793059200 - ((h / 8) % 30000000), 'unixepoch') END,
       CASE WHEN (h / 128) % 3 = 0 THEN 1 + (h / 512) % 5 ELSE 0 END, (h / 1024) % 8 = 0,
       CASE WHEN (h / 1024) % 8 = 0 THEN datetime(1793059200 - ((h / 16) % 20000000), 'unixepoch') END,
       CASE WHEN (h / 128) % 3 = 0 THEN datetime(1793059200 - ((h / 32) % 25000000), 'unixepoch') END
FROM m, (SELECT 1 AS k UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 6 UNION ALL SELECT 9) u;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 3266489917) % 4294967296 AS h FROM n)
INSERT OR IGNORE INTO annotation(user_id, item_id, item_type, play_count, play_date, rating, starred, starred_at, rated_at)
SELECT 'usr' || u.k, printf('ar%05d', 1 + ((h / 4) * (u.k * 3 + 1)) % (1000*(SELECT scale FROM _cfg))), 'artist',
       (h / 64) % 200, datetime(1793059200 - ((h / 8) % 30000000), 'unixepoch'),
       CASE WHEN (h / 128) % 4 = 0 THEN 1 + (h / 512) % 5 ELSE 0 END, (h / 1024) % 6 = 0,
       CASE WHEN (h / 1024) % 6 = 0 THEN datetime(1793059200 - ((h / 16) % 20000000), 'unixepoch') END,
       CASE WHEN (h / 128) % 4 = 0 THEN datetime(1793059200 - ((h / 32) % 25000000), 'unixepoch') END
FROM m, (SELECT 1 AS k UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 6) u;

INSERT INTO bookmark(user_id, item_id, item_type, comment, position, changed_by, created_at, updated_at)
SELECT 'usr2', id, 'media_file', '', 1000 * (rowid % 97), 'DSub', '2026-10-01 00:00:00', '2026-10-01 00:00:00'
FROM media_file WHERE rowid % 37 = 0;

-- playlists: 60 regular, 2 smart (owned by usr2, who only sees libraries 1 and 2)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 60)
INSERT INTO playlist(id, name, comment, public, created_at, updated_at, owner_id, path, sync, rules)
SELECT printf('pl%04d', i), (SELECT w FROM w WHERE k = (i * 7) % 32) || ' Mix ' || i, '', i % 5 < 2,
       '2025-01-01 00:00:00', '2026-10-01 00:00:00', 'usr' || (1 + i % 20), '', 0, NULL
FROM n;
INSERT INTO playlist(id, name, comment, public, created_at, updated_at, owner_id, path, sync, rules, evaluated_at)
VALUES ('sp0001', 'Recent rock favourites', '', 0, '2025-01-01', '2026-10-01', 'usr2', '', 0,
        '{"all":[{"inTheLast":{"lastPlayed":90}},{"gt":{"rating":3}},{"any":[{"contains":{"genre":"Rock"}},{"contains":{"genre":"Jazz"}}]}],"sort":"playCount","order":"desc","limit":100}', NULL),
       ('sp0002', '90s albums I rated', '', 0, '2025-01-01', '2026-10-01', 'usr2', '', 0,
        '{"all":[{"gt":{"albumRating":2}},{"notInPlaylist":{"id":"pl0001"}},{"inTheRange":{"year":[1990,1999]}}],"sort":"-albumRating,title","limit":200}', NULL);

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2400)
INSERT INTO playlist_tracks(id, playlist_id, media_file_id)
SELECT 1 + (i - 1) % 40, printf('pl%04d', 1 + (i - 1) / 40),
       printf('mf%06d', 1 + ((i * 2654435761) % 4294967296) % (30000*(SELECT scale FROM _cfg)))
FROM n;

UPDATE playlist SET (song_count, duration, size) =
  (SELECT count(*), coalesce(sum(duration), 0), coalesce(sum(size), 0)
   FROM playlist_tracks pt JOIN media_file mf ON mf.id = pt.media_file_id WHERE pt.playlist_id = playlist.id);

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO scrobbles(media_file_id, user_id, submission_time)
SELECT printf('mf%06d', 1 + (h / 16) % (30000*(SELECT scale FROM _cfg))), 'usr' || (1 + ((h % 400) * (h / 400 % 20)) / 400),
       1762000000 + i * (31000000 / (40000*(SELECT scale FROM _cfg)))
FROM m;

-- artwork for 80% of albums; some albums share an image hash
INSERT INTO item_artwork(item_kind, item_id, image_type, hash, source, source_path, ref_mtime, attempted_at, updated_at)
SELECT 'al', id, 'primary', printf('%016x', ((rowid * 2654435761) % 4294967296) / 2 * 977), 'folder', 'cover.jpg', 1700000000,
       '2026-10-01 00:00:00', '2026-10-01 00:00:00'
FROM album WHERE rowid % 5 <> 0;
INSERT OR IGNORE INTO artwork(hash, mime, width, height, size_bytes, blur_hash, thumb_hash, dominant_color)
SELECT DISTINCT hash, 'image/jpeg', 1000, 1000, 250000 + length(hash) * 1000, 'LEHV6nWB2yk8pyo0adR*.7kCMdnj', 'YTkGJwaRhWUIt4lbgnhZl3ath2BUBGYA', '#334455'
FROM item_artwork WHERE (CAST(substr(hash, 12) AS INTEGER) % 3) <> 1;

COMMIT;
