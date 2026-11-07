// turbo_bench: Google Benchmark (CodSpeed's) over turbo's statements, through SQLite's plain API: prepare, bind, step,
// column_*, reset. Every statement runs twice, on the same database and the same parameters:
//   .../interpreter   SQLite's own bytecode interpreter (turbo off)
//   .../turbo         turbo serving the statement inside sqlite3_step (qc -> qcg -> qvm)
// Groups:
//   BM_Prepared   prepared once, run repeatedly (turbo's target workload), one batch of executions per iteration
//   BM_Oneshot    prepared, run and finalized on every execution (plan cache across prepares)
// The database is scripts/gen-db.py's social-feed schema (users, posts, likes), copied into memory so no I/O is timed.
// TURBO_BENCH_DB names it (default: the one CMake generates).
#include <benchmark/benchmark.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "sqlite3.h"

extern "C" {
void turbo_bench_init(void);
void turbo_bench_serve(int on);
long long turbo_bench_runs(void);
}

#ifndef TURBO_BENCH_DB
#define TURBO_BENCH_DB "turbo_bench.db"
#endif

namespace {

// parameters: 'p' a post id, 'u' a user id, 'r' a post id range start (the end is +20), 'k' a small count, 'w' a LIKE pattern
struct Query {
  const char *name, *sql, *params;
};

const Query QUERIES[] = {
    {"pk_point", "SELECT id, user_id, body, created_at FROM posts WHERE id = ?1", "p"},
    {"feed", "SELECT p.id, p.body, p.created_at, u.username, (SELECT count(*) FROM likes l WHERE l.post_id = p.id) "
             "FROM posts p JOIN users u ON u.id = p.user_id ORDER BY p.created_at DESC, p.id DESC LIMIT 20", ""},
    {"post_with_count", "SELECT p.id, p.body, p.created_at, u.username, (SELECT count(*) FROM likes l WHERE l.post_id = p.id) "
                        "FROM posts p JOIN users u ON u.id = p.user_id WHERE p.id = ?1", "p"},
    {"user_posts_counts", "SELECT p.id, (SELECT count(*) FROM likes l WHERE l.post_id = p.id) FROM posts p "
                          "WHERE p.user_id = ?1 ORDER BY p.id DESC LIMIT 10", "u"},
    {"join_1n_index", "SELECT u.username, p.id, p.body FROM users u JOIN posts p ON p.user_id = u.id WHERE u.id = ?1 "
                      "ORDER BY p.id DESC LIMIT 10", "u"},
    {"filter_like", "SELECT id FROM posts WHERE id > ?1 AND body LIKE ?2 ORDER BY id LIMIT 10", "pw"},
    {"projection_expr", "SELECT id, length(body), upper(substr(body, 1, 10)), CASE WHEN length(body) > 100 THEN 'long' "
                        "ELSE 'short' END FROM posts WHERE id BETWEEN ?1 AND ?1 + 20", "r"},
    {"group_by_index", "SELECT post_id, count(*) FROM likes WHERE post_id BETWEEN ?1 AND ?1 + 50 GROUP BY post_id "
                       "HAVING count(*) > 1", "r"},
    {"group_by_sorter", "SELECT length(body) % 10, count(*), avg(length(body)) FROM posts "
                        "WHERE user_id BETWEEN ?1 AND ?1 + 50 GROUP BY 1", "u"},
    {"order_by_sorter", "SELECT id, created_at FROM posts WHERE user_id BETWEEN ?1 AND ?1 + 10 ORDER BY created_at DESC", "u"},
    {"distinct", "SELECT DISTINCT user_id FROM likes WHERE post_id BETWEEN ?1 AND ?1 + 20", "r"},
    {"union", "SELECT id FROM posts WHERE user_id = ?1 UNION SELECT post_id FROM likes WHERE user_id = ?1", "u"},
    {"intersect", "SELECT post_id FROM likes WHERE user_id BETWEEN ?1 AND ?1 + 20 "
                  "INTERSECT SELECT post_id FROM likes WHERE user_id BETWEEN ?1 + 10 AND ?1 + 40", "u"},
    {"cte_materialized", "WITH t AS MATERIALIZED (SELECT user_id, count(*) AS c FROM posts WHERE user_id BETWEEN ?1 AND ?1 + 20 "
                         "GROUP BY user_id) SELECT user_id, c FROM t WHERE c > 1", "u"},
    {"recursive_cte", "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < ?1 + 100) "
                      "SELECT x, x * x FROM n", "k"},
    {"window_rank", "SELECT id, user_id, rank() OVER (PARTITION BY user_id ORDER BY created_at) FROM posts "
                    "WHERE user_id BETWEEN ?1 AND ?1 + 10", "u"},
    {"window_sum_frame", "SELECT id, sum(length(body)) OVER (PARTITION BY user_id ORDER BY id ROWS BETWEEN 1 PRECEDING "
                         "AND CURRENT ROW) FROM posts WHERE user_id BETWEEN ?1 AND ?1 + 10", "u"},
    {"in_subselect", "SELECT id FROM posts WHERE user_id IN (SELECT user_id FROM likes WHERE post_id = ?1) ORDER BY id LIMIT 20", "p"},
    {"not_exists", "SELECT id FROM posts p WHERE user_id BETWEEN ?1 AND ?1 + 5 "
                   "AND NOT EXISTS (SELECT 1 FROM likes l WHERE l.post_id = p.id)", "u"},
};
constexpr int NQUERIES = sizeof QUERIES / sizeof *QUERIES;
constexpr int BATCH = 16;   // executions per benchmark iteration, inside one read transaction
const char *WORDS[] = {"%alpha%", "%sqlite%", "%feed%", "b%", "%x%"};

sqlite3 *g_db;
int64_t g_nusers, g_nposts;

void die(const char *what) {
  std::fprintf(stderr, "turbo_bench: %s: %s\n", what, g_db ? sqlite3_errmsg(g_db) : "");
  std::exit(1);
}

int64_t count_of(const char *sql) {
  sqlite3_stmt *s;
  if (sqlite3_prepare_v2(g_db, sql, -1, &s, nullptr) != SQLITE_OK) die(sql);
  int64_t n = sqlite3_step(s) == SQLITE_ROW ? sqlite3_column_int64(s, 0) : 0;
  sqlite3_finalize(s);
  return n;
}

// the database, from its file into memory (the backup API), opened once for every benchmark
void open_db() {
  if (g_db) return;
  turbo_bench_init();
  const char *path = std::getenv("TURBO_BENCH_DB");
  if (!path || !*path) path = TURBO_BENCH_DB;
  sqlite3 *file;
  if (sqlite3_open_v2(path, &file, SQLITE_OPEN_READONLY, nullptr) != SQLITE_OK) {
    std::fprintf(stderr, "turbo_bench: cannot open %s (scripts/gen-db.py makes it)\n", path);
    std::exit(1);
  }
  if (sqlite3_open(":memory:", &g_db) != SQLITE_OK) die("open :memory:");
  sqlite3_backup *b = sqlite3_backup_init(g_db, "main", file, "main");
  if (!b || sqlite3_backup_step(b, -1) != SQLITE_DONE) die("backup");
  sqlite3_backup_finish(b);
  sqlite3_close(file);
  g_nusers = count_of("SELECT max(id) FROM users");
  g_nposts = count_of("SELECT max(id) FROM posts");
  if (g_nusers < 100 || g_nposts < 100) die("the database is too small");
}

// the parameters of a batch's executions: fixed (a deterministic sequence), the same for both modes
struct Params {
  int64_t ints[BATCH][2] = {};
  const char *word[BATCH];
};

Params make_params(const char *ps) {
  Params P;
  uint64_t rs = 88172645463325252ULL;
  auto rnd = [&rs] { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; };
  for (int k = 0; k < BATCH; k++) {
    P.word[k] = WORDS[k % 5];
    for (int i = 0; ps[i] && i < 2; i++) {
      int64_t v = 0;
      switch (ps[i]) {
        case 'p': v = 1 + (int64_t)(rnd() % (uint64_t)g_nposts); break;
        case 'u': v = 1 + (int64_t)(rnd() % (uint64_t)(g_nusers - 50)); break;
        case 'r': v = 1 + (int64_t)(rnd() % (uint64_t)(g_nposts - 60)); break;
        case 'k': v = 1 + (int64_t)(rnd() % 20); break;
        default: break;
      }
      P.ints[k][i] = v;
    }
  }
  return P;
}

void bind(sqlite3_stmt *s, const char *ps, const Params &P, int k) {
  for (int i = 0; ps[i]; i++) {
    if (ps[i] == 'w') sqlite3_bind_text(s, i + 1, P.word[k], -1, SQLITE_STATIC);
    else sqlite3_bind_int64(s, i + 1, P.ints[k][i]);
  }
}

// what an application does with a row: every value's type, bytes and text
int64_t consume(sqlite3_stmt *s) {
  int64_t x = 0;
  int nc = sqlite3_column_count(s), rc;
  while ((rc = sqlite3_step(s)) == SQLITE_ROW)
    for (int c = 0; c < nc; c++) {
      x += sqlite3_column_type(s, c);
      const unsigned char *t = sqlite3_column_text(s, c);
      x += sqlite3_column_bytes(s, c) + (t ? t[0] : 0);
    }
  if (rc != SQLITE_DONE) die("step");
  sqlite3_reset(s);
  return x;
}

void exec(const char *sql) {
  if (sqlite3_exec(g_db, sql, nullptr, nullptr, nullptr) != SQLITE_OK) die(sql);
}

// prepared once, run BATCH times per iteration (after a warm-up: turbo lifts a statement on its first executions)
void BM_Prepared(benchmark::State &state, const Query *q, bool turbo) {
  open_db();
  turbo_bench_serve(turbo);
  Params P = make_params(q->params);
  sqlite3_stmt *s;
  if (sqlite3_prepare_v3(g_db, q->sql, -1, SQLITE_PREPARE_PERSISTENT, &s, nullptr) != SQLITE_OK) die(q->sql);
  for (int w = 0; w < 4; w++) {
    exec("BEGIN");
    for (int k = 0; k < BATCH; k++) { bind(s, q->params, P, k); benchmark::DoNotOptimize(consume(s)); }
    exec("COMMIT");
  }
  long long runs0 = turbo_bench_runs();
  for (auto _ : state) {
    exec("BEGIN");
    for (int k = 0; k < BATCH; k++) { bind(s, q->params, P, k); benchmark::DoNotOptimize(consume(s)); }
    exec("COMMIT");
  }
  state.counters["served"] = benchmark::Counter((double)(turbo_bench_runs() - runs0) / ((double)state.iterations() * BATCH));
  sqlite3_finalize(s);
  turbo_bench_serve(1);
}

// prepared, run and finalized on every execution (an ORM's or a script's pattern: the plan cache across prepares)
void BM_Oneshot(benchmark::State &state, const Query *q, bool turbo) {
  open_db();
  turbo_bench_serve(turbo);
  Params P = make_params(q->params);
  auto batch = [&] {
    exec("BEGIN");
    for (int k = 0; k < BATCH; k++) {
      sqlite3_stmt *s;
      if (sqlite3_prepare_v2(g_db, q->sql, -1, &s, nullptr) != SQLITE_OK) die(q->sql);
      bind(s, q->params, P, k);
      benchmark::DoNotOptimize(consume(s));
      sqlite3_finalize(s);
    }
    exec("COMMIT");
  };
  for (int w = 0; w < 4; w++) batch();
  for (auto _ : state) batch();
  turbo_bench_serve(1);
}

const Query *find(const char *name) {
  for (const Query &q : QUERIES)
    if (std::strcmp(q.name, name) == 0) return &q;
  std::fprintf(stderr, "turbo_bench: no query %s\n", name);
  std::exit(1);
}

}  // namespace

// each query twice: SQLite's interpreter, then turbo serving it
#define PAIR(fn, q)                                                \
  BENCHMARK_CAPTURE(fn, q/interpreter, find(#q), false);           \
  BENCHMARK_CAPTURE(fn, q/turbo, find(#q), true)

PAIR(BM_Prepared, pk_point);
PAIR(BM_Prepared, feed);
PAIR(BM_Prepared, post_with_count);
PAIR(BM_Prepared, user_posts_counts);
PAIR(BM_Prepared, join_1n_index);
PAIR(BM_Prepared, filter_like);
PAIR(BM_Prepared, projection_expr);
PAIR(BM_Prepared, group_by_index);
PAIR(BM_Prepared, group_by_sorter);
PAIR(BM_Prepared, order_by_sorter);
PAIR(BM_Prepared, distinct);
PAIR(BM_Prepared, union);
PAIR(BM_Prepared, intersect);
PAIR(BM_Prepared, cte_materialized);
PAIR(BM_Prepared, recursive_cte);
PAIR(BM_Prepared, window_rank);
PAIR(BM_Prepared, window_sum_frame);
PAIR(BM_Prepared, in_subselect);
PAIR(BM_Prepared, not_exists);

PAIR(BM_Oneshot, pk_point);
PAIR(BM_Oneshot, feed);
PAIR(BM_Oneshot, post_with_count);
PAIR(BM_Oneshot, group_by_index);
PAIR(BM_Oneshot, union);
PAIR(BM_Oneshot, window_rank);

int main(int argc, char **argv) {
  benchmark::Initialize(&argc, argv);
  if (benchmark::ReportUnrecognizedArguments(argc, argv)) return 1;
  benchmark::RunSpecifiedBenchmarks();
  benchmark::Shutdown();
  if (g_db) sqlite3_close(g_db);
  return 0;
}
