#!/usr/bin/env bash
set -euo pipefail

ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"

echo "This will remove ICMP Tunnel completely:"
echo "  - Stop and remove systemd services"
echo "  - Remove ${ICMPTUNNEL_DIR}"
echo "  - Remove /opt/icmptunnel (if exists)"
echo "  - Remove icmptunnel system user (if exists)"
echo "  - Remove UFW firewall rules"
echo "  - Remove iptables rules (WARP/DNS)"
echo "  - Remove ip rules (WARP routing)"
echo "  - Remove policy state files"
echo
read -r -p "Continue? [y/N]: " confirm
case "${confirm}" in
  y|Y) ;;
  *) echo "Aborted."; exit 0 ;;
esac

# Stop and remove services
for role in server client; do
  SERVICE_NAME="icmptunnel-${role}"
  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    echo "Stopping and removing ${SERVICE_NAME}..."
    systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    rm -rf "/etc/systemd/system/${SERVICE_NAME}.service.d"
  fi
done

systemctl daemon-reload 2>/dev/null || true

# Remove directories
if [ -d "${ICMPTUNNEL_DIR}" ]; then
  echo "Removing ${ICMPTUNNEL_DIR}..."
  rm -rf "${ICMPTUNNEL_DIR}"
fi

if [ -d "/opt/icmptunnel" ]; then
  echo "Removing /opt/icmptunnel..."
  rm -rf "/opt/icmptunnel"
fi

# Remove UFW rules
if command -v ufw >/dev/null 2>&1; then
  echo "Removing UFW rules..."
  declare -a rules=()
  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk '/icmptunnel/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')
  if [ "${#rules[@]}" -gt 0 ]; then
    for ((i=${#rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
    done
    echo "Removed ${#rules[@]} UFW rule(s)."
  fi
fi

# Remove iptables rules (WARP/DNS)
if command -v iptables >/dev/null 2>&1 && id -u icmptunnel >/dev/null 2>&1; then
  ICMPTUNNEL_UID="$(id -u icmptunnel)"
  echo "Removing iptables rules..."

  # WARP rules (raw table)
  while iptables -t raw -C PREROUTING -p icmp -m comment --comment icmptunnel-notrack-in -j NOTRACK 2>/dev/null; do
    iptables -t raw -D PREROUTING -p icmp -m comment --comment icmptunnel-notrack-in -j NOTRACK 2>/dev/null || true
  done
  while iptables -t raw -C OUTPUT -p icmp -m comment --comment icmptunnel-notrack-out -j NOTRACK 2>/dev/null; do
    iptables -t raw -D OUTPUT -p icmp -m comment --comment icmptunnel-notrack-out -j NOTRACK 2>/dev/null || true
  done

  # DNS rules (nat table)
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${ICMPTUNNEL_UID}" -p udp --dport 53 -m comment --comment icmptunnel-dns-policy -j REDIRECT --to-ports 5353 2>/dev/null; do :; done
  while iptables -t nat -D OUTPUT -m owner --uid-owner "${ICMPTUNNEL_UID}" -p tcp --dport 53 -m comment --comment icmptunnel-dns-policy -j REDIRECT --to-ports 5353 2>/dev/null; do :; done

  # Save iptables
  if iptables -V 2>/dev/null | grep -qi nf_tables; then
    if command -v nft >/dev/null 2>&1; then
      nft list ruleset > /etc/nftables.conf 2>/dev/null || true
    fi
  else
    if command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save 2>/dev/null || true
    elif [ -d /etc/iptables ]; then
      iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
  fi
fi

# Remove ip rules (WARP routing)
if id -u icmptunnel >/dev/null 2>&1; then
  ICMPTUNNEL_UID="$(id -u icmptunnel)"
  echo "Removing ip rules..."
  while ip rule show | grep -Eq "uidrange ${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}"; do
    ip rule del uidrange "${ICMPTUNNEL_UID}-${ICMPTUNNEL_UID}" 2>/dev/null || true
  done
fi

# Remove system user
if id -u icmptunnel >/dev/null 2>&1; then
  echo "Removing icmptunnel system user..."
  userdel icmptunnel 2>/dev/null || true
fi

# Remove policy state files
if [ -d "/etc/icmptunnel-policy" ]; then
  echo "Removing /etc/icmptunnel-policy..."
  rm -rf "/etc/icmptunnel-policy"
fi

echo
echo "ICMP Tunnel uninstalled successfully."
echo
echo "Note: WARP and DNS policy cores are shared with other tunnels."
echo "Run 'WARP/DNS core -> Uninstall' menus to remove them if not needed."
