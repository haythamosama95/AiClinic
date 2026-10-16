# Implementation Plan: Desktop denial states and the administrator coverage view

**Branch**: `ai/090-abo-p6-2-desktop-denial-states-administrator-coverage` | **Date**: 2026-10-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/090-abo-p6-2-desktop-denial-states-administrator-coverage/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

The live desktop host shows each platform denial as an inline `AiDegradedView` state, with the staff sentence and the administrator sentence from the denial table, and a denial of `allowance_exhausted` still refreshes status. This is phase P6, size M, and **Depends** P6.1.

## Technical Context

**Language/Version**: Dart / Flutter stable. Desktop app in `frontend/`.

**Primary Dependencies**: Existing `package:http` client and the existing live composition in `frontend/lib/features/ai/presentation/pages/ai_page.dart`. `StaffRole` is already passed into that composition as `staffIsAdministrator`. No new library.

**Storage**: N/A. The desktop does not store coverage and does not write it.

**Testing**: Harness H-FL. One widget file with fake ports, composed from `AiFeatureHostPage` in the app shell. No `integration_test/` driver (OQ-6). Titles start with the E2E id (rule V3). The seven tests are written to fail before the production changes.

**Target Platform**: Flutter desktop. Denial codes arrive on the existing `POST /v1/requests` path. Live allowance arrives on `GET /v1/coverage`.

**Project Type**: Frontend. The unit row names no wiring exception. H-FL widget scenarios live under `frontend/test/widget/`. This unit does not change `e2e/fullstack/`.

**Performance Goals**: One coverage read for an administrator session on the live host. A staff session performs no coverage read and no usage read. A coverage-code denial uses the status reader the live composition already uses.

**Constraints**: Denials stay inline in `AiDegradedView`. The renew or buy control is visible and does not navigate, mint a token, or call billing. `frontend/lib/core/ai/usage_summary_client.dart` is the only `/v1/coverage` client. `AiFeatureHostPage` calls it only when `staffIsAdministrator` is true and does not call `/v1/usage`. No second coverage client and no second scheduler. `GET /v1/coverage` stays `role = administrator` on the platform (TB-3); this desktop enforces that by not calling it for staff. The request keeps `Aip-Contract-Version` set to `platformClinic`, which 04 §4.2 requires on every clinic route. Billing screens, checkout, and the subscription page stay with P6.3 and P6.4.

**Scale/Scope**: Size M (rule S3: two user stories, one codebase, seven E2E ids). Implied task count is 21 (the sequencing below).

The coverage body this client reads is the live snapshot 04 §4.2 names, plus `subscription_ref`. Snapshot fields used here are the ones in 04 §1.7: `term.allowance`, `term.used`, and `term.plan_display_name`. `queued_terms` and `recent_terms` are the queued-terms and last-12-terms lists on that same response. The gauge shows `term.used` against `term.allowance`. The administrator `suspended` state shows `subscription_ref`. The administrator `forbidden_capability` state shows `term.plan_display_name`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). Spikes are none, so there is no `research.md`. Freezes are none and the spec defines no entities, so there is no `contracts/` directory and no `data-model.md`. The same boxes hold after this plan. This unit adds no constitution violation, so Complexity Tracking stays empty.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  A staff member who is denied AI sees an inline sentence and is told to contact the administrator, with no purchase action. An administrator sees renew or buy, "Contact support" with the subscription reference, the plan name when the capability is forbidden, and a gauge of live allowance (spec §4.1, 02 §7 principle I).

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The change is the Flutter desktop. No new worker, queue, or service (02 §7 principle I).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Flutter owns the denial taxonomy, `AiDegradedView`, the status refresh the live composition already triggers, and the administrator `/v1/coverage` client and gauge. The platform remains the source of the denial codes and of the coverage snapshot. The desktop does not grant, write coverage, or decide admission (spec §4.1, 02 §7 principle II).

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit defines no tables, RPCs, or writes. Staff sessions do not call `/v1/coverage` or `/v1/usage` (spec §4.1, 02 §7 principle III).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  `/v1/coverage` is read-only and is called only for an administrator. The `suspended` denial shows `subscription_ref` to that administrator. The desktop does not delete anything (spec §4.1, TB-3, 02 §7 principle IV).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  `coverage_unknown`, network failure, and `status_stale` show the inline state "AI service unreachable". Safety limits show "AI busy, try again shortly" with `retry_after`. None of these states is a dialog (spec §4.1, 02 §7 principle V).

| Principle or rule | How this unit complies |
| --- | --- |
| I. Product fit and simplicity | Inline denial sentences and one administrator gauge on the existing desktop host. |
| II. Replaceable layer boundaries | Codebase is frontend. The platform remains the source of denial codes and of the coverage snapshot. |
| III. Backend authority and data integrity | No tables, RPCs, or writes. The gauge displays the snapshot it is given. |
| IV. Secure and human-gated operations | Staff sessions do not call `/v1/coverage`. The route stays administrator-only at the platform (TB-3). |
| V. Operational continuity | Unreachable and safety-limit states stay inline. Clinical work is not blocked by a dialog. |
| Workflow automation | Status refresh after a coverage-code denial uses the existing app-shell reader. No second scheduler. |
| Higher operational burden | No new operational part. Widget scenarios extend harness H-FL. |

## Project Structure

### Documentation (this feature)

```text
specs/090-abo-p6-2-desktop-denial-states-administrator-coverage/
├── plan.md
├── spec.md
└── quickstart.md          # after this unit's H-FL tests are green; outline below
```

`research.md` is omitted. Spikes are none. `data-model.md` is omitted. The spec defines no entities. `contracts/` is omitted. Freezes are none.

`quickstart.md` is not written in this phase. After the harness is green, implement fills only these sections:

- What was implemented, and the files added or modified
- Harness command for this unit's tests only, from `frontend/`:
  - `flutter test test/widget/ai/denial_states_coverage_gauge_test.dart`
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- Manual steps only if the harness cannot see the behaviour (none are expected)

### Source Code (repository root)

```text
frontend/lib/core/ai/taxonomy.dart
frontend/lib/core/ai/ports.dart
frontend/lib/core/ai/https_submit_port.dart
frontend/lib/core/ai/usage_summary_client.dart
frontend/lib/features/ai/degraded/ai_degraded_mode.dart
frontend/lib/features/ai/degraded/ai_degraded_view.dart
frontend/lib/features/ai/host/ai_feature_host_page.dart
frontend/lib/features/ai/surface/first_ai_feature_surface.dart
frontend/lib/features/ai/presentation/pages/ai_page.dart
frontend/lib/features/ai/surface/usage_gauge.dart
frontend/test/widget/ai/denial_states_coverage_gauge_test.dart
frontend/test/widget/ai/ai_surface_test_harness.dart
frontend/test/widget/ai/usage_gauge_test.dart
frontend/test/widget/ai/ai_degraded_mode_test.dart
```

**Structure Decision**: Frontend only. The app shell route in `frontend/lib/app/router.dart` already builds `AiPage`, which composes `AiFeatureHostPage`. This unit does not change the router. Widget scenarios use fake ports through `buildLiveVisitSummaryComposition`. `UsageGauge` stays the existing widget; the host feeds it from the coverage client and shows it only to an administrator. Platform removal of `GET /v1/usage` stays with P3.9.

## Consumes Binding

None. The unit contract's Consumes cell is none. P6.1 freezes nothing for this unit.

## Files

| Path | Action | FR |
| --- | --- | --- |
| `frontend/lib/core/ai/taxonomy.dart` | Modify. Recognize `allowance_exhausted` (HTTP 403), `coverage_lapsed` (HTTP 403, `coverage_reason`), `coverage_unknown` (HTTP 503, `retry_after`), `suspended` (HTTP 403), `concurrency_limited` (HTTP 429, `retry_after`), `rate_limited` (HTTP 429, `retry_after`), and `contract_version_unsupported` (HTTP 400, `accepted_versions`). Keep the existing codes. A helper returns the code only when the HTTP status matches that row, and carries the named extra fields | FR-001, FR-002 |
| `frontend/lib/features/ai/degraded/ai_degraded_mode.dart` | Modify. `resolveDegradedMode` maps those codes onto the FR-65 classes. `status_stale` and a network failure map to the same unreachable class as `coverage_unknown`. `contract_version_unsupported` maps to the existing app-update mode | FR-001, FR-002 |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | Modify. Inline column only. Staff and administrator sentences are the denial-table sentences. `concurrency_limited` and `rate_limited` include `retry_after`. The administrator lapsed and exhausted states show a renew or buy control with an empty `onPressed`. The administrator `suspended` state shows "Contact support" and the subscription reference. The administrator `forbidden_capability` state shows the plan name. `capability_disabled` and `provider_unavailable` use "AI temporarily unavailable" | FR-001, FR-002, FR-005 |
| `frontend/lib/core/ai/ports.dart` | Modify. `PlatformHttpException` carries the extra fields the taxonomy recognized (`retry_after`, `coverage_reason`, `accepted_versions`) | FR-002 |
| `frontend/lib/core/ai/https_submit_port.dart` | Modify. Pre-stream denial bodies go through the taxonomy helper so the new codes and extra fields reach `PlatformHttpException`. `contract_version_unsupported` still throws `ContractVersionUnsupportedException` | FR-001, FR-002 |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | Modify. A pre-stream denial passes the taxonomy code, wire code, and extra fields to the host. `TransportRetryExhausted` tells the host this request failed on the network | FR-002, FR-003 |
| `frontend/lib/core/ai/usage_summary_client.dart` | Modify. The file becomes the `GET /v1/coverage` client. It sends `Aip-Contract-Version: platformClinic` and reads `subscription_ref`, `term.allowance`, `term.used`, and `term.plan_display_name`. It does not call `/v1/usage` | FR-004, FR-005 |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | Modify. Call the coverage client only when `staffIsAdministrator` is true, and only to fill `UsageGauge`, the subscription reference, and the plan name. Remove the `/v1/usage` fetch and the spy fixture for that path. The spy fixture, when an administrator fetch runs, returns a coverage body whose `term.used` is 42 and `term.allowance` is 10000. Pass role, `retry_after`, subscription reference, and plan name into `AiDegradedView`. `allowance_exhausted` still calls the existing `onStatusRefresh` | FR-002, FR-003, FR-004, FR-005 |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | Modify. `buildLiveVisitSummaryComposition` accepts the existing `UsageSummaryClient` override and places it on `AiFeatureHostDependencies` | FR-004 |
| `frontend/lib/features/ai/surface/usage_gauge.dart` | Unchanged widget. The host supplies `term.used` as credits used and `term.allowance` as the budget, and builds it only for an administrator | FR-004, FR-005 |
| `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart` | Create. Seven tests, titles prefixed `E2E-P6.2-01` through `E2E-P6.2-07` | FR-001, FR-002, FR-003, FR-004, FR-005 |
| `frontend/test/widget/ai/ai_surface_test_harness.dart` | Modify. `hostDependencies` accepts `staffIsAdministrator` so the existing gauge test can open an administrator session | FR-004 |
| `frontend/test/widget/ai/usage_gauge_test.dart` | Modify. The ready-host gauge test sets `staffIsAdministrator` and still expects 42 and 10000. The non-enrolled test still sees no `/v1/usage` call | FR-004, FR-005 |
| `frontend/test/widget/ai/ai_degraded_mode_test.dart` | Modify. The provider-unavailable sentence expectation is "AI temporarily unavailable". The retry key stays | FR-002 |
| `specs/090-abo-p6-2-desktop-denial-states-administrator-coverage/quickstart.md` | Create after this unit's H-FL tests are green | FR-001, FR-004 |

`frontend/lib/app/router.dart` already builds `AiPage` at the AI route. It is the shell entry the tests compose through `buildLiveVisitSummaryComposition`. This unit does not change it.

## Test Layout

Harness H-FL. One widget file, fake ports only, composed with `buildLiveVisitSummaryComposition` and pumped as `AiFeatureHostPage`. A row that names two triggers or two sessions asserts both inside that single test. Each new test is red before the production change it names. No `integration_test/` driver.

| ID | Title prefix | Entry → chain | Assertion |
| --- | --- | --- | --- |
| E2E-P6.2-01 | `E2E-P6.2-01` | `buildLiveVisitSummaryComposition` → `AiFeatureHostPage` → fake submit port → `resolveDegradedMode` → `AiDegradedView` | `coverage_lapsed` shows staff "AI not available, contact your administrator" and no renew or buy control. The administrator session shows that sentence and a renew or buy control. No dialog in either session |
| E2E-P6.2-02 | `E2E-P6.2-02` | The same host. `allowance_exhausted` → `AiDegradedView` and `onStatusRefresh` | Staff see "AI not available, contact your administrator". The administrator sees the renew or buy control. The status refresh callback runs |
| E2E-P6.2-03 | `E2E-P6.2-03` | The same host, with the coverage client returning `subscription_ref` | `suspended`: staff see "AI not available, contact your administrator". The administrator sees "Contact support" and that subscription reference |
| E2E-P6.2-04 | `E2E-P6.2-04` | The same host. Fake denials carry `retry_after` | `concurrency_limited` and `rate_limited` each show "AI busy, try again shortly" and that `retry_after`, for a staff session and an administrator session |
| E2E-P6.2-05 | `E2E-P6.2-05` | The same host | `coverage_unknown` shows "AI service unreachable". A submit port that fails with `TransportFailure` until `TransportRetryExhausted` shows the same sentence. Both sessions, no dialog |
| E2E-P6.2-06 | `E2E-P6.2-06` | `UsageGauge` in `AiFeatureHostPage`, fed by `usage_summary_client.dart` | The administrator gauge shows `term.used` and `term.allowance` from `GET /v1/coverage`. The staff session records no `/v1/coverage` URL and no `/v1/usage` URL, and the gauge is absent |
| E2E-P6.2-07 | `E2E-P6.2-07` | The same host, with the coverage client returning `term.plan_display_name` | `forbidden_capability`: the administrator sees that plan name. Staff see "Not included in your clinic's AI plan" |

## Sequencing

Tests before implementation. The new tests are observed failing, then the desktop changes, then those tests pass. Implied task count: 21.

1. Add the failing `E2E-P6.2-01` widget test.
2. Add the failing `E2E-P6.2-02` widget test in the same file.
3. Add the failing `E2E-P6.2-03` widget test in the same file.
4. Add the failing `E2E-P6.2-04` widget test in the same file.
5. Add the failing `E2E-P6.2-05` widget test in the same file.
6. Add the failing `E2E-P6.2-06` widget test in the same file.
7. Add the failing `E2E-P6.2-07` widget test in the same file.
8. Run `flutter test test/widget/ai/denial_states_coverage_gauge_test.dart` from `frontend/` and confirm E2E-P6.2-01 through E2E-P6.2-07 fail.
9. Teach `taxonomy.dart` the 04 §4.2 codes, HTTP statuses, and extra fields.
10. Map those codes, `status_stale`, and network failure in `resolveDegradedMode`.
11. Render the denial-table sentences, `retry_after`, the renew or buy control, "Contact support", the subscription reference, and the plan name in `AiDegradedView`.
12. Carry the extra fields on `PlatformHttpException` from `https_submit_port.dart`.
13. Pass those fields from `FirstAiFeatureSurface` to the host, and report `TransportRetryExhausted` as a network failure.
14. Replace `fetchUsage` with `GET /v1/coverage` in `usage_summary_client.dart`.
15. On the host, call that client only for an administrator, feed `UsageGauge`, and keep the coverage-code status refresh.
16. Pass the coverage-client override through `buildLiveVisitSummaryComposition`.
17. Point the host network-spy fixture at `/v1/coverage` with `term.used` 42 and `term.allowance` 10000.
18. Update `usage_gauge_test.dart` so the ready gauge runs as an administrator, and update the provider-unavailable sentence in `ai_degraded_mode_test.dart`.
19. Re-run the new widget file until E2E-P6.2-01 through E2E-P6.2-07 pass.
20. Re-run `frontend/test/widget/ai/usage_gauge_test.dart` and `frontend/test/widget/ai/ai_degraded_mode_test.dart` so those existing expectations stay green.
21. Write `quickstart.md` from the outline in Project Structure.

## Complexity Tracking

No constitution violation is recorded in 02 §7 for this unit. Nothing to justify.
