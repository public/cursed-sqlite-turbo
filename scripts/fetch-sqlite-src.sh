#!/bin/sh
# fetch-sqlite-src.sh: SQLite's canonical source tree (with the TCL test suite), pinned and SHA-256-checked, into
# build/sqlite-src-<V>.zip. SQLITE_SRC_ZIP=<path> uses a local copy instead (checked the same way).
set -e
cd "$(dirname "$0")/.."
V=3540100
SHA=387e7f6cad4797b17848c07d453dc6606917bb356a6cfe5a3abafd38c240c71b
Z=build/sqlite-src-$V.zip
sha() { if command -v sha256sum > /dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
[ -f "$Z" ] && [ "$(sha "$Z")" = "$SHA" ] && exit 0
mkdir -p build
if [ -n "${SQLITE_SRC_ZIP:-}" ]; then cp "$SQLITE_SRC_ZIP" "$Z"; else curl -fsSL "https://www.sqlite.org/2026/sqlite-src-$V.zip" -o "$Z"; fi
[ "$(sha "$Z")" = "$SHA" ] || { echo "fetch-sqlite-src: checksum mismatch" >&2; rm -f "$Z"; exit 1; }
echo "fetch-sqlite-src: $Z"
