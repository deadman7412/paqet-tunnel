#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

TABLE_ID=51820

remove_uid_rule() {
  local uid="$1"
  while ip rule del uidrange "${uid}-${uid}" table ${TABLE_ID} 2>/dev/null; do :; done
  while ip rule del uidrange "${uid}-${uid}" table wgcf 2>/dev/null; do :; done
}

main() {
  local usernames=""
  local user=""
  local uid=""
  local count=0

  ssh_proxy_require_root

  usernames="$(ssh_proxy_list_usernames || true)"
  if [ -z "${usernames}" ]; then
    echo "No SSH proxy users found."
    exit 0
  fi

  while IFS= read -r user; do
    [ -z "${user}" ] && continue
    if ! id -u "${user}" >/dev/null 2>&1; then
      continue
    fi
    uid="$(id -u "${user}")"
    remove_uid_rule "${uid}"
    count=$((count + 1))
  done <<< "${usernames}"

  echo "Disabled WARP uid rules for ${count} SSH proxy user(s)."
}

main "$@"
