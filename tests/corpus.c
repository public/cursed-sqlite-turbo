// corpus <db> [executions] [filter]: common query flavours over the test schema. For each: does qc compile it (and
// if not, why), are its results the interpreter's (every value, over many parameter values), and how fast are both.
// Read-only: everything runs inside one transaction per batch of executions.
#include "sqlite3.c"
#include "qc.c"
#include <stdlib.h>
#include <time.h>

static double now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e9 + t.tv_nsec; }
static unsigned long long rng = 0x9E3779B97F4A7C15ULL;
static unsigned long long rnd(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }
static sqlite3 *db; static i64 NU, NP;

// parameters: 'p' a post id, 'P' a post id or a missing one, 'u' a user id, 'n' a username, 'k' a small count (limit),
// 'r' a post id range start (the end is +20), 't' a timestamp text, 'w' a word (LIKE pattern)
typedef struct { const char *name, *sql, *params; } Q;
static const Q QS[] = {
  {"pk point",                 "SELECT id, user_id, body, created_at FROM posts WHERE id = ?1", "P"},
  {"pk point, one column",     "SELECT body FROM posts WHERE id = ?1", "p"},
  {"unique index point",       "SELECT id, username, created_at FROM users WHERE username = ?1", "n"},
  {"pk range",                 "SELECT id, body FROM posts WHERE id BETWEEN ?1 AND ?1 + 20", "r"},
  {"pk range, order desc",     "SELECT id, body FROM posts WHERE id < ?1 ORDER BY id DESC LIMIT 20", "p"},
  {"pk IN list",               "SELECT id, body FROM posts WHERE id IN (?1, ?2, ?3, ?4, ?5)", "ppppp"},
  {"index eq, limit",          "SELECT id, body, created_at FROM posts WHERE user_id = ?1 ORDER BY id DESC LIMIT 10", "u"},
  {"index eq, all rows",       "SELECT id FROM posts WHERE user_id = ?1", "u"},
  {"index order, limit",       "SELECT id, created_at FROM posts ORDER BY created_at DESC, id DESC LIMIT 20", ""},
  {"index range text",         "SELECT id FROM posts WHERE created_at > ?1 ORDER BY created_at LIMIT 20", "t"},
  {"count by index eq",        "SELECT count(*) FROM likes WHERE post_id = ?1", "p"},
  {"count by pk range",        "SELECT count(*) FROM posts WHERE id BETWEEN ?1 AND ?1 + 20", "r"},
  {"exists by index",          "SELECT EXISTS (SELECT 1 FROM likes WHERE post_id = ?1 AND user_id = ?2)", "pu"},
  {"join 1-1 by pk",           "SELECT p.id, p.body, u.username FROM posts p JOIN users u ON u.id = p.user_id WHERE p.id = ?1", "P"},
  {"join 1-n via index",       "SELECT u.username, p.id, p.body FROM users u JOIN posts p ON p.user_id = u.id WHERE u.id = ?1 ORDER BY p.id DESC LIMIT 10", "u"},
  {"left join",                "SELECT p.id, u.username FROM posts p LEFT JOIN users u ON u.id = p.user_id WHERE p.id = ?1", "P"},
  {"feed (spec query)",        "SELECT p.id, p.body, p.created_at, u.username, (SELECT count(*) FROM likes l WHERE l.post_id = p.id) "
                               "FROM posts p JOIN users u ON u.id = p.user_id ORDER BY p.created_at DESC, p.id DESC LIMIT 20", ""},
  {"post with count",          "SELECT p.id, p.body, p.created_at, u.username, (SELECT count(*) FROM likes l WHERE l.post_id = p.id) "
                               "FROM posts p JOIN users u ON u.id = p.user_id WHERE p.id = ?1", "P"},
  {"user's posts + counts",    "SELECT p.id, (SELECT count(*) FROM likes l WHERE l.post_id = p.id) FROM posts p WHERE p.user_id = ?1 ORDER BY p.id DESC LIMIT 10", "u"},
  {"filter non-indexed",       "SELECT id FROM posts WHERE id > ?1 AND length(body) > 100 ORDER BY id LIMIT 10", "p"},
  {"filter LIKE",              "SELECT id FROM posts WHERE id > ?1 AND body LIKE ?2 ORDER BY id LIMIT 10", "pw"},
  {"projection expr",          "SELECT id, length(body), upper(substr(body, 1, 10)) FROM posts WHERE id = ?1", "p"},
  {"group by index",           "SELECT post_id, count(*) FROM likes WHERE post_id BETWEEN ?1 AND ?1 + 20 GROUP BY post_id", "r"},
  {"min/max by index",         "SELECT max(created_at) FROM posts WHERE user_id = ?1", "u"},
  {"likes of user",            "SELECT post_id, created_at FROM likes WHERE user_id = ?1 ORDER BY post_id LIMIT 20", "u"},
};
#define NQ (int)(sizeof QS / sizeof *QS)

static char **NAMES;   // every username, loaded once (binding must not cost a query)
static const char *WORDS[] = {"%alpha%", "%sqlite%", "%feed%", "b%", "%x%"};
static char txt[8][64];
static void bind_params(sqlite3_stmt *s, const char *ps) {
  for (int k = 0; ps[k]; k++) {
    int i = k + 1;
    switch (ps[k]) {
      case 'p': sqlite3_bind_int64(s, i, 1 + (i64)(rnd() % (u64)NP)); break;
      case 'P': sqlite3_bind_int64(s, i, rnd() % 8 ? 1 + (i64)(rnd() % (u64)NP) : NP + 1 + (i64)(rnd() % 10)); break;
      case 'u': sqlite3_bind_int64(s, i, 1 + (i64)(rnd() % (u64)NU)); break;
      case 'r': sqlite3_bind_int64(s, i, 1 + (i64)(rnd() % (u64)(NP - 25))); break;
      case 'k': sqlite3_bind_int64(s, i, 1 + (i64)(rnd() % 20)); break;
      case 'n': if (rnd() % 8) snprintf(txt[k], sizeof txt[k], "%s", NAMES[rnd() % (u64)NU]);   // a real name
                else snprintf(txt[k], sizeof txt[k], "user%05lld_", 1 + (long long)(rnd() % (u64)NU));   // a prefix: misses
                sqlite3_bind_text(s, i, txt[k], -1, SQLITE_TRANSIENT); break;
      case 't': snprintf(txt[k], sizeof txt[k], "2025-%02d-%02dT00:00:00.000Z", 1 + (int)(rnd() % 12), 1 + (int)(rnd() % 28));
                sqlite3_bind_text(s, i, txt[k], -1, SQLITE_TRANSIENT); break;
      case 'w': sqlite3_bind_text(s, i, WORDS[rnd() % 5], -1, SQLITE_STATIC); break;
    }
  }
}
// a row set as one hash (types and bytes of every value, in order) + the row count
static unsigned long long hval(unsigned long long h, int type, const void *z, int n, i64 iv, double rv) {
  h = (h ^ (unsigned)type) * 1099511628211ULL;
  if (type == SQLITE_INTEGER) { for (int k = 0; k < 8; k++) h = (h ^ ((u64)iv >> (8 * k) & 255)) * 1099511628211ULL; }
  else if (type == SQLITE_FLOAT) { u64 b; memcpy(&b, &rv, 8); for (int k = 0; k < 8; k++) h = (h ^ (b >> (8 * k) & 255)) * 1099511628211ULL; }
  else if (type == SQLITE_TEXT || type == SQLITE_BLOB) for (int k = 0; k < n; k++) h = (h ^ ((const u8 *)z)[k]) * 1099511628211ULL;
  return h;
}
static int interp_rows(sqlite3_stmt *s, unsigned long long *h) {
  int rows = 0, rc; *h = 1469598103934665603ULL;
  while ((rc = sqlite3_step(s)) == SQLITE_ROW) {
    rows++;
    for (int c = 0; c < sqlite3_column_count(s); c++) {
      int t = sqlite3_column_type(s, c);
      *h = hval(*h, t, t == SQLITE_TEXT ? (const void *)sqlite3_column_text(s, c) : sqlite3_column_blob(s, c), sqlite3_column_bytes(s, c),
                sqlite3_column_int64(s, c), sqlite3_column_double(s, c));
    }
  }
  sqlite3_reset(s);
  return rc == SQLITE_DONE ? rows : -1;
}
typedef struct { unsigned long long h; int rows; } Acc;
static volatile size_t sink;
/* timing consumers: what an application does with a row (type, pointer and length of each value), no hashing */
static void interp_touch(sqlite3_stmt *s) {
  size_t x = 0; int nc = sqlite3_column_count(s);
  while (sqlite3_step(s) == SQLITE_ROW) for (int c = 0; c < nc; c++) { x += (size_t)sqlite3_column_type(s, c); x += (size_t)sqlite3_column_bytes(s, c) + (size_t)(uintptr_t)sqlite3_column_text(s, c); }
  sqlite3_reset(s); sink += x;
}
static int qc_touch(void *ctx, int nrow, int ncol, const QcVal *v) { size_t x = 0; for (int i = 0; i < nrow * ncol; i++) x += (size_t)v[i].type + (size_t)v[i].n + (size_t)(uintptr_t)v[i].z; sink += x; (void)ctx; return 0; }
static int dump;
static int qc_cb(void *ctx, int nrow, int ncol, const QcVal *v) {
  Acc *a = ctx; a->h = 1469598103934665603ULL; a->rows = nrow;
  if (dump) for (int i = 0; i < nrow * ncol; i++) printf("    qc   [%d] type %d i %lld text %.*s\n", i, v[i].type, (long long)v[i].i, v[i].type == SQLITE_TEXT ? v[i].n : 0, v[i].type == SQLITE_TEXT ? (const char *)v[i].z : "");
  for (int i = 0; i < nrow * ncol; i++) a->h = hval(a->h, v[i].type, v[i].z, v[i].n, v[i].i, v[i].r);
  return 0;
}
static i64 one(const char *sql) { sqlite3_stmt *s; sqlite3_prepare_v2(db, sql, -1, &s, 0); sqlite3_step(s); i64 v = sqlite3_column_int64(s, 0); sqlite3_finalize(s); return v; }

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: corpus <db> [executions] [name-filter]\n"); return 2; }
  int N = argc > 2 ? atoi(argv[2]) : 20000; const char *filt = argc > 3 ? argv[3] : 0;
  if (sqlite3_open(argv[1], &db)) return 1;
  sqlite3_exec(db, "PRAGMA cache_size=-65536", 0, 0, 0);
  NU = one("SELECT max(id) FROM users"); NP = one("SELECT max(id) FROM posts");
  NAMES = calloc((size_t)NU, sizeof *NAMES);
  { sqlite3_stmt *q; sqlite3_prepare_v2(db, "SELECT id, username FROM users", -1, &q, 0);
    while (sqlite3_step(q) == SQLITE_ROW) { i64 id = sqlite3_column_int64(q, 0); if (id >= 1 && id <= NU) NAMES[id - 1] = strdup((const char *)sqlite3_column_text(q, 1)); }
    sqlite3_finalize(q); for (i64 k = 0; k < NU; k++) if (!NAMES[k]) NAMES[k] = "none"; }
  sqlite3_stmt *s_begin, *s_commit; sqlite3_prepare_v2(db, "BEGIN", -1, &s_begin, 0); sqlite3_prepare_v2(db, "COMMIT", -1, &s_commit, 0);
  int ncomp = 0, nq = 0, bad = 0;
  printf("| query | qc | equal / fallbacks | interp µs | qc µs | qc vs interp |\n|---|---|---:|---:|---:|---:|\n");
  for (int q = 0; q < NQ; q++) {
    if (filt && !strstr(QS[q].name, filt)) continue;
    nq++;
    sqlite3_stmt *a, *b;
    if (sqlite3_prepare_v3(db, QS[q].sql, -1, SQLITE_PREPARE_PERSISTENT, &a, 0) || sqlite3_prepare_v3(db, QS[q].sql, -1, SQLITE_PREPARE_PERSISTENT, &b, 0)) {
      printf("| %s | prepare: %s | | | | |\n", QS[q].name, sqlite3_errmsg(db)); continue;
    }
    qc_why = "";
    int ok = sqlite3_qc(b);
    if (!ok) { printf("| %s | no: %s | | | | |\n", QS[q].name, qc_why); sqlite3_finalize(a); sqlite3_finalize(b); continue; }
    ncomp++;
    // correctness: same parameters to both
    long eq = 0, fb = 0; unsigned long long saved = rng;
    sqlite3_exec(db, "BEGIN", 0, 0, 0);
    for (int i = 0; i < N; i++) {
      unsigned long long r0 = rng; bind_params(a, QS[q].params); rng = r0; bind_params(b, QS[q].params);
      unsigned long long ha; int ra = interp_rows(a, &ha);
      Acc ac = {0, 0}; int rc = sqlite3_qc_exec(b, qc_cb, &ac);
      if (rc == QC_FALLBACK) { fb++; if (getenv("QC_WHY") && fb < 3) printf("    fallback: %s\n", qc_why); unsigned long long hb; int rb = interp_rows(b, &hb); if (rb != ra || hb != ha) { bad++; printf("  MISMATCH (fallback path!) %s\n", QS[q].name); break; } continue; }
      if (ac.rows != ra || ac.h != ha) {
        bad++; printf("| %s | **MISMATCH** at execution %d: rows %d vs %d | | | | |\n", QS[q].name, i, ac.rows, ra);
        for (int k = 1; k <= sqlite3_bind_parameter_count(a); k++) { sqlite3_value *pv = ((Vdbe *)a)->aVar + k - 1; printf("    param %d = %s\n", k, sqlite3_value_text(pv)); }
        while (sqlite3_step(a) == SQLITE_ROW) for (int c = 0; c < sqlite3_column_count(a); c++) printf("    interp col %d type %d %s\n", c, sqlite3_column_type(a, c), sqlite3_column_text(a, c));
        sqlite3_reset(a); dump = 1; sqlite3_qc_exec(b, qc_cb, &ac); dump = 0;
        break;
      }
      eq++;
      if (i % 2000 == 1999) { sqlite3_exec(db, "COMMIT", 0, 0, 0); sqlite3_exec(db, "BEGIN", 0, 0, 0); }
    }
    sqlite3_exec(db, "COMMIT", 0, 0, 0);
    // speed: interleaved, 16 per transaction; the binding and transaction cost alone (m == 2) is subtracted from both
    double ti = 1e18, tq = 1e18, tb = 1e18; int it = 4000;
    for (int r = 0; r < 5; r++) for (int m = 0; m < 3; m++) {
      rng = saved; double t0 = now_ns();
      for (int i = 0; i < it; i += 16) {
        sqlite3_step(s_begin); sqlite3_reset(s_begin);
        for (int k = 0; k < 16; k++) {
          sqlite3_stmt *s = m == 1 ? b : a; bind_params(s, QS[q].params);
          if (m == 0) interp_touch(s);
          else if (m == 1 && sqlite3_qc_exec(s, qc_touch, 0) == QC_FALLBACK) interp_touch(s);
        }
        sqlite3_step(s_commit); sqlite3_reset(s_commit);
      }
      double d = (now_ns() - t0) / it / 1000; double *t = m == 0 ? &ti : m == 1 ? &tq : &tb; if (d < *t) *t = d;
    }
    ti -= tb; tq -= tb;
    printf("| %s | yes | %ld / %ld | %.3f | %.3f | %+.0f %% |\n", QS[q].name, eq, fb, ti, tq, 100 * (tq / ti - 1));
    sqlite3_finalize(a); sqlite3_finalize(b);
  }
  printf("\n%d of %d queries compiled; %d mismatches\n", ncomp, nq, bad);
  return bad != 0;
}
