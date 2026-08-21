# AI Platform Code Audit — 2026-08-21

Independent review of `ai-platform/src/` against the data-journey docs
(`docs/architecture/ai-platform/data-journey/`). This audit deliberately does
**not** restate the issues already catalogued in those docs except where this
review sharpens the root cause or finds the doc understated the blast radius.
Everything below was verified by reading the code paths end to end.

Severity legend: **P0** = breaks the happy path or bills/serves incorrectly by
default; **P1** = broken feature or security/authorization gap; **P2** =
accounting/observability divergence; **P3** = dead field, dead code, or
robustness nit.

Implementation status (2026-08-21 working tree, not committed): **Done** =
failing test, fix, AI Platform suite, and data-journey docs landed. **Partial** =
some of the audited fix landed; remaining work is listed under that issue's
**Fix** section. **Open** = not started. Counts: **48 Done**, **0 Partial**,
**0 Open**.


---



## Chunk 1 — P0: bugs that break the default request path



### 1.1 DeepSeek adapter sends canonical `role: "data"` on the wire — every real request on the default chain dies terminally — **Done**

`composeRequest` emits the rendered context as a message part with the
canonical role `"data"` (`src/prompt/composer.ts` —
`messageParts.push({ role: "data", content: contextPart })`). `"data"` is a
legal canonical role (`CANONICAL_MESSAGE_ROLES` in
`src/contracts/canonical.ts`), and the Gemini adapter translates it
(`mapRoleToGemini`: `data → user`, system parts folded into
`systemInstruction`). The DeepSeek adapter does **no** role translation:

```203:217:ai-platform/src/provider/deepseek.ts
function mapCanonicalToWire(
  request: CanonicalRequest,
  modelId: string,
): DeepSeekWireRequest {
  // ...
  const wire: DeepSeekWireRequest = {
    model: modelId,
    messages: request.parts.map((part) => ({
      role: part.role,
      content: part.content,
    })),
    stream: Boolean(request.stream),
  };
```

For `clinic.visit_summary` the context part is always present (chief complaint
is a required key), so every composed request contains a `role: "data"`
message. DeepSeek's OpenAI-compatible chat-completions API accepts only
`system/user/assistant/tool`; an unknown role returns HTTP 400.
`classifyHttpFailure(400)` → `provider_rejected`, and
`classifyFailure("provider_rejected")` is **terminal**
(`src/provider/classify.ts` — retryable "No" → terminal), so the chain does
**not** fall back to Gemini. Net effect: with real providers wired, the first
target of the default chain terminally fails every request. The fake
transports used in tests mask this because they never validate roles.

**Fix:** Add canonical→wire role translation in `mapCanonicalToWire`
(`src/provider/deepseek.ts`), mirroring the Gemini adapter: `data → user`,
`system → system`, `user`/`assistant` passthrough. Add an adapter test whose
fake transport validates roles against the OpenAI-compatible set so this
cannot regress behind role-blind fakes.

### 1.2 The checked-in manifest and routing-policy fixtures are mutually incompatible — default routing is dead on arrival — **Done**

Two independent mismatches between the only published manifest and the only
checked-in policy document:

1. **Policy identity mismatch.** The manifest pins
  `"routingPolicyRef": "routing/standard@v1"`
   (`ai-platform/manifests/published/clinic.visit_summary@1.0.0.json`), so the
   router loads D1 rows `WHERE policy_id = 'standard'`. The checked-in fixture
   `ai-platform/control/routing-policy/platform-default/1.json` declares
   `"policy_id": "platform-default"`. Because the publish endpoint performs no
   document validation (a doc-reported gap), an operator who publishes this
   fixture under the `standard` ref creates a row whose D1 `policy_id` says
   `standard` while the R2 document says `platform-default` — and
   `selectCandidateChain` then fails **every** request with
   `policy_identity_mismatch` (`src/router/index.ts`).
2. **Latency-class mismatch.** The manifest declares
  `"latencyClass": "standard"`; both targets in the fixture declare
   `"latency_class": "interactive"`. The router filter is exact equality:

```(router/index.ts)
if (features.latency_class !== requirements.latency_class) → excluded (feature_unsupported)
```

   Both targets are excluded, the chain is empty, and every request fails with
   `provider_unavailable` — even if the identity mismatch is fixed.

So the out-of-the-box deployment cannot serve a single request: the fixtures
must be edited by hand before publishing, and nothing in the publish path
warns about either mismatch.

**Fix:** (a) Make the checked-in artifacts mutually consistent: align the
fixture's `policy_id` with the ref it is published under (`standard`) and the
targets' `latency_class` with the manifest's `latencyClass` (`standard`) — or
change the manifest's `routingPolicyRef`/`latencyClass` to match the fixture.
(b) Add document validation to the routing-policy publish endpoint: reject a
document whose `policy_id`/`version` do not match the publish ref, and warn
when no target's `latency_class` matches the publishing manifest's latency
class.

### 1.3 Retry backoff is a no-op in production — zero-delay retry storms — **Done**

`runInvocation` implements documented exponential backoff with jitter through
an injected `sleeper` (`src/invocation/index.ts` — `sleepWithinDeadline`).
The worker wires it as a no-op:

```(ai-platform/src/worker.ts — runFreshEventSource)
sleeper: async () => { },
```

So in production every retryable failure (provider 429 → `rate_limited`,
5xx → `internal_error`, attempt `timeout` — all classified "retryable" by
`classifyFailure`) is retried **immediately**, up to `max_attempts` per target
across the whole chain. Against a rate-limiting provider this is a
tight-loop retry storm that ignores the provider's `Retry-After` (which the
adapter faithfully parses into `retryAfterMs` — a value nothing upstream ever
reads). The documented "exponential backoff with jitter" behavior exists only
in tests.

**Fix:** Wire a real sleeper in `src/worker.ts`
(`ms => new Promise((r) => setTimeout(r, ms))`). `sleepWithinDeadline` already
bounds the sleep against the deadline, and the invocation layer already
computes `max(jittered, retryAfterMs)` (see 3.6), so this one-line wiring
change makes both backoff and `Retry-After` effective. Keep the no-op sleeper
only in tests.

### 1.4 Grace admission is broken in four independent ways — **Done**

`src/admission/index.ts` + `src/credit/index.ts`:

1. **Isolate-local state.** `graceAdmissionsUsed` and
  `graceReconciliationQueue` are module-scope Maps. With N warm isolates the
   effective cap is `5 × N`, not `GRACE_ADMISSION_CAP = 5`. Worse, the cron
   (`reconcileGraceUsage`) runs in whichever isolate Cloudflare picks; the
   queues living in *other* isolates are never drained and are lost on
   eviction. The reconciliation mechanism is effectively inert in a
   multi-isolate deployment.
2. **No idempotency or JTI replay protection.** The grace path never consults
  the DO idempotency map or the JTI replay window. Retries of the same
   `Idempotency-Key` during a DO outage are admitted as fresh requests and
   executed repeatedly → duplicate provider spend and duplicate
   `usage_event` rows.
3. **No quota-exhaustion check.** `admitWithGrace` skips the
  `isQuotaExhausted` snapshot check, so an installation that has already
   blown its budget keeps getting served during a DO outage.
4. **Grace usage is never credited back.** `attachGraceUsage` exists in
  `src/credit/index.ts` but is **never called** from production code, and the
   worker's `creditUsage` wrapper ignores its return value. Completed
   grace-admitted requests write a D1 `usage_event` but the DO counters never
   see the usage. When `reconcileGraceUsage` later re-admits the queued entry,
   `entry.usage` is `undefined`, so it credits `{tokens: 0, cost: 0}` with
   `partial = false` — incrementing `requestsUsed`, marking the idempotency
   entry `"completed"`, and permanently diverging DO counters from D1.

**Fix:** Move all grace state into installation-scoped serialized storage. The
quota DO is the sanctioned home (§9.17 of the architecture doc forbids a new
store): (1) replace the module-scope cap Map with a DO-held counter so
`GRACE_ADMISSION_CAP` is enforced across isolates, and persist the
reconciliation queue in DO storage (or a D1 table the cron drains) instead of
isolate memory; (2) before grace-admitting, dedupe on `Idempotency-Key`
against D1 `ai_request` so transport retries during a DO outage are not
double-executed; (3) apply the quota-exhaustion check against the last known
entitlement snapshot before admitting; (4) at settlement, record actual usage
onto the queued grace entry (call `attachGraceUsage` / thread usage through
the `creditUsage` wrapper) so `reconcileGraceUsage` credits real tokens
instead of phantom zeros. All of this lives on the already-degraded grace
path — do not add DO round trips to the healthy path (§13.6: two DO calls per
request).

### 1.5 Failure and cancel paths never credit the DO — quota leaks, `inFlight` leaks, false idempotent replays — **Done**

The taxonomy table in `src/errors.ts` says `provider_rejected` and
`validation_failed` consume quota ("Yes") and `provider_unavailable`,
`timeout`, `cancelled` consume "Partially, recorded". The code never credits
any of them:

- **Invocation failure** (`src/worker.ts` ~line 740): on `!invokeResult.ok`
the worker sets `ignoreBrokerSettlement = true`, disconnects the broker,
pushes the `failed` event and records `ai_request.status = Failed`. It never
calls `creditUsage`. Consequences: DO `inFlight` leaks until the 2-hour
sweep; quota is not consumed despite the taxonomy; the idempotency entry
stays `"admitted"` (see 1.6 for why that replays as "completed").
- **Prose-guard / broker failure** (`src/stream/index.ts` — `handleFailed`):
no `safeCredit` call. Tokens the provider already generated (e.g. output
that then fails a validation guard) are never charged.
- **Cancel with no accrued usage** (`src/stream/index.ts` — `handleCancel`):
when `chunkSource.getPartialUsage()` is undefined, no credit happens at all
→ `inFlight` leak + idempotency stuck `"admitted"`.

Because `replayIdempotentTerminal` maps a stuck-`"admitted"` entry to
`{ finalContent: { text: "Prior request completed.", authoritative: true } }`,
a client that retries any of these failed/cancelled requests with the same
idempotency key is told the request **completed** — with a placeholder body.

**Fix:** Add one `settleTerminal` helper in `src/worker.ts` and call it from
every non-completed outcome: invocation failure, prose-guard/broker failure,
and cancel with or without accrued usage. It credits the DO with accrued
usage (possibly zero) and the taxonomy-correct `partial` flag per §5.4
(`provider_rejected`/`validation_failed` consume quota;
`provider_unavailable`/`timeout`/`cancelled` are partially consumed but
recorded). Critically, the credit must happen even at zero usage so
`inFlight` is released and the idempotency entry transitions to a truthful
terminal state (`failed`/`cancelled` — see 1.6) instead of staying
`"admitted"`.

### 1.6 Idempotency state machine: three states are unreachable, and the reachable ones lie — **Done**

In `src/quota-do/index.ts`:

- The DO's idempotency states `"failed"`, `"in_progress"`, and
`"awaiting_context"` are **never written** anywhere. Entries go
`"admitted"` → (`"completed"` | `"cancelled"`) via `markIdempotencyOnCredit`,
or stay `"admitted"` forever.
- `sweepAbandonedAdmissions` decrements `inFlight` for crashed requests but
leaves their idempotency entries `"admitted"` → replayed as
"Prior request completed." (authoritative) even though nothing ever ran to
completion.
- `replayIdempotentTerminal`'s `"failed"` branch (maps to `internal_error`)
is dead code, since no path ever writes `"failed"`.
- `expiresAt` is fixed at admission (+2 h) and never extended on credit. A
legitimate retry with the same key after 2 h is treated as a brand-new
request → double admission and double charging for slow client retry loops.

**Fix:** In `src/quota-do/index.ts`: (1) extend `markIdempotencyOnCredit` with
a terminal-status parameter so the settlement paths (1.5) can write
`"failed"`/`"cancelled"` — making `replayIdempotentTerminal`'s `"failed"`
branch live and truthful instead of dead; (2) have `sweepAbandonedAdmissions`
transition swept entries to `"failed"` so crashed requests replay as failures,
not as the "completed" placeholder; (3) slide `expiresAt` forward on every
state transition/credit so a retry within the entry's active life still
dedupes; (4) either wire `"in_progress"`/`"awaiting_context"` at the
appropriate pipeline points or remove them from the state type — no states
without writers.

**Leftover (accepted with Done):** an in-flight `"admitted"` entry (request
still running) still replays as the completed placeholder. Abandoned
admissions are now swept to `"failed"`.

---



## Chunk 2 — P1: authorization and security gaps



### 2.1 `requiredCapabilityScope` is never enforced — **Done**

The manifest declares `Access.requiredCapabilityScope: "ai.visit_summary"`,
and the identity layer extracts `principal.scopes` from the AAT payload. No
code anywhere compares the two — not in `src/identity/index.ts`, not in
`src/entitlement/index.ts`, not in the guard. Any holder of a valid AAT for
the installation can invoke any granted capability regardless of scopes. The
scope claim is journaled but never authorized.

**Fix:** Add a guard stage (after identity, before/inside entitlement): if the
manifest's `Access.requiredCapabilityScope` is set and absent from
`principal.scopes`, reject with `forbidden_capability` (§5.4). Pure set
membership against already-loaded data — no new I/O.

### 2.2 `allowedStaffRoles` is never enforced — **Done**

`Access.allowedStaffRoles: ["clinician", "nurse"]` is declared in the manifest
and `principal.role` is extracted from the AAT, but no guard stage checks
role membership. The field is informational only; a `receptionist` token can
run the visit-summary capability.

**Fix:** Same guard stage as 2.1: when `Access.allowedStaffRoles` is
non-empty, require `principal.role` membership, otherwise reject with
`forbidden_capability`.

### 2.3 `killSwitchFlag` in the manifest is parsed but never read — **Done**

The manifest loader accepts `Access.killSwitchFlag`, and the published
manifest sets it to `false`. No runtime code reads it — the only kill-switch
enforcement is the D1 `kill_switch` table via `isCapabilityDisabled`. The
manifest-level flag is dead.

**Fix:** Enforce it at capability resolution: a manifest with
`Access.killSwitchFlag === true` behaves as `capability_disabled` (503),
checked alongside the D1 `kill_switch` table. One comparison against the
already-loaded manifest. (Deleting the field from the schema would also be
honest, but enforcement matches the published manifest's intent.)

### 2.4 No maximum AAT lifetime is enforced by the platform — **Done**

The verifier checks `exp` against now, but never bounds `exp - iat`. The
platform therefore accepts tokens with arbitrarily long lifetimes if an issuer
ever mints one (misconfiguration or key compromise). Combined with the 2-hour
JTI replay window in the DO, a long-lived token becomes replayable after its
JTI entry expires: the same `jti` is accepted again once the replay entry
evicts. The platform should reject AATs whose lifetime exceeds the issuer's
documented ~5 minutes (defense in depth) and/or the JTI window should cover
the maximum acceptable token lifetime.

**Fix:** In the AAT verifier, reject tokens whose `exp - iat` exceeds a
platform constant (e.g. 10 minutes — §5.6 specifies "short lifetime,
minutes") with `unauthenticated`. Size the DO JTI replay window ≥ that
maximum lifetime so a token can never outlive its replay entry.

### 2.5 Key rotation never retires the old key; `valid_until` is never set — **Done**

`handleRotate` (`src/control/lifecycle.ts`) inserts a new `installation_key`
row but does not set `revoked_at` or `valid_until` on any existing key. After
"rotation", both the old and new keys verify successfully until someone
manually calls `revoke-key`. Rotation therefore does not reduce exposure from
a leaked key — it only adds a second valid credential. Relatedly,
`installation_key.valid_until` is written as `NULL` by every insert and never
set anywhere else, so keys never expire; the column is dead.

**Fix:** In `handleRotate` (`src/control/lifecycle.ts`), in the same batch as
the new-key insert, set `revoked_at` (or `valid_until = now + short grace` if
overlap during rotation is desired) on all currently active keys for the
installation. Give new keys a real `valid_until` (configured TTL) and have
the verifier reject keys past `valid_until` — making the column live.

### 2.6 Conversational context validation skips the tenant binding check — **Done**

The single-shot path of `validateContext` enforces
`suppliedContext.org === principal.organizationId` and
`suppliedContext.branch === principal.branchId`
(`src/context/validator.ts`). The conversational path
(`validateConversationalContext`) performs no org/branch check at all — it
only allowlists keys and checks shapes/sizes. A conversational capability
would accept context resolved against another tenant's data. Latent today
(only a single-shot capability is published), but the conversational
machinery is written and tested, so this will activate silently when the
first conversational capability ships.

**Fix:** In `validateConversationalContext` (`src/context/validator.ts`),
apply the single-shot path's tenant binding: the supplied context and every
`context_resolved` turn payload must match
`principal.organizationId`/`principal.branchId`; mismatch → `context_invalid`.
Note this path is live (not latent) whenever a request carries
`turn_ordinal` — see 5.6.

### 2.7 Provider kill switch = whole-capability outage, not provider failover — **Done**

Two cooperating defects:

1. At guard stage 5, `isCapabilityDisabled` treats **any** active
  `provider:<id>` kill switch for providers named in the policy as disabling
   the entire capability → 503 `capability_disabled`. Killing one provider to
   drain it takes the capability down instead of routing around it.
2. The router's own exclusion (`filterTargets` via `collectKilledProviderIds`)
  would provide graceful failover, but it reads the cache with
   `cache.consult` — a synchronous, non-loading peek. In the invoke path the
   `ConfigCache` is fresh per request and only `active_routing_policy` was
   preloaded, so no `kill_switch` entries are ever present and the exclusion
   never fires in production.

Net: the graceful "exclude the killed provider and use the fallback chain"
behavior documented for the router is dead; the actual behavior is
all-or-nothing 503 at the guard.

**Fix:** (1) Guard stage 5: only capability-level kill switches produce
`capability_disabled`; collect active `provider:<id>` switches and pass them
on as router input instead of failing the request. (2) Router: make the
killed-provider set available to `filterTargets` — preferably pass the set the
guard already loaded directly into `selectCandidateChain` (no extra D1 read);
the alternative is preloading `kill_switch` rows into the request's
`ConfigCache` alongside `active_routing_policy`. Net behavior: a killed
provider is excluded from the candidate chain and traffic fails over to the
remaining targets.

---



## Chunk 3 — P1/P2: routing and invocation layer



### 3.1 `max_parallel_attempts` is computed, journaled, and never used — **Done**

The router resolves `max_parallel_attempts` (defaults, clamp, per-rule
override) and emits it in the routing decision. `runInvocation`
(`src/invocation/index.ts`) walks the candidate chain strictly sequentially —
one target at a time, awaiting each attempt. No parallel racing exists. The
field is dead in the invocation layer; the docs describe clamp behavior for a
knob nothing consumes.

**Fix:** Prefer deletion: parallel racing multiplies token spend, which §13.6
identifies as the dominant cost by one to two orders of magnitude. Drop
`max_parallel_attempts` from the routing decision and the docs (or hardcode
it to 1 with a comment). Only if a product need is demonstrated, implement
bounded racing in `runInvocation` — first success wins, losers aborted, every
attempt journaled separately per §6.6.

### 3.2 Malformed policy targets fail open on cost class and context window — **Done**

Because publish performs no document validation, malformed target `features`
reach `filterTargets`, where the per-filter behavior is inconsistent:

- **Context window — fail open.** `features.min_context_window < required`
excludes; if the field is missing, `undefined < 32000` is `false` → target
**survives** with an undeclared window.
- **Cost class — fail open.** `COST_CLASS_ORDER[features.cost_class] > COST_CLASS_ORDER[effectiveCostClass]`; an unknown or missing cost class
indexes to `undefined`, `undefined > 1` is `false` → target **survives**
any cost ceiling. A typo like `"standrd"` silently routes traffic to a
model whose cost class was never vetted.
- **Languages — throws.** `features.languages.includes(...)` on a missing
array throws a `TypeError` out of `selectCandidateChain` → caught in the
worker as `internal_error`.
- **Latency class — fail closed** (exact `!==`).

So a single malformed R2 document can simultaneously route to undersized or
over-priced models (fail-open filters) and 500 the request (languages). The
filters should treat missing/unknown feature fields uniformly — ideally fail
closed, given publish does no validation.

**Fix:** Make every `filterTargets` feature check fail closed: a missing or
unknown `min_context_window`, `cost_class`, or `languages` excludes the
target with reason `feature_unsupported`; guard the languages check with
`Array.isArray` so malformed documents exclude rather than throw. The
publish-time validation from 1.2(b) is the defense in depth.

### 3.3 `routing_decision` is never persisted — **Done**

`ai_request.routing_decision` exists in D1 and the router produces a rich
decision object (selected rule, excluded targets with reasons, overrides
applied, max_parallel_attempts). Nothing writes it — support cannot answer
"why did this request go to model X?" from the ledger. (Doc-reported as a
column reference; confirmed here that no write path exists anywhere in
`src/`.)

**Fix:** Serialize the router's decision object (selected rule, excluded
targets with reasons, overrides applied, `max_parallel_attempts`) into
`ai_request.routing_decision` when the request row is updated at stage 10 —
one JSON write on an existing row, no new tables or write paths.

### 3.4 Truncated provider output is emitted as authoritative `completed` — **Done**

When DeepSeek returns `finish_reason: "length"` (or a stream without
`[DONE]`/finish reason), the adapter returns `kind: "truncation"`.
`processInvokeResult` records the attempt as outcome `"truncation"` but
`runInvocation` returns `ok: true` — a success. The stream broker's last line
of defense would be `chunkSource.wasTruncated()`, but
`createChunkSourceFromInvocationEvents` never implements it. Result: a
truncated visit summary is streamed to the client, passes the prose guards,
and terminates as `completed` with `authoritative: true`, and the
`usage_event`/`ai_attempt` rows record it as a normal success. The docs'
"truncation is surfaced" behavior does not exist.

**Fix:** Two coordinated changes: (1) `runInvocation` must not return
`ok: true` when the terminal attempt outcome is `truncation` — surface it as
`validation_failed`, since truncated prose must never complete as
authoritative (the broker's own comment says so); (2) implement
`wasTruncated()` on `createChunkSourceFromInvocationEvents` (`src/worker.ts`),
tracking truncation events seen in the invocation event stream, so the
existing broker checks in `src/stream/index.ts` and `src/validate/phases.ts`
actually fire (6.2).

### 3.5 Streaming is batch end-to-end — **Done**

Three stacked buffering points: (1) the DeepSeek/Gemini transports return the
**full** response body as a string — `handleStreamResponse` parses complete
SSE text after the body has fully arrived; (2) `runInvocation` resolves the
whole invoke promise before `relayTextDeltas` runs; (3) only then do chunks
flow to the broker. Even if `stream: true` were sent on the wire (it is not —
see 5.2), the client would see no token until the provider call finished. The
"live relay" described in the stream stage docs is not live.

**Fix:** Staged: (1) send `stream: true` on the wire (5.2); (2) make the
DeepSeek/Gemini transports parse SSE incrementally — a `ReadableStream`
reader over `response.body` feeding the existing SSE parser per event —
instead of awaiting the full body text; (3) emit deltas through the existing
invocation-event channel as they arrive so `relayTextDeltas` runs
concurrently with the provider call. If this is deferred, correct the
stream-stage docs to say batch.

**Done:** All three stages. Guard compose passes `streamFlag: true` (5.2).
DeepSeek/Gemini parse SSE incrementally from a `ReadableStream` reader
(`src/provider/readable-body.ts`); production `createFetchTransport` does not
buffer via `.text()`. Invocation passes `onStreamChunk` into `port.invoke` so
text deltas hit `InvocationSink.emitStreamText` before invoke resolves.

### 3.6 `retryAfterMs` is consumed but nullified by the no-op sleeper — **Done**

*Corrected after subagent extraction.* The invocation layer **does** read the
provider's `Retry-After` hint: `delay = Math.max(jittered, retryAfterMs)`
(`src/invocation/index.ts` ~645–657). But the computed delay is passed to
`sleepWithinDeadline(sleeper, delay, …)` where `sleeper` is the worker's no-op
(1.3) — so the hint is honored on paper and never in wall-clock. Separately,
the SSE `failed` event for guard-stage `rate_limited` carries the hardcoded
`DEFAULT_RETRY_AFTER_SECONDS = 60`, unrelated to any provider hint.

**Fix:** Fixed by 1.3's real sleeper — the invocation layer already computes
`max(jittered, retryAfterMs)`. Independently, for guard-stage `rate_limited`
SSE `failed` events, prefer the admission result's retry hint over the
hardcoded default when one is available.

**Done:** Production `wallClockSleeper` in `src/worker.ts` (issue 1.3), so
invocation `max(jittered, retryAfterMs)` is wall-clock. Guard-stage
`rate_limited` (pre-SSE HTTP JSON, same error-body shape as SSE `failed`)
prefers the Rate Limit binding's `retryAfter` hint when `limit()` supplies a
positive number, else the 60s simple-limiter window.
`retryAfterSecondsForRateLimited` in `src/errors.ts` is the single default.
The hint is threaded `checkRateLimit` → `GuardFailure.retryAfter` →
`PreAcceptResult` → `preAcceptFailureResponse` via
`supplementaryFieldsForCode`.

---



## Chunk 4 — P2: settlement, journaling, and accounting divergences



### 4.1 Cost accounting is hardcoded twice, inconsistently — **Done**

- `usageFieldsFromResult` (`src/invocation/index.ts`) hardcodes `cost: 0` on
every `AttemptRecord` → every `ai_attempt.cost` is 0.
- `settleCompletedRequest` (`src/worker.ts`) hardcodes cost `0.001` into the
`usage_event` row regardless of provider, model, or token counts.

So `ai_attempt` and `usage_event` permanently disagree, and neither reflects
real provider pricing. Any rollup joining the two (or summing either) is
fiction. There is no price table anywhere in the codebase — `cost_budget` in
the entitlement is enforced by the DO against these synthetic numbers.

**Fix:** Add a small price table (per model: input/output price per 1K
tokens) as platform config — a versioned artifact loaded alongside the
routing policy, never client-visible. Compute cost from provider-reported
token counts in one shared pricing helper, and use it in both
`usageFieldsFromResult` (`ai_attempt`) and `settleCompletedRequest`
(`usage_event`) so the two rows agree. Per §13.6.2, money appears only in the
post-response ledger, priced from actual provider-reported tokens — keep it
that way; no currency enters the preflight.

### 4.2 Cancelled requests leave no billing rows — **Done**

A cancelled request with accrued usage is credited to the DO
(`partial: true`), but the journal writes **no** `ai_attempt` rows and **no**
`usage_event` row for cancellations (`src/journal/index.ts` only writes those
from `settleCompletedRequest`). The DO counters and the D1 ledger diverge by
exactly the cancelled-with-usage traffic, and `usage_rollup` built from
`usage_event` undercounts. The taxonomy says cancelled consumes "Partially,
recorded" — it is partially consumed but never recorded.

**Fix:** In the cancel settlement path (the `settleTerminal` helper from
1.5), write the `ai_attempt` row(s) and a `usage_event` row for cancellations
with accrued usage, marked with terminal state `cancelled` — reusing the same
journal writers as `settleCompletedRequest`. This also un-floods
reconciliation (6.4).

### 4.3 Failed chains leave no attempt rows and no R2 envelope — **Done**

On invocation failure the worker records only `ai_request.status = Failed`
with the terminal taxonomy code. The per-attempt records (provider, model,
native error code/message, timing, retryable outcomes) collected in
`attemptRecords` are discarded — `ai_attempt` gets rows only via
`settleCompletedRequest`, which runs only on `completed`. The R2 diagnostic
envelope is likewise written only on completion. A failed request — the case
support most needs to diagnose — has the least evidence: no attempt detail,
no envelope, no provider-native error.

**Fix:** On terminal failure, persist the collected `attemptRecords` to
`ai_attempt` and write the R2 diagnostic envelope (failure variant, same
single-object layout per §7.4.1) before marking the request failed. Reuse the
existing writers from `settleCompletedRequest` with a failure status — no new
tables or write paths.

### 4.4 `prompt_artifact_hash` stores a reference string, not a hash — **Done**

`createRequestRow` (`src/journal/index.ts`) fills the
`ai_request.prompt_artifact_hash` column with
`manifest["Prompt binding"].systemInstructionArtifactRef` — e.g.
`"clinic.visit_summary/system@v1"`. The column name promises a content hash
(which would detect silent artifact changes under a pinned ref); what is
stored is just the ref, which is already implied by capability + version.
Meanwhile the composer computes a real `promptVersion`
(`resolvePromptVersion`) that is logged and then dropped — never journaled.

**Fix:** Journal the composer's computed `promptVersion` (content hash of the
resolved artifact bytes) into `ai_request.prompt_artifact_hash` instead of
the ref string. The ref is already implied by capability + version and can
stay in the R2 envelope.

### 4.5 R2 envelopes are hollow: `rawBody` is always `{}` — **Done**

`buildAttemptInput` (`src/worker.ts`) sets `rawBody: {}` unconditionally, and
`buildEnvelope` (`src/journal/index.ts`) copies `attempt.rawBody` into the
envelope's per-attempt entries. The documented "raw provider bodies per
attempt" diagnostic payload is always empty. Combined with 4.3, R2 diagnostics
contain no provider-level evidence in any outcome.

**Fix:** Capture the raw provider response body per attempt in the
adapter/transport layer, size-capped (e.g. 16 KB, truncated with a flag), and
thread it through `AttemptRecord.rawBody` in place of the hardcoded `{}` in
`buildAttemptInput`. Keep the one-envelope-per-request rule (§7.4.1).

### 4.6 Settlement period is recomputed from wall-clock at credit time — **Done**

`periodFromIso(new Date().toISOString())` runs at settlement, not from the
entitlement's `period_start`/`period_end` bounds loaded at admission. A
request admitted at 23:59:59 and credited at 00:00:01 lands in the next
period in D1 while the DO applied it to the admission-time period — one more
D1/DO divergence vector around period boundaries. (The DO has its own
period-rollover race in the other direction: `creditRPC` does not re-run
`maybeResetPeriod`, so usage admitted before rollover is credited into
whatever period is current at credit time.)

**Fix:** Thread the admission-time entitlement snapshot
(`period_start`/`period_end`) through to settlement and derive the D1 period
from it instead of `new Date()` at credit time; in the DO, re-run
`maybeResetPeriod` inside `creditRPC` before applying usage. Both sides then
agree at period boundaries.

### 4.7 `perRequestCostCeiling` is a token ceiling wearing a cost name — **Done**

The preflight check is `estimatedInputTokens + maxOutputTokens > perRequestCostCeiling` (`src/context/preflight.ts`) — token units on both
sides. The published manifest sets it to 9024 = 8000 + 1024, making the check
exactly redundant with `estimatedInputTokens > maxInputTokens`. The field
name (and its neighborhood, `cost_budget` in dollars) implies currency; the
semantics are tokens. Either the check or the name is wrong.

**Fix:** The semantics are correct — §13.6.2 specifies tokens throughout and
exactly this comparison (`estimatedInputTokens + maxOutputTokens ≤ perRequestCostCeiling`). Fix the name, not the check: rename the manifest
field to `perRequestTokenCeiling` (with a schema-version note) or, minimally,
document the token units in the manifest schema and docs. Do not introduce
currency into the preflight.

### 4.8 Stage-7 preflight never receives `promptArtifactByteLength` — **Done**

`estimateInputTokens` supports a `promptArtifactByteLength` parameter precisely
so the system instruction, rule fragments, and template bytes count toward
the input estimate. The worker's call site never passes it (defaults to 0),
so the preflight estimate excludes the entire composed prompt scaffold and
can under-estimate real provider input by kilobytes per request. The
`request_too_large` boundary is therefore miscalibrated in the permissive
direction.

**Fix:** Pass `promptArtifactByteLength` at the worker's stage-7 call site —
the byte length of the composed prompt scaffold (system instruction + rule
fragments + template), which the composer already knows. §13.6.2 requires
prompt artifacts bound to the capability to count at their known byte
length.

---



## Chunk 5 — P3: dead fields, dead features, and ignored data



### 5.1 The degraded-tier feature is dead at three independent points — **Done**

The docs note `degraded_notice` is "not emitted"; the full chain is dead:

1. The quota DO's `allowRPC` never returns `degraded: true` — the soft
  threshold (`soft_threshold` on the entitlement, coerce/validate machinery
   in `src/quota-do`) is loaded and stored but never consulted when admitting.
2. `degradedNoticeFromAdmission` (`src/soft-threshold/index.ts`) is never
  called from any file.
3. The adapter's `degradedNotice` is a **static** `handleAdapterRequest`
  option (`src/adapter.ts`), and the worker's call site never passes it —
   so even a manually-constructed degraded admission could not reach the SSE
   `accepted` event. The option is structurally incapable of carrying
   per-request state.

`routingTierFromAdmission` is the only live consumer and always yields
`"standard"`, so the economy cost-class path in the router is unreachable too.

**Fix:** Wire the chain end-to-end (or delete it): (a) the DO's `allowRPC`
returns `degraded: true` when usage crosses the entitlement's
`soft_threshold`; (b) replace the static `degradedNotice` adapter option with
a per-request value the worker passes from the admission result, so the
`accepted` event can carry `degraded_notice`; (c) feed
`routingTierFromAdmission(...)` into the worker's router context in place of
the hardcoded `"standard"` (also fixes 7.1). Constitution V: soft thresholds
downgrade rather than refuse.

**Done:** (a) Quota DO `admissionRPC` returns `degraded: true` when
`isSoftThresholdCrossed`; (b) adapter `degradedNotice` is per-request from
preAccept (`degradedNoticeFromAdmission`), not a static `handleAdapterRequest`
option; (c) `runFreshEventSource` passes `routingTierFromAdmission(...)` into
`selectCandidateChain`. Soft-threshold and grace admission both emit
`degraded_notice` on `accepted` and select `match.tiers` degraded rules.

### 5.2 `stream` is never set on the canonical request — **Done**

`composeRequest` accepts `streamFlag` and defaults it to `false`; the
pipeline's call site passes no `streamFlag` (and no `deadline`). Every
provider call therefore goes out with `stream: false` / absent, and the
DeepSeek `stream_options.include_usage` branch is unreachable. The entire
streaming code path in the adapters is exercised only by tests.

**Fix:** Pass `streamFlag: true` (and the request deadline) from the
pipeline's `composeRequest` call site for streaming capabilities. Pair with
3.5 so the flag actually produces live deltas.

**Done:** `runGuard` stage 10 calls `composeRequest` with `streamFlag: true`
and `deadline: input.deadline ?? null`. Visit summary therefore goes out with
`stream: true` / DeepSeek `stream_options.include_usage` and Gemini
`:streamGenerateContent?alt=sse`.

### 5.3 `stopConditionsFromManifest` always returns `[]` — **Done**

By its own comment, A4 declares no stop-sequences field, so
`CanonicalRequest.stopConditions` is always empty and the DeepSeek
`wire.stop` branch is dead. Fine as a contract decision — but the docs'
request-shape tables imply stop conditions flow; they never do.

**Fix:** Docs-only: state in the request-shape tables that stop conditions
are always empty under A4. Optionally delete the dead `wire.stop` branch.

**Done:** Request-shape tables (CanonicalRequest + DeepSeek/Gemini wire maps)
state stop conditions are always empty under A4; adapters omit `stop` /
`stopSequences` when empty (the wire branch is kept for the canonical field,
which A4 never populates). Tests lock `stopConditionsFromManifest` → `[]`
and empty wire omission.

### 5.4 `freshnessHint` on context requirements is never read — **Done**

`"freshnessHint": "session"` is declared per context key in the manifest,
validated as a shape, and then ignored by the validator, the composer, and
the renderer. No freshness enforcement or client hint exists.

**Fix:** Prefer removal: the architecture accepts stale context by design
(the §6.7.3 reasoning — containment is elsewhere). Drop `freshnessHint` from
the manifest schema, or document it as informational-only. Enforcement would
add complexity the design deliberately avoided.

**Done:** Dropped `freshnessHint` from the Context-requirements schema
(`MANIFEST_FIELD_MANIFEST`), the published `clinic.visit_summary@1.0.0`
manifest (and its registry hash), loader exact-key validation, and fixtures.
The loader rejects leftover `freshnessHint` as an extra key. No freshness
enforcement was added; stale context remains accepted by design.

### 5.5 `ConfigCache` is request-scoped in production — the 30 s TTL never helps — **Done**

`createProductionPreAccept` (for `POST /v1/requests`) and
`authenticateGetRequest` (for `GET /v1/requests/{ref}`) each construct
`new ConfigCache()` per request. Entries never survive across requests, so
every request re-reads installation, keys, entitlement, grants, kill
switches, and policy rows from D1. The documented 30-second TTL only
dedupes reads *within* one request's guard pipeline. This also defeats the
kill-switch consult in the router (2.7) and multiplies D1 read load exactly
where the cache was meant to help.

**Fix:** Hoist the `ConfigCache` to module scope (one instance per isolate),
shared by `createProductionPreAccept` and `authenticateGetRequest`, keeping
constructor injection for tests. The 30 s TTL then dedupes across requests
within an isolate, and the router's kill-switch `consult` (2.7) can hit warm
entries.

**Done:** `isolateConfigCache` is one `ConfigCache` per Worker isolate
(isolate-local memory, not a store). Production POST pre-accept, GET request
auth, invoke-path routing, and discovery share it; tests still inject
`new ConfigCache()`. The 30 s TTL now dedupes D1 across requests in a warm
isolate, and `collectKilledProviderIds` can `consult` kill-switch rows the
guard already loaded. Workers tests reset the isolate cache between cases
(and after in-test D1 mutations) so they still see immediate config changes.

### 5.6 Conversational mode is wired but gated on `turn_ordinal` — and tenant-unbound — **Done**

*Corrected after subagent extraction.* The pipeline does pass conversational
options, but only when the wire body carries `turn_ordinal`:

```350:354:ai-platform/src/pipeline/index.ts
  // Stage 6 — context validate (H2 conversational options when interactionMode is conversational)
  const conversationalOptions =
    manifest.interactionMode === "conversational" && turnOrdinal !== undefined
      ? { transcript, legTurnOrdinal: turnOrdinal }
      : undefined;
```

So a conversational request that omits `turn_ordinal` fails with
`context_invalid` (options undefined), while one that includes it is fully
processed — including the missing org/branch tenant binding (2.6), which is
therefore a **live** gap for any conversational capability, not a latent one.

**Fix:** The tenant-binding fix (2.6) closes the live gap. Additionally,
document the contract: conversational legs must carry `turn_ordinal` —
omission failing with `context_invalid` is acceptable behavior, but it should
be stated in the API docs rather than discovered.

### 5.7 Composer neutralizes context but not the user intent — **Done**

`neutralizeJson`/`neutralizeText` escape `</` inside context blocks and
transcript turns, but the final `userIntent` part is pushed raw. Low risk
(staff-authored text), but inconsistent with the delimiter-injection hygiene
applied everywhere else.

**Fix:** Run the final `userIntent` part through the same
`neutralizeText`/`neutralizeJson` escaping used for context blocks before
pushing it.

### 5.8 Transcript `context_requested` turns bypass the permitted-key allowlist — **Done**

`applyPermittedKeyAllowlist` filters `context_resolved` turns only. Historical
`context_requested` turns requesting keys outside `permittedKeySet` are
rendered verbatim into the prompt by `renderTranscriptPriorTurns`, while the
output-format instruction tells the model to use "keys from the permitted
set". Minor prompt-hygiene inconsistency.

**Fix:** Extend `applyPermittedKeyAllowlist` (or `renderTranscriptPriorTurns`)
to drop out-of-set keys from historical `context_requested` turns before
rendering, matching the `context_resolved` behavior.

### 5.9 Schema and control-plane nits — **Done**

- `entitlement` **has no** `UNIQUE(installation_id)`**.** Enroll's pre-check makes
duplicates unlikely via the control plane, but `handleEntitle` reads with
`.first()` and updates with `WHERE installation_id = ?` — a duplicate row
set would be silently multi-updated. The constraint should exist.
- `handleEntitle` **does not validate** `period_start`**/**`period_end` beyond
non-empty strings — no ISO parsing, no ordering check. Garbage periods flow
straight into the DO's period math.
- `usage_event.request_id` was migrated from `NOT NULL` to nullable; the
credit path can now write usage rows with no request linkage, weakening the
ledger's joinability (grace-reconciliation credits are the intended user,
but see 1.4 — those credits are phantom zero-usage rows).
- **Doc inaccuracy:** doc 02 states the D1 schema has 14 tables; the
migrations define 13.

**Fix:** (a) New migration adding `UNIQUE(installation_id)` on `entitlement`
(check for duplicates first). (b) Validate `period_start`/`period_end` in
`handleEntitle` — ISO parse plus start < end, reject garbage with 400.
(c) Keep `usage_event.request_id` nullable (retention needs it, 7.6); the
real fix is 1.4's truthful grace credits. (d) Correct doc 02 to 13 tables.

**Done:** (a) Migration `20260821130000_entitlement_installation_unique.sql`
adds `UNIQUE` index `idx_entitlement_installation_id` on
`entitlement(installation_id)`; apply fails if duplicates already exist.
(b) `handleEntitle` parses `period_start`/`period_end` as ISO-8601 UTC
instants and rejects garbage or `start >= end` with 400 `invalid_payload`.
(c) `usage_event.request_id` stays nullable; 1.4 now writes real grace usage
instead of phantom zeros. (d) D1 table count in doc 02 / intro docs is 14,
matching the schema after `grace_admission_queue`.

### 5.10 `platform_counter` undercounts rejections (confirmed) — **Done**

The rejection tally is isolate-local and flushed only by the isolate that
happens to run the cron. Tallies in other isolates are lost on eviction. The
docs describe the mechanism; confirming here that there is no cross-isolate
drain, so `platform_counter` is a lower bound, not a count.

**Fix:** Cheapest correct option: document the lower-bound semantics wherever
the counter is consumed. If an accurate count is ever needed, flush tallies
to D1 batched with the existing journal write at request end rather than only
from the cron isolate.

**Done:** Lower-bound semantics documented at every consumption site
(`platform_counter` column ref, cron flush, guard stage 4, dashboards,
rate-limit JSDoc). Flush-at-request-end is recorded as future work only —
not implemented. Test locks that D1 is empty until this isolate's flush.

---



## Chunk 6 — P1/P2: output guards that cannot fire



### 6.1 The system-prompt-leak guard uses a test needle in production — **Done**

`PRODUCTION_GUARD_THRESHOLDS` (`src/worker.ts`):

```140:144:ai-platform/src/worker.ts
const PRODUCTION_GUARD_THRESHOLDS: ProseGuardThresholds = {
  maxLength: 128_000,
  stopSequences: ["<|end|>"],
  systemPromptLeakNeedle: "SYSTEM_PROMPT_LEAK_TEST_NEEDLE",
};
```

`runFullGuardSet` / `checkIncrementalGuards` (`src/stream/prose-guards.ts`)
check `text.includes(systemPromptLeakNeedle)` — a literal placeholder string
that appears only in tests. Real leaked system instructions will never
contain it, so the leak guard is inert in production. The needle should be
derived from the composed system instruction (e.g. a distinctive substring
per prompt version), not a constant.

**Fix:** Derive the needle per request from the composed system instruction —
a distinctive fixed substring or hash prefix of the composed prompt, computed
by the composer and passed into the guard thresholds — so a real leak of the
actual system prompt is detected.

### 6.2 The truncation guard is wired but its sensor is missing — **Done**

The prose broker does the right thing:

```413:417:ai-platform/src/stream/index.ts
      // Truncated prose must not complete as authoritative (§4.3.9 / §3.2.2).
      if (chunkSource.wasTruncated?.() === true) {
        handleFailed("validation_failed");
        return;
      }
```

…but the only production `ChunkSource`,
`createChunkSourceFromInvocationEvents` (`src/worker.ts`), never implements
`wasTruncated`, so the optional call is always `undefined` and the guard
never fires. The adapters faithfully report `kind: "truncation"`; the
invocation layer converts it to `ok: true`; the broker's last line of
defense has no sensor. (This is the mechanism behind 3.4.) Note also that
the structured broker's safety phase *does* check `output.truncated`
(`src/validate/phases.ts` — `checkSafety`), fed by the same missing
`wasTruncated` — so both brokers are blind.

**Fix:** See 3.4 — one coordinated change: implement `wasTruncated()` on
`createChunkSourceFromInvocationEvents` and stop converting truncation to
`ok: true` in `runInvocation`.

### 6.3 The richer safety markers are unreachable from the prose path — **Done**

`SafetyMarkers` (leaked-instruction needle, refusal prefixes, injection-echo
needle) exist only on the **structured** broker
(`src/stream/structured.ts`). The worker wires only the prose broker
(`createStreamBroker`), and passes no marker configuration beyond the static
thresholds above. There is no refusal detection and no injection-echo
detection on the only live output path. A model that answers every visit
summary with "I'm sorry, I can't help with that" streams cleanly to
`completed`.

**Fix:** Port the structured broker's `SafetyMarkers` (refusal prefixes,
injection-echo needle, leak needle) into the prose guard set
(`src/stream/prose-guards.ts`) as configurable thresholds, and wire
production values in `src/worker.ts`. Matches route through the existing
guard-failure path as `validation_failed`.

**Done:** `ProseGuardThresholds` now carries `refusalPrefixes` and
`injectionEchoNeedle` alongside the existing leak needle. Incremental and
completion prose guards match them (start-of-text for refusal, substring for
echo and leak) and abort as `validation_failed`. Production values are wired
in `src/worker.ts`. Live `POST /v1/requests` tests cover all three marker
kinds.

### 6.4 Reconciliation signal is permanently flooded by design — **Done**

`runReconciliation` (`src/rollup/index.ts`) flags every terminal request
missing `ai_attempt` or `usage_event` rows. Because failed chains never
write attempt rows (4.3) and cancelled requests never write usage rows
(4.2), **every** Failed and Cancelled request is flagged, forever. The
report cannot distinguish "known uncredited paths" from genuine anomalies,
so the cron's reconciliation output is noise exactly where it should be a
signal.

**Fix:** Lands with 4.2/4.3 (failed and cancelled requests get their rows).
Independently, teach `runReconciliation` the expected row profile per
terminal state so it flags only genuine anomalies (e.g. a `completed`
request missing rows).

### 6.5 Operator auth is a single shared bearer with a single identity — **Done**

`createSecretOperatorAuth` (`src/control/auth.ts`) verifies one configured
bearer token (timing-safe — good) and attributes every control-plane action
to one configured `operatorId`. The `control_audit` trail therefore cannot
distinguish operators, and the token cannot be rotated per-operator or
revoked individually. Acceptable for a single-operator deployment; worth
knowing before the control plane is exposed to a wider ops team.

**Fix:** Document the single-operator limitation now; no code change required
today. If multi-operator access is ever needed, add a `control_operator`
table (per-operator token hashes + ids) so `control_audit` attributes actions
correctly and revocation is per-operator.

**Done:** Single-operator limitation documented (enroll auth, Stage 0
`OPERATOR_ID` / bearer, `control_audit.operator_id`, control-plane journeys).
No `control_operator` table. Test locks every successful auth to the one
configured `operatorId`.

---



## Chunk 7 — additions from the mechanical extraction pass

Facts extracted by the subagent pass across 50+ files, cross-checked by me
before inclusion.

### 7.1 Journaled `routing_tier` can contradict the actual routing — **Done**

The pipeline journals `routing_tier: "degraded"` for grace-admitted requests
(`src/pipeline/index.ts` 423–426), but the worker's router context hardcodes
`routingTier: "standard"` (`src/worker.ts` ~574) when calling
`selectCandidateChain`. So `ai_request.routing_tier` can say "degraded" for a
request that was routed through the standard cost class — the ledger
mislabels the routing decision it claims to record. (Sharpens 5.1: the only
live producer of the "degraded" label is grace admission, and it never
reaches the router.)

**Fix:** Use `routingTierFromAdmission(...)` in the worker's router context
instead of the hardcoded `"standard"` (part of 5.1c), so the journaled tier
and the actual routing agree.

**Done:** Worker router context uses `routingTierFromAdmission` from the
guard result (soft threshold `degraded: true` or grace). Live tests prove
`ai_request.routing_tier` and the selected chain (`ai_attempt.model`) agree
for both producers of the degraded label.

### 7.2 The client routing-injection guard is test-only — **Done**

`bodyHasClientRoutingInjection` (`src/soft-threshold/index.ts`) exists to
prove that `routing_tier` / `degraded` / `degraded_notice` body keys are
ignored at ingress — but it is called only from
`test/soft-threshold-routing.test.ts`. The adapter's
`ADAPTER_ROUTING_BODY_FIELDS = []` means ingress genuinely ignores those keys
(the invariant holds), but the guard function itself is dead production code.

**Fix:** Move `bodyHasClientRoutingInjection` into the test file that uses it
(or delete it). The invariant itself is enforced structurally by
`ADAPTER_ROUTING_BODY_FIELDS = []`.

**Done:** `bodyHasClientRoutingInjection` lives only in
`test/soft-threshold-routing.test.ts`. Production `src/` does not define or
export it. Ingress still ignores `routing_tier` / `degraded` /
`degraded_notice` because `ADAPTER_ROUTING_BODY_FIELDS = []`.

### 7.3 `dashboardRepairRateByCapability` is an empty stub — **Done**

`src/dashboards/index.ts` — the repair-rate dashboard returns `{}` with no
SQL. The other five dashboard queries are real. Any consumer of the repair
rate gets a silently empty object.

**Fix:** Implement the query following the same pattern as the other five
dashboard queries (repair attempts ÷ completed requests, grouped by
capability over the window), or remove the endpoint from the dashboard
surface until implemented.

**Done:** `dashboardRepairRateByCapability` is a real journal query:
`ai_attempt.outcome = 'repair'` attempts ÷ `ai_request` rows in
`Completed`/`Failed`, grouped by `capability_id`, bounded to the journal
retention window. Cancelled requests are excluded. Empty `{}` now means
no in-window Completed/Failed rows, not a stub.

### 7.4 Partial-usage cost on cancel is a char-count estimate or zero — **Done**

`runInvocation` accrues partial usage for cancel credits with
`accruedCost += 0` when provider usage exists, and falls back to
`{ tokens: streamedChars, cost: streamedChars * 0.001 }` when it does not
(`src/invocation/index.ts` ~445–470). So cancelled-request credits mix real
token counts with a characters-as-tokens estimate and a hardcoded 0.001
cost-per-char — a third synthetic cost formula alongside 4.1's two.

**Fix:** Route cancel-cost through 4.1's shared pricing helper: real
provider-reported tokens × price when usage exists; when it does not, keep a
char-based fallback but as one clearly-named estimate function — no third
hardcoded 0.001.

### 7.5 Control-plane robustness nits (verified) — **Done**

- **Duplicate policy publish is an unhandled 500.** `handleRoutingPolicyPublish`
runs `await DB.batch(...)` with no try/catch; re-publishing the same
`(policy_id, version)` violates the primary key and throws out of the
handler (other control handlers wrap batches and map constraint errors to
409 — publish does not).
- **Rollback/promote version ordering is lexical.** `ORDER BY active_from DESC, version DESC` over a TEXT `version` column sorts `"10"` before
`"9"`; with same-second `active_from` timestamps, rollback can resurrect
the wrong prior version.
- `assertInstallationBound`**'s throw is handled.** The `GatewayObject` RPC
dispatcher in `worker.ts` maps `installation_id_mismatch` to a 400
`bad_request` — the throw inside `blockConcurrencyWhile` is safe. (Resolves
a minor open question from the first pass.)

**Fix:** (a) Wrap `handleRoutingPolicyPublish`'s `DB.batch` in try/catch and
map constraint violations to 409 like the other control handlers. (b) Order
rollback/promote by `active_from DESC, rowid DESC` (or a numeric version
cast) so same-second ties pick the true latest version. (c) No action —
verified safe.

**Done:** (a) `handleRoutingPolicyPublish` wraps `DB.batch` and maps
UNIQUE/SQLITE_CONSTRAINT to 409 `already_published` (other D1 errors 500
`storage_error`). (b) Rollback, promote, canary, and config-cache serving
reads order `routing_policy` by `active_from DESC, rowid DESC` so
same-second ties pick the later-inserted row, not lexical TEXT `"9"` over
`"10"`. (c) No change — `assertInstallationBound`'s throw remains mapped to
400 `bad_request` by the `GatewayObject` RPC dispatcher.

### 7.6 Why `usage_event.request_id` is nullable — and what it costs — **Done**

The retention purge (`src/retention/index.ts`) runs
`UPDATE usage_event SET request_id = NULL` before deleting aged `ai_request`
rows — that is the entire reason for the nullable migration. The ledger keeps
the money rows while the journal is purged (by design), but it permanently
severs request-level joinability for aged usage, and `runReconciliation`'s
`LEFT JOIN usage_event u ON u.request_id = r.request_id` can never match
those rows. Fine as a retention decision; worth documenting as the reason
reconciliation coverage shrinks with age.

**Fix:** Docs-only: record in the retention/reconciliation docs that aged
usage rows lose request joinability by design, so reconciliation coverage
shrinks with age. No code change.

**Done:** Retention, settlement, D1 column ref, lookup, and reconciliation
docs record that aged usage loses `request_id` joinability by design.
Tests lock the NULL after purge and that `runReconciliation`'s LEFT JOIN
cannot match nulled rows. No schema change.

---



## Summary — what to fix first


| # | Finding | Severity | Effort | Status |
| --- | --- | --- | --- | --- |
| 1.1 | DeepSeek wire sends `role: "data"` → terminal `provider_rejected` on the default chain's first target | **P0** | Small | **Done** |
| 1.2 | Checked-in manifest vs policy fixture: `policy_id` + `latency_class` mismatches → default route dead | **P0** | Small | **Done** |
| 1.3 | No-op `sleeper` → zero-backoff retry storms; provider `Retry-After` ignored | **P0** | Trivial | **Done** |
| 1.4 | Grace admission: isolate-local state, no idempotency/JTI, no quota check, phantom reconciliation credits | **P0** | Large | **Done** |
| 1.5 | Failure/cancel paths never credit the DO → quota + `inFlight` leaks, false "completed" replays | **P0** | Medium | **Done** |
| 1.6 | Idempotency states unreachable; abandoned admissions replay as completed | **P0** | Medium | **Done** |
| 2.1 | `requiredCapabilityScope` never enforced | **P1** | Small | **Done** |
| 2.2 | `allowedStaffRoles` never enforced | **P1** | Small | **Done** |
| 2.3 | Manifest `killSwitchFlag` parsed but never read | **P1** | Small | **Done** |
| 2.4 | No maximum AAT lifetime | **P1** | Small | **Done** |
| 2.5 | Rotation never revokes old keys; `valid_until` never set | **P1** | Small | **Done** |
| 2.6 | Conversational context skips tenant binding | **P1** | Small | **Done** |
| 2.7 | Provider kill switch 503s the whole capability; router exclusion dead | **P1** | Medium | **Done** |
| 3.1 | `max_parallel_attempts` unused | **P2/P3** | Small | **Done** |
| 3.2 | Malformed policy targets fail open on cost class and context window | **P2** | Small | **Done** |
| 3.3 | `routing_decision` never persisted | **P2** | Small | **Done** |
| 3.4 | Truncated output completes as authoritative | **P1** | Small | **Done** |
| 3.5 | Streaming is batch end-to-end | **P1** | Medium | **Done** |
| 3.6 | `retryAfterMs` nullified by no-op sleeper; guard SSE retry_after hardcoded | **P2** | Small | **Done** |
| 4.1 | Cost hardcoded as 0 (`ai_attempt`) and 0.001 (`usage_event`) | **P2** | Medium | **Done** |
| 4.2 | Cancelled requests leave no billing rows | **P2** | Medium | **Done** |
| 4.3 | Failed chains leave no attempt rows and no R2 envelope | **P2** | Medium | **Done** |
| 4.4 | `prompt_artifact_hash` stores a ref, not a hash | **P2** | Small | **Done** |
| 4.5 | R2 envelopes hollow: `rawBody` always `{}` | **P2** | Medium | **Done** |
| 4.6 | Settlement period recomputed from wall-clock at credit time | **P2** | Small | **Done** |
| 4.7 | `perRequestCostCeiling` is a token ceiling wearing a cost name | **P3** | Small | **Done** |
| 4.8 | Stage-7 preflight never receives `promptArtifactByteLength` | **P2** | Small | **Done** |
| 5.1 | Degraded-tier chain dead at three points | **P2** | Medium | **Done** |
| 5.2 | `stream` never set on the canonical request | **P3** | Small | **Done** |
| 5.3 | `stopConditionsFromManifest` always returns `[]` | **P3** | Docs | **Done** |
| 5.4 | `freshnessHint` never read | **P3** | Small | **Done** |
| 5.5 | `ConfigCache` request-scoped → TTL useless | **P2** | Small | **Done** |
| 5.6 | Conversational `turn_ordinal` gate; tenant-unbound (closed by 2.6) | **P3** | Docs | **Done** |
| 5.7 | Composer does not neutralize `userIntent` | **P3** | Small | **Done** |
| 5.8 | Transcript `context_requested` bypasses permitted-key allowlist | **P3** | Small | **Done** |
| 5.9 | Entitlement UNIQUE / period validation / table-count nits | **P3** | Small | **Done** |
| 5.10 | `platform_counter` undercounts rejections | **P3** | Docs | **Done** |
| 6.1 | Leak guard needle is a test placeholder in production | **P1** | Small | **Done** |
| 6.2 | Truncation guard sensor missing (`wasTruncated`) | **P1** | Small | **Done** |
| 6.3 | SafetyMarkers unreachable from the prose path | **P1** | Medium | **Done** |
| 6.4 | Reconciliation flooded by missing cancel/fail rows | **P2** | Small | **Done** |
| 6.5 | Single shared operator bearer | **P2** | Docs | **Done** |
| 7.1 | Journaled `routing_tier` can contradict actual routing | **P3** | Small | **Done** |
| 7.2 | Client routing-injection guard is test-only | **P3** | Small | **Done** |
| 7.3 | `dashboardRepairRateByCapability` empty stub | **P3** | Small | **Done** |
| 7.4 | Cancel partial-usage cost is char-count estimate or zero | **P3** | Small | **Done** |
| 7.5 | Duplicate policy publish 500; rollback version ordering lexical | **P3** | Small | **Done** |
| 7.6 | Nullable `usage_event.request_id` / aged joinability undocumented | **P3** | Docs | **Done** |

**Coverage note:** every stage of the request path was read directly
(adapter, identity, entitlement, admission, quota DO, router, context
validator/preflight, composer, invocation, both providers, stream brokers,
prose guards, journal, credit, rollup, control plane, worker wiring, D1
migrations, and the checked-in fixtures). Periphery modules (`discovery/`,
`support/`, `dashboards/`, `retention/`, `config-cache/`, `logger.ts`,
`control/cohort.ts`, `control/audit.ts`, `control/support-purge.ts`,
`control/token-contract.ts`) were covered by a mechanical extraction pass
(four subagents, 50+ files) with their facts cross-checked before use;
findings from that pass are in Chunk 7.

The single highest-leverage theme: **terminal-state handling**. Admission is
careful, but every non-completed outcome (failed, cancelled, truncated,
grace-admitted) leaks DO state, skips billing rows, and corrupts idempotent
replay. Fixing 1.5 + 1.6 + 3.4 together would make the ledger, the DO, and
the client-visible replay semantics agree for the first time.

---



## Fix groups — delegation plan

Issues grouped by similarity for implementation. Each group is delegated to
one implementation agent. Every fix must respect the architecture invariants
in `docs/architecture/ai-platform/01-ai-platform.md`: no new stores, services,
or queues (§9.17, constitution); installation-scoped serialized state lives
in the quota DO; at most two DO round trips per request on the healthy path
and one R2 envelope per request (§13.6); the §5.4 error taxonomy is normative
for quota consumption; the preflight stays token-only and money appears only
in the post-response ledger priced from provider-reported tokens (§13.6.2).


| Group | Theme | Issues | Primary files |
| ----- | ----- | ------ | ------------- |
| A | Terminal-state settlement, idempotency & grace | **Done:** 1.4, 1.5, 1.6, 4.2, 4.3, 4.6, 7.4 | `src/worker.ts` (settle paths), `src/credit/`, `src/admission/`, `src/quota-do/`, `src/journal/`, `src/stream/index.ts`, `src/invocation/index.ts` |
| B | Provider adapters, invocation & streaming | **Done:** 1.1, 1.3, 3.4, 6.2, 5.3, 3.6, 3.5, 5.2 | `src/provider/`, `src/invocation/`, `src/prompt/composer.ts`, `src/worker.ts` (sleeper, chunk source), `src/stream/` |
| C | Identity, authorization & control-plane security | **Done:** 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 6.5, 7.5 | `src/identity/`, `src/entitlement/`, guard stages, `src/control/`, `src/context/validator.ts` |
| D | Routing, policy, fixtures, cache & degraded tier | **Done:** 1.2, 2.7, 5.1, 7.1, 3.1, 3.3, 3.2, 5.5 | `src/router/`, `src/control/` (publish), `manifests/`, `control/routing-policy/`, `src/config-cache/`, `src/soft-threshold/`, `src/worker.ts` (cache + router context) |
| E | Accounting, output guards & hygiene | **Done:** 5.6, 6.1, 4.1, 4.5, 6.4, 4.4, 4.8, 5.7, 5.8, 5.10, 7.6, 4.7, 5.4, 5.9, 6.3, 7.2, 7.3 | `src/journal/`, `src/stream/prose-guards.ts`, `src/context/preflight.ts`, `src/prompt/`, `src/dashboards/`, `src/rollup/`, migrations, `src/worker.ts`, `src/pricing/` |


Cross-group dependencies to respect: 3.6 invocation Retry-After landed with 1.3
(Group B); the guard-stage `retry_after` half is now Done. 6.4 landed with 4.2/4.3
(Group A) plus the reconciliation-profile refinement in Group E (batch 3);
7.1 landed with 5.1(c) (Group D); 7.4 landed with 4.1's shared pricing helper
(`src/pricing`, Group E owns the helper, Group A the cancel call site).
`src/worker.ts` is shared by groups A, B, D, and E: keep edits targeted and localized.

---



## Remaining open/partial batches

Tighter implementation batches than Groups A–E above: only **Open** and
**Partial** issues (skip **Done**). Grouped issues share a call site, helper,
or half-fix if split; each other remaining issue is its own row. Each issue
ID appears once. Row 3 merges the overlapping settlement groups (4.2/4.3
would otherwise sit in two batches). 4.1 + 7.4 stay a separate batch so
cost-helper work is not forced into the journal write path.

All **0** remaining open/partial issues; batches 1–18 are **Done**.


| # | Batch / issue | Issues | Status | Count |
| --- | --- | --- | --- | --- |
| 1 | Live streaming | 3.5, 5.2 | **Done** | 2 |
| 2 | Degraded routing | 5.1, 7.1 | **Done** | 2 |
| 3 | Terminal settlement + envelopes + period + reconciliation | 4.2, 4.3, 4.5, 4.6, 6.4 | **Done** | 5 |
| 4 | Shared cost formula | 4.1, 7.4 | **Done** | 2 |
| 5 | Routing decision shape | 3.1, 3.3 | **Done** | 2 |
| 6 | Composer hash + preflight bytes | 4.4, 4.8 | **Done** | 2 |
| 7 | Prompt hygiene | 5.7, 5.8 | **Done** | 2 |
| 8 | Docs-only cluster | 5.3, 5.10, 6.5, 7.6 | **Done** | 4 |
| 9 | Malformed policy targets fail open | 3.2 | **Done** | 1 |
| 10 | Guard-stage SSE `retry_after` still hardcoded | 3.6 | **Done** | 1 |
| 11 | `perRequestCostCeiling` token-name mismatch | 4.7 | **Done** | 1 |
| 12 | `freshnessHint` never read | 5.4 | **Done** | 1 |
| 13 | `ConfigCache` is request-scoped | 5.5 | **Done** | 1 |
| 14 | Entitlement UNIQUE + period validation | 5.9 | **Done** | 1 |
| 15 | SafetyMarkers unreachable on prose path | 6.3 | **Done** | 1 |
| 16 | Client routing-injection guard is test-only | 7.2 | **Done** | 1 |
| 17 | `dashboardRepairRateByCapability` empty stub | 7.3 | **Done** | 1 |
| 18 | Duplicate policy publish 500; lexical rollback order | 7.5 | **Done** | 1 |


**Count check**


| Source | Value |
| --- | --- |
| Audit remaining (open/partial) | Original 31 minus all 18 batches = **0** |
| Grouped open rows | 0 |
| Solo rows remaining open | 0 |
| Table total (open/partial) | **0** |

Issue IDs remaining open/partial: none. All 31 original remaining IDs are **Done**.