#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
BIN_PATH="${PAQET_DIR}/paqet"
CLIENT_CONFIG="${PAQET_DIR}/client.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PROXYCHAINS="${SCRIPT_DIR}/install_proxychains4.sh"
NET_PREFIX=()

github_reachable() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --connect-timeout 3 --max-time 5 https://api.github.com/repos/hanselime/paqet/releases/latest >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=5 --spider https://api.github.com/repos/hanselime/paqet/releases/latest >/dev/null 2>&1
  else
    return 1
  fi
}

get_socks_listen() {
  local socks=""
  if [ -f "${CLIENT_CONFIG}" ]; then
    socks="$(awk '
      $1 == "socks5:" { insocks=1; next }
      insocks && $1 == "-" && $2 == "listen:" { gsub(/"/, "", $3); print $3; exit }
      insocks && $1 == "listen:" { gsub(/"/, "", $2); print $2; exit }
    ' "${CLIENT_CONFIG}")"
  fi
  if [ -z "${socks}" ]; then
    socks="127.0.0.1:1080"
  fi
  echo "${socks}"
}

require_paqet_socks() {
  if [ ! -f "${CLIENT_CONFIG}" ]; then
    echo "Client config not found: ${CLIENT_CONFIG}" >&2
    echo "You must configure and run paqet client at least once before using proxychains." >&2
    return 1
  fi
  if command -v curl >/dev/null 2>&1; then
    local socks
    socks="$(get_socks_listen)"
    if ! curl -fsSL --connect-timeout 5 --max-time 10 https://api.github.com --proxy "socks5h://${socks}" >/dev/null 2>&1; then
      echo "SOCKS proxy test failed: ${socks}" >&2
      echo "Ensure paqet client is running and client 'Test connection' succeeds." >&2
      return 1
    fi
  else
    echo "Warning: curl not found; cannot verify SOCKS proxy." >&2
  fi
}

print_manual_notice() {
  local arch_raw arch name
  arch_raw="$(uname -m)"
  case "${arch_raw}" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) arch="<arch>" ;;
  esac
  name="paqet-linux-${arch}-<version>.tar.gz"
  echo "Unable to fetch release from GitHub." >&2
  echo "Please put the latest paqet tarball in ${PAQET_DIR} and re-run update." >&2
  echo "Expected filename pattern: ${name}" >&2
  echo "Releases: https://github.com/hanselime/paqet/releases/latest" >&2
}

get_latest_tag() {
  if command -v curl >/dev/null 2>&1; then
    "${NET_PREFIX[@]}" curl -fsSL --connect-timeout 5 --max-time 12 https://api.github.com/repos/hanselime/paqet/releases/latest 2>/dev/null | awk -F '\"' '/tag_name/{print $4; exit}' || true
  else
    "${NET_PREFIX[@]}" wget -qO- --timeout=12 https://api.github.com/repos/hanselime/paqet/releases/latest 2>/dev/null | awk -F '\"' '/tag_name/{print $4; exit}' || true
  fi
}

enable_proxychains_mode() {
  if command -v proxychains4 >/dev/null 2>&1 || command -v proxychains >/dev/null 2>&1; then
    read -r -p "Use proxychains to update paqet via paqet SOCKS? [y/N]: " use_proxy
  else
    read -r -p "Install proxychains4 and use it to update paqet via paqet SOCKS? [y/N]: " use_proxy
  fi

  case "${use_proxy}" in
    y|Y)
      if ! command -v proxychains4 >/dev/null 2>&1 && ! command -v proxychains >/dev/null 2>&1; then
        if [ -x "${INSTALL_PROXYCHAINS}" ]; then
          "${INSTALL_PROXYCHAINS}"
        else
          echo "Proxychains installer not found: ${INSTALL_PROXYCHAINS}" >&2
          return 1
        fi
      fi
      if ! require_paqet_socks; then
        return 1
      fi
      if command -v proxychains4 >/dev/null 2>&1; then
        NET_PREFIX=(proxychains4)
      else
        NET_PREFIX=(proxychains)
      fi
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "curl or wget is required to check releases." >&2
  exit 1
fi

latest=""
if github_reachable; then
  latest="$(get_latest_tag)"
  if [ -z "${latest}" ]; then
    echo "Direct GitHub API query returned no release tag." >&2
    if enable_proxychains_mode; then
      latest="$(get_latest_tag)"
    else
      print_manual_notice
      exit 1
    fi
  fi
else
  echo "GitHub is not reachable from this server." >&2
  if enable_proxychains_mode; then
    latest="$(get_latest_tag)"
  else
    print_manual_notice
    exit 1
  fi
fi

if [ -z "${latest}" ]; then
  echo "Failed to detect latest release tag from GitHub API." >&2
  print_manual_notice
  exit 1
fi

current=""
if [ -x "${BIN_PATH}" ]; then
  current="$("${BIN_PATH}" version 2>/dev/null | awk '{print $NF}' | head -n1 || true)"
fi

echo "Latest release: ${latest}"
if [ -n "${current}" ]; then
  echo "Current version: ${current}"
fi
echo "Notice: Ensure BOTH server and client use the same paqet version."

if [ "${current}" = "${latest}" ]; then
  echo "Already up to date."
  exit 0
fi

read -r -p "Update paqet to ${latest}? [y/N]: " confirm
case "${confirm}" in
  y|Y) ;;
  *) echo "Aborted."; exit 0 ;;
esac

# Stop services if present
systemctl stop paqet-server.service 2>/dev/null || true
systemctl stop paqet-client.service 2>/dev/null || true

# Backup current binary if present
if [ -f "${BIN_PATH}" ]; then
  if [ -n "${current}" ]; then
    cp -f "${BIN_PATH}" "${BIN_PATH}.bak.${current}" || true
  else
    cp -f "${BIN_PATH}" "${BIN_PATH}.bak" || true
  fi
fi

# Remove old files (keep configs)
rm -f "${PAQET_DIR}/paqet"
rm -f "${PAQET_DIR}/README.md"
rm -rf "${PAQET_DIR}/example"

# Prefer local tarball for latest if present
OS="linux"
ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) ARCH="unknown" ;;
esac
NAME="paqet-${OS}-${ARCH}-${latest}.tar.gz"
TARBALL_PATH="${PAQET_DIR}/${NAME}"

if [ ! -s "${TARBALL_PATH}" ]; then
  echo "Latest tarball not found locally: ${TARBALL_PATH}"
  echo "If GitHub is blocked, download on the other VPS and copy it here."
  echo "Example:"
  echo "  scp ${NAME} root@<IRAN_VPS_IP>:${PAQET_DIR}/"
fi

# Run installer (will fetch latest or use local tarball)
INSTALL_SCRIPT="${SCRIPT_DIR}/install_paqet.sh"
if [ ! -x "${INSTALL_SCRIPT}" ]; then
  echo "Installer not found: ${INSTALL_SCRIPT}" >&2
  exit 1
fi

if [ "${#NET_PREFIX[@]}" -gt 0 ]; then
  "${NET_PREFIX[@]}" env VERSION="${latest}" "${INSTALL_SCRIPT}"
else
  env VERSION="${latest}" "${INSTALL_SCRIPT}"
fi

# Restart services if configs exist
if [ -f "${PAQET_DIR}/server.yaml" ]; then
  systemctl restart paqet-server.service 2>/dev/null || true
fi
if [ -f "${PAQET_DIR}/client.yaml" ]; then
  systemctl restart paqet-client.service 2>/dev/null || true
fi

echo "Update completed."
