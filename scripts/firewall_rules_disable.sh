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

remove_by_pattern() {
  local pattern="$1"
  local -a rules=()
  mapfile -t rules < <(ufw status numbered 2>/dev/null | awk -v p="${pattern}" '
    $0 ~ p {
      if (match($0, /^\[[[:space:]]*[0-9]+]/)) {
        n=substr($0, RSTART+1, RLENGTH-2)
        gsub(/[[:space:]]/, "", n)
        print n
      }
    }')
  if [ "${#rules[@]}" -gt 0 ]; then
    for ((i=${#rules[@]}-1; i>=0; i--)); do
      ufw --force delete "${rules[$i]}" >/dev/null 2>&1 || true
    done
  fi
}

case "${SCOPE}" in
  paqet)
    remove_by_pattern "paqet-(tunnel|loopback)"
    ;;
  ssh)
    remove_by_pattern "paqet-ssh-proxy"
    ;;
  waterwall)
    remove_by_pattern "waterwall-(tunnel|loopback)"
    ;;
  icmptunnel)
    remove_by_pattern "icmptunnel"
    ;;
  all)
    remove_by_pattern "paqet-(tunnel|loopback)"
    remove_by_pattern "paqet-ssh-proxy"
    remove_by_pattern "waterwall-(tunnel|loopback)"
    remove_by_pattern "icmptunnel"
    ;;
esac

if [ "${DISABLE_UFW}" = "1" ]; then
  ufw --force disable >/dev/null 2>&1 || true
fi

ufw status verbose || true
