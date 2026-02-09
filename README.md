# Paqet Tunnel Scripts

![Release](https://img.shields.io/github/v/release/deadman7412/paqet-tunnel)

> **Notice**
> This project is intended for personal experimentation and learning.
> Do not use it for unlawful activities or in production systems.

This repo provides a menu-driven setup for installing, configuring, and operating **paqet** on Linux VPS servers (server and client).

**Credit:** Paqet is created and maintained by [hanselime/paqet](https://github.com/hanselime/paqet). This project only provides helper scripts.

## Features

- **Menu-driven setup:** Interactive server/client workflows for Paqet on Linux VPS
- **Install/Update/Uninstall:** One-command lifecycle management from the main menu
- **Config generation:** Server/client config creators with backup-safe overwrites
- **Service management:** Systemd install/remove plus start/stop/status/log controls
- **Health checks:** Cron-based health monitoring with auto-restart and health logs
- **Restart scheduler:** Fixed-interval cron restarts for server or client service
- **Proxy support:** Built-in `proxychains4` install and auto-configuration for Paqet SOCKS
- **Network controls:** UFW + iptables helpers and networking stack repair actions
- **WARP routing:** Optional Cloudflare WARP policy routing with status/tests
- **SSH proxy:** Managed SSH proxy users (password auth), simple credentials output, and explicit firewall/WARP/DNS toggles
- **Diagnostics:** Built-in connection tests, WARP tests, and server info tools

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

1. On destination VPS: `Install Paqet` -> `Server configuration` -> create server config.
2. On client VPS: `Install Paqet` -> `Client configuration` -> create client config.
3. Install systemd service on both sides.
4. Run connection test from client menu.

## Documentation

Detailed docs are split by topic in `docs/`:

- [Getting Started](docs/getting_started.md)
- [Updates and Versioning](docs/updates_and_versioning.md)
- [Menu and Operations](docs/menu_and_operations.md)
- [Networking, WARP, DNS, Firewall](docs/networking_warp_dns_firewall.md)
- [SSH Proxy Guide](docs/ssh_proxy_docs.md)
- [Project Files and Paths](docs/project_files_and_paths.md)

If this project is useful to you, consider giving it a star.
