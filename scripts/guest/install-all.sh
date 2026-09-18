#!/bin/sh
# Run every provisioning step in order. Stops at the first failure.
. "$(dirname "$0")/_common.sh"
HERE=$(cd "$(dirname "$0")" && pwd)

for step in 10-router 05-virtiofs 20-file-sharing 30-printing 40-netdrive; do
    case "$step" in
        05-*) [ -n "$(printf '%s' "${VIRTIOFS_SHARES:-}" | tr -d '[:space:]')" ] || { say "Skipping $step (no virtiofs shares)"; continue; } ;;
        20-*) [ "${ENABLE_FTP:-1}${ENABLE_SAMBA:-1}${ENABLE_AFP:-1}" = "000" ] \
                  && { say "Skipping $step (all file sharing disabled)"; continue; } ;;
        30-*) [ "${ENABLE_PRINTING:-1}" = "1" ] || { say "Skipping $step (disabled)"; continue; } ;;
        40-*) [ "${ENABLE_NETDRIVE:-1}" = "1" ] || { say "Skipping $step (disabled)"; continue; } ;;
    esac
    printf '\n\033[1;44m  %s  \033[0m\n' "$step"
    "$HERE/$step.sh" || { echo; echo "error: $step.sh failed - fix it and run it again."; exit 1; }
done

printf '\n\033[1;42m  All steps finished  \033[0m\n\n'
