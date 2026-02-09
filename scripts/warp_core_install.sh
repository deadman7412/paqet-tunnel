#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECONCILE_SCRIPT="${SCRIPT_DIR}/reconcile_policy_bindings.sh"

TABLE_ID=51820
ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported arch: ${ARCH_RAW}" >&2; exit 1 ;;
esac

WGCF_BIN="/usr/local/bin/wgcf"
WGCF_DIR="/root/wgcf"
WGCF_TMP="${WGCF_DIR}/wgcf"
WGCF_PROFILE="${WGCF_DIR}/wgcf-profile.conf"
WGCF_CONF="/etc/wireguard/wgcf.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard-tools iproute2 iptables curl ca-certificates
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y wireguard-tools iproute iptables curl ca-certificates
elif command -v yum >/dev/null 2>&1; then
  yum install -y wireguard-tools iproute iptables curl ca-certificates
fi

if [ ! -x "${WGCF_BIN}" ]; then
  TAG=""
  if command -v curl >/dev/null 2>&1; then
    TAG="$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.github.com/repos/ViRb3/wgcf/releases/latest | awk -F '"' '/tag_name/{print $4; exit}' || true)"
  elif command -v wget >/dev/null 2>&1; then
    TAG="$(wget -qO- --timeout=10 https://api.github.com/repos/ViRb3/wgcf/releases/latest | awk -F '"' '/tag_name/{print $4; exit}' || true)"
  fi
  if [ -z "${TAG}" ]; then
    echo "Failed to detect wgcf version." >&2
    exit 1
  fi

  VER="${TAG#v}"
  ASSET="wgcf_${VER}_linux_${ARCH}"
  URL="https://github.com/ViRb3/wgcf/releases/download/${TAG}/${ASSET}"

  mkdir -p "${WGCF_DIR}" /usr/local/bin
  if command -v curl >/dev/null 2>&1; then
    curl -fSL --connect-timeout 5 --max-time 30 "${URL}" -o "${WGCF_TMP}"
  else
    wget -q --timeout=10 --tries=1 "${URL}" -O "${WGCF_TMP}"
  fi
  mv -f "${WGCF_TMP}" "${WGCF_BIN}"
  chmod +x "${WGCF_BIN}"
fi

mkdir -p "${WGCF_DIR}"
cd "${WGCF_DIR}"

if [ ! -f "${WGCF_DIR}/wgcf-account.toml" ]; then
  printf "y\n" | "${WGCF_BIN}" register
fi

read -r -p "WARP+ license key (optional, leave empty to skip): " WARP_KEY
if [ -n "${WARP_KEY}" ]; then
  WGCF_LICENSE_KEY="${WARP_KEY}" "${WGCF_BIN}" update
fi

"${WGCF_BIN}" generate

if [ ! -f "${WGCF_PROFILE}" ]; then
  echo "wgcf-profile.conf not found after generate." >&2
  exit 1
fi

mkdir -p /etc/wireguard
cp -f "${WGCF_PROFILE}" "${WGCF_CONF}"
sed -i '/^DNS/d' "${WGCF_CONF}"
sed -i '/^Table[[:space:]]*=.*/d' "${WGCF_CONF}"
if grep -q '^\[Interface\]' "${WGCF_CONF}"; then
  sed -i '/^\[Interface\]/a Table = off' "${WGCF_CONF}"
else
  sed -i '1i [Interface]\nTable = off' "${WGCF_CONF}"
fi

MTU_VALUE=""
if [ -f "${PAQET_DIR}/server_info.txt" ]; then
  MTU_VALUE="$(awk -F= '/^mtu=/{print $2; exit}' "${PAQET_DIR}/server_info.txt")"
fi
[ -z "${MTU_VALUE}" ] && MTU_VALUE="1280"

sed -i '/^MTU[[:space:]]*=.*/d' "${WGCF_CONF}"
if grep -q '^\[Interface\]' "${WGCF_CONF}"; then
  sed -i "/^\\[Interface\\]/a MTU = ${MTU_VALUE}" "${WGCF_CONF}"
fi

echo "WARP MTU set to ${MTU_VALUE}"

wg-quick down wgcf >/dev/null 2>&1 || true
wg-quick up wgcf

if [ -f /etc/iproute2/rt_tables ]; then
  if ! grep -qE "^[[:space:]]*${TABLE_ID}[[:space:]]+wgcf$" /etc/iproute2/rt_tables; then
    echo "${TABLE_ID} wgcf" >> /etc/iproute2/rt_tables
  fi
fi

if ! ip route show table ${TABLE_ID} 2>/dev/null | grep -q '^default '; then
  ip route add default dev wgcf table ${TABLE_ID}
fi

echo "WARP core installed and wgcf is active."

if [ -x "${RECONCILE_SCRIPT}" ]; then
  "${RECONCILE_SCRIPT}" warp || true
fi
