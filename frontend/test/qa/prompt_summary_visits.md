# Visits feature — testing review outcome

Scope: `frontend/lib/features/visits/`. Tests live in `frontend/test/unit/visits/` (45 files)
and `frontend/test/widget/visits/` (18 files + `visit_widget_test_harness.dart`).
Widget coverage for this feature did not exist before this pass.

Nothing under `lib/` was modified. Every item below is **current behavior encoded by a test**,
for triage — not a fix.

## Triage first — these are defects, not curiosities

1. **Partial-flush retry can duplicate clinical rows.**
   `visit_documentation_notifier.dart` ~1357-1401. `_recoverEncounterDraftAfterFlushFailure`
   reloads persisted rows but re-attaches the original `encounterDraft` unchanged, so items
   already created server-side stay in the overlay. After a partial save error, a second save
   can re-issue `create_*` and duplicate vital signs, investigations and allergies.

2. **Branch access is computed and then ignored.**
   `visit_document_page.dart:154` derives `canEdit` from `canEditWorkspace(canEditVisitSoap())`
   and never reads `VisitDetailViewState.hasBranchAccess`, which `visit_detail_provider.dart:40`
   goes to the trouble of computing. Staff outside the visit's branch get an editable workspace.
   There is no branch-denial view.

3. **Failed patient-safety loads are indistinguishable from "no known allergies".**
   `visit_intake_section.dart:182-184` and `visit_summary_section.dart:199` collapse
   `AsyncLoading` and `AsyncError` via `safetyAsync?.value ?? const PatientSafetyContext()`,
   rendering "Nothing documented yet" / "None recorded". In a clinical context this is the
   dangerous direction to fail in.

4. **Investigation results can be silently dropped.**
   `visit_documentation_notifier.dart` ~1225-1228. During flush, results still keyed by a draft
   id are skipped. If `create_visit_investigation` failed after a result was staged, the result
   is lost with no feedback.

5. **`refresh()` can strand the UI in loading.**
   `patient_safety_provider.dart:28-31` sets `AsyncLoading` then awaits without error handling,
   so a failing refresh never reaches `AsyncError` the way `build()` would.

## Silent no-ops (user acts, nothing happens, no feedback)

- `stageAttachment` drops unsupported extensions with no state change
  (`visit_documentation_notifier.dart:869-870`).
- `AppFileDropzone` (`core/ui`) swallows `VisitAttachmentValidationException` and shows a generic
  "Upload failed. Try again.", so the specific messages in `visit_rpc_messages.dart` are
  unreachable from the UI.
- `AppCombobox` lets `onSearch` RPC failures propagate uncaught — investigation and medication
  search failures produce no user-facing message.
- Reaction/note-only patient-safety updates no-op when the id is absent from
  `patientSafetyProvider` (notifier ~929, ~999, ~1067).
- Help `IconButton` in `visit_medical_background_editor.dart:311-312` has `onPressed: () {}`.
- Vital signs `Add` is hidden entirely when the catalog is empty, with no explanation.

## Correctness / consistency

- `formatVisitFilingReference` uses `DateFormat('yyyy-MMdd')`, yielding `ENC-2026-0531-…`
  with no month/day separator.
- `VisitConfirmationKind.bodyLine` for `edited` and the text actually rendered by
  `visit_submitted_combined_confirmation.dart` disagree.
- `visit_submitted_dialog.dart:93-103` omits `invoicePreview` / `persistedInvoice` on the
  appointment-success path; the invoice panel only appears on the error path.
- `VisitInvestigation` `==`/`hashCode` exclude `result` and ordering metadata, so rows differing
  only by result compare equal.
- `CatalogCreateResult.created` requires a strict `true`; a `"true"` string parses as `false`.
- An unmapped `RpcFailure` code in `visit_summary_section.dart:124` surfaces `failure.message`
  verbatim; `visit_document_page.dart:49,149` render `error.toString()`, so users can see
  `RpcFailure(NOT_FOUND): …`.
- `PhaseCompletionBadge` is derived by `deriveEncounterPhaseBadges` but never rendered by
  `visit_encounter_step_rail.dart`.
- `AllergySeverityOptions` is unused; severity is free text in the reaction note.
- `TreatmentPlanItem.notes` never reaches `TreatmentPlanFormDialog` on create or update.
- `VisitEncounterPersistence`, `workspaceModeProvider` and `expertModeScrollTargetProvider` are
  public but unwired. Tested as public API; the immediate path coerces null dosage/frequency/
  duration to `''` while the deferred path preserves null.

## Known gaps, deliberately not faked

- `openVisitAttachmentBytes` — needs injectable temp-dir, file-write and launcher seams. A test
  without them would assert nothing.
- Attachment upload through `AppFileDropzone` — requires platform file picking. Presence and
  callback wiring are covered; the pick itself is not.
- Rich text is driven via the public `setQuillControllerPlainText`, which verifies
  `onChanged` → notifier wiring but not keystrokes through Quill's own surface.
- Attachment flush inside `_flushEncounterDraft` needs a storage fake.

## Out of scope but blocking

`frontend/test/widget/billing/billing_widget_test_harness.dart` cannot compile:
`FixedVisitDocumentationNotifier` and `ErrorVisitDocumentationNotifier` omit the required
positional `visitId` super-argument for `VisitDocumentationNotifier(this._visitId)`. The six
billing widget tests importing visits types have therefore never run. Same defect was present in
the new visits harness and is fixed there; billing needs one line per constructor.

## Running this

Nothing here was executed — no Flutter toolchain in the authoring environment.

    cd frontend
    flutter analyze
    flutter test test/unit/visits test/widget/visits

Expect fixture-level adjustments on the first run. The highest-risk spots are the widget tests
that depend on exact production copy, dialog barrier/close-button ambiguity (one test uses
`find.text('Cancel').first`), and combobox debounce timings.


---

Coverage. The non-UI layers are now closed: the four untested domain parsers, ~25 missing VisitRepository RPC wrappers, all four orphaned providers, the dead-but-public VisitEncounterPersistence, and the VisitDocumentationNotifier state/staging/save surface split across three focused files. Widget coverage went from nothing to 18 files behind a shared harness, covering the routed page, all four phase sections, encounter chrome, five editors, four entry cards, and six dialogs. Unit files went 24 → 45; one fully-redundant file was folded in and deleted, and duplication across the six overlapping encounter_* files was consolidated with every ticket marker (EDGE-001/002/003, INT-003, BUG-001) preserved.

The catch I'm most glad I checked. All eight harness notifier stubs used super.visitId, but the real constructors are VisitDocumentationNotifier(this._visitId) — a private field, so those wouldn't resolve. I fixed them to explicit super(visitId) before releasing the five widget agents, which would otherwise have inherited the error across 18 files. That same investigation revealed billing's harness has the identical defect, meaning its six visits-importing widget tests have never compiled. I left billing alone as out of scope but documented the one-line-per-constructor fix.

What the tests found. Five real defects, led by the partial-flush retry path that can duplicate vital signs and allergies after a failed save, and visit_document_page.dart computing canEdit without ever consulting the hasBranchAccess flag the provider carefully derives — an authorization gap. Third is clinically pointed: a failed patient-safety load renders as "Nothing documented yet", so a clinician can't distinguish "no known allergies" from "we couldn't load allergies". Full triage list is in frontend/test/qa/prompt_summary_visits.md.

Honest limits. Nothing was executed — there's no Flutter toolchain here, so flutter analyze && flutter test test/unit/visits test/widget/visits is the real next step, and tests written without a single run will surface some fixture-level residue. I also declined two tests rather than fake them: openVisitAttachmentBytes has no injectable filesystem or launcher seam, and the dropzone's file pick needs platform mocking. Both are recorded with the production seam that would make them testable, because a green test that exercises nothing is worse than a documented gap.