#!/usr/bin/env bash
set -euo pipefail

WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"

if [ ! -d "${WATERWALL_DIR}" ]; then
  echo "Waterwall directory not found: ${WATERWALL_DIR}"
  exit 0
fi

echo "This will remove: ${WATERWALL_DIR}"
read -r -p "Proceed with Waterwall uninstall? [y/N]: " confirm
case "${confirm}" in
  y|Y|yes|YES)
    rm -rf "${WATERWALL_DIR}"
    echo "Waterwall removed: ${WATERWALL_DIR}"
    ;;
  *)
    echo "Aborted."
    ;;
esac
