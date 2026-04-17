#!/bin/bash
#
# Copyright 2026 Oxide Computer Company
#

set -o errexit
set -o pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/../lib/common.sh"

NAM='mfg'
CREV=0
VER="1.0.$CREV"

WORK="$ROOT/work"
mkdir -p "$WORK"
PROTO="$WORK/proto"
rm -rf "$PROTO"
mkdir -p "$PROTO"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package_simple "oxide/$NAM" \
	    'Manufacturing software meta-package' \
	    "$WORK/proto" \
	    "$ROOT/mfg.p5m" \
	    "$VER"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	pkgrecv -a -d "$WORK/$NAM-$VER.p5p" -s "$WORK/repo" "oxide/$NAM@$VER"
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
