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
SRC64="$WORK/src64"
mkdir -p "$SRC64"
PROTO="$WORK/proto"
mkdir -p "$PROTO"
TOOLS="$WORK/tools"
mkdir -p "$TOOLS"

NAM='humility'
REPO="https://github.com/oxidecomputer/$NAM.git"

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

if [[ -d "$SRC64/.git" ]]; then
	(cd "$SRC64" &&
	    git clean -fxd &&
	    git fetch --all &&
	    git reset --hard origin/master)
else
	rm -rf "$SRC64"
	git clone "$REPO" "$SRC64"
fi

#
# We need a cargo-readme binary for the humility build to complete.  Build one
# just for us:
#
cargo install --locked --root "$TOOLS" cargo-readme
export PATH="$TOOLS/bin:$PATH"

header "building $NAM"

cd "$SRC64"

#
# Determine the version embedded in this humility binary.  Not every commit
# will bump the version number, so we include the repository commit count as an
# additional component.
#
commit_count=$(git rev-list --count HEAD)
VER=$(cargo metadata --format-version 1 |
    jq -r '.packages | map(select(.name == "humility-bin")) | .[].version'
    ).$commit_count

info "version is $VER"
if pkg info -g "$HELIOS_REPO" "humility@$VER"; then
	fatal 'package already published'
fi

info "build $NAM..."
cargo build --release

header "installing $NAM"
rm -rf "$PROTO"
mkdir -p "$PROTO/usr/bin"
cp target/release/humility "$PROTO/usr/bin/humility"

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package "developer/debug/$NAM" \
	    'Debugger for Hubris' \
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
