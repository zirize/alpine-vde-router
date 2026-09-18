#!/bin/bash
# ---------------------------------------------------------------------------
# Create the libvirt domain for the appliance.
#
#   ./scripts/host/create-vm.sh            # create it
#   ./scripts/host/create-vm.sh --recreate # delete an existing one first
#
# Everything here talks to libvirtd, which already runs as root, so you do
# NOT need sudo - you only need to be in the "libvirt" group.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/../.."
. ./config.sh

RECREATE=0
[ "${1:-}" = "--recreate" ] && RECREATE=1

die() { echo "error: $*" >&2; exit 1; }

command -v virt-install >/dev/null || die "virt-install not found (install virtinst)"
[ -r "$ISO_PATH" ] || die "ISO not readable: $ISO_PATH"
virsh -q pool-info default >/dev/null 2>&1 || die "libvirt storage pool 'default' is missing"

if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    [ "$RECREATE" = 1 ] || die "domain '$VM_NAME' already exists (use --recreate)"
    echo "==> removing existing domain '$VM_NAME'"
    virsh destroy "$VM_NAME" >/dev/null 2>&1 || true
    virsh undefine "$VM_NAME" --nvram >/dev/null 2>&1 || virsh undefine "$VM_NAME" >/dev/null
fi

if virsh vol-info --pool default "${VM_NAME}.qcow2" >/dev/null 2>&1; then
    [ "$RECREATE" = 1 ] || die "volume ${VM_NAME}.qcow2 already exists (use --recreate)"
    echo "==> deleting existing disk ${VM_NAME}.qcow2"
    virsh vol-delete --pool default "${VM_NAME}.qcow2" >/dev/null
fi

echo "==> creating ${VM_DISK_GB}G disk"
virsh vol-create-as default "${VM_NAME}.qcow2" "${VM_DISK_GB}G" --format qcow2 >/dev/null
DISK=$(virsh vol-path --pool default "${VM_NAME}.qcow2")

# --- build the argument list ----------------------------------------------
args=(
  --name "$VM_NAME"
  --memory "$VM_RAM_MB"
  --vcpus "$VM_VCPUS"
  --cpu host-passthrough
  --disk "path=$DISK,bus=virtio,format=qcow2,discard=unmap"
  --cdrom "$ISO_PATH"
  --os-variant alpinelinux3.19
  --graphics none
  --console pty,target_type=serial
  --noautoconsole
  --noreboot
)

# Uplink NIC.
if [ "$HOST_BRIDGE" = "default" ]; then
    args+=( --network network=default,model=virtio )
else
    args+=( --network "bridge=$HOST_BRIDGE,model=virtio" )
fi

# Isolated NIC on the VDE TAP (macvtap in bridge mode).
if [ -n "${VDE_TAP:-}" ]; then
    ip link show "$VDE_TAP" >/dev/null 2>&1 \
        || die "TAP device '$VDE_TAP' does not exist - run scripts/host/vde-switch.sh first"
    args+=( --network "type=direct,source=$VDE_TAP,source_mode=bridge,model=virtio" )
fi

# virtiofs needs shared memory backing, otherwise the domain refuses to start.
if [ -n "${VIRTIOFS_SHARES// /}" ]; then
    args+=( --memorybacking access.mode=shared,source.type=memfd )
    while IFS='|' read -r hostpath tag guestpath mode; do
        [ -n "${hostpath:-}" ] || continue
        [ -d "$hostpath" ] || die "virtiofs source is not a directory: $hostpath"
        args+=( --filesystem "driver.type=virtiofs,source.dir=$hostpath,target.dir=$tag" )
    done <<< "$(echo "$VIRTIOFS_SHARES" | sed '/^[[:space:]]*$/d')"
fi

echo "==> virt-install"
printf '    %s\n' "${args[@]}"
virt-install "${args[@]}"

echo
echo "Domain '$VM_NAME' defined and booted from the ISO."
echo "Next: ./scripts/host/install-alpine.py"
