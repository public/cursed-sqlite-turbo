-- Served 'now' after a statement with a bound parameter (corpus: n8n.executions.find_soft_deleted, 0 rows vs 100).
-- The database: corpus build <db> now-after-bind.sql. The statements: now-after-bind.q, through corpus check with
-- QC_SERVE=1 and CORPUS_ROWS=1. v0 (first on the connection) shows the right time; v1, after pre (?1 bound), shows
-- -4712-11-06 11:19:31.076 / julianday 347.97 in every served run; stock shows the current time in both.
CREATE TABLE e(id INTEGER PRIMARY KEY, status TEXT, d TEXT);
WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM c WHERE i<500)
INSERT INTO e SELECT i, CASE WHEN i%2 THEN 'success' ELSE 'error' END, '2020-01-01 00:00:00.000' FROM c;
