# Health Check and Scheduled Restart Guide

## Overview

This document explains the health check and scheduled restart features available for all three tunnel systems: Paqet, ICMP Tunnel, and WaterWall.

Both features provide automated service recovery with comprehensive protection against infinite restart loops.

---

## Table of Contents

1. [Features Overview](#features-overview)
2. [Protection Mechanisms](#protection-mechanisms)
3. [System-Specific Details](#system-specific-details)
4. [Usage Instructions](#usage-instructions)
5. [Log Locations](#log-locations)
6. [Troubleshooting](#troubleshooting)
7. [Technical Implementation](#technical-implementation)

---

## Features Overview

### Health Check (Recommended)

Automatically monitors service health and restarts only when problems are detected.

**How It Works:**
- Runs periodically (every 2, 5, or 10 minutes)
- Tests service health (different tests for server vs client)
- Retries test 3 times before declaring failure
- Restarts service only if tests fail
- Respects cooldown and restart limits

**When to Use:**
- Production environments (recommended for all deployments)
- Automatic recovery from service failures
- Monitoring tunnel connectivity

### Scheduled Restart (Cron-based)

Periodic service restarts on a fixed schedule, regardless of health status.

**How It Works:**
- Runs on user-defined schedule (10 minutes to 24 hours)
- Checks if restart is allowed (cooldown, limits)
- Restarts service on schedule
- Skips restart if protection rules prevent it

**When to Use:**
- Services with known memory leaks
- Preventive maintenance (session refresh)
- Complement to health check (not replacement)

---

## Protection Mechanisms

Both features share the same protection system to prevent infinite restart loops.

### 1. Cooldown Period

**120 seconds minimum between ANY restarts (from any source)**

- Prevents rapid restart loops
- Applies to both health check and cron restarts
- If service was restarted 60 seconds ago, next restart must wait 60 more seconds

**Example:**
```
10:00:00 - Health check restarts service
10:01:00 - Cron restart scheduled, but cooldown active (wait 60s more) - SKIPPED
10:02:30 - Next restart allowed (120s elapsed)
```

### 2. Restart Limit

**Maximum 5 restarts per hour (rolling 1-hour window)**

- Shared counter between health check and cron restart
- Prevents runaway restart loops
- When limit is reached, automatic restarts stop completely
- Must wait for 1-hour window to expire

**Example:**
```
10:00:00 - Restart 1/5
10:05:00 - Restart 2/5
10:10:00 - Restart 3/5
10:15:00 - Restart 4/5
10:20:00 - Restart 5/5
10:25:00 - Restart attempt DENIED (limit reached)
11:00:01 - First restart expires from window, now 4/5 (restart allowed again)
```

### 3. File Locking

**Prevents race conditions when both systems try to restart simultaneously**

- Uses flock on file descriptor 200
- 10-second timeout
- Only one restart can happen at a time
- If lock cannot be acquired, restart is skipped

### 4. Retry Logic (Health Check Only)

**Tests service health 3 times before declaring failure**

- 5-second delay between retries
- Filters out transient network issues
- Reduces false positive restarts

**Example:**
```
10:00:00 - Health test fails (attempt 1/3)
10:00:05 - Health test fails (attempt 2/3)
10:00:10 - Health test succeeds (attempt 3/3)
Result: Service is healthy, no restart needed
```

### 5. Grace Period (Health Check Only)

**Waits 30 seconds after service start before testing**

- Prevents testing during service initialization
- Allows service to fully start before health checks
- Avoids premature failure detection

### 6. Shared State Tracking

**Both health check and cron use the same state file**

- Location: `/var/tmp/{system}_restart_state_{role}.txt`
- Format: Each line = `timestamp source` (e.g., `1739515200 health`)
- Automatically prunes entries older than 1 hour
- Atomic file updates prevent corruption

---

## System-Specific Details

### Paqet Tunnel

**Service Names:**
- Server: `paqet-server`
- Client: `paqet-client`

**Health Check Tests:**
- **Client:** SOCKS5 proxy test with curl to httpbin.org
- **Server:** journalctl log scanning for connection errors

**Files:**
- State: `/var/tmp/paqet_restart_state_{server|client}.txt`
- Health Logs: `/var/log/paqet-health-{server|client}.log`
- Cron Logs: `/var/log/paqet-cron-{server|client}.log`
- Cron Files: `/etc/cron.d/paqet-health-paqet-{server|client}`
- Cron Files: `/etc/cron.d/paqet-restart-paqet-{server|client}`

**Menu Options:**
- Server: Options 7 (Cron), 10 (Health Check)
- Client: Options 7 (Cron), 10 (Health Check)

### ICMP Tunnel

**Service Names:**
- Server: `icmptunnel-server`
- Client: `icmptunnel-client`

**Health Check Tests:**
- **Client:** SOCKS5 proxy test with curl to httpbin.org
- **Server:** journalctl log scanning for ICMP errors

**Files:**
- State: `/var/tmp/icmptunnel_restart_state_{server|client}.txt`
- Health Logs: `/var/log/icmptunnel-health-{server|client}.log`
- Cron Logs: `/var/log/icmptunnel-cron-{server|client}.log`
- Cron Files: `/etc/cron.d/icmptunnel-health-icmptunnel-{server|client}`
- Cron Files: `/etc/cron.d/icmptunnel-restart-icmptunnel-{server|client}`

**Menu Options:**
- Server: Options 7 (Cron), 8 (Health Check)
- Client: Options 6 (Cron), 7 (Health Check)

### WaterWall

**Service Names:**
- Server: `waterwall-direct-server`
- Client: `waterwall-direct-client`

**Health Check Tests:**
- **Client:** TCP listener port check via ss/netstat
- **Server:** journalctl log scanning for errors

**Files:**
- State: `/var/tmp/waterwall_restart_state_{server|client}.txt`
- Health Logs: `/var/log/waterwall-health-{server|client}.log`
- Cron Logs: `/var/log/waterwall-cron-{server|client}.log`
- Cron Files: `/etc/cron.d/waterwall-health-waterwall-direct-{server|client}`
- Cron Files: `/etc/cron.d/waterwall-restart-waterwall-direct-{server|client}`

**Menu Options:**
- Server: Options 7 (Cron), 8 (Health Check)
- Client: Options 7 (Cron), 8 (Health Check)

---

## Usage Instructions

### Enable Health Check

**Via Menu:**
```
Main Menu → [Tunnel System] → Server/Client → Health check option
```

**Available Intervals:**
- Every 2 minutes (frequent monitoring)
- Every 5 minutes (recommended - balanced)
- Every 10 minutes (conservative)

**Example:**
```bash
# For Paqet server
sudo ~/paqet_tunnel/scripts/health_check_scheduler.sh server
# Select option 2 (every 5 minutes)

# For ICMP Tunnel client
# Via menu: Main Menu → ICMP Tunnel → Client → Option 7
```

### Enable Scheduled Restart

**Via Menu:**
```
Main Menu → [Tunnel System] → Server/Client → Scheduled restart option
```

**Available Intervals:**
- Every 10 minutes (testing only - not recommended)
- Every 30 minutes (frequent - warning shown)
- Every 1 hour (balanced - recommended)
- Every 2 hours (conservative)
- Every 4 hours (conservative)
- Every 6 hours (minimal)
- Every 12 hours (minimal)
- Every 24 hours (daily maintenance)

**Example:**
```bash
# For Paqet server
sudo ~/paqet_tunnel/scripts/cron_restart.sh server
# Select option 2 (every 1 hour)

# For WaterWall client
# Via menu: Main Menu → WaterWall → Client → Option 7
```

### Disable Features

**Via Menu:**
- Health Check Menu → Disable option
- Scheduled Restart Menu → Remove scheduler option

**Manual Removal:**
```bash
# Remove health check
sudo rm /etc/cron.d/paqet-health-paqet-server

# Remove cron restart
sudo rm /etc/cron.d/paqet-restart-paqet-server

# Clear restart history (optional - allows immediate restart)
sudo rm /var/tmp/paqet_restart_state_server.txt
```

### View Status in Menus

All menus now show current configuration inline:

```
7) Scheduled restart (cron) [Every 1 hour]          (cyan - enabled)
8) Health check (auto-restart) [Not configured]     (dim - disabled)
```

---

## Log Locations

### View Logs

**Health Check Logs:**
```bash
# Paqet
tail -f /var/log/paqet-health-server.log
tail -f /var/log/paqet-health-client.log

# ICMP Tunnel
tail -f /var/log/icmptunnel-health-server.log
tail -f /var/log/icmptunnel-health-client.log

# WaterWall
tail -f /var/log/waterwall-health-server.log
tail -f /var/log/waterwall-health-client.log
```

**Cron Restart Logs:**
```bash
# Paqet
tail -f /var/log/paqet-cron-server.log
tail -f /var/log/paqet-cron-client.log

# ICMP Tunnel
tail -f /var/log/icmptunnel-cron-server.log
tail -f /var/log/icmptunnel-cron-client.log

# WaterWall
tail -f /var/log/waterwall-cron-server.log
tail -f /var/log/waterwall-cron-client.log
```

**Restart State Files:**
```bash
# View recent restarts
cat /var/tmp/paqet_restart_state_server.txt
cat /var/tmp/icmptunnel_restart_state_client.txt
cat /var/tmp/waterwall_restart_state_server.txt
```

### Log Format

**Health Check Logs:**
```
[2025-02-14T10:30:00Z] === Health Check Start: paqet-client ===
[2025-02-14T10:30:00Z] Health check: Service is active
[2025-02-14T10:30:00Z] Health check: Grace period passed (uptime: 120s)
[2025-02-14T10:30:00Z] Running client health check (SOCKS proxy test)...
[2025-02-14T10:30:00Z] Health check PASS: SOCKS proxy test successful (port 1080)
[2025-02-14T10:30:00Z] === Health Check PASSED: Service is healthy ===
```

**Cron Restart Logs:**
```
[2025-02-14T11:00:00Z] === Cron Restart Triggered: paqet-server ===
[2025-02-14T11:00:00Z] Restart SKIPPED: cooldown active (90s ago by health, need 120s, wait 30s more)
[2025-02-14T11:00:00Z] === Cron Restart Complete: Restart skipped (protection active) ===
```

**Restart Limit Reached:**
```
[2025-02-14T12:30:00Z] Restart DENIED: limit reached (5/5 per hour)
[2025-02-14T12:30:00Z] ACTION REQUIRED: Check service health manually - automatic restarts stopped
```

---

## Troubleshooting

### Restart Limit Reached Every Hour

**Symptoms:**
- Logs show "limit reached (5/5 per hour)" repeatedly
- Service keeps failing

**Diagnosis:**
```bash
# Check service logs
journalctl -u paqet-server -n 100

# Check restart history
cat /var/tmp/paqet_restart_state_server.txt

# Test service manually
curl -x socks5://127.0.0.1:1080 https://httpbin.org/ip
```

**Solutions:**
1. Fix underlying issue (network, configuration, server down)
2. Verify server is reachable: `ping <server_ip>`
3. Check firewall rules
4. Verify configuration files match between server and client
5. Review service logs for actual errors

### Health Check Not Running

**Symptoms:**
- No entries in health check logs
- Service failures not detected

**Diagnosis:**
```bash
# Check cron file exists
ls -la /etc/cron.d/paqet-health-*

# Check cron service is running
systemctl status cron    # Debian/Ubuntu
systemctl status crond   # RHEL/CentOS

# Check script is executable
ls -la /root/paqet_tunnel/scripts/health_check.sh
```

**Solutions:**
```bash
# Restart cron service
sudo systemctl restart cron

# Manually run health check script
sudo /root/paqet_tunnel/scripts/health_check.sh server

# Re-enable health check via menu
./menu.sh
```

### Cron Restart Always Skipped

**Symptoms:**
- Cron logs show "Restart skipped (protection active)" every time
- Scheduled restarts never happen

**Diagnosis:**
```bash
# Check restart history
cat /var/tmp/paqet_restart_state_server.txt

# Check if health check is too frequent
cat /etc/cron.d/paqet-health-paqet-server
cat /etc/cron.d/paqet-restart-paqet-server
```

**Solutions:**
1. If health check runs every 2 minutes and cron every 10 minutes, cooldown may prevent cron restart
2. Increase cron restart interval
3. Reduce health check frequency
4. Consider disabling one feature if the other is sufficient

### Service Keeps Failing After Restart

**Symptoms:**
- Service restarts but immediately fails again
- Health checks always fail
- Restart limit reached quickly

**This indicates a persistent problem, not a transient issue.**

**Diagnosis:**
```bash
# Check if server is reachable
ping <server_ip>

# Test tunnel manually
# For Paqet/ICMP: curl -x socks5://127.0.0.1:1080 https://httpbin.org/ip
# For WaterWall: Check if listener port is active

# Check service logs for actual errors
journalctl -u paqet-client -n 100

# Verify configuration
cat ~/paqet/client.yaml
```

**Solutions:**
1. Fix underlying issue before relying on automated restarts
2. Verify server-side service is running
3. Check firewall rules on both server and client
4. Verify authentication keys match
5. Test configuration manually before enabling automation

### False Positives (Service Healthy but Restarts Anyway)

**Symptoms:**
- Service works fine but gets restarted frequently
- Health check logs show intermittent failures

**Diagnosis:**
- Review health check logs for pattern
- Check if external test URL (httpbin.org) is sometimes unreachable
- Verify network stability

**Solutions:**
1. Retry logic should filter most false positives (3 attempts)
2. Increase health check interval (from 2 to 5 or 10 minutes)
3. Consider using cron restart only (blind periodic restart)

---

## Technical Implementation

### State File Format

**Location:** `/var/tmp/{system}_restart_state_{role}.txt`

**Format:**
```
1739515200 health
1739515350 health
1739515680 cron
1739516020 health
1739516380 health
```

Each line: `timestamp source`
- timestamp: Unix epoch seconds
- source: "health" or "cron"

**Pruning:** Entries older than 1 hour are automatically removed before each restart decision.

### Restart Decision Algorithm

```
1. Load state file
2. Prune entries older than 1 hour
3. Count remaining entries
4. IF count >= 5:
     Log "Restart DENIED: limit reached"
     Return FALSE
5. Get last restart timestamp and source
6. Calculate elapsed time = now - last_restart
7. IF elapsed < 120 seconds:
     Log "Restart SKIPPED: cooldown active"
     Return FALSE
8. Log "Restart ALLOWED"
9. Acquire file lock (wait up to 10 seconds)
10. IF lock acquired:
      Perform restart
      Record restart (append timestamp + source to state file)
      Release lock
      Return TRUE
    ELSE:
      Log "Could not acquire lock"
      Return FALSE
```

### File Locking Implementation

```bash
# In restart_common.sh
acquire_restart_lock() {
  local lock_file="$1"
  exec 200>"${lock_file}"
  flock -w 10 200 || return 1
  return 0
}

release_restart_lock() {
  flock -u 200 2>/dev/null || true
}
```

### Cron File Format

**Health Check:**
```
# Paqet Health Check for paqet-server
# Checks service health and restarts if needed (with protection against infinite loops)
*/5 * * * * root /root/paqet_tunnel/scripts/health_check.sh server >> /var/log/paqet-health-server.log 2>&1
```

**Cron Restart:**
```
# Paqet Scheduled Restart for paqet-server
# Smart restart with protection against infinite loops
0 * * * * root /root/paqet_tunnel/scripts/paqet_cron_restart.sh server >> /var/log/paqet-cron-server.log 2>&1
```

---

## Recommended Configurations

### Production Server

**Server (Foreign VPS):**
- Health Check: Every 5-10 minutes
- Cron Restart: Every 4-12 hours (or disable if health check is sufficient)

**Client (Local VPS):**
- Health Check: Every 5 minutes (monitors SOCKS/TCP proxy)
- Cron Restart: Every 1-2 hours (if service has memory leaks)

### Development/Testing

**Both Server and Client:**
- Health Check: Every 2 minutes (catch issues quickly)
- Cron Restart: Disable (rely on health check only)

### General Guidelines

1. **Start with health check only** - it's smart and only restarts when needed
2. **Add cron restart only if:**
   - Service has known memory leaks
   - You want preventive maintenance
   - Health check alone isn't sufficient
3. **Monitor logs regularly** - watch for patterns of repeated restarts
4. **If restart limit is hit frequently** - investigate root cause, don't just increase limit
5. **Use conservative intervals** - more restarts does not mean better stability

---

## Migration from Old System

### Paqet Migration

**Old System:**
- State file: `/var/tmp/paqet_health_{role}.state`
- No cooldown period
- No coordination between health check and cron restart
- No retry logic

**New System:**
- State file: `/var/tmp/paqet_restart_state_{role}.txt`
- 120-second cooldown
- Shared state between health check and cron
- 3 retry attempts

**Migration Process:**
- Old state file is NOT migrated (intentional - clean slate)
- New system starts with empty state file
- Existing cron jobs continue to work
- Re-enabling features creates new cron files with updated paths

**No service downtime during migration.**

---

## Quick Reference

### Enable Features

```bash
# Health Check
sudo ~/paqet_tunnel/scripts/health_check_scheduler.sh {server|client}
sudo ~/paqet_tunnel/scripts/icmptunnel_health_check_scheduler.sh {server|client}
sudo ~/paqet_tunnel/scripts/waterwall_health_check_scheduler.sh {server|client}

# Cron Restart
sudo ~/paqet_tunnel/scripts/cron_restart.sh {server|client}
sudo ~/paqet_tunnel/scripts/icmptunnel_cron_restart_scheduler.sh {server|client}
sudo ~/paqet_tunnel/scripts/waterwall_cron_restart_scheduler.sh {server|client}
```

### View Status

```bash
# Check if features are enabled
ls -la /etc/cron.d/*health* /etc/cron.d/*restart*

# View recent restarts
cat /var/tmp/paqet_restart_state_server.txt

# View logs
tail -f /var/log/paqet-health-server.log
tail -f /var/log/paqet-cron-server.log
```

### Emergency Reset

```bash
# Clear restart history (allows immediate restart)
sudo rm /var/tmp/paqet_restart_state_server.txt

# Disable features
sudo rm /etc/cron.d/paqet-health-paqet-server
sudo rm /etc/cron.d/paqet-restart-paqet-server
```

### Test Manually

```bash
# Run health check once
sudo /root/paqet_tunnel/scripts/health_check.sh server

# Run cron restart once
sudo /root/paqet_tunnel/scripts/paqet_cron_restart.sh server
```

---

## Summary

**Key Features:**
- Automated service recovery with health check
- Periodic service refresh with cron restart
- Comprehensive protection against infinite restart loops
- Coordinated operation between both features
- Detailed logging for debugging
- Available for all three tunnel systems

**Protection Mechanisms:**
- 120-second cooldown between restarts
- Maximum 5 restarts per hour
- File locking prevents race conditions
- 3 retry attempts reduce false positives
- 30-second grace period after service start
- Shared state tracking for coordination

**All three tunnel systems (Paqet, ICMP Tunnel, WaterWall) now have identical, enterprise-grade restart protection.**
