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

NAM='libusb'
VER='1.0.25'
URL="https://github.com/libusb/libusb/releases/download"
URL+="/v$VER/libusb-$VER.tar.bz2"
SHA256='8a28ef197a797ebac2702f095e81975e2b02b2eeff2774fa909c78a74ef50849'

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
    '/system/header/header-usb' \
    '/system/header/header-ugen'

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

file="$ARTEFACT/libusb-$VER.tar.bz2"
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
	'--enable-log'
	'--disable-system-log'
)

export PATH="$WORKAROUND:$PATH"

cd "$SRC32"

apply_patches "$ROOT/patches"

info "configure 32bit..."
CFLAGS='-m32 -gdwarf-2 ' \
    ./configure \
    "${common_args[@]}" \
    --libdir=/usr/lib

info "make 32bit..."
gmake -j8

info "make install 32bit..."
gmake install DESTDIR="$PROTO"

cd "$SRC64"

apply_patches "$ROOT/patches"

info "configure 64bit..."
CFLAGS='-m64 -gdwarf-2 -msave-args ' \
    ./configure \
    "${common_args[@]}" \
    --libdir=/usr/lib/amd64

info "make 64bit..."
gmake -j8

info "make install 64bit..."
gmake install DESTDIR="$PROTO"

for f in 'libusb-1.0.so.0.3.0'; do
	"$CTFCONVERT" "$PROTO/usr/lib/amd64/$f"
	"$CTFCONVERT" "$PROTO/usr/lib/$f"
done

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	CREV=4
	BRANCH="1.$CREV" make_package "library/$NAM" \
	    'A cross-platform library to access USB devices' \
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
