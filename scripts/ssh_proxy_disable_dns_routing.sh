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
RULE_COMMENT="paqet-ssh-proxy-dns"

DEBUG=1
debug_log() {
  [ "${DEBUG}" = "1" ] && echo -e "${BLUE}[DEBUG]${NC} $*"
}

remove_uid_dns_rules() {
  local uid="$1"
  local removed=0

  debug_log "Removing DNS redirect rules for UID ${uid}..."

  while iptables -t nat -D OUTPUT -m owner --uid-owner "${uid}" -p udp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do
    removed=$((removed + 1))
  done
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${uid}" -p tcp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do
    removed=$((removed + 1))
  done

  if [ "${removed}" -gt 0 ]; then
    echo -e "${GREEN}[OK]${NC} Removed ${removed} DNS redirect rule(s) for UID ${uid}"
  else
    echo -e "${YELLOW}[INFO]${NC} No DNS redirect rules found for UID ${uid}"
  fi
}

persist_firewall() {
  local success=0

  echo
  echo -e "${BLUE}[INFO]${NC} Persisting firewall rules..."

  if iptables -V 2>/dev/null | grep -qi nf_tables; then
    if command -v nft >/dev/null 2>&1; then
      if nft list ruleset > /etc/nftables.conf 2>&1; then
        systemctl enable nftables >/dev/null 2>&1 || true
        success=1
        echo -e "${GREEN}[OK]${NC} Rules saved using nftables"
      fi
    fi
  else
    if command -v netfilter-persistent >/dev/null 2>&1; then
      if netfilter-persistent save 2>&1; then
        success=1
        echo -e "${GREEN}[OK]${NC} Rules saved using netfilter-persistent"
      fi
    elif [ -d /etc/iptables ]; then
      if iptables-save > /etc/iptables/rules.v4 2>&1; then
        success=1
        echo -e "${GREEN}[OK]${NC} Rules saved to /etc/iptables/rules.v4"
      fi
    elif command -v service >/dev/null 2>&1; then
      if service iptables save 2>&1; then
        success=1
        echo -e "${GREEN}[OK]${NC} Rules saved using iptables service"
      fi
    fi
  fi

  if [ "${success}" -eq 0 ]; then
    echo -e "${YELLOW}[WARN]${NC} Could not persist changes automatically"
  fi
}

main() {
  local usernames=""
  local user=""
  local uid=""
  local count=0

  echo -e "${BLUE}=== SSH PROXY DNS ROUTING REMOVAL ===${NC}"
  echo

  ssh_proxy_require_root

  debug_log "Fetching SSH proxy users..."
  usernames="$(ssh_proxy_list_usernames || true)"
  if [ -z "${usernames}" ]; then
    echo -e "${YELLOW}[INFO]${NC} No SSH proxy users found."
    exit 0
  fi

  echo -e "${BLUE}[INFO]${NC} Removing DNS redirect rules for SSH proxy users..."
  echo

  while IFS= read -r user; do
    [ -z "${user}" ] && continue
    if ! id -u "${user}" >/dev/null 2>&1; then
      echo -e "${YELLOW}[WARN]${NC} Skipping missing system user: ${user}"
      continue
    fi

    uid="$(id -u "${user}")"
    echo -e "${BLUE}[INFO]${NC} Processing user: ${user} (UID: ${uid})"
    remove_uid_dns_rules "${uid}"
    count=$((count + 1))
    echo
  done <<< "${usernames}"

  persist_firewall

  echo
  ssh_proxy_set_setting "dns_enabled" "0"
  debug_log "Updated settings: dns_enabled=0"

  echo
  echo -e "${GREEN}[SUCCESS]${NC} Disabled DNS routing for ${count} SSH proxy user(s)"
}

main "$@"
