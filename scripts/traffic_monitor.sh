#!/bin/ash
#
# Orchestrates the creation of the five standard period reports for the UI.
# This script is intended to be run by cron every few minutes.
#

############################################################
# BusyBox-safe helpers – paste once at top of every script #
############################################################

# ---------- integer_add  (posix calc without $(( )) ) ----------
integer_add() { awk "BEGIN{print $1 + $2}"; }

# ---------- epoch_from_ISO  (YYYY-MM-DD → seconds) --------------
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

# ---------- ISO_from_epoch  (seconds → YYYY-MM-DD) --------------
iso_from_epoch() { awk -v ts="$1" 'BEGIN { print strftime("%Y-%m-%d", ts) }'; }

# ---------- yesterday() – returns yesterday's ISO date ----------
yesterday() {
    now=$(date +%s)
    epoch_yest=$(integer_add "$now" -86400)
    iso_from_epoch "$epoch_yest"
}

############################################################
#                ←  END OF HELPER BLOCK                   #
############################################################

# Source the central configuration.
export BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/scripts/config.sh"

# --- Sanity Checks & Logging Setup ---
# Ensure critical directories are defined and exist before we do anything else.
if [ -z "$LOGS_DIR" ] || [ -z "$PERIOD_DIR" ]; then
    # We can't use our log file if LOGS_DIR is missing, so output to stderr and hope cron captures it.
    echo "[$(date)] CRITICAL: LOGS_DIR or PERIOD_DIR is not defined in traffic_monitor.sh. Exiting." >&2
    exit 1
fi
mkdir -p "$LOGS_DIR"
mkdir -p "$PERIOD_DIR"

LOG_FILE="$LOGS_DIR/traffic_monitor.log"

# Write a definitive log entry before redirecting all script output.
# This helps debug if the script is running at all, even if exec fails.
echo "[$(date)] --- traffic_monitor.sh started ---" >> "$LOG_FILE"


# Redirect all output to a log file.
exec >> "$LOG_FILE" 2>&1

echo "--- Running Traffic Monitor: $(date) ---"

# --- Date Calculations ---
TODAY=$(date +%F)
YESTERDAY=$(yesterday)
NOW_EPOCH=$(date +%s)
SEVEN_DAYS_AGO_EPOCH=$(integer_add "$NOW_EPOCH" -518400)
SEVEN_DAYS_AGO=$(iso_from_epoch "$SEVEN_DAYS_AGO_EPOCH")
START_OF_MONTH=$(date +%Y-%m-01)

# --- Report Generation ---

# 1. Today's Report
echo "Generating 'Today' report..."
"$BASE_DIR/scripts/period_builder.sh" "$TODAY" "$TODAY" "$PERIOD_DIR/traffic_period_${TODAY}_${TODAY}.json"

# 2. Yesterday's Report
echo "Generating 'Yesterday' report..."
"$BASE_DIR/scripts/period_builder.sh" "$YESTERDAY" "$YESTERDAY" "$PERIOD_DIR/traffic_period_${YESTERDAY}_${YESTERDAY}.json"

# 3. Last 7 Days Report
echo "Generating 'Last 7 Days' report..."
"$BASE_DIR/scripts/period_builder.sh" "$SEVEN_DAYS_AGO" "$TODAY" "$PERIOD_DIR/traffic_period_last-7-days.json"

# 4. This Month's Report
echo "Generating 'This Month' report..."
"$BASE_DIR/scripts/period_builder.sh" "$START_OF_MONTH" "$TODAY" "$PERIOD_DIR/traffic_period_${START_OF_MONTH}_${TODAY}.json"

# 5. All-Time Report
echo "Generating 'All-Time' report..."
# Safer way to find the first day without complex pipes
FIRST_DAY=""
for f in "$DAILY_DIR"/*.json; do
    [ -f "$f" ] || continue # Skip if no files found
    FIRST_DAY=$(basename "$f" .json)
    break # Found the first one, exit loop
done

if [ -n "$FIRST_DAY" ]; then
    "$BASE_DIR/scripts/period_builder.sh" "$FIRST_DAY" "$TODAY" "$PERIOD_DIR/traffic_period_all_time.json"
else
    echo "No daily data found, skipping 'All-Time' report."
fi

echo "--- Traffic Monitor Finished ---"
