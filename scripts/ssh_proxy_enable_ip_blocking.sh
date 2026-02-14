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

IP_BLOCK_DIR="/etc/paqet-ip-blocking"
IP_LIST_FILE="${IP_BLOCK_DIR}/iran_ips.txt"
NFTABLES_SET_NAME="iran_ips"
NFT_TABLE="filter"

download_iranian_ips() {
  local tmp_file=""
  tmp_file="$(mktemp)"

  echo -e "${BLUE}[INFO]${NC} Downloading Iranian IP ranges..."

  # Try multiple sources
  if curl -fsSL --connect-timeout 10 --max-time 30 "https://www.ipdeny.com/ipblocks/data/countries/ir.zone" -o "${tmp_file}" 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Downloaded from ipdeny.com"
  elif curl -fsSL --connect-timeout 10 --max-time 30 "https://raw.githubusercontent.com/herrbischoff/country-ip-blocks/master/ipv4/ir.cidr" -o "${tmp_file}" 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Downloaded from github.com/herrbischoff"
  else
    echo -e "${RED}[ERROR]${NC} Failed to download IP list from all sources"
    rm -f "${tmp_file}"
    return 1
  fi

  # Validate and clean
  if [ ! -s "${tmp_file}" ]; then
    echo -e "${RED}[ERROR]${NC} Downloaded file is empty"
    rm -f "${tmp_file}"
    return 1
  fi

  # Count IPs
  local count
  count=$(wc -l < "${tmp_file}" | tr -d ' ')
  echo -e "${GREEN}[OK]${NC} Downloaded ${count} IP ranges"

  # Move to permanent location
  mkdir -p "${IP_BLOCK_DIR}"
  mv "${tmp_file}" "${IP_LIST_FILE}"
  chmod 644 "${IP_LIST_FILE}"

  return 0
}

create_nftables_set() {
  echo -e "${BLUE}[INFO]${NC} Creating nftables IP set..."

  # Check if table exists, create if not
  if ! nft list table ip "${NFT_TABLE}" >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN]${NC} Table 'ip ${NFT_TABLE}' doesn't exist, creating..."
    nft add table ip "${NFT_TABLE}"
  fi

  # Delete old set if exists
  nft delete set ip "${NFT_TABLE}" "${NFTABLES_SET_NAME}" 2>/dev/null || true

  # Create new set
  nft add set ip "${NFT_TABLE}" "${NFTABLES_SET_NAME}" "{ type ipv4_addr; flags interval; }"

  echo -e "${GREEN}[OK]${NC} Created nftables set: ${NFTABLES_SET_NAME}"
}

load_ips_into_set() {
  echo -e "${BLUE}[INFO]${NC} Loading IP ranges into nftables set..."

  local count=0
  local batch_size=100
  local batch_ips=()

  while IFS= read -r ip; do
    # Skip empty lines and comments
    [[ -z "${ip}" || "${ip}" =~ ^# ]] && continue

    # Validate CIDR format
    if [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
      batch_ips+=("${ip}")
      count=$((count + 1))

      # Add in batches for better performance
      if [ ${#batch_ips[@]} -ge ${batch_size} ]; then
        nft add element ip "${NFT_TABLE}" "${NFTABLES_SET_NAME}" "{ $(IFS=,; echo "${batch_ips[*]}") }"
        batch_ips=()
      fi
    fi
  done < "${IP_LIST_FILE}"

  # Add remaining IPs
  if [ ${#batch_ips[@]} -gt 0 ]; then
    nft add element ip "${NFT_TABLE}" "${NFTABLES_SET_NAME}" "{ $(IFS=,; echo "${batch_ips[*]}") }"
  fi

  echo -e "${GREEN}[OK]${NC} Loaded ${count} IP ranges into set"
}

add_blocking_rules() {
  local usernames=""
  local user=""
  local uid=""

  echo -e "${BLUE}[INFO]${NC} Adding IP blocking rules for SSH proxy users..."

  usernames="$(ssh_proxy_list_usernames || true)"
  if [ -z "${usernames}" ]; then
    echo -e "${YELLOW}[WARN]${NC} No SSH proxy users found"
    return 0
  fi

  while IFS= read -r user; do
    [ -z "${user}" ] && continue
    if ! id -u "${user}" >/dev/null 2>&1; then
      continue
    fi

    uid="$(id -u "${user}")"
    echo -e "${BLUE}[INFO]${NC} Adding rule for user: ${user} (UID: ${uid})"

    # Delete old rule if exists
    nft delete rule ip "${NFT_TABLE}" OUTPUT handle \
      $(nft -a list chain ip "${NFT_TABLE}" OUTPUT 2>/dev/null | grep "skuid ${uid}" | grep "${NFTABLES_SET_NAME}" | awk '{print $NF}') \
      2>/dev/null || true

    # Add new rule: Block outbound connections to Iranian IPs for this UID
    nft add rule ip "${NFT_TABLE}" OUTPUT \
      meta skuid "${uid}" \
      ip daddr @"${NFTABLES_SET_NAME}" \
      counter reject with icmp type host-unreachable \
      comment "\"ssh-proxy-ip-block-${user}\""

    echo -e "${GREEN}[OK]${NC} Added IP blocking rule for ${user}"
  done <<< "${usernames}"
}

persist_rules() {
  echo -e "${BLUE}[INFO]${NC} Persisting nftables rules..."

  if nft list ruleset > /etc/nftables.conf 2>&1; then
    systemctl enable nftables >/dev/null 2>&1 || true
    echo -e "${GREEN}[OK]${NC} Rules persisted to /etc/nftables.conf"
  else
    echo -e "${YELLOW}[WARN]${NC} Failed to persist rules"
  fi
}

main() {
  echo -e "${BLUE}=== SSH PROXY IP-BASED BLOCKING SETUP ===${NC}"
  echo
  echo "This will block Iranian IP ranges for SSH proxy users."
  echo "Uses lightweight nftables sets for efficient blocking."
  echo

  ssh_proxy_require_root

  # Check if nft is available
  if ! command -v nft >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} nftables not installed"
    echo "Install: apt-get install nftables"
    exit 1
  fi

  # Download Iranian IPs
  if [ -f "${IP_LIST_FILE}" ]; then
    echo -e "${YELLOW}[INFO]${NC} IP list already exists at ${IP_LIST_FILE}"
    read -r -p "Download fresh list? (y/n): " update
    if [ "${update}" = "y" ] || [ "${update}" = "Y" ]; then
      download_iranian_ips || exit 1
    fi
  else
    download_iranian_ips || exit 1
  fi

  echo

  # Create nftables set
  create_nftables_set

  # Load IPs into set
  load_ips_into_set

  echo

  # Add blocking rules
  add_blocking_rules

  echo

  # Persist
  persist_rules

  # Save state
  ssh_proxy_set_setting "ip_blocking_enabled" "1"

  echo
  echo -e "${GREEN}[SUCCESS]${NC} IP-based blocking enabled!"
  echo
  echo "What this does:"
  echo "  - Blocks connections to Iranian IP ranges"
  echo "  - Uses efficient nftables sets (not individual rules)"
  echo "  - Works regardless of DNS resolution location"
  echo
  echo "Coverage:"
  echo "  - Blocks Iranian-hosted sites"
  echo "  - Sites on global CDNs (Cloudflare, etc.) not blocked"
  echo
  echo "Next steps:"
  echo "  1. Test from your phone - Iranian sites should be unreachable"
  echo "  2. Update IP list monthly: SSH Proxy -> Update IP blocklist"
}

main "$@"
