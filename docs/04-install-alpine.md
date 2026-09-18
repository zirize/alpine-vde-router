# 4 · Installing Alpine

## What this does

Installs Alpine Linux onto the appliance and leaves you with a machine you can
reach over SSH with a key. Nothing about the appliance's job is set up yet —
that starts in the next chapter.

Alpine is a good fit here: the whole system is about 300 MB installed, it boots
in a couple of seconds, and it uses OpenRC, which is small enough to read.

There are two paths. **A** is one command and is what the rest of this guide
assumes. **B** is the same thing done by hand, for a physical server or if you
simply want to see it happen.

---

## A · Unattended (virtual machine)

```bash
./scripts/host/install-alpine.py
```

It drives the serial console, echoing everything, and takes about five minutes.
In order it:

1. logs into the live system
2. brings the uplink up and **checks that the package mirror is reachable** —
   this is deliberately done before anything is written to disk, so a wrong
   address or a wrong bridge fails in ten seconds instead of five minutes
3. runs `setup-alpine` from a generated answer file
4. writes the final network configuration and your SSH public keys onto the new
   disk
5. powers off, ejects the ISO, boots from disk

When it finishes it prints the address to connect to.

> **The answer file.** `setup-alpine -f` reads a file of shell variables. The
> one this script generates is worth a look if you want to adapt it:
>
> ```sh
> KEYMAPOPTS="us us"
> HOSTNAMEOPTS="-n vde"
> INTERFACESOPTS="auto lo
> iface lo inet loopback
>
> auto eth0
> iface eth0 inet static
>     address 192.168.1.50
>     netmask 255.255.255.0
>     gateway 192.168.1.1
> "
> DNSOPTS="-d home.net 192.168.1.1"
> TIMEZONEOPTS="-z Europe/London"
> PROXYOPTS="none"
> APKREPOSOPTS="http://dl-cdn.alpinelinux.org/alpine/v3.24/main http://dl-cdn.alpinelinux.org/alpine/v3.24/community"
> USEROPTS="none"
> SSHDOPTS="-c openssh"
> NTPOPTS="chrony"
> DISKOPTS="-m sys /dev/vda"
> ```
>
> Two things in there are commonly got wrong, and both fail *silently*:
>
> * **`INTERFACESOPTS` with real newlines**, not `\n` escapes. Answer files are
>   sourced by the shell, so a quoted multi-line value is correct and always
>   works. Whether `\n` is expanded depends on the Alpine release — get it
>   wrong and the installed machine boots with no IP address at all.
> * **`NTPOPTS="chrony"`, not `NTPOPTS="-c chrony"`.** `setup-ntp` takes the
>   daemon name on its own. The `-c` form is copied around widely, does
>   nothing, and leaves the machine with no time synchronisation — which you
>   discover months later when SMB authentication or a TLS handshake fails.

---

## B · By hand

Use this on a physical server, or when you want to watch.

Boot the Alpine ISO. At `localhost login:` type `root` — there is no password
on the live system. Then:

```
setup-alpine
```

Answer as follows. Defaults are in brackets; pressing Enter takes them.

| Question | Answer |
|---|---|
| Keyboard layout | `us`, then `us` again |
| Hostname | `vde` |
| Which interface to initialize | `eth0` — **only the uplink** |
| Ip address for eth0 | your fixed address, or `dhcp` |
| Netmask / Gateway | as for your network |
| Any other interfaces | **`done`** — leave the isolated one alone for now |
| DNS domain name | `home.net` |
| DNS nameserver | your router's address |
| Root password | choose one |
| Timezone | yours |
| HTTP/FTP proxy | `none` |
| NTP client | `chrony` |
| APK mirror | pick a nearby one, or `f` for fastest |
| Setup a user | `no` |
| SSH server | `openssh` |
| Which disk to use | `sda` (or `vda` on a VM) |
| How to use it | `sys` |
| Erase the disk? | `y` |

Leave the isolated interface unconfigured. Chapter 05 sets it up, and doing it
now only gives `setup-alpine` a chance to put a default route on the wrong card.

When it finishes:

```
poweroff
```

Remove the installation media and boot from disk.

### Install your SSH key

From your desktop:

```bash
ssh-keygen -t ed25519                     # if you do not have a key yet
ssh-copy-id root@192.168.1.50
```

Then check that `ssh root@192.168.1.50` works without asking for a password.

---

## Check it

```bash
ssh root@192.168.1.50
```

On the appliance:

```
vde:~# cat /etc/alpine-release
3.24.2
vde:~# ip -o -4 addr
2: eth0    inet 192.168.1.50/24 scope global eth0
vde:~# ls /sys/class/net
eth0
eth1
lo
vde:~# ping -c2 dl-cdn.alpinelinux.org
```

Both interfaces must be present. `eth1` will be down and without an address —
that is expected.

## If it went wrong

**`REMOTE HOST IDENTIFICATION HAS CHANGED!`** — you reinstalled, so the machine
has a new host key. This is normal, not an attack. Forget the old one:

```bash
ssh-keygen -R 192.168.1.50
ssh-keygen -R vde
```

**No IP address after installation.** Almost always `INTERFACESOPTS` with
unexpanded `\n` escapes (see above), or a bridge that is not really connected
to your LAN. Get in with `virsh console vde`, log in on the serial console and
look at `/etc/network/interfaces`.

**`ERROR: unable to select packages`** during the install. The mirror is
unreachable or the branch is wrong. `ALPINE_BRANCH` in `config.sh` must match
the ISO you booted — a v3.24 ISO cannot install from a v3.21 repository.

**Installer hangs right after "Installation is complete".** If you wrote your
own automation: `setup-alpine` changes the hostname, so the shell prompt
changes from `localhost:~#` to `vde:~#` halfway through. Match on a prompt you
set yourself, not on the default one.

**`ip -br link` says "Usage: ip ..."** — Alpine's `ip` is BusyBox's, which has
no `-br`. Use `ls /sys/class/net` or plain `ip addr`.

Next: [05 · Router](05-router.md)
