/* load.c: load <db> <schema.sql> <indexes.sql> <dir>: creates the tables, loads dbgen's <dir>/<table>.tbl files
** ('|'-separated, with or without a trailing '|'), each field bound as text so the column's affinity converts it, then creates the
** indexes and runs ANALYZE (indexes.sql). Linked with the stock amalgamation: every arm then reads the same file. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sqlite3.h"
static char *slurp(const char *p) {
  FILE *f = fopen(p, "rb"); if (!f) { perror(p); exit(1); }
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  char *b = malloc((size_t)n + 1); if (fread(b, 1, (size_t)n, f) != (size_t)n) exit(1); b[n] = 0; fclose(f); return b;
}
static void ok(sqlite3 *db, int rc, const char *what) { if (rc != SQLITE_OK && rc != SQLITE_DONE) { fprintf(stderr, "load: %s: %s\n", what, sqlite3_errmsg(db)); exit(1); } }
int main(int argc, char **argv) {
  if (argc != 5) { fprintf(stderr, "usage: load <db> <schema.sql> <indexes.sql> <tbl-dir>\n"); return 2; }
  sqlite3 *db; ok(db, sqlite3_open(argv[1], &db), "open");
  ok(db, sqlite3_exec(db, "PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA cache_size=-262144;", 0, 0, 0), "pragmas");
  ok(db, sqlite3_exec(db, slurp(argv[2]), 0, 0, 0), "schema");
  static const char *T[] = { "region", "nation", "part", "supplier", "partsupp", "customer", "orders", "lineitem" };
  char line[8192], sql[512], path[4096];
  for (int t = 0; t < 8; t++) {
    sqlite3_stmt *c; snprintf(sql, sizeof sql, "SELECT * FROM %s", T[t]);
    ok(db, sqlite3_prepare_v2(db, sql, -1, &c, 0), sql); int nc = sqlite3_column_count(c); sqlite3_finalize(c);
    int n = snprintf(sql, sizeof sql, "INSERT INTO %s VALUES(?", T[t]);
    for (int i = 1; i < nc; i++) n += snprintf(sql + n, sizeof sql - (size_t)n, ",?");
    snprintf(sql + n, sizeof sql - (size_t)n, ")");
    sqlite3_stmt *ins; ok(db, sqlite3_prepare_v2(db, sql, -1, &ins, 0), sql);
    snprintf(path, sizeof path, "%s/%s.tbl", argv[4], T[t]);
    FILE *f = fopen(path, "r"); if (!f) { perror(path); return 1; }
    ok(db, sqlite3_exec(db, "BEGIN", 0, 0, 0), "begin");
    long rows = 0;
    while (fgets(line, sizeof line, f)) {
      size_t L = strlen(line); while (L && (line[L - 1] == '\n' || line[L - 1] == '\r')) line[--L] = 0;
      if (L && line[L - 1] != '|') { line[L++] = '|'; line[L] = 0; }   /* (tpch-kit's POSTGRESQL build: no trailing '|') */
      char *p = line; int col = 0;
      for (char *e; col < nc && (e = strchr(p, '|')); p = e + 1) { *e = 0; sqlite3_bind_text(ins, ++col, p, (int)(e - p), SQLITE_TRANSIENT); }
      if (col != nc) { fprintf(stderr, "load: %s: bad line %ld\n", path, rows + 1); return 1; }
      ok(db, sqlite3_step(ins), "insert"); sqlite3_reset(ins); rows++;
    }
    ok(db, sqlite3_exec(db, "COMMIT", 0, 0, 0), "commit");
    fclose(f); sqlite3_finalize(ins);
    fprintf(stderr, "load: %s %ld rows\n", T[t], rows);
  }
  ok(db, sqlite3_exec(db, slurp(argv[3]), 0, 0, 0), "indexes");
  ok(db, sqlite3_close(db), "close");
  return 0;
}
