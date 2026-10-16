# Feature Specification: Desktop contract versions, token minting and AI status reads

**Feature Branch**: `ai/089-abo-p6-1-desktop-contract-versions-token-minting`

**Created**: 2026-10-08

**Status**: Draft

**Input**: P6.1 — Desktop contract versions, token minting and AI status reads

## 1. Unit Contract

**Implements** — Read: 04 §3.1 (intro; rows `issue_ai_token`, `get_ai_status`); 04 §3.2; 04 §3.4 (first bullet "When to read status"); 04 §3.5 row "Frontend status"; 04 §7.1 rows Desktop→RPCs and Desktop→platform; 04 §7.2 (constants bullet); 04 §6.6 row frontend.

- `lib/core/contract_versions.dart` + a contract test against the package vectors; `Aip-Contract-Version` on every platform call; `p_contract_version` on every RPC; the new `issue_ai_token` signature; `get_ai_status` replaces the availability reader; refresh on open, resume, a coverage-code denial (`allowance_exhausted`, `coverage_lapsed`, `coverage_unknown`), `next_change_at` and every 5 min, contacting the backend only; notice rendering (staff form vs administrator form with a renew action wired in P6.3); the inline "update the app" state; **H-FL** (Dart `fullstack`-tagged tests on H-FS + widget scenarios; CI job).

**Freezes** — None.

**Consumes** — P5.2b: status RPC results and notice codes (consumed by P6.x).

**Open questions relied on** — OQ-6: "Default: no `integration_test` driver; Dart client tests against H-FS plus widget scenario tests (harness H-FL)."

**Spikes** — None.

## Clarifications

### Session 2026-10-08

- Q: Where does the contract test live, and how does it compare the desktop constants to the package? → A: Put it at `frontend/test/integration/contract_versions_test.dart` and do not tag it `fullstack`. The test imports `frontend/lib/core/contract_versions.dart` and compares those constants to the package vector under `packages/vendor-contracts/`. It fails when they differ, and it does not hard-code a second copy of the numbers. `[implementation choice — no §citation]`
- Q: Where does the new Flutter `fullstack` CI job go? → A: Add one job to the existing frontend CI workflow that runs Flutter tests filtered to the `fullstack` tag against H-FS. Widget scenarios and the contract test stay on the existing frontend test job. The Dart tests do not boot workers themselves. `[implementation choice — no §citation]`
- Q: Which code owns status refresh? → A: The existing app-shell lifecycle path in `frontend/lib/app/app.dart` calls the status reader on open, on resume, at `next_change_at`, and every 5 minutes. The live AI composition uses that same refresh when it sees a coverage-code denial. Do not add a second scheduler or a second status client. `[implementation choice — no §citation]`
- Q: What does the administrator renew action do before P6.3 wires it? → A: Render it as a visible control on the administrator notice form inside the existing `AiPage` composition. The control does not navigate, mint a token, or call billing. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Desktop contract constants match the package (Priority: P1)

The desktop copy of the channel versions lives in `frontend/lib/core/contract_versions.dart`. Every later call in this unit sends that copy. A contract test fails when the copy differs from the package.

**Why this priority**: Status reads, token minting, and platform calls send these constants. They depend on this copy matching the package.

**Independent Test**: E2E-P6.1-07 in harness H-FL.

**Acceptance Scenarios**:

1. **Given** the package contract-version constants, **When** the Dart constants in `frontend/lib/core/contract_versions.dart` differ from that vector file, **Then** the contract test fails. (E2E-P6.1-07)

### 2.2 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2)

A clinic member's desktop reads `get_ai_status` from the backend, refreshes it on the stated triggers, and renders notice codes in a staff form or an administrator form. Token minting calls `issue_ai_token(p_contract_version)` and still receives the token text. Every backend RPC sends `p_contract_version`. Every platform clinic-route call sends `Aip-Contract-Version`. A missing or unsupported version on either channel is the inline update state, with no dialog.

**Why this priority**: This story uses the constants from User Story 1. The status surface, the mint, and the platform client are the live calls those constants exist to serve.

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** a staff session for a granted organisation, **When** the desktop reads status through `get_ai_status(p_contract_version)`, **Then** the status shows active, the `rpc_result` carries `contract_version` for the version the request used, and a network spy sees no call to the ABO host. (E2E-P6.1-01) [FR-61]
2. **Given** a signed-in clinic session, **When** the app resumes, and **When** the `next_change_at` timer fires, **Then** each trigger refreshes status by contacting the backend only. (E2E-P6.1-02)
3. **Given** `get_ai_status` includes `ends_soon` at 7, 3, and 1 days, **When** staff view that status, **Then** they see "ask your administrator", with no prices and no purchase action. **When** an administrator views that same notice, **Then** they see the renew action. (E2E-P6.1-03) [A28, FR-26, FR-27]
4. **Given** `get_ai_status` includes `allowance_low`, **When** staff view it, and **When** an administrator views it, **Then** each role sees that notice: staff as "ask your administrator" with no prices, and the administrator with the renew action. (E2E-P6.1-04) [A29]
5. **Given** a desktop RPC (`get_ai_status` or `issue_ai_token`) whose `p_contract_version` is missing or outside the accepted range, **When** the RPC answers `CONTRACT_VERSION_UNSUPPORTED`, **Then** the AI surface shows the inline "Update the app to use AI" state and no dialog. That refusal is before authentication and before any write. (E2E-P6.1-05) [NFR-09, FR-64]
6. **Given** a platform clinic-route call from the live desktop composition, **When** the call is sent, **Then** the request carries `Aip-Contract-Version`, sent before the first byte of a stream, and the preceding mint called `issue_ai_token(p_contract_version)` and received the token text. An accepted response carries that header and `contract_version` in the JSON body. **When** the platform answers HTTP 400 `contract_version_unsupported` for a missing or unsupported version, **Then** the desktop shows the same inline "Update the app to use AI" state and no dialog. That refusal is before authentication and before any write. (E2E-P6.1-06)

### 2.3 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P6.1-01 | H-FL, Dart `fullstack` tag on H-FS | Production `SupabaseAiAvailabilityReader.read` composed from `AiPage` / `buildLiveVisitSummaryComposition` (`frontend/lib/features/ai/presentation/pages/ai_page.dart`, `frontend/lib/features/ai/availability/ai_availability_reader.dart`), calling PostgREST `get_ai_status` for a staff session | Staff session: status via `get_ai_status` shows active for a granted org; the accepted version is echoed on `contract_version`; a network spy sees no call to the ABO host [FR-61] | FR-002, FR-004, FR-005, FR-008 | User Story 2 |
| E2E-P6.1-02 | H-FL, widget scenario with fake ports | App-shell resume at `frontend/lib/app/app.dart` (`didChangeAppLifecycleState`, the cited resume path) and the `next_change_at` timer on that same status read | App resume and the `next_change_at` timer both trigger a refresh. Each refresh contacts the backend only | FR-005, FR-008 | User Story 2 |
| E2E-P6.1-03 | H-FL, widget scenario with fake ports | The live AI surface composed in the app shell (`AiPage`), rendering `notices[]` from the status reader | A28: staff see `ends_soon` "ask your administrator" at 7, 3 and 1 days, with no prices and no purchase action; administrators see the renew action [FR-26, FR-27] | FR-006, FR-008 | User Story 2 |
| E2E-P6.1-04 | H-FL, widget scenario with fake ports | The same live AI surface, rendering `allowance_low` from the status reader | A29: `allowance_low` for staff and administrators. Staff form is "ask your administrator" with no prices; the administrator sees the renew action | FR-006, FR-008 | User Story 2 |
| E2E-P6.1-05 | H-FL, widget scenario with fake ports | `SupabaseAiAvailabilityReader.read` and `SupabaseAatMintPort.mint` (`frontend/lib/core/ai/supabase_aat_mint_port.dart`) composed from the live AI surface, against a fake RPC | RPC answers `CONTRACT_VERSION_UNSUPPORTED` → inline "Update the app to use AI", no dialog. Missing or unsupported `p_contract_version` is that refusal before authentication and before any write [NFR-09, FR-64] | FR-002, FR-007, FR-008 | User Story 2 |
| E2E-P6.1-06 | H-FL, widget scenario with fake ports | `DiscoveryClient.fetchCapabilities` (`frontend/lib/core/ai/discovery_client.dart`) and `SupabaseAatMintPort.mint`, composed from `buildLiveVisitSummaryComposition` | Platform calls carry `Aip-Contract-Version` before the first byte of a stream; an accepted response echoes the header and `contract_version` in the JSON body; mint calls `issue_ai_token(p_contract_version)` and receives the token text; a platform 400 `contract_version_unsupported` (missing or unsupported) → the same update state, before authentication and before any write | FR-002, FR-003, FR-007, FR-008 | User Story 2 |
| E2E-P6.1-07 | H-FL, Dart contract test | Dart test that compares `frontend/lib/core/contract_versions.dart` with the `packages/vendor-contracts/` vector | The contract test fails when the Dart constants differ from the vector file | FR-001, FR-008 | User Story 1 |

### 2.4 Edge Cases

- A version outside the backend's accepted range on `issue_ai_token` or `get_ai_status` answers `CONTRACT_VERSION_UNSUPPORTED`. `issue_ai_token` raises it and still returns `text` on success; the token's `ver` claim states its version. `get_ai_status` uses the `rpc_result` envelope extended with `contract_version`. (04 §3.1, E2E-P6.1-05)
- A missing version, or one the channel does not accept, is `CONTRACT_VERSION_UNSUPPORTED` on Desktop → backend RPCs and HTTP 400 `contract_version_unsupported` on Desktop → platform clinic routes. The check runs before authentication and before any write. The desktop shows the inline "Update the app to use AI" state and no dialog. (04 §7.1, 04 §6.6, 06 §3 V5, E2E-P6.1-05, E2E-P6.1-06)
- Status refresh on app open, on resume, after any AI denial with a coverage code (`allowance_exhausted`, `coverage_lapsed`, or `coverage_unknown`), at `next_change_at`, and every 5 minutes contacts only the backend. A network spy sees no call to the ABO host. E2E-P6.1-02 proves resume and `next_change_at`. (04 §3.4, E2E-P6.1-01, E2E-P6.1-02)
- `get_ai_status` returns no prices, payments, or references. Staff notice forms do not add prices or a purchase action. (04 §3.2, E2E-P6.1-01, E2E-P6.1-03)
- `ends_soon` is the notice the status RPC returns when `days_left` is 7, 3, or 1 or fewer and `queued_count = 0`. A null `days_left` does not raise it. The desktop renders the record it is given; it does not decide the threshold. (04 §3.2, E2E-P6.1-03)
- `allowance_low` is the notice the status RPC returns for band 75 or 90. Staff and administrators both see it, in the staff form or the administrator form. (04 §3.2, E2E-P6.1-04)
- Each notice is a record `{code, audience: member, channel: in_app}`. `grace_days_left` is present only when `code` is `in_grace`. The desktop renders each `code` it receives in the administrator form or the staff form, with no prices. The renew action is shown to administrators and is not wired here. (04 §3.2)
- The contract test fails when `frontend/lib/core/contract_versions.dart` differs from the package. (04 §7.2, E2E-P6.1-07)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The desktop MUST keep its contract-version constants in `frontend/lib/core/contract_versions.dart`. A contract test MUST fail if that copy differs from the package. (04 §7.2)
- **FR-002**: Every desktop call on Desktop → backend RPCs MUST pass `p_contract_version` as the first argument. `issue_ai_token(p_contract_version)` MUST keep the current name and text return, and add that version argument. Members with an AI scope receive the AI token. `get_ai_status(p_contract_version)` MUST be the status call for every member. A version outside the backend's accepted range MUST answer `CONTRACT_VERSION_UNSUPPORTED`, which `issue_ai_token` raises. A missing or unsupported version MUST be refused before authentication and before any write. An accepted `get_ai_status` result MUST carry `contract_version` for the version the request used. (04 §3.1, 04 §7.1, 06 §3 V5)
- **FR-003**: Every desktop call on Desktop → platform clinic routes MUST send `Aip-Contract-Version` on the request, before the first byte of a stream. An accepted response MUST carry that header and `contract_version` in the JSON body, in the version the request used. A missing or unsupported version MUST be HTTP 400 `contract_version_unsupported`, before authentication and before any write. (04 §7.1, 04 §6.6, 06 §3 V5)
- **FR-004**: The frontend status reader MUST call `get_ai_status` in place of `get_ai_availability`. That call returns the status view `available`, `state`, `reason`, `days_left`, `band`, `notices[]`, `next_change_at`, `as_of`, `stale`, and `platform_base_url`, with no prices, payments, or references. The desktop shows that result. (04 §3.1, 04 §3.2, 04 §3.5)
- **FR-005**: Every desktop MUST call `get_ai_status()` on app open, on resume (as `frontend/lib/app/app.dart:47-57` does today), after any AI denial with a coverage code, at `next_change_at`, and every 5 minutes. A coverage code is `allowance_exhausted`, `coverage_lapsed`, or `coverage_unknown`. Those reads MUST contact only the backend. (04 §3.4)
- **FR-006**: The desktop MUST render each notice `code` in an administrator form, with a renew action, or a staff form ("ask your administrator"), with no prices. Staff `ends_soon` MUST show that staff form at 7, 3, and 1 days, with no purchase action. Administrators MUST see the renew action for that notice. `allowance_low` MUST be shown to staff and to administrators. (04 §3.2, E2E-P6.1-03, E2E-P6.1-04)
- **FR-007**: When an RPC answers `CONTRACT_VERSION_UNSUPPORTED`, or a platform call answers HTTP 400 `contract_version_unsupported`, the desktop MUST show the inline "Update the app to use AI" state and MUST NOT show a dialog. (04 §6.6, 04 §7.1, E2E-P6.1-05, E2E-P6.1-06)
- **FR-008**: This unit MUST add harness H-FL: Dart client tests tagged `fullstack` against H-FS, widget scenario tests with fake ports, and a CI job for the Flutter `fullstack` tag. It MUST NOT add an `integration_test` desktop driver. (06 §3 V1 H-FL, 06 §3 V7, OQ-6)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: frontend. The unit row names no wiring exception. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: A clinic member sees whether AI is active, and sees staff notices that say to ask the administrator, with no prices and no purchase action. An administrator sees the renew action on those notices. The desktop asks the member to update the app before AI calls continue on an unsupported contract.
- **Layer Placement**: Flutter owns presentation, refresh, token minting, and the contract-version headers and RPC arguments. Status results and notice codes stay the consumed PostgreSQL RPCs from P5.2b, reached through Supabase. The desktop does not recompute coverage. H-FL is the harness (`frontend/test/integration/`, `frontend/test/widget/`); H-FS is the stack the `fullstack` tag runs against.
- **Data Integrity & Security**: The desktop sends `p_contract_version` and `Aip-Contract-Version` and renders the RPC result. It does not write coverage. `issue_ai_token` and `get_ai_status` remain the existing SECURITY DEFINER RPCs. Staff status shows no prices, payments, or references.
- **Failure Handling**: A missing or unsupported contract version on an RPC or a platform clinic route becomes the inline "Update the app to use AI" state, with no dialog, and does not continue into an authenticated write. Status refresh contacts only the backend. (04 §3.4, 04 §6.6, 04 §7.1, E2E-P6.1-05, E2E-P6.1-06)

## 5. Out of Scope

- No Do-not-read material. The unit row names none. The cited 04 §3.4 span is the "When to read status" bullet. The cited 04 §3.5 span is the Frontend status row. The cited 04 §7.2 span is the constants bullet.
- No rewrite of the consumed P5.2b contract: status RPC results and notice codes.
- No module this unit's E2E scenarios do not reach (rule S8). The P2.2 and package-half P2.1 exception does not apply. The status reader, the mint port, and `DiscoveryClient` are reached from the live AI composition. The constants module is reached by those calls and by E2E-P6.1-07.
- The renew action is shown to administrators. Wiring that action is P6.3, as this unit's Implements line states.
- `get_ai_billing_status()`, the ABO API, and `/v1/coverage` appear in the when-to-read bullet as additional administrator reads. They are not in this unit's Implements, and the status refresh in that bullet contacts only the backend. This unit does not add those clients.
- No S9 path owned by a later unit. This unit replaces the availability reader with `get_ai_status`. It does not keep `get_ai_availability` as a transitional path.
- No second codebase beyond frontend. H-FL's `fullstack` tag runs on H-FS (`e2e/fullstack/`), which is the harness named in 06 §3 V1, not a product codebase this unit changes.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, E2E-P6.1-06, and E2E-P6.1-07 are green in harness H-FL.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- OQ-6 default: no `integration_test` driver; Dart client tests against H-FS plus widget scenario tests (harness H-FL).
- Rule S9: this unit names no transitional path left to a later owner. The availability reader is replaced here.
