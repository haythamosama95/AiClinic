# AI Platform — Delivery Plan

- Purpose: Decompose the AI platform architecture into small, individually specifiable, individually implementable slices, and define the rules that keep those slices from drifting away from the architecture.
- Read this when: choosing what to build next on the AI platform, opening a new Spec Kit feature for AI platform work, or reviewing a completed AI platform slice.
- Canonical for: AI platform build order, slice boundaries, slice completion criteria, and the authoring rules for AI platform feature specs.
- Usually paired with: `docs/architecture/ai-platform/01-ai-platform.md` (the architecture this plan sequences), `docs/architecture/ai-platform/02-ai-platform-overview.md` (orientation), the band implementation references [`01-band-a`](implementation-references/01-band-a-implementation-reference.md)–[`03-band-c`](implementation-references/03-band-c-implementation-reference.md) (A–C), [`04-band-d`](implementation-references/04-band-d-implementation-reference.md)–[`08-band-j`](implementation-references/08-band-j-implementation-reference.md) (D, E, F, H, J; `04-ai-platform-operator-runbook` is the operator runbook), and `.specify/memory/constitution.md`.
- Not covered here: any architectural decision. This document sequences decisions made in `01-ai-platform.md`; it never makes new ones. Where the two appear to conflict, `01-ai-platform.md` wins and this document is wrong.

> **Status:** Delivery plan. Bands A–J are sliced and largely implemented as modules and suites;
> band I wires those modules onto the live Worker and Flutter request paths, band G (the commercial
> surface) is sliced now that amendment A15 has settled its product inputs, and band V covers the
> verification tooling around the platform (scenario catalog suite and viewer). Section references
> of the form §N.M refer to `docs/architecture/ai-platform/01-ai-platform.md` unless stated
> otherwise.

---



## Table of Contents

1. [Purpose and Operating Assumptions](#1-purpose-and-operating-assumptions)
2. [What a Slice Is](#2-what-a-slice-is)
3. [The Slice Sequence](#3-the-slice-sequence)
4. [Bands Not Yet Decomposed](#4-bands-not-yet-decomposed) (band K only; band G decomposed in [§3.13](#313-band-g--commercial-surface))
5. [Review Checkpoints](#5-review-checkpoints)
6. [Spec Authoring Protocol](#6-spec-authoring-protocol)
7. [Dependencies Outside the Platform](#7-dependencies-outside-the-platform)

---



## 1. Purpose and Operating Assumptions



### 1.1 Why this document exists separately

`01-ai-platform.md` decides *what* the AI platform is. It is deliberately dense, and it is stable:
once a decision in it is settled, it should not churn. This document decides *in what order the
decisions get built*, and it is expected to churn — slice boundaries will move as the first few
slices reveal how much a single Spec Kit cycle can actually absorb.

Keeping them apart means the volatile document can be rewritten without touching the authoritative
one.

### 1.2 The four assumptions that shape the sequence

These are stated explicitly because they invalidate the ordering criteria that would otherwise be
obvious, and because if any of them stops being true the plan needs revisiting.


| #   | Assumption                                                                                                                                              | Consequence for the plan                                                                                                                                                        |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **Nothing is sold and nothing is deployed.** The product ships only when the Flutter client, the Supabase backend, and the AI platform are all complete | "Independently shippable" is not a useful property of an increment. No slice needs to be demoable, and no slice needs a migration path from a previous release                  |
| 2   | **Feature specs are authored by a capable but not exceptional reasoning model.** Its job is to transcribe architecture into tasks, not to design        | A slice must be answerable entirely from `01-ai-platform.md`. Any slice that would require inventing an architectural decision is mis-scoped ([§6.3](#63-stop-conditions))      |
| 3   | **Implementation is performed by a model with weak judgement.** It will implement whatever the spec says, including whatever the spec got wrong         | Contracts must be frozen as *code* before their consumers are built, so the implementer is constrained by the type system rather than by prose ([§2.3](#23-the-no-rework-rule)) |
| 4   | **The reviewer is one human.** Review capacity, not implementation capacity, is the binding constraint                                                  | Slice size is chosen so that one diff is reviewable in one sitting against one named part of the architecture                                                                   |




### 1.3 Decisions this plan records

These supersede the phase model previously carried in §12.2 of the architecture document.


| #    | Decision                                                                                                                                                 | Rationale                                                                                                                                                                                                                                                                                                                                                                   |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DP-1 | **The P0–P4 milestone layer is retired.** Slices are grouped into lettered *bands* for orientation only; a band is not a gate and has no release meaning | Milestones existed to mark "safe to expose to a clinic". With no rollout before completion, that gate protects nothing and only adds a concept                                                                                                                                                                                                                              |
| DP-2 | **Sequencing is driven by dependency and contract stability**, not by user-visible value                                                                 | The only thing that can make a later slice expensive is an earlier slice having frozen the wrong contract, so contract slices come first                                                                                                                                                                                                                                    |
| DP-3 | **A slice is complete when an automated test proves it**, not when it can be demonstrated                                                                | With nothing deployed, tests are the only available evidence, and they are also the review artifact ([§2.2](#22-the-completion-criterion))                                                                                                                                                                                                                                  |
| DP-4 | **Contracts are frozen in dedicated early slices that contain no behaviour**                                                                             | A frozen, typed contract is a constraint a weak implementer cannot drift away from; prose in a spec is a suggestion                                                                                                                                                                                                                                                         |
| DP-5 | **Compatibility machinery is deferred, but its contract surface is not**                                                                                 | There are no deployed clients, so overlap windows, deprecation flows, staged prompt rollout, and the `context_required` self-healing *behaviour* have no audience yet. The error codes, lifecycle states, and journal columns they need are cheap now and expensive to retrofit, so those land early and stay unused; the behaviour is sliced as band J ([§3.9](#39-band-j--deferred-compatibility-machinery)) |
| DP-6 | **The client architecture guard (R-12) lands before any client AI code**, not at hardening time                                                          | The guard exists to stop prompt text, provider names, and model identifiers from entering the Flutter app. With generated client code, that is the expected outcome rather than a tail risk, so the guard must precede the code it guards                                                                                                                                   |
| DP-7 | **The walking-skeleton thread is retained as a falsification checkpoint**, not as a release                                                              | Without shipping pressure, the failure mode is fifty well-tested slices that have never run together. One end-to-end thread through a fake provider is the earliest point at which the contract slices can be proven wrong ([§5](#5-review-checkpoints)). Band I is the slice set that makes that thread run on the live Worker and Flutter paths rather than only in harnesses |
| DP-8 | **Everything the architecture decides is sliced (bands A–J plus bands G and I).** Only band K stays coarse                                               | Band G was blocked on product decisions rather than architectural ones; amendment A15 settled them (credit-denominated monthly quota, declared per-capability prices, a small plan catalogue, no overage, platform-issued invoices, gauge usage surface), and the band is decomposed in [§3.13](#313-band-g--commercial-surface). Band K remains deliberately undesigned — slicing it would encode a deferral as a commitment ([§4](#4-bands-not-yet-decomposed)). Band I adds no new §4 component: it composes modules already frozen by A–J onto `POST /v1/requests`, discovery HTTP, and the first client invoke path. Band V is verification tooling traced to §13.5 and the scenario catalog, not a §4 component group ([§3.14](#314-band-v--verification-tooling-scenario-catalog-and-viewer)) |


---



## 2. What a Slice Is



### 2.1 Definition

A slice is one Spec Kit feature: one `specs/<NNN>-<name>/` directory, one branch, one review. It
implements *named parts* of `01-ai-platform.md` — one component group from §4 or the contracts from
§5 that group needs — and nothing else. The single exception is band V
([§3.14](#314-band-v--verification-tooling-scenario-catalog-and-viewer)): verification tooling that
traces to §13.5 and the scenario catalog rather than to a §4 component group.

Slice identifiers in this document (`A1`, `D3`, `D4`, …) are stable and do not change when a slice
is started. The three-digit Spec Kit number is assigned at that moment from the next free number in
`specs/`, so a slice directory looks like `specs/015-ai-worker-skeleton/` while still being referred
to here as A1.

### 2.2 The completion criterion

**A slice is done when a test a human can read and believe passes.** Every slice's `spec.md` states
its acceptance criteria as test cases, and the review artifact is the test file plus the diff. The
minimum case list for each slice is [§3.12](#312-required-test-cases-per-slice), governed by the
coverage rule in [§3.11](#311-coverage-rule).

This replaces "independently shippable" (DP-1, DP-3). It has two useful side effects: it gives the
spec-authoring model something concrete to write instead of prose about clinical value, and it makes
a slice's boundary self-enforcing — work that cannot be named in a test belongs to a different slice.

### 2.3 The no-rework rule

**A later slice may extend an earlier slice's contract. It may never rewrite one.** Adding a field, a
case, a column, or an implementation is extension. Changing the meaning of an existing one is not.

If a slice discovers that a frozen contract is wrong, that is not a licence to change it inside the
slice. It is a finding: stop, amend `01-ai-platform.md`, and treat the amendment as a contract change
reviewed on its own ([§13.4](01-ai-platform.md#134-environments-configuration-and-secrets),
"contracts first"). The rule exists because the implementer will otherwise "fix" a contract to suit
the slice in front of it, and the fix will be invisible in a large diff.

### 2.4 Every slice states its exclusions

Each slice's `spec.md` carries an explicit out-of-scope list, the way the retired phase table did per
phase. With fifty slices instead of five phases, R-20 (complexity creep) has ten times as many
openings, and an implementer with weak judgement is exactly the kind that helpfully adds a retry loop
nobody asked for.

### 2.5 Sizing guidance

A correctly sized slice touches one *component group* from §4 — one component, or a small set of
components that cannot be tested apart — produces roughly 25–40 tasks, and has requirements that fit
on a few pages because they are restatements of named architecture sections. A slice whose `spec.md`
needs original prose to explain *why* is too large or is mis-scoped.

The earlier guidance was 10–25 tasks and strictly one component. A1–A4 were authored under it and
each produced 11–14 tasks, at which size the fixed per-slice overhead — spec, plan, research,
contracts, review setup — dominates the work actually delivered. The band tables in
[§3](#3-the-slice-sequence) were merged accordingly ([§2.6](#26-merged-slices)).

### 2.6 Merged slices

Several slices in [§3](#3-the-slice-sequence) combine what were originally separate rows in this
document's first version. Each merged slice keeps **one** sequential id within its band (`A5`, `B3`,
`C1`, …) rather than a compound name.

A merged slice is still **one** Spec Kit feature: one `specs/<NNN>-<name>/` directory, one branch,
one review. Its `Implements` section lists the union of the merged components' canonical sections, and
its test plan is the union of their former case lists in [§3.12](#312-required-test-cases-per-slice).

A1–A4 were implemented before the merge and are unchanged.

---



## 3. The Slice Sequence



### 3.1 How to read the tables

`Canonical` names the sections of `01-ai-platform.md` a slice implements; these are the sections the
spec must cite and the reviewer must check against. `Needs` lists prerequisite slices. `Done when`
states the acceptance shape — the spec expands each into named test cases.

Bands A, B, and C are close to strictly ordered. Band D and band E may proceed in parallel once
C1 exists. Band F may start any time after the slice it hardens. Band H is the last large block of
new behaviour. Band J is ordered by trigger rather than by position: each of its slices waits for the
condition in its `Build when` column ([§3.9](#39-band-j--deferred-compatibility-machinery)). Band I
is the live-composition band: it starts after the modules named in each slice's `Needs` column exist,
and it freezes no new contract — it only attaches already-built stages and client libraries to the
Worker fetch handler and the first Flutter AI surface ([§3.10](#310-band-i--live-composition-and-request-path-wiring)).
Band G is the commercial band: it may start as soon as its `Needs` are met and runs in parallel with
the later bands — nothing in bands H, I, or J depends on it ([§3.13](#313-band-g--commercial-surface)).
Band V is verification tooling — the E2E scenario catalog suite and the viewer app — and is ordered
by what it verifies rather than by platform dependencies ([§3.14](#314-band-v--verification-tooling-scenario-catalog-and-viewer)).

### 3.2 Band A — Foundations and frozen contracts

> **Implementation reference:** [`implementation-references/01-band-a-implementation-reference.md`](implementation-references/01-band-a-implementation-reference.md) — plain-language account of what A1–A6 built, with diagrams and test commands.

Nothing in this band handles a real request. It exists so that everything after it is constrained.

**What this band does:** Deploys the Worker shell (three isolated environments), then freezes every cross-slice contract — error taxonomy, canonical inference types, capability manifest schema, context-key vocabulary, D1 schema, config cache, and the HTTP/SSE wire protocol. No authentication, no quota, no prompts, no providers.

**Useful to know:** A1–A4 are complete. Completing A6 satisfies checkpoint **CP1** — the earliest proof that the frozen contracts compose at build time. Every later band consumes these types; changing them after CP1 is a contract-change review, not a slice fix ([§2.3](#23-the-no-rework-rule)).


| ID     | Slice                                                                     | Canonical                  | Needs | Done when                                                                                                                                                                                                                                                                                                   |
| ------ | ------------------------------------------------------------------------- | -------------------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A1** | Worker skeleton and environments                                          | §13.4, §1.4                | —     | Separate dev/staging/production Worker environments deploy, each with its own D1, R2, and Durable Object namespaces and its own secret bindings; a health endpoint reports build and environment identity; a test fails if two environments share any binding                                               |
| **A2** | Diagnostic envelope: error taxonomy, request reference, trace propagation | §5.4, §4.3.1, §13.1, §13.2 | A1    | Every code in the §5.4 table exists with its retryability, quota-consumption flag, and HTTP mapping; a caller-supplied trace id appears on every log line for that request; the request reference generator produces a short human-readable identifier; an unrecognised code is treated as `internal_error` |
| **A3** | Canonical inference representation                                        | §5.3, §9.10                | A1    | Canonical request, stream chunk, result, and error types exist; a contract test fails if any field name is provider-shaped                                                                                                                                                                                  |
| **A4** | Capability manifest schema and loader                                     | §5.1, §5.7                 | A3    | The manifest schema covers all ten field groups; the build fails on a malformed manifest or on an in-place edit to a published version; `interaction_mode` defaults to `single_shot`                                                                                                                        |
| **A5** | Context key vocabulary, D1 schema, and config cache | §5.2, §7.3, §13.4, §4.3.2, §4.4, §9.15 | A4 | The `domain.concept@vN` format is enforced, the first key's shape is published, and a test rejects a key named after storage rather than meaning; forward-only migrations create every entity in §7.3, including the index on the request reference and the nullable `conversation_id` / `turn_ordinal` columns, pinned by a schema snapshot test and applying cleanly to an empty database; a warm isolate answers installations, keys, entitlements, grants, kill switches, and the active routing policy from memory with no I/O, and a cold isolate performs exactly one D1 read |
| **A6** | Protocol adapter and SSE framing                                          | §4.3.1, §5.5               | A2    | Size limits and the idempotency key, trace id, and version pin headers are parsed; a stream opens with `accepted` carrying the request reference, emits heartbeats, and ends with exactly one terminal event; the one-terminal-event invariant holds under abort                                            |




### 3.3 Band B — Trust, identity, and admission

> **Implementation reference:** [`implementation-references/02-band-b-implementation-reference.md`](implementation-references/02-band-b-implementation-reference.md) — plain-language account of what B1–B4 built, with diagrams and test commands.

**What this band does:** Answers "who is calling, are they allowed, and have they exceeded their budget?" before any inference work begins. It mints installation-scoped access tokens (AATs) from Supabase, enrolls and manages installations in the control plane, runs the guard pipeline stages (identity, rate limiting, entitlement, kill switches), and admits requests through a per-installation Quota Durable Object that tracks `jti` freshness, idempotency, budget, and concurrency.

**Useful to know:** B1 can start in parallel with Band A once RBAC tables are stable ([§7](#7-dependencies-outside-the-platform)). B3 deliberately excludes replay rejection — that belongs to B4's Quota DO. Completing B4 satisfies the *module* half of checkpoint **CP2**; I1 reifies CP2 on live HTTP. Guard and admission modules are library-ready after Band B; attaching them to `POST /v1/requests` is Band I.


| ID     | Slice                                               | Canonical                           | Needs      | Done when                                                                                                                                                                                                                                                                               |
| ------ | --------------------------------------------------- | ----------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **B1** | Installation keystore and AAT issuer | §4.2, §4.2.1, §8.1, §5.6 | — | The installation id and Ed25519 private signing key live in a restricted schema, an RLS test proves `anon` and `authenticated` cannot read it, and rotation adds a key without invalidating tokens already in flight; the issuer RPC mints an `alg: EdDSA` JWS via `pgsodium.crypto_sign_detached` (§4.2.1), populates all claims in §5.6, derives `scopes` from the RBAC tables so they can never be supplied by the caller, records issuance, and is itself rate-limited |
| **B2** | Control-plane enrollment and installation lifecycle | §4.5, §8.1 | A5 | Operator-authenticated enroll, suspend, resume, rotate, and delete write `installation`, `installation_key`, `entitlement`, and a `control_audit` row carrying the operator identity |
| **B3** | Guard stages: identity, rate limiting, entitlement and kill switches | §4.3.2, §4.2.1, §5.6, §4.3.3, §4.3.4, §4.3.12, §7.5, §6.1 stages 2–4 | A5, B1, B2 | Signature (WebCrypto `Ed25519`, `alg` pinned to `EdDSA` so `none` and HMAC tokens are rejected), audience, expiry, and clock skew are verified through the token verifier port, the request principal is immutable to later stages, and a suspended installation is rejected; all three composite rate-limit keys are enforced, with rejections incrementing bucketed `platform_counter` rows and never journaled as requests; AI-enablement, plan tier, capability grant, and all four kill-switch scopes are evaluated from the config cache with no D1 read on a warm isolate. Replay rejection is explicitly out of scope here — it belongs to B4 |
| **B4** | Quota Durable Object and admission stage | §4.3.3, §4.4, §9.17, §7.7, §6.1 stage 8, §6.2, §6.6 | A5, B3 | One admission call answers all four installation-scoped questions — `jti` freshness, idempotency novelty, remaining budget, concurrency headroom — and a separate credit call settles actual usage; ephemeral sets expire in place and a concurrency test demonstrates serialized counting; the pipeline stage makes exactly one Durable Object round trip per request, a repeated idempotency key returns the original request's state instead of starting a second inference, and Durable Object unavailability follows the capped fail-open grace policy (Open Decision 3) |




### 3.4 Band C — Capability, context, and the journal

**What this band does:** Resolves which AI capabilities an installation may use, validates the clinic context payload against each capability's declared key requirements, and journals every admitted request from first touch through terminal state. The discovery endpoint lets the client learn what is available without hard-coding capability ids.

**Useful to know:** C1 is the unlock for parallel work in bands D and E — both need a resolved manifest. C1 freezes `resolve()` / `discover()` as libraries; the live discovery HTTP route is Band I (I2). C2 emits `context_required` with the missing-key manifest (the self-healing *behaviour* for stale clients is deferred to J2 under DP-5; hosting that behaviour on the live submit path is I4). C3's journal is the audit backbone that band F's support lookup and dashboards query. A guard rejection must produce **no** journal row. Wiring stages 5–9 into live `POST /v1/requests` is I1.

> **Implementation reference:** [`implementation-references/03-band-c-implementation-reference.md`](implementation-references/03-band-c-implementation-reference.md) — plain-language account of what C1–C3 built, with diagrams and test commands.


| ID     | Slice                                     | Canonical                            | Needs  | Done when                                                                                                                                                                                                                                          |
| ------ | ----------------------------------------- | ------------------------------------ | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **C1** | Capability registry, resolver stage, and discovery endpoint | §4.3.4, §5.1, §6.1 stage 5, §5.5, §5.2 | A4, B3 | A capability id plus requested version resolves to one immutable manifest honouring the client's pin, distinguishing `capability_unknown`, `capability_retired`, and `capability_disabled`; the discovery endpoint returns the active manifests for an installation and plan, cacheable and revalidated by version or etag |
| **C2** | Context validator stage and cost pre-flight | §4.3.5, §5.2, §4.3.3, §6.1 stages 6–7 | A5, C1 | Required keys, declared shapes, size bounds, and branch consistency against the token claims are enforced, undeclared keys are dropped rather than forwarded, and a missing required key produces `context_required` carrying the missing-key manifest; estimated input tokens (the byte-based estimator of §13.6.2) plus the capability's maximum output tokens are checked in tokens against its token-denominated per-request ceiling before any egress, producing `request_too_large` |
| **C3** | Journal writer, post-response detail, and get-request endpoint | §4.3.11, §6.1 stages 9, 15, 16, §6.3, §7.4, §7.4.1, §7.6, §5.5 | A5, C1 | The `ai_request` row is written synchronously before any work begins and updated with the terminal state, every state transition in §6.3 is journaled with a timestamp, and a request rejected by the guard produces no journal row; `ai_attempt` rows, the `usage_event` row, and exactly one R2 object per request are written after the response, and a failure there never fails the request; a request reference resolves to its terminal state and, if completed, the validated result, through a single indexed lookup |




### 3.5 Band D — The inference path

> **Implementation reference:** [`implementation-references/04-band-d-implementation-reference.md`](implementation-references/04-band-d-implementation-reference.md) — plain-language account of what D1–D7 built, with diagrams and test commands (tip `181ab637`, before review-comment remediation).

**What this band does:** The core AI pipeline: compose a prompt from immutable artifacts, route to a provider through a policy-driven chain, invoke with bounded retry and fallback, stream normalized chunks to the client, validate the assembled output (with optional repair), and adapt real providers behind a shared port. D1–D4 use the fake adapter; D5 adds the first real provider; D7 proves a second provider needs only an adapter and a routing-policy edit.

**Useful to know:** D4 plus E4 produce the *module* half of checkpoint **CP3** (the falsification / walking-skeleton thread, DP-7). Band I wires those modules onto live HTTP and Flutter invoke so the thread runs end to end ([§3.10](#310-band-i--live-composition-and-request-path-wiring)). D7 plus F1 satisfy **CP4**: provider independence. Prompt text never lives in D1; context is rendered as delimited typed data, never merged into instructions (R-10).


| ID      | Slice                                      | Canonical           | Needs      | Done when                                                                                                                                                                                                                                                                                                                                               |
| ------- | ------------------------------------------ | ------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **D1** | Prompt registry and composer | §4.3.6, §5.7, §9.5, §5.3 | A3, A4, C2 | Prompt artifacts are immutable assets deployed with the Worker, pinned by hash from the manifest, the build fails if a pinned artifact is missing or altered, and no prompt text is readable from D1; a canonical request is assembled from the system instruction, business-rule fragments, the context rendering template, the user intent, and the output constraints, with the output-format instruction derived from the output schema rather than authored separately, and context rendered as delimited typed data, never merged into instructions (R-10) |
| **D2** | Provider port, fake adapter, and routing policy | §4.3.8, §13.5, §4.3.7, §7.3 | A3, A5 | The provider port is defined including the retryable-versus-terminal classification contract, and a deterministic fake adapter produces success, each retryable failure class, each terminal failure class, truncation, and a malformed response; a versioned routing policy stored as data yields an ordered candidate chain from capability requirements, the selection reason is recorded on the request, and the chain depends only on capability, policy, and request — never on provider history |
| **D3**  | Invocation with bounded retry and fallback | §4.3.7, §8.6, §6.6  | D2      | Retries are bounded and jittered and occur only for adapter-classified retryable failures; each attempt is journaled separately; exhausting the chain produces `provider_unavailable`; a stream restarted on a fallback target emits an explicit regenerating event and never splices two providers' text                                               |
| **D4** | Stream broker, prose streaming, and cancellation | §4.3.10, §6.4, §5.5, §6.5, §9.7 | A6, D3 | Normalized chunks are relayed with incremental cheap guards for `prose`, heartbeats prevent idle timeouts, and the full guard set runs on the assembled text at completion; a client disconnect aborts the in-flight provider fetch through its abort signal, the request terminates as `cancelled`, partial usage is credited to the Quota Durable Object, and no per-request state is created |
| **D5**  | First real provider adapter                | §4.3.8              | D2      | Wire mapping, stream normalization, usage extraction, and error classification pass against recorded fixtures including malformed and truncated responses; credentials come from the secret store and appear in no log or journal row                                                                                                                   |
| **D6** | Response validator, bounded repair, and structured output modes | §4.3.9, §6.4, §5.1 | D4 | Transport validity, schema conformance, declared business constraints, and safety guards (leaked system instructions, refusals, empty or truncated output, injection echo) are applied in that order; a single budgeted re-ask with the validation errors appended is attempted only where the manifest allows it, attempts are capped, counted, and journaled, and exhaustion produces `validation_failed` with invalid content never returned; `structured` emits `partial_structured` events every one of which is flagged provisional with the terminal event carrying the whole validated document, `structured_atomic` emits progress only, and the terminal payload is self-contained and never assembled from chunks |
| **D7** | Second provider adapter                    | §4.3.8, §13.5       | D5 (F1 for the eval clause only) | A second provider passes the same fixture suite and the capability evals, and is registered as a low-priority fallback target by routing policy alone, with no pipeline change. The adapter, fixture suite, policy registration, and fallback ordering need only D5; the capability-eval clause needs F1 and is satisfied whenever F1 lands, in either order, since F1's own `Needs` (D1, D5) do not include D7. CP4 requires both halves                                                                                                                                                                          |




### 3.6 Band E — Client integration

> **Implementation reference:** [`implementation-references/05-band-e-implementation-reference.md`](implementation-references/05-band-e-implementation-reference.md) — plain-language account of what E1–E4 built, with diagrams and test commands (tip `b41e3894`, before review-comment remediation).

**What this band does:** Wires the Flutter desktop app to the platform without leaking AI internals. E1 installs the architecture guard (R-12) in CI; E2 is the AI Client SDK (token acquisition, idempotency, SSE consumption, cancel); E3 is the Context Resolver and the first clinic-side context RPC; E4 is the first user-visible AI surface with provisional-draft UX and degraded-mode behaviour.

**Useful to know:** E1 must land before E2 (DP-6) — the guard must exist before any client AI code is written. The rest of the band may proceed in parallel with band D once C1 exists. E3's contract test fetches live manifests and fails if the Resolver cannot satisfy every declared key — this catches context-key drift early. E4 ships the first surface and degraded-mode UX; composing production AAT mint and HTTPS submit onto that surface is Band I ([§3.10](#310-band-i--live-composition-and-request-path-wiring)), which together with I1 reifies CP3.


| ID     | Slice                                  | Canonical           | Needs      | Done when                                                                                                                                                                                                                                                                   |
| ------ | -------------------------------------- | ------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **E1** | Client architecture guard in CI        | §13.5, §3.4.1, R-12 | —          | A CI lint fails the Flutter build on prompt-like strings, provider names, or model identifiers anywhere in client code, and is proven by a deliberately failing fixture                                                                                                     |
| **E2** | AI Client SDK                          | §4.1, §5.5, §5.4    | E1, A6, C1 | The SDK acquires and caches an AAT, re-mints once on `unauthenticated`, submits with a stable idempotency key, consumes the event stream, surfaces terminal state, exposes cancel, retains the last N request references, and never retries after a terminal platform error |
| **E3** | Context Resolver registry, first context RPC, and client contract test | §4.1, §5.2, §4.2, §13.5 | E2, C1 | A generic context key → resolver registry assembles a payload from a key list, never receives or branches on a capability id, and caches only within a screen; an ordinary read RPC returns the first key's declared shape under the caller's own RLS with no AI-specific knowledge; the Flutter test suite fetches live manifests and fails if the Resolver cannot satisfy every declared key of every active capability |
| **E4** | First AI feature surface and degraded mode | §4.1, §6.4, §13.2, §4.2, §5.4, A11 | E2, E3 | Provisional content is visibly draft with no commit affordance until terminal success, the request reference is displayed on every failure, and provisional content is never persisted or exported; a non-enrolled installation hides AI affordances entirely without probing the network, and platform unreachability renders as a normal state rather than an error dialog |




### 3.7 Band F — Hardening and operations

> **Implementation reference:** [`implementation-references/06-band-f-implementation-reference.md`](implementation-references/06-band-f-implementation-reference.md) — plain-language account of what F1–F5 built, with diagrams and test commands (tip `9084b9d7`, before review-comment remediation).

**What this band does:** Makes the platform operationally honest after the inference path works. Eval harnesses block prompt regressions; the acceptance RPC ties AI output to clinical records with provenance; support lookup, retention purges, and usage rollups make every request explainable from its reference; soft-threshold routing degrades gracefully under quota pressure; load tests assert the metered footprint in §13.6.

**Useful to know:** F2 (acceptance recording) is required before any capability may write to a clinical record, but is **not** a prerequisite for CP3 if the first capability uses `advisory_display` acceptance ([§7](#7-dependencies-outside-the-platform), Open Decision 1). The two are reconciled by §4.2.2: F2 freezes the mechanism against a registered demonstration target and an allow-list registry, so no product capability gains a clinical write until a manifest declares `human_accept_required`. F1 depends on D1 and D5 — evals need a real prompt and a real adapter. Completing F5 satisfies checkpoint **CP5**. Individual F slices may start as soon as their `Needs` column is met; the band as a whole is not strictly sequential.


| ID     | Slice                                           | Canonical             | Needs  | Done when                                                                                                                                                                                                                                                                                                |
| ------ | ----------------------------------------------- | --------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **F1** | Eval suite harness and first capability eval    | §13.5, A9             | D1, D5 | Golden cases run per capability in CI against fixtures and block a prompt change that regresses them; a scheduled live smoke set runs against pinned model versions                                                                                                                                      |
| **F2** | Acceptance recording RPC and client accept path | §4.2, §4.2.2, §4.1, A5 | E4, C3 | `public.record_ai_acceptance` delegates to an allow-listed existing domain RPC and writes the domain change, the `ai_accepted_output` row carrying the AI request reference, and the `audit_log` entry that joins them in one transaction, so the clinic audit log can explain a field's provenance. Proved against the registered demonstration target `visit_clinical_notes` → `public.save_visit_documentation` (§4.2.2), which promotes no capability to clinical writing. Required before any capability may write to a clinical record |
| **F3** | Support lookup, retention purges, usage rollups, and journal dashboards | §4.5, §8.9, §7.6, §7.7, §13.1, R-6, A13 | C3, B4 | An operator resolves a request reference to the full trace and the R2 envelope through one indexed D1 lookup and one `GetObject`; each retention class expires on its own horizon, the diagnostic envelope's horizon is per-capability, and an installation deletion is executable as a purge by installation id in both stores; a scheduled job produces `usage_rollup` from `usage_event` and a reconciliation pass reports requests with a terminal state but missing attempt rows or missing usage credit; the named diagnostics are answerable by query against the journal and rollups with no second metrics store — time to first token by provider, validation-failure rate by prompt version, repair rate by capability, fallback rate by provider, cost per capability per installation, quota rejection rate |
| **F4** | Soft-threshold degraded routing                 | §4.3.3, §8.8, §4.3.7  | D2, B4 | Crossing a soft quota threshold downgrades routing to the capability's degraded tier rather than refusing; exhaustion disables an additive feature and says so, and never hard-locks anything                                                                                                            |
| **F5** | Load and cost tests                             | §13.5, §13.6          | D7    | Guard latency at p95 under concurrency, D1 write headroom, and Durable Object throughput per installation are measured, and per-request R2 Class A operations and Durable Object round trips are asserted at one and two respectively                                                                    |




### 3.8 Band H — Conversational capabilities

> **Implementation reference:** [`implementation-references/07-band-h-implementation-reference.md`](implementation-references/07-band-h-implementation-reference.md) — plain-language account of what H1–H4 built, with diagrams and test commands (tip `24d1e7cc`, before review-comment remediation).

**What this band does:** Adds multi-turn conversational AI on top of the single-shot path. A capability may declare `interaction_mode: conversational` with transcript limits, permitted context keys, and a shared context-request schema; the validator enforces turn budgets; the composer renders prior turns as delimited typed data; the client holds the transcript locally and resupplies it per leg with a new idempotency key; journaling records `conversation_id` and `turn_ordinal` per leg without introducing a server-side conversation entity.

**Useful to know:** Everything amendment A14 introduces, and nothing before it — `interaction_mode` defaults to `single_shot`, so no existing button-invoked capability acquires behaviour from this band's existence. The band is fully determined by §6.7, §5.1, §5.2, §5.4, §5.5, and §8.10; it is placed late because it is the largest capability addition, not because it is under-specified. The nullable `conversation_id` / `turn_ordinal` columns were reserved in A5 so H3 does not require a schema migration.


| ID     | Slice                                       | Canonical                              | Needs          | Done when                                                                                                                                                                                                                                                    |
| ------ | ------------------------------------------- | -------------------------------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **H1** | Conversational manifest fields and context-request schema | §5.1, §5.7, §6.7.4, §6.7.2, §5.5, §5.4, §6.3, A14 | A2, A4, A6 | A manifest may declare `interaction_mode: conversational` with max history turns, max context rounds per turn, transcript size limit, and a permitted key set, interaction mode is fixed for the life of a capability version, and conversational-only fields are rejected on a `single_shot` manifest; one platform-owned `{key, arguments}` schema is shared by every conversational capability, `context_requested` is a terminal event kind and not a taxonomy code, `AwaitingContext` is terminal and immutable, and a `single_shot` client can never receive the fourth kind |
| **H2** | Transcript validation, conversation budgets, and composer rendering | §4.3.5, §6.7.1, §6.7.3, §4.3.6, §6.7.2 | C2, D1, D6, H1 | Turn ordering and declared turn shapes are validated, max history turns and max context rounds are counted from the submitted transcript alone, a breach produces `conversation_budget_exhausted`, the permitted key set is an allowlist enforced at the validator, and per-turn cost pre-flight prices the transcript with no new mechanism; the transcript renders as prior turns of delimited typed data on the same footing as context, the context-request schema is offered as a second permitted output shape alongside prose, and the validator accepts either |
| **H3** | Conversational journaling and client chat surface | §7.3, §6.7.1, §8.10, §4.1, §6.7 | C3, E2, E3, H1 | `conversation_id` and `turn_ordinal` are written per leg, a whole conversation is readable with one indexed query, each leg is independently admitted, journaled, and credited, and no conversation entity and no per-request state is introduced; the client holds the transcript locally, resupplies it per leg, resolves requested keys through the existing Resolver, appends the request and payload, submits the next leg with a new idempotency key, and discards the transcript when the conversation closes |
| **H4** | Conversation evals                          | §13.5, A9                              | F1, H2      | Scripted multi-leg conversations are scored per conversation: does the assistant request the right keys, stay inside the permitted set, and converge within the round budget |


### 3.9 Band J — Deferred compatibility machinery

> **Implementation reference:** [`implementation-references/08-band-j-implementation-reference.md`](implementation-references/08-band-j-implementation-reference.md) — plain-language account of what J1–J4 built, with diagrams and test commands (tip `37b82f0e`, before review-comment remediation).

**What this band does:** Adds the runtime behaviour for compatibility scenarios that have no audience yet: capability deprecation overlap windows, `context_required` self-healing for stale manifest caches, staged rollout and canary cohorts, and token-contract rotation with overlapping `ver` acceptance. The error codes, lifecycle states, and journal columns these features need were frozen early (DP-5); this band wires up the behaviour.

**Useful to know:** Deferred under DP-5 because there are no deployed clients, not because it is undesigned. Each slice's contract surface already exists from bands A–D, so these are behaviour-only additions. Build a slice when its trigger fires — the triggers are in the `Build when` column, not the band's position in the sequence. J2 explicitly does not apply to conversational capabilities.

**One exception to "behaviour-only" in this band:** J1's deprecate / retire mutations persist onto the lifecycle-overlay fields of `capability_grant` (§7.3 of the architecture reference). That entity is A5's, and per DP-5 those fields belong with the early contract surface — but if the shipped A5 migration predates the §5.1 / §7.3 lifecycle-overlay amendment, J1 carries one forward-only additive migration to add them. J1 introduces no new entity.


| ID     | Slice                                            | Canonical                | Needs          | Build when                                                                        | Done when                                                                                                                                                                                                                        |
| ------ | ------------------------------------------------ | ------------------------ | -------------- | --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **J1** | Capability deprecation and the overlap window    | §5.7, §12.4, A12         | C1, B2      | A client version exists in the field that a capability change could break         | Discovery announces deprecation with a successor before retirement is enforced; a deprecated version keeps serving for the configured window; retirement returns `capability_retired` so old clients prompt for an update        |
| **J2** | `context_required` self-healing round trip       | §8.4, §5.2               | C2, E2, E3 | A client's manifest cache can be stale relative to the platform              | A client receiving `context_required` refreshes its manifest, resolves the named keys, and resubmits **once** with the same idempotency key; a second `context_required` surfaces to the user with the request reference          |
| **J3** | Staged rollout and canary cohorts                | §12.4, §4.5, §13.4       | B2, D1, D2, F1 | A prompt, capability version, or routing policy has an audience that can be split | A new capability build, prompt artifact, or routing policy version is activated for a named cohort, promoted, or rolled back by deploy; every activation is a `control_audit` row with the operator identity              |
| **J4** | Token contract rotation with overlapping acceptance | §5.7, §5.6            | B1, B3 | The token contract needs its first change                                        | Two `ver` values are accepted simultaneously during a rotation window; tokens of the retired version are refused after it; rotation requires no re-enrollment                                                                     |


### 3.10 Band I — Live composition and request-path wiring

**What this band does:** Attaches the modules bands A–J already built onto the live Cloudflare Worker fetch handler and the first Flutter AI surface so a clinic installation can enroll, discover capabilities, submit a request, stream a draft, and look the request up by reference — without inventing new pipeline stages, contracts, or stores.

**Why this band exists:** Earlier slices froze each §4 component behind an injectable surface and deferred production wiring so a single Spec Kit review could stay inside one component group. The result matches DP-7's failure mode: suites that pass while `POST /v1/requests` still returns an adapter shell (no `eventSource`), discovery remains an in-process library, and the E4 hub leaves invoke idle. Band I closes that composition gap. It freezes **no** new contract ([§2.3](#23-the-no-rework-rule)); every requirement cites an existing §4 / §5 / §6 surface. Completing **I1** and **I3** reifies checkpoint **CP3** on the live paths.

**Useful to know:** I1 consumes the existing `src/pipeline` composer (`runGuard` / settle) and D4's stream broker — `runGuard` (through stage 9 journal) as the A6 **`preAccept`** gate and the broker / settle path as the post-accept **`eventSource`**. A6's original shell emitted `accepted` before calling `eventSource`; live composition requires the documented A6 contract extension (`specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md` §8): defer `accepted` until `preAccept` succeeds, and return taxonomy **HTTP** (no stream) on pre-accept guard failure. I1 may implement that deferred-`accepted` framing in `adapter.ts` as in-scope composition; it does not rewrite `src/pipeline` or the D4 broker modules, and it freezes no new contract. I2 exposes C1's `discover()` over HTTP and ensures the production config-cache D1 reader covers every entity kind the guard reads on a warm/cold isolate (installations, keys, entitlements, grants, kill switches, routing policy). I3 composes E2 and E3 onto E4. I4 is the thin operator + client glue required for a non-pending installation and for J2's self-heal on the live submit path; it is not Band G (no plan catalogue, billing, or usage-summary UI).


| ID     | Slice                                                      | Canonical                                      | Needs                                      | Done when                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------ | ---------------------------------------------------------- | ---------------------------------------------- | ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **I1** | Worker request orchestrator on `POST /v1/requests`         | §6.1 stages 1–16, §4.3.1, §4.3.10, §5.5, §6.4 | A6, B3, B4, C1, C2, C3, D1, D2, D3, D4, D6 | `worker.ts` supplies a production `eventSource` to the protocol adapter so a live `POST /v1/requests` runs the §6.1 sequence end to end: guard stages 1–10 (including one Quota DO admission and one D1 journal insert), route/invoke, stream relay with heartbeats and disconnect abort, validate/repair, exactly one terminal SSE event, then credit and post-response detail; a guard rejection returns the taxonomy error with **no** `ai_request` row; the fake adapter path satisfies the CP3 Worker half; real adapters (D5/D7) are selected only by routing policy; no per-request server-side state and no second DO or R2 object per request |
| **I2** | Discovery HTTP route and production config-cache readers   | §5.5, §4.3.4, §4.3.2, §13.4                    | A5, C1                                     | Capability discovery is reachable over HTTP for an authenticated installation, returns only granted active manifests, supports etag/version revalidation, and never requires a capability id from the client beyond the installation's entitlements; the production D1 config reader serves every kind the guard and resolver consult on the request path (installations, keys, entitlements, grants / lifecycle overlay, kill switches, active routing policy, token contracts) so a cold isolate still pays exactly one D1 read pattern already frozen by A5 |
| **I3** | Live client invoke on the first AI feature surface         | §4.1, §5.5, §5.4, §6.4, A11                    | E2, E3, E4, I1, I2                         | The Flutter `/ai` visit-summary (or equivalent) host composes production AAT mint and HTTPS submit adapters from E2, resolves required context keys through E3, submits with a stable idempotency key, consumes the SSE stream to a terminal event, renders provisional draft with no commit affordance until `completed`, and displays the request reference on every failure; non-enrolled installations still hide affordances and make no network probe; platform unreachability remains a normal degraded state |
| **I4** | Entitle-and-grant operator path and live `context_required` self-heal | §4.5, §7.3, §8.4, §5.2                | B2, I3, J2                                 | An operator-authenticated control action activates an enrolled installation's entitlement and capability grants (and the budget fields admission already reads) so stages 3 and 8 can admit a real request — without introducing a plan catalogue, billing period close, or usage-summary UI (those remain Band G); the E2 submit path hosts J2's `context_required` self-heal so a stale manifest refreshes, resolves the named keys, and resubmits **once** with the same idempotency key |



### 3.11 Coverage rule

A slice's suite must cover, with no exceptions:

1. The happy path of every requirement.
2. **Every error code the slice can emit**, one case each.
3. Every branch of every rule the slice states.
4. Every invariant and every prohibition it inherits from [§6.4](#64-what-implementation-must-never-do).
5. Every boundary the architecture names — size limits, caps, TTLs, skew windows, retry ceilings.

Coverage is **behavioural, not line-based**; a line-coverage percentage is not evidence. Where a case
below says *spy*, the assertion is on the number or absence of calls, because several of this
platform's invariants are about work *not* done. The cases in
[§3.12](#312-required-test-cases-per-slice) are a floor, not a ceiling.

Every slice's suite joins CI permanently. A checkpoint ([§5](#5-review-checkpoints)) requires every
prior suite green, not just the latest.

### 3.12 Required test cases per slice

#### 3.12.1 Band A

| ID | Layer | Required cases |
| --- | --- | --- |
| **A1** | Infra / config | Each environment deploys; health endpoint returns build and environment identity; no binding is shared between two environments; a missing required binding fails startup rather than at first use |
| **A2** | Unit + contract | One case per §5.4 code asserting its HTTP status, retryability, and quota-consumption flag; unrecognised code → `internal_error`; every error body carries reference, trace id, and retry-safety; reference format valid and unique across a large generation run; supplied trace id reaches every log line; absent trace id is generated |
| **A3** | Contract | Round-trip each canonical element; a provider-shaped field name fails the guard test; chunk kinds exhaustive (`text_delta`, `partial_structured`, `usage`, `provider_note`); terminal flag appears exactly once per chunk sequence |
| **A4** | Contract + build | A valid manifest loads with all ten field groups; one failure case per omitted or malformed group; in-place edit of a published version fails the build; omitted `interaction_mode` defaults to `single_shot`; conversational-only fields are rejected on a `single_shot` manifest |
| **A5** | Contract + migration + unit (spy) | *Context keys:* valid key accepted; malformed format rejected; storage-named key rejected; unknown key version rejected; a conforming payload validates and one case per shape violation (type, cardinality, units, missing field). *Schema:* migrations apply cleanly to an empty database; schema snapshot matches; one presence case per §7.3 entity; request-reference index exists and is unique; `conversation_id` and `turn_ordinal` are nullable; re-running migrations is a no-op. *Config cache:* cold isolate performs exactly one D1 read; warm isolate performs zero I/O; TTL expiry triggers exactly one refetch; one case per cached entity kind; a D1 miss surfaces as a typed failure rather than an empty cache entry |
| **A6** | Integration | Oversized body → `request_too_large` before any other work; one case per header parsed and per malformed header; stream opens with `accepted` carrying the reference; heartbeat emitted while idle; exactly one terminal event for each of `completed`, `failed`, `cancelled`; abort mid-stream still yields exactly one terminal event; no duplicate terminal event under any path |

#### 3.12.2 Band B

| ID | Layer | Required cases |
| --- | --- | --- |
| **B1** | SQL / RLS | *Keystore:* `anon` read denied; `authenticated` read denied; the issuing function reads successfully; rotation adds a key without removing the previous one; a token signed by the previous key still verifies inside its validity window; a revoked key is rejected. *Issuer:* one case per §5.6 claim populated; `scopes` derived from RBAC and unaffected by a caller attempting to supply them; expired or absent session rejected; issuance row written; issuer rate limit trips; `exp` within the configured minutes |
| **B2** | Integration | Enroll writes `installation`, `installation_key`, `entitlement`, `control_audit`; one case per lifecycle action (suspend, resume, rotate, delete) asserting the audit row and operator identity; non-operator credentials rejected; duplicate enrollment handled deterministically |
| **B3** | Unit + integration (spy) | *Identity:* valid token accepted; one rejection case each for bad signature, wrong audience, expired, not-yet-valid inside skew, outside skew, unknown issuer, suspended installation; the principal cannot be mutated by a later stage; swapping the verifier implementation changes no outcome. *Rate limiting:* one case per composite key tripping independently; `retry_after` returned; counter incremented with correct dimensions per rejection; no `ai_request` row created on rejection; counters flush bucketed, never one row per event. *Entitlement:* AI-disabled installation; plan tier too low; capability not granted; one case per kill-switch scope (global, capability, installation, provider); warm isolate performs no D1 read |
| **B4** | DO unit + concurrency + integration (spy) | *Durable Object:* fresh `jti` accepted, repeated `jti` rejected; new idempotency key accepted, repeat returns the prior record; budget exhaustion; concurrency ceiling; credit adjusts counters correctly including partial usage; N parallel admissions produce an exact final count; ephemeral entries expire in place. *Admission stage:* exactly one Durable Object fetch per request; a repeated idempotency key returns the original state and starts no second inference; expired token with the same key → `unauthenticated` (§6.2); Durable Object unavailable → capped grace then rejection; grace usage is reconciled afterwards |

#### 3.12.3 Band C

| ID | Layer | Required cases |
| --- | --- | --- |
| **C1** | Unit + integration | *Resolver:* exact version pin resolves; unknown id → `capability_unknown`; retired → `capability_retired`; killed → `capability_disabled`; deprecated still serves; the returned manifest cannot be mutated. *Discovery:* only granted and active manifests returned; etag revalidation returns not-modified; a changed manifest changes the etag; an entitlement-gated capability is absent for an ineligible installation |
| **C2** | Unit (spy) | *Validator:* complete valid context passes; one case per required key missing, each listing exactly the missing keys in `context_required`; one case per shape violation → `context_invalid`; oversize key rejected; an undeclared key is provably absent from the composer input; org or branch mismatch against the token rejected; absent optional key passes. *Pre-flight:* under ceiling passes; over ceiling → `request_too_large`; the estimate includes the capability's max output tokens; no egress occurs on rejection |
| **C3** | Integration (ordering + spy) | *Request row:* the row exists before the provider is invoked; one terminal-state case each for `completed`, `failed`, `cancelled`, `rejected`; every §6.3 transition timestamped; a guard-rejected request produces no row; the row survives a failed generation. *Post-response:* exactly one R2 `PutObject` per request; the envelope contains all four sections; one `ai_attempt` row per attempt; exactly one `usage_event`; a failure here does not fail the request; all of it runs after the terminal event. *Get-request:* completed → state plus validated result; failed → state plus error code and no content; cancelled → state only; unknown reference → not found; exactly one indexed query |

#### 3.12.4 Band D

| ID | Layer | Required cases |
| --- | --- | --- |
| **D1** | Build + golden + unit | *Registry:* a manifest-pinned hash resolves to its artifact; an altered artifact fails the build; a missing artifact fails the build; no prompt text is present in any D1 table; the prompt version is recorded on the journal row. *Composer:* composed request matches the golden for a fixture capability; changing the output schema changes the derived format instruction; context is rendered as delimited typed data; an instruction embedded in context does not act as an instruction (R-10); max tokens, stop conditions, and language constraints present; no provider-shaped field in the output |
| **D2** | Unit | *Port and fake:* the fake produces success, one case per retryable class, one per terminal class, truncation, and a malformed response; the classification contract is exhaustive over the error taxonomy. *Router:* chain ordered by policy; one filtering case per capability requirement (structured support, context window, language, latency class); installation override applied; identical inputs produce an identical chain; the selection reason is recorded; a prior failure does not change the next request's chain |
| **D3** | Integration | A retryable failure is retried to the cap then falls back; a terminal failure is not retried; jitter is applied; every attempt is journaled separately; an exhausted chain → `provider_unavailable`; a fallback after partial streaming emits the regenerating event and discards the earlier text; the retry budget is never exceeded |
| **D4** | Integration (spy) | *Streaming:* chunks relayed in order; heartbeat emitted during provider silence; one case per incremental guard (length ceiling, stop sequence, system-prompt leak) aborting the stream and failing terminally; the full guard set runs on the assembled text; the terminal event carries the validated payload. *Cancellation:* disconnect aborts the in-flight provider fetch via its abort signal; state becomes `cancelled`; partial usage is credited; the journal row is complete; no per-request state object is created; cancel before the first token and cancel mid-stream are separate cases |
| **D5** | Adapter fixtures | Request-mapping golden; stream normalization; usage extraction; one case per provider error class mapped to the taxonomy; malformed response; truncated response; timeout; credentials absent from every emitted log and journal record |
| **D6** | Unit (ordering) + integration | *Validator:* valid output passes; parse failure; schema violation; one case per declared business rule; one case per safety guard (leaked instruction, refusal, empty, truncated, injection echo); the four phases run in the stated order; invalid content is never emitted. *Repair:* repair allowed → one re-ask with errors appended → success; repair disallowed → immediate `validation_failed`; repair fails → `validation_failed`; the attempt cap is enforced and journaled; repair cost is counted against the request. *Output modes:* `structured` emits `partial_structured` events all flagged provisional; the terminal event carries the whole validated document; `structured_atomic` emits progress only; a client ignoring all chunks still receives the correct result; the terminal payload is not assembled from chunks |
| **D7** | Adapter fixtures + evals | The full D5 case list against the second provider; the provider is added by a routing-policy edit with no pipeline diff; fallback ordering honoured; capability evals pass — the eval case is written against F1's harness and lands with F1, not with D7 alone (§3.5 row D7) |

#### 3.12.5 Band E

| ID | Layer | Required cases |
| --- | --- | --- |
| **E1** | CI lint | A fixture containing a prompt-like string fails the build; a provider name fails; a model identifier fails; a clean tree passes; the guard covers every client source path |
| **E2** | Flutter unit + integration | Token acquired and cached; one re-mint on `unauthenticated` then success; no re-mint loop; the idempotency key is stable across transport retries of the same action; stream consumed to its terminal event; cancel closes the stream; one case per terminal code proving no retry; last-N references retained; an unknown error code is treated as `internal_error` |
| **E3** | Flutter unit + SQL / RLS + contract | *Resolver:* a key list resolves to a payload; an unknown key surfaces a typed failure; the API exposes no capability id; the cache is screen-scoped and discarded on dispose. *RPC:* returns the declared shape; RLS denies out-of-scope rows; the RPC takes no AI-specific parameter; the returned shape matches the key shape published in A5. *Contract:* every declared key of every active manifest is resolvable; a manifest requiring an unknown key fails the suite |
| **E4** | Flutter widget (spy) | *Surface:* provisional content is visually distinct; no commit control exists before `completed`; accept and discard both behave; failure displays the request reference; provisional content does not survive a rebuild or restart. *Degraded mode:* a non-enrolled installation shows no affordances and makes no network call; an unreachable platform renders a normal state, not an error dialog; enrolled and reachable shows affordances |

#### 3.12.6 Band F

| ID | Layer | Required cases |
| --- | --- | --- |
| **F1** | CI | The golden set passes on the current prompt; a deliberately regressed prompt fails; scores are recorded per run; the scheduled live smoke set runs against pinned model versions |
| **F2** | SQL + Flutter | Acceptance writes the domain change and the request reference together or not at all; the clinic `audit_log` entry is present and resolves in both directions between the domain row and the reference (§4.2.2); the discard path writes nothing; unaccepted content is never persisted; a `target_key` outside the registry is rejected |
| **F3** | Integration + scheduled job + query tests (spy) | *Support lookup:* a reference resolves to trace plus envelope in exactly one D1 query and one `GetObject`; an expired envelope still resolves its metadata; a non-operator is denied. *Retention:* one expiry case per retention class; the per-capability diagnostic horizon is honoured; purge by installation id clears both stores; nothing inside its horizon is deleted. *Rollups:* rollup totals equal ledger sums; reconciliation flags a terminal request missing attempt rows; flags missing usage credit; a re-run is idempotent. *Dashboards:* one case per named diagnostic returning correct values against a seeded journal; no second metrics store is written |
| **F4** | Integration | Crossing the soft threshold selects the degraded target; hard exhaustion returns `quota_exhausted` with the admin path and disables the feature without locking anything; below-threshold traffic is unaffected |
| **F5** | Load | Guard p95 within tens of milliseconds at target concurrency; exactly one R2 Class A operation and two Durable Object requests per request under load; D1 write headroom measured; Durable Object throughput per installation measured |

#### 3.12.7 Band H

| ID | Layer | Required cases |
| --- | --- | --- |
| **H1** | Contract + build + integration | *Manifest:* a conversational manifest loads with all four extra fields; one failure case per omitted field; conversational fields on a `single_shot` manifest are rejected; changing interaction mode in place fails the build; a permitted key set naming an unknown key fails. *Context request:* the shared schema validates a conforming request and rejects each malformed form; `context_requested` is absent from the error taxonomy; `AwaitingContext` is terminal and cannot transition; a `single_shot` capability can never emit the fourth kind; still exactly one terminal event per leg |
| **H2** | Unit + golden | *Transcript:* valid transcript passes; out-of-order `turn_ordinal` rejected; malformed turn shape rejected; history-turn limit breached → `conversation_budget_exhausted`; consecutive context rounds at the transcript tail breached → same code; a key outside the permitted set is dropped even when requested by the model; oversized transcript → `request_too_large` from the existing pre-flight; a trimmed transcript is accepted but bounded by admission (R-22). *Composer:* transcript renders as delimited typed prior turns; an instruction inside a user turn does not act as an instruction (R-10); a prose answer validates; a context request validates; output that is neither fails; the composer draws no distinction between chat text and clinical free text |
| **H3** | Integration (spy) + Flutter | *Journaling:* `conversation_id` and `turn_ordinal` written per leg; one indexed query returns a whole conversation ordered; each leg admitted and credited independently; a `context_requested` leg is credited with actual usage; no conversation table and no per-request state object created. *Client:* transcript held locally and resupplied per leg; requested keys resolved through the existing Resolver with no capability branching; each leg uses a new idempotency key; the transcript is discarded on close; closing one leg's stream cancels only that leg; the conversation survives a cancelled leg |
| **H4** | Evals | A scripted conversation converges within the round budget; one case where the assistant must request the correct key; one case proving it cannot obtain a key outside the permitted set; scoring is per conversation, not per turn |

#### 3.12.8 Band J

| ID | Layer | Required cases |
| --- | --- | --- |
| **J1** | Integration | Discovery marks a deprecated version with its successor; a deprecated version still serves inside the window; after retirement the same request returns `capability_retired`; retirement is journaled with the operator identity |
| **J2** | Flutter integration | A stale client receiving `context_required` refreshes, resolves, and resubmits once with the same idempotency key and succeeds; a second `context_required` stops and surfaces the request reference; no automatic third attempt; conversational capabilities never take this path |
| **J3** | Integration | A cohort receives the new build while others receive the previous one; promotion moves all cohorts; rollback restores the previous build; every activation writes a `control_audit` row; the journal records which version served each request |
| **J4** | Unit + SQL | Both `ver` values verify during the rotation window; a retired `ver` is refused afterwards; a token minted under the new contract carries every claim; rotation requires no re-enrollment |

#### 3.12.9 Band I

| ID | Layer | Required cases |
| --- | --- | --- |
| **I1** | Workers integration (spy) | *Happy path:* `POST /v1/requests` through `SELF.fetch` (or equivalent) with a valid AAT opens `accepted`, streams fake-provider chunks, ends with exactly one `completed`, writes one `ai_request` before invoke, one R2 envelope after, and exactly two DO round trips (admit + credit). *Guard rejects:* one HTTP case each for unauthenticated, rate-limited, forbidden capability, capability unknown/retired/disabled, context_required, context_invalid, request_too_large, quota_exhausted — each asserting **no** journal row and no provider call. *Idempotency:* repeated key returns the prior state and starts no second inference. *Cancel:* client disconnect aborts the in-flight provider fetch, terminal state `cancelled`, partial usage credited when present. *Invariants:* no per-request Durable Object or other server-side request state; provider selection changes only via routing-policy data |
| **I2** | Workers integration | *Discovery HTTP:* granted active manifests returned for an enrolled installation; etag not-modified; changed manifest changes etag; ungated capability absent for ineligible plan; unauthenticated → taxonomy unauthorized. *Config readers:* one presence case per request-path entity kind through the production D1 reader; cold isolate still performs a single config read pattern; a miss is a typed failure, not an empty grant set that silently admits |
| **I3** | Flutter widget + integration | *Live host:* enrolled + reachable installation mints an AAT, resolves context keys, submits over HTTPS to the Worker, renders provisional draft, enables no commit control before `completed`, and shows the request reference on failure. *Degraded:* non-enrolled still makes no Worker probe; unreachable still renders the normal-state banner. *Spy:* production mint and submit ports are the ones composed on the hub (not test fakes left wired by default) |
| **I4** | Integration + Flutter | *Entitle:* operator activate/grant writes entitlement and grant rows and a `control_audit` entry with operator identity; pending enroll still fails entitlement until activated; non-operator rejected. *Self-heal:* live submit path refreshes on first `context_required`, resubmits once with the same idempotency key, and surfaces the reference on a second `context_required`; conversational capabilities never take this path |

#### 3.12.10 Band G

| ID | Layer | Required cases |
| --- | --- | --- |
| **G1** | SQL / migration + integration | *Catalogue:* migrations apply cleanly to an empty database and the schema snapshot matches, including `plan`, `credit_price`, and the `entitlement` credit-budget column; one case per plan CRUD mutation asserting the `control_audit` row and operator identity; non-operator rejected. *Assignment:* assigning a plan populates credit budget, request guard, `max_cost_class`, soft threshold, and capability set in one audited mutation; an explicit per-installation override of a plan value is recorded as such. *Cache:* plans and entitlements are served through the config cache with the A5 read pattern — one D1 read cold, zero warm |
| **G2** | DO unit + integration (spy) | *Debit:* settlement debits exactly the manifest's declared `quota_weight`; a conversational leg debits per leg; a cancelled request debits the full declared weight; a guard rejection debits nothing and writes no journal row. *Admission:* exhausted credit budget → `quota_exhausted` with `reset_at`; crossing the soft threshold on the credit ratio sets the `degraded` flag F4 routes on. *Invariants:* token and cost counters still settle actuals unchanged; exactly two Durable Object round trips per request; the credit RPC gains fields without changing the meaning of any existing field (§2.3) |
| **G3** | Workers integration + Flutter widget (spy) | *Endpoint:* an authenticated installation reads current-period credits consumed against budget, sourced live from the Quota DO, and prior periods from `usage_rollup`; unauthenticated → taxonomy unauthorized; the response carries credits only — no provider prices, no token or cost actuals. *Client:* the gauge renders consumed-versus-budget; a non-enrolled installation hides it with no network probe; platform unreachability renders as a normal state, not an error dialog |
| **G4** | Scheduled job + integration | *Close:* period close writes exactly one immutable `invoice` row per active installation, priced through the `credit_price` version active for that period; a re-run is idempotent; a zero-consumption period issues no invoice. *Price list:* activating a new price-list version is an audited operator mutation and never reprices a closed period. *Evidence:* an invoice resolves to its `usage_rollup` rows, and any line can be traced to request references; payment collection is out of scope and no payment-provider call exists |

#### 3.12.11 Band V

| ID | Layer | Required cases |
| --- | --- | --- |
| **V1** | E2E (Worker + SQL) | Every automatable scenario ID in `docs/testing/catalog/` has exactly one test named `Sxx-yyy — <title>`; every non-automatable ID is an `it.skip` citing its Register 5 row; no test without an ID and no ID without a test; `[SEED]` setup only where the scenario's journey justifies it; the full suites (`vitest.e2e`, `backend/tests/catalog/run.sh`) are green |
| **V2** | E2E + code fixes | Every item in `docs/testing/catalog/implementation-work-order.md` lands as code fix + test rewrite + catalog text in one commit per item; no test is weakened to go green; the work order's own definition of done (its §12) is met, including the skip-count reduction and both full suites green |
| **V3** | Viewer build + smoke | The viewer builds (`tsc -b && vite build`); every stage 00–12 page, the guard-pipeline view, and the secrets page render against the dev plugin; each operation card executes its real control-plane or gateway call against a running local stack and shows the raw request/response |
| **V4** | Viewer build + smoke | *Commercial pages:* plan catalogue CRUD drives the real G1 control mutations; the per-installation credit gauge renders the G3 endpoint's consumed-versus-budget; the invoice list and detail render G4's invoices with their rollup evidence. *Stage X:* the cron and failure-journey operations are drivable from the viewer. All of it against the local stack, with raw request/response visible |


### 3.13 Band G — Commercial surface

**What this band does:** Builds the commercial layer the product decisions recorded in amendment
A15 define: a small plan catalogue mapping a plan name to its economics, credit-denominated monthly
quota debited at each capability's declared `quota_weight`, a usage-summary endpoint with a simple
in-app gauge, and billing period close with platform-issued invoices. Payment collection stays
outside the platform.

**Useful to know:** This band was held coarse under DP-8 until its product inputs existed; A15
settled them (OD-2, OD-15, and the §12.3 billing row). G2 **extends** B4's frozen admission
contract — the entitlement snapshot gains `credit_budget`, the credit RPC gains a `credits` debit,
and the period counters gain `creditsUsed` — which [§2.3](#23-the-no-rework-rule) permits, because
adding a field is extension and no existing field changes meaning; the token and cost counters
remain for reconciliation and billing evidence. G1 and G2 are sequential; G3 and G4 may proceed in
parallel once their `Needs` are met. Nothing here is on the request path's latency budget: G2 rides
the existing two Durable Object round trips, and G3/G4 are read surfaces and scheduled jobs.

**Code sync (verified against `ai-platform/` as of 2026-09):**
- The `entitlement` table (`migrations/20260731120000_platform_schema.sql`) carries `request_quota`,
  `token_budget`, `cost_budget`, period bounds, and `plan` as a free string — **no** credit column,
  and no `plan` / `credit_price` / `invoice` tables exist. G1's migrations are greenfield and
  forward-only per A5's rule.
- `usage_event.quota_weight INTEGER` already exists — the ledger needed no change, as A15 states.
- `src/pricing/` is the **bundled token-rate artifact** (`control/pricing/platform-default/1.json`)
  that prices provider-reported tokens into ledger cost units. It is *not* the A15 `credit_price`
  list; G4 must keep the two apart (A15 item 5 says which answers which question).
- G1 extends I4's entitle endpoint (`src/control/entitle.ts`,
  `POST /control/installations/:id/entitle`) with plan-catalogue assignment; the entitlement stage
  (`src/entitlement/`) reads `entitlement.plan` as a string via `planTierMeetsMinimum`, so the
  catalogue changes what entitlement *management* reads, not the guard — exactly as OD-15 promised.
- G3's endpoint is **installation-authenticated and client-facing** — a different audience from the
  existing operator-only `GET /control/installations/:id/quota` (`src/control/quota-inspect.ts`),
  whose DO inspect path it may reuse. The operator endpoint stays operator-only.
- G4 consumes F3's `src/rollup/` output; the close is a new scheduled job, not a rollup change.

| ID     | Slice                                              | Canonical                              | Needs        | Done when                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------ | -------------------------------------------------- | -------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **G1** | Plan catalogue and credit-denominated entitlement  | §4.5, §7.3, §4.3.2, A15                | A5, B2       | Forward-only migrations create `plan`, `credit_price`, and the `entitlement` monthly credit-budget column, pinned by a schema snapshot test; operator plan CRUD and plan-based entitlement assignment are audited control-plane mutations; assignment from a plan populates every economics field in one mutation; plans and entitlements are served through the config cache with the A5 warm/cold read pattern                                                            |
| **G2** | Declared-weight credit debit in admission          | §4.3.3, §5.1, §8.8, A15                | G1, B4, F4   | The stage-15 credit call debits the manifest's declared `quota_weight` (per leg for `conversational`), cancelled requests debit in full, guard rejections debit nothing; admission answers credit-budget exhaustion with `quota_exhausted` and crosses the soft threshold on the credit ratio into the `degraded` flag; token and cost counters settle actuals unchanged; the two-round-trip and no-journal-on-rejection invariants hold                                     |
| **G3** | Usage summary endpoint and in-app gauge            | §7.6, §4.1, A11, A15                   | G2, E4       | An authenticated installation reads current-period credits consumed against budget (live from the Quota DO) and prior periods from `usage_rollup`; the response carries credits only; the Flutter client renders a simple gauge, hides it for non-enrolled installations without probing, and renders platform unreachability as a normal state                                                                                                                              |
| **G4** | Billing period close and invoice generation        | §7.3, §4.5, §12.3, A15                 | G1, F3       | A scheduled close freezes the period's `usage_rollup` and writes exactly one immutable `invoice` per active installation, priced through the `credit_price` version active for that period; re-runs are idempotent; zero-consumption periods issue no invoice; price-list activation is an audited operator mutation that never reprices a closed period; every invoice line traces to request references; no payment-provider integration exists                          |


### 3.14 Band V — Verification tooling: scenario catalog and viewer

**What this band does:** Builds and maintains the two verification surfaces that sit *around* the
platform rather than inside it: the E2E scenario catalog suite (`docs/testing/catalog/`, 818
scenarios across stages 00–X, implemented under `ai-platform/test/e2e/` and
`backend/tests/catalog/`), and the `ai-platform-viewer/` dev console that lets a human drive every
stage of the journey against a running local stack.

**Why this band is different:** every other band implements named components of
`01-ai-platform.md` §4. Band V traces to **§13.5 (testing strategy)** and to the catalog documents
themselves, which are the spec for V1–V2. The viewer is development and operator tooling: it
freezes no platform contract, ships to no clinic, and appears in no architecture component group —
its slices cite the control-plane and HTTP surfaces they drive rather than a §4 component. It is
sliced here so the work is visible in one sequence, not because the architecture owns it.

**Useful to know (code-verified 2026-09):** V1 is **implemented** — phase 15 declared the suite
green with coverage complete (707 tests, 40 files, 0 gaps; `ai-platform/test/e2e/reports/phase-15.md`).
V2 is **implemented** — the work order's code fixes are in the source (spot-verified: BUG-01's
`grace_admission_queue` purge delete in `src/retention/index.ts`, BUG-03's manifest-loading
`settleMissingHandoffInternalError` in `src/worker.ts`). V3 is **largely implemented** —
`ai-platform-viewer/` already covers stage pages 00–12, the guard-pipeline view, and secrets;
V4 adds what Band G and stage X need.

| ID     | Slice                                            | Canonical                            | Needs          | Done when                                                                                                                                                                                                                                                                                                                                                          |
| ------ | ------------------------------------------------ | ------------------------------------ | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **V1** | E2E scenario catalog suite                       | §13.5; `docs/testing/catalog/`       | I1, I2         | Every automatable scenario in the catalog has exactly one ID-tagged test; every Register 5 non-automatable ID is a cited `it.skip`; `[SEED]` discipline holds; both full suites (`vitest.e2e`, `backend/tests/catalog/run.sh`) are green. **Status: implemented** (phase-15 report)                                                                                |
| **V2** | Scenario catalog remediation and coverage close  | §13.5; the catalog work order        | V1             | `docs/testing/catalog/implementation-work-order.md` is executed to its own definition of done: every code bug fixed with its pinning test rewritten in the same commit, weak tests strengthened, coverage gaps closed, catalog text sweep applied, no test weakened to go green, both full suites green. **Status: implemented** (code fixes spot-verified at HEAD) |
| **V3** | Viewer foundations and stage pages               | — (tooling; drives §4.5, §5.5)       | B2, I1, I2     | The `ai-platform-viewer/` app builds and lets a developer drive stages 00–12, the guard pipeline, and secrets against the local stack, with raw request/response visible for every operation. **Status: largely implemented** — remaining work is whatever the smoke pass in [§3.12.11](#31211-band-v) surfaces                                                    |
| **V4** | Viewer commercial surface and stage-X page       | — (tooling; drives A15 surfaces)     | V3, G1, G3, G4 | The viewer gains plan-catalogue CRUD against G1's control mutations, a per-installation credit gauge reading G3's endpoint, and an invoice list/detail view over G4's output; the stage-X cron and failure journeys are drivable; everything runs against the local stack with raw request/response visible                                                          |


---



## 4. Bands Not Yet Decomposed

One band is deliberately left coarse. The reason is not "the architecture has not decided" —
everything the architecture owns is decided and sliced in bands A–J plus the live-composition band I
and the commercial band G; only K stays coarse. (Band G was held here until amendment A15 settled
its product inputs — quota unit and period, plan structure, overage policy, and the billing
boundary — and is now decomposed in [§3.13](#313-band-g--commercial-surface).)

### 4.1 Band K — Explicitly later

Held under §12.5 and §9.14 of the architecture document, each with its own written trigger:
health-based provider routing, out-of-band cancellation and stream resume, region-aware routing, D1
sharding, an on-LAN OpenAI-compatible adapter, per-context-key redaction, per-installation model
preferences, asynchronous or batch execution, fine-tuning, and vector search.

Not decomposed because these are **deliberately undesigned**. Each is a deferral with a written
trigger, and slicing one now would be a soft commitment to build it. Adding one requires citing the
evidence its trigger names, not the argument for it (R-20).

---



## 5. Review Checkpoints

A checkpoint is a point at which the *composition* of the preceding slices is examined, rather than
any single slice. It is not a gate on shipping, because nothing ships (DP-1); it is a gate on
continuing to build in the same direction.


| #       | After                             | Question the checkpoint answers                                                                                                                                                                                                                                                                                                     |
| ------- | --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **CP1** | A6                                | Do the frozen contracts compose at build time? Manifest, context key shapes, canonical representation, and error taxonomy are mutually consistent, and the contract tests in §13.5 pass                                                                                                                                             |
| **CP2** | B4, reified by I1                 | Can a request be authenticated, admitted, and correctly rejected with no inference? The guard's I/O budget — one Durable Object round trip, one D1 insert — is measurable and met. Band B proves the modules; I1 proves them on live `POST /v1/requests`                                                                                                                                           |
| **CP3** | I1 with the fake adapter, plus I3 | **The falsification checkpoint (DP-7).** One thread runs from a Flutter button through the whole guard, a composed prompt, a fake provider, a stream, and a terminal event, and back to a rendered draft — on the live Worker and composed E4 host, not only in injectable harnesses. This is the earliest point at which a wrong contract becomes visible, and the last point at which correcting one is cheap |
| **CP4** | D7 and F1                        | Is the inference path complete and provider-independent? A second provider is added by adapter and policy alone, with no pipeline change — the claim in §12.4 that the whole design rests on                                                                                                                                        |
| **CP5** | F5                                | Is the platform operationally honest? Every request is explainable from its reference, costs are bounded and measured, and the metered footprint matches §13.6.1                                                                                                                                                                    |
| **CP6** | I4                                | Is the local stack operable end to end? An enrolled installation can be entitled and granted, discovery and submit work over HTTP, and a stale-manifest `context_required` self-heals once on the live client path                                                                                                                   |


At CP2, CP4, CP5, and CP6, also perform the review R-19 and R-20 call for: diff the implemented
components against §4, and confirm nothing from §9.14 was added without its trigger. At CP6,
confirm Band I introduced no new pipeline stage and no new contract field — only composition.

---



## 6. Spec Authoring Protocol

This section is the instruction set for whichever model authors a slice's `spec.md` and `plan.md`.

### 6.1 The authoring model's job is transcription, not design

`01-ai-platform.md` has already made the decisions. A slice spec is correctly written when it can be
produced by citing sections and attaching acceptance tests to their statements. If the spec contains
original architectural reasoning, something has gone wrong: either the slice is too large, or a
decision is missing from the architecture document and is being invented in the wrong place
([§6.3](#63-stop-conditions)).

### 6.2 Required sections in every AI platform slice spec


| Section                      | Contents                                                                                                                                                        |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Implements**               | The exact sections of `01-ai-platform.md` this slice realises, copied from the `Canonical` column of the slice's row                                            |
| **Freezes**                  | Contracts this slice establishes for the first time. Later slices may extend these and may not rewrite them ([§2.3](#23-the-no-rework-rule))                    |
| **Consumes**                 | Contracts frozen by earlier slices that this slice uses. Changing any of them is out of scope by definition                                                     |
| **Requirements**             | Restatements of the cited architecture, each with acceptance criteria expressed as named test cases ([§2.2](#22-the-completion-criterion))                      |
| **Test plan**                | The slice's row in [§3.12](#312-required-test-cases-per-slice) expanded into named tests, plus any case the coverage rule in [§3.11](#311-coverage-rule) adds  |
| **Out of scope**             | Explicit exclusions, including anything from a neighbouring slice that would be tempting to finish while nearby ([§2.4](#24-every-slice-states-its-exclusions)) |
| **Open decisions relied on** | Any of the fourteen decisions in §15 whose recommended default this slice assumes                                                                               |




### 6.3 Stop conditions

Authoring must stop and escalate to an architecture change, rather than proceed, when any of these is
true:

1. A requirement cannot be traced to a section of `01-ai-platform.md` or to a recommended default in
  §15.
2. Satisfying the slice appears to require changing a contract listed in its **Consumes** section.
3. The slice cannot be given acceptance criteria as test cases.
4. The task list exceeds roughly 40 tasks, or the slice touches a component outside the component
  group named in its row in [§3](#3-the-slice-sequence) without an explicit reason recorded in the
  plan.

Escalation means amending `01-ai-platform.md` first, then returning. The amendment is reviewed as a
contract change, which is the discipline §13.4 already requires of every capability and context-key
change.

### 6.4 What implementation must never do

Restated here because these are the failure modes a weak implementer produces by default, and each
maps to a named risk:

- Add a mechanism from §9.14 because it looks prudent (R-20).
- Put prompt text, a provider name, or a model identifier anywhere in the Flutter client (R-12) — E1
exists to make this fail the build.
- Add a second round trip to the Quota Durable Object, or a second R2 object per request (§7.5,
§13.6).
- Journal a guard rejection as a request, or write a D1 row per stream chunk (§7.5).
- Introduce per-request server-side state of any kind (§4.4, §9.7).
- Assemble a final result from stream chunks on the client, or make provisional content committable
(§6.4, A5).

---



## 7. Dependencies Outside the Platform

Three prerequisites sit outside the AI platform's own work and are on someone else's schedule.


| Dependency                                                        | Blocks         | Note                                                                                                                                                                                                     |
| ----------------------------------------------------------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The clinic schema and RPCs that can satisfy the first context key | A5, E3 | The Context Contract can only declare keys the clinic side can actually produce. Confirm which of the §5.2 example keys the current schema supports before A5 fixes the first key's shape       |
| Supabase RBAC tables stable enough to derive AI capability scopes | B1             | `scopes` are derived server-side from RBAC and never supplied by the client, so the RBAC model must be settled before the token contract is                                                              |
| Selection of the first capability                                 | A5, D1, E4 | Open Decision 1, whose recommended default is one non-clinical-record capability. Its output mode should be `prose` and its acceptance mode `advisory_display`, so that F2 is not a prerequisite for CP3. F2 itself is unblocked either way: it ships against §4.2.2's registered demonstration target |


The constitution amendment recorded in §14 — registering the new deployable component and its
boundary in `.specify/memory/constitution.md` — should be made before A1, not after, so that the
first slice is not itself architectural drift.

### 7.1 Repository layout

The gateway lives in **`ai-platform/`** at the repository root, alongside `frontend/` and
`backend/`: Worker source, D1 migrations, prompt artifacts, and tests. It is deliberately a sibling
rather than a subdirectory of `backend/`, because it is a separate deployable with a separate store
and no write path into Supabase (§3.4, §14).

The Spec Kit templates in `.specify/templates/` predate this directory and name only `frontend/` and
`backend/` in their path conventions. A slice's plan extends the tree rather than forcing Worker code
into `backend/`.