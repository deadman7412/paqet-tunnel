#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

git -C "${REPO_DIR}" fetch --prune
git -C "${REPO_DIR}" status -sb

read -r -p "Pull latest changes from origin? [y/N]: " CONFIRM
case "${CONFIRM}" in
  y|Y) ;;
  *) echo "Aborted."; exit 0 ;;
esac

git -C "${REPO_DIR}" pull --ff-only

echo "Update complete."
