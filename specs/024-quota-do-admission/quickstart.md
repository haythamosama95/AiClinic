# Quickstart: Quota Durable Object and admission stage (B4)

Slice **B4** adds the platform's only stateful side-car — the per-installation Quota Durable Object —
and the pipeline's stage-8 admission call and stage-15 credit call that use it. One admission round
trip answers `jti` freshness, idempotency novelty, remaining budget, and concurrency headroom; a
separate credit call settles actual usage after the request completes.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. Architecture context

This slice implements delivery-plan row **B4** (*Quota Durable Object and admission stage*), which
maps to §4.3.3, §4.4, §9.17, §7.7, §6.1 stage 8, §6.2, and §6.6 of
[`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md) and row B4 of
[`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md)
(§3.3). It is sequenced after slices A5 and B3 and precedes C3 — admission is the last gate before
the journal writer's stage 9.

- The **spec** freezes the per-installation Quota Durable Object contract, the stage-8 admission RPC
  (one round trip for `jti` replay, idempotency, budget, and concurrency), the stage-15 credit RPC,
  the in-object ephemeral store with in-place expiry, and the capped fail-open grace policy for Quota
  DO unavailability (Open Decision 3).
- The **plan** scopes `src/quota-do/` (DO handlers), `src/admission/` (stage-8 caller with
  fail-open grace path), `src/credit/` (stage-15 caller), a `GatewayObject` fetch/rpc extension in
  `worker.ts`, two test files (16 named tests across DO unit, concurrency, and integration-spy
  layers), and the frozen contract artifact `contracts/quota-do-rpc.md`.

## 2. What was implemented

- **`src/quota-do/`** — `admissionRPC` and `creditRPC` handlers over the per-installation DO state:
  `jti` replay check, idempotency lookup, budget and concurrency enforcement, period-counter
  adjustment (including partial usage), and a lazy sweep that evicts expired ephemeral entries on
  each admission call (no `alarm()` handler).
- **`src/admission/`** — Stage-8 caller: loads the entitlement snapshot through A5's
  `loadConfig`, builds the admission RPC payload from the verified `Principal` and parsed
  idempotency key, invokes `env.DO` once per request, and implements the capped fail-open grace
  path with later reconciliation when the Quota DO is unreachable.
- **`src/credit/`** — Stage-15 caller: invokes the same DO instance once with actual token/cost
  usage and a `partial` flag; drains pending grace admissions for reconciliation.
- **`worker.ts` extension** — `GatewayObject.fetch` dispatches on the RPC `kind` discriminant to
  `admissionRPC` / `creditRPC`; the A1 `DO → GatewayObject` binding is unchanged.
- **Frozen contract** — `contracts/quota-do-rpc.md` documents the admission and credit RPC wire
  shapes and the in-object ephemeral entry shape for downstream slices.
- **Test suite** — 16 named tests: 10 in `quota-do.test.ts` (DO unit + concurrency) and 6 in
  `admission-credit.test.ts` (integration spy), run under the workers-pool Miniflare DO binding.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/quota-do/index.ts` | `admissionRPC`, `creditRPC`, ephemeral entry types, lazy sweep, `CONCURRENCY_LIMIT` / `EPHEMERAL_HORIZON_MS` |
| `ai-platform/src/admission/index.ts` | Stage-8 caller: entitlement snapshot load, one DO fetch per request, fail-open grace path, rejection tally |
| `ai-platform/src/credit/index.ts` | Stage-15 caller: credit RPC with actual/partial usage, grace reconciliation drain |
| `ai-platform/src/worker.ts` | `GatewayObject` fetch/rpc dispatch to `admissionRPC` / `creditRPC` |
| `ai-platform/test/quota-do.test.ts` | 10 tests: admission (fresh/replay `jti`, idempotency, budget, concurrency), credit (actual/partial), parallel admissions, ephemeral expiry |
| `ai-platform/test/admission-credit.test.ts` | 6 tests: one DO fetch per request, idempotent replay, expired-token rejection, capped grace, grace reconciliation, rejection counted not journaled |
| `specs/024-quota-do-admission/contracts/quota-do-rpc.md` | Frozen admission and credit RPC request/response shapes and ephemeral entry shape |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/quota-do.test.ts test/admission-credit.test.ts
```

Expected: **16 passing tests** for this slice only (10 in `quota-do.test.ts`, 6 in
`admission-credit.test.ts`).

| Test name | File | Asserts |
| --- | --- | --- |
| `admission_fresh_jti_accepted` | `quota-do.test.ts` | A previously-unseen `jti` is admitted as fresh |
| `admission_repeated_jti_rejected` | `quota-do.test.ts` | A `jti` already seen for this installation is rejected as a replay |
| `admission_new_idempotency_key_accepted` | `quota-do.test.ts` | A previously-unseen idempotency key is accepted as new |
| `admission_repeat_idempotency_key_returns_prior_record` | `quota-do.test.ts` | A repeat idempotency key returns the existing request's state |
| `admission_budget_exhaustion_rejected` | `quota-do.test.ts` | An installation with no remaining budget is rejected `quota_exhausted` |
| `admission_concurrency_ceiling_rejected` | `quota-do.test.ts` | An installation at its in-flight concurrency ceiling is rejected |
| `credit_adjusts_counters_with_actual_usage` | `quota-do.test.ts` | A completed request's credit call adjusts period counters by actual usage |
| `credit_adjusts_counters_with_partial_usage` | `quota-do.test.ts` | A cancelled request's partial usage is credited |
| `parallel_admissions_exact_final_count` | `quota-do.test.ts` | N parallel admissions against one installation produce an exact final count |
| `ephemeral_entries_expire_in_place` | `quota-do.test.ts` | `jti` replay and idempotency records expire in place at the ephemeral horizon |
| `admission_exactly_one_do_fetch_per_request` | `admission-credit.test.ts` | The pipeline stage makes exactly one Durable Object fetch per request |
| `admission_repeated_key_no_second_inference` | `admission-credit.test.ts` | A repeated idempotency key returns the original state and starts no second inference |
| `admission_expired_token_same_key_unauthenticated` | `admission-credit.test.ts` | An expired token with the same idempotency key is rejected `unauthenticated` |
| `quota_do_unavailable_capped_grace_then_rejection` | `admission-credit.test.ts` | Quota DO unavailability serves under a capped grace allowance, then rejects when the cap is exhausted |
| `grace_usage_reconciled_afterwards` | `admission-credit.test.ts` | Usage admitted under the fail-open cap is reconciled against the DO's counters afterwards |
| `admission_rejection_counted_not_journaled` | `admission-credit.test.ts` | An admission rejection is tallied to bucketed `platform_counter` and creates no `ai_request` row |

To run a single test:

```bash
npx vitest run test/quota-do.test.ts -t "admission_fresh_jti_accepted"
```

## 5. Inspect the changes

Read the frozen RPC contract:

```bash
cat specs/024-quota-do-admission/contracts/quota-do-rpc.md
```

Grep the `GatewayObject` dispatch in `worker.ts`:

```bash
grep -n 'admissionRPC\|creditRPC\|GatewayObject' ai-platform/src/worker.ts
```

Inspect the Quota DO handlers and ephemeral sweep:

```bash
grep -n 'admissionRPC\|creditRPC\|sweepEphemeral\|EPHEMERAL_HORIZON' ai-platform/src/quota-do/index.ts
```

Inspect the fail-open grace path in the admission caller:

```bash
grep -n 'GRACE_ADMISSION_CAP\|grace\|reconcil' ai-platform/src/admission/index.ts
```

List the named test cases:

```bash
grep -n '^describe(' ai-platform/test/quota-do.test.ts ai-platform/test/admission-credit.test.ts
```

Run a focused test file:

```bash
npx vitest run test/quota-do.test.ts
npx vitest run test/admission-credit.test.ts
```
