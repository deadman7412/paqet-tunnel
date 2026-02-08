#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

is_valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{2,31}$ ]]
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

create_proxy_user() {
  local username="$1"
  local proxy_port="$2"
  local pubkey="$3"
  local private_key_file="$4"
  local public_key_file="$5"
  local home_dir="/home/${username}"
  local ssh_dir="${home_dir}/.ssh"
  local auth_keys="${ssh_dir}/authorized_keys"
  local meta_file="${SSH_PROXY_USERS_DIR}/${username}.env"
  local meta_json_file="${SSH_PROXY_USERS_DIR}/${username}.json"

  if id -u "${username}" >/dev/null 2>&1; then
    echo "User already exists: ${username}" >&2
    return 1
  fi

  useradd -m -s /bin/bash "${username}"
  passwd -l "${username}" >/dev/null 2>&1 || true

  mkdir -p "${ssh_dir}" "${SSH_PROXY_USERS_DIR}" "${SSH_PROXY_STATE_DIR}"
  touch "${auth_keys}"
  chmod 700 "${ssh_dir}"
  chmod 600 "${auth_keys}"
  chown -R "${username}:${username}" "${ssh_dir}"

  printf '%s\n' "${pubkey}" >> "${auth_keys}"

  cat > "${meta_file}" <<META
username=${username}
proxy_port=${proxy_port}
private_key_file=${private_key_file}
public_key_file=${public_key_file}
created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
META
  chmod 600 "${meta_file}"

  cat > "${meta_json_file}" <<JSON
{
  "username": "${username}",
  "proxy_port": ${proxy_port},
  "private_key_file": "${private_key_file}",
  "public_key_file": "${public_key_file}",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
JSON
  chmod 600 "${meta_json_file}"

  echo "Created SSH proxy user: ${username}"
  echo "Assigned SSH proxy port: ${proxy_port}"
}

generate_user_keypair() {
  local username="$1"
  local user_client_dir="${SSH_PROXY_STATE_DIR}/clients/${username}"
  local private_key_file="${user_client_dir}/id_ed25519"
  local public_key_file="${private_key_file}.pub"
  local comment="paqet-ssh-proxy-${username}"

  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "ssh-keygen is not available. Install OpenSSH client tools first." >&2
    return 1
  fi

  mkdir -p "${user_client_dir}"
  chmod 700 "${user_client_dir}"

  if [ -f "${private_key_file}" ] || [ -f "${public_key_file}" ]; then
    echo "Key files already exist for ${username}: ${private_key_file}" >&2
    echo "Remove old files or choose another username." >&2
    return 1
  fi

  ssh-keygen -t ed25519 -N "" -f "${private_key_file}" -C "${comment}" >/dev/null
  chmod 600 "${private_key_file}" "${public_key_file}"

  echo "${private_key_file}|${public_key_file}"
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

main() {
  local username=""
  local proxy_port=""
  local key_files=""
  local private_key_file=""
  local public_key_file=""
  local pubkey=""
  local server_ip=""

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

  key_files="$(generate_user_keypair "${username}")"
  if [ -z "${key_files}" ]; then
    echo "Failed to generate user keypair." >&2
    exit 1
  fi
  private_key_file="${key_files%%|*}"
  public_key_file="${key_files##*|}"
  pubkey="$(cat "${public_key_file}")"

  create_proxy_user "${username}" "${proxy_port}" "${pubkey}" "${private_key_file}" "${public_key_file}"
  server_ip="$(read_default_server_ip)"

  echo
  echo "Generated key files:"
  echo "  Private key: ${private_key_file}"
  echo "  Public key:  ${public_key_file}"
  echo
  echo "Connection example:"
  echo "  ssh -N -D 127.0.0.1:1081 ${username}@${server_ip} -p ${proxy_port}"
}

main "$@"
