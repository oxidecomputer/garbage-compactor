#!/bin/bash

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

NAM='yubico-piv-tool'
VER='2.3.0'
URL="https://developers.yubico.com/$NAM/Releases/$NAM-2.3.0.tar.gz"
SHA256='a02a12d9545d1ef7a1b998606d89b7b655a5f5a1437736cf51db083f876f55a9'

if [[ -x /usr/gcc/10/bin/gcc ]]; then
	GCC_DIR=/usr/gcc/10/bin
elif [[ -x /opt/gcc-10/bin/gcc ]]; then
	GCC_DIR=/opt/gcc-10/bin
else
	fatal "Could not find GCC in any expected location"
fi
info "using $GCC_DIR/gcc: $($GCC_DIR/gcc --version | head -1)"
info "using $GCC_DIR/g++: $($GCC_DIR/g++ --version | head -1)"

build_deps \
    '/ooce/developer/cmake' \
    '/developer/check' \
    '/developer/help2man' \
    '/developer/gengetopt'

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

file="$ARTEFACT/$NAM-$VER.tar.gz"
download_to "$NAM" "$URL" "$file" "$SHA256"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to "$NAM" "$file" "$SRC64" --strip-components=1

header "building $NAM"

#
# Common cmake arguments for 32- and 64-bit library builds:
#
common_args=(
	'-DBUILD_STATIC_LIB=OFF'
	'-DCMAKE_INSTALL_PREFIX=/usr'
)

export PATH="$WORKAROUND:$PATH"

cd "$SRC64"

apply_patches "$ROOT/patches"

rm -rf build
mkdir build
cd build

info "cmake 64bit..."
MAKE='gmake' \
LDFLAGS='-R/usr/lib/amd64' \
CFLAGS='-m64 -gdwarf-2 -msave-args -D_REENTRANT ' \
    cmake \
    "${common_args[@]}" \
    '-DYKPIV_INSTALL_PKGCONFIG_DIR=/usr/lib/amd64/pkgconfig' \
    '-DYKPIV_INSTALL_LIB_DIR=/usr/lib/amd64' \
    ..

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
	CREV=0
	BRANCH="1.$CREV" make_package "security/$NAM" \
	    'tools and PKCS#11 modules for YubiKey devices' \
	    "$WORK/proto"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	pkgrecv -a -d "$WORK/$NAM-$VER.p5p" -s "$WORK/repo" "$NAM@$VER-1.$CREV"
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
