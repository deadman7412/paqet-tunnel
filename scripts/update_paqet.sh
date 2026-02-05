#!/usr/bin/env bash
set -euo pipefail

PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
BIN_PATH="${PAQET_DIR}/paqet"

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "curl or wget is required to check releases." >&2
  exit 1
fi

latest=""
if command -v curl >/dev/null 2>&1; then
  latest="$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.github.com/repos/hanselime/paqet/releases/latest 2>/dev/null | awk -F '\"' '/tag_name/{print $4; exit}' || true)"
else
  latest="$(wget -qO- --timeout=10 https://api.github.com/repos/hanselime/paqet/releases/latest 2>/dev/null | awk -F '\"' '/tag_name/{print $4; exit}' || true)"
fi

if [ -z "${latest}" ]; then
  echo "Failed to detect latest release tag from GitHub API." >&2
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install_paqet.sh"
if [ ! -x "${INSTALL_SCRIPT}" ]; then
  echo "Installer not found: ${INSTALL_SCRIPT}" >&2
  exit 1
fi

"${INSTALL_SCRIPT}"

# Restart services if configs exist
if [ -f "${PAQET_DIR}/server.yaml" ]; then
  systemctl restart paqet-server.service 2>/dev/null || true
fi
if [ -f "${PAQET_DIR}/client.yaml" ]; then
  systemctl restart paqet-client.service 2>/dev/null || true
fi

echo "Update completed."
