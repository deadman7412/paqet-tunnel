#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"

read -r -p "Remove paqet directory ${PAQET_DIR}? [y/N]: " CONFIRM
case "${CONFIRM}" in
  y|Y) ;;
  *) echo "Aborted."; exit 0 ;;
esac

# Stop/disable known services if present
for svc in paqet-server paqet-client; do
  echo "Stopping ${svc}.service (if running)..."
  systemctl stop "${svc}.service" 2>/dev/null || true
  echo "Disabling ${svc}.service (if enabled)..."
  systemctl disable "${svc}.service" 2>/dev/null || true
  if [ -f "/etc/systemd/system/${svc}.service" ]; then
    echo "Removing /etc/systemd/system/${svc}.service"
    rm -f "/etc/systemd/system/${svc}.service"
  else
    echo "Service file not found: /etc/systemd/system/${svc}.service"
  fi
done
echo "Reloading systemd daemon..."
systemctl daemon-reload 2>/dev/null || true

# Remove cron jobs created by this menu
echo "Removing cron jobs (if present)..."
if [ -f /etc/cron.d/paqet-restart-paqet-server ]; then
  echo "Removing /etc/cron.d/paqet-restart-paqet-server"
  rm -f /etc/cron.d/paqet-restart-paqet-server
else
  echo "Cron file not found: /etc/cron.d/paqet-restart-paqet-server"
fi

if [ -f /etc/cron.d/paqet-restart-paqet-client ]; then
  echo "Removing /etc/cron.d/paqet-restart-paqet-client"
  rm -f /etc/cron.d/paqet-restart-paqet-client
else
  echo "Cron file not found: /etc/cron.d/paqet-restart-paqet-client"
fi

# Remove UFW rules created by paqet scripts
echo "Cleaning UFW paqet rules (if present)..."
if command -v ufw >/dev/null 2>&1; then
  status_line="$(ufw status 2>/dev/null | head -n1 || true)"
  if echo "${status_line}" | grep -qiE "Status: (active|inactive)"; then
    # Keep SSH access intact; only remove tunnel/loopback rules.
    mapfile -t UFW_RULES < <(ufw status numbered 2>/dev/null | awk '/paqet-(tunnel|loopback)/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
    if [ "${#UFW_RULES[@]}" -gt 0 ]; then
      # Delete from highest number to avoid rule index shifts.
      for ((i=${#UFW_RULES[@]}-1; i>=0; i--)); do
        ufw --force delete "${UFW_RULES[$i]}" >/dev/null 2>&1 || true
      done
      echo "Removed UFW paqet rule(s)."
    else
      echo "No UFW paqet rules found."
    fi
    ufw status verbose || true
  else
    echo "UFW status unavailable; skipping UFW cleanup."
  fi
else
  echo "ufw not installed; skipping UFW cleanup."
fi

# Remove WARP-related files
echo "Removing WARP files (if present)..."
echo "Disabling WARP interface and routing (if present)..."
wg-quick down wgcf >/dev/null 2>&1 || true
ip rule del fwmark 51820 table 51820 2>/dev/null || true
ip route flush table 51820 2>/dev/null || true
iptables -t mangle -D OUTPUT -m owner --uid-owner paqet -j MARK --set-mark 51820 2>/dev/null || true
iptables -t mangle -D OUTPUT -m owner --uid-owner paqet -j MARK --set-mark 51820 2>/dev/null || true
# Remove nft mark rule if present
if command -v nft >/dev/null 2>&1; then
  nft delete rule inet mangle output meta skuid \"paqet\" meta mark set 51820 2>/dev/null || true
fi
# Save firewall changes (handle nft vs legacy safely)
if iptables -V 2>/dev/null | grep -qi nf_tables; then
  # nft backend: avoid netfilter-persistent iptables-save errors
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

if [ -d /etc/systemd/system/paqet-server.service.d ]; then
  if [ -f /etc/systemd/system/paqet-server.service.d/10-warp.conf ]; then
    echo "Removing /etc/systemd/system/paqet-server.service.d/10-warp.conf"
    rm -f /etc/systemd/system/paqet-server.service.d/10-warp.conf
    systemctl daemon-reload 2>/dev/null || true
  fi
fi
if [ -d /root/wgcf ]; then
  echo "Removing /root/wgcf"
  rm -rf /root/wgcf
else
  echo "WARP folder not found: /root/wgcf"
fi

if [ -f /etc/wireguard/wgcf.conf ]; then
  echo "Removing /etc/wireguard/wgcf.conf"
  rm -f /etc/wireguard/wgcf.conf
else
  echo "WARP config not found: /etc/wireguard/wgcf.conf"
fi

if [ -x /usr/local/bin/wgcf ]; then
  echo "Removing /usr/local/bin/wgcf"
  rm -f /usr/local/bin/wgcf
else
  echo "wgcf binary not found: /usr/local/bin/wgcf"
fi

# Remove DNS policy files/rules (if present)
echo "Removing DNS policy files/rules (if present)..."
if [ -x "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/disable_dns_policy.sh" ]; then
  "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/disable_dns_policy.sh" >/dev/null 2>&1 || true
else
  rm -f /etc/cron.d/paqet-dns-policy-update
  rm -f /etc/dnsmasq.d/paqet-dns-policy.conf /etc/dnsmasq.d/paqet-dns-policy-blocklist.conf
  rm -rf /etc/paqet-dns-policy
fi

# Remove paqet directory
rm -rf "${PAQET_DIR}"
rm -rf /opt/paqet 2>/dev/null || true

echo "Uninstalled paqet from ${PAQET_DIR}"

read -r -p "Reboot now? [y/N]: " REBOOT
case "${REBOOT}" in
  y|Y)
    echo "Rebooting..."
    reboot
    ;;
  *) ;;
esac
