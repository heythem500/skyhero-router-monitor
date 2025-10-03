#!/bin/ash
set -eu

# --- Color Definitions ---
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_RESET='\033[0m'

# --- Script Setup ---
SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [ "$SOURCE" != /* ] && SOURCE="$DIR/$SOURCE"
done
SCRIPTS_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
BASE_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"

# --- Configuration ---
LIGHTTPD_CONF_PATH="/opt/etc/lighttpd/lighttpd.conf"
UNIQUE_COMMENT="# --- Added by Superman-V2 ---"

# --- Helper Functions ---
check_status() {
    echo -e "\n${C_CYAN}--- Checking Configuration Status ---${C_RESET}"
    if [ ! -f "$LIGHTTPD_CONF_PATH" ]; then
        echo -e "${C_RED}❌ Status: Web server configuration not found at '${LIGHTTPD_CONF_PATH}'.${C_RESET}"
        return
    fi

    if grep -q "$UNIQUE_COMMENT" "$LIGHTTPD_CONF_PATH"; then
        echo -e "${C_GREEN}✅ Status: Found existing configuration. Your server appears to be set up correctly.${C_RESET}"
    else
        echo -e "${C_YELLOW}❌ Status: Configuration not found. Please use option 2 or 3 to set it up.${C_RESET}"
    fi
}

show_manual_instructions() {
    echo -e "\n${C_YELLOW}--------------------------------------------------------------------${C_RESET}"
    echo -e "  ${C_CYAN}MANUAL WEB SERVER CONFIGURATION${C_RESET}"
    echo -e "${C_YELLOW}--------------------------------------------------------------------${C_RESET}"
    echo -e "Please add the following lines to the end of your web server configuration file."
    echo ""
    echo -e "  File Path: ${C_GREEN}${LIGHTTPD_CONF_PATH}${C_RESET}"
    echo ""
    echo -e "  Please add this exact block of text:"
    echo -e "  ${C_CYAN}"
cat <<EOT

${UNIQUE_COMMENT}
server.port = 8081 # Superman-V2 Dashboard Port
alias.url += (
    "/skyhero-v2/data/" => "$BASE_DIR/data/",
    "/skyhero-v2/logs/" => "$BASE_DIR/logs/",
    "/skyhero-v2/" => "$BASE_DIR/www/"
)
cgi.assign += ( ".sh" => "/bin/sh" )
# --- End Superman-V2 ---
EOT
    echo -e "${C_CYAN}"
    echo -e "After saving the file, you can restart the server by running:"
    echo -e "${C_GREEN}/opt/etc/init.d/S80lighttpd restart${C_RESET}"
    echo -e "${C_YELLOW}--------------------------------------------------------------------${C_RESET}"
}

run_automatic_setup() {
    if grep -q "$UNIQUE_COMMENT" "$LIGHTTPD_CONF_PATH"; then
        echo -e "\n${C_GREEN}✅ Already configured! No action needed.${C_RESET}"
        return
    fi

    printf "\nThis script will automatically back up and modify your web server configuration. Are you sure you want to proceed? [y/N]: "
    read -r choice
    case "$choice" in
        [yY][eE][sS]|[yY])
            ;; 
        *)
            echo "\nUser cancelled operation."
            return
            ;; 
    esac

    BACKUP_PATH="${LIGHTTPD_CONF_PATH}.bak-skyhero-$(date +%F_%H-%M-%S)"
    echo -e "\nCreating safety backup..."
    cp "$LIGHTTPD_CONF_PATH" "$BACKUP_PATH"
    echo -e "${C_GREEN}🛡️ Backup created: ${BACKUP_PATH}${C_RESET}"

    echo -e "\nAppending Superman-V2 configuration..."
    # Clean up any potentially conflicting existing lines before appending
    sed -i '/alias.url = (.*skyhero-v2/d' "$LIGHTTPD_CONF_PATH"
    sed -i '/cgi.assign = (.*.sh/d' "$LIGHTTPD_CONF_PATH"
    sed -i '/^\s*server.port\s*=/d' "$LIGHTTPD_CONF_PATH"
    cat <<EOT >> "$LIGHTTPD_CONF_PATH"

${UNIQUE_COMMENT}
server.port = 8081 # Superman-V2 Dashboard Port
alias.url += (
    "/skyhero-v2/data/" => "$BASE_DIR/data/",
    "/skyhero-v2/logs/" => "$BASE_DIR/logs/",
    "/skyhero-v2/" => "$BASE_DIR/www/"
)
cgi.assign += ( ".sh" => "/bin/sh" )
# --- End Superman-V2 ---
EOT
    echo -e "${C_GREEN}✍️ Configuration appended.${C_RESET}"

    echo -e "\nTesting new configuration for errors..."
    if lighttpd -t -f "$LIGHTTPD_CONF_PATH" > /tmp/lighttpd_test_output 2>&1; then
        echo -e "${C_GREEN}✅ Syntax check passed. Configuration is valid.${C_RESET}"
        
        echo -e "\nRestarting web server to apply changes..."
        /opt/etc/init.d/S80lighttpd restart
        echo -e "${C_GREEN}🚀 Success! The dashboard should now be accessible.${C_RESET}"
    else
        echo -e "${C_RED}❌ CRITICAL ERROR DETECTED IN CONFIGURATION!${C_RESET}"
        echo -e "${C_YELLOW}The web server was NOT restarted. Restoring from safety backup...${C_RESET}"
        
        mv "$BACKUP_PATH" "$LIGHTTPD_CONF_PATH"
        echo -e "${C_GREEN}✅ Backup restored. Your original configuration is safe.${C_RESET}"
        
        echo -e "\n--- Error Details ---"
        cat /tmp/lighttpd_test_output
        echo -e "---------------------"
        
        show_manual_instructions
    fi

    rm -f /tmp/lighttpd_test_output
}

# --- Main Logic ---
while true; do
    clear
    echo -e "${C_CYAN}--- Superman-V2 Web Server Setup ---${C_RESET}"
    echo -e "\nThis tool helps configure your lighttpd web server."
    echo ""
    echo -e "  1) Check Configuration Status"
    echo -e "     - Safely checks if the server is already configured."
    echo ""
    echo -e "  2) Apply Automatic Configuration ${C_GREEN}(Recommended)${C_RESET}"
    echo -e "     - Backs up, appends config, tests it, and self-heals on error."
    echo ""
    echo -e "  3) Show Manual Instructions"
    echo -e "     - Displays the exact text to copy and paste into the file yourself."
    echo ""
    echo -e "  q) Quit to Main Menu"

    printf "\nEnter your choice [1-3, q]: "
    read -r choice

    case "$choice" in
        1)
            check_status
            read -p "\nPress [Enter] to return to the menu..."
            ;; 
        2)
            run_automatic_setup
            read -p "\nPress [Enter] to return to the menu..."
            ;; 
        3)
            show_manual_instructions
            read -p "\nPress [Enter] to return to the menu..."
            ;; 
        q|Q)
            exit 0
            ;; 
        *)
            echo -e "\n${C_RED}Invalid option. Please try again.${C_RESET}"
            sleep 1
            ;; 
    esac
done