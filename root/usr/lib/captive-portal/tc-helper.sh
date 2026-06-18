#!/bin/sh
# Traffic control helper for captive-portal
# Manages per-client bandwidth limits using tc (traffic control)
#
# Usage: tc-helper.sh <action> <ip> <mac> <upload_kbit> <download_kbit>
# Actions: add, remove

set -e

IFACE="br-guest"
IFB_DEV="ifb0"
ROOT_HANDLE="1:"
BASE_CLASSID="1:1"
# Class IDs start from 1:100 to avoid conflicts
CLASSID_BASE=100

log() {
    logger -t captive-portal-tc "$@"
}

# Convert MAC to class ID suffix (use last octet + second-to-last octet, mod 1000)
mac_to_classid() {
    local mac="$1"
    # Extract last 2 octets
    local last=$(echo "$mac" | awk -F: '{print $6}')
    local second_last=$(echo "$mac" | awk -F: '{print $5}')
    # Convert hex to decimal
    local last_dec=$(printf "%d" "0x$last" 2>/dev/null || echo "1")
    local second_last_dec=$(printf "%d" "0x$second_last" 2>/dev/null || echo "1")
    # Combine and mod to get range 100-999
    local combined=$(( (last_dec + second_last_dec * 256) % 900 + 100 ))
    echo "$combined"
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
    
    # Flush existing qdisc on IFB
    tc qdisc del dev "$IFB_DEV" root 2>/dev/null || true
    
    # Add root HTB qdisc on IFB for ingress shaping
    tc qdisc add dev "$IFB_DEV" root handle "$ROOT_HANDLE" htb default 9999
    tc class add dev "$IFB_DEV" parent "$ROOT_HANDLE" classid "$BASE_CLASSID" htb rate 1000mbit ceil 1000mbit
    tc qdisc add dev "$IFB_DEV" parent "$BASE_CLASSID" handle 100: pfifo_fast
}

# Setup root qdisc on interface
setup_root_qdisc() {
    # Remove existing qdisc
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    
    # Add root HTB qdisc
    tc qdisc add dev "$IFACE" root handle "$ROOT_HANDLE" htb default 9999
    
    # Add default class (unlimited)
    tc class add dev "$IFACE" parent "$ROOT_HANDLE" classid "$BASE_CLASSID" htb rate 1000mbit ceil 1000mbit
    tc qdisc add dev "$IFACE" parent "$BASE_CLASSID" handle 100: pfifo_fast
    
    # Setup IFB for ingress
    setup_ifb
    
    # Redirect ingress to IFB
    tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
    tc qdisc add dev "$IFACE" ingress
    tc filter add dev "$IFACE" parent ffff: protocol all u32 match u32 0 0 action mirred egress redirect dev "$IFB_DEV"
}

# Add traffic shaping for a client
add_client() {
    local ip="$1"
    local mac="$2"
    local upload_kbit="$3"
    local download_kbit="$4"
    
    # Ensure root qdisc exists
    tc qdisc show dev "$IFACE" | grep -q "htb" || setup_root_qdisc
    
    # Calculate class ID from MAC
    local class_num=$(mac_to_classid "$mac")
    local classid="${ROOT_HANDLE}${class_num}"
    local handle_num=$((class_num + 100))
    
    # Convert kbit to bytes for tc (tc uses bits, but we specify kbit)
    # Ensure minimum rate
    [ "$upload_kbit" -lt 64 ] 2>/dev/null && upload_kbit=64
    [ "$download_kbit" -lt 64 ] 2>/dev/null && download_kbit=64
    
    log "Adding tc rules for $ip ($mac): upload=${upload_kbit}kbit download=${download_kbit}kbit"
    
    # Egress (download from client perspective = traffic going TO client)
    # Add class for this client
    tc class add dev "$IFACE" parent "$BASE_CLASSID" classid "$classid" \
        htb rate "${download_kbit}kbit" ceil "${download_kbit}kbit" burst 15k 2>/dev/null || {
        log "Failed to add egress class for $ip"
        return 1
    }
    
    # Add pfifo_fast qdisc for the class
    tc qdisc add dev "$IFACE" parent "$classid" handle "${handle_num}:" pfifo_fast 2>/dev/null || true
    
    # Add filter to match client IP
    tc filter add dev "$IFACE" parent "$ROOT_HANDLE" protocol ip prio 1 \
        u32 match ip dst "$ip/32" flowid "$classid" 2>/dev/null || {
        log "Failed to add egress filter for $ip"
    }
    
    # Ingress (upload from client perspective = traffic coming FROM client)
    # Traffic is redirected to IFB, so we shape on IFB
    # Add class on IFB
    tc class add dev "$IFB_DEV" parent "$BASE_CLASSID" classid "$classid" \
        htb rate "${upload_kbit}kbit" ceil "${upload_kbit}kbit" burst 15k 2>/dev/null || {
        log "Failed to add ingress class for $ip"
        return 1
    }
    
    # Add pfifo_fast qdisc for the class on IFB
    tc qdisc add dev "$IFB_DEV" parent "$classid" handle "${handle_num}:" pfifo_fast 2>/dev/null || true
    
    # Add filter on IFB to match client IP (source IP after redirect)
    tc filter add dev "$IFB_DEV" parent "$ROOT_HANDLE" protocol ip prio 1 \
        u32 match ip src "$ip/32" flowid "$classid" 2>/dev/null || {
        log "Failed to add ingress filter for $ip"
    }
    
    log "Successfully added tc rules for $ip"
}

# Remove traffic shaping for a client
remove_client() {
    local ip="$1"
    local mac="$2"
    
    local class_num=$(mac_to_classid "$mac")
    local classid="${ROOT_HANDLE}${class_num}"
    local handle_num=$((class_num + 100))
    
    log "Removing tc rules for $ip ($mac)"
    
    # Remove egress filter
    tc filter del dev "$IFACE" parent "$ROOT_HANDLE" protocol ip prio 1 \
        u32 match ip dst "$ip/32" 2>/dev/null || true
    
    # Remove egress qdisc
    tc qdisc del dev "$IFACE" parent "$classid" 2>/dev/null || true
    
    # Remove egress class
    tc class del dev "$IFACE" classid "$classid" 2>/dev/null || true
    
    # Remove ingress filter on IFB
    tc filter del dev "$IFB_DEV" parent "$ROOT_HANDLE" protocol ip prio 1 \
        u32 match ip src "$ip/32" 2>/dev/null || true
    
    # Remove ingress qdisc on IFB
    tc qdisc del dev "$IFB_DEV" parent "$classid" 2>/dev/null || true
    
    # Remove ingress class on IFB
    tc class del dev "$IFB_DEV" classid "$classid" 2>/dev/null || true
    
    log "Successfully removed tc rules for $ip"
}

# Main
ACTION="$1"
IP="$2"
MAC="$3"
UPLOAD_KBIT="$4"
DOWNLOAD_KBIT="$5"

# Validate inputs
[ -z "$ACTION" ] && { echo "Usage: $0 <add|remove|setup> [ip] [mac] [upload_kbit] [download_kbit]"; exit 1; }

case "$ACTION" in
    add)
        [ -z "$IP" ] && { echo "IP required for add"; exit 1; }
        [ -z "$MAC" ] && { echo "MAC required for add"; exit 1; }
        [ -z "$UPLOAD_KBIT" ] && UPLOAD_KBIT=1000
        [ -z "$DOWNLOAD_KBIT" ] && DOWNLOAD_KBIT=1000
        add_client "$IP" "$MAC" "$UPLOAD_KBIT" "$DOWNLOAD_KBIT"
        ;;
    remove)
        [ -z "$IP" ] && IP="0.0.0.0"
        [ -z "$MAC" ] && { echo "MAC required for remove"; exit 1; }
        remove_client "$IP" "$MAC"
        ;;
    setup)
        setup_root_qdisc
        log "Root qdisc setup complete"
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo "Usage: $0 <add|remove|setup> [ip] [mac] [upload_kbit] [download_kbit]"
        exit 1
        ;;
esac

exit 0
