# Quickstart: Token contract rotation with overlapping acceptance (J4)

J4 adds a platform-global D1 `token_contract` accepted-`ver` set, control-plane begin-rotation
and retire writers, and an identity-stage overlapping `ver` check that refuses retired or unknown
contract versions as existing `unauthenticated`. Clinic mint verification confirms single-`ver`
mint from `ai.aat.ver` without re-enrollment.

**Scope rule:** This quickstart covers slice J4 only — its migration, modules, tests, and clinic SQL.

## 1. Architecture context

- **Delivery plan row:** J4 in [`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md) §3.9 — deferred band-J token contract rotation.
- **Architecture sections:** §5.7 (overlapping acceptance), §5.6 (minting `ver` from `ai.aat.ver`),
  §4.5 (control-plane writers), §7.3 (`token_contract` D1 entity).
- **Spec delivered:** platform-global accepted set (one stable, two mid-rotation); begin-rotation /
  retire as only writers; identity accepts every member of the set; retired/unknown →
  `unauthenticated`; clinic issuer mints exactly one `ver` from `ai.aat.ver`; no re-enrollment.
- **Plan scoped:** one D1 migration + seed; config-cache `"token_contracts"` kind; identity check;
  control handlers + routes; Worker `/control` dispatch; Unit + D1 SQL + clinic SQL tests;
  frozen `data-model.md` and `contracts/token-contract-rotation.md`.

## 2. What was implemented

- D1 `token_contract` table with seed `ver = '1'` (no `retire_after` / TTL).
- Config-cache kind `"token_contracts"` and identity accepted-`ver` membership check.
- Control handlers `handleTokenContractBeginRotation` / `handleTokenContractRetire` in
  `src/control/token-contract.ts` with `control_audit` actions
  `token_contract_begin_rotation` / `token_contract_retire`.
- `/control/token-contract/begin-rotation` and `/control/token-contract/retire` routes via
  existing `dispatchControlRequest`.
- Retire takes full effect within one config-cache TTL; safe sequencing is advance-all-clinics →
  wait token lifetime **and** cache TTL → retire (see contract §2.3).
- Clinic SQL coverage for advanced `ai.aat.ver` mint and no-re-enrollment.
- See [`spec.md`](./spec.md) for requirements and [`plan.md`](./plan.md) for file traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/migrations/20260803120000_token_contract.sql` | `token_contract` DDL + seed |
| `ai-platform/schema.snap.sql` | Post-migration DDL snapshot |
| `ai-platform/src/config-cache/index.ts` | `"token_contracts"` kind |
| `ai-platform/src/identity/index.ts` | Accepted-`ver` check after signature path |
| `ai-platform/src/control/token-contract.ts` | Begin-rotation / retire handlers (FR-002 atomic guards) |
| `ai-platform/src/control/index.ts` | Re-exports + `dispatchControlRequest` routes |
| `ai-platform/test/token-contract-rotation.test.ts` | T-J4-01 .. T-J4-03, T-J4-07, Unit T-J4-10 |
| `ai-platform/test/token-contract-control.test.ts` | T-J4-04 .. T-J4-06, D1 T-J4-10, writer/retire/auth/D1-reader cases |
| `backend/tests/ai_token_contract_rotation.sql` | T-J4-08 .. T-J4-10 clinic halves |
| `backend/tests/run_ai_platform_trust_tests.sh` | Registers clinic SQL in trust suite |
| `specs/051-token-contract-rotation/data-model.md` | D1 entity binding |
| `specs/051-token-contract-rotation/contracts/token-contract-rotation.md` | Frozen contract |

## 4. Prerequisites

- Node.js and `npm install` in `ai-platform/` (one time).
- Miniflare D1 workers pool for `token-contract-control.test.ts` (Vitest workers config).
- Local Supabase for `backend/tests/ai_token_contract_rotation.sql` (default port 54322).

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/token-contract-rotation.test.ts
npx vitest run --config vitest.workers.config.ts test/token-contract-control.test.ts
```

Expected: **18 passing tests** in the Worker files (6 Unit + 12 workers-pool).

Clinic SQL (requires local Supabase):

```bash
psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/ai_token_contract_rotation.sql
```

Or via the trust harness entry for this file:

```bash
bash backend/tests/run_ai_platform_trust_tests.sh
```

## 6. Inspect the changes

```bash
grep -R "token_contract" ai-platform/src ai-platform/migrations
grep -E "begin-rotation|token_contract_retire" ai-platform/src/control/index.ts
grep "ai.aat.ver" backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql
```

Confirm retired/unknown `ver` refusal uses existing `unauthenticated` only (no new taxonomy code
in `VerifyResult`).
