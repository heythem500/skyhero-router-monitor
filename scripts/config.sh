#!/bin/ash
set -eu
#
# Central configuration for Superman-v2 Dashboard
#

# If BASE_DIR is not already set, derive it from the calling script's location
if [ -z "$BASE_DIR" ]; then
  # This is a fallback for running scripts directly, but install.sh should always set it
  BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi

# Prepend /opt/bin to the PATH to ensure our custom binaries (like jq) are found first.
# Only prepend if not already in PATH
case ":$PATH:" in
  *":/opt/bin:"*) ;;
  *) PATH="/opt/bin:$PATH" ;;
esac
export PATH

# --- Core Paths ---
# The absolute path to the project's root directory on the USB drive.

# Directory for all data files.
export DATA_DIR="$BASE_DIR/data"

# Directory for scripts.
export SCRIPTS_DIR="$BASE_DIR/scripts"

# Directory for immutable daily JSON files.
export DAILY_DIR="$DATA_DIR/daily_json"

# Directory for cached period reports for the UI.
export PERIOD_DIR="$DATA_DIR/period_data"

# Directory for gzipped database backups.
export BACKUP_DIR="$BASE_DIR/db_backups"

# Directory for logs.
export LOGS_DIR="$BASE_DIR/logs"

# Directory for the web interface files.
export WWW_DIR="$BASE_DIR/www"

# Directory for request files for auto_period_generator.sh
export REQUESTS_DIR="$DATA_DIR/requests"

# Ensure all directories exist
mkdir -p "$DATA_DIR" "$DAILY_DIR" "$PERIOD_DIR" "$BACKUP_DIR" "$LOGS_DIR" "$REQUESTS_DIR" 

# --- System Paths ---
# Location of the live Traffic Analyzer database.
LIVE_DB="/jffs/.sys/TrafficAnalyzer/TrafficAnalyzer.db"

# --- Quota Configuration ---
# Monthly data usage quota in Gigabytes (GB).
MONTHLY_QUOTA_GB=500