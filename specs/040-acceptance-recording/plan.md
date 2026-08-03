# Implementation Plan: Acceptance recording RPC and client accept path (F2)

**Branch**: `ai/040-f2-acceptance-recording` | **Date**: 2026-08-02 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/040-acceptance-recording/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

F2 freezes the clinic-side AI acceptance mechanism: `public.record_ai_acceptance` delegates to an allow-listed existing domain RPC and, in one transaction, writes the domain change, the `ai_accepted_output` row carrying the AI request reference, and the `audit_log` entry (`action = 'ai.acceptance_record'`) that joins them bidirectionally — plus the Flutter clinical accept/discard path on AI Feature Surfaces. It sits in Band F after E4 and C3 (`Needs: E4, C3`); it is required before any capability may write to a clinical record, but is not a CP3 prerequisite when the first capability stays `advisory_display` (delivery plan §3.7; Open Decision 1).

## Technical Context

**Language/Version**: PostgreSQL / Supabase SQL for the acceptance RPC, registry, and `ai_accepted_output` (matching existing `public` INVOKER → `auth_internal` SECURITY DEFINER clinic RPCs); Dart (SDK `^3.11.5` as declared in `frontend/pubspec.yaml`) for the clinical accept path on AI Feature Surfaces.

**Primary Dependencies**: Existing clinic RPC/audit patterns under `backend/supabase/migrations/`; existing demonstration domain RPC `public.save_visit_documentation` → `auth_internal.save_visit_documentation` (writes `public.visit_clinical_notes`); E4 AI Feature Surfaces under `frontend/lib/features/ai/` (Consumes — provisional styling / accept-discard affordances / advisory_display non-writing behaviour not redefined); C3/A2 request reference as the join key (Consumes — text handle only; no D1 write). No Worker source changes, no new pub packages, no platform error-taxonomy codes.

**Storage**: Clinic Supabase PostgreSQL only. New: `ai_internal.acceptance_targets`, `public.ai_accepted_output`, `public`/`auth_internal.record_ai_acceptance`, registry seed row for the demonstration target. **No D1, no R2, no Durable Object, no `ai-platform/` changes** — acceptance is clinic-side (A5; §4.2 boundary note).

**Testing**: SQL + Flutter (delivery plan §3.11.6 row F2; DP-3). Named cases T1–T10: SQL suites under `backend/tests/` (atomicity, provenance, unregistered reject, delegated error pass-through, boundary spy, demonstration registry); Flutter widget/unit spies under `frontend/test/` (discard, unaccepted never persisted, no auto-commit, advisory_display unchanged, clinical accept invoking the RPC against the demonstration target). Suite joins CI permanently (delivery plan §3.10). Mapping to §13.5: SQL suites are the clinic Contract/SQL verification path (same posture as B1); Flutter cases are the client widget/spy layer; T10 also asserts the frozen contract artifact.

**Target Platform**: Flutter Windows desktop client (`frontend/`) and local/clinic Supabase PostgreSQL (`backend/`). AI remains optional and additive; this slice adds no gateway stage.

**Project Type**: Dual-layer slice — clinic acceptance RPC/registry/table under `backend/` plus clinical accept path under `frontend/lib/features/ai/`. Not a Worker slice (`ai-platform/` unchanged).

**Performance Goals**: None beyond ordinary clinic RPC/UI. F2 adds no Quota DO round trip, no D1 insert, and no R2 object on the Worker path; platform I/O budgets (§6.1, §7.5, §13.6) remain untouched. Acceptance does not journal into D1.

**Constraints**: Domain change + `ai_accepted_output` + `ai.acceptance_record` audit together or not at all (FR-009). Unregistered `p_target_key` rejected before any write (FR-004). Delegated errors pass through unchanged — no new clinic or platform error vocabulary (FR-005). Clinic stores the request-reference handle only — no prompts, providers, quotas, or AI request state (FR-007, FR-016). No auto-commit; discard writes nothing; unaccepted content never persisted (FR-012–FR-014; A5; §6.4). Demonstration target `visit_clinical_notes` → `public.save_visit_documentation` proves the mechanism without promoting any product capability to `human_accept_required` (FR-011; Open Decision 1). E4 `advisory_display` accept remains non-writing (FR-018). One shared RPC only — no second acceptance path (FR-019; Open Decision 14). No prompt/provider/model identifiers in Flutter (FR-017; R-12).

**Scale/Scope**: Two §4 components with an explicit reason (see Components Touched): §4.2 AI acceptance recording RPC and §4.1 AI Feature Surfaces (clinical accept path). ~one migration (+ runner wiring), one frozen contract, a small Flutter acceptance module family, SQL + Flutter test suites for T1–T10, one quickstart. Nineteen FRs. Ten named tests. Roughly 18–22 tasks when SQL cases and Flutter spies are grouped — under the ~25-task ceiling (delivery plan §6.3 / skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — human-gated
      acceptance of advisory AI into clinical records; clinics can refuse accept and continue
      manual documentation (A5; constitution I; spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — additive clinic RPC/table/registry and
      Flutter accept path; no new deployable.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — acceptance
      RPC/registry/`ai_accepted_output` in `backend/`; clinical accept path in `frontend/`;
      `ai-platform/` unchanged. Gateway remains the additive, non-primary §14 component (no
      domain logic, no business data, no write path into Supabase); F2 reinforces that boundary
      by keeping clinical acceptance entirely on the clinic side and routing writes through
      existing domain RPCs (§4.2; §14; spec Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — delegated domain RPC
      keeps its own authorization/validation/triggers/RLS; atomicity of domain write +
      `ai_accepted_output` + `audit_log` is a transaction property of
      `auth_internal.record_ai_acceptance` (constitution III; FR-002, FR-009).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — `organization_id` / `branch_id` on
      `ai_accepted_output`; acceptance grants no privilege the clinician did not already have;
      `ai.acceptance_record` audit; soft-delete conventions unchanged (§4.2.2).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — explicit human
      accept required (A5); discard/non-accept leave clinical workflows unchanged; without a
      prior terminal result and request reference, clinical accept is simply not offered;
      Consumes E4 degraded mode without redefining it (constitution V; FR-012–FR-014).

## Project Structure

### Documentation (this feature)

```text
specs/040-acceptance-recording/
├── plan.md                              # This file
├── spec.md                              # /ai-platform-specify + /ai-platform-clarify (authoritative)
├── contracts/
│   └── acceptance-recording.md          # Frozen: RPC, registry, ai_accepted_output, audit, demo target
└── quickstart.md                        # Written during the implement-phase Documentation task
```

`data-model.md` is **not** produced — F2 defines clinic-side Supabase entities, not D1 entities
(the platform's store). Entity shapes live in `contracts/acceptance-recording.md`.

`research.md` is **not** produced — the research is `docs/architecture/17-ai-platform.md`.

`contracts/` is produced because **Freezes** entries have wire/table shapes later slices’
**Consumes** must bind to: the RPC signature and success/failure contract, the
`acceptance_targets` registry, `ai_accepted_output` columns/constraints, the
`ai.acceptance_record` audit join, and the demonstration target row. Behavioural Freezes
(single shared path; client clinical accept/discard rules) bind to the Flutter modules under
`frontend/lib/features/ai/` and are described in the same contract for Completeness (same posture
as E4 behavioural Freezes).

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:

- **§1 Architecture context** — F2 row of the delivery plan (§3.7) and §4.2 / §4.2.2 / §4.1 / A5;
  what the spec delivered; what the plan scoped.
- **§2 What was implemented** — `record_ai_acceptance`, registry + demonstration target,
  `ai_accepted_output`, clinical accept path on Feature Surfaces (without promoting
  `advisory_display`).
- **§3 Files to review** — this slice’s migration(s), `frontend/lib/features/ai/acceptance/`,
  SQL + Flutter test files, and `contracts/acceptance-recording.md` only.
- **§5 Run the automated suite** — slice-only SQL (`psql -f` / trust-runner entry for this
  slice’s SQL file) and `flutter test` against this slice’s test files; no full-suite `npm test`,
  no combined prior-slice counts.
- **§6 Inspect the changes** — `\df+ public.record_ai_acceptance`, registry row,
  `ai_accepted_output` columns, clinical accept module, focused SQL/Flutter tests.
- **§7 Manual validation** — optional: drive the clinical accept harness against a local visit
  documentation save via the demonstration target. Omit detailed deploy steps — SQL + Flutter
  suites are the primary verification path (DP-3).

### Source Code (repository root)

```text
frontend/
├── lib/
│   ├── core/
│   │   └── ai/                                    # UNCHANGED — Consumes request reference via E2/E4
│   │       ├── ai_client_sdk.dart                 # lastRequestReference (Consumes)
│   │       └── sse_events.dart                    # terminal events carrying reference (Consumes)
│   └── features/
│       └── ai/
│           ├── surface/
│           │   └── first_ai_feature_surface.dart  # UNCHANGED behaviour for advisory_display (FR-018; T8)
│           └── acceptance/                        # NEW — clinical accept path (FR-012–FR-014, FR-017)
│               ├── clinical_acceptance_port.dart  # NEW — injectable port → record_ai_acceptance
│               ├── clinical_acceptance_client.dart# NEW — Supabase RPC caller (no prompts/models)
│               └── clinical_accept_controller.dart# NEW — accept invokes RPC; discard writes nothing
├── test/
│   ├── widget/
│   │   └── ai/
│   │       └── clinical_accept_path_test.dart     # NEW — Flutter T1/T3/T4/T7/T8 (spy)
│   └── unit/
│       └── ai/
│           └── clinical_acceptance_client_test.dart # NEW — RPC arg shape / no auto-commit spy support
└── tool/
    └── architecture_guard/                        # UNCHANGED — Consumes E1 / R-12 (FR-017)

backend/
├── supabase/
│   └── migrations/
│       └── 20260802150000_ai_acceptance_recording.sql  # NEW — targets, ai_accepted_output, RPC, demo seed
└── tests/
    ├── ai_acceptance_recording.sql                # NEW — SQL T1/T2/T5/T6/T9/T10 (+ Flutter-paired asserts)
    └── run_ai_platform_trust_tests.sh             # MODIFIED — append this slice’s SQL file

# ai-platform/ — UNCHANGED (no D1 journal of acceptance; no gateway write into Supabase)
```

**Structure Decision**: Clinic acceptance lives entirely under `backend/` as additive schema + the
established `public` → `auth_internal` SECURITY DEFINER pattern (F4; FR-002, FR-015). The Flutter
clinical accept path lives under `frontend/lib/features/ai/acceptance/` beside E4 surfaces, and
invokes the clinic RPC with the request reference retained by the E2 SDK — it does not redefine E4
provisional styling, degraded mode, or `clinic.visit_summary` `advisory_display` accept (FR-018;
Consumes E4). Demonstration proof uses the existing `public.save_visit_documentation` RPC; that
RPC is not modified (Consumes ordinary domain write; Freezes only the registry row). Tests follow
existing `backend/tests/*.sql` and `frontend/test/widget/ai/` layouts. No `ai-platform/` path is
modified.

## Consumes Binding

F2 has `Needs: E4, C3` (delivery plan §3.7). Changing any Consumes contract is out of scope
(delivery plan §2.3).

| Consumes entry | Existing module / file / type it binds to |
| --- | --- |
| **E4 — AI Feature Surfaces** (§4.1 Freezes: provisional/draft styling, no commit before terminal success, explicit accept/discard, request-reference on failure, provisional never persisted/exported; `advisory_display` accept non-writing) | `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` (`FirstAiFeatureSurface`, `kAiAcceptKey` / `kAiDiscardKey`, advisory acknowledge-only `_accept`), `provisional_prose_view.dart`, `request_reference_view.dart`, degraded/availability modules under `frontend/lib/features/ai/`, frozen artifact `specs/038-first-ai-feature-surface/contracts/ai-availability-flag.md`. F2 adds the clinical accept path alongside these surfaces and proves `advisory_display` accept still does not invoke `record_ai_acceptance` (T8); it does not redefine provisional styling, degraded-mode UX, or rewrite E4 modules’ advisory behaviour. |
| **C3 — request reference + get-request / terminal validated result** (C3 Freezes; join key to platform journal) | Request reference as `text` in §8.9 format (`XXXX-XXXX`), carried on the client via E2 `AiClientSdk.lastRequestReference` / SSE terminal events (`frontend/lib/core/ai/ai_client_sdk.dart`, `sse_events.dart`) and journaled by C3 (`ai-platform/src/journal/index.ts`, `ai-platform/src/reference.ts`; frozen artifact `specs/027-journal-writer-get-request/contracts/journal.md`). F2 stores that reference on `public.ai_accepted_output.ai_request_reference` at human accept; it does not write D1, invent a second platform acceptance journal, or change get-request semantics. |

**Demonstration domain RPC (assumption / Freezes proof target — not a Consumes rewrite):**
`public.save_visit_documentation` / `auth_internal.save_visit_documentation` in
`backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql` (and follow-ups). F2
registers it in `acceptance_targets`; it does not modify the RPC.

No Consumes entry lacks an existing implementation. None is modified (delivery plan §2.3). Stop
condition 2 is not triggered.

## Components Touched

Two §4 components, with explicit reason:

1. **§4.2 AI acceptance recording RPC** (clinic backend) — `record_ai_acceptance`,
   `ai_internal.acceptance_targets`, `public.ai_accepted_output`, demonstration registry row, and
   `ai.acceptance_record` audit join (§4.2 / §4.2.2; delivery plan §3.7 Done when).
2. **§4.1 AI Feature Surfaces** (client clinical accept path) — after terminal success, explicit
   human accept for clinical-content acceptance invokes `public.record_ai_acceptance`; discard
   writes nothing; unaccepted content never persisted; no auto-commit (§4.1; A5; Done when).

**Reason for two components:** Delivery plan §3.7 row F2 Canonical cell names §4.2, §4.2.2, §4.1,
and A5 together; Done when requires both the clinic RPC/provenance write and the client accept
path. Architecture places the recording contract on Supabase (§4.2.2) and accept/discard UX on
Feature Surfaces (§4.1). Touching both is the minimal way to freeze what F2’s row names; it is not
scope creep into E4 rewrite, C3/D1 journal, F1/F3–F5, B1 token issuer, or gateway stages.

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.1 AI Feature Surfaces | **Extended** | Clinical accept path (FR-012–FR-014); advisory_display behaviour Consumed unchanged |
| §4.1 AI Client SDK | **Not touched** | Consumes request reference via existing SDK fields only |
| §4.1 Context Resolver | **Not touched** | E3 |
| §4.1 Conversation store | **Not touched** | H band |
| §4.2 AI acceptance recording RPC | **Created** | This slice’s clinic deliverable (§4.2.2; Done when) |
| §4.2 Installation keystore / AI token issuer / context provider / availability flag | **Not touched** | B1 / E3 / E4 |
| §4.3.* gateway stages | **Not touched** | Out of scope; no D1 acceptance journal |

Stop condition 5 (multi-component without reason) is not triggered — reason recorded above. Task
count stays under ~25.

## Files

| File | FR(s) | Status |
| --- | --- | --- |
| `specs/040-acceptance-recording/contracts/acceptance-recording.md` | Freezes (RPC, registry, table, audit, demo target); FR-001–FR-011, FR-015–FR-016, FR-019 | NEW — frozen artifact for later Consumes (Open Decision 14 / `human_accept_required`). |
| `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql` | FR-001–FR-011, FR-015–FR-016, FR-019; T1/T2/T5/T6/T9/T10 | NEW — `ai_internal.acceptance_targets`; `public.ai_accepted_output` (+ RLS/indexes/CHECK); `auth_internal.record_ai_acceptance` + `public` wrapper; seed `visit_clinical_notes` → `save_visit_documentation` / `visit_clinical_notes`. |
| `backend/tests/ai_acceptance_recording.sql` | FR-001–FR-011, FR-015–FR-016; T1, T2, T5, T6, T9, T10 | NEW — SQL suite for atomicity, bidirectional provenance, unregistered reject, boundary spy (no AI request state columns), delegated error pass-through, demonstration registry proof. |
| `backend/tests/run_ai_platform_trust_tests.sh` | T1–T2, T5–T6, T9–T10 (CI wiring) | MODIFIED — append `ai_acceptance_recording.sql`. |
| `frontend/lib/features/ai/acceptance/clinical_acceptance_port.dart` | FR-012–FR-014, FR-017; T1, T3, T4, T7 | NEW — injectable port for `record_ai_acceptance` (test doubles). |
| `frontend/lib/features/ai/acceptance/clinical_acceptance_client.dart` | FR-001, FR-012–FR-013, FR-017; T1 | NEW — production Supabase RPC caller; no prompts/providers/models/business rules. |
| `frontend/lib/features/ai/acceptance/clinical_accept_controller.dart` | FR-012–FR-014, FR-018; T1, T3, T4, T7, T8 | NEW — clinical accept invokes RPC with request reference + registered target; discard writes nothing; does not replace E4 advisory_display acknowledge path. |
| `frontend/test/widget/ai/clinical_accept_path_test.dart` | FR-012–FR-014, FR-018; T1, T3, T4, T7, T8 | NEW — Flutter widget/spy suite: accept writes via RPC against demonstration target args; discard/unaccepted/auto-commit spies; advisory_display accept unchanged. |
| `frontend/test/unit/ai/clinical_acceptance_client_test.dart` | FR-013, FR-017; T1, T7 | NEW — unit coverage for RPC parameter mapping / no auto-commit helper behaviour. |
| `specs/040-acceptance-recording/quickstart.md` | — | NEW — written during the implement-phase Documentation task (sections named above). |

Every file traces to an `FR-###` (or Freezes / deferred Documentation). No file is created for an
unstated requirement. No Consumes module is rewritten. No `ai-platform/` file is touched.
`public.save_visit_documentation` is not modified.

## Test Layout

The spec’s Test plan names ten tests at layer **SQL + Flutter** (delivery plan §3.11.6 row F2),
plus coverage-rule additions T6–T10 (§3.10). SQL cases live under `backend/tests/`; Flutter
spy/widget cases under `frontend/test/`. §13.5 mapping: clinic SQL verification (Contract/SQL CI
path, B1 posture) + client Flutter widget/spy suite; T10 also pins the frozen contract artifact.
Tests join CI permanently (delivery plan §3.10).

| # | Named test | Spec layer | Where it lives | Asserts |
| --- | --- | --- | --- | --- |
| T1 | `acceptance_writes_domain_change_and_request_reference_together` | SQL + Flutter | `ai_acceptance_recording.sql` + `clinical_accept_path_test.dart` | Against `visit_clinical_notes` → `save_visit_documentation`: domain row + `ai_accepted_output` + acceptance audit commit together or not at all (§4.2.2; Done when) |
| T2 | `acceptance_audit_log_bidirectional_provenance` | SQL | `ai_acceptance_recording.sql` | `audit_log.action = 'ai.acceptance_record'`; provenance resolves both ways between `(table_name, record_id)` and `ai_request_reference` |
| T3 | `discard_path_writes_nothing` | SQL + Flutter | `ai_acceptance_recording.sql` (precondition/count) + `clinical_accept_path_test.dart` | Discard → no domain change, no `ai_accepted_output`, no acceptance audit |
| T4 | `unaccepted_content_never_persisted` | SQL + Flutter | same pairing | Unaccepted/provisional/display-only content never becomes a clinical write |
| T5 | `unregistered_target_key_rejected` | SQL | `ai_acceptance_recording.sql` | Unknown `p_target_key` rejected before any write |
| T6 | `acceptance_rpc_does_not_store_ai_request_state` | SQL (spy) | `ai_acceptance_recording.sql` | Clinic DB gains acceptance fact only — no prompts/providers/quotas/request-state columns beyond §4.2.2 |
| T7 | `clinical_accept_never_auto_commits` | Flutter (spy) | `clinical_accept_path_test.dart` (+ unit support) | No path auto-commits AI output without explicit human accept |
| T8 | `advisory_display_accept_unchanged` | Flutter (spy) | `clinical_accept_path_test.dart` | E4 `advisory_display` accept still does not invoke `record_ai_acceptance` |
| T9 | `delegated_rpc_errors_pass_through_unchanged` | SQL | `ai_acceptance_recording.sql` | Delegated failure returns that RPC’s `error_code` / `error_message`; writes nothing |
| T10 | `demonstration_target_does_not_promote_capability` | SQL + contract | `ai_acceptance_recording.sql` + `contracts/acceptance-recording.md` | Registry row exists for proof only; no product capability gains `human_accept_required` from this slice |

Every named test places in the SQL and/or Flutter layers named by the delivery plan — stop
condition 3 not triggered. Coverage matches delivery plan §3.10 / spec Coverage paragraph (happy
path, unregistered reject, delegated error pass-through, discard/unaccepted/auto-commit
prohibitions, boundary spy, advisory_display unchanged, demonstration non-promotion).

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2). Within this
slice:

1. **Frozen acceptance contract** — confirm `contracts/acceptance-recording.md` so later Consumes
   bind to an artifact (delivery plan DP-4 / Freezes).
2. **Clinic schema + RPC (FR-001–FR-011, FR-015–FR-016, FR-019; T2, T5, T6, T9, T10)** — land
   migration (registry, `ai_accepted_output`, `record_ai_acceptance`, demonstration seed); land SQL
   suite alongside for unregistered reject, provenance, boundary spy, delegated errors, demo
   non-promotion.
3. **Atomicity SQL (FR-009; T1)** — prove domain + acceptance row + audit together-or-not-at-all
   against `visit_clinical_notes` → `save_visit_documentation`.
4. **Flutter clinical accept path (FR-012–FR-014, FR-017; T1, T3, T4, T7)** — land port/client/
   controller; prove accept invokes RPC, discard/unaccepted write nothing, no auto-commit.
5. **Advisory_display unchanged (FR-018; T8)** — prove E4 first-capability accept still does not
   call `record_ai_acceptance`.
6. **CI wiring** — append SQL file to `run_ai_platform_trust_tests.sh`; ensure Flutter tests are
   runnable via `flutter test` on this slice’s files.
7. **Documentation** — fill `quickstart.md` after implementation and verification (sections named
   above).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations. Table omitted.
