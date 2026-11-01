# Lint image: the pinned linters scripts/lint.sh runs (locally via Docker, and in CI), so every machine gets the same
# findings. gcc 13 and clang 18 for the warnings-as-errors compile of qc; ruff for the Python; shellcheck for the shell.
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gcc clang-18 make python3 curl unzip ca-certificates shellcheck git pipx \
 && ln -s /usr/bin/clang-18 /usr/local/bin/clang \
 && PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install ruff==0.6.9 \
 && rm -rf /var/lib/apt/lists/*
