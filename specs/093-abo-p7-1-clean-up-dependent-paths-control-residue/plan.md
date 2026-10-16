# Implementation Plan: Clean-up of dependent paths and the `/control` residue guard

**Branch**: `ai/093-abo-p7-1-clean-up-dependent-paths-control-residue` | **Date**: 2026-10-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

The viewer keeps its clinic capabilities and request pages, drops its control pages and `/control/*` catalog operations, and calls the local platform with issuer tokens from the test issuer key plus `Aip-Contract-Version`. This is phase P7, size S, and **Depends** P3.10 and P4.9.

## Technical Context

**Language/Version**: TypeScript on Node.js >= 22 in `ai-platform-viewer/` (Vite, React, Vitest). The residue guard is a bash script. Docs are markdown.

**Primary Dependencies**: The existing viewer send path: `sendCapabilitiesRequest` in `ai-platform-viewer/src/lib/gateway-api.ts` and `sendJourneyRequest` in `ai-platform-viewer/src/lib/journey-api.ts`. Clinic pages are composed in `AppShell`. No new library. Issuer tokens are minted with WebCrypto Ed25519, which the runtime already provides.

**Storage**: N/A. This unit defines no entities. `ai-platform/scripts/bootstrap-routing-policy.sh` is deleted. The console's class-H routing-policy action replaces it and is not built here.

**Testing**: Two harnesses. Viewer catalog smoke and the viewer build stay in `ai-platform-viewer/` (rule V2). The residue guard is one new CI job (rule V7). Titles start with the E2E id (rule V3). Tests are written to fail before the production changes. The viewer smoke talks to the local platform at `http://127.0.0.1:8787`. It does not boot wrangler and does not run `npm test` in `e2e/fullstack/`.

**Target Platform**: The local platform for clinic pages. CI for the residue guard. The script lives at `.github/scripts/control-residue-guard.sh`, outside the four scanned trees.

**Project Type**: Wiring exception in rule S3: viewer + scripts + docs, plus the CI job that owns the guard. This unit does not change `frontend/`, `backend/`, `abo/`, `packages/vendor-contracts/`, `e2e/fullstack/`, or `ai-platform/` outside `ai-platform/scripts/bootstrap-routing-policy.sh`.

**Performance Goals**: N/A. This unit adds no request path and no new runtime service.

**Constraints**: The guard scans only `ai-platform-viewer/`, `ai-platform/scripts/`, `docs/architecture/ai-platform/`, and `docs/testing/catalog/`. It uses `git ls-files` for those roots, then skips any path with a `migrations` segment, and treats each needle as a literal substring. A file path passed by the job (the temporary fixture) is scanned as that file alone. Needles are `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, and `installation_key`. `specs/`, `ai-platform/` outside `scripts/`, every other docs tree including `docs/architecture/ai-billing-orchestration/` (01–06), `backend/` (tests included), and `frontend/` are not scanned and may still contain those needles. The guard script is outside the four trees, so the needle list it holds is not residue. Untracked `dist/` and `node_modules/` are not in `git ls-files`. The build test runs the same script against the fresh `dist/` so the built bundle is checked without writing a needle into the viewer tree.

**Scale/Scope**: Size S (rule S3: two user stories, the named wiring exception, three E2E ids). Implied task count is 16 (the sequencing below).

Issuer token minted for clinic calls: compact JWT, header `{ alg: "EdDSA", kid, typ: "JWT" }`, payload `iss` `issuer-test` (the local platform `ISSUER_ID`), `aud` `ai-platform`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver` `"2"`. Signed by the test issuer private key. Clinic requests send `Authorization: Bearer <token>` and `Aip-Contract-Version: 1`. The dev plugin stops returning a bearer. `/api/dev/config` returns that test issuer key (kid and private key) from `ai-platform/.dev.vars`, which is outside the scanned trees. The local platform already trusts this test issuer key. This unit does not register it.

`AppShell` after this unit composes only `stage-7` through `stage-12`. Capabilities stay `GET /v1/capabilities` on `/stage-7` through `gateway-api.ts` and `stage-7-discovery.ts`. Request pages stay `/v1/requests` and `/v1/requests/{request_reference}` through those pages' catalogs and `sendJourneyRequest`. Catalog operations whose path contains `/control/` are removed from the pages that stay.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). Spikes are none, so there is no `research.md`. Freezes are none, so there is no `contracts/` directory. The spec defines no entities, so there is no `data-model.md`. The same boxes hold after this plan. This unit adds no constitution violation, so Complexity Tracking stays empty.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  Clinic pages in the viewer call the local platform with issuer tokens. Control pages and the shared bearer leave the viewer. This is a clinic-scale viewer, script, docs, and CI clean-up (spec §4.1, 02 §7 principle I).

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The change is the existing viewer, one deleted script, rewritten docs, and one CI job that runs a shell script. No new worker, queue, or service (02 §7 principle I).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  The viewer owns the remaining clinic-route pages. CI owns the residue guard. This unit adds no Flutter, Supabase, or PostgreSQL behavior (spec §4.1, 02 §7 principle II).

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit defines no tables, constraints, RLS policies, or RPCs. Clinic-side integrity stays where it already is (spec §4.1, 02 §7 principle III).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  Clinic-route pages use issuer tokens from the test issuer key. Viewer smoke tests pass without a bearer token. The guard fails on the five needles inside the four trees (spec §4.1, 02 §7 principle IV).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  Removing control pages does not hard-lock clinical work. The viewer only calls the local platform's clinic routes (spec §4.1, 02 §7 principle V).

| Principle or rule | How this unit complies |
| --- | --- |
| I. Product fit and simplicity | One viewer clean-up, one deleted script, rewritten docs, one CI script. |
| II. Replaceable layer boundaries | Codebases are the viewer, `ai-platform/scripts`, the two doc trees, and CI. |
| III. Backend authority and data integrity | No tables and no RPCs. |
| IV. Secure and human-gated operations | Clinic calls use issuer tokens. The bearer and `/control/*` pages leave the viewer. |
| V. Operational continuity | Clinic pages remain. A negative fixture fails the guard. |
| Workflow automation | The CI job is one script run. No scheduler and no queue. |
| Higher operational burden | No new operational part. The job runs the guard on the four trees. |

## Project Structure

### Documentation (this feature)

```text
specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/
├── plan.md
├── spec.md
├── escalations.md
└── quickstart.md          # after this unit's tests are green; outline below
```

`research.md` is omitted. Spikes are none. `data-model.md` is omitted. The spec defines no entities. `contracts/` is omitted. This unit freezes no wire shape.

`quickstart.md` is not written in this phase. After the harness is green, implement fills only these sections:

- What was implemented, and the files added or modified
- Harness commands for this unit's tests only:
  - From `ai-platform-viewer/`: `npx vitest run test/clinic-pages.smoke.test.ts test/viewer-builds.test.ts`
  - From the repo root: `bash .github/scripts/control-residue-guard.sh ai-platform-viewer ai-platform/scripts docs/architecture/ai-platform docs/testing/catalog`, then the same script on a temporary fixture that contains `/control/` (that run must exit non-zero)
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- Manual step: the local platform is already listening on `http://127.0.0.1:8787` with the test issuer key registered. This unit does not boot wrangler.

### Source Code (repository root)

```text
ai-platform-viewer/src/components/AppShell.tsx
ai-platform-viewer/src/lib/gateway-api.ts
ai-platform-viewer/src/lib/journey-api.ts
ai-platform-viewer/src/lib/issuer-token.ts
ai-platform-viewer/src/catalog/stage-7-discovery.ts
ai-platform-viewer/src/catalog/stage-8-ingress.ts
ai-platform-viewer/src/catalog/stage-9-guard.ts
ai-platform-viewer/src/catalog/stage-10-stream.ts
ai-platform-viewer/src/catalog/stage-11-settlement.ts
ai-platform-viewer/src/catalog/stage-12-lookup-support.ts
ai-platform-viewer/test/clinic-pages.smoke.test.ts
ai-platform-viewer/test/viewer-builds.test.ts
.github/scripts/control-residue-guard.sh
.github/workflows/ci.yml
docs/architecture/ai-platform/
docs/testing/catalog/
```

**Structure Decision**: `AppShell` keeps stages 7–12 and drops every other route. `issuer-token.ts` is reached from `gateway-api.ts` (capabilities) and `journey-api.ts` (request pages). The residue guard is the CI job `control-residue-guard`. `bootstrap-routing-policy.sh` is removed. Superseded docs in the two trees are rewritten in place.

## Consumes Binding

None. P3.10 and P4.9 publish no Outputs / freezes line. This unit does not import or modify their modules.

## Files

| Path | Action | FR |
| --- | --- | --- |
| `ai-platform-viewer/src/lib/issuer-token.ts` | Create. Mint the issuer token described in Technical Context with WebCrypto. Used by the capabilities send and the request send | FR-002 |
| `ai-platform-viewer/src/lib/gateway-api.ts` | Modify. `sendCapabilitiesRequest` sends `GET /v1/capabilities` with the issuer token and `Aip-Contract-Version: 1`. Delete the `/control/token-contract/*` send and the bearer header. Do not call platform enrollment | FR-001, FR-002 |
| `ai-platform-viewer/src/lib/journey-api.ts` | Modify. Clinic `aat` operations send the issuer token and `Aip-Contract-Version: 1`. Remove the bearer branch | FR-001, FR-002 |
| `ai-platform-viewer/src/catalog/stage-7-discovery.ts` | Modify. Capabilities operations stay `GET /v1/capabilities` and use the issuer token | FR-002 |
| `ai-platform-viewer/src/catalog/stage-8-ingress.ts` | Modify. Keep `/v1/requests` operations. They use the issuer token | FR-002 |
| `ai-platform-viewer/src/catalog/stage-9-guard.ts` | Modify. Keep clinic guard operations on `/v1/requests`. Remove bearer wording | FR-001, FR-002 |
| `ai-platform-viewer/src/catalog/stage-10-stream.ts` | Modify. Remove the routing-policy operations whose path contains `/control/`. Keep the clinic stream operations on `/v1/requests` with the issuer token | FR-001, FR-002 |
| `ai-platform-viewer/src/catalog/stage-11-settlement.ts` | Modify. Settlement operations stay on `/v1/requests` and use the issuer token | FR-002 |
| `ai-platform-viewer/src/catalog/stage-12-lookup-support.ts` | Modify. Remove the support operation whose path contains `/control/`. Keep lookup on `/v1/requests/{request_reference}` with the issuer token | FR-001, FR-002 |
| `ai-platform-viewer/src/components/AppShell.tsx` | Modify. Compose only `Stage7DiscoveryPage`, `Stage8IngressPage`, `Stage9GuardPage`, `Stage10StreamPage`, `Stage11SettlementPage`, and `Stage12LookupSupportPage` | FR-001, FR-002 |
| `ai-platform-viewer/src/lib/routes.ts` | Modify. Paths only for `stage-7` through `stage-12`. Default section is `stage-7` | FR-001 |
| `ai-platform-viewer/src/types.ts` | Modify. `NavSection` is only those six sections. Drop the bearer field from `DevConfig` | FR-001, FR-002 |
| `ai-platform-viewer/src/components/SideNav.tsx` | Modify. Nav entries only for stages 7–12. Remove the needle | FR-001 |
| `ai-platform-viewer/src/context/SessionContext.tsx` | Modify. Mint the issuer token for clinic sends. Do not mint through the installation-keypair RPC and do not require a bearer | FR-002 |
| `ai-platform-viewer/src/components/Stage8IngressPage.tsx` | Modify. Remove enrollment-keypair wording. The page still sends `/v1/requests` | FR-001, FR-002 |
| `ai-platform-viewer/src/components/JourneyCommandPanel.tsx` | Modify. Pass the issuer token into `sendJourneyRequest`. Remove the needle | FR-002 |
| `ai-platform-viewer/src/components/JourneyOperationCard.tsx` | Modify. Same issuer-token send. Remove the needle | FR-002 |
| `ai-platform-viewer/src/lib/supabase-api.ts` | Modify. Remove the `installation_key` wording. Clinic request sends do not use it | FR-001 |
| `ai-platform-viewer/server/dev-plugin.ts` | Modify. `/api/dev/config` returns the test issuer key from `ai-platform/.dev.vars` and does not return a bearer. Remove the reset routes that run the SQL files deleted below | FR-001, FR-002 |
| `ai-platform-viewer/src/lib/dev-api.ts` | Modify. Stop calling the installation reset route | FR-001 |
| `ai-platform-viewer/test/clinic-pages.smoke.test.ts` | Create. One test titled `E2E-P7.1-01`. Drives capabilities and the request catalogs against `http://127.0.0.1:8787` | FR-002 |
| `ai-platform-viewer/test/viewer-builds.test.ts` | Modify. One test titled `E2E-P7.1-03`. Runs `npm run build` from `ai-platform-viewer/` and runs the residue-guard script on `dist/`. The test source does not contain the five needles | FR-001 |
| `ai-platform-viewer/test/commercial-pages.smoke.test.ts` | Delete | FR-001 |
| `ai-platform-viewer/test/stage-x.smoke.test.ts` | Delete | FR-001 |
| `ai-platform-viewer/test/helpers/smoke-http.ts` | Delete | FR-001 |
| `ai-platform-viewer/server/reset-clinic-ai-internal.sql` | Delete | FR-001 |
| `ai-platform-viewer/server/reset-installations.sql` | Delete | FR-001 |
| `ai-platform-viewer/server/reset-platform.sql` | Delete | FR-001 |
| `ai-platform-viewer/src/lib/mint-aat.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/lib/platform-enroll.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/lib/platform-installation-api.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/lib/routing-policy-default.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/commercial-plans.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/commercial-usage.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/guard-pipeline.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/stage-0-platform-boot.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/stage-1-token-contract.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/stage-2-clinic-keypair.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/stage-3-platform-installation.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/stage-4-entitlement.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/stage-5-routing-policy.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/stage-5-routing.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/stage-6-mint-aat.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/catalog/stage-x.ts` | Delete | FR-001 |
| `ai-platform-viewer/src/components/SecretsPage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/Stage0PlatformBootPage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/Stage1TokenContractPage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/Stage1CommandPanel.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/Stage2ClinicKeypairPage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/Stage2CommandPanel.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/Stage3PlatformInstallationPage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/Stage3CommandPanel.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/Stage4EntitlementPage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/Stage5RoutingPage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/Stage6MintAatPage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/StageXPage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/UsageGaugePage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/PlansPage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/InvoicesPage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/GuardPipelinePage.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/OperationCard.tsx` | Delete | FR-001 |
| `ai-platform-viewer/src/components/PlatformOperationCard.tsx` | Delete | FR-001 |
| `ai-platform/scripts/bootstrap-routing-policy.sh` | Delete | FR-003 |
| `.github/scripts/control-residue-guard.sh` | Create. Scan the paths it is given. For a directory, scan `git ls-files` under that directory and skip a `migrations` segment. For a file, scan that file alone. Exit non-zero when any needle occurs as a literal substring | FR-005 |
| `.github/workflows/ci.yml` | Modify. Add job `control-residue-guard`. It checks out the repo, runs the script on the four trees, writes a temporary fixture that contains `/control/` outside those trees, and runs the script on that fixture alone. The fixture is not committed. The tree run must pass. The fixture run must fail | FR-005 |
| `docs/architecture/ai-platform/01-ai-platform.md` | Rewrite. Superseded note in entrypoint terms, with links to `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` and `docs/architecture/ai-billing-orchestration/05-abo-operations-and-traceability.md`. None of the five needles | FR-004 |
| `docs/architecture/ai-platform/03-ai-platform-delivery-plan.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/04-ai-platform-operator-runbook.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/06-ai-platform-behavioral-journey.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/07-ai-platform-d1-r2-storage.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/08-ai-platform-data-journey.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/09-ai-platform-request-response-flow.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/arch-vs-source-gap-analysis.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/code-audit-2026-08-21.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/code-audit-2026-08-21-verification.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/request-lifecycle-brief.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/system-testing-plan.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/01-introduction-and-storage-layers.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/02-stage-0-platform-configuration-and-boot.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/03-stage-1-token-contract-baseline.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/04-stage-2-clinic-keypair-enrollment.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/05-stage-3-platform-installation-enrollment.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/06-stage-4-entitlement-and-capability-grants.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/07-stage-5-routing-policy.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/08-stage-6-minting-an-aat.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/09-stage-7-discovery.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/10-stage-8-request-ingress.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/11-stage-9-the-guard.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/12-stage-10-accept-route-invoke-stream.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/13-stage-11-terminal-settlement.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/14-stage-12-lookup-and-support.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/15-alternative-and-failure-journeys.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/16-complete-d1-column-reference.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/17-complete-r2-object-reference.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/18-quota-durable-object-state-reference.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/19-taxonomy-codes-and-http-mapping.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/data-journey/20-source-file-index.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/implementation-references/01-band-a-implementation-reference.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/implementation-references/02-band-b-implementation-reference.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/implementation-references/04-band-d-implementation-reference.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/implementation-references/06-band-f-implementation-reference.md` | Rewrite, same notice | FR-004 |
| `docs/architecture/ai-platform/implementation-references/08-band-j-implementation-reference.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/FIX-WORKLIST.md` | Rewrite, same notice. Stage pages that describe `/control/*` probes are in this set | FR-004 |
| `docs/testing/catalog/README.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/implementation-audit-findings.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/implementation-review-findings.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/implementation-work-order.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/registers.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/remediation-plan.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-00-platform-boot.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-01-token-contract.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-02-clinic-keypair.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-03-installation-enrollment.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-04-entitlement-capability-grants.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-05-routing-policy.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-06-minting-an-aat.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-07-discovery.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-08-request-ingress.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-09-the-guard.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-10-accept-route-invoke-stream.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-11-terminal-settlement.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-12-lookup-and-support.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/stage-X-cron-and-failure-journeys.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/sweep/sql-track.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/sweep/stage-X-and-coverage.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/sweep/stages-04-05.md` | Rewrite, same notice | FR-004 |
| `docs/testing/catalog/sweep/stages-07-08-09.md` | Rewrite, same notice | FR-004 |
| `specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/quickstart.md` | Create after this unit's tests are green | FR-001, FR-002, FR-003, FR-005 |

Pages in the two doc trees that do not contain the five needles stay as they are. `docs/architecture/ai-platform/02-ai-platform-overview.md` is one of those.

Control-only modules that the deleted pages alone import, and that are not in the table above, are deleted in the same change so `npm run build` still typechecks. They are not new modules.

## Test Layout

Viewer tests are Vitest in `ai-platform-viewer/`. The residue guard is the CI job. A row is one test (rule V3). Each new test is red before the production change it names. The clinic smoke does not boot wrangler.

| ID | Title prefix | Entry → chain | Assertion |
| --- | --- | --- | --- |
| E2E-P7.1-01 | `E2E-P7.1-01` | `AppShell` stage-7 `Stage7DiscoveryPage` → `stage-7-discovery.ts` → `sendCapabilitiesRequest`; stages 8–12 → their catalogs → `sendJourneyRequest` → `issuer-token.ts`. Target `http://127.0.0.1:8787` | `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/requests/{request_reference}` are sent with an issuer token and `Aip-Contract-Version: 1`. The local platform accepts those calls. The test does not read a bearer |
| E2E-P7.1-02 | `E2E-P7.1-02` | Job `control-residue-guard` → `.github/scripts/control-residue-guard.sh` on the four trees, then on a temporary fixture | The four-tree scan exits 0. The fixture scan exits non-zero. The fixture is not committed |
| E2E-P7.1-03 | `E2E-P7.1-03` | `npm run build` of `AppShell`, then the guard script on `ai-platform-viewer/dist` | The build completes. The built bundle has no control routes (the guard finds none of the five needles). The viewer smoke file does not read a bearer |

## Sequencing

Tests before implementation. The new tests are observed failing, then the clean-up, then those tests pass. Implied task count: 16.

1. Add the failing `E2E-P7.1-03` test in `viewer-builds.test.ts`.
2. Add the failing `E2E-P7.1-01` test in `clinic-pages.smoke.test.ts`.
3. Add `.github/scripts/control-residue-guard.sh` and the `control-residue-guard` job. Run the script on the four trees and on a temporary fixture that contains `/control/`.
4. Confirm the tree scan fails, the fixture scan fails the guard, and the two viewer tests fail.
5. Add `issuer-token.ts` and point `sendCapabilitiesRequest` and `sendJourneyRequest` at it with `Aip-Contract-Version: 1`.
6. Leave `AppShell` composing only stages 7–12, and drop the other routes from `routes.ts`, `SideNav.tsx`, and `NavSection`.
7. Remove `/control/` operations from the stage 10 and stage 12 catalogs. Strip bearer and enrollment-keypair wording from the clinic pages that stay.
8. Delete the control pages, control catalogs, control smokes, reset SQL, and the control-only libraries listed in Files.
9. Stop the dev plugin and the session from using a bearer. Return the test issuer key from `/api/dev/config`.
10. Delete `ai-platform/scripts/bootstrap-routing-policy.sh`.
11. Rewrite the listed `docs/architecture/ai-platform/` pages so the five needles are gone and each page links to the v2 design.
12. Rewrite the listed `docs/testing/catalog/` pages the same way.
13. Re-run the guard: the four trees pass, and the temporary fixture still fails it.
14. From `ai-platform-viewer/`, re-run `npx vitest run test/clinic-pages.smoke.test.ts test/viewer-builds.test.ts` until `E2E-P7.1-01` and `E2E-P7.1-03` pass. Do not boot wrangler in this step; the local platform is already up.
15. Confirm `AppShell` still opens stages 7–12 and the smoke file does not read a bearer.
16. Write `quickstart.md` from the outline in Project Structure.

## Complexity Tracking

No constitution violation is recorded in 02 §7 for this unit. Nothing to justify.
