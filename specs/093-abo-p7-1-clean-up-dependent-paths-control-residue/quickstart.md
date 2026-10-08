# Quickstart — P7.1 clean-up of dependent paths and the `/control` residue guard

**Unit**: P7.1 · **Branch**: `ai/093-abo-p7-1-clean-up-dependent-paths-control-residue` · **Verification**: T014 (three E2E ids)

## 1. What was implemented

- **Clinic viewer shell (stages 7–12 only)** — `AppShell` composes only `Stage7DiscoveryPage` through `Stage12LookupSupportPage`. `routes.ts`, `SideNav.tsx`, and `NavSection` drop every other route. `DevConfig` has no bearer field (FR-001).
- **Issuer-token sends** — `issuer-token.ts` mints a compact Ed25519 JWT. `sendCapabilitiesRequest` (`gateway-api.ts`) and clinic `sendJourneyRequest` (`journey-api.ts`) send `Authorization: Bearer <issuer token>` and `Aip-Contract-Version: 1` on `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/requests/{request_reference}`. Bearer and `/control/token-contract/*` sends are gone (FR-001, FR-002).
- **Clinic catalogs and pages** — Stage 7–12 catalogs and the remaining clinic pages use the issuer token. Stage 10 and stage 12 lose `/control/` operations. Bearer and enrollment-keypair wording is stripped from the clinic pages that stay (FR-001, FR-002).
- **Control module deletion** — Control pages, catalogs, smokes, reset SQL, and control-only libraries listed in `plan.md` **Files** are deleted so `npm run build` typechecks (FR-001).
- **Dev config and session** — `/api/dev/config` returns the test issuer key from `ai-platform/.dev.vars` and no bearer. `SessionContext` mints the issuer token for clinic sends. Reset routes for the deleted SQL files are removed (FR-001, FR-002).
- **Dependent-path clean-up** — `ai-platform/scripts/bootstrap-routing-policy.sh` is deleted (FR-003). Listed pages under `docs/architecture/ai-platform/` and `docs/testing/catalog/` are rewritten with a superseded note linking to the v2 ABO design; none of the five needles remain (FR-004).
- **Residue guard** — `.github/scripts/control-residue-guard.sh` scans given paths for the literal substrings `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, and `installation_key`. CI job `control-residue-guard` runs the four-tree scan and a temporary fixture outside those trees (FR-005).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `ai-platform-viewer/src/lib/issuer-token.ts` | FR-002 |
| `ai-platform-viewer/src/lib/gateway-api.ts` | FR-001, FR-002 |
| `ai-platform-viewer/src/lib/journey-api.ts` | FR-001, FR-002 |
| `ai-platform-viewer/src/catalog/stage-7-discovery.ts` | FR-002 |
| `ai-platform-viewer/src/catalog/stage-8-ingress.ts` | FR-002 |
| `ai-platform-viewer/src/catalog/stage-9-guard.ts` | FR-001, FR-002 |
| `ai-platform-viewer/src/catalog/stage-10-stream.ts` | FR-001, FR-002 |
| `ai-platform-viewer/src/catalog/stage-11-settlement.ts` | FR-002 |
| `ai-platform-viewer/src/catalog/stage-12-lookup-support.ts` | FR-001, FR-002 |
| `ai-platform-viewer/src/components/AppShell.tsx` | FR-001, FR-002 |
| `ai-platform-viewer/src/lib/routes.ts` | FR-001 |
| `ai-platform-viewer/src/types.ts` | FR-001, FR-002 |
| `ai-platform-viewer/src/components/SideNav.tsx` | FR-001 |
| `ai-platform-viewer/src/context/SessionContext.tsx` | FR-002 |
| `ai-platform-viewer/src/components/Stage8IngressPage.tsx` | FR-001, FR-002 |
| `ai-platform-viewer/src/components/JourneyCommandPanel.tsx` | FR-002 |
| `ai-platform-viewer/src/components/JourneyOperationCard.tsx` | FR-002 |
| `ai-platform-viewer/src/lib/supabase-api.ts` | FR-001 |
| `ai-platform-viewer/server/dev-plugin.ts` | FR-001, FR-002 |
| `ai-platform-viewer/src/lib/dev-api.ts` | FR-001 |
| `ai-platform-viewer/test/clinic-pages.smoke.test.ts` | FR-002 |
| `ai-platform-viewer/test/viewer-builds.test.ts` | FR-001 |
| `.github/scripts/control-residue-guard.sh` | FR-005 |
| `.github/workflows/ci.yml` | FR-005 |
| `ai-platform/scripts/bootstrap-routing-policy.sh` (delete) | FR-003 |
| `docs/architecture/ai-platform/` (listed pages rewritten) | FR-004 |
| `docs/testing/catalog/` (listed pages rewritten) | FR-004 |
| `specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/quickstart.md` | FR-001, FR-002, FR-003, FR-005 |

Deleted viewer control modules (pages, catalogs, smokes, reset SQL, and control-only libraries) are listed in `plan.md` **Files**; they are not duplicated here.

## 3. Harness commands (this unit only)

### 3.1 Residue guard (E2E-P7.1-02)

From the repo root:

```bash
bash .github/scripts/control-residue-guard.sh ai-platform-viewer ai-platform/scripts docs/architecture/ai-platform docs/testing/catalog
```

Then run the same script on a temporary fixture that contains `/control/` outside those four trees (that run must exit non-zero; do not commit the fixture):

```bash
echo '/control/' > /tmp/p71-control-fixture.txt
bash .github/scripts/control-residue-guard.sh /tmp/p71-control-fixture.txt
```

**T014 result:** the four-tree scan exited 0. The fixture scan exited non-zero.

### 3.2 Viewer tests (E2E-P7.1-01, E2E-P7.1-03)

From `ai-platform-viewer/`:

```bash
npx vitest run test/clinic-pages.smoke.test.ts test/viewer-builds.test.ts
```

To run only the build test:

```bash
npx vitest run test/viewer-builds.test.ts -t "E2E-P7.1-03"
```

**T014 result:** `npx vitest run test/viewer-builds.test.ts -t "E2E-P7.1-03"` passed.

**E2E-P7.1-01 not executed:** `ai-platform-viewer/test/clinic-pages.smoke.test.ts` was not run because the local platform stack was not listening on `http://127.0.0.1:8787` and this workflow does not boot wrangler. Do not run `npm test` in `e2e/fullstack`.

### 3.3 Manual prerequisite (E2E-P7.1-01 only)

Before running the clinic smoke, the local platform must already be listening on `http://127.0.0.1:8787` with the test issuer key registered. This unit does not boot wrangler.

## 4. Entry point → module chain (E2E ids)

| ID | Chain |
| --- | --- |
| E2E-P7.1-01 | `AppShell` stage-7 `Stage7DiscoveryPage` → `stage-7-discovery.ts` → `sendCapabilitiesRequest` → `issuer-token.ts`; stages 8–12 → their catalogs → `sendJourneyRequest` → `issuer-token.ts`. Target `http://127.0.0.1:8787`. `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/requests/{request_reference}` are sent with an issuer token and `Aip-Contract-Version: 1`. The test does not read a bearer |
| E2E-P7.1-02 | Job `control-residue-guard` in `.github/workflows/ci.yml` → `.github/scripts/control-residue-guard.sh` on `ai-platform-viewer`, `ai-platform/scripts`, `docs/architecture/ai-platform`, and `docs/testing/catalog`, then on a temporary fixture outside those trees. The four-tree scan exits 0; the fixture scan exits non-zero |
| E2E-P7.1-03 | `npm run build` of `ai-platform-viewer/` (`AppShell` bundle) → `.github/scripts/control-residue-guard.sh` on `ai-platform-viewer/dist`. The build completes and the built bundle contains none of the five needles. The test source does not read a bearer |
