#!/bin/sh
# build-tcl.sh <out dir>: SQLite's testfixture with qc and the differential sqlite3_step hook (tests/tcl_qc.c), from
# the canonical source tree (scripts/fetch-sqlite-src.sh). Needs a C compiler, tclsh and Tcl headers (the
# sqlconf-tools Docker image has them). The amalgamation is made from the tree, patched (qc/patch.py --step-hook),
# and qc.c and tcl_qc.c are appended to it; testfixture then compiles it with the suite's own options.
set -e
cd "$(dirname "$0")/.."
R=$(pwd); O=$1; V=3540100
sh scripts/fetch-sqlite-src.sh
[ -f build/gen/qc_dec.h ] || python3 qc/gen_decoders.py build/gen/qc_dec.h
rm -rf "$O" && mkdir -p "$O/inc" "$O/bld"
python3 -c 'import sys, zipfile, os
z = zipfile.ZipFile(sys.argv[1])
for i in z.infolist():   # (zipfile drops the modes: configure and autosetup need their execute bits)
    p = z.extract(i, sys.argv[2]); m = i.external_attr >> 16
    if m and not i.is_dir(): os.chmod(p, m & 0o777)' "$R/build/sqlite-src-$V.zip" "$O"
mv "$O/sqlite-src-$V" "$O/src"
cp build/gen/qc_dec.h "$O/inc/"
cd "$O/bld"
../src/configure > configure.log 2>&1
make sqlite3.c > amal.log 2>&1
python3 "$R/qc/patch.py" --step-hook sqlite3.c sqlite3.c.qc
printf '\n#include "qc.c"   /* cursed-sqlite-jit */\n#include "tcl_qc.c"\n' >> sqlite3.c.qc
mv sqlite3.c.qc sqlite3.c && touch sqlite3.c
make -j"${JOBS:-4}" testfixture OPTS="-I$R/qc -I$R/tests -I$O/inc" > make.log 2>&1 || { tail -30 make.log; exit 1; }
echo "build-tcl: $O/bld/testfixture"
