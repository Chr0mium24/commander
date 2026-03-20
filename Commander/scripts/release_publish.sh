#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ENGINE_DIR}/.." && pwd)"
GATE_SCRIPT="${SCRIPT_DIR}/release_gate.sh"

REMOTE="origin"
BRANCH="main"
RUN_GATE=1
ALLOW_DIRTY=0
DRY_RUN=0
TAG=""
TAG_MESSAGE=""
NOTES_FILE=""

usage() {
  cat <<'EOF'
Usage: scripts/release_publish.sh --tag <version> [options]

Run release gate, verify an explicit release notes file, push branch, create an annotated tag, and push tag to trigger GitHub Release workflow.

Options:
  --tag <version>            Release version tag. Accepts "v0.3.0" or "0.3.0"
  --message <text>           Release title / annotated tag heading (default: "Release <tag>")
  --notes-file <path>        Required Markdown file used as the annotated tag body
  --remote <name>            Git remote (default: origin)
  --branch <name>            Branch to push before tagging (default: main)
  --no-gate                  Skip release gate checks
  --allow-dirty              Allow uncommitted working tree
  --dry-run                  Print commands only, do not execute
  -h, --help                 Show this help
EOF
}

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --tag" >&2
        exit 2
      fi
      TAG="$2"
      shift 2
      ;;
    --message)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --message" >&2
        exit 2
      fi
      TAG_MESSAGE="$2"
      shift 2
      ;;
    --remote)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --remote" >&2
        exit 2
      fi
      REMOTE="$2"
      shift 2
      ;;
    --branch)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --branch" >&2
        exit 2
      fi
      BRANCH="$2"
      shift 2
      ;;
    --notes-file)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --notes-file" >&2
        exit 2
      fi
      NOTES_FILE="$2"
      shift 2
      ;;
    --no-gate)
      RUN_GATE=0
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${TAG}" ]]; then
  echo "--tag is required" >&2
  usage
  exit 2
fi

if [[ -z "${NOTES_FILE}" ]]; then
  echo "--notes-file is required. Generate context with scripts/release_notes.sh, write the final Markdown notes, then pass that file here." >&2
  usage
  exit 2
fi

if [[ "${TAG}" != v* ]]; then
  TAG="v${TAG}"
fi

if [[ -z "${TAG_MESSAGE}" ]]; then
  TAG_MESSAGE="Release ${TAG}"
fi

if [[ ! -f "${GATE_SCRIPT}" ]]; then
  echo "Gate script missing: ${GATE_SCRIPT}" >&2
  exit 1
fi

cd "${REPO_ROOT}"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${CURRENT_BRANCH}" != "${BRANCH}" ]]; then
  echo "Current branch is '${CURRENT_BRANCH}', expected '${BRANCH}'." >&2
  exit 1
fi

if [[ "${ALLOW_DIRTY}" -eq 0 ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean. Commit/stash first, or use --allow-dirty." >&2
    exit 1
  fi
fi

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "Tag already exists locally: ${TAG}" >&2
  exit 1
fi

if [[ "${DRY_RUN}" -eq 0 ]]; then
  if git ls-remote --tags "${REMOTE}" "refs/tags/${TAG}" | grep -q .; then
    echo "Tag already exists on remote '${REMOTE}': ${TAG}" >&2
    exit 1
  fi
else
  echo "[dry-run] Skipping remote tag existence check for ${REMOTE}/${TAG}"
fi

if [[ ! -f "${NOTES_FILE}" ]]; then
  echo "Notes file not found: ${NOTES_FILE}" >&2
  exit 1
fi

if ! grep -q '[^[:space:]]' "${NOTES_FILE}"; then
  echo "Notes file is empty: ${NOTES_FILE}" >&2
  exit 1
fi

if [[ "${RUN_GATE}" -eq 1 ]]; then
  echo "==> Running release gate"
  run bash "${GATE_SCRIPT}"
fi

echo "==> Pushing branch ${BRANCH} to ${REMOTE}"
run git push "${REMOTE}" "${BRANCH}"

echo "==> Creating tag ${TAG}"
run git tag -a "${TAG}" -F "${NOTES_FILE}"

echo "==> Pushing tag ${TAG} to ${REMOTE}"
run git push "${REMOTE}" "${TAG}"

echo "==> Done"
echo "GitHub Actions release workflow should start for tag ${TAG}."
