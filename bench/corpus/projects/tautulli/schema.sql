-- Tautulli monitor database (Tautulli/Tautulli @ c0f0120e9dd385eee18087aaef63a8a5bab9e4da, GPL-3.0).
-- Only the CREATE statements the queries need, from plexpy/__init__.py dbcheck() (tables at lines 618-740, indexes at
-- lines 2780-2875 and 2938). The fresh-install CREATE TABLE statements already carry every column the upgrade ALTERs add.
-- Fetch the original with tools/fetch.sh tautulli.

CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, session_key INTEGER, session_id TEXT,
  transcode_key TEXT, rating_key INTEGER, section_id INTEGER, media_type TEXT, started INTEGER, stopped INTEGER,
  paused_counter INTEGER DEFAULT 0, state TEXT, user_id INTEGER, user TEXT, friendly_name TEXT,
  ip_address TEXT, machine_id TEXT, bandwidth INTEGER, location TEXT, player TEXT, product TEXT, platform TEXT,
  title TEXT, parent_title TEXT, grandparent_title TEXT, original_title TEXT, full_title TEXT,
  media_index INTEGER, parent_media_index INTEGER,
  thumb TEXT, parent_thumb TEXT, grandparent_thumb TEXT, year INTEGER,
  parent_rating_key INTEGER, grandparent_rating_key INTEGER,
  originally_available_at TEXT, added_at INTEGER, guid TEXT,
  view_offset INTEGER DEFAULT 0, duration INTEGER, video_decision TEXT, audio_decision TEXT,
  transcode_decision TEXT, container TEXT, bitrate INTEGER, width INTEGER, height INTEGER,
  video_codec TEXT, video_bitrate INTEGER, video_resolution TEXT, video_width INTEGER, video_height INTEGER,
  video_framerate TEXT, video_scan_type TEXT, video_full_resolution TEXT,
  video_dynamic_range TEXT, aspect_ratio TEXT,
  audio_codec TEXT, audio_bitrate INTEGER, audio_channels INTEGER, audio_language TEXT, audio_language_code TEXT,
  subtitle_codec TEXT, subtitle_forced INTEGER, subtitle_language TEXT,
  stream_bitrate INTEGER, stream_video_resolution TEXT, quality_profile TEXT,
  stream_container_decision TEXT, stream_container TEXT,
  stream_video_decision TEXT, stream_video_codec TEXT, stream_video_bitrate INTEGER, stream_video_width INTEGER,
  stream_video_height INTEGER, stream_video_framerate TEXT, stream_video_scan_type TEXT, stream_video_full_resolution TEXT,
  stream_video_dynamic_range TEXT,
  stream_audio_decision TEXT, stream_audio_codec TEXT, stream_audio_bitrate INTEGER, stream_audio_channels INTEGER,
  stream_audio_language TEXT, stream_audio_language_code TEXT,
  subtitles INTEGER, stream_subtitle_decision TEXT, stream_subtitle_codec TEXT,
  stream_subtitle_forced INTEGER, stream_subtitle_language TEXT,
  transcode_protocol TEXT, transcode_container TEXT,
  transcode_video_codec TEXT, transcode_audio_codec TEXT, transcode_audio_channels INTEGER,
  transcode_width INTEGER, transcode_height INTEGER,
  transcode_hw_decoding INTEGER, transcode_hw_encoding INTEGER,
  optimized_version INTEGER, optimized_version_profile TEXT, optimized_version_title TEXT,
  synced_version INTEGER, synced_version_profile TEXT,
  live INTEGER, live_uuid TEXT,
  channel_call_sign TEXT, channel_id TEXT, channel_identifier TEXT, channel_title TEXT, channel_thumb TEXT, channel_vcn TEXT,
  secure INTEGER, relayed INTEGER,
  buffer_count INTEGER DEFAULT 0, buffer_last_triggered INTEGER, last_paused INTEGER, watched INTEGER DEFAULT 0,
  intro INTEGER DEFAULT 0, credits INTEGER DEFAULT 0, commercial INTEGER DEFAULT 0, marker INTEGER DEFAULT 0,
  initial_stream INTEGER DEFAULT 1, write_attempts INTEGER DEFAULT 0, raw_stream_info TEXT,
  rating_key_websocket TEXT);

CREATE TABLE IF NOT EXISTS sessions_continued (id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER, machine_id TEXT, media_type TEXT, stopped INTEGER);

CREATE TABLE IF NOT EXISTS session_history (id INTEGER PRIMARY KEY AUTOINCREMENT, reference_id INTEGER,
  started INTEGER, stopped INTEGER, rating_key INTEGER, user_id INTEGER, user TEXT,
  ip_address TEXT, paused_counter INTEGER DEFAULT 0, player TEXT, product TEXT, product_version TEXT,
  platform TEXT, platform_version TEXT, profile TEXT, machine_id TEXT,
  bandwidth INTEGER, location TEXT, quality_profile TEXT, secure INTEGER, relayed INTEGER,
  parent_rating_key INTEGER, grandparent_rating_key INTEGER, media_type TEXT, section_id INTEGER,
  live INTEGER DEFAULT 0, transcode_decision TEXT,
  view_offset INTEGER DEFAULT 0);

CREATE TABLE IF NOT EXISTS session_history_media_info (id INTEGER PRIMARY KEY, rating_key INTEGER,
  video_decision TEXT, audio_decision TEXT, transcode_decision TEXT, duration INTEGER DEFAULT 0,
  container TEXT, bitrate INTEGER, width INTEGER, height INTEGER, video_bitrate INTEGER, video_bit_depth INTEGER,
  video_codec TEXT, video_codec_level TEXT, video_width INTEGER, video_height INTEGER, video_resolution TEXT,
  video_framerate TEXT, video_scan_type TEXT, video_full_resolution TEXT, video_dynamic_range TEXT, aspect_ratio TEXT,
  audio_bitrate INTEGER, audio_codec TEXT, audio_channels INTEGER, audio_language TEXT, audio_language_code TEXT,
  subtitles INTEGER, subtitle_codec TEXT, subtitle_forced, subtitle_language TEXT,
  transcode_protocol TEXT, transcode_container TEXT, transcode_video_codec TEXT, transcode_audio_codec TEXT,
  transcode_audio_channels INTEGER, transcode_width INTEGER, transcode_height INTEGER,
  transcode_hw_requested INTEGER, transcode_hw_full_pipeline INTEGER,
  transcode_hw_decode TEXT, transcode_hw_decode_title TEXT, transcode_hw_decoding INTEGER,
  transcode_hw_encode TEXT, transcode_hw_encode_title TEXT, transcode_hw_encoding INTEGER,
  stream_container TEXT, stream_container_decision TEXT, stream_bitrate INTEGER,
  stream_video_decision TEXT, stream_video_bitrate INTEGER, stream_video_codec TEXT, stream_video_codec_level TEXT,
  stream_video_bit_depth INTEGER, stream_video_height INTEGER, stream_video_width INTEGER, stream_video_resolution TEXT,
  stream_video_framerate TEXT, stream_video_scan_type TEXT, stream_video_full_resolution TEXT, stream_video_dynamic_range TEXT,
  stream_audio_decision TEXT, stream_audio_codec TEXT, stream_audio_bitrate INTEGER, stream_audio_channels INTEGER,
  stream_audio_language TEXT, stream_audio_language_code TEXT,
  stream_subtitle_decision TEXT, stream_subtitle_codec TEXT,
  stream_subtitle_container TEXT, stream_subtitle_forced INTEGER, stream_subtitle_language TEXT,
  synced_version INTEGER, synced_version_profile TEXT,
  optimized_version INTEGER, optimized_version_profile TEXT, optimized_version_title TEXT);

CREATE TABLE IF NOT EXISTS session_history_metadata (id INTEGER PRIMARY KEY,
  rating_key INTEGER, parent_rating_key INTEGER, grandparent_rating_key INTEGER,
  title TEXT, parent_title TEXT, grandparent_title TEXT, original_title TEXT, full_title TEXT,
  media_index INTEGER, parent_media_index INTEGER,
  thumb TEXT, parent_thumb TEXT, grandparent_thumb TEXT,
  art TEXT, media_type TEXT, year INTEGER, originally_available_at TEXT, added_at INTEGER, updated_at INTEGER,
  last_viewed_at INTEGER, content_rating TEXT, summary TEXT, tagline TEXT, rating TEXT,
  duration INTEGER DEFAULT 0, guid TEXT, directors TEXT, writers TEXT, actors TEXT, genres TEXT, studio TEXT,
  labels TEXT, live INTEGER DEFAULT 0,
  channel_call_sign TEXT, channel_id TEXT, channel_identifier TEXT, channel_title TEXT, channel_thumb TEXT, channel_vcn TEXT,
  marker_credits_first INTEGER DEFAULT NULL, marker_credits_final INTEGER DEFAULT NULL);

CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER DEFAULT NULL UNIQUE, username TEXT NOT NULL, friendly_name TEXT,
  thumb TEXT, custom_avatar_url TEXT, title TEXT, email TEXT,
  is_active INTEGER DEFAULT 1, is_admin INTEGER DEFAULT 0, is_home_user INTEGER DEFAULT NULL,
  is_allow_sync INTEGER DEFAULT NULL, is_restricted INTEGER DEFAULT NULL,
  do_notify INTEGER DEFAULT 1, keep_history INTEGER DEFAULT 1, deleted_user INTEGER DEFAULT 0,
  is_archived INTEGER DEFAULT 0,
  allow_guest INTEGER DEFAULT 0, user_token TEXT, server_token TEXT, shared_libraries TEXT,
  filter_all TEXT, filter_movies TEXT, filter_tv TEXT, filter_music TEXT, filter_photos TEXT);

CREATE TABLE IF NOT EXISTS library_sections (id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT, section_id INTEGER, section_name TEXT, section_type TEXT, agent TEXT,
  thumb TEXT, custom_thumb_url TEXT, art TEXT, custom_art_url TEXT,
  count INTEGER, parent_count INTEGER, child_count INTEGER, is_active INTEGER DEFAULT 1,
  do_notify INTEGER DEFAULT 1, do_notify_created INTEGER DEFAULT 1, keep_history INTEGER DEFAULT 1,
  deleted_section INTEGER DEFAULT 0, is_archived INTEGER DEFAULT 0, UNIQUE(server_id, section_id));

CREATE INDEX IF NOT EXISTS idx_session_history_started_reference_id ON session_history (started, reference_id);
CREATE INDEX IF NOT EXISTS idx_session_history_stopped ON session_history (stopped);
CREATE INDEX IF NOT EXISTS idx_session_history_media_type_stopped ON session_history (media_type, stopped ASC);
CREATE INDEX IF NOT EXISTS idx_session_history_rating_key ON session_history (rating_key);
CREATE INDEX IF NOT EXISTS idx_session_history_parent_rating_key ON session_history (parent_rating_key);
CREATE INDEX IF NOT EXISTS idx_session_history_grandparent_rating_key ON session_history (grandparent_rating_key);
CREATE INDEX IF NOT EXISTS idx_session_history_user ON session_history (user);
CREATE INDEX IF NOT EXISTS idx_session_history_user_id_started ON session_history (user_id, started ASC);
CREATE INDEX IF NOT EXISTS idx_session_history_user_id_stopped ON session_history (user_id, stopped ASC);
CREATE INDEX IF NOT EXISTS idx_session_history_user_id_rating_key ON session_history (user_id, rating_key);
CREATE INDEX IF NOT EXISTS idx_session_history_section_id_started ON session_history (section_id, started ASC);
CREATE INDEX IF NOT EXISTS idx_session_history_section_id_stopped ON session_history (section_id, stopped ASC);
CREATE INDEX IF NOT EXISTS idx_session_history_reference_id ON session_history (reference_id ASC);
CREATE INDEX IF NOT EXISTS idx_session_history_metadata_rating_key ON session_history_metadata (rating_key);
CREATE INDEX IF NOT EXISTS idx_session_history_metadata_guid ON session_history_metadata (guid);
CREATE INDEX IF NOT EXISTS idx_session_history_metadata_guid_nocase ON session_history_metadata (guid COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS idx_session_history_metadata_live ON session_history_metadata (live);
CREATE INDEX IF NOT EXISTS idx_session_history_metadata_parent_rating_key ON session_history_metadata (parent_rating_key);
CREATE INDEX IF NOT EXISTS idx_session_history_metadata_grandparent_rating_key ON session_history_metadata (grandparent_rating_key);
CREATE INDEX IF NOT EXISTS idx_session_history_media_info_transcode_decision ON session_history_media_info (transcode_decision);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_continued ON sessions_continued (user_id, machine_id, media_type);
