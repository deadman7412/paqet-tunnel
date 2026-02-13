# ICMP Tunnel Guide

This guide covers installation, setup, and management of ICMP Tunnel (ICMPTunnel) in the Paqet Tunnel Scripts system.

## Overview

ICMP Tunnel creates a covert network tunnel using ICMP (ping) packets, allowing you to bypass restrictive firewalls that only allow ICMP traffic. The client exposes a SOCKS5 proxy that routes traffic through the ICMP tunnel to the server.

**Credit:** ICMP Tunnel is created and maintained by [Qteam-official/ICMPTunnel](https://github.com/Qteam-official/ICMPTunnel). This project only provides helper scripts for installation and management.

**Use Cases:**
- Networks that block all TCP/UDP but allow ICMP (ping)
- Educational and security research purposes
- Network penetration testing with proper authorization

**Important:** ICMP tunneling may be detected by network monitoring systems. Use only in authorized environments.

## Architecture

### Server (Foreign VPS)
- Listens for ICMP echo requests containing tunneled data
- Forwards decrypted traffic to the internet or local services
- API port for management (default: 8080)

### Client (Local VPS/Machine)
- Sends traffic as ICMP echo requests to server
- Exposes SOCKS5 proxy (default port: 1010)
- Applications connect to SOCKS5 proxy for internet access through tunnel

### Configuration Format

ICMP Tunnel uses JSON configuration:

**Server config:**
```json
{
  "type": "server",
  "timeout": 20,
  "dns": "8.8.8.8",
  "key": 12345678,
  "api_port": "8080",
  "encrypt_data": true,
  "encrypt_data_key": "randomly_generated_key"
}
```

**Client config:**
```json
{
  "type": "client",
  "listen_port_socks": "1010",
  "server": "SERVER_IP",
  "timeout": 20,
  "dns": "8.8.8.8",
  "key": 12345678,
  "encrypt_data": true,
  "encrypt_data_key": "randomly_generated_key"
}
```

## Installation

### 1. Install ICMP Tunnel Binary

**From main menu:**
```
Main Menu → 4) ICMP Tunnel → 1) Install ICMP Tunnel
```

This downloads the appropriate binary for your architecture (amd64, arm64, arm, 386) from GitHub releases and installs to `~/icmptunnel/`.

**Directory structure created:**
```
~/icmptunnel/
├── icmptunnel          # Binary
├── server/
│   └── config.json     # Server config (after setup)
├── client/
│   └── config.json     # Client config (after setup)
└── logs/               # Log files
```

### 2. Update ICMP Tunnel

To update to the latest release:
```
Main Menu → 4) ICMP Tunnel → 2) Update ICMP Tunnel
```

This downloads the latest binary and preserves your configurations.

## Server Setup

### 1. Create Server Configuration

**From menu:**
```
Main Menu → 4) ICMP Tunnel → 3) Server menu → 1) Server setup
```

**Configuration prompts:**
- **API Port** (default: 8080): Management API port
- **Authentication Key**: Numeric key for client authentication
- **Enable Encryption** (y/n): Enable data encryption (recommended)
- **DNS Server** (default: 8.8.8.8): DNS server for name resolution
- **Timeout** (default: 20): Connection timeout in seconds

**Output files:**
- `~/icmptunnel/server/config.json`: Server configuration
- `~/icmptunnel/server_info.txt`: Connection info for client setup

**Example server_info.txt:**
```
server_ip=YOUR_SERVER_IP
auth_key=12345678
encryption_enabled=1
encryption_key=random_generated_key
dns=8.8.8.8
timeout=20
```

### 2. Install systemd Service

**From menu:**
```
Server menu → 2) Install systemd service
```

This creates `/etc/systemd/system/icmptunnel-server.service` and enables it to start on boot.

### 3. Configure Firewall

**From menu:**
```
Main Menu → 8) Firewall (UFW) → 4) ICMP Tunnel firewall → 1) Enable firewall
Select role: server
```

**What it does:**
- Preserves SSH access
- Allows ICMP protocol from client IP (or from anywhere if no client IP specified)
- Adds loopback access for local communication

### 4. Start Server

**From menu:**
```
Server menu → 4) Service control
Select action: start
```

Or use systemctl directly:
```bash
sudo systemctl start icmptunnel-server
```

### 5. Transfer server_info.txt to Client

**Copy to client VPS:**
```bash
scp ~/icmptunnel/server_info.txt root@CLIENT_IP:~/icmptunnel/
```

The client setup script will read this file to configure the connection.

## Client Setup

### 1. Receive server_info.txt

Ensure `~/icmptunnel/server_info.txt` exists on the client VPS (copied from server).

### 2. Create Client Configuration

**From menu:**
```
Main Menu → 4) ICMP Tunnel → 4) Client menu → 1) Client setup
```

**Configuration prompts:**
- **Server IP**: Auto-filled from server_info.txt (can override)
- **SOCKS5 Port** (default: 1010): Local SOCKS5 proxy port
- **Encryption Key**: Auto-filled from server_info.txt

**Output:**
- `~/icmptunnel/client/config.json`: Client configuration

### 3. Install systemd Service

**From menu:**
```
Client menu → 2) Install systemd service
```

This creates `/etc/systemd/system/icmptunnel-client.service`.

### 4. Configure Firewall

**From menu:**
```
Main Menu → 8) Firewall (UFW) → 4) ICMP Tunnel firewall → 1) Enable firewall
Select role: client
```

**What it does:**
- Preserves SSH access
- Allows outbound ICMP to server IP
- Opens SOCKS5 port (default: 1010) for local applications

### 5. Start Client

**From menu:**
```
Client menu → 4) Service control
Select action: start
```

Or use systemctl:
```bash
sudo systemctl start icmptunnel-client
```

## Testing

### Quick Connection Test

**From client menu:**
```
Client menu → 5) Tests → 2) Quick connection test
```

**Test steps:**
1. ICMP reachability to server (ping test)
2. SOCKS5 proxy listening check
3. Service status check
4. HTTP request through SOCKS5 proxy

**Expected output:**
```
[SUCCESS] Server is reachable via ICMP
[SUCCESS] SOCKS5 proxy is listening on port 1010
[SUCCESS] icmptunnel-client service is active
[SUCCESS] SOCKS5 proxy is working - internet egress OK
```

### Comprehensive Diagnostic

**From server or client menu:**
```
Server menu → 6) Tests → 1) Diagnostic report
```

**Report includes:**
- System information (OS, kernel, architecture)
- Binary information (path, size, permissions)
- Configuration files validation
- Network information (public IP)
- Service status (systemd)
- Port listening status
- WARP status (if enabled)
- DNS policy status (if enabled)
- Firewall rules
- Recent service logs

**Share this report with support for troubleshooting.**

### Manual Testing

**Test ICMP connectivity:**
```bash
ping -c 5 SERVER_IP
```

**Test SOCKS5 proxy:**
```bash
curl -x socks5://127.0.0.1:1010 https://api.ipify.org
```

**Check service logs:**
```bash
sudo journalctl -u icmptunnel-client -f
```

## Service Management

### Control Service

**From menu:**
```
Server/Client menu → 4) Service control
```

**Available actions:**
- **start**: Start the service
- **stop**: Stop the service
- **restart**: Restart the service
- **status**: Show service status
- **logs**: View recent logs (last 50 lines)
- **enable**: Enable service to start on boot
- **disable**: Disable service from starting on boot

### View Service Logs

**From menu:**
```
Server/Client menu → 6) Tests → 4) Service logs
```

Or manually:
```bash
# Last 50 lines
sudo journalctl -u icmptunnel-server -n 50

# Follow logs in real-time
sudo journalctl -u icmptunnel-client -f
```

### Show Server Info

**From server menu:**
```
Server menu → 5) Show server info
```

Displays the contents of `~/icmptunnel/server_info.txt` for easy reference.

## Advanced Features

### WARP Routing

Route ICMP Tunnel traffic through Cloudflare WARP for additional IP masking.

**Enable WARP for ICMP Tunnel:**

1. **Install WARP core:**
   ```
   Main Menu → 6) WARP/DNS core → 1) WARP Configuration → 1) Install WARP core
   ```

2. **Apply WARP rule to ICMP Tunnel:**
   ```
   Main Menu → 6) WARP/DNS core → 1) WARP Configuration → 3) Apply WARP rule
   Select proxy type: icmp (or icmptunnel)
   ```

**What it does:**
- Creates `icmptunnel` system user
- Detects iproute2 ipproto support for protocol-level filtering
- **Critical:** Routes only TCP/UDP through WARP, **excludes ICMP** to preserve tunnel functionality
- Sets up uidrange routing to WARP table (51820)
- Adds Linux capabilities (CAP_NET_RAW, CAP_NET_ADMIN)
- Creates systemd drop-in to run service as icmptunnel user
- Provides detailed debug output showing configuration steps

**Important technical details:**
- ICMP Tunnel uses ICMP packets for the tunnel protocol itself
- If ICMP packets are routed through WARP, the tunnel breaks
- The script uses `ipproto tcp` and `ipproto udp` filters to route only encapsulated traffic through WARP
- ICMP echo requests/replies go directly to/from server (not through WARP)
- Requires iproute2 v4.17+ (Ubuntu 18.04+) for ipproto support

**Expected output on modern systems:**
```
[DEBUG] Starting ipproto support detection...
[DEBUG] iproute2 version: ip utility, iproute2-6.1.0
[DEBUG] ipproto support: DETECTED
[INFO] Adding uidrange rule for TCP/UDP only (excluding ICMP)...
[SUCCESS] TCP rule added
[SUCCESS] UDP rule added
[INFO] WARP routing: TCP/UDP only (ICMP excluded to preserve tunnel replies)
```

**On older systems (iproute2 < 4.17):**
```
[WARN] Cannot exclude ICMP from WARP (old iproute2 version)
[WARN] ICMP tunnel + WARP may not work properly on this system
```

**Check WARP status:**
```
Server/Client menu → 6) Tests → 2) WARP status
```

**Verify routing rules:**
```bash
# Should show separate TCP and UDP rules, NO ICMP rule
ip rule show | grep icmptunnel
```

**Expected output:**
```
32765:  from all uidrange 995-995 ipproto tcp lookup 51820
32766:  from all uidrange 995-995 ipproto udp lookup 51820
```

**Disable WARP:**
```
Main Menu → 6) WARP/DNS core → 1) WARP Configuration → 4) Remove WARP rule
Select proxy type: icmp
```

### DNS Policy Routing

Route DNS queries through a local DNS resolver with custom blocklists (ads, malware, etc.).

**Enable DNS policy for ICMP Tunnel:**

1. **Install DNS policy core:**
   ```
   Main Menu → 7) DNS blocklist → 2) DNS Configuration → 1) Install DNS policy core
   Select category: ads (or all/proxy)
   ```

2. **Apply DNS rule to ICMP Tunnel:**
   ```
   Main Menu → 7) DNS blocklist → 2) DNS Configuration → 3) Apply DNS rule
   Select proxy type: icmptunnel
   ```

**What it does:**
- Installs dnsmasq with port 5353 listener
- Configures DNS blocklists (ads, tracking, malware)
- Adds iptables NAT rules to redirect port 53 to 5353
- Routes icmptunnel user's DNS through dnsmasq

**Check DNS status:**
```
Server/Client menu → 6) Tests → 3) DNS status
```

**Update blocklists:**
```
Main Menu → 7) DNS blocklist → 2) DNS Configuration → 5) Update DNS blocklist
```

**Disable DNS policy:**
```
Main Menu → 7) DNS blocklist → 2) DNS Configuration → 4) Remove DNS rule
Select proxy type: icmptunnel
```

## Application Configuration

### Using SOCKS5 Proxy

Configure applications to use the ICMP Tunnel SOCKS5 proxy:

**Proxy settings:**
- Protocol: SOCKS5
- Host: 127.0.0.1 (or client VPS IP if accessing remotely)
- Port: 1010 (or your configured port)
- No authentication required

**curl example:**
```bash
curl -x socks5://127.0.0.1:1010 https://www.google.com
```

**wget example:**
```bash
ALL_PROXY=socks5://127.0.0.1:1010 wget https://example.com
```

**Browser configuration:**
- Firefox: Settings → Network Settings → Manual proxy → SOCKS5: 127.0.0.1:1010
- Chrome/Edge: Use system proxy or extensions like SwitchyOmega

### Proxychains (System-wide)

Route any application through ICMP Tunnel:

**Install proxychains:**
```bash
sudo apt-get update
sudo apt-get install -y proxychains4
```

**Configure:**
```bash
sudo nano /etc/proxychains4.conf
```

Add at the end:
```
[ProxyList]
socks5 127.0.0.1 1010
```

**Usage:**
```bash
proxychains4 curl https://api.ipify.org
proxychains4 ssh user@remote-server
proxychains4 git clone https://github.com/user/repo
```

## Troubleshooting

### Server Issues

**Service won't start:**
```bash
# Check service status
sudo systemctl status icmptunnel-server

# Check logs for errors
sudo journalctl -u icmptunnel-server -n 100

# Verify binary permissions
ls -l ~/icmptunnel/icmptunnel

# Verify config syntax
cat ~/icmptunnel/server/config.json | python3 -m json.tool
```

**ICMP not allowed through firewall:**
```bash
# Check UFW rules
sudo ufw status verbose

# Manually allow ICMP from client
sudo ufw allow from CLIENT_IP proto icmp comment 'icmptunnel'
```

### Client Issues

**Cannot reach server:**
```bash
# Test ICMP connectivity
ping -c 5 SERVER_IP

# Check if server is blocking ICMP
# Server should allow ICMP from your client IP
```

**SOCKS5 proxy not working:**
```bash
# Verify proxy is listening
ss -ltn | grep 1010

# Test proxy
curl -v -x socks5://127.0.0.1:1010 https://www.google.com

# Check client logs
sudo journalctl -u icmptunnel-client -n 50
```

**Authentication failures:**
- Verify auth_key matches between server and client configs
- Check encryption_key matches if encryption is enabled
- Regenerate configs if keys are mismatched

### WARP Issues

**WARP not routing traffic:**
```bash
# Check WARP interface status
ip link show wgcf

# Check routing rules (should show TCP and UDP, NOT ICMP)
ip rule show | grep icmptunnel
# Expected: separate rules for ipproto tcp and ipproto udp

# Verify no ICMP is being routed through WARP
ip rule show | grep -E "uidrange.*icmptunnel" | grep -i icmp
# Expected: no output (ICMP should NOT be in routing rules)

# Check iproute2 version and ipproto support
ip -V
ip rule add help 2>&1 | grep ipproto
# Should show ipproto in help output

# Check WARP status
sudo ~/paqet_tunnel/scripts/icmptunnel_warp_status.sh

# View detailed WARP configuration (with debug output)
sudo ~/paqet_tunnel/scripts/icmptunnel_enable_warp_policy.sh server
```

**Tunnel freezes or times out with WARP enabled:**

This typically means ICMP packets are being routed through WARP instead of direct:

```bash
# 1. Check if ipproto filtering is active
ip rule show | grep icmptunnel
# Should show: ipproto tcp and ipproto udp (NOT all protocols)

# 2. If you see rules without ipproto, remove and re-apply WARP
cd ~/paqet_tunnel
./menu.sh
# WARP Configuration → Remove WARP rule → icmp
# WARP Configuration → Apply WARP rule → icmp

# 3. Verify new rules have ipproto filtering
ip rule show | grep icmptunnel

# 4. Test tunnel
curl -x socks5://127.0.0.1:1010 https://api.ipify.org
# Should return WARP IP (104.28.x.x) without freezing
```

**Old iproute2 version (< 4.17):**

If your system has iproute2 < 4.17, ipproto filtering is not supported and ICMP tunnel + WARP will not work together:

```bash
# Check version
ip -V

# Upgrade iproute2 (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install --only-upgrade iproute2

# Verify ipproto support after upgrade
ip rule add help 2>&1 | grep ipproto
```

If upgrade is not possible:
- Use ICMP tunnel **without** WARP, or
- Use Paqet/WaterWall tunnel with WARP instead

**Restart WARP interface:**
```bash
sudo wg-quick down wgcf
sudo wg-quick up wgcf
sudo systemctl restart icmptunnel-server
```

### DNS Policy Issues

**DNS not being filtered:**
```bash
# Check dnsmasq status
sudo systemctl status dnsmasq

# Check iptables NAT rules
sudo iptables -t nat -L OUTPUT -n -v | grep 5353

# Check DNS status
sudo ~/paqet_tunnel/scripts/icmptunnel_dns_status.sh

# Test DNS resolution
dig @127.0.0.1 -p 5353 google.com
```

### Performance Issues

**Slow tunnel speeds:**
- ICMP tunnels are inherently slower than TCP/UDP tunnels
- Expected throughput: 100-500 KB/s (highly variable)
- Reduce MTU if experiencing packet loss
- Consider using encryption=false for testing (not recommended in production)

**High latency:**
- ICMP packets may be rate-limited by routers
- Check server/client timeout settings (increase if needed)
- Verify server is geographically close to reduce RTT

## Security Considerations

### Encryption

**Always enable encryption** (`encrypt_data: true`) when transmitting sensitive data:
- Prevents MITM attacks
- Obscures tunnel traffic from deep packet inspection
- Authentication key provides basic client verification

**Key management:**
- Use strong, random authentication keys
- Rotate encryption keys periodically
- Never share server_info.txt over insecure channels

### Firewall Best Practices

**Server firewall:**
- Only allow ICMP from known client IPs
- Keep API port (8080) closed to public or use strong authentication
- Monitor for unauthorized ICMP traffic

**Client firewall:**
- Restrict SOCKS5 port to localhost (127.0.0.1) unless remote access is needed
- Only allow outbound ICMP to server IP

### Detection Risks

**ICMP tunneling can be detected by:**
- Deep packet inspection (DPI) systems
- Anomaly detection (unusual ICMP packet sizes)
- Intrusion detection systems (IDS)

**Mitigation:**
- Use encryption to obscure payload
- Keep traffic volume low to avoid triggering anomaly detection
- Only use in authorized environments

## Uninstallation

### Remove ICMP Tunnel

**From menu:**
```
Main Menu → 4) ICMP Tunnel → 5) Uninstall ICMP Tunnel
```

**What it removes:**
- Systemd services (server and client)
- Binary and configuration files
- icmptunnel system user (if created for WARP/DNS)
- Firewall rules
- WARP/DNS policy bindings
- All state files

**Manual cleanup (if needed):**
```bash
# Stop services
sudo systemctl stop icmptunnel-server icmptunnel-client

# Remove services
sudo systemctl disable icmptunnel-server icmptunnel-client
sudo rm -f /etc/systemd/system/icmptunnel-*.service
sudo rm -rf /etc/systemd/system/icmptunnel-*.service.d
sudo systemctl daemon-reload

# Remove files
rm -rf ~/icmptunnel

# Remove user
sudo userdel icmptunnel 2>/dev/null || true

# Remove firewall rules
sudo ufw delete allow proto icmp comment 'icmptunnel'

# Remove state
sudo rm -rf /etc/icmptunnel-policy
```

## Performance Tuning

### Timeout Adjustment

Increase timeout for high-latency connections:
```json
{
  "timeout": 30
}
```

### DNS Selection

Use faster DNS servers:
```json
{
  "dns": "1.1.1.1"  // Cloudflare
}
```

### Encryption Toggle

For testing only, disable encryption:
```json
{
  "encrypt_data": false
}
```

**Warning:** Only disable encryption in trusted, isolated test environments.

## Comparison with Other Tunnels

| Feature | ICMP Tunnel | Paqet | WaterWall |
|---------|-------------|-------|-----------|
| Protocol | ICMP (ping) | WireGuard/SOCKS5 | TCP |
| Speed | Low (100-500 KB/s) | High (10+ MB/s) | High (10+ MB/s) |
| Stealth | High | Medium | Low |
| Firewall Bypass | Excellent | Good | Fair |
| Encryption | Optional | Built-in | Optional |
| Use Case | Restrictive networks | General VPN | Port forwarding |

**When to use ICMP Tunnel:**
- Networks that block all TCP/UDP ports
- Only ICMP (ping) is allowed
- Stealth is more important than speed
- Educational/research purposes

**When to use Paqet:**
- General VPN needs
- Speed is important
- WireGuard support

**When to use WaterWall:**
- Simple TCP port forwarding
- Backend service proxying
- Integration with 3x-ui/v2ray

## Additional Resources

- **ICMP Tunnel GitHub**: https://github.com/Qteam-official/ICMPTunnel
- **Project Issues**: https://github.com/deadman7412/paqet-tunnel/issues
- **ICMP Protocol**: RFC 792
- **Network Testing**: Use diagnostic report for comprehensive troubleshooting

## Support

If you encounter issues:

1. Run diagnostic report: `Server/Client menu → Tests → Diagnostic report`
2. Check logs: `sudo journalctl -u icmptunnel-server -n 100`
3. Review this guide's troubleshooting section
4. Report issues with diagnostic output at: https://github.com/deadman7412/paqet-tunnel/issues
