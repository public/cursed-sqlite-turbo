#!/bin/sh
# gauntlet.sh [check|speed] [sqlgauntlet-run options...]: turbo's benchmarks and differential correctness runs, from
# sqlgauntlet (https://github.com/public/sqlgauntlet) at the commit pinned below, against this working tree (make
# gauntlet). It:
#   1. clones sqlgauntlet at the pin into build/sqlgauntlet, or uses SQLGAUNTLET_DIR (a checkout of your own, as it is);
#   2. builds its CLI and its SQLite 3.54.1 backend, and fetches the two corpus apps it doesn't commit, from this
#      repository's history;
#   3. builds turbo from this checkout, not from any pin: qc/patch.py over the same SQLite, qc.c appended, as
#      sqlgauntlet's backend "turbo" (make sqlite-api), serving with QC_SERVE=1;
#   4. runs sqlgauntlet-run with the arms sqlite (the reference) and turbo, or ARMS="...", over the corpus (or
#      --corpus <dir>, e.g. a workload's: sqlgauntlet's workloads/tpch/make.py), into build/gauntlet/<mode>.
# check (the default) compares every statement's rows with SQLite's; speed times both arms, interleaved (add --rounds,
# --exec-lines, --callgrind). Other arms: ARMS="sqlite turbo turbo-novm=turbo:QC_VM_ONLY=1".
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
SQLGAUNTLET_COMMIT=544c83dc91d6392cff23392643f10d2003afe381
SQLGAUNTLET_URL=${SQLGAUNTLET_URL:-https://github.com/public/sqlgauntlet}
MODE=${1:-check}; [ $# -gt 0 ] && shift
if [ -n "${SQLGAUNTLET_DIR:-}" ]; then G=$(cd "$SQLGAUNTLET_DIR" && pwd)
else
  G=$R/build/sqlgauntlet
  [ -d "$G/.git" ] || git clone -q "$SQLGAUNTLET_URL" "$G"
  [ "$(git -C "$G" rev-parse HEAD)" = "$SQLGAUNTLET_COMMIT" ] || { git -C "$G" fetch -q origin; git -C "$G" checkout -q "$SQLGAUNTLET_COMMIT"; }
fi
make -s -C "$G" all sqlite
[ -f "$G/corpus/manifest.fetched.jsonl" ] || sh "$G/corpus/fetch.sh" "$R"   # (phoenix and n8n: fetched, not committed)
# turbo from this checkout
make -s -C "$R" all
T=$R/build/gauntlet/turbo; mkdir -p "$T"
cp "$R/build/gen/sqlite3.c" "$T/sqlite3.c.tmp"; printf '\n#include "qc.c"   /* cursed-sqlite-turbo */\n' >> "$T/sqlite3.c.tmp"
cmp -s "$T/sqlite3.c.tmp" "$T/sqlite3.c" 2>/dev/null && rm "$T/sqlite3.c.tmp" || mv "$T/sqlite3.c.tmp" "$T/sqlite3.c"
cp "$R/build/gen/sqlite3.h" "$R/build/gen/qc_dec.h" "$T/"
REV=$(git -C "$R" rev-parse --short=10 HEAD)$(git -C "$R" diff --quiet HEAD -- qc || echo +dirty)
make -s -C "$G" sqlite-api NAME=turbo SRC="$T" ENV="QC_SERVE=1" EXTRA_CFLAGS="-I$R/qc -DSG_VERSION_NOTE='\" + turbo $REV\"'"
# the run
set -- --out "$R/build/gauntlet/$MODE" "$@"
for a in ${ARMS:-sqlite turbo}; do set -- "$@" --arm "$a"; done
cd "$G/python" && exec python3 -m sqlgauntlet.run "$MODE" "$@"
