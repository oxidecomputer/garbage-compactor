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
NAM='tpm2-tools'
VER='5.7'
URL="https://github.com/tpm2-software/tpm2-tools/releases/download"
URL+="/$VER/$NAM-$VER.tar.gz"
SHA256='3810d36b5079256f4f2f7ce552e22213d43b1031c131538df8a2dbc3c570983a'

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
    '/library/tpm2-tss' \
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
	'--disable-hardening'
)

export PATH="$WORKAROUND:$PATH"

cd "$SRC64"

PLVL=0 apply_patches "$ROOT/patches"

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

binaries=(
	'tpm2'
	'tss2'
)

for f in "${binaries[@]}"; do
	printf ' * CTF convert: %s\n' "$f"
	"$CTFCONVERT" "$PROTO/usr/bin/$f"
done

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	CREV=0
	BRANCH="2.$CREV" make_package "security/$NAM" \
	    'Trusted Platform Module (TPM2.0) tools' \
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
