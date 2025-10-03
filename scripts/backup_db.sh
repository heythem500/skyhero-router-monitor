#!/bin/ash
set -eu
#
# Creates a compressed daily backup of the live TrafficAnalyzer.db
#

# Source the central configuration to get all paths and settings.
export BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/scripts/config.sh"
. "$SCRIPTS_DIR/helpers.sh"

restore_live_db_if_needed

# --- Main Logic ---

# Use a temporary directory in RAM for staging to minimize wear on the USB drive.
TMP_DIR="/tmp/skyhero_backup_$$"
mkdir -p "$TMP_DIR"

# Ensure our final backup destination exists.
mkdir -p "$BACKUP_DIR"

# Define file names and paths.
DATE_TAG=$(date +%F_%H)
DB_SNAPSHOT_PATH="$TMP_DIR/TrafficAnalyzer.db"
FINAL_BACKUP_PATH="$BACKUP_DIR/TrafficAnalyzer_${DATE_TAG}.db.gz"
CHECKSUM_FILE="${FINAL_BACKUP_PATH}.sha256"

# 1. Use SQLite's recommended ".backup" command to create a safe, consistent snapshot.
echo "Creating a safe snapshot of the live database..."
sqlite3 "$LIVE_DB" ".backup '$DB_SNAPSHOT_PATH'"

# 2. Compress the snapshot.
echo "Compressing the database snapshot..."
gzip -c "$DB_SNAPSHOT_PATH" > "$FINAL_BACKUP_PATH"

# 3. Generate a checksum for the compressed archive for integrity verification.
echo "Generating SHA256 checksum..."
sha256sum "$FINAL_BACKUP_PATH" | awk '{print $1}' > "$CHECKSUM_FILE"

# 4. Enforce retention policy: delete backups and their checksums older than 60 days.
echo "Enforcing 60-day retention policy..."
find "$BACKUP_DIR" -name "TrafficAnalyzer_*.db.gz" -type f -mtime +60 -exec rm -f {} \;
find "$BACKUP_DIR" -name "TrafficAnalyzer_*.db.gz.sha256" -type f -mtime +60 -exec rm -f {} \;

# 5. Clean up the temporary directory.
rm -rf "$TMP_DIR"

echo "Database backup and cleanup complete."
