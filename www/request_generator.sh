#!/bin/sh
set -eu

# --- Robustly determine BASE_DIR and source config ---
# Get the directory of this script, handling symlinks
SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [ "$SOURCE" != /* ] && SOURCE="$DIR/$SOURCE"
done
SCRIPTS_DIR_WWW="$(cd -P "$(dirname "$SOURCE")" && pwd)"
BASE_DIR="$(cd "$SCRIPTS_DIR_WWW/.." && pwd)"

# Source the central configuration using the now-known BASE_DIR
. "$BASE_DIR/scripts/config.sh"


# --- CGI-specific output ---
# The Content-Type header is essential for the web server to handle the response correctly.
echo "Content-Type: application/json"
echo "" # An empty line is required to separate headers from the body.

# --- Main Logic ---
# The QUERY_STRING environment variable contains the URL parameters (e.g., start=2025-06-22&end=2025-06-28)
if [ -n "$QUERY_STRING" ]; then
    # Extract start and end dates using basic shell tools
    START_DATE=$(echo "$QUERY_STRING" | sed -n 's/.*start=\([^&]*\).*/\1/p')
    END_DATE=$(echo "$QUERY_STRING" | sed -n 's/.*end=\([^&]*\).*/\1/p')

    # Basic validation to ensure dates are not empty
    if [ -n "$START_DATE" ] && [ -n "$END_DATE" ]; then
        # Define the request file path using the configured REQUESTS_DIR
        REQUEST_FILE="${REQUESTS_DIR}/${START_DATE}_${END_DATE}.req"
        
        # Create the empty request file
        if touch "$REQUEST_FILE"; then
            # Success response in JSON format
            echo "{\"success\": true, \"message\": \"Report generation for ${START_DATE} to ${END_DATE} has been queued.\"}"
        else
            # Error response if file creation fails
            echo "{\"success\": false, \"message\": \"Error: Could not create request file in ${REQUESTS_DIR}. Check permissions.\"}"
        fi
    else
        # Error if parameters are missing or malformed
        echo "{\"success\": false, \"message\": \"Error: Invalid or missing start/end date parameters.\"}"
    fi
else
    # Error if no query string is provided
    echo "{\"success\": false, \"message\": \"Error: No parameters provided.\"}"
fi
