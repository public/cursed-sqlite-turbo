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
export QC_STATS=1   # (the engine's own counters, to stderr at exit: log.txt)
{ echo "WL=$WL ARM=$ARM ROUND=$ROUND"; clang --version | head -1; uname -r; nproc; grep -m1 'model name' /proc/cpuinfo; } > "$OUT/env.txt"
dbgen() {   # (TPC-H's dbgen from the shipped sources, once)
  D=build/bench/tpch/dbgen
  if [ ! -x "$D/dbgen" ]; then
    make -C "$D" CC="${CC% clang} gcc" DATABASE=POSTGRESQL MACHINE=LINUX WORKLOAD=TPCH CFLAGS="-O2 -fcommon -DDBNAME=\\\"dss\\\" -DLINUX -DPOSTGRESQL -DTPCH -DRNG_TEST -D_FILE_OFFSET_BITS=64 -w" dbgen > "$OUT/dbgen-make.log" 2>&1
    cat "$D/COMMIT" > "$D/VERSION"
  fi
}
left() { echo $(( DEADLINE - $(date +%s) - 8 )); }
t0=$(date +%s)
case $WL in
  parity)   # (the parity bar: bench/small at 20,000 executions per statement, both modes, with user-mode counters, then
            #  speedtest1 under perf stat; needs root for the counters (perf_event_paranoid 4))
    dbgen
    ARMS=$ARM R0=$ROUND QRUN_PERF=1 timeout "$(left)" sh bench/small/run.sh 1 "${REPS:-20000}" > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp build/bench/small/*.tsv build/bench/small/*.stats "$OUT/" 2>/dev/null
    if [ "$ARM" = direct ]; then echo "speedtest1: skipped (direct is qrun only)" >> "$OUT/log.txt"
    else
      b=build/bench/speedtest1/speedtest1-serve; [ "$ARM" = stock ] && b=build/bench/speedtest1/speedtest1-stock
      case $ARM in serve|serveoff|servevm) b=build/bench/speedtest1/speedtest1-native ;; esac
      ARMS=$ARM R0=$ROUND timeout "$(left)" sh bench/speedtest1/run.sh 0 > /dev/null 2>&1   # (builds it)
      case $ARM in qvm) export QC_VM_ONLY=1 ;; off) export QCS_OFF=1 ;; notxn) export QCS_NOTXN=1 ;;
                   serve) export QC_SERVE=1 ;; serveoff) export QC_SERVE=0 ;; servevm) export QC_SERVE=1 QC_VM_ONLY=1 ;; esac
      rm -f "$BENCH_TMP"/st.db*
      P="perf stat -x, -e instructions:u,cycles:u -o $OUT/perf-$ARM.$ROUND.txt"; command -v perf > /dev/null || P=
      timeout "$(left)" $P "$b" --verify --size 100 "$BENCH_TMP/st.db" > "$OUT/$ARM.$ROUND.txt" 2>&1   # (no QCS_STATS: timing)
      echo "speedtest1 exit $?" >> "$OUT/log.txt"
    fi ;;
  st1diag|st1prof)   # (speedtest1 diagnosis: bench/speedtest1/diag.sh; root for the counters and perf record)
    m=sizes; [ "$WL" = st1prof ] && m=profile
    timeout "$(left)" sh bench/speedtest1/diag.sh "$ARM" "$ROUND" $m > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp -r build/bench/st1diag/* "$OUT/" 2>/dev/null ;;
  corpus)   # (the query corpus, bench/corpus, hot and prepare+step, one arm; PROJ: a share of the projects, to fit the time
            #  limit; QC_STATS off: the shipped defaults; root for the per-statement perf counters)
    unset QC_STATS
    ARMS=$ARM R0=$ROUND REPS=${REPS:-200} BUDGET=${BUDGET:-40} timeout "$(left)" sh bench/corpus/run.sh speed 1 ${PROJ:-} > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp build/bench-corpus/corpus/*.tsv "$OUT/" 2>/dev/null; cp build/bench-corpus/native/cflags.txt "$OUT/cflags-native.txt" 2>/dev/null ;;
  corpusfast)   # (the loser set, bench/corpus/losers.tsv: one build, then N rounds of every arm in ARMS, their order
                #  rotated by round; the confirmation step of the fast loop, against corpus's one arm per run; root for perf)
    unset QC_STATS; S=losers; [ -n "${CORPUS_EXTRA:-}" ] && export CORPUS_EXTRA   # (SUBSET="id id ...": only those statements, a confirm on a handful; cause "other" outside the loser set)
    [ -n "${SUBSET:-}" ] && { S=subset; for i in $SUBSET; do grep "^$i	" bench/corpus/losers.tsv || printf '%s\t-\tother\n' "$i"; done > bench/corpus/subset.tsv; }
    IDS=bench/corpus/$S.tsv ARMS="${ARMS:-stock serve}" ROTATE=1 REPS=${REPS:-200} BUDGET=${BUDGET:-30} MODES="${MODES:-hot prep}" timeout "$(left)" sh bench/corpus/run.sh speed "${N:-5}" > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp build/bench-corpus/corpus-$S/*.tsv "$OUT/" 2>/dev/null; cp build/bench-corpus/native/cflags.txt "$OUT/cflags-native.txt" 2>/dev/null
    python3 bench/corpus/fast.py build/bench-corpus/corpus-$S bench/corpus/$S.tsv > "$OUT/fast.txt" 2>&1 ;;
  corpuscg)   # (the loser set under callgrind: deterministic instructions, so no perf counters and no root; ARMS in one
              #  run; needs valgrind on the box)
    unset QC_STATS
    IDS=bench/corpus/losers.tsv ARMS="${ARMS:-stock serve}" REPS=${REPS:-20} timeout "$(left)" sh bench/corpus/run.sh cg > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp build/bench-corpus-cg/corpus-losers/*.tsv build/bench-corpus-cg/corpus-losers/*.cgraw "$OUT/" 2>/dev/null; cp build/bench-corpus-cg/native/cflags.txt "$OUT/cflags-native.txt" 2>/dev/null ;;
  corpusdiag)   # (one statement, ID: EXPLAIN plain and under QPSG, and a hot run with QC_STATS=1; root for perf)
    ARMS=$ARM REPS=${REPS:-200} ID=$ID timeout "$(left)" sh bench/corpus/run.sh diag ${PROJ:-} > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp build/bench-corpus/corpus/*.diag.txt "$OUT/" 2>/dev/null; cp build/bench-corpus/native/cflags.txt "$OUT/cflags-native.txt" 2>/dev/null ;;
  build)   # (warms the box's ccache: both objects, as the workloads build them)
    for v in stock serve; do ( BR=$WORK; . bench/lib.sh; s=$(date +%s); bench_sqlite $v > /dev/null; echo "$v $(( $(date +%s) - s )) s" ) >> "$OUT/log.txt" 2>&1; done ;;
  speedtest1)
    ARMS=$ARM R0=$ROUND timeout "$(left)" sh bench/speedtest1/run.sh 1 ${ST_OPTS:-} > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp build/bench/speedtest1/*.txt build/bench/speedtest1/*.stats "$OUT/" 2>/dev/null ;;
  tpch)
    dbgen
    ARMS=$ARM R0=$ROUND BUDGET=20 timeout "$(left)" sh bench/tpch/run.sh 0.1 1 "$REPS" > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp build/bench/tpch/sf0.1/*.tsv build/bench/tpch/sf0.1/*.stats "$OUT/" 2>/dev/null ;;
  clickbench)   # (a 300k-row prefix: 46 MB downloaded on the box, pinned; bench/clickbench/fetch.sh)
    ARMS=$ARM R0=$ROUND BUDGET=20 timeout "$(left)" sh bench/clickbench/run.sh "${ROWS:-300000}" 1 "$REPS" > "$OUT/log.txt" 2>&1; echo "exit $?" >> "$OUT/log.txt"
    cp build/bench/clickbench/r${ROWS:-300000}/*.tsv build/bench/clickbench/r${ROWS:-300000}/*.stats "$OUT/" 2>/dev/null ;;
esac
cp build/bench/stock/cflags.txt "$OUT/cflags-stock.txt" 2>/dev/null; cp build/bench/serve/cflags.txt "$OUT/cflags-serve.txt" 2>/dev/null; cp build/bench/native/cflags.txt "$OUT/cflags-native.txt" 2>/dev/null
echo "wall $(( $(date +%s) - t0 )) s" >> "$OUT/env.txt"
