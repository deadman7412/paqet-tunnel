#!/usr/bin/env bash
set -euo pipefail

PAQET_USER="paqet"
DNS_POLICY_DIR="/etc/paqet-dns-policy"
DNSMASQ_MAIN_CONF="/etc/dnsmasq.d/paqet-dns-policy.conf"
DNSMASQ_BLOCK_CONF="/etc/dnsmasq.d/paqet-dns-policy-blocklist.conf"
CRON_FILE="/etc/cron.d/paqet-dns-policy-update"
DNS_PORT=5353

PAQET_UID=""
if id -u "${PAQET_USER}" >/dev/null 2>&1; then
  PAQET_UID="$(id -u "${PAQET_USER}")"
fi

if [ -n "${PAQET_UID}" ]; then
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${PAQET_UID}" -p udp --dport 53 -m comment --comment paqet-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${PAQET_UID}" -p tcp --dport 53 -m comment --comment paqet-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
fi

rm -f "${CRON_FILE}"
rm -f "${DNSMASQ_MAIN_CONF}" "${DNSMASQ_BLOCK_CONF}"
rm -rf "${DNS_POLICY_DIR}"

if systemctl is-active --quiet dnsmasq 2>/dev/null; then
  systemctl restart dnsmasq >/dev/null 2>&1 || true
fi

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

echo "DNS policy disabled."
