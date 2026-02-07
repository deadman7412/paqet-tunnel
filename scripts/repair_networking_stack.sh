#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-auto}"
PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
SERVER_CFG="${PAQET_DIR}/server.yaml"
CLIENT_CFG="${PAQET_DIR}/client.yaml"
ADD_IPTABLES_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/add_server_iptables.sh"

TABLE_ID=51820
MARK=51820
MARK_HEX="$(printf '0x%08x' "${MARK}")"

role_enabled() {
  local wanted="$1"
  case "${ROLE}" in
    auto|all) return 0 ;;
    "${wanted}") return 0 ;;
    *) return 1 ;;
  esac
}

get_server_port() {
  local port=""
  if [ -f "${SERVER_CFG}" ]; then
    port="$(awk '
      $1 == "listen:" { inlisten=1; next }
      inlisten && $1 == "addr:" {
        gsub(/"/, "", $2)
        sub(/^:/, "", $2)
        print $2
        exit
      }
    ' "${SERVER_CFG}")"
  fi
  echo "${port}"
}

get_client_server_addr() {
  local addr=""
  if [ -f "${CLIENT_CFG}" ]; then
    addr="$(awk '
      $1 == "server:" { inserver=1; next }
      inserver && $1 == "addr:" {
        gsub(/"/, "", $2)
        print $2
        exit
      }
    ' "${CLIENT_CFG}")"
  fi
  echo "${addr}"
}

sync_ufw_server_rule() {
  local new_port="$1"
  local old_client_ip=""
  local status_line=""
  local -a rules=()

  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi
  status_line="$(ufw status 2>/dev/null | head -n1 || true)"
  if ! echo "${status_line}" | grep -q "Status: active"; then
    return 0
  fi

  old_client_ip="$(ufw status 2>/dev/null | awk '/paqet-tunnel/ && /ALLOW IN/ {for(i=1;i<=NF;i++) if($i=="IN"){print $(i+1); exit}}')"
  if [ -z "${old_client_ip}" ] || [ "${old_client_ip}" = "Anywhere" ] || [ "${old_client_ip}" = "Anywhere(v6)" ]; then
    old_client_ip=""
  fi

  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk '/paqet-tunnel/ {gsub(/[][]/,"",$1); print $1}')
  if [ "${#rules[@]}" -gt 0 ]; then
    for ((i=${#rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
    done
    echo "UFW: removed old paqet-tunnel rule(s)."
  fi

  if [ -n "${old_client_ip}" ]; then
    ufw allow from "${old_client_ip}" to any port "${new_port}" proto tcp comment 'paqet-tunnel' >/dev/null 2>&1 || true
    echo "UFW: updated paqet-tunnel IN rule to port ${new_port} from ${old_client_ip}."
  else
    echo "UFW: skipped server paqet-tunnel add (client IP unknown)."
  fi
}

sync_ufw_client_rule() {
  local server_ip="$1"
  local server_port="$2"
  local status_line=""
  local -a rules=()

  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi
  status_line="$(ufw status 2>/dev/null | head -n1 || true)"
  if ! echo "${status_line}" | grep -q "Status: active"; then
    return 0
  fi

  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk '/paqet-tunnel/ {gsub(/[][]/,"",$1); print $1}')
  if [ "${#rules[@]}" -gt 0 ]; then
    for ((i=${#rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
    done
    echo "UFW: removed old paqet-tunnel rule(s)."
  fi

  ufw allow out to "${server_ip}" port "${server_port}" proto tcp comment 'paqet-tunnel' >/dev/null 2>&1 || true
  echo "UFW: updated paqet-tunnel OUT rule to ${server_ip}:${server_port}."
}

ensure_warp_policy_rules() {
  local uid=""

  if [ ! -f /etc/wireguard/wgcf.conf ]; then
    return 0
  fi

  wg-quick down wgcf >/dev/null 2>&1 || true
  wg-quick up wgcf >/dev/null 2>&1 || true

  if ! id -u paqet >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin paqet
  fi
  uid="$(id -u paqet)"

  if [ -f /etc/iproute2/rt_tables ] && ! grep -qE "^[[:space:]]*${TABLE_ID}[[:space:]]+wgcf$" /etc/iproute2/rt_tables; then
    echo "${TABLE_ID} wgcf" >> /etc/iproute2/rt_tables
  fi

  ip route add default dev wgcf table ${TABLE_ID} 2>/dev/null || true

  if ! ip rule show | grep -Eq "fwmark (0x0*ca6c|${MARK}).*lookup (${TABLE_ID}|wgcf)"; then
    ip rule add fwmark ${MARK} table ${TABLE_ID} 2>/dev/null || ip rule add fwmark ${MARK_HEX} table ${TABLE_ID} 2>/dev/null || true
  fi

  if ! ip rule show | grep -Eq "uidrange ${uid}-${uid}.*lookup (${TABLE_ID}|wgcf)"; then
    ip rule add uidrange ${uid}-${uid} table ${TABLE_ID} 2>/dev/null || true
  fi

  modprobe xt_owner 2>/dev/null || true
  iptables -t mangle -D OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK} 2>/dev/null || true
  iptables -t mangle -A OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK} 2>/dev/null || true

  if ! iptables -t mangle -C OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK} 2>/dev/null; then
    if command -v nft >/dev/null 2>&1; then
      nft list table inet mangle >/dev/null 2>&1 || nft add table inet mangle
      nft list chain inet mangle output >/dev/null 2>&1 || nft add chain inet mangle output '{ type filter hook output priority mangle; policy accept; }'
      while read -r handle; do
        [ -n "${handle}" ] && nft delete rule inet mangle output handle "${handle}" 2>/dev/null || true
      done < <(nft -a list chain inet mangle output 2>/dev/null | awk -v p_uid="${uid}" '/skuid/ && /mark set/ && $0 ~ ("skuid " p_uid) {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1)}}')
      nft add rule inet mangle output meta skuid ${uid} counter meta mark set ${MARK}
    fi
  fi

  echo "WARP: refreshed policy routing and mark rules."
}

repair_server() {
  if [ ! -f "${SERVER_CFG}" ]; then
    echo "Server config not found; skipping server repair."
    return 0
  fi

  local port
  port="$(get_server_port)"
  if [ -z "${port}" ]; then
    echo "Could not detect server listen port; skipping server repair." >&2
    return 0
  fi

  echo "Repairing server networking stack..."
  if [ -x "${ADD_IPTABLES_SCRIPT}" ]; then
    SKIP_PKG_INSTALL=1 "${ADD_IPTABLES_SCRIPT}" || true
  fi
  sync_ufw_server_rule "${port}"
  ensure_warp_policy_rules

  if systemctl list-unit-files 2>/dev/null | grep -q '^paqet-server.service'; then
    systemctl restart paqet-server.service 2>/dev/null || true
  fi
}

repair_client() {
  if [ ! -f "${CLIENT_CFG}" ]; then
    echo "Client config not found; skipping client repair."
    return 0
  fi

  local server_addr server_ip server_port
  server_addr="$(get_client_server_addr)"
  if [ -n "${server_addr}" ]; then
    server_ip="${server_addr%:*}"
    server_port="${server_addr##*:}"
    if [ -n "${server_ip}" ] && [ -n "${server_port}" ] && [[ "${server_port}" =~ ^[0-9]+$ ]]; then
      sync_ufw_client_rule "${server_ip}" "${server_port}"
    fi
  fi

  echo "Repairing client networking stack..."
  if systemctl list-unit-files 2>/dev/null | grep -q '^paqet-client.service'; then
    systemctl restart paqet-client.service 2>/dev/null || true
  fi
}

case "${ROLE}" in
  auto|all|server|client) ;;
  *)
    echo "Invalid role: ${ROLE} (use auto|all|server|client)" >&2
    exit 1
    ;;
esac

if role_enabled server; then
  repair_server
fi
if role_enabled client; then
  repair_client
fi

echo "Networking repair completed."
