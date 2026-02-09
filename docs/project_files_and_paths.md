# Project Files and Paths

## Installed Paths

- Paqet binaries and configs: `~/paqet`
- Menu script: `~/paqet_tunnel/menu.sh`
- Helper scripts: `~/paqet_tunnel/scripts`

Installer always uses `~/paqet`.

## Systemd Services

- `paqet-server.service`
- `paqet-client.service`

Service command:

```bash
~/paqet/paqet run -c ~/paqet/<role>.yaml
```

## Key Scripts

- `scripts/install_paqet.sh`
- `scripts/update_paqet.sh`
- `scripts/create_server_config.sh`
- `scripts/create_client_config.sh`
- `scripts/install_systemd_service.sh`
- `scripts/service_control.sh`
- `scripts/cron_restart.sh`
- `scripts/health_check.sh`
- `scripts/install_proxychains4.sh`
- `scripts/repair_networking_stack.sh`
- `scripts/uninstall_paqet.sh`
