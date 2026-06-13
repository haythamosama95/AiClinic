# Senior Code Review — `ui/007-patients`

**Base branch:** `ui/006-settings` (identical to `ui/master`)
**Head:** `ui/007-patients` (10 commits ahead)
**Scope reviewed:** patient list + detail UI, `search_patients` RPC, dev-reset RPC, dev clinic seed tooling, shared input/core widgets, routing, assets.
**Diff size:** 83 files, ~8,779 insertions / 182 deletions.

---

## Findings (by severity)

### HIGH

#### H1 — "Assigned Doctor" filter always returns zero patients
- **Severity:** High
- **Files:** `frontend/lib/features/patients/presentation/models/patient_list_filters.dart` (L112–114), `patients_filter_sidebar.dart` (L247–252), `patient_list_notifier.dart`
- **Explanation:** The filter sidebar exposes a user-selectable **Assigned Doctor** dropdown. When set, `applyClientFilters` filters with `filtered.where((row) => row.assignedDoctorName != null)`. But `PatientTableRow.assignedDoctorName` is **never populated** — `PatientTableRow.fromItems` always constructs rows with `assignedDoctorName == null`, and there is no other assignment anywhere in the codebase. Therefore selecting *any* doctor filter unconditionally empties the result set and the page shows "no matches". A visible, reachable filter is completely broken.
- **Suggested fix:** Either (a) hide/disable the Assigned Doctor filter until the backend returns the assigned doctor, or (b) populate `assignedDoctorName` from the RPC and filter by the selected `assignedDoctorId`. Do not ship a UI control whose only effect is to break the list.

#### H2 — Client-side filtering & sorting operate only on the current server page
- **Severity:** High
- **Files:** `patient_list_filters.dart` (`applyClientFilters`, L109–152), `patient_list_notifier.dart` (L74–83), `patients_table.dart` (L76–118)
- **Explanation:** `search_patients` returns a single paginated page (`limit/offset`) plus a server `total_count`. The notifier then applies **last-visit filters and sort client-side over only that page**, while `totalCount` and pagination math (`totalPages`, "Showing X–Y of Z") still come from the unfiltered server count. Consequences:
  - Last-visit filters (e.g. `over90Days`, `never`) silently drop rows from the visible page while pagination still claims there are N total — a page can render 3 rows out of a "page size" of 20 with later pages still labeled as existing, and matching patients on other pages are never shown.
  - Name/last-visit sorting only reorders the ~20 rows currently visible, not the global result set, so "sort by name desc" is wrong as soon as there is more than one page.
  - The footer summary `Showing $start–$end of $totalCount` becomes inconsistent (`end = offset + rows.length` shrinks after client filtering, but `totalCount` does not).
- **Suggested fix:** Push these filters/sort into `search_patients` (the SQL already ranks/sorts there), or disable pagination while client-side filtering is in effect and compute counts from the filtered set. At minimum, the comments acknowledging these are "client-side placeholders" should be matched by hiding the controls until server support exists.

---

### MEDIUM

#### M1 — `patientUpcomingAppointmentsProvider` loads an entire branch's appointments to show one patient
- **Severity:** Medium (performance / payload)
- **File:** `patient_detail_history_provider.dart` (L64–85)
- **Explanation:** To list a single patient's upcoming appointments, the provider calls `listAppointments(branchId, from: now, to: now + 365 days, statuses: [...])` and then filters client-side by `patientId`. For a busy branch this pulls a year of appointments across **all** patients on every patient-detail open — a large payload and wasted work to display a handful of rows.
- **Suggested fix:** Add a patient-scoped appointment query (RPC param `p_patient_id`) and request only that patient's upcoming appointments, or narrow the time window significantly.

#### M2 — `patientVisitDocumentsProvider` issues an N+1 burst of `get_visit` calls
- **Severity:** Medium (performance)
- **File:** `patient_detail_history_provider.dart` (L88–115)
- **Explanation:** It loads up to 100 past visits, then fires `getVisit(visitId)` for **every** visit concurrently via `Future.wait` just to collect attachments. That is up to 100 parallel RPC round-trips per documents-card render — an N+1 over the network and a thundering-herd against the DB/PostgREST.
- **Suggested fix:** Provide a single RPC that returns attachments for a patient (or for a batch of visit IDs) instead of one call per visit. If unavoidable short-term, cap concurrency.

#### M3 — Oversized avatar PNG assets decoded at full resolution
- **Severity:** Medium (bundle size / memory)
- **Files:** `frontend/assets/images/patient_avatar_male.png` (1.36 MB), `patient_avatar_female.png` (1.23 MB), `pubspec.yaml`, `patient_gender_avatar.dart`
- **Explanation:** Two ~1.3 MB PNGs (≈2.6 MB added to the bundle) are used purely as 72–96 px circular avatars. `Image.asset` is called without `cacheWidth`/`cacheHeight`, so Flutter decodes the full-resolution bitmap into memory regardless of the tiny display size — significant memory per rendered avatar and unnecessary app-size growth.
- **Suggested fix:** Downscale/compress the source images to the display size (or 2x/3x), and pass `cacheWidth`/`cacheHeight` to `Image.asset`. Consider a vector/SVG alternative.

#### M4 — Patient list does not reload when the active branch changes
- **Severity:** Medium (correctness, moderate confidence)
- **File:** `patient_list_notifier.dart` (L51–72)
- **Explanation:** `_load` reads `authSessionProvider` via `ref.read` and resolves `branchId` from `auth.context?.activeBranchId`, but the provider does not `watch`/`listen` to auth. If the user switches the active branch in the shell, `patientListProvider` keeps its cached state and continues showing the previous branch's patients until something else invalidates it.
- **Suggested fix:** `ref.listen`/`ref.watch` the active branch id inside the notifier (or invalidate `patientListProvider` on branch switch) so the list refreshes.

#### M5 — Phone field accepts non-numeric input despite "Only numbers are allowed"
- **Severity:** Medium (validation / data quality)
- **File:** `create_patient_modal.dart` (L438–445)
- **Explanation:** The mobile-number field hint says "Only numbers are allowed", but there is no `inputFormatters` restriction and the validator only checks non-empty. Letters/symbols can be saved. This also interacts with `search_patients`, which classifies a query as a phone search only when it matches `^[0-9]+$`; phone numbers stored with stray characters won't be findable by phone-prefix search.
- **Suggested fix:** Add a digits/`+`-only `FilteringTextInputFormatter` and validate the phone format, consistent with backend expectations.

---

### LOW

#### L1 — Pagination/sort ordering lacks a stable tiebreaker
- **Severity:** Low
- **File:** `backend/supabase/migrations/20260614130000_search_patients_visit_appointment_fields.sql` (L178), `20260614120000_*`
- **Explanation:** Results are ordered `ORDER BY name_match_rank, full_name` with no unique tiebreaker (e.g. `id`). Patients sharing a name can be ordered nondeterministically across requests, which can cause rows to repeat or be skipped when paging.
- **Suggested fix:** Append `, p.id` to the `ORDER BY` (both the inner and the `jsonb_agg` ordering).

#### L2 — Migration churn: superseded function definitions within the branch
- **Severity:** Low
- **Files:** `20260614110000_dev_reset_delete_staff_and_auth_users.sql` vs `20260614140000_fix_dev_reset_audit_log_before_auth_users.sql`; `20260614120000_search_patients_prefix_ranking.sql` vs `20260614130000_search_patients_visit_appointment_fields.sql`
- **Explanation:** `dev_reset_clinic_installation` is created in `110000` with the `audit_log` delete placed **after** `DELETE FROM auth.users` (an `audit_log.user_id → auth.users` FK violation at runtime), then re-created correctly in `140000`. Likewise `search_patients` is fully redefined twice. The intermediate `110000`/`120000` definitions are dead on arrival. Forward-fixing via a new migration is acceptable, but anyone invoking `dev_reset` between applying `110000` and `140000` would hit the FK error. Migrations are dev/local-gated, so impact is limited.
- **Suggested fix:** For local branches it's fine to squash; at minimum keep the fix as the only new definition to reduce confusion. (No production impact since `dev_reset` is environment-gated.)

#### L3 — Inconsistent trimming between create vs update inputs
- **Severity:** Low
- **File:** `create_patient_modal.dart` (L160–186)
- **Explanation:** `_buildCreateInput` passes `_phoneController.text` and `_fullNameController.text` untrimmed, while `_buildUpdateInput` passes `phone: _phoneController.text.trim()`. Behavior differs depending on whether you create or edit; relies on the backend to normalize.
- **Suggested fix:** Trim consistently in both builders.

#### L4 — Unknown/unspecified gender renders the male avatar
- **Severity:** Low (UX)
- **File:** `patient_gender_avatar.dart` (L19–23)
- **Explanation:** `switch (gender)` maps `null`/unspecified to the male portrait. A patient with no recorded gender is shown as male, which is misleading.
- **Suggested fix:** Use the neutral `_FallbackAvatar` (person icon) for the `null` case.

#### L5 — Edit from detail page doesn't refresh the patient list
- **Severity:** Low
- **Files:** `patient_detail_page.dart` (L834–836), `create_patient_modal.dart` (L258)
- **Explanation:** A successful edit invalidates `patientDetailProvider`, but not `patientListProvider`. If the user navigates back to the list, name/phone edits are stale until a manual reload. (Create correctly invalidates the list.)
- **Suggested fix:** Invalidate `patientListProvider` after a successful update too.

---

## What looked good

- **Security of `search_patients`:** permission check (`assert_permission('patients.view')`), org-context enforcement, branch-membership check against `jwt_branch_ids()`, branch active/ownership validation, and proper `LIKE` escaping (`replace ... ESCAPE '\'`). Limits clamped (`LEAST(GREATEST(...),100)`), offset floored at 0. Good defensive `EXCEPTION` mapping.
- **Search performance is index-backed:** name substring uses the existing `patients_org_fullname_trgm_idx` (GIN trigram on `lower(full_name)`), phone prefix uses `text_pattern_ops` B-trees, and a new partial index `appointments_patient_start_idx` plus existing `visits_patient_visit_date_idx` cover the new lateral joins. Lateral subqueries are bounded by the page limit (≤100).
- **`dev_reset` safety:** environment-gated (`app.environment` must be development/local/test), bootstrap-admin asserted, deletions ordered to respect FKs (billing → visits → shifts → appointments → patients → staff → audit_log → auth.users → branches → orgs), with `to_regclass` guards for not-yet-migrated tables and a post-condition completeness check.
- **Dev clinic seed tooling** is correctly gated behind `kDebugMode` everywhere (`ShellDevShellWrapper`, `shellDevListenForRouterRefresh`, `shellDevSuppressAuthRedirect`, `ShellDevFillDummyClinic.isEnabled`), with a clean documented removal path. The `shellDevSuppressAuthRedirect` router hook is debug-only and cannot weaken production auth redirects.
- **Detail page UX:** thoughtful loading states (preview → skeleton → deferred loading overlay), error+retry views, permission-denied views, container-transform transition, optimistic preview from list item, and an authorization-gated delete with confirmation + in-flight guard.

---

## 1. Overall assessment
A large, generally well-structured feature with strong backend security hygiene and polished detail-page UX. The main risks are on the **patients list** side, where two user-facing filter/sort behaviors are effectively broken or misleading once data spans more than one page (H1, H2), plus a couple of avoidable performance patterns on the detail page (M1, M2) and asset bloat (M3). None of the issues are data-destructive in production; they are correctness/UX/perf rather than safety.

## 2. Migration risk assessment
**Low for production.** All new SQL is `CREATE OR REPLACE FUNCTION` / `CREATE INDEX IF NOT EXISTS` — no destructive DDL, no column drops, no type changes on production tables. The only `DELETE` operations live inside the **environment-gated** `dev_reset` function. The new appointments index is created without `CONCURRENTLY`, so it briefly locks writes to `appointments` on apply — minor, acceptable for the table size, but consider `CONCURRENTLY` if applied on a large live table. Within-branch migration churn (L2) and a missing ORDER BY tiebreaker (L1) are the only real notes.

## 3. UI quality assessment
**Good on the detail page, mixed on the list.** Detail page has excellent loading/error/empty/permission states, responsive wide/medium/compact layouts, and good component decomposition. The list page is clean and dense, but ships two filter/sort controls (assigned doctor, last-visit/sort across pages) that don't actually work correctly with server pagination, and a footer summary that can contradict the rendered rows. Avatar assets are far heavier than needed.

## 4. Deployment risk
**Low–Medium.** No production migration danger and no security regressions found. The risk is user-visible incorrectness in patient list filtering/sorting (H1/H2) and detail-page performance under real data volume (M1/M2). Safe to deploy infrastructurally; the list-filter bugs are likely to generate support noise.

## 5. Approval
**Request changes.** Blocking items before merge: **H1** (broken doctor filter — hide it or wire it up) and **H2** (page-scoped filter/sort presented as global). Strongly recommend addressing **M1/M2/M3** soon after (or before, if real-data volume is expected at launch). The Low items are cleanup.
