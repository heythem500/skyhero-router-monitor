#!/bin/ash
set -eu

# --- Color Definitions ---
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_RESET='\033[0m'

# Source config to get BASE_DIR
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

PASSWORD_FILE="$DATA_DIR/.password"

# Functions for hashing and setting password
set_password() {
    # Use echo -n for same-line input, and -s for silent (password) read
    printf "Enter new password: "
    read -s new_password
    printf "\n" # Add a newline after the hidden input
    printf "Confirm new password: "
    read -s confirm_password
    printf "\n"

    if [ "$new_password" != "$confirm_password" ]; then
        echo -e "\n${C_RED}Passwords do not match. Aborting.${C_RESET}"
        sleep 2
        return 1
    fi

    if [ -z "$new_password" ]; then
        echo -e "\n${C_RED}Password cannot be empty. Aborting.${C_RESET}"
        sleep 2
        return 1
    fi

    echo -n "$new_password" | sha256sum | cut -d' ' -f1 > "$PASSWORD_FILE"
    echo -e "\n${C_GREEN}Password has been set successfully.${C_RESET}"
    read -p "Press [Enter] to return..."
}

disable_password() {
    if [ -f "$PASSWORD_FILE" ]; then
        rm "$PASSWORD_FILE"
        echo -e "\n${C_YELLOW}Password protection has been disabled.${C_RESET}"
    else
        echo -e "\nPassword protection is already disabled."
    fi
    read -p "Press [Enter] to return..."
}

# Main Menu Logic
while true; do
    clear
    echo "--- Security Manager ---"
    if [ -f "$PASSWORD_FILE" ]; then
        echo -e "Status: Password protection is ${C_GREEN}ENABLED.${C_RESET}"
    else
        echo -e "Status: Password protection is ${C_YELLOW}DISABLED.${C_RESET}"
    fi
    echo "------------------------"
    echo "1) Enable / Change Password"
    echo "2) Disable Password"
    echo "3) Return to Main Menu"
    echo -n "Enter your choice: "
    read -r choice

    case "$choice" in
        1) set_password ;;
        2) disable_password ;;
        3) exit 0 ;;
        *) echo -e "${C_RED}Invalid option.${C_RESET}" ; sleep 1 ;;
    esac
done
