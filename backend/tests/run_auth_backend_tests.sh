#!/usr/bin/env bash
# Run all auth/RBAC backend verification scripts (Phase 11 full suite).
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

printf '== Auth backend suite: smoke ==\n'
"${script_dir}/auth_flow_smoke.sh"

sql_tests=(
  jwt_claims_contract.sql
  auth_security_extensions.sql
  bootstrap_rpc.sql
  create_staff_rpc.sql
  admin_reset_staff_password.sql
  subscription_cache_nonblocking.sql
  rpc_contract_alignment.sql
  rls_isolation.sql
  auth_rbac_extended.sql
  owner_role_migration.sql
  dev_reset_clinic_installation.sql
)

for f in "${sql_tests[@]}"; do
  printf '== Auth backend suite: %s ==\n' "${f}"
  psql_run -f "${script_dir}/${f}" >/dev/null
done

printf '== Auth backend suite: staff_sign_in_after_create.sh ==\n'
"${script_dir}/staff_sign_in_after_create.sh" >/dev/null

printf 'Auth backend suite: all checks passed.\n'
