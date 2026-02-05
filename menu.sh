#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
INSTALL_SCRIPT="${SCRIPTS_DIR}/install_paqet.sh"
PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

banner() {
  local ver=""
  if command -v git >/dev/null 2>&1 && git -C "${SCRIPT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ver="$(git -C "${SCRIPT_DIR}" describe --tags --always --dirty 2>/dev/null || true)"
  fi
  echo -e "${CYAN}=================================${NC}"
  echo -e "${CYAN}        Paqet Tunnel Menu        ${NC}"
  if [ -n "${ver}" ]; then
    echo -e "${CYAN}            ${ver}            ${NC}"
  fi
  echo -e "${CYAN}=================================${NC}"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "unknown" ;;
  esac
}

github_reachable() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --connect-timeout 3 --max-time 5 https://github.com/hanselime/paqet/releases/latest >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=5 --spider https://github.com/hanselime/paqet/releases/latest >/dev/null 2>&1
  else
    return 1
  fi
}

tarball_present() {
  ls "${PAQET_DIR}"/paqet-linux-*.tar.gz >/dev/null 2>&1
}

pause() {
  echo
  read -r -p "$(printf "${YELLOW}Press Enter to return to menu...${NC} ")" _
}

ensure_executable_scripts() {
  chmod +x "${SCRIPTS_DIR}"/*.sh 2>/dev/null || true
}

ensure_executable_scripts

run_action() {
  if ! "$@"; then
    echo -e "${RED}Action failed.${NC}" >&2
  fi
}

server_menu() {
  while true; do
    clear
    banner
    echo -e "${BLUE}Server Configuration${NC}"
    echo "--------------------"
    echo -e "${GREEN}1)${NC} Create server config"
    echo -e "${GREEN}2)${NC} Add iptable rules"
    echo -e "${GREEN}3)${NC} Install systemd service"
    echo -e "${GREEN}4)${NC} Remove iptable rules"
    echo -e "${GREEN}5)${NC} Remove systemd service"
    echo -e "${GREEN}6)${NC} Service control"
    echo -e "${GREEN}7)${NC} Restart scheduler"
    echo -e "${GREEN}8)${NC} Show server info"
    echo -e "${GREEN}9)${NC} Change MTU"
    echo -e "${GREEN}10)${NC} Health check"
    echo -e "${GREEN}11)${NC} Health logs"
    echo -e "${GREEN}12)${NC} Enable WARP (policy routing)"
    echo -e "${GREEN}13)${NC} Disable WARP (policy routing)"
    echo -e "${GREEN}14)${NC} WARP status"
    echo -e "${GREEN}15)${NC} Test WARP"
    echo -e "${GREEN}16)${NC} Enable firewall (ufw)"
    echo -e "${GREEN}17)${NC} Disable firewall (ufw)"
    echo
    echo
    echo -e "${GREEN}0)${NC} Back to main menu"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${SCRIPTS_DIR}/create_server_config.sh" ]; then
          run_action "${SCRIPTS_DIR}/create_server_config.sh"
          echo
          echo -e "${BLUE}Next:${NC} Copy ~/paqet/server_info.txt to the client VPS (same path) before creating client config."
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/create_server_config.sh" >&2
        fi
        pause
        ;;
      2)
        if [ -x "${SCRIPTS_DIR}/add_server_iptables.sh" ]; then
          run_action "${SCRIPTS_DIR}/add_server_iptables.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/add_server_iptables.sh" >&2
        fi
        pause
        ;;
      3)
        if [ -x "${SCRIPTS_DIR}/install_systemd_service.sh" ]; then
          run_action "${SCRIPTS_DIR}/install_systemd_service.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/install_systemd_service.sh" >&2
        fi
        pause
        ;;
      4)
        if [ -x "${SCRIPTS_DIR}/remove_server_iptables.sh" ]; then
          run_action "${SCRIPTS_DIR}/remove_server_iptables.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/remove_server_iptables.sh" >&2
        fi
        pause
        ;;
      5)
        if [ -x "${SCRIPTS_DIR}/remove_systemd_service.sh" ]; then
          run_action "${SCRIPTS_DIR}/remove_systemd_service.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/remove_systemd_service.sh" >&2
        fi
        pause
        ;;
      6)
        if [ -x "${SCRIPTS_DIR}/service_control.sh" ]; then
          run_action "${SCRIPTS_DIR}/service_control.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/service_control.sh" >&2
        fi
        pause
        ;;
      7)
        if [ -x "${SCRIPTS_DIR}/cron_restart.sh" ]; then
          run_action "${SCRIPTS_DIR}/cron_restart.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/cron_restart.sh" >&2
        fi
        pause
        ;;
      8)
        if [ -x "${SCRIPTS_DIR}/show_server_info.sh" ]; then
          run_action "${SCRIPTS_DIR}/show_server_info.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/show_server_info.sh" >&2
        fi
        pause
        ;;
      9)
        if [ -x "${SCRIPTS_DIR}/change_mtu.sh" ]; then
          run_action "${SCRIPTS_DIR}/change_mtu.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/change_mtu.sh" >&2
        fi
        pause
        ;;
      10)
        if [ -x "${SCRIPTS_DIR}/health_check_scheduler.sh" ]; then
          run_action "${SCRIPTS_DIR}/health_check_scheduler.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/health_check_scheduler.sh" >&2
        fi
        pause
        ;;
      11)
        if [ -x "${SCRIPTS_DIR}/show_health_logs.sh" ]; then
          run_action "${SCRIPTS_DIR}/show_health_logs.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/show_health_logs.sh" >&2
        fi
        pause
        ;;
      12)
        if [ -x "${SCRIPTS_DIR}/enable_warp_policy.sh" ]; then
          run_action "${SCRIPTS_DIR}/enable_warp_policy.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/enable_warp_policy.sh" >&2
        fi
        pause
        ;;
      13)
        if [ -x "${SCRIPTS_DIR}/disable_warp_policy.sh" ]; then
          run_action "${SCRIPTS_DIR}/disable_warp_policy.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/disable_warp_policy.sh" >&2
        fi
        pause
        ;;
      14)
        if [ -x "${SCRIPTS_DIR}/warp_status.sh" ]; then
          run_action "${SCRIPTS_DIR}/warp_status.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/warp_status.sh" >&2
        fi
        pause
        ;;
      15)
        if [ -x "${SCRIPTS_DIR}/test_warp_full.sh" ]; then
          run_action "${SCRIPTS_DIR}/test_warp_full.sh"
        elif [ -x "${SCRIPTS_DIR}/test_warp.sh" ]; then
          run_action "${SCRIPTS_DIR}/test_warp.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/test_warp_full.sh" >&2
        fi
        pause
        ;;
      16)
        if [ -x "${SCRIPTS_DIR}/enable_firewall.sh" ]; then
          run_action "${SCRIPTS_DIR}/enable_firewall.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/enable_firewall.sh" >&2
        fi
        pause
        ;;
      17)
        if [ -x "${SCRIPTS_DIR}/disable_firewall.sh" ]; then
          run_action "${SCRIPTS_DIR}/disable_firewall.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/disable_firewall.sh" >&2
        fi
        pause
        ;;
      0)
        return 0
        ;;
      *)
        echo -e "${RED}Invalid option:${NC} ${choice}" >&2
        pause
        ;;
    esac
  done
}

client_menu() {
  while true; do
    clear
    banner
    echo -e "${BLUE}Client Configuration${NC}"
    echo "--------------------"
    echo -e "${GREEN}1)${NC} Create client config"
    echo -e "${GREEN}3)${NC} Install systemd service"
    echo -e "${GREEN}5)${NC} Remove systemd service"
    echo -e "${GREEN}6)${NC} Service control"
    echo -e "${GREEN}7)${NC} Restart scheduler"
    echo -e "${GREEN}8)${NC} Test connection"
    echo -e "${GREEN}9)${NC} Change MTU"
    echo -e "${GREEN}10)${NC} Health check"
    echo -e "${GREEN}11)${NC} Health logs"
    echo -e "${GREEN}12)${NC} Enable firewall (ufw)"
    echo -e "${GREEN}13)${NC} Disable firewall (ufw)"
    echo
    echo
    echo -e "${GREEN}0)${NC} Back to main menu"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${SCRIPTS_DIR}/create_client_config.sh" ]; then
          run_action "${SCRIPTS_DIR}/create_client_config.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/create_client_config.sh" >&2
        fi
        pause
        ;;
      3)
        if [ -x "${SCRIPTS_DIR}/install_systemd_service.sh" ]; then
          run_action "${SCRIPTS_DIR}/install_systemd_service.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/install_systemd_service.sh" >&2
        fi
        pause
        ;;
      5)
        if [ -x "${SCRIPTS_DIR}/remove_systemd_service.sh" ]; then
          run_action "${SCRIPTS_DIR}/remove_systemd_service.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/remove_systemd_service.sh" >&2
        fi
        pause
        ;;
      6)
        if [ -x "${SCRIPTS_DIR}/service_control.sh" ]; then
          run_action "${SCRIPTS_DIR}/service_control.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/service_control.sh" >&2
        fi
        pause
        ;;
      7)
        if [ -x "${SCRIPTS_DIR}/cron_restart.sh" ]; then
          run_action "${SCRIPTS_DIR}/cron_restart.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/cron_restart.sh" >&2
        fi
        pause
        ;;
      8)
        if [ -x "${SCRIPTS_DIR}/test_client_connection.sh" ]; then
          run_action "${SCRIPTS_DIR}/test_client_connection.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/test_client_connection.sh" >&2
        fi
        pause
        ;;
      9)
        if [ -x "${SCRIPTS_DIR}/change_mtu.sh" ]; then
          run_action "${SCRIPTS_DIR}/change_mtu.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/change_mtu.sh" >&2
        fi
        pause
        ;;
      10)
        if [ -x "${SCRIPTS_DIR}/health_check_scheduler.sh" ]; then
          run_action "${SCRIPTS_DIR}/health_check_scheduler.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/health_check_scheduler.sh" >&2
        fi
        pause
        ;;
      11)
        if [ -x "${SCRIPTS_DIR}/show_health_logs.sh" ]; then
          run_action "${SCRIPTS_DIR}/show_health_logs.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/show_health_logs.sh" >&2
        fi
        pause
        ;;
      12)
        if [ -x "${SCRIPTS_DIR}/enable_firewall.sh" ]; then
          run_action "${SCRIPTS_DIR}/enable_firewall.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/enable_firewall.sh" >&2
        fi
        pause
        ;;
      13)
        if [ -x "${SCRIPTS_DIR}/disable_firewall.sh" ]; then
          run_action "${SCRIPTS_DIR}/disable_firewall.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/disable_firewall.sh" >&2
        fi
        pause
        ;;
      0)
        return 0
        ;;
      *)
        echo -e "${RED}Invalid option:${NC} ${choice}" >&2
        pause
        ;;
    esac
  done
}

  while true; do
    clear
    banner
    if [ ! -x "${PAQET_DIR}/paqet" ] && ! tarball_present; then
      if ! github_reachable; then
        ARCH_DETECTED="$(detect_arch)"
        echo -e "${YELLOW}Notice:${NC} GitHub is not reachable from this server."
        echo "Download the latest release tarball manually and place it in ${PAQET_DIR}."
        if [ "${ARCH_DETECTED}" != "unknown" ]; then
          echo "Look for a file named: paqet-linux-${ARCH_DETECTED}-<version>.tar.gz"
        else
          echo "Look for a file named: paqet-linux-<arch>-<version>.tar.gz"
        fi
        echo "Releases: https://github.com/hanselime/paqet/releases/latest"
        echo
      fi
    fi
    echo -e "${GREEN}1)${NC} Install Paqet"
    echo -e "${GREEN}2)${NC} Update Paqet"
    echo -e "${GREEN}3)${NC} Server configuration"
    echo -e "${GREEN}4)${NC} Client configuration"
    echo -e "${GREEN}7)${NC} Uninstall Paqet"
    echo
    echo
    echo -e "${GREEN}0)${NC} Exit"
  echo
  read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${INSTALL_SCRIPT}" ]; then
          run_action "${INSTALL_SCRIPT}"
        else
          echo -e "${RED}Install script not found or not executable:${NC} ${INSTALL_SCRIPT}" >&2
        fi
        pause
        ;;
      2)
        if [ -x "${SCRIPTS_DIR}/update_paqet.sh" ]; then
          run_action "${SCRIPTS_DIR}/update_paqet.sh"
        else
          echo -e "${RED}Update script not found or not executable:${NC} ${SCRIPTS_DIR}/update_paqet.sh" >&2
        fi
        pause
        ;;
      3)
        server_menu
        ;;
      4)
        client_menu
        ;;
      7)
        if [ -x "${SCRIPTS_DIR}/uninstall_paqet.sh" ]; then
          run_action "${SCRIPTS_DIR}/uninstall_paqet.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/uninstall_paqet.sh" >&2
        fi
        pause
        ;;
      0)
        echo -e "${GREEN}Goodbye.${NC}"
        exit 0
        ;;
      *)
        echo -e "${RED}Invalid option:${NC} ${choice}" >&2
        pause
        ;;
    esac
  done
