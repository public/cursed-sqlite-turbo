// explain <db> "<sql>"...: each statement's bytecode with operands (the lifter's input), for working on qc
#include "sqlite3.c"
int main(int argc, char **argv) {
  sqlite3 *db; if (argc < 3 || sqlite3_open(argv[1], &db)) return 2;
  for (int q = 2; q < argc; q++) {
    sqlite3_stmt *s; if (sqlite3_prepare_v2(db, argv[q], -1, &s, 0)) { printf("ERR %s\n", sqlite3_errmsg(db)); continue; }
    Vdbe *v = (Vdbe *)s; printf("\n## %s\n", argv[q]);
    for (int i = 0; i < v->nOp; i++) { Op *o = &v->aOp[i];
      printf("%3d %-14s %4d %4d %4d  p4t=%-3d p5=%-3d", i, sqlite3OpcodeName(o->opcode), o->p1, o->p2, o->p3, o->p4type, o->p5);
      if (o->p4type == P4_FUNCDEF) printf(" %s", o->p4.pFunc->zName);
      if (o->p4type == P4_INT32) printf(" i=%d", o->p4.i);
      if (o->p4type == P4_KEYINFO) printf(" keyinfo(%d)", o->p4.pKeyInfo->nKeyField);
      printf("\n"); }
    sqlite3_finalize(s);
  }
}
