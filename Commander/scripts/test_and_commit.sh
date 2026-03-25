#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
GATE_SCRIPT="${SCRIPT_DIR}/release_gate.sh"

RUN_GATE=1
ALLOW_EMPTY=0
COMMIT_MESSAGE=""

usage() {
  cat <<'EOF'
Usage: scripts/test_and_commit.sh --message <text> [options]

Run release gate checks, stage current changes, and create a git commit.

Options:
  --message <text>           Commit message to create
  --no-gate                  Skip release gate checks
  --allow-empty              Allow creating an empty commit
  -h, --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message|-m)
      [[ $# -ge 2 ]] || { echo "Missing value for --message" >&2; exit 2; }
      COMMIT_MESSAGE="$2"
      shift 2
      ;;
    --no-gate)
      RUN_GATE=0
      shift
      ;;
    --allow-empty)
      ALLOW_EMPTY=1
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

if [[ -z "${COMMIT_MESSAGE}" ]]; then
  echo "--message is required" >&2
  usage
  exit 2
fi

if [[ ! -f "${GATE_SCRIPT}" ]]; then
  echo "Gate script missing: ${GATE_SCRIPT}" >&2
  exit 1
fi

cd "${REPO_ROOT}"

if [[ "${RUN_GATE}" -eq 1 ]]; then
  echo "==> Running release gate"
  bash "${GATE_SCRIPT}"
fi

if [[ -z "$(git status --porcelain)" && "${ALLOW_EMPTY}" -eq 0 ]]; then
  echo "No changes to commit." >&2
  exit 1
fi

echo "==> Staging changes"
git add -A

echo "==> Creating commit"
if [[ "${ALLOW_EMPTY}" -eq 1 ]]; then
  git commit --allow-empty -m "${COMMIT_MESSAGE}"
else
  git commit -m "${COMMIT_MESSAGE}"
fi

echo "==> Done"
