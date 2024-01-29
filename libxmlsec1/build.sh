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

#
# The build will try to detect information about the git repository, but finds
# garbage-compactor.git, because the source archive we use to build Cockroach
# is not, itself, a git repository.
#
cat >"$WORKAROUND/git" <<'EOF'
#!/usr/bin/bash
exit 1
EOF
chmod 0755 "$WORKAROUND/git"

NAM='libxmlsec1'
VER='1.2.35'
URL="http://www.aleksey.com/xmlsec/download/xmlsec1-$VER.tar.gz"

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
    '/library/libxml2' \
    '/library/libxslt' \
    '/library/libusb'

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

file="$ARTEFACT/xmlsec1-$VER.tar.gz"
download_to "$NAM" "$URL" "$file"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to "$NAM" "$file" "$SRC32" --strip-components=1
extract_to "$NAM" "$file" "$SRC64" --strip-components=1

header "building $NAM"

export PATH="$WORKAROUND:$PATH"

cd "$SRC32"

PKG_CONFIG_PATH='/usr/lib/pkgconfig' \
CFLAGS='-m32' \
    ./configure \
    --prefix=/usr \
    --libdir=/usr/lib \
    --enable-static=no

info "make..."
gmake -j8

info "make install..."
gmake install DESTDIR="$PROTO"

cd "$SRC64"

PKG_CONFIG_PATH='/usr/lib/amd64/pkgconfig' \
CFLAGS='-m64' \
LDFLAGS='-R/usr/lib/amd64' \
    ./configure \
    --prefix=/usr \
    --libdir=/usr/lib/amd64 \
    --enable-static=no

info "make..."
gmake -j8

info "make install..."
gmake install DESTDIR="$PROTO"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package "library/$NAM" \
	    'XML Security Library based on libxml2' \
	    "$WORK/proto"
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
