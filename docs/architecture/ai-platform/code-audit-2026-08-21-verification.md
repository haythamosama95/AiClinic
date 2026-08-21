# AI Platform Code Audit — Verification of Fixes (2026-08-21)

Independent verification that the 48 findings in
`docs/architecture/ai-platform/code-audit-2026-08-21.md` (all marked **Done**)
are actually fulfilled by the modified working tree under `ai-platform/`.
Every verdict below is backed by reading the current code (and, where the fix
was docs-only, the data-journey docs). Code evidence was extracted verbatim by
mechanical passes and cross-checked against the audit's **Fix** sections before
each verdict was assigned.

## Table of Contents

1. [Method](#1-method)
2. [Verdict Summary](#2-verdict-summary)
3. [Chunk 1 — P0: default request path](#3-chunk-1--p0-default-request-path)
4. [Chunk 2 — P1: authorization and security](#4-chunk-2--p1-authorization-and-security)
5. [Chunk 3 — P1/P2: routing and invocation](#5-chunk-3--p1p2-routing-and-invocation)
6. [Chunk 4 — P2: settlement, journaling, accounting](#6-chunk-4--p2-settlement-journaling-accounting)
7. [Chunk 5 — P3: dead fields, dead features, ignored data](#7-chunk-5--p3-dead-fields-dead-features-ignored-data)
8. [Chunks 6–7 — output guards and extraction-pass findings](#8-chunks-67--output-guards-and-extraction-pass-findings)
9. [New Findings (major/critical only)](#9-new-findings-majorcritical-only)
10. [Conclusion](#10-conclusion)

---

## 1. Method

- Verified the uncommitted working tree on `ai/master` (the audit's fixes are
  the pending modifications plus new files: `src/pricing/`, `src/provider/raw-body.ts`,
  `src/provider/readable-body.ts`, `src/provider/fetch-transport.ts`,
  `src/wall-clock-sleeper.ts`, two new migrations, `control/pricing/`).
- Full test suite run: `npm test` (manifest gates + unit + workers config) —
  **463 tests, 25 files, all passing**.
- Verdicts: **Verified** = the prescribed fix is present and correct in code;
  **Verified (variation)** = the issue is closed by an implementation that
  differs from the letter of the fix but satisfies its intent;
  **Not verified** = the claimed fix is missing or incorrect.

## 2. Verdict Summary

| Chunk | Findings | Verified | Verified (variation) | Not verified |
| ----- | -------- | -------- | -------------------- | ------------ |
| 1 (P0) | 1.1–1.6 | 5 | 1 (1.4 cap mechanism) | 0 |
| 2 (P1 security) | 2.1–2.7 | 7 | 0 | 0 |
| 3 (routing/invocation) | 3.1–3.6 | 6 | 0 | 0 |
| 4 (settlement/accounting) | 4.1–4.8 | 8 | 0 | 0 |
| 5 (dead fields) | 5.1–5.10 | 10 | 0 | 0 |
| 6 (output guards) | 6.1–6.5 | 5 | 0 | 0 |
| 7 (extraction pass) | 7.1–7.6 | 6 | 0 | 0 |
| **Total** | **48** | **47** | **1** | **0** |

New major/critical issues found during verification: **none** (see §9).

## 3. Chunk 1 — P0: default request path

### 3.1 Finding 1.1 (DeepSeek `role: "data"` on the wire) — Verified

`src/provider/deepseek.ts` now translates canonical roles before wiring:
`mapRoleToDeepSeek` (lines 199–207) maps `system`/`assistant` through and
everything else — including `"data"` — to `"user"`, and `mapCanonicalToWire`
(lines 209–243) applies it to every message part. `stream_options.include_usage`
is set whenever `stream` is true. The Gemini adapter already translated; the
two adapters now behave consistently. The role-validating adapter test exists
(`test/deepseek-adapter.test.ts`, modified).

### 3.2 Finding 1.2 (manifest vs policy fixture mismatch) — Verified

(a) The checked-in artifacts now agree: the manifest pins
`routingPolicyRef: "routing/standard@v1"` and `latencyClass: "standard"`
(`manifests/published/clinic.visit_summary@1.0.0.json` lines 44–52); the
fixture declares `policy_id: "standard"`, `policy_version: 1`, and both targets
carry `latency_class: "standard"`
(`control/routing-policy/platform-default/1.json`).

(b) Publish-time validation landed in `src/control/routing-policy.ts`: the
handler rejects with 400 `policy_identity_mismatch` when the document's
`policy_id`/`policy_version` do not match the publish ref (lines 182–189), and
`latencyMismatchWarnings` (lines 91–118) returns a `latency_class_mismatch`
warning when no target matches a referencing manifest's latency class.

### 3.3 Finding 1.3 (no-op sleeper) — Verified

`src/worker.ts` wires `sleeper: wallClockSleeper` into `runInvocation`
(line 876); `src/wall-clock-sleeper.ts` is a real `setTimeout`-based sleep.
`sleepWithinDeadline` (`src/invocation/index.ts` lines 416–432) still bounds
the sleep against the deadline, so backoff and `Retry-After` are now effective
in production.

### 3.4 Finding 1.4 (grace admission) — Verified (variation)

All four defects are closed:

1. **Cross-isolate state.** Module-scope Maps are gone (`drainPendingGraceAdmissions`
   and `resetGraceAdmissionCounter` are now documented no-ops,
   `src/admission/index.ts` lines 358–364, 401–402). The queue and the cap live
   in D1: migration `20260821120000_grace_admission_queue.sql` creates the
   table with `UNIQUE (installation_id, idempotency_key)`, and the admit path
   enforces `GRACE_ADMISSION_CAP` via an atomic
   `INSERT … SELECT … WHERE (SELECT COUNT(*) …) < ?` (lines 517–541).
   *Variation:* the audit suggested a DO-held counter for the cap; the D1
   `COUNT(*)`-guarded insert achieves the same cross-isolate enforcement and
   the fix text explicitly allowed "a D1 table the cron drains".
2. **Idempotency dedupe.** `admitUnderGrace` (lines 483–512) checks D1
   `ai_request` by `(installation_id, idempotency_key)` first, then the grace
   queue by the same key, returning the prior outcome on a hit.
3. **Quota check.** `isLedgerQuotaExhausted` (lines 258–296) applies
   request/token/cost budgets from the entitlement snapshot against D1 before
   admitting, rejecting with `quota_exhausted`.
4. **Real usage credited.** `attachGraceUsage` now UPDATEs the queue row with
   actual tokens/cost (lines 377–399) and is called from the `creditUsage`
   wrapper (`src/credit/index.ts` lines 204–218); `reconcileGraceUsage`
   (lines 255–347) drains D1 rows, credits `entry.usage` (real values, not
   phantom zeros), and marks rows `reconciled`/`dropped` with TTL and max-attempt
   bounds.

### 3.5 Finding 1.5 (failure/cancel paths never credit) — Verified

A single `settleTerminal` helper (`src/worker.ts` lines 482–532) credits the DO
with accrued-or-zero usage plus the taxonomy-derived `partial` flag and a
truthful terminal idempotency state, then writes the settlement journal. It is
called from every non-completed outcome: invocation cancel (lines 912–940),
invocation failure (lines 943–974), and broker/prose-guard non-completed
terminals (lines 980–1001, with `skipCredit` where the broker already
credited). The stream broker's `handleCancel`/`handleFailed`
(`src/stream/index.ts` lines 258–325) both call `safeCredit` with a
`{tokens: 0, cost: 0}` fallback, so `inFlight` is released and the idempotency
entry leaves `"admitted"` even at zero usage.

### 3.6 Finding 1.6 (idempotency state machine) — Verified

1. `markIdempotencyOnCredit` (`src/quota-do/index.ts` lines 339–356) takes a
   terminal-status parameter; settle paths write `"failed"`/`"cancelled"`.
2. `sweepAbandonedAdmissions` (lines 208–231) transitions swept entries to
   `"failed"` — crashed requests replay as failures, not the "completed"
   placeholder. `replayIdempotentTerminal`'s `"failed"` branch
   (`src/worker.ts` lines 595–629) is now live.
3. `expiresAt` slides forward on every transition: admission, credit
   (line 352), and sweep (line 225) all set `now + EPHEMERAL_HORIZON_MS`.
4. The unreachable `"in_progress"`/`"awaiting_context"` states were **removed
   from the state type** (no occurrences remain in `src/quota-do/`) — the fix's
   "no states without writers" option. The accepted leftover (an actively
   in-flight `"admitted"` entry replaying as the completed placeholder) is
   unchanged, as recorded in the audit.

## 4. Chunk 2 — P1: authorization and security

### 4.1 Finding 2.1 (`requiredCapabilityScope`) — Verified

`assertPlanAllowance` (`src/capability/index.ts` lines 210–296) rejects with
`forbidden_capability` when the manifest's `requiredCapabilityScope` is set and
absent from `principal.scopes`. Called from capability `resolve` at guard
stage 5 (`src/pipeline/index.ts` lines 374–385). Pure membership check against
already-loaded data — no new I/O.

### 4.2 Finding 2.2 (`allowedStaffRoles`) — Verified

Same function: when `Access.allowedStaffRoles` is non-empty and
`principal.role` is not a member, `forbidden_capability`
(`src/capability/index.ts` lines 274–281).

### 4.3 Finding 2.3 (manifest `killSwitchFlag`) — Verified

`evaluateCapabilityKillSwitches` (`src/capability/index.ts` lines 404–439)
returns `capabilityDisabled: true` when `manifest.Access.killSwitchFlag === true`,
and `resolve` maps that to `capability_disabled` (lines 601–616) alongside the
D1 `kill_switch` checks (`global`, `capability:<id>`, `installation:<id>`).

### 4.4 Finding 2.4 (AAT max lifetime) — Verified

`MAX_AAT_LIFETIME_SECONDS = 600` (`src/identity/index.ts` lines 42–43) and the
verifier rejects `exp - iat > 600` with `unauthenticated` (lines 286–295). The
DO JTI replay window (`EPHEMERAL_HORIZON_MS = 7_200_000`, 2 h) comfortably
exceeds the 10-minute maximum token lifetime, so a token can never outlive its
replay entry.

### 4.5 Finding 2.5 (key rotation) — Verified

`handleRotate` (`src/control/lifecycle.ts` lines 239–321) now batches, with the
new-key insert, an `UPDATE installation_key SET revoked_at = ? … WHERE
revoked_at IS NULL` that retires all active keys for the installation. New keys
get a real `valid_until` (`INSTALLATION_KEY_TTL_DAYS = 365`, lines 21–28), also
written at enroll (lines 204–215). The verifier enforces the window:
`isKeyWithinValidityWindow` rejects keys past `valid_until`
(`src/identity/index.ts` lines 211–232, 317–323). The column is live.

### 4.6 Finding 2.6 (conversational tenant binding) — Verified

`validateConversationalContext` (`src/context/validator.ts` lines 329–428) now
applies `contextMatchesPrincipal` (org/branch equality) to the supplied context
**and** to every `context_resolved` turn payload, failing with
`context_invalid` on mismatch — the same binding as the single-shot path.

### 4.7 Finding 2.7 (provider kill switch) — Verified

(1) Guard stage 5 distinguishes levels: capability-level switches
(`global` / `capability:<id>` / `installation:<id>`) produce
`capability_disabled`; `provider:<id>` switches are collected by
`collectActiveProviderKillSwitches` and returned on the resolve result instead
of failing the request (`src/capability/index.ts` lines 377–439, 618–622).
(2) The killed set reaches the router two ways: the guard threads
`killedProviderIds` through the pipeline into the worker's
`selectCandidateChain` context (`src/pipeline/index.ts` lines 387, 542;
`src/worker.ts` lines 731–747), and the router additionally merges
cache-consulted kills via `mergeKilledProviderIds` (`src/router/index.ts`
lines 432–462, 634–645) — which now works in production because the cache is
isolate-scoped (5.5). `filterTargets` excludes killed providers with
`reason_code: "kill_switch"` (lines 464–485), so traffic fails over to the
remaining chain targets.

## 5. Chunk 3 — P1/P2: routing and invocation

### 5.1 Finding 3.1 (`max_parallel_attempts`) — Verified

Removed from `RoutingDecision` (`src/router/index.ts` lines 68–78) and not
consumed by `runInvocation` (explicit comment at `src/invocation/index.ts`
lines 522–524). The policy-schema field is retained with a "schema-retained,
not read" comment (lines 136–141, 160–165) — matching the fix's preferred
outcome (no parallel racing; token-spend rationale preserved).

### 5.2 Finding 3.2 (fail-open filters) — Verified

`filterTargets` (`src/router/index.ts` lines 464–580) is now uniformly fail
closed: missing/non-finite `min_context_window` → `feature_unsupported`;
missing/non-array `languages` → `feature_unsupported` (no more `TypeError`);
unknown/missing `cost_class` → `feature_unsupported`; latency stays exact-match.
Known-but-insufficient values keep their distinct reasons
(`context_window_too_small`, `language_unsupported`, `cost_class_excluded`).

### 5.3 Finding 3.3 (`routing_decision` persistence) — Verified

`persistRoutingDecision` (`src/journal/index.ts` lines 289–302) serializes the
full decision (policy id/version, rule, effective cost class + source, tier,
required features, chain, excluded-with-reasons) onto the existing
`ai_request` row; called from the worker before invoke (`src/worker.ts`
lines 753–757). The locked test `routing_decision_persisted_at_stage_10`
passes.

### 5.4 Finding 3.4 (truncated output completes authoritative) — Verified

Both halves landed: (1) `runInvocation` no longer returns `ok: true` for
truncation — a chain exhausted via truncation returns
`ok: false` with `validation_failed` (`src/invocation/index.ts` lines 644–674,
749–754); (2) `createChunkSourceFromInvocationEvents` implements
`wasTruncated()` with regeneration reset (`src/stream/index.ts` lines 44–75),
so the broker guard (`chunkSource.wasTruncated?.()` → `validation_failed`) and
the structured safety phase (`output.truncated`) both have a live sensor.

### 5.5 Finding 3.5 (batch streaming) — Verified

All three stages: (1) `stream: true` goes on the wire (5.2 below); (2) both
adapters parse SSE incrementally — `readSseDataPayloads` streams a
`ReadableStream` reader through a UTF-8 decoder with byte limits
(`src/provider/readable-body.ts`; used at `deepseek.ts` line 800 and
`gemini.ts` line 893), and the production transport passes `response.body`
through without buffering (`src/provider/fetch-transport.ts`); (3) invocation
passes `onStreamChunk` into `port.invoke` and emits text deltas through
`InvocationSink.emitStreamText` as they arrive (`src/invocation/index.ts`
lines 373–378, 623–638).

### 5.6 Finding 3.6 (`retryAfterMs` nullified) — Verified

Invocation delay is `Math.max(jittered, retryAfterMs)` fed to the now-real
sleeper (`src/invocation/index.ts` lines 702–724; 1.3). Guard-stage
`rate_limited` threads the Rate Limit binding hint:
`checkRateLimit` → `GuardFailure.retryAfter` → `PreAcceptResult` →
`preAcceptFailureResponse` via `supplementaryFieldsForCode` /
`retryAfterSecondsForRateLimited` (`src/rate-limit/index.ts` lines 89–146;
`src/pipeline/index.ts` lines 152–209, 368–371; `src/adapter.ts` lines
213–228, 433–438; `src/errors.ts` lines 179–202).

## 6. Chunk 4 — P2: settlement, journaling, accounting

### 6.1 Finding 4.1 (hardcoded costs) — Verified

A versioned price table exists at `control/pricing/platform-default/1.json`
(per-model input/output rates per 1K tokens plus a default), bundled and
validated by `src/pricing/index.ts` (`PLATFORM_PRICING_TABLE`, `priceUsage`,
`ledgerUsageFromProvider`). Both former hardcodes are gone:
`usageFieldsFromResult` (`src/invocation/index.ts` lines 196–210) prices
`ai_attempt.cost` from provider-reported tokens, and `settleCompletedRequest`
(`src/worker.ts` lines 534–579) prices the `usage_event` row through the same
`ledgerUsageFromProvider` helper — the test
`completed_attempt_and_usage_event_cost_agree` locks the agreement. Remaining
`cost: 0` occurrences are legitimate zero-usage fallbacks (terminal settle with
no accrued usage, grace entries without usage). Money stays post-response;
the preflight remains token-only.

### 6.2 Finding 4.2 (cancelled requests leave no billing rows) — Verified

The cancel path settles through `settleTerminal` → `writeSettlementJournal` →
`persistPostResponseDetail`, which writes the `ai_attempt` rows and a
`usage_event` row from the same statements used for completion
(`src/journal/index.ts` lines 377–424; `src/worker.ts` lines 482–532,
912–940). The passing test `cancel_disconnect_aborts_cancelled_credits_partial
> writes ai_attempt and usage_event when cancel has accrued usage` locks it.

### 6.3 Finding 4.3 (failed chains leave no rows/envelope) — Verified

On terminal failure the worker calls `settleTerminal` with
`attemptsForFailedSettlement` (`src/worker.ts` lines 371–399, 943–974): real
`AttemptRecord`s when attempts ran, or one diagnostic row carrying the routing
exclusion reasons when the chain was empty. The same journal path writes the
R2 envelope (single object per request) and sets `payload_pointer`
(`src/journal/index.ts` lines 426–434). Test `writes a diagnostic attempt row
when routing yields an empty chain` passes.

### 6.4 Finding 4.4 (`prompt_artifact_hash` stores a ref) — Verified

Stage 9 now passes `promptArtifactHash: input.resolvePromptVersion?.(manifest)`
into `createRequestRow` (`src/pipeline/index.ts` lines 476–491);
`resolvePromptVersion` (`src/prompt/registry.ts` lines 115–145) is a content
hash over the resolved system instruction + fragments + template bytes, and the
worker injects the real function (`src/worker.ts` lines 1025–1061). The ref
string remains only as fallback. Test `journals promptVersion content hash into
prompt_artifact_hash, not the ref (4.4)` passes.

### 6.5 Finding 4.5 (hollow R2 envelopes) — Verified

`src/provider/raw-body.ts` captures raw provider bodies with a 16 KB cap and a
`truncated` flag; both adapters attach it on **every** outcome — success,
truncation, error, malformed, content-filtered — via `withRawBody`
(`deepseek.ts` lines 688–840, `gemini.ts` lines 779–933), including the SSE
path (joined raw payloads). `buildAttemptInput` threads `record.rawBody` into
the envelope in place of the old `{}` (`src/worker.ts` lines 350–364). Test
`stores a non-empty raw provider body per attempt in the envelope` passes.

### 6.6 Finding 4.6 (settlement period from wall-clock) — Verified

Both sides fixed. D1: `periodStart` comes from the admission-time entitlement
snapshot (`guard.entitlementSnapshot.period_bounds.period_start`,
`src/worker.ts` line 897) and `periodFromIso(periodStart)` derives the D1
period from it (lines 269–271, 428–431) — test
`usage_event_period_from_admission_entitlement` passes. DO: `creditRPC`
re-runs `maybeResetPeriod` before applying usage (`src/quota-do/index.ts`
lines 464–510), so both sides agree at period boundaries.

### 6.7 Finding 4.7 (`perRequestCostCeiling` misnomer) — Verified

The manifest field is renamed to `perRequestTokenCeiling`
(`manifests/published/clinic.visit_summary@1.0.0.json` lines 54–59;
`src/context/preflight.ts` lines 76–111); the loader keeps a documented legacy
alias for previously published manifests (`src/manifest/index.ts` lines 79–85).
Token semantics unchanged; no currency in the preflight.

### 6.8 Finding 4.8 (`promptArtifactByteLength` never passed) — Verified

Stage 7 computes `promptArtifactBytes` from
`input.promptScaffoldByteLength?.(manifest)` (`src/pipeline/index.ts` lines
407–422); the worker injects the composer's `promptScaffoldByteLength`
(`src/prompt/composer.ts` lines 51–87), which sums the UTF-8 bytes of the
system instruction, rule fragments, and template. `runCostPreflight` fails
closed on non-numeric inputs.

## 7. Chunk 5 — P3: dead fields, dead features, ignored data

### 7.1 Finding 5.1 (degraded-tier chain) — Verified

All three points wired: (a) `admissionRPC` returns `degraded: true` when
`isSoftThresholdCrossed` (`src/quota-do/index.ts` lines 302–337, 444–460);
(b) the notice is per-request — `PreAcceptResult.degradedNotice` flows from
`degradedNoticeFromAdmission` through the adapter into the SSE `accepted`
event's `degraded_notice` (`src/adapter.ts` lines 67–69, 97–111, 415–441,
514–525; `src/worker.ts` lines 1094–1100); (c) the worker feeds
`routingTierFromAdmission(...)` into `selectCandidateChain`
(`src/worker.ts` line 737). Live test
`live_soft_threshold_degraded_notice_and_routing_agree` passes.

### 7.2 Finding 5.2 (`stream` never set) — Verified

Stage 10 composes with `streamFlag: true` and `deadline`
(`src/pipeline/index.ts` lines 502–511); DeepSeek sends `stream: true` +
`stream_options.include_usage` and Gemini uses
`:streamGenerateContent?alt=sse` (see 5.5/3.5 above).

### 7.3 Finding 5.3 (stop conditions always `[]`) — Verified

Docs-only fix landed: the request-shape tables state stop conditions are always
empty under A4 (`data-journey/12-stage-10-accept-route-invoke-stream.md` lines
413, 464, 501; `11-stage-9-the-guard.md` line 286). Adapters omit
`stop`/`stopSequences` when empty (`deepseek.ts` lines 235–237; `gemini.ts`
lines 275–278).

### 7.4 Finding 5.4 (`freshnessHint`) — Verified

Zero remaining occurrences in `src/`, `manifests/`, `control/`. The manifest
loader's exact-key validation (`src/manifest/index.ts` lines 211–226, 276–309)
rejects a leftover `freshnessHint` as an extra key. No freshness enforcement
added — stale context remains accepted by design.

### 7.5 Finding 5.5 (`ConfigCache` request-scoped) — Verified

`isolateConfigCache` is a module-scope singleton per isolate
(`src/config-cache/index.ts` lines 120–126), shared by production pre-accept,
the invoke path, and `authenticateGetRequest` (default parameter,
`src/journal/index.ts` lines 544–569; `src/worker.ts` lines 717–718,
1012–1058). Tests reset it via `test/setup-isolate-config-cache.ts`.

### 7.6 Finding 5.6 (conversational `turn_ordinal` gate) — Verified

The tenant-binding half closed with 2.6. The contract (conversational legs
must carry `turn_ordinal`; omission fails `context_invalid`) is documented in
the data-journey docs (`10-stage-8-request-ingress.md`,
`11-stage-9-the-guard.md`, `15-alternative-and-failure-journeys.md`).

### 7.7 Finding 5.7 (`userIntent` not neutralized) — Verified

The final intent part is pushed as
`{ role: "user", content: neutralizeText(userIntent) }`
(`src/prompt/composer.ts` line 359) — same hygiene as context blocks.

### 7.8 Finding 5.8 (`context_requested` bypasses allowlist) — Verified

`applyPermittedKeyAllowlist` (`src/context/validator.ts` lines 250–273) now
also filters `context_requested` turns' `requests` to the permitted key set,
matching the `context_resolved` behavior; applied before rendering
(lines 385–388).

### 7.9 Finding 5.9 (schema/control-plane nits) — Verified

(a) Migration `20260821130000_entitlement_installation_unique.sql` adds
`UNIQUE` index `idx_entitlement_installation_id` (fails on existing
duplicates). (b) `handleEntitle` validates `period_start`/`period_end` as
ISO-8601 UTC instants with `start < end`, rejecting with 400 `invalid_payload`
(`src/control/entitle.ts` lines 40–99). (c) `usage_event.request_id` stays
nullable; grace credits now carry real usage (1.4). (d) Table count corrected —
the docs' count of 14 matches the schema after `grace_admission_queue`.

### 7.10 Finding 5.10 (`platform_counter` lower bound) — Verified

Docs-only fix landed: lower-bound semantics are documented at the flush site
(`src/rate-limit/index.ts` lines 148–190) and consumption sites (e.g.
`src/dashboards/index.ts` lines 157–165), and in the data-journey docs
(`02`, `11`, `15`, `16`, `20`). Flush-at-request-end is recorded as future
work, not implemented — as the audit prescribed.

## 8. Chunks 6–7 — output guards and extraction-pass findings

### 8.1 Finding 6.1 (leak-guard needle) — Verified

The needle is derived per request from the composed system instruction:
`leakNeedleFromSystemInstruction` takes a distinctive 48-char slice
(`src/prompt/composer.ts` lines 33–48, 297–298), the composer returns it
alongside `promptVersion`, the guard threads it onto `GuardFreshSuccess`
(`src/pipeline/index.ts` lines 114–124, 530–538), and the worker merges it
into the broker thresholds (`src/worker.ts` lines 849–852). The test-only
placeholder constant is gone from production. Live test `fails
validation_failed when the model leaks the composed system instruction` passes.

### 8.2 Finding 6.2 (truncation sensor) — Verified

Covered with 3.4 (§5.4 above): `wasTruncated()` implemented and truncation no
longer converts to `ok: true`; both brokers' truncation checks now fire.

### 8.3 Finding 6.3 (SafetyMarkers unreachable from prose path) — Verified

`ProseGuardThresholds` carries `refusalPrefixes` and `injectionEchoNeedle`
beside the leak needle (`src/stream/prose-guards.ts` lines 1–88); incremental
and completion guards match them (start-of-text for refusal, substring for
echo/leak) and abort as `validation_failed`. Production values are wired in
`PRODUCTION_GUARD_THRESHOLDS` (`src/worker.ts` lines 152–163). Live tests for
all three marker kinds pass (`prose_safety_markers_on_live_path`).

### 8.4 Finding 6.4 (reconciliation flooded) — Verified

Failed and cancelled requests now write their rows (4.2/4.3), and
`runReconciliation` (`src/rollup/index.ts` lines 134–187) encodes the expected
row profile per terminal state: attempts are required for `Completed`/`Failed`,
usage rows for `Completed`/`Failed`/`Cancelled` — so only genuine anomalies are
flagged.

### 8.5 Finding 6.5 (single shared operator bearer) — Verified

Docs-only: the single-operator limitation is recorded in the enrollment /
token-contract docs (`05-stage-3-platform-installation-enrollment.md`,
`03-stage-1-token-contract-baseline.md`). No `control_operator` table — as
prescribed.

### 8.6 Finding 7.1 (journaled `routing_tier` contradicts routing) — Verified

The worker's router context uses `routingTierFromAdmission(...)` from the guard
result (`src/worker.ts` line 737); live tests prove `ai_request.routing_tier`
and the selected chain agree for both producers of the degraded label
(`live_soft_threshold_degraded_notice_and_routing_agree`,
`live_grace_admission_routing_tier_matches_router`).

### 8.7 Finding 7.2 (routing-injection guard test-only) — Verified

`bodyHasClientRoutingInjection` exists only in
`test/soft-threshold-routing.test.ts`; no occurrence in `src/`.
`ADAPTER_ROUTING_BODY_FIELDS = []` (`src/adapter.ts` lines 275–279) keeps the
invariant structural, and `test/soft-threshold-hygiene.test.ts` locks that the
helper never returns to production code.

### 8.8 Finding 7.3 (repair-rate dashboard stub) — Verified

`dashboardRepairRateByCapability` (`src/dashboards/index.ts` lines 64–98) is a
real query: `ai_attempt.outcome = 'repair'` ÷ distinct `Completed`/`Failed`
requests, grouped by capability, bounded to the journal retention window.
Empty `{}` now means no in-window rows.

### 8.9 Finding 7.4 (cancel partial-usage cost) — Verified

Cancel accrual routes through the shared pricing helper: real provider-reported
tokens via `ledgerUsageFromProvider` when usage exists; otherwise the named
fallback `estimateUsageFromStreamedChars` priced by `priceUsage`
(`src/invocation/index.ts` lines 471–519; `src/pricing/index.ts` lines
137–155). No third hardcoded 0.001 formula remains.

### 8.10 Finding 7.5 (control-plane robustness) — Verified

(a) `handleRoutingPolicyPublish` wraps `DB.batch` and maps UNIQUE violations to
409 `already_published`, other D1 errors to 500 `storage_error`
(`src/control/routing-policy.ts` lines 199–224). (b) Rollback, promote, canary,
and config-cache reads all order by `active_from DESC, rowid DESC`
(`src/control/routing-policy.ts` lines 281–483; `src/config-cache/index.ts`
lines 310–334) — no lexical `version DESC` remains in `src/control/`.
(c) `assertInstallationBound` throw → 400 mapping confirmed unchanged.

### 8.11 Finding 7.6 (nullable `usage_event.request_id`) — Verified

Docs-only: aged-usage joinability loss is recorded in the retention,
settlement, column-reference, and reconciliation docs. Tests lock the NULL
after purge and that the reconciliation LEFT JOIN cannot match nulled rows.
No schema change — as prescribed.

## 9. New Findings (major/critical only)

**None.** Verification re-read the changed hot paths end to end (admission →
guard → router → invocation → adapters → broker → settlement → DO) and found
no new P0/P1-class defects introduced by the fixes. Test suite: 463/463 passing
across manifest gates, unit, and workers-pool configs.

Observations below the reporting threshold (minor, listed for completeness):

1. **Grace-cap refusal is coded `quota_exhausted`.** When the D1 grace queue is
   at cap, `admitUnderGrace` rejects with `quota_exhausted`
   (`src/admission/index.ts` lines 543–552) even though the budget is not
   exhausted — the signal conflates two distinct refusal causes.
2. **Orphaned R2 object on duplicate publish.** `handleRoutingPolicyPublish`
   writes the R2 document before the D1 batch; a 409 `already_published` leaves
   an unreferenced object at the content pointer. Harmless (same content,
   content-addressed path), but it is an unreferenced write.
3. **Leak needle covers only the prompt's opening.** The 48-char prefix detects
   verbatim leaks of the system instruction's start; a leak of only later
   portions would not trip the guard. This matches the audit's prescribed fix
   ("a distinctive fixed substring") — noted so the detection boundary is
   explicit.

## 10. Conclusion

All 48 audit findings are resolved: **47 Verified**, **1 Verified with a
sanctioned implementation variation** (1.4's cross-isolate grace cap is
enforced in D1 rather than a DO-held counter — an option the fix text
explicitly allowed). Docs-only fixes (5.3, 5.6, 5.10, 6.5, 7.6, 5.9d) were
spot-checked in the data-journey docs and are present. The audit's claimed
end state — "the ledger, the DO, and the client-visible replay semantics
agree" — holds in the current working tree, and no new major or critical
issues were found.




