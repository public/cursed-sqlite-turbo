-- Synthetic data for Tautulli: a household Plex server with four years of play history.
-- Deterministic (no random()): every value comes from multiplicative hashes of the row number. "Now" is 1790000000
-- (2026-09-21 UTC); started times are denser towards now (about 200 plays/day in the last month, 60/day four years ago).
-- Scale 1: 40 users (5 heavy ones hold 70 % of plays; 3 archived, 1 deleted), 8 library sections (1 archived, 1 deleted),
-- 135k session_history rows with 1:1 session_history_metadata and session_history_media_info rows,
-- 3000 movies / 400 shows / 800 artists with Zipf-like popularity, one row in seven continuing the previous play
-- (same reference_id, as group_history() sets it), 4 live sessions. _cfg.scale multiplies the history.
BEGIN;

CREATE TEMP TABLE _plat(k INTEGER PRIMARY KEY, platform TEXT, product TEXT, player TEXT);
INSERT INTO _plat VALUES (0,'Roku','Plex for Roku','Living Room Roku'),(1,'Chrome','Plex Web','Chrome'),
  (2,'Android','Plex for Android (TV)','SHIELD Android TV'),(3,'iOS','Plex for iOS','iPhone'),
  (4,'tvOS','Plex for Apple TV','Apple TV'),(5,'Windows','Plex for Windows','DESKTOP-7Q2'),
  (6,'Samsung','Plex for Samsung','Samsung TV'),(7,'LG','Plex for LG','LG OLED'),(8,'Xbox','Plex for Xbox','Xbox Series X'),
  (9,'Android','Plexamp','Pixel 8'),(10,'macOS','Plexamp','MacBook Pro'),(11,'Firefox','Plex Web','Firefox'),
  (12,'Safari','Plex Web','Safari'),(13,'Linux','Plex HTPC','htpc');

CREATE TEMP TABLE _show(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO _show VALUES (0,'The Office'),(1,'Breaking Point'),(2,'Severance'),(3,'Dark Waters'),(4,'The Expanse'),
  (5,'Parks and Rec'),(6,'Northern Lights'),(7,'The Wire'),(8,'Bluey'),(9,'Midnight Diner'),(10,'Station Eleven'),
  (11,'The Bear'),(12,'Slow Horses'),(13,'Columbo'),(14,'Taskmaster'),(15,'Office Hours');

-- users: user_id is a Plex account id. 38-40 archived, 37 deleted, every fifth friendly_name missing.
WITH RECURSIVE n(u) AS (SELECT 1 UNION ALL SELECT u+1 FROM n WHERE u < 40)
INSERT INTO users(user_id, username, friendly_name, thumb, custom_avatar_url, title, email, is_active, is_admin,
  is_home_user, is_allow_sync, is_restricted, do_notify, keep_history, deleted_user, is_archived, allow_guest,
  shared_libraries)
SELECT 1000000 + u * 7919, 'plexuser' || u,
  CASE WHEN u % 5 = 0 THEN (CASE WHEN u % 10 = 0 THEN '' ELSE NULL END) ELSE 'Friend ' || u END,
  'https://plex.tv/users/' || printf('%016x', u * 2654435761) || '/avatar?c=' || (1700000000 + u),
  CASE WHEN u % 9 = 0 THEN 'https://img.example/avatars/' || u || '.png' END,
  CASE WHEN u = 1 THEN 'Owner' ELSE 'plexuser' || u END, 'plexuser' || u || '@example.com',
  CASE WHEN u >= 37 THEN 0 ELSE 1 END, CASE WHEN u = 1 THEN 1 ELSE 0 END, CASE WHEN u <= 4 THEN 1 ELSE 0 END, 0, 0,
  1, 1, CASE WHEN u = 37 THEN 1 ELSE 0 END, CASE WHEN u >= 38 THEN 1 ELSE 0 END, 0, '1;2;3;4;5;7'
FROM n;

INSERT INTO library_sections(server_id, section_id, section_name, section_type, agent, thumb, art, count, parent_count,
  child_count, is_active, deleted_section, is_archived) VALUES
  ('a1b2c3d4e5f6', 1, 'Movies', 'movie', 'tv.plex.agents.movie', '/:/resources/movie.png', '/:/resources/movie-fanart.jpg', 2650, NULL, NULL, 1, 0, 0),
  ('a1b2c3d4e5f6', 2, 'TV Shows', 'show', 'tv.plex.agents.series', '/:/resources/show.png', '/:/resources/show-fanart.jpg', 360, 1480, 21400, 1, 0, 0),
  ('a1b2c3d4e5f6', 3, 'Music', 'artist', 'tv.plex.agents.music', '/:/resources/artist.png', '/:/resources/artist-fanart.jpg', 800, 3900, 41000, 1, 0, 0),
  ('a1b2c3d4e5f6', 4, 'Movies 4K', 'movie', 'tv.plex.agents.movie', '/:/resources/movie.png', '/:/resources/movie-fanart.jpg', 350, NULL, NULL, 1, 0, 0),
  ('a1b2c3d4e5f6', 5, 'Anime', 'show', 'tv.plex.agents.series', '/:/resources/show.png', '/:/resources/show-fanart.jpg', 40, 120, 1900, 1, 0, 0),
  ('a1b2c3d4e5f6', 6, 'Old Movies', 'movie', 'tv.plex.agents.movie', '/:/resources/movie.png', '/:/resources/movie-fanart.jpg', 120, NULL, NULL, 1, 0, 1),
  ('a1b2c3d4e5f6', 7, 'Live TV', 'live', NULL, '/:/resources/live.png', NULL, NULL, NULL, NULL, 1, 0, 0),
  ('a1b2c3d4e5f6', 8, 'Home Videos', 'movie', 'com.plexapp.agents.none', '/:/resources/movie.png', NULL, 40, NULL, NULL, 0, 1, 0);

-- One row per play. j is the play this row continues (i-1 for every seventh row) and supplies user and item.
CREATE TEMP TABLE _h AS
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 135000 * (SELECT scale FROM _cfg)),
r AS (
  SELECT i, CASE WHEN i % 7 = 3 THEN i - 1 ELSE i END AS j, 135000 * (SELECT scale FROM _cfg) AS total,
         (i * 2246822519 + 374761393) % 4294967296 AS h2
  FROM n),
s AS (
  SELECT i, j, total, h2,
         (j * 2654435761) % 4294967296 AS hb,
         (((j * 40503 + 12345) % 65536) * 2654435761) % 4294967296 AS hc
  FROM r),
t AS (
  SELECT i, j, h2, hb, hc,
    1790000000 - 3600 - CAST(126144000 * (1.0 - (i - 1.0) / total) * (0.5 + 0.5 * (1.0 - (i - 1.0) / total)) AS INTEGER) AS started,
    CASE WHEN (hb / 8) % 100 < 28 THEN 1 WHEN (hb / 8) % 100 < 44 THEN 2 WHEN (hb / 8) % 100 < 56 THEN 3
         WHEN (hb / 8) % 100 < 64 THEN 4 WHEN (hb / 8) % 100 < 70 THEN 5 ELSE 6 + (hb / 1024) % 35 END AS u,
    CASE WHEN (hb / 4096) % 100 < 54 THEN 'episode' WHEN (hb / 4096) % 100 < 78 THEN 'movie'
         WHEN (hb / 4096) % 100 < 96 THEN 'track' ELSE 'live' END AS kind,
    ((hc / 65536) % 3000) * ((hc / 16) % 3000) / 3000 AS mrank,
    ((hc / 65536) % 400) * ((hc / 16) % 400) / 400 AS srank,
    ((hc / 65536) % 800) * ((hc / 16) % 800) / 800 AS arank
  FROM s)
SELECT i, j, h2, hb, hc, started, u, kind,
  1000000 + u * 7919 AS user_id,
  CASE kind WHEN 'movie' THEN (CASE WHEN (hb / 1048576) % 50 = 0 THEN 6 WHEN (hb / 1048576) % 10 = 0 THEN 4 ELSE 1 END)
            WHEN 'episode' THEN (CASE WHEN srank % 8 = 7 THEN 5 ELSE 2 END) WHEN 'track' THEN 3 ELSE 7 END AS section_id,
  CASE kind WHEN 'movie' THEN 10000 + mrank WHEN 'episode' THEN 100000 + srank * 1000 + ((hb / 256) % 6 + 1) * 20 + (hb / 16384) % 12 + 1
            WHEN 'track' THEN 300000 + arank * 100 + (hb / 512) % 60 ELSE 900000 + (hb / 64) % 30 END AS rating_key,
  CASE kind WHEN 'episode' THEN 60000 + srank * 10 + (hb / 256) % 6 + 1 WHEN 'track' THEN 210000 + arank * 10 + (hb / 512) % 5 END AS parent_rating_key,
  CASE kind WHEN 'episode' THEN 50000 + srank WHEN 'track' THEN 200000 + arank END AS grandparent_rating_key,
  mrank, srank, arank,
  (hb / 256) % 6 + 1 AS season, (hb / 16384) % 12 + 1 AS episode, (hb / 512) % 60 AS trackno,
  CASE kind WHEN 'movie' THEN 5400000 + (hc % 3600) * 1000 WHEN 'episode' THEN 1500000 + (hc % 1800) * 1000
            WHEN 'track' THEN 150000 + (hc % 200) * 1000 ELSE 3600000 END AS duration,
  (u * 3 + (h2 / 32) % 3) % 14 AS plat,
  CASE WHEN (h2 / 128) % 100 < 60 THEN 'direct play' WHEN (h2 / 128) % 100 < 75 THEN 'copy' ELSE 'transcode' END AS td,
  (h2 / 2048) % 100 AS pct,
  CASE WHEN (h2 / 8192) % 5 = 0 THEN (h2 / 65536) % 900 ELSE 0 END AS paused
FROM t;

INSERT INTO session_history(id, reference_id, started, stopped, rating_key, user_id, user, ip_address, paused_counter,
  player, product, product_version, platform, platform_version, profile, machine_id, bandwidth, location,
  quality_profile, secure, relayed, parent_rating_key, grandparent_rating_key, media_type, section_id, live,
  transcode_decision, view_offset)
SELECT i, j, started,
  started + (CASE WHEN pct < 70 THEN duration * 97 / 100 ELSE duration * pct / 100 END) / 1000 + paused,
  rating_key, user_id, 'plexuser' || u,
  CASE WHEN u <= 4 OR u % 3 = 0 THEN '192.168.1.' || (10 + u) ELSE '84.' || (u * 7 % 250) || '.' || (h2 % 250) || '.' || (u + 3) END,
  paused, p.player, p.product, '4.' || (100 + (h2 / 1024) % 40) || '.0', p.platform, (10 + (h2 / 4096) % 5) || '.0',
  CASE WHEN td = 'transcode' THEN 'Universal TV' ELSE NULL END, 'm' || printf('%08x', u * 2654435761 % 4294967296) || '-' || plat,
  CASE WHEN td = 'transcode' THEN 8000 ELSE 20000 + (h2 % 40000) END,
  CASE WHEN u <= 4 OR u % 3 = 0 THEN 'lan' ELSE 'wan' END,
  CASE WHEN td = 'transcode' THEN '8 Mbps 1080p' ELSE 'Original' END, 1, CASE WHEN h2 % 23 = 0 THEN 1 ELSE 0 END,
  parent_rating_key, grandparent_rating_key, CASE kind WHEN 'live' THEN 'episode' ELSE kind END, section_id,
  CASE WHEN kind = 'live' THEN 1 ELSE 0 END, td,
  CASE WHEN pct < 70 THEN duration * 97 / 100 ELSE duration * pct / 100 END
FROM _h JOIN _plat AS p ON p.k = _h.plat;

INSERT INTO session_history_metadata(id, rating_key, parent_rating_key, grandparent_rating_key, title, parent_title,
  grandparent_title, original_title, full_title, media_index, parent_media_index, thumb, parent_thumb,
  grandparent_thumb, art, media_type, year, originally_available_at, added_at, updated_at, last_viewed_at,
  content_rating, summary, tagline, rating, duration, guid, directors, writers, actors, genres, studio, labels, live,
  marker_credits_first, marker_credits_final)
SELECT i, rating_key, parent_rating_key, grandparent_rating_key,
  CASE kind WHEN 'movie' THEN 'Movie ' || mrank WHEN 'episode' THEN 'Episode ' || episode
            WHEN 'track' THEN 'Track ' || trackno ELSE 'Evening News' END,
  CASE kind WHEN 'episode' THEN 'Season ' || season WHEN 'track' THEN 'Album ' || ((hb / 512) % 5) ELSE '' END,
  CASE kind WHEN 'episode' THEN (SELECT w FROM _show WHERE k = srank % 16) || ' ' || srank
            WHEN 'track' THEN 'Artist ' || arank WHEN 'live' THEN 'Channel ' || (rating_key % 30) ELSE '' END,
  CASE WHEN kind = 'track' AND arank % 4 = 0 THEN 'Various ' || arank END,
  CASE kind WHEN 'movie' THEN 'Movie ' || mrank
            WHEN 'episode' THEN (SELECT w FROM _show WHERE k = srank % 16) || ' ' || srank || ' - Episode ' || episode
            WHEN 'track' THEN 'Artist ' || arank || ' - Track ' || trackno ELSE 'Channel ' || (rating_key % 30) || ' - Evening News' END,
  CASE kind WHEN 'episode' THEN episode WHEN 'track' THEN trackno END,
  CASE kind WHEN 'episode' THEN season WHEN 'track' THEN 1 END,
  '/library/metadata/' || rating_key || '/thumb/' || (1600000000 + rating_key),
  CASE WHEN parent_rating_key IS NOT NULL THEN '/library/metadata/' || parent_rating_key || '/thumb/' || (1600000000 + parent_rating_key) ELSE '' END,
  CASE WHEN grandparent_rating_key IS NOT NULL THEN '/library/metadata/' || grandparent_rating_key || '/thumb/' || (1600000000 + grandparent_rating_key) ELSE '' END,
  '/library/metadata/' || coalesce(grandparent_rating_key, rating_key) || '/art/1700000000',
  CASE kind WHEN 'live' THEN 'episode' ELSE kind END,
  1960 + (hc / 4096) % 66, (1960 + (hc / 4096) % 66) || '-0' || (1 + hc % 9) || '-1' || (hc % 9),
  1500000000 + (hc % 200000000), 1700000000 + (hc % 80000000), started,
  CASE (hc / 32) % 5 WHEN 0 THEN 'PG' WHEN 1 THEN 'PG-13' WHEN 2 THEN 'R' WHEN 3 THEN 'TV-MA' ELSE 'TV-14' END,
  CASE WHEN kind = 'movie' THEN 'Plot of item ' || rating_key || '.' END,
  '', CAST(5 + (hc % 50) / 10.0 AS TEXT), duration,
  CASE kind WHEN 'movie' THEN 'plex://movie/5d7768' || printf('%06x', mrank * 7919 % 16777216) || 'a1b2c3d4'
            WHEN 'episode' THEN 'plex://episode/5d9c08' || printf('%06x', (rating_key * 31) % 16777216) || 'e1f2a3b4'
            WHEN 'track' THEN 'plex://track/5d07cd' || printf('%06x', (rating_key * 17) % 16777216) || 'c5d6e7f8'
            ELSE 'tv.plex.xmltv://' || printf('%08x', rating_key * 2654435761 % 4294967296) || '/evening-news' END,
  CASE WHEN kind = 'movie' THEN 'Director ' || (hc % 500) END, NULL,
  CASE WHEN kind = 'movie' THEN 'Actor ' || (hc % 900) || ';Actor ' || ((hc / 7) % 900) END,
  CASE (hc / 1024) % 6 WHEN 0 THEN 'Drama' WHEN 1 THEN 'Comedy;Drama' WHEN 2 THEN 'Action;Thriller' WHEN 3 THEN 'Animation'
       WHEN 4 THEN 'Documentary' ELSE 'Science Fiction;Adventure' END,
  'Studio ' || (hc % 60), CASE WHEN hc % 11 = 0 THEN 'Kids;Favourites' WHEN hc % 7 = 0 THEN 'Favourites' ELSE '' END,
  CASE WHEN kind = 'live' THEN 1 ELSE 0 END,
  CASE WHEN kind IN ('movie', 'episode') AND hc % 3 <> 0 THEN duration - 120000 - (hc % 240) * 1000 END,
  CASE WHEN kind IN ('movie', 'episode') AND hc % 3 <> 0 THEN duration - 30000 END
FROM _h;

INSERT INTO session_history_media_info(id, rating_key, video_decision, audio_decision, transcode_decision, duration,
  container, bitrate, width, height, video_codec, video_full_resolution, audio_codec, audio_channels,
  transcode_height, stream_bitrate, stream_video_decision, stream_video_full_resolution)
SELECT i, rating_key,
  CASE WHEN kind = 'track' THEN NULL ELSE td END,
  CASE WHEN td = 'transcode' AND h2 % 3 = 0 THEN 'transcode' WHEN td = 'transcode' THEN 'copy' ELSE td END,
  td, duration,
  CASE WHEN kind = 'track' THEN 'flac' ELSE 'mkv' END,
  CASE WHEN kind = 'track' THEN 900 WHEN section_id = 4 THEN 60000 ELSE 9000 + hc % 6000 END,
  CASE WHEN kind = 'track' THEN NULL WHEN section_id = 4 THEN 3840 WHEN hc % 5 = 0 THEN 1280 ELSE 1920 END,
  CASE WHEN kind = 'track' THEN NULL WHEN section_id = 4 THEN 2160 WHEN hc % 5 = 0 THEN 720 ELSE 1080 END,
  CASE WHEN kind = 'track' THEN NULL WHEN section_id = 4 THEN 'hevc' ELSE 'h264' END,
  CASE WHEN kind = 'track' THEN NULL WHEN section_id = 4 THEN '4k' WHEN hc % 5 = 0 THEN '720' WHEN hc % 23 = 0 THEN 'sd' ELSE '1080' END,
  CASE WHEN kind = 'track' THEN 'flac' ELSE 'eac3' END, CASE WHEN kind = 'track' THEN 2 ELSE 6 END,
  CASE WHEN td = 'transcode' AND kind <> 'track' THEN (CASE WHEN h2 % 4 = 0 THEN 720 WHEN h2 % 9 = 0 THEN 480 ELSE 1080 END) END,
  CASE WHEN td = 'transcode' THEN 8000 WHEN kind = 'track' THEN 900 ELSE 9000 + hc % 6000 END,
  CASE WHEN kind = 'track' THEN NULL ELSE td END,
  CASE WHEN kind = 'track' OR h2 % 6 = 0 THEN NULL WHEN td = 'transcode' THEN (CASE WHEN h2 % 4 = 0 THEN '720' ELSE '1080' END)
       WHEN section_id = 4 THEN '4k' ELSE '1080' END
FROM _h;

-- Four streams playing now; the history table's activity union reads these.
INSERT INTO sessions(session_key, session_id, rating_key, section_id, media_type, started, stopped, paused_counter, state,
  user_id, user, friendly_name, ip_address, machine_id, player, product, platform, title, parent_title,
  grandparent_title, original_title, full_title, media_index, parent_media_index, thumb, parent_thumb,
  grandparent_thumb, year, parent_rating_key, grandparent_rating_key, originally_available_at, added_at, guid,
  view_offset, duration, transcode_decision, video_full_resolution, live, secure, relayed)
SELECT 300 + k, 'sess' || k, CASE WHEN k = 3 THEN 300101 ELSE 100000 + k * 1000 + 21 END, CASE WHEN k = 3 THEN 3 ELSE 2 END,
  CASE WHEN k = 3 THEN 'track' ELSE 'episode' END, 1790000000 - 600 * (k + 1), NULL, 30 * k,
  CASE WHEN k = 2 THEN 'paused' ELSE 'playing' END, 1000000 + (k + 1) * 7919, 'plexuser' || (k + 1), 'Friend ' || (k + 1),
  '192.168.1.' || (11 + k), 'm-live-' || k, 'Player ' || k, 'Plex Web', 'Chrome', 'Episode 1', 'Season 1',
  'The Office ' || k, NULL, 'The Office ' || k || ' - Episode 1', 1, 1, '/library/metadata/' || k || '/thumb/1',
  '', '', 2005, 60000 + k * 10 + 1, 50000 + k, '2005-03-24', 1600000000, 'plex://episode/live' || k,
  300000 * (k + 1), 1800000, CASE WHEN k = 1 THEN 'transcode' ELSE 'direct play' END, '1080', 0, 1, 0
FROM (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3);

INSERT OR IGNORE INTO sessions_continued(user_id, machine_id, media_type, stopped)
SELECT user_id, 'm' || printf('%08x', u * 2654435761 % 4294967296) || '-' || plat, kind, MAX(started) + 1800
FROM _h WHERE started > 1790000000 - 86400 * 3 GROUP BY user_id, plat, kind;

DROP TABLE _h;
DROP TABLE _plat;
DROP TABLE _show;
COMMIT;
