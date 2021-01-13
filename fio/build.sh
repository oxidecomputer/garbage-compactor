#!/bin/bash

set -o errexit
set -o pipefail

function info {
	printf 'INFO: %s\n' "$*"
}

function header {
	printf -- '\n'
	printf -- '----------------------------------------------------------\n'
	printf -- 'INFO: %s\n' "$*"
	printf -- '----------------------------------------------------------\n'
	printf -- '\n'
}

function fatal {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

function extract_to {
	local name="$1"
	local tar="$2"
	local outdir="$3"
	local extra="$4"

	stamp="$outdir/.extracted"
	if [[ ! -f "$stamp" ]]; then
		rm -rf "$outdir"
		info "extracting $name..."
		mkdir -p "$outdir"
		gtar -C "$outdir" $extra -xzf "$tar"
		info "extracted $name ok"
		touch "$stamp"
	else
		info "$name extracted already"
	fi

	return 0
}

function download_to {
	local name="$1"
	local url="$2"
	local path="$3"

	if [[ ! -f "$path" ]]; then
		info "downloading $name..."
		if ! curl -fL -o "$path" "$url"; then
			fatal "$name download failed"
			exit 1
		fi
		info "ok"
	else
		info "downloaded $name already"
	fi

	return 0
}

ROOT=$(cd "$(dirname "$0")" && pwd)

ARTEFACT="$ROOT/artefact"
mkdir -p "$ARTEFACT"
WORK="$ROOT/work"
mkdir -p "$WORK"
PROTO="$ROOT/proto"
mkdir -p "$PROTO"

#
# Directory for workaround scripts that we can put in PATH:
#
WORKAROUND="$ROOT/cache/workaround"
rm -rf "$WORKAROUND"
mkdir -p "$WORKAROUND"

VER='3.25'
URL="https://github.com/axboe/fio/archive/fio-$VER.tar.gz"

if [[ -x /usr/gcc/9/bin/gcc ]]; then
	GCC_DIR=/usr/gcc/9/bin
elif [[ -x /opt/gcc-9/bin/gcc ]]; then
	GCC_DIR=/opt/gcc-9/bin
else
	fatal "Could not find GCC in any expected location"
fi
info "using $GCC_DIR/gcc: $($GCC_DIR/gcc --version | head -1)"
info "using $GCC_DIR/g++: $($GCC_DIR/g++ --version | head -1)"

#
# Download artefacts to use during build:
#
header 'downloading artefacts'

file="$ARTEFACT/fio-$VER.src.tgz"
download_to fio "$URL" "$file"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to fio "$file" "$WORK" --strip-components=1

#
# Create workaround wrappers:
#
header 'preparing workaround wrappers'

cat >"$WORKAROUND/python2" <<'EOF'
#!/usr/bin/bash
exec /usr/bin/python2.7 "$@"
EOF
chmod 0755 "$WORKAROUND/python2"

cat >"$WORKAROUND/make" <<'EOF'
#!/usr/bin/bash
exec gmake "$@"
EOF
chmod 0755 "$WORKAROUND/make"

cat >"$WORKAROUND/cc" <<EOF
#!/usr/bin/bash
exec "$GCC_DIR/gcc" -m64 "\$@"
EOF
chmod 0755 "$WORKAROUND/cc"

cat >"$WORKAROUND/gcc" <<EOF
#!/usr/bin/bash
exec "$GCC_DIR/gcc" -m64 "\$@"
EOF
chmod 0755 "$WORKAROUND/gcc"

cat >"$WORKAROUND/g++" <<EOF
#!/usr/bin/bash
exec "$GCC_DIR/g++" -m64 "\$@"
EOF
chmod 0755 "$WORKAROUND/g++"

cat >"$WORKAROUND/c++" <<EOF
#!/usr/bin/bash
exec "$GCC_DIR/g++" -m64 "\$@"
EOF
chmod 0755 "$WORKAROUND/c++"

cat >"$WORKAROUND/grep" <<'EOF'
#!/usr/bin/bash
exec ggrep "$@"
EOF
chmod 0755 "$WORKAROUND/grep"

cat >"$WORKAROUND/sed" <<'EOF'
#!/usr/bin/bash
exec gsed "$@"
EOF
chmod 0755 "$WORKAROUND/sed"

cat >"$WORKAROUND/install" <<'EOF'
#!/usr/bin/bash
exec ginstall "$@"
EOF
chmod 0755 "$WORKAROUND/install"

cat >"$WORKAROUND/make" <<'EOF'
#!/usr/bin/bash
exec gmake "$@"
EOF
chmod 0755 "$WORKAROUND/make"

#
# Build fio:
#
header 'patching fio source'

stamp="$ROOT/cache/patched.stamp"
if [[ ! -f "$stamp" ]]; then
	for f in $ROOT/patches/*.patch; do
		if [[ ! -f $f ]]; then
			continue;
		fi

		info "apply patch $f"
		(cd "$WORK" && patch --verbose -p1 < "$f")
	done

	touch "$stamp"
else
	info 'already patched'
fi

header 'building fio'

export PATH="$WORKAROUND:$PATH"

info 'running configure...'
(cd "$WORK" && ./configure --prefix=/opt/oxide/fio --disable-http)

args=()
if [[ -n $JOBS ]]; then
	if [[ $JOBS != 1 ]]; then
		args+=( "-j$JOBS" )
	fi
else
	args+=( "-j2" )
fi

info "running gmake..."
gmake \
    -C "$WORK" \
    "${args[@]}"

info "running gmake install..."
gmake \
    -C "$WORK" \
    install \
    DESTDIR="$PROTO"

#
# Some distributions do different things with libz.so.1, so, carry the one we
# were built with along for the ride.  (Sigh.)
#
mkdir -p "$PROTO/opt/oxide/fio/lib"
cp /usr/lib/64/libz.so.1 "$PROTO/opt/oxide/fio/lib"

bins=$(/bin/file "$PROTO/opt/oxide/fio/bin/"* | grep ELF | sed 's/:.*//' |
    xargs -n 1 basename)
for bin in $bins; do
	info "patching rpath in $bin..."
	/usr/bin/elfedit -e 'dyn:rpath $ORIGIN/../lib' \
	    "$PROTO/opt/oxide/fio/bin/$bin"
done

ldd "$PROTO/opt/oxide/fio/bin/fio"

/usr/bin/tar cvfz $WORK/fio-$VER.illumos.tar.gz -C "$PROTO" opt/oxide/fio

header 'build output:'
ls -lh "$WORK/fio-$VER.illumos.tar.gz"
