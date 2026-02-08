#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

is_valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{2,31}$ ]]
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 18 | tr -d '\n' | tr '/+' 'AZ' | cut -c1-20
    return
  fi
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20
}

read_default_server_ip() {
  local info_file="${PAQET_DIR}/server_info.txt"
  local server_ip=""

  if [ -f "${info_file}" ]; then
    server_ip="$(awk -F= '/^server_public_ip=/{print $2; exit}' "${info_file}" 2>/dev/null || true)"
    if [ "${server_ip}" = "REPLACE_WITH_SERVER_PUBLIC_IP" ]; then
      server_ip=""
    fi
  fi

  if [ -z "${server_ip}" ] && command -v curl >/dev/null 2>&1; then
    server_ip="$(curl -fsS --connect-timeout 3 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  fi

  if [ -z "${server_ip}" ]; then
    server_ip="<SERVER_IP>"
  fi

  echo "${server_ip}"
}

ensure_port_once() {
  local current_port=""
  local paqet_port=""
  local ssh_ports=""
  local selected=""

  current_port="$(ssh_proxy_get_configured_port)"
  if [ -n "${current_port}" ]; then
    echo "Using configured SSH proxy port from settings DB: ${current_port}"
    return 0
  fi

  echo "No SSH proxy port configured yet. This is a one-time setup."
  paqet_port="$(ssh_proxy_get_paqet_port)"
  ssh_ports="$(ssh_proxy_get_all_ssh_ports)"

  if [ -n "${paqet_port}" ]; then
    echo "Detected paqet port: ${paqet_port}"
  fi
  echo "Detected SSH ports: ${ssh_ports}"

  read -r -p "Set SSH proxy port [random high port]: " selected
  if [ -z "${selected}" ]; then
    selected="$(ssh_proxy_random_port "${paqet_port}" "${ssh_ports}")"
    echo "Selected random SSH proxy port: ${selected}"
  else
    ssh_proxy_validate_port "${selected}" "${paqet_port}" "${ssh_ports}"
  fi

  ssh_proxy_apply_port "${selected}" ""
  echo "Saved SSH proxy port to settings DB: ${selected}"
}

create_proxy_user() {
  local username="$1"
  local proxy_port="$2"
  local password="$3"
  local nologin_shell="$4"
  local meta_file="${SSH_PROXY_USERS_DIR}/${username}.env"
  local meta_json_file="${SSH_PROXY_USERS_DIR}/${username}.json"

  if id -u "${username}" >/dev/null 2>&1; then
    echo "User already exists: ${username}" >&2
    return 1
  fi

  ssh_proxy_ensure_group
  useradd -m -s "${nologin_shell}" -g "${SSH_PROXY_GROUP}" "${username}"
  echo "${username}:${password}" | chpasswd

  mkdir -p "${SSH_PROXY_USERS_DIR}" "${SSH_PROXY_STATE_DIR}/clients/${username}"

  cat > "${meta_file}" <<META
username=${username}
proxy_port=${proxy_port}
auth_method=password
password=${password}
shell=${nologin_shell}
created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
META
  chmod 600 "${meta_file}"

  cat > "${meta_json_file}" <<JSON
{
  "username": "${username}",
  "proxy_port": ${proxy_port},
  "auth_method": "password",
  "password": "${password}",
  "shell": "${nologin_shell}",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
JSON
  chmod 600 "${meta_json_file}"

  echo "Created SSH proxy user: ${username}"
  echo "Assigned SSH proxy port: ${proxy_port}"
}

main() {
  local username=""
  local password=""
  local generated_password=""
  local proxy_port=""
  local server_ip=""
  local nologin_shell=""

  ssh_proxy_require_root

  ensure_port_once
  proxy_port="$(ssh_proxy_get_configured_port)"
  if [ -z "${proxy_port}" ]; then
    echo "SSH proxy port is not configured. Run ssh_proxy_manage_port.sh first." >&2
    exit 1
  fi

  read -r -p "Proxy username: " username
  if ! is_valid_username "${username}"; then
    echo "Invalid username. Use [a-z0-9_-], start with a letter/underscore, length 3-32." >&2
    exit 1
  fi

  read -r -s -p "Password (leave empty to auto-generate): " password
  echo
  if [ -z "${password}" ]; then
    generated_password="$(generate_password)"
    password="${generated_password}"
  fi

  nologin_shell="$(ssh_proxy_detect_nologin_shell)"
  ssh_proxy_ensure_sshd_user_policy
  if ! sshd -t >/dev/null 2>&1; then
    echo "sshd policy config is invalid. Aborting." >&2
    exit 1
  fi
  ssh_proxy_reload_service

  create_proxy_user "${username}" "${proxy_port}" "${password}" "${nologin_shell}"
  server_ip="$(read_default_server_ip)"

  echo
  echo "Credentials:"
  echo "Username: ${username}"
  echo "Password: ${password}"
  echo "Server IP: ${server_ip}"
  echo "Port: ${proxy_port}"
  echo
  echo "Note: user shell is '${nologin_shell}' (interactive SSH login disabled)."
  echo "Use tunnel/proxy mode from your client app with these credentials."
}

main "$@"
