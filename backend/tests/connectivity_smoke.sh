#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_dir="$(cd "${script_dir}/../local" && pwd)"
env_file="${local_dir}/.env"
fallback_env_file="${local_dir}/.env.example"

if [[ -f "${env_file}" ]]; then
  # shellcheck disable=SC1090
  set -a && source "${env_file}" && set +a
elif [[ -f "${fallback_env_file}" ]]; then
  # shellcheck disable=SC1090
  set -a && source "${fallback_env_file}" && set +a
fi

base_url="${SUPABASE_PUBLIC_URL:-http://127.0.0.1:${SUPABASE_HTTP_PORT:-54321}}"
failures=0

probe_endpoint() {
  local name="$1"
  local url="$2"
  local status

  status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "${url}" || true)"

  if [[ -z "${status}" || "${status}" == "000" ]]; then
    printf 'FAIL  %s -> unreachable (%s)\n' "${name}" "${url}"
    failures=$((failures + 1))
    return
  fi

  case "${status}" in
    2*|3*|401|404)
      printf 'PASS  %s -> HTTP %s (%s)\n' "${name}" "${status}" "${url}"
      ;;
    *)
      printf 'FAIL  %s -> HTTP %s (%s)\n' "${name}" "${status}" "${url}"
      failures=$((failures + 1))
      ;;
  esac
}

printf 'Running clinic-local connectivity smoke checks against %s\n' "${base_url}"

probe_endpoint "auth health" "${base_url}/auth/v1/health"
probe_endpoint "rest gateway" "${base_url}/rest/v1/"
probe_endpoint "storage gateway" "${base_url}/storage/v1/"

if (( failures > 0 )); then
  printf 'Connectivity smoke checks failed: %d endpoint(s) were unavailable.\n' "${failures}"
  exit 1
fi

printf 'Connectivity smoke checks passed.\n'
