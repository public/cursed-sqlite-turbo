"""instrument.py <speedtest1.c> <out.c>: the instrumented copy of speedtest1.c (bench/speedtest1/st1_instr.h): hook
calls inserted at exact anchors, each found once, so a changed upstream file fails loudly instead of measuring
something else. The unchanged file stays the headline benchmark."""
import sys
s = open(sys.argv[1], encoding='latin-1').read()
def once(old, new):
    global s
    if s.count(old) != 1: sys.exit(f'instrument: anchor found {s.count(old)} times: {old[:60]!r}')
    s = s.replace(old, new)
once('#include "sqlite3.h"\n', '#include "sqlite3.h"\n#include <string.h>\n#include <stdlib.h>\n#include "st1_instr.h"   /* bench/speedtest1 */\n')
once('  g.iStart = speedtest1_timestamp();\n  g.x = 0xad131d0b;\n', '  g.iStart = speedtest1_timestamp();\n  st1i_begin(iTestNum);\n  g.x = 0xad131d0b;\n')
once('  sqlite3_int64 iElapseTime = speedtest1_timestamp() - g.iStart;\n', '  sqlite3_int64 iElapseTime = speedtest1_timestamp() - g.iStart;\n  st1i_end();\n')
once('    rc = sqlite3_exec(g.db, zSql, 0, 0, &zErrMsg);\n', '    st1i_exec_start();\n    rc = sqlite3_exec(g.db, zSql, 0, 0, &zErrMsg);\n    st1i_exec_end(zSql);\n')
once('    rc = sqlite3_prepare_v2(g.db, zSql, -1, &g.pStmt, 0);\n', '    st1i_prep_start();\n    rc = sqlite3_prepare_v2(g.db, zSql, -1, &g.pStmt, 0);\n    st1i_prep_end(zSql);\n')
once('  assert( g.pStmt );\n  g.nResult = 0;\n', '  assert( g.pStmt );\n  g.nResult = 0;\n  st1i_run_start();\n')
once('    }\n  }\n  speedtest1_shrink_memory();\n}\n', '    }\n  }\n  st1i_run_end();\n  speedtest1_shrink_memory();\n}\n')
open(sys.argv[2], 'w', encoding='latin-1').write(s)
