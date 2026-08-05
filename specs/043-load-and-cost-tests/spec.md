# Feature Specification: Load and cost tests

**Feature Branch**: `ai/043-f5-load-and-cost-tests`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `F5` — "Load and cost tests" (delivery plan §3.7, band F).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.7, row F5):

> §13.5, §13.6

### Freezes

Contracts this slice establishes for the first time:

- The **load and cost test layer** named in §13.5: automated tests that exercise guard
  latency under concurrency, D1 write headroom, and Durable Object throughput per
  installation, run before each delivery checkpoint (§13.5 Load and cost tests row;
  delivery plan §3.11.6 row F5). Later checkpoints and review practice consume this
  suite; they must not redefine what the load layer measures or when it runs relative
  to checkpoints.
- The **under-load metered-footprint assertion** for the two binding Cloudflare cost
  drivers in §13.6 / §13.6.1: under load, each request performs **exactly one R2 Class A
  operation** (one payload envelope per request) and **exactly two Durable Object
  requests** (one admission call in the guard, one credit call at settle) (delivery plan
  §3.7 Done when; §3.11.6 F5; §13.6 R2 Class A and Durable Object requests rows;
  §13.6.1). This freezes the load-time proof of the design-shape budget; it does not
  rewrite the one-envelope or two-trip pipeline contracts earlier slices already
  established.
- The **measurement gate for operational honesty (CP5)**: guard latency at p95 under
  concurrency, D1 write headroom, and Durable Object throughput per installation are
  **measured**, and the one-R2 / two-DO assertions above pass — completing F5 satisfies
  checkpoint **CP5** (delivery plan §3.7 Done when; §5 CP5; §13.5; §13.6.1).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (D7). Changing any is out of scope by
definition:

- **From D7 (second provider adapter)**: the **second real provider adapter** behind the
  D2 provider port, the **recorded-fixture suite** applied to that provider, and
  **registration as a low-priority fallback target by routing-policy data alone** with no
  inference-pipeline change (D7 Freezes; delivery plan §3.5 Done when; §4.3.8; §13.5
  Provider adapter tests). F5 load- and cost-tests the platform after that second
  provider exists; it does not rewrite the adapter, fixture-suite shape, policy
  registration, or fallback ordering. The capability-eval half of D7 that binds to F1
  remains F1's concern; F5 does not redefine the eval harness.

### Open decisions relied on

None — F5 does not depend on a §15 recommended default. Its scope is the §13.5 load and
cost test layer and the §13.6 / §13.6.1 metered-footprint assertions stated in the
delivery plan §3.7 and §3.11.6 rows.

## Clarifications

### Session 2026-08-02

- Q: Where should the F5 load and cost suite run, and how should it meter R2 Class A operations, Durable Object requests, and D1 writes under load? → A: Workers-pool Miniflare (real D1/R2/QUOTA_DO) + counting spies on the bindings `[implementation choice — no §citation]`
- Q: Under load, what request path should the suite drive so T1–T5 (and the inherited T6–T7 metering spies) can observe guard latency, one R2 Class A, two DO trips, D1 headroom, and DO throughput? → A: Full happy path under load with a fake provider (admission + credit + one R2 envelope) `[implementation choice — no §citation]`
- Q: How should T1 encode the architecture’s phrases “target concurrency” and “tens of milliseconds” as suite fixture parameters (without rewriting the FR/SC prose)? → A: Concurrency fixture N=20; production-oriented design target `GUARD_P95_PRODUCTION_TARGET_MS = 100` (“tens of milliseconds”). **Revised 2026-08-05** — see Session 2026-08-05 for the workers-pool Miniflare ceiling. `[implementation choice — no §citation]`
- Q: How should T4/T5 prove D1 write headroom and DO throughput per installation were measured (no invented numeric ceilings), and how should the load suite be invoked before a delivery checkpoint? → A: Structured in-test measurement report (finite values, no ceilings) + dedicated `test:load` workers-pool script as the checkpoint gate `[implementation choice — no §citation]`


### Session 2026-08-05 (review resolution)

- Q: How should the load suite compose the happy path so spies observe production modules rather than a test-only assembly? → A: Thin production `src/pipeline` composer (`runGuard` stages 1–10 + `settleHappyPath`) called from the load harness; Worker HTTP wiring remains deferred `[implementation choice — contract extension]`
- Q: How is real concurrency generated without exceeding Quota DO `CONCURRENCY_LIMIT` (16) on one installation? → A: Bounded worker pool of size `Math.min(N=20, CONCURRENCY_LIMIT=16)` against **one shared installation**; observed in-flight peak is reported as `concurrency`; wall-clock overlap proves concurrency; DO throughput is pinned-installation DO fetches / wall_clock_seconds `[implementation choice — no §citation]`
- Q: How should T1 assert guard p95 under workers-pool Miniflare when a single sequential Miniflare `runGuard` is already ~300–400 ms (revises Clarification Q3)? → A: Time the full `runGuard` (§6.1 stages 1–10). Keep production design target `GUARD_P95_PRODUCTION_TARGET_MS = 100`. Suite fixture ceiling under Miniflare concurrency is `GUARD_P95_CEILING_MS = 2000`; T1 requires a finite p95 under that ceiling plus wall-clock overlap proof `[implementation choice — revises Q3]`
- Q: How does the suite join CI permanently for FR-002 / contract §2.2? → A: `.github/workflows/ci.yml` job `ai-platform-tests` runs `npm test` and `npm run test:load` `[implementation choice — no §citation]`
- Q: How are per-request maxima asserted (not averages only)? → A: Binding spies tag Class A / DO ops via AsyncLocalStorage and report `*_max_per_request` fields alongside averages; D1 counts INSERT into `ai_request` at `run`/`batch`; R2 counts put/list/multipart Class A; D1 spy is prototype-preserving `[implementation choice — contract extension]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Load and cost tests (Priority: P1)

As the platform operator and checkpoint reviewer, after a second real provider is
registered by policy alone (D7), I run the load and cost test layer before delivery
checkpoints: under target concurrency the guard's p95 latency stays within tens of
milliseconds; under load each request performs exactly one R2 Class A operation and
exactly two Durable Object requests; and D1 write headroom and Durable Object throughput
per installation are measured so the metered footprint matches the §13.6.1 design-shape
budget and checkpoint CP5 can be answered honestly.

**Why this priority**: F5 sits where it does because its `Needs` (D7) are the point at
which provider independence is in place (CP4 rests on D7 plus F1) and the full inference
path is available to load; without that, load tests would invent a second provider or
measure an incomplete pipeline. Completing F5 satisfies checkpoint **CP5**: the platform
is operationally honest — costs are bounded and measured, and the metered footprint
matches §13.6.1 (delivery plan §3.7; §5 CP5).

**Independent Test**: Guard latency at p95 under concurrency, D1 write headroom, and
Durable Object throughput per installation are measured, and per-request R2 Class A
operations and Durable Object round trips are asserted at one and two respectively
(delivery plan §3.7 Done when; §3.11.6 row F5).

**Acceptance Scenarios**:

1. **Given** the AI gateway under load at target concurrency (N=20 requests on **one
   shared installation**, bounded pool `Math.min(20, CONCURRENCY_LIMIT=16)`), **When**
   guard latency for the full `runGuard` path (architecture §6.1 stages 1–10) is measured
   at p95, **Then** that p95 is within the suite fixture bound for the runtime (production
   design target 100 ms; workers-pool Miniflare ceiling 2000 ms — Clarification Q3 /
   2026-08-05) and wall-clock overlap proves real concurrency. *(Guard p95 within tens of
   milliseconds at target concurrency)*
2. **Given** requests exercised under load via production `src/pipeline`, **When**
   per-request R2 Class A operations are counted (spy / meter, including maxima), **Then**
   each request performs exactly one R2 Class A operation (one payload envelope per
   request). *(Exactly one R2 Class A operation per request under load)*
3. **Given** requests exercised under load via production `src/pipeline`, **When**
   per-request Durable Object requests are counted (spy / meter, including maxima),
   **Then** each request performs exactly two Durable Object requests (one admission call
   in the guard, one credit call at settle). *(Exactly two Durable Object requests per
   request under load)*
4. **Given** the load and cost suite running before a delivery checkpoint, **When** D1
   write behaviour on the hot path is exercised under load, **Then** D1 write headroom is
   measured (one row per request on the hot path, detail afterwards — no invented numeric
   pass threshold beyond measurement). *(D1 write headroom measured)*
5. **Given** the load and cost suite running before a delivery checkpoint against one
   pinned installation, **When** installation-scoped Durable Object work is exercised
   under load, **Then** Durable Object throughput per installation is measured as
   DO fetches / wall_clock_seconds. *(Durable Object throughput per installation measured)*

### Test plan

Layer: **Load** (delivery plan §3.11.6, row F5; §13.5 Load and cost tests — guard latency
under concurrency; D1 write headroom; DO throughput per installation; before each
delivery checkpoint). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `guard_p95_within_tens_of_ms_at_target_concurrency` | Load | Guard p95 within tens of milliseconds at target concurrency (§3.11.6 F5; §13.5; Done when) |
| T2 | `exactly_one_r2_class_a_per_request_under_load` | Load | Exactly one R2 Class A operation per request under load (§3.11.6 F5; §13.6; §13.6.1; Done when) |
| T3 | `exactly_two_durable_object_requests_per_request_under_load` | Load | Exactly two Durable Object requests per request under load — admission + credit (§3.11.6 F5; §13.6; §13.6.1; Done when) |
| T4 | `d1_write_headroom_measured` | Load | D1 write headroom measured under load (§3.11.6 F5; §13.5; §13.6 D1 writes row; Done when) |
| T5 | `do_throughput_per_installation_measured` | Load | Durable Object throughput per installation measured (§3.11.6 F5; §13.5; Done when) |
| T6 | `no_second_r2_object_per_request` | Load (inherited prohibition) | No second R2 object per request under load (delivery plan §6.4 / §7.5, §13.6; reinforces T2) |
| T7 | `no_second_quota_do_round_trip_beyond_two` | Load (inherited prohibition) | No additional Quota Durable Object round trip beyond the two named in §13.6 (delivery plan §6.4 / §7.5, §13.6; reinforces T3) |
| T8 | `load_suite_introduces_no_per_request_server_state` | Load (inherited prohibition) | Running load/cost tests does not introduce per-request server-side state of any kind (delivery plan §6.4 / §4.4, §9.7) |
| T9 | `no_prompt_provider_model_in_flutter_from_load_suite` | Load (inherited prohibition) | The load/cost suite introduces no prompt text, provider name, or model identifier into Flutter client code (delivery plan §6.4 / R-12) |

Coverage of every error code the slice can emit (§3.10 item 2): this slice is a **Load**
layer suite, not a pipeline stage. It emits **no** runtime §5.4 taxonomy codes.
Pass/fail of p95, one-R2 / two-DO assertions, and completion of the named measurements
are suite outcomes (T1–T5), not request error codes.

---

### Edge Cases

- **No runtime taxonomy codes.** F5 does not emit `quota_exhausted`, `rate_limited`,
  `request_too_large`, or any other §5.4 code. A failing load assertion fails the suite /
  checkpoint gate; it does not invent a new request error code (§13.5; §3.10).
- **p95 bound is "tens of milliseconds", not an invented numeric cutoff in FR/SC.**
  §3.11.6 F5 and the Done when cell require guard p95 within tens of milliseconds at
  target concurrency. FR/SC prose keeps those phrases; suite fixture parameters
  (Clarification Q3 / 2026-08-05) encode production design target 100 ms and workers-pool
  Miniflare ceiling 2000 ms without rewriting FR-003 / SC-001.
- **D1 headroom and DO throughput are measured, not thresholded here.** Done when and
  §3.11.6 require those quantities to be **measured**. No pass/fail numeric ceiling for
  either is named in §13.5 or §13.6; inventing one is out of scope (§3.7 Done when;
  §13.5; §13.6 D1 writes row).
- **One envelope / two DO trips under load.** The happy path asserts exactly one R2 Class
  A operation and exactly two Durable Object requests per request (§13.6; §13.6.1). A
  second envelope or a third DO round trip fails T2/T3/T6/T7 (delivery plan §6.4).
- **Checkpoint timing.** The load and cost layer runs before each delivery checkpoint
  (§13.5). Completing F5 is what satisfies CP5; the suite does not redefine other
  checkpoints' gates (§5 CP5).
- **Pre-flight estimator is not this slice.** The byte-based estimator of §13.6.2 is
  Canonical background for the cost model and was implemented by C2; F5 does not
  re-implement or re-threshold pre-flight (Out of Scope).
- **Inherited prohibitions.** No §9.14 mechanism added because it looks prudent; no
  prompt/provider/model strings in Flutter; no second Quota DO round trip or second R2
  object per request; no guard-rejection journal rows or per-chunk D1 rows; no
  per-request server-side state; no client assembly of final results from chunks
  (delivery plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The platform MUST provide a load and cost test layer that covers guard
  latency under concurrency, D1 write headroom, and Durable Object throughput per
  installation (§13.5 Load and cost tests).
- **FR-002**: The load and cost tests MUST run before each delivery checkpoint (§13.5
  Load and cost tests — How).
- **FR-003**: Under load at target concurrency, guard latency at p95 MUST be within tens
  of milliseconds (delivery plan §3.7 Done when; §3.11.6 F5; §13.5).
- **FR-004**: Under load, each request MUST perform exactly one R2 Class A operation —
  one payload envelope per request (§13.6 R2 Class A operations row; §13.6.1; delivery
  plan §3.7 Done when; §3.11.6 F5).
- **FR-005**: Under load, each request MUST perform exactly two Durable Object requests —
  one admission call in the guard and one credit call at settle (§13.6 Durable Object
  requests row; §13.6.1; delivery plan §3.7 Done when; §3.11.6 F5).
- **FR-006**: D1 write headroom MUST be measured under load, consistent with the §13.6
  D1 writes control (one row per request on the hot path, detail afterwards; payloads to
  R2; no per-event metric rows; no per-chunk rows) (delivery plan §3.7 Done when;
  §3.11.6 F5; §13.5; §13.6).
- **FR-007**: Durable Object throughput per installation MUST be measured under load
  (delivery plan §3.7 Done when; §3.11.6 F5; §13.5).
- **FR-008**: The suite MUST treat Cloudflare R2 Class A operations and Durable Object
  requests as the binding metered constraints consumed by design shape (one envelope and
  two DO calls per request) and MUST assert that footprint under load (§13.6.1).
- **FR-009**: Completing this slice's measured and asserted outcomes MUST be what
  satisfies checkpoint CP5 (operational honesty: costs bounded and measured; metered
  footprint matches §13.6.1) (delivery plan §5 CP5; §3.7).
- **FR-010**: The load and cost suite MUST NOT rewrite D7's second-provider adapter,
  fixture suite, or routing-policy registration; it measures the platform that consumes
  those contracts (Consumes D7; delivery plan §3.7 Needs).

### Key Entities

Not applicable — this slice defines no entities. It freezes a load/cost test layer and
under-load assertions over R2, Durable Object, D1, and guard latency behaviour already
established by earlier pipeline slices.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Measuring guard p95, D1 write headroom, and per-installation Durable
  Object throughput, and asserting one R2 Class A operation and two Durable Object
  requests per request, keeps the platform inside the §13.6.1 clinic-scale metered
  footprint (low single-digit percentages of Cloudflare allowances at the cited clinic
  volume) without introducing hospital-scale capacity planning or fixed clusters (§13.6.1;
  constitution principle I).
- **Layer Placement**: This slice touches **`ai-platform/`** (Cloudflare Worker — load and
  cost tests against the gateway, D1, R2, and Durable Objects). It adds no `backend/`
  (Supabase) domain writes and no `frontend/` (Flutter) load UI. Per the §14
  acknowledgement, the gateway is a non-primary, additive component — it holds no domain
  logic and no business data, has no write path into Supabase, and is always optional.
- **Data Integrity & Security**: F5 does not write clinical records and does not open a
  write path into Supabase. Load assertions spy on R2 Class A and Durable Object request
  counts and measure D1/DO headroom; they do not weaken installation-scoped isolation or
  invent a second metrics store.
- **Failure Handling**: A failing load or cost assertion fails the suite / checkpoint
  gate (CP5). Load-suite failure does not hard-lock clinic workflows; AI remains additive
  and optional (§14; constitution principle V). This slice invents no new runtime
  degraded-mode UI.

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **D7 (second provider adapter)**: Adapter, fixture suite, policy registration, and
  fallback ordering remain D7; F5 only measures the platform after D7 (Consumes D7).
- **B4 (Quota Durable Object and admission)**: The admission and credit RPCs that produce
  the two DO round trips remain B4; F5 asserts the count under load and does not rewrite
  admission, credit, ephemeral store, or fail-open grace.
- **C3 (journal writer / post-response / get-request)**: The one R2 payload envelope per
  request remains C3; F5 asserts one Class A operation under load and does not rewrite
  envelope layout or journal ordering.
- **C2 (context validator and cost pre-flight)**: The §13.6.2 byte-based pre-flight
  estimator and `request_too_large` path remain C2; F5 does not re-implement pre-flight.
- **F1–F4**: Eval harness, acceptance recording, support/retention/rollups, and
  soft-threshold routing are sibling F slices; F5 does not implement them.
- **H\* / J\***: Conversational and deferred compatibility bands are out of scope.
- **Token-spend engineering beyond the load assertions**: §13.6.1 states token spend
  dominates and must be engineered continuously; F5's Done when is the Cloudflare
  metered-footprint load gate (one R2, two DO, measured D1/DO/guard), not a new token
  budget product surface.

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No second Quota Durable Object round trip and no second R2 object per request (§7.5,
  §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional
  content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An automated load test proves guard p95 is within tens of milliseconds at
  target concurrency (T1; delivery plan §3.7 Done when; §3.11.6 F5).
- **SC-002**: An automated load test proves exactly one R2 Class A operation per request
  under load (T2; T6; §13.6; §13.6.1; Done when).
- **SC-003**: An automated load test proves exactly two Durable Object requests per
  request under load (T3; T7; §13.6; §13.6.1; Done when).
- **SC-004**: An automated load test measures D1 write headroom under load (T4; Done
  when; §13.5; §13.6).
- **SC-005**: An automated load test measures Durable Object throughput per installation
  (T5; Done when; §13.5).
- **SC-006**: Completing SC-001–SC-005 is what satisfies checkpoint CP5 (delivery plan
  §5 CP5; §3.7).
- **SC-007**: The suite introduces no per-request server-side state and no Flutter
  prompt/provider/model strings (T8–T9; delivery plan §6.4).

## Assumptions

- D7 is complete on `ai/master` (or otherwise available as Needs): the second real
  provider adapter and routing-policy registration exist so load exercises the
  post-CP4 platform without inventing a second provider (delivery plan §3.7 Needs; D7
  Freezes).
- The one-R2-envelope and two-DO-trip pipeline behaviours asserted under load were
  established by earlier slices (notably C3 and B4); F5 freezes the under-load proof,
  not those pipeline contracts themselves (§13.6; §13.6.1).
- "Target concurrency" and "tens of milliseconds" are used exactly as cited in delivery
  plan §3.11.6 F5 / Done when in FR/SC prose; suite fixture parameters (Clarification Q3 /
  2026-08-05) encode N=20, production target 100 ms, and Miniflare ceiling 2000 ms without
  rewriting those FR/SC phrases.
- D1 write headroom and Durable Object throughput per installation have no numeric
  pass/fail ceilings named in §13.5 or §13.6; measurement satisfies Done when.
- The §13.6.2 pre-flight estimator remains C2's contract; F5 does not re-open it.
- The platform does not ship until the whole product does (DP-1); "independently
  testable" means provable by the automated load cases above, not demonstrable to a
  clinic user (DP-3).
- Nothing from §9.14 is pulled forward because it looks prudent (R-20).
