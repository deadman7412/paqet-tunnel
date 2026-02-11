#!/usr/bin/env bash
set -euo pipefail

WATERWALL_USER="waterwall"
DNS_PORT=5353
WATERWALL_POLICY_STATE_DIR="/etc/waterwall-policy"
WATERWALL_POLICY_STATE_FILE="${WATERWALL_POLICY_STATE_DIR}/settings.env"

set_state() {
  local key="$1"
  local value="$2"
  local tmp=""

  mkdir -p "${WATERWALL_POLICY_STATE_DIR}"
  tmp="$(mktemp)"
  if [ -f "${WATERWALL_POLICY_STATE_FILE}" ]; then
    awk -F= -v k="${key}" '$1!=k {print $0}' "${WATERWALL_POLICY_STATE_FILE}" > "${tmp}" 2>/dev/null || true
  fi
  echo "${key}=${value}" >> "${tmp}"
  mv "${tmp}" "${WATERWALL_POLICY_STATE_FILE}"
  chmod 600 "${WATERWALL_POLICY_STATE_FILE}"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if [ ! -f /etc/dnsmasq.d/paqet-dns-policy.conf ]; then
  echo "DNS policy core is not installed/configured." >&2
  echo "Run: Paqet Tunnel -> WARP/DNS core -> Install DNS policy core" >&2
  exit 1
fi

systemctl enable --now dnsmasq >/dev/null 2>&1 || true
systemctl restart dnsmasq >/dev/null 2>&1 || true
if ! systemctl is-active --quiet dnsmasq 2>/dev/null; then
  echo "dnsmasq is not active for DNS policy core." >&2
  exit 1
fi

if ! id -u "${WATERWALL_USER}" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "${WATERWALL_USER}"
fi
WATERWALL_UID="$(id -u "${WATERWALL_USER}")"

while iptables -t nat -D OUTPUT -m owner --uid-owner "${WATERWALL_UID}" -p udp --dport 53 -m comment --comment waterwall-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
while iptables -t nat -D OUTPUT -m owner --uid-owner "${WATERWALL_UID}" -p tcp --dport 53 -m comment --comment waterwall-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done

iptables -t nat -A OUTPUT -m owner --uid-owner "${WATERWALL_UID}" -p udp --dport 53 -m comment --comment waterwall-dns-policy -j REDIRECT --to-ports "${DNS_PORT}"
iptables -t nat -A OUTPUT -m owner --uid-owner "${WATERWALL_UID}" -p tcp --dport 53 -m comment --comment waterwall-dns-policy -j REDIRECT --to-ports "${DNS_PORT}"

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

set_state "waterwall_dns_enabled" "1"

echo "DNS policy binding enabled for waterwall traffic."
