#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-server}"
SERVICE_NAME="paqet-${ROLE}"
PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"

# Policy routing constants (defined early for use throughout script)
TABLE_ID=51820
MARK=51820
MARK_HEX="$(printf '0x%08x' "${MARK}")"

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

ensure_server_iptables_rules() {
  local port=""
  local info_file="${PAQET_DIR}/server_info.txt"
  local cfg_file="${PAQET_DIR}/server.yaml"

  if [ -f "${cfg_file}" ]; then
    port="$(awk '
      $1 == "listen:" { inlisten=1; next }
      inlisten && $1 == "addr:" {
        gsub(/"/, "", $2);
        sub(/^:/, "", $2);
        print $2;
        exit
      }
    ' "${cfg_file}")"
  fi
  if [ -z "${port}" ] && [ -f "${info_file}" ]; then
    port="$(awk -F= '/^listen_port=/{print $2; exit}' "${info_file}")"
  fi
  if [ -z "${port}" ]; then
    echo "Warning: could not detect server listen port for iptables checks." >&2
    return 0
  fi

  # Keep one tagged copy of each server rule (older releases could create duplicates).
  while iptables -t raw -C PREROUTING -p tcp --dport "${port}" -m comment --comment paqet-notrack-in -j NOTRACK 2>/dev/null; do
    iptables -t raw -D PREROUTING -p tcp --dport "${port}" -m comment --comment paqet-notrack-in -j NOTRACK 2>/dev/null || true
  done
  iptables -t raw -A PREROUTING -p tcp --dport "${port}" -m comment --comment paqet-notrack-in -j NOTRACK 2>/dev/null || true

  while iptables -t raw -C OUTPUT -p tcp --sport "${port}" -m comment --comment paqet-notrack-out -j NOTRACK 2>/dev/null; do
    iptables -t raw -D OUTPUT -p tcp --sport "${port}" -m comment --comment paqet-notrack-out -j NOTRACK 2>/dev/null || true
  done
  iptables -t raw -A OUTPUT -p tcp --sport "${port}" -m comment --comment paqet-notrack-out -j NOTRACK 2>/dev/null || true

  while iptables -t mangle -C OUTPUT -p tcp --sport "${port}" --tcp-flags RST RST -m comment --comment paqet-rst-drop -j DROP 2>/dev/null; do
    iptables -t mangle -D OUTPUT -p tcp --sport "${port}" --tcp-flags RST RST -m comment --comment paqet-rst-drop -j DROP 2>/dev/null || true
  done
  iptables -t mangle -A OUTPUT -p tcp --sport "${port}" --tcp-flags RST RST -m comment --comment paqet-rst-drop -j DROP 2>/dev/null || true
}

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
if [ -f "${PAQET_DIR}/server_info.txt" ]; then
  MTU_VALUE="$(awk -F= '/^mtu=/{print $2; exit}' "${PAQET_DIR}/server_info.txt")"
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
PAQET_UID="$(id -u paqet)"
MARK_HEX="$(printf '0x%08x' "${MARK}")"

# Ensure paqet binary/config are accessible to paqet user
PAQET_SRC_DIR="${PAQET_DIR}"
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
if [ -f "${UNIT}" ]; then
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service" || true
else
  echo "Note: ${SERVICE_NAME}.service not installed yet. WARP drop-in is prepared and will apply after service install."
fi

# Ensure route table name exists (avoids "FIB table does not exist")
if [ -f /etc/iproute2/rt_tables ]; then
  if ! grep -qE "^[[:space:]]*${TABLE_ID}[[:space:]]+wgcf\$" /etc/iproute2/rt_tables; then
    echo "${TABLE_ID} wgcf" >> /etc/iproute2/rt_tables
  fi
fi

# Add route table
if ! ip route show table ${TABLE_ID} 2>/dev/null | grep -q default; then
  ip route add default dev wgcf table ${TABLE_ID}
fi

# Add rule (ip may display fwmark in hex and table may show as name)
if ! ip rule show | grep -Eq "fwmark (0x0*ca6c|0x0000ca6c|${MARK}).*lookup (${TABLE_ID}|wgcf)"; then
  if ! ip rule add fwmark ${MARK} table ${TABLE_ID} 2>/dev/null; then
    ip rule add fwmark ${MARK_HEX} table ${TABLE_ID} 2>/dev/null || true
  fi
fi
if ! ip rule show | grep -Eq "fwmark (0x0*ca6c|0x0000ca6c|${MARK}).*lookup (${TABLE_ID}|wgcf)"; then
  echo "Debug: fwmark rule still missing after add."
  ip rule show || true
else
  echo "fwmark rule present:"
  ip rule show | grep -E "fwmark (0x0*ca6c|0x0000ca6c|${MARK}).*lookup (${TABLE_ID}|wgcf)" || true
fi

# Fallback: uidrange rule (forces routing for paqet user, avoids mark timing issues)
if ! ip rule show | grep -Eq "uidrange ${PAQET_UID}-${PAQET_UID}.*lookup (${TABLE_ID}|wgcf)"; then
  if ip rule add uidrange ${PAQET_UID}-${PAQET_UID} table ${TABLE_ID} 2>/dev/null; then
    echo "uidrange rule added for paqet user (${PAQET_UID})."
  else
    echo "Warning: uidrange rule not supported or failed to add." >&2
  fi
fi

# iptables/nft mark rules for paqet user (ensure exists)
modprobe xt_owner 2>/dev/null || true
if iptables -V 2>/dev/null | grep -qi nf_tables; then
  echo "iptables backend: nft"
else
  echo "iptables backend: legacy"
fi
iptables -t mangle -D OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK} 2>/dev/null || true
if ! iptables -t mangle -A OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK} 2>/dev/null; then
  echo "iptables owner-mark rule failed (will try nft fallback)."
fi

if ! iptables -t mangle -C OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK} 2>/dev/null; then
  # Fallback to nft if iptables owner match isn't effective
  if command -v nft >/dev/null 2>&1; then
    nft list table inet mangle >/dev/null 2>&1 || nft add table inet mangle
    nft list chain inet mangle output >/dev/null 2>&1 || nft add chain inet mangle output '{ type filter hook output priority mangle; policy accept; }'
    # Remove any existing mark rules for this UID (avoid duplicates)
    while read -r handle; do
      [ -n "${handle}" ] && nft delete rule inet mangle output handle "${handle}" 2>/dev/null || true
    done < <(nft -a list chain inet mangle output 2>/dev/null | awk -v uid="${PAQET_UID}" '/skuid/ && /mark set/ && $0 ~ ("skuid " uid) {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1)}}')
    nft add rule inet mangle output meta skuid ${PAQET_UID} counter meta mark set ${MARK}
  fi
fi

# Verify rule exists via iptables or nft
if ! iptables -t mangle -C OUTPUT -m owner --uid-owner paqet -j MARK --set-mark ${MARK} 2>/dev/null; then
  echo "iptables mark rule not detected; checking nft..."
  if command -v nft >/dev/null 2>&1; then
    if ! nft -a list chain inet mangle output 2>/dev/null | grep -Eq "skuid ${PAQET_UID}.*mark set"; then
      echo "Warning: could not verify nft mark rule (continuing)." >&2
      echo "Debug:"
      echo "  PAQET_UID=${PAQET_UID}"
      echo "  MARK=${MARK}"
      echo "  MARK_HEX=${MARK_HEX}"
      echo "  nft chain output:"
      nft -a list chain inet mangle output 2>/dev/null || true
    fi
  else
    echo "Warning: iptables mark rule not present and nft not available (continuing)." >&2
  fi
fi

# Persist firewall changes
ensure_server_iptables_rules
if iptables -V 2>/dev/null | grep -qi nf_tables; then
  if command -v nft >/dev/null 2>&1; then
    nft list ruleset > /etc/nftables.conf || true
    systemctl enable --now nftables >/dev/null 2>&1 || true
  fi
else
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save || true
  elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4 || true
  elif command -v service >/dev/null 2>&1; then
    service iptables save || true
  fi
fi

echo "WARP policy routing enabled for ${SERVICE_NAME}."

# Quick verification (best-effort)
if command -v curl >/dev/null 2>&1 && id -u paqet >/dev/null 2>&1; then
  get_trace() {
    local out=""
    out="$(sudo -u paqet curl -fsSL --connect-timeout 5 --max-time 12 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)"
    if [ -z "${out}" ]; then
      out="$(sudo -u paqet curl -fsSL --connect-timeout 5 --max-time 12 https://cloudflare.com/cdn-cgi/trace 2>/dev/null || true)"
    fi
    if [ -z "${out}" ]; then
      out="$(sudo -u paqet curl -fsSL --connect-timeout 5 --max-time 12 http://1.1.1.1/cdn-cgi/trace 2>/dev/null || true)"
    fi
    echo "${out}"
  }
  echo "Verifying WARP for paqet traffic..."
  PAQET_TRACE="$(get_trace)"
  if echo "${PAQET_TRACE}" | grep -q "warp=on"; then
    echo "WARP verification: OK (paqet traffic uses WARP)"
  else
    echo "WARP verification: NOT CONFIRMED (paqet traffic shows warp=off)"
    echo "Run Test WARP for full diagnostics."
  fi
else
  echo "WARP verification: skipped (curl or user 'paqet' missing)"
fi
