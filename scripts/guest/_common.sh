# Sourced by every guest script. Not meant to be run on its own.
set -eu

[ "$(id -u)" = "0" ] || { echo "error: run this as root"; exit 1; }
[ -f /etc/alpine-release ] || { echo "error: this is not Alpine Linux"; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
if [ -f "$HERE/config.sh" ]; then
    . "$HERE/config.sh"
elif [ -f "$HERE/../../config.sh" ]; then
    . "$HERE/../../config.sh"
else
    echo "error: config.sh not found next to the scripts."
    echo "       Copy config.example.sh to config.sh and edit it first."
    exit 1
fi

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[33m    warning: %s\033[0m\n' "$*"; }

# Add a line to a file only once.
ensure_line() {
    _line=$1; _file=$2
    grep -qxF "$_line" "$_file" 2>/dev/null || echo "$_line" >> "$_file"
}

# Install packages, retrying once with the community repo enabled.
apk_add() {
    apk add --no-progress "$@" >/dev/null 2>&1 && return 0
    info "retrying with an apk index refresh"
    apk update --no-progress >/dev/null 2>&1 || true
    apk add --no-progress "$@" >/dev/null
}

svc() {   # svc <name> -> enable at boot and (re)start now
    rc-update add "$1" default >/dev/null 2>&1 || true
    rc-service "$1" restart >/dev/null 2>&1 || rc-service "$1" start >/dev/null 2>&1 || {
        warn "service $1 did not start; check 'rc-service $1 status'"
        return 1
    }
}
