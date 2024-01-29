#!/bin/bash
#
# Copyright 2024 Oxide Computer Company
#

set -o errexit
set -o pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/../lib/common.sh"

ARTEFACT="$ROOT/artefact"
mkdir -p "$ARTEFACT"
WORK="$ROOT/work"
mkdir -p "$WORK"
SRC64="$WORK/src64"
mkdir -p "$SRC64"
PROTO="$WORK/proto"
mkdir -p "$PROTO"

#
# Directory for workaround scripts that we can put in PATH:
#
WORKAROUND="$ROOT/cache/workaround"
rm -rf "$WORKAROUND"
mkdir -p "$WORKAROUND"

NAM='column'
VER='0.0.0.20181004'
COMMIT='7b4463b6b3bb49b964ec5cf241dd2a2ff0ecc116'
BASE='https://raw.githubusercontent.com/TritonDataCenter/illumos-joyent'

if [[ -x /usr/gcc/10/bin/gcc ]]; then
	GCC_DIR=/usr/gcc/10/bin
elif [[ -x /opt/gcc-10/bin/gcc ]]; then
	GCC_DIR=/opt/gcc-10/bin
else
	fatal "Could not find GCC in any expected location"
fi
info "using $GCC_DIR/gcc: $($GCC_DIR/gcc --version | head -1)"
info "using $GCC_DIR/g++: $($GCC_DIR/g++ --version | head -1)"

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

file_c="$ARTEFACT/column.c"
download_to "$NAM.c" "$BASE/$COMMIT/usr/src/cmd/column/column.c" "$file_c"

file_1="$ARTEFACT/column.1"
download_to "$NAM.1" "$BASE/$COMMIT/usr/src/man/man1/column.1" "$file_1"

header "building $NAM"

export PATH="$WORKAROUND:$PATH"

cd "$SRC64"

info "build $NAM..."
gcc -m64 -gdwarf-2 -o column "$file_c"

info "install $NAM..."
mkdir -p "$PROTO/usr/bin"
cp column "$PROTO/usr/bin/column"
mkdir -p "$PROTO/usr/share/man/man1"
cp "$file_1" "$PROTO/usr/share/man/man1/column.1"

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package "text/$NAM" \
	    'basic utility for reformatting tables and lists' \
	    "$WORK/proto" \
	    "$ROOT/overrides.p5m"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	pkgrecv -a -d "$WORK/$NAM-$VER.p5p" -s "$WORK/repo" "$NAM@$VER-2.0"
	ls -lh "$WORK/$NAM-$VER.p5p"
	exit 0
	;;
none)
	#
	# Just leave the build tree as-is without doing any more work.
	#
	exit 0
	;;
*)
	fatal "unknown output type: $OUTPUT_TYPE"
	;;
esac
