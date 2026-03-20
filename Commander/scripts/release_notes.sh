#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ENGINE_DIR}/.." && pwd)"

TAG=""
FROM_REF=""
TO_REF="HEAD"
TITLE=""
OUTPUT_PATH=""

usage() {
  cat <<'EOF'
Usage: scripts/release_notes.sh [options]

Generate Markdown release notes from the previous tag (or a custom range) to a target ref.

Options:
  --tag <version>            Release tag label to show in the title, accepts "v1.0.3" or "1.0.3"
  --from <ref>               Start ref for commit range (default: latest reachable tag before --to)
  --to <ref>                 End ref for commit range (default: HEAD)
  --title <text>             Custom title (default: "Release <tag>" or "Release Notes")
  --output <path>            Write Markdown to file instead of stdout
  -h, --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || { echo "Missing value for --tag" >&2; exit 2; }
      TAG="$2"
      shift 2
      ;;
    --from)
      [[ $# -ge 2 ]] || { echo "Missing value for --from" >&2; exit 2; }
      FROM_REF="$2"
      shift 2
      ;;
    --to)
      [[ $# -ge 2 ]] || { echo "Missing value for --to" >&2; exit 2; }
      TO_REF="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || { echo "Missing value for --title" >&2; exit 2; }
      TITLE="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 2; }
      OUTPUT_PATH="$2"
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

if [[ -n "${TAG}" && "${TAG}" != v* ]]; then
  TAG="v${TAG}"
fi

cd "${REPO_ROOT}"

if ! git rev-parse --verify "${TO_REF}^{commit}" >/dev/null 2>&1; then
  echo "Invalid --to ref: ${TO_REF}" >&2
  exit 1
fi

if [[ -n "${FROM_REF}" ]]; then
  if ! git rev-parse --verify "${FROM_REF}^{commit}" >/dev/null 2>&1; then
    echo "Invalid --from ref: ${FROM_REF}" >&2
    exit 1
  fi
else
  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    if [[ -n "${TAG}" && "${candidate}" == "${TAG}" ]]; then
      continue
    fi
    FROM_REF="${candidate}"
    break
  done < <(git tag --merged "${TO_REF}" --sort=-creatordate)
fi

if [[ -z "${TITLE}" ]]; then
  if [[ -n "${TAG}" ]]; then
    TITLE="Release ${TAG}"
  else
    TITLE="Release Notes"
  fi
fi

if [[ -n "${FROM_REF}" ]]; then
  RANGE="${FROM_REF}..${TO_REF}"
  RANGE_LABEL="${FROM_REF}..${TO_REF}"
else
  RANGE="${TO_REF}"
  RANGE_LABEL="${TO_REF}"
fi

DATE_LABEL="$(date '+%Y-%m-%d')"
NOTES="$(mktemp)"
trap 'rm -f "${NOTES}"' EXIT

{
  echo "# ${TITLE}"
  echo
  if [[ -n "${TAG}" ]]; then
    echo "- Version: \`${TAG}\`"
  fi
  echo "- Date: ${DATE_LABEL}"
  echo "- Range: \`${RANGE_LABEL}\`"
  echo
  echo "## Commits"
  COMMITS="$(git log --reverse --no-merges --pretty='- %s (`%h`)' "${RANGE}")"
  if [[ -n "${COMMITS}" ]]; then
    printf '%s\n' "${COMMITS}"
  else
    echo "- No commits in range"
  fi
} > "${NOTES}"

if [[ -n "${OUTPUT_PATH}" ]]; then
  cp "${NOTES}" "${OUTPUT_PATH}"
else
  cat "${NOTES}"
fi
