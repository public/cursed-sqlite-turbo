#!/usr/bin/env bash
# lint.sh: lint checks for first-party code (third_party/ and generated build/ files excluded).
#   ruff check     the Python (ruff.toml: pyflakes and pycodestyle's error-class rules)
#   shellcheck     the shell scripts, warnings and errors
#   qc warnings    qc/qc.c (with qcg.c, qvm.c) compiled with -Wall -Wextra -Werror by gcc and clang, after the
#                  amalgamation as a system header (its own warnings are SQLite's, and the Makefile builds it with -w):
#                  the patched build at SQLITE_THREADSAFE 0 and 1, and QC_STOCK=1 on the unmodified amalgamation
# Formatting isn't checked: the code has its own dense style and no formatter reproduces it.
# The tools are pinned in ci/lint.Dockerfile. Unless LINT_LOCAL=1 (CI sets it inside that image), this script
# re-runs itself in that image. Exits non-zero on any finding.
set -euo pipefail
cd "$(dirname "$0")/.."

# file lists from git on the host (a worktree's .git points outside the container's mount)
PY_FILES=${PY_FILES:-$(git ls-files -- '*.py' | grep -v '^third_party/' | tr '\n' ' ')}
SH_FILES=${SH_FILES:-$(git ls-files -- '*.sh' | grep -v '^third_party/' | tr '\n' ' ')}

if [ "${LINT_LOCAL:-0}" != 1 ]; then
  command -v docker >/dev/null || { echo "lint.sh: needs Docker (or LINT_LOCAL=1 with the tools in ci/lint.Dockerfile)" >&2 && exit 2; }
  img=lint-turbo:$(git hash-object ci/lint.Dockerfile | cut -c1-12)
  docker image inspect "$img" >/dev/null 2>&1 || docker build -q -t "$img" -f ci/lint.Dockerfile ci >/dev/null
  exec docker run --rm -e LINT_LOCAL=1 -e PY_FILES="$PY_FILES" -e SH_FILES="$SH_FILES" \
    -v "$PWD":/r -w /r -u "$(id -u):$(id -g)" -e HOME=/tmp "$img" bash scripts/lint.sh "$@"
fi

bad=0
step() { printf '== %s\n' "$1"; }

step "ruff check"
# shellcheck disable=SC2086 # (file lists: tracked paths without spaces)
ruff check --no-cache -q $PY_FILES || bad=1

step "shellcheck"
# shellcheck disable=SC2086
shellcheck -S warning $SH_FILES || bad=1

# the warnings qc's style produces on purpose, off: partial initializers ({0}-style tables), callbacks with a uniform
# signature, debug-only helpers, designated initializers that override a range (opcode tables), one-line guards
# followed by another statement, and comma-expression macros whose value is unused
W=(-Wall -Wextra -Werror -Wno-missing-field-initializers -Wno-unused-parameter -Wno-unused-function
  -Wno-misleading-indentation -Wno-unused-value)
make -s all build/gen-stock/qc_copies.c build/gen-stock/qc_dec.h
tu=$(mktemp -d)/lint_qc.c
printf '#include <sqlite3.c>\n#include "qc.c"\n' >"$tu"
for cc in gcc clang; do
  if [ $cc = gcc ]; then x=-Wno-override-init; else x=-Wno-initializer-overrides; fi
  for ts in 0 1; do
    step "qc warnings: $cc, patched amalgamation, SQLITE_THREADSAFE=$ts"
    $cc -std=gnu11 -O2 -isystem build/gen -Iqc -DSQLITE_THREADSAFE=$ts "${W[@]}" $x -c "$tu" -o /dev/null || bad=1
  done
  # (QC_STOCK keeps the patched build's hook pointers, set and never called: gcc reports them unused)
  step "qc warnings: $cc, QC_STOCK=1 on the unmodified amalgamation"
  $cc -std=gnu11 -O2 -isystem third_party/sqlite -isystem build/gen-stock -Iqc -DQC_STOCK=1 -DSQLITE_THREADSAFE=1 \
    "${W[@]}" -Wno-unused-variable $x -c "$tu" -o /dev/null || bad=1
done

if [ $bad = 1 ]; then
  echo "lint: findings above" >&2
  exit 1
fi
echo "lint: clean"
