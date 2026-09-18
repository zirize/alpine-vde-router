#!/bin/sh
# ---------------------------------------------------------------------------
# File sharing for old clients, all of it guest-access (no passwords):
#   * FTP      (vsftpd)     - DOS, Windows, anything with an FTP client
#   * SMB / CIFS (Samba)    - Windows for Workgroups 3.11, 95, 98, NT, XP
#   * AFP      (netatalk)   - Mac OS 8 / 9 / OS X
#
# Safe to run more than once.
# ---------------------------------------------------------------------------
. "$(dirname "$0")/_common.sh"

say "Creating the shared directories"
# One unix account owns everything. Guests are mapped onto it, so a 1998
# machine that has no concept of your user database still gets sane ownership.
if ! id -u "$SHARE_USER" >/dev/null 2>&1; then
    adduser -u "$SHARE_UID" -D -H -s /sbin/nologin "$SHARE_USER"
    info "created user $SHARE_USER (uid $SHARE_UID)"
fi
mkdir -p "$FTP_ROOT" "$SHARE_DIR"
chown "$SHARE_USER:$SHARE_USER" "$SHARE_DIR"
chmod 0775 "$SHARE_DIR"
info "share root  $FTP_ROOT"
info "drop box    $SHARE_DIR"

# ---------------------------------------------------------------------- FTP
if [ "${ENABLE_FTP:-1}" = "1" ]; then
    say "FTP (vsftpd)"
    apk_add vsftpd
    cat > /etc/vsftpd/vsftpd.conf <<VSEOF
# Written by alpine-vde-router.
listen=YES
anonymous_enable=YES
no_anon_password=YES
anon_root=$FTP_ROOT

write_enable=YES
anon_upload_enable=YES
anon_mkdir_write_enable=YES
anon_other_write_enable=YES
local_umask=0022
anon_umask=0022

dirmessage_enable=YES
xferlog_enable=YES
use_localtime=YES

# Old clients often cannot do active FTP through a router, so keep passive on
# and pin the port range - the firewall rule below has to match it.
connect_from_port_20=YES
pasv_enable=YES
pasv_min_port=10000
pasv_max_port=10100

# Alpine's vsftpd and its seccomp filter do not get along.
seccomp_sandbox=NO
VSEOF
    svc vsftpd
    info "anonymous FTP on port 21, passive range 10000-10100"
fi

# -------------------------------------------------------------------- Samba
if [ "${ENABLE_SAMBA:-1}" = "1" ]; then
    say "SMB / CIFS (Samba)"
    apk_add samba
    smbpasswd -an "$SHARE_USER" >/dev/null 2>&1 || true
    cat > /etc/samba/smb.conf <<SMBEOF
# Written by alpine-vde-router.
[global]
	server role = standalone server
	server string = %h
	workgroup = WORKGROUP

	# Only answer on the isolated network. "bind interfaces only" is what
	# actually stops smbd from listening on 0.0.0.0 - without it the
	# "interfaces" line alone is advisory and the port stays open to the
	# uplink, with nothing but the firewall in the way.
	interfaces = 127.0.0.0/8 $LAN_IF
	bind interfaces only = yes

	# Windows 9x / NT4 speak SMB1 and NTLMv1 and nothing newer.
	# Only do this on an isolated network that has no route in from outside.
	server min protocol = NT1
	client min protocol = NT1
	ntlm auth = ntlmv1-permitted
	smb1 unix extensions = no

	# Everyone is a guest, mapped onto $SHARE_USER.
	map to guest = Bad User
	guest account = $SHARE_USER
	usershare allow guests = yes

	wins support = yes
	dns proxy = no
	load printers = no
	printcap name = /dev/null
	log file = /var/log/samba/%m.log
	max log size = 50

[share]
	comment = Drop box (read/write)
	path = $SHARE_DIR
	guest ok = yes
	read only = no
	create mask = 0664
	directory mask = 0775

[pub]
	comment = Everything (read/write)
	path = $FTP_ROOT
	guest ok = yes
	read only = no
	create mask = 0664
	directory mask = 0775
SMBEOF
    if [ "${ENABLE_PRINTING:-1}" = "1" ]; then
        mkdir -p "$SPOOL_DIR"
        cat >> /etc/samba/smb.conf <<SMBEOF

[spool]
	comment = Printed PDFs
	path = $SPOOL_DIR
	guest ok = yes
	read only = no
	create mask = 0664
SMBEOF
    fi
    testparm -s >/dev/null 2>&1 || warn "testparm reported a problem with smb.conf"
    svc samba
    info 'shares:  \\'"$LAN_ADDR"'\share   and   \\'"$LAN_ADDR"'\pub'
fi

# ------------------------------------------------------------------ netatalk
if [ "${ENABLE_AFP:-1}" = "1" ]; then
    say "AFP (netatalk) for classic Mac OS"
    apk_add netatalk netatalk-openrc

    # The CNID database must live on a real local filesystem. If a share is a
    # virtiofs mount (or any filesystem without proper locking and extended
    # attributes) netatalk cannot keep its index there, and the Mac reports
    # "error -50" when copying files. Keeping the databases on / avoids it.
    for v in share pub spool; do mkdir -p "/var/lib/netatalk/cnid/$v"; done
    chown -R "$SHARE_USER:$SHARE_USER" /var/lib/netatalk/cnid
    if mount | grep -q " on /var/lib/netatalk/cnid .*virtiofs"; then
        warn "/var/lib/netatalk/cnid is itself a virtiofs mount."
        warn "  It may work, but this is the first thing to undo if Macs start"
        warn "  reporting error -50: remove that share from VIRTIOFS_SHARES so"
        warn "  the index lives on the VM's own disk."
    fi

    cat > /etc/afp.conf <<AFPEOF
; Written by alpine-vde-router.
[Global]
guest account = $SHARE_USER
uam list = uams_guest.so uams_clrtxt.so uams_dhx.so uams_dhx2.so

; Classic Mac OS stores its resource forks in .AppleDouble directories.
; "ea = none" is required when a share sits on a filesystem that cannot do
; extended attributes - virtiofs, most notably.
appledouble = v2
ea = none

[share]
path = $SHARE_DIR
file perm = 0664
directory perm = 0775
vol dbpath = /var/lib/netatalk/cnid/share

[pub]
path = $FTP_ROOT
file perm = 0664
directory perm = 0775
vol dbpath = /var/lib/netatalk/cnid/pub
AFPEOF
    if [ "${ENABLE_PRINTING:-1}" = "1" ]; then
        cat >> /etc/afp.conf <<AFPEOF

[spool]
path = $SPOOL_DIR
file perm = 0664
directory perm = 0775
vol dbpath = /var/lib/netatalk/cnid/spool
AFPEOF
    fi
    # Alpine's netatalk-openrc ships an init script whose pidfile points at
    # /run/lock - a DIRECTORY. OpenRC cannot read a pid out of it, so
    # "rc-service netatalk status" reports "crashed" while afpd is running
    # perfectly well. The daemon actually writes /run/lock/netatalk.
    # Left alone, this breaks any monitoring or auto-restart you build later.
    if grep -q '^pidfile=/run/lock$' /etc/init.d/netatalk 2>/dev/null; then
        sed -i 's|^pidfile=/run/lock$|pidfile=/run/lock/netatalk|' /etc/init.d/netatalk
        info "corrected the pidfile in /etc/init.d/netatalk (Alpine packaging bug)"
    fi

    svc netatalk
    sleep 1
    if rc-service netatalk status 2>&1 | grep -q crashed; then
        warn "netatalk still reports 'crashed'."
        warn "  If 'netstat -lnt | grep 548' shows it listening, AFP is fine and"
        warn "  only the status is wrong. An Alpine update can reintroduce this;"
        warn "  just run this script again."
    fi
    info "AFP volumes: share, pub"
fi

say "Done"
info "Check it:  netstat -lntu | grep -E ':(21|139|445|548) '"
