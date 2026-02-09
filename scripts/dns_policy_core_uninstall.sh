#!/usr/bin/env bash
set -euo pipefail

DNS_POLICY_DIR="/etc/paqet-dns-policy"
DNSMASQ_MAIN_CONF="/etc/dnsmasq.d/paqet-dns-policy.conf"
DNSMASQ_BLOCK_CONF="/etc/dnsmasq.d/paqet-dns-policy-blocklist.conf"
CRON_FILE="/etc/cron.d/paqet-dns-policy-update"
DNS_PORT=5353

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

while iptables -t nat -D OUTPUT -p udp --dport 53 -m comment --comment paqet-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
while iptables -t nat -D OUTPUT -p tcp --dport 53 -m comment --comment paqet-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
while iptables -t nat -D OUTPUT -p udp --dport 53 -m comment --comment paqet-ssh-proxy-dns -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
while iptables -t nat -D OUTPUT -p tcp --dport 53 -m comment --comment paqet-ssh-proxy-dns -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done

rm -f "${CRON_FILE}"
rm -f "${DNSMASQ_MAIN_CONF}" "${DNSMASQ_BLOCK_CONF}"
rm -rf "${DNS_POLICY_DIR}"

if systemctl is-active --quiet dnsmasq 2>/dev/null; then
  systemctl restart dnsmasq >/dev/null 2>&1 || true
fi

echo "DNS policy core uninstalled."
