#!/bin/bash
#
# Copyright 2025 Oxide Computer Company
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

NAM='lmar'
REPO="https://github.com/oxidecomputer/$NAM.git"
prefix="/opt/oxide/$NAM"

if [[ -x /usr/gcc/10/bin/gcc ]]; then
	GCC_DIR=/usr/gcc/10/bin
elif [[ -x /opt/gcc-10/bin/gcc ]]; then
	GCC_DIR=/opt/gcc-10/bin
else
	fatal "Could not find GCC in any expected location"
fi
info "using $GCC_DIR/gcc: $($GCC_DIR/gcc --version | head -1)"
info "using $GCC_DIR/g++: $($GCC_DIR/g++ --version | head -1)"

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

export PATH="$TOOLS/bin:$PATH"

header "building $NAM"

cd "$SRC64"

#
# Determine the version embedded in this binary.  Not every commit will bump
# the version number, so we include the repository commit count as an
# additional component.
#
commit_count=$(git rev-list --count HEAD)
VER=$(cargo metadata --format-version 1 |
    jq -r '.packages | map(select(.name == "lmar")) | .[].version'
    ).$commit_count
CREV=1
BRANCH=2.$CREV

info "version is $VER"
if pkg info -g "$HELIOS_REPO" "$NAM@$VER-$BRANCH"; then
	fatal 'package already published'
fi

info "build $NAM..."

#
# The "lmar" program, which runs on the device under test, is written in Rust:
#
cargo build --release

rm -rf "$PROTO"
mkdir -p "$PROTO$prefix/sbin"
cp 'target/release/lmar' "$PROTO$prefix/sbin/lmar"

#
# The analysis tools are, regrettably, written in Python.
#

info "install Python dependencies..."
venv="$PROTO$prefix/lib/venv"
mkdir -p "$venv"
python3.11 -m venv "$venv"

#
# There does not appear to be any metadata about specific versions of the
# required dependencies, just an unversioned list in the README.  We'll just
# install the latest version of those.
#
info "fixing Python dependencies..."
for dep in pip tabulate matplotlib numpy; do
	info "installing Python dependency: $dep..."
	PKG_CONFIG_PATH=/opt/ooce/lib/amd64/pkgconfig:/usr/lib/amd64/pkgconfig \
	    MAKE=gmake \
	    "$venv/bin/pip" install --upgrade "$dep"
done

#
# For whatever reason, some of the native modules do not end up with the
# correct rpath for the libraries on which they depend.  Rather than look
# too closely at the mess, we'll just fix it in post:
#
for dep in webp imaging imagingft; do
	elfedit -e \
	    'dyn:rpath /opt/ooce/lib/amd64:/usr/gcc/12/lib/amd64' \
	    "$venv/lib/python3.11/site-packages/PIL/_$dep.cpython-311.so"
done

#
# Trim the actual virtual environment fluff out:
#
rm -rf "$venv/include"
rm -rf "$venv/bin"
rm -rf "$venv/pyvenv.cfg"

#
# The packaging system looks at the interpreter line of Python scripts in order
# to generate a dependency on the correct runtime package.  Doctor any Python
# scripts that we find with an interpeter line so that they reference a
# specific version.
#
find "$venv" -name '*.py' | while read f; do
	sed -e '/^#!.*python/,1s%^#!.*%#!/usr/bin/python3.11%' -i "$f"
done

#
# Remove things that seem broken and are not required:
#
rm -f \
    "$venv/lib/python3.11/site-packages/numpy/testing/print_coercion_tables.py"

info "installing Python commands and wrappers..."
for c in analyze collect_summaries margin_summary; do
	#
	# Whack the Python script we need into place:
	#
	cc="lmar-${c/_/-}"
	cp "$c.py" "$PROTO$prefix/lib/$c.py"
	chmod 0644 "$PROTO$prefix/lib/$c.py"

	#
	# Create a wrapper that will use our private copies of dependencies:
	#
	mkdir -p "$PROTO$prefix/bin"
	cat >"$PROTO$prefix/bin/$cc" <<-EOF
	#!/bin/bash

	set -o errexit
	set -o pipefail

	dir="\$(cd "\$(dirname "\$0")/.." && pwd)"

	unset PYTHONHOME
	export PYTHONPATH="\$dir/lib/venv/lib/python3.11/site-packages"

	exec /usr/bin/python3.11 "\$dir/lib/$c.py" "\$@"
	EOF
	chmod 0755 "$PROTO$prefix/bin/$cc"
done

cd "$WORK"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=ips
fi


case "$OUTPUT_TYPE" in
ips)
	make_package "diagnostic/$NAM" \
	    'PCIe Lane Margining at the Receiver' \
	    "$WORK/proto" \
	    "$ROOT/overrides.p5m"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	pkgrecv -a -d "$WORK/$NAM-$VER-$BRANCH.p5p" -s "$WORK/repo" \
	    "$NAM@$VER-$BRANCH"
	ls -lh "$WORK/$NAM-$VER-$BRANCH.p5p"
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
