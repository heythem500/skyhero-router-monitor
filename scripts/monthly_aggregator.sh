#!/bin/ash
set -eu

#
# monthly_aggregator.sh
# Automatically generates an aggregated JSON report for each month that has data.
# This script is intended to be run by a daily cron job.
#

# --- Robustly determine BASE_DIR and source config ---
SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [ "$SOURCE" != /* ] && SOURCE="$DIR/$SOURCE"
done
SCRIPTS_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
export BASE_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"

# Source helper functions and configuration
. "$SCRIPTS_DIR/helpers.sh"
. "$SCRIPTS_DIR/config.sh"

# --- Main Logic ---
LOG_FILE="$LOGS_DIR/monthly_aggregator.log"
exec >> "$LOG_FILE" 2>&1

echo "[$(date)] --- Starting Monthly Aggregation ---"

# 1. Discover available months by scanning the daily JSON files.
# Use `sed` to strip the path and extension, then `cut` and `sort -u` to get a unique list of YYYY-MM prefixes.
AVAILABLE_MONTHS=$(ls -1 "$DAILY_DIR"/*.json 2>/dev/null | sed 's/.*\///; s/\.json//' | cut -d'-' -f1,2 | sort -u)

if [ -z "$AVAILABLE_MONTHS" ]; then
    echo "[$(date)] No daily data found. Exiting."
    exit 0
fi

echo "[$(date)] Found available months: $AVAILABLE_MONTHS"

# 2. Loop through each available month and generate the report.
for month_prefix in $AVAILABLE_MONTHS; do
    echo "[$(date)] Processing month: $month_prefix"

    # 3. Calculate the start and end dates for the month.
    start_date="${month_prefix}-01"

    CURRENT_YEAR_MONTH=$(date +%Y-%m)

    if [ "$month_prefix" = "$CURRENT_YEAR_MONTH" ]; then
        # For the current month, end date is today
        end_date=$(date +%F)
    else
        # For past months, end date is the last day of the month
        year=$(echo "$month_prefix" | cut -d'-' -f1)
        month=$(echo "$month_prefix" | cut -d'-' -f2)

        if [ "$month" = "12" ]; then
            next_month_year=$(integer_add "$year" 1)
            next_month="01"
        else
            next_month_year="$year"
            next_month_num=$(integer_add "$month" 1)
            if [ "$next_month_num" -lt 10 ]; then
                next_month="0$next_month_num"
            else
                next_month="$next_month_num"
            fi
        fi

        first_day_of_next_month="${next_month_year}-${next_month}-01"
        epoch_of_next_month=$(epoch_from_ISO "$first_day_of_next_month")
        epoch_of_last_day=$(integer_add "$epoch_of_next_month" -86400)
        end_date=$(iso_from_epoch "$epoch_of_last_day")
    fi

    # 4. Define the output filename using the new convention.
    output_filename="traffic_month_${month_prefix}.json"
    output_path="$PERIOD_DIR/$output_filename"

    echo "[$(date)] Date range: $start_date to $end_date"
    echo "[$(date)] Output file: $output_path"

    # 5. Call the existing period_builder.sh script.
    "$SCRIPTS_DIR/period_builder.sh" "$start_date" "$end_date" "$output_path"
    
    if [ $? -eq 0 ]; then
        echo "[$(date)] Successfully generated report for $month_prefix."
    else
        echo "[$(date)] ERROR: period_builder.sh failed for month $month_prefix."
    fi

    # Add a 10-second pause to reduce system load
    echo "[$(date)] Pausing for 10 seconds before processing next month..."
    sleep 10
done

echo "[$(date)] --- Monthly Aggregation Finished ---"
