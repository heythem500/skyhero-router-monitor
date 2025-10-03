#!/bin/ash
set -eu

#
# get_device_apps.sh
# CGI script to get the top applications for a single device over a given period.
#

# --- Robustly determine BASE_DIR and source config ---
SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [ "$SOURCE" != /* ] && SOURCE="$DIR/$SOURCE"
done
SCRIPTS_DIR_WWW="$(cd -P "$(dirname "$SOURCE")" && pwd)"
BASE_DIR="$(cd "$SCRIPTS_DIR_WWW/.." && pwd)"

. "$BASE_DIR/scripts/config.sh"
. "$BASE_DIR/scripts/helpers.sh"

# --- Main Logic ---
# Do all processing first, store the result in a variable.

# Extract parameters from the query string
MAC_ADDR=$(echo "$QUERY_STRING" | sed -n 's/.*mac=\([^&]*\).*/\1/p')
START_DATE=$(echo "$QUERY_STRING" | sed -n 's/.*start=\([^&]*\).*/\1/p')
END_DATE=$(echo "$QUERY_STRING" | sed -n 's/.*end=\([^&]*\).*/\1/p')

# Basic validation
if [ -z "$MAC_ADDR" ] || [ -z "$START_DATE" ] || [ -z "$END_DATE" ]; then
    JSON_OUTPUT='{"error": "Missing required parameters (mac, start_date, end_date)."}'
else
    # 1. Build a list of daily JSON files to process
    file_list=""
    epoch_start=$(epoch_from_ISO "$START_DATE")
    epoch_end=$(epoch_from_ISO "$END_DATE")

    cur=$epoch_start
    while [ "$(integer_add "$cur" 0)" -le "$(integer_add "$epoch_end" 0)" ]; do
        day=$(iso_from_epoch "$cur")
        f="$DAILY_DIR/$day.json"
        if [ -f "$f" ]; then
            file_list="$file_list $f"
        fi
        cur=$(integer_add "$cur" 86400)
    done

    # If no files are found, return an empty array
    if [ -z "$file_list" ]; then
        JSON_OUTPUT='{"apps": []}'
    else
        # Transform the file list into positional parameters for jq
        set -- $file_list

        # 2. Aggregate with jq
        JQ_SCRIPT_FILE="/tmp/jq_device_apps_$"
        trap 'rm -f "$JQ_SCRIPT_FILE"' EXIT

cat <<'EOF' > "$JQ_SCRIPT_FILE"
# Helper to convert bytes to GB, rounded to 2 decimal places.
def bytes_to_gb: . / 1073741824 | (.*100 | round) / 100;

# Helper function to rename/group common, generic traffic types
def rename_app:
  if . == "QUIC" or . == "SSL/TLS" or . == "General" or . == "HTTP Protocol over TLS SSL" then
    "Other Sources"
  else
    .
  end;

# Process the data
{
  apps: (
    # Go through each daily file provided
    [ .[] | .devices[] | select(.mac == $mac) | .topApps[]? ] # Added ? to handle missing topApps
    # Group by the (potentially renamed) app name
    | group_by(.name | rename_app)
    # Sum the total_bytes for each group
    | map({
        name: (.[0].name | rename_app),
        total_bytes: (map(.total_bytes) | add)
      })
    # Add the human-readable "total" field
    | map(. + { total: (.total_bytes | bytes_to_gb) })
    # Sort by the most traffic first
    | sort_by(-.total_bytes)
  )
}
EOF
        # Execute jq with the MAC address as an argument
        JSON_OUTPUT=$(jq -s --arg mac "$MAC_ADDR" -f "$JQ_SCRIPT_FILE" "$@")
    fi
fi

# --- CGI Output ---
# Print the header and then the JSON content all at once.
echo "Content-Type: application/json"
echo ""
echo "$JSON_OUTPUT"


