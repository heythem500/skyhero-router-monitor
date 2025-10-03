#!/bin/ash
set -eu

# --- Color Definitions ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_RESET='\033[0m'

# Resolve the actual script path, handling symlinks in BusyBox
# This is a common BusyBox-compatible way to get the real path of the script
SOURCE="${0}"
while [ -h "${SOURCE}" ]; do
    DIR="$( cd -P "$( dirname "${SOURCE}" )" && pwd )"
    SOURCE="$(readlink "${SOURCE}")"
    [ "${SOURCE}" != /* ] && SOURCE="${DIR}/${SOURCE}"
done
SCRIPT_DIR="$( cd -P "$( dirname "${SOURCE}" )" && pwd )"

# Now that SCRIPT_DIR is correctly determined, we can set BASE_DIR
# BASE_DIR is the parent directory of SCRIPT_DIR (e.g., /path/to/project)
export BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the central configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    . "$SCRIPT_DIR/config.sh"
else
    echo -e "${C_RED}ERROR: config.sh not found! Please ensure you are running this script from the 'scripts' directory or that the project structure is intact.${C_RESET}" >&2
    exit 1
fi

# --- Helper Functions ---
verify_installation() {
    echo "
Verifying active cron jobs..."
    cru l | while IFS= read -r line; do
        case "$line" in
            *skyhero_traffic_monitor*|*skyhero_db_backup*)
                echo -e "${C_GREEN}  -> $line${C_RESET}"
                ;;
            *)
                echo "     $line"
                ;;
        esac
    done

    echo "
Verifying background daemon..."
    if ps w | grep "auto_period_generator.sh" | grep -v grep | grep -q "auto_period_generator.sh"; then
        echo -e "${C_GREEN}  -> Background daemon is RUNNING.${C_RESET}"
    else
        echo -e "${C_RED}  -> Background daemon is NOT RUNNING.${C_RESET}\n"
    fi

    echo "
Verifying database backups..."
    # Ensure DB_BACKUPS_DIR is set before using it
    if [ -z "$BACKUP_DIR" ]; then
        echo -e "${C_RED}ERROR: BACKUP_DIR is not set. Cannot verify backups.${C_RESET}" >&2
    else
        BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name "TrafficAnalyzer_*.db" -type f | wc -l)
        echo -e "${C_GREEN}  -> Found $BACKUP_COUNT historical database backups.${C_RESET}"
    fi
}

show_instructions() {
    clear
    echo -e "${C_GREEN}--- Superman-Tracking v2.0 Instructions ---${C_RESET}"
    echo ""
    echo "To access the dashboard, open your web browser to:"
    echo -e "${C_CYAN}http://<your_router_ip>:8081/skyhero-v2/${C_RESET}"
    echo "(Replace <your_router_ip> with your router's actual IP address and 8081 with your lighttpd port if different)"
    echo ""
    echo "Key Information:"
    echo "- Data is updated hourly by the 'traffic_monitor' cron job."
    echo "- Historical data is backed up daily by the 'db_backup' cron job (at 3:00 AM)."
    echo "- The 'auto_period_generator' daemon runs in the background to process custom date range requests."
    echo ""
    echo "Troubleshooting Tips:"
    echo "- If the dashboard shows no data, try running 'skyhero' and selecting 'Verify Status' (option 2)."
    echo "- Ensure your router's Traffic Analyzer is enabled and working."
    echo "- Check your lighttpd configuration (usually /opt/etc/lighttpd/lighttpd.conf) to ensure it's serving the 'www' directory and CGI scripts correctly."
    echo ""
    read -p "Press [Enter] to return to the menu..."
}

show_last_install_results() {
    clear
    echo -e "${C_GREEN}--- Last Installation/Update Results ---${C_RESET}"
    echo ""
    # Ensure LOGS_DIR is set before using it
    if [ -z "$LOGS_DIR" ]; then
        echo -e "${C_RED}ERROR: LOGS_DIR is not set. Cannot show install results.${C_RESET}" >&2
    elif [ -f "$LOGS_DIR/install.log" ]; then
        cat "$LOGS_DIR/install.log"
    else
        echo -e "${C_YELLOW}No installation log found. Please run 'Install / Update' first.${C_RESET}"
    fi
    echo ""
    read -p "Press [Enter] to return to the menu..."
}

change_monthly_quota() {
    clear
    echo -e "${C_GREEN}--- Change Monthly Quota ---${C_RESET}"
    echo ""
    echo "Current Monthly Quota: ${MONTHLY_QUOTA_GB} GB"
    echo ""
    read -p "Enter new monthly quota in GB (e.g., 300): " new_quota

    if [ -n "$new_quota" ] && [ "$new_quota" -eq "$new_quota" ] 2>/dev/null && [ "$new_quota" -gt 0 ]; then
        # Update the config.sh file
        sed -i "s/^MONTHLY_QUOTA_GB=.*/MONTHLY_QUOTA_GB=${new_quota}/" "$SCRIPT_DIR/config.sh"
        # Re-source config.sh to update the current session's variable
        . "$SCRIPT_DIR/config.sh"
        echo -e "${C_GREEN}Monthly quota updated to ${new_quota} GB.${C_RESET}"
        echo "Triggering a manual traffic scan to update dashboard..."
        "$SCRIPT_DIR/traffic_monitor.sh"
        echo "Dashboard update triggered."
    else
        echo -e "${C_RED}Invalid input. Please enter a positive number.${C_RESET}"
    fi
}

show_menu() {
    clear
    
    echo -e "${C_CYAN}"
    cat "$SCRIPT_DIR/ascii_art.txt"
cat <<'EOF'
EOF
    echo -e "${C_RESET}"
    echo ""
    echo -e "    ${C_GREEN}Welcome to the Superman-Tracking Management Menu${C_RESET}"
    echo "---------------------------------------------------------------------------"
    echo ""
    echo "  1) Install / Update - Run this first or to update scripts."
    echo ""
    echo "  2) Verify Status    - Check cron jobs, daemon, and backup count."
    echo ""
    echo "  3) Run Manual Traffic Grab   - instant on-demand dashboard refresh."
    echo ""
    echo "  4) Configure Web Server (1-Click Setup)"
    echo ""
    echo -e "  ${C_RED}5) Remove Project   - Uninstall the entire project.${C_RESET}"
    echo ""
    echo "  6) Show Dashboard URL & Instructions."
    echo ""
    echo "  7) Manual Data Backup & Restore."
    echo ""
    echo "  8) Change Monthly Quota."
    echo ""
    echo "  9) Restart lighttpd."
    echo ""
    echo "  10) Security Options (Set/Change Password)."
    echo ""
    echo "  11) View DB Restore History."
    echo ""
    echo "  12) Quit             - Exit this menu."
    echo ""
    echo -e "Dashboard URL: ${C_CYAN}http://<your_router_ip>:8081/skyhero-v2/${C_RESET}"
    echo ""
    echo -n "Enter your choice [1-9]: "
    read -r menu_choice

    case "$menu_choice" in
        1) 
            "$BASE_DIR/install.sh"
            read -p "Press [Enter] to return to the menu..."
            show_menu
            ;;
        2) 
            verify_installation
            read -p "\nPress [Enter] to return to the menu..."
            show_menu
            ;;
        3)
            echo "Forcing an immediate data update for the dashboard..."
            "$SCRIPT_DIR/traffic_monitor.sh"
            echo "Manual data update complete."
            read -p "\nPress [Enter] to return to the menu..."
            show_menu
            ;;
        4)
            "$SCRIPT_DIR/web_server_setup.sh"
            read -p "\nPress [Enter] to return to the menu..."
            show_menu
            ;;
        5)
            "$SCRIPT_DIR/remove.sh"
            echo "Exiting management menu."
            exit 0
            ;;
        6)
            show_instructions
            show_menu
            ;;
        7)
            "$SCRIPT_DIR/manual_data_backup_restore.sh"
            read -p "\nPress [Enter] to return to the menu..."
            show_menu
            ;;
        8)
            change_monthly_quota
            read -p "\nPress [Enter] to return to the menu..."
            show_menu
            ;;
        9)
            echo "Restarting lighttpd..."
            /opt/etc/init.d/S80lighttpd restart
            echo "lighttpd restart command issued."
            read -p "\nPress [Enter] to return to the menu..."
            show_menu
            ;;
        10)
            "$SCRIPT_DIR/security_manager.sh"
            read -p "\nPress [Enter] to return to the menu..."
            show_menu
            ;;
        11)
            echo "--- Displaying Database Restore History ---\n"
            if [ -f "$LOGS_DIR/db_restore_history.log" ]; then
                # Colorize the output using a while loop for better BusyBox compatibility
                while IFS= read -r line; do
                    if echo "$line" | grep -q "RESTORED"; then
                        echo -e "\033[01;32m$line\033[0m"  # Green for successful restores
                    elif echo "$line" | grep -q "FAILED\|CRITICAL"; then
                        echo -e "\033[01;31m$line\033[0m"  # Red with X for critical failures
                    elif echo "$line" | grep -q "missing\|corrupt"; then
                        echo -e "\033[01;31m$line\033[0m"  # Red for database issues
                    elif echo "$line" | grep -q "DETECTED\|TIME GAP"; then
                        echo -e "\033[01;33m$line\033[0m"  # Yellow for informational messages
                    else
                        echo "$line"
                    fi
                done < "$LOGS_DIR/db_restore_history.log"
            else
                echo "No restore events recorded."
            fi
            read -p "\nPress [Enter] to return to the menu..."
            show_menu
            ;;
        12)
            echo "Exiting management menu."
            exit 0
            ;;
        *)
            echo -e "${C_RED}Invalid option. Please try again.${C_RESET}"
            sleep 2
            show_menu
            ;;
    esac
}

# --- Main Script Execution ---
show_menu
