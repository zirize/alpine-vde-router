#!/bin/bash
# ---------------------------------------------------------------------------
# Create the TAP device and run a VDE switch on it.
#
#   ./scripts/host/vde-switch.sh install   # persistent: systemd units (needs sudo)
#   ./scripts/host/vde-switch.sh start     # start the switch now
#   ./scripts/host/vde-switch.sh stop
#   ./scripts/host/vde-switch.sh status
#
# Why a VDE switch at all? Emulators such as QEMU and 86Box can plug straight
# into a unix socket with ordinary user privileges. No bridge, no root, no
# per-emulator TAP device. Everything plugged into the same socket is on the
# same virtual ethernet segment.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/../.."
. ./config.sh

TAP="${VDE_TAP:-vde0}"
SOCK="${VDE_SOCK:-/tmp/$TAP}"
MGMT="$SOCK.mgmt"
PIDFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$TAP.pid"

die() { echo "error: $*" >&2; exit 1; }

have_tap() { ip link show "$TAP" >/dev/null 2>&1; }

cmd_install() {
    command -v vde_switch >/dev/null || die "vde_switch not found (install the vde2 package)"
    echo "==> installing systemd units (this is the only step that needs sudo)"

    sudo install -d -m 0755 /etc/vde2
    # Note: the heredoc delimiter is QUOTED. With an unquoted one the shell
    # expands $1 and $TAP while writing the file, and you end up installing a
    # script full of empty strings that silently does nothing.
    sudo tee /etc/vde2/vde.conf >/dev/null <<CONF
V_TAP="$TAP"
V_USER="$(id -un)"
CONF

    sudo tee /etc/vde2/create-tap.sh >/dev/null <<'TAPSH'
#!/bin/bash
set -eu
. /etc/vde2/vde.conf
if [ "${1:-}" = "-d" ] || [ "${1:-}" = "--delete" ]; then
    ip tuntap del dev "$V_TAP" mode tap
    exit 0
fi
ip link show "$V_TAP" >/dev/null 2>&1 && exit 0
ip tuntap add dev "$V_TAP" mode tap user "$V_USER"
ip link set "$V_TAP" up
TAPSH
    sudo chmod 0755 /etc/vde2/create-tap.sh

    sudo tee /etc/systemd/system/create-tap.service >/dev/null <<'UNIT'
[Unit]
Description=Create the VDE TAP device
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/etc/vde2/create-tap.sh
ExecStop=/etc/vde2/create-tap.sh -d

[Install]
WantedBy=multi-user.target
UNIT

    sudo systemctl daemon-reload
    sudo systemctl enable --now create-tap.service

    mkdir -p ~/.config/systemd/user
    cat > ~/.config/systemd/user/vde-switch.service <<UNIT
[Unit]
Description=VDE switch on $TAP
# The TAP device is created by a system unit, so a user unit cannot order
# itself after it. The switch script waits for the device instead.
After=default.target

[Service]
Type=forking
ExecStart=$PWD/scripts/host/vde-switch.sh start
ExecStop=$PWD/scripts/host/vde-switch.sh stop
RemainAfterExit=yes

[Install]
WantedBy=default.target
UNIT
    systemctl --user daemon-reload
    systemctl --user enable --now vde-switch.service
    echo "==> done. The switch will come back after a reboot."
}

cmd_start() {
    command -v vde_switch >/dev/null || die "vde_switch not found (install the vde2 package)"
    # The TAP unit and this one can race at boot, so wait rather than fail.
    for _ in $(seq 1 30); do have_tap && break; sleep 1; done
    have_tap || die "TAP device '$TAP' does not exist. Run '$0 install' first."

    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "already running (pid $(cat "$PIDFILE"))"; return 0
    fi
    rm -f "$PIDFILE"
    mkdir -p "$(dirname "$PIDFILE")"
    vde_switch --daemon --numports 32 \
               --sock "$SOCK" --mode 660 \
               --mgmt "$MGMT" --mgmtmode 660 \
               --tap "$TAP" --pidfile "$PIDFILE"
    sleep 1
    [ -S "$SOCK/ctl" ] || die "the switch did not create $SOCK/ctl"
    echo "VDE switch running on $SOCK (pid $(cat "$PIDFILE"))"
}

cmd_stop() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
        echo "stopped"
    else
        echo "not running"
    fi
}

cmd_status() {
    have_tap && echo "TAP    $TAP: present" || echo "TAP    $TAP: MISSING"
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "switch running, pid $(cat "$PIDFILE"), socket $SOCK"
    else
        echo "switch not running"
        return 0
    fi
    echo
    echo "Ports (each connected client takes one):"
    if command -v socat >/dev/null; then
        { printf 'port/allprint\n'; sleep 1; } | socat -t3 - "UNIX-CONNECT:$MGMT" 2>/dev/null \
            | grep -E '^Port|endpoint' | sed 's/^/    /'
    else
        echo "    (install socat, or run: vdeterm $MGMT)"
    fi
}

case "${1:-status}" in
    install) cmd_install ;;
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    restart) cmd_stop; cmd_start ;;
    status)  cmd_status ;;
    *) echo "usage: $0 {install|start|stop|restart|status}"; exit 1 ;;
esac
