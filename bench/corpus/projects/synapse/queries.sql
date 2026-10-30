-- Synapse (element-hq/synapse @ b20ae98, AGPL-3.0). Python DB-API with `?` placeholders on SQLite; many statements
-- splice in clauses built at runtime (make_in_list_sql_clause, pagination bounds, event filters), so those are one
-- representative instantiation each (tagged dynamic). Where SQLite and Postgres branches differ, the SQLite one is
-- used. Paths are repo-relative.

-- @id synapse.stream.paginate_room_events_backwards
-- @src synapse/storage/databases/main/stream.py:2280-2350
-- @style ? positional; bounds from generate_pagination_where_clause (stream.py:152) with the SQLite OR-expansion (stream.py:314)
-- @tags hotpath,dynamic
-- @note /messages backwards pagination: a two-column (topological, stream) token bound expanded to OR form for SQLite, top-N fetching 2x the limit.
-- @param ?1 '!room1:example.org'
-- @param ?2 40
SELECT event.event_id, event.instance_name, event.topological_ordering, event.stream_ordering
FROM events AS event
WHERE event.outlier = FALSE AND event.room_id = ?1 AND (
        1200 > event.topological_ordering
        OR (1200 = event.topological_ordering AND 39000 >= event.stream_ordering)
    ) AND (
        300 < event.topological_ordering
        OR (300 = event.topological_ordering AND 9000 < event.stream_ordering)
    )
ORDER BY event.topological_ordering DESC, event.stream_ordering DESC LIMIT ?2;

-- @id synapse.stream.paginate_room_events_filtered
-- @src synapse/storage/databases/main/stream.py:2287-2350
-- @style ? positional; filter_to_clause (stream.py:480) for a filter {types:[m.room.message, m.reaction*], not_senders:[..], not_rel_types:[m.thread]}
-- @tags hotpath,dynamic
-- @note Filtered /messages (threads-aware clients exclude thread replies): LEFT JOIN event_relations, LIKE on the type wildcard, NOT-IN-style relation predicate.
-- @param ?1 '!room1:example.org'
-- @param ?2 'm.room.message'
-- @param ?3 'm.reaction%'
-- @param ?4 '@user1:example.org'
-- @param ?5 'm.thread'
-- @param ?6 40
SELECT event.event_id, event.instance_name, event.topological_ordering, event.stream_ordering
FROM events AS event
LEFT JOIN event_relations AS event_relation USING (event_id)
WHERE event.outlier = FALSE AND event.room_id = ?1 AND (
        1200 > event.topological_ordering
        OR (1200 = event.topological_ordering AND 39000 >= event.stream_ordering)
    )
    AND (event.type = ?2 OR event.type LIKE ?3) AND event.sender != ?4
    AND ((event_relation.relation_type != ?5) OR event_relation.relation_type IS NULL)
ORDER BY event.topological_ordering DESC, event.stream_ordering DESC LIMIT ?6;

-- @id synapse.stream.get_last_event_pos_in_room
-- @src synapse/storage/databases/main/stream.py:1540-1565
-- @style ? positional; event_type IN clause from make_in_list_sql_clause
-- @tags hot-small,hotpath,dynamic
-- @note Latest non-rejected event of given types in a room: anti-join on rejections, top-1.
-- @param ?1 '!room6:example.org'
-- @param ?2 'm.room.message'
-- @param ?3 'm.room.encrypted'
SELECT event_id, stream_ordering, instance_name
FROM events
LEFT JOIN rejections USING (event_id)
WHERE room_id = ?1
    AND type IN (?2, ?3)
    AND NOT outlier
    AND rejections.event_id IS NULL
ORDER BY stream_ordering DESC
LIMIT 1;

-- @id synapse.stream.bulk_get_max_event_pos_fallback
-- @src synapse/storage/databases/main/stream.py:1772-1792
-- @style ? positional; room_id IN clause from make_in_list_sql_clause
-- @tags hotpath,dynamic
-- @note Per-room latest position before a stream token: correlated top-1 subquery in the result set, once per room in an IN list.
-- @param ?1 38000
-- @param ?2 '!room1:example.org'
-- @param ?3 '!room2:example.org'
-- @param ?4 '!room6:example.org'
-- @param ?5 '!room39:example.org'
-- @param ?6 '!room170:example.org'
-- @param ?7 '!room251:example.org'
SELECT room_id, (
    SELECT stream_ordering FROM events AS e
    LEFT JOIN rejections USING (event_id)
    WHERE e.room_id = r.room_id
        AND e.stream_ordering <= ?1
        AND NOT outlier
        AND rejection_reason IS NULL
    ORDER BY stream_ordering DESC
    LIMIT 1
)
FROM rooms AS r
WHERE room_id IN (?2, ?3, ?4, ?5, ?6, ?7);

-- @id synapse.stream.get_rooms_around_token_union
-- @src synapse/storage/databases/main/stream.py:1626-1660
-- @style ? positional; event_type_clause empty (no type filter)
-- @tags hotpath,dynamic
-- @note UNION ALL of an in-range scan and the last event before the range, each with an anti-join on rejections, re-sorted.
-- @param ?1 '!room6:example.org'
-- @param ?2 30000
-- @param ?3 36000
-- @param ?4 '!room6:example.org'
-- @param ?5 30000
SELECT * FROM (
    SELECT instance_name, stream_ordering, topological_ordering, event_id
    FROM events
    LEFT JOIN rejections USING (event_id)
    WHERE room_id = ?1
        AND ?2 < stream_ordering AND stream_ordering <= ?3
        AND NOT outlier
        AND rejections.event_id IS NULL
    ORDER BY stream_ordering DESC
) AS a
UNION ALL
SELECT * FROM (
    SELECT instance_name, stream_ordering, topological_ordering, event_id
    FROM events
    LEFT JOIN rejections USING (event_id)
    WHERE room_id = ?4
        AND stream_ordering <= ?5
        AND NOT outlier
        AND rejections.event_id IS NULL
    ORDER BY stream_ordering DESC
    LIMIT 1
) AS b
ORDER BY stream_ordering DESC;

-- @id synapse.stream.membership_changes_for_user
-- @src synapse/storage/databases/main/stream.py:1026-1050
-- @style ? positional
-- @tags hotpath
-- @note Sync membership deltas: current_state_delta_stream with four LEFT JOINs (events and room_memberships, current and previous).
-- @param ?1 0
-- @param ?2 50000
-- @param ?3 'm.room.member'
-- @param ?4 '@user1334:example.org'
SELECT
    s.room_id,
    e.event_id,
    s.instance_name,
    s.stream_id,
    m.membership,
    e.sender,
    s.prev_event_id,
    e_prev.instance_name AS prev_instance_name,
    e_prev.stream_ordering AS prev_stream_ordering,
    m_prev.membership AS prev_membership,
    e_prev.sender AS prev_sender
FROM current_state_delta_stream AS s
    LEFT JOIN events AS e ON e.event_id = s.event_id
    LEFT JOIN room_memberships AS m ON m.event_id = s.event_id
    LEFT JOIN events AS e_prev ON e_prev.event_id = s.prev_event_id
    LEFT JOIN room_memberships AS m_prev ON m_prev.event_id = s.prev_event_id
WHERE s.stream_id > ?1 AND s.stream_id <= ?2
    AND s.type = ?3
    AND s.state_key = ?4
ORDER BY s.stream_id ASC;

-- @id synapse.stream.sliding_sync_membership_changes
-- @src synapse/storage/databases/main/stream.py:1204-1250
-- @style ? positional
-- @tags hotpath
-- @note Sliding sync: UNION ALL of out-of-band snapshot memberships (outlier join) and state-delta memberships, as a derived table joined to rooms USING, range-filtered and sorted.
-- @param ?1 '@user1334:example.org'
-- @param ?2 'm.room.member'
-- @param ?3 '@user1334:example.org'
-- @param ?4 0
-- @param ?5 50000
SELECT
    room_id,
    membership_event_id,
    event_instance_name,
    event_stream_ordering,
    membership,
    sender,
    prev_membership,
    room_version
FROM
(
    SELECT
        s.room_id,
        s.membership_event_id,
        s.event_instance_name,
        s.event_stream_ordering,
        s.membership,
        s.sender,
        NULL AS prev_membership
    FROM sliding_sync_membership_snapshots AS s
        INNER JOIN events AS e ON e.event_id = s.membership_event_id
    WHERE
        s.user_id = ?1
        AND e.outlier

    UNION ALL

    SELECT
        s.room_id,
        e.event_id AS membership_event_id,
        s.instance_name AS event_instance_name,
        s.stream_id AS event_stream_ordering,
        m.membership,
        e.sender,
        m_prev.membership AS prev_membership
    FROM current_state_delta_stream AS s
        LEFT JOIN events AS e ON e.event_id = s.event_id
        LEFT JOIN room_memberships AS m ON m.event_id = s.event_id
        LEFT JOIN room_memberships AS m_prev ON m_prev.event_id = s.prev_event_id
    WHERE
        s.type = ?2
        AND s.state_key = ?3
) AS c
INNER JOIN rooms USING (room_id)
WHERE event_stream_ordering > ?4 AND event_stream_ordering <= ?5
ORDER BY event_stream_ordering ASC;

-- @id synapse.events.fetch_event_rows
-- @src synapse/storage/databases/main/events_worker.py:1656-1680
-- @style ? positional; e.event_id IN clause from make_in_list_sql_clause (batches of up to 200)
-- @tags hotpath,dynamic
-- @note The event cache miss path: events JOIN event_json USING, LEFT JOIN rooms and rejections, for a batch of event IDs.
-- @param ?1 '$ev41868_0feabf26'
-- @param ?2 '$ev26064_a72e342a'
-- @param ?3 '$ev31647_23051f49'
-- @param ?4 '$ev32939_a2ff4895'
-- @param ?5 '$ev24890_14c62274'
-- @param ?6 '$ev33344_f0c2cd9a'
-- @param ?7 '$ev30535_e20c8671'
-- @param ?8 '$ev12898_9e19a71c'
SELECT
  e.event_id,
  e.stream_ordering,
  e.received_ts,
  e.instance_name,
  ej.internal_metadata,
  ej.json,
  ej.format_version,
  r.room_version,
  rej.reason,
  e.outlier
FROM events AS e
  JOIN event_json AS ej USING (event_id)
  LEFT JOIN rooms r ON r.room_id = e.room_id
  LEFT JOIN rejections as rej USING (event_id)
WHERE e.event_id IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8);

-- @id synapse.events.fetch_redactions
-- @src synapse/storage/databases/main/events_worker.py:1700-1704
-- @style ? positional; redacts IN clause from make_in_list_sql_clause
-- @tags hot-small,hotpath,dynamic
-- @note Redaction check that follows every event fetch batch.
-- @param ?1 '$ev12898_9e19a71c'
-- @param ?2 '$ev20037_c3203a0f'
-- @param ?3 '$ev21537_d02d432b'
-- @param ?4 '$ev28287_8ae7ec29'
SELECT event_id, redacts, recheck FROM redactions WHERE redacts IN (?1, ?2, ?3, ?4);

-- @id synapse.events.get_all_new_forward_event_rows
-- @src synapse/storage/databases/main/events_worker.py:2010-2030
-- @style ? positional
-- @tags hotpath
-- @note Replication stream: events with five LEFT JOINs USING (event_id) (redactions, state_events, event_relations, room_memberships, rejections), range + instance filter, top-N.
-- @param ?1 30000
-- @param ?2 40000
-- @param ?3 'master'
-- @param ?4 100
SELECT e.stream_ordering, e.event_id, e.room_id, e.type, se.state_key, redacts, relates_to_id, membership, rejections.reason IS NOT NULL, e.outlier
FROM events AS e
LEFT JOIN redactions USING (event_id)
LEFT JOIN state_events AS se USING (event_id)
LEFT JOIN event_relations USING (event_id)
LEFT JOIN room_memberships USING (event_id)
LEFT JOIN rejections USING (event_id)
WHERE ?1 < stream_ordering AND stream_ordering <= ?2
AND instance_name = ?3
ORDER BY stream_ordering ASC
LIMIT ?4;

-- @id synapse.relations.get_relations_for_event_recursive
-- @src synapse/storage/databases/main/relations.py:240-265
-- @style ? positional; where_clause built from the relation filters (none here beyond the bound), order DESC
-- @tags hotpath,dynamic
-- @note Recursive relations walk (depth <= 3) with events joined inside the recursion, then ordered top-N.
-- @param ?1 '$ev12898_9e19a71c'
-- @param ?2 10
WITH RECURSIVE related_events AS (
    SELECT er.event_id, er.relation_type, ev.room_id, ev.sender,
        ev.topological_ordering, ev.stream_ordering, ev.type, 0 AS depth
    FROM event_relations er
    INNER JOIN events ev ON ev.event_id = er.event_id
    WHERE er.relates_to_id = ?1
    UNION ALL
    SELECT er.event_id, er.relation_type, ev.room_id, ev.sender,
        ev.topological_ordering, ev.stream_ordering, ev.type, r.depth + 1
    FROM related_events r
    INNER JOIN event_relations er ON er.relates_to_id = r.event_id
    INNER JOIN events ev ON ev.event_id = er.event_id
    WHERE r.depth <= 3
)
SELECT event_id, relation_type, sender, topological_ordering, stream_ordering
FROM related_events
WHERE (100000 >= stream_ordering)
ORDER BY topological_ordering DESC, stream_ordering DESC
LIMIT ?2;

-- @id synapse.relations.get_thread_id
-- @src synapse/storage/databases/main/relations.py:1035-1050
-- @style ? positional
-- @tags hotpath
-- @note Recursive UNION up the relation chain to find the thread root, top-1 by depth.
-- @param ?1 '$ev12331_313b2015'
WITH RECURSIVE related_events AS (
    SELECT event_id, relates_to_id, relation_type, 0 AS depth
    FROM event_relations
    WHERE event_id = ?1
    UNION SELECT e.event_id, e.relates_to_id, e.relation_type, depth + 1
    FROM event_relations e
    INNER JOIN related_events r ON r.relates_to_id = e.event_id
    WHERE depth <= 3
)
SELECT relates_to_id FROM related_events
WHERE relation_type = 'm.thread'
ORDER BY depth DESC
LIMIT 1;

-- @id synapse.push.unread_counts_by_room_summary
-- @src synapse/storage/databases/main/event_push_actions.py:371-437
-- @style ? positional; receipt_type IN clause from make_in_list_sql_clause; SQLite MAX(COALESCE,COALESCE) branch
-- @tags hotpath,dynamic
-- @note Badge counts: CTE of per-room/thread max receipts, joined twice as threaded/unthreaded derived tables, compared to the summary with scalar max().
-- @param ?1 'm.read'
-- @param ?2 'm.read.private'
-- @param ?3 '@user1334:example.org'
-- @param ?4 '@user1334:example.org'
WITH all_receipts AS (
    SELECT room_id, thread_id, MAX(event_stream_ordering) AS max_receipt_stream_ordering
    FROM receipts_linearized
    WHERE
        receipt_type IN (?1, ?2)
        AND user_id = ?3
    GROUP BY room_id, thread_id
)
SELECT eps.room_id, eps.thread_id, notif_count
FROM event_push_summary AS eps
LEFT JOIN (
    SELECT room_id, thread_id,
    max_receipt_stream_ordering AS threaded_receipt_stream_ordering
    FROM all_receipts
    WHERE thread_id IS NOT NULL
) AS threaded_receipts USING (room_id, thread_id)
LEFT JOIN (
    SELECT room_id, thread_id,
    max_receipt_stream_ordering AS unthreaded_receipt_stream_ordering
    FROM all_receipts
    WHERE thread_id IS NULL
) AS unthreaded_receipts USING (room_id)
WHERE user_id = ?4
    AND notif_count != 0
    AND (
        (last_receipt_stream_ordering IS NULL AND stream_ordering > MAX(
            COALESCE(threaded_receipt_stream_ordering, 0),
            COALESCE(unthreaded_receipt_stream_ordering, 0)
        ))
        OR last_receipt_stream_ordering = MAX(
            COALESCE(threaded_receipt_stream_ordering, 0),
            COALESCE(unthreaded_receipt_stream_ordering, 0)
        )
    );

-- @id synapse.push.unread_counts_by_room_actions
-- @src synapse/storage/databases/main/event_push_actions.py:445-461
-- @style ? positional; receipt_type IN clause from make_in_list_sql_clause
-- @tags hotpath,dynamic
-- @note Same receipts CTE, then COUNT(CASE ...) over unrotated push actions grouped by room/thread with a scalar subquery bound.
-- @param ?1 'm.read'
-- @param ?2 'm.read.private'
-- @param ?3 '@user1334:example.org'
-- @param ?4 '@user1334:example.org'
WITH all_receipts AS (
    SELECT room_id, thread_id, MAX(event_stream_ordering) AS max_receipt_stream_ordering
    FROM receipts_linearized
    WHERE
        receipt_type IN (?1, ?2)
        AND user_id = ?3
    GROUP BY room_id, thread_id
)
SELECT epa.room_id, epa.thread_id, COUNT(CASE WHEN epa.notif = 1 THEN 1 END) AS notif_count
FROM event_push_actions AS epa
LEFT JOIN (
    SELECT room_id, thread_id,
    max_receipt_stream_ordering AS threaded_receipt_stream_ordering
    FROM all_receipts
    WHERE thread_id IS NOT NULL
) AS threaded_receipts USING (room_id, thread_id)
LEFT JOIN (
    SELECT room_id, thread_id,
    max_receipt_stream_ordering AS unthreaded_receipt_stream_ordering
    FROM all_receipts
    WHERE thread_id IS NULL
) AS unthreaded_receipts USING (room_id)
WHERE user_id = ?4
    AND epa.notif = 1
    AND stream_ordering > (SELECT stream_ordering FROM event_push_summary_stream_ordering)
    AND (threaded_receipt_stream_ordering IS NULL OR stream_ordering > threaded_receipt_stream_ordering)
    AND (unthreaded_receipt_stream_ordering IS NULL OR stream_ordering > unthreaded_receipt_stream_ordering)
GROUP BY epa.room_id, epa.thread_id;

-- @id synapse.push.room_counts_summary
-- @src synapse/storage/databases/main/event_push_actions.py:612-640
-- @style ? positional; receipt_type IN clause from make_in_list_sql_clause
-- @tags hotpath,dynamic
-- @note Per-room notification counts on every sync: summary LEFT JOIN a grouped receipts derived table USING (thread_id), COALESCE comparisons.
-- @param ?1 '@user1334:example.org'
-- @param ?2 '!room1:example.org'
-- @param ?3 26064
-- @param ?4 'm.read'
-- @param ?5 'm.read.private'
-- @param ?6 '!room1:example.org'
-- @param ?7 '@user1334:example.org'
-- @param ?8 26064
-- @param ?9 26064
SELECT notif_count, COALESCE(unread_count, 0), thread_id
FROM event_push_summary
LEFT JOIN (
    SELECT thread_id, MAX(event_stream_ordering) AS threaded_receipt_stream_ordering
    FROM receipts_linearized
    WHERE
        user_id = ?1
        AND room_id = ?2
        AND event_stream_ordering > ?3
        AND receipt_type IN (?4, ?5)
    GROUP BY thread_id
) AS receipts USING (thread_id)
WHERE room_id = ?6 AND user_id = ?7
AND (
    (last_receipt_stream_ordering IS NULL AND stream_ordering > COALESCE(threaded_receipt_stream_ordering, ?8))
    OR last_receipt_stream_ordering = COALESCE(threaded_receipt_stream_ordering, ?9)
) AND (notif_count != 0 OR COALESCE(unread_count, 0) != 0);

-- @id synapse.push.room_unsummarised_counts
-- @src synapse/storage/databases/main/event_push_actions.py:725-760
-- @style ? positional; receipt_type IN and NOT thread_id IN clauses from make_in_list_sql_clause
-- @tags hotpath,dynamic
-- @note Two COUNT(CASE ...) aggregates per thread, excluding summarised threads with NOT IN.
-- @param ?1 '@user1334:example.org'
-- @param ?2 '!room1:example.org'
-- @param ?3 20000
-- @param ?4 'm.read'
-- @param ?5 'm.read.private'
-- @param ?6 '@user1334:example.org'
-- @param ?7 '!room1:example.org'
-- @param ?8 20000
-- @param ?9 '$nonexistent_thread'
SELECT
    COUNT(CASE WHEN notif = 1 THEN 1 END),
    COUNT(CASE WHEN unread = 1 THEN 1 END),
    thread_id
FROM event_push_actions
LEFT JOIN (
    SELECT thread_id, MAX(event_stream_ordering) AS threaded_receipt_stream_ordering
    FROM receipts_linearized
    WHERE
        user_id = ?1
        AND room_id = ?2
        AND event_stream_ordering > ?3
        AND receipt_type IN (?4, ?5)
    GROUP BY thread_id
) AS receipts USING (thread_id)
WHERE user_id = ?6
    AND room_id = ?7
    AND stream_ordering > COALESCE(threaded_receipt_stream_ordering, ?8)
    AND NOT thread_id IN (?9)
GROUP BY thread_id;

-- @id synapse.push.receipts_for_rooms_and_threads
-- @src synapse/storage/databases/main/event_push_actions.py:852-931
-- @style ? positional; receipt_type, thread_id and room_id IN clauses from make_in_list_sql_clause
-- @tags hotpath,dynamic
-- @note UNION ALL of two grouped MAX queries, the second joining events USING (room_id, event_id).
-- @param ?1 'm.read'
-- @param ?2 'm.read.private'
-- @param ?3 'main'
-- @param ?4 '!room1:example.org'
-- @param ?5 '!room6:example.org'
-- @param ?6 '@user1334:example.org'
-- @param ?7 'm.read'
-- @param ?8 'm.read.private'
-- @param ?9 '!room1:example.org'
-- @param ?10 '!room6:example.org'
-- @param ?11 '@user1334:example.org'
    SELECT room_id, thread_id, MAX(event_stream_ordering)
    FROM receipts_linearized
    WHERE receipt_type IN (?1, ?2)
        AND thread_id IN (?3)
        AND room_id IN (?4, ?5)
    AND user_id = ?6
    GROUP BY room_id, thread_id

UNION ALL

    SELECT room_id, thread_id, MAX(stream_ordering)
    FROM receipts_linearized
    INNER JOIN events USING (room_id, event_id)
    WHERE receipt_type IN (?7, ?8)
        AND room_id IN (?9, ?10)
        AND thread_id IS NULL
    AND user_id = ?11
    GROUP BY room_id, thread_id;

-- @id synapse.push.push_actions_for_http_pusher
-- @src synapse/storage/databases/main/event_push_actions.py:966-981
-- @style ? positional
-- @tags hotpath
-- @note HTTP pusher batch: per-user stream range, notif filter, ordered top-N.
-- @param ?1 '@user1334:example.org'
-- @param ?2 20000
-- @param ?3 42000
-- @param ?4 20
SELECT ep.event_id, ep.room_id, ep.thread_id, ep.stream_ordering,
    ep.actions, ep.highlight
FROM event_push_actions AS ep
WHERE
    ep.user_id = ?1
    AND ep.stream_ordering > ?2
    AND ep.stream_ordering <= ?3
    AND ep.notif = 1
ORDER BY ep.stream_ordering ASC LIMIT ?4;

-- @id synapse.push.rotate_notifs_counts
-- @src synapse/storage/databases/main/event_push_actions.py:1655-1690
-- @style ? positional; column names spliced in (notif_count / notif)
-- @tags dynamic
-- @note Notification rotation: grouped count over a stream window with a LEFT JOIN to the summary inside, then the summary joined again outside.
-- @param ?1 34000
-- @param ?2 41910
SELECT user_id, room_id, thread_id,
    coalesce(old.notif_count, 0) + upd.cnt,
    upd.stream_ordering
FROM (
    SELECT user_id, room_id, thread_id, count(*) as cnt,
        max(ea.stream_ordering) as stream_ordering
    FROM event_push_actions AS ea
    LEFT JOIN event_push_summary AS old USING (user_id, room_id, thread_id)
    WHERE ?1 < ea.stream_ordering AND ea.stream_ordering <= ?2
        AND (
            old.last_receipt_stream_ordering IS NULL
            OR old.last_receipt_stream_ordering < ea.stream_ordering
        )
        AND notif = 1
    GROUP BY user_id, room_id, thread_id
) AS upd
LEFT JOIN event_push_summary AS old USING (user_id, room_id, thread_id);

-- @id synapse.receipts.linearized_receipts_for_all_rooms
-- @src synapse/storage/databases/main/receipts.py:625-640
-- @style ? positional; bounds from make_multiwriter_sharded_token_bounds_sql (util/id_generators.py:1033) with an empty instance map
-- @tags hotpath,dynamic
-- @note Receipts stream for sync/federation: range on stream_id, ordered top-N.
-- @param ?1 5000
-- @param ?2 9000
-- @param ?3 100
SELECT stream_id, room_id, receipt_type, user_id, event_id, data
FROM receipts_linearized
WHERE (?1 < stream_id AND stream_id <= ?2)
ORDER BY stream_id ASC
LIMIT ?3;

-- @id synapse.receipts.existing_receipt_check
-- @src synapse/storage/databases/main/receipts.py:953-965
-- @style ? positional; thread_clause = "r.thread_id IS NULL"
-- @tags hot-small,hotpath,dynamic
-- @note Point lookup before every receipt write.
-- @param ?1 '!room1:example.org'
-- @param ?2 'm.read'
-- @param ?3 '@user1334:example.org'
SELECT r.event_stream_ordering, r.event_id FROM receipts_linearized AS r
WHERE r.room_id = ?1 AND r.receipt_type = ?2 AND r.user_id = ?3
AND r.event_stream_ordering IS NOT NULL AND r.thread_id IS NULL;

-- @id synapse.receipts.upsert_linearized_receipt
-- @src synapse/storage/databases/main/receipts.py:987-1007
-- @style ? positional; text generated by simple_upsert_txn_native_upsert (storage/database.py:1521) with where_clause "thread_id IS NULL"
-- @tags hot-small,hotpath,dynamic
-- @note Native UPSERT against a partial unique index (ON CONFLICT ... WHERE thread_id IS NULL DO UPDATE SET col=EXCLUDED.col).
-- @param ?1 '!room1:example.org'
-- @param ?2 'm.read'
-- @param ?3 '@user1334:example.org'
-- @param ?4 300000
-- @param ?5 'master'
-- @param ?6 '$ev41868_0feabf26'
-- @param ?7 41868
-- @param ?8 '{"ts":1701046700000}'
INSERT INTO receipts_linearized (room_id, receipt_type, user_id, stream_id, instance_name, event_id, event_stream_ordering, data)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
ON CONFLICT (room_id, receipt_type, user_id) WHERE thread_id IS NULL
DO UPDATE SET stream_id=EXCLUDED.stream_id, instance_name=EXCLUDED.instance_name, event_id=EXCLUDED.event_id,
              event_stream_ordering=EXCLUDED.event_stream_ordering, data=EXCLUDED.data;

-- @id synapse.members.users_in_room_with_profiles
-- @src synapse/storage/databases/main/roommember.py:282-296
-- @style ? positional
-- @tags hotpath
-- @note Member list: room_memberships joined to current_state_events on three columns.
-- @param ?1 '!room1:example.org'
-- @param ?2 'join'
SELECT state_key, display_name, avatar_url FROM room_memberships as m
INNER JOIN current_state_events as c
ON m.event_id = c.event_id
AND m.room_id = c.room_id
AND m.user_id = c.state_key
WHERE c.type = 'm.room.member' AND c.room_id = ?1 AND m.membership = ?2;

-- @id synapse.members.room_summary_heroes
-- @src synapse/storage/databases/main/roommember.py:340-365
-- @style ? positional
-- @tags hotpath
-- @note Room heroes for sync summaries: CASE-ranked membership order, then stream order, top-6.
-- @param ?1 '!room1:example.org'
-- @param ?2 'join'
-- @param ?3 'invite'
-- @param ?4 'leave'
-- @param ?5 6
SELECT state_key, membership, event_id
FROM current_state_events
WHERE type = 'm.room.member' AND room_id = ?1
    AND membership IS NOT NULL
ORDER BY
    CASE membership WHEN ?2 THEN 1 WHEN ?3 THEN 2 WHEN ?4 THEN 3 ELSE 4 END ASC,
    event_stream_ordering ASC
LIMIT ?5;

-- @id synapse.members.member_counts
-- @src synapse/storage/databases/main/roommember.py:390-405
-- @style ? positional
-- @tags hotpath
-- @note Member counts by membership for one room.
-- @param ?1 '!room1:example.org'
SELECT count(*), membership FROM current_state_events
WHERE type = 'm.room.member' AND room_id = ?1
    AND membership IS NOT NULL
GROUP BY membership;

-- @id synapse.members.rooms_for_user_with_membership
-- @src synapse/storage/databases/main/roommember.py:705-720
-- @style ? positional; c.membership IN clause from make_in_list_sql_clause
-- @tags hotpath,dynamic
-- @note Rooms for a user: local_current_membership JOIN events USING (room_id, event_id) JOIN rooms.
-- @param ?1 '@user1334:example.org'
-- @param ?2 'join'
-- @param ?3 'invite'
SELECT room_id, e.sender, c.membership, event_id, e.instance_name, e.stream_ordering, r.room_version
FROM local_current_membership AS c
INNER JOIN events AS e USING (room_id, event_id)
INNER JOIN rooms AS r USING (room_id)
WHERE
    user_id = ?1
    AND c.membership IN (?2, ?3);

-- @id synapse.members.sliding_sync_rooms_for_user
-- @src synapse/storage/databases/main/roommember.py:1840-1860
-- @style ? positional; m.room_id IN clause from make_in_list_sql_clause
-- @tags hotpath,dynamic
-- @note Sliding sync room list: snapshots JOIN rooms USING, LEFT JOIN joined-rooms on a conditional ON, COALESCE overrides.
-- @param ?1 '!room1:example.org'
-- @param ?2 '!room6:example.org'
-- @param ?3 '!room7:example.org'
-- @param ?4 '!room39:example.org'
-- @param ?5 '!room170:example.org'
-- @param ?6 '@user1334:example.org'
SELECT m.room_id, m.sender, m.membership, m.membership_event_id,
    r.room_version,
    m.event_instance_name, m.event_stream_ordering,
    m.has_known_state,
    COALESCE(j.room_type, m.room_type),
    COALESCE(j.is_encrypted, m.is_encrypted)
FROM sliding_sync_membership_snapshots AS m
INNER JOIN rooms AS r USING (room_id)
LEFT JOIN sliding_sync_joined_rooms AS j ON (j.room_id = m.room_id AND m.membership = 'join')
WHERE m.forgotten = 0
    AND m.room_id IN (?1, ?2, ?3, ?4, ?5)
    AND user_id = ?6;

-- @id synapse.rooms.largest_public_rooms_search
-- @src synapse/storage/databases/main/room.py:620-745
-- @style ? positional; published_sql UNION branch, generic_search_term LIKE clause, bounds omitted
-- @tags hotpath,dynamic
-- @note Room directory: UNION derived table joined to two stats tables, OR'd join-rule predicate, LOWER(...) LIKE search, top-N by member count.
-- @param ?1 '%matrix%'
-- @param ?2 '%matrix%'
-- @param ?3 '%matrix%'
-- @param ?4 21
SELECT
    room_id, name, topic, canonical_alias, joined_members,
    avatar, history_visibility, guest_access, join_rules, room_type
FROM (
    SELECT room_id FROM rooms WHERE is_public
    UNION SELECT room_id from appservice_room_list
) published
INNER JOIN room_stats_state USING (room_id)
INNER JOIN room_stats_current USING (room_id)
WHERE
    (
        join_rules = 'public'
        OR join_rules = 'knock'
        OR join_rules = 'knock_restricted'
        OR history_visibility = 'world_readable'
    )
    AND joined_members > 0
     AND
        (
            LOWER(name) LIKE ?1
            OR LOWER(topic) LIKE ?2
            OR LOWER(canonical_alias) LIKE ?3
        )
ORDER BY
    joined_members DESC,
    room_id DESC
LIMIT ?4;

-- @id synapse.rooms.get_room_with_stats
-- @src synapse/storage/databases/main/room.py:443-458
-- @style ? positional
-- @tags hot-small
-- @note Room point lookup with two LEFT JOINs USING (room_id).
-- @param ?1 '!room6:example.org'
SELECT room_id, state.name, state.canonical_alias, curr.joined_members,
  curr.local_users_in_room AS joined_local_members, rooms.room_version AS version,
  rooms.creator, state.encryption, state.is_federatable AS federatable,
  rooms.is_public AS public, state.join_rules, state.guest_access,
  state.history_visibility, curr.current_state_events AS state_events,
  state.avatar, state.topic, state.room_type
FROM rooms
LEFT JOIN room_stats_state state USING (room_id)
LEFT JOIN room_stats_current curr USING (room_id)
WHERE room_id = ?1;

-- @id synapse.search.search_rooms
-- @src synapse/storage/databases/main/search.py:630-680
-- @style ? positional; room_id IN clause, key OR clause and pagination clause appended; SQLite branch
-- @tags hotpath,dynamic,modified
-- @note Message search on SQLite: FTS4 MATCH in a subquery with matchinfo(), CROSS JOIN events USING (event_id) to force the FTS index first, keyset pagination, top-N.
-- @modified rank(matchinfo) is a Python function Synapse registers (_rank); replaced by length(matchinfo), which keeps a matchinfo-derived value in the result
-- @param ?1 'deploy release'
-- @param ?2 '!room1:example.org'
-- @param ?3 '!room6:example.org'
-- @param ?4 '!room39:example.org'
-- @param ?5 'content.body'
-- @param ?6 1701000000000
-- @param ?7 1701000000000
-- @param ?8 41000
-- @param ?9 10
SELECT
    length(matchinfo) as rank, room_id, event_id, origin_server_ts, stream_ordering
FROM (
    SELECT key, event_id, matchinfo(event_search) as matchinfo
    FROM event_search
    WHERE value MATCH ?1
)
CROSS JOIN events USING (event_id)
WHERE room_id IN (?2, ?3, ?4) AND (key = ?5) AND
    (origin_server_ts < ?6 OR (origin_server_ts = ?7 AND stream_ordering < ?8))
ORDER BY origin_server_ts DESC, stream_ordering DESC LIMIT ?9;

-- @id synapse.search.search_rooms_count
-- @src synapse/storage/databases/main/search.py:653-700
-- @style ? positional; room_id IN clause and key OR clause appended
-- @tags hotpath,dynamic
-- @note FTS4 MATCH count grouped by room.
-- @param ?1 'deploy release'
-- @param ?2 '!room1:example.org'
-- @param ?3 '!room6:example.org'
-- @param ?4 '!room39:example.org'
-- @param ?5 'content.body'
SELECT room_id, count(*) as count FROM event_search
WHERE value MATCH ?1 AND room_id IN (?2, ?3, ?4) AND (key = ?5)
GROUP BY room_id;

-- @id synapse.user_directory.search_user_dir
-- @src synapse/storage/databases/main/user_directory.py:1010-1140
-- @style ? positional; where_clause for search_all_users=false, show_locked_users=false, LEFT JOIN users; SQLite branch
-- @tags hotpath,dynamic,modified
-- @note User directory search: FTS4 MATCH joined to user_directory and users, two EXISTS visibility checks, ranked top-N.
-- @modified rank(matchinfo(user_directory_search)) is a Python function Synapse registers; replaced by length(offsets(user_directory_search)), a core-SQL "more matches first" stand-in
-- @param ?1 '@user1334:example.org'
-- @param ?2 '(alice* OR alice)'
-- @param ?3 11
SELECT d.user_id AS user_id, display_name, avatar_url
FROM user_directory_search as t
INNER JOIN user_directory AS d USING (user_id)
LEFT JOIN users AS u ON t.user_id = u.name
WHERE
    (
        EXISTS (select 1 from users_in_public_rooms WHERE user_id = t.user_id)
        OR EXISTS (
            SELECT 1 FROM users_who_share_private_rooms
            WHERE user_id = ?1 AND other_user_id = t.user_id
        )
    )
 AND (u.locked IS NULL OR u.locked = FALSE)
    AND value MATCH ?2
ORDER BY
    length(offsets(user_directory_search)) DESC,
    display_name IS NULL,
    avatar_url IS NULL
LIMIT ?3;

-- @id synapse.state.state_groups_state_for_group
-- @src synapse/storage/databases/state/bg_updates.py:225-260
-- @style ? positional; where_clause from StateFilter.make_sql_filter_clause for (m.room.history_visibility, '') and (m.room.member, user)
-- @tags hot-small,hotpath,dynamic
-- @note SQLite walks the state-group chain in Python: one of these per hop.
-- @param ?1 25
-- @param ?2 'm.room.history_visibility'
-- @param ?3 ''
-- @param ?4 'm.room.member'
-- @param ?5 '@user182:example.org'
SELECT type, state_key, event_id FROM state_groups_state WHERE state_group = ?1
 AND ((type = ?2 AND state_key = ?3) OR (type = ?4 AND state_key = ?5));

-- @id synapse.state.state_group_edges_next_hop
-- @src synapse/storage/databases/state/bg_updates.py:280-287
-- @style ? positional; simple_select_one_onecol_txn (storage/database.py)
-- @tags hot-small,hotpath,dynamic
-- @note The per-hop prev_state_group point lookup that follows each state fetch.
-- @param ?1 25
SELECT prev_state_group FROM state_group_edges WHERE state_group = ?1;

-- @id synapse.state.deletion_ancestors
-- @src synapse/storage/databases/state/deletion.py:520-536
-- @style ? positional; state_group IN clause from make_in_list_sql_clause
-- @tags dynamic
-- @note Recursive UNION walking state_group_edges to all ancestors of a set of groups.
-- @param ?1 30
-- @param ?2 75
-- @param ?3 150
WITH RECURSIVE ancestors(state_group) AS (
    SELECT DISTINCT prev_state_group
    FROM state_group_edges WHERE state_group IN (?1, ?2, ?3)
    UNION
    SELECT prev_state_group
    FROM state_group_edges
    INNER JOIN ancestors USING (state_group)
)
SELECT state_group FROM ancestors;
