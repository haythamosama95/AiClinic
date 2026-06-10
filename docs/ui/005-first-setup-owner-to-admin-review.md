# First setup & owner→administrator — code review

**Branch:** `ui/005-first-setup`
**Commits reviewed:** `5b9579c` → `5548354` → `407537a` (HEAD)
**Date:** 2026-06-11
**Scope:** Clinic setup wizard (UI), owner role removal (backend + frontend), related tests and migrations

---

## Summary

| Area                                | Verdict                                                                           |
| ----------------------------------- | --------------------------------------------------------------------------------- |
| Owner → administrator migration     | Structurally sound; data migration, enum rebuild, RLS/RPC recreation look correct |
| Atomic `bootstrap_finish_setup`     | Good design; rollback test present                                                |
| Setup wizard (deferred persistence) | Coherent; org/branch/staff drafts held until Finish                               |
| Last-administrator guard            | **Bug — must fix before merge**                                                   |
| Staff-step copy vs behavior         | **Copy bug — behavior is correct**                                                |
| Plaintext password in setup alert   | **Intentional** (admin records credentials before Finish)                         |
| Multiple administrators             | **Intentional** (no cap)                                                          |

Unit tests under `frontend/test/unit/setup/` and related auth/settings guards were run locally and passed. Backend SQL suites were not executed in this review (`DATABASE_URL` unavailable).

---

## Confirmed product decisions

These were ambiguous in code alone; product owner confirmed intent:

| Topic                   | Decision                                                                                                                                     |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Last administrator      | **Restore guard.** Deactivating or demoting the sole remaining administrator must be blocked (successor to `assert_not_last_owner`).         |
| Staff step at setup     | **Require at least one staff draft** before Finish. Bootstrap admin alone is not enough for the wizard UI.                                   |
| Password in setup alert | **Keep showing password** in the post-draft acknowledgement alert so the admin can record credentials before accounts are created on Finish. |
| Administrator count     | **Unlimited administrators** per clinic. Single-owner model is intentionally retired.                                                        |

---

## 1. Bugs to fix (merge blockers)

### 1.1 Last-administrator guard removed without replacement

**Severity:** Critical
**Status:** Confirmed bug — fix required

`20260611150000_remove_owner_role.sql` drops `auth_internal.assert_not_last_owner()` and rewrites `set_staff_active` / `update_staff_member` without an `assert_not_last_administrator` equivalent.

**Impact:** A clinic with one active administrator can be locked out of admin settings by:

- deactivating that user via `set_staff_active`, or
- demoting them via `update_staff_member` (e.g. administrator → doctor).

**Evidence:** Backend tests that previously enforced this were removed from `backend/tests/org_branch_management_crud.sql` and not replaced:

- `staff_deactivate_last_owner_rejected`
- `staff_update_admin_forbidden_owner_role`

**Recommended fix:**

1. Add `auth_internal.assert_not_last_administrator(p_staff_member_id uuid)` (org-scoped count of other active administrators).
2. Call it from `set_staff_active` (on deactivate) and `update_staff_member` (on role change away from administrator).
3. Return `LAST_ADMINISTRATOR` (or keep `LAST_OWNER` for API stability if clients depend on the code).
4. Restore SQL tests + a boundary manifest scenario.

---

### 1.2 Staff-step subtitle contradicts enforced behavior

**Severity:** Medium (UX / trust)
**Status:** Confirmed copy bug — behavior stays, copy changes

Guide text added in `5b9579c` says users can skip staff creation:

```text
Create a staff account now, or skip and add team members later.
```

But Finish stays disabled until `staffDrafts.isNotEmpty` (`setup_modal.dart`). Product intent: **at least one staff account is required**.

**Recommended fix:** Update `_setupStepSubtitle` for `SetupWizardStep.staff` to match behavior, e.g.:

```text
Create at least one staff account to finish setup. You can add more now or manage staff later in Settings.
```

Align `_nextDisabledTooltip` if needed (already close: *"Create at least one staff account to finish setup"*).

---

### 1.3 Bootstrap admin count in first migration (fixed by follow-up migration)

**Severity:** Medium (deployment ordering)
**Status:** Fixed in-repo; document for operators

In `20260611150000`, `bootstrap_finish_setup` initialized `v_admin_count := 0` and only counted administrators in the **draft** payload. That rejected setups where drafts were operational roles only (e.g. receptionist), even though the signed-in bootstrap admin is an administrator.

`20260611160000_fix_bootstrap_finish_setup_admin_count.sql` corrects this by counting the caller when `v_staff.role = 'administrator'`.

**Action:** Ensure both migrations apply together. `bootstrap_rpc.sql` test `finish_setup_operational_roles_only` covers the fixed path.

---

## 2. Intentional design (no change required)

### 2.1 Plaintext password in setup acknowledgement alert

After adding a staff draft, `SetupModal` shows username and password in an `AppAlert` until Finish. Passwords also live in `SetupStaffDraft` in notifier state until submit.

**Rationale (confirmed):** Bootstrap admin needs to record credentials before RPC creation on Finish.

**Residual risk:** Shoulder-surfing, screen recordings, shared displays. Acceptable trade-off for setup; not a defect.

---

### 2.2 Unlimited administrator accounts

`create_staff_rpc.sql` now expects bootstrap and non-bootstrap administrators to create additional administrators. The former single-owner constraint is gone by design.

---

### 2.3 Relaxed password complexity (no digit requirement)

Migration `20260611120000_relax_staff_password_digit_requirement.sql` and `StaffPasswordValidation` align: minimum 8 characters, at least one letter. Frontend and backend match.

---

### 2.4 Deferred wizard persistence + atomic Finish

Commits in `5548354` move org/branch/staff to in-memory drafts; `finishSetup()` calls `bootstrap_finish_setup` once. Rollback on duplicate username is tested (`finish_setup_existing_username_rolls_back`).

---

### 2.5 Draft `branchIds` not sent to `bootstrap_finish_setup`

`SetupStaffDraft` stores branch assignments, but `BootstrapRepositoryImpl.finishSetup` only sends username, password, full_name, and role. The RPC assigns all new staff to the newly created branch.

**Acceptable for V1** (wizard has one branch). Revisit if multi-branch setup is added.

---

## 3. Full review — backend

### Migrations (chronological)

| Migration                                                                | Purpose                                                                                      |
| ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| `20260611120000_relax_staff_password_digit_requirement.sql`              | Drop digit rule; keep length + letter                                                        |
| `20260611140000_allow_admin_create_owner_and_atomic_bootstrap_setup.sql` | Interim: owner creation rules + first `bootstrap_finish_setup` (superseded by owner removal) |
| `20260611150000_remove_owner_role.sql`                                   | Owner → administrator data migration; enum rebuild; RPC/RLS recreation                       |
| `20260611160000_fix_bootstrap_finish_setup_admin_count.sql`              | Count bootstrap admin toward administrator requirement                                       |

### What looks solid

- Existing `owner` rows updated to `administrator`; `roles_permissions` owner rows deleted.
- `staff_role` enum recreated without `owner`; columns cast via text.
- `assert_owner_or_administrator()` now allows `administrator` or `is_bootstrap_admin` (name is legacy but behavior is correct).
- `build_staff_claims` / `staff_can_access_branch`: administrator gets org-wide branch access.
- `update_role_permission`: `settings.billing.manage` not delegable to non-administrator roles.
- `update_billing_settings`: requires administrator role explicitly.
- Public RPC wrappers recreated with appropriate `GRANT`/`REVOKE`.

### Gaps and cleanup

| Item                           | Notes                                                                                                                                                                    |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Last-admin guard               | See §1.1                                                                                                                                                                 |
| Stale owner references         | `docs/tests/test-coverage-backend.md`, `specs/002-auth-rbac/contracts/bootstrap-provisioning.md` (`FORBIDDEN_OWNER_CREATE`), seed migration comments still mention owner |
| `patient_management_roles.sql` | Fixture uses `role IN ('administrator', 'administrator', ...)` — duplicate entry (harmless typo)                                                                         |
| Test names                     | Many SQL tests still use variable names like `v_owner_*` while role is `administrator`                                                                                   |

---

## 4. Full review — frontend

### Setup wizard (`5548354` + `407537a`)

| Component               | Assessment                                                                                        |
| ----------------------- | ------------------------------------------------------------------------------------------------- |
| `SetupNotifier`         | Draft-based flow; validation mirrors server rules; `finishSetup` maps to `bootstrap_finish_setup` |
| `SetupModal`            | Step subtitles, nav bar, draft acknowledgement panel, Finish without re-validating cleared form   |
| `SetupStaffStep`        | Wizard branch placeholder (`SetupWizardDraftIds.branch`); shared `StaffFormFields`                |
| `StaffFormFields`       | Reusable create/edit form; password requirements hint matches backend                             |
| `SetupStepTransition`   | Animated step changes with height tracking                                                        |
| `auth_route_guard.dart` | `bootstrapStaffWizardInProgress` allows `/bootstrap` while wizard incomplete                      |
| `router.dart`           | Listens to `setupNotifierProvider` for redirect refresh                                           |

### Role / RBAC UI (`407537a`)

- `StaffRole.owner` removed from Dart enum and permission matrix display roles.
- `ProvisioningRules`: administrators and bootstrap admin can provision; all operational roles selectable including administrator.
- `organizationHasOwner` use case and repository method removed (appropriate after role removal).
- Route guards: organization settings and permission matrix require `StaffRole.administrator`.

### Positive test coverage

- `setup_notifier_test.dart` — drafts, atomic finish, dev reset
- `provisioning_rules_test.dart` — role selection rules
- `staff_password_validation_test.dart` — aligned with backend
- `auth_route_guard_test.dart` — bootstrap wizard in progress

### Missing / weak coverage

| Gap                                                               | Priority |
| ----------------------------------------------------------------- | -------- |
| Widget test: staff step requires draft before Finish              | P1       |
| Widget test: staff subtitle matches Finish gate                   | P1       |
| Widget test: full `SetupModal` staff add → Finish flow            | P2       |
| Boundary: `LAST_ADMINISTRATOR` after guard restored               | P0       |
| Update `boundary_coverage_manifest.md` `patientRole.owner.*` rows | P2       |

---

## 5. Commit-by-commit notes

### `5b9579c` — Adding guide text label for each stage

Small change to `setup_modal.dart` (`_setupStepSubtitle`). Staff-step line is now known to be inaccurate; fix per §1.2.

### `5548354` — Enhancing the forms

Largest UI commit: draft-based wizard, `StaffFormFields`, `bootstrap_finish_setup` wiring, password validation module, step transitions. Coherent architecture; main follow-ups are copy (§1.2) and test gaps above.

### `407537a` — Completely removing the owner role and replacing it with admin

Backend migration is thorough. Critical regression is last-admin protection (§1.1). Frontend and test renames are largely consistent; docs/manifest lag behind.

---

## 6. Merge checklist

### Must fix before merge

- [ ] Implement `assert_not_last_administrator` in `set_staff_active` and `update_staff_member`
- [ ] Restore backend SQL tests for last-administrator deactivate and demote
- [ ] Fix staff-step subtitle (and any related helper copy) to require at least one staff account

### Should fix soon (same PR or immediate follow-up)

- [ ] Add boundary test for `LAST_ADMINISTRATOR`
- [ ] Run full backend test suite after migration apply
- [ ] Widget test asserting Finish disabled/enabled on `staffDrafts.isEmpty`

### Accepted / no action

- [x] Show password in setup draft acknowledgement alert
- [x] Allow unlimited administrator accounts
- [x] Require at least one staff draft (not bootstrap-only Finish)
- [x] Password policy: 8+ chars, one letter (no digit)
- [x] Single-branch assignment via RPC during bootstrap Finish

### Documentation hygiene (non-blocking)

- [ ] Update `specs/002-auth-rbac/contracts/bootstrap-provisioning.md` (remove `FORBIDDEN_OWNER_CREATE`)
- [ ] Update `docs/tests/test-coverage-backend.md` (last-owner → last-administrator)
- [ ] Rename or clarify `patientRole.owner.*` rows in `boundary_coverage_manifest.md`

---

## 7. References

| Artifact                  | Path                                                                                    |
| ------------------------- | --------------------------------------------------------------------------------------- |
| Remove owner migration    | `backend/supabase/migrations/20260611150000_remove_owner_role.sql`                      |
| Bootstrap admin count fix | `backend/supabase/migrations/20260611160000_fix_bootstrap_finish_setup_admin_count.sql` |
| Setup modal               | `frontend/lib/features/setup/presentation/widgets/setup_modal.dart`                     |
| Setup notifier            | `frontend/lib/features/setup/presentation/providers/setup_notifier.dart`                |
| Provisioning rules        | `frontend/lib/features/setup/domain/provisioning_rules.dart`                            |
| Bootstrap RPC tests       | `backend/tests/bootstrap_rpc.sql`                                                       |
| Staff RPC tests           | `backend/tests/create_staff_rpc.sql`                                                    |
| UI widget tests (auth)    | `ui/tests/auth.md`                                                                      |
