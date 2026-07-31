# Backend Architecture Review — Second Pass (Skeptical)

**Third pass:** [backend-architecture-review-third-pass.md](./backend-architecture-review-third-pass.md) (new Critical/High only, 2026-07-05)

**Date:** 2026-07-05  
**Scope:** Full `backend/` tree — 154 SQL migrations, 50+ test files, local Docker/Kong stack, CI workflow  
**Prior art:** [backend-architecture-review.md](./backend-architecture-review.md) (first-pass synthesis, 2026-07-05)  
**Next:** [backend-architecture-review-third-pass.md](./backend-architecture-review-third-pass.md) (third-pass synthesis, 2026-07-05 — 2 new Critical, 16 new High)  
**Method:** Independent file-by-file review with cross-artifact validation; first-pass items re-verified in source, not repeated unless still present with new evidence.

---

## Executive Summary

The AiClinic backend remains a **PostgreSQL + PostgREST + GoTrue** stack with a consistent **RLS + `auth_internal` SECURITY DEFINER RPC** mutation model. That pattern is sound where applied completely. This second pass **confirms all two critical and nineteen high-severity findings** from the first review still exist in current migrations, and adds **six new high**, **seven new medium**, and **four new low** findings the first pass did not cover.

The highest-risk cluster is unchanged: **PostgREST can PATCH sensitive tables** (`staff_members`, `organizations`, `branches`) around RPC guards, and **INVOKER wrapper chains for billing, shifts, and service catalog lack `auth_internal` EXECUTE grants**, so production PostgREST calls fail while superuser SQL tests pass.

New concerns center on **branch-level patient privacy** (org-wide RLS SELECT and `assert_org_patient` without branch checks), **asymmetric staff-provisioning validation** (`create_staff_account` vs `update_staff_member`), **extended grant gaps on service-catalog pricing RPCs**, **July migration churn** (encounter-workspace features added then removed within days), and **Kong rate-limiting gaps** on storage/realtime routes.

**Finding counts (this document):**

| Severity | Confirmed from 1st pass | New in 2nd pass | Total |
|----------|-------------------------|-----------------|-------|
| Critical | 2 | 0 | 2 |
| High | 19 | 6 | 25 |
| Medium | 6 | 7 | 13 |
| Low | 3 | 4 | 7 |

---

## Relationship to First-Pass Review

| First-pass ID | Status (2026-07-05 code) | Second-pass notes |
|---------------|--------------------------|-------------------|
| C-01 staff_members RLS UPDATE | **Still present** | Re-verified in `20260521100000_auth_rbac_supabase_linter_fixes.sql:118-136` |
| C-02 service catalog auth_internal grants | **Still present** | Grep across all migrations: zero `GRANT EXECUTE ON FUNCTION auth_internal.create_service` (or billing/shift equivalents) |
| H-01..H-19 | **All still present** | See confirmed subsections below |
| M-01..M-06 | **All still present** | `assert_one_active_invoice_per_visit` exists but is never called (new evidence, M-12) |
| L-01..L-03 | **Still present** | |
| Teardown / dev_reset | **Still present, worsened** | 7+ `delete_clinic_operational_dependents` redefinitions in July 2026 alone (H-20) |
| Encounter workspace teardown | **Resolved by table drops** | `visit_plan_details` / `diagnosis_codes` dropped in `20260705120000` / `20260702120000`; transient FK risk no longer applies |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Flutter Desktop (Supabase SDK)                                         │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ JWT + custom claims (get_custom_claims hook)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Kong (:54321)  →  PostgREST  →  GoTrue  →  Storage API  →  Realtime   │
│  Rate limit: auth (30/min), rest (60/min) — storage/realtime: NONE      │
│  PGRST_DB_PRE_REQUEST: local_dev_pre_request (seed.sql only)            │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  public schema (RLS + thin SECURITY INVOKER RPC wrappers)               │
│  auth_internal schema (SECURITY DEFINER business logic + audit)         │
│  storage.objects (visit-attachments bucket policies)                    │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
                    PostgreSQL 15 (Supabase image)
```

**Module boundaries (by migration cluster):**

| Domain | Schema tables | Mutation path | Test runner |
|--------|---------------|---------------|-------------|
| Auth/RBAC | organizations, branches, staff_*, roles_permissions | RPC + **leaky RLS on 3 core tables** | `run_auth_backend_tests.sh`, inline in master |
| Patients | patients | RPC-only UPDATE; **org-wide SELECT** | `run_patient_management_tests.sh` |
| Appointments | appointments | RPC-only mutations | `run_appointment_management_tests.sh` |
| Visits / documentation | visits, soap_notes, visit_clinical_notes, … | RPC-only mutations | `run_visit_medical_records_tests.sh` |
| Encounter workspace (reduced) | patient_allergies, patient_medications, patient_chronic_conditions | RPC + grants present | nested in visit suite |
| Billing | invoices, invoice_items, payments, … | RPC-only mutations; **missing auth_internal grants** | `run_billing_tests.sh` |
| Service catalog | services, service_branches | RPC-only mutations; **missing auth_internal grants** | `run_service_catalog_tests.sh` |
| Shifts | shifts, shift_assignments | RPC-only mutations; **missing auth_internal grants** | `run_shift_management_tests.sh` |

**Dependency flow:** Client → `public.*` INVOKER wrapper → `auth_internal.*` DEFINER → tables + `audit_log`. RLS governs direct PostgREST table access. INVOKER wrappers require explicit `GRANT EXECUTE` on each underlying `auth_internal` function for the `authenticated` role.

---

## 1. Critical Issues

### C-01 — `staff_members` RLS UPDATE allows role escalation via PostgREST PATCH *(CONFIRMED)*

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files involved** | `backend/supabase/migrations/20260521100000_auth_rbac_supabase_linter_fixes.sql`, `backend/supabase/migrations/20260611170000_restore_last_administrator_guard.sql` |
| **Evidence** | `staff_members_update` at `20260521100000:118-136` permits UPDATE when the target shares any branch in the caller's org. `WITH CHECK` only enforces `is_deleted = false` — no restriction on `role`, `is_bootstrap_admin`, `is_active`, or `auth_user_id`. Guarded RPC `auth_internal.update_staff_member` at `20260611170000:51+` is bypassed. |
| **Why it is a problem** | Any staff member who can see a colleague via shared branch membership can PATCH `role=administrator` through PostgREST. |
| **Potential impact** | Privilege escalation; last-administrator guard bypass; full tenant compromise. |
| **Recommended solution** | Set `staff_members_update` to `USING (false)`. Add regression test: authenticated PATCH on `staff_members` must fail. |

---

### C-02 — Service catalog `auth_internal` EXECUTE grants missing *(CONFIRMED + EXTENDED)*

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files involved** | `backend/supabase/migrations/20260525120200_fix_restrict_auth_internal_grants.sql`, `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql`, `backend/supabase/migrations/20260712091000_service_catalog_pricing_rpcs.sql`, `backend/supabase/migrations/20260712091500_service_catalog_billing_integration.sql` |
| **Evidence** | Blanket revoke at `20260525120200:4-7`. Service-catalog migrations grant only `auth_internal.staff_has_services_read_access()` (`20260712090000:228`) and `public.*` wrappers (`20260712090500:1544-1552`). `public.create_service` is `SECURITY INVOKER` calling `auth_internal.create_service` — repository-wide grep finds **no** `GRANT EXECUTE ON FUNCTION auth_internal.create_service`. Pricing wrappers (`get_service`, `list_services`, `search_eligible_services`, `resolve_effective_service_price`) at `20260712091000` grant **only** `public.*` — also no `auth_internal` grants. |
| **Why it is a problem** | PostgREST runs as `authenticated`; INVOKER wrappers need EXECUTE on underlying definer functions. |
| **Potential impact** | Entire service catalog (CRUD, pricing, billing integration) non-functional via API; SQL tests as `postgres` superuser mask this. |
| **Recommended solution** | One migration granting EXECUTE on every `auth_internal.*` function referenced by a public INVOKER wrapper. Add `service_catalog_grants.sql` regression test modeled on `appointment_management_grants.sql`. |

---

## 2. High Priority Issues

### Confirmed from first pass (still present)

| ID | Summary | Primary evidence |
|----|---------|------------------|
| H-01 | Organizations direct UPDATE bypasses RPC | `20260516100200:154-158` |
| H-02 | Branches direct UPDATE bypasses RPC | `20260516100200:178-186`; tests use direct UPDATE at `org_branch_management_extended.sql:247` |
| H-03 | Legacy `add_invoice_item` free-text path active | `20260605180500:1063`; plan.md retires it |
| H-04 | `build_staff_claims(uuid)` callable by any authenticated user | `20260525120200:13`; test at `auth_rbac_extended.sql:212-241` |
| H-05 | Teardown logic duplicated, regressed before | 15+ `dev_reset_*` / `delete_clinic_*` patch migrations |
| H-06 | Missing `ON DELETE CASCADE` on core FKs | `20260516100000:91`, `20260523140000:14`, etc. |
| H-07 | No DB constraint linking `patients.branch_id` to `patients.organization_id` | `20260523140000:12-28`; RPC-only runtime check |
| H-08 | `service_branches` allows cross-org assignment at DB level | `20260712090000:62-65` |
| H-09 | Billing `auth_internal` EXECUTE grants missing | Only RLS helpers granted at `20260605180400:2-4`; INVOKER at `20260605180500:982+` |
| H-10 | Shift `auth_internal` EXECUTE grants missing | Only `staff_has_shifts_manage()` at `20260606180000:1188-1189` |
| H-11 | `run_all_backend_tests.sh` omits appointment QA suites | Lines 97-102 omit `appointment_queue_qa.sql`, `appointment_calendar_backend_integrity.sql` |
| H-12 | Test runner suppresses `psql` stderr | `run_all_backend_tests.sh:34,48` |
| H-13 | SQL tests run as `postgres` superuser | `run_all_backend_tests.sh:22`; documented in `appointment_management_grants.sql:4-6` |
| H-14 | COMMIT/ROLLBACK pollution across test files | 50+ test files use explicit `COMMIT` or `ROLLBACK` |
| H-15 | "Concurrency" tests are sequential | `billing_concurrency.sql:233-249` |
| H-16 | GoTrue HTTP sign-in soft-fails in smoke tests | `auth_flow_smoke.sh:94-98` |
| H-17 | CI runs only Flutter | `.github/workflows/ci.yml` — single `frontend-quality` job |
| H-18 | Docker Compose does not apply migrations | `local/docker-compose.yml:17-18` mounts only `init.sql` |
| H-19 | Open signup in local auth config | `local/docker-compose.yml:35` `GOTRUE_DISABLE_SIGNUP: "false"` |

---

### H-20 — Patients readable org-wide via RLS and `get_patient`; no branch isolation *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260523140000_patient_management.sql`, `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql` |
| **Evidence** | `patients_select` RLS at `20260523140000:50-56` filters only `organization_id = jwt_organization_id()` — **no** `branch_id` check. `auth_internal.assert_org_patient` at `20260523140000:184-219` validates org membership only, not branch. `get_patient` uses `assert_org_patient` at `396`. By contrast, encounter workspace uses `assert_patient_branch_scope` at `20260701120000:282-305` which calls `staff_can_access_branch(p.branch_id)`. |
| **Why it is a problem** | In multi-branch clinics, any staff with `patients.view` (or direct PostgREST SELECT) can read patients registered at branches they are not assigned to — phone, national ID, notes. |
| **Potential impact** | Cross-branch PII disclosure; regulatory/privacy violation for segregated branches. |
| **Recommended solution** | Add branch predicate to `patients_select` (or `staff_can_access_branch(branch_id)`). Update `assert_org_patient` / `get_patient` to enforce branch scope consistently with encounter RPCs. Add RLS regression test: receptionist at branch A cannot SELECT patient at branch B. |

---

### H-21 — `create_staff_account` branch validation not scoped to caller organization *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260613150000_create_staff_account_phone.sql`, `backend/supabase/migrations/20260611170000_restore_last_administrator_guard.sql` |
| **Evidence** | `create_staff_account` branch check at `20260613150000:61-75` validates branches exist in **any** non-deleted organization (`b.organization_id IN (SELECT o.id FROM organizations o …)`). `update_staff_member` at `20260611170000:104-111` explicitly rejects `b.organization_id != v_org_id` with `CROSS_ORG_DENIED`. |
| **Why it is a problem** | Asymmetric validation: create path can assign foreign-org branches if multiple orgs exist (tests, migration residue, future multi-tenant). |
| **Potential impact** | Staff provisioned into wrong org branches; cross-tenant assignment in shared DB scenarios. |
| **Recommended solution** | Align create with update: require `b.organization_id = public.jwt_organization_id()` for every `p_branch_ids` entry. |

---

### H-22 — Service catalog **pricing** RPCs missing `auth_internal` grants *(NEW — extends C-02)*

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260712091000_service_catalog_pricing_rpcs.sql` |
| **Evidence** | INVOKER wrappers call `auth_internal.get_service`, `resolve_effective_service_price_rpc`, `search_eligible_services`, `list_services` (lines 9, 198, 285, 399). Grants section (lines 98, 279, 393, 569) grants **only** `public.*` functions. No `GRANT EXECUTE ON FUNCTION auth_internal.*` in this file or any later migration. |
| **Why it is a problem** | Invoice service selector and price preview fail under PostgREST even if CRUD RPCs are fixed later. |
| **Potential impact** | Billing catalog integration broken end-to-end in production path. |
| **Recommended solution** | Include pricing `auth_internal` functions in the grant migration and grant regression test. |

---

### H-23 — July 2026 teardown churn: repeated `delete_clinic_operational_dependents` replacements *(NEW — extends H-05)*

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `20260702120000_remove_coded_diagnosis.sql`, `20260705120000_remove_structured_plan_outputs.sql`, `20260706120000_dev_reset_delete_patient_health_records.sql`, `20260710130000_fix_delete_clinic_test_fixtures_shifts.sql`, `20260712100000_fix_dev_reset_orgs_before_auth_users.sql` |
| **Evidence** | `delete_clinic_operational_dependents` fully replaced at least **5 times** in 10 days. `20260710130000:1-2` comment documents shift regression when visit migrations replaced teardown without shift rows. `20260705120000` removes `visit_plan_details` handling that `20260702120000` had just added. |
| **Why it is a problem** | Each feature/revert migration copy-pastes teardown; order drifts; tests using `delete_clinic_test_fixtures` vs `dev_reset` see different coverage. |
| **Potential impact** | FK failures during dev_reset; orphaned rows; false test passes. |
| **Recommended solution** | Single teardown registry function; CI check that all FK child tables appear in teardown; block feature migrations from redefining the whole function. |

---

### H-24 — `assert_patient_branch_scope` granted directly to `authenticated` *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql` |
| **Evidence** | `GRANT EXECUTE ON FUNCTION auth_internal.assert_patient_branch_scope(uuid) TO authenticated` at line 2035. Function is `SECURITY DEFINER` (`282-305`) returning full `patients` row when branch access succeeds. |
| **Why it is a problem** | Exposes internal definer helper on `auth_internal` schema to clients; violates the project's own grant-restriction pattern (`20260525120200`). Enables direct probing of patient existence within accessible branches outside RPC audit envelopes. |
| **Potential impact** | Expanded attack surface; harder to evolve internal API; inconsistent with other revoked internal helpers (e.g. `assign_invoice_number` revoked at `20260605180000:869`). |
| **Recommended solution** | Revoke `authenticated` EXECUTE; keep scope checks inside public RPCs only. |

---

### H-25 — `dev_seed_*` and `public.dev_seed_*` remain granted to `authenticated` *(NEW — extends M-04)*

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260628200000_dev_seed_medications_catalog.sql`, `backend/supabase/migrations/20260628210000_dev_seed_investigations_catalog.sql`, `backend/supabase/migrations/20260711120000_coderabbit_review_fixes.sql` |
| **Evidence** | Grants at `20260628200000:72-73` and `20260628210000:72-73` remain after coderabbit fail-closed body updates (`20260711120000:564-580`). Any authenticated bootstrap admin can invoke when `app.environment` is set (via `seed.sql` `local_dev_pre_request`). |
| **Why it is a problem** | Catalog pollution / DoS via bulk inserts; relies on environment string + bootstrap check, not role isolation. |
| **Potential impact** | Unauthorized catalog mutation on shared dev/staging if pre-request runs. |
| **Recommended solution** | Revoke `authenticated` grants; restrict to `postgres` / `service_role` or drop public wrappers entirely. |

---

## 3. Medium Priority Issues

### Confirmed from first pass

| ID | Summary | Evidence |
|----|---------|----------|
| M-01 | Invoice `currency` defaults to `USD` | `20260605180000:75`; `create_invoice_from_visit` omits currency |
| M-02 | `create_invoice_from_visit` TOCTOU race | Check-then-insert at `20260605180500:149-182`; no partial unique index |
| M-03 | Shifts use `deleted_at`; rest uses `is_deleted` | `20260606180000:9-25` |
| M-04 | `dev_seed_*` weaker guard when `app.environment` unset | Fail-closed improved in coderabbit but grants remain (see H-25) |
| M-05 | `cleanup_audit_log` return type `jsonb` vs `rpc_result` | `20260524110300:8-9` |
| M-06 | `PGRST_DB_PRE_REQUEST` only in `seed.sql` | `seed.sql:7-14`; compose does not run seed |

### M-07 — Kong rate limiting absent on storage and realtime routes *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `backend/local/kong.yml` |
| **Evidence** | `auth` (lines 13-18) and `rest` (lines 29-35) have `rate-limiting` plugins. `storage` (lines 37-43) and `realtime` (lines 45-51) have **no** plugins. |
| **Why it is a problem** | Attachment upload/download and websocket endpoints can be abused for DoS on clinic LAN gateways. |
| **Potential impact** | Resource exhaustion; degraded clinic operations. |
| **Recommended solution** | Add rate-limiting plugins to storage and realtime; tune limits for LAN profile. |

---

### M-08 — `audit_log` readable org-wide by all authenticated staff *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `backend/supabase/migrations/20260516100200_auth_rbac_rls.sql`, `backend/supabase/migrations/20260521100000_auth_rbac_supabase_linter_fixes.sql` |
| **Evidence** | `audit_log_select` at `20260516100200:278-287` and `20260521100000:138-148` allows SELECT when `organization_id = jwt_organization_id()` — any org member, not just administrators. |
| **Why it is a problem** | Receptionists can read audit entries for staff password resets, role changes, billing voids, dev_reset actions. |
| **Potential impact** | Over-broad visibility of sensitive operational metadata. |
| **Recommended solution** | Restrict org-wide audit SELECT to `settings.view_audit` permission or administrator role; keep self-action visibility for all roles. |

---

### M-09 — Encounter-workspace feature churn creates spec/schema drift *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `20260701120000_visit_encounter_workspace.sql`, `20260702120000_remove_coded_diagnosis.sql`, `20260705120000_remove_structured_plan_outputs.sql`, `backend/tests/visit_encounter_workspace_*.sql` |
| **Evidence** | July 1 migration adds `diagnosis_codes`, `visit_diagnosis_codes`, `visit_plan_details`, and RPCs. July 2 drops diagnosis tables/RPCs. July 5 drops `visit_plan_details` and `save_visit_plan_details`. Tests still named `visit_encounter_workspace_*` but no longer cover removed surfaces. |
| **Why it is a problem** | Documentation, Flutter contracts, and tests diverge from live schema within days; increases regression risk. |
| **Potential impact** | Client calls removed RPCs; developers trust stale spec docs. |
| **Recommended solution** | Update spec 014 docs to reflect reduced scope; rename tests; add migration comment block listing active encounter tables. |

---

### M-10 — README migration instructions disagree with Docker Compose path *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `backend/README.md`, `backend/local/docker-compose.yml` |
| **Evidence** | README lines 6-8 recommend `supabase db reset` / `supabase migration up`. Compose stack mounts only `init.sql` (`docker-compose.yml:17-18`) with no migration runner. |
| **Why it is a problem** | Developers following README on Compose get empty schema; following Compose README gets roles only. |
| **Potential impact** | Onboarding failures; "works on my machine" when migration apply method differs. |
| **Recommended solution** | Document two explicit paths (CLI vs Compose) with required migration apply steps for each. |

---

### M-11 — Org catalog tables writable by any staff with `visits.edit_soap` *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`, `backend/supabase/migrations/20260711120000_coderabbit_review_fixes.sql` |
| **Evidence** | `create_catalog_medication` / `create_catalog_investigation` require only `assert_permission('visits.edit_soap')` (`20260628140000:865`, coderabbit rewrite `20260711120000:99`). RLS blocks direct INSERT (`medications_insert` `WITH CHECK (false)`). |
| **Why it is a problem** | Doctors can permanently add arbitrary medication/investigation names to org catalog during documentation — no admin gate, no dedup review. |
| **Potential impact** | Catalog pollution; autocomplete noise; duplicate entries. |
| **Recommended solution** | Separate `catalog.manage` permission or restrict catalog creation to administrators; keep visit-line free-text for doctors. |

---

### M-12 — `assert_one_active_invoice_per_visit` defined but unused *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `backend/supabase/migrations/20260605180000_billing.sql`, `backend/supabase/migrations/20260605180500_billing_us1_rpcs.sql` |
| **Evidence** | Helper created at `20260605180000:742+`, revoked from authenticated at `:865`. `create_invoice_from_visit` uses inline `IF EXISTS` (`20260605180500:149-160`) instead of helper or unique index. Grep shows zero calls to `assert_one_active_invoice_per_visit` outside its definition. |
| **Why it is a problem** | Suggests incomplete refactor; TOCTOU race (M-02) remains; dead security code misleads reviewers. |
| **Potential impact** | Duplicate active invoices under concurrency. |
| **Recommended solution** | Add partial unique index on `(visit_id) WHERE status <> 'voided' AND is_deleted = false`; call helper inside `create_invoice_from_visit` or remove dead helper. |

---

### M-13 — Storage bucket lacks DELETE/UPDATE policies for `authenticated` *(NEW — informational)*

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `backend/supabase/migrations/20260531180000_visit_medical_records.sql`, `backend/supabase/migrations/20260601160000_fix_visit_storage_folder_depth.sql` |
| **Evidence** | Only `visit_attachments_storage_insert` and `visit_attachments_storage_select` policies exist. No storage DELETE policy for clients. Deletes go through `auth_internal.delete_visit_attachment` with `storage.allow_delete_query` (`20260711190000:65-84`). |
| **Why it is a problem** | Correct by design, but undocumented; developers may expect Storage API delete to work. |
| **Potential impact** | Confusion; accidental reliance on direct storage delete in client code. |
| **Recommended solution** | Document that attachment deletion is RPC-only; add negative test attempting direct storage delete. |

---

## 4. Low Priority Issues

| ID | Summary | Status | Evidence |
|----|---------|--------|----------|
| L-01 | Grant regression tests only for appointments | CONFIRMED | `appointment_management_grants.sql` only |
| L-02 | Deferred auth tests documented, not implemented | CONFIRMED | `README_DEFERRED_TESTS.md:6-10` |
| L-03 | `add_invoice_item` retirement in plan, not enforced | CONFIRMED | plan.md:13 vs `20260605180500:1063` |
| L-04 | `validate_local_stack.sh` / `connectivity_smoke.sh` not in master runner | **NEW** | Not referenced in `run_all_backend_tests.sh` |
| L-05 | `seed_organization_catalog_defaults` grant revoked but trigger remains | **NEW** | Revoke at `20260711120000:7`; trigger `seed_organization_catalog_defaults` on organizations from `20260703120000:22-26` still fires internally |
| L-06 | Visit medical records sub-runner shows psql errors; master runner does not | **NEW** | `run_visit_medical_records_tests.sh:36` vs `run_all_backend_tests.sh:34` |
| L-07 | 10+ `coderabbit_review_fixes_*` migrations increase review surface | **NEW** | `20260711120000` through `20260711210000` — hard to audit atomic intent |

---

## 5. Migration Issues

| ID | Issue | Evidence | Recommendation |
|----|-------|----------|----------------|
| MI-01 | 15+ patches to `dev_reset_clinic_installation` | `20260521140000` through `20260712100000` | Consolidate; table-driven delete registry |
| MI-02 | `delete_clinic_operational_dependents` redefined 5× in July 2026 | `20260702120000`, `05120000`, `06120000`, `10130000`, plus encounter inline | Single source of truth; CI FK-child parity test |
| MI-03 | `seed.sql` functions not in migrations | `seed.sql:7-29` vs 154 migrations | Migrate `local_dev_pre_request` or compose seed step |
| MI-04 | Grant migrations not co-located with feature RPCs | Service catalog, billing, shifts | End each feature migration with explicit `auth_internal` GRANT block |
| MI-05 | Feature add/remove within days (encounter workspace) | `01120000` → `02120000` → `05120000` | Feature flags or single squashed migration per release |
| MI-06 | **NEW:** Transient FK hazard pattern | Between `01120000` and `05120000`, `dev_reset` deleted `visits` before `visit_plan_details` | For future tables: always add teardown in same migration as CREATE |
| MI-07 | **NEW:** `remove_coded_diagnosis` drops functions but encounter migration seeds remain in history | `20260701120000:2083+` seeds `diagnosis_codes`; table dropped `20260702120000:533` | Squash or document one-time data migration path |

---

## 6. Configuration Issues

| ID | Issue | Evidence | Recommendation |
|----|-------|----------|----------------|
| CF-01 | Open signup | `docker-compose.yml:35` | `GOTRUE_DISABLE_SIGNUP: "true"` except solo dev |
| CF-02 | Pre-request not applied without seed | `docker-compose.yml:57`, `seed.sql:7-14` | Auto-run seed or migrate function |
| CF-03 | Compose lacks migration automation | `docker-compose.yml:17-18` | Add migrate init container |
| CF-04 | JWT hook URI hardcoded | `docker-compose.yml:42` | Validate in `validate_local_stack.sh` |
| CF-05 | `app.environment` unset blocks dev_reset in prod | By design | Ensure pre-request never runs in prod |
| CF-06 | **NEW:** Kong storage/realtime unrate-limited | `kong.yml:37-51` | Add rate-limiting plugins |
| CF-07 | **NEW:** README vs Compose migration path split | `backend/README.md:6-8` vs compose | Unify documentation |

---

## 7. Test Coverage Gaps

| Area | Covered | Gap (incl. new) |
|------|---------|-----------------|
| Auth / RBAC | jwt contract, extended, isolation | **No PATCH escalation test for `staff_members`** |
| Org / Branch | CRUD, RLS | Direct UPDATE bypass not tested as vulnerability |
| Patients | CRUD, RLS, search | **No cross-branch SELECT denial within same org (H-20)** |
| Appointments | CRUD, RLS, grants | `appointment_queue_qa.sql`, `appointment_calendar_backend_integrity.sql` omitted |
| Billing | CRUD, RLS, pseudo-concurrency | No grant regression; no true parallel payment race |
| Service Catalog | CRUD, RLS, pricing, pseudo-concurrency | No grant regression; pricing `auth_internal` grants untested |
| Shifts | CRUD, RLS, pseudo-concurrency | No grant regression |
| Visits | Sub-suite via `run_visit_medical_records_tests.sh` | Encounter workspace reduced scope not reflected in test names |
| Infrastructure | `validate_local_stack.sh`, `connectivity_smoke.sh` | **Not in master runner (L-04)** |
| Auth E2E | `auth_flow_smoke.sh` with soft-fail | GoTrue failures non-blocking |
| Staff provisioning | `create_staff_rpc.sql` | **No cross-org branch rejection on create (H-21)** |
| INVOKER grant chain | `appointment_management_grants.sql` only | Billing, shifts, catalog, pricing lack equivalent |

---

## 8. Security Concerns

| Concern | Severity | Summary |
|---------|----------|---------|
| Role escalation via RLS | Critical | `staff_members` PATCH bypasses RPC guards (C-01) |
| Missing invoker grants | Critical/High | PostgREST path broken; tests give false positives (C-02, H-09, H-10, H-22) |
| Cross-user claims disclosure | High | `build_staff_claims(any_uuid)` callable by authenticated (H-04) |
| Direct table mutation | High | `organizations`, `branches` UPDATE too permissive (H-01, H-02) |
| Cross-branch patient reads | High | Org-wide `patients` SELECT + `get_patient` (H-20) |
| Staff create branch scope | High | `create_staff_account` lacks org guard on branches (H-21) |
| Internal definer exposure | High | `assert_patient_branch_scope` granted to authenticated (H-24) |
| Open signup | High | Arbitrary auth user creation on shared environments (H-19) |
| Legacy billing bypass | High | Free-text invoice items bypass catalog (H-03) |
| Dev seed grants | High | `dev_seed_*` still callable by authenticated (H-25) |
| Audit log over-read | Medium | All org staff can read org audit entries (M-08) |
| Storage/realtime DoS | Medium | No Kong rate limits (M-07) |
| Superuser test execution | High | RLS and GRANT holes not exercised (H-13) |

---

## 9. Performance Concerns

| Concern | Evidence | Notes |
|---------|----------|-------|
| Audit log growth | Append-only `audit_log`; cleanup RPC return type inconsistent (M-05) | Schedule retention job |
| Patient search | Indexes in `20260525120700_fix_search_indexes.sql` | Monitor under load |
| Invoice number assignment | `assign_invoice_number` uses UPDATE on sequence row (`20260605180000:847-856`) | Row-level lock per branch — acceptable for V1 |
| Org-wide patient SELECT | No branch predicate on `patients_select` | Large orgs: wider scans than necessary (H-20) |
| Sequential concurrency tests | H-15 | Does not validate lock contention |
| Catalog autocomplete | `search_eligible_services` resolves price per row (`20260712091000:365`) | N+1 resolution pattern; monitor at 2k services |

*No new critical throughput blockers; risks remain correctness, security, and privacy.*

---

## 10. Architectural Improvements

1. **RPC-only mutations universally** — Set UPDATE (and INSERT where applicable) to `USING (false)` on `staff_members`, `organizations`, `branches` (pattern already on `patients`, `services`, billing tables).

2. **Grant checklist per feature** — Every `public` INVOKER wrapper → `GRANT EXECUTE ON auth_internal.* TO authenticated` in same migration + SQL grant regression file.

3. **Branch-scoped patient access model** — Decide org-wide vs branch-default; align RLS, `assert_org_patient`, `search_patients`, and PostgREST SELECT.

4. **Unified teardown registry** — Stop redefining `delete_clinic_operational_dependents` in feature migrations; append to ordered table list.

5. **CI backend gate** — Linux job: compose up, apply migrations, `run_all_backend_tests.sh`, `validate_local_stack.sh`.

6. **Test harness hardening** — Surface psql errors; split superuser fixtures from authenticated assertions; add INVOKER grant tests per domain.

7. **Reduce migration churn** — Squash or document revert migrations; keep spec/tests in sync when dropping tables.

8. **Kong hardening** — Rate-limit storage/realtime; require GoTrue sign-in in CI smoke tests.

9. **Revoke internal helpers from authenticated** — `assert_patient_branch_scope`, `build_staff_claims(uuid)`, `dev_seed_*`.

10. **Symmetric staff provisioning validation** — `create_staff_account` must match `update_staff_member` org-branch guards.

---

## Verified Correct Areas

These were re-checked in second pass with concrete evidence:

- **RLS deny-by-default on billing mutations** — `invoices_update` `USING (false)` (`20260605180000:348-351`); `invoice_items_insert` `WITH CHECK (false)`.
- **Service catalog direct DML blocked** — `services_update` / `service_branches_insert` use `false` (`20260712090000:163-166, 192-195`).
- **Patient/appointment/visit/shift direct mutations blocked** — `patients_update`, `appointments_update`, `visits_update`, `shifts_update` all `USING (false)`.
- **Appointment grant regression test** — `appointment_management_grants.sql` documents superuser bypass and checks `has_function_privilege`.
- **Visit encounter workspace grants** — Unlike catalog/billing, `20260701120000:2035-2077` grants `auth_internal` EXECUTE for encounter RPCs (positive contrast).
- **`update_staff_member` cross-org branch guard** — `20260611170000:104-114` rejects foreign-org branches.
- **`seed_organization_catalog_defaults` restricted** — `REVOKE` from authenticated at `20260711120000:7`.
- **Encounter patient safety uses branch scope** — `get_patient_safety_context` calls `assert_patient_branch_scope` (`20260701120000:342`).
- **Invoice number sequences RLS denied** — `invoice_number_sequences_deny` (`20260605180000:477-478`).
- **Dev reset environment gate** — `20260712100000:22-27` blocks when `app.environment` not in dev/local/test.
- **Storage insert policy uses branch access helper** — `staff_can_access_branch` in `20260601160000:11`.
- **Shift table column grants** — `REVOKE INSERT, UPDATE, DELETE` at `20260606180000:129`.

---

## Recommended Remediation Priority

### P0 — Immediate

| # | Action | Addresses |
|---|--------|-----------|
| 1 | Lock `staff_members_update` to RPC-only | C-01 |
| 2 | Add all missing `auth_internal` EXECUTE grants (catalog CRUD + pricing, billing, shifts) | C-02, H-09, H-10, H-22 |
| 3 | Lock `organizations_update` / `branches_update` to RPC-only | H-01, H-02 |
| 4 | Revoke `authenticated` on `build_staff_claims(uuid)` | H-04 |

### P1 — This sprint

| # | Action | Addresses |
|---|--------|-----------|
| 5 | Branch-scope `patients_select` and `assert_org_patient` | H-20 |
| 6 | Fix `create_staff_account` org branch validation | H-21 |
| 7 | Revoke `assert_patient_branch_scope` + `dev_seed_*` from authenticated | H-24, H-25 |
| 8 | Add grant regression tests for billing, shifts, catalog | L-01, H-13 |
| 9 | Add omitted appointment tests; surface psql errors | H-11, H-12 |
| 10 | Partial unique index + use `assert_one_active_invoice_per_visit` | M-02, M-12 |

### P2 — Next sprint

| # | Action | Addresses |
|---|--------|-----------|
| 11 | Consolidate teardown; CI FK-child parity test | H-05, H-23, MI-02 |
| 12 | Backend CI job | H-17 |
| 13 | Compose migration runner + seed step | H-18, M-06, CF-03 |
| 14 | Kong rate limits on storage/realtime | M-07, CF-06 |
| 15 | Restrict audit_log SELECT by permission | M-08 |
| 16 | Align encounter spec/tests with reduced schema | M-09 |

---

*End of second-pass review. All findings traced to `backend/supabase/migrations/` and `backend/tests/` as of 2026-07-05.*
