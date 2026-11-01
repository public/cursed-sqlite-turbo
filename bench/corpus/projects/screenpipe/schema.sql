-- screenpipe schema subset (screenpipe/screenpipe @ 892199f742e46d0c5d9e8c06687b35ca7c2b6547, the last commit under the
-- MIT licence, 2026-06-10; see LICENSE). Produced by applying all 89 files in crates/screenpipe-db/src/migrations/ in
-- order to an empty database with the sqlite3 CLI and dumping the final objects for the tables the queries touch.
-- speaker_embeddings (sqlite-vec) is omitted: no query uses it. FTS5 tables are external-content (content='frames'
-- etc.) and kept in sync by the app's own triggers, which are included. ocr_text is the legacy OCR table that this
-- version's /search still LEFT JOINs. Indexes are exactly the app's.
CREATE TABLE video_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL
, device_name TEXT NOT NULL DEFAULT '', sync_id TEXT, machine_id TEXT, synced_at DATETIME, fps REAL NOT NULL DEFAULT 0.5, cloud_blob_id TEXT DEFAULT NULL, evicted_at TIMESTAMP DEFAULT NULL);
CREATE TABLE audio_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL
, timestamp TIMESTAMP, sync_id TEXT, machine_id TEXT, synced_at DATETIME, evicted_at TIMESTAMP DEFAULT NULL, transcription_status TEXT
    NOT NULL DEFAULT 'pending'
    CHECK (transcription_status IN ('pending', 'transcribed', 'silent', 'failed')), transcription_attempts INTEGER
    NOT NULL DEFAULT 0, last_transcription_attempt_at TIMESTAMP, transcription_failure_reason TEXT);
CREATE INDEX idx_audio_chunks_timestamp ON audio_chunks(timestamp);
CREATE TABLE "ocr_text" (
    frame_id INTEGER NOT NULL,
    text TEXT NOT NULL,
    text_json TEXT,
    app_name TEXT NOT NULL DEFAULT '',
    ocr_engine TEXT NOT NULL DEFAULT 'unknown'
, window_name TEXT, focused BOOLEAN DEFAULT FALSE, text_length INTEGER, sync_id TEXT, synced_at DATETIME, redacted_at       INTEGER);
CREATE TABLE tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE vision_tags (
    vision_id INTEGER NOT NULL,
    tag_id INTEGER NOT NULL,
    PRIMARY KEY (vision_id, tag_id),
    FOREIGN KEY (vision_id) REFERENCES frames(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);
CREATE TABLE audio_tags (
    audio_chunk_id INTEGER NOT NULL,
    tag_id INTEGER NOT NULL,
    PRIMARY KEY (audio_chunk_id, tag_id),
    FOREIGN KEY (audio_chunk_id) REFERENCES audio_chunks(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);
CREATE INDEX idx_vision_tags_vision_id ON vision_tags(vision_id);
CREATE INDEX idx_vision_tags_tag_id ON vision_tags(tag_id);
CREATE INDEX idx_audio_tags_audio_chunk_id ON audio_tags(audio_chunk_id);
CREATE INDEX idx_audio_tags_tag_id ON audio_tags(tag_id);
CREATE INDEX idx_ocr_text_frame_id ON ocr_text(frame_id);
CREATE INDEX idx_ocr_text_frame_app_window ON ocr_text(frame_id, app_name, window_name);
CREATE TABLE speakers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    metadata JSON
, hallucination BOOLEAN DEFAULT FALSE, centroid FLOAT[512], embedding_count INTEGER DEFAULT 0);
CREATE TABLE "audio_transcriptions" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    audio_chunk_id INTEGER NOT NULL,
    offset_index INTEGER NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    transcription TEXT NOT NULL,
    device TEXT NOT NULL DEFAULT '',
    is_input_device BOOLEAN NOT NULL DEFAULT TRUE,
    speaker_id INTEGER,
    transcription_engine TEXT NOT NULL DEFAULT 'Whisper', start_time REAL, end_time REAL, text_length INTEGER, sync_id TEXT, synced_at DATETIME, redacted_at       INTEGER,
    FOREIGN KEY (audio_chunk_id) REFERENCES audio_chunks(id)
);
CREATE INDEX idx_audio_transcriptions_audio_chunk_id_timestamp ON audio_transcriptions(audio_chunk_id, timestamp);
CREATE INDEX idx_audio_transcriptions_audio_chunk_id ON audio_transcriptions(audio_chunk_id);
CREATE INDEX idx_audio_transcriptions_timestamp ON audio_transcriptions(timestamp);
CREATE INDEX idx_audio_transcriptions_transcription ON audio_transcriptions(transcription);
CREATE INDEX idx_ocr_text_length ON ocr_text (text_length);
CREATE INDEX idx_audio_transcriptions_length ON audio_transcriptions (text_length);
CREATE TABLE ui_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    session_id TEXT,
    relative_ms INTEGER NOT NULL DEFAULT 0,
    event_type TEXT NOT NULL,  -- click, move, scroll, key, text, app_switch, window_focus, clipboard
    -- Position
    x INTEGER,
    y INTEGER,
    delta_x INTEGER,
    delta_y INTEGER,
    -- Mouse/key
    button INTEGER,
    click_count INTEGER,
    key_code INTEGER,
    modifiers INTEGER,
    -- Text content
    text_content TEXT,
    text_length INTEGER,
    -- App context
    app_name TEXT,
    app_pid INTEGER,
    window_title TEXT,
    browser_url TEXT,
    -- Element context (from accessibility APIs)
    element_role TEXT,
    element_name TEXT,
    element_value TEXT,
    element_description TEXT,
    element_automation_id TEXT,
    element_bounds TEXT,  -- JSON: {"x":0,"y":0,"width":100,"height":50}
    -- Frame correlation
    frame_id INTEGER,
    -- Sync columns
    sync_id TEXT,
    machine_id TEXT,
    synced_at DATETIME
, redacted_at       INTEGER);
CREATE INDEX idx_ui_events_timestamp ON ui_events(timestamp);
CREATE INDEX idx_ui_events_event_type ON ui_events(event_type);
CREATE INDEX idx_ui_events_app_name ON ui_events(app_name);
CREATE INDEX idx_ui_events_session_id ON ui_events(session_id);
CREATE INDEX idx_ui_events_frame_id ON ui_events(frame_id);
CREATE INDEX idx_ui_events_sync_id ON ui_events(sync_id);
CREATE INDEX idx_ui_events_synced_at ON ui_events(synced_at);
CREATE INDEX idx_ui_events_unsynced ON ui_events(synced_at) WHERE synced_at IS NULL;
CREATE VIRTUAL TABLE ui_events_fts USING fts5(
    text_content,
    app_name,
    window_title,
    element_name,
    content='ui_events',
    content_rowid='id',
    tokenize='unicode61'
);
CREATE TRIGGER ui_events_ad AFTER DELETE ON ui_events BEGIN
    INSERT INTO ui_events_fts(ui_events_fts, rowid, text_content, app_name, window_title, element_name)
    VALUES('delete', OLD.id, OLD.text_content, OLD.app_name, OLD.window_title, OLD.element_name);
END;
CREATE TRIGGER ui_events_au AFTER UPDATE ON ui_events BEGIN
    INSERT INTO ui_events_fts(ui_events_fts, rowid, text_content, app_name, window_title, element_name)
    VALUES('delete', OLD.id, OLD.text_content, OLD.app_name, OLD.window_title, OLD.element_name);
    INSERT INTO ui_events_fts(rowid, text_content, app_name, window_title, element_name)
    VALUES (NEW.id, NEW.text_content, NEW.app_name, NEW.window_title, NEW.element_name);
END;
CREATE UNIQUE INDEX idx_audio_transcription_chunk_text
ON audio_transcriptions(audio_chunk_id, transcription);
CREATE INDEX idx_video_chunks_device_name ON video_chunks(device_name);
CREATE INDEX idx_video_chunks_device_name_id ON video_chunks(device_name, id DESC);
CREATE TABLE "frames" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    video_chunk_id INTEGER DEFAULT NULL,
    offset_index INTEGER NOT NULL DEFAULT 0,
    timestamp TIMESTAMP NOT NULL,
    name TEXT,
    app_name TEXT DEFAULT NULL,
    window_name TEXT DEFAULT NULL,
    focused BOOLEAN DEFAULT NULL,
    browser_url TEXT DEFAULT NULL,
    device_name TEXT NOT NULL DEFAULT '',
    sync_id TEXT,
    machine_id TEXT,
    synced_at DATETIME,
    -- New event-driven capture columns
    snapshot_path TEXT DEFAULT NULL,
    accessibility_text TEXT DEFAULT NULL,
    accessibility_tree_json TEXT DEFAULT NULL,
    content_hash INTEGER DEFAULT NULL,
    simhash INTEGER DEFAULT NULL,
    capture_trigger TEXT DEFAULT NULL,
    text_source TEXT DEFAULT NULL, cloud_blob_id TEXT DEFAULT NULL, full_text TEXT DEFAULT NULL, elements_ref_frame_id INTEGER DEFAULT NULL, accessibility_redacted_at   INTEGER, image_redacted_at       INTEGER, document_path TEXT DEFAULT NULL,
    FOREIGN KEY (video_chunk_id) REFERENCES video_chunks(id)
);
CREATE INDEX idx_frames_timestamp ON frames(timestamp);
CREATE INDEX idx_frames_video_chunk_id ON frames(video_chunk_id);
CREATE INDEX idx_frames_timestamp_device
  ON frames(timestamp, device_name);
CREATE INDEX idx_frames_snapshot_path
  ON frames(snapshot_path) WHERE snapshot_path IS NOT NULL;
CREATE TRIGGER ui_events_ai AFTER INSERT ON ui_events BEGIN
    INSERT OR IGNORE INTO ui_events_fts(rowid, text_content, app_name, window_title, element_name)
    VALUES (NEW.id, NEW.text_content, NEW.app_name, NEW.window_title, NEW.element_name);
END;
CREATE TABLE meetings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    meeting_start TEXT NOT NULL,
    meeting_end TEXT,
    meeting_app TEXT NOT NULL,
    title TEXT,
    attendees TEXT,
    detection_source TEXT NOT NULL DEFAULT 'app',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
, note TEXT, end_reason TEXT);
CREATE INDEX idx_meetings_start ON meetings(meeting_start);
CREATE INDEX idx_meetings_end ON meetings(meeting_end);
CREATE TABLE elements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    frame_id INTEGER NOT NULL,
    source TEXT NOT NULL,             -- 'ocr' | 'accessibility'
    role TEXT NOT NULL,               -- OCR: 'page','block','paragraph','line','word'
                                      -- AX: 'AXButton','AXTextField','AXStaticText', etc.
    text TEXT,                        -- element text content (NULL for container nodes)
    parent_id INTEGER,               -- self-referential FK for tree hierarchy (NULL = root)
    depth INTEGER NOT NULL DEFAULT 0, -- tree depth (0 = root)
    left_bound REAL,                 -- normalized 0-1 bounding box
    top_bound REAL,
    width_bound REAL,
    height_bound REAL,
    confidence REAL,                 -- OCR confidence (0-100), NULL for AX
    sort_order INTEGER NOT NULL DEFAULT 0, properties TEXT, on_screen INTEGER, -- sibling order within parent
    FOREIGN KEY (frame_id) REFERENCES frames(id),
    FOREIGN KEY (parent_id) REFERENCES elements(id)
);
CREATE INDEX idx_elements_frame_id ON elements(frame_id);
CREATE INDEX idx_elements_parent_id ON elements(parent_id);
CREATE INDEX idx_elements_source ON elements(source);
CREATE INDEX idx_elements_frame_source ON elements(frame_id, source);
CREATE VIRTUAL TABLE elements_fts USING fts5(
    text,
    role,
    frame_id UNINDEXED,
    content='elements',
    content_rowid='id',
    tokenize='unicode61'
);
CREATE TRIGGER elements_ai AFTER INSERT ON elements
WHEN NEW.text IS NOT NULL AND NEW.text != ''
BEGIN
    INSERT INTO elements_fts(rowid, text, role, frame_id)
    VALUES (NEW.id, NEW.text, NEW.role, NEW.frame_id);
END;
CREATE TRIGGER elements_ad AFTER DELETE ON elements
WHEN OLD.text IS NOT NULL AND OLD.text != ''
BEGIN
    INSERT INTO elements_fts(elements_fts, rowid, text, role, frame_id)
    VALUES ('delete', OLD.id, OLD.text, OLD.role, OLD.frame_id);
END;
CREATE TRIGGER elements_au AFTER UPDATE ON elements
WHEN OLD.text IS NOT NULL AND OLD.text != ''
BEGIN
    INSERT INTO elements_fts(elements_fts, rowid, text, role, frame_id)
    VALUES ('delete', OLD.id, OLD.text, OLD.role, OLD.frame_id);
    INSERT INTO elements_fts(rowid, text, role, frame_id)
    VALUES (NEW.id, NEW.text, NEW.role, NEW.frame_id);
END;
CREATE VIRTUAL TABLE audio_transcriptions_fts USING fts5(
    transcription,
    device,
    speaker_id,
    content='audio_transcriptions',
    content_rowid='id',
    tokenize='unicode61'
);
CREATE TRIGGER audio_transcriptions_ai AFTER INSERT ON audio_transcriptions
WHEN NEW.transcription IS NOT NULL AND NEW.transcription != ''
BEGIN
    INSERT INTO audio_transcriptions_fts(rowid, transcription, device, speaker_id)
    VALUES (NEW.id, NEW.transcription, COALESCE(NEW.device, ''), NEW.speaker_id);
END;
CREATE TRIGGER audio_transcriptions_delete AFTER DELETE ON audio_transcriptions
WHEN OLD.transcription IS NOT NULL AND OLD.transcription != ''
BEGIN
    INSERT INTO audio_transcriptions_fts(audio_transcriptions_fts, rowid, transcription, device, speaker_id)
    VALUES ('delete', OLD.id, OLD.transcription, COALESCE(OLD.device, ''), OLD.speaker_id);
END;
CREATE TRIGGER audio_transcriptions_update AFTER UPDATE ON audio_transcriptions
WHEN OLD.transcription IS NOT NULL AND OLD.transcription != ''
BEGIN
    INSERT INTO audio_transcriptions_fts(audio_transcriptions_fts, rowid, transcription, device, speaker_id)
    VALUES ('delete', OLD.id, OLD.transcription, COALESCE(OLD.device, ''), OLD.speaker_id);
    INSERT INTO audio_transcriptions_fts(rowid, transcription, device, speaker_id)
    VALUES (NEW.id, COALESCE(NEW.transcription, ''), COALESCE(NEW.device, ''), NEW.speaker_id);
END;
CREATE INDEX idx_video_chunks_cloud_blob_id
    ON video_chunks(cloud_blob_id) WHERE cloud_blob_id IS NULL;
CREATE INDEX idx_frames_cloud_blob_id
    ON frames(cloud_blob_id) WHERE cloud_blob_id IS NULL AND snapshot_path IS NOT NULL;
CREATE INDEX idx_elements_source_role_text
    ON elements(source, role, frame_id)
    WHERE text IS NOT NULL;
CREATE INDEX idx_frames_sync_id ON frames(sync_id) WHERE sync_id IS NOT NULL;
CREATE INDEX idx_ocr_text_sync_id ON ocr_text(sync_id) WHERE sync_id IS NOT NULL;
CREATE INDEX idx_audio_transcriptions_sync_id ON audio_transcriptions(sync_id) WHERE sync_id IS NOT NULL;
CREATE INDEX idx_elements_frame_source_role ON elements(frame_id, source, role) WHERE text IS NOT NULL;
CREATE INDEX idx_frames_elements_ref_frame_id
    ON frames(elements_ref_frame_id)
    WHERE elements_ref_frame_id IS NOT NULL;
CREATE VIRTUAL TABLE frames_fts USING fts5(
    full_text,
    app_name,
    window_name,
    browser_url,
    content='frames',
    content_rowid='id',
    tokenize='unicode61'
);
CREATE TRIGGER frames_ai AFTER INSERT ON frames
WHEN NEW.full_text IS NOT NULL AND NEW.full_text != ''
BEGIN
    INSERT INTO frames_fts(rowid, full_text, app_name, window_name, browser_url)
    VALUES (
        NEW.id,
        NEW.full_text,
        COALESCE(NEW.app_name, ''),
        COALESCE(NEW.window_name, ''),
        COALESCE(NEW.browser_url, '')
    );
END;
CREATE TRIGGER frames_ad AFTER DELETE ON frames
WHEN OLD.full_text IS NOT NULL AND OLD.full_text != ''
BEGIN
    INSERT INTO frames_fts(frames_fts, rowid, full_text, app_name, window_name, browser_url)
    VALUES (
        'delete',
        OLD.id,
        OLD.full_text,
        COALESCE(OLD.app_name, ''),
        COALESCE(OLD.window_name, ''),
        COALESCE(OLD.browser_url, '')
    );
END;
CREATE TRIGGER frames_au AFTER UPDATE OF full_text, app_name, window_name, browser_url ON frames
BEGIN
    -- remove old tokens if the old row was indexed
    INSERT INTO frames_fts(frames_fts, rowid, full_text, app_name, window_name, browser_url)
    SELECT
        'delete',
        OLD.id,
        OLD.full_text,
        COALESCE(OLD.app_name, ''),
        COALESCE(OLD.window_name, ''),
        COALESCE(OLD.browser_url, '')
    WHERE OLD.full_text IS NOT NULL AND OLD.full_text != '';

    -- insert new tokens if the new row should be indexed
    INSERT INTO frames_fts(rowid, full_text, app_name, window_name, browser_url)
    SELECT
        NEW.id,
        NEW.full_text,
        COALESCE(NEW.app_name, ''),
        COALESCE(NEW.window_name, ''),
        COALESCE(NEW.browser_url, '')
    WHERE NEW.full_text IS NOT NULL AND NEW.full_text != '';
END;
CREATE INDEX idx_audio_transcriptions_speaker_id_timestamp
  ON audio_transcriptions(speaker_id, timestamp DESC);
CREATE INDEX idx_ocr_text_redacted_at             ON ocr_text(redacted_at);
CREATE INDEX idx_audio_transcriptions_redacted_at ON audio_transcriptions(redacted_at);
CREATE INDEX idx_frames_accessibility_redacted_at ON frames(accessibility_redacted_at);
CREATE INDEX idx_ui_events_redacted_at            ON ui_events(redacted_at);
CREATE INDEX idx_ui_events_type_redacted_at
  ON ui_events(event_type, redacted_at);
CREATE INDEX idx_elements_on_screen
    ON elements(frame_id, on_screen)
    WHERE on_screen IS NOT NULL;
CREATE INDEX idx_frames_image_redaction_pending
    ON frames(id DESC)
    WHERE image_redacted_at IS NULL;
CREATE TABLE meeting_transcript_segments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    meeting_id INTEGER NOT NULL,
    provider TEXT NOT NULL,
    model TEXT,
    item_id TEXT NOT NULL,
    device_name TEXT NOT NULL DEFAULT '',
    device_type TEXT NOT NULL DEFAULT '',
    speaker_name TEXT,
    transcript TEXT NOT NULL,
    captured_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')), speaker_id INTEGER,
    FOREIGN KEY (meeting_id) REFERENCES meetings(id) ON DELETE CASCADE,
    UNIQUE(meeting_id, provider, item_id, device_name, device_type)
);
CREATE INDEX idx_meeting_transcript_segments_meeting_time
    ON meeting_transcript_segments(meeting_id, captured_at);
CREATE TABLE diarization_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    audio_chunk_id INTEGER NOT NULL REFERENCES audio_chunks(id) ON DELETE CASCADE,
    mode TEXT NOT NULL CHECK (mode IN ('live', 'background')),
    provider TEXT NOT NULL,
    model TEXT,
    status TEXT NOT NULL DEFAULT 'completed',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    metadata JSON
);
CREATE TABLE diarization_segments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    diarization_run_id INTEGER NOT NULL REFERENCES diarization_runs(id) ON DELETE CASCADE,
    audio_chunk_id INTEGER NOT NULL REFERENCES audio_chunks(id) ON DELETE CASCADE,
    provider_speaker_label TEXT NOT NULL,
    speaker_id INTEGER REFERENCES speakers(id) ON DELETE SET NULL,
    source TEXT NOT NULL DEFAULT 'provider',
    start_time REAL NOT NULL,
    end_time REAL NOT NULL,
    confidence REAL,
    overlap BOOLEAN NOT NULL DEFAULT FALSE,
    metadata JSON
);
CREATE INDEX idx_diarization_runs_audio_chunk
    ON diarization_runs(audio_chunk_id, mode, created_at DESC);
CREATE INDEX idx_diarization_segments_run
    ON diarization_segments(diarization_run_id);
CREATE INDEX idx_diarization_segments_chunk_time
    ON diarization_segments(audio_chunk_id, start_time, end_time);
CREATE INDEX idx_diarization_segments_speaker
    ON diarization_segments(speaker_id, audio_chunk_id);
CREATE INDEX idx_audio_chunks_pending_timestamp
    ON audio_chunks(timestamp)
    WHERE transcription_status = 'pending';
CREATE INDEX idx_audio_chunks_status
    ON audio_chunks(transcription_status);
CREATE UNIQUE INDEX idx_meetings_single_open
    ON meetings((1))
    WHERE meeting_end IS NULL;
CREATE INDEX idx_meeting_transcript_segments_speaker
    ON meeting_transcript_segments(speaker_id);
