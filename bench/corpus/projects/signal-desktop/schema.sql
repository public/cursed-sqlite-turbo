-- signalapp/Signal-Desktop @ 17502b9d1a9e34af689f31508c4ac4ccee5b5cb7 (AGPL-3.0-only).
-- Final shape of the tables the queries need, reconstructed by replaying ts/sql/migrations/index.node.ts
-- (versions 1-40) and ts/sql/migrations/<N>-*.ts in order, then copying out only these tables' CREATE
-- statements. Signal's SQLCipher build is replaced by stock SQLite:
--   * messages_fts uses tokenize='unicode61' instead of Signal's custom 'signal_tokenizer'
--     (migration 77-signal-tokenizer.std.ts), which only exists in @signalapp/sqlcipher.
-- Triggers are the final versions: messages_on_insert/messages_on_update from 1500-search-polls.std.ts,
-- messages_on_delete from 45-stories.std.ts (its sendLogPayloads clause is dropped because the send-log
-- tables are not included), messages_on_view_once_update from index.node.ts (version 27), and
-- messages_on_insert_insert_mentions from Server.node.ts enableMessageInsertTriggersAndBackfill.

CREATE TABLE conversations(
      id STRING PRIMARY KEY ASC,
      json TEXT,

      active_at INTEGER,
      type STRING,
      members TEXT,
      name TEXT,
      profileName TEXT
    , profileFamilyName TEXT, profileFullName TEXT, e164 TEXT, serviceId TEXT, groupId TEXT, profileLastFetchedAt INTEGER, expireTimerVersion INTEGER NOT NULL DEFAULT 1);
CREATE INDEX conversations_active ON conversations (
      active_at
    ) WHERE active_at IS NOT NULL;
CREATE INDEX conversations_type ON conversations (
      type
    ) WHERE type IS NOT NULL;
CREATE INDEX conversations_e164 ON conversations(e164);
CREATE INDEX conversations_groupId ON conversations(groupId);
CREATE INDEX conversations_serviceId ON conversations(serviceId);

CREATE TABLE messages(
      rowid INTEGER PRIMARY KEY ASC,
      id STRING UNIQUE,
      json TEXT,
      readStatus INTEGER,
      expires_at INTEGER,
      sent_at INTEGER,
      schemaVersion INTEGER,
      conversationId STRING,
      received_at INTEGER,
      hasAttachments INTEGER,
      hasFileAttachments INTEGER,
      hasVisualMediaAttachments INTEGER,
      expireTimer INTEGER,
      expirationStartTimestamp INTEGER,
      type STRING,
      body TEXT,
      messageTimer INTEGER,
      messageTimerStart INTEGER,
      messageTimerExpiresAt INTEGER,
      isErased INTEGER,
      isViewOnce INTEGER,
      sourceServiceId TEXT, serverGuid STRING NULL, sourceDevice INTEGER, storyId STRING, isStory INTEGER
      GENERATED ALWAYS AS (type IS 'story'), isChangeCreatedByUs INTEGER NOT NULL DEFAULT 0, isTimerChangeFromSync INTEGER
      GENERATED ALWAYS AS (
        json_extract(json, '$.expirationTimerUpdate.fromSync') IS 1
      ), seenStatus NUMBER default 0, storyDistributionListId STRING, expiresAt INT
      GENERATED ALWAYS
      AS (ifnull(
        expirationStartTimestamp + (expireTimer * 1000),
        9007199254740991
      )), isUserInitiatedMessage INTEGER
      GENERATED ALWAYS AS (
        type IS NULL
        OR
        type NOT IN (
          'change-number-notification',
          'contact-removed-notification',
          'conversation-merge',
          'group-v1-migration',
          'group-v2-change',
          'keychange',
          'message-history-unsynced',
          'profile-change',
          'story',
          'universal-timer-notification',
          'verified-change'
        )
      ), mentionsMe INTEGER NOT NULL DEFAULT 0, isGroupLeaveEvent INTEGER
      GENERATED ALWAYS AS (
        type IS 'group-v2-change' AND
        json_array_length(json_extract(json, '$.groupV2Change.details')) IS 1 AND
        json_extract(json, '$.groupV2Change.details[0].type') IS 'member-remove' AND
        json_extract(json, '$.groupV2Change.from') IS NOT NULL AND
        json_extract(json, '$.groupV2Change.from') IS json_extract(json, '$.groupV2Change.details[0].aci')
      ), isGroupLeaveEventFromOther INTEGER
      GENERATED ALWAYS AS (
        isGroupLeaveEvent IS 1
        AND
        isChangeCreatedByUs IS 0
      ), callId TEXT
      GENERATED ALWAYS AS (
        json_extract(json, '$.callId')
      ), shouldAffectPreview INTEGER
      GENERATED ALWAYS AS (
    type IS NULL
    OR
    type NOT IN (
      'change-number-notification',
      'contact-removed-notification',
      'conversation-merge',
      'group-v1-migration',
      'keychange',
      'message-history-unsynced',
      'profile-change',
      'story',
      'universal-timer-notification',
      'verified-change'
    )
    AND NOT (
      type IS 'message-request-response-event'
      AND json_extract(json, '$.messageRequestResponseEvent') IN ('ACCEPT', 'BLOCK', 'UNBLOCK')
    )
  ), shouldAffectActivity INTEGER
      GENERATED ALWAYS AS (
    type IS NULL
    OR
    type NOT IN (
      'change-number-notification',
      'contact-removed-notification',
      'conversation-merge',
      'group-v1-migration',
      'keychange',
      'message-history-unsynced',
      'profile-change',
      'story',
      'universal-timer-notification',
      'verified-change'
    )
    AND NOT (
      type IS 'message-request-response-event'
      AND json_extract(json, '$.messageRequestResponseEvent') IN ('ACCEPT', 'BLOCK', 'UNBLOCK')
    )
  ), isAddressableMessage INTEGER
      GENERATED ALWAYS AS (
        type IS NULL
        OR
        type IN (
          'incoming',
          'outgoing'
        )
      ), timestamp INTEGER, received_at_ms INTEGER, unidentifiedDeliveryReceived INTEGER, serverTimestamp INTEGER, source TEXT, isSearchable INT 
      GENERATED ALWAYS AS (isViewOnce IS NOT 1 AND storyId IS NULL) VIRTUAL, searchableText TEXT GENERATED ALWAYS AS (
      CASE
        WHEN json->'poll' IS NOT NULL THEN json->'poll'->>'question'
        ELSE body
      END
      ) VIRTUAL, hasUnreadPollVotes INTEGER NOT NULL DEFAULT 0, hasExpireTimer INTEGER NOT NULL
    GENERATED ALWAYS AS (COALESCE(expireTimer, 0) > 0) VIRTUAL, hasPreviews INTEGER NOT NULL
      GENERATED ALWAYS AS (
        IFNULL(json_array_length(json, '$.preview'), 0) > 0
      ), hasContacts INTEGER NOT NULL
      GENERATED ALWAYS AS (
        IFNULL(json_array_length(json, '$.contact'), 0) > 0
      ));
CREATE INDEX messages_id ON messages (id ASC);
CREATE INDEX messages_receipt ON messages (sent_at);
CREATE INDEX messages_schemaVersion ON messages (schemaVersion);
CREATE INDEX messages_view_once ON messages
      (isErased) WHERE isViewOnce = 1;
CREATE INDEX messages_searchOrder on messages(received_at, sent_at);
CREATE INDEX messages_unexpectedly_missing_expiration_start_timestamp ON messages (
      expireTimer, expirationStartTimestamp, type
    )
    WHERE expireTimer IS NOT NULL AND expirationStartTimestamp IS NULL;
CREATE INDEX messages_hasAttachments
      ON messages (conversationId, hasAttachments, received_at)
      WHERE type IS NOT 'story' AND storyId IS NULL;
CREATE INDEX messages_hasFileAttachments
      ON messages (conversationId, hasFileAttachments, received_at)
      WHERE type IS NOT 'story' AND storyId IS NULL;
CREATE INDEX messages_conversation ON messages
      (conversationId, isStory, storyId, received_at, sent_at);
CREATE INDEX messages_unread ON messages
      (conversationId, readStatus, isStory, storyId, received_at, sent_at) WHERE readStatus IS NOT NULL;
CREATE INDEX messages_conversation_no_story_id ON messages
      (conversationId, isStory, received_at, sent_at);
CREATE INDEX messages_unread_no_story_id ON messages
      (conversationId, readStatus, isStory, received_at, sent_at)
      WHERE readStatus IS NOT NULL;
CREATE INDEX messages_unseen_no_story ON messages
      (conversationId, seenStatus, isStory, received_at, sent_at)
      WHERE
        seenStatus IS NOT NULL;
CREATE INDEX messages_unseen_with_story ON messages
      (conversationId, seenStatus, isStory, storyId, received_at, sent_at)
      WHERE
        seenStatus IS NOT NULL;
CREATE INDEX expiring_message_by_conversation_and_received_at
      ON messages
      (
        conversationId,
        storyId,
        expirationStartTimestamp,
        expireTimer,
        received_at
      )
      WHERE isStory IS 0 AND type IS 'incoming';
CREATE INDEX messages_by_distribution_list
      ON messages(storyDistributionListId, received_at)
      WHERE storyDistributionListId IS NOT NULL;
CREATE INDEX messages_by_storyId ON messages (storyId);
CREATE INDEX messages_expires_at ON messages (
      expiresAt
    );
CREATE INDEX messages_hasVisualMediaAttachments
      ON messages (
        conversationId, isStory, storyId,
        hasVisualMediaAttachments, received_at, sent_at
      )
      WHERE hasVisualMediaAttachments IS 1;
CREATE INDEX messages_unread_mentions ON messages
      (conversationId, readStatus, mentionsMe, isStory, storyId, received_at, sent_at)
      WHERE readStatus IS NOT NULL;
CREATE INDEX messages_unread_mentions_no_story_id ON messages
      (conversationId, readStatus, mentionsMe, isStory, received_at, sent_at)
      WHERE isStory IS 0 AND readStatus IS NOT NULL;
CREATE INDEX messages_story_replies
      ON messages (storyId, received_at, sent_at)
      WHERE isStory IS 0;
CREATE INDEX messages_sourceServiceId on messages(sourceServiceId);
CREATE INDEX messages_preview ON messages
      (conversationId, shouldAffectPreview, isGroupLeaveEventFromOther,
       received_at, sent_at);
CREATE INDEX messages_preview_without_story ON messages
      (conversationId, shouldAffectPreview, isGroupLeaveEventFromOther,
       received_at, sent_at) WHERE storyId IS NULL;
CREATE INDEX messages_activity ON messages
      (conversationId, shouldAffectActivity, isTimerChangeFromSync,
       isGroupLeaveEventFromOther, received_at, sent_at);
CREATE INDEX message_user_initiated ON messages (conversationId, isUserInitiatedMessage);
CREATE INDEX messages_by_date_addressable
      ON messages (
        conversationId, isAddressableMessage, received_at, sent_at
    );
CREATE INDEX messages_by_date_addressable_nondisappearing
      ON messages (
        conversationId, isAddressableMessage, received_at, sent_at
    ) WHERE expireTimer IS NULL;
CREATE INDEX messages_callHistory_seenStatus
      ON messages (type, seenStatus)
      WHERE type IS 'call-history';
CREATE INDEX messages_call ON messages
      (type, conversationId, callId, sent_at)
      WHERE type IS 'call-history';
CREATE INDEX messages_callHistory_markReadByConversationBefore
      ON messages (type, conversationId, seenStatus, sent_at DESC)
      WHERE type IS 'call-history';
CREATE INDEX messages_isStory
      ON messages(received_at, sent_at)
      WHERE isStory = 1;
CREATE INDEX messages_callHistory_markReadBefore
      ON messages (type, seenStatus, received_at DESC)
      WHERE type IS 'call-history';
CREATE INDEX messages_unread_poll_votes ON messages (
      conversationId,
      received_at
    ) WHERE hasUnreadPollVotes = 1 AND type IS 'outgoing';
CREATE INDEX messages_conversationId_expirationStartTimestamp
    ON messages (conversationId, expirationStartTimestamp)
    WHERE hasExpireTimer IS 1;
CREATE INDEX messages_hasPreviews
      ON messages (conversationId, received_at DESC, sent_at DESC)
      WHERE
        hasPreviews IS 1 AND
        isViewOnce IS NOT 1 AND
        type IN ('incoming', 'outgoing');
CREATE INDEX messages_hasContacts
      ON messages (conversationId, received_at DESC, sent_at DESC)
      WHERE
        hasContacts IS 1 AND
        isViewOnce IS NOT 1 AND
        type IN ('incoming', 'outgoing');

CREATE TABLE mentions (
      messageId REFERENCES messages(id) ON DELETE CASCADE,
      mentionAci STRING,
      start INTEGER,
      length INTEGER
    );
CREATE INDEX mentions_aci ON mentions (mentionAci);
CREATE INDEX mentions_messageId
      ON mentions(messageId);

CREATE TABLE reactions(
      conversationId STRING,
      emoji STRING,
      fromId STRING,
      messageReceivedAt INTEGER,
      targetAuthorAci STRING,
      targetTimestamp INTEGER,
      unread INTEGER
    , messageId STRING, timestamp NUMBER);
CREATE INDEX reactions_unread ON reactions (
      conversationId,
      unread
    );
CREATE INDEX reaction_identifier ON reactions (
      emoji,
      targetAuthorAci,
      targetTimestamp
    );
CREATE INDEX reactions_byTimestamp
    ON reactions
    (fromId, timestamp);
CREATE INDEX reactions_messageId
      ON reactions (messageId);

CREATE TABLE edited_messages(
      messageId STRING REFERENCES messages(id)
        ON DELETE CASCADE,
      sentAt INTEGER,
      readStatus INTEGER
    , conversationId STRING);
CREATE INDEX edited_messages_sent_at ON edited_messages (sentAt);
CREATE INDEX edited_messages_unread ON edited_messages (readStatus, conversationId);
CREATE INDEX edited_messages_messageId
      ON edited_messages(messageId);

CREATE TABLE callsHistory (
      callId TEXT PRIMARY KEY,
      peerId TEXT NOT NULL, -- conversation id (legacy) | uuid | groupId | roomId
      ringerId TEXT DEFAULT NULL, -- ringer uuid
      mode TEXT NOT NULL, -- enum "Direct" | "Group"
      type TEXT NOT NULL, -- enum "Audio" | "Video" | "Group"
      direction TEXT NOT NULL, -- enum "Incoming" | "Outgoing
      -- Direct: enum "Pending" | "Missed" | "Accepted" | "Deleted"
      -- Group: enum "GenericGroupCall" | "OutgoingRing" | "Ringing" | "Joined" | "Missed" | "Declined" | "Accepted" | "Deleted"
      status TEXT NOT NULL,
      timestamp INTEGER NOT NULL, startedById TEXT DEFAULT NULL, endedTimestamp INTEGER DEFAULT NULL,
      UNIQUE (callId, peerId) ON CONFLICT FAIL
    );
CREATE INDEX callsHistory_callAndGroupInfo_optimize on callsHistory (
      direction,
      peerId,
      timestamp DESC,
      status
    );
CREATE INDEX callsHistory_order ON callsHistory
      (timestamp DESC, callId, peerId);
CREATE INDEX callsHistory_byConversation_order ON callsHistory (peerId, timestamp DESC, callId);
CREATE INDEX callsHistory_incoming_missed
      ON callsHistory (callId, status, direction)
      WHERE status IS 'Missed'
        AND direction IS 'Incoming';

CREATE TABLE message_attachments (
      messageId TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
      -- For editHistoryIndex to be part of the primary key, it cannot be NULL in strict tables.
      -- For that reason, we use a value of -1 to indicate that it is the root message (not in editHistory)
      editHistoryIndex INTEGER NOT NULL,
      attachmentType TEXT NOT NULL, -- 'long-message' | 'quote' | 'attachment' | 'preview' | 'contact' | 'sticker'
      orderInMessage INTEGER NOT NULL,
      conversationId TEXT NOT NULL,
      sentAt INTEGER NOT NULL,
      clientUuid TEXT,
      size INTEGER NOT NULL,
      contentType TEXT NOT NULL,
      path TEXT,
      plaintextHash TEXT,
      localKey TEXT,
      caption TEXT,
      fileName TEXT,
      blurHash TEXT,
      height INTEGER,
      width INTEGER,
      digest TEXT,
      key TEXT,
      downloadPath TEXT,
      version INTEGER,
      incrementalMac TEXT,
      incrementalMacChunkSize INTEGER,
      transitCdnKey TEXT,
      transitCdnNumber INTEGER,
      transitCdnUploadTimestamp INTEGER,
      backupCdnNumber INTEGER,
      thumbnailPath TEXT,
      thumbnailSize INTEGER,
      thumbnailContentType TEXT,
      thumbnailLocalKey TEXT,
      thumbnailVersion INTEGER,
      screenshotPath TEXT,
      screenshotSize INTEGER,
      screenshotContentType TEXT,
      screenshotLocalKey TEXT,
      screenshotVersion INTEGER,
      backupThumbnailPath TEXT,
      backupThumbnailSize INTEGER,
      backupThumbnailContentType TEXT,
      backupThumbnailLocalKey TEXT,
      backupThumbnailVersion INTEGER,
      storyTextAttachmentJson TEXT,
      localBackupPath TEXT,
      flags INTEGER,
      error INTEGER,
      wasTooBig INTEGER,
      isCorrupted INTEGER,
      copiedFromQuotedAttachment INTEGER,
      pending INTEGER,
      backfillError INTEGER, messageType TEXT, receivedAt INTEGER, receivedAtMs INTEGER, isViewOnce INTEGER, duration REAL, audioWaveform BLOB, transcodingTargetQuality INTEGER,
      PRIMARY KEY (messageId, editHistoryIndex, attachmentType, orderInMessage)
    ) STRICT;
CREATE INDEX message_attachments_getOlderMedia ON message_attachments
    (conversationId, attachmentType, receivedAt DESC, sentAt DESC)
    WHERE
      editHistoryIndex IS -1 AND
      messageType IN ('incoming', 'outgoing') AND
      isViewOnce IS NOT 1
  ;
CREATE INDEX message_attachments_sortBiggerMedia ON message_attachments
    (conversationId, attachmentType, size DESC, receivedAt DESC, sentAt DESC)
    WHERE
      editHistoryIndex IS -1 AND
      messageType IN ('incoming', 'outgoing') AND
      isViewOnce IS NOT 1;
CREATE INDEX message_attachments_plaintextHash ON message_attachments (plaintextHash);
CREATE INDEX message_attachments_path ON message_attachments (path);
CREATE INDEX message_attachments_thumbnailPath ON message_attachments (thumbnailPath);
CREATE INDEX message_attachments_screenshotPath ON message_attachments (screenshotPath);
CREATE INDEX message_attachments_backupThumbnailPath ON message_attachments (backupThumbnailPath);

CREATE TABLE "attachment_downloads" (
        messageId TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
        attachmentType TEXT NOT NULL,
        attachmentSignature TEXT NOT NULL,
        receivedAt INTEGER NOT NULL,
        sentAt INTEGER NOT NULL,
        contentType TEXT NOT NULL,
        size INTEGER NOT NULL,
        attachmentJson TEXT NOT NULL,
        active INTEGER NOT NULL,
        attempts INTEGER NOT NULL,
        retryAfter INTEGER,
        lastAttemptTimestamp INTEGER, source TEXT NOT NULL DEFAULT NULL, ciphertextSize INTEGER NOT NULL DEFAULT 0, originalSource TEXT NOT NULL DEFAULT NULL,

        PRIMARY KEY (messageId, attachmentType, attachmentSignature)
      ) STRICT;
CREATE INDEX attachment_downloads_active_receivedAt
      ON attachment_downloads (
        active, receivedAt
    );
CREATE INDEX attachment_downloads_active_messageId
      ON attachment_downloads (
        active, messageId
    );
CREATE INDEX attachment_downloads_messageId
      ON attachment_downloads (
        messageId
    );
CREATE INDEX attachment_downloads_source_ciphertextSize
        ON attachment_downloads (
            source, ciphertextSize
        );
CREATE INDEX attachment_downloads_active_source_receivedAt
        ON attachment_downloads (
            active, source, receivedAt
        );

CREATE TABLE syncTasks(
      id TEXT PRIMARY KEY NOT NULL,
      attempts INTEGER NOT NULL,
      createdAt INTEGER NOT NULL,
      data TEXT NOT NULL,
      envelopeId TEXT NOT NULL,
      sentAt INTEGER NOT NULL,
      type TEXT NOT NULL
    ) STRICT;
CREATE INDEX syncTasks_delete ON syncTasks (attempts DESC);
CREATE INDEX syncTasks_type ON syncTasks (type);

CREATE TABLE items(
      id STRING PRIMARY KEY ASC,
      json TEXT
    );

CREATE TABLE recentEmojis (
      emoji TEXT NOT NULL PRIMARY KEY,
      lastUsedAt INTEGER NOT NULL
    ) STRICT;
CREATE INDEX recentEmojis_order ON recentEmojis (lastUsedAt DESC);

CREATE TABLE pinnedMessages (
     	id               INTEGER PRIMARY KEY AUTOINCREMENT,
     	conversationId   TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
     	messageId        TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
     	pinnedAt         INTEGER NOT NULL,
     	expiresAt        INTEGER,
     	UNIQUE (conversationId, messageId)
    ) STRICT;
CREATE INDEX pinnedMessages_byConversation
      ON pinnedMessages(
        conversationId,
        pinnedAt DESC,
        messageId
      );
CREATE INDEX pinnedMessages_byExpiresAt
      ON pinnedMessages(
        expiresAt ASC
      )
      WHERE expiresAt IS NOT NULL;

CREATE TABLE storyReads (
      authorId STRING NOT NULL,
      conversationId STRING NOT NULL,
      storyId STRING NOT NULL,
      storyReadDate NUMBER NOT NULL,

      PRIMARY KEY (authorId, storyId)
    );
CREATE INDEX storyReads_data ON storyReads (
      storyReadDate, authorId, conversationId
    );
CREATE INDEX storyReads_storyId
      ON storyReads (storyId);

CREATE VIRTUAL TABLE messages_fts USING fts5(
      body,
      tokenize = 'unicode61'
    );

CREATE TRIGGER messages_on_insert AFTER INSERT ON messages
    WHEN new.isSearchable IS 1
    BEGIN
      INSERT INTO messages_fts
      (rowid, body)
      VALUES
      (new.rowid, new.searchableText);
    END;

CREATE TRIGGER messages_on_update AFTER UPDATE ON messages
    WHEN
      new.isSearchable IS 1 AND old.searchableText IS NOT new.searchableText
    BEGIN
      UPDATE messages_fts SET body = new.searchableText WHERE rowId = new.rowId;
    END;

CREATE TRIGGER messages_on_view_once_update AFTER UPDATE ON messages
    WHEN
      new.body IS NOT NULL AND new.isViewOnce = 1
    BEGIN
      DELETE FROM messages_fts WHERE rowid = old.rowid;
    END;

CREATE TRIGGER messages_on_delete AFTER DELETE ON messages BEGIN
      DELETE FROM messages_fts WHERE rowid = old.rowid;
      DELETE FROM reactions WHERE rowid IN (
        SELECT rowid FROM reactions
        WHERE messageId = old.id
      );
      DELETE FROM storyReads WHERE storyId = old.storyId;
    END;

CREATE TRIGGER messages_on_insert_insert_mentions AFTER INSERT ON messages
      BEGIN
        INSERT INTO mentions (messageId, mentionAci, start, length)
        SELECT messages.id, bodyRanges.value ->> 'mentionAci' as mentionAci,
          bodyRanges.value ->> 'start' as start,
          bodyRanges.value ->> 'length' as length
        FROM messages, json_each(messages.json ->> 'bodyRanges') as bodyRanges
        WHERE bodyRanges.value ->> 'mentionAci' IS NOT NULL
        AND messages.id = new.id;
      END;

-- searchMessages (Server.node.ts:2196-2203) creates these two as TEMP tables inside its transaction and drops
-- them afterwards. They are ordinary tables here so each step of the search can run as its own query; data.sql
-- fills them with what the earlier steps would have produced.
CREATE TABLE tmp_results(rowid INTEGER PRIMARY KEY ASC);
CREATE TABLE tmp_filtered_results(rowid INTEGER PRIMARY KEY ASC);
