#!/bin/bash

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
		gtar -C "$outdir" $extra -xaf "$tar"
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

function make_package {
	local name="$1"
	local summary="$2"
	local proto="$3"
	local mf="$WORK/input.mf"
	local publisher="helios-dev"
	local branch='1.0'
	local repo="$WORK/repo"

	#
	# Generate the base package manifest:
	#
	printf '%% generating base manifest...\n'
	rm -f "$mf"
	printf 'set name=pkg.fmri value=pkg://%s/%s@%s-%s\n' \
	    "$publisher" "$name" "$VER" "$branch" >> "$mf"
	printf 'set name=pkg.summary value="%s"\n' "$summary" >> "$mf"

	#
	# Add all files found in the proto area.
	#
	# We keep timestamps for any Python files (and their compiled versions)
	# to prevent their immediate recompilation on the installed system.
	#
	printf '%% generating file list...\n'
	pkgsend generate -T '*.py' -T '*.pyc' "$proto" >> "$mf"

	#
	# Append pkgmogrify directives to fix up the generated manifest, and
	# transform the manifest now:
	#
	printf '%% transforming manifest...\n'
	rm -f "$WORK/step1.mf"
	pkgmogrify -v -O "$WORK/step1.mf" "$ROOT/../lib/transforms.mog" "$mf"

	#
	# Walk through the packaged files and generate a list of dependencies:
	#
	printf '%% generating dependency list...\n'
	rm -f "$WORK/step2.mf"
	pkgdepend generate -d "$proto" "$WORK/step1.mf" > "$WORK/step2.mf"

	#
	# Resolve those dependencies to specific packages and versions:
	#
	printf '%% resolving dependencies...\n'
	rm -f "$WORK/step2.mf.res"
	pkgdepend resolve "$WORK/step2.mf"

	printf -- '===== RESOLVED DEPENDENCIES: =====\n'
	cat "$WORK/step2.mf.res"
	printf -- '==================================\n'

	printf '%% creating repository...\n'
	rm -rf "$repo"
	pkgrepo create "$repo"
	pkgrepo add-publisher -s "$repo" "$publisher"

	rm -f "$WORK/final.mf"
	cat "$WORK/step1.mf" "$WORK/step2.mf.res" > "$WORK/final.mf"

	printf '%% publishing...\n'
	pkgsend publish -d "$proto" -s "$repo" "$WORK/final.mf"

	printf '%% ok\n'
}

function build_deps {
	local deps_missing=()

	for p in "$@"; do
		if ! pkg info -q "$p"; then
			deps_missing+=( "$p" )
		fi
	done

	if (( ${#deps_missing[@]} > 0 )); then
		info "installing package ${deps_missing[@]}"
		pfexec pkg install -v "${deps_missing[@]}"
	fi

	info "build dependency versions:"
	pkg list -v "$@"
}
