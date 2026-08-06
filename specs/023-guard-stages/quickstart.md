# Quickstart: Guard stages — identity, rate limiting, entitlement and kill switches (B3)

Slice **B3** implements the guard stages 2–4: identity verifies the AAT and produces an immutable
request principal; entitlement evaluates AI-enablement, plan tier, capability grant, and all four
kill-switch scopes from the config cache; rate limiting enforces the three composite keys and flushes
rejections to bucketed `platform_counter` rows — never as `ai_request` rows.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. Architecture context

This slice implements delivery-plan row **B3** (*Guard stages: identity, rate limiting, entitlement
and kill switches*), which maps to §4.3.2, §4.2.1, §5.6, §4.3.3, §4.3.4, §4.3.12, §7.5, and §6.1
stages 2–4 of
[`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md) and row B3 of
[`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md).

- The **spec** freezes the token verifier port (enrolled-key strategy, `alg: EdDSA` pin), the
  immutable request principal, guard-stage rejection discipline (bucketed `platform_counter`, no
  `ai_request` rows), and the config-cache read discipline for entitlement and kill-switch
  evaluation — with zero D1 reads on a warm isolate.
- The **plan** scopes three sibling modules (`src/identity/`, `src/entitlement/`,
  `src/rate-limit/`), three test files (24 named tests across unit and integration layers), a
  workers-pool harness extension (`vitest.workers.config.ts`), and two frozen contract artifacts
  (`contracts/token-verifier.md`, `contracts/request-principal.md`). No migration, route, or
  `worker.ts` change — B3 exercises the guard modules directly and does not wire them into the
  request pipeline.

## 2. What was implemented

- **`src/identity/`** — `TokenVerifier` port (`verify(token, ctx) → VerifyResult`), the
  `EnrolledKeyVerifier` strategy (WebCrypto `Ed25519`, `alg` pinned to `EdDSA`, audience/expiry/skew
  checks, key selection by `iss`+`kid` through the config cache), and the immutable `Principal`
  type.
- **`src/entitlement/`** — `evaluateEntitlement` reads AI-enablement, plan tier, capability grant,
  and all four kill-switch scopes (global, capability, installation, provider) from the config cache
  with no D1 read on a warm isolate.
- **`src/rate-limit/`** — three composite keys (`installation`, `installation+actor`,
  `installation+capability`) against the Workers Rate Limiting binding; `rate_limited` rejections
  carry `retry_after`; an in-isolate rejection tally flushes bucketed `platform_counter` rows (never
  one row per event, never journaled as `ai_request`).
- **Frozen contracts** — `contracts/token-verifier.md` and `contracts/request-principal.md` document
  the port wire shape and the principal field set for B4/J4 and downstream pipeline stages.
- **Test suite** — 24 named tests across `identity.test.ts` (11), `entitlement.test.ts` (8), and
  `rate-limit.test.ts` (5), run under the workers-pool Miniflare D1 harness.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/identity/index.ts` | `TokenVerifier` port, `VerifyContext`, `VerifyResult`, `Principal`, `EnrolledKeyVerifier` |
| `ai-platform/src/entitlement/index.ts` | `evaluateEntitlement` — AI-enablement, plan tier, capability grant, four kill-switch scopes |
| `ai-platform/src/rate-limit/index.ts` | Three composite rate-limit keys, `rate_limited` + `retry_after`, bucketed `platform_counter` flush |
| `ai-platform/test/identity.test.ts` | 11 tests: valid token, eight rejection cases, verifier swap, principal immutability, suspended installation |
| `ai-platform/test/entitlement.test.ts` | 8 tests: three `forbidden_capability` cases, four kill-switch cases, warm-isolate zero-D1-read spy |
| `ai-platform/test/rate-limit.test.ts` | 5 tests: three composite-key trips, no `ai_request` row on rejection, bucketed counter flush |
| `ai-platform/vitest.workers.config.ts` | Workers-pool `include` adds the three B3 test files alongside B2's `control.test.ts` |
| `specs/023-guard-stages/contracts/token-verifier.md` | Frozen `TokenVerifier` port wire shape and enrolled-key verification rules |
| `specs/023-guard-stages/contracts/request-principal.md` | Frozen immutable `Principal` field set for downstream pipeline stages |

## 4. Prerequisites

This slice's tests use the `@cloudflare/vitest-pool-workers` Miniflare D1 pool, not the default
Node-pool config. Pass `--config vitest.workers.config.ts` on every run. A one-time `npm install`
in `ai-platform/` is required.

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run --config vitest.workers.config.ts test/identity.test.ts test/entitlement.test.ts test/rate-limit.test.ts
```

Expected: **24 passing tests** for this slice only:

| Test name | File | Asserts |
| --- | --- | --- |
| `identity_valid_token_accepted` | `identity.test.ts` | Valid `EdDSA` AAT verifies and yields an immutable principal |
| `identity_rejects_non_eddsa_alg` | `identity.test.ts` | `none` or HMAC `alg` rejected `unauthenticated` |
| `identity_rejects_bad_signature` | `identity.test.ts` | Bad signature rejected `unauthenticated` |
| `identity_rejects_wrong_audience` | `identity.test.ts` | Wrong `aud` rejected |
| `identity_rejects_expired_token` | `identity.test.ts` | Expired token rejected |
| `identity_accepts_notyetvalid_inside_skew` | `identity.test.ts` | Not-yet-valid token inside skew accepted |
| `identity_rejects_outside_skew` | `identity.test.ts` | Token outside skew rejected |
| `identity_rejects_unknown_issuer` | `identity.test.ts` | Unknown `iss`/`kid` rejected |
| `verifier_swap_changes_no_outcome` | `identity.test.ts` | Swapping verifier implementation changes no outcome |
| `principal_immutable_to_later_stage` | `identity.test.ts` | Later stage cannot mutate the principal |
| `identity_rejects_suspended_installation` | `identity.test.ts` | Suspended installation rejected `installation_suspended` |
| `entitlement_ai_disabled_installation_rejected` | `entitlement.test.ts` | AI-disabled installation rejected `forbidden_capability` |
| `entitlement_plan_tier_too_low_rejected` | `entitlement.test.ts` | Too-low plan tier rejected `forbidden_capability` |
| `entitlement_capability_not_granted_rejected` | `entitlement.test.ts` | Ungranted capability rejected `forbidden_capability` |
| `kill_switch_global_rejected` | `entitlement.test.ts` | Global kill switch rejected `capability_disabled` |
| `kill_switch_capability_rejected` | `entitlement.test.ts` | Capability kill switch rejected `capability_disabled` |
| `kill_switch_installation_rejected` | `entitlement.test.ts` | Installation kill switch rejected `capability_disabled` |
| `kill_switch_provider_rejected` | `entitlement.test.ts` | Provider kill switch rejected `capability_disabled` |
| `entitlement_warm_isolate_no_d1_read` | `entitlement.test.ts` | Warm isolate performs zero D1 reads |
| `rate_limit_installation_key_trips` | `rate-limit.test.ts` | `installation` key overflow rejects `rate_limited` |
| `rate_limit_installation_actor_key_trips` | `rate-limit.test.ts` | `installation+actor` key trips independently |
| `rate_limit_installation_capability_key_trips` | `rate-limit.test.ts` | `installation+capability` key trips independently |
| `rate_limit_rejection_no_ai_request_row` | `rate-limit.test.ts` | Rate-limit rejection creates no `ai_request` row |
| `rate_limit_counters_flush_bucketed` | `rate-limit.test.ts` | Counters flush bucketed, never one row per event |

To run a single test:

```bash
npx vitest run --config vitest.workers.config.ts test/identity.test.ts -t "identity_valid_token_accepted"
```

## 6. Inspect the changes

Read the `TokenVerifier` port and enrolled-key verifier:

```bash
sed -n '12,39p' ai-platform/src/identity/index.ts
```

Grep the `alg` pin to `EdDSA`:

```bash
grep -n 'alg.*EdDSA' ai-platform/src/identity/index.ts
```

Read the frozen contract artifacts:

```bash
cat specs/023-guard-stages/contracts/token-verifier.md
cat specs/023-guard-stages/contracts/request-principal.md
```

Inspect the bucketed counter flush in the rate-limit module:

```bash
grep -n 'platform_counter\|rejectionTally\|flush' ai-platform/src/rate-limit/index.ts
```

List the named test cases:

```bash
grep -n '^describe(' ai-platform/test/identity.test.ts ai-platform/test/entitlement.test.ts ai-platform/test/rate-limit.test.ts
```
