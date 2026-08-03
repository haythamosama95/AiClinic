# Quickstart: Control-plane enrollment and installation lifecycle (B2)

Slice **B2** implements the operator-authenticated control plane: enroll, rotate keys, suspend,
resume, and delete for clinic installations. Each mutation writes a `control_audit` row carrying
the operator identity; enroll additionally creates `installation`, `installation_key`, and a
`pending` `entitlement` row with zeroed economics.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. Architecture context

This slice implements delivery-plan row **B2** (*Control-plane enrollment and installation
lifecycle*), which maps to §4.5 and §8.1 of
[`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md) and row B2 of
[`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md).

- The **spec** freezes the installation-lifecycle control-plane surface (five mutations, operator
  identity, audit journaling), the enroll write set (four D1 tables), one-time enrollment, rotation
  overlap, and the `pending` entitlement initial snapshot with zeroed economics.
- The **plan** scopes one new source module (`src/control/`), a `/control` route addition in
  `worker.ts`, a workers-pool integration harness (`vitest.workers.config.ts` + `control.test.ts`),
  and the frozen `contracts/control-plane.md` artifact. No migration, binding, or `wrangler.toml`
  change — B2 writes into the four entities A5 froze.

## 2. What was implemented

- **Five lifecycle handlers** — `ai-platform/src/control/index.ts` exports `handleEnroll`,
  `handleRotate`, `handleSuspend`, `handleResume`, and `handleDelete`. Each consults the
  `OperatorAuth` port, writes the appropriate D1 rows, and journals a `control_audit` row with the
  operator identity.
- **`OperatorAuth` port** — a single-method seam (`resolve(request) → principal | null`) with a
  `defaultOperatorAuth` implementation (Bearer token → `operatorId`). Tests inject a fake returning a
  fixed principal or `null`.
- **`/control` route dispatch** — `ai-platform/src/worker.ts` routes `POST
  /control/installations/{id}/{action}` to `dispatchControlRequest`; `/v1/requests` and `/health`
  are unchanged.
- **`pending` enrollment entitlement** — enroll creates an `entitlement` row with status `pending`,
  zeroed quotas/budgets, empty `allowed_capabilities`, and a closed empty period
  (`period_start = period_end`).
- **Frozen lifecycle contract** — `contracts/control-plane.md` documents the HTTP surface, the five
  `control_audit.action` values, operator-auth rule, entitlement status enum, enroll initial values,
  and rotation overlap invariant for B3/J3/F3 Consumes review.
- **Integration test suite** — `ai-platform/test/control.test.ts` runs seven named tests (T-B2-01
  through T-B2-07) against a real Miniflare D1 with the A5 migration applied.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/control/index.ts` | `OperatorAuth` port, five lifecycle handlers, `dispatchControlRequest` |
| `ai-platform/src/worker.ts` | `/control` route dispatch with operator-auth gating |
| `ai-platform/test/control.test.ts` | T-B2-01..07 integration suite (real Miniflare D1 + fake `OperatorAuth`) |
| `ai-platform/vitest.workers.config.ts` | Scoped `@cloudflare/vitest-pool-workers` pool with ephemeral D1 binding |
| `specs/022-control-plane-enrollment/contracts/control-plane.md` | Frozen HTTP surface, audit vocabulary, entitlement initial values |

## 4. Prerequisites

This slice's tests use the `@cloudflare/vitest-pool-workers` Miniflare D1 pool, not the default
Node-pool config. A one-time `npm install` in `ai-platform/` is required.

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run --config vitest.workers.config.ts test/control.test.ts
```

Expected: **7 passing tests** for this slice only:

| Test name | Asserts |
| --- | --- |
| `enroll_writes_all_four_tables` | Enroll writes all four tables; `pending` entitlement; gateway origin in response |
| `lifecycle_suspend_audit` | Suspend audit + `installation.status = suspended` |
| `lifecycle_resume_audit` | Resume audit + prior active status restored |
| `lifecycle_rotate_audit` | New `kid` row added; previous key remains; rotate audit |
| `lifecycle_delete_audit` | Delete audit + lifecycle-terminal status (no row purge) |
| `non_operator_credentials_rejected` | All five mutations reject without D1 writes |
| `duplicate_enrollment_deterministic` | Second enroll unchanged row count + non-2xx |

To run a single test:

```bash
npx vitest run --config vitest.workers.config.ts test/control.test.ts -t "lifecycle_rotate_audit"
```

## 6. Inspect the changes

Read the frozen control-plane contract:

```bash
cat specs/022-control-plane-enrollment/contracts/control-plane.md
```

Inspect the five `control_audit.action` values in the handlers:

```bash
grep -n "'enroll'\|'rotate'\|'suspend'\|'resume'\|'delete'" \
  ai-platform/src/control/index.ts
```

Read the enroll entitlement initial values (`pending`, zeroed economics):

```bash
grep -n "pending\|request_quota\|allowed_capabilities\|period_start" \
  ai-platform/src/control/index.ts
```

Inspect the `/control` route wiring in the Worker:

```bash
grep -n 'isControlRoute\|dispatchControlRequest\|/control' ai-platform/src/worker.ts
```

List the named test cases:

```bash
grep -n '^describe(' ai-platform/test/control.test.ts
```
