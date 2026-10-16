# Feature Specification: Clean-up of dependent paths and the `/control` residue guard

**Feature Branch**: `ai/093-abo-p7-1-clean-up-dependent-paths-control-residue`

**Created**: 2026-10-08

**Status**: Draft

**Input**: P7.1 — Clean-up of dependent paths and the `/control` residue guard

## 1. Unit Contract

**Implements** — Read: 04 §6.6; 05 §6.2 (second bullet).

- remove the viewer's control pages and its catalog operations that use `/control/*`; viewer clinic pages use issuer tokens (test issuer key) and send `Aip-Contract-Version`; delete `bootstrap-routing-policy.sh`; mark superseded parts of `docs/architecture/ai-platform/` and `docs/testing/catalog/` with links to the v2 design (rule V2); CI residue guard failing on `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, `installation_key` outside migrations.

**Freezes** — None. The P7.1 unit row has no Outputs / freezes line.

**Consumes** — None. P3.10 and P4.9 publish no Outputs / freezes line.

**Open questions relied on** — None.

**Spikes** — None.

## Clarifications

### Session 2026-10-08

- Q: Where does the residue guard live, and which paths does "outside migrations" skip? → A: One new CI job runs a checked-in shell script over the four dependent-path trees (`ai-platform-viewer/`, `ai-platform/scripts/`, `docs/architecture/ai-platform/`, `docs/testing/catalog/`), skips any path with a `migrations` directory segment, and treats each needle as a literal substring. The script lives with the CI job, outside those four trees. `[implementation choice — no §citation]`
- Q: How can a negative fixture containing `/control/` fail the guard while the tree scan passes? → A: The same job writes a temporary fixture and runs the guard on that fixture alone. The fixture is not committed into the scanned trees. `[implementation choice — no §citation]`
- Q: A literal scan of the tracked tree still hits `specs/`, `ai-platform/` outside `scripts/`, other docs including `docs/architecture/ai-billing-orchestration/` (01–06), `backend/` tests, and `frontend/`. Those paths are outside the trees this unit may change. Which of them may still contain `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, and `installation_key`, or is the scan limited to the named trees? → A: The scan is limited to the four dependent-path trees. `specs/`, `ai-platform/` outside `scripts/`, every other docs tree including `docs/architecture/ai-billing-orchestration/` (01–06), `backend/` (tests included), and `frontend/` may still contain those five needles and are not scanned. (04 §6.6, rule V2, rule V7, 05 §6.2 second bullet)

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1)

The viewer, against the local platform, opens its capabilities and request pages with issuer tokens from the test issuer key and sends `Aip-Contract-Version`. Its control pages and catalog operations that use `/control/*` are removed. The viewer build contains no control routes, and the viewer smoke tests pass without a bearer token.

**Why this priority**: User Story 2's residue guard passes only after these viewer paths no longer point at `/control/*` or the shared bearer. This is the story User Story 2 depends on.

**Independent Test**: E2E-P7.1-01 and E2E-P7.1-03. Viewer catalog smoke tests against the local platform (`ai-platform-viewer/`, rule V2).

**Acceptance Scenarios**:

1. **Given** the viewer against the local platform, **When** the capabilities and request pages run, **Then** those clinic-route pages work with issuer tokens (test issuer key) and send `Aip-Contract-Version`. (E2E-P7.1-01, 04 §6.6)
2. **Given** the viewer build, **When** it is inspected, **Then** it contains no control routes. **Given** the viewer smoke tests, **When** they run, **Then** they pass without a bearer token. (E2E-P7.1-03, 04 §6.6)

### 2.2 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2)

`ai-platform/scripts/bootstrap-routing-policy.sh` is deleted. Superseded parts of `docs/architecture/ai-platform/` and `docs/testing/catalog/` are rewritten to entrypoint terms, with links to the v2 design, so those pages no longer contain the guard's needles. The CI residue guard passes on the four dependent-path trees and fails a negative fixture that contains `/control/`.

**Why this priority**: This story uses the viewer clean-up from User Story 1. The guard is the check that the dependent paths this unit owns no longer point at the removed control path.

**Independent Test**: E2E-P7.1-02 in the CI residue guard (rule V7). Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** the four dependent-path trees, **When** the CI residue guard runs, **Then** it passes. **Given** a negative fixture containing `/control/`, **When** the guard runs on that fixture, **Then** it fails. (E2E-P7.1-02) [FR-91]

### 2.3 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P7.1-01 | Viewer catalog smoke tests against the local platform (`ai-platform-viewer/`, rule V2) | Capabilities page `Stage7DiscoveryPage` and request pages `Stage8IngressPage`, `Stage9GuardPage`, `Stage10StreamPage`, `Stage11SettlementPage`, and `Stage12LookupSupportPage`, composed in `AppShell` (`ai-platform-viewer/src/components/AppShell.tsx`). Capabilities: `/stage-7`, `GET /v1/capabilities` (`ai-platform-viewer/src/catalog/stage-7-discovery.ts`, `ai-platform-viewer/src/lib/gateway-api.ts`). Requests: `/v1/requests` and `/v1/requests/{request_reference}` from those pages' catalogs | Viewer against the local platform: capabilities and request pages work with issuer tokens | FR-002 | User Story 1 |
| E2E-P7.1-02 | CI residue guard (rule V7) | The CI residue guard. A negative fixture containing `/control/` | The residue guard passes; a negative fixture containing `/control/` fails it [FR-91] | FR-005 | User Story 2 |
| E2E-P7.1-03 | Viewer build and viewer smoke tests (`ai-platform-viewer/`) | Viewer build of `AppShell` (`ai-platform-viewer`, `npm run build`) and viewer smoke tests under `ai-platform-viewer/test/` | The viewer build contains no control routes; viewer smoke tests pass without a bearer token | FR-001 | User Story 1 |

### 2.4 Edge Cases

- A negative fixture containing `/control/` fails the residue guard. (E2E-P7.1-02) [FR-91]
- The residue guard fails on `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, and `installation_key` inside the four dependent-path trees, skipping a `migrations` segment. Paths outside those trees may still contain the needles. (Implements, 04 §6.6)
- No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, or manual entitle path exists. (05 §6.2, second bullet) [FR-91]
- The viewer build contains no control routes. Viewer smoke tests pass without a bearer token. (E2E-P7.1-03)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The viewer's control pages and its catalog operations that use `/control/*` MUST be removed. The viewer build MUST contain no control routes. (04 §6.6, Implements, E2E-P7.1-03)
- **FR-002**: Viewer clinic-route pages MUST use issuer tokens (test issuer key) and MUST send `Aip-Contract-Version`. Against the local platform, the capabilities and request pages MUST work with those issuer tokens. (04 §6.6, Implements, E2E-P7.1-01)
- **FR-003**: `ai-platform/scripts/bootstrap-routing-policy.sh` MUST be deleted. That script seeded the routing policy through `/control/*`; the console's routing-policy action (class H) replaces it. (04 §6.6, Implements)
- **FR-004**: Superseded parts of `docs/architecture/ai-platform/` and `docs/testing/catalog/` MUST be rewritten to entrypoint terms, with links to the v2 design, so those pages no longer contain `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, or `installation_key`. `docs/testing/catalog/` stage pages that describe `/control/*` probes are in that set. (04 §6.6, Implements, rule V2)
- **FR-005**: The CI residue guard MUST fail on `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, and `installation_key` inside `ai-platform-viewer/`, `ai-platform/scripts/`, `docs/architecture/ai-platform/`, and `docs/testing/catalog/`, skipping any path with a `migrations` segment. The guard script lives with the CI job and is not one of those trees. The guard MUST pass on those four trees. A negative fixture containing `/control/` MUST fail it. Paths outside those four trees are not scanned and MAY still contain the five needles. No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, or manual entitle path exists on the dependent paths this unit owns (FR-91). (Implements, 04 §6.6, 05 §6.2 second bullet, rule V2, rule V7, E2E-P7.1-02)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: ai-platform-viewer, `ai-platform/scripts`, docs, CI. Wiring exception named in rule S3: P7.1 viewer + scripts + docs. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: Clinic AI pages in the viewer call the local platform with issuer tokens and `Aip-Contract-Version`. The shared bearer and `/control/*` pages are removed. This stays a clinic-scale viewer, script, docs, and CI clean-up.
- **Layer Placement**: The viewer owns the remaining clinic-route pages and drops its control pages and `/control/*` catalog operations. `ai-platform/scripts` loses `bootstrap-routing-policy.sh`. Docs mark superseded platform and catalog pages. CI owns the residue guard. This unit adds no Flutter, Supabase, or PostgreSQL behavior.
- **Data Integrity & Security**: This unit defines no tables, constraints, RLS policies, or RPCs. The residue guard fails on `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, and `installation_key` inside the four dependent-path trees, outside a `migrations` segment. Viewer smoke tests pass without a bearer token. Clinic-route pages use issuer tokens (test issuer key).
- **Failure Handling**: A negative fixture containing `/control/` fails the residue guard (E2E-P7.1-02, FR-91).

## 5. Out of Scope

- The unit row states no Out of scope list.
- No Do-not-read material. The unit row names none. The cited 04 §6.6 span is "Other affected paths". The cited 05 §6.2 span is the second bullet.
- No Consumes rewrite. P3.10 and P4.9 publish no Outputs / freezes line.
- No module this unit's E2E scenarios do not reach (rule S8). The P2.2 and package-half P2.1 exception does not apply. Viewer clinic pages are reached from `AppShell`. The residue guard is reached by the CI job (rule V7). Script deletion and the superseded docs are reached by that guard, which fails on the named strings inside the four dependent-path trees.
- No S9 path owned by a later unit. This unit names no transitional path.
- No second codebase beyond ai-platform-viewer, `ai-platform/scripts`, docs, and CI. The S3 wiring exception is viewer + scripts + docs.
- `frontend/` AI and billing clients stay with P6.x (04 §6.6 frontend row; section 5, D1). This unit does not send channel versions from the desktop or render `contract_version_unsupported` there.
- The ABO console that replaces the viewer's control pages, including the class-H routing-policy action that replaces `bootstrap-routing-policy.sh`, stays with P4.9. This unit deletes the script and the viewer control pages.
- Platform removal of `/control/*`, `OPERATOR_BEARER_TOKEN`, and the harness migration stay with P3.10 (rule V2 steps through step 4). This unit migrates the viewer and `docs/testing/catalog/` (rule V2) and adds the residue guard (rule V7).
- Launch-checklist ownership of 05 §6.2 stays with P8.3. This unit implements the second bullet through the residue guard and the dependent-path clean-up.
- The residue guard does not scan `specs/`, `ai-platform/` outside `scripts/`, docs other than `docs/architecture/ai-platform/` and `docs/testing/catalog/` (including `docs/architecture/ai-billing-orchestration/` 01–06), `backend/`, or `frontend/`. Those paths may still contain the five needles. Platform source stays with P3.10, the backend drops of `installation_keys` and `set_ai_availability` stay with P5.1 and P5.2a, and the frontend row of 04 §6.6 stays with P6.x.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P7.1-01, E2E-P7.1-02, and E2E-P7.1-03 are green in the harnesses named in the test plan.
- **SC-002**: Every earlier suite stays green (rule S2). Existing platform and frontend jobs stay green (rule V7).

## 7. Assumptions

- This unit relies on no §6 default. Its Read and Implements lines name none.
- Rule S9: this unit names no transitional path. Viewer control pages, `docs/testing/catalog/` stage pages that describe `/control/*` probes, and `bootstrap-routing-policy.sh` are removed or rewritten in this unit.
- The residue guard scans only `ai-platform-viewer/`, `ai-platform/scripts/`, `docs/architecture/ai-platform/`, and `docs/testing/catalog/`. It skips a `migrations` path segment inside those trees. The checked-in script lives with the CI job, outside those trees, so the needles it lists are not residue. `specs/`, `ai-platform/` outside `scripts/`, other docs including `docs/architecture/ai-billing-orchestration/` (01–06), `backend/` tests, and `frontend/` may still contain `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, and `installation_key`.
