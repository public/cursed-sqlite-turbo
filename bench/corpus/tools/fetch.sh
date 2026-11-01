#!/bin/sh
# Download a project's original source files at the pinned commit into fetched/<project>/ (gitignored).
#   tools/fetch.sh PROJECT...    (or --all)
# Uses raw.githubusercontent.com; nothing needs a token. The repo, sha and paths come from projects/P/meta.json.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
[ "${1:-}" = "--all" ] && set -- $(ls "$root/projects")
for p in "$@"; do
  meta="$root/projects/$p/meta.json"
  python3 -I - "$meta" <<'EOF' | while read -r url path; do
import json, sys
m = json.load(open(sys.argv[1]))
slug = m["repo"].rstrip("/").split("github.com/")[1]
for f in m.get("fetch_paths", []):
    print(f"https://raw.githubusercontent.com/{slug}/{m['sha']}/{f} {f}")
EOF
    out="$root/fetched/$p/$path"
    mkdir -p "$(dirname "$out")"
    curl -fsSL "$url" -o "$out" && echo "fetched $p/$path" || echo "skipped $p/$path (directory, or not at this sha)"
  done
done
