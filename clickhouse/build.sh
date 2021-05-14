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
PATCH_DIR="$ROOT/patches"
ARTEFACT="$ROOT/clickhouse"
WORK="$ARTEFACT/build"
VER="21.6"
COMMIT=""

#
# Download ClickHouse sources
#
REPO="https://github.com/oxidecomputer/clickhouse"
header "downloading clickhouse sources"
if [[ -d "$ARTEFACT" ]]; then
    info "clickhouse repo exists, removing and re-cloning"
    rm -rf "$ARTEFACT"
fi
git clone "$REPO"
cd "$ARTEFACT"
git submodule update --init --recursive

#
# Patch ClickHouse:
#
header 'patching clickhouse source'
# Patches to the actual sources. Below we apply those to CMake-generated files.
git apply --verbose $PATCH_DIR/direct/*

#
# Build ClickHouse
#
header 'building clickhouse'
mkdir -p "$WORK" && cd "$WORK"
FLAGS="-D_REENTRANT -D_POSIX_PTHREAD_SEMANTICS -D__EXTENSIONS__ -m64 -I$ARTEFACT/contrib/hyperscan-cmake/x86_64/"
CFLAGS="$FLAGS" CXXFLAGS="$FLAGS" \
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

header 'patching CMake-generated files'
cd "$ARTEFACT" && git apply --verbose $PATCH_DIR/cmake/* && cd "$WORK"

# The build is massive. Try to parallelize until we error out, usually due to space constraints while
# linking. At that point, continue serially
ninja || (header 'parallel build failed, continuing serially' && ninja -j 1)

# Strip the resulting binary. This part is crucial. ClickHouse's binary is 3+GiB unstripped.
/usr/bin/strip "$WORK/programs/clickhouse"
/usr/bin/tar cvfz \
    $ROOT/clickhouse-v$VER.illumos.tar.gz \
    -C "$WORK/programs" clickhouse \
    -C "$ARTEFACT/programs/server" config.xml \
    -C "$ARTEFACT/programs/server" users.xml \
    -C "$ROOT" manifest.xml

header 'build output:'
find "$WORK" -type f -ls
