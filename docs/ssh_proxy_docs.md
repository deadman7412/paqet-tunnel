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

1. `WARP/DNS core -> Install WARP core` (optional, if you want SSH users over WARP)
2. `WARP/DNS core -> Install DNS policy core` (optional, if you want DNS routing)
3. `Manage SSH proxy port`
4. `Create SSH proxy user`
5. `Enable SSH firewall rules`
6. `Enable WARP on SSH` (optional)
7. `Enable server DNS routing on SSH` (optional)
8. `Show simple SSH credentials`

## Legacy Order (before core split)

1. `Manage SSH proxy port`
2. `Create SSH proxy user`
3. `Enable SSH firewall rules`
4. `Enable WARP on SSH` (optional)
5. `Enable server DNS routing on SSH` (optional)
6. `Show simple SSH credentials`

## What Each Option Does

- `Manage SSH proxy port`
  - Sets one dedicated SSH proxy port in server state.
  - Validates conflicts (existing SSH ports, paqet port, in-use ports).
  - Updates SSH config and reloads SSH.

- `Create SSH proxy user`
  - Creates Linux user.
  - Uses password authentication.
  - Sets no-login shell for proxy-only access.
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

- `Show simple SSH credentials`
  - Prints username, password, server IP, and port.
  - Writes credentials file at:
    - `/etc/paqet-ssh-proxy/clients/<username>/ssh-simple.txt`

## Client Usage (Raw SSH)

On the client device:

1. Use the shown username/password/server/port in your SSH client app.
2. Enable dynamic SOCKS proxy / tunnel mode in the app.
3. Keep WARP/DNS SSH options enabled on server if required.

## Troubleshooting

- `SSH proxy port is not configured`
  - Run `Manage SSH proxy port` first.

- `Password is not stored`
  - Recreate the user with menu option `Create SSH proxy user`.
