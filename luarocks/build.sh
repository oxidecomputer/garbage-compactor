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

NAM='luarocks'
VER='3.11.0'
LUAVER='5.4'
URL="https://luarocks.org/releases/luarocks-$VER.tar.gz"
SHA256='25f56b3c7272fb35b869049371d649a1bbe668a56d24df0a66e3712e35dd44a6'

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
    "/developer/lua-${LUAVER/.}"

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

export PATH="$WORKAROUND:$PATH"

cd "$SRC64"

info "configure..."
./configure \
    --prefix=/usr \
    --lua-version="$LUAVER" \
    --with-lua-interpreter="lua$LUAVER" \
    --with-lua-bin=/usr/bin \
    --with-lua-lib=/usr/lib/amd64 \
    --with-lua-include="/usr/include/lua/$LUAVER"

info "make 64bit..."
gmake -j8

info "make install 64bit..."
gmake \
    DESTDIR="$PROTO" \
    install

for f in luarocks luarocks-admin; do
	#
	# Rename the shipped scripts so that they include the Lua minor version
	# in the name:
	#
	mv "$PROTO/usr/bin/$f" "$PROTO/usr/bin/$f-$LUAVER"

	#
	# And, for convenience, also create an unversioned symlink.  This
	# should be mediated, but I am already in my pyjamas.
	#
	ln -s "$f-$LUAVER" "$PROTO/usr/bin/$f"
done

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	CREV=0
	PNAM="$NAM-${LUAVER/.}"
	BRANCH="$HELIOS_RELEASE.$CREV" make_package "developer/$PNAM" \
	    'the Lua package manager' \
	    "$WORK/proto"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	pkgrecv -a -d "$WORK/$PNAM-$VER.p5p" -s "$WORK/repo" \
	    "$PNAM@$VER-$HELIOS_RELEASE.$CREV"
	ls -lh "$WORK/$PNAM-$VER.p5p"
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
