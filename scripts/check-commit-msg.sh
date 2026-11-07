#!/bin/sh
# check-commit-msg.sh: Conventional Commits (https://www.conventionalcommits.org/en/v1.0.0/) for this repo.
#   check-commit-msg.sh FILE           the commit-msg hook: FILE holds the message (.githooks/commit-msg calls this)
#   check-commit-msg.sh --subject TEXT one subject line (CI: every commit in a PR, and the PR title)
# Accepted: type(optional-scope)!: description, with type one of
#   build chore ci docs feat fix perf refactor revert style test
# and a subject of at most 100 characters. Git's own messages (Merge ..., Revert "...", fixup!/squash!/amend!) pass.
set -eu
TYPES='build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test'
if [ "${1:-}" = --subject ]; then subj="${2:-}"; else subj="$(grep -v '^#' "$1" | sed -n '/[^[:space:]]/{p;q;}')"; fi
case "$subj" in "Merge "*|"Revert \""*|"fixup! "*|"squash! "*|"amend! "*) exit 0;; esac
if ! printf '%s\n' "$subj" | grep -Eq "^($TYPES)(\([A-Za-z0-9][A-Za-z0-9._/#-]*\))?!?: [^ ].*"; then
  printf 'commit message is not a Conventional Commit:\n  %s\n' "$subj" >&2
  printf 'use type(scope): description, with type one of %s\n' "$(echo "$TYPES" | tr '|' ' ')" >&2
  printf 'e.g. "perf(hs256): unroll the SHA-NI 4-stream kernel" or "fix(qc)!: ..." for a breaking change\n' >&2
  exit 1
fi
[ "${#subj}" -le 100 ] || { printf 'commit subject is %s characters; keep it to 100:\n  %s\n' "${#subj}" "$subj" >&2; exit 1; }
