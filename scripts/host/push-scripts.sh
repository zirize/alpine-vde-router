#!/bin/bash
# ---------------------------------------------------------------------------
# Copy config.sh and the guest scripts onto the appliance.
#
#   ./scripts/host/push-scripts.sh
#
# After this, everything you need is in /root/setup on the appliance:
#
#   ssh root@<address>
#   cd /root/setup && ./10-router.sh
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/../.."
. ./config.sh

TARGET="root@${1:-${WAN_ADDR}}"

echo "==> copying to $TARGET:/root/setup"
ssh -o StrictHostKeyChecking=accept-new "$TARGET" 'mkdir -p /root/setup'
scp -q -o StrictHostKeyChecking=accept-new \
    config.sh scripts/guest/*.sh "$TARGET":/root/setup/
ssh "$TARGET" 'chmod +x /root/setup/*.sh; ls -1 /root/setup'

cat <<MSG

Done. Now, on the appliance:

    ssh $TARGET
    cd /root/setup
    ./10-router.sh          # NAT, DHCP, DNS       (docs/05-router.md)
    ./20-file-sharing.sh    # FTP, SMB, AFP        (docs/06-file-sharing.md)
    ./30-printing.sh        # PDF printer          (docs/07-printing.md)
    ./40-netdrive.sh        # DOS disk server      (docs/08-netdrive.md)

Or all of them at once:

    ssh $TARGET 'cd /root/setup && ./install-all.sh'
MSG
