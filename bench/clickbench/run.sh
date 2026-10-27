#!/bin/sh
# clickbench/run.sh [rows] [rounds] [reps]: ClickBench's 43 queries (its sqlite/ entry, pinned) on the first <rows>
# records of hits (default 1,000,000; bench/clickbench/fetch.sh), loaded as ClickBench loads SQLite (create.sql, then
# every field imported as text). Three arms in alternation, one process per arm and round, through bench/qrun.c as
# bench/tpch/run.sh does; bench/compare.py checks that every query's rows are identical across arms.
set -e
# ARMS="stock turbo qvm" (default) picks arms (also: off = the turbo binary with QCS_OFF=1, qc never runs; main = turbo under another label, for a second turbo build in the same series); KEEP=1 keeps earlier rounds' outputs; R0=<n> numbers rounds from n.
BR=$(cd "$(dirname "$0")/../.." && pwd); . "$BR/bench/lib.sh"
ROWS=${1:-1000000}; N=${2:-3}; REPS=${3:-2}
D=${BENCH_DATA:-$BR/build/bench/data}/clickbench; O=$BB/clickbench/r$ROWS; mkdir -p "$O"
DB=$D/hits-$ROWS.db
if [ ! -f "$DB" ]; then
  sh "$BR/bench/clickbench/fetch.sh" "$ROWS"
  bench_link stock "$BB/clickbench-load" "$BR/bench/clickbench/load.c"
  rm -f "$DB.tmp"; "$BB/clickbench-load" "$DB.tmp" "$D/create.sql" "$D/hits-$ROWS.csv"
  mv "$DB.tmp" "$DB"
fi
awk '/[^ \t]/ { printf "-- name: Q%02d\n%s\n", n++, $0 }' "$D/queries.sql" > "$O/queries.sql"   # (one query a line; ClickBench numbers them from 0)
case " ${ARMS:-stock} " in *" stock "*) bench_link stock "$BB/qrun-stock" "$BR/bench/qrun.c" ;; esac
case " ${ARMS:-turbo} " in *" turbo "*|*" qvm "*|*" off "*|*" main "*|*" notxn "*) bench_link serve "$BB/qrun-serve" "$BR/bench/qrun.c" ;; esac
[ -n "${KEEP:-}" ] || rm -f "$O"/*.tsv "$O"/*.stats
for r in $(seq "${R0:-1}" $(( ${R0:-1} + N - 1 ))); do
  for arm in ${ARMS:-stock turbo qvm}; do
    b=$BB/qrun-serve; [ $arm = stock ] && b=$BB/qrun-stock
    if [ $arm = qvm ]; then export QC_VM_ONLY=1; else unset QC_VM_ONLY; fi
    if [ $arm = off ]; then export QCS_OFF=1; else unset QCS_OFF; fi
    if [ $arm = notxn ]; then export QCS_NOTXN=1; else unset QCS_NOTXN; fi   # (the shim without BEGIN/COMMIT)
    QCS_STATS=$O/$arm.$r.stats "$b" "$DB" "$O/queries.sql" "$REPS" "${BUDGET:-120}" > "$O/$arm.$r.tsv" || true
    echo "clickbench r$ROWS: $arm round $r done"
  done
done
unset QC_VM_ONLY QCS_OFF
python3 "$BR/bench/compare.py" "$O"
