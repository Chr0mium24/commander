#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
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

remove_path() {
  local path="$1"
  local label="$2"

  if [[ ! -e "${path}" ]]; then
    return 0
  fi

  echo "==> [gate] Clearing ${label}: ${path}"
  rm -rf "${path}" 2>/dev/null || true

  if [[ -e "${path}" ]]; then
    sleep 1
    rm -rf "${path}" 2>/dev/null || true
  fi

  if [[ -e "${path}" ]]; then
    echo "[gate] Failed to clear ${label}: ${path}" >&2
    exit 1
  fi
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if command -v rg >/dev/null 2>&1; then
    if rg -U -q "${pattern}" "${file}"; then
      return 0
    fi
  elif perl -0ne "exit(!(/${pattern}/s))" "${file}"; then
    return 0
  fi

  if [[ -f "${file}" ]]; then
    echo "[gate] ${message}" >&2
    exit 1
  fi
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
  remove_path "${LOCAL_VENV_PATH}" "local virtualenv to avoid Xcode resource collisions"
fi

if [[ -d "${DERIVED_DATA}" ]]; then
  remove_path "${DERIVED_DATA}" "derived data"
fi

echo "==> [gate] Actor isolation compatibility checks"
require_pattern \
  "${ENGINE_DIR}/AppState.swift" \
  '@MainActor\s*@Observable\s*class AppState' \
  "AppState must be explicitly annotated with @MainActor for CI/Xcode compatibility."
require_pattern \
  "${ENGINE_DIR}/StatusItemController.swift" \
  '@MainActor\s*final class StatusItemController' \
  "StatusItemController must be explicitly annotated with @MainActor for CI/Xcode compatibility."

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
