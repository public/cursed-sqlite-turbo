#!/bin/sh
# speedtest1/run.sh [rounds] [speedtest1 options...]: SQLite's own benchmark (test/speedtest1.c from the pinned source
# tree, scripts/fetch-sqlite-src.sh), unchanged, linked three ways and run in alternation, one arm at a time:
#   stock  the plain amalgamation         turbo  bench/qc_serve.c, plans first         qvm  the same with QC_VM_ONLY=1
# Every run uses --verify, and the verification hashes (a hash of every result row speedtest1 reads) must match across
# arms. Output: build/bench/speedtest1/<arm>.<round>.txt and .stats (qc's counters), summarised by summarise.py.
# Default options: --testset main --size 100 (speedtest1's defaults) on a file database in $BENCH_TMP (default /tmp: in Docker, the container's own disk, not the bind mount).
set -e
# ARMS="stock turbo qvm" (default) picks arms; KEEP=1 keeps earlier rounds' outputs; R0=<n> numbers rounds from n.
BR=$(cd "$(dirname "$0")/../.." && pwd); . "$BR/bench/lib.sh"
N=${1:-3}; [ $# -gt 0 ] && shift
OPTS=${*:---size 100}
O=$BB/speedtest1; mkdir -p "$O"
[ -f "$O/speedtest1.c" ] || { sh "$BR/scripts/fetch-sqlite-src.sh" > /dev/null
  unzip -p "$BR/build/sqlite-src-3540100.zip" sqlite-src-3540100/test/speedtest1.c > "$O/speedtest1.c"; }
case " ${ARMS:-stock} " in *" stock "*) bench_link stock "$O/speedtest1-stock" "$O/speedtest1.c" ;; esac
case " ${ARMS:-turbo} " in *" turbo "*|*" qvm "*) bench_link serve "$O/speedtest1-serve" "$O/speedtest1.c" ;; esac
[ -n "${KEEP:-}" ] || rm -f "$O"/*.txt "$O"/*.stats
for r in $(seq "${R0:-1}" $(( ${R0:-1} + N - 1 ))); do
  for arm in ${ARMS:-stock turbo qvm}; do
    b=$O/speedtest1-serve; [ $arm = stock ] && b=$O/speedtest1-stock
    DB=${BENCH_TMP:-/tmp}/speedtest1.db; rm -f "$DB" "$DB-wal" "$DB-shm" "$DB-journal"
    if [ $arm = qvm ]; then export QC_VM_ONLY=1; else unset QC_VM_ONLY; fi
    QCS_STATS=$O/$arm.$r.stats "$b" --verify $OPTS "$DB" > "$O/$arm.$r.txt" 2>&1
    echo "speedtest1: $arm round $r: $(grep -E 'TOTAL' "$O/$arm.$r.txt" | tr -s ' .' ' ')"
  done
done
unset QC_VM_ONLY
python3 "$BR/bench/speedtest1/summarise.py" "$O"
