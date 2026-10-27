#!/bin/sh
# crashes.sh <sql-file>: exit 1 if turbo (replay-serve, with QC_VM_ONLY as set) crashes replaying the file on a database
# file and stock doesn't; 0 otherwise. For reduce.py. Uses tests/sqlancer/repro.sh's builds (build/bench-repro).
B=${BENCH_BUILD:-$(cd "$(dirname "$0")/../.." && pwd)/build/bench-repro}
D=$(mktemp -d)
REPLAY_DB=$D/r.db "$B/replay-stock" "$1" > /dev/null 2>&1; s=$?
rm -f "$D"/r.db*; REPLAY_DB=$D/r.db "$B/replay-serve" "$1" > /dev/null 2>&1; t=$?
rm -rf "$D"
[ $s -eq 0 ] && [ $t -ge 128 ] && exit 1
exit 0
