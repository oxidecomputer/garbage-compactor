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

VER='2.24.1'
URL="https://github.com/prometheus/prometheus/archive/v$VER.tar.gz"

PROMUVER='0.7.0'
PROMUURL="https://github.com/prometheus/promu/archive/v$PROMUVER.tar.gz"

GOVER='1.15.3'
GOURL="https://illumos.org/downloads/go$GOVER.illumos-amd64.tar.gz"

YARNVER='1.22.10'
YARNURL="https://github.com/yarnpkg/yarn/releases/download/v$YARNVER/yarn-v$YARNVER.tar.gz"

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

yarnfile="$ARTEFACT/yarn-v$YARNVER.tar.gz"
download_to yarn "$YARNURL" "$yarnfile"

gofile="$ARTEFACT/go$GOVER.illumos-amd64.tar.gz"
download_to go "$GOURL" "$gofile"

promufile="$ARTEFACT/promu-v$VER.tar.gz"
download_to promu "$PROMUURL" "$promufile"

file="$ARTEFACT/prometheus-v$VER.tar.gz"
download_to prometheus "$URL" "$file"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to yarn "$yarnfile" "$YARNROOT" --strip-components=1

export GOROOT="$ROOT/cache/go$GOVER"
extract_to go "$gofile" "$GOROOT"

mkdir -p "$GOPATH/src/github.com/prometheus/promu"
extract_to promu "$promufile" "$GOPATH/src/github.com/prometheus/promu" \
    --strip-components=1

mkdir -p "$GOPATH/src/github.com/prometheus/prometheus"
extract_to prometheus "$file" "$GOPATH/src/github.com/prometheus/prometheus" \
    --strip-components=1

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

cat >"$WORKAROUND/tar" <<'EOF'
#!/usr/bin/bash
exec gtar "$@"
EOF
chmod 0755 "$WORKAROUND/tar"

cat >"$WORKAROUND/cc" <<'EOF'
#!/usr/bin/bash
exec gcc "$@"
EOF
chmod 0755 "$WORKAROUND/cc"

#
# promu will try to detect information about the git repository, but finds
# garbage-compactor.git, because the source archive we use to build Prometheus
# is not, itself, a git repository.
#
cat >"$WORKAROUND/git" <<'EOF'
#!/usr/bin/bash
exit 1
EOF
chmod 0755 "$WORKAROUND/git"

#
# Build promu, the Prometheus build tool:
#
header 'building promu'

export PATH="$GOPATH/bin:$GOROOT/bin:$YARNROOT/bin:$WORKAROUND:$PATH"

cd "$GOPATH/src/github.com/prometheus/promu"

go install .

#
# Build Prometheus:
#
header 'building prometheus'

export PATH="$GOPATH/bin:$GOROOT/bin:$YARNROOT/bin:$WORKAROUND:$PATH"

cd "$GOPATH/src/github.com/prometheus/prometheus"

info 'running gmake build...'
gmake build

info 'running gmake tarball...'
gmake tarball

outf="$WORK/prometheus-$VER.illumos-amd64.tar.gz"
builddir="$GOPATH/src/github.com/prometheus/prometheus"
rm -f "$outf"
cp "$builddir/prometheus-$VER.illumos-amd64.tar.gz" "$outf"

header 'build output:'
find "$WORK" -type f -ls
