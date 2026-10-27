#!/bin/sh
# collect.sh [experiments-dir]: the results of bench/xeon/payload.sh runs (expN-turbo-bench-<wl>-<arm>-<round>/result.zip
# under cursed-http's synteq-experiments/) into build/xeon-results/<wl>/, then the same summaries as locally
# (bench/speedtest1/summarise.py, bench/compare.py), and each run's box, wall time and exit status.
R=$(cd "$(dirname "$0")/../.." && pwd); E=${1:-$HOME/Documents/my-code/cursed-http/synteq-experiments}; O=$R/build/xeon-results
rm -rf "$O"; mkdir -p "$O/speedtest1" "$O/tpch" "$O/clickbench"
X=${XEON_PREFIX:-turbo-bench2}   # (the slug prefix the runs were submitted under)
for d in "$E"/exp*-$X-speedtest1-* "$E"/exp*-$X-tpch-* "$E"/exp*-$X-clickbench-*; do
  [ -f "$d/result.zip" ] || { echo "pending: $(basename "$d")"; continue; }
  case $d in *-speedtest1-*) wl=speedtest1 ;; *-clickbench-*) wl=clickbench ;; *) wl=tpch ;; esac
  unzip -q -o -j "$d/result.zip" 'out/*.txt' 'out/*.tsv' 'out/*.stats' -x 'out/env.txt' 'out/log.txt' 'out/cflags*' 'out/dbgen*' -d "$O/$wl" 2>/dev/null
  echo "$(basename "$d"): $(jq -r '"\(.host // "?") wall \(.wall_s)s exit \(.exit_code) \(.systemd_result) steal \(.steal_pct)%"' "$d/status.json" 2>/dev/null) $(unzip -p "$d/result.zip" out/log.txt 2>/dev/null | tail -1)"
done
echo; echo "## speedtest1"; python3 "$R/bench/speedtest1/summarise.py" "$O/speedtest1"
echo; echo "## tpch sf0.1"; python3 "$R/bench/compare.py" "$O/tpch"
ls "$O"/clickbench/*.tsv > /dev/null 2>&1 && { echo; echo "## clickbench"; python3 "$R/bench/compare.py" "$O/clickbench"; }
