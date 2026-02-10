# Menu and Operations

## Main Menu

- Paqet Tunnel
- Waterwall Tunnel

## Paqet Tunnel Menu

- Install Paqet
- Update Paqet
- Update Scripts (git pull)
- Server configuration
- Client configuration
- SSH proxy
- WARP/DNS core
- Uninstall / remove components

## Server Configuration Menu

- Create server config
- Add iptable rules
- Install systemd service
- Remove iptable rules
- Remove systemd service
- Service control
- Restart scheduler
- Show server info
- Change MTU
- Health check
- Health logs
- Enable/Disable WARP bind
- WARP status
- Test WARP
- Enable/Disable firewall (ufw)
- Repair networking stack
- Enable/Disable DNS policy bind
- Update DNS policy list now
- DNS policy status

## Client Configuration Menu

- Create client config
- Install proxychains4
- Install systemd service
- Remove systemd service
- Service control
- Restart scheduler
- Test connection
- Change MTU
- Health check
- Health logs
- Enable/Disable firewall (ufw)
- Repair networking stack

## Restart Scheduler

Creates `/etc/cron.d/*` jobs to restart service at fixed intervals:

- 30 minutes
- 1, 2, 4, 8, 12, 24 hours

## Health Checks

Cron-based health checks restart only when needed (max 5 restarts/hour).

Health logs:

- `/var/log/paqet-health-server.log`
- `/var/log/paqet-health-client.log`

## Uninstall Modes

- Remove paqet only
- Remove WARP core only
- Remove DNS core only
- Remove SSH proxy only
- Remove SSH proxy + all SSH users
- Full uninstall
