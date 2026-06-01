# Visits Feature End-to-End Review

**Date**: 2026-06-01
**Scope**: `frontend/lib/features/visits/` ↔ Backend RPCs in `backend/supabase/migrations/`

---

## Finding 1: Frontend cannot clear optional treatment plan fields on update

**Severity**: Medium
**Files**:
- `frontend/lib/features/visits/data/visit_repository.dart` (lines 129–146)
- `frontend/lib/features/visits/presentation/widgets/treatment_plan_display.dart` (lines 234–244)

**Problem**:
When editing a treatment plan, the frontend only sends fields that are non-null (`if (dosage != null) 'p_dosage': dosage`). The backend uses `CASE WHEN p_dosage IS NULL THEN tp.dosage ELSE NULLIF(trim(p_dosage), '') END` — meaning NULL = keep existing, empty string = clear.

However, `TreatmentPlanFormView._submit()` converts empty strings to `null` before passing to the repository: `dosage: _dosage.text.trim().isEmpty ? null : _dosage.text.trim()`. This means if a user clears a field that previously had a value, the field is sent as `null`, the `if (dosage != null)` guard skips it entirely, and the backend never receives the intent to clear. The old value persists.

**Recommended fix**:
In `updateTreatmentPlan()` in `visit_repository.dart`, always include optional text fields in the params map (don't gate on `!= null`). Send empty strings for cleared fields so the backend receives the clear intent:

```dart
Future<void> updateTreatmentPlan({
  required String treatmentPlanId,
  String? medicationName,
  String? dosage,
  String? frequency,
  String? duration,
  String? notes,
}) async {
  _assertNonEmpty('treatmentPlanId', treatmentPlanId);

  await invokeRpc('update_treatment_plan', {
    'p_treatment_plan_id': treatmentPlanId.trim(),
    if (medicationName != null) 'p_medication_name': medicationName,
    'p_dosage': dosage ?? '',
    'p_frequency': frequency ?? '',
    'p_duration': duration ?? '',
    'p_notes': notes ?? '',
  });
}
```

Alternatively, change `TreatmentPlanFormView._submit()` to pass empty strings instead of nulls for previously-populated fields during edits.

---

## Finding 2: Visit submit does not save unsaved SOAP draft first

**Severity**: High
**Files**:
- `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart` (lines 92–104)
- `frontend/lib/features/visits/presentation/widgets/visit_submit_dialog.dart`

**Problem**:
When the user clicks "Submit visit", the `_submitVisit` method opens the confirmation dialog and calls `completeVisit` RPC directly. It does NOT save the current SOAP draft first. If the user has unsaved text in the SOAP fields and submits, the backend's `complete_visit` RPC checks for non-empty SOAP content **in the database**, not the frontend draft.

Scenario: User types SOAP content → never clicks "Save SOAP" → clicks "Submit visit" → backend rejects with `SOAP_REQUIRED_FOR_COMPLETE` because the DB has no SOAP row.

Even if an existing saved SOAP exists, any unsaved changes are silently lost on submit.

**Recommended fix**:
In `_submitVisit`, call `notifier.save()` before opening the submit dialog (similar to what `_saveAndClose` does). Abort if save fails:

```dart
Future<void> _submitVisit(BuildContext context, WidgetRef ref, String visitId, VisitDocumentationState state) async {
  final notifier = ref.read(visitDocumentationProvider(visitId).notifier);

  if (state.needsSaveBeforeLeaving) {
    await notifier.save();
    if (!context.mounted) return;
    final updated = ref.read(visitDocumentationProvider(visitId)).value;
    if (updated == null || updated.saveStatus == SoapSaveStatus.error || updated.saveStatus == SoapSaveStatus.stale) {
      return;
    }
  }

  final result = await VisitSubmitDialog.show(context, visitId: visitId, expectedUpdatedAt: state.expectedUpdatedAt);
  // ... rest unchanged
}
```

---

## Finding 3: `_formatDate` is dead code in VisitRepository

**Severity**: Low
**Files**:
- `frontend/lib/features/visits/data/visit_repository.dart` (lines 234–239)

**Problem**:
The `_formatDate` helper method is defined but never called anywhere in `VisitRepository`. This is dead code that reduces maintainability.

**Recommended fix**:
Remove the `_formatDate` method.

---

## Finding 4: `updateTreatmentPlan` frontend sends all fields including unchanged ones on edit

**Severity**: Medium
**Files**:
- `frontend/lib/features/visits/presentation/widgets/treatment_plan_list.dart` (lines 148–163)
- `frontend/lib/features/visits/presentation/widgets/treatment_plan_display.dart` (lines 234–244)

**Problem**:
`TreatmentPlanFormView` always sends ALL fields from the form on update — even those the user didn't change. Combined with Finding 1, this means unchanged fields are passed through fine, but the real issue is: `start_date` and `end_date` fields exist on the backend but are not exposed in the form UI.

The backend `update_treatment_plan` uses `COALESCE(p_start_date, tp.start_date)` — meaning once set, start_date/end_date can never be cleared since the frontend never sends them. If legacy data has start/end dates, they will persist forever without UI to clear them.

This isn't critical for V1-5 (duration replaced start/end) but becomes a data integrity issue if the schema is ever extended.

**Recommended fix**:
No immediate action required; document that `start_date`/`end_date` are legacy fields that cannot be cleared from the current UI. If clearability is needed later, add explicit null-sending logic.

---

## Finding 5: `VisitDocumentationNotifier` doesn't use `FamilyAsyncNotifier` API correctly

**Severity**: Medium
**Files**:
- `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` (lines 118–128)

**Problem**:
`VisitDocumentationNotifier` extends `AsyncNotifier` but is declared as a family provider. It stores the family arg (`_visitId`) in its own constructor. With Riverpod's `AsyncNotifierProvider.autoDispose.family`, the notifier class should extend `AutoDisposeFamilyAsyncNotifier<State, Arg>` (or use the generated API). The current pattern `AsyncNotifier<VisitDocumentationState>` with a constructor arg works due to `Notifier.new` passthrough but doesn't follow the canonical Riverpod family notifier pattern — the `build()` method receives no `arg` parameter and `ref.arg` isn't used.

In practice this works because `VisitDocumentationNotifier.new` is used as the constructor reference and Riverpod passes the family arg to it. However, this relies on an implicit behavior and may break with Riverpod version upgrades.

**Recommended fix**:
Verify this compiles and works on the current Riverpod version used (it likely does with riverpod 2.x). If upgrading Riverpod in the future, refactor to the canonical `FamilyAsyncNotifier` pattern. No immediate code change required if tests pass.

---

## Finding 6: Visit attachment download bypasses authorized `filePath` when `fetchDownloadBytes` test hook is set

**Severity**: Low
**Files**:
- `frontend/lib/features/visits/presentation/widgets/visit_attachment_list.dart` (lines 223–225)

**Problem**:
When the `fetchDownloadBytes` test hook is provided, the widget calls it with `download.signedUrl` — bypassing the `VisitAttachmentService.downloadAttachmentBytes` path that prefers authenticated storage download via `filePath`. This is fine for tests, but if a developer accidentally uses this hook in production (unlikely), it would bypass the preferred download mechanism.

Not a real bug — test hooks are appropriately separated. No fix needed.

---

## Finding 7: `VisitAttachmentList` uses `refreshTreatmentPlansPreservingDraft` for attachment refresh

**Severity**: Medium
**Files**:
- `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart` (lines 199–205)

**Problem**:
After a successful attachment upload, the `onChanged` callback calls `refreshTreatmentPlansPreservingDraft()`. While this method does refresh attachments (it calls `getVisit` and updates `visit.attachments`), the method name is misleading and creates a maintenance trap. A future developer might rename or refactor this method thinking it only deals with treatment plans, breaking attachment refresh.

**Recommended fix**:
Rename `refreshTreatmentPlansPreservingDraft` to `refreshVisitPreservingDraft` (or similar) since it refreshes the entire visit metadata including treatment plans and attachments. Update all call sites.

---

## Finding 8: No client-side SOAP length validation before save

**Severity**: Medium
**Files**:
- `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`
- `frontend/lib/features/visits/presentation/widgets/soap_editor.dart`

**Problem**:
The backend enforces a 10,000-character limit per SOAP section (`length(COALESCE(p_subjective, '')) > 10000` triggers `INVALID_INPUT`). The frontend has no client-side length validation — users can type beyond 10,000 characters, hit Save, and get a generic RPC error. There is no `maxLength` on the `TextField` widgets and no validation in the notifier.

**Recommended fix**:
Add `maxLength: 10000` to each SOAP `TextField` in `_SoapField` widget, or validate in `VisitDocumentationNotifier.save()` before calling the RPC and set a user-friendly error message:

```dart
// In save(), before the RPC call:
const maxSoapLength = 10000;
if (current.subjective.length > maxSoapLength ||
    current.objective.length > maxSoapLength ||
    current.assessment.length > maxSoapLength ||
    current.plan.length > maxSoapLength) {
  state = AsyncData(current.copyWith(
    saveStatus: SoapSaveStatus.error,
    errorMessage: 'Each SOAP section must be 10,000 characters or fewer.',
  ));
  return;
}
```

---

## Finding 9: `VisitDocumentationNotifier` initial `expectedUpdatedAt` uses `DateTime.now()` when no SOAP exists

**Severity**: Low
**Files**:
- `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` (line 112)

**Problem**:
When a visit has no SOAP note yet, `VisitDocumentationState.fromVisit` uses `DateTime.now().toUtc()` as `expectedUpdatedAt`. The backend's `save_soap_note` compares this against `visits.updated_at` when no SOAP row exists. If there's any clock drift between client and server (common in LAN deployments), the first save could get a false STALE_SOAP conflict.

However, the backend fallback already handles this correctly — when no soap_notes row exists, it compares against `visits.updated_at`. The `DateTime.now()` is only used as a client placeholder and the actual comparison is server-side. On first save, the backend would use `visits.updated_at` as the baseline. The issue is that `DateTime.now()` will almost certainly differ from `visits.updated_at`, causing a guaranteed STALE_SOAP on first save.

Wait — re-reading the backend: the `get_visit` RPC returns `'updated_at', v_visit.updated_at` in the soap JSON object when no SOAP row exists (line 287 of the duration migration). So `fromRow` would parse `v_visit.updated_at` from the soap object, and `SoapNote.fromRow` would succeed with this server-provided timestamp. The `DateTime.now()` fallback at line 112 only triggers if `visit.soap` is null (which shouldn't happen since `get_visit` always returns a soap object for clinical users).

For non-clinical users (`patients.view` only), `visit.soap` would be null (no soap in payload), and `expectedUpdatedAt` defaults to `DateTime.now()`. But non-clinical users have `canEdit = false`, so they can't save anyway. No real bug here.

**Recommended fix**: None required. The code path is safe.

---

## Finding 10: `VisitDocumentationNotifier.build()` is missing the family arg parameter

**Severity**: Low
**Files**:
- `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` (lines 121–129)

**Problem**:
The `build()` method signature is `Future<VisitDocumentationState> build()` without accepting the family arg. In `AutoDisposeFamilyAsyncNotifier`, the `build` method should accept the arg. The current code works because it stores the arg via the constructor (`this._visitId`), but this pattern is non-standard for Riverpod family notifiers.

**Recommended fix**:
Same as Finding 5 — no immediate fix if tests pass, but refactor during Riverpod upgrades.

---

## Summary

| #   | Severity | Issue                                                 |
| --- | -------- | ----------------------------------------------------- |
| 1   | Medium   | Cannot clear optional treatment plan fields on update |
| 2   | **High** | Visit submit does not save unsaved SOAP draft first   |
| 3   | Low      | Dead `_formatDate` method                             |
| 7   | Medium   | Misleading method name for visit refresh              |
| 8   | Medium   | No client-side SOAP length validation                 |

**Findings 4, 5, 6, 9, 10** are informational / low priority and don't require immediate fixes.

### Priority order for fixes:
1. **Finding 2** (High) — Data loss: unsaved SOAP lost on submit
2. **Finding 1** (Medium) — Cannot clear treatment plan optional fields
3. **Finding 8** (Medium) — No SOAP length validation causes confusing errors
4. **Finding 7** (Medium) — Misleading method name
5. **Finding 3** (Low) — Dead code removal
