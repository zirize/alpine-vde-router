#!/bin/sh
# ---------------------------------------------------------------------------
# Turn this Alpine machine into a router for the isolated network:
#   * a static address on the isolated interface
#   * NAT out through the uplink
#   * DHCP and DNS for the machines on the isolated side
#
# Safe to run more than once.
# ---------------------------------------------------------------------------
. "$(dirname "$0")/_common.sh"

say "Checking the interfaces"
ip link show "$WAN_IF" >/dev/null 2>&1 || {
    echo "error: uplink interface '$WAN_IF' does not exist."
    echo "       Interfaces on this machine:"; ls /sys/class/net | sed 's/^/         /'
    echo "       Fix WAN_IF in config.sh."
    exit 1
}
ip link show "$LAN_IF" >/dev/null 2>&1 || {
    echo "error: isolated interface '$LAN_IF' does not exist."
    echo "       Interfaces on this machine:"; ls /sys/class/net | sed 's/^/         /'
    echo "       On a VM, add a second network card. On a physical server,"
    echo "       set LAN_IF in config.sh to the port you want to serve."
    exit 1
}
info "uplink   $WAN_IF"
info "isolated $LAN_IF -> $LAN_ADDR/$LAN_NETMASK"

say "Installing packages"
apk_add dnsmasq ufw iptables

say "Making sure the clock is right"
# A router with the wrong time breaks TLS, SMB authentication and log reading.
# Note: some widely copied Alpine answer files use NTPOPTS="-c chrony", which
# is not valid - setup-ntp takes the daemon name on its own - so the installer
# can silently leave a machine with no time synchronisation at all.
apk_add chrony
svc chronyd || warn "chronyd did not start; check 'rc-service chronyd status'"
info "$(date)"

say "Giving $LAN_IF its static address"
if ! grep -q "^iface $LAN_IF " /etc/network/interfaces; then
    cat >> /etc/network/interfaces <<IFEOF

auto $LAN_IF
iface $LAN_IF inet static
    address $LAN_ADDR
    netmask $LAN_NETMASK
IFEOF
    rc-service networking restart >/dev/null 2>&1 || true
fi
ip addr show "$LAN_IF" | grep -q "$LAN_ADDR" || ip addr add "$LAN_ADDR/24" dev "$LAN_IF" 2>/dev/null || true
ip link set "$LAN_IF" up

say "Turning on IP forwarding"
ensure_line "net.ipv4.ip_forward=1" /etc/sysctl.conf
sysctl -p /etc/sysctl.conf >/dev/null

say "Configuring the firewall and NAT"
# Order matters here. "ufw reset" restores the stock before.rules, so the NAT
# block has to be written AFTER the reset - do it the other way round and the
# masquerade rule silently disappears, DHCP and DNS keep working, and only
# Internet access from the isolated side is broken.
ufw --force reset >/dev/null 2>&1 || true

ensure_line "IPV6=no" /etc/ufw/ufw.conf
if ! grep -q "alpine-vde-router NAT" /etc/ufw/before.rules; then
    tmp=$(mktemp)
    {
        echo "# alpine-vde-router NAT rules"
        echo "*nat"
        echo ":POSTROUTING ACCEPT [0:0]"
        echo "-A POSTROUTING -s $LAN_CIDR -o $WAN_IF -j MASQUERADE"
        echo "COMMIT"
        echo
        cat /etc/ufw/before.rules
    } > "$tmp"
    mv "$tmp" /etc/ufw/before.rules
fi

ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null
ufw default allow routed   >/dev/null
# SSH from anywhere, everything else only from the isolated side.
ufw allow 22/tcp                >/dev/null
ufw allow in on "$LAN_IF" to any >/dev/null
if [ -n "${ADMIN_HOST:-}" ]; then
    # FTP from one trusted machine on the uplink side. Passive FTP needs the
    # data port range open too, which is why there are three rules and not one.
    ufw allow from "$ADMIN_HOST" to any port 20  proto tcp >/dev/null
    ufw allow from "$ADMIN_HOST" to any port 21  proto tcp >/dev/null
    ufw allow from "$ADMIN_HOST" to any port 10000:10100 proto tcp >/dev/null
    info "FTP also allowed from $ADMIN_HOST"
fi
yes | ufw enable >/dev/null 2>&1 || true
ufw logging off >/dev/null
svc ufw

# Verify rather than assume. This is the single most common way for the whole
# appliance to look healthy while the isolated machines have no Internet.
if iptables -t nat -S POSTROUTING 2>/dev/null | grep -q "MASQUERADE"; then
    info "NAT active: $LAN_CIDR -> $WAN_IF"
else
    echo
    echo "error: the masquerade rule is not loaded."
    echo "       Look for the block starting '# alpine-vde-router NAT rules'"
    echo "       at the top of /etc/ufw/before.rules, then run:"
    echo "           ufw disable && ufw --force enable"
    exit 1
fi

say "Configuring DHCP and DNS (dnsmasq)"
cat > /etc/dnsmasq.conf <<DNSEOF
# Written by alpine-vde-router. Edit /etc/dnsmasq.d/*.conf instead of this file.

# Never talk to anything except the isolated interface.
local-service
interface=$LAN_IF
bind-interfaces

# Forward everything else to the upstream resolver, out through the uplink.
server=$UPSTREAM_DNS@$WAN_IF

# Serve our own domain locally and never leak it upstream.
# Without these three lines a typo like "nosuchbox.$LAN_DOMAIN" is forwarded to
# the Internet, and an ISP that hijacks NXDOMAIN answers it with a junk address.
domain=$LAN_DOMAIN
expand-hosts
local=/$LAN_DOMAIN/

dhcp-range=$DHCP_FROM,$DHCP_TO,$DHCP_LEASE
dhcp-option=option:router,$LAN_ADDR
dhcp-option=option:dns-server,$LAN_ADDR

# Per-machine settings live here, one file per machine.
conf-dir=/etc/dnsmasq.d/,*.conf
DNSEOF
mkdir -p /etc/dnsmasq.d

say "Registering our own names in /etc/hosts"
sed -i "/# alpine-vde-router names/d" /etc/hosts
sed -i "/[[:space:]]gw\.$LAN_DOMAIN/d" /etc/hosts
printf '%s\tgw ns ftp samba spool %s # alpine-vde-router names\n' \
       "$LAN_ADDR" "$HOSTNAME" >> /etc/hosts
svc dnsmasq

say "Done"
info "Gateway     $LAN_ADDR"
info "DHCP pool   $DHCP_FROM - $DHCP_TO"
info "DNS domain  $LAN_DOMAIN  (gw.$LAN_DOMAIN, ftp.$LAN_DOMAIN, ...)"
echo
info "Check it:  rc-service dnsmasq status ; ufw status verbose"
