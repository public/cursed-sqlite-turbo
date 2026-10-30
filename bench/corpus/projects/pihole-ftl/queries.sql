-- Pi-hole FTL (pi-hole/FTL @ 29c8b13, EUPL-1.2). C with the SQLite C API: sqlite3_prepare_v2/_v3 and
-- sqlite3_bind_*; positional `?`/`?N` in the DNS hot path, named `:name` in the API. The /api/queries SQL and the
-- gravityDB_readTable() list SQL are assembled with snprintf at runtime; each block here is one instantiation.
-- Both of FTL's databases (gravity.db and the query DB) share one schema; disk.query_storage of the ATTACHed
-- long-term DB is the table disk_query_storage here.

-- ===================================================================== query database: DNS hot path

-- @id ftl.querydb.insert_query
-- @src src/database/query-table.c:367-368
-- @style ?N positional, persistent prepared statement (SQLITE_PREPARE_PERSISTENT)
-- @tags hot-small,hotpath
-- @note Every DNS query FTL answers is written (and rewritten as its status/reply change) into the in-memory query_storage with this REPLACE; 10 secondary indexes to maintain.
-- @param ?1 50001
-- @param ?2 1761300010.5
-- @param ?3 1
-- @param ?4 2
-- @param ?5 1600
-- @param ?6 4
-- @param ?7 1
-- @param ?8 NULL
-- @param ?9 4
-- @param ?10 0.0123
-- @param ?11 0
-- @param ?12 NULL
-- @param ?13 NULL
REPLACE INTO query_storage VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13);

-- @id ftl.querydb.client_id_lookup
-- @src src/database/query-table.c:418
-- @style ? positional, persistent prepared statement
-- @tags hot-small,hotpath
-- @note Linking-table id lookup on first sight of a (client IP, name) pair; composite unique index point lookup.
-- @param ?1 '192.168.1.4'
-- @param ?2 'device-3.lan'
SELECT id FROM client_by_id WHERE ip = ?1 AND name = ?2;

-- @id ftl.querydb.export_to_disk
-- @src src/database/query-table.c:453-457
-- @style ?N positional, persistent prepared statement; runs every database.DBinterval (60 s)
-- @tags batch
-- @modified disk.query_storage (ATTACHed pihole-FTL.db) is the table disk_query_storage in this single-file corpus DB.
-- @note Periodic memory-to-disk export: INSERT ... SELECT * bounded by two nested scalar MAX/MIN subqueries over the attached table, so rows inside the cutoff window hold back the export.
-- @param ?1 1761570000
-- @param ?2 1761600100
INSERT INTO disk_query_storage SELECT * FROM query_storage
WHERE id > (SELECT IFNULL(MAX(id), -1) FROM disk_query_storage)
  AND id < (SELECT IFNULL(MIN(id), 9223372036854775807) FROM query_storage
            WHERE id > (SELECT IFNULL(MAX(id), -1) FROM disk_query_storage)
              AND timestamp >= ?1 AND timestamp <= ?2);

-- @id ftl.querydb.delete_old_batch
-- @src src/database/query-table.c:1172-1174
-- @style ? positional; ?2 bound to DATABASE_DELETE_BATCH (10000)
-- @note Retention: delete in batches of 10000 via IN (SELECT ... ORDER BY timestamp LIMIT ?) on the timestamp index.
-- @param ?1 1761100000
-- @param ?2 10000
DELETE FROM query_storage WHERE id IN (SELECT id FROM query_storage WHERE timestamp <= ?1 ORDER BY timestamp LIMIT ?2);

-- @id ftl.querydb.read_queries_view
-- @src src/database/query-table.c:1631-1642
-- @style no parameters; view from src/database/query-table.h:41-51 (CREATE_QUERIES_VIEW)
-- @note Startup history import through the `queries` view: four CASE typeof(...) WHEN 'integer' THEN (correlated scalar subquery) columns per row over the whole table.
SELECT id, timestamp, type, status, domain, client, forward, additional_info, reply_type, reply_time, dnssec FROM queries;

-- ===================================================================== /api/queries (query log page)

-- @id ftl.api_queries.default_page
-- @src src/api/queries.c:181-184,300,609
-- @style :name, string-built (QUERYSTR + JOINSTR + querystr_finish)
-- @tags hotpath,dynamic
-- @modified LIMIT 100 added: with no filter the C loop stops stepping after `length` (default 100) rows; the statement itself has no LIMIT.
-- @note Query log first page: 4-way join (2 inner, 2 LEFT) from query_storage to the linking tables, newest first by rowid.
SELECT q.id,timestamp,q.type,status,d.domain,f.forward,additional_info,reply_type,reply_time,dnssec,c.ip,c.name,a.content,list_id,ede
FROM query_storage q
JOIN client_by_id c ON q.client = c.id JOIN domain_by_id d ON q.domain = d.id
LEFT JOIN forward_by_id f ON q.forward = f.id LEFT JOIN addinfo_by_id a ON a.id = q.additional_info
ORDER BY q.id DESC
LIMIT 100;

-- @id ftl.api_queries.domain_wildcard_window
-- @src src/api/queries.c:300-351,445,609
-- @style :name, string-built WHERE via add_querystr_string()
-- @tags hotpath,dynamic
-- @note ?from=&until=&domain=*track4*&cursor=: time window + wildcard LIKE on the joined domain + cursor; the C loop steps every row to count recordsFiltered.
-- @param :tsfrom 1761300000
-- @param :tsuntil 1761386400
-- @param :domain '%track4%'
-- @param :cursor 70000
SELECT q.id,timestamp,q.type,status,d.domain,f.forward,additional_info,reply_type,reply_time,dnssec,c.ip,c.name,a.content,list_id,ede
FROM query_storage q
JOIN client_by_id c ON q.client = c.id JOIN domain_by_id d ON q.domain = d.id
LEFT JOIN forward_by_id f ON q.forward = f.id LEFT JOIN addinfo_by_id a ON a.id = q.additional_info
WHERE (timestamp>=:tsfrom) AND (timestamp<:tsuntil) AND (d.domain LIKE:domain) AND (q.id<=:cursor)
ORDER BY q.id DESC;

-- @id ftl.api_queries.blocklist_client
-- @src src/api/queries.c:300,363-398,609; status list from src/datastructure.c:1115-1138
-- @style :name, string-built; get_blocked_statuslist() is spliced in as a literal IN list
-- @tags hotpath,dynamic
-- @note ?upstream=blocklist&client_ip=…&order=time desc: blocked-status IN list plus exact client IP, sorted by timestamp.
-- @param :cip '192.168.1.3'
SELECT q.id,timestamp,q.type,status,d.domain,f.forward,additional_info,reply_type,reply_time,dnssec,c.ip,c.name,a.content,list_id,ede
FROM query_storage q
JOIN client_by_id c ON q.client = c.id JOIN domain_by_id d ON q.domain = d.id
LEFT JOIN forward_by_id f ON q.forward = f.id LEFT JOIN addinfo_by_id a ON a.id = q.additional_info
WHERE (q.status IN (1,4,5,6,7,8,9,10,11,15,16,18)) AND (c.ip=:cip)
ORDER BY timestamp DESC;

-- @id ftl.api_queries.datatables_search
-- @src src/api/queries.c:300,461-468,512-565,609
-- @style :name, string-built; DataTables column search adds '%' around the term
-- @tags hotpath,dynamic
-- @note DataTables per-column search: domain LIKE … ESCAPE plus an OR across client IP and name, type filter, sorted by reply time.
-- @param :type 2
-- @param :domain_search '%netflix%'
-- @param :client_search '%device-1%'
SELECT q.id,timestamp,q.type,status,d.domain,f.forward,additional_info,reply_type,reply_time,dnssec,c.ip,c.name,a.content,list_id,ede
FROM query_storage q
JOIN client_by_id c ON q.client = c.id JOIN domain_by_id d ON q.domain = d.id
LEFT JOIN forward_by_id f ON q.forward = f.id LEFT JOIN addinfo_by_id a ON a.id = q.additional_info
WHERE (q.type=:type) AND (d.domain LIKE:domain_search ESCAPE '\') AND (c.ip LIKE :client_search ESCAPE '\' OR c.name LIKE:client_search ESCAPE '\')
ORDER BY q.reply_time DESC;

-- @id ftl.api_queries.disk_upstream_dnssec
-- @src src/api/queries.c:300,381-388,478-481,609
-- @style :name, string-built; ?disk=true selects the attached long-term table
-- @tags dynamic
-- @modified disk.query_storage is disk_query_storage (single-file corpus DB).
-- @note Long-term query log: exact upstream on the LEFT-joined forward table, DNSSEC status filter, sorted by domain text.
-- @param :tsfrom 1761000000
-- @param :upstream '9.9.9.9#53'
-- @param :dnssec 2
SELECT q.id,timestamp,q.type,status,d.domain,f.forward,additional_info,reply_type,reply_time,dnssec,c.ip,c.name,a.content,list_id,ede
FROM disk_query_storage q
JOIN client_by_id c ON q.client = c.id JOIN domain_by_id d ON q.domain = d.id
LEFT JOIN forward_by_id f ON q.forward = f.id LEFT JOIN addinfo_by_id a ON a.id = q.additional_info
WHERE (timestamp>=:tsfrom) AND (f.forward=:upstream) AND (q.dnssec=:dnssec)
ORDER BY d.domain ASC;

-- ===================================================================== long-term statistics (/api/*/database)

-- @id ftl.stats_db.history_over_time
-- @src src/api/stats_database.c:54-56
-- @style :name
-- @tags hotpath
-- @note Long-term graph: 10-minute buckets via (CAST(timestamp AS INTEGER)/:interval)*:interval, GROUP BY bucket,status.
-- @param :interval 600
-- @param :from 1761200000
-- @param :until 1761286400
SELECT (CAST(timestamp AS INTEGER)/:interval)*:interval interval,status,COUNT(*) FROM query_storage
WHERE (status != 0) AND timestamp >= :from AND timestamp <= :until
GROUP by interval,status ORDER by interval;

-- @id ftl.stats_db.top_domains_blocked
-- @src src/api/stats_database.c:236-241
-- @style :name; FILTER_STATUS_BLOCKED (stats_database.c:25) spliced in
-- @tags hotpath
-- @note Top blocked domains: grouped derived table over a time range with NOT IN status list, joined to domain_by_id, top-N by count.
-- @param :from 1761000000
-- @param :until 1761604800
-- @param :count 10
SELECT q.cnt,d.domain FROM
  (SELECT domain,COUNT(*) AS cnt FROM query_storage
   WHERE timestamp >= :from AND timestamp <= :until AND status NOT IN (0,2,3,12,13,14,17)
   GROUP BY domain) q
JOIN domain_by_id d ON d.id = q.domain ORDER BY q.cnt DESC LIMIT :count;

-- @id ftl.stats_db.top_clients_permitted
-- @src src/api/stats_database.c:278-283
-- @style :name; FILTER_STATUS_NOT_BLOCKED (stats_database.c:24) spliced in
-- @tags hotpath
-- @note Top permitted clients over a range: GROUP BY client in a derived table, join, top-N.
-- @param :from 1761200000
-- @param :until 1761286400
-- @param :count 10
SELECT q.cnt,c.ip,c.name FROM
  (SELECT client,COUNT(*) AS cnt FROM query_storage
   WHERE timestamp >= :from AND timestamp <= :until AND status IN (0,2,3,12,13,14,17)
   GROUP BY client) q
JOIN client_by_id c ON c.id = q.client ORDER BY q.cnt DESC LIMIT :count;

-- @id ftl.stats_db.summary_blocked
-- @src src/api/stats_database.c:422-425
-- @style positional via db_query_int_from_until() (src/database/common.c:1117), :from/:until bound as 1/2
-- @tags hotpath
-- @note Summary tile: count of blocked queries in a range (timestamp index range + NOT IN filter).
-- @param :from 1761200000
-- @param :until 1761286400
SELECT COUNT(*) FROM query_storage WHERE timestamp >= :from AND timestamp <= :until AND status NOT IN (0,2,3,12,13,14,17);

-- @id ftl.stats_db.client_list
-- @src src/api/stats_database.c:493-498
-- @style :name
-- @note Clients keyed by IP: per-client counts regrouped by IP with MAX(name)/SUM(cnt) (several client_by_id rows share an IP).
-- @param :from 1761000000
-- @param :until 1761604800
SELECT ip,MAX(name),SUM(cnt) FROM
  (SELECT client,COUNT(*) AS cnt FROM query_storage
   WHERE timestamp >= :from AND timestamp <= :until
   GROUP BY client) q
JOIN client_by_id ON client_by_id.id = q.client
GROUP BY ip ORDER BY ip;

-- @id ftl.stats_db.clients_over_time
-- @src src/api/stats_database.c:554-559
-- @style :name
-- @tags hotpath
-- @note Per-client graph: two-level GROUP BY (bucket, client) then (bucket, ip) after the join, ordered bucket DESC.
-- @param :interval 600
-- @param :from 1761200000
-- @param :until 1761286400
SELECT q.interval,ip,SUM(cnt) FROM
  (SELECT (CAST(timestamp AS INTEGER)/:interval)*:interval AS interval,client,COUNT(*) AS cnt
   FROM query_storage WHERE timestamp >= :from AND timestamp <= :until
   GROUP BY interval,client) q
JOIN client_by_id ON client_by_id.id = q.client
GROUP BY q.interval,ip ORDER BY q.interval DESC, ip;

-- @id ftl.stats_db.query_types
-- @src src/api/stats_database.c:690-692
-- @style :name
-- @note Query type pie over a range: one-pass GROUP BY type.
-- @param :from 1761000000
-- @param :until 1761604800
SELECT type,COUNT(*) FROM query_storage WHERE timestamp >= :from AND timestamp <= :until GROUP BY type;

-- @id ftl.stats_db.upstreams
-- @src src/api/stats_database.c:813-818
-- @style :name; FILTER_STATUS_FORWARDED (stats_database.c:27) spliced in
-- @note Upstream pie: forwarded-status IN list, GROUP BY forward, join forward_by_id.
-- @param :from 1761000000
-- @param :until 1761604800
SELECT f.forward,q.cnt FROM
  (SELECT forward,COUNT(*) AS cnt FROM query_storage
   WHERE timestamp >= :from AND timestamp <= :until AND status IN (2,12,13)
   GROUP BY forward) q
JOIN forward_by_id f ON q.forward = f.id ORDER BY q.forward;

-- ===================================================================== gravity.db

-- @id ftl.gravity.lookup_gravity
-- @src src/database/gravity-db.c:483
-- @style ?N positional, shared prepared statement; ?2 bound with sqlite3_carray_bind()
-- @tags hot-small,hotpath
-- @modified `group_id IN carray(?2)` becomes `group_id IN (?2,?3,?4)`: carray needs a C pointer binding the CLI cannot make.
-- @note Blocklist check on every DNS cache miss: point lookup on idx_gravity through vw_gravity's three LEFT JOINs with the enabled-flag/group predicates.
-- @param ?1 'ad1235.track71.net'
-- @param ?2 0
-- @param ?3 1
-- @param ?4 2
SELECT adlist_id FROM vw_gravity WHERE domain = ?1 AND group_id IN (?2,?3,?4);

-- @id ftl.gravity.lookup_denylist
-- @src src/database/gravity-db.c:492
-- @style ?N positional, shared prepared statement; carray group binding
-- @tags hotpath
-- @modified `group_id IN carray(?2)` becomes `group_id IN (?2,?3,?4)` (carray needs a C pointer binding).
-- @note Exact denylist check through vw_denylist (domainlist UNIQUE(domain,type) + group junction + group table).
-- @param ?1 'ad45071.track63.net'
-- @param ?2 0
-- @param ?3 1
-- @param ?4 4
SELECT id FROM vw_denylist WHERE domain = ?1 AND group_id IN (?2,?3,?4);

-- @id ftl.gravity.regex_deny_groups
-- @src src/database/gravity-db.c:497
-- @style ?N positional, carray group binding
-- @tags hotpath
-- @modified `group_id IN carray(?1)` becomes `group_id IN (?1,?2,?3)` (carray needs a C pointer binding).
-- @note Which regex deny filters apply to a client: DISTINCT over the view, driven by the group-id IN list.
-- @param ?1 0
-- @param ?2 2
-- @param ?3 6
SELECT DISTINCT id FROM vw_regex_denylist WHERE group_id IN (?1,?2,?3);

-- @id ftl.gravity.client_groups
-- @src src/database/gravity-db.c:1046
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Group ids of a configured client; WITHOUT ROWID primary-key prefix scan.
-- @param ?1 10
SELECT group_id FROM client_by_group WHERE client_id = ?1;

-- @id ftl.gravity.list_domains
-- @src src/database/gravity-db.c:2794-2813
-- @style :item named, string-built (type IN list and LIKE filter formatted in)
-- @tags hotpath,dynamic
-- @note /api/domains list with partial search: correlated GROUP_CONCAT of group ids per row, type IN list, LIKE … ESCAPE.
-- @param :item '%example.com%'
SELECT id,domain,type,enabled,date_added,date_modified,comment,
       (SELECT GROUP_CONCAT(group_id) FROM domainlist_by_group g WHERE g.domainlist_id = d.id) AS group_ids
FROM domainlist d WHERE d.type IN (0,1) AND domain LIKE :item ESCAPE '\';

-- @id ftl.gravity.list_adlists
-- @src src/database/gravity-db.c:2743-2766
-- @style :item named, string-built
-- @tags dynamic
-- @note /api/lists?type=block: correlated GROUP_CONCAT of group ids per adlist.
SELECT id,type,address,enabled,date_added,date_modified,comment,
       (SELECT GROUP_CONCAT(group_id) FROM adlist_by_group g WHERE g.adlist_id = a.id) AS group_ids,
       date_updated,number,invalid_domains,status,abp_entries
FROM adlist a WHERE type = 0;

-- @id ftl.gravity.search_gravity_partial
-- @src src/database/gravity-db.c:2780-2793
-- @style :item named, string-built; called from src/api/search.c:117 with partial=true
-- @tags dynamic
-- @note /api/search partial match: '%term%' LIKE over every gravity row joined to adlist, correlated GROUP_CONCAT of the list's groups.
-- @param :item '%ad1235.%'
SELECT domain,a.id,a.address,a.enabled,a.date_added,a.date_modified,a.comment,a.date_updated,a.number,a.invalid_domains,a.status,a.abp_entries,a.type,
       (SELECT GROUP_CONCAT(group_id) FROM adlist_by_group ag WHERE ag.adlist_id = g.adlist_id) AS group_ids
FROM gravity g JOIN adlist a ON a.id = g.adlist_id WHERE g.domain LIKE :item ESCAPE '\';

-- @id ftl.gravity.upsert_domain
-- @src src/database/gravity-db.c:2114-2117
-- @style :name named
-- @note PUT /api/domains: UPSERT whose inserted type is a CASE over an EXISTS subquery, moving an existing row between types; fires the domainlist triggers.
-- @param :item 'host2000.cdn.net'
-- @param :oldtype 1
-- @param :type 0
-- @param :enabled 1
-- @param :comment 'moved from deny to allow'
INSERT INTO domainlist (domain,type,enabled,comment) VALUES (:item,
  CASE WHEN EXISTS (SELECT 1 FROM domainlist WHERE domain = :item AND type = :oldtype) THEN :oldtype ELSE :type END,
  :enabled,:comment)
ON CONFLICT(domain,type) DO UPDATE SET type = :type, enabled = :enabled, comment = :comment;

-- ===================================================================== network table / messages

-- @id ftl.network.devices_api
-- @src src/api/network.c:393-403
-- @style ? positional
-- @tags hotpath
-- @modified `g.client` (gravity.db ATTACHed as g) is `client` in the single-file corpus DB.
-- @note /api/network/devices unconfigured devices: two correlated GROUP_CONCAT(DISTINCT) per device, two NOT IN subqueries with lower()/CONCAT, top-N by lastQuery.
-- @param ?1 50
SELECT n.hwaddr,n.macVendor,n.lastQuery,
       (SELECT GROUP_CONCAT(DISTINCT na.ip) FROM network_addresses na WHERE na.network_id = n.id),
       (SELECT GROUP_CONCAT(DISTINCT na.name) FROM network_addresses na WHERE na.network_id = n.id)
FROM network n
WHERE n.hwaddr NOT IN (SELECT lower(ip) FROM client)AND n.hwaddr NOT IN (SELECT CONCAT('ip-',lower(ip)) FROM client)ORDER BY lastQuery DESC LIMIT ?1;

-- @id ftl.network.upsert_address
-- @src src/database/network-table.c:483-485
-- @style ?N positional
-- @tags hot-small
-- @note ARP/neighbour scan: UPSERT of an address, refreshing lastSeen on conflict.
-- @param ?1 42
-- @param ?2 '192.168.1.43'
INSERT INTO network_addresses (network_id,ip,lastSeen) VALUES (?1,?2,(cast(strftime('%s', 'now') as int)))
ON CONFLICT(ip) DO UPDATE SET lastSeen = excluded.lastSeen;

-- @id ftl.network.name_from_ip_fallback
-- @src src/database/network-table.c:2321-2325
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Client host-name resolution fallback: scalar subquery for the device id, then latest named address of that device.
-- @param ?1 '192.168.1.13'
SELECT name FROM network_addresses
WHERE name IS NOT NULL AND network_id = (SELECT network_id FROM network_addresses WHERE ip = ?1)
ORDER BY lastSeen DESC LIMIT 1;

-- @id ftl.message.count_filtered
-- @src src/database/message-table.c:1104
-- @style no parameters (variant chosen by config)
-- @tags hot-small,hotpath
-- @note Dashboard badge poll: message count excluding two types (NOT IN list).
SELECT COUNT(*) FROM message WHERE type NOT IN ('DNSMASQ_WARN', 'CONNECTION_ERROR');
