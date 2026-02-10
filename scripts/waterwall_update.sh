#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "${SCRIPT_DIR}/waterwall_install.sh" ]; then
  echo "Install script not found or not executable: ${SCRIPT_DIR}/waterwall_install.sh" >&2
  exit 1
fi

echo "Updating Waterwall to latest available release (with local zip fallback)..."
exec "${SCRIPT_DIR}/waterwall_install.sh"
