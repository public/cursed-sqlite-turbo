-- Synthetic data for memos. Deterministic (no random()): values come from multiplicative hashes of the row number.
-- _cfg.scale (default 1) multiplies the row counts: 200 users, 20 spaces, 60k memos, 30k comment relations,
-- 40k reactions, 15k attachments, 2k inbox rows at scale 1.
BEGIN;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 200*(SELECT scale FROM _cfg))
INSERT INTO user(id, created_ts, updated_ts, row_status, username, role, email, nickname, password_hash)
SELECT i, 1700000000 + i*3600, 1700000000 + i*3600, CASE WHEN i % 25 = 0 THEN 'ARCHIVED' ELSE 'NORMAL' END,
       'user' || i, CASE WHEN i = 1 THEN 'ADMIN' ELSE 'USER' END, 'user' || i || '@example.org', 'User ' || i, 'x'
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20*(SELECT scale FROM _cfg))
INSERT INTO space(id, uid, title) SELECT i, 'space-' || i, 'Space ' || i FROM n;

-- every user is a member of 3 spaces
INSERT INTO space_member(space_id, user_id, status, role)
SELECT DISTINCT ((u.id * 7 + k.k * 3) % (SELECT count(*) FROM space)) + 1, u.id,
       CASE WHEN (u.id + k.k) % 11 = 0 THEN 'INVITED' ELSE 'ACTIVE' END,
       CASE WHEN k.k = 0 AND u.id % 10 = 0 THEN 'ADMIN' ELSE 'USER' END
FROM user u, (SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2) k;

INSERT INTO user_setting(user_id, key, value)
SELECT id, 'GENERAL', json_object('locale', 'en', 'appearance', 'system', 'memoVisibility', 'PRIVATE') FROM user
UNION ALL
SELECT id, 'SHORTCUTS', json_object('shortcuts', json_array(json_object('id', 'work', 'title', 'Work', 'filter', 'tag in ["work"]'))) FROM user
UNION ALL
SELECT id, 'PERSONAL_ACCESS_TOKENS', json_object('tokens', json_array(
         json_object('tokenId', 't' || id || '-1', 'tokenHash', 'hash-' || id || '-1', 'description', 'cli'),
         json_object('tokenId', 't' || id || '-2', 'tokenHash', 'hash-' || id || '-2', 'description', 'ios')))
FROM user WHERE id % 2 = 1;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 60000*(SELECT scale FROM _cfg)),
words(w, k) AS (VALUES ('meeting',0),('idea',1),('todo',2),('link',3),('book',4),('travel',5),('recipe',6),('code',7)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO memo(id, uid, creator_id, created_ts, updated_ts, row_status, content, visibility, pinned, payload, space_id)
SELECT i,
       printf('m%08x', h),
       ((h / 4) % (200*(SELECT scale FROM _cfg))) + 1,
       1700000000 + i * 500,
       1700000000 + i * 500 + (h % 86400),
       CASE WHEN (h / 7) % 31 = 0 THEN 'ARCHIVED' ELSE 'NORMAL' END,
       printf('Memo %d about #%s and #%s. %s', i, (SELECT w FROM words WHERE k = (h / 2048) % 8), (SELECT w FROM words WHERE k = (h / 16384) % 8),
              CASE WHEN (h / 1024) % 5 = 0 THEN 'See https://example.org/' || (h % 1000) ELSE '- [ ] follow up' END),
       CASE (h / 65536) % 10 WHEN 0 THEN 'PUBLIC' WHEN 1 THEN 'PUBLIC' WHEN 2 THEN 'PROTECTED' WHEN 3 THEN 'SPACE' ELSE 'PRIVATE' END,
       CASE WHEN (h / 333) % 97 = 0 THEN 1 ELSE 0 END,
       json_object('tags', json_array((SELECT w FROM words WHERE k = (h / 2048) % 8), (SELECT w FROM words WHERE k = (h / 16384) % 8)),
                   'property', json_object('hasLink', json(CASE WHEN (h / 1024) % 5 = 0 THEN 'true' ELSE 'false' END),
                                                'hasTaskList', json(CASE WHEN (h / 1024) % 5 = 0 THEN 'false' ELSE 'true' END),
                                                'hasIncompleteTasks', json(CASE WHEN (h / 4096) % 3 = 0 THEN 'true' ELSE 'false' END)),
                   'location', CASE WHEN (h / 77) % 13 = 0 THEN json_object('placeholder', 'Berlin', 'latitude', 52.5, 'longitude', 13.4) END),
       CASE WHEN (h / 65536) % 10 = 3 THEN ((h / 3) % (20*(SELECT scale FROM _cfg))) + 1 END
FROM m;

-- every other memo with id % 2 = 0 and id > 10 is a comment on an earlier memo
INSERT INTO memo_relation(memo_id, related_memo_id, type)
SELECT id, id - 1 - ((id * 40503) % 50), 'COMMENT' FROM memo WHERE id % 2 = 0 AND id > 60
UNION ALL
SELECT id, id - 7 - ((id * 7919) % 500), 'REFERENCE' FROM memo WHERE id % 9 = 1 AND id > 600;

INSERT OR IGNORE INTO reaction(created_ts, creator_id, memo_id, reaction_type)
SELECT 1700000000 + r.i * 400, (r.i * 13) % (SELECT count(*) FROM user) + 1, (r.i * 2654435761) % (SELECT count(*) FROM memo) + 1,
       CASE r.i % 4 WHEN 0 THEN '👍' WHEN 1 THEN '❤️' WHEN 2 THEN '🎉' ELSE '👀' END
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40000*(SELECT scale FROM _cfg)) SELECT i FROM n) r;

INSERT INTO attachment(uid, creator_id, created_ts, updated_ts, filename, type, size, memo_id, storage_type, reference)
SELECT printf('a%07d', i), (i % (SELECT count(*) FROM user)) + 1, 1700000000 + i * 2000, 1700000000 + i * 2000,
       'file' || i || CASE i % 3 WHEN 0 THEN '.png' WHEN 1 THEN '.pdf' ELSE '.jpg' END,
       CASE i % 3 WHEN 0 THEN 'image/png' WHEN 1 THEN 'application/pdf' ELSE 'image/jpeg' END,
       (i * 7919) % 5000000, CASE WHEN i % 10 = 0 THEN NULL ELSE (i * 4) % (SELECT count(*) FROM memo) + 1 END, 'LOCAL',
       'assets/' || i
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 15000*(SELECT scale FROM _cfg)) SELECT i FROM n);

INSERT INTO inbox(created_ts, sender_id, receiver_id, status, message)
SELECT 1700000000 + i * 1000, (i % 200) + 1, ((i * 7) % 200) + 1, CASE WHEN i % 3 = 0 THEN 'ARCHIVED' ELSE 'UNREAD' END,
       json_object('type', 'MEMO_COMMENT', 'memoCommentPayload', json_object('memoId', i * 3, 'relatedMemoId', i * 3 - 1))
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000*(SELECT scale FROM _cfg)) SELECT i FROM n);

INSERT INTO memo_share(uid, memo_id, creator_id, created_ts, expires_ts)
SELECT 's' || id, id, creator_id, created_ts, CASE WHEN id % 2 = 0 THEN created_ts + 86400 * 30 END FROM memo WHERE id % 50 = 0;

INSERT INTO system_setting(name, value) VALUES ('GENERAL', '{"disallowUserRegistration":false}'), ('MEMO_RELATED', '{"contentLengthLimit":8192}');
COMMIT;
