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
  elif [ -f "${SCRIPT_DIR}/VERSION" ]; then
    ver="$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null | tr -d ' \n\r')"
  fi
  echo -e "${CYAN}===========================================${NC}"
  echo -e "${CYAN}Paqet Tunnel Menu${NC}"
  if [ -n "${ver}" ]; then
    echo -e "${CYAN}Version: ${ver}${NC}"
  fi
  echo -e "${CYAN}Created by deadman7412${NC}"
  echo -e "${CYAN}===========================================${NC}"
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

policy_core_menu() {
  while true; do
    clear
    banner
    echo -e "${BLUE}WARP/DNS Core${NC}"
    echo "-------------"
    echo -e "${GREEN}1)${NC} Install WARP core (wgcf)"
    echo -e "${GREEN}2)${NC} Uninstall WARP core (wgcf)"
    echo -e "${GREEN}3)${NC} Install DNS policy core"
    echo -e "${GREEN}4)${NC} Uninstall DNS policy core"
    echo -e "${GREEN}5)${NC} Reconcile server/SSH policy bindings"
    echo
    echo
    echo -e "${GREEN}0)${NC} Back to main menu"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${SCRIPTS_DIR}/warp_core_install.sh" ]; then
          run_action "${SCRIPTS_DIR}/warp_core_install.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/warp_core_install.sh" >&2
        fi
        pause
        ;;
      2)
        if [ -x "${SCRIPTS_DIR}/warp_core_uninstall.sh" ]; then
          run_action "${SCRIPTS_DIR}/warp_core_uninstall.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/warp_core_uninstall.sh" >&2
        fi
        pause
        ;;
      3)
        if [ -x "${SCRIPTS_DIR}/dns_policy_core_install.sh" ]; then
          read -r -p "DNS category [ads/all/proxy] (default ads): " dns_category
          dns_category="${dns_category:-ads}"
          run_action "${SCRIPTS_DIR}/dns_policy_core_install.sh" "${dns_category}"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/dns_policy_core_install.sh" >&2
        fi
        pause
        ;;
      4)
        if [ -x "${SCRIPTS_DIR}/dns_policy_core_uninstall.sh" ]; then
          run_action "${SCRIPTS_DIR}/dns_policy_core_uninstall.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/dns_policy_core_uninstall.sh" >&2
        fi
        pause
        ;;
      5)
        if [ -x "${SCRIPTS_DIR}/reconcile_policy_bindings.sh" ]; then
          run_action "${SCRIPTS_DIR}/reconcile_policy_bindings.sh" all
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/reconcile_policy_bindings.sh" >&2
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
    echo -e "${GREEN}12)${NC} Enable WARP for paqet-server (bind)"
    echo -e "${GREEN}13)${NC} Disable WARP for paqet-server (unbind)"
    echo -e "${GREEN}14)${NC} WARP status"
    echo -e "${GREEN}15)${NC} Test WARP"
    echo -e "${GREEN}16)${NC} Repair networking stack"
    echo -e "${GREEN}17)${NC} Enable DNS policy for paqet-server (bind)"
    echo -e "${GREEN}18)${NC} Disable DNS policy for paqet-server (unbind)"
    echo -e "${GREEN}19)${NC} Update DNS policy list now"
    echo -e "${GREEN}20)${NC} DNS policy status"
    echo -e "${GREEN}21)${NC} Show WARP config for 3x-ui"
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
        if [ -x "${SCRIPTS_DIR}/repair_networking_stack.sh" ]; then
          run_action "${SCRIPTS_DIR}/repair_networking_stack.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/repair_networking_stack.sh" >&2
        fi
        pause
        ;;
      17)
        if [ -x "${SCRIPTS_DIR}/enable_dns_policy.sh" ]; then
          run_action "${SCRIPTS_DIR}/enable_dns_policy.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/enable_dns_policy.sh" >&2
        fi
        pause
        ;;
      18)
        if [ -x "${SCRIPTS_DIR}/disable_dns_policy.sh" ]; then
          run_action "${SCRIPTS_DIR}/disable_dns_policy.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/disable_dns_policy.sh" >&2
        fi
        pause
        ;;
      19)
        if [ -x "${SCRIPTS_DIR}/update_dns_policy_list.sh" ]; then
          read -r -p "DNS category [ads/all/proxy] (leave empty to use current): " dns_category
          if [ -n "${dns_category}" ]; then
            run_action "${SCRIPTS_DIR}/update_dns_policy_list.sh" "${dns_category}"
          else
            run_action "${SCRIPTS_DIR}/update_dns_policy_list.sh"
          fi
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/update_dns_policy_list.sh" >&2
        fi
        pause
        ;;
      20)
        if [ -x "${SCRIPTS_DIR}/dns_policy_status.sh" ]; then
          run_action "${SCRIPTS_DIR}/dns_policy_status.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/dns_policy_status.sh" >&2
        fi
        pause
        ;;
      21)
        if [ -x "${SCRIPTS_DIR}/show_warp_3xui_config.sh" ]; then
          run_action "${SCRIPTS_DIR}/show_warp_3xui_config.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/show_warp_3xui_config.sh" >&2
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
    echo -e "${GREEN}2)${NC} Install proxychains4"
    echo -e "${GREEN}3)${NC} Install systemd service"
    echo -e "${GREEN}5)${NC} Remove systemd service"
    echo -e "${GREEN}6)${NC} Service control"
    echo -e "${GREEN}7)${NC} Restart scheduler"
    echo -e "${GREEN}8)${NC} Test connection"
    echo -e "${GREEN}9)${NC} Change MTU"
    echo -e "${GREEN}10)${NC} Health check"
    echo -e "${GREEN}11)${NC} Health logs"
    echo -e "${GREEN}12)${NC} Repair networking stack"
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
      2)
        if [ -x "${SCRIPTS_DIR}/install_proxychains4.sh" ]; then
          run_action "${SCRIPTS_DIR}/install_proxychains4.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/install_proxychains4.sh" >&2
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
        if [ -x "${SCRIPTS_DIR}/repair_networking_stack.sh" ]; then
          run_action "${SCRIPTS_DIR}/repair_networking_stack.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/repair_networking_stack.sh" >&2
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

ssh_proxy_menu() {
  while true; do
    clear
    banner
    echo -e "${BLUE}SSH Proxy${NC}"
    echo "---------"
    echo -e "${GREEN}1)${NC} Manage SSH proxy port"
    echo -e "${GREEN}2)${NC} Create SSH proxy user"
    echo -e "${GREEN}3)${NC} Remove SSH proxy user"
    echo -e "${GREEN}4)${NC} List SSH proxy users"
    echo -e "${GREEN}5)${NC} Show simple SSH credentials"
    echo -e "${GREEN}6)${NC} Enable WARP for SSH proxy users"
    echo -e "${GREEN}7)${NC} Disable WARP for SSH proxy users"
    echo -e "${GREEN}8)${NC} Enable DNS routing for SSH proxy users"
    echo -e "${GREEN}9)${NC} Disable DNS routing for SSH proxy users"
    echo
    echo
    echo -e "${GREEN}0)${NC} Back to main menu"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${SCRIPTS_DIR}/ssh_proxy_manage_port.sh" ]; then
          run_action "${SCRIPTS_DIR}/ssh_proxy_manage_port.sh"
        else
          echo -e "${YELLOW}Not implemented yet:${NC} ${SCRIPTS_DIR}/ssh_proxy_manage_port.sh"
        fi
        pause
        ;;
      2)
        if [ -x "${SCRIPTS_DIR}/ssh_proxy_create_user.sh" ]; then
          run_action "${SCRIPTS_DIR}/ssh_proxy_create_user.sh"
        else
          echo -e "${YELLOW}Not implemented yet:${NC} ${SCRIPTS_DIR}/ssh_proxy_create_user.sh"
        fi
        pause
        ;;
      3)
        if [ -x "${SCRIPTS_DIR}/ssh_proxy_remove_user.sh" ]; then
          run_action "${SCRIPTS_DIR}/ssh_proxy_remove_user.sh"
        else
          echo -e "${YELLOW}Not implemented yet:${NC} ${SCRIPTS_DIR}/ssh_proxy_remove_user.sh"
        fi
        pause
        ;;
      4)
        if [ -x "${SCRIPTS_DIR}/ssh_proxy_list_users.sh" ]; then
          run_action "${SCRIPTS_DIR}/ssh_proxy_list_users.sh"
        else
          echo -e "${YELLOW}Not implemented yet:${NC} ${SCRIPTS_DIR}/ssh_proxy_list_users.sh"
        fi
        pause
        ;;
      5)
        if [ -x "${SCRIPTS_DIR}/ssh_proxy_create_simple_credentials.sh" ]; then
          run_action "${SCRIPTS_DIR}/ssh_proxy_create_simple_credentials.sh"
        else
          echo -e "${YELLOW}Not implemented yet:${NC} ${SCRIPTS_DIR}/ssh_proxy_create_simple_credentials.sh"
        fi
        pause
        ;;
      6)
        if [ -x "${SCRIPTS_DIR}/ssh_proxy_enable_warp.sh" ]; then
          run_action "${SCRIPTS_DIR}/ssh_proxy_enable_warp.sh"
        else
          echo -e "${YELLOW}Not implemented yet:${NC} ${SCRIPTS_DIR}/ssh_proxy_enable_warp.sh"
        fi
        pause
        ;;
      7)
        if [ -x "${SCRIPTS_DIR}/ssh_proxy_disable_warp.sh" ]; then
          run_action "${SCRIPTS_DIR}/ssh_proxy_disable_warp.sh"
        else
          echo -e "${YELLOW}Not implemented yet:${NC} ${SCRIPTS_DIR}/ssh_proxy_disable_warp.sh"
        fi
        pause
        ;;
      8)
        if [ -x "${SCRIPTS_DIR}/ssh_proxy_enable_dns_routing.sh" ]; then
          run_action "${SCRIPTS_DIR}/ssh_proxy_enable_dns_routing.sh"
        else
          echo -e "${YELLOW}Not implemented yet:${NC} ${SCRIPTS_DIR}/ssh_proxy_enable_dns_routing.sh"
        fi
        pause
        ;;
      9)
        if [ -x "${SCRIPTS_DIR}/ssh_proxy_disable_dns_routing.sh" ]; then
          run_action "${SCRIPTS_DIR}/ssh_proxy_disable_dns_routing.sh"
        else
          echo -e "${YELLOW}Not implemented yet:${NC} ${SCRIPTS_DIR}/ssh_proxy_disable_dns_routing.sh"
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

firewall_menu() {
  firewall_select_role() {
    local label="$1"
    local role=""
    read -r -p "${label} role [server/client]: " role
    role="$(echo "${role}" | tr '[:upper:]' '[:lower:]')"
    case "${role}" in
      server|client) echo "${role}" ;;
      *)
        echo "Invalid role. Use: server or client." >&2
        return 1
        ;;
    esac
  }

  firewall_paqet_menu() {
    while true; do
      clear
      banner
      echo -e "${BLUE}Firewall (UFW) - Paqet${NC}"
      echo "-----------------------"
      echo -e "${GREEN}1)${NC} Enable firewall"
      echo -e "${GREEN}2)${NC} Remove Paqet firewall rules"
      echo
      echo
      echo -e "${GREEN}0)${NC} Back"
      echo
      read -r -p "Select an option: " sub_choice

      case "${sub_choice}" in
        1)
          if [ -x "${SCRIPTS_DIR}/enable_firewall.sh" ]; then
            if role="$(firewall_select_role "Paqet")"; then
              run_action "${SCRIPTS_DIR}/enable_firewall.sh" "${role}"
            fi
          else
            echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/enable_firewall.sh" >&2
          fi
          pause
          ;;
        2)
          if [ -x "${SCRIPTS_DIR}/firewall_rules_disable.sh" ]; then
            run_action "${SCRIPTS_DIR}/firewall_rules_disable.sh" paqet 0
          else
            echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/firewall_rules_disable.sh" >&2
          fi
          pause
          ;;
        0)
          return 0
          ;;
        *)
          echo -e "${RED}Invalid option:${NC} ${sub_choice}" >&2
          pause
          ;;
      esac
    done
  }

  firewall_waterwall_menu() {
    while true; do
      clear
      banner
      echo -e "${BLUE}Firewall (UFW) - Waterwall${NC}"
      echo "---------------------------"
      echo -e "${GREEN}1)${NC} Enable firewall"
      echo -e "${GREEN}2)${NC} Remove Waterwall firewall rules"
      echo
      echo
      echo -e "${GREEN}0)${NC} Back"
      echo
      read -r -p "Select an option: " sub_choice

      case "${sub_choice}" in
        1)
          if [ -x "${SCRIPTS_DIR}/enable_firewall_waterwall.sh" ]; then
            if role="$(firewall_select_role "Waterwall")"; then
              run_action "${SCRIPTS_DIR}/enable_firewall_waterwall.sh" "${role}"
            fi
          else
            echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/enable_firewall_waterwall.sh" >&2
          fi
          pause
          ;;
        2)
          if [ -x "${SCRIPTS_DIR}/firewall_rules_disable.sh" ]; then
            run_action "${SCRIPTS_DIR}/firewall_rules_disable.sh" waterwall 0
          else
            echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/firewall_rules_disable.sh" >&2
          fi
          pause
          ;;
        0)
          return 0
          ;;
        *)
          echo -e "${RED}Invalid option:${NC} ${sub_choice}" >&2
          pause
          ;;
      esac
    done
  }

  while true; do
    clear
    banner
    echo -e "${BLUE}Firewall (UFW)${NC}"
    echo "--------------"
    echo -e "${GREEN}1)${NC} Paqet firewall"
    echo -e "${GREEN}2)${NC} SSH proxy firewall"
    echo -e "${GREEN}3)${NC} Waterwall firewall"
    echo -e "${GREEN}4)${NC} Disable UFW completely"
    echo -e "${GREEN}5)${NC} UFW status"
    echo
    echo
    echo -e "${GREEN}0)${NC} Back"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        firewall_paqet_menu
        ;;
      2)
        if [ -x "${SCRIPTS_DIR}/ssh_proxy_enable_firewall.sh" ]; then
          run_action "${SCRIPTS_DIR}/ssh_proxy_enable_firewall.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/ssh_proxy_enable_firewall.sh" >&2
        fi
        pause
        ;;
      3)
        firewall_waterwall_menu
        ;;
      4)
        if [ -x "${SCRIPTS_DIR}/firewall_rules_disable.sh" ]; then
          run_action "${SCRIPTS_DIR}/firewall_rules_disable.sh" all 1
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/firewall_rules_disable.sh" >&2
        fi
        pause
        ;;
      5)
        if command -v ufw >/dev/null 2>&1; then
          ufw status verbose || true
          echo
          ufw status numbered || true
        else
          echo "ufw is not installed."
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

waterwall_direct_server_test_menu() {
  while true; do
    clear
    banner
    echo -e "${BLUE}Direct Waterwall: Server Tests${NC}"
    echo "-------------------------------"
    echo -e "${GREEN}1)${NC} Diagnostic report (share with support)"
    echo -e "${GREEN}2)${NC} Start test backend service"
    echo
    echo
    echo -e "${GREEN}0)${NC} Back"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${SCRIPTS_DIR}/waterwall_test_all.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_test_all.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_test_all.sh" >&2
        fi
        pause
        ;;
      2)
        if [ -x "${SCRIPTS_DIR}/waterwall_start_test_backend.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_start_test_backend.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_start_test_backend.sh" >&2
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

waterwall_direct_server_menu() {
  while true; do
    clear
    banner
    echo -e "${BLUE}Direct Waterwall: Server${NC}"
    echo "------------------------"
    echo -e "${GREEN}1)${NC} Server (foreign VPS) setup"
    echo -e "${GREEN}2)${NC} Install systemd service (server)"
    echo -e "${GREEN}3)${NC} Remove systemd service (server)"
    echo -e "${GREEN}4)${NC} Service control (server)"
    echo -e "${GREEN}5)${NC} Show server info"
    echo -e "${GREEN}6)${NC} Tests & Diagnostics"
    echo
    echo
    echo -e "${GREEN}0)${NC} Back"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${SCRIPTS_DIR}/waterwall_direct_server_setup.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_direct_server_setup.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_direct_server_setup.sh" >&2
        fi
        pause
        ;;
      2)
        if [ -x "${SCRIPTS_DIR}/waterwall_direct_install_systemd_service.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_direct_install_systemd_service.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_direct_install_systemd_service.sh" >&2
        fi
        pause
        ;;
      3)
        if [ -x "${SCRIPTS_DIR}/waterwall_direct_remove_systemd_service.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_direct_remove_systemd_service.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_direct_remove_systemd_service.sh" >&2
        fi
        pause
        ;;
      4)
        if [ -x "${SCRIPTS_DIR}/waterwall_direct_service_control.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_direct_service_control.sh" server
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_direct_service_control.sh" >&2
        fi
        pause
        ;;
      5)
        if [ -x "${SCRIPTS_DIR}/waterwall_show_direct_server_info.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_show_direct_server_info.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_show_direct_server_info.sh" >&2
        fi
        pause
        ;;
      6)
        waterwall_direct_server_test_menu
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

waterwall_direct_client_test_menu() {
  while true; do
    clear
    banner
    echo -e "${BLUE}Direct Waterwall: Client Tests${NC}"
    echo "-------------------------------"
    echo -e "${GREEN}1)${NC} Diagnostic report (share with support)"
    echo -e "${GREEN}2)${NC} Quick connectivity + internet egress check"
    echo
    echo
    echo -e "${GREEN}0)${NC} Back"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${SCRIPTS_DIR}/waterwall_test_all.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_test_all.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_test_all.sh" >&2
        fi
        pause
        ;;
      2)
        if [ -x "${SCRIPTS_DIR}/waterwall_test_client_connection.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_test_client_connection.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_test_client_connection.sh" >&2
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

waterwall_direct_client_menu() {
  while true; do
    clear
    banner
    echo -e "${BLUE}Direct Waterwall: Client${NC}"
    echo "------------------------"
    echo -e "${GREEN}1)${NC} Client (local VPS) setup"
    echo -e "${GREEN}2)${NC} Install systemd service (client)"
    echo -e "${GREEN}3)${NC} Remove systemd service (client)"
    echo -e "${GREEN}4)${NC} Service control (client)"
    echo -e "${GREEN}5)${NC} Tests & Diagnostics"
    echo -e "${GREEN}6)${NC} Show ports for configuration"
    echo
    echo
    echo -e "${GREEN}0)${NC} Back"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${SCRIPTS_DIR}/waterwall_direct_client_setup.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_direct_client_setup.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_direct_client_setup.sh" >&2
        fi
        pause
        ;;
      2)
        if [ -x "${SCRIPTS_DIR}/waterwall_direct_install_systemd_service.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_direct_install_systemd_service.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_direct_install_systemd_service.sh" >&2
        fi
        pause
        ;;
      3)
        if [ -x "${SCRIPTS_DIR}/waterwall_direct_remove_systemd_service.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_direct_remove_systemd_service.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_direct_remove_systemd_service.sh" >&2
        fi
        pause
        ;;
      4)
        if [ -x "${SCRIPTS_DIR}/waterwall_direct_service_control.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_direct_service_control.sh" client
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_direct_service_control.sh" >&2
        fi
        pause
        ;;
      5)
        waterwall_direct_client_test_menu
        ;;
      6)
        if [ -x "${SCRIPTS_DIR}/waterwall_show_ports.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_show_ports.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_show_ports.sh" >&2
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

waterwall_direct_menu() {
  while true; do
    clear
    banner
    echo -e "${BLUE}Direct Waterwall Tunnel${NC}"
    echo "-----------------------"
    echo -e "${GREEN}1)${NC} Server menu (foreign VPS)"
    echo -e "${GREEN}2)${NC} Client menu (local VPS)"
    echo
    echo
    echo -e "${GREEN}0)${NC} Back"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        waterwall_direct_server_menu
        ;;
      2)
        waterwall_direct_client_menu
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

waterwall_menu() {
  while true; do
    clear
    banner
    echo -e "${BLUE}Waterwall Tunnel${NC}"
    echo "----------------"
    echo -e "${GREEN}1)${NC} Install Waterwall"
    echo -e "${GREEN}2)${NC} Update Waterwall"
    echo -e "${GREEN}3)${NC} Direct Waterwall tunnel"
    echo -e "${GREEN}4)${NC} Reverse Waterwall tunnel"
    echo -e "${GREEN}5)${NC} Uninstall Waterwall"
    echo
    echo
    echo -e "${GREEN}0)${NC} Back to main menu"
    echo
    read -r -p "Select an option: " choice

    case "${choice}" in
      1)
        if [ -x "${SCRIPTS_DIR}/waterwall_install.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_install.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_install.sh" >&2
        fi
        pause
        ;;
      2)
        if [ -x "${SCRIPTS_DIR}/waterwall_update.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_update.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_update.sh" >&2
        fi
        pause
        ;;
      3)
        waterwall_direct_menu
        ;;
      4)
        if [ -x "${SCRIPTS_DIR}/waterwall_configure_reverse.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_configure_reverse.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_configure_reverse.sh" >&2
        fi
        pause
        ;;
      5)
        if [ -x "${SCRIPTS_DIR}/waterwall_uninstall.sh" ]; then
          run_action "${SCRIPTS_DIR}/waterwall_uninstall.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/waterwall_uninstall.sh" >&2
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

paqet_tunnel_menu() {
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
    echo -e "${GREEN}3)${NC} Update Scripts (git pull)"
    echo -e "${GREEN}4)${NC} Server configuration"
    echo -e "${GREEN}5)${NC} Client configuration"
    echo -e "${GREEN}6)${NC} SSH proxy"
    echo -e "${GREEN}7)${NC} WARP/DNS core"
    echo -e "${GREEN}8)${NC} Uninstall / remove components"
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
        if [ -x "${SCRIPTS_DIR}/update_scripts.sh" ]; then
          run_action "${SCRIPTS_DIR}/update_scripts.sh"
        else
          echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/update_scripts.sh" >&2
        fi
        pause
        ;;
      4)
        server_menu
        ;;
      5)
        client_menu
        ;;
      6)
        ssh_proxy_menu
        ;;
      7)
        policy_core_menu
        ;;
      8)
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
}

while true; do
  clear
  banner
  echo -e "${GREEN}1)${NC} Update Scripts (git pull)"
  echo -e "${GREEN}2)${NC} Paqet Tunnel"
  echo -e "${GREEN}3)${NC} Waterwall Tunnel"
  echo -e "${GREEN}4)${NC} Firewall (UFW)"
  echo
  echo
  echo -e "${GREEN}0)${NC} Exit"
  echo
  read -r -p "Select an option: " choice

  case "${choice}" in
    1)
      if [ -x "${SCRIPTS_DIR}/update_scripts.sh" ]; then
        run_action "${SCRIPTS_DIR}/update_scripts.sh"
      else
        echo -e "${RED}Script not found or not executable:${NC} ${SCRIPTS_DIR}/update_scripts.sh" >&2
      fi
      pause
      ;;
    2)
      paqet_tunnel_menu
      ;;
    3)
      waterwall_menu
      ;;
    4)
      firewall_menu
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
