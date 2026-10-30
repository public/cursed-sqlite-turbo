-- Signal Desktop (signalapp/Signal-Desktop @ 17502b9d1a9e34af689f31508c4ac4ccee5b5cb7, AGPL-3.0-only). Each statement
-- is quoted from the file:line in its @src. The app runs on @signalapp/sqlcipher (better-sqlite3 API). Two binding
-- styles: plain prepare() strings with $name parameters, and the sql`` tagged template (ts/sql/util.std.ts), which
-- turns every ${value} into a positional `?` (normalised to ?N here) and inlines sqlConstant() values as literals.
-- MESSAGE_COLUMNS_FRAGMENT (ts/sql/Interface.std.ts:205) expands to messages.`col` for the 29 MESSAGE_COLUMNS;
-- MESSAGE_COLUMNS.join(', ') expands to the bare names. Number.MAX_VALUE bounds are bound as 1.7976931348623157e308.

-- @id signal-desktop.search.fts_collect_rowids
-- @src ts/sql/Server.node.ts:2204-2215
-- @style $name (prepare().run)
-- @tags hotpath,batch
-- @note Step 1 of message search: every FTS5 rowid matching the tokenised prefix query goes into a rowid temp table.
-- @modified tmp_results is a TEMP table created just before this statement in the app; here it is an ordinary table (see schema.sql).
-- @param $query '"coffee"* "train"*'
INSERT INTO tmp_results (rowid)
SELECT rowid FROM messages_fts WHERE messages_fts.body MATCH $query;

-- @id signal-desktop.search.filter_sort_limit
-- @src ts/sql/Server.node.ts:2217-2240
-- @style sql`` positional, dynamic WHERE (conversation and unread filters resolve to TRUE for a global search)
-- @tags hotpath,dynamic,batch
-- @note Step 2: join the rowids back to messages and keep the newest 500 by (received_at, sent_at) so ORDER BY+LIMIT run without the virtual table.
-- @modified tmp_results / tmp_filtered_results are TEMP tables in the app (see schema.sql).
-- @param ?1 500
INSERT INTO tmp_filtered_results (rowid)
SELECT tmp_results.rowid
FROM tmp_results
INNER JOIN messages ON messages.rowid = tmp_results.rowid
WHERE TRUE AND TRUE
ORDER BY messages.received_at DESC, messages.sent_at DESC
LIMIT ?1;

-- @id signal-desktop.search.snippet_page
-- @src ts/sql/Server.node.ts:2246-2265
-- @style sql`` positional; snippet markers bound as parameters
-- @tags hotpath
-- @note Step 3: re-MATCH the kept rowids to get FTS5 snippet() with the full message columns, newest first.
-- @modified tmp_filtered_results is a TEMP table in the app (see schema.sql).
-- @param ?1 '<<left>>'
-- @param ?2 '<<right>>'
-- @param ?3 '<<truncation>>'
-- @param ?4 '"concert"* "garden"*'
-- @param ?5 500
SELECT messages.rowid, messages.`id`,messages.`json`,messages.`body`,messages.`conversationId`,messages.`expirationStartTimestamp`,messages.`expireTimer`,messages.`hasAttachments`,messages.`hasFileAttachments`,messages.`hasVisualMediaAttachments`,messages.`hasUnreadPollVotes`,messages.`isChangeCreatedByUs`,messages.`isErased`,messages.`isViewOnce`,messages.`mentionsMe`,messages.`received_at`,messages.`received_at_ms`,messages.`schemaVersion`,messages.`serverGuid`,messages.`sent_at`,messages.`source`,messages.`sourceServiceId`,messages.`sourceDevice`,messages.`storyId`,messages.`type`,messages.`readStatus`,messages.`seenStatus`,messages.`serverTimestamp`,messages.`timestamp`,messages.`unidentifiedDeliveryReceived`,
       snippet(messages_fts, -1, ?1, ?2, ?3, 10) AS ftsSnippet
FROM tmp_filtered_results
INNER JOIN messages_fts ON messages_fts.rowid = tmp_filtered_results.rowid
INNER JOIN messages ON messages.rowid = tmp_filtered_results.rowid
WHERE messages_fts.body MATCH ?4
ORDER BY messages.received_at DESC, messages.sent_at DESC
LIMIT ?5;

-- @id signal-desktop.search.mentions_full_outer_join
-- @src ts/sql/Server.node.ts:2267-2318
-- @style sql`` positional, dynamic (contact ACIs matching the query become an IN list; COALESCE per message column)
-- @tags hotpath,dynamic
-- @note Search that also matches contacts' names: FULL OUTER JOIN of messages mentioning those ACIs with the FTS snippet page, GROUP BY rowid, top-N.
-- @modified tmp_filtered_results is a TEMP table in the app (see schema.sql).
-- @param ?1 '0000006b-0000-4000-8000-000000000107'
-- @param ?2 '0000006e-0000-4000-8000-000000000110'
-- @param ?3 '<<left>>'
-- @param ?4 '<<right>>'
-- @param ?5 '<<truncation>>'
-- @param ?6 '"concert"* "garden"*'
-- @param ?7 500
-- @param ?8 500
SELECT messages.rowid as rowid, COALESCE(messages.`id`, ftsResults.`id`) AS `id`,COALESCE(messages.`json`, ftsResults.`json`) AS `json`,COALESCE(messages.`body`, ftsResults.`body`) AS `body`,COALESCE(messages.`conversationId`, ftsResults.`conversationId`) AS `conversationId`,COALESCE(messages.`expirationStartTimestamp`, ftsResults.`expirationStartTimestamp`) AS `expirationStartTimestamp`,COALESCE(messages.`expireTimer`, ftsResults.`expireTimer`) AS `expireTimer`,COALESCE(messages.`hasAttachments`, ftsResults.`hasAttachments`) AS `hasAttachments`,COALESCE(messages.`hasFileAttachments`, ftsResults.`hasFileAttachments`) AS `hasFileAttachments`,COALESCE(messages.`hasVisualMediaAttachments`, ftsResults.`hasVisualMediaAttachments`) AS `hasVisualMediaAttachments`,COALESCE(messages.`hasUnreadPollVotes`, ftsResults.`hasUnreadPollVotes`) AS `hasUnreadPollVotes`,COALESCE(messages.`isChangeCreatedByUs`, ftsResults.`isChangeCreatedByUs`) AS `isChangeCreatedByUs`,COALESCE(messages.`isErased`, ftsResults.`isErased`) AS `isErased`,COALESCE(messages.`isViewOnce`, ftsResults.`isViewOnce`) AS `isViewOnce`,COALESCE(messages.`mentionsMe`, ftsResults.`mentionsMe`) AS `mentionsMe`,COALESCE(messages.`received_at`, ftsResults.`received_at`) AS `received_at`,COALESCE(messages.`received_at_ms`, ftsResults.`received_at_ms`) AS `received_at_ms`,COALESCE(messages.`schemaVersion`, ftsResults.`schemaVersion`) AS `schemaVersion`,COALESCE(messages.`serverGuid`, ftsResults.`serverGuid`) AS `serverGuid`,COALESCE(messages.`sent_at`, ftsResults.`sent_at`) AS `sent_at`,COALESCE(messages.`source`, ftsResults.`source`) AS `source`,COALESCE(messages.`sourceServiceId`, ftsResults.`sourceServiceId`) AS `sourceServiceId`,COALESCE(messages.`sourceDevice`, ftsResults.`sourceDevice`) AS `sourceDevice`,COALESCE(messages.`storyId`, ftsResults.`storyId`) AS `storyId`,COALESCE(messages.`type`, ftsResults.`type`) AS `type`,COALESCE(messages.`readStatus`, ftsResults.`readStatus`) AS `readStatus`,COALESCE(messages.`seenStatus`, ftsResults.`seenStatus`) AS `seenStatus`,COALESCE(messages.`serverTimestamp`, ftsResults.`serverTimestamp`) AS `serverTimestamp`,COALESCE(messages.`timestamp`, ftsResults.`timestamp`) AS `timestamp`,COALESCE(messages.`unidentifiedDeliveryReceived`, ftsResults.`unidentifiedDeliveryReceived`) AS `unidentifiedDeliveryReceived`,
       ftsResults.ftsSnippet, mentionAci, start as mentionStart, length as mentionLength
FROM mentions
INNER JOIN messages ON
  messages.id = mentions.messageId
  AND mentions.mentionAci IN (?1,?2)
  AND 1 IS 1
  AND messages.isViewOnce IS NOT 1
  AND messages.storyId IS NULL
FULL OUTER JOIN (
  SELECT messages.rowid, messages.`id`,messages.`json`,messages.`body`,messages.`conversationId`,messages.`expirationStartTimestamp`,messages.`expireTimer`,messages.`hasAttachments`,messages.`hasFileAttachments`,messages.`hasVisualMediaAttachments`,messages.`hasUnreadPollVotes`,messages.`isChangeCreatedByUs`,messages.`isErased`,messages.`isViewOnce`,messages.`mentionsMe`,messages.`received_at`,messages.`received_at_ms`,messages.`schemaVersion`,messages.`serverGuid`,messages.`sent_at`,messages.`source`,messages.`sourceServiceId`,messages.`sourceDevice`,messages.`storyId`,messages.`type`,messages.`readStatus`,messages.`seenStatus`,messages.`serverTimestamp`,messages.`timestamp`,messages.`unidentifiedDeliveryReceived`,
         snippet(messages_fts, -1, ?3, ?4, ?5, 10) AS ftsSnippet
  FROM tmp_filtered_results
  INNER JOIN messages_fts ON messages_fts.rowid = tmp_filtered_results.rowid
  INNER JOIN messages ON messages.rowid = tmp_filtered_results.rowid
  WHERE messages_fts.body MATCH ?6
  ORDER BY messages.received_at DESC, messages.sent_at DESC
  LIMIT ?7
) as ftsResults
USING (rowid)
GROUP BY rowid
ORDER BY received_at DESC, sent_at DESC
LIMIT ?8;

-- @id signal-desktop.conversation.older_page
-- @src ts/sql/Server.node.ts:4056-4135
-- @style sql`` positional, dynamic (direction Older, no attachment filter, story replies excluded)
-- @tags hotpath,dynamic
-- @note The conversation scroll-back page: UNION ALL of the same-received_at tie-break and the strictly-older range, each ordered DESC, outer LIMIT.
-- @param ?1 'conv-0005'
-- @param ?2 'msg-0050963'
-- @param ?3 'msg-0050963'
-- @param ?4 NULL
-- @param ?5 1050963
-- @param ?6 1701019263027
-- @param ?7 'conv-0005'
-- @param ?8 'msg-0050963'
-- @param ?9 'msg-0050963'
-- @param ?10 NULL
-- @param ?11 1050963
-- @param ?12 100
SELECT first.* FROM (
  SELECT messages.`id`,messages.`json`,messages.`body`,messages.`conversationId`,messages.`expirationStartTimestamp`,messages.`expireTimer`,messages.`hasAttachments`,messages.`hasFileAttachments`,messages.`hasVisualMediaAttachments`,messages.`hasUnreadPollVotes`,messages.`isChangeCreatedByUs`,messages.`isErased`,messages.`isViewOnce`,messages.`mentionsMe`,messages.`received_at`,messages.`received_at_ms`,messages.`schemaVersion`,messages.`serverGuid`,messages.`sent_at`,messages.`source`,messages.`sourceServiceId`,messages.`sourceDevice`,messages.`storyId`,messages.`type`,messages.`readStatus`,messages.`seenStatus`,messages.`serverTimestamp`,messages.`timestamp`,messages.`unidentifiedDeliveryReceived`
  FROM messages WHERE
    conversationId = ?1 AND
    (?2 IS NULL OR id IS NOT ?3) AND
    isStory IS 0 AND
    (storyId IS ?4) AND
    ( received_at = ?5 AND sent_at < ?6 )
    ORDER BY received_at DESC, sent_at DESC
) as first
UNION ALL
SELECT second.* FROM (
  SELECT messages.`id`,messages.`json`,messages.`body`,messages.`conversationId`,messages.`expirationStartTimestamp`,messages.`expireTimer`,messages.`hasAttachments`,messages.`hasFileAttachments`,messages.`hasVisualMediaAttachments`,messages.`hasUnreadPollVotes`,messages.`isChangeCreatedByUs`,messages.`isErased`,messages.`isViewOnce`,messages.`mentionsMe`,messages.`received_at`,messages.`received_at_ms`,messages.`schemaVersion`,messages.`serverGuid`,messages.`sent_at`,messages.`source`,messages.`sourceServiceId`,messages.`sourceDevice`,messages.`storyId`,messages.`type`,messages.`readStatus`,messages.`seenStatus`,messages.`serverTimestamp`,messages.`timestamp`,messages.`unidentifiedDeliveryReceived`
  FROM messages WHERE
    conversationId = ?7 AND
    (?8 IS NULL OR id IS NOT ?9) AND
    isStory IS 0 AND
    (storyId IS ?10) AND
    ( received_at < ?11 )
    ORDER BY received_at DESC, sent_at DESC
) as second
LIMIT ?12;

-- @id signal-desktop.stories.recent_replies
-- @src ts/sql/Server.node.ts:4014-4053
-- @style sql`` positional
-- @tags hotpath
-- @note Replies to one story, newest first: two-branch UNION ALL with ORDER BY on the compound and LIMIT.
-- @param ?1 NULL
-- @param ?2 NULL
-- @param ?3 'msg-0000057'
-- @param ?4 1.7976931348623157e308
-- @param ?5 1.7976931348623157e308
-- @param ?6 NULL
-- @param ?7 NULL
-- @param ?8 'msg-0000057'
-- @param ?9 1.7976931348623157e308
-- @param ?10 100
SELECT first.* FROM (
  SELECT messages.`id`,messages.`json`,messages.`body`,messages.`conversationId`,messages.`expirationStartTimestamp`,messages.`expireTimer`,messages.`hasAttachments`,messages.`hasFileAttachments`,messages.`hasVisualMediaAttachments`,messages.`hasUnreadPollVotes`,messages.`isChangeCreatedByUs`,messages.`isErased`,messages.`isViewOnce`,messages.`mentionsMe`,messages.`received_at`,messages.`received_at_ms`,messages.`schemaVersion`,messages.`serverGuid`,messages.`sent_at`,messages.`source`,messages.`sourceServiceId`,messages.`sourceDevice`,messages.`storyId`,messages.`type`,messages.`readStatus`,messages.`seenStatus`,messages.`serverTimestamp`,messages.`timestamp`,messages.`unidentifiedDeliveryReceived`
  FROM messages
  WHERE (?1 IS NULL OR id IS NOT ?2) AND isStory IS 0 AND storyId IS ?3 AND
    ( received_at = ?4 AND sent_at < ?5 )
) as first
UNION ALL
SELECT second.* FROM (
  SELECT messages.`id`,messages.`json`,messages.`body`,messages.`conversationId`,messages.`expirationStartTimestamp`,messages.`expireTimer`,messages.`hasAttachments`,messages.`hasFileAttachments`,messages.`hasVisualMediaAttachments`,messages.`hasUnreadPollVotes`,messages.`isChangeCreatedByUs`,messages.`isErased`,messages.`isViewOnce`,messages.`mentionsMe`,messages.`received_at`,messages.`received_at_ms`,messages.`schemaVersion`,messages.`serverGuid`,messages.`sent_at`,messages.`source`,messages.`sourceServiceId`,messages.`sourceDevice`,messages.`storyId`,messages.`type`,messages.`readStatus`,messages.`seenStatus`,messages.`serverTimestamp`,messages.`timestamp`,messages.`unidentifiedDeliveryReceived`
  FROM messages
  WHERE (?6 IS NULL OR id IS NOT ?7) AND isStory IS 0 AND storyId IS ?8 AND
    ( received_at < ?9 )
) as second
ORDER BY received_at DESC, sent_at DESC
LIMIT ?10;

-- @id signal-desktop.conversation.last_activity
-- @src ts/sql/Server.node.ts:4371-4406
-- @style $name, dynamic (includeStoryReplies = false adds the storyId predicate)
-- @tags hotpath,dynamic
-- @note Left-pane timestamp: INDEXED BY a 6-column index over generated columns (shouldAffectActivity, isTimerChangeFromSync, isGroupLeaveEventFromOther), top-1.
-- @param $conversationId 'conv-0005'
SELECT id, json, body, conversationId, expirationStartTimestamp, expireTimer, hasAttachments, hasFileAttachments, hasVisualMediaAttachments, hasUnreadPollVotes, isChangeCreatedByUs, isErased, isViewOnce, mentionsMe, received_at, received_at_ms, schemaVersion, serverGuid, sent_at, source, sourceServiceId, sourceDevice, storyId, type, readStatus, seenStatus, serverTimestamp, timestamp, unidentifiedDeliveryReceived FROM messages
INDEXED BY messages_activity
WHERE
  conversationId IS $conversationId AND
  shouldAffectActivity IS 1 AND
  isTimerChangeFromSync IS 0 AND
  storyId IS NULL AND
  isGroupLeaveEventFromOther IS 0
ORDER BY received_at DESC, sent_at DESC
LIMIT 1;

-- @id signal-desktop.conversation.last_preview
-- @src ts/sql/Server.node.ts:4408-4447
-- @style $name, dynamic (index name and storyId predicate depend on includeStoryReplies)
-- @tags hotpath,dynamic
-- @note Left-pane preview: ordered subquery on a partial index, then likely(expiresAt > $now) over the generated expiresAt column, LIMIT 1.
-- @param $conversationId 'conv-0005'
-- @param $now 1702000000000
SELECT id, json, body, conversationId, expirationStartTimestamp, expireTimer, hasAttachments, hasFileAttachments, hasVisualMediaAttachments, hasUnreadPollVotes, isChangeCreatedByUs, isErased, isViewOnce, mentionsMe, received_at, received_at_ms, schemaVersion, serverGuid, sent_at, source, sourceServiceId, sourceDevice, storyId, type, readStatus, seenStatus, serverTimestamp, timestamp, unidentifiedDeliveryReceived, expiresAt FROM (
  SELECT id, json, body, conversationId, expirationStartTimestamp, expireTimer, hasAttachments, hasFileAttachments, hasVisualMediaAttachments, hasUnreadPollVotes, isChangeCreatedByUs, isErased, isViewOnce, mentionsMe, received_at, received_at_ms, schemaVersion, serverGuid, sent_at, source, sourceServiceId, sourceDevice, storyId, type, readStatus, seenStatus, serverTimestamp, timestamp, unidentifiedDeliveryReceived, expiresAt FROM messages
  INDEXED BY messages_preview_without_story
  WHERE
    conversationId IS $conversationId AND
    shouldAffectPreview IS 1 AND
    isGroupLeaveEventFromOther IS 0
    AND storyId IS NULL
  ORDER BY received_at DESC, sent_at DESC
)
WHERE likely(expiresAt > $now)
LIMIT 1;

-- @id signal-desktop.conversation.has_user_initiated
-- @src ts/sql/Server.node.ts:2385-2407
-- @style $name
-- @tags hotpath,hot-small
-- @note EXISTS probe on a generated-column index, run whenever a 1:1 conversation opens.
-- @param $conversationId 'conv-0001'
SELECT EXISTS(
  SELECT 1 FROM messages
  INDEXED BY message_user_initiated
  WHERE
    conversationId IS $conversationId AND
    isUserInitiatedMessage IS 1
);

-- @id signal-desktop.unread.total_unread
-- @src ts/sql/Server.node.ts:4558-4584
-- @style sql`` positional; ReadStatus.Unread bound as a parameter
-- @tags hotpath
-- @note Unread badge count for the open conversation (story replies excluded).
-- @param ?1 'conv-0005'
-- @param ?2 1
-- @param ?3 NULL
SELECT count(1)
FROM messages
WHERE
  conversationId = ?1 AND
  readStatus = ?2 AND
  isStory IS 0 AND
  (storyId IS ?3);

-- @id signal-desktop.unread.oldest_unseen
-- @src ts/sql/Server.node.ts:4504-4534
-- @style sql`` positional
-- @tags hotpath,hot-small
-- @note Scroll anchor when opening a conversation: oldest unseen message, top-1 ascending.
-- @param ?1 'conv-0005'
-- @param ?2 1
-- @param ?3 NULL
SELECT received_at, sent_at, id FROM messages WHERE
  conversationId = ?1 AND
  seenStatus = ?2 AND
  isStory IS 0 AND
  (storyId IS ?3)
ORDER BY received_at ASC, sent_at ASC
LIMIT 1;

-- @id signal-desktop.unread.select_unseen
-- @src ts/sql/Server.node.ts:3699-3711
-- @style sql`` positional; index name chosen at runtime
-- @tags hotpath,dynamic
-- @note Mark-read, step 3: every unseen message up to the read position via INDEXED BY messages_unseen_with_story.
-- @param ?1 'conv-0001'
-- @param ?2 1
-- @param ?3 NULL
-- @param ?4 1060000
SELECT id, readStatus, expirationStartTimestamp, sent_at, source, sourceServiceId, type
FROM messages
INDEXED BY messages_unseen_with_story
WHERE
  conversationId = ?1 AND
  seenStatus = ?2 AND
  isStory = 0 AND
  storyId IS ?3 AND
  received_at <= ?4
ORDER BY received_at DESC, sent_at DESC;

-- @id signal-desktop.unread.mark_read
-- @src ts/sql/Server.node.ts:3731-3745
-- @style sql`` positional; index name chosen at runtime
-- @tags hotpath,dynamic
-- @note Mark-read, step 4: flips readStatus/seenStatus through INDEXED BY; the messages_on_update triggers' WHEN clauses evaluate per row.
-- @param ?1 0
-- @param ?2 2
-- @param ?3 'conv-0001'
-- @param ?4 1
-- @param ?5 NULL
-- @param ?6 1060000
UPDATE messages
  INDEXED BY messages_unseen_with_story
  SET
    readStatus = ?1,
    seenStatus = ?2
  WHERE
    conversationId = ?3 AND
    seenStatus = ?4 AND
    isStory = 0 AND
    storyId IS ?5 AND
    received_at <= ?6;

-- @id signal-desktop.unread.start_expiration
-- @src ts/sql/Server.node.ts:3662-3685
-- @style sql`` positional
-- @tags hotpath,dynamic
-- @note Mark-read, step 1: start disappearing-message timers via a partial index on the generated hasExpireTimer column.
-- @param ?1 1702300000000
-- @param ?2 'conv-0006'
-- @param ?3 NULL
-- @param ?4 1060000
UPDATE messages
INDEXED BY messages_conversationId_expirationStartTimestamp
SET
  expirationStartTimestamp = ?1
WHERE
  conversationId = ?2 AND
  storyId IS ?3 AND
  type IS NOT 'outgoing' AND
  type IS NOT 'call-history' AND
  hasExpireTimer IS 1 AND
  received_at <= ?4 AND
  expirationStartTimestamp IS NULL;

-- @id signal-desktop.unread.reactions_mark_read
-- @src ts/sql/Server.node.ts:3768-3804
-- @style $name
-- @tags hotpath
-- @note UPDATE ... RETURNING with a correlated EXISTS into messages, forced onto reactions_unread.
-- @param $conversationId 'conv-0001'
-- @param $readMessageReceivedAt 1060000
-- @param $storyId NULL
UPDATE reactions
INDEXED BY reactions_unread
SET unread = 0
WHERE
  conversationId = $conversationId AND
  unread >= 1 AND
  EXISTS (
    SELECT 1
    FROM messages
    WHERE messages.id = reactions.messageId
      AND messages.received_at <= $readMessageReceivedAt
      AND messages.storyId IS $storyId
  )
RETURNING targetAuthorAci, targetTimestamp, messageId;

-- @id signal-desktop.calls.history_groups_page
-- @src ts/sql/Server.node.ts:5239-5457
-- @style sql`` positional, dynamic (status All, no peer filter so no temp-table join); constants inlined by sqlConstant
-- @tags hotpath,dynamic
-- @note Calls tab: CTE with three correlated subqueries per call (possibleParent, JSON_GROUP_ARRAY of possibleChildren, GROUP_CONCAT inPeriod), LAG() window to find group parents, GROUP BY CASE, top-N.
-- @param ?1 50
-- @param ?2 0
SELECT
  peerId, ringerId, mode, type, direction, status, timestamp, possibleChildren, inPeriod
FROM (
  WITH callAndGroupInfo AS (
    SELECT
      *,
      (
        SELECT callId
        FROM callsHistory
        WHERE
          callsHistory.direction IS c.direction
          AND callsHistory.type IS c.type
          AND callsHistory.peerId IS c.peerId
          AND (callsHistory.timestamp - 14400000) <= c.timestamp
          AND callsHistory.timestamp >= c.timestamp
          AND (
            (callsHistory.status IS c.status AND callsHistory.status IS 'Missed') OR
            (callsHistory.status IS NOT 'Missed' AND c.status IS NOT 'Missed')
          )
          AND callsHistory.status IS c.status
          AND status IS NOT 'Deleted'
        ORDER BY timestamp DESC
      ) as possibleParent,
      (
        SELECT JSON_GROUP_ARRAY(
          JSON_OBJECT(
            'callId', callsHistory.callId,
            'timestamp', callsHistory.timestamp
          )
        )
        FROM callsHistory
        WHERE
          callsHistory.direction IS c.direction
          AND callsHistory.type IS c.type
          AND callsHistory.peerId IS c.peerId
          AND (c.timestamp - 14400000) <= callsHistory.timestamp
          AND c.timestamp >= callsHistory.timestamp
          AND (
            (callsHistory.status IS c.status AND callsHistory.status IS 'Missed') OR
            (callsHistory.status IS NOT 'Missed' AND c.status IS NOT 'Missed')
          )
          AND callsHistory.status IS c.status
          AND status IS NOT 'Deleted'
        ORDER BY callsHistory.timestamp DESC
      ) as possibleChildren,
      (
        SELECT GROUP_CONCAT(callId)
        FROM callsHistory
        WHERE
          (c.timestamp - 14400000) <= callsHistory.timestamp
          AND c.timestamp >= callsHistory.timestamp
          AND status IS NOT 'Deleted'
      ) AS inPeriod
    FROM callsHistory AS c
    WHERE
      status IS NOT 'Deleted'
    ORDER BY timestamp DESC
  )
  SELECT
    *,
    CASE
      WHEN LAG (possibleParent, 1, 0) OVER (
      ) != possibleParent THEN callId
      ELSE possibleParent
    END AS parent
  FROM callAndGroupInfo
) AS parentCallAndGroupInfo
WHERE parent = parentCallAndGroupInfo.callId
GROUP BY
  CASE
    WHEN mode IS 'Adhoc' THEN peerId
    ELSE callId
  END
ORDER BY parentCallAndGroupInfo.timestamp DESC
LIMIT ?1 OFFSET ?2;

-- @id signal-desktop.calls.missed_groups_count
-- @src ts/sql/Server.node.ts:5239-5485
-- @style sql`` positional, dynamic (isCount, status Missed filter, no LIMIT)
-- @tags hotpath,dynamic
-- @note Missed-calls badge: the same grouping query with the missed-incoming filter and COUNT(*) OVER() as the projection.
SELECT
  COUNT(*) OVER() AS count
FROM (
  WITH callAndGroupInfo AS (
    SELECT
      *,
      (
        SELECT callId
        FROM callsHistory
        WHERE
          callsHistory.direction IS c.direction
          AND callsHistory.type IS c.type
          AND callsHistory.peerId IS c.peerId
          AND (callsHistory.timestamp - 14400000) <= c.timestamp
          AND callsHistory.timestamp >= c.timestamp
          AND (
            (callsHistory.status IS c.status AND callsHistory.status IS 'Missed') OR
            (callsHistory.status IS NOT 'Missed' AND c.status IS NOT 'Missed')
          )
          AND callsHistory.status IS c.status
          AND direction IS 'Incoming' AND
            status IS 'Missed' AND status IS NOT 'Deleted'
        ORDER BY timestamp DESC
      ) as possibleParent,
      (
        SELECT JSON_GROUP_ARRAY(
          JSON_OBJECT(
            'callId', callsHistory.callId,
            'timestamp', callsHistory.timestamp
          )
        )
        FROM callsHistory
        WHERE
          callsHistory.direction IS c.direction
          AND callsHistory.type IS c.type
          AND callsHistory.peerId IS c.peerId
          AND (c.timestamp - 14400000) <= callsHistory.timestamp
          AND c.timestamp >= callsHistory.timestamp
          AND (
            (callsHistory.status IS c.status AND callsHistory.status IS 'Missed') OR
            (callsHistory.status IS NOT 'Missed' AND c.status IS NOT 'Missed')
          )
          AND callsHistory.status IS c.status
          AND direction IS 'Incoming' AND
            status IS 'Missed' AND status IS NOT 'Deleted'
        ORDER BY callsHistory.timestamp DESC
      ) as possibleChildren,
      (
        SELECT GROUP_CONCAT(callId)
        FROM callsHistory
        WHERE
          (c.timestamp - 14400000) <= callsHistory.timestamp
          AND c.timestamp >= callsHistory.timestamp
          AND direction IS 'Incoming' AND
            status IS 'Missed' AND status IS NOT 'Deleted'
      ) AS inPeriod
    FROM callsHistory AS c
    WHERE
      direction IS 'Incoming' AND
      status IS 'Missed' AND status IS NOT 'Deleted'
    ORDER BY timestamp DESC
  )
  SELECT
    *,
    CASE
      WHEN LAG (possibleParent, 1, 0) OVER (
      ) != possibleParent THEN callId
      ELSE possibleParent
    END AS parent
  FROM callAndGroupInfo
) AS parentCallAndGroupInfo
WHERE parent = parentCallAndGroupInfo.callId
GROUP BY
  CASE
    WHEN mode IS 'Adhoc' THEN peerId
    ELSE callId
  END
ORDER BY parentCallAndGroupInfo.timestamp DESC;

-- @id signal-desktop.calls.unread_counts_by_conversation
-- @src ts/sql/Server.node.ts:4895-4916
-- @style sql`` positional; constants inlined by sqlConstant
-- @tags hotpath
-- @note Per-conversation unread call badges: join on the generated messages.callId column, GROUP BY conversation.
SELECT messages.conversationId, count(*) AS unreadCount FROM messages
INNER JOIN callsHistory ON callsHistory.callId = messages.callId
WHERE messages.type IS 'call-history'
  AND messages.seenStatus IS 1
  AND callsHistory.direction IS 'Incoming'
GROUP BY messages.conversationId;

-- @id signal-desktop.media.older_visual
-- @src ts/sql/Server.node.ts:5680-5860
-- @style sql`` positional, dynamic (order 'older', type 'media')
-- @tags hotpath,dynamic
-- @note Media gallery page: two-branch UNION ALL over message_attachments INDEXED BY a partial index, LIKE content filters, JSON -> extraction from the joined message.
-- @param ?1 'conv-0005'
-- @param ?2 1.7976931348623157e308
-- @param ?3 1.7976931348623157e308
-- @param ?4 NULL
-- @param ?5 NULL
-- @param ?6 50
-- @param ?7 'conv-0005'
-- @param ?8 1.7976931348623157e308
-- @param ?9 NULL
-- @param ?10 NULL
-- @param ?11 50
SELECT first.* FROM (
  SELECT
    message_attachments.*,
    messages.json -> '$.sendStateByConversationId' AS messageSendState,
    messages.json -> '$.errors' AS messageErrors,
    messages.isErased AS messageIsErased,
    messages.readStatus AS messageReadStatus,
    messages.source AS messageSource,
    messages.sourceServiceId AS messageSourceServiceId
  FROM message_attachments
  INDEXED BY message_attachments_getOlderMedia
  INNER JOIN messages ON
    messages.id = message_attachments.messageId
  WHERE
    message_attachments.conversationId IS ?1 AND
    message_attachments.editHistoryIndex IS -1 AND
    message_attachments.attachmentType IS 'attachment' AND
    (
      message_attachments.receivedAt = ?2
      AND
      message_attachments.sentAt < ?3
    ) AND
    (message_attachments.flags IS NOT 1 AND
      (
        message_attachments.contentType LIKE 'image/%' OR
        message_attachments.contentType LIKE 'video/%'
      )) AND
    message_attachments.isViewOnce IS NOT 1 AND
    message_attachments.messageType IN ('incoming', 'outgoing') AND
    (?4 IS NULL OR message_attachments.messageId IS NOT ?5)
    ORDER BY message_attachments.receivedAt DESC, message_attachments.sentAt DESC
    LIMIT ?6
) as first
UNION ALL
SELECT second.* FROM (
  SELECT
    message_attachments.*,
    messages.json -> '$.sendStateByConversationId' AS messageSendState,
    messages.json -> '$.errors' AS messageErrors,
    messages.isErased AS messageIsErased,
    messages.readStatus AS messageReadStatus,
    messages.source AS messageSource,
    messages.sourceServiceId AS messageSourceServiceId
  FROM message_attachments
  INDEXED BY message_attachments_getOlderMedia
  INNER JOIN messages ON
    messages.id = message_attachments.messageId
  WHERE
    message_attachments.conversationId IS ?7 AND
    message_attachments.editHistoryIndex IS -1 AND
    message_attachments.attachmentType IS 'attachment' AND
    (message_attachments.receivedAt < ?8) AND
    (message_attachments.flags IS NOT 1 AND
      (
        message_attachments.contentType LIKE 'image/%' OR
        message_attachments.contentType LIKE 'video/%'
      )) AND
    message_attachments.isViewOnce IS NOT 1 AND
    message_attachments.messageType IN ('incoming', 'outgoing') AND
    (?9 IS NULL OR message_attachments.messageId IS NOT ?10)
    ORDER BY message_attachments.receivedAt DESC, message_attachments.sentAt DESC
    LIMIT ?11
) as second;

-- @id signal-desktop.media.links
-- @src ts/sql/Server.node.ts:5894-5940
-- @style sql`` positional, dynamic (type 'links')
-- @tags dynamic
-- @note Links tab: partial index over the generated hasPreviews column (json_array_length of $.preview), two-branch UNION ALL.
-- @param ?1 'conv-0001'
-- @param ?2 NULL
-- @param ?3 NULL
-- @param ?4 1.7976931348623157e308
-- @param ?5 1.7976931348623157e308
-- @param ?6 30
-- @param ?7 'conv-0001'
-- @param ?8 NULL
-- @param ?9 NULL
-- @param ?10 1.7976931348623157e308
-- @param ?11 30
SELECT first.* FROM (
  SELECT messages.`id`,messages.`json`,messages.`body`,messages.`conversationId`,messages.`expirationStartTimestamp`,messages.`expireTimer`,messages.`hasAttachments`,messages.`hasFileAttachments`,messages.`hasVisualMediaAttachments`,messages.`hasUnreadPollVotes`,messages.`isChangeCreatedByUs`,messages.`isErased`,messages.`isViewOnce`,messages.`mentionsMe`,messages.`received_at`,messages.`received_at_ms`,messages.`schemaVersion`,messages.`serverGuid`,messages.`sent_at`,messages.`source`,messages.`sourceServiceId`,messages.`sourceDevice`,messages.`storyId`,messages.`type`,messages.`readStatus`,messages.`seenStatus`,messages.`serverTimestamp`,messages.`timestamp`,messages.`unidentifiedDeliveryReceived`
  FROM messages
  INDEXED BY messages_hasPreviews
  WHERE
    conversationId IS ?1 AND
    (hasPreviews IS 1) AND
    isViewOnce IS NOT 1 AND
    type IN ('incoming', 'outgoing') AND
    (?2 IS NULL OR id IS NOT ?3)
    AND (received_at = ?4 AND sent_at < ?5)
    ORDER BY received_at DESC, sent_at DESC
    LIMIT ?6
) as first
UNION ALL
SELECT second.* FROM (
  SELECT messages.`id`,messages.`json`,messages.`body`,messages.`conversationId`,messages.`expirationStartTimestamp`,messages.`expireTimer`,messages.`hasAttachments`,messages.`hasFileAttachments`,messages.`hasVisualMediaAttachments`,messages.`hasUnreadPollVotes`,messages.`isChangeCreatedByUs`,messages.`isErased`,messages.`isViewOnce`,messages.`mentionsMe`,messages.`received_at`,messages.`received_at_ms`,messages.`schemaVersion`,messages.`serverGuid`,messages.`sent_at`,messages.`source`,messages.`sourceServiceId`,messages.`sourceDevice`,messages.`storyId`,messages.`type`,messages.`readStatus`,messages.`seenStatus`,messages.`serverTimestamp`,messages.`timestamp`,messages.`unidentifiedDeliveryReceived`
  FROM messages
  INDEXED BY messages_hasPreviews
  WHERE
    conversationId IS ?7 AND
    (hasPreviews IS 1) AND
    isViewOnce IS NOT 1 AND
    type IN ('incoming', 'outgoing') AND
    (?8 IS NULL OR id IS NOT ?9)
    AND (received_at < ?10)
    ORDER BY received_at DESC, sent_at DESC
    LIMIT ?11
) as second;

-- @id signal-desktop.hydrate.attachments_for_page
-- @src ts/sql/hydration.std.ts:145-148
-- @style sql`` positional, dynamic IN list (batched by batchMultiVarQuery)
-- @tags hotpath,hot-small,dynamic
-- @note Runs after every message page load to attach normalised attachments; 20 primary-key prefix probes.
SELECT * FROM message_attachments
WHERE messageId IN ('msg-0059282','msg-0059251','msg-0059237','msg-0059083','msg-0059069','msg-0059055','msg-0059052','msg-0059038','msg-0059024','msg-0058870','msg-0058853','msg-0058839','msg-0058825','msg-0058808','msg-0058794','msg-0058640','msg-0058626','msg-0057669','msg-0057591','msg-0057560');

-- @id signal-desktop.messages.get_by_id
-- @src ts/sql/Server.node.ts:3467-3487
-- @style $name
-- @tags hotpath,hot-small
-- @note Point lookup by message id on the UNIQUE index.
-- @param $id 'msg-0041234'
SELECT id, json, body, conversationId, expirationStartTimestamp, expireTimer, hasAttachments, hasFileAttachments, hasVisualMediaAttachments, hasUnreadPollVotes, isChangeCreatedByUs, isErased, isViewOnce, mentionsMe, received_at, received_at_ms, schemaVersion, serverGuid, sent_at, source, sourceServiceId, sourceDevice, storyId, type, readStatus, seenStatus, serverTimestamp, timestamp, unidentifiedDeliveryReceived
FROM messages
WHERE id = $id;

-- @id signal-desktop.messages.by_author_sent_at_with_edits
-- @src ts/sql/Server.node.ts:3547-3603
-- @style sql`` positional, dynamic (includeEdits = true, sender is not us)
-- @tags hotpath,dynamic
-- @note Receipt/reaction target lookup: UNION (with dedup) of edited_messages JOIN messages and messages by sent_at, LIMIT 2.
-- @param ?1 '00000098-0000-4000-8000-000000000152'
-- @param ?2 1700003657632
-- @param ?3 '00000098-0000-4000-8000-000000000152'
-- @param ?4 1700003657632
SELECT messages.`id`,messages.`json`,messages.`body`,messages.`conversationId`,messages.`expirationStartTimestamp`,messages.`expireTimer`,messages.`hasAttachments`,messages.`hasFileAttachments`,messages.`hasVisualMediaAttachments`,messages.`hasUnreadPollVotes`,messages.`isChangeCreatedByUs`,messages.`isErased`,messages.`isViewOnce`,messages.`mentionsMe`,messages.`received_at`,messages.`received_at_ms`,messages.`schemaVersion`,messages.`serverGuid`,messages.`sent_at`,messages.`source`,messages.`sourceServiceId`,messages.`sourceDevice`,messages.`storyId`,messages.`type`,messages.`readStatus`,messages.`seenStatus`,messages.`serverTimestamp`,messages.`timestamp`,messages.`unidentifiedDeliveryReceived`
FROM edited_messages
INNER JOIN messages ON
  messages.id = edited_messages.messageId
WHERE (messages.sourceServiceId = ?1)
  AND edited_messages.sentAt = ?2
UNION
SELECT messages.`id`,messages.`json`,messages.`body`,messages.`conversationId`,messages.`expirationStartTimestamp`,messages.`expireTimer`,messages.`hasAttachments`,messages.`hasFileAttachments`,messages.`hasVisualMediaAttachments`,messages.`hasUnreadPollVotes`,messages.`isChangeCreatedByUs`,messages.`isErased`,messages.`isViewOnce`,messages.`mentionsMe`,messages.`received_at`,messages.`received_at_ms`,messages.`schemaVersion`,messages.`serverGuid`,messages.`sent_at`,messages.`source`,messages.`sourceServiceId`,messages.`sourceDevice`,messages.`storyId`,messages.`type`,messages.`readStatus`,messages.`seenStatus`,messages.`serverTimestamp`,messages.`timestamp`,messages.`unidentifiedDeliveryReceived`
FROM messages
WHERE (messages.sourceServiceId = ?3)
  AND messages.sent_at = ?4
LIMIT 2;

-- @id signal-desktop.messages.insert
-- @src ts/sql/Server.node.ts:3364-3376
-- @style $name
-- @tags hotpath,hot-small
-- @note New incoming message: 29-column insert into a table with ~40 indexes and generated columns; the FTS5 and mentions triggers fire.
-- @param $id 'msg-9000001'
-- @param $json '{"id":"msg-9000001","conversationId":"conv-0005","type":"incoming","body":"pizza tonight at 8, garden?","bodyRanges":[{"start":0,"length":1,"mentionAci":"aaaaaaaa-0000-4000-8000-000000000000"}],"sent_at":1702400000000,"timestamp":1702400000000}'
-- @param $body 'pizza tonight at 8, garden?'
-- @param $conversationId 'conv-0005'
-- @param $expirationStartTimestamp NULL
-- @param $expireTimer NULL
-- @param $hasAttachments 0
-- @param $hasFileAttachments 0
-- @param $hasVisualMediaAttachments 0
-- @param $hasUnreadPollVotes 0
-- @param $isChangeCreatedByUs 0
-- @param $isErased 0
-- @param $isViewOnce 0
-- @param $mentionsMe 1
-- @param $received_at 1070001
-- @param $received_at_ms 1702400000500
-- @param $schemaVersion 14
-- @param $serverGuid 'guid-9000001'
-- @param $sent_at 1702400000000
-- @param $source '+15550000012'
-- @param $sourceServiceId '0000000c-0000-4000-8000-000000000012'
-- @param $sourceDevice 1
-- @param $storyId NULL
-- @param $type 'incoming'
-- @param $readStatus 1
-- @param $seenStatus 1
-- @param $serverTimestamp 1702400000100
-- @param $timestamp 1702400000000
-- @param $unidentifiedDeliveryReceived 1
INSERT INTO messages (
  id, json, body, conversationId, expirationStartTimestamp, expireTimer, hasAttachments, hasFileAttachments, hasVisualMediaAttachments, hasUnreadPollVotes, isChangeCreatedByUs, isErased, isViewOnce, mentionsMe, received_at, received_at_ms, schemaVersion, serverGuid, sent_at, source, sourceServiceId, sourceDevice, storyId, type, readStatus, seenStatus, serverTimestamp, timestamp, unidentifiedDeliveryReceived
) VALUES (
  $id, $json, $body, $conversationId, $expirationStartTimestamp, $expireTimer, $hasAttachments, $hasFileAttachments, $hasVisualMediaAttachments, $hasUnreadPollVotes, $isChangeCreatedByUs, $isErased, $isViewOnce, $mentionsMe, $received_at, $received_at_ms, $schemaVersion, $serverGuid, $sent_at, $source, $sourceServiceId, $sourceDevice, $storyId, $type, $readStatus, $seenStatus, $serverTimestamp, $timestamp, $unidentifiedDeliveryReceived
);

-- @id signal-desktop.reactions.insert
-- @src ts/sql/Server.node.ts:3936-3958
-- @style $name
-- @tags hotpath,hot-small
-- @note Reaction insert into a table with four secondary indexes.
-- @param $conversationId 'conv-0005'
-- @param $emoji '👍'
-- @param $fromId 'conv-0012'
-- @param $messageId 'msg-0059282'
-- @param $messageReceivedAt 1059282
-- @param $targetAuthorAci '00000020-0000-4000-8000-000000000032'
-- @param $targetTimestamp 1701185643291
-- @param $timestamp 1702400000000
-- @param $unread 1
INSERT INTO reactions (
  conversationId, emoji, fromId, messageId, messageReceivedAt, targetAuthorAci, targetTimestamp, timestamp, unread
) VALUES (
  $conversationId, $emoji, $fromId, $messageId, $messageReceivedAt, $targetAuthorAci, $targetTimestamp, $timestamp, $unread
);

-- @id signal-desktop.conversations.get_by_id
-- @src ts/sql/Server.node.ts:2109-2128
-- @style $name
-- @tags hotpath,hot-small
-- @note Point lookup on the conversations primary key.
-- @param $id 'conv-0042'
SELECT json, profileLastFetchedAt, expireTimerVersion
FROM conversations
WHERE id = $id;

-- @id signal-desktop.reminders.unreminded_time_ranges
-- @src ts/sql/server/unreadReminders.std.ts:47-67
-- @style sql`` positional, dynamic VALUES list (batched by batchMultiVarQuery)
-- @tags dynamic
-- @note Unread-reminder scan: VALUES CTE joined with IS against messages, per-candidate cutoff and story-reply switch, MIN/MAX grouped by conversation.
-- @param ?1 'conv-0001'
-- @param ?2 1701100000000
-- @param ?3 0
-- @param ?4 'conv-0005'
-- @param ?5 NULL
-- @param ?6 1
-- @param ?7 'conv-0030'
-- @param ?8 1700500000000
-- @param ?9 0
WITH cutoffs(conversationId, lastRemindedAt, includeStoryReplies) AS (
  VALUES (?1, ?2, ?3),(?4, ?5, ?6),(?7, ?8, ?9)
)
SELECT
  messages.conversationId AS conversationId,
  MIN(messages.received_at_ms) AS oldestUnremindedReceivedAtMs,
  MAX(messages.received_at_ms) AS newestUnreadReceivedAtMs
FROM messages
INNER JOIN cutoffs ON cutoffs.conversationId IS messages.conversationId
WHERE
  messages.readStatus = 1 AND
  messages.isStory IS 0 AND
  (cutoffs.includeStoryReplies IS 1 OR messages.storyId IS NULL) AND
  messages.received_at_ms > IFNULL(cutoffs.lastRemindedAt, 0)
GROUP BY messages.conversationId;

-- @id signal-desktop.mentions.backfill
-- @src ts/sql/Server.node.ts:9800-9806
-- @style plain exec; selectMentionsFromMessages from Server.node.ts:9744-9750
-- @tags batch
-- @note Rebuilds mentions after a bulk import (the app runs DELETE FROM mentions first): json_each over every message's bodyRanges with ->> extraction.
INSERT INTO mentions (messageId, mentionAci, start, length)
SELECT messages.id, bodyRanges.value ->> 'mentionAci' as mentionAci,
  bodyRanges.value ->> 'start' as start,
  bodyRanges.value ->> 'length' as length
FROM messages, json_each(messages.json ->> 'bodyRanges') as bodyRanges
WHERE bodyRanges.value ->> 'mentionAci' IS NOT NULL;

-- @id signal-desktop.attachments.next_download_jobs
-- @src ts/sql/Server.node.ts:6667-6680
-- @style sql`` positional, dynamic (sources filter given)
-- @tags hotpath,dynamic
-- @note Download queue poll: inactive jobs whose retryAfter passed, source IN list, newest first, LIMIT.
-- @param ?1 1700600000000
-- @param ?2 'standard'
-- @param ?3 'backup_thumbnail'
-- @param ?4 20
SELECT * FROM attachment_downloads
WHERE
  active = 0
AND
  (retryAfter is NULL OR retryAfter <= ?1)
AND
  source IN (?2,?3)
ORDER BY receivedAt DESC
LIMIT ?4;

