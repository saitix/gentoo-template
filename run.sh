#!/usr/bin/env bash
set -euo pipefail

# --- Paths ------------------------------------------------------------------
# These mirror oddlama/gentoo-install's scripts/config.sh (TMP_DIR and
# ROOT_MOUNTPOINT). The values MUST stay in sync with upstream — the installer
# always works under this dir regardless of where run.sh is launched from.
INSTALLER_DIR="/tmp/gentoo-install"   # upstream TMP_DIR: clone + working area
CHROOT_ROOT="$INSTALLER_DIR/root"     # upstream ROOT_MOUNTPOINT: the new system

##############################################################################
# --- Post-install: Function to enable binary package building in the installed system.
# oddlama/gentoo-install mounts the new system under $ROOT_MOUNTPOINT, which is
# /tmp/gentoo-install/root (see upstream scripts/config.sh).
enable_buildpkg() {
	local makeconf="$1"

	if [[ ! -f "$makeconf" ]]; then
		echo "[-bb] make.conf not found at '$makeconf'; nothing to do" >&2
		return 1
	fi

	# Keep a timestamped backup before editing
	cp -a "$makeconf" "${makeconf}.bak-bb-$(date +%Y%m%d%H%M%S)"

	# FEATURES: make sure the 'buildpkg' token is enabled, preserving the rest.
	if grep -qE '^FEATURES=' "$makeconf"; then
		# Extract the value of the first FEATURES= line (strip FEATURES= and any
		# surrounding double/single quotes).
		local cur token found='false' newval
		cur=$(grep -E '^FEATURES=' "$makeconf" | head -n1 \
			| sed -E 's/^FEATURES=//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')

		# Look for the buildpkg token (so -buildpkg / getbinpkg don't false-match)
		read -ra _tokens <<<"$cur"
		for token in "${_tokens[@]}"; do
			if [[ "$token" == "buildpkg" ]]; then
				found='true'; break
			fi
		done

		if [[ "$found" == 'true' ]]; then
			echo "[-bb] FEATURES already contains buildpkg"
		else
			newval="${cur:+$cur }buildpkg"
			sed -i "s|^FEATURES=.*|FEATURES=\"$newval\"|" "$makeconf"
			echo "[-bb] FEATURES updated -> FEATURES=\"$newval\""
		fi
	else
		echo 'FEATURES="buildpkg"' >>"$makeconf"
		echo '[-bb] FEATURES not present; added FEATURES="buildpkg"'
	fi

	# BINPKG_COMPRESS: force lz4 (fast, low-CPU compression for the binpkgs).
	if grep -qE '^BINPKG_COMPRESS=' "$makeconf"; then
		if grep -qE '^BINPKG_COMPRESS="lz4"' "$makeconf"; then
			echo "[-bb] BINPKG_COMPRESS already lz4"
		else
			sed -i 's|^BINPKG_COMPRESS=.*|BINPKG_COMPRESS="lz4"|' "$makeconf"
			echo '[-bb] BINPKG_COMPRESS set to lz4'
		fi
	else
		echo 'BINPKG_COMPRESS="lz4"' >>"$makeconf"
		echo '[-bb] BINPKG_COMPRESS not present; added BINPKG_COMPRESS="lz4"'
	fi
}
##############################################################################
# Function to  copy the working tree (not a fresh 'git clone') so that local gentoo.conf
# edits and the local git state are preserved — a future 'git push' from
# /opt/gentoo-template will still work. -a preserves perms/symlinks/.git.
copy_repo_into_chroot() {
	local target="$CHROOT_ROOT/opt/gentoo-template"

	if [[ ! -d "$CHROOT_ROOT" ]]; then
		echo "[stage3] chroot root '$CHROOT_ROOT' not found; cannot stage repo" >&2
		return 1
	fi

	mkdir -p "$target"
	# Copy contents (trailing /.) so we don't nest a gentoo-template/ subdir.
	cp -a "$pwd/." "$target/"

	echo "[stage3] repo staged at /opt/gentoo-template in the chroot"
	echo "[stage3] After reboot run:  cd /opt/gentoo-template && ./run_stage3.sh"
}
##############################################################################

# --- Optional flags ---------------------------------------------------------
# -bb  Enable binary package building on the installed system.
#      After ./install finishes, the chrooted /etc/portage/make.conf is edited
#      to enable FEATURES="buildpkg" (preserving existing features) and to force
#      BINPKG_COMPRESS="lz4". See:
#      https://wiki.gentoo.org/wiki/Binary_package_guide#Setting_up_a_binary_package_host
BUILD_BINPKG='false'
INSTALL_ARGS=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		-bb)
			BUILD_BINPKG='true'
			shift
			;;
		--)
			# Everything after -- is forwarded verbatim to ./install
			shift
			while [[ $# -gt 0 ]]; do
				INSTALL_ARGS+=("$1"); shift
			done
			;;
		*)
			# Unknown options/args are forwarded to the upstream installer
			INSTALL_ARGS+=("$1"); shift
			;;
	esac
done

#Prepare and clone the gentoo-install repo, then copy our gentoo.conf into it. This is needed because the upstream installer expects gentoo.conf to be in the same directory as install.sh.
pwd=$(pwd)

# Sanity: the local gentoo.conf must exist before we try to copy it in.
if [[ ! -f "$pwd/gentoo.conf" ]]; then
	echo "ERROR: gentoo.conf not found in '$pwd' — cannot continue." >&2
	exit 1
fi

cd /tmp

# Guard against a leftover directory from a previous/failed run: git clone
# refuses to clone into a path that already exists, which would abort here.
if [[ -e "$INSTALLER_DIR" ]]; then
	echo "ERROR: $INSTALLER_DIR already exists (leftover from a previous run?)." >&2
	echo "       Remove it (rm -rf $INSTALLER_DIR) and re-run." >&2
	exit 1
fi

# Clone the upstream installer and check it actually succeeded.
if ! git clone https://github.com/oddlama/gentoo-install; then
	echo "ERROR: git clone of oddlama/gentoo-install failed." >&2
	exit 1
fi

# Verify the clone produced the expected directory before we use it.
if [[ ! -d "$INSTALLER_DIR" ]]; then
	echo "ERROR: $INSTALLER_DIR does not exist after git clone." >&2
	exit 1
fi

#Run the upstream installer (install.sh) from the cloned repo
cp "$pwd/gentoo.conf" "$INSTALLER_DIR"/
cd "$INSTALLER_DIR"

#Fixup: issue: https://github.com/oddlama/gentoo-install/issues/153
export DEBUGINFOD_URLS="http://foo.mynet.local/debuginfo https://debuginfod.elfutils.org/" 
export DEBUGINFOD_IMA_CERT_PATH="/etc/certs" 
##

# Run the real installer (forward any extra arguments)
if [[ ${#INSTALL_ARGS[@]} -gt 0 ]]; then
	./install "${INSTALL_ARGS[@]}"
else
	./install
fi

# --- Post-install: enable binary package building when -bb was given --------
if [[ "$BUILD_BINPKG" == 'true' ]]; then
	echo '[-bb] Enabling binary package building in the installed system...'
	enable_buildpkg "$CHROOT_ROOT/etc/portage/make.conf"
fi

# --- Post-install: stage this repo into the installed system ----------------
# Copy the working gentoo-template checkout (the dir run.sh was launched from)
# verbatim into the chroot at /opt/gentoo-template. After the first reboot the
# second-stage installer can then be run with:
#     cd /opt/gentoo-template && ./run_stage3.sh
#
copy_repo_into_chroot

