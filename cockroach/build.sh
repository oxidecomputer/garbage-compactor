#!/bin/bash

set -o errexit
set -o pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/../lib/common.sh"

export GOPATH="$ROOT/cache/gopath"
export GOCACHE="$ROOT/cache/gocache"
export YARN_CACHE_FOLDER="$ROOT/cache/yarncache"
YARNROOT="$ROOT/cache/yarnroot"

ARTEFACT="$ROOT/artefact"
mkdir -p "$ARTEFACT"
WORK="$ROOT/work"
mkdir -p "$WORK"

#
# Directory for workaround scripts that we can put in PATH:
#
WORKAROUND="$ROOT/cache/workaround"
rm -rf "$WORKAROUND"
mkdir -p "$WORKAROUND"

VER='22.1.5'
COCKROACHDB_CLONE_REF="v$VER"

GOVER='1.17.11'
SYSGOVER=$( (pkg info go-117 || true) | awk '/Version:/ { print $NF }')
if [[ "$SYSGOVER" != "$GOVER" ]]; then
	fatal 'install or update go-116 package'
fi
export GOROOT='/opt/ooce/go-1.17'
info "using $GOROOT/bin/go: $($GOROOT/bin/go version)"

YARNVER='1.22.5'
YARNURL="https://github.com/yarnpkg/yarn/releases/download/v$YARNVER/yarn-v$YARNVER.tar.gz"
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

yarnfile="$ARTEFACT/yarn-v$YARNVER.tar.gz"
download_to yarn "$YARNURL" "$yarnfile"

stamp="$ROOT/cache/cloned.stamp"
if [[ ! -f "$stamp" ]]; then
	repo=https://github.com/cockroachdb/cockroach
	info "cloning $repo branch $COCKROACHDB_CLONE_REF ..."
	mkdir -p "$ROOT/cache/gopath/src/github.com/cockroachdb"
	git clone \
	    --recurse-submodules \
	    --branch $COCKROACHDB_CLONE_REF \
	    --depth 1 \
	    $repo \
	    cache/gopath/src/github.com/cockroachdb/cockroach
	touch "$stamp"
else
	info 'already cloned'
fi

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to yarn "$yarnfile" "$YARNROOT" --strip-components=1

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

cat >"$WORKAROUND/install" <<'EOF'
#!/usr/bin/bash
exec ginstall "$@"
EOF
chmod 0755 "$WORKAROUND/install"

cat >"$WORKAROUND/make" <<'EOF'
#!/usr/bin/bash
exec gmake "$@"
EOF
chmod 0755 "$WORKAROUND/make"

cat >"$WORKAROUND/ps" <<'EOF'
#!/usr/bin/bash
if [[ $1 == '-o' && $2 == 'args=' && $3 && !$4 ]]; then
	exec /usr/bin/ps -o args= -p $3
fi

printf 'ERROR: unknown usage of ps(1): %s\n' "$*" >&2
exit 1
EOF
chmod 0755 "$WORKAROUND/ps"

#
# Build Cockroach:
#
header 'patching cockroach source'

stamp="$ROOT/cache/patched.stamp"
if [[ ! -f "$stamp" ]]; then
	apply_patches "$ROOT/patches" "$GOPATH"
	touch "$stamp"
else
	info 'already patched'
fi

header 'building cockroach'

export PATH="$GOPATH/bin:$GOROOT/bin:$YARNROOT/bin:$WORKAROUND:$PATH"

#
# We want to avoid any CCL-licenced code (enterprise features) because these
# are proprietary software and require a separate licence agreement with the
# Cockroach people.
#
buildtype=oss

args=()
if [[ -n $JOBS ]]; then
	if [[ $JOBS != 1 ]]; then
		args+=( "-j$JOBS" )
	fi
else
	args+=( "-j2" )
fi

#
# The Makefile appears to contain a Performance Improvement that involves
# generating another, smaller Makefile that can be included by the first, and
# which "caches" a slapdash set of values.  Because we patch the Makefile, this
# trips the cache invalidation logic which the comments suggest will "reboot"
# make (it does not) so we do it by hand first:
#
info "running gmake build/defs.mk..."
BUILDCHANNEL=source-archive \
    gmake \
    -C "$GOPATH/src/github.com/cockroachdb/cockroach" \
    "${args[@]}" \
    "build/defs.mk" \
    BUILDTYPE=release

info "running gmake build$buildtype..."
BUILDCHANNEL=source-archive \
    gmake \
    -C "$GOPATH/src/github.com/cockroachdb/cockroach" \
    "${args[@]}" \
    "build$buildtype" \
    BUILDTYPE=release

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=tar
fi

case "$OUTPUT_TYPE" in
ips)
	rm -rf "$WORK/proto"
	mkdir -p "$WORK/proto/opt/oxide/cockroach/$VER/bin"
	cp "$GOPATH/src/github.com/cockroachdb/cockroach/cockroach$buildtype" \
	    "$WORK/proto/opt/oxide/cockroach/$VER/bin/cockroach"
	#
	# Make a package per release version series; e.g., 21.1.0 and 21.1.1
	# will be package "cockroachdb-211".
	#
	suffix=$(awk -F. '{ print $1$2 }' <<< "$VER")
	make_package "oxide/cockroachdb-$suffix" \
	    'CockroachDB is a distributed SQL database management system' \
	    "$WORK/proto"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	exit 0
	;;
tar)
	#
	# Fall through to original tar processing below...
	#
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

info 'copying final executables and libraries...'

rm -rf "$WORK/tmp"
mkdir -p "$WORK/tmp"
rm -rf "$WORK/cockroach-v$VER"
mkdir -p "$WORK/cockroach-v$VER/bin"
mkdir -p "$WORK/cockroach-v$VER/lib"

#
# Get the set of libraries we need to include from the build system.
# (this is somewhat less than ideal, but will do until we are packaging
# correctly...)
#
libs=$(ldd "$GOPATH/src/github.com/cockroachdb/cockroach/cockroach$buildtype" |
    awk '$3 !~ "^/lib/64" { print $3 }')
for lib in $libs; do
	bn=$(basename "$lib")
	cp "$lib" "$WORK/tmp/$bn"
	chmod 0755 "$WORK/tmp/$bn"
	/usr/bin/elfedit -e 'dyn:rpath $ORIGIN/../lib' "$WORK/tmp/$bn"
	mv "$WORK/tmp/$bn" "$WORK/cockroach-v$VER/lib/$bn"
done

cp "$GOPATH/src/github.com/cockroachdb/cockroach/cockroach$buildtype" \
    "$WORK/tmp/cockroach"
/usr/bin/elfedit -e 'dyn:rpath $ORIGIN/../lib' "$WORK/tmp/cockroach"
mv "$WORK/tmp/cockroach" "$WORK/cockroach-v$VER/bin"

ldd "$WORK/cockroach-v$VER/bin/cockroach"

/usr/bin/tar cvfz $WORK/cockroach-v$VER.illumos.tar.gz -C $WORK cockroach-v$VER

rm -rf "$WORK/cockroach-v$VER"
rm -rf "$WORK/tmp"

header 'build output:'
find "$WORK" -type f -ls
