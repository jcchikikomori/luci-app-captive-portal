#!/bin/sh
# Sync the captive-portal blocked MAC list to a static JSON file
# that the splash page can read before authentication.

JSON_FILE="/www/captive-portal/blocked.json"
TMP_FILE="${JSON_FILE}.tmp"

mkdir -p "$(dirname "$JSON_FILE")" 2>/dev/null || true

printf '%s' '{"blocked":[' > "$TMP_FILE"

FIRST=1
BLOCKED_SECTIONS=$(uci show captive-portal 2>/dev/null | grep '=blocked$' | cut -d. -f2 | cut -d= -f1)

for SECTION in $BLOCKED_SECTIONS; do
	ENABLED=$(uci get captive-portal.$SECTION.enabled 2>/dev/null)
	[ "$ENABLED" != "1" ] && continue

	MAC=$(uci get captive-portal.$SECTION.mac 2>/dev/null | tr 'a-z' 'A-Z')
	[ -z "$MAC" ] && continue

	if [ "$FIRST" -eq 1 ]; then
		FIRST=0
	else
		printf ',' >> "$TMP_FILE"
	fi

	printf '"%s"' "$MAC" >> "$TMP_FILE"
done

printf ']}' >> "$TMP_FILE"
mv "$TMP_FILE" "$JSON_FILE"
