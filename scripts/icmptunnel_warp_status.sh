#!/usr/bin/env bash
set -euo pipefail

ICMPTUNNEL_POLICY_STATE_FILE="/etc/icmptunnel-policy/settings.env"
TABLE_ID=51820

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}ICMP Tunnel WARP Status${NC}"
echo -e "${BLUE}===================================${NC}"
echo

# Check WARP core
echo -e "${BLUE}WARP Core:${NC}"
if [ -f /etc/wireguard/wgcf.conf ]; then
  echo -e "  ${GREEN}[INSTALLED]${NC} WARP core is installed"

  if ip link show wgcf >/dev/null 2>&1; then
    echo -e "  ${GREEN}[ACTIVE]${NC} wgcf interface is up"
  else
    echo -e "  ${RED}[INACTIVE]${NC} wgcf interface is down"
  fi

  if ip route show table ${TABLE_ID} 2>/dev/null | grep -q '^default '; then
    echo -e "  ${GREEN}[OK]${NC} Routing table ${TABLE_ID} has default route"
  else
    echo -e "  ${RED}[ERROR]${NC} Routing table ${TABLE_ID} missing default route"
  fi
else
  echo -e "  ${RED}[NOT INSTALLED]${NC} WARP core is not installed"
  echo
  echo "Install with: WARP/DNS core -> WARP Configuration -> Install WARP core"
  exit 0
fi
echo

# Check icmptunnel user
echo -e "${BLUE}ICMP Tunnel User:${NC}"
if id -u icmptunnel >/dev/null 2>&1; then
  ICMPTUNNEL_UID="$(id -u icmptunnel)"
  echo -e "  ${GREEN}[OK]${NC} icmptunnel user exists (UID: ${ICMPTUNNEL_UID})"
else
  echo -e "  ${YELLOW}[NOT CONFIGURED]${NC} icmptunnel user does not exist"
  echo "  WARP policy not enabled for ICMP Tunnel"
  echo
  echo "Enable with: WARP/DNS core -> WARP Configuration -> Apply WARP rule -> icmptunnel"
  exit 0
fi
echo

# Check uidrange rules
echo -e "${BLUE}uidrange Rules:${NC}"
if ip rule show | grep -q "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}"; then
  RULE_DETAIL="$(ip rule show | grep "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}")"
  echo -e "  ${GREEN}[OK]${NC} uidrange rule exists"
  echo "  ${RULE_DETAIL}"
else
  echo -e "  ${RED}[ERROR]${NC} uidrange rule NOT found"
  echo "  WARP routing may not work"
fi
echo

# Check systemd drop-in
echo -e "${BLUE}Service Configuration:${NC}"
for role in server client; do
  DROPIN="/etc/systemd/system/icmptunnel-${role}.service.d/10-warp.conf"
  if [ -f "${DROPIN}" ]; then
    echo -e "  ${GREEN}[OK]${NC} icmptunnel-${role}: WARP drop-in exists"
  else
    echo -e "  ${YELLOW}[WARN]${NC} icmptunnel-${role}: WARP drop-in not found"
  fi
done
echo

# Check state file
echo -e "${BLUE}State File:${NC}"
if [ -f "${ICMPTUNNEL_POLICY_STATE_FILE}" ]; then
  WARP_ENABLED="$(awk -F= '/^icmptunnel_warp_enabled=/{print $2}' "${ICMPTUNNEL_POLICY_STATE_FILE}" 2>/dev/null || echo "0")"
  if [ "${WARP_ENABLED}" = "1" ]; then
    echo -e "  ${GREEN}[ENABLED]${NC} WARP policy is enabled (state file)"
  else
    echo -e "  ${RED}[DISABLED]${NC} WARP policy is disabled (state file)"
  fi
  echo "  State file: ${ICMPTUNNEL_POLICY_STATE_FILE}"
else
  echo -e "  ${YELLOW}[WARN]${NC} State file not found"
fi
echo

echo -e "${BLUE}===================================${NC}"
echo "To enable WARP:"
echo "  Menu -> WARP/DNS core -> WARP Configuration -> Apply WARP rule -> icmptunnel"
echo
echo "To disable WARP:"
echo "  Menu -> WARP/DNS core -> WARP Configuration -> Remove WARP rule -> icmptunnel"
