#!/bin/sh
# wasm/run-tests.sh [corpus] [qtest] [jsapi] [slt] [wasi]: the WebAssembly builds (wasm/build.sh) against the
# interpreter, under Node. Default: corpus qtest jsapi. Any difference fails the run.
#   corpus  the 61 query shapes, plans first and QC_VM_ONLY=1 (N= executions per query, default 2000)
#   qtest   rows and JSON bodies, odd values, schema changes (BATCHES=, SEED= as make test)
#   jsapi   wasm/bench.mjs: the jit bundle's qcAll() against stock sqlite3.wasm on the corpus queries (JS_N=, default 200)
#   slt     sqllogictest, both modes (tests/run-slt.sh with the Node build; SLT_FILTER= a grep -e filter on the file
#           names, default all 622 files; JOBS=, default 4: the local limit)
#   wasi    the corpus built with wasi-sdk, both modes, under Node's WASI (wasm/wasi-run.mjs)
# The test database is build/test.db (make db) in rollback-journal mode, copied to $O (WASM_OUT, default build/wasm).
set -e
cd "$(dirname "$0")/.."
O=${WASM_OUT:-build/wasm}; N=${N:-2000}
TARGETS=${*:-corpus qtest jsapi}
[ -f build/test.db ] || make db
if [ ! -f $O/test.db ] || [ build/test.db -nt $O/test.db ]; then
  cp build/test.db $O/test.db && python3 -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('PRAGMA journal_mode=DELETE'); c.close()" $O/test.db
fi
fail=0
check() { if grep -q "$2" "$1"; then echo "  ok: $(grep "$2" "$1" | tail -1)"; else echo "  FAILED: $1"; tail -5 "$1"; fail=1; fi; }
for t in $TARGETS; do case $t in
corpus)
  echo "corpus (plans first)"; node $O/corpus.js $O/test.db $N > $O/corpus.out 2>&1 || true
  check $O/corpus.out '61 of 61 queries compiled; 0 mismatches'
  echo "corpus (QC_VM_ONLY=1)"; QC_VM_ONLY=1 node $O/corpus.js $O/test.db $N > $O/corpus-vm.out 2>&1 || true
  check $O/corpus-vm.out '61 of 61 queries compiled; 0 mismatches' ;;
qtest)
  echo "qtest"; cp $O/test.db $O/t.db && rm -f $O/t.db-journal
  node $O/qtest.js $O/t.db ${BATCHES:-300} ${SEED:-1} > $O/qtest.out 2>&1 || true
  check $O/qtest.out '^OK:' ;;
jsapi)
  echo "jsapi (stock sqlite3.wasm vs the jit bundle's qcAll)"
  WASM_BUILD=$PWD/$O/jsapi node wasm/bench.mjs $O/test.db ${JS_N:-200} > $O/jsapi.out 2>&1 || true
  check $O/jsapi.out ' 0 mismatches' ;;
slt)
  [ -x $O/slt/sqllogictest ] || printf '#!/bin/sh\nexec node "%s/sqllogictest.js" "$@"\n' "$PWD/$O/slt" > $O/slt/sqllogictest
  chmod +x $O/slt/sqllogictest
  for m in plans vm; do
    echo "sqllogictest ($m)"; rm -rf $O/slt-$m
    if [ $m = vm ]; then export QC_VM_ONLY=1; else unset QC_VM_ONLY; fi
    sh tests/run-slt.sh $O/slt/sqllogictest ${SLT_DIR:-third_party/slt}/test $O/slt-$m ${JOBS:-4} "${SLT_FILTER:-.}" > /dev/null
    cat $O/slt-$m/summary.txt
    grep -q ' 0 errors out of' $O/slt-$m/summary.txt && grep -q 'differences 0' $O/slt-$m/summary.txt \
      && grep -q 'exits not 0: 0' $O/slt-$m/summary.txt && grep -q 'leaks: 0' $O/slt-$m/summary.txt || fail=1
  done; unset QC_VM_ONLY ;;
wasi)
  for m in plans vm; do
    echo "corpus under WASI ($m)"
    if [ $m = vm ]; then export QC_VM_ONLY=1; else unset QC_VM_ONLY; fi
    node --no-warnings wasm/wasi-run.mjs $O/wasi/corpus.wasm $O/test.db $N > $O/wasi-$m.out 2>&1 || true
    check $O/wasi-$m.out '61 of 61 queries compiled; 0 mismatches'
  done; unset QC_VM_ONLY ;;
*) echo "wasm/run-tests.sh: unknown target $t (corpus, qtest, jsapi, slt, wasi)" >&2; exit 2 ;;
esac; done
[ $fail = 0 ] && echo "wasm/run-tests.sh: all passed" || { echo "wasm/run-tests.sh: FAILED"; exit 1; }
