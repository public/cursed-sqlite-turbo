// threads <db> [threads] [iterations] [seed]: qc served on many threads at once (SQLITE_THREADSAFE=1), every result
// against the interpreter. tests/corpus.c's statements over the test schema (a WAL database: scripts/gen-db.py).
//   - multi-thread mode: each thread its own connection (SQLITE_OPEN_NOMUTEX). Reads in a transaction of their own, so a
//     served run and the interpreter's see the same snapshot while the other threads write; writes (insert, update,
//     delete) and reads of the thread's own uncommitted writes in BEGIN IMMEDIATE; a stream left suspended while another
//     statement runs on the connection; statements finalized and prepared again (the plan cache); now and then an index
//     created or dropped (every other connection's statements re-prepared)
//   - serialized mode: one connection (SQLITE_OPEN_FULLMUTEX) shared by threads, each stepping its own statements, their
//     steps interleaved with the other threads' (a stream suspended by one thread drained by another's statement); the
//     tables it reads are not written while it runs (its writes go to a table of its own), so any run is comparable
// The interpreter's run is a second handle of the same text that qc never takes (qcNo set before each run).
#define main corpus_main   /* (the statements, their parameters and the row hash: corpus.c's) */
#include "corpus.c"
#undef main
#include <pthread.h>

static const char *PATH; static int NT = 8, ITERS = 400; static unsigned SEED = 1;
static long n_cmp, n_diff, n_served, n_err;   /* (added to atomically) */
#define ADD(x, n) __atomic_fetch_add(&(x), (n), __ATOMIC_RELAXED)

typedef struct { u64 s; } Rng;
static u64 rn(Rng *r) { r->s ^= r->s << 13; r->s ^= r->s >> 7; r->s ^= r->s << 17; return r->s; }
static void bind_r(sqlite3_stmt *s, const char *ps, Rng *r) {   /* corpus.c's bind_params with the thread's generator */
  char t[64];
  for (int k = 0; ps[k]; k++) {
    int i = k + 1;
    switch (ps[k]) {
      case 'p': sqlite3_bind_int64(s, i, 1 + (i64)(rn(r) % (u64)NP)); break;
      case 'P': sqlite3_bind_int64(s, i, rn(r) % 8 ? 1 + (i64)(rn(r) % (u64)NP) : NP + 1 + (i64)(rn(r) % 10)); break;
      case 'u': sqlite3_bind_int64(s, i, 1 + (i64)(rn(r) % (u64)NU)); break;
      case 'r': sqlite3_bind_int64(s, i, 1 + (i64)(rn(r) % (u64)(NP - 25))); break;
      case 'k': sqlite3_bind_int64(s, i, 1 + (i64)(rn(r) % 20)); break;
      case 'n': if (rn(r) % 8) snprintf(t, sizeof t, "%s", NAMES[rn(r) % (u64)NU]); else snprintf(t, sizeof t, "user%05lld_", 1 + (long long)(rn(r) % (u64)NU));
                sqlite3_bind_text(s, i, t, -1, SQLITE_TRANSIENT); break;
      case 't': snprintf(t, sizeof t, "2025-%02d-%02dT00:00:00.000Z", 1 + (int)(rn(r) % 12), 1 + (int)(rn(r) % 28));
                sqlite3_bind_text(s, i, t, -1, SQLITE_TRANSIENT); break;
      case 'w': sqlite3_bind_text(s, i, WORDS[rn(r) % 5], -1, SQLITE_STATIC); break;
    }
  }
}
/* a statement's rows hashed (as corpus.c's interp_rows); first: rows stepped before `between` runs, -1 none */
static int rows_hash(sqlite3_stmt *s, u64 *h, int first, void (*between)(void *), void *arg) {
  int rows = 0, rc; *h = 1469598103934665603ULL;
  while ((rc = sqlite3_step(s)) == SQLITE_ROW) {
    rows++;
    for (int c = 0; c < sqlite3_column_count(s); c++) {
      int t = sqlite3_column_type(s, c);
      *h = hval(*h, t, t == SQLITE_TEXT ? (const void *)sqlite3_column_text(s, c) : sqlite3_column_blob(s, c), sqlite3_column_bytes(s, c),
                sqlite3_column_int64(s, c), sqlite3_column_double(s, c));
    }
    if (rows == first && between) between(arg);
  }
  sqlite3_reset(s);
  return rc == SQLITE_DONE ? rows : -1 - rc;
}
typedef struct { sqlite3_stmt *a, *b; } Pair;   /* a: served; b: the interpreter's (qcNo) */
static int prep_pair(sqlite3 *db, int q, Pair *p) {
  if (sqlite3_prepare_v2(db, QS[q].sql, -1, &p->a, 0) || sqlite3_prepare_v2(db, QS[q].sql, -1, &p->b, 0)) return 0;
  return 1;
}
static void fin_pair(Pair *p) { sqlite3_finalize(p->a); sqlite3_finalize(p->b); p->a = p->b = 0; }
typedef struct { sqlite3 *db; Pair *other; Rng *r; int q; } Between;
static void run_other(void *x) {   /* while the served statement may be suspended mid-stream: another statement on its connection */
  Between *B = x; u64 h; ((Vdbe *)B->other->b)->qcNo = 1; bind_r(B->other->b, QS[B->q].params, B->r); rows_hash(B->other->b, &h, -1, 0, 0);
}
/* one comparison: the served handle's rows (optionally with another statement run after its first row) against the
   interpreter's, under the caller's transaction (or none, where nothing it reads is being written) */
static void compare(Pair *p, int q, Rng *r, Between *mid, int tid) {
  Rng r2 = *r; bind_r(p->a, QS[q].params, r); bind_r(p->b, QS[q].params, &r2);   /* (the same values) */
  u64 ha, hb; int na = rows_hash(p->a, &ha, mid ? 1 : -1, mid ? run_other : 0, mid);
  ((Vdbe *)p->b)->qcNo = 1; int nb = rows_hash(p->b, &hb, -1, 0, 0);
  if (((Vdbe *)p->a)->pQc) ADD(n_served, 1);
  if (na == -1 - SQLITE_BUSY || nb == -1 - SQLITE_BUSY || na == -1 - SQLITE_LOCKED || nb == -1 - SQLITE_LOCKED) { ADD(n_err, 1); return; }
  ADD(n_cmp, 1);
  if (na != nb || ha != hb) {
    ADD(n_diff, 1);
    fprintf(stderr, "threads: thread %d: %s: served %d rows (%016llx), interpreter %d (%016llx)\n", tid, QS[q].name, na, (unsigned long long)ha, nb, (unsigned long long)hb);
  }
}
static int ex(sqlite3 *db, const char *sql) { return sqlite3_exec(db, sql, 0, 0, 0); }

static void *own_conn(void *arg) {   /* multi-thread mode: this thread's own connection */
  int tid = (int)(intptr_t)arg; Rng r = {SEED * 0x9E3779B97F4A7C15ULL + (u64)tid * 0xBF58476D1CE4E5B9ULL + 1};
  sqlite3 *db; if (sqlite3_open_v2(PATH, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, 0)) { ADD(n_err, 1); return 0; }
  sqlite3_busy_timeout(db, 10000);
  Pair *P = calloc(NQ, sizeof *P);
  for (int it = 0; it < ITERS; it++) {
    int q = (int)(rn(&r) % NQ), mode = (int)(rn(&r) % 16);
    if (!P[q].a && !prep_pair(db, q, &P[q])) { ADD(n_err, 1); continue; }
    if (mode < 9) {   /* a read in a transaction of its own (its snapshot), once in a while with another statement mid-stream */
      ex(db, "BEGIN");
      Between B = {db, 0, &r, (int)(rn(&r) % NQ)};
      if (mode == 0 && (P[B.q].a || prep_pair(db, B.q, &P[B.q]))) { B.other = &P[B.q]; if (B.other == &P[q]) B.other = 0; }
      compare(&P[q], q, &r, B.other ? &B : 0, tid);
      ex(db, "COMMIT");
    } else if (mode < 13) {   /* writes, and reads that see them, in one write transaction */
      if (ex(db, "BEGIN IMMEDIATE") != SQLITE_OK) { ADD(n_err, 1); continue; }
      char sql[256]; i64 u = 1 + (i64)(rn(&r) % (u64)NU), pid = 1 + (i64)(rn(&r) % (u64)NP);
      switch (rn(&r) % 4) {
        case 0: snprintf(sql, sizeof sql, "INSERT INTO posts (user_id, body) VALUES (%lld, 'thread %d post %d')", (long long)u, tid, it); break;
        case 1: snprintf(sql, sizeof sql, "INSERT OR IGNORE INTO likes (user_id, post_id) VALUES (%lld, %lld)", (long long)u, (long long)pid); break;
        case 2: snprintf(sql, sizeof sql, "UPDATE posts SET body = body || '.' WHERE id = %lld AND length(body) < 400", (long long)pid); break;
        default: snprintf(sql, sizeof sql, "DELETE FROM likes WHERE user_id = %lld AND post_id IN (SELECT post_id FROM likes WHERE user_id = %lld LIMIT 1)", (long long)u, (long long)u); break;
      }
      ex(db, sql);
      compare(&P[q], q, &r, 0, tid);
      ex(db, "COMMIT");
    } else if (mode < 15) {   /* finalized and prepared again: the plan cache */
      fin_pair(&P[q]);
    } else if (rn(&r) % 8 == 0) {   /* a schema change: every connection's statements re-prepared */
      char sql[128]; snprintf(sql, sizeof sql, (rn(&r) & 1) ? "CREATE INDEX IF NOT EXISTS t%d ON posts(length(body))" : "DROP INDEX IF EXISTS t%d", tid % 2);
      if (ex(db, sql) != SQLITE_OK && sqlite3_errcode(db) != SQLITE_BUSY) ADD(n_err, 1);
    }
  }
  for (int q = 0; q < NQ; q++) if (P[q].a) fin_pair(&P[q]);
  free(P); sqlite3_close(db);
  return 0;
}

/* one thread, deterministic: a statement's stream left suspended while others run on its connection, as serialized mode
   interleaves them (and any program may, on one thread). 1: its row, and the text column_* returned for it before, stay
   as they were while another statement runs (the stream drained into its rows); 2: another statement that ends (its
   halt commits, downgrading the transaction while the stream still reads) leaves the stream's cursors open. Each
   against the interpreter's rows; returns the differences (and how many runs really streamed, *strm) */
static int interleaved(const char *path, int *strm) {
  sqlite3 *c; if (sqlite3_open_v2(path, &c, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, 0)) return 1;
  const char *big = "SELECT id, body FROM posts WHERE user_id BETWEEN ?1 AND ?1 + 60 ORDER BY id";   /* (texts, more rows than QC_STREAM_MIN) */
  const char *other = "SELECT p.id, u.username FROM posts p JOIN users u ON u.id = p.user_id WHERE p.user_id BETWEEN ?1 AND ?1 + 3";
  sqlite3_stmt *a, *ar, *b; int bad = 0;
  sqlite3_prepare_v2(c, big, -1, &a, 0); sqlite3_prepare_v2(c, big, -1, &ar, 0); sqlite3_prepare_v2(c, other, -1, &b, 0);
  for (int run = 0; run < 12; run++) {
    i64 u = 1 + (run * 97) % (NU - 70);
    sqlite3_bind_int64(a, 1, u); sqlite3_bind_int64(ar, 1, u); sqlite3_bind_int64(b, 1, u + 5);
    u64 hr; ((Vdbe *)ar)->qcNo = 1; int nr = rows_hash(ar, &hr, -1, 0, 0);
    u64 h = 1469598103934665603ULL; int n = 0, rc; char keep[512]; const unsigned char *kp = 0; int kn = 0;
    if (run % 2 && run > 6) { rc = sqlite3_step(b); }   /* (2: b under way before a starts) */
    while ((rc = sqlite3_step(a)) == SQLITE_ROW) {
      n++;
      if (n == 1 && a && ((Vdbe *)a)->pQcRows && ((QcServe *)((Vdbe *)a)->pQcRows)->strm == 1) ++*strm;
      if (n == 3) {   /* (1: a text handed out, then another statement on the connection) */
        kp = sqlite3_column_text(a, 1); kn = sqlite3_column_bytes(a, 1); if (kn > (int)sizeof keep) kn = sizeof keep; memcpy(keep, kp, (size_t)kn);
        if (run % 2 && run > 6) { while (sqlite3_step(b) == SQLITE_ROW) {} sqlite3_reset(b); }   /* (2: b ends) */
        else { u64 hb; rows_hash(b, &hb, -1, 0, 0); }
        if (memcmp(kp, keep, (size_t)kn) || sqlite3_column_bytes(a, 1) < kn || memcmp(sqlite3_column_text(a, 1), keep, (size_t)kn)) {
          bad++; fprintf(stderr, "threads: interleaved run %d: the row handed out changed under another statement\n", run);
        }
      }
      for (int k = 0; k < sqlite3_column_count(a); k++) {
        int t = sqlite3_column_type(a, k);
        h = hval(h, t, t == SQLITE_TEXT ? (const void *)sqlite3_column_text(a, k) : sqlite3_column_blob(a, k), sqlite3_column_bytes(a, k), sqlite3_column_int64(a, k), sqlite3_column_double(a, k));
      }
    }
    sqlite3_reset(a); sqlite3_reset(b);
    if (rc != SQLITE_DONE || n != nr || h != hr) { bad++; fprintf(stderr, "threads: interleaved run %d: served %d rows, interpreter %d (rc %d)\n", run, n, nr, rc); }
  }
  /* 3: a write to the pages the stream reads (rows grown: cells move, pages split) while it is suspended: the drain
     leaves no page referenced, so the write's balance doesn't take them for corrupt; the rows still come whole */
  sqlite3_exec(c, "BEGIN", 0, 0, 0);
  sqlite3_stmt *w; sqlite3_prepare_v2(c, "UPDATE posts SET body = body || ' grown by a writer' WHERE user_id BETWEEN ?1 AND ?1 + 60", -1, &w, 0);
  for (int run = 0; run < 8; run++) {
    i64 u = 1 + (run * 131) % (NU - 70); int n = 0, rc, nr = 0; u64 h;
    sqlite3_bind_int64(ar, 1, u); ((Vdbe *)ar)->qcNo = 1; nr = rows_hash(ar, &h, -1, 0, 0);
    sqlite3_bind_int64(a, 1, u);
    while ((rc = sqlite3_step(a)) == SQLITE_ROW)
      if (++n == 2) { sqlite3_bind_int64(w, 1, u); int rw = sqlite3_step(w); sqlite3_reset(w);
                      if (rw != SQLITE_DONE) { bad++; fprintf(stderr, "threads: interleaved write %d: %s\n", run, sqlite3_errmsg(c)); } }
    sqlite3_reset(a);
    if (rc != SQLITE_DONE || n != nr) { bad++; fprintf(stderr, "threads: interleaved write %d: served %d rows (rc %d), interpreter %d\n", run, n, rc, nr); }
  }
  sqlite3_finalize(w); sqlite3_exec(c, "ROLLBACK", 0, 0, 0);
  sqlite3_finalize(a); sqlite3_finalize(ar); sqlite3_finalize(b); sqlite3_close(c);
  return bad;
}

static sqlite3 *SHARED;
static void *shared_conn(void *arg) {   /* serialized mode: SHARED's statements of this thread's own */
  int tid = (int)(intptr_t)arg; Rng r = {SEED * 0xD1B54A32D192ED03ULL + (u64)tid * 0x94D049BB133111EBULL + 7};
  Pair *P = calloc(NQ, sizeof *P);
  for (int it = 0; it < ITERS; it++) {
    int q = (int)(rn(&r) % NQ), mode = (int)(rn(&r) % 8);
    if (!P[q].a && !prep_pair(SHARED, q, &P[q])) { ADD(n_err, 1); continue; }
    if (mode < 6) compare(&P[q], q, &r, 0, 100 + tid);
    else if (mode == 6) { char sql[128]; snprintf(sql, sizeof sql, "INSERT INTO shared_w (t, i) VALUES (%d, %d)", tid, it); sqlite3_exec(SHARED, sql, 0, 0, 0); }
    else fin_pair(&P[q]);
  }
  for (int q = 0; q < NQ; q++) if (P[q].a) fin_pair(&P[q]);
  free(P);
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: threads <db> [threads] [iterations] [seed]\n"); return 2; }
  PATH = argv[1]; if (argc > 2) NT = atoi(argv[2]); if (argc > 3) ITERS = atoi(argv[3]); if (argc > 4) SEED = (unsigned)atoi(argv[4]);
  if (!sqlite3_threadsafe()) { fprintf(stderr, "threads: built with SQLITE_THREADSAFE=0\n"); return 2; }
  sqlite3_qc_serve(1);   /* (before the threads: a process-wide switch) */
  if (sqlite3_open(PATH, &db)) return 1;
  ex(db, "PRAGMA journal_mode=WAL"); ex(db, "DROP INDEX IF EXISTS t0"); ex(db, "DROP INDEX IF EXISTS t1");
  NU = one("SELECT max(id) FROM users"); NP = one("SELECT max(id) FROM posts");
  NAMES = calloc((size_t)NU, sizeof *NAMES);
  { sqlite3_stmt *q; sqlite3_prepare_v2(db, "SELECT id, username FROM users", -1, &q, 0);
    while (sqlite3_step(q) == SQLITE_ROW) { i64 id = sqlite3_column_int64(q, 0); if (id >= 1 && id <= NU) NAMES[id - 1] = strdup((const char *)sqlite3_column_text(q, 1)); }
    sqlite3_finalize(q); for (i64 k = 0; k < NU; k++) if (!NAMES[k]) NAMES[k] = "none"; }
  sqlite3_close(db); db = 0;
  int nstrm = 0, ibad = interleaved(PATH, &nstrm); n_diff += ibad;
  printf("threads: interleaved on one thread: 12 runs (%d streamed) and 8 with a write, %d differences\n", nstrm, ibad);
  /* multi-thread mode: NT connections, reading and writing */
  pthread_t *th = calloc((size_t)NT * 2, sizeof *th);
  for (int t = 0; t < NT; t++) pthread_create(&th[t], 0, own_conn, (void *)(intptr_t)t);
  for (int t = 0; t < NT; t++) pthread_join(th[t], 0);
  long c1 = n_cmp, d1 = n_diff;
  printf("threads: multi-thread mode: %d threads, %ld compared, %ld served, %ld differences, %ld busy or errors\n", NT, n_cmp, n_served, n_diff, n_err);
  /* serialized mode: one connection, NT threads (a snapshot of the database: nothing writes what it reads) */
  char path2[1024]; snprintf(path2, sizeof path2, "%s.shared", PATH);
  { sqlite3 *a, *b; remove(path2); sqlite3_open(PATH, &a); sqlite3_open(path2, &b);
    sqlite3_backup *k = sqlite3_backup_init(b, "main", a, "main"); sqlite3_backup_step(k, -1); sqlite3_backup_finish(k);
    sqlite3_close(a); sqlite3_close(b); }
  if (sqlite3_open_v2(path2, &SHARED, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, 0)) return 1;
  sqlite3_busy_timeout(SHARED, 10000); ex(SHARED, "CREATE TABLE shared_w (t INT, i INT)");
  for (int t = 0; t < NT; t++) pthread_create(&th[t], 0, shared_conn, (void *)(intptr_t)t);
  for (int t = 0; t < NT; t++) pthread_join(th[t], 0);
  sqlite3_close(SHARED); remove(path2);
  printf("threads: serialized mode: one connection, %d threads, %ld compared, %ld differences\n", NT, n_cmp - c1, n_diff - d1);
  free(th);
  for (i64 k = 0; k < NU; k++) if (strcmp(NAMES[k], "none")) free(NAMES[k]);
  free(NAMES);
  return n_diff ? 1 : 0;
}
