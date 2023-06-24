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

NAM='pivy'
VER="0.10.0"
REPO="https://github.com/arekinath/pivy.git"
COMMIT='ef6477bf96c5df44653c193a6fbd1e63744141ba'

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
    '/system/library/libpcsc' \
    '/library/json-c'

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

header "building $NAM"

cd "$SRC64"

info "build $NAM..."
MAKE=gmake \
gmake -j8 \
  CTFCONVERT=/opt/onbld/bin/i386/ctfconvert \
  USE_ZFS=no \
  USE_JSONC=yes \
  PCSC_CFLAGS= PCSC_LIBS=-lpcsc \
  prefix=/usr \
  bingroup=bin

header "installing $NAM"

#
# For now, we do this on our own because the install target does not meet our
# exact needs for proto area assembly.
#
commands=(
	pivy-tool
	pivy-agent
	pivy-box
	pivy-ca
)
mkdir -p "$PROTO/usr/bin"
for cmd in "${commands[@]}"; do
	info "installing $cmd..."
	/usr/sbin/install -f "$PROTO/usr/bin" "$SRC64/$cmd"
	info "CTF conversion for $cmd..."
	"$CTFCONVERT" "$PROTO/usr/bin/$cmd"
done

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package "security/$NAM" \
	    'Use PIV tokens (Yubikeys, etc) for SSH, data encryption, etc.' \
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
