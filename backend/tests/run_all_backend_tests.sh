#!/usr/bin/env bash
# Master orchestration: run ALL backend verification suites.
# This script consolidates auth, org/branch, patient, appointment, visit,
# billing, and shift management tests.
# Run: ./backend/tests/run_all_backend_tests.sh
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

total_suites=0
passed_suites=0
failed_suites=()

run_sql_test() {
  local name="$1"
  local file="$2"
  total_suites=$((total_suites + 1))
  printf -- '== [%d] %s ==\n' "${total_suites}" "${name}"
  if psql_run -f "${script_dir}/${file}" >/dev/null 2>&1; then
    passed_suites=$((passed_suites + 1))
    printf -- '   PASS\n'
  else
    failed_suites+=("${name}")
    printf -- '   FAIL\n'
  fi
}

run_shell_test() {
  local name="$1"
  local file="$2"
  total_suites=$((total_suites + 1))
  printf -- '== [%d] %s ==\n' "${total_suites}" "${name}"
  if "${script_dir}/${file}" >/dev/null 2>&1; then
    passed_suites=$((passed_suites + 1))
    printf -- '   PASS\n'
  else
    failed_suites+=("${name}")
    printf -- '   FAIL\n'
  fi
}

printf -- '==========================================================\n'
printf -- ' AiClinic Backend Test Suite\n'
printf -- '==========================================================\n\n'

# --- Auth / RBAC ---
printf -- '--- Auth / RBAC ---\n'
run_shell_test "Auth flow smoke" "auth_flow_smoke.sh"
run_sql_test "JWT claims contract" "jwt_claims_contract.sql"
run_sql_test "Auth security extensions" "auth_security_extensions.sql"
run_sql_test "Bootstrap RPC" "bootstrap_rpc.sql"
run_sql_test "Create staff RPC" "create_staff_rpc.sql"
run_sql_test "Admin reset staff password" "admin_reset_staff_password.sql"
run_sql_test "Subscription cache nonblocking" "subscription_cache_nonblocking.sql"
run_sql_test "RPC contract alignment" "rpc_contract_alignment.sql"
run_sql_test "RLS isolation" "rls_isolation.sql"
run_sql_test "Auth RBAC extended" "auth_rbac_extended.sql"
run_sql_test "Owner role migration" "owner_role_migration.sql"
run_sql_test "Dev reset clinic installation" "dev_reset_clinic_installation.sql"
run_shell_test "Staff sign-in after create" "staff_sign_in_after_create.sh"

# --- Org / Branch Management ---
printf -- '\n--- Org / Branch Management ---\n'
run_sql_test "Org branch management CRUD" "org_branch_management_crud.sql"
run_sql_test "Org branch management RLS" "org_branch_management_rls.sql"
run_sql_test "Org branch management extended" "org_branch_management_extended.sql"
run_sql_test "Role permissions matrix" "role_permissions_matrix.sql"
run_sql_test "Admin update staff username" "admin_update_staff_username.sql"
run_sql_test "Delete staff member" "delete_staff_member.sql"
run_sql_test "Settings code review fixes" "settings_code_review_fixes.sql"

# --- Patient Management ---
printf -- '\n--- Patient Management ---\n'
run_sql_test "Patient management CRUD" "patient_management_crud.sql"
run_sql_test "Patient management RLS" "patient_management_rls.sql"
run_sql_test "Patient management extended" "patient_management_extended.sql"
run_sql_test "Patient management roles" "patient_management_roles.sql"
run_sql_test "Patient management search advanced" "patient_management_search_advanced.sql"
run_sql_test "Patient management search filters" "patient_management_search_filters.sql"
run_sql_test "Patient management concurrent" "patient_management_concurrent.sql"

# --- Appointment Management ---
printf '\n--- Appointment Management ---\n'
run_sql_test "Appointment management CRUD" "appointment_management_crud.sql"
run_sql_test "Appointment management patient filter" "appointment_management_patient_filter.sql"
run_sql_test "Appointment management RLS" "appointment_management_rls.sql"
run_sql_test "Appointment management grants" "appointment_management_grants.sql"

# --- Visit Medical Records ---
printf '\n--- Visit Medical Records ---\n'
run_shell_test "Visit medical records suite" "run_visit_medical_records_tests.sh"

# --- Billing ---
printf '\n--- Billing ---\n'
run_shell_test "Billing suite" "run_billing_tests.sh"

# --- Shift Management ---
printf '\n--- Shift Management ---\n'
run_shell_test "Shift management suite" "run_shift_management_tests.sh"

# --- Safety ---
printf '\n--- Safety ---\n'
run_sql_test "Dev reset safety" "dev_reset_safety.sql"

# --- Summary ---
printf -- '\n==========================================================\n'
printf -- ' Results: %d/%d suites passed\n' "${passed_suites}" "${total_suites}"
printf -- '==========================================================\n'

if (( ${#failed_suites[@]} > 0 )); then
  printf -- '\nFailed suites:\n'
  for name in "${failed_suites[@]}"; do
    printf -- '  - %s\n' "${name}"
  done
  exit 1
fi

printf -- '\nAll backend tests passed.\n'
