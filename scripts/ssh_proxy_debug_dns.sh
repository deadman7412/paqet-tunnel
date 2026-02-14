#!/usr/bin/env bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

DNS_PORT=5353
DNS_POLICY_DIR="/etc/paqet-dns-policy"
DNSMASQ_BLOCK_CONF="/etc/dnsmasq.d/paqet-dns-policy-blocklist.conf"
META_FILE="${DNS_POLICY_DIR}/last_update"

echo "=== SSH PROXY DNS ROUTING DIAGNOSTIC ==="
echo

# Check 1: DNS policy core status
echo -e "${BLUE}[1/7] Checking DNS policy core installation...${NC}"
if [ -f "${DNSMASQ_BLOCK_CONF}" ]; then
  echo -e "${GREEN}[OK]${NC} DNS blocklist config exists"

  # Count domains
  if [ -f "${DNSMASQ_BLOCK_CONF}" ]; then
    COUNT="$(grep -c '^address=/' "${DNSMASQ_BLOCK_CONF}" 2>/dev/null || echo "0")"
    DOMAINS=$(( COUNT / 2 ))
    if [ "${DOMAINS}" -gt 0 ]; then
      echo -e "${GREEN}[OK]${NC} Blocklist loaded: ${DOMAINS} domains"
    else
      echo -e "${RED}[ERROR]${NC} Blocklist is EMPTY!"
      echo "  Run: sudo ~/paqet_tunnel/scripts/update_dns_policy_list.sh all"
    fi
  fi

  # Show metadata
  if [ -f "${META_FILE}" ]; then
    echo "  Last update info:"
    cat "${META_FILE}" | sed 's/^/    /'

    # Suggest lighter categories if using "all"
    CATEGORY="$(grep '^category=' "${META_FILE}" 2>/dev/null | cut -d= -f2 || echo "unknown")"
    if [ "${CATEGORY}" = "all" ] && [ "${DOMAINS}" -gt 100000 ]; then
      echo
      echo -e "  ${YELLOW}[OPTIMIZATION TIP]${NC} You're using 'all' category (${DOMAINS} domains)"
      echo "  Consider lighter options:"
      echo "    - 'ads': Only block ads/tracking (much smaller)"
      echo "    - 'proxy': Only block proxy-related domains"
      echo "  Change: DNS Configuration -> Update DNS policy list now"
    fi
  fi
else
  echo -e "${RED}[ERROR]${NC} DNS policy core is NOT installed"
  echo "  Run: Paqet Tunnel -> WARP/DNS core -> Install DNS policy core"
  exit 1
fi
echo

# Check 2: dnsmasq service
echo -e "${BLUE}[2/7] Checking dnsmasq service...${NC}"
if systemctl is-active --quiet dnsmasq 2>/dev/null; then
  echo -e "${GREEN}[OK]${NC} dnsmasq is active"
else
  echo -e "${RED}[ERROR]${NC} dnsmasq is NOT running!"
  echo "  Run: sudo systemctl start dnsmasq"
  exit 1
fi
echo

# Check 3: Test DNS resolver
echo -e "${BLUE}[3/7] Testing DNS resolver on port ${DNS_PORT}...${NC}"
if command -v nslookup >/dev/null 2>&1; then
  # Test a known Iranian domain (if in blocklist)
  TEST_DOMAIN="google.com"
  if nslookup -port="${DNS_PORT}" "${TEST_DOMAIN}" 127.0.0.1 >/dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} DNS resolver is responding"

    # Test if a domain is blocked
    TEST_IR_DOMAIN="digikala.com"  # Common Iranian e-commerce site
    RESULT="$(nslookup -port="${DNS_PORT}" "${TEST_IR_DOMAIN}" 127.0.0.1 2>&1 || true)"
    if echo "${RESULT}" | grep -q "0.0.0.0"; then
      echo -e "${GREEN}[OK]${NC} Blocklist is working (${TEST_IR_DOMAIN} returns 0.0.0.0)"
    else
      echo -e "${YELLOW}[WARN]${NC} Test domain ${TEST_IR_DOMAIN} is not blocked"
      echo "  This might be normal if it's not in the blocklist"
    fi
  else
    echo -e "${RED}[ERROR]${NC} DNS resolver is NOT responding on port ${DNS_PORT}"
    echo "  Check dnsmasq logs: sudo journalctl -u dnsmasq -n 50"
  fi
else
  echo -e "${YELLOW}[WARN]${NC} nslookup not installed, skipping resolver test"
  echo "  Install: sudo apt-get install dnsutils"
fi
echo

# Check 4: SSH proxy users
echo -e "${BLUE}[4/7] Checking SSH proxy users...${NC}"
usernames="$(ssh_proxy_list_usernames || true)"
if [ -z "${usernames}" ]; then
  echo -e "${YELLOW}[WARN]${NC} No SSH proxy users found"
  echo "  Create one first: Paqet Tunnel -> SSH Proxy -> Create new user"
  exit 0
fi

USER_COUNT=0
while IFS= read -r user; do
  [ -z "${user}" ] && continue
  if id -u "${user}" >/dev/null 2>&1; then
    USER_COUNT=$((USER_COUNT + 1))
  fi
done <<< "${usernames}"

echo -e "${GREEN}[OK]${NC} Found ${USER_COUNT} SSH proxy user(s)"
echo

# Check 5: iptables DNS redirect rules
echo -e "${BLUE}[5/7] Checking iptables DNS redirect rules...${NC}"
RULE_COUNT=0
while IFS= read -r user; do
  [ -z "${user}" ] && continue
  if ! id -u "${user}" >/dev/null 2>&1; then
    continue
  fi

  uid="$(id -u "${user}")"
  echo "  User: ${user} (UID: ${uid})"

  # Check for UDP redirect rule
  if iptables -t nat -S OUTPUT 2>/dev/null | grep -q "uid-owner ${uid}.*dport 53.*udp.*REDIRECT.*${DNS_PORT}"; then
    echo -e "    ${GREEN}[OK]${NC} UDP DNS redirect rule exists"
    RULE_COUNT=$((RULE_COUNT + 1))
  else
    echo -e "    ${RED}[ERROR]${NC} UDP DNS redirect rule MISSING"
  fi

  # Check for TCP redirect rule
  if iptables -t nat -S OUTPUT 2>/dev/null | grep -q "uid-owner ${uid}.*dport 53.*tcp.*REDIRECT.*${DNS_PORT}"; then
    echo -e "    ${GREEN}[OK]${NC} TCP DNS redirect rule exists"
    RULE_COUNT=$((RULE_COUNT + 1))
  else
    echo -e "    ${RED}[ERROR]${NC} TCP DNS redirect rule MISSING"
  fi
done <<< "${usernames}"

if [ "${RULE_COUNT}" -eq 0 ]; then
  echo -e "${RED}[ERROR]${NC} No iptables DNS redirect rules found!"
  echo "  Run: Paqet Tunnel -> SSH Proxy -> Enable DNS routing"
fi
echo

# Check 6: DNS settings in state DB
echo -e "${BLUE}[6/7] Checking DNS routing status in settings...${NC}"
DNS_ENABLED="$(ssh_proxy_get_setting "dns_enabled" || echo "0")"
if [ "${DNS_ENABLED}" = "1" ]; then
  echo -e "${GREEN}[OK]${NC} DNS routing is marked as enabled in settings"
else
  echo -e "${YELLOW}[WARN]${NC} DNS routing is NOT marked as enabled in settings"
  echo "  This might indicate incomplete setup"
fi
echo

# Check 7: Identify DNS bypass risks
echo -e "${BLUE}[7/7] Checking for DNS bypass risks...${NC}"
echo -e "${YELLOW}[INFO]${NC} Current setup only blocks standard DNS (port 53)"
echo "  ${YELLOW}[WARNING]${NC} The following can BYPASS DNS blocking:"
echo "    - DoH (DNS over HTTPS) - uses port 443"
echo "    - DoT (DNS over TLS) - uses port 853"
echo "    - Hardcoded IP addresses (no DNS lookup)"
echo "    - Applications with built-in DNS resolvers"
echo
echo "  To fully block these bypasses, you need additional firewall rules."
echo "  See: https://github.com/bootmortis/iran-hosted-domains for IP ranges"
echo

# Summary
echo "=== SUMMARY ==="
if [ "${DOMAINS}" -gt 0 ] && systemctl is-active --quiet dnsmasq 2>/dev/null && [ "${RULE_COUNT}" -gt 0 ]; then
  echo -e "${GREEN}[SUCCESS]${NC} DNS routing is properly configured"
  echo
  echo "If Iranian sites are still accessible, the most likely cause is:"
  echo "  1. Client using DoH/DoT (encrypted DNS bypass)"
  echo "  2. Sites accessed via IP addresses instead of domain names"
  echo "  3. Sites not in the bootmortis blocklist"
  echo
  echo "To test, try accessing a known Iranian site:"
  echo "  curl --interface <ssh-proxy-interface> http://digikala.com"
else
  echo -e "${RED}[FAILURE]${NC} DNS routing has configuration issues"
  echo "Review the errors above and fix them"
fi
