-- Synthetic data for Frigate: a 10-camera NVR with 30 days of retention. Deterministic (no random()): values come
-- from multiplicative hashes of row numbers. "Now" is 1790000000.0 (2026-09-21 14:13 UTC); times are float epoch seconds.
-- Scale 1: 10 cameras (driveway, street and front_door busy), 10-second recording segments: the last 24 h continuous
-- on every camera plus motion bursts (5-minute blocks) kept for 30 days and one day past retention (~165k rows), a sub
-- stream on street for the last day; 30k tracked objects (events, ~1000/day, JSON data with boxes, scores, path
-- data and plates), 3 timeline rows per event (90k), 12k review segments with per-user review status, one preview
-- per camera-hour, and 400 events from a camera that was removed from the config. _cfg.scale multiplies events,
-- timeline and review segments, and the number of recording slots kept per camera.
BEGIN;

CREATE TEMP TABLE _cam(k INTEGER PRIMARY KEY, name TEXT, busy INTEGER, zone TEXT);
INSERT INTO _cam VALUES (0,'backyard',0,'lawn'),(1,'driveway',1,'driveway_zone'),(2,'front_door',1,'front_steps'),
  (3,'garage',0,'garage_door'),(4,'kitchen',0,'counter'),(5,'living_room',0,'sofa'),(6,'nursery',0,'crib'),
  (7,'porch',0,'porch_zone'),(8,'side_gate',0,'gate'),(9,'street',1,'sidewalk'),(10,'old_shed',0,'shed');

CREATE TEMP TABLE _lab(k INTEGER PRIMARY KEY, label TEXT);
INSERT INTO _lab VALUES (0,'person'),(1,'person'),(2,'person'),(3,'person'),(4,'person'),(5,'person'),(6,'person'),
  (7,'person'),(8,'person'),(9,'car'),(10,'car'),(11,'car'),(12,'car'),(13,'car'),(14,'car'),(15,'car'),(16,'dog'),
  (17,'dog'),(18,'cat'),(19,'package');

-- Recordings: slot s is a 10-second segment, s = 0 is the oldest (31 days ago). Busy cameras keep 6 % of their
-- 5-minute blocks, quiet ones 1.5 %, scaled by _cfg.scale; the last 8640 slots (24 h) are continuous.
CREATE TEMP TABLE _rec AS
WITH RECURSIVE s(n) AS (SELECT 0 UNION ALL SELECT n + 1 FROM s WHERE n < 267839)
SELECT c.k AS ck, c.name AS camera, c.busy, s.n AS slot,
  1790000000.0 - (267840 - s.n) * 10.0 + (c.k * 0.37) AS start_time,
  ((s.n / 30) * 2654435761 + c.k * 97) % 4294967296 AS hb,
  ((s.n * 40503 + c.k * 7919) % 65536) * 2654435761 % 4294967296 AS h
FROM s JOIN _cam AS c ON c.k < 10
WHERE s.n >= 267840 - 8640
   OR ((s.n / 30) * 2654435761 + c.k * 97) % 4294967296 % 1000
      < (CASE WHEN c.busy = 1 THEN 60 ELSE 15 END) * (SELECT scale FROM _cfg);

INSERT INTO recordings(id, camera, path, start_time, end_time, duration, objects, motion, segment_size, dBFS, regions,
  stream_type, has_audio, audio_rate, audio_codec, video_codec, audio_duration)
SELECT printf('%.6f', start_time) || '-' || substr(printf('%08x', h), 1, 6), camera,
  '/media/frigate/recordings/' || strftime('%Y-%m-%d/%H', start_time, 'unixepoch') || '/' || camera || '/'
    || strftime('%M.%S', start_time, 'unixepoch') || '.mp4',
  start_time, start_time + 10.0, 10.0,
  CASE WHEN hb % 1000 < (CASE WHEN busy = 1 THEN 60 ELSE 15 END) * (SELECT scale FROM _cfg) THEN h % 4 ELSE 0 END,
  CASE WHEN hb % 1000 < (CASE WHEN busy = 1 THEN 60 ELSE 15 END) * (SELECT scale FROM _cfg) THEN 10 + h % 240 ELSE 0 END,
  (CASE WHEN busy = 1 THEN 1.6 ELSE 0.9 END) + (h % 400) / 1000.0,
  CASE WHEN ck IN (0, 1, 2, 7, 9) THEN 0 - (h / 256) % 3 ELSE 0 END,
  CASE WHEN hb % 1000 < (CASE WHEN busy = 1 THEN 60 ELSE 15 END) * (SELECT scale FROM _cfg) THEN 1 + h % 6 ELSE 0 END,
  'main', CASE WHEN ck IN (0, 1, 2, 7, 9) THEN 1 ELSE 0 END, CASE WHEN ck IN (0, 1, 2, 7, 9) THEN 16000 END,
  CASE WHEN ck IN (0, 1, 2, 7, 9) THEN 'aac' END, CASE WHEN ck = 9 THEN 'hevc' ELSE 'h264' END,
  CASE WHEN ck IN (0, 1, 2, 7, 9) THEN 10.0 END
FROM _rec;

-- sub stream on the street camera for the last 24 h
INSERT INTO recordings(id, camera, path, start_time, end_time, duration, objects, motion, segment_size, dBFS, regions,
  stream_type, has_audio, video_codec)
SELECT printf('%.6f', start_time + 0.01) || '-' || substr(printf('%08x', h / 3), 1, 6), camera,
  '/media/frigate/recordings/' || strftime('%Y-%m-%d/%H', start_time, 'unixepoch') || '/' || camera || '/sub/'
    || strftime('%M.%S', start_time, 'unixepoch') || '.mp4',
  start_time + 0.01, start_time + 10.01, 10.0, 0, 0, 0.25 + (h % 50) / 1000.0, 0, 0, 'sub', 0, 'h264'
FROM _rec WHERE ck = 9 AND slot >= 267840 - 8640;

-- Events (tracked objects). 400 of them belong to old_shed, a camera since removed from the config, 35-40 days old.
CREATE TEMP TABLE _ev AS
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 30000 * (SELECT scale FROM _cfg) + 400),
a AS (SELECT i, (i * 2654435761) % 4294967296 AS h, ((i * 40503 + 977) % 65536) * 2246822519 % 4294967296 AS g,
             30000 * (SELECT scale FROM _cfg) AS total FROM n)
SELECT i, h, g,
  CASE WHEN i > total THEN 10
       ELSE (CASE WHEN h % 100 < 24 THEN 1 WHEN h % 100 < 46 THEN 9 WHEN h % 100 < 62 THEN 2
                  ELSE (CASE (h / 128) % 7 WHEN 0 THEN 0 WHEN 1 THEN 3 WHEN 2 THEN 4 WHEN 3 THEN 5 WHEN 4 THEN 6 WHEN 5 THEN 7 ELSE 8 END) END) END AS ck,
  CASE WHEN i > total THEN 1790000000.0 - 35 * 86400 - (i - total) * 1080.0 - (h % 997) / 10.0
       ELSE 1790000000.0 - 30 * 86400 + (i - 1) * (30 * 86400.0 / total) + (h % 997) / 100.0 END AS start_time
FROM a;

INSERT INTO event(id, label, camera, start_time, end_time, top_score, false_positive, zones, thumbnail, has_clip,
  has_snapshot, region, box, area, retain_indefinitely, sub_label, ratio, plus_id, score, model_hash, detector_type,
  model_type, data)
SELECT printf('%.6f', start_time) || '-' || substr(printf('%08x', g), 1, 6) AS id,
  CASE WHEN c.k IN (4, 5, 6) THEN (CASE WHEN g % 10 < 8 THEN 'person' ELSE 'cat' END)
       WHEN c.k = 9 THEN (CASE WHEN g % 10 < 6 THEN 'car' WHEN g % 10 < 9 THEN 'person' ELSE 'bicycle' END)
       ELSE (SELECT label FROM _lab WHERE k = g % 20) END AS label,
  c.name, start_time,
  CASE WHEN start_time > 1790000000.0 - 120 THEN NULL ELSE start_time + 4.0 + (h % 1160) / 10.0 END,
  NULL, 0,
  CASE WHEN g % 3 = 0 THEN '[]' WHEN g % 7 = 0 THEN json_array(c.zone, 'yard') ELSE json_array(c.zone) END,
  NULL,
  CASE WHEN i % 97 = 0 THEN 0 ELSE 1 END, CASE WHEN i % 97 = 0 AND g % 2 = 0 THEN 0 ELSE 1 END,
  NULL, NULL, NULL, CASE WHEN i % 211 = 0 THEN 1 ELSE 0 END,
  CASE WHEN c.k IN (2, 4, 5, 6) AND g % 5 = 0 THEN (CASE g % 3 WHEN 0 THEN 'Alice' WHEN 1 THEN 'Bob' ELSE 'Alice, Bob' END) END,
  NULL, CASE WHEN g % 53 = 0 THEN printf('%024x', g * 7919) END, NULL, NULL, NULL, NULL,
  json_object('type', 'object',
    'box', json_array(round((h % 600) / 1000.0, 4), round((g % 600) / 1000.0, 4), round(0.05 + (h % 300) / 1000.0, 4), round(0.1 + (g % 300) / 1000.0, 4)),
    'region', json_array(round((h % 400) / 1000.0, 4), round((g % 400) / 1000.0, 4), 0.4, 0.4),
    'score', round(0.6 + (h % 390) / 1000.0, 3), 'top_score', round(0.7 + (g % 290) / 1000.0, 3),
    'attributes', CASE WHEN g % 11 = 0 THEN json_array('face') ELSE json_array() END,
    'average_estimated_speed', CASE WHEN c.k IN (1, 9) THEN (h % 60) ELSE 0 END,
    'velocity_angle', CASE WHEN c.k IN (1, 9) THEN (g % 360) ELSE 0 END,
    'recognized_license_plate', CASE WHEN c.k IN (1, 9) AND g % 4 = 0 THEN printf('%s%03d%s', char(65 + g % 26), h % 1000, char(65 + (h / 26) % 26)) END,
    'recognized_license_plate_score', CASE WHEN c.k IN (1, 9) AND g % 4 = 0 THEN round(0.8 + (h % 200) / 1000.0, 3) END,
    'path_data', json_array(json_array(json_array(round((h % 900) / 1000.0, 3), round((g % 900) / 1000.0, 3)), start_time + 1),
                            json_array(json_array(round((h % 800) / 1000.0, 3), round((g % 800) / 1000.0, 3)), start_time + 3))) AS data
FROM _ev JOIN _cam AS c ON c.k = _ev.ck;

-- Timeline: visible, entered_zone (or attribute), gone, per event.
INSERT INTO timeline(timestamp, camera, source, source_id, class_type, data)
SELECT e.start_time + t.k * ((coalesce(e.end_time, e.start_time + 20) - e.start_time) / 2.0), e.camera, 'tracked_object', e.id,
  CASE t.k WHEN 0 THEN 'visible' WHEN 1 THEN (CASE WHEN e.zones = '[]' THEN 'attribute' ELSE 'entered_zone' END) ELSE 'gone' END,
  json_object('camera', e.camera, 'label', e.label, 'sub_label', e.sub_label,
    'box', json_extract(e.data, '$.box'), 'region', json_extract(e.data, '$.region'),
    'attribute', CASE WHEN t.k = 1 AND e.zones = '[]' THEN 'face' ELSE '' END,
    'zones', json(CASE WHEN t.k = 0 THEN '[]' ELSE e.zones END))
FROM event AS e JOIN (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2) AS t;

-- Review segments: one per 2.5 events on average, alerts for persons/cars in zones.
CREATE TEMP TABLE _rv AS
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 12000 * (SELECT scale FROM _cfg)),
a AS (SELECT i, (i * 2654435761) % 4294967296 AS h, ((i * 40503 + 31) % 65536) * 2246822519 % 4294967296 AS g,
             12000 * (SELECT scale FROM _cfg) AS total FROM n)
SELECT i, h, g,
  CASE WHEN h % 100 < 24 THEN 1 WHEN h % 100 < 46 THEN 9 WHEN h % 100 < 62 THEN 2
       ELSE (CASE (h / 128) % 7 WHEN 0 THEN 0 WHEN 1 THEN 3 WHEN 2 THEN 4 WHEN 3 THEN 5 WHEN 4 THEN 6 WHEN 5 THEN 7 ELSE 8 END) END AS ck,
  1790000000.0 - 30 * 86400 + (i - 1) * (30 * 86400.0 / total) + (h % 997) / 100.0 AS start_time
FROM a;

INSERT INTO reviewsegment(id, camera, start_time, end_time, severity, thumb_path, data)
SELECT printf('%.6f', start_time) || '-' || substr(printf('%08x', g), 1, 6), c.name, start_time,
  CASE WHEN start_time > 1790000000.0 - 60 THEN NULL ELSE start_time + 8.0 + (h % 1500) / 10.0 END,
  CASE WHEN g % 10 < 3 THEN 'alert' ELSE 'detection' END,
  '/media/frigate/clips/review/thumb-' || c.name || '-' || printf('%.6f', start_time) || '-' || substr(printf('%08x', g), 1, 6) || '.webp',
  json_object(
    'detections', json_array(printf('%.6f', start_time + 0.4) || '-' || substr(printf('%08x', h), 1, 6),
                             printf('%.6f', start_time + 2.1) || '-' || substr(printf('%08x', g / 7), 1, 6)),
    'objects', CASE WHEN c.k IN (1, 9) THEN (CASE WHEN g % 3 = 0 THEN json_array('car', 'person') WHEN g % 3 = 1 THEN json_array('car') ELSE json_array('person-verified') END)
                    WHEN c.k IN (4, 5, 6) THEN json_array('person') ELSE json_array((SELECT label FROM _lab WHERE k = g % 20)) END,
    'sub_labels', CASE WHEN c.k = 2 AND g % 5 = 0 THEN json_array('Alice') ELSE json_array() END,
    'zones', CASE WHEN g % 3 = 0 THEN json_array() ELSE json_array(c.zone) END,
    'audio', CASE WHEN c.k IN (0, 7) AND g % 9 = 0 THEN json_array('speech') ELSE json_array() END,
    'thumb_time', start_time + 1.5, 'metadata', NULL)
FROM _rv JOIN _cam AS c ON c.k = _rv.ck;

INSERT INTO userreviewstatus(user_id, review_segment_id, has_been_reviewed)
SELECT 'admin', id, 1 FROM reviewsegment
WHERE (start_time < 1790000000.0 - 86400 AND rowid % 10 < 7) OR rowid % 10 < 2;
INSERT INTO userreviewstatus(user_id, review_segment_id, has_been_reviewed)
SELECT 'viewer', id, CASE WHEN rowid % 4 = 0 THEN 0 ELSE 1 END FROM reviewsegment
WHERE rowid % 10 IN (2, 5, 8);

-- Previews: one 1-hour preview clip per camera per hour.
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < 30 * 24 - 1)
INSERT INTO previews(id, camera, path, start_time, end_time, duration)
SELECT printf('%.6f', 1790000000.0 - 3600 * (i + 1) - c.k * 0.01) || '-' || printf('%06x', (i * 2654435761 + c.k) % 16777216),
  c.name, '/media/frigate/clips/previews/' || c.name || '/' || printf('%.1f', 1790000000.0 - 3600 * (i + 1)) || '-' || printf('%.1f', 1790000000.0 - 3600 * i) || '.mp4',
  1790000000.0 - 3600 * (i + 1), 1790000000.0 - 3600 * i, 3600.0
FROM n JOIN _cam AS c ON c.k < 10;

DROP TABLE _rec; DROP TABLE _ev; DROP TABLE _rv; DROP TABLE _cam; DROP TABLE _lab;
COMMIT;
