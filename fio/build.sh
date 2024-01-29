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

#
# Directory for workaround scripts that we can put in PATH:
#
WORKAROUND="$ROOT/cache/workaround"
rm -rf "$WORKAROUND"
mkdir -p "$WORKAROUND"

NAM='fio'
VER='3.29'
URL="https://github.com/axboe/fio/archive/$NAM-$VER.tar.gz"
SHA256='3ad22ee9c545afae914f399886e9637a43d1b3aa5dfcf6966ed83e633759acb7'

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
    '/library/libnbd'

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

file="$ARTEFACT/$NAM-$VER.src.tgz"
download_to fio "$URL" "$file" "$SHA256"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to fio "$file" "$SRC64" --strip-components=1

#
# Create workaround wrappers:
#
header 'preparing workaround wrappers'

cat >"$WORKAROUND/python2" <<'EOF'
#!/usr/bin/bash
exec /usr/bin/python2.7 "$@"
EOF
chmod 0755 "$WORKAROUND/python2"

cat >"$WORKAROUND/make" <<'EOF'
#!/usr/bin/bash
exec gmake "$@"
EOF
chmod 0755 "$WORKAROUND/make"

cat >"$WORKAROUND/cc" <<EOF
#!/usr/bin/bash
exec "$GCC_DIR/gcc" -m64 "\$@"
EOF
chmod 0755 "$WORKAROUND/cc"

cat >"$WORKAROUND/gcc" <<EOF
#!/usr/bin/bash
exec "$GCC_DIR/gcc" -m64 "\$@"
EOF
chmod 0755 "$WORKAROUND/gcc"

cat >"$WORKAROUND/g++" <<EOF
#!/usr/bin/bash
exec "$GCC_DIR/g++" -m64 "\$@"
EOF
chmod 0755 "$WORKAROUND/g++"

cat >"$WORKAROUND/c++" <<EOF
#!/usr/bin/bash
exec "$GCC_DIR/g++" -m64 "\$@"
EOF
chmod 0755 "$WORKAROUND/c++"

cat >"$WORKAROUND/grep" <<'EOF'
#!/usr/bin/bash
exec ggrep "$@"
EOF
chmod 0755 "$WORKAROUND/grep"

cat >"$WORKAROUND/sed" <<'EOF'
#!/usr/bin/bash
exec gsed "$@"
EOF
chmod 0755 "$WORKAROUND/sed"

cat >"$WORKAROUND/ginstall" <<'EOF'
#!/usr/bin/bash
exec /usr/gnu/bin/install "$@"
EOF
chmod 0755 "$WORKAROUND/ginstall"

cat >"$WORKAROUND/make" <<'EOF'
#!/usr/bin/bash
exec gmake "$@"
EOF
chmod 0755 "$WORKAROUND/make"

#
# Build fio:
#
header 'patching fio source'

cd "$SRC64"

apply_patches "$ROOT/patches"

header 'building fio'

export PATH="$WORKAROUND:$PATH"

cd "$SRC64"

info 'running configure...'
./configure \
    --prefix=/usr \
    --disable-http \
    --enable-libnbd

args=()
if [[ -n $JOBS ]]; then
	if [[ $JOBS != 1 ]]; then
		args+=( "-j$JOBS" )
	fi
else
	args+=( "-j8" )
fi

info "make 64bit..."
gmake mandir=/usr/share/man "${args[@]}"

info "running gmake install..."
gmake install mandir=/usr/share/man DESTDIR="$PROTO"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package "system/test/$NAM" \
	    'Flexible IO Tester' \
	    "$PROTO" \
	    "$ROOT/overrides.p5m"
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
