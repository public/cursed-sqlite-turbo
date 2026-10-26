#!/bin/sh
# fetch-slt.sh: sqllogictest (https://sqlite.org/sqllogictest, public domain), pinned to one check-in, into
# third_party/slt/ (the harness sources in src/, the corpus in test/). Needs fossil, or docker with an image that has
# it (SLT_IMAGE, run on CPUs 8-13): the web tarballs sit behind a browser check, fossil's sync protocol does not.
set -e
cd "$(dirname "$0")/.."
CI=ab599cbdd0976a63c5cfc7755588f716a7621f27
D=third_party/slt
[ -f "$D/src/sqllogictest.c" ] && [ "$(cat "$D/CHECKIN" 2>/dev/null)" = "$CI" ] && exit 0
rm -rf "$D" && mkdir -p "$D" build
if command -v fossil > /dev/null; then
  fossil clone https://sqlite.org/sqllogictest build/slt.fossil
  (cd "$D" && fossil open ../../build/slt.fossil "$CI")
else
  IMG=${SLT_IMAGE:-sqlconf-tools:arm64}
  docker run --rm --cpuset-cpus 8-13 -u "$(id -u):$(id -g)" -e HOME=/tmp -e USER=slt -v "$PWD:/w" -w /w "$IMG" \
    sh -c "fossil clone https://sqlite.org/sqllogictest build/slt.fossil && cd $D && fossil open ../../build/slt.fossil $CI"
fi
[ -f "$D/src/sqllogictest.c" ] || { echo "fetch-slt: no src/sqllogictest.c at $CI" >&2; exit 1; }
echo "$CI" > "$D/CHECKIN"
echo "fetch-slt: sqllogictest $CI in $D ($(find "$D/test" -name '*.test' | wc -l | tr -d ' ') test files)"
