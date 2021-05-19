#!/bin/bash

set -o errexit
set -o pipefail

function info {
	printf 'INFO: %s\n' "$*"
}

function header {
	printf -- '\n'
	printf -- '----------------------------------------------------------\n'
	printf -- 'INFO: %s\n' "$*"
	printf -- '----------------------------------------------------------\n'
	printf -- '\n'
}

function fatal {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

function extract_to {
	local name="$1"
	local tar="$2"
	local outdir="$3"
	local extra="$4"

	stamp="$outdir/.extracted"
	if [[ ! -f "$stamp" ]]; then
		rm -rf "$outdir"
		info "extracting $name..."
		mkdir -p "$outdir"
		gtar -C "$outdir" $extra -xzf "$tar"
		info "extracted $name ok"
		touch "$stamp"
	else
		info "$name extracted already"
	fi

	return 0
}

function download_to {
	local name="$1"
	local url="$2"
	local path="$3"

	if [[ ! -f "$path" ]]; then
		info "downloading $name..."
		if ! curl -fL -o "$path" "$url"; then
			fatal "$name download failed"
			exit 1
		fi
		info "ok"
	else
		info "downloaded $name already"
	fi

	return 0
}

function make_package {
	local name="$1"
	local summary="$2"
	local proto="$3"
	local mf="$WORK/input.mf"
	local publisher="helios-dev"
	local branch='1.0'
	local repo="$WORK/repo"

	#
	# Generate the base package manifest:
	#
	printf '%% generating base manifest...\n'
	rm -f "$mf"
	printf 'set name=pkg.fmri value=pkg://%s/%s@%s-%s\n' \
	    "$publisher" "$name" "$VER" "$branch" >> "$mf"
	printf 'set name=pkg.summary value="%s"\n' "$summary" >> "$mf"

	#
	# Add all files found in the proto area.
	#
	# We keep timestamps for any Python files (and their compiled versions)
	# to prevent their immediate recompilation on the installed system.
	#
	printf '%% generating file list...\n'
	pkgsend generate -T '*.py' -T '*.pyc' "$proto" >> "$mf"

	#
	# Append pkgmogrify directives to fix up the generated manifest, and
	# transform the manifest now:
	#
	printf '%% transforming manifest...\n'
	rm -f "$WORK/step1.mf"
	printf '<transform dir path=opt$ -> drop>\n' >> "$mf"
	pkgmogrify -v -O "$WORK/step1.mf" "$mf"

	#
	# Walk through the packaged files and generate a list of dependencies:
	#
	printf '%% generating dependency list...\n'
	rm -f "$WORK/step2.mf"
	pkgdepend generate -d "$proto" "$WORK/step1.mf" > "$WORK/step2.mf"

	#
	# Resolve those dependencies to specific packages and versions:
	#
	printf '%% resolving dependencies...\n'
	rm -f "$WORK/step2.mf.res"
	pkgdepend resolve "$WORK/step2.mf"

	printf -- '===== RESOLVED DEPENDENCIES: =====\n'
	cat "$WORK/step2.mf.res"
	printf -- '==================================\n'

	printf '%% creating repository...\n'
	rm -rf "$repo"
	pkgrepo create "$repo"
	pkgrepo add-publisher -s "$repo" "$publisher"

	rm -f "$WORK/final.mf"
	cat "$WORK/step1.mf" "$WORK/step2.mf.res" > "$WORK/final.mf"

	printf '%% publishing...\n'
	pkgsend publish -d "$proto" -s "$repo" "$WORK/final.mf"

	printf '%% ok\n'
}

ROOT=$(cd "$(dirname "$0")" && pwd)
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

VER='20.2.5'
URL="https://binaries.cockroachdb.com/cockroach-v$VER.src.tgz"

GOVER='1.16.4'
SYSGOVER=$(pkg info go-116 | awk '/Version:/ { print $NF }')
if [[ "$SYSGOVER" != "$GOVER" ]]; then
	fatal 'install or update go-116 package'
fi
export GOROOT='/opt/ooce/go-1.16'
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

file="$ARTEFACT/cockroach-v$VER.src.tgz"
download_to cockroach "$URL" "$file"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to yarn "$yarnfile" "$YARNROOT" --strip-components=1

#
# The Cockroach DB source archive contains a wrapper Makefile at the top level
# which merely redirects one into the source that is set up, and sets GOPATH
# and BUILDCHANNEL='source-archive'.  We'll just extract it into our expected
# GOPATH and ignore the rest.
#
#rm -rf "$GOPATH" # XXX
extract_to cockroach "$file" "$GOPATH" --strip-components=1

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
# Build Cockroach:
#
header 'patching cockroach source'

function vendor_replace {
	local targ="$GOPATH/src/github.com/cockroachdb/cockroach/vendor/$1"
	info "vendor replace $1"
	rm -rf "$targ/"
	cp -r "$ROOT/patches/$1/" "$targ/"
}

stamp="$ROOT/cache/patched.stamp"
if [[ ! -f "$stamp" ]]; then
	for f in $ROOT/patches/*.patch; do
		if [[ ! -f $f ]]; then
			continue;
		fi

		info "apply patch $f"
		(cd "$GOPATH" && patch --verbose -p1 < "$f")
	done

	info 'copying in extra files...'
	cp $ROOT/patches/sysutil_illumos.go \
	    "$GOPATH/src/github.com/cockroachdb/cockroach/pkg/util/sysutil/"
	cp $ROOT/patches/stderr_redirect_illumos.go \
	    "$GOPATH/src/github.com/cockroachdb/cockroach/pkg/util/log/"

	vendor_replace "github.com/elastic/gosigar"
	vendor_replace "github.com/Azure/azure-storage-blob-go"
	vendor_replace "github.com/google/uuid"
	vendor_replace "github.com/knz/strtime"
	vendor_replace "github.com/cockroachdb/pebble/vfs"

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
# The source archive for CockroachDB contains a pre-rendered copy of the web
# assets, ostensibly to avoid requiring the full set of Node-based software
# that is used to regenerate it.  Because we are patching the UI, we need to
# force the regeneration of the Go source file that contains the
# webpack/minified version of the Javascript before trying to build the final
# binary:
#
info "running gmake ui-generate-oss..."
BUILDCHANNEL=source-archive \
    gmake \
    -C "$GOPATH/src/github.com/cockroachdb/cockroach" \
    "${args[@]}" \
    "ui-generate-oss" \
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
