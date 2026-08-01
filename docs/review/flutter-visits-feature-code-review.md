# Flutter Visits Feature — Code Review

**Date:** 2026-07-05 (Cycle 1 + Cycle 2)  
**Scope:** All 30 files under `frontend/lib/features/visits/`, 23 unit tests under `frontend/test/unit/visits/`, routing/auth integration, cross-feature coupling with `patients` and dev shell  
**Sources:** Cycle 1 — four parallel passes (domain, data + application, presentation, cross-cutting). Cycle 2 — four parallel re-reads with direct code verification (see [Cycle 2](#cycle-2--second-pass-review) section).  
**Maturity:** Logic-layer only — visit routes exist but all screens are `uiPendingPlaceholder` (project-wide UI migration state)

---

## Executive Summary

The visits feature implements encounter documentation (SOAP notes, vitals, investigations, treatment plans, attachments) and visit lifecycle (create, save, complete) via a concrete `VisitRepository`, Riverpod notifiers, and a large `VisitDocumentationNotifier` (~1,400 lines). Submit-readiness rules and RPC error mapping are well tested for the clinical-note happy path.

However, **layer boundaries are inverted in multiple places**, **structured-data flush is the highest functional risk**, and **attachment lifecycle has genuine correctness/security gaps**:

1. **Clean Architecture inversions (critical)** — `domain/visit_submit_readiness.dart` imports presentation providers; `domain/visit_encounter_draft.dart` imports data-layer attachment types; `application/visit_encounter_persistence.dart` depends on `WidgetRef` and the presentation notifier. Domain also depends on `flutter/material.dart` and `flutter_quill`.
2. **Structured flush integrity (critical)** — `_flushEncounterDraft` is client-orchestrated, non-transactional, untested, and can duplicate server rows on partial-failure retry; overlapping `save()`/`saveAll()` calls have no mutex; in-flight staging edits can be silently dropped on successful flush.
3. **Attachment lifecycle bugs (critical/high)** — `deleteAttachment` removes the DB row but not the storage object (orphaned PHI); upload compensation can delete storage after a committed DB row; downloaded PHI sits in shared temp files with only opportunistic cleanup.
4. **Domain ↔ backend alignment gaps (high)** — whitespace-only rich deltas count as content client-side but not server-side; section length validation ignores rich-text-only content; comma-decimal BMI parsing is wrong (`'70,2'` → 702 kg); `VisitInvestigation` equality omits result fields.
5. **Feature boundary drift (high)** — patient allergies/medications/conditions live entirely under `visits`; `patients` reaches into `visits/data` directly; `VisitRepository` is an ~800-line god-class.
6. **Security-relevant test holes (critical)** — `AuthRouteGuard.visitRouteRedirect` / `canAccessVisit*` have no dedicated tests (unlike billing, patients, appointments).

Remediation should prioritize: fix layer inversions, harden flush recovery and save serialization, fix attachment delete/compensation, align rich-text content rules with backend, add visit route-guard tests, then split repository and extract flush orchestration to `application/`.

---

## Feature Overview

### Purpose

Clinic visit encounter workspace: load visit detail, edit SOAP documentation (plain + Quill rich text), stage structured data (vitals, investigations, treatment plans, attachments, patient safety), flush staged changes to the server, and complete visits when documentation requirements are met.

### Layer inventory

| Layer | Files | Role |
|-------|-------|------|
| `domain/` | 19 | Entities, parsing (`fromRow`), submit readiness, BMI, draft merge, catalog normalization |
| `data/` | 3 | `VisitRepository` (~800 lines), `VisitAttachmentService`, `VisitAttachmentOpener` |
| `application/` | 2 | `visit_rpc_messages.dart` (pure), `visit_encounter_persistence.dart` (defer-vs-direct router — mislayered) |
| `presentation/` | 6 | Riverpod providers/notifiers; `VisitDocumentationNotifier` owns bulk of orchestration |

**Missing:** repository interfaces, use cases, `presentation/pages/`, `presentation/widgets/`.

### Data flow (intended vs actual)

```
Intended:  presentation → application → domain ← data

Actual:    presentation ←→ application (VisitEncounterPersistence uses WidgetRef + notifier)
           domain → presentation (visit_submit_readiness imports notifier state)
           domain → data (PendingVisitAttachment uses VisitAttachmentPickInput)
           presentation → data (direct repository calls in _flushEncounterDraft)
```

### Cross-feature integration

| Consumer | Dependency |
|----------|------------|
| `patients` | `visit_repository.dart`, `visit_list_item.dart`, `visit_attachment_item.dart` |
| `dev_clinic_seed_*` | Visit repository for seeding |
| `core/auth` | `visitRouteRedirect`, permission keys |
| `app/providers` | `visitRepositoryProvider` **not** exported in `repository_providers.dart` barrel |

---

## 1. Critical Issues

### C-01 — Domain imports presentation layer

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `domain/visit_submit_readiness.dart`, `presentation/providers/encounter_step_provider.dart`, `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | `visit_submit_readiness.dart` imports presentation providers and operates on `VisitDocumentationState`; `evaluateVisitSubmitReadiness` calls `deriveEncounterPhaseBadges(state)` from presentation. |
| **Why** | Dependency rule inverted: innermost domain depends on Riverpod presentation types. |
| **Impact** | Domain not independently testable; presentation refactors break submit rules; circular coupling. |
| **Solution** | Introduce `VisitDocumentationSnapshot` in domain; move badge derivation and readiness evaluation to domain/application with zero presentation imports. |

---

### C-02 — Application layer depends on presentation (`WidgetRef` + notifier)

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `application/visit_encounter_persistence.dart` |
| **Evidence** | Class holds `WidgetRef ref`, reads `visitDocumentationProvider(visitId).notifier`, imports `visit_documentation_notifier.dart`. Sibling features keep `application/` UI-free (`visit_rpc_messages.dart`, `billing_rpc_messages.dart`). |
| **Why** | Misfiled presentation helper; cannot unit-test without widget tree. |
| **Impact** | Zero tests for defer-vs-direct routing (T1 in data review); layer boundary is fiction. |
| **Solution** | Inject `Ref`/repository + `VisitDraftPort` interface, or relocate to `presentation/`. |

---

### C-03 — Partial flush failure retains encounter draft → duplicate creates on retry

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` (`_flushEncounterDraft`, `_recoverEncounterDraftAfterFlushFailure`) |
| **Evidence** | Recovery comment says draft is cleared to avoid duplicate creates; implementation re-applies `afterNote.encounterDraft`. Sequential RPC loops across vitals, investigations, plans, attachments, patient safety with no transaction. Error message: *"Some changes may have been saved — review the visit before retrying."* |
| **Why** | Partial server writes + full client draft retained. |
| **Impact** | Retry creates duplicate vitals, allergies, investigations, attachments. |
| **Solution** | On partial failure: clear draft or diff against refreshed server rows. Add test injecting mid-sequence RPC failure. Longer term: server-side transactional "apply encounter draft" RPC. |

---

### C-04 — No in-flight mutex on overlapping `save()` / `saveAll()` / `_flushEncounterDraft()`

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | `saveAll` captures `current` snapshot, sets `saving`, awaits flush — no `_saveInFlight` flag or serialization. Same pattern in `save()`. |
| **Why** | Double-tap save, auto-save + manual save, or `completeVisit` + `saveAll` can interleave. |
| **Impact** | Duplicate structured creates; stale `expectedUpdatedAt` on clinical-note save; last-writer-wins corruption. |
| **Solution** | Serialize mutations with in-flight `Future`/`Completer`; re-read `state.value` before each RPC batch. |

---

### C-05 — Staging edits during flush discarded on success

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | Success path rebuilds from `VisitDocumentationState.fromVisit(refreshed)` (empty draft default) without merging post-await `state.value.encounterDraft`. Flush uses pre-await snapshot. |
| **Why** | Concurrent `stageCreate*` during save spinner updates state; success wipe ignores it. |
| **Impact** | Silent data loss for edits made while save runs. |
| **Solution** | Merge latest `encounterDraft` after flush, or block staging while `saveStatus == saving`. |

---

### C-06 — `deleteAttachment` deletes DB row but not storage object

| Field | Detail |
|-------|--------|
| **Severity** | Critical (PHI retention) |
| **Files** | `data/visit_attachment_service.dart`, `data/visit_repository.dart` |
| **Evidence** | `deleteAttachment` delegates to `deleteVisitAttachment` RPC only. Upload path writes storage + registers metadata; delete has no symmetric `storage.remove`. |
| **Why** | Two-phase upload, single-phase delete. |
| **Impact** | Orphaned medical files in `visit-attachments` bucket; erasure compliance risk. |
| **Solution** | Confirm server RPC deletes storage; if not, fetch `file_path` and remove after RPC success. Add test. |

---

### C-07 — Visit route-guard logic entirely untested

| Field | Detail |
|-------|--------|
| **Severity** | Critical (security coverage) |
| **Files** | `core/auth/auth_route_guard.dart`, `test/unit/visits/app_routes_visits_test.dart` |
| **Evidence** | `visitRouteRedirect` branches on auth, setup, document vs detail permissions. No test references `visitRouteRedirect`, `canAccessVisitDocumentation`, `canAccessVisitDetail`, or `isVisitRoute`. Billing/patients/appointments each have dedicated guard test files. |
| **Why** | Controls access to `/visits/:id/document` vs `/detail`. |
| **Impact** | Permission regressions ship silently. |
| **Solution** | Add `auth_route_guard_visits_test.dart` mirroring sibling suites; cover `?edit=1` query on document URL. |

---

### C-08 — Domain imports data layer for attachment pick input

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `domain/visit_encounter_draft.dart`, `data/visit_attachment_service.dart` |
| **Evidence** | `PendingVisitAttachment.pick` is typed as `VisitAttachmentPickInput` from data layer. |
| **Why** | Domain draft model coupled to Supabase upload DTO. |
| **Impact** | Domain not portable; data changes break domain. |
| **Solution** | Define `VisitAttachmentPick` in domain; map in data layer. |

---

### C-09 — Flutter / Quill dependencies in domain

| Field | Detail |
|-------|--------|
| **Severity** | Critical (architecture) |
| **Files** | `domain/encounter_phase.dart` (`material.dart`, `IconData`), `domain/rich_text_draft_utils.dart` (`flutter_quill`) |
| **Evidence** | `EncounterPhase.icon` uses Material icons; most presentation metadata getters (`label`, `icon`, `next`, `previous`) are unused in codebase. `Document.fromJson` in domain with no malformed-delta guard. |
| **Why** | Domain should be headless and editor-agnostic. |
| **Impact** | Cannot test/reuse domain without Flutter/Quill; swap editor forces domain rewrite. |
| **Solution** | Move UI metadata to presentation mapper; keep domain checks on normalized plain text. |

---

## 2. High Priority Issues

### H-01 — `uploadAndRegister` compensation can delete storage after DB row committed

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/visit_attachment_service.dart` |
| **Evidence** | Catch block removes storage on any `registerVisitAttachment` throw, including `StateError` after successful-but-malformed RPC response. |
| **Impact** | DB row pointing at deleted storage object. |
| **Solution** | Compensate only on pre-commit failures (`RpcFailure`); add test for post-success parse failure. |

---

### H-02 — Downloaded PHI in shared temp dir with opportunistic cleanup only

| Field | Detail |
|-------|--------|
| **Severity** | High (PHI) |
| **Files** | `data/visit_attachment_opener.dart` |
| **Evidence** | `writeAsBytes` to temp path; `_cleanupStaleAttachmentFiles` runs only on next open, deletes files >24h old. |
| **Impact** | PHI residue on shared clinic workstations. |
| **Solution** | Shorter retention, cleanup on app start/dispose, delete-after-open where feasible. |

---

### H-03 — No timeouts, retry, or cancellation on RPC/HTTP/storage

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `core/rpc/app_rpc_invoker.dart`, `data/visit_attachment_service.dart`, all repository methods |
| **Evidence** | `invokeRpc` and `http.get` have no `.timeout()`; no cancellation tokens; grep finds no retry in visits feature. |
| **Impact** | Hung saves/downloads; no abort on navigation away. |
| **Solution** | Add timeouts to RPC and downloads; bounded retry for idempotent reads; thread cancellation for uploads. |

---

### H-04 — Inconsistent FK "clear" semantics across update methods

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/visit_repository.dart` |
| **Evidence** | `updateTreatmentPlan` sends explicit `null` to clear; `updateVisitInvestigation` uses `p_clear_investigation_id` flag; `updateVisitVitalSign` uses null-aware entry that cannot clear and may send `''` as bogus FK. |
| **Impact** | Cannot unlink predefined vital sign; inconsistent behavior per entity. |
| **Solution** | Standardize one clear convention; add tests per entity. |

---

### H-05 — Whitespace-only rich deltas counted as documentation (client ≠ server)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/rich_text_draft_utils.dart`, `domain/visit_submit_readiness.dart` |
| **Evidence** | `richDeltaIsEffectivelyEmpty` only handles single-op `'\n'` delta; `[{'insert': ' \n'}]` is non-empty in FE. Backend `visit_has_documentation` uses `trim()` on plain text. |
| **Impact** | Submit allowed in UI, `complete_visit` fails with `DOCUMENTATION_REQUIRED_FOR_COMPLETE`. |
| **Solution** | Treat rich content as empty when `plainTextFromRichDelta(delta).trim().isEmpty`. |

---

### H-06 — Section length validation ignores rich-text-only content

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/visit_clinical_note.dart`, `presentation/providers/encounter_step_provider.dart` |
| **Evidence** | `clinicalSectionLengthError` and `_sectionTooLong` check plain `String.length` only; tests use plain strings exclusively. |
| **Impact** | >10k chars in Quill with empty plain field bypasses client validation. |
| **Solution** | Measure `max(plain.length, plainTextFromRichDelta(delta).length)` per section. |

---

### H-07 — Comma-decimal BMI parsing produces wrong values

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/bmi.dart`, `test/unit/visits/bmi_test.dart` |
| **Evidence** | `_parseVitalNumeric` strips commas entirely (`'70,2'` → `702`). Test only asserts `> 0`, masking the bug. |
| **Impact** | Clinically wrong BMI for locale-formatted input. |
| **Solution** | Treat comma as decimal separator or reject; fix test to assert expected BMI. |

---

### H-08 — `VisitInvestigation` equality omits result metadata

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/visit_investigation.dart`, `domain/visit_encounter_draft.dart` |
| **Evidence** | `==` / `hashCode` cover `id`, `name`, `note`, `investigationId` only — not `result`, `resultRecordedAt`, `orderedVisitId`. |
| **Impact** | Stale UI, missed rebuilds, incorrect unchanged detection. |
| **Solution** | Include all fields or drop custom equality. |

---

### H-09 — Patient-level clinical data owned by `visits`, not `patients`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/patient_safety.dart`, `data/visit_repository.dart`, `features/patients/*` |
| **Evidence** | Allergies/medications/chronic conditions CRUD in `VisitRepository`; grep finds no allergy/medication/condition code under `patients`. |
| **Impact** | Patient-centric surfaces must depend on `visits`; repository responsibilities sprawl. |
| **Solution** | Extract patient safety into `patients` feature or shared module. |

---

### H-10 — Non-atomic `_flushEncounterDraft` untested

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/visit_documentation_notifier.dart`, `test/unit/visits/encounter_stale_documentation_test.dart` |
| **Evidence** | Notifier tests seed clinical-note-only drafts; `_flushEncounterDraft` never exercised. No tests for `stageCreate`, `stageArchive`, `saveAll` with structured data. |
| **Impact** | Recovery paths (`investigationResultIdRemap`, partial failure) regress silently. |
| **Solution** | Add `VisitRpcTestClient` tests with mixed staged items + mid-sequence failure injection. |

---

### H-11 — Clinical-note flush callbacks never disposed

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | `_clinicalNoteFlushCallbacks` set with `registerClinicalNoteFlush`; `autoDispose` provider has no `ref.onDispose` to clear set; no production `unregister` call sites. |
| **Impact** | Leaked widget/controller references; flush invokes disposed editors. |
| **Solution** | `ref.onDispose(() => _clinicalNoteFlushCallbacks.clear())`; require widget unregister in `dispose()`. |

---

### H-12 — `completeVisit({expectedUpdatedAt})` parameter is dead code

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | Parameter declared but never read; only `current.expectedUpdatedAt` sent to RPC. |
| **Impact** | Callers believe they control concurrency; misleading API. |
| **Solution** | Use `expectedUpdatedAt ?? current.expectedUpdatedAt` or remove parameter. |

---

### H-13 — Cross-feature DI bypasses `repository_providers.dart` barrel

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `app/providers/repository_providers.dart`, `patients/presentation/providers/patient_detail_history_provider.dart` |
| **Evidence** | Barrel comment says cross-feature repos should import from there; `visitRepositoryProvider` not exported. `patients` imports `visits/data` directly; `patients/domain/patient_visit_document.dart` imports `visits/domain/visit_attachment_item.dart`. |
| **Solution** | Export visit repo from barrel or move shared types to neutral module. |

---

### H-14 — Bulk persistence orchestration lives in presentation, not application

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` (~220 lines `_flushEncounterDraft`), `application/visit_encounter_persistence.dart` (single-op only) |
| **Why** | Presentation owns transaction-like fan-out, ID remapping, recovery. |
| **Solution** | Extract `FlushEncounterDraftUseCase` in `application/`; notifier maps result to `DocumentationSaveStatus`. |

---

### H-15 — `hasUnsavedDraft` hides changes during `saving` → navigation guard bypass

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | `hasUnsavedDraft` returns `false` when `saveStatus == saving`; `hasUnsavedChanges` used as leave guard. |
| **Impact** | User navigates away mid-save without UI awareness. |
| **Solution** | Treat `saving` as unsaved for navigation, or expose `isPersistInFlight`. |

---

### H-16 — `reloadVisit` / `reloadAfterStale` wipe all local draft state

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | Both call `ref.invalidateSelf()` → full `_load()` → `fromVisit` with no draft merge. `refreshVisitPreservingDraft` exists but unused here. |
| **Impact** | Stale recovery destroys in-progress encounter draft and rich-text deltas. |
| **Solution** | Implement `reloadAfterStale` via `refreshVisitPreservingDraft` + token update. |

---

### H-17 — Inconsistent doctor-name parsing: detail vs list

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/visit_detail.dart`, `domain/visit_list_item.dart` |
| **Evidence** | Detail defaults empty doctor to `'Unknown doctor'`; list rejects row when `doctorName` empty. |
| **Impact** | Visit visible in detail but missing from patient history list for same payload. |
| **Solution** | Shared parsing policy in `visit_row_parsing.dart`. |

---

## 3. Medium Priority Issues

| ID | Issue | Files | Summary |
|----|-------|-------|---------|
| M-01 | Two divergent `_sanitizeFilename` implementations | `visit_attachment_service.dart`, `visit_attachment_opener.dart` | Service strips spaces; opener keeps them. |
| M-02 | `buildStoragePath` does not sanitize org/branch/visit ID segments | `visit_attachment_service.dart` | Defense-in-depth gap on storage key composition. |
| M-03 | File type from extension only (no magic-byte sniffing) | `visit_attachment_service.dart` | Renamed non-PDF uploaded as `application/pdf`. |
| M-04 | DTO validation inconsistent (empty string vs null) | `visit_repository.dart` | `CreateVisitResult` rejects empty IDs; `CompleteVisitResult` may accept `''`. |
| M-05 | Optional RPC text params forwarded untrimmed | `visit_repository.dart` | Whitespace-only optional fields persisted. |
| M-06 | `visit_rpc_messages.dart` hardcodes English + substring-matches server errors | `application/visit_rpc_messages.dart` | Brittle i18n; prefer error codes. |
| M-07 | `investigationResults` map alone can satisfy persistable-documentation check | `domain/visit_submit_readiness.dart` | Looser than backend `visit_has_documentation`. |
| M-08 | `plainTextFromRichDelta` can throw on malformed JSON | `domain/rich_text_draft_utils.dart` | No try/catch around `Document.fromJson`. |
| M-09 | `VisitClinicalNote.fromRow` never returns null despite nullable return type | `domain/visit_clinical_note.dart` | Always constructs wrapper even when all fields null. |
| M-10 | `parseVisitDateTime` does not normalize timezone | `domain/visit_row_parsing.dart` | Inconsistent with `parseVisitDate` UTC handling. |
| M-11 | `PendingVisitAttachment.toDisplayItem()` uses `DateTime.now()` | `domain/visit_encounter_draft.dart` | Non-deterministic `createdAt` on each merge. |
| M-12 | `newVisitDraftId()` uses module-level mutable counter | `domain/visit_encounter_draft.dart` | Non-deterministic; harder to test. |
| M-13 | Permission model conflates patient-safety edits with SOAP editing | `visit_documentation_notifier.dart`, `permission_service.dart` | `visits.edit_soap` gates allergy/medication/condition mutations. |
| M-14 | `visitDetailViewProvider` / `patientSafetyProvider` untested | presentation providers | Branch-access and upload flags uncaught by tests. |
| M-15 | `workspaceModeProvider` load race can overwrite user selection | `workspace_mode_provider.dart` | Re-scheduled microtask loads on auth changes; no generation token. |
| M-16 | `patientSafetyProvider` not invalidated after safety flush | `visit_documentation_notifier.dart` | Other widgets show stale allergies. |
| M-17 | `encounterActivePhaseProvider` not reset on documentation reload | `encounter_step_provider.dart` | Stepper out of sync after stale recovery. |
| M-18 | Subjective badge vs submit gate mismatch for patient-safety-only drafts | `encounter_step_provider.dart`, `visit_submit_readiness.dart` | Badge shows content; submit blocked (tested, confusing UX). |
| M-19 | `stage*` methods silently no-op without edit permission | `visit_documentation_notifier.dart` | No error surfaced to UI. |
| M-20 | Async operations lack post-await `ref.mounted` checks | all async notifiers | Writes on disposed notifier after navigation. |
| M-21 | `visit_attachment_opener.dart` in data layer opens OS default viewer | `visit_attachment_opener.dart` | Platform action mixed with I/O (CA3). |
| M-22 | `completeVisit` RpcFailure does not update presentation state | `visit_documentation_notifier.dart` | Unlike `save()` stale mapping. |

---

## 4. Low Priority Issues

| ID | Issue | Files |
|----|-------|-------|
| L-01 | "25 MB" label vs 25 MiB limit (`26214400` bytes) | `visit_attachment_service.dart`, `visit_rpc_messages.dart` |
| L-02 | `_newStorageUniqueId` produces UUID-shaped but invalid UUID | `visit_attachment_service.dart` |
| L-03 | Temp filename collision window (`microsecondsSinceEpoch`) | `visit_attachment_opener.dart` |
| L-04 | `PatientVisitsPage.totalCount` falls back to `items.length` silently | `visit_repository.dart` |
| L-05 | `EncounterPhase.context` excluded from stepper but referenced in badge logic | `encounter_phase.dart` |
| L-06 | `orderIndex` duplicates unused `stepperIndex` | `encounter_phase.dart` |
| L-07 | `VisitStatus.canTransitionTo` redundant completed branch | `visit_status.dart` |
| L-08 | `DevCatalogSeedResult` has no `fromRpcData` parser | `catalog_item.dart` |
| L-09 | `ClinicalNoteSection.label` / `abbr` unused | `clinical_note_section.dart` |
| L-10 | Deprecated `visitDetailProvider`, `needsSaveBeforeLeaving` still in public surface | `visit_detail_provider.dart`, notifier |
| L-11 | `visitDocument(?edit=1)` query contract untested/unwired in placeholder route | `app_routes.dart`, `router.dart` |
| L-12 | `reloadVisit` and `reloadAfterStale` are duplicate implementations | `visit_documentation_notifier.dart` |
| L-13 | `workspaceModeProvider` unprefixed prefs key when `staffId` absent | `workspace_mode_provider.dart` |

---

## 5. Clean Architecture Violations

| Violation | Direction | Files |
|-----------|-----------|-------|
| Domain → Presentation | Inward rule broken | `visit_submit_readiness.dart` |
| Domain → Data | Inward rule broken | `visit_encounter_draft.dart` |
| Application → Presentation | Inward rule broken | `visit_encounter_persistence.dart` |
| Domain → Flutter UI | Framework in domain | `encounter_phase.dart` |
| Domain → Editor package | Third-party in domain | `rich_text_draft_utils.dart` |
| Presentation owns orchestration | Application layer bypassed | `_flushEncounterDraft` in notifier |
| Data performs platform action | Layer blur | `visit_attachment_opener.dart` (`OpenFilex.open`) |
| JSON `fromRow` in domain entities | DTO mapping in domain (common Flutter pattern) | Most entity files |
| No repository interfaces / use cases | Convention drift vs patients | Entire feature |
| Cross-feature domain imports | Feature boundary blur | `patients/domain` → `visits/domain` |

**Target boundary:**

```
domain/     entities + rules (readiness, validation, badges)
application/ use cases (flush, defer-vs-direct routing)
data/       repositories, DTO mappers, Supabase/storage
presentation/ Riverpod state, UI mappers (icons, labels)
```

---

## 6. SOLID Violations

| Principle | Violation | Evidence |
|-----------|-----------|----------|
| **SRP** | `VisitRepository` ~800 lines: visits, catalogs, vitals, investigations, treatment, attachments, patient safety, dev seed | `data/visit_repository.dart` |
| **SRP** | `VisitDocumentationNotifier` ~1,400 lines: notes, staging, flush, complete, permissions, rich-text sync | `visit_documentation_notifier.dart` |
| **SRP** | `visit_encounter_draft.dart`: ID gen, merge, safety overlay, attachment staging, display projection | `domain/visit_encounter_draft.dart` |
| **OCP** | Adding documentation source requires editing multiple OR chains in readiness | `visit_submit_readiness.dart` |
| **DIP** | Concrete `SupabaseClient`, `WidgetRef`, presentation notifier — no ports | repository, persistence, notifier |
| **ISP** | Consumers needing attachments depend on entire `VisitRepository` | all data consumers |
| **Liskov** | `VisitClinicalNote? fromRow` always returns non-null empty wrapper | `visit_clinical_note.dart` |

---

## 7. Code Duplication & Redundancy

| Duplication | Files | Recommendation |
|-------------|-------|----------------|
| `_sectionHasContent` / `_clinicalNoteSectionHasContent` | `visit_submit_readiness.dart`, `encounter_step_provider.dart` | Single domain helper |
| `if (deferPersistence) { stage; return; } await repo.*` × ~20 | `visit_encounter_persistence.dart` | Generic `_route(stage, persist)` |
| `throw StateError('unexpected shape')` × ~15 | `visit_repository.dart` | `_requireShape<T>` helper |
| Two `_sanitizeFilename` implementations | attachment service + opener | Shared tested utility |
| List-of-map `fromRow` parsing pattern | `visit_detail.dart`, `patient_safety.dart`, repository | `parseVisitEntityList<T>` |
| Draft merge archive/update/pending pattern × 4 | `visit_encounter_draft.dart`, `PatientSafetyDraft` | Shared merge helper |
| `PatientVisitsPage._parseInt` vs `optionalVisitInt` | repository vs `visit_row_parsing.dart` | Reuse shared helper |
| Dead `EncounterPhase` API (`label`, `icon`, `next`, `previous`) | `encounter_phase.dart` | Remove or move to presentation |
| `registerVisitAttachment` / `getVisitAttachmentDownload` / `deleteAttachment` thin pass-throughs | `visit_attachment_service.dart` | Acceptable façade; note redundancy |
| `documentationPhases` == `stepperPhases` alias | `encounter_phase.dart` | Remove if no divergence planned |

---

## 8. Performance Issues

| ID | Issue | Severity | Files |
|----|-------|----------|-------|
| P-01 | `_flushEncounterDraft` strictly sequential RPC chain | Medium | `visit_documentation_notifier.dart` |
| P-02 | No caching — every navigation re-fetches visit, catalogs, safety | Medium | `visit_repository.dart`, providers |
| P-03 | Whole-file in-memory upload/download up to 25 MiB | Low | `visit_attachment_service.dart` |
| P-04 | `plainTextFromRichDelta` rebuilds Quill `Document` per section during readiness | Low–Medium | `rich_text_draft_utils.dart` |
| P-05 | `_cleanupStaleAttachmentFiles` sequential stat/delete before each open | Low | `visit_attachment_opener.dart` |
| P-06 | `listPredefinedVitalSigns()` on every `invalidateSelf` reload | Low | `visit_documentation_notifier.dart` |
| P-07 | Offset pagination degrades on deep patient visit lists | Low | `visit_repository.dart` |
| P-08 | `Object.hashAll` on full `VisitDetail` if used in hot paths | Low | `visit_detail.dart` |

---

## 9. Test Coverage Gaps

### Well covered

| Area | Tests |
|------|-------|
| Submit readiness (plain + rich) | `visit_submit_readiness_test.dart`, `encounter_rich_text_readiness_test.dart`, `encounter_submit_safety_mismatch_test.dart` |
| Stale SOAP concurrency | `encounter_stale_documentation_test.dart` |
| Section length (plain only) | `encounter_section_length_test.dart` |
| Phase badges | `encounter_step_provider_test.dart` |
| Repository CRUD (partial) | `visit_repository_*_test.dart` (create, documentation, treatment, complete history) |
| RPC messages | `visit_rpc_messages_test.dart` |
| Entity parsing smoke | `visit_detail_test.dart`, `visit_list_item_test.dart`, `bmi_test.dart`, etc. |
| Attachment service (partial) | `visit_attachment_service_test.dart` |

### Missing or inadequate

| Gap | Risk |
|-----|------|
| `AuthRouteGuard.visitRouteRedirect` / `canAccessVisit*` | C-07 — security regression |
| `_flushEncounterDraft` partial failure + retry | C-03 — duplicate rows |
| Concurrent `save` / `saveAll` | C-04 — race corruption |
| Edits during flush | C-05 — silent loss |
| `VisitEncounterPersistence` defer-vs-direct routing | C-02 — zero coverage |
| `visit_attachment_opener.dart` (`openVisitAttachmentBytes`, cleanup) | `visit_attachment_opener_test.dart` only tests RPC message helper |
| Upload compensation after successful-but-malformed register | H-01 |
| FK clear semantics per update method | H-04 |
| `visit_encounter_draft.dart` merge/archive/`applyTo` | Domain draft logic |
| `patient_safety.dart` `applyTo` / `fromRpcData` | Safety draft merge |
| `visit_row_parsing.dart` direct tests | Date/timezone edge cases |
| Rich-text-only oversized content | H-06 |
| Whitespace-only rich delta vs backend | H-05 |
| `VisitInvestigation` equality with results | H-08 |
| `visitDetailViewProvider` / `patientSafetyProvider` permission flags | M-14 |
| `workspace_mode_provider` load race | M-15 |
| `reloadAfterStale` / `reloadVisit` draft wipe | H-16 |
| Flush callback dispose | H-11 |
| `completeVisit` stale RpcFailure state mapping | M-22 |
| Comma-decimal BMI (weak assertion) | H-07 |
| Doctor name detail vs list consistency | H-17 |
| Timeout/cancellation (behavior absent) | H-03 |

---

## 10. Recommended Refactoring

### Phase 1 — Blocking correctness (before broad UI wiring)

1. **Fix flush recovery** — clear or diff encounter draft on partial failure; align with comment (C-03).
2. **Serialize saves** — in-flight mutex + re-read state before RPC batches (C-04).
3. **Merge post-flush draft** — preserve in-flight staging on success (C-05).
4. **Fix attachment lifecycle** — symmetric storage delete; safe upload compensation (C-06, H-01).
5. **Align rich-text content rules** with backend trim semantics (H-05, H-06).
6. **Fix BMI locale parsing** + strengthen test (H-07).
7. **Add `auth_route_guard_visits_test.dart`** (C-07).

### Phase 2 — Restore layer boundaries

8. **Extract `VisitDocumentationSnapshot`** in domain; move readiness + badges out of presentation imports (C-01, M-04).
9. **Move `VisitAttachmentPick`** to domain (C-08).
10. **Refactor `VisitEncounterPersistence`** — inject ports, remove `WidgetRef` (C-02); add unit tests.
11. **Extract `FlushEncounterDraftUseCase`** from notifier to `application/` (H-14).
12. **Strip Material/Quill from domain** — presentation mappers (C-09).

### Phase 3 — Feature boundaries and repository split

13. **Extract patient safety** to `patients` or shared module (H-09).
14. **Split `VisitRepository`** by aggregate: visit lifecycle, documentation, catalog, attachments, patient safety, dev seed.
15. **Export `visitRepositoryProvider`** from `repository_providers.dart` or neutralize shared types (H-13).
16. **Unify FK-clear convention** and filename sanitization (H-04, M-01).

### Phase 4 — Resilience and hygiene

17. **Add RPC/HTTP timeouts**; optional retry for reads; cancellation for uploads (H-03).
18. **PHI temp-file policy** — shorter retention, dispose hooks (H-02).
19. **Fix `VisitInvestigation` equality** (H-08).
20. **Provider lifecycle** — `ref.onDispose` for flush callbacks, `ref.mounted` guards (H-11, M-20).
21. **Unify `reloadAfterStale`** with `refreshVisitPreservingDraft` (H-16).
22. **Remove deprecated providers/getters** (L-10).

### Suggested target layout

```
features/visits/
  domain/
    entities/
    value_objects/     # VisitAttachmentPick, BmiResult
    rules/               # readiness, badges, clinicalSectionLengthError
  application/
    flush_encounter_draft.dart
    visit_encounter_persistence.dart   # port-based, no WidgetRef
    visit_rpc_messages.dart
  data/
    visit_repository.dart              # split into focused repos
    visit_attachment_service.dart
    mappers/
  presentation/
    providers/
    mappers/             # EncounterPhase icons/labels
```

---

## Cross-File Consistency Matrix

| Concern | Models | Parsing | Validation | Business rules | Aligned? |
|---------|--------|---------|------------|----------------|----------|
| Clinical note content | `VisitClinicalNote.hasContent` uses trim | `optionalVisitString` | `clinicalSectionLengthError` plain only | `_clinicalNoteSectionHasContent` + rich delta | **Partial** — rich/whitespace gap |
| Submit minimum doc | N/A | N/A | N/A | `visitHasPersistableDocumentation` vs BE | **Mostly** — `investigationResults` clause looser |
| Phase badges vs submit | N/A | N/A | `_sectionTooLong` plain only | Badges count safety; submit does not | **Intentional** UX mismatch |
| Doctor name | Required string | List rejects empty | Detail defaults `'Unknown doctor'` | N/A | **No** |
| Investigation results | `hasResult` uses trim | `optionalVisitString` | N/A | Draft overlay + loose map check | **Partial** |
| BMI | Height/Weight by name | Strips commas | >0 checks | Never stored (FR-025) | **Broken** for locale decimals |
| Attachment delete | N/A | N/A | N/A | Upload two-phase, delete one-phase | **No** |
| Permission gating | N/A | N/A | Route guard | Notifier `_canEditVisit` | **Untested** route path |

---

## Verified Correct (not false alarms)

The reviews explicitly confirmed several behaviors that could look suspicious but are correct:

- `getVisit` null guard is real — `VisitDetail.fromRow` returns nullable.
- Null-aware map entries (`'p_x': ?value`) correctly omit keys when value is null.
- Pre-RPC blank-input guards work (tests assert `client.lastFunction == null`).
- `invokeRpc` maps `PGRST202`/`42501` correctly; logs param keys only, not values (no PHI in logs).
- Stale SOAP concurrency on clinical-note save is handled and tested.
- Rich-text → plain-text sync before review is tested for empty-plain case.
- `signedUrl` fallback path in attachment download is structurally sound when `filePath` absent.

---

## Bottom Line

The visits feature has **solid entity modeling** and **good submit-readiness test coverage** for the clinical-note path, but it is **not production-ready for encounter workspace UI** until structured flush integrity (C-03–C-05), save serialization (C-04), and attachment lifecycle (C-06, H-01) are fixed. **Layer inversions** (C-01, C-02, C-08, C-09) are the main architectural debt and block testability of orchestration. **Visit route guards** (C-07) must be tested before UI ships. Address Phase 1 items first; Phase 2–3 can proceed in parallel with UI migration once blocking correctness is resolved.

---

## Cycle 2 — Second Pass Review

**Date:** 2026-07-05  
**Method:** Four parallel skeptical re-reads (domain, data + application, presentation, cross-cutting) per `docs/review/prompt.md`, with direct code verification against current `frontend/lib/features/visits/`  
**Outcome:** **One cycle 1 Critical resolved (C-06).** Sixteen new Critical/High/Medium findings across all four agent passes. Domain pass adds two High investigation-result defects (H-27, H-28).

### Cycle 2 Executive Summary

Cycle 2 confirms **8 of 9 cycle 1 Critical issues remain open**; **C-06 is resolved** server-side. Highest risks: structured flush integrity (C-03–C-05), concurrent saves (C-04, **C-10**), and **authorization inconsistency (C-11)**.

**C-10** — staging resets `saveStatus` mid-RPC. **C-11** — route guard allows `visits.create` on document route; notifier requires `visits.edit_soap` for mutations (create-only principals get read-only workspace with silent no-ops). **C-07** remains open with false confidence from `visit_permission_service_test.dart` not exercising guards (**H-26**).

Rich-text gaps (H-18–H-20), investigation result overlay bugs (**H-27**, **H-28**), dead `VisitEncounterPersistence` (H-23), and auth misalignment (C-11) round out new findings.

**Remediation priority:** Phase 1 — C-03–C-05, C-04, C-10, **C-11**, **C-07** (add `auth_route_guard_visits_test.dart`), H-05–H-07, H-18–H-20, H-22.

---

### Cycle 1 Triage — Cycle 2 Status

| ID | Severity | Cycle 2 status | Evidence |
|----|----------|----------------|----------|
| C-01 | Critical | **STILL OPEN** | `visit_submit_readiness.dart` still imports `encounter_step_provider.dart` and `visit_documentation_notifier.dart` |
| C-02 | Critical | **STILL OPEN** | `visit_encounter_persistence.dart` still holds `WidgetRef` and imports presentation notifier |
| C-03 | Critical | **STILL OPEN** | `_recoverEncounterDraftAfterFlushFailure` retains `afterNote.encounterDraft` (L1398) despite comment claiming draft is cleared (L1381) |
| C-04 | Critical | **STILL OPEN** | No in-flight mutex in `saveAll()` / `save()` / `_flushEncounterDraft()` |
| C-05 | Critical | **STILL OPEN** | Flush success rebuilds via `fromVisit(refreshed)` without merging post-await `encounterDraft` (L1340–1353) |
| C-06 | Critical | **RESOLVED** | Backend `delete_visit_attachment` RPC deletes `storage.objects` then soft-deletes metadata (`backend/supabase/migrations/20260711190000_*`). Client correctly delegates via RPC; residual gap is no integration test asserting storage lifecycle |
| C-07 | Critical | **STILL OPEN** | No tests reference `visitRouteRedirect`, `canAccessVisitDocumentation`, or `canAccessVisitDetail` |
| C-08 | Critical | **STILL OPEN** | `PendingVisitAttachment.pick` still typed as `VisitAttachmentPickInput` from data layer |
| C-09 | Critical | **STILL OPEN** | `encounter_phase.dart` imports `material.dart`; `rich_text_draft_utils.dart` imports `flutter_quill` |
| H-01 | High | **STILL OPEN** | `uploadAndRegister` catch block still removes storage on any register failure (L134–141) |
| H-02 | High | **STILL OPEN** | Temp-file PHI policy unchanged in `visit_attachment_opener.dart` |
| H-03 | High | **STILL OPEN** | No RPC/HTTP timeouts in visits data paths |
| H-04 | High | **STILL OPEN** | `updateVisitVitalSign` still uses null-aware `p_predefined_vital_sign_id` with no clear flag (L254–260) |
| H-05 | High | **STILL OPEN** | Whitespace-only rich deltas still non-empty client-side (`rich_text_draft_utils.dart` L4–14) |
| H-06 | High | **STILL OPEN** | `clinicalSectionLengthError` still plain-length only (`visit_clinical_note.dart` L15–19) |
| H-07 | High | **STILL OPEN** | `_parseVitalNumeric` still strips commas (`bmi.dart` L51) |
| H-08 | High | **STILL OPEN** | `VisitInvestigation` equality still omits result fields (L31–43) |
| H-09 | High | **STILL OPEN** | Patient safety CRUD still in `VisitRepository` |
| H-10 | High | **STILL OPEN** | `_flushEncounterDraft` still untested |
| H-11 | High | **STILL OPEN** | `_clinicalNoteFlushCallbacks` — no `ref.onDispose` in `build()` (L192–194) |
| H-12 | High | **STILL OPEN** | `completeVisit({expectedUpdatedAt})` parameter still unused (L229 vs L265) |
| H-13 | High | **STILL OPEN (worse)** | `repository_providers.dart` has **zero imports project-wide**; visit repo not exported; patients/dev shell import `visits/data` directly |
| H-14 | High | **STILL OPEN** | `_flushEncounterDraft` (~220 lines) still in presentation notifier |
| H-15 | High | **STILL OPEN** | `hasUnsavedDraft` returns `false` when `saveStatus == saving` (L85–88) |
| H-16 | High | **STILL OPEN** | `reloadVisit` / `reloadAfterStale` still call `invalidateSelf()` instead of `refreshVisitPreservingDraft` |
| H-17 | High | **STILL OPEN** | Detail defaults `'Unknown doctor'`; list rejects empty `doctor_name` |
| M-01–M-22 | Medium | **STILL OPEN** | No material changes detected in any medium-priority item |

---

### Cycle 2 — New Critical Issues

#### C-10 — Staging / note edits reset `saveStatus` from `saving` → `idle` during in-flight persist

| Field | Detail |
|-------|--------|
| **Severity** | Critical (amplifies C-04) |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | `_applyEncounterDraft` (L511) and `_updateDraft` (L334) unconditionally set `saveStatus: DocumentationSaveStatus.idle` with no guard when flush/save is in progress. `prepareEncounterReview` also demotes `saving` → `idle` (L545–547). |
| **Why** | UI and guards believe save finished while RPCs still run; second save/flush can start. |
| **Impact** | Overlapping flushes, duplicate server rows, corrupted concurrency tokens. |
| **Solution** | No-op staging/note edits while `saveStatus == saving`; never downgrade `saving` in `prepareEncounterReview`; or serialize all mutations behind an in-flight mutex (C-04). |

---

#### C-11 — Route guard allows `visits.create`; notifier requires `visits.edit_soap` for all mutations

| Field | Detail |
|-------|--------|
| **Severity** | Critical (authorization inconsistency) |
| **Files** | `core/auth/auth_route_guard.dart`, `presentation/providers/visit_documentation_notifier.dart`, `presentation/providers/visit_detail_provider.dart` |
| **Evidence** | Guard: `canAccessVisitDocumentation` → `canCreateVisits() \|\| canEditVisitSoap()` (L109–114). Notifier: `_canEditVisit` → `canEditVisitSoap()` only (L208–212). `_load()` fetches full visit with no permission gate. `visitDetailViewProvider.canEditDocumentation` also uses `canEditVisitSoap()` only. |
| **Why** | Custom RBAC can grant `visits.create` without `visits.edit_soap`; seed roles bundle both, masking the split. |
| **Impact** | Principal passes route guard, loads full SOAP workspace, mutations silently no-op via `_canMutateVisit`. Authorization model inconsistent across layers and untested. |
| **Solution** | Align guard with notifier (document route = `edit_soap` only, or add explicit read permission); add cross-layer tests for create-only, edit-only, upload-only, and denied cases. |

---

### Cycle 2 — New High Priority Issues

#### H-18 — `save()` does not sync Quill deltas before persisting plain text

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | `saveAll()` and `completeVisit()` call `prepareEncounterReview()` (which runs `_syncPlainTextFromRichDrafts`) before persist. `save()` (L391–425) reads `current.complaint` etc. directly with no rich-text sync. `saveVisitDocumentation` RPC accepts plain strings only — no delta payload. |
| **Why** | Two save entry points with inconsistent pre-persist normalization. |
| **Impact** | A direct `save()` call (or any future UI wiring that bypasses `saveAll`) can persist empty plain fields while Quill holds the only copy of clinical content. |
| **Solution** | Call `prepareEncounterReview()` (or `_syncPlainTextFromRichDrafts`) at the start of `save()`; add test: rich-only delta → `save()` → RPC receives synced plain text. |

---

#### H-19 — `save()` success path drops in-session `richTextDrafts`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | After successful save, state rebuild uses `VisitDocumentationState.fromVisit(refreshed).copyWith(complaint: …, plan: …)` (L428–439) without passing `richTextDrafts: current.richTextDrafts`. `fromVisit` defaults `richTextDrafts` to `{}` (L163). |
| **Why** | Rich deltas are documented as in-session formatting state (L63–64 comment). |
| **Impact** | Successful clinical-note save wipes Quill editor state; user loses bold/lists/formatting mid-session even when plain text was persisted. |
| **Solution** | Preserve `richTextDrafts` in post-save `copyWith`; or rehydrate deltas from persisted plain text if backend never stores deltas. |

---

#### H-20 — Unsaved-change detection ignores rich-text-only edits

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | `_clinicalNoteDiffersFromPersisted()` (L97–104) compares trimmed plain strings only. `hasUnsavedDraft` / `needsPersistBeforeSubmit` depend on this. `richTextDrafts` with non-empty content and empty plain field returns `false`. |
| **Why** | Rich-text sync is deferred to `prepareEncounterReview`, but unsaved detection runs without it. |
| **Impact** | Navigation leave-guards (`hasUnsavedChanges`) and UI dirty indicators miss rich-only edits; user can navigate away without warning. Compounds H-15 (saving state also hides dirty). |
| **Solution** | Include rich delta comparison in `_clinicalNoteDiffersFromPersisted` (e.g. `!richDeltaIsEffectivelyEmpty(richTextDrafts[section])` when plain is empty); test rich-only dirty state. |

---

#### H-21 — Application layer imports data layer in `visit_rpc_messages.dart`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `application/visit_rpc_messages.dart`, `data/visit_attachment_service.dart`, `data/visit_attachment_opener.dart` |
| **Evidence** | `visit_rpc_messages.dart` imports data-layer files for `VisitAttachmentValidationException` and opener types. Cycle 1 flagged C-02 (`visit_encounter_persistence`) but not this sibling application file. |
| **Why** | Application should depend on domain abstractions, not concrete data implementations. |
| **Impact** | Error-mapping logic cannot be unit-tested without data-layer types; refactors to attachment service break application imports. |
| **Solution** | Move shared exception/result types to `domain/` or `core/`; keep `visit_rpc_messages.dart` free of `features/visits/data/` imports. |

---

#### H-22 — `prepareEncounterReview()` demotes `saving` → `idle` during in-flight save

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/visit_documentation_notifier.dart`, `presentation/providers/encounter_step_provider.dart` |
| **Evidence** | L545–547 explicitly reset `saving` to `idle`. `encounterActivePhaseProvider.setPhase(EncounterPhase.review)` calls `prepareEncounterReview()` — callable while save is in flight. |
| **Why** | Save spinner/guards cleared mid-RPC. |
| **Impact** | Enables concurrent saves (C-04/C-10); user can navigate to review while persist incomplete. |
| **Solution** | Do not downgrade `saving` in `prepareEncounterReview`; block review navigation while persist in flight. |

---

#### H-23 — `VisitEncounterPersistence` is dead code (zero production call sites)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `application/visit_encounter_persistence.dart` |
| **Evidence** | Repo-wide grep: class/factory only referenced in its own file (~360 lines). Presentation notifier implements staging via direct `stage*` methods; `_flushEncounterDraft` calls repository/service directly. |
| **Why** | Mislayered application class provides no runtime value. |
| **Impact** | Defer-vs-direct routing never exercised; C-02/H-14 debt with zero production benefit; misleads maintainers about architecture. |
| **Solution** | Wire UI through persistence router **or** delete and consolidate; if kept, inject ports and add unit tests. |

---

#### H-24 — Asymmetric attachment delete vs upload paths in flush

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/visit_documentation_notifier.dart`, `data/visit_attachment_service.dart` |
| **Evidence** | Flush uploads via `attachmentService.uploadAndRegister` (L1266–1272); deletes via `repo.deleteVisitAttachment` (L1275–1278), bypassing `VisitAttachmentService.deleteAttachment`. |
| **Why** | Two parallel delete surfaces. |
| **Impact** | Future client-side attachment logic (metrics, retry, pre-delete fetch) must be duplicated or one path misses it. |
| **Solution** | Route all attachment lifecycle through `VisitAttachmentService`. |

---

#### H-25 — `completeVisit` RpcFailure leaves presentation state unchanged

| Field | Detail |
|-------|--------|
| **Severity** | High (cycle 1 M-22, elevated in cycle 2) |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | `save()` maps `STALE_DOCUMENTATION` to `saveStatus: stale`. `completeVisit` catches `RpcFailure` and rethrows with no state update (L267–284). |
| **Impact** | UI shows `saved`/idle after failed complete; user retries without stale awareness. |
| **Solution** | Mirror `save()` stale/error mapping before rethrow. |

---

#### H-26 — Permission tests create false confidence; route guard layer untested

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `test/unit/visits/visit_permission_service_test.dart`, `core/auth/auth_route_guard.dart` |
| **Evidence** | `visit_permission_service_test.dart` asserts `PermissionService` helpers only — not `AuthRouteGuard.canAccessVisitDocumentation` / `visitRouteRedirect`. Lab-staff upload-only path (detail allowed, document denied) has no test. Sibling guard suites exist for billing, patients, appointments — not visits. |
| **Impact** | Test suite suggests visit permissions are covered; route enforcement (C-07) and C-11 split are completely unverified. |
| **Solution** | Add `auth_route_guard_visits_test.dart`; cross-reference permission matrix from role seed data. |

---

#### H-27 — `investigationResults` overlay applied only to `pendingInvestigations`, not `investigations`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/visit_encounter_draft.dart` |
| **Evidence** | `_mergeInvestigations` does not call `_withInvestigationResult`; `_mergePendingInvestigations` does. `stageInvestigationResult` stores results for any line ID including current-visit `investigations`, but those results never appear on `effectiveVisit.investigations`. |
| **Impact** | Staged results on current-visit lines invisible in `effectiveVisit` until flush + reload; UI/BMI consumers see stale data. Compounds H-08. |
| **Solution** | Apply `_withInvestigationResult` in `_mergeInvestigations`; add `applyTo` unit tests for results keyed to both investigation lists. |

---

#### H-28 — Pending investigation result alone satisfies client submit gate; backend rejects

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/visit_submit_readiness.dart` |
| **Evidence** | `visitHasPersistableDocumentation` counts `visit.pendingInvestigations.any((i) => i.hasResult)` and unflushed `investigationResults` map. Backend `visit_has_documentation` only checks rows on current `visit_id` — recording a cross-visit pending result does not create a current-visit documentation row. |
| **Impact** | Clinician records only documentation action (pending result); UI submit passes; `complete_visit` fails with `DOCUMENTATION_REQUIRED_FOR_COMPLETE`. Extends cycle-1 M-07. |
| **Solution** | Align client rule with backend, or extend `visit_has_documentation` to count result recording on the current encounter. |

---

### Cycle 2 — New Medium Priority Issues

#### M-23 — `_recoverEncounterDraftAfterFlushFailure` docstring contradicts implementation

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | Docstring L1381: *"Clears the encounter draft overlay to avoid duplicate creates on retry."* Implementation L1398: `encounterDraft: afterNote.encounterDraft` — draft is **retained**. |
| **Why** | Comment documents intended C-03 fix that was never applied. |
| **Impact** | Maintainers trusting the docstring will misdiagnose duplicate-create bugs; wrong fixes may be attempted. |
| **Solution** | Either clear draft (`encounterDraft: const VisitEncounterDraft()`) or update docstring to match retention strategy and document retry UX. |

---

#### M-24 — `save()` omits `richTextDrafts` in stale/error recovery paths

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | `save()` stale handler (L443–446) and error handler update `saveStatus`/`errorMessage` on `currentAfter` without preserving or re-syncing `richTextDrafts`. Combined with H-19 on success path. |
| **Why** | Inconsistent state object shape across save outcomes. |
| **Impact** | Editor state may diverge from notifier state after failed save; retry behavior unpredictable. |
| **Solution** | Centralize post-mutation state rebuild helper that always carries forward `richTextDrafts` and synced plain text. |

---

#### M-25 — `patientSafetyProvider` not invalidated after safety flush

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `presentation/providers/visit_documentation_notifier.dart`, `presentation/providers/patient_safety_provider.dart` |
| **Evidence** | `_flushEncounterDraft` persists allergies/medications/conditions but does not `ref.invalidate(patientSafetyProvider(...))`. Notifier reads stale provider in `_findAllergyInContext` etc. |
| **Impact** | Widgets bound to `patientSafetyProvider` show stale safety data after successful save. |
| **Solution** | Invalidate `patientSafetyProvider(patientId)` after safety RPC batch in flush success/recovery. |

---

#### M-26 — No post-await `ref.mounted` guards in async presentation methods

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | All async methods in presentation providers |
| **Evidence** | Zero `ref.mounted` checks under `presentation/`. Auto-dispose provider writes state after navigation away. |
| **Impact** | State writes on disposed notifier; framework warnings / stale UI updates. |
| **Solution** | Guard all post-await `state =` assignments with `if (!ref.mounted) return`. |

---

#### M-27 — `visitDetailViewProvider` edit flag ignores completed-visit viewing rules

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `presentation/providers/visit_detail_provider.dart`, `presentation/providers/visit_documentation_notifier.dart` |
| **Evidence** | Detail: `canEditDocumentation: canEditSoap && hasBranchAccess`. Notifier: completed visits require `enterWorkspaceEditMode()` via `canEditWorkspace`. |
| **Impact** | Detail screen shows edit affordance; documentation workspace blocks until explicit mode switch. |
| **Solution** | Align detail flag with visit status + workspace edit mode policy. |

---

#### M-28 — `?edit=1` deep-link contract built but unwired

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app/app_routes.dart`, `app/app_navigator.dart`, `app/router.dart` |
| **Evidence** | `AppRoutes.visitDocument(visitId, startEditing: true)` → `.../document?edit=1` (tested in `app_routes_visits_test.dart`). `AppNavigator.goVisitDocument` / `pushVisitDocument` never pass `startEditing: true`. Router placeholder; no provider reads `state.uri.queryParameters['edit']`. |
| **Impact** | Documented API contract is dead; post-complete edit entry cannot be deep-linked. |
| **Solution** | Wire query to `WorkspaceEditMode`; add navigator helper; test if query affects auth. |

---

#### M-29 — Patients history silently drops visits with empty `doctor_name`

| Field | Detail |
|-------|--------|
| **Severity** | Medium (cross-feature; extends H-17) |
| **Files** | `domain/visit_list_item.dart`, `domain/visit_detail.dart`, `patients/presentation/providers/patient_detail_history_provider.dart` |
| **Evidence** | `VisitListItem.fromRow` returns `null` when `doctor_name` empty; `VisitDetail.fromRow` defaults to `'Unknown doctor'`. Same payload: visible in detail, missing from patient timeline. No test in `patient_detail_history_provider_test.dart`. |
| **Impact** | Patient history incomplete vs visit detail for partial backend rows. |
| **Solution** | Shared doctor-name parsing policy; integration test through `patientPastVisitsProvider`. |

---

#### M-30 — `patientPastVisitsProvider` hardcodes `limit: 100` with no pagination

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `patients/presentation/providers/patient_detail_history_provider.dart`, `data/visit_repository.dart` |
| **Evidence** | `listPatientVisits(patientId: patientId, limit: 100)` (L59). Repository supports `offset`; provider ignores `total_count`. |
| **Impact** | Long-tenure patients lose visits beyond 100 from timeline with no UI indication. |
| **Solution** | Paginate or surface truncation; test boundary at limit. |

---

#### M-31 — `applyTo` stamps non-deterministic `resultRecordedAt` via `DateTime.now()`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/visit_encounter_draft.dart` |
| **Evidence** | `_withInvestigationResult` sets `resultRecordedAt: DateTime.now().toUtc()` on every rebuild when staged result unchanged. |
| **Impact** | Unstable domain projection; equality/display keyed on `resultRecordedAt` will flicker. Same anti-pattern as M-11 (`PendingVisitAttachment.toDisplayItem`). |
| **Solution** | Use `null` until persisted, or pass a fixed staged timestamp into draft merge. |

---

#### M-32 — Draft field `pendingInvestigations` collides with `VisitDetail.pendingInvestigations` semantics

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/visit_encounter_draft.dart` |
| **Evidence** | Draft `pendingInvestigations` (staged creates) merges into `VisitDetail.investigations`, not `VisitDetail.pendingInvestigations` (server prior-visit lines). Name collision contributed to H-27 overlay bug. |
| **Impact** | Maintainability risk; easy to apply overlay logic to wrong list. |
| **Solution** | Rename draft field to `stagedNewInvestigations` or `pendingCreates`. |

---

### Cycle 2 — Cross-Cutting Confirmations

| Area | Cycle 2 finding |
|------|-----------------|
| Route guards | `visitRouteRedirect` wired in `router.dart` L289; **zero dedicated tests** (C-07); **guard ≠ notifier permissions** (C-11) |
| DI barrel | `repository_providers.dart` **unused project-wide**; visit repo not exported (H-13) |
| Patients coupling | Direct `visits/data` + `visits/domain` imports; history truncation (M-30) and parsing gap (M-29/H-17) |
| Permission tests | `visit_permission_service_test.dart` does **not** cover `AuthRouteGuard` (H-26) |
| Application layer | `VisitEncounterPersistence` dead — zero call sites (H-23) |
| Test count | 23 files under `test/unit/visits/`; no flush, guard, persistence, or rich-save race tests |
| UI maturity | All visit screens `uiPendingPlaceholder`; `?edit=1` unwired (M-28) |

---

### Cycle 2 — Updated Recommended Priority

1. **Phase 1 (blocking)** — C-03–C-05, C-04, **C-10**, **C-11**, **C-07** + `auth_route_guard_visits_test.dart`, H-05–H-08, **H-27–H-28**, H-18–H-20, H-22, H-26.
2. **Phase 1 (attachments)** — H-01 upload compensation + post-commit parse test (C-06 resolved; unify delete via H-24).
3. **Phase 2** — H-21, H-23 (wire or remove dead persistence), layer boundaries (C-01, C-02, C-08, C-09), H-13 barrel enforcement.
4. **Documentation / contracts** — M-23 (C-03 docstring), M-28 (`?edit=1` wiring).

---

### Cycle 2 Bottom Line

Cycle 2 **confirms** cycle 1 with one resolution (**C-06** server-side). The inventory **grew by two Critical (C-10, C-11), ten High (H-18–H-28), and ten Medium (M-23–M-32)**. Top risk clusters: **structured flush integrity**, **save concurrency / saveStatus races (C-04, C-10, H-22)**, **auth misalignment (C-11, C-07, H-26)**, **investigation result handling (H-27, H-28, H-08)**, and **rich-text draft lifecycle (H-18–H-20)**. All four agent passes completed: [domain](bc2b862b-bb40-4847-a300-1fd1b529d5d3), [presentation](2dea649c-cf84-4ddd-91f3-5906f8902efe), [data/application](90c92523-3cad-4abb-836c-556d80e2daff), [cross-cutting](b909146a-fa1f-41f9-aff7-85c1fb4a3118).
