#!/bin/sh
# wasm/build.sh [tests] [jsapi] [wasi]: qc + qvm as WebAssembly, opt-in; the native build does not change. Everything
# lands in build/wasm/ (not in git). Default: tests jsapi.
#   tests   the test programs for Node, with the host file system (-sNODERAWFS): corpus.js, qtest.js, qbench.js and,
#           when the sqllogictest sources are there (SLT_DIR, default third_party/slt; scripts/fetch-slt.sh),
#           slt/sqllogictest.js. Run them with wasm/run-tests.sh.
#   jsapi   SQLite's own JS API bundle (ext/wasm from the pinned source tree, scripts/fetch-sqlite-src.sh), twice, both
#           -O2: jsapi/stock (SQLite as released) and jsapi/jit, the qc bundle (the patched amalgamation + qc.c + wasm/qc_wasm.c).
#           Each has sqlite3.mjs + sqlite3.wasm; wasm/qc.mjs adds qc to the qc bundle's oo1 statements. ext/wasm's extra
#           wasm-opt pass is skipped (bin.wasm-opt=): its --all-features makes binaryen write the compact import
#           section, which Node 24 can't load; emcc's own -O2 wasm-opt pass still runs, and llvm-objcopy strips the
#           debug info that pass would have.
#   wasi    corpus.wasm for WASI (wasi-sdk), run by wasm/run-tests.sh under Node's WASI or wasmtime.
# The toolchains are pinned Docker images, run on CPUs 8-11 (WASM_CPUS; at most 4 cores locally). EMSDK_IMAGE and
# WASI_IMAGE override them; EMCC=emcc uses an emcc on the PATH instead, for the tests and jsapi targets.
# QC_WASM_SIMD=1 builds with WASM SIMD128 (-msimd128 -msse2: qc's SSE2 JSON escaper through Emscripten's
# SSE2-on-SIMD128 headers); without it qc takes its scalar paths.
set -e
cd "$(dirname "$0")/.."
EMSDK_IMAGE=${EMSDK_IMAGE:-emscripten/emsdk:6.0.12@sha256:77638e6c215a65f25a704c0c831d5c2463a8c0468a58c6cb82489dbe621dfa05}
WASI_IMAGE=${WASI_IMAGE:-ghcr.io/webassembly/wasi-sdk:wasi-sdk-34@sha256:52595085a0ffbaf574d8d678a9aa81305f0b3af81c639291f15bc7713e42848e}
SLT_DIR=${SLT_DIR:-third_party/slt}
O=${WASM_OUT:-build/wasm}   # (QC_WASM_SIMD=1 WASM_OUT=build/wasm-simd keeps both builds)
TARGETS=${*:-tests jsapi}
mkdir -p "$O"
[ -f build/gen/sqlite3.c ] && [ -f build/gen/qc_dec.h ] || make build/gen/sqlite3.c build/gen/qc_dec.h

# run a command with the toolchain, in this directory (mounted at /w in the container)
dock() { img=$1; shift; docker run --rm --cpuset-cpus ${WASM_CPUS:-8-11} -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/w" -w /w "$img" "$@"; }
em() { if [ -n "${EMCC:-}" ]; then "$@"; else dock "$EMSDK_IMAGE" "$@"; fi; }
OBJCOPY=/emsdk/upstream/bin/llvm-objcopy; [ -n "${EMCC:-}" ] && OBJCOPY=llvm-objcopy

SQLOPTS="-DSQLITE_THREADSAFE=0 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 -DSQLITE_DQS=0"
SQLOPTS="$SQLOPTS -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_USE_ALLOCA -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_DEPRECATED"
SQLOPTS="$SQLOPTS -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_OMIT_DECLTYPE"   # (the Makefile's)
SIMD=; [ "${QC_WASM_SIMD:-0}" = 1 ] && SIMD="-msimd128 -msse2"
# Node, the host's files, a growing heap; qvm's recursion (subprograms, sorter merges) wants more than 64 KB of stack
EMFLAGS="-O2 -w $SIMD -sENVIRONMENT=node -sNODERAWFS=1 -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -sSTACK_SIZE=8MB -sEXIT_RUNTIME=1"

for t in $TARGETS; do case $t in
tests)
  for p in tests/corpus tests/qtest tests/qbench; do
    n=$(basename $p); echo "wasm/build.sh: $O/$n.js"
    em emcc $EMFLAGS $SQLOPTS -Ibuild/gen -Iqc $p.c -o $O/$n.js
  done
  if [ -f "$SLT_DIR/src/sqllogictest.c" ]; then
    S=$O/slt; mkdir -p $S; echo "wasm/build.sh: $S/sqllogictest.js"
    cp "$SLT_DIR/src/sqllogictest.c" "$SLT_DIR/src/sqllogictest.h" "$SLT_DIR/src/md5.c" "$SLT_DIR/src/slt_odbc3.c" $S/
    cp tests/slt_qc.c $S/slt_sqlite.c   # as tests/build-slt.sh: the harness #includes it from its own directory
    em emcc $EMFLAGS -D_GNU_SOURCE -DOMIT_ODBC=1 -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_NO_SYNC=1 \
      -Ibuild/gen -Iqc $S/sqllogictest.c $S/md5.c -o $S/sqllogictest.js
  else
    echo "wasm/build.sh: no $SLT_DIR/src/sqllogictest.c (scripts/fetch-slt.sh, or SLT_DIR=...): sqllogictest skipped"
  fi ;;
jsapi)
  sh scripts/fetch-sqlite-src.sh
  V=$(sed -n 's/^V=//p' scripts/fetch-sqlite-src.sh); T=$O/src/sqlite-src-$V
  if [ ! -f $T/sqlite3.c ]; then
    rm -rf $O/src && mkdir -p $O/src && unzip -q build/sqlite-src-$V.zip -d $O/src
    em sh -c "cd $T && ./configure --disable-tcl > /dev/null && make sqlite3.c > /dev/null"
  fi
  # the qc bundle's amalgamation: the hooks (qc/patch.py), qc.c and the JS API glue in one file, as ext/wasm compiles one unit
  J=$O/jit-src; mkdir -p $J
  python3 qc/patch.py $T/sqlite3.c $J/sqlite3.c.tmp
  cp qc/qc.c qc/qcg.c qc/qvm.c qc/qvm_run.h qc/qvm_par.h qc/qvm_region.h build/gen/qc_dec.h wasm/qc_wasm.c $J/
  printf '\n#include "qc.c"\n#include "qc_wasm.c"\n' >> $J/sqlite3.c.tmp && mv $J/sqlite3.c.tmp $J/sqlite3.c
  cp $T/sqlite3.h $J/
  for v in stock jit; do
    echo "wasm/build.sh: $O/jsapi/$v"
    c=; [ $v = jit ] && c="sqlite3.c=/w/$J/sqlite3.c"
    em sh -c "cd $T/ext/wasm && make clean > /dev/null && make -j4 emcc_opt='-O2 $SIMD' bin.wasm-opt= $c > /w/$O/jsapi-$v.log 2>&1" \
      || { tail -30 $O/jsapi-$v.log; exit 1; }
    mkdir -p $O/jsapi/$v && cp $T/ext/wasm/jswasm/sqlite3.mjs $O/jsapi/$v/
    em $OBJCOPY --strip-debug $T/ext/wasm/jswasm/sqlite3.wasm $O/jsapi/$v/sqlite3.wasm   # (that pass's other job)
  done ;;
wasi)
  echo "wasm/build.sh: $O/wasi/corpus.wasm"; mkdir -p $O/wasi
  # WASI has no mmap/shm (no WAL), no signals, no getpid: SQLite's unix VFS with those parts emulated or left out
  dock "$WASI_IMAGE" sh -c "\$CC -O2 -w $SIMD --target=wasm32-wasip1 -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_GETPID -D_WASI_EMULATED_SIGNAL \
    -D_WASI_EMULATED_PROCESS_CLOCKS $SQLOPTS -DSQLITE_OMIT_WAL -DSQLITE_OMIT_RANDOMNESS -DSQLITE_OS_UNIX=1 -DSQLITE_MAX_MMAP_SIZE=0 \
    -DSQLITE_OMIT_POPEN -DSQLITE_NO_SYNC=1 -Ibuild/gen -Iqc tests/corpus.c -o $O/wasi/corpus.wasm \
    -lwasi-emulated-mman -lwasi-emulated-getpid -lwasi-emulated-signal -lwasi-emulated-process-clocks -Wl,-z,stack-size=8388608" ;;
*) echo "wasm/build.sh: unknown target $t (tests, jsapi, wasi)" >&2; exit 2 ;;
esac; done
