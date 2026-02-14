#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

DNS_PORT=5353
RULE_COMMENT="paqet-ssh-proxy-dns"

ensure_dns_resolver() {
  if [ ! -f /etc/dnsmasq.d/paqet-dns-policy.conf ]; then
    echo "Server DNS policy is not installed/configured." >&2
    echo "Run: Paqet Tunnel -> WARP/DNS core -> Install DNS policy core" >&2
    exit 1
  fi

  if ! systemctl is-active --quiet dnsmasq 2>/dev/null; then
    echo "dnsmasq is not active for server DNS policy." >&2
    echo "Run: Paqet Tunnel -> WARP/DNS core -> Install DNS policy core" >&2
    exit 1
  fi
}

ensure_uid_dns_rules() {
  local uid="$1"

  while iptables -t nat -D OUTPUT -m owner --uid-owner "${uid}" -p udp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${uid}" -p tcp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done

  iptables -t nat -A OUTPUT -m owner --uid-owner "${uid}" -p udp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}"
  iptables -t nat -A OUTPUT -m owner --uid-owner "${uid}" -p tcp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}"
}

ensure_persistence_tools() {
  if iptables -V 2>/dev/null | grep -qi nf_tables; then
    if ! command -v nft >/dev/null 2>&1; then
      echo "Installing nftables for rule persistence..."
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y nftables
      elif command -v dnf >/dev/null 2>&1; then
        dnf install -y nftables
      elif command -v yum >/dev/null 2>&1; then
        yum install -y nftables
      fi
    fi
  else
    if ! command -v netfilter-persistent >/dev/null 2>&1 && ! command -v iptables-persistent >/dev/null 2>&1; then
      echo "Installing iptables-persistent for rule persistence..."
      if command -v apt-get >/dev/null 2>&1; then
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
        apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
      elif command -v dnf >/dev/null 2>&1; then
        dnf install -y iptables-services
      elif command -v yum >/dev/null 2>&1; then
        yum install -y iptables-services
      fi
    fi
  fi
}

persist_firewall() {
  local success=0

  if iptables -V 2>/dev/null | grep -qi nf_tables; then
    if command -v nft >/dev/null 2>&1; then
      if nft list ruleset > /etc/nftables.conf 2>/dev/null; then
        systemctl enable nftables >/dev/null 2>&1 || true
        systemctl start nftables >/dev/null 2>&1 || true
        success=1
        echo "Rules saved using nftables"
      fi
    fi
  else
    if command -v netfilter-persistent >/dev/null 2>&1; then
      if netfilter-persistent save 2>/dev/null; then
        success=1
        echo "Rules saved using netfilter-persistent"
      fi
    elif [ -d /etc/iptables ]; then
      if iptables-save > /etc/iptables/rules.v4 2>/dev/null; then
        success=1
        echo "Rules saved to /etc/iptables/rules.v4"
      fi
    elif command -v service >/dev/null 2>&1; then
      if service iptables save >/dev/null 2>&1; then
        success=1
        echo "Rules saved using iptables service"
      fi
    fi
  fi

  if [ "${success}" -eq 0 ]; then
    echo "Warning: Could not persist iptables rules automatically." >&2
    echo "Rules will be lost on reboot. Consider installing iptables-persistent." >&2
  fi
}

main() {
  local usernames=""
  local user=""
  local uid=""
  local count=0

  ssh_proxy_require_root
  ensure_dns_resolver
  ensure_persistence_tools

  usernames="$(ssh_proxy_list_usernames || true)"
  if [ -z "${usernames}" ]; then
    echo "No SSH proxy users found."
    exit 0
  fi

  while IFS= read -r user; do
    [ -z "${user}" ] && continue
    if ! id -u "${user}" >/dev/null 2>&1; then
      echo "Skipping missing system user: ${user}"
      continue
    fi
    uid="$(id -u "${user}")"
    ensure_uid_dns_rules "${uid}"
    count=$((count + 1))
  done <<< "${usernames}"

  persist_firewall
  ssh_proxy_set_setting "dns_enabled" "1"
  echo "Enabled server DNS routing for ${count} SSH proxy user(s)."
}

main "$@"
