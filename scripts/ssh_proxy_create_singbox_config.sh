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

generate_qr_if_requested() {
  local out_dir="$1"
  local profile_name="$2"
  local remote_url="$3"
  local encoded_url=""
  local encoded_name=""
  local import_link=""
  local qr_png=""

  if [ -z "${remote_url}" ]; then
    return 0
  fi

  encoded_url="$(url_encode "${remote_url}")"
  encoded_name="$(url_encode "${profile_name}")"
  import_link="sing-box://import-remote-profile?url=${encoded_url}#${encoded_name}"
  qr_png="${out_dir}/sing-box-import-qr.png"

  echo
  echo "Remote import link:"
  echo "${import_link}"

  if ! command -v qrencode >/dev/null 2>&1; then
    echo "qrencode not found; skipping QR image generation."
    echo "Install hint: apt-get install -y qrencode"
    return 0
  fi

  qrencode -o "${qr_png}" -s 8 -m 2 "${import_link}"
  echo "Saved QR PNG: ${qr_png}"
  echo
  echo "Terminal QR preview:"
  qrencode -t ANSIUTF8 "${import_link}" || true
}

show_terminal_qr_from_config() {
  local config_file="$1"
  local payload=""

  if ! command -v qrencode >/dev/null 2>&1; then
    echo "qrencode not found; cannot show terminal QR."
    echo "Install hint: apt-get install -y qrencode"
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
  if ! qrencode -t ANSIUTF8 "${payload}"; then
    echo "Config is too large for a single QR payload."
    echo "Use remote profile URL mode instead."
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

  if [ ! -f "${meta_file}" ] && ! id -u "${username}" >/dev/null 2>&1; then
    echo "Unknown SSH proxy user: ${username}" >&2
    return 1
  fi

  return 0
}

read_user_port() {
  local username="$1"
  local meta_file="${SSH_PROXY_USERS_DIR}/${username}.env"
  local user_port=""

  if [ -f "${meta_file}" ]; then
    user_port="$(awk -F= '/^proxy_port=/{print $2; exit}' "${meta_file}" 2>/dev/null || true)"
  fi

  if [ -z "${user_port}" ]; then
    user_port="$(ssh_proxy_get_configured_port)"
  fi

  echo "${user_port}"
}

write_config() {
  local out_file="$1"
  local server="$2"
  local server_port="$3"
  local username="$4"
  local private_key_path="$5"
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
      "private_key_path": "${private_key_path}"
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
  local local_port=""
  local rule_set_detour=""
  local remote_url=""
  local show_qr_now=""
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
  read -r -p "Server address/IP [${server}]: " input_server
  server="${input_server:-${server}}"
  if [ -z "${server}" ]; then
    echo "Server address is required." >&2
    exit 1
  fi

  read -r -p "Client private key path [~/.ssh/${username}_proxy]: " private_key_path
  private_key_path="${private_key_path:-~/.ssh/${username}_proxy}"

  read -r -p "Local mixed inbound port [2080]: " local_port
  local_port="${local_port:-2080}"
  if ! ssh_proxy_is_number "${local_port}" || [ "${local_port}" -lt 1 ] || [ "${local_port}" -gt 65535 ]; then
    echo "Local mixed inbound port must be 1-65535." >&2
    exit 1
  fi

  read -r -p "Rule-set download detour outbound [ssh-out]: " rule_set_detour
  rule_set_detour="${rule_set_detour:-ssh-out}"

  out_dir="${CLIENTS_DIR}/${username}"
  out_file="${out_dir}/sing-box.json"
  mkdir -p "${out_dir}"

  write_config "${out_file}" "${server}" "${server_port}" "${username}" "${private_key_path}" "${local_port}" "${rule_set_detour}"
  chmod 600 "${out_file}" || true

  echo "Generated: ${out_file}"
  read -r -p "Show terminal QR now? [Y/n]: " show_qr_now
  case "${show_qr_now}" in
    n|N) ;;
    *)
      show_terminal_qr_from_config "${out_file}" || true
      ;;
  esac

  read -r -p "Remote HTTPS URL for this config (optional, for import-remote-profile QR): " remote_url
  if [ -n "${remote_url}" ]; then
    generate_qr_if_requested "${out_dir}" "${username}-ssh-proxy" "${remote_url}"
  fi
  echo
  echo "Use this on client:"
  echo "  sing-box run -c ${out_file}"
  echo "Then set your apps proxy to: socks5://127.0.0.1:${local_port}"
}

main "$@"
