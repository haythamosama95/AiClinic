# Tasks: Clean-up of dependent paths and the `/control` residue guard

**Input**: Design documents from `specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: none. Plan artifacts from `AVAILABLE_DOCS`: none. `research.md` is omitted (no spike). `data-model.md` and `contracts/` are omitted (no entities; this unit freezes no wire shape). `quickstart.md` is written in Documentation after this unit's harness is green.

**Organization**: P7.1 is User Story 1 and User Story 2 (`[US1]`, `[US2]`), size S (rule S3). Branch `ai/093-abo-p7-1-clean-up-dependent-paths-control-residue`. E2E ids stay `E2E-P7.1-01`, `E2E-P7.1-02`, and `E2E-P7.1-03`. Tests are one task per E2E id, written before the production change they cover, plus the plan sequencing red run. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase. No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 15. Size S is 12–20 (rule S3). Plan sequencing implies 16 steps. Sequencing steps 13–15 are one verification task. Sequencing step 7 is two tasks because the stage-10 and stage-12 catalogs share no path with the clinic wording files. The count is not padded. `npm test` in `e2e/fullstack` is not a task. This unit does not boot wrangler.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Viewer**: `ai-platform-viewer/` (Vite, React, Vitest). Clinic smoke and the viewer build stay in this tree (rule V2)
- **Residue guard**: `.github/scripts/control-residue-guard.sh` and job `control-residue-guard` in `.github/workflows/ci.yml` (rule V7). The script is outside the four scanned trees
- **Scanned trees**: `ai-platform-viewer/`, `ai-platform/scripts/`, `docs/architecture/ai-platform/`, and `docs/testing/catalog/`. A `migrations` path segment inside those trees is skipped. `specs/`, `ai-platform/` outside `scripts/`, every other docs tree including `docs/architecture/ai-billing-orchestration/` (01–06), `backend/` (tests included), and `frontend/` are not scanned
- **Unchanged by this unit**: `frontend/`, `backend/`, `abo/`, `packages/vendor-contracts/`, `e2e/fullstack/`, and `ai-platform/` except deleting `ai-platform/scripts/bootstrap-routing-policy.sh`. `docs/architecture/ai-platform/02-ai-platform-overview.md` stays as it is
- **Spec Kit artifacts**: `specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/`

---

## 3. Tests

**Purpose**: Sequencing steps 1–4. One test per E2E id. `E2E-P7.1-03` is written to fail before the viewer clean-up. `E2E-P7.1-01` is created and is not executed. `E2E-P7.1-02` is the residue-guard script and CI job, observed failing on the four trees before those trees are cleaned. Leave the other production files in **Files** unchanged through T004.

`E2E-P7.1-03` command, from `ai-platform-viewer/`. It does not boot wrangler:

```bash
npx vitest run test/viewer-builds.test.ts -t "E2E-P7.1-03"
```

`E2E-P7.1-02` command, from the repo root. It does not boot wrangler:

```bash
bash .github/scripts/control-residue-guard.sh ai-platform-viewer ai-platform/scripts docs/architecture/ai-platform docs/testing/catalog
```

`E2E-P7.1-01` is `ai-platform-viewer/test/clinic-pages.smoke.test.ts`. This phase creates that file and does not run it. Do not boot wrangler. Do not run `npm test` in `e2e/fullstack`.

### 3.1 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — tests

**Independent Test**: E2E-P7.1-01 and E2E-P7.1-03. Viewer catalog smoke tests against the local platform (`ai-platform-viewer/`, rule V2).

- [X] T001 [US1] Add the failing test `E2E-P7.1-03` in `ai-platform-viewer/test/viewer-builds.test.ts` — red test, FR-001, E2E-P7.1-03. Depends on nothing. Title `E2E-P7.1-03`. From `ai-platform-viewer/`, the test runs `npm run build`, then runs `.github/scripts/control-residue-guard.sh` on `ai-platform-viewer/dist`. The build completes and the guard exits 0 when the built bundle has none of the five needles. The test source does not contain `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, or `installation_key`. The test does not boot wrangler. The vitest command fails because the guard script is not present yet and the viewer build still has control routes.

**Checkpoint**: E2E-P7.1-03 exists and fails.

- [X] T002 [US1] Create `ai-platform-viewer/test/clinic-pages.smoke.test.ts` with the test `E2E-P7.1-01` — test file, FR-002, E2E-P7.1-01. Depends on T001. Title `E2E-P7.1-01`. The test drives `Stage7DiscoveryPage` through `stage-7-discovery.ts` and `sendCapabilitiesRequest`, and stages 8–12 through their catalogs, `sendJourneyRequest`, and `issuer-token.ts`, against `http://127.0.0.1:8787`. It expects `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/requests/{request_reference}` with an issuer token and `Aip-Contract-Version: 1`, and the local platform accepting those calls. The test does not read a bearer. The test source does not contain the five needles. Do not run this file. Do not boot wrangler. Do not run `npm test` in `e2e/fullstack`.

**Checkpoint**: E2E-P7.1-01 exists as a file and is not executed. E2E-P7.1-03 still fails.

### 3.2 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — residue guard

**Independent Test**: E2E-P7.1-02 in the CI residue guard (rule V7). Every earlier suite stays green (rule S2).

- [X] T003 [US2] Add `.github/scripts/control-residue-guard.sh` and job `control-residue-guard` in `.github/workflows/ci.yml` — residue guard, FR-005, E2E-P7.1-02. Depends on T002. The script scans the paths it is given. Needles are the literal substrings `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, and `installation_key`. For a directory among the four trees, scan `git ls-files` under that directory and skip any path with a `migrations` segment. For a file, scan that file alone. For `ai-platform-viewer/dist`, scan the built files on disk, because that directory is not in `git ls-files`. Exit non-zero when any needle occurs. The script lives at `.github/scripts/control-residue-guard.sh`, outside the four trees. The job checks out the repo, runs the script on `ai-platform-viewer`, `ai-platform/scripts`, `docs/architecture/ai-platform`, and `docs/testing/catalog` (that run must pass once those trees are clean), writes a temporary fixture that contains `/control/` outside those four trees, and runs the script on that fixture alone (that run must exit non-zero). The fixture is not committed. Do not boot wrangler.

**Checkpoint**: E2E-P7.1-02's script and job exist. The four-tree scan still sees needles.

### 3.3 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — red run

**Independent Test**: E2E-P7.1-02 in the CI residue guard (rule V7). Every earlier suite stays green (rule S2).

- [X] T004 [US2] Run the residue guard and `E2E-P7.1-03` and confirm they fail — red run, FR-001, FR-005, E2E-P7.1-02, E2E-P7.1-03. Depends on T003. From the repo root, run `bash .github/scripts/control-residue-guard.sh ai-platform-viewer ai-platform/scripts docs/architecture/ai-platform docs/testing/catalog` and confirm it exits non-zero. Write a temporary fixture that contains `/control/` outside the four trees, run the script on that file alone, and confirm it exits non-zero. Do not commit the fixture. From `ai-platform-viewer/`, run `npx vitest run test/viewer-builds.test.ts -t "E2E-P7.1-03"` and confirm that test fails. Leave production files unchanged. Do not edit `ai-platform-viewer/test/viewer-builds.test.ts`, `ai-platform-viewer/test/clinic-pages.smoke.test.ts`, `.github/scripts/control-residue-guard.sh`, or `.github/workflows/ci.yml` in this task. Do not run `ai-platform-viewer/test/clinic-pages.smoke.test.ts`. Do not boot wrangler. Do not run `npm test` in `e2e/fullstack`.

**Checkpoint**: E2E-P7.1-02 fails on the four trees and fails the fixture. E2E-P7.1-03 fails. E2E-P7.1-01 is still not executed.

---

## 4. Implementation

**Purpose**: Sequencing steps 5–12. Starts after T004 has shown the guard and `E2E-P7.1-03` fail. Within a subphase the tasks run in id order.

### 4.1 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — issuer token sends

**Independent Test**: E2E-P7.1-01 and E2E-P7.1-03. Viewer catalog smoke tests against the local platform (`ai-platform-viewer/`, rule V2).

- [X] T005 [US1] Add `ai-platform-viewer/src/lib/issuer-token.ts` and point `sendCapabilitiesRequest` and `sendJourneyRequest` at it — issuer token and `Aip-Contract-Version: 1`, FR-001, FR-002, E2E-P7.1-01, E2E-P7.1-03. Depends on T004. Create `ai-platform-viewer/src/lib/issuer-token.ts`. Mint a compact JWT with WebCrypto Ed25519. Header `{ alg: "EdDSA", kid, typ: "JWT" }`. Payload `iss` `issuer-test`, `aud` `ai-platform`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver` `"2"`. Signed by the test issuer private key. In `ai-platform-viewer/src/lib/gateway-api.ts`, `sendCapabilitiesRequest` sends `GET /v1/capabilities` with `Authorization: Bearer <token>` for that issuer token and `Aip-Contract-Version: 1`. Delete the `/control/token-contract/*` send and the bearer header. Do not call platform enrollment. In `ai-platform-viewer/src/lib/journey-api.ts`, clinic `aat` operations send the issuer token and `Aip-Contract-Version: 1`. Remove the bearer branch. This unit does not register the test issuer key.

**Checkpoint**: Capabilities and request sends use the issuer token and `Aip-Contract-Version: 1`. E2E-P7.1-03 still fails.

### 4.2 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — clinic shell

**Independent Test**: E2E-P7.1-01 and E2E-P7.1-03. Viewer catalog smoke tests against the local platform (`ai-platform-viewer/`, rule V2).

- [X] T006 [US1] Leave `AppShell` on stages 7–12 and drop the other routes — clinic shell, FR-001, FR-002, E2E-P7.1-01, E2E-P7.1-03. Depends on T005. In `ai-platform-viewer/src/components/AppShell.tsx`, compose only `Stage7DiscoveryPage`, `Stage8IngressPage`, `Stage9GuardPage`, `Stage10StreamPage`, `Stage11SettlementPage`, and `Stage12LookupSupportPage`. In `ai-platform-viewer/src/lib/routes.ts`, paths only for `stage-7` through `stage-12`, and the default section is `stage-7`. In `ai-platform-viewer/src/types.ts`, `NavSection` is only those six sections, and `DevConfig` has no bearer field. In `ai-platform-viewer/src/components/SideNav.tsx`, nav entries only for stages 7–12, and the five needles are gone from that file.

**Checkpoint**: `AppShell` composes only stages 7–12. E2E-P7.1-03 still fails.

### 4.3 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — control catalog removal

**Independent Test**: E2E-P7.1-01 and E2E-P7.1-03. Viewer catalog smoke tests against the local platform (`ai-platform-viewer/`, rule V2).

- [ ] T007 [US1] Remove `/control/` operations from the stage 10 and stage 12 catalogs — clinic operations kept, FR-001, FR-002, E2E-P7.1-01, E2E-P7.1-03. Depends on T006. In `ai-platform-viewer/src/catalog/stage-10-stream.ts`, remove the routing-policy operations whose path contains `/control/`, and keep the clinic stream operations on `/v1/requests` with the issuer token. In `ai-platform-viewer/src/catalog/stage-12-lookup-support.ts`, remove the support operation whose path contains `/control/`, and keep lookup on `/v1/requests/{request_reference}` with the issuer token. Those files contain none of the five needles.

**Checkpoint**: Stage 10 and stage 12 catalogs have no `/control/` operation. E2E-P7.1-03 still fails.

### 4.4 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — clinic wording

**Independent Test**: E2E-P7.1-01 and E2E-P7.1-03. Viewer catalog smoke tests against the local platform (`ai-platform-viewer/`, rule V2).

- [ ] T008 [US1] Strip bearer and enrollment-keypair wording from the clinic catalogs and pages that stay — issuer token on the remaining clinic operations, FR-001, FR-002, E2E-P7.1-01, E2E-P7.1-03. Depends on T006. Does not depend on T007. In `ai-platform-viewer/src/catalog/stage-7-discovery.ts`, capabilities operations stay `GET /v1/capabilities` and use the issuer token. In `ai-platform-viewer/src/catalog/stage-8-ingress.ts`, keep `/v1/requests` operations and use the issuer token. In `ai-platform-viewer/src/catalog/stage-9-guard.ts`, keep clinic guard operations on `/v1/requests` and remove bearer wording. In `ai-platform-viewer/src/catalog/stage-11-settlement.ts`, settlement operations stay on `/v1/requests` and use the issuer token. In `ai-platform-viewer/src/components/Stage8IngressPage.tsx`, remove enrollment-keypair wording; the page still sends `/v1/requests`. In `ai-platform-viewer/src/components/JourneyCommandPanel.tsx` and `ai-platform-viewer/src/components/JourneyOperationCard.tsx`, pass the issuer token into `sendJourneyRequest` and remove the five needles. In `ai-platform-viewer/src/lib/supabase-api.ts`, remove the `installation_key` wording; clinic request sends do not use it. Those files contain none of the five needles.

**Checkpoint**: The clinic catalogs and pages that stay use the issuer token and contain none of the five needles. E2E-P7.1-03 still fails.

### 4.5 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — control module deletion

**Independent Test**: E2E-P7.1-01 and E2E-P7.1-03. Viewer catalog smoke tests against the local platform (`ai-platform-viewer/`, rule V2).

- [ ] T009 [US1] Delete the control pages, control catalogs, control smokes, reset SQL, and control-only libraries — control routes gone, FR-001, E2E-P7.1-03. Depends on T007 and T008. Delete these files:

  - `ai-platform-viewer/test/commercial-pages.smoke.test.ts`
  - `ai-platform-viewer/test/stage-x.smoke.test.ts`
  - `ai-platform-viewer/test/helpers/smoke-http.ts`
  - `ai-platform-viewer/server/reset-clinic-ai-internal.sql`
  - `ai-platform-viewer/server/reset-installations.sql`
  - `ai-platform-viewer/server/reset-platform.sql`
  - `ai-platform-viewer/src/lib/mint-aat.ts`
  - `ai-platform-viewer/src/lib/platform-enroll.ts`
  - `ai-platform-viewer/src/lib/platform-installation-api.ts`
  - `ai-platform-viewer/src/lib/routing-policy-default.ts`
  - `ai-platform-viewer/src/catalog/commercial-plans.ts`
  - `ai-platform-viewer/src/catalog/commercial-usage.ts`
  - `ai-platform-viewer/src/catalog/guard-pipeline.ts`
  - `ai-platform-viewer/src/catalog/stage-0-platform-boot.ts`
  - `ai-platform-viewer/src/catalog/stage-1-token-contract.ts`
  - `ai-platform-viewer/src/catalog/stage-2-clinic-keypair.ts`
  - `ai-platform-viewer/src/catalog/stage-3-platform-installation.ts`
  - `ai-platform-viewer/src/catalog/stage-4-entitlement.ts`
  - `ai-platform-viewer/src/catalog/stage-5-routing-policy.ts`
  - `ai-platform-viewer/src/catalog/stage-5-routing.ts`
  - `ai-platform-viewer/src/catalog/stage-6-mint-aat.ts`
  - `ai-platform-viewer/src/catalog/stage-x.ts`
  - `ai-platform-viewer/src/components/SecretsPage.tsx`
  - `ai-platform-viewer/src/components/Stage0PlatformBootPage.tsx`
  - `ai-platform-viewer/src/components/Stage1TokenContractPage.tsx`
  - `ai-platform-viewer/src/components/Stage1CommandPanel.tsx`
  - `ai-platform-viewer/src/components/Stage2ClinicKeypairPage.tsx`
  - `ai-platform-viewer/src/components/Stage2CommandPanel.tsx`
  - `ai-platform-viewer/src/components/Stage3PlatformInstallationPage.tsx`
  - `ai-platform-viewer/src/components/Stage3CommandPanel.tsx`
  - `ai-platform-viewer/src/components/Stage4EntitlementPage.tsx`
  - `ai-platform-viewer/src/components/Stage5RoutingPage.tsx`
  - `ai-platform-viewer/src/components/Stage6MintAatPage.tsx`
  - `ai-platform-viewer/src/components/StageXPage.tsx`
  - `ai-platform-viewer/src/components/UsageGaugePage.tsx`
  - `ai-platform-viewer/src/components/PlansPage.tsx`
  - `ai-platform-viewer/src/components/InvoicesPage.tsx`
  - `ai-platform-viewer/src/components/GuardPipelinePage.tsx`
  - `ai-platform-viewer/src/components/OperationCard.tsx`
  - `ai-platform-viewer/src/components/PlatformOperationCard.tsx`

  Control-only modules that the deleted pages alone import, and that are not listed in **Files**, are deleted in this same change so `npm run build` still typechecks. They are not new modules.

**Checkpoint**: The listed control modules are deleted. E2E-P7.1-03 still fails until the dev plugin and session stop emitting needles.

### 4.6 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — dev config and session

**Independent Test**: E2E-P7.1-01 and E2E-P7.1-03. Viewer catalog smoke tests against the local platform (`ai-platform-viewer/`, rule V2).

- [ ] T010 [US1] Stop the dev plugin and the session from using a bearer — test issuer key on `/api/dev/config`, FR-001, FR-002, E2E-P7.1-01, E2E-P7.1-03. Depends on T009. In `ai-platform-viewer/server/dev-plugin.ts`, `/api/dev/config` returns the test issuer key (kid and private key) from `ai-platform/.dev.vars` and does not return a bearer. Remove the reset routes that run the SQL files deleted in T009. In `ai-platform-viewer/src/lib/dev-api.ts`, stop calling the installation reset route. In `ai-platform-viewer/src/context/SessionContext.tsx`, mint the issuer token for clinic sends. Do not mint through the installation-keypair RPC and do not require a bearer. Those files contain none of the five needles. `ai-platform/.dev.vars` is outside the scanned trees and is not edited.

**Checkpoint**: `/api/dev/config` returns the test issuer key and no bearer. The session mints the issuer token. E2E-P7.1-03 is ready to re-run after the dependent-path docs are clean.

### 4.7 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — routing-policy script

**Independent Test**: E2E-P7.1-02 in the CI residue guard (rule V7). Every earlier suite stays green (rule S2).

- [ ] T011 [US2] Delete `ai-platform/scripts/bootstrap-routing-policy.sh` — script removed, FR-003, E2E-P7.1-02. Depends on T010. Delete that file. The console's class-H routing-policy action replaces it and is not built here.

**Checkpoint**: `bootstrap-routing-policy.sh` is deleted. The four-tree guard still fails until the superseded docs are rewritten.

### 4.8 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — architecture docs

**Independent Test**: E2E-P7.1-02 in the CI residue guard (rule V7). Every earlier suite stays green (rule S2).

- [ ] T012 [US2] Rewrite the listed `docs/architecture/ai-platform/` pages — superseded note, FR-004, E2E-P7.1-02. Depends on T011. Replace each listed page with a superseded note in entrypoint terms, with links to `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` and `docs/architecture/ai-billing-orchestration/05-abo-operations-and-traceability.md`. None of the five needles remain in these pages. Leave `docs/architecture/ai-platform/02-ai-platform-overview.md` unchanged. Pages in this tree that are not listed and do not contain the five needles stay as they are. Rewrite:

  - `docs/architecture/ai-platform/01-ai-platform.md`
  - `docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`
  - `docs/architecture/ai-platform/04-ai-platform-operator-runbook.md`
  - `docs/architecture/ai-platform/06-ai-platform-behavioral-journey.md`
  - `docs/architecture/ai-platform/07-ai-platform-d1-r2-storage.md`
  - `docs/architecture/ai-platform/08-ai-platform-data-journey.md`
  - `docs/architecture/ai-platform/09-ai-platform-request-response-flow.md`
  - `docs/architecture/ai-platform/arch-vs-source-gap-analysis.md`
  - `docs/architecture/ai-platform/code-audit-2026-08-21.md`
  - `docs/architecture/ai-platform/code-audit-2026-08-21-verification.md`
  - `docs/architecture/ai-platform/request-lifecycle-brief.md`
  - `docs/architecture/ai-platform/system-testing-plan.md`
  - `docs/architecture/ai-platform/data-journey/01-introduction-and-storage-layers.md`
  - `docs/architecture/ai-platform/data-journey/02-stage-0-platform-configuration-and-boot.md`
  - `docs/architecture/ai-platform/data-journey/03-stage-1-token-contract-baseline.md`
  - `docs/architecture/ai-platform/data-journey/04-stage-2-clinic-keypair-enrollment.md`
  - `docs/architecture/ai-platform/data-journey/05-stage-3-platform-installation-enrollment.md`
  - `docs/architecture/ai-platform/data-journey/06-stage-4-entitlement-and-capability-grants.md`
  - `docs/architecture/ai-platform/data-journey/07-stage-5-routing-policy.md`
  - `docs/architecture/ai-platform/data-journey/08-stage-6-minting-an-aat.md`
  - `docs/architecture/ai-platform/data-journey/09-stage-7-discovery.md`
  - `docs/architecture/ai-platform/data-journey/10-stage-8-request-ingress.md`
  - `docs/architecture/ai-platform/data-journey/11-stage-9-the-guard.md`
  - `docs/architecture/ai-platform/data-journey/12-stage-10-accept-route-invoke-stream.md`
  - `docs/architecture/ai-platform/data-journey/13-stage-11-terminal-settlement.md`
  - `docs/architecture/ai-platform/data-journey/14-stage-12-lookup-and-support.md`
  - `docs/architecture/ai-platform/data-journey/15-alternative-and-failure-journeys.md`
  - `docs/architecture/ai-platform/data-journey/16-complete-d1-column-reference.md`
  - `docs/architecture/ai-platform/data-journey/17-complete-r2-object-reference.md`
  - `docs/architecture/ai-platform/data-journey/18-quota-durable-object-state-reference.md`
  - `docs/architecture/ai-platform/data-journey/19-taxonomy-codes-and-http-mapping.md`
  - `docs/architecture/ai-platform/data-journey/20-source-file-index.md`
  - `docs/architecture/ai-platform/implementation-references/01-band-a-implementation-reference.md`
  - `docs/architecture/ai-platform/implementation-references/02-band-b-implementation-reference.md`
  - `docs/architecture/ai-platform/implementation-references/04-band-d-implementation-reference.md`
  - `docs/architecture/ai-platform/implementation-references/06-band-f-implementation-reference.md`
  - `docs/architecture/ai-platform/implementation-references/08-band-j-implementation-reference.md`

**Checkpoint**: The listed architecture pages link to the v2 design and contain none of the five needles.

### 4.9 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — catalog docs

**Independent Test**: E2E-P7.1-02 in the CI residue guard (rule V7). Every earlier suite stays green (rule S2).

- [ ] T013 [US2] Rewrite the listed `docs/testing/catalog/` pages — superseded note, including stage pages that describe `/control/*` probes, FR-004, E2E-P7.1-02. Depends on T012. Use the same superseded note as T012, with the same two v2 links. None of the five needles remain in these pages. Pages in this tree that are not listed and do not contain the five needles stay as they are. Rewrite:

  - `docs/testing/catalog/FIX-WORKLIST.md`
  - `docs/testing/catalog/README.md`
  - `docs/testing/catalog/implementation-audit-findings.md`
  - `docs/testing/catalog/implementation-review-findings.md`
  - `docs/testing/catalog/implementation-work-order.md`
  - `docs/testing/catalog/registers.md`
  - `docs/testing/catalog/remediation-plan.md`
  - `docs/testing/catalog/stage-00-platform-boot.md`
  - `docs/testing/catalog/stage-01-token-contract.md`
  - `docs/testing/catalog/stage-02-clinic-keypair.md`
  - `docs/testing/catalog/stage-03-installation-enrollment.md`
  - `docs/testing/catalog/stage-04-entitlement-capability-grants.md`
  - `docs/testing/catalog/stage-05-routing-policy.md`
  - `docs/testing/catalog/stage-06-minting-an-aat.md`
  - `docs/testing/catalog/stage-07-discovery.md`
  - `docs/testing/catalog/stage-08-request-ingress.md`
  - `docs/testing/catalog/stage-09-the-guard.md`
  - `docs/testing/catalog/stage-10-accept-route-invoke-stream.md`
  - `docs/testing/catalog/stage-11-terminal-settlement.md`
  - `docs/testing/catalog/stage-12-lookup-and-support.md`
  - `docs/testing/catalog/stage-X-cron-and-failure-journeys.md`
  - `docs/testing/catalog/sweep/sql-track.md`
  - `docs/testing/catalog/sweep/stage-X-and-coverage.md`
  - `docs/testing/catalog/sweep/stages-04-05.md`
  - `docs/testing/catalog/sweep/stages-07-08-09.md`

**Checkpoint**: The listed catalog pages link to the v2 design and contain none of the five needles. E2E-P7.1-02 is ready for the harness.

---

## 5. Verification

**Purpose**: Sequencing steps 13–15. The residue guard passes on the four trees, the fixture still fails it, and `E2E-P7.1-03` passes. `E2E-P7.1-01` is not executed. This is not a repo-wide command.

### 5.1 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — unit harness

**Independent Test**: E2E-P7.1-02 in the CI residue guard (rule V7). Every earlier suite stays green (rule S2).

- [ ] T014 [US2] Re-run the residue guard and `E2E-P7.1-03` until they match the harness, and confirm the clinic shell — green harness, FR-001, FR-002, FR-003, FR-004, FR-005, E2E-P7.1-01, E2E-P7.1-02, E2E-P7.1-03. Depends on T013. From the repo root, run `bash .github/scripts/control-residue-guard.sh ai-platform-viewer ai-platform/scripts docs/architecture/ai-platform docs/testing/catalog` until it exits 0. Run the same script on a temporary fixture that contains `/control/` and confirm that run exits non-zero. Do not commit the fixture. From `ai-platform-viewer/`, run `npx vitest run test/viewer-builds.test.ts -t "E2E-P7.1-03"` until that test passes. Confirm `ai-platform-viewer/src/components/AppShell.tsx` still composes only stages 7–12, and confirm `ai-platform-viewer/test/clinic-pages.smoke.test.ts` does not read a bearer. Do not run `ai-platform-viewer/test/clinic-pages.smoke.test.ts`. Do not boot wrangler. Do not run `npm test` in `e2e/fullstack`. Fixes stay in the files this unit's **Files** table lists.

**Checkpoint**: E2E-P7.1-02 passes on the four trees and fails the fixture. E2E-P7.1-03 passes. E2E-P7.1-01 is not executed. `AppShell` still composes only stages 7–12.

---

## 6. Documentation

**Purpose**: Sequencing step 16. `quickstart.md` after the harness is green. Plan-phase `research.md`, `data-model.md`, and `contracts/` stay omitted.

### 6.1 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — quickstart

**Independent Test**: E2E-P7.1-02 in the CI residue guard (rule V7). Every earlier suite stays green (rule S2).

- [ ] T015 [US2] Write `specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/quickstart.md` — unit quickstart, FR-001, FR-002, FR-003, FR-005, E2E-P7.1-01, E2E-P7.1-02, E2E-P7.1-03. Depends on T014. Fill only these sections: what was implemented and the files added or modified; the harness commands for this unit's tests only; the entry point → module chain per E2E id. Harness commands: from `ai-platform-viewer/`, `npx vitest run test/clinic-pages.smoke.test.ts test/viewer-builds.test.ts`; from the repo root, `bash .github/scripts/control-residue-guard.sh ai-platform-viewer ai-platform/scripts docs/architecture/ai-platform docs/testing/catalog`, then the same script on a temporary fixture that contains `/control/` (that run must exit non-zero). Do not list earlier-unit files, combined counts, or full-suite commands. Manual step: the local platform is already listening on `http://127.0.0.1:8787` with the test issuer key registered. This unit does not boot wrangler.

**Checkpoint**: `quickstart.md` names the three E2E ids, the unit commands, and the entry chain.

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (Phase 3)**: T001 adds `E2E-P7.1-03` in `ai-platform-viewer/test/viewer-builds.test.ts`. T002 creates `ai-platform-viewer/test/clinic-pages.smoke.test.ts` and does not run it. T003 adds `.github/scripts/control-residue-guard.sh` and the `control-residue-guard` job. T004 runs the guard on the four trees and on a temporary fixture, and runs `E2E-P7.1-03`, and confirms those runs fail before any other production file in **Files** changes.
- **Implementation (Phase 4)**: Starts after T004. The issuer token and the two send paths come first. `AppShell`, routes, nav, and `NavSection` then keep only stages 7–12. Stage 10 and stage 12 lose `/control/` operations. The clinic catalogs and pages that stay lose bearer and enrollment-keypair wording. Control pages, catalogs, smokes, reset SQL, and control-only libraries are then deleted. The dev plugin and the session stop using a bearer and `/api/dev/config` returns the test issuer key. `bootstrap-routing-policy.sh` is deleted. The listed architecture pages are rewritten, then the listed catalog pages.
- **Verification (Phase 5)**: Starts after T013. The four-tree guard exits 0, the fixture exits non-zero, and `E2E-P7.1-03` passes. The clinic smoke file is not executed.
- **Documentation (Phase 6)**: Starts after T014. One file: `quickstart.md`.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: The build test is T001. The clinic smoke file is T002 and is not executed. The issuer-token sends, the clinic shell, the catalog edits, the control-module deletion, and the dev config and session are T005 through T010. E2E-P7.1-03 is in the red run (T004) and the green harness (T014). E2E-P7.1-01 is created in T002 and is not run in T004 or T014.
- **User Story 2 (P2)**: The residue guard is T003, after the User Story 1 test files. The red run is T004. The script deletion is T011, after the viewer clean-up. The architecture docs are T012. The catalog docs are T013. E2E-P7.1-02 is in the red run (T004) and the green harness (T014).

### 7.3 Within Each Phase

- T001 writes `ai-platform-viewer/test/viewer-builds.test.ts`. T002 creates `ai-platform-viewer/test/clinic-pages.smoke.test.ts` and does not run it. T003 writes `.github/scripts/control-residue-guard.sh` and `.github/workflows/ci.yml`. T004 runs those commands and does not edit those files.
- T005 creates `ai-platform-viewer/src/lib/issuer-token.ts` and writes `ai-platform-viewer/src/lib/gateway-api.ts` and `ai-platform-viewer/src/lib/journey-api.ts`. T006 writes `ai-platform-viewer/src/components/AppShell.tsx`, `ai-platform-viewer/src/lib/routes.ts`, `ai-platform-viewer/src/types.ts`, and `ai-platform-viewer/src/components/SideNav.tsx`. T007 writes `ai-platform-viewer/src/catalog/stage-10-stream.ts` and `ai-platform-viewer/src/catalog/stage-12-lookup-support.ts`. T008 writes the stage 7, 8, 9, and 11 catalogs, `Stage8IngressPage.tsx`, `JourneyCommandPanel.tsx`, `JourneyOperationCard.tsx`, and `supabase-api.ts`. T009 deletes the control files listed in that task. T010 writes `ai-platform-viewer/server/dev-plugin.ts`, `ai-platform-viewer/src/lib/dev-api.ts`, and `ai-platform-viewer/src/context/SessionContext.tsx`.
- T011 deletes `ai-platform/scripts/bootstrap-routing-policy.sh`. T012 rewrites the listed `docs/architecture/ai-platform/` pages. T013 rewrites the listed `docs/testing/catalog/` pages.
- T014 runs after T013 and may edit only the files this unit's **Files** table lists.
- T015 writes only `specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/quickstart.md` after T014 is green.

---

## 8. Implementation Waves

Stage 10 and stage 12 catalog removal shares no path with the clinic wording edits, and both follow the clinic shell, so that wave has two bullets. Every other subphase is serial with the one before it.

### 8.1 Wave 1

- T001–T002 [US1] — subphase: `### 3.1 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — tests` — paths: `ai-platform-viewer/test/viewer-builds.test.ts`, `ai-platform-viewer/test/clinic-pages.smoke.test.ts`

### 8.2 Wave 2

- T003 [US2] — subphase: `### 3.2 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — residue guard` — paths: `.github/scripts/control-residue-guard.sh`, `.github/workflows/ci.yml`

### 8.3 Wave 3

- T004 [US2] — subphase: `### 3.3 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — red run` — paths: `.github/scripts/control-residue-guard.sh`, `ai-platform-viewer/test/viewer-builds.test.ts`

### 8.4 Wave 4

- T005 [US1] — subphase: `### 4.1 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — issuer token sends` — paths: `ai-platform-viewer/src/lib/issuer-token.ts`, `ai-platform-viewer/src/lib/gateway-api.ts`, `ai-platform-viewer/src/lib/journey-api.ts`

### 8.5 Wave 5

- T006 [US1] — subphase: `### 4.2 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — clinic shell` — paths: `ai-platform-viewer/src/components/AppShell.tsx`, `ai-platform-viewer/src/lib/routes.ts`, `ai-platform-viewer/src/types.ts`, `ai-platform-viewer/src/components/SideNav.tsx`

### 8.6 Wave 6

- T007 [US1] — subphase: `### 4.3 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — control catalog removal` — paths: `ai-platform-viewer/src/catalog/stage-10-stream.ts`, `ai-platform-viewer/src/catalog/stage-12-lookup-support.ts`
- T008 [US1] — subphase: `### 4.4 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — clinic wording` — paths: `ai-platform-viewer/src/catalog/stage-7-discovery.ts`, `ai-platform-viewer/src/catalog/stage-8-ingress.ts`, `ai-platform-viewer/src/catalog/stage-9-guard.ts`, `ai-platform-viewer/src/catalog/stage-11-settlement.ts`, `ai-platform-viewer/src/components/Stage8IngressPage.tsx`, `ai-platform-viewer/src/components/JourneyCommandPanel.tsx`, `ai-platform-viewer/src/components/JourneyOperationCard.tsx`, `ai-platform-viewer/src/lib/supabase-api.ts`

### 8.7 Wave 7

- T009 [US1] — subphase: `### 4.5 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — control module deletion` — paths: `ai-platform-viewer/test/commercial-pages.smoke.test.ts`, `ai-platform-viewer/test/stage-x.smoke.test.ts`, `ai-platform-viewer/test/helpers/smoke-http.ts`, `ai-platform-viewer/server/reset-clinic-ai-internal.sql`, `ai-platform-viewer/server/reset-installations.sql`, `ai-platform-viewer/server/reset-platform.sql`, `ai-platform-viewer/src/lib/mint-aat.ts`, `ai-platform-viewer/src/lib/platform-enroll.ts`, `ai-platform-viewer/src/lib/platform-installation-api.ts`, `ai-platform-viewer/src/lib/routing-policy-default.ts`, `ai-platform-viewer/src/catalog/commercial-plans.ts`, `ai-platform-viewer/src/catalog/commercial-usage.ts`, `ai-platform-viewer/src/catalog/guard-pipeline.ts`, `ai-platform-viewer/src/catalog/stage-0-platform-boot.ts`, `ai-platform-viewer/src/catalog/stage-1-token-contract.ts`, `ai-platform-viewer/src/catalog/stage-2-clinic-keypair.ts`, `ai-platform-viewer/src/catalog/stage-3-platform-installation.ts`, `ai-platform-viewer/src/catalog/stage-4-entitlement.ts`, `ai-platform-viewer/src/catalog/stage-5-routing-policy.ts`, `ai-platform-viewer/src/catalog/stage-5-routing.ts`, `ai-platform-viewer/src/catalog/stage-6-mint-aat.ts`, `ai-platform-viewer/src/catalog/stage-x.ts`, `ai-platform-viewer/src/components/SecretsPage.tsx`, `ai-platform-viewer/src/components/Stage0PlatformBootPage.tsx`, `ai-platform-viewer/src/components/Stage1TokenContractPage.tsx`, `ai-platform-viewer/src/components/Stage1CommandPanel.tsx`, `ai-platform-viewer/src/components/Stage2ClinicKeypairPage.tsx`, `ai-platform-viewer/src/components/Stage2CommandPanel.tsx`, `ai-platform-viewer/src/components/Stage3PlatformInstallationPage.tsx`, `ai-platform-viewer/src/components/Stage3CommandPanel.tsx`, `ai-platform-viewer/src/components/Stage4EntitlementPage.tsx`, `ai-platform-viewer/src/components/Stage5RoutingPage.tsx`, `ai-platform-viewer/src/components/Stage6MintAatPage.tsx`, `ai-platform-viewer/src/components/StageXPage.tsx`, `ai-platform-viewer/src/components/UsageGaugePage.tsx`, `ai-platform-viewer/src/components/PlansPage.tsx`, `ai-platform-viewer/src/components/InvoicesPage.tsx`, `ai-platform-viewer/src/components/GuardPipelinePage.tsx`, `ai-platform-viewer/src/components/OperationCard.tsx`, `ai-platform-viewer/src/components/PlatformOperationCard.tsx`

### 8.8 Wave 8

- T010 [US1] — subphase: `### 4.6 User Story 1 - Viewer clinic pages use issuer tokens (Priority: P1) — dev config and session` — paths: `ai-platform-viewer/server/dev-plugin.ts`, `ai-platform-viewer/src/lib/dev-api.ts`, `ai-platform-viewer/src/context/SessionContext.tsx`

### 8.9 Wave 9

- T011 [US2] — subphase: `### 4.7 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — routing-policy script` — paths: `ai-platform/scripts/bootstrap-routing-policy.sh`

### 8.10 Wave 10

- T012 [US2] — subphase: `### 4.8 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — architecture docs` — paths: `docs/architecture/ai-platform/01-ai-platform.md`, `docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`, `docs/architecture/ai-platform/04-ai-platform-operator-runbook.md`, `docs/architecture/ai-platform/06-ai-platform-behavioral-journey.md`, `docs/architecture/ai-platform/07-ai-platform-d1-r2-storage.md`, `docs/architecture/ai-platform/08-ai-platform-data-journey.md`, `docs/architecture/ai-platform/09-ai-platform-request-response-flow.md`, `docs/architecture/ai-platform/arch-vs-source-gap-analysis.md`, `docs/architecture/ai-platform/code-audit-2026-08-21.md`, `docs/architecture/ai-platform/code-audit-2026-08-21-verification.md`, `docs/architecture/ai-platform/request-lifecycle-brief.md`, `docs/architecture/ai-platform/system-testing-plan.md`, `docs/architecture/ai-platform/data-journey/01-introduction-and-storage-layers.md`, `docs/architecture/ai-platform/data-journey/02-stage-0-platform-configuration-and-boot.md`, `docs/architecture/ai-platform/data-journey/03-stage-1-token-contract-baseline.md`, `docs/architecture/ai-platform/data-journey/04-stage-2-clinic-keypair-enrollment.md`, `docs/architecture/ai-platform/data-journey/05-stage-3-platform-installation-enrollment.md`, `docs/architecture/ai-platform/data-journey/06-stage-4-entitlement-and-capability-grants.md`, `docs/architecture/ai-platform/data-journey/07-stage-5-routing-policy.md`, `docs/architecture/ai-platform/data-journey/08-stage-6-minting-an-aat.md`, `docs/architecture/ai-platform/data-journey/09-stage-7-discovery.md`, `docs/architecture/ai-platform/data-journey/10-stage-8-request-ingress.md`, `docs/architecture/ai-platform/data-journey/11-stage-9-the-guard.md`, `docs/architecture/ai-platform/data-journey/12-stage-10-accept-route-invoke-stream.md`, `docs/architecture/ai-platform/data-journey/13-stage-11-terminal-settlement.md`, `docs/architecture/ai-platform/data-journey/14-stage-12-lookup-and-support.md`, `docs/architecture/ai-platform/data-journey/15-alternative-and-failure-journeys.md`, `docs/architecture/ai-platform/data-journey/16-complete-d1-column-reference.md`, `docs/architecture/ai-platform/data-journey/17-complete-r2-object-reference.md`, `docs/architecture/ai-platform/data-journey/18-quota-durable-object-state-reference.md`, `docs/architecture/ai-platform/data-journey/19-taxonomy-codes-and-http-mapping.md`, `docs/architecture/ai-platform/data-journey/20-source-file-index.md`, `docs/architecture/ai-platform/implementation-references/01-band-a-implementation-reference.md`, `docs/architecture/ai-platform/implementation-references/02-band-b-implementation-reference.md`, `docs/architecture/ai-platform/implementation-references/04-band-d-implementation-reference.md`, `docs/architecture/ai-platform/implementation-references/06-band-f-implementation-reference.md`, `docs/architecture/ai-platform/implementation-references/08-band-j-implementation-reference.md`

### 8.11 Wave 11

- T013 [US2] — subphase: `### 4.9 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — catalog docs` — paths: `docs/testing/catalog/FIX-WORKLIST.md`, `docs/testing/catalog/README.md`, `docs/testing/catalog/implementation-audit-findings.md`, `docs/testing/catalog/implementation-review-findings.md`, `docs/testing/catalog/implementation-work-order.md`, `docs/testing/catalog/registers.md`, `docs/testing/catalog/remediation-plan.md`, `docs/testing/catalog/stage-00-platform-boot.md`, `docs/testing/catalog/stage-01-token-contract.md`, `docs/testing/catalog/stage-02-clinic-keypair.md`, `docs/testing/catalog/stage-03-installation-enrollment.md`, `docs/testing/catalog/stage-04-entitlement-capability-grants.md`, `docs/testing/catalog/stage-05-routing-policy.md`, `docs/testing/catalog/stage-06-minting-an-aat.md`, `docs/testing/catalog/stage-07-discovery.md`, `docs/testing/catalog/stage-08-request-ingress.md`, `docs/testing/catalog/stage-09-the-guard.md`, `docs/testing/catalog/stage-10-accept-route-invoke-stream.md`, `docs/testing/catalog/stage-11-terminal-settlement.md`, `docs/testing/catalog/stage-12-lookup-and-support.md`, `docs/testing/catalog/stage-X-cron-and-failure-journeys.md`, `docs/testing/catalog/sweep/sql-track.md`, `docs/testing/catalog/sweep/stage-X-and-coverage.md`, `docs/testing/catalog/sweep/stages-04-05.md`, `docs/testing/catalog/sweep/stages-07-08-09.md`

### 8.12 Wave 12

- T014 [US2] — subphase: `### 5.1 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — unit harness` — paths: `.github/scripts/control-residue-guard.sh`, `.github/workflows/ci.yml`, `ai-platform-viewer/test/viewer-builds.test.ts`, `ai-platform-viewer/test/clinic-pages.smoke.test.ts`, `ai-platform-viewer/src/lib/issuer-token.ts`, `ai-platform-viewer/src/lib/gateway-api.ts`, `ai-platform-viewer/src/lib/journey-api.ts`, `ai-platform-viewer/src/components/AppShell.tsx`, `ai-platform-viewer/src/lib/routes.ts`, `ai-platform-viewer/src/types.ts`, `ai-platform-viewer/src/components/SideNav.tsx`, `ai-platform-viewer/src/catalog/stage-7-discovery.ts`, `ai-platform-viewer/src/catalog/stage-8-ingress.ts`, `ai-platform-viewer/src/catalog/stage-9-guard.ts`, `ai-platform-viewer/src/catalog/stage-10-stream.ts`, `ai-platform-viewer/src/catalog/stage-11-settlement.ts`, `ai-platform-viewer/src/catalog/stage-12-lookup-support.ts`, `ai-platform-viewer/src/components/Stage8IngressPage.tsx`, `ai-platform-viewer/src/components/JourneyCommandPanel.tsx`, `ai-platform-viewer/src/components/JourneyOperationCard.tsx`, `ai-platform-viewer/src/lib/supabase-api.ts`, `ai-platform-viewer/server/dev-plugin.ts`, `ai-platform-viewer/src/lib/dev-api.ts`, `ai-platform-viewer/src/context/SessionContext.tsx`, `ai-platform/scripts/bootstrap-routing-policy.sh`, `docs/architecture/ai-platform/`, `docs/testing/catalog/`

### 8.13 Wave 13

- T015 [US2] — subphase: `### 6.1 User Story 2 - Dependent paths are cleaned and the residue guard fails closed (Priority: P2) — quickstart` — paths: `specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/quickstart.md`
