-- Frigate NVR database (blakeblackshear/frigate @ a6b2a29c4c23deb7e23b4dcd8f3311c270342f5d, MIT).
-- The schema after migrations/001-040 have run (Frigate creates tables only through peewee_migrate), for the tables
-- the queries use. Raw-SQL migrations are copied verbatim; peewee migrator steps (add_fields, drop_not_null) are
-- rendered with peewee's SQLite column types (BooleanField INTEGER, JSONField JSON, FloatField REAL, CharField
-- VARCHAR(n), DateTimeField DATETIME). Timestamps are stored as float epoch seconds.
-- Indexes are exactly the ones the migrations create: 039 added event (camera, start_time); the review, timeline and
-- previews indexes proposed in frigate#24043 were never merged, so timeline has no timestamp index and previews none.

CREATE TABLE "event" ("id" VARCHAR(30) NOT NULL PRIMARY KEY, "label" VARCHAR(20) NOT NULL, "camera" VARCHAR(20) NOT NULL,
  "start_time" DATETIME NOT NULL, "end_time" DATETIME, "top_score" REAL, "false_positive" INTEGER DEFAULT 0,
  "zones" JSON NOT NULL, "thumbnail" TEXT, "has_clip" INTEGER NOT NULL DEFAULT 1, "has_snapshot" INTEGER NOT NULL DEFAULT 1,
  "region" JSON, "box" JSON, "area" INTEGER, "retain_indefinitely" INTEGER NOT NULL DEFAULT 0,
  "sub_label" VARCHAR(100), "ratio" REAL, "plus_id" VARCHAR(30), "score" REAL, "model_hash" VARCHAR(32),
  "detector_type" VARCHAR(32), "model_type" VARCHAR(32), "data" JSON NOT NULL DEFAULT '{}');
CREATE INDEX IF NOT EXISTS "event_label" ON "event" ("label");
CREATE INDEX IF NOT EXISTS "event_camera" ON "event" ("camera");
CREATE INDEX "event_start_time_end_time" ON "event" ("start_time" DESC, "end_time" DESC);
CREATE INDEX IF NOT EXISTS "event_label_start_time" ON "event" ("label", "start_time" DESC);
CREATE INDEX IF NOT EXISTS "event_camera_start_time" ON "event" ("camera", "start_time");

CREATE TABLE IF NOT EXISTS "recordings" ("id" VARCHAR(30) NOT NULL PRIMARY KEY, "camera" VARCHAR(20) NOT NULL,
  "path" VARCHAR(255) NOT NULL, "start_time" DATETIME NOT NULL, "end_time" DATETIME NOT NULL, "duration" REAL NOT NULL,
  "objects" INTEGER, "motion" INTEGER, "segment_size" REAL NOT NULL DEFAULT 0, "dBFS" INTEGER, "regions" INTEGER,
  "motion_heatmap" TEXT NULL, "stream_type" VARCHAR(8) NOT NULL DEFAULT 'main', "has_audio" INTEGER,
  "audio_rate" INTEGER, "audio_codec" TEXT, "video_codec" TEXT, "keyframes" TEXT, "audio_duration" REAL);
CREATE INDEX IF NOT EXISTS "recordings_camera" ON "recordings" ("camera");
CREATE UNIQUE INDEX IF NOT EXISTS "recordings_path" ON "recordings" ("path");
-- 006 created this before the "regions" column existed (it arrived in 023). Python's sqlite3 accepts a double-quoted
-- unknown identifier as a string literal (DQS), so on real databases the third key is the constant 'regions'.
CREATE INDEX "recordings_activity" ON "recordings" ("camera", "start_time" DESC, 'regions');
CREATE INDEX "recordings_camera_segment_size" ON "recordings" ("camera", "segment_size");
CREATE INDEX "recordings_camera_start_time_end_time" ON "recordings" ("camera", "start_time" DESC, "end_time" DESC);
CREATE INDEX "recordings_api_recordings_summary" ON "recordings" ("camera", "start_time" DESC, "duration", "motion", "objects");
CREATE INDEX "recordings_start_time" ON "recordings" ("start_time");
CREATE INDEX IF NOT EXISTS "recordings_camera_stream_type_start_time" ON "recordings" ("camera", "stream_type", "start_time" DESC);

CREATE TABLE IF NOT EXISTS "timeline" ("timestamp" DATETIME NOT NULL, "camera" VARCHAR(20) NOT NULL,
  "source" VARCHAR(20) NOT NULL, "source_id" VARCHAR(30), "class_type" VARCHAR(50) NOT NULL, "data" JSON);
CREATE INDEX IF NOT EXISTS "timeline_camera" ON "timeline" ("camera");
CREATE INDEX IF NOT EXISTS "timeline_source" ON "timeline" ("source");
CREATE INDEX IF NOT EXISTS "timeline_source_id" ON "timeline" ("source_id");

CREATE TABLE IF NOT EXISTS "previews" ("id" VARCHAR(30) NOT NULL PRIMARY KEY, "camera" VARCHAR(20) NOT NULL,
  "path" VARCHAR(255) NOT NULL, "start_time" DATETIME NOT NULL, "end_time" DATETIME NOT NULL, "duration" REAL NOT NULL);

-- 022, with has_been_reviewed dropped by 030 (ALTER TABLE ... DROP COLUMN).
CREATE TABLE IF NOT EXISTS "reviewsegment" ("id" VARCHAR(30) NOT NULL PRIMARY KEY, "camera" VARCHAR(20) NOT NULL,
  "start_time" DATETIME NOT NULL, "end_time" DATETIME, "severity" VARCHAR(30) NOT NULL,
  "thumb_path" VARCHAR(255) NOT NULL, "data" JSON NOT NULL);
CREATE INDEX IF NOT EXISTS "review_segment_camera" ON "reviewsegment" ("camera");
CREATE INDEX "review_segment_start_time_end_time" ON "reviewsegment" ("start_time" DESC, "end_time" DESC);

CREATE TABLE IF NOT EXISTS "userreviewstatus" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "user_id" VARCHAR(30) NOT NULL,
  "review_segment_id" VARCHAR(30) NOT NULL,
  "has_been_reviewed" INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY ("review_segment_id") REFERENCES "reviewsegment" ("id") ON DELETE CASCADE);
CREATE UNIQUE INDEX IF NOT EXISTS "userreviewstatus_user_segment" ON "userreviewstatus" ("user_id", "review_segment_id");
