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
export GOMODCACHE="$ROOT/cache/gomodcache"

ARTEFACT="$ROOT/artefact"
mkdir -p "$ARTEFACT"
WORK="$ROOT/work"
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

NAM="yubihsm-connector"
VER='3.0.4'
URL="https://developers.yubico.com/$NAM/Releases/$NAM-$VER.tar.gz"

GOVER='1.19.9'
SYSGOVER=$( (pkg info go-119 || true) | awk '/Version:/ { print $NF }')
if [[ "$SYSGOVER" != "$GOVER" ]]; then
	fatal 'install or update go-119 package'
fi
export GOROOT='/opt/ooce/go-1.19'
GO="$GOROOT/bin/go"
info "using $GOROOT/bin/go: $("$GO" version)"

build_deps \
    '/library/libusb'

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

file="$ARTEFACT/$NAM-$VER.tar.gz"
download_to yubihsm-connector "$URL" "$file"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to "$NAM" "$file" "$SRC64" --strip-components=1

#
# Some software will try to detect information about the git repository, but
# finds garbage-compactor.git, because the source archive we use to build is
# not, itself, a git repository.
#
cat >"$WORKAROUND/git" <<'EOF'
#!/usr/bin/bash
exit 1
EOF
chmod 0755 "$WORKAROUND/git"

header "building $NAM"

export PATH="$GOPATH/bin:$GOROOT/bin:$WORKAROUND:$PATH"

cd "$SRC64"

#
# We would use the Makefile, except that it does not allow us to pass
# the extra flag we need to go build; i.e., "-buildvcs=false".
#
info 'go generate...'
"$GO" generate

info 'go build...'
"$GO" build -buildvcs=false -o 'bin/yubihsm-connector'

info 'arranging proto...'
mkdir -p "$PROTO/usr/sbin"
cp "$SRC64/bin/yubihsm-connector" "$PROTO/usr/sbin/yubihsm-connector"
mkdir -p "$PROTO/lib/svc/manifest/application/security"
cp "$ROOT/smf/yubihsm-connector.xml" \
    "$PROTO/lib/svc/manifest/application/security/yubihsm-connector.xml"
mkdir -p "$PROTO/lib/svc/method"
cp "$ROOT/smf/yubihsm-connector.sh" \
    "$PROTO/lib/svc/method/yubihsm-connector"
chmod 0755 "$PROTO/lib/svc/method/yubihsm-connector"

header "packaging $NAM"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	CREV=0
	BRANCH="2.$CREV" make_package "security/$NAM" \
	    'YubiHSM Connector daemon' \
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
