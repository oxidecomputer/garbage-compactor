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

NAM='clickhouse'
VER="23.5.3.24"
URL="https://github.com/ClickHouse/ClickHouse/archive/refs/tags/v$VER-stable.tar.gz"
SHA256='8a87a72facaa4e01bba01f80c7c879151f38240cf8e7c83372de69bb21d769a4'

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

export PATH="/usr/gnu/bin:/opt/ooce/bin:/usr/bin:/usr/sbin:/sbin"

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
	CFLAGS="$CFLAGS" CXXFLAGS="$CXXINC $CFLAGS" cmake \
	    -DCMAKE_C_COMPILER="/opt/gcc-10/bin/gcc" \
	    -DCMAKE_CXX_COMPILER="/opt/gcc-10/bin/g++" \
	    -DCMAKE_C_FLAGS="$CFLAGS" \
	    -DCMAKE_CXX_FLAGS="$CXXINC $CFLAGS" \
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
		if ! ninja -k 0 -C "$SRC/build" -j $jobs; then
			exit 1
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
	#
	# Make a package per release version series; e.g., 21.6.7.57-stable
	# will be package "clickhouse-21.6".
	#
	SVER=$(awk -F. '{ print $1"."$2 }' <<< "$VER")

	rm -rf "$WORK/proto"
	mkdir -p "$WORK/proto/opt/clickhouse/$SVER/bin"
	cp "$CACHE/clickhouse" \
	    "$WORK/proto/opt/clickhouse/$SVER/bin/clickhouse"

	mkdir -p "$WORK/proto/opt/clickhouse/$SVER/config"
	for f in config.xml users.xml; do
		cp "$SRC/programs/server/$f" \
		    "$WORK/proto/opt/clickhouse/$SVER/config/$f"
	done

	make_package "database/$NAM-$SVER" \
	    'columnar OLAP database for real-time analytics in SQL' \
	    "$WORK/proto" \
	    "$ROOT/current.p5m"

	rm -rf "$WORK/proto"
	mkdir -p "$WORK/proto/var/svc/manifest/database"
	cp smf.xml "$WORK/proto/var/svc/manifest/database/clickhouse.xml"

	#
	# The common package will be shared by all release series, so it does
	# not need a version suffix in the name.  It also does not require a
	# branch version.
	#
	CVER='1.0.1'
	make_package_simple "database/$NAM-common" \
	    'ClickHouse common package' \
	    "$WORK/proto" \
	    "$ROOT/common.p5m" \
	    "$CVER"

	header 'build output:'
	pkgrepo -s "$WORK/repo" list
	pkgrecv -a -d "$WORK/$NAM-$VER.p5p" -s "$WORK/repo" \
	    "database/$NAM-$SVER@$VER-1.0" \
	    "database/$NAM-common@$CVER"
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
