-- Synthetic data for vaultwarden. Deterministic (no random()): values come from multiplicative hashes of the row number,
-- each column from different bits. UUIDs are printf()-built with a per-table prefix. Scale 1: 2k users, 30 orgs,
-- 300 collections, 50k personal + 30k org ciphers, ~45k cipher->collection links, ~2.4k memberships, 60 groups,
-- 6k folders, 30k folder links, favorites/archives/attachments/sends/devices. User 7 (a0000000-...-000000000007)
-- is the sync subject: owner of org 1, collection member in org 2, group member in org 3, invited to org 4.
BEGIN;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000*(SELECT scale FROM _cfg))
INSERT INTO users(uuid, created_at, updated_at, email, name, password_hash, salt, password_iterations, akey, private_key,
  public_key, security_stamp, equivalent_domains, excluded_globals, client_kdf_type, client_kdf_iter, verified_at, enabled,
  avatar_color)
SELECT printf('a0000000-0000-4000-8000-%012d', i),
       strftime('%Y-%m-%d %H:%M:%f', unixepoch('2023-01-01') + i * 40000, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%f', unixepoch('2026-10-01') + (i * 2654435761) % 2400000, 'unixepoch'),
       'user' || i || '@example.org', 'User ' || i, x'00112233', x'44556677', 600000,
       '2.AkeyAkeyAkey|' || i, '2.PrivateKey|' || i, 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA' || i,
       printf('%08x-stamp', (i * 2246822519) % 4294967296), '[]', '[]', 0, 600000,
       strftime('%Y-%m-%d %H:%M:%f', unixepoch('2023-01-02') + i * 40000, 'unixepoch'), 1,
       CASE WHEN i % 3 = 0 THEN '#2196f3' ELSE NULL END
FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 30)
INSERT INTO organizations(uuid, name, billing_email, private_key, public_key)
SELECT printf('b0000000-0000-4000-8000-%012d', i), 'Org ' || i, 'billing' || i || '@example.org', '2.orgpriv|' || i, 'orgpub' || i FROM n;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 300)
INSERT INTO collections(uuid, org_uuid, name, external_id)
SELECT printf('d0000000-0000-4000-8000-%012d', i), printf('b0000000-0000-4000-8000-%012d', (i - 1) / 10 + 1),
       '2.EncCollectionName|' || i, CASE WHEN i % 4 = 0 THEN 'ext-' || i ELSE NULL END FROM n;

-- memberships: users 1..1200 join 1-3 orgs; user 7 handled explicitly below
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 1200),
k(k) AS (SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2)
INSERT OR IGNORE INTO users_organizations(uuid, user_uuid, org_uuid, access_all, akey, status, atype)
SELECT printf('90000000-0000-4000-8000-%06d%06d', n.i, k.k), printf('a0000000-0000-4000-8000-%012d', n.i),
       printf('b0000000-0000-4000-8000-%012d', 1 + (n.i * 7 + k.k * 11) % 30),
       CASE WHEN (n.i + k.k) % 9 = 0 THEN 1 ELSE 0 END, '4.OrgKey|' || n.i,
       CASE WHEN (n.i * 3 + k.k) % 17 = 0 THEN 0 WHEN (n.i + k.k) % 23 = 0 THEN 1 WHEN (n.i + k.k) % 29 = 0 THEN -1 ELSE 2 END,
       CASE WHEN (n.i + k.k) % 13 = 0 THEN 0 WHEN (n.i + k.k) % 7 = 0 THEN 1 WHEN (n.i + k.k) % 11 = 0 THEN 3 ELSE 2 END
FROM n, k WHERE n.i <> 7 AND k.k < 1 + n.i % 3;

INSERT INTO users_organizations(uuid, user_uuid, org_uuid, access_all, akey, status, atype) VALUES
 ('90000000-0000-4000-8000-000007000001', 'a0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-000000000001', 1, '4.OrgKey|7', 2, 0),
 ('90000000-0000-4000-8000-000007000002', 'a0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-000000000002', 0, '4.OrgKey|7', 2, 2),
 ('90000000-0000-4000-8000-000007000003', 'a0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-000000000003', 0, '4.OrgKey|7', 2, 2),
 ('90000000-0000-4000-8000-000007000004', 'a0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-000000000004', 0, '4.OrgKey|7', 0, 2);

-- direct collection grants: non-access_all members get 2 collections of each org they are in
INSERT OR IGNORE INTO users_collections(user_uuid, collection_uuid, read_only, hide_passwords, manage)
SELECT m.user_uuid, printf('d0000000-0000-4000-8000-%012d', (CAST(substr(m.org_uuid, 25) AS INTEGER) - 1) * 10 + 1 + (k.k * 3 + CAST(substr(m.user_uuid, 25) AS INTEGER)) % 10),
       CASE WHEN k.k = 1 THEN 1 ELSE 0 END, CASE WHEN CAST(substr(m.user_uuid, 25) AS INTEGER) % 5 = 0 THEN 1 ELSE 0 END, CASE WHEN m.atype = 3 THEN 1 ELSE 0 END
FROM users_organizations m, (SELECT 0 AS k UNION ALL SELECT 1) k
WHERE m.access_all = 0 AND m.org_uuid <> 'b0000000-0000-4000-8000-000000000003';

-- groups: two per org, the second has access_all
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 60)
INSERT INTO groups(uuid, organizations_uuid, name, access_all, external_id, creation_date, revision_date)
SELECT printf('e0000000-0000-4000-8000-%012d', i), printf('b0000000-0000-4000-8000-%012d', (i - 1) / 2 + 1),
       CASE WHEN i % 2 = 1 THEN 'Engineering' ELSE 'Admins' END, CASE WHEN i % 2 = 0 THEN 1 ELSE 0 END, NULL,
       '2024-01-01 00:00:00.000000', '2024-06-01 00:00:00.000000'
FROM n;

INSERT INTO groups_users(groups_uuid, users_organizations_uuid)
SELECT printf('e0000000-0000-4000-8000-%012d', (CAST(substr(m.org_uuid, 25) AS INTEGER) - 1) * 2 + 1 + (CAST(substr(m.user_uuid, 25) AS INTEGER) % 8 = 0)),
       m.uuid
FROM users_organizations m WHERE CAST(substr(m.user_uuid, 25) AS INTEGER) % 2 = 0 OR m.org_uuid = 'b0000000-0000-4000-8000-000000000003';

-- each non-access_all group can reach 5 collections of its org
WITH RECURSIVE k(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM k WHERE k < 4)
INSERT INTO collections_groups(collections_uuid, groups_uuid, read_only, hide_passwords, manage)
SELECT printf('d0000000-0000-4000-8000-%012d', (g.i - 1) / 2 * 10 + 1 + k.k * 2), printf('e0000000-0000-4000-8000-%012d', g.i),
       CASE WHEN k.k = 3 THEN 1 ELSE 0 END, 0, CASE WHEN k.k = 0 THEN 1 ELSE 0 END
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+2 FROM n WHERE i < 59) SELECT i FROM n) g, k;

-- ciphers: 50k personal (skewed: low user ids own more), 30k org-owned
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 80000*(SELECT scale FROM _cfg)),
m AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO ciphers(uuid, created_at, updated_at, user_uuid, organization_uuid, atype, name, notes, fields, data,
  password_history, deleted_at, reprompt, "key")
SELECT printf('c0000000-0000-4000-8000-%012d', i),
       strftime('%Y-%m-%d %H:%M:%f', unixepoch('2023-06-01') + i * 1000, 'unixepoch'),
       strftime('%Y-%m-%d %H:%M:%f', unixepoch('2023-06-01') + i * 1000 + h % 30000000, 'unixepoch'),
       CASE WHEN i % 8 < 5 THEN printf('a0000000-0000-4000-8000-%012d', 1 + ((h / 16) % 2000) * ((h / 65536) % 2000) / 2000 * (SELECT scale FROM _cfg)) ELSE NULL END,
       CASE WHEN i % 8 < 5 THEN NULL ELSE printf('b0000000-0000-4000-8000-%012d', 1 + (h / 128) % 30) END,
       CASE (h / 8) % 20 WHEN 0 THEN 2 WHEN 1 THEN 3 WHEN 2 THEN 4 WHEN 3 THEN 5 ELSE 1 END,
       '2.EncName' || printf('%08x', h) || '|' || i,
       CASE WHEN (h / 4096) % 4 = 0 THEN '2.EncNotes|' || printf('%016x', h * 31) ELSE NULL END,
       CASE WHEN (h / 1024) % 6 = 0 THEN '[{"name":"2.f|' || i || '","value":"2.v","type":0,"linkedId":null}]' ELSE NULL END,
       '{"name":"2.EncName|' || i || '","username":"2.EncUser|' || (h % 99991) || '","password":"2.EncPw|' || printf('%016x', h * 7) ||
         '","totp":null,"uris":[{"uri":"2.EncUri|' || (h % 5000) || '","match":null}],"passwordRevisionDate":null,"fido2Credentials":[]}',
       CASE WHEN (h / 2048) % 10 = 0 THEN '[{"lastUsedDate":"2025-02-01T00:00:00.000Z","password":"2.old"}]' ELSE NULL END,
       CASE WHEN (h / 524288) % 40 = 0 THEN strftime('%Y-%m-%d %H:%M:%f', unixepoch('2026-09-01') + h % 5000000, 'unixepoch') ELSE NULL END,
       CASE WHEN (h / 32) % 15 = 0 THEN 1 ELSE 0 END,
       CASE WHEN (h / 64) % 3 = 0 THEN '2.CipherKey|' || i ELSE NULL END
FROM m;

-- org ciphers live in 1-2 collections of their org
INSERT OR IGNORE INTO ciphers_collections(cipher_uuid, collection_uuid)
SELECT c.uuid, printf('d0000000-0000-4000-8000-%012d', (CAST(substr(c.organization_uuid, 25) AS INTEGER) - 1) * 10 + 1 + CAST(substr(c.uuid, 25) AS INTEGER) % 10)
FROM ciphers c WHERE c.organization_uuid IS NOT NULL
UNION ALL
SELECT c.uuid, printf('d0000000-0000-4000-8000-%012d', (CAST(substr(c.organization_uuid, 25) AS INTEGER) - 1) * 10 + 1 + (CAST(substr(c.uuid, 25) AS INTEGER) / 10) % 10)
FROM ciphers c WHERE c.organization_uuid IS NOT NULL AND CAST(substr(c.uuid, 25) AS INTEGER) % 2 = 0;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 6000*(SELECT scale FROM _cfg))
INSERT INTO folders(uuid, created_at, updated_at, user_uuid, name)
SELECT printf('f0000000-0000-4000-8000-%012d', i), '2024-01-01 00:00:00.000000', '2024-01-01 00:00:00.000000',
       printf('a0000000-0000-4000-8000-%012d', (i - 1) % (2000*(SELECT scale FROM _cfg)) + 1), '2.EncFolder|' || i
FROM n;

-- 60% of personal ciphers are filed into one of their owner's folders
INSERT INTO folders_ciphers(cipher_uuid, folder_uuid)
SELECT c.uuid, printf('f0000000-0000-4000-8000-%012d', CAST(substr(c.user_uuid, 25) AS INTEGER) + (2000*(SELECT scale FROM _cfg)) * (CAST(substr(c.uuid, 25) AS INTEGER) % 3))
FROM ciphers c WHERE c.user_uuid IS NOT NULL AND CAST(substr(c.uuid, 25) AS INTEGER) % 5 < 3;

INSERT INTO favorites(user_uuid, cipher_uuid)
SELECT c.user_uuid, c.uuid FROM ciphers c WHERE c.user_uuid IS NOT NULL AND CAST(substr(c.uuid, 25) AS INTEGER) % 11 = 0;

INSERT INTO archives(user_uuid, cipher_uuid, archived_at)
SELECT c.user_uuid, c.uuid, '2026-08-01 00:00:00.000000' FROM ciphers c WHERE c.user_uuid IS NOT NULL AND CAST(substr(c.uuid, 25) AS INTEGER) % 53 = 0;

INSERT INTO attachments(id, cipher_uuid, file_name, file_size, akey)
SELECT printf('%08x%08x', CAST(substr(c.uuid, 25) AS INTEGER), CAST(substr(c.uuid, 25) AS INTEGER) * 2654435761 % 4294967296), c.uuid,
       '2.EncFileName|' || substr(c.uuid, 25), 1000 + CAST(substr(c.uuid, 25) AS INTEGER) % 900000, '2.AttKey'
FROM ciphers c WHERE CAST(substr(c.uuid, 25) AS INTEGER) % 19 = 0;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 3000*(SELECT scale FROM _cfg))
INSERT INTO sends(uuid, user_uuid, organization_uuid, name, notes, atype, data, akey, max_access_count, access_count,
  creation_date, revision_date, expiration_date, deletion_date, disabled, hide_email)
SELECT printf('50000000-0000-4000-8000-%012d', i), printf('a0000000-0000-4000-8000-%012d', 1 + (i * 7) % (2000*(SELECT scale FROM _cfg))), NULL,
       '2.EncSend|' || i, NULL, i % 2, '{"text":"2.EncText|' || i || '","hidden":false}', '2.SendKey|' || i,
       CASE WHEN i % 4 = 0 THEN 5 ELSE NULL END, i % 3,
       '2026-10-01 00:00:00.000000', '2026-10-01 00:00:00.000000', NULL, '2026-11-01 00:00:00.000000', 0, 0
FROM n;

INSERT INTO org_policies(uuid, org_uuid, atype, enabled, data, revision_date)
SELECT printf('70000000-0000-4000-8000-%012d', o.i * 10 + t.t), printf('b0000000-0000-4000-8000-%012d', o.i), t.t,
       CASE WHEN (o.i + t.t) % 3 = 0 THEN 0 ELSE 1 END, '{}', '2026-01-01 00:00:00'
FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 30) SELECT i FROM n) o,
     (SELECT 0 AS t UNION ALL SELECT 1 UNION ALL SELECT 3) t
WHERE (o.i + t.t) % 2 = 0 OR o.i <= 4;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 3000*(SELECT scale FROM _cfg))
INSERT INTO devices(uuid, created_at, updated_at, user_uuid, name, atype, push_token, refresh_token, twofactor_remember, push_uuid)
SELECT printf('60000000-0000-4000-8000-%012d', i), '2025-01-01 00:00:00.000000', '2026-10-27 00:00:00.000000',
       printf('a0000000-0000-4000-8000-%012d', (i - 1) % (2000*(SELECT scale FROM _cfg)) + 1),
       CASE i % 3 WHEN 0 THEN 'firefox' WHEN 1 THEN 'iPhone' ELSE 'chrome-extension' END, i % 15, NULL,
       printf('rt%08x%08x', i, (i * 2654435761) % 4294967296), NULL, NULL
FROM n;

COMMIT;
