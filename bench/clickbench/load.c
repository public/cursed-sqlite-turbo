/* load.c: load <db> <create.sql> <hits.csv>: ClickBench's SQLite load (sqlite3 mydb < create.sql, then
** .import --csv hits.csv hits) without the shell: every field bound as text, as .import does, so the columns'
** affinity converts them. RFC 4180 quoting. Linked with the stock amalgamation. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sqlite3.h"
static void ok(sqlite3 *db, int rc, const char *what) { if (rc != SQLITE_OK && rc != SQLITE_DONE) { fprintf(stderr, "load: %s: %s\n", what, sqlite3_errmsg(db)); exit(1); } }
int main(int argc, char **argv) {
  if (argc != 4) { fprintf(stderr, "usage: load <db> <create.sql> <hits.csv>\n"); return 2; }
  FILE *f = fopen(argv[2], "rb"); if (!f) { perror(argv[2]); return 1; }
  static char ddl[1 << 16]; ddl[fread(ddl, 1, sizeof ddl - 1, f)] = 0; fclose(f);
  sqlite3 *db; ok(db, sqlite3_open(argv[1], &db), "open");
  ok(db, sqlite3_exec(db, "PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA cache_size=-262144;", 0, 0, 0), "pragmas");
  ok(db, sqlite3_exec(db, ddl, 0, 0, 0), "create.sql");
  sqlite3_stmt *c; ok(db, sqlite3_prepare_v2(db, "SELECT * FROM hits", -1, &c, 0), "columns");
  int nc = sqlite3_column_count(c); sqlite3_finalize(c);
  char *sql = malloc((size_t)nc * 2 + 64); int n = sprintf(sql, "INSERT INTO hits VALUES(?");
  for (int i = 1; i < nc; i++) n += sprintf(sql + n, ",?");
  strcpy(sql + n, ")");
  sqlite3_stmt *ins; ok(db, sqlite3_prepare_v2(db, sql, -1, &ins, 0), "insert");
  f = fopen(argv[3], "rb"); if (!f) { perror(argv[3]); return 1; }
  size_t cap = 1 << 16, len = 0; char *fld = malloc(cap);
  int col = 0, ch, inq = 0; long rows = 0;
  ok(db, sqlite3_exec(db, "BEGIN", 0, 0, 0), "begin");
  for (;;) {
    ch = getc(f);
    if (inq) {
      if (ch == EOF) { fprintf(stderr, "load: EOF inside quotes\n"); return 1; }
      if (ch == '"') { int d = getc(f); if (d == '"') { fld[len++] = '"'; } else { inq = 0; ungetc(d, f); } }
      else fld[len++] = (char)ch;
    } else if (ch == '"' && len == 0) inq = 1;
    else if (ch == ',' || ch == '\n' || ch == EOF) {
      if (ch == EOF && col == 0 && len == 0) break;
      if (len && fld[len - 1] == '\r' && ch != ',') len--;
      if (col < nc) sqlite3_bind_text(ins, col + 1, fld, (int)len, SQLITE_TRANSIENT);
      col++; len = 0;
      if (ch != ',') {
        if (col != nc) { fprintf(stderr, "load: record %ld has %d fields, not %d\n", rows + 1, col, nc); return 1; }
        ok(db, sqlite3_step(ins), "insert row"); sqlite3_reset(ins); rows++; col = 0;
        if (ch == EOF) break;
      }
    } else fld[len++] = (char)ch;
    if (len + 2 >= cap) { cap *= 2; fld = realloc(fld, cap); }
  }
  ok(db, sqlite3_exec(db, "COMMIT", 0, 0, 0), "commit");
  sqlite3_finalize(ins); ok(db, sqlite3_close(db), "close");
  fprintf(stderr, "load: hits %ld rows\n", rows);
  return 0;
}
