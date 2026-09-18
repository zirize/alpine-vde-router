#!/bin/sh
# ---------------------------------------------------------------------------
# alpine-vde-router - site configuration
#
# Copy this file to config.sh and edit it, then every script in scripts/
# will pick your values up automatically:
#
#     cp config.example.sh config.sh
#     nano config.sh
#
# Every value has a sane default. If you are unsure, leave it alone.
# ---------------------------------------------------------------------------

# --- Identity -------------------------------------------------------------
# Hostname of the appliance.
HOSTNAME="vde"

# --- Uplink (the network that already has Internet access) ----------------
# The interface that faces your existing LAN / the Internet.
# On a VM this is usually eth0. On a physical server run `ip link` and look
# for the port with a cable in it.
WAN_IF="eth0"

# Address of the appliance on that network. Use "dhcp" to let your existing
# router assign one, or an address in CIDR-less form plus netmask/gateway.
WAN_MODE="static"              # "static" or "dhcp"
WAN_ADDR="192.168.1.50"
WAN_NETMASK="255.255.255.0"
WAN_GATEWAY="192.168.1.1"

# Upstream DNS resolver the appliance forwards queries to.
UPSTREAM_DNS="192.168.1.1"

# --- Isolated network (the network this appliance creates) ----------------
# The interface that faces the machines you want to serve.
# On a VM attached to a VDE switch this is eth1.
LAN_IF="eth1"
LAN_ADDR="10.1.0.1"
LAN_NETMASK="255.255.255.0"
LAN_CIDR="10.1.0.0/24"

# DHCP pool handed out on the isolated network.
DHCP_FROM="10.1.0.20"
DHCP_TO="10.1.0.50"
DHCP_LEASE="12h"

# Internal DNS domain. Names below are served locally and never leak upstream.
LAN_DOMAIN="home.net"

# --- Shared storage -------------------------------------------------------
# Root of the anonymous FTP tree. Everything else lives underneath it.
FTP_ROOT="/var/lib/ftp"
# Writable drop box, shared over FTP, SMB and AFP.
SHARE_DIR="/var/lib/ftp/uploads"
# Where printed PDFs land.
SPOOL_DIR="/mnt/spool"
# Where NetDrive disk images live.
NETDRV_DIR="/mnt/netdrv"

# Unix account that owns the shared files. Clients connect as guests and are
# mapped to this account, so you never hand out a password to a 1998 PC.
SHARE_USER="netdrv"
SHARE_UID="1000"

# One machine on the UPLINK side that is allowed to reach FTP as well, so you
# can drop files into the shares from your desktop without going through the
# isolated network. Leave empty to allow nobody. SSH is always allowed.
ADMIN_HOST=""

# --- Optional components (set to 0 to skip) -------------------------------
ENABLE_FTP=1
ENABLE_SAMBA=1
ENABLE_AFP=1
ENABLE_PRINTING=1
ENABLE_NETDRIVE=1

# ===========================================================================
# HOST SIDE - only needed if you run the appliance as a virtual machine.
# Skip this whole block when installing on a physical server.
# ===========================================================================

# Name of the libvirt domain.
VM_NAME="vde"
VM_RAM_MB="2048"           # 512 is enough for a router only; 2048 is comfortable
VM_VCPUS="2"
VM_DISK_GB="4"

# Alpine "Virtual" ISO. Download from https://alpinelinux.org/downloads/
ISO_PATH="$HOME/iso/alpine-virt-3.24.2-x86_64.iso"

# Bridge on the host that reaches your LAN / the Internet.
# Use "default" to fall back to libvirt's built-in NAT network instead.
HOST_BRIDGE="br0"

# TAP device that the VDE switch is attached to (see docs/01-host-vde.md).
# Leave empty to build a single-NIC appliance with no isolated network.
VDE_TAP="vde0"
VDE_SOCK="/tmp/vde0"

# virtiofs shares: "<host path>|<tag>|<guest mount point>|<ro|rw>"
# The tag is an arbitrary label; it must match between host and guest.
# Delete the lines you do not need.
VIRTIOFS_SHARES="
/srv/share/ftp|hostftp|/var/lib/ftp/uploads|rw
/srv/share/spool|hostspool|/mnt/spool|rw
/srv/share/netdrv|hostnetdrv|/mnt/netdrv|rw
"

# --- Alpine installation --------------------------------------------------
# Root password set during installation. Change it after the first login,
# or better: rely on the SSH keys below and disable password login.
ROOT_PASSWORD="alpine"
TIMEZONE="UTC"
KEYMAP="us us"
# Alpine release branch and mirror used by the installer.
ALPINE_BRANCH="v3.24"
APK_MIRROR="http://dl-cdn.alpinelinux.org/alpine"
# Public keys installed into /root/.ssh/authorized_keys (space separated).
SSH_PUBKEYS="$HOME/.ssh/id_ed25519.pub"
