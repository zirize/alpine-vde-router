# 3 · Creating the VM

**Skip this chapter** on a physical server. Go to
[04 · Installing Alpine](04-install-alpine.md).

## What this does

Defines a libvirt domain with:

* a small virtio disk
* **two** network cards — one on a bridge to your real network, one on the
  VDE TAP device
* a serial console, so the installer can be automated and so you can always get
  in even when the network is broken
* optional shared folders from the host, using virtiofs

## Before you start

**1. libvirt and QEMU.**

```bash
# Debian / Ubuntu
sudo apt install qemu-system-x86 libvirt-daemon-system virtinst virtiofsd python3-pexpect
sudo usermod -aG libvirt "$(id -un)"
# log out and back in, so the new group takes effect
```

Check that you can talk to libvirt **without sudo** — everything below depends
on it:

```bash
virsh list --all
```

If that prints a table (even an empty one), you are fine. If it says
"failed to connect", you are not in the `libvirt` group yet.

**2. A bridge to your real network.** The appliance needs an address on your
existing LAN. The usual way is a bridge named `br0` that contains your physical
network port.

```bash
ip -br addr        # is there a br0 with your LAN address on it?
```

If you have no bridge and do not want to make one, set `HOST_BRIDGE="default"`
in `config.sh`. The appliance then sits behind libvirt's own NAT. Everything in
this guide still works; you just cannot reach the appliance from other machines
on your LAN, only from this host.

**3. The Alpine ISO.** Download the **Virtual** edition from
<https://alpinelinux.org/downloads/> — it has a kernel built for VMs and is
about 60 MB. Put the path in `ISO_PATH`.

**4. Shared folders,** if you want them. Create the directories on the host
first; the script refuses to continue if a source directory is missing.

## Do it

Edit `config.sh`:

```bash
cp config.example.sh config.sh
nano config.sh
```

The host section is at the bottom:

```sh
VM_NAME="vde"
VM_RAM_MB="2048"       # 512 is enough for a router only
VM_VCPUS="2"
VM_DISK_GB="4"
ISO_PATH="$HOME/iso/alpine-virt-3.24.2-x86_64.iso"
HOST_BRIDGE="br0"
VDE_TAP="vde0"

VIRTIOFS_SHARES="
/srv/share/ftp|hostftp|/var/lib/ftp/uploads|rw
/srv/share/spool|hostspool|/mnt/spool|rw
"
```

Each virtiofs line is `host path | tag | mount point in the VM | ro or rw`.
The tag is just a label, but it has to match on both sides — the script takes
care of that for you.

Then:

```bash
./scripts/host/create-vm.sh
```

Add `--recreate` to throw away an existing VM of the same name and start over.
You will do that more than once while you find your feet; it is safe, and it is
how this guide was written.

### What the script actually runs

Nothing exotic. It creates the disk through libvirt's storage pool (so no sudo)
and then calls `virt-install`:

```bash
virsh vol-create-as default vde.qcow2 4G --format qcow2

virt-install \
  --name vde --memory 2048 --vcpus 2 --cpu host-passthrough \
  --disk path=/var/lib/libvirt/images/vde.qcow2,bus=virtio,format=qcow2 \
  --cdrom ~/iso/alpine-virt-3.24.2-x86_64.iso \
  --os-variant alpinelinux3.19 \
  --graphics none --console pty,target_type=serial --noautoconsole --noreboot \
  --network bridge=br0,model=virtio \
  --network type=direct,source=vde0,source_mode=bridge,model=virtio \
  --memorybacking access.mode=shared,source.type=memfd \
  --filesystem driver.type=virtiofs,source.dir=/srv/share/ftp,target.dir=hostftp
```

Three details in there are worth understanding:

**`--memorybacking access.mode=shared,source.type=memfd`** is mandatory as soon
as you use virtiofs. Without it the domain refuses to start, with an error
about shared memory that does not obviously point at the filesystem you added.

**`type=direct,source=vde0,source_mode=bridge`** attaches the second card to
the TAP device with macvtap. Note what this means: the appliance reaches the
VDE segment *through the TAP*, not through the socket. Two macvtap interfaces
on the same TAP can also talk to each other directly in the kernel, bypassing
the switch — so if you test the setup by attaching a second libvirt VM the same
way, you are not actually testing the switch. Use a real VDE client for that
(see [09 · Connecting clients](09-clients.md)).

**`--graphics none --console pty`** gives you a serial console. `virsh console
vde` gets you a login prompt even when networking is completely broken, which
is exactly when you need it.

## Check it

```bash
virsh list --all
virsh dumpxml vde | grep -E 'source (bridge|dev)=|target.dir|memfd'
```

You should see the domain running, both network sources, and your virtiofs
tags.

## If it went wrong

**`TAP device 'vde0' does not exist`** — run
[`./scripts/host/vde-switch.sh install`](02-host-vde-switch.md) first, or set
`VDE_TAP=""` to build a single-NIC appliance.

**`virtiofs source is not a directory`** — create the host directory first.
libvirt will not create it for you.

**Domain fails to start with a memory error** — you added a virtiofs share
without the shared memory backing. The script always adds both; if you built
the XML by hand, that is the missing piece.

**`Cannot access storage file`** — the ISO or disk is somewhere libvirt's
AppArmor profile does not allow. Putting the ISO under your home directory or
`/var/lib/libvirt/images` avoids this.

Next: [04 · Installing Alpine](04-install-alpine.md)
