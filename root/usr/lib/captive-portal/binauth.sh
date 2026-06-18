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

# Convert bytes/s to Kbit/s for nodogsplash BinAuth output.
bytes_to_kbit() {
	local bytes="${1:-0}"
	if [ -z "$bytes" ] || [ "$bytes" -le 0 ] 2>/dev/null; then
		echo 0
	else
		echo $(( (bytes * 8) / 1000 ))
	fi
}

# Get client IP from MAC using ndsctl json
get_client_ip() {
	local mac="$1"
	local norm_mac=$(normalize_mac "$mac")
	# Use ndsctl json to get client info
	local json=$(ndsctl json 2>/dev/null)
	if [ -n "$json" ]; then
		# Parse JSON to find client with matching MAC
		# Format: {"clients":[{"ip":"x.x.x.x","mac":"XX:XX:XX:XX:XX:XX",...}]}
		echo "$json" | grep -o '"ip":"[^"]*","mac":"[^"]*"' | while read -r line; do
			local ip=$(echo "$line" | sed 's/"ip":"\([^"]*\)".*/\1/')
			local client_mac=$(echo "$line" | sed 's/.*"mac":"\([^"]*\)".*/\1/' | tr 'a-z' 'A-Z')
			if [ "$client_mac" = "$norm_mac" ]; then
				echo "$ip"
				return
			fi
		done
	fi
	# Fallback: check ARP table
	ip neigh show | grep -i "$mac" | awk '{print $1}' | head -1
}

# Apply traffic control for authenticated client
apply_tc() {
	local mac="$1"
	local ip=$(get_client_ip "$mac")
	if [ -z "$ip" ]; then
		log_msg "TC: Could not find IP for MAC=$mac"
		return 1
	fi
	
	# Get limits from UCI for this client's account
	# We need to find which account authenticated this client
	# For now, use service defaults (the auth_client already determined limits)
	local upload_bytes=$(uci get captive-portal.@service[0].default_upload_limit 2>/dev/null)
	local download_bytes=$(uci get captive-portal.@service[0].default_download_limit 2>/dev/null)
	[ -z "$upload_bytes" ] && upload_bytes=0
	[ -z "$download_bytes" ] && download_bytes=0
	
	# Check if client has a specific account with limits
	local sections=$(uci show captive-portal 2>/dev/null | grep '=guest$' | cut -d. -f2 | cut -d= -f1)
	for section in $sections; do
		local enabled=$(uci get captive-portal.$section.enabled 2>/dev/null)
		[ "$enabled" != "1" ] && continue
		local stored_mac=$(uci get captive-portal.$section.mac 2>/dev/null)
		local stored_mac_norm=$(normalize_mac "$stored_mac")
		if [ -n "$stored_mac" ] && [ "$stored_mac_norm" = "$(normalize_mac "$mac")" ]; then
			local ul=$(uci get captive-portal.$section.upload_limit 2>/dev/null)
			local dl=$(uci get captive-portal.$section.download_limit 2>/dev/null)
			[ -n "$ul" ] && [ "$ul" != "0" ] && upload_bytes=$ul
			[ -n "$dl" ] && [ "$dl" != "0" ] && download_bytes=$dl
			break
		fi
	done
	
	local upload_kbit=$(bytes_to_kbit "$upload_bytes")
	local download_kbit=$(bytes_to_kbit "$download_bytes")
	
	# Minimum 64 kbit to avoid tc errors
	[ "$upload_kbit" -lt 64 ] 2>/dev/null && upload_kbit=64
	[ "$download_kbit" -lt 64 ] 2>/dev/null && download_kbit=64
	
	log_msg "TC: Applying limits for $ip ($mac): upload=${upload_kbit}kbit download=${download_kbit}kbit"
	/usr/lib/captive-portal/tc-helper.sh add "$ip" "$mac" "$upload_kbit" "$download_kbit" 2>&1 | while read -r line; do
		log_msg "TC: $line"
	done
}

# Remove traffic control for deauthenticated client
remove_tc() {
	local mac="$1"
	local ip=$(get_client_ip "$mac")
	if [ -z "$ip" ]; then
		# Client already removed from ndsctl, try ARP or just use MAC
		log_msg "TC: Client $mac already removed, attempting cleanup by MAC only"
		/usr/lib/captive-portal/tc-helper.sh remove "0.0.0.0" "$mac" 2>&1 | while read -r line; do
			log_msg "TC: $line"
		done
		return
	fi
	log_msg "TC: Removing limits for $ip ($mac)"
	/usr/lib/captive-portal/tc-helper.sh remove "$ip" "$mac" 2>&1 | while read -r line; do
		log_msg "TC: $line"
	done
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

	DEFAULT_TIMEOUT=$(uci get captive-portal.@service[0].default_timeout 2>/dev/null)
	DEFAULT_UPLOAD=$(uci get captive-portal.@service[0].default_upload_limit 2>/dev/null)
	DEFAULT_DOWNLOAD=$(uci get captive-portal.@service[0].default_download_limit 2>/dev/null)
	[ -z "$DEFAULT_TIMEOUT" ] && DEFAULT_TIMEOUT='1200'
	[ -z "$DEFAULT_UPLOAD" ] && DEFAULT_UPLOAD='0'
	[ -z "$DEFAULT_DOWNLOAD" ] && DEFAULT_DOWNLOAD='0'

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

		[ -z "$TIMEOUT" ] || [ "$TIMEOUT" = "0" ] && TIMEOUT="$DEFAULT_TIMEOUT"
		[ -z "$UPLOAD" ] || [ "$UPLOAD" = "0" ] && UPLOAD="$DEFAULT_UPLOAD"
		[ -z "$DOWNLOAD" ] || [ "$DOWNLOAD" = "0" ] && DOWNLOAD="$DEFAULT_DOWNLOAD"

		UPLOAD_KBIT=$(bytes_to_kbit "$UPLOAD")
		DOWNLOAD_KBIT=$(bytes_to_kbit "$DOWNLOAD")

		case "$AUTH_METHOD" in
		password)
			if [ "$USERNAME" = "$STORED_USER" ] && [ "$PASSWORD" = "$STORED_PASS" ]; then
				log_msg "Password auth matched for user '$USERNAME' (timeout=$TIMEOUT upload=${UPLOAD_KBIT}Kbit download=${DOWNLOAD_KBIT}Kbit)"
				echo "$TIMEOUT $UPLOAD_KBIT $DOWNLOAD_KBIT"
				exit 0
			fi
			;;
		mac)
			if [ -n "$STORED_MAC" ] && [ "$NORM_MAC" = "$STORED_MAC_NORM" ]; then
				log_msg "MAC auth matched for MAC=$NORM_MAC (timeout=$TIMEOUT upload=${UPLOAD_KBIT}Kbit download=${DOWNLOAD_KBIT}Kbit)"
				echo "$TIMEOUT $UPLOAD_KBIT $DOWNLOAD_KBIT"
				exit 0
			fi
			;;
		both)
			if [ "$USERNAME" = "$STORED_USER" ] && [ "$PASSWORD" = "$STORED_PASS" ]; then
				CRED_MATCH=1
				if [ -z "$STORED_MAC" ] || [ "$NORM_MAC" = "$STORED_MAC_NORM" ]; then
					log_msg "User/Password + MAC matched for user '$USERNAME' (timeout=$TIMEOUT upload=${UPLOAD_KBIT}Kbit download=${DOWNLOAD_KBIT}Kbit)"
					echo "$TIMEOUT $UPLOAD_KBIT $DOWNLOAD_KBIT"
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
	apply_tc "$ARG2"
	;;

client_deauth)
	log_msg "Client deauthenticated: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4"
	remove_tc "$ARG2"
	;;

idle_deauth)
	log_msg "Client idle timeout: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4"
	remove_tc "$ARG2"
	;;

timeout_deauth)
	log_msg "Client session timeout: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4"
	remove_tc "$ARG2"
	;;

ndsctl_auth)
	log_msg "Client authenticated via ndsctl: MAC=$ARG2"
	apply_tc "$ARG2"
	;;

ndsctl_deauth)
	log_msg "Client deauthenticated via ndsctl: MAC=$ARG2"
	remove_tc "$ARG2"
	;;

shutdown_deauth)
	log_msg "Client deauthenticated due to shutdown: MAC=$ARG2"
	remove_tc "$ARG2"
	;;

*)
	log_msg "Unknown method: $METHOD"
	;;
esac

exit 0
