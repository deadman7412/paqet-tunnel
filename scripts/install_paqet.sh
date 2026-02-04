#!/usr/bin/env bash
set -euo pipefail

VERSION=""
OS="linux"
PAQET_DIR="${PAQET_DIR:-$HOME/paqet}"
BIN_PATH="${PAQET_DIR}/paqet"

# Detect arch
ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
  x86_64|amd64)
    ARCH="amd64"
    ;;
  aarch64|arm64)
    ARCH="arm64"
    ;;
  *)
    echo "Unsupported architecture: ${ARCH_RAW}" >&2
    exit 1
    ;;
esac

local_tarball=""
if [ -d "${PAQET_DIR}" ]; then
  for f in $(ls -1 "${PAQET_DIR}"/paqet-${OS}-${ARCH}-v*.tar.gz 2>/dev/null | sort -V); do
    if [ -s "${f}" ]; then
      local_tarball="${f}"
    fi
  done
fi

if [ -n "${local_tarball}" ]; then
  NAME="$(basename "${local_tarball}")"
  VERSION="$(echo "${NAME}" | sed -n 's/^paqet-'"${OS}"'-'"${ARCH}"'-\(v[^.]*\..*\)\.tar\.gz$/\1/p')"
  URL="https://github.com/hanselime/paqet/releases/download/${VERSION}/${NAME}"
  TARBALL_PATH="${PAQET_DIR}/${NAME}"
  echo "Found local tarball: ${TARBALL_PATH}"

  # Check for newer version on GitHub
  latest=""
  if command -v curl >/dev/null 2>&1; then
    latest="$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.github.com/repos/hanselime/paqet/releases/latest 2>/dev/null | awk -F '\"' '/tag_name/{print $4; exit}' || true)"
  elif command -v wget >/dev/null 2>&1; then
    latest="$(wget -qO- --timeout=10 https://api.github.com/repos/hanselime/paqet/releases/latest 2>/dev/null | awk -F '\"' '/tag_name/{print $4; exit}' || true)"
  fi

  if [ -n "${latest}" ] && [ "${latest}" != "${VERSION}" ]; then
    echo
    echo -e "\033[1;31m====================================\033[0m"
    echo -e "\033[1;31m  NEWER VERSION AVAILABLE\033[0m"
    echo -e "\033[1;31m====================================\033[0m"
    echo -e "\033[1;33mLatest:\033[0m ${latest}"
    echo -e "\033[1;33mLocal:\033[0m  ${VERSION}"
    echo
    read -r -p "Use local version anyway? [y/N]: " USE_LOCAL
    case "${USE_LOCAL}" in
      y|Y)
        echo
        echo "Using local version: ${VERSION}"
        echo
        echo -e "\033[1;31mWARNING:\033[0m Ensure BOTH server and client use the same paqet version."
        echo
        ;;
      *)
        VERSION="${latest}"
        NAME="paqet-${OS}-${ARCH}-${VERSION}.tar.gz"
        URL="https://github.com/hanselime/paqet/releases/download/${VERSION}/${NAME}"
        TARBALL_PATH="${PAQET_DIR}/${NAME}"
        echo
        echo "Using latest version: ${VERSION}"
        echo
        ;;
    esac
  fi
else
  if [ -z "${VERSION}" ]; then
    if command -v curl >/dev/null 2>&1; then
      VERSION="$(curl -fsSL https://api.github.com/repos/hanselime/paqet/releases/latest 2>/dev/null | awk -F '\"' '/tag_name/{print $4; exit}' || true)"
    elif command -v wget >/dev/null 2>&1; then
      VERSION="$(wget -qO- https://api.github.com/repos/hanselime/paqet/releases/latest 2>/dev/null | awk -F '\"' '/tag_name/{print $4; exit}' || true)"
    fi
  fi

  if [ -z "${VERSION}" ]; then
    echo "Failed to detect latest release tag from GitHub API." >&2
    echo "Set VERSION manually (e.g., VERSION=v1.0.0-alpha.12) and re-run." >&2
    exit 1
  fi

  NAME="paqet-${OS}-${ARCH}-${VERSION}.tar.gz"
  URL="https://github.com/hanselime/paqet/releases/download/${VERSION}/${NAME}"
  TARBALL_PATH="${PAQET_DIR}/${NAME}"
fi

if [ -x "${BIN_PATH}" ]; then
  echo "paqet is already installed at ${BIN_PATH}"
  exit 0
fi

# Install prerequisites (libpcap)
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y libpcap-dev
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y libpcap-devel
elif command -v yum >/dev/null 2>&1; then
  yum install -y libpcap-devel
else
  echo "No supported package manager found (apt-get/dnf/yum). Skipping libpcap install." >&2
fi

mkdir -p "${PAQET_DIR}"
cd "${PAQET_DIR}"
echo "Install dir: ${PAQET_DIR}"
echo "Tarball: ${NAME}"
echo "URL: ${URL}"
echo
echo "=== NOTICE ==="
echo "GitHub download is time-limited (connect 5s, total ~20s)."
echo "If it fails, manually download the tarball and place it in ${PAQET_DIR}."
echo "============="
echo

# Download (skip if tarball already exists and is non-empty)
if [ -s "${TARBALL_PATH}" ]; then
  echo "Found existing tarball: ${TARBALL_PATH}"
else
  if [ -f "${TARBALL_PATH}" ] && [ ! -s "${TARBALL_PATH}" ]; then
    echo "Found empty tarball (0 bytes). Removing: ${TARBALL_PATH}"
    rm -f "${TARBALL_PATH}" || true
    if [ -f "${TARBALL_PATH}" ]; then
      echo "Empty tarball still exists. Please remove it with:" >&2
      echo "  rm -f ${TARBALL_PATH}" >&2
      exit 1
    fi
  fi
  # Quick GitHub reachability check (avoid long hangs)
  if command -v curl >/dev/null 2>&1; then
    if ! curl -fsS --connect-timeout 3 --max-time 5 https://github.com/hanselime/paqet/releases/latest >/dev/null 2>&1; then
      echo "GitHub is not reachable from this server." >&2
      echo "Please download this file manually and place it in ${PAQET_DIR}:" >&2
      echo "  ${NAME}" >&2
      echo "Releases: https://github.com/hanselime/paqet/releases/latest" >&2
      exit 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -q --timeout=5 --spider https://github.com/hanselime/paqet/releases/latest >/dev/null 2>&1; then
      echo "GitHub is not reachable from this server." >&2
      echo "Please download this file manually and place it in ${PAQET_DIR}:" >&2
      echo "  ${NAME}" >&2
      echo "Releases: https://github.com/hanselime/paqet/releases/latest" >&2
      exit 1
    fi
  fi

  if command -v wget >/dev/null 2>&1; then
    if ! wget -q --timeout=5 --tries=1 "${URL}" -O "${NAME}"; then
      echo "Download failed." >&2
      if [ -f "${TARBALL_PATH}" ] && [ ! -s "${TARBALL_PATH}" ]; then
        echo "Removing empty tarball created by failed download." >&2
        rm -f "${TARBALL_PATH}" || true
        if [ -f "${TARBALL_PATH}" ]; then
          echo "Empty tarball still exists. Please remove it with:" >&2
          echo "  rm -f ${TARBALL_PATH}" >&2
        fi
      fi
      echo "---- DEBUG INFO ----" >&2
      pwd >&2
      ls -la >&2
      df -h . >&2
      echo "--------------------" >&2
      echo >&2
      echo "=== MANUAL DOWNLOAD ===" >&2
      echo "Place this file in ${PAQET_DIR}:" >&2
      echo "  ${NAME}" >&2
      echo "URL: ${URL}" >&2
      echo "=======================" >&2
      echo "Then re-run the installer." >&2
      exit 1
    fi
  elif command -v curl >/dev/null 2>&1; then
    if ! curl -fSL --connect-timeout 5 --max-time 20 "${URL}" -o "${NAME}"; then
      echo "Download failed." >&2
      if [ -f "${TARBALL_PATH}" ] && [ ! -s "${TARBALL_PATH}" ]; then
        echo "Removing empty tarball created by failed download." >&2
        rm -f "${TARBALL_PATH}" || true
        if [ -f "${TARBALL_PATH}" ]; then
          echo "Empty tarball still exists. Please remove it with:" >&2
          echo "  rm -f ${TARBALL_PATH}" >&2
        fi
      fi
      echo "---- DEBUG INFO ----" >&2
      pwd >&2
      ls -la >&2
      df -h . >&2
      echo "--------------------" >&2
      echo >&2
      echo "=== MANUAL DOWNLOAD ===" >&2
      echo "Place this file in ${PAQET_DIR}:" >&2
      echo "  ${NAME}" >&2
      echo "URL: ${URL}" >&2
      echo "=======================" >&2
      echo "Then re-run the installer." >&2
      exit 1
    fi
  else
    echo "Neither wget nor curl is available." >&2
    echo "=== MANUAL DOWNLOAD ===" >&2
    echo "Place this file in ${PAQET_DIR}:" >&2
    echo "  ${NAME}" >&2
    echo "URL: ${URL}" >&2
    echo "=======================" >&2
    echo "Then re-run the installer." >&2
    exit 1
  fi
fi

# Extract into this folder
if command -v tar >/dev/null 2>&1; then
  if ! tar -xvzf "${NAME}"; then
    echo "Tarball extract failed (possibly corrupted): ${TARBALL_PATH}" >&2
    rm -f "${TARBALL_PATH}"
    echo "Please download this file manually and place it in ${PAQET_DIR}:" >&2
    echo "  ${NAME}" >&2
    echo "Releases: https://github.com/hanselime/paqet/releases/latest" >&2
    exit 1
  fi
else
  echo "tar is not available." >&2
  exit 1
fi

# Rename binary to paqet
mv "paqet_${OS}_${ARCH}" paqet
chmod +x paqet

# optional: clean the tarball
# rm -f "${NAME}"

ls -la
