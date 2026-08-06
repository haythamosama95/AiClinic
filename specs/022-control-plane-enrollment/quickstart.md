# Quickstart: Control-plane enrollment and installation lifecycle (B2)

Slice **B2** implements the operator-authenticated control plane: enroll, rotate keys, suspend,
resume, and delete for clinic installations. Each mutation writes a `control_audit` row carrying
the stable operator id (`OPERATOR_ID`); enroll additionally creates `installation`,
`installation_key`, and a `pending` `entitlement` row with zeroed economics.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. Architecture context

This slice implements delivery-plan row **B2** (*Control-plane enrollment and installation
lifecycle*), which maps to §4.5 and §8.1 of
[`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md) and row B2 of
[`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md).

- The **spec** freezes the installation-lifecycle control-plane surface (five mutations, verifying
  operator auth, audit journaling), the enroll write set (four D1 tables), one-time enrollment,
  rotation overlap, lifecycle FSM terminal rules, and the `pending` entitlement initial snapshot.
- The **plan** scopes sibling modules under `src/control/` (barrel `index.ts`), `/control` route
  wiring with `OPERATOR_BEARER_TOKEN` + `OPERATOR_ID`, a workers-pool harness, and
  `contracts/control-plane.md`. No A5 migration edit — `UNIQUE(org_id)` on `installation` is a known
  A5 follow-up.

## 2. What was implemented

- **Five lifecycle handlers** — `ai-platform/src/control/lifecycle.ts` (`handleEnroll`,
  `handleRotate`, `handleSuspend`, `handleResume`, `handleDelete`). Each consults `OperatorAuth`,
  validates payloads / FSM, writes D1 in a batch (audit inlined), and maps UNIQUE failures to contract
  §2.4 codes. Barrel: `ai-platform/src/control/index.ts`.
- **`createSecretOperatorAuth`** — `ai-platform/src/control/auth.ts`: timing-safe Bearer compare
  against a configured secret; returns configured `operatorId` (never the credential); fail-closed if
  secret or id empty. Tests inject a fake `OperatorAuth`; e2e uses Miniflare bindings.
- **`/control` route dispatch** — `worker.ts` builds auth from Env and passes it explicitly to
  `dispatchControlRequest` (no default). `/v1/requests` and `/health` unchanged.
- **`pending` enrollment entitlement** — enroll creates `entitlement` with status `pending`, zeroed
  quotas/budgets, empty `allowed_capabilities`, closed empty period.
- **Frozen lifecycle contract** — `contracts/control-plane.md` (routes, actions, secret auth, FSM,
  rejection table, entitlement enum/initial values, rotation overlap).
- **Integration suite** — `test/control.test.ts`: T-B2-01..07 plus review-resolution cases (secret
  auth, route e2e, illegal transitions, entitlement unchanged, payload/kid/json/route/not-found).

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/control/lifecycle.ts` | Five lifecycle handlers, FSM, payload/D1 error mapping |
| `ai-platform/src/control/auth.ts` | `createSecretOperatorAuth` |
| `ai-platform/src/control/index.ts` | Barrel + `dispatchControlRequest` / `isControlRoute` |
| `ai-platform/src/worker.ts` | Env → secret auth → `/control` dispatch |
| `ai-platform/test/control.test.ts` | T-B2-01..07 + review-resolution cases |
| `ai-platform/vitest.workers.config.ts` | Workers pool; Miniflare `DB` + `OPERATOR_*` |
| `specs/022-control-plane-enrollment/contracts/control-plane.md` | Frozen contract |

## 4. Prerequisites

This slice's tests use the `@cloudflare/vitest-pool-workers` Miniflare D1 pool. A one-time
`npm install` in `ai-platform/` is required.

### 4.1 Operator auth Env (local Worker / deploy)

| Binding | Kind | Purpose |
| --- | --- | --- |
| `OPERATOR_BEARER_TOKEN` | secret | Bearer credential verified by timing-safe compare |
| `OPERATOR_ID` | var (`wrangler.toml` `[env.*.vars]`) | Stable id journaled in `control_audit` |

```bash
cd ai-platform
# Per environment (development | staging | production):
npx wrangler secret put OPERATOR_BEARER_TOKEN --env development
# OPERATOR_ID is already set in wrangler.toml vars (e.g. platform-operator)
```

Do **not** put the bearer token in committed config. Empty secret or empty `OPERATOR_ID` fail-closes
all `/control` mutations (`401 unauthorized`).

Vitest Miniflare bindings supply test values in `vitest.workers.config.ts` for
`control_route_end_to_end`.

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run --config vitest.workers.config.ts test/control.test.ts
```

Expected: all cases in `test/control.test.ts` passing (T-B2-01..07 plus review-resolution describes):

| Test name | Asserts |
| --- | --- |
| `enroll_writes_all_four_tables` | Enroll writes all four tables; `pending` entitlement; gateway origin |
| `lifecycle_suspend_audit` | Suspend audit + `installation.status = suspended` |
| `lifecycle_resume_audit` | Resume audit + prior active status restored |
| `lifecycle_rotate_audit` | New `kid` row added; previous key remains; rotate audit |
| `lifecycle_delete_audit` | Delete audit + `status === "deleted"` |
| `non_operator_credentials_rejected` | `401 unauthorized` on all five; no D1 writes |
| `duplicate_enrollment_deterministic` | `409 already_enrolled`; unchanged row counts |
| `secret_operator_auth_verifies_credential` | Secret scheme; never journals credential |
| `control_route_end_to_end` | `SELF.fetch` route → D1; journals `OPERATOR_ID` |
| `lifecycle_illegal_transitions` | Five illegal FSM cases → `409 illegal_lifecycle_transition` |
| `suspend_resume_entitlement_unchanged` | Entitlement row unchanged |
| `duplicate_enrollment_same_org_different_installation` | Same org, different id → `409` |
| `enroll_invalid_payload` | `400 invalid_payload` |
| `rotate_duplicate_kid` | `409 duplicate_kid` |
| `enroll_invalid_json` | `400 invalid_json` |
| `invalid_route_rejected` | `400 invalid_route` |
| `installation_not_found` | `404 installation_not_found` |

To run a single test:

```bash
npx vitest run --config vitest.workers.config.ts test/control.test.ts -t "lifecycle_rotate_audit"
```

## 6. Inspect the changes

Read the frozen control-plane contract:

```bash
cat specs/022-control-plane-enrollment/contracts/control-plane.md
```

Inspect lifecycle + auth modules:

```bash
grep -n "illegal_lifecycle_transition\|createSecretOperatorAuth\|invalid_payload\|duplicate_kid" \
  ai-platform/src/control/lifecycle.ts ai-platform/src/control/auth.ts
```

Inspect Worker Env wiring:

```bash
grep -n 'createSecretOperatorAuth\|OPERATOR_BEARER_TOKEN\|OPERATOR_ID\|dispatchControlRequest' \
  ai-platform/src/worker.ts
```

List named test describes:

```bash
grep -n '^describe(' ai-platform/test/control.test.ts
```
