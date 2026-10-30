-- Technitium DNS Server, "Query Logs (Sqlite)" app (TechnitiumSoftware/DnsServer @ 0dd592a, GPL-3.0). C# with
-- Microsoft.Data.Sqlite 10.0.13; @name parameters via AddWithValue. The web console's Logs > Query Logs tab and the CSV
-- export call App.QueryLogsAsync(), which builds one WHERE clause from the chosen filters (App.cs:585-625, fixed order
-- timestamp, client_ip, protocol, response_type, rcode, qname, qtype, qclass; a '*' in the domain turns
-- `qname = @qname` into `qname like @qname` with '*' -> '%'), runs a Count(*) for the pager, then the page with
-- ORDER BY dlid LIMIT/OFFSET. Each block is one real filter instantiation of those two statements; the texts are
-- exact apart from whitespace (and the page query's missing trailing ';'). The cleanup timer (every 15 min) and the
-- bulk inserter supply the rest. The dashboard's top clients/domains are not SQL (in-memory stats files), so the
-- dashboard drill-down links appear here as the filtered query-log pages they open.
-- Data "now" is 2026-10-30 00:00:00 UTC; the log spans 2026-10-20 .. 2026-10-29.

-- @id technitium.querylogs.count.all
-- @src Apps/QueryLogsSqliteApp/App.cs:636 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath,cpu-evidence
-- @note Pager total with no filter: a full Count(*) of dns_logs on every Query button press and every live-update tick; the same text is the cleanup timer's maxLogRecords check (App.cs:89). Users with 0.4-18 GB logs report the app getting really slow: https://github.com/TechnitiumSoftware/DnsServer/issues/563
SELECT Count(*) FROM dns_logs;

-- @id technitium.querylogs.page.latest
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath,hot-small
-- @note Default view and live update: newest 25 entries, ORDER BY dlid DESC LIMIT 25 (a rowid walk from the end).
-- @param @limit 25
-- @param @offset 0
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.page.last_page
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,cpu-evidence
-- @note Pager jump to the last page (or a page number past the end, which the app clamps to the last page): OFFSET skips ~250k rows. Slowness on large logs: https://github.com/TechnitiumSoftware/DnsServer/issues/563
-- @param @limit 25
-- @param @offset 249975
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.count.client
-- @src Apps/QueryLogsSqliteApp/App.cs:636 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath,cpu-evidence
-- @note Count for one client (dashboard Top Clients click), the heaviest client (~20 % of rows). The same Count(*) WHERE client_ip took ~35 s and timed out on a 48M-row log in the MySQL sibling app: https://github.com/TechnitiumSoftware/DnsServer/issues/1996
-- @param @client_ip '192.168.1.10'
SELECT Count(*) FROM dns_logs WHERE client_ip = @client_ip;

-- @id technitium.querylogs.page.client
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath
-- @note First page for one client, newest first: index_client_ip walked backwards gives dlid DESC order.
-- @param @limit 25
-- @param @offset 0
-- @param @client_ip '192.168.1.10'
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE client_ip = @client_ip ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.count.qname_exact
-- @src Apps/QueryLogsSqliteApp/App.cs:636 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath
-- @note Count for the top queried domain (dashboard Top Domains click), ~10 % of all rows.
-- @param @qname 'connectivitycheck.gstatic.com'
SELECT Count(*) FROM dns_logs WHERE qname = @qname;

-- @id technitium.querylogs.page.qname_exact
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath,hot-small
-- @note First page for one exact domain, newest first.
-- @param @limit 25
-- @param @offset 0
-- @param @qname 'connectivitycheck.gstatic.com'
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE qname = @qname ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.count.qname_wildcard
-- @src Apps/QueryLogsSqliteApp/App.cs:636 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath
-- @note User typed *google* in the Domain box: qname like '%google%' can't use index_qname, so the count scans a whole index.
-- @param @qname '%google%'
SELECT Count(*) FROM dns_logs WHERE qname like @qname;

-- @id technitium.querylogs.page.qname_wildcard
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath
-- @note First page for *google*: LIKE filter with ORDER BY dlid DESC LIMIT 25.
-- @param @limit 25
-- @param @offset 0
-- @param @qname '%google%'
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE qname like @qname ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.count.qname_suffix_aaaa
-- @src Apps/QueryLogsSqliteApp/App.cs:636 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic
-- @note *.netflix.com with Type AAAA: leading-wildcard LIKE plus qtype; index_query (qname, qtype) only as a covering scan.
-- @param @qname '%.netflix.com'
-- @param @qtype 28
SELECT Count(*) FROM dns_logs WHERE qname like @qname AND qtype = @qtype;

-- @id technitium.querylogs.page.qname_suffix_aaaa
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic
-- @note First page for *.netflix.com / AAAA, newest first; the match rate is low, so the DESC walk filters many rows per hit.
-- @param @limit 25
-- @param @offset 0
-- @param @qname '%.netflix.com'
-- @param @qtype 28
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE qname like @qname AND qtype = @qtype ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.count.time_hour
-- @src Apps/QueryLogsSqliteApp/App.cs:636 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath
-- @note From/To one hour (minute precision from the GUI, issue #2238): range count on index_timestamp.
-- @param @start '2026-10-29 18:00:00'
-- @param @end '2026-10-29 19:00:00'
SELECT Count(*) FROM dns_logs WHERE timestamp >= @start AND timestamp <= @end;

-- @id technitium.querylogs.page.time_hour
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath
-- @note One hour, newest first: the planner picks between a timestamp-range index scan plus sort and a backwards dlid walk.
-- @param @limit 25
-- @param @offset 0
-- @param @start '2026-10-29 18:00:00'
-- @param @end '2026-10-29 19:00:00'
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE timestamp >= @start AND timestamp <= @end ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.page.time_old_hour
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic
-- @note One hour at the old end of the log, newest first: a backwards dlid walk would pass ~245k rows before the first hit.
-- @param @limit 25
-- @param @offset 0
-- @param @start '2026-10-20 03:00:00'
-- @param @end '2026-10-20 04:00:00'
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE timestamp >= @start AND timestamp <= @end ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.count.week_wildcard
-- @src Apps/QueryLogsSqliteApp/App.cs:636 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath
-- @note From = one week ago (no To) plus *doubleclick*: the LIKE runs over ~70 % of the log via index_timestamp_qname (timestamp, qname).
-- @param @start '2026-10-23 00:00:00'
-- @param @qname '%doubleclick%'
SELECT Count(*) FROM dns_logs WHERE timestamp >= @start AND qname like @qname;

-- @id technitium.querylogs.page.week_wildcard
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath
-- @note First page of the week + *doubleclick* filter, newest first.
-- @param @limit 25
-- @param @offset 0
-- @param @start '2026-10-23 00:00:00'
-- @param @qname '%doubleclick%'
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE timestamp >= @start AND qname like @qname ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.count.blocked
-- @src Apps/QueryLogsSqliteApp/App.cs:636 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath
-- @note Dashboard Blocked click: Response Type = Blocked over the whole log (~13 %).
-- @param @response_type 4
SELECT Count(*) FROM dns_logs WHERE response_type = @response_type;

-- @id technitium.querylogs.page.blocked
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,hotpath
-- @note First page of blocked queries, newest first.
-- @param @limit 25
-- @param @offset 0
-- @param @response_type 4
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE response_type = @response_type ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.count.client_nxdomain
-- @src Apps/QueryLogsSqliteApp/App.cs:636 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic
-- @note One client's NXDOMAIN answers (client + rcode): two single-column indexes, neither selective on its own.
-- @param @client_ip '192.168.1.47'
-- @param @rcode 3
SELECT Count(*) FROM dns_logs WHERE client_ip = @client_ip AND rcode = @rcode;

-- @id technitium.querylogs.page.client_nxdomain
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic
-- @note First page of one client's NXDOMAINs.
-- @param @limit 25
-- @param @offset 0
-- @param @client_ip '192.168.1.47'
-- @param @rcode 3
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE client_ip = @client_ip AND rcode = @rcode ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.count.servfail_day
-- @src Apps/QueryLogsSqliteApp/App.cs:636 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic
-- @note Troubleshooting: SERVFAIL within one day; index_timestamp vs index_rcode vs index_all choice.
-- @param @start '2026-10-28 00:00:00'
-- @param @end '2026-10-29 00:00:00'
-- @param @rcode 2
SELECT Count(*) FROM dns_logs WHERE timestamp >= @start AND timestamp <= @end AND rcode = @rcode;

-- @id technitium.querylogs.page.servfail_day
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic
-- @note SERVFAIL within one day, ascending order (oldest first).
-- @param @limit 25
-- @param @offset 0
-- @param @start '2026-10-28 00:00:00'
-- @param @end '2026-10-29 00:00:00'
-- @param @rcode 2
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE timestamp >= @start AND timestamp <= @end AND rcode = @rcode ORDER BY dlid LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.count.combo_blocked_client
-- @src Apps/QueryLogsSqliteApp/App.cs:636 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic
-- @note Four filters at once (day, client, Blocked, *adserv*): every predicate is a prefix-or-trailing column of index_all (timestamp, client_ip, protocol, response_type, rcode, qname, ...).
-- @param @start '2026-10-29 00:00:00'
-- @param @end '2026-10-29 23:59:00'
-- @param @client_ip '192.168.1.10'
-- @param @response_type 4
-- @param @qname '%adserv%'
SELECT Count(*) FROM dns_logs WHERE timestamp >= @start AND timestamp <= @end AND client_ip = @client_ip AND response_type = @response_type AND qname like @qname;

-- @id technitium.querylogs.page.combo_blocked_client
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic
-- @note Page for the four-filter combination, newest first.
-- @param @limit 25
-- @param @offset 0
-- @param @start '2026-10-29 00:00:00'
-- @param @end '2026-10-29 23:59:00'
-- @param @client_ip '192.168.1.10'
-- @param @response_type 4
-- @param @qname '%adserv%'
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE timestamp >= @start AND timestamp <= @end AND client_ip = @client_ip AND response_type = @response_type AND qname like @qname ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.page.doh_recursive
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic
-- @note DoH (protocol Https) queries that went recursive, page 2 at 50 per page.
-- @param @limit 50
-- @param @offset 50
-- @param @protocol 3
-- @param @response_type 2
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE protocol = @protocol AND response_type = @response_type ORDER BY dlid DESC LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.export.day_page
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,batch
-- @note Export CSV of one day (WebServiceLogsApi.cs:336): pages of 10000 ascending, page 3; the app recounts the range before each page.
-- @param @limit 10000
-- @param @offset 20000
-- @param @start '2026-10-28 00:00:00'
-- @param @end '2026-10-29 00:00:00'
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs WHERE timestamp >= @start AND timestamp <= @end ORDER BY dlid LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.export.all_page
-- @src Apps/QueryLogsSqliteApp/App.cs:681-698 (WHERE built at 585-625)
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags dynamic,cpu-evidence
-- @note Export CSV of the whole log, page 20 of 10000 ascending: the OFFSET walk grows with every page, so the export is quadratic in log size; logs reach 40 GB: https://github.com/TechnitiumSoftware/DnsServer/issues/959
-- @param @limit 10000
-- @param @offset 190000
SELECT dlid, timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer FROM dns_logs ORDER BY dlid LIMIT @limit OFFSET @offset;

-- @id technitium.querylogs.cleanup.count_older
-- @src Apps/QueryLogsSqliteApp/App.cs:108
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags cpu-evidence
-- @note Cleanup timer (every 15 min, maxLogDays = 7): rows older than the cutoff, before batch-deleting them. Retention not keeping up on 0.4-18 GB logs: https://github.com/TechnitiumSoftware/DnsServer/issues/563
-- @param @timestamp '2026-10-23 00:00:00.4821936'
SELECT Count(*) FROM dns_logs WHERE timestamp < @timestamp;

-- @id technitium.querylogs.cleanup.batch_delete
-- @src Apps/QueryLogsSqliteApp/App.cs:132
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags cpu-evidence
-- @note Cleanup batch: delete the 10000 oldest rows by dlid (LIMIT interpolated as BULK_REMOVE_COUNT), repeated until the count is reached; each row touches 13 indexes. https://github.com/TechnitiumSoftware/DnsServer/issues/563
DELETE FROM dns_logs WHERE dlid IN (SELECT dlid FROM dns_logs ORDER BY dlid LIMIT 10000);

-- @id technitium.querylogs.insert_log
-- @src Apps/QueryLogsSqliteApp/App.cs:267
-- @style @name binds (Microsoft.Data.Sqlite AddWithValue; DateTime binds as TEXT 'yyyy-MM-dd HH:mm:ss.FFFFFFF'); WHERE assembled by string concatenation, one instantiation
-- @tags hot-small,hotpath
-- @note Bulk inserter: one prepared INSERT per logged DNS query, up to 1000 per transaction; 13 secondary indexes to maintain.
-- @param @timestamp '2026-10-30 00:00:01.2345678'
-- @param @client_ip '192.168.1.10'
-- @param @protocol 0
-- @param @response_type 2
-- @param @response_rtt 23.41
-- @param @rcode 0
-- @param @qname 'www.example.com'
-- @param @qtype 1
-- @param @qclass 1
-- @param @answer 'A 93.184.215.14'
INSERT INTO dns_logs (timestamp, client_ip, protocol, response_type, response_rtt, rcode, qname, qtype, qclass, answer) VALUES (@timestamp, @client_ip, @protocol, @response_type, @response_rtt, @rcode, @qname, @qtype, @qclass, @answer);
