# BBR Congestion Control Optimization

## Overview

BBR (Bottleneck Bandwidth and Round-trip propagation time) is a modern TCP congestion control algorithm developed by Google. It significantly improves network performance, especially for high-latency and lossy connections.

## Why BBR Benefits Tunnel Performance

### Traditional Congestion Control (CUBIC) Problems

**CUBIC's Assumptions:**
- Packet loss = network congestion
- Aggressive window reduction on packet loss
- Slow recovery after packet loss

**Issues for Tunnels:**
- SSH proxy creates TCP-over-TCP (double encapsulation)
- Causes ACK compression and poor congestion handling
- International connections have high latency
- Censored regions often have packet loss (not from congestion)

### BBR's Advantages

**How BBR Works:**
- Measures actual bandwidth and round-trip time (RTT)
- Doesn't treat all packet loss as congestion signal
- Maintains optimal sending rate based on real network conditions
- More intelligent bandwidth probing

**Benefits for Tunnels:**
1. **Better High-Latency Performance:** 30-200% faster on international connections
2. **Packet Loss Tolerance:** Maintains throughput with 1-2% packet loss
3. **TCP-over-TCP Mitigation:** Handles double encapsulation better
4. **Faster Connection Startup:** Intelligent ramp-up for new connections

## Performance Improvements

### Expected Gains by Connection Type

| Connection Type | Latency (RTT) | Expected Improvement |
|----------------|---------------|---------------------|
| Local/Regional | < 50ms | 10-20% faster |
| Medium Distance | 50-200ms | 30-50% faster |
| International | 200-400ms | 50-100% faster |
| Very High Latency | > 400ms | 100-200% faster |
| Lossy Networks | Any (with packet loss) | 2-5x faster |

### Real-World Use Cases

**Best for:**
- Iran ↔ Europe tunnels (200-300ms RTT)
- China ↔ US tunnels (150-250ms RTT)
- Any international SSH proxy
- Networks with intermittent packet loss
- Mobile/cellular connections
- Satellite connections

**Less Impact:**
- Local VPS to VPS (< 10ms RTT)
- Very high bandwidth, low latency connections
- Already well-optimized networks

## Requirements

### Kernel Version

BBR requires **Linux kernel 4.9 or newer**.

**Check your kernel:**
```bash
uname -r
# Example output: 5.15.0-91-generic
```

**Most modern distributions have this:**
- Ubuntu 18.04+ ✓
- Debian 9+ ✓
- CentOS 8+ ✓
- Rocky Linux 8+ ✓
- AlmaLinux 8+ ✓
- Fedora 26+ ✓

**If kernel is too old:**
- Update your system: `sudo apt update && sudo apt upgrade`
- Consider upgrading to a newer OS version
- Contact your VPS provider for kernel upgrade

### System Impact

**What BBR Changes:**
- System-wide setting (affects ALL TCP connections)
- Kernel module: tcp_bbr
- Sysctl settings for congestion control
- Queue discipline (qdisc): fq (Fair Queue)

**What BBR Does NOT Change:**
- Firewall rules
- Network interfaces
- Application configurations
- Tunnel configurations

## Installation

### Using the Menu

```bash
cd ~/paqet_tunnel
./menu.sh

# Select: 9) BBR Congestion Control
# Then:   2) Enable BBR
```

### Manual Installation

```bash
# Check current status
sudo ~/paqet_tunnel/scripts/check_bbr_status.sh

# Enable BBR
sudo ~/paqet_tunnel/scripts/enable_bbr.sh

# Verify it's enabled
sudo sysctl net.ipv4.tcp_congestion_control
# Should output: net.ipv4.tcp_congestion_control = bbr
```

### What Gets Configured

**1. Kernel Module Load** (`/etc/modules-load.d/bbr.conf`):
```
tcp_bbr
```

**2. Sysctl Configuration** (`/etc/sysctl.d/99-bbr.conf`):
```
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0
```

**Explanation:**
- `default_qdisc = fq`: Fair Queue discipline (required for BBR)
- `tcp_congestion_control = bbr`: Use BBR algorithm
- `tcp_notsent_lowat`: Don't buffer too much unsent data (BBR-friendly)
- `tcp_slow_start_after_idle = 0`: Don't slow down after idle periods

## Usage

### Checking Status

**Via Menu:**
```
Main Menu → 9) BBR Congestion Control → 1) Check BBR status
```

**Manual Check:**
```bash
sudo ~/paqet_tunnel/scripts/check_bbr_status.sh
```

**Quick Check:**
```bash
# Current algorithm
sysctl net.ipv4.tcp_congestion_control

# Available algorithms
sysctl net.ipv4.tcp_available_congestion_control

# Check if BBR module is loaded
lsmod | grep tcp_bbr
```

### Disabling BBR

**Why disable?**
- Troubleshooting network issues
- Reverting to test performance difference
- VPS provider requirement (rare)

**Via Menu:**
```
Main Menu → 9) BBR Congestion Control → 3) Disable BBR
```

**Manual Disable:**
```bash
sudo ~/paqet_tunnel/scripts/disable_bbr.sh
```

**What happens:**
- Reverts to CUBIC (Linux default)
- Removes BBR configuration files
- Changes persist across reboots
- BBR module remains loaded until reboot (harmless)

### Re-enabling

Simply run enable script again:
```bash
sudo ~/paqet_tunnel/scripts/enable_bbr.sh
```

## Testing Performance

### Before and After Comparison

**1. Test BEFORE enabling BBR:**
```bash
# From client, test download speed through tunnel
curl -o /dev/null http://speedtest.tele2.net/100MB.zip

# Note the speed and time
```

**2. Enable BBR:**
```bash
sudo ~/paqet_tunnel/scripts/enable_bbr.sh
```

**3. Test AFTER enabling BBR:**
```bash
# Same test
curl -o /dev/null http://speedtest.tele2.net/100MB.zip

# Compare speed improvement
```

### Monitoring BBR in Action

**Check congestion control per connection:**
```bash
ss -info | grep -A 1 "bbr"
```

**Example output:**
```
    cubic wscale:7,7 rto:204 rtt:3.125/1.562 ato:40 mss:1448 pmtu:1500 rcvmss:1448 advmss:1448 cwnd:10 bytes_sent:1234 bytes_acked:1234 segs_out:10 segs_in:8 send 37.0Mbps lastsnd:12 lastrcv:12 lastack:12 pacing_rate 73.9Mbps bbr:(bw:37.0Mbps,mrtt:3.125,pacing_gain:2.88672,cwnd_gain:2.88672)
```

**Key BBR metrics:**
- `bw`: Measured bandwidth
- `mrtt`: Minimum RTT
- `pacing_rate`: Current sending rate
- `cwnd`: Congestion window

## Integration with Paqet Tunnel

### Tunnel Types That Benefit

**All tunnel types benefit from BBR:**
1. **Paqet (SOCKS5/WireGuard)** - Improved SOCKS proxy throughput
2. **WaterWall (TCP)** - Better performance for TCP forwarding
3. **ICMP Tunnel** - Improved SOCKS5 over ICMP
4. **SSH Proxy** - Significant improvement (TCP-over-TCP scenario)

### When to Enable BBR

**Enable BBR:**
- **Server VPS:** Always enable (improves outbound performance)
- **Client VPS:** Always enable (improves tunnel performance)
- **Both ends:** Best performance when both server and client use BBR

**Order of operations:**
```
1. Set up VPS (server or client)
2. Enable BBR (before or after tunnel setup - doesn't matter)
3. Configure tunnel (Paqet/WaterWall/ICMP/SSH)
4. Enable firewall
5. Test performance
```

### Compatibility

**Works with all tunnel features:**
- ✓ WARP integration
- ✓ DNS policy routing
- ✓ SSH proxy users
- ✓ Firewall (UFW)
- ✓ All tunnel backends

**No conflicts with:**
- iptables rules
- systemd services
- cron jobs
- health checks

## Troubleshooting

### BBR Not Available

**Error:** "BBR module not available"

**Solutions:**
1. Check kernel version: `uname -r` (need 4.9+)
2. Update system: `sudo apt update && sudo apt upgrade`
3. Check if module exists: `modinfo tcp_bbr`
4. If module missing, kernel may not have BBR compiled (rare on modern distros)

### BBR Not Persistent

**Issue:** BBR active now but resets on reboot

**Fix:**
```bash
# Check if config files exist
ls -l /etc/sysctl.d/99-bbr.conf
ls -l /etc/modules-load.d/bbr.conf

# If missing, re-run enable script
sudo ~/paqet_tunnel/scripts/enable_bbr.sh
```

### Performance Not Improved

**Possible reasons:**

1. **Low latency connection:** BBR has minimal impact on < 20ms RTT
   - Check RTT: `ping your-server-ip`

2. **Bandwidth bottleneck elsewhere:** BBR can't exceed physical limits
   - Test raw bandwidth without tunnel

3. **BBR only on one end:** Enable on both server and client
   - Check both: `sysctl net.ipv4.tcp_congestion_control`

4. **Network already well-optimized:** Some VPS providers optimize networks
   - Still worth enabling, but gains may be smaller

5. **Existing connections:** BBR applies to NEW connections only
   - Restart tunnel service after enabling BBR

### Reverting Changes

**If BBR causes issues (extremely rare):**

```bash
# Disable BBR completely
sudo ~/paqet_tunnel/scripts/disable_bbr.sh

# Verify CUBIC is active
sysctl net.ipv4.tcp_congestion_control
# Should show: cubic

# Reboot to fully unload BBR module
sudo reboot
```

## Technical Details

### BBR vs CUBIC Comparison

| Feature | CUBIC | BBR |
|---------|-------|-----|
| **Loss Detection** | Packet loss = congestion | Measures actual bandwidth |
| **Window Growth** | Cubic function | Model-based probing |
| **RTT Sensitivity** | Not considered | Core metric |
| **Packet Loss Handling** | Aggressive reduction | Distinguishes loss types |
| **Startup** | Slow start | Faster ramp-up |
| **Best For** | Low-latency, low-loss | High-latency, variable conditions |

### How BBR Avoids Bufferbloat

**Bufferbloat Problem:**
- Traditional algorithms fill network buffers
- Causes high latency spikes
- Degrades real-time performance

**BBR Solution:**
- Maintains optimal in-flight data (BDP - Bandwidth Delay Product)
- Doesn't overfill buffers
- Lower latency variance

### BBR Versions

**BBR v1 (Current):**
- Available since Linux kernel 4.9
- Stable and widely tested
- Default in our scripts

**BBR v2 (Future):**
- Available in Linux kernel 5.18+
- Further improvements for fairness
- Not yet default (requires manual config)

**BBR v3 (Development):**
- Currently in testing
- Not recommended for production

## Security Considerations

### Is BBR Safe?

**Yes, BBR is very safe:**
- Used by Google, Cloudflare, major CDNs
- Millions of servers run BBR in production
- No known security vulnerabilities related to BBR
- Actively maintained by Google and Linux kernel developers

### Firewall Interaction

**BBR doesn't affect firewall:**
- Operates at TCP layer (Layer 4)
- Firewall operates at packet filtering layer
- No conflicts with UFW/iptables rules
- SSH access remains protected

### DDoS Mitigation

**BBR can help with some DDoS scenarios:**
- Better performance under load
- Faster recovery from attack traffic
- But NOT a DDoS protection solution (use proper DDoS protection)

## Advanced Configuration

### Custom BBR Settings

For advanced users, you can tune BBR parameters in `/etc/sysctl.d/99-bbr.conf`:

```bash
# Our defaults (optimized for tunnels)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0

# Optional advanced tuning (not included by default)
# net.ipv4.tcp_rmem = 4096 87380 67108864
# net.ipv4.tcp_wmem = 4096 65536 67108864
# net.core.rmem_max = 67108864
# net.core.wmem_max = 67108864
```

**After changes:**
```bash
sudo sysctl -p /etc/sysctl.d/99-bbr.conf
```

### Per-Application BBR

BBR is system-wide by default, but you can set per-connection:

```bash
# Example: Force CUBIC for a specific application
# (Advanced - not commonly needed)
```

## References

### Official Resources

- **BBR Paper:** https://queue.acm.org/detail.cfm?id=3022184
- **Linux Kernel BBR:** https://github.com/google/bbr
- **BBR v2 Updates:** https://www.ietf.org/archive/id/draft-cardwell-iccrg-bbr-congestion-control-02.html

### Community Resources

- **ArchWiki BBR:** https://wiki.archlinux.org/title/BBR
- **Cloudflare BBR Blog:** https://blog.cloudflare.com/http-2-prioritization-with-nginx/

## FAQ

### Q: Will BBR improve my download speeds?

**A:** Yes, if your connection has:
- High latency (> 50ms RTT)
- Packet loss (even 1-2%)
- Variable bandwidth

Expect 30-200% improvement for international tunnels.

### Q: Do I need BBR on both server and client?

**A:** BBR on server is most important (handles outbound traffic). BBR on client helps too, but server-side is priority.

### Q: Can BBR cause network issues?

**A:** Extremely rare. BBR has been production-tested for years. If you see issues, easily revert with disable script.

### Q: Does BBR work with IPv6?

**A:** Yes, BBR works with both IPv4 and IPv6.

### Q: Can I use BBR with VPN?

**A:** Yes, BBR improves VPN performance (WireGuard, OpenVPN, etc.)

### Q: Will my VPS provider allow BBR?

**A:** Almost all providers allow it. BBR is a standard kernel feature, not a hack.

### Q: How do I know if BBR is working?

**A:** Check with: `sysctl net.ipv4.tcp_congestion_control` - should show "bbr"
Also check active connections: `ss -info | grep bbr`

## Summary

**BBR is a high-impact, low-risk optimization for tunnel performance.**

**Quick Start:**
1. Check status: `sudo ~/paqet_tunnel/scripts/check_bbr_status.sh`
2. Enable BBR: `sudo ~/paqet_tunnel/scripts/enable_bbr.sh`
3. Verify: `sysctl net.ipv4.tcp_congestion_control`
4. Test your tunnel performance

**Expected Results:**
- 30-50% faster for international tunnels
- Better performance on lossy networks
- Smoother throughput, less latency variance
- Immediate effect on new connections

**Recommendation:** Enable BBR on all tunnel servers (both server and client VPS) for best performance.
