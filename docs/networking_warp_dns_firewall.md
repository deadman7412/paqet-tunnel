# Networking, WARP, DNS, Firewall

## Repair Networking Stack

Use when tunnel connectivity is inconsistent after port/MTU/WARP/firewall changes.

Run from menu:

- `Paqet Tunnel -> Server configuration -> Repair networking stack`
- `Paqet Tunnel -> Client configuration -> Repair networking stack`

Or script:

```bash
sudo ~/paqet_tunnel/scripts/repair_networking_stack.sh auto
```

## Cloudflare WARP (Policy Routing)

WARP is split into:

- Core layer: install/remove `wgcf` from `Paqet Tunnel -> WARP/DNS core`
- Binding layer: enable/disable per consumer (`paqet`, `ssh`, `waterwall`, `icmptunnel`)

Behavior:

- Routes selected traffic through WARP using UID policy routing
- Keeps non-target server traffic on normal route
- For ICMP Tunnel: uses protocol-level filtering (TCP/UDP only, ICMP excluded)

### WARP Routing Modes by Tunnel Type

| Tunnel Type | Routing Mode | Protocols Routed | Notes |
|-------------|--------------|------------------|-------|
| **Paqet** | uidrange-only | All (TCP/UDP/ICMP) | Simple uidrange rule, no protocol filtering needed |
| **WaterWall** | uidrange-only | All (TCP/UDP/ICMP) | Simple uidrange rule, no protocol filtering needed |
| **SSH Proxy** | uidrange-only | All (TCP/UDP/ICMP) | Simple uidrange rule per SSH user |
| **ICMP Tunnel** | uidrange + ipproto | **TCP/UDP only** | **CRITICAL:** ICMP must NOT be routed through WARP (breaks tunnel) |

### ICMP Tunnel + WARP Technical Details

ICMP Tunnel requires special handling because:
- The tunnel protocol itself uses ICMP packets (ping)
- If ICMP echo requests/replies are routed through WARP, the tunnel breaks
- Only the encapsulated traffic (TCP/UDP) should go through WARP

**Implementation:**
```bash
# Modern iproute2 (v4.17+) - protocol-level filtering
ip rule add uidrange 995-995 ipproto tcp table 51820
ip rule add uidrange 995-995 ipproto udp table 51820
# ICMP is NOT routed through WARP - goes direct to/from server
```

**Verification:**
```bash
ip rule show | grep icmptunnel
# Should show separate TCP and UDP rules, NO rule for ICMP
```

**Requirements:**
- iproute2 v4.17+ (Ubuntu 18.04+, Debian 10+)
- Kernel support for ipproto filtering in ip rules

**Fallback on old systems:**
- If ipproto is not supported, WARP cannot be used with ICMP Tunnel
- Use ICMP tunnel without WARP, or use different tunnel type

## DNS Policy Blocklist

DNS policy is split into:

- Core layer: dnsmasq policy resolver and updater
- Binding layer: enable/disable DNS redirect per consumer

Highlights:

- Local resolver on `127.0.0.1:5353`
- Category-based blocklist from bootmortis repository
- Daily updater via cron
- Applies to target users, not all server traffic

## Firewall (UFW)

Firewall option adds safe allow rules and enables UFW:

- Detects SSH ports and keeps them open (critical for remote access)
- Server: allows tunnel port/protocol from client IP
- Client: allows outbound to server IP/port/protocol
- Avoids duplicate rules

### Firewall Rules by Tunnel Type

| Tunnel Type | Server Rules | Client Rules | Special Handling |
|-------------|--------------|--------------|------------------|
| **Paqet** | TCP port (server) from client | Outbound TCP to server | UFW TCP rules |
| **WaterWall** | TCP port (server) from client | Outbound TCP to server | UFW TCP rules |
| **SSH Proxy** | SSH ports preserved | N/A | Auto-detects custom SSH ports |
| **ICMP Tunnel** | **ICMP protocol** from client | Outbound **ICMP** to server | **Uses iptables** (UFW doesn't support ICMP) |

### ICMP Tunnel Firewall

UFW does not support protocol-level filtering (only TCP/UDP ports), so ICMP tunnel firewall uses **iptables directly**:

**Server (allows ICMP from client):**
```bash
# If client IP is specified
iptables -I INPUT -s CLIENT_IP -p icmp -m comment --comment icmptunnel -j ACCEPT

# If no client IP (allows from anywhere - not recommended)
iptables -I INPUT -p icmp -m comment --comment icmptunnel -j ACCEPT

# Rules are saved to nftables.conf or iptables rules.v4
```

**Client (allows outbound ICMP to server):**
```bash
# Outbound ICMP to server
iptables -I OUTPUT -d SERVER_IP -p icmp -m comment --comment icmptunnel -j ACCEPT

# Optional: SOCKS5 port (UFW rule)
ufw allow SOCKS_PORT/tcp comment 'icmptunnel-socks'
```

**Verification:**
```bash
# Check iptables ICMP rules
sudo iptables -L INPUT -n -v | grep icmp
sudo iptables -L OUTPUT -n -v | grep icmp

# Check UFW status
sudo ufw status verbose
```
