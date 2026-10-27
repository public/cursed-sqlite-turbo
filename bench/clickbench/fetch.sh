#!/bin/sh
# fetch.sh [rows]: ClickBench's SQLite entry (create.sql, queries.sql at a pinned ClickBench commit, SHA-256-checked) and
# the first <rows> records (default 1,000,000) of its dataset, hits.csv (datasets.clickhouse.com, 99,997,497 rows,
# 16.6 GB gzipped). Only a prefix is downloaded (an HTTP range of the .gz, decompressed as far as it goes) and cut
# at a record boundary by cut.py; the cut CSV's SHA-256 is pinned per row count. Into $BENCH_DATA/clickbench/.
set -e
R=$(cd "$(dirname "$0")/../.." && pwd); ROWS=${1:-1000000}
C=db61f6ad831cb6c8b8a65724e65d8c9764b5b00b
D=${BENCH_DATA:-$R/build/bench/data}/clickbench; mkdir -p "$D"
sha() { if command -v sha256sum > /dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
get() {   # get <path in ClickBench> <sha256>
  f=$D/$(basename "$1")
  [ -f "$f" ] && [ "$(sha "$f")" = "$2" ] && return 0
  curl -fsSL "https://raw.githubusercontent.com/ClickHouse/ClickBench/$C/$1" -o "$f.part"
  [ "$(sha "$f.part")" = "$2" ] || { echo "fetch: checksum mismatch for $1 ($(sha "$f.part"))" >&2; rm -f "$f.part"; exit 1; }
  mv "$f.part" "$f"
}
get sqlite/create.sql 944e60d596d6f572658f86e4200ec3d33c0b87dddc39c0ad9e0a45afb2686a15
get sqlite/queries.sql c6198321d95bea6a3c113e2c144fa3a79e461f53f4e587b7bbfd9620eb002829
case $ROWS in
  1000000) WANT=159ee609e3396a8b44e96ec9df63ffac1e05b37221485932185403f31bbd0678 ;;
  10000000) WANT=@SHA_10M@ ;;
  *) WANT= ;;
esac
CSV=$D/hits-$ROWS.csv
[ -f "$CSV" ] && [ -n "$WANT" ] && [ "$(sha "$CSV")" = "$WANT" ] && { echo "fetch: $CSV"; exit 0; }
BYTES=$((ROWS * 140 + 4000000))   # (~125 compressed bytes a row at the start of the file)
curl -fsS -r "0-$BYTES" https://datasets.clickhouse.com/hits_compatible/hits.csv.gz | { gzip -dc 2>/dev/null || true; } | python3 -I "$R/bench/clickbench/cut.py" "$ROWS" "$CSV.part" \
  || { echo "fetch: the range held fewer than $ROWS records" >&2; rm -f "$CSV.part"; exit 1; }
S=$(sha "$CSV.part")
if [ -z "$WANT" ]; then echo "fetch: no pinned checksum for $ROWS rows; got $S" >&2
elif [ "$S" != "$WANT" ]; then echo "fetch: checksum mismatch for the first $ROWS rows ($S)" >&2; rm -f "$CSV.part"; exit 1; fi
mv "$CSV.part" "$CSV"
echo "fetch: $CSV"
