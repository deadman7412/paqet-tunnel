#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ssh_proxy_port_lib.sh
source "${SCRIPT_DIR}/ssh_proxy_port_lib.sh"

DNS_PORT=5353
RULE_COMMENT="paqet-ssh-proxy-dns"

remove_uid_dns_rules() {
  local uid="$1"
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${uid}" -p udp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${uid}" -p tcp --dport 53 -m comment --comment "${RULE_COMMENT}" -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
}

persist_firewall() {
  if iptables -V 2>/dev/null | grep -qi nf_tables; then
    if command -v nft >/dev/null 2>&1; then
      nft list ruleset > /etc/nftables.conf || true
      systemctl enable --now nftables >/dev/null 2>&1 || true
    fi
  else
    if command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save || true
    elif [ -d /etc/iptables ]; then
      iptables-save > /etc/iptables/rules.v4 || true
    elif command -v service >/dev/null 2>&1; then
      service iptables save || true
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

  while IFS= read -r user; do
    [ -z "${user}" ] && continue
    if ! id -u "${user}" >/dev/null 2>&1; then
      continue
    fi
    uid="$(id -u "${user}")"
    remove_uid_dns_rules "${uid}"
    count=$((count + 1))
  done <<< "${usernames}"

  persist_firewall
  echo "Disabled server DNS routing for ${count} SSH proxy user(s)."
}

main "$@"
