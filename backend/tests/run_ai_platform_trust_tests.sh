#!/usr/bin/env bash
# Run B1 installation keystore and AAT issuer verification scripts.
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
  ai_keystore_rls.sql
  ai_token_issuer.sql
  ai_token_contract_rotation.sql
  context_provider_rpc.sql
  ai_acceptance_recording.sql
)

for f in "${sql_tests[@]}"; do
  psql_run -c "DELETE FROM ai_internal.ai_token_issuance;" >/dev/null
  printf '== AI platform trust suite: %s ==\n' "${f}"
  psql_run -f "${script_dir}/${f}" >/dev/null
done

printf 'AI platform trust suite: all checks passed.\n'
