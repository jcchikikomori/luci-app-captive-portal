#!/bin/sh

# BinAuth script for luci-app-captive-portal
# Authenticates clients against UCI guest accounts
# No external dependencies (no jq, no curl, no API)

METHOD="$1"
ARG2="$2"
ARG3="$3"
ARG4="$4"
ARG5="$5"

LOG_DIR="/tmp/captive-portal"
LOG_FILE="$LOG_DIR/binauth.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$METHOD] $*" >> "$LOG_FILE" 2>/dev/null || true
}

normalize_mac() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

case "$METHOD" in
auth_client)
    # Determine argument order based on MAC format
    if echo "$ARG3" | grep -Eq '^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'; then
        CLIENTMAC="$ARG3"
        USERNAME="$ARG4"
        PASSWORD="$ARG5"
    elif echo "$ARG2" | grep -Eq '^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'; then
        CLIENTMAC="$ARG2"
        USERNAME="$ARG3"
        PASSWORD="$ARG4"
    else
        CLIENTMAC="$ARG2"
        USERNAME="$ARG3"
        PASSWORD="$ARG4"
    fi

    NORM_MAC=$(normalize_mac "$CLIENTMAC")
    log_msg "Auth request: MAC=$NORM_MAC user=$USERNAME"

    # Read all enabled guest accounts from UCI
    SECTIONS=$(uci show captive-portal 2>/dev/null | grep '=guest$' | cut -d. -f2 | cut -d= -f1)

    FOUND_MATCH=0
    MATCHED_MAC=0

    for SECTION in $SECTIONS; do
        ENABLED=$(uci get captive-portal.$SECTION.enabled 2>/dev/null)
        [ "$ENABLED" != "1" ] && continue

        STORED_USER=$(uci get captive-portal.$SECTION.username 2>/dev/null)
        STORED_PASS=$(uci get captive-portal.$SECTION.password 2>/dev/null)
        STORED_MAC=$(uci get captive-portal.$SECTION.mac 2>/dev/null)
        TIMEOUT=$(uci get captive-portal.$SECTION.timeout 2>/dev/null)
        UPLOAD=$(uci get captive-portal.$SECTION.upload_limit 2>/dev/null)
        DOWNLOAD=$(uci get captive-portal.$SECTION.download_limit 2>/dev/null)

        STORED_MAC_NORM=$(normalize_mac "$STORED_MAC")

        if [ "$USERNAME" = "$STORED_USER" ] && [ "$PASSWORD" = "$STORED_PASS" ]; then
            log_msg "Credentials matched for user '$USERNAME'"

            # Check MAC binding
            if [ -z "$STORED_MAC" ]; then
                # No MAC binding - allow
                log_msg "No MAC binding, allowing MAC=$NORM_MAC"
                echo "$TIMEOUT $UPLOAD $DOWNLOAD"
                exit 0
            elif [ "$NORM_MAC" = "$STORED_MAC_NORM" ]; then
                # MAC matches - allow
                log_msg "MAC matched, allowing MAC=$NORM_MAC"
                echo "$TIMEOUT $UPLOAD $DOWNLOAD"
                exit 0
            else
                # MAC mismatch
                FOUND_MATCH=1
                MATCHED_MAC=0
                log_msg "MAC mismatch: client=$NORM_MAC account=$STORED_MAC_NORM"
            fi
        fi
    done

    if [ $FOUND_MATCH -eq 1 ] && [ $MATCHED_MAC -eq 0 ]; then
        log_msg "Auth denied for '$USERNAME': MAC mismatch"
        echo "Access denied: MAC address does not match account"
        exit 1
    fi

    log_msg "Auth denied for '$USERNAME': invalid credentials"
    echo "Authentication failed"
    exit 1
    ;;

client_auth)
    log_msg "Client authenticated: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4"
    ;;

client_deauth)
    log_msg "Client deauthenticated: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4"
    ;;

idle_deauth)
    log_msg "Client idle timeout: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4"
    ;;

timeout_deauth)
    log_msg "Client session timeout: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4"
    ;;

ndsctl_auth)
    log_msg "Client authenticated via ndsctl: MAC=$ARG2"
    ;;

ndsctl_deauth)
    log_msg "Client deauthenticated via ndsctl: MAC=$ARG2"
    ;;

shutdown_deauth)
    log_msg "Client deauthenticated due to shutdown: MAC=$ARG2"
    ;;

*)
    log_msg "Unknown method: $METHOD"
    ;;
esac

exit 0
