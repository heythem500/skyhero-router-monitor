#!/bin/bash
# Dynamic data generation script for skyhero-v2 dashboard

set -e

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PERIOD_DIR="$BASE_DIR/data/period_data"
DAILY_DIR="$BASE_DIR/data/daily_json"

# Ensure directories exist
mkdir -p "$PERIOD_DIR" "$DAILY_DIR"

# Get current date
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
SEVEN_DAYS_AGO=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)
MONTH_START=$(date +%Y-%m-01)

# Function to generate realistic sample data
generate_period_data() {
    local start_date=$1
    local end_date=$2
    local output_file=$3
    local period_name=$4
    
    # Calculate days between dates for realistic data
    local days=1
    if [[ "$start_date" != "$end_date" ]]; then
        days=$(( ($(date -d "$end_date" +%s) - $(date -d "$start_date" +%s)) / 86400 + 1 ))
    fi
    
    # Generate realistic traffic data (scaled by days)
    local base_traffic=$(echo "scale=1; $days * (15 + $RANDOM % 20)" | bc)
    local dl=$(echo "scale=1; $base_traffic * 0.8" | bc)
    local ul=$(echo "scale=1; $base_traffic * 0.2" | bc)
    
    cat > "$output_file" << EOF
{
  "stats": {
    "traffic": $base_traffic,
    "dl": $dl,
    "ul": $ul,
    "devices": 6,
    "monthlyQuotaGB": 500
  },
  "devices": [
    {"name": "iPhone-12", "mac": "aa:bb:cc:dd:ee:01", "dl": $(echo "scale=1; $dl * 0.45" | bc), "ul": $(echo "scale=1; $ul * 0.45" | bc), "total": $(echo "scale=1; $base_traffic * 0.45" | bc), "percentage": 45.0, "topApps": [{"name": "Netflix", "total_bytes": $(echo "scale=0; $base_traffic * 0.45 * 0.5 * 1073741824" | bc)}, {"name": "YouTube", "total_bytes": $(echo "scale=0; $base_traffic * 0.45 * 0.3 * 1073741824" | bc)}, {"name": "Other Sources", "total_bytes": $(echo "scale=0; $base_traffic * 0.45 * 0.2 * 1073741824" | bc)}]},
    {"name": "MacBook-Pro", "mac": "aa:bb:cc:dd:ee:02", "dl": $(echo "scale=1; $dl * 0.30" | bc), "ul": $(echo "scale=1; $ul * 0.30" | bc), "total": $(echo "scale=1; $base_traffic * 0.30" | bc), "percentage": 30.0, "topApps": [{"name": "Zoom", "total_bytes": $(echo "scale=0; $base_traffic * 0.30 * 0.6 * 1073741824" | bc)}, {"name": "Google Drive", "total_bytes": $(echo "scale=0; $base_traffic * 0.30 * 0.25 * 1073741824" | bc)}, {"name": "Other Sources", "total_bytes": $(echo "scale=0; $base_traffic * 0.30 * 0.15 * 1073741824" | bc)}]},
    {"name": "iPad-Air", "mac": "aa:bb:cc:dd:ee:03", "dl": $(echo "scale=1; $dl * 0.15" | bc), "ul": $(echo "scale=1; $ul * 0.15" | bc), "total": $(echo "scale=1; $base_traffic * 0.15" | bc), "percentage": 15.0, "topApps": [{"name": "Safari", "total_bytes": $(echo "scale=0; $base_traffic * 0.15 * 0.7 * 1073741824" | bc)}, {"name": "Apple App Store", "total_bytes": $(echo "scale=0; $base_traffic * 0.15 * 0.2 * 1073741824" | bc)}, {"name": "Other Sources", "total_bytes": $(echo "scale=0; $base_traffic * 0.15 * 0.1 * 1073741824" | bc)}]},
    {"name": "Smart-TV", "mac": "aa:bb:cc:dd:ee:04", "dl": $(echo "scale=1; $dl * 0.07" | bc), "ul": $(echo "scale=1; $ul * 0.07" | bc), "total": $(echo "scale=1; $base_traffic * 0.07" | bc), "percentage": 7.0, "topApps": [{"name": "Disney+", "total_bytes": $(echo "scale=0; $base_traffic * 0.07 * 0.8 * 1073741824" | bc)}, {"name": "Hulu", "total_bytes": $(echo "scale=0; $base_traffic * 0.07 * 0.15 * 1073741824" | bc)}, {"name": "Other Sources", "total_bytes": $(echo "scale=0; $base_traffic * 0.07 * 0.05 * 1073741824" | bc)}]},
    {"name": "Gaming-Console", "mac": "aa:bb:cc:dd:ee:05", "dl": $(echo "scale=1; $dl * 0.03" | bc), "ul": $(echo "scale=1; $ul * 0.03" | bc), "total": $(echo "scale=1; $base_traffic * 0.03" | bc), "percentage": 3.0, "topApps": [{"name": "Steam", "total_bytes": $(echo "scale=0; $base_traffic * 0.03 * 0.7 * 1073741824" | bc)}, {"name": "Xbox Live", "total_bytes": $(echo "scale=0; $base_traffic * 0.03 * 0.2 * 1073741824" | bc)}, {"name": "Other Sources", "total_bytes": $(echo "scale=0; $base_traffic * 0.03 * 0.1 * 1073741824" | bc)}]}
  ],
  "barChart": {
    "labels": ["$end_date"],
    "values": [$base_traffic],
    "title": "Daily Traffic ($period_name)"
  },
  "topApps": [
    {"name": "YouTube", "total": $(echo "scale=1; $base_traffic * 0.28" | bc)},
    {"name": "Netflix", "total": $(echo "scale=1; $base_traffic * 0.23" | bc)},
    {"name": "Zoom", "total": $(echo "scale=1; $base_traffic * 0.10" | bc)},
    {"name": "Chrome", "total": $(echo "scale=1; $base_traffic * 0.08" | bc)},
    {"name": "WhatsApp", "total": $(echo "scale=1; $base_traffic * 0.05" | bc)},
    {"name": "Steam", "total": $(echo "scale=1; $base_traffic * 0.04" | bc)},
    {"name": "Safari", "total": $(echo "scale=1; $base_traffic * 0.03" | bc)},
    {"name": "Instagram", "total": $(echo "scale=1; $base_traffic * 0.03" | bc)},
    {"name": "Facebook", "total": $(echo "scale=1; $base_traffic * 0.03" | bc)},
    {"name": "Spotify", "total": $(echo "scale=1; $base_traffic * 0.02" | bc)}
  ]
}
EOF
}

# Generate all required period files
echo "Generating dynamic period data for $TODAY..."

# Today
generate_period_data "$TODAY" "$TODAY" "$PERIOD_DIR/traffic_period_${TODAY}_${TODAY}.json" "Today"

# Yesterday
generate_period_data "$YESTERDAY" "$YESTERDAY" "$PERIOD_DIR/traffic_period_${YESTERDAY}_${YESTERDAY}.json" "Yesterday"

# Last 7 days
generate_period_data "$SEVEN_DAYS_AGO" "$TODAY" "$PERIOD_DIR/traffic_period_${SEVEN_DAYS_AGO}_${TODAY}.json" "Last 7 Days"

# This month
generate_period_data "$MONTH_START" "$TODAY" "$PERIOD_DIR/traffic_period_${MONTH_START}_${TODAY}.json" "This Month"

# All time (cumulative)
generate_period_data "2025-01-01" "$TODAY" "$PERIOD_DIR/traffic_period_all-time.json" "All Time"

echo "✅ Generated dynamic period data for $TODAY"
echo "Files created:"
ls -la "$PERIOD_DIR"/traffic_period_*.json