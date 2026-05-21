#!/usr/bin/env bash
# Auth flow smoke checks: sign-in (when gateway routes auth), claims, bootstrap RPC guards.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
local_env="${repo_root}/backend/local/.env"
example_env="${repo_root}/backend/local/.env.example"

if [[ -f "${local_env}" ]]; then
  # shellcheck disable=SC1090
  set -a && source "${local_env}" && set +a
elif [[ -f "${example_env}" ]]; then
  # shellcheck disable=SC1090
  set -a && source "${example_env}" && set +a
fi

base_url="${SUPABASE_PUBLIC_URL:-http://127.0.0.1:54321}"
anon_key="${SUPABASE_ANON_KEY:-}"
email="${BOOTSTRAP_ADMIN_EMAIL:-admin@clinic.local}"
password="${BOOTSTRAP_ADMIN_PASSWORD:-ChangeMeOnFirstSignIn!}"
db_port="${SUPABASE_DB_PORT:-54322}"
db_password="${POSTGRES_PASSWORD:-postgres}"
bootstrap_user_id="${BOOTSTRAP_ADMIN_USER_ID:-a0000000-0000-4000-8000-000000000001}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'ERROR: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

require_command curl
require_command python3
require_command psql

http_sign_in() {
  local sign_in_payload sign_in_response access_token
  sign_in_payload="$(python3 -c 'import json,sys; print(json.dumps({"email":sys.argv[1],"password":sys.argv[2]}))' "${email}" "${password}")"
  sign_in_response="$(curl -sS -X POST "${base_url}/auth/v1/token?grant_type=password" \
    -H "apikey: ${anon_key}" \
    -H "Authorization: Bearer ${anon_key}" \
    -H "Content-Type: application/json" \
    -d "${sign_in_payload}" || true)"

  if ! SIGN_IN_RESPONSE="${sign_in_response}" python3 -c '
import json, os
payload = json.loads(os.environ["SIGN_IN_RESPONSE"])
token = payload.get("access_token")
if not token:
    raise SystemExit("no token")
print(token)
' 2>/dev/null; then
    return 1
  fi

  access_token="$(SIGN_IN_RESPONSE="${sign_in_response}" python3 -c '
import json, os
print(json.loads(os.environ["SIGN_IN_RESPONSE"])["access_token"])
')"
  ACCESS_TOKEN="${access_token}" python3 -c '
import base64, json, os
token = os.environ["ACCESS_TOKEN"]
parts = token.split(".")
padding = "=" * (-len(parts[1]) % 4)
payload = json.loads(base64.urlsafe_b64decode(parts[1] + padding))
for key in ("staff_member_id", "staff_role", "setup_required"):
    print(f"{key}={payload.get(key)}")
'
  return 0
}

sql_claims_check() {
  printf 'Auth smoke: verifying get_custom_claims via SQL (auth gateway unavailable)\n'
  PGPASSWORD="${db_password}" psql -h 127.0.0.1 -p "${db_port}" -U postgres -d postgres -Atqc \
    "SELECT public.build_staff_claims('${bootstrap_user_id}'::uuid)::text;" | while read -r line; do
    printf 'claims=%s\n' "${line}"
  done
}

printf 'Auth smoke: signing in as %s\n' "${email}"

if [[ -n "${anon_key}" ]] && http_sign_in; then
  printf 'Auth smoke: HTTP sign-in succeeded\n'
else
  printf 'WARN  auth/v1/token unavailable through gateway; falling back to SQL claims check\n'
  sql_claims_check
fi

printf 'Auth smoke: bootstrap_create_organization guard\n'

PGPASSWORD="${db_password}" psql -h 127.0.0.1 -p "${db_port}" -U postgres -d postgres -Atqc \
  "BEGIN;
   SELECT set_config(
     'request.jwt.claims',
     json_build_object('sub', '${bootstrap_user_id}', 'role', 'authenticated')::text,
     true
   );
   SELECT set_config('role', 'authenticated', true);
   SELECT (public.bootstrap_create_organization('Smoke Org')::public.rpc_result).error_code;" \
  | while read -r code; do
    printf 'bootstrap_create_organization error_code=%s (expect ORG_ALREADY_EXISTS when org exists)\n' "${code}"
  done

printf 'Auth smoke checks completed.\n'
