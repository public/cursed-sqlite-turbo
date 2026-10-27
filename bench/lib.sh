# lib.sh (sourced): build helpers shared by bench/*/run.sh and tests/sqlancer/.
#   bench_sqlite <variant>   build/bench/<variant>/sqlite3.o (stock | serve | native | diff; bench/build-sqlite.sh), echoes its dir
#   bench_link <variant> <out> <sources...>   a program against that SQLite
# CC defaults to clang; one set of options for every variant (the repo Makefile's), so only the executor differs. On
# x86-64 both arms get -mbranches-within-32B-boundaries (the JCC erratum: alignment alone can move a loop 15 %).
BR=${BR:?set BR to the repo root before sourcing bench/lib.sh}
: "${CC:=clang}"
BENCH_SQLOPTS="-DSQLITE_THREADSAFE=0 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 -DSQLITE_DQS=0 \
 -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_USE_ALLOCA -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_DEPRECATED \
 -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_ENABLE_MATH_FUNCTIONS"
if [ -z "${BENCH_ARCH+x}" ]; then
  case $(uname -m) in
    x86_64) BENCH_ARCH="-march=native"
            $CC -mbranches-within-32B-boundaries -x c -c /dev/null -o /dev/null 2>/dev/null && BENCH_ARCH="$BENCH_ARCH -mbranches-within-32B-boundaries" ;;
    *) BENCH_ARCH="-mcpu=native" ;;
  esac
fi
: "${BENCH_CFLAGS:=-O2 $BENCH_ARCH}"
BB=${BENCH_BUILD:-$BR/build/bench}
bench_sqlite() {
  d=$BB/$1
  if [ ! -f "$d/sqlite3.o" ] || [ "$BR/bench/qc_serve.c" -nt "$d/sqlite3.o" ] || [ "$BR/qc/qc.c" -nt "$d/sqlite3.o" ] \
     || [ "$BR/qc/qvm.c" -nt "$d/sqlite3.o" ] || [ "$BR/qc/qcg.c" -nt "$d/sqlite3.o" ] || [ "$BR/qc/qvm_run.h" -nt "$d/sqlite3.o" ]; then
    sh "$BR/bench/build-sqlite.sh" "$1" "$d" >&2
    (cd "$d" && $CC $BENCH_CFLAGS $BENCH_SQLOPTS -w -I. -c sqlite3.c -o sqlite3.o)
    echo "$CC $BENCH_CFLAGS $BENCH_SQLOPTS" > "$d/cflags.txt"
  fi
  echo "$d"
}
bench_link() {
  v=$1; out=$2; shift 2; d=$(bench_sqlite "$v")
  $CC $BENCH_CFLAGS $BENCH_SQLOPTS -w -I"$d" "$@" "$d/sqlite3.o" -o "$out" -lm -lpthread
}
