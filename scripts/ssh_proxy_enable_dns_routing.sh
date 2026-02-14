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

ensure_dns_resolver() {
  debug_log "Checking DNS policy core installation..."

  if [ ! -f /etc/dnsmasq.d/paqet-dns-policy.conf ]; then
    echo -e "${RED}[ERROR]${NC} Server DNS policy is not installed/configured." >&2
    echo "Run: Paqet Tunnel -> WARP/DNS core -> Install DNS policy core" >&2
    exit 1
  fi
  debug_log "DNS policy config file exists"

  if ! systemctl is-active --quiet dnsmasq 2>/dev/null; then
    echo -e "${RED}[ERROR]${NC} dnsmasq is not active for server DNS policy." >&2
    echo "Run: Paqet Tunnel -> WARP/DNS core -> Install DNS policy core" >&2
    exit 1
  fi
  debug_log "dnsmasq service is active"
  echo -e "${GREEN}[OK]${NC} DNS resolver is ready"
}

ensure_uid_dns_rules() {
  local uid="$1"
  local removed_count=0

  debug_log "Removing old DNS redirect rules for UID ${uid}..."
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${uid}" -p udp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do
    removed_count=$((removed_count + 1))
  done
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${uid}" -p tcp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do
    removed_count=$((removed_count + 1))
  done
  [ "${removed_count}" -gt 0 ] && debug_log "Removed ${removed_count} old rule(s)"

  debug_log "Adding DNS redirect rules for UID ${uid}..."

  if ! iptables -t nat -A OUTPUT -m owner --uid-owner "${uid}" -p udp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}" 2>&1; then
    echo -e "${RED}[ERROR]${NC} Failed to add UDP DNS redirect rule for UID ${uid}" >&2
    return 1
  fi
  echo -e "${GREEN}[OK]${NC} Added UDP DNS redirect rule (UID ${uid} -> port ${DNS_PORT})"

  if ! iptables -t nat -A OUTPUT -m owner --uid-owner "${uid}" -p tcp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}" 2>&1; then
    echo -e "${RED}[ERROR]${NC} Failed to add TCP DNS redirect rule for UID ${uid}" >&2
    return 1
  fi
  echo -e "${GREEN}[OK]${NC} Added TCP DNS redirect rule (UID ${uid} -> port ${DNS_PORT})"

  # Verify rules were added
  debug_log "Verifying rules were added..."
  if iptables -t nat -S OUTPUT 2>/dev/null | grep -q "uid-owner ${uid}.*dport 53.*udp.*REDIRECT.*${DNS_PORT}"; then
    debug_log "UDP rule verified in iptables"
  else
    echo -e "${YELLOW}[WARN]${NC} UDP rule not found in iptables after adding!" >&2
  fi

  if iptables -t nat -S OUTPUT 2>/dev/null | grep -q "uid-owner ${uid}.*dport 53.*tcp.*REDIRECT.*${DNS_PORT}"; then
    debug_log "TCP rule verified in iptables"
  else
    echo -e "${YELLOW}[WARN]${NC} TCP rule not found in iptables after adding!" >&2
  fi
}

ensure_persistence_tools() {
  debug_log "Checking persistence tools..."

  if iptables -V 2>/dev/null | grep -qi nf_tables; then
    debug_log "Detected nftables backend"
    if ! command -v nft >/dev/null 2>&1; then
      echo -e "${YELLOW}[INFO]${NC} Installing nftables for rule persistence..."
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y nftables
      elif command -v dnf >/dev/null 2>&1; then
        dnf install -y nftables
      elif command -v yum >/dev/null 2>&1; then
        yum install -y nftables
      fi
      echo -e "${GREEN}[OK]${NC} nftables installed"
    else
      debug_log "nftables already installed"
    fi
  else
    debug_log "Detected legacy iptables backend"
    if ! command -v netfilter-persistent >/dev/null 2>&1 && ! command -v iptables-persistent >/dev/null 2>&1; then
      echo -e "${YELLOW}[INFO]${NC} Installing iptables-persistent for rule persistence..."
      if command -v apt-get >/dev/null 2>&1; then
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
        apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
        echo -e "${GREEN}[OK]${NC} iptables-persistent installed"
      elif command -v dnf >/dev/null 2>&1; then
        dnf install -y iptables-services
        echo -e "${GREEN}[OK]${NC} iptables-services installed"
      elif command -v yum >/dev/null 2>&1; then
        yum install -y iptables-services
        echo -e "${GREEN}[OK]${NC} iptables-services installed"
      fi
    else
      debug_log "netfilter-persistent already installed"
    fi
  fi
}

persist_firewall() {
  local success=0

  echo
  echo -e "${BLUE}[INFO]${NC} Persisting firewall rules..."

  if iptables -V 2>/dev/null | grep -qi nf_tables; then
    debug_log "Using nftables persistence method"
    if command -v nft >/dev/null 2>&1; then
      debug_log "Running: nft list ruleset > /etc/nftables.conf"
      if nft list ruleset > /etc/nftables.conf 2>&1; then
        debug_log "Enabling nftables service"
        systemctl enable nftables >/dev/null 2>&1 || true
        systemctl start nftables >/dev/null 2>&1 || true
        success=1
        echo -e "${GREEN}[OK]${NC} Rules saved using nftables (/etc/nftables.conf)"
      else
        echo -e "${YELLOW}[WARN]${NC} Failed to save nftables ruleset"
      fi
    else
      echo -e "${YELLOW}[WARN]${NC} nft command not found"
    fi
  else
    debug_log "Using legacy iptables persistence method"
    if command -v netfilter-persistent >/dev/null 2>&1; then
      debug_log "Running: netfilter-persistent save"
      if netfilter-persistent save 2>&1; then
        success=1
        echo -e "${GREEN}[OK]${NC} Rules saved using netfilter-persistent"
      else
        echo -e "${YELLOW}[WARN]${NC} netfilter-persistent save failed"
      fi
    elif [ -d /etc/iptables ]; then
      debug_log "Running: iptables-save > /etc/iptables/rules.v4"
      if iptables-save > /etc/iptables/rules.v4 2>&1; then
        success=1
        echo -e "${GREEN}[OK]${NC} Rules saved to /etc/iptables/rules.v4"
      else
        echo -e "${YELLOW}[WARN]${NC} Failed to save to /etc/iptables/rules.v4"
      fi
    elif command -v service >/dev/null 2>&1; then
      debug_log "Running: service iptables save"
      if service iptables save 2>&1; then
        success=1
        echo -e "${GREEN}[OK]${NC} Rules saved using iptables service"
      else
        echo -e "${YELLOW}[WARN]${NC} service iptables save failed"
      fi
    else
      echo -e "${YELLOW}[WARN]${NC} No persistence method available"
    fi
  fi

  if [ "${success}" -eq 0 ]; then
    echo -e "${RED}[ERROR]${NC} Could not persist iptables rules automatically" >&2
    echo "Rules will be lost on reboot. Install iptables-persistent:" >&2
    echo "  apt-get install iptables-persistent" >&2
    return 1
  fi
}

main() {
  local usernames=""
  local user=""
  local uid=""
  local count=0

  echo -e "${BLUE}=== SSH PROXY DNS ROUTING SETUP ===${NC}"
  echo

  ssh_proxy_require_root
  ensure_dns_resolver
  echo
  ensure_persistence_tools
  echo

  debug_log "Fetching SSH proxy users..."
  usernames="$(ssh_proxy_list_usernames || true)"
  if [ -z "${usernames}" ]; then
    echo -e "${YELLOW}[WARN]${NC} No SSH proxy users found."
    echo "Create SSH proxy users first: SSH Proxy -> Create SSH proxy user"
    exit 0
  fi

  echo -e "${BLUE}[INFO]${NC} Configuring DNS redirect rules for SSH proxy users..."
  echo

  while IFS= read -r user; do
    [ -z "${user}" ] && continue
    if ! id -u "${user}" >/dev/null 2>&1; then
      echo -e "${YELLOW}[WARN]${NC} Skipping missing system user: ${user}"
      continue
    fi

    uid="$(id -u "${user}")"
    echo -e "${BLUE}[INFO]${NC} Processing user: ${user} (UID: ${uid})"

    if ! ensure_uid_dns_rules "${uid}"; then
      echo -e "${RED}[ERROR]${NC} Failed to create DNS rules for ${user}" >&2
      continue
    fi

    count=$((count + 1))
    echo
  done <<< "${usernames}"

  if [ "${count}" -eq 0 ]; then
    echo -e "${RED}[ERROR]${NC} No DNS rules were created" >&2
    exit 1
  fi

  if ! persist_firewall; then
    echo -e "${YELLOW}[WARN]${NC} Rules were created but may not survive reboot" >&2
  fi

  echo
  ssh_proxy_set_setting "dns_enabled" "1"
  debug_log "Updated settings: dns_enabled=1"

  echo
  echo -e "${GREEN}[SUCCESS]${NC} Enabled DNS routing for ${count} SSH proxy user(s)"
  echo
  echo "Next steps:"
  echo "  1. Verify: DNS Configuration -> Debug SSH proxy DNS routing"
  echo "  2. Optional: DNS Configuration -> Block DNS bypass (DoH/DoT)"
}

main "$@"
