#!/bin/bash
#
# centrify_monitor.sh - Monitors Centrify ADClient CPU usage and thread count on AIX
# 
# This script monitors the Centrify ADClient (adclient) on AIX systems,
# checking for excessive CPU usage and thread count, and sends alerts
# when predefined thresholds are exceeded.
#
# Author: Rethin Silvester 
# Date: May 2, 2022
# Version: 1.0
#
# Usage: ./centrify_monitor.sh [options]
#   Options:
#     -c THRESHOLD  CPU threshold percentage (default: 80)
#     -t THRESHOLD  Thread count threshold (default: 100)
#     -i INTERVAL   Check interval in seconds (default: 300)
#     -e EMAIL      Email address for alerts (default: root@localhost)
#     -s            Silent mode (no console output)
#     -l LOGFILE    Log file path (default: /var/log/centrify_monitor.log)
#     -h            Display this help message
#
# Example:
#   ./centrify_monitor.sh -c 70 -t 120 -i 600 -e admin@example.com
#
# Crontab example (run every 5 minutes):
#   */5 * * * * /path/to/centrify_monitor.sh -s -l /var/log/centrify_monitor.log
#

# Default configuration
CPU_THRESHOLD=80
THREAD_THRESHOLD=100
CHECK_INTERVAL=300
EMAIL_ALERT="root@localhost"
SILENT_MODE=false
LOG_FILE="/var/log/centrify_monitor.log"
HOSTNAME=$(hostname)

# Process management
PID_FILE="/var/run/centrify_monitor.pid"

# Parse command line arguments
while getopts "c:t:i:e:sl:h" opt; do
  case $opt in
    c) CPU_THRESHOLD=$OPTARG ;;
    t) THREAD_THRESHOLD=$OPTARG ;;
    i) CHECK_INTERVAL=$OPTARG ;;
    e) EMAIL_ALERT=$OPTARG ;;
    s) SILENT_MODE=true ;;
    l) LOG_FILE=$OPTARG ;;
    h) 
      echo "Usage: $0 [options]"
      echo "  Options:"
      echo "    -c THRESHOLD  CPU threshold percentage (default: 80)"
      echo "    -t THRESHOLD  Thread count threshold (default: 100)"
      echo "    -i INTERVAL   Check interval in seconds (default: 300)"
      echo "    -e EMAIL      Email address for alerts (default: root@localhost)"
      echo "    -s            Silent mode (no console output)"
      echo "    -l LOGFILE    Log file path (default: /var/log/centrify_monitor.log)"
      echo "    -h            Display this help message"
      exit 0
      ;;
    \?) 
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :) 
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Create log directory if it doesn't exist
log_dir=$(dirname "$LOG_FILE")
if [ ! -d "$log_dir" ]; then
    mkdir -p "$log_dir"
    chmod 755 "$log_dir"
fi

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Display on console if not in silent mode
    if [ "$SILENT_MODE" = false ]; then
        echo "[$timestamp] [$level] $message"
    fi
}

# Function to send email alerts
send_alert() {
    local subject="$1"
    local message="$2"
    
    echo "$message" | mail -s "$subject" "$EMAIL_ALERT"
    log_message "ALERT" "Email alert sent to $EMAIL_ALERT: $subject"
}

# Function to check if adclient is running
check_adclient_running() {
    if ! pgrep adclient > /dev/null; then
        log_message "ERROR" "Centrify ADClient (adclient) is not running!"
        send_alert "CRITICAL: Centrify ADClient not running on $HOSTNAME" \
                  "The Centrify ADClient process (adclient) is not running on server $HOSTNAME. Please investigate immediately."
        return 1
    fi
    return 0
}

# Function to get adclient CPU usage
get_adclient_cpu() {
    # On AIX, use ps with appropriate flags to get CPU percentage
    local cpu_usage=$(ps -o pcpu -p $(pgrep adclient) | grep -v "%CPU" | awk '{sum+=$1} END {print sum}')
    
    # If empty, set to 0
    if [ -z "$cpu_usage" ]; then
        cpu_usage=0
    fi
    
    echo "$cpu_usage"
}

# Function to get adclient thread count
get_adclient_threads() {
    # On AIX, use ps -m to show threads and count them
    local thread_count=$(ps -m -o THREAD -p $(pgrep adclient) | grep -v "THREAD" | wc -l | tr -d ' ')
    
    # If empty, set to 0
    if [ -z "$thread_count" ]; then
        thread_count=0
    fi
    
    echo "$thread_count"
}

# Function to collect detailed diagnostic information
collect_diagnostics() {
    local diag_file="/tmp/centrify_diag_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "=== Centrify ADClient Diagnostics ==="
        echo "Date: $(date)"
        echo "Hostname: $HOSTNAME"
        echo ""
        
        echo "=== System Information ==="
        uname -a
        echo ""
        
        echo "=== Memory Usage ==="
        svmon -G
        echo ""
        
        echo "=== CPU Information ==="
        lparstat -i
        echo ""
        
        echo "=== Process Information ==="
        ps -ef | grep adclient
        echo ""
        
        echo "=== Thread Information ==="
        ps -m -p $(pgrep adclient)
        echo ""
        
        echo "=== Network Connections ==="
        netstat -an | grep -E '(389|636|88|464)'  # LDAP, LDAPS, Kerberos ports
        echo ""
        
        echo "=== Centrify Status ==="
        if command -v adinfo &> /dev/null; then
            adinfo
        else
            echo "adinfo command not found"
        fi
        echo ""
        
        echo "=== Recent ADClient Log Entries ==="
        if [ -f /var/log/centrifydc.log ]; then
            tail -n 100 /var/log/centrifydc.log
        else
            echo "Centrify log file not found"
        fi
        
    } > "$diag_file"
    
    log_message "INFO" "Diagnostics collected at $diag_file"
    return "$diag_file"
}

# Function to check for a previous instance
check_previous_instance() {
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat "$PID_FILE")
        if ps -p "$old_pid" &>/dev/null; then
            log_message "WARNING" "Previous instance is still running (PID: $old_pid). Exiting."
            exit 1
        else
            log_message "INFO" "Removing stale PID file."
            rm -f "$PID_FILE"
        fi
    fi
    
    # Create new PID file
    echo $$ > "$PID_FILE"
}

# Function to clean up before exit
cleanup() {
    log_message "INFO" "Script terminating, cleaning up..."
    rm -f "$PID_FILE"
    exit 0
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Main monitoring function
monitor_adclient() {
    local cpu_usage=0
    local thread_count=0
    local alert_sent=false
    local alert_cooldown=0
    
    log_message "INFO" "Starting Centrify ADClient monitoring (CPU threshold: ${CPU_THRESHOLD}%, Thread threshold: $THREAD_THRESHOLD)"
    
    while true; do
        # Check if adclient is running
        if check_adclient_running; then
            # Get CPU usage and thread count
            cpu_usage=$(get_adclient_cpu)
            thread_count=$(get_adclient_threads)
            
            log_message "INFO" "ADClient CPU usage: ${cpu_usage}%, Thread count: $thread_count"
            
            # Check thresholds
            if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) )) || [ "$thread_count" -gt "$THREAD_THRESHOLD" ]; then
                # Only send an alert if we haven't sent one recently (avoid alert storms)
                if [ "$alert_sent" = false ] || [ "$alert_cooldown" -le 0 ]; then
                    diag_file=$(collect_diagnostics)
                    
                    # Prepare alert message
                    alert_subject="WARNING: Centrify ADClient high resource usage on $HOSTNAME"
                    alert_message="Centrify ADClient (adclient) on server $HOSTNAME is showing high resource usage:

CPU Usage: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)
Thread Count: $thread_count (threshold: $THREAD_THRESHOLD)

Diagnostics have been collected to: $diag_file

Please investigate as soon as possible."

                    # Send alert
                    send_alert "$alert_subject" "$alert_message"
                    
                    # Set alert cooldown (don't send another alert for 1 hour)
                    alert_sent=true
                    alert_cooldown=12
                else
                    log_message "INFO" "Alert cooldown active, not sending new alert"
                    alert_cooldown=$((alert_cooldown - 1))
                fi
            else
                # Reset alert status if we're back below thresholds
                if [ "$alert_sent" = true ]; then
                    log_message "INFO" "Resource usage returned to normal levels"
                    
                    # Send recovery notification
                    recovery_subject="RESOLVED: Centrify ADClient resource usage normal on $HOSTNAME"
                    recovery_message="Centrify ADClient (adclient) on server $HOSTNAME has returned to normal resource levels:

CPU Usage: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)
Thread Count: $thread_count (threshold: $THREAD_THRESHOLD})"

                    send_alert "$recovery_subject" "$recovery_message"
                fi
                
                alert_sent=false
                alert_cooldown=0
            fi
        fi
        
        # Wait for next check
        sleep "$CHECK_INTERVAL"
    done
}

# Initialize log file
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Check for previous instance
check_previous_instance

# Start monitoring
monitor_adclient
