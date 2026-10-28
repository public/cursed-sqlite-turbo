-- Synthetic data for synapse. Deterministic (no random()): values come from multiplicative hashes of row numbers.
-- _cfg.scale multiplies users, rooms and messages. Scale 1: 2000 users, 300 rooms (20 of them big), ~10k
-- memberships, 30k timeline events with relations (reactions, threads, edits), 2 push actions per message,
-- receipts, push summaries, FTS4 search rows, the user directory, state groups and sliding-sync tables.
BEGIN;

CREATE TEMP TABLE p(nu, nr, nm);
INSERT INTO p SELECT 2000*scale, 300*scale, 30000*scale FROM _cfg;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT nu FROM p))
INSERT INTO users(name, password_hash, creation_ts, admin, is_guest, user_type, deactivated, shadow_banned, approved, locked, suspended)
SELECT '@user' || i || ':example.org', 'x', 1600000000 + i*3600, i = 1, 0, CASE WHEN i % 97 = 0 THEN 'bot' END,
       i % 151 = 0, 0, 1, i % 83 = 0, 0
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT nr FROM p))
INSERT INTO rooms(room_id, is_public, creator, room_version, has_auth_chain_index)
SELECT '!room' || i || ':example.org', i % 3 = 0, '@user' || ((i * 37) % (SELECT nu FROM p) + 1) || ':example.org',
       CASE WHEN i % 4 = 0 THEN '11' ELSE '10' END, 1
FROM n;

-- memberships: every user is in 5 rooms; the first 20 rooms are big
CREATE TEMP TABLE pairs(pid INTEGER PRIMARY KEY, u INTEGER, r INTEGER, membership TEXT, ri INTEGER);
INSERT INTO pairs(u, r, membership)
SELECT u, r, CASE WHEN h % 100 < 88 THEN 'join' WHEN h % 100 < 93 THEN 'leave' WHEN h % 100 < 97 THEN 'invite' ELSE 'ban' END
FROM (SELECT DISTINCT u.i AS u,
             CASE WHEN k.k < 3 THEN ((u.i * 7 + k.k * 131) % (SELECT nr FROM p)) + 1 ELSE ((u.i * 13 + k.k) % 20) + 1 END AS r,
             ((u.i * 2654435761 + k.k * 40503) % 4294967296) / 256 AS h
      FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT nu FROM p)) SELECT i FROM n) u,
           (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4) k)
GROUP BY u, r ORDER BY r, u;
UPDATE pairs SET ri = x.rn FROM (SELECT pid, row_number() OVER (PARTITION BY r ORDER BY pid) AS rn FROM pairs) x WHERE x.pid = pairs.pid;
CREATE INDEX pairs_r ON pairs(r, ri);
CREATE TEMP TABLE rcount AS SELECT r, count(*) AS cnt FROM pairs GROUP BY r;
CREATE INDEX rcount_r ON rcount(r);

-- the event stream, in order: room state, then memberships, then the timeline
CREATE TEMP TABLE ev(so INTEGER PRIMARY KEY, r INTEGER, u INTEGER, type TEXT, state_key TEXT, kind TEXT, h INTEGER, pid INTEGER);
INSERT INTO ev(r, u, type, state_key, kind, h)
SELECT r.i, (r.i * 37) % (SELECT nu FROM p) + 1, t.type, '', 'state', (r.i * 2654435761 + t.k) % 4294967296
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT nr FROM p)) SELECT i FROM n) r,
     (SELECT column1 AS k, column2 AS type FROM (VALUES (0,'m.room.create'),(1,'m.room.name'),(2,'m.room.topic'),(3,'m.room.join_rules'),(4,'m.room.history_visibility'),(5,'m.room.power_levels'),(6,'m.room.encryption'))) t
WHERE t.k < 6 OR r.i % 2 = 0
ORDER BY r.i, t.k;
INSERT INTO ev(r, u, type, state_key, kind, h, pid)
SELECT r, u, 'm.room.member', '@user' || u || ':example.org', 'member', (pid * 2654435761) % 4294967296, pid FROM pairs ORDER BY (pid * 7919) % 100003, pid;
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT nm FROM p)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n),
mr AS (SELECT i, h, CASE WHEN (h / 8) % 10 < 6 THEN (h / 64) % 20 + 1 ELSE (h / 64) % (SELECT nr FROM p) + 1 END AS r FROM m)
INSERT INTO ev(r, u, type, state_key, kind, h)
SELECT mr.r, pr.u,
       CASE WHEN (mr.h / 4096) % 100 < 10 THEN 'm.reaction' ELSE 'm.room.message' END, NULL, 'msg', mr.h
FROM mr JOIN rcount rc ON rc.r = mr.r JOIN pairs pr ON pr.r = mr.r AND pr.ri = (mr.h / 1024) % rc.cnt + 1
ORDER BY mr.i;

-- per-room position of each timeline event (for relations and receipts)
CREATE TEMP TABLE rmsg(r INTEGER, rn INTEGER, so INTEGER, PRIMARY KEY (r, rn));
INSERT INTO rmsg SELECT r, row_number() OVER (PARTITION BY r ORDER BY so), so FROM ev WHERE kind = 'msg';
CREATE TEMP TABLE rmcount AS SELECT r, count(*) AS cnt FROM rmsg GROUP BY r;

INSERT INTO events(stream_ordering, topological_ordering, event_id, type, room_id, content, unrecognized_keys, processed, outlier,
                   depth, origin_server_ts, received_ts, sender, contains_url, instance_name, state_key, rejection_reason)
SELECT so, row_number() OVER (PARTITION BY r ORDER BY so), '$ev' || so || '_' || printf('%08x', h), type, '!room' || r || ':example.org',
       NULL, NULL, 1,
       CASE WHEN kind = 'member' AND (h / 16) % 100 < 30 AND (SELECT membership FROM pairs WHERE pairs.pid = ev.pid) = 'invite' THEN 1
            WHEN kind = 'msg' AND (h / 65536) % 200 = 0 THEN 1 ELSE 0 END,
       row_number() OVER (PARTITION BY r ORDER BY so),
       1700000000000 + so * 25000, 1700000000000 + so * 25000 + h % 900,
       '@user' || u || ':example.org', kind = 'msg' AND (h / 512) % 20 = 0, CASE WHEN so % 3 = 0 THEN 'worker1' ELSE 'master' END,
       state_key, NULL
FROM ev;

INSERT INTO event_json(event_id, room_id, internal_metadata, json, format_version)
SELECT e.event_id, e.room_id, CASE WHEN e.outlier THEN '{"outlier":true}' ELSE '{}' END,
       json_object('type', e.type, 'room_id', e.room_id, 'sender', e.sender, 'origin_server_ts', e.origin_server_ts,
                   'depth', e.depth, 'state_key', e.state_key,
                   'content', CASE e.type WHEN 'm.room.message' THEN json_object('msgtype', 'm.text', 'body', 'message ' || e.stream_ordering)
                                          WHEN 'm.room.member' THEN json_object('membership', 'join', 'displayname', 'User')
                                          ELSE json_object() END,
                   'prev_events', json_array('$ev' || (e.stream_ordering - 1)), 'auth_events', json_array()),
       3
FROM events e;

-- rejected events and redactions
INSERT INTO rejections(event_id, reason, last_check)
SELECT event_id, 'auth_error', '2024-01-01' FROM events WHERE (stream_ordering * 40503) % 500 = 7;
INSERT INTO redactions(event_id, redacts, have_censored, received_ts, recheck)
SELECT '$redact' || e.stream_ordering, e.event_id, e.stream_ordering % 2, e.received_ts + 60000, e.stream_ordering % 5 = 0
FROM events e WHERE e.type = 'm.room.message' AND (e.stream_ordering * 7919) % 150 = 3;

-- relations: reactions annotate a recent message, ~6% of messages are thread replies, ~2% are edits
CREATE TEMP TABLE rel AS
SELECT ev.so, ev.r, rm.rn, ev.type, ev.h,
       CASE WHEN ev.type = 'm.reaction' THEN 'm.annotation'
            WHEN (ev.h / 131072) % 100 < 6 THEN 'm.thread'
            WHEN (ev.h / 131072) % 100 < 8 THEN 'm.replace' END AS relation_type,
       CASE WHEN ev.type = 'm.reaction' THEN rm.rn - 1 - (ev.h / 32) % 4
            WHEN (ev.h / 131072) % 100 < 6 THEN rm.rn - 1 - (ev.h / 32) % 3 - ((rm.rn / 40) % 3)
            ELSE rm.rn - 1 END AS target_rn
FROM ev JOIN rmsg rm ON rm.so = ev.so;
-- thread replies hang off a few roots per room: round the target down to a multiple of 40
UPDATE rel SET target_rn = (target_rn / 40) * 40 + 1 WHERE relation_type = 'm.thread';
INSERT INTO event_relations(event_id, relates_to_id, relation_type, aggregation_key)
SELECT e.event_id, t.event_id, rel.relation_type, CASE rel.relation_type WHEN 'm.annotation' THEN CASE rel.h % 3 WHEN 0 THEN '👍' WHEN 1 THEN '🎉' ELSE '❤️' END END
FROM rel JOIN rmsg tm ON tm.r = rel.r AND tm.rn = rel.target_rn
JOIN events e ON e.stream_ordering = rel.so JOIN events t ON t.stream_ordering = tm.so
WHERE rel.relation_type IS NOT NULL AND rel.target_rn >= 1 AND tm.so <> rel.so;

-- state
INSERT INTO state_events(event_id, room_id, type, state_key, prev_state)
SELECT event_id, room_id, type, state_key, NULL FROM events WHERE state_key IS NOT NULL;
INSERT INTO room_memberships(event_id, user_id, sender, room_id, membership, forgotten, display_name, avatar_url, event_stream_ordering, participant)
SELECT e.event_id, e.state_key, CASE WHEN pr.membership IN ('invite', 'ban') THEN '@user' || ((pr.u * 31) % (SELECT nu FROM p) + 1) || ':example.org' ELSE e.state_key END,
       e.room_id, pr.membership, CASE WHEN pr.membership = 'leave' AND pr.u % 4 = 0 THEN 1 ELSE 0 END,
       'User ' || pr.u || CASE WHEN pr.u % 5 = 0 THEN ' (away)' ELSE '' END, CASE WHEN pr.u % 3 = 0 THEN 'mxc://example.org/av' || pr.u END,
       e.stream_ordering, pr.u % 2
FROM ev JOIN pairs pr ON pr.pid = ev.pid JOIN events e ON e.stream_ordering = ev.so;
INSERT INTO current_state_events(event_id, room_id, type, state_key, membership, event_stream_ordering)
SELECT e.event_id, e.room_id, e.type, e.state_key, rm.membership, e.stream_ordering
FROM events e LEFT JOIN room_memberships rm ON rm.event_id = e.event_id WHERE e.state_key IS NOT NULL;
INSERT INTO current_state_delta_stream(stream_id, room_id, type, state_key, event_id, prev_event_id, instance_name)
SELECT stream_ordering, room_id, type, state_key, event_id,
       CASE WHEN type = 'm.room.member' AND stream_ordering % 4 = 0 THEN (SELECT x.event_id FROM events x WHERE x.stream_ordering = events.stream_ordering - 1 AND x.type = 'm.room.member') END,
       instance_name
FROM events WHERE state_key IS NOT NULL;
INSERT INTO local_current_membership(room_id, user_id, event_id, membership, event_stream_ordering)
SELECT room_id, user_id, event_id, membership, event_stream_ordering FROM room_memberships;

INSERT INTO room_stats_state(room_id, name, canonical_alias, join_rules, history_visibility, encryption, avatar, guest_access, is_federatable, topic, room_type)
SELECT room_id, 'Room ' || substr(room_id, 6, instr(room_id, ':') - 6) || CASE CAST(substr(room_id, 6, instr(room_id, ':') - 6) AS INT) % 4 WHEN 0 THEN ' Matrix chat' WHEN 1 THEN ' Rust lounge' WHEN 2 THEN ' Python help' ELSE ' Off-topic' END,
       '#' || substr(room_id, 2, instr(room_id, ':') - 2) || ':example.org',
       CASE CAST(substr(room_id, 6, instr(room_id, ':') - 6) AS INT) % 5 WHEN 0 THEN 'invite' WHEN 1 THEN 'knock' ELSE 'public' END,
       CASE WHEN CAST(substr(room_id, 6, instr(room_id, ':') - 6) AS INT) % 7 = 0 THEN 'world_readable' ELSE 'shared' END,
       CASE WHEN CAST(substr(room_id, 6, instr(room_id, ':') - 6) AS INT) % 2 = 0 THEN 'm.megolm.v1.aes-sha2' END,
       NULL, 'can_join', 1, 'A room about things', CASE WHEN CAST(substr(room_id, 6, instr(room_id, ':') - 6) AS INT) % 25 = 0 THEN 'm.space' END
FROM rooms;
INSERT INTO room_stats_current(room_id, current_state_events, joined_members, invited_members, left_members, banned_members, local_users_in_room, completed_delta_stream_id, knocked_members)
SELECT r.room_id, (SELECT count(*) FROM current_state_events c WHERE c.room_id = r.room_id),
       sum(m.membership = 'join'), sum(m.membership = 'invite'), sum(m.membership = 'leave'), sum(m.membership = 'ban'), sum(m.membership = 'join'),
       (SELECT max(stream_ordering) FROM events), 0
FROM rooms r JOIN room_memberships m ON m.room_id = r.room_id GROUP BY r.room_id;
INSERT INTO appservice_room_list(appservice_id, network_id, room_id)
SELECT 'irc', 'libera', room_id FROM rooms WHERE CAST(substr(room_id, 6, instr(room_id, ':') - 6) AS INT) % 11 = 1;

-- receipts: an unthreaded m.read for most joined members, part way into the room's timeline; some private and threaded receipts
INSERT INTO receipts_linearized(stream_id, room_id, receipt_type, user_id, event_id, thread_id, event_stream_ordering, data, instance_name)
SELECT row_number() OVER (ORDER BY pr.pid) , '!room' || pr.r || ':example.org', 'm.read', '@user' || pr.u || ':example.org', e.event_id, NULL, e.stream_ordering,
       json_object('ts', e.origin_server_ts + 5000), 'master'
FROM pairs pr JOIN rmcount c ON c.r = pr.r
JOIN rmsg rm ON rm.r = pr.r AND rm.rn = max(1, c.cnt * (40 + (pr.pid * 2654435761 / 64) % 55) / 100)
JOIN events e ON e.stream_ordering = rm.so
WHERE pr.membership = 'join' AND pr.pid % 10 <> 0;
INSERT INTO receipts_linearized(stream_id, room_id, receipt_type, user_id, event_id, thread_id, event_stream_ordering, data, instance_name)
SELECT 100000 + row_number() OVER (ORDER BY pr.pid), '!room' || pr.r || ':example.org', 'm.read.private', '@user' || pr.u || ':example.org', e.event_id, NULL, e.stream_ordering,
       json_object('ts', e.origin_server_ts + 9000), 'worker1'
FROM pairs pr JOIN rmcount c ON c.r = pr.r
JOIN rmsg rm ON rm.r = pr.r AND rm.rn = max(1, c.cnt * (60 + (pr.pid * 40503) % 35) / 100)
JOIN events e ON e.stream_ordering = rm.so
WHERE pr.membership = 'join' AND pr.pid % 7 = 0;
INSERT OR IGNORE INTO receipts_linearized(stream_id, room_id, receipt_type, user_id, event_id, thread_id, event_stream_ordering, data, instance_name)
SELECT 200000 + row_number() OVER (ORDER BY pr.pid), '!room' || pr.r || ':example.org', 'm.read', '@user' || pr.u || ':example.org', er.event_id, er.relates_to_id,
       e.stream_ordering, json_object('ts', e.origin_server_ts + 1000, 'thread_id', er.relates_to_id), 'master'
FROM pairs pr JOIN event_relations er ON er.relation_type = 'm.thread'
JOIN events e ON e.event_id = er.event_id AND e.room_id = '!room' || pr.r || ':example.org'
WHERE pr.membership = 'join' AND pr.pid % 3 = 0 AND (e.stream_ordering + pr.pid) % 9 = 0;

-- push actions: two members of the room are notified for each message
INSERT OR IGNORE INTO event_push_actions(room_id, event_id, user_id, profile_tag, actions, topological_ordering, stream_ordering, notif, highlight, unread, thread_id)
SELECT e.room_id, e.event_id, '@user' || pr.u || ':example.org', NULL,
       CASE WHEN (ev.h / 8192) % 20 = 0 THEN '["notify",{"set_tweak":"sound","value":"default"},{"set_tweak":"highlight"}]' ELSE '["notify"]' END,
       e.topological_ordering, e.stream_ordering, CASE WHEN (ev.h / 4) % 10 = 0 THEN 0 ELSE 1 END, (ev.h / 8192) % 20 = 0, 1,
       COALESCE((SELECT er.relates_to_id FROM event_relations er WHERE er.event_id = e.event_id AND er.relation_type = 'm.thread'), 'main')
FROM ev JOIN events e ON e.stream_ordering = ev.so
JOIN rcount rc ON rc.r = ev.r
JOIN (SELECT 7 AS k UNION ALL SELECT 11) k
JOIN pairs pr ON pr.r = ev.r AND pr.ri = (ev.h / k.k) % rc.cnt + 1
WHERE ev.kind = 'msg' AND ev.type = 'm.room.message' AND pr.u <> ev.u;

-- rotation has summarised everything up to 85 % of the stream
INSERT INTO event_push_summary_stream_ordering(lock, stream_ordering) SELECT 'X', (SELECT max(stream_ordering) FROM events) * 85 / 100;
INSERT INTO event_push_summary(user_id, room_id, notif_count, stream_ordering, unread_count, last_receipt_stream_ordering, thread_id)
SELECT a.user_id, a.room_id, sum(a.notif), max(a.stream_ordering), count(*),
       CASE WHEN length(a.user_id) % 3 = 0 THEN (SELECT max(r.event_stream_ordering) FROM receipts_linearized r WHERE r.user_id = a.user_id AND r.room_id = a.room_id AND r.receipt_type IN ('m.read', 'm.read.private')) END,
       a.thread_id
FROM event_push_actions a
WHERE a.stream_ordering <= (SELECT stream_ordering FROM event_push_summary_stream_ordering)
GROUP BY a.user_id, a.room_id, a.thread_id;

-- full-text search (FTS4, Synapse's SQLite path)
INSERT INTO event_search(event_id, room_id, sender, key, value)
SELECT e.event_id, e.room_id, e.sender, 'content.body',
       (SELECT group_concat(w, ' ') FROM (SELECT w FROM (SELECT column1 AS k, column2 AS w FROM (VALUES (0,'lunch'),(1,'deploy'),(2,'meeting'),(3,'release'),(4,'bug'),(5,'coffee'),(6,'review'),(7,'matrix'),(8,'bridge'),(9,'federation'),(10,'weekend'),(11,'server'))) v
                                            WHERE v.k IN ((ev.h / 16) % 12, (ev.h / 256) % 12, (ev.h / 4096) % 12, (ev.h / 65536) % 12)))
         || ' message ' || e.stream_ordering
FROM ev JOIN events e ON e.stream_ordering = ev.so WHERE ev.type = 'm.room.message';

-- user directory
INSERT INTO user_directory(user_id, room_id, display_name, avatar_url)
SELECT name, NULL, CASE WHEN CAST(substr(name, 6, instr(name, ':') - 6) AS INT) % 9 = 0 THEN NULL
                        ELSE (SELECT v FROM (SELECT column1 AS k, column2 AS v FROM (VALUES (0,'Alice'),(1,'Bob'),(2,'Carol'),(3,'Dave'),(4,'Erin'),(5,'Frank'),(6,'Grace'),(7,'Heidi'))) n WHERE k = CAST(substr(name, 6, instr(name, ':') - 6) AS INT) % 8)
                             || ' ' || (SELECT v FROM (SELECT column1 AS k, column2 AS v FROM (VALUES (0,'Smith'),(1,'Jones'),(2,'Garcia'),(3,'Müller'),(4,'Chen'),(5,'Okafor'))) n WHERE k = (CAST(substr(name, 6, instr(name, ':') - 6) AS INT) / 8) % 6) END,
       CASE WHEN CAST(substr(name, 6, instr(name, ':') - 6) AS INT) % 3 = 0 THEN 'mxc://example.org/av' || substr(name, 6, instr(name, ':') - 6) END
FROM users;
INSERT INTO user_directory_search(user_id, value)
SELECT user_id, substr(user_id, 2, instr(user_id, ':') - 2) || ' ' || COALESCE(display_name, '') || ' example.org' FROM user_directory;
INSERT OR IGNORE INTO users_in_public_rooms(user_id, room_id)
SELECT '@user' || pr.u || ':example.org', '!room' || pr.r || ':example.org' FROM pairs pr WHERE pr.membership = 'join' AND pr.r % 3 = 0;
INSERT OR IGNORE INTO users_who_share_private_rooms(user_id, other_user_id, room_id)
SELECT '@user' || a.u || ':example.org', '@user' || b.u || ':example.org', '!room' || a.r || ':example.org'
FROM pairs a JOIN pairs b ON b.r = a.r AND b.ri BETWEEN a.ri - 4 AND a.ri + 4 AND b.ri <> a.ri
WHERE a.r % 3 <> 0 AND a.membership = 'join' AND b.membership = 'join';

-- state groups: a chain of 15 groups per room; the first holds the full state, the rest small deltas
INSERT INTO state_groups(id, room_id, event_id)
SELECT (r.i - 1) * 15 + g.g + 1, '!room' || r.i || ':example.org', '$sg' || r.i || '_' || g.g
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < (SELECT nr FROM p)) SELECT i FROM n) r,
     (WITH RECURSIVE n(g) AS (SELECT 0 UNION ALL SELECT g+1 FROM n WHERE g < 14) SELECT g FROM n) g;
INSERT INTO state_group_edges(state_group, prev_state_group) SELECT id, id - 1 FROM state_groups WHERE (id - 1) % 15 <> 0;
INSERT INTO state_groups_state(state_group, room_id, type, state_key, event_id)
SELECT (CAST(substr(c.room_id, 6, instr(c.room_id, ':') - 6) AS INT) - 1) * 15 + 1, c.room_id, c.type, c.state_key, c.event_id FROM current_state_events c;
INSERT INTO state_groups_state(state_group, room_id, type, state_key, event_id)
SELECT sg.id, sg.room_id, 'm.room.member', '@user' || ((sg.id * 7 + k.k * 53) % (SELECT nu FROM p) + 1) || ':example.org', '$sgev' || sg.id || '_' || k.k
FROM state_groups sg, (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2) k WHERE (sg.id - 1) % 15 <> 0 AND (k.k = 0 OR sg.id % 2 = 0);
INSERT INTO state_groups_state(state_group, room_id, type, state_key, event_id)
SELECT sg.id, sg.room_id, 'm.room.history_visibility', '', '$sghv' || sg.id FROM state_groups sg WHERE (sg.id - 1) % 15 = 9;

-- sliding sync tables
INSERT INTO sliding_sync_joined_rooms(room_id, event_stream_ordering, bump_stamp, room_type, room_name, is_encrypted, tombstone_successor_room_id)
SELECT e.room_id, max(e.stream_ordering), max(e.stream_ordering), s.room_type, s.name, s.encryption IS NOT NULL, NULL
FROM events e JOIN room_stats_state s USING (room_id) GROUP BY e.room_id;
INSERT INTO sliding_sync_membership_snapshots(room_id, user_id, sender, membership_event_id, membership, forgotten, event_stream_ordering,
                                              event_instance_name, has_known_state, room_type, room_name, is_encrypted, tombstone_successor_room_id)
SELECT m.room_id, m.user_id, m.sender, m.event_id, m.membership, m.forgotten, m.event_stream_ordering, e.instance_name, NOT e.outlier,
       s.room_type, s.name, s.encryption IS NOT NULL, NULL
FROM room_memberships m JOIN events e USING (event_id) JOIN room_stats_state s ON s.room_id = m.room_id;
COMMIT;
