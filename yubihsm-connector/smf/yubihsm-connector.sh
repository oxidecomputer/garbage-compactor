#!/bin/bash
#
# Copyright 2024 Oxide Computer Company
#

set -o errexit
set -o pipefail

. '/lib/svc/share/smf_include.sh'

args=()

if svcprop -q -p 'config/debug' "$SMF_FMRI"; then
	if [[ "$(svcprop -p 'config/debug' "$SMF_FMRI")" == true ]]; then
		args+=( '-d' )
	fi
fi

if svcprop -q -p 'config/config_file' "$SMF_FMRI"; then
	f=$(svcprop -p 'config/config_file' "$SMF_FMRI")

	if [[ ! -f "$f" ]]; then
		printf 'ERROR: config file "%s" missing\n' "$f" >&2
		exit "$SMF_EXIT_ERR_CONFIG"
	fi

	args+=( '-c' "$f" )
fi

address=127.0.0.1
if svcprop -q -p 'config/address' "$SMF_FMRI"; then
	address=$(svcprop -p 'config/address' "$SMF_FMRI")
fi

port=12345
if svcprop -q -p 'config/port' "$SMF_FMRI"; then
	port=$(svcprop -p 'config/port' "$SMF_FMRI")
fi

args+=( '-l' "$address:$port" )

exec /usr/sbin/yubihsm-connector "${args[@]}"
