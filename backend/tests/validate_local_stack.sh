#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_dir="$(cd "${script_dir}/../local" && pwd)"
smoke_script="${script_dir}/connectivity_smoke.sh"

usage() {
  cat <<'EOF'
Validate the clinic-local Supabase stack for AiClinic V1-0.

Usage:
  ./backend/tests/validate_local_stack.sh [options]

Options:
  --no-start       Do not run `docker compose up`; fail if the gateway is down.
  --teardown       Run `docker compose down` after a successful validation.
  --max-wait SEC   Maximum seconds to wait for gateway readiness (default: 120).
  -h, --help       Show this help text.

Typical flows:
  Developer machine (stack already running):
    ./backend/tests/validate_local_stack.sh --no-start

  First-time or CI bring-up:
    ./backend/tests/validate_local_stack.sh

  CI cleanup after validation:
    ./backend/tests/validate_local_stack.sh --teardown
EOF
}

require_command() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    printf 'ERROR: required command not found: %s\n' "${name}" >&2
    exit 1
  fi
}

no_start=0
teardown=0
max_wait=120

while (($# > 0)); do
  case "$1" in
    --no-start)
      no_start=1
      shift
      ;;
    --teardown)
      teardown=1
      shift
      ;;
    --max-wait)
      if (($# < 2)); then
        printf 'ERROR: --max-wait requires a value\n' >&2
        exit 1
      fi
      max_wait="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command docker
require_command curl

if ! docker compose version >/dev/null 2>&1; then
  printf 'ERROR: docker compose plugin is required\n' >&2
  exit 1
fi

env_file="${local_dir}/.env"
example_env_file="${local_dir}/.env.example"

if [[ ! -f "${env_file}" ]]; then
  if [[ -f "${example_env_file}" ]]; then
    cp "${example_env_file}" "${env_file}"
    printf 'Created %s from .env.example\n' "${env_file}"
  else
    printf 'ERROR: missing %s and %s\n' "${env_file}" "${example_env_file}" >&2
    exit 1
  fi
fi

# shellcheck disable=SC1090
set -a && source "${env_file}" && set +a

base_url="${SUPABASE_PUBLIC_URL:-http://127.0.0.1:${SUPABASE_HTTP_PORT:-54321}}"
http_port="${SUPABASE_HTTP_PORT:-54321}"

gateway_ready() {
  local status
  status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 "${base_url}/auth/v1/health" 2>/dev/null || true)"
  [[ -n "${status}" && "${status}" != "000" ]]
}

printf 'Validating clinic-local stack in %s\n' "${local_dir}"
printf 'Gateway URL: %s\n' "${base_url}"

if (( no_start == 0 )); then
  printf 'Starting Docker Compose services...\n'
  (cd "${local_dir}" && docker compose up -d)
else
  printf 'Skipping compose start (--no-start).\n'
fi

printf 'Waiting for gateway readiness (max %ss)...\n' "${max_wait}"
deadline=$((SECONDS + max_wait))
while ! gateway_ready; do
  if (( SECONDS >= deadline )); then
    printf 'ERROR: gateway did not become ready within %ss (%s)\n' "${max_wait}" "${base_url}" >&2
    printf 'Hint: run `cd backend/local && docker compose ps` and inspect service logs.\n' >&2
    exit 1
  fi
  sleep 2
done

printf 'Gateway is responding. Running connectivity smoke checks...\n'
"${smoke_script}"

printf 'Checking container status...\n'
(cd "${local_dir}" && docker compose ps)

if ! (cd "${local_dir}" && docker compose ps --status running | grep -q kong); then
  printf 'ERROR: kong service is not running\n' >&2
  exit 1
fi

printf '\nLocal stack validation passed.\n'
printf '  Gateway : %s\n' "${base_url}"
printf '  Studio  : http://127.0.0.1:%s (default)\n' "${SUPABASE_STUDIO_PORT:-54323}"
printf '  Postgres: 127.0.0.1:%s (host SQL tools / backups)\n' "${SUPABASE_DB_PORT:-54322}"
printf '  Anon key: copy SUPABASE_ANON_KEY from backend/local/.env into deployment-profile.json\n'

if (( teardown == 1 )); then
  printf 'Tearing down stack (--teardown)...\n'
  (cd "${local_dir}" && docker compose down)
fi
