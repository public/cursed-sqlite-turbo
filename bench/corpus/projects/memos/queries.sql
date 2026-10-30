-- Memos (usememos/memos @ dcf08b5, MIT). Go database/sql with `?` placeholders; WHERE lists are assembled at
-- runtime, so each query below is one representative instantiation (marked dynamic). Placeholders are
-- normalised to ?N in argument order.

-- @id memos.list_memos.home_feed
-- @src store/db/sqlite/memo.go:118-246
-- @style ? positional, dynamic WHERE (ListMemos + sqliteMemoAccessPredicate in store/db/sqlite/memo_access.go:12)
-- @tags hotpath,dynamic
-- @note Home timeline for a signed-in user: access predicate (public/protected/own-private/space-member EXISTS), exclude comments, correlated parent_uid lookup in the result set, pinned-first top-N.
-- @param ?1 7
-- @param ?2 7
-- @param ?3 7
-- @param ?4 7
-- @param ?5 7
SELECT `memo`.`id` AS `id`, `memo`.`uid` AS `uid`, `memo`.`creator_id` AS `creator_id`, `memo`.`created_ts` AS `created_ts`,
       `memo`.`updated_ts` AS `updated_ts`, `memo`.`row_status` AS `row_status`, `memo`.`visibility` AS `visibility`,
       `memo`.`pinned` AS `pinned`, `memo`.`payload` AS `payload`, `memo`.`space_id` AS `space_id`,
       (SELECT parent_memo.uid FROM memo_relation AS parent_relation
          JOIN memo AS parent_memo ON parent_memo.id = parent_relation.related_memo_id
         WHERE parent_relation.memo_id = memo.id AND parent_relation.type = 'COMMENT'
         ORDER BY parent_memo.id LIMIT 1) AS parent_uid,
       `memo`.`content` AS `content`
FROM `memo`
LEFT JOIN `user` AS `memo_creator` ON `memo`.`creator_id` = `memo_creator`.`id`
LEFT JOIN `space` AS `memo_space` ON `memo`.`space_id` = `memo_space`.`id`
WHERE 1 = 1
  AND ((`memo`.`visibility` = 'PUBLIC') OR (EXISTS (SELECT 1 FROM `user` AS `access_user` WHERE `access_user`.`id` = ?1 AND `access_user`.`row_status` = 'NORMAL')
        AND ((`memo`.`visibility` = 'PRIVATE' AND `memo`.`creator_id` = ?2) OR `memo`.`visibility` = 'PROTECTED'
             OR (`memo`.`visibility` = 'SPACE' AND EXISTS (SELECT 1 FROM `space_member` AS `access_member` WHERE `access_member`.`space_id` = `memo`.`space_id` AND `access_member`.`user_id` = ?3 AND `access_member`.`status` = 'ACTIVE' AND `access_member`.`role` IN ('ADMIN', 'USER'))))))
  AND (`memo`.`visibility` IN ('PUBLIC', 'PROTECTED', 'PRIVATE', 'SPACE')
       AND EXISTS (SELECT 1 FROM `user` AS `valid_creator` WHERE `valid_creator`.`id` = `memo`.`creator_id` AND `valid_creator`.`row_status` IN ('NORMAL', 'ARCHIVED'))
       AND (`memo`.`visibility` <> 'SPACE' OR (`memo`.`space_id` IS NOT NULL AND EXISTS (SELECT 1 FROM `space` AS `valid_space` WHERE `valid_space`.`id` = `memo`.`space_id`))))
  AND (`memo`.`row_status` = 'NORMAL' OR (`memo`.`row_status` = 'ARCHIVED' AND `memo`.`creator_id` = ?4))
  AND `memo`.`row_status` = 'NORMAL'
  AND NOT EXISTS (SELECT 1 FROM memo_relation AS comment_relation WHERE comment_relation.memo_id = memo.id AND comment_relation.type = 'COMMENT')
ORDER BY `pinned` DESC, `created_ts` DESC, `id` DESC
LIMIT 11 OFFSET 0;

-- @id memos.list_memos.tag_filter
-- @src store/db/sqlite/memo.go:118-246
-- @style ? positional, dynamic WHERE; tag predicate from filter/render.go:629 (renderTagComprehension)
-- @tags hotpath,dynamic
-- @note Filter `tag in ["idea"]` on the explore page: correlated json_each over the payload's tags array, public memos only.
-- @param ?1 'idea'
SELECT `memo`.`id` AS `id`, `memo`.`uid` AS `uid`, `memo`.`creator_id` AS `creator_id`, `memo`.`created_ts` AS `created_ts`,
       `memo`.`updated_ts` AS `updated_ts`, `memo`.`row_status` AS `row_status`, `memo`.`visibility` AS `visibility`,
       `memo`.`pinned` AS `pinned`, `memo`.`payload` AS `payload`, `memo`.`space_id` AS `space_id`,
       (SELECT parent_memo.uid FROM memo_relation AS parent_relation
          JOIN memo AS parent_memo ON parent_memo.id = parent_relation.related_memo_id
         WHERE parent_relation.memo_id = memo.id AND parent_relation.type = 'COMMENT'
         ORDER BY parent_memo.id LIMIT 1) AS parent_uid,
       `memo`.`content` AS `content`
FROM `memo`
LEFT JOIN `user` AS `memo_creator` ON `memo`.`creator_id` = `memo_creator`.`id`
LEFT JOIN `space` AS `memo_space` ON `memo`.`space_id` = `memo_space`.`id`
WHERE 1 = 1
  AND EXISTS (SELECT 1 FROM json_each(COALESCE(JSON_EXTRACT(`memo`.`payload`, '$.tags'), JSON_ARRAY())) AS tag_item
              WHERE tag_item.value = ?1 COLLATE BINARY)
  AND `memo`.`visibility` = 'PUBLIC'
  AND (`memo`.`visibility` IN ('PUBLIC', 'PROTECTED', 'PRIVATE', 'SPACE')
       AND EXISTS (SELECT 1 FROM `user` AS `valid_creator` WHERE `valid_creator`.`id` = `memo`.`creator_id` AND `valid_creator`.`row_status` IN ('NORMAL', 'ARCHIVED')))
  AND `memo`.`row_status` = 'NORMAL'
ORDER BY `pinned` DESC, `created_ts` DESC, `id` DESC
LIMIT 11;

-- @id memos.list_memos.property_filter
-- @src store/db/sqlite/memo.go:118-246
-- @style ? positional, dynamic WHERE; property predicates from filter/render.go:962
-- @tags dynamic
-- @note Shortcut filter `has_link && has_incomplete_tasks` for the creator's own memos: JSON_EXTRACT IS TRUE predicates over a creator range.
-- @param ?1 12
SELECT `memo`.`id`, `memo`.`uid`, `memo`.`created_ts`, `memo`.`visibility`, `memo`.`pinned`, `memo`.`payload`, `memo`.`content`
FROM `memo`
WHERE 1 = 1
  AND (JSON_EXTRACT(`memo`.`payload`, '$.property.hasLink') IS TRUE AND JSON_EXTRACT(`memo`.`payload`, '$.property.hasIncompleteTasks') IS TRUE)
  AND `memo`.`creator_id` = ?1
  AND `memo`.`row_status` = 'NORMAL'
ORDER BY `pinned` DESC, `created_ts` DESC, `id` DESC
LIMIT 21;

-- @id memos.count_user_memos
-- @src store/db/sqlite/memo.go:280
-- @style ? positional
-- @tags hot-small
-- @param ?1 42
SELECT COUNT(*) FROM memo WHERE creator_id = ?1;

-- @id memos.delete_memo
-- @src store/db/sqlite/memo.go:310
-- @style ? positional
-- @tags hot-small
-- @param ?1 1234
DELETE FROM `memo` WHERE `id` = ?1;

-- @id memos.list_memos.comments_of_memo
-- @src store/db/sqlite/memo.go:170-178
-- @style ? positional, dynamic WHERE (CommentContextMemoID)
-- @tags hotpath,dynamic
-- @note Comment thread under a memo: EXISTS on the relation table plus the access predicate; ascending time order.
-- @param ?1 3001
-- @param ?2 7
-- @param ?3 7
-- @param ?4 7
-- @param ?5 7
-- @param ?6 7
SELECT `memo`.`id` AS `id`, `memo`.`uid` AS `uid`, `memo`.`creator_id` AS `creator_id`, `memo`.`created_ts` AS `created_ts`,
       `memo`.`updated_ts` AS `updated_ts`, `memo`.`row_status` AS `row_status`, `memo`.`visibility` AS `visibility`,
       `memo`.`pinned` AS `pinned`, `memo`.`payload` AS `payload`, `memo`.`space_id` AS `space_id`,
       (SELECT parent_memo.uid FROM memo_relation AS parent_relation
          JOIN memo AS parent_memo ON parent_memo.id = parent_relation.related_memo_id
         WHERE parent_relation.memo_id = memo.id AND parent_relation.type = 'COMMENT'
         ORDER BY parent_memo.id LIMIT 1) AS parent_uid,
       `memo`.`content` AS `content`
FROM `memo`
LEFT JOIN `user` AS `memo_creator` ON `memo`.`creator_id` = `memo_creator`.`id`
LEFT JOIN `space` AS `memo_space` ON `memo`.`space_id` = `memo_space`.`id`
WHERE 1 = 1
  AND EXISTS (SELECT 1 FROM memo_relation AS comment_context
              WHERE comment_context.memo_id = memo.id AND comment_context.related_memo_id = ?1 AND comment_context.type = 'COMMENT')
  AND ((`memo`.`visibility` = 'PUBLIC') OR (EXISTS (SELECT 1 FROM `user` AS `access_user` WHERE `access_user`.`id` = ?2 AND `access_user`.`row_status` = 'NORMAL')
        AND ((`memo`.`visibility` = 'PRIVATE' AND `memo`.`creator_id` = ?3) OR `memo`.`visibility` = 'PROTECTED'
             OR (`memo`.`visibility` = 'SPACE' AND EXISTS (SELECT 1 FROM `space_member` AS `access_member` WHERE `access_member`.`space_id` = `memo`.`space_id` AND `access_member`.`user_id` = ?4 AND `access_member`.`status` = 'ACTIVE' AND `access_member`.`role` IN ('ADMIN', 'USER'))))))
  AND (`memo`.`visibility` IN ('PUBLIC', 'PROTECTED', 'PRIVATE', 'SPACE')
       AND EXISTS (SELECT 1 FROM `user` AS `valid_creator` WHERE `valid_creator`.`id` = `memo`.`creator_id` AND `valid_creator`.`row_status` IN ('NORMAL', 'ARCHIVED'))
       AND (`memo`.`visibility` <> 'SPACE' OR (`memo`.`space_id` IS NOT NULL AND EXISTS (SELECT 1 FROM `space` AS `valid_space` WHERE `valid_space`.`id` = `memo`.`space_id`))))
  AND (`memo`.`row_status` = 'NORMAL' OR (`memo`.`row_status` = 'ARCHIVED' AND `memo`.`creator_id` = ?5))
ORDER BY `created_ts` ASC, `id` DESC;

-- @id memos.list_memos.user_profile_page
-- @src store/db/sqlite/memo.go:118-246
-- @style ? positional, dynamic WHERE (CreatorID + VisibilityList + ExcludeComments, OrderByUpdatedTs)
-- @tags hotpath,dynamic
-- @note A user's profile page seen by an anonymous visitor: creator filter, visibility IN-list, NOT EXISTS comments, ordered by updated_ts with OFFSET paging.
-- @param ?1 33
-- @param ?2 'NORMAL'
-- @param ?3 'PUBLIC'
SELECT `memo`.`id` AS `id`, `memo`.`uid` AS `uid`, `memo`.`creator_id` AS `creator_id`, `memo`.`created_ts` AS `created_ts`,
       `memo`.`updated_ts` AS `updated_ts`, `memo`.`row_status` AS `row_status`, `memo`.`visibility` AS `visibility`,
       `memo`.`pinned` AS `pinned`, `memo`.`payload` AS `payload`, `memo`.`space_id` AS `space_id`,
       (SELECT parent_memo.uid FROM memo_relation AS parent_relation
          JOIN memo AS parent_memo ON parent_memo.id = parent_relation.related_memo_id
         WHERE parent_relation.memo_id = memo.id AND parent_relation.type = 'COMMENT'
         ORDER BY parent_memo.id LIMIT 1) AS parent_uid,
       `memo`.`content` AS `content`
FROM `memo`
LEFT JOIN `user` AS `memo_creator` ON `memo`.`creator_id` = `memo_creator`.`id`
LEFT JOIN `space` AS `memo_space` ON `memo`.`space_id` = `memo_space`.`id`
WHERE 1 = 1 AND `memo`.`creator_id` = ?1 AND `memo`.`row_status` = ?2 AND `memo`.`visibility` IN (?3)
  AND NOT EXISTS (SELECT 1 FROM memo_relation AS comment_relation WHERE comment_relation.memo_id = memo.id AND comment_relation.type = 'COMMENT')
ORDER BY `pinned` DESC, `updated_ts` DESC, `id` DESC
LIMIT 11 OFFSET 10;

-- @id memos.list_memos.by_uid
-- @src store/db/sqlite/memo.go:136
-- @style ? positional, dynamic WHERE (UID only)
-- @tags hot-small,dynamic
-- @note Single memo page / GetMemo: the same wide SELECT with a UNIQUE lookup.
-- @param ?1 'm9e3779b1'
SELECT `memo`.`id` AS `id`, `memo`.`uid` AS `uid`, `memo`.`creator_id` AS `creator_id`, `memo`.`created_ts` AS `created_ts`,
       `memo`.`updated_ts` AS `updated_ts`, `memo`.`row_status` AS `row_status`, `memo`.`visibility` AS `visibility`,
       `memo`.`pinned` AS `pinned`, `memo`.`payload` AS `payload`, `memo`.`space_id` AS `space_id`,
       (SELECT parent_memo.uid FROM memo_relation AS parent_relation
          JOIN memo AS parent_memo ON parent_memo.id = parent_relation.related_memo_id
         WHERE parent_relation.memo_id = memo.id AND parent_relation.type = 'COMMENT'
         ORDER BY parent_memo.id LIMIT 1) AS parent_uid,
       `memo`.`content` AS `content`
FROM `memo`
LEFT JOIN `user` AS `memo_creator` ON `memo`.`creator_id` = `memo_creator`.`id`
LEFT JOIN `space` AS `memo_space` ON `memo`.`space_id` = `memo_space`.`id`
WHERE 1 = 1 AND `memo`.`uid` = ?1
ORDER BY `created_ts` DESC, `id` DESC
LIMIT 1;

-- @id memos.list_memos.tag_prefix_not
-- @src filter/render.go:629-700
-- @style ? positional; tag comprehension `!tags.exists(t, t.startsWith("work/"))` per filter/engine_test.go:488
-- @tags dynamic
-- @note NOT EXISTS over json_each with instr() prefix test plus json_array_length guard; scans every visible memo.
-- @param ?1 'tr'
SELECT `memo`.`id` AS `id`, `memo`.`uid` AS `uid`, `memo`.`created_ts` AS `created_ts`, `memo`.`payload` AS `payload`
FROM `memo`
WHERE 1 = 1
  AND (json_array_length(COALESCE(JSON_EXTRACT(`memo`.`payload`, '$.tags'), JSON_ARRAY())) > 0
       AND NOT EXISTS (SELECT 1 FROM json_each(COALESCE(JSON_EXTRACT(`memo`.`payload`, '$.tags'), JSON_ARRAY())) AS tag_item
                       WHERE instr(tag_item.value, ?1) = 1))
  AND `memo`.`visibility` = 'PUBLIC' AND `memo`.`row_status` = 'NORMAL'
ORDER BY `pinned` DESC, `created_ts` DESC, `id` DESC
LIMIT 21;

-- @id memos.list_memos.has_location
-- @src filter/render.go:962
-- @style ? positional; filter `location != null` (filter/engine_test.go:575)
-- @tags dynamic
-- @note Map view: JSON_EXTRACT IS NOT NULL over payload for the user's own memos, all rows (no LIMIT).
-- @param ?1 21
SELECT `memo`.`id` AS `id`, `memo`.`uid` AS `uid`, `memo`.`created_ts` AS `created_ts`, `memo`.`payload` AS `payload`
FROM `memo`
WHERE 1 = 1 AND JSON_EXTRACT(`memo`.`payload`, '$.location') IS NOT NULL AND `memo`.`creator_id` = ?1 AND `memo`.`row_status` = 'NORMAL'
ORDER BY `created_ts` DESC, `id` DESC;

-- @id memos.list_memo_relations.page
-- @src store/db/sqlite/memo_relation.go:41-110
-- @style ? positional, dynamic WHERE (MemoIDList IN-clause on both sides)
-- @tags hotpath,dynamic
-- @note Batch-loads relations for the memos on one timeline page: (memo_id IN (...) OR related_memo_id IN (...)) -> MULTI-INDEX OR.
SELECT memo_id, related_memo_id, type FROM memo_relation
WHERE (memo_id IN (59990,59980,59970,59960,59950,59940,59930,59920,59910,59900) OR related_memo_id IN (59990,59980,59970,59960,59950,59940,59930,59920,59910,59900))
ORDER BY memo_id DESC;

-- @id memos.list_memo_relations.active_sources_for_memo
-- @src store/db/sqlite/memo_relation.go:84-87
-- @style ? positional, dynamic WHERE (RelatedMemoID + SourceMemoRowStatus)
-- @tags dynamic
-- @param ?1 3001
-- @param ?2 'NORMAL'
SELECT memo_id, related_memo_id, type FROM memo_relation
WHERE related_memo_id = ?1 AND memo_id IN (SELECT id FROM memo WHERE row_status = ?2)
ORDER BY memo_id DESC;

-- @id memos.upsert_memo_relation
-- @src store/db/sqlite/memo_relation.go:13-22
-- @style ? positional
-- @tags hot-small
-- @param ?1 59999
-- @param ?2 59998
-- @param ?3 'REFERENCE'
INSERT INTO memo_relation (memo_id, related_memo_id, type) VALUES (?1, ?2, ?3)
ON CONFLICT(memo_id, related_memo_id, type) DO UPDATE SET type = excluded.type
RETURNING memo_id, related_memo_id, type;

-- @id memos.list_reactions.page
-- @src store/db/sqlite/reaction.go:59-92
-- @style ? positional, dynamic WHERE (MemoIDList)
-- @tags hotpath,dynamic
-- @note Reactions for the memos on one page; no index on memo_id, so a full scan of reaction.
SELECT id, created_ts, creator_id, memo_id, reaction_type FROM reaction
WHERE memo_id IN (59990,59980,59970,59960,59950,59940,59930,59920,59910,59900,1001,1002,1003,1004,1005)
ORDER BY id ASC;

-- @id memos.upsert_reaction
-- @src store/db/sqlite/reaction.go:40-46
-- @style ? positional
-- @tags hot-small,wallclock
-- @note INSERT ... SELECT guarded by the memo existing; RETURNING created_ts comes from the column's strftime('%s','now') default, so the output hash changes every second.
-- @param ?1 5
-- @param ?2 '🚀'
-- @param ?3 1234
INSERT INTO reaction (creator_id, memo_id, reaction_type) SELECT ?1, memo.id, ?2 FROM memo WHERE memo.id = ?3 RETURNING id, created_ts;

-- @id memos.list_attachments.page
-- @src store/db/sqlite/attachment.go:67-150
-- @style ? positional, dynamic WHERE (MemoIDList), access-scoped
-- @tags hotpath,dynamic
-- @note Attachments of a page of memos: three LEFT JOINs, CASE in the select list, access predicate on the joined memo.
-- @param ?1 7
-- @param ?2 7
-- @param ?3 7
-- @param ?4 7
-- @param ?5 7
SELECT `attachment`.`id` AS `id`, `attachment`.`uid` AS `uid`, `attachment`.`filename` AS `filename`, `attachment`.`type` AS `type`,
       `attachment`.`size` AS `size`, `attachment`.`creator_id` AS `creator_id`, `attachment`.`created_ts` AS `created_ts`,
       `attachment`.`updated_ts` AS `updated_ts`, `attachment`.`memo_id` AS `memo_id`, `attachment`.`storage_type` AS `storage_type`,
       `attachment`.`reference` AS `reference`, `attachment`.`payload` AS `payload`,
       CASE WHEN `memo`.`uid` IS NOT NULL THEN `memo`.`uid` ELSE NULL END AS `memo_uid`,
       `attachment_creator`.`username` AS `creator_username`
FROM `attachment`
LEFT JOIN `memo` ON `attachment`.`memo_id` = `memo`.`id`
LEFT JOIN `user` AS `attachment_creator` ON `attachment`.`creator_id` = `attachment_creator`.`id`
LEFT JOIN `space` AS `attachment_space` ON `memo`.`space_id` = `attachment_space`.`id`
WHERE 1 = 1 AND `attachment`.`memo_id` IN (5,9,13,17,21,25,29,33,37,41,45,49,53,57,61,65)
  AND ((`attachment`.`memo_id` IS NOT NULL AND ((`memo`.`visibility` = 'PUBLIC') OR (EXISTS (SELECT 1 FROM `user` AS `access_user` WHERE `access_user`.`id` = ?1 AND `access_user`.`row_status` = 'NORMAL')
        AND ((`memo`.`visibility` = 'PRIVATE' AND `memo`.`creator_id` = ?2) OR `memo`.`visibility` = 'PROTECTED'
             OR (`memo`.`visibility` = 'SPACE' AND EXISTS (SELECT 1 FROM `space_member` AS `attachment_member` WHERE `attachment_member`.`space_id` = `memo`.`space_id` AND `attachment_member`.`user_id` = ?3 AND `attachment_member`.`status` = 'ACTIVE' AND `attachment_member`.`role` IN ('ADMIN', 'USER'))))))
       AND (`memo`.`visibility` IN ('PUBLIC', 'PROTECTED', 'PRIVATE', 'SPACE')
            AND EXISTS (SELECT 1 FROM `user` AS `valid_creator` WHERE `valid_creator`.`id` = `memo`.`creator_id` AND `valid_creator`.`row_status` IN ('NORMAL', 'ARCHIVED'))
            AND (`memo`.`visibility` <> 'SPACE' OR (`memo`.`space_id` IS NOT NULL AND EXISTS (SELECT 1 FROM `space` AS `valid_space` WHERE `valid_space`.`id` = `memo`.`space_id`))))
       AND (`memo`.`row_status` = 'NORMAL' OR (`memo`.`row_status` = 'ARCHIVED' AND `memo`.`creator_id` = ?4))))
ORDER BY `attachment`.`updated_ts` DESC;

-- @id memos.list_attachments.filename_search
-- @src store/db/sqlite/attachment.go:83
-- @style ? positional, dynamic WHERE (CreatorID + FilenameSearch with %...%)
-- @tags dynamic
-- @param ?1 9
-- @param ?2 '%1%.pdf%'
SELECT `attachment`.`id` AS `id`, `attachment`.`uid` AS `uid`, `attachment`.`filename` AS `filename`, `attachment`.`type` AS `type`,
       `attachment`.`size` AS `size`, `attachment`.`memo_id` AS `memo_id`,
       CASE WHEN `memo`.`uid` IS NOT NULL THEN `memo`.`uid` ELSE NULL END AS `memo_uid`,
       `attachment_creator`.`username` AS `creator_username`
FROM `attachment`
LEFT JOIN `memo` ON `attachment`.`memo_id` = `memo`.`id`
LEFT JOIN `user` AS `attachment_creator` ON `attachment`.`creator_id` = `attachment_creator`.`id`
LEFT JOIN `space` AS `attachment_space` ON `memo`.`space_id` = `attachment_space`.`id`
WHERE 1 = 1 AND `attachment`.`creator_id` = ?1 AND `attachment`.`filename` LIKE ?2
ORDER BY `attachment`.`updated_ts` DESC;

-- @id memos.attachment_storage_used
-- @src store/db/sqlite/attachment.go:314
-- @style ? positional
-- @tags hot-small
-- @param ?1 9
SELECT COALESCE(SUM(size), 0) FROM attachment WHERE creator_id = ?1 AND storage_type <> 'EXTERNAL';

-- @id memos.list_inboxes
-- @src store/db/sqlite/inbox.go:40-66
-- @style ? positional, dynamic WHERE (ReceiverID + Status + MessageType)
-- @tags hotpath,dynamic
-- @note Notification bell: JSON_EXTRACT on message type, ordered by created_ts, no index on receiver_id.
-- @param ?1 7
-- @param ?2 'UNREAD'
-- @param ?3 'MEMO_COMMENT'
SELECT `id`, `created_ts`, `sender_id`, `receiver_id`, `status`, `message` FROM `inbox`
WHERE `receiver_id` = ?1 AND `status` = ?2 AND (JSON_EXTRACT(`message`, '$.type') IS NULL OR JSON_EXTRACT(`message`, '$.type') = ?3)
ORDER BY `created_ts` DESC;

-- @id memos.upsert_user_setting
-- @src store/db/sqlite/user_setting.go:14-22
-- @style ? positional
-- @tags hot-small
-- @param ?1 7
-- @param ?2 'GENERAL'
-- @param ?3 '{"locale":"de","appearance":"dark"}'
INSERT INTO user_setting (user_id, key, value) VALUES (?1, ?2, ?3)
ON CONFLICT(user_id, key) DO UPDATE SET value = EXCLUDED.value;

-- @id memos.get_user_by_pat_hash
-- @src store/db/sqlite/user_setting.go:89-101
-- @style ? positional
-- @tags hotpath
-- @note Runs on every API request with a personal access token: EXISTS over json_each of each user's token list.
-- @param ?1 'hash-77-1'
SELECT user_setting.user_id, user_setting.value FROM user_setting
WHERE user_setting.key = 'PERSONAL_ACCESS_TOKENS'
  AND EXISTS (SELECT 1 FROM json_each(json_extract(user_setting.value, '$.tokens')) AS token
              WHERE json_extract(token.value, '$.tokenHash') = ?1);

-- @id memos.would_lose_space_admin
-- @src store/db/sqlite/user.go:106-113
-- @style ? positional
-- @note Nested EXISTS / NOT EXISTS with a join inside the inner subquery.
-- @param ?1 10
-- @param ?2 10
SELECT EXISTS(
  SELECT 1 FROM space_member target
  WHERE target.user_id = ?1 AND target.status = 'ACTIVE' AND target.role = 'ADMIN'
    AND NOT EXISTS (SELECT 1 FROM space_member other JOIN user u ON u.id = other.user_id
                    WHERE other.space_id = target.space_id AND other.user_id <> ?2
                      AND other.status = 'ACTIVE' AND other.role = 'ADMIN' AND u.row_status = 'NORMAL'));

-- @id memos.list_users.search
-- @src store/db/sqlite/user.go:198-224
-- @style ? positional, dynamic WHERE + ORDER BY (Search)
-- @tags dynamic
-- @note User picker search: LOWER() LIKE on two columns and a CASE ranking in ORDER BY.
-- @param ?1 '%user1%'
-- @param ?2 '%user1%'
-- @param ?3 'user1'
-- @param ?4 'user1%'
-- @param ?5 'user1%'
SELECT id, username, role, email, nickname, password_hash, avatar_url, description, created_ts, updated_ts, row_status
FROM user
WHERE 1 = 1 AND (LOWER(username) LIKE ?1 OR LOWER(nickname) LIKE ?2)
ORDER BY CASE WHEN LOWER(username) = ?3 THEN 0 WHEN LOWER(username) LIKE ?4 THEN 1 WHEN LOWER(nickname) LIKE ?5 THEN 2 ELSE 3 END,
         LENGTH(username) ASC, created_ts DESC, row_status DESC
LIMIT 10;

-- @id memos.refresh_memo_derived_payload
-- @src store/db/sqlite/memo.go:336
-- @style ? positional
-- @tags hot-small
-- @note Runs after every memo edit: JSON_SET with two JSON() arguments, guarded by content equality.
-- @param ?1 '["idea","code"]'
-- @param ?2 '{"hasLink":false,"hasTaskList":true}'
-- @param ?3 1200
-- @param ?4 (SELECT content FROM memo WHERE id = 1200)
UPDATE `memo` SET `payload` = JSON_SET(COALESCE(NULLIF(`payload`, ''), '{}'), '$.tags', JSON(?1), '$.property', JSON(?2)) WHERE `id` = ?3 AND `content` = ?4;
