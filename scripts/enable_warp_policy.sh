#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-server}"
SERVICE_NAME="paqet-${ROLE}"

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

# Install dependencies
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard-tools iproute2 iptables curl
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y wireguard-tools iproute iptables curl
elif command -v yum >/dev/null 2>&1; then
  yum install -y wireguard-tools iproute iptables curl
fi

# Install wgcf
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
  mkdir -p "${WGCF_DIR}"
  mkdir -p /usr/local/bin
  if command -v curl >/dev/null 2>&1; then
    if ! curl -fSL --connect-timeout 5 --max-time 30 "${URL}" -o "${WGCF_TMP}"; then
      if [ ! -s "${WGCF_TMP}" ]; then
        echo "Failed to download wgcf." >&2
        echo "Please download manually and place it at ${WGCF_BIN}:" >&2
        echo "  ${URL}" >&2
        exit 1
      fi
    fi
  else
    if ! wget -q --timeout=10 --tries=1 "${URL}" -O "${WGCF_TMP}"; then
      if [ ! -s "${WGCF_TMP}" ]; then
        echo "Failed to download wgcf." >&2
        echo "Please download manually and place it at ${WGCF_BIN}:" >&2
        echo "  ${URL}" >&2
        exit 1
      fi
    fi
  fi
  mv -f "${WGCF_TMP}" "${WGCF_BIN}"
  chmod +x "${WGCF_BIN}"
fi

mkdir -p "${WGCF_DIR}"
cd "${WGCF_DIR}"

# Register if no account
if [ ! -f "${WGCF_DIR}/wgcf-account.toml" ]; then
  printf "y\n" | "${WGCF_BIN}" register
fi

# Optional Warp+ key
read -r -p "WARP+ license key (optional, leave empty to skip): " WARP_KEY
if [ -n "${WARP_KEY}" ]; then
  WGCF_LICENSE_KEY="${WARP_KEY}" "${WGCF_BIN}" update
fi

# Generate profile
"${WGCF_BIN}" generate

if [ ! -f "${WGCF_PROFILE}" ]; then
  echo "wgcf-profile.conf not found after generate." >&2
  exit 1
fi

mkdir -p /etc/wireguard
cp -f "${WGCF_PROFILE}" "${WGCF_CONF}"
# Avoid DNS/resolvconf issues on minimal VPS (prevents wg-quick from calling resolvconf)
sed -i '/^DNS/d' "${WGCF_CONF}"
# Prevent wg-quick from changing system routes (protects SSH)
# Must be inside [Interface] section so wg-quick recognizes it.
sed -i '/^Table[[:space:]]*=.*/d' "${WGCF_CONF}"
if grep -q '^\[Interface\]' "${WGCF_CONF}"; then
  sed -i '/^\[Interface\]/a Table = off' "${WGCF_CONF}"
else
  # Fallback: prepend if malformed file
  sed -i '1i [Interface]\nTable = off' "${WGCF_CONF}"
fi

# Apply MTU (use same value as paqet if available)
MTU_VALUE=""
if [ -f "/root/paqet/server_info.txt" ]; then
  # shellcheck disable=SC1090
  source /root/paqet/server_info.txt
  MTU_VALUE="${mtu:-}"
fi
if [ -z "${MTU_VALUE}" ]; then
  MTU_VALUE="1280"
fi
sed -i '/^MTU[[:space:]]*=.*/d' "${WGCF_CONF}"
if grep -q '^\[Interface\]' "${WGCF_CONF}"; then
  sed -i "/^\\[Interface\\]/a MTU = ${MTU_VALUE}" "${WGCF_CONF}"
fi
echo "WARP MTU set to ${MTU_VALUE}"

# Bring up wgcf
wg-quick down wgcf >/dev/null 2>&1 || true
wg-quick up wgcf

# Create paqet user (for policy routing)
if ! id -u paqet >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin paqet
fi

# Ensure paqet binary/config are accessible to paqet user
PAQET_SRC_DIR="/root/paqet"
PAQET_DST_DIR="/opt/paqet"
PAQET_BIN_SRC="${PAQET_SRC_DIR}/paqet"
PAQET_CFG_SRC="${PAQET_SRC_DIR}/server.yaml"
PAQET_BIN_DST="${PAQET_DST_DIR}/paqet"
PAQET_CFG_DST="${PAQET_DST_DIR}/server.yaml"

if [ -x "${PAQET_BIN_SRC}" ] && [ -f "${PAQET_CFG_SRC}" ]; then
  mkdir -p "${PAQET_DST_DIR}"
  cp -f "${PAQET_BIN_SRC}" "${PAQET_BIN_DST}"
  cp -f "${PAQET_CFG_SRC}" "${PAQET_CFG_DST}"
  chown root:paqet "${PAQET_BIN_DST}" "${PAQET_CFG_DST}"
  chmod 750 "${PAQET_BIN_DST}"
  chmod 640 "${PAQET_CFG_DST}"
else
  echo "Warning: paqet binary/config not found at ${PAQET_SRC_DIR}. Service may fail to start." >&2
fi

# Ensure setcap is available
if ! command -v setcap >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get install -y libcap2-bin
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y libcap
  elif command -v yum >/dev/null 2>&1; then
    yum install -y libcap
  fi
fi

# Apply capabilities to paqet binary (if present)
if [ -x "${PAQET_BIN_DST}" ] && command -v setcap >/dev/null 2>&1; then
  setcap cap_net_raw,cap_net_admin=ep "${PAQET_BIN_DST}" || true
fi

# systemd drop-in to run as paqet with caps (if service exists)
UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
if [ -f "${UNIT}" ]; then
  mkdir -p "${DROPIN_DIR}"
  cat <<CONF > "${DROPIN_DIR}/10-warp.conf"
[Service]
User=paqet
Group=paqet
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true
WorkingDirectory=${PAQET_DST_DIR}
# Override ExecStart to use accessible path
ExecStart=
ExecStart=${PAQET_BIN_DST} run -c ${PAQET_CFG_DST}
CONF
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service" || true
fi

# Policy routing
TABLE_ID=51820
MARK=51820

# Add route table
if ! ip route show table ${TABLE_ID} | grep -q default; then
  ip route add default dev wgcf table ${TABLE_ID}
fi

# Add rule
if ! ip rule show | grep -q "fwmark ${MARK}.*lookup ${TABLE_ID}"; then
  ip rule add fwmark ${MARK} table ${TABLE_ID}
fi

# iptables mark rules for paqet user (ensure exists)
iptables -t mangle -D OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK} 2>/dev/null || true
iptables -t mangle -A OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK}

# Save iptables if persistence is installed
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
elif command -v service >/dev/null 2>&1; then
  service iptables save || true
fi

echo "WARP policy routing enabled for ${SERVICE_NAME}."
