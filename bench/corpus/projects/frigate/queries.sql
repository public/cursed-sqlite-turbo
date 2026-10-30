-- Frigate NVR (blakeblackshear/frigate @ a6b2a29, MIT). All statements are peewee 4.5 query builders: the handler's
-- builder calls were transcribed against a copy of frigate/models.py (Frigate itself was not imported) and compiled
-- with query.sql() for SqliteDatabase, so identifiers, aliases ("t1") and parameter order are peewee's. ? placeholders
-- are numbered ?N in order. allowed_cameras is every configured camera (an admin), timezone America/New_York (EDT,
-- '-4 hour'), "now" 1790000000.0. Per-day/per-hour period bounds are the data's MIN/MAX start_time, as the handlers
-- compute them first.

-- @id frigate.review.list_24h_all_cameras
-- @src frigate/api/review.py:64-173
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,cpu-evidence
-- @note Review page load: last 24 h of review segments for every allowed camera (IN list of all 10), LEFT JOIN the user's review status, newest first, no LIMIT. https://github.com/blakeblackshear/frigate/pull/24043 measured this 'review list for the last 24 hours' at more than 12 s (119k review rows, 42 cameras); its indexes were not merged.
-- @param ?1 0
-- @param ?2 'admin'
-- @param ?3 1790000000.0
-- @param ?4 1789913600.0
-- @param ?5 'backyard'
-- @param ?6 'driveway'
-- @param ?7 'front_door'
-- @param ?8 'garage'
-- @param ?9 'kitchen'
-- @param ?10 'living_room'
-- @param ?11 'nursery'
-- @param ?12 'porch'
-- @param ?13 'side_gate'
-- @param ?14 'street'
SELECT "t1"."id", "t1"."camera", "t1"."start_time", "t1"."end_time", "t1"."severity", "t1"."thumb_path", "t1"."data", COALESCE("t2"."has_been_reviewed", ?1) AS "has_been_reviewed"
FROM "reviewsegment" AS "t1"
LEFT OUTER JOIN "userreviewstatus" AS "t2" ON (("t1"."id" = "t2"."review_segment_id") AND ("t2"."user_id" = ?2))
WHERE ((("t1"."start_time" < ?3) AND (("t1"."end_time" IS NULL) OR ("t1"."end_time" > ?4))) AND ("t1"."camera" IN (?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)))
ORDER BY "t1"."start_time" DESC;

-- @id frigate.review.list_unreviewed_person_alerts
-- @src frigate/api/review.py:64-173,48-61
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,cpu-evidence
-- @note Review page filtered to unreviewed alerts with label person on two cameras: GLOB over CAST(json_extract(data,'$.objects')) for person and person-verified plus the audio list, and the has_been_reviewed IS NULL/false filter after the LEFT JOIN. Same endpoint as https://github.com/blakeblackshear/frigate/pull/24043.
-- @param ?1 0
-- @param ?2 'admin'
-- @param ?3 1790000000.0
-- @param ?4 1789913600.0
-- @param ?5 'front_door'
-- @param ?6 'driveway'
-- @param ?7 '$."objects"'
-- @param ?8 '*"person"*'
-- @param ?9 '$."objects"'
-- @param ?10 '*"person-verified"*'
-- @param ?11 '$."audio"'
-- @param ?12 '*"person"*'
-- @param ?13 'alert'
-- @param ?14 0
SELECT "t1"."id", "t1"."camera", "t1"."start_time", "t1"."end_time", "t1"."severity", "t1"."thumb_path", "t1"."data", COALESCE("t2"."has_been_reviewed", ?1) AS "has_been_reviewed"
FROM "reviewsegment" AS "t1"
LEFT OUTER JOIN "userreviewstatus" AS "t2" ON (("t1"."id" = "t2"."review_segment_id") AND ("t2"."user_id" = ?2))
WHERE (((((("t1"."start_time" < ?3) AND (("t1"."end_time" IS NULL) OR ("t1"."end_time" > ?4))) AND ("t1"."camera" IN (?5, ?6))) AND (((CAST(json_extract("t1"."data", ?7) AS text) GLOB ?8) OR (CAST(json_extract("t1"."data", ?9) AS text) GLOB ?10)) OR (CAST(json_extract("t1"."data", ?11) AS text) GLOB ?12))) AND ("t1"."severity" = ?13)) AND (("t2"."has_been_reviewed" = ?14) OR ("t2"."has_been_reviewed" IS NULL)))
ORDER BY "t1"."start_time" DESC;

-- @id frigate.review.summary_last24
-- @src frigate/api/review.py:221-333
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,analytics,cpu-evidence
-- @note Review summary badge counts for the last 24 h: four CASE sums over reviewsegment LEFT JOIN userreviewstatus for all cameras. Part of the 'daily review summary' https://github.com/blakeblackshear/frigate/pull/24043 timed at more than 12 s.
-- @param ?1 'alert'
-- @param ?2 1
-- @param ?3 1
-- @param ?4 0
-- @param ?5 'detection'
-- @param ?6 1
-- @param ?7 1
-- @param ?8 0
-- @param ?9 'alert'
-- @param ?10 1
-- @param ?11 0
-- @param ?12 'detection'
-- @param ?13 1
-- @param ?14 0
-- @param ?15 'admin'
-- @param ?16 1789913600.0
-- @param ?17 'backyard'
-- @param ?18 'driveway'
-- @param ?19 'front_door'
-- @param ?20 'garage'
-- @param ?21 'kitchen'
-- @param ?22 'living_room'
-- @param ?23 'nursery'
-- @param ?24 'porch'
-- @param ?25 'side_gate'
-- @param ?26 'street'
SELECT SUM(CASE WHEN (("t1"."severity" = ?1) AND ("t2"."has_been_reviewed" = ?2)) THEN ?3 ELSE ?4 END) AS "reviewed_alert", SUM(CASE WHEN (("t1"."severity" = ?5) AND ("t2"."has_been_reviewed" = ?6)) THEN ?7 ELSE ?8 END) AS "reviewed_detection", SUM(CASE WHEN ("t1"."severity" = ?9) THEN ?10 ELSE ?11 END) AS "total_alert", SUM(CASE WHEN ("t1"."severity" = ?12) THEN ?13 ELSE ?14 END) AS "total_detection"
FROM "reviewsegment" AS "t1"
LEFT OUTER JOIN "userreviewstatus" AS "t2" ON (("t1"."id" = "t2"."review_segment_id") AND ("t2"."user_id" = ?15))
WHERE (("t1"."start_time" > ?16) AND ("t1"."camera" IN (?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26)));

-- @id frigate.review.summary_time_range
-- @src frigate/api/review.py:335-366
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,analytics,cpu-evidence
-- @note Review summary, step 2: MIN/MAX(start_time) over every review segment of the allowed cameras, to size the per-day calendar (https://github.com/blakeblackshear/frigate/pull/24043).
-- @param ?1 'backyard'
-- @param ?2 'driveway'
-- @param ?3 'front_door'
-- @param ?4 'garage'
-- @param ?5 'kitchen'
-- @param ?6 'living_room'
-- @param ?7 'nursery'
-- @param ?8 'porch'
-- @param ?9 'side_gate'
-- @param ?10 'street'
SELECT MIN("t1"."start_time") AS "min_time", MAX("t1"."start_time") AS "max_time"
FROM "reviewsegment" AS "t1"
WHERE ("t1"."camera" IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10));

-- @id frigate.review.summary_per_day
-- @src frigate/api/review.py:368-489
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,analytics,cpu-evidence
-- @note Review summary calendar: per local day (strftime of datetime(start_time,'unixepoch','-4 hour','0 minute'), grouped by CAST(start_time + offset AS int) / 86400) reviewed/total alert and detection counts across the whole retention window, LEFT JOIN review status, ORDER BY start_time DESC over grouped rows. The 'daily review summary' of https://github.com/blakeblackshear/frigate/pull/24043 (>12 s). Period bounds are the data's MIN/MAX start_time (one DST period).
-- @param ?1 '%Y-%m-%d'
-- @param ?2 'unixepoch'
-- @param ?3 '-4 hour'
-- @param ?4 '0 minute'
-- @param ?5 'alert'
-- @param ?6 1
-- @param ?7 1
-- @param ?8 0
-- @param ?9 'detection'
-- @param ?10 1
-- @param ?11 1
-- @param ?12 0
-- @param ?13 'alert'
-- @param ?14 1
-- @param ?15 0
-- @param ?16 'detection'
-- @param ?17 1
-- @param ?18 0
-- @param ?19 'admin'
-- @param ?20 'backyard'
-- @param ?21 'driveway'
-- @param ?22 'front_door'
-- @param ?23 'garage'
-- @param ?24 'kitchen'
-- @param ?25 'living_room'
-- @param ?26 'nursery'
-- @param ?27 'porch'
-- @param ?28 'side_gate'
-- @param ?29 'street'
-- @param ?30 1787408000.3
-- @param ?31 1789999790.69
-- @param ?32 -14400
-- @param ?33 86400
SELECT strftime(?1, datetime("t1"."start_time", ?2, ?3, ?4)) AS "day", SUM(CASE WHEN (("t1"."severity" = ?5) AND ("t2"."has_been_reviewed" = ?6)) THEN ?7 ELSE ?8 END) AS "reviewed_alert", SUM(CASE WHEN (("t1"."severity" = ?9) AND ("t2"."has_been_reviewed" = ?10)) THEN ?11 ELSE ?12 END) AS "reviewed_detection", SUM(CASE WHEN ("t1"."severity" = ?13) THEN ?14 ELSE ?15 END) AS "total_alert", SUM(CASE WHEN ("t1"."severity" = ?16) THEN ?17 ELSE ?18 END) AS "total_detection"
FROM "reviewsegment" AS "t1"
LEFT OUTER JOIN "userreviewstatus" AS "t2" ON (("t1"."id" = "t2"."review_segment_id") AND ("t2"."user_id" = ?19))
WHERE (("t1"."camera" IN (?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29)) AND (("t1"."start_time" >= ?30) AND ("t1"."start_time" <= ?31)))
GROUP BY (CAST(("t1"."start_time" + ?32) AS int) / ?33)
ORDER BY "t1"."start_time" DESC;

-- @id frigate.review.motion_activity_24h
-- @src frigate/api/review.py:611-702
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,analytics
-- @note Review timeline motion graph for all cameras over 24 h: every main-stream recording segment with motion, ordered by start_time (pandas resamples it). Range scan on recordings_start_time plus a filter on camera IN (all).
-- @param ?1 1789913600.0
-- @param ?2 1790000000.0
-- @param ?3 0
-- @param ?4 'main'
-- @param ?5 'backyard'
-- @param ?6 'driveway'
-- @param ?7 'front_door'
-- @param ?8 'garage'
-- @param ?9 'kitchen'
-- @param ?10 'living_room'
-- @param ?11 'nursery'
-- @param ?12 'porch'
-- @param ?13 'side_gate'
-- @param ?14 'street'
SELECT "t1"."camera", "t1"."start_time", "t1"."motion"
FROM "recordings" AS "t1"
WHERE ((((("t1"."start_time" > ?1) AND ("t1"."end_time" < ?2)) AND ("t1"."motion" > ?3)) AND ("t1"."stream_type" = ?4)) AND ("t1"."camera" IN (?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)))
ORDER BY "t1"."start_time" ASC;

-- @id frigate.events.latest_100_all_cameras
-- @src frigate/api/event.py:97-377
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,cpu-evidence
-- @note Events API default: latest 100 tracked objects for all allowed cameras (camera IN all 10, start_time DESC). https://github.com/blakeblackshear/frigate/pull/24043: 228 ms on 282k events, 1.68 s before its index on another run.
-- @param ?1 'backyard'
-- @param ?2 'driveway'
-- @param ?3 'front_door'
-- @param ?4 'garage'
-- @param ?5 'kitchen'
-- @param ?6 'living_room'
-- @param ?7 'nursery'
-- @param ?8 'porch'
-- @param ?9 'side_gate'
-- @param ?10 'street'
-- @param ?11 100
-- @param ?12 0
SELECT "t1"."id", "t1"."camera", "t1"."label", "t1"."zones", "t1"."start_time", "t1"."end_time", "t1"."has_clip", "t1"."has_snapshot", "t1"."plus_id", "t1"."retain_indefinitely", "t1"."sub_label", "t1"."top_score", "t1"."false_positive", "t1"."box", "t1"."data"
FROM "event" AS "t1"
WHERE ("t1"."camera" IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10))
ORDER BY "t1"."start_time" DESC
LIMIT ?11 OFFSET ?12;

-- @id frigate.events.latest_100_one_camera
-- @src frigate/api/event.py:97-377
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,cpu-evidence
-- @note Events for one camera (cameras=nursery): https://github.com/blakeblackshear/frigate/pull/24043 measured more than 8.7 s with only the camera index; migration 039 later added event (camera, start_time).
-- @param ?1 'nursery'
-- @param ?2 100
-- @param ?3 0
SELECT "t1"."id", "t1"."camera", "t1"."label", "t1"."zones", "t1"."start_time", "t1"."end_time", "t1"."has_clip", "t1"."has_snapshot", "t1"."plus_id", "t1"."retain_indefinitely", "t1"."sub_label", "t1"."top_score", "t1"."false_positive", "t1"."box", "t1"."data"
FROM "event" AS "t1"
WHERE ("t1"."camera" IN (?1))
ORDER BY "t1"."start_time" DESC
LIMIT ?2 OFFSET ?3;

-- @id frigate.events.one_camera_last_day
-- @src frigate/api/event.py:97-377
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,cpu-evidence
-- @note One quiet camera's events from the last day (after/before bounds): https://github.com/blakeblackshear/frigate/pull/24043 timed this at 8.34 s returning 9 rows.
-- @param ?1 'garage'
-- @param ?2 1789913600.0
-- @param ?3 1790000000.0
-- @param ?4 100
-- @param ?5 0
SELECT "t1"."id", "t1"."camera", "t1"."label", "t1"."zones", "t1"."start_time", "t1"."end_time", "t1"."has_clip", "t1"."has_snapshot", "t1"."plus_id", "t1"."retain_indefinitely", "t1"."sub_label", "t1"."top_score", "t1"."false_positive", "t1"."box", "t1"."data"
FROM "event" AS "t1"
WHERE ((("t1"."camera" IN (?1)) AND ("t1"."start_time" > ?2)) AND ("t1"."start_time" < ?3))
ORDER BY "t1"."start_time" DESC
LIMIT ?4 OFFSET ?5;

-- @id frigate.events.filtered_score_sort
-- @src frigate/api/event.py:97-377
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic
-- @note Explore filters: labels person,car, zone GLOB on CAST(zones AS text), sub_label exact-or-list match (LOWER + GLOB), has_snapshot, min score from json_extract, sorted by json_extract(data,'$.score') DESC with the id tiebreaker, page 1 of 50.
-- @param ?1 'backyard'
-- @param ?2 'driveway'
-- @param ?3 'front_door'
-- @param ?4 'garage'
-- @param ?5 'kitchen'
-- @param ?6 'living_room'
-- @param ?7 'nursery'
-- @param ?8 'porch'
-- @param ?9 'side_gate'
-- @param ?10 'street'
-- @param ?11 'person'
-- @param ?12 'car'
-- @param ?13 'alice'
-- @param ?14 '*alice,*'
-- @param ?15 '*, alice*'
-- @param ?16 '*"front_steps"*'
-- @param ?17 1
-- @param ?18 '$."score"'
-- @param ?19 0.7
-- @param ?20 '$."score"'
-- @param ?21 50
-- @param ?22 0
SELECT "t1"."id", "t1"."camera", "t1"."label", "t1"."zones", "t1"."start_time", "t1"."end_time", "t1"."has_clip", "t1"."has_snapshot", "t1"."plus_id", "t1"."retain_indefinitely", "t1"."sub_label", "t1"."top_score", "t1"."false_positive", "t1"."box", "t1"."data"
FROM "event" AS "t1"
WHERE (((((("t1"."camera" IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)) AND ("t1"."label" IN (?11, ?12))) AND (((LOWER(CAST("t1"."sub_label" AS text)) = ?13) OR (LOWER(CAST("t1"."sub_label" AS text)) GLOB ?14)) OR (LOWER(CAST("t1"."sub_label" AS text)) GLOB ?15))) AND (CAST("t1"."zones" AS text) GLOB ?16)) AND ("t1"."has_snapshot" = ?17)) AND (json_extract("t1"."data", ?18) >= ?19))
ORDER BY json_extract("t1"."data", ?20) DESC, "t1"."id"
LIMIT ?21 OFFSET ?22;

-- @id frigate.events.summary_per_day
-- @src frigate/api/event.py:914-1018
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,analytics
-- @note Events summary (calendar dots and counts): GROUP BY camera, label, sub_label, the whole data JSON text, the local day and zones over every event in retention. Grouping on the JSON payload makes nearly every event its own group.
-- @param ?1 '%Y-%m-%d'
-- @param ?2 'unixepoch'
-- @param ?3 '-4 hour'
-- @param ?4 '0 minute'
-- @param ?5 1
-- @param ?6 'backyard'
-- @param ?7 'driveway'
-- @param ?8 'front_door'
-- @param ?9 'garage'
-- @param ?10 'kitchen'
-- @param ?11 'living_room'
-- @param ?12 'nursery'
-- @param ?13 'porch'
-- @param ?14 'side_gate'
-- @param ?15 'street'
-- @param ?16 1787408000.3
-- @param ?17 1789999915.68
-- @param ?18 -14400
-- @param ?19 86400
SELECT "t1"."camera", "t1"."label", "t1"."sub_label", "t1"."data", strftime(?1, datetime("t1"."start_time", ?2, ?3, ?4)) AS "day", "t1"."zones", COUNT("t1"."id") AS "count"
FROM "event" AS "t1"
WHERE (((?5 AND ("t1"."camera" IN (?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15))) AND ("t1"."start_time" >= ?16)) AND ("t1"."start_time" <= ?17))
GROUP BY "t1"."camera", "t1"."label", "t1"."sub_label", "t1"."data", (CAST(("t1"."start_time" + ?18) AS int) / ?19), "t1"."zones";

-- @id frigate.events.explore_distinct_labels
-- @src frigate/api/event.py:397-402
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic
-- @note Explore page, step 1: distinct labels over the allowed cameras. Touched by https://github.com/blakeblackshear/frigate/pull/23244.
-- @param ?1 'backyard'
-- @param ?2 'driveway'
-- @param ?3 'front_door'
-- @param ?4 'garage'
-- @param ?5 'kitchen'
-- @param ?6 'living_room'
-- @param ?7 'nursery'
-- @param ?8 'porch'
-- @param ?9 'side_gate'
-- @param ?10 'street'
SELECT DISTINCT "t1"."label"
FROM "event" AS "t1"
WHERE ("t1"."camera" IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10))
ORDER BY "t1"."label";

-- @id frigate.events.explore_label_latest
-- @src frigate/api/event.py:429-435
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic
-- @note Explore page, per label: the 10 most recent events (event_label_start_time index), run once per distinct label; https://github.com/blakeblackshear/frigate/pull/23244 narrowed the column list.
-- @param ?1 'person'
-- @param ?2 'backyard'
-- @param ?3 'driveway'
-- @param ?4 'front_door'
-- @param ?5 'garage'
-- @param ?6 'kitchen'
-- @param ?7 'living_room'
-- @param ?8 'nursery'
-- @param ?9 'porch'
-- @param ?10 'side_gate'
-- @param ?11 'street'
-- @param ?12 10
SELECT "t1"."id", "t1"."camera", "t1"."label", "t1"."sub_label", "t1"."zones", "t1"."start_time", "t1"."end_time", "t1"."has_clip", "t1"."has_snapshot", "t1"."plus_id", "t1"."retain_indefinitely", "t1"."top_score", "t1"."false_positive", "t1"."box", "t1"."data"
FROM "event" AS "t1"
WHERE (("t1"."label" = ?1) AND ("t1"."camera" IN (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)))
ORDER BY "t1"."start_time" DESC
LIMIT ?12;

-- @id frigate.events.explore_label_count
-- @src frigate/api/event.py:437-442
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,analytics
-- @note Explore page, per label: total events for the label over the allowed cameras (peewee .count() wraps the query in SELECT COUNT(1) FROM (...)).
-- @param ?1 'car'
-- @param ?2 'backyard'
-- @param ?3 'driveway'
-- @param ?4 'front_door'
-- @param ?5 'garage'
-- @param ?6 'kitchen'
-- @param ?7 'living_room'
-- @param ?8 'nursery'
-- @param ?9 'porch'
-- @param ?10 'side_gate'
-- @param ?11 'street'
SELECT COUNT(1)
FROM (SELECT "t1"."id", "t1"."label", "t1"."sub_label", "t1"."camera", "t1"."start_time", "t1"."end_time", "t1"."top_score", "t1"."score", "t1"."false_positive", "t1"."zones", "t1"."thumbnail", "t1"."has_clip", "t1"."has_snapshot", "t1"."region", "t1"."box", "t1"."area", "t1"."retain_indefinitely", "t1"."ratio", "t1"."plus_id", "t1"."model_hash", "t1"."detector_type", "t1"."model_type", "t1"."data"
FROM "event" AS "t1"
WHERE (("t1"."label" = ?1) AND ("t1"."camera" IN (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)))) AS "_wrapped";

-- @id frigate.timeline.latest_all_cameras
-- @src frigate/api/app.py:1715-1756
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,cpu-evidence
-- @note Timeline API default (camera=all, limit 100): camera IN all, ORDER BY timestamp, with no index on timestamp at this SHA, so every timeline row is read and sorted. https://github.com/blakeblackshear/frigate/pull/24043: 'latest timeline rows' more than 12 s, 2.33 s -> 1 ms with its (timestamp DESC) index, which was not merged.
-- @param ?1 'backyard'
-- @param ?2 'driveway'
-- @param ?3 'front_door'
-- @param ?4 'garage'
-- @param ?5 'kitchen'
-- @param ?6 'living_room'
-- @param ?7 'nursery'
-- @param ?8 'porch'
-- @param ?9 'side_gate'
-- @param ?10 'street'
-- @param ?11 100
SELECT "t1"."timestamp", "t1"."camera", "t1"."source", "t1"."source_id", "t1"."class_type", "t1"."data"
FROM "timeline" AS "t1"
WHERE ("t1"."camera" IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10))
ORDER BY "t1"."timestamp" ASC
LIMIT ?11;

-- @id frigate.timeline.hourly_person_24h
-- @src frigate/api/app.py:1759-1845
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,cpu-evidence
-- @note Hourly timeline for label person over 24 h: json_extract(data,'$.label') IN (...) plus a timestamp range with no timestamp index; newest 200. Same missing index as https://github.com/blakeblackshear/frigate/pull/24043.
-- @param ?1 'backyard'
-- @param ?2 'driveway'
-- @param ?3 'front_door'
-- @param ?4 'garage'
-- @param ?5 'kitchen'
-- @param ?6 'living_room'
-- @param ?7 'nursery'
-- @param ?8 'porch'
-- @param ?9 'side_gate'
-- @param ?10 'street'
-- @param ?11 '$."label"'
-- @param ?12 'person'
-- @param ?13 1790000000.0
-- @param ?14 1789913600.0
-- @param ?15 200
SELECT "t1"."camera", "t1"."timestamp", "t1"."data", "t1"."class_type", "t1"."source_id", "t1"."source"
FROM "timeline" AS "t1"
WHERE (((("t1"."camera" IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)) AND (json_extract("t1"."data", ?11) IN (?12))) AND ("t1"."timestamp" < ?13)) AND ("t1"."timestamp" > ?14))
ORDER BY "t1"."timestamp" DESC
LIMIT ?15;

-- @id frigate.timeline.by_source_id
-- @src frigate/api/app.py:1715-1756
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hot-small,dynamic
-- @note Object detail pane: the timeline of one tracked object (source_id index), camera IN all.
-- @param ?1 (SELECT source_id FROM timeline WHERE source_id IS NOT NULL ORDER BY timestamp DESC, source_id LIMIT 1 OFFSET 200)
-- @param ?2 'backyard'
-- @param ?3 'driveway'
-- @param ?4 'front_door'
-- @param ?5 'garage'
-- @param ?6 'kitchen'
-- @param ?7 'living_room'
-- @param ?8 'nursery'
-- @param ?9 'porch'
-- @param ?10 'side_gate'
-- @param ?11 'street'
-- @param ?12 100
SELECT "t1"."timestamp", "t1"."camera", "t1"."source", "t1"."source_id", "t1"."class_type", "t1"."data"
FROM "timeline" AS "t1"
WHERE (("t1"."source_id" = ?1) AND ("t1"."camera" IN (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)))
ORDER BY "t1"."timestamp" ASC
LIMIT ?12;

-- @id frigate.previews.range_all_cameras
-- @src frigate/api/preview.py:63-78
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,cpu-evidence
-- @note Preview clips overlapping the last 24 h for all cameras: three-way OR of BETWEENs and a containment test on a table with no secondary index. https://github.com/blakeblackshear/frigate/pull/24043: 1.53 s for 936 rows (40k previews).
-- @param ?1 1789913600.0
-- @param ?2 1790000000.0
-- @param ?3 1789913600.0
-- @param ?4 1790000000.0
-- @param ?5 1789913600.0
-- @param ?6 1790000000.0
-- @param ?7 'backyard'
-- @param ?8 'driveway'
-- @param ?9 'front_door'
-- @param ?10 'garage'
-- @param ?11 'kitchen'
-- @param ?12 'living_room'
-- @param ?13 'nursery'
-- @param ?14 'porch'
-- @param ?15 'side_gate'
-- @param ?16 'street'
SELECT "t1"."camera", "t1"."path", "t1"."duration", "t1"."start_time", "t1"."end_time"
FROM "previews" AS "t1"
WHERE (((("t1"."start_time" BETWEEN ?1 AND ?2) OR ("t1"."end_time" BETWEEN ?3 AND ?4)) OR (("t1"."start_time" < ?5) AND ("t1"."end_time" > ?6))) AND ("t1"."camera" IN (?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)))
ORDER BY "t1"."start_time" ASC;

-- @id frigate.recordings.camera_time_range
-- @src frigate/api/record.py:182-189
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hot-small,dynamic
-- @note Per-camera recordings summary, step 1: MIN/MAX(start_time) for one camera (index on camera, start_time).
-- @param ?1 'driveway'
SELECT MIN("t1"."start_time") AS "min_time", MAX("t1"."start_time") AS "max_time"
FROM "recordings" AS "t1"
WHERE ("t1"."camera" = ?1);

-- @id frigate.recordings.summary_hourly
-- @src frigate/api/record.py:220-233
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic,analytics
-- @note Per-camera recordings summary (history calendar): per local hour SUM(duration), SUM(motion), SUM(objects) for the main stream across the whole retention, grouped by CAST(start_time + offset AS int) / 3600, newest first.
-- @param ?1 '%Y-%m-%d %H'
-- @param ?2 'unixepoch'
-- @param ?3 '-4 hour'
-- @param ?4 '0 minute'
-- @param ?5 'driveway'
-- @param ?6 'main'
-- @param ?7 1787323100.37
-- @param ?8 1789999990.37
-- @param ?9 -14400
-- @param ?10 3600
SELECT strftime(?1, datetime("t1"."start_time", ?2, ?3, ?4)) AS "hour", SUM("t1"."duration") AS "duration", SUM("t1"."motion") AS "motion", SUM("t1"."objects") AS "objects"
FROM "recordings" AS "t1"
WHERE (((("t1"."camera" = ?5) AND ("t1"."stream_type" = ?6)) AND ("t1"."end_time" >= ?7)) AND ("t1"."start_time" <= ?8))
GROUP BY (CAST(("t1"."start_time" + ?9) AS int) / ?10)
ORDER BY "t1"."start_time" DESC;

-- @id frigate.recordings.day_has_recordings
-- @src frigate/api/record.py:137-145
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hot-small,dynamic
-- @note All-cameras recordings calendar: EXISTS-style probe (SELECT 1 ... LIMIT 1) for one local day, run once per day of retention.
-- @param ?1 'backyard'
-- @param ?2 'driveway'
-- @param ?3 'front_door'
-- @param ?4 'garage'
-- @param ?5 'kitchen'
-- @param ?6 'living_room'
-- @param ?7 'nursery'
-- @param ?8 'porch'
-- @param ?9 'side_gate'
-- @param ?10 'street'
-- @param ?11 1787323100.37
-- @param ?12 1789704000.0
-- @param ?13 1789790400.0
-- @param ?14 1
SELECT 1
FROM "recordings" AS "t1"
WHERE (((("t1"."camera" IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)) AND ("t1"."end_time" >= ?11)) AND ("t1"."start_time" >= ?12)) AND ("t1"."start_time" < ?13))
LIMIT ?14;

-- @id frigate.recordings.list_last_hour
-- @src frigate/api/record.py:369-391
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags hotpath,dynamic
-- @note Playback: one camera's main-stream segments for the last hour (start_time >= after - MAX_SEGMENT_DURATION), ordered by start_time.
-- @param ?1 'street'
-- @param ?2 'main'
-- @param ?3 1789995800.0
-- @param ?4 1789996400.0
-- @param ?5 1790000000.0
SELECT "t1"."id", "t1"."start_time", "t1"."end_time", "t1"."segment_size", "t1"."motion", "t1"."objects", "t1"."motion_heatmap", "t1"."duration"
FROM "recordings" AS "t1"
WHERE ((((("t1"."camera" = ?1) AND ("t1"."stream_type" = ?2)) AND ("t1"."start_time" >= ?3)) AND ("t1"."end_time" >= ?4)) AND ("t1"."start_time" <= ?5))
ORDER BY "t1"."start_time";

-- @id frigate.storage.camera_usage
-- @src frigate/storage.py:185-205
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags dynamic,analytics
-- @note Storage page: SUM(segment_size) per stream type for one camera over all its segments (segment_size != 0), run per camera.
-- @param ?1 'street'
-- @param ?2 0.0
SELECT "t1"."stream_type", SUM("t1"."segment_size") AS "usage"
FROM "recordings" AS "t1"
WHERE (("t1"."camera" = ?1) AND ("t1"."segment_size" != ?2))
GROUP BY "t1"."stream_type";

-- @id frigate.storage.recent_bandwidth
-- @src frigate/storage.py:83-109
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags dynamic,analytics
-- @note Storage maintainer: average MB/s over a stream's most recent 1000 segments (CASE inside a LIMITed derived table so the planner keeps the time-ordered index).
-- @param ?1 0.0
-- @param ?2 'driveway'
-- @param ?3 'main'
-- @param ?4 1000
SELECT AVG(bw)
FROM (SELECT CASE WHEN ("t1"."segment_size" > ?1) THEN ("t1"."segment_size" / ("t1"."end_time" - "t1"."start_time")) END AS "bw"
FROM "recordings" AS "t1"
WHERE (("t1"."camera" = ?2) AND ("t1"."stream_type" = ?3))
ORDER BY "t1"."start_time" DESC
LIMIT ?4) AS "recent";

-- @id frigate.cleanup.expire_recordings_scan
-- @src frigate/record/cleanup.py:162-190
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags dynamic
-- @note Hourly retention pass per camera and stream: segments older than the continuous cutoff that have no motion and no audio, or older than the motion cutoff (continuous 1 day, motion 30 days), in start_time order.
-- @param ?1 'driveway'
-- @param ?2 'main'
-- @param ?3 1789913600.0
-- @param ?4 1789913600.0
-- @param ?5 0
-- @param ?6 0
-- @param ?7 1787408000.0
SELECT "t1"."id", "t1"."start_time", "t1"."end_time", "t1"."path", "t1"."objects", "t1"."motion", "t1"."dBFS"
FROM "recordings" AS "t1"
WHERE (((("t1"."camera" = ?1) AND ("t1"."stream_type" = ?2)) AND ("t1"."start_time" < ?3)) AND (((("t1"."end_time" < ?4) AND ("t1"."motion" = ?5)) AND ("t1"."dBFS" = ?6)) OR ("t1"."end_time" < ?7)))
ORDER BY "t1"."start_time";

-- @id frigate.cleanup.delete_recordings_batch
-- @src frigate/record/cleanup.py:262-267
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags dynamic,batch
-- @note Retention delete: DELETE ... WHERE id IN (...) for the expired segment ids (batches of up to 100000; 100 here), touching 8 recordings indexes per row.
-- @param ?1 '1787323100.370000-102f60'
-- @param ?2 '1787323110.370000-d184c3'
-- @param ?3 '1787323120.370000-92da26'
-- @param ?4 '1787323130.370000-cde089'
-- @param ?5 '1787323140.370000-8f35ec'
-- @param ?6 '1787323150.370000-ca3c4f'
-- @param ?7 '1787323160.370000-8b91b2'
-- @param ?8 '1787323170.370000-4ce715'
-- @param ?9 '1787323180.370000-87ed78'
-- @param ?10 '1787323190.370000-4942db'
-- @param ?11 '1787323200.370000-0a983e'
-- @param ?12 '1787323210.370000-459ea1'
-- @param ?13 '1787323220.370000-06f404'
-- @param ?14 '1787323230.370000-41fa67'
-- @param ?15 '1787323240.370000-034fca'
-- @param ?16 '1787323250.370000-c4a52d'
-- @param ?17 '1787323260.370000-ffab90'
-- @param ?18 '1787323270.370000-c100f3'
-- @param ?19 '1787323280.370000-fc0756'
-- @param ?20 '1787323290.370000-bd5cb9'
-- @param ?21 '1787323300.370000-7eb21c'
-- @param ?22 '1787323310.370000-b9b87f'
-- @param ?23 '1787323320.370000-7b0de2'
-- @param ?24 '1787323330.370000-3c6345'
-- @param ?25 '1787323340.370000-7769a9'
-- @param ?26 '1787323350.370000-38bf0c'
-- @param ?27 '1787323360.370000-73c56f'
-- @param ?28 '1787323370.370000-351ad2'
-- @param ?29 '1787323380.370000-f67035'
-- @param ?30 '1787323390.370000-317698'
-- @param ?31 '1787324000.370000-31b630'
-- @param ?32 '1787324010.370000-f30b93'
-- @param ?33 '1787324020.370000-2e11f6'
-- @param ?34 '1787324030.370000-ef6759'
-- @param ?35 '1787324040.370000-2a6dbc'
-- @param ?36 '1787324050.370000-ebc31f'
-- @param ?37 '1787324060.370000-ad1882'
-- @param ?38 '1787324070.370000-e81ee6'
-- @param ?39 '1787324080.370000-a97449'
-- @param ?40 '1787324090.370000-6ac9ac'
-- @param ?41 '1787324100.370000-a5d00f'
-- @param ?42 '1787324110.370000-672572'
-- @param ?43 '1787324120.370000-a22bd5'
-- @param ?44 '1787324130.370000-638138'
-- @param ?45 '1787324140.370000-24d69b'
-- @param ?46 '1787324150.370000-5fdcfe'
-- @param ?47 '1787324160.370000-213261'
-- @param ?48 '1787324170.370000-5c38c4'
-- @param ?49 '1787324180.370000-1d8e27'
-- @param ?50 '1787324190.370000-dee38a'
-- @param ?51 '1787324200.370000-19e9ed'
-- @param ?52 '1787324210.370000-db3f50'
-- @param ?53 '1787324220.370000-9c94b3'
-- @param ?54 '1787324230.370000-d79b16'
-- @param ?55 '1787324240.370000-98f079'
-- @param ?56 '1787324250.370000-d3f6dc'
-- @param ?57 '1787324260.370000-954c3f'
-- @param ?58 '1787324270.370000-56a1a2'
-- @param ?59 '1787324280.370000-91a805'
-- @param ?60 '1787324290.370000-52fd68'
-- @param ?61 '1787336000.370000-28a061'
-- @param ?62 '1787336010.370000-63a6c4'
-- @param ?63 '1787336020.370000-24fc27'
-- @param ?64 '1787336030.370000-60028a'
-- @param ?65 '1787336040.370000-2157ed'
-- @param ?66 '1787336050.370000-e2ad50'
-- @param ?67 '1787336060.370000-1db3b3'
-- @param ?68 '1787336070.370000-df0916'
-- @param ?69 '1787336080.370000-a05e79'
-- @param ?70 '1787336090.370000-db64dc'
-- @param ?71 '1787336100.370000-9cba3f'
-- @param ?72 '1787336110.370000-d7c0a2'
-- @param ?73 '1787336120.370000-991605'
-- @param ?74 '1787336130.370000-5a6b68'
-- @param ?75 '1787336140.370000-9571cc'
-- @param ?76 '1787336150.370000-56c72f'
-- @param ?77 '1787336160.370000-91cd92'
-- @param ?78 '1787336170.370000-5322f5'
-- @param ?79 '1787336180.370000-147858'
-- @param ?80 '1787336190.370000-4f7ebb'
-- @param ?81 '1787336200.370000-10d41e'
-- @param ?82 '1787336210.370000-d22981'
-- @param ?83 '1787336220.370000-0d2fe4'
-- @param ?84 '1787336230.370000-ce8547'
-- @param ?85 '1787336240.370000-098baa'
-- @param ?86 '1787336250.370000-cae10d'
-- @param ?87 '1787336260.370000-8c3670'
-- @param ?88 '1787336270.370000-c73cd3'
-- @param ?89 '1787336280.370000-889236'
-- @param ?90 '1787336290.370000-49e799'
-- @param ?91 '1787340200.370000-e107d9'
-- @param ?92 '1787340210.370000-a25d3c'
-- @param ?93 '1787340220.370000-dd639f'
-- @param ?94 '1787340230.370000-9eb902'
-- @param ?95 '1787340240.370000-600e65'
-- @param ?96 '1787340250.370000-9b14c8'
-- @param ?97 '1787340260.370000-5c6a2b'
-- @param ?98 '1787340270.370000-97708e'
-- @param ?99 '1787340280.370000-58c5f1'
-- @param ?100 '1787340290.370000-1a1b54'
DELETE
FROM "recordings"
WHERE ("recordings"."id" IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48, ?49, ?50, ?51, ?52, ?53, ?54, ?55, ?56, ?57, ?58, ?59, ?60, ?61, ?62, ?63, ?64, ?65, ?66, ?67, ?68, ?69, ?70, ?71, ?72, ?73, ?74, ?75, ?76, ?77, ?78, ?79, ?80, ?81, ?82, ?83, ?84, ?85, ?86, ?87, ?88, ?89, ?90, ?91, ?92, ?93, ?94, ?95, ?96, ?97, ?98, ?99, ?100));

-- @id frigate.cleanup.expire_review_segments
-- @src frigate/record/cleanup.py:108-122
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags dynamic
-- @note Review retention per camera: alerts older than 30 days or detections older than 10 days.
-- @param ?1 'street'
-- @param ?2 'alert'
-- @param ?3 1787408000.0
-- @param ?4 'detection'
-- @param ?5 1789136000.0
SELECT "t1"."id", "t1"."thumb_path"
FROM "reviewsegment" AS "t1"
WHERE (("t1"."camera" = ?1) AND ((("t1"."severity" = ?2) AND ("t1"."end_time" < ?3)) OR (("t1"."severity" = ?4) AND ("t1"."end_time" < ?5))));

-- @id frigate.cleanup.expire_removed_camera_events
-- @src frigate/events/cleanup.py:212-228
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags dynamic
-- @note Event retention for cameras no longer in the config: camera NOT IN (configured cameras), older than the retention, not retained.
-- @param ?1 'backyard'
-- @param ?2 'driveway'
-- @param ?3 'front_door'
-- @param ?4 'garage'
-- @param ?5 'kitchen'
-- @param ?6 'living_room'
-- @param ?7 'nursery'
-- @param ?8 'porch'
-- @param ?9 'side_gate'
-- @param ?10 'street'
-- @param ?11 1787408000.0
-- @param ?12 0
SELECT "t1"."id", "t1"."camera"
FROM "event" AS "t1"
WHERE ((("t1"."camera" NOT IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)) AND ("t1"."start_time" < ?11)) AND ("t1"."retain_indefinitely" = ?12));

-- @id frigate.cleanup.events_without_media
-- @src frigate/events/cleanup.py:352-356
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags dynamic
-- @note Event cleanup: every column of events whose clip and snapshot have both expired (no index on has_clip/has_snapshot).
-- @param ?1 0
-- @param ?2 0
SELECT "t1"."id", "t1"."label", "t1"."sub_label", "t1"."camera", "t1"."start_time", "t1"."end_time", "t1"."top_score", "t1"."score", "t1"."false_positive", "t1"."zones", "t1"."thumbnail", "t1"."has_clip", "t1"."has_snapshot", "t1"."region", "t1"."box", "t1"."area", "t1"."retain_indefinitely", "t1"."ratio", "t1"."plus_id", "t1"."model_hash", "t1"."detector_type", "t1"."model_type", "t1"."data"
FROM "event" AS "t1"
WHERE (("t1"."has_clip" = ?1) AND ("t1"."has_snapshot" = ?2));

-- @id frigate.cleanup.delete_timeline_batch
-- @src frigate/events/cleanup.py:369
-- @style peewee 4.5 compiled for the sqlite dialect from a transcription of the handler's builder; ? positional
-- @tags dynamic,batch
-- @note Event cleanup: delete the timeline rows of the expired events (source_id IN list, timeline_source_id index).
-- @param ?1 '1786586119.500000-70c0e5'
-- @param ?2 '1786795596.500000-7e60d5'
-- @param ?3 '1787416301.910000-774b38'
-- @param ?4 '1787433059.210000-9f3447'
-- @param ?5 '1787449826.480000-c71d57'
-- @param ?6 '1787466583.780000-ef0667'
-- @param ?7 '1787483341.080000-16ef77'
-- @param ?8 '1787500108.350000-3ed887'
-- @param ?9 '1787516865.650000-66c197'
-- @param ?10 '1787533632.920000-8eaaa7'
-- @param ?11 '1787550390.220000-b693b7'
-- @param ?12 '1787567157.490000-de7cc7'
-- @param ?13 '1787583914.480000-d0dcd6'
-- @param ?14 '1787600681.750000-f8c5e6'
-- @param ?15 '1787617439.050000-20aef6'
-- @param ?16 '1787634196.350000-489806'
-- @param ?17 '1787650963.620000-708116'
-- @param ?18 '1787667720.920000-986a26'
-- @param ?19 '1787684488.190000-c05336'
-- @param ?20 '1787701245.490000-e83c46'
-- @param ?21 '1787718012.760000-102555'
-- @param ?22 '1787734770.060000-380e65'
-- @param ?23 '1787751527.050000-2a6e75'
-- @param ?24 '1787768294.320000-525785'
-- @param ?25 '1787785051.620000-7a4095'
-- @param ?26 '1787801818.890000-a229a5'
-- @param ?27 '1787818576.190000-ca12b5'
-- @param ?28 '1787835343.460000-f1fbc5'
-- @param ?29 '1787852100.760000-19e4d5'
-- @param ?30 '1787868858.060000-41cde4'
-- @param ?31 '1787885625.330000-69b6f4'
-- @param ?32 '1787902382.630000-5c1704'
-- @param ?33 '1787919149.590000-840014'
-- @param ?34 '1787935906.890000-abe924'
-- @param ?35 '1787952674.160000-d3d234'
-- @param ?36 '1787969431.460000-fbbb44'
-- @param ?37 '1787986198.730000-23a454'
-- @param ?38 '1788002956.030000-4b8d63'
-- @param ?39 '1788019713.330000-737673'
-- @param ?40 '1788036480.600000-9b5f83'
-- @param ?41 '1788053237.900000-c34893'
-- @param ?42 '1788070004.860000-b5a8a3'
-- @param ?43 '1788086762.160000-dd91b3'
-- @param ?44 '1788103529.430000-057ac3'
-- @param ?45 '1788120286.730000-2d63d3'
-- @param ?46 '1788137044.030000-554ce3'
-- @param ?47 '1788153811.300000-7d35f2'
-- @param ?48 '1788170568.600000-a51f02'
-- @param ?49 '1788187335.870000-cd0812'
-- @param ?50 '1788204093.170000-f4f122'
DELETE
FROM "timeline"
WHERE ("timeline"."source_id" IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48, ?49, ?50));
