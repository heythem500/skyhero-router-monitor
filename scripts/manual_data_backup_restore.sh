#!/bin/ash
set -eu

# --- Color Definitions ---
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_RESET='\033[0m'

# Source the central configuration
export BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/scripts/config.sh"

BACKUP_ROOT="/tmp/mnt/ym"

# --- Helper Functions ---
handle_error() {
    echo -e "\n${C_RED}ERROR: $1${C_RESET}" >&2
    read -p "Press [Enter] to return..."
    return 1
}

show_success() {
    echo -e "\n${C_GREEN}SUCCESS: $1${C_RESET}"
    read -p "Press [Enter] to return..."
}

# --- Backup Function ---
create_backup() {
    clear
    echo -e "${C_CYAN}--- Create Manual Data Backup ---${C_RESET}"
    echo ""
    echo "This will create a compressed archive of your 'data' and 'db_backups' folders."
    echo "The backup will be stored in: ${C_YELLOW}$BACKUP_ROOT/${C_RESET}"
    echo ""
    printf "Proceed with backup? [y/N]: "
    read -r confirm

    case "$confirm" in
        [yY][eE][sS]|[yY])
            TIMESTAMP=$(date +%Y%m%d_%H%M%S)
            BACKUP_FILE="$BACKUP_ROOT/skyhero_v2_manual_backup_${TIMESTAMP}.tar.gz"

            mkdir -p "$BACKUP_ROOT" || handle_error "Could not create backup root directory $BACKUP_ROOT."

            echo "Creating backup... This may take a moment."
            if tar -czf "$BACKUP_FILE" -C "$BASE_DIR" data db_backups; then
                show_success "Backup created successfully: $(basename "$BACKUP_FILE")"
            else
                handle_error "Failed to create backup."
            fi
            ;;
        *)
            echo -e "${C_YELLOW}Backup cancelled.${C_RESET}"
            read -p "Press [Enter] to return..."
            ;;
    esac
}

# --- Restore Function ---
restore_backup() {
    clear
    echo -e "${C_CYAN}--- Restore Manual Data Backup ---${C_RESET}"
    echo ""
    echo "Available manual data backups in ${C_YELLOW}$BACKUP_ROOT/${C_RESET}:"
    echo "---------------------------------------------------"

    BACKUPS=$(find "$BACKUP_ROOT" -maxdepth 1 -name "skyhero_v2_manual_backup_*.tar.gz" -printf "%f\n" | sort -r)
    
    if [ -z "$BACKUPS" ]; then
        echo -e "${C_YELLOW}No manual data backups found.${C_RESET}"
        read -p "Press [Enter] to return..."
        return
    fi

    COUNT=1
    for BFILE in $BACKUPS; do
        echo "  $COUNT) $BFILE"
        COUNT=$((COUNT+1))
    done
    echo "---------------------------------------------------"
    echo ""
    printf "Enter the number of the backup to restore, or 'q' to quit: "
    read -r choice

    if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
        echo -e "${C_YELLOW}Restore cancelled.${C_RESET}"
        read -p "Press [Enter] to return..."
        return
    fi

    # Validate choice is a number and within range
    if ! expr "$choice" : '^[0-9]*$' >/dev/null || [ "$choice" -lt 1 ] || [ "$choice" -ge "$COUNT" ]; then
        handle_error "Invalid choice. Please enter a valid number."
        return
    fi

    SELECTED_FILE=$(echo "$BACKUPS" | awk "NR==$choice")
    FULL_PATH_SELECTED_FILE="$BACKUP_ROOT/$SELECTED_FILE"

    echo ""
    echo -e "${C_YELLOW}WARNING: Restoring will OVERWRITE your current 'data' and 'db_backups' folders!${C_RESET}"
    echo -e "${C_YELLOW}This action cannot be undone.${C_RESET}"
    printf "Are you sure you want to restore from ${C_CYAN}$SELECTED_FILE${C_RESET}? [y/N]: "
    read -r confirm_restore

    case "$confirm_restore" in
        [yY][eE][sS]|[yY])
            TMP_RESTORE_DIR="/tmp/skyhero_restore_$$"
            mkdir -p "$TMP_RESTORE_DIR" || handle_error "Could not create temporary restore directory."

            echo "Restoring backup... This may take a moment."
            if tar -xzf "$FULL_PATH_SELECTED_FILE" -C "$TMP_RESTORE_DIR"; then
                # Remove current data and db_backups directories
                rm -rf "$DATA_DIR" "$BACKUP_DIR"
                
                # Move restored contents to BASE_DIR
                mv "$TMP_RESTORE_DIR/data" "$BASE_DIR/" || handle_error "Failed to move restored data folder."
                mv "$TMP_RESTORE_DIR/db_backups" "$BASE_DIR/" || handle_error "Failed to move restored db_backups folder."

                show_success "Backup restored successfully from $SELECTED_FILE."
            else
                handle_error "Failed to extract backup file."
            fi
            rm -rf "$TMP_RESTORE_DIR" # Clean up temp directory
            ;;
        *)
            echo -e "${C_YELLOW}Restore cancelled.${C_RESET}"
            read -p "Press [Enter] to return..."
            ;;
    esac
}

# --- Main Menu Logic ---
while true; do
    clear
    echo -e "${C_GREEN}--- Manual Data Backup & Restore ---${C_RESET}"
    echo "-----------------------------------"
    echo "1) Create New Full Data Backup"
    echo "2) Restore Full Data Backup"
    echo "3) Return to Main Menu"
    echo "-----------------------------------"
    echo -n "Enter your choice: "
    read -r choice

    case "$choice" in
        1) create_backup ;;
        2) restore_backup ;;
        3) exit 0 ;;
        *) echo -e "${C_RED}Invalid option.${C_RESET}" ; sleep 1 ;;
    esac
done
