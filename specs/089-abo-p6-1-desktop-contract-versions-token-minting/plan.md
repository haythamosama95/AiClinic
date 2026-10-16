# Implementation Plan: Desktop contract versions, token minting and AI status reads

**Branch**: `ai/089-abo-p6-1-desktop-contract-versions-token-minting` | **Date**: 2026-10-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/089-abo-p6-1-desktop-contract-versions-token-minting/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

The desktop keeps channel versions in `frontend/lib/core/contract_versions.dart`, sends them on `get_ai_status` and `issue_ai_token` and on platform clinic routes, and renders P5.2b status and notices from the backend only. This is phase P6, size M, and **Depends** P5.2b.

## Technical Context

**Language/Version**: Dart / Flutter stable. Desktop app in `frontend/`.

**Primary Dependencies**: Existing `supabase_flutter` client, existing `package:http` client, `StaffRole` on `AuthSessionContext.staffProfile` (`frontend/lib/features/auth/domain/auth_session.dart`). Channel integers are the `CHANNEL_VERSIONS` object in `packages/vendor-contracts/src/version.ts` (`backendRpc`, `platformClinic`, and the other keys in that object). No new library.

**Storage**: N/A. The desktop does not store coverage. It reads `public.get_ai_status(integer)` and calls `public.issue_ai_token(integer)`.

**Testing**: Harness H-FL. Dart contract test and widget scenarios run under the existing frontend test job. One Dart test tagged `fullstack` runs against H-FS (local Supabase). No `integration_test/` driver (OQ-6). Titles start with the E2E id (rule V3). Tests are written to fail before the production changes.

**Target Platform**: Flutter desktop. Clinic status and mint go through Supabase PostgREST. Platform clinic routes are the existing `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/usage` clients.

**Project Type**: Frontend. The unit row names no wiring exception. H-FS (`e2e/fullstack/`) is the stack the `fullstack` tag runs against (06 §3 V1). This unit does not change that package.

**Performance Goals**: One status read on open, on resume, after a coverage-code denial, at `next_change_at`, and every 5 minutes. Those reads contact only the backend.

**Constraints**: One status reader (`SupabaseAiAvailabilityReader`) and one scheduler, both the existing app-shell path in `frontend/lib/app/app.dart`. No second status client. `p_contract_version` is the `backendRpc` constant and is the first RPC argument on `get_ai_status` and `issue_ai_token`. `Aip-Contract-Version` is the `platformClinic` constant, set on the request before the body of a stream. A coverage code is `allowance_exhausted`, `coverage_lapsed`, or `coverage_unknown` (`escalations.md`; 04 §3.4). The desktop renders notice records it is given and does not compute the `ends_soon` threshold. The administrator renew control is visible and does not navigate, mint, or call billing. `get_ai_billing_status`, the ABO API, and `/v1/coverage` are not added. `get_ai_availability` is not kept.

**Scale/Scope**: Size M (rule S3: two user stories, one codebase, seven E2E ids). Implied task count is 24 (the sequencing below).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). Spikes are none, so there is no `research.md`. Freezes are none and the spec defines no entities, so there is no `contracts/` directory and no `data-model.md`. The same boxes hold after this plan. This unit adds no constitution violation, so Complexity Tracking stays empty.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  A clinic member sees whether AI is active, and sees staff notices that say to ask the administrator. An administrator sees an unwired renew control. An unsupported contract asks the member to update the app (spec §4.1, 02 §7 principle I).

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The change is the Flutter app plus one CI job that runs the existing Flutter tests against local Supabase. No new worker, queue, or service (02 §7 principle I).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Flutter owns presentation, refresh, token minting, and the version header and RPC argument. Status results and notice codes stay the P5.2b RPCs, reached through Supabase. The desktop does not recompute coverage (spec §4.1, 02 §7 principle II).

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  The desktop sends `p_contract_version` and `Aip-Contract-Version` and renders the RPC result. It does not write coverage. `issue_ai_token` and `get_ai_status` remain the existing `SECURITY DEFINER` functions (spec §4.1, 02 §7 principle III).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  Status and mint run as the signed-in member. Staff notice forms show no prices, payments, or references. This unit deletes nothing (spec §4.1, 02 §7 principle IV).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  An unsupported contract version becomes the inline "Update the app to use AI" state and does not open a dialog or continue into an authenticated write. Clinical work stays available through the existing inline degraded surface (spec §4.1, 02 §7 principle V).

| Principle or rule | How this unit complies |
| --- | --- |
| I. Product fit and simplicity | Desktop status, notices, and an update state on the existing app. No second deployable. |
| II. Replaceable layer boundaries | Codebase is frontend. PostgreSQL RPCs and the package constants are consumed, not rewritten. |
| III. Backend authority and data integrity | Coverage and notice codes stay in `public.get_ai_status`. The desktop displays that payload. |
| IV. Secure and human-gated operations | Calls use the member session. The version check is the existing RPC and platform refusal, shown inline. |
| V. Operational continuity | Status refresh contacts only the backend. The update state does not block clinical screens. |
| Workflow automation | The refresh is one timer in the app shell: open, resume, `next_change_at`, and every 5 minutes. No DAG. |
| Higher operational burden | No new operational part. The CI job runs the Flutter `fullstack` tag against H-FS, which 06 §3 V7 assigns to this unit. |

## Project Structure

### Documentation (this feature)

```text
specs/089-abo-p6-1-desktop-contract-versions-token-minting/
├── plan.md
├── spec.md
├── escalations.md
└── quickstart.md          # after this unit's H-FL tests are green; outline below
```

`research.md` is omitted. Spikes are none. `data-model.md` is omitted. The spec defines no entities. `contracts/` is omitted. Freezes are none.

`quickstart.md` is not written in this phase. After the harness is green, implement fills only these sections:

- What was implemented, and the files added or modified
- Harness commands for this unit's tests only, from `frontend/`:
  - `flutter test test/integration/contract_versions_test.dart test/widget/ai/ai_status_refresh_test.dart test/widget/ai/ai_status_notices_test.dart test/widget/ai/ai_contract_version_state_test.dart`
  - with local Supabase already started: `flutter test --tags fullstack test/integration/ai_status_fullstack_test.dart`
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- Manual steps only if the harness cannot see the behaviour (none are expected)

### Source Code (repository root)

```text
frontend/lib/core/contract_versions.dart
frontend/lib/app/app.dart
frontend/lib/core/ai/discovery_client.dart
frontend/lib/core/ai/https_submit_port.dart
frontend/lib/core/ai/supabase_aat_mint_port.dart
frontend/lib/core/ai/usage_summary_client.dart
frontend/lib/features/ai/availability/ai_availability.dart
frontend/lib/features/ai/availability/ai_availability_reader.dart
frontend/lib/features/ai/degraded/ai_degraded_view.dart
frontend/lib/features/ai/host/ai_feature_host_page.dart
frontend/lib/features/ai/presentation/pages/ai_page.dart
frontend/test/integration/contract_versions_test.dart
frontend/test/integration/ai_status_fullstack_test.dart
frontend/test/widget/ai/ai_status_refresh_test.dart
frontend/test/widget/ai/ai_status_notices_test.dart
frontend/test/widget/ai/ai_contract_version_state_test.dart
frontend/dart_test.yaml
.github/workflows/ci.yml
```

**Structure Decision**: Frontend only. The new constants module is reached by the status reader, the mint port, the platform clients, and E2E-P6.1-07. Notice rendering and the update state stay on the live AI surface `AiPage` already composes. H-FL files live under `frontend/test/integration/` and `frontend/test/widget/ai/`. The P5.2b migration and `packages/vendor-contracts/` are not modified.

## Consumes Binding

| Consumes | Existing module | This unit |
| --- | --- | --- |
| P5.2b status RPC results and notice codes | `public.get_ai_status(integer)` and `auth_internal.get_ai_status(integer)` in `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`. Success `rpc_result.data` is `available`, `state`, `reason`, `days_left`, `band`, `notices`, `next_change_at`, `as_of`, `stale`, `platform_base_url`, plus envelope `contract_version`. Each notice is `{code, audience, channel}`; `grace_days_left` is present only when `code` is `in_grace`. A missing or unsupported `p_contract_version` returns `error_code` `CONTRACT_VERSION_UNSUPPORTED` and does not call the reader | Read only. The desktop parses this payload and does not recompute notices, `days_left`, or coverage. The SQL is not modified |

`public.issue_ai_token(integer)` in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` is the existing mint the desktop already calls. This unit adds the version argument on the client. That function is not a Consumes row and is not modified. It returns `text` on success and raises `CONTRACT_VERSION_UNSUPPORTED` when `p_contract_version` is null or not `0` or `1`.

## Files

| Path | Action | FR |
| --- | --- | --- |
| `frontend/lib/core/contract_versions.dart` | Create. Integer constants for every key of `CHANNEL_VERSIONS` in `packages/vendor-contracts/src/version.ts`. `backendRpc` is the RPC argument. `platformClinic` is the platform header value | FR-001, FR-002, FR-003 |
| `frontend/lib/features/ai/availability/ai_availability.dart` | Modify. Carry the status view fields from the consumed RPC. `fromJson` sets `enrolled` from `available` so the existing gate follows `get_ai_status`. Notice records stay `{code, audience, channel}` with optional `grace_days_left` | FR-004, FR-006 |
| `frontend/lib/features/ai/availability/ai_availability_reader.dart` | Modify. `read` calls PostgREST `get_ai_status` with `p_contract_version` set to `backendRpc`, and stops calling `get_ai_availability`. Parse `rpc_result`. An `error_code` of `CONTRACT_VERSION_UNSUPPORTED` is the update state, not a dialog. A `withRpc` seam matches the existing mint port so widget tests can fake the RPC. Production still uses `SupabaseClient` | FR-002, FR-004, FR-007 |
| `frontend/lib/core/ai/supabase_aat_mint_port.dart` | Modify. `mint` calls `issue_ai_token` with `p_contract_version` set to `backendRpc` and returns the token text. `CONTRACT_VERSION_UNSUPPORTED` is the update state, not a dialog | FR-002, FR-007 |
| `frontend/lib/core/ai/discovery_client.dart` | Modify. Set `Aip-Contract-Version` to `platformClinic` on `GET /v1/capabilities` before the request is sent. HTTP 400 with body code `contract_version_unsupported` is the update state. An accepted response is the one that carries that header and `contract_version` in the JSON body | FR-003, FR-007 |
| `frontend/lib/core/ai/https_submit_port.dart` | Modify. Set `Aip-Contract-Version` to `platformClinic` on `POST /v1/requests` before the request body is assigned. Keep the response `code` string so the live surface can see `allowance_exhausted`, `coverage_lapsed`, and `coverage_unknown`. HTTP 400 `contract_version_unsupported` is the update state | FR-003, FR-005, FR-007 |
| `frontend/lib/core/ai/usage_summary_client.dart` | Modify. Set `Aip-Contract-Version` to `platformClinic` on `GET /v1/usage` before the request is sent | FR-003 |
| `frontend/lib/app/app.dart` | Modify. The existing lifecycle path calls `SupabaseAiAvailabilityReader.read` on open (after the current authenticated bootstrap), on resume (`didChangeAppLifecycleState`), at `next_change_at` from the last status, and every 5 minutes. One refresh function. Resume still reloads auth context. Expose that same function for the live composition | FR-005 |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | Modify. Pass `StaffRole.administrator` versus any other role from `authSessionProvider` into the live composition. The composition calls the app-shell refresh when it sees a coverage-code denial. It does not add a scheduler or a second reader | FR-005, FR-006 |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | Modify. The live surface renders `notices[]` from the status read. Staff form is the text "ask your administrator", with no price and no purchase control. Administrator form includes a visible renew control that has no navigation, mint, or billing call. `available` from the status read drives the existing gate. A coverage-code denial and a contract-version refusal use the shell refresh or the inline update state | FR-004, FR-005, FR-006, FR-007 |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | Modify. The existing `AiDegradedMode.appUpdate` message is "Update the app to use AI". It stays inline. No dialog | FR-007 |
| `frontend/test/widget/ai/ai_degraded_mode_test.dart` | Modify. The existing `appUpdate` text expectation uses "Update the app to use AI" | FR-007 |
| `frontend/test/integration/contract_versions_test.dart` | Create. Not tagged `fullstack` | FR-001, FR-008 |
| `frontend/test/integration/ai_status_fullstack_test.dart` | Create. Tagged `fullstack` | FR-002, FR-004, FR-008 |
| `frontend/test/widget/ai/ai_status_refresh_test.dart` | Create | FR-005, FR-008 |
| `frontend/test/widget/ai/ai_status_notices_test.dart` | Create | FR-006, FR-008 |
| `frontend/test/widget/ai/ai_contract_version_state_test.dart` | Create | FR-002, FR-003, FR-007, FR-008 |
| `frontend/dart_test.yaml` | Modify. Declare the `fullstack` tag next to `boundary` and `live` | FR-008 |
| `.github/workflows/ci.yml` | Modify. The existing `frontend-quality` test step excludes the `fullstack` tag. Add one job that starts local Supabase (`supabase start` in `backend/`) and runs `flutter test --tags fullstack` in `frontend/`. That job does not run `npm test` and does not start wrangler. The Dart test does not boot workers | FR-008 |
| `specs/089-abo-p6-1-desktop-contract-versions-token-minting/quickstart.md` | Create after this unit's H-FL tests are green | FR-001, FR-008 |

The `/health` reachability probe is not a platform clinic route and does not gain `Aip-Contract-Version`.

## Test Layout

Harness H-FL. Widget scenarios and the contract test use fake ports and the package file. E2E-P6.1-01 uses tag `fullstack` against H-FS local Supabase. Each new test is red before the production change it names. No `integration_test/` driver.

| ID | Title prefix | Entry → chain | Assertion |
| --- | --- | --- | --- |
| E2E-P6.1-01 | `E2E-P6.1-01` | `AiPage` / `buildLiveVisitSummaryComposition` → `SupabaseAiAvailabilityReader.read` → PostgREST `get_ai_status` | Staff session on local Supabase. Seed an active projection for that org the way `e2e/fullstack/test/p5-2b.test.mjs` seeds `clinic_ai_coverage`, then the production reader shows active. `rpc_result.contract_version` equals the `backendRpc` constant sent as `p_contract_version`. The composition `PlatformNetworkSpy` records no ABO host URL. The test does not start wrangler |
| E2E-P6.1-02 | `E2E-P6.1-02` | `AiClinicApp.didChangeAppLifecycleState` and the `next_change_at` timer in `frontend/lib/app/app.dart` → the one refresh → `SupabaseAiAvailabilityReader.read` | Resume and the `next_change_at` timer each call that refresh. Each refresh's network is the backend RPC only |
| E2E-P6.1-03 | `E2E-P6.1-03` | `AiPage` live surface (`liveVisitSummaryHostBody` / `AiFeatureHostPage`) rendering `notices[]` from the status reader | Fake status includes `ends_soon` with `days_left` 7, then 3, then 1. Staff sees "ask your administrator", no price text, and no purchase control. An administrator sees the renew control. The desktop does not decide the threshold |
| E2E-P6.1-04 | `E2E-P6.1-04` | The same live surface, rendering `allowance_low` | Staff sees "ask your administrator" and no price text. An administrator sees the renew control |
| E2E-P6.1-05 | `E2E-P6.1-05` | Live surface → `SupabaseAiAvailabilityReader.read` and `SupabaseAatMintPort.mint` against a fake RPC | A missing or unsupported `p_contract_version` answered as `CONTRACT_VERSION_UNSUPPORTED` shows "Update the app to use AI" inline and no dialog |
| E2E-P6.1-06 | `E2E-P6.1-06` | `buildLiveVisitSummaryComposition` → `DiscoveryClient.fetchCapabilities`, `SupabaseAatMintPort.mint`, and `PlatformHttpsSubmitPort.submit` | The discovery request and the submit request carry `Aip-Contract-Version` set to `platformClinic`. The submit header is set before the body. Mint calls `issue_ai_token` with `p_contract_version` and the fake returns token text. An accepted discovery response carries the header and `contract_version` in the JSON body. HTTP 400 `contract_version_unsupported` shows the same inline update state and no dialog |
| E2E-P6.1-07 | `E2E-P6.1-07` | `frontend/test/integration/contract_versions_test.dart` reads `frontend/lib/core/contract_versions.dart` and `packages/vendor-contracts/src/version.ts` | The test fails when any Dart constant differs from `CHANNEL_VERSIONS`, or when the Dart file is missing. It parses the package source. It does not contain a second copy of the integers. It is not tagged `fullstack` |

Widget tests for E2E-P6.1-02 pump `AiClinicApp` with the reader seam. Widget tests for E2E-P6.1-03 and E2E-P6.1-04 pump the live surface with a fake reader and a staff role, then an administrator role. E2E-P6.1-05 and E2E-P6.1-06 use the production reader, mint port, and discovery client with fake RPC and HTTP ports, composed from `buildLiveVisitSummaryComposition`.

## Sequencing

Tests before implementation. The new tests are observed failing, then the desktop changes, then those tests pass. Implied task count: 24.

1. Declare the `fullstack` tag in `frontend/dart_test.yaml`. Exclude it from the `frontend-quality` `flutter test` step so the existing job still runs widget tests and the contract test.
2. Add the failing `E2E-P6.1-07` test. It compares `contract_versions.dart` to `CHANNEL_VERSIONS` in `packages/vendor-contracts/src/version.ts` and does not hard-code the integers.
3. Add the failing `E2E-P6.1-01` test, tagged `fullstack`, against local Supabase. Do not start wrangler.
4. Add the failing `E2E-P6.1-02` widget test.
5. Add the failing `E2E-P6.1-03` widget test.
6. Add the failing `E2E-P6.1-04` widget test.
7. Add the failing `E2E-P6.1-05` widget test.
8. Add the failing `E2E-P6.1-06` widget test.
9. Run the contract and widget commands from Project Structure and confirm E2E-P6.1-02 through E2E-P6.1-07 fail. With local Supabase started, run the `fullstack` command and confirm E2E-P6.1-01 fails.
10. Add `frontend/lib/core/contract_versions.dart` with the `CHANNEL_VERSIONS` keys.
11. Extend `AiAvailability` with the status fields. `fromJson` maps `available` onto `enrolled`.
12. Point `SupabaseAiAvailabilityReader.read` at `get_ai_status` with `p_contract_version`.
13. Pass `p_contract_version` from `SupabaseAatMintPort.mint` and return the token text.
14. Send `Aip-Contract-Version` from `DiscoveryClient` before the request, and map HTTP 400 `contract_version_unsupported` to the update state.
15. Send that header from `PlatformHttpsSubmitPort` before the body, and keep the denial `code` string.
16. Send that header from `usage_summary_client.dart`.
17. In `app.dart`, call the one reader on open, on resume, at `next_change_at`, and every 5 minutes.
18. From the live composition, call that same refresh after a denial whose code is `allowance_exhausted`, `coverage_lapsed`, or `coverage_unknown`.
19. Render staff and administrator notice forms on the live surface. The renew control does not navigate, mint, or call billing.
20. Set the `appUpdate` copy to "Update the app to use AI", and route RPC `CONTRACT_VERSION_UNSUPPORTED` and platform HTTP 400 `contract_version_unsupported` to that inline state.
21. Drive the host gate from `available` on the status result. Do not call `get_ai_availability`.
22. Add the frontend CI job that starts local Supabase and runs `flutter test --tags fullstack`.
23. Re-run the two harness commands until E2E-P6.1-01 through E2E-P6.1-07 pass.
24. Write `quickstart.md` from the outline in Project Structure.

## Complexity Tracking

No constitution violation is recorded in 02 §7 for this unit. Nothing to justify.
