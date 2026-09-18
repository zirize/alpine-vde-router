#!/bin/sh
# ---------------------------------------------------------------------------
# mTCP NetDrive - serves a disk image over UDP to DOS machines, which then see
# it as an ordinary hard disk. Useful for PCs too old to run a network stack
# with file sharing, or with no free drive bay.
#
# The server binary is NOT part of this repository. Download it first:
#     https://www.brutman.com/mTCP/
# and put it at /usr/local/bin/netdrive.
#
# Safe to run more than once.
# ---------------------------------------------------------------------------
. "$(dirname "$0")/_common.sh"

BIN=/usr/local/bin/netdrive

say "Looking for the NetDrive server"
if [ ! -x "$BIN" ]; then
    # Accept the upstream file name too, so people can just copy it over.
    for c in /usr/local/bin/netdrive_linux_amd64 /bin/netdrive_linux_amd64 \
             /root/netdrive_linux_amd64 /root/netdrive; do
        if [ -f "$c" ]; then
            install -m 0755 "$c" "$BIN"
            info "installed from $c"
            break
        fi
    done
fi
if [ ! -x "$BIN" ]; then
    cat <<MSG
error: the NetDrive server is not installed.

  1. Download the Linux server from  https://www.brutman.com/mTCP/
  2. Copy it onto this machine, for example from your desktop:
         scp netdrive_linux_amd64 root@$WAN_ADDR:/usr/local/bin/netdrive
  3. Run this script again.

  Or set ENABLE_NETDRIVE=0 in config.sh to skip NetDrive entirely.
MSG
    exit 1
fi
info "$("$BIN" 2>&1 | head -1)"

say "Preparing $NETDRV_DIR"
id -u "$SHARE_USER" >/dev/null 2>&1 || adduser -u "$SHARE_UID" -D -H -s /sbin/nologin "$SHARE_USER"
mkdir -p "$NETDRV_DIR"
chown "$SHARE_USER:$SHARE_USER" "$NETDRV_DIR"

if [ -z "$(ls -A "$NETDRV_DIR" 2>/dev/null)" ]; then
    info "no disk image yet - creating a 500 MB one called dosshare.hd"
    su -s /bin/sh "$SHARE_USER" -c "$BIN create -size 500 '$NETDRV_DIR/dosshare.hd'" \
        || "$BIN" create -size 500 "$NETDRV_DIR/dosshare.hd"
    chown "$SHARE_USER:$SHARE_USER" "$NETDRV_DIR"/*.hd 2>/dev/null || true
fi
ls -l "$NETDRV_DIR" | sed 's/^/    /'

say "Installing the service"
touch /var/log/netdrive.log
chown "$SHARE_USER:$SHARE_USER" /var/log/netdrive.log
cat > /etc/init.d/netdrive <<INITEOF
#!/sbin/openrc-run
description="mTCP NetDrive disk server"
command="$BIN"
command_args="-log_file /var/log/netdrive.log serve -headless -image_dir $NETDRV_DIR"
command_user="$SHARE_USER:$SHARE_USER"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
depend() {
    need net
    after firewall
}
INITEOF
chmod 0755 /etc/init.d/netdrive
svc netdrive

say "Done"
info "NetDrive listens on UDP 2002"
info "Images in $NETDRV_DIR"
echo
info "On the DOS client:  netdrive $LAN_ADDR dosshare.hd"
info "Log:                tail -f /var/log/netdrive.log"
