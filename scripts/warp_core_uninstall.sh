#!/usr/bin/env bash
set -euo pipefail

TABLE_ID=51820
MARK=51820
SSH_PROXY_USERS_DIR="/etc/paqet-ssh-proxy/users"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if id -u paqet >/dev/null 2>&1; then
  PAQET_UID="$(id -u paqet)"
  while ip rule del uidrange "${PAQET_UID}-${PAQET_UID}" table ${TABLE_ID} 2>/dev/null; do :; done
  while ip rule del uidrange "${PAQET_UID}-${PAQET_UID}" table wgcf 2>/dev/null; do :; done
fi

if [ -d "${SSH_PROXY_USERS_DIR}" ]; then
  while IFS= read -r user; do
    [ -z "${user}" ] && continue
    if id -u "${user}" >/dev/null 2>&1; then
      uid="$(id -u "${user}")"
      while ip rule del uidrange "${uid}-${uid}" table ${TABLE_ID} 2>/dev/null; do :; done
      while ip rule del uidrange "${uid}-${uid}" table wgcf 2>/dev/null; do :; done
    fi
  done < <(awk -F= '/^username=/{print $2}' "${SSH_PROXY_USERS_DIR}"/*.env 2>/dev/null || true)
fi

while ip rule del fwmark ${MARK} table ${TABLE_ID} 2>/dev/null; do :; done
while ip rule del fwmark 0xca6c table ${TABLE_ID} 2>/dev/null; do :; done
while ip rule del fwmark 0xca6c table wgcf 2>/dev/null; do :; done

ip route flush table ${TABLE_ID} 2>/dev/null || true
wg-quick down wgcf >/dev/null 2>&1 || true

rm -f /etc/wireguard/wgcf.conf
rm -rf /root/wgcf
rm -f /usr/local/bin/wgcf

echo "WARP core uninstalled."
