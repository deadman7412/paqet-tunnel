# Paqet Tunnel Scripts

![Release](https://img.shields.io/github/v/release/deadman7412/paqet-tunnel)

> **Notice**
> This project is intended for personal experimentation and learning.
> Do not use it for unlawful activities or in production systems.

This repo provides a menu-driven setup for installing, configuring, and operating **Paqet**, **WaterWall**, and **ICMP Tunnel** on Linux VPS servers (server and client).

**Credits:**
- Paqet is created and maintained by [hanselime/paqet](https://github.com/hanselime/paqet)
- WaterWall is created and maintained by [radkesvat/WaterWall](https://github.com/radkesvat/WaterWall)
- ICMP Tunnel is created and maintained by [jakev/ICMPTunnel](https://github.com/jakev/ICMPTunnel)

This project only provides helper scripts for easy installation and management.

## Features

### Core Features
- **Multiple tunnel backends:** Paqet (SOCKS5/WireGuard), WaterWall (TCP tunnel), ICMP Tunnel (ICMP-based covert tunnel)
- **Menu-driven setup:** Interactive server/client workflows for all tunnel types on Linux VPS
- **Install/Update/Uninstall:** One-command lifecycle management from the main menu
- **Config generation:** Server/client config creators with backup-safe overwrites
- **Service management:** Systemd install/remove plus start/stop/status/log controls
- **Proxy support:** Built-in `proxychains4` install and auto-configuration for SOCKS proxies

### Network & Security
- **WARP routing:** Optional Cloudflare WARP policy routing with per-tunnel binding
- **DNS policy:** DNS blocklists (ads/malware/tracking) with per-tunnel binding
- **Firewall management:** UFW + iptables helpers for all tunnel types
- **Network controls:** Networking stack repair actions and diagnostics
- **SSH proxy:** Managed SSH proxy users with password auth, firewall/WARP/DNS toggles

### Monitoring & Diagnostics
- **Health checks:** Cron-based health monitoring with auto-restart and health logs
- **Restart scheduler:** Fixed-interval cron restarts for server or client service
- **Comprehensive tests:** Connection tests, WARP tests, DNS tests, and diagnostic reports
- **Service logs:** Easy access to systemd logs for all services

### ICMP Tunnel Specific
- **Covert tunneling:** Bypass restrictive firewalls using ICMP (ping) packets
- **SOCKS5 proxy:** Client exposes SOCKS5 proxy for application routing
- **Encryption support:** Optional data encryption for secure communication
- **WARP/DNS integration:** Full support for WARP routing and DNS policy binding

## Installation

### Option A (Git clone, recommended)

```bash
git clone https://github.com/deadman7412/paqet-tunnel ~/paqet_tunnel
cd ~/paqet_tunnel
chmod +x menu.sh
./menu.sh
```

### Option B (Manual ZIP)

```bash
# 1) On GitHub, click Code -> Download ZIP
# 2) Upload ZIP to your server
scp paqet-tunnel-main.zip root@<SERVER_IP>:/root/

# 3) Unzip and run
cd /root
apt-get update -y && apt-get install -y unzip
unzip paqet-tunnel-main.zip
mv paqet-tunnel-main ~/paqet_tunnel
cd ~/paqet_tunnel
chmod +x menu.sh
./menu.sh
```

## Quick Setup Flow

### Paqet Tunnel
1. On destination VPS: `Paqet Tunnel` -> `Install Paqet` -> `Server configuration` -> create server config
2. On client VPS: `Paqet Tunnel` -> `Install Paqet` -> `Client configuration` -> create client config
3. Install systemd service on both sides
4. Run connection test from client menu

### WaterWall Tunnel
1. On destination VPS: `WaterWall` -> `Install WaterWall` -> `Server menu` -> server setup
2. On client VPS: `WaterWall` -> `Install WaterWall` -> `Client menu` -> client setup
3. Install systemd service on both sides
4. Run diagnostic report or connection test

### ICMP Tunnel
1. On destination VPS: `ICMP Tunnel` -> `Install ICMP Tunnel` -> `Server menu` -> server setup
2. Transfer `~/icmptunnel/server_info.txt` to client VPS
3. On client VPS: `ICMP Tunnel` -> `Install ICMP Tunnel` -> `Client menu` -> client setup
4. Install systemd service and enable firewall on both sides
5. Run quick connection test from client menu

## Documentation

Detailed docs are split by topic in `docs/`:

- [Getting Started](docs/getting_started.md)
- [Updates and Versioning](docs/updates_and_versioning.md)
- [Menu and Operations](docs/menu_and_operations.md)
- [Networking, WARP, DNS, Firewall](docs/networking_warp_dns_firewall.md)
- [SSH Proxy Guide](docs/ssh_proxy_docs.md)
- [ICMP Tunnel Guide](docs/icmptunnel_guide.md) - **New!** Covert tunneling using ICMP packets
- [Project Files and Paths](docs/project_files_and_paths.md)

If this project is useful to you, consider giving it a star.
