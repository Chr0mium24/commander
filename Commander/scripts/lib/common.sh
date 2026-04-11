#!/usr/bin/env bash

COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${COMMON_SCRIPT_DIR}/.." && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ENGINE_DIR}/.." && pwd)"

normalize_tag() {
  local tag="${1:-}"
  if [[ -n "${tag}" && "${tag}" != v* ]]; then
    printf 'v%s\n' "${tag}"
    return 0
  fi
  printf '%s\n' "${tag}"
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

resolve_uv_executable() {
  local override="${COMMANDER_UV_BIN:-}"
  if [[ -n "${override}" && -x "${override}" ]]; then
    printf '%s\n' "${override}"
    return 0
  fi

  if command -v uv >/dev/null 2>&1; then
    command -v uv
    return 0
  fi

  local candidate
  for candidate in \
    "/opt/homebrew/bin/uv" \
    "/usr/local/bin/uv" \
    "/usr/bin/uv" \
    "/bin/uv"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

infer_github_repo() {
  git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##'
}

require_git_ref() {
  local ref_name="$1"
  local label="$2"
  if ! git rev-parse --verify "${ref_name}^{commit}" >/dev/null 2>&1; then
    echo "Invalid ${label}: ${ref_name}" >&2
    exit 1
  fi
}

find_previous_tag() {
  local to_ref="$1"
  local skip_tag="${2:-}"
  local candidate

  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    if [[ -n "${skip_tag}" && "${candidate}" == "${skip_tag}" ]]; then
      continue
    fi
    printf '%s\n' "${candidate}"
    return 0
  done < <(git tag --merged "${to_ref}" --sort=-creatordate)

  return 1
}

require_synced_with_upstream() {
  local upstream_ref
  local local_head
  local remote_head
  local ahead_count
  local behind_count

  upstream_ref="$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || true)"
  if [[ -z "${upstream_ref}" ]]; then
    echo "No upstream branch configured. Push with -u first." >&2
    exit 1
  fi

  local_head="$(git rev-parse HEAD)"
  remote_head="$(git rev-parse "@{u}")"
  if [[ "${local_head}" == "${remote_head}" ]]; then
    return 0
  fi

  ahead_count="$(git rev-list --count "@{u}..HEAD")"
  behind_count="$(git rev-list --count "HEAD..@{u}")"
  echo "Current commit is not synced with ${upstream_ref}." >&2
  echo "Ahead: ${ahead_count}, Behind: ${behind_count}" >&2
  exit 1
}
