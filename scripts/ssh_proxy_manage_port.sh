#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

main() {
  local current_port=""
  local paqet_port=""
  local ssh_ports=""
  local target_port=""

  ssh_proxy_require_root

  current_port="$(ssh_proxy_get_configured_port)"
  paqet_port="$(ssh_proxy_get_paqet_port)"
  ssh_ports="$(ssh_proxy_get_all_ssh_ports)"

  if [ -n "${current_port}" ]; then
    echo "Current SSH proxy port (settings DB): ${current_port}"
  else
    echo "Current SSH proxy port (settings DB): not set"
  fi
  echo "Detected SSH ports: ${ssh_ports}"
  if [ -n "${paqet_port}" ]; then
    echo "Detected paqet port: ${paqet_port}"
  fi

  read -r -p "New SSH proxy port [leave empty to keep/randomize]: " target_port

  if [ -z "${target_port}" ]; then
    if [ -n "${current_port}" ]; then
      target_port="${current_port}"
      echo "Keeping existing SSH proxy port: ${target_port}"
    else
      target_port="$(ssh_proxy_random_port "${paqet_port}" "${ssh_ports}" "${current_port}")"
      echo "Selected random SSH proxy port: ${target_port}"
    fi
  else
    ssh_proxy_validate_port "${target_port}" "${paqet_port}" "${ssh_ports}" "${current_port}"
  fi

  ssh_proxy_apply_port "${target_port}" "${current_port}"
  echo "SSH proxy port is set to ${target_port}."
}

main "$@"
