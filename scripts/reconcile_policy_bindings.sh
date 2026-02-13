#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-all}"
TABLE_ID=51820
SERVER_POLICY_STATE_FILE="/etc/paqet-policy/settings.env"
SSH_PROXY_SETTINGS_FILE="/etc/paqet-ssh-proxy/settings.env"
WATERWALL_POLICY_STATE_FILE="/etc/waterwall-policy/settings.env"
ICMPTUNNEL_POLICY_STATE_FILE="/etc/icmptunnel-policy/settings.env"

case "${MODE}" in
  all|warp|dns) ;;
  *)
    echo "Invalid mode: ${MODE} (use all|warp|dns)" >&2
    exit 1
    ;;
esac

get_setting() {
  local file="$1"
  local key="$2"
  if [ -f "${file}" ]; then
    awk -F= -v k="${key}" '$1==k {print $2; exit}' "${file}" 2>/dev/null || true
  fi
}

ensure_warp_core_ready() {
  if [ ! -f /etc/wireguard/wgcf.conf ]; then
    return 1
  fi

  if [ -f /etc/iproute2/rt_tables ]; then
    if ! grep -qE "^[[:space:]]*${TABLE_ID}[[:space:]]+wgcf$" /etc/iproute2/rt_tables; then
      echo "${TABLE_ID} wgcf" >> /etc/iproute2/rt_tables
    fi
  fi

  if ! ip link show wgcf >/dev/null 2>&1; then
    wg-quick up wgcf >/dev/null 2>&1 || true
  fi
  ip route add default dev wgcf table ${TABLE_ID} 2>/dev/null || true
  ip link show wgcf >/dev/null 2>&1
}

ensure_dns_core_ready() {
  if [ ! -f /etc/dnsmasq.d/paqet-dns-policy.conf ]; then
    return 1
  fi
  systemctl enable --now dnsmasq >/dev/null 2>&1 || true
  systemctl restart dnsmasq >/dev/null 2>&1 || true
  systemctl is-active --quiet dnsmasq 2>/dev/null
}

reconcile_warp() {
  local server_enabled=""
  local ssh_enabled=""
  local waterwall_enabled=""
  local icmptunnel_enabled=""

  server_enabled="$(get_setting "${SERVER_POLICY_STATE_FILE}" "server_warp_enabled")"
  ssh_enabled="$(get_setting "${SSH_PROXY_SETTINGS_FILE}" "warp_enabled")"
  waterwall_enabled="$(get_setting "${WATERWALL_POLICY_STATE_FILE}" "waterwall_warp_enabled")"
  icmptunnel_enabled="$(get_setting "${ICMPTUNNEL_POLICY_STATE_FILE}" "icmptunnel_warp_enabled")"

  if [ -z "${server_enabled}" ]; then
    if [ -f /etc/systemd/system/paqet-server.service.d/10-warp.conf ]; then
      server_enabled="1"
    elif id -u paqet >/dev/null 2>&1; then
      p_uid="$(id -u paqet)"
      if ip rule show | grep -Eq "uidrange ${p_uid}-${p_uid}.*lookup (${TABLE_ID}|wgcf)"; then
        server_enabled="1"
      fi
    fi
  fi

  if [ -z "${waterwall_enabled}" ]; then
    if [ -f /etc/systemd/system/waterwall-direct-server.service.d/10-warp.conf ]; then
      waterwall_enabled="1"
    elif id -u waterwall >/dev/null 2>&1; then
      w_uid="$(id -u waterwall)"
      if ip rule show | grep -Eq "uidrange ${w_uid}-${w_uid}.*lookup (${TABLE_ID}|wgcf)"; then
        waterwall_enabled="1"
      fi
    fi
  fi

  if [ -z "${icmptunnel_enabled}" ]; then
    if [ -f /etc/systemd/system/icmptunnel-server.service.d/10-warp.conf ] || [ -f /etc/systemd/system/icmptunnel-client.service.d/10-warp.conf ]; then
      icmptunnel_enabled="1"
    elif id -u icmptunnel >/dev/null 2>&1; then
      i_uid="$(id -u icmptunnel)"
      if ip rule show | grep -Eq "uidrange ${i_uid}-${i_uid}.*lookup (${TABLE_ID}|wgcf)"; then
        icmptunnel_enabled="1"
      fi
    fi
  fi

  if ! ensure_warp_core_ready; then
    echo "WARP core is not ready. Skipping WARP binding reconciliation."
    return 0
  fi

  if [ "${server_enabled}" = "1" ] && [ -x "${SCRIPT_DIR}/enable_warp_policy.sh" ]; then
    "${SCRIPT_DIR}/enable_warp_policy.sh" server >/dev/null 2>&1 || true
    echo "Re-applied WARP binding for paqet-server."
  fi

  if [ "${ssh_enabled}" = "1" ] && [ -x "${SCRIPT_DIR}/ssh_proxy_enable_warp.sh" ]; then
    "${SCRIPT_DIR}/ssh_proxy_enable_warp.sh" >/dev/null 2>&1 || true
    echo "Re-applied WARP binding for SSH proxy users."
  fi

  if [ "${waterwall_enabled}" = "1" ] && [ -x "${SCRIPT_DIR}/waterwall_enable_warp_policy.sh" ]; then
    "${SCRIPT_DIR}/waterwall_enable_warp_policy.sh" server >/dev/null 2>&1 || true
    echo "Re-applied WARP binding for waterwall-direct-server."
  fi

  if [ "${icmptunnel_enabled}" = "1" ] && [ -x "${SCRIPT_DIR}/icmptunnel_enable_warp_policy.sh" ]; then
    "${SCRIPT_DIR}/icmptunnel_enable_warp_policy.sh" server >/dev/null 2>&1 || true
    echo "Re-applied WARP binding for icmptunnel."
  fi
}

reconcile_dns() {
  local server_enabled=""
  local ssh_enabled=""
  local waterwall_enabled=""
  local icmptunnel_enabled=""

  server_enabled="$(get_setting "${SERVER_POLICY_STATE_FILE}" "server_dns_enabled")"
  ssh_enabled="$(get_setting "${SSH_PROXY_SETTINGS_FILE}" "dns_enabled")"
  waterwall_enabled="$(get_setting "${WATERWALL_POLICY_STATE_FILE}" "waterwall_dns_enabled")"
  icmptunnel_enabled="$(get_setting "${ICMPTUNNEL_POLICY_STATE_FILE}" "icmptunnel_dns_enabled")"

  if [ -z "${server_enabled}" ]; then
    if iptables -t nat -S OUTPUT 2>/dev/null | grep -q "paqet-dns-policy"; then
      server_enabled="1"
    fi
  fi

  if [ -z "${waterwall_enabled}" ]; then
    if iptables -t nat -S OUTPUT 2>/dev/null | grep -q "waterwall-dns-policy"; then
      waterwall_enabled="1"
    fi
  fi

  if [ -z "${icmptunnel_enabled}" ]; then
    if id -u icmptunnel >/dev/null 2>&1; then
      i_uid="$(id -u icmptunnel)"
      if iptables -t nat -S OUTPUT 2>/dev/null | grep -q "owner-uid-match ${i_uid}"; then
        icmptunnel_enabled="1"
      fi
    fi
  fi

  if ! ensure_dns_core_ready; then
    echo "DNS core is not ready. Skipping DNS binding reconciliation."
    return 0
  fi

  if [ "${server_enabled}" = "1" ] && [ -x "${SCRIPT_DIR}/enable_dns_policy.sh" ]; then
    "${SCRIPT_DIR}/enable_dns_policy.sh" >/dev/null 2>&1 || true
    echo "Re-applied DNS binding for paqet-server."
  fi

  if [ "${ssh_enabled}" = "1" ] && [ -x "${SCRIPT_DIR}/ssh_proxy_enable_dns_routing.sh" ]; then
    "${SCRIPT_DIR}/ssh_proxy_enable_dns_routing.sh" >/dev/null 2>&1 || true
    echo "Re-applied DNS binding for SSH proxy users."
  fi

  if [ "${waterwall_enabled}" = "1" ] && [ -x "${SCRIPT_DIR}/waterwall_enable_dns_policy.sh" ]; then
    "${SCRIPT_DIR}/waterwall_enable_dns_policy.sh" >/dev/null 2>&1 || true
    echo "Re-applied DNS binding for waterwall-direct-server."
  fi

  if [ "${icmptunnel_enabled}" = "1" ] && [ -x "${SCRIPT_DIR}/icmptunnel_enable_dns_policy.sh" ]; then
    "${SCRIPT_DIR}/icmptunnel_enable_dns_policy.sh" >/dev/null 2>&1 || true
    echo "Re-applied DNS binding for icmptunnel."
  fi
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if [ "${MODE}" = "all" ] || [ "${MODE}" = "warp" ]; then
  reconcile_warp
fi
if [ "${MODE}" = "all" ] || [ "${MODE}" = "dns" ]; then
  reconcile_dns
fi

echo "Policy binding reconciliation completed (${MODE})."
