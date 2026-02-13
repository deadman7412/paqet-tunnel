#!/usr/bin/env bash
set -euo pipefail

ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ICMP Tunnel Comprehensive Diagnostic${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo "This report can be shared with support for troubleshooting."
echo

# Section 1: System Info
echo -e "${BLUE}=== System Information ===${NC}"
echo "OS: $(uname -s)"
echo "Kernel: $(uname -r)"
echo "Arch: $(uname -m)"
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo

# Section 2: Binary Info
echo -e "${BLUE}=== Binary Information ===${NC}"
BIN_PATH="${ICMPTUNNEL_DIR}/icmptunnel"
if [ -x "${BIN_PATH}" ]; then
  echo -e "${GREEN}[OK]${NC} Binary found: ${BIN_PATH}"
  ls -lh "${BIN_PATH}"
  echo "Size: $(stat -c%s "${BIN_PATH}" 2>/dev/null || stat -f%z "${BIN_PATH}" 2>/dev/null || echo "unknown") bytes"
else
  echo -e "${RED}[ERROR]${NC} Binary not found or not executable: ${BIN_PATH}"
fi
echo

# Section 3: Configuration
echo -e "${BLUE}=== Configuration Files ===${NC}"
for role in server client; do
  CONFIG_FILE="${ICMPTUNNEL_DIR}/${role}/config.json"
  if [ -f "${CONFIG_FILE}" ]; then
    echo -e "${GREEN}[OK]${NC} ${role} config found: ${CONFIG_FILE}"
    echo "Contents:"
    cat "${CONFIG_FILE}" | python3 -m json.tool 2>/dev/null || cat "${CONFIG_FILE}"
  else
    echo -e "${YELLOW}[WARN]${NC} ${role} config not found: ${CONFIG_FILE}"
  fi
  echo
done

# Section 4: Network Info
echo -e "${BLUE}=== Network Information ===${NC}"
PUBLIC_IP=""
if command -v curl >/dev/null 2>&1; then
  PUBLIC_IP="$(curl -fsS --connect-timeout 3 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
fi
if [ -z "${PUBLIC_IP}" ] && command -v wget >/dev/null 2>&1; then
  PUBLIC_IP="$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || true)"
fi
echo "Public IP: ${PUBLIC_IP:-Unable to detect}"
echo

# Section 5: Service Status
echo -e "${BLUE}=== Service Status ===${NC}"
for role in server client; do
  SERVICE_NAME="icmptunnel-${role}"
  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
      echo -e "${GREEN}[ACTIVE]${NC} ${SERVICE_NAME}"
    else
      echo -e "${RED}[INACTIVE]${NC} ${SERVICE_NAME}"
    fi
    systemctl status "${SERVICE_NAME}.service" --no-pager -l || true
  else
    echo -e "${YELLOW}[NOT INSTALLED]${NC} ${SERVICE_NAME}"
  fi
  echo
done

# Section 6: Port Listening Status
echo -e "${BLUE}=== Port Listening Status ===${NC}"
if command -v ss >/dev/null 2>&1; then
  echo "TCP listening ports (ICMP Tunnel related):"
  ss -ltn | grep -E "(1010|8080)" || echo "  No related ports found"
else
  echo "ss command not available"
fi
echo

# Section 7: WARP Status
echo -e "${BLUE}=== WARP Status ===${NC}"
if [ -f /etc/wireguard/wgcf.conf ]; then
  echo -e "${GREEN}[OK]${NC} WARP core installed"
  if ip link show wgcf >/dev/null 2>&1; then
    echo -e "${GREEN}[ACTIVE]${NC} wgcf interface is up"
  else
    echo -e "${RED}[INACTIVE]${NC} wgcf interface is down"
  fi

  if id -u icmptunnel >/dev/null 2>&1; then
    ICMPTUNNEL_UID="$(id -u icmptunnel)"
    echo "icmptunnel user exists (UID: ${ICMPTUNNEL_UID})"

    if ip rule show | grep -q "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}"; then
      echo -e "${GREEN}[OK]${NC} WARP uidrange rule exists"
    else
      echo -e "${YELLOW}[WARN]${NC} WARP uidrange rule NOT found"
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} icmptunnel user does not exist (WARP not enabled)"
  fi
else
  echo -e "${YELLOW}[WARN]${NC} WARP core not installed"
fi
echo

# Section 8: DNS Policy Status
echo -e "${BLUE}=== DNS Policy Status ===${NC}"
if [ -f /etc/dnsmasq.d/paqet-dns-policy.conf ]; then
  echo -e "${GREEN}[OK]${NC} DNS policy core installed"
  if systemctl is-active --quiet dnsmasq; then
    echo -e "${GREEN}[ACTIVE]${NC} dnsmasq is running"
  else
    echo -e "${RED}[INACTIVE]${NC} dnsmasq is not running"
  fi

  if id -u icmptunnel >/dev/null 2>&1; then
    ICMPTUNNEL_UID="$(id -u icmptunnel)"
    DNS_RULES="$(iptables -t nat -L OUTPUT -n -v 2>/dev/null | grep -c "owner UID match ${ICMPTUNNEL_UID}" || echo "0")"
    if [ "${DNS_RULES}" -gt 0 ]; then
      echo -e "${GREEN}[OK]${NC} DNS policy iptables rules exist (${DNS_RULES} rules)"
    else
      echo -e "${YELLOW}[WARN]${NC} DNS policy iptables rules NOT found"
    fi
  fi
else
  echo -e "${YELLOW}[WARN]${NC} DNS policy core not installed"
fi
echo

# Section 9: Firewall Rules
echo -e "${BLUE}=== Firewall Rules ===${NC}"
if command -v ufw >/dev/null 2>&1; then
  UFW_STATUS="$(ufw status 2>/dev/null | head -n1 || true)"
  echo "UFW Status: ${UFW_STATUS}"
  echo
  echo "ICMP Tunnel related rules:"
  ufw status numbered 2>/dev/null | grep -i icmptunnel || echo "  No ICMP Tunnel rules found"
else
  echo "UFW not installed"
fi
echo

echo "iptables rules (ICMP Tunnel related):"
echo "Raw table (NOTRACK):"
iptables -t raw -L -n -v 2>/dev/null | grep -i icmptunnel || echo "  No rules found"
echo
echo "NAT table (DNS redirect):"
iptables -t nat -L OUTPUT -n -v 2>/dev/null | grep -i icmptunnel || echo "  No rules found"
echo

# Section 10: Recent Logs
echo -e "${BLUE}=== Recent Service Logs ===${NC}"
for role in server client; do
  SERVICE_NAME="icmptunnel-${role}"
  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    echo "Last 20 lines from ${SERVICE_NAME}:"
    journalctl -u "${SERVICE_NAME}.service" -n 20 --no-pager 2>/dev/null || echo "  No logs available"
    echo
  fi
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Diagnostic Complete${NC}"
echo -e "${BLUE}========================================${NC}"
