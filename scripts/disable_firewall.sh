#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
if [ -z "${ROLE}" ]; then
  echo "Role is required (server/client)." >&2
  exit 1
fi
case "${ROLE}" in
  server|client) ;;
  *) echo "Invalid role." >&2; exit 1 ;;
esac

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw not installed." >&2
  exit 0
fi

# Get SSH ports from config to ensure we never remove them
SSH_PORTS="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u || true)"
if [ -z "${SSH_PORTS}" ]; then
  SSH_PORTS="22"
fi

echo "[INFO] SSH ports detected (will be protected): ${SSH_PORTS}"

# Remove only tunnel and loopback rules; keep SSH rules to avoid lockout
echo "[INFO] Removing paqet-tunnel rules..."
mapfile -t TUNNEL_RULES < <(ufw status numbered 2>/dev/null | awk '/paqet-tunnel/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')

if [ "${#TUNNEL_RULES[@]}" -gt 0 ]; then
  # Delete from highest number to avoid reindex issues
  for ((i=${#TUNNEL_RULES[@]}-1; i>=0; i--)); do
    ufw --force delete "${TUNNEL_RULES[$i]}" >/dev/null 2>&1 || true
  done
  echo "[SUCCESS] Removed ${#TUNNEL_RULES[@]} paqet-tunnel rule(s)."
else
  echo "[INFO] No paqet-tunnel rules found."
fi

echo "[INFO] Removing paqet-loopback rules..."
mapfile -t LOOPBACK_RULES < <(ufw status numbered 2>/dev/null | awk '/paqet-loopback/ { if (match($0, /^\[[[:space:]]*[0-9]+]/)) { n=substr($0, RSTART+1, RLENGTH-2); gsub(/[[:space:]]/, "", n); print n } }')

if [ "${#LOOPBACK_RULES[@]}" -gt 0 ]; then
  for ((i=${#LOOPBACK_RULES[@]}-1; i>=0; i--)); do
    ufw --force delete "${LOOPBACK_RULES[$i]}" >/dev/null 2>&1 || true
  done
  echo "[SUCCESS] Removed ${#LOOPBACK_RULES[@]} paqet-loopback rule(s)."
else
  echo "[INFO] No paqet-loopback rules found."
fi

echo ""
echo "========================================"
echo "Paqet Firewall Rules Removed"
echo "========================================"
echo ""
echo "[INFO] UFW remains ACTIVE with SSH protection."
echo "[INFO] SSH ports protected: ${SSH_PORTS}"
echo ""
echo "To completely disable UFW (NOT recommended):"
echo "  sudo ufw disable"
echo ""
echo "========================================"
echo ""
ufw status verbose
