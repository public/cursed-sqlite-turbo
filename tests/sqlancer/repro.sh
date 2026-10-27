#!/bin/sh
# repro.sh <sql-file>: replay.c linked with stock SQLite, with turbo (bench/qc_serve.c; plans first and qvm only) and
# with the differential hook (tests/tcl_qc.c, as SQLancer's diff arms; plans first and qvm only), and what differs:
# rows against stock, a crash (exit status), QCTDIFF lines. Run inside bench/docker.sh. Exit 1 if anything differs.
# Needs SQLancer's options for the replay (rtree, fts, math): built with -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_FTS5.
set -e
BR=$(cd "$(dirname "$0")/../.." && pwd)
BENCH_BUILD=${BENCH_BUILD:-$BR/build/bench-repro}
BENCH_SQLOPTS_EXTRA="-DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_STAT4 -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_COLUMN_METADATA"
. "$BR/bench/lib.sh"
BENCH_SQLOPTS="$BENCH_SQLOPTS $BENCH_SQLOPTS_EXTRA"; BENCH_CFLAGS="${REPRO_CFLAGS:--O1 -g}"
for v in stock serve diff; do bench_link $v "$BB/replay-$v" "$BR/tests/sqlancer/replay.c"; done
T=$(mktemp -d); bad=0
REPLAY_DB="$T/r.db" "$BB/replay-stock" "$1" > "$T/stock" 2>&1 || echo "stock: exit $?"
F=$1
for x in "turbo $BB/replay-serve" "qvm $BB/replay-serve QC_VM_ONLY=1" "diff $BB/replay-diff" "diffvm $BB/replay-diff QC_VM_ONLY=1"; do
  set -- $x; n=$1; b=$2; shift 2
  rm -f "$T"/qct.*.txt
  rm -f "$T"/r.db*
  if env "$@" QCT_DIR="$T" REPLAY_DB="$T/r.db" "$b" "$F" > "$T/$n" 2>&1; then :; else echo "== $n: exit $? (crash?)"; tail -2 "$T/$n"; bad=1; fi
  if [ "$n" = diff ] || [ "$n" = diffvm ]; then
    grep -h "QCTDIFF\|QCTSTAT" "$T"/qct.*.txt 2>/dev/null | sed "s/^/== $n: /" | grep -v " differences 0 " || true
    grep -qh QCTDIFF "$T"/qct.*.txt 2>/dev/null && bad=1
  elif ! cmp -s "$T/stock" "$T/$n"; then echo "== stock vs $n:"; diff "$T/stock" "$T/$n" | head -20 || true; bad=1
  else echo "== stock vs $n: same"; fi
done
rm -rf "$T"; exit $bad
