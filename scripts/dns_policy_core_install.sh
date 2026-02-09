#!/usr/bin/env bash
set -euo pipefail

DNS_POLICY_DIR="/etc/paqet-dns-policy"
DNSMASQ_MAIN_CONF="/etc/dnsmasq.d/paqet-dns-policy.conf"
DNSMASQ_BLOCK_CONF="/etc/dnsmasq.d/paqet-dns-policy-blocklist.conf"
ALLOW_FILE="${DNS_POLICY_DIR}/allow_domains.txt"
CRON_FILE="/etc/cron.d/paqet-dns-policy-update"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_SCRIPT="${SCRIPT_DIR}/update_dns_policy_list.sh"
RECONCILE_SCRIPT="${SCRIPT_DIR}/reconcile_policy_bindings.sh"
DNS_PORT=5353

CATEGORY="${1:-ads}"
case "${CATEGORY}" in
  ads|all|proxy) ;;
  *)
    echo "Invalid category: ${CATEGORY} (allowed: ads|all|proxy)" >&2
    exit 1
    ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq curl ca-certificates
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y dnsmasq curl ca-certificates
elif command -v yum >/dev/null 2>&1; then
  yum install -y dnsmasq curl ca-certificates
fi

mkdir -p "${DNS_POLICY_DIR}" /etc/dnsmasq.d

UPSTREAMS="${DNS_POLICY_UPSTREAMS:-}"
{
  cat <<CONF
# Paqet DNS policy resolver
port=${DNS_PORT}
listen-address=127.0.0.1
bind-interfaces
cache-size=10000
conf-file=${DNSMASQ_BLOCK_CONF}
CONF
  if [ -n "${UPSTREAMS}" ]; then
    echo "no-resolv"
    IFS=',' read -r -a UP_ARR <<< "${UPSTREAMS}"
    for s in "${UP_ARR[@]}"; do
      s="$(echo "${s}" | xargs)"
      [ -n "${s}" ] && echo "server=${s}"
    done
  else
    echo "resolv-file=/etc/resolv.conf"
  fi
} > "${DNSMASQ_MAIN_CONF}"

if [ ! -f "${ALLOW_FILE}" ]; then
  cat > "${ALLOW_FILE}" <<CONF
# One domain per line to allow (override blocklist).
# Example:
# example.com
CONF
fi

"${UPDATE_SCRIPT}" "${CATEGORY}"

systemctl enable --now dnsmasq >/dev/null 2>&1 || true
systemctl restart dnsmasq >/dev/null 2>&1 || true

cat > "${CRON_FILE}" <<CONF
SHELL=/bin/bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin
17 3 * * * root ${UPDATE_SCRIPT} --quiet >/var/log/paqet-dns-policy-update.log 2>&1
CONF
chmod 644 "${CRON_FILE}"

echo "DNS policy core installed."
echo "Category: ${CATEGORY}"
echo "Resolver: 127.0.0.1:${DNS_PORT}"

if command -v nslookup >/dev/null 2>&1; then
  if nslookup -port="${DNS_PORT}" example.com 127.0.0.1 >/dev/null 2>&1; then
    echo "Resolver self-check: OK"
  else
    echo "Resolver self-check: FAILED (check upstream DNS reachability and dnsmasq logs)" >&2
  fi
fi

if [ -x "${RECONCILE_SCRIPT}" ]; then
  "${RECONCILE_SCRIPT}" dns || true
fi
