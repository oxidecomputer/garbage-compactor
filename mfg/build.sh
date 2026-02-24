#!/bin/bash
#
# Copyright 2026 Oxide Computer Company
#
# `mfg` is a package for the manufacturing software deployed to station
# computers.  It uses "require" dependencies to ensure the required tools are
# installed, and "incorporate" dependencies to lock against particular versions
# of those tools.
#
# To date, manufacturing station tools have been managed via an
# initial `confomat-oxide` setup followed by ad-hoc pkg installs, leading to
# version drift between stations.  This package ensures the correct, pinned
# versions are installed and updated in lock step.
#

set -o errexit
set -o pipefail

NAM='mfg'
CREV=1
VER="0.1.$CREV"

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/../lib/common.sh"

WORK="$ROOT/work"
mkdir -p "$WORK"

cat <<-EOM > manifest.p5m
set name=pkg.fmri value=pkg://helios/oxide/$NAM@$VER-$HELIOS_RELEASE.0
set name=pkg.summary value="Manufacturing software package"
EOM

grep -v '^#' pkglist | while read pkg ver; do
	[ -n "$ver" ] || ver=`pkg list -aHo version $pkg@latest`
	[ -n "$ver" ] || { echo "No version for $pkg" >&2; exit 1; }
	[[ $ver = *-$HELIOS_RELEASE.* ]] || ver+="-$HELIOS_RELEASE.0"

	echo "[$pkg] -> [$ver]" >&2
	bpkg=${pkg#pkg:/}
	facet="version-lock.$bpkg=true"

	echo "depend type=require fmri=$pkg"
	echo "depend facet=$facet type=incorporate fmri=$pkg@$ver"
done >> manifest.p5m

publish_manifest manifest.p5m
cat manifest.p5m
rm -f manifest.p5m

pkgrecv -a -d "$WORK/$NAM-$VER.p5p" -s "$WORK/repo" -m latest \*
ls -lh "$WORK/$NAM-$VER.p5p"

