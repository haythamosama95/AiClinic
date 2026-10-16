# Desktop denial states and the administrator coverage view

**Unit**: P6.2 · **Branch**: `ai/090-abo-p6-2-desktop-denial-states-administrator-coverage` · **Harness**: H-FL · **Verification**: T021 (seven E2E ids)

## 1. What was implemented

The Flutter desktop host shows each platform denial as an inline `AiDegradedView` state with role-specific sentences from the denial table. Administrators see a live allowance gauge fed by `GET /v1/coverage`; staff sessions do not call `/v1/coverage` or `/v1/usage`.

- **Denial taxonomy** (`taxonomy.dart`) — Recognizes 04 §4.2 pre-stream denial codes with HTTP status matching and extra fields (`retry_after`, `coverage_reason`, `accepted_versions`) (FR-001, FR-002).
- **Degraded mode mapping** (`ai_degraded_mode.dart`) — Maps denial codes, `status_stale`, and network failure onto FR-65 classes; `contract_version_unsupported` maps to app-update mode (FR-001, FR-002).
- **Inline denial view** (`ai_degraded_view.dart`) — Staff and administrator denial-table sentences; `retry_after` on safety-limit states; renew or buy control for lapsed/exhausted administrators; "Contact support" with subscription reference; plan name for forbidden capability (FR-001, FR-002, FR-005).
- **Exception extra fields** (`ports.dart`, `https_submit_port.dart`) — `PlatformHttpException` carries taxonomy extra fields from pre-stream denial bodies (FR-002).
- **Surface handoff** (`first_ai_feature_surface.dart`) — Passes taxonomy code, wire code, and extra fields to the host; `TransportRetryExhausted` reports network failure (FR-002, FR-003).
- **Coverage client** (`usage_summary_client.dart`) — Sole `GET /v1/coverage` client; reads `subscription_ref`, `term.used`, `term.allowance`, and `term.plan_display_name` (FR-004, FR-005).
- **Administrator host** (`ai_feature_host_page.dart`) — Calls coverage client only when `staffIsAdministrator` is true; feeds `UsageGauge`, subscription reference, and plan name; `allowance_exhausted` still triggers status refresh (FR-002, FR-003, FR-004, FR-005).
- **Composition seam** (`ai_page.dart`) — `buildLiveVisitSummaryComposition` accepts a `UsageSummaryClient` override for widget scenarios (FR-004).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `frontend/lib/core/ai/taxonomy.dart` | FR-001, FR-002 |
| `frontend/lib/features/ai/degraded/ai_degraded_mode.dart` | FR-001, FR-002 |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | FR-001, FR-002, FR-005 |
| `frontend/lib/core/ai/ports.dart` | FR-002 |
| `frontend/lib/core/ai/https_submit_port.dart` | FR-001, FR-002 |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | FR-002, FR-003 |
| `frontend/lib/core/ai/usage_summary_client.dart` | FR-004, FR-005 |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | FR-002, FR-003, FR-004, FR-005 |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | FR-004 |
| `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart` | FR-001, FR-002, FR-003, FR-004, FR-005 |
| `frontend/test/widget/ai/ai_surface_test_harness.dart` | FR-004 |
| `frontend/test/widget/ai/usage_gauge_test.dart` | FR-004, FR-005 |
| `frontend/test/widget/ai/ai_degraded_mode_test.dart` | FR-002 |
| `specs/090-abo-p6-2-desktop-denial-states-administrator-coverage/quickstart.md` | FR-001, FR-004 |

## 3. Harness command for this unit's tests only

From `frontend/`:

```bash
flutter test test/widget/ai/denial_states_coverage_gauge_test.dart
```

## 4. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P6.2-01 | `buildLiveVisitSummaryComposition` → `AiFeatureHostPage` → fake submit port → `resolveDegradedMode` → `AiDegradedView` |
| E2E-P6.2-02 | The same host. `allowance_exhausted` → `AiDegradedView` and `onStatusRefresh` |
| E2E-P6.2-03 | The same host, with the coverage client returning `subscription_ref` |
| E2E-P6.2-04 | The same host. Fake denials carry `retry_after` |
| E2E-P6.2-05 | The same host |
| E2E-P6.2-06 | `UsageGauge` in `AiFeatureHostPage`, fed by `usage_summary_client.dart` |
| E2E-P6.2-07 | The same host, with the coverage client returning `term.plan_display_name` |
