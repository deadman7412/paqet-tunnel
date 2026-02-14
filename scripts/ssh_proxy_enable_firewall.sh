#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

ensure_ufw() {
  if command -v ufw >/dev/null 2>&1; then
    return 0
  fi

  read -r -p "ufw not found. Install ufw? [y/N]: " install_ufw
  case "${install_ufw}" in
    y|Y)
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
      elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ufw
      elif command -v yum >/dev/null 2>&1; then
        yum install -y ufw
      else
        echo "No supported package manager found." >&2
        exit 1
      fi
      ;;
    *)
      echo "Skipped ufw install."
      exit 0
      ;;
  esac
}

ensure_ssh_ports() {
  local ssh_ports=""

  ssh_ports="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u || true)"
  if [ -z "${ssh_ports}" ]; then
    ssh_ports="22"
  fi

  echo "SSH ports detected: ${ssh_ports}"
  for p in ${ssh_ports}; do
    if ! ufw status 2>/dev/null | grep -qE "\\b${p}/tcp\\b.*ALLOW IN"; then
      echo "Opening SSH port ${p}/tcp..."
      ufw allow "${p}/tcp" comment 'paqet-ssh' >/dev/null 2>&1 || true
    fi
  done
}

main() {
  local port=""

  ssh_proxy_require_root
  port="$(ssh_proxy_get_configured_port)"
  if [ -z "${port}" ]; then
    echo "SSH proxy port is not configured. Run ssh_proxy_manage_port.sh first." >&2
    exit 1
  fi

  echo "[INFO] Ensuring UFW is installed..."
  ensure_ufw

  if ! ufw status 2>/dev/null | head -n1 | grep -q "Status: active"; then
    echo "[INFO] UFW is not active. Enabling UFW with safe defaults..."
    ufw default deny incoming >/dev/null 2>&1 || true
    ufw default allow outgoing >/dev/null 2>&1 || true
    ufw allow in on lo comment 'paqet-loopback' >/dev/null 2>&1 || true

    echo "[INFO] Ensuring SSH ports are protected before enabling UFW..."
    ensure_ssh_ports

    echo "[INFO] Enabling UFW..."
    ufw --force enable >/dev/null 2>&1 || true
    echo "[INFO] UFW enabled successfully."
  else
    echo "[INFO] UFW is already active."
    echo "[INFO] Ensuring SSH ports are protected..."
    ensure_ssh_ports
  fi

  ssh_proxy_ensure_ufw_port_if_active "${port}"
  echo "Enabled SSH firewall rule for port ${port}/tcp."
}

main "$@"
