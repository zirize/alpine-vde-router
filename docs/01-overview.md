# 1 · Overview

## What this builds

One small Linux machine with two network interfaces:

| | |
|---|---|
| **uplink** | faces the network you already have. Gets Internet access from your ordinary router. |
| **isolated** | faces the old machines. Nothing from the outside can reach in. |

On the isolated side the appliance is the router (`10.1.0.1` by default), the
DHCP server, the DNS server, the file server and the print server. Old machines
need no configuration at all beyond "obtain an address automatically".

## The services, and who needs them

| Service | Port | Used by |
|---|---|---|
| DHCP | 67/udp | everything |
| DNS | 53 | everything |
| NAT | — | everything that wants the Internet |
| FTP (anonymous) | 21 + 10000–10100 | DOS, Windows, anything scriptable |
| SMB / CIFS (SMB1) | 139, 445 | Windows for Workgroups 3.11, 95, 98, ME, NT, 2000, XP |
| AFP | 548 | Mac OS 8, 9, and OS X |
| IPP printing → PDF | 631 | Windows 98 and later, Linux |
| LPD printing → PDF | 515 | classic Mac OS, and anything with only LPR |
| NetDrive | 2002/udp | DOS, as a network hard disk |

All file services are **guest access with no password**, mapped onto one Unix
account. This is a deliberate choice: SMB1 with NTLMv1 is the only dialect
Windows 98 speaks, and it is not a protocol you should expose to anything. The
whole design assumes the isolated network is a cul-de-sac.

> **Read this once.** The isolated network is not a DMZ and not a guest
> network. It is a network where the security model is "nothing can get in".
> The firewall on the appliance enforces that: the uplink side accepts SSH, and
> optionally FTP from one address you nominate, and nothing else. Do not
> port-forward anything to it from your real router.

## Addresses used in these examples

Every command in this documentation uses the same made-up network. **Substitute
your own** — the only one you are likely to keep as-is is the isolated side.

| | Example | What it is |
|---|---|---|
| `192.168.1.0/24` | | your existing home or office network |
| | `192.168.1.1` | your existing router, and the upstream DNS resolver |
| | `192.168.1.10` | the desktop you are typing on |
| | `192.168.1.50` | the appliance's uplink address — pick one outside your router's DHCP pool |
| `10.1.0.0/24` | | the isolated network the appliance creates |
| | `10.1.0.1` | the appliance, as seen by the old machines |
| | `10.1.0.20`–`10.1.0.50` | handed out by DHCP |

All of these are settings in `config.sh`. If `10.1.0.0/24` happens to collide
with something you already run, change `LAN_ADDR`, `LAN_CIDR`, `DHCP_FROM` and
`DHCP_TO` together.

## Decide these before you start

Open `config.example.sh` — every one of these is a variable in it.

**Addresses.** The appliance needs a fixed address on your existing network
(`WAN_ADDR`) that is outside your router's DHCP pool, and an address on the
isolated network (`LAN_ADDR`, `10.1.0.1` by default). If `10.1.0.0/24` clashes
with something you already have, change `LAN_ADDR`, `LAN_CIDR`, `DHCP_FROM` and
`DHCP_TO` together.

**Upstream DNS** (`UPSTREAM_DNS`). Usually your router's address. The appliance
forwards anything it cannot answer itself to this resolver.

**Internal domain** (`LAN_DOMAIN`, `home.net` by default). Names inside it are
answered locally and never sent upstream.

**Where the shared files live** (`SHARE_DIR` and friends). On a VM these are
usually folders on the host, passed in with virtiofs. On real hardware they are
just directories, or a mounted disk.

**Which services you want.** Set `ENABLE_FTP`, `ENABLE_SAMBA`, `ENABLE_AFP`,
`ENABLE_PRINTING`, `ENABLE_NETDRIVE` to `0` to skip any of them. A machine that
only needs to be a router is a two-minute install.

## Two ways to run it

### As a virtual machine

The usual case, and what the host-side scripts automate. You get an extra
benefit: emulators can plug into a
[VDE switch](02-host-vde-switch.md) — a virtual ethernet segment that runs in
user space. QEMU, 86Box and PCem can all join it without root and without
touching your host's network configuration.

Chapters 02 → 03 → 04 → 05 …

### On a physical server

Everything from chapter 05 onward is identical. You install Alpine yourself,
skip the VDE and virtiofs chapters, and point the share paths at real
directories. See [10 · On a physical server](10-physical-server.md).

Chapters 04 → 05 → … plus [10](10-physical-server.md).

## How the documentation is arranged

Every chapter has the same shape:

1. **What this does** — in plain words
2. **Do it** — either one script, or the individual commands to paste
3. **Check it** — commands that prove it worked, with the output you should see
4. **If it went wrong** — the failures people actually hit

The scripts in `scripts/` run exactly the commands the chapters show. Reading
one teaches you the other.

Next: [02 · The VDE switch](02-host-vde-switch.md) for a VM, or
[04 · Installing Alpine](04-install-alpine.md) for real hardware.
