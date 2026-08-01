# Backend Review — Third Pass (Business Logic & Transactions)

**Date:** 2026-07-05  
**Scope:** `auth_internal` business logic — billing, visits, appointments, patients, shifts, service catalog  
**Focus:** Transaction boundaries, race conditions, validation gaps, RPC vs RLS vs DTO assumptions, null handling  
**Prior art:** [backend-architecture-review.md](./backend-architecture-review.md), [backend-architecture-review-second-pass.md](./backend-architecture-review-second-pass.md)  
**Method:** Deep read of latest migration definitions for in-scope RPCs; cross-checked against prior finding IDs to avoid duplication.

---

## Executive Summary

This pass targeted **business logic correctness under concurrency** and **cross-layer consistency** in the six in-scope domains. Prior passes already covered RLS bypasses (C-01, H-01/H-02), grant chains (C-02, H-09/H-10/H-22), patient org-wide reads (H-20), staff provisioning (H-21), and infrastructure/test gaps (H-11–H-19).

This pass adds **five new High** findings, all in **optimistic-concurrency / check-then-act races** and **billing void semantics**:

| Severity | New in 3rd pass |
|----------|-----------------|
| Critical | 0 |
| High | 5 |

Billing payment recording (`record_payment` / `record_refund`) correctly uses `FOR UPDATE` via `lock_payable_invoice`. Invoice draft mutations use `lock_draft_invoice`. Appointment `in_progress` uniqueness is enforced by partial unique indexes. `invoices_visit_active_unique` prevents duplicate active invoices per visit at the DB level (mitigating M-02 data corruption, though the RPC still lacks `unique_violation` handling).

---

## 1. Critical Issues

*None new. C-01 and C-02 from prior passes remain open.*

---

## 2. High Priority Issues (New)

### H-34 — `update_patient` stale check is non-atomic; concurrent edits silently overwrite

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260523140000_patient_management.sql` |
| **Evidence** | `assert_org_patient` at lines 184–219 is `STABLE` with no row lock. Stale check at lines 737–738 compares `updated_at` to `p_expected_updated_at`. `UPDATE` at lines 786–797 has **no** `FOR UPDATE` beforehand and **no** `WHERE updated_at = p_expected_updated_at` on the update itself. |
| **Why it is a problem** | Two receptionists editing the same patient with the same loaded `updated_at` both pass `STALE_PATIENT`, then last-write-wins. National ID, phone, and clinical notes can be lost without either user seeing a stale error. |
| **Potential impact** | Patient PII corruption; duplicate national IDs if uniqueness check passes on stale snapshot; audit trail shows two successes but only one edit survives. |
| **Recommended solution** | `SELECT … FOR UPDATE` before validation, or atomic `UPDATE … WHERE id = $1 AND updated_at = $2` with `GET DIAGNOSTICS` → `STALE_PATIENT` when `ROW_COUNT = 0`. Match the `lock_draft_invoice` pattern used in billing. |

---

### H-35 — Service catalog branch config/promotion RPCs have racy optimistic concurrency

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql` |
| **Evidence** | `configure_service_branch` (lines 419–526): reads `service_branches` without `FOR UPDATE` (lines 475–480), stale check at 486–488, then `UPDATE` at 516–525 with no `WHERE updated_at = p_expected_updated_at`. Same pattern in `set_service_promotion` (lines 568+, stale check at 636, updates at 641+). Contrast `update_service` (lines 838–844) which **does** use `FOR UPDATE`. |
| **Why it is a problem** | Concurrent administrators editing branch pricing/promotions can pass `STALE_SERVICE_BRANCH` checks on the same timestamp and overwrite each other. Promotion windows and overrides can be partially applied. |
| **Potential impact** | Wrong prices on invoices created via `add_invoice_item_from_service`; promo dates corrupted; billing disputes. |
| **Recommended solution** | `SELECT … FOR UPDATE` on `service_branches` before stale validation, or conditional `UPDATE … WHERE updated_at = p_expected_updated_at`. |

---

### H-36 — Appointment scheduling overlap checks are check-then-act without exclusion constraints

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260628160000_simplified_slot_booking.sql`, `backend/supabase/migrations/20260604130000_fix_create_appointment_exception_handlers.sql`, `backend/supabase/migrations/20260618140000_update_appointment.sql`, `backend/supabase/migrations/20260601180000_appointment_medium_severity_fixes.sql` |
| **Evidence** | `appointment_has_overlap` (28160000:7–33) is `STABLE`, returns `false` when `p_doctor_id IS NULL`, and performs a non-locking `EXISTS`. `create_appointment` checks overlap then inserts (04130000:84–97) with no `FOR UPDATE` on conflicting rows. `update_appointment` (18140000:29–34) selects appointment without `FOR UPDATE`; overlap check at 119–121 then `UPDATE` at 123–132. `reschedule_appointment` (01180000:187–240) same pattern. No GiST/exclusion constraint on `(branch_id, doctor_id, tstzrange(start_time, end_time))` for active appointments. |
| **Why it is a problem** | Two concurrent `create_appointment` / `reschedule_appointment` calls for the same doctor and slot can both pass `appointment_has_overlap` and both commit. H-15 notes tests don't exercise this; this is the underlying production race. |
| **Potential impact** | Double-booked doctors; two patients for one slot; queue/calendar corruption. |
| **Recommended solution** | Add PostgreSQL exclusion constraint using `tstzrange` + `btree_gist`, or `SELECT … FOR UPDATE` on overlapping appointment rows inside the RPC before insert/update. Handle `exclusion_violation` as `SCHEDULE_CONFLICT`. |

---

### H-37 — Shift staff overlap validation is check-then-act without row locks

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260606180000_shift_management.sql`, `backend/supabase/migrations/20260607120000_shift_medium_severity_fixes.sql` |
| **Evidence** | `assert_no_staff_shift_overlap` (06180000:381–440) queries overlapping shifts without locking them. `create_shift` calls it (685–692) then `INSERT INTO shifts` (694–714) and assignment inserts (716–721). `modify_shift_assignments` calls it per added staff (843–850) after removals already committed in-transaction. `update_shift` calls it (964+) before time change. No exclusion constraint on shift time ranges per staff member. |
| **Why it is a problem** | Concurrent `create_shift` / `modify_shift_assignments` for the same staff and overlapping window can both pass the assertion and commit duplicate assignments. |
| **Potential impact** | Staff scheduled in two places at once; payroll/scheduling errors. |
| **Recommended solution** | Lock conflicting `shifts`/`shift_assignments` rows with `FOR UPDATE`, or add exclusion constraint on `(staff_member_id, shift_date, timerange(start_time, end_time))` where `deleted_at IS NULL`. |

---

### H-38 — `void_invoice` allows voiding partially-paid invoices without refund enforcement

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260605310000_fix_billing_review_items_18_21_24.sql`, `backend/supabase/migrations/20260605181000_billing_us2_payment_rpcs.sql`, `backend/tests/billing_crud.sql` |
| **Evidence** | `void_invoice` permits `status IN ('issued', 'partially_paid')` (05310000:562–566). No check that `sum(payments.amount) = 0` or mandatory `record_refund` before void. `UPDATE` sets `status = 'voided'` (571–578) but **does not** reverse or flag existing payment rows. `get_invoice_detail` zeroes displayed balance for voided invoices (05300000:170–171) while `list_invoices` still sums `payments.amount` as `paid_amount` (05290000:504–508). Test `void_partially_paid_invoice_succeeds` at `billing_crud.sql:1704–1718` expects this behavior. |
| **Why it is a problem** | Staff with `invoices.void` can collect partial cash (`record_payment`), void the invoice, and leave positive payment rows attached to a voided invoice. UI shows balance 0; payment ledger still shows collected funds with no active invoice obligation. Error text says "Refund paid invoices first" but only blocks **fully** `paid` status. |
| **Potential impact** | Revenue reconciliation gaps; cash handling without audit trail tie to active invoice; potential internal fraud vector. |
| **Recommended solution** | Require `compute_invoice_balance = 0` OR auto-insert offsetting refund payments on void; alternatively block void when `sum(payments.amount) > 0` unless explicit `allow_void_with_payments` admin flag. Update `list_invoices` to exclude voided invoices from payment rollups or show `net_collected` separately. |

---

## 3. Areas Reviewed — No New Critical/High

| Area | What was checked | Result |
|------|------------------|--------|
| **Billing payments** | `lock_payable_invoice` + balance check before insert; concurrent payment serialization | Correct — row lock prevents overpayment races |
| **Billing refunds** | `record_refund` locks invoice `FOR UPDATE`, validates against net payments | Correct under sequential locking |
| **Billing issue/void** | `lock_draft_invoice` / invoice `FOR UPDATE` on void | Locking OK; void semantics gap → H-38 |
| **Billing catalog integration** | `add_invoice_item_from_service` eligibility, price resolution, draft lock | Logic sound; grant gaps are C-02/H-09 (prior) |
| **Invoice per visit** | `invoices_visit_active_unique` partial index | DB prevents duplicates; RPC lacks graceful `unique_violation` handler (Medium, M-02 prior) |
| **Visits** | `create_visit` appointment lock + `visits_appointment_id_active_unique`; `complete_visit` dual `FOR UPDATE` | Concurrency well-handled for in-progress and duplicate visit |
| **Appointments status** | Partial unique indexes for one `in_progress` per doctor | DB + `unique_violation` handlers present |
| **Patients create** | National ID uniqueness index + pre-insert check | Race reduced to unique-index 500 on concurrent duplicate (Medium) |
| **Patients transfer** | Org-aligned branch validation | OK; branch-scope asymmetry covered by H-20 |
| **Shifts cancel/update** | `FOR UPDATE` on shift row, stale `updated_at` on shift itself | Shift row concurrency OK; overlap gap is H-37 |
| **Service catalog CRUD** | `update_service` uses `FOR UPDATE`; name uniqueness | Service-level locking OK; branch-level gap → H-35 |
| **Null handling** | `p_expected_updated_at IS NULL` rejected in patient/billing/catalog mutations; `lock_draft_invoice` raises on null | Consistent fail-closed on required timestamps |
| **RPC vs RLS** | Billing/appointments/visits/shifts mutations blocked at RLS | Confirmed; patient SELECT org-wide is H-20 (prior) |
| **Internal helper grants** | `assert_visit_branch_scope` granted to `authenticated` | Same class as H-24 (prior); not re-reported |

---

## 4. Relationship to Prior Findings

| Prior ID | Relevant to this pass | Third-pass note |
|----------|----------------------|-----------------|
| M-02 | `create_invoice_from_visit` TOCTOU | **Partially mitigated** — `invoices_visit_active_unique` exists at `20260605180000:108–110`; RPC still lacks `unique_violation` → `ACTIVE_INVOICE_EXISTS` mapping |
| H-15 | Sequential concurrency tests | Underlying races now documented as H-36, H-37 |
| H-03 | Legacy `add_invoice_item` | Not re-reported |
| H-20 | Patient org-wide access | `create_appointment`/`create_visit` use `assert_org_patient` (org-wide) — consistent with H-20, not new |
| H-24 | `assert_patient_branch_scope` grant | `assert_visit_branch_scope` has same grant pattern (`20260531180000:2196`) — prior class, not duplicated |

---

## 5. Recommended Remediation Priority

| # | Action | Addresses |
|---|--------|-----------|
| 1 | Atomic stale checks on `update_patient` (`FOR UPDATE` or conditional `UPDATE`) | H-34 |
| 2 | Add exclusion constraint or row locks for appointment doctor overlap | H-36 |
| 3 | Define void semantics: block or auto-refund when payments exist | H-38 |
| 4 | `FOR UPDATE` on `service_branches` in configure/promotion RPCs | H-35 |
| 5 | Lock or constrain shift staff overlap | H-37 |

---

*End of third-pass review. 0 Critical, 5 High (new). All findings traced to `backend/supabase/migrations/` as of 2026-07-05.*
