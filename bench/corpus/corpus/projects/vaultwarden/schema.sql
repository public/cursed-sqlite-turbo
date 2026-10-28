-- dani-garcia/vaultwarden @ 0f44744ef86a2a7bea615af1c024044ce5736187 (AGPL-3.0)
-- Final-state CREATE statements for the tables the queries use, derived from migrations/sqlite/*/up.sql
-- (2018-01-14-171611_create_tables, 2018-02-17-205753_create_collections_and_orgs, 2018-04-27-155151_create_users_ciphers,
-- 2018-05-08-161616_create_collection_cipher_map, 2018-05-25-232323_update_attachments_reference,
-- 2020-03-13-205045_add_policy_table, 2020-08-02-025025_add_favorites_table (ciphers rebuild),
-- 2021-03-11-190243_add_sends, 2022-03-02-210038_update_devices_primary_key, 2022-07-27-110000_add_group_support,
-- 2026-03-09-005927_add_archives) with every later ALTER TABLE ... ADD/RENAME COLUMN folded in; column set checked
-- against src/db/schema.rs. The SQLite migrations create no secondary indexes. Original files: tools/fetch.sh.

CREATE TABLE users (
  uuid                   TEXT     NOT NULL PRIMARY KEY,
  created_at             DATETIME NOT NULL,
  updated_at             DATETIME NOT NULL,
  email                  TEXT     NOT NULL UNIQUE,
  name                   TEXT     NOT NULL,
  password_hash          BLOB     NOT NULL,
  salt                   BLOB     NOT NULL,
  password_iterations    INTEGER  NOT NULL,
  password_hint          TEXT,
  akey                   TEXT     NOT NULL,
  private_key            TEXT,
  public_key             TEXT,
  totp_secret            TEXT,
  totp_recover           TEXT,
  security_stamp         TEXT     NOT NULL,
  equivalent_domains     TEXT     NOT NULL,
  excluded_globals       TEXT     NOT NULL,
  client_kdf_type        INTEGER  NOT NULL DEFAULT 0,
  client_kdf_iter        INTEGER  NOT NULL DEFAULT 100000,
  verified_at            DATETIME DEFAULT NULL,
  last_verifying_at      DATETIME DEFAULT NULL,
  login_verify_count     INTEGER  NOT NULL DEFAULT 0,
  email_new              TEXT     DEFAULT NULL,
  email_new_token        TEXT     DEFAULT NULL,
  enabled                BOOLEAN  NOT NULL DEFAULT 1,
  stamp_exception        TEXT     DEFAULT NULL,
  api_key                TEXT,
  avatar_color           TEXT,
  client_kdf_memory      INTEGER  DEFAULT NULL,
  client_kdf_parallelism INTEGER  DEFAULT NULL,
  external_id            TEXT,
  key_id                 TEXT
);

CREATE TABLE devices (
  uuid               TEXT NOT NULL,
  created_at         DATETIME NOT NULL,
  updated_at         DATETIME NOT NULL,
  user_uuid          TEXT NOT NULL,
  name               TEXT NOT NULL,
  atype              INTEGER NOT NULL,
  push_token         TEXT,
  refresh_token      TEXT NOT NULL,
  twofactor_remember TEXT,
  push_uuid          TEXT,
  PRIMARY KEY(uuid, user_uuid),
  FOREIGN KEY(user_uuid) REFERENCES users(uuid)
);

CREATE TABLE organizations (
  uuid          TEXT NOT NULL PRIMARY KEY,
  name          TEXT NOT NULL,
  billing_email TEXT NOT NULL,
  private_key   TEXT,
  public_key    TEXT
);

CREATE TABLE ciphers (
  uuid              TEXT     NOT NULL PRIMARY KEY,
  created_at        DATETIME NOT NULL,
  updated_at        DATETIME NOT NULL,
  user_uuid         TEXT     REFERENCES users(uuid),
  organization_uuid TEXT     REFERENCES organizations(uuid),
  atype             INTEGER  NOT NULL,
  name              TEXT     NOT NULL,
  notes             TEXT,
  fields            TEXT,
  data              TEXT     NOT NULL,
  password_history  TEXT,
  deleted_at        DATETIME,
  reprompt          INTEGER,
  "key"             TEXT
);

CREATE TABLE attachments (
  id          TEXT    NOT NULL PRIMARY KEY,
  cipher_uuid TEXT    NOT NULL REFERENCES ciphers (uuid),
  file_name   TEXT    NOT NULL,
  file_size   INTEGER NOT NULL,
  akey        TEXT
);

CREATE TABLE folders (
  uuid       TEXT     NOT NULL PRIMARY KEY,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  user_uuid  TEXT     NOT NULL REFERENCES users (uuid),
  name       TEXT     NOT NULL
);

CREATE TABLE folders_ciphers (
  cipher_uuid TEXT NOT NULL REFERENCES ciphers (uuid),
  folder_uuid TEXT NOT NULL REFERENCES folders (uuid),
  PRIMARY KEY (cipher_uuid, folder_uuid)
);

CREATE TABLE collections (
  uuid        TEXT NOT NULL PRIMARY KEY,
  org_uuid    TEXT NOT NULL REFERENCES organizations (uuid),
  name        TEXT NOT NULL,
  external_id TEXT
);

CREATE TABLE users_collections (
  user_uuid       TEXT NOT NULL REFERENCES users (uuid),
  collection_uuid TEXT NOT NULL REFERENCES collections (uuid),
  read_only       BOOLEAN NOT NULL DEFAULT 0,
  hide_passwords  BOOLEAN NOT NULL DEFAULT 0,
  manage          BOOLEAN NOT NULL DEFAULT 0,
  PRIMARY KEY (user_uuid, collection_uuid)
);

CREATE TABLE users_organizations (
  uuid               TEXT    NOT NULL PRIMARY KEY,
  user_uuid          TEXT    NOT NULL REFERENCES users (uuid),
  org_uuid           TEXT    NOT NULL REFERENCES organizations (uuid),
  access_all         BOOLEAN NOT NULL,
  akey               TEXT    NOT NULL,
  status             INTEGER NOT NULL,
  atype              INTEGER NOT NULL,
  reset_password_key TEXT,
  external_id        TEXT,
  invited_by_email   TEXT DEFAULT NULL,
  UNIQUE (user_uuid, org_uuid)
);

CREATE TABLE ciphers_collections (
  cipher_uuid     TEXT NOT NULL REFERENCES ciphers (uuid),
  collection_uuid TEXT NOT NULL REFERENCES collections (uuid),
  PRIMARY KEY (cipher_uuid, collection_uuid)
);

CREATE TABLE org_policies (
  uuid          TEXT     NOT NULL PRIMARY KEY,
  org_uuid      TEXT     NOT NULL REFERENCES organizations (uuid),
  atype         INTEGER  NOT NULL,
  enabled       BOOLEAN  NOT NULL,
  data          TEXT     NOT NULL,
  revision_date DATETIME NOT NULL DEFAULT '1970-01-01 00:00:00',
  UNIQUE (org_uuid, atype)
);

CREATE TABLE favorites (
  user_uuid   TEXT NOT NULL REFERENCES users(uuid),
  cipher_uuid TEXT NOT NULL REFERENCES ciphers(uuid),
  PRIMARY KEY (user_uuid, cipher_uuid)
);

CREATE TABLE sends (
  uuid              TEXT NOT NULL   PRIMARY KEY,
  user_uuid         TEXT            REFERENCES users (uuid),
  organization_uuid TEXT            REFERENCES organizations (uuid),
  name              TEXT    NOT NULL,
  notes             TEXT,
  atype             INTEGER NOT NULL,
  data              TEXT    NOT NULL,
  akey              TEXT    NOT NULL,
  password_hash     BLOB,
  password_salt     BLOB,
  password_iter     INTEGER,
  max_access_count  INTEGER,
  access_count      INTEGER NOT NULL,
  creation_date     DATETIME NOT NULL,
  revision_date     DATETIME NOT NULL,
  expiration_date   DATETIME,
  deletion_date     DATETIME NOT NULL,
  disabled          BOOLEAN NOT NULL,
  hide_email        BOOLEAN
);

CREATE TABLE groups (
  uuid               TEXT NOT NULL PRIMARY KEY,
  organizations_uuid TEXT NOT NULL REFERENCES organizations (uuid),
  name               TEXT NOT NULL,
  access_all         BOOLEAN NOT NULL,
  external_id        TEXT NULL,
  creation_date      TIMESTAMP NOT NULL,
  revision_date      TIMESTAMP NOT NULL
);

CREATE TABLE groups_users (
  groups_uuid              TEXT NOT NULL REFERENCES groups (uuid),
  users_organizations_uuid TEXT NOT NULL REFERENCES users_organizations (uuid),
  UNIQUE (groups_uuid, users_organizations_uuid)
);

CREATE TABLE collections_groups (
  collections_uuid TEXT NOT NULL REFERENCES collections (uuid),
  groups_uuid      TEXT NOT NULL REFERENCES groups (uuid),
  read_only        BOOLEAN NOT NULL,
  hide_passwords   BOOLEAN NOT NULL,
  manage           BOOLEAN NOT NULL DEFAULT 0,
  UNIQUE (collections_uuid, groups_uuid)
);

CREATE TABLE archives (
  user_uuid   CHAR(36) NOT NULL REFERENCES users (uuid) ON DELETE CASCADE,
  cipher_uuid CHAR(36) NOT NULL REFERENCES ciphers (uuid) ON DELETE CASCADE,
  archived_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_uuid, cipher_uuid)
);
