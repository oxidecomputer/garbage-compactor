#!/bin/bash

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

NAM='picocom'
VER='3.1.999' # unreleased bits after 3.1, may one day be 3.2
REV='1acf1ddabaf3576b4023c4f6f09c5a3e4b086fb8'
URL="https://github.com/npat-efault/picocom/archive/$REV.tar.gz"

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

file="$ARTEFACT/$NAM-$VER.tar.gz"
download_to "$NAM" "$URL" "$file"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to "$NAM" "$file" "$SRC64" --strip-components=1

header "building $NAM"

export PATH="$WORKAROUND:$PATH"

cd "$SRC64"

apply_patches "$ROOT/patches"

info "build picocom..."
gmake picocom picocom.1

info "install..."
#
# There is no install target!  Arrange things by hand...
#
mkdir -p "$PROTO/usr/bin"
rm -f "$PROTO/usr/bin/picocom"
cp "$SRC64/picocom" "$PROTO/usr/bin/picocom"
mkdir -p "$PROTO/usr/share/man/man1"
rm -f "$PROTO/usr/share/man/man1/picocom.1"
cp "$SRC64/picocom.1" "$PROTO/usr/share/man/man1/picocom.1"

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package "terminal/$NAM" \
	    'Minimal dumb-terminal emulation program' \
	    "$WORK/proto" \
	    "$ROOT/overrides.p5m"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	pkgrecv -a -d "$WORK/$NAM-$VER.p5p" -s "$WORK/repo" "$NAM@$VER-1.0"
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
