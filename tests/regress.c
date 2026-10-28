// regress: the bugs found so far, each a schema and its queries, qc against the interpreter value by value. Each query
// is lifted once and run five times (its plan, its feedback, its regions; the last two in autocommit). Run as is (plans first) and with
// QC_VM_ONLY=1. Add a case for every wrong result found (SQLancer, the suites, the replays).
#define SQLITE_ENABLE_DBPAGE_VTAB 1   /* (the corrupt-record cases patch a page in place) */
#include "sqlite3.c"
#include "qc.c"
#include <stdio.h>
#include <stdlib.h>

typedef struct { const char *what, *setup, *q[12]; int file; const char *from, *to; } Case;
/* file: an on-disk database (build/regress.db), for what :memory: doesn't do (mmap); from/to: 5 record bytes patched
   in page 2 after the setup (a corrupt record): then the interpreter reports an error and qc must not return rows */
static const Case CASES[] = {
  {"SQLancer (bench, 2026-10-27): a blob passed to a built-in function by a loop plan was read as UTF-16 text (qg_mem left enc 0)",
   "CREATE TABLE t1(c0 INTEGER); INSERT INTO t1 VALUES (x'eece'), (x''), (x'41'), (NULL), (7);",
   {"SELECT UNICODE(c0) FROM t1", "SELECT MAX(LTRIM(c0)) FROM t1", "SELECT UPPER(c0) FROM t1", "SELECT LOWER(c0), LENGTH(c0), HEX(c0) FROM t1",
    "SELECT MAX(UNICODE(c0) COLLATE NOCASE COLLATE BINARY) FROM t1", "SELECT c0 FROM t1 WHERE UPPER(c0) = 'A'", 0}},
  {"gcc x86 (exp357, 2026-10-27): IdxGT's integer fast path read the cell's key before the call that decodes it (unspecified argument order): the scan ran past its range",
   "CREATE TABLE c(id INTEGER PRIMARY KEY, issue_id INT, type INT, ct INT, body TEXT); CREATE INDEX ci ON c(issue_id);"
   "WITH RECURSIVE r(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < 3000) INSERT INTO c SELECT n, n / 4, n % 3, 1000 - n, 'x' || n FROM r;",
   {"SELECT id, type, ct FROM c WHERE issue_id = 300 AND type = 0 ORDER BY ct, id", "SELECT id, body FROM c WHERE issue_id = 7 ORDER BY ct",
    "SELECT count(*), max(id) FROM c WHERE issue_id = 512", "SELECT id FROM c WHERE issue_id BETWEEN 10 AND 12", "SELECT id FROM c WHERE issue_id > 745", 0}},
  {"SQLancer (bench, 2026-10-27): with PRAGMA mmap_size every tier crashed, pinning a memory-mapped page (sqlite3PagerRef on a page with no cache)",
   "CREATE TABLE t0(c0); INSERT INTO t0 VALUES ('x');"
   "CREATE TABLE t(id INTEGER PRIMARY KEY, a INT, b TEXT); CREATE INDEX ta ON t(a); CREATE TABLE u(x INT, y TEXT); CREATE INDEX ux ON u(x);"
   "WITH RECURSIVE r(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < 2000) INSERT INTO t SELECT n, n % 50, printf('%0300d', n) FROM r;"
   "INSERT INTO u SELECT a, b FROM t WHERE id % 3 = 0; PRAGMA mmap_size = 268435456;",
   {"SELECT c0 FROM t0", "SELECT id, a, b FROM t WHERE id = 77", "SELECT id, b FROM t WHERE a = 7 ORDER BY id", "SELECT t.id, u.y FROM t JOIN u ON u.x = t.a WHERE t.id < 40 ORDER BY 1, 2",
    "SELECT a, count(*), max(b) FROM t GROUP BY a ORDER BY a", "SELECT b FROM t ORDER BY b DESC LIMIT 5", "SELECT count(*) FROM t WHERE a = 3 AND b > '0'", 0}, 1},
  {"turbo-bench TPC-H/ClickBench (2026-10-27): a sorter past SQLite's spill size made qvm fall back after doing the work (now SQLite's own sorter takes over); equal keys must come out in SQLite's order",
   "PRAGMA cache_size = 10; CREATE TABLE big(id INTEGER PRIMARY KEY, a INT, b TEXT, c REAL);"
   "WITH RECURSIVE r(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < 30000) INSERT INTO big SELECT n, n % 37, printf('%0120d', (n * 7919) % 30000), (n % 101) / 3.0 FROM r;",
   {"SELECT a, b FROM big ORDER BY a", "SELECT a, c, id FROM big ORDER BY c DESC, a", "SELECT a, group_concat(id) FROM big GROUP BY a",
    "SELECT DISTINCT b FROM big ORDER BY 1 LIMIT 50", "SELECT a, count(*), sum(c) FROM big GROUP BY a, round(c) ORDER BY 3 DESC, 1", "SELECT b, id FROM big ORDER BY substr(b, 100), a LIMIT 3000 OFFSET 20", 0}, 1},
  {"speedtest1 json (2026-10-27): overflow records were copied whole into the arena for every row read (q0 ran out of arena and fell back); now fields past the cell are read from the overflow pages, large ones shared per row (vdbeColumnFromOverflow's cache)",
   "CREATE TABLE b(id INTEGER PRIMARY KEY, k INT, t TEXT, x BLOB, j JSONB);"
   "WITH RECURSIVE r(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < 120) INSERT INTO b SELECT n, n % 7, printf('%.*c', 3000 + n * 97, 'a' + n % 26) || n, randomblob(5000 + n * 50), jsonb_object('a', n, 'p', printf('%.*c', 6000, 'q'), 'v', json_array(n, n * 2, 'z')) FROM r;",
   {"SELECT id, length(t), substr(t, 1, 5), substr(t, -6), length(x), hex(substr(x, 1, 4)) FROM b ORDER BY id", "SELECT t, j ->> '$.a', j ->> '$.v[1]' FROM b WHERE k = 3",
    "SELECT k, max(t), count(DISTINCT t), sum(length(x)) FROM b GROUP BY k ORDER BY k", "SELECT t FROM b ORDER BY t DESC LIMIT 7", "SELECT b1.id, b2.id FROM b b1, b b2 WHERE b1.t = b2.t AND b1.id < 30 ORDER BY 1",
    "SELECT sum(j ->> '$.a' + j ->> '$.v[0]' + length(j ->> '$.p')), max(j -> '$.v') FROM b", "SELECT x FROM b WHERE id IN (3, 77, 119)", 0}, 1},
  {"sum (2026-10-28): after its first float qvm steps SQLite's SumCtx itself (sumStep's Kahan-Babuska-Neumaier steps, an integer overflow, text and NULL)",
   "CREATE TABLE s(id INTEGER PRIMARY KEY, g INT, r REAL, v);"
   "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 600) INSERT INTO s SELECT i, i % 7, i * 1.1 + (i % 13) / 7.0, CASE i % 9 WHEN 0 THEN NULL WHEN 1 THEN '12.5' WHEN 2 THEN 9223372036854775000 WHEN 3 THEN 'x' WHEN 4 THEN 1e300 WHEN 5 THEN -1e300 ELSE i END FROM n;"
   "INSERT INTO s VALUES (601, 1, 3, 9223372036854775807), (602, 1, 2.0, 9223372036854775807), (603, 2, 0.1, -9223372036854775807);",
   {"SELECT sum(r), total(r), avg(r), count(r) FROM s", "SELECT g, sum(r), avg(r), sum(v), total(v), avg(v) FROM s GROUP BY g ORDER BY g",
    "SELECT sum(r) FROM s WHERE id BETWEEN 100 AND 200", "SELECT sum(v) FROM s WHERE id > 590", "SELECT g, sum(r * 3), sum(id) + 0.5 FROM s GROUP BY g ORDER BY 1",
    "SELECT id, sum(r) OVER (ORDER BY id ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) FROM s WHERE id < 40 ORDER BY id", "SELECT sum(r) FROM s WHERE r > 1e9", 0}},
  {"LIKE (2026-10-28): qvm's '%word%' search (ASCII case folded, the text up to its first NUL) and terminated text arguments for functions",
   "CREATE TABLE p(id INTEGER PRIMARY KEY, name TEXT, x);"
   "INSERT INTO p VALUES (1, 'dark green lace', 1), (2, 'GREEN', 2), (3, 'gReEn', 3), (4, 'gree', 4), (5, 'greengreen', 5), (6, NULL, 6),"
   " (7, CAST(x'6100677265656e' AS TEXT), 7), (8, CAST(x'677265656e00' AS TEXT), 8), (9, 12345, 9), (10, x'677265656e', 10), (11, 'grÉen gréen', 11),"
   " (12, 'g_r%een', 12), (13, '', 13), (14, 'Ägreen', 14), (15, 'xgreex green', 15);"
   "WITH RECURSIVE r(n) AS (SELECT 16 UNION ALL SELECT n + 1 FROM r WHERE n < 400) INSERT INTO p SELECT n, printf('%s %d', CASE n % 3 WHEN 0 THEN 'green' WHEN 1 THEN 'blue' ELSE 'GrEeNy' END, n), n FROM r;",
   {"SELECT id FROM p WHERE name LIKE '%green%' ORDER BY id", "SELECT id, name LIKE '%GrEeN%', name NOT LIKE '%een%' FROM p ORDER BY id",
    "SELECT count(*) FROM p WHERE id BETWEEN 1 AND 300 AND name LIKE '%green%'", "SELECT id FROM p WHERE name LIKE '%r_e%' OR name LIKE '%%' ORDER BY id LIMIT 30",
    "SELECT id, x LIKE '%3%', name LIKE '%é%', name LIKE '%É%' FROM p WHERE id < 20 ORDER BY id", "SELECT id, name LIKE '%_r%%' FROM p WHERE id < 20 ORDER BY id",
    "SELECT id, upper(name), substr(name, 2, 3), instr(name, 'een') FROM p WHERE id < 30 ORDER BY id", "SELECT id FROM p WHERE name LIKE '%n 1%' ORDER BY id", 0}},
  {"point lookups (2026-10-28): specialised plans take REAL columns (OP_RealAffinity: an integer stored for an integral value reads as a float) and an integer literal for the rowid",
   "CREATE TABLE c(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO c VALUES (1, 'a'), (5, 'e'), (6, 'f');"
   "CREATE TABLE o(id INTEGER PRIMARY KEY, cust INT, price REAL, d TEXT, w REAL); CREATE INDEX op ON o(price);"
   "INSERT INTO o VALUES (5, 1, 12, 'x', 5), (6, 5, 12.5, 'y', 6.5), (7, 6, NULL, 'z', NULL), (8, 1, 'abc', 'w', 1e300), (9, 5, -0.0, '', 9223372036854775807), (10, 6, 3, NULL, -7);",
   {"SELECT price, d FROM o WHERE id = 5", "SELECT price, d, w FROM o WHERE id = 6", "SELECT price, w FROM o WHERE id = 7", "SELECT d, price, w FROM o WHERE id = 8",
    "SELECT w, price FROM o WHERE id = 9", "SELECT price FROM o WHERE id = 999", "SELECT o.price, c.name, o.w FROM o, c WHERE o.id = 10 AND c.id = o.cust",
    "SELECT c.name FROM o, c WHERE o.id = 6 AND c.id = o.w", 0}},
  {"point lookups (2026-10-28): a REAL column from a covering index, and as a join key",
   "CREATE TABLE c(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO c VALUES (1, 'a'), (5, 'e'), (6, 'f'), (12, 'l');"
   "CREATE TABLE o(id INTEGER PRIMARY KEY, cust INT, price REAL, w REAL); CREATE INDEX op ON o(price);"
   "INSERT INTO o VALUES (5, 1, 12, 5), (6, 5, 12.5, 6.5), (7, 6, NULL, NULL), (8, 1, 'abc', 1), (9, 5, -0.0, 6), (10, 6, 3, 12);",
   {"SELECT price, id FROM o ORDER BY price LIMIT 4", "SELECT id, price FROM o INDEXED BY op WHERE price > 1 ORDER BY price LIMIT 9",
    "SELECT o.id, c.name FROM o, c WHERE o.id = 10 AND c.id = o.w", "SELECT o.id, c.name FROM o, c WHERE o.id = 5 AND c.id = o.price", 0}},
  {"corpus (2026-10-28): loop plans decode a record the generic decoder reads (a DATETIME column, no shape) in two steps: the filters' columns, then the rest for a row that passes",
   "CREATE TABLE d(uuid TEXT NOT NULL, created DATETIME NOT NULL, user TEXT, atype INTEGER, push TEXT, tok TEXT NOT NULL, two TEXT, n NUMERIC, PRIMARY KEY(uuid, user));"
   "CREATE TABLE u(id TEXT PRIMARY KEY, name TEXT, at DATETIME);"
   "WITH RECURSIVE r(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM r WHERE i < 300) INSERT INTO d SELECT 'u' || i, '2024-01-' || (i % 28), 'p' || (i % 7), i % 5, CASE WHEN i % 3 THEN NULL ELSE 'pt' || i END, 'rt' || (i * 7919 % 1000), CASE WHEN i % 4 = 0 THEN x'00ff' END, CASE i % 3 WHEN 0 THEN 1.5 WHEN 1 THEN i ELSE 'n' || i END FROM r;"
   "INSERT INTO u VALUES ('p0', 'a', 1), ('p1', 'b', '2020'), ('p3', NULL, 2.5), ('p6', 'g', NULL);",
   {"SELECT uuid, created, user, atype, push, tok, two, n FROM d WHERE (tok = 'rt' || 7919 % 1000) LIMIT 1", "SELECT * FROM d WHERE tok = 'rt123' LIMIT 3",
    "SELECT uuid, two, n FROM d WHERE atype = 2 AND push IS NOT NULL LIMIT 20", "SELECT tok, uuid FROM d WHERE tok > 'rt9' AND n IS NOT NULL LIMIT 50",
    "SELECT d.uuid, u.name, u.at FROM d JOIN u ON u.id = d.user WHERE d.atype = 1 AND u.at IS NOT NULL LIMIT 30",
    "SELECT d.uuid, d.n FROM u, d WHERE d.user = u.id AND d.created = '2024-01-3' AND u.name IS NOT NULL LIMIT 9",
    "SELECT count(*), max(created) FROM (SELECT created FROM d WHERE push IS NULL AND atype < 3 LIMIT 100)", "SELECT uuid FROM d WHERE tok = 'none' LIMIT 1", 0}},
#define CORRUPT_Q {"SELECT a, b FROM t", "SELECT a, b FROM t WHERE a = 7", "SELECT b FROM t WHERE rowid = 1", "SELECT count(b), sum(a) FROM t", "SELECT a FROM t ORDER BY b LIMIT 1", 0}
  {"turbo-lean (2026-10-27): a NULL type with a body byte left over (fields not ending at the payload's end): the specialised and loop plans returned rows, SQLite says malformed",
   "CREATE TABLE t(a INTEGER, b INTEGER); INSERT INTO t VALUES (7, 5), (2, 6);", CORRUPT_Q, 1, "\x03\x01\x01\x07\x05", "\x03\x01\x00\x07\x05"},
  {"turbo-lean (2026-10-27): a header size that is only itself, with a body",
   "CREATE TABLE t(a INTEGER, b INTEGER); INSERT INTO t VALUES (7, 5), (2, 6);", CORRUPT_Q, 1, "\x03\x01\x01\x07\x05", "\x01\x01\x01\x07\x05"},
  {"turbo-lean (2026-10-27): a type varint running past the header's end",
   "CREATE TABLE t(a INTEGER, b INTEGER); INSERT INTO t VALUES (7, 5), (2, 6);", CORRUPT_Q, 1, "\x03\x01\x01\x07\x05", "\x02\x81\x01\x07\x05"},
};
#define NCASE ((int)(sizeof CASES / sizeof CASES[0]))

static u64 hv(u64 h, int t, const void *z, int n, i64 iv, double rv) {
  h = (h ^ (unsigned)t) * 1099511628211ULL;
  if (t == SQLITE_INTEGER) { for (int k = 0; k < 8; k++) h = (h ^ ((u64)iv >> (8 * k) & 255)) * 1099511628211ULL; }
  else if (t == SQLITE_FLOAT) { u64 b; memcpy(&b, &rv, 8); for (int k = 0; k < 8; k++) h = (h ^ (b >> (8 * k) & 255)) * 1099511628211ULL; }
  else if (t == SQLITE_TEXT || t == SQLITE_BLOB) for (int k = 0; k < n; k++) h = (h ^ ((const u8 *)z)[k]) * 1099511628211ULL;
  return h;
}
typedef struct { u64 h; int rows; } Acc;
static int cb(void *ctx, int nrow, int ncol, const QcVal *v) {
  Acc *a = ctx; a->h = 1469598103934665603ULL; a->rows = nrow;
  for (int i = 0; i < nrow * ncol; i++) a->h = hv(a->h, v[i].type, v[i].z, v[i].n, v[i].i, v[i].r);
  return 0;
}
static void ex(sqlite3 *db, const char *q) { char *e = 0; if (sqlite3_exec(db, q, 0, 0, &e)) { fprintf(stderr, "regress: %s: %s\n", q, e); exit(2); } }
int main(void) {
  long cmp = 0, fell = 0, diffs = 0;
  for (int c = 0; c < NCASE; c++) {
    sqlite3 *db; const char *path = CASES[c].file ? "build/regress.db" : ":memory:";
    if (CASES[c].file) remove(path);
    if (sqlite3_open(path, &db) != SQLITE_OK) return 2;
    ex(db, CASES[c].setup);
    if (CASES[c].from) {   /* the corrupt record, written into page 2 through sqlite_dbpage */
      sqlite3_stmt *g; sqlite3_prepare_v2(db, "SELECT data FROM sqlite_dbpage WHERE pgno = 2", -1, &g, 0);
      if (sqlite3_step(g) != SQLITE_ROW) { fprintf(stderr, "regress: no page 2\n"); return 2; }
      int n = sqlite3_column_bytes(g, 0); unsigned char *pg = malloc((size_t)n); memcpy(pg, sqlite3_column_blob(g, 0), (size_t)n); sqlite3_finalize(g);
      int hit = 0; for (int i = 0; i + 5 <= n && !hit; i++) if (!memcmp(pg + i, CASES[c].from, 5)) { memcpy(pg + i, CASES[c].to, 5); hit = 1; }
      if (!hit) { fprintf(stderr, "regress: record not found in page 2\n"); return 2; }
      sqlite3_prepare_v2(db, "UPDATE sqlite_dbpage SET data = ?1 WHERE pgno = 2", -1, &g, 0); sqlite3_bind_blob(g, 1, pg, n, SQLITE_TRANSIENT);
      if (sqlite3_step(g) != SQLITE_DONE) { fprintf(stderr, "regress: dbpage write: %s\n", sqlite3_errmsg(db)); return 2; }
      sqlite3_finalize(g); free(pg);
      sqlite3_close(db); if (sqlite3_open(path, &db) != SQLITE_OK) return 2;   /* (a fresh connection: no cached page) */
    }
    for (int k = 0; CASES[c].q[k]; k++) {
      const char *q = CASES[c].q[k]; sqlite3_stmt *s, *p;
      if (sqlite3_prepare_v2(db, q, -1, &s, 0) || sqlite3_prepare_v2(db, q, -1, &p, 0)) { fprintf(stderr, "regress: prepare %s: %s\n", q, sqlite3_errmsg(db)); return 2; }
      int lifted = 0;
      for (int rep = 0; rep < 5; rep++) {   /* (runs 3 and 4 in autocommit: qc opens the read transaction itself) */
        int ac = rep >= 3; if (!ac) ex(db, "BEGIN"); int rc = QC_FALLBACK; Acc a = {0, -1}, b = {1469598103934665603ULL, 0};
        if (rep == 0) lifted = sqlite3_qc(s);
        if (lifted) rc = sqlite3_qc_exec(s, cb, &a);
        int irc;
        while ((irc = sqlite3_step(p)) == SQLITE_ROW) {
          b.rows++;
          for (int i = 0; i < sqlite3_column_count(p); i++) {
            int t = sqlite3_column_type(p, i);
            b.h = hv(b.h, t, t == SQLITE_TEXT ? (const void *)sqlite3_column_text(p, i) : sqlite3_column_blob(p, i), sqlite3_column_bytes(p, i),
                     sqlite3_column_int64(p, i), sqlite3_column_double(p, i));
          }
        }
        sqlite3_reset(p);
        if (ac) { if (!sqlite3_get_autocommit(db)) { diffs++; fprintf(stderr, "DIFF [%s]\n  %s: a transaction left open after an autocommit run\n", CASES[c].what, q); sqlite3_exec(db, "ROLLBACK", 0, 0, 0); } }
        else if (CASES[c].from) { sqlite3_exec(db, "COMMIT", 0, 0, 0); if (!sqlite3_get_autocommit(db)) sqlite3_exec(db, "ROLLBACK", 0, 0, 0); }   /* (a corruption error can end the transaction) */
        else ex(db, "COMMIT");
        if (rc != SQLITE_OK) { fell++; continue; }
        if (irc != SQLITE_DONE) { diffs++; fprintf(stderr, "DIFF [%s]\n  %s: qc returned %d rows, the interpreter an error (%d)\n", CASES[c].what, q, a.rows, irc); continue; }
        cmp++;
        if (a.h != b.h || a.rows != b.rows) { diffs++; fprintf(stderr, "DIFF [%s]\n  %s: qc %d rows, interpreter %d\n", CASES[c].what, q, a.rows, b.rows); }
      }
      sqlite3_finalize(s); sqlite3_finalize(p);
    }
    sqlite3_close(db);
    if (CASES[c].file) remove(path);
  }
  printf("regress: %d cases, %ld compared, %ld fell back, %ld differences\n", NCASE, cmp, fell, diffs);
  sqlite3_qc_release();
  return diffs ? 1 : 0;
}
