#!/usr/bin/env bash
# Provision dependencies for `python3 test/run_campaigns.py` (root governor) on Linux CI.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

start_supabase=1
if [[ "${1:-}" == "--no-supabase" ]]; then
  start_supabase=0
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_command node
require_command npm
require_command python3
require_command flutter

echo "Installing Node campaign packages..."
for pkg_dir in \
  packages/vendor-contracts \
  ai-platform \
  abo \
  e2e/fullstack
do
  echo "  npm ci in ${pkg_dir}"
  (cd "${repo_root}/${pkg_dir}" && npm ci)
done

echo "Installing Flutter dependencies..."
(cd "${repo_root}/frontend" && flutter pub get)

echo "Installing Python harness dependencies..."
python3 -m pip install --disable-pip-version-check -r "${repo_root}/test/requirements.txt"

if [[ "${start_supabase}" -eq 1 ]]; then
  require_command supabase
  echo "Starting local Supabase (backend/)..."
  (cd "${repo_root}/backend" && supabase start)
else
  echo "Skipping supabase start (--no-supabase)."
fi

echo "Test campaign environment ready."
