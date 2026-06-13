#!/usr/bin/env bash
# Run V1-5 visit medical records backend verification scripts.
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
  visit_medical_records_crud.sql
  visit_medical_records_rls.sql
  visit_attachment_storage_rls.sql
  patient_visit_attachments_list.sql
)

for f in "${sql_tests[@]}"; do
  printf '== Visit medical records: %s ==\n' "${f}"
  psql_run -f "${script_dir}/${f}"
done

printf 'Visit medical records backend suite: all checks passed.\n'
