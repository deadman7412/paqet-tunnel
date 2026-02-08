#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

is_valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{2,31}$ ]]
}

create_proxy_user() {
  local username="$1"
  local pubkey="$2"
  local proxy_port="$3"
  local home_dir="/home/${username}"
  local ssh_dir="${home_dir}/.ssh"
  local auth_keys="${ssh_dir}/authorized_keys"
  local meta_file="${SSH_PROXY_USERS_DIR}/${username}.env"

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
created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
META
  chmod 600 "${meta_file}"

  echo "Created SSH proxy user: ${username}"
  echo "Assigned SSH proxy port: ${proxy_port}"
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
  local pubkey=""
  local proxy_port=""

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

  read -r -p "User public key (ssh-ed25519/ssh-rsa ...): " pubkey
  if [ -z "${pubkey}" ]; then
    echo "Public key is required." >&2
    exit 1
  fi
  if ! echo "${pubkey}" | grep -qE '^ssh-(ed25519|rsa|ecdsa) '; then
    echo "Public key format looks invalid." >&2
    exit 1
  fi

  create_proxy_user "${username}" "${pubkey}" "${proxy_port}"

  echo
  echo "Connection example:"
  echo "  ssh -N -D 127.0.0.1:1081 ${username}@<SERVER_IP> -p ${proxy_port}"
}

main "$@"
