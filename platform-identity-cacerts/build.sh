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
#
# evidence-room is a private repository, so we use the ssh URL:
#
REPO='ssh://git@github.com/oxidecomputer/evidence-room.git'

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

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

#
# This repository isn't versioned, so we track the version here.  If we want to
# publish new files, the minor component should be bumped; e.g., from "1.0" to
# "1.1".  If we stop shipping some files in the future, or rename them, a major
# roll would be more appropriate.
#
VER=1.0

info "version is $VER"
if pkg info -g "$HELIOS_REPO" "$NAM@$VER"; then
	fatal 'package already published'
fi

#
# For each separate PKI, locate the CA roots and concatenate them into a single
# PEM file:
#
header "installing $NAM"
rm -rf "$PROTO"
mkdir -p "$PROTO/usr/share/oxide/idcerts"
for pki in production staging; do
	outf="$PROTO/usr/share/oxide/idcerts/$pki.pem"

	for d in $(find "$pki" -maxdepth 1 -type d -name '*_provisioning'); do
		for f in $(find "$d/output" -type f \
		    -name "platform-identity-root-[a-z].cert.pem"); do
			info "[pki $pki] including: %f"
			cat "$f" >> "$outf"
		done
	done

	if [[ ! -f $outf ]]; then
		fatal "did not create file $outf"
	fi
done

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi

case "$OUTPUT_TYPE" in
ips)
	make_package "oxide/$NAM" \
	    'CA certs for device identity PKIs' \
	    "$PROTO"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	archive="$WORK/$NAM-$VER.p5p"
	pkgrecv -a -d "$archive" -s "$WORK/repo" "$NAM@$VER-2.0"
	ls -lh "$archive"
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
