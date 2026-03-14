#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Commander.xcodeproj"
SCHEME="commander"
CONFIGURATION="Debug"
DESTINATION="platform=macOS"
DERIVED_DATA_PATH="/tmp/CommanderDerived"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/Commander.app"

DO_CLEAN=0
DO_OPEN=1
DO_KILL=0

usage() {
  cat <<'EOF'
Usage: scripts/build_run.sh [options]

Options:
  --clean      Clean before building
  --no-open    Build only, do not launch app
  --kill       Kill existing Commander process before launch
  -h, --help   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      DO_CLEAN=1
      shift
      ;;
    --no-open)
      DO_OPEN=0
      shift
      ;;
    --kill)
      DO_KILL=1
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

if [[ ! -d "${PROJECT_PATH}" ]]; then
  echo "Project not found: ${PROJECT_PATH}" >&2
  exit 1
fi

echo "==> Building ${SCHEME} (${CONFIGURATION})"
XCBUILD_CMD=(
  xcodebuild
  -project "${PROJECT_PATH}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination "${DESTINATION}"
  -derivedDataPath "${DERIVED_DATA_PATH}"
)

if [[ "${DO_CLEAN}" -eq 1 ]]; then
  XCBUILD_CMD+=(clean build)
else
  XCBUILD_CMD+=(build)
fi

"${XCBUILD_CMD[@]}"

if [[ "${DO_OPEN}" -eq 0 ]]; then
  echo "==> Build finished (launch skipped)"
  exit 0
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Build finished but app not found: ${APP_PATH}" >&2
  exit 1
fi

if [[ "${DO_KILL}" -eq 1 ]]; then
  echo "==> Killing existing Commander process"
  pkill -f "${APP_PATH}/Contents/MacOS/Commander" 2>/dev/null || true
fi

echo "==> Launching ${APP_PATH}"
open "${APP_PATH}"
echo "==> Done"
