#!/usr/bin/env bash
set -euo pipefail

NEEDLES=(
  '/control/'
  'OPERATOR_BEARER_TOKEN'
  'set_ai_availability'
  'enroll_installation_keypair'
  'installation_key'
)

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

has_migrations_segment() {
  [[ "$1" == *migrations* ]]
}

scan_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "control-residue-guard: not a file: $file" >&2
    return 1
  fi

  for needle in "${NEEDLES[@]}"; do
    if grep -qF -- "$needle" "$file"; then
      echo "control-residue-guard: needle '$needle' in $file" >&2
      return 1
    fi
  done
  return 0
}

scan_dist_directory() {
  local dir="$1"
  local failed=0

  while IFS= read -r -d '' file; do
    if ! scan_file "$file"; then
      failed=1
    fi
  done < <(find "$dir" -type f -print0)

  return "$failed"
}

scan_git_directory() {
  local dir="$1"
  local failed=0

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if has_migrations_segment "$file"; then
      continue
    fi
    if ! scan_file "$REPO_ROOT/$file"; then
      failed=1
    fi
  done < <(git -C "$REPO_ROOT" ls-files "$dir")

  return "$failed"
}

scan_path() {
  local target="$1"

  if [[ -f "$target" ]]; then
    scan_file "$target"
    return
  fi

  if [[ ! -d "$target" ]]; then
    echo "control-residue-guard: path not found: $target" >&2
    return 1
  fi

  if [[ "$target" == */dist ]]; then
    scan_dist_directory "$target"
    return
  fi

  scan_git_directory "$target"
}

main() {
  if [[ "$#" -eq 0 ]]; then
    echo "usage: control-residue-guard.sh <path> [<path> ...]" >&2
    exit 2
  fi

  local failed=0
  for target in "$@"; do
    if ! scan_path "$target"; then
      failed=1
    fi
  done

  if [[ "$failed" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
