#!/bin/sh
# docker.sh <command...>: run a command in the bench toolchain image (bench/Dockerfile), with the repo at /repo, on
# CPUs 8-11 only (BENCH_CPUS; 0-7 belong to other work on this machine). The image is built on first use. Datasets
# and databases live in the named volume cursed-turbo-bench-data, at /data (BENCH_DATA there), not in the repo.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
IMG=cursed-turbo-bench:$(shasum -a 256 "$R/bench/Dockerfile" 2>/dev/null | cut -c1-12 || sha256sum "$R/bench/Dockerfile" | cut -c1-12)
CPUS=${BENCH_CPUS:-8-11}
docker image inspect "$IMG" > /dev/null 2>&1 || docker build --cpuset-cpus "$CPUS" -t "$IMG" -f "$R/bench/Dockerfile" "$R/bench"
T=; [ -t 0 ] && T=-t
exec docker run --rm -i $T --cpuset-cpus "$CPUS" --memory "${BENCH_MEM:-12g}" -v "$R:/repo" -v cursed-turbo-bench-data:/data -e BENCH_DATA=/data -w /repo \
  -e QC_VM_ONLY -e QCS_OFF -e QCS_STATS -e QCT_DIR -e JOBS "$IMG" "$@"
