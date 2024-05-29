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
TOOLS="$WORK/tools"
mkdir -p "$TOOLS"

NAM='platform-identity-cacerts'
# evidence-room is private so we use the ssh URL
REPO="ssh://git@github.com/oxidecomputer/evidence-room.git"

#
# Download artefacts to use during build:
#
header 'downloading artefacts for $NAM'

if [[ -d "$SRC64/.git" ]]; then
	(cd "$SRC64" &&
	    git clean -fxd &&
	    git fetch --all &&
	    git reset --hard origin/main)
else
	rm -rf "$SRC64"
	git clone "$REPO" "$SRC64"
fi


cd "$SRC64"

# this repo isn't versioned so we track the version here
VER=1.0

info "version is $VER"
if pkg info -g https://pkg.oxide.computer/helios-dev "$NAM@$VER"; then
	fatal 'package already published'
fi

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi
	
case "$OUTPUT_TYPE" in
ips)
	rm -rf "$PROTO"
	for flavor in production staging; do
		header "installing $NAM-$flavor"
		mkdir -p "$PROTO/$flavor/usr/share/oxide/idcerts"
		certs=$(ls -1 "$flavor"/*_provisioning/output/platform-identity-root-[a-z].cert.pem)
		for cert in "$certs"; do
			cat "$cert" >> "$PROTO/$flavor/usr/share/oxide/idcerts/$flavor.pem"
		done

		cd "$WORK"

		make_package "developer/debug/$NAM-$flavor" \
		    'CA certs for device identity PKIs' \
		    "$PROTO/$flavor"

		header 'build output:'
		pkgrepo -s "$WORK/repo" list
		pkg_file="$WORK/$NAM-$flavor-$VER.p5p"
		pkgrecv -a -d "$pkg_file" -s "$WORK/repo" "$NAM-$flavor@$VER-2.0"
		ls -lh "$pkg_file"

		cd -
	done

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
