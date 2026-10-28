-- Synthetic data for atuin. Deterministic (no random()): values come from multiplicative hashes of the row number.
-- Scale 1: 120k history rows over ~2 years (nanosecond timestamps, UUIDv7-like ids that sort by time) from 4
-- machines and ~3000 sessions, a Zipf-ish command mix (a few hundred hot commands, a long tail of one-offs),
-- 1% soft-deleted, ~8% run by agents; 40k encrypted record-store rows over 3 hosts x 4 tags.
BEGIN;

CREATE TEMP TABLE cmdtpl(k INTEGER PRIMARY KEY, tpl TEXT, spread INTEGER);
INSERT INTO cmdtpl(k, tpl, spread) VALUES
 (0, 'git status', 1), (1, 'ls -la', 1), (2, 'cd ~/src/proj%d', 40), (3, 'git commit -m "fix %d"', 5000),
 (4, 'cargo build --release', 1), (5, 'cargo test -p atuin-client', 1), (6, 'vim src/file%d.rs', 300), (7, 'git push origin main', 1),
 (8, 'kubectl get pods -n ns%d', 25), (9, 'docker ps -a', 1), (10, 'grep -rn TODO%d .', 2000), (11, 'ssh server%d.example.org', 12),
 (12, 'git log --oneline -n %d', 30), (13, 'make -j8', 1), (14, 'python3 -m pytest tests/test_%d.py', 150), (15, 'npm run dev', 1),
 (16, 'curl -s https://api.example.org/v1/items/%d | jq .', 3000), (17, 'git checkout -b feature/%d', 800), (18, 'rg "fn main" crates/%d', 60), (19, 'htop', 1);

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 120000*(SELECT scale FROM _cfg)),
h AS (SELECT i, (i * 2654435761) % 4294967296 AS h, (i * 40503 + 12345) % 65536 AS g FROM n),
t AS (SELECT i, h, g,
             -- skew: low template ids are much more common
             (SELECT k FROM cmdtpl WHERE k = ((h / 16) % 400) * ((h / 16) % 400) / 8000) AS k,
             1700000000000000000 + i * 520000000000 + (h % 1000) * 1000000 AS ts,
             (i / 40) AS sess
      FROM h)
INSERT INTO history(id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind)
SELECT printf('%012x7%03x%04x%012x', ts / 1000000, h % 4096, 32768 + g % 16384, (h * 7919) % 281474976710656),
       ts,
       CASE WHEN (h / 8) % 50 = 0 THEN -1 ELSE ((h / 64) % 4000) * 1000000 + (h % 997) * 1000 END,
       CASE WHEN (h / 4096) % 100 < 85 THEN 0 WHEN (h / 4096) % 100 < 95 THEN 1 WHEN (h / 4096) % 100 < 98 THEN 130 ELSE 127 END,
       replace((SELECT tpl FROM cmdtpl c WHERE c.k = t.k), '%d', CAST((h / 1048576) % (SELECT spread FROM cmdtpl c WHERE c.k = t.k) AS TEXT)),
       CASE (g / 4) % 6 WHEN 0 THEN '/home/alex' WHEN 1 THEN '/home/alex/src/atuin' WHEN 2 THEN '/home/alex/src/atuin/crates/atuin-client'
                        WHEN 3 THEN '/home/alex/src/proj' || ((h / 256) % 40) WHEN 4 THEN '/tmp' ELSE '/home/alex/src/atuin/ui' END,
       printf('%012x7%03x%04x%012x', (1700000000 + sess * 21000) * 1000, sess % 4096, 32768 + sess % 16384, sess * 2654435761 % 281474976710656),
       CASE (sess * 7) % 10 WHEN 0 THEN 'server1:root' WHEN 1 THEN 'Workstation:alex' WHEN 2 THEN 'workstation:alex'
                            WHEN 3 THEN 'laptop' ELSE 'laptop:alex' END,
       CASE WHEN (h / 32768) % 100 = 0 THEN ts + 86400000000000 END,
       CASE WHEN (sess % 13) = 0 THEN 'claude-code' WHEN (sess % 29) = 0 THEN 'codex' ELSE 'alex' END,
       CASE WHEN (sess % 13) = 0 THEN 'run the test suite' END,
       CASE WHEN i < 30000 THEN NULL WHEN sess % 5 = 0 THEN 'bash' WHEN sess % 7 = 0 THEN 'fish' ELSE 'zsh' END,
       CASE WHEN i < 60000 THEN NULL WHEN (sess % 13) = 0 OR (sess % 29) = 0 THEN 2 ELSE 1 END
FROM t;

-- record store: 3 hosts x 4 tags, idx increments per (host, tag); one interior gap per series
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40000*(SELECT scale FROM _cfg)),
r AS (SELECT i, (i * 2654435761) % 4294967296 AS h,
             CASE i % 3 WHEN 0 THEN '0190c1e2-7a1b-7c3d-8e4f-5a6b7c8d9e0f' WHEN 1 THEN '0190c1e2-7a1b-7c3d-8e4f-111111111111' ELSE '0190c1e2-7a1b-7c3d-8e4f-222222222222' END AS host,
             CASE WHEN (i / 3) % 20 < 16 THEN 'history' WHEN (i / 3) % 20 < 18 THEN 'kv' WHEN (i / 3) % 20 < 19 THEN 'dotfiles-alias' ELSE 'script' END AS tag
      FROM n),
ri AS (SELECT r.*, row_number() OVER (PARTITION BY host, tag ORDER BY i) - 1 AS idx FROM r)
INSERT OR IGNORE INTO store(id, idx, host, tag, timestamp, version, data, cek)
SELECT printf('%08x-%04x-7%03x-%04x-%012x', 1700000000 + i, i % 65536, h % 4096, 32768 + (h / 4096) % 16384, i),
       idx, host, tag, 1700000000000000000 + i * 1500000000000, 'v0',
       CASE WHEN i % 50 = 0 THEN 'v4.local.' || hex(zeroblob(8)) ELSE x'7634' || zeroblob(120 + h % 200) END,
       CASE WHEN i % 50 = 0 THEN '{"wpk":"k' || i || '"}' ELSE zeroblob(96) END
FROM ri WHERE idx <> 500;

INSERT INTO records(id, parent, host, timestamp, tag, version, data, cek)
SELECT id, NULL, host, timestamp, tag, version, data, cek FROM store WHERE idx < 200;
COMMIT;
