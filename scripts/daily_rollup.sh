#!/bin/ash
#
# Creates a single, immutable JSON file for a given calendar day.
# This is the core data-gathering script.
#

############################################################
# BusyBox-safe helpers 
############################################################

# Ensure we are running under ash

# ---------- integer_add  (posix calc without $(( )) ) ----------
integer_add() { awk "BEGIN{print $1 + $2}"; }

# ---------- epoch_from_ISO  (YYYY-MM-DD 
epoch_from_ISO() {
    # BusyBox date understands “-d”, but some builds don’t; fall back to awk
    if date -d "$1 00:00:00" +%s >/dev/null 2>&1; then
        date -d "$1 00:00:00" +%s
    else
        # Lightweight POSIX fallback
        year=$(echo "$1" | cut -d'-' -f1); mon=$(echo "$1" | cut -d'-' -f2); day=$(echo "$1" | cut -d'-' -f3)
        awk -v y=$year -v m=$mon -v d=$day << 'AWK_SCRIPT_END'
          BEGIN{
            mdays[1]=31;mdays[2]=28;mdays[3]=31;mdays[4]=30;mdays[5]=31;mdays[6]=30;
            mdays[7]=31;mdays[8]=31;mdays[9]=30;mdays[10]=31;mdays[11]=30;mdays[12]=31;
            secs=0
            for (yr=1970; yr<y; yr++){
               leap=((yr%4==0 && yr%100!=0)|| yr%400==0)
               secs+= (leap?366:365)*86400
            }
            leap=((y%4==0 && y%100!=0)|| y%400==0)
            mdays[2]=leap?29:28
            for (i=1;i<m;i++) secs+=mdays[i]*86400
            secs+=(d-1)*86400
            print secs
          }
AWK_SCRIPT_END
    fi
}

# ---------- ISO_from_epoch  (seconds 
iso_from_epoch() { awk -v ts="$1" 'BEGIN { print strftime("%Y-%m-%d", ts) }'; }

# ---------- yesterday() – returns yesterday’s ISO date ----------
yesterday() {
    now=$(date +%s)
    epoch_yest=$(integer_add "$now" -86400)
    iso_from_epoch "$epoch_yest"
}

############################################################
#                ←  END OF HELPER BLOCK                   #
############################################################

export BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Source the central configuration.
# Source the central configuration.
. "$BASE_DIR/scripts/config.sh"
. "$SCRIPTS_DIR/helpers.sh"

# --- Sanity Checks & Logging Setup ---
# Ensure critical directories are defined and exist before we do anything else.
if [ -z "$LOGS_DIR" ] || [ -z "$DAILY_DIR" ]; then
    # We can't use a log file if LOGS_DIR is missing, so output to stderr and hope cron captures it.
    echo "[$(date)] CRITICAL: LOGS_DIR or DAILY_DIR is not defined in daily_rollup.sh. Exiting." >&2
    exit 1
fi
mkdir -p "$LOGS_DIR"
mkdir -p "$DAILY_DIR"

# Create a specific log file for this script and redirect all output there.
ROLLUP_LOG_FILE="$LOGS_DIR/daily_rollup.log"
exec >> "$ROLLUP_LOG_FILE" 2>&1

# Write a definitive log entry to show the script started with its arguments.
echo "[$(date)] --- daily_rollup.sh started for TARGET_DATE_INPUT: '${1:-}' ---"

restore_live_db_if_needed

# --- Argument Handling ---
TARGET_DATE_INPUT="${1:-}" # Added default empty value for safety
DB_SOURCE="${2:-$LIVE_DB}"

if [ -z "$TARGET_DATE_INPUT" ]; then
    echo "Usage: $0 YYYY-MM-DD|today|yesterday [path_to_db]" >&2
    exit 1
fi

# Resolve keywords to dates
if [ "$TARGET_DATE_INPUT" = "today" ]; then
    TARGET_DATE=$(date +%F)
elif [ "$TARGET_DATE_INPUT" = "yesterday" ]; then
    TARGET_DATE=$(yesterday) # Use the helper function we already have
else
    TARGET_DATE="$TARGET_DATE_INPUT"
fi

# --- Setup ---
TMP_DIR="/tmp/rollup_$$"
mkdir -p "$TMP_DIR"

TMP_DB="$TMP_DIR/db.sqlite"
TMP_STATS="$TMP_DIR/stats.txt"
TMP_DEVICES="$TMP_DIR/devices.txt"
TMP_APPS="$TMP_DIR/apps.txt"
TMP_MACS="$TMP_DIR/macs.txt"
TMP_NAMES="$TMP_DIR/names.txt"
TMP_DEVICE_APPS="$TMP_DIR/device_apps.txt" # New temp file
JQ_SCRIPT_FILE="$TMP_DIR/jq_program.jq" # Temp file for the jq script

FINAL_JSON_PATH="$DAILY_DIR/${TARGET_DATE}.json"
CHECKSUM_PATH="${FINAL_JSON_PATH}.sha256"

# --- Helper Functions ---
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cache_device_names() {
    > "$TMP_NAMES"
    cat "$TMP_MACS" | sort -u | while read -r mac; do
        search_mac=$(echo "$mac" | tr 'a-f' 'A-F')
        name=""
        custom_list=$(nvram get custom_clientlist 2>/dev/null || echo "")
        if [ -n "$custom_list" ]; then
            name=$(echo "$custom_list" | tr '<' '\n' | grep -i "$search_mac" | cut -d'>' -f1)
        fi
        if [ -z "$name" ]; then
            if [ -f /var/lib/misc/dnsmasq.leases ]; then
                dhcp_name=$(grep -i "$search_mac" /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print $4}' | tail -n 1)
                if [ "$dhcp_name" != "*" ] && [ -n "$dhcp_name" ]; then
                    name="$dhcp_name"
                fi
            fi
        fi
        name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '*' | tr -d '"' | tr -d "\\")
        [ -z "$name" ] && name="Unknown Device"
        echo "$mac|$name" >> "$TMP_NAMES"
    done
}

# --- Main Logic ---

# 1. Prepare DB
if [ "$DB_SOURCE" = "$LIVE_DB" ]; then
    cp "$DB_SOURCE" "$TMP_DB"
else
    TMP_DB="$DB_SOURCE"
fi

# 2. Calculate Timestamps
# This is the robust, portable way to get a timestamp from a date string on BusyBox.
DAY_START_TS=$(epoch_from_ISO "$TARGET_DATE")
DAY_END_TS=$(integer_add "$DAY_START_TS" 86400)

# 3. Extract Data
sqlite3 "$TMP_DB" "SELECT SUM(rx), SUM(tx), SUM(rx+tx) FROM traffic WHERE timestamp >= $DAY_START_TS AND timestamp < $DAY_END_TS;" > "$TMP_STATS"
sqlite3 "$TMP_DB" "SELECT mac, SUM(rx), SUM(tx), SUM(rx+tx) FROM traffic WHERE timestamp >= $DAY_START_TS AND timestamp < $DAY_END_TS GROUP BY mac;" > "$TMP_DEVICES"
sqlite3 "$TMP_DB" "SELECT app_name, SUM(rx+tx) FROM traffic WHERE timestamp >= $DAY_START_TS AND timestamp < $DAY_END_TS GROUP BY app_name;" > "$TMP_APPS"
sqlite3 "$TMP_DB" "SELECT mac, app_name, SUM(rx+tx) FROM traffic WHERE timestamp >= $DAY_START_TS AND timestamp < $DAY_END_TS GROUP BY mac, app_name;" > "$TMP_DEVICE_APPS"
cut -d'|' -f1 "$TMP_DEVICES" > "$TMP_MACS"

# 4. Zero-Traffic Check
# If the stats file is empty or just contains nulls, there was no traffic.
if [ ! -s "$TMP_STATS" ] || [ "$(cat "$TMP_STATS")" = "||" ]; then
    echo "No traffic data for $TARGET_DATE. Writing zero-template." >&2
    # Create the zero-template JSON
    cat <<EOF > "$FINAL_JSON_PATH"
{
    "stats": {
        "traffic": 0, "dl": 0, "ul": 0, "devices": 0,
        "monthlyQuotaGB": $MONTHLY_QUOTA_GB
    },
    "barChart": { "title": "Daily Breakdown", "labels": ["$TARGET_DATE"], "values": [0] },
    "devices": [],
    "topApps": []
}
EOF
    # Generate checksum for the zero-template
    sha256sum "$FINAL_JSON_PATH" | awk '{print $1 "  " $2}' > "$CHECKSUM_PATH"
    # Exit successfully
    exit 0
fi

# If we are here, it means there IS traffic data. Proceed with name resolution and jq processing.
# 5. Resolve Names
cache_device_names

# 6. Create the jq program file using a 'here document'.
cat <<'EOF' > "$JQ_SCRIPT_FILE"
# Helper to convert bytes to GB, rounded to 2 decimal places.
def bytes_to_gb: . / 1073741824 | (.*100 | round) / 100;

# Process raw text files into jq variables.
($stats | split("|") | .[0] // "0" | tonumber) as $dl_bytes |
($stats | split("|") | .[1] // "0" | tonumber) as $ul_bytes |
($stats | split("|") | .[2] // "0" | tonumber) as $total_bytes |
($quota_gb | tonumber) as $quota |

# Create a lookup map for device names.
(reduce ($names | split("\n") | .[] | select(length > 0) | split("|")) as $parts ({}; .[$parts[0]] = $parts[1])) as $name_map |

# Create a nested structure for per-device app usage.
(reduce ($device_apps | split("\n") | .[] | select(length > 0) | split("|")) as $parts ({}; .[$parts[0]] += [{name: $parts[1], total_bytes: ($parts[2] | tonumber)}])) as $device_app_map |

# Construct the final JSON object.

{
    stats: {
        traffic: ($total_bytes | bytes_to_gb),
        dl: ($dl_bytes | bytes_to_gb),
        ul: ($ul_bytes | bytes_to_gb),
        devices: ([ $devices | split("\n") | .[] | select(length > 0) ] | length),
        monthlyQuotaGB: $quota
    },
    barChart: {
        title: "Daily Breakdown",
        labels: [$date],
        values: [($total_bytes | bytes_to_gb)]
    },
    devices: [
        $devices | split("\n") | .[] | select(length > 0) | split("|") |
        {
            mac: .[0],
            dl_bytes: (.[1] | tonumber),
            ul_bytes: (.[2] | tonumber),
            total_bytes: (.[3] | tonumber)
        } | . + {
            name: ($name_map[.mac] // "Unknown Device"),
            total: (.total_bytes | bytes_to_gb),
            topApps: ($device_app_map[.mac] // [] | sort_by(-.total_bytes) | map(. + {total: (.total_bytes | bytes_to_gb)}))
        }
    ] | sort_by(-.total_bytes),
    topApps: [
        $apps | split("\n") | .[] | select(length > 0) | split("|") |
        {
            name: .[0],
            total_bytes: (.[1] | tonumber)
        } | . + {
            total: (.total_bytes | bytes_to_gb)
        }
    ] | sort_by(-.total_bytes) | .[:10]
}
EOF

# 7. Execute the jq program from the script file.
JSON_OUTPUT=$(jq -n \
    --arg quota_gb "$MONTHLY_QUOTA_GB" \
    --arg date "$TARGET_DATE" \
    --rawfile stats "$TMP_STATS" \
    --rawfile devices "$TMP_DEVICES" \
    --rawfile apps "$TMP_APPS" \
    --rawfile device_apps "$TMP_DEVICE_APPS" \
    --rawfile names "$TMP_NAMES" \
    -f "$JQ_SCRIPT_FILE"
)

# 8. Write Output Atomically.
echo "$JSON_OUTPUT" > "${FINAL_JSON_PATH}.tmp"
mv "${FINAL_JSON_PATH}.tmp" "$FINAL_JSON_PATH"

# 9. Generate Checksum.
sha256sum "$FINAL_JSON_PATH" | awk '{print $1 "  " $2}' > "$CHECKSUM_PATH"

echo "Successfully generated daily rollup for $TARGET_DATE."