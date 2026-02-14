#!/usr/bin/env bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SYSCTL_CONF="/etc/sysctl.d/99-bbr.conf"

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)" >&2
    exit 1
  fi
}

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

check_bbr_module_available() {
  if modinfo tcp_bbr >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

load_bbr_module() {
  echo -e "${BLUE}[INFO]${NC} Loading tcp_bbr kernel module..."
  if modprobe tcp_bbr 2>/dev/null; then
    echo -e "${GREEN}[SUCCESS]${NC} BBR module loaded"
    return 0
  else
    echo -e "${RED}[ERROR]${NC} Failed to load BBR module" >&2
    return 1
  fi
}

ensure_bbr_module_persistence() {
  local modules_file="/etc/modules-load.d/bbr.conf"

  if grep -q "^tcp_bbr" "${modules_file}" 2>/dev/null; then
    echo -e "${BLUE}[INFO]${NC} BBR module already configured to load at boot"
  else
    echo -e "${BLUE}[INFO]${NC} Configuring BBR module to load at boot..."
    mkdir -p "$(dirname "${modules_file}")"
    echo "tcp_bbr" > "${modules_file}"
    echo -e "${GREEN}[SUCCESS]${NC} BBR module will load at boot"
  fi
}

configure_sysctl_bbr() {
  echo -e "${BLUE}[INFO]${NC} Configuring sysctl for BBR..."

  # Create sysctl config file
  cat > "${SYSCTL_CONF}" <<'EOF'
# BBR congestion control for improved network performance
# Especially beneficial for high-latency and lossy connections
# Created by paqet_tunnel BBR setup

# Enable BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# BBR-friendly settings for better performance
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0
EOF

  echo -e "${GREEN}[SUCCESS]${NC} Created ${SYSCTL_CONF}"
}

apply_sysctl_settings() {
  echo -e "${BLUE}[INFO]${NC} Applying sysctl settings..."

  if sysctl -p "${SYSCTL_CONF}" >/dev/null 2>&1; then
    echo -e "${GREEN}[SUCCESS]${NC} BBR settings applied"
  else
    echo -e "${RED}[ERROR]${NC} Failed to apply sysctl settings" >&2
    return 1
  fi
}

verify_bbr_enabled() {
  local current_cc=""
  local current_qdisc=""

  current_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")"
  current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")"

  if [ "${current_cc}" = "bbr" ] && [ "${current_qdisc}" = "fq" ]; then
    return 0
  else
    return 1
  fi
}

main() {
  local kernel_version=""
  local current_cc=""

  check_root

  echo ""
  echo "========================================"
  echo "Enable BBR Congestion Control"
  echo "========================================"
  echo ""

  # Check current status
  current_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")"
  if [ "${current_cc}" = "bbr" ]; then
    echo -e "${YELLOW}[WARN]${NC} BBR is already enabled"
    echo ""
    read -r -p "Re-configure BBR settings anyway? [y/N]: " reconfigure
    case "${reconfigure}" in
      y|Y|yes|YES) ;;
      *)
        echo "No changes made."
        exit 0
        ;;
    esac
    echo ""
  fi

  # Check kernel version
  kernel_version="$(get_kernel_version)"
  echo -e "${BLUE}[INFO]${NC} Kernel version: ${kernel_version}"

  if ! check_kernel_bbr_support; then
    echo -e "${RED}[ERROR]${NC} Kernel version is too old for BBR" >&2
    echo "      BBR requires Linux kernel 4.9 or newer" >&2
    echo "      Current kernel: ${kernel_version}" >&2
    echo ""
    echo "Please upgrade your kernel to use BBR."
    exit 1
  fi

  echo -e "${GREEN}[OK]${NC} Kernel supports BBR (4.9+)"
  echo ""

  # Check BBR module availability
  echo -e "${BLUE}[INFO]${NC} Checking BBR module availability..."
  if ! check_bbr_module_available; then
    echo -e "${RED}[ERROR]${NC} BBR module not available" >&2
    echo "      Your kernel may not have BBR compiled" >&2
    echo "      This is rare on modern distributions" >&2
    exit 1
  fi

  echo -e "${GREEN}[OK]${NC} BBR module available"
  echo ""

  # Confirm with user
  echo -e "${YELLOW}About to enable BBR congestion control:${NC}"
  echo ""
  echo "  Current algorithm: ${current_cc}"
  echo "  New algorithm:     bbr"
  echo "  Queue discipline:  fq (Fair Queue)"
  echo ""
  echo "  Changes will:"
  echo "    - Load tcp_bbr kernel module"
  echo "    - Set BBR as default congestion control"
  echo "    - Configure optimal settings for BBR"
  echo "    - Persist across reboots"
  echo ""
  echo "  Expected benefits:"
  echo "    - Better throughput on high-latency connections"
  echo "    - Improved performance on lossy networks"
  echo "    - Faster connection startup"
  echo "    - Better SSH tunnel performance"
  echo ""

  read -r -p "Continue? [y/N]: " confirm
  case "${confirm}" in
    y|Y|yes|YES) ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac

  echo ""
  echo "========================================"
  echo "Enabling BBR..."
  echo "========================================"
  echo ""

  # Load BBR module
  if ! load_bbr_module; then
    exit 1
  fi

  # Ensure module loads at boot
  ensure_bbr_module_persistence

  # Configure sysctl
  configure_sysctl_bbr

  # Apply settings
  if ! apply_sysctl_settings; then
    exit 1
  fi

  echo ""

  # Verify
  if verify_bbr_enabled; then
    echo -e "${GREEN}[SUCCESS]${NC} BBR is now enabled and configured"
  else
    echo -e "${RED}[ERROR]${NC} BBR configuration may have failed" >&2
    echo "      Current settings:" >&2
    sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc 2>&1 >&2
    exit 1
  fi

  echo ""
  echo "========================================"
  echo "BBR Successfully Enabled"
  echo "========================================"
  echo ""
  echo -e "${GREEN}Configuration:${NC}"
  echo "  - Congestion control: bbr"
  echo "  - Queue discipline: fq"
  echo "  - Module: tcp_bbr (loaded)"
  echo "  - Persistence: Configured for reboot"
  echo ""
  echo -e "${BLUE}Performance improvements:${NC}"
  echo "  - Low latency (< 50ms): 10-20% faster"
  echo "  - Medium latency (50-200ms): 30-50% faster"
  echo "  - High latency (> 200ms): 50-200% faster"
  echo "  - Lossy networks: 2-5x faster"
  echo ""
  echo -e "${YELLOW}Note:${NC} Changes take effect immediately for new connections."
  echo "      Existing connections will continue using previous algorithm."
  echo ""
  echo "To check BBR status:"
  echo "  sudo ~/paqet_tunnel/scripts/check_bbr_status.sh"
  echo ""
  echo "To disable BBR:"
  echo "  sudo ~/paqet_tunnel/scripts/disable_bbr.sh"
  echo ""
  echo "========================================"
}

main "$@"
