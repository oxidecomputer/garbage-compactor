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

NAM='texinfo'
VER='7.0'
URL="https://ftp.gnu.org/gnu/texinfo/texinfo-$VER.tar.gz"
SHA256='9261d4ee11cdf6b61895e213ffcd6b746a61a64fe38b9741a3aaa73125b35170'

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

file="$ARTEFACT/textinfo-$VER.tar.gz"
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
	'--enable-shared=yes'
	'--enable-static=no'
)

export PATH="$WORKAROUND:$PATH"

cd "$SRC64"

info "configure 64bit..."
CFLAGS='-m64 -gdwarf-2 -msave-args ' \
    ./configure \
    "${common_args[@]}" \
    --libdir=/usr/lib/amd64

info "make 64bit..."
gmake -j8

info "make install 64bit..."
gmake install DESTDIR="$PROTO"

#
# XXX Some of the files don't get built with debug information even though we
# asked for it.  If we can fix that, remove -m below.
#
for f in info install-info; do
	"$CTFCONVERT" -m "$PROTO/usr/bin/$f"
done
for f in "$PROTO/usr/lib/amd64/texinfo/"*.so; do
	"$CTFCONVERT" -m "$f"
done

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	CREV=0
	BRANCH=1.$CREV make_package "text/$NAM" \
	    'official documentation format of the GNU project' \
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
