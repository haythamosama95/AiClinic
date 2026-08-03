# Feature Specification: Client architecture guard in CI

**Feature Branch**: `ai/035-e1-client-arch-guard-ci`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `E1` — "Client architecture guard in CI" (delivery plan §3.6, band E).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.6, row E1):

> §13.5, §3.4.1, R-12

### Freezes

Contracts this slice establishes for the first time:

- The **client architecture guard** as an architectural CI component (not a discretionary
  test): a client-side lint that fails the Flutter build on prompt-like strings, provider
  names, or model identifiers anywhere in client code (§3.4.1 item 1; §13.5 Architecture
  guard (R-12); R-12). Later client AI slices (E2 onward) must not weaken, bypass, or
  relocate this guard; they may only extend its detection surface if the architecture is
  amended.
- The **deliberately failing fixture proof** for that guard: fixtures that inject a
  prompt-like string, a provider name, and a model identifier each fail the build, while a
  clean client tree passes (delivery plan §3.6 Done when; §3.11.5 row E1).
- The **full client-source coverage rule**: the guard's scan covers every client source
  path (delivery plan §3.11.5 row E1; §3.4.1 "Flutter codebase"; Done when "anywhere in
  client code").

### Consumes

None. E1 has `Needs: —` (delivery plan §3.6). It consumes no frozen contract from any
earlier slice. It must land before any client AI code (DP-6; §13.5 "before any AI code is
written in the client").

### Open decisions relied on

None. E1 does not depend on any §15 decision. The guard's existence, failure modes, and
placement in CI before client AI code are fully specified by §13.5, §3.4.1, R-12, and
delivery plan DP-6 / §3.6.

## Clarifications

### Session 2026-08-02

- Q: How should the client architecture guard be implemented as the CI lint that fails the Flutter build? → A: Standalone Dart script invoked as a dedicated CI step; scans client sources and exits non-zero on matches `[implementation choice — no §citation]`
- Q: Where should the deliberately failing fixtures live, and how should CI invoke the guard against them versus the clean client tree? → A: Fixtures live outside the clean scan roots under the guard’s tool/fixture directory; CI runs the script against each fixture expecting failure, and against real client sources expecting success `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Client architecture guard in CI (Priority: P1)

As the reviewer of the Flutter client, I want a CI lint treated as an architectural
component — not an optional test — that fails the build whenever prompt-like strings,
provider names, or model identifiers appear anywhere in client source, proven by
deliberately failing fixtures and by a clean-tree pass, so that later client AI work (E2+)
cannot quietly reintroduce AI internals into the Flutter app (R-12).

**Why this priority**: E1 has `Needs: —` and must precede every client AI slice (DP-6;
§13.5). Without it, E2's SDK and later surfaces have no automated defence against the
decay §3.4.1 names — prompt fragments entering the client under deadline pressure. Band E
places this guard first for that reason (delivery plan §3.6).

**Independent Test**: A CI lint fails the Flutter build on prompt-like strings, provider
names, or model identifiers anywhere in client code, and is proven by a deliberately
failing fixture (delivery plan §3.6 Done when; §3.11.5 row E1).

**Acceptance Scenarios**:

1. **Given** a deliberately prepared client fixture whose source contains a prompt-like
   string, **When** the architecture-guard CI lint runs against that fixture, **Then** the
   Flutter build fails (§3.4.1; §13.5 Architecture guard (R-12); delivery plan §3.11.5 E1
   case 1).
2. **Given** a deliberately prepared client fixture whose source contains a provider name,
   **When** the architecture-guard CI lint runs against that fixture, **Then** the Flutter
   build fails (§3.4.1; R-12; delivery plan §3.11.5 E1 case 2).
3. **Given** a deliberately prepared client fixture whose source contains a model
   identifier, **When** the architecture-guard CI lint runs against that fixture, **Then**
   the Flutter build fails (§3.4.1; R-12; delivery plan §3.11.5 E1 case 3).
4. **Given** a clean client source tree with no prompt-like strings, provider names, or
   model identifiers, **When** the architecture-guard CI lint runs, **Then** the Flutter
   build passes (delivery plan §3.11.5 E1 case 4; Done when).
5. **Given** the architecture-guard CI lint's configured scan roots, **When** those roots
   are compared to every client source path, **Then** no client source path is omitted from
   the guard (delivery plan §3.11.5 E1 case 5; §3.4.1 Flutter codebase; Done when
   "anywhere in client code").

### Test plan

The minimum test set is the E1 row of delivery plan §3.11.5 (layer: *CI lint*). Tests join
CI permanently (delivery plan §3.10). Named tests cite §13.5's Architecture guard (R-12)
layer.

| # | Named test | Layer | Asserts |
| --- | --- | --- | --- |
| T1 | `guard_prompt_like_string_fails_build` | CI lint | A fixture containing a prompt-like string fails the Flutter build (§3.11.5 E1; §3.4.1; §13.5 Architecture guard (R-12)) |
| T2 | `guard_provider_name_fails_build` | CI lint | A fixture containing a provider name fails the Flutter build (§3.11.5 E1; §3.4.1; R-12) |
| T3 | `guard_model_identifier_fails_build` | CI lint | A fixture containing a model identifier fails the Flutter build (§3.11.5 E1; §3.4.1; R-12) |
| T4 | `guard_clean_tree_passes` | CI lint | A clean client tree with none of the three forbidden categories passes the Flutter build (§3.11.5 E1; Done when) |
| T5 | `guard_covers_every_client_source_path` | CI lint | The guard's scan covers every client source path; omitting a path fails the assertion (§3.11.5 E1; §3.4.1; Done when) |

Coverage (delivery plan §3.10): happy path of every requirement (T4 clean pass; T5 full
coverage); every failure branch this slice can reach — prompt-like string (T1), provider
name (T2), model identifier (T3); the inherited prohibition that prompt text, provider
names, and model identifiers must not enter the Flutter client (R-12 / delivery plan
§6.4); the named boundary that the guard covers every client source path (T5). E1 emits
no §5.4 platform error codes — failures are CI build failures, not runtime taxonomy codes.

### Edge Cases

- **Prompt-like string in client source**: the only defence against seam decay named in
  §3.4.1 is a build failure. T1 is that branch. This slice emits no §5.4 error code.
- **Provider name in client source**: Capability Contract deliberately excludes provider
  name from what the client may learn (§3.4); the guard fails the build when one appears
  (T2; R-12).
- **Model identifier in client source**: same seam exclusion for model name (§3.4); the
  guard fails the build when a model identifier appears (T3; R-12).
- **Clean tree versus failing fixtures**: the deliberately failing fixtures prove T1–T3 and
  must not remain in the tree that T4 asserts as clean. The failing runs are separate,
  controlled invocations against fixtures; the clean-tree pass is the permanent CI gate on
  the real client sources (Done when; §3.11.5 E1).
- **Partial path coverage**: if any client source path is outside the lint's scan roots,
  the R-12 mitigation is incomplete. T5 fails on omitted paths (§3.11.5 E1 case 5).
- **No runtime degradation path**: E1 is CI-only. It does not handle AI unavailability,
  network failure, or permission denial at runtime — those belong to later client slices
  (E2–E4). When the guard fails, the build stops; there is no degraded "warn and continue"
  mode in the cited sections.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Flutter client MUST be protected by a client-side CI lint, treated as an
  architectural component rather than an optional test, that fails the build when
  prompt-like strings appear in the Flutter codebase. `(§3.4.1; §13.5 Architecture guard
  (R-12); R-12)`
- **FR-002**: The same CI lint MUST fail the Flutter build when provider names appear
  anywhere in client code. `(§3.4.1; R-12; delivery plan §3.6 Done when)`
- **FR-003**: The same CI lint MUST fail the Flutter build when model identifiers appear
  anywhere in client code. `(§3.4.1; R-12; delivery plan §3.6 Done when)`
- **FR-004**: The CI lint MUST cover every client source path so the prohibition cannot be
  bypassed by placing forbidden content outside a narrow scan root. `(§3.4.1 Flutter
  codebase; delivery plan §3.11.5 E1; Done when "anywhere in client code")`
- **FR-005**: The guard MUST be proven by deliberately failing fixtures — one for a
  prompt-like string, one for a provider name, and one for a model identifier — each of
  which fails the build, and by a clean client tree that passes. `(delivery plan §3.6 Done
  when; §3.11.5 E1)`
- **FR-006**: The architecture guard MUST exist in CI before any AI code is written in the
  client; later band-E slices that add client AI behaviour (E2 onward) depend on this
  ordering (DP-6). `(§13.5; delivery plan DP-6, §3.6)`

### Key Entities

Not applicable — this slice defines no entities.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Protecting the client/platform seam keeps AI additive for small-to-mid
  multi-branch clinics: if prompt or provider knowledge leaks into Flutter, clinics inherit
  a dual-maintained AI surface that the architecture rejects (§3.4 asymmetry; R-12). This
  slice adds one CI rule, not clinic-operated infrastructure.

- **Layer Placement**: This slice touches only `frontend/` (Flutter) — the CI lint, its
  scan of client source paths, and the deliberately failing fixtures that prove it
  (§3.4.1; §13.5 Architecture guard (R-12)). It touches neither `ai-platform/` (Cloudflare
  Worker) nor `backend/` (Supabase). It is not part of the gateway; the §14 acknowledgement
  that the gateway is a non-primary, additive component does not apply to this slice's
  placement.

- **Data Integrity & Security**: E1 writes no domain data, opens no RPC, and creates no
  journal row. Its security contribution is preventing AI internals (prompt text, provider
  names, model identifiers) from entering the client binary path (R-12; Capability Contract
  exclusions enforced via §3.4.1). Tenant/branch RLS and audit fields are unchanged.

- **Failure Handling**: Failure is a CI build failure on forbidden content (FR-001–FR-003)
  or on incomplete path coverage (FR-004). There is no runtime request path and therefore
  no AI-unavailable degradation behaviour in this slice; clinical work continues unaffected
  because no client AI surface yet depends on the platform (E1 precedes E2–E4).

## Out of Scope

Explicit exclusions (delivery plan §2.4, §6.4):

- **AI Client SDK (E2)**: token acquisition, idempotency, SSE consumption, cancel, and
  terminal-error non-retry — delivery plan §3.6 row E2. E1 installs the guard only; it
  adds no SDK.
- **Context Resolver registry, first context RPC, and client contract test (E3)**: the
  second automated rule in §3.4.1 (client contract test that the Resolver can produce every
  declared key) is E3, not E1. E1 does not fetch manifests or assert context-key coverage.
- **First AI feature surface and degraded mode (E4)**: provisional-draft UX and
  non-enrolled / unreachable behaviour — delivery plan §3.6 row E4.
- **Any client AI feature code**: E1 must land before that code exists (DP-6; §13.5); this
  slice must not introduce the surfaces it is meant to guard.
- **Gateway, Supabase, and provider adapter work**: bands A–D and F+; E1 does not change
  Worker, D1, R2, or clinic RPCs.
- **Concrete enumeration of every commercial provider name or model id as architecture**:
  the cited sections name the three forbidden *categories*; expanding an exhaustive
  worldwide catalogue is not in scope. The slice freezes the CI rule and proves the three
  categories with fixtures (FR-005).

Prohibitions inherited from delivery plan §6.4 that E1 must not introduce:

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, a provider name, or a model identifier anywhere in the Flutter client
  (R-12) — E1 exists to make this fail the build.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5,
  §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content
  (§6.4, A5).

E1 carries no request path, so most of these are vacuous here — they are restated because
the coverage rule (delivery plan §3.10 item 4) requires every inherited prohibition to be
acknowledged. The R-12 prohibition is the one this slice actively enforces.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A fixture containing a prompt-like string fails the Flutter build, provable by
  `guard_prompt_like_string_fails_build`.
- **SC-002**: A fixture containing a provider name fails the Flutter build, provable by
  `guard_provider_name_fails_build`.
- **SC-003**: A fixture containing a model identifier fails the Flutter build, provable by
  `guard_model_identifier_fails_build`.
- **SC-004**: A clean client source tree passes the architecture-guard lint, provable by
  `guard_clean_tree_passes`.
- **SC-005**: The guard's configured scan covers every client source path, provable by
  `guard_covers_every_client_source_path`.

## Assumptions

- "Client source" / "Flutter codebase" means the Flutter application sources under
  `frontend/` that ship in or build the desktop client — the surface §3.4.1 and R-12 name.
  Exact include/exclude globs (e.g. generated files versus hand-written Dart) are an
  implementation choice so long as T5 still proves every client source path is covered and
  T4 still passes on the clean tree.
- The concrete fixture strings that stand for "prompt-like string", "provider name", and
  "model identifier" are chosen in implementation to exercise the three categories named by
  §3.4.1 / R-12 / §13.5; the architecture does not enumerate an exhaustive corpus. Clarify
  may pin representative examples without amending the architecture.
- Deliberately failing fixtures are invoked in controlled CI jobs that expect failure; they
  are not left in the clean tree that T4 gates (Done when; §3.11.5).
- No §15 open decision is assumed; none applies to this slice.
- E2 and later client AI slices are out of scope and must not begin until this guard is in
  CI (DP-6).
