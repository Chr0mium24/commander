#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ENGINE_DIR}/.." && pwd)"
PROJECT_PATH="${REPO_ROOT}/Commander.xcodeproj"
SCHEME="commander"
DESTINATION="platform=macOS"
SDK="macosx"
DERIVED_DATA="/tmp/CommanderGateBuild"
LOCAL_VENV_PATH="${ENGINE_DIR}/.venv"
UV_PROJECT_ENV_PATH="${REPO_ROOT}/.venv"

usage() {
  cat <<'EOF'
Usage: scripts/release_gate.sh [options]

Options:
  -h, --help                 Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ -d "${LOCAL_VENV_PATH}" ]]; then
  echo "==> [gate] Removing local virtualenv to avoid Xcode resource collisions: ${LOCAL_VENV_PATH}"
  rm -rf "${LOCAL_VENV_PATH}"
fi

if [[ -d "${DERIVED_DATA}" ]]; then
  echo "==> [gate] Clearing derived data: ${DERIVED_DATA}"
  rm -rf "${DERIVED_DATA}"
fi

echo "==> [gate] Build Debug"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -sdk "${SDK}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> [gate] Python compile check"
cd "${ENGINE_DIR}"
UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENV_PATH}" uv run --project . python -m py_compile \
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
HELP_OUTPUT="$(UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENV_PATH}" uv run --project . python python/commander_engine.py '{"query":"help","settings":{}}')"
PLUGINS_OUTPUT="$(UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENV_PATH}" uv run --project . python python/commander_engine.py '{"query":"plugins","settings":{}}')"

if [[ "${HELP_OUTPUT}" != *"Commander Python Engine"* ]]; then
  echo "[gate] help smoke check failed"
  exit 1
fi

if [[ "${PLUGINS_OUTPUT}" != *"### Plugins"* ]]; then
  echo "[gate] plugins smoke check failed"
  exit 1
fi

echo "==> [gate] PASS"
