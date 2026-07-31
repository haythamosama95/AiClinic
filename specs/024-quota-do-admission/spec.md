# Feature Specification: Quota Durable Object and admission stage (B4)

**Feature Branch**: `ai/024-b4-quota-do-admission`

**Created**: 2026-07-31

**Status**: Draft

**Input**: Slice `B4` — "Quota Durable Object and admission stage" (delivery plan §3.3, row B4). Not a
prose feature description; it is a row of the delivery plan, so every requirement below cites a section
of `docs/architecture/17-ai-platform.md`.

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Verbatim from the `Canonical` cell of slice B4 (delivery plan §3.3):

- `§4.3.3`
- `§4.4`
- `§9.17`
- `§7.7`
- `§6.1 stage 8`
- `§6.2`
- `§6.6`

### Freezes

This slice establishes, for the first time:

- **The per-installation Quota Durable Object contract.** One Durable Object instance per installation is
  the only primitive here that gives serialized, strongly consistent accounting; it holds the entitlement
  snapshot, the period counters, and the in-flight count, and it owns per-installation quota, concurrency,
  the `jti` replay set, and idempotency records (§4.3.3; §4.4). It never holds long-term records or
  per-request objects (§4.4).
- **The admission RPC of stage 8.** A single admission call answered by the Quota DO answers all four
  installation-scoped questions at once — `jti` freshness, idempotency-key novelty, remaining budget, and
  concurrency headroom — in one Durable Object round trip (§6.1 stage 8; §9.17; §4.3.3).
- **The separate credit RPC.** Actual usage is settled by a separate credit call to the same Quota DO
  after the call completes, adjusting the period counters including partial usage (§6.1 stage 15; §4.3.3
  "credited with actual usage after").
- **The in-object ephemeral store and its expiry.** The `jti` replay set and idempotency records live
  inside the Quota DO as ephemeral entries that expire in place — minutes to hours, no table to prune
  (§7.7 `ephemeral` class; §9.17).
- **The capped fail-open grace policy for Quota DO unavailability.** When the Quota DO is unavailable the
  admission stage follows the capped grace allowance and later reconciliation that Open Decision 3 names,
  so an infrastructure blip does not block care (§15 #3; delivery plan §3.3 row B4 "Done when").

Later slices may extend these (e.g. add the soft-threshold degraded-routing read of remaining budget in
F4) and may not rewrite them (delivery plan §2.3).

### Consumes

- Slice **A5** freezes the platform D1 logical model (every §7.3 entity) and the config cache: an
  in-isolate memory map, short TTL, populated from D1 on a miss, holding installations, keys,
  entitlements, grants, kill switches, and the active routing policy (A5 `Freezes`; delivery plan §3.2
  row A5). B4 reads the installation's entitlement snapshot — plan, period bounds, request quota,
  token/cost budget, allowed capability set, soft threshold, status — through that cache and does not
  redefine its shape, its TTL, or its entities (§4.3.3; §7.3 `entitlement`).
- Slice **B1** freezes the AAT token contract (§5.6) — every claim, including `jti` and `exp` — and the
  installation keystore (B1 `Freezes`; delivery plan §3.3 row B1). B4 consumes the verified `jti` from the
  immutable principal B3 produced and does not redefine the claim set or the signing mechanism.
- Slice **B2** freezes the installation-lifecycle state and the `entitlement` entity written on enroll and
  modified by suspend/resume/rotate/delete (B2 `Freezes`; delivery plan §3.3 row B2). B4 reads the
  entitlement snapshot and its period bounds and does not write the lifecycle surface.
- Slice **B3** freezes the immutable request principal, the guard-stage rejection discipline, and the
  config-cache read discipline for stages 2–4 (B3 `Freezes`; delivery plan §3.3 row B3). B4 receives the
  immutable principal (installation, organization, branch, actor, role, capability scopes) and the
  parsed idempotency key and may not mutate the principal; rejections from stage 8 follow the same
  `platform_counter` bucketing discipline B3 froze (§4.3.12; §7.5).
- Slice **A6** freezes the protocol adapter surface: the parsed idempotency key, trace id, and version
  pin headers (A6 `Freezes`; delivery plan §3.2 row A6). B4 reads the idempotency key the adapter parsed
  and does not redefine the header contract.
- Slice **A2** freezes the diagnostic envelope: the §5.4 error taxonomy codes, HTTP mappings,
  retryability, and quota-consumption flags, and the error body shape (A2 `Freezes`; delivery plan §3.2
  row A2). B4 emits the §5.4 codes stage 8 owns (`unauthenticated`, `quota_exhausted`) and does not
  redefine the taxonomy or the HTTP column.

Changing any consumed contract is out of scope by definition (delivery plan §2.3). B4's `Needs` cell lists
A5, B3; A2, A6, B1, and B2 are transitive prerequisites of those.

### Open decisions relied on

- **Open Decision 3** — *Behaviour when the Quota DO is unavailable: fail open or fail closed?*
  Recommended default: "Fail open with a capped grace allowance and reconciliation — an infrastructure
  blip must not block care (R-15)." B4 implements this default: a Quota DO that cannot be reached is
  served under a capped grace allowance, the request proceeds without a second round trip, and grace usage
  is reconciled afterwards. The recommended default is assumed verbatim; if it changes, this slice stops
  and amends `17-ai-platform.md` first (§15 #3; §4.3.3; delivery plan §3.3 row B4 "Done when").
- No other §15 decision is assumed. The quota unit and period (Open Decision 2) are read from the
  `entitlement` snapshot A5 froze and are not chosen here; per-clinic model preference (Open Decision 5)
  and soft-threshold routing (Open Decision & §8.8) belong to F4, not B4.

## Clarifications

### Session 2026-07-31

- Q: Where under `ai-platform/src/` do the per-installation Quota Durable Object class and the
  stage-8 / stage-15 invocations live? → A: `src/quota-do/` holds the Durable Object class plus its
  RPC handlers (admission and credit); `src/admission/` holds the stage-8 invocation;
  `src/credit/` holds the stage-15 invocation `[implementation choice — no §citation]`
- Q: How does stage-8 admission obtain the entitlement snapshot it sends to the Quota DO without
  extending A5's config-cache contract or adding a D1 read on a warm isolate? → A: Admission calls
  A5's shared `ConfigCache.loadConfig(...)` (the seam B3 already used) and passes the snapshot into
  the QDO admission call; the Quota DO does no entitlement read of its own `[implementation choice
  — no §citation]`
- Q: How does the `parallel_admissions_exact_final_count` concurrency test drive N simultaneous
  admissions against one installation's Quota DO? → A: Against the real Miniflare Durable Object
  binding under `vitest.workers.config.ts` (the same setup the Consumes slices use for `ai_request`
  / `platform_counter`), spawning N concurrent `fetch` calls to the DO instance and asserting the
  final counter; an in-memory stub would only test the stub, not DO-level serialization
  `[implementation choice — no §citation]`
- Q: How do the spy-based integration tests assert "exactly one DO fetch per request" and "grace
  usage reconciled afterwards" without coupling to the Worker's internal call sites? → A: Inject a
  counting spy around `env.QUOTA_DO` (Miniflare's DO namespace), asserting the fetch count per
  request and the post-reconciliation counter delta — the same injection shape A5/B3 use for D1
  reads, extended to the DO binding `[implementation choice — no §citation]`
- Q: How does the Quota Durable Object expire the ephemeral `jti` replay set and idempotency records
  in place — eagerly via a DO alarm, or lazily on access? → A: Lazy sweep-on-access; each admission
  call first evicts any entries whose `expires_at` has passed before answering, so expiry piggybacks
  on the round trip that already happens, with no `alarm()` handler and no scheduled sweep
  `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Quota Durable Object and admission stage (Priority: P1)

A requesting component that has already passed the guard stages 2–4 (B3) reaches admission (§6.1 stage
8). One Quota Durable Object round trip answers all four installation-scoped questions at once — is the
`jti` fresh, is the idempotency key new, is there budget left, is there concurrency headroom — and a
separate credit call settles actual usage after the call completes. Replay and idempotency ride along in
that same round trip because both are installation-scoped facts that need exactly the serialization the
DO already provides, which removes a D1 table, its TTL pruning cron, and one D1 write per request, and
costs no additional DO request. The ephemeral `jti` replay set and idempotency records expire in place
inside the object, with no table to prune. The pipeline stage makes exactly one Durable Object round
trip per request; a repeated idempotency key returns the original request's state instead of starting a
second inference; and when the Quota DO is unavailable the stage follows the capped fail-open grace
policy and reconciles afterwards.

**Why this priority**: B4 is sequenced after A5 and B3 (its `Needs`) because admission reads the
entitlement snapshot A5 froze through the config cache, consumes the `jti` and the immutable request
principal B3 froze, and runs after identity, entitlement, and rate limiting have already produced a
principal and a cheap rejection — the ordering principle that keeps idempotency *after* identity so an
idempotency lookup is never performed on behalf of an unverified caller (delivery plan §3.3 row B4
`Needs` = A5, B3; §6.2 "Why admission is one stage and not another"). It precedes C3 because the
journal writer's stage 9 sits exactly where a request stops being a candidate and starts being work, and
admission is the last word on whether it does.

**Independent Test**: Provably complete by automated Durable Object unit, concurrency, and integration
(spy) tests that assert the four admission answers, the separate credit call (including partial usage),
serialized counting under parallel admissions, in-place expiry of ephemeral entries, exactly one DO
fetch per request, the idempotent replay returning the original state, the expired-token-with-same-key
`unauthenticated` consequence, and the capped fail-open grace policy (delivery plan §2.2; DP-3; §3.11.2
row B4).

**Acceptance Scenarios**:

1. **Given** a request that has passed stages 2–4 carrying a `jti` not yet seen for this installation,
   **When** admission runs, **Then** a single Quota Durable Object round trip answers `jti` fresh and
   admits the request (delivery plan §3.3 row B4 "Done when"; §3.11.2 row B4 "fresh `jti` accepted";
   §6.1 stage 8; §4.3.3).
2. **Given** a `jti` already seen for this installation, **When** admission runs, **Then** the repeated
   `jti` is rejected as a replay (delivery plan §3.11.2 row B4 "repeated `jti` rejected"; §4.3.3; §9.17).
3. **Given** an idempotency key not yet seen for this installation, **When** admission runs, **Then** the
   key is accepted as new and the request proceeds (delivery plan §3.11.2 row B4 "new idempotency key
   accepted"; §6.6; §6.1 stage 8).
4. **Given** an idempotency key already seen for this installation and a still-valid request, **When**
   admission runs, **Then** the repeat returns the existing request's state instead of starting a second
   inference (delivery plan §3.3 row B4 "Done when"; §3.11.2 row B4 "repeat returns the prior record";
   §6.6; §6.1 stage 8).
5. **Given** an installation whose remaining budget for the period is exhausted, **When** admission
   runs, **Then** the request is rejected `quota_exhausted` (delivery plan §3.11.2 row B4 "budget
   exhaustion"; §6.1 stage 8; §5.4).
6. **Given** an installation already at its concurrency ceiling for in-flight requests, **When**
   admission runs, **Then** the request is rejected for lack of concurrency headroom (delivery plan
   §3.11.2 row B4 "concurrency ceiling"; §4.3.3; §4.4).
7. **Given** a request that completes with actual token usage, **When** the credit call runs, **Then**
   the Quota DO's period counters are adjusted by the actual usage (delivery plan §3.3 row B4 "Done
   when"; §3.11.2 row B4 "credit adjusts counters correctly"; §6.1 stage 15; §4.3.3 "credited with
   actual usage after").
8. **Given** a request that was cancelled mid-stream with partial usage, **When** the credit call runs,
   **Then** the partial usage is credited to the Quota DO and the period counters reflect it (delivery
   plan §3.11.2 row B4 "credit adjusts counters correctly including partial usage"; §6.1 stage 15;
   §4.3.3; §6.4 "partial usage is credited").
9. **Given** N parallel admission calls against one installation's Quota DO, **When** they all settle,
   **Then** the final period count equals the exact sum of the admitted requests, because the DO provides
   serialized counting (delivery plan §3.11.2 row B4 "N parallel admissions produce an exact final
   count"; §4.4 "Serialized counting"; §3.3 row B4 "a concurrency test demonstrates serialized
   counting").
10. **Given** `jti` replay set and idempotency records older than the ephemeral horizon, **When** the
    in-object expiry runs, **Then** the entries expire in place, with no table to prune and no separate
    TTL cron (delivery plan §3.3 row B4 "Done when"; §3.11.2 row B4 "ephemeral entries expire in place";
    §7.7 `ephemeral`; §9.17).
11. **Given** a request that passes the guard stages, **When** admission runs as pipeline stage 8,
    **Then** the pipeline makes exactly one Durable Object round trip for that request — no second
    round trip for replay, idempotency, quota, or concurrency (delivery plan §3.3 row B4 "Done when";
    §3.11.2 row B4 "exactly one Durable Object fetch per request"; §6.1 stage 8; §7.5 "Multiple round
    trips to the same DO") — *spy on the DO binding and assert one fetch*.
12. **Given** a repeated idempotency key, **When** admission runs, **Then** admission returns the
    original request's state and starts no second inference (delivery plan §3.11.2 row B4 "a repeated
    idempotency key returns the original state and starts no second inference"; §6.6).
13. **Given** a transport retry whose token expired in the meantime carrying the same idempotency key,
    **When** admission runs, **Then** the request is rejected `unauthenticated` rather than returning the
    original result, because idempotency is checked after identity (delivery plan §3.11.2 row B4
    "expired token with the same key → `unauthenticated`"; §6.2).
14. **Given** the Quota Durable Object is unreachable, **When** admission runs, **Then** the stage
    follows the capped fail-open grace allowance and the request proceeds under that cap, then its usage
    is reconciled afterwards (delivery plan §3.3 row B4 "Done when"; §3.11.2 row B4 "Durable Object
    unavailable → capped grace then rejection; grace usage is reconciled afterwards"; §15 #3; §4.3.3).
15. **Given** the Quota Durable Object is unreachable and the grace allowance is exhausted, **When**
    admission runs, **Then** the request is rejected rather than admitted unbounded (delivery plan
    §3.11.2 row B4 "capped grace then rejection"; §15 #3).
16. **Given** an admission served under the fail-open grace cap, **When** the Quota DO becomes reachable
    again, **Then** the grace usage that was admitted without serialized accounting is reconciled against
    the DO's counters afterwards (delivery plan §3.11.2 row B4 "grace usage is reconciled afterwards";
    §15 #3).
17. **Given** a request that is admitted and then runs to completion, **When** the pipeline invokes the
    credit call at stage 15 alongside the D1 update, **Then** admission and credit are exactly two DO
    calls for the whole request lifecycle — one at stage 8, one at stage 15 — and no third DO call is
    made (§6.1 stages 8 and 15; §7.5).
18. **Given** an admission rejection, **When** the rejection is tallied, **Then** it is counted in an
    in-isolate tally flushed periodically to bucketed `platform_counter` rows and is never journaled as
    a request and never written one row per event (§4.3.12; §7.5; B3 `Freezes`).

### Test plan

Every named test runs in CI on every change (§13.5). The layer designation is the one named in the
slice's row of delivery plan §3.11.2 ("DO unit + concurrency + integration (spy)").

| Test name | Layer | Asserts |
| --- | --- | --- |
| `admission_fresh_jti_accepted` | DO unit | A previously-unseen `jti` is admitted as fresh (§3.11.2 row B4; §4.3.3; §6.1 stage 8) |
| `admission_repeated_jti_rejected` | DO unit | A `jti` already seen for this installation is rejected as a replay (§3.11.2 row B4; §9.17) |
| `admission_new_idempotency_key_accepted` | DO unit | A previously-unseen idempotency key is accepted as new (§3.11.2 row B4; §6.6) |
| `admission_repeat_idempotency_key_returns_prior_record` | DO unit | A repeat idempotency key returns the existing request's state instead of starting a second inference (§3.11.2 row B4; §6.6; §6.1 stage 8) |
| `admission_budget_exhaustion_rejected` | DO unit | An installation with no remaining budget is rejected `quota_exhausted` (§3.11.2 row B4; §6.1 stage 8; §5.4) |
| `admission_concurrency_ceiling_rejected` | DO unit | An installation at its in-flight concurrency ceiling is rejected for lack of headroom (§3.11.2 row B4; §4.3.3; §4.4) |
| `credit_adjusts_counters_with_actual_usage` | DO unit | A completed request's credit call adjusts the period counters by actual usage (§3.11.2 row B4; §6.1 stage 15; §4.3.3) |
| `credit_adjusts_counters_with_partial_usage` | DO unit | A cancelled request's partial usage is credited (§3.11.2 row B4; §6.1 stage 15; §6.4) |
| `parallel_admissions_exact_final_count` | Concurrency | N parallel admissions against one installation produce an exact final count (§3.11.2 row B4; §4.4 "Serialized counting") |
| `ephemeral_entries_expire_in_place` | DO unit | `jti` replay and idempotency records expire in place at the ephemeral horizon with no table to prune (§3.11.2 row B4; §7.7 `ephemeral`; §9.17) |
| `admission_exactly_one_do_fetch_per_request` | Integration (spy) | The pipeline stage makes exactly one Durable Object fetch per request (§3.11.2 row B4; §6.1 stage 8; §7.5) — *spy on the DO binding and assert one fetch* |
| `admission_repeated_key_no_second_inference` | Integration (spy) | A repeated idempotency key returns the original state and starts no second inference (§3.11.2 row B4; §6.6) |
| `admission_expired_token_same_key_unauthenticated` | Integration | An expired token with the same idempotency key is rejected `unauthenticated`, not returned as the original result (§3.11.2 row B4; §6.2) |
| `quota_do_unavailable_capped_grace_then_rejection` | Integration | Quota DO unavailability serves the request under a capped grace allowance, then rejects when the cap is exhausted (§3.11.2 row B4; §15 #3) |
| `grace_usage_reconciled_afterwards` | Integration (spy) | Usage admitted under the fail-open cap is reconciled against the DO's counters afterwards (§3.11.2 row B4; §15 #3) |
| `admission_rejection_counted_not_journaled` | Integration (spy) | An admission rejection is tallied to bucketed `platform_counter` and creates no `ai_request` row (§4.3.12; §7.5; B3 `Freezes`) |

### Edge Cases

- **Every error code B4 can emit.** Admission (§6.1 stage 8) owns these taxonomy codes: `unauthenticated`
  (HTTP 401 — the consequence of an idempotency retry whose token expired in the meantime, because
  idempotency is checked after identity), and `quota_exhausted` (the `Done when` rejection when the
  remaining budget is gone). The HTTP status is normative and is applied by the protocol adapter (A6),
  not by B4; B4 emits the taxonomy code, which is what clients branch on (§5.4; §4.3.1; A6 `Consumes`).
  No other code is emitted by stage 8. A replayed `jti` is not a distinct client-facing code; it is
  rejected through the same `unauthenticated` path an unverified caller would see, because `jti` replay
  is only meaningful after identity has already authenticated the caller (§6.2).
- **Idempotency after identity, not before.** A transport retry whose token expired in the meantime is
  rejected `unauthenticated` rather than returning the original result; the client re-mints the AAT and
  resubmits with the *same* idempotency key, which is what the error taxonomy already instructs it to do
  (§6.2; §5.4). This is the boundary that makes the single-round-trip admission stage possible.
- **User-initiated retry is a new request, not a replay.** The client's idempotency key is stable across
  transport retries of the *same* user action, but a *user*-initiated retry is a distinct new request with
  a new idempotency key, linked to the previous one — conflating the two would corrupt both quota
  accounting and eval data (§6.6).
- **No pre-flight reservations against the estimated cost.** The Quota DO deliberately does not hold
  pre-flight reservations against the estimated cost of each request; reservations exist to stop
  concurrent requests from collectively overshooting the last unit of quota, which at clinic volumes is
  an overshoot of one or two requests with no real exposure, while the cost ceiling (§6.1 stage 7, slice
  C2) already blocks the genuinely dangerous case of a single very expensive request. Counting after the
  fact is exact in the billing ledger and one mechanism simpler (§4.3.3). B4 implements no reservation
  mechanism.
- **Ephemeral horizon.** The `jti` replay set and idempotency records live inside the Quota DO and expire
  in place at the `ephemeral` retention horizon — minutes to hours, with no table to prune and no TTL
  cron (§7.7; §9.17). The horizon is named by the architecture; B4 enforces in-place expiry and does not
  choose or invent the value. Retention class is a per-capability manifest field for the *envelope*, not
  for these ephemeral records.
- **Capped grace boundary.** Quota DO unavailability admits under a capped grace allowance and then
  rejects once the cap is exhausted; the cap is the value Open Decision 3 recommends ("a capped grace
  allowance and reconciliation"). B4 enforces the boundary against that configured value and does not
  choose it (§15 #3; delivery plan §3.3 row B4 "Done when"). Grace usage is reconciled against the DO's
  counters afterwards, never silently dropped (§15 #3).
- **Exactly two DO calls per request, no third.** Admission is one DO round trip at stage 8; the credit
  call is one DO round trip at stage 15. A second round trip for replay, idempotency, quota, or
  concurrency is a prohibited anti-pattern (§7.5; §13.6); a third round trip is out of scope and must not
  be added.
- **Serialized counting, not approximate.** Rate limiting (B3) is approximate and eventually consistent
  by design; quota and concurrency are not, which is why they share the one Quota DO. The
  serialized-counting test takes N parallel admissions and asserts the exact final count (delivery plan
  §3.11.2 row B4; §4.3.3; §4.4).
- **Quota exhaustion never hard-locks.** A `quota_exhausted` rejection disables an additive feature and
  says so; it never blocks a clinical workflow (constitution principle V; §14 "V"; §8.8). Soft-threshold
  degraded routing — crossing a soft threshold to downgrade a cheaper model rather than refusing — is F4,
  not B4 (§4.3.3; delivery plan §3.7 row F4); B4 exposes the remaining budget that F4 will read as an
  extension.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Admission (§6.1 stage 8) MUST be implemented as a single Durable Object round trip to the
  per-installation Quota Durable Object, and that one admission call MUST answer all four
  installation-scoped questions at once — `jti` freshness, idempotency-key novelty, remaining budget, and
  concurrency headroom (§4.3.3; §4.4; §9.17; delivery plan §3.3 row B4 "Done when").
- **FR-002**: The Quota Durable Object MUST be the only primitive that holds per-installation quota,
  concurrency, the `jti` replay set, and idempotency records, providing strong-per-object serialized
  counting — the property neither D1 nor a cache can supply (§4.3.3; §4.4). It MUST NOT hold long-term
  records or per-request objects (§4.4).
- **FR-003**: Replay and idempotency MUST ride along inside the admission round trip rather than in a
  separate D1 table or a KV namespace, because both are installation-scoped facts that need exactly the
  serialization the DO already provides and are consulted at the same point in the pipeline (§4.3.3;
  §9.17; §4.4).
- **FR-004**: The admission call MUST accept a `jti` not yet seen for this installation and MUST reject a
  `jti` already seen as a replay (§4.3.3; §9.17; delivery plan §3.11.2 row B4).
- **FR-005**: The admission call MUST accept an idempotency key not yet seen for this installation and,
  for a repeat of a key already seen, MUST return the existing request's state instead of starting a
  second inference (§6.6; §6.1 stage 8; delivery plan §3.3 row B4 "Done when"; §3.11.2 row B4).
- **FR-006**: The admission call MUST reject a request whose remaining period budget is exhausted as
  `quota_exhausted`, the stage-8 failure code (§6.1 stage 8; §5.4; §4.3.3; delivery plan §3.11.2 row B4).
- **FR-007**: The admission call MUST reject a request whose installation is already at its in-flight
  concurrency ceiling for lack of concurrency headroom (§4.3.3; §4.4; delivery plan §3.11.2 row B4).
- **FR-008**: A separate credit call, invoked at §6.1 stage 15 alongside the journal's terminal D1
  update, MUST settle actual usage against the Quota DO's period counters after the call completes, and
  MUST include partial usage from a cancelled request (§6.1 stage 15; §4.3.3 "credited with actual usage
  after"; §6.4; delivery plan §3.3 row B4 "Done when"; §3.11.2 row B4).
- **FR-009**: N parallel admissions against one installation's Quota DO MUST produce an exact final
  count, because the DO provides serialized counting where D1 races on read-modify-write and no cache can
  be authoritative (§4.4; §7.5 "Quota counters in D1"; delivery plan §3.3 row B4 "Done when"; §3.11.2
  row B4).
- **FR-010**: The `jti` replay set and idempotency records MUST live inside the Quota DO as ephemeral
  entries that expire in place at the `ephemeral` retention horizon — minutes to hours, with no table to
  prune and no TTL cron (§7.7 `ephemeral`; §9.17; delivery plan §3.3 row B4 "Done when"; §3.11.2 row B4).
- **FR-011**: The pipeline stage MUST make exactly one Durable Object round trip per request at
  admission; a second round trip to the same DO for replay, idempotency, quota, or concurrency MUST NOT
  be added (§6.1 stage 8; §7.5 "Multiple round trips to the same DO"; §9.17; §13.6; delivery plan §3.3
  row B4 "Done when"; §3.11.2 row B4).
- **FR-012**: A transport retry whose token expired in the meantime carrying the same idempotency key
  MUST be rejected `unauthenticated` rather than returning the original result, because idempotency is
  checked after identity, not before it; the client re-mints the AAT and resubmits with the same
  idempotency key (§6.2; §5.4; §6.6; delivery plan §3.11.2 row B4).
- **FR-013**: When the Quota Durable Object is unavailable, the admission stage MUST follow the capped
  fail-open grace allowance Open Decision 3 names: serve the request under the cap, reject once the cap
  is exhausted, and reconcile the grace usage against the DO's counters afterwards (§15 #3; §4.3.3;
  delivery plan §3.3 row B4 "Done when"; §3.11.2 row B4).
- **FR-014**: Admission rejections MUST be counted in an in-isolate tally flushed periodically to
  bucketed `platform_counter` rows keyed by dimension and time bucket, never journaled as a request and
  never written one row per event (§4.3.12; §7.5; B3 `Freezes`; delivery plan §3.11.2 row B4).
- **FR-015**: The Quota DO MUST NOT hold pre-flight reservations against the estimated cost of each
  request; the cost ceiling at §6.1 stage 7 (slice C2) blocks the dangerous single-request case, and
  counting after the fact is exact in the billing ledger (§4.3.3; §9.14 reservation deferral).
- **FR-016**: The credit call MUST be exactly the second DO round trip of the request lifecycle (after
  stage 8's admission), and no third DO call MUST be introduced (§6.1 stages 8 and 15; §7.5; §13.6).

### Key Entities *(include if feature involves data)*

- **Quota Durable Object** (contract type): the platform's only stateful side-car, one instance per
  installation. It holds the entitlement snapshot, the period counters, and the in-flight count, plus the
  in-object ephemeral `jti` replay set and idempotency records, all of which are installation-scoped facts
  needing serialized truth (§4.3.3; §4.4). Its RPC surface is the admission call (stage 8) and the credit
  call (stage 15). It owns no long-term records and no per-request objects (§4.4; §7.7).
- No D1 entity is defined by this slice. B4 reads `installation`, `installation_key`, and `entitlement`
  through the config cache frozen by A5 (§7.3; A5 `Consumes`) and writes only bucketed
  `platform_counter` rows whose shape is fixed by §4.3.12 / §7.5 and was frozen by B3. Those shapes and
  names are consumed unchanged.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: The Quota Durable Object is the only stateful side-car, one instance per installation,
  holding the counters and ephemeral sets for a clinic-scale tenant boundary. At clinic volume the
  serialized counting it provides is the right primitive for an exact answer without enterprise machinery:
  no queues, no second metrics store, no per-request state (§4.3.3; §4.4; §14). One DO class, five
  mechanisms deliberately left out (§9.14).
- **Layer Placement**: This slice touches `ai-platform/` (the Cloudflare Worker and its Durable Object)
  only. The Quota DO is a platform-side primitive over the platform's own D1-derived entitlement
  snapshot; the credit call is invoked by the Worker at stage 15. It does not touch `backend/` (Supabase)
  — the clinic-side signing and keystore belong to B1, the installation lifecycle belongs to B2, and the
  economics B4 reads belong to a later control-plane function — and it does not touch `frontend/`
  (Flutter). Per §14, the gateway is a non-primary, additive component: *"no domain logic, no business
  data, no write path into Supabase, always optional."* The Quota DO never writes to the clinic database.
- **Data Integrity & Security**: Every request that reaches admission has already been authenticated,
  audience-scoped, installation-scoped, entitled, rate-limited, and kill-switch-checked by B3 against an
  immutable principal (§4.3.2; §4.3.3; §14 "IV"). Admission is the last gate before the journal: it
  serializes the four installation-scoped facts (replay, idempotency, budget, concurrency) so two
  isolated Worker invocations cannot double-spend a budget or replay a `jti`. The D1 read path is the one
  A5 froze on a cold isolate; on a warm isolate admission adds no D1 read (§4.3.2; A5 `Freezes`). The
  `jti` replay set is bounded by the ephemeral horizon and never leaves the object.
- **Failure Handling**: Quota exhaustion disables an additive feature and says so; it never hard-locks
  anything (§14 "V"; §8.8). When the Quota DO itself is unavailable, the stage fails open under a capped
  grace allowance and reconciles afterwards, so an infrastructure blip does not block care (§15 #3;
  R-15). The platform is strictly additive: an unreachable or refusing admission surface degrades to "AI
  unavailable", and the client hides affordances (§14; A11).

## Out of Scope

- **Soft-threshold degraded routing** — crossing a soft quota threshold to downgrade routing to the
  capability's degraded tier rather than refusing — is F4, not B4 (§4.3.3; §8.8; delivery plan §3.7
  row F4). B4 exposes the remaining-budget answer that F4 will read but builds no routing decision.
- **The cost-ceiling pre-flight** (§6.1 stage 7, `request_too_large`) is C2, which estimates input
  tokens plus the capability's maximum output tokens against the per-request ceiling before any egress
  (§4.3.3; delivery plan §3.4 row C2). B4 performs no cost pre-flight; the cost ceiling and the quota
  budget are separate mechanisms (§4.3.3).
- **The journal writer** — creating the `ai_request` row at stage 9, recording every §6.3 transition, and
  the post-response detail and get-request endpoint — is C3 (§6.1 stages 9, 15, 16; delivery plan §3.4
  row C3). B4 invokes its credit call at stage 15 in coordination with C3's terminal D1 update but owns
  no journal row.
- **Replay rejection before identity** is explicitly rejected; idempotency is checked *after* identity,
  and that ordering is fixed by §6.2. A pre-identity replay or idempotency lookup is out of scope by
  design (§6.2; §9.17).
- **Pre-flight reservations against the estimated cost** are explicitly *not* held by the Quota DO; the
  architecture rejects that mechanism and counts after the fact (§4.3.3; §9.14). B4 implements no
  reservation.
- **Quota unit and period selection** (requests, tokens, or cost) is Open Decision 2; the recommended
  default (cost-based budget with a request-count guard) is read from the `entitlement` snapshot A5 froze
  and is not chosen or re-decided here (§15 #2; A5 `Consumes`).
- **Token contract rotation with overlapping acceptance** (two `ver` values accepted) is J4 (delivery
  plan §3.9 row J4). **Capability deprecation / overlap windows** (J1) and **out-of-band cancellation**
  requiring a per-request Durable Object are band K / §9.14 deferrals; neither is built.
- **HTTP status translation.** Mapping taxonomy codes to HTTP statuses is the protocol adapter's job
  (A6, §4.3.1; §5.4); B4 emits taxonomy codes and does not apply the HTTP column itself.
- **`context_required` self-healing** is J2; B4 admits or rejects and never returns the
  `context_required` terminal-event kind (delivery plan §3.9 row J2).

Prohibitions inherited from delivery plan §6.4, copied verbatim:

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — not applicable here,
  as B4 touches neither the client nor prompts, but the prohibition is inherited.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7) — the Quota DO is per-installation, not
  per-request, and holds no per-request objects (§4.4; §9.18).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One admission call to the per-installation Quota Durable Object answers all four
  installation-scoped questions — `jti` freshness, idempotency-key novelty, remaining budget, and
  concurrency headroom — and a separate credit call settles actual usage (delivery plan §3.3 row B4
  "Done when"; §6.1 stage 8; §4.3.3).
- **SC-002**: A fresh `jti` is admitted and a repeated `jti` is rejected as a replay; a new idempotency
  key is admitted and a repeat returns the original request's state instead of starting a second
  inference (delivery plan §3.11.2 row B4; §4.3.3; §9.17; §6.6).
- **SC-003**: Budget exhaustion rejects `quota_exhausted` and a request against an installation at its
  concurrency ceiling is rejected for lack of headroom (delivery plan §3.11.2 row B4; §6.1 stage 8; §5.4;
  §4.4).
- **SC-004**: The credit call adjusts the period counters by actual usage, including partial usage from a
  cancelled request (delivery plan §3.11.2 row B4; §6.1 stage 15; §6.4).
- **SC-005**: N parallel admissions against one installation produce an exact final count, proving
  serialized counting (delivery plan §3.3 row B4 "Done when"; §3.11.2 row B4; §4.4).
- **SC-006**: The `jti` replay set and idempotency records expire in place at the ephemeral horizon with
  no table to prune (delivery plan §3.3 row B4 "Done when"; §3.11.2 row B4; §7.7 `ephemeral`; §9.17).
- **SC-007**: The pipeline makes exactly one Durable Object round trip per request at admission and no
  second round trip for replay, idempotency, quota, or concurrency (delivery plan §3.3 row B4 "Done when";
  §3.11.2 row B4; §7.5; §9.17).
- **SC-008**: A transport retry whose token expired in the meantime carrying the same idempotency key is
  rejected `unauthenticated`, not returned as the original result (delivery plan §3.11.2 row B4; §6.2).
- **SC-009**: Quota DO unavailability is served under a capped fail-open grace allowance, rejection
  follows once the cap is exhausted, and grace usage is reconciled afterwards (delivery plan §3.3 row B4
  "Done when"; §3.11.2 row B4; §15 #3).
- **SC-010**: An admission rejection is tallied to bucketed `platform_counter` and creates no
  `ai_request` row and no per-event row (§4.3.12; §7.5; B3 `Freezes`).

## Assumptions

- The entitlement snapshot — plan, period bounds, request quota, token/cost budget, allowed capability
  set, soft threshold, and status — is frozen by A5 as part of the config cache and the `entitlement`
  entity; B4 reads it through the shared `ConfigCache` seam and owns no cache of its own (A5 `Freezes`;
  §7.3; §4.3.3).
- The AAT token contract including the `jti` and `exp` claims is frozen by B1, and the immutable request
  principal carrying the verified `jti` is frozen by B3; B4 consumes the verified `jti` and the
  principal and defines neither (B1 `Freezes`; B3 `Freezes`; §5.6; §4.3.2).
- The installation lifecycle and the `entitlement` row's pending/active/suspended status are owned by
  B2; B4 reads them and does not write the lifecycle surface (B2 `Freezes`; delivery plan §3.3 row B2).
- The diagnostic envelope — the §5.4 error taxonomy with its normative HTTP column, retryability, and
  quota-consumption flags — is frozen by A2, and the HTTP translation is applied by the protocol adapter
  A6; B4 emits taxonomy codes and relies on that envelope (A2 `Freezes`; A6 `Freezes`; §4.3.1; §5.4).
- The parsed idempotency-key header contract is frozen by A6; B4 reads the key the adapter parsed and
  does not redefine the header (A6 `Freezes`; §4.3.1).
- The capped fail-open grace allowance follows the recommended default of Open Decision 3; the cap value
  is the configured one, not chosen by this slice (§15 #3; R-15).
- The quota unit and period (Open Decision 2) are read from the `entitlement` snapshot and are not
  re-decided here (§15 #2; A5 `Consumes`).
- The D1 read discipline on a warm isolate is the one A5 froze — zero reads; a cold isolate pays the
  single same-region read on a miss — and B4 introduces no additional read (A5 `Freezes`; §4.3.2).