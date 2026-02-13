#!/usr/bin/env bash
set -euo pipefail

ICMPTUNNEL_POLICY_STATE_FILE="/etc/icmptunnel-policy/settings.env"
DNS_PORT=5353

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}ICMP Tunnel DNS Policy Status${NC}"
echo -e "${BLUE}===================================${NC}"
echo

# Check DNS core
echo -e "${BLUE}DNS Policy Core:${NC}"
if [ -f /etc/dnsmasq.d/paqet-dns-policy.conf ]; then
  echo -e "  ${GREEN}[INSTALLED]${NC} DNS policy core is installed"

  if systemctl is-active --quiet dnsmasq 2>/dev/null; then
    echo -e "  ${GREEN}[ACTIVE]${NC} dnsmasq service is running"
  else
    echo -e "  ${RED}[INACTIVE]${NC} dnsmasq service is not running"
  fi

  if ss -lun 2>/dev/null | grep -q ":${DNS_PORT} "; then
    echo -e "  ${GREEN}[OK]${NC} DNS resolver listening on port ${DNS_PORT}"
  else
    echo -e "  ${RED}[ERROR]${NC} DNS resolver NOT listening on port ${DNS_PORT}"
  fi
else
  echo -e "  ${RED}[NOT INSTALLED]${NC} DNS policy core is not installed"
  echo
  echo "Install with: WARP/DNS core -> DNS Configuration -> Install DNS policy core"
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
  echo "  DNS policy not enabled for ICMP Tunnel"
  echo
  echo "Enable with: WARP/DNS core -> DNS Configuration -> Apply DNS rule -> icmptunnel"
  exit 0
fi
echo

# Check iptables NAT rules
echo -e "${BLUE}iptables NAT Rules:${NC}"
DNS_RULE_COUNT="$(iptables -t nat -L OUTPUT -n -v 2>/dev/null | grep -c "owner UID match ${ICMPTUNNEL_UID}" || echo "0")"
if [ "${DNS_RULE_COUNT}" -gt 0 ]; then
  echo -e "  ${GREEN}[OK]${NC} DNS redirect rules exist (${DNS_RULE_COUNT} rules)"
  echo
  echo "  Rules:"
  iptables -t nat -L OUTPUT -n -v 2>/dev/null | grep "owner UID match ${ICMPTUNNEL_UID}" | sed 's/^/    /'
else
  echo -e "  ${RED}[ERROR]${NC} DNS redirect rules NOT found"
  echo "  DNS policy may not work"
fi
echo

# Check state file
echo -e "${BLUE}State File:${NC}"
if [ -f "${ICMPTUNNEL_POLICY_STATE_FILE}" ]; then
  DNS_ENABLED="$(awk -F= '/^icmptunnel_dns_enabled=/{print $2}' "${ICMPTUNNEL_POLICY_STATE_FILE}" 2>/dev/null || echo "0")"
  if [ "${DNS_ENABLED}" = "1" ]; then
    echo -e "  ${GREEN}[ENABLED]${NC} DNS policy is enabled (state file)"
  else
    echo -e "  ${RED}[DISABLED]${NC} DNS policy is disabled (state file)"
  fi
  echo "  State file: ${ICMPTUNNEL_POLICY_STATE_FILE}"
else
  echo -e "  ${YELLOW}[WARN]${NC} State file not found"
fi
echo

echo -e "${BLUE}===================================${NC}"
echo "To enable DNS policy:"
echo "  Menu -> WARP/DNS core -> DNS Configuration -> Apply DNS rule -> icmptunnel"
echo
echo "To disable DNS policy:"
echo "  Menu -> WARP/DNS core -> DNS Configuration -> Remove DNS rule -> icmptunnel"
