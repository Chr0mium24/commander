#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ENGINE_DIR}/.." && pwd)"
PROJECT_PATH="${REPO_ROOT}/Commander.xcodeproj"
SCHEME="commander"
DESTINATION="platform=macOS"
DERIVED_DATA="/tmp/CommanderGateBuild"
MIN_COMMITS_SINCE_TAG=0
LOCAL_VENV_PATH="${ENGINE_DIR}/.venv"

usage() {
  cat <<'EOF'
Usage: scripts/release_gate.sh [options]

Options:
  --min-commits-since-tag N  Require at least N commits after latest tag.
                             Set to 0 to disable this release-readiness check.
  -h, --help                 Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --min-commits-since-tag)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --min-commits-since-tag" >&2
        exit 2
      fi
      MIN_COMMITS_SINCE_TAG="$2"
      shift 2
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

if ! [[ "${MIN_COMMITS_SINCE_TAG}" =~ ^[0-9]+$ ]]; then
  echo "--min-commits-since-tag must be a non-negative integer" >&2
  exit 2
fi

if [[ -d "${LOCAL_VENV_PATH}" ]]; then
  echo "==> [gate] Removing local virtualenv to avoid Xcode resource collisions: ${LOCAL_VENV_PATH}"
  rm -rf "${LOCAL_VENV_PATH}"
fi

echo "==> [gate] Build Debug"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> [gate] Python compile check"
cd "${ENGINE_DIR}"
uv run --project . python -m py_compile \
  python/command_engine/main.py \
  python/command_engine/router.py \
  python/command_engine/plugin_registry.py \
  python/command_engine/prompts.py \
  python/command_engine/plugins/core.py \
  python/command_engine/plugins/shell.py \
  python/command_engine/plugins/ai.py \
  python/command_engine/plugins/web.py \
  python/command_engine/plugins/read.py \
  python/command_engine/plugins/music.py

echo "==> [gate] Router smoke tests"
HELP_OUTPUT="$(uv run --project . python python/commander_engine.py '{"query":"help","settings":{}}')"
PLUGINS_OUTPUT="$(uv run --project . python python/commander_engine.py '{"query":"plugins","settings":{}}')"

if [[ "${HELP_OUTPUT}" != *"Commander Python Engine"* ]]; then
  echo "[gate] help smoke check failed"
  exit 1
fi

if [[ "${PLUGINS_OUTPUT}" != *"### Plugins"* ]]; then
  echo "[gate] plugins smoke check failed"
  exit 1
fi

if [[ "${MIN_COMMITS_SINCE_TAG}" -gt 0 ]]; then
  echo "==> [gate] Release readiness (min commits since tag: ${MIN_COMMITS_SINCE_TAG})"
  cd "${REPO_ROOT}"
  LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  if [[ -z "${LAST_TAG}" ]]; then
    echo "[gate] No previous tag found. Treat as first release."
  else
    COMMITS_SINCE_TAG="$(git rev-list --count "${LAST_TAG}..HEAD")"
    if [[ "${COMMITS_SINCE_TAG}" -lt "${MIN_COMMITS_SINCE_TAG}" ]]; then
      echo "[gate] Not enough changes for release: ${COMMITS_SINCE_TAG} < ${MIN_COMMITS_SINCE_TAG} since ${LAST_TAG}" >&2
      exit 1
    fi
    echo "[gate] Commits since ${LAST_TAG}: ${COMMITS_SINCE_TAG}"
  fi
fi

echo "==> [gate] PASS"
