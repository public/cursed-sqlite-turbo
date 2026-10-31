#!/bin/sh
# payload.sh <speedtest1|tpch|clickbench|parity|corpus|corpusfast|build> <stock|turbo|qvm|off> <round> <dir> [reps]: a payload directory for cursed-http's Xeon broker
# (synteq-experiments/submit.sh <slug> <dir>): this tree's sources only (qc/, bench/, SQLite 3.54.1, speedtest1.c or
# dbgen's sources), bench/xeon/box-run.sh as run.sh, and a manifest. One arm per experiment: submit the arms in
# alternation (paired arms in one run showed a ~4 µs second-arm effect). bench/xeon/collect.sh gathers the results.
# XEON_FIXED_TITLE and XEON_REASON make every payload of a series identical but for PARAMS (one root review).
set -e
R=$(cd "$(dirname "$0")/../.." && pwd); WL=$1; ARM=$2; ROUND=$3; P=$4; REPS=${5:-3}
REQ=${XEON_REQUESTER:?set XEON_REQUESTER to your session id (local_...)}
mkdir -p "$P"; P=$(cd "$P" && pwd)
rm -rf "$P" && mkdir -p "$P/qc" "$P/bench" "$P/scripts" "$P/third_party/sqlite" "$P/tests"
cp "$R"/qc/*.c "$R"/qc/*.h "$R"/qc/*.py "$P/qc/"
cp "$R"/bench/lib.sh "$R"/bench/build-sqlite.sh "$R"/bench/qc_serve.c "$R"/bench/qrun.c "$R"/bench/compare.py "$P/bench/"
[ -d "$R/bench/$WL" ] && { mkdir -p "$P/bench/$WL"; cp "$R"/bench/$WL/* "$P/bench/$WL/" 2>/dev/null || true; }
case $WL in corpus*) WLD=corpus ;; *) WLD= ;; esac
[ "$WLD" = corpus ] && { rm -rf "$P/bench/corpus"; mkdir -p "$P/bench/corpus"; cp -R "$R"/bench/corpus/*.py "$R"/bench/corpus/*.c "$R"/bench/corpus/*.sh "$R"/bench/corpus/*.tsv "$R"/bench/corpus/manifest.jsonl "$P/bench/corpus/"; mkdir -p "$P/bench/corpus/projects"; for d in "$R"/bench/corpus/projects/*/; do mkdir -p "$P/bench/corpus/projects/$(basename "$d")"; cp "$d"schema.sql "$d"data.sql "$d"queries.sql "$d"meta.json "$P/bench/corpus/projects/$(basename "$d")/"; done; }   # (the corpus: what prep.py reads)
if [ "$WL" = st1diag ] || [ "$WL" = st1prof ]; then mkdir -p "$P/bench/speedtest1"; cp "$R"/bench/speedtest1/* "$P/bench/speedtest1/"; fi
if [ "$WL" = parity ]; then   # (bench/small on TPC-H SF0.1, and speedtest1)
  for w in small tpch speedtest1; do mkdir -p "$P/bench/$w"; cp "$R"/bench/$w/* "$P/bench/$w/"; done; cp "$R/bench/parity.py" "$P/bench/"
fi
cp "$R/tests/tcl_qc.c" "$P/tests/"
cp "$R/scripts/fetch-sqlite.sh" "$P/scripts/"
[ -f "$R/QC_SNAPSHOT.txt" ] && cp "$R/QC_SNAPSHOT.txt" "$P/"   # (a scratch tree with someone's uncommitted qc/: its checksums)
sh "$R/scripts/fetch-sqlite.sh" > /dev/null; cp "$R"/third_party/sqlite/sqlite3.c "$R"/third_party/sqlite/sqlite3.h "$R"/third_party/sqlite/VERSION "$P/third_party/sqlite/"
case $WL in parity) WLS="speedtest1 tpch" ;; st1diag|st1prof) WLS=speedtest1 ;; *) WLS=$WL ;; esac
for WLX in $WLS; do case $WLX in
  speedtest1) mkdir -p "$P/build/bench/speedtest1"
    sh "$R/scripts/fetch-sqlite-src.sh" > /dev/null
    unzip -p "$R/build/sqlite-src-3540100.zip" sqlite-src-3540100/test/speedtest1.c > "$P/build/bench/speedtest1/speedtest1.c" ;;
  tpch) sh "$R/bench/tpch/fetch-dbgen.sh" > /dev/null
    mkdir -p "$P/build/bench/tpch/dbgen"
    (cd "$R/build/bench/tpch/dbgen" && cp *.c *.h dists.dss Makefile "$P/build/bench/tpch/dbgen/") 
    cp "$R/build/bench/tpch/dbgen/VERSION" "$P/build/bench/tpch/dbgen/COMMIT" ;;
esac; done
cp "$R/bench/xeon/box-run.sh" "$P/run.sh"
printf 'WL=%s\nARM=%s\nROUND=%s\nREPS=%s\n' "$WL" "$ARM" "$ROUND" "$REPS" > "$P/PARAMS"
[ -n "${PROJ:-}" ] && printf 'PROJ="%s"\n' "$PROJ" >> "$P/PARAMS"   # (corpus: these projects only)
[ -n "${ID:-}" ] && printf 'ID=%s\n' "$ID" >> "$P/PARAMS"   # (corpusdiag: the statement)
[ -n "${BUDGET:-}" ] && printf 'BUDGET=%s\n' "$BUDGET" >> "$P/PARAMS"
[ -n "${ARMS:-}" ] && printf 'ARMS="%s"\n' "$ARMS" >> "$P/PARAMS"   # (corpusfast: every arm in the one run)
[ -n "${N:-}" ] && printf 'N=%s\n' "$N" >> "$P/PARAMS"   # (corpusfast: rounds)
[ -n "${MODES:-}" ] && printf 'MODES="%s"\n' "$MODES" >> "$P/PARAMS"   # (corpusfast: hot, prep or both)
[ -n "${CORPUS_EXTRA:-}" ] && printf 'CORPUS_EXTRA=%s\n' "$CORPUS_EXTRA" >> "$P/PARAMS"   # (corpus: cache, TLB, page-fault and allocation counts, X lines; 2: the front end's instead of the caches')
[ -n "${CORPUS_MIN_REPS:-}" ] && printf 'CORPUS_MIN_REPS=%s\n' "$CORPUS_MIN_REPS" >> "$P/PARAMS"   # (corpus: at least that many executions a statement and mode, past BUDGET)
[ -n "${SUBSET:-}" ] && printf 'SUBSET="%s"\n' "$SUBSET" >> "$P/PARAMS"   # (corpusfast: these statements of the loser set only)
[ -n "${ST_OPTS:-}" ] && printf 'ST_OPTS="%s"\n' "$ST_OPTS" >> "$P/PARAMS"   # (speedtest1's options, e.g. --testset json)
[ "$WL" = clickbench ] && TITLE_X=" (300k rows, the sorter-spill queries)"
TITLE=${XEON_FIXED_TITLE:-"turbo bench: $WL $ARM round $ROUND${TITLE_X:-}${XEON_TITLE:-}"}
REASON=${XEON_REASON:-"cursed-sqlite-turbo external benchmarks (SQLite speedtest1, TPC-H SF0.1, ClickBench) on the scored CPU: one arm ($ARM) of stock SQLite 3.54.1 / turbo plans-first / turbo qvm-only per run, arms alternated across runs; results checked identical across arms. Decides whether turbo costs real users time on general SQL, which feeds the specialisation-policy work in sqlite-jit."}
BOXJSON=; [ -n "${XEON_BOX:-}" ] && BOXJSON=", \"box\": \"$XEON_BOX\""   # (XEON_BOX=box1: ask the broker for that box)
cat > "$P/manifest.json" <<JSON
{"requester_session_id": "$REQ", "title": "$TITLE",
 "reasoning": "$REASON",
 "timeout_s": ${XEON_TIMEOUT:-300}, "needs_root": ${XEON_ROOT:-false}$BOXJSON}
JSON
du -sh "$P" | cut -f1
