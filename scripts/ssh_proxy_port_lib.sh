#!/usr/bin/env bash

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
SSH_PROXY_STATE_DIR="${SSH_PROXY_STATE_DIR:-/etc/paqet-ssh-proxy}"
SSH_PROXY_USERS_DIR="${SSH_PROXY_STATE_DIR}/users"
SSH_PROXY_SETTINGS_FILE="${SSH_PROXY_STATE_DIR}/settings.env"
SSH_PROXY_PORT_CONF="/etc/ssh/sshd_config.d/paqet-ssh-proxy.conf"

ssh_proxy_require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

ssh_proxy_is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

ssh_proxy_get_configured_port() {
  if [ -f "${SSH_PROXY_SETTINGS_FILE}" ]; then
    awk -F= '/^proxy_port=/{print $2; exit}' "${SSH_PROXY_SETTINGS_FILE}" 2>/dev/null || true
  fi
}

ssh_proxy_list_usernames() {
  local meta_file=""
  local username=""

  if [ ! -d "${SSH_PROXY_USERS_DIR}" ]; then
    return 0
  fi

  for meta_file in "${SSH_PROXY_USERS_DIR}"/*.env; do
    if [ ! -f "${meta_file}" ]; then
      continue
    fi
    username="$(awk -F= '/^username=/{print $2; exit}' "${meta_file}" 2>/dev/null || true)"
    if [ -n "${username}" ]; then
      echo "${username}"
    fi
  done
}

ssh_proxy_save_configured_port() {
  local port="$1"

  mkdir -p "${SSH_PROXY_STATE_DIR}" "${SSH_PROXY_USERS_DIR}"
  cat > "${SSH_PROXY_SETTINGS_FILE}" <<CONF
proxy_port=${port}
updated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CONF
  chmod 600 "${SSH_PROXY_SETTINGS_FILE}"
}

ssh_proxy_get_all_ssh_ports() {
  local ports=""
  ports="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -un | xargs 2>/dev/null || true)"
  if [ -z "${ports}" ]; then
    ports="22"
  fi
  echo "${ports}"
}

ssh_proxy_get_paqet_port() {
  local cfg="${PAQET_DIR}/server.yaml"
  local port=""

  if [ -f "${cfg}" ]; then
    port="$(awk '
      $1 == "listen:" { inlisten=1; next }
      inlisten && $1 == "addr:" {
        gsub(/"/, "", $2);
        if ($2 ~ /:/) { sub(/^.*:/, "", $2); }
        print $2; exit
      }
    ' "${cfg}")"
  fi

  echo "${port}"
}

ssh_proxy_is_port_in_use() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)${port}$"
  else
    return 1
  fi
}

ssh_proxy_is_reserved_or_standard_port() {
  local port="$1"

  case "${port}" in
    20|21|22|23|25|53|67|68|69|80|110|123|143|161|389|443|465|587|636|873|993|995|1194|3306|3389|5432|6379|8080|8443)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ssh_proxy_port_in_list() {
  local port="$1"
  local ports="$2"

  echo " ${ports} " | grep -q " ${port} "
}

ssh_proxy_validate_port() {
  local port="$1"
  local paqet_port="$2"
  local ssh_ports="$3"
  local current_port="${4:-}"

  if ! ssh_proxy_is_number "${port}"; then
    echo "Port must be numeric." >&2
    return 1
  fi

  if [ "${port}" -lt 1025 ] || [ "${port}" -gt 65535 ]; then
    echo "Use a high non-standard port (1025-65535)." >&2
    return 1
  fi

  if ssh_proxy_is_reserved_or_standard_port "${port}"; then
    echo "Port ${port} is reserved/standard. Choose another." >&2
    return 1
  fi

  if [ -n "${paqet_port}" ] && [ "${port}" = "${paqet_port}" ]; then
    echo "Port ${port} conflicts with paqet listen_port." >&2
    return 1
  fi

  if [ -n "${current_port}" ] && [ "${port}" = "${current_port}" ]; then
    return 0
  fi

  if ssh_proxy_port_in_list "${port}" "${ssh_ports}"; then
    echo "Port ${port} is already configured in SSH." >&2
    return 1
  fi

  if ssh_proxy_is_port_in_use "${port}"; then
    echo "Port ${port} is already in use." >&2
    return 1
  fi

  return 0
}

ssh_proxy_random_port() {
  local paqet_port="$1"
  local ssh_ports="$2"
  local current_port="${3:-}"
  local port=""
  local try=0

  while [ "${try}" -lt 300 ]; do
    port="$(shuf -i 20000-60000 -n 1 2>/dev/null || awk 'BEGIN{srand(); print int(20000+rand()*40001)}')"
    try=$((try + 1))

    if ssh_proxy_is_reserved_or_standard_port "${port}"; then
      continue
    fi
    if [ -n "${paqet_port}" ] && [ "${port}" = "${paqet_port}" ]; then
      continue
    fi
    if [ -n "${current_port}" ] && [ "${port}" = "${current_port}" ]; then
      continue
    fi
    if ssh_proxy_port_in_list "${port}" "${ssh_ports}"; then
      continue
    fi
    if ssh_proxy_is_port_in_use "${port}"; then
      continue
    fi

    echo "${port}"
    return 0
  done

  echo "Could not find a free random high port." >&2
  return 1
}

ssh_proxy_write_port_conf() {
  local port="$1"

  mkdir -p "$(dirname "${SSH_PROXY_PORT_CONF}")"

  cat > "${SSH_PROXY_PORT_CONF}" <<CONF
# Managed by paqet SSH proxy
Port ${port}
CONF
}

ssh_proxy_reload_service() {
  if systemctl is-active --quiet ssh 2>/dev/null; then
    systemctl reload ssh
    return 0
  fi

  if systemctl is-active --quiet sshd 2>/dev/null; then
    systemctl reload sshd
    return 0
  fi

  echo "Warning: ssh/sshd service not active; config updated but service not reloaded." >&2
  return 0
}

ssh_proxy_wait_for_port_listen() {
  local port="$1"
  local try=0

  if ! command -v ss >/dev/null 2>&1; then
    return 0
  fi

  while [ "${try}" -lt 10 ]; do
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)${port}$"; then
      return 0
    fi
    sleep 1
    try=$((try + 1))
  done

  return 1
}

ssh_proxy_remove_ufw_port_if_active() {
  local port="$1"
  local -a rules=()

  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi

  if ! ufw status 2>/dev/null | head -n1 | grep -q "Status: active"; then
    return 0
  fi

  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk -v p="${port}/tcp" '/paqet-ssh-proxy/ && $0 ~ p { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
  if [ "${#rules[@]}" -eq 0 ]; then
    return 0
  fi

  for ((i=${#rules[@]}-1; i>=0; i--)); do
    ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
  done
}

ssh_proxy_ensure_ufw_port_if_active() {
  local port="$1"

  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi

  if ! ufw status 2>/dev/null | head -n1 | grep -q "Status: active"; then
    return 0
  fi

  if ! ufw status 2>/dev/null | grep -qE "\b${port}/tcp\b.*ALLOW IN"; then
    ufw allow "${port}/tcp" comment 'paqet-ssh-proxy' >/dev/null 2>&1 || true
  fi
}

ssh_proxy_apply_port() {
  local new_port="$1"
  local old_port="${2:-}"
  local backup=""

  if [ -f "${SSH_PROXY_PORT_CONF}" ]; then
    backup="${SSH_PROXY_PORT_CONF}.bak.$(date -u +%Y%m%d-%H%M%S)"
    cp -f "${SSH_PROXY_PORT_CONF}" "${backup}"
  fi

  ssh_proxy_write_port_conf "${new_port}"

  if ! sshd -t >/dev/null 2>&1; then
    echo "sshd config test failed. Rolling back." >&2
    if [ -n "${backup}" ] && [ -f "${backup}" ]; then
      cp -f "${backup}" "${SSH_PROXY_PORT_CONF}"
    else
      rm -f "${SSH_PROXY_PORT_CONF}"
    fi
    return 1
  fi

  if ! ssh_proxy_reload_service; then
    echo "Failed to reload ssh service. Rolling back." >&2
    if [ -n "${backup}" ] && [ -f "${backup}" ]; then
      cp -f "${backup}" "${SSH_PROXY_PORT_CONF}"
    else
      rm -f "${SSH_PROXY_PORT_CONF}"
    fi
    sshd -t >/dev/null 2>&1 || true
    ssh_proxy_reload_service >/dev/null 2>&1 || true
    return 1
  fi

  if ! ssh_proxy_wait_for_port_listen "${new_port}"; then
    echo "SSH is not listening on ${new_port} after reload. Rolling back." >&2
    if [ -n "${backup}" ] && [ -f "${backup}" ]; then
      cp -f "${backup}" "${SSH_PROXY_PORT_CONF}"
    else
      rm -f "${SSH_PROXY_PORT_CONF}"
    fi
    sshd -t >/dev/null 2>&1 || true
    ssh_proxy_reload_service >/dev/null 2>&1 || true
    return 1
  fi

  ssh_proxy_ensure_ufw_port_if_active "${new_port}"
  if [ -n "${old_port}" ] && [ "${old_port}" != "${new_port}" ]; then
    ssh_proxy_remove_ufw_port_if_active "${old_port}"
  fi

  ssh_proxy_save_configured_port "${new_port}"
  return 0
}
