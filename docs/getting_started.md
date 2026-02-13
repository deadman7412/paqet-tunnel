# Getting Started

Quick setup guides for all tunnel types. Tested on **Ubuntu 24.04** and **Debian 12**.

## Paqet Tunnel (SOCKS5/WireGuard)

### Server (Destination VPS)

1. `Paqet Tunnel -> Install Paqet`
2. `Paqet Tunnel -> Server configuration -> Create server config`
3. Copy printed command and run it on client VPS (creates `server_info.txt`)
4. `Add iptable rules`
5. `Install systemd service`
6. Optional: restart scheduler, health check, WARP

### Client (Local VPS)

1. `Paqet Tunnel -> Install Paqet`
2. `Paqet Tunnel -> Client configuration -> Create client config`
3. `Install systemd service`
4. Optional: restart scheduler and health check
5. `Test connection`

## WaterWall Tunnel (TCP Port Forwarding)

### Server (Destination VPS)

1. `WaterWall -> Install WaterWall`
2. `WaterWall -> Server menu -> Server setup`
3. `Install systemd service`
4. `Enable firewall` (optional but recommended)
5. Optional: WARP, DNS policy

### Client (Local VPS)

1. `WaterWall -> Install WaterWall`
2. `WaterWall -> Client menu -> Client setup`
3. `Install systemd service`
4. `Test -> Quick connection test`

## ICMP Tunnel (Covert ICMP-based Tunnel)

### Server (Destination VPS)

1. `ICMP Tunnel -> Install ICMP Tunnel`
2. `ICMP Tunnel -> Server menu -> Server setup`
3. Transfer `~/icmptunnel/server_info.txt` to client
4. `Install systemd service`
5. **Enable firewall** (critical - allows ICMP from client)
6. `Service control -> Start`

### Client (Local VPS)

1. Receive `~/icmptunnel/server_info.txt` from server
2. `ICMP Tunnel -> Install ICMP Tunnel`
3. `ICMP Tunnel -> Client menu -> Client setup`
4. `Install systemd service`
5. **Enable firewall** (allows outbound ICMP to server)
6. `Service control -> Start`
7. `Tests -> Quick connection test`

**Test SOCKS5 proxy:**
```bash
curl -x socks5://127.0.0.1:1010 https://api.ipify.org
```

## 3x-ui (Client VPS)

1. Install 3x-ui on client
2. Create Outbound SOCKS -> `127.0.0.1:1080`
3. Create Inbound (for example VLESS TCP)
4. In Xray routing, map inbound -> outbound
5. Save and restart Xray

## Proxychains4

Install from menu:

- `Paqet Tunnel -> Client configuration -> Install proxychains4`

Manual:

```bash
sudo ~/paqet_tunnel/scripts/install_proxychains4.sh
```

Example:

```bash
proxychains4 curl https://httpbin.org/ip
```
