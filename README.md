# alpine-vde-router

A small Alpine Linux appliance that gives obsolete computers a network they can
actually use: **DHCP, DNS, NAT, FTP, SMB1, AppleTalk-era AFP, a PDF printer and
an mTCP NetDrive disk server** — all with guest access, because a 1996 machine
has no idea what your password policy is.

It runs on a virtual machine or on a physical box. If you use it as a VM, an
optional [VDE](docs/02-host-vde-switch.md) switch lets emulators (QEMU, 86Box,
PCem…) plug in with ordinary user privileges — no root, no bridge configuration.

```
                Internet
                    │
          your existing router
                    │
        ┌───────────┴────────────┐
        │  uplink (eth0)         │
        │                        │
        │   alpine-vde-router    │   DHCP · DNS · NAT
        │                        │   FTP · SMB · AFP
        │  isolated (eth1)       │   IPP/LPD → PDF
        └───────────┬────────────┘   NetDrive
                    │  10.1.0.0/24
    ┌───────────┬───┴────┬───────────┬──────────┐
  Win98       WinXP   Mac OS 9      DOS      anything
```

Everything on the isolated side reaches the Internet through NAT, resolves
names, mounts the same shared folder over three different protocols, and prints
to a queue that writes PDF files you can pick up again from any of them.

---

## Why you might want this

Old operating systems cannot talk to a modern network. SMB1 is disabled
everywhere, AppleTalk is gone, no browser from 1999 can complete a TLS
handshake, and plugging a Windows 98 machine straight onto your LAN is a bad
idea anyway. This appliance gives those machines a network of their own, with
services they understand, and one carefully controlled door to the outside.

It is equally useful as a plain "retro lab in a box" on real hardware: an old
ThinkPad with two network ports will do.

## What you need

* A machine to run it on — a VM with 512 MB of RAM is enough, or any x86-64 box
* **Two network interfaces**: one facing your existing network, one facing the
  old machines. (On a VM, the second one can be virtual.)
* About 2 GB of disk
* An [Alpine Linux "Virtual" or "Standard" ISO](https://alpinelinux.org/downloads/)

## Quick start (virtual machine)

```bash
git clone https://github.com/zirize/alpine-vde-router
cd alpine-vde-router
cp config.example.sh config.sh
nano config.sh                       # addresses, shares, what to install

./scripts/host/vde-switch.sh install # optional: VDE switch for emulators
./scripts/host/create-vm.sh          # define the VM
./scripts/host/install-alpine.py     # unattended Alpine install
./scripts/host/push-scripts.sh       # copy the setup scripts over

ssh root@<the address you set> 'cd /root/setup && ./install-all.sh'
```

That is the whole thing. Roughly fifteen minutes, most of it waiting for
packages to download.

If you would rather understand each step than run a script — which is the point
of this repository — every chapter below explains what it does and gives you
the commands to paste by hand. **The scripts and the documentation are the same
commands.** Nothing happens off-screen.

## Documentation

| | |
|---|---|
| [01 · Overview](docs/01-overview.md) | How the pieces fit, and what to decide before you start |
| [02 · The VDE switch](docs/02-host-vde-switch.md) | Host side. Only for emulators. Skip on real hardware |
| [03 · Creating the VM](docs/03-create-the-vm.md) | libvirt domain, two NICs, shared folders |
| [04 · Installing Alpine](docs/04-install-alpine.md) | Unattended, or by hand |
| [05 · Router](docs/05-router.md) | NAT, DHCP, DNS, firewall |
| [06 · File sharing](docs/06-file-sharing.md) | FTP, SMB1 for Windows 9x, AFP for classic Mac OS |
| [07 · Printing](docs/07-printing.md) | IPP and LPD, printed output as PDF |
| [08 · NetDrive](docs/08-netdrive.md) | A network hard disk for DOS |
| [09 · Connecting clients](docs/09-clients.md) | Windows 98/XP, Mac OS 9, DOS, QEMU, 86Box |
| [10 · On a physical server](docs/10-physical-server.md) | What changes on real hardware |
| [11 · Troubleshooting](docs/11-troubleshooting.md) | Symptoms, causes, fixes |

## Status

Built and verified end to end on Alpine 3.24.2 with libvirt/QEMU on Ubuntu.
Every command in the documentation was run on a machine installed from scratch
by following this repository.

## License

MIT for the scripts and documentation. The mTCP NetDrive server is a separate
work by Michael Brutman and is **not** included here — see
[docs/08-netdrive.md](docs/08-netdrive.md).
