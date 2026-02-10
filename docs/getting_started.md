# Getting Started

These steps assume **server first**, then **client**. Tested on **Ubuntu 24.04**.

## Server (Destination VPS)

1. `Paqet Tunnel -> Install Paqet`
2. `Paqet Tunnel -> Server configuration -> Create server config`
3. Copy printed command and run it on client VPS (creates `server_info.txt`)
4. `Add iptable rules`
5. `Install systemd service`
6. Optional: restart scheduler, health check, WARP

## Client (Local VPS)

1. `Paqet Tunnel -> Install Paqet`
2. `Paqet Tunnel -> Client configuration -> Create client config`
3. `Install systemd service`
4. Optional: restart scheduler and health check
5. `Test connection`

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
