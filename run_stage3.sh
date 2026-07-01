#!/usr/bin/env bash
set -euo pipefail

# run_stage3.sh — second-stage package install, run AFTER the first reboot.
#
# The initial installer (run.sh) lays down a minimal stage-1 system and copies
# this repo into /opt/gentoo-template. After rebooting into the new system,
# run this script to install the rest of the packages defined in
# ADDITIONAL_PACKAGES_stage3 (see gentoo.conf, the single source of truth).
#
# Usage:
#   ./run_stage3.sh        # install the stage-3 packages from source
#   ./run_stage3.sh -bb    # also build binary packages (--buildpkg)
#   ./run_stage3.sh --pretend -bb   # extra args are forwarded to emerge
#
# Any argument other than -bb is forwarded to emerge.

# --- Optional flags ---------------------------------------------------------
# -bb  Tell emerge to also create binary packages of everything it builds
#      (passes --buildpkg). This mirrors the -bb option of run.sh, which sets
#      FEATURES="buildpkg" in make.conf; --buildpkg does the same per-invocation.
BUILD_BINPKG='false'
EMERGE_EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		-bb)
			BUILD_BINPKG='true'
			shift
			;;
		*)
			# Unknown options/args are forwarded to emerge
			EMERGE_EXTRA_ARGS+=("$1"); shift
			;;
	esac
done

# --- Locate and source gentoo.conf ------------------------------------------
# gentoo.conf holds ADDITIONAL_PACKAGES_stage3 (and ADDITIONAL_PACKAGES).
# Sourcing only defines variables/functions — it does NOT run the installer,
# so the disk_configuration()/before_configure_portage() hooks etc. are inert.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/gentoo.conf"

# Sanity: make sure the stage-3 array exists and is non-empty.
if ! declare -p ADDITIONAL_PACKAGES_stage3 >/dev/null 2>&1; then
	echo "run_stage3: ADDITIONAL_PACKAGES_stage3 is not defined in gentoo.conf" >&2
	exit 1
fi
if [[ ${#ADDITIONAL_PACKAGES_stage3[@]} -eq 0 ]]; then
	echo "run_stage3: ADDITIONAL_PACKAGES_stage3 is empty; nothing to install."
	exit 0
fi

# --- Build the emerge command -----------------------------------------------
# --noreplace      : don't reinstall packages that are already up to date
# --jobs=4 -l9     : parallel build limits (load-average 9)
EMERGE_OPTS=(--verbose --noreplace --jobs=4 --load-average=9)

if [[ "$BUILD_BINPKG" == 'true' ]]; then
	EMERGE_OPTS+=(--buildpkg)
	echo "run_stage3: binary package building enabled (--buildpkg)"
fi

echo "run_stage3: emerging ${#ADDITIONAL_PACKAGES_stage3[@]} packages..."

if [[ ${#EMERGE_EXTRA_ARGS[@]} -gt 0 ]]; then
	emerge "${EMERGE_OPTS[@]}" "${EMERGE_EXTRA_ARGS[@]}" "${ADDITIONAL_PACKAGES_stage3[@]}"
else
	emerge "${EMERGE_OPTS[@]}" "${ADDITIONAL_PACKAGES_stage3[@]}"
fi
