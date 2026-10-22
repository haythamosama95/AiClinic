# Stage 3 Second-Round Review — Value Command Conservation (RM14–RM21)

Branch `ai/abo-remediation` (tip `6cae8104`) compared with `master`. Light, read-only pass: one targeted spot-check per requirement against the plan's §4.3 and the per-phase records `RM14.md`–`RM21.md`. No `RMxx.todo.md` files exist for this range.

## 1. Summary

- **RM status:** 8 HANDLED, 0 PARTIAL, 0 NOT HANDLED, 0 REGRESSED.
- **Findings:** 0 Critical, 0 Major.
- **Verdict:** **PASS**

Later phases RM28 and RM32 changed `abo/src/work/reversal.ts`, and RM20 changed `applyGrantRPC` and `routePendingGrantClaim`. I re-read those paths at the tip. RM21's parent-cumulative gating and RM14/RM15's seal and atomic commit are still in place.

## 2. Phase verification

| RM | Requirement | Status | Evidence |
|---|---|---|---|
| RM14 | R4-PG1: global `grant_claim` binding org, source, envelope/hash and route (installation/epoch/generation). Identity is immutable and rows cannot be deleted. | HANDLED | `ai-platform/migrations/20261019120000_r4_pg1_global_grant_claims.sql:5-55` |
| RM14 | R4-PG1: an authenticated exact replay of a completed claim returns the original receipt. A changed org or envelope conflicts. | HANDLED | `ai-platform/src/vendor/entrypoint.ts:4755-4768` (`claimReplayResult`), `:1195-1214` |
| RM14 | R4-PG1: a pending claim moves only after the old DO returns a no-effect seal. The move is a compare-and-swap on route and generation. | HANDLED | `entrypoint.ts:1217-1304`; DO `sealGrantRouteRPC` `ai-platform/src/quota-do/coverage.ts:213-257` |
| RM14 | R4-PG1: a sealed DO refuses any later apply of that grant. | HANDLED | `coverage.ts:2100-2108` (`route_sealed` / conflict) |
| RM14 | R4-PG1: the backfill fails closed under D-5. | HANDLED | `entrypoint.ts:878-938` (`ensureGrantClaimsBackfilled` returns false or raises a dispute alert; no winner is picked) |
| RM14 | R4-PG2: DO calls go through the RM07 decoder. A version refusal is classified separately; transport or unknown outcomes are transient. | HANDLED | `entrypoint.ts:22`, `:1505-1525` |
| RM15 | R4-D1: term writes, hot state, `grant` row, signed receipt and ordered final-state events commit in one `transactionSync`. Paid velocity is moved to the outbox. | HANDLED | `coverage.ts:1558-1745` (`finalizeGrantApply`; events at `:1607-1627`, transaction at `:1707`, velocity outbox at `:1688-1693`) |
| RM15 | R4-D4: the alarm is armed before commit, and `syncAlarm` repairs a missing or late alarm via `getAlarm()`. | HANDLED | `coverage.ts:1439-1462`, `:1702` |
| RM16 | R4-A1: append-only `grant_outcome_event`, legacy table preserved, one-row compatibility view (first terminal event, else latest). | HANDLED | `abo/migrations/0014_grant_outcome_events.sql:1-53` |
| RM16 | R4-A2: org, grant ID and source kind/ref are bound before platform dispatch. | HANDLED | `abo/src/ops/index.ts:4247-4254` |
| RM16 | R4-A2: one shared receipt validator (schema, signature, request linkage, contract version, `applied`, term IDs, ledger sequence), used by both paid and complimentary paths. | HANDLED | `abo/src/work/grant-receipt.ts:53-85`; used at `ops/index.ts:3741`, `work/grant.ts:11` |
| RM16 | R4-A2: the request is persisted before dispatch. An invalid receipt parks the command with AL-07 and writes no terminal outcome. | HANDLED | `ops/index.ts:3596-3648`, `:3740-3765` |
| RM17 | R4-PG3: the accepted command, signer, challenge hashes, plan snapshot and lease/due fields are stored on the claim. | HANDLED | `ai-platform/migrations/20261019130000_r4_pg3_accepted_grant_commands.sql:1-24`; insert at `entrypoint.ts:1075-1109` |
| RM17 | R4-PG3: a bounded dispatcher runs on the five-minute cron and resumes only exact stored bytes. | HANDLED | `entrypoint.ts:7582-7627`, `:4715-4728`; `ai-platform/src/worker.ts:3027` |
| RM17 | R4-PG4: attribution uses the verified signer, and the operator email flows into the ledger outbox. | HANDLED | `entrypoint.ts:4926`, `:5627`; `coverage.ts:1646-1647` |
| RM18 | R4-D5: per-org claim table. A trigger reserves capacity, counting pending claims of any age plus applied claims inside the window. | HANDLED | `ai-platform/migrations/20261019140000_rm18_complimentary_ceiling_claims.sql:5-89` |
| RM18 | R4-D5: a pending claim is released only on a verified original-route `sealed_no_effect` receipt. | HANDLED | `entrypoint.ts:1392-1444`; DO refuses sealed claims at `coverage.ts:2110-2118` |
| RM18 | R4-D5: the installation-local window sum is removed from `grantExceedsCeiling`. | HANDLED | `coverage.ts:1521-1540` (per-grant caps only) |
| RM18 | R8-CEILING1: the policy version comes from `COALESCE(MAX)+1` in a single statement, batched with the command record and assertion use. | HANDLED | `entrypoint.ts:4512-4560`; table at migration `:91-116` |
| RM19 | R6-DM3: reversal, release and manual void prepare events and receipt first, then commit inside `transactionSync`, with replay checks. | HANDLED | `coverage.ts:2622-2856` (transaction at `:2828-2842`); release/void transactions at `:3027`, `:3287`, `:3431` |
| RM19 | R6-DM5: both suspend and resume emit `suspension_changed`; a no-change toggle emits nothing. | HANDLED | `coverage.ts:2414-2439` |
| RM20 | R6-PT1: `live_value_route`, `reversal_command` and `grant_tombstone` tables, all immutable. | HANDLED | `ai-platform/migrations/20261019150000_r6_pt1_reversal_routes.sql:5-103` |
| RM20 | R6-PT1: a reversal of an unseen grant writes a terminal tombstone, and later claims are blocked. | HANDLED | `entrypoint.ts:6030-6090`; claim insert guards at `:1086`, `:1123` |
| RM20 | R6-PT1: the DO checks exact route, epoch, generation and `voiding` state, and seals the grant when no term exists. | HANDLED | `coverage.ts:2654-2737` |
| RM20 | R6-PT1: failed R2 exports are retried on the cron. | HANDLED | `entrypoint.ts:7637-7651` (`shipDueReversalExports`) |
| RM21 | R6-BR1: only inquiry paths record reversals. A full reversal needs authenticated parent cumulative evidence; anything else is `review_partial`. | HANDLED | Callers at `abo/src/work/runner.ts:1300`, `sweep.ts:322`, `:443`, `rebuild.ts:1157` (all `"inquiry"`); `reversal.ts:341-348`, `:787-788`; `adapter.ts:669-684` |
| RM21 | R6-BR3: the provider kind is persisted, and a kind conflict raises a finding plus an alert. | HANDLED | `reversal.ts:764-785`, `:652-686` |
| RM21 | R6-BR2: reversal activity no longer suppresses the six-hour inquiries. | HANDLED | `abo/src/work/sweep.ts:674-700` (no reversal exclusion) |
| RM21 | R8-RETRY1: the immutable `reversal_request` is reused on retry; legacy rows return 409. | HANDLED | `abo/migrations/0015_reversal_request.sql:1-23`; `ops/index.ts:3296-3306` |

## 3. Critical findings

No Critical findings.

## 4. Major findings

No Major findings.

## 5. Could not verify

- **RM17 R4-PG4 step 3 (historical attribution correction):** deferred by design to operator reconciliation, because it needs production D1/R2 data. This is not a code gap.
- **RM18 recovered-envelope addendum:** assigned to RM29 by the plan (§4.3.5 notes), so it is out of scope here.
- **RM14 `routePendingGrantClaim` batch (`entrypoint.ts:1281-1302`):** the `live_value_route` UPDATE is not explicitly conditioned on the `grant_claim` UPDATE having matched. Both statements compare-and-swap on the same old installation and generation, and the preceding DO seal blocks a concurrent apply. Because of that, I could not build a failing scenario in this light pass. A deeper audit could confirm that claim and route generations never diverge.
- I did not run tests. The per-phase records cite green CI runs, which I did not re-check.
