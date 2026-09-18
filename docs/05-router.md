# 5 · Router

## What this does

Turns the machine into the router for the isolated network:

* gives the isolated interface a fixed address (`10.1.0.1`)
* enables IP forwarding and masquerades outbound traffic through the uplink
* hands out addresses with DHCP, and answers DNS
* closes the uplink side down to SSH (plus optional FTP from one address)

After this chapter an old machine set to "obtain an address automatically" can
browse the Internet.

## Get the scripts onto the appliance

From your desktop:

```bash
./scripts/host/push-scripts.sh
```

That copies `config.sh` and the guest scripts to `/root/setup`. On a physical
server just clone the repository on the machine itself, or `scp` the files.

## Do it

```bash
ssh root@192.168.1.50
cd /root/setup
./10-router.sh
```

```
==> Checking the interfaces
    uplink   eth0
    isolated eth1 -> 10.1.0.1/255.255.255.0
==> Installing packages
==> Making sure the clock is right
    Fri Sep 18 14:30:16 KST 2026
==> Giving eth1 its static address
==> Turning on IP forwarding
==> Configuring the firewall and NAT
    FTP also allowed from 192.168.1.10
    NAT active: 10.1.0.0/24 -> eth0
==> Configuring DHCP and DNS (dnsmasq)
==> Registering our own names in /etc/hosts
==> Done
    Gateway     10.1.0.1
    DHCP pool   10.1.0.20 - 10.1.0.50
    DNS domain  home.net  (gw.home.net, ftp.home.net, ...)
```

### By hand

```sh
apk add dnsmasq ufw iptables chrony
rc-update add chronyd default && rc-service chronyd start
```

**The isolated interface.** Append to `/etc/network/interfaces`:

```
auto eth1
iface eth1 inet static
    address 10.1.0.1
    netmask 255.255.255.0
```

Note there is **no gateway line**. Only the uplink has a default route; a
second one here is a classic way to break all outbound traffic.

```sh
rc-service networking restart
```

**Forwarding:**

```sh
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
```

**Firewall and NAT.** Reset first, then add the NAT block, then enable — in
that order:

```sh
ufw --force reset
```

> **This order is not optional.** `ufw reset` restores the stock
> `before.rules`. Write your NAT block first and the reset silently throws it
> away. The symptom is nasty because it looks like everything works: DHCP
> hands out addresses, DNS resolves, and only Internet access from the isolated
> side is dead.

Now put the NAT rules at the **top** of `/etc/ufw/before.rules`, above the
`*filter` section:

```
# alpine-vde-router NAT rules
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.1.0.0/24 -o eth0 -j MASQUERADE
COMMIT
```

Then the policy:

```sh
echo 'IPV6=no' >> /etc/ufw/ufw.conf

ufw default deny incoming
ufw default allow outgoing
ufw default allow routed          # lets traffic pass between the two sides

ufw allow 22/tcp                  # SSH, from anywhere
ufw allow in on eth1 to any       # everything, but only from the isolated side

# optional: FTP from one machine on the uplink side
ufw allow from 192.168.1.10 to any port 20 proto tcp
ufw allow from 192.168.1.10 to any port 21 proto tcp
ufw allow from 192.168.1.10 to any port 10000:10100 proto tcp

ufw --force enable
ufw logging off
rc-update add ufw default
```

**DHCP and DNS.** Write `/etc/dnsmasq.conf`:

```
local-service
interface=eth1
bind-interfaces

server=192.168.1.1@eth0

domain=home.net
expand-hosts
local=/home.net/

dhcp-range=10.1.0.20,10.1.0.50,12h
dhcp-option=option:router,10.1.0.1
dhcp-option=option:dns-server,10.1.0.1

conf-dir=/etc/dnsmasq.d/,*.conf
```

> **Those three lines in the middle earn their keep.** Without `domain=`,
> `expand-hosts` and `local=/home.net/`, a query for a name that does not exist
> inside your domain — a typo like `nosuchbox.home.net` — is forwarded to the
> Internet. Plenty of ISPs answer any unknown name with the address of an
> advertising page, so instead of "no such host" your old machine cheerfully
> connects to a stranger. With those lines the appliance answers NXDOMAIN
> itself and nothing leaks.

Register your own names in `/etc/hosts`:

```
10.1.0.1	gw ns ftp samba spool vde
```

`expand-hosts` turns each of those into `gw.home.net`, `ftp.home.net` and so on.

```sh
rc-service dnsmasq restart
rc-update add dnsmasq default
```

## Check it

On the appliance:

```sh
ip -o -4 addr show eth1                     # 10.1.0.1/24
sysctl -n net.ipv4.ip_forward               # 1
iptables -t nat -S POSTROUTING | grep MASQ  # the rule must be there
ufw status verbose
rc-service dnsmasq status
```

Internal names resolve, and names that do not exist say so:

```sh
nslookup gw.home.net 10.1.0.1          # -> 10.1.0.1
nslookup nosuchhost.home.net 10.1.0.1  # -> NXDOMAIN, NOT an address
```

From the uplink side, almost everything must be closed:

```bash
for p in 21 22 53 139 445 631; do
  nc -z -w2 192.168.1.50 $p && echo "tcp/$p OPEN" || echo "tcp/$p closed"
done
```

Only 22 — and 21, if you set `ADMIN_HOST` — should be open. Anything else open
means the firewall is not doing its job.

The real test is a client. Boot any machine on the isolated network; it should
get an address in the pool, resolve names and reach the Internet. If you have
no client yet, see [09 · Connecting clients](09-clients.md), which includes a
tiny test tool that joins the VDE switch and checks all of it in one command.

## If it went wrong

**Clients get an address but have no Internet.** The masquerade rule is
missing. Check `iptables -t nat -S POSTROUTING`. If it is empty, the `ufw
reset` ordering above is why. Fix `/etc/ufw/before.rules`, then
`ufw disable && ufw --force enable`.

**No DHCP at all.** `rc-service dnsmasq status`. If it will not start,
`dnsmasq --test` prints the offending line. The usual cause is `interface=eth1`
naming an interface that does not exist or is down.

**A name that should not exist resolves to some advertising page.** The three
`domain` / `expand-hosts` / `local=` lines are missing.

**DNS works but only for external names.** `expand-hosts` is missing, so
`/etc/hosts` entries are only known by their short name.

**The appliance itself lost Internet access after adding eth1.** You gave the
isolated interface a gateway line. Remove it and restart networking.

Next: [06 · File sharing](06-file-sharing.md)
