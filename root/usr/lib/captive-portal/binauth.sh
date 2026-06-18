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
	echo "$1" | tr 'a-z' 'A-Z'
}

case "$METHOD" in
auth_client)
	# Determine argument order based on MAC format.
	# nodogsplash: auth_client <client_mac> '<username>' '<password>'
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

	# Check blocked MAC list before any account lookup.
	BLOCKED_SECTIONS=$(uci show captive-portal 2>/dev/null | grep '=blocked$' | cut -d. -f2 | cut -d= -f1)
	for BLOCKED in $BLOCKED_SECTIONS; do
		BLOCKED_ENABLED=$(uci get captive-portal.$BLOCKED.enabled 2>/dev/null)
		[ "$BLOCKED_ENABLED" != "1" ] && continue
		BLOCKED_MAC=$(uci get captive-portal.$BLOCKED.mac 2>/dev/null)
		BLOCKED_MAC_NORM=$(normalize_mac "$BLOCKED_MAC")
		if [ -n "$BLOCKED_MAC_NORM" ] && [ "$NORM_MAC" = "$BLOCKED_MAC_NORM" ]; then
			log_msg "Auth denied: MAC=$NORM_MAC is blocked"
			exit 1
		fi
	done

	DEFAULT_AUTH_METHOD=$(uci get captive-portal.@service[0].auth_method 2>/dev/null)
	[ -z "$DEFAULT_AUTH_METHOD" ] && DEFAULT_AUTH_METHOD='both'

	SECTIONS=$(uci show captive-portal 2>/dev/null | grep '=guest$' | cut -d. -f2 | cut -d= -f1)

	CRED_MATCH=0
	MAC_MATCH=0
	ALLOWED=0

	for SECTION in $SECTIONS; do
		ENABLED=$(uci get captive-portal.$SECTION.enabled 2>/dev/null)
		[ "$ENABLED" != "1" ] && continue

		STORED_USER=$(uci get captive-portal.$SECTION.username 2>/dev/null)
		STORED_PASS=$(uci get captive-portal.$SECTION.password 2>/dev/null)
		STORED_MAC=$(uci get captive-portal.$SECTION.mac 2>/dev/null)
		TIMEOUT=$(uci get captive-portal.$SECTION.timeout 2>/dev/null)
		UPLOAD=$(uci get captive-portal.$SECTION.upload_limit 2>/dev/null)
		DOWNLOAD=$(uci get captive-portal.$SECTION.download_limit 2>/dev/null)
		AUTH_METHOD=$(uci get captive-portal.$SECTION.auth_method 2>/dev/null)
		[ -z "$AUTH_METHOD" ] && AUTH_METHOD="$DEFAULT_AUTH_METHOD"

		STORED_MAC_NORM=$(normalize_mac "$STORED_MAC")

		[ -z "$TIMEOUT" ] && TIMEOUT='1200'
		[ -z "$UPLOAD" ] && UPLOAD='0'
		[ -z "$DOWNLOAD" ] && DOWNLOAD='0'

		case "$AUTH_METHOD" in
		password)
			if [ "$USERNAME" = "$STORED_USER" ] && [ "$PASSWORD" = "$STORED_PASS" ]; then
				log_msg "Password auth matched for user '$USERNAME'"
				echo "$TIMEOUT $UPLOAD $DOWNLOAD"
				exit 0
			fi
			;;
		mac)
			if [ -n "$STORED_MAC" ] && [ "$NORM_MAC" = "$STORED_MAC_NORM" ]; then
				log_msg "MAC auth matched for MAC=$NORM_MAC"
				echo "$TIMEOUT $UPLOAD $DOWNLOAD"
				exit 0
			fi
			;;
		both)
			if [ "$USERNAME" = "$STORED_USER" ] && [ "$PASSWORD" = "$STORED_PASS" ]; then
				CRED_MATCH=1
				if [ -z "$STORED_MAC" ] || [ "$NORM_MAC" = "$STORED_MAC_NORM" ]; then
					log_msg "User/Password + MAC matched for user '$USERNAME'"
					echo "$TIMEOUT $UPLOAD $DOWNLOAD"
					exit 0
				else
					log_msg "MAC mismatch for user '$USERNAME': client=$NORM_MAC account=$STORED_MAC_NORM"
					MAC_MATCH=0
				fi
			fi
			;;
		esac
	done

	if [ "$DEFAULT_AUTH_METHOD" = "both" ] || [ "$DEFAULT_AUTH_METHOD" = "password" ]; then
		if [ $CRED_MATCH -eq 1 ]; then
			log_msg "Auth denied for '$USERNAME': MAC does not match account"
			exit 1
		fi
	fi

	log_msg "Auth denied for '$USERNAME': no matching account"
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
