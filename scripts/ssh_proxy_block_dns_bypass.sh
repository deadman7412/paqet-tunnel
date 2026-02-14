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

RULE_COMMENT="paqet-ssh-proxy-dns-bypass-block"

# Common DoH/DoT DNS servers to block
DOH_DOT_SERVERS=(
  "1.1.1.1"           # Cloudflare
  "1.0.0.1"           # Cloudflare
  "8.8.8.8"           # Google
  "8.8.4.4"           # Google
  "9.9.9.9"           # Quad9
  "149.112.112.112"   # Quad9
  "208.67.222.222"    # OpenDNS
  "208.67.220.220"    # OpenDNS
)

block_doh_dot_for_uid() {
  local uid="$1"
  local server=""

  echo "  Blocking DoH/DoT for UID ${uid}..."

  # Block port 853 (DoT)
  while iptables -D OUTPUT -m owner --uid-owner "${uid}" -p tcp --dport 853 -m comment --comment "${RULE_COMMENT}" -j REJECT 2>/dev/null; do :; done
  while iptables -D OUTPUT -m owner --uid-owner "${uid}" -p udp --dport 853 -m comment --comment "${RULE_COMMENT}" -j REJECT 2>/dev/null; do :; done

  iptables -A OUTPUT -m owner --uid-owner "${uid}" -p tcp --dport 853 -m comment --comment "${RULE_COMMENT}" -j REJECT
  iptables -A OUTPUT -m owner --uid-owner "${uid}" -p udp --dport 853 -m comment --comment "${RULE_COMMENT}" -j REJECT

  # Block common DoH/DoT server IPs
  for server in "${DOH_DOT_SERVERS[@]}"; do
    while iptables -D OUTPUT -m owner --uid-owner "${uid}" -d "${server}" -m comment --comment "${RULE_COMMENT}" -j REJECT 2>/dev/null; do :; done
    iptables -A OUTPUT -m owner --uid-owner "${uid}" -d "${server}" -m comment --comment "${RULE_COMMENT}" -j REJECT
  done

  echo -e "  ${GREEN}[OK]${NC} Blocked DoT (port 853) and ${#DOH_DOT_SERVERS[@]} DoH/DoT servers"
}

persist_firewall() {
  local success=0

  if iptables -V 2>/dev/null | grep -qi nf_tables; then
    if command -v nft >/dev/null 2>&1; then
      if nft list ruleset > /etc/nftables.conf 2>/dev/null; then
        systemctl enable nftables >/dev/null 2>&1 || true
        systemctl start nftables >/dev/null 2>&1 || true
        success=1
      fi
    fi
  else
    if command -v netfilter-persistent >/dev/null 2>&1; then
      if netfilter-persistent save 2>/dev/null; then
        success=1
      fi
    elif [ -d /etc/iptables ]; then
      if iptables-save > /etc/iptables/rules.v4 2>/dev/null; then
        success=1
      fi
    elif command -v service >/dev/null 2>&1; then
      if service iptables save >/dev/null 2>&1; then
        success=1
      fi
    fi
  fi

  if [ "${success}" -eq 0 ]; then
    echo -e "${YELLOW}[WARN]${NC} Could not persist iptables rules automatically" >&2
  else
    echo -e "${GREEN}[OK]${NC} Rules persisted successfully"
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

  echo -e "${BLUE}Blocking DNS bypass (DoH/DoT) for SSH proxy users...${NC}"
  echo

  while IFS= read -r user; do
    [ -z "${user}" ] && continue
    if ! id -u "${user}" >/dev/null 2>&1; then
      echo "Skipping missing system user: ${user}"
      continue
    fi

    uid="$(id -u "${user}")"
    echo "User: ${user} (UID: ${uid})"
    block_doh_dot_for_uid "${uid}"
    count=$((count + 1))
    echo
  done <<< "${usernames}"

  persist_firewall
  ssh_proxy_set_setting "dns_bypass_blocked" "1"

  echo
  echo -e "${GREEN}[SUCCESS]${NC} Blocked DNS bypass for ${count} SSH proxy user(s)"
  echo
  echo "What this does:"
  echo "  - Blocks DoT (DNS over TLS) on port 853"
  echo "  - Blocks access to common DoH/DoT servers (Cloudflare, Google, etc.)"
  echo "  - Forces DNS queries through your DNS blocker"
  echo
  echo "Note: This blocks legitimate encrypted DNS too. If you need DoH/DoT,"
  echo "      use a custom DNS server that respects your blocklist."
}

main "$@"
