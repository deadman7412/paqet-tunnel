#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
SSH_PROXY_STATE_DIR="/etc/paqet-ssh-proxy"
SSH_PROXY_USERS_DIR="${SSH_PROXY_STATE_DIR}/users"
SSH_PROXY_GROUP="paqet-ssh-proxy"
SSH_PROXY_PORT_CONF="/etc/ssh/sshd_config.d/paqet-ssh-proxy.conf"
SSH_PROXY_POLICY_CONF="/etc/ssh/sshd_config.d/paqet-ssh-proxy-users.conf"
SERVER_POLICY_STATE_DIR="/etc/paqet-policy"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

confirm() {
  local prompt="$1"
  local ans=""
  read -r -p "${prompt} [y/N]: " ans
  case "${ans}" in
    y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

run_if_exec() {
  local script="$1"
  shift || true
  if [ -x "${script}" ]; then
    "${script}" "$@" >/dev/null 2>&1 || true
  fi
}

is_warp_core_installed() {
  [ -f /etc/wireguard/wgcf.conf ] || [ -x /usr/local/bin/wgcf ] || [ -d /root/wgcf ]
}

is_dns_core_installed() {
  [ -f /etc/dnsmasq.d/paqet-dns-policy.conf ] || [ -f /etc/dnsmasq.d/paqet-dns-policy-blocklist.conf ] || [ -d /etc/paqet-dns-policy ]
}

count_ssh_proxy_users() {
  local count=0
  if [ -d "${SSH_PROXY_USERS_DIR}" ]; then
    count="$(find "${SSH_PROXY_USERS_DIR}" -maxdepth 1 -type f -name '*.env' 2>/dev/null | wc -l | tr -d ' ')"
  fi
  echo "${count}"
}

service_present() {
  local svc="$1"
  systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"
}

service_active() {
  local svc="$1"
  systemctl is-active --quiet "${svc}.service" 2>/dev/null
}

show_precheck_summary() {
  local ssh_users=""

  ssh_users="$(count_ssh_proxy_users)"

  echo
  echo "Current state summary"
  echo "---------------------"
  if service_present paqet-server; then
    if service_active paqet-server; then
      echo "- paqet-server.service: installed, active"
    else
      echo "- paqet-server.service: installed, inactive"
    fi
  else
    echo "- paqet-server.service: not installed"
  fi

  if service_present paqet-client; then
    if service_active paqet-client; then
      echo "- paqet-client.service: installed, active"
    else
      echo "- paqet-client.service: installed, inactive"
    fi
  else
    echo "- paqet-client.service: not installed"
  fi

  if is_warp_core_installed; then
    echo "- WARP core: installed"
  else
    echo "- WARP core: not installed"
  fi

  if is_dns_core_installed; then
    echo "- DNS core: installed"
  else
    echo "- DNS core: not installed"
  fi

  if [ -d "${SSH_PROXY_STATE_DIR}" ] || [ -f "${SSH_PROXY_PORT_CONF}" ] || [ -f "${SSH_PROXY_POLICY_CONF}" ]; then
    echo "- SSH proxy: configured"
  else
    echo "- SSH proxy: not configured"
  fi
  echo "- SSH proxy users: ${ssh_users}"
  echo
}

cleanup_paqet_services() {
  for svc in paqet-server paqet-client; do
    systemctl stop "${svc}.service" 2>/dev/null || true
    systemctl disable "${svc}.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/${svc}.service"
  done
  systemctl daemon-reload 2>/dev/null || true
}

cleanup_paqet_cron() {
  rm -f /etc/cron.d/paqet-restart-paqet-server
  rm -f /etc/cron.d/paqet-restart-paqet-client
}

cleanup_paqet_ufw_rules() {
  local -a ufw_rules=()

  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi
  if ! ufw status 2>/dev/null | head -n1 | grep -qiE "Status: (active|inactive)"; then
    return 0
  fi

  mapfile -t ufw_rules < <(ufw status numbered 2>/dev/null | awk '/paqet-(tunnel|loopback)/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
  if [ "${#ufw_rules[@]}" -gt 0 ]; then
    for ((i=${#ufw_rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${ufw_rules[$i]}" >/dev/null 2>&1 || true
    done
  fi
}

disable_server_bindings() {
  run_if_exec "${SCRIPT_DIR}/disable_warp_policy.sh" server
  run_if_exec "${SCRIPT_DIR}/disable_dns_policy.sh"
}

disable_ssh_bindings() {
  run_if_exec "${SCRIPT_DIR}/ssh_proxy_disable_warp.sh"
  run_if_exec "${SCRIPT_DIR}/ssh_proxy_disable_dns_routing.sh"
}

remove_paqet_only() {
  echo "Removing paqet (services/config/runtime files) ..."

  disable_server_bindings
  cleanup_paqet_services
  cleanup_paqet_cron
  cleanup_paqet_ufw_rules

  rm -rf "${PAQET_DIR}"
  rm -rf /opt/paqet 2>/dev/null || true

  echo "Paqet-only uninstall completed."
}

remove_warp_core_only() {
  echo "Removing WARP core ..."
  echo "Auto-unbinding WARP from server and SSH proxy users first."

  disable_server_bindings
  disable_ssh_bindings
  run_if_exec "${SCRIPT_DIR}/warp_core_uninstall.sh"

  echo "WARP core uninstall completed."
}

remove_dns_core_only() {
  echo "Removing DNS core ..."
  echo "Auto-unbinding DNS routing from server and SSH proxy users first."

  run_if_exec "${SCRIPT_DIR}/disable_dns_policy.sh"
  run_if_exec "${SCRIPT_DIR}/ssh_proxy_disable_dns_routing.sh"
  run_if_exec "${SCRIPT_DIR}/dns_policy_core_uninstall.sh"

  echo "DNS core uninstall completed."
}

reload_sshd() {
  if ! command -v sshd >/dev/null 2>&1; then
    return 0
  fi

  if ! sshd -t >/dev/null 2>&1; then
    echo "Warning: sshd config validation failed; SSH reload skipped." >&2
    return 1
  fi

  if systemctl restart ssh >/dev/null 2>&1; then
    return 0
  fi
  if systemctl restart sshd >/dev/null 2>&1; then
    return 0
  fi
  if command -v service >/dev/null 2>&1; then
    service ssh restart >/dev/null 2>&1 || service sshd restart >/dev/null 2>&1 || true
  fi
}

remove_ssh_proxy_firewall() {
  local -a rules=()

  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi
  if ! ufw status 2>/dev/null | head -n1 | grep -q "Status: active"; then
    return 0
  fi

  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk '/paqet-ssh-proxy/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
  if [ "${#rules[@]}" -gt 0 ]; then
    for ((i=${#rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
    done
  fi
}

list_proxy_usernames() {
  {
    awk -F= '/^username=/{print $2}' "${SSH_PROXY_USERS_DIR}"/*.env 2>/dev/null || true
    getent group "${SSH_PROXY_GROUP}" 2>/dev/null | awk -F: '{print $4}' | tr ',' '\n' 2>/dev/null || true
  } | awk 'NF' | sort -u
}

remove_ssh_proxy_only_keep_users() {
  echo "Removing SSH proxy infrastructure (keeping Linux users) ..."

  disable_ssh_bindings
  remove_ssh_proxy_firewall

  rm -f "${SSH_PROXY_PORT_CONF}"
  rm -f "${SSH_PROXY_POLICY_CONF}"

  reload_sshd || true

  rm -f "${SSH_PROXY_STATE_DIR}/settings.env" 2>/dev/null || true

  echo "SSH proxy removed. Linux users were kept."
}

remove_ssh_proxy_and_users() {
  local user=""
  local uid=""

  echo "Removing SSH proxy infrastructure and SSH proxy users ..."

  disable_ssh_bindings
  remove_ssh_proxy_firewall

  while IFS= read -r user; do
    [ -z "${user}" ] && continue
    if ! id -u "${user}" >/dev/null 2>&1; then
      continue
    fi

    uid="$(id -u "${user}")"
    pkill -KILL -u "${uid}" >/dev/null 2>&1 || true
    sleep 1

    userdel -r -f "${user}" >/dev/null 2>&1 || userdel -r "${user}" >/dev/null 2>&1 || userdel -f "${user}" >/dev/null 2>&1 || userdel "${user}" >/dev/null 2>&1 || true
  done < <(list_proxy_usernames)

  rm -f "${SSH_PROXY_PORT_CONF}"
  rm -f "${SSH_PROXY_POLICY_CONF}"
  rm -rf "${SSH_PROXY_STATE_DIR}"

  if getent group "${SSH_PROXY_GROUP}" >/dev/null 2>&1; then
    groupdel "${SSH_PROXY_GROUP}" >/dev/null 2>&1 || true
  fi

  reload_sshd || true

  echo "SSH proxy and its users removed."
}

full_uninstall_everything() {
  echo "Running full uninstall ..."

  remove_ssh_proxy_and_users
  remove_dns_core_only
  remove_warp_core_only
  remove_paqet_only

  rm -rf "${SERVER_POLICY_STATE_DIR}" 2>/dev/null || true

  echo "Full uninstall completed."
}

show_menu() {
  echo "Uninstall Options"
  echo "-----------------"
  echo "1) Remove paqet only"
  echo "2) Remove WARP core only"
  echo "3) Remove DNS core only"
  echo "4) Remove SSH proxy only (keep Linux users)"
  echo "5) Remove SSH proxy + all SSH proxy users"
  echo "6) Full uninstall (everything)"
  echo "0) Cancel"
}

main() {
  local choice=""

  show_precheck_summary
  show_menu
  read -r -p "Select an option: " choice

  case "${choice}" in
    1)
      confirm "Proceed with paqet-only uninstall?" || { echo "Aborted."; exit 0; }
      remove_paqet_only
      ;;
    2)
      confirm "Proceed with WARP core uninstall?" || { echo "Aborted."; exit 0; }
      remove_warp_core_only
      ;;
    3)
      confirm "Proceed with DNS core uninstall?" || { echo "Aborted."; exit 0; }
      remove_dns_core_only
      ;;
    4)
      confirm "Proceed with SSH proxy uninstall while keeping Linux users?" || { echo "Aborted."; exit 0; }
      remove_ssh_proxy_only_keep_users
      ;;
    5)
      confirm "Proceed with SSH proxy uninstall and remove all SSH proxy users?" || { echo "Aborted."; exit 0; }
      remove_ssh_proxy_and_users
      ;;
    6)
      confirm "Proceed with FULL uninstall (everything)?" || { echo "Aborted."; exit 0; }
      full_uninstall_everything
      if confirm "Reboot now?"; then
        reboot
      fi
      ;;
    0)
      echo "Cancelled."
      exit 0
      ;;
    *)
      echo "Invalid option: ${choice}" >&2
      exit 1
      ;;
  esac
}

main "$@"
