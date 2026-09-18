# 11 · Troubleshooting

## Start here

Four commands, in this order. The first one that misbehaves tells you which
section to read.

```sh
ssh root@192.168.1.50                      # 1. can you get in at all
rc-status default                             # 2. is everything running
netstat -lntu | grep -E ':(21|53|139|445|515|548|631|2002) '   # 3. listening
ufw status verbose                            # 4. and allowed
```

Everything in `rc-status` should say `started`. Nothing should say `crashed`
except netatalk before you have applied the pidfile fix
([chapter 06](06-file-sharing.md)).

## Symptom index

| Symptom | Section |
|---|---|
| Cannot SSH in after reinstalling | [Host key changed](#host-key-changed) |
| Client gets no address | [No DHCP](#no-dhcp) |
| Client has an address, no Internet | [NAT is missing](#nat-is-missing) |
| A name that should not exist resolves to some ad page | [DNS leaks](#dns-leaks) |
| Windows 98 cannot see the shares | [SMB1](#windows-98-cannot-see-the-shares) |
| Mac OS 9 error −50 when copying | [CNID](#mac-os-9-error-50) |
| `netatalk` says crashed but AFP works | [The pidfile bug](#netatalk-says-crashed) |
| Port 631 refused from your desktop | [That is correct](#port-631-refused) |
| Printing produces no PDF | [Printing](#printing-produces-no-pdf) |
| Emulator cannot join the switch | [VDE](#emulator-cannot-join-the-switch) |
| Everything worked, then stopped after `apk upgrade` | [After an upgrade](#after-an-upgrade) |

---

## Host key changed

```
@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@
```

You reinstalled the appliance, so it generated a new SSH host key. Expected,
not an attack:

```bash
ssh-keygen -R 192.168.1.50
ssh-keygen -R vde
```

## No DHCP

```sh
rc-service dnsmasq status
dnsmasq --test                    # syntax check, names the bad line
tail -f /var/log/messages         # watch while the client boots
```

You should see `DHCPDISCOVER` / `DHCPOFFER` lines appear. If nothing appears at
all, the client's packets are not arriving:

* is the isolated interface up and holding `10.1.0.1`? `ip -o -4 addr show eth1`
* on a VM: is the client really on the same segment? `vdeterm /tmp/vde0.mgmt`,
  then `port/allprint` — the packet counters tell you whether anything is
  arriving at the switch
* `interface=eth1` in `/etc/dnsmasq.conf` must name an interface that exists

Current leases:

```sh
cat /var/lib/misc/dnsmasq.leases
```

## NAT is missing

The classic failure: DHCP works, DNS works, and there is no Internet.

```sh
iptables -t nat -S POSTROUTING
```

If there is no `MASQUERADE` line, the rule is not loaded. Check that
`/etc/ufw/before.rules` still begins with the NAT block, then:

```sh
ufw disable && ufw --force enable
iptables -t nat -S POSTROUTING | grep MASQ
```

The commonest cause is writing the NAT block *before* running `ufw reset`,
which restores the stock rules file and throws your block away. Always reset
first. Re-running `./10-router.sh` does it in the right order.

Also check:

```sh
sysctl -n net.ipv4.ip_forward     # must be 1
ufw status verbose | head -4      # "Default: ... allow (routed)"
```

## DNS leaks

```sh
nslookup nosuchhost.home.net 10.1.0.1
```

This **must** say NXDOMAIN. If it returns an address, your internal domain is
being forwarded to the Internet, and some resolver upstream is answering
unknown names with a placeholder. Add to `/etc/dnsmasq.conf`:

```
domain=home.net
expand-hosts
local=/home.net/
```

and restart dnsmasq.

## Windows 98 cannot see the shares

```sh
testparm -s | grep -E 'min protocol|ntlm auth|guest'
netstat -lnt | grep -E ':(139|445) '
```

You need all three of:

```
server min protocol = NT1
ntlm auth = ntlmv1-permitted
map to guest = Bad User
```

If `smbd` is listening on `0.0.0.0` rather than `10.1.0.1`, you have
`interfaces = ...` without `bind interfaces only = yes`. Fix that — it is a
real exposure, not cosmetic.

Try the address bar (`\\10.1.0.1\share`) before blaming anything: Network
Neighbourhood depends on a browse-master election that can take minutes.

## Mac OS 9 error −50

The CNID index cannot be maintained where it currently lives.

```sh
grep dbpath /etc/afp.conf
mount | grep netatalk
```

`vol dbpath` must point at the appliance's own disk, not at a virtiofs mount or
a network filesystem, and `/etc/afp.conf` must have `ea = none` and
`appledouble = v2`.

To rebuild an index that has already gone wrong:

```sh
rc-service netatalk stop
rm -rf /var/lib/netatalk/cnid/*/*
rc-service netatalk start
```

Your files are untouched; only the index is discarded and rebuilt.

## netatalk says crashed

```sh
rc-service netatalk status      # crashed
netstat -lnt | grep 548         # ...but it is listening
```

Alpine's `netatalk-openrc` sets `pidfile=/run/lock`, which is a directory.

```sh
sed -i 's|^pidfile=/run/lock$|pidfile=/run/lock/netatalk|' /etc/init.d/netatalk
rc-service netatalk restart
```

## Port 631 refused

From your desktop on the uplink side:

```
curl: (7) Failed to connect to 192.168.1.50 port 631: Connection refused
```

**That is correct.** CUPS is bound to the isolated address only:

```sh
grep ^Listen /etc/cups/cupsd.conf
# Listen 10.1.0.1:631
```

Check it from the isolated side, or over SSH with `lpstat -t`. The same applies
to Samba, LPD and NetDrive: from the uplink, only SSH — and FTP if you set
`ADMIN_HOST` — is meant to answer.

## Printing produces no PDF

```sh
lpstat -t
tail -40 /var/log/cups/error_log
ls -l /mnt/spool
```

In order of likelihood:

1. The cups-pdf backend is group- or world-writable and CUPS refuses to run it.
   `chmod 0700 /usr/lib/cups/backend/cups-pdf`
2. `Out` in `/etc/cups/cups-pdf.conf` points somewhere that does not exist or
   is not writable by the `AnonUser`.
3. The queue is stopped. `cupsenable PDF && cupsaccept PDF`
4. The PDF is there but you cannot read it over the shares — the
   `PostProcessing` script did not run. Files should be mode `0664` and owned
   by the share user.

## Emulator cannot join the switch

```bash
./scripts/host/vde-switch.sh status
vdeterm /tmp/vde0.mgmt
vde$ port/allprint
```

* QEMU built without VDE support: `qemu-system-x86_64 -netdev help | grep vde`
* Socket permissions: `--mode 660` only lets your own user and group in
* The packet counters in `port/allprint` do not move → the client is not
  actually attached to the switch. If it is a libvirt VM using
  `type=direct` on the TAP, that is expected — see
  [chapter 09](09-clients.md).

## After an upgrade

`apk upgrade` can replace files this guide edited. The two that come back are:

* `/etc/init.d/netatalk` — the pidfile bug returns
* occasionally `/etc/cups/cupsd.conf`, saved as `.apk-new` alongside

Re-running the setup scripts is safe and fixes both:

```sh
cd /root/setup && ./install-all.sh
```

Everything in them is written to be idempotent.

## Collecting information before asking for help

```sh
{
  echo "=== release ==="; cat /etc/alpine-release
  echo "=== services ==="; rc-status default
  echo "=== interfaces ==="; ip -o addr; ip route
  echo "=== listening ==="; netstat -lntu
  echo "=== firewall ==="; ufw status verbose; iptables -t nat -S
  echo "=== dnsmasq ==="; grep -v '^#' /etc/dnsmasq.conf | grep .
} > /tmp/report.txt
```

Then read `/tmp/report.txt`, or attach it to an issue. Check it for your own
addresses before posting it anywhere public.
