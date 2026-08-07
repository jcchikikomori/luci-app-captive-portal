#!/bin/sh
# Global traffic control for captive-portal
# Applies a single rate limit on the guest interface based on service defaults
#
# Usage: tc-helper.sh <action>
# Actions: apply, remove

set -e

IFACE="br-guest"
IFB_DEV="ifb0"

log() {
    logger -t captive-portal-tc "$@"
}

# Get service default limits from UCI (in bytes)
get_limits() {
    local upload_bytes=$(uci -q get captive-portal.@service[0].default_upload_limit)
    local download_bytes=$(uci -q get captive-portal.@service[0].default_download_limit)

    # Default to 0 (unlimited) if not set
    [ -z "$upload_bytes" ] && upload_bytes=0
    [ -z "$download_bytes" ] && download_bytes=0

    # Convert bytes to kbit/s: (bytes * 8) / 1000
    local upload_kbit=$(( (upload_bytes * 8) / 1000 ))
    local download_kbit=$(( (download_bytes * 8) / 1000 ))

    # If 0, use a very high value (effectively unlimited)
    [ "$upload_kbit" -eq 0 ] && upload_kbit=1000000
    [ "$download_kbit" -eq 0 ] && download_kbit=1000000

    echo "$upload_kbit $download_kbit"
}

# Setup IFB device for ingress shaping
setup_ifb() {
    # Load ifb module if not loaded
    modprobe ifb numifbs=1 2>/dev/null || true

    # Bring up IFB device if not already up
    ip link show "$IFB_DEV" >/dev/null 2>&1 || {
        ip link add "$IFB_DEV" type ifb
        ip link set "$IFB_DEV" up
    }
}

# Apply global rate limit
apply() {
    local limits=$(get_limits)
    local upload_kbit=$(echo "$limits" | awk '{print $1}')
    local download_kbit=$(echo "$limits" | awk '{print $2}')

    log "Applying global rate limit: upload=${upload_kbit}kbit download=${download_kbit}kbit"

    # Remove existing qdiscs
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
    tc qdisc del dev "$IFB_DEV" root 2>/dev/null || true

    # Setup IFB for ingress shaping
    setup_ifb

    # Apply egress limit (download from client perspective)
    tc qdisc add dev "$IFACE" root handle 1: htb default 1
    tc class add dev "$IFACE" parent 1: classid 1:1 htb rate ${download_kbit}kbit ceil ${download_kbit}kbit burst 15k

    # Redirect ingress to IFB for upload shaping
    tc qdisc add dev "$IFACE" ingress
    tc filter add dev "$IFACE" parent ffff: protocol all u32 match u32 0 0 action mirred egress redirect dev "$IFB_DEV"

    # Apply ingress limit (upload from client perspective)
    tc qdisc add dev "$IFB_DEV" root handle 1: htb default 1
    tc class add dev "$IFB_DEV" parent 1: classid 1:1 htb rate ${upload_kbit}kbit ceil ${upload_kbit}kbit burst 15k

    log "Global rate limit applied successfully"
}

# Remove rate limits
remove() {
    log "Removing global rate limit"
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
    tc qdisc del dev "$IFB_DEV" root 2>/dev/null || true
    log "Global rate limit removed"
}

# Main
ACTION="$1"

case "$ACTION" in
    apply)
        apply
        ;;
    remove)
        remove
        ;;
    *)
        echo "Usage: $0 <apply|remove>"
        exit 1
        ;;
esac

exit 0
