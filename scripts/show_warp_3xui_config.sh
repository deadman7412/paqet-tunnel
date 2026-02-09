#!/usr/bin/env bash
set -euo pipefail

WGCF_CONF="${WGCF_CONF:-/etc/wireguard/wgcf.conf}"

get_value() {
  local section="$1"
  local key="$2"
  awk -F= -v sec="${section}" -v k="${key}" '
    /^[[:space:]]*\[/ {
      insec = ($0 ~ "^[[:space:]]*\\[" sec "\\][[:space:]]*$")
      next
    }
    insec && $1 ~ "^[[:space:]]*" k "[[:space:]]*$" {
      v = $2
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]]+$/, "", v)
      print v
      exit
    }
  ' "${WGCF_CONF}"
}

if [ ! -f "${WGCF_CONF}" ]; then
  echo "WARP config not found: ${WGCF_CONF}" >&2
  echo "Run: Server configuration -> Enable WARP (policy routing)" >&2
  exit 1
fi

if [ ! -r "${WGCF_CONF}" ]; then
  echo "Cannot read ${WGCF_CONF}. Run this as root (sudo)." >&2
  exit 1
fi

iface_private_key="$(get_value "Interface" "PrivateKey")"
iface_address="$(get_value "Interface" "Address")"
iface_mtu="$(get_value "Interface" "MTU")"
peer_public_key="$(get_value "Peer" "PublicKey")"
peer_endpoint="$(get_value "Peer" "Endpoint")"
peer_allowed_ips="$(get_value "Peer" "AllowedIPs")"
peer_keepalive="$(get_value "Peer" "PersistentKeepalive")"
peer_reserved="$(get_value "Peer" "Reserved")"

iface_mtu="${iface_mtu:-1280}"
peer_keepalive="${peer_keepalive:-25}"
peer_allowed_ips="${peer_allowed_ips:-0.0.0.0/0, ::/0}"

json_array_from_csv() {
  local csv="$1"
  local out=""
  local item=""
  IFS=',' read -r -a _items <<< "${csv}"
  for item in "${_items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [ -z "${item}" ] && continue
    if [ -n "${out}" ]; then
      out="${out}, "
    fi
    out="${out}\"${item}\""
  done
  printf '%s' "${out}"
}

json_addresses="$(json_array_from_csv "${iface_address}")"
json_allowed_ips="$(json_array_from_csv "${peer_allowed_ips}")"

echo "WARP WireGuard values for 3x-ui"
echo "Source: ${WGCF_CONF}"
echo
echo "Tag: warp-wgcf"
echo "Protocol: wireguard"
echo "No Kernel Tun: ON"
echo "Secret Key: ${iface_private_key}"
echo "Address: ${iface_address}"
echo "MTU: ${iface_mtu}"
echo "Reserved: ${peer_reserved}"
echo
echo "Peer 1"
echo "Endpoint: ${peer_endpoint}"
echo "Public Key: ${peer_public_key}"
echo "Allowed IPs: ${peer_allowed_ips}"
echo "Keep Alive: ${peer_keepalive}"
echo
echo "Paste-ready JSON (3x-ui JSON tab)"
cat <<EOF
{
  "protocol": "wireguard",
  "tag": "warp-wgcf",
  "settings": {
    "secretKey": "${iface_private_key}",
    "address": [${json_addresses}],
    "mtu": ${iface_mtu},
    "workers": 2,
    "domainStrategy": "ForceIP",
    "reserved": [${peer_reserved}],
    "peers": [
      {
        "publicKey": "${peer_public_key}",
        "endpoint": "${peer_endpoint}",
        "keepAlive": ${peer_keepalive},
        "allowedIPs": [${json_allowed_ips}]
      }
    ],
    "kernelMode": false
  }
}
EOF
echo
echo "Note: Do not run kernel wgcf and this outbound simultaneously with the same profile while testing."
