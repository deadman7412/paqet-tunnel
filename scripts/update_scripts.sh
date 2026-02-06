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

echo "Connecting to GitHub..."
git -C "${REPO_DIR}" fetch --prune
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

git -C "${REPO_DIR}" pull --ff-only

if [ "${STASHED}" -eq 1 ]; then
  echo "Re-applying local changes..."
  if ! git -C "${REPO_DIR}" stash pop >/dev/null 2>&1; then
    echo "Warning: stash pop had conflicts. Resolve them manually." >&2
    exit 1
  fi
fi

echo "Update complete."
