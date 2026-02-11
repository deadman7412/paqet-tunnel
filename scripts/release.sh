#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required." >&2
  exit 1
fi

if ! git -C "${REPO_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository: ${REPO_DIR}" >&2
  exit 1
fi

TAG="${1:-}"
if [ -z "${TAG}" ]; then
  echo "Usage: scripts/release.sh vX.Y.Z" >&2
  exit 1
fi

if ! [[ "${TAG}" =~ ^v[0-9] ]]; then
  echo "Tag must start with v (example: v0.1.0)" >&2
  exit 1
fi

# Ensure working tree is clean
if ! git -C "${REPO_DIR}" diff --quiet || ! git -C "${REPO_DIR}" diff --cached --quiet; then
  echo "Working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

echo "${TAG}" > "${REPO_DIR}/VERSION"
git -C "${REPO_DIR}" add VERSION
git -C "${REPO_DIR}" commit -m "chore: bump version to ${TAG}"
git -C "${REPO_DIR}" tag -a "${TAG}" -m "Release ${TAG}"

echo "Created commit + tag ${TAG}."
echo "Next:"
echo "  git push"
echo "  git push --tags"
