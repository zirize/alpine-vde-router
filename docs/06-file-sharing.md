# 6 · File sharing

## What this does

Shares the same directory three ways, so every machine on the isolated network
can use whichever protocol it was born with:

| Protocol | Server | Clients |
|---|---|---|
| FTP | vsftpd | DOS, Windows, Linux, anything |
| SMB1 / CIFS | Samba | Windows for Workgroups 3.11 → XP |
| AFP | netatalk | Mac OS 8, 9, OS X |

All of them are **guest access, no password**, mapped onto one Unix account.

> **Why no passwords.** Windows 98 can only do SMB1 with NTLMv1. Mac OS 9 does
> AFP with cleartext or DHX. None of these is something you should authenticate
> against with a password you use anywhere else, and most of these clients
> cannot store a modern one anyway. The security boundary in this design is the
> network, not the login. Keep the isolated side isolated.

## Layout

```
/var/lib/ftp/            "pub"    - everything, read/write
└── uploads/             "share"  - the drop box, read/write
```

Add read-only folders underneath `/var/lib/ftp` and they appear in all three
protocols at once. On a VM those are usually virtiofs mounts from the host.

### Virtual machines: mount the host folders first

```bash
ssh root@192.168.1.50 'cd /root/setup && ./05-virtiofs.sh'
```

```
==> Mounting virtiofs shares
    added to fstab:   ftp -> /var/lib/ftp/uploads (rw)
    mounted:          /var/lib/ftp/uploads
    added to fstab:   spool -> /mnt/spool (rw)
    mounted:          /mnt/spool
```

By hand, one line per share in `/etc/fstab` — the first field is the **tag**
from the domain XML, not a device:

```
ftp	/var/lib/ftp/uploads	virtiofs	defaults	0 0
spool	/mnt/spool		virtiofs	defaults	0 0
```

```sh
mount -a
```

> **virtiofs does not carry extended attributes.** Anything that tries to use
> them fails with `errno 95` (ENOTSUP). That is not a bug you can fix; it is
> why the AFP configuration below keeps its index elsewhere and sets
> `ea = none`.

## Do it

```bash
ssh root@192.168.1.50
cd /root/setup
./20-file-sharing.sh
```

```
==> Creating the shared directories
    created user netdrv (uid 1000)
==> FTP (vsftpd)
    anonymous FTP on port 21, passive range 10000-10100
==> SMB / CIFS (Samba)
    shares:  \\10.1.0.1\share   and   \\10.1.0.1\pub
==> AFP (netatalk) for classic Mac OS
    corrected the pidfile in /etc/init.d/netatalk (Alpine packaging bug)
    AFP volumes: share, pub
```

### By hand — FTP

```sh
apk add vsftpd
```

`/etc/vsftpd/vsftpd.conf`:

```
listen=YES
anonymous_enable=YES
no_anon_password=YES
anon_root=/var/lib/ftp

write_enable=YES
anon_upload_enable=YES
anon_mkdir_write_enable=YES
anon_other_write_enable=YES
local_umask=0022
anon_umask=0022

connect_from_port_20=YES
pasv_enable=YES
pasv_min_port=10000
pasv_max_port=10100

seccomp_sandbox=NO
```

The passive port range must match the firewall rules from chapter 05. The last
line is needed because Alpine's vsftpd and its seccomp filter do not get along;
without it transfers die with "500 OOPS: priv_sock_get_cmd".

```sh
rc-update add vsftpd default && rc-service vsftpd start
```

### By hand — Samba

```sh
apk add samba
smbpasswd -an netdrv        # create the guest mapping account
```

`/etc/samba/smb.conf`:

```ini
[global]
	server role = standalone server
	workgroup = WORKGROUP

	interfaces = 127.0.0.0/8 eth1
	bind interfaces only = yes

	server min protocol = NT1
	client min protocol = NT1
	ntlm auth = ntlmv1-permitted
	smb1 unix extensions = no

	map to guest = Bad User
	guest account = netdrv
	usershare allow guests = yes

	wins support = yes
	dns proxy = no
	load printers = no
	printcap name = /dev/null

[share]
	comment = Drop box (read/write)
	path = /var/lib/ftp/uploads
	guest ok = yes
	read only = no
	create mask = 0664
	directory mask = 0775

[pub]
	comment = Everything (read/write)
	path = /var/lib/ftp
	guest ok = yes
	read only = no
	create mask = 0664
	directory mask = 0775
```

> **`bind interfaces only = yes` is the line that matters.** On its own,
> `interfaces = ...` is advisory: `smbd` still listens on `0.0.0.0`, and the
> only thing keeping SMB1 off your real network is the firewall. One mistaken
> firewall rule later and you are serving NTLMv1 to the world. With both lines,
> `netstat` shows smbd bound to `10.1.0.1` and `127.0.0.1` and nothing else.

```sh
testparm -s            # syntax check
rc-update add samba default && rc-service samba start
```

### By hand — AFP for classic Mac OS

```sh
apk add netatalk netatalk-openrc
mkdir -p /var/lib/netatalk/cnid/share /var/lib/netatalk/cnid/pub
chown -R netdrv:netdrv /var/lib/netatalk/cnid
```

`/etc/afp.conf`:

```ini
[Global]
guest account = netdrv
uam list = uams_guest.so uams_clrtxt.so uams_dhx.so uams_dhx2.so
appledouble = v2
ea = none

[share]
path = /var/lib/ftp/uploads
file perm = 0664
directory perm = 0775
vol dbpath = /var/lib/netatalk/cnid/share

[pub]
path = /var/lib/ftp
file perm = 0664
directory perm = 0775
vol dbpath = /var/lib/netatalk/cnid/pub
```

> **`vol dbpath` and `ea = none` are what stop "error ‑50".** netatalk keeps an
> index (the CNID database) for every volume. By default it lives inside the
> share. If the share is on virtiofs — or any filesystem without proper file
> locking, memory mapping and extended attributes — that index cannot be
> maintained, and the Mac reports a parameter error when copying files. Moving
> the index onto the appliance's own disk, and telling netatalk to store
> resource forks in `.AppleDouble` directories instead of extended attributes,
> makes it work.

There is one more thing to fix:

```sh
sed -i 's|^pidfile=/run/lock$|pidfile=/run/lock/netatalk|' /etc/init.d/netatalk
rc-update add netatalk default && rc-service netatalk restart
```

> **Alpine's `netatalk-openrc` has a packaging bug.** The init script sets
> `pidfile=/run/lock`, which is a *directory*. OpenRC cannot read a pid out of
> it, so `rc-service netatalk status` reports **crashed** while `afpd` is
> running perfectly. Harmless until you build monitoring or an auto-restart on
> top of it, and then extremely confusing. The daemon really writes
> `/run/lock/netatalk`. An Alpine update can put the wrong line back; just run
> the script again.

## Check it

```sh
rc-status default | grep -E 'vsftpd|samba|netatalk'
netstat -lnt | grep -E ':(21|139|445|548) '
```

```
 vsftpd       [  started  ]
 netatalk     [  started  ]
 samba        [  started  ]
tcp  0  0 0.0.0.0:21      LISTEN
tcp  0  0 10.1.0.1:139    LISTEN     <- note: not 0.0.0.0
tcp  0  0 10.1.0.1:445    LISTEN
tcp  0  0 :::548          LISTEN
```

From a client on the isolated network:

```
ftp 10.1.0.1                          # log in as "anonymous", empty password
smbclient -N -L //10.1.0.1            # should list share, pub
```

And from Windows 98: `\\10.1.0.1\share` in Explorer's address bar, or
Network Neighbourhood after a minute or two.

## If it went wrong

**Windows 98 cannot see the server at all.** Check `server min protocol = NT1`
and `ntlm auth = ntlmv1-permitted`. Modern Samba refuses SMB1 by default and
the client just sees nothing.

**Windows asks for a password and rejects everything.** `map to guest = Bad
User` is missing, or `guest account` names an account that does not exist.

**FTP connects then hangs on a directory listing.** Passive ports are blocked.
The `pasv_min_port`/`pasv_max_port` range and the firewall rule must match.

**Mac OS 9 copies fail with error ‑50.** The CNID index. See the note above. If
you are on a VM, check whether `/var/lib/netatalk/cnid` is itself a virtiofs
mount — move it onto the local disk.

**`rc-service netatalk status` says crashed but AFP works.** The pidfile bug
above.

**Files appear with the wrong owner.** Everything is created as the guest
account (`netdrv`, uid 1000). If the share is a host directory passed in with
virtiofs, that uid has to be meaningful on the *host* too.

Next: [07 · Printing](07-printing.md)
