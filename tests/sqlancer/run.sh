#!/bin/sh
# run.sh <arm> <oracle> <seconds> [seed]: one SQLancer process (one thread: qc's run state is per process, one thread
# at a time) on its sqlite3 provider, against the JNI library of tests/sqlancer/build.sh for <arm>:
#   stock       plain SQLite 3.54.1
#   turbo, qvm  bench/qc_serve.c: qc runs every read-only statement it takes and SQLancer's oracle sees its rows (qvm:
#               QC_VM_ONLY=1)
#   serve, servevm  the native variant: qc serving inside sqlite3_step (QC_SERVE=1, no shim; servevm: QC_VM_ONLY=1);
#               qc's process-wide counts (QC_STATS=1) at the end of sqlancer.txt
#   diff, diffvm  tests/tcl_qc.c: every read-only statement SQLancer runs is also run through qc on a copy and compared
#               with the interpreter, value by value (QCTDIFF lines); SQLancer sees SQLite's rows
# <oracle>: one of SQLancer's sqlite3 oracles (NoREC, QUERY_PARTITIONING, PQS, ...). Output in
# build/sqlancer/runs/<arm>-<oracle>-<seed>/: sqlancer.txt, SQLancer's logs/ (one file per bug it reports), qc's
# counters (qcs.stats or qct.*.txt), hs_err_pid*.log after a native crash. SQLANCER_OPTS: more SQLancer options
# (--log-each-select true to replay a crash). Run it inside bench/docker.sh; tests/sqlancer/campaign.sh runs a matrix.
set -e
R=$(cd "$(dirname "$0")/../.." && pwd); O=$R/build/sqlancer
ARM=$1; ORACLE=$2; SECS=$3; SEED=${4:-1}
case $ARM in stock) L=stock ;; turbo|qvm) L=serve ;; serve|servevm) L=native; export QC_SERVE=1 QC_STATS=1 ;; diff|diffvm) L=diff ;; *) echo "run: unknown arm $ARM" >&2; exit 2 ;; esac
case $ARM in qvm|diffvm|servevm) export QC_VM_ONLY=1 ;; *) unset QC_VM_ONLY ;; esac
W=$O/runs/$ARM-$ORACLE-$SEED; rm -rf "$W"; mkdir -p "$W"
T=$(mktemp -d); cd "$T"   # (SQLancer writes its databases and logs/ under the working directory)
QCS_STATS=$W/qcs.stats QCT_DIR=$W timeout -k 30 $((SECS + 120)) java -Xmx1g \
  -Dorg.sqlite.lib.path="$O/$L" -Dorg.sqlite.lib.name=libsqlitejdbc.so \
  -jar "$O/sqlancer.jar" --num-threads 1 --timeout-seconds "$SECS" --random-seed "$SEED" --num-tries 100000 \
  --print-progress-summary true --print-failed false ${SQLANCER_OPTS:-} sqlite3 --oracle "$ORACLE" > "$W/sqlancer.txt" 2>&1 || true
[ -d logs ] && cp -r logs "$W/" || true
cp hs_err_pid*.log "$W/" 2>/dev/null || true   # (a native crash's report)
cd / && rm -rf "$T"
n=$(ls "$W"/logs/sqlite3/*-cur.log 2>/dev/null | wc -l || true)
echo "sqlancer: $ARM $ORACLE seed $SEED: $(grep -c . "$W/sqlancer.txt") lines of output, $(ls "$W"/logs/sqlite3 2>/dev/null | grep -vc -- '-cur.log$' || true) bug logs"
