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

if [ -z "${VERSION}" ]; then
  if command -v curl >/dev/null 2>&1; then
    VERSION="$(curl -fsSL https://api.github.com/repos/hanselime/paqet/releases/latest | awk -F '\"' '/tag_name/{print $4; exit}')"
  elif command -v wget >/dev/null 2>&1; then
    VERSION="$(wget -qO- https://api.github.com/repos/hanselime/paqet/releases/latest | awk -F '\"' '/tag_name/{print $4; exit}')"
  fi
fi

if [ -z "${VERSION}" ]; then
  echo "Failed to detect latest release tag. Set VERSION manually." >&2
  exit 1
fi

NAME="paqet-${OS}-${ARCH}-${VERSION}.tar.gz"
URL="https://github.com/hanselime/paqet/releases/download/${VERSION}/${NAME}"

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

# Download (wget preferred, curl fallback)
if command -v wget >/dev/null 2>&1; then
  wget -q "${URL}" -O "${NAME}"
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "${URL}" -o "${NAME}"
else
  echo "Neither wget nor curl is available." >&2
  exit 1
fi

# Extract into this folder
if command -v tar >/dev/null 2>&1; then
  tar -xvzf "${NAME}"
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
