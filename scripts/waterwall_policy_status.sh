#!/usr/bin/env bash
set -euo pipefail

WATERWALL_POLICY_STATE_FILE="/etc/waterwall-policy/settings.env"
TABLE_ID=51820
DNS_PORT=5353

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

get_setting() {
  local key="$1"
  if [ -f "${WATERWALL_POLICY_STATE_FILE}" ]; then
    awk -F= -v k="${key}" '$1==k {print $2; exit}' "${WATERWALL_POLICY_STATE_FILE}" 2>/dev/null || true
  fi
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Waterwall Routing Policy Status${NC}"
echo -e "${BLUE}========================================${NC}"
echo

if ! id -u waterwall >/dev/null 2>&1; then
  echo -e "${YELLOW}[WARN]${NC} waterwall user does not exist"
  echo "WARP and DNS routing require the waterwall user."
  echo "Enable WARP binding to create the user automatically."
  exit 0
fi

WATERWALL_UID="$(id -u waterwall)"
echo -e "${BLUE}Waterwall User:${NC}"
echo "  Username: waterwall"
echo "  UID: ${WATERWALL_UID}"
echo

warp_enabled="$(get_setting "waterwall_warp_enabled")"
echo -e "${BLUE}WARP Binding Status:${NC}"
if [ "${warp_enabled}" = "1" ]; then
  echo -e "  State: ${GREEN}[ENABLED]${NC}"
else
  echo -e "  State: ${RED}[DISABLED]${NC}"
fi

if [ -f /etc/wireguard/wgcf.conf ]; then
  echo -e "  WARP core: ${GREEN}[INSTALLED]${NC}"
  if ip link show wgcf >/dev/null 2>&1; then
    echo -e "  wgcf interface: ${GREEN}[ACTIVE]${NC}"
  else
    echo -e "  wgcf interface: ${RED}[INACTIVE]${NC}"
  fi
else
  echo -e "  WARP core: ${RED}[NOT INSTALLED]${NC}"
fi

if ip rule show | grep -Eq "uidrange ${WATERWALL_UID}-${WATERWALL_UID}.*lookup (${TABLE_ID}|wgcf)"; then
  echo -e "  UID routing rule: ${GREEN}[ACTIVE]${NC}"
  ip rule show | grep -E "uidrange ${WATERWALL_UID}-${WATERWALL_UID}.*lookup (${TABLE_ID}|wgcf)" | sed 's/^/    /'
else
  echo -e "  UID routing rule: ${RED}[NOT FOUND]${NC}"
fi

if [ -f /etc/systemd/system/waterwall-direct-server.service.d/10-warp.conf ]; then
  echo -e "  systemd drop-in: ${GREEN}[PRESENT]${NC}"
  echo "    /etc/systemd/system/waterwall-direct-server.service.d/10-warp.conf"
else
  echo -e "  systemd drop-in: ${YELLOW}[NOT PRESENT]${NC}"
fi

echo

dns_enabled="$(get_setting "waterwall_dns_enabled")"
echo -e "${BLUE}DNS Policy Binding Status:${NC}"
if [ "${dns_enabled}" = "1" ]; then
  echo -e "  State: ${GREEN}[ENABLED]${NC}"
else
  echo -e "  State: ${RED}[DISABLED]${NC}"
fi

if [ -f /etc/dnsmasq.d/paqet-dns-policy.conf ]; then
  echo -e "  DNS core: ${GREEN}[INSTALLED]${NC}"
  if systemctl is-active --quiet dnsmasq 2>/dev/null; then
    echo -e "  dnsmasq: ${GREEN}[ACTIVE]${NC}"
  else
    echo -e "  dnsmasq: ${RED}[INACTIVE]${NC}"
  fi
else
  echo -e "  DNS core: ${RED}[NOT INSTALLED]${NC}"
fi

nat_rules_count="$(iptables -t nat -S OUTPUT 2>/dev/null | grep -c "waterwall-dns-policy" || true)"
if [ "${nat_rules_count}" -gt 0 ]; then
  echo -e "  iptables NAT rules: ${GREEN}[ACTIVE]${NC} (${nat_rules_count} rules)"
  iptables -t nat -S OUTPUT 2>/dev/null | grep "waterwall-dns-policy" | sed 's/^/    /'
else
  echo -e "  iptables NAT rules: ${RED}[NOT FOUND]${NC}"
fi

echo
echo -e "${BLUE}========================================${NC}"
