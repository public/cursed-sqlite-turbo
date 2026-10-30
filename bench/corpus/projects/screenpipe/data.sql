-- Synthetic data for screenpipe (one user's ~/.screenpipe/db.sqlite). Deterministic (no random()): values come from
-- multiplicative hashes of the row number. "Now" is 2026-10-28T18:00:00Z; recording covers the 60 days before it,
-- in working hours (08:00-19:00 UTC), on two monitors. Timestamps are stored the way sqlx encodes DateTime<Utc>:
-- 'YYYY-MM-DDTHH:MM:SS.ffffff+00:00'.
-- Scale 1: 200k frames (sessions of ~40 frames on one app/window; 30 apps with a heavy head: Chrome, Slack, VS Code),
-- full OCR/accessibility text on 95 % of them (frames_fts), ~290k accessibility elements on the frames that carry
-- their own tree (elements_fts), 150k ui_events (ui_events_fts), 24k audio chunks with ~41k transcriptions
-- (audio_transcriptions_fts), 40 speakers, diarization on 20 % of chunks, 80 meetings with 4.8k live transcript
-- segments, 1k video chunks (plus 20 orphans) for the older video-backed 60 % of frames (the rest are event-driven snapshots).
-- _cfg.scale multiplies frames, ui_events, audio and meeting segments; the time range stays 60 days (denser capture).
BEGIN;

CREATE TEMP TABLE _w(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO _w SELECT key, value FROM json_each('["the","to","and","of","a","in","for","is","on","that","with","you","this","it","be","are","as","at","we","from","not","have","or","by","will","new","can","all","your","more","update","review","merge","pull","request","issue","deploy","build","test","release","version","error","fix","commit","branch","main","feature","api","server","client","database","query","index","sqlite","search","timeline","frame","audio","meeting","notes","agenda","roadmap","planning","design","sprint","backlog","customer","invoice","payment","contract","budget","forecast","revenue","quarter","report","dashboard","metrics","latency","throughput","memory","cpu","disk","network","cache","cluster","kubernetes","docker","container","pipeline","workflow","schedule","calendar","event","reminder","message","thread","channel","reply","mention","reaction","approve","comment","draft","document","spreadsheet","slide","presentation","figma","component","layout","button","modal","settings","account","profile","login","password","token","security","privacy","retention","backup","restore","migration","schema","table","column","row","record","batch","job","worker","queue","retry","timeout","warning","log","trace","span","alert","incident","postmortem","oncall","standup","retro","demo","launch","pricing","subscription","trial","enterprise","onboarding","support","ticket","bug","crash","panic","stack","rust","typescript","python","swift","tauri","electron","react","component","hook","state","props","render","style","theme","dark","mode","window","screen","monitor","display","capture","ocr","transcript","speaker","microphone","recording","pause","resume","export","import","sync","cloud","upload","download","storage","quota","limit","usage","billing","plan","team","member","invite","role","permission","owner","admin","project","milestone","deadline","estimate","priority","blocked","done","progress","todo","week","today","tomorrow","yesterday","monday","friday","morning","afternoon","lunch","coffee","call","zoom","teams","slack","notion","linear","github","jira","confluence","gmail","inbox","archive","label","filter","rule","snooze","flight","hotel","booking","receipt","order","shipping","delivery","refund","tax","quarterly","annual","hiring","candidate","interview","offer","feedback","okr","goal","kpi","growth","churn","retention","cohort","funnel","conversion","experiment","variant","rollout","flag","canary","rollback","hotfix","benchmark","profile","flamegraph","allocation","vacuum","checkpoint","wal","fts5","planner","analyze","statistics"]');

-- 4096 OCR-ish lines of 7 words; word choice skewed toward the frequent head of the vocabulary.
CREATE TEMP TABLE _line(k INTEGER PRIMARY KEY, t TEXT);
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 4095),
     j(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM j WHERE j < 6),
     p AS (SELECT i, j, ((i * 7 + j) * 2654435761) % 4294967296 AS h FROM n, j)
INSERT INTO _line SELECT i, group_concat(w, ' ')
FROM (SELECT p.i, p.j, (SELECT w FROM _w WHERE k = ((h % 300) * ((h / 300) % 300)) / 300 % (SELECT count(*) FROM _w)) AS w
      FROM p ORDER BY p.i, p.j)
GROUP BY i;

-- 30 apps with usage weights (lo..hi out of 100) and a kind that drives window names.
CREATE TEMP TABLE _app(k INTEGER PRIMARY KEY, name TEXT, lo INT, hi INT, kind TEXT);
INSERT INTO _app VALUES
 (0,'Google Chrome',0,18,'browser'),(1,'Arc',18,24,'browser'),(2,'Safari',24,27,'browser'),(3,'Slack',27,37,'chat'),
 (4,'Visual Studio Code',37,47,'code'),(5,'Cursor',47,53,'code'),(6,'iTerm2',53,59,'term'),(7,'zoom.us',59,63,'meeting'),
 (8,'Microsoft Teams',63,65,'meeting'),(9,'Notion',65,69,'doc'),(10,'Figma',69,72,'doc'),(11,'Mail',72,74,'mail'),
 (12,'Microsoft Outlook',74,76,'mail'),(13,'Finder',76,78,'other'),(14,'Messages',78,80,'chat'),(15,'Spotify',80,81,'other'),
 (16,'Obsidian',81,83,'doc'),(17,'Linear',83,85,'doc'),(18,'Discord',85,86,'chat'),(19,'WhatsApp',86,87,'chat'),
 (20,'Microsoft Excel',87,89,'office'),(21,'Microsoft Word',89,90,'office'),(22,'Preview',90,91,'other'),
 (23,'Xcode',91,92,'code'),(24,'Postman',92,93,'other'),(25,'1Password',93,94,'other'),(26,'System Settings',94,95,'other'),
 (27,'Calendar',95,96,'other'),(28,'ChatGPT',96,98,'doc'),(29,'Claude',98,100,'doc');

CREATE TEMP TABLE _subj(k INTEGER PRIMARY KEY, s TEXT, slug TEXT);
INSERT INTO _subj SELECT key, value, lower(replace(replace(value, ' ', '-'), '#', '')) FROM json_each('["Q4 roadmap planning","Fix flaky retention test","Weekly metrics review","Customer onboarding flow","Search latency regression","Incident 2291 postmortem","Pricing page redesign","Hiring pipeline","Invoice INV-20431","Board deck draft","API rate limits","Release 2.7 checklist","Design system tokens","Quarterly OKRs","Sprint 44 backlog","Database migration plan","Timeline scrubbing bug","Meeting notes standup","Travel booking Lisbon","Expense report October","Kubernetes upgrade","Security review","Privacy policy update","Support ticket 8812","Churn analysis cohort","Launch announcement","Benchmark results","WAL checkpoint tuning","Audio diarization eval","Enterprise contract"]');

CREATE TEMP TABLE _win(app INT, v INT, name TEXT, url TEXT, doc TEXT, PRIMARY KEY(app, v));
WITH RECURSIVE v(v) AS (SELECT 0 UNION ALL SELECT v+1 FROM v WHERE v < 11)
INSERT INTO _win
SELECT a.k, v.v,
  CASE a.kind
    WHEN 'browser' THEN s.s || ' - ' || CASE v.v % 6 WHEN 0 THEN 'GitHub' WHEN 1 THEN 'Google Docs' WHEN 2 THEN 'Gmail'
         WHEN 3 THEN 'Linear' WHEN 4 THEN 'Stack Overflow' ELSE 'YouTube' END
    WHEN 'chat' THEN CASE WHEN a.name = 'Slack' THEN '#' || CASE v.v % 6 WHEN 0 THEN 'eng-platform' WHEN 1 THEN 'general'
         WHEN 2 THEN 'incidents' WHEN 3 THEN 'design' WHEN 4 THEN 'sales' ELSE 'random' END || ' (Channel) - Acme - Slack'
         ELSE CASE v.v % 4 WHEN 0 THEN 'Maria Lopez' WHEN 1 THEN 'Dev team' WHEN 2 THEN 'Sam Chen' ELSE 'Family' END END
    WHEN 'code' THEN CASE v.v % 6 WHEN 0 THEN 'search.rs' WHEN 1 THEN 'frames.rs' WHEN 2 THEN 'activity_summary.rs'
         WHEN 3 THEN 'page.tsx' WHEN 4 THEN 'Cargo.toml' ELSE 'README.md' END || ' — ' ||
         CASE v.v % 3 WHEN 0 THEN 'screenpipe' WHEN 1 THEN 'web-app' ELSE 'infra' END
    WHEN 'term' THEN 'demo@mbp: ~/code/' || CASE v.v % 3 WHEN 0 THEN 'screenpipe' WHEN 1 THEN 'web-app' ELSE 'infra' END || ' — zsh'
    WHEN 'meeting' THEN CASE v.v % 3 WHEN 0 THEN 'Zoom Meeting' WHEN 1 THEN s.s ELSE 'Meeting | Microsoft Teams' END
    WHEN 'mail' THEN 'Inbox (' || (v.v * 37 % 900) || ' messages) — ' || s.s
    WHEN 'office' THEN s.s || CASE WHEN a.name = 'Microsoft Excel' THEN '.xlsx' ELSE '.docx' END
    ELSE s.s || ' — ' || a.name END,
  CASE WHEN a.kind = 'browser' THEN 'https://' || CASE v.v % 6 WHEN 0 THEN 'github.com/acme/' || s.slug
       WHEN 1 THEN 'docs.google.com/document/d/1x' || (v.v * 7919 + a.k) WHEN 2 THEN 'mail.google.com/mail/u/0/#inbox'
       WHEN 3 THEN 'linear.app/acme/issue/ENG-' || (1000 + v.v * 37) WHEN 4 THEN 'stackoverflow.com/questions/' || (7000000 + v.v * 13)
       ELSE 'www.youtube.com/watch?v=dQw' || v.v END END,
  CASE WHEN a.kind = 'code' THEN '/Users/demo/code/' || CASE v.v % 3 WHEN 0 THEN 'screenpipe' WHEN 1 THEN 'web-app' ELSE 'infra' END
         || '/src/' || CASE v.v % 6 WHEN 0 THEN 'search.rs' WHEN 1 THEN 'frames.rs' WHEN 2 THEN 'activity_summary.rs'
         WHEN 3 THEN 'page.tsx' WHEN 4 THEN 'Cargo.toml' ELSE 'README.md' END
       WHEN a.kind = 'office' THEN '/Users/demo/Documents/' || s.s || CASE WHEN a.name = 'Microsoft Excel' THEN '.xlsx' ELSE '.docx' END END
FROM _app a, v, _subj s WHERE s.k = (a.k * 7 + v.v * 11) % 30;

-- Per-frame plan: i -> day, time of day, session (40 frames), app, window, device.
CREATE TEMP TABLE _fr(i INTEGER PRIMARY KEY, h INT, ts TEXT, app INT, v INT, dev INT);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 100000*(SELECT scale FROM _cfg)),
q AS (SELECT i, (i * 2654435761) % 4294967296 AS h, ((i - 1) / 40) AS s,
             (i - 1) * 60 / (100000*(SELECT scale FROM _cfg)) AS day,
             ((i - 1) * 60) % (100000*(SELECT scale FROM _cfg)) * 1.0 / (100000*(SELECT scale FROM _cfg)) AS p FROM n),
r AS (SELECT i, h, day, p, (s * 2654435761) % 4294967296 AS sh FROM q)
INSERT INTO _fr
SELECT i, h,
  strftime('%Y-%m-%dT%H:%M:%f', julianday('2026-08-29T00:00:00') + day + (8 + p * 11) / 24.0) || '000+00:00',
  (SELECT k FROM _app WHERE (sh % 100) >= lo AND (sh % 100) < hi),
  ((sh / 128) % 4) * ((sh / 512) % 4) % 12,
  CASE WHEN (h / 8) % 10 < 7 THEN 0 ELSE 1 END
FROM r;

-- video chunks: the oldest 60 % of frames are video-backed, one chunk per device per 120 frames.
WITH RECURSIVE n(c) AS (SELECT 1 UNION ALL SELECT c+1 FROM n WHERE c < (60000*(SELECT scale FROM _cfg)) / 120 * 2 + 20)
INSERT INTO video_chunks(id, file_path, device_name, fps, machine_id, cloud_blob_id)
SELECT c,
  CASE WHEN c % 20 = 0 THEN 'cloud://archive/' ELSE '/Users/demo/.screenpipe/data/' END || 'monitor_' || (2 - c % 2) || '_' ||
    replace(replace(substr((SELECT ts FROM _fr WHERE i = ((c - 1) / 2) * 120 + 1), 1, 19), 'T', '_'), ':', '-') || '.mp4',
  'monitor_' || (2 - c % 2), 0.5, NULL, CASE WHEN c % 20 = 0 THEN 'blob-' || c END
FROM n;

INSERT INTO frames(id, video_chunk_id, offset_index, timestamp, name, app_name, window_name, focused, browser_url, device_name,
                   machine_id, snapshot_path, accessibility_text, content_hash, capture_trigger, text_source, full_text,
                   elements_ref_frame_id, document_path)
SELECT f.i,
  CASE WHEN f.i <= 60000*(SELECT scale FROM _cfg) THEN ((f.i - 1) / 120) * 2 + 2 - (f.dev = 0) END,
  CASE WHEN f.i <= 60000*(SELECT scale FROM _cfg) THEN (f.i - 1) % 120 ELSE 0 END,
  f.ts,
  CASE WHEN f.i <= 60000*(SELECT scale FROM _cfg) THEN '/Users/demo/.screenpipe/data/monitor_' || (f.dev + 1) || '.mp4' END,
  CASE WHEN (f.h / 1024) % 100 < 8 THEN CASE WHEN (f.h / 1024) % 2 = 0 THEN NULL ELSE '' END ELSE a.name END,
  CASE WHEN (f.h / 1024) % 100 < 8 THEN NULL ELSE w.name END,
  CASE WHEN f.dev = 0 THEN 1 ELSE (f.h / 16) % 4 = 0 END,
  CASE WHEN (f.h / 1024) % 100 < 8 THEN NULL ELSE w.url END,
  'monitor_' || (f.dev + 1),
  CASE WHEN f.i < 30000*(SELECT scale FROM _cfg) AND (f.h / 64) % 100 < 6 THEN 'b7e1c2a4-mbp-2024' END,
  CASE WHEN f.i > 60000*(SELECT scale FROM _cfg) THEN '/Users/demo/.screenpipe/data/snapshots/' || substr(f.ts, 1, 10) || '/' ||
       f.i || '_m' || (f.dev + 1) || '.jpg' END,
  CASE WHEN a.kind IN ('browser','chat','code','doc') AND (f.h / 32) % 100 < 70 THEN substr(l1.t, 1, 60) END,
  f.h,
  CASE (f.h / 4096) % 6 WHEN 0 THEN 'app_switch' WHEN 1 THEN 'window_focus' WHEN 2 THEN 'click' WHEN 3 THEN 'typing_pause'
       WHEN 4 THEN 'visual_change' ELSE 'idle' END,
  CASE WHEN a.kind IN ('browser','chat','code','doc') AND (f.h / 32) % 100 < 70 THEN 'accessibility' ELSE 'ocr' END,
  CASE WHEN (f.h / 2048) % 100 < 5 THEN NULL ELSE COALESCE(w.name, a.name) || ' ' || l1.t || ' ' || l2.t || CASE WHEN f.h % 2 = 0 THEN ' ' || l3.t ELSE '' END END,
  -- element dedup: a third of accessibility frames reuse the tree of the session's first frame
  CASE WHEN a.kind IN ('browser','chat','code','doc') AND (f.h / 32) % 100 < 70 AND (f.h / 16384) % 3 <> 0
            AND (f.i - 1) % 40 <> 0 THEN f.i - ((f.i - 1) % 40) END,
  CASE WHEN (f.h / 1024) % 100 >= 8 THEN w.doc END
FROM _fr f JOIN _app a ON a.k = f.app JOIN _win w ON w.app = f.app AND w.v = f.v
JOIN _line l1 ON l1.k = f.h % 4096 JOIN _line l2 ON l2.k = (f.h / 4096) % 4096 JOIN _line l3 ON l3.k = (f.h / 65536) % 4096
ORDER BY f.i;

-- accessibility elements: 1 root + 4 text nodes for every accessibility frame that owns its tree.
CREATE TEMP TABLE _ef AS SELECT ROW_NUMBER() OVER (ORDER BY id) AS rn, id, content_hash AS h FROM frames
  WHERE text_source = 'accessibility' AND elements_ref_frame_id IS NULL;
WITH RECURSIVE j(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM j WHERE j < 3)
INSERT INTO elements(id, frame_id, source, role, text, parent_id, depth, left_bound, top_bound, width_bound, height_bound,
                     confidence, sort_order, on_screen)
SELECT e.rn * 4 + j.j, e.id, 'accessibility',
  CASE j.j WHEN 0 THEN 'AXWindow' WHEN 1 THEN 'AXStaticText' WHEN 2 THEN 'AXStaticText'
           WHEN 3 THEN CASE WHEN (e.h / 8) % 3 = 0 THEN 'AXTextArea' WHEN (e.h / 8) % 3 = 1 THEN 'AXTextField' ELSE 'AXLink' END
           ELSE 'AXButton' END,
  CASE j.j WHEN 0 THEN NULL
           WHEN 1 THEN (SELECT t FROM _line WHERE k = (e.h / 3) % 4096) || ' ' || (SELECT t FROM _line WHERE k = (e.h / 5) % 4096)
           WHEN 2 THEN CASE WHEN (e.h / 64) % 5 = 0 THEN 'https://github.com/acme/' || (e.h % 997) ELSE
                       (SELECT t FROM _line WHERE k = (e.h / 7) % 4096) END
           WHEN 3 THEN (SELECT t FROM _line WHERE k = (e.h / 11) % 4096) || ' ' ||
                       CASE WHEN (e.h / 128) % 2 = 0 THEN (SELECT t FROM _line WHERE k = (e.h / 13) % 4096) ELSE '' END
           ELSE CASE (e.h / 256) % 4 WHEN 0 THEN 'Send' WHEN 1 THEN 'Cancel' WHEN 2 THEN 'Share' ELSE 'Reply in thread' END END,
  CASE WHEN j.j = 0 THEN NULL ELSE e.rn * 4 END,
  CASE WHEN j.j = 0 THEN 0 ELSE 1 END,
  0.05 * j.j, 0.1 + 0.15 * j.j, 0.8, 0.05, NULL, j.j,
  CASE WHEN (e.h / 1024 + j.j) % 20 = 0 THEN NULL WHEN (e.h / 1024 + j.j) % 7 = 0 THEN 0 ELSE 1 END
FROM _ef e, j ORDER BY e.rn, j.j;

-- ui_events: 150k, each tied to a frame's moment (half carry frame_id); app/window come from the session plan, so
-- they also cover the 8 % of frames whose capture lost the app name.
WITH RECURSIVE n(j) AS (SELECT 1 UNION ALL SELECT j+1 FROM n WHERE j < 50000*(SELECT scale FROM _cfg)),
q AS (SELECT j, (j * 2246822519) % 4294967296 AS h, j * 2 AS fi FROM n)
INSERT INTO ui_events(id, timestamp, session_id, relative_ms, event_type, x, y, text_content, text_length, app_name,
                      window_title, browser_url, element_role, element_name, frame_id, machine_id)
SELECT q.j,
  strftime('%Y-%m-%dT%H:%M:%f', julianday(substr(f.ts, 1, 23)) - ((q.h % 9000) / 1000.0) / 86400.0) || '000+00:00',
  'sess-' || (f.i / 400), q.h % 60000,
  CASE WHEN (q.h / 16) % 100 < 35 THEN 'click' WHEN (q.h / 16) % 100 < 50 THEN 'text' WHEN (q.h / 16) % 100 < 65 THEN 'scroll'
       WHEN (q.h / 16) % 100 < 72 THEN 'app_switch' WHEN (q.h / 16) % 100 < 82 THEN 'window_focus'
       WHEN (q.h / 16) % 100 < 85 THEN 'clipboard' WHEN (q.h / 16) % 100 < 93 THEN 'key' ELSE 'move' END,
  (q.h / 7) % 2560, (q.h / 11) % 1440,
  CASE WHEN (q.h / 16) % 100 BETWEEN 35 AND 49 THEN (SELECT t FROM _line WHERE k = (q.h / 3) % 4096)
       WHEN (q.h / 16) % 100 BETWEEN 82 AND 84 THEN 'https://linear.app/acme/issue/ENG-' || (q.h % 4000) END,
  CASE WHEN (q.h / 16) % 100 BETWEEN 35 AND 49 THEN length((SELECT t FROM _line WHERE k = (q.h / 3) % 4096)) END,
  a.name, w.name, w.url,
  CASE WHEN (q.h / 16) % 100 < 35 THEN 'AXButton' WHEN (q.h / 16) % 100 < 50 THEN 'AXTextArea' END,
  CASE WHEN (q.h / 16) % 100 < 35 THEN CASE (q.h / 5) % 4 WHEN 0 THEN 'Send' WHEN 1 THEN 'Merge pull request'
       WHEN 2 THEN 'Reply' ELSE 'New message' END END,
  CASE WHEN (q.h / 2) % 2 = 0 THEN f.i END,
  NULL
FROM q JOIN _fr f ON f.i = MIN(q.fi, 100000*(SELECT scale FROM _cfg)) JOIN _app a ON a.k = f.app JOIN _win w ON w.app = f.app AND w.v = f.v
ORDER BY q.j;

-- speakers: 1 = the user, 2-10 named colleagues, 11-37 unnamed clusters, 38-40 hallucinations.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40)
INSERT INTO speakers(id, name, metadata, hallucination, embedding_count)
SELECT i,
  CASE WHEN i = 1 THEN 'Alex' WHEN i <= 10 THEN json_extract('["Maria Lopez","Sam Chen","Priya Patel","Jonas Berg","Ava Kim","Leo Martin","Nora Weiss","Omar Haddad","Ivy Brooks"]', '$[' || (i - 2) || ']')
       WHEN i % 2 = 0 THEN '' ELSE NULL END,
  CASE WHEN i % 3 = 0 THEN json_object('source', 'diarization', 'cluster', i) ELSE '' END,
  i >= 38, 3 + i % 17
FROM n;

-- audio: 24k 30-second chunks over the same working hours, alternating mic (input) and system output.
WITH RECURSIVE n(c) AS (SELECT 1 UNION ALL SELECT c+1 FROM n WHERE c < 24000*(SELECT scale FROM _cfg)),
q AS (SELECT c, (c * 2654435761) % 4294967296 AS h,
             (c - 1) * 60 / (24000*(SELECT scale FROM _cfg)) AS day,
             ((c - 1) * 60) % (24000*(SELECT scale FROM _cfg)) * 1.0 / (24000*(SELECT scale FROM _cfg)) AS p FROM n)
INSERT INTO audio_chunks(id, file_path, timestamp, machine_id, transcription_status, transcription_attempts)
SELECT c,
  CASE WHEN c % 33 = 0 THEN 'cloud://archive/' ELSE '/Users/demo/.screenpipe/data/' END ||
    CASE WHEN c % 2 = 1 THEN 'MacBook Pro Microphone (input)' ELSE 'MacBook Pro Speakers (output)' END || '_' ||
    replace(strftime('%Y-%m-%d_%H-%M-%S', julianday('2026-08-29T00:00:00') + day + (9 + p * 9) / 24.0), ':', '-') || '.mp4',
  strftime('%Y-%m-%dT%H:%M:%f', julianday('2026-08-29T00:00:00') + day + (9 + p * 9) / 24.0) || '000+00:00',
  CASE WHEN c < 6000*(SELECT scale FROM _cfg) AND (h / 64) % 100 < 6 THEN 'b7e1c2a4-mbp-2024' END,
  CASE WHEN (h / 16) % 100 < 3 THEN 'pending' WHEN (h / 16) % 100 < 13 THEN 'silent' WHEN (h / 16) % 100 < 14 THEN 'failed'
       ELSE 'transcribed' END,
  CASE WHEN (h / 16) % 100 < 3 THEN (h / 4096) % 4 WHEN (h / 16) % 100 < 14 THEN 1 ELSE 1 END
FROM q;

-- 1-3 transcription segments per transcribed chunk.
WITH RECURSIVE k(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM k WHERE k < 2)
INSERT OR IGNORE INTO audio_transcriptions(audio_chunk_id, offset_index, timestamp, transcription, device, is_input_device, speaker_id,
                                 transcription_engine, start_time, end_time, text_length)
SELECT ac.id, k.k,
  strftime('%Y-%m-%dT%H:%M:%f', julianday(substr(ac.timestamp, 1, 23)) + k.k * 10 / 86400.0) || '000+00:00',
  tx, CASE WHEN ac.id % 2 = 1 THEN 'MacBook Pro Microphone (input)' ELSE 'MacBook Pro Speakers (output)' END,
  ac.id % 2 = 1,
  CASE WHEN ac.id % 2 = 1 THEN CASE WHEN (h / 8) % 10 < 8 THEN 1 ELSE 11 + (h / 32) % 5 END
       WHEN (h / 8) % 50 = 0 THEN 38 + (h / 32) % 3
       ELSE 2 + ((((h / 32) % 36) * ((h / 2048) % 36)) / 36) END,
  CASE WHEN (h / 8192) % 10 = 0 THEN 'live' WHEN (h / 8192) % 10 < 4 THEN 'screenpipe-cloud' ELSE 'WhisperLargeV3Turbo' END,
  k.k * 10.0, k.k * 10.0 + 4.5 + (h % 50) / 10.0, length(tx)
FROM (SELECT ac.*, k.k, ((ac.id * 3 + k.k) * 2654435761) % 4294967296 AS h,
             CASE WHEN ((ac.id * 3 + k.k) * 2654435761) % 4294967296 / 65536 % 9 = 0 THEN 'yeah'
                  ELSE (SELECT t FROM _line WHERE k = ((ac.id * 3 + k.k) * 2654435761) % 4294967296 % 4096) || ' ' ||
                       (SELECT t FROM _line WHERE k = ((ac.id * 3 + k.k) * 2654435761) % 4294967296 / 4096 % 4096) END AS tx
      FROM audio_chunks ac, k WHERE ac.transcription_status = 'transcribed' AND k.k <= (ac.id * 7) % 3) ac
JOIN k ON k.k = ac.k
ORDER BY ac.id, k.k;

-- diarization on 20 % of transcribed chunks, segments aligned with the first two transcription segments.
INSERT INTO diarization_runs(id, audio_chunk_id, mode, provider, model, status, created_at)
SELECT id, id, CASE WHEN id % 3 = 0 THEN 'live' ELSE 'background' END, CASE WHEN id % 2 = 0 THEN 'pyannote' ELSE 'deepgram' END,
  'v3.1', 'completed', datetime(substr(timestamp, 1, 19), '+40 seconds')
FROM audio_chunks WHERE transcription_status = 'transcribed' AND id % 5 = 0;
INSERT INTO diarization_segments(diarization_run_id, audio_chunk_id, provider_speaker_label, speaker_id, source, start_time,
                                 end_time, confidence)
SELECT dr.id, at.audio_chunk_id, 'SPEAKER_0' || (at.speaker_id % 4), at.speaker_id, 'provider', at.start_time + 0.01,
  at.end_time - 0.01, 0.6 + (at.id % 40) / 100.0
FROM diarization_runs dr JOIN audio_transcriptions at ON at.audio_chunk_id = dr.audio_chunk_id AND at.offset_index < 2;

-- meetings and live transcript segments
WITH RECURSIVE n(m) AS (SELECT 1 UNION ALL SELECT m+1 FROM n WHERE m < 80)
INSERT INTO meetings(id, meeting_start, meeting_end, meeting_app, title, attendees, detection_source)
SELECT m, strftime('%Y-%m-%dT%H:%M:%fZ', julianday('2026-08-29T00:00:00') + (m - 1) * 60 / 80 + (10 + (m % 6)) / 24.0),
  strftime('%Y-%m-%dT%H:%M:%fZ', julianday('2026-08-29T00:00:00') + (m - 1) * 60 / 80 + (10 + (m % 6)) / 24.0 + 45 / 1440.0),
  CASE m % 3 WHEN 0 THEN 'zoom.us' WHEN 1 THEN 'Microsoft Teams' ELSE 'Google Meet' END,
  (SELECT s FROM _subj WHERE k = m % 30), 'Alex, Maria Lopez, Sam Chen', 'app'
FROM n;
WITH RECURSIVE n(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM n WHERE j < 4800*(SELECT scale FROM _cfg) - 1)
INSERT INTO meeting_transcript_segments(meeting_id, provider, model, item_id, device_name, device_type, speaker_name, transcript,
                                        captured_at, speaker_id, stream_id)
SELECT 1 + j % 80, 'screenpipe-cloud', 'nova-3', 'item-' || j,
  CASE WHEN j % 2 = 0 THEN 'MacBook Pro Microphone' ELSE 'MacBook Pro Speakers' END,
  CASE WHEN j % 2 = 0 THEN 'input' ELSE 'output' END,
  CASE WHEN j % 2 = 0 THEN 'Alex' ELSE 'Maria Lopez' END,
  CASE WHEN j % 17 = 0 THEN ' ' ELSE (SELECT t FROM _line WHERE k = (j * 2654435761) % 4294967296 % 4096) END,
  strftime('%Y-%m-%dT%H:%M:%fZ', julianday(m.meeting_start) + (j / 80) * 2700.0 / (60*(SELECT scale FROM _cfg)) / 86400.0),
  CASE WHEN j % 2 = 0 THEN 1 ELSE 2 END, 'live'
FROM n JOIN meetings m ON m.id = 1 + n.j % 80;

-- tags: 2 % of frames and 3 % of audio chunks are tagged
INSERT INTO tags(id, name) SELECT key + 1, value FROM json_each('["work","personal","meeting","deep-work","bug","customer","idea","important","follow-up","private"]');
INSERT INTO vision_tags(vision_id, tag_id) SELECT id, 1 + (content_hash / 50) % 10 FROM frames WHERE content_hash % 50 = 0;
INSERT OR IGNORE INTO vision_tags(vision_id, tag_id) SELECT id, 1 FROM frames WHERE content_hash % 150 = 0;
INSERT INTO audio_tags(audio_chunk_id, tag_id) SELECT id, 1 + id % 10 FROM audio_chunks WHERE (id * 2654435761) % 4294967296 % 33 = 1;

WITH RECURSIVE n(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM n WHERE j < 149)
INSERT INTO display_layout(timestamp, reason, layout_json)
SELECT strftime('%Y-%m-%dT%H:%M:%fZ', julianday('2026-08-29T08:00:00') + j * 0.4), CASE WHEN j % 5 = 0 THEN 'startup' ELSE 'change' END,
  json_array(json_object('id', 1, 'stable_id', 'built-in-retina', 'name', 'Built-in Retina Display', 'x', 0, 'y', 0, 'width', 1512,
             'height', 982, 'is_primary', json('true')),
             json_object('id', 2, 'stable_id', 'dell-u2723qe', 'name', 'DELL U2723QE', 'x', 1512, 'y', -300, 'width', 2560,
             'height', 1440, 'is_primary', json('false')))
FROM n WHERE j % 3 <> 2 OR j < 100;

DROP TABLE _w; DROP TABLE _line; DROP TABLE _app; DROP TABLE _subj; DROP TABLE _win; DROP TABLE _fr; DROP TABLE _ef;
COMMIT;
