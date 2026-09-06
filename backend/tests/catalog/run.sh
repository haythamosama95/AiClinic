#!/usr/bin/env bash
# Run catalog SQL scenario files against local Supabase.
# Does not invoke Worker vitest or the old backend/tests trust suite.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
local_env="${repo_root}/backend/local/.env"

if [[ -f "${local_env}" ]]; then
  # shellcheck disable=SC1090
  set -a && source "${local_env}" && set +a
fi

db_port="${SUPABASE_DB_PORT:-54322}"
db_password="${POSTGRES_PASSWORD:-postgres}"
export PGPASSWORD="${db_password}"

psql_run() {
  psql -h 127.0.0.1 -p "${db_port}" -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

shopt -s nullglob
cd "${script_dir}"

files=()
if [[ -f harness-smoke.sql ]]; then
  files+=(harness-smoke.sql)
fi
files+=(stage-*.sql)

if [[ ${#files[@]} -eq 0 ]]; then
  printf 'catalog SQL harness: no files to run (expected harness-smoke.sql and/or stage-*.sql).\n' >&2
  exit 1
fi

failed=0
passed=0

for f in "${files[@]}"; do
  printf '== catalog SQL: %s ==\n' "${f}"
  if psql_run -f "${script_dir}/${f}"; then
    printf 'PASS  %s\n' "${f}"
    passed=$((passed + 1))
  else
    printf 'FAIL  %s\n' "${f}"
    failed=$((failed + 1))
  fi
done

printf 'catalog SQL harness: %d passed, %d failed.\n' "${passed}" "${failed}"
if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
exit 0
