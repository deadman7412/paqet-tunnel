# Paqet Tunnel Scripts

## Install & Setup (Quick Guide)

These steps assume **server first**, then **client**. Tested on **Ubuntu 24.04**.

### Server (Destination VPS)
1. **Get the scripts**
   - Option A: `git clone <REPO_URL>` (replace when ready).
   - Option B: download the source and upload it to the server.
2. **Place in the correct folder**
   ```bash
   mv <source-folder> ~/paqet_tunnel
   cd ~/paqet_tunnel
   chmod +x menu.sh
   ./menu.sh
   ```
3. **Install Paqet**
   - Menu → **Install Paqet**
4. **Create server config**
   - Menu → **Server configuration → Create server config**
   - **Copy the printed command** and run it on the client VPS (this creates `server_info.txt`).
5. **Apply iptables + systemd**
   - Menu → **Add iptable rules**
   - Menu → **Install systemd service**
6. **Optional scheduling**
   - Menu → **Restart scheduler** (cron restart)
   - Menu → **Health check** (auto‑restart if needed)
7. **Optional WARP**
   - Menu → **Enable WARP (policy routing)**
   - Menu → **Test WARP** (confirm `warp=on` for paqet traffic)

### Client (Local VPS)
1. **If GitHub is blocked**, download the release tarball manually:
   - Use the **same paqet version** as the server.
   - Place the tarball in `~/paqet` before running Install.
2. **Install Paqet**
   - Menu → **Install Paqet**
3. **Create client config**
   - Menu → **Client configuration → Create client config**
   - If you ran the server’s copy/paste command, values auto‑fill.
4. **Install systemd + optional schedules**
   - Menu → **Install systemd service**
   - Menu → **Restart scheduler** and/or **Health check**
5. **Test connection**
   - Menu → **Test connection** (shows proxy IP)

### Logs & Status
- **Service logs:** Menu → **Service control → Live logs**
  - Press **Ctrl+C** to return.
- **Health logs:** Menu → **Health logs**

### Using the Tunnel With 3x‑ui (Client VPS)
1. Install **3x‑ui** on the client server.
2. Create **Outbound** → SOCKS:
   - Address: `127.0.0.1`
   - Port: `1080`
3. Create **Inbound** (simple **VLESS TCP** is enough).
4. Go to **Xray Settings → Routing**:
   - Add a rule linking the new inbound → new outbound.
5. Save and restart Xray.

Now your traffic routes through the paqet tunnel.

This folder contains a menu‑driven setup for installing, configuring, and operating **paqet** on Linux VPS servers (server and client). It automates the common steps from the paqet README and adds operational tooling (systemd, restart scheduler, logs, uninstall).

## Quick Start

1. Copy this folder to your VPS (server or client).
2. Run the menu:

```bash
./menu.sh
```

## What Gets Installed Where

- Paqet binaries and configs live in: `~/paqet`
- Menu script lives in: `~/paqet_tunnel/menu.sh`
- Helper scripts live in: `~/paqet_tunnel/scripts`

The installer always uses `~/paqet` regardless of the current directory.

## Main Menu Options

- **Install Paqet**: Downloads paqet, installs libpcap, extracts and renames the binary to `~/paqet/paqet`.
- **Server configuration**: Server setup (config, iptables, systemd, service control, restart scheduler, show server info).
- **Client configuration**: Client setup (config, systemd, service control, restart scheduler, test connection).
- **Uninstall Paqet**: Removes paqet files, services, cron jobs, and optionally reboots.

## Install Behavior

The installer detects:
- **CPU arch** (`amd64` / `arm64`) from `uname -m`
- **latest paqet release** from GitHub API
- **libpcap** via your package manager (apt/dnf/yum)

### GitHub blocked or slow
- The download is time‑limited (connect 5s, total ~20s).
- If GitHub is unreachable, the menu shows a notice and tells you to download manually.
- If the tarball download fails, the script shows a **manual download** section with the exact tarball name and URL.

### Empty or broken tarball
- If a tarball is **0 bytes**, the installer removes it automatically.
- If it still exists, it prints the exact `rm -f` command to run.
- If extraction fails, it deletes the tarball and asks you to re‑download.

## Server Configuration Menu

Options include:
- **Create server config** → creates `~/paqet/server.yaml`
- **Add iptable rules** → applies required rules from paqet README and persists them
- **Install systemd service** → creates `paqet-server.service`
- **Remove iptable rules** → removes rules and can remove persistence packages
- **Remove systemd service** → removes the service
- **Service control** → start/stop/restart/status/enable/disable/reset failed/logs
- **Restart scheduler** → cron‑based service restart schedule
- **Health check** → auto‑restart if stuck (server/client)
- **Health logs** → view/clear health check logs
- **Enable WARP (policy routing)** → route paqet traffic through Cloudflare WARP (server)
- **Disable WARP (policy routing)**
- **WARP status**
- **Test WARP** → full diagnostics (wg, routing, iptables/nft, curl tests + summary)
- **Show server info** → shows or recreates `~/paqet/server_info.txt`

### server_info.txt
When server config is created, the script writes:

```
~/paqet/server_info.txt
```

This contains:
- `listen_port`
- `kcp_key`
- `server_public_ip`
- `mtu`

If file transfer is not possible, **Show server info** prints a ready-to-paste command block to recreate it on the client.

## Client Configuration Menu

Options include:
- **Create client config** → creates `~/paqet/client.yaml`
- **Install systemd service** → creates `paqet-client.service`
- **Remove systemd service**
- **Service control**
- **Restart scheduler**
- **Test connection** → runs curl with SOCKS5 and prints the IP response
- **Change MTU** → updates client MTU (and restarts client service)
- **Health check**
- **Health logs**

### Client Config Defaults
If `~/paqet/server_info.txt` is present, the client config auto‑fills:
- Server port
- KCP key
- Server public IP (if present)
- MTU

## Restart Scheduler (Cron)

Creates a cron job in `/etc/cron.d/` to restart the service at fixed intervals:
- 30 minutes
- 1, 2, 4, 8, 12, 24 hours

Selecting a schedule overwrites the previous one.

## Health Checks (Cron)

Health checks run via cron and **restart the service only when needed**, with a safety cap of **max 5 restarts per hour**.

### Client health logic
- If service is not active → restart
- SOCKS5 test fails → restart

### Server health logic
- If service is not active → restart
- Recent logs include `connection lost`, `timeout`, or `reconnect` → restart
- No logs for 10 minutes → restart

### Health logs
Logs are written to:
- `/var/log/paqet-health-server.log`
- `/var/log/paqet-health-client.log`

Logs are auto‑rotated when they exceed **1MB** (current log is truncated and previous is saved to `.1`).

## Cloudflare WARP (Policy Routing)

This is the **3x‑ui style** setup: only paqet traffic is routed through WARP, not the whole server.

Features:
- Creates a WARP WireGuard profile using **wgcf**
- Brings up `wgcf` interface
- Adds **policy routing** for traffic from the `paqet` user
- Adds a **uidrange rule** (stronger than marks) for reliability
- Does **not** affect SSH (traffic not owned by `paqet` stays on default route)

### Ubuntu 24.04 vs 22.04 notes
- Ubuntu **24.04** uses **nftables** by default (iptables-nft).
- Ubuntu **22.04** may use **iptables-legacy** or **nft** depending on setup.
- Scripts automatically detect the backend and install the mark rule via **iptables** or **nft** as needed.
- On nft backends, `iptables -t mangle` may print errors; this is expected and does not affect nft rules.

You can optionally enter a **WARP+ license key** during setup.

Note: This config uses a systemd drop‑in to run `paqet-server` as user `paqet` with required capabilities.
Enable WARP performs a quick verification and warns if `paqet` traffic is not using WARP.

## Systemd Services

Services are created as:
- `paqet-server.service`
- `paqet-client.service`

Service runs:
```
~/paqet/paqet run -c ~/paqet/<role>.yaml
```
When WARP is enabled, the service runs as user `paqet` from `/opt/paqet` so it can be policy‑routed safely.

## Logs

From **Service control**:
- **Live logs (tail 20)** → uses `journalctl -u <service> -n 20 -f`.
- Press **Ctrl+C** to return to menu.

## Uninstall

Uninstall removes:
- `~/paqet` directory
- systemd services
- cron jobs created by the menu
- WARP files (wgcf, wgcf.conf, routing, firewall marks)

Then optionally asks for **reboot**.

## Files Included

- `menu.sh` – main menu
- `scripts/install_paqet.sh` – installer + dependency setup
- `scripts/create_server_config.sh` – server config generator
- `scripts/create_client_config.sh` – client config generator
- `scripts/add_server_iptables.sh` – server iptables rules
- `scripts/remove_server_iptables.sh` – remove iptables rules
- `scripts/install_systemd_service.sh` – create service
- `scripts/remove_systemd_service.sh` – remove service
- `scripts/service_control.sh` – systemd control + logs
- `scripts/cron_restart.sh` – restart scheduler
- `scripts/test_client_connection.sh` – SOCKS5 test
- `scripts/change_mtu.sh` – update MTU (server/client + WARP)
- `scripts/show_server_info.sh` – show/recreate server_info.txt
- `scripts/health_check.sh` – server/client health check logic
- `scripts/health_check_scheduler.sh` – health check scheduler
- `scripts/show_health_logs.sh` – view/clear health logs
- `scripts/health_log_rotate.sh` – rotate health logs
- `scripts/enable_warp_policy.sh` – enable WARP policy routing (server)
- `scripts/disable_warp_policy.sh` – disable WARP policy routing
- `scripts/warp_status.sh` – show WARP status
- `scripts/test_warp_full.sh` – full WARP diagnostics
- `scripts/uninstall_paqet.sh` – full uninstall

## Notes

- Scripts are designed for **Linux** VPS only.
- All scripts are auto‑chmod’d on menu start.
- The menu does not close on errors; it returns to the menu.
