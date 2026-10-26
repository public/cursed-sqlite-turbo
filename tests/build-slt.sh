#!/bin/sh
# build-slt.sh [out-dir]: sqllogictest with qc (tests/slt_qc.c as the harness's SQLite engine), from the patched
# amalgamation in build/gen and the pinned harness in third_party/slt (scripts/fetch-slt.sh). CC and CFLAGS as usual;
# memory statistics stay on (the harness checks for leaks at disconnect, which also checks qc frees its plans).
set -e
cd "$(dirname "$0")/.."
O=${1:-build/slt-qc}; S=third_party/slt/src
[ -f "$S/sqllogictest.c" ] || sh scripts/fetch-slt.sh
[ -f build/gen/sqlite3.c ] || make build/gen/sqlite3.c build/gen/qc_dec.h
mkdir -p "$O"
cp "$S/sqllogictest.c" "$S/sqllogictest.h" "$S/md5.c" "$S/slt_odbc3.c" "$O/"
cp tests/slt_qc.c "$O/slt_sqlite.c"   # sqllogictest.c #includes "slt_sqlite.c" from its own directory
${CC:-cc} ${CFLAGS:--O2 -g} -D_GNU_SOURCE -DOMIT_ODBC=1 -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_NO_SYNC=1 \
  -Ibuild/gen -Iqc -w "$O/sqllogictest.c" "$O/md5.c" -o "$O/sqllogictest" -lm -lpthread
echo "build-slt: $O/sqllogictest"
