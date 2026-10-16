# Desktop contract versions, token minting and AI status reads

**Unit**: P6.1 · **Branch**: `ai/089-abo-p6-1-desktop-contract-versions-token-minting` · **Harness**: H-FL · **Verification**: T024 (seven E2E ids)

## 1. What was implemented

The Flutter desktop keeps channel versions in `contract_versions.dart`, sends them on `get_ai_status`, `issue_ai_token`, and platform clinic routes, and renders P5.2b status and notices from the backend only. Platform and ABO workers are not started in this unit's harness.

- **Contract constants** (`frontend/lib/core/contract_versions.dart`) — Integer constants for every key of `CHANNEL_VERSIONS` in `packages/vendor-contracts/src/version.ts`. `backendRpc` is the RPC argument; `platformClinic` is the platform header value (FR-001, FR-002, FR-003).
- **Status model and reader** (`ai_availability.dart`, `ai_availability_reader.dart`) — `read` calls PostgREST `get_ai_status` with `p_contract_version` set to `backendRpc`, parses the P5.2b payload, and maps `CONTRACT_VERSION_UNSUPPORTED` to the inline update state (FR-002, FR-004, FR-007).
- **Versioned mint** (`supabase_aat_mint_port.dart`) — `mint` calls `issue_ai_token` with `p_contract_version` set to `backendRpc` (FR-002, FR-007).
- **Platform headers** (`discovery_client.dart`, `https_submit_port.dart`, `usage_summary_client.dart`) — `Aip-Contract-Version` set to `platformClinic` on `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/usage` before the request body (FR-003, FR-005, FR-007).
- **App-shell refresh** (`app.dart`, `ai_page.dart`) — One refresh function on open, resume, `next_change_at`, every 5 minutes, and after a coverage-code denial (`allowance_exhausted`, `coverage_lapsed`, `coverage_unknown`); contacts the backend only (FR-005, FR-006).
- **Notice forms and host gate** (`ai_feature_host_page.dart`) — Renders `notices[]` with staff "ask your administrator" form and administrator renew control; `available` drives the gate (FR-004, FR-006).
- **Update copy** (`ai_degraded_view.dart`) — `AiDegradedMode.appUpdate` reads "Update the app to use AI" inline, no dialog (FR-007).
- **CI** (`.github/workflows/ci.yml`) — Job `frontend-fullstack` starts local Supabase and runs `flutter test --tags fullstack` (FR-008).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `frontend/lib/core/contract_versions.dart` | FR-001, FR-002, FR-003 |
| `frontend/lib/features/ai/availability/ai_availability.dart` | FR-004, FR-006 |
| `frontend/lib/features/ai/availability/ai_availability_reader.dart` | FR-002, FR-004, FR-007 |
| `frontend/lib/core/ai/supabase_aat_mint_port.dart` | FR-002, FR-007 |
| `frontend/lib/core/ai/discovery_client.dart` | FR-003, FR-007 |
| `frontend/lib/core/ai/https_submit_port.dart` | FR-003, FR-005, FR-007 |
| `frontend/lib/core/ai/usage_summary_client.dart` | FR-003 |
| `frontend/lib/app/app.dart` | FR-005 |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | FR-005, FR-006 |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | FR-004, FR-005, FR-006, FR-007 |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | FR-007 |
| `frontend/test/widget/ai/ai_degraded_mode_test.dart` | FR-007 |
| `frontend/test/integration/contract_versions_test.dart` | FR-001, FR-008 |
| `frontend/test/integration/ai_status_fullstack_test.dart` | FR-002, FR-004, FR-008 |
| `frontend/test/widget/ai/ai_status_refresh_test.dart` | FR-005, FR-008 |
| `frontend/test/widget/ai/ai_status_notices_test.dart` | FR-006, FR-008 |
| `frontend/test/widget/ai/ai_contract_version_state_test.dart` | FR-002, FR-003, FR-007, FR-008 |
| `frontend/dart_test.yaml` | FR-008 |
| `.github/workflows/ci.yml` | FR-008 |
| `specs/089-abo-p6-1-desktop-contract-versions-token-minting/quickstart.md` | FR-001, FR-008 |

## 3. Harness commands for this unit's tests only

From `frontend/`:

```bash
flutter test test/integration/contract_versions_test.dart test/widget/ai/ai_status_refresh_test.dart test/widget/ai/ai_status_notices_test.dart test/widget/ai/ai_contract_version_state_test.dart
```

With local Supabase already started:

```bash
flutter test --tags fullstack test/integration/ai_status_fullstack_test.dart
```

## 4. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P6.1-01 | `AiPage` / `buildLiveVisitSummaryComposition` → `SupabaseAiAvailabilityReader.read` → PostgREST `get_ai_status` |
| E2E-P6.1-02 | `AiClinicApp.didChangeAppLifecycleState` and the `next_change_at` timer in `frontend/lib/app/app.dart` → the one refresh → `SupabaseAiAvailabilityReader.read` |
| E2E-P6.1-03 | `AiPage` live surface (`liveVisitSummaryHostBody` / `AiFeatureHostPage`) rendering `notices[]` from the status reader |
| E2E-P6.1-04 | The same live surface, rendering `allowance_low` |
| E2E-P6.1-05 | Live surface → `SupabaseAiAvailabilityReader.read` and `SupabaseAatMintPort.mint` against a fake RPC |
| E2E-P6.1-06 | `buildLiveVisitSummaryComposition` → `DiscoveryClient.fetchCapabilities`, `SupabaseAatMintPort.mint`, and `PlatformHttpsSubmitPort.submit` |
| E2E-P6.1-07 | `frontend/test/integration/contract_versions_test.dart` reads `frontend/lib/core/contract_versions.dart` and `packages/vendor-contracts/src/version.ts` |
