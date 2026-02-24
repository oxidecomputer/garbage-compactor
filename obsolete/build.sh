#!/bin/bash
#
# Copyright 2026 Oxide Computer Company
#

set -o errexit
set -o pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/../lib/common.sh"

WORK="$ROOT/work"
mkdir -p "$WORK"

grep -v '^#' list | while read src dst; do
	echo "[$src] -> [$dst]"
	cat <<-EOM > manifest.p5m
set name=pkg.fmri value=pkg://helios/$src-$HELIOS_RELEASE.0
set name=pkg.renamed value=true
depend type=require fmri=$dst
	EOM

	publish_manifest manifest.p5m
	rm -f manifest.p5m
done

pkgrecv -a -d "$WORK/obsolete.p5p" -s "$WORK/repo" -m latest \*
ls -lh "$WORK/obsolete.p5p"

