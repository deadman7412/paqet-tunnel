#!/usr/bin/env bash
set -euo pipefail

PAQET_USER="paqet"
DNS_POLICY_DIR="/etc/paqet-dns-policy"
DNSMASQ_MAIN_CONF="/etc/dnsmasq.d/paqet-dns-policy.conf"
DNSMASQ_BLOCK_CONF="/etc/dnsmasq.d/paqet-dns-policy-blocklist.conf"
ALLOW_FILE="${DNS_POLICY_DIR}/allow_domains.txt"
CRON_FILE="/etc/cron.d/paqet-dns-policy-update"
UPDATE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/update_dns_policy_list.sh"
DNS_PORT=5353

CATEGORY="${1:-ads}"
case "${CATEGORY}" in
  ads|all|proxy) ;;
  *)
    echo "Invalid category: ${CATEGORY} (allowed: ads|all|proxy)" >&2
    exit 1
    ;;
esac

if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq curl ca-certificates
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y dnsmasq curl ca-certificates
elif command -v yum >/dev/null 2>&1; then
  yum install -y dnsmasq curl ca-certificates
fi

if ! id -u "${PAQET_USER}" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "${PAQET_USER}"
fi
PAQET_UID="$(id -u "${PAQET_USER}")"

mkdir -p "${DNS_POLICY_DIR}" /etc/dnsmasq.d

cat > "${DNSMASQ_MAIN_CONF}" <<CONF
# Paqet DNS policy resolver
port=${DNS_PORT}
listen-address=127.0.0.1
bind-interfaces
no-resolv
server=1.1.1.1
server=1.0.0.1
cache-size=10000
conf-file=${DNSMASQ_BLOCK_CONF}
CONF

if [ ! -f "${ALLOW_FILE}" ]; then
  cat > "${ALLOW_FILE}" <<CONF
# One domain per line to allow (override blocklist).
# Example:
# example.com
CONF
fi

"${UPDATE_SCRIPT}" "${CATEGORY}"

systemctl enable --now dnsmasq >/dev/null 2>&1 || true

while iptables -t nat -D OUTPUT -m owner --uid-owner "${PAQET_UID}" -p udp --dport 53 -m comment --comment paqet-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done
while iptables -t nat -D OUTPUT -m owner --uid-owner "${PAQET_UID}" -p tcp --dport 53 -m comment --comment paqet-dns-policy -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null; do :; done

iptables -t nat -A OUTPUT -m owner --uid-owner "${PAQET_UID}" -p udp --dport 53 -m comment --comment paqet-dns-policy -j REDIRECT --to-ports "${DNS_PORT}"
iptables -t nat -A OUTPUT -m owner --uid-owner "${PAQET_UID}" -p tcp --dport 53 -m comment --comment paqet-dns-policy -j REDIRECT --to-ports "${DNS_PORT}"

cat > "${CRON_FILE}" <<CONF
SHELL=/bin/bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin
17 3 * * * root ${UPDATE_SCRIPT} --quiet >/var/log/paqet-dns-policy-update.log 2>&1
CONF
chmod 644 "${CRON_FILE}"

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

echo "DNS policy enabled for paqet traffic."
echo "Category: ${CATEGORY}"
echo "Resolver: 127.0.0.1:${DNS_PORT}"
echo "Whitelist file: ${ALLOW_FILE}"
