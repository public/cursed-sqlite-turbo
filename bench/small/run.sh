#!/bin/sh
# small/run.sh [rounds] [reps]: bench/small/queries.sql on TPC-H SF0.1 (built as bench/tpch/run.sh builds it), each
# statement run 1 + reps times (default 20000) by bench/qrun.c, twice per arm and round: in autocommit (small-ac: the
# drop-in path, a transaction per statement) and inside one transaction (small-tx). QRUN_PERF=1 adds user-mode
# instructions and cycles per execution (needs root or perf_event_paranoid <= 2). ARMS, R0, KEEP as the other run.sh.
# Arms: stock, turbo, qvm, off, main, notxn, serve, servevm, serveoff (as speedtest1/run.sh), and direct (qrun calling qc's embedded API: QRUN_DIRECT). QCS_STATS_ON=1 keeps the
# shim's per-statement stats (its bookkeeping then costs instructions in every start, so the parity runs leave it off).
# bench/parity.py summarises: per query and per class, ratios and their 95 % intervals over rounds.
set -e
BR=$(cd "$(dirname "$0")/../.." && pwd); . "$BR/bench/lib.sh"
N=${1:-3}; REPS=${2:-20000}
D=${BENCH_DATA:-$BR/build/bench/data}; O=$BB/small; mkdir -p "$O"
[ -f "$D/tpch-sf0.1.db" ] || sh "$BR/bench/tpch/run.sh" 0.1 0 > /dev/null
case " ${ARMS:-stock} " in *" stock "*) bench_link stock "$BB/qrun-stock" "$BR/bench/qrun.c" ;; esac
case " ${ARMS:-turbo} " in *" turbo "*|*" qvm "*|*" off "*|*" main "*|*" direct "*|*" notxn "*) bench_link serve "$BB/qrun-serve" "$BR/bench/qrun.c" ;; esac
case " ${ARMS:-turbo} " in *" serve "*|*" serveoff "*|*" servevm "*) bench_link native "$BB/qrun-native" "$BR/bench/qrun.c" ;; esac
[ -n "${KEEP:-}" ] || rm -f "$O"/*.tsv "$O"/*.stats
for r in $(seq "${R0:-1}" $(( ${R0:-1} + N - 1 ))); do
  for arm in ${ARMS:-stock turbo qvm}; do
    b=$BB/qrun-serve; [ $arm = stock ] && b=$BB/qrun-stock
    case $arm in serve|serveoff|servevm) b=$BB/qrun-native ;; esac
    if [ $arm = qvm ] || [ $arm = servevm ]; then export QC_VM_ONLY=1; else unset QC_VM_ONLY; fi
    if [ $arm = off ]; then export QCS_OFF=1; else unset QCS_OFF; fi
    if [ $arm = notxn ]; then export QCS_NOTXN=1; else unset QCS_NOTXN; fi   # (the shim without BEGIN/COMMIT)
    case $arm in serve|servevm) export QC_SERVE=1 ;; serveoff) export QC_SERVE=0 ;; *) unset QC_SERVE ;; esac   # (serving inside SQLite: the native build, no shim)
    if [ $arm = direct ]; then export QRUN_DIRECT=1 QCS_OFF=1 QCS_NOTXN=1; else unset QRUN_DIRECT; fi   # (direct: qc's API, no shim, no BEGIN/COMMIT: qc_exec opens the read transaction)
    for m in ac tx; do
      if [ $m = tx ]; then export QRUN_TXN=1; else unset QRUN_TXN; fi
      QCS_STATS=${QCS_STATS_ON:+$O/$arm.$m.$r.stats} "$b" "$D/tpch-sf0.1.db" "$BR/bench/small/queries.sql" "$REPS" "${BUDGET:-5}" > "$O/$arm.$m.$r.tsv"
    done
    echo "small: $arm round $r done"
  done
done
