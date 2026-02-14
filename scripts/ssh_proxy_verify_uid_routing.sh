#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

echo -e "${BLUE}=== SSH PROXY UID ROUTING VERIFICATION ===${NC}"
echo
echo "This checks if SSH connections actually run as the authenticated user's UID."
echo

# Get SSH proxy user
usernames="$(ssh_proxy_list_usernames || true)"
if [ -z "${usernames}" ]; then
  echo -e "${RED}[ERROR]${NC} No SSH proxy users found"
  exit 1
fi

test_user="$(echo "${usernames}" | head -1)"
test_uid="$(id -u "${test_user}")"

echo -e "${BLUE}[INFO]${NC} Testing with user: ${test_user} (UID: ${test_uid})"
echo

# Check current SSH processes
echo -e "${BLUE}[1/4] Checking current SSH processes...${NC}"
echo "Looking for sshd processes running as UID ${test_uid}:"
ps aux | grep "sshd.*${test_user}" | grep -v grep || echo "  No active SSH sessions for ${test_user}"
echo

# Check iptables rules
echo -e "${BLUE}[2/4] Checking iptables NAT rules for UID ${test_uid}...${NC}"
if iptables -t nat -L OUTPUT -n -v 2>/dev/null | grep "owner UID match ${test_uid}"; then
  echo -e "${GREEN}[OK]${NC} NAT redirect rules exist for UID ${test_uid}"
else
  echo -e "${RED}[ERROR]${NC} No NAT redirect rules found for UID ${test_uid}"
fi
echo

# Test DNS resolution as user
echo -e "${BLUE}[3/4] Testing DNS resolution as user ${test_user}...${NC}"
echo "Query: digikala.com"
result="$(sudo -u "${test_user}" nslookup digikala.com 2>&1 | grep -A1 "Name:" | tail -1 || echo "query failed")"
if echo "${result}" | grep -q "0.0.0.0"; then
  echo -e "${GREEN}[OK]${NC} DNS returns 0.0.0.0 (blocked)"
else
  echo -e "${RED}[ERROR]${NC} DNS does NOT return 0.0.0.0"
  echo "Result: ${result}"
fi
echo

# Explain the issue
echo -e "${BLUE}[4/4] Understanding SSH SOCKS Proxy UID Behavior...${NC}"
echo
echo "CRITICAL FINDING:"
echo "When you connect via SSH SOCKS proxy (ssh -D), the DNS queries"
echo "are made by the SSH CLIENT, not the server!"
echo
echo "Flow:"
echo "  1. Phone browser → SOCKS proxy on phone"
echo "  2. SOCKS proxy → SSH client on phone"
echo "  3. SSH client sends request to SSH server"
echo "  4. SSH server makes connection as user UID ${test_uid}"
echo "  5. But DNS query happens on PHONE, not on server!"
echo
echo -e "${YELLOW}[ISSUE]${NC} DNS blocking on the server won't work because:"
echo "  - The phone resolves DNS locally (not through server)"
echo "  - Only the TCP connection goes through the server"
echo "  - The phone's DNS isn't redirected to your dnsmasq"
echo
echo -e "${BLUE}[SOLUTION]${NC} To block Iranian sites via SSH proxy:"
echo "  1. Use IP-based blocking (not DNS-based)"
echo "  2. Or configure the phone to use server as DNS"
echo "  3. Or use a VPN instead of SSH SOCKS proxy"
echo
echo "Testing the ACTUAL connection behavior:"
echo "  Run this while connected from your phone:"
echo "    sudo tcpdump -i any -n port 53"
echo "  Then browse to digikala.com on phone"
echo "  You'll see NO DNS queries on the server!"
