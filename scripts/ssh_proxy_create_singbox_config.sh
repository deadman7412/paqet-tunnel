#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

CLIENTS_DIR="${SSH_PROXY_STATE_DIR}/clients"

url_encode() {
  local s="$1"
  local i ch out=""
  for ((i=0; i<${#s}; i++)); do
    ch="${s:i:1}"
    case "${ch}" in
      [a-zA-Z0-9.~_-]) out+="${ch}" ;;
      *) printf -v out '%s%%%02X' "${out}" "'${ch}" ;;
    esac
  done
  echo "${out}"
}

ensure_qrencode() {
  if command -v qrencode >/dev/null 2>&1; then
    return 0
  fi

  echo "qrencode not found. Installing..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y qrencode
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y qrencode
  elif command -v yum >/dev/null 2>&1; then
    yum install -y qrencode
  else
    echo "No supported package manager found to install qrencode." >&2
    return 1
  fi

  command -v qrencode >/dev/null 2>&1
}

show_terminal_qr_from_config() {
  local config_file="$1"
  local payload=""

  if ! ensure_qrencode; then
    echo "Could not install qrencode; skipping terminal QR." >&2
    return 0
  fi

  if command -v jq >/dev/null 2>&1; then
    payload="$(jq -c . "${config_file}" 2>/dev/null || true)"
  fi
  if [ -z "${payload}" ]; then
    payload="$(tr -d '\n\r\t' < "${config_file}" 2>/dev/null || true)"
  fi

  if [ -z "${payload}" ]; then
    echo "Could not read config content for QR output." >&2
    return 1
  fi

  echo
  echo "Terminal QR (config payload):"
  if ! qrencode -t UTF8 -l L -m 0 "${payload}"; then
    echo "Config is too large for a single QR payload."
    echo "Use file import (sing-box.json) or remote profile URL mode."
  fi
}

read_default_server() {
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

ensure_user_exists() {
  local username="$1"
  local meta_file="${SSH_PROXY_USERS_DIR}/${username}.env"
  local meta_json_file="${SSH_PROXY_USERS_DIR}/${username}.json"

  if [ ! -f "${meta_file}" ] && [ ! -f "${meta_json_file}" ] && ! id -u "${username}" >/dev/null 2>&1; then
    echo "Unknown SSH proxy user: ${username}" >&2
    return 1
  fi

  return 0
}

read_user_json_field() {
  local username="$1"
  local field="$2"
  local meta_json_file="${SSH_PROXY_USERS_DIR}/${username}.json"

  if [ ! -f "${meta_json_file}" ]; then
    return 0
  fi

  awk -v k="${field}" '
    $0 ~ "\"" k "\"" {
      line=$0
      sub(/^[^:]*:[[:space:]]*/, "", line)
      gsub(/[",]/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      print line
      exit
    }
  ' "${meta_json_file}" 2>/dev/null || true
}

read_user_port() {
  local username="$1"
  local meta_file="${SSH_PROXY_USERS_DIR}/${username}.env"
  local user_port=""

  user_port="$(read_user_json_field "${username}" "proxy_port")"
  if [ -f "${meta_file}" ]; then
    user_port="${user_port:-$(awk -F= '/^proxy_port=/{print $2; exit}' "${meta_file}" 2>/dev/null || true)}"
  fi

  if [ -z "${user_port}" ]; then
    user_port="$(ssh_proxy_get_configured_port)"
  fi

  echo "${user_port}"
}

read_user_private_key_default() {
  local username="$1"
  local meta_file="${SSH_PROXY_USERS_DIR}/${username}.env"
  local key_path=""

  key_path="$(read_user_json_field "${username}" "private_key_file")"
  if [ -z "${key_path}" ] && [ -f "${meta_file}" ]; then
    key_path="$(awk -F= '/^private_key_file=/{print $2; exit}' "${meta_file}" 2>/dev/null || true)"
  fi

  if [ -z "${key_path}" ]; then
    key_path="~/.ssh/${username}_proxy"
  fi

  echo "${key_path}"
}

json_escape_multiline() {
  awk '
    BEGIN { ORS=""; first=1 }
    {
      gsub(/\\/,"\\\\");
      gsub(/"/,"\\\"");
      if (!first) printf "\\n";
      printf "%s", $0;
      first=0
    }
  ' "$1"
}

write_config() {
  local out_file="$1"
  local server="$2"
  local server_port="$3"
  local username="$4"
  local private_key_content="$5"
  local local_port="$6"
  local rule_set_detour="$7"

  cat > "${out_file}" <<JSON
{
  "log": {
    "level": "info"
  },
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": ${local_port}
    }
  ],
  "route": {
    "rule_set": [
      {
        "tag": "iran-geosite-ads",
        "type": "remote",
        "format": "binary",
        "download_detour": "${rule_set_detour}",
        "update_interval": "7d",
        "url": "https://github.com/bootmortis/sing-geosite/releases/latest/download/geosite-ads.srs"
      },
      {
        "tag": "iran-geosite-all",
        "type": "remote",
        "format": "binary",
        "download_detour": "${rule_set_detour}",
        "update_interval": "7d",
        "url": "https://github.com/bootmortis/sing-geosite/releases/latest/download/geosite-all.srs"
      }
    ],
    "rules": [
      {
        "rule_set": [
          "iran-geosite-ads"
        ],
        "action": "reject"
      },
      {
        "rule_set": [
          "iran-geosite-all"
        ],
        "action": "route",
        "outbound": "direct"
      }
    ],
    "final": "ssh-out"
  },
  "outbounds": [
    {
      "type": "ssh",
      "tag": "ssh-out",
      "server": "${server}",
      "server_port": ${server_port},
      "user": "${username}",
      "private_key": "${private_key_content}"
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
JSON
}

main() {
  local username=""
  local server=""
  local server_port=""
  local private_key_path=""
  local private_key_content=""
  local local_port="2080"
  local rule_set_detour="direct"
  local out_dir=""
  local out_file=""

  ssh_proxy_require_root

  read -r -p "Proxy username: " username
  if [ -z "${username}" ]; then
    echo "Username is required." >&2
    exit 1
  fi
  ensure_user_exists "${username}"

  server_port="$(read_user_port "${username}")"
  if [ -z "${server_port}" ]; then
    echo "SSH proxy port is not configured. Run ssh_proxy_manage_port.sh first." >&2
    exit 1
  fi

  server="$(read_default_server)"
  if [ -z "${server}" ]; then
    echo "Server address could not be detected." >&2
    echo "Set server_public_ip in ${PAQET_DIR}/server_info.txt and retry." >&2
    exit 1
  fi

  private_key_path="$(read_user_private_key_default "${username}")"
  if [ ! -f "${private_key_path}" ]; then
    echo "Private key file not found for user '${username}': ${private_key_path}" >&2
    echo "Create the user again or fix metadata before generating config." >&2
    exit 1
  fi
  private_key_content="$(json_escape_multiline "${private_key_path}")"
  if [ -z "${private_key_content}" ]; then
    echo "Private key is empty: ${private_key_path}" >&2
    exit 1
  fi

  out_dir="${CLIENTS_DIR}/${username}"
  out_file="${out_dir}/sing-box.json"
  mkdir -p "${out_dir}"

  write_config "${out_file}" "${server}" "${server_port}" "${username}" "${private_key_content}" "${local_port}" "${rule_set_detour}"
  chmod 600 "${out_file}" || true

  echo "Generated: ${out_file}"
  echo "Server: ${server}:${server_port} (locked)"
  echo "Local mixed inbound port: ${local_port} (locked)"
  echo "Rule-set detour outbound: ${rule_set_detour} (locked)"
  show_terminal_qr_from_config "${out_file}" || true
  echo
  echo "Use this on client:"
  echo "  sing-box run -c ${out_file}"
  echo "Then set your apps proxy to: socks5://127.0.0.1:${local_port}"
}

main "$@"
