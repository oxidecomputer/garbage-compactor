#!/bin/bash
#
# Copyright 2025 Oxide Computer Company
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
NAM='tpm2-tss'
VER='4.1.3'
URL="https://github.com/tpm2-software/tpm2-tss/releases/download"
URL+="/$VER/$NAM-$VER.tar.gz"
SHA256='37f1580200ab78305d1fc872d89241aaee0c93cbe85bc559bf332737a60d3be8'

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
    '/library/json-c' \
    '/library/libftdi1' \
    '/library/libusb' \
    '/web/curl'

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

extract_to "$NAM" "$file" "$SRC32" --strip-components=1
extract_to "$NAM" "$file" "$SRC64" --strip-components=1

header "building $NAM"

#
# Common configure arguments for 32- and 64-bit library builds:
#
common_args=(
	'--prefix=/usr'
	'--sysconfdir=/etc'
	'--enable-shared=yes'
	'--enable-static=no'

#8608:LIBFTDI_CFLAGS = -I/usr/include/libftdi1 -I/usr/include/libusb-1.0
#8609:LIBFTDI_LIBS = -L/usr/lib/amd64 -lftdi1 -lusb-1.
)

export PATH="$WORKAROUND:$PATH"

cd "$SRC32"

PLVL=0 apply_patches "$ROOT/patches"

#LIBUSB_CFLAGS='-I/usr/include/libusb-1.0' \
#LIBUSB_LIBS='-lusb-1.0' \
#LIBFTDI_CFLAGS='-I/usr/include/libftdi1' \
#LIBFTDI_LIBS='-lftdi1' \

info "configure 32bit..."
PKG_CONFIG_PATH='/usr/lib/pkgconfig' \
MAKE='gmake' \
CC="$GCC_DIR/gcc -m32" \
CFLAGS='-m32 -gdwarf-2 ' \
    ./configure \
    "${common_args[@]}" \
    --libdir=/usr/lib

info "make 32bit..."
gmake -j8

info "make install 32bit..."
gmake install DESTDIR="$PROTO"

cd "$SRC64"

PLVL=0 apply_patches "$ROOT/patches"

#LIBUSB_CFLAGS='-I/usr/include/libusb-1.0' \
#LIBUSB_LIBS='-lusb-1.0' \

info "configure 64bit..."
PKG_CONFIG_PATH='/usr/lib/pkgconfig/amd64' \
MAKE='gmake' \
CC="$GCC_DIR/gcc -m64" \
CFLAGS='-m64 -gdwarf-2 -msave-args ' \
    ./configure \
    "${common_args[@]}" \
    --libdir=/usr/lib/amd64

info "make 64bit..."
gmake -j8

info "make install 64bit..."
gmake install DESTDIR="$PROTO"

libraries=(
	'libtss2-esys.so.0.0.1'
	'libtss2-fapi.so.1.0.0'
	'libtss2-mu.so.0.0.1'
	'libtss2-policy.so.0.0.0'
	'libtss2-rc.so.0.0.0'
	'libtss2-sys.so.1.0.1'
	'libtss2-tcti-cmd.so.0.0.0'
	'libtss2-tcti-device.so.0.0.0'
	'libtss2-tcti-i2c-ftdi.so.0.0.0'
	'libtss2-tcti-i2c-helper.so.0.0.0'
	'libtss2-tcti-mssim.so.0.0.0'
	'libtss2-tcti-pcap.so.0.0.0'
	'libtss2-tcti-spi-ftdi.so.0.0.0'
	'libtss2-tcti-spi-helper.so.0.0.0'
	'libtss2-tcti-spi-ltt2go.so.0.0.0'
	'libtss2-tcti-swtpm.so.0.0.0'
	'libtss2-tctildr.so.0.0.0'
)

for f in "${libraries[@]}"; do
	printf ' * CTF convert: %s\n' "$f"
	"$CTFCONVERT" "$PROTO/usr/lib/amd64/$f"
	"$CTFCONVERT" "$PROTO/usr/lib/$f"
done

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	CREV=0
	BRANCH="2.$CREV" make_package "library/$NAM" \
	    'OSS implementation of the TCG TPM2 Software Stack (TSS2)' \
	    "$WORK/proto"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	pkgrecv -a -d "$WORK/$NAM-$VER.p5p" -s "$WORK/repo" "$NAM@$VER-2.$CREV"
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
