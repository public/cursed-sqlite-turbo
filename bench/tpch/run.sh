#!/bin/sh
# tpch/run.sh [SF] [rounds] [reps]: TPC-H at scale factor SF (default 0.1) on SQLite, three arms run in alternation, one
# process per arm and round (stock, turbo = bench/qc_serve.c plans first, qvm = QC_VM_ONLY=1), each running the 22
# queries (bench/tpch/queries.sql) 1 + reps times through bench/qrun.c. Every arm reads the same database file, built
# once per SF by dbgen + bench/tpch/load.c (stock) in $BENCH_DATA (default build/bench/data). Results: one hash per
# query, which must be equal across arms and rounds (bench/compare.py checks), and qc's counters per arm.
set -e
# ARMS="stock turbo qvm" (default) picks arms (also: off = the turbo binary with QCS_OFF=1, qc never runs); KEEP=1 keeps earlier rounds' outputs; R0=<n> numbers rounds from n.
BR=$(cd "$(dirname "$0")/../.." && pwd); . "$BR/bench/lib.sh"
SF=${1:-0.1}; N=${2:-3}; REPS=${3:-3}
D=${BENCH_DATA:-$BR/build/bench/data}; O=$BB/tpch/sf$SF; mkdir -p "$D" "$O"
DB=$D/tpch-sf$SF.db
if [ ! -f "$DB" ]; then
  sh "$BR/bench/tpch/fetch-dbgen.sh"
  G=$D/tpch-sf$SF.tbl; rm -rf "$G"; mkdir -p "$G"
  (cd "$G" && "$BB/tpch/dbgen/dbgen" -b "$BB/tpch/dbgen/dists.dss" -s "$SF" -f -q)
  bench_link stock "$BB/tpch/load" "$BR/bench/tpch/load.c"
  rm -f "$DB.tmp"; "$BB/tpch/load" "$DB.tmp" "$BR/bench/tpch/schema.sql" "$BR/bench/tpch/indexes.sql" "$G"
  mv "$DB.tmp" "$DB"; rm -rf "$G"
fi
python3 -c 'import sys; sf = float(sys.argv[1]); s = open(sys.argv[2]).read(); open(sys.argv[3], "w").write(s.replace("@FRACTION@", repr(0.0001 / sf)))' "$SF" "$BR/bench/tpch/queries.sql" "$O/queries.sql"
case " ${ARMS:-stock} " in *" stock "*) bench_link stock "$BB/qrun-stock" "$BR/bench/qrun.c" ;; esac
case " ${ARMS:-turbo} " in *" turbo "*|*" qvm "*|*" off "*) bench_link serve "$BB/qrun-serve" "$BR/bench/qrun.c" ;; esac
[ -n "${KEEP:-}" ] || rm -f "$O"/*.tsv "$O"/*.stats
for r in $(seq "${R0:-1}" $(( ${R0:-1} + N - 1 ))); do
  for arm in ${ARMS:-stock turbo qvm}; do
    b=$BB/qrun-serve; [ $arm = stock ] && b=$BB/qrun-stock
    if [ $arm = qvm ]; then export QC_VM_ONLY=1; else unset QC_VM_ONLY; fi
    if [ $arm = off ]; then export QCS_OFF=1; else unset QCS_OFF; fi
    QCS_STATS=$O/$arm.$r.stats "$b" "$DB" "$O/queries.sql" "$REPS" "${BUDGET:-120}" > "$O/$arm.$r.tsv" || echo "tpch: $arm round $r: errors (see $O/$arm.$r.tsv)"
    echo "tpch sf$SF: $arm round $r done"
  done
done
unset QC_VM_ONLY QCS_OFF
python3 "$BR/bench/compare.py" "$O"
