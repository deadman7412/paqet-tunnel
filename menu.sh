#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install_paqet.sh"
PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

banner() {
  echo -e "${CYAN}=================================${NC}"
  echo -e "${CYAN}        Paqet Tunnel Menu        ${NC}"
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
  chmod +x "${SCRIPT_DIR}"/*.sh 2>/dev/null || true
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
    echo -e "${GREEN}0)${NC} Back to main menu"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${SCRIPT_DIR}/create_server_config.sh" ]; then
          run_action "${SCRIPT_DIR}/create_server_config.sh"
          echo
          echo -e "${BLUE}Next:${NC} Copy ~/paqet/server_info.txt to the client VPS (same path) before creating client config."
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/create_server_config.sh" >&2
        fi
        pause
        ;;
      2)
        if [ -x "${SCRIPT_DIR}/add_server_iptables.sh" ]; then
          run_action "${SCRIPT_DIR}/add_server_iptables.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/add_server_iptables.sh" >&2
        fi
        pause
        ;;
      3)
        if [ -x "${SCRIPT_DIR}/install_systemd_service.sh" ]; then
          run_action "${SCRIPT_DIR}/install_systemd_service.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/install_systemd_service.sh" >&2
        fi
        pause
        ;;
      4)
        if [ -x "${SCRIPT_DIR}/remove_server_iptables.sh" ]; then
          run_action "${SCRIPT_DIR}/remove_server_iptables.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/remove_server_iptables.sh" >&2
        fi
        pause
        ;;
      5)
        if [ -x "${SCRIPT_DIR}/remove_systemd_service.sh" ]; then
          run_action "${SCRIPT_DIR}/remove_systemd_service.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/remove_systemd_service.sh" >&2
        fi
        pause
        ;;
      6)
        if [ -x "${SCRIPT_DIR}/service_control.sh" ]; then
          run_action "${SCRIPT_DIR}/service_control.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/service_control.sh" >&2
        fi
        pause
        ;;
      7)
        if [ -x "${SCRIPT_DIR}/cron_restart.sh" ]; then
          run_action "${SCRIPT_DIR}/cron_restart.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/cron_restart.sh" >&2
        fi
        pause
        ;;
      8)
        if [ -x "${SCRIPT_DIR}/show_server_info.sh" ]; then
          run_action "${SCRIPT_DIR}/show_server_info.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/show_server_info.sh" >&2
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
    echo -e "${GREEN}0)${NC} Back to main menu"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${SCRIPT_DIR}/create_client_config.sh" ]; then
          run_action "${SCRIPT_DIR}/create_client_config.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/create_client_config.sh" >&2
        fi
        pause
        ;;
      3)
        if [ -x "${SCRIPT_DIR}/install_systemd_service.sh" ]; then
          run_action "${SCRIPT_DIR}/install_systemd_service.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/install_systemd_service.sh" >&2
        fi
        pause
        ;;
      5)
        if [ -x "${SCRIPT_DIR}/remove_systemd_service.sh" ]; then
          run_action "${SCRIPT_DIR}/remove_systemd_service.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/remove_systemd_service.sh" >&2
        fi
        pause
        ;;
      6)
        if [ -x "${SCRIPT_DIR}/service_control.sh" ]; then
          run_action "${SCRIPT_DIR}/service_control.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/service_control.sh" >&2
        fi
        pause
        ;;
      7)
        if [ -x "${SCRIPT_DIR}/cron_restart.sh" ]; then
          run_action "${SCRIPT_DIR}/cron_restart.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/cron_restart.sh" >&2
        fi
        pause
        ;;
      8)
        if [ -x "${SCRIPT_DIR}/test_client_connection.sh" ]; then
          run_action "${SCRIPT_DIR}/test_client_connection.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/test_client_connection.sh" >&2
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
    echo -e "${GREEN}2)${NC} Server configuration"
    echo -e "${GREEN}3)${NC} Client configuration"
    echo -e "${GREEN}6)${NC} Uninstall Paqet"
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
        server_menu
        ;;
      3)
        client_menu
        ;;
      6)
        if [ -x "${SCRIPT_DIR}/uninstall_paqet.sh" ]; then
          run_action "${SCRIPT_DIR}/uninstall_paqet.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPT_DIR}/uninstall_paqet.sh" >&2
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
