#!/bin/bash
#
# Copyright 2025 Oxide Computer Company
#

#
# This job script is run inside a buildomat ephemeral VM.
#
if [[ -z $BUILDOMAT_JOB_ID ]]; then
	printf 'ERROR: this is supposed to be run under buildomat.\n' >&2
	exit 1
fi

if [[ -z $INPUT_PACKAGE ]]; then
	exit 1
fi

set -o errexit
set -o pipefail
set -o xtrace

function pkg_maybe {
	if pkg "$@"; then
		echo "pkg $1 ok"
	else
		rc=$?
		if (( $rc != 4 )); then
			printf 'ERROR: pkg %s failed with status %d\n' "$1" \
			    "$rc" >&2
			exit 1
		fi
		echo "pkg $1 ok (no action needed)"
	fi
}

#
# Try to update pkg(1), in case there are new features that we will need to
# build an image with current OS bits:
#
pkg_maybe update -v pkg
pkg_maybe install -v /compress/zstd

#
# Install a stable Rust toolchain so that we can build the image builder:
#
RUSTUP_INIT_SKIP_PATH_CHECK=yes \
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s - \
    --default-toolchain stable \
    --profile minimal \
    --no-modify-path \
    -y -q

. "$HOME/.cargo/env"

#
# Create datasets to work in:
#
zfs create rpool/images
zfs create -o mountpoint=/work rpool/work
zfs create -o mountpoint=/proto rpool/proto
zfs create -o mountpoint=/out rpool/out

cd /work

#
# Unpack the templates and scripts we included when kicking off the job:
#
gunzip < '/input/image.cpio.gz' | cpio -idv

cd "/work/$INPUT_PACKAGE"

./build.sh

for f in "/work/$INPUT_PACKAGE/work/"*.p5p; do
	n=$(basename "$f")
	zstd -o "/out/$n.zst" -k -7 "$f"
done

find '/out' -type f -ls
