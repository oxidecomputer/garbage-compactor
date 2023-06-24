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

NAM='neovim'
VER='0.6.1'
URL="https://github.com/neovim/neovim/archive/refs/tags/v$VER.tar.gz"

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

file="$ARTEFACT/$NAM-$VER.tar.bz2"
download_to "$NAM" "$URL" "$file"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to "$NAM" "$file" "$SRC64" --strip-components=1

header "building $NAM"

export PATH="$WORKAROUND:$PATH"

cd "$SRC64"

stamp="$SRC64/patched.stamp"
if [[ ! -f "$SRC64/patched.stamp" ]]; then
	for f in $ROOT/patches/*.patch; do
		if [[ ! -f $f ]]; then
			continue
		fi

		info "apply patch $f"
		patch --verbose -p1 < "$f"
	done
fi

#
# Note that we are careful not to specify DESTDIR here, as it appears to leak
# in to the dependency builds which should install into $SRC64/.deps
#
info "build deps..."
PATH="/usr/gnu/bin:$PATH" \
    gmake \
    CMAKE_BUILD_TYPE=Release \
    CMAKE_INSTALL_PREFIX=/usr \
    deps

info "build nvim..."
PATH="/usr/gnu/bin:$PATH" \
    gmake \
    CMAKE_BUILD_TYPE=Release \
    CMAKE_INSTALL_PREFIX=/usr

info "install..."
PATH="/usr/gnu/bin:$PATH" \
    gmake \
    CMAKE_BUILD_TYPE=Release \
    CMAKE_INSTALL_PREFIX=/usr \
    DESTDIR=$PROTO \
    install

#
# Fix some of the locale delivery stuff to align with other packages.
#
for l in ko pl zh_TW zh_CN; do
	mv "$PROTO/usr/share/locale/$l.UTF-8" "$PROTO/usr/share/locale/$l"
done

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package "editor/$NAM" \
	    'Vim fork focused on extensibility and usability' \
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
