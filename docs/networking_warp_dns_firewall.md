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
- Binding layer: enable/disable per consumer (`paqet-server` or SSH proxy users)

Behavior:

- Routes selected traffic through WARP using UID policy routing
- Keeps non-target server traffic on normal route

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

- Detects SSH ports and keeps them open
- Server: allows paqet port from client IP
- Client: allows outbound to server IP/port
- Avoids duplicate rules
