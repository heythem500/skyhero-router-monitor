#!/bin/ash
#
# This script is executed at boot time to ensure the
# Superman-Tacking v2.0 services are running.
#

# Derive the project base directory from the script's location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Wait for the USB drive to be mounted and project directory to exist
i=0
while [ $i -le 30 ]; do
    if [ -d "$BASE_DIR/scripts" ]; then
        break
    fi
    sleep 2
    i=$((i+1))
done

# Source the central configuration to set variables.
. "$BASE_DIR/scripts/config.sh"

# --- Cron Job Setup ---
# Clear any old jobs first to prevent duplicates
cru d roll_yesterday 2>/dev/null
cru d roll_today 2>/dev/null
cru d traffic_monitor 2>/dev/null
cru d db_backup 2>/dev/null
cru d daemon_watchdog 2>/dev/null
cru d monthly_aggregator 2>/dev/null

# Add the cron jobs
cru a roll_yesterday "5 0 * * *" "$SCRIPTS_DIR/daily_rollup.sh yesterday"
cru a roll_today "*/5 * * * *" "$SCRIPTS_DIR/daily_rollup.sh today"
cru a traffic_monitor "*/5 * * * *" "$SCRIPTS_DIR/traffic_monitor.sh"
cru a db_backup "0 */2 * * *" "$SCRIPTS_DIR/backup_db.sh"
cru a daemon_watchdog "* * * * *" "$SCRIPTS_DIR/daemon_watchdog.sh"
cru a monthly_aggregator "5 2 * * *" "$SCRIPTS_DIR/monthly_aggregator.sh"

# --- Daemon Management ---
# Stop any existing daemon process using a BusyBox-compatible method
# The grep '[a]uto_period_generator.sh' pattern avoids matching the grep process itself.
pid=$(ps w | grep '[a]uto_period_generator.sh' | awk '{print $1}')
if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    sleep 1
fi

# Start the new daemon in the background
nohup "$SCRIPTS_DIR/auto_period_generator.sh" >> "$LOGS_DIR/auto_period_generator.debug.log" 2>&1 &
