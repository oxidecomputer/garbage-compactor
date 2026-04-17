#!/bin/bash
#
# Copyright 2026 Oxide Computer Company
#
# `mfg` is a package for the manufacturing software deployed to station
# computers.  It uses require dependencies to ensure the required tools are
# installed, and incorporate
# dependencies to lock against particular versions of those tools.  To date,
# manufacturing station tools have been managed via a combination of
# confomat-oxide and ad-hoc pkg installs, leading to version drift between
# stations.  This package ensures the correct versions are installed and
# updated in lock step.
#

set -o errexit
set -o pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/../lib/common.sh"

NAM='mfg'
CREV=0
VER="0.1.$CREV"

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
	pkgrepo create "$WORK/repo"
	pkgrepo add-publisher -s "$WORK/repo" helios-dev
	make_package_simple "oxide/$NAM" \
	    'Manufacturing software package' \
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
