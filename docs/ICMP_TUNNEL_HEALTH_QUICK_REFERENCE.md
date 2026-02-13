# ICMP Tunnel Health & Restart - Quick Reference

## Enable Features

**Via Menu:**
```
Main Menu → ICMP Tunnel → Server/Client
  → Option 7: Scheduled restart (cron)
  → Option 8: Health check (auto-restart on failure)
```

**Via Command:**
```bash
# Health check
sudo ~/paqet_tunnel/scripts/icmptunnel_health_check_scheduler.sh {server|client}

# Cron restart
sudo ~/paqet_tunnel/scripts/icmptunnel_cron_restart_scheduler.sh {server|client}
```

## Recommended Settings

| Role | Health Check | Cron Restart |
|------|-------------|--------------|
| Server | Every 5 minutes | Every 4-12 hours (optional) |
| Client | Every 5 minutes | Every 1-2 hours (optional) |

## View Logs

```bash
# Health check logs
tail -f /var/log/icmptunnel-health-server.log
tail -f /var/log/icmptunnel-health-client.log

# Cron restart logs
tail -f /var/log/icmptunnel-cron-server.log
tail -f /var/log/icmptunnel-cron-client.log

# Restart history
cat /var/tmp/icmptunnel_restart_state_server.txt
cat /var/tmp/icmptunnel_restart_state_client.txt
```

## Protection Mechanisms

| Protection | Value | Purpose |
|------------|-------|---------|
| Cooldown | 120 seconds | Minimum time between ANY restarts |
| Restart Limit | 5 per hour | Maximum restarts in rolling 1-hour window |
| Retry Attempts | 3 times | Health check retries before declaring failure |
| Grace Period | 30 seconds | Wait time after service start before testing |
| File Lock | Yes | Prevents race conditions |

## Disable Features

**Health Check:**
- Menu → Health check → Option 4: Disable

**Cron Restart:**
- Menu → Scheduled restart → Option 9: Remove scheduler

## Troubleshooting

**Restart limit reached?**
```bash
# Check logs for patterns
journalctl -u icmptunnel-{server|client} -n 100

# Test SOCKS proxy manually (client only)
curl -x socks5://127.0.0.1:1010 https://httpbin.org/ip

# Clear restart history (emergency only)
sudo rm /var/tmp/icmptunnel_restart_state_*.txt
```

**Health check not running?**
```bash
# Check cron file exists
ls -la /etc/cron.d/icmptunnel-health-*

# Check cron service
systemctl status cron
```

**Service keeps failing?**
```bash
# Check connectivity
ping <server_ip>

# Test config manually
~/icmptunnel/icmptunnel

# Check for port conflicts
ss -lntp | grep <port>
```

## Log Messages Explained

| Message | Meaning | Action |
|---------|---------|--------|
| `Restart ALLOWED` | Restart is safe | Normal operation |
| `Restart SKIPPED: cooldown active` | Too soon after last restart | Wait for cooldown to expire |
| `Restart DENIED: limit reached` | 5 restarts in last hour | Investigate root cause |
| `Health check PASSED` | Service is healthy | No action needed |
| `Health check FAILED` | Service has issues | Restart will be attempted |
| `[SUCCESS] Service restarted` | Restart completed | Monitor for stability |

## Key Files

**Configuration:**
- `/etc/cron.d/icmptunnel-health-icmptunnel-{server|client}`
- `/etc/cron.d/icmptunnel-restart-icmptunnel-{server|client}`

**State:**
- `/var/tmp/icmptunnel_restart_state_{server|client}.txt`

**Logs:**
- `/var/log/icmptunnel-health-{server|client}.log`
- `/var/log/icmptunnel-cron-{server|client}.log`
