-- Technitium DNS Server, "Query Logs (Sqlite)" app (TechnitiumSoftware/DnsServer @ 0dd592a, GPL-3.0).
-- Only the CREATE statements the queries need, as App.InitializeAsync() issues them
-- (Apps/QueryLogsSqliteApp/App.cs:420-526). The response_rtt ALTER TABLE (App.cs:443) is folded into the table,
-- where it already is for new databases. All 13 secondary indexes are the app's own; nothing added.
CREATE TABLE IF NOT EXISTS dns_logs
(
    dlid INTEGER PRIMARY KEY,
    timestamp DATETIME NOT NULL,
    client_ip VARCHAR(39) NOT NULL,
    protocol TINYINT NOT NULL,
    response_type TINYINT NOT NULL,
    response_rtt REAL,
    rcode TINYINT NOT NULL,
    qname VARCHAR(255),
    qtype SMALLINT,
    qclass SMALLINT,
    answer TEXT
);
CREATE INDEX IF NOT EXISTS index_timestamp ON dns_logs (timestamp);
CREATE INDEX IF NOT EXISTS index_client_ip ON dns_logs (client_ip);
CREATE INDEX IF NOT EXISTS index_protocol ON dns_logs (protocol);
CREATE INDEX IF NOT EXISTS index_response_type ON dns_logs (response_type);
CREATE INDEX IF NOT EXISTS index_rcode ON dns_logs (rcode);
CREATE INDEX IF NOT EXISTS index_qname ON dns_logs (qname);
CREATE INDEX IF NOT EXISTS index_qtype ON dns_logs (qtype);
CREATE INDEX IF NOT EXISTS index_qclass ON dns_logs (qclass);
CREATE INDEX IF NOT EXISTS index_timestamp_client_ip ON dns_logs (timestamp, client_ip);
CREATE INDEX IF NOT EXISTS index_timestamp_qname ON dns_logs (timestamp, qname);
CREATE INDEX IF NOT EXISTS index_client_qname ON dns_logs (client_ip, qname);
CREATE INDEX IF NOT EXISTS index_query ON dns_logs (qname, qtype);
CREATE INDEX IF NOT EXISTS index_all ON dns_logs (timestamp, client_ip, protocol, response_type, rcode, qname, qtype, qclass);
