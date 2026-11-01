-- screenpipe (screenpipe/screenpipe @ 892199f, 2026-06-10: the last commit under the MIT licence; see LICENSE).
-- Rust + sqlx against a plain SQLite database. Statements are copied from the pinned source: the activity-summary
-- statements from their format! literals (continuations resolved, IDLE_CAP_SECS=300 and the time range substituted);
-- the rest by hand, with the runtime-built pieces resolved for one instantiation. Unnumbered ? binds are renumbered
-- ?N in order. sqlx binds DateTime<Utc> as RFC 3339 text ('2026-10-20T00:00:00+00:00'); the activity summary inlines
-- '...Z' strings. Data covers 2026-08-29 .. 2026-10-27 (08:00-19:00 UTC each day).

-- @id screenpipe.activity.apps.week
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:375-390
-- @style format! string with literal timestamps (start/end formatted %Y-%m-%dT%H:%M:%SZ, sql_escape), run through execute_raw_sql; no binds
-- @tags analytics,hotpath,dynamic
-- @note GET /activity-summary for 7 days, the apps part: a LEAD() gap window per app over every frame in range (gaps over IDLE_CAP_SECS=300 count as idle), GROUP BY app, top 20 by minutes.
SELECT app_name, COUNT(*) as frame_count, ROUND(SUM(CASE WHEN gap_sec < 300 THEN gap_sec ELSE 0 END) / 60.0, 1) as minutes, MIN(ts) as first_seen, MAX(ts) as last_seen FROM ( SELECT app_name, timestamp as ts, (JULIANDAY(LEAD(timestamp) OVER (PARTITION BY app_name ORDER BY timestamp)) - JULIANDAY(timestamp)) * 86400 AS gap_sec FROM frames WHERE timestamp BETWEEN '2026-10-13T00:00:00Z' AND '2026-10-20T00:00:00Z' AND app_name IS NOT NULL AND app_name != '' ) gaps GROUP BY app_name ORDER BY minutes DESC LIMIT 20;

-- @id screenpipe.activity.apps.full_history
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:375-390
-- @style format! string with literal timestamps (start/end formatted %Y-%m-%dT%H:%M:%SZ, sql_escape), run through execute_raw_sql; no binds
-- @tags analytics,dynamic
-- @note The same statement with start = the first frame of the install and end = now, as the home activity ledger requests it: the window runs over all 100k frames.
SELECT app_name, COUNT(*) as frame_count, ROUND(SUM(CASE WHEN gap_sec < 300 THEN gap_sec ELSE 0 END) / 60.0, 1) as minutes, MIN(ts) as first_seen, MAX(ts) as last_seen FROM ( SELECT app_name, timestamp as ts, (JULIANDAY(LEAD(timestamp) OVER (PARTITION BY app_name ORDER BY timestamp)) - JULIANDAY(timestamp)) * 86400 AS gap_sec FROM frames WHERE timestamp BETWEEN '2026-08-29T08:00:00Z' AND '2026-10-28T09:00:00Z' AND app_name IS NOT NULL AND app_name != '' ) gaps GROUP BY app_name ORDER BY minutes DESC LIMIT 20;

-- @id screenpipe.activity.windows.week
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:392-410
-- @style format! string with literal timestamps (start/end formatted %Y-%m-%dT%H:%M:%SZ, sql_escape), run through execute_raw_sql; no binds
-- @tags analytics,dynamic
-- @note Activity summary's windows part for 7 days: LEAD() gap window partitioned by app and window title, GROUP BY both, top 30 by minutes.
SELECT app_name, window_name, COALESCE(browser_url, '') as browser_url, COUNT(*) as frame_count, ROUND(SUM(CASE WHEN gap_sec < 300 THEN gap_sec ELSE 0 END) / 60.0, 1) as minutes FROM ( SELECT app_name, COALESCE(window_name, '') as window_name, browser_url, (JULIANDAY(LEAD(timestamp) OVER (PARTITION BY app_name, window_name ORDER BY timestamp)) - JULIANDAY(timestamp)) * 86400 AS gap_sec FROM frames WHERE timestamp BETWEEN '2026-10-13T00:00:00Z' AND '2026-10-20T00:00:00Z' AND app_name IS NOT NULL AND app_name != '' AND window_name IS NOT NULL AND window_name != '' ) gaps GROUP BY app_name, window_name ORDER BY minutes DESC LIMIT 30;

-- @id screenpipe.activity.key_texts.day
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:415-437
-- @style format! string with literal timestamps (start/end formatted %Y-%m-%dT%H:%M:%SZ, sql_escape), run through execute_raw_sql; no binds
-- @tags analytics,dynamic
-- @note Representative accessibility text per app and window for one day: elements JOIN frames in range, ROW_NUMBER() preferring text inputs (AXTextArea/AXTextField) and then longer text, one row per context, newest 20.
SELECT text, app_name, window_name, timestamp FROM ( SELECT e.text, f.app_name, COALESCE(f.window_name, '') as window_name, f.timestamp, ROW_NUMBER() OVER ( PARTITION BY f.app_name, f.window_name ORDER BY CASE WHEN e.role IN ('AXTextArea', 'AXTextField') THEN 0 ELSE 1 END, LENGTH(e.text) DESC ) as rn FROM elements e JOIN frames f ON f.id = e.frame_id WHERE f.timestamp BETWEEN '2026-10-20T00:00:00Z' AND '2026-10-21T00:00:00Z' AND e.text IS NOT NULL AND e.source = 'accessibility' AND LENGTH(e.text) BETWEEN 30 AND 300 AND e.text NOT LIKE 'http%' AND e.text NOT LIKE 'cdn.%' ) ranked WHERE rn = 1 ORDER BY timestamp DESC LIMIT 20;

-- @id screenpipe.activity.key_texts.week_app
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:369-373,415-437
-- @style format! string with literal timestamps (start/end formatted %Y-%m-%dT%H:%M:%SZ, sql_escape), run through execute_raw_sql; no binds
-- @tags analytics,dynamic
-- @note Key texts for one week filtered to one app (app_filter_f adds f.app_name = ...), as pipes and the agent call it.
SELECT text, app_name, window_name, timestamp FROM ( SELECT e.text, f.app_name, COALESCE(f.window_name, '') as window_name, f.timestamp, ROW_NUMBER() OVER ( PARTITION BY f.app_name, f.window_name ORDER BY CASE WHEN e.role IN ('AXTextArea', 'AXTextField') THEN 0 ELSE 1 END, LENGTH(e.text) DESC ) as rn FROM elements e JOIN frames f ON f.id = e.frame_id WHERE f.timestamp BETWEEN '2026-10-13T00:00:00Z' AND '2026-10-20T00:00:00Z' AND f.app_name = 'Slack' AND e.text IS NOT NULL AND e.source = 'accessibility' AND LENGTH(e.text) BETWEEN 30 AND 300 AND e.text NOT LIKE 'http%' AND e.text NOT LIKE 'cdn.%' ) ranked WHERE rn = 1 ORDER BY timestamp DESC LIMIT 20;

-- @id screenpipe.activity.speakers.week
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:439-445
-- @style format! string with literal timestamps (start/end formatted %Y-%m-%dT%H:%M:%SZ, sql_escape), run through execute_raw_sql; no binds
-- @tags analytics
-- @note Activity summary's audio part: transcription segments per speaker for 7 days, LEFT JOIN speakers, GROUP BY speaker_id, top 10.
SELECT COALESCE(s.name, 'Unknown') as speaker_name, COUNT(*) as segment_count FROM audio_transcriptions at LEFT JOIN speakers s ON at.speaker_id = s.id WHERE at.timestamp BETWEEN '2026-10-13T00:00:00Z' AND '2026-10-20T00:00:00Z' GROUP BY at.speaker_id ORDER BY 2 DESC LIMIT 10;

-- @id screenpipe.activity.top_transcriptions.week
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:449-460
-- @style format! string with literal timestamps (start/end formatted %Y-%m-%dT%H:%M:%SZ, sql_escape), run through execute_raw_sql; no binds
-- @tags analytics,dynamic
-- @note Notable quotes for the summary prompt: the 20 longest non-blank transcriptions of the week, ORDER BY LENGTH(transcription) over every row in range.
SELECT at.transcription, COALESCE(s.name, 'Unknown') as speaker, at.device, at.timestamp FROM audio_transcriptions at LEFT JOIN speakers s ON at.speaker_id = s.id WHERE at.timestamp BETWEEN '2026-10-13T00:00:00Z' AND '2026-10-20T00:00:00Z' AND TRIM(at.transcription) != '' AND LENGTH(at.transcription) > 5 ORDER BY LENGTH(at.transcription) DESC LIMIT 20;

-- @id screenpipe.activity.edited_files.week
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:463-472
-- @style format! string with literal timestamps (sql_escape), sent through query_activity_summary_sql; no binds
-- @tags analytics,dynamic
-- @note Edited files: GROUP BY document_path over a week of frames, ORDER BY count, LIMIT 50.
SELECT document_path AS path, COUNT(*) AS frame_count FROM frames WHERE timestamp BETWEEN '2026-10-13T00:00:00Z' AND '2026-10-20T00:00:00Z' AND document_path IS NOT NULL AND document_path != '' GROUP BY document_path ORDER BY frame_count DESC, document_path ASC LIMIT 50;

-- @id screenpipe.search.ocr.fts_app_week
-- @src crates/screenpipe-db/src/db.rs:3788-3846
-- @style sqlx ?N numbered binds (12 always bound, unused ones NULL); the frames_fts join and MATCH are format!-ed in only when the FTS query is non-empty
-- @tags hotpath,dynamic,cpu-evidence
-- @note /search content_type=ocr q=deploy app_name=Slack for 7 days: app and text merged into one frames_fts MATCH (column filter app_name:"Slack" plus "deploy"), joined to frames, ocr_text and the tag tables, GROUP BY frame, ORDER BY timestamp, LIMIT 20. Search slowness on large DBs: https://github.com/screenpipe/screenpipe/issues/4474.
-- @param ?1 'app_name:"Slack" "deploy"'
-- @param ?2 '2026-10-13T00:00:00+00:00'
-- @param ?3 '2026-10-20T00:00:00+00:00'
-- @param ?4 NULL
-- @param ?5 NULL
-- @param ?6 NULL
-- @param ?7 NULL
-- @param ?8 NULL
-- @param ?9 NULL
-- @param ?10 20
-- @param ?11 0
-- @param ?12 '[]'
SELECT frames.id as frame_id, COALESCE(frames.full_text, ocr_text.text, frames.accessibility_text, '') as ocr_text, ocr_text.text_json, frames.timestamp, frames.name as frame_name, COALESCE(frames.snapshot_path, video_chunks.file_path) as file_path, frames.offset_index, frames.app_name, COALESCE(ocr_text.ocr_engine, '') as ocr_engine, frames.window_name, COALESCE(video_chunks.device_name, frames.device_name) as device_name, GROUP_CONCAT(tags.name, ',') as tags, frames.browser_url, frames.focused, frames.text_source
FROM frames
LEFT JOIN video_chunks ON frames.video_chunk_id = video_chunks.id
LEFT JOIN ocr_text ON frames.id = ocr_text.frame_id
LEFT JOIN vision_tags ON frames.id = vision_tags.vision_id
LEFT JOIN tags ON vision_tags.tag_id = tags.id
JOIN frames_fts ON frames.id = frames_fts.rowid
WHERE 1=1
  AND frames_fts MATCH ?1
  AND (?2 IS NULL OR frames.timestamp >= ?2)
  AND (?3 IS NULL OR frames.timestamp <= ?3)
  AND (?4 IS NULL OR LENGTH(COALESCE(frames.full_text, ocr_text.text, '')) >= ?4)
  AND (?5 IS NULL OR LENGTH(COALESCE(frames.full_text, ocr_text.text, '')) <= ?5)
  AND (?6 IS NULL OR COALESCE(video_chunks.device_name, frames.device_name) LIKE '%' || ?6 || '%')
  AND (?7 IS NULL OR frames.machine_id = ?7)
  AND (?8 IS NULL OR frames.focused = ?8)
  AND (?9 IS NULL OR frames.name LIKE '%' || ?9 || '%')
  AND (json_array_length(?12) = 0 OR frames.id IN (
    SELECT vt.vision_id
    FROM vision_tags vt
    JOIN tags t ON vt.tag_id = t.id
    WHERE t.name IN (SELECT value FROM json_each(?12))
    GROUP BY vt.vision_id
    HAVING COUNT(DISTINCT t.name) = json_array_length(?12)
  ))
GROUP BY frames.id
ORDER BY frames.timestamp DESC
LIMIT ?10 OFFSET ?11;

-- @id screenpipe.search.ocr.fts_all_history
-- @src crates/screenpipe-db/src/db.rs:3788-3846
-- @style sqlx ?N numbered binds (12 always bound, unused ones NULL); the frames_fts join and MATCH are format!-ed in only when the FTS query is non-empty
-- @tags hotpath,dynamic,cpu-evidence
-- @note /search q=invoice with no time bounds: every frames_fts match is joined, grouped and sorted by timestamp before LIMIT 20 (https://github.com/screenpipe/screenpipe/issues/4474).
-- @param ?1 '"invoice"'
-- @param ?2 NULL
-- @param ?3 NULL
-- @param ?4 NULL
-- @param ?5 NULL
-- @param ?6 NULL
-- @param ?7 NULL
-- @param ?8 NULL
-- @param ?9 NULL
-- @param ?10 20
-- @param ?11 0
-- @param ?12 '[]'
SELECT frames.id as frame_id, COALESCE(frames.full_text, ocr_text.text, frames.accessibility_text, '') as ocr_text, ocr_text.text_json, frames.timestamp, frames.name as frame_name, COALESCE(frames.snapshot_path, video_chunks.file_path) as file_path, frames.offset_index, frames.app_name, COALESCE(ocr_text.ocr_engine, '') as ocr_engine, frames.window_name, COALESCE(video_chunks.device_name, frames.device_name) as device_name, GROUP_CONCAT(tags.name, ',') as tags, frames.browser_url, frames.focused, frames.text_source
FROM frames
LEFT JOIN video_chunks ON frames.video_chunk_id = video_chunks.id
LEFT JOIN ocr_text ON frames.id = ocr_text.frame_id
LEFT JOIN vision_tags ON frames.id = vision_tags.vision_id
LEFT JOIN tags ON vision_tags.tag_id = tags.id
JOIN frames_fts ON frames.id = frames_fts.rowid
WHERE 1=1
  AND frames_fts MATCH ?1
  AND (?2 IS NULL OR frames.timestamp >= ?2)
  AND (?3 IS NULL OR frames.timestamp <= ?3)
  AND (?4 IS NULL OR LENGTH(COALESCE(frames.full_text, ocr_text.text, '')) >= ?4)
  AND (?5 IS NULL OR LENGTH(COALESCE(frames.full_text, ocr_text.text, '')) <= ?5)
  AND (?6 IS NULL OR COALESCE(video_chunks.device_name, frames.device_name) LIKE '%' || ?6 || '%')
  AND (?7 IS NULL OR frames.machine_id = ?7)
  AND (?8 IS NULL OR frames.focused = ?8)
  AND (?9 IS NULL OR frames.name LIKE '%' || ?9 || '%')
  AND (json_array_length(?12) = 0 OR frames.id IN (
    SELECT vt.vision_id
    FROM vision_tags vt
    JOIN tags t ON vt.tag_id = t.id
    WHERE t.name IN (SELECT value FROM json_each(?12))
    GROUP BY vt.vision_id
    HAVING COUNT(DISTINCT t.name) = json_array_length(?12)
  ))
GROUP BY frames.id
ORDER BY frames.timestamp DESC
LIMIT ?10 OFFSET ?11;

-- @id screenpipe.search.ocr.focused_tags_month
-- @src crates/screenpipe-db/src/db.rs:3788-3846
-- @style sqlx ?N numbered binds (12 always bound, unused ones NULL); the frames_fts join and MATCH are format!-ed in only when the FTS query is non-empty
-- @tags dynamic
-- @note Filter-only search (no text, so no FTS join): focused frames tagged "work" over 30 days; the tag filter is a GROUP BY/HAVING COUNT(DISTINCT) IN-subquery over vision_tags evaluated against a time-range scan.
-- @param ?1 NULL
-- @param ?2 '2026-09-20T00:00:00+00:00'
-- @param ?3 '2026-10-20T00:00:00+00:00'
-- @param ?4 NULL
-- @param ?5 NULL
-- @param ?6 NULL
-- @param ?7 NULL
-- @param ?8 1
-- @param ?9 NULL
-- @param ?10 50
-- @param ?11 0
-- @param ?12 '["work"]'
SELECT frames.id as frame_id, COALESCE(frames.full_text, ocr_text.text, frames.accessibility_text, '') as ocr_text, ocr_text.text_json, frames.timestamp, frames.name as frame_name, COALESCE(frames.snapshot_path, video_chunks.file_path) as file_path, frames.offset_index, frames.app_name, COALESCE(ocr_text.ocr_engine, '') as ocr_engine, frames.window_name, COALESCE(video_chunks.device_name, frames.device_name) as device_name, GROUP_CONCAT(tags.name, ',') as tags, frames.browser_url, frames.focused, frames.text_source
FROM frames
LEFT JOIN video_chunks ON frames.video_chunk_id = video_chunks.id
LEFT JOIN ocr_text ON frames.id = ocr_text.frame_id
LEFT JOIN vision_tags ON frames.id = vision_tags.vision_id
LEFT JOIN tags ON vision_tags.tag_id = tags.id

WHERE 1=1
  
  AND (?2 IS NULL OR frames.timestamp >= ?2)
  AND (?3 IS NULL OR frames.timestamp <= ?3)
  AND (?4 IS NULL OR LENGTH(COALESCE(frames.full_text, ocr_text.text, '')) >= ?4)
  AND (?5 IS NULL OR LENGTH(COALESCE(frames.full_text, ocr_text.text, '')) <= ?5)
  AND (?6 IS NULL OR COALESCE(video_chunks.device_name, frames.device_name) LIKE '%' || ?6 || '%')
  AND (?7 IS NULL OR frames.machine_id = ?7)
  AND (?8 IS NULL OR frames.focused = ?8)
  AND (?9 IS NULL OR frames.name LIKE '%' || ?9 || '%')
  AND (json_array_length(?12) = 0 OR frames.id IN (
    SELECT vt.vision_id
    FROM vision_tags vt
    JOIN tags t ON vt.tag_id = t.id
    WHERE t.name IN (SELECT value FROM json_each(?12))
    GROUP BY vt.vision_id
    HAVING COUNT(DISTINCT t.name) = json_array_length(?12)
  ))
GROUP BY frames.id
ORDER BY frames.timestamp DESC
LIMIT ?10 OFFSET ?11;

-- @id screenpipe.search.ocr.browse_page
-- @src crates/screenpipe-db/src/db.rs:3788-3846
-- @style sqlx ?N numbered binds (12 always bound, unused ones NULL); the frames_fts join and MATCH are format!-ed in only when the FTS query is non-empty
-- @tags hotpath,dynamic
-- @note Unfiltered browse (empty q): page 3 of the last day, newest first. With no FTS query the statement scans the day's frames, groups them with their tags and sorts before OFFSET 100.
-- @param ?1 NULL
-- @param ?2 '2026-10-26T00:00:00+00:00'
-- @param ?3 '2026-10-27T00:00:00+00:00'
-- @param ?4 NULL
-- @param ?5 NULL
-- @param ?6 NULL
-- @param ?7 NULL
-- @param ?8 NULL
-- @param ?9 NULL
-- @param ?10 50
-- @param ?11 100
-- @param ?12 '[]'
SELECT frames.id as frame_id, COALESCE(frames.full_text, ocr_text.text, frames.accessibility_text, '') as ocr_text, ocr_text.text_json, frames.timestamp, frames.name as frame_name, COALESCE(frames.snapshot_path, video_chunks.file_path) as file_path, frames.offset_index, frames.app_name, COALESCE(ocr_text.ocr_engine, '') as ocr_engine, frames.window_name, COALESCE(video_chunks.device_name, frames.device_name) as device_name, GROUP_CONCAT(tags.name, ',') as tags, frames.browser_url, frames.focused, frames.text_source
FROM frames
LEFT JOIN video_chunks ON frames.video_chunk_id = video_chunks.id
LEFT JOIN ocr_text ON frames.id = ocr_text.frame_id
LEFT JOIN vision_tags ON frames.id = vision_tags.vision_id
LEFT JOIN tags ON vision_tags.tag_id = tags.id

WHERE 1=1
  
  AND (?2 IS NULL OR frames.timestamp >= ?2)
  AND (?3 IS NULL OR frames.timestamp <= ?3)
  AND (?4 IS NULL OR LENGTH(COALESCE(frames.full_text, ocr_text.text, '')) >= ?4)
  AND (?5 IS NULL OR LENGTH(COALESCE(frames.full_text, ocr_text.text, '')) <= ?5)
  AND (?6 IS NULL OR COALESCE(video_chunks.device_name, frames.device_name) LIKE '%' || ?6 || '%')
  AND (?7 IS NULL OR frames.machine_id = ?7)
  AND (?8 IS NULL OR frames.focused = ?8)
  AND (?9 IS NULL OR frames.name LIKE '%' || ?9 || '%')
  AND (json_array_length(?12) = 0 OR frames.id IN (
    SELECT vt.vision_id
    FROM vision_tags vt
    JOIN tags t ON vt.tag_id = t.id
    WHERE t.name IN (SELECT value FROM json_each(?12))
    GROUP BY vt.vision_id
    HAVING COUNT(DISTINCT t.name) = json_array_length(?12)
  ))
GROUP BY frames.id
ORDER BY frames.timestamp DESC
LIMIT ?10 OFFSET ?11;

-- @id screenpipe.search.count.ocr_fts_month
-- @src crates/screenpipe-db/src/db.rs:4833-4864
-- @style sqlx ?N numbered binds; FTS join and time bounds format!-ed in
-- @tags hotpath,dynamic,cpu-evidence
-- @note Total-count companion of every /search page: COUNT(DISTINCT frames.id) over all frames_fts matches for "invoice" in 30 days; runs alongside the page query (https://github.com/screenpipe/screenpipe/issues/4474).
-- @param ?1 '"invoice"'
-- @param ?2 '2026-09-20T00:00:00+00:00'
-- @param ?3 '2026-10-20T00:00:00+00:00'
-- @param ?4 NULL
-- @param ?5 NULL
-- @param ?6 NULL
-- @param ?7 NULL
-- @param ?8 '[]'
SELECT COUNT(DISTINCT frames.id)
FROM frames
JOIN frames_fts ON frames.id = frames_fts.rowid
WHERE 1=1
  AND frames_fts MATCH ?1
  AND frames.timestamp >= ?2
  AND frames.timestamp <= ?3
  AND (?4 IS NULL OR LENGTH(COALESCE(frames.full_text, '')) >= ?4)
  AND (?5 IS NULL OR LENGTH(COALESCE(frames.full_text, '')) <= ?5)
  AND (?6 IS NULL OR frames.name LIKE '%' || ?6 || '%')
  AND (?7 IS NULL OR frames.focused = ?7)
  AND (json_array_length(?8) = 0 OR frames.id IN (
    SELECT vt.vision_id
    FROM vision_tags vt
    JOIN tags t ON vt.tag_id = t.id
    WHERE t.name IN (SELECT value FROM json_each(?8))
    GROUP BY vt.vision_id
    HAVING COUNT(DISTINCT t.name) = json_array_length(?8)
  ));

-- @id screenpipe.search.audio.fts_month
-- @src crates/screenpipe-db/src/db.rs:3973-4118
-- @style sqlx positional ? binds in condition order (renumbered ?N); WHERE assembled from optional filters
-- @tags hotpath,dynamic,cpu-evidence
-- @note /search content_type=audio q=budget over 30 days: FTS IN-subquery ranked by bm25 with LIMIT 5000, five correlated diarization_segments lookups per result row (ABS time-alignment), tag LEFT JOINs + GROUP BY (https://github.com/screenpipe/screenpipe/issues/4474).
-- @param ?1 '"budget"'
-- @param ?2 '2026-09-20T00:00:00+00:00'
-- @param ?3 '2026-10-20T00:00:00+00:00'
-- @param ?4 20
-- @param ?5 0
SELECT
  audio_transcriptions.audio_chunk_id,
  audio_transcriptions.transcription,
  audio_transcriptions.timestamp,
  audio_chunks.file_path,
  audio_transcriptions.offset_index,
  audio_transcriptions.transcription_engine,
  GROUP_CONCAT(tags.name, ',') as tags,
  audio_transcriptions.device as device_name,
  audio_transcriptions.is_input_device,
  audio_transcriptions.speaker_id,
  audio_transcriptions.start_time,
  audio_transcriptions.end_time,
  (SELECT dr.mode FROM diarization_segments ds JOIN diarization_runs dr ON dr.id = ds.diarization_run_id WHERE ds.audio_chunk_id = audio_transcriptions.audio_chunk_id AND audio_transcriptions.start_time IS NOT NULL AND audio_transcriptions.end_time IS NOT NULL AND ABS(ds.start_time - audio_transcriptions.start_time) < 0.05 AND ABS(ds.end_time - audio_transcriptions.end_time) < 0.05 ORDER BY dr.created_at DESC, ds.id DESC LIMIT 1) AS diarization_mode,
  (SELECT ds.provider_speaker_label FROM diarization_segments ds JOIN diarization_runs dr ON dr.id = ds.diarization_run_id WHERE ds.audio_chunk_id = audio_transcriptions.audio_chunk_id AND audio_transcriptions.start_time IS NOT NULL AND audio_transcriptions.end_time IS NOT NULL AND ABS(ds.start_time - audio_transcriptions.start_time) < 0.05 AND ABS(ds.end_time - audio_transcriptions.end_time) < 0.05 ORDER BY dr.created_at DESC, ds.id DESC LIMIT 1) AS diarization_speaker_label,
  (SELECT dr.provider FROM diarization_segments ds JOIN diarization_runs dr ON dr.id = ds.diarization_run_id WHERE ds.audio_chunk_id = audio_transcriptions.audio_chunk_id AND audio_transcriptions.start_time IS NOT NULL AND audio_transcriptions.end_time IS NOT NULL AND ABS(ds.start_time - audio_transcriptions.start_time) < 0.05 AND ABS(ds.end_time - audio_transcriptions.end_time) < 0.05 ORDER BY dr.created_at DESC, ds.id DESC LIMIT 1) AS diarization_provider,
  (SELECT ds.source FROM diarization_segments ds JOIN diarization_runs dr ON dr.id = ds.diarization_run_id WHERE ds.audio_chunk_id = audio_transcriptions.audio_chunk_id AND audio_transcriptions.start_time IS NOT NULL AND audio_transcriptions.end_time IS NOT NULL AND ABS(ds.start_time - audio_transcriptions.start_time) < 0.05 AND ABS(ds.end_time - audio_transcriptions.end_time) < 0.05 ORDER BY dr.created_at DESC, ds.id DESC LIMIT 1) AS diarization_source,
  (SELECT ds.confidence FROM diarization_segments ds JOIN diarization_runs dr ON dr.id = ds.diarization_run_id WHERE ds.audio_chunk_id = audio_transcriptions.audio_chunk_id AND audio_transcriptions.start_time IS NOT NULL AND audio_transcriptions.end_time IS NOT NULL AND ABS(ds.start_time - audio_transcriptions.start_time) < 0.05 AND ABS(ds.end_time - audio_transcriptions.end_time) < 0.05 ORDER BY dr.created_at DESC, ds.id DESC LIMIT 1) AS diarization_confidence
FROM audio_transcriptions
JOIN audio_chunks ON audio_transcriptions.audio_chunk_id = audio_chunks.id
LEFT JOIN speakers ON audio_transcriptions.speaker_id = speakers.id
LEFT JOIN audio_tags ON audio_chunks.id = audio_tags.audio_chunk_id
LEFT JOIN tags ON audio_tags.tag_id = tags.id
WHERE audio_transcriptions.audio_chunk_id IN (SELECT at_inner.audio_chunk_id FROM audio_transcriptions_fts JOIN audio_transcriptions at_inner ON at_inner.id = audio_transcriptions_fts.rowid WHERE audio_transcriptions_fts MATCH ?1 ORDER BY audio_transcriptions_fts.rank LIMIT 5000) AND audio_transcriptions.timestamp >= ?2 AND audio_transcriptions.timestamp <= ?3 AND (speakers.id IS NULL OR speakers.hallucination = 0) AND audio_chunks.file_path NOT LIKE 'cloud://%'
GROUP BY audio_transcriptions.audio_chunk_id, audio_transcriptions.offset_index ORDER BY audio_transcriptions.timestamp DESC LIMIT ?4 OFFSET ?5;

-- @id screenpipe.search.count.input_like
-- @src crates/screenpipe-db/src/db.rs:4944-4972
-- @style sqlx positional ? binds (renumbered ?N); LIKE conditions pushed per filter
-- @tags dynamic,cpu-evidence
-- @note Input-event count for /search content_type=input q=deploy: three leading-wildcard LIKEs OR-ed over every ui_event in the window (no FTS), 30 days (https://github.com/screenpipe/screenpipe/issues/4474).
-- @param ?1 'deploy'
-- @param ?2 'deploy'
-- @param ?3 'deploy'
-- @param ?4 '2026-09-20T00:00:00+00:00'
-- @param ?5 '2026-09-20T00:00:00+00:00'
-- @param ?6 '2026-10-20T00:00:00+00:00'
-- @param ?7 '2026-10-20T00:00:00+00:00'
SELECT COUNT(*) FROM ui_events WHERE (text_content LIKE '%' || ?1 || '%' OR app_name LIKE '%' || ?2 || '%' OR window_title LIKE '%' || ?3 || '%') AND (?4 IS NULL OR timestamp >= ?5) AND (?6 IS NULL OR timestamp <= ?7);

-- @id screenpipe.search.grouped_matches
-- @src crates/screenpipe-db/src/db.rs:7884-7965
-- @style sqlx positional ? binds (renumbered ?N); IN list expanded per app; the max_per_app branch (no cap here) not taken
-- @tags hotpath,dynamic,cpu-evidence
-- @note Search-results grid (search_for_grouping): frames in 30 days for two apps whose id is in the top-5000 bm25 frames_fts matches, newest first, LIMIT 5000 rows handed to Rust for episode grouping (https://github.com/screenpipe/screenpipe/issues/4474).
-- @param ?1 '2026-09-20T00:00:00+00:00'
-- @param ?2 '2026-10-20T00:00:00+00:00'
-- @param ?3 'Google Chrome'
-- @param ?4 'Slack'
-- @param ?5 '"invoice"'
-- @param ?6 5000
-- @param ?7 0
SELECT
  f.id,
  f.timestamp,
  f.browser_url as url,
  COALESCE(f.app_name, '') as app_name,
  COALESCE(f.window_name, '') as window_name
FROM frames f
WHERE f.timestamp >= ?1 AND f.timestamp <= ?2 AND f.app_name IN (?3,?4) AND f.id IN (SELECT rowid FROM frames_fts WHERE frames_fts MATCH ?5 ORDER BY rank LIMIT 5000)
ORDER BY f.timestamp DESC
LIMIT ?6 OFFSET ?7;

-- @id screenpipe.elements.search_fts
-- @src crates/screenpipe-db/src/db.rs:7708-7756
-- @style sqlx positional ? binds in condition order (renumbered ?N)
-- @tags hotpath,dynamic
-- @note /elements?q=invoice&source=accessibility over 30 days: elements_fts JOIN elements JOIN frames, ORDER BY frame_id DESC, sort_order, LIMIT 50.
-- @param ?1 '"invoice"'
-- @param ?2 'accessibility'
-- @param ?3 '2026-09-20T00:00:00+00:00'
-- @param ?4 '2026-10-20T00:00:00+00:00'
-- @param ?5 50
-- @param ?6 0
SELECT e.id, e.frame_id, e.source, e.role, e.text, e.parent_id,
       e.depth, e.left_bound, e.top_bound, e.width_bound, e.height_bound,
       e.confidence, e.sort_order, e.on_screen
FROM elements e
JOIN frames f ON f.id = e.frame_id
JOIN elements_fts fts ON fts.rowid = e.id
WHERE fts.text MATCH ?1 AND e.source = ?2 AND f.timestamp >= ?3 AND f.timestamp <= ?4
ORDER BY e.frame_id DESC, e.sort_order ASC
LIMIT ?5 OFFSET ?6;

-- @id screenpipe.timeline.frames_day
-- @src crates/screenpipe-db/src/db.rs:5335-5364
-- @style sqlx ?N numbered binds
-- @tags hotpath,dynamic
-- @note Timeline stream for one day: every frame in range with 200-char text previews (correlated ocr_text fallbacks for text, app and window), LEFT JOIN video_chunks, NOT LIKE cloud filter, ordered by timestamp/offset, LIMIT 10000.
-- @param ?1 '2026-09-15T00:00:00+00:00'
-- @param ?2 '2026-09-16T00:00:00+00:00'
SELECT
  f.id,
  f.timestamp,
  f.offset_index,
  COALESCE(
    SUBSTR(f.full_text, 1, 200),
    SUBSTR(f.accessibility_text, 1, 200),
    (SELECT SUBSTR(ot.text, 1, 200) FROM ocr_text ot WHERE ot.frame_id = f.id LIMIT 1)
  ) as text,
  COALESCE(
    f.app_name,
    (SELECT ot.app_name FROM ocr_text ot WHERE ot.frame_id = f.id LIMIT 1)
  ) as app_name,
  COALESCE(
    f.window_name,
    (SELECT ot.window_name FROM ocr_text ot WHERE ot.frame_id = f.id LIMIT 1)
  ) as window_name,
  COALESCE(vc.device_name, f.device_name) as screen_device,
  COALESCE(vc.file_path, f.snapshot_path) as video_path,
  COALESCE(vc.fps, 0.033) as chunk_fps,
  f.browser_url,
  f.machine_id
FROM frames f
LEFT JOIN video_chunks vc ON f.video_chunk_id = vc.id
WHERE f.timestamp >= ?1 AND f.timestamp <= ?2
  AND COALESCE(vc.file_path, f.snapshot_path, '') NOT LIKE 'cloud://%'
ORDER BY f.timestamp DESC, f.offset_index DESC
LIMIT 10000;

-- @id screenpipe.timeline.audio_day
-- @src crates/screenpipe-db/src/db.rs:5367-5389
-- @style sqlx ?N numbered binds
-- @tags hotpath,dynamic
-- @note Timeline stream for one day, audio side: transcriptions in range JOIN audio_chunks LEFT JOIN speakers, per-row duration from julianday(datetime(...)) arithmetic, NOT LIKE cloud filter, newest first, LIMIT 10000.
-- @param ?1 '2026-09-15T00:00:00+00:00'
-- @param ?2 '2026-09-16T00:00:00+00:00'
SELECT
  at.timestamp,
  at.transcription,
  at.device as audio_device,
  at.is_input_device,
  ac.file_path as audio_path,
  ac.id as audio_chunk_id,
  at.start_time,
  at.end_time,
  at.speaker_id,
  s.name as speaker_name,
  CAST((julianday(datetime(at.timestamp, '+' || at.end_time || ' seconds')) -
        julianday(datetime(at.timestamp, '+' || at.start_time || ' seconds'))) * 86400
       as REAL) as duration_secs
FROM audio_transcriptions at
JOIN audio_chunks ac ON at.audio_chunk_id = ac.id
LEFT JOIN speakers s ON at.speaker_id = s.id
WHERE at.timestamp >= ?1 AND at.timestamp <= ?2
  AND ac.file_path NOT LIKE 'cloud://%'
ORDER BY at.timestamp DESC
LIMIT 10000;

-- @id screenpipe.speakers.active_in_range
-- @src crates/screenpipe-db/src/db.rs:2267-2281
-- @style sqlx ?N numbered binds
-- @tags analytics
-- @note Active speakers over a month: transcriptions in range JOIN speakers, GROUP BY speaker and input/output device, ORDER BY count.
-- @param ?1 '2026-09-20T00:00:00+00:00'
-- @param ?2 '2026-10-20T00:00:00+00:00'
SELECT
  at.speaker_id,
  COALESCE(s.name, '') as speaker_name,
  at.is_input_device,
  CAST(COUNT(*) AS INTEGER) as transcription_count
FROM audio_transcriptions at
INNER JOIN speakers s ON at.speaker_id = s.id
WHERE at.speaker_id IS NOT NULL
  AND at.timestamp >= ?1
  AND at.timestamp <= ?2
  AND (s.hallucination IS NULL OR s.hallucination = 0)
GROUP BY at.speaker_id, at.is_input_device
ORDER BY transcription_count DESC;

-- @id screenpipe.speakers.unnamed
-- @src crates/screenpipe-db/src/db.rs:5961-6031
-- @style sqlx positional ? binds (renumbered ?N); speaker IN-list omitted (no filter)
-- @tags analytics,dynamic
-- @note Speaker-naming page: CTE of each unnamed speaker's 3 latest transcriptions (correlated IN ... ORDER BY timestamp DESC LIMIT 3), joined back to all their transcriptions, json_group_array(DISTINCT json_object(...)) samples, GROUP BY speaker ORDER BY count.
-- @param ?1 10
-- @param ?2 0
WITH RecentAudioPaths AS (
  SELECT DISTINCT
    s.id as speaker_id,
    ac.file_path,
    at.transcription,
    at.start_time,
    at.end_time,
    CAST(unixepoch(at.timestamp) AS INTEGER) as abs_timestamp
  FROM speakers s
  JOIN audio_transcriptions at ON s.id = at.speaker_id
  JOIN audio_chunks ac ON at.audio_chunk_id = ac.id
  WHERE (s.name = '' OR s.name IS NULL)
  AND s.hallucination = 0
  AND ac.file_path NOT LIKE 'cloud://%'
  AND at.timestamp IN (
    SELECT timestamp
    FROM audio_transcriptions at2
    WHERE at2.speaker_id = s.id
    ORDER BY timestamp DESC
    LIMIT 3
  )
)
SELECT
  s.id,
  s.name,
  CASE
    WHEN s.metadata = '' OR s.metadata IS NULL OR json_valid(s.metadata) = 0
    THEN json_object('audio_samples', json_group_array(
      DISTINCT json_object('path', rap.file_path, 'transcript', rap.transcription, 'start_time', rap.start_time, 'end_time', rap.end_time, 'timestamp', rap.abs_timestamp)
    ))
    ELSE json_patch(
      json(s.metadata),
      json_object('audio_samples', json_group_array(
        DISTINCT json_object('path', rap.file_path, 'transcript', rap.transcription, 'start_time', rap.start_time, 'end_time', rap.end_time, 'timestamp', rap.abs_timestamp)
      ))
    )
  END as metadata,
  COUNT(at.id) as transcription_count
FROM speakers s
JOIN RecentAudioPaths rap ON s.id = rap.speaker_id
JOIN audio_transcriptions at ON s.id = at.speaker_id
GROUP BY s.id
ORDER BY transcription_count DESC
LIMIT ?1 OFFSET ?2;

-- @id screenpipe.ui.event_stats
-- @src crates/screenpipe-db/src/db.rs:5909-5920
-- @style sqlx ?N numbered binds
-- @tags analytics
-- @note Input statistics: GROUP BY app_name, event_type over 30 days of ui_events, ORDER BY count, LIMIT 100.
-- @param ?1 '2026-09-20T00:00:00+00:00'
-- @param ?2 '2026-10-20T00:00:00+00:00'
SELECT
  COALESCE(app_name, 'unknown') as app,
  event_type,
  COUNT(*) as count
FROM ui_events
WHERE (?1 IS NULL OR timestamp >= ?1)
  AND (?2 IS NULL OR timestamp <= ?2)
GROUP BY app_name, event_type
ORDER BY count DESC
LIMIT 100;

-- @id screenpipe.maintenance.count_by_machine
-- @src crates/screenpipe-db/src/db.rs:7137-7140
-- @style no binds
-- @tags analytics
-- @note Per-machine frame counts for the sync/storage settings page: GROUP BY machine_id over every frame (no machine_id index).
SELECT machine_id, COUNT(*) FROM frames WHERE machine_id IS NOT NULL GROUP BY machine_id;

-- @id screenpipe.retention.video_files_in_slice
-- @src crates/screenpipe-db/src/db.rs:6831-6834
-- @style sqlx ?N numbered binds (rfc3339 strings)
-- @tags batch,expect-empty
-- @note Retention slice (2 hours): video files whose every frame is in range. The NOT IN subquery reads every frame outside the slice (frames.timestamp NOT BETWEEN), i.e. the whole table, per slice. Returns no rows: event-driven snapshot frames have a NULL video_chunk_id, and NOT IN over a set with a NULL is never true (later versions add IS NOT NULL to both subqueries).
-- @param ?1 '2026-08-29T09:00:00+00:00'
-- @param ?2 '2026-08-29T11:00:00+00:00'
SELECT file_path FROM video_chunks
WHERE id IN (SELECT DISTINCT video_chunk_id FROM frames WHERE timestamp BETWEEN ?1 AND ?2)
AND id NOT IN (SELECT DISTINCT video_chunk_id FROM frames WHERE timestamp NOT BETWEEN ?1 AND ?2)
AND file_path NOT LIKE 'cloud://%';

-- @id screenpipe.retention.delete_frames_slice
-- @src crates/screenpipe-db/src/db.rs:6928
-- @style sqlx ?N numbered binds (rfc3339 strings)
-- @tags batch,cpu-evidence
-- @note Retention delete of a 2-hour slice of frames: each row fires frames_ad (external-content frames_fts 'delete' with the old text). https://github.com/screenpipe/screenpipe/issues/2930 measured 4 min 39 s for 6,548 frames with the earlier standalone FTS table.
-- @param ?1 '2026-08-29T09:00:00+00:00'
-- @param ?2 '2026-08-29T11:00:00+00:00'
DELETE FROM frames WHERE timestamp BETWEEN ?1 AND ?2;

-- @id screenpipe.retention.delete_elements_slice
-- @src crates/screenpipe-db/src/db.rs:6920
-- @style sqlx ?N numbered binds (rfc3339 strings)
-- @tags batch
-- @note Elements of the same slice, deleted first: IN-subquery on frames by timestamp, elements_ad trigger per row into elements_fts.
-- @param ?1 '2026-08-29T09:00:00+00:00'
-- @param ?2 '2026-08-29T11:00:00+00:00'
DELETE FROM elements WHERE frame_id IN (SELECT id FROM frames WHERE timestamp BETWEEN ?1 AND ?2);

-- @id screenpipe.retention.cleanup_orphaned_video_chunks
-- @src crates/screenpipe-db/src/db.rs:6995
-- @style no binds
-- @tags batch
-- @note End-of-run orphan cleanup: DELETE video_chunks NOT IN (SELECT DISTINCT video_chunk_id FROM frames), a full frames scan into a temp b-tree (the code calls it the expensive operation that should run once after all batches). Deletes nothing here for the same reason as video_files_in_slice: the subquery's NULL video_chunk_ids.
DELETE FROM video_chunks WHERE id NOT IN (SELECT DISTINCT video_chunk_id FROM frames);

-- @id screenpipe.audio.find_chunk_by_path
-- @src crates/screenpipe-db/src/db.rs:1056
-- @style sqlx ?N numbered binds
-- @tags hotpath,cpu-evidence
-- @note Runs after every audio chunk write (2.5-5.5k times a day). audio_chunks has no file_path index, so it is a full scan: 2-9 s per call on 608k chunks (https://github.com/screenpipe/screenpipe/issues/7704, reported on a later version; the statement and audio_chunks' indexes are the same at this commit).
-- @param ?1 '/Users/demo/.screenpipe/data/MacBook Pro Microphone (input)_2026-10-27_17-57-18.mp4'
SELECT id FROM audio_chunks WHERE file_path = ?1;

-- @id screenpipe.frames.latest_video_chunk
-- @src crates/screenpipe-db/src/db.rs:3218
-- @style sqlx ?N numbered binds
-- @tags hot-small,hotpath
-- @note Before every frame insert: newest video chunk of the device via idx_video_chunks_device_name_id.
-- @param ?1 'monitor_1'
SELECT id, file_path FROM video_chunks WHERE device_name = ?1 ORDER BY id DESC LIMIT 1;

-- @id screenpipe.frames.insert_with_ocr
-- @src crates/screenpipe-db/src/db.rs:3276
-- @style sqlx ?N numbered binds
-- @tags hot-small,hotpath
-- @note Capture write: one frame with its OCR text in full_text; frames_ai inserts the text into frames_fts in the same statement.
-- @param ?1 1499
-- @param ?2 120
-- @param ?3 '2026-10-27T19:00:01.250000+00:00'
-- @param ?4 '/Users/demo/.screenpipe/data/monitor_1_2026-10-27_18-58-00.mp4'
-- @param ?5 'https://github.com/acme/web-app/pull/812'
-- @param ?6 'Google Chrome'
-- @param ?7 'Fix search latency regression - GitHub'
-- @param ?8 1
-- @param ?9 'monitor_1'
-- @param ?10 'Fix search latency regression merge pull request review the index planner statistics'
INSERT INTO frames (video_chunk_id, offset_index, timestamp, name, browser_url, app_name, window_name, focused, device_name, full_text) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10);

-- @id screenpipe.frames.latest_timestamp
-- @src crates/screenpipe-db/src/db.rs:5060
-- @style no binds
-- @tags hot-small,hotpath
-- @note Health endpoint: newest frame timestamp, a reverse walk of idx_frames_timestamp.
SELECT timestamp FROM frames WHERE timestamp IS NOT NULL AND timestamp != '' ORDER BY timestamp DESC LIMIT 1;
