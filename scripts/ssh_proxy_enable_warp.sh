#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

TABLE_ID=51820

ensure_wgcf_route_table() {
  if [ ! -f /etc/wireguard/wgcf.conf ]; then
    echo "WARP is not installed/configured on this server." >&2
    echo "Run: Server configuration -> Enable WARP (policy routing)" >&2
    exit 1
  fi

  if ! ip link show wgcf >/dev/null 2>&1; then
    echo "WARP is installed but wgcf interface is not active." >&2
    echo "Run: Server configuration -> Enable WARP (policy routing)" >&2
    exit 1
  fi

  if [ -f /etc/iproute2/rt_tables ]; then
    if ! grep -qE "^[[:space:]]*${TABLE_ID}[[:space:]]+wgcf$" /etc/iproute2/rt_tables; then
      echo "${TABLE_ID} wgcf" >> /etc/iproute2/rt_tables
    fi
  fi

  if ! ip route show table ${TABLE_ID} 2>/dev/null | grep -q '^default '; then
    ip route add default dev wgcf table ${TABLE_ID}
  fi
}

ensure_uid_rule() {
  local uid="$1"
  if ip rule show | grep -Eq "uidrange ${uid}-${uid}.*lookup (${TABLE_ID}|wgcf)"; then
    return 0
  fi

  ip rule add uidrange "${uid}-${uid}" table ${TABLE_ID} 2>/dev/null || ip rule add uidrange "${uid}-${uid}" table wgcf 2>/dev/null || {
    echo "Failed to add WARP rule for uid ${uid}." >&2
    return 1
  }
}

main() {
  local usernames=""
  local user=""
  local uid=""
  local count=0

  ssh_proxy_require_root
  ensure_wgcf_route_table

  usernames="$(ssh_proxy_list_usernames || true)"
  if [ -z "${usernames}" ]; then
    echo "No SSH proxy users found."
    exit 0
  fi

  while IFS= read -r user; do
    [ -z "${user}" ] && continue
    if ! id -u "${user}" >/dev/null 2>&1; then
      echo "Skipping missing system user: ${user}"
      continue
    fi
    uid="$(id -u "${user}")"
    ensure_uid_rule "${uid}" && count=$((count + 1))
  done <<< "${usernames}"

  ssh_proxy_set_setting "warp_enabled" "1"
  echo "Enabled WARP uid rules for ${count} SSH proxy user(s)."
}

main "$@"
