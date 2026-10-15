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
    npm_dirs+=(packages/vendor-contracts ai-platform abo e2e/fullstack)
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
    need_flutter=1
    npm_dirs+=(packages/vendor-contracts ai-platform abo e2e/fullstack)
    ;;
  vendor-contracts)
    npm_dirs+=(packages/vendor-contracts ai-platform)
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
  if [[ "${area}" == "e2e-fullstack" ]]; then
    (cd "${repo_root}/e2e/fullstack/dart" && flutter pub get)
  fi
fi

if [[ "${need_supabase}" -eq 1 ]]; then
  require_command supabase
  echo "Starting local Supabase (backend/)..."
  (cd "${repo_root}/backend" && supabase start)
fi

if [[ "${area}" == "frontend" ]]; then
  echo "Writing frontend local deployment profile..."
  anon_key=""
  api_url=""
  if status_env="$(cd "${repo_root}/backend" && supabase status -o env 2>/dev/null)"; then
    anon_key="$(printf '%s\n' "${status_env}" | sed -n 's/^ANON_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -n 1)"
    api_url="$(printf '%s\n' "${status_env}" | sed -n 's/^API_URL="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -n 1)"
  fi
  anon_key="${anon_key:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0}"
  api_url="${api_url:-http://127.0.0.1:54321}"
  mkdir -p "${repo_root}/frontend/config/local"
  cat > "${repo_root}/frontend/config/local/deployment-profile.json" <<EOF
{
  "deployment_mode": "local",
  "supabase_url": "${api_url}",
  "supabase_anon_key": "${anon_key}"
}
EOF
fi

echo "Campaign area ${area} ready."
