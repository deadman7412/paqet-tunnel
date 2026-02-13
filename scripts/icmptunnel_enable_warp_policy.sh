#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-server}"
SERVICE_NAME="icmptunnel-${ROLE}"
ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
ICMPTUNNEL_POLICY_STATE_DIR="/etc/icmptunnel-policy"
ICMPTUNNEL_POLICY_STATE_FILE="${ICMPTUNNEL_POLICY_STATE_DIR}/settings.env"

TABLE_ID=51820
MARK=51820
MARK_HEX="$(printf '0x%08x' "${MARK}")"

set_state() {
  local key="$1"
  local value="$2"
  local tmp=""

  mkdir -p "${ICMPTUNNEL_POLICY_STATE_DIR}"
  tmp="$(mktemp)"
  if [ -f "${ICMPTUNNEL_POLICY_STATE_FILE}" ]; then
    awk -F= -v k="${key}" '$1!=k {print $0}' "${ICMPTUNNEL_POLICY_STATE_FILE}" > "${tmp}" 2>/dev/null || true
  fi
  echo "${key}=${value}" >> "${tmp}"
  mv "${tmp}" "${ICMPTUNNEL_POLICY_STATE_FILE}"
  chmod 600 "${ICMPTUNNEL_POLICY_STATE_FILE}"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

echo "========================================="
echo "ICMP Tunnel WARP Policy - Enable"
echo "========================================="
echo "[DEBUG] Role: ${ROLE}"
echo "[DEBUG] Service: ${SERVICE_NAME}"
echo "[DEBUG] Script directory: ${ICMPTUNNEL_DIR}"
echo
echo "[DEBUG] Initial state check..."
echo "[DEBUG] Existing ip rules with uidrange:"
ip rule show | grep -E "uidrange" | sed 's/^/  /' || echo "  (none)"
echo

echo "[DEBUG] Checking WARP core installation..."
if [ ! -f /etc/wireguard/wgcf.conf ]; then
  echo "[ERROR] WARP core is not installed." >&2
  echo "Run: Paqet Tunnel -> WARP/DNS core -> Install WARP core" >&2
  exit 1
fi
echo "[SUCCESS] WARP core config found"

echo "[DEBUG] Checking wgcf interface status..."
if ! ip link show wgcf >/dev/null 2>&1; then
  echo "[INFO] wgcf interface is down, attempting to start..."
  wg-quick up wgcf || {
    echo "[ERROR] wgcf interface is not active and could not be started." >&2
    exit 1
  }
  echo "[SUCCESS] wgcf interface started"
else
  echo "[SUCCESS] wgcf interface is active"
fi

echo "[DEBUG] Setting up routing table ${TABLE_ID}..."
if [ -f /etc/iproute2/rt_tables ]; then
  if ! grep -qE "^[[:space:]]*${TABLE_ID}[[:space:]]+wgcf$" /etc/iproute2/rt_tables; then
    echo "[INFO] Adding table ${TABLE_ID} to /etc/iproute2/rt_tables"
    echo "${TABLE_ID} wgcf" >> /etc/iproute2/rt_tables
  else
    echo "[DEBUG] Table ${TABLE_ID} already in rt_tables"
  fi
fi

echo "[DEBUG] Checking default route in table ${TABLE_ID}..."
if ! ip route show table ${TABLE_ID} 2>/dev/null | grep -q '^default '; then
  echo "[INFO] Adding default route via wgcf to table ${TABLE_ID}"
  ip route add default dev wgcf table ${TABLE_ID}
  echo "[SUCCESS] Default route added"
else
  echo "[DEBUG] Default route already exists in table ${TABLE_ID}"
fi

echo "[DEBUG] Current routes in table ${TABLE_ID}:"
ip route show table ${TABLE_ID} | sed 's/^/  /' || echo "  (no routes)"

echo "[DEBUG] Checking icmptunnel user..."
if ! id -u icmptunnel >/dev/null 2>&1; then
  echo "[INFO] Creating icmptunnel system user..."
  useradd --system --no-create-home --shell /usr/sbin/nologin icmptunnel
  echo "[SUCCESS] icmptunnel user created"
else
  echo "[DEBUG] icmptunnel user already exists"
fi
ICMPTUNNEL_UID="$(id -u icmptunnel)"
echo "[DEBUG] icmptunnel UID: ${ICMPTUNNEL_UID}"

ICMPTUNNEL_SRC_DIR="${ICMPTUNNEL_DIR}"
ICMPTUNNEL_DST_DIR="/opt/icmptunnel"
ICMPTUNNEL_BIN_SRC="${ICMPTUNNEL_SRC_DIR}/icmptunnel"
ICMPTUNNEL_CFG_SRC="${ICMPTUNNEL_SRC_DIR}/${ROLE}/config.json"
ICMPTUNNEL_BIN_DST="${ICMPTUNNEL_DST_DIR}/icmptunnel"
ICMPTUNNEL_CFG_DST="${ICMPTUNNEL_DST_DIR}/${ROLE}/config.json"

if [ -x "${ICMPTUNNEL_BIN_SRC}" ] && [ -f "${ICMPTUNNEL_CFG_SRC}" ]; then
  mkdir -p "${ICMPTUNNEL_DST_DIR}/${ROLE}"
  cp -f "${ICMPTUNNEL_BIN_SRC}" "${ICMPTUNNEL_BIN_DST}"
  cp -f "${ICMPTUNNEL_CFG_SRC}" "${ICMPTUNNEL_CFG_DST}"
  chown root:icmptunnel "${ICMPTUNNEL_BIN_DST}" "${ICMPTUNNEL_CFG_DST}" 2>/dev/null || true
  chmod 750 "${ICMPTUNNEL_BIN_DST}" || true
  chmod 640 "${ICMPTUNNEL_CFG_DST}" || true
else
  echo "Warning: icmptunnel binary/config not found at ${ICMPTUNNEL_SRC_DIR}. Service may fail to start." >&2
fi

if ! command -v setcap >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get install -y libcap2-bin
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y libcap
  elif command -v yum >/dev/null 2>&1; then
    yum install -y libcap
  fi
fi
if [ -x "${ICMPTUNNEL_BIN_DST}" ] && command -v setcap >/dev/null 2>&1; then
  setcap cap_net_raw,cap_net_admin=ep "${ICMPTUNNEL_BIN_DST}" || true
fi

echo
echo "[DEBUG] Creating systemd drop-in configuration..."
UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
echo "[DEBUG] Drop-in directory: ${DROPIN_DIR}"
mkdir -p "${DROPIN_DIR}"

cat <<CONF > "${DROPIN_DIR}/10-warp.conf"
[Service]
User=icmptunnel
Group=icmptunnel
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true
WorkingDirectory=${ICMPTUNNEL_DST_DIR}/${ROLE}
ExecStart=
ExecStart=${ICMPTUNNEL_BIN_DST}
CONF

echo "[SUCCESS] Systemd drop-in created: ${DROPIN_DIR}/10-warp.conf"
echo "[DEBUG] Drop-in contents:"
cat "${DROPIN_DIR}/10-warp.conf" | sed 's/^/  /'

if [ -f "${UNIT}" ]; then
  echo "[INFO] Reloading systemd and restarting ${SERVICE_NAME}..."
  systemctl daemon-reload
  if systemctl restart "${SERVICE_NAME}.service"; then
    echo "[SUCCESS] Service restarted successfully"
  else
    echo "[WARN] Service restart failed (may be expected if not fully configured yet)" >&2
  fi
else
  echo "[INFO] ${SERVICE_NAME}.service not installed yet. WARP drop-in is prepared and will apply after service install."
fi

# Remove old uidrange rules
while ip rule show | grep -Eq "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}.*lookup (${TABLE_ID}|wgcf)"; do
  ip rule del uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID} table ${TABLE_ID} 2>/dev/null || ip rule del uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID} table wgcf 2>/dev/null || true
done

# Add uidrange rule that EXCLUDES ICMP protocol (only route TCP/UDP through WARP)
# CRITICAL: ICMP echo replies must go direct, not through WARP!

echo "[DEBUG] Starting ipproto support detection..."
echo "[DEBUG] iproute2 version: $(ip -V 2>/dev/null || echo 'unknown')"
echo "[DEBUG] icmptunnel UID: ${ICMPTUNNEL_UID}"
echo "[DEBUG] Routing table ID: ${TABLE_ID}"

# Check if ipproto is supported (pipefail-safe detection)
IPPROTO_SUPPORTED="false"
if command -v ip >/dev/null 2>&1; then
  echo "[DEBUG] ip command found, checking for ipproto support..."
  IP_HELP_OUTPUT="$(ip rule add help 2>&1 || true)"
  echo "[DEBUG] ip rule add help output (first 3 lines):"
  echo "${IP_HELP_OUTPUT}" | head -n 3 | sed 's/^/  /'

  if echo "${IP_HELP_OUTPUT}" | grep -q "ipproto"; then
    IPPROTO_SUPPORTED="true"
    echo "[DEBUG] ipproto support: DETECTED"
  else
    echo "[DEBUG] ipproto support: NOT FOUND"
  fi
else
  echo "[DEBUG] ip command not found"
fi

echo "[DEBUG] IPPROTO_SUPPORTED=${IPPROTO_SUPPORTED}"
echo

if [ "${IPPROTO_SUPPORTED}" = "true" ]; then
  # Modern iproute2 - can exclude ICMP
  echo "[INFO] Adding uidrange rule for TCP/UDP only (excluding ICMP)..."

  # Route TCP through WARP
  echo "[DEBUG] Adding TCP rule: ip rule add uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID} ipproto tcp table ${TABLE_ID}"
  if ip rule add uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID} ipproto tcp table ${TABLE_ID} 2>&1; then
    echo "[SUCCESS] TCP rule added"
  else
    echo "[ERROR] Failed to add TCP rule" >&2
  fi

  # Route UDP through WARP
  echo "[DEBUG] Adding UDP rule: ip rule add uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID} ipproto udp table ${TABLE_ID}"
  if ip rule add uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID} ipproto udp table ${TABLE_ID} 2>&1; then
    echo "[SUCCESS] UDP rule added"
  else
    echo "[ERROR] Failed to add UDP rule" >&2
  fi

  echo
  echo "[INFO] WARP routing: TCP/UDP only (ICMP excluded to preserve tunnel replies)"

  # Verify rules were added
  echo
  echo "[DEBUG] Verifying ip rules were added correctly..."
  echo "[DEBUG] Current ip rules matching uidrange ${ICMPTUNNEL_UID}:"
  ip rule show | grep -E "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}" | sed 's/^/  /' || echo "  (no matching rules found)"

  echo
  echo "[DEBUG] Full ip rule list:"
  ip rule show | sed 's/^/  /'
else
  # Fallback: old iproute2 doesn't support ipproto filter
  echo "[WARN] Cannot exclude ICMP from WARP (old iproute2 version)" >&2
  echo "[WARN] ICMP tunnel + WARP may not work properly on this system" >&2

  echo "[DEBUG] Adding fallback rule (all protocols): ip rule add uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID} table ${TABLE_ID}"
  if ip rule add uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID} table ${TABLE_ID} 2>&1; then
    echo "[INFO] uidrange rule added for icmptunnel user (${ICMPTUNNEL_UID}) - ALL protocols"
  else
    echo "[ERROR] uidrange rule not supported or failed to add." >&2
  fi

  echo
  echo "[DEBUG] Current ip rules matching uidrange ${ICMPTUNNEL_UID}:"
  ip rule show | grep -E "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}" | sed 's/^/  /' || echo "  (no matching rules found)"
fi

while ip rule show | grep -Eq "fwmark (0x0*ca6c|0x0000ca6c|${MARK}).*lookup (${TABLE_ID}|wgcf)"; do
  ip rule del fwmark ${MARK} table ${TABLE_ID} 2>/dev/null || ip rule del fwmark ${MARK_HEX} table ${TABLE_ID} 2>/dev/null || ip rule del fwmark 0xca6c table wgcf 2>/dev/null || true
done
while iptables -t mangle -D OUTPUT -m owner --uid-owner "${ICMPTUNNEL_UID}" -j MARK --set-mark ${MARK} 2>/dev/null; do :; done
while iptables -t mangle -D OUTPUT -m owner --uid-owner icmptunnel -j MARK --set-mark ${MARK} 2>/dev/null; do :; done
if command -v nft >/dev/null 2>&1; then
  while read -r handle; do
    [ -n "${handle}" ] && nft delete rule ip mangle OUTPUT handle "${handle}" 2>/dev/null || true
  done < <(nft -a list chain ip mangle OUTPUT 2>/dev/null | awk -v uid="${ICMPTUNNEL_UID}" '/skuid/ && /mark set/ && $0 ~ ("skuid " uid) {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1)}}')
  while read -r handle; do
    [ -n "${handle}" ] && nft delete rule inet mangle output handle "${handle}" 2>/dev/null || true
  done < <(nft -a list chain inet mangle output 2>/dev/null | awk -v uid="${ICMPTUNNEL_UID}" '/skuid/ && /mark set/ && $0 ~ ("skuid " uid) {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1)}}')
fi

echo "WARP routing mode: uidrange-only (no iptables rules - SSH approach)."
echo "Note: ICMP NOTRACK rules skipped (not needed, causes nftables conflicts)."

set_state "icmptunnel_warp_enabled" "1"

echo
echo "========================================="
echo "[SUCCESS] WARP binding enabled for ${SERVICE_NAME}"
echo "========================================="
echo
echo "[DEBUG] Final Configuration Summary:"
echo "  Service: ${SERVICE_NAME}"
echo "  User: icmptunnel (UID: ${ICMPTUNNEL_UID})"
echo "  Routing table: ${TABLE_ID} (wgcf)"
echo "  ipproto support: ${IPPROTO_SUPPORTED}"
echo
echo "[DEBUG] Active ip rules for uidrange ${ICMPTUNNEL_UID}:"
ip rule show | grep -E "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}" | sed 's/^/  /' || echo "  (none found - this is a problem!)"
echo
echo "[DEBUG] Service status:"
systemctl status "${SERVICE_NAME}.service" --no-pager -l | head -n 10 | sed 's/^/  /' || echo "  (service not running)"
echo
echo "========================================="
