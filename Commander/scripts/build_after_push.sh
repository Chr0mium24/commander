#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ENGINE_DIR}/.." && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build_run.sh"

CONFIGURATION="Release"
DO_OPEN=0
DO_CLEAN=0
DO_KILL=0
SKIP_PUSH_CHECK=0

usage() {
  cat <<'EOF'
Usage: scripts/build_after_push.sh [options]

Build the current commit after verifying it has been pushed.

Options:
  --release          Build in Release mode (default)
  --debug            Build in Debug mode
  --open             Launch app after build
  --no-open          Build only (default)
  --clean            Clean before build
  --kill             Kill existing app process before launch
  --no-kill          Do not kill existing app process (default)
  --skip-push-check  Skip remote sync check
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)
      CONFIGURATION="Release"
      shift
      ;;
    --debug)
      CONFIGURATION="Debug"
      shift
      ;;
    --open)
      DO_OPEN=1
      shift
      ;;
    --no-open)
      DO_OPEN=0
      shift
      ;;
    --clean)
      DO_CLEAN=1
      shift
      ;;
    --kill)
      DO_KILL=1
      shift
      ;;
    --no-kill)
      DO_KILL=0
      shift
      ;;
    --skip-push-check)
      SKIP_PUSH_CHECK=1
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

if [[ ! -x "${BUILD_SCRIPT}" ]]; then
  echo "Build script not found or not executable: ${BUILD_SCRIPT}" >&2
  exit 1
fi

cd "${REPO_ROOT}"

if [[ "${SKIP_PUSH_CHECK}" -eq 0 ]]; then
  UPSTREAM_REF="$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || true)"
  if [[ -z "${UPSTREAM_REF}" ]]; then
    echo "No upstream branch configured. Push with -u first, or use --skip-push-check." >&2
    exit 1
  fi

  LOCAL_HEAD="$(git rev-parse HEAD)"
  REMOTE_HEAD="$(git rev-parse "@{u}")"
  if [[ "${LOCAL_HEAD}" != "${REMOTE_HEAD}" ]]; then
    AHEAD_COUNT="$(git rev-list --count "@{u}..HEAD")"
    BEHIND_COUNT="$(git rev-list --count "HEAD..@{u}")"
    echo "Current commit is not synced with ${UPSTREAM_REF}." >&2
    echo "Ahead: ${AHEAD_COUNT}, Behind: ${BEHIND_COUNT}" >&2
    echo "Push first or run with --skip-push-check." >&2
    exit 1
  fi
fi

SHORT_SHA="$(git rev-parse --short HEAD)"
SUBJECT="$(git log -1 --pretty=%s)"
echo "==> Building pushed commit ${SHORT_SHA}: ${SUBJECT}"

BUILD_ARGS=()
if [[ "${CONFIGURATION}" == "Release" ]]; then
  BUILD_ARGS+=(--release)
else
  BUILD_ARGS+=(--debug)
fi

if [[ "${DO_CLEAN}" -eq 1 ]]; then
  BUILD_ARGS+=(--clean)
fi

if [[ "${DO_OPEN}" -eq 1 ]]; then
  :
else
  BUILD_ARGS+=(--no-open)
fi

if [[ "${DO_KILL}" -eq 1 ]]; then
  BUILD_ARGS+=(--kill)
else
  BUILD_ARGS+=(--no-kill)
fi

cd "${ENGINE_DIR}"
bash "${BUILD_SCRIPT}" "${BUILD_ARGS[@]}"
