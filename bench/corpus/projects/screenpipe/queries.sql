-- screenpipe (screenpipe/screenpipe @ 2431cbf, Screenpipe Commercial License: source-available, quoted with attribution).
-- Rust + sqlx 0.9 against a plain SQLite database (the non-hybrid storage path). Statements are copied from the pinned
-- source: the activity-summary statements are extracted programmatically from their format! literals (continuations
-- resolved, timestamps and constants substituted: IDLE_CAP_SECS=300, MAX_TOP_TRANSCRIPTIONS=20); the rest are copied by
-- hand with the runtime-built pieces resolved for one instantiation. Unnumbered ? binds are renumbered ?N in order.
-- sqlx binds DateTime<Utc> as RFC 3339 text ('2026-10-20T00:00:00+00:00'); the activity summary inlines '...Z' strings.
-- Data covers 2026-08-29 .. 2026-10-27 (08:00-19:00 UTC each day).

-- @id screenpipe.activity.frame_summary.week
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:693-834
-- @style format! string with literal timestamps (sql_escape), sent through query_activity_summary_sql; no binds
-- @tags analytics,cpu-evidence,hotpath,dynamic
-- @note GET /activity-summary for 7 days: two MATERIALIZED CTEs resolve each frame's app (correlated ui_events fallbacks for frames that lost AX attribution), then 12 CTEs of GROUP BY, ROW_NUMBER and LEAD() gap windows over JULIANDAY, four-way UNION ALL. The "frame_fallback" statement logged at 11-14 s in https://github.com/screenpipe/screenpipe/issues/7352 and 1.3 s in https://github.com/screenpipe/screenpipe/issues/7059.
WITH frame_fallback AS MATERIALIZED (
  SELECT f.id, f.timestamp, f.app_name, f.window_name, f.browser_url, f.focused, f.document_path, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN COALESCE( (SELECT u.id FROM main.ui_events u WHERE u.frame_id = f.id AND u.app_name IS NOT NULL AND u.app_name != '' ORDER BY u.timestamp DESC, u.id DESC LIMIT 1), (SELECT u.id FROM main.ui_events u WHERE u.timestamp <= f.timestamp AND u.timestamp > datetime(f.timestamp, '-300 seconds') AND u.app_name IS NOT NULL AND u.app_name != '' ORDER BY u.timestamp DESC, u.id DESC LIMIT 1) ) ELSE NULL END AS fallback_event_id FROM frames f WHERE f.timestamp BETWEEN '2026-10-13T00:00:00Z' AND '2026-10-20T00:00:00Z'
), resolved_frames AS MATERIALIZED (
  SELECT f.id, f.timestamp, COALESCE(NULLIF(f.app_name, ''), (SELECT NULLIF(u.app_name, '') FROM ui_events u WHERE u.id = f.fallback_event_id)) AS app_name, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN (SELECT NULLIF(u.window_title, '') FROM ui_events u WHERE u.id = f.fallback_event_id) ELSE NULLIF(f.window_name, '') END AS window_name, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN (SELECT NULLIF(u.browser_url, '') FROM ui_events u WHERE u.id = f.fallback_event_id) ELSE NULLIF(f.browser_url, '') END AS browser_url, f.focused, f.document_path, CASE WHEN f.app_name IS NOT NULL AND f.app_name != '' THEN 'frame' WHEN f.fallback_event_id IS NOT NULL THEN 'ui_event' ELSE NULL END AS attribution_source FROM frame_fallback f
), app_raw AS (
  SELECT app_name, COUNT(*) AS frame_count, MIN(timestamp) AS first_seen, MAX(timestamp) AS last_seen FROM resolved_frames WHERE 1 = 1 AND app_name IS NOT NULL AND app_name != '' GROUP BY app_name
), app_selected AS (
  SELECT id, app_name, timestamp AS ts FROM ( SELECT id, app_name, timestamp, focused, ROW_NUMBER() OVER ( PARTITION BY timestamp ORDER BY focused DESC, id DESC ) AS rn FROM resolved_frames WHERE 1 = 1 AND app_name IS NOT NULL AND app_name != '' ) ranked WHERE rn = 1
), app_allocated AS (
  SELECT app_name, CASE WHEN gap_sec > 0 AND gap_sec < 300 THEN gap_sec ELSE 0 END AS active_sec FROM ( SELECT app_name, ts, (JULIANDAY(LEAD(ts) OVER (ORDER BY ts, id)) - JULIANDAY(ts)) * 86400 AS gap_sec FROM app_selected ) gaps
), app_totals AS (
  SELECT app_raw.app_name, app_raw.frame_count, COALESCE(ROUND(SUM(app_allocated.active_sec) / 60.0, 1), 0.0) AS minutes, app_raw.first_seen, app_raw.last_seen FROM app_raw LEFT JOIN app_allocated ON app_allocated.app_name = app_raw.app_name GROUP BY app_raw.app_name
), app_ranked AS (
  SELECT app_name, frame_count, minutes, first_seen, last_seen, ROW_NUMBER() OVER ( ORDER BY minutes DESC, frame_count DESC, app_name ASC ) AS row_order FROM app_totals
), window_raw AS (
  SELECT app_name, COALESCE(window_name, '') AS window_name, COALESCE(MAX(browser_url), '') AS browser_url, COUNT(*) AS frame_count FROM resolved_frames WHERE 1 = 1 AND app_name IS NOT NULL AND app_name != '' AND window_name IS NOT NULL AND window_name != '' GROUP BY app_name, window_name
), window_selected AS (
  SELECT id, app_name, COALESCE(window_name, '') AS window_name, timestamp AS ts FROM ( SELECT id, app_name, window_name, timestamp, focused, ROW_NUMBER() OVER ( PARTITION BY timestamp ORDER BY focused DESC, id DESC ) AS rn FROM resolved_frames WHERE 1 = 1 AND app_name IS NOT NULL AND app_name != '' AND window_name IS NOT NULL AND window_name != '' ) ranked WHERE rn = 1
), window_allocated AS (
  SELECT app_name, window_name, CASE WHEN gap_sec > 0 AND gap_sec < 300 THEN gap_sec ELSE 0 END AS active_sec FROM ( SELECT app_name, window_name, ts, (JULIANDAY(LEAD(ts) OVER (ORDER BY ts, id)) - JULIANDAY(ts)) * 86400 AS gap_sec FROM window_selected ) gaps
), window_totals AS (
  SELECT window_raw.app_name, window_raw.window_name, window_raw.browser_url, window_raw.frame_count, COALESCE(ROUND(SUM(window_allocated.active_sec) / 60.0, 1), 0.0) AS minutes FROM window_raw LEFT JOIN window_allocated ON window_allocated.app_name = window_raw.app_name AND window_allocated.window_name = window_raw.window_name GROUP BY window_raw.app_name, window_raw.window_name
), window_ranked AS (
  SELECT app_name, window_name, browser_url, frame_count, minutes, ROW_NUMBER() OVER ( ORDER BY minutes DESC, frame_count DESC, app_name ASC, window_name ASC ) AS row_order FROM window_totals
), active_gaps AS (
  SELECT ( JULIANDAY(LEAD(timestamp) OVER (ORDER BY timestamp, id)) - JULIANDAY(timestamp) ) * 86400.0 AS gap_sec FROM resolved_frames WHERE 1 = 1
), active_total AS (
  SELECT COALESCE(ROUND(SUM( CASE WHEN gap_sec > 0 AND gap_sec < 300 THEN gap_sec ELSE 0 END ) / 60.0, 1), 0.0) AS total_active_minutes FROM active_gaps
), attribution_totals AS (
  SELECT COUNT(*) AS total_frames, COALESCE(SUM(attribution_source = 'frame'), 0) AS native_frames, COALESCE(SUM(attribution_source = 'ui_event'), 0) AS recovered_frames, COALESCE(SUM(attribution_source IS NULL), 0) AS unresolved_frames FROM resolved_frames WHERE 1 = 1
)
SELECT 1 AS section_order, 'app' AS row_kind, row_order, app_name, '' AS window_name, '' AS browser_url, frame_count, minutes, first_seen, last_seen, NULL AS total_frames, NULL AS native_frames, NULL AS recovered_frames, NULL AS unresolved_frames FROM app_ranked WHERE row_order <= 20
UNION ALL
SELECT 2, 'window', row_order, app_name, window_name, browser_url, frame_count, minutes, '', '', NULL, NULL, NULL, NULL FROM window_ranked WHERE row_order <= 30
UNION ALL
SELECT 3, 'active', 1, '', '', '', NULL, total_active_minutes, '', '', NULL, NULL, NULL, NULL FROM active_total
UNION ALL
SELECT 4, 'attribution', 1, '', '', '', NULL, NULL, '', '', total_frames, native_frames, recovered_frames, unresolved_frames FROM attribution_totals ORDER BY section_order, row_order;

-- @id screenpipe.activity.frame_summary.full_history
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:693-834
-- @style format! string with literal timestamps (sql_escape), sent through query_activity_summary_sql; no binds
-- @tags analytics,cpu-evidence,dynamic
-- @note Same statement with start = first frame of the install, end = now: the home activity ledger requested this every ~4 s and each run took 20-63 s on a 148k-frame database (https://github.com/screenpipe/screenpipe/issues/7364).
WITH frame_fallback AS MATERIALIZED (
  SELECT f.id, f.timestamp, f.app_name, f.window_name, f.browser_url, f.focused, f.document_path, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN COALESCE( (SELECT u.id FROM main.ui_events u WHERE u.frame_id = f.id AND u.app_name IS NOT NULL AND u.app_name != '' ORDER BY u.timestamp DESC, u.id DESC LIMIT 1), (SELECT u.id FROM main.ui_events u WHERE u.timestamp <= f.timestamp AND u.timestamp > datetime(f.timestamp, '-300 seconds') AND u.app_name IS NOT NULL AND u.app_name != '' ORDER BY u.timestamp DESC, u.id DESC LIMIT 1) ) ELSE NULL END AS fallback_event_id FROM frames f WHERE f.timestamp BETWEEN '2026-08-29T08:00:00Z' AND '2026-10-28T09:00:00Z'
), resolved_frames AS MATERIALIZED (
  SELECT f.id, f.timestamp, COALESCE(NULLIF(f.app_name, ''), (SELECT NULLIF(u.app_name, '') FROM ui_events u WHERE u.id = f.fallback_event_id)) AS app_name, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN (SELECT NULLIF(u.window_title, '') FROM ui_events u WHERE u.id = f.fallback_event_id) ELSE NULLIF(f.window_name, '') END AS window_name, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN (SELECT NULLIF(u.browser_url, '') FROM ui_events u WHERE u.id = f.fallback_event_id) ELSE NULLIF(f.browser_url, '') END AS browser_url, f.focused, f.document_path, CASE WHEN f.app_name IS NOT NULL AND f.app_name != '' THEN 'frame' WHEN f.fallback_event_id IS NOT NULL THEN 'ui_event' ELSE NULL END AS attribution_source FROM frame_fallback f
), app_raw AS (
  SELECT app_name, COUNT(*) AS frame_count, MIN(timestamp) AS first_seen, MAX(timestamp) AS last_seen FROM resolved_frames WHERE 1 = 1 AND app_name IS NOT NULL AND app_name != '' GROUP BY app_name
), app_selected AS (
  SELECT id, app_name, timestamp AS ts FROM ( SELECT id, app_name, timestamp, focused, ROW_NUMBER() OVER ( PARTITION BY timestamp ORDER BY focused DESC, id DESC ) AS rn FROM resolved_frames WHERE 1 = 1 AND app_name IS NOT NULL AND app_name != '' ) ranked WHERE rn = 1
), app_allocated AS (
  SELECT app_name, CASE WHEN gap_sec > 0 AND gap_sec < 300 THEN gap_sec ELSE 0 END AS active_sec FROM ( SELECT app_name, ts, (JULIANDAY(LEAD(ts) OVER (ORDER BY ts, id)) - JULIANDAY(ts)) * 86400 AS gap_sec FROM app_selected ) gaps
), app_totals AS (
  SELECT app_raw.app_name, app_raw.frame_count, COALESCE(ROUND(SUM(app_allocated.active_sec) / 60.0, 1), 0.0) AS minutes, app_raw.first_seen, app_raw.last_seen FROM app_raw LEFT JOIN app_allocated ON app_allocated.app_name = app_raw.app_name GROUP BY app_raw.app_name
), app_ranked AS (
  SELECT app_name, frame_count, minutes, first_seen, last_seen, ROW_NUMBER() OVER ( ORDER BY minutes DESC, frame_count DESC, app_name ASC ) AS row_order FROM app_totals
), window_raw AS (
  SELECT app_name, COALESCE(window_name, '') AS window_name, COALESCE(MAX(browser_url), '') AS browser_url, COUNT(*) AS frame_count FROM resolved_frames WHERE 1 = 1 AND app_name IS NOT NULL AND app_name != '' AND window_name IS NOT NULL AND window_name != '' GROUP BY app_name, window_name
), window_selected AS (
  SELECT id, app_name, COALESCE(window_name, '') AS window_name, timestamp AS ts FROM ( SELECT id, app_name, window_name, timestamp, focused, ROW_NUMBER() OVER ( PARTITION BY timestamp ORDER BY focused DESC, id DESC ) AS rn FROM resolved_frames WHERE 1 = 1 AND app_name IS NOT NULL AND app_name != '' AND window_name IS NOT NULL AND window_name != '' ) ranked WHERE rn = 1
), window_allocated AS (
  SELECT app_name, window_name, CASE WHEN gap_sec > 0 AND gap_sec < 300 THEN gap_sec ELSE 0 END AS active_sec FROM ( SELECT app_name, window_name, ts, (JULIANDAY(LEAD(ts) OVER (ORDER BY ts, id)) - JULIANDAY(ts)) * 86400 AS gap_sec FROM window_selected ) gaps
), window_totals AS (
  SELECT window_raw.app_name, window_raw.window_name, window_raw.browser_url, window_raw.frame_count, COALESCE(ROUND(SUM(window_allocated.active_sec) / 60.0, 1), 0.0) AS minutes FROM window_raw LEFT JOIN window_allocated ON window_allocated.app_name = window_raw.app_name AND window_allocated.window_name = window_raw.window_name GROUP BY window_raw.app_name, window_raw.window_name
), window_ranked AS (
  SELECT app_name, window_name, browser_url, frame_count, minutes, ROW_NUMBER() OVER ( ORDER BY minutes DESC, frame_count DESC, app_name ASC, window_name ASC ) AS row_order FROM window_totals
), active_gaps AS (
  SELECT ( JULIANDAY(LEAD(timestamp) OVER (ORDER BY timestamp, id)) - JULIANDAY(timestamp) ) * 86400.0 AS gap_sec FROM resolved_frames WHERE 1 = 1
), active_total AS (
  SELECT COALESCE(ROUND(SUM( CASE WHEN gap_sec > 0 AND gap_sec < 300 THEN gap_sec ELSE 0 END ) / 60.0, 1), 0.0) AS total_active_minutes FROM active_gaps
), attribution_totals AS (
  SELECT COUNT(*) AS total_frames, COALESCE(SUM(attribution_source = 'frame'), 0) AS native_frames, COALESCE(SUM(attribution_source = 'ui_event'), 0) AS recovered_frames, COALESCE(SUM(attribution_source IS NULL), 0) AS unresolved_frames FROM resolved_frames WHERE 1 = 1
)
SELECT 1 AS section_order, 'app' AS row_kind, row_order, app_name, '' AS window_name, '' AS browser_url, frame_count, minutes, first_seen, last_seen, NULL AS total_frames, NULL AS native_frames, NULL AS recovered_frames, NULL AS unresolved_frames FROM app_ranked WHERE row_order <= 20
UNION ALL
SELECT 2, 'window', row_order, app_name, window_name, browser_url, frame_count, minutes, '', '', NULL, NULL, NULL, NULL FROM window_ranked WHERE row_order <= 30
UNION ALL
SELECT 3, 'active', 1, '', '', '', NULL, total_active_minutes, '', '', NULL, NULL, NULL, NULL FROM active_total
UNION ALL
SELECT 4, 'attribution', 1, '', '', '', NULL, NULL, '', '', total_frames, native_frames, recovered_frames, unresolved_frames FROM attribution_totals ORDER BY section_order, row_order;

-- @id screenpipe.activity.key_texts.day
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:621-658
-- @style format! string with literal timestamps (sql_escape), sent through query_activity_summary_sql; no binds
-- @tags analytics,cpu-evidence,dynamic
-- @note Representative accessibility text per date/app/window: resolved-frames CTE CROSS JOIN elements (the fix from https://github.com/screenpipe/screenpipe/issues/7092, where the plain JOIN started from idx_elements_source and took 19-32 s for 24 h), ROW_NUMBER over LENGTH/role CASE, then a per-day rank and LIMIT 20.
WITH frame_fallback AS MATERIALIZED (
  SELECT f.id, f.timestamp, f.app_name, f.window_name, f.browser_url, f.focused, f.document_path, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN COALESCE( (SELECT u.id FROM main.ui_events u WHERE u.frame_id = f.id AND u.app_name IS NOT NULL AND u.app_name != '' ORDER BY u.timestamp DESC, u.id DESC LIMIT 1), (SELECT u.id FROM main.ui_events u WHERE u.timestamp <= f.timestamp AND u.timestamp > datetime(f.timestamp, '-300 seconds') AND u.app_name IS NOT NULL AND u.app_name != '' ORDER BY u.timestamp DESC, u.id DESC LIMIT 1) ) ELSE NULL END AS fallback_event_id FROM frames f WHERE f.timestamp BETWEEN '2026-10-20T00:00:00Z' AND '2026-10-21T00:00:00Z'
), resolved_frames AS MATERIALIZED (
  SELECT f.id, f.timestamp, COALESCE(NULLIF(f.app_name, ''), (SELECT NULLIF(u.app_name, '') FROM ui_events u WHERE u.id = f.fallback_event_id)) AS app_name, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN (SELECT NULLIF(u.window_title, '') FROM ui_events u WHERE u.id = f.fallback_event_id) ELSE NULLIF(f.window_name, '') END AS window_name, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN (SELECT NULLIF(u.browser_url, '') FROM ui_events u WHERE u.id = f.fallback_event_id) ELSE NULLIF(f.browser_url, '') END AS browser_url, f.focused, f.document_path, CASE WHEN f.app_name IS NOT NULL AND f.app_name != '' THEN 'frame' WHEN f.fallback_event_id IS NOT NULL THEN 'ui_event' ELSE NULL END AS attribution_source FROM frame_fallback f
), ranked_contexts AS (
  SELECT e.text, f.app_name, COALESCE(f.window_name, '') as window_name, f.timestamp, DATE(f.timestamp) AS bucket, ROW_NUMBER() OVER ( PARTITION BY DATE(f.timestamp), f.app_name, f.window_name ORDER BY CASE WHEN e.role IN ('AXTextArea', 'AXTextField') THEN 0 ELSE 1 END, LENGTH(e.text) DESC, f.timestamp DESC ) as rn FROM resolved_frames f CROSS JOIN elements e ON e.frame_id = f.id WHERE 1 = 1 AND e.text IS NOT NULL AND e.source = 'accessibility' AND LENGTH(e.text) BETWEEN 30 AND 300 AND e.text NOT LIKE 'http%' AND e.text NOT LIKE 'cdn.%'
), balanced AS (
  SELECT text, app_name, window_name, timestamp, bucket, ROW_NUMBER() OVER (PARTITION BY bucket ORDER BY timestamp DESC) AS bucket_rank FROM ranked_contexts WHERE rn = 1
)
SELECT text, app_name, window_name, timestamp FROM balanced ORDER BY bucket_rank ASC, timestamp ASC LIMIT 20;

-- @id screenpipe.activity.key_texts.week_app
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:621-658
-- @style format! string with literal timestamps (sql_escape), sent through query_activity_summary_sql; no binds
-- @tags analytics,cpu-evidence,dynamic
-- @note Key texts for one week filtered to one app (app_filter_f adds f.app_name = ...), as pipes and the agent call it (https://github.com/screenpipe/screenpipe/issues/7092).
WITH frame_fallback AS MATERIALIZED (
  SELECT f.id, f.timestamp, f.app_name, f.window_name, f.browser_url, f.focused, f.document_path, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN COALESCE( (SELECT u.id FROM main.ui_events u WHERE u.frame_id = f.id AND u.app_name IS NOT NULL AND u.app_name != '' ORDER BY u.timestamp DESC, u.id DESC LIMIT 1), (SELECT u.id FROM main.ui_events u WHERE u.timestamp <= f.timestamp AND u.timestamp > datetime(f.timestamp, '-300 seconds') AND u.app_name IS NOT NULL AND u.app_name != '' ORDER BY u.timestamp DESC, u.id DESC LIMIT 1) ) ELSE NULL END AS fallback_event_id FROM frames f WHERE f.timestamp BETWEEN '2026-10-13T00:00:00Z' AND '2026-10-20T00:00:00Z'
), resolved_frames AS MATERIALIZED (
  SELECT f.id, f.timestamp, COALESCE(NULLIF(f.app_name, ''), (SELECT NULLIF(u.app_name, '') FROM ui_events u WHERE u.id = f.fallback_event_id)) AS app_name, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN (SELECT NULLIF(u.window_title, '') FROM ui_events u WHERE u.id = f.fallback_event_id) ELSE NULLIF(f.window_name, '') END AS window_name, CASE WHEN f.app_name IS NULL OR f.app_name = '' THEN (SELECT NULLIF(u.browser_url, '') FROM ui_events u WHERE u.id = f.fallback_event_id) ELSE NULLIF(f.browser_url, '') END AS browser_url, f.focused, f.document_path, CASE WHEN f.app_name IS NOT NULL AND f.app_name != '' THEN 'frame' WHEN f.fallback_event_id IS NOT NULL THEN 'ui_event' ELSE NULL END AS attribution_source FROM frame_fallback f
), ranked_contexts AS (
  SELECT e.text, f.app_name, COALESCE(f.window_name, '') as window_name, f.timestamp, DATE(f.timestamp) AS bucket, ROW_NUMBER() OVER ( PARTITION BY DATE(f.timestamp), f.app_name, f.window_name ORDER BY CASE WHEN e.role IN ('AXTextArea', 'AXTextField') THEN 0 ELSE 1 END, LENGTH(e.text) DESC, f.timestamp DESC ) as rn FROM resolved_frames f CROSS JOIN elements e ON e.frame_id = f.id WHERE 1 = 1 AND f.app_name = 'Slack' AND e.text IS NOT NULL AND e.source = 'accessibility' AND LENGTH(e.text) BETWEEN 30 AND 300 AND e.text NOT LIKE 'http%' AND e.text NOT LIKE 'cdn.%'
), balanced AS (
  SELECT text, app_name, window_name, timestamp, bucket, ROW_NUMBER() OVER (PARTITION BY bucket ORDER BY timestamp DESC) AS bucket_rank FROM ranked_contexts WHERE rn = 1
)
SELECT text, app_name, window_name, timestamp FROM balanced ORDER BY bucket_rank ASC, timestamp ASC LIMIT 20;

-- @id screenpipe.activity.balanced_audio.week
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:1327-1362
-- @style format! string with literal timestamps (sql_escape), sent through query_activity_summary_sql; no binds
-- @tags analytics,dynamic
-- @note Notable quotes: buckets the week into 20 JULIANDAY slices, ROW_NUMBER per bucket by LENGTH(transcription), round-robin LIMIT 20, re-sorted chronologically.
WITH bucketed AS (
  SELECT at.transcription, COALESCE(s.name, 'Unknown') AS speaker, at.device, at.timestamp, MIN(19, CAST( ((JULIANDAY(at.timestamp) - JULIANDAY('2026-10-13T00:00:00Z')) / NULLIF(JULIANDAY('2026-10-20T00:00:00Z') - JULIANDAY('2026-10-13T00:00:00Z'), 0)) * 20 AS INTEGER )) AS time_bucket FROM audio_transcriptions at LEFT JOIN speakers s ON at.speaker_id = s.id WHERE at.timestamp BETWEEN '2026-10-13T00:00:00Z' AND '2026-10-20T00:00:00Z' AND TRIM(at.transcription) != '' AND LENGTH(at.transcription) > 5
), ranked AS (
  SELECT transcription, speaker, device, timestamp, time_bucket, ROW_NUMBER() OVER ( PARTITION BY time_bucket ORDER BY LENGTH(transcription) DESC, timestamp DESC ) AS bucket_rank FROM bucketed
), selected AS (
  SELECT transcription, speaker, device, timestamp FROM ranked ORDER BY bucket_rank ASC, time_bucket ASC, timestamp ASC LIMIT 20
)
SELECT transcription, speaker, device, timestamp FROM selected ORDER BY timestamp ASC;

-- @id screenpipe.activity.edited_files.week
-- @src crates/screenpipe-engine/src/routes/activity_summary.rs:850-858
-- @style format! string with literal timestamps (sql_escape), sent through query_activity_summary_sql; no binds
-- @tags analytics,dynamic
-- @note Edited files: GROUP BY document_path over a week of frames, ORDER BY count, LIMIT 50.
SELECT document_path AS path, COUNT(*) AS frame_count FROM frames WHERE timestamp BETWEEN '2026-10-13T00:00:00Z' AND '2026-10-20T00:00:00Z' AND document_path IS NOT NULL AND document_path != '' GROUP BY document_path ORDER BY frame_count DESC, document_path ASC LIMIT 50;

-- @id screenpipe.search.ocr.fts_app_week
-- @src crates/screenpipe-db/src/db/search.rs:839-911
-- @style sqlx ?N numbered binds (13 always bound, unused ones NULL); FTS join, time bounds and the length expression are format!-ed in
-- @tags hotpath,dynamic,cpu-evidence
-- @note /search content_type=ocr q=deploy app_name=Slack for 7 days: app and text merged into one frames_fts MATCH (column filter app_name:"Slack" plus "deploy"), candidates CTE ordered by timestamp with LIMIT, then tag joins + GROUP_CONCAT. Search slowness on large DBs: https://github.com/screenpipe/screenpipe/issues/4474.
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
WITH candidates AS MATERIALIZED (
  SELECT frames.id, frames.timestamp
  FROM frames
  LEFT JOIN video_chunks ON frames.video_chunk_id = video_chunks.id
  JOIN frames_fts ON frames.id = frames_fts.rowid
  WHERE 1=1
    AND frames_fts MATCH ?1
    AND frames.timestamp >= ?2
    AND frames.timestamp <= ?3
    AND (?4 IS NULL OR LENGTH(COALESCE(frames.full_text, '')) >= ?4)
    AND (?5 IS NULL OR LENGTH(COALESCE(frames.full_text, '')) <= ?5)
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
  ORDER BY frames.timestamp DESC, frames.id DESC
  LIMIT ?10 OFFSET ?11
)
SELECT
  frames.id as frame_id,
  COALESCE(frames.full_text, frames.accessibility_text, '') as ocr_text,
  '' as text_json,
  frames.timestamp,
  frames.name as frame_name,
  COALESCE(frames.snapshot_path, video_chunks.file_path) as file_path,
  frames.offset_index,
  frames.app_name,
  '' as ocr_engine,
  frames.window_name,
  COALESCE(video_chunks.device_name, frames.device_name) as device_name,
  GROUP_CONCAT(tags.name, ',') as tags,
  frames.browser_url,
  frames.focused,
  frames.text_source,
  frames.capture_trigger
FROM candidates
JOIN frames ON frames.id = candidates.id
LEFT JOIN video_chunks ON frames.video_chunk_id = video_chunks.id
LEFT JOIN vision_tags ON frames.id = vision_tags.vision_id
LEFT JOIN tags ON vision_tags.tag_id = tags.id
GROUP BY frames.id
ORDER BY candidates.timestamp DESC, candidates.id DESC;

-- @id screenpipe.search.ocr.fts_all_history
-- @src crates/screenpipe-db/src/db/search.rs:839-911
-- @style sqlx ?N numbered binds (13 always bound, unused ones NULL); FTS join, time bounds and the length expression are format!-ed in
-- @tags hotpath,dynamic,cpu-evidence
-- @note /search q=invoice with no time bounds: every frames_fts match (~9 % of all frames) is joined back to frames and sorted by timestamp before LIMIT 20; the unbounded case behind the search pool-wedge (https://github.com/screenpipe/screenpipe/issues/4474).
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
WITH candidates AS MATERIALIZED (
  SELECT frames.id, frames.timestamp
  FROM frames
  LEFT JOIN video_chunks ON frames.video_chunk_id = video_chunks.id
  JOIN frames_fts ON frames.id = frames_fts.rowid
  WHERE 1=1
    AND frames_fts MATCH ?1
    
    
    AND (?4 IS NULL OR LENGTH(COALESCE(frames.full_text, '')) >= ?4)
    AND (?5 IS NULL OR LENGTH(COALESCE(frames.full_text, '')) <= ?5)
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
  ORDER BY frames.timestamp DESC, frames.id DESC
  LIMIT ?10 OFFSET ?11
)
SELECT
  frames.id as frame_id,
  COALESCE(frames.full_text, frames.accessibility_text, '') as ocr_text,
  '' as text_json,
  frames.timestamp,
  frames.name as frame_name,
  COALESCE(frames.snapshot_path, video_chunks.file_path) as file_path,
  frames.offset_index,
  frames.app_name,
  '' as ocr_engine,
  frames.window_name,
  COALESCE(video_chunks.device_name, frames.device_name) as device_name,
  GROUP_CONCAT(tags.name, ',') as tags,
  frames.browser_url,
  frames.focused,
  frames.text_source,
  frames.capture_trigger
FROM candidates
JOIN frames ON frames.id = candidates.id
LEFT JOIN video_chunks ON frames.video_chunk_id = video_chunks.id
LEFT JOIN vision_tags ON frames.id = vision_tags.vision_id
LEFT JOIN tags ON vision_tags.tag_id = tags.id
GROUP BY frames.id
ORDER BY candidates.timestamp DESC, candidates.id DESC;

-- @id screenpipe.search.ocr.focused_tags_month
-- @src crates/screenpipe-db/src/db/search.rs:839-911
-- @style sqlx ?N numbered binds (13 always bound, unused ones NULL); FTS join, time bounds and the length expression are format!-ed in
-- @tags dynamic
-- @note Filter-only search (no text): focused frames tagged "work" over 30 days; the tag filter is a GROUP BY/HAVING COUNT(DISTINCT) IN-subquery over vision_tags evaluated against a time-range scan.
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
WITH candidates AS MATERIALIZED (
  SELECT frames.id, frames.timestamp
  FROM frames
  LEFT JOIN video_chunks ON frames.video_chunk_id = video_chunks.id
  
  WHERE 1=1
    
    AND frames.timestamp >= ?2
    AND frames.timestamp <= ?3
    AND (?4 IS NULL OR LENGTH(COALESCE(frames.full_text, '')) >= ?4)
    AND (?5 IS NULL OR LENGTH(COALESCE(frames.full_text, '')) <= ?5)
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
  ORDER BY frames.timestamp DESC, frames.id DESC
  LIMIT ?10 OFFSET ?11
)
SELECT
  frames.id as frame_id,
  COALESCE(frames.full_text, frames.accessibility_text, '') as ocr_text,
  '' as text_json,
  frames.timestamp,
  frames.name as frame_name,
  COALESCE(frames.snapshot_path, video_chunks.file_path) as file_path,
  frames.offset_index,
  frames.app_name,
  '' as ocr_engine,
  frames.window_name,
  COALESCE(video_chunks.device_name, frames.device_name) as device_name,
  GROUP_CONCAT(tags.name, ',') as tags,
  frames.browser_url,
  frames.focused,
  frames.text_source,
  frames.capture_trigger
FROM candidates
JOIN frames ON frames.id = candidates.id
LEFT JOIN video_chunks ON frames.video_chunk_id = video_chunks.id
LEFT JOIN vision_tags ON frames.id = vision_tags.vision_id
LEFT JOIN tags ON vision_tags.tag_id = tags.id
GROUP BY frames.id
ORDER BY candidates.timestamp DESC, candidates.id DESC;

-- @id screenpipe.search.ocr.browse_page
-- @src crates/screenpipe-db/src/db/search.rs:641-676
-- @style sqlx positional ? binds (renumbered ?N); time conditions appended only when set
-- @tags hotpath,dynamic
-- @note Unfiltered browse (empty q): page 3 of the last day, newest first. The candidates CTE is bounded by idx_frames_timestamp; OFFSET 100 still walks the skipped rows.
-- @param ?1 '2026-10-26T00:00:00+00:00'
-- @param ?2 '2026-10-27T00:00:00+00:00'
-- @param ?3 50
-- @param ?4 100
WITH candidates AS MATERIALIZED (
  SELECT id, timestamp
  FROM frames
  WHERE 1=1
    AND timestamp >= ?1
    AND timestamp <= ?2
  ORDER BY timestamp DESC, id DESC
  LIMIT ?3 OFFSET ?4
)
SELECT
  frames.id as frame_id,
  COALESCE(frames.full_text, frames.accessibility_text, '') as ocr_text,
  '' as text_json,
  frames.timestamp,
  frames.name as frame_name,
  COALESCE(frames.snapshot_path, video_chunks.file_path) as file_path,
  frames.offset_index,
  frames.app_name,
  '' as ocr_engine,
  frames.window_name,
  COALESCE(video_chunks.device_name, frames.device_name) as device_name,
  GROUP_CONCAT(tags.name, ',') as tags,
  frames.browser_url,
  frames.focused,
  frames.text_source,
  frames.capture_trigger
FROM candidates
JOIN frames ON frames.id = candidates.id
LEFT JOIN video_chunks ON frames.video_chunk_id = video_chunks.id
LEFT JOIN vision_tags ON frames.id = vision_tags.vision_id
LEFT JOIN tags ON vision_tags.tag_id = tags.id
GROUP BY frames.id
ORDER BY frames.timestamp DESC, frames.id DESC;

-- @id screenpipe.search.count.ocr_fts_month
-- @src crates/screenpipe-db/src/db/search.rs:2164-2200
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
-- @src crates/screenpipe-db/src/db/search.rs:1055-1215
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
  CASE
  WHEN speakers.id IS NULL THEN NULL
  ELSE COALESCE(speakers.name, '')
  END AS speaker_name,
  CASE
  WHEN speakers.id IS NULL THEN NULL
  ELSE COALESCE(speakers.metadata, '')
  END AS speaker_metadata,
  audio_transcriptions.start_time,
  audio_transcriptions.end_time,
  (
  SELECT dr.mode
  FROM diarization_segments ds
  JOIN diarization_runs dr ON dr.id = ds.diarization_run_id
  WHERE ds.audio_chunk_id = audio_transcriptions.audio_chunk_id
  AND audio_transcriptions.start_time IS NOT NULL
  AND audio_transcriptions.end_time IS NOT NULL
  AND ABS(ds.start_time - audio_transcriptions.start_time) < 0.05
  AND ABS(ds.end_time - audio_transcriptions.end_time) < 0.05
  ORDER BY dr.created_at DESC, ds.id DESC
  LIMIT 1
  ) AS diarization_mode,
  (
  SELECT ds.provider_speaker_label
  FROM diarization_segments ds
  JOIN diarization_runs dr ON dr.id = ds.diarization_run_id
  WHERE ds.audio_chunk_id = audio_transcriptions.audio_chunk_id
  AND audio_transcriptions.start_time IS NOT NULL
  AND audio_transcriptions.end_time IS NOT NULL
  AND ABS(ds.start_time - audio_transcriptions.start_time) < 0.05
  AND ABS(ds.end_time - audio_transcriptions.end_time) < 0.05
  ORDER BY dr.created_at DESC, ds.id DESC
  LIMIT 1
  ) AS diarization_speaker_label,
  (
  SELECT dr.provider
  FROM diarization_segments ds
  JOIN diarization_runs dr ON dr.id = ds.diarization_run_id
  WHERE ds.audio_chunk_id = audio_transcriptions.audio_chunk_id
  AND audio_transcriptions.start_time IS NOT NULL
  AND audio_transcriptions.end_time IS NOT NULL
  AND ABS(ds.start_time - audio_transcriptions.start_time) < 0.05
  AND ABS(ds.end_time - audio_transcriptions.end_time) < 0.05
  ORDER BY dr.created_at DESC, ds.id DESC
  LIMIT 1
  ) AS diarization_provider,
  (
  SELECT ds.source
  FROM diarization_segments ds
  JOIN diarization_runs dr ON dr.id = ds.diarization_run_id
  WHERE ds.audio_chunk_id = audio_transcriptions.audio_chunk_id
  AND audio_transcriptions.start_time IS NOT NULL
  AND audio_transcriptions.end_time IS NOT NULL
  AND ABS(ds.start_time - audio_transcriptions.start_time) < 0.05
  AND ABS(ds.end_time - audio_transcriptions.end_time) < 0.05
  ORDER BY dr.created_at DESC, ds.id DESC
  LIMIT 1
  ) AS diarization_source,
  (
  SELECT ds.confidence
  FROM diarization_segments ds
  JOIN diarization_runs dr ON dr.id = ds.diarization_run_id
  WHERE ds.audio_chunk_id = audio_transcriptions.audio_chunk_id
  AND audio_transcriptions.start_time IS NOT NULL
  AND audio_transcriptions.end_time IS NOT NULL
  AND ABS(ds.start_time - audio_transcriptions.start_time) < 0.05
  AND ABS(ds.end_time - audio_transcriptions.end_time) < 0.05
  ORDER BY dr.created_at DESC, ds.id DESC
  LIMIT 1
  ) AS diarization_confidence
  FROM audio_transcriptions
  JOIN audio_chunks ON audio_transcriptions.audio_chunk_id = audio_chunks.id
  LEFT JOIN speakers ON audio_transcriptions.speaker_id = speakers.id
  LEFT JOIN audio_tags ON audio_chunks.id = audio_tags.audio_chunk_id
  LEFT JOIN tags ON audio_tags.tag_id = tags.id WHERE audio_transcriptions.audio_chunk_id IN (SELECT at_inner.audio_chunk_id FROM audio_transcriptions_fts JOIN audio_transcriptions at_inner ON at_inner.id = audio_transcriptions_fts.rowid WHERE audio_transcriptions_fts MATCH ?1 ORDER BY audio_transcriptions_fts.rank LIMIT 5000) AND audio_transcriptions.timestamp >= ?2 AND audio_transcriptions.timestamp <= ?3 AND (speakers.id IS NULL OR speakers.hallucination = 0) AND audio_chunks.file_path NOT LIKE 'cloud://%' GROUP BY audio_transcriptions.id ORDER BY audio_transcriptions.timestamp DESC, audio_transcriptions.audio_chunk_id DESC, audio_transcriptions.offset_index DESC, audio_transcriptions.id DESC LIMIT ?4 OFFSET ?5;

-- @id screenpipe.search.count.input_like
-- @src crates/screenpipe-db/src/db/search.rs:2296-2313
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
-- @src crates/screenpipe-db/src/db/elements.rs:441-468
-- @style sqlx positional ? binds (renumbered ?N); IN list expanded per app
-- @tags hotpath,dynamic,cpu-evidence
-- @note Search-results grid ("grouped matches"): frames in 30 days for two apps whose id is in the top-5000 bm25 frames_fts matches, newest first, LIMIT 5000 rows streamed to Rust for episode grouping (https://github.com/screenpipe/screenpipe/issues/4474).
-- @param ?1 '2026-09-20T00:00:00+00:00'
-- @param ?2 '2026-10-20T00:00:00+00:00'
-- @param ?3 'Google Chrome'
-- @param ?4 'Slack'
-- @param ?5 '"invoice"'
-- @param ?6 5000
SELECT
  f.id,
  f.timestamp,
  COALESCE(f.device_name, '') as device_name,
  f.browser_url as url,
  COALESCE(f.app_name, '') as app_name,
  COALESCE(f.window_name, '') as window_name
FROM frames f
WHERE f.timestamp >= ?1 AND f.timestamp <= ?2 AND f.app_name IN (?3,?4) AND f.id IN (SELECT rowid FROM frames_fts WHERE frames_fts MATCH ?5 ORDER BY rank LIMIT 5000)
ORDER BY f.timestamp DESC
LIMIT ?6;

-- @id screenpipe.elements.search_fts
-- @src crates/screenpipe-db/src/db/elements.rs:276-283
-- @style sqlx positional ? binds in condition order (renumbered ?N); non-hybrid (plain SQLite) branch
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
       e.confidence, e.sort_order, e.on_screen, e.properties
FROM elements e JOIN frames f ON f.id=e.frame_id JOIN elements_fts fts ON fts.rowid = e.id WHERE fts.text MATCH ?1 AND e.source = ?2 AND f.timestamp >= ?3 AND f.timestamp <= ?4
ORDER BY e.frame_id DESC, e.sort_order ASC, e.id ASC
LIMIT ?5 OFFSET ?6;

-- @id screenpipe.timeline.frames_day
-- @src crates/screenpipe-db/src/db/frames.rs:1175-1199
-- @style sqlx ?N numbered binds; preview length format!-ed in (200)
-- @tags hotpath,dynamic,cpu-evidence
-- @note Timeline stream for one day: every frame in range with 200-char text previews, LEFT JOIN video_chunks, NOT LIKE cloud filter, ordered by timestamp/offset, LIMIT 10000 (the cap). Slow frame queries during meetings: https://github.com/screenpipe/screenpipe/issues/7352.
-- @param ?1 '2026-09-15T00:00:00+00:00'
-- @param ?2 '2026-09-16T00:00:00+00:00'
-- @param ?3 10000
SELECT
  f.id,
  f.timestamp,
  f.offset_index,
  COALESCE(
    SUBSTR(f.full_text, 1, 200),
    SUBSTR(f.accessibility_text, 1, 200)
  ) as text,
  f.app_name as app_name,
  f.window_name as window_name,
  COALESCE(vc.device_name, f.device_name) as screen_device,
  COALESCE(vc.file_path, f.snapshot_path) as video_path,
  COALESCE(vc.fps, 0.033) as chunk_fps,
  f.browser_url,
  f.machine_id
FROM frames f
LEFT JOIN video_chunks vc ON f.video_chunk_id = vc.id
WHERE f.timestamp >= ?1 AND f.timestamp <= ?2
  AND COALESCE(vc.file_path, f.snapshot_path, '') NOT LIKE 'cloud://%'
ORDER BY f.timestamp ASC, f.offset_index ASC
LIMIT ?3;

-- @id screenpipe.preview.candidates
-- @src crates/screenpipe-db/src/db/search.rs:1615-1682
-- @style sqlx ?N numbered binds
-- @tags analytics,hotpath
-- @note App-usage preview strip: focused frames of one app plus frames recovered through their latest ui_event (correlated ORDER BY ... LIMIT 1), UNION ALL, ROW_NUMBER per 10-second unixepoch bucket and browser domain, instr(lower()) domain filter.
-- @param ?1 'Google Chrome'
-- @param ?2 '2026-10-13T00:00:00+00:00'
-- @param ?3 '2026-10-16T00:00:00+00:00'
-- @param ?4 'github'
WITH candidates AS (
                SELECT
                    f.id,
                    f.timestamp,
                    f.browser_url,
                    COALESCE(NULLIF(f.snapshot_path, ''), vc.file_path) AS source_path,
                    CASE WHEN NULLIF(f.snapshot_path, '') IS NULL THEN vc.id END AS video_chunk_id,
                    CASE
                        WHEN NULLIF(f.snapshot_path, '') IS NULL
                        THEN CAST(f.offset_index AS REAL) / MAX(COALESCE(vc.fps, 0.5), 0.001)
                    END AS video_offset_seconds
                FROM frames f
                LEFT JOIN video_chunks vc ON f.video_chunk_id = vc.id
                WHERE f.app_name = ?1
                  AND f.timestamp >= ?2
                  AND f.timestamp <= ?3
                  AND f.focused = 1
                  AND COALESCE(NULLIF(f.snapshot_path, ''), vc.file_path) IS NOT NULL
                  AND COALESCE(NULLIF(f.snapshot_path, ''), vc.file_path) NOT LIKE 'cloud://%'
                UNION ALL
                SELECT
                    f.id,
                    f.timestamp,
                    u.browser_url,
                    COALESCE(NULLIF(f.snapshot_path, ''), vc.file_path) AS source_path,
                    CASE WHEN NULLIF(f.snapshot_path, '') IS NULL THEN vc.id END AS video_chunk_id,
                    CASE
                        WHEN NULLIF(f.snapshot_path, '') IS NULL
                        THEN CAST(f.offset_index AS REAL) / MAX(COALESCE(vc.fps, 0.5), 0.001)
                    END AS video_offset_seconds
                FROM ui_events u
                JOIN frames f ON f.id = u.frame_id
                LEFT JOIN video_chunks vc ON f.video_chunk_id = vc.id
                WHERE u.app_name = ?1
                  AND f.timestamp >= ?2
                  AND f.timestamp <= ?3
                  AND (f.app_name IS NULL OR f.app_name = '')
                  AND u.id = (
                      SELECT latest.id
                      FROM ui_events latest
                      WHERE latest.frame_id = f.id
                        AND latest.app_name IS NOT NULL
                        AND latest.app_name != ''
                      ORDER BY latest.timestamp DESC, latest.id DESC
                      LIMIT 1
                  )
                  AND COALESCE(NULLIF(f.snapshot_path, ''), vc.file_path) IS NOT NULL
                  AND COALESCE(NULLIF(f.snapshot_path, ''), vc.file_path) NOT LIKE 'cloud://%'
            ), bucketed AS (
                SELECT *, ROW_NUMBER() OVER (
                    PARTITION BY
                        CAST(unixepoch(timestamp) / 10 AS INTEGER),
                        CASE WHEN ?4 IS NULL THEN '' ELSE COALESCE(browser_url, '') END
                    ORDER BY timestamp, id
                ) AS bucket_rank
                FROM candidates
                WHERE ?4 IS NULL
                   OR instr(lower(COALESCE(browser_url, '')), lower(?4)) > 0
            )
            SELECT id, timestamp, browser_url, source_path, video_chunk_id, video_offset_seconds
            FROM bucketed
            WHERE bucket_rank = 1
            ORDER BY timestamp, id;

-- @id screenpipe.speakers.active_in_range
-- @src crates/screenpipe-db/src/db/speakers.rs:460-476
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
-- @src crates/screenpipe-db/src/db/speakers.rs:580-654
-- @style sqlx positional ? binds (renumbered ?N); speaker IN-list omitted (no filter)
-- @tags analytics,dynamic
-- @note Speaker-naming page: CTE of each unnamed speaker's 3 latest transcriptions (correlated IN ... ORDER BY timestamp DESC LIMIT 3), joined back to all their transcriptions, json_group_array(DISTINCT json_object(...)) samples, COUNT per speaker, ORDER BY count.
-- @param ?1 10
-- @param ?2 0
WITH RecentAudioPaths AS (
                SELECT DISTINCT
                    s.id as speaker_id,
                    ac.id as audio_chunk_id,
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
                AND TRIM(COALESCE(ac.file_path, '')) NOT IN ('', '.')
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
                        DISTINCT json_object(
                            'path', rap.file_path,
                            'audio_chunk_id', rap.audio_chunk_id,
                            'transcript', rap.transcription,
                            'start_time', rap.start_time,
                            'end_time', rap.end_time,
                            'timestamp', rap.abs_timestamp
                        )
                    ))
                    ELSE json_patch(
                        json(s.metadata),
                        json_object('audio_samples', json_group_array(
                            DISTINCT json_object(
                                'path', rap.file_path,
                                'audio_chunk_id', rap.audio_chunk_id,
                                'transcript', rap.transcription,
                                'start_time', rap.start_time,
                                'end_time', rap.end_time,
                                'timestamp', rap.abs_timestamp
                            )
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
-- @src crates/screenpipe-db/src/db/accessibility.rs:462-474
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
-- @src crates/screenpipe-db/src/db/maintenance.rs:1385-1388
-- @style no binds
-- @tags analytics
-- @note Per-machine frame counts for the sync/storage settings page: GROUP BY machine_id over every frame (no machine_id index).
SELECT machine_id, COUNT(*) FROM frames WHERE machine_id IS NOT NULL GROUP BY machine_id;

-- @id screenpipe.retention.video_files_in_slice
-- @src crates/screenpipe-db/src/db/maintenance.rs:1007-1015
-- @style sqlx ?N numbered binds (rfc3339 strings)
-- @tags cpu-evidence
-- @note Retention slice (2 hours): video files whose every frame is in range. The NOT IN subquery reads every frame outside the hour (frames.timestamp NOT BETWEEN), i.e. the whole table, per slice (https://github.com/screenpipe/screenpipe/issues/2930).
-- @param ?1 '2026-08-29T09:00:00+00:00'
-- @param ?2 '2026-08-29T11:00:00+00:00'
SELECT file_path FROM video_chunks
WHERE id IN (SELECT DISTINCT video_chunk_id FROM frames
             WHERE timestamp BETWEEN ?1 AND ?2 AND video_chunk_id IS NOT NULL)
AND id NOT IN (SELECT DISTINCT video_chunk_id FROM frames
               WHERE timestamp NOT BETWEEN ?1 AND ?2 AND video_chunk_id IS NOT NULL)
AND file_path NOT LIKE 'cloud://%';

-- @id screenpipe.retention.delete_frames_slice
-- @src crates/screenpipe-db/src/db/maintenance.rs:1122-1126
-- @style sqlx ?N numbered binds (rfc3339 strings)
-- @tags batch,cpu-evidence
-- @note Retention delete of a 2-hour slice of frames: each row fires frames_ad (external-content frames_fts 'delete' with the old text) and activity_frames_ad. https://github.com/screenpipe/screenpipe/issues/2930 measured 4 min 39 s for 6,548 frames with the earlier standalone FTS table.
-- @param ?1 '2026-08-29T09:00:00+00:00'
-- @param ?2 '2026-08-29T11:00:00+00:00'
DELETE FROM frames WHERE timestamp BETWEEN ?1 AND ?2;

-- @id screenpipe.retention.delete_elements_slice
-- @src crates/screenpipe-db/src/db/maintenance.rs:1112-1116
-- @style sqlx ?N numbered binds (rfc3339 strings)
-- @tags batch,cpu-evidence
-- @note Elements of the same slice, deleted first: IN-subquery on frames by timestamp, elements_ad trigger per row into elements_fts. Element cleanup holding the writer: https://github.com/screenpipe/screenpipe/issues/7666.
-- @param ?1 '2026-08-29T09:00:00+00:00'
-- @param ?2 '2026-08-29T11:00:00+00:00'
DELETE FROM elements WHERE frame_id IN (SELECT id FROM frames WHERE timestamp BETWEEN ?1 AND ?2);

-- @id screenpipe.retention.next_timestamp
-- @src crates/screenpipe-db/src/db/maintenance.rs:1254-1266
-- @style sqlx ?N numbered binds
-- @tags dynamic
-- @note Next retention boundary: UNION ALL of three MIN(timestamp) range probes (index-bounded by text, then filtered by julianday()) over frames, audio_transcriptions and ui_events, ordered by julianday.
-- @param ?1 '2026-08-29T10:00:00'
-- @param ?2 '2026-09-05T00:00:01'
-- @param ?3 '2026-08-29T10:00:00+00:00'
-- @param ?4 '2026-09-05T00:00:00+00:00'
SELECT ts FROM (
    SELECT MIN(timestamp) AS ts FROM frames
    WHERE timestamp>=?1 AND timestamp<?2 AND julianday(timestamp)>julianday(?3) AND julianday(timestamp)<=julianday(?4)
    UNION ALL
    SELECT MIN(timestamp) AS ts FROM audio_transcriptions
    WHERE timestamp>=?1 AND timestamp<?2 AND julianday(timestamp)>julianday(?3) AND julianday(timestamp)<=julianday(?4)
    UNION ALL
    SELECT MIN(timestamp) AS ts FROM ui_events
    WHERE timestamp>=?1 AND timestamp<?2 AND julianday(timestamp)>julianday(?3) AND julianday(timestamp)<=julianday(?4)
 ) WHERE ts IS NOT NULL ORDER BY julianday(ts) LIMIT 1;

-- @id screenpipe.retention.cleanup_orphaned_video_chunks
-- @src crates/screenpipe-db/src/db/maintenance.rs:1203-1206
-- @style no binds
-- @tags batch
-- @note End-of-run orphan cleanup: DELETE video_chunks NOT IN (SELECT DISTINCT video_chunk_id FROM frames), a full frames scan into a temp b-tree (the code calls it "the expensive operation").
DELETE FROM video_chunks WHERE id NOT IN (SELECT DISTINCT video_chunk_id FROM frames WHERE video_chunk_id IS NOT NULL);

-- @id screenpipe.audio.find_chunk_by_path
-- @src crates/screenpipe-db/src/db/audio.rs:65
-- @style sqlx ?N numbered binds
-- @tags hotpath,cpu-evidence
-- @note Runs after every audio chunk write (2.5-5.5k times a day). audio_chunks has no file_path index, so it is a full scan: 2-9 s per call on 608k chunks (https://github.com/screenpipe/screenpipe/issues/7704).
-- @param ?1 '/Users/demo/.screenpipe/data/MacBook Pro Microphone (input)_2026-10-27_17-57-18.mp4'
SELECT id FROM audio_chunks WHERE file_path = ?1;

-- @id screenpipe.frames.latest_video_chunk
-- @src crates/screenpipe-db/src/db/frames.rs:111
-- @style sqlx ?N numbered binds
-- @tags hot-small,hotpath
-- @note Before every frame insert: newest video chunk of the device via idx_video_chunks_device_name_id.
-- @param ?1 'monitor_1'
SELECT id, file_path FROM video_chunks WHERE device_name = ?1 ORDER BY id DESC LIMIT 1;

-- @id screenpipe.frames.insert_with_ocr
-- @src crates/screenpipe-db/src/db/frames.rs:1083-1097
-- @style sqlx ?N numbered binds
-- @tags hot-small,hotpath
-- @note Capture write: one frame with its OCR text; frames_ai inserts the text into frames_fts in the same statement.
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
-- @param ?11 NULL
INSERT INTO frames (video_chunk_id, offset_index, timestamp, name, browser_url, app_name, window_name, focused, device_name, full_text, text_json) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11);

-- @id screenpipe.frames.latest_timestamp
-- @src crates/screenpipe-db/src/db/search.rs:2407
-- @style no binds
-- @tags hot-small,hotpath
-- @note Health endpoint: newest frame timestamp, a reverse walk of idx_frames_timestamp.
SELECT timestamp FROM frames WHERE timestamp IS NOT NULL AND timestamp != '' ORDER BY timestamp DESC LIMIT 1;
