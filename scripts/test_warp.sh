#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "${SCRIPT_DIR}/test_warp_full.sh" ]; then
  exec "${SCRIPT_DIR}/test_warp_full.sh"
fi

echo "test_warp_full.sh not found. Running basic test..." >&2
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 1
fi
if ! id -u paqet >/dev/null 2>&1; then
  echo "User 'paqet' not found. WARP policy routing may not be enabled." >&2
  exit 1
fi

echo "Testing WARP egress as user 'paqet'..."
if sudo -u paqet curl -s --connect-timeout 5 --max-time 10 https://1.1.1.1/cdn-cgi/trace | grep -E 'warp=|ip='; then
  echo "Test completed."
else
  echo "WARP test failed or timed out." >&2
  exit 1
fi
