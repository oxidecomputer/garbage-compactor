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

VER='20.1.5'
URL="https://binaries.cockroachdb.com/cockroach-v$VER.src.tgz"

GOVER='1.14.6'
GOURL="https://illumos.org/downloads/go$GOVER.illumos-amd64.tar.gz"

YARNVER='1.22.5'
YARNURL="https://github.com/yarnpkg/yarn/releases/download/v$YARNVER/yarn-v$YARNVER.tar.gz"

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

yarnfile="$ARTEFACT/yarn-v$YARNVER.tar.gz"
download_to yarn "$YARNURL" "$yarnfile"

gofile="$ARTEFACT/go1.14.6.illumos-amd64.tar.gz"
download_to go "$GOURL" "$gofile"

file="$ARTEFACT/cockroach-v$VER.src.tgz"
download_to cockroach "$URL" "$file"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to yarn "$yarnfile" "$YARNROOT" --strip-components=1

export GOROOT="$ROOT/cache/go$GOVER"
extract_to go "$gofile" "$GOROOT"

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

cat >"$WORKAROUND/cc" <<'EOF'
#!/usr/bin/bash
exec /usr/gcc/9/bin/gcc -m64 "$@"
EOF
chmod 0755 "$WORKAROUND/cc"

cat >"$WORKAROUND/gcc" <<'EOF'
#!/usr/bin/bash
exec /usr/gcc/9/bin/gcc -m64 "$@"
EOF
chmod 0755 "$WORKAROUND/gcc"

cat >"$WORKAROUND/g++" <<'EOF'
#!/usr/bin/bash
exec /usr/gcc/9/bin/g++ -m64 "$@"
EOF
chmod 0755 "$WORKAROUND/g++"

cat >"$WORKAROUND/c++" <<'EOF'
#!/usr/bin/bash
exec /usr/gcc/9/bin/g++ -m64 "$@"
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

function vendor_replace {
	local targ="$GOPATH/src/github.com/cockroachdb/cockroach/vendor/$1"
	info "vendor replace $1"
	rm -rf "$targ/"
	cp -r "$ROOT/patches/$1/" "$targ/"
}

stamp="$CACHE/patched.stamp"
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

cd "$GOPATH/src/github.com/cockroachdb/cockroach"

info 'running gmake build...'
BUILDCHANNEL=source-archive \
    gmake -j4 build

info 'copying final executable...'
cp "$GOPATH/src/github.com/cockroachdb/cockroach/cockroach" \
    "$WORK/cockroach"

header 'build output:'
find "$WORK" -type f -ls
