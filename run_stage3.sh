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


# --- System upgrade ---------------------------------------------------------
# Bring the whole system up to date. Prefer gentoo-update; if it isn't
# installed, fall back to a plain emerge @world. Every step is wrapped so a
# failure yields a clear message and aborts the script (set -e + explicit exit).
#
# When -bb was given, binary packages are built: gentoo-update/emerge get
# --buildpkg, and afterwards quickpkg re-archives every currently-installed
# package so the binpkgs can be reused on other machines.
if command -v gentoo-update >/dev/null 2>&1; then
	if [[ "$BUILD_BINPKG" == 'true' ]]; then
		echo "run_stage3: upgrading @world via gentoo-update (--buildpkg)"
		if ! gentoo-update update -m full --clean --args='--buildpkg'; then
			echo "ERROR: gentoo-update failed." >&2
			exit 1
		fi
	else
		echo "run_stage3: upgrading @world via gentoo-update"
		if ! gentoo-update update -m full --clean; then
			echo "ERROR: gentoo-update failed." >&2
			exit 1
		fi
	fi
else
	# gentoo-update not available — fall back to a plain emerge @world update.
	if [[ "$BUILD_BINPKG" == 'true' ]]; then
		echo "run_stage3: gentoo-update not found; emerging @world (--buildpkg)"
		if ! emerge --ask --verbose --update --deep --newuse --buildpkg @world; then
			echo "ERROR: emerge @world update failed." >&2
			exit 1
		fi
	else
		echo "run_stage3: gentoo-update not found; emerging @world"
		if ! emerge --ask --verbose --update --deep --newuse @world; then
			echo "ERROR: emerge @world update failed." >&2
			exit 1
		fi
	fi
fi

# Build binary packages of all currently-installed packages (buildpkg path).
# quickpkg ships in app-portage/gentoolkit — warn (don't fail) if it's missing.
if [[ "$BUILD_BINPKG" == 'true' ]]; then
	if command -v quickpkg >/dev/null 2>&1; then
		echo "run_stage3: creating binary packages of all installed packages"
		if ! quickpkg "*/*"; then
			echo "ERROR: quickpkg failed." >&2
			exit 1
		fi
	else
		echo "WARNING: quickpkg not found (install app-portage/gentoolkit); skipping quickpkg." >&2
	fi
fi


#Cleaning up after an update. After the update, Portage recommends running
emerge --depclean
