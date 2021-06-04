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

ROOT=$(cd "$(dirname "$0")" && pwd)
ARTEFACT="$ROOT/clickhouse"
WORK="$ARTEFACT/build"
VER="21.7"
BRANCH="master"
REPO="https://github.com/oxidecomputer/clickhouse"

# Get platform specific options/tools/paths
if [ $# -eq 0 ]; then
    PLATFORM="$OSTYPE"
else
    PLATFORM="$1"
fi
case $PLATFORM in
    linux*)
        PLATFORM="linux"
        BUILD_COMMAND="make"
        CC=gcc-10
        CXX=g++-10
        STRIP_ARGS="--strip-debug"
        NPROC="$(nproc)"
        ;;
    darwin*)
        PLATFORM="macos"
        BUILD_COMMAND="make"
        CC=clang
        CXX=clang
        STRIP_ARGS="-S"
        NPROC="$(sysctl -n hw.ncpu)"
        ;;
    solaris*|illumos*)
        PLATFORM="illumos"
        BUILD_COMMAND="ninja"
        CC=gcc-10
        CXX=g++-10
        STRIP_ARGS="-x"
        NPROC="$(nproc)"
        ;;
    *)
        failed "Unsupported platform $PLATFORM"
        exit 1
        ;;
esac
COMMON_PATCH_DIR="$ROOT/common/patches"
PATCH_DIR="$ROOT/$PLATFORM/patches"
FILES_DIR="$ROOT/$PLATFORM/files"
EXTRA_FILES=""
if [ -d "$FILES_DIR" ]; then
    EXTRA_FILES="$(ls "$FILES_DIR")"
fi
header "Building clickhouse for $PLATFORM"

#
# Download ClickHouse sources
#
if [ -d "$ARTEFACT" ]; then
    info "ClickHouse repo exists, resetting to HEAD"
    cd "$ARTEFACT"
    git fetch origin
    git switch "$BRANCH"
    git reset --hard "origin/$BRANCH"
    git submodule update --checkout --recursive --force
else
    info "Cloning ClickHouse sources"
    git clone "$REPO"
    cd "$ARTEFACT"
    git switch "$BRANCH"
    git submodule update --init --recursive
fi

# Apply common patches, independent of platform
header "Applying shared ClickHouse patches"
git apply --verbose $COMMON_PATCH_DIR/*

# Patches to the actual sources. Below we apply those to CMake-generated files.
if [ -d "$PATCH_DIR/direct" ]; then
    header "Applying $PLATFORM-specific patches"
    git apply --verbose $PATCH_DIR/direct/*
fi

header "Building ClickHouse"
mkdir -p "$WORK" && cd "$WORK"
FLAGS="-D_REENTRANT -D_POSIX_PTHREAD_SEMANTICS -D__EXTENSIONS__ -m64 -I$ARTEFACT/contrib/hyperscan-cmake/x86_64/"
CC=$CC CXX=$CXX CFLAGS="$FLAGS" CXXFLAGS="$FLAGS" \
cmake \
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
    "$ARTEFACT"

header "Patching CMake-generated files"
cd "$ARTEFACT"
if [ -d "$PATCH_DIR/cmake" ]; then
    git apply --verbose $PATCH_DIR/cmake/*
fi
cd "$WORK"

# The build is massive. Try to parallelize until we error out, usually due to space constraints while
# linking. At that point, continue serially
$BUILD_COMMAND -j "$NPROC" || (header "Parallel build failed, continuing serially" && $BUILD_COMMAND -j 1)

# Strip the resulting binary. This part is crucial. ClickHouse's binary is 3+GiB unstripped.
strip $STRIP_ARGS "$WORK/programs/clickhouse"
CONFIG_FILE_DIR="$ARTEFACT/programs/server"
CONFIG_FILE_NAME="config.xml"
if [ -z "$EXTRA_FILES" ]; then
    /usr/bin/tar cvfz \
        $ROOT/clickhouse-v$VER.$PLATFORM.tar.gz \
        -C "$WORK/programs" clickhouse \
        -C "$CONFIG_FILE_DIR" "$CONFIG_FILE_NAME"
else
    /usr/bin/tar cvfz \
        $ROOT/clickhouse-v$VER.$PLATFORM.tar.gz \
        -C "$WORK/programs" clickhouse \
        -C "$CONFIG_FILE_DIR" "$CONFIG_FILE_NAME" \
        -C "$FILES_DIR" "$EXTRA_FILES"
fi

header "Build output:"
find "$WORK" -type f -ls
