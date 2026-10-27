#!/bin/sh
# campaign.sh [seconds] [jobs]: tests/sqlancer/run.sh over arms x oracles, <jobs> processes at a time (default 4, the
# CPUs bench/docker.sh gives the container), <seconds> each (default 600), the same seed per oracle in every arm so the
# arms see the same generated statements as long as results agree. Then summarise.py. ARMS=, ORACLES=, SEEDS= override.
R=$(cd "$(dirname "$0")/../.." && pwd)
SECS=${1:-600}; JOBS=${2:-4}
ARMS=${ARMS:-"stock turbo qvm diff diffvm"}; ORACLES=${ORACLES:-"NoREC QUERY_PARTITIONING PQS"}; SEEDS=${SEEDS:-1}
for s in $SEEDS; do for o in $ORACLES; do for a in $ARMS; do echo "$a $o $s"; done; done; done |
  xargs -P "$JOBS" -L 1 sh -c 'sh "$0/tests/sqlancer/run.sh" "$1" "$2" '"$SECS"' "$3"' "$R"
python3 "$R/tests/sqlancer/summarise.py" "$R/build/sqlancer/runs"
