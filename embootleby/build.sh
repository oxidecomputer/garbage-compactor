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
TOOLS="$WORK/tools"
mkdir -p "$TOOLS"

NAM='embootleby'
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
	    git reset --hard origin/main)
else
	rm -rf "$SRC64"
	git clone "$REPO" "$SRC64"
fi

header "building $NAM"

cd "$SRC64"

#
# Determine the version of at least one of the crates.  We currently assume
# that all the crates will have the same version (which is true at time of
# writing!).  Not every commit will bump the version number, so we include the
# repository commit count as an additional component.
#
commit_count=$(git rev-list --count HEAD)
VER=$(cargo metadata --format-version 1 |
    jq -r '.packages | map(select(.name == "embootleby")) | .[].version'
    ).$commit_count

info "version is $VER"
if pkg info -g https://pkg.oxide.computer/helios-dev "$NAM@$VER"; then
	fatal 'package already published'
fi

info "build $NAM..."
cargo build --release --locked

header "installing $NAM"
rm -rf "$PROTO"
mkdir -p "$PROTO/usr/bin"
for cmd in embootleby; do
	cp "target/release/$cmd" "$PROTO/usr/bin/$cmd"
done

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package "developer/debug/$NAM" \
	    'Bootleby support tools' \
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
