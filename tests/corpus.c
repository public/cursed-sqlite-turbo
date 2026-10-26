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
  {"group by, having",         "SELECT post_id, count(*) FROM likes WHERE post_id BETWEEN ?1 AND ?1 + 50 GROUP BY post_id HAVING count(*) > 4", "r"},
  {"group by, bare col, limit","SELECT user_id, count(*), max(created_at), body FROM posts WHERE user_id BETWEEN ?1 AND ?1 + 20 GROUP BY user_id LIMIT 5", "u"},
  {"order by, top-n",          "SELECT id, body FROM posts WHERE user_id = ?1 ORDER BY created_at LIMIT 3", "u"},
  {"order by desc, sorter",    "SELECT id, created_at FROM posts WHERE user_id = ?1 ORDER BY created_at DESC", "u"},
  {"order by, ties (sorter)",  "SELECT user_id, post_id FROM likes WHERE post_id = ?1 ORDER BY length(created_at)", "p"},
  {"order by, ties (top-n)",   "SELECT user_id, post_id FROM likes WHERE post_id = ?1 ORDER BY length(created_at) LIMIT 3", "p"},
  {"order by, join",           "SELECT u.username, p.id FROM posts p JOIN users u ON u.id = p.user_id WHERE p.user_id = ?1 ORDER BY p.created_at, p.id", "u"},
  {"union all",                "SELECT id FROM posts WHERE user_id = ?1 UNION ALL SELECT post_id FROM likes WHERE user_id = ?1", "u"},
  {"union",                    "SELECT id FROM posts WHERE user_id = ?1 UNION SELECT post_id FROM likes WHERE user_id = ?1", "u"},
  {"intersect",                "SELECT post_id FROM likes WHERE user_id = ?1 INTERSECT SELECT post_id FROM likes WHERE user_id = ?2", "uu"},
  {"except",                   "SELECT post_id FROM likes WHERE user_id = ?1 EXCEPT SELECT post_id FROM likes WHERE user_id = ?2", "uu"},
  {"cte, flattened",           "WITH t AS (SELECT id, user_id FROM posts WHERE user_id = ?1) SELECT t.id, u.username FROM t JOIN users u ON u.id = t.user_id", "u"},
  {"cte, materialized",        "WITH t AS MATERIALIZED (SELECT user_id, count(*) AS c FROM posts WHERE user_id BETWEEN ?1 AND ?1 + 5 GROUP BY user_id) SELECT user_id, c FROM t WHERE c > 1", "u"},
  {"subquery in FROM",         "SELECT x.c FROM (SELECT user_id, count(*) AS c FROM posts WHERE user_id BETWEEN ?1 AND ?1 + 5 GROUP BY user_id) x WHERE x.c > 2", "u"},
  {"recursive cte, counter",   "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < ?1) SELECT x FROM n", "k"},
  {"recursive cte, walk",      "WITH RECURSIVE c(id, n) AS (SELECT ?1, 0 UNION ALL SELECT p.id + 1, c.n + 1 FROM c JOIN posts p ON p.id = c.id WHERE c.n < 5) SELECT id, n FROM c", "p"},
  {"window row_number",        "SELECT id, row_number() OVER (ORDER BY id) FROM posts WHERE user_id = ?1", "u"},
  {"window rank, partition",   "SELECT id, user_id, rank() OVER (PARTITION BY user_id ORDER BY created_at) FROM posts WHERE user_id BETWEEN ?1 AND ?1 + 3", "u"},
  {"window sum, rows frame",   "SELECT id, sum(length(body)) OVER (PARTITION BY user_id ORDER BY id ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) FROM posts WHERE user_id BETWEEN ?1 AND ?1 + 3", "u"},
  {"window lag/lead",          "SELECT id, lag(id) OVER (ORDER BY id), lead(id, 2) OVER (ORDER BY id) FROM posts WHERE user_id = ?1", "u"},
  {"window count over ()",     "SELECT user_id, count(*) OVER () FROM likes WHERE post_id = ?1", "p"},
  {"window avg, range frame",  "SELECT id, avg(length(body)) OVER (ORDER BY id RANGE BETWEEN 3 PRECEDING AND 3 FOLLOWING) FROM posts WHERE id BETWEEN ?1 AND ?1 + 20", "r"},
  {"window dense_rank/ntile",  "SELECT id, dense_rank() OVER (ORDER BY length(body) / 50), ntile(3) OVER (ORDER BY id), first_value(id) OVER (ORDER BY id DESC) FROM posts WHERE user_id BETWEEN ?1 AND ?1 + 2", "u"},
  {"distinct",                 "SELECT DISTINCT user_id FROM likes WHERE post_id BETWEEN ?1 AND ?1 + 20", "r"},
  {"in (subselect)",           "SELECT id FROM posts WHERE user_id IN (SELECT user_id FROM likes WHERE post_id = ?1) ORDER BY id LIMIT 20", "p"},
  {"scalar subquery max",      "SELECT u.username, (SELECT max(created_at) FROM posts WHERE user_id = u.id) FROM users u WHERE u.id = ?1", "u"},
  {"not exists",               "SELECT id FROM posts p WHERE user_id = ?1 AND NOT EXISTS (SELECT 1 FROM likes l WHERE l.post_id = p.id)", "u"},
  {"group by, sorter",         "SELECT length(body) % 10, count(*) FROM posts WHERE user_id BETWEEN ?1 AND ?1 + 50 GROUP BY 1", "u"},
  {"count distinct",           "SELECT count(DISTINCT user_id) FROM likes WHERE post_id BETWEEN ?1 AND ?1 + 20", "r"},
  {"case expression",          "SELECT id, CASE WHEN length(body) > 100 THEN 'long' WHEN length(body) > 50 THEN 'mid' ELSE 'short' END FROM posts WHERE id BETWEEN ?1 AND ?1 + 20", "r"},
  {"limit offset",             "SELECT id FROM posts WHERE user_id = ?1 ORDER BY id LIMIT 3 OFFSET 1", "u"},
  {"left join, coalesce",      "SELECT p.id, coalesce(u.username, '?') FROM posts p LEFT JOIN users u ON u.id = p.user_id + ?2 WHERE p.id = ?1", "pk"},
  {"arithmetic",               "SELECT id, id * 2 + 1, id / 3, id % 7, -id, id << 2, id & 255 FROM posts WHERE id BETWEEN ?1 AND ?1 + 10", "r"},
  {"concat",                   "SELECT username || '@' || id FROM users WHERE id = ?1", "u"},
  {"avg/sum/total",            "SELECT avg(length(body)), sum(user_id), total(id), count(body) FROM posts WHERE user_id = ?1", "u"},
  {"group_concat",             "SELECT group_concat(post_id, ',') FROM likes WHERE user_id = ?1", "u"},
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
static char last_rows[1 << 16]; static size_t last_n;   /* the last qc result, as text, for a mismatch report */
static int qc_cb(void *ctx, int nrow, int ncol, const QcVal *v) {
  Acc *a = ctx; a->h = 1469598103934665603ULL; a->rows = nrow;
  last_n = 0;
  for (int i = 0; i < nrow * ncol && last_n + 96 < sizeof last_rows; i++)
    last_n += (size_t)snprintf(last_rows + last_n, sizeof last_rows - last_n, "    qc   [%d] type %d i %lld text %.*s\n", i, v[i].type, (long long)v[i].i,
                              v[i].type == SQLITE_TEXT ? (v[i].n < 40 ? v[i].n : 40) : 0, v[i].type == SQLITE_TEXT ? (const char *)v[i].z : "");
  if (dump) for (int i = 0; i < nrow * ncol; i++) printf("    qc   [%d] type %d i %lld text %.*s\n", i, v[i].type, (long long)v[i].i, v[i].type == SQLITE_TEXT ? v[i].n : 0, v[i].type == SQLITE_TEXT ? (const char *)v[i].z : "");
  for (int i = 0; i < nrow * ncol; i++) a->h = hval(a->h, v[i].type, v[i].z, v[i].n, v[i].i, v[i].r);
  return 0;
}
#ifdef QV_TRACE   /* debugging builds: on a crash, which query and where in qvm */
#include <signal.h>
#include <execinfo.h>
static const char *cur_query = "";
static void on_crash(int sig) {
  fprintf(stderr, "\nCRASH signal %d in query \"%s\" at qvm pc %d op %s\n", sig, cur_query, qv_trace_pc, qv_trace_op >= 0 ? sqlite3OpcodeName(qv_trace_op) : "-");
  void *bt[48]; int n = backtrace(bt, 48); backtrace_symbols_fd(bt, n, 2); _exit(3);
}
#endif
static i64 one(const char *sql) { sqlite3_stmt *s; sqlite3_prepare_v2(db, sql, -1, &s, 0); sqlite3_step(s); i64 v = sqlite3_column_int64(s, 0); sqlite3_finalize(s); return v; }

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: corpus <db> [executions] [name-filter]\n"); return 2; }
  setvbuf(stdout, 0, _IOLBF, 0);   /* a row per query as it finishes, even if the run is cut short */
#ifdef QV_TRACE
  signal(SIGSEGV, on_crash); signal(SIGBUS, on_crash); signal(SIGABRT, on_crash); signal(SIGFPE, on_crash);
#endif
  int N = argc > 2 ? atoi(argv[2]) : 20000; const char *filt = argc > 3 ? argv[3] : 0;
  if (sqlite3_open(argv[1], &db)) return 1;
  if (getenv("QC_QPSG")) sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_QPSG, 1, (int *)0);   /* plans that never look at bound values: no re-prepare at lift */
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
    if (q < (getenv("QSKIP") ? atoi(getenv("QSKIP")) : 0)) continue;   /* resume a run cut short */
    nq++;
#ifdef QV_TRACE
    cur_query = QS[q].name; fprintf(stderr, "> %s\n", cur_query);
#endif
    sqlite3_stmt *a, *b;
    if (sqlite3_prepare_v3(db, QS[q].sql, -1, SQLITE_PREPARE_PERSISTENT, &a, 0) || sqlite3_prepare_v3(db, QS[q].sql, -1, SQLITE_PREPARE_PERSISTENT, &b, 0)) {
      printf("| %s | prepare: %s | | | | |\n", QS[q].name, sqlite3_errmsg(db)); continue;
    }
    qc_why = "";
    int ok = sqlite3_qc(b);
    if (!ok) { printf("| %s | no: %s | | | | |\n", QS[q].name, qc_why); sqlite3_finalize(a); sqlite3_finalize(b); continue; }
    ncomp++;
    static const char *KIND[] = {"", "yes (plan)", "yes (loops)", "yes (vm)"};
    const char *kind = KIND[*(int *)((Vdbe *)b)->pQc & 3];
    if (getenv("QAB")) {   /* A/B: interpreter and qc alternately, QAB rounds of 200 ms each; the median ratio of executions */
      int rounds = atoi(getenv("QAB")); double ratio[64]; int nr = 0;
      for (int r = 0; r < rounds && r < 64; r++) {
        long cnt[2] = {0, 0};
        for (int side = 0; side < 2; side++) {
          double end = now_ns() + 0.2e9;
          while (now_ns() < end) {
            sqlite3_step(s_begin); sqlite3_reset(s_begin);
            for (int k = 0; k < 16; k++, cnt[side]++) {
              sqlite3_stmt *s = side ? b : a; bind_params(s, QS[q].params);
              if (!side || sqlite3_qc_exec(s, qc_touch, 0) == QC_FALLBACK) interp_touch(s);
            }
            sqlite3_step(s_commit); sqlite3_reset(s_commit);
          }
        }
        ratio[nr++] = (double)cnt[0] / (double)cnt[1];   /* qc time / interpreter time */
      }
      for (int i = 1; i < nr; i++) for (int j = i; j > 0 && ratio[j - 1] > ratio[j]; j--) { double t = ratio[j]; ratio[j] = ratio[j - 1]; ratio[j - 1] = t; }
      printf("| %s | %s | A/B %d rounds | qc vs interp median %+.1f %% (min %+.1f, max %+.1f) |\n", QS[q].name, kind, nr,
             100 * (ratio[nr / 2] - 1), 100 * (ratio[0] - 1), 100 * (ratio[nr - 1] - 1));
      sqlite3_finalize(a); sqlite3_finalize(b); continue;
    }
    if (getenv("QONESHOT")) {   /* one-shot statements (an ORM's prepare, run, finalize): this query alone, QONESHOT seconds
                                   each way, alternated; qc through the plan cache (QC_NOCACHE=1: a lift every time) */
      double sec = atof(getenv("QONESHOT")); double t[2] = {0, 0}, part[2][4] = {{0}}; long n[2] = {0, 0};
      for (int round = 0; round < 6; round++) for (int way = 0; way < 2; way++) {
        double t0 = now_ns(), end = t0 + sec / 6 * 1e9;
        while (now_ns() < end) {
          sqlite3_exec(db, "BEGIN", 0, 0, 0);
          for (int k = 0; k < 16; k++, n[way]++) {
            double c0 = now_ns(); sqlite3_stmt *s; sqlite3_prepare_v2(db, QS[q].sql, -1, &s, 0); bind_params(s, QS[q].params);
            double c1 = now_ns(); int lifted = way && sqlite3_qc(s); double c2 = now_ns();
            if (!lifted || sqlite3_qc_exec(s, qc_touch, 0) == QC_FALLBACK) interp_touch(s);
            double c3 = now_ns(); sqlite3_finalize(s); double c4 = now_ns();
            part[way][0] += c1 - c0; part[way][1] += c2 - c1; part[way][2] += c3 - c2; part[way][3] += c4 - c3;
          }
          sqlite3_exec(db, "COMMIT", 0, 0, 0);
        }
        t[way] += now_ns() - t0;
      }
      fprintf(stderr, "%s: one-shot interpreter %.3f us, qc %.3f us (%+.0f %%); cache %llu hits\n", QS[q].name, t[0] / 1e3 / (double)n[0],
              t[1] / 1e3 / (double)n[1], 100.0 * (t[1] / (double)n[1]) / (t[0] / (double)n[0]) - 100.0, 
#ifdef QC_CACHE_PLANS
              (unsigned long long)qv_cache_hits);
#else
              0ULL);   /* (a qc without the plan cache) */
#endif
      for (int w = 0; w < 2; w++) fprintf(stderr, "  %s: prepare %.3f, sqlite3_qc %.3f, run %.3f, finalize %.3f us\n", w ? "qc" : "interpreter",
              part[w][0] / 1e3 / (double)n[w], part[w][1] / 1e3 / (double)n[w], part[w][2] / 1e3 / (double)n[w], part[w][3] / 1e3 / (double)n[w]);
      sqlite3_finalize(a); sqlite3_finalize(b); continue;
    }
    if (getenv("QLOOP")) {   /* profiling: this query alone, qc (or QLOOP_INTERP=1: the interpreter), for QLOOP seconds */
      double end = now_ns() + atof(getenv("QLOOP")) * 1e9; long n = 0; int interp = getenv("QLOOP_INTERP") != 0;
      while (now_ns() < end) {
        sqlite3_exec(db, "BEGIN", 0, 0, 0);
        for (int k = 0; k < 16; k++, n++) {
          sqlite3_stmt *s = interp ? a : b; bind_params(s, QS[q].params);
          if (interp || sqlite3_qc_exec(s, qc_touch, 0) == QC_FALLBACK) interp_touch(s);
        }
        sqlite3_exec(db, "COMMIT", 0, 0, 0);
      }
      fprintf(stderr, "%s: %ld executions\n", QS[q].name, n);
      sqlite3_finalize(a); sqlite3_finalize(b); continue;
    }
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
        sqlite3_reset(a); printf("  (qc rows of the mismatching run:)\n%.*s", (int)last_n, last_rows);
        break;
      }
      eq++;
      if (i % 2000 == 1999) { sqlite3_exec(db, "COMMIT", 0, 0, 0); sqlite3_exec(db, "BEGIN", 0, 0, 0); }
    }
    sqlite3_exec(db, "COMMIT", 0, 0, 0);
    if (getenv("QFB")) qv_fb_dump((Vdbe *)b, stdout);
    // speed: interleaved, 16 per transaction; the binding and transaction cost alone (m == 2) is subtracted from both
    double ti = 1e18, tq = 1e18, tb = 1e18; int it = 16;
    {   /* iterations for ~50 ms per round and mode, from a first measurement of the interpreter */
      rng = saved; double t0 = now_ns();
      sqlite3_step(s_begin); sqlite3_reset(s_begin);
      for (int k = 0; k < 16; k++) { bind_params(a, QS[q].params); interp_touch(a); }
      sqlite3_step(s_commit); sqlite3_reset(s_commit);
      double us = (now_ns() - t0) / 16 / 1000; it = us > 0 ? (int)(50000 / us) : 4000;
      it = it < 16 ? 16 : it > 4000 ? 4000 : it; it = it / 16 * 16;
    }
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
    printf("| %s | %s | %ld / %ld | %.3f | %.3f | %+.0f %% |\n", QS[q].name, kind, eq, fb, ti, tq, 100 * (tq / ti - 1));
    sqlite3_finalize(a); sqlite3_finalize(b);
  }
  printf("\n%d of %d queries compiled; %d mismatches\n", ncomp, nq, bad);
  return bad != 0;
}
