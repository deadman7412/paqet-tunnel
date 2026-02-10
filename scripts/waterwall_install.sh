#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="radkesvat"
REPO_NAME="WaterWall"
RELEASES_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
WATERWALL_DIR="${WATERWALL_DIR:-$HOME/waterwall}"
DOWNLOAD_DIR="${WATERWALL_DIR}/downloads"

mkdir -p "${WATERWALL_DIR}" "${DOWNLOAD_DIR}"

ensure_runtime_dependencies() {
  local pkgs_apt=() pkgs_dnf=() pkgs_yum=()
  pkgs_apt=(libatomic1 libstdc++6)
  pkgs_dnf=(libatomic libstdc++)
  pkgs_yum=(libatomic libstdc++)

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs_apt[@]}" >/dev/null 2>&1 || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "${pkgs_dnf[@]}" >/dev/null 2>&1 || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "${pkgs_yum[@]}" >/dev/null 2>&1 || true
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "unknown" ;;
  esac
}

cpu_has_flag() {
  local flag="$1"
  if command -v lscpu >/dev/null 2>&1; then
    lscpu 2>/dev/null | grep -i "^Flags:" | grep -qw "${flag}" && return 0
  fi
  if [ -r /proc/cpuinfo ]; then
    grep -m1 -i "^flags" /proc/cpuinfo 2>/dev/null | grep -qw "${flag}" && return 0
  fi
  return 1
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
  local urls="" preferred="" line
  urls="$(printf "%s\n" "${json}" | awk -F'"' '/"browser_download_url":/ {print $4}')"
  [ -n "${urls}" ] || return 1

  case "${arch}" in
    amd64)
      # Prioritize broad CPU compatibility to avoid Illegal instruction on older VPS CPUs.
      while IFS= read -r line; do
        case "${line}" in
          *linux-gcc-x64-old-cpu.zip) preferred="${line}"; break ;;
        esac
      done <<< "${urls}"
      if [ -z "${preferred}" ]; then
        while IFS= read -r line; do
          case "${line}" in
            *linux-gcc-x64.zip) preferred="${line}"; break ;;
          esac
        done <<< "${urls}"
      fi
      if [ -z "${preferred}" ]; then
        while IFS= read -r line; do
          case "${line}" in
            *linux-clang-x64.zip) preferred="${line}"; break ;;
          esac
        done <<< "${urls}"
      fi
      if [ -z "${preferred}" ] && cpu_has_flag avx512f; then
        while IFS= read -r line; do
          case "${line}" in
            *linux-clang-avx512f-x64.zip) preferred="${line}"; break ;;
          esac
        done <<< "${urls}"
      fi
      if [ -z "${preferred}" ]; then
        preferred="$(printf "%s\n" "${urls}" | grep -Ei '\.zip$' | grep -Ei 'linux' | grep -Ei '(amd64|x86_64|x64|linux-64)' | head -n1 || true)"
      fi
      ;;
    arm64)
      preferred="$(printf "%s\n" "${urls}" | grep -Ei 'linux-(gcc|clang)-arm64-old-cpu\.zip$' | head -n1 || true)"
      if [ -z "${preferred}" ]; then
        preferred="$(printf "%s\n" "${urls}" | grep -Ei '\.zip$' | grep -Ei 'linux' | grep -Ei '(arm64|aarch64)' | head -n1 || true)"
      fi
      ;;
    *)
      preferred=""
      ;;
  esac

  if [ -z "${preferred}" ]; then
    preferred="$(printf "%s\n" "${urls}" | grep -Ei '\.zip$' | grep -Ei 'linux' | head -n1 || true)"
  fi
  if [ -z "${preferred}" ]; then
    preferred="$(printf "%s\n" "${urls}" | grep -Ei '\.zip$' | head -n1 || true)"
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

pick_local_zip() {
  local zip=""
  zip="$(ls -1t "${WATERWALL_DIR}"/*.zip "${DOWNLOAD_DIR}"/*.zip 2>/dev/null | head -n1 || true)"
  printf "%s\n" "${zip}"
}

extract_zip() {
  local zip_path="$1"
  local target_dir="$2"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  # Expand tmp_dir now so cleanup does not depend on variable scope at trap time.
  trap 'rm -rf '"'"${tmp_dir}"'"'' RETURN

  if command -v unzip >/dev/null 2>&1; then
    unzip -oq "${zip_path}" -d "${tmp_dir}"
  elif command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "${zip_path}" -C "${tmp_dir}"
  else
    echo "Neither unzip nor bsdtar is available to extract zip files." >&2
    exit 1
  fi

  # Keep user-generated files (configs/logs/runtime) and refresh core payload.
  cp -a "${tmp_dir}/." "${target_dir}/"
}

set_binary_link() {
  local bin_target=""
  if [ -f "${WATERWALL_DIR}/Waterwall" ]; then
    bin_target="${WATERWALL_DIR}/Waterwall"
  elif [ -f "${WATERWALL_DIR}/waterwall" ] && [ ! -L "${WATERWALL_DIR}/waterwall" ]; then
    bin_target="${WATERWALL_DIR}/waterwall"
  elif [ -f "${WATERWALL_DIR}/bin/Waterwall" ]; then
    bin_target="${WATERWALL_DIR}/bin/Waterwall"
  elif [ -f "${WATERWALL_DIR}/bin/waterwall" ]; then
    bin_target="${WATERWALL_DIR}/bin/waterwall"
  else
    bin_target="$(find "${WATERWALL_DIR}" -maxdepth 3 -type f \( -iname 'waterwall' -o -iname 'Waterwall' \) | head -n1 || true)"
  fi

  if [ -z "${bin_target}" ]; then
    echo "Waterwall binary was not found after extraction." >&2
    echo "Please inspect files under: ${WATERWALL_DIR}/bin" >&2
    exit 1
  fi

  chmod +x "${bin_target}" || true
  ensure_runtime_dependencies
  ln -sf "${bin_target}" "${WATERWALL_DIR}/waterwall"
}

main() {
  local arch json tag asset_url local_zip final_zip
  arch="$(detect_arch)"

  echo "Install dir: ${WATERWALL_DIR}"
  echo "Release source: ${RELEASES_URL}"

  json="$(fetch_latest_release_json)"
  tag="$(printf "%s\n" "${json}" | awk -F'"' '/"tag_name":/ {print $4; exit}' || true)"
  asset_url="$(pick_asset_url "${json}" "${arch}" || true)"

  if [ -n "${tag}" ] && [ -n "${asset_url}" ]; then
    final_zip="${DOWNLOAD_DIR}/$(basename "${asset_url}")"
    echo "Detected latest release: ${tag}"
    echo "Selected asset: $(basename "${asset_url}")"
    if [ ! -s "${final_zip}" ]; then
      echo "Downloading asset from GitHub..."
      if ! download_file "${asset_url}" "${final_zip}"; then
        rm -f "${final_zip}" || true
        echo "Download failed. Trying local zip fallback..." >&2
        final_zip=""
      fi
    else
      echo "Using cached downloaded asset: ${final_zip}"
    fi
  else
    echo "Could not detect latest release from GitHub API."
    final_zip=""
  fi

  if [ -z "${final_zip:-}" ] || [ ! -s "${final_zip:-/nonexistent}" ]; then
    local_zip="$(pick_local_zip)"
    if [ -n "${local_zip}" ] && [ -s "${local_zip}" ]; then
      final_zip="${local_zip}"
      echo "Using local zip fallback: ${final_zip}"
    else
      echo "No downloadable asset or local zip file found." >&2
      echo "Upload a Waterwall zip into one of these folders, then rerun:" >&2
      echo "  ${WATERWALL_DIR}" >&2
      echo "  ${DOWNLOAD_DIR}" >&2
      echo "Releases: ${RELEASES_URL}" >&2
      exit 1
    fi
  fi

  extract_zip "${final_zip}" "${WATERWALL_DIR}"
  set_binary_link
  mkdir -p "${WATERWALL_DIR}/configs" "${WATERWALL_DIR}/logs" "${WATERWALL_DIR}/runtime"

  echo
  echo "Waterwall installed successfully."
  echo "Binary link: ${WATERWALL_DIR}/waterwall"
  echo "Configs dir: ${WATERWALL_DIR}/configs"
  echo "Logs dir: ${WATERWALL_DIR}/logs"
}

main "$@"
