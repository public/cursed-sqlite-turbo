-- atuinsh/atuin @ a9fa414a52a45f627577ff3d99dd4ba86311d32f (MIT). crates/atuin-client/migrations/*.sql (history.db) followed by
-- crates/atuin-client/record-migrations/*.sql (records.db), concatenated verbatim in migration order. Atuin keeps the two in
-- separate database files; they share one database here.

-- == migrations/20210422143411_create_history.sql
-- Add migration script here
create table if not exists history (
	id text primary key,
	timestamp integer not null,
	duration integer not null,
	exit integer not null,
	command text not null,
	cwd text not null,
	session text not null,
	hostname text not null,

	unique(timestamp, cwd, command)
);

create index if not exists idx_history_timestamp on history(timestamp);
create index if not exists idx_history_command on history(command);

-- == migrations/20220505083406_create-events.sql
create table if not exists events (
	id text primary key,
	timestamp integer not null,
	hostname text not null,
	event_type text not null,

	history_id text not null
);

-- Ensure there is only ever one of each event type per history item
create unique index history_event_idx ON events(event_type, history_id);

-- == migrations/20220806155627_interactive_search_index.sql
-- Interactive search filters by command then by the max(timestamp) for that
-- command. Create an index that covers those
create index if not exists idx_history_command_timestamp on history(
	command,
	timestamp
);

-- == migrations/20230315220114_drop-events.sql
-- Add migration script here
drop table events;

-- == migrations/20230319185725_deleted_at.sql
-- Add migration script here
alter table history add column deleted_at integer;

-- == migrations/20260224000100_history_author_intent.sql
alter table history add column author text;
alter table history add column intent text;

-- == migrations/20260709214605_shell.sql
alter table history add column shell text;

-- == migrations/20260723000000_active_history_index.sql
-- Most queries only consider live history (deleted_at is null), and counting
-- it previously required a full table scan - slow on a large, cold database.
-- A partial index on timestamp covers both the count and timestamp-ordered
-- listings of live history, at a fraction of the table's size.
create index if not exists idx_history_active_timestamp on history(timestamp)
where deleted_at is null;

-- == migrations/20260723000001_filtered_history_indexes.sql
-- The session, directory and workspace filters (`session = ?`, `cwd = ?`,
-- `cwd like 'x%'`) had no index, so the timestamp-ordered dedup scan in
-- search() and list() read the whole table per keystroke when matches were
-- sparse. Partial indexes over live history keep that a range scan, at a
-- fraction of the size of a full index.
create index if not exists idx_history_session_timestamp on history(session, timestamp)
where deleted_at is null;

create index if not exists idx_history_cwd_timestamp on history(cwd, timestamp)
where deleted_at is null;

-- == migrations/20260723000002_hostname_index.sql
-- The host filter compares lower(hostname), because the reported casing of
-- the same machine changes over time (e.g. "Ellies-MBP" vs "ellies-mbp").
-- Index the same expression so the filter is sargable rather than a scan.
create index if not exists idx_history_hostname_timestamp on history(lower(hostname), timestamp)
where deleted_at is null;

-- == migrations/20260723000003_drop_command_index.sql
-- idx_history_command (from the original 2021 schema) has been redundant
-- since idx_history_command_timestamp was added: it shares the leading
-- column, so every query that could use it plans identically onto the
-- (command, timestamp) index. Dropping it saves ~9MB on a 100MB database
-- and removes an index from the per-command insert path.
drop index if exists idx_history_command;

-- == migrations/20260818000000_history_author_kind.sql
-- Whether a human or an agent ran the command. If null, we have to go off
-- the author name.
alter table history add column author_kind integer;

-- == record-migrations/20230531212437_create-records.sql
-- Add migration script here
create table if not exists records (
  id text primary key,
  parent text unique, -- null if this is the first one
  host text not null,

  timestamp integer not null,
  tag text not null,
  version text not null,
  data blob not null,
  cek blob not null
);

create index host_idx on records (host);
create index tag_idx on records (tag);
create index host_tag_idx on records (host, tag);

-- == record-migrations/20231127090831_create-store.sql
-- Add migration script here
create table if not exists store (
  id text primary key,   -- globally unique ID

  idx integer,           -- incrementing integer ID unique per (host, tag)
  host text not null, -- references the host row
  tag text not null,

  timestamp integer not null,
  version text not null,
  data blob not null,
  cek blob not null
);

create unique index record_uniq ON store(host, tag, idx);

-- == record-migrations/20260723000000_store_tag_index.sql
-- all_tagged and len_tag select by tag ordered by timestamp; without an
-- index they scan and sort the entire store - over a second on a large,
-- cold store - on every kv/scripts/dotfiles load and store rebuild.
create index if not exists idx_store_tag_timestamp on store(tag, timestamp);
