#!/bin/ash
# period_builder.sh – build traffic_period_START_END.json

############################################################
# BusyBox-safe helpers – paste once at top of every script #
############################################################

# ---------- integer_add  (posix calc without $(( )) ) ----------
integer_add() { awk "BEGIN{print $1 + $2}"; }

# ---------- epoch_from_ISO  (YYYY-MM-DD → seconds) --------------
epoch_from_ISO() {
    # BusyBox date understands “-d”, but some builds don’t; fall back to awk
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

# ---------- ISO_from_epoch  (seconds → YYYY-MM-DD) --------------
iso_from_epoch() { awk -v ts="$1" 'BEGIN { print strftime("%Y-%m-%d", ts) }'; }

# ---------- yesterday() – returns yesterday’s ISO date ----------
yesterday() {
    now=$(date +%s)
    epoch_yest=$(integer_add "$now" -86400)
    iso_from_epoch "$epoch_yest"
}

############################################################
#                ←  END OF HELPER BLOCK                   #
############################################################


# ---------- resolve BASE_DIR once, then source config ----------
[ -z "${BASE_DIR+x}" ] && BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/scripts/config.sh"
. "$BASE_DIR/scripts/helpers.sh"
# ---------------------------------------------------------------

# Check database health before proceeding
restore_live_db_if_needed

start="$1"; end="$2"; out="$3"
tmpdir="/tmp/pb_$$"; mkdir -p "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT

# 1. Build a list of files to process
file_list=""
epoch_start=$(epoch_from_ISO "$start")
epoch_end=$(epoch_from_ISO "$end")

cur=$epoch_start
while [ "$(integer_add "$cur" 0)" -le "$(integer_add "$epoch_end" 0)" ]; do
    day=$(iso_from_epoch "$cur")
    f="$DAILY_DIR/$day.json"
    if [ ! -f "$f" ]; then
        "$SCRIPTS_DIR/daily_rollup.sh" "$day"
    fi
    if [ -s "$f" ]; then
        # Verify checksum if it exists
        if [ -f "${f}.sha256" ]; then
            stored_sum=$(cat "${f}.sha256" | awk '{print $1}')
            current_sum=$(sha256sum "$f" | awk '{print $1}')
            if [ "$stored_sum" = "$current_sum" ]; then
                 file_list="$file_list $f"
            else
                 "$SCRIPTS_DIR/daily_rollup.sh" "$day"
                 # Re-check if file is valid now
                 if [ -s "$f" ]; then
                    file_list="$file_list $f"
                 else
                    echo "ERROR: File $f is still invalid after re-running rollup." >&2
                 fi
            fi
        else
            file_list="$file_list $f"
        fi
    else
        echo "ERROR: File $f is empty or still not found after rollup attempt." >&2
    fi
    cur=$(integer_add "$cur" 86400)
done

# Transform the file list into positional parameters for jq
# The shell will split the string on spaces/newlines correctly
set -- $file_list

if [ $# -eq 0 ]; then
   echo "ERROR: period_builder: no valid daily files found for range $start to $end" >&2
   exit 1
fi

########################################
# Aggregate with jq (multiple args)
########################################
JQ_SCRIPT_FILE="$tmpdir/jq_program.jq"
days_in_period=$#

cat <<'EOF' > "$JQ_SCRIPT_FILE"
# Helper to convert bytes to GB, rounded to 2 decimal places.
def bytes_to_gb: . / 1073741824 | (.*100 | round) / 100;

reduce .[] as $d (
  {stats:{traffic:0,dl:0,ul:0,devices:0,monthlyQuotaGB:($monthly_quota_gb | tonumber)},
   barChart:{labels:[],values:[]},
   devices:[],topApps:[]} ;
  .stats.traffic += $d.stats.traffic |
  .stats.dl      += $d.stats.dl      |
  .stats.ul      += $d.stats.ul      |
  .barChart.labels += $d.barChart.labels |
  .barChart.values += $d.barChart.values |
  .devices        += ($d.devices | map(. + {date: $d.barChart.labels[0]})) |
  .topApps        += $d.topApps
)
| . as $aggregated_data
| $aggregated_data.stats.traffic as $total_traffic_gb
| .devices = (
    $aggregated_data.devices
    | group_by(.mac)
    | map({
        mac: .[0].mac,
        name: (.[0].name // "Unknown Device"),
        dl_bytes: (map(.dl_bytes) | add),
        ul_bytes: (map(.ul_bytes) | add),
        total_bytes: (map(.total_bytes) | add),
        daily_traffic: map({date: .date, total_bytes: (.total_bytes // 0)}),
        topApps: (map(.topApps[]) | group_by(.name) | map({name: .[0].name, total_bytes: (map(.total_bytes) | add)}) | sort_by(-.total_bytes) | .[:5])
      })
    | map(select(.total_bytes > 5368709))
    | map(. + {
        dl: (.dl_bytes | bytes_to_gb),
        ul: (.ul_bytes | bytes_to_gb),
        total: (.total_bytes | bytes_to_gb),
        avg_daily_gb: (if ($days_in_period | tonumber) > 0 then ((.total_bytes | bytes_to_gb) / ($days_in_period | tonumber)) else 0 end),
        peak_day: (if (.daily_traffic | length) > 0 then (.daily_traffic | max_by(.total_bytes) | {date: .date, gb: ((.total_bytes // 0) | bytes_to_gb)}) else {date: "N/A", gb: 0} end),
        trend_bytes: (.daily_traffic | map(.total_bytes))
      })
    | map(. + {
        percentage: (if $total_traffic_gb > 0 then ((.total / $total_traffic_gb) * 100) else 0 end)
      })
    | sort_by(-.total_bytes)
  )
| .stats.devices = (.devices | length)
| .topApps = ($aggregated_data.topApps
  | group_by(.name)
  | map({
      name: .[0].name,
      total_bytes: (map(.total_bytes) | add)
    })
  | map(. + {
      total: (.total_bytes | bytes_to_gb)
    })
  | sort_by(-.total_bytes)
  | .[0:10]
)
| .barChart.title = "Daily Breakdown (\($s) to \($e))"
EOF

jq -s --arg s "$start" --arg e "$end" --arg days_in_period "$days_in_period" --arg monthly_quota_gb "$MONTHLY_QUOTA_GB" -f "$JQ_SCRIPT_FILE" "$@" > "${out}.tmp"

JQ_EXIT_CODE=$?
if [ $JQ_EXIT_CODE -ne 0 ]; then
    echo "ERROR: jq command failed with exit code $JQ_EXIT_CODE" >&2
    exit $JQ_EXIT_CODE
fi

# Atomic move
mv "${out}.tmp" "$out"
chmod 644 "$out"
