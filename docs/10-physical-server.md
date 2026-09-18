# 10 · On a physical server

Everything from [chapter 05](05-router.md) onward is the same on real hardware.
This page lists only what differs.

## What you need

* Any x86-64 machine. A 2010 desktop or a thin client is plenty; the whole
  system idles at well under 100 MB of RAM.
* **Two network interfaces.** One goes to your existing network, the other to a
  switch that the old machines plug into. If the machine has only one port, a
  USB ethernet adapter works fine.
* A disk of any size. 2 GB is enough unless you plan to store files on it.

A small switch and a handful of cables between the appliance's second port and
your old computers is the whole physical build. Do **not** plug the second port
back into your main network — the whole design assumes that segment is a
cul-de-sac.

## Chapters you skip

| Chapter | Why |
|---|---|
| [02 · VDE switch](02-host-vde-switch.md) | VDE is for emulators. Real machines use real cables. |
| [03 · Creating the VM](03-create-the-vm.md) | There is no VM. |
| `05-virtiofs.sh` | There is no host to share folders from. Set `VIRTIOFS_SHARES=""`. |

## Installing

Follow **[04 · Installing Alpine, path B](04-install-alpine.md#b--by-hand)**.
Write the ISO to a USB stick:

```bash
# on your desktop - CHECK the device name first with lsblk
sudo dd if=alpine-standard-3.24.2-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Use the **standard** ISO rather than the *virtual* one. The virtual edition's
kernel omits most real hardware drivers.

During `setup-alpine`, configure only the uplink interface. Answer `done` when
it asks about further interfaces.

## Finding your interface names

Alpine names interfaces `eth0`, `eth1`, … in the order the kernel finds them,
which is not necessarily the order of the sockets on the back of the machine.

```sh
ls /sys/class/net
```

To work out which is which, unplug a cable and watch:

```sh
cat /sys/class/net/eth0/carrier      # 1 = cable connected, 0 = not
```

Or bring them up one at a time and see which gets a DHCP lease. Then set
`WAN_IF` and `LAN_IF` in `config.sh` accordingly. Getting them the wrong way
round is the single most common mistake on real hardware — you end up
masquerading your real LAN into a dead port, and nothing works in either
direction.

If you would rather use stable names, Alpine can do it:

```sh
apk add eudev
setup-devd udev
```

after which interfaces get names like `enp3s0` derived from their PCI slot.
Both names work; just put the right one in `config.sh`.

## Storage

On a VM the shares come from the host over virtiofs. Here they are just
directories, or a mounted disk:

```sh
# a whole second disk for the shares
mkfs.ext4 /dev/sdb1
mkdir -p /srv/share
echo '/dev/sdb1 /srv/share ext4 defaults 0 2' >> /etc/fstab
mount -a
mkdir -p /srv/share/uploads /srv/share/spool /srv/share/netdrv
```

and in `config.sh`:

```sh
FTP_ROOT="/srv/share"
SHARE_DIR="/srv/share/uploads"
SPOOL_DIR="/srv/share/spool"
NETDRV_DIR="/srv/share/netdrv"
VIRTIOFS_SHARES=""
```

Two things get easier on real hardware, and both come from having a normal
local filesystem:

* **netatalk** can keep its CNID index inside the share, because extended
  attributes and file locking actually work. The `vol dbpath` lines are then
  optional — though leaving them in does no harm, and keeps the configuration
  identical between a VM and a physical box.
* `ea = none` is no longer needed either, but again, harmless.

## Getting the scripts onto the machine

There is no host to push from:

```sh
apk add git
git clone https://github.com/YOURNAME/alpine-vde-router /root/setup
cd /root/setup
cp config.example.sh config.sh
vi config.sh
./scripts/guest/install-all.sh
```

## Things to add that a VM does not need

**Watchdog.** An appliance in a cupboard should reboot itself if it wedges:

```sh
apk add watchdog
rc-update add watchdog default
```

**Power loss.** Alpine's default `sys` install mounts everything read-write. If
the machine will be switched off at the wall, consider Alpine's diskless mode,
where the system runs from RAM and you commit changes deliberately with
`lbu commit`. That is a different installation style; the
[Alpine wiki](https://wiki.alpinelinux.org/wiki/Alpine_local_backup) covers it.

**Remote console.** You lose `virsh console`. Either keep a monitor and
keyboard attached, or enable the serial console on a real serial port by adding
`console=ttyS0,115200` to `default_kernel_opts` in
`/etc/update-extlinux.conf` and running `update-extlinux`.

Next: [11 · Troubleshooting](11-troubleshooting.md)
