#!/usr/bin/env bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

RULE_COMMENT="paqet-ssh-proxy-dns-bypass-block"

remove_doh_dot_blocks_for_uid() {
  local uid="$1"
  local removed=0

  while iptables -D OUTPUT -m owner --uid-owner "${uid}" -p tcp --dport 853 -m comment --comment "${RULE_COMMENT}" -j REJECT 2>/dev/null; do
    removed=$((removed + 1))
  done
  while iptables -D OUTPUT -m owner --uid-owner "${uid}" -p udp --dport 853 -m comment --comment "${RULE_COMMENT}" -j REJECT 2>/dev/null; do
    removed=$((removed + 1))
  done

  while iptables -D OUTPUT -m owner --uid-owner "${uid}" -m comment --comment "${RULE_COMMENT}" -j REJECT 2>/dev/null; do
    removed=$((removed + 1))
  done

  echo "  Removed ${removed} DoH/DoT blocking rule(s) for UID ${uid}"
}

persist_firewall() {
  if iptables -V 2>/dev/null | grep -qi nf_tables; then
    if command -v nft >/dev/null 2>&1; then
      nft list ruleset > /etc/nftables.conf 2>/dev/null || true
      systemctl enable nftables >/dev/null 2>&1 || true
    fi
  else
    if command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save 2>/dev/null || true
    elif [ -d /etc/iptables ]; then
      iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    elif command -v service >/dev/null 2>&1; then
      service iptables save >/dev/null 2>&1 || true
    fi
  fi
}

main() {
  local usernames=""
  local user=""
  local uid=""
  local count=0

  ssh_proxy_require_root

  usernames="$(ssh_proxy_list_usernames || true)"
  if [ -z "${usernames}" ]; then
    echo "No SSH proxy users found."
    exit 0
  fi

  echo -e "${BLUE}Removing DNS bypass blocks for SSH proxy users...${NC}"
  echo

  while IFS= read -r user; do
    [ -z "${user}" ] && continue
    if ! id -u "${user}" >/dev/null 2>&1; then
      echo "Skipping missing system user: ${user}"
      continue
    fi

    uid="$(id -u "${user}")"
    echo "User: ${user} (UID: ${uid})"
    remove_doh_dot_blocks_for_uid "${uid}"
    count=$((count + 1))
  done <<< "${usernames}"

  persist_firewall
  ssh_proxy_set_setting "dns_bypass_blocked" "0"

  echo
  echo -e "${GREEN}[SUCCESS]${NC} Removed DNS bypass blocks for ${count} SSH proxy user(s)"
  echo "DoH/DoT is now allowed (but may bypass your DNS blocker)"
}

main "$@"
