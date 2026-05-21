#!/usr/bin/env bash
# End-to-end: create_staff_account then GoTrue password sign-in for the new staff user.
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
db_port="${SUPABASE_DB_PORT:-54322}"
db_password="${POSTGRES_PASSWORD:-postgres}"
bootstrap_user_id="${BOOTSTRAP_ADMIN_USER_ID:-a0000000-0000-4000-8000-000000000001}"
bootstrap_staff_id="${BOOTSTRAP_ADMIN_STAFF_ID:-b0000000-0000-4000-8000-000000000001}"

test_username="us6-signin-e2e"
test_password="E2eStaffPass1!"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'ERROR: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

require_command curl
require_command python3
require_command psql

printf 'staff_sign_in_after_create: provisioning %s\n' "${test_username}"

PGPASSWORD="${db_password}" psql -h 127.0.0.1 -p "${db_port}" -U postgres -d postgres -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$
DECLARE
  v_result public.rpc_result;
  v_org uuid;
  v_branch uuid;
BEGIN
  SELECT id INTO v_org FROM public.organizations WHERE is_deleted = false LIMIT 1;
  SELECT id INTO v_branch FROM public.branches WHERE is_deleted = false LIMIT 1;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', '${bootstrap_user_id}',
      'role', 'authenticated',
      'staff_member_id', '${bootstrap_staff_id}',
      'staff_role', 'administrator',
      'setup_required', true
    )::text,
    true
  );

  IF v_org IS NULL THEN
    v_result := public.bootstrap_create_organization('Staff Sign-In E2E Org');
    IF NOT v_result.success THEN
      RAISE EXCEPTION 'bootstrap_create_organization failed: %', v_result.error_code;
    END IF;
    v_org := (v_result.data ->> 'organization_id')::uuid;
  END IF;

  IF v_branch IS NULL THEN
    v_result := public.bootstrap_create_branch(v_org, 'Main', '1 St', '+1', 'MAIN', NULL);
    IF NOT v_result.success THEN
      RAISE EXCEPTION 'bootstrap_create_branch failed: %', v_result.error_code;
    END IF;
    v_branch := (v_result.data ->> 'branch_id')::uuid;
  END IF;

  IF v_branch IS NULL THEN
    RAISE EXCEPTION 'no active branch available for staff assignment';
  END IF;

  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.staff_branch_assignments sba
  USING public.staff_members sm
  WHERE sba.staff_member_id = sm.id AND sm.auth_user_id IN (
    SELECT id FROM auth.users WHERE email = '${test_username}'
  );
  DELETE FROM public.staff_members sm
  WHERE sm.auth_user_id IN (SELECT id FROM auth.users WHERE email = '${test_username}');
  DELETE FROM auth.users WHERE email = '${test_username}';

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', '${bootstrap_user_id}',
      'role', 'authenticated',
      'staff_member_id', '${bootstrap_staff_id}',
      'staff_role', 'administrator',
      'organization_id', v_org::text,
      'branch_ids', v_branch::text
    )::text,
    true
  );

  v_result := public.create_staff_account(
    '${test_username}',
    '${test_password}',
    'E2E Receptionist',
    'receptionist',
    ARRAY[v_branch]
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_staff_account failed: % %', v_result.error_code, v_result.error_message;
  END IF;
END \$\$;

DO \$\$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  IF EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE u.email = '${test_username}'
      AND (
        u.confirmation_token IS NULL
        OR u.recovery_token IS NULL
        OR u.email_change IS NULL
        OR u.email_change_token_new IS NULL
      )
  ) THEN
    RAISE EXCEPTION 'provisioned auth.users row still has NULL GoTrue token columns';
  END IF;
END \$\$;
SQL

sign_in_payload="$(python3 -c 'import json,sys; print(json.dumps({"email":sys.argv[1],"password":sys.argv[2]}))' "${test_username}" "${test_password}")"
sign_in_response="$(curl -sS -X POST "${base_url}/auth/v1/token?grant_type=password" \
  -H "apikey: ${anon_key}" \
  -H "Authorization: Bearer ${anon_key}" \
  -H "Content-Type: application/json" \
  -d "${sign_in_payload}")"

SIGN_IN_RESPONSE="${sign_in_response}" python3 -c '
import base64
import json
import os
import sys

payload = json.loads(os.environ["SIGN_IN_RESPONSE"])
token = payload.get("access_token")
if not token:
    print("staff_sign_in_after_create FAILED:", payload, file=sys.stderr)
    sys.exit(1)

parts = token.split(".")
padding = "=" * (-len(parts[1]) % 4)
claims = json.loads(base64.urlsafe_b64decode(parts[1] + padding))

if claims.get("role") != "authenticated":
    print("staff_sign_in_after_create FAILED: JWT role must be authenticated", file=sys.stderr)
    sys.exit(1)
if claims.get("staff_role") != "receptionist":
    print("staff_sign_in_after_create FAILED: expected staff_role=receptionist", file=sys.stderr)
    sys.exit(1)
if not claims.get("staff_member_id"):
    print("staff_sign_in_after_create FAILED: missing staff_member_id", file=sys.stderr)
    sys.exit(1)
if not claims.get("branch_ids"):
    print("staff_sign_in_after_create FAILED: missing branch_ids", file=sys.stderr)
    sys.exit(1)

print("staff_sign_in_after_create: HTTP sign-in succeeded")
print("staff_member_id=%s staff_role=%s" % (claims.get("staff_member_id"), claims.get("staff_role")))
'

printf 'staff_sign_in_after_create: OK\n'
