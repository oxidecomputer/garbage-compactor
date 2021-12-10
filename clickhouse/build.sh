#!/bin/bash

set -o errexit
set -o pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/../lib/common.sh"

PATCH_DIR="$ROOT/patches"
CACHE="$ROOT/cache"
mkdir -p "$CACHE"
ARTEFACT="$ROOT/artefact"
mkdir -p "$ARTEFACT"
WORK="$ROOT/work"
mkdir -p "$WORK"
STAMPS="$WORK/.stamps"
mkdir -p "$STAMPS"
SRC="$ROOT/work/src"
mkdir -p "$SRC"

#
# Check build environment
#
for pkg in cmake ninja; do
	if ! pkg info -q $pkg; then
		fatal "need $pkg"
	fi
done

VER="21.6.7.57"
URL="https://github.com/ClickHouse/ClickHouse/releases/download/v$VER-stable"
URL+="/ClickHouse_sources_with_submodules.tar.gz"
SHA256='b060fb3bb10051537093823fe67e17ca198310cc8d76cc5aeeab78827f92ba08'

#
# Download ClickHouse sources
#
header 'downloading artefacts'

file="$ARTEFACT/clickhouse-$VER-stable.tar.gz"
download_to clickhouse "$URL" "$file" "$SHA256"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to clickhouse "$file" "$SRC" --strip-components=1

#
# Patch ClickHouse:
#
header 'patching clickhouse source'

stamp="$STAMPS/patched.stamp"
if [[ ! -f "$stamp" ]]; then
	for f in $ROOT/patches/*.patch; do
		if [[ ! -f $f ]]; then
			continue;
		fi

		info "apply patch $f"
		(cd "$SRC" && patch --verbose -p1 < "$f")
	done

	touch "$stamp"
else
	info 'already patched'
fi

#
# Build ClickHouse
#
header 'building clickhouse'

#
# Empirically it seems like we might need as much as 3-4GB of memory
# per C++ compilation process, which is impressive.  Start with the
# number of CPUs we have available, and reduce further if we do not
# have enough memory:
#
njobs=$(psrinfo -t)
njobs_mem=$(( $(prtconf -m) / 1024 / 3 ))
if (( njobs_mem < njobs )); then
	njobs=$njobs_mem
fi
info "using $njobs jobs..."

stamp="$STAMPS/cmake.stamp"
if [[ ! -f "$stamp" ]]; then
	info "running cmake..."

	CFLAGS='-D_REENTRANT -D_POSIX_PTHREAD_SEMANTICS -D__EXTENSIONS__ -m64'
	CFLAGS+=" -I$SRC/contrib/hyperscan-cmake/x86_64/ "

	#
	# We must set PARALLEL_COMPILE_JOBS, or else the cmake files will make
	# a somewhat naive guess and set a Ninja job pool that constrains
	# compilation parallelism.
	#
	# The link editor gets quite large when linking some of the final
	# objects -- sometimes 15-30GB! -- so we constrain PARALLEL_LINK_JOBS
	# to 1.
	#
	CFLAGS="$CFLAGS" CXXFLAGS="$CFLAGS" cmake \
	    -DCMAKE_C_FLAGS="$CFLAGS" \
	    -DCMAKE_CXX_FLAGS="$CFLAGS" \
	    -DABSL_CXX_STANDARD="17" \
	    -DENABLE_LDAP=off \
	    -DUSE_INTERNAL_LDAP_LIBRARY=off \
	    -DENABLE_HDFS=off \
	    -DUSE_INTERNAL_HDFS3_LIBRARY=off \
	    -DENABLE_AMQPCPP=off \
	    -DENABLE_AVRO=off \
	    -DUSE_INTERNAL_AVRO_LIBRARY=off \
	    -DENABLE_CAPNP=off \
	    -DUSE_INTERNAL_CAPNP_LIBRARY=off \
	    -DENABLE_MSGPACK=off \
	    -DUSE_INTERNAL_MSGPACK_LIBRARY=off \
	    -DENABLE_MYSQL=off \
	    -DENABLE_S3=off \
	    -DUSE_INTERNAL_AWS_S3_LIBRARY=off \
	    -DENABLE_PARQUET=off \
	    -DUSE_INTERNAL_PARQUET_LIBRARY=off \
	    -DENABLE_ORC=off \
	    -DUSE_INTERNAL_ORC_LIBRARY=off \
	    -DUSE_SENTRY=off \
	    -DENABLE_CLICKHOUSE_ODBC_BRIDGE=off \
	    -DENABLE_CLICKHOUSE_BENCHMARK=off \
	    -DENABLE_TESTS=off \
	    \
	    -DPARALLEL_COMPILE_JOBS="$njobs" \
	    -DPARALLEL_LINK_JOBS="1" \
	    \
	    -S "$SRC" \
	    -B "$SRC/build"

	touch "$stamp"
else
	info "cmake already run"
fi

stamp="$STAMPS/ninja.stamp"
if [[ ! -f "$stamp" ]]; then
	info "running build with ninja..."

	#
	# The build is massive.  Try to parallelize until we error out, usually
	# due to space constraints while linking. At that point, continue
	# serially.
	#
	jobs=$njobs
	while :; do
		info "trying ninja build with $jobs jobs"
		if ! ninja -C "$SRC/build" -j $jobs; then
			if (( jobs-- <= 1 )); then
				fatal 'ninja failed even with only one job'
			fi
			continue
		fi
		info 'ninja build completed ok'
		break
	done

	touch "$stamp"
else
	info "ninja already run"
fi

#
# Strip the resulting binary. This part is crucial. ClickHouse's binary is
# 3+GiB unstripped.
#
rm -f "$CACHE/clickhouse"
cp "$SRC/build/programs/clickhouse" "$CACHE/clickhouse"
/usr/bin/strip -x "$CACHE/clickhouse"

if [[ -z "$OUTPUT_TYPE" ]]; then
	OUTPUT_TYPE=tar
fi

case "$OUTPUT_TYPE" in
ips)
	rm -rf "$WORK/proto"
	mkdir -p "$WORK/proto/opt/oxide/clickhouse/$VER/bin"
	cp "$CACHE/clickhouse" \
	    "$WORK/proto/opt/oxide/clickhouse/$VER/bin/clickhouse"
	#
	# Make a package per release version series; e.g., 21.6.7.57-stable
	# will be package "clickhouse-216".
	#
	suffix=$(awk -F. '{ print $1$2 }' <<< "$VER")
	make_package "oxide/clickhouse-$suffix" \
	    'columnar OLAP database for real-time analytics in SQL' \
	    "$WORK/proto"
	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	pkgrecv -a -d "$WORK/$NAM-$VER.p5p" -s "$WORK/repo" "$NAM@$VER-1.0"
	ls -lh "$WORK/$NAM-$VER.p5p"
	exit 0
	;;
none)
	#
	# Just leave the build tree as-is without doing any more work.
	#
	exit 0
	;;
tar)
	/usr/bin/tar cvfz \
	    $WORK/clickhouse-v$VER.illumos.tar.gz \
	    -C "$CACHE" clickhouse \
	    -C "$SRC/programs/server" config.xml \
	    -C "$SRC/programs/server" users.xml \
	    -C "$ROOT" manifest.xml
	header 'build output:'
	ls -lh $WORK/*.tar.gz
	exit 0
	;;
*)
	fatal "unknown output type: $OUTPUT_TYPE"
	;;
esac
