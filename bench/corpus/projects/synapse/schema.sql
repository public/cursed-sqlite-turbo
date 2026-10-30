-- element-hq/synapse @ b20ae98cc5ead16212de01f00dff8862f1766bb3 (AGPL-3.0). Only the CREATE statements the queries
-- need. Built by applying synapse/storage/schema/{main,state}/full_schemas/72/full.sql.sqlite plus every later
-- main/delta/*.sql and *.sql.sqlite file up to delta 95, then dumping these tables from sqlite_master.
-- The trailing block adds indexes Synapse creates through background updates (register_background_index_update /
-- create_index_in_background in synapse/storage/databases/**), which a running server has.
CREATE TABLE events( stream_ordering INTEGER PRIMARY KEY, topological_ordering BIGINT NOT NULL, event_id TEXT NOT NULL, type TEXT NOT NULL, room_id TEXT NOT NULL, content TEXT, unrecognized_keys TEXT, processed BOOL NOT NULL, outlier BOOL NOT NULL, depth BIGINT DEFAULT 0 NOT NULL, origin_server_ts BIGINT, received_ts BIGINT, sender TEXT, contains_url BOOLEAN, instance_name TEXT, state_key TEXT DEFAULT NULL, rejection_reason TEXT DEFAULT NULL, UNIQUE (event_id) );
CREATE INDEX event_contains_url_index ON events (room_id, topological_ordering, stream_ordering) WHERE contains_url = true AND outlier = false;
CREATE INDEX events_order_room ON events ( room_id, topological_ordering, stream_ordering );
CREATE INDEX events_room_stream on events(room_id, stream_ordering);
CREATE INDEX events_ts ON events(origin_server_ts, stream_ordering);
CREATE TABLE event_json( event_id TEXT NOT NULL, room_id TEXT NOT NULL, internal_metadata TEXT NOT NULL, json TEXT NOT NULL, format_version INTEGER, UNIQUE (event_id) );
CREATE TABLE rooms( room_id TEXT PRIMARY KEY NOT NULL, is_public BOOL, creator TEXT , room_version TEXT, has_auth_chain_index BOOLEAN);
CREATE INDEX public_room_index on rooms(is_public);
CREATE TABLE rejections( event_id TEXT NOT NULL, reason TEXT NOT NULL, last_check TEXT NOT NULL, UNIQUE (event_id) );
CREATE TABLE redactions ( event_id TEXT NOT NULL, redacts TEXT NOT NULL, have_censored BOOL NOT NULL DEFAULT false, received_ts BIGINT, recheck boolean NOT NULL DEFAULT true, UNIQUE (event_id) );
CREATE INDEX redactions_have_censored_ts ON redactions (received_ts) WHERE NOT have_censored;
CREATE INDEX redactions_redacts ON redactions (redacts);
CREATE TABLE state_events( event_id TEXT NOT NULL, room_id TEXT NOT NULL, type TEXT NOT NULL, state_key TEXT NOT NULL, prev_state TEXT, UNIQUE (event_id) );
CREATE TABLE event_relations ( event_id TEXT NOT NULL, relates_to_id TEXT NOT NULL, relation_type TEXT NOT NULL, aggregation_key TEXT );
CREATE UNIQUE INDEX event_relations_id ON event_relations(event_id);
CREATE INDEX event_relations_relates ON event_relations(relates_to_id, relation_type, aggregation_key);
CREATE TABLE room_memberships( event_id TEXT NOT NULL, user_id TEXT NOT NULL, sender TEXT NOT NULL, room_id TEXT NOT NULL, membership TEXT NOT NULL, forgotten INTEGER DEFAULT 0, display_name TEXT, avatar_url TEXT, event_stream_ordering BIGINT REFERENCES events(stream_ordering), participant BOOLEAN DEFAULT FALSE, UNIQUE (event_id) );
CREATE INDEX room_memberships_room_id ON room_memberships (room_id);
CREATE INDEX room_memberships_user_id ON room_memberships (user_id);
CREATE INDEX room_memberships_user_room_forgotten ON room_memberships (user_id, room_id) WHERE forgotten = 1;
CREATE TABLE current_state_events( event_id TEXT NOT NULL, room_id TEXT NOT NULL, type TEXT NOT NULL, state_key TEXT NOT NULL, membership TEXT, event_stream_ordering BIGINT REFERENCES events(stream_ordering), UNIQUE (event_id), UNIQUE (room_id, type, state_key) );
CREATE INDEX current_state_events_member_index ON current_state_events (state_key) WHERE type='m.room.member';
CREATE TABLE current_state_delta_stream ( stream_id BIGINT NOT NULL, room_id TEXT NOT NULL, type TEXT NOT NULL, state_key TEXT NOT NULL, event_id TEXT, prev_event_id TEXT , instance_name TEXT);
CREATE INDEX current_state_delta_stream_idx ON current_state_delta_stream(stream_id);
CREATE TABLE local_current_membership (
            room_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            event_id TEXT NOT NULL,
            membership TEXT NOT NULL
        , event_stream_ordering BIGINT REFERENCES events(stream_ordering));
CREATE UNIQUE INDEX local_current_membership_idx ON local_current_membership(user_id, room_id);
CREATE INDEX local_current_membership_room_idx ON local_current_membership(room_id);
CREATE TABLE "receipts_linearized" (
    stream_id BIGINT NOT NULL,
    room_id TEXT NOT NULL,
    receipt_type TEXT NOT NULL,
    user_id TEXT NOT NULL,
    event_id TEXT NOT NULL,
    thread_id TEXT,
    event_stream_ordering BIGINT,
    data TEXT NOT NULL, instance_name TEXT,
    CONSTRAINT receipts_linearized_uniqueness_thread UNIQUE (room_id, receipt_type, user_id, thread_id)
);
CREATE INDEX receipts_linearized_id ON receipts_linearized( stream_id );
CREATE INDEX receipts_linearized_room_stream ON receipts_linearized( room_id, stream_id );
CREATE INDEX receipts_linearized_user ON receipts_linearized( user_id );
CREATE TABLE "event_push_actions" (
    room_id TEXT NOT NULL,
    event_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    profile_tag VARCHAR(32),
    actions TEXT NOT NULL,
    topological_ordering BIGINT,
    stream_ordering BIGINT,
    notif SMALLINT,
    highlight SMALLINT,
    unread SMALLINT,
    thread_id TEXT,
    CONSTRAINT event_id_user_id_profile_tag_uniqueness UNIQUE (room_id, event_id, user_id, profile_tag),
    CONSTRAINT event_push_actions_thread_id CHECK (thread_id is NOT NULL)
);
CREATE INDEX event_push_actions_highlights_index ON event_push_actions (user_id, room_id, topological_ordering, stream_ordering);
CREATE INDEX event_push_actions_rm_tokens on event_push_actions( user_id, room_id, topological_ordering, stream_ordering );
CREATE INDEX event_push_actions_room_id_user_id on event_push_actions(room_id, user_id);
CREATE INDEX event_push_actions_stream_ordering on event_push_actions( stream_ordering, user_id );
CREATE INDEX event_push_actions_u_highlight ON event_push_actions (user_id, stream_ordering);
CREATE TABLE "event_push_summary" (
    user_id TEXT NOT NULL,
    room_id TEXT NOT NULL,
    notif_count BIGINT NOT NULL,
    stream_ordering BIGINT NOT NULL,
    unread_count BIGINT,
    last_receipt_stream_ordering BIGINT,
    thread_id TEXT,
    CONSTRAINT event_push_summary_thread_id CHECK (thread_id is NOT NULL)
);
CREATE UNIQUE INDEX event_push_summary_unique_index2 ON event_push_summary (user_id, room_id, thread_id) ;
CREATE TABLE event_push_summary_stream_ordering ( Lock CHAR(1) NOT NULL DEFAULT 'X' UNIQUE, stream_ordering BIGINT NOT NULL, CHECK (Lock='X') );
CREATE VIRTUAL TABLE event_search USING fts4 ( event_id, room_id, sender, key, value );
CREATE TABLE "user_directory" ( user_id TEXT NOT NULL, room_id TEXT, display_name TEXT, avatar_url TEXT );
CREATE INDEX user_directory_room_idx ON user_directory(room_id);
CREATE UNIQUE INDEX user_directory_user_idx ON user_directory(user_id);
CREATE VIRTUAL TABLE user_directory_search USING fts4 ( user_id, value );
CREATE TABLE users( name TEXT, password_hash TEXT, creation_ts BIGINT, admin SMALLINT DEFAULT 0 NOT NULL, upgrade_ts BIGINT, is_guest SMALLINT DEFAULT 0 NOT NULL, appservice_id TEXT, consent_version TEXT, consent_server_notice_sent TEXT, user_type TEXT DEFAULT NULL, deactivated SMALLINT DEFAULT 0 NOT NULL, shadow_banned BOOLEAN, consent_ts bigint, approved BOOLEAN, locked BOOLEAN DEFAULT FALSE NOT NULL, suspended BOOLEAN DEFAULT FALSE NOT NULL, UNIQUE(name) );
CREATE INDEX users_creation_ts ON users (creation_ts);
CREATE TABLE users_in_public_rooms ( user_id TEXT NOT NULL, room_id TEXT NOT NULL );
CREATE INDEX users_in_public_rooms_r_idx ON users_in_public_rooms(room_id);
CREATE UNIQUE INDEX users_in_public_rooms_u_idx ON users_in_public_rooms(user_id, room_id);
CREATE TABLE users_who_share_private_rooms ( user_id TEXT NOT NULL, other_user_id TEXT NOT NULL, room_id TEXT NOT NULL );
CREATE INDEX users_who_share_private_rooms_o_idx ON users_who_share_private_rooms(other_user_id);
CREATE INDEX users_who_share_private_rooms_r_idx ON users_who_share_private_rooms(room_id);
CREATE UNIQUE INDEX users_who_share_private_rooms_u_idx ON users_who_share_private_rooms(user_id, other_user_id, room_id);
CREATE TABLE room_stats_state (
    room_id TEXT NOT NULL,
    name TEXT,
    canonical_alias TEXT,
    join_rules TEXT,
    history_visibility TEXT,
    encryption TEXT,
    avatar TEXT,
    guest_access TEXT,
    is_federatable BOOLEAN,
    topic TEXT
, room_type TEXT);
CREATE UNIQUE INDEX room_stats_state_room ON room_stats_state(room_id);
CREATE TABLE room_stats_current (
    room_id TEXT NOT NULL PRIMARY KEY,

    -- These are absolute counts
    current_state_events INT NOT NULL,
    joined_members INT NOT NULL,
    invited_members INT NOT NULL,
    left_members INT NOT NULL,
    banned_members INT NOT NULL,

    local_users_in_room INT NOT NULL,

    -- The maximum delta stream position that this row takes into account.
    completed_delta_stream_id BIGINT NOT NULL
, knocked_members INT);
CREATE TABLE appservice_room_list( appservice_id TEXT NOT NULL, network_id TEXT NOT NULL, room_id TEXT NOT NULL );
CREATE UNIQUE INDEX appservice_room_list_idx ON appservice_room_list( appservice_id, network_id, room_id );
CREATE TABLE sliding_sync_membership_snapshots(
    room_id TEXT NOT NULL REFERENCES rooms(room_id),
    user_id TEXT NOT NULL,
    -- Useful to be able to tell leaves from kicks (where the `user_id` is different from the `sender`)
    sender TEXT NOT NULL,
    membership_event_id TEXT NOT NULL REFERENCES events(event_id),
    membership TEXT NOT NULL,
    -- This is an integer just to match `room_memberships` and also means we don't need
    -- to do any casting.
    forgotten INTEGER DEFAULT 0 NOT NULL,
    -- `stream_ordering` of the `membership_event_id`
    event_stream_ordering BIGINT NOT NULL REFERENCES events(stream_ordering),
    -- `instance_name` of the worker that persisted the `membership_event_id`.
    -- Useful for crafting `PersistedEventPosition(...)`
    event_instance_name TEXT NOT NULL,
    -- For remote invites/knocks that don't include any stripped state, we want to be
    -- able to distinguish between a room with `None` as valid value for some state and
    -- room where the state is completely unknown. Basically, this should be True unless
    -- no stripped state was provided for a remote invite/knock (False).
    has_known_state BOOLEAN DEFAULT FALSE NOT NULL,
    -- `m.room.create` -> `content.type` (according to the current state at the time of
    -- the membership).
    --
    -- Useful for the `spaces`/`not_spaces` filter in the Sliding Sync API
    room_type TEXT,
    -- `m.room.name` -> `content.name` (according to the current state at the time of
    -- the membership).
    --
    -- Useful for the room meta data and `room_name_like` filter in the Sliding Sync API
    room_name TEXT,
    -- `m.room.encryption` -> `content.algorithm` (according to the current state at the
    -- time of the membership).
    --
    -- Useful for the `is_encrypted` filter in the Sliding Sync API
    is_encrypted BOOLEAN DEFAULT FALSE NOT NULL,
    -- `m.room.tombstone` -> `content.replacement_room` (according to the current state at the
    -- time of the membership).
    --
    -- Useful for the `include_old_rooms` functionality in the Sliding Sync API
    tombstone_successor_room_id TEXT,
    PRIMARY KEY (room_id, user_id)
);
CREATE UNIQUE INDEX sliding_sync_membership_snapshots_event_stream_ordering ON sliding_sync_membership_snapshots(event_stream_ordering);
CREATE INDEX sliding_sync_membership_snapshots_user_id ON sliding_sync_membership_snapshots(user_id);
CREATE TABLE sliding_sync_joined_rooms(
    room_id TEXT NOT NULL REFERENCES rooms(room_id),
    -- The `stream_ordering` of the most-recent/latest event in the room
    event_stream_ordering BIGINT NOT NULL REFERENCES events(stream_ordering),
    -- The `stream_ordering` of the last event according to the `bump_event_types`
    bump_stamp BIGINT,
    -- `m.room.create` -> `content.type` (current state)
    --
    -- Useful for the `spaces`/`not_spaces` filter in the Sliding Sync API
    room_type TEXT,
    -- `m.room.name` -> `content.name` (current state)
    --
    -- Useful for the room meta data and `room_name_like` filter in the Sliding Sync API
    room_name TEXT,
    -- `m.room.encryption` -> `content.algorithm` (current state)
    --
    -- Useful for the `is_encrypted` filter in the Sliding Sync API
    is_encrypted BOOLEAN DEFAULT FALSE NOT NULL,
    -- `m.room.tombstone` -> `content.replacement_room` (according to the current state at the
    -- time of the membership).
    --
    -- Useful for the `include_old_rooms` functionality in the Sliding Sync API
    tombstone_successor_room_id TEXT,
    PRIMARY KEY (room_id)
);
CREATE UNIQUE INDEX sliding_sync_joined_rooms_event_stream_ordering ON sliding_sync_joined_rooms(event_stream_ordering);
CREATE TABLE state_group_edges (
    state_group BIGINT NOT NULL,
    prev_state_group BIGINT NOT NULL
);
CREATE INDEX state_group_edges_prev_idx ON state_group_edges (prev_state_group);
CREATE UNIQUE INDEX state_group_edges_unique_idx ON state_group_edges (state_group, prev_state_group) ;
CREATE TABLE state_groups_state (
    state_group BIGINT NOT NULL,
    room_id TEXT NOT NULL,
    type TEXT NOT NULL,
    state_key TEXT NOT NULL,
    event_id TEXT NOT NULL
);
CREATE INDEX state_groups_state_type_idx ON state_groups_state (state_group, type, state_key);
CREATE TABLE state_groups (
    id BIGINT PRIMARY KEY,
    room_id TEXT NOT NULL,
    event_id TEXT NOT NULL
);
CREATE INDEX state_groups_room_id_idx ON state_groups (room_id) ;

-- background-update indexes
CREATE UNIQUE INDEX receipts_linearized_unique_index ON receipts_linearized (room_id, receipt_type, user_id) WHERE thread_id IS NULL;
CREATE INDEX receipts_linearized_event_id ON receipts_linearized (room_id, event_id);
CREATE INDEX current_state_delta_stream_room_idx ON current_state_delta_stream (room_id, stream_id);
CREATE INDEX current_state_events_members_room_index ON current_state_events (room_id, membership) WHERE type='m.room.member';
CREATE INDEX current_state_events_stream_ordering_idx ON current_state_events (event_stream_ordering);
CREATE INDEX event_push_actions_stream_highlight_index ON event_push_actions (highlight, stream_ordering) WHERE highlight=0;
CREATE INDEX event_push_summary_index_room_id ON event_push_summary (room_id);
CREATE INDEX events_jump_to_date_idx ON events (room_id, origin_server_ts) WHERE NOT outlier;
CREATE INDEX received_ts_idx ON events (received_ts);
CREATE INDEX local_current_membership_stream_ordering_idx ON local_current_membership (event_stream_ordering);
CREATE INDEX room_membership_user_room_idx ON room_memberships (user_id, room_id);
CREATE INDEX room_memberships_stream_ordering_idx ON room_memberships (event_stream_ordering);
CREATE INDEX sliding_sync_membership_snapshots_membership_event_id_idx ON sliding_sync_membership_snapshots (membership_event_id);
CREATE INDEX sliding_sync_membership_snapshots_user_id_stream_ordering ON sliding_sync_membership_snapshots (user_id, event_stream_ordering);
