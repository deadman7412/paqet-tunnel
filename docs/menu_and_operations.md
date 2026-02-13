# Menu and Operations

## Main Menu

1. Paqet Tunnel
2. WaterWall Tunnel
3. Update Scripts (git pull)
4. ICMP Tunnel
5. SSH Proxy
6. WARP/DNS core
7. DNS blocklist
8. Firewall (UFW)
9. Uninstall / remove components

## Paqet Tunnel Menu

- Install Paqet
- Update Paqet
- Server configuration
- Client configuration

## WaterWall Tunnel Menu

- Install WaterWall
- Update WaterWall
- Direct WaterWall tunnel
  - Server menu
  - Client menu
- Reverse WaterWall tunnel
- Uninstall WaterWall

## ICMP Tunnel Menu

- Install ICMP Tunnel
- Update ICMP Tunnel
- Server menu
  - Server setup
  - Install systemd service
  - Remove systemd service
  - Service control
  - Show server info
  - Tests (diagnostic, WARP status, DNS status, logs)
- Client menu
  - Client setup
  - Install systemd service
  - Remove systemd service
  - Service control
  - Tests (diagnostic, connection test, WARP status, DNS status, logs)
- Uninstall ICMP Tunnel

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

Available from `Main Menu -> 9) Uninstall / remove components`:

- Remove Paqet only
- Remove WaterWall only
- Remove ICMP Tunnel only
- Remove WARP core only
- Remove DNS core only
- Remove SSH proxy only
- Remove SSH proxy + all SSH users
- Full uninstall (removes everything)

**Important:** Uninstall operations:
- Stop and disable systemd services
- Remove binaries and configurations
- Remove system users (if created for WARP/DNS)
- Remove firewall rules
- Remove WARP/DNS policy bindings
- Remove state files and logs
