# Quickstart: Acceptance recording RPC and client accept path (F2)

F2 adds the clinic-side `public.record_ai_acceptance` RPC, the `ai_internal.acceptance_targets`
registry, `public.ai_accepted_output`, and the Flutter clinical accept/discard **library** under
`frontend/lib/features/ai/acceptance/` (harness/tests). Acceptance is entirely clinic-side — no
gateway or D1 journal involvement. No production Feature Surface wires clinical accept yet
(Open Decision 1 keeps capabilities on `advisory_display`).

**Scope rule:** This document covers slice F2 only.

## 1. Architecture context

- **Delivery plan row:** F2 in [`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.7 — acceptance recording RPC and client accept path.
- **Architecture sections:** §4.2 / §4.2.2 (clinic acceptance RPC and provenance), §4.1 (Feature Surfaces clinical accept path), A5 (human-gated acceptance; no auto-commit).
- **Spec delivered:** Single shared `record_ai_acceptance` RPC, registry + demonstration target `visit_clinical_notes` → `save_visit_documentation`, atomic domain + `ai_accepted_output` + `ai.acceptance_record` audit, clinical accept library (harness/tests) without promoting or wiring `advisory_display`.
- **Plan scoped:** Migration(s) including review-resolution, Flutter `acceptance/` library, SQL + Flutter test suites T1–T10, frozen contract at `contracts/acceptance-recording.md`.

## 2. What was implemented

- `public.record_ai_acceptance` — delegates to allow-listed domain RPCs; writes domain change, `ai_accepted_output`, and `ai.acceptance_record` audit in one transaction.
- `ai_internal.acceptance_targets` — registry with demonstration row `visit_clinical_notes` (registry is the only enablement source; dispatch resolves `domain_function` via catalog lookup).
- `public.ai_accepted_output` — stores the AI request reference handle only (no prompts/providers/models).
- Flutter clinical accept **library** — `ClinicalAcceptController` (port/client/controller) invoked from harness/tests on explicit accept; discard writes nothing. Not a runnable product surface; production Feature Surface wiring awaits `human_accept_required`.
- E4 `advisory_display` accept remains non-writing and does not use this library (T8).

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql` | Registry, `ai_accepted_output`, `record_ai_acceptance`, demonstration seed |
| `backend/supabase/migrations/20260805150000_f2_review_resolution.sql` | Review honesty: registry-driven dispatch, auth, duplicate reject |
| `backend/tests/ai_acceptance_recording.sql` | SQL named tests T1–T6, T9–T10 |
| `backend/tests/run_ai_platform_trust_tests.sh` | CI wiring for this slice's SQL suite |
| `frontend/lib/features/ai/acceptance/clinical_acceptance_port.dart` | Injectable acceptance port |
| `frontend/lib/features/ai/acceptance/clinical_acceptance_client.dart` | Supabase RPC caller |
| `frontend/lib/features/ai/acceptance/clinical_accept_controller.dart` | Accept/discard library orchestration |
| `frontend/test/widget/ai/clinical_accept_path_test.dart` | Flutter widget/spy tests T1, T3–T4, T7–T8 |
| `frontend/test/unit/ai/clinical_acceptance_client_test.dart` | RPC parameter mapping unit tests |
| `specs/040-acceptance-recording/contracts/acceptance-recording.md` | Frozen RPC/registry/table contract |

## 4. Prerequisites

- Local Supabase PostgreSQL with migrations applied (including
  `20260802150000_ai_acceptance_recording.sql` and
  `20260805150000_f2_review_resolution.sql`).
- Flutter SDK as declared in `frontend/pubspec.yaml`.

## 5. Run the automated suite

From the repository root:

```bash
# SQL suite (requires local Supabase on port 54322)
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/ai_acceptance_recording.sql

# Flutter slice tests
cd frontend
flutter test test/widget/ai/clinical_accept_path_test.dart \
             test/unit/ai/clinical_acceptance_client_test.dart
```

Expected: **7 passing Flutter tests** and **9 passing SQL assertions** (fixture + T1–T6, T9–T10).

## 6. Inspect the changes

```bash
# RPC signature
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
  -c "\df+ public.record_ai_acceptance"

# Demonstration registry row
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
  -c "SELECT * FROM ai_internal.acceptance_targets WHERE target_key = 'visit_clinical_notes';"

# ai_accepted_output columns
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
  -c "\d public.ai_accepted_output"
```

Review the Flutter modules under `frontend/lib/features/ai/acceptance/` and the focused test files listed above.

## 7. Manual validation

Optional: with a local visit in progress, drive the clinical accept **harness** (test fixture /
library under `frontend/lib/features/ai/acceptance/`, not a runnable product surface) against
`visit_clinical_notes` → `save_visit_documentation` using a valid §8.9 request reference and the
doctor's `visits.edit_soap` permission. SQL + Flutter automated suites are the primary verification
path.
