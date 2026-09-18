#!/bin/sh
# ---------------------------------------------------------------------------
# Mount the host directories that were handed to this VM with virtiofs.
#
# VIRTUAL MACHINES ONLY. On a physical server there is nothing to mount here -
# just point SHARE_DIR and friends at real directories in config.sh and skip
# this script entirely.
#
# Safe to run more than once.
# ---------------------------------------------------------------------------
. "$(dirname "$0")/_common.sh"

if [ -z "$(printf '%s' "${VIRTIOFS_SHARES:-}" | tr -d '[:space:]')" ]; then
    say "No virtiofs shares configured - nothing to do"
    exit 0
fi

grep -q virtiofs /proc/filesystems || modprobe virtiofs 2>/dev/null || true
if ! grep -q virtiofs /proc/filesystems; then
    echo "error: this kernel has no virtiofs support."
    echo "       Are you sure this is a VM created by scripts/host/create-vm.sh?"
    echo "       If this is a physical server, set VIRTIOFS_SHARES=\"\" in config.sh."
    exit 1
fi

say "Mounting virtiofs shares"
printf '%s\n' "$VIRTIOFS_SHARES" | while IFS='|' read -r hostpath tag guestpath mode; do
    [ -n "${tag:-}" ] || continue
    mode=${mode:-rw}
    case "$mode" in ro) opts="ro" ;; *) opts="defaults" ;; esac

    mkdir -p "$guestpath"
    if grep -qE "^[[:space:]]*$tag[[:space:]]" /etc/fstab; then
        info "already in fstab: $tag -> $guestpath"
    else
        printf '%s\t%s\tvirtiofs\t%s\t0 0\n' "$tag" "$guestpath" "$opts" >> /etc/fstab
        info "added to fstab:   $tag -> $guestpath ($mode)"
    fi

    if mountpoint -q "$guestpath" 2>/dev/null || mount | grep -q " on $guestpath "; then
        continue
    fi
    if mount "$guestpath" 2>/dev/null; then
        info "mounted:          $guestpath"
    else
        warn "could not mount tag '$tag' on $guestpath"
        warn "  the tag must match target.dir in the domain XML exactly:"
        warn "      virsh dumpxml \$VM | grep -A2 virtiofs"
    fi
done

say "Current mounts"
mount | grep virtiofs | sed 's/^/    /' || info "(none)"

cat <<'NOTE'

    Note: virtiofs does not pass extended attributes through. Anything that
    needs them fails with errno 95 (ENOTSUP). That is why the AFP setup keeps
    its CNID index on the local disk and sets "ea = none".
NOTE
