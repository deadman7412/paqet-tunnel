#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

main() {
  local port=""

  ssh_proxy_require_root
  port="$(ssh_proxy_get_configured_port)"
  if [ -z "${port}" ]; then
    echo "SSH proxy port is not configured. Nothing to disable."
    exit 0
  fi

  if ! command -v ufw >/dev/null 2>&1; then
    echo "ufw is not installed. Nothing to disable."
    exit 0
  fi

  ssh_proxy_remove_ufw_port_if_active "${port}"
  echo "Disabled SSH firewall rule for port ${port}/tcp (if present)."
}

main "$@"
