# CI Failure Analysis — Run 38695681551

- **Repo:** `haythamosama95/AiClinic` · branch `ai/abo-master` · commit `953e5e6e`
- **Campaign:** [38695681551](https://github.com/haythamosama95/AiClinic/actions/runs/38695681551) — **123 failures**
- **Downloaded artifacts:** `C:\Users\haosama\AppData\Local\Temp\ci-artifacts2\new1\`
  - `campaign-ai-platform-38695681551\`, `campaign-frontend-38695681551\`, `campaign-abo-38695681551\`, `campaign-e2e-fullstack-38695681551\`, `campaign-vendor-contracts-38695681551\`, `campaign-backend-38695681551\`, `campaign-ops-launch-38695681551\`
- **Sources:** `vitest-report.json`, `summary.json`, per-test logs, and `output.log` inside the campaign artifacts

> **One root cause drives 70 of the 123 failures (57%): a D1 schema drift — the worker
> queries a column `request_fingerprint` that doesn't exist in the migrated schema.**

---

## ai-platform/e2e — 11 failures

| Test | Why it fails |
|---|---|
| S09-068 — idempotent replay after failed | `expected 409 to be 200` — replay returns Conflict instead of stored answer |
| S09-069 — idempotent replay after cancelled | `expected 409 to be 200` — same replay bug |
| S10-018 — idempotent replay of a failed prior request | `expected 409 to be 200` |
| S10-019 — idempotent replay of a cancelled prior request | `expected 409 to be 200` |
| S10-016 — idempotent replay of completed prior returns placeholder | `expected 409 to be 200` |
| S11-013 — idempotent replay after Completed | `expected 409 to be 200` |
| S11-014 — idempotent replay after Failed | `expected 409 to be 200` |
| S11-015 — idempotent replay after Cancelled | `expected 409 to be 200` |
| S10-001 — single-target chain success settles completed | `expected null to be 'request/55a2ff13…'` — request ref never written (waitUntil credit race) |
| S11-002 — Ledger cost from pricing table | `expected [] to have a length of 1` — usage_event row missing at read time |
| S11-010 — Cancel after truncation fallback | `R2 object not found: null` — envelope not written before read |

---

## ai-platform/npm-test — 81 failures

**66 of them fail with the identical error:**
`D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR`.
Every admission/credit/journal test hits it — the DO admission path queries a column the
applied migrations never created. Full list:

```text
makes exactly one Durable Object fetch per pipeline admission call
returns idempotent priorState with one DO fetch per call and no duplicate inference
rejects unauthenticated when the token expired outside skew before idempotency replay
admits under grace for 5 calls then rejects when DO stays unavailable
rejects at the fallback cap with coverage_unknown while entitlement budget remains
rejects a sixth grace admit after isolate maps are wiped because D1 pending count holds the cap
returns the same graceRequestId and keeps a single pending D1 row
rejects quota_exhausted when request_quota is already 0 on the entitlement snapshot
rejects coverage_unknown when mirror fallback is unavailable
settles pending fallback_admission via settleFallback on the five-minute drain
keeps pending fallback rows when settleFallback is skipped
tallies allowance_exhausted to bucketed platform_counter without an ai_request row
rejects a repeated jti as replay without an ai_request row
maps concurrency_exhausted onto concurrency_limited and tallies that code
tallies fallback-cap rejection as coverage_unknown, not quota_exhausted
rejects coverage_lapsed on config-cache miss instead of throwing or grace
does not invoke credit or write ai_request when credit budget is exhausted at admission
makes exactly two DO fetches for admission then credit
writes client-supplied conversation_id and turn_ordinal on each conversational leg
returns all legs ordered by turn_ordinal via listConversationLegs
produces N admissions and N usage credits for N legs
credits a leg terminating as AwaitingContext with actual usage
has no conversation entity table and only ordinary ai_request rows
holds no conversation state between terminal leg 1 and leg 2 submit
writes one R2 object and one DO fetch per leg
writes null conversation_id and turn_ordinal for single_shot rows
writes conversation_id and turn_ordinal when runGuard receives a conversational body
stage 8 — quota exhausted → quota_exhausted; no journal
stage 8 — duplicate idempotency key → idempotent success with priorState
stage 9 — journals resolvePromptVersion into prompt_artifact_hash, not the artifact ref
stage 9 — D1 insert failure → internal_error + release; key reusable
stage 10 — compose failure → Failed terminal + internal_error
threads validatedTranscript into composeRequest and GuardSuccess
passes streamFlag true and the request deadline into composeRequest
returns routingTier degraded on GuardFreshSuccess after usage crosses soft_threshold
admits with degraded flag, routes degraded tier, and emits degraded_notice
returns quota_exhausted with period_reset and does not journal an AI request
keeps standard tier without degraded_notice below the soft threshold
writes degraded and standard routing_tier via createRequestRow
uses exactly one Quota DO fetch for soft-threshold admission
emits only quota_exhausted from hard exhaustion and no error on soft path
keeps standard routing when soft_threshold is 0 with positive budgets
crosses soft threshold on creditsUsed / credit_budget and routes degraded  (×2 tests)
keeps standard tier at 79/100 just below the >= soft boundary
T23 — live route is not the missing-eventSource 503 shell
T1 — accepted, fake chunks, exactly one completed
journals promptVersion content hash into prompt_artifact_hash, not the ref (4.4)
T2 — one journal insert before provider work
T3 — exactly one R2 envelope after terminal
stores a non-empty raw provider body per attempt in the envelope
prices ai_attempt.cost and usage_event.cost from the same helper
journals term_id from admission, not an entitlement period string
T4 — admit + credit only
T15 — repeated key returns prior state
T20 — provider_unavailable as one failed terminal
writes a diagnostic attempt row when routing yields an empty chain
T21 — validation_failed as one failed terminal
fails validation_failed when the model opens with a refusal prefix
fails validation_failed when the model echoes the injection needle
fails validation_failed when the model leaks the composed system instruction
T22 — every exercised path has exactly one terminal
T17 — Quota DO is installation-scoped only (no per-request DO name)
T18 — routing-policy edit changes selection without orchestrator code change
emits degraded_notice, journals degraded, and routes the degraded cost class
writes the router decision onto the existing ai_request row before invoke
```

**The other 15 npm-test failures** (mostly secondary cascades of the same missing
column — rows never written):

| Test | Why it fails |
|---|---|
| T-A4-15 manifest is data, not code | `export hashCanonicalJson must be data, not executable wiring: expected false to be true` |
| post-migration CREATE TABLE DDL equals `ai-platform/schema.snap.sql` | applied migrations' DDL **differs from the snapshot** — the schema-drift smoking gun |
| post-migration snapshot matches DDL and includes G1 catalogue entities | same DDL mismatch |
| T-J3-05 journal prompt hash matches each cohort build | `expected false to be true` |
| T16 — disconnect aborts in-flight invoke; journal Cancelled; partial credit | `expected false to be true` |
| writes ai_attempt and usage_event when cancel has accrued usage | `expected false to be true` |
| routes the degraded chain when grace admission journals routing_tier degraded | `expected 500 to be 200` |
| E2E-P3.4-01 CP-B paid grant then issuer token lists the plan, completes charged request | `expected [] to have a length of 1` — no usage rows written |
| E2E-P3.4-11 replayed jti or idempotency key returns the stored answer | `expected 401 to be 200` |
| SYS-8.1 retention purge keeps usage_event money row | `expected null to be truthy` |
| SYS-5.5 idempotent replay of completed | `R2 object not found: null` |
| SYS-5.6 replay of failed and cancelled | `expected undefined to be 'failed'` |
| SYS-7.1 completed settlement columns and envelope | `expected null to be 'request/fa906603…'` |
| SYS-7.3 cancelled settlement after accepted | `expected false to be true` |
| SYS-7.4 exactly-once under replay | `expected 409 to be 200` |

---

## frontend/all — 12 failures

| Test | Why it fails |
|---|---|
| E2E-P6.3-01 | `H-FS stack unavailable (ABO at http://127.0.0.1:8788). Start the H-FS stack before running fullstack billing tests.` |
| E2E-P6.3-02…07 (6 tests) | `LateInitializationError: Local 'ctx' has not been initialized` — cascade: setUpAll never ran because the ABO stack was down |
| E2E-P6.4-01…05 (5 tests) | `H-FS stack unavailable (ABO at http://127.0.0.1:8788)` — same, subscription suite |

---

## e2e-fullstack — all-manual (12) + all-ci (2)

| Test | Why it fails |
|---|---|
| E2E-P7.2-01…09 (9) + P7.3-01 | `hookFailed`: stack startup runs `wrangler d1 migrations apply` → **`duplicate column name: canary_installation_ids: SQLITE_ERROR`** — migrations re-applied over an already-migrated persisted D1 seed |
| test/p5-1.test.mjs (all-manual + all-ci) | `test timed out after 180000ms` — wrangler dev for the platform worker kept failing to bundle: `Could not resolve "vendor-contracts"` (12 build errors in `src/worker.ts`, `src/vendor/entrypoint.ts`, `src/admission/index.ts`) |
| test/p5-2.test.mjs (all-manual + all-ci) | `ERR_MODULE_NOT_FOUND: Cannot find package 'vendor-contracts' imported from src/vendor/entrypoint.ts` |

The p5 failures are a packaging gap: the `e2e-fullstack` campaign installs
`packages/vendor-contracts` and `e2e/fullstack`, but **not `ai-platform`** — so the
ai-platform worker can't resolve its `file:` dependency when built from that area
(`.github/scripts/setup-campaign-area.sh`).

---

## abo/cross-worker — 4 failures

| Test | Why it fails |
|---|---|
| E2E-P4.9-03 — issuer-key register, token accept/reject within TTL | `D1_ERROR: no such column: request_fingerprint` |
| E2E-P4.9-05 — routing publish, canary, fake provider, promote, rollback | `D1_ERROR: no such column: request_fingerprint` |
| E2E-P4.8-07 — suspend refuses admission and resume restores it | `D1_ERROR: no such column: request_fingerprint` (at `env.PLATFORM_HTTP.fetch` → gateway admission) |
| E2E-P4.4-01 — paid grant activates the term, completes issuer request | `D1_ERROR: no such column: request_fingerprint` |

---

## vendor-contracts/all — 1 failure

| Test | Why it fails |
|---|---|
| E2E-P2.2-08 — production bundle contains no testkit code | bundle scan still flags testkit code in the production ai-platform bundle |

---

## The big picture

| Root cause | Failures | Fix direction |
|---|---:|---|
| **Missing D1 column `request_fingerprint`** (schema/migration drift) | **70** | add the migration (or fix the code↔snapshot mismatch — note the `schema.snap.sql` DDL test also fails, confirming drift) |
| vendor-contracts unresolvable in `e2e-fullstack` area | 4 | add `ai-platform` to `npm_dirs` for the e2e-fullstack campaign |
| duplicate-column on D1 seed re-apply (P7.2/P7.3) | 10 | make `wrangler-persist.mjs` tolerant of an already-migrated seed dir |
| H-FS stack not started for frontend/fullstack suites | 12 | start the ABO stack (or route those tests to the `frontend/fullstack` subcampaign only) |
| waitUntil/settlement timing races | ~5 | deterministic-clock treatment like the earlier fixes |
| idempotent replay returns 409 instead of 200 | 8 (overlapping with the above) | product bug in replay path |
| testkit code in production bundle | 1 | bundle-scan guardrail finding |

**Bottom line:** the dominant issue is the `request_fingerprint` schema-drift bug —
fixing it addresses 70 of 123 failures.
