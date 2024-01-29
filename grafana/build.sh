#!/bin/bash
#
# Copyright 2024 Oxide Computer Company
#

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

VER='7.1.5'
URL="https://github.com/grafana/grafana/archive/v${VER}.tar.gz"

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

file="$ARTEFACT/grafana-v$VER.tar.gz"
download_to grafana "$URL" "$file"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to yarn "$yarnfile" "$YARNROOT" --strip-components=1

export GOROOT="$ROOT/cache/go$GOVER"
extract_to go "$gofile" "$GOROOT"

extract_to grafana "$file" "$WORK" --strip-components=1

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
exec gcc "$@"
EOF
chmod 0755 "$WORKAROUND/cc"

NODEPATH=/opt/ooce/node-12

#
# Build Grafana:
#
header 'building grafana'

export PATH="$GOPATH/bin:$GOROOT/bin:$YARNROOT/bin:$WORKAROUND:$NODEPATH/bin:$PATH"

cd "$WORK"

info 'expurgating...'
#
# The "cypress" browser testing system does not build on illumos systems,
# but is also not actually a required part of the package.
#
rm -rf "$WORK/packages/grafana-e2e"

header 'yarn install...'
yarn install --frozen-lockfile

header 'build go binaries...'
go run build.go -cc=gcc -skipRpm -skipDeb build

header 'build frontend files (this may take a while)...'
go run build.go -cc=gcc -skipRpm -skipDeb build-frontend

header 'build package archive...'
go run build.go -cc=gcc -skipRpm -skipDeb pkg-archive
go run build.go -cc=gcc -skipRpm -skipDeb sha-dist

header 'build output:'
ls -lh dist
