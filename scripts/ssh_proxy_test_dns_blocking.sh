#!/usr/bin/env bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

DNS_PORT=5353

# Test domains
BLOCKED_DOMAINS=(
  "digikala.com"      # Iranian e-commerce
  "divar.ir"          # Iranian classifieds
  "irancell.ir"       # Iranian telecom
)

ALLOWED_DOMAINS=(
  "google.com"
  "cloudflare.com"
  "github.com"
)

test_dns_resolution() {
  local user="$1"
  local domain="$2"
  local expected_blocked="$3"  # 1 if should be blocked, 0 if allowed
  local result=""

  # Test DNS resolution as the SSH proxy user
  result="$(sudo -u "${user}" nslookup "${domain}" 2>&1 || true)"

  if echo "${result}" | grep -q "0.0.0.0"; then
    # Domain is blocked
    if [ "${expected_blocked}" = "1" ]; then
      echo -e "  ${GREEN}[PASS]${NC} ${domain} → 0.0.0.0 (blocked as expected)"
      return 0
    else
      echo -e "  ${RED}[FAIL]${NC} ${domain} → 0.0.0.0 (should NOT be blocked)"
      return 1
    fi
  else
    # Domain is not blocked
    if [ "${expected_blocked}" = "0" ]; then
      echo -e "  ${GREEN}[PASS]${NC} ${domain} → resolved (allowed as expected)"
      return 0
    else
      echo -e "  ${RED}[FAIL]${NC} ${domain} → resolved (should be BLOCKED)"
      return 1
    fi
  fi
}

test_http_connection() {
  local user="$1"
  local url="$2"
  local expected_blocked="$3"
  local result=""
  local curl_exit_code=0

  # Test HTTP connection as the SSH proxy user
  result="$(sudo -u "${user}" curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "${url}" 2>/dev/null || echo "FAILED")"
  curl_exit_code=$?

  # Check if connection failed (000, FAILED, or non-zero exit code)
  if [ "${result}" = "000" ] || [ "${result}" = "FAILED" ] || [ "${curl_exit_code}" -ne 0 ] || [[ "${result}" =~ ^0+$ ]]; then
    # Connection failed
    if [ "${expected_blocked}" = "1" ]; then
      echo -e "  ${GREEN}[PASS]${NC} ${url} → connection failed (blocked as expected)"
      return 0
    else
      echo -e "  ${YELLOW}[WARN]${NC} ${url} → connection failed (should work)"
      return 1
    fi
  else
    # Connection succeeded (got HTTP response code)
    if [ "${expected_blocked}" = "0" ]; then
      echo -e "  ${GREEN}[PASS]${NC} ${url} → HTTP ${result} (allowed as expected)"
      return 0
    else
      echo -e "  ${RED}[FAIL]${NC} ${url} → HTTP ${result} (should be BLOCKED)"
      return 1
    fi
  fi
}

monitor_dns_queries() {
  local user="$1"
  local domain="$2"

  echo -e "${BLUE}[INFO]${NC} Monitoring dnsmasq logs (press Ctrl+C to stop)..."
  echo -e "${BLUE}[INFO]${NC} Testing ${domain} as user ${user}..."
  echo

  # Start monitoring in background
  sudo journalctl -u dnsmasq -f --no-hostname -n 0 &
  local monitor_pid=$!

  # Give journalctl time to start
  sleep 1

  # Trigger DNS query
  sudo -u "${user}" nslookup "${domain}" >/dev/null 2>&1 || true

  # Wait a bit for logs
  sleep 2

  # Stop monitoring
  kill "${monitor_pid}" 2>/dev/null || true
}

main() {
  local usernames=""
  local user=""
  local test_user=""
  local passed=0
  local failed=0
  local domain=""

  ssh_proxy_require_root

  echo -e "${BLUE}=== SSH PROXY DNS BLOCKING TEST ===${NC}"
  echo

  # Get SSH proxy users
  usernames="$(ssh_proxy_list_usernames || true)"
  if [ -z "${usernames}" ]; then
    echo -e "${RED}[ERROR]${NC} No SSH proxy users found"
    echo "Create SSH proxy users first: SSH Proxy -> Create SSH proxy user"
    exit 1
  fi

  # Select first user for testing
  test_user="$(echo "${usernames}" | head -1)"
  echo -e "${BLUE}[INFO]${NC} Testing with user: ${test_user}"
  echo

  # Check if nslookup is available
  if ! command -v nslookup >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN]${NC} nslookup not installed, installing dnsutils..."
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -qq && apt-get install -y dnsutils
    fi
  fi

  # Test 1: DNS Resolution - Blocked Domains
  echo -e "${BLUE}[TEST 1/4] DNS Resolution - Iranian Domains (should be blocked)${NC}"
  for domain in "${BLOCKED_DOMAINS[@]}"; do
    if test_dns_resolution "${test_user}" "${domain}" 1; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
  done
  echo

  # Test 2: DNS Resolution - Allowed Domains
  echo -e "${BLUE}[TEST 2/4] DNS Resolution - International Domains (should be allowed)${NC}"
  for domain in "${ALLOWED_DOMAINS[@]}"; do
    if test_dns_resolution "${test_user}" "${domain}" 0; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
  done
  echo

  # Test 3: HTTP Connection - Blocked Sites
  echo -e "${BLUE}[TEST 3/4] HTTP Connection - Iranian Sites (should fail)${NC}"
  if command -v curl >/dev/null 2>&1; then
    for domain in "${BLOCKED_DOMAINS[@]}"; do
      if test_http_connection "${test_user}" "http://${domain}" 1; then
        passed=$((passed + 1))
      else
        failed=$((failed + 1))
      fi
    done
  else
    echo -e "${YELLOW}[SKIP]${NC} curl not installed, skipping HTTP tests"
  fi
  echo

  # Test 4: HTTP Connection - Allowed Sites
  echo -e "${BLUE}[TEST 4/4] HTTP Connection - International Sites (should work)${NC}"
  if command -v curl >/dev/null 2>&1; then
    for domain in "${ALLOWED_DOMAINS[@]}"; do
      if test_http_connection "${test_user}" "http://${domain}" 0; then
        passed=$((passed + 1))
      else
        failed=$((failed + 1))
      fi
    done
  else
    echo -e "${YELLOW}[SKIP]${NC} curl not installed, skipping HTTP tests"
  fi
  echo

  # Summary
  echo -e "${BLUE}=== TEST SUMMARY ===${NC}"
  echo "Passed: ${passed}"
  echo "Failed: ${failed}"
  echo

  if [ "${failed}" -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} All tests passed! DNS blocking is working correctly."
    echo
    echo "What this means:"
    echo "  - Iranian domains resolve to 0.0.0.0 (blocked)"
    echo "  - International domains resolve normally (allowed)"
    echo "  - HTTP connections to Iranian sites fail (blocked)"
    echo "  - HTTP connections to international sites work (allowed)"
    echo
    echo "Your SSH proxy users cannot access Iranian sites!"
  else
    echo -e "${RED}[FAILURE]${NC} Some tests failed. Check the output above."
    echo
    echo "Common issues:"
    echo "  - DNS redirect rules not applied: Run 'Apply DNS rule' for ssh"
    echo "  - DNS policy core not installed: Run 'Install DNS policy core'"
    echo "  - Firewall blocking outbound connections"
  fi

  echo
  read -r -p "Do you want to monitor live DNS queries? (y/n): " monitor
  if [ "${monitor}" = "y" ] || [ "${monitor}" = "Y" ]; then
    echo
    monitor_dns_queries "${test_user}" "digikala.com"
  fi
}

main "$@"
