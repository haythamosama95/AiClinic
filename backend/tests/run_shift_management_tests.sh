#!/usr/bin/env bash
# Run V1-7 shift management backend verification scripts.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
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

sql_tests=(
  shift_management_rls.sql
  shift_management_crud.sql
  shift_management_concurrency.sql
)

for f in "${sql_tests[@]}"; do
  if [[ ! -f "${script_dir}/${f}" ]]; then
    printf '== Shift management: skipping missing %s ==\n' "${f}"
    continue
  fi
  printf '== Shift management: %s ==\n' "${f}"
  psql_run -f "${script_dir}/${f}"
done

printf 'Shift management backend suite: all checks passed.\n'
