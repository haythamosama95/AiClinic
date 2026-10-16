# Feature Specification: First AI feature surface and degraded mode

**Feature Branch**: `ai/038-e4-first-ai-feature-surface`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `E4` — "First AI feature surface and degraded mode" (delivery plan §3.6, band E).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.6, row E4):

> §4.1, §6.4, §13.2, §4.2, §5.4, A11

### Freezes

Contracts this slice establishes for the first time:

- The **AI Feature Surfaces** Flutter component named in §4.1: per-feature UI for draft
  rendering, provisional/draft styling, explicit accept/discard, degraded-mode states, and
  request-reference display on failure — and nothing else from the §4.1 client table
  (§4.1 AI Feature Surfaces row; delivery plan §3.6 Done when).
- The **provisional-content client rules** for the first capability's `prose` output mode:
  display live; enable save/accept only on `completed`; provisional content is never
  persisted, never exported, and never entered into a clinical record; no commit
  affordance until terminal success (§6.4 `prose` Client rule and invariant 2; §4.1 Must
  not; delivery plan §3.6 Done when; §3.11.5 E4).
- The **terminal-payload authority rule on the surface**: the validated terminal payload
  is authoritative and self-contained; the surface never assembles the final result from
  chunks (§6.4 invariant 1; delivery plan §6.4).
- The **request-reference display** requirement on every failure, using the short
  human-readable reference the support workflow depends on (§13.2; A13 via §5.4 "Every
  error response carries the request reference"; delivery plan §3.6 Done when; §3.11.5
  E4).
- The **AI availability flag** clinic-side store: whether this installation is AI-enrolled
  and the platform base URL, so the client can hide AI affordances entirely for non-AI
  clinics without probing the network (§4.2 AI availability flag; Open Decision 8
  recommended default; delivery plan §3.6 Done when; §3.11.5 E4).
- The **defined degraded mode** as first-class UI: AI unavailable, quota exhausted, and
  offline/unreachable are distinct states; no AI failure may block a clinical workflow;
  platform unreachability renders as a normal state rather than an error dialog (A11;
  delivery plan §3.6 Done when; §3.11.5 E4).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (E2, E3). Changing any is out of scope by
definition:

- **E2 — AI Client SDK** (§4.1 AI Client SDK; §5.5; §5.4): transport-only AAT acquire and
  cache, submit with idempotency key, SSE consumption to one terminal event, cancel by
  stream close, last request-reference retention, no auto-retry after terminal platform
  errors. E4 renders and degrades on top of that SDK; it does not reinterpret transport,
  idempotency, SSE framing, or remint rules.
- **E3 — Context Resolver registry, first context RPC, and client contract test** (§4.1
  Context Resolver; §5.2; §4.2 Context provider RPCs; §13.5): generic key-list resolution
  under caller RLS, screen-scoped cache, first ordinary context read RPC. E4 obtains
  context through that registry for the first surface; it does not branch the Resolver on
  capability id, add per-feature glue resolvers outside the registry, or rewrite the
  contract test.
- **A2 / A6 via E2 — Error taxonomy and request reference** (§5.4; §13.2): closed taxonomy
  codes, client-behaviour column, request reference on every error. E4 displays references
  and applies named client behaviours; it adds no taxonomy codes and changes none.
- **§6.4 streaming contract via the SDK / prior band D surfaces the client already
  consumes**: `accepted`, content/heartbeat events, and exactly one terminal
  `completed` / `failed` / `cancelled`. E4 does not redefine stream event kinds or the
  one-terminal-event rule.

### Open decisions relied on

- **Open Decision 1** (recommended default): the first capability is one
  non-clinical-record capability. Per delivery plan §7, its output mode is `prose` and its
  acceptance mode is `advisory_display`, so F2 is not a prerequisite for CP3.
- **Open Decision 8** (recommended default): AI entitlement mirrors into Supabase
  minimally as an AI-enabled flag so the client can hide affordances offline — not quota
  state. Aligns with §4.2 AI availability flag (enrolled + platform base URL).

## Clarifications

### Session 2026-08-02

- Q: Where should AI Feature Surfaces code live under `frontend/`? → A: `frontend/lib/features/ai/` for surfaces / degraded-mode UI; import SDK + Resolver from `core/ai` `[implementation choice — no §citation]`
- Q: How should the first AI feature surface be hosted for CP3 and the widget suite? → A: Standalone host shell/route under `features/ai/` for tests + CP3 entry; not embedded in a production clinical screen in this slice. The route builds `AiFeatureHostPage` when `AiFeatureHostDependencies` are passed via GoRouter `extra` (CP3 composition supplies mint/submit ports); without extra it shows a composition-required message rather than a placeholder string claiming the host is registered. `[implementation choice — no §citation]`
- Q: How should T1 (`surface_provisional_content_visually_distinct`) assert that live/provisional prose is visually distinct as draft? → A: Stable test `Key` / Semantics marker + draft styling token asserted by the widget test `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - First AI feature surface and degraded mode (Priority: P1)

As clinic staff on the Flutter desktop app, I want a first AI feature surface that shows
streaming prose as a visibly provisional draft with no commit control until terminal
success, lets me accept or discard only after that success, shows the request reference on
every failure, and never persists or exports provisional content — and I want degraded
mode so a non-enrolled installation hides AI affordances with no network probe, an
unreachable platform appears as a normal state rather than an error dialog, and enrolled
reachable installations show the affordances — so AI stays additive and clinical work
continues when AI cannot (§4.1; §6.4; §13.2; §4.2; A11).

**Why this priority**: E4 has `Needs: E2, E3` (delivery plan §3.6). The SDK and Context
Resolver must already exist so the surface submits and resolves context without inventing
transport or per-feature glue. Band E places this last so the first user-visible AI UI
is constrained by those frozen client contracts; together with D4 it is the CP3
falsification thread (delivery plan §3.6 Useful to know; §5 CP3).

**Independent Test**: Provisional content is visibly draft with no commit affordance until
terminal success, the request reference is displayed on every failure, and provisional
content is never persisted or exported; a non-enrolled installation hides AI affordances
entirely without probing the network, and platform unreachability renders as a normal
state rather than an error dialog (delivery plan §3.6 Done when). Provable by Flutter
widget tests with spies (DP-3; §3.11.5 E4).

**Acceptance Scenarios**:

1. **Given** an in-flight `prose` stream emitting `text_delta` (and optional heartbeats)
   before any terminal event, **When** the surface renders the live content, **Then** that
   content is visually distinct as provisional/draft and no commit/save/accept control is
   present (§6.4 `prose` Client rule; §4.1 provisional/draft styling; delivery plan
   §3.11.5 E4 "provisional content is visually distinct"; "no commit control exists before
   `completed`").
2. **Given** a stream that has not yet terminated as `completed`, **When** the tester
   inspects the surface for commit affordances, **Then** no commit/save/accept control
   exists (§6.4 invariant 2; delivery plan §3.11.5 E4).
3. **Given** a terminal `completed` event carrying the validated prose payload, **When**
   the user accepts, **Then** accept behaves for `advisory_display` (acknowledges the
   validated terminal payload without writing to a clinical record via the F2 acceptance
   RPC) and the surface does not treat pre-terminal provisional text as the accepted
   answer (§4.1 explicit accept/discard; §6.4 invariant 1–2; Open Decision 1 /
   `advisory_display`; delivery plan §3.11.5 E4 "accept and discard both behave").
4. **Given** validated or provisional content visible on the surface, **When** the user
   discards, **Then** discard clears that content from the surface and writes nothing to a
   clinical record (§4.1; delivery plan §3.11.5 E4; F2 remains out of scope).
5. **Given** a terminal `failed` (or equivalent failure path) that carries a request
   reference, **When** the surface presents the failure, **Then** the request reference is
   displayed (§13.2; §5.4; delivery plan §3.11.5 E4 "failure displays the request
   reference").
6. **Given** provisional content shown during a stream, **When** the widget is rebuilt or
   the app is restarted before a successful accept of a terminal validated payload,
   **Then** that provisional content does not survive (§6.4 invariant 2; delivery plan
   §3.11.5 E4 "provisional content does not survive a rebuild or restart").
7. **Given** an installation whose AI availability flag indicates not enrolled, **When**
   the feature host builds, **Then** no AI affordances are shown and a spy proves no
   network call is made to the AI platform (§4.2 AI availability flag; A11; delivery plan
   §3.11.5 E4 "non-enrolled installation shows no affordances and makes no network call").
8. **Given** an enrolled installation whose platform is unreachable, **When** the surface
   would otherwise offer AI, **Then** it renders a normal unreachable/offline state, not
   an error dialog, and clinical non-AI workflows remain usable (A11; delivery plan
   §3.11.5 E4 "unreachable platform renders a normal state, not an error dialog").
9. **Given** an enrolled installation with a reachable platform, **When** the feature host
   builds, **Then** AI affordances are shown (delivery plan §3.11.5 E4 "enrolled and
   reachable shows affordances"; §4.2).
10. **Given** a terminal `quota_exhausted`, **When** the surface handles that outcome,
    **Then** it shows the quota state as a first-class UI state distinct from offline and
    from generic AI-unavailable, without blocking non-AI clinical work (§5.4
    `quota_exhausted` Client behaviour; A11).
11. **Given** a terminal failure whose §5.4 Client behaviour requires showing the request
    reference (including `internal_error` and `context_invalid`), **When** the surface
    presents that failure, **Then** the request reference is visible (§5.4; §13.2).
12. **Given** streaming content events and a later terminal `completed` payload, **When**
    the surface settles on the answer, **Then** it uses the validated terminal payload and
    does not assemble the final result from chunks (§6.4 invariant 1; delivery plan §6.4).

### Test plan

The minimum test set is the E4 row of delivery plan §3.11.5 (layer: *Flutter widget
(spy)*). Tests join CI permanently (delivery plan §3.10). Named tests use that Flutter
widget (spy) layer.

| # | Named test | Layer | Asserts |
| --- | --- | --- | --- |
| T1 | `surface_provisional_content_visually_distinct` | Flutter widget (spy) | Live/provisional prose is visually distinct as draft (§3.11.5 E4; §6.4; §4.1) |
| T2 | `surface_no_commit_control_before_completed` | Flutter widget (spy) | No commit/save/accept control exists before terminal `completed` (§3.11.5 E4; §6.4) |
| T3 | `surface_accept_after_completed_behaves` | Flutter widget (spy) | After `completed`, accept acknowledges the validated terminal payload; no F2 clinical acceptance write (§3.11.5 E4; Open Decision 1 `advisory_display`) |
| T4 | `surface_discard_behaves` | Flutter widget (spy) | Discard clears surface content and writes nothing to a clinical record (§3.11.5 E4; §4.1) |
| T5 | `surface_failure_displays_request_reference` | Flutter widget (spy) | Failure UI displays the request reference (§3.11.5 E4; §13.2; §5.4) |
| T6 | `surface_provisional_does_not_survive_rebuild` | Flutter widget (spy) | Provisional content does not survive a widget rebuild (§3.11.5 E4; §6.4 invariant 2) |
| T7 | `surface_provisional_does_not_survive_restart` | Flutter widget (spy) | Provisional content does not survive an app restart (§3.11.5 E4; §6.4 invariant 2) |
| T8 | `degraded_non_enrolled_hides_affordances_no_network` | Flutter widget (spy) | Non-enrolled: no AI chrome/affordances; `reachabilityPort.callCount == 0` and network spy zero (§3.11.5 E4; §4.2) |
| T9 | `degraded_unreachable_is_normal_state_not_error_dialog` | Flutter widget (spy) | Unreachable platform → normal state, not an error dialog; clinical work not blocked (A11; §3.11.5 E4) |
| T10 | `degraded_enrolled_reachable_shows_affordances` | Flutter widget (spy) | Enrolled and reachable shows AI affordances (§3.11.5 E4; §4.2) |
| T11 | `degraded_quota_exhausted_distinct_state` | Flutter widget (spy) | `quota_exhausted` shows quota state as a distinct first-class UI state (A11; §5.4) |
| T12 | `degraded_ai_unavailable_distinct_from_offline_and_quota` | Flutter widget (spy) | AI-unavailable presentation is distinct from offline/unreachable and from quota exhausted (A11) |
| T13 | `surface_internal_error_shows_request_reference` | Flutter widget (spy) | `internal_error` failure displays the request reference (§5.4 Client behaviour; §13.2) |
| T14 | `surface_context_invalid_shows_request_reference` | Flutter widget (spy) | `context_invalid` failure displays the request reference (§5.4; §13.2) |
| T15 | `surface_uses_terminal_payload_not_chunk_assembly` | Flutter widget (spy) | Final displayed answer equals the terminal validated payload, not a client assembly of deltas (§6.4 invariant 1; delivery plan §6.4) |
| T16 | `surface_provisional_never_exported` | Flutter widget (spy) | Live provisional path fires export-probe visibility hook; `exports` stays empty (§6.4 invariant 2; Done when) |
| T17 | `surface_provisional_never_persisted` | Flutter widget (spy) | Live provisional path fires persistence-probe visibility hook; `writes` stays empty (§6.4 invariant 2; §4.1 Must not) |
| T18 | `surface_installation_suspended_hides_ai_features` | Flutter widget (spy) | Terminal `FailedEvent(installation_suspended)` through SDK → host hides AI features per §5.4; clinical workflows remain usable (A11) |
| T19 | `surface_forbidden_capability_hides_affordance` | Flutter widget (spy) | `forbidden_capability` → hide the affordance for this role (§5.4) |
| T20 | `surface_contains_no_prompt_provider_or_model_identifiers` | Flutter widget (spy) | Feature surface sources pass the E1 architecture guard (R-12; delivery plan §6.4; §4.1) |
| T21 | `availability_flag_readable_without_platform_probe` | Flutter widget (spy) | Enrollment/availability and platform base URL are read from the clinic-side AI availability flag; non-enrolled path makes no platform probe (§4.2; T8 companion) |

Coverage (delivery plan §3.10): happy path of every requirement (T1–T4, T10, T15);
failure/reference branches (T5, T13–T14); every degraded-mode branch named by Done when /
A11 / §3.11.5 (T8–T12, T18–T19); provisional persistence/export/rebuild prohibitions
(T6–T7, T16–T17); inherited delivery-plan §6.4 / R-12 prohibitions (T15, T20); named
boundaries — no commit before `completed` (T2), no network when non-enrolled (T8, T21),
unreachable is not an error dialog (T9). This slice emits no new §5.4 taxonomy codes; it
surfaces consumed codes' client behaviours.

### Edge Cases

- **Commit control before `completed`**: must not exist for `prose` (§6.4; T2).
- **Accept under `advisory_display`**: acknowledges validated terminal content only; does
  not invoke the F2 AI acceptance recording RPC or write clinical provenance (Open
  Decision 1; Out of Scope F2; T3).
- **Discard**: clears surface content; writes nothing (T4).
- **Provisional across rebuild/restart**: must not survive (§6.4 invariant 2; T6–T7).
- **Provisional export/persist**: never (§6.4 invariant 2; T16–T17).
- **Chunk assembly**: forbidden; terminal payload is authoritative (§6.4 invariant 1;
  T15).
- **Non-enrolled**: hide all AI affordances; zero platform network calls (§4.2; T8, T21).
- **Platform unreachable / offline**: normal first-class state, not an error dialog; does
  not block clinical workflows (A11; T9).
- **`quota_exhausted`**: distinct quota state; offer admin path per §5.4; do not hard-lock
  the clinic (A11; §5.4; T11).
- **`installation_suspended`**: hide AI features; instruct admin (§5.4; T18).
- **`forbidden_capability`**: hide the affordance for this role (§5.4; T19).
- **`internal_error` / `context_invalid`**: show request reference (§5.4; §13.2; T13–T14).
- **Retained references after closing the screen**: E2 retains the last request reference
  for support; E4 displays it on failure and does not drop the §13.2 requirement that
  references remain available for reporting after the screen closes (Consumes E2; §13.2).
- **Diagnostic export**: if any diagnostic export is produced, it MUST include the
  retained request references (§13.2); this slice does not invent a new export product
  surface beyond that inclusion rule.
- **`structured` / `structured_atomic` client rules**: not exercised by the first
  capability (Open Decision 1 / `prose`); those §6.4 rows remain architecture for later
  surfaces and must not be weakened if referenced.
- **Conversational transcript / fourth terminal kind**: H-band; out of scope.
- **`context_required` self-healing resubmit**: J2; out of scope. E4 may display the
  failure and reference; it does not implement the refresh-and-resubmit loop.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Flutter application MUST include **AI Feature Surfaces** that provide
  per-feature UI for draft rendering, provisional/draft styling, explicit accept/discard,
  degraded-mode states, and request-reference display on failure. `(§4.1)`
- **FR-002**: AI Feature Surfaces MUST NOT persist provisional content and MUST NOT
  auto-commit AI output. `(§4.1; A5)`
- **FR-003**: For the first capability's `prose` mode, the surface MUST display live
  content and MUST enable save/accept only on `completed`. `(§6.4; Open Decision 1)`
- **FR-004**: The validated terminal payload MUST be treated as authoritative and
  self-contained; the surface MUST NEVER assemble the final result from stream chunks.
  `(§6.4)`
- **FR-005**: Provisional content MUST NEVER be persisted, NEVER be exported, and NEVER
  be entered into a clinical record; no commit affordance MAY exist until terminal
  success. `(§6.4; delivery plan §3.6 Done when)`
- **FR-006**: Every failure presentation MUST display the request reference. `(§13.2;
  §5.4; delivery plan §3.6 Done when)`
- **FR-007**: Request references retained for support MUST remain available so a user can
  report a failure after closing the screen, and MUST be included in any diagnostic
  export. `(§13.2; Consumes E2 last-reference retention)`
- **FR-008**: The clinic backend MUST store an **AI availability flag**: whether this
  installation is AI-enrolled and the platform base URL, following the established
  additive Supabase pattern. `(§4.2)`
- **FR-009**: When the installation is not AI-enrolled, the client MUST hide AI
  affordances entirely and MUST NOT probe the network to discover that fact. `(§4.2;
  delivery plan §3.6 Done when; §3.11.5 E4)`
- **FR-010**: AI unavailable, quota exhausted, and offline/unreachable MUST be distinct,
  first-class UI states; no AI failure MAY block a clinical workflow. `(A11)`
- **FR-011**: Platform unreachability MUST render as a normal state rather than an error
  dialog. `(A11; delivery plan §3.6 Done when; §3.11.5 E4)`
- **FR-012**: When the installation is enrolled and the platform is reachable, AI
  affordances MUST be shown. `(§4.2; delivery plan §3.11.5 E4)`
- **FR-013**: Clients MUST branch on §5.4 taxonomy codes (never raw provider errors) and
  MUST apply the §5.4 Client behaviour column for outcomes the surface presents, including
  hide-features / hide-affordance / show-quota / show-reference behaviours named there.
  `(§5.4)`
- **FR-014**: Explicit accept and discard MUST both be available after terminal success
  for the first surface; under `advisory_display`, accept MUST NOT write AI content into a
  clinical record through the acceptance recording RPC. `(§4.1; Open Decision 1; delivery
  plan §3.11.5 E4)`
- **FR-015**: The first AI feature surface MUST contain no prompt text, provider name, or
  model identifier, and MUST pass the E1 client architecture guard. `(§4.1; R-12;
  delivery plan §6.4)`
- **FR-016**: The first capability exercised by this surface MUST be a non-clinical-record
  capability with output mode `prose` and acceptance mode `advisory_display`. `(Open
  Decision 1; delivery plan §7)`

### Key Entities

Not applicable — this slice defines no D1 entities or new contract types. The AI
availability flag is clinic-side configuration named by §4.2 (enrolled status and
platform base URL); table/column identifiers are not invented here beyond that
responsibility.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: The first AI surface is additive for small-to-mid multi-branch clinics:
  staff can ignore or lose AI without losing clinical workflows (A11; constitution V).
  Non-enrolled clinics never see AI chrome (§4.2). No hospital-scale or always-online
  assumption is introduced.

- **Layer Placement**: This slice touches **`frontend/`** (Flutter AI Feature Surfaces,
  degraded-mode UX, request-reference display per §4.1 / §6.4 / §13.2 / A11 / §5.4) and
  **`backend/`** (AI availability flag per §4.2). It does **not** add or change
  `ai-platform/` Worker stages. Where the surface calls the gateway through the E2 SDK, it
  respects the §14 acknowledgement that the gateway is a non-primary, additive component
  (no domain logic, no business data, no write path into Supabase): Flutter still holds no
  prompts, providers, or AI business rules (§4.1; §14).

- **Data Integrity & Security**: Provisional AI content never enters clinical records
  (§6.4; §4.1 Must not). `advisory_display` accept does not perform the F2 acceptance
  write. The availability flag is additive clinic configuration; the clinic database gains
  no prompts, providers, quotas, or AI request state from this slice (§4.2 Boundary note).
  Context continues to flow only through E3 under caller RLS.

- **Failure Handling**: Non-enrolled → hide affordances, no probe (§4.2). Unreachable →
  normal state, not an error dialog (A11). `quota_exhausted` and other §5.4 outcomes follow
  the Client behaviour column with request reference on failure (§5.4; §13.2). No AI
  failure blocks clinical work (A11; constitution V).

## Out of Scope

Neighbouring slices and temptations this slice must not absorb:

- **E2** — AI Client SDK transport, AAT cache, SSE consumption, cancel, last-reference
  retention (already frozen; do not rewrite).
- **E3** — Context Resolver registry, first context RPC, client contract test (already
  frozen; do not rewrite).
- **F2** — AI acceptance recording RPC and client accept path into a clinical record.
- **D4 / D6** — Stream broker, response validator, `structured` /
  `structured_atomic` server behaviour; E4 only consumes terminal/provisional events via
  the SDK for the first `prose` surface.
- **F4** — Soft-threshold degraded *routing* (platform-side); E4 owns client degraded-mode
  UX only.
- **Band G** — In-app quota display productisation beyond showing the §5.4
  `quota_exhausted` client behaviour.
- **H1 / H3** — Conversational manifest fields, transcript store, chat surface.
- **J2** — `context_required` self-healing refresh and single resubmit.
- **B1 / B2** — Keystore, AAT issuer, and control-plane enrollment mutations (consumed
  facts only via the availability flag).
- Additional AI feature surfaces beyond the first capability named by Open Decision 1 /
  delivery plan §7.

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

- **SC-001**: Automated Flutter widget tests prove provisional content is visually draft
  and that no commit control exists before `completed` (T1–T2) — matching delivery plan
  §3.6 Done when.
- **SC-002**: Accept and discard both behave after terminal success under
  `advisory_display`, without an F2 clinical acceptance write (T3–T4).
- **SC-003**: Every exercised failure path displays the request reference (T5, T13–T14).
- **SC-004**: Provisional content does not survive rebuild or restart and is neither
  persisted nor exported (T6–T7, T16–T17).
- **SC-005**: Non-enrolled installations show no AI affordances and make no AI-platform
  network call (T8, T21); enrolled and reachable shows affordances (T10).
- **SC-006**: Platform unreachability renders as a normal state, not an error dialog, and
  AI unavailable / quota exhausted / offline are distinct (T9, T11–T12; A11).
- **SC-007**: The surface uses the terminal validated payload rather than chunk assembly,
  and passes the E1 architecture guard (T15, T20).

## Assumptions

- E2 and E3 are complete and their frozen contracts are available to consume; E1's
  architecture guard remains a permanent CI gate on `frontend/` (DP-6).
- Open Decision 1's recommended default applies: one non-clinical-record first capability
  with `prose` output and `advisory_display` acceptance (delivery plan §7).
- Open Decision 8's recommended default applies: a minimal AI-enabled (availability) flag
  in Supabase, not mirrored quota state (§4.2; §15).
- Flutter widget tests may drive the surface with spies/fakes for enrollment flag, SDK
  streams, and network; live provider inference is not required to prove this slice
  (DP-3; §3.11.5 E4 spy layer).
- CP3 composition with D4 is a review checkpoint after both exist; this slice's Done when
  is independently provable by the E4 widget suite alone.
- Primary operators remain clinic staff on Windows desktop; AI remains optional and
  additive relative to clinical workflows (A11; constitution V).
- Exact clinic table/column identifiers for the AI availability flag are chosen at plan
  time without changing the §4.2 responsibility (enrolled + platform base URL).
