#!/bin/ash
#
# BusyBox-safe helpers for Superman-v2 Dashboard scripts.
#

# ---------- integer_add (posix calc without $(( )) ) ----------
integer_add() { awk "BEGIN{print $1 + $2}"; }

# ---------- epoch_from_ISO (YYYY-MM-DD -> seconds) --------------
epoch_from_ISO() {
    # BusyBox date understands "-d", but some builds don't; fall back to awk
    if date -d "$1 00:00:00" +%s >/dev/null 2>&1; then
        date -d "$1 00:00:00" +%s
    else
        # Lightweight POSIX fallback
        year=$(echo "$1" | cut -d'-' -f1); mon=$(echo "$1" | cut -d'-' -f2); day=$(echo "$1" | cut -d'-' -f3)
        awk -v y=$year -v m=$mon -v d=$day << 'AWK_SCRIPT_END'
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

# ---------- ISO_from_epoch (seconds -> YYYY-MM-DD) --------------
iso_from_epoch() { awk -v ts="$1" 'BEGIN { print strftime("%Y-%m-%d", ts) }'; }

# ---------- yesterday() returns yesterday's ISO date ----------
yesterday() {
    now=$(date +%s)
    epoch_yest=$(integer_add "$now" -86400)
    iso_from_epoch "$epoch_yest"
}

# ---------- restore_live_db_if_needed() ----------
restore_live_db_if_needed() {
    live="$LIVE_DB"
    RESTORE_LOG="$LOGS_DIR/db_restore_history.log"
    
    # Check if DB is missing or corrupt
    [ -f "$live" ] || integrity=fail
    [ "${integrity:-ok}" = "fail" ] || \
        integrity=$(sqlite3 "$live" 'PRAGMA quick_check;' 2>/dev/null || echo fail)

    if [ "$integrity" != "ok" ]; then
        timestamp=$(date '+%F %T')
        
        # Log when corruption detected
        echo "[$timestamp] DETECTED: TrafficAnalyzer.db is missing/corrupt" >> "$RESTORE_LOG"
        
        newest=$(ls -1t "$BACKUP_DIR"/TrafficAnalyzer_*.db.gz 2>/dev/null | head -1)
        
        if [ -n "$newest" ]; then
            if gunzip -c "$newest" > "$live.tmp" && mv "$live.tmp" "$live" && chmod 600 "$live"; then
                # Log successful restore
                restore_time=$(date '+%F %T')
                echo "[$restore_time] RESTORED: Successfully restored from $(basename "$newest")" >> "$RESTORE_LOG"
                echo "[$restore_time] TIME GAP: DB was unavailable between $timestamp and $restore_time" >> "$RESTORE_LOG"
                
                # Create marker for dashboard
                echo "$timestamp|$restore_time|$(basename "$newest")" > "$DATA_DIR/last_restore.txt"
            else
                echo "[$timestamp] FAILED: Could not restore from $(basename "$newest")" >> "$RESTORE_LOG"
            fi
        else
            echo "[$timestamp] CRITICAL: No backup available to restore from" >> "$RESTORE_LOG"
        fi
    fi
}