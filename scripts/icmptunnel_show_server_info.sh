#!/usr/bin/env bash
set -euo pipefail

ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
INFO_FILE="${ICMPTUNNEL_DIR}/server_info.txt"

if [ ! -f "${INFO_FILE}" ]; then
  echo "Server info file not found: ${INFO_FILE}" >&2
  echo "Run 'Server setup' first to generate server_info.txt." >&2
  exit 1
fi

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}ICMP Tunnel Server Information${NC}"
echo -e "${BLUE}===================================${NC}"
echo

# Parse and display values
while IFS='=' read -r key value; do
  # Skip comments and empty lines
  [[ "${key}" =~ ^#.*$ ]] && continue
  [[ -z "${key}" ]] && continue

  case "${key}" in
    format_version) echo -e "${GREEN}Format Version:${NC} ${value}" ;;
    created_at) echo -e "${GREEN}Created At:${NC} ${value}" ;;
    server_public_ip) echo -e "${GREEN}Server Public IP:${NC} ${value}" ;;
    api_port) echo -e "${GREEN}API Port:${NC} ${value}" ;;
    auth_key) echo -e "${GREEN}Authentication Key:${NC} ${value}" ;;
    encrypt_data) echo -e "${GREEN}Encryption Enabled:${NC} ${value}" ;;
    encrypt_data_key) echo -e "${GREEN}Encryption Key:${NC} ${value}" ;;
    dns_server) echo -e "${GREEN}DNS Server:${NC} ${value}" ;;
    timeout) echo -e "${GREEN}Timeout:${NC} ${value} seconds" ;;
  esac
done < "${INFO_FILE}"

echo
echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}Transfer to Client VPS${NC}"
echo -e "${BLUE}===================================${NC}"
echo
echo -e "${YELLOW}Copy and paste these commands on the CLIENT VPS:${NC}"
echo
echo "mkdir -p ${ICMPTUNNEL_DIR}"
echo "cat <<'EOF' > ${INFO_FILE}"
grep -v '^#' "${INFO_FILE}"
echo "EOF"
echo
echo -e "${YELLOW}Then run: ICMP Tunnel -> Client menu -> Client setup${NC}"
