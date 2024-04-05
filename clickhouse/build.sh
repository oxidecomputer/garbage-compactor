#!/bin/bash
#
# Copyright 2024 Oxide Computer Company
# Copyright 2023 The University of Queensland
#

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

CLANGVER=17
GCCVER=13

#
# Check build environment
#
header 'checking build environment'
PKGS=(
	developer/ccache
	developer/clang-$CLANGVER
	developer/cmake
	developer/gcc$GCCVER
	developer/nasm
	developer/ninja
)
for pkg in ${PKGS[@]}; do
	info "checking for $pkg"
	pkg info -q "$pkg" || fatal "need $pkg"
done

NAM='clickhouse'
VER="23.8.7.24"
FILE="clickhouse-src-bundle-v$VER-lts.tar.gz"
S3="https://oxide-clickhouse-build.s3.us-west-2.amazonaws.com"
URL="$S3/$FILE"
SHA256='e90f3c9381d782c153f21726849710362d6fb0c5e2bbd4f45d32b140e9463cb4'

#
# Download ClickHouse sources
#
header 'downloading artefacts'

file="$ARTEFACT/$FILE"
download_to clickhouse "$URL" "$file" "$SHA256"

#
# Extract artefacts:
#
header 'extracting artefacts'

extract_to clickhouse "$file" "$SRC" --strip-components=1

#
# Maintaining the set of clickhouse patches is somewhat challenging.  To make
# it easier we create a local git repository in the extracted source directory
# and then apply the patches to the git history.  This allows for iterative
# work on the patches and then the full set can be re-generated using something
# similar to:
#
#     git rm patches/*
#     git -C work/src format-patch base..
#     mv work/src/0*.patch patches/
#     git add patches/*
#
header 'setting up git repository for source tree'

if [[ ! -d "$SRC/.git" ]]; then
	git init "$SRC"
	git -C "$SRC" add .
	git -C "$SRC" commit -m 'base' -q
	git -C "$SRC" tag base
	git -C "$SRC" config user.name "Oxide Computer Company"
	git -C "$SRC" config user.email "<eng@oxide.computer>"
fi

#
# Patch ClickHouse:
#
header 'patching clickhouse source'

stamp="$STAMPS/patched.stamp"
if [[ ! -f "$stamp" ]]; then
	for f in "$ROOT/patches/"[0-9]*.patch; do
		[[ -f "$f" ]] || continue

		pstamp="$stamp.${f##*/}"
		[[ -f "$pstamp" ]] && continue

		header "apply patch $f"

		#
		# Attempt to apply the patch as a git mailbox:
		#
		if ! git -C "$SRC" am "$f"; then
			#
			# If that fails, apply as a normal patch
			# "git am" may have modified the tree.
			#
			git -C "$SRC" am --abort || true
			git -C "$SRC" reset --hard HEAD
			gpatch --directory="$SRC" --batch --forward \
			    --strip=1 < "$f"
			#
			# Determine the commit message to use:
			#
			if egrep -sq '^Subject:' "$f"; then
				subject=$(grep '^Subject:' "$f" |
				    tr -s '[[:space:]]' |
				    cut -d\  -f2-)
				#
				# Strip any sequence number:
				#
				subject=${subject#*]}
			else
				subject="Patch ${f##*/}"
			fi
			git -C "$SRC" commit -m "$subject" .
		fi

		touch "$pstamp"
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
	CFLAGS+=' -DHAVE_STRERROR_R -DSTRERROR_R_INT'
	CFLAGS+=" -I$SRC/contrib/hyperscan-cmake/x86_64/ "
	CFLAGS+=" -fno-use-cxa-atexit "

	CXXFLAGS="$CXXINC $CFLAGS"
	CXXFLAGS+=" -fcxx-exceptions -fexceptions -frtti "

	#
	# We must set PARALLEL_COMPILE_JOBS, or else the cmake files will make
	# a somewhat naive guess and set a Ninja job pool that constrains
	# compilation parallelism.
	#
	# The link editor gets quite large when linking some of the final
	# objects -- sometimes 15-30GB! -- so we constrain PARALLEL_LINK_JOBS
	# to 1.
	#
	CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" cmake \
	    -DCMAKE_BUILD_TYPE=Release \
	    -DCMAKE_INSTALL_PREFIX="/opt/oxide/clickhouse" \
	    -DCMAKE_C_COMPILER="/opt/ooce/llvm-$CLANGVER/bin/clang" \
	    -DCMAKE_CXX_COMPILER="/opt/ooce/llvm-$CLANGVER/bin/clang++" \
	    -DCMAKE_C_FLAGS="$CFLAGS" \
	    -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
	    -DABSL_CXX_STANDARD="20" \
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
	    -DCMAKE_BUILD_WITH_INSTALL_RPATH=on \
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
	info "running build with ninja (jobs $njobs)..."

	#
	# The build is massive.  Try to parallelize until we error out, usually
	# due to space constraints while linking.  At that point, continue
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
# Strip the resulting binary.  This part is crucial.  ClickHouse's binary is
# 3+GiB unstripped.
#
rm -f "$CACHE/clickhouse"
cp "$SRC/build/programs/clickhouse" "$CACHE/clickhouse"
/usr/bin/strip -x "$CACHE/clickhouse"

cp -P $SRC/build/programs/clickhouse-* "$CACHE/"
/usr/bin/strip -x "$CACHE/clickhouse-library-bridge"

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
	cp -P $CACHE/* \
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
	    "database/$NAM-$SVER@$VER-2.0" \
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
	    -C "$SRC/programs/server" users.xml
	header 'build output:'
	ls -lh $WORK/*.tar.gz
	exit 0
	;;
*)
	fatal "unknown output type: $OUTPUT_TYPE"
	;;
esac
