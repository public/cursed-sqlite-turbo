-- Synthetic data for signal-desktop. Deterministic (no random()): values come from multiplicative hashes of the
-- row number, with different bits per column. _cfg.scale multiplies the row counts. At scale 1: 300
-- conversations (conv-0001..conv-0005 are the busy ones), 60k messages (incoming/outgoing chat plus stories,
-- story replies, call-history, group-change, keychange and timer notifications), ~12k attachments, ~1.9k call
-- history rows, 7k reactions, 900 edits, 3k attachment download jobs, 3k sync tasks.
-- Our own ACI is aaaaaaaa-0000-4000-8000-000000000000; contact n has ACI printf('%08x-0000-4000-8000-%012d', n, n).
-- The messages_fts and mentions triggers fire on every insert, as in the app.
BEGIN;

CREATE TEMP TABLE _w(k INTEGER PRIMARY KEY, w TEXT);
INSERT INTO _w VALUES (0,'pizza'),(1,'tonight'),(2,'meeting'),(3,'photo'),(4,'birthday'),(5,'train'),(6,'coffee'),
  (7,'weekend'),(8,'project'),(9,'doctor'),(10,'movie'),(11,'dinner'),(12,'flight'),(13,'concert'),(14,'invoice'),(15,'garden');

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300*(SELECT scale FROM _cfg))
INSERT INTO conversations(id, json, active_at, type, members, name, profileName, profileFamilyName, profileFullName,
                          e164, serviceId, groupId, profileLastFetchedAt, expireTimerVersion)
SELECT printf('conv-%04d', i),
       json_object('id', printf('conv-%04d', i), 'type', CASE WHEN i % 5 = 0 THEN 'group' ELSE 'private' END,
                   'name', CASE WHEN i % 5 = 0 THEN 'Group ' || i END, 'profileName', 'Contact ' || i,
                   'markedUnread', json('false'), 'unreadCount', 0, 'isArchived', json(CASE WHEN i % 23 = 0 THEN 'true' ELSE 'false' END),
                   'expireTimer', CASE WHEN i % 6 = 0 THEN 604800 END),
       1700000000000 + (300*(SELECT scale FROM _cfg) - i) * 3600000,
       CASE WHEN i % 5 = 0 THEN 'group' ELSE 'private' END,
       CASE WHEN i % 5 = 0 THEN (SELECT group_concat(printf('conv-%04d', ((i*7 + k*13) % 300) + 1), ' ') FROM _w WHERE k < 8) END,
       CASE WHEN i % 5 = 0 THEN 'Group ' || i END,
       'Contact ' || i, 'Family' || (i % 40), 'Contact ' || i || ' Family' || (i % 40),
       CASE WHEN i % 5 <> 0 THEN printf('+1555%07d', i) END,
       CASE WHEN i % 5 <> 0 THEN printf('%08x-0000-4000-8000-%012d', i, i) END,
       CASE WHEN i % 5 = 0 THEN printf('grp%029d', i) END,
       1700000000000 + i * 1000, 2
FROM n;

-- Messages. json_patch('{}', ...) drops the null keys, as the app's JSON never has them. Every 50th row (i % 50 = 7) is a story; ~1 in 30 chat messages replies to the latest story.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 60000*(SELECT scale FROM _cfg)),
m0 AS (
  SELECT i, (i * 2654435761) % 4294967296 AS h, 60000*(SELECT scale FROM _cfg) AS total, 300*(SELECT scale FROM _cfg) AS nconv FROM n
),
m1 AS (
  SELECT i, h, total,
         CASE WHEN (h / 3) % 100 < 35 THEN 1 + (h / 300) % 5 ELSE 1 + (h / 1000) % nconv END AS conv,
         CASE WHEN i % 50 = 7 THEN 'story'
              ELSE CASE WHEN (h / 7) % 100 < 46 THEN 'incoming' WHEN (h / 7) % 100 < 90 THEN 'outgoing'
                        WHEN (h / 7) % 100 < 93 THEN 'call-history' WHEN (h / 7) % 100 < 96 THEN 'group-v2-change'
                        WHEN (h / 7) % 100 < 98 THEN 'keychange' ELSE 'timer-notification' END END AS type,
         1700000000000 + i * 20000 + (h % 5000) AS sent
  FROM m0
),
m AS (
  SELECT *,
         type IN ('incoming','outgoing') AS chat,
         CASE WHEN type IN ('incoming','outgoing') AND (h / 13) % 30 = 0 AND i > 60 THEN printf('msg-%07d', i - ((i - 7) % 50)) END AS story_id,
         CASE WHEN conv % 5 = 0 THEN 1 + (h / 1024) % 200 ELSE conv END AS contact,
         type = 'incoming' AND i > total - total / 40 AS unread,
         type IN ('incoming','outgoing') AND (h / 512) % 6 = 0 AS has_att,
         (h / 2048) % 3 <> 0 AS visual,
         type = 'incoming' AND conv % 5 = 0 AND (h / 65536) % 20 = 0 AS mentions_me,
         type = 'incoming' AND (h / 99991) % 97 = 0 AS view_once,
         CASE WHEN type IN ('incoming','outgoing') AND conv % 6 = 0 THEN 604800 END AS timer
  FROM m1
)
INSERT INTO messages(id, json, body, conversationId, expirationStartTimestamp, expireTimer, hasAttachments,
                     hasFileAttachments, hasVisualMediaAttachments, hasUnreadPollVotes, isChangeCreatedByUs, isErased,
                     isViewOnce, mentionsMe, received_at, received_at_ms, schemaVersion, serverGuid, sent_at, source,
                     sourceServiceId, sourceDevice, storyId, type, readStatus, seenStatus, serverTimestamp, timestamp,
                     unidentifiedDeliveryReceived)
SELECT printf('msg-%07d', i),
       json_patch('{}', json_object(
         'id', printf('msg-%07d', i), 'conversationId', printf('conv-%04d', conv), 'type', type, 'sent_at', sent,
         'timestamp', sent, 'received_at', 1000000 + i, 'schemaVersion', 14,
         'body', CASE WHEN chat OR type = 'story' THEN printf('%s %s at %d, %s?', (SELECT w FROM _w WHERE k = (h / 16) % 16),
                      (SELECT w FROM _w WHERE k = (h / 256) % 16), h % 24, (SELECT w FROM _w WHERE k = (h / 131072) % 16)) END,
         'bodyRanges', CASE WHEN mentions_me THEN json_array(json_object('start', 0, 'length', 1, 'mentionAci', 'aaaaaaaa-0000-4000-8000-000000000000'))
                            WHEN type = 'incoming' AND (h / 65536) % 20 = 1 THEN json_array(json_object('start', 0, 'length', 1, 'mentionAci', printf('%08x-0000-4000-8000-%012d', 1 + (h / 4096) % 200, 1 + (h / 4096) % 200)))
                            WHEN chat AND (h / 65536) % 20 = 2 THEN json_array(json_object('start', 2, 'length', 4, 'style', 1)) END,
         'quote', CASE WHEN type = 'incoming' AND (h / 262144) % 12 = 0
                       THEN json_object('id', sent - 600000, 'authorAci', CASE WHEN (h / 1048576) % 2 = 0 THEN 'aaaaaaaa-0000-4000-8000-000000000000'
                                                                             ELSE printf('%08x-0000-4000-8000-%012d', contact, contact) END,
                                        'text', 'earlier message', 'isViewOnce', json('false')) END,
         'preview', CASE WHEN chat AND (h / 333) % 23 = 0 THEN json_array(json_object('url', 'https://example.org/post/' || (h % 10000), 'title', 'Example post ' || (h % 10000), 'domain', 'example.org')) END,
         'contact', CASE WHEN chat AND (h / 777) % 151 = 0 THEN json_array(json_object('name', json_object('givenName', 'Ann', 'familyName', 'Lee' || (h % 50)), 'number', json_array(json_object('value', '+15550001111', 'type', 1)))) END,
         'poll', CASE WHEN type = 'outgoing' AND (h / 5555) % 499 = 0 THEN json_object('question', 'Pizza tonight or tomorrow?', 'options', json_array('tonight', 'tomorrow')) END,
         'sendStateByConversationId', CASE WHEN type = 'outgoing' THEN json_object(printf('conv-%04d', conv), json_object('status', CASE (h / 64) % 3 WHEN 0 THEN 'Sent' WHEN 1 THEN 'Delivered' ELSE 'Read' END, 'updatedAt', sent + 4000)) END,
         'callId', CASE WHEN type = 'call-history' THEN printf('call-%07d', i) END,
         'groupV2Change', CASE WHEN type = 'group-v2-change' THEN
                            CASE WHEN (h / 64) % 3 = 0 THEN json_object('from', printf('%08x-0000-4000-8000-%012d', contact, contact), 'details', json_array(json_object('type', 'member-remove', 'aci', printf('%08x-0000-4000-8000-%012d', contact, contact))))
                                 ELSE json_object('from', printf('%08x-0000-4000-8000-%012d', contact, contact), 'details', json_array(json_object('type', 'title', 'newTitle', 'Group ' || (h % 90)))) END END,
         'expirationTimerUpdate', CASE WHEN type = 'timer-notification' THEN json_object('expireTimer', 604800, 'fromSync', json(CASE WHEN h % 2 = 1 THEN 'true' ELSE 'false' END)) END,
         'messageRequestResponseEvent', NULL)),
       CASE WHEN chat OR type = 'story' THEN printf('%s %s at %d, %s?', (SELECT w FROM _w WHERE k = (h / 16) % 16),
            (SELECT w FROM _w WHERE k = (h / 256) % 16), h % 24, (SELECT w FROM _w WHERE k = (h / 131072) % 16)) END,
       printf('conv-%04d', conv),
       CASE WHEN timer IS NOT NULL AND NOT unread THEN sent + 1000 END,
       timer,
       has_att, has_att AND NOT visual, has_att AND visual,
       0, 0, 0, view_once, mentions_me,
       1000000 + i, sent + 300 + (h % 700), 14,
       printf('%08x-guid-%07d', h, i),
       sent,
       CASE WHEN type = 'incoming' THEN printf('+1555%07d', contact) END,
       CASE WHEN type IN ('incoming', 'story', 'group-v2-change') THEN printf('%08x-0000-4000-8000-%012d', contact, contact)
            WHEN type = 'outgoing' THEN 'aaaaaaaa-0000-4000-8000-000000000000' END,
       CASE WHEN type = 'incoming' THEN 1 + (h / 8) % 3 END,
       story_id,
       type,
       CASE WHEN type = 'incoming' THEN CASE WHEN unread THEN 1 ELSE 0 END
            WHEN type IN ('outgoing', 'call-history', 'story') THEN 0 END,
       CASE WHEN type = 'incoming' THEN CASE WHEN unread THEN 1 ELSE 2 END
            WHEN type = 'call-history' THEN CASE WHEN (h / 4096) % 4 = 0 THEN 1 ELSE 2 END
            WHEN type = 'outgoing' THEN 0 ELSE 2 END,
       sent + 120, sent, CASE WHEN type = 'incoming' THEN (h / 32) % 2 END
FROM m;

-- Attachments for messages with hasAttachments (one each, a second for ~1/3 of them).
WITH a AS (
  SELECT m.*, (m.rowid * 2246822519) % 4294967296 AS g FROM messages m WHERE hasAttachments = 1
),
o(k) AS (VALUES (0), (1))
INSERT INTO message_attachments(messageId, editHistoryIndex, attachmentType, orderInMessage, conversationId, sentAt,
                                clientUuid, size, contentType, path, plaintextHash, localKey, fileName, height, width,
                                digest, key, version, flags, pending, messageType, receivedAt, receivedAtMs, isViewOnce,
                                duration)
SELECT a.id, -1, 'attachment', o.k, a.conversationId, a.sent_at,
       printf('%08x-cu-%d', a.g, o.k), 1000 + (a.g / 16) % 8000000,
       CASE WHEN a.hasVisualMediaAttachments = 1 THEN CASE WHEN (a.g / 8) % 4 = 0 THEN 'video/mp4' ELSE 'image/jpeg' END
            ELSE CASE (a.g / 8) % 5 WHEN 0 THEN 'audio/aac' WHEN 1 THEN 'text/x-signal-plain' WHEN 2 THEN 'application/zip' ELSE 'application/pdf' END END,
       printf('%02x/%08x%d', a.g % 256, a.g, o.k), printf('%016x', a.g * 31 + o.k), 'lk' || a.g,
       CASE WHEN a.hasFileAttachments = 1 THEN 'document-' || (a.g % 1000) || '.pdf' END,
       CASE WHEN a.hasVisualMediaAttachments = 1 THEN 600 + a.g % 1000 END,
       CASE WHEN a.hasVisualMediaAttachments = 1 THEN 800 + a.g % 1000 END,
       printf('dg%08x', a.g), printf('key%08x', a.g), 2,
       CASE WHEN a.hasFileAttachments = 1 AND (a.g / 8) % 5 = 0 AND (a.g / 64) % 2 = 0 THEN 1 ELSE 0 END,
       0, a.type, a.received_at, a.received_at_ms, a.isViewOnce,
       CASE WHEN (a.g / 8) % 4 = 0 THEN (a.g % 600) / 10.0 END
FROM a JOIN o ON o.k = 0 OR (a.g / 4096) % 3 = 0;

-- Call history: one row per call-history message, plus ad-hoc call-link calls.
INSERT INTO callsHistory(callId, peerId, ringerId, mode, type, direction, status, timestamp, startedById, endedTimestamp)
SELECT json_extract(m.json, '$.callId'),
       COALESCE(c.serviceId, c.groupId),
       CASE WHEN c.type = 'group' THEN printf('%08x-0000-4000-8000-%012d', 1 + (m.rowid / 3) % 200, 1 + (m.rowid / 3) % 200) END,
       CASE WHEN c.type = 'group' THEN 'Group' ELSE 'Direct' END,
       CASE WHEN c.type = 'group' THEN 'Group' WHEN m.rowid % 3 = 0 THEN 'Video' ELSE 'Audio' END,
       CASE WHEN (m.rowid / 5) % 5 < 3 THEN 'Incoming' ELSE 'Outgoing' END,
       CASE WHEN c.type = 'group' THEN CASE (m.rowid / 11) % 6 WHEN 0 THEN 'Missed' WHEN 1 THEN 'Joined' WHEN 2 THEN 'Declined' WHEN 3 THEN 'Deleted' ELSE 'GenericGroupCall' END
            ELSE CASE (m.rowid / 11) % 6 WHEN 0 THEN 'Missed' WHEN 1 THEN 'Missed' WHEN 2 THEN 'Declined' WHEN 3 THEN 'Deleted' ELSE 'Accepted' END END,
       m.sent_at,
       CASE WHEN c.type = 'group' THEN printf('%08x-0000-4000-8000-%012d', 1 + (m.rowid / 7) % 200, 1 + (m.rowid / 7) % 200) END,
       m.sent_at + 60000 + (m.rowid % 900000)
FROM messages m JOIN conversations c ON c.id = m.conversationId
WHERE m.type = 'call-history';

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 200*(SELECT scale FROM _cfg))
INSERT INTO callsHistory(callId, peerId, ringerId, mode, type, direction, status, timestamp)
SELECT printf('adhoc-%06d', i), printf('room%04d', 1 + (i * 37) % 25), NULL, 'Adhoc', 'Adhoc',
       CASE WHEN i % 3 = 0 THEN 'Outgoing' ELSE 'Incoming' END, 'GenericAdhocCall',
       1700000000000 + ((i * 2654435761) % 4294967296) % (60000*(SELECT scale FROM _cfg)) * 20000
FROM n;

-- Reactions on recent-ish messages; a tenth unread.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 8000*(SELECT scale FROM _cfg)),
r AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO reactions(conversationId, emoji, fromId, messageId, messageReceivedAt, targetAuthorAci, targetTimestamp, timestamp, unread)
SELECT m.conversationId, CASE (r.h / 16) % 5 WHEN 0 THEN '👍' WHEN 1 THEN '❤️' WHEN 2 THEN '😂' WHEN 3 THEN '😮' ELSE '🙏' END,
       printf('conv-%04d', 1 + (r.h / 256) % 300), m.id, m.received_at, COALESCE(m.sourceServiceId, 'aaaaaaaa-0000-4000-8000-000000000000'),
       m.sent_at, m.sent_at + 30000 + r.h % 100000, CASE WHEN r.i % 10 = 0 THEN 1 ELSE 0 END
FROM r JOIN messages m ON m.rowid = 1 + (r.h / 4096) % (60000*(SELECT scale FROM _cfg))
WHERE m.type IN ('incoming', 'outgoing');

-- Edits: the edited message keeps its row; edited_messages holds each prior revision's sentAt.
INSERT INTO edited_messages(messageId, sentAt, readStatus, conversationId)
SELECT id, sent_at - 7000 - (rowid % 900), CASE WHEN readStatus = 1 THEN 1 ELSE 0 END, conversationId
FROM messages WHERE type IN ('incoming', 'outgoing') AND rowid % 60 = 3;

INSERT INTO storyReads(authorId, conversationId, storyId, storyReadDate)
SELECT sourceServiceId, conversationId, id, sent_at + 3600000 FROM messages WHERE type = 'story' AND rowid % 3 <> 0;

-- Attachment download queue.
INSERT INTO attachment_downloads(messageId, attachmentType, attachmentSignature, receivedAt, sentAt, contentType, size,
                                 attachmentJson, active, attempts, retryAfter, lastAttemptTimestamp, source,
                                 ciphertextSize, originalSource)
SELECT ma.messageId, 'attachment', ma.digest || ':' || ma.orderInMessage, ma.receivedAt, ma.sentAt, ma.contentType, ma.size,
       json_object('contentType', ma.contentType, 'size', ma.size, 'digest', ma.digest, 'key', ma.key, 'cdnKey', 'cdn' || ma.rowid, 'cdnNumber', 3),
       CASE WHEN ma.rowid % 17 = 0 THEN 1 ELSE 0 END, ma.rowid % 4,
       CASE WHEN ma.rowid % 4 > 0 THEN ma.sentAt + 3600000 * (ma.rowid % 4) END,
       CASE WHEN ma.rowid % 4 > 0 THEN ma.sentAt + 60000 END,
       CASE WHEN ma.rowid % 5 = 0 THEN 'backup_import' ELSE 'standard' END,
       ma.size + 64, CASE WHEN ma.rowid % 5 = 0 THEN 'backup_import' ELSE 'standard' END
FROM message_attachments ma WHERE ma.rowid % 4 = 1;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 3000*(SELECT scale FROM _cfg))
INSERT INTO syncTasks(id, attempts, createdAt, data, envelopeId, sentAt, type)
SELECT printf('task-%06d', i), i % 7, 1702000000000 + i * 1000,
       json_object('type', CASE i % 3 WHEN 0 THEN 'delete-message' WHEN 1 THEN 'read-sync' ELSE 'view-sync' END, 'conversationId', printf('conv-%04d', 1 + i % 300)),
       printf('env-%06d', i), 1702000000000 + i * 1000 - 500,
       CASE i % 3 WHEN 0 THEN 'delete-message' WHEN 1 THEN 'read-sync' ELSE 'view-sync' END
FROM n;

INSERT INTO items(id, json)
SELECT 'item' || k, json_object('id', 'item' || k, 'value', w) FROM _w
UNION ALL SELECT 'uuid_id', json_object('id', 'uuid_id', 'value', 'aaaaaaaa-0000-4000-8000-000000000000.1')
UNION ALL SELECT 'read-receipt-setting', json_object('id', 'read-receipt-setting', 'value', json('true'));

INSERT INTO recentEmojis(emoji, lastUsedAt)
VALUES ('👍', 1702000000000), ('❤️', 1702000100000), ('😂', 1702000200000), ('🙏', 1701000000000), ('🎉', 1700000000000);

INSERT INTO pinnedMessages(conversationId, messageId, pinnedAt, expiresAt)
SELECT conversationId, id, sent_at + 1000, CASE WHEN rowid % 2 = 0 THEN sent_at + 86400000 END
FROM messages WHERE type IN ('incoming', 'outgoing') AND rowid % 997 = 0;

-- searchMessages' temp tables. They hold the state of two different searches so each step in queries.sql can run
-- without colliding with rows already there: tmp_results holds step 1's output for '"pizza"* "tonight"*' (input to
-- the filter step), tmp_filtered_results holds step 2's output for '"concert"* "garden"*' (input to the snippet
-- step). The body format puts three words in each message, so the two searches never match the same row.
INSERT INTO tmp_results(rowid) SELECT rowid FROM messages_fts WHERE messages_fts.body MATCH '"pizza"* "tonight"*';
INSERT INTO tmp_filtered_results(rowid)
SELECT m.rowid FROM messages_fts f INNER JOIN messages m ON m.rowid = f.rowid
WHERE f.body MATCH '"concert"* "garden"*'
ORDER BY m.received_at DESC, m.sent_at DESC LIMIT 500;

DROP TABLE _w;
COMMIT;
