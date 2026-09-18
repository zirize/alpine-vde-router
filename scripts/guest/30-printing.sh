#!/bin/sh
# ---------------------------------------------------------------------------
# A virtual printer that turns anything printed at it into a PDF file.
#
#   * IPP (port 631)  - Windows 98 / NT / 2000 / XP, Linux, modern machines
#   * LPD (port 515)  - classic Mac OS, and anything else that only speaks LPR
#
# PDFs land in $SPOOL_DIR, which is also shared over SMB and AFP, so the old
# machine can print and then pick its own PDF up again.
#
# Safe to run more than once.
# ---------------------------------------------------------------------------
. "$(dirname "$0")/_common.sh"

say "Installing CUPS and the PDF backend"
apk_add cups cups-filters cups-pdf busybox-extras

mkdir -p "$SPOOL_DIR"
id -u "$SHARE_USER" >/dev/null 2>&1 || adduser -u "$SHARE_UID" -D -H -s /sbin/nologin "$SHARE_USER"
chown "$SHARE_USER:$SHARE_USER" "$SPOOL_DIR"
chmod 0775 "$SPOOL_DIR"

say "Letting root administer the queue"
# Without this, "lpadmin" from a root shell is refused with 403 Forbidden,
# because the default SystemGroup does not contain any group root is in.
if [ -f /etc/cups/cups-files.conf ]; then
    if grep -q '^SystemGroup' /etc/cups/cups-files.conf; then
        sed -i 's/^SystemGroup .*/SystemGroup sys root lpadmin/' /etc/cups/cups-files.conf
    else
        echo "SystemGroup sys root lpadmin" >> /etc/cups/cups-files.conf
    fi
fi

say "Configuring the CUPS daemon"
CUPSD=/etc/cups/cupsd.conf
[ -f "$CUPSD.orig" ] || cp "$CUPSD" "$CUPSD.orig" 2>/dev/null || true
python3 - "$CUPSD" "$LAN_ADDR" "$LAN_CIDR" <<'PYEOF' 2>/dev/null || sh -c '
# No python on the box - fall back to sed. Same result, less tidy.
true'
import sys, re
path, lan_addr, lan_cidr = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
src = re.sub(r'(?m)^\s*(Listen|Port)\s+.*$', '', src)
head = """# Written by alpine-vde-router.
# Listen only on the isolated network plus the local socket. If you ever try to
# reach :631 from the uplink side you will get "connection refused" - that is
# this line doing its job, not a broken service.
Listen %s:631
Listen /run/cups/cups.sock

# Windows 98 sends an IPP Host: header CUPS does not recognise and would answer
# with "400 Bad Request". ServerAlias * makes CUPS stop checking.
ServerAlias *
DefaultEncryption Never
""" % lan_addr
src = head + src
src = src.replace("<Location />",
                  "<Location />\n  Allow %s" % lan_cidr, 1)
open(path, "w").write(src)
PYEOF

if ! grep -q "^Listen $LAN_ADDR:631" "$CUPSD"; then
    # python was not available; do it with plain tools.
    sed -i -e '/^[[:space:]]*Listen /d' -e '/^[[:space:]]*Port /d' "$CUPSD"
    tmp=$(mktemp)
    {
        echo "# Written by alpine-vde-router."
        echo "Listen $LAN_ADDR:631"
        echo "Listen /run/cups/cups.sock"
        echo "ServerAlias *"
        echo "DefaultEncryption Never"
        cat "$CUPSD"
    } > "$tmp"
    mv "$tmp" "$CUPSD"
    grep -q "Allow $LAN_CIDR" "$CUPSD" || \
        sed -i "0,/<Location \/>/s//<Location \/>\n  Allow $LAN_CIDR/" "$CUPSD"
fi

say "Pointing the PDF backend at $SPOOL_DIR"
POST=/usr/local/bin/pdf-post.sh
mkdir -p /usr/local/bin
cat > "$POST" <<POSTEOF
#!/bin/sh
# Runs once per finished PDF. Makes the file readable by everyone on the
# shares, instead of the 0600 root-owned file cups-pdf would leave behind.
chown $SHARE_UID:$SHARE_UID "\$1"
chmod 0664 "\$1"
POSTEOF
chmod 0755 "$POST"

PDFCONF=/etc/cups/cups-pdf.conf
for kv in "Out $SPOOL_DIR" "AnonDirName $SPOOL_DIR" "AnonUser $SHARE_USER" \
          "Grp $SHARE_USER" "PostProcessing $POST"; do
    key=${kv%% *}
    if grep -qE "^#?$key " "$PDFCONF"; then
        sed -i "s|^#\?$key .*|$kv|" "$PDFCONF"
    else
        echo "$kv" >> "$PDFCONF"
    fi
done

# cups-pdf refuses to run if its backend is group- or world-writable.
chmod 0700 /usr/lib/cups/backend/cups-pdf 2>/dev/null || true

svc cupsd
sleep 2

say "Creating the 'PDF' queue"
PPD=$(ls /usr/share/ppd/cups-pdf/*.ppd 2>/dev/null | head -1)
if [ -z "$PPD" ]; then
    warn "no cups-pdf PPD found; creating the queue without one"
    lpadmin -p PDF -v cups-pdf:/ -E
else
    lpadmin -p PDF -v cups-pdf:/ -P "$PPD" -E
fi
# Without printer-is-shared the queue is invisible to the network even though
# the daemon is listening.
lpadmin -p PDF -o printer-is-shared=true
# Mac OS 9 sometimes sends an empty queue name. Making PDF the default turns
# that from error -8873 into a normal print job.
lpadmin -d PDF
cupsenable PDF 2>/dev/null || true
cupsaccept PDF 2>/dev/null || true

say "Enabling LPD on port 515 for classic Mac OS"
apk_add busybox-extras
ensure_line \
"printer stream tcp nowait root /usr/lib/cups/daemon/cups-lpd cups-lpd -n -o document-format=application/octet-stream" \
    /etc/inetd.conf
# Ship a real OpenRC service rather than hiding inetd in /etc/local.d, so that
# "rc-service inetd status" tells the truth and dependencies are honoured.
cat > /etc/init.d/inetd <<'INITEOF'
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
INITEOF
chmod 0755 /etc/init.d/inetd
svc inetd

say "Done"
info "IPP  http://$LAN_ADDR:631/printers/PDF"
info "LPD  host $LAN_ADDR, queue name PDF"
info "PDFs appear in $SPOOL_DIR"
echo
info "Test it from here:  echo hello | lp -d PDF && sleep 3 && ls -l $SPOOL_DIR"
