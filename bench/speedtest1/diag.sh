#!/bin/sh
# diag.sh <arm> <round> [profile]: the instrumented speedtest1 (instrument.py, st1_instr.h) for one arm, at --size 100
# and --size 1000, per-test user-mode instructions and cycles (root, or perf_event_paranoid <= 2) and the prepare /
# first-run / loop split; QCS_STATS and QC_STATS=1 for which tier ran each statement. "profile": instead, --size 100
# under perf record (CLOCK_MONOTONIC), then each test's top symbols from perf report --time over that test's interval.
# Outputs in build/bench/st1diag/: <arm>.s<size>.<round>.{st1i,txt,stats,qcstats}, prof.<arm>.<round>/<order>-<test>.txt.
# bench/speedtest1/diag.py summarises.
set -e
BR=$(cd "$(dirname "$0")/../.." && pwd); . "$BR/bench/lib.sh"
ARM=$1; R=$2; MODE=${3:-sizes}
O=$BB/st1diag; S=$BB/speedtest1; mkdir -p "$O" "$S"
[ -f "$S/speedtest1.c" ] || { sh "$BR/scripts/fetch-sqlite-src.sh" > /dev/null
  unzip -p "$BR/build/sqlite-src-3540100.zip" sqlite-src-3540100/test/speedtest1.c > "$S/speedtest1.c"; }
python3 "$BR/bench/speedtest1/instrument.py" "$S/speedtest1.c" "$S/st1i.c"
v=serve; [ "$ARM" = stock ] && v=stock
bench_link $v "$S/st1i-$v" -I"$BR/bench/speedtest1" "$S/st1i.c"
case $ARM in qvm) export QC_VM_ONLY=1 ;; off) export QCS_OFF=1 ;; esac
export QC_STATS=1
DB=${BENCH_TMP:-/tmp}/st1diag.db
if [ "$MODE" = profile ]; then
  P=$O/prof.$ARM.$R; mkdir -p "$P"; rm -f "$DB"*
  ST1I_OUT=$O/$ARM.p100.$R.st1i QCS_STATS=$O/$ARM.p100.$R.stats perf record -q -k CLOCK_MONOTONIC -F 2999 -o "$P/perf.data" \
    "$S/st1i-$v" --verify --size 100 "$DB" > "$O/$ARM.p100.$R.txt" 2> "$O/$ARM.p100.$R.qcstats"
  k=0
  while read -r tag test ins cyc prep first loop exec np nr ne t0 t1; do
    [ "$tag" = ST1I ] || continue
    k=$((k + 1)); test=$(printf '%02d-%s' $k "$test")   # (run order first: mix1's testsets repeat test numbers)
    perf report -i "$P/perf.data" --time "$t0,$t1" --sort dso,symbol --stdio --percent-limit 1.5 2> /dev/null \
      | grep -v '^#' | grep -v '^$' | head -25 > "$P/$test.txt" || true
  done < "$O/$ARM.p100.$R.st1i"
  rm -f "$P/perf.data"
else
  for size in 100 1000; do
    rm -f "$DB"*
    ST1I_OUT=$O/$ARM.s$size.$R.st1i QCS_STATS=$O/$ARM.s$size.$R.stats "$S/st1i-$v" --verify --size $size "$DB" \
      > "$O/$ARM.s$size.$R.txt" 2> "$O/$ARM.s$size.$R.qcstats"
    echo "diag: $ARM size $size round $R: $(grep TOTAL "$O/$ARM.s$size.$R.txt" | tr -s ' .' ' ')"
  done
fi
