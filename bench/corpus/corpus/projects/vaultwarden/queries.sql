-- vaultwarden (dani-garcia/vaultwarden @ 0f44744, AGPL-3.0). All SQL is built with the Diesel DSL in src/db/models/*.rs;
-- each query is the SQLite text Diesel 2 emits for one representative call (backtick identifiers, parenthesised
-- operators, ? binds with booleans as 1/0, .first() binding LIMIT), reconstructed from the builder code. Quoted
-- individually with attribution. The sync subject is user 7 (owner in org 1, collection grants in org 2, group in org 3).

-- @id vaultwarden.ciphers.find_by_user_visible
-- @src src/db/models/cipher.rs:821-916
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath,dynamic
-- @note The /api/sync core (org groups off, the default): ciphers LEFT JOIN collections/memberships/collection grants, OR-chain of ownership and access predicates, SELECT DISTINCT all columns. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 2
-- @param ?3 'a0000000-0000-4000-8000-000000000007'
-- @param ?4 1
-- @param ?5 'a0000000-0000-4000-8000-000000000007'
SELECT DISTINCT `ciphers`.`uuid`, `ciphers`.`created_at`, `ciphers`.`updated_at`, `ciphers`.`user_uuid`, `ciphers`.`organization_uuid`, `ciphers`.`key`, `ciphers`.`atype`, `ciphers`.`name`, `ciphers`.`notes`, `ciphers`.`fields`, `ciphers`.`data`, `ciphers`.`password_history`, `ciphers`.`deleted_at`, `ciphers`.`reprompt` FROM `ciphers` LEFT OUTER JOIN `ciphers_collections` ON (`ciphers`.`uuid` = `ciphers_collections`.`cipher_uuid`) LEFT OUTER JOIN `users_organizations` ON (((`ciphers`.`organization_uuid` = `users_organizations`.`org_uuid`) AND (`users_organizations`.`user_uuid` = ?1)) AND (`users_organizations`.`status` = ?2)) LEFT OUTER JOIN `users_collections` ON ((`ciphers_collections`.`collection_uuid` = `users_collections`.`collection_uuid`) AND (`users_organizations`.`user_uuid` = `users_collections`.`user_uuid`)) WHERE (((`ciphers`.`user_uuid` = ?3) OR (`users_organizations`.`access_all` = ?4)) OR (`users_collections`.`user_uuid` = ?5));

-- @id vaultwarden.ciphers.find_by_user_visible_groups
-- @src src/db/models/cipher.rs:821-876
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath,dynamic
-- @note The /api/sync core with ORG_GROUPS_ENABLED: six LEFT OUTER JOINs (collections, memberships, user grants, group membership, groups, group grants) and a five-way OR, SELECT DISTINCT. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 2
-- @param ?3 'a0000000-0000-4000-8000-000000000007'
-- @param ?4 1
-- @param ?5 'a0000000-0000-4000-8000-000000000007'
-- @param ?6 1
SELECT DISTINCT `ciphers`.`uuid`, `ciphers`.`created_at`, `ciphers`.`updated_at`, `ciphers`.`user_uuid`, `ciphers`.`organization_uuid`, `ciphers`.`key`, `ciphers`.`atype`, `ciphers`.`name`, `ciphers`.`notes`, `ciphers`.`fields`, `ciphers`.`data`, `ciphers`.`password_history`, `ciphers`.`deleted_at`, `ciphers`.`reprompt` FROM `ciphers` LEFT OUTER JOIN `ciphers_collections` ON (`ciphers`.`uuid` = `ciphers_collections`.`cipher_uuid`) LEFT OUTER JOIN `users_organizations` ON (((`ciphers`.`organization_uuid` = `users_organizations`.`org_uuid`) AND (`users_organizations`.`user_uuid` = ?1)) AND (`users_organizations`.`status` = ?2)) LEFT OUTER JOIN `users_collections` ON ((`ciphers_collections`.`collection_uuid` = `users_collections`.`collection_uuid`) AND (`users_organizations`.`user_uuid` = `users_collections`.`user_uuid`)) LEFT OUTER JOIN `groups_users` ON (`groups_users`.`users_organizations_uuid` = `users_organizations`.`uuid`) LEFT OUTER JOIN `groups` ON ((`groups`.`uuid` = `groups_users`.`groups_uuid`) AND (`groups`.`organizations_uuid` = `users_organizations`.`org_uuid`)) LEFT OUTER JOIN `collections_groups` ON ((`collections_groups`.`collections_uuid` = `ciphers_collections`.`collection_uuid`) AND (`collections_groups`.`groups_uuid` = `groups`.`uuid`)) WHERE (((((`ciphers`.`user_uuid` = ?3) OR (`users_organizations`.`access_all` = ?4)) OR (`users_collections`.`user_uuid` = ?5)) OR (`groups`.`access_all` = ?6)) OR (`collections_groups`.`collections_uuid` IS NOT NULL));

-- @id vaultwarden.ciphers.find_by_user_and_cipher
-- @src src/db/models/cipher.rs:929-932
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath,dynamic
-- @note Per-cipher access check (every cipher GET/PUT): the sync join narrowed with AND uuid IN (?), groups off. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 2
-- @param ?3 'a0000000-0000-4000-8000-000000000007'
-- @param ?4 1
-- @param ?5 'a0000000-0000-4000-8000-000000000007'
-- @param ?6 'c0000000-0000-4000-8000-000000000022'
SELECT DISTINCT `ciphers`.`uuid`, `ciphers`.`created_at`, `ciphers`.`updated_at`, `ciphers`.`user_uuid`, `ciphers`.`organization_uuid`, `ciphers`.`key`, `ciphers`.`atype`, `ciphers`.`name`, `ciphers`.`notes`, `ciphers`.`fields`, `ciphers`.`data`, `ciphers`.`password_history`, `ciphers`.`deleted_at`, `ciphers`.`reprompt` FROM `ciphers` LEFT OUTER JOIN `ciphers_collections` ON (`ciphers`.`uuid` = `ciphers_collections`.`cipher_uuid`) LEFT OUTER JOIN `users_organizations` ON (((`ciphers`.`organization_uuid` = `users_organizations`.`org_uuid`) AND (`users_organizations`.`user_uuid` = ?1)) AND (`users_organizations`.`status` = ?2)) LEFT OUTER JOIN `users_collections` ON ((`ciphers_collections`.`collection_uuid` = `users_collections`.`collection_uuid`) AND (`users_organizations`.`user_uuid` = `users_collections`.`user_uuid`)) WHERE ((((`ciphers`.`user_uuid` = ?3) OR (`users_organizations`.`access_all` = ?4)) OR (`users_collections`.`user_uuid` = ?5)) AND (`ciphers`.`uuid` IN (?6)));

-- @id vaultwarden.ciphers.collections_with_cipher_by_user
-- @src src/db/models/cipher.rs:1146-1185
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath
-- @note CipherSyncData: every (cipher, collection) pair the user can see, via inner joins to collections/memberships and left joins to user and group grants, five-way OR then AND confirmed, DISTINCT. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 'a0000000-0000-4000-8000-000000000007'
-- @param ?3 'a0000000-0000-4000-8000-000000000007'
-- @param ?4 1
-- @param ?5 1
-- @param ?6 1
-- @param ?7 2
SELECT DISTINCT `ciphers_collections`.`cipher_uuid`, `ciphers_collections`.`collection_uuid` FROM `ciphers_collections` INNER JOIN `collections` ON (`collections`.`uuid` = `ciphers_collections`.`collection_uuid`) INNER JOIN `users_organizations` ON ((`users_organizations`.`org_uuid` = `collections`.`org_uuid`) AND (`users_organizations`.`user_uuid` = ?1)) LEFT OUTER JOIN `users_collections` ON ((`users_collections`.`collection_uuid` = `ciphers_collections`.`collection_uuid`) AND (`users_collections`.`user_uuid` = ?2)) LEFT OUTER JOIN `groups_users` ON (`groups_users`.`users_organizations_uuid` = `users_organizations`.`uuid`) LEFT OUTER JOIN `groups` ON ((`groups`.`uuid` = `groups_users`.`groups_uuid`) AND (`groups`.`organizations_uuid` = `users_organizations`.`org_uuid`)) LEFT OUTER JOIN `collections_groups` ON ((`collections_groups`.`collections_uuid` = `ciphers_collections`.`collection_uuid`) AND (`collections_groups`.`groups_uuid` = `groups`.`uuid`)) WHERE ((((((`users_collections`.`user_uuid` = ?3) OR (`users_organizations`.`access_all` = ?4)) OR (`users_organizations`.`atype` <= ?5)) OR (`groups`.`access_all` = ?6)) OR (`collections_groups`.`collections_uuid` IS NOT NULL)) AND (`users_organizations`.`status` = ?7));

-- @id vaultwarden.ciphers.user_collection_access_flags
-- @src src/db/models/cipher.rs:668-697
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags dynamic
-- @note Per-cipher permission flags outside sync: three inner joins with a compound ON tying the grant to a confirmed membership. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 2
-- @param ?3 'c0000000-0000-4000-8000-000000000302'
SELECT `users_collections`.`read_only`, `users_collections`.`hide_passwords`, `users_collections`.`manage` FROM `ciphers` INNER JOIN `ciphers_collections` ON (`ciphers`.`uuid` = `ciphers_collections`.`cipher_uuid`) INNER JOIN `users_organizations` ON (((`ciphers`.`organization_uuid` = `users_organizations`.`org_uuid`) AND (`users_organizations`.`user_uuid` = ?1)) AND (`users_organizations`.`status` = ?2)) INNER JOIN `users_collections` ON ((`ciphers_collections`.`collection_uuid` = `users_collections`.`collection_uuid`) AND (`users_organizations`.`user_uuid` = `users_collections`.`user_uuid`)) WHERE (`ciphers`.`uuid` = ?3);

-- @id vaultwarden.ciphers.group_collection_access_flags
-- @src src/db/models/cipher.rs:699-730
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags dynamic
-- @note Group-derived permission flags: a six-table inner-join chain (cipher -> collection link -> group grant -> group member -> membership -> group) with three filters. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'c0000000-0000-4000-8000-000000000582'
-- @param ?2 'a0000000-0000-4000-8000-000000000007'
-- @param ?3 2
SELECT `collections_groups`.`read_only`, `collections_groups`.`hide_passwords`, `collections_groups`.`manage` FROM `ciphers` INNER JOIN `ciphers_collections` ON (`ciphers`.`uuid` = `ciphers_collections`.`cipher_uuid`) INNER JOIN `collections_groups` ON (`collections_groups`.`collections_uuid` = `ciphers_collections`.`collection_uuid`) INNER JOIN `groups_users` ON (`groups_users`.`groups_uuid` = `collections_groups`.`groups_uuid`) INNER JOIN `users_organizations` ON (`users_organizations`.`uuid` = `groups_users`.`users_organizations_uuid`) INNER JOIN `groups` ON ((`groups`.`uuid` = `collections_groups`.`groups_uuid`) AND (`groups`.`organizations_uuid` = `users_organizations`.`org_uuid`)) WHERE ((((`ciphers`.`uuid` = ?1) AND (`users_organizations`.`user_uuid` = ?2)) AND (`users_organizations`.`status` = ?3)) AND (`ciphers`.`organization_uuid` = `users_organizations`.`org_uuid`));

-- @id vaultwarden.collections.find_by_user_uuid
-- @src src/db/models/collection.rs:223-299
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath,dynamic
-- @note Sync collections (groups off): collections LEFT JOIN user grant and membership with bound user in both ON clauses, confirmed AND (grant OR access_all), DISTINCT. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 'a0000000-0000-4000-8000-000000000007'
-- @param ?3 2
-- @param ?4 'a0000000-0000-4000-8000-000000000007'
-- @param ?5 1
SELECT DISTINCT `collections`.`uuid`, `collections`.`org_uuid`, `collections`.`name`, `collections`.`external_id` FROM `collections` LEFT OUTER JOIN `users_collections` ON ((`users_collections`.`collection_uuid` = `collections`.`uuid`) AND (`users_collections`.`user_uuid` = ?1)) LEFT OUTER JOIN `users_organizations` ON ((`collections`.`org_uuid` = `users_organizations`.`org_uuid`) AND (`users_organizations`.`user_uuid` = ?2)) WHERE ((`users_organizations`.`status` = ?3) AND ((`users_collections`.`user_uuid` = ?4) OR (`users_organizations`.`access_all` = ?5)));

-- @id vaultwarden.collections.find_by_user_uuid_groups
-- @src src/db/models/collection.rs:223-273
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath,dynamic
-- @note Sync collections with groups: five LEFT JOINs and a nested OR containing an AND (group member AND group grant present), DISTINCT. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 'a0000000-0000-4000-8000-000000000007'
-- @param ?3 2
-- @param ?4 'a0000000-0000-4000-8000-000000000007'
-- @param ?5 1
-- @param ?6 1
SELECT DISTINCT `collections`.`uuid`, `collections`.`org_uuid`, `collections`.`name`, `collections`.`external_id` FROM `collections` LEFT OUTER JOIN `users_collections` ON ((`users_collections`.`collection_uuid` = `collections`.`uuid`) AND (`users_collections`.`user_uuid` = ?1)) LEFT OUTER JOIN `users_organizations` ON ((`collections`.`org_uuid` = `users_organizations`.`org_uuid`) AND (`users_organizations`.`user_uuid` = ?2)) LEFT OUTER JOIN `groups_users` ON (`groups_users`.`users_organizations_uuid` = `users_organizations`.`uuid`) LEFT OUTER JOIN `groups` ON ((`groups`.`uuid` = `groups_users`.`groups_uuid`) AND (`groups`.`organizations_uuid` = `users_organizations`.`org_uuid`)) LEFT OUTER JOIN `collections_groups` ON ((`collections_groups`.`groups_uuid` = `groups_users`.`groups_uuid`) AND (`collections_groups`.`collections_uuid` = `collections`.`uuid`)) WHERE ((`users_organizations`.`status` = ?3) AND ((((`users_collections`.`user_uuid` = ?4) OR (`users_organizations`.`access_all` = ?5)) OR (`groups`.`access_all` = ?6)) OR ((`groups_users`.`users_organizations_uuid` = `users_organizations`.`uuid`) AND (`collections_groups`.`collections_uuid` IS NOT NULL))));

-- @id vaultwarden.collections.is_writable_by_user_groups
-- @src src/db/models/collection.rs:426-472
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags dynamic
-- @note Write check on collection edits: COUNT(*) over an inner+left join chain with a five-way OR mixing admin rank, access_all, writable grants and writable group grants, LIMIT bound. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 2
-- @param ?3 'a0000000-0000-4000-8000-000000000007'
-- @param ?4 'd0000000-0000-4000-8000-000000000021'
-- @param ?5 1
-- @param ?6 1
-- @param ?7 'd0000000-0000-4000-8000-000000000021'
-- @param ?8 0
-- @param ?9 1
-- @param ?10 0
-- @param ?11 1
SELECT COUNT(*) FROM `collections` INNER JOIN `users_organizations` ON (((`collections`.`org_uuid` = `users_organizations`.`org_uuid`) AND (`users_organizations`.`user_uuid` = ?1)) AND (`users_organizations`.`status` = ?2)) LEFT OUTER JOIN `users_collections` ON ((`users_collections`.`collection_uuid` = `collections`.`uuid`) AND (`users_collections`.`user_uuid` = ?3)) LEFT OUTER JOIN `groups_users` ON (`groups_users`.`users_organizations_uuid` = `users_organizations`.`uuid`) LEFT OUTER JOIN `groups` ON ((`groups`.`uuid` = `groups_users`.`groups_uuid`) AND (`groups`.`organizations_uuid` = `users_organizations`.`org_uuid`)) LEFT OUTER JOIN `collections_groups` ON ((`collections_groups`.`groups_uuid` = `groups_users`.`groups_uuid`) AND (`collections_groups`.`collections_uuid` = `collections`.`uuid`)) WHERE ((`collections`.`uuid` = ?4) AND (((((`users_organizations`.`atype` <= ?5) OR (`users_organizations`.`access_all` = ?6)) OR ((`users_collections`.`collection_uuid` = ?7) AND (`users_collections`.`read_only` = ?8))) OR (`groups`.`access_all` = ?9)) OR ((`collections_groups`.`collections_uuid` IS NOT NULL) AND (`collections_groups`.`read_only` = ?10)))) LIMIT ?11;

-- @id vaultwarden.users_collections.find_by_user
-- @src src/db/models/collection.rs:830-846
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath
-- @note CipherSyncData: the user's direct collection grants, joined to collections and to a confirmed membership in the same org. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 2
SELECT `users_collections`.`user_uuid`, `users_collections`.`collection_uuid`, `users_collections`.`read_only`, `users_collections`.`hide_passwords`, `users_collections`.`manage` FROM `users_collections` INNER JOIN `collections` ON (`collections`.`uuid` = `users_collections`.`collection_uuid`) INNER JOIN `users_organizations` ON ((`users_organizations`.`org_uuid` = `collections`.`org_uuid`) AND (`users_organizations`.`user_uuid` = `users_collections`.`user_uuid`)) WHERE ((`users_collections`.`user_uuid` = ?1) AND (`users_organizations`.`status` = ?2));

-- @id vaultwarden.collections_groups.find_by_user
-- @src src/db/models/group.rs:372-396
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath
-- @note CipherSyncData (groups on): group grants reachable by the user, four inner joins with org-consistency conditions. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 2
SELECT `collections_groups`.`collections_uuid`, `collections_groups`.`groups_uuid`, `collections_groups`.`read_only`, `collections_groups`.`hide_passwords`, `collections_groups`.`manage` FROM `collections_groups` INNER JOIN `groups_users` ON (`groups_users`.`groups_uuid` = `collections_groups`.`groups_uuid`) INNER JOIN `users_organizations` ON (`users_organizations`.`uuid` = `groups_users`.`users_organizations_uuid`) INNER JOIN `groups` ON ((`groups`.`uuid` = `collections_groups`.`groups_uuid`) AND (`groups`.`organizations_uuid` = `users_organizations`.`org_uuid`)) INNER JOIN `collections` ON ((`collections`.`uuid` = `collections_groups`.`collections_uuid`) AND (`collections`.`org_uuid` = `groups`.`organizations_uuid`)) WHERE ((`users_organizations`.`user_uuid` = ?1) AND (`users_organizations`.`status` = ?2));

-- @id vaultwarden.groups.orgs_with_full_access
-- @src src/db/models/group.rs:239-258
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath
-- @note CipherSyncData: orgs where the user sits in an access_all group, DISTINCT over a three-table join. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000104'
-- @param ?2 2
-- @param ?3 1
SELECT DISTINCT `groups`.`organizations_uuid` FROM `groups_users` INNER JOIN `users_organizations` ON (`users_organizations`.`uuid` = `groups_users`.`users_organizations_uuid`) INNER JOIN `groups` ON ((`groups`.`uuid` = `groups_users`.`groups_uuid`) AND (`groups`.`organizations_uuid` = `users_organizations`.`org_uuid`)) WHERE (((`users_organizations`.`user_uuid` = ?1) AND (`users_organizations`.`status` = ?2)) AND (`groups`.`access_all` = ?3));

-- @id vaultwarden.folders_ciphers.find_by_user
-- @src src/db/models/folder.rs:219-229
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath
-- @note CipherSyncData: (cipher, folder) pairs through the joinable! implicit join to folders, filtered by owner. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000002'
SELECT `folders_ciphers`.`cipher_uuid`, `folders_ciphers`.`folder_uuid` FROM `folders_ciphers` INNER JOIN `folders` ON (`folders_ciphers`.`folder_uuid` = `folders`.`uuid`) WHERE (`folders`.`user_uuid` = ?1);

-- @id vaultwarden.favorites.cipher_uuids_by_user
-- @src src/db/models/favorite.rs:92-101
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath
-- @note CipherSyncData favourites: PK-prefix scan on favorites. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000002'
SELECT `favorites`.`cipher_uuid` FROM `favorites` WHERE (`favorites`.`user_uuid` = ?1);

-- @id vaultwarden.archives.find_by_user
-- @src src/db/models/archive.rs:88-97
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath
-- @note CipherSyncData archives: PK-prefix scan. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000001'
SELECT `archives`.`cipher_uuid`, `archives`.`archived_at` FROM `archives` WHERE (`archives`.`user_uuid` = ?1);

-- @id vaultwarden.memberships.find_confirmed_by_user
-- @src src/db/models/organization.rs:807-816
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath
-- @note CipherSyncData memberships: the UNIQUE(user_uuid, org_uuid) autoindex prefix plus a status filter. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 2
SELECT `users_organizations`.`uuid`, `users_organizations`.`user_uuid`, `users_organizations`.`org_uuid`, `users_organizations`.`invited_by_email`, `users_organizations`.`access_all`, `users_organizations`.`akey`, `users_organizations`.`status`, `users_organizations`.`atype`, `users_organizations`.`reset_password_key`, `users_organizations`.`external_id` FROM `users_organizations` WHERE ((`users_organizations`.`user_uuid` = ?1) AND (`users_organizations`.`status` = ?2));

-- @id vaultwarden.attachments.find_all_by_user_and_orgs
-- @src src/db/models/attachment.rs:216-231
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath,dynamic
-- @note CipherSyncData attachments: attachments LEFT JOIN ciphers WHERE owner OR org IN (user's confirmed orgs); the OR defeats any index, so it scans. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 'b0000000-0000-4000-8000-000000000001'
-- @param ?3 'b0000000-0000-4000-8000-000000000002'
-- @param ?4 'b0000000-0000-4000-8000-000000000003'
SELECT `attachments`.`id`, `attachments`.`cipher_uuid`, `attachments`.`file_name`, `attachments`.`file_size`, `attachments`.`akey` FROM `attachments` LEFT OUTER JOIN `ciphers` ON (`ciphers`.`uuid` = `attachments`.`cipher_uuid`) WHERE ((`ciphers`.`user_uuid` = ?1) OR (`ciphers`.`organization_uuid` IN (?2, ?3, ?4)));

-- @id vaultwarden.org_policies.find_confirmed_by_user
-- @src src/db/models/org_policy.rs:180-194
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath
-- @note Sync policies: org_policies joined to the user's membership, confirmed only. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 2
SELECT `org_policies`.`uuid`, `org_policies`.`org_uuid`, `org_policies`.`atype`, `org_policies`.`enabled`, `org_policies`.`data`, `org_policies`.`revision_date` FROM `org_policies` INNER JOIN `users_organizations` ON ((`users_organizations`.`org_uuid` = `org_policies`.`org_uuid`) AND (`users_organizations`.`user_uuid` = ?1)) WHERE (`users_organizations`.`status` = ?2);

-- @id vaultwarden.org_policies.accepted_confirmed_active_policy
-- @src src/db/models/org_policy.rs:240-261
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags dynamic
-- @note Policy enforcement (login, org join): filter/or_filter/filter chaining gives ((Accepted OR Confirmed) AND type) AND enabled. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 1
-- @param ?3 2
-- @param ?4 0
-- @param ?5 1
SELECT `org_policies`.`uuid`, `org_policies`.`org_uuid`, `org_policies`.`atype`, `org_policies`.`enabled`, `org_policies`.`data`, `org_policies`.`revision_date` FROM `org_policies` INNER JOIN `users_organizations` ON ((`users_organizations`.`org_uuid` = `org_policies`.`org_uuid`) AND (`users_organizations`.`user_uuid` = ?1)) WHERE ((((`users_organizations`.`status` = ?2) OR (`users_organizations`.`status` = ?3)) AND (`org_policies`.`atype` = ?4)) AND (`org_policies`.`enabled` = ?5));

-- @id vaultwarden.memberships.find_by_cipher_and_org
-- @src src/db/models/organization.rs:1024-1045
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags dynamic
-- @note On every org-cipher write: members to notify, via LEFT JOINs to grants and the cipher's collection links, access_all OR has-cipher, DISTINCT. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'c0000000-0000-4000-8000-000000000302'
-- @param ?2 'b0000000-0000-4000-8000-000000000002'
-- @param ?3 2
-- @param ?4 1
-- @param ?5 'c0000000-0000-4000-8000-000000000302'
SELECT DISTINCT `users_organizations`.`uuid`, `users_organizations`.`user_uuid`, `users_organizations`.`org_uuid`, `users_organizations`.`invited_by_email`, `users_organizations`.`access_all`, `users_organizations`.`akey`, `users_organizations`.`status`, `users_organizations`.`atype`, `users_organizations`.`reset_password_key`, `users_organizations`.`external_id` FROM `users_organizations` LEFT OUTER JOIN `users_collections` ON (`users_collections`.`user_uuid` = `users_organizations`.`user_uuid`) LEFT OUTER JOIN `ciphers_collections` ON ((`ciphers_collections`.`collection_uuid` = `users_collections`.`collection_uuid`) AND (`ciphers_collections`.`cipher_uuid` = ?1)) WHERE (((`users_organizations`.`org_uuid` = ?2) AND (`users_organizations`.`status` = ?3)) AND ((`users_organizations`.`access_all` = ?4) OR (`ciphers_collections`.`cipher_uuid` = ?5)));

-- @id vaultwarden.folders.find_by_user
-- @src src/db/models/folder.rs:131-136
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath
-- @note Sync folders: no index on folders.user_uuid in the SQLite migrations, so a table scan. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000002'
SELECT `folders`.`uuid`, `folders`.`created_at`, `folders`.`updated_at`, `folders`.`user_uuid`, `folders`.`name` FROM `folders` WHERE (`folders`.`user_uuid` = ?1);

-- @id vaultwarden.sends.find_by_user
-- @src src/db/models/send.rs:327-331
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hotpath
-- @note Sync sends: table scan on user_uuid. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000002000'
SELECT `sends`.`uuid`, `sends`.`user_uuid`, `sends`.`organization_uuid`, `sends`.`name`, `sends`.`notes`, `sends`.`atype`, `sends`.`data`, `sends`.`akey`, `sends`.`password_hash`, `sends`.`password_salt`, `sends`.`password_iter`, `sends`.`max_access_count`, `sends`.`access_count`, `sends`.`creation_date`, `sends`.`revision_date`, `sends`.`expiration_date`, `sends`.`deletion_date`, `sends`.`disabled`, `sends`.`hide_email` FROM `sends` WHERE (`sends`.`user_uuid` = ?1);

-- @id vaultwarden.users.find_by_uuid
-- @src src/db/models/user.rs:435-437
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hot-small
-- @note Every authenticated request: user by primary key, LIMIT bound by Diesel .first(). Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'a0000000-0000-4000-8000-000000000007'
-- @param ?2 1
SELECT `users`.`uuid`, `users`.`enabled`, `users`.`created_at`, `users`.`updated_at`, `users`.`verified_at`, `users`.`last_verifying_at`, `users`.`login_verify_count`, `users`.`email`, `users`.`email_new`, `users`.`email_new_token`, `users`.`name`, `users`.`password_hash`, `users`.`salt`, `users`.`password_iterations`, `users`.`password_hint`, `users`.`akey`, `users`.`private_key`, `users`.`public_key`, `users`.`totp_secret`, `users`.`totp_recover`, `users`.`security_stamp`, `users`.`stamp_exception`, `users`.`equivalent_domains`, `users`.`excluded_globals`, `users`.`client_kdf_type`, `users`.`client_kdf_iter`, `users`.`client_kdf_memory`, `users`.`client_kdf_parallelism`, `users`.`api_key`, `users`.`avatar_color`, `users`.`external_id`, `users`.`key_id` FROM `users` WHERE (`users`.`uuid` = ?1) LIMIT ?2;

-- @id vaultwarden.devices.find_by_refresh_token
-- @src src/db/models/device.rs:225-228
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hot-small
-- @note Token refresh: device by refresh_token (unindexed, scans devices). Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'rt0000002af519f70a'
-- @param ?2 1
SELECT `devices`.`uuid`, `devices`.`created_at`, `devices`.`updated_at`, `devices`.`user_uuid`, `devices`.`name`, `devices`.`atype`, `devices`.`push_uuid`, `devices`.`push_token`, `devices`.`refresh_token`, `devices`.`twofactor_remember` FROM `devices` WHERE (`devices`.`refresh_token` = ?1) LIMIT ?2;

-- @id vaultwarden.ciphers.find_by_uuid
-- @src src/db/models/cipher.rs:790-792
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hot-small
-- @note Cipher by primary key before every edit. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'c0000000-0000-4000-8000-000000000016'
-- @param ?2 1
SELECT `ciphers`.`uuid`, `ciphers`.`created_at`, `ciphers`.`updated_at`, `ciphers`.`user_uuid`, `ciphers`.`organization_uuid`, `ciphers`.`key`, `ciphers`.`atype`, `ciphers`.`name`, `ciphers`.`notes`, `ciphers`.`fields`, `ciphers`.`data`, `ciphers`.`password_history`, `ciphers`.`deleted_at`, `ciphers`.`reprompt` FROM `ciphers` WHERE (`ciphers`.`uuid` = ?1) LIMIT ?2;

-- @id vaultwarden.users.update_revision
-- @src src/db/models/user.rs:415-428
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hot-small
-- @note After every vault write: bump the owner's revision date. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 '2026-10-28 10:00:00.000000'
-- @param ?2 'a0000000-0000-4000-8000-000000000007'
UPDATE `users` SET `updated_at` = ?1 WHERE (`users`.`uuid` = ?2);

-- @id vaultwarden.ciphers.save_upsert
-- @src src/db/models/cipher.rs:438-462
-- @style Diesel DSL (? positional); SQL reconstructed from the query builder
-- @tags hot-small
-- @note Cipher create/edit: INSERT ... ON CONFLICT (uuid) DO UPDATE SET every non-key column (treat_none_as_null). Diesel omits None columns from the INSERT list on SQLite. Reconstructed from Diesel DSL (SQLite backend: backtick identifiers, parenthesised operators, bound booleans/LIMIT).
-- @param ?1 'c0000000-0000-4000-8000-000000000016'
-- @param ?2 '2023-06-01 04:26:40.000000'
-- @param ?3 '2026-10-28 10:00:00.000000'
-- @param ?4 'a0000000-0000-4000-8000-000000000007'
-- @param ?5 '2.CipherKey|16'
-- @param ?6 1
-- @param ?7 '2.EncName|16'
-- @param ?8 NULL
-- @param ?9 NULL
-- @param ?10 '{"name":"2.EncName|16","username":"2.u","password":"2.p","uris":[]}'
-- @param ?11 NULL
-- @param ?12 0
-- @param ?13 '2023-06-01 04:26:40.000000'
-- @param ?14 '2026-10-28 10:00:00.000000'
-- @param ?15 'a0000000-0000-4000-8000-000000000007'
-- @param ?16 NULL
-- @param ?17 '2.CipherKey|16'
-- @param ?18 1
-- @param ?19 '2.EncName|16'
-- @param ?20 NULL
-- @param ?21 NULL
-- @param ?22 '{"name":"2.EncName|16","username":"2.u","password":"2.p","uris":[]}'
-- @param ?23 NULL
-- @param ?24 NULL
-- @param ?25 0
INSERT INTO `ciphers` (`uuid`, `created_at`, `updated_at`, `user_uuid`, `key`, `atype`, `name`, `notes`, `fields`, `data`, `password_history`, `reprompt`) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12) ON CONFLICT (`uuid`) DO UPDATE SET `created_at` = ?13, `updated_at` = ?14, `user_uuid` = ?15, `organization_uuid` = ?16, `key` = ?17, `atype` = ?18, `name` = ?19, `notes` = ?20, `fields` = ?21, `data` = ?22, `password_history` = ?23, `deleted_at` = ?24, `reprompt` = ?25;
