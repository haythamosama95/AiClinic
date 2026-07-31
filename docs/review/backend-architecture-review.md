# Backend Architecture Review — Consolidated

**Date:** 2026-07-05
**Scope:** Full `backend/` tree — 154 SQL migrations, 50+ test files, local Docker/Kong stack, CI workflow
**Review passes:** First pass (5 domain syntheses) → Second pass (skeptical re-verification) → Third pass (config/tests, auth/RPC, migrations/RLS, business logic)
**Archived cycle documents:** `docs/review/archive/backend-review-cycles/`

---

## Executive Summary

The AiClinic backend follows a sound architectural pattern: PostgreSQL with `auth_internal` `SECURITY DEFINER` RPCs, thin `public` `SECURITY INVOKER` wrappers, RLS for tenant isolation, and optimistic concurrency via `p_expected_updated_at`. That pattern is consistently applied across auth/RBAC, patients, appointments, visits, billing, shifts, and the service catalog.

Three review passes identified **four critical**, **forty-one high**, **thirteen medium**, and **seven low** severity issues that undermine the RPC-only mutation model and production readiness.

**Highest-risk clusters:**

1. **RLS gaps** on `staff_members`, `organizations`, and `branches` allow PostgREST PATCH to bypass RPC validation guards.
2. **Missing `auth_internal` EXECUTE grants** for billing, shifts, service catalog, pricing, bootstrap, and settings RPCs break the `SECURITY INVOKER` wrapper chain under PostgREST.
3. **LAN-exposed Postgres superuser** with default password bypasses all application security (C-03).
4. **Irreversible `soap_notes` data loss** on migration apply with unreachable backfill dead code (C-04).
5. **Test harness weaknesses** — omitted suites, suppressed `psql` stderr, superuser execution, zero PostgREST coverage for billing/shifts/catalog, CI that only runs Flutter.
6. **JWT/RLS split-brain** — deactivated staff retain read access until token expiry (H-33).
7. **Concurrent double-booking races** in appointments, patients, shifts, and service catalog (H-37–H-40).

| Severity | 1st pass | 2nd pass (new) | 3rd pass (new) | **Total open** |
|----------|----------|----------------|----------------|----------------|
| Critical | 2 | 0 | 2 | **4** |
| High | 19 | 6 | 16 | **41** |
| Medium | 6 | 7 | 0 | **13** |
| Low | 3 | 4 | 0 | **7** |

**Remediation priority:** Lock down RLS UPDATE policies, add all missing `auth_internal` grants (with grant-regression tests), remove Postgres host exposure, fix JWT/key coherence, wire backend tests into CI, and add missing DB constraints.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Flutter Desktop Client (Supabase SDK → PostgREST / GoTrue / Realtime)  │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ JWT (custom claims via get_custom_claims)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Kong (:54321)  →  PostgREST  →  GoTrue  →  Storage API  →  Realtime   │
│  Rate limit: auth (30/min), rest (60/min) — storage/realtime: NONE      │
│  PGRST_DB_PRE_REQUEST: local_dev_pre_request (seed.sql only)            │
│  PostgREST connects as postgres superuser (not authenticator)           │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  public schema (RLS + thin SECURITY INVOKER RPC wrappers)               │
│  auth_internal schema (SECURITY DEFINER business logic + audit)         │
│  storage.objects (visit-attachments bucket policies)                    │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
                    PostgreSQL 15 (Supabase image)
                    Tables: organizations, branches, staff_members,
                    patients, appointments, visits, invoices,
                    services, service_branches, shifts, audit_log
```

**Intended mutation path:** Client calls `public.*` RPC → invoker wrapper delegates to `auth_internal.*` → permission checks (`assert_permission`), branch scoping, audit logging, optimistic concurrency.

**Actual gaps:** Direct table UPDATE via PostgREST permitted on several tables; `auth_internal` EXECUTE missing for newer feature RPCs; local docker-compose mounts only `init.sql` without applying migrations; Postgres published on host with default password.

**Module boundaries:**

| Domain | Mutation path | Known gap |
|--------|---------------|-----------|
| Auth/RBAC | RPC + **leaky RLS on 3 core tables** | C-01, H-01, H-02 |
| Patients | RPC-only UPDATE; **org-wide SELECT** | H-20, H-34, H-37 |
| Appointments | RPC-only mutations | H-39, H-27 (Realtime) |
| Visits / documentation | RPC-only mutations | C-04 (`soap_notes` loss) |
| Billing | RPC-only mutations; **missing grants** | C-02, H-09, H-30, H-41 |
| Service catalog | RPC-only mutations; **missing grants** | C-02, H-22, H-38 |
| Shifts | RPC-only mutations; **missing grants** | H-10, H-40 |

---

## 1. Critical Issues

### C-01 — `staff_members` RLS UPDATE allows role escalation via PostgREST PATCH

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | Critical |
| **Files involved** | `backend/supabase/migrations/20260516100200_auth_rbac_rls.sql`, `backend/supabase/migrations/20260521100000_auth_rbac_supabase_linter_fixes.sql`, `backend/supabase/migrations/20260611170000_restore_last_administrator_guard.sql` |
| **Evidence** | `staff_members_update` at `20260521100000:118-136` permits UPDATE when the target shares any branch in the caller's org. `WITH CHECK` only enforces `is_deleted = false` — no restriction on `role`, `is_bootstrap_admin`, `is_active`, or `auth_user_id`. Guarded RPC `auth_internal.update_staff_member` is bypassed. |
| **Why it's a problem** | Any staff member who can see a colleague via shared branch membership can PATCH `role=administrator` through PostgREST. |
| **Potential impact** | Privilege escalation; last-administrator guard bypass; full tenant compromise. |
| **Recommended solution** | Set `staff_members_update` to `USING (false)`. Add regression test: authenticated PATCH on `staff_members` must fail. |

---

### C-02 — Service catalog `auth_internal` EXECUTE grants missing (PostgREST RPC chain broken)

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd, extended H-22) |
| **Severity** | Critical |
| **Files involved** | `backend/supabase/migrations/20260525120200_fix_restrict_auth_internal_grants.sql`, `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql`, `backend/supabase/migrations/20260712091000_service_catalog_pricing_rpcs.sql`, `backend/supabase/migrations/20260712091500_service_catalog_billing_integration.sql` |
| **Evidence** | Blanket revoke at `20260525120200:4-7`. Service-catalog migrations grant only `auth_internal.staff_has_services_read_access()` and `public.*` wrappers. `public.create_service` is `SECURITY INVOKER` calling `auth_internal.create_service` — no `GRANT EXECUTE ON FUNCTION auth_internal.create_service` exists. Pricing wrappers also lack `auth_internal` grants. |
| **Why it's a problem** | PostgREST runs as `authenticated`; INVOKER wrappers need EXECUTE on underlying definer functions. |
| **Potential impact** | Entire service catalog (CRUD, pricing, billing integration) non-functional via API; SQL tests as `postgres` superuser mask this. |
| **Recommended solution** | One migration granting EXECUTE on every `auth_internal.*` function referenced by a public INVOKER wrapper. Add `service_catalog_grants.sql` regression test modeled on `appointment_management_grants.sql`. |

---

### C-03 — PostgreSQL superuser port published on host with default password

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (config/tests) |
| **Severity** | Critical (Tier 1 LAN clinic deployment) |
| **Files involved** | `backend/local/docker-compose.yml`, `backend/local/.env.example` |
| **Evidence** | Postgres binds `"${SUPABASE_DB_PORT}:5432"` to the host (default `0.0.0.0`). Default `POSTGRES_PASSWORD=postgres`. Tier 1 target is LAN clinic workstations connecting to a server. |
| **Why it's a problem** | Any device on the clinic LAN can connect directly as `postgres` superuser, bypassing Kong, JWT, RLS, and all RPC guards. |
| **Potential impact** | Full database compromise from the LAN; read/modify all PHI; forge staff rows; disable audit. |
| **Recommended solution** | Do not publish Postgres to the host in deployment compose; use internal Docker network only. Require strong generated password; fail compose if `POSTGRES_PASSWORD` is default on non-solo-dev. |

---

### C-04 — `soap_notes` destroyed at migration 28140000; backfill at 11120000 is unreachable dead code

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (migrations/RLS) |
| **Severity** | Critical |
| **Files involved** | `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`, `backend/supabase/migrations/20260711120000_coderabbit_review_fixes.sql` |
| **Evidence** | `20260628140000:67-90` creates `visit_clinical_notes` as replacement for `soap_notes`. `20260628140000:169` executes `DROP TABLE IF EXISTS public.soap_notes` with **no** `INSERT INTO visit_clinical_notes … SELECT FROM soap_notes`. Later, `20260711120000:522-557` wraps backfill in `IF to_regclass('public.soap_notes') IS NOT NULL` — but `soap_notes` was already dropped 11 migrations earlier, so this block never runs on a normal sequential apply. |
| **Why it's a problem** | Any database with existing `soap_notes` clinical documentation loses all subjective/objective/assessment/plan content permanently when `20260628140000` is applied. The later "fix" migration gives false confidence but cannot recover data. |
| **Potential impact** | Irreversible loss of visit clinical documentation on production/staging upgrade; regulatory/clinical record integrity failure. |
| **Recommended solution** | Document one-time manual recovery for already-upgraded DBs. For greenfield paths: squash or reorder so backfill runs **before** first `DROP TABLE soap_notes`. Map `subjective→complaint`, `objective→examination`, `assessment→diagnosis`, `plan→plan`. Add migration test asserting row-count parity when `soap_notes` has seed data. |

---

## 2. High Priority Issues

### H-01 — Organizations direct UPDATE bypasses RPC validation

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260516100200_auth_rbac_rls.sql`, `backend/supabase/migrations/20260522100000_org_branch_management.sql` |
| **Evidence** | `organizations_update` at `20260516100200:154-158` allows any authenticated user in the org to UPDATE any column. Validated path is `auth_internal.update_organization` via `public.update_organization`. |
| **Why it's a problem** | Non-admin staff can PATCH subscription metadata, currency, or settings without `assert_permission` or audit logging. |
| **Potential impact** | Unauthorized settings changes; subscription tier manipulation; audit trail gaps. |
| **Recommended solution** | Set `organizations_update` to `USING (false)`. All mutations via RPC only. Add RLS regression test. |

---

### H-02 — Branches direct UPDATE bypasses RPC validation

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260516100200_auth_rbac_rls.sql`, `backend/supabase/migrations/20260522100000_org_branch_management.sql`, `backend/tests/org_branch_management_extended.sql` |
| **Evidence** | `branches_update` at `20260516100200:178-186` permits UPDATE when `id = ANY(jwt_branch_ids())` with no column restrictions. Tests use direct UPDATE (`org_branch_management_extended.sql:247`). Guarded RPC: `auth_internal.update_branch`. |
| **Why it's a problem** | Staff can modify branch fields without permission checks or field-preservation logic in the RPC. |
| **Potential impact** | Branch deactivation without authorization; bypass of `settings.manage_branches` permission gate. |
| **Recommended solution** | Set `branches_update` to `USING (false)`. Migrate test fixtures to use RPCs. |

---

### H-03 — `add_invoice_item` legacy free-text RPC bypasses service catalog

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260605180500_billing_us1_rpcs.sql`, `backend/supabase/migrations/20260712091500_service_catalog_billing_integration.sql`, `docs/specs/015-service-catalog/plan.md`, `backend/tests/billing_crud.sql` |
| **Evidence** | `public.add_invoice_item` remains granted at `20260605180500:1063`. Plan states old RPC should be retired. `add_invoice_item_from_service` added but legacy path still active. Tests continue using free-text path. |
| **Why it's a problem** | Catalog price resolution, eligibility checks, and snapshot immutability are bypassed. |
| **Potential impact** | Revenue leakage; pricing policy bypass; inconsistent invoice history vs catalog. |
| **Recommended solution** | Revoke `GRANT EXECUTE` on `public.add_invoice_item` or make it return `FORBIDDEN` for new items. Migrate tests. |

---

### H-04 — `build_staff_claims(uuid)` information disclosure to any authenticated user

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260525120200_fix_restrict_auth_internal_grants.sql`, `backend/supabase/migrations/20260611150000_remove_owner_role.sql`, `backend/tests/auth_rbac_extended.sql` |
| **Evidence** | `GRANT EXECUTE ON FUNCTION auth_internal.build_staff_claims(uuid) TO authenticated` at `20260525120200:13`. Test at `auth_rbac_extended.sql:212-241`: any authenticated user can call `auth_internal.build_staff_claims(v_bootstrap_user)` for arbitrary UUIDs. Function is `SECURITY DEFINER`. |
| **Why it's a problem** | Cross-tenant/org staff enumeration: role, branch assignments, organization_id, setup state for any user UUID. |
| **Potential impact** | Information disclosure aiding targeted attacks; privacy violation for staff PII/metadata. |
| **Recommended solution** | Revoke `authenticated` EXECUTE; restrict to `service_role` / `supabase_auth_admin` only. If client needs self-claims, expose `build_staff_claims(auth.uid())` with caller check inside function. |

---

### H-05 — Teardown logic duplicated and prone to drift

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd, extended H-23) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260605260000_delete_clinic_test_fixtures.sql`, `backend/supabase/migrations/20260606180000_shift_management.sql`, `backend/supabase/migrations/20260710130000_fix_delete_clinic_test_fixtures_shifts.sql`, `backend/supabase/migrations/20260712100000_fix_dev_reset_orgs_before_auth_users.sql`, plus 15+ other `dev_reset_*` / teardown patches |
| **Evidence** | `delete_clinic_operational_dependents` defined without shifts, then re-added, then regressed when visit migrations replaced teardown without shift rows. `dev_reset_clinic_installation` independently maintained across many migrations. |
| **Why it's a problem** | Each new feature adds tables but teardown is copy-pasted into multiple functions. Historical regression already occurred for shifts. |
| **Potential impact** | `dev_reset` FK failures; test pollution; orphaned rows; false test passes. |
| **Recommended solution** | Single authoritative teardown function; feature migrations append to a registry table list rather than redefining the whole function. Add teardown parity test. |

---

### H-06 — Missing `ON DELETE CASCADE` on core FK relationships

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260516100000_auth_rbac_schema.sql`, `backend/supabase/migrations/20260523140000_patient_management.sql`, `backend/supabase/migrations/20260605180000_billing.sql`, `backend/supabase/migrations/20260712090000_service_catalog.sql` |
| **Evidence** | `branches.organization_id`, `patients.branch_id`, `invoices` FKs, `services.organization_id` — no `ON DELETE CASCADE`. Only `subscription_cache` uses CASCADE. |
| **Why it's a problem** | Deletes require manual ordering in teardown functions. Any missed table blocks org/branch removal. |
| **Potential impact** | `dev_reset` failures; orphaned data; complex manual DELETE chains. |
| **Recommended solution** | Evaluate `ON DELETE CASCADE` or `ON DELETE RESTRICT` with clear semantics per relationship. |

---

### H-07 — No DB constraint linking `patients.branch_id` to `patients.organization_id`

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260523140000_patient_management.sql` |
| **Evidence** | `patients` table: `branch_id` and `organization_id` are independent FKs. Consistency enforced only in RPC runtime checks. No `CHECK` or composite FK. |
| **Why it's a problem** | Superuser, migration scripts, or future RLS gaps can insert patients with branch from org A and organization_id from org B. |
| **Potential impact** | Cross-tenant data corruption; RLS bypass for patient records. |
| **Recommended solution** | Add trigger or composite FK: `organization_id` must equal `(SELECT organization_id FROM branches WHERE id = branch_id)`. |

---

### H-08 — `service_branches` allows cross-organization assignment at DB level

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260712090000_service_catalog.sql` |
| **Evidence** | `service_branches`: `service_id` and `branch_id` FKs — no constraint that `services.organization_id = branches.organization_id`. RPCs enforce at runtime; RLS blocks direct DML. |
| **Why it's a problem** | `SECURITY DEFINER` bugs or superuser paths can link services to foreign-org branches. |
| **Potential impact** | Cross-org pricing leakage; invoices resolved against wrong branch config. |
| **Recommended solution** | Add composite constraint via trigger validating org alignment. |

---

### H-09 — Billing `auth_internal` EXECUTE grants missing

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260525120200_fix_restrict_auth_internal_grants.sql`, `backend/supabase/migrations/20260605180400_grant_billing_rls_helpers.sql`, `backend/supabase/migrations/20260605180500_billing_us1_rpcs.sql` |
| **Evidence** | Only RLS helpers granted. `public.add_invoice_item` is `SECURITY INVOKER` calling `auth_internal.add_invoice_item` — no matching `GRANT EXECUTE` to `authenticated`. |
| **Why it's a problem** | Same INVOKER grant gap as service catalog. Billing RPCs fail under PostgREST. |
| **Potential impact** | Invoice creation, payments, voiding non-functional via API. |
| **Recommended solution** | Grant EXECUTE on all `auth_internal` billing functions referenced by public wrappers. Add `billing_grants.sql` regression test. |

---

### H-10 — Shift management `auth_internal` EXECUTE grants missing

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260606180000_shift_management.sql` |
| **Evidence** | Only `auth_internal.staff_has_shifts_manage()` granted. `public.create_shift` is `SECURITY INVOKER` calling `auth_internal.create_shift` — no grant on underlying definer function. |
| **Why it's a problem** | Shift RPCs fail under PostgREST for real users. |
| **Potential impact** | Shift scheduling feature broken in production path. |
| **Recommended solution** | Grant EXECUTE on `auth_internal.create_shift`, `update_shift`, `cancel_shift`, `list_shifts`, `get_shift_detail`, `modify_shift_assignments` to `authenticated`. Add grant regression test. |

---

### H-11 — `run_all_backend_tests.sh` omits appointment QA suites

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/tests/run_all_backend_tests.sh`, `backend/tests/appointment_queue_qa.sql`, `backend/tests/appointment_calendar_backend_integrity.sql` |
| **Evidence** | Master runner lists four appointment tests; neither `appointment_queue_qa.sql` nor `appointment_calendar_backend_integrity.sql` is included. |
| **Why it's a problem** | Queue ordering and calendar integrity regressions ship undetected when running the "all tests" script. |
| **Potential impact** | Production appointment queue bugs; calendar view data inconsistencies. |
| **Recommended solution** | Add both files to `run_all_backend_tests.sh`. Document any intentional deferral in `README_DEFERRED_TESTS.md`. |

---

### H-12 — Test runner suppresses `psql` error output

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/tests/run_all_backend_tests.sh` |
| **Evidence** | `run_sql_test` at lines 34 and 48: `psql_run -f ... >/dev/null 2>&1` discards stdout and stderr on both pass and fail paths. |
| **Why it's a problem** | Failures surface only as `FAIL` with no SQL error, assertion message, or line number. |
| **Potential impact** | Extended debug time; CI/local developers cannot diagnose failures from runner output. |
| **Recommended solution** | On failure, re-run with stderr visible or tee output to a log file. Print last 50 lines on failure. |

---

### H-13 — SQL tests run as `postgres` superuser (bypasses EXECUTE and RLS)

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd, extended H-30) |
| **Severity** | High |
| **Files involved** | `backend/tests/run_all_backend_tests.sh`, `backend/tests/appointment_management_grants.sql`, most `backend/tests/*.sql` |
| **Evidence** | Runner uses `-U postgres`. Grant test explicitly notes superuser bypasses EXECUTE checks. Tests routinely `PERFORM set_config('role', 'postgres', true)` for fixture setup. |
| **Why it's a problem** | Grant regressions and RLS holes are invisible to the majority of tests. Explains why missing `auth_internal` grants were not caught. |
| **Potential impact** | False confidence; production-only failures. |
| **Recommended solution** | Split fixture setup (superuser) from assertion blocks (authenticated role). Default test execution as `authenticated` with JWT simulation. |

---

### H-14 — COMMIT/ROLLBACK pollution across test files

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | Multiple files under `backend/tests/` |
| **Evidence** | Mixed transaction endings across 50+ test files. COMMIT-ending tests leave persisted state; ROLLBACK-ending tests do not. |
| **Why it's a problem** | When tests are composed or run in sequence without isolation, committed data from one file affects subsequent files. |
| **Potential impact** | Order-dependent test failures; flaky CI; difficult parallelization. |
| **Recommended solution** | Standardize on `ROLLBACK` for all SQL tests, or run each file in a dedicated database transaction from the runner. |

---

### H-15 — "Concurrency" tests are sequential, not concurrent

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd; underlying races documented as H-39, H-40) |
| **Severity** | High |
| **Files involved** | `backend/tests/billing_concurrency.sql`, `backend/tests/shift_management_concurrency.sql`, `backend/tests/service_catalog_concurrency.sql`, `backend/tests/patient_management_concurrent.sql` |
| **Evidence** | `billing_concurrency.sql` executes `record_payment` calls sequentially in one transaction. `shift_management_concurrency.sql` tests stale `updated_at` rejection, not parallel sessions. |
| **Why it's a problem** | True race conditions (double invoice issue, duplicate payment, double-booking) are not exercised. |
| **Potential impact** | Production race bugs under concurrent receptionists/doctors. |
| **Recommended solution** | Use `pg_background` extension, multiple psql sessions, or dedicated race test harness with explicit locking verification. |

---

### H-16 — GoTrue HTTP sign-in soft-fails in smoke tests

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd; root cause also H-26) |
| **Severity** | High |
| **Files involved** | `backend/tests/auth_flow_smoke.sh` |
| **Evidence** | Lines 94-98: if HTTP sign-in fails, prints WARN and continues. Script exits 0 after SQL fallback. |
| **Why it's a problem** | Broken Kong routing, GoTrue misconfiguration, or hook failures are masked. |
| **Potential impact** | Auth stack regressions undetected until manual testing. |
| **Recommended solution** | Make HTTP sign-in mandatory when `REQUIRE_GOTRUE=1` (CI). Keep SQL fallback only for explicit offline mode. |

---

### H-17 — CI runs only Flutter; no backend test job

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `.github/workflows/ci.yml` |
| **Evidence** | Workflow defines single job `frontend-quality`: `flutter analyze`, `flutter test`, `flutter build windows`. No backend test step. |
| **Why it's a problem** | All SQL regression tests, grant checks, and RLS verifications are manual-only. |
| **Potential impact** | Backend regressions merge to main undetected. |
| **Recommended solution** | Add `backend-quality` job: docker-compose up, apply migrations, run `run_all_backend_tests.sh` and `validate_local_stack.sh`. |

---

### H-18 — Docker Compose does not apply migrations on startup

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High |
| **Files involved** | `backend/local/docker-compose.yml`, `backend/local/init.sql` |
| **Evidence** | Postgres volume mount mounts only `./init.sql`. No migration runner service or volume for `backend/supabase/migrations/`. |
| **Why it's a problem** | Fresh `docker compose up` yields empty schema except roles. Developers must manually apply 150+ migrations. |
| **Potential impact** | Onboarding friction; drift from production. |
| **Recommended solution** | Add migrate service that runs on postgres healthy. Document in backend README. |

---

### H-19 — Open signup enabled in local auth configuration

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Severity** | High (for any shared/staging deployment) |
| **Files involved** | `backend/local/docker-compose.yml` |
| **Evidence** | `GOTRUE_DISABLE_SIGNUP: "false"` at line 35. |
| **Why it's a problem** | Staff accounts are intended to be provisioned via `create_staff_account` RPC by administrators. Open signup allows arbitrary `auth.users` creation. |
| **Potential impact** | Unauthorized accounts on shared dev/staging. |
| **Recommended solution** | Set `GOTRUE_DISABLE_SIGNUP: "true"` for all non-local-solo environments. |

---

### H-20 — Patients readable org-wide via RLS and `get_patient`; no branch isolation *(2nd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260523140000_patient_management.sql`, `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql` |
| **Evidence** | `patients_select` RLS filters only `organization_id = jwt_organization_id()` — **no** `branch_id` check. `auth_internal.assert_org_patient` validates org membership only. `get_patient` uses `assert_org_patient`. Encounter workspace uses `assert_patient_branch_scope` with `staff_can_access_branch`. |
| **Why it's a problem** | In multi-branch clinics, any staff with `patients.view` can read patients registered at branches they are not assigned to. |
| **Potential impact** | Cross-branch PII disclosure; regulatory/privacy violation for segregated branches. |
| **Recommended solution** | Add branch predicate to `patients_select`. Update `assert_org_patient` / `get_patient` to enforce branch scope. Add RLS regression test. |

---

### H-21 — `create_staff_account` branch validation not scoped to caller organization *(2nd pass — REMEDIATED)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd |
| **Status** | **Remediated** in `20260614100000_settings_code_review_fixes.sql:216-226` (`v_org_id := public.jwt_organization_id()` guard) |
| **Severity** | High (was) |
| **Files involved** | `backend/supabase/migrations/20260613150000_create_staff_account_phone.sql`, `backend/supabase/migrations/20260611170000_restore_last_administrator_guard.sql` |
| **Evidence** | Original `create_staff_account` validated branches exist in **any** non-deleted organization. `update_staff_member` explicitly rejected cross-org branches. |
| **Why it was a problem** | Asymmetric validation could assign foreign-org branches in shared DB scenarios. |
| **Recommended solution** | *(Applied)* Align create with update: require `b.organization_id = public.jwt_organization_id()` for every `p_branch_ids` entry. |

---

### H-22 — Service catalog **pricing** RPCs missing `auth_internal` grants *(2nd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd (extends C-02) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260712091000_service_catalog_pricing_rpcs.sql` |
| **Evidence** | INVOKER wrappers call `auth_internal.get_service`, `resolve_effective_service_price_rpc`, `search_eligible_services`, `list_services`. Grants section grants **only** `public.*` functions. No `GRANT EXECUTE ON FUNCTION auth_internal.*`. |
| **Why it's a problem** | Invoice service selector and price preview fail under PostgREST even if CRUD RPCs are fixed later. |
| **Potential impact** | Billing catalog integration broken end-to-end in production path. |
| **Recommended solution** | Include pricing `auth_internal` functions in the grant migration and grant regression test. |

---

### H-23 — July 2026 teardown churn: repeated `delete_clinic_operational_dependents` replacements *(2nd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd (extends H-05) |
| **Severity** | High |
| **Files involved** | `20260702120000_remove_coded_diagnosis.sql`, `20260705120000_remove_structured_plan_outputs.sql`, `20260706120000_dev_reset_delete_patient_health_records.sql`, `20260710130000_fix_delete_clinic_test_fixtures_shifts.sql`, `20260712100000_fix_dev_reset_orgs_before_auth_users.sql` |
| **Evidence** | `delete_clinic_operational_dependents` fully replaced at least **5 times** in 10 days. Comment at `20260710130000:1-2` documents shift regression. |
| **Why it's a problem** | Each feature/revert migration copy-pastes teardown; order drifts. |
| **Potential impact** | FK failures during dev_reset; orphaned rows; false test passes. |
| **Recommended solution** | Single teardown registry function; CI check that all FK child tables appear in teardown. |

---

### H-24 — `assert_patient_branch_scope` granted directly to `authenticated` *(2nd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql` |
| **Evidence** | `GRANT EXECUTE ON FUNCTION auth_internal.assert_patient_branch_scope(uuid) TO authenticated` at line 2035. Function is `SECURITY DEFINER` returning full `patients` row. |
| **Why it's a problem** | Exposes internal definer helper on `auth_internal` schema to clients; violates grant-restriction pattern. |
| **Potential impact** | Expanded attack surface; inconsistent with other revoked internal helpers. |
| **Recommended solution** | Revoke `authenticated` EXECUTE; keep scope checks inside public RPCs only. |

---

### H-25 — `dev_seed_*` and `public.dev_seed_*` remain granted to `authenticated` *(2nd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd (extends M-04) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260628200000_dev_seed_medications_catalog.sql`, `backend/supabase/migrations/20260628210000_dev_seed_investigations_catalog.sql`, `backend/supabase/migrations/20260711120000_coderabbit_review_fixes.sql` |
| **Evidence** | Grants remain after coderabbit fail-closed body updates. Any authenticated bootstrap admin can invoke when `app.environment` is set. |
| **Why it's a problem** | Catalog pollution / DoS via bulk inserts; relies on environment string + bootstrap check, not role isolation. |
| **Potential impact** | Unauthorized catalog mutation on shared dev/staging if pre-request runs. |
| **Recommended solution** | Revoke `authenticated` grants; restrict to `postgres` / `service_role` or drop public wrappers entirely. |

---

### H-26 — JWT secret and API keys incoherent in committed `.env.example` *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (config/tests) |
| **Severity** | High |
| **Files involved** | `backend/local/.env.example`, `frontend/config/local/deployment-profile.json`, `docs/implementation/spec001/backend-implementation.md` |
| **Evidence** | `.env.example` sets custom `SUPABASE_JWT_SECRET` but ships standard Supabase **demo** `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` signed for a different secret. `validate_local_stack.sh:87-90` auto-copies `.env.example` → `.env`. |
| **Why it's a problem** | Fresh compose setup produces invalid JWTs. HTTP auth/REST/Storage fail; SQL tests still pass as `postgres` superuser. |
| **Potential impact** | Flutter client cannot authenticate; false green backend test runs; onboarding broken. |
| **Recommended solution** | Regenerate anon/service keys signed with the committed JWT secret, or revert JWT secret to match demo keys. Add sign-in smoke validation to `validate_local_stack.sh`. |

---

### H-27 — Appointment Realtime never configured in migrations *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (config/tests) |
| **Severity** | High |
| **Files involved** | `backend/local/docker-compose.yml`, `frontend/lib/features/appointments/data/appointment_queue_realtime.dart`, all `backend/supabase/migrations/*.sql` |
| **Evidence** | Flutter subscribes to `public.appointments` postgres changes. Repository-wide grep: **zero** `ALTER PUBLICATION`, `supabase_realtime`, or `REPLICA IDENTITY` in migrations. |
| **Why it's a problem** | Self-hosted compose path likely never broadcasts appointment changes; queue stays stale unless manually refreshed. |
| **Potential impact** | Live queue feature non-functional on deployment stack. |
| **Recommended solution** | Migration: `ALTER PUBLICATION supabase_realtime ADD TABLE public.appointments`; set `REPLICA IDENTITY FULL`; add websocket integration test in CI. |

---

### H-28 — PostgREST connects as `postgres` superuser, not `authenticator` *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (config/tests) |
| **Severity** | High |
| **Files involved** | `backend/local/docker-compose.yml`, `backend/local/init.sql` |
| **Evidence** | `PGRST_DB_URI: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres`. `init.sql` creates `anon`/`authenticated`/`service_role` but **not** `authenticator`. No `FORCE ROW LEVEL SECURITY` in any migration. |
| **Why it's a problem** | Violates Supabase least-privilege model. API layer DB connection is superuser-capable. |
| **Potential impact** | PostgREST misconfiguration or future CVE could expose superuser access. |
| **Recommended solution** | Use `authenticator` role in `PGRST_DB_URI`; grant `authenticated`/`anon` membership. |

---

### H-29 — Compose hardcodes `PGRST_DB_PRE_REQUEST` without applying `seed.sql` *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (config/tests; elevates M-06) |
| **Severity** | High |
| **Files involved** | `backend/local/docker-compose.yml`, `backend/supabase/seed.sql` |
| **Evidence** | Compose sets `PGRST_DB_PRE_REQUEST: public.local_dev_pre_request`. Function defined only in `seed.sql:7-14`. Compose mounts only `init.sql`; no seed step. |
| **Why it's a problem** | Migrations-only compose bring-up leaves pre-request function missing → PostgREST errors on **every** request. |
| **Potential impact** | Total REST/RPC API outage on compose stack until seed manually applied. |
| **Recommended solution** | Move `local_dev_pre_request` into a guarded migration, or remove `PGRST_DB_PRE_REQUEST` from compose until seed runs; add REST smoke test. |

---

### H-30 — Billing, shifts, and service catalog have zero PostgREST HTTP test coverage *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (config/tests; extends H-13/L-01) |
| **Severity** | High |
| **Files involved** | `backend/tests/run_billing_tests.sh`, `run_shift_management_tests.sh`, `run_service_catalog_tests.sh`, `frontend/test/boundary/` |
| **Evidence** | All three sub-runners use `psql -U postgres` only. Flutter boundary suite covers auth/patients/appointments/settings; **no** billing/shift/catalog boundary tests. |
| **Why it's a problem** | INVOKER grant chain failures are the highest-risk production bug class; 3 of 4 major feature domains have no PostgREST-path verification. |
| **Potential impact** | Billing, shifts, and catalog ship broken via API while SQL superuser tests stay green. |
| **Recommended solution** | Add `*_grants.sql` per domain; add boundary or curl-based RPC smoke per feature; wire into CI. |

---

### H-31 — `bootstrap_finish_setup` `auth_internal` EXECUTE grant signature drift *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (auth/RPC) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260611140000_allow_admin_create_owner_and_atomic_bootstrap_setup.sql`, `backend/supabase/migrations/20260613120000_bootstrap_finish_setup_working_schedule.sql`, `backend/supabase/migrations/20260613150000_create_staff_account_phone.sql` |
| **Evidence** | Only `auth_internal` grant is on **11-parameter** signature. `20260613120000` adds `p_branch_working_schedule jsonb` (12th param) — a new function identity. Re-grants **public** 12-param wrapper only; no matching `auth_internal` re-grant. Public wrapper is `SECURITY INVOKER`. |
| **Why it's a problem** | PostgREST runs as `authenticated`. INVOKER wrapper requires `EXECUTE` on the **current** `auth_internal` function signature. |
| **Potential impact** | Atomic clinic bootstrap (`bootstrap_finish_setup`) fails under PostgREST for all callers. |
| **Recommended solution** | Add migration: `GRANT EXECUTE ON FUNCTION auth_internal.bootstrap_finish_setup(..., jsonb) TO authenticated;` Add grant regression test. |

---

### H-32 — `admin_update_staff_username` missing `auth_internal` EXECUTE grant *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (auth/RPC) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260613200000_admin_update_staff_username.sql`, `backend/supabase/migrations/20260614000000_fix_admin_update_staff_username_forbidden.sql` |
| **Evidence** | `public.admin_update_staff_username` is `SECURITY INVOKER`. Only grant: `GRANT EXECUTE ON FUNCTION public.admin_update_staff_username(uuid, text) TO authenticated`. Zero `GRANT EXECUTE ON FUNCTION auth_internal.admin_update_staff_username`. |
| **Why it's a problem** | Same INVOKER grant-gap class as H-09/H-10/C-02. |
| **Potential impact** | Staff username changes non-functional via API. |
| **Recommended solution** | `GRANT EXECUTE ON FUNCTION auth_internal.admin_update_staff_username(uuid, text) TO authenticated;` |

---

### H-33 — JWT-stale authorization: RLS and `staff_can_access_branch` trust claims over live staff state *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (auth/RPC) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260528133000_fix_staff_branch_assignments_rls_recursion.sql`, `backend/supabase/migrations/20260611150000_remove_owner_role.sql`, `backend/supabase/migrations/20260523140000_patient_management.sql`, `backend/local/docker-compose.yml` |
| **Evidence** | `staff_branch_assignments_select` grants org-wide visibility when `public.jwt_staff_role() IN ('owner', 'administrator')`. `staff_can_access_branch` grants administrators org-wide access via JWT. RPC `assert_permission` reads live `staff_members`. RLS `patients_select` has no caller `is_active` check. JWT lifetime: 3600s. |
| **Why it's a problem** | Authorization is **split-brain**: RPC mutations use live DB state; RLS SELECT uses JWT claims that can lag up to 1 hour after deactivation or role demotion. |
| **Potential impact** | Deactivated staff with unexpired JWT retain PostgREST read access. Demoted administrators retain org-wide branch visibility until re-login. |
| **Recommended solution** | Add `auth_internal.current_staff_is_active()` / `current_staff_role()` reading live `staff_members`; use in RLS and `staff_can_access_branch`. Optionally shorten JWT TTL or force session invalidation on deactivation. |

---

### H-34 — `transfer_patient` allows cross-branch transfer without caller branch-access validation *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (migrations/RLS) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260524110200_fix_patient_transfer_restore.sql` |
| **Evidence** | Source patient resolved via `assert_org_patient` only — org scope, no branch check. Target branch validated for same-org but **not** `staff_can_access_branch(p_new_branch_id)`. Encounter RPCs use `assert_patient_branch_scope` — asymmetric. |
| **Why it's a problem** | Staff with `patients.edit` at branch A can transfer any org patient (including from branch B) to any active org branch. |
| **Potential impact** | Unauthorized cross-branch patient relocation; branch segregation policy bypass. |
| **Recommended solution** | Before UPDATE: `PERFORM auth_internal.assert_patient_branch_scope(p_patient_id)`. Require `staff_can_access_branch(p_new_branch_id)` on target. Add regression test. |

---

### H-35 — `invoice_items.service_id` lacks DB constraint aligning service org with invoice org *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (migrations/RLS) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260712091500_service_catalog_billing_integration.sql`, `backend/supabase/migrations/20260605180000_billing.sql` |
| **Evidence** | Adds `invoice_items.service_id uuid REFERENCES public.services (id)` — no CHECK/trigger that `services.organization_id = invoices.organization_id`. RPC validates at runtime. Legacy `add_invoice_item` path can insert rows without `service_id`. |
| **Why it's a problem** | Integrity depends entirely on RPC code. Superuser paths can attach foreign-org `service_id` to an invoice item. |
| **Potential impact** | Cross-org service references on invoice line items; incorrect pricing snapshots. |
| **Recommended solution** | Add trigger `BEFORE INSERT OR UPDATE ON invoice_items` validating org alignment. Add negative test. |

---

### H-36 — `invoices` and `shifts` store independent `organization_id` + `branch_id` with no alignment constraint *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (migrations/RLS) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260605180000_billing.sql`, `backend/supabase/migrations/20260606180000_shift_management.sql` |
| **Evidence** | `invoices` and `shifts`: `organization_id` and `branch_id` are separate FKs with no CHECK that `branch.organization_id` matches. Same gap as H-07 for `patients`. |
| **Why it's a problem** | Misaligned rows can be inserted via superuser or migration scripts. |
| **Potential impact** | Cross-tenant data corruption; billing reports scoped wrong. |
| **Recommended solution** | Add composite CHECK or trigger: `organization_id = (SELECT organization_id FROM branches WHERE id = branch_id)`. |

---

### H-37 — `update_patient` stale check is non-atomic; concurrent edits silently overwrite *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (business logic) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260523140000_patient_management.sql` |
| **Evidence** | `assert_org_patient` is `STABLE` with no row lock. Stale check compares `updated_at` to `p_expected_updated_at`. `UPDATE` has **no** `FOR UPDATE` beforehand and **no** `WHERE updated_at = p_expected_updated_at` on the update itself. |
| **Why it's a problem** | Two receptionists editing the same patient with the same loaded `updated_at` both pass `STALE_PATIENT`, then last-write-wins. |
| **Potential impact** | Patient PII corruption; duplicate national IDs if uniqueness check passes on stale snapshot. |
| **Recommended solution** | `SELECT … FOR UPDATE` before validation, or atomic `UPDATE … WHERE id = $1 AND updated_at = $2` with `GET DIAGNOSTICS` → `STALE_PATIENT` when `ROW_COUNT = 0`. |

---

### H-38 — Service catalog branch config/promotion RPCs have racy optimistic concurrency *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (business logic) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql` |
| **Evidence** | `configure_service_branch` reads `service_branches` without `FOR UPDATE`, stale check, then `UPDATE` with no `WHERE updated_at = p_expected_updated_at`. Same pattern in `set_service_promotion`. Contrast `update_service` which **does** use `FOR UPDATE`. |
| **Why it's a problem** | Concurrent administrators editing branch pricing/promotions can pass stale checks on the same timestamp and overwrite each other. |
| **Potential impact** | Wrong prices on invoices; promo dates corrupted; billing disputes. |
| **Recommended solution** | `SELECT … FOR UPDATE` on `service_branches` before stale validation, or conditional `UPDATE … WHERE updated_at = p_expected_updated_at`. |

---

### H-39 — Appointment scheduling overlap checks are check-then-act without exclusion constraints *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (business logic) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260628160000_simplified_slot_booking.sql`, `backend/supabase/migrations/20260604130000_fix_create_appointment_exception_handlers.sql`, `backend/supabase/migrations/20260618140000_update_appointment.sql` |
| **Evidence** | `appointment_has_overlap` is `STABLE`, returns `false` when `p_doctor_id IS NULL`, and performs a non-locking `EXISTS`. `create_appointment` checks overlap then inserts with no `FOR UPDATE`. No GiST/exclusion constraint on doctor time ranges. |
| **Why it's a problem** | Two concurrent `create_appointment` / `reschedule_appointment` calls for the same doctor and slot can both pass overlap check and both commit. |
| **Potential impact** | Double-booked doctors; two patients for one slot; queue/calendar corruption. |
| **Recommended solution** | Add PostgreSQL exclusion constraint using `tstzrange` + `btree_gist`, or `SELECT … FOR UPDATE` on overlapping appointment rows inside the RPC. |

---

### H-40 — Shift staff overlap validation is check-then-act without row locks *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (business logic) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260606180000_shift_management.sql`, `backend/supabase/migrations/20260607120000_shift_medium_severity_fixes.sql` |
| **Evidence** | `assert_no_staff_shift_overlap` queries overlapping shifts without locking them. `create_shift` calls it then `INSERT`. No exclusion constraint on shift time ranges per staff member. |
| **Why it's a problem** | Concurrent `create_shift` / `modify_shift_assignments` for the same staff and overlapping window can both pass the assertion and commit. |
| **Potential impact** | Staff scheduled in two places at once; payroll/scheduling errors. |
| **Recommended solution** | Lock conflicting `shifts`/`shift_assignments` rows with `FOR UPDATE`, or add exclusion constraint on staff shift time ranges where `deleted_at IS NULL`. |

---

### H-41 — `void_invoice` allows voiding partially-paid invoices without refund enforcement *(3rd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 3rd (business logic) |
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260605310000_fix_billing_review_items_18_21_24.sql`, `backend/supabase/migrations/20260605181000_billing_us2_payment_rpcs.sql`, `backend/tests/billing_crud.sql` |
| **Evidence** | `void_invoice` permits `status IN ('issued', 'partially_paid')`. No check that `sum(payments.amount) = 0` or mandatory `record_refund` before void. `UPDATE` sets `status = 'voided'` but **does not** reverse existing payment rows. Test `void_partially_paid_invoice_succeeds` expects this behavior. |
| **Why it's a problem** | Staff with `invoices.void` can collect partial cash, void the invoice, and leave positive payment rows attached to a voided invoice. Error text blocks only **fully** `paid` status. |
| **Potential impact** | Revenue reconciliation gaps; cash handling without audit trail; potential internal fraud vector. |
| **Recommended solution** | Require `compute_invoice_balance = 0` OR auto-insert offsetting refund payments on void; alternatively block void when `sum(payments.amount) > 0`. |

---

## 3. Medium Priority Issues

### M-01 — Invoice `currency` defaults to `USD` instead of organization `currency_code`

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Files involved** | `backend/supabase/migrations/20260605180000_billing.sql`, `backend/supabase/migrations/20260516100000_auth_rbac_schema.sql`, `backend/supabase/migrations/20260605180500_billing_us1_rpcs.sql` |
| **Evidence** | `invoices.currency text NOT NULL DEFAULT 'USD'`. `create_invoice_from_visit` INSERT omits `currency` column, inheriting USD default. |
| **Recommended solution** | Default invoice currency from `organizations.currency_code` at creation time. Add test asserting currency parity. |

---

### M-02 — `create_invoice_from_visit` TOCTOU race (duplicate active invoices)

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd; partially mitigated by `invoices_visit_active_unique` index) |
| **Files involved** | `backend/supabase/migrations/20260605180500_billing_us1_rpcs.sql`, `backend/supabase/migrations/20260605180000_billing.sql` |
| **Evidence** | Existence check followed by INSERT — not atomic in RPC. Partial unique index `invoices_visit_active_unique` exists at `20260605180000:108-110` but RPC lacks `unique_violation` handler. |
| **Recommended solution** | Map `unique_violation` → `ACTIVE_INVOICE_EXISTS` in RPC; call `assert_one_active_invoice_per_visit` or remove dead helper (M-12). |

---

### M-03 — Shifts use `deleted_at` soft-delete; rest of schema uses `is_deleted`

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Files involved** | `backend/supabase/migrations/20260606180000_shift_management.sql` |
| **Evidence** | `shifts` table has `deleted_at`/`deleted_by` but no `is_deleted` column. Rest of platform uses `is_deleted boolean` pattern. |
| **Recommended solution** | Align shifts with `is_deleted` pattern or document explicit exception. |

---

### M-04 — `dev_seed_*` functions have weaker environment guard than `dev_reset`

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd; grants elevated to H-25) |
| **Files involved** | `backend/supabase/migrations/20260628200000_dev_seed_medications_catalog.sql`, `backend/supabase/migrations/20260525120500_fix_dev_reset_environment_guard.sql` |
| **Evidence** | Blocks only when `app.environment IS NOT NULL AND NOT IN (...)`. If setting is unset (production default), guard passes. |
| **Recommended solution** | Fail closed: require `app.environment IN ('development','local','test')` rather than allowing when unset. |

---

### M-05 — `cleanup_audit_log` return type mismatch (`jsonb` vs `rpc_result`)

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd) |
| **Files involved** | `backend/supabase/migrations/20260524110300_fix_audit_log_retention.sql`, `backend/supabase/migrations/20260524150000_fix_audit_log_timestamp_column.sql` |
| **Evidence** | Function declared `RETURNS jsonb` but body returns `public.rpc_success(...)` / `public.rpc_error(...)` which are `rpc_result` composite type. |
| **Recommended solution** | Change return type to `public.rpc_result` or return explicit `to_jsonb(rpc_success(...))`. |

---

### M-06 — `PGRST_DB_PRE_REQUEST` depends on `seed.sql` (not migrations)

| Field | Detail |
|-------|--------|
| **Pass** | 1st (confirmed 2nd; impact elevated to H-29) |
| **Files involved** | `backend/local/docker-compose.yml`, `backend/supabase/seed.sql`, `backend/supabase/config.toml` |
| **Evidence** | PostgREST configured with `PGRST_DB_PRE_REQUEST: public.local_dev_pre_request`. Function defined only in `seed.sql:7-14`, not in any migration. Docker compose does not run seed.sql. |
| **Recommended solution** | Move `local_dev_pre_request` to a migration (guarded as local-only) or add seed step to compose startup. |

---

### M-07 — Kong rate limiting absent on storage and realtime routes *(2nd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd |
| **Files involved** | `backend/local/kong.yml` |
| **Evidence** | `auth` and `rest` have `rate-limiting` plugins. `storage` and `realtime` have **no** plugins. |
| **Recommended solution** | Add rate-limiting plugins to storage and realtime; tune limits for LAN profile. |

---

### M-08 — `audit_log` readable org-wide by all authenticated staff *(2nd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd |
| **Files involved** | `backend/supabase/migrations/20260516100200_auth_rbac_rls.sql`, `backend/supabase/migrations/20260521100000_auth_rbac_supabase_linter_fixes.sql` |
| **Evidence** | `audit_log_select` allows SELECT when `organization_id = jwt_organization_id()` — any org member, not just administrators. |
| **Recommended solution** | Restrict org-wide audit SELECT to `settings.view_audit` permission or administrator role. |

---

### M-09 — Encounter-workspace feature churn creates spec/schema drift *(2nd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd |
| **Files involved** | `20260701120000_visit_encounter_workspace.sql`, `20260702120000_remove_coded_diagnosis.sql`, `20260705120000_remove_structured_plan_outputs.sql` |
| **Evidence** | July 1 migration adds diagnosis/plan tables and RPCs. July 2 drops diagnosis tables. July 5 drops `visit_plan_details`. Tests still named `visit_encounter_workspace_*`. |
| **Recommended solution** | Update spec 014 docs to reflect reduced scope; rename tests; add migration comment block listing active encounter tables. |

---

### M-10 — README migration instructions disagree with Docker Compose path *(2nd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd |
| **Files involved** | `backend/README.md`, `backend/local/docker-compose.yml` |
| **Evidence** | README recommends `supabase db reset` / `supabase migration up`. Compose stack mounts only `init.sql` with no migration runner. |
| **Recommended solution** | Document two explicit paths (CLI vs Compose) with required migration apply steps for each. |

---

### M-11 — Org catalog tables writable by any staff with `visits.edit_soap` *(2nd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd |
| **Files involved** | `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`, `backend/supabase/migrations/20260711120000_coderabbit_review_fixes.sql` |
| **Evidence** | `create_catalog_medication` / `create_catalog_investigation` require only `assert_permission('visits.edit_soap')`. RLS blocks direct INSERT. |
| **Recommended solution** | Separate `catalog.manage` permission or restrict catalog creation to administrators. |

---

### M-12 — `assert_one_active_invoice_per_visit` defined but unused *(2nd pass)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd |
| **Files involved** | `backend/supabase/migrations/20260605180000_billing.sql`, `backend/supabase/migrations/20260605180500_billing_us1_rpcs.sql` |
| **Evidence** | Helper created, revoked from authenticated. `create_invoice_from_visit` uses inline `IF EXISTS` instead. Zero calls outside definition. |
| **Recommended solution** | Call helper inside `create_invoice_from_visit` or remove dead helper. |

---

### M-13 — Storage bucket lacks DELETE/UPDATE policies for `authenticated` *(2nd pass — informational)*

| Field | Detail |
|-------|--------|
| **Pass** | 2nd |
| **Files involved** | `backend/supabase/migrations/20260531180000_visit_medical_records.sql`, `backend/supabase/migrations/20260601160000_fix_visit_storage_folder_depth.sql` |
| **Evidence** | Only insert/select policies exist. Deletes go through `auth_internal.delete_visit_attachment` RPC. |
| **Recommended solution** | Document that attachment deletion is RPC-only; add negative test attempting direct storage delete. |

---

## 4. Low Priority Issues

| ID | Summary | Pass | Evidence / Recommendation |
|----|---------|------|---------------------------|
| L-01 | Grant regression tests exist only for appointments | 1st | Add generic `auth_internal_grants_regression.sql` per feature |
| L-02 | Deferred auth tests documented but not implemented | 1st | `README_DEFERRED_TESTS.md:6-10` — track as GitHub issues |
| L-03 | `add_invoice_item` retirement documented in plan but not enforced | 1st | See H-03 |
| L-04 | `validate_local_stack.sh` / `connectivity_smoke.sh` not in master runner | 2nd | Wire into `run_all_backend_tests.sh` |
| L-05 | `seed_organization_catalog_defaults` grant revoked but trigger remains | 2nd | Revoke at `20260711120000:7`; trigger still fires internally |
| L-06 | Visit medical records sub-runner shows psql errors; master runner does not | 2nd | Align error visibility across runners |
| L-07 | 10+ `coderabbit_review_fixes_*` migrations increase review surface | 2nd | `20260711120000` through `20260711210000` — hard to audit atomic intent |

---

## 5. Migration Issues

| ID | Issue | Recommendation |
|----|-------|----------------|
| MI-01 | 15+ patches to `dev_reset_clinic_installation` | Consolidate into one function; use additive delete helpers |
| MI-02 | `delete_clinic_operational_dependents` redefined 5× in July 2026 | Single source of truth; CI FK-child parity test |
| MI-03 | `seed.sql` functions not in migrations | Migrate local-only functions or document as mandatory post-migrate step |
| MI-04 | Grant migrations not co-located with feature RPCs | Each feature migration file ends with explicit `GRANT EXECUTE` block |
| MI-05 | Feature add/remove within days (encounter workspace) | Feature flags or single squashed migration per release |
| MI-06 | Transient FK hazard pattern during encounter workspace churn | For future tables: always add teardown in same migration as CREATE |
| MI-07 | `remove_coded_diagnosis` drops functions but encounter migration seeds remain in history | Squash or document one-time data migration path |
| MI-08 | `soap_notes` dropped before backfill could run | See C-04; reorder migrations for greenfield paths |

---

## 6. Configuration Issues

| ID | Issue | Recommendation |
|----|-------|----------------|
| CF-01 | Open signup (`GOTRUE_DISABLE_SIGNUP: "false"`) | `true` except solo dev — see H-19 |
| CF-02 | Pre-request not applied without seed | Auto-run seed or migrate function — see H-29 |
| CF-03 | Compose lacks migration automation | Add migrate init container — see H-18 |
| CF-04 | JWT hook URI hardcoded | Validate in `validate_local_stack.sh` |
| CF-05 | `app.environment` unset blocks dev_reset in prod | By design; ensure pre-request never runs in prod |
| CF-06 | Kong storage/realtime unrate-limited | Add rate-limiting plugins — see M-07 |
| CF-07 | README vs Compose migration path split | Unify documentation — see M-10 |
| CF-08 | JWT secret ↔ anon/service key incoherence | Regenerate keys or align secret — see H-26 |
| CF-09 | Postgres host port published with default password | Remove host publish — see C-03 |
| CF-10 | PostgREST uses `postgres` superuser DB role | Switch to `authenticator` — see H-28 |

---

## 7. Test Coverage Gaps

| Area | Covered | Gap |
|------|---------|-----|
| Auth / RBAC | jwt contract, extended, isolation | No PATCH escalation test for `staff_members`; no deactivation SELECT denial (H-33) |
| Org / Branch | CRUD, RLS | Direct UPDATE bypass not tested as vulnerability |
| Patients | CRUD, RLS, search | No cross-branch SELECT denial (H-20); no transfer branch-scope test (H-34) |
| Appointments | CRUD, RLS, grants | `appointment_queue_qa.sql`, `appointment_calendar_backend_integrity.sql` omitted; Realtime not configured (H-27); no true overlap race test (H-39) |
| Billing | CRUD, RLS, pseudo-concurrency | No grant regression; no PostgREST HTTP tests (H-30); void semantics gap (H-41) |
| Service Catalog | CRUD, RLS, pricing, pseudo-concurrency | No grant regression; no PostgREST tests; branch config race (H-38) |
| Shifts | CRUD, RLS, pseudo-concurrency | No grant regression; no PostgREST tests; overlap race (H-40) |
| Visits | Sub-suite via `run_visit_medical_records_tests.sh` | Encounter workspace reduced scope not reflected in test names |
| Infrastructure | `validate_local_stack.sh`, `connectivity_smoke.sh` | Not in CI or master runner (L-04) |
| Auth E2E | `auth_flow_smoke.sh` with soft-fail | GoTrue failures non-blocking (H-16); JWT incoherence (H-26) |
| INVOKER grant chain | `appointment_management_grants.sql` only | Billing, shifts, catalog, pricing, bootstrap, settings lack equivalent |

---

## 8. Security Concerns

| Concern | Severity | Finding IDs |
|---------|----------|-------------|
| LAN-exposed Postgres superuser | Critical | C-03 |
| Role escalation via RLS | Critical | C-01 |
| Missing invoker grants | Critical/High | C-02, H-09, H-10, H-22, H-31, H-32 |
| Clinical data loss on migration | Critical | C-04 |
| Cross-user claims disclosure | High | H-04 |
| Direct table mutation | High | H-01, H-02 |
| Cross-branch patient reads | High | H-20 |
| JWT-stale authorization | High | H-33 |
| Internal definer exposure | High | H-24 |
| Open signup | High | H-19 |
| Legacy billing bypass | High | H-03 |
| Dev seed grants | High | H-25 |
| Patient transfer branch bypass | High | H-34 |
| Audit log over-read | Medium | M-08 |
| Storage/realtime DoS | Medium | M-07 |
| Superuser test execution | High | H-13, H-30 |

---

## 9. Performance Concerns

| Concern | Evidence | Notes |
|---------|----------|-------|
| Audit log growth | Append-only `audit_log`; cleanup RPC return type inconsistent (M-05) | Schedule retention job |
| Patient search | Indexes in `20260525120700_fix_search_indexes.sql` | Monitor under load |
| Org-wide patient SELECT | No branch predicate on `patients_select` (H-20) | Large orgs: wider scans than necessary |
| Invoice number assignment | Row-level lock per branch | Acceptable for V1 |
| Sequential concurrency tests | H-15 | Does not validate lock contention (H-39, H-40) |
| Catalog autocomplete | `search_eligible_services` resolves price per row | N+1 pattern; monitor at 2k services |

*No critical throughput blockers; primary risks are correctness, security, and privacy.*

---

## 10. Architectural Improvements

1. **Enforce RPC-only mutations universally** — Set UPDATE/INSERT RLS policies to `false` on `staff_members`, `organizations`, `branches` (pattern already on billing, service catalog, patients).

2. **Grant checklist per feature** — Every `public` INVOKER wrapper → matching `GRANT EXECUTE ON auth_internal.* TO authenticated` in same migration + grant regression SQL file.

3. **Branch-scoped patient access model** — Align RLS, `assert_org_patient`, `search_patients`, `transfer_patient`, and PostgREST SELECT.

4. **Unified teardown registry** — Stop redefining `delete_clinic_operational_dependents` in feature migrations.

5. **DB-level integrity constraints** — Patient branch/org alignment (H-07), service-branch org alignment (H-08), invoice/shift org-branch alignment (H-36), invoice item service org alignment (H-35).

6. **CI backend gate** — Docker compose + migrations + `run_all_backend_tests.sh` + `validate_local_stack.sh` on every PR.

7. **Test harness hardening** — Visible errors, authenticated-role assertions, PostgREST HTTP smoke per domain, real concurrency sessions.

8. **Infrastructure hardening** — Remove Postgres host exposure (C-03), switch PostgREST to `authenticator` (H-28), fix JWT/key coherence (H-26), Kong rate limits (M-07).

9. **Revoke internal helpers from authenticated** — `assert_patient_branch_scope`, `build_staff_claims(uuid)`, `dev_seed_*`.

10. **Live staff state in RLS** — Replace `jwt_staff_role()` with DB lookups (H-33).

11. **Atomic concurrency patterns** — `FOR UPDATE` or exclusion constraints for patients (H-37), appointments (H-39), shifts (H-40), service catalog (H-38).

12. **Retire legacy APIs** — `add_invoice_item` free-text path per service catalog plan (H-03).

---

## 11. Things That Appear Correct

- **RLS deny-by-default on billing mutations** — `invoices_update` `USING (false)`; `invoice_items_insert` `WITH CHECK (false)`.
- **Service catalog direct DML blocked** — `services_update` / `service_branches_insert` use `false`.
- **Patient/appointment/visit/shift direct mutations blocked** — `patients_update`, `appointments_update`, `visits_update`, `shifts_update` all `USING (false)`.
- **Auth internal grant restriction pattern** — Blanket revoke + explicit grants (`20260525120200`) is correct; newer features failed to follow it.
- **Appointment grant regression test** — `appointment_management_grants.sql` documents superuser bypass and checks `has_function_privilege`.
- **Visit encounter workspace grants** — `20260701120000` grants `auth_internal` EXECUTE for encounter RPCs (positive contrast to catalog/billing).
- **`update_staff_member` cross-org branch guard** — `20260611170000:104-114` rejects foreign-org branches.
- **`create_staff_account` org branch guard** — Remediated in `20260614100000`.
- **`seed_organization_catalog_defaults` restricted** — `REVOKE` from authenticated at `20260711120000:7`.
- **Encounter patient safety uses branch scope** — `get_patient_safety_context` calls `assert_patient_branch_scope`.
- **Invoice number sequences RLS denied** — `invoice_number_sequences_deny`.
- **Partial unique index for one active invoice per visit** — `invoices_visit_active_unique` at `20260605180000:108-110`.
- **Billing payment recording** — `lock_payable_invoice` + balance check prevents overpayment races.
- **Appointment in_progress uniqueness** — Partial unique indexes + `unique_violation` handlers.
- **Dev reset environment gate** — Blocks when `app.environment` not in dev/local/test.
- **Storage insert policy** — Uses `staff_can_access_branch` helper.
- **JWT custom claims hook** — `get_custom_claims` wired in compose; claims contract tested in `jwt_claims_contract.sql`.
- **Optimistic concurrency pattern** — `p_expected_updated_at` with `STALE_*` errors consistently applied (where `FOR UPDATE` is used).
- **Last administrator guards in RPCs** — Protected on RPC path (undermined only by RLS bypass C-01).

---

## 12. Recommended Remediation Priority

### P0 — Immediate (before next release)

| # | Action | Addresses |
|---|--------|-----------|
| 1 | Remove Postgres host port publish; enforce non-default password | C-03 |
| 2 | Lock `staff_members_update` to RPC-only (`USING false`) | C-01 |
| 3 | Add all missing `auth_internal` EXECUTE grants (catalog CRUD + pricing, billing, shifts, bootstrap, settings) | C-02, H-09, H-10, H-22, H-31, H-32 |
| 4 | Lock `organizations_update` and `branches_update` to RPC-only | H-01, H-02 |
| 5 | Revoke `authenticated` on `auth_internal.build_staff_claims(uuid)` | H-04 |
| 6 | Fix JWT secret ↔ anon/service key coherence; add sign-in validation | H-26 |
| 7 | Document `soap_notes` recovery; fix migration ordering for greenfield backfill | C-04 |

### P1 — This sprint

| # | Action | Addresses |
|---|--------|-----------|
| 8 | Branch-scope `patients_select` and `assert_org_patient` | H-20 |
| 9 | Revoke `assert_patient_branch_scope` + `dev_seed_*` from authenticated | H-24, H-25 |
| 10 | Add grant regression tests + PostgREST smoke for billing, shifts, catalog | L-01, H-13, H-30 |
| 11 | Add omitted appointment tests; surface psql errors | H-11, H-12 |
| 12 | Retire or gate `add_invoice_item` legacy path | H-03 |
| 13 | Add patient branch/org DB constraint | H-07 |
| 14 | Add service_branches and invoice_items org-alignment constraints | H-08, H-35 |
| 15 | Fix invoice currency default from org settings | M-01 |
| 16 | Replace `jwt_staff_role()` in RLS with live staff row lookups | H-33 |
| 17 | Branch-access guards on `transfer_patient` | H-34 |
| 18 | Atomic stale checks on `update_patient` | H-37 |
| 19 | Exclusion constraint or row locks for appointment doctor overlap | H-39 |
| 20 | Define void semantics: block or auto-refund when payments exist | H-41 |
| 21 | Migration: Realtime publication for `appointments` | H-27 |
| 22 | Resolve pre-request/seed coupling | H-29 |

### P2 — Next sprint

| # | Action | Addresses |
|---|--------|-----------|
| 23 | Consolidate teardown functions; add parity test | H-05, H-23, MI-02 |
| 24 | Add backend job to CI | H-17 |
| 25 | Add migration runner to docker-compose; switch PostgREST to `authenticator` | H-18, H-28, CF-03 |
| 26 | Migrate `local_dev_pre_request` or auto-run seed | M-06, CF-02 |
| 27 | Kong rate limits on storage/realtime | M-07, CF-06 |
| 28 | Restrict audit_log SELECT by permission | M-08 |
| 29 | Align encounter spec/tests with reduced schema | M-09 |
| 30 | Org-alignment constraints on `invoices` and `shifts` | H-36 |
| 31 | `FOR UPDATE` on `service_branches` in configure/promotion RPCs | H-38 |
| 32 | Lock or constrain shift staff overlap | H-40 |
| 33 | Disable open signup on shared environments | H-19 |
| 34 | Harden `dev_seed_*` fail-closed guards | M-04 |

### P3 — Backlog

| # | Action | Addresses |
|---|--------|-----------|
| 35 | Real concurrency test harness | H-15 |
| 36 | Standardize test transaction strategy | H-14 |
| 37 | Align shifts soft-delete with platform convention | M-03 |
| 38 | Evaluate ON DELETE CASCADE for child tables | H-06 |
| 39 | Implement deferred auth E2E tests | L-02 |
| 40 | Make GoTrue smoke test mandatory in CI | H-16 |
| 41 | Fix `cleanup_audit_log` return type | M-05 |
| 42 | Wire infrastructure smoke tests into master runner | L-04 |

---

## 13. Review History

| Pass | Date | Documents (archived) | Focus |
|------|------|----------------------|-------|
| 1st | 2026-07-05 | *(merged into consolidated doc; no separate archive file)* | Services & Auth, Data Layer, Tests, Infrastructure — C-01/C-02, H-01–H-19, M-01–M-06, L-01–L-03 |
| 2nd | 2026-07-05 | `archive/backend-review-cycles/backend-architecture-review-second-pass.md` | Skeptical re-verification + H-20–H-25, M-07–M-13, L-04–L-07 |
| 3rd | 2026-07-05 | `archive/backend-review-cycles/backend-architecture-review-third-pass.md`, `third-pass-*.md` | Config/tests (C-03, H-26–H-30), auth/RPC (H-31–H-33), migrations/RLS (C-04, H-34–H-36), business logic (H-37–H-41) |

---

*End of consolidated backend architecture review. Generated 2026-07-05 from three review passes cross-checked against `backend/supabase/migrations/` and `backend/tests/`.*
