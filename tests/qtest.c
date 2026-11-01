// qtest <work.db> [batches] [seed]: the query compiler against the interpreter, value by value.
// A and B are the same statement prepared twice on one connection; B is compiled (sqlite3_qc) and run through
// sqlite3_qc_exec, falling back to sqlite3_step when the plan says so. Checked: the feed (spec query) and GET /posts/:id
// for every id on the seed, after random write batches, and after writes the fast path must handle or refuse exactly:
// likes whose post_id is REAL (integral and not), TEXT or BLOB, a missing author, a TEXT user_id.
#ifndef QALL
#include "sqlite3.c"
#include "qc.c"
#if QC_STOCK   /* (stock SQLite: no hook frees a statement's plan with it) */
#define sqlite3_finalize sqlite3_qc_finalize
#endif
#endif
#include <stdlib.h>
static void die(const char *m) { fprintf(stderr, "FATAL: %s\n", m); exit(1); }
static unsigned long long rng = 0x9E3779B97F4A7C15ULL;
static unsigned long long rnd(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }
static const char *QF = "SELECT p.id, p.body, p.created_at, u.username, (SELECT count(*) FROM likes l WHERE l.post_id = p.id) AS like_count "
                        "FROM posts p JOIN users u ON u.id = p.user_id ORDER BY p.created_at DESC, p.id DESC LIMIT 20";
static const char *QG = "SELECT p.id, p.body, p.created_at, u.username, (SELECT count(*) FROM likes l WHERE l.post_id = p.id) AS like_count "
                        "FROM posts p JOIN users u ON u.id = p.user_id WHERE p.id = ?1";
static sqlite3 *db; static long ncmp, nfall, nqc, nddl; static const char *path;
typedef struct { int n, nc; QcVal v[QC_MAXROWS * QC_MAXOUT]; char *txt; size_t tn; } Rows;
static char tbuf[1 << 20];
static int collect(void *ctx, int nrow, int ncol, const QcVal *vals) {   // copy text out: pointers die after the callback
  Rows *r = ctx; r->n = nrow; r->nc = ncol; size_t off = 0;
  for (int i = 0; i < nrow * ncol; i++) {
    r->v[i] = vals[i];
    if (vals[i].type == SQLITE_TEXT || vals[i].type == SQLITE_BLOB) { memcpy(tbuf + off, vals[i].z, (size_t)vals[i].n); r->v[i].z = (u8 *)tbuf + off; off += (size_t)vals[i].n; }
  }
  return SQLITE_OK;
}
static void from_stmt(sqlite3_stmt *s, Rows *r) {   // the interpreter's rows in the same form
  static char sbuf[1 << 20]; size_t off = 0; r->n = 0; r->nc = sqlite3_column_count(s); int rc;
  while ((rc = sqlite3_step(s)) == SQLITE_ROW) {
    for (int c = 0; c < r->nc; c++) {
      QcVal *o = &r->v[r->n * r->nc + c]; o->type = sqlite3_column_type(s, c);
      if (o->type == SQLITE_INTEGER) o->i = sqlite3_column_int64(s, c);
      else if (o->type == SQLITE_FLOAT) o->r = sqlite3_column_double(s, c);
      else if (o->type != SQLITE_NULL) {
        const void *z = o->type == SQLITE_TEXT ? (const void *)sqlite3_column_text(s, c) : sqlite3_column_blob(s, c);
        o->n = sqlite3_column_bytes(s, c); memcpy(sbuf + off, z, (size_t)o->n); o->z = (u8 *)sbuf + off; off += (size_t)o->n;
      }
    }
    if (++r->n > QC_MAXROWS) die("too many rows");
  }
  if (rc != SQLITE_DONE) die(sqlite3_errmsg(db));
  sqlite3_reset(s);
}
static void same(const char *what, long id, Rows *a, Rows *b) {
  ncmp++;
  int ok = a->n == b->n && (a->n == 0 || a->nc == b->nc);
  for (int i = 0; ok && i < a->n * a->nc; i++) {
    QcVal *x = &a->v[i], *y = &b->v[i];
    ok = x->type == y->type && (x->type == SQLITE_INTEGER ? x->i == y->i : x->type == SQLITE_FLOAT ? x->r == y->r :
         x->type == SQLITE_NULL ? 1 : x->n == y->n && !memcmp(x->z, y->z, (size_t)x->n));
    if (!ok) fprintf(stderr, "  value %d: type %d/%d int %lld/%lld\n", i, x->type, y->type, (long long)x->i, (long long)y->i);
  }
  if (!ok) { fprintf(stderr, "MISMATCH %s id=%ld: rows %d/%d\n", what, id, a->n, b->n); exit(1); }
}
// the JSON path: B also writes the body from its template; it must equal a reference rendering of A's rows (or fall back
// exactly when a value is not what the template takes)
static const QcJson JF = {"{\"posts\":[", "]}", ",", 5, "isssi", {"{\"id\":", ",\"body\":", ",\"created_at\":", ",\"author\":", ",\"like_count\":", "}"}};
static const QcJson JG = {"{\"post\":", "}", ",", 5, "isssi", {"{\"id\":", ",\"body\":", ",\"created_at\":", ",\"author\":", ",\"like_count\":", "}"}};
static long njson, njfall;
static char jb[1 << 20], jr[1 << 20];
static size_t ref_json(const QcJson *j, Rows *a, int *ok) {
  char *p = jr; *ok = 1; p += sprintf(p, "%s", j->open);
  for (int i = 0; i < a->n; i++) {
    if (i) p += sprintf(p, "%s", j->sep);
    for (int k = 0; k < j->ncol; k++) {
      p += sprintf(p, "%s", j->frag[k]); QcVal *v = &a->v[i * a->nc + k];
      if (j->kind[k] == 'i') { if (v->type != SQLITE_INTEGER) *ok = 0; p += sprintf(p, "%lld", (long long)v->i); }
      else { if (v->type != SQLITE_TEXT) *ok = 0; *p++ = '"';
        for (int c = 0; c < v->n; c++) { unsigned ch = v->z[c];
          if (ch == '"' || ch == '\\') { *p++ = '\\'; *p++ = (char)ch; }
          else if (ch == '\b') p += sprintf(p, "\\b"); else if (ch == '\f') p += sprintf(p, "\\f"); else if (ch == '\n') p += sprintf(p, "\\n");
          else if (ch == '\r') p += sprintf(p, "\\r"); else if (ch == '\t') p += sprintf(p, "\\t");
          else if (ch < 0x20) p += sprintf(p, "\\u%04x", ch); else *p++ = (char)ch; }
        *p++ = '"'; }
    }
    p += sprintf(p, "%s", j->frag[j->ncol]);
  }
  p += sprintf(p, "%s", j->close); return (size_t)(p - jr);
}
static void check_json(sqlite3_stmt *b, const QcJson *j, Rows *a, const char *what, long id) {
  QcOut o = {jb, sizeof jb, 0, 0, 0, 0}; int ok; size_t rn = ref_json(j, a, &ok);
  int rc = sqlite3_qc_exec(b, 0, &o);
  if (rc == QC_FALLBACK) { njfall++; if (getenv("QC_WHY") && njfall < 4) fprintf(stderr, "json fallback: %s\n", qc_why); return; }
  njson++;
  if (!ok) { fprintf(stderr, "JSON %s id=%ld: written although a value is not what the template takes\n", what, id); exit(1); }
  if (rc != SQLITE_OK || o.rows != a->n || o.n != rn || memcmp(jb, jr, rn)) {
    fprintf(stderr, "JSON MISMATCH %s id=%ld rows %d/%d\n  qc:  %.300s\n  ref: %.300s\n", what, id, o.rows, a->n, jb, jr); exit(1); }
}
static void run_b(sqlite3_stmt *b, Rows *r) {
  int rc = sqlite3_qc_exec(b, collect, r);
  if (rc == QC_FALLBACK) { nfall++; if (getenv("QC_WHY") && nfall < 5) fprintf(stderr, "fallback: %s\n", qc_why); from_stmt(b, r); } else if (rc != SQLITE_OK) die("qc callback"); else nqc++;
}
static sqlite3_stmt *fa, *fb, *ga, *gb;
static void check_get(long id) { Rows ra, rb; sqlite3_bind_int64(ga, 1, id); sqlite3_bind_int64(gb, 1, id); from_stmt(ga, &ra); run_b(gb, &rb); same("get", id, &ra, &rb);
  check_json(gb, &JG, &ra, "get", id); }
static void check_feed(void) { Rows ra, rb; from_stmt(fa, &ra); run_b(fb, &rb); same("feed", 0, &ra, &rb); check_json(fb, &JF, &ra, "feed", 0); }
static long max_id(void) { sqlite3_stmt *s; sqlite3_prepare_v2(db, "SELECT max(id) FROM posts", -1, &s, 0); sqlite3_step(s); long m = sqlite3_column_int64(s, 0); sqlite3_finalize(s); return m; }
static void ex(const char *sql) { char *e = 0; if (sqlite3_exec(db, sql, 0, 0, &e)) { fprintf(stderr, "%s: %s\n", sql, e); exit(1); } }
int main(int argc, char **argv) {
  if (argc < 2) die("usage: qtest <work.db> [batches] [seed]");
  int batches = argc > 2 ? atoi(argv[2]) : 500; if (argc > 3) rng ^= strtoull(argv[3], 0, 0) * 0x2545F4914F6CDD1DULL;
  path = argv[1];
  if (sqlite3_open(argv[1], &db)) die("open");
  ex("PRAGMA foreign_keys=OFF");
  sqlite3_prepare_v3(db, QF, -1, SQLITE_PREPARE_PERSISTENT, &fa, 0); sqlite3_prepare_v3(db, QF, -1, SQLITE_PREPARE_PERSISTENT, &fb, 0);
  sqlite3_prepare_v3(db, QG, -1, SQLITE_PREPARE_PERSISTENT, &ga, 0); sqlite3_prepare_v3(db, QG, -1, SQLITE_PREPARE_PERSISTENT, &gb, 0);
  if (!sqlite3_qc(fb) || !sqlite3_qc(gb) || !sqlite3_qc_json(fb, &JF) || !sqlite3_qc_json(gb, &JG)) die("not compiled");
  printf("qtest: feed and get compiled\n");
  ex("BEGIN"); long m = max_id();
  for (long id = -1; id <= m + 2; id++) { check_get(id); if (id % 5000 == 0) { ex("COMMIT"); ex("BEGIN"); } }
  check_feed(); ex("COMMIT");
  printf("  seed: all ids -1..%ld and the feed equal (%ld compiled, %ld fallbacks)\n", m + 2, nqc, nfall);
  char sql[512];
  for (int b = 0; b < batches; b++) {
    ex("BEGIN"); m = max_id();
    int ops = 1 + (int)(rnd() % 20);
    for (int k = 0; k < ops; k++) {
      long uid = 1 + (long)(rnd() % 50000), pid = m - (long)(rnd() % 30);
      int r = (int)(rnd() % 100);
      if (r < 20) snprintf(sql, sizeof sql, "INSERT INTO posts(user_id, body, created_at) VALUES (%ld, 'b\"o\\dy %d' || char(%d) || printf('%%.*c', %d, 'x') || char(%d), strftime('%%Y-%%m-%%dT%%H:%%M:%%fZ','now'))",
                           uid, k, (int)(1 + rnd() % 31), (int)(rnd() % 40), (int)(rnd() % 3 ? 10 : 0x7f));
      else if (r < 90) snprintf(sql, sizeof sql, "INSERT OR IGNORE INTO likes(user_id, post_id, created_at) VALUES (%ld, %ld, 'x')", uid, pid);
      else if (r < 93) snprintf(sql, sizeof sql, "INSERT OR IGNORE INTO likes(user_id, post_id, created_at) VALUES (%ld, %ld.5, 'x')", uid, pid);     // REAL, never equal
      else if (r < 95) snprintf(sql, sizeof sql, "INSERT OR IGNORE INTO likes(user_id, post_id, created_at) VALUES (%ld, 'p%ld', 'x')", uid, pid);   // TEXT
      else if (r < 96) snprintf(sql, sizeof sql, "INSERT OR IGNORE INTO likes(user_id, post_id, created_at) VALUES (%ld, x'%02x', 'x')", uid, (int)(pid & 255));
      else if (r < 98) snprintf(sql, sizeof sql, "UPDATE posts SET user_id = %s WHERE id = %ld", rnd() % 2 ? "999999" : "'text'", pid);   // author missing / TEXT key
      else snprintf(sql, sizeof sql, "UPDATE posts SET body = NULL WHERE id = %ld", pid);   // NOT NULL is not checked by UPDATE? (it is: ignored on failure)
      char *e = 0; sqlite3_exec(db, sql, 0, 0, &e); sqlite3_free(e);
    }
    check_feed();
    if (b % 50 == 7) { ex("CREATE TABLE IF NOT EXISTS qc_tmp(x)"); check_feed(); check_get(m); ex("DROP TABLE qc_tmp"); }   // own DDL: expires
    for (long id = m - 25; id <= m + 1; id++) check_get(id);
    ex("COMMIT");
    if (b % 50 == 23) {   // another connection changes the schema between transactions: the cookie check must see it
      sqlite3 *d2; sqlite3_open(path, &d2); sqlite3_exec(d2, "CREATE INDEX IF NOT EXISTS qc_tmp_idx ON users(created_at); DROP INDEX qc_tmp_idx", 0, 0, 0); sqlite3_close(d2);
      ex("BEGIN"); check_feed(); check_get(max_id()); ex("COMMIT"); nddl++;
    }
  }
  printf("  %d write batches: feed and newest posts equal after each (%ld compiled, %ld fallbacks; own DDL every 50, %ld schema changes from a second connection)\n", batches, nqc, nfall, nddl);
  ex("BEGIN"); m = max_id(); for (long id = 1; id <= m; id++) check_get(id); ex("COMMIT");
  printf("OK: %ld comparisons, %ld compiled executions, %ld fallbacks; JSON bodies: %ld equal, %ld fallbacks\n", ncmp, nqc, nfall, njson, njfall);
  return 0;
}
