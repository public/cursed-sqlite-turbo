# The toolchain for bench/ and tests/sqlancer/ (bench/docker.sh builds and runs it on CPUs 8-11). Debian bookworm,
# pinned by digest (multi-arch index); the packages are bookworm's.
FROM debian:bookworm@sha256:854dd8ab51d62866dbd8f5431d15ce77b12983a2a4a1e1fe43a2395dc7ef9f61
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential clang lld curl ca-certificates unzip zip xz-utils python3 git \
      openjdk-17-jdk-headless maven time valgrind && rm -rf /var/lib/apt/lists/*
