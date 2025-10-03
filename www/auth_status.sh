#!/bin/sh
# More robust CGI script for checking auth status

# Function to output a JSON error and exit
json_error() {
    echo "Content-Type: application/json"
    echo ""
    echo "{\"enabled\": false, \"error\": \"$1\"}" # Fail-open
    exit 1
}

# Trap errors to call the json_error function
trap 'json_error "An unexpected server error occurred."' ERR

# Set -e to exit on error, -u to treat unset variables as an error
set -eu

# --- Robustly determine BASE_DIR and source config ---
SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [ "$SOURCE" != /* ] && SOURCE="$DIR/$SOURCE"
done
SCRIPTS_DIR_WWW="$(cd -P "$(dirname "$SOURCE")" && pwd)"
BASE_DIR="$(cd "$SCRIPTS_DIR_WWW/.." && pwd)"

if [ ! -f "$BASE_DIR/scripts/config.sh" ]; then
    json_error "Configuration file not found."
fi
. "$BASE_DIR/scripts/config.sh"

PASSWORD_FILE="$DATA_DIR/.password"

# --- CGI Output ---
echo "Content-Type: application/json"
echo ""

if [ -f "$PASSWORD_FILE" ]; then
    echo '{"enabled": true}'
else
    echo '{"enabled": false}'
fi