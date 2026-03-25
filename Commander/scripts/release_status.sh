#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

REPO=""
WORKFLOW="Build And Release"
TAG=""
RUN_ID=""
WAIT=0
POLL_INTERVAL=10

usage() {
  cat <<'EOF'
Usage: scripts/release_status.sh [options]

Check the latest GitHub Actions release workflow status and optionally wait for completion.

Options:
  --tag <version>            Check the run for a specific tag, accepts "v1.0.8" or "1.0.8"
  --run-id <id>              Check a specific GitHub Actions run id instead of resolving by tag
  --repo <owner/name>        GitHub repository, default: inferred from local git remote
  --workflow <name>          Workflow name, default: "Build And Release"
  --wait                     Poll until the run completes
  --poll-interval <seconds>  Poll interval for --wait, default: 10
  -h, --help                 Show this help

Exit codes:
  0  Completed successfully
  1  Completed but failed/cancelled, or no matching run found
  2  Run exists but is still queued/in progress
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || { echo "Missing value for --tag" >&2; exit 2; }
      TAG="$2"
      shift 2
      ;;
    --run-id)
      [[ $# -ge 2 ]] || { echo "Missing value for --run-id" >&2; exit 2; }
      RUN_ID="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "Missing value for --repo" >&2; exit 2; }
      REPO="$2"
      shift 2
      ;;
    --workflow)
      [[ $# -ge 2 ]] || { echo "Missing value for --workflow" >&2; exit 2; }
      WORKFLOW="$2"
      shift 2
      ;;
    --wait)
      WAIT=1
      shift
      ;;
    --poll-interval)
      [[ $# -ge 2 ]] || { echo "Missing value for --poll-interval" >&2; exit 2; }
      POLL_INTERVAL="$2"
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

TAG="$(normalize_tag "${TAG}")"

cd "${REPO_ROOT}"

require_command gh

if [[ -z "${REPO}" ]]; then
  REPO="$(infer_github_repo)"
fi

if [[ -z "${REPO}" ]]; then
  echo "Unable to determine GitHub repo. Pass --repo owner/name." >&2
  exit 1
fi

if [[ -z "${RUN_ID}" && -z "${TAG}" ]]; then
  TAG="$(git tag --sort=-creatordate | head -n 1)"
fi

if [[ -z "${RUN_ID}" && -z "${TAG}" ]]; then
  echo "No tag found to inspect. Pass --tag or --run-id." >&2
  exit 1
fi

resolve_run_id() {
  local json
  if ! json="$(gh run list \
    -R "${REPO}" \
    --workflow "${WORKFLOW}" \
    --branch "${TAG}" \
    --event push \
    --limit 20 \
    --json databaseId,status,conclusion,workflowName,displayTitle,headBranch,headSha,createdAt,updatedAt,url 2>/dev/null)"; then
    return 1
  fi

  python3 - <<'PY' "${json}"
import json
import sys

runs = json.loads(sys.argv[1] or "[]")
if not runs:
    sys.exit(1)
print(runs[0]["databaseId"])
PY
}

print_summary() {
  local json="$1"
  python3 - <<'PY' "${json}"
import json
import sys

payload = json.loads(sys.argv[1])
print(f"workflow: {payload.get('workflowName')}")
print(f"run_id: {payload.get('databaseId')}")
print(f"status: {payload.get('status')}")
print(f"conclusion: {payload.get('conclusion')}")
print(f"ref: {payload.get('headBranch')}")
print(f"sha: {payload.get('headSha')}")
print(f"title: {payload.get('displayTitle')}")
print(f"url: {payload.get('url')}")
jobs = payload.get("jobs") or []
if jobs:
    print("jobs:")
    for job in jobs:
        print(f"  - {job.get('name')}: {job.get('status')} / {job.get('conclusion')}")
PY
}

run_view_json() {
  gh run view "${RUN_ID}" \
    -R "${REPO}" \
    --json databaseId,status,conclusion,workflowName,displayTitle,headBranch,headSha,createdAt,updatedAt,jobs,url
}

if [[ -z "${RUN_ID}" ]]; then
  if ! RUN_ID="$(resolve_run_id)"; then
    echo "No matching workflow run found for ${WORKFLOW} on tag ${TAG}." >&2
    exit 1
  fi
fi

while true; do
  VIEW_JSON="$(run_view_json)"
  print_summary "${VIEW_JSON}"

  STATUS="$(python3 - <<'PY' "${VIEW_JSON}"
import json
import sys
payload = json.loads(sys.argv[1])
print(payload.get("status") or "")
PY
)"

  CONCLUSION="$(python3 - <<'PY' "${VIEW_JSON}"
import json
import sys
payload = json.loads(sys.argv[1])
print(payload.get("conclusion") or "")
PY
)"

  if [[ "${STATUS}" == "completed" ]]; then
    if [[ "${CONCLUSION}" == "success" ]]; then
      exit 0
    fi
    exit 1
  fi

  if [[ "${WAIT}" -eq 0 ]]; then
    exit 2
  fi

  echo "Waiting ${POLL_INTERVAL}s for run ${RUN_ID}..."
  sleep "${POLL_INTERVAL}"
done
