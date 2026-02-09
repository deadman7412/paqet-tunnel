#!/usr/bin/env bash
set -euo pipefail

PAQET_USER="paqet"
DNS_PORT=5353
SERVER_POLICY_STATE_DIR="/etc/paqet-policy"
SERVER_POLICY_STATE_FILE="${SERVER_POLICY_STATE_DIR}/settings.env"

set_state() {
  local key="$1"
  local value="$2"
  local tmp=""

  mkdir -p "${SERVER_POLICY_STATE_DIR}"
  tmp="$(mktemp)"
  if [ -f "${SERVER_POLICY_STATE_FILE}" ]; then
    awk -F= -v k="${key}" '$1!=k {print $0}' "${SERVER_POLICY_STATE_FILE}" > "${tmp}" 2>/dev/null || true
  fi
  echo "${key}=${value}" >> "${tmp}"
  mv "${tmp}" "${SERVER_POLICY_STATE_FILE}"
  chmod 600 "${SERVER_POLICY_STATE_FILE}"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if id -u "${PAQET_USER}" >/dev/null 2>&1; then
  PAQET_UID="$(id -u "${PAQET_USER}")"
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${PAQET_UID}" -p udp --dport 53 -m comment --comment paqet-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${PAQET_UID}" -p tcp --dport 53 -m comment --comment paqet-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
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

set_state "server_dns_enabled" "0"

echo "DNS policy binding disabled for paqet traffic."
