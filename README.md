# Centrify ADClient Monitor for AIX

A bash script for monitoring Centrify ADClient (adclient) on AIX servers. This script tracks CPU usage and thread count, sending alerts when predefined thresholds are exceeded.

## Features

- Monitors CPU usage percentage of the adclient process
- Tracks thread count for the adclient process
- Sends email alerts when thresholds are exceeded
- Collects detailed diagnostics when issues are detected
- Includes alert cooldown mechanism to prevent alert storms
- Sends recovery notifications when metrics return to normal

## Requirements

- AIX operating system
- Centrify DirectControl installed
- Mail command configured for sending alerts
- Root access for execution

## Installation

1. Download the script to your AIX server:
```bash
curl -O https://raw.githubusercontent.com/rethinsilvester/centrify-monitor/main/centrify_monitor.sh
```

2. Make the script executable:
```bash
chmod +x centrify_monitor.sh
```

3. Test the script:
```bash
./centrify_monitor.sh -h
```

## Usage

```bash
./centrify_monitor.sh [options]
```

### Options

- `-c THRESHOLD` - CPU threshold percentage (default: 80)
- `-t THRESHOLD` - Thread count threshold (default: 100)
- `-i INTERVAL` - Check interval in seconds (default: 300)
- `-e EMAIL` - Email address for alerts (default: root@localhost)
- `-s` - Silent mode (no console output)
- `-l LOGFILE` - Log file path (default: /var/log/centrify_monitor.log)
- `-h` - Display help message

### Examples

Run with custom thresholds and email recipient:
```bash
./centrify_monitor.sh -c 70 -t 120 -i 600 -e admin@example.com
```

Run in silent mode with custom log file:
```bash
./centrify_monitor.sh -s -l /var/log/centrify_custom.log
```

### Running as a Service

To run the script as a service that starts automatically with the system:

1. Create a startup script in `/etc/rc.d/init.d/`
2. Configure it to start the monitoring script
3. Add it to the system startup sequence

### Crontab Setup

To run the script periodically using cron:

```
# Run every 5 minutes
*/5 * * * * /path/to/centrify_monitor.sh -s -l /var/log/centrify_monitor.log
```

## Logs and Diagnostics

- Default log location: `/var/log/centrify_monitor.log`
- Diagnostic files are created at `/tmp/centrify_diag_[TIMESTAMP].txt` when issues are detected

## License

MIT License
