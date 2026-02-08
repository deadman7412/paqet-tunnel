# SSH Proxy Guide

This guide explains how to use the SSH Proxy features from `menu.sh`.

## Prerequisites

- Run as `root` (or `sudo`) on the server.
- Paqet server should already be installed/configured.
- `server_info.txt` should contain `server_public_ip` for best UX.

## Menu Path

Run:

```bash
cd ~/paqet_tunnel
./menu.sh
```

Open:

- `SSH Proxy`

## Recommended Order

1. `Manage SSH proxy port`
2. `Create SSH proxy user`
3. `Enable SSH firewall rules`
4. `Enable WARP on SSH` (optional)
5. `Enable server DNS routing on SSH` (optional)
6. `Generate sing-box client config`

## What Each Option Does

- `Manage SSH proxy port`
  - Sets one dedicated SSH proxy port in server state.
  - Validates conflicts (existing SSH ports, paqet port, in-use ports).
  - Updates SSH config and reloads SSH.

- `Create SSH proxy user`
  - Creates Linux user.
  - Auto-generates SSH keypair for that user.
  - Stores metadata under `/etc/paqet-ssh-proxy/users/`.

- `Remove SSH proxy user`
  - Removes the user and proxy metadata.

- `List SSH proxy users`
  - Shows configured users and status.

- `Enable/Disable SSH firewall rules`
  - Adds/removes UFW allow rule for the configured SSH proxy port.

- `Enable/Disable WARP on SSH`
  - Adds/removes UID-based routing rules for SSH proxy users.

- `Enable/Disable server DNS routing on SSH`
  - Adds/removes UID-based DNS redirect rules for SSH proxy users.

- `Generate sing-box client config`
  - Builds per-user sing-box config at:
    - `/etc/paqet-ssh-proxy/clients/<username>/sing-box.json`
  - Embeds the generated private SSH key directly in config.
  - Prints a terminal QR from that same embedded config.

## Client Usage (sing-box)

On the client device:

1. Import config (or scan QR shown during generation).
2. Start sing-box with that profile.
3. Use local proxy from the config (`mixed` inbound, default `127.0.0.1:2080`).

## Troubleshooting

- `SSH proxy port is not configured`
  - Run `Manage SSH proxy port` first.

- `Private key file not found`
  - Recreate the user or inspect:
    - `/etc/paqet-ssh-proxy/users/<username>.json`

- `qrencode not found`
  - Generator attempts to install it automatically.
  - Manual install fallback:
    - `apt-get install -y qrencode`

