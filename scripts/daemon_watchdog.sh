#!/bin/ash
#
# daemon_watchdog.sh
# This script checks if the auto_period_generator.sh daemon is running.
# If not, it restarts it. This script is intended to be run by cron every minute.
#

# Source the central configuration to get all paths and settings.
export BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/scripts/config.sh"

LOG_FILE="$LOGS_DIR/daemon_watchdog.log"

# Check if the daemon process is running
# We use a grep pattern that avoids matching the grep process itself.
if ! ps w | grep "[a]uto_period_generator.sh" > /dev/null; then
    echo "[$(date)] Daemon not found. Restarting..." >> "$LOG_FILE"
    nohup "$SCRIPTS_DIR/auto_period_generator.sh" >> "$LOGS_DIR/auto_period_generator.debug.log" 2>&1 &
fi
