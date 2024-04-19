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

NAM='lua'
BASEVER='5.4'
VER="$BASEVER.6"
URL="https://www.lua.org/ftp/lua-$VER.tar.gz"
SHA256='7d5ea1b9cb6aa0b59ca3dde1c6adcb57ef83a1ba8e5432c0ecd06bf439b3ad88'

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
download_to "$NAM" "$URL" "$file" "$SHA256"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to "$NAM" "$file" "$SRC64" --strip-components=1

header "building $NAM"

export PATH="$WORKAROUND:$PATH"

cd "$SRC64"

info "make 64bit..."
gmake -j8 \
    INSTALL_TOP=/usr \
    INSTALL_INC="/usr/include/lua/$BASEVER" \
    INSTALL_MAN=/usr/share/man \
    INSTALL_LIB=/usr/lib/amd64 \
    MYCFLAGS='-m64 -msave-args -gdwarf-2' \
    solaris

info "make install 64bit..."
gmake \
    INSTALL_TOP="$PROTO/usr" \
    INSTALL_INC="$PROTO/usr/include/lua/$BASEVER" \
    INSTALL_MAN="$PROTO/usr/share/man" \
    INSTALL_LIB="$PROTO/usr/lib/amd64" \
    install

#
# We don't want to ship a static library, and the software does not appear (at
# least by default) to be willing to build a shared library.  We still ship the
# includes, so that modules (e.g., via "LuaRocks") can build a shared library
# that the lua binary can then load.
#
rm -rf "$PROTO/usr/lib"

for f in lua luac; do
	#
	# The Lua folk apparently make backwards incompatible changes from
	# minor to minor (sigh) so we'll name the binary for the shipped
	# minor version; e.g., lua5.4.
	#
	mv "$PROTO/usr/bin/$f" "$PROTO/usr/bin/$f$BASEVER"
	"$CTFCONVERT" "$PROTO/usr/bin/$f$BASEVER"

	#
	# And, for convenience, also create an unversioned symlink.  This
	# should be mediated, but I am already in my pyjamas.
	#
	ln -s "$f$BASEVER" "$PROTO/usr/bin/$f"
done

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	CREV=0
	PNAM="$NAM-${BASEVER/.}"
	BRANCH="2.$CREV" make_package "developer/$PNAM" \
	    'a lightweight, embeddable scripting language' \
	    "$WORK/proto"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	pkgrecv -a -d "$WORK/$PNAM-$VER.p5p" -s "$WORK/repo" \
	    "$PNAM@$VER-2.$CREV"
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
