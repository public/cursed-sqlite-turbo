#!/bin/sh
# run-slt.sh <sqllogictest binary> <test dir> <out dir> [jobs] [file filter (grep -e)]: each .test file with optimizer=0
# and -1 (as sqllogictest's run-all.tcl), integrity_check on, each run in its own scratch directory (test.db is made in
# the current one). Per invocation, out/<file>.<optimizer> holds the harness's output and qc's QCSTAT/QCWHY/QCDIFF
# lines; summary.txt has the harness's totals and qc's.
set -u
B=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); T=$(cd "$2" && pwd); mkdir -p "$3/out" "$3/tmp"; O=$(cd "$3" && pwd)
J=${4:-4}; F=${5:-.}
start=$(date +%s)
cat > "$O/one.sh" <<EOS
#!/bin/sh
# one.sh <file> <optimizer>
o="$O/out/\$(echo "\$1.\$2" | sed 's|^\./||; s|/|_|g')"
t=\$(mktemp -d "$O/tmp/XXXXXX"); cd "\$t"
"$B" -verify -parameter "integrity_check;optimizer=\$2" "$T/\$1" > "\$o" 2>&1
echo "exit=\$?" >> "\$o"; cd /; rm -rf "\$t"
EOS
chmod +x "$O/one.sh"
(cd "$T" && find . -name '*.test' | grep -e "$F" | sort | while read f; do echo "$f 0"; echo "$f -1"; done) | xargs -P "$J" -L 1 "$O/one.sh"
cd "$O"
{
  awk '/errors out of/ { e += $1; t += $5; n++ } END { printf "harness: %d invocations, %d errors out of %d tests\n", n, e, t }' out/*
  awk '/^QCSTAT/ { for (i = 2; i < NF; i += 2) { k = $i; v = $(i+1); gsub(/[(),]/, "", k); gsub(/[(),]/, "", v); s[k] += v } }
       END { printf "qc:"; for (k in s) printf " %s %d", k, s[k]; printf "\n" }' out/*
  echo "exits not 0: $(grep -L '^exit=0' out/* | wc -l | tr -d ' ')"
  echo "leaks: $(grep -l 'memory leak' out/* | wc -l | tr -d ' ')"
  echo "secs=$(( $(date +%s) - start ))"
} > summary.txt
grep -h '^QCWHY' out/* | awk '{ n = $2; $1 = $2 = ""; w[substr($0, 3)] += n } END { for (k in w) print w[k], k }' | sort -rn > why.txt
grep -h -A3 '^QCDIFF' out/* > diffs.txt
cat summary.txt
