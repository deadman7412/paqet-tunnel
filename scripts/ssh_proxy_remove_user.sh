#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

confirm() {
  local prompt="$1"
  local ans=""

  read -r -p "${prompt} [y/N]: " ans
  case "${ans}" in
    y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

remove_user_account() {
  local username="$1"
  local remove_home="$2"

  if ! id -u "${username}" >/dev/null 2>&1; then
    echo "System user not found: ${username}"
    return 0
  fi

  if [ "${remove_home}" = "yes" ]; then
    userdel -r "${username}" >/dev/null 2>&1 || userdel "${username}"
  else
    userdel "${username}"
  fi

  echo "Removed system user: ${username}"
}

remove_user_meta() {
  local username="$1"
  local meta_file="${SSH_PROXY_USERS_DIR}/${username}.env"

  if [ -f "${meta_file}" ]; then
    rm -f "${meta_file}"
    echo "Removed user metadata: ${meta_file}"
  fi
}

main() {
  local username=""
  local remove_home="no"
  local configured_port=""

  ssh_proxy_require_root

  configured_port="$(ssh_proxy_get_configured_port)"
  if [ -n "${configured_port}" ]; then
    echo "SSH proxy port (unchanged): ${configured_port}"
  else
    echo "SSH proxy port: not configured"
  fi

  read -r -p "Proxy username to remove: " username
  if [ -z "${username}" ]; then
    echo "Username is required." >&2
    exit 1
  fi

  if ! id -u "${username}" >/dev/null 2>&1 && [ ! -f "${SSH_PROXY_USERS_DIR}/${username}.env" ]; then
    echo "No such SSH proxy user in system or metadata: ${username}" >&2
    exit 1
  fi

  if ! confirm "Remove SSH proxy user '${username}'?"; then
    echo "Aborted."
    exit 0
  fi

  if confirm "Also remove home directory for '${username}'?"; then
    remove_home="yes"
  fi

  remove_user_account "${username}" "${remove_home}"
  remove_user_meta "${username}"

  echo "SSH proxy user removal complete."
}

main "$@"
