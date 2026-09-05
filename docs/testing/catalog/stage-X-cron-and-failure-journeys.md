# Stage X — Cron-driven behaviors and alternative/failure journeys

Source files read:
- `ai-platform/src/worker.ts` (`scheduled` handler L1447-L1495 — job order flushRejectionCounters → reconcileGraceUsage → cron-string dispatch; `GatewayObject.fetch` `now` injection L1263-L1266; GET `/v1/requests/{ref}` Completed/resultMissing branch L1412-L1420)
- `ai-platform/src/rate-limit/index.ts` (`recordGuardRejection` L70-L75, `currentTimeBucket` L47-L50, `counterIdFor` L78-L87, `flushRejectionCounters` L159-L190)
- `ai-platform/src/credit/index.ts` (`GRACE_RECONCILE_MAX_ATTEMPTS` L19, `GRACE_RECONCILE_TTL_MS` L21, `journalGraceDrop` L99-L116, `invokeAdmissionRpc` L118-L150, `invokeCreditRpc` L152-L198, `creditUsage` L201-L244, `reconcileGraceUsage` L256-L346)
- `ai-platform/src/admission/index.ts` (`GRACE_ADMISSION_CAP` L27, `listPendingGraceAdmissions` L323-L330, `markGraceAdmissionStatus` L332-L342, `stampGraceReconcileRetry` L344-L361, `attachGraceUsage` L381-L404, `admitUnderGrace` capped insert L490-L575)
- `ai-platform/src/retention/index.ts` (horizon constants L11-L18, `minPublishedDiagnosticHorizonDays` L45-L60, `createManifestRetentionClassResolver` L62-L71, `parseDiagnosticHorizonDays` L74-L80, `runRetentionPurge` L133-L285)
- `ai-platform/src/rollup/index.ts` (`defaultReconciliationWindow` L28-L33, `aggregateUsageEvents` L44-L83, `runRollup` L86-L129, `runReconciliation` L135-L186, `runRollupAndReconciliation` L202-L209)
- `ai-platform/src/quota-do/index.ts` (`EPHEMERAL_HORIZON_MS` L4, `CONCURRENCY_LIMIT` L5, `sweepAbandonedAdmissions` L209-L231, `sweepEphemeral` L233-L254, `maybeResetPeriod` L257-L274, `admissionRPC` L359-L462, `creditRPC` L464-L541, `releaseRPC` L545-L599, `inspectRPC` L613-L622 — **no `alarm()` handler exists**)
- `ai-platform/src/dashboards/index.ts` (`dashboardQuotaRejectionRate` L166-L191 — sole in-repo consumer of cron-produced `platform_counter`)
- `ai-platform/src/journal/index.ts` (terminal-state set L115-L120, envelope write + `payload_pointer` L428-L434, `getRequest` L462-L535)
- `ai-platform/migrations/20260805120000_f3_retention_indexes.sql`, `20260821120000_grace_admission_queue.sql`, `20260805180000_h3_conversation_index.sql`
- `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json` (`Governance.retentionClass = "diagnostic_30d"`)
- Orientation only: `docs/architecture/ai-platform/data-journey/15-alternative-and-failure-journeys.md`, `16-complete-d1-column-reference.md`, `17-complete-r2-object-reference.md`, `18-quota-durable-object-state-reference.md`, `19-taxonomy-codes-and-http-mapping.md`, `docs/architecture/ai-platform/request-lifecycle-brief.md`
- Test-harness confirmation: `ai-platform/test/system/harness.ts` (`runScheduled` L865-L872 — direct `worker.scheduled({ cron, ... })` invocation), `ai-platform/test/worker-entry.test.ts` L354-L421 (dispatch order assertions)

Conventions used throughout:
- All D1 state is built by applying the real migration chain to a fresh database, then real operations (control-plane calls, `POST /v1/requests`, DO RPCs). `[SEED]` marks the permitted exceptions: aged rows (retention/reconciliation backdating) and deliberately inconsistent rows that production writers never produce (e.g. Completed without `ai_attempt`) seeded to exercise reconciliation signal detection. Each use carries its justification inline.
- "Run cron tick `C`" means directly invoking the exported scheduled handler: `worker.scheduled({ cron: C, scheduledTime: Date.now(), noRetry() {} }, env, ctx)` — the exact pattern of `test/system/harness.ts:runScheduled`. Never a wall-clock wait.
- The scheduled handler passes **no** `now` to `runRetentionPurge` and **no** `window`/`now` to `runRollupAndReconciliation` or `reconcileGraceUsage` (worker.ts L1458-L1483). Where a job function supports injection (`runRetentionPurge` `bindings.now`, `RollupBindings.window`, `ReconcileGraceContext.now`, DO RPC body `now`), scenarios say "direct call" and use it; scheduled-handler scenarios use `[SEED]` backdating relative to real wall-clock instead.
- Concrete identities: installation **I0** = `inst-9f8e7d6c-0000-4000-8000-aaaaaaaa0001`, **I1** = `inst-9f8e7d6c-0000-4000-8000-aaaaaaaa0002`; capability `clinic.visit_summary@1.0.0` (retention class `diagnostic_30d`); entitlement period P1 = `2026-08-01T00:00:00.000Z`→`2026-09-01T00:00:00.000Z` (`request_quota=1000`, `token_budget=500000`, `cost_budget=50.0`, `soft_threshold=0.8`).
- DO RPCs are invoked through `GatewayObject.fetch` (`POST https://quota-do.internal/rpc` via `env.DO.idFromName(installationId)`), which honors an optional numeric `now` field in the body (worker.ts L1263-L1266) — the forced-timing mechanism for all DO sweep scenarios.
- Log assertions reference the structured event names the code emits: `scheduled_cron_start`, `Flushing guard rejection counters`, `grace_reconcile_batch_start`/`grace_reconcile_batch_end`, `grace_reconcile_dropped`, `scheduled_retention_purge_start`/`scheduled_retention_purge_complete`, `retention_purge_complete`, `rollup_start`/`rollup_complete`, `reconcile_start`/`reconcile_complete`, `usage_rollup_reconciliation`, `scheduled_cron_complete`.

## Scenario SX-001 — Cron `0 3 * * *` runs flush → grace reconcile → retention purge, in that order

| Field | Content |
|-------|---------|
| ID | SX-001 |
| Journey setup | Stage 3 enrollment + entitle happy path for I0 (period P1). One guard rejection recorded this minute (Stage 8 behavior: invoke with `request_quota` exhausted → `recordGuardRejection({error_code:"quota_exhausted", installation_id:I0})`). One pending grace row `grace-sx001` (Stage 8 behavior: DO-down grace admit; in the pool, inserted via the real `admitUnderGrace` path against a throwing DO stub, usage attached by Stage 11 settlement `creditUsage`). One Completed request **R-old** from Stage 11 settlement, `[SEED]` backdated `created_at=completed_at=<now − 91 days>` (retention backdating — permitted). DO healthy at tick time. |
| Action | Run cron tick `"0 3 * * *"`. |
| Expected outcome | Log order is `scheduled_cron_start{cron:"0 3 * * *"}` → `Flushing guard rejection counters` → `grace_reconcile_batch_start`/`grace_reconcile_batch_end` → `scheduled_retention_purge_start` → `retention_purge_complete` → `scheduled_retention_purge_complete` → `scheduled_cron_complete`. Final D1: one `platform_counter` row (count ≥ 1); `grace-sx001.status='reconciled'`; R-old and its `ai_attempt` rows deleted, its `usage_event.request_id` NULLed. `usage_rollup` untouched (no rollup on this cron). |
| Side effects | Writes: `platform_counter` upsert, `grace_admission_queue` status update, `usage_event` NULL update, `ai_attempt`/`ai_request` deletes, R2 delete of `request/<R-old>/envelope`. Must NOT write: `usage_rollup`, `kill_switch`, `installation`. |
| Code reference | ai-platform/src/worker.ts:L1447-L1495 — `scheduled` (flush L1458-L1461, reconcile L1463-L1467, retention dispatch L1469-L1477) |

## Scenario SX-002 — Cron `0 4 * * *` runs flush → grace reconcile → rollup + reconciliation with report log fields

| Field | Content |
|-------|---------|
| ID | SX-002 |
| Journey setup | I0 entitled (P1). Stage 11 Completed settlement produced request **R1** with `usage_event` (tokens 30, cost 0.003, period `2026-08`) and one `ai_attempt`. No pending grace rows, no rejections. |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | Log order: flush → `grace_reconcile_batch_start{pending_count:0}` → `scheduled_rollup_start` → `rollup_start`/`rollup_complete` → `reconcile_start`/`reconcile_complete` → `usage_rollup_reconciliation{rollups_written:1, missing_attempt_rows:0, missing_usage_credit:0, window:{start:<now−30d ISO>, end:<now ISO>}}` → `scheduled_cron_complete`. D1: one `usage_rollup` row, `dimensions={"installation_id":I0,"period":"2026-08"}`, `request_count=1`, `tokens=30`, `cost=0.003`. The window is the default trailing 30 days of wall clock — the scheduled handler cannot inject it. |
| Side effects | Writes: `usage_rollup` upsert only. Must NOT write: `ai_request`, `ai_attempt`, `usage_event`, `platform_counter` (empty tally), R2 (no deletes). |
| Code reference | ai-platform/src/worker.ts:L1478-L1492 — rollup dispatch + report log; ai-platform/src/rollup/index.ts:L202-L209 — `runRollupAndReconciliation`; L28-L33 — `defaultReconciliationWindow` |

## Scenario SX-003 — Unknown cron string runs only flush + reconcile (no retention, no rollup)

| Field | Content |
|-------|---------|
| ID | SX-003 |
| Journey setup | I0 entitled. One rejection tallied this minute. One `[SEED]` 91-day-old Completed request (would be purged on `0 3 * * *`). One `usage_event` (would roll up on `0 4 * * *`). |
| Action | Run cron tick `"0 5 * * *"` (also repeat with `""` and `"* * * * *"` — identical else-if fallthrough). |
| Expected outcome | Logs show `scheduled_cron_start`, flush, `grace_reconcile_batch_*`, `scheduled_cron_complete` — and neither `scheduled_retention_purge_start` nor `scheduled_rollup_start`. D1: `platform_counter` row written; the aged `ai_request` row still present; `usage_rollup` still empty. |
| Side effects | Writes: `platform_counter` only. Must NOT delete any `ai_request`/`ai_attempt`/R2 object; must NOT write `usage_rollup`. |
| Code reference | ai-platform/src/worker.ts:L1469-L1492 — `if/else if` cron-string dispatch with no else branch |

## Scenario SX-004 — A flush failure aborts the whole tick (no try/catch in the scheduled handler)

| Field | Content |
|-------|---------|
| ID | SX-004 |
| Journey setup | I0 entitled. One rejection tallied. One pending grace row `grace-sx004`. One `[SEED]` 91-day-old Completed request. Env DB replaced by a proxy shim around the real D1 binding that throws only when the SQL contains `INSERT INTO platform_counter` (real D1 cannot fail on demand — see Non-automatable notes). |
| Action | Run cron tick `"0 3 * * *"`. |
| Expected outcome | `scheduled()` rejects with the shim's error. `reconcileGraceUsage` and `runRetentionPurge` never run: `grace-sx004` still `status='pending'` with `reconcile_attempts=0`; the aged request row still present; no `scheduled_retention_purge_start` log. The in-isolate tally was already cleared by snapshot-and-clear, so a later healthy tick does not double-apply (see SX-008). |
| Side effects | No D1 writes at all (the single failing INSERT is the first write attempted). No R2 deletes. |
| Code reference | ai-platform/src/worker.ts:L1457-L1467 — sequential `await`s with no error isolation; ai-platform/src/rate-limit/index.ts:L165-L171 — snapshot-and-clear before writing |

## Scenario SX-005 — Flush with tallies present upserts bucketed `platform_counter` rows

| Field | Content |
|-------|---------|
| ID | SX-005 |
| Journey setup | I0 entitled. Three guard rejections in the current minute with identical dimensions — produced by real guard failures (Stage 8 behavior: three invokes against `request_quota=0`, each `quota_exhausted`) or direct `recordGuardRejection({error_code:"quota_exhausted", installation_id:I0})` ×3. Plus one rejection with a different dimension set (`error_code:"rate_limited", composite_key:"installation+actor"`). |
| Action | Run cron tick `"0 4 * * *"` (any cron flushes). |
| Expected outcome | Log `Flushing guard rejection counters{bucket_count:2, rejection_count:4}`. D1 `platform_counter` has exactly 2 rows: row A `dimension_set='{"error_code":"quota_exhausted","installation_id":"<I0>"}'`, `count=3`; row B `dimension_set` including `"composite_key":"installation+actor"`, `count=1`. Each `counter_id` = SHA-256 hex of `"<time_bucket>:<dimension_set>"`; `time_bucket` = current minute as `YYYY-MM-DDTHH:MM:00` (ISO sliced to minute, no `Z`). |
| Side effects | Writes: 2 `platform_counter` INSERTs. No other table touched by the flush. |
| Code reference | ai-platform/src/rate-limit/index.ts:L159-L190 — `flushRejectionCounters`; L47-L50 — `currentTimeBucket`; L78-L87 — `counterIdFor` |

## Scenario SX-006 — Repeat flush into the same minute bucket accumulates via ON CONFLICT

| Field | Content |
|-------|---------|
| ID | SX-006 |
| Journey setup | SX-005 completed (row A `count=3` in the current minute bucket). Two further identical `quota_exhausted` rejections for I0 recorded in the **same** minute. |
| Action | Run cron tick `"0 4 * * *"` again within the same wall-clock minute. |
| Expected outcome | Still exactly one `platform_counter` row for that bucket+dimension set; `count=5` (`ON CONFLICT(counter_id) DO UPDATE SET count = count + excluded.count`). No second row, no overwrite to 2. |
| Side effects | Writes: one `platform_counter` UPDATE via upsert. Row count unchanged. |
| Code reference | ai-platform/src/rate-limit/index.ts:L183-L189 — upsert SQL |

## Scenario SX-007 — Empty tally flush is a complete no-op

| Field | Content |
|-------|---------|
| ID | SX-007 |
| Journey setup | Fresh isolate (no `recordGuardRejection` since start). `platform_counter` empty. |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | `flushRejectionCounters` returns before logging or touching D1 (`rejectionTally.size === 0` early return). No `Flushing guard rejection counters` log; `platform_counter` still empty. |
| Side effects | None. |
| Code reference | ai-platform/src/rate-limit/index.ts:L163-L165 — empty-map early return |

## Scenario SX-008 — Mid-flush D1 failure loses the snapshot (under-count, never double-apply)

| Field | Content |
|-------|---------|
| ID | SX-008 |
| Journey setup | Two rejections tallied this minute. `flushRejectionCounters` called directly with a DB shim that throws on the first `platform_counter` INSERT. |
| Action | Direct call `flushRejectionCounters({DB: shim})` → rejects. Then restore the real DB binding and run cron tick `"0 4 * * *"`. |
| Expected outcome | The direct call throws; the in-isolate map was cleared **before** the write loop, so the recovery tick finds an empty tally and writes nothing. `platform_counter` stays empty — the 2 rejections are lost (documented lower-bound/under-count preference), and crucially are not double-counted later. |
| Side effects | No `platform_counter` rows ever written for the lost snapshot. |
| Code reference | ai-platform/src/rate-limit/index.ts:L149-L158 (design comment) and L166-L171 (snapshot-then-clear) |

## Scenario SX-009 — `dashboardQuotaRejectionRate` consumes only cron-flushed counters, and counter retention erases the numerator

| Field | Content |
|-------|---------|
| ID | SX-009 |
| Journey setup | SX-005 state: one `platform_counter` row `quota_exhausted` count=3, bucket = now. I0 has 4 journaled `ai_request` rows with `created_at` inside the trailing 90 days (Stage 11 settlements). |
| Action | (a) Direct call `dashboardQuotaRejectionRate(db)`. (b) `[SEED]` backdate the counter row's `time_bucket` to `<now − 91 days>` (retention backdating — permitted), run cron tick `"0 3 * * *"`, then call `dashboardQuotaRejectionRate(db)` again. |
| Expected outcome | (a) rate = `3 / 4 = 0.75` — numerator is `SUM(count)` of buckets `>= now−90d` whose `dimension_set` contains `quota_exhausted`; denominator is in-window `ai_request` count. (b) `retention_purge_complete{counter_deleted:1}`; the counter row is deleted (`time_bucket < now−90d`); recomputed rate = `0 / 4 = 0`. The dashboard can never be more exact than the flushed lower bound. |
| Side effects | Tick (b) deletes only the aged `platform_counter` row (plus any aged journal rows — none here). |
| Code reference | ai-platform/src/dashboards/index.ts:L166-L191 — `dashboardQuotaRejectionRate`; ai-platform/src/retention/index.ts:L271-L274 — counter purge (`COUNTER_HORIZON_DAYS = JOURNAL_HORIZON_DAYS = 90`) |

## Scenario SX-010 — Reconcile with an empty grace queue

| Field | Content |
|-------|---------|
| ID | SX-010 |
| Journey setup | Migrations applied; `grace_admission_queue` empty (or only `reconciled`/`dropped` rows — `listPendingGraceAdmissions` filters `status='pending'`). |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | Logs `grace_reconcile_batch_start{pending_count:0}` then `grace_reconcile_batch_end{pending_count:0, reconciled:0}`. No DO RPC is made (DO storage untouched — verifiable via `inspect` before/after). |
| Side effects | None. |
| Code reference | ai-platform/src/credit/index.ts:L261-L267 — empty-pending path; ai-platform/src/admission/index.ts:L323-L330 — `listPendingGraceAdmissions` pending filter |

## Scenario SX-011 — Pending grace row reconciles: fresh admit + attached usage credited, cap room freed

| Field | Content |
|-------|---------|
| ID | SX-011 |
| Journey setup | I0 entitled (P1). Pending grace row `grace-sx011`: `installation_id=I0`, `idempotency_key='sx011-key'`, `jti='sx011-jti'`, `request_reference='SX01-1000'`, `entitlement_json` = P1 snapshot, `usage_tokens=10`, `usage_cost=0.01`, `partial=1` (attached by Stage 11 settlement behavior: `creditUsage` → `attachGraceUsage` matched on the grace request id), `reconcile_attempts=0`, `reconcile_first_seen_at_ms=NULL`, `status='pending'`. DO healthy. |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | `grace_reconcile_batch_end{pending_count:1, reconciled:1}`. D1: row `status='reconciled'`; usage columns unchanged (10 / 0.01 / 1). DO (via `inspect`): `periodCounters` = `{requestsUsed:1, tokensUsed:10, costUsed:0.01, inFlight:0}`; `idempotency['sx011-key'].state='cancelled'` (partial credit with no explicit `idempotencyState` maps partial→cancelled); `creditedRequests` holds the DO-issued requestId. The pending `COUNT(*)` for I0 drops to 0 — cap room freed (SX-022). |
| Side effects | Writes: one `grace_admission_queue` UPDATE; DO storage put (admission + credit). Must NOT write `usage_event`/`ai_request` (reconcile never journals). |
| Code reference | ai-platform/src/credit/index.ts:L316-L340 — admitted → credit → `markGraceAdmissionStatus(..., "reconciled")`; ai-platform/src/quota-do/index.ts:L339-L356 — `markIdempotencyOnCredit` partial→cancelled |

## Scenario SX-012 — Pending grace row without attached usage credits `{tokens:0, cost:0}`, partial false

| Field | Content |
|-------|---------|
| ID | SX-012 |
| Journey setup | SX-011 shape but `usage_tokens=NULL`, `usage_cost=NULL`, `partial=NULL` (settlement never ran — e.g. the request never reached a terminal while the DO was down). |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | `reconciled:1`; row `status='reconciled'`. DO credited with `entry.usage ?? {tokens:0, cost:0}` and `entry.partial ?? false`: `requestsUsed=1`, `tokensUsed=0`, `costUsed=0`, `inFlight=0`; idempotency state `completed` (not partial → default completed). Zero usage is a valid credit and still releases the in-flight slot. |
| Side effects | Writes: grace row status UPDATE; DO storage. No ledger writes. |
| Code reference | ai-platform/src/credit/index.ts:L317-L327 — `entry.usage ?? { tokens: 0, cost: 0 }`, `entry.partial ?? false`; ai-platform/src/quota-do/index.ts:L505-L515 — zero-usage credit path |

## Scenario SX-013 — DO still unavailable: `reconcile_attempts` incremented, first-seen stamped, row stays pending

| Field | Content |
|-------|---------|
| ID | SX-013 |
| Journey setup | Pending row `grace-sx013` (`reconcile_attempts=0`, `reconcile_first_seen_at_ms=NULL`). DO namespace replaced by a stub whose `fetch` throws (transport `unavailable`). |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | `reconciled:0`. D1 row: `status='pending'`, `reconcile_attempts=1`, `reconcile_first_seen_at_ms=<tick wall-clock ms>` (TTL origin stamped on first failed presentation). No `grace_reconcile_dropped` log. The row still counts toward the cap. |
| Side effects | Writes: one `grace_admission_queue` UPDATE (`stampGraceReconcileRetry`). No DO state change (stub). |
| Code reference | ai-platform/src/credit/index.ts:L288-L292 — `!admission.ok` → `stampGraceReconcileRetry`; ai-platform/src/admission/index.ts:L344-L361 — retry stamp SQL |

## Scenario SX-014 — Reconcile-time `quota_exhausted` keeps the row pending (retry, not a drop)

| Field | Content |
|-------|---------|
| ID | SX-014 |
| Journey setup | Pending row `grace-sx014` whose `entitlement_json` has `request_quota=0` (installation exhausted its ledger during the outage — Stage 8 `isLedgerQuotaExhausted` behavior). **Real** DO (healthy). |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | The re-presented admission returns `outcome:"quota_exhausted"` from the real DO. Reconcile treats any non-`admitted`, non-`idempotent`, non-`replay` outcome as retryable: row stays `status='pending'`, `reconcile_attempts=1`, first-seen stamped; `reconciled:0`; no drop journal entry. The entry will churn on every tick until TTL (SX-020) or max-attempts (SX-019) drops it — its usage is never credited. |
| Side effects | Writes: retry-stamp UPDATE only. DO storage unchanged (quota_exhausted path puts state but mutates nothing observable: no jti/idempotency/counter writes). |
| Code reference | ai-platform/src/credit/index.ts:L310-L314 — `body.outcome !== "admitted"` → retry; ai-platform/src/quota-do/index.ts:L401-L413 — `quota_exhausted` outcome |

## Scenario SX-015 — Reconcile admission outcome `idempotent` drops the entry (`settled_by_another_path_idempotent`)

| Field | Content |
|-------|---------|
| ID | SX-015 |
| Journey setup | Real DO already holds idempotency key `sx015-key` from a real admission RPC (the original admit actually reached the DO but the response was lost — the classic grace trigger). Pending grace row `grace-sx015` with `idempotency_key='sx015-key'`, usage attached (tokens 10, cost 0.01, partial 0). |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | Admission RPC returns `outcome:"idempotent"` with the prior state. Row → `status='dropped'`; isolate journal entry `{reason:"settled_by_another_path_idempotent", graceRequestId:'grace-sx015', ...}` (info level, drainable via `drainDroppedGraceJournal()`); `reconciled:0`. The attached usage is **not** credited by this path; if the DO-side prior state is still `admitted`, that in-flight slot leaks until the abandoned sweep (SX-046). |
| Side effects | Writes: grace row status UPDATE. Must NOT issue a credit RPC (DO `periodCounters` unchanged). |
| Code reference | ai-platform/src/credit/index.ts:L300-L304 — idempotent drop; L51-L57 — `GraceDropReason` |

## Scenario SX-016 — Reconcile admission outcome `replay` drops the entry (`settled_by_another_path_replay`)

| Field | Content |
|-------|---------|
| ID | SX-016 |
| Journey setup | Real DO holds `jtiReplay['sx016-jti']` from a real admission RPC at tick−5min. Pending grace row `grace-sx016` with `jti='sx016-jti'` and a **different** idempotency key. |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | Admission RPC returns `outcome:"replay"` (jti checked before idempotency). Row → `status='dropped'`; journal reason `settled_by_another_path_replay`; `reconciled:0`; no credit issued. |
| Side effects | Writes: grace row status UPDATE only. |
| Code reference | ai-platform/src/credit/index.ts:L305-L309 — replay drop; ai-platform/src/quota-do/index.ts:L373-L381 — jti replay check |

## Scenario SX-017 — Fresh reconcile admit followed by credit `unknown_request` drops the entry (`settled_by_another_path_unknown_request`)

| Field | Content |
|-------|---------|
| ID | SX-017 |
| Journey setup | Pending row `grace-sx017`. DO stub scripted to return a well-formed `admitted` body (fresh `requestId`) for `kind:"admission"` and `{kind:"credit", ok:false, code:"unknown_request"}` for `kind:"credit"` — the production cause is DO state loss between the two RPCs (see Non-automatable notes). |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | Row → `status='dropped'`; journal reason `settled_by_another_path_unknown_request`; `reconciled:0`. No retry stamp (`reconcile_attempts` stays 0). |
| Side effects | Writes: grace row status UPDATE only. |
| Code reference | ai-platform/src/credit/index.ts:L328-L334 — credit `unknown_request` drop |

## Scenario SX-018 — Reconcile admit succeeds but credit is unavailable: retry, then next tick replay-drops; in-flight leaks until the abandoned sweep

| Field | Content |
|-------|---------|
| ID | SX-018 |
| Journey setup | Pending row `grace-sx018` (`jti='sx018-jti'`, key `sx018-key`, usage 10/0.01). DO facade that forwards `kind:"admission"` to the **real** GatewayObject but throws on `kind:"credit"` (transport `unavailable`). |
| Action | Run cron tick `"0 4 * * *"` (tick 1). Restore full DO facade. Run cron tick `"0 4 * * *"` again (tick 2). Then any DO RPC with body `now = <tick2 ms> + 7_200_001` (tick-3 sweep probe). |
| Expected outcome | Tick 1: real DO admitted (inFlight=1, `jtiReplay['sx018-jti']` set, idempotency `sx018-key` state `admitted`); credit threw → row stays `pending`, `reconcile_attempts=1`. Tick 2: admission RPC now returns `replay` (jti recorded on tick 1) → row `status='dropped'`, reason `settled_by_another_path_replay`; the attached usage is **never credited** (`requestsUsed` stays 0). Sweep probe: `sweepAbandonedAdmissions` drops the orphaned admission — `inFlight` 1→0, idempotency `sx018-key` → `state='failed'` with `expiresAt` slid to `now + 7_200_000`. |
| Side effects | Tick 1 writes: retry stamp + real DO admission state. Tick 2 writes: drop UPDATE only. Sweep probe writes: DO storage put. No `usage_event` is ever written for this entry. |
| Code reference | ai-platform/src/credit/index.ts:L336-L338 (credit failure → retry) + L305-L309 (next-tick replay drop); ai-platform/src/quota-do/index.ts:L209-L231 — `sweepAbandonedAdmissions` |

## Scenario SX-019 — `reconcile_attempts >= 5` drops the entry (`max_attempts`) before any RPC

| Field | Content |
|-------|---------|
| ID | SX-019 |
| Journey setup | `[SEED]` pending row `grace-sx019` with `reconcile_attempts=5` (pre-exhausted retry budget — permitted seed; reaching this honestly needs 5 DO-down ticks). Real healthy DO. |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | Row → `status='dropped'`; `grace_reconcile_dropped{reason:"max_attempts", ...}` logged at **error** level; `reconciled:0`. The check precedes the admission RPC — the DO receives no admission (verify via `inspect`: no new jti/idempotency entries). Pending count for the cap decreases by 1. |
| Side effects | Writes: grace row status UPDATE only. |
| Code reference | ai-platform/src/credit/index.ts:L282-L286 — max-attempts drop; L19 — `GRACE_RECONCILE_MAX_ATTEMPTS = 5`; L112-L113 — error-level for max_attempts |

## Scenario SX-020 — Grace TTL: first-seen older than 7 200 000 ms drops (`expired`); exactly-at-TTL survives

| Field | Content |
|-------|---------|
| ID | SX-020 |
| Journey setup | `[SEED]` two pending rows: A `grace-sx020a` with `reconcile_first_seen_at_ms = <tick ms> − 7_200_001`; B `grace-sx020b` with `reconcile_first_seen_at_ms = <tick ms> − 7_200_000` exactly (aged-queue backdating — permitted). Real healthy DO. |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | A: dropped, `grace_reconcile_dropped{reason:"expired"}` at error level (`nowMs − queuedAtMs > 7_200_000`, strict). B: **not** dropped — proceeds to admission against the real DO and reconciles (`status='reconciled'`). Batch end `{pending_count:2, reconciled:1}`. |
| Side effects | Writes: A status UPDATE; B status UPDATE + DO admission/credit state for B. |
| Code reference | ai-platform/src/credit/index.ts:L276-L280 — TTL drop (strict `>`); L21 — `GRACE_RECONCILE_TTL_MS = 7_200_000` |

## Scenario SX-021 — TTL cannot fire on first sighting (queued long ago, first-seen NULL)

| Field | Content |
|-------|---------|
| ID | SX-021 |
| Journey setup | `[SEED]` pending row `grace-sx021` with `queued_at = <now − 3 hours>` but `reconcile_first_seen_at_ms = NULL` (e.g. inserted by a DO-down admit while every cron isolate was starved). DO stub unavailable. |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | **Not** expired: `reconcileQueuedAtMs` defaults to `nowMs` on first sighting, so `nowMs − nowMs = 0 ≯ 7_200_000`. The unavailable admission stamps `reconcile_attempts=1`, `reconcile_first_seen_at_ms=<now ms>`; row stays `pending`. `queued_at` age is irrelevant to the TTL — only first cron sighting starts the clock. |
| Side effects | Writes: retry-stamp UPDATE only. |
| Code reference | ai-platform/src/credit/index.ts:L270-L280 — `reconcileQueuedAtMs: prior.reconcileQueuedAtMs ?? nowMs` before the TTL check |

## Scenario SX-022 — Cap interplay: reconciling 2 of 5 pending rows re-opens grace admission

| Field | Content |
|-------|---------|
| ID | SX-022 |
| Journey setup | I0 at the durable cap: 5 pending grace rows (`GRACE_ADMISSION_CAP=5`), two with attached usage, all reconcilable-eligible; real healthy DO. While the cap is full, Stage 8 behavior: a DO-down grace admit maps to `rate_limited` + `retry_after` (insert guard `COUNT(*) pending < 5` fails). |
| Action | Run cron tick `"0 4 * * *"`. Then, with the DO stubbed unavailable again, drive one real `POST /v1/requests` (Stage 8 behavior: `admitUnderGrace`). |
| Expected outcome | Tick: `reconciled:5` (all rows healthy-DO reconcilable) — or stage it as 2 reconciled + 3 DO-stub-pending across two ticks for a partial drain; either way `COUNT(*) status='pending'` drops below 5. The subsequent grace admit succeeds: HTTP 200 SSE path with `grace_admitted` outcome, new pending row inserted (pending count returns to 4 or 1 respectively). Dropped/reconciled rows no longer count toward the cap. |
| Side effects | Writes: grace status UPDATEs + one new grace INSERT. No ledger writes from reconcile. |
| Code reference | ai-platform/src/admission/index.ts:L522-L546 — capped `INSERT … WHERE (SELECT COUNT(*) … status='pending') < 5`; ai-platform/src/credit/index.ts:L339-L340 — reconciled transition |

## Scenario SX-023 — `reconcileGraceUsage` without a DB binding short-circuits

| Field | Content |
|-------|---------|
| ID | SX-023 |
| Journey setup | None (branch-coverage scenario; the scheduled handler always passes DB, so this branch is reachable only by direct call). |
| Action | Direct call `reconcileGraceUsage({ DO: env.DO })` — no `DB`. |
| Expected outcome | Returns `{reconciled:0}`; logs `grace_reconcile_batch_start{pending_count:0}`; no D1 read attempted, no DO RPC. |
| Side effects | None. |
| Code reference | ai-platform/src/credit/index.ts:L261-L264 — `!bindings.DB` guard |

## Scenario SX-024 — Diagnostic purge: 31-day-old Completed visit-summary request loses its R2 envelope and `payload_pointer`; journal row and money survive

| Field | Content |
|-------|---------|
| ID | SX-024 |
| Journey setup | Stage 11 Completed settlement produced request **R-diag** (`clinic.visit_summary@1.0.0`, envelope at `request/<R-diag>/envelope`, `payload_pointer` set, `usage_event` present). `[SEED]` backdate `created_at=completed_at=<now − 31 days>` (retention backdating — permitted): older than the manifest's `diagnostic_30d` horizon, younger than the 90-day journal horizon. |
| Action | Run cron tick `"0 3 * * *"`. |
| Expected outcome | `retention_purge_complete{diagnostic_deleted:1, journal_deleted:0, ledger_deleted:0, counter_deleted:0}`. R2 `request/<R-diag>/envelope` deleted. D1: `ai_request` row still present with `payload_pointer=NULL`; `ai_attempt` rows intact; `usage_event` row intact with `request_id` still set (money and joinability kept). The 31-day-old row passed the scan prefilter because `minPublishedDiagnosticHorizonDays()` floors to the 1-day band minimum (`min(7d baseline, 30d published, 1d band)`), and the per-row check `ageMs > 30d` fired. |
| Side effects | Writes: one R2 delete, one `ai_request` UPDATE. Must NOT touch `usage_event`, `ai_attempt`, `usage_rollup`. |
| Code reference | ai-platform/src/retention/index.ts:L164-L193 — diagnostic scan + per-row horizon check; L45-L60 — `minPublishedDiagnosticHorizonDays`; L62-L71 — manifest resolver (`diagnostic_30d`) |

## Scenario SX-025 — Per-class retention: unpublished capability version falls back to `diagnostic_7d` while visit-summary keeps 30 days

| Field | Content |
|-------|---------|
| ID | SX-025 |
| Journey setup | Two Completed requests, both `[SEED]` backdated to `now − 8 days` with envelopes: **R-vs** for `clinic.visit_summary@1.0.0` (resolver hit → 30d), and **R-fut** for `clinic.visit_summary@2.0.0` (justified seed: no real operation can journal an unpublished version today; this exercises the resolver's `?? "diagnostic_7d"` fallback for a future manifest the Worker doesn't bundle). |
| Action | Run cron tick `"0 3 * * *"`. |
| Expected outcome | `diagnostic_deleted:1` — only R-fut: its envelope deleted, `payload_pointer=NULL` (8d > 7d fallback horizon). R-vs untouched: envelope present, pointer set (8d ≤ 30d). Both `ai_request` rows and both `usage_event` rows survive. |
| Side effects | Writes: one R2 delete + one pointer UPDATE (R-fut only). |
| Code reference | ai-platform/src/retention/index.ts:L62-L71 — resolver fallback; L74-L80 — `parseDiagnosticHorizonDays`; L175-L193 — per-row class check |

## Scenario SX-026 — Diagnostic horizon boundary: age exactly 30 days is not purged (strict `>`)

| Field | Content |
|-------|---------|
| ID | SX-026 |
| Journey setup | Stage 11 Completed request **R-edge** (visit-summary, envelope present). Direct call variant for exact boundary control: `runRetentionPurge({db, r2, now: NOW, resolveRetentionClass: createManifestRetentionClassResolver()})` with `[SEED]` `completed_at = NOW − 30 days` exactly (and a second row at `NOW − 30 days − 1 ms`). |
| Action | Direct call `runRetentionPurge` with injected `now = NOW`. |
| Expected outcome | The exactly-30d row survives (`ageMs > horizonMs` is strict); the 30d+1ms row is purged (envelope deleted, pointer NULLed). `diagnostic_deleted=1`. |
| Side effects | Writes: purge mutations for the over-boundary row only. |
| Code reference | ai-platform/src/retention/index.ts:L181-L191 — `ageMs > horizonMs` strict inequality; L141 — injectable `now` |

## Scenario SX-027 — Rows with `payload_pointer IS NULL` are never diagnostic-scanned

| Field | Content |
|-------|---------|
| ID | SX-027 |
| Journey setup | `[SEED]` an aged (40-day-old) `ai_request` row in state `Accepted` with `payload_pointer=NULL` (justified: real pre-terminal rows crash-leak in this shape — Stage 11 behavior — and never get an envelope). |
| Action | Run cron tick `"0 3 * * *"`. |
| Expected outcome | `diagnostic_deleted:0` — the scan SQL filters `payload_pointer IS NOT NULL`. The row survives the diagnostic pass (it is under 90d, so the journal pass leaves it too). No R2 delete attempted for it. |
| Side effects | None. |
| Code reference | ai-platform/src/retention/index.ts:L165-L173 — scan `WHERE payload_pointer IS NOT NULL AND COALESCE(completed_at, created_at) < ?` |

## Scenario SX-028 — Journal purge: 91-day-old Completed request deleted; `usage_event.request_id` NULLed; money row and R2 envelope handled in order

| Field | Content |
|-------|---------|
| ID | SX-028 |
| Journey setup | Stage 11 Completed settlement produced request **R-old** with one `ai_attempt` (tokens 30, cost 0.003), one `usage_event` (period `2026-08`, same totals), envelope at `request/<R-old>/envelope`. `[SEED]` backdate `created_at=completed_at=<now − 91 days>` (retention backdating — permitted). A second, non-aged Completed request **R-new** exists as a control. |
| Action | Run cron tick `"0 3 * * *"`. |
| Expected outcome | `retention_purge_complete{diagnostic_deleted:0, journal_deleted:2, ledger_deleted:0, counter_deleted:0}` (journal_deleted = 1 `ai_attempt` + 1 `ai_request`). D1: R-old's `ai_request` and `ai_attempt` rows gone; its `usage_event` row **present** with `request_id=NULL`, tokens/cost unchanged (money kept). R2: `request/<R-old>/envelope` gone (deleted by stored pointer **before** the row delete, so long diagnostic classes cannot orphan PII). R-new fully intact, pointer set, envelope present. |
| Side effects | Writes: R2 delete (R-old), `usage_event` NULL update, `ai_attempt` + `ai_request` deletes. Must NOT delete R-old's `usage_event`; must NOT touch R-new or `usage_rollup`. |
| Code reference | ai-platform/src/retention/index.ts:L196-L241 — journal purge (R2-first loop L205-L209, usage NULL L213-L222, attempt delete L224-L232, request delete L234-L237); ai-platform/migrations/20260805120000_f3_retention_indexes.sql:L5-L31 — nullable `request_id` FK |

## Scenario SX-029 — Journal horizon boundary: `created_at` exactly 90 days ago survives

| Field | Content |
|-------|---------|
| ID | SX-029 |
| Journey setup | Two `[SEED]` Completed rows with envelopes: A `created_at = NOW − 90 days` exactly; B `created_at = NOW − 90 days − 1 ms`. |
| Action | Direct call `runRetentionPurge({db, r2, now: NOW})`. |
| Expected outcome | A survives entirely (`created_at < cutoff` is strict). B is fully journal-purged (row + attempts deleted, usage NULLed, envelope deleted). `journal_deleted` counts only B's rows. |
| Side effects | Writes: purge mutations for B only. |
| Code reference | ai-platform/src/retention/index.ts:L147-L149 — `journalCutoff`; L199-L203 / L234-L237 — strict `<` comparisons; L15 — `JOURNAL_HORIZON_DAYS = 90` |

## Scenario SX-030 — Journal purge of a row whose `payload_pointer` is already NULL deletes the derived key (no-op) and the row

| Field | Content |
|-------|---------|
| ID | SX-030 |
| Journey setup | SX-024's R-diag (diagnostic-purged at 31d: pointer NULL, envelope already gone). `[SEED]` further backdate `created_at=<now − 91 days>` (`completed_at` already aged). |
| Action | Run cron tick `"0 3 * * *"`. |
| Expected outcome | The journal R2 loop calls `r2.delete(row.payload_pointer ?? envelopeObjectKey(request_id))` → deletes derived key `request/<R-diag>/envelope` (absent — R2 delete of a missing key succeeds as a no-op). Row and attempts deleted; its `usage_event.request_id` NULLed. `journal_deleted ≥ 2` for this request family. No error from the missing object. |
| Side effects | Writes: one (no-op) R2 delete, usage NULL update, row deletes. |
| Code reference | ai-platform/src/retention/index.ts:L205-L209 — `payload_pointer ?? envelopeObjectKey(request_id)`; L37-L39 — derived key shape |

## Scenario SX-031 — Aged non-terminal rows (`Accepted`, `AwaitingContext`) are journal-purged at 90 days and were never reconciliation-flagged

| Field | Content |
|-------|---------|
| ID | SX-031 |
| Journey setup | `[SEED]` two 91-day-old rows: **R-acc** state `Accepted` (`completed_at=NULL`, no envelope — crash-leaked pre-terminal, Stage 11 behavior) and **R-awc** state `AwaitingContext` (`completed_at=NULL`; justified seed: `AwaitingContext` is conversational-only per `canReachAwaitingContext` and no conversational capability is published, so no real operation can produce one today). Neither has `ai_attempt`/`usage_event`. Before the tick, run cron `"0 4 * * *"` and capture the reconciliation report. |
| Action | Run cron tick `"0 4 * * *"` (pre-purge report), then `"0 3 * * *"` (purge). |
| Expected outcome | Pre-purge report: neither row flagged — R-acc has `completed_at NULL` (window predicate excludes it); R-awc's state is outside both `('Completed','Failed')` and `('Completed','Failed','Cancelled')` filters. Purge: both rows deleted (`journal_deleted=2`; no attempts, no envelopes, no usage to NULL). Retention is state-agnostic — only `created_at` matters. |
| Side effects | Purge writes: two `ai_request` deletes. No R2 deletes with effect (pointers NULL → derived-key no-ops). |
| Code reference | ai-platform/src/retention/index.ts:L199-L203 — no state predicate; ai-platform/src/rollup/index.ts:L146-L168 — state filters + `completed_at` window; ai-platform/src/journal/index.ts:L164-L168 — `canReachAwaitingContext` |

## Scenario SX-032 — Non-aged rows are untouched by the entire purge

| Field | Content |
|-------|---------|
| ID | SX-032 |
| Journey setup | I0 with a full fresh footprint: Completed request (1d old) with attempts, usage_event, envelope, platform_counter bucket from SX-005, a `control_audit` row, live `capability_grant` rows, a `usage_rollup` row from SX-002. |
| Action | Run cron tick `"0 3 * * *"`. |
| Expected outcome | `retention_purge_complete{diagnostic_deleted:0, journal_deleted:0, ledger_deleted:0, counter_deleted:0}`. Every row and object byte-identical before/after. |
| Side effects | None. |
| Code reference | ai-platform/src/retention/index.ts:L133-L285 — `runRetentionPurge` (all four cutoff gates) |

## Scenario SX-033 — Ledger horizon: `usage_event` rows older than 2555 days are deleted; younger money survives

| Field | Content |
|-------|---------|
| ID | SX-033 |
| Journey setup | `[SEED]` two `usage_event` rows for I0 (justified: 7-year-old ledger rows cannot be produced in a test by real operations): A `recorded_at = NOW − 2556 days` (with `request_id` already NULL from a prior journal purge), B `recorded_at = NOW − 2554 days`. |
| Action | Direct call `runRetentionPurge({db, r2, now: NOW})`. |
| Expected outcome | `ledger_deleted=1`: A deleted (`recorded_at < NOW − 2555d`, strict), B survives. Ledger purge is by `recorded_at`, independent of the journal horizon and of `request_id` nullability. |
| Side effects | Writes: one `usage_event` delete. |
| Code reference | ai-platform/src/retention/index.ts:L150-L152 — `ledgerCutoff`; L243-L247 — `usage_event` ledger delete; L16 — `LEDGER_HORIZON_DAYS = 2555` |

## Scenario SX-034 — Ledger horizon: `usage_rollup` rows whose period predates the cutoff month are deleted (string compare on `dimensions.period`)

| Field | Content |
|-------|---------|
| ID | SX-034 |
| Journey setup | `[SEED]` two `usage_rollup` rows: A `dimensions={"installation_id":I0,"period":"2019-08"}`; B `dimensions={"installation_id":I0,"period":"2019-09"}`, with `NOW` chosen so the ledger cutoff ISO is `2019-09-15T…` (cutoff period string `2019-09`). |
| Action | Direct call `runRetentionPurge({db, r2, now: NOW})`. |
| Expected outcome | A deleted (`'2019-08' < '2019-09'`); B survives (`'2019-09' < '2019-09'` false — the whole cutoff month is kept). Comparison is `json_extract(dimensions,'$.period') < ledgerCutoff.slice(0,7)` — lexicographic `YYYY-MM`. |
| Side effects | Writes: one `usage_rollup` delete. |
| Code reference | ai-platform/src/retention/index.ts:L249-L255 — rollup ledger delete; L249 — `ledgerCutoffPeriod` |

## Scenario SX-035 — Ledger horizon: aged `control_audit` and `capability_grant` rows (including retired overlays) are deleted

| Field | Content |
|-------|---------|
| ID | SX-035 |
| Journey setup | `[SEED]` (7-year aging): one `control_audit` row `recorded_at = NOW − 2556 days`; one live installation-scoped `capability_grant` `changed_at = NOW − 2556 days`; one global overlay grant `lifecycle_state='retired'`, `changed_at = NOW − 2556 days`; plus fresh counterparts of each as controls. |
| Action | Direct call `runRetentionPurge({db, r2, now: NOW})`. |
| Expected outcome | `ledger_deleted=3`: all three aged rows deleted (`recorded_at < cutoff`, `changed_at < cutoff` respectively); fresh controls survive. Retention does not distinguish live grants from retired overlays — any grant untouched for 2555 days is purged. |
| Side effects | Writes: one `control_audit` delete, two `capability_grant` deletes. |
| Code reference | ai-platform/src/retention/index.ts:L257-L264 — audit + grant ledger deletes |

## Scenario SX-036 — Counter horizon purges 90-day-old `platform_counter` buckets; `kill_switch` rows are never purged (kill-switch × cron interaction)

| Field | Content |
|-------|---------|
| ID | SX-036 |
| Journey setup | `[SEED]` one `platform_counter` row `time_bucket = <now − 91 days>` minute format; one fresh bucket (SX-005). One `[SEED]` `kill_switch` row `scope='provider', target='deepseek', active=1, changed_at=<now − 365 days>` (kill switches have no HTTP writer — direct D1 is the production write path, doc 16 §6). |
| Action | Run cron tick `"0 3 * * *"`. |
| Expected outcome | `counter_deleted=1`: the aged bucket deleted (`time_bucket < now−90d`, lexicographic on the `YYYY-MM-DDTHH:MM:00` bucket format); fresh bucket survives. The `kill_switch` row is **untouched** — `runRetentionPurge` contains no `DELETE FROM kill_switch`; an active provider kill switch therefore survives every cron forever and keeps excluding that provider at routing (Stage 10 behavior) until an operator clears it by SQL. |
| Side effects | Writes: one `platform_counter` delete. Must NOT write `kill_switch`. |
| Code reference | ai-platform/src/retention/index.ts:L271-L274 — counter purge; L18 — `COUNTER_HORIZON_DAYS`; absence of any kill_switch statement in L133-L285 |

## Scenario SX-037 — Rollup aggregates the full ledger per (installation, period); re-run is an idempotent upsert

| Field | Content |
|-------|---------|
| ID | SX-037 |
| Journey setup | Real Stage 11 settlements: I0 period `2026-08` two Completed requests (tokens 30+40, cost 0.003+0.004); I0 period `2026-09` one (tokens 10, cost 0.001 — entitlement period rolled, Stage 8/DO behavior); I1 period `2026-08` one (tokens 5, cost 0.0005). |
| Action | Run cron tick `"0 4 * * *"`. Capture `usage_rollup`. Run the same tick again. |
| Expected outcome | First run: `rollups_written=3`; rows `(I0,2026-08): count=2, tokens=70, cost=0.007`, `(I0,2026-09): count=1, tokens=10, cost=0.001`, `(I1,2026-08): count=1, tokens=5, cost=0.0005`; each `rollup_id` = SHA-256 hex of the dimensions JSON. Second run: `rollups_written=3` again, still exactly 3 rows, identical values (`ON CONFLICT(rollup_id) DO UPDATE` — no duplicates, no drift). The scheduled path passes no window → full-ledger `GROUP BY installation_id, period`. |
| Side effects | Writes: 3 `usage_rollup` upserts per run. No other table touched. |
| Code reference | ai-platform/src/rollup/index.ts:L70-L82 — unwindowed aggregate; L97-L126 — upsert; ai-platform/src/worker.ts:L1481-L1484 — no window passed |

## Scenario SX-038 — Windowed rollup re-aggregates **entire** periods touched by the window

| Field | Content |
|-------|---------|
| ID | SX-038 |
| Journey setup | `[SEED]` I0 `usage_event` rows, period `2026-08`: E1 `recorded_at=2026-08-05T00:00:00.000Z` tokens 10; E2 `recorded_at=2026-08-25T00:00:00.000Z` tokens 20 (seeded ledger rows — the scheduled handler never passes a window, so this branch is reachable only by direct call). |
| Action | Direct call `runRollupAndReconciliation({db, window:{start:"2026-08-20T00:00:00.000Z", end:"2026-08-31T23:59:59.999Z"}})`. |
| Expected outcome | `rollupsWritten=1` with `request_count=2, tokens=30` — E1 falls **outside** the window but inside a touched period, and the windowed query re-reads ALL events for touched periods so each rollup row equals the full period ledger sum. |
| Side effects | Writes: one `usage_rollup` upsert. |
| Code reference | ai-platform/src/rollup/index.ts:L44-L68 — windowed `EXISTS`-touched-period aggregate |

## Scenario SX-039 — Empty ledger: zero rollups, empty reconciliation arrays

| Field | Content |
|-------|---------|
| ID | SX-039 |
| Journey setup | Fresh migrated D1 (no requests, no usage). |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | `usage_rollup_reconciliation{rollups_written:0, missing_attempt_rows:0, missing_usage_credit:0, window:{…}}`; `usage_rollup` empty; report arrays `[]`. No errors. |
| Side effects | None. |
| Code reference | ai-platform/src/rollup/index.ts:L86-L129 (empty aggregate loop) and L135-L186 (empty joins) |

## Scenario SX-040 — Reconciliation flags a Completed request with no `ai_attempt` rows (`missingAttemptRows`)

| Field | Content |
|-------|---------|
| ID | SX-040 |
| Journey setup | `[SEED]` request **R-noatt**: `state='Completed'`, `completed_at=<now − 1 day>` (inside the trailing-30d window), with a `usage_event` but **zero** `ai_attempt` rows (justified: production settlement always writes attempts — worker.ts `attemptsForFailedSettlement` guarantees at least one even for empty-chain failures — so this inconsistency can only be seeded; detecting it is the report's purpose). |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | `missing_attempt_rows=1`; `usage_rollup_reconciliation_detail` report `missingAttemptRows=[{requestId:R-noatt, requestReference:<ref>}]`. `missingUsageCredit` does **not** contain it (usage present). |
| Side effects | None (reconciliation is read-only). |
| Code reference | ai-platform/src/rollup/index.ts:L146-L155 — `LEFT JOIN ai_attempt … a.attempt_id IS NULL` over `state IN ('Completed','Failed')`; ai-platform/src/worker.ts:L378-L411 — production guarantee being checked |

## Scenario SX-041 — Reconciliation flags a Failed request with no attempts; Cancelled is never attempt-flagged

| Field | Content |
|-------|---------|
| ID | SX-041 |
| Journey setup | `[SEED]` (same justification as SX-040): **R-fail** `state='Failed'`, `terminal_error_code='provider_unavailable'`, `completed_at` in-window, no attempts; **R-cx** `state='Cancelled'`, `completed_at` in-window, no attempts (a real zero-attempt cancel is producible — Stage 11 behavior — but seeding keeps the pair deterministic). |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | `missingAttemptRows` contains R-fail only. R-cx absent: the attempt query filters `state IN ('Completed','Failed')` — Cancelled is deliberately excluded from the attempt profile (a pre-first-byte cancel legitimately has none). |
| Side effects | None. |
| Code reference | ai-platform/src/rollup/index.ts:L150 — attempt-query state filter |

## Scenario SX-042 — Reconciliation flags Completed/Failed/Cancelled requests with no joinable `usage_event` (`missingUsageCredit`)

| Field | Content |
|-------|---------|
| ID | SX-042 |
| Journey setup | `[SEED]` three in-window rows, each with attempts but no `usage_event` (justified: real settlement always writes usage — doc 15 §6 — so a missing credit is by-definition an inconsistency): **R-c** Completed, **R-f** Failed, **R-x** Cancelled. |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | `missing_usage_credit=3`; report `missingUsageCredit` lists all three `{requestId, requestReference}` pairs — the usage query filters `state IN ('Completed','Failed','Cancelled')` with `LEFT JOIN usage_event u ON u.request_id = r.request_id … u.usage_event_id IS NULL`. |
| Side effects | None. |
| Code reference | ai-platform/src/rollup/index.ts:L157-L168 — usage-query state filter and join |

## Scenario SX-043 — `AwaitingContext` is excluded from both reconciliation reports

| Field | Content |
|-------|---------|
| ID | SX-043 |
| Journey setup | `[SEED]` **R-awc2** `state='AwaitingContext'`, `completed_at=<now − 1 day>` (in-window even though production leaves it NULL), no attempts, no usage (conversational-only state — same seed justification as SX-031). |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | Both report arrays empty for R-awc2: its state is in neither `('Completed','Failed')` nor `('Completed','Failed','Cancelled')`. Awaiting-context requests are deliberately outside the settlement profile. |
| Side effects | None. |
| Code reference | ai-platform/src/rollup/index.ts:L150 and L162 — both state filters |

## Scenario SX-044 — Reconciliation window boundaries are inclusive; `completed_at NULL` is excluded

| Field | Content |
|-------|---------|
| ID | SX-044 |
| Journey setup | `[SEED]` four Completed rows with no attempts: W0 `completed_at = <window start>` exactly; W1 `completed_at = <window end>` exactly; OUT `completed_at = <window start − 1 ms>`; NT `state='Accepted'`, `completed_at=NULL`. Direct call with explicit window `{start: "2026-08-10T00:00:00.000Z", end: "2026-09-05T00:00:00.000Z"}` for determinism. |
| Action | Direct call `runRollupAndReconciliation({db, window})`. |
| Expected outcome | `missingAttemptRows` = {W0, W1} — `completed_at >= ? AND completed_at <= ?` is inclusive at both ends. OUT excluded (1 ms early). NT excluded (NULL fails both comparisons). |
| Side effects | None. |
| Code reference | ai-platform/src/rollup/index.ts:L151-L152 — inclusive window predicates |

## Scenario SX-045 — Aged, retention-NULLed usage rows are never flagged as missing credit

| Field | Content |
|-------|---------|
| ID | SX-045 |
| Journey setup | SX-028 end state: R-old purged (91d), its `usage_event` survives with `request_id=NULL`, `recorded_at` 91 days ago. |
| Action | Run cron tick `"0 4 * * *"`. |
| Expected outcome | `missing_usage_credit=0` for this family, on both sides of the join: (1) the `ai_request` row is gone, so no request-centric row exists to flag; (2) the orphaned `usage_event` with NULL `request_id` can never match `u.request_id = r.request_id`, so it is invisible to reconciliation forever. Reconciliation coverage shrinks with age by design; the money row remains as commercial evidence and still rolls up (SX-053). |
| Side effects | None. |
| Code reference | ai-platform/src/rollup/index.ts:L131-L134 (design comment) and L157-L168 (request-centric LEFT JOIN); ai-platform/src/retention/index.ts:L211-L222 (the NULLing) |

## Scenario SX-046 — DO abandoned-admission sweep: stale in-flight admission dropped, `inFlight` decremented, idempotency marked `failed` with slid expiry

| Field | Content |
|-------|---------|
| ID | SX-046 |
| Journey setup | Real DO admission RPC for I0 at t0 (`jti='sx046-jti'`, key `sx046-key`, entitlement P1) → `admitted`, requestId **Q0**; never credited (Worker crash between admission and settlement — Stage 11 failure behavior). |
| Action | Any mutating DO RPC with injected `now = t0 + 7_200_001` — e.g. an admission RPC for a different key `sx046-probe` (body field `now`). Then `inspect`. |
| Expected outcome | `sweepAbandonedAdmissions` runs inside `sweepEphemeral`: Q0's `admittedRequests` entry (`admittedAt=t0 ≤ now−7_200_000`) is deleted; `periodCounters.inFlight` 1→0 (floored at 0); the matching idempotency entry `sx046-key` (state `admitted`) flips to `state='failed'` with `expiresAt = now + 7_200_000` (slid, so a retry replays as failed rather than a completed placeholder or a fresh admit). The probe admission itself succeeds (inFlight back to 1). Persisted: inspect afterwards shows the swept state. |
| Side effects | Writes: DO storage put (swept state + probe admission). No D1 writes. |
| Code reference | ai-platform/src/quota-do/index.ts:L209-L231 — `sweepAbandonedAdmissions`; L233-L254 — `sweepEphemeral`; L371 — sweep on admission; ai-platform/src/worker.ts:L1263-L1266 — `now` injection |

## Scenario SX-047 — Slid-window replay: retry inside the slid 2 h replays `failed`; after the slid window the key admits fresh

| Field | Content |
|-------|---------|
| ID | SX-047 |
| Journey setup | SX-046 end state at sweep time t1 = t0+7_200_001: idempotency `sx046-key` = `failed`, `expiresAt = t1 + 7_200_000`. |
| Action | (a) Admission RPC key `sx046-key`, new jti, `now = t1 + 3_600_000` (inside slid window). (b) Admission RPC same key, another new jti, `now = t1 + 7_200_001` (past slid expiry). |
| Expected outcome | (a) `outcome:"idempotent"`, `priorState.state='failed'`, `priorState.requestId=Q0` — the Worker replays SSE `failed`/`internal_error` (Stage 11 behavior), not a fresh admit, not a completed placeholder. (b) The entry was deleted by `sweepEphemeral` (`expiresAt <= now`), so this is a **fresh** `admitted` with a new requestId; `inFlight` increments; the key is not stuck. |
| Side effects | Writes: DO storage puts. No D1 writes from the DO. |
| Code reference | ai-platform/src/quota-do/index.ts:L223-L227 (slide) and L243-L247 (idempotency expiry); L383-L400 (idempotent outcome) |

## Scenario SX-048 — `jtiReplay` expiry: the same jti can admit again after 2 hours

| Field | Content |
|-------|---------|
| ID | SX-048 |
| Journey setup | Real admission at t0 with `jti='sx048-jti'` → admitted (jti entry `expiresAt=t0+7_200_000`). Doc-verified behavior (doc 15 §4): a second admission with the same jti at `now=t0+3_600_000` → `outcome:"replay"` (Worker maps to `unauthenticated` — Stage 8 behavior). |
| Action | Admission RPC, same `jti='sx048-jti'`, new idempotency key, `now = t0 + 7_200_001`. |
| Expected outcome | `sweepEphemeral` deletes the expired jti entry first; the admission proceeds to a fresh `admitted` (new requestId). Note the production bound (doc 18 §2): the 2 h JTI window already exceeds the 10-minute max AAT lifetime, so a still-valid token can never reach this branch — this scenario exercises it via injected `now` only. |
| Side effects | Writes: DO storage put (jti entry deleted, new admission state). |
| Code reference | ai-platform/src/quota-do/index.ts:L234-L238 — jti expiry; L373-L381 — replay check after sweep |

## Scenario SX-049 — `creditedRequests` blocks double-credit inside the window; after expiry the credit is `unknown_request` (never a second charge)

| Field | Content |
|-------|---------|
| ID | SX-049 |
| Journey setup | Real admission (t0) + real credit (t0, tokens 10) for requestId **Q9** — `creditedRequests[Q9].expiresAt = t0+7_200_000`, `admittedRequests[Q9]` deleted. |
| Action | (a) Credit RPC for Q9 again at `now=t0+3_600_000`. (b) Credit RPC for Q9 at `now=t0+7_200_001` (after a sweep — the credit RPC itself runs it). |
| Expected outcome | (a) `{kind:"credit", ok:false, code:"unknown_request"}` — `creditedRequests[Q9]` present; `periodCounters` unchanged (requestsUsed stays 1, tokensUsed 10). (b) Same `unknown_request` — the credited marker expired but so did any path to re-admit Q9; usage is never double-counted at any timescale. |
| Side effects | Writes: DO storage puts (sweep results only). Counters never move. |
| Code reference | ai-platform/src/quota-do/index.ts:L489-L499 — credit admission/credited gate; L249-L253 — creditedRequests expiry |

## Scenario SX-050 — `inspect` sweeps in memory only — persisted DO state is unchanged

| Field | Content |
|-------|---------|
| ID | SX-050 |
| Journey setup | Real admission at t0, never credited (inFlight=1, admittedAt=t0). |
| Action | (a) `inspectRPC` with `now = t0 + 7_200_001`. (b) `inspectRPC` again with `now = t0 + 60_000` (still inside the horizon). |
| Expected outcome | (a) Response shows the swept view: `admittedRequests` empty, `inFlight=0`, idempotency `failed` — but **no `storage.put`** ran. (b) The persisted state still holds the stale admission: `admittedRequests` has Q0, `inFlight=1` (t0+60 s is inside the 2 h horizon, so the real-time sweep keeps it). The operator snapshot can show a future that storage does not reflect. |
| Side effects | None — inspect never persists (contrast with admission/credit/release, which put swept state). |
| Code reference | ai-platform/src/quota-do/index.ts:L610-L622 — `inspectRPC` (load, sweep, return; no put) |

## Scenario SX-051 — Period rollover on admission: counters reset, `inFlight` preserved across the boundary

| Field | Content |
|-------|---------|
| ID | SX-051 |
| Journey setup | Real admission+credit in period P1 (`2026-08`): requestsUsed=1, tokensUsed=10. A second admission in P1 left uncredited (inFlight=1). Entitlement rolled (Stage 3 control-plane behavior: new period P2 `2026-09-01`→`2026-10-01`). |
| Action | Admission RPC with entitlement snapshot P2 (new key/jti). Then `inspect`. |
| Expected outcome | `maybeResetPeriod` sees bounds differ from stored `periodBounds`: `periodCounters` reset to `{requestsUsed:0, tokensUsed:0, costUsed:0, inFlight:1}` — the in-flight reservation survives the rollover (it is still holding a slot), usage counters do not. The new admission then increments inFlight to 2. `periodBounds` now P2. |
| Side effects | Writes: DO storage put. No D1 writes (the D1 entitlement row was changed by the control plane, not the DO). |
| Code reference | ai-platform/src/quota-do/index.ts:L257-L274 — `maybeResetPeriod` (inFlight carry); L372 — called on admission |

## Scenario SX-052 — Period rollover on credit: usage lands in the new period's counters

| Field | Content |
|-------|---------|
| ID | SX-052 |
| Journey setup | Admission in P1 (uncredited, inFlight=1, counters {1,10,0.001} from a prior credit). Entitlement rolled to P2. |
| Action | Credit RPC for the admitted requestId with `entitlement` = P2 snapshot (the Worker sends the admission-time snapshot; here the rolled one — Stage 11 settlement behavior), usage tokens 5, cost 0.0005. |
| Expected outcome | `creditRPC` resolves `entitlement = request.entitlement ?? admitted.entitlement`, re-runs `maybeResetPeriod` **before** applying usage: counters reset (preserving inFlight=1), then usage applies into the P2 counters → `{requestsUsed:1, tokensUsed:5, costUsed:0.0005, inFlight:0}`. The P1 usage (10 tokens) is gone from DO counters — D1 `usage_event` remains the durable per-period record (`period` column from the admission-time snapshot). |
| Side effects | Writes: DO storage put. |
| Code reference | ai-platform/src/quota-do/index.ts:L500-L510 — credit-time `maybeResetPeriod` then counter application |

## Scenario SX-053 — Retention → rollup joinability journey: purge at 03:00, rollup at 04:00; aged money still aggregates, purged requests absent from missing-usage

| Field | Content |
|-------|---------|
| ID | SX-053 |
| Journey setup | SX-028 end state (R-old purged at the 03:00 tick; its `usage_event` — period `2026-08`, tokens 30, cost 0.003, `request_id=NULL` — survives). R-new (fresh Completed, tokens 40, same period) intact. |
| Action | Run cron tick `"0 4 * * *"` (the next scheduled run after the purge). |
| Expected outcome | `rollups_written=1`: `(I0,2026-08)` aggregates **both** usage rows — `request_count=2, tokens=70, cost=0.007` — because rollup groups by `installation_id, period` and never touches `request_id`; retention-NULLed money still closes the month. Reconciliation: `missing_usage_credit=0` — R-old no longer exists request-side and its NULLed usage can never join (SX-045); R-new is fully wired. The two crons compose: purge shrinks reconciliation coverage, never rollup coverage. |
| Side effects | Writes: one `usage_rollup` upsert. |
| Code reference | ai-platform/src/rollup/index.ts:L70-L82 — request-id-agnostic aggregation; ai-platform/src/retention/index.ts:L211-L222 — the NULLing that precedes it |

## Scenario SX-054 — Retention → lookup journey: journal-purged reference 404s for the clinic and returns nothing for support

| Field | Content |
|-------|---------|
| ID | SX-054 |
| Journey setup | SX-028 end state: R-old (`request_reference='SX05-4000'`) fully journal-purged. I0's AAT still valid. |
| Action | `GET /v1/requests/SX05-4000` with I0's AAT (Stage 12 behavior). Operator support lookup `POST /control/support/lookup?reference=SX05-4000` (Stage 12 behavior). |
| Expected outcome | Client GET: HTTP 404 empty body — `getRequest` finds no row (`found:false`). Support lookup: not-found/empty projection (Stage 12 behavior — the envelope object is gone too, so even a dangling pointer could not resolve). The request is unrecoverable by either audience; only the `usage_event` money row and the `usage_rollup` aggregate remain. |
| Side effects | None (reads). |
| Code reference | ai-platform/src/worker.ts:L1396-L1409 — 404 on `!result.found`; ai-platform/src/journal/index.ts:L468-L485 — `getRequest` miss |

## Scenario SX-055 — Diagnostic purge → lookup journey: Completed row with NULL `payload_pointer` returns state without `result`

| Field | Content |
|-------|---------|
| ID | SX-055 |
| Journey setup | SX-024 end state: R-diag (31d old) — `ai_request` row present, `state='Completed'`, `payload_pointer=NULL`, envelope deleted. |
| Action | `GET /v1/requests/<R-diag reference>` with I0's AAT (Stage 12 behavior). Operator support lookup for the same reference (Stage 12 behavior). |
| Expected outcome | Client GET: HTTP 200 `{"state":"Completed"}` with **no** `result` key — `getRequest` hits the `resultMissing` branch (pointer NULL) and worker.ts L1412-L1420 omits `result` when it is absent. Support lookup: row projection with `envelope: null` (Stage 12 behavior — outside the diagnostic class). The terminal record outlives its diagnostic payload by design. |
| Side effects | None (reads). |
| Code reference | ai-platform/src/worker.ts:L1412-L1420 — Completed with/without `result`; ai-platform/src/journal/index.ts:L487-L495 — `resultMissing` on NULL pointer |

## Scenario SX-056 — One 03:00 tick does it all: tally flush, grace reconcile, and retention purge compose in a single run

| Field | Content |
|-------|---------|
| ID | SX-056 |
| Journey setup | Combined realistic state: (1) two `quota_exhausted` rejections tallied this minute; (2) pending grace row `grace-sx056` with attached usage (tokens 7, cost 0.007, partial 0), real healthy DO; (3) `[SEED]` 91-day-old Completed request R-old with attempts/usage/envelope; (4) `[SEED]` 31-day-old Completed request R-diag with envelope; (5) fresh Completed request R-new as control. |
| Action | Run cron tick `"0 3 * * *"` once. |
| Expected outcome | Single run, ordered logs per SX-001. Final state: `platform_counter` one row count=2; `grace-sx056.status='reconciled'` and DO counters `{requestsUsed:1, tokensUsed:7, costUsed:0.007, inFlight:0}`; R-old journal-purged (usage NULLed, envelope gone); R-diag diagnostic-purged (row kept, pointer NULL, envelope gone); R-new untouched. `retention_purge_complete{diagnostic_deleted:1, journal_deleted:2, ledger_deleted:0, counter_deleted:0}`. No rollup rows (not this cron). |
| Side effects | Writes: exactly the union of the three jobs' writes listed above; nothing else in D1/DO/R2 changes. |
| Code reference | ai-platform/src/worker.ts:L1447-L1495 — `scheduled` (full 03:00 path) |

## Scenario SX-057 — GatewayObject rejects a non-POST call with 405

| Field | Content |
|-------|---------|
| ID | SX-057 |
| Journey setup | Stage 0 boot happy path; the `GatewayObject` DO is addressable in-pool via the same direct-RPC seam SX-046…SX-052 use (`DO.idFromName("quota:inst_01J4ZEXAMPLE0000000000000")` → `stub.fetch`). Production frame: the worker only ever POSTs to the DO; a misconfigured internal caller issuing GET is the realistic misuse. |
| Action | `GET` against the DO stub URL `https://quota-do.internal/rpc` (no body). |
| Expected outcome | HTTP 405, plain-text body `Method Not Allowed` — the method guard runs before any body parsing. |
| Side effects | None: no DO storage reads or writes; no D1 writes. |
| Code reference | ai-platform/src/worker.ts:L1251-L1253 — `GatewayObject.fetch` method guard |

## Scenario SX-058 — GatewayObject rejects malformed JSON with 400 invalid_json

| Field | Content |
|-------|---------|
| ID | SX-058 |
| Journey setup | Same direct-DO-RPC seam as SX-057. Production frame: a corrupted internal payload (truncated buffer) reaching the DO. |
| Action | `POST` to the DO stub with body `{"kind":"admission","installationId":` (truncated JSON). |
| Expected outcome | HTTP 400, body `{"error":"invalid_json"}`; error log `gateway_object_invalid_json`. |
| Side effects | None: parsing fails before `kind` dispatch; no storage writes. |
| Code reference | ai-platform/src/worker.ts:L1254-L1259 — JSON parse guard in `GatewayObject.fetch` |

## Scenario SX-059 — GatewayObject rejects an unknown RPC kind with 400 unknown_kind

| Field | Content |
|-------|---------|
| ID | SX-059 |
| Journey setup | Same direct-DO-RPC seam as SX-057. Production frame: a newer worker build calling a kind this DO build does not implement (version skew during rollout). |
| Action | `POST` to the DO stub with body `{"kind":"obliterate","installationId":"inst_01J4ZEXAMPLE0000000000000","now":1757000000000}`. |
| Expected outcome | HTTP 400, body `{"error":"unknown_kind"}`; error log `gateway_object_unknown_kind` with `kind: "obliterate"`. |
| Side effects | None: no RPC invoked, no storage writes. |
| Code reference | ai-platform/src/worker.ts:L1319-L1320 — unknown-kind fallthrough in `GatewayObject.fetch` |

## Scenario SX-060 — Real-DO admission with missing args → 400 bad_request

| Field | Content |
|-------|---------|
| ID | SX-060 |
| Journey setup | Same direct-DO-RPC seam as SX-057 — crucially this exercises the **real** `GatewayObject` asserts (contrast S09-079, which scripts a 400 from a namespace double). Production frame: a worker bug emitting a malformed admission payload. |
| Action | `POST` to the DO stub with body `{"kind":"admission","installationId":"inst_01J4ZEXAMPLE0000000000000","requestReference":"AAAA-AAAA"}` — `jti`, `idempotencyKey`, and `entitlement` missing. |
| Expected outcome | HTTP 400, body `{"error":"bad_request"}` — `assertAdmissionArgs` throws `ArgValidationError("invalid_admission_args")` and the catch maps it to 400 (never to grace/500). |
| Side effects | None: `admissionRPC` never runs; no `admittedRequests`/`jtiReplay`/`idempotency` storage writes. |
| Code reference | ai-platform/src/worker.ts:L1164-L1175 — `assertAdmissionArgs`; ai-platform/src/worker.ts:L1311-L1315 — `isArgValidationError` → 400 mapping |

## Scenario SX-061 — Real-DO credit with wrong-typed args → 400 bad_request

| Field | Content |
|-------|---------|
| ID | SX-061 |
| Journey setup | Same direct-DO-RPC seam as SX-057. |
| Action | Two POSTs: (1) `{"kind":"credit","installationId":"inst_01J4ZEXAMPLE0000000000000","requestId":"req_01J4ZEXAMPLE0000000000001","requestReference":"AAAA-AAAA","usage":{"tokens":10,"cost":0.001},"partial":"yes"}` (`partial` not boolean); (2) same body but `"partial":false,"idempotencyState":"exploded"` (not in `failed`/`cancelled`/`completed`). |
| Expected outcome | Both HTTP 400 `{"error":"bad_request"}` — `assertCreditArgs` throws `ArgValidationError("invalid_credit_args")` on both the wrong-typed `partial` and the out-of-set `idempotencyState`. |
| Side effects | None: `creditRPC` never runs; no `usage_event`, no counter mutation, no `creditedRequests` write. |
| Code reference | ai-platform/src/worker.ts:L1178-L1208 — `assertCreditArgs` (incl. the `idempotencyState` allowlist); ai-platform/src/worker.ts:L1311-L1315 — 400 mapping |

## Scenario SX-062 — Real-DO release with missing args → 400 bad_request

| Field | Content |
|-------|---------|
| ID | SX-062 |
| Journey setup | Same direct-DO-RPC seam as SX-057. |
| Action | `POST` to the DO stub with body `{"kind":"release","installationId":"inst_01J4ZEXAMPLE0000000000000","requestId":"req_01J4ZEXAMPLE0000000000001"}` — `idempotencyKey` and `jti` missing. |
| Expected outcome | HTTP 400, body `{"error":"bad_request"}` — `assertReleaseArgs` throws `ArgValidationError("invalid_release_args")`. |
| Side effects | None: `releaseRPC` never runs; in-flight state (if any) unchanged. |
| Code reference | ai-platform/src/worker.ts:L1211-L1220 — `assertReleaseArgs`; ai-platform/src/worker.ts:L1311-L1315 — 400 mapping |

## Scenario SX-063 — DO RPC unexpected throw → 500 internal_error (fault seam)

| Field | Content |
|-------|---------|
| ID | SX-063 |
| Journey setup | Same direct-DO-RPC seam as SX-057, plus a storage-fault seam: a DO `storage` double whose `get`/`put` throws (simulating a storage-layer outage mid-admission). **[Seam]** — real DO storage cannot be forced to fail in the pool; this is the DO-side counterpart of Register 5's fault-injection entries. |
| Action | `POST` a fully valid admission body `{"kind":"admission","jti":"jti-sx063-0001","installationId":"inst_01J4ZEXAMPLE0000000000000","idempotencyKey":"idem-sx063-0001","requestReference":"AAAA-AAAA","entitlement":{...valid snapshot...}}` against the faulting-storage DO. |
| Expected outcome | HTTP 500, body `{"error":"internal_error"}` — the throw is not an `ArgValidationError`, so the catch logs `gateway_object_rpc_failed` (with `kind`, `installation`, `request_reference`, `jti` fields) and returns 500. Distinct from the 400 `bad_request` arg path (SX-060…SX-062). |
| Side effects | None beyond the failed storage attempt; the error log carries the request identifiers. |
| Code reference | ai-platform/src/worker.ts:L1311-L1317 — catch-all → 500; ai-platform/src/worker.ts:L1224-L1246 — `logGatewayRpcFailure` |

## Doc-drift observations

Verified doc-15 failure journeys against code (each is a scenario here or belongs to another stage chapter):

- Doc 15 §1 (lifecycle alternatives) — control-plane chapter (Stage 3); not cron. §2 (zero quotas) and §4 (JTI replay) and §8 matrix stage-8 rows — Stage 8 admission chapter; this catalog covers only the 2 h JTI expiry side (SX-048). §3 (missing routing policy) — Stage 10 invoke chapter. §6 (client disconnect) and §7 (prose guards) — Stage 11 settlement chapter. §5 (grace + cron reconcile), §9 (retention joinability), §10 (counters lower bound) — this chapter (SX-010…SX-023, SX-028/SX-053, SX-005…SX-009 respectively). §11.3.6 / §11.3.10 probe claims verified against code and encoded as scenarios.
- **Doc 15 §5 / §11.3.6 is incomplete on reconcile outcomes.** Code has five drop reasons (`GraceDropReason`, credit/index.ts L51-L57): `expired`, `max_attempts`, `settled_by_another_path_idempotent`, `settled_by_another_path_replay`, `settled_by_another_path_unknown_request`. The doc mentions only TTL/max-attempt drops and the happy reconcile. SX-015…SX-017 are code-derived, doc-silent.
- **Doc 15 is silent on reconcile-time `quota_exhausted`/`concurrency_exhausted`:** any non-admitted/non-idempotent/non-replay admission outcome is retried, not dropped (SX-014) — a grace entry for an exhausted installation churns until TTL/max-attempts and its usage is never credited.
- **Doc 15 is silent on the SX-018 leak:** reconcile admit succeeds but credit transport fails → next tick's admission is a jti `replay` → the entry is dropped `settled_by_another_path_replay`, the attached usage is never credited, and the DO-side in-flight slot leaks until the 2 h abandoned sweep (SX-046) marks it `failed`.
- **Doc 15 §11.3.6 vs doc 17 §3.3.15 trigger URL inconsistency:** the former fires `/cdn-cgi/handler/scheduled?cron=…`, the latter `/__scheduled?cron=…`. Code-agnostic (Wrangler test endpoint), but the docs disagree with each other.
- **Doc 17 §3.3.15 coverage table compresses two purges:** "deletes the envelope and nulls `payload_pointer` (90d journal horizon)" — the pointer NULLing happens at the **diagnostic** horizon (30d for visit-summary, SX-024); the 90d journal purge deletes the row (SX-028). The probe body itself is correct.
- **Doc 15 §9 / doc 16 §10 omit most of the retention surface.** Code also purges `usage_rollup` (period < cutoff month, SX-034), `control_audit` and `capability_grant` (2555d, SX-035 — including *live* grants untouched for 7 years), and `platform_counter` (90d, SX-036). Docs mention only `usage_event`/`ai_request`/`ai_attempt`.
- **Doc 16 §14 / doc 15 §5:** `reconcile_first_seen_at_ms` as "first cron sighting (TTL origin)" is accurate, but neither doc states that TTL therefore cannot fire on first sighting and that `queued_at` age is irrelevant (SX-021).
- **Doc 18 §4 ordering nit:** "abandoned-admission handling first, then deletes idempotency entries" — true relative to idempotency, but `sweepEphemeral` deletes expired `jtiReplay` entries *before* the abandoned sweep (quota-do/index.ts L233-L254). Observable only in ordering, not outcome.
- **`usage_rollup` has no in-repo reader.** Dashboards never select it (dashboards/index.ts reads `ai_attempt`/`ai_request`/`platform_counter` only); the rollup cron writes a table nothing in the Worker consumes. Docs describe the columns but not the absence of a consumer.
- **No injection through the scheduled handler.** `runRetentionPurge`'s `bindings.now`, `RollupBindings.window`, and `ReconcileGraceContext.now` are unreachable via cron (worker.ts passes none); docs don't state this. Scheduled-handler tests must backdate `[SEED]` rows against real wall clock; only direct job-function calls can inject time (SX-026, SX-029, SX-033…SX-035, SX-038, SX-044).
- **No DO alarm.** `quota-do/index.ts` defines no `alarm()` handler; all sweeps are lazy, driven by the next RPC (or read-only via `inspect`, SX-050). Doc 18 does not claim an alarm — recorded here per mission, not as drift.
- **`kill_switch` is immortal under cron** (no `DELETE FROM kill_switch` anywhere in retention) — docs silent; SX-036.
- **No try/catch in `scheduled()`** — a flush failure aborts reconcile and the cron-specific job (SX-004); docs silent.
- `request-lifecycle-brief.md` L106/L266-L267 (tally flush on cron, grace queue writers) — consistent with code; no drift.

## Non-automatable notes

- **Cross-isolate tally loss (the lower bound itself).** `@cloudflare/vitest-pool-workers` runs one isolate; there is no second isolate whose in-memory tally can be evicted unflushed. SX-005…SX-008 cover everything observable in-isolate; the multi-isolate loss is document-only (rate-limit/index.ts L149-L158 comment).
- **Genuine Quota DO outage/eviction.** Real DO unavailability (5xx, network, state eviction between RPCs) cannot be produced against the in-pool DO. Scenarios SX-013, SX-017, SX-018, SX-022 use a stub/facade `DurableObjectNamespace` whose `stub.fetch` throws or scripts responses; the real GatewayObject covers all state-machine assertions.
- **Mid-flush / mid-tick D1 failure.** Real D1 in the pool does not fail on demand; SX-004 and SX-008 use a proxy shim around the binding that throws on targeted SQL. The production failure mode itself (D1 incident) is not reproducible.
- **Platform cron triggering.** Whether Cloudflare fires `0 3 * * *` at 03:00 UTC is platform behavior; all scenarios invoke `worker.scheduled({cron})` directly. `ScheduledController.retry`/`noRetry` semantics are not exercised — the handler never calls them.
- **Wall-clock horizons.** 90d/2555d/2h waits are never performed; they are forced by `[SEED]` backdating (retention, reconciliation windows) or injected `now` (DO RPC body field, worker.ts L1263-L1266; direct job-function args). This is by design, listed here so implementers don't "simplify" scenarios into sleeps.
- **`AwaitingContext` and unpublished-capability rows** cannot be produced by any real operation on the current catalog (single-shot visit-summary only; one bundled manifest). SX-031, SX-043, SX-025 seed them with justification; if a conversational capability ships, replace the seeds with real operations.
