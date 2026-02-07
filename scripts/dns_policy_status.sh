#!/usr/bin/env bash
set -euo pipefail

PAQET_USER="paqet"
DNS_POLICY_DIR="/etc/paqet-dns-policy"
DNSMASQ_MAIN_CONF="/etc/dnsmasq.d/paqet-dns-policy.conf"
DNSMASQ_BLOCK_CONF="/etc/dnsmasq.d/paqet-dns-policy-blocklist.conf"
META_FILE="${DNS_POLICY_DIR}/last_update"
DNS_PORT=5353

echo "=== DNS POLICY STATUS ==="
echo

if [ -f "${DNSMASQ_MAIN_CONF}" ] && [ -f "${DNSMASQ_BLOCK_CONF}" ]; then
  echo "Config: enabled"
else
  echo "Config: disabled"
fi

if systemctl is-active --quiet dnsmasq 2>/dev/null; then
  echo "dnsmasq: active"
else
  echo "dnsmasq: inactive"
fi

if [ -f "${META_FILE}" ]; then
  echo
  echo "Last update:"
  cat "${META_FILE}"
fi

if [ -f "${DNSMASQ_BLOCK_CONF}" ]; then
  COUNT="$(grep -c '^address=/' "${DNSMASQ_BLOCK_CONF}" 2>/dev/null || true)"
  # Two address entries per domain (IPv4 + IPv6)
  DOMAINS=$(( COUNT / 2 ))
  echo "Loaded domains: ${DOMAINS}"
fi

if id -u "${PAQET_USER}" >/dev/null 2>&1; then
  PAQET_UID="$(id -u "${PAQET_USER}")"
  echo
  echo "Redirect rules for uid ${PAQET_UID}:"
  iptables -t nat -S OUTPUT 2>/dev/null | grep -E "uid-owner ${PAQET_UID}.*dport 53.*REDIRECT.*to-ports ${DNS_PORT}" || echo "(none)"
fi

echo
echo "=== END ==="
