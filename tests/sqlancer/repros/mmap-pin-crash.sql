-- SQLancer (PQS, differential arm, 3 of 4 seeds), 2026-10-27: SIGSEGV at 0x18 in qv_pin (qvm) and qg_pin/qg_fetch (loop
-- plans) once memory-mapped I/O is on. sqlite3PagerRef() on a PGHDR_MMAP page (pagerAcquireMapPage), whose pCache
-- is NULL: sqlite3PcacheRef's p->pCache->nRefSum++. Needs a file database (tests/sqlancer/crashes.sh, REPLAY_DB) of
-- more than two pages; both tiers, both shims. Stock is fine.
CREATE TABLE t0(c0);
INSERT INTO t0 VALUES ('x');
CREATE TABLE t1(a);
PRAGMA mmap_size = 268435456;
SELECT c0 FROM t0;
