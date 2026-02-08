#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

print_user_row() {
  local meta_file="$1"
  local username=""
  local proxy_port=""
  local created_at=""
  local status="missing"

  username="$(awk -F= '/^username=/{print $2; exit}' "${meta_file}" 2>/dev/null || true)"
  proxy_port="$(awk -F= '/^proxy_port=/{print $2; exit}' "${meta_file}" 2>/dev/null || true)"
  created_at="$(awk -F= '/^created_at=/{print $2; exit}' "${meta_file}" 2>/dev/null || true)"

  if [ -z "${username}" ]; then
    return 0
  fi

  if id -u "${username}" >/dev/null 2>&1; then
    status="active"
  fi

  printf '%-20s %-8s %-24s %-8s\n' "${username}" "${proxy_port:-N/A}" "${created_at:-N/A}" "${status}"
}

main() {
  local configured_port=""
  local found_any="0"
  local meta_file=""

  configured_port="$(ssh_proxy_get_configured_port)"
  if [ -n "${configured_port}" ]; then
    echo "SSH proxy port: ${configured_port}"
  else
    echo "SSH proxy port: not configured"
  fi
  echo

  if [ ! -d "${SSH_PROXY_USERS_DIR}" ]; then
    echo "No SSH proxy users found."
    exit 0
  fi

  printf '%-20s %-8s %-24s %-8s\n' "USERNAME" "PORT" "CREATED_AT_UTC" "STATUS"
  printf '%-20s %-8s %-24s %-8s\n' "--------------------" "--------" "------------------------" "--------"

  for meta_file in "${SSH_PROXY_USERS_DIR}"/*.env; do
    if [ ! -f "${meta_file}" ]; then
      continue
    fi
    found_any="1"
    print_user_row "${meta_file}"
  done

  if [ "${found_any}" = "0" ]; then
    echo "No SSH proxy users found."
  fi
}

main "$@"
