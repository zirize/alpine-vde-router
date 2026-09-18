# 2 · The VDE switch (host side)

**Skip this chapter** if you are installing on a physical server, or if your
old machines are real computers with real network cards. You only need it to
let *emulators* share a network segment.

## What this does

[VDE](https://github.com/virtualsquare/vde-2) (Virtual Distributed Ethernet) is
an ethernet switch that runs as an ordinary user-space program. Emulators
connect to it through a unix socket. Everything plugged into the same socket is
on the same ethernet segment, exactly as if you had run patch cables between
them.

Compared with the usual alternatives:

| | needs root | needs host network changes | works with 86Box/PCem |
|---|---|---|---|
| Linux bridge + TAP per VM | yes | yes | awkward |
| QEMU user-mode (`-netdev user`) | no | no | no, and no inter-guest traffic |
| **VDE socket** | **no** | **one TAP device, once** | **yes** |

One TAP device is still needed, because the appliance VM joins the segment
through libvirt rather than through the socket. Creating a TAP device is the
single step in this whole guide that needs `sudo`.

```
  emulators ───┐
  (QEMU, 86Box)│  unix socket /tmp/vde0/ctl
               ▼
         ┌───────────┐      TAP device        ┌──────────────┐
         │ vde_switch│◄────── vde0 ──────────►│ appliance VM │
         └───────────┘                        │   (eth1)     │
                                              └──────────────┘
```

## Before you start

Install the VDE tools:

```bash
# Debian / Ubuntu
sudo apt install vde2 socat

# Fedora
sudo dnf install vde2 socat

# Arch
sudo pacman -S vde2 socat
```

## Do it

```bash
cd alpine-vde-router
cp config.example.sh config.sh     # if you have not already
./scripts/host/vde-switch.sh install
```

That asks for your password once, and then:

* writes `/etc/vde2/vde.conf` with the TAP name and your username
* installs `/etc/vde2/create-tap.sh` and a systemd unit, so the TAP device
  comes back after a reboot
* installs a *user* systemd unit that starts the switch when you log in

### By hand

If you prefer to do it yourself, this is all it is:

```bash
# 1. the TAP device, owned by you so the switch can open it without root
sudo ip tuntap add dev vde0 mode tap user "$(id -un)"
sudo ip link set vde0 up

# 2. the switch
vde_switch --daemon --numports 32 \
           --sock /tmp/vde0   --mode 660 \
           --mgmt /tmp/vde0.mgmt --mgmtmode 660 \
           --tap vde0 \
           --pidfile "$XDG_RUNTIME_DIR/vde0.pid"
```

> **A trap worth knowing about.** Many published versions of this setup
> generate `create-tap.sh` with an *unquoted* heredoc:
>
> ```bash
> cat << EOF | sudo tee /etc/vde2/create-tap.sh    # <-- WRONG
> ip tuntap add dev "$V_TAP" mode tap user "$V_USER"
> EOF
> ```
>
> The shell expands `$V_TAP` and `$V_USER` *while writing the file*, and since
> they are not set in that shell you install a script that runs
> `ip tuntap add dev "" mode tap user ""`. It fails silently and the TAP device
> never appears. Quote the delimiter — `<< 'EOF'` — or just copy the file with
> `install -m755`.

## Check it

```bash
./scripts/host/vde-switch.sh status
```

```
TAP    vde0: present
switch running, pid 404964, socket /tmp/vde0

Ports (each connected client takes one):
    Port 0001 untagged_vlan=0000 ACTIVE - Unnamed Allocatable
      -- endpoint ID 0007 module tuntap      : vde0
```

Port 1 is the TAP. Every emulator that connects takes another port. The
management socket is a small interactive console:

```bash
vdeterm /tmp/vde0.mgmt
```

```
vde$ port/allprint          # who is connected, and their packet counters
vde$ hash/print             # the MAC address table the switch has learned
vde$ help
```

This console is the single most useful debugging tool in the whole setup. If a
client says the network is dead, `port/allprint` tells you in one line whether
its packets are reaching the switch at all.

## If it went wrong

**`vde_switch: command not found`** — install the `vde2` package.

**`Could not open TAP device`** — the TAP device does not exist, or it belongs
to another user. Check with `ip -d link show vde0`; the line should end with
`user <your name>`.

**The switch is gone after a reboot** — the user unit starts at login, not at
boot. Either log in, or enable lingering: `sudo loginctl enable-linger $USER`.

**Emulator cannot connect** — check the socket permissions. `--mode 660` means
only your user and group can connect; use `--mode 666` if the emulator runs as
a different user (but then anyone on the machine can join the segment).

Next: [03 · Creating the VM](03-create-the-vm.md)
