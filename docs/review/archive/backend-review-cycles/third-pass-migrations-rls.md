# Backend Review — Third Pass (MIGRATIONS & RLS)

**Date:** 2026-07-05  
**Scope:** All 154 SQL migrations in `backend/supabase/migrations/` — RLS policies, constraints, indexes, FKs, rollback safety, migration ordering, idempotency, destructive changes  
**Prior art:** [backend-architecture-review.md](./backend-architecture-review.md), [backend-architecture-review-second-pass.md](./backend-architecture-review-second-pass.md)  
**Method:** Full migration/RLS audit cross-checked against RPC table references; prior findings excluded unless new evidence or distinct impact.

*Synthesis doc renumbers C-04 and H-34–H-36 to avoid collision with config C-03 and config/auth H-26–H-30.*

---

## Executive Summary

This pass focused exclusively on **migrations, RLS, constraints, FKs, teardown ordering, and RPC↔schema alignment**. All 27 Critical/High items from the first two passes were re-verified and **not re-reported**.

**4 new Critical/High findings** (1 Critical, 3 High):

| ID | Severity | Summary |
|----|----------|---------|
| C-04 | Critical | `soap_notes` dropped without backfill; later backfill migration is dead code |
| H-34 | High | `transfer_patient` lacks branch-access validation on source/target |
| H-35 | High | `invoice_items.service_id` has no org-alignment constraint with parent invoice |
| H-36 | High | `invoices` / `shifts` lack DB constraint tying `organization_id` to `branch_id` |

---

## 1. Critical Issues

### C-04 — `soap_notes` destroyed at migration 28140000; backfill at 11120000 is unreachable dead code

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files involved** | `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`, `backend/supabase/migrations/20260711120000_coderabbit_review_fixes.sql` |
| **Evidence** | `20260628140000:67-90` creates `visit_clinical_notes` as replacement for `soap_notes`. `20260628140000:169` executes `DROP TABLE IF EXISTS public.soap_notes` with **no** `INSERT INTO visit_clinical_notes … SELECT FROM soap_notes`. Later, `20260711120000:522-557` wraps backfill in `IF to_regclass('public.soap_notes') IS NOT NULL` — but `soap_notes` was already dropped 11 migrations earlier, so this block never runs on a normal sequential apply. |
| **Why it's a problem** | Any database with existing `soap_notes` clinical documentation loses all subjective/objective/assessment/plan content permanently when `20260628140000` is applied. The later “fix” migration gives false confidence but cannot recover data. |
| **Potential impact** | Irreversible loss of visit clinical documentation on production/staging upgrade; regulatory/clinical record integrity failure. |
| **Recommended solution** | Add a new migration that cannot help already-upgraded DBs (document one-time manual recovery). For greenfield paths: squash or reorder so backfill runs **before** first `DROP TABLE soap_notes`. Pattern: `INSERT INTO visit_clinical_notes … SELECT … FROM soap_notes WHERE NOT EXISTS (…)` then `DROP TABLE`. Map `subjective→complaint`, `objective→examination`, `assessment→diagnosis`, `plan→plan` per `20260711120000:536-545`. Add migration test asserting row-count parity when `soap_notes` has seed data. |

---

## 2. High Priority Issues

### H-34 — `transfer_patient` allows cross-branch transfer without caller branch-access validation

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260524110200_fix_patient_transfer_restore.sql` |
| **Evidence** | Source patient resolved via `assert_org_patient` only (`:35`) — org scope, no branch check. Target branch validated for existence/active/same-org (`:56-68`) but **not** `staff_can_access_branch(p_new_branch_id)`. No check that caller can access the patient's current `branch_id`. Encounter RPCs added in `20260701120000` use `assert_patient_branch_scope` (`:282-305`) — asymmetric. |
| **Why it's a problem** | Staff with `patients.edit` at branch A can transfer any org patient (including from branch B they cannot access) to any active org branch, including branches they are not assigned to. Mutation path bypasses branch isolation that encounter workspace enforces. |
| **Potential impact** | Unauthorized cross-branch patient relocation; branch segregation policy bypass; audit trail shows transfer by staff without legitimate branch assignment. |
| **Recommended solution** | Before UPDATE: `PERFORM auth_internal.assert_patient_branch_scope(p_patient_id)` (or `staff_can_access_branch` on source branch). Require `staff_can_access_branch(p_new_branch_id)` on target. Add regression test: receptionist at branch A cannot transfer patient registered at branch B. |

---

### H-35 — `invoice_items.service_id` lacks DB constraint aligning service org with invoice org

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260712091500_service_catalog_billing_integration.sql`, `backend/supabase/migrations/20260605180000_billing.sql` |
| **Evidence** | `20260712091500:5-6` adds `invoice_items.service_id uuid REFERENCES public.services (id)` — no CHECK/trigger that `services.organization_id = invoices.organization_id`. RPC `add_invoice_item_from_service` validates at runtime (`:62-71`). `invoice_items_insert` is `WITH CHECK (false)` (`20260605180000:379`). Legacy `add_invoice_item` free-text path (`H-03`) can still insert rows without `service_id`. |
| **Why it's a problem** | Integrity depends entirely on RPC code. `SECURITY DEFINER` bugs, superuser paths, or future direct SQL can attach a foreign-org `service_id` to an invoice item, breaking catalog snapshot semantics. |
| **Potential impact** | Cross-org service references on invoice line items; incorrect pricing snapshots; reporting corruption. |
| **Recommended solution** | Add trigger `BEFORE INSERT OR UPDATE ON invoice_items` validating `service_id IS NULL OR (SELECT organization_id FROM services WHERE id = service_id) = (SELECT organization_id FROM invoices WHERE id = invoice_id)`. Add negative test attempting mismatched org link via superuser. |

---

### H-36 — `invoices` and `shifts` store independent `organization_id` + `branch_id` with no alignment constraint

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260605180000_billing.sql`, `backend/supabase/migrations/20260606180000_shift_management.sql` |
| **Evidence** | `invoices` at `20260605180000:63-64`: `organization_id` and `branch_id` are separate FKs with no CHECK that `branch.organization_id = invoices.organization_id`. `shifts` at `20260606180000:11-12`: same pattern. RPCs set both from branch lookup (`create_shift :705-706`, `create_invoice_from_visit` sets org from JWT and branch from visit). `patients` has the same gap (H-07); these tables were not called out. |
| **Why it's a problem** | Misaligned rows can be inserted via superuser, migration scripts, or future RLS gaps, producing invoices/shifts that belong to org A but reference branch B from org C. RLS on `invoices_select` uses `branch_id = ANY(jwt_branch_ids())` (`20260605180300:43`) — misaligned row could leak across tenants if `organization_id` check is omitted in a future policy change. |
| **Potential impact** | Cross-tenant data corruption; billing reports scoped wrong; shift schedules attached to wrong org metadata. |
| **Recommended solution** | Add composite CHECK or trigger on both tables: `organization_id = (SELECT organization_id FROM branches WHERE id = branch_id)`. Mirror H-07 remediation pattern. |

---

## 3. What Was Checked (No New Critical/High)

| Area | Checked | Result |
|------|---------|--------|
| RLS UPDATE bypass on `staff_members`, `organizations`, `branches` | C-01, H-01, H-02 | Still present — already reported |
| Missing `auth_internal` EXECUTE grants (billing, shifts, catalog, pricing) | C-02, H-09, H-10, H-22 | Still present — already reported |
| Org-wide `patients` SELECT / `assert_org_patient` | H-20 | Already reported |
| `create_staff_account` cross-org branch validation | H-21 | Remediated in `20260614100000` |
| `assert_patient_branch_scope` / `dev_seed_*` grants | H-24, H-25 | Already reported |
| Teardown churn in `delete_clinic_operational_dependents` / `dev_reset` | H-05, H-23 | Already reported |
| `service_branches` cross-org assignment | H-08 | Already reported |
| `patients.branch_id` ↔ `organization_id` alignment | H-07 | Already reported |
| Partial unique index `invoices_visit_active_unique` | `20260605180000:108-110` | Exists — M-02 overstated in prior reviews |
| Encounter workspace add/remove migrations | Drop functions/tables cleanly | No new finding |
| Chronic-condition RPC grant gap after signature change | `20260711160000:264-265` | Fixed |
| Vital-sign signature churn | `20260704120000:545-547` | Resolved |

---

## 4. Recommended Remediation (New Items Only)

| Priority | Action | ID |
|----------|--------|-----|
| P0 | Reorder or squash migrations so `soap_notes` backfill runs before first DROP; document recovery for already-upgraded DBs | C-04 |
| P1 | Add branch-access guards to `transfer_patient` | H-34 |
| P1 | Add org-alignment trigger on `invoice_items.service_id` | H-35 |
| P1 | Add org/branch alignment CHECK on `invoices` and `shifts` | H-36 |

---

## Finding Count

| Severity | New in third pass |
|----------|-------------------|
| Critical | **1** (C-04) |
| High | **3** (H-34 – H-36) |
| **Total** | **4** |

---

*End of third-pass review. Prior-pass IDs C-01..C-02, H-01..H-25 intentionally omitted.*
