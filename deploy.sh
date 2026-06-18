#!/bin/bash
# Deploy script for luci-app-captive-portal
# Manual deployment for development/testing

set -e

DEVICE="${1:-192.168.1.1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Deploying luci-app-captive-portal to ${DEVICE} ==="

# Deploy LuCI views
echo "Deploying LuCI views..."
scp -r "${SCRIPT_DIR}/htdocs/luci-static/resources/view/captive-portal/" \
    "root@${DEVICE}:/www/luci-static/resources/view/"

# Deploy splash page assets
echo "Deploying splash page..."
scp -r "${SCRIPT_DIR}/htdocs/captive-portal/" \
    "root@${DEVICE}:/www/captive-portal/"

# Deploy backend files
echo "Deploying backend files..."
scp "${SCRIPT_DIR}/root/etc/uci-defaults/80_captive-portal" \
    "root@${DEVICE}:/etc/uci-defaults/"
scp "${SCRIPT_DIR}/root/usr/lib/captive-portal/binauth.sh" \
    "root@${DEVICE}:/usr/lib/captive-portal/"
scp "${SCRIPT_DIR}/root/usr/share/luci/menu.d/luci-app-captive-portal.json" \
    "root@${DEVICE}:/usr/share/luci/menu.d/"
scp "${SCRIPT_DIR}/root/usr/share/rpcd/acl.d/luci-app-captive-portal.json" \
    "root@${DEVICE}:/usr/share/rpcd/acl.d/"
scp "${SCRIPT_DIR}/root/usr/share/rpcd/ucode/captive-portal.uc" \
    "root@${DEVICE}:/usr/share/rpcd/ucode/"

# Set permissions and run setup
echo "Running setup..."
ssh "root@${DEVICE}" << 'EOF'
chmod +x /usr/lib/captive-portal/binauth.sh
sh /etc/uci-defaults/80_captive-portal
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
EOF

echo ""
echo "=== Deployment Complete ==="
echo "Access LuCI at: http://${DEVICE}/cgi-bin/luci/admin/services/captive-portal/"
echo ""
echo "Note: Log out and back into LuCI to clear the cache."
