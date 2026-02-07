#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
INFO_FILE="${PAQET_DIR}/server_info.txt"
CONFIG_FILE="${PAQET_DIR}/server.yaml"

PORT=""

if [ -f "${CONFIG_FILE}" ]; then
  PORT="$(awk '
    $1 == "listen:" { inlisten=1; next }
    inlisten && $1 == "addr:" {
      gsub(/"/, "", $2);
      sub(/^:/, "", $2);
      print $2;
      exit
    }
  ' "${CONFIG_FILE}")"
fi

if [ -z "${PORT}" ] && [ -f "${INFO_FILE}" ]; then
  PORT="$(awk -F= '/^listen_port=/{print $2; exit}' "${INFO_FILE}")"
fi

if [ -z "${PORT}" ]; then
  echo "Could not determine listen port. Create server config first (${CONFIG_FILE})." >&2
  exit 1
fi

add_rule() {
  local table="$1"; shift
  if iptables -t "${table}" -C "$@" 2>/dev/null; then
    return 0
  fi
  iptables -t "${table}" -A "$@"
}

remove_tagged_rules() {
  local table="$1"
  local chain="$2"
  local tag="$3"
  while read -r rule; do
    [ -z "${rule}" ] && continue
    iptables -t "${table}" ${rule} 2>/dev/null || true
  done < <(
    iptables -t "${table}" -S "${chain}" 2>/dev/null \
      | awk -v c="${chain}" -v t="${tag}" '$1=="-A" && $2==c && $0 ~ t { $1="-D"; print }'
  )
}

# Remove older paqet-tagged rules (possibly from a previous port) before adding current ones.
remove_tagged_rules raw PREROUTING "paqet-notrack-in"
remove_tagged_rules raw OUTPUT "paqet-notrack-out"
remove_tagged_rules mangle OUTPUT "paqet-rst-drop"
remove_tagged_rules filter INPUT "paqet-accept-in"
remove_tagged_rules filter OUTPUT "paqet-accept-out"

# Detect backend for persistence
BACKEND="legacy"
if iptables -V 2>/dev/null | grep -qi nf_tables; then
  BACKEND="nft"
fi

# Auto-detect OS family for persistence
if [ "${SKIP_PKG_INSTALL:-0}" != "1" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    if [ "${BACKEND}" = "legacy" ]; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent
    else
      DEBIAN_FRONTEND=noninteractive apt-get install -y nftables
    fi
  elif command -v dnf >/dev/null 2>&1; then
    if [ "${BACKEND}" = "legacy" ]; then
      dnf install -y iptables-services
      systemctl enable --now iptables
    else
      dnf install -y nftables
      systemctl enable --now nftables
    fi
  elif command -v yum >/dev/null 2>&1; then
    if [ "${BACKEND}" = "legacy" ]; then
      yum install -y iptables-services
      systemctl enable --now iptables
    else
      yum install -y nftables
      systemctl enable --now nftables
    fi
  else
    echo "No supported package manager found. Skipping persistence install." >&2
  fi
else
  echo "Skipping package install (SKIP_PKG_INSTALL=1)."
fi

# Add required rules
add_rule raw PREROUTING -p tcp --dport "${PORT}" -m comment --comment paqet-notrack-in -j NOTRACK
add_rule raw OUTPUT -p tcp --sport "${PORT}" -m comment --comment paqet-notrack-out -j NOTRACK
add_rule mangle OUTPUT -p tcp --sport "${PORT}" --tcp-flags RST RST -m comment --comment paqet-rst-drop -j DROP

# Optional accept rules (auto-enabled)
add_rule filter INPUT -p tcp --dport "${PORT}" -m comment --comment paqet-accept-in -j ACCEPT
add_rule filter OUTPUT -p tcp --sport "${PORT}" -m comment --comment paqet-accept-out -j ACCEPT

# Persist rules (handle nft vs legacy safely)
if [ "${BACKEND}" = "nft" ]; then
  # nft backend: avoid netfilter-persistent iptables-save errors
  if command -v nft >/dev/null 2>&1; then
    nft list ruleset > /etc/nftables.conf || true
    systemctl enable --now nftables >/dev/null 2>&1 || true
  fi
else
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save || true
  elif command -v iptables-save >/dev/null 2>&1; then
    if [ -d /etc/iptables ]; then
      iptables-save > /etc/iptables/rules.v4 || true
      echo "Saved to /etc/iptables/rules.v4"
    else
      echo "iptables-save available but /etc/iptables not found; skipping save." >&2
    fi
  elif command -v service >/dev/null 2>&1; then
    service iptables save || true
  fi
fi

echo "Server iptables rules added for port ${PORT}."
