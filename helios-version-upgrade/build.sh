#!/bin/bash
#
# Copyright 2026 Oxide Computer Company
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
TOOLS="$WORK/tools"
mkdir -p "$TOOLS"

NAM='helios-version-upgrade'
VER=3.0.1

info "version is $VER"

header "installing $NAM"
rm -rf "$PROTO"
mkdir -p "$PROTO/usr/bin"
cp $NAM $PROTO/usr/bin/$NAM
chmod 755 $PROTO/usr/bin/$NAM

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	echo "depend type=require fmri=pkg:/ooce/util/jq" > "$WORK/manifest"
	make_package "oxide/helios-version-upgrade" \
	    'System major version upgrade utility' \
	    "$WORK/proto" "$WORK/manifest"
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
