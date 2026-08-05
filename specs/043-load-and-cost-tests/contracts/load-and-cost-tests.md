# Load and cost tests (F5)

Frozen contracts for the §13.5 **load and cost test layer**, the under-load
§13.6 / §13.6.1 **metered-footprint assertions** (exactly one R2 Class A
operation and exactly two Durable Object requests per request), and the
**CP5 measurement gate** (guard p95 under concurrency, D1 write headroom, and
Durable Object throughput per installation are measured). Later checkpoints
and review practice **consume** this artifact — they must not redefine what
the load layer measures, when it runs relative to checkpoints, or the
one-R2 / two-DO under-load proof.

**Source of truth in code (this slice):**
`ai-platform/src/pipeline/index.ts` (production `runGuard` / `settleHappyPath`),
`ai-platform/test/load/` (binding spies, measurement report, happy-path driver,
Vitest entry), proven by `load-and-cost.test.ts`, invoked before each delivery
checkpoint via the dedicated workers-pool `test:load` script and the
`ai-platform-tests` CI job.

**Traces to:** spec Freezes (load and cost test layer; under-load
metered-footprint assertion; measurement gate for CP5); FR-001–FR-010;
architecture §13.5 Load and cost tests, §13.6, §13.6.1; delivery plan §3.7
row F5, §3.11.6 row F5, §5 CP5.

**Does not freeze:** the one-envelope pipeline contract (C3) or the two-trip
admission/credit pipeline contract (B4). F5 freezes the **under-load proof**
of those design-shape budgets, not the pipeline modules themselves.

---

## 1. Overview

F5 freezes automated load and cost tests that run before each delivery
checkpoint (§13.5). Under load at target concurrency the guard's p95 latency
stays within tens of milliseconds; under load each request performs exactly
one R2 Class A operation and exactly two Durable Object requests; and D1 write
headroom and Durable Object throughput per installation are **measured** so
checkpoint **CP5** can be answered honestly (delivery plan §5 CP5; §13.6.1).

This suite is **workers-pool Miniflare tooling** under `ai-platform/test/load/`.
It is not a Worker pipeline stage, emits **no** §5.4 taxonomy codes, and adds
**no** `src/load/` runtime module. It **does** call the thin production composer
at `ai-platform/src/pipeline/` so spies observe the same §6.1 composition a
future Worker orchestrator will use. Completing F5's measured and asserted
outcomes **is** what satisfies CP5 (FR-009).

---

## 2. Load and cost test layer (§13.5)

### 2.1 Placement

| Element | Contract |
| --- | --- |
| Root | `ai-platform/test/load/` |
| Runtime module | Thin production composer `ai-platform/src/pipeline/` (`runGuard`, `settleHappyPath`) — **no** `ai-platform/src/load/` |
| Runtime | Workers-pool Miniflare with real D1, R2, and Quota DO bindings (`vitest.workers.config.ts` / Wrangler development env) |
| Metering | Counting spies on the D1 / R2 / `DO` (Quota DO) bindings — D1 INSERT into `ai_request` at `run`/`batch`; R2 Class A put/list/multipart; per-request maxima via AsyncLocalStorage tagging; prototype-preserving D1 spy — not invented secondary meters |
| Request path | Full happy path under load with a **fake** provider via production `src/pipeline` (`runGuard` stages 1–10 + `settleHappyPath`: FakeAdapter + credit + one R2 envelope); no warm-up / discarded admissions; no live provider egress |
| Concurrency | Bounded worker pool of size `Math.min(N=20, CONCURRENCY_LIMIT=16)` on **one shared installation**; `concurrency` is the observed in-flight peak |
| Consumes | D7 second-provider adapter / fixture suite / policy registration — unchanged; F5 measures the post-D7 platform and does not rewrite those contracts |

### 2.2 When the layer runs

| Rule | Contract |
| --- | --- |
| Timing | The load and cost suite **MUST** run **before each delivery checkpoint** (§13.5 How) |
| Checkpoint gate | Completing this suite's measured and asserted outcomes satisfies **CP5** (delivery plan §5 CP5; §3.7). The suite does **not** redefine other checkpoints' gates |
| Invocation | Dedicated npm script `test:load` under `ai-platform/` runs the workers-pool Vitest entry for this suite — that script is the checkpoint gate |
| Permanent join | The suite joins CI permanently (delivery plan §3.10) via the workers-pool config include **and** the `ai-platform-tests` CI job running `npm run test:load` |

### 2.3 What the layer measures and asserts

| Concern | Contract |
| --- | --- |
| Guard latency | p95 of the full production `runGuard` path — architecture §6.1 stages 1–10 — under concurrency (not admission-only) |
| R2 Class A | Exactly **one** Class A operation (one payload envelope) per request under load — average **and** max (§13.6; §13.6.1) |
| Durable Object requests | Exactly **two** DO requests per request under load — one admission in the guard, one credit at settle — average **and** max (§13.6; §13.6.1) |
| D1 write headroom | **Measured** under load — one hot-path `ai_request` INSERT per request, detail afterwards; no invented numeric pass ceiling (§13.6 D1 writes row) |
| DO throughput per installation | **Measured** under load as pinned-installation DO fetches / wall_clock_seconds — no invented numeric pass ceiling (§13.5) |

### 2.4 What later checkpoints must not redefine

Later checkpoints and review practice **MUST** bind to this layer for:

- What the load and cost suite measures (guard p95, one R2, two DO, D1 headroom, DO throughput)
- When it runs relative to delivery checkpoints (`test:load` before each checkpoint; CP5 satisfied by completing F5)
- The under-load metered-footprint proof (section 3)
- How measurement is reported without inventing ceilings (section 4)

---

## 3. Under-load metered-footprint assertion (§13.6 / §13.6.1)

Two Cloudflare cost drivers are the binding metered constraints, consumed by
**design shape** rather than data volume (§13.6.1):

| Driver | Under-load assertion |
| --- | --- |
| R2 Class A operations | Each request under load performs **exactly one** R2 Class A operation — one payload envelope per request |
| Durable Object requests | Each request under load performs **exactly two** Durable Object requests — one admission call in the guard, one credit call at settle |

Reinforcing prohibitions (delivery plan §6.4 / §7.5):

- No second R2 object per request under load
- No additional Quota DO round trip beyond the two named above

This freezes the **load-time proof** of the design-shape budget. It does **not**
rewrite C3's one-envelope layout or B4's admission/credit RPCs.

---

## 4. Measurement report and CP5 gate

### 4.1 Structured in-test measurement report

T4 / T5 prove D1 write headroom and DO throughput per installation were
**measured** by emitting a structured in-test measurement report with
**finite** numeric values and **no** pass/fail numeric ceilings for those two
quantities.

| Field | Meaning | Pass rule |
| --- | --- | --- |
| `guard_p95_ms` | Guard latency p95 (ms) of full `runGuard` (stages 1–10) under the concurrency fixture | Finite; within the Miniflare suite ceiling in §4.2 (production design target retained separately) |
| `r2_class_a_ops_per_request` | Class A ops counted per request under load (average) | Must equal `1` |
| `r2_class_a_ops_max_per_request` | Max Class A ops on any single request | Must equal `1` |
| `durable_object_requests_per_request` | DO requests counted per request under load (average) | Must equal `2` |
| `durable_object_requests_max_per_request` | Max DO fetches on any single request | Must equal `2` |
| `wall_clock_ms` | Wall-clock duration of the concurrent measured window | Finite; used with latency sum to prove overlap |
| `d1_hot_path_writes_per_request` | Hot-path D1 writes observed per request (headroom evidence) | Must be a finite number; **no** ceiling asserted here |
| `d1_hot_path_writes_max_per_request` | Max hot-path D1 INSERTs on any single request | Must equal `1` |
| `do_throughput_per_installation` | Pinned-installation DO fetches / wall_clock_seconds (time-dimensioned) | Finite; **no** ceiling |
| `concurrency` | Observed in-flight peak during the measured window (bounded pool size) | Equals `Math.min(N=20, CONCURRENCY_LIMIT=16)` |
| `request_count` | Number of happy-path requests exercised under load | Finite positive integer (`N=20`) |

The report is an in-test artifact (asserted by the suite). It is not a second
metrics store and not a runtime Worker surface.

### 4.2 Suite fixture parameters (encoding of architecture phrases)

Architecture and delivery-plan prose use **"target concurrency"** and
**"tens of milliseconds"** without inventing substitute integers in FR/SC
prose. This suite freezes the following **fixture parameters** so checkpoints
do not redefine them:

| Phrase | Suite fixture |
| --- | --- |
| Target concurrency | `N = 20` happy-path requests on **one shared installation**; in-flight pool size `Math.min(20, CONCURRENCY_LIMIT=16)` |
| Guard p95 within tens of milliseconds (production design target) | `GUARD_P95_PRODUCTION_TARGET_MS = 100` — retained as the production-oriented encoding of “tens of milliseconds” |
| Guard p95 workers-pool Miniflare ceiling | `GUARD_P95_CEILING_MS = 2000` — a single sequential Miniflare `runGuard` is already ~300–400 ms; T1 asserts finite p95 under this ceiling plus wall-clock overlap proof |

These parameters are suite fixture bindings for T1 / the CP5 gate. They do
not rewrite FR-003 / SC-001 prose. The production target and the Miniflare
ceiling are both frozen so checkpoints do not redefine either.

### 4.3 CP5 satisfaction

Checkpoint **CP5** ("Is the platform operationally honest?") is satisfied when
this suite's measured and asserted outcomes pass (FR-009; delivery plan §5
CP5; §3.7 Done when):

1. Guard p95 of full `runGuard` (stages 1–10) under the concurrency fixture is finite
   within the Miniflare suite ceiling, with production design target retained (T1; §4.2)
2. Exactly one R2 Class A operation per request under load (T2; T6)
3. Exactly two Durable Object requests per request under load (T3; T7)
4. D1 write headroom measured (T4)
5. Durable Object throughput per installation measured (T5)

A failing load or cost assertion fails the suite / checkpoint gate. It does
**not** invent a new §5.4 request error code.

---

## 5. Inherited prohibitions

| Prohibition | Contract |
| --- | --- |
| No per-request server-side state | Running the load/cost suite introduces no per-request server-side state of any kind (§4.4, §9.7) |
| No Flutter prompt/provider/model | The suite introduces no prompt text, provider name, or model identifier into Flutter client code (R-12) |
| No §9.14 mechanism | Nothing from §9.14 is added because it looks prudent (R-20) |
| No D7 rewrite | The suite does not rewrite D7's second-provider adapter, fixture suite, or routing-policy registration (Consumes D7) |

---

## 6. Out of this contract

- C2 byte-based pre-flight estimator (§13.6.2) — remains C2
- Token-spend product surface beyond the Cloudflare metered-footprint load gate
- F1–F4 sibling hardening slices
- Live provider egress under load (happy path uses the fake provider)
