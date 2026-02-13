#!/usr/bin/env bash
set -euo pipefail

ICMPTUNNEL_USER="icmptunnel"
DNS_PORT=5353
ICMPTUNNEL_POLICY_STATE_DIR="/etc/icmptunnel-policy"
ICMPTUNNEL_POLICY_STATE_FILE="${ICMPTUNNEL_POLICY_STATE_DIR}/settings.env"

set_state() {
  local key="$1"
  local value="$2"
  local tmp=""

  mkdir -p "${ICMPTUNNEL_POLICY_STATE_DIR}"
  tmp="$(mktemp)"
  if [ -f "${ICMPTUNNEL_POLICY_STATE_FILE}" ]; then
    awk -F= -v k="${key}" '$1!=k {print $0}' "${ICMPTUNNEL_POLICY_STATE_FILE}" > "${tmp}" 2>/dev/null || true
  fi
  echo "${key}=${value}" >> "${tmp}"
  mv "${tmp}" "${ICMPTUNNEL_POLICY_STATE_FILE}"
  chmod 600 "${ICMPTUNNEL_POLICY_STATE_FILE}"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if ! id -u "${ICMPTUNNEL_USER}" >/dev/null 2>&1; then
  echo "icmptunnel user does not exist. DNS policy may not be enabled." >&2
  exit 0
fi

ICMPTUNNEL_UID="$(id -u "${ICMPTUNNEL_USER}")"

echo "Removing DNS policy iptables rules..."
while iptables -t nat -D OUTPUT -m owner --uid-owner "${ICMPTUNNEL_UID}" -p udp --dport 53 -m comment --comment icmptunnel-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
while iptables -t nat -D OUTPUT -m owner --uid-owner "${ICMPTUNNEL_UID}" -p tcp --dport 53 -m comment --comment icmptunnel-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done

if iptables -V 2>/dev/null | grep -qi nf_tables; then
  if command -v nft >/dev/null 2>&1; then
    nft list ruleset > /etc/nftables.conf || true
  fi
else
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save || true
  elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4 || true
  fi
fi

set_state "icmptunnel_dns_enabled" "0"

echo "DNS policy binding disabled for icmptunnel traffic."
