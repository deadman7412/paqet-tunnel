# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Paqet Tunnel Scripts is a menu-driven bash orchestration system for setting up and managing VPN tunnels on Linux VPS servers. It provides wrappers around two tunnel backends:
- **Paqet** (hanselime/paqet): SOCKS5/WireGuard tunnel
- **WaterWall** (radkesvat/WaterWall): Basic TCP tunnel

The project is NOT the tunnel software itself - it's a collection of bash scripts that automate installation, configuration, testing, and management.

## Architecture

### Menu System (`menu.sh`)

The entry point is `menu.sh`, which presents a hierarchical menu structure:
- Main menu → Paqet/WaterWall selection
- Role-specific submenus (server/client)
- Test and diagnostic submenus

**Key patterns:**
- All menu functions use `while true` loops to stay in submenu until user selects "Back"
- `ensure_executable_scripts()` at line 59-62 auto-chmod scripts on startup
- `pause()` function keeps menu visible after each operation
- Script paths are relative to `SCRIPT_DIR` (detected from `menu.sh` location)

### Configuration Architecture

**Paqet:**
- Install path: `~/paqet/` (binaries and YAML configs)
- Server config: `~/paqet/server.yaml`
- Client config: `~/paqet/client.yaml`
- Client reads `~/paqet/server_info.txt` (generated on server) for connection details

**WaterWall:**
- Install path: `~/waterwall/` (binary and JSON configs)
- Server config: `~/waterwall/server/config.json` + `core.json`
- Client config: `~/waterwall/client/config.json` + `core.json`
- Node-based JSON configuration: TcpListener → TcpConnector chain
- **Client listens on 0.0.0.0 by default** (accessible from internet for 3x-ui/proxy integration)

**WaterWall JSON Structure:**
```json
{
  "nodes": [
    {"name": "input", "type": "TcpListener", "settings": {"address": "0.0.0.0", "port": 39650}},
    {"name": "output", "type": "TcpConnector", "settings": {"address": "127.0.0.1", "port": 41358}}
  ]
}
```

### Script Organization

Scripts in `scripts/` are organized by feature prefix:
- `install_*.sh`, `update_*.sh`, `uninstall_*.sh`: Lifecycle management
- `create_*_config.sh`: Configuration generators
- `*_systemd_service.sh`: systemd integration
- `service_control.sh`: Start/stop/status/logs wrapper
- `test_*.sh`: Connection and tunnel testing
- `waterwall_*.sh`: WaterWall-specific operations
- `ssh_proxy_*.sh`: SSH proxy user management
- `warp_*.sh`, `dns_policy_*.sh`: WARP and DNS blocklist features
- `enable_firewall*.sh`, `disable_firewall*.sh`: UFW management

### Testing Architecture

**Paqet tests:**
- `test_client_connection.sh`: Basic SOCKS proxy test

**WaterWall tests (comprehensive):**
- `waterwall_test_all.sh`: Full diagnostic report (share with support)
- `waterwall_test_client_connection.sh`: Quick 4-step health check
- `waterwall_test_tunnel_complete.sh`: End-to-end tunnel validation
- `waterwall_start_test_backend.sh`: Start test HTTP echo server

**Python JSON parsing:**
All WaterWall test scripts use Python for accurate JSON parsing instead of grep/awk:
```bash
parse_json_nodes() {
  python3 -c "
import json
with open('${file}', 'r') as f:
    data = json.load(f)
nodes = data.get('nodes', [])
listener = nodes[0].get('settings', {})
connector = nodes[1].get('settings', {})
print('LISTEN_ADDR=' + str(listener.get('address', '')))
print('LISTEN_PORT=' + str(listener.get('port', '')))
"
}
```

### Policy Routing (WARP/DNS)

**Two-layer architecture:**
1. **Core layer**: Install base software (wgcf, dnsmasq)
2. **Binding layer**: Enable per-consumer (paqet-server service or SSH proxy users)

This allows multiple consumers to independently enable/disable WARP or DNS policy without affecting each other.

## Development Commands

### Running the Menu

```bash
cd ~/paqet_tunnel
./menu.sh
```

### Testing Scripts Directly

```bash
# Server setup
sudo ~/paqet_tunnel/scripts/create_server_config.sh

# Client setup
sudo ~/paqet_tunnel/scripts/create_client_config.sh

# WaterWall diagnostic (run on VPS, not local dev)
sudo ~/paqet_tunnel/scripts/waterwall_test_all.sh

# Test backend (run on server VPS)
sudo ~/paqet_tunnel/scripts/waterwall_start_test_backend.sh
```

### Systemd Service Management

```bash
# Install service
sudo ~/paqet_tunnel/scripts/install_systemd_service.sh [server|client]

# Control service
sudo ~/paqet_tunnel/scripts/service_control.sh [server|client] [start|stop|restart|status|logs]

# Example
sudo ~/paqet_tunnel/scripts/service_control.sh server status
```

### Release Management

```bash
# Create new release (updates VERSION file and git tag)
./scripts/release.sh
```

## Important Constraints

### Code Style Rules

**STRICTLY PROHIBITED: Emojis**
- Never use emojis (✅ ❌ ✓ ✗ ⚠ 🎉 🚀 etc.) in any code or output
- Use `[SUCCESS]` or `[FAILURE]` or `[OK]` or `[ERROR]` or `[WARN]` instead
- Apply proper color codes:
  - `${GREEN}[SUCCESS]${NC}` or `${GREEN}[OK]${NC}`
  - `${RED}[FAILURE]${NC}` or `${RED}[ERROR]${NC}`
  - `${YELLOW}[WARN]${NC}`
  - `${BLUE}[INFO]${NC}`

**Example:**
```bash
# ❌ WRONG
echo "✅ Service started"
echo "❌ Failed to connect"

# ✓ CORRECT
echo -e "${GREEN}[SUCCESS]${NC} Service started"
echo -e "${RED}[FAILURE]${NC} Failed to connect"
```

### WaterWall Configuration Rules

**ONLY focus on basic TCP profile:**
- Latest WaterWall release does NOT support TLS/HTTP2/gRPC/Obfuscation
- Use simple two-node chain: TcpListener → TcpConnector
- Server listens on public interface, forwards to localhost backend
- Client listens on localhost, connects to remote server

**Do NOT:**
- Add ALPN configuration (not supported without TLS)
- Use complex multi-node chains
- Assume SOCKS5 proxy mode (direct TCP forwarding only)

### Firewall Setup

**ALWAYS preserve SSH access:**
- Parse `/etc/ssh/sshd_config` for SSH ports before enabling UFW
- Add SSH allow rules BEFORE enabling firewall
- Client setup: `scripts/waterwall_direct_client_setup.sh` lines 82-86
- Server setup: Already has SSH protection

### Testing Best Practices

**Never run tests on local dev machine:**
- Tests use `/dev/tcp`, `ss`, `systemctl`, and VPS-specific networking
- Menu already handles script permissions via `ensure_executable_scripts()`
- Only test on actual VPS servers where services are deployed

**Public IP detection:**
- Use multiple fallback services (api.ipify.org, icanhazip.com, ipecho.net)
- Gracefully handle failure with "Unable to detect"
- See `waterwall_test_all.sh` lines 39-45

## Common Patterns

### Config Parsing

**Prefer Python over shell for JSON:**
```bash
# ❌ Bad: grep-based parsing reads wrong values
grep -o '"port".*' config.json | head -n1

# ✅ Good: Python JSON parser
parse_json_nodes() {
  python3 -c "
import json
data = json.load(open('config.json'))
print('PORT=' + str(data['nodes'][0]['settings']['port']))
"
}
```

### Menu Navigation Flow

```bash
# Pattern: Stay in submenu until explicit exit
waterwall_server_test_menu() {
  while true; do
    display_menu
    case "${choice}" in
      1) run_test; pause ;;    # Returns to menu after pause
      0) return 0 ;;           # Only exit on explicit "0"
    esac
  done
}
```

### Script Error Handling

```bash
#!/usr/bin/env bash
set -euo pipefail  # All scripts use strict mode

# Check prerequisites
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "Error: Config not found" >&2
  exit 1
fi
```

## Documentation Structure

- `docs/getting_started.md`: Server/client setup flow
- `docs/menu_and_operations.md`: Menu hierarchy reference
- `docs/networking_warp_dns_firewall.md`: Policy routing details
- `docs/ssh_proxy_docs.md`: SSH proxy user management
- `docs/WATERWALL_TESTING_GUIDE.md`: WaterWall testing workflow
- `docs/FIXES_APPLIED.md`: Recent bug fixes and verification steps

## Key Files to Know

- `menu.sh`: Main entry point, orchestrates all operations
- `scripts/install_paqet.sh`: Paqet binary download and installation
- `scripts/waterwall_install.sh`: WaterWall binary installation
- `scripts/waterwall_direct_server_setup.sh`: WaterWall server config generator
- `scripts/waterwall_direct_client_setup.sh`: WaterWall client config generator
- `scripts/waterwall_test_all.sh`: Comprehensive diagnostic report
- `scripts/repair_networking_stack.sh`: Fix networking issues after changes

## Version Management

Version is stored in `VERSION` file at repo root. Git tags match VERSION content. Use `scripts/release.sh` to bump version and create tags.
