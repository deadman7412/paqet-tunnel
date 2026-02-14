#!/usr/bin/env bash
set -euo pipefail

SCOPE="${1:-all}"
DISABLE_UFW="${2:-0}"

case "${SCOPE}" in
  paqet|ssh|waterwall|icmptunnel|all) ;;
  *)
    echo "Usage: $0 [paqet|ssh|waterwall|icmptunnel|all] [disable_ufw:0|1]" >&2
    exit 1
    ;;
esac

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw is not installed."
  exit 0
fi

# Get SSH ports from sshd config to ensure we NEVER remove them
get_ssh_ports() {
  local ports=""
  ports="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u || true)"
  if [ -z "${ports}" ]; then
    ports="22"
  fi
  echo "${ports}"
}

SSH_PORTS="$(get_ssh_ports)"
echo "[INFO] SSH ports detected (will be protected): ${SSH_PORTS}"

remove_by_pattern() {
  local pattern="$1"
  local -a rules=()
  local -a safe_rules=()
  local rule_num=""
  local rule_line=""
  local is_ssh_rule=""

  # Get all rules matching the pattern
  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk -v p="${pattern}" '
    $0 ~ p {
      if (match($0, /^\[[[:space:]]*[0-9]+]/)) {
        n=substr($0, RSTART+1, RLENGTH-2)
        gsub(/[[:space:]]/, "", n)
        print n "|||" $0
      }
    }')

  if [ "${#rules[@]}" -eq 0 ]; then
    return 0
  fi

  # Filter out SSH rules for extra safety
  for rule_entry in "${rules[@]}"; do
    rule_num="${rule_entry%%|||*}"
    rule_line="${rule_entry#*|||}"
    is_ssh_rule=0

    # Check if rule contains SSH-related comments or SSH ports
    if echo "${rule_line}" | grep -qiE "# (ssh|paqet-ssh)"; then
      echo "[WARN] Skipping rule ${rule_num}: SSH rule protected (${rule_line})"
      is_ssh_rule=1
    else
      # Check if rule uses SSH ports
      for ssh_port in ${SSH_PORTS}; do
        if echo "${rule_line}" | grep -qE "\\b${ssh_port}/tcp\\b"; then
          echo "[WARN] Skipping rule ${rule_num}: Uses SSH port ${ssh_port} (${rule_line})"
          is_ssh_rule=1
          break
        fi
      done
    fi

    # Only add to deletion list if not an SSH rule
    if [ "${is_ssh_rule}" -eq 0 ]; then
      safe_rules+=("${rule_num}")
    fi
  done

  # Delete safe rules in reverse order
  if [ "${#safe_rules[@]}" -gt 0 ]; then
    for ((i=${#safe_rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${safe_rules[$i]}" >/dev/null 2>&1 || true
    done
    echo "[SUCCESS] Removed ${#safe_rules[@]} firewall rule(s) matching pattern: ${pattern}"
  fi
}

echo ""
echo "========================================"
echo "Removing Firewall Rules: ${SCOPE}"
echo "========================================"
echo ""

case "${SCOPE}" in
  paqet)
    echo "[INFO] Removing paqet tunnel and loopback rules..."
    remove_by_pattern "paqet-(tunnel|loopback)"
    ;;
  ssh)
    echo "[INFO] Removing paqet SSH proxy rules..."
    echo "[WARN] This does NOT remove main SSH access rules!"
    remove_by_pattern "paqet-ssh-proxy"
    ;;
  waterwall)
    echo "[INFO] Removing waterwall tunnel and loopback rules..."
    remove_by_pattern "waterwall-(tunnel|loopback)"
    echo "[INFO] Removing waterwall service rules..."
    remove_by_pattern "waterwall-service"
    ;;
  icmptunnel)
    echo "[INFO] Removing icmptunnel rules..."
    remove_by_pattern "icmptunnel"
    ;;
  all)
    echo "[INFO] Removing ALL tunnel-related rules..."
    remove_by_pattern "paqet-(tunnel|loopback)"
    remove_by_pattern "paqet-ssh-proxy"
    remove_by_pattern "waterwall-(tunnel|loopback|service)"
    remove_by_pattern "icmptunnel"
    ;;
esac

echo ""
echo "========================================"

if [ "${DISABLE_UFW}" = "1" ]; then
  echo "[WARN] Disabling UFW completely (removes ALL protection)..."
  ufw --force disable >/dev/null 2>&1 || true
  echo "[WARN] UFW has been disabled!"
  echo "[WARN] Your server has NO firewall protection!"
else
  echo "[INFO] UFW remains ACTIVE."
  echo "[INFO] SSH ports protected: ${SSH_PORTS}"
fi

echo "========================================"
echo ""
ufw status verbose || true
