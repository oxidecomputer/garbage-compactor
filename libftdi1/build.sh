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
CONFUSE32="$WORK/confuse32"
mkdir -p "$CONFUSE32"
CONFUSE64="$WORK/confuse64"
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

#
# libftdi depends on libconfuse, which we will build into that library
# statically...
#
URL2=https://www.intra2net.com/en/developer/libftdi/download/confuse-2.5.tar.gz


NAM='libftdi1'
VER='1.5'
URL="https://www.intra2net.com/en/developer/libftdi/download/$NAM-$VER.tar.bz2"

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
    '/library/libusb'

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

file="$ARTEFACT/$NAM-$VER.tar.gz"
download_to "$NAM" "$URL" "$file"

file2="$ARTEFACT/confuse-2.5.tar.gz"
download_to "confuse" "$URL2" "$file2"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to "confuse" "$file2" "$CONFUSE32" --strip-components=1
extract_to "confuse" "$file2" "$CONFUSE64" --strip-components=1

extract_to "$NAM" "$file" "$SRC32" --strip-components=1
extract_to "$NAM" "$file" "$SRC64" --strip-components=1

header "building $NAM"

export PATH="$WORKAROUND:$PATH"

cd "$CONFUSE32"
stamp="$CONFUSE32/patched.stamp"
if [[ ! -f "$CONFUSE32/patched.stamp" ]]; then
	for f in $ROOT/patches/confuse/*.patch; do
		if [[ ! -f $f ]]; then
			continue
		fi

		info "apply patch $f"
		patch --verbose -p1 < "$f"
	done
fi

info 'configuring confuse 32bit...'
CFLAGS='-m32 -gdwarf-2' \
    ./configure \
    --prefix=$CONFUSE32/sproto \
    --enable-static=yes \
    --enable-shared=no
info 'building confuse 32bit...'
gmake -j8
info 'installing confuse 32bit...'
gmake install

cd "$CONFUSE64"
stamp="$CONFUSE64/patched.stamp"
if [[ ! -f "$CONFUSE64/patched.stamp" ]]; then
	for f in $ROOT/patches/confuse/*.patch; do
		if [[ ! -f $f ]]; then
			continue
		fi

		info "apply patch $f"
		patch --verbose -p1 < "$f"
	done
fi

info 'configuring confuse 64bit...'
CFLAGS='-m64 -gdwarf-2 -msave-args' \
    ./configure \
    --prefix=$CONFUSE64/sproto \
    --enable-static=yes \
    --enable-shared=no
info 'building confuse 64bit...'
gmake -j8
info 'installing confuse 64bit...'
gmake install

cd "$SRC32"

stamp="$SRC32/patched.stamp"
if [[ ! -f "$SRC32/patched.stamp" ]]; then
	for f in $ROOT/patches/libftdi1/*.patch; do
		if [[ ! -f $f ]]; then
			continue
		fi

		info "apply patch $f"
		patch --verbose -p1 < "$f"
	done
fi

mkdir build
cd build
CFLAGS='-m32 -gdwarf-2' \
    cmake \
    -Wno-dev \
    -DCONFUSE_LIBRARY="$CONFUSE32/sproto/lib/libconfuse.a" \
    -DCONFUSE_INCLUDE_DIR="$CONFUSE32/sproto/include" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DSTATICLIBS=OFF \
    ..

info "make..."
gmake -j8

info "make install..."
gmake install DESTDIR="$PROTO"

cd "$SRC64"

stamp="$SRC64/patched.stamp"
if [[ ! -f "$SRC64/patched.stamp" ]]; then
	for f in $ROOT/patches/libftdi1/*.patch; do
		if [[ ! -f $f ]]; then
			continue
		fi

		info "apply patch $f"
		patch --verbose -p1 < "$f"
	done
fi

mkdir build
cd build
PKG_CONFIG_PATH='/usr/lib/amd64/pkgconfig' \
CFLAGS='-m64 -gdwarf-2 -msave-args' \
LDFLAGS='-R/usr/lib/amd64' \
    cmake \
    -Wno-dev \
    -DCONFUSE_LIBRARY="$CONFUSE64/sproto/lib/libconfuse.a" \
    -DCONFUSE_INCLUDE_DIR="$CONFUSE64/sproto/include" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib/amd64 \
    -DLIB_SUFFIX=/amd64 \
    -DSTATICLIBS=OFF \
    ..

info "make..."
gmake -j8

info "make install..."
gmake install DESTDIR="$PROTO"

for f in 'libftdi1.so.2.5.0'; do
	"$CTFCONVERT" "$PROTO/usr/lib/amd64/$f"
	"$CTFCONVERT" "$PROTO/usr/lib/$f"
done

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	CREV=0
	BRANCH=2.$CREV make_package "library/$NAM" \
	    'a library for communicating with USB and Bluetooth HID devices' \
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
