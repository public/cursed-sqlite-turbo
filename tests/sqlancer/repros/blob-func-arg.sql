-- SQLancer (TLP aggregate oracle, and the differential arm), 2026-10-27: a BLOB passed to a built-in scalar function
-- by a loop plan (qc/qcg.c qg_mem) carried enc 0, so sqlite3_value_text() converted it as UTF-16. Plans first:
-- unicode 61134, ltrim/upper ''; SQLite and qvm: 65533 and the 2-byte text. tests/sqlancer/repro.sh <this file>.
CREATE TABLE t1(c0 INTEGER);
INSERT INTO t1 VALUES (x'eece'), (x'');
SELECT UNICODE(c0) FROM t1;
SELECT MAX(LTRIM(c0)) FROM t1;
SELECT UPPER(c0) FROM t1;
SELECT MAX(UNICODE(c0) COLLATE NOCASE COLLATE BINARY) FROM t1;
