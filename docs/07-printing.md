# 7 · Printing

## What this does

Gives the isolated network a printer that turns anything sent to it into a PDF
file. Old software gets to print; you get a file instead of paper.

* **IPP**, port 631 — Windows 98 and later, Linux, modern machines
* **LPD**, port 515 — classic Mac OS, and anything that only speaks LPR

PDFs land in `/mnt/spool`, which is also shared over SMB and AFP, so the same
old machine can print a document and then pick up its own PDF.

## Do it

```bash
ssh root@192.168.1.50
cd /root/setup
./30-printing.sh
```

```
==> Installing CUPS and the PDF backend
==> Letting root administer the queue
==> Configuring the CUPS daemon
==> Pointing the PDF backend at /mnt/spool
==> Creating the 'PDF' queue
==> Enabling LPD on port 515 for classic Mac OS
==> Done
    IPP  http://10.1.0.1:631/printers/PDF
    LPD  host 10.1.0.1, queue name PDF
    PDFs appear in /mnt/spool
```

### By hand

```sh
apk add cups cups-filters cups-pdf busybox-extras
mkdir -p /mnt/spool
chown netdrv:netdrv /mnt/spool
```

**Let root administer the queue.** In `/etc/cups/cups-files.conf`:

```
SystemGroup sys root lpadmin
```

Without this, `lpadmin` from a root shell is refused with `403 Forbidden`,
which is a baffling error to get as root.

**The daemon.** At the top of `/etc/cups/cupsd.conf`, replacing any existing
`Listen`/`Port` lines:

```
Listen 10.1.0.1:631
Listen /run/cups/cups.sock
ServerAlias *
DefaultEncryption Never
```

and inside `<Location />`, add your isolated network:

```
<Location />
  Allow 10.1.0.0/24
  Order allow,deny
  ...
</Location>
```

> **Two things here bite people.**
>
> `ServerAlias *` — Windows 98 sends an IPP `Host:` header CUPS does not
> recognise, and CUPS answers `400 Bad Request`. This line turns the check off.
>
> `Listen 10.1.0.1:631` means CUPS is **not** listening on the uplink side. If
> you later try `http://192.168.1.50:631/` from your desktop you will get
> "connection refused", and that is correct behaviour, not a broken service.
> Check it from the isolated side, or with `lpstat -t` over SSH.

**The PDF backend.** In `/etc/cups/cups-pdf.conf`:

```
Out /mnt/spool
AnonDirName /mnt/spool
AnonUser netdrv
Grp netdrv
PostProcessing /usr/local/bin/pdf-post.sh
```

`/usr/local/bin/pdf-post.sh` runs once per finished file, so that the PDF is
readable over the shares instead of being a root-owned 0600 file:

```sh
#!/bin/sh
chown 1000:1000 "$1"
chmod 0664 "$1"
```

```sh
chmod 0755 /usr/local/bin/pdf-post.sh
chmod 0700 /usr/lib/cups/backend/cups-pdf   # cups-pdf refuses to run otherwise
rc-update add cupsd default && rc-service cupsd restart
```

**The queue:**

```sh
lpadmin -p PDF -v cups-pdf:/ -P /usr/share/ppd/cups-pdf/CUPS-PDF_opt.ppd -E
lpadmin -p PDF -o printer-is-shared=true
lpadmin -d PDF
```

`printer-is-shared=true` is not optional — without it the queue is invisible
over the network even though the daemon is listening. Making it the default
queue matters for Mac OS 9, which sometimes sends an empty queue name; with a
default set, that becomes a normal job instead of error `-8873`.

**LPD for classic Mac OS.** CUPS ships an LPD bridge that runs from inetd. Add
to `/etc/inetd.conf`:

```
printer stream tcp nowait root /usr/lib/cups/daemon/cups-lpd cups-lpd -n -o document-format=application/octet-stream
```

Then give inetd a real service file, `/etc/init.d/inetd`:

```sh
#!/sbin/openrc-run
description="BusyBox inetd (provides LPD via cups-lpd)"
command="/usr/sbin/inetd"
pidfile="/run/inetd.pid"
command_args="-f"
command_background=true
depend() {
    need net
    after firewall cupsd
}
```

```sh
chmod 0755 /etc/init.d/inetd
rc-update add inetd default && rc-service inetd start
```

> Most write-ups start inetd from `/etc/local.d/inetd.start` instead. That
> works, but `rc-service inetd status` then knows nothing about it, it has no
> dependency on `cupsd`, and it will not restart cleanly. A twelve-line service
> file is worth it.

## Check it

On the appliance:

```sh
lpstat -t
netstat -lnt | grep -E ':(631|515) '
```

```
scheduler is running
system default destination: PDF
device for PDF: cups-pdf:/
printer PDF is idle.  enabled since ...
tcp  0  0 0.0.0.0:515      LISTEN
tcp  0  0 10.1.0.1:631     LISTEN
```

End to end:

```sh
printf '%%!PS\n/Courier findfont 18 scalefont setfont 72 700 moveto (test) show showpage\n' > /tmp/t.ps
lp -d PDF /tmp/t.ps
sleep 5
ls -l /mnt/spool/
```

```
-rw-rw-r--    1 netdrv   netdrv        1675 Sep 18 14:34 t.ps____0-job_1.pdf
```

Owner `netdrv` and mode `0664` mean the post-processing script ran; without it
the file would be root-owned and unreadable over the shares.

Client setup is in [09 · Connecting clients](09-clients.md). In short:

* **Windows 98 / XP** — network printer, URL `http://10.1.0.1:631/printers/PDF`,
  and you must pick a **colour PostScript** driver
* **Mac OS 9** — Desktop Printer Utility → Printer (LPR), address `10.1.0.1`,
  queue name `PDF`

## If it went wrong

**`lpadmin: 403 Forbidden` as root.** `SystemGroup` in
`/etc/cups/cups-files.conf`.

**Windows 98 says "400 Bad Request".** `ServerAlias *` is missing.

**Connection refused from the uplink side.** Expected — see the note above.

**Job disappears and no PDF appears.** Look at `/var/log/cups/error_log`. The
usual cause is the cups-pdf backend being group-writable; `chmod 0700` it.

**PDFs come out black and white** from a colour document. The client is using a
monochrome PostScript driver. CUPS renders what it is sent — change the driver
on the client, not anything here.

**Mac OS 9 fails with `-8873`.** The queue name was sent empty. Set a default
queue (`lpadmin -d PDF`) and, on the Mac, untick "Use Default Queue on Server"
and type `PDF` explicitly.

**Nothing on port 515.** `rc-service inetd status`. Also check that
`/etc/inetd.conf` has exactly one `printer` line.

Next: [08 · NetDrive](08-netdrive.md)
