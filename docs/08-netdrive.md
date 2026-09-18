# 8 · NetDrive — a network hard disk for DOS

Optional. Set `ENABLE_NETDRIVE=0` in `config.sh` to skip it.

## What this does

[mTCP NetDrive](https://www.brutman.com/mTCP/) serves a disk image over UDP.
The DOS client loads a small TSR and the image appears as an ordinary drive
letter — `D:` with a full DOS filesystem, not a network redirector.

That matters for machines where nothing else works: a 286 with 640 KB of RAM
has no room for a network file-sharing stack, and a laptop with a dead drive
bay has nowhere to put a second disk. NetDrive needs about 8 KB resident.

It is also simply fast, because the client is doing plain sector reads and
writes rather than translating file operations.

## Get the server

The NetDrive server is **not** part of this repository. It is Michael Brutman's
work and is distributed from his own site:

> <https://www.brutman.com/mTCP/>

Download the Linux server binary, then copy it to the appliance:

```bash
scp netdrive_linux_amd64 root@192.168.1.50:/usr/local/bin/netdrive
ssh root@192.168.1.50 'chmod 755 /usr/local/bin/netdrive'
```

The setup script also picks it up automatically if you leave it in `/root` or
under its original name.

## Do it

```bash
ssh root@192.168.1.50
cd /root/setup
./40-netdrive.sh
```

```
==> Looking for the NetDrive server
    mTCP NetDrive by M Brutman (mbbrutman@gmail.com) ... Version: Jan 10 2025
==> Preparing /mnt/netdrv
    -rw-r--r--    1 netdrv   netdrv   524288000 Sep 18 14:40 dosshare.hd
==> Installing the service
==> Done
    NetDrive listens on UDP 2002
    Images in /mnt/netdrv
    On the DOS client:  netdrive 10.1.0.1 dosshare.hd
```

If there is no image yet the script makes a 500 MB one.

### By hand

```sh
adduser -u 1000 -D -H -s /sbin/nologin netdrv
mkdir -p /mnt/netdrv
chown netdrv:netdrv /mnt/netdrv

# a 500 MB hard disk image
/usr/local/bin/netdrive create -size 500 /mnt/netdrv/dosshare.hd

touch /var/log/netdrive.log
chown netdrv:netdrv /var/log/netdrive.log
```

`/etc/init.d/netdrive`:

```sh
#!/sbin/openrc-run
description="mTCP NetDrive disk server"
command="/usr/local/bin/netdrive"
command_args="-log_file /var/log/netdrive.log serve -headless -image_dir /mnt/netdrv"
command_user="netdrv:netdrv"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
depend() {
    need net
    after firewall
}
```

```sh
chmod 0755 /etc/init.d/netdrive
rc-update add netdrive default && rc-service netdrive start
```

Useful server options — `netdrive serve help` lists them all:

| | |
|---|---|
| `-port <n>` | listen somewhere other than 2002 |
| `-max_active_sessions <n>` | default 20 |
| `-timeout <minutes>` | drop idle sessions |
| `-log_level debug` | very chatty, but tells you exactly what a client asked for |

## Check it

```sh
rc-service netdrive status
netstat -lnu | grep 2002
tail /var/log/netdrive.log
```

```
 * status: started
udp  0  0 0.0.0.0:2002   0.0.0.0:*
2026-09-18 14:40:21 INFO   Serve: Listening on port 2002
```

There is no useful way to test the protocol from Linux — it is only spoken by
the DOS client. Watch the log while a DOS machine connects.

## On the DOS client

You need the mTCP client package on the DOS machine, and mTCP configured (a
`MTCPCFG` environment variable pointing at a config file, with `PACKETINT` and
DHCP settings). The mTCP documentation covers that far better than this page
could.

Then:

```
C:\> dhcp
C:\> netdrive 10.1.0.1 dosshare.hd
```

The image appears as the next free drive letter. Unmount with:

```
C:\> netdrive /stop
```

A newly created image is unformatted. Format it once, from the DOS side:

```
C:\> format d: /s
```

> **One image, one machine at a time.** This is a *block* protocol: the client
> is writing sectors directly. Two DOS machines mounting the same image
> read/write at once will corrupt the filesystem, exactly as two computers
> wired to one IDE disk would. Give each machine its own image, or mount
> read-only. If you need genuinely shared storage, use the SMB or FTP shares
> from [chapter 06](06-file-sharing.md) instead.

## If it went wrong

**`error: the NetDrive server is not installed`** — the binary is not at
`/usr/local/bin/netdrive`. See above.

**Service starts then stops immediately.** Check `/var/log/netdrive.log`. The
usual cause is `/mnt/netdrv` not being writable by `netdrv`.

**DOS client times out.** Check the client got an address (`dhcp` first), that
it can `ping 10.1.0.1`, and that the packet driver is loaded. NetDrive is UDP,
so a firewall in between silently drops it — on this appliance the rule
`ufw allow in on eth1 to any` already covers it.

**Drive letter appears but the disk is unreadable.** The image has never been
formatted. `format d:` from DOS.

Next: [09 · Connecting clients](09-clients.md)
