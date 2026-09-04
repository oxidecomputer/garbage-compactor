#!/bin/bash
#
# Copyright 2026 Oxide Computer Company
# Copyright 2023 The University of Queensland
#

set -o errexit
set -o pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/../lib/common.sh"

PATCH_DIR="$ROOT/patches"
CACHE="$ROOT/cache"
mkdir -p "$CACHE"
WORK="$ROOT/work"
mkdir -p "$WORK"
SRC="$ROOT/work/src"
mkdir -p "$SRC"

CLANGVER=21
GCCVER=14

# Build on OmniOS bloody for now.  ClickHouse requires Clang 21, and the newer
# illumos linker there (1.1791 rather than 1.1790) handles the executable's ELF
# extended section indices without our former local ELF-reader workaround.
# This can move back to OmniOS stable, or preferably Helios, once that build OS
# supplies a working Clang >= 21 and an illumos linker >= 1.1791.
#
# Bloody's Clang defaults to GCC 15.  Pin its GCC installation to version 14 so
# the compiler's ABI support and the executable's runtime path match GCC 14 as
# shipped by Helios 3.
GCC_INSTALL_DIR="/opt/gcc-$GCCVER/lib/gcc/x86_64-pc-solaris2.11/$GCCVER"

#
# Check build environment
#
header 'checking build environment'
PKGS=(
	developer/ccache
	developer/cmake
	"developer/gcc$GCCVER"
	developer/nasm
	developer/ninja
	"ooce/developer/clang-$CLANGVER"
	"ooce/developer/llvm-$CLANGVER"
)
for pkg in "${PKGS[@]}"; do
	info "checking for $pkg"
	pkg info -q "$pkg" || fatal "need $pkg"
done

NAM='clickhouse'
VER="26.9.1.1"
COMMIT='fc475a7efc13fb6ca77935cbcba2bc1ea2389b32'
URL='https://github.com/ClickHouse/ClickHouse.git'

#
# Check out ClickHouse sources
#
header 'checking out clickhouse sources'

if [[ ! -d "$SRC/.git" ]]; then
	git init "$SRC"
	git -C "$SRC" remote add origin "$URL"
fi

git -C "$SRC" remote set-url origin "$URL"
git -C "$SRC" fetch --depth=1 origin "$COMMIT"
git -C "$SRC" checkout --detach --force FETCH_HEAD
git -C "$SRC" submodule update --init --recursive --depth=1 --force

if [[ $(git -C "$SRC" rev-parse HEAD) != "$COMMIT" ]]; then
	fatal "checked out the wrong ClickHouse commit"
fi

#
# Remove files left by a previous build.  In particular, CMake may otherwise
# reuse feature probes and object files produced from a different source or
# toolchain revision.
#
git -C "$SRC" clean -ffdx
git -C "$SRC" submodule foreach --recursive git clean -ffdx

#
# Patch ClickHouse:
#
header 'patching clickhouse source'

for f in "$PATCH_DIR/"[0-9]*.patch; do
	[[ -f "$f" ]] || continue
	header "apply patch $f"
	gpatch --directory="$SRC" --batch --forward --fuzz=0 \
	    --no-backup-if-mismatch \
	    --strip=1 < "$f"
done

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

info "running cmake..."

COMPILER_ARG1="--no-default-config --gcc-install-dir=$GCC_INSTALL_DIR"

#
# We must set PARALLEL_COMPILE_JOBS, or else the cmake files will make
# a somewhat naive guess and set a Ninja job pool that constrains
# compilation parallelism.
#
# The link editor gets quite large when linking some of the final
# objects -- sometimes 15-30GB! -- so we constrain PARALLEL_LINK_JOBS
# to 1.
#
cmake \
	-G Ninja \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="/opt/oxide/clickhouse" \
	-DCMAKE_C_COMPILER="/opt/ooce/llvm-$CLANGVER/bin/clang" \
	-DCMAKE_CXX_COMPILER="/opt/ooce/llvm-$CLANGVER/bin/clang++" \
	-DCMAKE_C_COMPILER_ARG1="$COMPILER_ARG1" \
	-DCMAKE_CXX_COMPILER_ARG1="$COMPILER_ARG1" \
	-DCMAKE_INSTALL_RPATH="/usr/gcc/$GCCVER/lib/amd64" \
	    -DENABLE_LDAP=off \
	    -DENABLE_HDFS=off \
	    -DENABLE_AMQPCPP=off \
	    -DENABLE_AVRO=off \
	    -DENABLE_CAPNP=off \
	    -DENABLE_MSGPACK=off \
	    -DENABLE_MYSQL=off \
	    -DENABLE_PARQUET=off \
	    -DENABLE_S3=off \
	    -DENABLE_ORC=off \
	    -DUSE_SENTRY=off \
	    -DENABLE_SENTRY=off \
	    -DENABLE_CLICKHOUSE_ODBC_BRIDGE=off \
	    -DENABLE_CLICKHOUSE_BENCHMARK=off \
	    -DENABLE_TESTS=off \
	    -DENABLE_BENCHMARKS=off \
	    -DENABLE_EXAMPLES=off \
	    -DENABLE_FUZZING=off \
	    -DENABLE_FUZZER_TEST=off \
	    -DENABLE_AWS_S3=off \
	    -DENABLE_AZURE_BLOB_STORAGE=off \
	    -DENABLE_KAFKA=off \
	    -DENABLE_CASSANDRA=off \
	    -DUSE_MONGODB=off \
	    -DENABLE_ROCKSDB=off \
	    -DENABLE_GRPC=off \
	    -DENABLE_NATS=off \
	    -DENABLE_PROMETHEUS_PROTOBUFS=off \
	    -DENABLE_SSH=off \
	    -DENABLE_WASMEDGE=off \
	    -DENABLE_RUST=off \
	    -DENABLE_CHDIG=off \
	    -DENABLE_BUZZHOUSE=off \
	    -DENABLE_CLIENT_AI=off \
	    -DENABLE_GOOGLE_CLOUD_CPP=off \
	    -DENABLE_ICU=off \
	    -DENABLE_KRB5=off \
	    -DENABLE_LIBURING=off \
	    -DENABLE_CYRUS_SASL=off \
	    -DENABLE_THINLTO=off \
	    -DCMAKE_BUILD_WITH_INSTALL_RPATH=on \
	    \
	    -DPARALLEL_COMPILE_JOBS="$njobs" \
	    -DPARALLEL_LINK_JOBS="1" \
	    \
	    -S "$SRC" \
	    -B "$SRC/build"

info "running build with ninja (jobs $njobs)..."
ninja -k 0 -C "$SRC/build" -j "$njobs" clickhouse 2>&1 |
	grep -v '^ld: warning: relocation error: R_AMD64_64: .*\.debug_addr:' |
	tee "$WORK/build.log"

#
# Strip the resulting binary.  This part is crucial.  ClickHouse's binary is
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
	    "$WORK/proto/opt/clickhouse/$SVER/bin/"

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
	    "database/$NAM-$SVER@$VER-$HELIOS_RELEASE.0" \
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
	    "$WORK/clickhouse-v$VER.illumos.tar.gz" \
	    -C "$CACHE" clickhouse \
	    -C "$SRC/programs/server" config.xml \
	    -C "$SRC/programs/server" users.xml
	header 'build output:'
	ls -lh "$WORK"/*.tar.gz
	exit 0
	;;
*)
	fatal "unknown output type: $OUTPUT_TYPE"
	;;
esac
