#!/usr/bin/env bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SYSCTL_CONF="/etc/sysctl.d/99-bbr.conf"
MODULES_CONF="/etc/modules-load.d/bbr.conf"

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)" >&2
    exit 1
  fi
}

remove_sysctl_config() {
  if [ -f "${SYSCTL_CONF}" ]; then
    echo -e "${BLUE}[INFO]${NC} Removing BBR sysctl configuration..."
    rm -f "${SYSCTL_CONF}"
    echo -e "${GREEN}[SUCCESS]${NC} Removed ${SYSCTL_CONF}"
  else
    echo -e "${BLUE}[INFO]${NC} BBR sysctl config not found (already removed)"
  fi
}

remove_module_config() {
  if [ -f "${MODULES_CONF}" ]; then
    echo -e "${BLUE}[INFO]${NC} Removing BBR module autoload configuration..."
    rm -f "${MODULES_CONF}"
    echo -e "${GREEN}[SUCCESS]${NC} Removed ${MODULES_CONF}"
  else
    echo -e "${BLUE}[INFO]${NC} BBR module config not found (already removed)"
  fi
}

revert_to_cubic() {
  echo -e "${BLUE}[INFO]${NC} Reverting to CUBIC congestion control..."

  # Set CUBIC as congestion control
  if sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1; then
    echo -e "${GREEN}[SUCCESS]${NC} Set congestion control to CUBIC"
  else
    echo -e "${RED}[ERROR]${NC} Failed to set CUBIC" >&2
    return 1
  fi

  # Set pfifo_fast as default qdisc (traditional default)
  if sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1; then
    echo -e "${GREEN}[SUCCESS]${NC} Set queue discipline to pfifo_fast"
  else
    echo -e "${YELLOW}[WARN]${NC} Could not set pfifo_fast (not critical)"
  fi
}

remove_bbr_from_global_sysctl() {
  local files_modified=0

  # Remove BBR settings from /etc/sysctl.conf if present
  if [ -f /etc/sysctl.conf ]; then
    if grep -q "tcp_congestion_control.*=.*bbr" /etc/sysctl.conf 2>/dev/null; then
      echo -e "${BLUE}[INFO]${NC} Removing BBR settings from /etc/sysctl.conf..."
      sed -i.bak '/net\.ipv4\.tcp_congestion_control.*bbr/d' /etc/sysctl.conf
      sed -i.bak '/net\.core\.default_qdisc.*fq/d' /etc/sysctl.conf
      files_modified=$((files_modified + 1))
    fi
  fi

  # Check other sysctl.d files
  for conf_file in /etc/sysctl.d/*.conf; do
    if [ -f "${conf_file}" ] && [ "${conf_file}" != "${SYSCTL_CONF}" ]; then
      if grep -q "tcp_congestion_control.*=.*bbr" "${conf_file}" 2>/dev/null; then
        echo -e "${YELLOW}[WARN]${NC} Found BBR settings in ${conf_file}"
        echo "      You may want to manually review this file"
      fi
    fi
  done

  if [ "${files_modified}" -gt 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Cleaned BBR settings from system config files"
  fi
}

verify_bbr_disabled() {
  local current_cc=""

  current_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")"

  if [ "${current_cc}" != "bbr" ]; then
    return 0
  else
    return 1
  fi
}

main() {
  local current_cc=""

  check_root

  echo ""
  echo "========================================"
  echo "Disable BBR Congestion Control"
  echo "========================================"
  echo ""

  # Check current status
  current_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")"

  if [ "${current_cc}" != "bbr" ]; then
    echo -e "${YELLOW}[WARN]${NC} BBR is not currently active"
    echo "      Current congestion control: ${current_cc}"
    echo ""
    read -r -p "Remove BBR configuration files anyway? [y/N]: " remove_anyway
    case "${remove_anyway}" in
      y|Y|yes|YES) ;;
      *)
        echo "No changes made."
        exit 0
        ;;
    esac
    echo ""
  fi

  # Confirm with user
  echo -e "${YELLOW}About to disable BBR congestion control:${NC}"
  echo ""
  echo "  Current algorithm: ${current_cc}"
  echo "  New algorithm:     cubic (default)"
  echo ""
  echo "  Changes will:"
  echo "    - Revert to CUBIC congestion control"
  echo "    - Remove BBR configuration files"
  echo "    - Remove BBR module autoload"
  echo "    - Settings will persist across reboots"
  echo ""
  echo "  Note: BBR module will remain loaded until reboot"
  echo "        (harmless - will not load on next boot)"
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
  echo "Disabling BBR..."
  echo "========================================"
  echo ""

  # Revert to CUBIC
  if ! revert_to_cubic; then
    exit 1
  fi

  # Remove configuration files
  remove_sysctl_config
  remove_module_config
  remove_bbr_from_global_sysctl

  echo ""

  # Verify
  if verify_bbr_disabled; then
    echo -e "${GREEN}[SUCCESS]${NC} BBR is now disabled"
  else
    echo -e "${RED}[ERROR]${NC} BBR may still be active" >&2
    echo "      Current settings:" >&2
    sysctl net.ipv4.tcp_congestion_control 2>&1 >&2
    exit 1
  fi

  echo ""
  echo "========================================"
  echo "BBR Successfully Disabled"
  echo "========================================"
  echo ""
  echo -e "${GREEN}Configuration:${NC}"
  echo "  - Congestion control: ${current_cc} → cubic"
  echo "  - BBR config files: Removed"
  echo "  - Module autoload: Disabled"
  echo "  - Persistence: CUBIC will be default after reboot"
  echo ""
  echo -e "${BLUE}Note:${NC} tcp_bbr module remains loaded until reboot"
  echo "      This is harmless - it won't load on next boot"
  echo ""
  echo "To re-enable BBR:"
  echo "  sudo ~/paqet_tunnel/scripts/enable_bbr.sh"
  echo ""
  echo "To check current status:"
  echo "  sudo ~/paqet_tunnel/scripts/check_bbr_status.sh"
  echo ""
  echo "========================================"
}

main "$@"
