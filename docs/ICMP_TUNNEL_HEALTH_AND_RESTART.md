# ICMP Tunnel: Health Check and Scheduled Restart

This document explains the health check and scheduled restart features for ICMP Tunnel, including the comprehensive protection mechanisms against infinite restart loops.

## Overview

Two automated restart features are available:

1. **Health Check** - Monitors service health and restarts on failure
2. **Scheduled Restart** - Periodic restarts on a fixed schedule (cron-based)

Both features share the same **restart protection system** to prevent infinite restart loops and conflicts.

## Features

### Health Check (Recommended)

Automatically monitors ICMP Tunnel service health and restarts only when problems are detected.

**Client Health Checks:**
- SOCKS5 proxy listening check
- SOCKS5 proxy functionality test (HTTP request via curl)
- Service active status check
- 3 retry attempts before declaring failure

**Server Health Checks:**
- Service active status check
- Recent log analysis (scans for error patterns)
- Detects connection issues, timeouts, errors
- No logs in 10 minutes = potential stuck service

**Check Intervals:**
- Every 2 minutes (frequent monitoring)
- Every 5 minutes (recommended - balanced)
- Every 10 minutes (conservative)

**Log Location:** `/var/log/icmptunnel-health-{server|client}.log`

### Scheduled Restart (Optional)

Periodic service restarts on a fixed schedule, useful for:
- Memory leak mitigation
- Connection refresh
- Preventive maintenance

**Available Intervals:**
- Every 10 minutes (testing only - not recommended)
- Every 30 minutes (frequent)
- Every 1 hour (balanced - recommended)
- Every 2 hours (conservative)
- Every 4 hours (conservative)
- Every 6 hours (minimal)
- Every 12 hours (minimal)
- Every 24 hours (daily maintenance)

**Log Location:** `/var/log/icmptunnel-cron-{server|client}.log`

## Infinite Restart Prevention

### Protection Mechanisms

Both health check and scheduled restart use a **unified restart protection system** with these safeguards:

#### 1. Cooldown Period
- **Minimum 120 seconds** between ANY restarts (from any source)
- Prevents rapid restart loops
- Applies to both health check and cron restarts

#### 2. Restart Limit
- **Maximum 5 restarts per hour** (rolling 1-hour window)
- Prevents runaway restart loops
- Shared counter between health check and cron
- When limit is reached, automatic restarts stop completely

#### 3. File Locking
- Prevents race conditions
- Only one restart can happen at a time
- Protects against health check + cron restart conflicts

#### 4. Retry Logic (Health Check Only)
- Tests service health **3 times** before declaring failure
- 5-second delay between retries
- Filters out transient network issues
- Reduces false positive restarts

#### 5. Grace Period (Health Check Only)
- Service must be running for **30 seconds** before health checks start
- Prevents testing service during startup phase
- Allows service to fully initialize

#### 6. Smart Skipping
- Cron restart checks cooldown/limits before restarting
- Won't force restart if protection rules prevent it
- Logs reason for skipping restart

#### 7. Shared State Tracking
- Both systems use same state file: `/var/tmp/icmptunnel_restart_state_{server|client}.txt`
- Records every restart with timestamp and source (health/cron)
- Prunes entries older than 1 hour
- Atomic file updates prevent corruption

### How Protection Works

**Example Scenario 1: Persistent Failure**
```
10:00:00 - Health check fails, restart triggered (1/5)
10:02:30 - Health check fails again, restart triggered (2/5)
10:05:00 - Cron restart scheduled, but checks cooldown - SKIPPED
10:07:00 - Health check fails, restart triggered (3/5)
10:09:30 - Health check fails, restart triggered (4/5)
10:12:00 - Health check fails, restart triggered (5/5)
10:14:30 - Health check fails, but limit reached - STOPPED
         - Log message: "ACTION REQUIRED: Check service health manually"
```

**Example Scenario 2: Health Check + Cron Conflict**
```
10:00:00 - Cron restart scheduled, executes successfully
10:01:00 - Health check runs, but cooldown active (60s since last restart) - SKIPPED
10:05:00 - Health check runs, cooldown passed, but service is healthy - PASS
```

**Example Scenario 3: Transient Network Issue**
```
10:00:00 - Health check: SOCKS test fails (attempt 1/3)
10:00:05 - Health check: SOCKS test fails (attempt 2/3)
10:00:10 - Health check: SOCKS test succeeds (attempt 3/3)
         - Result: Service is healthy, no restart needed
```

## Usage

### Enable Health Check

Via Menu:
```
Main Menu → ICMP Tunnel → Server/Client → Health check (auto-restart on failure)
```

Or directly:
```bash
sudo ~/paqet_tunnel/scripts/icmptunnel_health_check_scheduler.sh server
sudo ~/paqet_tunnel/scripts/icmptunnel_health_check_scheduler.sh client
```

### Enable Scheduled Restart

Via Menu:
```
Main Menu → ICMP Tunnel → Server/Client → Scheduled restart (cron)
```

Or directly:
```bash
sudo ~/paqet_tunnel/scripts/icmptunnel_cron_restart_scheduler.sh server
sudo ~/paqet_tunnel/scripts/icmptunnel_cron_restart_scheduler.sh client
```

### View Logs

**Health Check Logs:**
```bash
# Last 50 lines
tail -n 50 /var/log/icmptunnel-health-server.log

# Follow in real-time
tail -f /var/log/icmptunnel-health-client.log
```

**Cron Restart Logs:**
```bash
# Last 50 lines
tail -n 50 /var/log/icmptunnel-cron-server.log

# Follow in real-time
tail -f /var/log/icmptunnel-cron-client.log
```

**Restart State File:**
```bash
# View recent restarts
cat /var/tmp/icmptunnel_restart_state_server.txt
```

Format: `timestamp source` (e.g., `1707912345 health` or `1707913456 cron`)

### Disable Features

Both features can be disabled via their respective menus:
- Health Check Menu → Option 4: Disable health check
- Scheduled Restart Menu → Option 9: Remove scheduler

This removes the cron files:
- `/etc/cron.d/icmptunnel-health-icmptunnel-{server|client}`
- `/etc/cron.d/icmptunnel-restart-icmptunnel-{server|client}`

## Log Format

### Health Check Logs

```
[2025-02-14T10:30:00Z] === Health Check Start: icmptunnel-client ===
[2025-02-14T10:30:00Z] Health check: Service is active
[2025-02-14T10:30:00Z] Health check: Grace period passed (uptime: 120s)
[2025-02-14T10:30:00Z] Running client health check (SOCKS proxy test)...
[2025-02-14T10:30:00Z] Health check PASS: SOCKS proxy test successful (port 1010)
[2025-02-14T10:30:00Z] === Health Check PASSED: Service is healthy ===
```

```
[2025-02-14T10:32:00Z] === Health Check Start: icmptunnel-client ===
[2025-02-14T10:32:00Z] Health check: Service is active
[2025-02-14T10:32:00Z] Health check: Grace period passed (uptime: 240s)
[2025-02-14T10:32:00Z] Running client health check (SOCKS proxy test)...
[2025-02-14T10:32:00Z] Health check FAIL: SOCKS proxy test failed (port 1010, url https://httpbin.org/ip)
[2025-02-14T10:32:05Z] Health check: Retry 1/3 after 5s
[2025-02-14T10:32:10Z] Health check FAIL: SOCKS proxy test failed (port 1010, url https://httpbin.org/ip)
[2025-02-14T10:32:15Z] Health check: Retry 2/3 after 5s
[2025-02-14T10:32:20Z] Health check FAIL: SOCKS proxy test failed (port 1010, url https://httpbin.org/ip)
[2025-02-14T10:32:20Z] Health check FAILED: All 3 attempts failed
[2025-02-14T10:32:20Z] === Health Check FAILED: Restart needed ===
[2025-02-14T10:32:20Z] Restart ALLOWED: 2 of 5 this hour, last restart 1707912120 (health)
[2025-02-14T10:32:20Z] Restarting icmptunnel-client.service (source: health)
[2025-02-14T10:32:22Z] [SUCCESS] Service restarted successfully
[2025-02-14T10:32:22Z] === Health Check Complete: Service restarted ===
```

### Cron Restart Logs

```
[2025-02-14T11:00:00Z] === Cron Restart Triggered: icmptunnel-server ===
[2025-02-14T11:00:00Z] Restart SKIPPED: cooldown active (90s ago by health, need 120s, wait 30s more)
[2025-02-14T11:00:00Z] === Cron Restart Complete: Restart skipped (protection active) ===
```

```
[2025-02-14T12:00:00Z] === Cron Restart Triggered: icmptunnel-server ===
[2025-02-14T12:00:00Z] Restart ALLOWED: 3 of 5 this hour, last restart 1707915600 (cron)
[2025-02-14T12:00:00Z] Restarting icmptunnel-server.service (source: cron)
[2025-02-14T12:00:02Z] [SUCCESS] Service restarted successfully
[2025-02-14T12:00:02Z] === Cron Restart Complete: Service restarted ===
```

### Restart Limit Reached

```
[2025-02-14T12:30:00Z] Restart DENIED: limit reached (5/5 per hour)
[2025-02-14T12:30:00Z] ACTION REQUIRED: Check service health manually - automatic restarts stopped
```

## Recommendations

### For Production Servers

**Server (Foreign VPS):**
- Enable health check: every 5-10 minutes
- Optional cron restart: every 4-12 hours (or disable if health check is sufficient)

**Client (Local VPS):**
- Enable health check: every 5 minutes (monitors SOCKS proxy)
- Optional cron restart: every 1-2 hours (if service has memory leaks)

### For Testing/Development

- Health check: every 2 minutes (catch issues quickly)
- Cron restart: disable (rely on health check only)

### General Guidelines

1. **Start with health check only** - it's smart and only restarts when needed
2. **Add cron restart only if:**
   - Service has known memory leaks
   - You want preventive maintenance
   - Health check alone isn't sufficient
3. **Monitor logs regularly** - watch for patterns of repeated restarts
4. **If restart limit is hit** - investigate the root cause, don't just increase the limit
5. **Use conservative intervals** - more restarts ≠ better stability

## Troubleshooting

### Restart Limit Reached Every Hour

**Problem:** Logs show "limit reached (5/5 per hour)" repeatedly

**Solutions:**
1. Check service logs: `journalctl -u icmptunnel-{server|client} -n 100`
2. Verify network connectivity between client and server
3. Check if server firewall is blocking ICMP
4. Verify ICMP tunnel configuration (auth key, encryption key match)
5. Test manually: `curl -x socks5://127.0.0.1:1010 https://httpbin.org/ip`

### Health Check Not Running

**Check cron file exists:**
```bash
ls -la /etc/cron.d/icmptunnel-health-*
```

**Check cron service:**
```bash
systemctl status cron   # Debian/Ubuntu
systemctl status crond  # RHEL/CentOS
```

### Cron Restart Always Skipped

**Check cooldown:**
- Cron might be scheduled too frequently relative to health check
- Review restart state file: `cat /var/tmp/icmptunnel_restart_state_*.txt`
- Increase cron interval or disable health check temporarily

### Service Keeps Failing After Restart

**This indicates a persistent problem:**
1. Check if server is reachable: `ping <server_ip>`
2. Verify ICMP tunnel binary is working: `~/icmptunnel/icmptunnel --version`
3. Test config manually: `~/icmptunnel/icmptunnel` (Ctrl+C to stop)
4. Review server-side logs
5. Check for port conflicts: `ss -lntp | grep <port>`

## Advanced: Manual Testing

### Test Health Check Script Directly

```bash
sudo ~/paqet_tunnel/scripts/icmptunnel_health_check.sh client
sudo ~/paqet_tunnel/scripts/icmptunnel_health_check.sh server
```

### Test Cron Restart Script Directly

```bash
sudo ~/paqet_tunnel/scripts/icmptunnel_cron_restart.sh client
sudo ~/paqet_tunnel/scripts/icmptunnel_cron_restart.sh server
```

### Clear Restart State (Emergency Reset)

**WARNING:** Only do this if you understand the consequences

```bash
# Clear restart history (allows immediate restart)
sudo rm /var/tmp/icmptunnel_restart_state_*.txt
```

## File Locations

### Scripts
- `/root/paqet_tunnel/scripts/icmptunnel_restart_common.sh` - Shared protection logic
- `/root/paqet_tunnel/scripts/icmptunnel_health_check.sh` - Health check implementation
- `/root/paqet_tunnel/scripts/icmptunnel_cron_restart.sh` - Cron restart implementation
- `/root/paqet_tunnel/scripts/icmptunnel_health_check_scheduler.sh` - Health check UI
- `/root/paqet_tunnel/scripts/icmptunnel_cron_restart_scheduler.sh` - Cron restart UI
- `/root/paqet_tunnel/scripts/icmptunnel_health_log_rotate.sh` - Log rotation

### Cron Files
- `/etc/cron.d/icmptunnel-health-icmptunnel-server`
- `/etc/cron.d/icmptunnel-health-icmptunnel-client`
- `/etc/cron.d/icmptunnel-restart-icmptunnel-server`
- `/etc/cron.d/icmptunnel-restart-icmptunnel-client`

### State Files
- `/var/tmp/icmptunnel_restart_state_server.txt` - Server restart history
- `/var/tmp/icmptunnel_restart_state_client.txt` - Client restart history

### Log Files
- `/var/log/icmptunnel-health-server.log` - Server health check logs
- `/var/log/icmptunnel-health-client.log` - Client health check logs
- `/var/log/icmptunnel-cron-server.log` - Server cron restart logs
- `/var/log/icmptunnel-cron-client.log` - Client cron restart logs

## Architecture Notes

### Why Two Features?

**Health Check:**
- Reactive - responds to actual problems
- Smart - only restarts when tests fail
- Lower restart frequency
- Better for most use cases

**Scheduled Restart:**
- Proactive - prevents problems before they occur
- Blind - restarts on schedule regardless of health
- Predictable timing
- Useful for known issues (memory leaks, connection staleness)

### Why Shared Protection?

Without shared protection:
- Health check might restart at 10:00:00
- Cron might restart at 10:00:30
- Both create restart loops independently
- No coordination = instability

With shared protection:
- Both check the same state file
- Both respect the same cooldown
- Both count toward the same limit
- Coordinated behavior = stability
