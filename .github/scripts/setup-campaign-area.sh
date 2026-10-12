#!/usr/bin/env bash
# Install only what a single root campaign area needs on Linux CI.
set -euo pipefail

area="${1:?usage: setup-campaign-area.sh <frontend|backend|ai-platform|abo|e2e-fullstack|vendor-contracts|ops-launch>}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_command node
require_command npm
require_command python3

echo "Installing Python harness dependencies..."
python3 -m pip install --disable-pip-version-check -r "${repo_root}/test/requirements.txt"

npm_dirs=()
need_supabase=0
need_flutter=0

case "${area}" in
  frontend)
    need_supabase=1
    need_flutter=1
    ;;
  backend)
    need_supabase=1
    ;;
  ai-platform)
    npm_dirs+=(packages/vendor-contracts ai-platform)
    ;;
  abo)
    npm_dirs+=(packages/vendor-contracts ai-platform abo)
    ;;
  e2e-fullstack)
    need_supabase=1
    npm_dirs+=(packages/vendor-contracts e2e/fullstack)
    ;;
  vendor-contracts)
    npm_dirs+=(packages/vendor-contracts)
    ;;
  ops-launch)
    ;;
  *)
    echo "ERROR: unknown campaign area: ${area}" >&2
    exit 1
    ;;
esac

for pkg_dir in "${npm_dirs[@]}"; do
  echo "  npm ci in ${pkg_dir}"
  (cd "${repo_root}/${pkg_dir}" && npm ci)
done

if [[ "${need_flutter}" -eq 1 ]]; then
  require_command flutter
  echo "Installing Flutter dependencies..."
  (cd "${repo_root}/frontend" && flutter pub get)
fi

if [[ "${need_supabase}" -eq 1 ]]; then
  require_command supabase
  echo "Starting local Supabase (backend/)..."
  (cd "${repo_root}/backend" && supabase start)
fi

echo "Campaign area ${area} ready."
