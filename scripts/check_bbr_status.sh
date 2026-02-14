#!/usr/bin/env bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

get_kernel_version() {
  uname -r
}

check_kernel_bbr_support() {
  local kernel_version=""
  local major=""
  local minor=""

  kernel_version="$(uname -r | cut -d. -f1-2)"
  major="$(echo "${kernel_version}" | cut -d. -f1)"
  minor="$(echo "${kernel_version}" | cut -d. -f2)"

  if [ "${major}" -gt 4 ] || { [ "${major}" -eq 4 ] && [ "${minor}" -ge 9 ]; }; then
    return 0
  else
    return 1
  fi
}

get_current_congestion_control() {
  sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown"
}

get_available_congestion_controls() {
  sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "unknown"
}

check_bbr_module_loaded() {
  if lsmod 2>/dev/null | grep -q "^tcp_bbr"; then
    return 0
  else
    return 1
  fi
}

check_bbr_module_available() {
  if modinfo tcp_bbr >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

main() {
  local kernel_version=""
  local current_cc=""
  local available_cc=""
  local bbr_status=""
  local bbr_color=""

  echo ""
  echo "========================================"
  echo "BBR Congestion Control Status"
  echo "========================================"
  echo ""

  # Kernel version
  kernel_version="$(get_kernel_version)"
  echo -e "${BLUE}[INFO]${NC} Kernel version: ${kernel_version}"

  # Check kernel support
  if check_kernel_bbr_support; then
    echo -e "${GREEN}[OK]${NC} Kernel supports BBR (4.9+)"
  else
    echo -e "${RED}[ERROR]${NC} Kernel too old for BBR (requires 4.9+)"
    echo "      Upgrade kernel to use BBR"
  fi

  echo ""

  # Check BBR module
  if check_bbr_module_available; then
    echo -e "${GREEN}[OK]${NC} BBR module available (tcp_bbr)"
    if check_bbr_module_loaded; then
      echo -e "${GREEN}[OK]${NC} BBR module loaded"
    else
      echo -e "${YELLOW}[WARN]${NC} BBR module not loaded (use 'modprobe tcp_bbr')"
    fi
  else
    echo -e "${RED}[ERROR]${NC} BBR module not available"
    echo "      Kernel may not have BBR compiled"
  fi

  echo ""

  # Current congestion control
  current_cc="$(get_current_congestion_control)"
  if [ "${current_cc}" = "bbr" ]; then
    bbr_status="ENABLED"
    bbr_color="${GREEN}"
  else
    bbr_status="DISABLED"
    bbr_color="${YELLOW}"
  fi

  echo -e "${bbr_color}[STATUS]${NC} Current congestion control: ${current_cc}"
  echo -e "${bbr_color}[STATUS]${NC} BBR is ${bbr_status}"

  # Available algorithms
  available_cc="$(get_available_congestion_controls)"
  echo -e "${BLUE}[INFO]${NC} Available algorithms: ${available_cc}"

  echo ""

  # Check persistence
  if grep -q "^net.ipv4.tcp_congestion_control.*=.*bbr" /etc/sysctl.conf /etc/sysctl.d/*.conf 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} BBR configured to persist across reboots"
  else
    if [ "${current_cc}" = "bbr" ]; then
      echo -e "${YELLOW}[WARN]${NC} BBR active but NOT persistent (will reset on reboot)"
      echo "      Run enable_bbr.sh to make it persistent"
    else
      echo -e "${BLUE}[INFO]${NC} BBR not configured in sysctl"
    fi
  fi

  echo ""
  echo "========================================"
  echo ""

  # Performance info
  if [ "${current_cc}" = "bbr" ]; then
    echo -e "${GREEN}BBR Performance Benefits:${NC}"
    echo "  - Better throughput on high-latency connections"
    echo "  - Improved performance on lossy networks"
    echo "  - Faster connection startup (ramp-up)"
    echo "  - Better handling of TCP-over-TCP (SSH tunnels)"
    echo ""
    echo "To disable BBR and revert to CUBIC:"
    echo "  sudo ~/paqet_tunnel/scripts/disable_bbr.sh"
  else
    echo -e "${BLUE}To enable BBR:${NC}"
    echo "  sudo ~/paqet_tunnel/scripts/enable_bbr.sh"
    echo ""
    echo -e "${BLUE}Expected performance improvements:${NC}"
    echo "  - Low latency (< 50ms): 10-20% faster"
    echo "  - Medium latency (50-200ms): 30-50% faster"
    echo "  - High latency (> 200ms): 50-200% faster"
    echo "  - Lossy networks: 2-5x faster"
  fi

  echo ""
  echo "========================================"
}

main "$@"
