#!/bin/sh

# BinAuth script for luci-app-captive-portal
# Logging-only post-authentication hook for openNDS. openNDS invokes BinAuth
# strictly after an authentication decision has already been made; it cannot
# gate, approve, or deny a client login. Credential validation happens in the
# fas_auth ubus method (root/usr/share/rpcd/ucode/captive-portal.uc) before
# openNDS ever calls this script.
# No external dependencies (no jq, no curl, no API)

METHOD="$1"
ARG2="$2"
ARG3="$3"
ARG4="$4"
ARG5="$5"
ARG6="$6"
ARG7="$7"

LOG_DIR="/tmp/captive-portal"
LOG_FILE="$LOG_DIR/binauth.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

log_msg() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') [$METHOD] $*" >> "$LOG_FILE" 2>/dev/null || true
}

case "$METHOD" in
auth_client)
	# openNDS: auth_client <client_mac> <username> <password> <redir> <user_agent> <client_ip> <client_token> <custom>
	# username/password are deprecated by openNDS and ignored here; this
	# method's return value has no effect on whether the client is granted
	# access (see header comment).
	log_msg "auth_client notification (post-auth handled by fas_auth ubus method): MAC=$ARG2"
	;;

client_auth)
	log_msg "Client authenticated: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4 session_start=$ARG5 session_end=$ARG6 token=$ARG7"
	;;

client_deauth)
	log_msg "Client deauthenticated: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4 session_start=$ARG5 session_end=$ARG6 token=$ARG7"
	;;

idle_deauth)
	log_msg "Client idle timeout: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4 session_start=$ARG5 session_end=$ARG6 token=$ARG7"
	;;

timeout_deauth)
	log_msg "Client session timeout: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4 session_start=$ARG5 session_end=$ARG6 token=$ARG7"
	;;

downquota_deauth)
	log_msg "Client download quota exceeded: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4 session_start=$ARG5 session_end=$ARG6 token=$ARG7"
	;;

upquota_deauth)
	log_msg "Client upload quota exceeded: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4 session_start=$ARG5 session_end=$ARG6 token=$ARG7"
	;;

shutdown_deauth)
	log_msg "Client deauthenticated due to shutdown: MAC=$ARG2 bytes_in=$ARG3 bytes_out=$ARG4 session_start=$ARG5 session_end=$ARG6 token=$ARG7"
	;;

*)
	log_msg "Unknown method: $METHOD"
	;;
esac

exit 0
