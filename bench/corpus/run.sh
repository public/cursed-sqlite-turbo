#!/bin/sh
# corpus/run.sh check|speed [rounds] [projects...]: the sqlite-query-corpus (bench/corpus/corpus, 803 statements from 27
# applications) through bench/corpus/corpus.c, stock against turbo serving inside sqlite3_step (the native build,
# QC_SERVE=1, the shipped defaults otherwise). Both builds add FTS4/FTS5 and allow double-quoted strings (the corpus
# needs them; the CLI it was recorded with has both) to the usual options.
#   check   every statement 8 times per arm (corpus.c check) on copies of one database per project; then
#           compare.py: rows (in order where the statement has ORDER BY), changes and errors must equal stock's
#   speed   hot (prepared once) and prep (prepare + step + finalize each time) per arm and round, perf counters
#           (QRUN-style, needs perf_event_paranoid <= 2 or root): <arm>.<mode>.<round>.tsv; parity.py-style summary
#           with bench/corpus/summarise.py
# ARMS (default "stock serve"; also servevm = serve with QC_VM_ONLY=1), R0, KEEP as the other run.sh; REPS (default
# 200) and BUDGET (ms per statement and mode, default 60); SCALE (default 1). CORPUS_ASAN=1: both builds with
# AddressSanitizer (check only; its own build directory). Output in build/bench/corpus (or build/bench-asan/corpus).
set -e
BR=$(cd "$(dirname "$0")/../.." && pwd)
[ -n "${CORPUS_ASAN:-}" ] && { BENCH_BUILD=$BR/build/bench-asan; CC=${CC:-gcc}; BENCH_CFLAGS="-O1 -g -fno-omit-frame-pointer -fsanitize=address"; }
BENCH_BUILD=${BENCH_BUILD:-$BR/build/bench-corpus}
. "$BR/bench/lib.sh"
BENCH_SQLOPTS="$(echo "$BENCH_SQLOPTS" | sed 's/-DSQLITE_DQS=0/-DSQLITE_DQS=3/') -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5"   # (the apps' SQL uses double-quoted strings, as the CLI allows)
MODE=${1:?usage: corpus/run.sh check|speed [rounds] [projects...]}; shift
N=1; [ "$MODE" = speed ] && { N=${1:-1}; shift || true; }
O=$BB/corpus; D=$O/db; mkdir -p "$O" "$D"
python3 "$BR/bench/corpus/prep.py" "$O/q" "${SCALE:-1}" "$@"
bench_link stock "$BB/corpus-stock" "$BR/bench/corpus/corpus.c"
bench_link native "$BB/corpus-native" "$BR/bench/corpus/corpus.c"
P=$(cd "$O/q" && ls *.q | sed 's/\.q$//')
[ $# -gt 0 ] && P="$*"
for p in $P; do   # (one database per project, built by the stock build; every arm runs on a fresh copy)
  [ -f "$D/$p.db" ] && [ "$D/$p.db" -nt "$O/q/$p.build.sql" ] || { rm -f "$D/$p.db"; "$BB/corpus-stock" build "$D/$p.db" "$O/q/$p.build.sql"; }
done
T=${BENCH_TMP:-/tmp}/corpus.$$; mkdir -p "$T"
arm_env() {
  b=$BB/corpus-native; unset QC_SERVE QC_VM_ONLY
  case $1 in stock) b=$BB/corpus-stock ;; serve) export QC_SERVE=1 ;; servevm) export QC_SERVE=1 QC_VM_ONLY=1 ;; serveoff) export QC_SERVE=0 ;;
    *) echo "corpus: unknown arm $1" >&2; exit 2 ;; esac
}
if [ "$MODE" = check ]; then
  [ -n "${KEEP:-}" ] || rm -f "$O"/*.check.tsv
  for arm in ${ARMS:-stock serve}; do
    arm_env $arm; : > "$O/$arm.check.tsv"
    for p in $P; do cp "$D/$p.db" "$T/c.db"; "$b" check "$T/c.db" "$O/q/$p.q" >> "$O/$arm.check.tsv" || echo "corpus: $arm $p: exit $?" >&2; done
    echo "corpus check: $arm: $(grep -c '^C' "$O/$arm.check.tsv") statements"
  done
  python3 "$BR/bench/corpus/compare.py" "$O" ${ARMS:-stock serve}
else
  [ -n "${KEEP:-}" ] || rm -f "$O"/*.hot.*.tsv "$O"/*.prep.*.tsv
  for r in $(seq "${R0:-1}" $(( ${R0:-1} + N - 1 ))); do
    for arm in ${ARMS:-stock serve}; do
      arm_env $arm
      : > "$O/$arm.hot.$r.tsv"; : > "$O/$arm.prep.$r.tsv"
      for p in $P; do   # (one copy per project and round: writes roll back, so hot and prep share it)
        cp "$D/$p.db" "$T/c.db"
        for m in hot prep; do "$b" $m "$T/c.db" "$O/q/$p.q" "${REPS:-200}" "${BUDGET:-60}" >> "$O/$arm.$m.$r.tsv" || echo "corpus: $arm $m $p: exit $?" >&2; done
      done
      echo "corpus speed: $arm round $r done"
    done
  done
fi
rm -rf "$T"
