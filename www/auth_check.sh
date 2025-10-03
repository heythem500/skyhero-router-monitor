#!/bin/sh

# Final, most robust version of the auth check CGI script.

# --- Setup Logging ---
LOG_FILE="/tmp/mnt/ym/skyhero-v2/logs/auth_cgi.log"
log() {
    echo "[$(date)] - auth_check.sh - $1" >> "$LOG_FILE"
}

log "--- Script execution started ---"
log "Request Method: $REQUEST_METHOD"
log "Content Length: $CONTENT_LENGTH"

# --- Start JSON Output ---
echo "Content-Type: application/json"
echo ""

# --- Find and Source Config ---
SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [ "$SOURCE" != /* ] && SOURCE="$DIR/$SOURCE"
done
SCRIPTS_DIR_WWW="$(cd -P "$(dirname "$SOURCE")" && pwd)"
BASE_DIR="$(cd "$SCRIPTS_DIR_WWW/.." && pwd)"
CONFIG_PATH="$BASE_DIR/scripts/config.sh"

if [ ! -f "$CONFIG_PATH" ]; then
    log "ERROR: Config file not found."
    echo '{"success": false, "error": "Server misconfiguration: Config file not found."}'
    exit 0
fi
. "$CONFIG_PATH"
log "Config file sourced successfully."

# --- Main Logic: Read POST data using CONTENT_LENGTH ---
password_attempt=""
if [ "$REQUEST_METHOD" = "POST" ]; then
    if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
        log "Attempting to read $CONTENT_LENGTH bytes from stdin..."
        # Use read with -n to read a specific number of characters. This is the key fix.
        read -n "$CONTENT_LENGTH" password_attempt
        log "Finished reading from stdin. Content of password_attempt: '$password_attempt'"
    else
        log "ERROR: POST request received but CONTENT_LENGTH is zero or not set."
        echo '{"success": false, "error": "Client sent an empty password."}'
        exit 0
    fi
else
    log "ERROR: Request method was not POST."
    echo '{"success": false, "error": "Invalid request method."}'
    exit 0
fi

# --- Hashing and Comparison ---
PASSWORD_FILE="$DATA_DIR/.password"
log "Password file path is: $PASSWORD_FILE"

attempted_hash=$(echo -n "$password_attempt" | sha256sum | cut -d' ' -f1)
log "Attempted hash: $attempted_hash"

if [ -f "$PASSWORD_FILE" ]; then
    stored_hash=$(cat "$PASSWORD_FILE")
    log "Stored hash: $stored_hash"
else
    stored_hash=""
    log "Password file does not exist."
fi

if [ "$attempted_hash" = "$stored_hash" ]; then
    log "SUCCESS: Hashes match."
    echo '{"success": true}'
else
    log "FAILURE: Hashes do not match."
    echo '{"success": false, "error": "Incorrect password"}'
fi

log "--- Script execution finished ---"
