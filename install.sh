#!/bin/ash
#
# Installation script for the Superman-v2 monitoring system.
# This script should be run once to set up the entire system.
#
set -eu

############################################################
# BusyBox-safe helpers – paste once at top of every script #
############################################################

# Ensure we are running under ash

# ---------- integer_add  (posix calc without $(( )) ) ----------
integer_add() { awk "BEGIN{print $1 + $2}"; }

# ---------- epoch_from_ISO  (YYYY-MM-DD → seconds) --------------
epoch_from_ISO() {
    # BusyBox date understands "-d", but some builds don't; fall back to awk
    if date -d "$1 00:00:00" +%s >/dev/null 2>&1; then
        date -d "$1 00:00:00" +%s
    else
        # Lightweight POSIX fallback
        year=$(echo "$1" | cut -d'-' -f1); mon=$(echo "$1" | cut -d'-' -f2); day=$(echo "$1" | cut -d'-' -f3)
        # seconds to start of 1970-01-01 → year / leap-year calc in awk
        awk -v y=$year -v m=$mon -v d=$day << AWK_SCRIPT_END
          BEGIN{
            mdays[1]=31;mdays[2]=28;mdays[3]=31;mdays[4]=30;mdays[5]=31;mdays[6]=30;
            mdays[7]=31;mdays[8]=31;mdays[9]=30;mdays[10]=31;mdays[11]=30;mdays[12]=31;
            secs=0
            for (yr=1970; yr<y; yr++){
               leap=((yr%4==0 && yr%100!=0)|| yr%400==0)
               secs+= (leap?366:365)*86400
            }
            leap=((y%4==0 && y%100!=0)|| y%400==0)
            mdays[2]=leap?29:28
            for (i=1;i<m;i++) secs+=mdays[i]*86400
            secs+=(d-1)*86400
            print secs
          }
AWK_SCRIPT_END
    fi
}

# ---------- ISO_from_epoch  (seconds → YYYY-MM-DD) --------------
iso_from_epoch() { awk -v ts="$1" 'BEGIN { print strftime("%Y-%m-%d", ts) }'; }

# ---------- yesterday() – returns yesterday's ISO date ----------
yesterday() {
    now=$(date +%s)
    epoch_yest=$(integer_add "$now" -86400)
    iso_from_epoch "$epoch_yest"
}

# ---------- version_ge (version1 >= version2) ----------
version_ge() {
    local v1="$1"
    local v2="$2"
    local IFS='.' # Internal Field Separator for splitting version parts

    # Read version parts into separate variables for ash compatibility
    set -- $v1
    local v1_major=$1 v1_minor=$2 v1_patch=$3

    set -- $v2
    local v2_major=$1 v2_minor=$2 v2_patch=$3

    # Compare major versions
    if [ "$v1_major" -gt "$v2_major" ]; then return 0; fi
    if [ "$v1_major" -lt "$v2_major" ]; then return 1; fi

    # If major versions are equal, compare minor versions
    if [ "$v1_minor" -gt "$v2_minor" ]; then return 0; fi
    if [ "$v1_minor" -lt "$v2_minor" ]; then return 1; fi

    # If major and minor are equal, compare patch versions
    if [ "$v1_patch" -ge "$v2_patch" ]; then return 0; fi

    return 1 # v1 is less than v2
}

############################################################
#                ←  END OF HELPER BLOCK                   #
############################################################

# Define the Base Directory for the project.
export BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source the central configuration to create directories and set variables.
. "$BASE_DIR/scripts/config.sh"

# --- Color Definitions ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_RESET='\033[0m'

# --- Helper Functions ---
handle_error() {
    echo -e "\n${C_RED}--- INSTALLATION FAILED ---${C_RESET}" >&2
    echo -e "${C_RED}ERROR: $1${C_RESET}" >&2
    # Also log to file
    echo -e "\n--- INSTALLATION FAILED ---" >> "$LOGS_DIR/install.log"
    echo -e "ERROR: $1" >> "$LOGS_DIR/install.log"
    exit 1
}

# BusyBox-compatible process management
kill_process() {
    pattern="$1"
    pid=$(ps | grep "$pattern" | grep -v grep | awk '{print $1}')
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
    fi
}

check_process() {
    pattern="$1"
    ps | grep "$pattern" | grep -v grep | awk '{print $1}'
}

# --- Dependency Check Function ---
check_dependencies() {
    echo "--- Checking System Dependencies ---"
    local missing_deps=0

    # 1. Check for Entware (or similar /opt environment)
    echo -n "Checking for Entware environment (/opt/bin in PATH or /opt directory)... "
    if echo "$PATH" | grep -q "/opt/bin" || [ -d "/opt" ]; then
        echo -e "${C_GREEN}✅ Found. ${C_RESET}"
    else
        echo -e "${C_YELLOW}⚠️ Not found. Many dependencies are typically installed via Entware.${C_RESET}"
        echo "   Consider installing Entware first: https://github.com/RMerl/asuswrt-merlin.ng/wiki/Entware"
        # This is a warning, not a critical failure, as some tools might be native.
    fi

    # 2. Check for lighttpd
    echo -n "Checking for lighttpd... "
    if lighttpd -v >/dev/null 2>&1; then # Try to get version, redirect stdout/stderr to /dev/null
        # Additional check: ensure the standard config directory exists
        if [ -d "/opt/etc/lighttpd" ]; then
            echo -e "${C_GREEN}✅ Found. ${C_RESET}"
        else
            echo -e "${C_RED}❌ Found (binary), but /opt/etc/lighttpd directory is missing. ${C_RESET}"
            echo "   Please reinstall lighttpd to restore its configuration files and directories."
            echo "   If you use Entware, run: opkg install lighttpd"
            missing_deps=1
        fi
    elif [ -x "/opt/bin/lighttpd" ] && "/opt/bin/lighttpd" -v >/dev/null 2>&1; then # Fallback check for /opt/bin and try to get version
        # Additional check for fallback: ensure the standard config directory exists
        if [ -d "/opt/etc/lighttpd" ]; then
            echo -e "${C_GREEN}✅ Found (in /opt/bin). ${C_RESET}"
            echo "   Ensure /opt/bin is in your PATH for full functionality."
        else
            echo -e "${C_RED}❌ Found (binary in /opt/bin), but /opt/etc/lighttpd directory is missing. ${C_RESET}"
            echo "   Please reinstall lighttpd to restore its configuration files and directories."
            echo "   If you use Entware, run: opkg install lighttpd"
            missing_deps=1
        fi
    else
        echo -e "${C_RED}❌ Not found. ${C_RESET}"
        echo "   Please install lighttpd. If you use Entware, run: opkg install lighttpd"
        missing_deps=1
    fi

    # 3. Check for jq
    echo -n "Checking for jq... "
    if type jq >/dev/null 2>&1; then
        echo -e "${C_GREEN}✅ Found. ${C_RESET}"
    elif [ -x "/opt/bin/jq" ]; then # Fallback check for /opt/bin
        echo -e "${C_GREEN}✅ Found (in /opt/bin). ${C_RESET}"
        echo "   Ensure /opt/bin is in your PATH for full functionality."
    else
        echo -e "${C_RED}❌ Not found. ${C_RESET}\n"
        echo "   Please install jq. If you use Entware, run: opkg install jq"
        missing_deps=1
    fi

    # 4. Check for sqlite3 and its version
    echo -n "Checking for sqlite3... "
    if ! type sqlite3 >/dev/null 2>&1; then
        echo -e "${C_RED}❌ Not found. ${C_RESET}\n"
        echo "   This is usually pre-installed on ASUS-Merlin. Ensure your PATH is correct."
        missing_deps=1
    else
        local sqlite_version=$(sqlite3 --version | awk '{print $1}')
        local required_version="3.41.0" # Minimum version for .backup and .mode json
        if version_ge "$sqlite_version" "$required_version"; then
            echo -e "${C_GREEN}✅ Found ( $sqlite_version) and meets version requirements.${C_RESET}"
        else
            echo -e "${C_RED}❌ Found ( $sqlite_version) but is older than required ($required_version).${C_RESET}\n"
            echo "   Functionality may be limited. Consider updating sqlite3 if possible (e.g., via Entware)."
            missing_deps=1
        fi
    fi

    echo "------------------------------------"
    return $missing_deps
}

# --- Main Installation Logic ---

echo "--- Starting Superman-Tracking v2.0 Installation/Update ---"

check_dependencies || handle_error "Missing critical dependencies. Please install them and try again."

echo "Ensuring directories exist..."
mkdir -p "$DAILY_DIR" "$PERIOD_DIR" "$BACKUP_DIR" "$LOGS_DIR" "$WWW_DIR" || handle_error "Could not create required directories. Check permissions for $BASE_DIR."

# 2. Make all scripts executable
echo "Setting script permissions..."
chmod +x "$SCRIPTS_DIR"/*.sh || handle_error "Could not set permissions on scripts in $SCRIPTS_DIR."
chmod +x "$WWW_DIR"/*.sh || handle_error "Could not set permissions on CGI script in "$WWW_DIR"."

# 3. Stop any existing daemon process
echo -e "${C_YELLOW}Stopping existing background daemon(s) (if any)...${C_RESET}"
kill_process "auto_period_generator.sh"
sleep 1

# 4. Set up Cron Jobs
echo "Updating cron jobs..."
cru d roll_yesterday 2>/dev/null
cru d roll_today 2>/dev/null
cru d traffic_monitor 2>/dev/null
cru d db_backup 2>/dev/null
cru d daemon_watchdog 2>/dev/null
cru d monthly_aggregator 2>/dev/null

cru a roll_yesterday "5 0 * * *" "$SCRIPTS_DIR/daily_rollup.sh yesterday" || handle_error "Failed to add the 'roll_yesterday' cron job."
cru a roll_today "*/5 * * * *" "$SCRIPTS_DIR/daily_rollup.sh today" || handle_error "Failed to add the 'roll_today' cron job."
cru a traffic_monitor "*/5 * * * *" "$SCRIPTS_DIR/traffic_monitor.sh" || handle_error "Failed to add the 'traffic_monitor' cron job."
cru a db_backup "0 */2 * * *" "$SCRIPTS_DIR/backup_db.sh" || handle_error "Failed to add the 'db_backup' cron job."
cru a daemon_watchdog "* * * * *" "$SCRIPTS_DIR/daemon_watchdog.sh" || handle_error "Failed to add the 'daemon_watchdog' cron job."
cru a monthly_aggregator "5 2 * * *" "$SCRIPTS_DIR/monthly_aggregator.sh" || handle_error "Failed to add the 'monthly_aggregator' cron job."
echo "Cron jobs have been set successfully." 

# 5. Start the Background Daemon
echo "Launching auto_period_generator daemon …"

# Kick it off in the background
nohup "$SCRIPTS_DIR/auto_period_generator.sh" >> "$LOGS_DIR/auto_period_generator.debug.log" 2>&1 &

# Give the kernel a moment to create the new ps entry
sleep 1

# Verify that the process is really running
if check_process "auto_period_generator.sh" >/dev/null; then
    echo "auto_period_generator is running."
else
    handle_error "Failed to start the background daemon (auto_period_generator.sh)."
fi

# 6. Create symlink for easy access
echo "Creating 'skyhero' command symlink..."
SYMLINK_PATH="/opt/bin/skyhero"
SYMLINK_CREATED=false
if [ -w "/opt/bin" ]; then
    ln -sf "$SCRIPTS_DIR/menu.sh" "$SYMLINK_PATH" || handle_error "Failed to create symlink for 'skyhero' command."
    echo "Symlink created: You can now type 'skyhero' to launch the menu."
else
    echo "You will need to run the menu using: $SCRIPTS_DIR/menu.sh"
fi

# 7. Generate initial data files and perform one-time upgrade
UPGRADE_FLAG_FILE="$DATA_DIR/.history_upgraded"
if [ ! -f "$UPGRADE_FLAG_FILE" ]; then
    echo "Performing one-time upgrade of historical data. This may take a few minutes..."
    "$SCRIPTS_DIR/history_harvest.sh"
    touch "$UPGRADE_FLAG_FILE"
    echo "Historical data upgrade complete."
else
    echo "Historical data already upgraded. Skipping."
fi

echo "Generating initial period reports..."
"$SCRIPTS_DIR/traffic_monitor.sh" || echo "Warning: traffic_monitor.sh failed, but this may be okay if data is still harvesting."

# 8. Make the startup script executable
chmod +x "$SCRIPTS_DIR/startup.sh"

# 9. Add to router's main startup script
STARTUP_SCRIPT_PATH="/jffs/scripts/services-start"
if [ -f "$STARTUP_SCRIPT_PATH" ]; then
    # Ensure the script is executable
    chmod +x "$STARTUP_SCRIPT_PATH"
    # Add our startup script call if it's not already there
    if ! grep -q "$SCRIPTS_DIR/startup.sh" "$STARTUP_SCRIPT_PATH"; then
        echo "Adding startup call to $STARTUP_SCRIPT_PATH..."
        echo "
# Start Superman-Tracking v2.0 services" >> "$STARTUP_SCRIPT_PATH"
        echo "$SCRIPTS_DIR/startup.sh &" >> "$STARTUP_SCRIPT_PATH"
    fi
else
    echo "Warning: $STARTUP_SCRIPT_PATH not found. Cannot ensure persistence across reboots." >&2
fi

# 10. Final Confirmation

echo -e "\n${C_GREEN}--- Installation/Update Complete! ---${C_RESET}"
echo -e "The Superman-Tracking v2.0 monitor components have been installed/updated."

echo -e "\nTo access the dashboard, open your web browser to:\n${C_CYAN}http://<your_router_ip>:8081/skyhero-v2/${C_RESET}\n(Or your configured lighttpd port)"

# Launch the management menu
"$SCRIPTS_DIR/menu.sh"
