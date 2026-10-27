#!/bin/sh
# fetch-dbgen.sh: TPC-H's dbgen (gregrahn/tpch-kit, pinned commit, SHA-256-checked tarball) built into
# build/bench/tpch/dbgen/dbgen. Only the dbgen sources are kept (bench/tpch/xeon/ ships them to the Xeon as well).
set -e
R=$(cd "$(dirname "$0")/../.." && pwd)
C=852ad0a5ee31ebefeed884cea4188781dd9613a3
SHA=d0d92c4191c776bcc7bce84e0d2156c3a744c115fb9a9ccbcaac908313708c96
T=$R/build/dl/tpch-kit-$C.tgz; D=$R/build/bench/tpch/dbgen
sha() { if command -v sha256sum > /dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
[ -x "$D/dbgen" ] && [ "$(cat "$D/VERSION" 2>/dev/null)" = "$C" ] && exit 0
mkdir -p "$R/build/dl"
if [ ! -f "$T" ] || [ "$(sha "$T")" != "$SHA" ]; then
  curl -fsSL "https://codeload.github.com/gregrahn/tpch-kit/tar.gz/$C" -o "$T.part"
  [ "$(sha "$T.part")" = "$SHA" ] || { echo "fetch-dbgen: checksum mismatch" >&2; rm -f "$T.part"; exit 1; }
  mv "$T.part" "$T"
fi
rm -rf "$D" && mkdir -p "$D"
tar xzf "$T" -C "$D" --strip-components 2 "tpch-kit-$C/dbgen"; rm -rf "$D/answers/../reference" "$D/check_answers"
# (gcc 10+ defaults to -fno-common; dbgen defines globals in headers)
make -C "$D" CC="${CC:-cc}" DATABASE=POSTGRESQL MACHINE=LINUX WORKLOAD=TPCH CFLAGS="-O2 -fcommon -DDBNAME=\\\"dss\\\" -DLINUX -DPOSTGRESQL -DTPCH -DRNG_TEST -D_FILE_OFFSET_BITS=64 -w" dbgen > "$D/make.log" 2>&1 || { tail -20 "$D/make.log"; exit 1; }
echo "$C" > "$D/VERSION"
echo "fetch-dbgen: $D/dbgen"
