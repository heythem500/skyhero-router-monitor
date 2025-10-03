#!/bin/ash
#
# Uninstallation script for the Superman-v2 monitoring system.
#

# --- Robustly determine BASE_DIR and source config ---
# Get the directory of this script, handling symlinks
SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [ "$SOURCE" != /* ] && SOURCE="$DIR/$SOURCE"
done
SCRIPTS_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
BASE_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"

# Source the central configuration if it exists to get all paths
if [ -f "$SCRIPTS_DIR/config.sh" ]; then
    . "$SCRIPTS_DIR/config.sh"
fi

# --- Color Definitions ---
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_RESET='\033[0m'

# --- Helper Functions ---
# BusyBox-compatible process management
kill_process() {
    pattern="$1"
    # Use a robust grep pattern to avoid killing the grep process itself
    pid=$(ps w | grep "$pattern" | grep -v grep | awk '{print $1}')
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
        echo "Process matching '$pattern' (PID: $pid) terminated."
    else
        echo "No running process found matching '$pattern'."
    fi
}

# --- Main Removal Logic ---
echo -e "${C_YELLOW}--- Superman-Tacking v2.0 Uninstaller ---${C_RESET}"
echo -e "${C_RED}WARNING: This will permanently delete project scripts, data, logs, and cron jobs.${C_RESET}"
echo -e "Project base directory is: ${C_CYAN}$BASE_DIR${C_RESET}"
echo ""

# General confirmation
printf "Are you sure you want to uninstall the project? [y/N]: "
read -r choice
case "$choice" in
    [yY][eE][sS]|[yY])
        ;;
    *)
        echo "Removal aborted by user."
        exit 0
        ;;
esac

# Specific confirmation for backups
printf "Do you want to delete the historical database backups? (This is permanent) [y/N]: "
read -r delete_backups_choice

# 1. Stop the background daemon process
echo ""
echo "Stopping the background daemon (auto_period_generator.sh)..."
kill_process "auto_period_generator.sh"

# 2. Remove the cron jobs
echo ""
echo "Removing cron jobs..."
cru d roll_yesterday 2>/dev/null
cru d roll_today 2>/dev/null
cru d traffic_monitor 2>/dev/null
cru d db_backup 2>/dev/null
cru d daemon_watchdog 2>/dev/null
echo "Cron jobs removed."

# 3. Remove the symlink
echo ""
echo "Removing 'skyhero' command symlink (if it exists)..."
SYMLINK_PATH="/opt/bin/skyhero"
if [ -L "$SYMLINK_PATH" ]; then
    rm "$SYMLINK_PATH"
    echo "Symlink removed."
else
    echo "Symlink not found or not a symlink."
fi

# 4. Remove web server configuration
echo ""
echo "Removing web server configuration..."
LIGHTTPD_CONF_PATH="/opt/etc/lighttpd/lighttpd.conf"
UNIQUE_COMMENT="# --- Added by Superman-V2 ---"
if [ -f "$LIGHTTPD_CONF_PATH" ] && grep -q "$UNIQUE_COMMENT" "$LIGHTTPD_CONF_PATH"; then
    # Create a backup before modifying
    cp "$LIGHTTPD_CONF_PATH" "${LIGHTTPD_CONF_PATH}.bak-uninstall-$(date +%F)"
    # Use sed to delete the block
    sed -i '/^${UNIQUE_COMMENT}/,/^# --- End Superman-V2 ---/d' "$LIGHTTPD_CONF_PATH"
    echo -e "${C_YELLOW}Superman-V2 block removed from ${LIGHTTPD_CONF_PATH}.${C_RESET}"
    echo "A backup of the original file was made."
    echo "You may need to restart the web server for changes to take effect."
else
    echo "No Superman-V2 configuration found in ${LIGHTTPD_CONF_PATH}."
fi

# 5. Remove project files
echo ""
case "$delete_backups_choice" in
    [yY][eE][sS]|[yY])
        echo -e "${C_RED}Deleting entire project directory, including all backups...${C_RESET}"
        rm -rf "$BASE_DIR"
        echo "Project directory '$BASE_DIR' removed."
        ;;
    *)
        echo -e "${C_YELLOW}Deleting all project files, but PRESERVING database backups...${C_RESET}"
        BACKUP_DIR_NAME=$(basename "${BACKUP_DIR:-$BASE_DIR/db_backups}")
        for item in "$BASE_DIR"/*; do
            if [ -e "$item" ]; then
                item_name=$(basename "$item")
                if [ "$item_name" != "$BACKUP_DIR_NAME" ]; then
                    echo "Removing $item_name..."
                    rm -rf "$item"
                fi
            fi
        done
        echo "Project files removed. Backups preserved in '$BASE_DIR/$BACKUP_DIR_NAME'."
        ;;
esac

echo -e "\n${C_YELLOW}--- Uninstallation Complete ---${C_RESET}"
