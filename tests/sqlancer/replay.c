/* replay.c: replay <sql-file>: SQLancer's log of a database (one statement a line; "--" lines skipped) run on a fresh
** in-memory database, every statement in order, errors ignored as SQLancer does; each row a statement returns is
** printed with its statement's line number, values typed (i:, r: with %.17g, t:, b:hex, null), so the output of the
** stock and turbo builds can be diffed (tests/sqlancer/repro.sh). REPLAY_DB=<file> uses a file instead. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sqlite3.h"
int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: replay <sql-file>\n"); return 2; }
  FILE *f = fopen(argv[1], "r"); if (!f) { perror(argv[1]); return 1; }
  sqlite3 *db; const char *p = getenv("REPLAY_DB");
  if (sqlite3_open(p ? p : ":memory:", &db) != SQLITE_OK) return 1;
  static char line[1 << 20]; int ln = 0;
  while (fgets(line, sizeof line, f)) {
    ln++;
    if (!strncmp(line, "--", 2) || line[0] == '\n') continue;
    const char *sql = line, *tail;
    while (*sql) {
      sqlite3_stmt *st = 0;
      if (sqlite3_prepare_v2(db, sql, -1, &st, &tail) != SQLITE_OK) { printf("%d prepare error: %s\n", ln, sqlite3_errmsg(db)); break; }
      if (!st) break;
      int rc;
      while ((rc = sqlite3_step(st)) == SQLITE_ROW) {
        printf("%d row:", ln);
        for (int i = 0; i < sqlite3_column_count(st); i++) {
          switch (sqlite3_column_type(st, i)) {
            case SQLITE_INTEGER: printf(" i:%lld", sqlite3_column_int64(st, i)); break;
            case SQLITE_FLOAT: printf(" r:%.17g", sqlite3_column_double(st, i)); break;
            case SQLITE_TEXT: printf(" t:'%s'", sqlite3_column_text(st, i)); break;
            case SQLITE_BLOB: { const unsigned char *b = sqlite3_column_blob(st, i); int n = sqlite3_column_bytes(st, i);
              printf(" b:"); for (int k = 0; k < n; k++) printf("%02x", b[k]); break; }
            default: printf(" null");
          }
        }
        printf("\n");
      }
      if (rc != SQLITE_DONE) printf("%d error: %s\n", ln, sqlite3_errmsg(db));
      sqlite3_finalize(st);
      sql = tail;
    }
  }
  sqlite3_close(db);
  return 0;
}
