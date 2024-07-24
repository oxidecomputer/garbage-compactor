#!/bin/bash
#
# Copyright 2024 Oxide Computer Company
#

unset HARDLINK_TARGETS
unset BRANCH

HELIOS_REPO='https://pkg.oxide.computer/helios/2/dev/'

CTFCONVERT=${CTFCONVERT:-/opt/onbld/bin/i386/ctfconvert}
if [[ ! -x $CTFCONVERT ]]; then
	printf 'ERROR: install pkg:/developer/build/onbld\n' >&2
	exit 1
fi

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
	local sha256="$4"

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

	if [[ -n "$sha256" ]]; then
		info "verifying hash for $name..."
		if ! actual=$(digest -a sha256 "$path"); then
			fatal "could not calculate SHA256 of $name, file $path"
		fi

		if [[ "$actual" != "$sha256" ]]; then
			fatal "$path hash mismatch $actual != $sha256"
		fi
		info "$name hash ok"
	fi

	return 0
}

function apply_patches {
	local patchdir=$1
	local srcdir=$2

	if [[ -z $srcdir ]]; then
		srcdir="$PWD"
	fi

	info "applying patches from $patchdir in $srcdir..."

	if [[ ! -d "$patchdir" ]]; then
		fatal "could not find patch directory $patchdir"
	fi

	for f in "$patchdir"/*.patch; do
		if [[ ! -f "$f" ]]; then
			continue
		fi

		info "applying patch $f..."
		(cd "$srcdir" && patch -p1 --verbose < "$f")
	done
}

function make_package {
	local name="$1"
	local summary="$2"
	local proto="$3"
	local inputmf="$4"
	local mf="$WORK/input.mf"
	local publisher="helios-dev"
	local branch="${BRANCH:-2.0}"
	local repo="$WORK/repo"
	local sendargs=()
	local licdir="$ROOT/licenses"
	local pubargs=()

	#
	# Generate the base package manifest:
	#
	printf '%% generating base manifest...\n'
	rm -f "$mf"
	printf 'set name=pkg.fmri value=pkg://%s/%s@%s-%s\n' \
	    "$publisher" "$name" "$VER" "$branch" >> "$mf"
	printf 'set name=pkg.summary value="%s"\n' "$summary" >> "$mf"

	if [[ -n "$inputmf" ]]; then
		cat "$inputmf" >> "$mf"
	fi

	#
	# Assemble list of hardlink target arguments.
	#
	if [[ -n $HARDLINK_TARGETS ]]; then
		for hlt in $HARDLINK_TARGETS; do
			sendargs+=( '--target' )
			sendargs+=( "$hlt" )
		done
	fi

	#
	# Add all files found in the proto area.
	#
	# We keep timestamps for any Python files (and their compiled versions)
	# to prevent their immediate recompilation on the installed system.
	#
	printf '%% generating file list...\n'
	pkgsend generate -T '*.py' -T '*.pyc' "${sendargs[@]}" "$proto" >> "$mf"

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

	if [[ -d $licdir ]]; then
		pubargs+=( '-d' )
		pubargs+=( "$licdir" )
	fi

	printf '%% publishing...\n'
	pkgsend publish -d "$proto" "${pubargs[@]}" -s "$repo" "$WORK/final.mf"

	printf '%% ok\n'
}

#
# Make a package without doing dependency list generation or resolution.  This
# is useful for a fully specified package such as "clickhouse/common" which
# just contains container directories and user accounts, but no ELF binaries or
# scripts with interpreters, etc.
#
# Because the contents of this package comes solely from this repository, there
# is no need for a separate branch version.
#
function make_package_simple {
	local name="$1"
	local summary="$2"
	local proto="$3"
	local inputmf="$4"
	local version="$5"
	local mf="$WORK/input.mf"
	local publisher="helios-dev"
	local repo="$WORK/repo"

	#
	# Generate the base package manifest:
	#
	printf '%% generating base manifest...\n'
	rm -f "$mf"
	printf 'set name=pkg.fmri value=pkg://%s/%s@%s\n' \
	    "$publisher" "$name" "$version" >> "$mf"
	printf 'set name=pkg.summary value="%s"\n' "$summary" >> "$mf"

	#
	# Append pkgmogrify directives to fix up the generated manifest, and
	# transform the manifest now:
	#
	printf '%% transforming manifest...\n'
	rm -f "$WORK/step1.mf"
	pkgmogrify -v -O "$WORK/step1.mf" \
	     "$ROOT/../lib/transforms.mog" \
	     "$inputmf" \
	     "$mf"

	rm -f "$WORK/final.mf"
	cat "$WORK/step1.mf" > "$WORK/final.mf"

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
