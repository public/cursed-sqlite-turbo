#!/bin/bash
# box-run.sh: the run.sh of a bench/xeon/payload.sh payload, on a Xeon box of cursed-http's broker (synteq-experiments
# contract: $WORK, $OUT, $DEADLINE; 1 vCPU, 180 s including the build). One workload, one arm, one round (PARAMS).
# Builds with ccache (relative paths, so runs share it), clang, -mbranches-within-32B-boundaries on every arm.
set -u
cd "$WORK"; . ./PARAMS   # WL, ARM, ROUND, REPS
CC=clang; command -v ccache > /dev/null && CC="ccache clang"
export CC BENCH_TMP=$WORK/tmp BENCH_DATA=$WORK/data
[ -d /var/cache/xexp/ccache ] && export CCACHE_DIR=/var/cache/xexp/ccache
mkdir -p "$BENCH_TMP" "$BENCH_DATA" "$OUT"
{ echo "WL=$WL ARM=$ARM ROUND=$ROUND"; clang --version | head -1; uname -r; nproc; grep -m1 'model name' /proc/cpuinfo; } > "$OUT/env.txt"
left() { echo $(( DEADLINE - $(date +%s) - 8 )); }
t0=$(date +%s)
case $WL in
  build)   # (warms the box's ccache: both objects, as the workloads build them)
    for v in stock serve; do ( BR=$WORK; . bench/lib.sh; s=$(date +%s); bench_sqlite $v > /dev/null; echo "$v $(( $(date +%s) - s )) s" ) >> "$OUT/log.txt" 2>&1; done ;;
  speedtest1)
    ARMS=$ARM R0=$ROUND timeout "$(left)" sh bench/speedtest1/run.sh 1 > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp build/bench/speedtest1/*.txt build/bench/speedtest1/*.stats "$OUT/" 2>/dev/null ;;
  tpch)
    D=build/bench/tpch/dbgen
    if [ ! -x "$D/dbgen" ]; then
      make -C "$D" CC="${CC% clang} gcc" DATABASE=POSTGRESQL MACHINE=LINUX WORKLOAD=TPCH CFLAGS="-O2 -fcommon -DDBNAME=\\\"dss\\\" -DLINUX -DPOSTGRESQL -DTPCH -DRNG_TEST -D_FILE_OFFSET_BITS=64 -w" dbgen > "$OUT/dbgen-make.log" 2>&1
      cat "$D/COMMIT" > "$D/VERSION"
    fi
    ARMS=$ARM R0=$ROUND BUDGET=20 timeout "$(left)" sh bench/tpch/run.sh 0.1 1 "$REPS" > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp build/bench/tpch/sf0.1/*.tsv build/bench/tpch/sf0.1/*.stats "$OUT/" 2>/dev/null ;;
  clickbench)   # (a 300k-row prefix: 46 MB downloaded on the box, pinned; bench/clickbench/fetch.sh)
    ARMS=$ARM R0=$ROUND BUDGET=20 timeout "$(left)" sh bench/clickbench/run.sh "${ROWS:-300000}" 1 "$REPS" > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp build/bench/clickbench/r${ROWS:-300000}/*.tsv build/bench/clickbench/r${ROWS:-300000}/*.stats "$OUT/" 2>/dev/null ;;
esac
cp build/bench/stock/cflags.txt "$OUT/cflags-stock.txt" 2>/dev/null; cp build/bench/serve/cflags.txt "$OUT/cflags-serve.txt" 2>/dev/null
echo "wall $(( $(date +%s) - t0 )) s" >> "$OUT/env.txt"
