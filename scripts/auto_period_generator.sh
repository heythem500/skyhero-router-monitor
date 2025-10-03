#!/bin/ash
set -eu
#
# auto_period_generator.sh
# Monitors the requests directory for new data generation requests
# and triggers period_builder.sh.
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

# ---------- yesterday() – returns yesterday’s ISO date ----------
yesterday() {
    now=$(date +%s)
    epoch_yest=$(integer_add "$now" -86400)
    iso_from_epoch "$epoch_yest"
}

############################################################
#                ←  END OF HELPER BLOCK                   #
############################################################

# Set BASE_DIR relative to the script's location
export BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Source the central configuration (defines REQUESTS_DIR, LOGS_DIR etc.)
. "$BASE_DIR/scripts/config.sh"

# The config script already creates this, but ensuring it again doesn't hurt.
mkdir -p "$REQUESTS_DIR"

# --- Enhanced Diagnostics & Error Trapping ---
LOG_FILE="$LOGS_DIR/auto_period_generator.debug.log"
exec >> "$LOG_FILE" 2>&1

# Log daemon PID at startup
echo "[$(date)] Daemon started with PID: $"

# Function to log daemon exit
log_exit() {
    echo "[$(date)] Daemon exiting with status: $?"
}

# Trap EXIT and ERR signals to log daemon termination
trap log_exit EXIT

# Function to check disk space
check_disk_space() {
    # Get available space in 1K blocks for the partition where DATA_DIR resides
    # Using `df -k` and parsing the output for the relevant mount point
    # This is a basic check, adjust THRESHOLD_KB as needed
    THRESHOLD_KB=102400 # 100 MB

    # Find the mount point for DATA_DIR
    MOUNT_POINT=$(df "$DATA_DIR" | awk 'NR==2 {print $6}')
    if [ -z "$MOUNT_POINT" ]; then
        echo "[$(date)] WARNING: Could not determine mount point for $DATA_DIR."
        return 0 # Don't block if we can't check
    fi

    AVAILABLE_KB=$(df -k "$MOUNT_POINT" | awk 'NR==2 {print $4}')

    if [ -z "$AVAILABLE_KB" ] || [ "$AVAILABLE_KB" -lt "$THRESHOLD_KB" ]; then
        echo "[$(date)] CRITICAL: Low disk space detected on $MOUNT_POINT. Available: $((AVAILABLE_KB / 1024)) MB. Threshold: $((THRESHOLD_KB / 1024)) MB."
        # Optionally, you could exit here if disk space is critical
        # exit 1
        return 1 # Indicate low disk space
    fi
    return 0 # Sufficient disk space
}

# Main daemon loop
while true; do

    # Check disk space at the beginning of each loop iteration
    if ! check_disk_space; then
        echo "[$(date)] Daemon pausing due to low disk space. Will re-check in 5 seconds."
        sleep 5
        continue # Skip processing requests if disk space is low
    fi

    # Use a for loop which is safer in ash for globbing
    for req_file in "$REQUESTS_DIR"/*.req; do
        # If no files are found, the loop runs once with the literal string.
        # We must check if the file actually exists.
        [ -f "$req_file" ] || continue

        echo "[$(date)] Detected request file: $(basename "$req_file")"

        filename=$(basename "$req_file" .req)
        start_date=$(echo "$filename" | cut -d'_' -f1)
        end_date=$(echo "$filename" | cut -d'_' -f2)

        # Use a case statement for POSIX-compliant validation
        case "$start_date" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                case "$end_date" in
                    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                        # Both dates are valid, proceed
                        output_filename="traffic_period_${start_date}_${end_date}.json"
                        output_path="$PERIOD_DIR/$output_filename"

                        echo "[$(date)] Calling period_builder.sh for $start_date to $end_date. Output: $output_path"
                        # Execute period_builder.sh, redirecting its output to the daemon's log
                        BASE_DIR="$BASE_DIR" "$SCRIPTS_DIR/period_builder.sh" "$start_date" "$end_date" "$output_path"
                        BUILDER_EXIT_CODE=$?

                        if [ $BUILDER_EXIT_CODE -eq 0 ]; then
                            echo "[$(date)] Successfully processed request for $start_date to $end_date. Removing request file."
                            rm -f "$req_file"
                        else
                            echo "[$(date)] ERROR: period_builder.sh failed with exit code $BUILDER_EXIT_CODE for $start_date to $end_date. Moving request to .failed"
                            mv "$req_file" "${req_file}.failed"
                        fi
                        ;;
                    *)
                        echo "[$(date)] ERROR: Invalid end_date format in filename: $(basename "$req_file"). Moving to .invalid"
                        mv "$req_file" "${req_file}.invalid"
                        ;;
                esac
                ;;
            *)
                echo "[$(date)] ERROR: Invalid start_date format in filename: $(basename "$req_file"). Moving to .invalid"
                mv "$req_file" "${req_file}.invalid"
                ;;
        esac
    done
    sleep 5
done