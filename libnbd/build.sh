#!/bin/bash
#
# Copyright 2026 Oxide Computer Company
#

set -o errexit
set -o pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/../lib/common.sh"

ARTEFACT="$ROOT/artefact"
mkdir -p "$ARTEFACT"
WORK="$ROOT/work"
mkdir -p "$WORK"
SRC32="$WORK/src32"
mkdir -p "$SRC32"
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

NAM='libnbd'
VER='1.10.5'
URL="https://download.libguestfs.org/libnbd/1.10-stable/libnbd-$VER.tar.gz"
SHA256='6d829393233ae7b874e504cb2094394520028ee6e2c35c33731a39b8df8ce613'

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

file="$ARTEFACT/libnbd-$VER.tar.gz"
download_to "$NAM" "$URL" "$file" "$SHA256"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to "$NAM" "$file" "$SRC32" --strip-components=1
extract_to "$NAM" "$file" "$SRC64" --strip-components=1

header "building $NAM"

#
# Common configure arguments for 32- and 64-bit library builds:
#
common_args=(
	'--prefix=/usr'
	'--enable-shared=yes'
	'--enable-static=no'
	'--disable-ocaml'
)

export PATH="$WORKAROUND:$PATH"

cd "$SRC32"

apply_patches "$ROOT/patches"

info "configure 32bit..."
LIBS='-lsocket -lnsl' \
CFLAGS='-m32' \
    ./configure \
    "${common_args[@]}" \
    --disable-python \
    --disable-golang \
    --libdir=/usr/lib

info "make 32bit..."
gmake -j8

info "make install 32bit..."
gmake install DESTDIR="$PROTO"

cd "$SRC64"

apply_patches "$ROOT/patches"

info "configure 64bit..."
LIBS='-lsocket -lnsl' \
CFLAGS='-m64' \
    ./configure \
    "${common_args[@]}" \
    --libdir=/usr/lib/amd64 \

info "make 64bit..."
gmake -j8

info "make install 64bit..."
gmake install DESTDIR="$PROTO"

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package "library/$NAM" \
	    'NBD client library in userspace' \
	    "$WORK/proto"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	pkgrecv -a -d "$WORK/$NAM-$VER.p5p" -s "$WORK/repo" \
	    "$NAM@$VER-$HELIOS_RELEASE.0"
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
