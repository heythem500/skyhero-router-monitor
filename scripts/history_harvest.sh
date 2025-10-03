#!/bin/ash
set -eu

# Mock history_harvest.sh for testing purposes

export BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Source the central configuration.
. "$(dirname "$0")/config.sh"
. "$(dirname "$0")/helpers.sh"

# Check database health before proceeding
restore_live_db_if_needed

############################################################
# BusyBox-safe helpers – paste once at top of every script #
############################################################

# Ensure we are running under ash

# ---------- integer_add  (posix calc without $(( )) ) ----------
integer_add() { awk "BEGIN{print $1 + $2}"; }

# ---------- epoch_from_ISO  (YYYY-MM-DD → seconds) --------------
epoch_from_ISO() {
    # BusyBox date understands “-d”, but some builds don’t; fall back to awk
    if date -d "$1 00:00:00" +%s >/dev/null 2>&1; then
        date -d "$1 00:00:00" +%s
    else
        # Lightweight POSIX fallback
        IFS=- set -- $1
        year=$1; mon=$2; day=$3
        # seconds to start of 1970-01-01 → year / leap-year calc in awk
        awk -v y=$year -v m=$mon -v d=$day 'BEGIN{
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
          }'
    fi
}

# ---------- ISO_from_epoch  (seconds → YYYY-MM-DD) --------------
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

LOG_FILE="$LOGS_DIR/history_harvest.log"

# Redirect all output to a log file for later review.
exec > "$LOG_FILE" 2>&1

echo "--- Starting Historical Data Harvest & Upgrade ---"
echo "Timestamp: $(date)"

# Use a temporary directory in RAM for staging to minimize wear on the USB drive.
TMP_DIR="/tmp/harvest_$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

TMP_DB="$TMP_DIR/db.sqlite"

# 1. Create a snapshot of the live DB to work with a consistent dataset.
sqlite3 "$LIVE_DB" ".backup '$TMP_DB'"

# 2. Discover the full date range from the database snapshot.
MIN_EPOCH=$(sqlite3 "$TMP_DB" "SELECT MIN(timestamp) FROM traffic;")
MAX_EPOCH=$(sqlite3 "$TMP_DB" "SELECT MAX(timestamp) FROM traffic;")

if [ -z "$MIN_EPOCH" ] || [ -z "$MAX_EPOCH" ]; then
    echo "Database contains no traffic data. Exiting."
    exit 0
fi

# 3. Loop through every day from the first record to the last.
cur=$MIN_EPOCH
while [ "$(integer_add "$cur" 0)" -le "$(integer_add "$MAX_EPOCH" 0)" ]; do
    day_to_process=$(iso_from_epoch "$cur")
    echo "Processing date: $day_to_process..."
    
    # Always run the rollup. This will either create a new file or overwrite an old one with the new, enriched format.
    # We use the consistent snapshot (TMP_DB) for all operations.
    "$SCRIPTS_DIR/daily_rollup.sh" "$day_to_process" "$TMP_DB"
    
    cur=$(integer_add "$cur" 86400)
done

echo "--- Historical Data Harvest & Upgrade Complete ---"
