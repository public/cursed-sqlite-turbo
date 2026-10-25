#!/bin/sh
# fetch-sqlite.sh: the SQLite amalgamation, pinned and SHA-256-checked, into third_party/sqlite/
set -e
cd "$(dirname "$0")/.."
V=3540100
SHA=0a9c8e34352dad46006aa82836d5383bff9dc6bc9ce5a60553c05aa30e6ad1f9
URL="https://www.sqlite.org/2026/sqlite-amalgamation-$V.zip"
D=third_party/sqlite
[ -f "$D/sqlite3.c" ] && [ "$(cat "$D/VERSION" 2>/dev/null)" = "$V $SHA" ] && exit 0
mkdir -p "$D" build
sha() { if command -v sha256sum > /dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
curl -fsSL "$URL" -o build/sqlite.zip
[ "$(sha build/sqlite.zip)" = "$SHA" ] || { echo "fetch-sqlite: checksum mismatch for $URL" >&2; exit 1; }
rm -rf build/sqlite-x && mkdir build/sqlite-x && (cd build/sqlite-x && unzip -q ../sqlite.zip)
cp build/sqlite-x/sqlite-amalgamation-$V/sqlite3.c build/sqlite-x/sqlite-amalgamation-$V/sqlite3.h "$D/"
echo "$V $SHA" > "$D/VERSION"
rm -rf build/sqlite-x build/sqlite.zip
echo "fetch-sqlite: SQLite $V in $D"
