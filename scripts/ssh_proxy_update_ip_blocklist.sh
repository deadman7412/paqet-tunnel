#!/usr/bin/env bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Just re-run the enable script which will update the IP list
echo -e "${BLUE}[INFO]${NC} Updating Iranian IP blocklist..."
echo

exec "${SCRIPT_DIR}/ssh_proxy_enable_ip_blocking.sh"
