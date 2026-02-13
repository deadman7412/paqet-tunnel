#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="Qteam-official"
REPO_NAME="ICMPTunnel"
RELEASES_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
ICMPTUNNEL_DIR="${ICMPTUNNEL_DIR:-$HOME/icmptunnel}"
DOWNLOAD_DIR="${ICMPTUNNEL_DIR}/downloads"

mkdir -p "${ICMPTUNNEL_DIR}" "${DOWNLOAD_DIR}"

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|arm) echo "arm" ;;
    i686|i386) echo "386" ;;
    *) echo "unknown" ;;
  esac
}

fetch_latest_release_json() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 5 --max-time 15 "${API_URL}" 2>/dev/null || true
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout=15 "${API_URL}" 2>/dev/null || true
  else
    echo ""
  fi
}

pick_asset_url() {
  local json="$1"
  local arch="$2"
  local urls="" preferred=""
  urls="$(printf "%s\n" "${json}" | awk -F'"' '/"browser_download_url":/ {print $4}')"
  [ -n "${urls}" ] || return 1

  # ICMPTunnel naming: ICMPTunnel-linux-{amd64,arm64,arm,386}
  preferred="$(printf "%s\n" "${urls}" | grep -E "ICMPTunnel-linux-${arch}$" | head -n1 || true)"

  if [ -z "${preferred}" ]; then
    preferred="$(printf "%s\n" "${urls}" | grep -E "linux" | head -n1 || true)"
  fi

  [ -n "${preferred}" ] || return 1
  printf "%s\n" "${preferred}"
}

download_file() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 5 --max-time 60 "${url}" -o "${out}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${out}" --timeout=20 "${url}"
  else
    return 1
  fi
}

pick_local_binary() {
  local arch="$1"
  local binary=""

  # Check for exact arch match first
  for dir in "${ICMPTUNNEL_DIR}" "${DOWNLOAD_DIR}"; do
    if [ -f "${dir}/ICMPTunnel-linux-${arch}" ]; then
      binary="${dir}/ICMPTunnel-linux-${arch}"
      break
    fi
  done

  # Fallback to any linux binary
  if [ -z "${binary}" ]; then
    binary="$(find "${ICMPTUNNEL_DIR}" "${DOWNLOAD_DIR}" -maxdepth 1 -type f -name "ICMPTunnel-linux-*" 2>/dev/null | head -n1 || true)"
  fi

  printf "%s\n" "${binary}"
}

main() {
  local arch json tag asset_url local_binary final_binary
  arch="$(detect_arch)"

  if [ "${arch}" = "unknown" ]; then
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
  fi

  echo "Install dir: ${ICMPTUNNEL_DIR}"
  echo "Architecture: ${arch}"
  echo "Release source: ${RELEASES_URL}"

  json="$(fetch_latest_release_json)"
  tag="$(printf "%s\n" "${json}" | awk -F'"' '/"tag_name":/ {print $4; exit}' || true)"
  asset_url="$(pick_asset_url "${json}" "${arch}" || true)"

  if [ -n "${tag}" ] && [ -n "${asset_url}" ]; then
    final_binary="${DOWNLOAD_DIR}/$(basename "${asset_url}")"
    echo "Detected latest release: ${tag}"
    echo "Selected asset: $(basename "${asset_url}")"

    if [ ! -s "${final_binary}" ]; then
      echo "Downloading from GitHub..."
      if ! download_file "${asset_url}" "${final_binary}"; then
        rm -f "${final_binary}" || true
        echo "Download failed. Trying local binary fallback..." >&2
        final_binary=""
      fi
    else
      echo "Using cached downloaded binary: ${final_binary}"
    fi
  else
    echo "Could not detect latest release from GitHub API."
    final_binary=""
  fi

  if [ -z "${final_binary:-}" ] || [ ! -s "${final_binary:-/nonexistent}" ]; then
    local_binary="$(pick_local_binary "${arch}")"
    if [ -n "${local_binary}" ] && [ -s "${local_binary}" ]; then
      final_binary="${local_binary}"
      echo "Using local binary: ${final_binary}"
    else
      echo "No downloadable asset or local binary found." >&2
      echo "Download manually and place in one of these folders, then rerun:" >&2
      echo "  ${ICMPTUNNEL_DIR}" >&2
      echo "  ${DOWNLOAD_DIR}" >&2
      echo "Expected filename: ICMPTunnel-linux-${arch}" >&2
      echo "Releases: ${RELEASES_URL}" >&2
      exit 1
    fi
  fi

  # Install binary
  mkdir -p "${ICMPTUNNEL_DIR}/server" "${ICMPTUNNEL_DIR}/client" "${ICMPTUNNEL_DIR}/logs"
  cp -f "${final_binary}" "${ICMPTUNNEL_DIR}/icmptunnel"
  chmod +x "${ICMPTUNNEL_DIR}/icmptunnel"

  echo
  echo "ICMP Tunnel installed successfully."
  echo "Binary: ${ICMPTUNNEL_DIR}/icmptunnel"
  echo "Server dir: ${ICMPTUNNEL_DIR}/server"
  echo "Client dir: ${ICMPTUNNEL_DIR}/client"
  echo "Logs dir: ${ICMPTUNNEL_DIR}/logs"
  echo
  echo "Next steps:"
  echo "  - Server setup: Run 'ICMP Tunnel -> Server menu -> Server setup'"
  echo "  - Client setup: Run 'ICMP Tunnel -> Client menu -> Client setup'"
}

main "$@"
