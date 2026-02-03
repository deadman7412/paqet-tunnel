# Paqet Tunnel Scripts

This folder contains a menu‑driven setup for installing, configuring, and operating **paqet** on Linux VPS servers (server and client). It automates the common steps from the paqet README and adds operational tooling (systemd, restart scheduler, logs, uninstall).

## Quick Start

1. Copy this folder to your VPS (server or client).
2. Run the menu:

```bash
./menu.sh
```

## What Gets Installed Where

- Paqet binaries and configs live in: `~/paqet`
- Menu scripts live in: `~/paqet_tunnel`

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

If file transfer is not possible, **Show server info** prints a ready-to-paste command block to recreate it on the client.

## Client Configuration Menu

Options include:
- **Create client config** → creates `~/paqet/client.yaml`
- **Install systemd service** → creates `paqet-client.service`
- **Remove systemd service**
- **Service control**
- **Restart scheduler**
- **Test connection** → runs curl with SOCKS5
- **Health check**
- **Health logs**

### Client Config Defaults
If `~/paqet/server_info.txt` is present, the client config auto‑fills:
- Server port
- KCP key
- Server public IP (if present)

## Restart Scheduler (Cron)

Creates a cron job in `/etc/cron.d/` to restart the service at fixed intervals:
- 30 minutes
- 1, 2, 4, 8, 12, 24 hours

Selecting a schedule overwrites the previous one.

## Health Checks (Cron)

Health checks run via cron and **restart the service only when needed**, with a safety cap of **max 5 restarts per hour**.

### Client health logic
- If service is not active → restart\n+- SOCKS5 test fails → restart

### Server health logic
- If service is not active → restart\n+- Recent logs include `connection lost`, `timeout`, or `reconnect` → restart\n+- No logs for 10 minutes → restart

### Health logs
Logs are written to:\n- `/var/log/paqet-health-server.log`\n- `/var/log/paqet-health-client.log`

Logs are auto‑rotated when they exceed **1MB** (current log is truncated and previous is saved to `.1`).

## Systemd Services

Services are created as:
- `paqet-server.service`
- `paqet-client.service`

Service runs:
```
~/paqet/paqet run -c ~/paqet/<role>.yaml
```

## Logs

From **Service control**:
- **Live logs (tail 20)** → uses `journalctl -u <service> -n 20 -f`.
- Press **Ctrl+C** to return to menu.

## Uninstall

Uninstall removes:
- `~/paqet` directory
- systemd services
- cron jobs created by the menu

Then optionally asks for **reboot**.

## Files Included

- `menu.sh` – main menu
- `install_paqet.sh` – installer + dependency setup
- `create_server_config.sh` – server config generator
- `create_client_config.sh` – client config generator
- `add_server_iptables.sh` – server iptables rules
- `remove_server_iptables.sh` – remove iptables rules
- `install_systemd_service.sh` – create service
- `remove_systemd_service.sh` – remove service
- `service_control.sh` – systemd control + logs
- `cron_restart.sh` – restart scheduler
- `test_client_connection.sh` – SOCKS5 test
- `show_server_info.sh` – show/recreate server_info.txt
- `health_check.sh` – server/client health check logic
- `health_check_scheduler.sh` – health check scheduler
- `show_health_logs.sh` – view/clear health logs
- `health_log_rotate.sh` – rotate health logs
- `uninstall_paqet.sh` – full uninstall

## Notes

- Scripts are designed for **Linux** VPS only.
- All scripts are auto‑chmod’d on menu start.
- The menu does not close on errors; it returns to the menu.
