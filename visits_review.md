# Visits Feature — Independent Architectural Review

## Scope & method

This is an independent architectural review of the **Visits / encounter workspace** feature of the Flutter desktop client in this repository (package `ai_clinic`, source root `frontend/lib`).

**Code reviewed in depth (57 Dart files under `frontend/lib/features/visits/`):**

- `data/` — `visit_repository.dart` (685 lines), `visit_attachment_service.dart`, `visit_attachment_opener.dart`
- `domain/` — 21 files including `visit_detail.dart`, `visit_encounter_draft.dart`, `patient_safety.dart`, `encounter_phase.dart`, `visit_submit_readiness.dart`, `visit_clinical_note.dart`, `rich_text_draft_utils.dart`, `treatment_plan_options.dart`, `bmi.dart`
- `application/` — `visit_encounter_persistence.dart` (339 lines), `visit_rpc_messages.dart`
- `presentation/` — `pages/visit_document_page.dart` (565 lines); providers `visit_documentation_notifier.dart` (1423 lines), `encounter_step_provider.dart`, `patient_safety_provider.dart`, `visit_detail_provider.dart`, `workspace_mode_provider.dart`, `expert_mode_scroll_provider.dart`; 28 widgets including `visit_summary_section.dart` (717 lines), `visit_submitted_combined_confirmation.dart` (497 lines), `visit_medical_background_editor.dart`, and the three phase canvases `visit_intake_section.dart` / `visit_findings_section.dart` / `visit_treatment_section.dart`

**Boundary-only inspection (not reviewed for their own quality):** `frontend/lib/core/**` (`core/rpc`, `core/auth`, `core/ui`, `core/utils`), `frontend/lib/app/**` (`router.dart`, `navigation/app_navigator.dart`, `providers/auth_session_provider.dart`, `shell/dev/**`), and the touching features `appointments`, `patients`, `billing`, `service_catalog`, `setup`, `clinic-management`.

**Method:**

1. Read the canonical architecture documents first and graded the implementation against them: `docs/architecture/01-principles.md`, `docs/architecture/07-frontend.md` (canonical frontend layering/state/repository conventions), `docs/architecture/14-visits-encounter-workspace.md` (canonical Visits domain architecture), `docs/architecture/15-billing.md` (visit → invoice boundary), `docs/architecture/ARCHITECTURAL_FLAWS.md` (pre-existing known debt).
2. Read every file in `features/visits/` and traced the full save/submit control flow from widget → notifier → repository → RPC.
3. Built a complete import graph in both directions with ripgrep: every `import 'package:ai_clinic/features/<other>/...'` inside `features/visits/`, and every import of `features/visits/...` from anywhere else in `frontend/lib/**`. Verified reachability (dead code) of each exported symbol by grepping `lib/` and `test/`.
4. Verified permission/route wiring in `frontend/lib/app/router.dart` and `frontend/lib/core/auth/auth_route_guard.dart`.

**Grading basis.** `docs/architecture/07-frontend.md` states the layer contract explicitly: **Presentation** depends on domain use cases; **Domain** depends on *nothing* (innermost layer); **Data** depends on domain interfaces and the Supabase SDK. It also records that Visits is an *accepted* exception to the use-case layer (`visits` = "`application/` + `VisitDocumentationNotifier`; notifier calls repository/persistence directly; orchestration-heavy"), and `ARCHITECTURAL_FLAWS.md` L2 accepts "repositories called from notifiers" for this module. **I therefore did not report the missing `domain/usecases/` + `domain/repositories/` layer as a finding** — it is a documented, accepted deviation. What I *did* grade strictly: dependency *direction* (domain must not depend on data/presentation/UI toolkits; `core/` must not depend on features), feature isolation, and correctness of the draft/save/submit lifecycle.

**Already-documented debt (not re-reported as new).** `ARCHITECTURAL_FLAWS.md` H5 already records "`VisitDocumentationNotifier` (~1400 lines) — monolithic notifier: draft, save, safety, attachments, completion" with the recommendation "split by concern". Finding H2 below is that same flaw, still unresolved, and is included **only** because it now carries a concrete, mechanical split plan (exact new files, exact line ranges, exact call sites) that the flaw register does not. Flaw L2 (visits skipping the use-case layer) is accepted and not re-reported. Flaw H1/M3 (billing/shifts presentation "pending") is stale — billing presentation now exists and is deeply entangled with Visits, which is the subject of finding C3.

**Assumption.** Existing behaviour is assumed correct unless there is direct code evidence of a defect. Where I claim a bug, I cite the exact lines that contradict each other.

**Also noted, not filed as findings** (documentation drift, no code impact): `docs/architecture/14-visits-encounter-workspace.md` describes files that do not exist under these names (`EncounterWorkspaceShell`, `EncounterPhaseSubjective/Objective/Plan`, `EncounterStepperHeader`, `visit_documentation_page.dart`, `visit_detail_page.dart`, a "patient safety rail", and a "sticky footer"); the real tree uses `visit_document_page.dart`, `VisitEncounterStepContent`, and the three `visit_*_section.dart` canvases, and `/visits/:visitId/detail` is a `shellPlaceholderPage` in `frontend/lib/app/router.dart:131`. The same doc claims "30+ widget tests under `frontend/test/widget/visits/`"; that directory does not exist — Visits has 17 unit test files under `frontend/test/unit/visits/` and no widget tests.

## Findings summary

| ID | Severity | Short title | Primary file |
| -- | -------- | ----------- | ------------ |
| C1 | Critical | Unsaved clinical documentation is silently discarded on navigation (no unsaved-changes guard, `autoDispose` provider) | `frontend/lib/features/visits/presentation/pages/visit_document_page.dart` |
| C2 | Critical | Partial encounter-draft flush keeps the draft, duplicating vitals/investigations/prescriptions on retry | `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` |
| C3 | Critical | Bidirectional visits ↔ billing presentation cycle; `complete_visit` is orchestrated inside the billing feature | `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart` |
| C4 | Critical | `core/` design system imports the Visits domain (`core` → feature inversion) | `frontend/lib/core/ui/components/app_rich_text_editor.dart` |
| H1 | High | The entire `visits/application/` save-orchestration layer is dead code that inverts layering | `frontend/lib/features/visits/application/visit_encounter_persistence.dart` |
| H2 | High | `VisitDocumentationNotifier` is a 1423-line god object (documented as flaw H5, still unresolved) | `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` |
| H3 | High | Visits `domain/` depends on `data/`, `presentation/`, Quill and the design system | `frontend/lib/features/visits/domain/visit_submit_readiness.dart` + 4 others |
| H4 | High | `STALE_DOCUMENTATION` conflict is an unrecoverable dead end — every later save fails and notes cannot be saved | `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` |
| H5 | High | Draft can be lost in the visits → billing handoff because it relies on an `autoDispose` provider staying alive | `frontend/lib/features/visits/presentation/widgets/visit_summary_section.dart` |
| H6 | High | Invoice receipt is dropped on the success path of the finalize confirmation dialog | `frontend/lib/features/visits/presentation/widgets/visit_submitted_dialog.dart` |
| M1 | Medium | Visits reaches into three other features' `presentation/` internals from two widgets instead of one seam | `frontend/lib/features/visits/presentation/pages/visit_document_page.dart` |
| M2 | Medium | ~110 lines of Quill↔notifier sync machinery copy-pasted across three phase canvases | `frontend/lib/features/visits/presentation/widgets/visit_intake_section.dart` + 2 others |
| M3 | Medium | Widgets call the repository directly for catalog search | `frontend/lib/features/visits/presentation/widgets/investigation_form_dialog.dart` |
| M4 | Medium | Triple visit representation (`visit` / `persistedVisit` / `effectiveVisit`) with manual re-derivation and inconsistent read sites | `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` |
| M5 | Medium | Substantial unreachable code and dead state contradicting the architecture doc | `frontend/lib/features/visits/presentation/providers/workspace_mode_provider.dart` + 6 others |

**Areas assessed as sound** (no findings filed): `data/visit_repository.dart` is a clean, consistent RPC wrapper — uniform `AppRpcInvoker` usage, uniform `_assertNonEmpty` validation, typed result classes, no presentation formatting, no business rules. `data/visit_attachment_service.dart` is well-factored, including correct compensating deletion of the storage object when `register_visit_attachment` fails (lines 127–142). The row-parsing domain DTOs (`visit_detail.dart`, `visit_clinical_note.dart`, `patient_safety.dart`, `visit_investigation.dart`, `visit_vital_sign.dart`, `visit_attachment_item.dart`, `visit_row_parsing.dart`) are defensive, immutable, and free of business logic. `core/auth/permission_service.dart` and `core/auth/auth_route_guard.dart` correctly own permission checks rather than the feature re-deriving them. Visits does **not** reimplement invoice/pricing rules, appointment status transitions, or patient models locally — all pricing and discount logic lives in `features/billing`, and appointment refresh goes through the single named seam `invalidateAppointmentAfterVisitCompleted`.

---

## C1 — Unsaved clinical documentation is silently discarded on navigation

**Severity:** Critical (patient-safety / data-loss)

**Location:**
- `frontend/lib/features/visits/presentation/pages/visit_document_page.dart` — `class VisitDocumentPage extends ConsumerWidget` (line 26), its `build` method, and the back/close affordances it renders
- `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` — `final visitDocumentationProvider = AsyncNotifierProvider.autoDispose...` (line 182) and `VisitDocumentationNotifier` (draft fields `pendingVitals`, `pendingInvestigations`, `pendingPrescriptions`, and the rich-text note drafts)
- `frontend/lib/app/shell/layout/app_shell.dart` and `frontend/lib/app/navigation/app_navigator.dart` — the shell navigation that can leave the page

**Issue.** `VisitDocumentPage` is a plain `ConsumerWidget` with **no `PopScope`, no `onPopInvoked`/`onPopInvokedWithResult`, no `WillPopScope`, and no "discard changes?" confirmation anywhere in `features/visits/presentation/`** (verified by grepping the whole presentation directory for `PopScope`/`onPopInvoked` — zero hits). All in-progress clinical documentation — vital signs, investigation orders, prescriptions, and the three Quill rich-text notes — lives **only** in the in-memory state of `VisitDocumentationNotifier` until an explicit save/flush is triggered. Because `visitDocumentationProvider` is declared `AsyncNotifierProvider.autoDispose`, the moment the last widget listening to it is unmounted (any shell navigation, any sidebar click, closing the page, the router replacing the route) Riverpod disposes the notifier and **the entire unsaved draft is destroyed with no warning and no recovery path**.

**Why it is a problem.**
1. This is clinical data. A clinician who types a full examination note and then clicks anything in the app shell loses the note irrecoverably. There is no autosave timer and no local persistence (no Hive/SharedPreferences draft cache for encounter drafts — `SharedPreferences` is only used for workspace-mode preference, see M5).
2. It is silent. There is no snackbar, dialog, or dirty-state indicator on exit, so the user does not learn the data is gone until they reopen the visit.
3. `docs/architecture/14-visits-encounter-workspace.md` specifies the workspace as an "online-only, explicit-save" surface, which makes an unsaved-changes guard a *required* part of the design, not an enhancement. Its absence is a gap against the canonical spec, not a design choice.
4. The notifier already computes everything needed to detect the dirty state — it tracks pending collections and compares note deltas — so the guard is cheap to add; the risk exists purely because nothing consults it at the navigation boundary.

**Recommended architectural solution.** Introduce a single explicit "is dirty" contract on the notifier and enforce it at exactly one navigation boundary in the page, plus keep the notifier alive for the lifetime of the visit workspace rather than for the lifetime of a widget subtree.

1. Add a pure, side-effect-free getter `bool get hasUnsavedChanges` to `VisitDocumentationNotifier` (and mirror it as a computed field on the state class so widgets can `select` it without rebuilding on every keystroke).
2. Wrap the page body in a `PopScope(canPop: !hasUnsavedChanges, onPopInvokedWithResult: ...)` that shows a three-way dialog (Save and leave / Discard and leave / Stay).
3. Remove `autoDispose` from `visitDocumentationProvider`, or keep `autoDispose` but hold the provider alive from the route-level widget with `ref.keepAlive()` scoped to the visit route so a transient rebuild cannot wipe the draft (this also removes the root cause of H5).
4. Route *all* exits through the same guard, including the custom back/close buttons the page renders and the app-shell navigation items, so there is no bypass.

**Suggested implementation steps.**

1. Open `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`. Locate the state class that holds `pendingVitals`, `pendingInvestigations`, `pendingPrescriptions` and the note-draft fields.
2. The state class **already exposes the needed predicates** — `bool get hasUnsavedDraft` (line 86, which compares note sections against `persistedVisit.documentation` via `_clinicalNoteDiffersFromPersisted()` at line 98) and `bool get hasPendingEncounterDraft => !encounterDraft.isEmpty` (line 107). Do not write new dirty-detection logic. Add only the combined accessor:
   `bool get hasUnsavedChanges => hasUnsavedDraft || hasPendingEncounterDraft;`
   Keep it pure — no I/O.
3. In the same file, change line 182 from `AsyncNotifierProvider.autoDispose.family<...>` to `AsyncNotifierProvider.family<...>` **and** add an explicit disposal call when the visit is finalized (see step 8) so the provider does not leak across visits.
4. Create `frontend/lib/features/visits/presentation/widgets/visit_unsaved_changes_guard.dart` exporting `Future<VisitExitDecision> showVisitUnsavedChangesDialog(BuildContext context)` with `enum VisitExitDecision { save, discard, stay }`, built with the project's existing dialog component from `frontend/lib/core/ui/` (match the style of `frontend/lib/features/visits/presentation/widgets/visit_submitted_dialog.dart`).
5. Add the three dialog strings to the localization files under `frontend/lib/l10n/` (title, body, and the three button labels) and regenerate localizations with `flutter gen-l10n` — do not hardcode English in the widget.
6. In `frontend/lib/features/visits/presentation/pages/visit_document_page.dart`, in `VisitDocumentPage.build`, read `final isDirty = ref.watch(visitDocumentationProvider(visitId).select((s) => s.valueOrNull?.hasUnsavedChanges ?? false));` and wrap the returned widget tree in `PopScope(canPop: !isDirty, onPopInvokedWithResult: (didPop, _) async { if (didPop) return; final decision = await showVisitUnsavedChangesDialog(context); ... })`.
7. In the `save` branch of that handler, `await ref.read(visitDocumentationProvider(visitId).notifier).saveAll()` (the existing flush entry point) and only pop if it returns success; in the `discard` branch, call `ref.read(visitDocumentationProvider(visitId).notifier).clearPendingDrafts()` then pop; in the `stay` branch, do nothing.
8. Add `clearPendingDrafts()` to `VisitDocumentationNotifier` if absent: reset the three pending collections and the note drafts to their last-persisted values, then `state = AsyncData(...)`.
9. Find every custom exit affordance in `visit_document_page.dart` (back arrow, close icon, any `context.go`/`context.pop` call) and replace direct navigation with `Navigator.maybePop(context)` so `PopScope` actually intercepts it. Grep the file for `context.go(` and `context.pop(` to be sure none remain.
10. Add a widget test at `frontend/test/widget/visits/visit_document_page_unsaved_guard_test.dart` that pumps the page, injects a dirty state via an overridden provider, triggers a pop, and asserts the dialog appears and that `stay` leaves the route unchanged.

## C2 — Partial encounter-draft flush re-applies the whole draft, duplicating clinical rows on retry

**Severity:** Critical (data corruption)

**Location:** `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`
- `VisitDocumentationNotifier._flushEncounterDraft(VisitDocumentationState current)` — lines 1160–1379
- `VisitDocumentationNotifier._recoverEncounterDraftAfterFlushFailure(VisitDocumentationState current)` — lines 1384–1407, specifically **line 1400**

**Issue.** `_flushEncounterDraft` persists the entire encounter draft as a long sequence of **individually awaited, non-transactional RPC calls** — roughly 20 separate loops covering vital-sign archive/create/update (1167–1191), investigation archive/create/update/result (1193–1231), treatment-plan archive/create/update (1233–1261), attachment upload/delete (1263–1281), and patient-safety allergy/medication/condition archive/create/update (1283–1337). There is no batching and no server-side transaction wrapping the set.

If any call in the middle fails, both `catch` blocks (1357 and 1368) call `_recoverEncounterDraftAfterFlushFailure`. That method's own doc comment (lines 1381–1383) states:

> *"Reloads persisted visit rows after a partial structured flush so the UI matches the server. **Clears the encounter draft overlay to avoid duplicate creates on retry.**"*

But the implementation does the exact opposite. It rebuilds state from the refreshed server row and then explicitly copies the old draft straight back in:

```1400:1400:frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart
          encounterDraft: afterNote.encounterDraft,
```

So after a partial failure the draft still contains every `pendingVitalSigns`, `pendingInvestigations`, `pendingTreatmentPlans`, `pendingAllergies`, `pendingMedications`, `pendingConditions` and `pendingAttachments` entry — **including the ones that were already successfully created on the server**. The next time the user presses save, `_flushEncounterDraft` runs the same `create*` loops from the top and creates them a second time. Nothing deduplicates: the create loops are unconditional (e.g. line 1172 `for (final sign in draft.pendingVitalSigns) await repo.createVisitVitalSign(...)`), and the freshly persisted rows now live in `current.visit.vitalSigns` where the flush never looks.

The failure is also fully silent at the data level — the only signal is the appended sentence in the error message at lines 1364 and 1374, *"Some changes may have been saved — review the visit before retrying."*, which puts the burden of detecting duplicated prescriptions and allergies on the clinician.

**Why it is a problem.**
1. **Duplicate clinical records.** A retry after a transient network failure duplicates prescriptions, allergies, chronic conditions and investigation orders. Duplicated allergy and medication rows corrupt the patient-safety surface that the workspace itself renders, so the corruption propagates to every future visit for that patient, not just this one.
2. **Duplicate side effects.** `pendingAttachments` re-runs `attachmentService.uploadAndRegister` (line 1268), so files are uploaded to storage twice and registered twice, consuming quota and producing duplicate attachment rows.
3. **The code contradicts its own contract.** The doc comment states the invariant that would make retry safe; line 1400 breaks it. This is not a design trade-off, it is a defect — the intended behaviour is written down two lines above the code that violates it.
4. **The compensating design is absent at both levels.** There is no server-side transactional "flush encounter draft" RPC, and no client-side idempotency (no client-generated stable keys sent to the server), so there is no layer at which a retry is currently safe.

**Recommended architectural solution.** Make the flush **resumable** by removing each item from the draft as soon as its RPC succeeds, so the draft always represents exactly "work not yet persisted". Then the retry-safety property holds regardless of where the failure happened, and `_recoverEncounterDraftAfterFlushFailure` no longer needs to clear or restore anything. Longer term, move the flush behind a single transactional RPC so partial application becomes impossible.

**Suggested implementation steps.**

1. Open `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`.
2. Add a private helper to the notifier that mutates the draft incrementally:
   `void _updateDraft(VisitEncounterDraft Function(VisitEncounterDraft draft) mutate)` which reads `state.value`, applies `mutate` to `state.value!.encounterDraft`, and writes back with `copyWith(encounterDraft: ...)`. (There is already an `_applyEncounterDraft` helper used around lines 688–744 — reuse it instead of adding a second mechanism if its semantics match.)
3. Convert **every** loop in `_flushEncounterDraft` (lines 1167–1337) from "iterate the draft, then discard nothing" to "iterate a snapshot copy, and after each successful `await`, remove that entry from the live draft". Concretely, for the create loop at 1172:
   - iterate `final snapshot = [...draft.pendingVitalSigns];`
   - inside the loop, after `await repo.createVisitVitalSign(...)` succeeds, call `_updateDraft((d) => d.copyWith(pendingVitalSigns: d.pendingVitalSigns.where((s) => s.id != sign.id).toList()))`.
4. Repeat step 3 mechanically for each of these draft collections, removing the processed key/entry after its successful await: `archivedVitalSignIds`, `vitalSignUpdates`, `archivedInvestigationIds`, `pendingInvestigations`, `investigationUpdates`, `investigationResults`, `archivedTreatmentPlanIds`, `pendingTreatmentPlans`, `treatmentPlanUpdates`, `pendingAttachments`, `deletedAttachmentIds`, and inside `draft.patientSafety`: `archivedAllergyIds`, `pendingAllergies`, `allergyUpdates`, `archivedMedicationIds`, `pendingMedications`, `medicationUpdates`, `archivedConditionIds`, `pendingConditions`, `conditionUpdates`.
5. For `pendingInvestigations` specifically, preserve the existing `investigationResultIdRemap` behaviour (lines 1198–1209 and 1225–1231): when removing a persisted pending investigation from the draft, also rewrite the matching key in `draft.investigationResults` from the draft id to `persistedId` **before** removing the pending entry, so the result is still recorded on the retry.
6. Delete line 1400 (`encounterDraft: afterNote.encounterDraft,`) from `_recoverEncounterDraftAfterFlushFailure` so the refreshed server state is authoritative and only genuinely unpersisted work survives (it now survives because of steps 3–4, in `state`, not because it is copied back here).
7. Change the two error messages at lines 1364 and 1374 from *"Some changes may have been saved — review the visit before retrying."* to a message stating that saved changes were kept and remaining changes can be retried safely; add it as a localization key under `frontend/lib/l10n/` rather than concatenating an English literal onto `visitMessageForRpc(error)`.
8. Add a unit test `frontend/test/unit/visits/visit_documentation_flush_resume_test.dart` using a fake `VisitRepository` that succeeds for the first two `createVisitVitalSign` calls and throws `RpcFailure` on the third. Assert: (a) after the failure the draft contains exactly the un-persisted vital signs, (b) a second `saveAll()` issues `createVisitVitalSign` only for those, and (c) total create calls across both attempts equals the original draft size.
9. Open a backend follow-up (not part of this change) to add a single transactional RPC — e.g. `flush_visit_encounter_draft(p_visit_id, p_payload jsonb)` under `backend/supabase/migrations/` — that applies the whole draft atomically, then reduce `_flushEncounterDraft` to one call. Steps 3–4 remain valuable as the client-side guarantee until that exists.

## C3 — Visit completion is orchestrated inside the billing feature, and visits ↔ billing presentation layers form an import cycle

**Severity:** Critical (feature-boundary violation + irreversible state divergence)

**Location:**
- `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart` — `_VisitBillingFlowState._handleFinalize()`, lines 73–130 (the `completeVisit()` call is **line 89**)
- `frontend/lib/features/visits/presentation/widgets/visit_submitted_combined_confirmation.dart:10` — imports `features/billing/presentation/widgets/visit_billing/visit_invoice_summary_panel.dart`
- `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` — `completeVisit({DateTime? expectedUpdatedAt})`, lines 230–271

**Issue.** There are two intertwined problems.

**(a) A genuine import cycle between two features' presentation layers.** Billing presentation imports Visits presentation in four files:

| From (billing) | Imports (visits) |
| -- | -- |
| `presentation/pages/visit_billing_page.dart:11` | `visits/presentation/providers/visit_documentation_notifier.dart` |
| `presentation/widgets/visit_billing/visit_billing_flow.dart:18,19` | `visit_documentation_notifier.dart`, `visits/presentation/widgets/visit_submitted_dialog.dart` |
| `presentation/widgets/visit_billing/visit_service_selection_step.dart:16` | `visit_documentation_notifier.dart` |
| `presentation/widgets/visit_billing/visit_invoice_review_step.dart:28` | `visit_documentation_notifier.dart` |

and Visits presentation imports Billing presentation back in `visit_submitted_combined_confirmation.dart:10`. `visit_billing_flow.dart:13` additionally reaches into `visits/application/visit_rpc_messages.dart`. Neither direction goes through a declared seam — billing widgets read and mutate the Visits notifier directly.

**(b) The visit lifecycle transition lives in the wrong feature, in the wrong order.** `_handleFinalize` in a **billing** widget performs the authoritative clinical state change:

```89:108:frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart
      await docNotifier.completeVisit();

      InvoiceDetail? invoice;
      if (permissions.canCreateInvoices()) {
        try {
          invoice = await _createAndIssueInvoice(...);
        } on RpcFailure catch (error) {
          if (!mounted) {
            return;
          }
          _showError(billingMessageForRpc(error));
          return;
        }
      }
```

The visit is completed **first**, then the invoice is created. If invoice creation fails, the handler shows an error and `return`s — leaving the visit permanently `completed` with **no invoice**, and no compensating action. The `CompleteVisitResult` return value is also discarded here, so the billing widget cannot tell which appointment was affected and cannot report a partial outcome. The failure branch hardcodes the English literal `'Could not finalize the visit. Please try again.'` (line 119) instead of using a localization key.

(Separately worth fixing while in this code: `completeVisit({DateTime? expectedUpdatedAt})` **ignores its own parameter** — line 266 always uses `current.expectedUpdatedAt` from state, per the comment on line 265. The parameter is dead in every caller. It should either be honoured or removed from the signature so callers are not misled into thinking they control the concurrency token.)

**Why it is a problem.**
1. **Irreversible divergence.** A billing RPC failure produces a completed, no-longer-editable visit with no invoice — a state the clinician cannot fix from the UI and which requires a database intervention.
2. **Ownership inversion.** `docs/architecture/14-visits-encounter-workspace.md` makes Visits the owner of the encounter lifecycle and `docs/architecture/15-billing.md` defines the handoff as visit → invoice. Here billing drives the visit transition, so the invariant "a visit is only completed as part of a successful finalize" is enforced nowhere and cannot be tested in isolation.
3. **The cycle blocks all modularization.** With presentation-level imports in both directions, neither feature can be extracted, tested, or reasoned about independently, and a change to `VisitDocumentationState` breaks four billing files. This also defeats the boundary discipline that `docs/architecture/01-principles.md` requires.
4. **Concurrency protection is silently unused.** Because `expectedUpdatedAt` is omitted, two users finalizing the same visit will not trigger the `STALE_DOCUMENTATION` path the notifier implements.

**Recommended architectural solution.** Invert the control flow: Visits owns finalization and *calls into* billing through one narrow interface; billing never imports Visits. Concretely, define a single application-layer orchestrator in Visits that performs "create+issue invoice, then complete visit" in the safe order, and reduce the billing widget to collecting line/discount input and returning a result object.

**Suggested implementation steps.**

1. Create `frontend/lib/features/visits/application/visit_finalization_service.dart` with a class `VisitFinalizationService` and a provider `visitFinalizationServiceProvider`. Give it one method:
   `Future<VisitFinalizationResult> finalize({required String visitId, required List<InvoiceDraftLine> lines, required DiscountType discountType, required num discountValue, required bool canApplyDiscount, required bool canCreateInvoices, required DateTime? expectedUpdatedAt})`.
2. Inside `finalize`, order the operations **invoice first, visit completion second**: (a) if `canCreateInvoices`, create and issue the invoice via the billing repository; (b) only if that succeeded (or was skipped by permission), call `completeVisit(expectedUpdatedAt: expectedUpdatedAt)`; (c) return a result carrying both the `InvoiceDetail?` and the `CompleteVisitResult`. Abort and return a failure result without completing the visit if (a) throws.
3. Move the invoice-creation logic currently in `_createAndIssueInvoice` (in `visit_billing_flow.dart`) into a method on the **billing repository/service** layer (`frontend/lib/features/billing/data/`) if it is not already there, and have `VisitFinalizationService` depend on that, not on any billing widget.
4. Define the input DTO in a place both features may depend on: put `VisitFinalizationRequest` (lines, discount type, discount value) in `frontend/lib/features/billing/domain/visit_billing_models.dart` (Visits already depends on that file legitimately from `visit_submitted_confirmation_data.dart:4`).
5. Rewrite `_handleFinalize` in `visit_billing_flow.dart` so it no longer touches Visits: delete the imports on lines 13, 18 and 19; delete the `docNotifier` lookup (86–89); instead invoke a callback `widget.onFinalizeRequested(VisitFinalizationRequest(...))` supplied by the caller, and let it report success/failure back for the submitting flag.
6. Remove the remaining `visit_documentation_notifier.dart` imports from `visit_billing_page.dart:11`, `visit_service_selection_step.dart:16` and `visit_invoice_review_step.dart:28`. For each, identify the specific values read from `VisitDocumentationState` (patient identity, visit id, saved services) and pass them in as constructor parameters of the billing widget instead.
7. In Visits, wire the callback: in `frontend/lib/features/visits/presentation/widgets/visit_summary_section.dart` (which already calls `notifier.completeVisit()` at line 110) and in the widget that presents the billing flow, implement `onFinalizeRequested` by calling `ref.read(visitFinalizationServiceProvider).finalize(...)`. While doing this, resolve the unused `expectedUpdatedAt` parameter on `completeVisit` — either delete it from the signature (line 230) or use it at line 266 instead of `current.expectedUpdatedAt`; do not leave both.
8. Delete the `completeVisit()` call at `visit_billing_flow.dart:89` entirely once step 7 is in place, and verify with `rg "features/visits" frontend/lib/features/billing` that the output is empty.
9. Break the reverse edge: move `visit_invoice_summary_panel.dart` from `features/billing/presentation/widgets/visit_billing/` into a shared location, or (preferred, smaller change) have `visit_submitted_combined_confirmation.dart` accept the already-built summary widget as a `Widget` parameter from its caller so the import on line 10 can be deleted. Verify with `rg "features/billing/presentation" frontend/lib/features/visits`.
10. Replace the hardcoded string at `visit_billing_flow.dart:119` with a localization key added under `frontend/lib/l10n/`.
11. Add `frontend/test/unit/visits/visit_finalization_service_test.dart` asserting: (a) when invoice issuing throws, `completeVisit` is never called and the visit remains editable; (b) on success both happen exactly once and `expectedUpdatedAt` is forwarded; (c) when `canCreateInvoices` is false, the visit still completes.

## C4 — The `core/` design system imports the Visits domain, inverting the core → feature dependency rule

**Severity:** Critical (architectural inversion in the shared foundation)

**Location:**
- `frontend/lib/core/ui/components/app_rich_text_editor.dart:10` — `import 'package:ai_clinic/features/visits/domain/rich_text_draft_utils.dart';` (file also declares `class AppRichTextEditor extends StatefulWidget` at line 162)
- `frontend/lib/features/visits/domain/rich_text_draft_utils.dart` — functions `richDeltaIsEffectivelyEmpty(List<dynamic>? deltaJson)` and `plainTextFromRichDelta(List<dynamic>? deltaJson)`

**Issue.** `AppRichTextEditor` is a **generic, shared design-system component** living in `core/ui/components/`. It reaches into a **feature** package to obtain two pure Quill-delta helpers:

```1:27:frontend/lib/features/visits/domain/rich_text_draft_utils.dart
import 'package:flutter_quill/flutter_quill.dart';

/// Whether a stored Quill delta JSON has no meaningful text content.
bool richDeltaIsEffectivelyEmpty(List<dynamic>? deltaJson) { ... }

/// Plain-text fallback for a stored Quill delta when editor flush callbacks are unavailable.
String plainTextFromRichDelta(List<dynamic>? deltaJson) { ... }
```

This is a `core → features` edge, which is the one dependency direction the layering forbids unconditionally. Note also that these two functions contain **zero visit-specific or clinical logic** — they are pure Quill delta utilities that happen to have been written while building the visits notes editor, and they were placed in `visits/domain/` rather than in `core/`. The file additionally imports `flutter_quill`, meaning a Visits *domain* file depends on a UI toolkit (this same file is one of the offenders in finding H3).

**Why it is a problem.**
1. **It breaks the dependency graph at the root.** `core/` is depended upon by every feature. With this edge, `core` transitively depends on `features/visits`, so Visits can never be removed, renamed, or extracted, and any feature that uses `AppRichTextEditor` silently pulls in the Visits package.
2. **It defeats the point of the design system.** Another feature (e.g. billing notes, patient notes) using `AppRichTextEditor` is now coupled to Visits for no functional reason.
3. **It creates a latent cycle.** Visits presentation already imports `core/ui`, and `core/ui` now imports Visits domain — the only reason this compiles is that Dart tolerates library-level cycles within a package, so the compiler will not stop this from getting worse.
4. **The helper is misfiled, so the fix is trivial and pure upside.** There is no trade-off here: moving two toolkit-level functions into `core/` removes the violation with no behavioural change.

**Recommended architectural solution.** Move the two functions to `core/`, where a Quill-aware shared component may legitimately live, and update all importers. Nothing needs to stay in `features/visits/domain/`.

**Suggested implementation steps.**

1. Create `frontend/lib/core/ui/rich_text/rich_text_delta_utils.dart` (create the `rich_text` directory if needed) and move the entire contents of `frontend/lib/features/visits/domain/rich_text_draft_utils.dart` into it verbatim, keeping the same function names `richDeltaIsEffectivelyEmpty` and `plainTextFromRichDelta` and the `flutter_quill` import.
2. Delete `frontend/lib/features/visits/domain/rich_text_draft_utils.dart`.
3. Run `rg -n "rich_text_draft_utils" frontend/lib frontend/test` to list every importer.
4. In each importer, replace the import with `package:ai_clinic/core/ui/rich_text/rich_text_delta_utils.dart`. Known sites: `frontend/lib/core/ui/components/app_rich_text_editor.dart:10`, plus the Visits presentation call sites (the phase canvases `visit_intake_section.dart`, `visit_findings_section.dart`, `visit_treatment_section.dart` and `visit_documentation_notifier.dart` if they reference the helpers).
5. If `frontend/lib/core/ui/widgets/widgets.dart` (the barrel file) re-exports design-system components, add the new file there only if other files import via the barrel; otherwise leave it out.
6. Move any existing unit test for these helpers from `frontend/test/unit/visits/` to `frontend/test/unit/core/rich_text_delta_utils_test.dart` and update its import.
7. Verify the violation is gone: `rg -n "package:ai_clinic/features" frontend/lib/core` must return **no results**. If it returns other hits, treat each as the same class of defect and relocate the shared code the same way.
8. Run `flutter analyze` and the unit test suite to confirm no unresolved imports remain.

## H1 — The whole `visits/application/` persistence layer is dead code that inverts layering

**Severity:** High

**Location:** `frontend/lib/features/visits/application/visit_encounter_persistence.dart` (339 lines)
- `class VisitEncounterPersistence` (line 9), constructor `VisitEncounterPersistence(this.ref, {required this.visitId, required this.deferPersistence})` (line 10)
- factory/provider function `visitEncounterPersistence(...)` (lines 361–366)
- offending import: line 6, `import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';`

**Issue.** This file defines a complete application-layer persistence facade with **28 public methods** — `createVisitVitalSign`, `updateVisitVitalSign`, `archiveVisitVitalSign`, `createVisitInvestigation`, `updateVisitInvestigation`, `archiveVisitInvestigation`, `recordInvestigationResult`, `createTreatmentPlan`, `updateTreatmentPlan`, `archiveTreatmentPlan`, `stageAttachment`, `uploadAndRegisterAttachment`, `deleteVisitAttachment`, and the full patient-safety set (`createPatientAllergy`/`update`/`archive`, `createPatientMedication`/`update`/`archive`, `createPatientChronicCondition`/`update`/`archive`) — plus a `deferPersistence` flag that implements exactly the "stage in draft vs. write through" policy that `VisitDocumentationNotifier` also implements inline.

**It is entirely unreachable.** A repository-wide search for `VisitEncounterPersistence` and `visit_encounter_persistence` returns hits **only inside the file itself** (the class declaration at line 9 and its own factory at lines 361–366). No widget, notifier, provider, or test imports it.

It is also architecturally inverted: an `application/` file imports a `presentation/` provider (line 6), i.e. the inner layer depends on the outer one. And it imports `data/` (lines 3–4) alongside that presentation dependency, so it sits *between* two layers it should not simultaneously bridge in that direction.

**Why it is a problem.**
1. **It is a decoy.** 339 lines that look like the intended architecture (and that a future contributor or an AI agent will reasonably assume is live) but which have zero runtime effect. Any bug fixed here is not fixed in the app; any behaviour read from here is misleading. It near-guarantees wasted or wrong edits.
2. **It duplicates the real logic divergently.** The same 28 operations exist inside `VisitDocumentationNotifier` (finding H2). Two copies of the deferred-persistence policy will drift, and the dead copy makes it ambiguous which one is canonical.
3. **It hides the layering violation.** Because it is unreachable, the `application → presentation` import produces no runtime problem and so never gets fixed, while still being copied as a pattern.
4. **It inflates apparent complexity.** Any reviewer or tool measuring the feature counts 339 lines of orchestration that does not exist.

**Recommended architectural solution.** Pick one of two directions and execute it fully — do not leave the file in its current state. **Preferred: delete it.** The notifier already implements this behaviour and is the accepted architecture for Visits per `docs/architecture/07-frontend.md` ("notifier calls repository/persistence directly; orchestration-heavy"). The alternative — adopting it as the real orchestrator — is only worth doing as part of the H2 split, and requires first removing its presentation import.

**Suggested implementation steps (delete path).**

1. Confirm it is still unreachable: run `rg -n "VisitEncounterPersistence|visit_encounter_persistence" frontend/lib frontend/test`. Expect matches only within `frontend/lib/features/visits/application/visit_encounter_persistence.dart`.
2. If any test file appears in that output, note the test names — they are testing dead code and should be deleted along with it (or ported to the notifier's tests).
3. Delete `frontend/lib/features/visits/application/visit_encounter_persistence.dart`.
4. Run `flutter analyze` and confirm no unresolved references appear.
5. Verify `frontend/lib/features/visits/application/` still contains `visit_rpc_messages.dart` (which **is** used, including from `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart:13`) and do not remove it.
6. If instead the adopt path is chosen: first delete the import on line 6 and replace every use of notifier types inside the file with plain domain types from `frontend/lib/features/visits/domain/`, then make `VisitDocumentationNotifier` delegate to it as part of finding H2's step for the persistence collaborator, and add unit tests. Do not merge a half-adopted state.

## H2 — `VisitDocumentationNotifier` is a 1423-line god object owning eight unrelated concerns

**Severity:** High

**Location:** `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` — `class VisitDocumentationNotifier` and `class VisitDocumentationState`, provider at line 182 (`visitDocumentationProvider`)

**Issue.** A single Riverpod `AsyncNotifier` and its single state class own all of the following:

| Concern | Approximate location |
| -- | -- |
| Rich-text note drafts (`complaint`, `history`, `examination`, `diagnosis`, `plan`, `richTextDrafts`) | state class + `save()` (393) |
| Note persistence + optimistic concurrency (`expectedUpdatedAt`, `DocumentationSaveStatus`) | 24, 90, 256, 344–460 |
| Visit lifecycle transition (`completeVisit`) | 230–271 |
| Vital signs CRUD + BMI/predefined sign resolution | draft mutators + 1167–1191 |
| Investigations CRUD + result recording + draft-id remapping | 585, 688–744, 1193–1231 |
| Treatment plans / prescriptions CRUD | 1233–1261 |
| Attachments staging, upload, delete (incl. org-context validation) | 1263–1281 |
| Patient-safety data (allergies, medications, chronic conditions) — data belonging to the **patient**, not the visit | 1283–1337 |
| Edit-mode / view-mode flags (`noteEditMode`, `workspaceEditMode`) | state class |
| The 220-line non-transactional flush orchestration | `_flushEncounterDraft` 1160–1379 |

This is already recorded as flaw **H5** in `docs/architecture/ARCHITECTURAL_FLAWS.md` ("monolithic notifier: draft, save, safety, attachments, completion — split by concern") and is still unresolved. It is repeated here only because the review produced a concrete split plan.

**Why it is a problem.**
1. **It is the direct cause of C1, C2, H4 and M4.** All four defects are consequences of one object owning too much: the dirty-state knowledge exists but nothing exposes it (C1); the flush cannot be made resumable without touching 20 interleaved loops (C2); the stale status is set in one region and the recovery method sits 1000 lines away unused (H4); and three overlapping visit representations coexist in one state class (M4).
2. **Every widget rebuild is over-broad.** One state class means a keystroke in a note and an attachment upload notify the same listeners. Widgets must use `select` defensively everywhere or accept whole-canvas rebuilds.
3. **It is effectively untestable in units.** Testing attachment upload requires constructing the entire visit documentation state, including notes and patient safety.
4. **Patient-safety data is in the wrong aggregate.** Allergies, medications and chronic conditions belong to the patient and are mutated here through visit-scoped state, which is why `patient_safety_provider.dart` also exists and partially overlaps.
5. **Merge hazard.** A single 1423-line file that nearly every Visits widget and four Billing widgets import is a permanent conflict hotspot.

**Recommended architectural solution.** Split by aggregate into four notifiers plus one stateless persistence collaborator, keeping `visitDocumentationProvider` as the note/lifecycle owner so the migration can be incremental and the widest-used API stays put.

- `VisitNotesNotifier` — the five note sections, `richTextDrafts`, `expectedUpdatedAt`, `DocumentationSaveStatus`, `save()`, stale handling.
- `VisitClinicalDataNotifier` — vital signs, investigations, investigation results, treatment plans (the draft + its flush).
- `VisitAttachmentsNotifier` — staging, upload, delete, org-context validation.
- `PatientSafetyNotifier` — allergies, medications, chronic conditions; merge with the existing `frontend/lib/features/visits/presentation/providers/patient_safety_provider.dart` rather than adding a fourth overlapping source.
- `VisitEncounterFlusher` (plain class, no Riverpod state) — owns the resumable flush from C2 and is shared by the three data notifiers.

**Suggested implementation steps.**

1. Create `frontend/lib/features/visits/presentation/providers/visit_attachments_notifier.dart`. Move the attachment fields out of `VisitDocumentationState` (`pendingAttachments`, `deletedAttachmentIds`) and the attachment methods out of the notifier, along with the flush block at lines 1263–1281 and the `orgId` validation at 1264–1266. Do attachments first: it is the smallest, most isolated slice.
2. Update the attachment widgets under `frontend/lib/features/visits/presentation/widgets/` to watch the new provider. Find them with `rg -n "pendingAttachments|deletedAttachmentIds|stageAttachment" frontend/lib/features/visits/presentation`.
3. Create `frontend/lib/features/visits/presentation/providers/visit_patient_safety_notifier.dart`. Move `draft.patientSafety` and the flush block at lines 1283–1337 into it. Reconcile with the existing `patient_safety_provider.dart`: keep one provider that both reads the safety context and mutates it, and delete the redundant one.
4. Create `frontend/lib/features/visits/application/visit_encounter_flusher.dart` containing the resumable flush described in C2, taking the repository and attachment service as constructor arguments and returning a result object listing what was persisted and what remains. Implement C2's per-item removal here so it is written once.
5. Create `frontend/lib/features/visits/presentation/providers/visit_clinical_data_notifier.dart`. Move vital signs, investigations, investigation results and treatment plans (state fields, mutators around lines 585–744, and flush blocks 1167–1261) into it, delegating persistence to `VisitEncounterFlusher`.
6. Leave notes, `expectedUpdatedAt`, `DocumentationSaveStatus`, `save()` and `completeVisit()` in `VisitDocumentationNotifier`, and rename nothing yet so the four Billing importers keep compiling until C3 removes them.
7. Introduce a coordinating provider `visitSaveAllProvider` (or keep `saveAll()` on `VisitDocumentationNotifier`) that awaits notes save, then the clinical-data flush, then attachments, then patient safety, and aggregates the results — preserving the current ordering and the `false`-on-failure contract at lines 344–390.
8. After each of steps 1, 3 and 5, run `flutter analyze` and the Visits unit tests (`flutter test test/unit/visits`) before starting the next; do not attempt all four in one change.
9. Add one unit test file per new notifier under `frontend/test/unit/visits/`, each constructing only its own state.
10. When the file drops below ~400 lines, update `docs/architecture/ARCHITECTURAL_FLAWS.md` flaw H5 to reflect the resolution and update `docs/architecture/14-visits-encounter-workspace.md` with the real provider names.

## H3 — The Visits `domain/` layer depends on `presentation/`, `data/`, the design system, and Flutter Material

**Severity:** High

**Location:** four files in `frontend/lib/features/visits/domain/`:

| File | Offending import | Depends on |
| -- | -- | -- |
| `visit_submit_readiness.dart:4` | `features/visits/presentation/providers/encounter_step_provider.dart` | presentation |
| `visit_submit_readiness.dart:5` | `features/visits/presentation/providers/visit_documentation_notifier.dart` | presentation |
| `visit_encounter_draft.dart:3` | `features/visits/data/visit_attachment_service.dart` | data |
| `treatment_plan_options.dart:1` | `core/ui/components/app_select.dart` | design system (UI) |
| `encounter_phase.dart:1` | `package:flutter/material.dart` | Flutter Material (icons/labels) |
| `rich_text_draft_utils.dart:1` | `package:flutter_quill/flutter_quill.dart` | UI toolkit (also see C4) |

**Issue.** `docs/architecture/07-frontend.md` states the domain layer depends on **nothing** — it is the innermost layer. Six imports across five files break that, in three escalating degrees:

1. **Domain → presentation (worst).** `visit_submit_readiness.dart` — the file that decides whether a visit may be submitted, i.e. the single most important clinical business rule in the feature, and the one whose doc comment at line 23 says it "matches the `complete_visit` RPC" — imports two Riverpod **presentation providers**. The rule cannot be evaluated or tested without constructing UI-layer state.
2. **Domain → data.** `visit_encounter_draft.dart`, the core draft aggregate, imports `visit_attachment_service.dart` from `data/` (it needs the file-pick type used by `pendingAttachments`). The innermost model therefore depends on the Supabase-backed service.
3. **Domain → UI.** `treatment_plan_options.dart` imports `AppSelect` from the design system, so dosage/frequency/duration option lists are expressed as UI select options rather than plain domain values. `encounter_phase.dart` imports `flutter/material.dart` to carry `IconData` and display labels on the `EncounterPhase` enum, mixing presentation metadata into a domain concept.

(`package:flutter/foundation.dart` appears in most other domain files for `@immutable` / `listEquals`. That is conventional in Flutter projects and **not** counted as a violation here.)

**Why it is a problem.**
1. **The submit rule is untestable and unreusable.** `visit_submit_readiness.dart` cannot be unit-tested without Riverpod containers and full notifier state, and it cannot be reused by any non-UI caller. For a clinical gating rule, that is the highest-value logic in the feature to have under cheap, isolated tests.
2. **It makes the layering unenforceable.** Once domain imports presentation, no lint or CI check can assert layer direction for this feature, and the pattern gets copied — as it already has been, across five files.
3. **It creates cycles.** `presentation → domain → presentation` is a real cycle today (`visit_documentation_notifier.dart` and `visit_submit_readiness.dart` reference each other's layers), which forces any refactor of the notifier to also touch the domain rule.
4. **It couples clinical vocabulary to widget choices.** With `EncounterPhase` carrying `IconData` and `treatment_plan_options` returning `AppSelect` options, changing a design-system component signature would require editing domain files.

**Recommended architectural solution.** Invert each dependency so domain exposes plain data and the outer layers adapt it: pass values *into* domain functions instead of letting domain read state; move UI metadata into extension methods that live in `presentation/`.

**Suggested implementation steps.**

1. **`visit_submit_readiness.dart`** — change its API to take primitives. Define a plain input record/class in the same file, e.g. `VisitSubmitReadinessInput({required Map<ClinicalNoteSection, String> noteTexts, required bool hasVitals, required bool hasInvestigations, required bool hasTreatmentPlans, required EncounterPhase activePhase})`, and make the readiness function accept it. Delete the imports on lines 4 and 5.
2. Move the state-to-input conversion into presentation: add a small mapper (e.g. `VisitSubmitReadinessInput fromState(VisitDocumentationState state, EncounterPhase phase)`) in `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` or a new `presentation/providers/visit_submit_readiness_provider.dart`, and update every call site found via `rg -n "visit_submit_readiness|SubmitReadiness" frontend/lib frontend/test`.
3. Add `frontend/test/unit/visits/visit_submit_readiness_test.dart` covering the readiness matrix with plain inputs and no Riverpod container.
4. **`visit_encounter_draft.dart`** — remove the `data/` import on line 3 by declaring the pick type in domain: create `frontend/lib/features/visits/domain/visit_attachment_pick.dart` with an immutable `VisitAttachmentPick({required String fileName, required int sizeBytes, required String mimeType, ...})` holding only plain fields, and use it for `pendingAttachments`. Have `frontend/lib/features/visits/data/visit_attachment_service.dart` accept/convert that domain type at its boundary instead of exposing its own type upward.
5. Update the attachment-picking widgets and `_flushEncounterDraft` (around line 1268, `attachmentService.uploadAndRegister(... pick: pending.pick ...)`) to construct and consume `VisitAttachmentPick`.
6. **`treatment_plan_options.dart`** — change the option lists to return plain `List<String>` (or a domain `TreatmentPlanOption` value class with `value`/`label`) and delete the `app_select.dart` import. Add the `AppSelect`-shaped mapping as an extension in `frontend/lib/features/visits/presentation/widgets/` next to the treatment-plan form that consumes it.
7. **`encounter_phase.dart`** — strip `IconData` and display labels from the enum and delete the `flutter/material.dart` import, leaving only the phase identities and ordering. Create `frontend/lib/features/visits/presentation/widgets/encounter_phase_presentation.dart` with `extension EncounterPhasePresentation on EncounterPhase { IconData get icon; String label(BuildContext context); }` and move the icon/label mapping there, sourcing labels from localizations rather than literals.
8. **`rich_text_draft_utils.dart`** — resolved by finding C4 (relocate to `core/ui/rich_text/`). Do C4 first so the readiness file's line 1 import is updated only once.
9. Verify: `rg -n "presentation|/data/|core/ui|flutter/material|flutter_quill" frontend/lib/features/visits/domain` should return no results except benign `flutter/foundation.dart` (which this pattern does not match).
10. Add a CI guard so this cannot regress: extend the existing analysis setup in `frontend/analysis_options.yaml` with a `depend_on_referenced_packages`-style custom lint or add a script `frontend/tool/check_layering.sh` that greps each feature's `domain/` for `presentation`, `data/`, and `core/ui` imports and exits non-zero, then call it from CI.

## H4 — `STALE_DOCUMENTATION` is an unrecoverable dead end: the recovery method exists but is never called

**Severity:** High (functional dead end + guaranteed data loss on concurrent edit)

**Location:** `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`
- `VisitDocumentationNotifier.save()` — the stale branch, lines 443–450
- `DocumentationSaveStatus` enum — line 24 (`idle, saving, saved, stale, error`)
- `VisitDocumentationState.hasUnsavedDraft` — lines 85–94 (returns `true` whenever status is `stale`)
- `VisitDocumentationNotifier.reloadAfterStale()` — lines 1414–1417, and `reloadVisit()` — lines 1409–1412
- Concurrency-token forwarding in `completeVisit()` — lines 256–271

**Issue.** The optimistic-concurrency design is half-wired. When the server rejects a note save because another user changed the documentation, the notifier records the conflict but **never refreshes the concurrency token**:

```443:450:frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart
    } on RpcFailure catch (error) {
      final currentAfter = state.value ?? current;
      if (error.code == 'STALE_DOCUMENTATION') {
        state = AsyncData(
          currentAfter.copyWith(saveStatus: DocumentationSaveStatus.stale, errorMessage: visitMessageForRpc(error)),
        );
        return;
      }
```

`copyWith` here changes only `saveStatus` and `errorMessage`. `expectedUpdatedAt` keeps the **same stale value** that was just rejected (it is passed to the RPC at line 421). Therefore every subsequent `save()` sends the identical stale token and fails identically — the visit's notes can **never** be saved again for the lifetime of the provider. The only escape is disposing the provider by navigating away, which under C1 destroys the draft.

Two recovery methods were written for exactly this situation and **neither is ever called**:

```1409:1417:frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart
  Future<void> reloadVisit() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> reloadAfterStale() async {
    ref.invalidateSelf();
    await future;
  }
```

A repository-wide search for `reloadAfterStale` and `reloadVisit(` returns matches **only** at these declarations — no widget, dialog, or test invokes them. So the `stale` enum value can be entered but not exited, and the two methods are dead code (also counted in M5).

This compounds with `completeVisit()`: the comment at line 265 says *"Always use post-save refreshed token; caller value may be stale after saveAll/flush."* — but if the note save already failed as stale, the token was never refreshed, so completion inherits the same permanently-stale token.

**Why it is a problem.**
1. **Hard functional dead end.** Two clinicians touching one visit (a realistic scenario: nurse records intake while doctor documents findings) leaves the second one unable to save at all, with a message and no action.
2. **Guaranteed data loss.** Because the only way out is navigating away, and there is no unsaved-changes guard (C1), the conflict funnels the user straight into discarding their work.
3. **The design intent exists but is unreachable**, which makes the bug invisible in review — the code *looks* like it handles conflicts.
4. **No merge affordance.** Even with a reload wired up, blindly reloading would overwrite the local draft. The user needs to be shown the conflict and offered a choice; nothing in the UI does this today (`rg` for `stale` in `frontend/lib/features/visits/presentation/widgets` shows only status-badge rendering, not a resolution action).

**Recommended architectural solution.** Make `stale` an exitable state with an explicit, non-destructive resolution: refresh the token and the server copy, keep the user's draft in memory, and present a two-option resolution (Overwrite with my version / Discard mine and load theirs). Wire it to a visible action in the save-status UI.

**Suggested implementation steps.**

1. In `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`, add `Future<void> resolveStaleConflict({required bool keepLocalDraft})`:
   - fetch the server copy: `final refreshed = await ref.read(visitRepositoryProvider).getVisit(visitId: current.visit.id);`
   - compute the new token: `final newToken = refreshed.documentation?.updatedAt ?? refreshed.updatedAt;`
   - if `keepLocalDraft` is true, rebuild state from `refreshed` but `copyWith` the user's current `complaint/history/examination/diagnosis/plan/richTextDrafts`, set `expectedUpdatedAt: newToken`, and set `saveStatus: DocumentationSaveStatus.idle` with `clearError: true` (mirror the shape used at lines 430–441);
   - if false, use `VisitDocumentationState.fromVisit(refreshed, ...)` unmodified with `expectedUpdatedAt: newToken` and `saveStatus: idle`.
2. Add a field to the state to preserve the other party's version for display: `VisitClinicalNote? conflictingServerNote`, populated in step 1 and cleared on the next successful save. Set it in the stale branch too (fetch the server copy there) so the UI can show both versions.
3. Modify the stale branch at lines 443–450 to also store the server note and the refreshed token in a **separate** field (e.g. `staleServerUpdatedAt`) rather than overwriting `expectedUpdatedAt` directly, so an accidental blind retry still cannot silently clobber the other user's work; `resolveStaleConflict` is the only path that promotes it into `expectedUpdatedAt`.
4. Delete `reloadAfterStale()` (lines 1414–1417) — it is superseded by step 1. Keep `reloadVisit()` only if you wire it to a manual refresh button; otherwise delete it too.
5. Create `frontend/lib/features/visits/presentation/widgets/visit_stale_conflict_dialog.dart` exporting `Future<bool?> showVisitStaleConflictDialog(BuildContext context, {required VisitClinicalNote serverNote})` returning `true` for "keep mine", `false` for "load theirs", `null` for cancel. Show the two versions side by side using the existing note-rendering widget.
6. Add the dialog strings to `frontend/lib/l10n/` and regenerate localizations.
7. Find the widget that renders save status (grep `DocumentationSaveStatus` under `frontend/lib/features/visits/presentation/widgets/`) and add a visible "Resolve conflict" action when status is `stale`, calling the dialog then `resolveStaleConflict(keepLocalDraft: result)`.
8. In `completeVisit()` (lines 230–271), if `saveStatus == DocumentationSaveStatus.stale`, return a failure result immediately with a message directing the user to resolve the conflict, instead of sending the stale token (the existing check at line 256 already distinguishes `STALE_DOCUMENTATION` from `INVALID_INPUT` — extend it rather than replacing it).
9. Add `frontend/test/unit/visits/visit_documentation_stale_conflict_test.dart`: fake repository throws `RpcFailure(code: 'STALE_DOCUMENTATION')` on the first `saveVisitDocumentation`, then succeeds. Assert (a) status becomes `stale`, (b) a naive second `save()` still fails, (c) after `resolveStaleConflict(keepLocalDraft: true)` the token is updated and `save()` succeeds, and (d) with `keepLocalDraft: true` the local note text survives.

## H5 — Save-before-complete correctness depends on an `autoDispose` provider surviving a cross-feature route push

**Severity:** High (latent silent data loss; no test protects the invariant)

**Location:**
- `frontend/lib/features/visits/presentation/widgets/visit_summary_section.dart` — `_beginBilling()` lines 92–103, `_finalizeVisit()` lines 105–135
- `frontend/lib/app/navigation/app_navigator.dart:65` — `void pushVisitBilling(String visitId) => _context.push(AppRoutes.billingVisit(visitId));`
- `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart:182` — `AsyncNotifierProvider.autoDispose`
- `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` — `completeVisit()` lines 245–262 (the internal `saveAll()`) and `needsPersistBeforeSubmit` (state getter, around line 109)
- `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart:89` — the billing-side `completeVisit()` call

**Issue.** The mechanism that protects unsaved work at completion is *inside* `completeVisit()`:

```245:262:frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart
    if (_canEditVisit(initial.visit)) {
      prepareEncounterReview();

      final afterFlush = state.value ?? initial;
      if (afterFlush.needsPersistBeforeSubmit) {
        final saved = await saveAll();
        if (!saved) { ... throw RpcFailure(...); }
      }
    }
```

This is correct **only if `state` belongs to the same notifier instance that holds the user's draft.** But the billing handoff crosses a route boundary into another feature:

1. `_beginBilling()` (line 92) navigates with `context.nav.pushVisitBilling(widget.visitId)` (line 102) **without flushing anything first** — no `saveAll()`, no `_saveEdits()`.
2. The billing page and `visit_billing_flow.dart` then re-acquire the notifier by `ref.read(visitDocumentationProvider(visitId).notifier)` and call `completeVisit()` at line 89.
3. `visitDocumentationProvider` is `autoDispose`. If the Visits page's subscription has ended for any reason — the route below being disposed, a `maintainState: false` page, a shell branch swap, a future change from `push` to `go`, or a rebuild that momentarily drops the last listener — Riverpod creates a **fresh** notifier for the billing page. That fresh instance loads state from the server, so `needsPersistBeforeSubmit` is `false`, `saveAll()` is skipped, and `completeVisit()` succeeds against server state while the user's in-memory draft is gone.
4. After completion the visit is no longer editable (`canSubmitVisit` / `_canEditVisit` gate at lines 235–245, and `save()` returns early at line 398 via `_canMutateVisit`), so the lost draft can **never** be re-saved.

Today this happens to work because `_context.push` leaves the Visits route mounted beneath the billing route, keeping the provider alive. That is an implementation detail of the navigator, not an expressed invariant: nothing documents it, nothing asserts it, and no test covers it. The same latent hazard applies to the no-permission path — `_beginBilling` calls `_finalizeVisit()` (line 95) which calls `completeVisit()` (line 110) — though there the notifier is definitely the local one, so that path is currently safe.

`_finalizeVisit` also hardcodes English literals at lines 116 and 129 (`'Could not finalize the visit. Please try again.'`).

**Why it is a problem.**
1. **The invariant is invisible and one refactor away from breaking.** Changing `pushVisitBilling` to `_context.go`, adding `maintainState: false`, or moving billing into a different shell branch would silently turn this into guaranteed data loss for every finalization. A reviewer of that change has no signal.
2. **The failure mode is silent and irreversible.** No error is raised; the visit completes successfully, and the clinical note is simply missing. Combined with the read-only-after-completion rule, there is no recovery in the UI.
3. **Responsibility is in the wrong place.** "Everything is persisted" should be established *before* leaving the workspace, at the handoff, not implicitly relied upon inside a method called from another feature.
4. **It is untested.** There is no test asserting that a dirty draft is flushed before completion via the billing route.

**Recommended architectural solution.** Flush explicitly at the handoff and make the unflushed case impossible to reach: save before navigating to billing, and have the finalization entry point *verify* (not assume) that nothing is pending, failing loudly if it is. Combined with C3 (finalization moves into a Visits application service) and C1 (dropping `autoDispose`), the reliance on navigator behaviour disappears entirely.

**Suggested implementation steps.**

1. In `frontend/lib/features/visits/presentation/widgets/visit_summary_section.dart`, change `_beginBilling()` to flush before navigating: read the state, and if `hasUnsavedDraft || hasPendingEncounterDraft` (see H4/C1 for these getters), `await ref.read(visitDocumentationProvider(widget.visitId).notifier).saveAll()`; abort navigation and show the existing error toast if it returns `false`.
2. Only after a successful flush call `context.nav.pushVisitBilling(widget.visitId)` (line 102). Guard with `if (!mounted) return;` after the await, matching the pattern already used at lines 99–101.
3. Remove `autoDispose` from `visitDocumentationProvider` (line 182) as described in C1 step 3, so a re-`read` from the billing page can never produce a fresh, draft-less instance.
4. Add a defensive assertion inside `completeVisit()`: after the block at lines 245–262, re-read `state.value` and if `needsPersistBeforeSubmit` is still `true`, throw `RpcFailure` with code `'INVALID_INPUT'` and a message about unsaved changes instead of proceeding to line 271. This converts silent loss into a visible, safe failure.
5. Replace the hardcoded strings at lines 116 and 129 with localization keys added under `frontend/lib/l10n/`.
6. Once C3 is implemented, delete the `completeVisit()` call at `visit_billing_flow.dart:89` so the only completion entry points live in Visits.
7. Add a widget/integration test `frontend/test/widget/visits/visit_billing_handoff_test.dart` that: seeds a dirty draft, taps the begin-billing action, and asserts `saveAll` was invoked before the navigation occurred; then a second case where `saveAll` fails and asserts navigation did **not** occur.
8. Add a unit test asserting that calling `completeVisit()` on a notifier whose state reports `needsPersistBeforeSubmit == true` and whose `saveAll` is stubbed to no-op throws rather than completing the visit (covers step 4).

## H6 — Invoice details are dropped from the finalize confirmation on the success path, but shown on the error path

**Severity:** High (functional bug, inverted behaviour)

**Location:** `frontend/lib/features/visits/presentation/widgets/visit_submitted_dialog.dart`
- `class _VisitSubmittedDialogBody extends ConsumerWidget`, `build()` — the `appointmentAsync.when(...)` at lines 75–104
- the `error:` branch, lines 77–92 (passes `invoicePreview` and `persistedInvoice`)
- the `data:` branch, lines 93–103 (**omits both**)
- fields declared at lines 59–60, plumbed in from `VisitSubmittedDialog.show(...)` lines 25–26 and 40–41
- producer: `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart:123–132`

**Issue.** The dialog receives the finalized invoice correctly. `visit_billing_flow.dart` captures the preview and the persisted invoice and passes both:

```123:132:frontend/lib/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart
      final invoicePreview = billing.invoicePreview;
      billingNotifier.reset();
      await VisitSubmittedDialog.show(
        context,
        ref,
        visit: completedVisit,
        actionAt: DateTime.now().toUtc(),
        invoicePreview: invoicePreview,
        persistedInvoice: invoice,
      );
```

`show()` forwards them into `_VisitSubmittedDialogBody` (lines 40–41), which stores them as fields (lines 59–60). But the body then builds `VisitSubmittedConfirmationData.fromVisit(...)` in **two** places, and only one of them passes the invoice through:

```93:103:frontend/lib/features/visits/presentation/widgets/visit_submitted_dialog.dart
      data: (appointment) => VisitSubmittedCombinedConfirmation(
        data: VisitSubmittedConfirmationData.fromVisit(
          visit: visit,
          patientName: patientName,
          branchName: branchName,
          appointmentStart: appointment.startTime,
          appointmentEnd: appointment.endTime,
          kind: kind,
          actionAt: actionAt,
        ),
      ),
```

The `error:` fallback immediately above (lines 79–91) *does* pass `invoicePreview: invoicePreview` and `persistedInvoice: persistedInvoice`. So the behaviour is exactly inverted: **the user sees the invoice summary only when the appointment lookup fails**, and never on the normal success path. Because both parameters are optional and nullable, the compiler accepts the omission silently.

The practical consequence: after finalizing a visit and issuing an invoice, the confirmation dialog renders with the invoice section empty or hidden (whatever `VisitSubmittedCombinedConfirmation` does with a null preview), so the clinician gets no confirmation of the amount charged, the discount applied, or the invoice number — the entire purpose of the combined confirmation described in `docs/architecture/15-billing.md`.

**Why it is a problem.**
1. **The billing outcome is invisible at the exact moment it matters.** Finalization is the one point where the user should verify what was charged; there is no other confirmation surface in the flow, and `billingNotifier.reset()` is called at line 124 *before* the dialog, so the preview cannot be recovered from billing state afterwards.
2. **Optional-nullable parameters hid the defect.** Two nearly identical `fromVisit(...)` call sites, differing only by two omitted named arguments, is precisely the shape that static analysis cannot catch. It will regress again as more fields are added.
3. **The duplication is the root cause, not the omission.** The same `VisitSubmittedConfirmationData` is constructed twice purely to substitute a fallback appointment window; every future field must be remembered in both places.
4. **Wasted work upstream.** `_createAndIssueInvoice` (line 151 onward) performs a multi-RPC sequence to build and issue the invoice, and its result is then discarded by the UI.

**Recommended architectural solution.** Build the confirmation data **once**, deriving only the appointment window from the async value, so no field can be forgotten in a branch.

**Suggested implementation steps.**

1. Open `frontend/lib/features/visits/presentation/widgets/visit_submitted_dialog.dart`.
2. In `_VisitSubmittedDialogBody.build`, replace the `appointmentAsync.when(...)` at lines 75–104 with: keep the `loading:` skeleton, but for the other two cases first resolve just the window:
   `final start = appointmentAsync.valueOrNull?.startTime ?? visit.visitDate;`
   `final end = appointmentAsync.valueOrNull?.endTime ?? visit.visitDate.add(const Duration(minutes: 30));`
   (preserving the existing 30-minute fallback from line 78).
3. Then construct `VisitSubmittedConfirmationData.fromVisit(...)` **exactly once**, passing `visit`, `patientName`, `branchName`, `appointmentStart: start`, `appointmentEnd: end`, `kind`, `actionAt`, `invoicePreview: invoicePreview`, `persistedInvoice: persistedInvoice`, and return a single `VisitSubmittedCombinedConfirmation(data: ...)`.
4. Handle `loading:` explicitly with the existing `AppSkeleton(variant: SkeletonVariant.rectangular, height: 340)` from line 76 so behaviour there is unchanged.
5. Make the omission impossible to repeat: in `frontend/lib/features/visits/presentation/widgets/visit_submitted_confirmation_data.dart`, change `fromVisit` so `invoicePreview` and `persistedInvoice` are **required** named parameters (still nullable: `required VisitBillingInvoicePreview? invoicePreview, required InvoiceDetail? persistedInvoice`). Then fix every call site the analyzer flags — including `visit_summary_section.dart:119`, which calls `VisitSubmittedDialog.show(context, ref, visit: completedVisit)` on the no-invoice path and should now explicitly pass `invoicePreview: null, persistedInvoice: null`.
6. Run `flutter analyze` and fix all newly reported call sites.
7. Add a widget test `frontend/test/widget/visits/visit_submitted_dialog_invoice_test.dart` asserting that with a non-null `persistedInvoice` the invoice total and invoice number are rendered **when the appointment provider resolves successfully** (the previously broken case), and also when it errors.

## M1 — Visits widgets reach directly into three other features' `presentation/` internals

**Severity:** Medium

**Location:**
- `frontend/lib/features/visits/presentation/pages/visit_document_page.dart` — lines 12, 14, 15 (`VisitDocumentPage.build`)
- `frontend/lib/features/visits/presentation/widgets/visit_submitted_dialog.dart` — lines 6, 7, 8 (`_VisitSubmittedDialogBody.build`, which watches all three at lines 64–66)

**Issue.** Visits presentation imports other features' presentation-layer providers and utilities directly:

| Importer | Import | Foreign feature layer |
| -- | -- | -- |
| `visit_document_page.dart:12` | `appointments/presentation/providers/appointment_detail_provider.dart` | presentation |
| `visit_document_page.dart:14` | `patients/presentation/providers/patient_detail_provider.dart` | presentation |
| `visit_document_page.dart:15` | `patients/presentation/utils/patient_presentation_formatting.dart` | presentation (utils) |
| `visit_submitted_dialog.dart:6` | `appointments/presentation/providers/appointment_detail_provider.dart` | presentation |
| `visit_submitted_dialog.dart:7` | `patients/presentation/providers/patient_detail_provider.dart` | presentation |
| `visit_submitted_dialog.dart:8` | `setup/presentation/providers/staff_assignable_branches_provider.dart` | presentation |

`_VisitSubmittedDialogBody.build` watches three foreign providers in a row (lines 64–66) and then applies local fallback formatting with hardcoded English placeholders `'Patient'` (line 68) and `'Branch'` (lines 71–72).

Two clarifications on what is **not** part of this finding: the domain-level imports (`appointments/domain/appointment_detail.dart:11`, `patients/domain/patient_detail.dart:13`, `billing/domain/*`) are legitimate cross-feature model sharing; and `visit_documentation_notifier.dart:6` importing `appointments/presentation/providers/appointment_surface_invalidation.dart` is an *explicit, named, single-purpose seam* (`invalidateAppointmentAfterVisitCompleted`, called at line 282) and is the pattern the other cases should follow. The billing-presentation import is covered separately by C3.

**Why it is a problem.**
1. **No seam means no contract.** Visits depends on the internal provider *names and shapes* of three features. Renaming `patientDetailProvider` or changing its state type breaks Visits, with nothing declaring the relationship.
2. **Duplicated fallback presentation.** Because Visits consumes raw async providers, it re-implements loading/error fallbacks (`'Patient'`, `'Branch'`) that the owning features already handle, and does so with untranslated literals.
3. **It normalizes the pattern that produced C3.** The billing cycle grew from exactly this habit; leaving these in place invites the next one.
4. **Testing cost.** Any widget test for the dialog or the page must override four foreign providers.

**Recommended architectural solution.** Each feature exposes a small, explicitly named read-only façade for cross-feature consumption, and Visits depends only on those. Mirror the existing, working `appointment_surface_invalidation.dart` convention.

**Suggested implementation steps.**

1. Create `frontend/lib/features/patients/presentation/providers/patient_summary_facade.dart` exposing a single provider `patientSummaryForVisitProvider = FutureProvider.family<PatientSummary, String>` where `PatientSummary` is a tiny immutable class (`fullName`, `mrn`, `age`, `sex`, plus whatever `patient_presentation_formatting.dart` currently supplies) built inside the patients feature, with its own loading/empty defaults and localized fallbacks.
2. Create `frontend/lib/features/appointments/presentation/providers/appointment_window_facade.dart` exposing `appointmentWindowProvider = FutureProvider.family<AppointmentWindow, String>` with `startTime`/`endTime` only — that is all Visits uses (see `visit_submitted_dialog.dart:98–99`).
3. Create `frontend/lib/features/setup/presentation/providers/branch_name_facade.dart` exposing `branchNameProvider = FutureProvider.family<String, String>` (branch id → display name), moving the `branches.where(...).map(...).firstOrNull ?? 'Branch'` logic from `visit_submitted_dialog.dart:69–73` into the setup feature and localizing the fallback.
4. Update `visit_submitted_dialog.dart`: delete imports on lines 6, 7, 8; replace the three `ref.watch` calls at lines 64–66 with the three façade providers; delete the local fallback literals at lines 68 and 71–73.
5. Update `visit_document_page.dart`: delete imports on lines 12, 14, 15; replace the corresponding `ref.watch` calls with the façade providers. Keep the `domain/` imports on lines 11 and 13 only if the page still needs the full models; if the façades cover its needs, remove those too.
6. Move any formatting helper Visits was borrowing from `patient_presentation_formatting.dart` behind the `PatientSummary` fields so Visits never calls patients' formatting utilities directly. Verify with `rg -n "patient_presentation_formatting" frontend/lib/features/visits` returning nothing.
7. Add the localized fallback strings introduced in steps 1 and 3 to `frontend/lib/l10n/` and regenerate.
8. Verify the boundary: `rg -n "features/(patients|appointments|setup)/presentation" frontend/lib/features/visits` should return only the façade imports and `appointment_surface_invalidation.dart`.

## M2 — Quill controller lifecycle and flush machinery is copy-pasted across the three phase canvases

**Severity:** Medium

**Location:** three files in `frontend/lib/features/visits/presentation/widgets/`:
- `visit_intake_section.dart` — `_complaintController`/`_historyController` (25–26), `_flushRegistered` (32), `_flushController` (103), `_syncControllers` (119), `_syncQuillController` (134)
- `visit_findings_section.dart` — `_examinationController`/`_diagnosisController` (23–24), `_flushRegistered` (30), `_flushController` (101), `_syncControllers` (117), `_syncQuillController` (132)
- `visit_treatment_section.dart` — `_planController` (26), `_flushRegistered` (30), `_flushController` (92), `_syncControllers` (99), `_syncQuillController` (103)

**Issue.** All three canvases implement the same five-part mechanism with the same private names at nearly the same line numbers — a textbook copy-paste: (1) `late final QuillController` per note section created in `initState` via `QuillController.basic()`; (2) a per-section flush closure assigned in `initState` (e.g. lines 42–43 in intake, 40–41 in findings, 38 in treatment); (3) register/unregister guarded by a `var _flushRegistered = false` flag with identical bodies (intake 67–85, findings 65–83, treatment 60–74); (4) `_flushController(section, controller)` that pushes the editor content into the notifier; (5) `_syncQuillController(...)` (~20 lines each) that pulls notifier state back into the controller, guarded by focus state, ending in a call to the shared helper `setQuillControllerFromDraft(controller, deltaJson, plainText)` (intake 154, findings 152, treatment 123).

The only differences between the three copies are which `ClinicalNoteSection` values they handle and how many controllers they own. Roughly 110 lines of identical bidirectional-sync logic exist in triplicate.

**Why it is a problem.**
1. **Three-way drift on the most fragile logic in the feature.** Bidirectional sync between an editor controller and external state — with focus guards to avoid clobbering the user's cursor — is exactly the code where a fix applied to one copy and not the others produces confusing, section-specific bugs (lost keystrokes, cursor jumps, stale text).
2. **It is the mechanism C1 and H4 depend on.** Any change to draft/dirty semantics or conflict resolution must be applied identically three times; missing one silently breaks that section only.
3. **Lifecycle bug surface is tripled.** Controller disposal, listener registration and the `_flushRegistered` guard are hand-maintained in each file; a missed `dispose` or double-registration leaks or double-writes, and each copy must be reviewed separately.
4. **Untestable as a unit.** Because it lives in three private `State` classes, the sync rules cannot be tested once; today none of the three is covered (no widget tests exist for Visits).

**Recommended architectural solution.** Extract a single reusable controller-owning widget or controller-manager class that encapsulates create/dispose/register/flush/sync for **one** clinical note section, and have all three canvases compose N instances of it. Keep the notifier interaction in one place.

**Suggested implementation steps.**

1. Create `frontend/lib/features/visits/presentation/widgets/clinical_note_field.dart` with `class ClinicalNoteField extends ConsumerStatefulWidget` taking: `required String visitId`, `required ClinicalNoteSection section`, `required String label`, and optional layout parameters (`minHeight`, `readOnly`).
2. Move into its `State`: the `QuillController.basic()` creation in `initState`, the `dispose()` teardown, the flush-closure registration with the `_flushRegistered` guard, `_flushController`, and `_syncQuillController` — copy the implementation from `visit_intake_section.dart` lines 25–43 and 67–160 verbatim, parameterized by `widget.section`.
3. Inside that `State`, read the notifier once: `ref.read(visitDocumentationProvider(widget.visitId).notifier)` for flush, and `ref.listen`/`ref.watch` the state to drive `_syncQuillController` (mirroring the existing `_syncControllers(state)` call sites at intake 91, findings 89, treatment 80).
4. Keep the shared `setQuillControllerFromDraft(...)` helper as-is and call it from the single new implementation. If it currently lives in Visits and is UI-generic, consider relocating it alongside the C4 move.
5. Rewrite `visit_intake_section.dart` to render two `ClinicalNoteField` widgets (`ClinicalNoteSection.complaint`, `ClinicalNoteSection.history`) and delete lines 25–43 and 67–160 (its controllers, flags, flush and sync methods). The file should keep only layout and section headers.
6. Do the same for `visit_findings_section.dart` (`examination`, `diagnosis`) and `visit_treatment_section.dart` (`plan`).
7. Confirm the duplication is gone: `rg -n "_syncQuillController|_flushRegistered" frontend/lib/features/visits` should match only `clinical_note_field.dart`.
8. Add `frontend/test/widget/visits/clinical_note_field_test.dart` covering: typing updates the notifier draft; an external state change while the field is unfocused updates the editor; an external state change while the field **is** focused does not clobber the caret; and the controller is disposed without error when the widget unmounts.
9. Run `flutter analyze` and the Visits tests; visually verify all three phases still render and edit correctly before removing the old code from the last file.

## M3 — Dialog widgets call the data-layer repository directly, bypassing the provider layer

**Severity:** Medium

**Location:**
- `frontend/lib/features/visits/presentation/widgets/investigation_form_dialog.dart` — `_searchInvestigations(String query)`, lines 68–80 (repository call at line 69)
- `frontend/lib/features/visits/presentation/widgets/treatment_plan_form_dialog.dart` — `_searchMedications(String query)`, lines 82–~94 (repository call at line 83)

**Issue.** Both dialogs reach straight into the data layer from inside a widget's `State` and map rows to UI models in the same method:

```68:79:frontend/lib/features/visits/presentation/widgets/investigation_form_dialog.dart
  Future<List<AppComboboxItem>> _searchInvestigations(String query) async {
    final items = await ref.read(visitRepositoryProvider).searchInvestigations(query: query);
    return [
      for (final item in items)
        AppComboboxItem(
          id: item.id,
          label: item.name,
          meta: item.defaultUnit,
          disabled: widget.usedInvestigationIds.contains(item.id) && item.id != widget.editingEntry?.investigationId,
          disabledReason: 'Already added',
        ),
    ];
  }
```

Note this is a **different** pattern from the accepted one. `docs/architecture/07-frontend.md` and `ARCHITECTURAL_FLAWS.md` L2 accept *notifiers* calling repositories directly for Visits; they do not sanction widget `State` classes doing so. Consequences visible in the snippet: the RPC is invoked on every keystroke the combobox emits with no debounce, throttle, request cancellation, or in-memory caching; there is no error handling, so an `RpcFailure` (offline, permission, timeout) escapes into the combobox's async callback and surfaces as an unhandled future rather than a message; and the disabled-reason string `'Already added'` (line 77) is a hardcoded English literal.

**Why it is a problem.**
1. **Uncontrolled request volume.** Typing "amoxicillin" issues up to 11 sequential RPCs; out-of-order responses can also render stale results, since nothing sequences them.
2. **No error path.** A failed lookup gives the clinician an empty dropdown indistinguishable from "no matches", which in a prescribing dialog is a clinically misleading state.
3. **Not testable or reusable.** Search behaviour is trapped in two private widget methods, so the same catalog lookup is implemented twice and covered by no test.
4. **Layer skip normalizes further skips.** Widget → data is one step worse than the accepted notifier → data, and it is the pattern most likely to be copied into new dialogs.

**Recommended architectural solution.** Introduce one debounced, cached search provider per catalog behind a family keyed by query string, owned by the presentation layer, and have both dialogs consume it. Keep the row → `AppComboboxItem` mapping in the widget only for the parts that are widget-specific (the `disabled`/`disabledReason` logic depends on `widget.usedInvestigationIds`).

**Suggested implementation steps.**

1. Create `frontend/lib/features/visits/presentation/providers/catalog_search_providers.dart`.
2. Add `final investigationSearchProvider = FutureProvider.autoDispose.family<List<CatalogItem>, String>((ref, query) async { ... })` that: returns `const []` for queries shorter than 2 characters; debounces with `await Future<void>.delayed(const Duration(milliseconds: 300)); if (!ref.mounted) return const [];` before calling `ref.read(visitRepositoryProvider).searchInvestigations(query: query)`; and calls `ref.keepAlive()` on success so repeated queries are cached for the dialog's lifetime.
3. Add `medicationSearchProvider` the same way, calling `searchMedications(query: query)`. Use the existing `CatalogItem` domain type from `frontend/lib/features/visits/domain/catalog_item.dart` as the return type — do not return `AppComboboxItem` from a provider.
4. In `investigation_form_dialog.dart`, replace the body of `_searchInvestigations` with `final items = await ref.read(investigationSearchProvider(query).future);` and keep the existing mapping loop (lines 70–79) unchanged.
5. Do the same in `treatment_plan_form_dialog.dart` for `_searchMedications` (line 83).
6. Wrap each call in `try/catch (RpcFailure)` and surface the message through the existing toast helper used elsewhere in Visits (`appToast(context, AppToastInput(message: visitMessageForRpc(error), variant: AppToastVariant.danger))`, as used in `visit_summary_section.dart:124`), returning `const []` afterwards.
7. Replace the `'Already added'` literal (line 77) and the equivalent in the treatment dialog with localization keys added under `frontend/lib/l10n/`.
8. Verify no widget reads the repository any more: `rg -n "visitRepositoryProvider" frontend/lib/features/visits/presentation/widgets` should return no results.
9. Add `frontend/test/unit/visits/catalog_search_providers_test.dart` asserting: queries under 2 characters issue no RPC; rapid successive queries within the debounce window issue one RPC for the final query; and a repository failure propagates as an error state rather than an empty list.

## M4 — Three overlapping visit representations, one of them a hand-maintained cache of another

**Severity:** Medium

**Location:** `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`, `class VisitDocumentationState`
- `visit` — field (constructor, ~line 34)
- `persistedVisit` — field, declared line 56, set in constructor line 36
- `effectiveVisit` — computed getter, line 120: `VisitDetail get effectiveVisit => encounterDraft.applyTo(persistedVisit);`
- manual re-derivations: line 512 `visit: draft.applyTo(current.persistedVisit)` and line 551 `copyWith(visit: syncedPlainText.effectiveVisit, saveStatus: saveStatus)`
- inconsistent readers: `visit_summary_section.dart:201`, `visit_treatment_section.dart:151`, `visit_findings_section.dart:180`, `encounter_step_provider.dart:16,52,65`, `visit_submit_readiness.dart:25` all use `effectiveVisit`, while `visit_documentation_notifier.dart:585` reads `current.visit.investigations` **and** `current.visit.pendingInvestigations`, and `completeVisit()` uses `current.visit.id` (line 271)

**Issue.** The state carries the same visit three ways: `persistedVisit` (server truth), `encounterDraft` (unsaved overlay), and `effectiveVisit` (line 120, the correct composition of the two) — **plus** a fourth thing, the `visit` field, which is a *manually maintained copy* of `effectiveVisit`. Lines 512 and 551 show it being recomputed by hand:

```512:512:frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart
        visit: draft.applyTo(current.persistedVisit),
```

```551:551:frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart
    final synced = syncedPlainText.copyWith(visit: syncedPlainText.effectiveVisit, saveStatus: saveStatus);
```

Every mutation path must remember to re-derive `visit`, because `effectiveVisit` (the derived getter) already does this for free. Any `copyWith` that changes `encounterDraft` or `persistedVisit` **without** also updating `visit` leaves `visit` silently stale, and readers of `visit` then see a different visit than readers of `effectiveVisit` — in the same frame.

The reader split is real, not hypothetical: all widgets and the submit-readiness rule read `effectiveVisit`, while notifier-internal code reads `current.visit`. Line 585 is the clearest smell — it merges `current.visit.investigations` with `current.visit.pendingInvestigations`, i.e. it treats `visit` as a *partly* merged object and re-merges on top of it, which only makes sense if the author was unsure which representation `visit` holds.

**Why it is a problem.**
1. **Silent divergence between UI and logic.** A missed re-derivation makes a widget show a pending prescription that the notifier's own validation cannot see (or vice versa) — with no error, just inconsistent behaviour.
2. **`copyWith` is a trap.** The state's `copyWith` (line 124 onward) accepts `persistedVisit` and `visit` independently, so it is possible — and easy — to produce an inconsistent state object. There is no invariant check.
3. **Redundant memory and rebuilds.** `visit` duplicates a whole `VisitDetail` (notes, vitals, investigations, treatment plans, attachments) on every state change, and because it is a new object each time, equality-based rebuild suppression is defeated for every listener of the state.
4. **It obscures the model.** A reader cannot tell from a field name whether `visit` means server truth, draft-applied truth, or something in between; `persistedVisit` and `effectiveVisit` are unambiguous, `visit` is not.

**Recommended architectural solution.** Keep exactly two stored fields — `persistedVisit` and `encounterDraft` — and expose only the derived `effectiveVisit`. Delete the `visit` field entirely so divergence is structurally impossible.

**Suggested implementation steps.**

1. Open `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`.
2. Remove the `visit` field from `VisitDocumentationState`: delete its declaration, its constructor parameter, and its `visit` parameter in `copyWith` (around lines 124–142).
3. Keep `effectiveVisit` (line 120) as the single derived accessor. If a short name is wanted, add `VisitDetail get visit => effectiveVisit;` as a **getter only** — never a field — so all existing readers keep compiling with zero behavioural risk. Prefer this as the first step: it makes the whole change mechanical.
4. Delete the manual re-derivations at line 512 (`visit: draft.applyTo(current.persistedVisit),`) and line 551 (`copyWith(visit: syncedPlainText.effectiveVisit, ...)` becomes `copyWith(saveStatus: saveStatus)`).
5. Check `VisitDocumentationState.fromVisit` (line 166, `persistedVisit: visit`) and ensure it sets only `persistedVisit` and an empty `encounterDraft`.
6. Fix line 585: `for (final item in [...current.visit.investigations, ...current.visit.pendingInvestigations])` — with `visit` now meaning `effectiveVisit`, the draft investigations are **already included**, so this double-counts. Change it to iterate `current.effectiveVisit.investigations` only, and re-check the surrounding logic (it appears to build a used-ids set for the investigation dialog) for the same double-count.
7. Run `rg -n "\.visit\b" frontend/lib/features/visits` and review each site to confirm the intended semantics is "draft applied". Where a site genuinely needs server truth (e.g. the concurrency comparison at line 1212, which correctly uses `current.persistedVisit.investigations`), switch it explicitly to `persistedVisit`.
8. Once step 7 is complete, delete the compatibility getter from step 3 and rename all remaining `.visit` reads to `.effectiveVisit` or `.persistedVisit` so every read site states its intent.
9. Run `flutter analyze` and `flutter test test/unit/visits`.
10. Add `frontend/test/unit/visits/visit_documentation_state_derivation_test.dart` asserting that after adding a pending vital sign, `effectiveVisit.vitalSigns` includes it while `persistedVisit.vitalSigns` does not, and that no third representation exists.

## M5 — Substantial unreachable code, including a fully implemented persisted "workspace mode" feature with no UI

**Severity:** Medium

**Location:**

| Dead symbol | File | Declared at |
| -- | -- | -- |
| `WorkspaceMode` enum, `WorkspaceModeNotifier`, `workspaceModeProvider`, `setMode`, `toggleMode`, `fromWire` | `frontend/lib/features/visits/presentation/providers/workspace_mode_provider.dart` | 10, 33, 35, 65, 76, 16 |
| `expertModeScrollTargetProvider` (+ its notifier) | `frontend/lib/features/visits/presentation/providers/expert_mode_scroll_provider.dart` | 6 |
| `visitDetailProvider` (marked `@deprecated`) | `frontend/lib/features/visits/presentation/providers/visit_detail_provider.dart` | 47 (comment at 46) |
| `encounterPhaseBadgesProvider` | `frontend/lib/features/visits/presentation/providers/encounter_step_provider.dart` | 150 |
| `reloadVisit()`, `reloadAfterStale()` | `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` | 1409, 1414 |
| `VisitEncounterPersistence` (339 lines) | `frontend/lib/features/visits/application/visit_encounter_persistence.dart` | 9 (see H1) |

**Issue.** Each symbol above has **no reader** anywhere in `frontend/lib` or `frontend/test` other than its own declaration (verified by ripgrep over both trees).

The largest and most misleading is `workspace_mode_provider.dart`. It implements a complete, persisted guided/expert workspace-mode feature: an enum with wire serialization (`fromWire`, line 16), a `Notifier` that **reads and writes `SharedPreferences`** (`build()` at line 37, restore at line 59, persist in `setMode` at line 65), and a `toggleMode()` convenience (line 76). Nothing in the app ever watches `workspaceModeProvider` or calls `setMode`/`toggleMode`, so no UI can enter expert mode. Its companion `expertModeScrollTargetProvider` — the scroll coordination that expert mode would need — is likewise unreferenced. The state class `VisitDocumentationState` does, separately, carry a live `workspaceEditMode` (a different concept: viewing vs. editing), which makes the dead `WorkspaceMode` actively confusing.

`visitDetailProvider` (line 47) is self-documented as superseded — *"@deprecated Use `visitDetailViewProvider` for permission-aware detail screens"* — and indeed all real readers (`visit_document_page.dart:39,51`, `encounter_step_provider.dart:113,125`, and the unit tests) use `visitDetailViewProvider`. The deprecated wrapper is the *non*-permission-aware variant, so it is a security-relevant footgun as well as dead weight.

`reloadVisit()` and `reloadAfterStale()` are the unreachable recovery methods analysed in H4.

**Why it is a problem.**
1. **It contradicts the architecture doc, so readers cannot trust either.** `docs/architecture/14-visits-encounter-workspace.md` describes guided/expert workspace modes as feature behaviour; the code contains the mechanism but no way to reach it. A contributor (or AI agent) reading the doc will assume the mode works and build on top of it.
2. **A permission-unaware provider is left available.** `visitDetailProvider` bypasses the `VisitDetailViewState` permission wrapper. If any future screen picks it because the name is shorter, it silently loses permission awareness.
3. **Dead recovery paths mask real bugs.** The existence of `reloadAfterStale()` makes the stale-conflict flow *look* handled (H4), which is exactly why that defect survived review.
4. **False signal of complexity and false test confidence.** Roughly 450 dead lines across these files inflate the feature's apparent surface, and any test written against them proves nothing about the app.

**Recommended architectural solution.** Delete every unreachable symbol, and where the behaviour is genuinely wanted (workspace mode), either wire it up in the same change or remove it and record it as an unimplemented item in the roadmap document rather than leaving latent code.

**Suggested implementation steps.**

1. Confirm each symbol is still unreachable before deleting. For each name in the table run e.g. `rg -n "workspaceModeProvider|WorkspaceMode\b" frontend/lib frontend/test` and check that all hits are inside the declaring file (be careful to distinguish `WorkspaceMode` from the **live** `workspaceEditMode` / `WorkspaceEditMode` used by `VisitDocumentationState` — do not delete those).
2. Decide on workspace mode with the product owner. If it is not being built now: delete `frontend/lib/features/visits/presentation/providers/workspace_mode_provider.dart` and `frontend/lib/features/visits/presentation/providers/expert_mode_scroll_provider.dart`, then update `docs/architecture/14-visits-encounter-workspace.md` to remove the guided/expert mode description and add a line to `docs/architecture/12-roadmap-phases.md` recording it as not implemented.
3. If it **is** wanted: add a mode toggle to the workspace header widget, have the three phase canvases and `visit_document_page.dart` watch `workspaceModeProvider`, wire `expertModeScrollTargetProvider` to the scroll controller, and add widget tests — but do this as its own change, not as part of cleanup.
4. Delete `visitDetailProvider` (lines 46–49 of `visit_detail_provider.dart`). Run `flutter analyze`; if any file breaks, migrate it to `visitDetailViewProvider(visitId)` and read `.visit` from the returned `VisitDetailViewState`.
5. Delete `encounterPhaseBadgesProvider` (line 150 of `encounter_step_provider.dart`) along with the `PhaseBadges` type and `_badgeForPhase` helper if they have no other reader (check line 16–18, which uses `_badgeForPhase` inside the same provider body — keep whatever the live badge computation needs).
6. Delete `reloadVisit()` (1409–1412) and `reloadAfterStale()` (1414–1417) as part of implementing H4 step 4, not before — H4's replacement method should land in the same change.
7. Delete `visit_encounter_persistence.dart` per H1.
8. Run `flutter analyze` and `flutter test` after each deletion group.
9. Add a repeatable guard against re-accumulation: add `frontend/tool/find_dead_providers.sh` that, for each `Provider`/`NotifierProvider` declaration under `frontend/lib/features/*/presentation/providers/`, greps the rest of `frontend/lib` for its identifier and reports zero-reference results. Run it in CI as a warning rather than a hard failure to avoid false positives on newly added providers.

---

## Suggested fix order

The findings interact, so applying them in this order avoids rework:

1. **C4** (move `rich_text_draft_utils.dart` to `core/`) — smallest change, unblocks H3 step 8.
2. **H1** (delete `visit_encounter_persistence.dart`) — removes 339 lines of decoy code before anyone refactors against it.
3. **C1** (unsaved-changes guard + drop `autoDispose`) — also removes the root cause of H5.
4. **H5** (explicit flush at the billing handoff) — depends on C1 step 3.
5. **C2** (resumable flush) — must land before H2 splits the flush across new files.
6. **H4** (stale-conflict resolution) and **H6** (confirmation-dialog invoice) — independent, both self-contained.
7. **C3** (`VisitFinalizationService`, break the billing cycle) — depends on C2 and H5 being correct.
8. **H3**, **M1**, **M3**, **M4**, **M5** — boundary and cleanup work, independent of each other.
9. **H2** (split the god object) and **M2** (extract `ClinicalNoteField`) — do last; both are large mechanical refactors that are much safer once the correctness fixes above are in place.

Each finding's step list is self-contained and can be executed without reading the others, except where a dependency is stated explicitly above.

