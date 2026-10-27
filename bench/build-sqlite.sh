#!/bin/sh
# build-sqlite.sh <variant> <out-dir>: one SQLite translation unit, <out-dir>/sqlite3.c (+ sqlite3.h, qc_dec.h), that
# any program compiles and links in place of the plain amalgamation:
#   stock   SQLite 3.54.1 as fetched (scripts/fetch-sqlite.sh), unchanged
#   serve   qc/patch.py --step-hook, sqlite3_reset/finalize/close/close_v2 renamed *_orig too, then qc.c and bench/qc_serve.c
#           appended: qc runs every read-only statement it takes, behind SQLite's own API (QC_VM_ONLY=1: through qvm)
#   diff    qc/patch.py --step-hook, then qc.c and tests/tcl_qc.c appended: every read-only statement also runs through
#           qc on a copy and is compared, value by value, with the interpreter's rows (QCTDIFF lines in $QCT_DIR)
# <out-dir> is self-contained (qc's sources and the shim are copied next to sqlite3.c): compile it from there, with the
# same options for every variant. (bench/lib.sh compiles it by relative paths, so ccache hits wherever the tree is.)
# SQLITE_SRC=<sqlite3.c>: start from that amalgamation instead (tests/sqlancer/build.sh: sqlite-jdbc's edited copy).
set -e
R=$(cd "$(dirname "$0")/.." && pwd); V=$1; O=$2
[ -n "$V" ] && [ -n "$O" ] || { echo "usage: build-sqlite.sh stock|serve|diff <out-dir>" >&2; exit 2; }
sh "$R/scripts/fetch-sqlite.sh"
mkdir -p "$O"; S="$R/third_party/sqlite"; SRC=${SQLITE_SRC:-$S/sqlite3.c}
cp "$S/sqlite3.h" "$O/"
case "$V" in
  stock) cp "$SRC" "$O/sqlite3.c" ;;
  serve|diff)
    python3 "$R/qc/gen_decoders.py" "$O/qc_dec.h"
    cp "$R"/qc/qc.c "$R"/qc/qcg.c "$R"/qc/qvm.c "$R"/qc/qvm_run.h "$R/bench/qc_serve.c" "$R/tests/tcl_qc.c" "$O/"
    python3 "$R/qc/patch.py" --step-hook "$SRC" "$O/sqlite3.c.tmp"
    if [ "$V" = serve ]; then
      python3 - "$O/sqlite3.c.tmp" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='latin-1').read()
for f in ('reset', 'finalize'):   # wrapped by bench/qc_serve.c (a handle given up mid-rows forgets qc's rows)
    a = 'SQLITE_API int sqlite3_%s(sqlite3_stmt *pStmt){\n' % f
    if s.count(a) != 1: sys.exit('build-sqlite: anchor for sqlite3_%s found %d times' % (f, s.count(a)))
    s = s.replace(a, 'static int sqlite3_%s_orig(sqlite3_stmt *pStmt){   /* bench/qc_serve.c */\n' % f)
for f, a in (('close', '0'), ('close_v2', '1')):   # (bench/qc_serve.c finalizes its BEGIN/COMMIT first)
    x = 'SQLITE_API int sqlite3_%s(sqlite3 *db){ return sqlite3Close(db,%s); }' % (f, a)
    if s.count(x) != 1: sys.exit('build-sqlite: anchor for sqlite3_%s found %d times' % (f, s.count(x)))
    s = s.replace(x, 'static int sqlite3_%s_orig(sqlite3 *db){ return sqlite3Close(db,%s); }   /* bench/qc_serve.c */' % (f, a))
open(p, 'w', encoding='latin-1').write(s)
PY
      printf '\n#include "qc.c"   /* cursed-sqlite-turbo */\n#include "qc_serve.c"\n' >> "$O/sqlite3.c.tmp"
    else
      printf '\n#include "qc.c"   /* cursed-sqlite-turbo */\n#include "tcl_qc.c"\n' >> "$O/sqlite3.c.tmp"
    fi
    mv "$O/sqlite3.c.tmp" "$O/sqlite3.c" ;;
  *) echo "build-sqlite: unknown variant $V" >&2; exit 2 ;;
esac
echo "build-sqlite: $V in $O"
