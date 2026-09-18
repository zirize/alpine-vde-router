# 9 · Connecting clients

## Emulators

### QEMU

QEMU can join the VDE segment directly, as your own user:

```bash
qemu-system-i386 \
  -netdev vde,id=net0,sock=/tmp/vde0 \
  -device pcnet,netdev=net0 \
  ...
```

| Guest | Network card that works out of the box |
|---|---|
| MS-DOS, Windows 3.11, Windows 95/98 | `pcnet` (AMD PCnet, driver on the Win98 CD) |
| Windows XP and later | `virtio-net-pci` with drivers, else `rtl8139` |
| Mac OS 9 (qemu-system-ppc) | `sungem` |

> **Check your QEMU has VDE support first:**
>
> ```bash
> qemu-system-x86_64 -netdev help | grep vde
> ```
>
> If nothing comes back, your distribution built QEMU without `libvdeplug`.
> Debian and Ubuntu have shipped builds both ways. You then either build QEMU
> yourself with `--enable-vde`, or use a TAP device instead of the socket.

### 86Box

In the machine's `config` file, or through Settings → Network:

```ini
[Network]
net_01_card = novell_ne2k
net_01_net_type = vde
net_01_host_device = /tmp/vde0
```

### PCem, DOSBox-X, others

Anything that links `libvdeplug` takes the same socket path. Anything that does
not can use a TAP device on the host instead.

## Testing the switch itself

There is a small tool that joins the VDE switch as a raw client and checks
DHCP, ARP, DNS, ICMP and NAT in one run — useful because it needs no VM at all:

```bash
vdetester -n 2 -s /tmp/vde0
```

```
[2/6] DHCP Discovering...
  [OK] Assigned IP: 10.1.0.49
  [OK] Gateway IP: 10.1.0.1
  [OK] DNS IP: 10.1.0.1
  [3/6] [OK] Gateway MAC found.
[4/6] [DNS] Querying google.com via 10.1.0.1...
  [OK] DNS Response received!
[5/6] [ICMP] Pinging 8.8.8.8...
  [OK] ICMP Echo Reply received from 8.8.8.8!
[6/6] [NAT] Testing outbound sessions to 8.8.8.8:53 (TCP SYN / UDP DNS)...
  [RECV] TCP NAT Success! (SYN-ACK from 8.8.8.8:53, 2/2)
  [RECV] UDP NAT Success! (DNS reply from 8.8.8.8, 2/2)

[SUCCESS] VDE DHCP, DNS, ICMP & NAT Test Passed!
```

> **Do not test the switch with a second libvirt VM.** If you attach another VM
> to the TAP the same way the appliance is attached (`type=direct`), the two
> macvtap interfaces talk to each other directly inside the kernel and never
> reach `vde_switch`. Everything appears to work while the switch is doing
> nothing. Watch `port/allprint` in `vdeterm /tmp/vde0.mgmt`: if the packet
> counters do not move, your traffic is not going through the switch.

---

## Windows 98 SE

**Network.** Control Panel → Network → TCP/IP → "Obtain an IP address
automatically". Reboot. That is all — DHCP supplies the address, gateway and
DNS.

**File sharing.** In Explorer's address bar:

```
\\10.1.0.1\share
```

Network Neighbourhood also works once the browse master election settles, which
can take a few minutes. The address bar is immediate and always works.

**Printing.** Add Printer → Network printer → and give it the IPP URL:

```
http://10.1.0.1:631/printers/PDF
```

For the driver, **pick a colour PostScript printer**. CUPS renders whatever
PostScript it is handed, so a monochrome driver gives you a monochrome PDF.
These are on the Windows 98 CD and all work:

* Apple Color LaserWriter 12/600 PS
* HP Color LaserJet 5/5M PS
* MS Publisher Color Printer

Printed documents appear in `/mnt/spool`, which is also the `spool` SMB share —
so you can fetch your own PDF from `\\10.1.0.1\spool`.

## Windows XP

Same as above. XP can use `virtio-net-pci` if you install the drivers, which is
noticeably faster than `rtl8139`.

SMB1 has to be enabled on the appliance side (it is), and XP speaks it natively.

## Mac OS 9

**Network.** Control Panels → TCP/IP → Connect via Ethernet, Configure using
DHCP Server. Close and save.

**File sharing.** Apple menu → Chooser → AppleShare → "Server IP Address…" →
`10.1.0.1` → Connect → **Guest** → pick `share` or `pub`.

**Printing.** Applications (Mac OS 9) → Utilities → Desktop Printer Utility →
**Printer (LPR)** → Change…

* Printer Address: `10.1.0.1`
* Queue Name: `PDF` — type it in, and **untick "Use Default Queue on Server"**

> Leaving that box ticked makes Mac OS 9 send an empty queue name, and the
> connection drops with error `-8873`. This is a bug in Mac OS 9, not in CUPS.

Then select the desktop printer and Printing → Set Default Printer.

If copying files to a share fails with **error ‑50**, see the CNID note in
[chapter 06](06-file-sharing.md).

## MS-DOS

**Network.** You need a packet driver for your card plus
[mTCP](https://www.brutman.com/mTCP/). With `MTCPCFG` pointing at your config:

```
C:\> dhcp
C:\> ping 10.1.0.1
```

**Files.** mTCP's `ftp` client:

```
C:\> ftp 10.1.0.1
Name: anonymous
Password: (just press Enter)
```

**A whole disk.** See [chapter 08](08-netdrive.md).

**A fixed address** for a machine you use often — on the appliance, one file
per machine in `/etc/dnsmasq.d/`:

```sh
echo 'dhcp-host=52:54:00:12:34:56,10.1.0.49,dosbox' > /etc/dnsmasq.d/dosbox.conf
rc-service dnsmasq restart
```

The name also becomes `dosbox.home.net` in DNS while the lease is held.

## Linux, or anything modern

Everything works, but note that current distributions have SMB1 disabled. For a
one-off mount:

```bash
sudo mount -t cifs //10.1.0.1/share /mnt -o guest,vers=1.0,sec=ntlm
```

FTP is usually easier, and the shares are visible over AFP too.

Next: [10 · On a physical server](10-physical-server.md)
