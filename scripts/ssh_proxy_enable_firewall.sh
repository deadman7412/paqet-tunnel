#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

main() {
  local port=""
  local ssh_ports=""

  ssh_proxy_require_root
  port="$(ssh_proxy_get_configured_port)"
  if [ -z "${port}" ]; then
    echo "SSH proxy port is not configured. Run ssh_proxy_manage_port.sh first." >&2
    exit 1
  fi

  if ! command -v ufw >/dev/null 2>&1; then
    echo "ufw is not installed. Install and enable it first." >&2
    exit 1
  fi

  if ! ufw status 2>/dev/null | head -n1 | grep -q "Status: active"; then
    echo "ufw is not active. Enable ufw first, then re-run this option." >&2
    exit 1
  fi

  ssh_ports="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u)"
  if [ -z "${ssh_ports}" ]; then
    ssh_ports="22"
  fi
  echo "SSH ports detected: ${ssh_ports}"
  for p in ${ssh_ports}; do
    if ! ufw status 2>/dev/null | grep -qE "\\b${p}/tcp\\b.*ALLOW IN"; then
      ufw allow "${p}/tcp" comment 'paqet-ssh' >/dev/null 2>&1 || true
    fi
  done

  ssh_proxy_ensure_ufw_port_if_active "${port}"
  echo "Enabled SSH firewall rule for port ${port}/tcp."
}

main "$@"
