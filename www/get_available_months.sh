#!/bin/ash
set -eu

#
# get_available_months.sh
# CGI script to find and return a sorted list of available monthly reports.
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

# --- CGI Header ---
echo "Content-Type: application/json"
echo ""

# --- Main Logic ---
# Find all traffic_month_*.json files, extract the YYYY-MM part, sort them, and format as a JSON array.
# Using a simple `while` loop and `sed` for maximum BusyBox compatibility.

MONTHS=$(ls -1 "$PERIOD_DIR"/traffic_month_*.json 2>/dev/null | sed 's/.*traffic_month_//; s/\.json//' | sort -r | awk '{printf "%s\"%s\"",sep,$0; sep=","}')

echo "[$MONTHS]"
