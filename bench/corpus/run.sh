#!/bin/sh
# corpus/run.sh check|speed [rounds] [projects...]: the query corpus (bench/corpus/projects, 1,306 statements from 44
# applications; WAVE=1 the 27 wave-1 ones, 803 statements, as corpus1-7; heavy statements only with HEAVY=1: prep.py)
# through bench/corpus/corpus.c, stock against turbo serving inside sqlite3_step (the native build, QC_SERVE=1, the
# shipped defaults otherwise). Both builds add FTS4/FTS5 and percentile() and allow double-quoted strings (the corpus
# needs them; the CLI it was recorded with has them) to the usual options; corpus.c adds regexp() (SQLite's ext/misc/regexp.c, as the CLI). TZ=UTC, as
# tools/run.py.
#   check   every statement 8 times per arm (corpus.c check) on copies of one database per project; then
#           compare.py: rows (in order where the statement has ORDER BY), changes and errors must equal stock's
#   speed   hot (prepared once) and prep (prepare + step + finalize each time) per arm and round, perf counters
#           (QRUN-style, needs perf_event_paranoid <= 2 or root): <arm>.<mode>.<round>.tsv; parity.py-style summary
#           with bench/corpus/summarise.py
#   diag    ID=<statement> (its project's database only): per arm, the statement's EXPLAIN QUERY PLAN and EXPLAIN as
#           SQLite plans it and under QPSG (corpus.c explain), then one hot run of REPS with QC_STATS=1:
#           <arm>.diag.txt
#   cg      callgrind instead of perf (deterministic instructions, any Linux; slow, so for small sets: IDS): per arm and
#           project, hot and prep under valgrind --tool=callgrind with REPS (default 20) executions each after an uncounted
#           one, counted as in speed (corpus.c -DCORPUS_CALLGRIND, -O2 without -march/-mcpu: its own build directory;
#           the serve arms with QC_NOADAPT=1; IDS statements at 2 ms stock or more, REPS_FEW (default 5) executions),
#           into
#           <arm>.<mode>.1.tsv (instructions; times are valgrind's), then fast.py's report against stock
#   prof    ID=<statement>: per arm, REPS (default 30) hot executions under perf record (the -g build, its own build
#           directory; PROF_EVENTS, default "cycles:ppu r019c:u", one record each, a plain user-mode cycles count when
#           an event fails), then perf report --no-children (top symbols) and perf annotate of PROF_SYM (default
#           qv_region) with source lines: <arm>.<event>.report.txt, <arm>.<event>.annotate.txt
# IDS=<file>: only those statements (bench/corpus/losers.tsv: the loser set; prep.py), output in corpus-<file's name>.
# ROTATE=1 (speed): the arms' order rotates by round (several arms in one run, as the corpusfast Xeon workload).
# ARMS (default "stock serve"; also servevm = serve with QC_VM_ONLY=1, noreoffer = serve with QC_NOREOFFER=1, servenoadapt = serve with QC_NOADAPT=1, servestream = serve with QC_STREAM=1, nostream = serve with QC_STREAM=0 (streaming is the default since 5497a19), streamnoadapt = both, margin1 = serve with QC_ADAPT_MARGIN=1.0, margin1all = that and QC_ADAPT_MIN_US=0, park = serve with QC_PARK=1, min0 = serve with QC_ADAPT_MIN_US=0, min5 = with QC_ADAPT_MIN_US=5, min0stats = that with QC_STATS=1 QC_STATS_ADAPT=1 (to stderr: the log), noadaptstats = QC_NOADAPT=1 with QC_STATS=1, adaptstats = serve with QC_STATS=1 QC_STATS_ADAPT=1 (adapt's decisions, to stderr: the log), small = serve with QC_ADAPT_SMALL_US=20, alignoff = the native build again with ALIGN_CFLAGS (default -falign-functions=64 -falign-loops=32) and QC_SERVE=0, noinlineoff = it without patch.py's always_inline on sqlite3Step, QC_SERVE=0), MODES (speed: default "hot prep"), R0, KEEP as the other run.sh; REPS (default
# 200) and BUDGET (ms per statement and mode, default 60); SCALE (default 1). CORPUS_ASAN=1: both builds with
# AddressSanitizer (check only; its own build directory). Output in build/bench/corpus (or build/bench-asan/corpus).
set -e
BR=$(cd "$(dirname "$0")/../.." && pwd)
[ "${1:-}" = prof ] && BENCH_BUILD=${BENCH_BUILD:-$BR/build/bench-corpus-prof}
[ -n "${CORPUS_ASAN:-}" ] && { BENCH_BUILD=$BR/build/bench-asan; CC=${CC:-gcc}; BENCH_CFLAGS="-O1 -g -fno-omit-frame-pointer -fsanitize=address"; }
[ "${1:-}" = cg ] && { BENCH_BUILD=${BENCH_BUILD:-$BR/build/bench-corpus-cg}; : "${BENCH_ARCH=}"; }
BENCH_BUILD=${BENCH_BUILD:-$BR/build/bench-corpus}
. "$BR/bench/lib.sh"
[ "${1:-}" = prof ] && BENCH_CFLAGS="$BENCH_CFLAGS -g"   # (prof: debug info for perf annotate's source lines; the code is the same)
BENCH_SQLOPTS="$(echo "$BENCH_SQLOPTS" | sed 's/-DSQLITE_DQS=0/-DSQLITE_DQS=3/') -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_PERCENTILE"   # (the apps' SQL uses double-quoted strings, as the CLI allows)
export TZ=UTC
MODE=${1:?usage: corpus/run.sh check|speed|diag|prof|cg [rounds] [projects...]}; shift
N=1; [ "$MODE" = speed ] && { N=${1:-1}; shift || true; }
O=$BB/corpus${IDS:+-$(basename "$IDS" .tsv)}; D=$O/db; mkdir -p "$O" "$D"
[ -n "${IDS:-}" ] && { IDS=$(cd "$(dirname "$IDS")" && pwd)/$(basename "$IDS"); export IDS; rm -f "$O"/q/*.q; }
python3 "$BR/bench/corpus/prep.py" "$O/q" "${SCALE:-1}" "$@"
CG=; [ "$MODE" = cg ] && CG=-DCORPUS_CALLGRIND
bench_link stock "$BB/corpus-stock" "$BR/bench/corpus/corpus.c" $CG
bench_link native "$BB/corpus-native" "$BR/bench/corpus/corpus.c" $CG
native_variant() {   # native_variant <name> <extra cflags> <sed script>: the native build again, its sqlite3.c edited, as corpus-native-<name>
  d=$(bench_sqlite native); o=$BB/native-$1; mkdir -p "$o"; sed "$3" "$d/sqlite3.c" > "$o/sqlite3.c"
  (cd "$d" && $CC $BENCH_CFLAGS $2 $BENCH_SQLOPTS -w -I. -c "$o/sqlite3.c" -o "$o/sqlite3.o")
  $CC $BENCH_CFLAGS $2 $BENCH_SQLOPTS -w $CG -I"$d" "$BR/bench/corpus/corpus.c" "$o/sqlite3.o" -o "$BB/corpus-native-$1" -lm -lpthread
  echo "$CC $BENCH_CFLAGS $2 $BENCH_SQLOPTS ($3)" > "$o/cflags.txt"
}
case " ${ARMS:-} " in *" alignoff "*)   # (layout against what qc's hooks cost: the same code aligned)
  native_variant align "${ALIGN_CFLAGS:--falign-functions=64 -falign-loops=32}" '' ;; esac
case " ${ARMS:-} " in *" noinlineoff "*)   # (sqlite3Step without patch.py's always_inline into sqlite3_step)
  native_variant noinline '' 's|^__attribute__((always_inline)) inline   /\* cursed-sqlite-turbo \*/$||' ;; esac
P=$(cd "$O/q" && ls *.q | sed 's/\.q$//')
[ $# -gt 0 ] && P="$*"
for p in $P; do   # (one database per project, built by the stock build; every arm runs on a fresh copy)
  [ -f "$D/$p.db" ] && [ "$D/$p.db" -nt "$O/q/$p.build.sql" ] || { rm -f "$D/$p.db"; "$BB/corpus-stock" build "$D/$p.db" "$O/q/$p.build.sql"; }
done
T=${BENCH_TMP:-/tmp}/corpus.$$; mkdir -p "$T"
arm_env() {
  b=$BB/corpus-native; unset QC_SERVE QC_VM_ONLY QC_NOREOFFER QC_NOADAPT QC_STREAM QC_ADAPT_MARGIN QC_ADAPT_MIN_US QC_PARK QC_ADAPT_SMALL_US QC_STATS QC_STATS_ADAPT
  case $1 in stock) b=$BB/corpus-stock ;; serve) export QC_SERVE=1 ;; servevm) export QC_SERVE=1 QC_VM_ONLY=1 ;; noreoffer) export QC_SERVE=1 QC_NOREOFFER=1 ;; servenoadapt) export QC_SERVE=1 QC_NOADAPT=1 ;; servestream) export QC_SERVE=1 QC_STREAM=1 ;; nostream) export QC_SERVE=1 QC_STREAM=0 ;; streamnoadapt) export QC_SERVE=1 QC_STREAM=1 QC_NOADAPT=1 ;; margin1) export QC_SERVE=1 QC_ADAPT_MARGIN=1.0 ;; margin1all) export QC_SERVE=1 QC_ADAPT_MARGIN=1.0 QC_ADAPT_MIN_US=0 ;; park) export QC_SERVE=1 QC_PARK=1 ;; min0) export QC_SERVE=1 QC_ADAPT_MIN_US=0 ;; min5) export QC_SERVE=1 QC_ADAPT_MIN_US=5 ;; min0stats) export QC_SERVE=1 QC_ADAPT_MIN_US=0 QC_STATS=1 QC_STATS_ADAPT=1 ;; noadaptstats) export QC_SERVE=1 QC_NOADAPT=1 QC_STATS=1 ;; adaptstats) export QC_SERVE=1 QC_STATS=1 QC_STATS_ADAPT=1 ;; small) export QC_SERVE=1 QC_ADAPT_SMALL_US=20 ;; serveoff) export QC_SERVE=0 ;; alignoff) b=$BB/corpus-native-align; export QC_SERVE=0 ;; noinlineoff) b=$BB/corpus-native-noinline; export QC_SERVE=0 ;;
    *) echo "corpus: unknown arm $1" >&2; exit 2 ;; esac
}
if [ "$MODE" = diag ]; then
  : "${ID:?diag: set ID to a statement id}"; p=$(grep -l "^@@Q $ID " "$O"/q/*.q | head -1); [ -n "$p" ] || { echo "corpus: no statement $ID" >&2; exit 2; }
  for arm in ${ARMS:-stock serve}; do
    arm_env $arm; cp "$D/$(basename "$p" .q).db" "$T/c.db"
    { echo "== $arm: explain"; "$b" explain "$T/c.db" "$p" "$ID"
      echo "== $arm: hot ${REPS:-200}, QC_STATS=1"; QC_STATS=1 "$b" hot "$T/c.db" "$p" "${REPS:-200}" 1e9 "$ID" 2>&1; } > "$O/$arm.diag.txt"
    echo "corpus diag: $arm done"
  done
elif [ "$MODE" = prof ]; then
  : "${ID:?prof: set ID to a statement id}"; p=$(grep -l "^@@Q $ID " "$O"/q/*.q | head -1); [ -n "$p" ] || { echo "corpus: no statement $ID" >&2; exit 2; }
  for arm in ${ARMS:-stock serve}; do
    arm_env $arm; cp "$D/$(basename "$p" .q).db" "$T/c.db"
    for ev in ${PROF_EVENTS:-cycles:ppu r019c:u}; do
      f=$(echo "$ev" | tr -c 'a-zA-Z0-9\n' _); e=$ev
      perf record -q -e "$e" -F 4999 -o "$T/perf.data" -- "$b" hot "$T/c.db" "$p" "${REPS:-30}" 1e9 "$ID" > "$O/$arm.$f.tsv" 2> "$O/$arm.$f.err" \
        || { e=cycles:u; echo "corpus prof: $ev failed, $e instead" >&2; perf record -q -e "$e" -F 4999 -o "$T/perf.data" -- "$b" hot "$T/c.db" "$p" "${REPS:-30}" 1e9 "$ID" > "$O/$arm.$f.tsv" 2>> "$O/$arm.$f.err"; }
      { echo "== $arm $e: perf report --no-children"; perf report -i "$T/perf.data" --no-children --sort symbol --stdio 2> /dev/null | grep -v '^#' | grep -v '^$' | head -40; } > "$O/$arm.$f.report.txt"
      { echo "== $arm $e: perf annotate ${PROF_SYM:-qv_region}"; perf annotate -i "$T/perf.data" -l --stdio -s "${PROF_SYM:-qv_region}" 2>&1; } > "$O/$arm.$f.annotate.txt"
      [ $arm = stock ] && perf annotate -i "$T/perf.data" -l --stdio -s sqlite3VdbeExec > "$O/$arm.$f.vdbeexec.txt" 2>&1 || true
    done
    echo "corpus prof: $arm done"
  done
elif [ "$MODE" = cg ]; then
  [ -n "${KEEP:-}" ] || rm -f "$O"/*.hot.*.tsv "$O"/*.prep.*.tsv "$O"/*.cgraw
  for arm in ${ARMS:-stock serve}; do
    arm_env $arm; : > "$O/$arm.hot.1.tsv"; : > "$O/$arm.prep.1.tsv"; : > "$O/$arm.hot.cgraw"; : > "$O/$arm.prep.cgraw"; s=$(date +%s)
    [ -n "${IDS:-}" ] && export CORPUS_FEW="$(awk -F'\t' '!/^#/ && $8 >= 2 { printf "%s ", $1 }' "$IDS")" CORPUS_FEW_REPS=${REPS_FEW:-5}
    [ $arm = stock ] || export QC_NOADAPT=1   # (under valgrind nearly every plan is over adapt's 50 µs, so it would sample the
                                              #  interpreter in counted runs; natively it doesn't for these: the Xeon covers adapt)
    for p in $P; do
      cp "$D/$p.db" "$T/c.db"
      for m in hot prep; do
        rm -f "$T"/cg.*
        valgrind --tool=callgrind --collect-atstart=no --dump-line=no --callgrind-out-file="$T/cg.%p" \
          "$b" $m "$T/c.db" "$O/q/$p.q" "${REPS:-20}" 1e9 > "$T/t.tsv" 2> "$T/vg.txt" || { echo "corpus: $arm $m $p: exit $?" >&2; tail -5 "$T/vg.txt" >&2; }
        python3 "$BR/bench/corpus/cg.py" "$T/t.tsv" "$T"/cg.* >> "$O/$arm.$m.1.tsv" 2>> "$O/$arm.$m.cgraw"
      done
    done
    echo "corpus cg: $arm done ($(( $(date +%s) - s )) s)"
  done
  python3 "$BR/bench/corpus/fast.py" "$O" ${IDS:+"$IDS"}
elif [ "$MODE" = check ]; then
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
    A=${ARMS:-stock serve}; [ -n "${ROTATE:-}" ] && { set -- $A; k=$(( r % $# )); while [ $k -gt 0 ]; do x=$1; shift; set -- "$@" "$x"; k=$((k - 1)); done; A="$*"; }
    for arm in $A; do
      arm_env $arm
      : > "$O/$arm.hot.$r.tsv"; : > "$O/$arm.prep.$r.tsv"
      for p in $P; do   # (one copy per project and round: writes roll back, so hot and prep share it)
        cp "$D/$p.db" "$T/c.db"
        for m in ${MODES:-hot prep}; do "$b" $m "$T/c.db" "$O/q/$p.q" "${REPS:-200}" "${BUDGET:-60}" >> "$O/$arm.$m.$r.tsv" || echo "corpus: $arm $m $p: exit $?" >&2; done
      done
      echo "corpus speed: $arm round $r done"
    done
  done
fi
rm -rf "$T"
