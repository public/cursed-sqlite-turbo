-- Synthetic data for Wakapi. Deterministic (no random()): values come from multiplicative hashes of the row number.
-- Times are Unix epoch milliseconds (CustomTime on SQLite). Today starts at 1790985600000 (2026-10-03 00:00 UTC);
-- "now" is 1791043200000 (16:00 UTC). History reaches back 3 years, skewed towards recent days.
-- Shape follows the #974 / #983 reporters (one heavy user with 420-513k heartbeats, ~190 projects, years of WakaTime
-- imports) at a fraction: 205 users at scale 1 (5 heavy, 200 light); 40 % of heartbeats/durations belong to 'alice',
-- 30 % to bob/carol/dave/erin, the rest spread over the light users.
-- Scale 1: 205 users, 200k heartbeats, 100k durations, ~5.9k summaries with ~53k summary_items, ~2.5k leaderboard_items.
-- _cfg.scale multiplies heartbeats, durations and the number of light users (and with them summaries/leaderboard rows).
BEGIN;

CREATE TEMP TABLE _w(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO _w VALUES (0,'api'),(1,'web'),(2,'core'),(3,'cli'),(4,'data'),(5,'infra'),(6,'auth'),(7,'mobile'),
  (8,'docs'),(9,'ml'),(10,'billing'),(11,'search'),(12,'chat'),(13,'game'),(14,'blog'),(15,'shop'),(16,'admin'),
  (17,'sync'),(18,'edge'),(19,'notes');
CREATE TEMP TABLE _w2(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO _w2 VALUES (0,'service'),(1,'app'),(2,'server'),(3,'client'),(4,'utils'),(5,'gateway'),(6,'worker'),
  (7,'dashboard'),(8,'sdk'),(9,'bot'),(10,'engine'),(11,'pipeline'),(12,'frontend'),(13,'backend'),(14,'lib');
-- 300 project names: _w x _w2
CREATE TEMP TABLE _proj(k INTEGER PRIMARY KEY, name TEXT);
INSERT INTO _proj SELECT a.k * 15 + b.k, a.w || '-' || b.w FROM _w a, _w2 b;

CREATE TEMP TABLE _lang(k INTEGER PRIMARY KEY, lang TEXT, ext TEXT);
INSERT INTO _lang VALUES (0,'Go','go'),(1,'TypeScript','ts'),(2,'Python','py'),(3,'Rust','rs'),(4,'Java','java'),
  (5,'JavaScript','js'),(6,'C++','cpp'),(7,'Kotlin','kt'),(8,'PHP','php'),(9,'C#','cs'),(10,'Ruby','rb'),
  (11,'Swift','swift'),(12,'Markdown','md'),(13,'JSON','json'),(14,'YAML','yaml'),(15,'Bash','sh');
CREATE TEMP TABLE _ed(k INTEGER PRIMARY KEY, editor TEXT, plugin TEXT);
INSERT INTO _ed VALUES (0,'VS Code','vscode/1.93.1 vscode-wakatime/24.6.1'),(1,'Neovim','neovim/0.10.1 vim-wakatime/11.2.0'),
  (2,'IntelliJ IDEA','IntelliJ/2024.2 intellij-wakatime/15.0.3'),(3,'GoLand','GoLand/2024.2 intellij-wakatime/15.0.3'),
  (4,'Zed','zed/0.152.3 zed-wakatime/0.1.9'),(5,'PyCharm','PyCharm/2024.2 intellij-wakatime/15.0.3'),
  (6,'Cursor','cursor/0.41.2 vscode-wakatime/24.6.1'),(7,'Emacs','emacs/29.4 wakatime-mode/1.0.2');
CREATE TEMP TABLE _os(k INTEGER PRIMARY KEY, os TEXT, ua TEXT);
INSERT INTO _os VALUES (0,'Linux','linux-6.8.0-45-generic-x86_64'),(1,'Mac','darwin-24.0.0-arm64'),
  (2,'Windows','windows-10.0.22631-x86_64'),(3,'Linux','linux-6.10.10-arch1-1-x86_64');

-- users: 1..5 heavy (alice..erin), the rest light. ~60 % share on the public leaderboard.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 5 + 200*(SELECT scale FROM _cfg))
INSERT INTO users(id, api_key, email, location, start_of_week, password, created_at, last_logged_in_at,
                  share_data_max_days, share_languages, share_projects, share_activity_chart, is_admin, has_data,
                  reports_weekly, public_leaderboard, exclude_unknown_projects, heartbeats_timeout_sec, auth_type)
SELECT CASE i WHEN 1 THEN 'alice' WHEN 2 THEN 'bob' WHEN 3 THEN 'carol' WHEN 4 THEN 'dave' WHEN 5 THEN 'erin'
              ELSE 'dev' || printf('%04d', i) END,
  printf('%08x-%04x-4%03x-a%03x-%012x', (i * 2654435761) % 4294967296, i % 65536, (i * 31) % 4096, (i * 17) % 4096, i * 1000003),
  CASE WHEN i % 3 = 0 THEN NULL ELSE 'user' || i || '@example.org' END,
  CASE i % 5 WHEN 0 THEN 'Europe/Berlin' WHEN 1 THEN 'UTC' WHEN 2 THEN 'America/New_York' WHEN 3 THEN 'Asia/Tokyo' ELSE 'Europe/London' END,
  1, '$2a$10$' || printf('%053x', i), 1696000000000 + i * 86400000, 1790900000000 + (i % 50) * 1000000,
  0, i % 2, i % 3 = 0, i % 4 = 0, i = 1, 1, i % 6 = 0, ((i * 2654435761) % 4294967296) % 10 < 6, 0, 600, 'local'
FROM n;

-- per-user profile: span in days, number of projects, editors/machines
-- idle: days since the user's last activity; ~70 % of light users have stopped using the instance at some point.
CREATE TEMP TABLE _u(u INTEGER PRIMARY KEY, id TEXT, span INTEGER, np INTEGER, ed1 INTEGER, ed2 INTEGER, nm INTEGER, idle INTEGER);
INSERT INTO _u SELECT rowid, id,
  CASE WHEN rowid = 1 THEN 1095 WHEN rowid <= 5 THEN 700 ELSE 60 + (rowid * 7919) % 600 END,
  CASE WHEN rowid = 1 THEN 190 WHEN rowid <= 5 THEN 60 ELSE 3 + rowid % 20 END,
  rowid % 8, (rowid * 3 + 1) % 8, 1 + rowid % 3,
  CASE WHEN rowid <= 5 OR (rowid * 2654435761) % 10 < 3 THEN 0 ELSE (rowid * 104729) % (30 + ((rowid * 7919) % 600) / 2) END
FROM users;

-- heartbeats: 200k * scale, inserted in time order (append-only table). 40 % alice, 30 % bob..erin, 30 % light users.
-- Ages are skewed to recent days (age = span * x^2). alice's/bob's oldest heartbeats are WakaTime imports (origin).
CREATE TEMP TABLE _hb AS
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 200000*(SELECT scale FROM _cfg)),
h AS (SELECT i, (i * 2654435761) % 4294967296 AS h, ((i + 7919) * 2246822519) % 4294967296 AS g FROM n),
a AS (SELECT i, h, g,
        CASE WHEN h % 100 < 40 THEN 1 WHEN h % 100 < 70 THEN 2 + (h / 100) % 4
             ELSE 6 + (h / 100) % (200*(SELECT scale FROM _cfg)) END AS u,
        ((g % 100000) / 100000.0) AS x, (((h / 1000) % 1000) / 1000.0) AS y FROM h)
SELECT a.i, a.h, a.g, _u.u, _u.id AS uid, _u.nm, _u.ed1, _u.ed2,
  _u.idle + CAST((_u.span - _u.idle) * a.x * a.x AS INTEGER) AS age,
  CAST(_u.np * a.y * a.y * a.y AS INTEGER) AS pi
FROM a JOIN _u ON _u.u = a.u;

INSERT INTO heartbeats(user_id, entity, type, category, project, branch, language, is_write, editor, ai_model,
  operating_system, machine, user_agent, time, hash, origin, origin_id, created_at, lines, line_no, cursor_pos,
  line_deletions, line_additions, project_root_count, ai_line_changes, ai_session, ai_input_tokens, ai_output_tokens,
  ai_prompt_length, human_line_changes)
SELECT uid,
  CASE cat WHEN 'browsing' THEN 'github.com' WHEN 'ai coding' THEN 'Claude Code'
       ELSE '/home/' || uid || '/dev/' || proj || '/' || CASE (g / 7) % 4 WHEN 0 THEN 'src' WHEN 1 THEN 'internal/' || w
            WHEN 2 THEN 'pkg/' || w ELSE 'test' END || '/' || w || '_' || ((g / 13) % 40) || '.' || ext END,
  CASE cat WHEN 'browsing' THEN 'domain' WHEN 'ai coding' THEN 'app' ELSE 'file' END,
  cat, proj,
  CASE WHEN (g / 17) % 10 < 6 THEN 'main' WHEN (g / 17) % 10 = 6 THEN 'develop' ELSE 'feature/' || w || '-' || ((g / 19) % 50) END,
  lang, (g / 23) % 7 = 0, editor,
  CASE WHEN cat = 'ai coding' THEN CASE (g / 29) % 3 WHEN 0 THEN 'claude-sonnet-4-5' WHEN 1 THEN 'gpt-5' ELSE 'claude-opus-4-1' END ELSE '' END,
  (SELECT os FROM _os WHERE k = (u + mi) % 4), 'machine-' || u || '-' || mi,
  'wakatime/v1.102.1 (' || (SELECT ua FROM _os WHERE k = (u + mi) % 4) || ') go1.22.5 ' || plugin,
  t, printf('%08x%09x', h, i),
  CASE WHEN (u = 1 AND age > 500) OR (u = 2 AND age > 400) THEN 'wakatime' ELSE '' END,
  CASE WHEN (u = 1 AND age > 500) OR (u = 2 AND age > 400) THEN printf('%08x-%04x-%04x', g, i % 65536, h % 65536) ELSE '' END,
  t + 1000 + (g % 60000),
  40 + (g / 31) % 2000, 1 + (g / 37) % 400, (g / 41) % 80, 0, 0, 1,
  CASE WHEN cat = 'ai coding' THEN (g / 43) % 200 END,
  CASE WHEN cat = 'ai coding' THEN printf('%08x', g) END,
  CASE WHEN cat = 'ai coding' THEN 1000 + (g / 47) % 50000 END,
  CASE WHEN cat = 'ai coding' THEN 200 + (g / 53) % 8000 END,
  CASE WHEN cat = 'ai coding' THEN 20 + (g / 59) % 2000 END,
  NULL
FROM (
  SELECT b.*,
    CASE WHEN (h / 1000000) % 100 < 85 THEN 'coding' WHEN (h / 1000000) % 100 < 90 THEN 'debugging'
         WHEN (h / 1000000) % 100 < 95 THEN 'browsing' ELSE 'ai coding' END AS cat,
    CASE WHEN (g / 3) % 50 = 0 THEN '' ELSE (SELECT name FROM _proj WHERE k = (u * 37 + pi) % 300) END AS proj,
    (SELECT lang FROM _lang WHERE k = lk) AS lang, (SELECT ext FROM _lang WHERE k = lk) AS ext,
    (SELECT w FROM _w WHERE k = (g / 11) % 20) AS w,
    (SELECT editor FROM _ed WHERE k = ek) AS editor, (SELECT plugin FROM _ed WHERE k = ek) AS plugin,
    1790985600000 - age * 86400000 + 25200000 + (g % CASE WHEN age = 0 THEN 32400000 ELSE 50400000 END) AS t
  FROM (SELECT _hb.*, CASE WHEN (g / 5) % 5 = 0 THEN 12 + (g / 101) % 4 ELSE (pi * 7 + u) % 12 END AS lk,
               CASE WHEN (h / 7) % 4 = 0 THEN ed2 ELSE ed1 END AS ek, (g / 9) % nm AS mi FROM _hb) b)
ORDER BY t;

-- durations: 100k * scale, same user/project/time shape (the duration cache that getCached reads).
CREATE TEMP TABLE _du AS
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 100000*(SELECT scale FROM _cfg)),
h AS (SELECT i, ((i + 104729) * 2654435761) % 4294967296 AS h, ((i + 15485863) * 2246822519) % 4294967296 AS g FROM n),
a AS (SELECT i, h, g,
        CASE WHEN h % 100 < 40 THEN 1 WHEN h % 100 < 70 THEN 2 + (h / 100) % 4
             ELSE 6 + (h / 100) % (200*(SELECT scale FROM _cfg)) END AS u,
        ((g % 100000) / 100000.0) AS x, (((h / 1000) % 1000) / 1000.0) AS y FROM h)
SELECT a.i, a.h, a.g, _u.u, _u.id AS uid, _u.nm, _u.ed1,
  _u.idle + CAST((_u.span - _u.idle) * a.x * a.x AS INTEGER) AS age, CAST(_u.np * a.y * a.y * a.y AS INTEGER) AS pi
FROM a JOIN _u ON _u.u = a.u;

INSERT INTO durations(user_id, time, duration, project, language, editor, operating_system, machine, category,
  ai_model, branch, entity, extension, num_heartbeats, group_hash, timeout)
SELECT uid, t, (60 + ((g / 7) % 3600) * (1 + (g / 11) % 3)) * 1000000000, proj, lang,
  (SELECT editor FROM _ed WHERE k = ed1), (SELECT os FROM _os WHERE k = (u + mi) % 4), 'machine-' || u || '-' || mi,
  CASE WHEN (h / 1000000) % 100 < 88 THEN 'coding' WHEN (h / 1000000) % 100 < 94 THEN 'debugging' ELSE 'browsing' END,
  '', CASE WHEN (g / 17) % 10 < 6 THEN 'main' ELSE 'develop' END, '', ext, 1 + (g / 19) % 200,
  printf('%017x', (h * 4096 + i) % 295147905179352825856), 600000000000
FROM (SELECT b.*, CASE WHEN (g / 3) % 50 = 0 THEN '' ELSE (SELECT name FROM _proj WHERE k = (u * 37 + pi) % 300) END AS proj,
             (SELECT lang FROM _lang WHERE k = (pi * 7 + u) % 12) AS lang, (SELECT ext FROM _lang WHERE k = (pi * 7 + u) % 12) AS ext,
             1790985600000 - age * 86400000 + 25200000 + (g % CASE WHEN age = 0 THEN 28800000 ELSE 50400000 END) AS t
      FROM (SELECT _du.*, (g / 9) % nm AS mi FROM _du) b)
ORDER BY t;

-- summaries: one per user per active day (UTC midnight to midnight, as the nightly aggregation writes them),
-- never for today. alice ~85 % of 1095 days, bob..erin ~70 % of 700, light users ~4 % of their span.
WITH RECURSIVE d(day) AS (SELECT 1 UNION ALL SELECT day+1 FROM d WHERE day < 1095)
INSERT INTO summaries(user_id, from_time, to_time, num_heartbeats)
SELECT id, 1790985600000 - day * 86400000, 1790985600000 - (day - 1) * 86400000,
  CASE WHEN hh % 33 = 0 THEN 0 ELSE 1 + hh % 400 END
FROM (SELECT _u.u, _u.id, _u.span, d.day, ((_u.u * 1000003 + d.day) * 2654435761) % 4294967296 AS hh FROM _u, d
      WHERE d.day <= _u.span AND d.day > _u.idle)
WHERE (hh / 7) % 100 < CASE WHEN u = 1 THEN 85 WHEN u <= 5 THEN 70 ELSE 4 END
ORDER BY 2, 1;

-- summary_items: type 0 project (1-4), 1 language (1-4), 2 editor (1-2), 3 os (1), 4 machine (1-2), 8 category (1-2)
CREATE TEMP TABLE _slot(s INTEGER PRIMARY KEY, typ INTEGER, nth INTEGER);
INSERT INTO _slot VALUES (0,0,0),(1,0,1),(2,0,2),(3,0,3),(4,1,0),(5,1,1),(6,1,2),(7,1,3),(8,2,0),(9,2,1),(10,3,0),
  (11,4,0),(12,4,1),(13,8,0),(14,8,1);
INSERT INTO summary_items(summary_id, type, key, total)
SELECT s.id, sl.typ,
  CASE sl.typ
    WHEN 0 THEN (SELECT name FROM _proj WHERE k = (u.u * 37 + CAST(u.np * (((hh / 16) % 1000) / 1000.0) * (((hh / 16) % 1000) / 1000.0) AS INTEGER) + sl.nth) % 300)
    WHEN 1 THEN (SELECT lang FROM _lang WHERE k = (u.u + sl.nth * 5 + (hh / 64) % 3) % 16)
    WHEN 2 THEN (SELECT editor FROM _ed WHERE k = CASE sl.nth WHEN 0 THEN u.ed1 ELSE u.ed2 END)
    WHEN 3 THEN (SELECT os FROM _os WHERE k = u.u % 4)
    WHEN 4 THEN 'machine-' || u.u || '-' || sl.nth
    ELSE CASE sl.nth WHEN 0 THEN 'coding' ELSE 'debugging' END END,
  (300 + (hh / (sl.s + 1)) % 20000) * 1000000000
FROM summaries s JOIN _u u ON u.id = s.user_id
  JOIN (SELECT id AS sid, ((id * 2246822519) % 4294967296) AS hh FROM summaries) hs ON hs.sid = s.id
  JOIN _slot sl ON sl.nth < CASE sl.typ WHEN 0 THEN 1 + hh % 4 WHEN 1 THEN 1 + (hh / 4) % 4 WHEN 2 THEN 1 + (hh / 8) % 2
                                        WHEN 3 THEN 1 WHEN 4 THEN 1 + (hh / 32) % 2 ELSE 1 + (hh / 128) % 2 END
ORDER BY s.id, sl.s;

-- leaderboard_items: public users, intervals 7_days and 30_days, one total row (by NULL) plus up to 6 per-language rows.
INSERT INTO leaderboard_items(user_id, interval, by, total, key, created_at)
SELECT u.id, iv.v, NULL, (3600 + (hh % 200000)) * iv.m * 1000000000, NULL, 1790992800000
FROM (SELECT users.id, ((users.rowid * 2654435761) % 4294967296) AS hh FROM users WHERE public_leaderboard) u,
     (SELECT '7_days' AS v, 1 AS m UNION ALL SELECT '30_days', 4) iv;
INSERT INTO leaderboard_items(user_id, interval, by, total, key, created_at)
SELECT u.id, iv.v, 1, (600 + ((hh / (l.k + 1)) % 90000)) * iv.m * 1000000000, l.lang, 1790992800000
FROM (SELECT users.id, users.rowid AS r, ((users.rowid * 2654435761) % 4294967296) AS hh FROM users WHERE public_leaderboard) u,
     (SELECT '7_days' AS v, 1 AS m UNION ALL SELECT '30_days', 4) iv, _lang l
WHERE (l.k + u.r) % 16 < 2 + u.r % 5;

DROP TABLE _hb; DROP TABLE _du;
COMMIT;
