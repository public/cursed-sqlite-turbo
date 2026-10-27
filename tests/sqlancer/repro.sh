#!/bin/sh
# repro.sh <sql-file>: replay.c linked with stock SQLite and with turbo (bench/qc_serve.c), plans first and qvm only,
# and the differences in what they return. Run inside bench/docker.sh. Exit 1 if any arm differs from stock.
set -e
BR=$(cd "$(dirname "$0")/../.." && pwd); . "$BR/bench/lib.sh"
bench_link stock "$BB/replay-stock" "$BR/tests/sqlancer/replay.c"
bench_link serve "$BB/replay-serve" "$BR/tests/sqlancer/replay.c"
T=$(mktemp -d)
"$BB/replay-stock" "$1" > "$T/stock"
"$BB/replay-serve" "$1" > "$T/turbo"
QC_VM_ONLY=1 "$BB/replay-serve" "$1" > "$T/qvm"
bad=0
for a in turbo qvm; do
  if ! cmp -s "$T/stock" "$T/$a"; then echo "== stock vs $a"; diff "$T/stock" "$T/$a" || true; bad=1; else echo "== stock vs $a: same"; fi
done
rm -rf "$T"; exit $bad
