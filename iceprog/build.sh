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
SRC64="$WORK/src64"
mkdir -p "$SRC64"
PROTO="$WORK/proto"
mkdir -p "$PROTO"
TOOLS="$WORK/tools"
mkdir -p "$TOOLS"

NAM='iceprog'
REPO="https://github.com/yosyshq/icestorm.git"
COMMIT='2bc541743ada3542c6da36a50e66303b9cbd2059'

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
    '/library/libftdi1'

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

if [[ -d "$SRC64/.git" ]]; then
	(cd "$SRC64" &&
	    git clean -fxd)
else
	rm -rf "$SRC64"
	git clone "$REPO" "$SRC64"
fi
(cd "$SRC64" &&
    git fetch origin "$COMMIT" &&
    git reset --hard "$COMMIT")

#
# Some of the makefiles are a bit unfortunate, including at least one library
# we do not need at all.  Trim that out:
#
sed -i -e 's/-lstdc++//' "$SRC64/config.mk"

header "building $NAM"

cd "$SRC64/$NAM"

info "build $NAM..."
CFLAGS='-gdwarf-2 -m64 -msave-args -D__EXTENSIONS__ ' \
PREFIX=/usr \
gmake iceprog

header "installing $NAM"
PREFIX=/usr \
DESTDIR="$PROTO" \
gmake install

info "CTF conversion for $NAM..."
"$CTFCONVERT" "$PROTO/usr/bin/$NAM"

#
# It is not immediately clear that this software has a proper version number,
# so we will make one up that is unlikely to conflict with a real versioning
# scheme should one arise in future.
#
commit_count=$(git rev-list --count HEAD)
VER="0.0.$commit_count"

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package "developer/$NAM" \
	    'simple programming tool for FTDI-based Lattice iCE programmers' \
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
