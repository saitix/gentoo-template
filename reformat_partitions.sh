#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        --help|-h)
            cat <<'USAGE'
Usage: reformat_partitions.sh [--dry-run] [--force]

Reads all partitions on all disks and reformats them, preserving:
  - Filesystem type     (FSTYPE)
  - Filesystem label    (LABEL)     — set via mkfs
  - GPT partition label (PARTLABEL) — set via parted name

Tools required: blkid, parted, wipefs  (all present on the Gentoo minimal CD)

  --dry-run   Show what would happen without touching any device
  --force     Skip interactive confirmations

Environment variables DRY_RUN=1 and FORCE=1 are also honoured.
USAGE
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

(( EUID == 0 )) || { echo "Must run as root" >&2; exit 1; }
for cmd in blkid parted wipefs; do
    command -v "$cmd" &>/dev/null || { echo "Missing required tool: $cmd" >&2; exit 1; }
done

log()  { echo "[$( [[ "$DRY_RUN" == "1" ]] && echo DRY-RUN || echo RUN )] $*"; }
warn() { echo "  WARNING: $*" >&2; }

# ---------------------------------------------------------------------------
# Determine parent disk + partition number from device path.
# Prints "<disk_dev> <partnum>" and returns 0.
# Returns 1 if the device is not a recognisable partition.
# ---------------------------------------------------------------------------
resolve_parent() {
    local dev="$1"
    local base="${dev##*/}"
    local disk partnum

    if [[ "$base" =~ ^(nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
        disk="/dev/${BASH_REMATCH[1]}"
        partnum="${BASH_REMATCH[2]}"
    elif [[ "$base" =~ ^(mmcblk[0-9]+)p([0-9]+)$ ]]; then
        disk="/dev/${BASH_REMATCH[1]}"
        partnum="${BASH_REMATCH[2]}"
    elif [[ "$base" =~ ^([a-z]+)([0-9]+)$ ]]; then
        disk="/dev/${BASH_REMATCH[1]}"
        partnum="${BASH_REMATCH[2]}"
    elif [[ "$base" =~ ^(xvd[a-z]+)([0-9]+)$ ]]; then
        disk="/dev/${BASH_REMATCH[1]}"
        partnum="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    [[ -b "$disk" ]] || return 1
    echo "$disk $partnum"
}

is_gpt() {
    [[ "$(blkid -o value -s PTTYPE "$1" 2>/dev/null)" == "gpt" ]]
}

# ---------------------------------------------------------------------------
# Check if a device is currently mounted.
# Returns 0 if mounted, 1 if not.
# ---------------------------------------------------------------------------
is_mounted() {
    local dev="$1"
    if command -v findmnt &>/dev/null; then
        findmnt -n -o TARGET "$dev" &>/dev/null
    else
        grep -Eq "^[[:space:]]*$dev[[:space:]]" /proc/mounts 2>/dev/null
    fi
}

confirm() {
    [[ "$FORCE" == "1" ]] && return 0
    local ans=""
    read -r -p "$1 [y/N] " ans
    [[ "${ans,,}" == y ]]
}

# ---------------------------------------------------------------------------
# Format a partition with the same fstype and filesystem label.
# ---------------------------------------------------------------------------
do_format() {
    local dev="$1" fstype="$2" label="$3"

    if [[ "$fstype" != "swap" ]]; then
        log "wipefs -a '$dev'"
        [[ "$DRY_RUN" == "1" ]] || wipefs -a "$dev"
    fi

    case "$fstype" in
        ext2|ext3|ext4)
            log "mkfs.$fstype -F -L '$label' '$dev'"
            [[ "$DRY_RUN" == "1" ]] || mkfs."$fstype" -F -L "$label" "$dev"
            ;;
        btrfs)
            log "mkfs.btrfs -f -L '$label' '$dev'"
            [[ "$DRY_RUN" == "1" ]] || mkfs.btrfs -f -L "$label" "$dev"
            ;;
        xfs)
            local lbl="${label:0:12}"
            log "mkfs.xfs -f -L '$lbl' '$dev'"
            [[ "$DRY_RUN" == "1" ]] || mkfs.xfs -f -L "$lbl" "$dev"
            ;;
        vfat|fat16|fat32)
            local lbl="${label:0:11}"
            local f=32
            [[ "$fstype" == "fat16" ]] && f=16
            log "mkfs.fat -F $f -n '$lbl' '$dev'"
            [[ "$DRY_RUN" == "1" ]] || mkfs.fat -F "$f" -n "$lbl" "$dev"
            ;;
        ntfs)
            log "mkfs.ntfs -f -Q -L '$label' '$dev'"
            [[ "$DRY_RUN" == "1" ]] || mkfs.ntfs -f -Q -L "$label" "$dev"
            ;;
        exfat)
            log "mkfs.exfat -n '$label' '$dev'"
            [[ "$DRY_RUN" == "1" ]] || mkfs.exfat -n "$label" "$dev"
            ;;
        f2fs)
            log "mkfs.f2fs -f -l '$label' '$dev'"
            [[ "$DRY_RUN" == "1" ]] || mkfs.f2fs -f -l "$label" "$dev"
            ;;
        swap)
            log "mkswap -L '$label' '$dev'"
            [[ "$DRY_RUN" == "1" ]] || mkswap -L "$label" "$dev"
            ;;
        *)
            warn "unsupported fstype '$fstype' on $dev — skipping"
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Set the GPT partition name (partlabel) via parted.
# ---------------------------------------------------------------------------
set_partlabel() {
    local dev="$1" partlabel="$2" disk="$3" partnum="$4"
    [[ -n "$partlabel" ]] || return 0

    if is_gpt "$disk"; then
        log "parted -s '$disk' name $partnum '$partlabel'"
        [[ "$DRY_RUN" == "1" ]] || parted -s "$disk" name "$partnum" "$partlabel"
    else
        warn "partlabel '$partlabel' on $dev ignored — MBR has no GPT partition names"
    fi
}

# ── main ──────────────────────────────────────────────────────────────────
main() {
    echo "=== reformat_partitions.sh ==="
    [[ "$DRY_RUN" == "1" ]] && echo "(DRY-RUN — no devices will be modified)"
    echo ""

    local processed=0
    local cur_dev="" cur_fstype="" cur_label="" cur_partlabel=""

    flush_record() {
        [[ -n "$cur_dev" && -n "$cur_fstype" ]] || return 0
        [[ -b "$cur_dev" ]] || return 0

        local info
        info=$(resolve_parent "$cur_dev") || return 0
        local disk="${info%% *}" partnum="${info##* }"

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        printf "  Device:    %s\n" "$cur_dev"
        printf "  Disk:      %s  (partition #%s)\n" "$disk" "$partnum"
        printf "  FSTYPE:    %s\n" "$cur_fstype"
        printf "  LABEL:     %s\n" "${cur_label:-(empty)}"
        printf "  PARTLABEL: %s\n" "${cur_partlabel:-(empty)}"

        if is_mounted "$cur_dev"; then
            warn "SKIPPED $cur_dev — currently mounted, refusing to reformat"
            return 0
        fi

        if confirm "Reformat $cur_dev as $cur_fstype?"; then
            if do_format "$cur_dev" "$cur_fstype" "$cur_label"; then
                set_partlabel "$cur_dev" "$cur_partlabel" "$disk" "$partnum"
            fi
            echo "  Done."
            (( processed++ )) || true
        else
            echo "  Skipped."
        fi
    }

    while IFS= read -r -u3 line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]]; then
            flush_record
            cur_dev="" cur_fstype="" cur_label="" cur_partlabel=""
            continue
        fi

        local key="${line%%=*}"
        local value="${line#*=}"

        case "$key" in
            DEVNAME)   cur_dev="$value" ;;
            TYPE)      cur_fstype="$value" ;;
            LABEL)     cur_label="$value" ;;
            PARTLABEL) cur_partlabel="$value" ;;
        esac
    done 3< <(blkid -o export 2>/dev/null; echo "")

    echo ""
    echo "=== Finished. $processed partition(s) reformatted. ==="
}

main
