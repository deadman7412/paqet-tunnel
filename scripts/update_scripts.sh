#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
CLIENT_CONFIG="${PAQET_DIR}/client.yaml"
INSTALL_PROXYCHAINS="${SCRIPT_DIR}/install_proxychains4.sh"

github_reachable() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --connect-timeout 3 --max-time 5 https://github.com/deadman7412/paqet-tunnel >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=5 --spider https://github.com/deadman7412/paqet-tunnel >/dev/null 2>&1
  else
    return 1
  fi
}

get_socks_listen() {
  local socks=""
  if [ -f "${CLIENT_CONFIG}" ]; then
    socks="$(awk '
      $1 == "socks5:" { insocks=1; next }
      insocks && $1 == "-" && $2 == "listen:" { gsub(/"/, "", $3); print $3; exit }
      insocks && $1 == "listen:" { gsub(/"/, "", $2); print $2; exit }
    ' "${CLIENT_CONFIG}")"
  fi
  if [ -z "${socks}" ]; then
    socks="127.0.0.1:1080"
  fi
  echo "${socks}"
}

require_paqet_socks() {
  if [ ! -f "${CLIENT_CONFIG}" ]; then
    echo "Client config not found: ${CLIENT_CONFIG}" >&2
    echo "Configure and start the paqet client first, then re-run this updater." >&2
    return 1
  fi
  if command -v curl >/dev/null 2>&1; then
    local socks
    socks="$(get_socks_listen)"
    if ! curl -fsSL --connect-timeout 5 --max-time 10 https://github.com --proxy "socks5h://${socks}" >/dev/null 2>&1; then
      echo "SOCKS proxy test failed: ${socks}" >&2
      echo "Ensure paqet client is running and 'Test connection' succeeds." >&2
      return 1
    fi
  else
    echo "Warning: curl not found; cannot verify SOCKS proxy. Ensure paqet client is running." >&2
  fi
}

if ! command -v git >/dev/null 2>&1; then
  echo "git is required to update scripts." >&2
  exit 1
fi

if ! git -C "${REPO_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This folder is not a git repository: ${REPO_DIR}" >&2
  echo "If you downloaded a ZIP, re-clone from GitHub to enable updates." >&2
  exit 1
fi

CURRENT_BRANCH="$(git -C "${REPO_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
echo "Updating scripts in ${REPO_DIR}"
echo "Current branch: ${CURRENT_BRANCH:-unknown}"

GIT_CMD=(git -C "${REPO_DIR}")
if github_reachable; then
  echo "Connecting to GitHub..."
else
  echo "GitHub is not reachable from this server." >&2
  if command -v proxychains4 >/dev/null 2>&1 || command -v proxychains >/dev/null 2>&1; then
    read -r -p "Use proxychains to update scripts via paqet SOCKS? [y/N]: " use_proxy
  else
    read -r -p "Install proxychains4 and use it to update scripts via paqet SOCKS? [y/N]: " use_proxy
  fi

  case "${use_proxy}" in
    y|Y)
      if ! command -v proxychains4 >/dev/null 2>&1 && ! command -v proxychains >/dev/null 2>&1; then
        if [ -x "${INSTALL_PROXYCHAINS}" ]; then
          "${INSTALL_PROXYCHAINS}"
        else
          echo "Proxychains installer not found: ${INSTALL_PROXYCHAINS}" >&2
          exit 1
        fi
      fi

      if ! require_paqet_socks; then
        exit 1
      fi

      if command -v proxychains4 >/dev/null 2>&1; then
        GIT_CMD=(proxychains4 git -C "${REPO_DIR}")
      else
        GIT_CMD=(proxychains git -C "${REPO_DIR}")
      fi
      ;;
    *)
      echo "Notice: GitHub not reachable. Update scripts manually or re-run with proxychains." >&2
      exit 1
      ;;
  esac
fi

"${GIT_CMD[@]}" fetch --prune
git -C "${REPO_DIR}" status -sb

# If working tree is dirty, auto-stash to allow fast-forward pull.
STASHED=0
if ! git -C "${REPO_DIR}" diff --quiet || ! git -C "${REPO_DIR}" diff --cached --quiet; then
  echo "Local changes detected. Stashing before update..."
  git -C "${REPO_DIR}" stash push -u -m "auto-stash before update $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >/dev/null 2>&1 || true
  if git -C "${REPO_DIR}" stash list | head -n1 | grep -q "auto-stash before update"; then
    STASHED=1
  fi
fi

"${GIT_CMD[@]}" pull --ff-only

if [ "${STASHED}" -eq 1 ]; then
  echo "Re-applying local changes..."
  if ! git -C "${REPO_DIR}" stash pop >/dev/null 2>&1; then
    echo "Warning: stash pop had conflicts. Resolve them manually." >&2
    exit 1
  fi
fi

echo "Update complete."
