#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

read_server_ip() {
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

  echo "${server_ip}"
}

read_user_meta() {
  local username="$1"
  local key="$2"
  local env_file="${SSH_PROXY_USERS_DIR}/${username}.env"
  local json_file="${SSH_PROXY_USERS_DIR}/${username}.json"
  local val=""

  if [ -f "${json_file}" ]; then
    val="$(awk -v k="${key}" '
      $0 ~ "\"" k "\"" {
        line=$0
        sub(/^[^:]*:[[:space:]]*/, "", line)
        gsub(/[",]/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        print line
        exit
      }
    ' "${json_file}" 2>/dev/null || true)"
  fi

  if [ -z "${val}" ] && [ -f "${env_file}" ]; then
    val="$(awk -F= -v k="${key}" '$1==k {print $2; exit}' "${env_file}" 2>/dev/null || true)"
  fi

  echo "${val}"
}

resolve_key_path() {
  local username="$1"
  local key_path=""

  key_path="$(read_user_meta "${username}" "private_key_file")"
  if [ -n "${key_path}" ] && [ -f "${key_path}" ]; then
    echo "${key_path}"
    return 0
  fi

  if [ -f "${SSH_PROXY_STATE_DIR}/clients/${username}/id_ed25519" ]; then
    echo "${SSH_PROXY_STATE_DIR}/clients/${username}/id_ed25519"
    return 0
  fi

  if [ -f "${SSH_PROXY_STATE_DIR}/clients/${username}/id_rsa_singbox" ]; then
    echo "${SSH_PROXY_STATE_DIR}/clients/${username}/id_rsa_singbox"
    return 0
  fi

  return 1
}

main() {
  local username=""
  local server_ip=""
  local port=""
  local key_path=""
  local out_dir=""
  local out_file=""

  ssh_proxy_require_root

  read -r -p "Proxy username: " username
  if [ -z "${username}" ]; then
    echo "Username is required." >&2
    exit 1
  fi

  if ! id -u "${username}" >/dev/null 2>&1 && [ ! -f "${SSH_PROXY_USERS_DIR}/${username}.env" ] && [ ! -f "${SSH_PROXY_USERS_DIR}/${username}.json" ]; then
    echo "Unknown SSH proxy user: ${username}" >&2
    exit 1
  fi

  server_ip="$(read_server_ip)"
  if [ -z "${server_ip}" ]; then
    echo "Could not determine server IP. Set server_public_ip in ${PAQET_DIR}/server_info.txt." >&2
    exit 1
  fi

  port="$(read_user_meta "${username}" "proxy_port")"
  if [ -z "${port}" ]; then
    port="$(ssh_proxy_get_configured_port)"
  fi
  if [ -z "${port}" ]; then
    echo "SSH proxy port is not configured." >&2
    exit 1
  fi

  if ! key_path="$(resolve_key_path "${username}")"; then
    echo "Private key file not found for ${username}." >&2
    exit 1
  fi

  out_dir="${SSH_PROXY_STATE_DIR}/clients/${username}"
  out_file="${out_dir}/ssh-simple.txt"
  mkdir -p "${out_dir}"

  cat > "${out_file}" <<TXT
SSH Proxy Simple Credentials
============================
username: ${username}
server_ip: ${server_ip}
server_port: ${port}
private_key_file: ${key_path}

SSH SOCKS command (desktop):
ssh -N -D 127.0.0.1:1080 -i ${key_path} -p ${port} ${username}@${server_ip} -o IdentitiesOnly=yes

SSH local-forward test:
ssh -N -L 18080:example.com:80 -i ${key_path} -p ${port} ${username}@${server_ip} -o IdentitiesOnly=yes

Notes:
- Enable these menu options for server-side routing policy:
  - Enable WARP on SSH
  - Enable server DNS routing on SSH
- Keep private key secret.
TXT
  chmod 600 "${out_file}"

  echo "Generated: ${out_file}"
  echo
  echo "Username: ${username}"
  echo "Server IP: ${server_ip}"
  echo "Port: ${port}"
  echo "Private key: ${key_path}"
  echo
  echo "Quick connect command:"
  echo "ssh -N -D 127.0.0.1:1080 -i ${key_path} -p ${port} ${username}@${server_ip} -o IdentitiesOnly=yes"
}

main "$@"
