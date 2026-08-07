# Feature Specification: Live client invoke on the first AI feature surface (I3)

**Feature Branch**: `ai/054-i3-live-client-invoke`

**Created**: 2026-08-07

**Status**: Draft

**Input**: I3 — "Live client invoke on the first AI feature surface"

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable. This slice composes the Flutter AI host onto the live Worker request and
> discovery paths. The Cloudflare AI Gateway remains the additive, non-primary component
> acknowledged in §14 of `docs/architecture/ai-platform/01-ai-platform.md`: no domain
> logic, no business data, and no write path into Supabase. AI stays optional (A11).

## Slice Contract

### Implements

`§4.1, §5.5, §5.4, §6.4, A11` (copied verbatim from the slice's `Canonical` cell in
§3.10 of `03-ai-platform-delivery-plan.md`).

### Freezes

**None.** Band I freezes no new contract (Delivery Plan §3.10; §2.3). I3 composes
contracts already frozen by E2, E3, E4, I1, and I2 onto the production Flutter `/ai`
visit-summary (or equivalent) host. Later slices may not rewrite those consumed
contracts through this slice.

What this slice *does* establish for the first time is **production client wiring only**:
the E4 host composes E2's production AAT mint and HTTPS submit adapters, resolves
required context keys through E3, and runs a live invoke against the Worker path I1
wired and the discovery HTTP wire I2 froze. That is composition, not a new SDK, surface,
taxonomy, or discovery contract.

### Consumes

Contracts frozen by the slices in I3's `Needs` (`E2`, `E3`, `E4`, `I1`, `I2`). Changing
any of these is out of scope by definition:

- **From E2 — AI Client SDK** (§4.1 AI Client SDK; §5.5; §5.4): transport-only AAT
  acquire and cache, submit with a stable client-generated idempotency key, SSE
  consumption to exactly one terminal event, cancel by stream close, last
  request-reference retention, transport-only retries, and no auto-retry after a
  terminal platform error (except the single `unauthenticated` re-mint). I3 wires
  production mint and HTTPS submit ports into that SDK; it does not reinterpret
  transport, idempotency, SSE framing, or remint rules.
- **From E3 — Context Resolver registry** (§4.1 Context Resolver; §5.2): generic
  key-list resolution under caller RLS, screen-scoped cache, ordinary context read
  RPCs. I3 resolves required keys through that registry for the live host; it does not
  branch the Resolver on capability id, add per-feature glue resolvers outside the
  registry, or rewrite the client contract test.
- **From E4 — First AI feature surface and degraded mode** (§4.1 AI Feature Surfaces;
  §6.4; A11; §5.4): provisional/draft rendering, no commit affordance until
  `completed`, request-reference display on failure, AI availability flag gating,
  and distinct degraded states (non-enrolled / unreachable / quota). I3 turns the E4
  hub's idle / unconfigured mint-submit stubs into live composition; it does not
  redefine surface UX contracts, provisional rules, or degraded-mode states.
- **From I1 — Worker request orchestrator** (`POST /v1/requests`): live `preAccept` +
  `eventSource` composition so submit runs the §6.1 sequence with deferred `accepted`,
  taxonomy HTTP on pre-accept failure, and exactly one terminal SSE event. I3 is a
  client of that live path; it does not rewrite `worker.ts` orchestration, pipeline
  modules, or A6 framing.
- **From I2 — Discovery HTTP and production config readers** (`GET /v1/capabilities`;
  `specs/053-discovery-http-config-readers/contracts/discovery-http.md`): Bearer AAT
  auth, etag/`If-None-Match` revalidation, discovery body shape, and auth-failure
  mapping (taxonomy error body, **no** discovery body, **no** journal row;
  `installation_suspended` when the verifier returns that code for a suspended
  installation). I3 may consume discovery to drive required context keys for the
  Resolver (§5.5); it does **not** reimplement discovery filtering, etag computation,
  or grant/lifecycle overlay rules (those remain C1 via I2).

### Open decisions relied on

- **Open Decision 1** (recommended default): the first capability is one
  non-clinical-record capability (visit-summary draft for review) with output mode
  `prose` and acceptance mode `advisory_display`. Assumed because I3 composes the E4
  first surface onto the live path; I3 does not choose a different first capability.
- **Open Decision 8** (recommended default): AI entitlement mirrors into Supabase
  minimally as an AI-enabled flag so the client can hide affordances offline — not
  quota state. Assumed because live invoke still gates on E4's availability flag
  before any Worker probe.

No other §15 decision is assumed. Live `context_required` self-heal remains I4/J2.
Entitle-and-grant operator activation remains I4. Usage-summary / billing UI remains
Band G.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Live client invoke on the first AI feature surface (Priority: P1)

As clinic staff on the Flutter desktop app, I want the `/ai` visit-summary (or
equivalent) host to compose production AAT mint and HTTPS submit adapters from E2,
resolve required context keys through E3, submit with a stable idempotency key, consume
the SSE stream to a terminal event, render a provisional draft with no commit
affordance until `completed`, and display the request reference on every failure — while
non-enrolled installations still hide affordances and make no network probe, and
platform unreachability remains a normal degraded state — so that CP3 is reified on the
composed E4 host against the live Worker rather than only in injectable harnesses
(§4.1; §5.5; §5.4; §6.4; A11; Delivery Plan §3.10 / §5 CP3).

**Why this priority**: I3 has `Needs: E2, E3, E4, I1, I2` (Delivery Plan §3.10). The SDK,
Resolver, and first surface must already exist; the Worker must already run live submit
(I1) and discovery HTTP (I2). Without this composition, E4 leaves invoke idle with
unconfigured mint/submit stubs and CP3 cannot falsify the end-to-end thread on the real
Flutter host (DP-7).

**Independent Test**: The Flutter `/ai` visit-summary (or equivalent) host composes
production AAT mint and HTTPS submit adapters from E2, resolves required context keys
through E3, submits with a stable idempotency key, consumes the SSE stream to a terminal
event, renders provisional draft with no commit affordance until `completed`, and
displays the request reference on every failure; non-enrolled installations still hide
affordances and make no network probe; platform unreachability remains a normal degraded
state (Delivery Plan §3.10 Done when). Provable by Flutter widget and integration tests
(DP-3; §3.12.9 I3).

**Acceptance Scenarios**:

1. **Given** an enrolled installation with a reachable platform and the production mint
   and HTTPS submit adapters composed on the hub, **When** the visit-summary host invokes
   the first capability, **Then** it mints an AAT, resolves required context keys through
   E3, submits over HTTPS to the Worker with a stable idempotency key, consumes the SSE
   stream to a terminal event, and renders provisional draft content while the stream is
   in flight (§4.1; §5.5; §6.4; Delivery Plan §3.12.9 I3 *Live host*).
2. **Given** an in-flight live invoke that has not yet received terminal `completed`,
   **When** the tester inspects commit/save/accept controls, **Then** no commit
   affordance is enabled (§6.4 `prose` Client rule and invariant 2; Delivery Plan
   §3.12.9 I3).
3. **Given** a live invoke that ends in a failure path carrying a request reference,
   **When** the surface presents the failure, **Then** the request reference is displayed
   (§5.4; A13 via §5.4; Delivery Plan §3.12.9 I3 *Live host*).
4. **Given** an installation whose AI availability flag indicates not enrolled, **When**
   the feature host builds, **Then** no AI affordances are shown and a spy proves no
   Worker / AI-platform network probe is made (§4.2 via E4; A11; Delivery Plan §3.12.9
   I3 *Degraded*).
5. **Given** an enrolled installation whose platform is unreachable, **When** the host
   would otherwise offer AI, **Then** it renders the normal-state unreachable banner (not
   an error dialog) and clinical non-AI workflows remain usable (A11; Delivery Plan
   §3.12.9 I3 *Degraded*).
6. **Given** the production `/ai` hub composition used outside widget-test harness
   overrides, **When** a spy inspects the composed mint and submit ports, **Then** those
   ports are the production AAT mint and HTTPS submit adapters from E2 — not the
   unconfigured stubs or test fakes left wired by default (Delivery Plan §3.12.9 I3
   *Spy*; §4.1).
7. **Given** a terminal `completed` event on the live path, **When** the surface settles
   on the answer, **Then** it uses the validated terminal payload and does not assemble
   the final result from chunks (§6.4 invariant 1; Delivery Plan §6.4).
8. **Given** the host obtains required context keys via capability discovery over
   `GET /v1/capabilities`, **When** discovery auth fails, **Then** the client observes a
   taxonomy error body with no discovery manifests payload (and does not treat that
   failure as a journaled request); a suspended installation may surface
   `installation_suspended` per I2's frozen wire (Consumes I2
   `contracts/discovery-http.md`; §5.4; §5.5).

### Test plan

The minimum test set is the I3 row of Delivery Plan §3.12.9 (layer: *Flutter widget +
integration*). Tests join CI permanently (Delivery Plan §3.11). Named tests use that
Flutter widget + integration layer (§13.5 client / widget coverage as applicable).

| # | Named test | Layer | Asserts |
| --- | --- | --- | --- |
| T1 | `live_host_mints_aat_resolves_context_submits_https` | Flutter widget + integration | Enrolled + reachable host mints AAT, resolves required keys through E3, submits over HTTPS with a stable idempotency key (§3.12.9 I3; §4.1; §5.5) |
| T2 | `live_host_consumes_sse_to_terminal_renders_provisional` | Flutter widget + integration | SSE consumed to a terminal event; provisional draft rendered while in flight (§3.12.9 I3; §5.5; §6.4) |
| T3 | `live_host_no_commit_control_before_completed` | Flutter widget + integration | No commit/save/accept affordance enabled before terminal `completed` (§3.12.9 I3; §6.4) |
| T4 | `live_host_failure_displays_request_reference` | Flutter widget + integration | Failure presentation displays the request reference (§3.12.9 I3; §5.4) |
| T5 | `live_host_uses_terminal_payload_not_chunk_assembly` | Flutter widget + integration | Final answer equals validated terminal payload, not client-assembled deltas (§6.4 invariant 1; Delivery Plan §6.4) |
| T6 | `degraded_non_enrolled_hides_affordances_no_worker_probe` | Flutter widget + integration (spy) | Non-enrolled: no AI affordances; zero Worker / platform network probes (§3.12.9 I3; A11; §4.2 via E4) |
| T7 | `degraded_unreachable_renders_normal_state_banner` | Flutter widget + integration | Unreachable platform → normal-state banner, not an error dialog (A11; §3.12.9 I3) |
| T8 | `spy_production_mint_and_submit_ports_composed_on_hub` | Flutter widget + integration (spy) | Hub default composition wires production AAT mint and HTTPS submit ports — not unconfigured stubs or test fakes (§3.12.9 I3 *Spy*; §4.1) |
| T9 | `live_idempotency_key_stable_for_single_user_action` | Flutter widget + integration | The idempotency key submitted for one user action remains stable across transport retries of that action (Consumes E2; §5.5; §4.1) |
| T10 | `discovery_auth_failure_taxonomy_no_manifest_body` | Flutter widget + integration | Discovery auth failure → taxonomy error, no `{ manifests: … }` body; suspended install may yield `installation_suspended` (Consumes I2 discovery-http contract; §5.4; §5.5) |
| T11 | `live_host_contains_no_prompt_provider_or_model_identifiers` | Flutter widget + integration | Live-host composition sources pass the E1 architecture guard (R-12; Delivery Plan §6.4; §4.1) |

Coverage (Delivery Plan §3.11): happy path of every requirement (T1–T3, T5, T9);
failure/reference branch (T4); degraded branches named by Done when / A11 (T6–T7);
production-port spy (T8); discovery auth-failure boundary when discovery is consumed
(T10); inherited Delivery Plan §6.4 / R-12 prohibitions (T5, T11). This slice emits no
new §5.4 taxonomy codes; it surfaces consumed codes' client behaviours and consumes I2's
auth-failure mapping without reimplementing discovery filtering.

### Edge Cases

- **Commit control before `completed`**: must not exist for `prose` on the live host
  (§6.4; T3).
- **Chunk assembly**: forbidden; terminal payload is authoritative (§6.4 invariant 1;
  T5).
- **Non-enrolled**: hide all AI affordances; zero Worker probes (§4.2 via E4; A11; T6).
- **Platform unreachable / offline**: normal first-class banner state, not an error
  dialog; does not block clinical workflows (A11; T7).
- **Failure with request reference**: every failure presentation shows the reference
  (§5.4; T4).
- **Unconfigured / test-fake ports left as hub defaults**: forbidden; production mint and
  submit adapters must be the composed defaults outside harness overrides (§3.12.9 I3
  *Spy*; T8).
- **Discovery auth failure**: taxonomy error body only; no discovery manifests payload;
  no journal row on that surface (Consumes I2; T10).
- **`installation_suspended` via discovery or submit**: hide AI features / instruct admin
  per §5.4 Client behaviour (Consumes E4 / I2; §5.4).
- **Idempotency key**: stable for one user action across transport retries; not regenerated
  per retry (Consumes E2; T9).
- **`context_required` self-healing resubmit**: I4 / J2; out of scope. I3 may display the
  failure and reference; it does not implement refresh-and-resubmit.
- **Operator entitle-and-grant / pending enrollment activation**: I4; out of scope.
- **Conversational transcript / fourth terminal kind**: H-band; out of scope.
- **Reimplementing discovery filtering or etag rules**: forbidden (Consumes I2 / C1).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Flutter `/ai` visit-summary (or equivalent) host MUST compose the
  production AAT mint and HTTPS submit adapters from the E2 AI Client SDK so a live
  invoke acquires an AAT and submits over HTTPS to the Worker. `(§4.1; Delivery Plan
  §3.10 Done when)`
- **FR-002**: The live host MUST resolve required context keys through the E3 Context
  Resolver registry (generic key-list API; no capability-id branching) before submit.
  `(§4.1; Delivery Plan §3.10 Done when)`
- **FR-003**: Every live submission MUST carry a stable client-generated idempotency key
  for the user action (unchanged across transport retries of that action). `(§4.1; §5.5;
  Consumes E2; Delivery Plan §3.10 Done when)`
- **FR-004**: The live host MUST consume the SSE stream through exactly one terminal
  event (`completed`, `failed`, or `cancelled` for the capabilities this surface
  invokes). `(§5.5; Consumes E2)`
- **FR-005**: For the first capability's `prose` mode on the live path, the surface MUST
  render provisional draft content during the stream and MUST NOT enable a commit
  affordance until terminal `completed`. `(§6.4; Delivery Plan §3.10 Done when)`
- **FR-006**: The validated terminal payload MUST be treated as authoritative and
  self-contained; the live host MUST NEVER assemble the final result from stream chunks.
  `(§6.4; Delivery Plan §6.4)`
- **FR-007**: Every failure presentation on the live host MUST display the request
  reference. `(§5.4; Delivery Plan §3.10 Done when)`
- **FR-008**: When the installation is not AI-enrolled, the live host MUST hide AI
  affordances entirely and MUST NOT probe the Worker / AI platform network. `(A11; §4.2
  via E4; Delivery Plan §3.10 Done when; §3.12.9 I3)`
- **FR-009**: Platform unreachability MUST remain a normal degraded state (banner), not
  an error dialog; no AI failure MAY block a clinical workflow. `(A11; Delivery Plan
  §3.10 Done when; §3.12.9 I3)`
- **FR-010**: Outside test-harness overrides, the hub's composed mint and submit ports
  MUST be the production E2 adapters — not unconfigured stubs or test fakes left wired
  by default. `(§4.1; Delivery Plan §3.12.9 I3 *Spy*)`
- **FR-011**: Clients MUST branch on §5.4 taxonomy codes (never raw provider errors) for
  outcomes the live host presents. `(§5.4)`
- **FR-012**: When the live host consumes capability discovery over `GET /v1/capabilities`,
  it MUST use I2's frozen wire (Bearer AAT, etag revalidation) and MUST NOT reimplement
  discovery filtering; auth failures MUST surface as taxonomy errors with no discovery
  manifests body (and may include `installation_suspended` for a suspended installation).
  `(§5.5; Consumes I2 discovery-http contract; §5.4)`
- **FR-013**: The live-host composition MUST contain no prompt text, provider name, or
  model identifier, and MUST pass the E1 client architecture guard. `(§4.1; R-12;
  Delivery Plan §6.4)`
- **FR-014**: The first capability exercised on the live path MUST remain the
  non-clinical-record `prose` / `advisory_display` capability assumed by Open Decision 1
  / E4; I3 MUST NOT introduce a different first capability or clinical auto-commit.
  `(Open Decision 1; §6.4; A5)`

### Key Entities

Not applicable — this slice defines no D1 entities or new contract types. It composes
existing E2 ports, E3 resolver keys, E4 surface/degraded-mode UI, and I1/I2 live Worker
wires.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Live invoke remains additive for small-to-mid multi-branch clinics:
  non-enrolled and unreachable installations continue clinical work without AI (A11;
  constitution V). No hospital-scale or always-online assumption is introduced.

- **Layer Placement**: This slice touches **`frontend/`** (Flutter `/ai` host composition
  of production E2 mint/submit adapters, E3 key resolution, E4 surface/degraded mode on
  the live path). It consumes the already-wired **`ai-platform/`** Worker submit (I1) and
  discovery HTTP (I2) paths without rewriting them. It does not add domain logic to the
  gateway. Where the client calls the gateway, it respects the §14 acknowledgement that
  the gateway is a non-primary, additive component (no domain logic, no business data, no
  write path into Supabase): Flutter still holds no prompts, providers, or AI business
  rules (§4.1; §14).

- **Data Integrity & Security**: Context resolution remains under caller RLS via E3.
  Provisional AI content never enters clinical records until a later acceptance path
  (F2 / Open Decision 1 `advisory_display`). AAT mint stays on the clinic issuer path
  consumed by E2; I3 does not weaken token or tenant isolation.

- **Failure Handling**: Non-enrolled → hide affordances, no probe. Unreachable → normal
  degraded banner. Taxonomy failures → show request reference; branch on §5.4 codes.
  Discovery auth failures → taxonomy body only (Consumes I2). Clinical workflows remain
  usable when AI cannot (A11; constitution V).

## Out of Scope

Neighbouring / later slices this one must not pull forward:

- **I4** — Operator entitle-and-grant activation and live `context_required` self-heal on
  the submit path.
- **J2** — `context_required` refresh-and-resubmit loop (hosted by I4 on the live path).
- **F2** — Clinical acceptance recording RPC / human-accept write path.
- **Band G** — Plan catalogue, billing period close, usage-summary UI.
- **H1 / H3** — Conversational manifests, transcript store, chat surface.
- **Reimplementing I2 discovery filtering**, etag computation, or grant/lifecycle overlay
  (Consumes I2 / C1).
- **Rewriting I1** Worker `preAccept` / `eventSource` orchestration or A6 framing.
- **Rewriting E2 / E3 / E4** SDK, Resolver, or surface contracts (composition only).
- Additional AI feature surfaces beyond the first capability named by Open Decision 1.

Prohibitions from delivery plan §6.4 (inherited; must never be done here):

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No second Quota Durable Object round trip and no second R2 object per request (§7.5,
  §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content
  (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Automated Flutter widget/integration tests prove the live host mints an
  AAT, resolves context through E3, submits over HTTPS with a stable idempotency key, and
  consumes SSE to a terminal event while rendering provisional draft (T1–T2, T9) —
  matching Delivery Plan §3.10 Done when.
- **SC-002**: No commit affordance is enabled before `completed`, and the final answer
  equals the validated terminal payload rather than chunk assembly (T3, T5).
- **SC-003**: Every exercised live failure path displays the request reference (T4).
- **SC-004**: Non-enrolled installations show no AI affordances and make no Worker probe
  (T6); unreachable platform renders the normal-state banner, not an error dialog (T7).
- **SC-005**: A spy proves the hub composes production mint and submit ports by default
  (T8).
- **SC-006**: When discovery is consumed, auth failure yields a taxonomy error with no
  manifests body; suspended install may surface `installation_suspended` (T10).
- **SC-007**: Live-host composition sources pass the E1 architecture guard (T11).

## Assumptions

- E2, E3, E4, I1, and I2 are complete and their frozen contracts are available to
  consume; E1's architecture guard remains a permanent CI gate on `frontend/` (DP-6).
- I1 is included on this feature branch (merged from `ai/052-i1-worker-request-orchestrator`)
  even though it is not yet on `ai/master`, so the live `POST /v1/requests` path remains
  available for composition.
- I2 is already on `ai/master` (merged at `857c7446`); its
  `contracts/discovery-http.md` is consumed as written.
- Open Decision 1 and Open Decision 8 recommended defaults continue to apply (first
  `prose` / `advisory_display` capability; minimal AI availability flag).
- Flutter widget/integration tests may use spies for network and ports where needed;
  proving production ports are composed is itself a spy assertion (DP-3; §3.12.9 I3).
- CP3 is the review checkpoint after I1 + I3; this slice's Done when is independently
  provable by the I3 Flutter suite against the composed host and live Worker contracts.
- Primary operators remain clinic staff on Windows desktop; AI remains optional and
  additive relative to clinical workflows (A11; constitution V).
- Pending enrollment entitlement activation required for a fully admitted real-provider
  request remains I4; the fake-adapter / test composition path may still prove the client
  live-invoke thread for CP3 as Delivery Plan §5 describes.
