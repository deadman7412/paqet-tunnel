#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== SSH CONNECTION UID CHECKER ===${NC}"
echo
echo "This script monitors which UID is actually making connections"
echo "when you connect via SSH proxy."
echo

# Get SSH proxy port
SSH_PROXY_PORT=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}' | head -1)
[ -z "${SSH_PROXY_PORT}" ] && SSH_PROXY_PORT=22

echo -e "${BLUE}[INFO]${NC} SSH is listening on port: ${SSH_PROXY_PORT}"
echo
echo "Instructions:"
echo "  1. Keep this terminal open"
echo "  2. On your phone, connect to SSH proxy"
echo "  3. Try to browse to digikala.com"
echo "  4. Check the output below to see which UID made the connection"
echo
echo "Monitoring active connections..."
echo "Press Ctrl+C to stop"
echo
echo "Format: [UID] [Command] [Connection]"
echo "----------------------------------------"

while true; do
  # Show active SSH connections and their UIDs
  netstat -tnp 2>/dev/null | grep ":${SSH_PROXY_PORT}" | grep ESTABLISHED | while read line; do
    pid=$(echo "$line" | awk '{print $7}' | cut -d/ -f1)
    if [ -n "$pid" ] && [ "$pid" != "-" ]; then
      uid=$(ps -o uid= -p "$pid" 2>/dev/null || echo "?")
      cmd=$(ps -o comm= -p "$pid" 2>/dev/null || echo "?")
      echo "[UID: $uid] [$cmd] $line"
    fi
  done

  sleep 2
done
