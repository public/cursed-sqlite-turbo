#!/bin/sh
# run-tcl.sh <testfixture> <src dir> <out dir> <jobs> <file list>: each test file in its own scratch directory, as
# testfixture runs it alone (no testrunner); out/<file>.txt holds its output, qct/<file>.txt the hook's lines.
# Summary in summary.txt: the suite's errors per file and the hook's totals.
set -u
B=$1; S=$(cd "$2" && pwd); mkdir -p "$3/out" "$3/qct" "$3/tmp"; O=$(cd "$3" && pwd); J=$4; L=$5
start=$(date +%s)
cat > "$O/one.sh" <<EOS
#!/bin/sh
f=\$1; n=\$(basename "\$f" .test)
t=\$(mktemp -d "$O/tmp/XXXXXX"); cd "\$t"
QCT_DIR="\$t" timeout 1200 "$B" "$S/test/\$f" > "$O/out/\$n.txt" 2>&1; echo "exit=\$?" >> "$O/out/\$n.txt"
cat "\$t"/qct.*.txt > "$O/qct/\$n.txt" 2>/dev/null; cd /; rm -rf "\$t"
EOS
chmod +x "$O/one.sh"
xargs -P "$J" -n 1 "$O/one.sh" < "$L"
cd "$O"
{
  for f in out/*.txt; do n=$(basename "$f" .txt); printf '%s\t%s\t%s\n' "$n" "$(grep -Eo '[0-9]+ errors out of [0-9]+ tests' "$f" | tail -1)" "$(tail -1 "$f")"; done > files.tsv
  awk -F'\t' '{ split($2, a, " "); e += a[1]; t += a[5]; if (a[1] > 0 || $3 != "exit=0") bad++ } END { printf "suite: %d files, %d errors out of %d tests, %d files with errors or a bad exit\n", NR, e, t, bad }' files.tsv
  cat qct/*.txt 2>/dev/null | awk '/^QCTSTAT/ { for (i = 2; i < NF; i += 2) s[$i] += $(i+1) } END { printf "qc:"; for (k in s) printf " %s %d", k, s[k]; printf "\n" }'
  echo "secs=$(( $(date +%s) - start ))"
} > summary.txt
cat qct/*.txt 2>/dev/null | grep '^QCTWHY' | awk '{ n = $2; $1 = $2 = ""; w[substr($0, 3)] += n } END { for (k in w) print w[k], k }' | sort -rn > why.txt
grep -H '^QCTDIFF\|^QCTINTERR' qct/*.txt > diffs.txt 2>/dev/null
cat summary.txt
