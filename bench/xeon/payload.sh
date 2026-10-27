#!/bin/sh
# payload.sh <speedtest1|tpch|build> <stock|turbo|qvm|off> <round> <dir> [reps]: a payload directory for cursed-http's Xeon broker
# (synteq-experiments/submit.sh <slug> <dir>): this tree's sources only (qc/, bench/, SQLite 3.54.1, speedtest1.c or
# dbgen's sources), bench/xeon/box-run.sh as run.sh, and a manifest. One arm per experiment: submit the arms in
# alternation (paired arms in one run showed a ~4 µs second-arm effect). bench/xeon/collect.sh gathers the results.
set -e
R=$(cd "$(dirname "$0")/../.." && pwd); WL=$1; ARM=$2; ROUND=$3; P=$4; REPS=${5:-3}
REQ=${XEON_REQUESTER:?set XEON_REQUESTER to your session id (local_...)}
mkdir -p "$P"; P=$(cd "$P" && pwd)
rm -rf "$P" && mkdir -p "$P/qc" "$P/bench/$WL" "$P/scripts" "$P/third_party/sqlite" "$P/tests"
cp "$R"/qc/*.c "$R"/qc/*.h "$R"/qc/*.py "$P/qc/"
cp "$R"/bench/lib.sh "$R"/bench/build-sqlite.sh "$R"/bench/qc_serve.c "$R"/bench/qrun.c "$R"/bench/compare.py "$P/bench/"
[ -d "$R/bench/$WL" ] && cp "$R"/bench/$WL/* "$P/bench/$WL/"
cp "$R/tests/tcl_qc.c" "$P/tests/"
cp "$R/scripts/fetch-sqlite.sh" "$P/scripts/"
sh "$R/scripts/fetch-sqlite.sh" > /dev/null; cp "$R"/third_party/sqlite/sqlite3.c "$R"/third_party/sqlite/sqlite3.h "$R"/third_party/sqlite/VERSION "$P/third_party/sqlite/"
case $WL in
  speedtest1) mkdir -p "$P/build/bench/speedtest1"
    sh "$R/scripts/fetch-sqlite-src.sh" > /dev/null
    unzip -p "$R/build/sqlite-src-3540100.zip" sqlite-src-3540100/test/speedtest1.c > "$P/build/bench/speedtest1/speedtest1.c" ;;
  tpch) sh "$R/bench/tpch/fetch-dbgen.sh" > /dev/null
    mkdir -p "$P/build/bench/tpch/dbgen"
    (cd "$R/build/bench/tpch/dbgen" && cp *.c *.h dists.dss Makefile "$P/build/bench/tpch/dbgen/") 
    cp "$R/build/bench/tpch/dbgen/VERSION" "$P/build/bench/tpch/dbgen/COMMIT" ;;
esac
cp "$R/bench/xeon/box-run.sh" "$P/run.sh"
printf 'WL=%s\nARM=%s\nROUND=%s\nREPS=%s\n' "$WL" "$ARM" "$ROUND" "$REPS" > "$P/PARAMS"
cat > "$P/manifest.json" <<JSON
{"requester_session_id": "$REQ", "title": "turbo bench: $WL $ARM round $ROUND",
 "reasoning": "cursed-sqlite-turbo's external benchmarks (SQLite's speedtest1, TPC-H SF0.1) on the scored CPU: one arm ($ARM) of stock SQLite 3.54.1 / turbo plans-first / turbo qvm-only per run, arms alternated across runs; results checked identical across arms. Decides whether turbo's fallbacks (sorter spill, refused functions) cost real users time on general SQL, which feeds the specialisation-policy work in sqlite-jit.",
 "timeout_s": ${XEON_TIMEOUT:-300}, "needs_root": false}
JSON
du -sh "$P" | cut -f1
