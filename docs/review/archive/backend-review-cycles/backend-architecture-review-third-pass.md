# Backend Architecture Review — Third Pass (Synthesis)

**Date:** 2026-07-05  
**Scope:** New Critical/High findings only — config/infra/tests, auth/RPC/grants, migrations/RLS, business logic/transactions  
**Prior art:** [backend-architecture-review.md](./backend-architecture-review.md) (first pass), [backend-architecture-review-second-pass.md](./backend-architecture-review-second-pass.md) (second pass)  
**Domain reports:** [third-pass-config-tests.md](./third-pass-config-tests.md) · [third-pass-auth-rpc.md](./third-pass-auth-rpc.md) · [third-pass-migrations-rls.md](./third-pass-migrations-rls.md) · [third-pass-business-logic.md](./third-pass-business-logic.md)

---

## Executive Summary

Third pass adds **2 new Critical** and **16 new High** findings across four domain reviews. All first/second-pass findings (C-01, C-02, H-01–H-25) remain open and are not repeated here.

| Severity | New in 3rd pass | Source |
|----------|-----------------|--------|
| Critical | 2 (C-03, C-04) | Config (1), Migrations (1) |
| High | 16 (H-26 – H-41) | Config (5), Auth (3), Migrations (3), Business logic (5) |
| **Total** | **18** | 4 of 4 domain passes complete |

**Highest-risk new items:** LAN-exposed Postgres superuser (C-03), irreversible `soap_notes` data loss on migration apply (C-04), JWT/RLS split-brain after staff deactivation (H-33), and concurrent appointment double-booking races (H-39).

---

## Critical Issues (New)

### C-03 — PostgreSQL superuser port published on host with default password

| Field | Detail |
|-------|--------|
| **Source** | [third-pass-config-tests.md](./third-pass-config-tests.md) |
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
| **Source** | [third-pass-migrations-rls.md](./third-pass-migrations-rls.md) |
| **Severity** | Critical |
| **Files involved** | `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`, `backend/supabase/migrations/20260711120000_coderabbit_review_fixes.sql` |
| **Evidence** | `20260628140000:67-90` creates `visit_clinical_notes` as replacement for `soap_notes`. `20260628140000:169` executes `DROP TABLE IF EXISTS public.soap_notes` with **no** `INSERT INTO visit_clinical_notes … SELECT FROM soap_notes`. Later, `20260711120000:522-557` wraps backfill in `IF to_regclass('public.soap_notes') IS NOT NULL` — but `soap_notes` was already dropped 11 migrations earlier, so this block never runs on a normal sequential apply. |
| **Why it's a problem** | Any database with existing `soap_notes` clinical documentation loses all subjective/objective/assessment/plan content permanently when `20260628140000` is applied. The later "fix" migration gives false confidence but cannot recover data. |
| **Potential impact** | Irreversible loss of visit clinical documentation on production/staging upgrade; regulatory/clinical record integrity failure. |
| **Recommended solution** | Add a new migration that cannot help already-upgraded DBs (document one-time manual recovery). For greenfield paths: squash or reorder so backfill runs **before** first `DROP TABLE soap_notes`. Pattern: `INSERT INTO visit_clinical_notes … SELECT … FROM soap_notes WHERE NOT EXISTS (…)` then `DROP TABLE`. Map `subjective→complaint`, `objective→examination`, `assessment→diagnosis`, `plan→plan` per `20260711120000:536-545`. Add migration test asserting row-count parity when `soap_notes` has seed data. |

---

## High Priority Issues (New)

### Config & test blind spots (H-26 – H-30)

| ID | Title | Source |
|----|-------|--------|
| **H-26** | JWT secret and API keys incoherent in `.env.example` — fresh compose produces invalid tokens while SQL tests pass | [config](./third-pass-config-tests.md) |
| **H-27** | Appointment Realtime never configured in migrations — live queue feature non-functional on compose stack | [config](./third-pass-config-tests.md) |
| **H-28** | PostgREST connects as `postgres` superuser, not `authenticator` | [config](./third-pass-config-tests.md) |
| **H-29** | Compose hardcodes `PGRST_DB_PRE_REQUEST` without applying `seed.sql` — total REST outage on migrations-only bring-up | [config](./third-pass-config-tests.md) |
| **H-30** | Billing, shifts, and service catalog have zero PostgREST HTTP test coverage | [config](./third-pass-config-tests.md) |

#### H-26 — JWT secret and API keys incoherent in committed `.env.example`

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/local/.env.example`, `frontend/config/local/deployment-profile.json`, `docs/implementation/spec001/backend-implementation.md` |
| **Evidence** | `.env.example` sets `SUPABASE_JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters-long` but ships standard Supabase **demo** `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` signed for a different secret. `validate_local_stack.sh:87-90` auto-copies `.env.example` → `.env`. |
| **Why it's a problem** | Fresh compose setup produces invalid JWTs. HTTP auth/REST/Storage fail; SQL tests still pass as `postgres` superuser. |
| **Potential impact** | Flutter client cannot authenticate; false green backend test runs; onboarding broken until keys manually regenerated. |
| **Recommended solution** | Regenerate anon/service keys signed with the committed JWT secret, or revert JWT secret to match demo keys. Add `validate_local_stack.sh` step: sign-in smoke with anon key must succeed. |

#### H-27 — Appointment Realtime never configured in migrations

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/local/docker-compose.yml`, `frontend/lib/features/appointments/data/appointment_queue_realtime.dart`, all `backend/supabase/migrations/*.sql` |
| **Evidence** | Flutter subscribes to `public.appointments` postgres changes. Repository-wide grep: **zero** `ALTER PUBLICATION`, `supabase_realtime`, or `REPLICA IDENTITY` in migrations. Realtime service runs in compose; Kong routes `/realtime/v1/`. |
| **Why it's a problem** | Self-hosted compose path likely never broadcasts appointment changes; queue stays stale unless manually refreshed. |
| **Potential impact** | Live queue feature non-functional on deployment stack; UI degrades silently. |
| **Recommended solution** | Migration: `ALTER PUBLICATION supabase_realtime ADD TABLE public.appointments`; set `REPLICA IDENTITY FULL` for UPDATE payloads; add Realtime RLS check; websocket integration test in CI. |

#### H-28 — PostgREST connects as `postgres` superuser, not `authenticator`

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/local/docker-compose.yml`, `backend/local/init.sql` |
| **Evidence** | `PGRST_DB_URI: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres`. `init.sql` creates `anon`/`authenticated`/`service_role` but **not** `authenticator`. No `FORCE ROW LEVEL SECURITY` in any migration. |
| **Why it's a problem** | Violates Supabase least-privilege model. API layer DB connection is superuser-capable; defense relies entirely on PostgREST always switching to JWT role correctly. |
| **Potential impact** | PostgREST misconfiguration or future CVE could expose superuser access; harder to audit DB privilege separation for clinic LAN deployments. |
| **Recommended solution** | Use `authenticator` role in `PGRST_DB_URI`; grant `authenticated`/`anon` membership; revoke direct superuser API path. |

#### H-29 — Compose hardcodes `PGRST_DB_PRE_REQUEST` without applying `seed.sql`

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/local/docker-compose.yml`, `backend/supabase/seed.sql` |
| **Evidence** | Compose sets `PGRST_DB_PRE_REQUEST: public.local_dev_pre_request`. Function defined only in `seed.sql:7-14`. Compose mounts only `init.sql`; no seed step. Migrations contain no `local_dev_pre_request`. |
| **Why it's a problem** | Migrations-only compose bring-up leaves pre-request function missing → PostgREST errors on **every** request. Prior review scoped impact to dev tooling (M-06 Medium). |
| **Potential impact** | Total REST/RPC API outage on compose stack until seed manually applied; `validate_local_stack.sh` may still pass auth health checks while REST is broken. |
| **Recommended solution** | Move `local_dev_pre_request` into a guarded migration, or remove `PGRST_DB_PRE_REQUEST` from compose until seed runs; add REST smoke that calls an RPC and expects 200. |

#### H-30 — Billing, shifts, and service catalog have zero PostgREST HTTP test coverage

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/tests/run_billing_tests.sh`, `run_shift_management_tests.sh`, `run_service_catalog_tests.sh`, `frontend/test/boundary/` |
| **Evidence** | All three sub-runners use `psql -U postgres` only. Flutter boundary suite covers auth/patients/appointments/settings via live PostgREST; **grep finds no** billing/shift/catalog boundary tests. Known missing grants (C-02, H-09, H-10, H-22) therefore cannot be caught for those domains. |
| **Why it's a problem** | INVOKER grant chain failures are the highest-risk production bug class; 3 of 4 major feature domains have no PostgREST-path verification at all. |
| **Potential impact** | Billing, shifts, and catalog ship broken via API while SQL superuser tests stay green. |
| **Recommended solution** | Add `*_grants.sql` per domain; add boundary or curl-based RPC smoke per feature; wire into `run_all_backend_tests.sh` and CI. |

---

### Auth, RPC & grants (H-31 – H-33)

| ID | Title | Source |
|----|-------|--------|
| **H-31** | `bootstrap_finish_setup` `auth_internal` EXECUTE grant signature drift — INVOKER chain broken after 12th parameter added | [auth](./third-pass-auth-rpc.md) |
| **H-32** | `admin_update_staff_username` missing `auth_internal` EXECUTE grant | [auth](./third-pass-auth-rpc.md) |
| **H-33** | RLS and `staff_can_access_branch` trust stale JWT claims over live `staff_members` state | [auth](./third-pass-auth-rpc.md) |

#### H-31 — `bootstrap_finish_setup` `auth_internal` EXECUTE grant signature drift

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/supabase/migrations/20260611140000_allow_admin_create_owner_and_atomic_bootstrap_setup.sql`, `backend/supabase/migrations/20260613120000_bootstrap_finish_setup_working_schedule.sql`, `backend/supabase/migrations/20260613150000_create_staff_account_phone.sql` |
| **Evidence** | Only `auth_internal` grant is on **11-parameter** signature. `20260613120000` adds `p_branch_working_schedule jsonb` (12th param) via `CREATE OR REPLACE` — a new function identity in PostgreSQL. Re-grants **public** 12-param wrapper only; no matching `auth_internal` re-grant. Public wrapper is `SECURITY INVOKER`. |
| **Why it is a problem** | PostgREST runs as `authenticated`. INVOKER wrapper requires `EXECUTE` on the **current** `auth_internal` function signature. Orphan 11-param grant does not cover the 12-param function. |
| **Potential impact** | Atomic clinic bootstrap (`bootstrap_finish_setup`) fails under PostgREST for all callers. Tests pass as `postgres` superuser. |
| **Recommended solution** | Add migration: `GRANT EXECUTE ON FUNCTION auth_internal.bootstrap_finish_setup(text, text, jsonb, jsonb, text, text, text, text, text, text, text, jsonb) TO authenticated;` Add grant regression test modeled on `appointment_management_grants.sql`. |

#### H-32 — `admin_update_staff_username` missing `auth_internal` EXECUTE grant

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/supabase/migrations/20260613200000_admin_update_staff_username.sql`, `backend/supabase/migrations/20260614000000_fix_admin_update_staff_username_forbidden.sql` |
| **Evidence** | `public.admin_update_staff_username` is `SECURITY INVOKER`. Only grant: `GRANT EXECUTE ON FUNCTION public.admin_update_staff_username(uuid, text) TO authenticated`. Repository-wide grep: **zero** `GRANT EXECUTE ON FUNCTION auth_internal.admin_update_staff_username`. |
| **Why it is a problem** | Same INVOKER grant-gap class as H-09/H-10/C-02. Wrapper delegates to `auth_internal.admin_update_staff_username`; `authenticated` lacks EXECUTE on the definer function. |
| **Potential impact** | Staff username changes non-functional via API; settings credential management broken under PostgREST. |
| **Recommended solution** | `GRANT EXECUTE ON FUNCTION auth_internal.admin_update_staff_username(uuid, text) TO authenticated;` in same migration pattern as other settings RPCs. |

#### H-33 — JWT-stale authorization: RLS and `staff_can_access_branch` trust claims over live staff state

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/supabase/migrations/20260528133000_fix_staff_branch_assignments_rls_recursion.sql`, `backend/supabase/migrations/20260611150000_remove_owner_role.sql`, `backend/supabase/migrations/20260523140000_patient_management.sql`, `backend/local/docker-compose.yml` |
| **Evidence** | `staff_branch_assignments_select` grants org-wide visibility when `public.jwt_staff_role() IN ('owner', 'administrator')` — reads JWT, not `staff_members.role`. `auth_internal.staff_can_access_branch` grants administrators org-wide branch access via `public.jwt_staff_role() = 'administrator'`. RPC `assert_permission` correctly reads live `staff_members.is_active` and `role` from DB. RLS `patients_select` filters only `organization_id = public.jwt_organization_id()` — no caller `is_active` check. JWT lifetime: 3600s. |
| **Why it is a problem** | Authorization is **split-brain**: RPC mutations use live DB state; RLS SELECT and branch helpers use JWT claims that can lag up to 1 hour after deactivation or role demotion. |
| **Potential impact** | Deactivated staff with unexpired JWT retain PostgREST read access to org patients, branches, appointments, audit entries, etc. Demoted administrators retain org-wide branch visibility until re-login. |
| **Recommended solution** | Add stable helper `auth_internal.current_staff_is_active()` / `current_staff_role()` reading live `staff_members` row; use in RLS policies and `staff_can_access_branch` instead of `jwt_staff_role()`. Optionally shorten JWT TTL or force session invalidation on deactivation/role change. |

---

### Migrations & RLS (H-34 – H-36)

| ID | Title | Source |
|----|-------|--------|
| **H-34** | `transfer_patient` allows cross-branch transfer without caller branch-access validation | [migrations](./third-pass-migrations-rls.md) |
| **H-35** | `invoice_items.service_id` lacks DB constraint aligning service org with invoice org | [migrations](./third-pass-migrations-rls.md) |
| **H-36** | `invoices` and `shifts` store independent `organization_id` + `branch_id` with no alignment constraint | [migrations](./third-pass-migrations-rls.md) |

#### H-34 — `transfer_patient` allows cross-branch transfer without caller branch-access validation

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/supabase/migrations/20260524110200_fix_patient_transfer_restore.sql` |
| **Evidence** | Source patient resolved via `assert_org_patient` only — org scope, no branch check. Target branch validated for existence/active/same-org but **not** `staff_can_access_branch(p_new_branch_id)`. No check that caller can access the patient's current `branch_id`. Encounter RPCs use `assert_patient_branch_scope` — asymmetric. |
| **Why it's a problem** | Staff with `patients.edit` at branch A can transfer any org patient (including from branch B they cannot access) to any active org branch, including branches they are not assigned to. |
| **Potential impact** | Unauthorized cross-branch patient relocation; branch segregation policy bypass. |
| **Recommended solution** | Before UPDATE: `PERFORM auth_internal.assert_patient_branch_scope(p_patient_id)`. Require `staff_can_access_branch(p_new_branch_id)` on target. Add regression test: receptionist at branch A cannot transfer patient registered at branch B. |

#### H-35 — `invoice_items.service_id` lacks DB constraint aligning service org with invoice org

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/supabase/migrations/20260712091500_service_catalog_billing_integration.sql`, `backend/supabase/migrations/20260605180000_billing.sql` |
| **Evidence** | Adds `invoice_items.service_id uuid REFERENCES public.services (id)` — no CHECK/trigger that `services.organization_id = invoices.organization_id`. RPC `add_invoice_item_from_service` validates at runtime. `invoice_items_insert` is `WITH CHECK (false)`. Legacy `add_invoice_item` free-text path (H-03) can still insert rows without `service_id`. |
| **Why it's a problem** | Integrity depends entirely on RPC code. `SECURITY DEFINER` bugs, superuser paths, or future direct SQL can attach a foreign-org `service_id` to an invoice item. |
| **Potential impact** | Cross-org service references on invoice line items; incorrect pricing snapshots; reporting corruption. |
| **Recommended solution** | Add trigger `BEFORE INSERT OR UPDATE ON invoice_items` validating org alignment between `service_id` and parent invoice. Add negative test attempting mismatched org link via superuser. |

#### H-36 — `invoices` and `shifts` store independent `organization_id` + `branch_id` with no alignment constraint

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/supabase/migrations/20260605180000_billing.sql`, `backend/supabase/migrations/20260606180000_shift_management.sql` |
| **Evidence** | `invoices`: `organization_id` and `branch_id` are separate FKs with no CHECK that `branch.organization_id = invoices.organization_id`. `shifts`: same pattern. RPCs set both from branch lookup. `patients` has the same gap (H-07); these tables were not called out. |
| **Why it's a problem** | Misaligned rows can be inserted via superuser, migration scripts, or future RLS gaps, producing invoices/shifts that belong to org A but reference branch B from org C. |
| **Potential impact** | Cross-tenant data corruption; billing reports scoped wrong; shift schedules attached to wrong org metadata. |
| **Recommended solution** | Add composite CHECK or trigger on both tables: `organization_id = (SELECT organization_id FROM branches WHERE id = branch_id)`. Mirror H-07 remediation pattern. |

---

### Business logic & transactions (H-37 – H-41)

| ID | Title | Source |
|----|-------|--------|
| **H-37** | `update_patient` stale check is non-atomic; concurrent edits silently overwrite | [business logic](./third-pass-business-logic.md) |
| **H-38** | Service catalog branch config/promotion RPCs have racy optimistic concurrency | [business logic](./third-pass-business-logic.md) |
| **H-39** | Appointment scheduling overlap checks are check-then-act without exclusion constraints | [business logic](./third-pass-business-logic.md) |
| **H-40** | Shift staff overlap validation is check-then-act without row locks | [business logic](./third-pass-business-logic.md) |
| **H-41** | `void_invoice` allows voiding partially-paid invoices without refund enforcement | [business logic](./third-pass-business-logic.md) |

#### H-37 — `update_patient` stale check is non-atomic; concurrent edits silently overwrite

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/supabase/migrations/20260523140000_patient_management.sql` |
| **Evidence** | `assert_org_patient` is `STABLE` with no row lock. Stale check compares `updated_at` to `p_expected_updated_at`. `UPDATE` has **no** `FOR UPDATE` beforehand and **no** `WHERE updated_at = p_expected_updated_at` on the update itself. |
| **Why it is a problem** | Two receptionists editing the same patient with the same loaded `updated_at` both pass `STALE_PATIENT`, then last-write-wins. |
| **Potential impact** | Patient PII corruption; duplicate national IDs if uniqueness check passes on stale snapshot. |
| **Recommended solution** | `SELECT … FOR UPDATE` before validation, or atomic `UPDATE … WHERE id = $1 AND updated_at = $2` with `GET DIAGNOSTICS` → `STALE_PATIENT` when `ROW_COUNT = 0`. |

#### H-38 — Service catalog branch config/promotion RPCs have racy optimistic concurrency

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql` |
| **Evidence** | `configure_service_branch` reads `service_branches` without `FOR UPDATE`, stale check, then `UPDATE` with no `WHERE updated_at = p_expected_updated_at`. Same pattern in `set_service_promotion`. Contrast `update_service` which **does** use `FOR UPDATE`. |
| **Why it is a problem** | Concurrent administrators editing branch pricing/promotions can pass stale checks on the same timestamp and overwrite each other. |
| **Potential impact** | Wrong prices on invoices created via `add_invoice_item_from_service`; promo dates corrupted; billing disputes. |
| **Recommended solution** | `SELECT … FOR UPDATE` on `service_branches` before stale validation, or conditional `UPDATE … WHERE updated_at = p_expected_updated_at`. |

#### H-39 — Appointment scheduling overlap checks are check-then-act without exclusion constraints

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/supabase/migrations/20260628160000_simplified_slot_booking.sql`, `backend/supabase/migrations/20260604130000_fix_create_appointment_exception_handlers.sql`, `backend/supabase/migrations/20260618140000_update_appointment.sql`, `backend/supabase/migrations/20260601180000_appointment_medium_severity_fixes.sql` |
| **Evidence** | `appointment_has_overlap` is `STABLE`, returns `false` when `p_doctor_id IS NULL`, and performs a non-locking `EXISTS`. `create_appointment` checks overlap then inserts with no `FOR UPDATE` on conflicting rows. No GiST/exclusion constraint on doctor time ranges for active appointments. |
| **Why it is a problem** | Two concurrent `create_appointment` / `reschedule_appointment` calls for the same doctor and slot can both pass `appointment_has_overlap` and both commit. |
| **Potential impact** | Double-booked doctors; two patients for one slot; queue/calendar corruption. |
| **Recommended solution** | Add PostgreSQL exclusion constraint using `tstzrange` + `btree_gist`, or `SELECT … FOR UPDATE` on overlapping appointment rows inside the RPC before insert/update. |

#### H-40 — Shift staff overlap validation is check-then-act without row locks

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/supabase/migrations/20260606180000_shift_management.sql`, `backend/supabase/migrations/20260607120000_shift_medium_severity_fixes.sql` |
| **Evidence** | `assert_no_staff_shift_overlap` queries overlapping shifts without locking them. `create_shift` calls it then `INSERT INTO shifts` and assignment inserts. No exclusion constraint on shift time ranges per staff member. |
| **Why it is a problem** | Concurrent `create_shift` / `modify_shift_assignments` for the same staff and overlapping window can both pass the assertion and commit duplicate assignments. |
| **Potential impact** | Staff scheduled in two places at once; payroll/scheduling errors. |
| **Recommended solution** | Lock conflicting `shifts`/`shift_assignments` rows with `FOR UPDATE`, or add exclusion constraint on staff shift time ranges where `deleted_at IS NULL`. |

#### H-41 — `void_invoice` allows voiding partially-paid invoices without refund enforcement

| Field | Detail |
|-------|--------|
| **Files involved** | `backend/supabase/migrations/20260605310000_fix_billing_review_items_18_21_24.sql`, `backend/supabase/migrations/20260605181000_billing_us2_payment_rpcs.sql`, `backend/tests/billing_crud.sql` |
| **Evidence** | `void_invoice` permits `status IN ('issued', 'partially_paid')`. No check that `sum(payments.amount) = 0` or mandatory `record_refund` before void. `UPDATE` sets `status = 'voided'` but **does not** reverse or flag existing payment rows. Test `void_partially_paid_invoice_succeeds` expects this behavior. |
| **Why it is a problem** | Staff with `invoices.void` can collect partial cash (`record_payment`), void the invoice, and leave positive payment rows attached to a voided invoice. Error text says "Refund paid invoices first" but only blocks **fully** `paid` status. |
| **Potential impact** | Revenue reconciliation gaps; cash handling without audit trail tie to active invoice; potential internal fraud vector. |
| **Recommended solution** | Require `compute_invoice_balance = 0` OR auto-insert offsetting refund payments on void; alternatively block void when `sum(payments.amount) > 0`. |

---

## Recommended Remediation Priority

| Priority | Action | IDs |
|----------|--------|-----|
| P0 | Remove Postgres host port publish; enforce non-default password | C-03 |
| P0 | Document `soap_notes` recovery; fix migration ordering for greenfield backfill | C-04 |
| P0 | Fix JWT secret ↔ anon/service key coherence; add sign-in validation | H-26 |
| P0 | Re-grant `auth_internal.bootstrap_finish_setup` on 12-param signature | H-31 |
| P0 | Grant `auth_internal.admin_update_staff_username` to `authenticated` | H-32 |
| P1 | Migration: Realtime publication for `appointments` | H-27 |
| P1 | Switch PostgREST to `authenticator` DB role | H-28 |
| P1 | Resolve pre-request/seed coupling | H-29 |
| P1 | Grant regression + PostgREST smoke for billing, shifts, catalog | H-30 |
| P1 | Replace `jwt_staff_role()` in RLS with live staff row lookups | H-33 |
| P1 | Branch-scope validation on `transfer_patient` | H-34 |
| P1 | Atomic stale checks on `update_patient` | H-37 |
| P1 | Exclusion constraint or row locks for appointment doctor overlap | H-39 |
| P1 | Define void semantics: block or auto-refund when payments exist | H-41 |
| P2 | Org-alignment constraints on `invoice_items.service_id`, `invoices`, `shifts` | H-35, H-36 |
| P2 | `FOR UPDATE` on `service_branches` in configure/promotion RPCs | H-38 |
| P2 | Lock or constrain shift staff overlap | H-40 |

---

## Cumulative Finding Count (All Passes)

| Severity | 1st pass | 2nd pass (new) | 3rd pass (new) | Open total |
|----------|----------|----------------|----------------|------------|
| Critical | 2 | 0 | 2 | **4** |
| High | 19 | 6 | 16 | **41** |

---

*End of third-pass synthesis. Medium/Low findings omitted per pass scope.*
