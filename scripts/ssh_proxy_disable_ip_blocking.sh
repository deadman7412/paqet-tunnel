#!/usr/bin/env bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

NFTABLES_SET_NAME="iran_ips"
NFT_TABLE="filter"

remove_blocking_rules() {
  echo -e "${BLUE}[INFO]${NC} Removing IP blocking rules..."

  # Check if table and chain exist
  if ! nft list table ip "${NFT_TABLE}" >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO]${NC} Table 'ip ${NFT_TABLE}' doesn't exist, nothing to remove"
    return 0
  fi

  if ! nft list chain ip "${NFT_TABLE}" OUTPUT >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO]${NC} Chain OUTPUT doesn't exist, nothing to remove"
    return 0
  fi

  local removed=0

  # Find and remove all rules with our comment pattern
  while true; do
    local handle
    handle=$(nft -a list chain ip "${NFT_TABLE}" OUTPUT 2>/dev/null | grep "ssh-proxy-ip-block" | head -1 | awk '{print $NF}')

    if [ -z "${handle}" ]; then
      break
    fi

    nft delete rule ip "${NFT_TABLE}" OUTPUT handle "${handle}" 2>/dev/null || break
    removed=$((removed + 1))
  done

  if [ "${removed}" -gt 0 ]; then
    echo -e "${GREEN}[OK]${NC} Removed ${removed} IP blocking rule(s)"
  else
    echo -e "${YELLOW}[INFO]${NC} No IP blocking rules found"
  fi
}

remove_nftables_set() {
  echo -e "${BLUE}[INFO]${NC} Removing nftables IP set..."

  # Check if table exists first
  if ! nft list table ip "${NFT_TABLE}" >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO]${NC} Table 'ip ${NFT_TABLE}' doesn't exist, nothing to remove"
    return 0
  fi

  # Check if set exists
  if ! nft list set ip "${NFT_TABLE}" "${NFTABLES_SET_NAME}" >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO]${NC} Set ${NFTABLES_SET_NAME} not found (already removed or never created)"
    return 0
  fi

  # Try to delete the set
  local error_output
  if error_output=$(nft delete set ip "${NFT_TABLE}" "${NFTABLES_SET_NAME}" 2>&1); then
    echo -e "${GREEN}[OK]${NC} Removed nftables set: ${NFTABLES_SET_NAME}"
  else
    # Check if error is due to set being in use
    if echo "${error_output}" | grep -q "in use"; then
      echo -e "${YELLOW}[WARN]${NC} Set is still in use by rules, flushing elements instead"
      # Flush the set instead of deleting it
      if nft flush set ip "${NFT_TABLE}" "${NFTABLES_SET_NAME}" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC} Flushed nftables set: ${NFTABLES_SET_NAME}"
      fi
    else
      echo -e "${YELLOW}[WARN]${NC} Could not remove set: ${error_output}"
    fi
  fi
}

persist_rules() {
  echo -e "${BLUE}[INFO]${NC} Persisting changes..."

  if nft list ruleset > /etc/nftables.conf 2>&1; then
    echo -e "${GREEN}[OK]${NC} Changes persisted"
  else
    echo -e "${YELLOW}[WARN]${NC} Failed to persist changes"
  fi
  return 0
}

main() {
  echo -e "${BLUE}=== SSH PROXY IP-BASED BLOCKING REMOVAL ===${NC}"
  echo

  ssh_proxy_require_root

  # Check if nft is available
  if ! command -v nft >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} nftables not installed"
    exit 1
  fi

  # Remove rules
  remove_blocking_rules

  echo

  # Remove set
  remove_nftables_set

  echo

  # Persist
  persist_rules

  # Update state
  ssh_proxy_set_setting "ip_blocking_enabled" "0"

  echo
  echo -e "${GREEN}[SUCCESS]${NC} IP-based blocking disabled"
  echo "Iranian IP ranges are no longer blocked for SSH proxy users"
}

main "$@"
