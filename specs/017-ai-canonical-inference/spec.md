# Feature Specification: Canonical inference representation

**Feature Branch**: `ai/018-a3-canonical-inference-representation`

**Created**: 2026-07-30

**Status**: Draft

**Input**: Slice `A3` — Canonical inference representation (delivery plan §3.2 row A3).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

§5.3 Canonical inference representation; §9.10 OpenAI-compatible wire format as the internal representation.

### Freezes

- The four canonical element shapes of §5.3 (canonical request, canonical stream chunk, canonical result, canonical error) and their field names, frozen as code/types so later slices (D2 composer, D3 provider port, D6 stream broker, D9 validator) extend rather than rewrite them.
- The four chunk kinds — `text_delta`, `partial_structured`, `usage`, `provider_note` — as a closed, exhaustive set (§5.3).
- The provider-shape guard: nothing upstream of the adapters may contain a provider-shaped field (§5.3, §9.10).

### Consumes

- A1's Worker skeleton and environment bindings (§13.4, §1.4). This slice adds only types and contract tests inside `ai-platform/`; it changes no A1 binding or environment contract.
- The error taxonomy of A2 (§5.4) is referenced but not modified: the canonical error element's `taxonomy code` and `retryability` fields are holders whose valid values are A2's frozen set.

### Open decisions relied on

None. §5.3 fully specifies the canonical elements; §9.10 records a rejected alternative and adds no decision A3 must assume.

## Clarifications

### Session 2026-07-30

- Q: How should the provider-shape guard enumerate the canonical types' field names so provider-shaped drift fails the contract test? → A: A runtime field-name manifest as source of truth; the TS types derive from it, and the guard test asserts the manifest equals the §5.3 names and rejects any provider-shaped or extra key. No separate lint or AST tooling. `[implementation choice — no §citation]`
- Q: How should the round-trip contract tests serialize and parse the canonical elements? → A: A thin owned JSON codec driven by the manifest; round-trip test asserts §5.3 key names survive byte-for-byte and no extra keys are emitted. Field-name drift is directly observable. `[implementation choice — no §citation]`
- Q: Where do the field-name manifest and owned JSON codec live within ai-platform/src/? → A: A single `contracts/canonical.ts` exporting the manifest, types derived from it, and the codec, plus a co-located `canonical.test.ts` for the contract suite. Two files; the plan may split later under §2.3 if a consumer needs its own import boundary. `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Canonical inference representation (Priority: P1)

A reviewer of the platform's internal types wants every component upstream of the provider adapters to speak only a provider-neutral canonical representation (request, stream chunk, result, error), and a contract test fails if any field name is provider-shaped — so the core stays stable while provider quirks remain quarantined inside adapters (§5.3, §9.10).

**Why this priority**: A3 sits immediately after A1 because the canonical representation is the contract every later inference-path slice (D2 composer, D3 provider port, D6 stream broker, D9 validator) consumes; freezing it as typed code before those slices start constrains a weak implementer against provider-shaped drift (DP-4, §3.2 Needs = A1).

**Independent Test**: A contract test proves the four canonical elements round-trip, the four chunk kinds are exhaustive, exactly one chunk per sequence carries the terminal flag, and a provider-shaped field name fails the guard test (delivery plan §3.2 Done when; §3.11.1 row A3).

**Acceptance Scenarios**:

1. **Given** the four canonical element types of §5.3, **When** each element is serialized and parsed back, **Then** the round-tripped value equals the original (field names and contents unchanged).
2. **Given** a field name that is provider-shaped (e.g. `messages`, `completion`, `n`, `frequency_penalty`), **When** the provider-shape guard runs, **Then** the contract test fails, because nothing upstream of the adapters may contain a provider-shaped field (§5.3, §9.10).
3. **Given** the canonical stream chunk type, **When** the set of chunk kinds is enumerated, **Then** it is exactly `{text_delta, partial_structured, usage, provider_note}` and no other kind is accepted (§5.3).
4. **Given** any valid chunk sequence emitted by a stream, **When** the sequence is scanned, **Then** exactly one chunk carries the terminal flag — never zero, never more than one (§5.3 terminal flag; §5.5 rule 4 one-terminal-event invariant).

### Test plan

Expanded from delivery plan §3.11.1 row A3 (Layer: Contract). Layer names follow §13.5 of `17-ai-platform.md`.

| Test name | Layer | Case (§3.11.1 A3) |
| --- | --- | --- |
| `T-A3-01` round-trip canonical request | Contract | Round-trip each canonical element |
| `T-A3-02` round-trip canonical stream chunk | Contract | Round-trip each canonical element |
| `T-A3-03` round-trip canonical result | Contract | Round-trip each canonical element |
| `T-A3-04` round-trip canonical error | Contract | Round-trip each canonical element |
| `T-A3-05` provider-shaped field name rejected | Contract | A provider-shaped field name fails the guard test |
| `T-A3-06` chunk kinds exhaustive | Contract | Chunk kinds exhaustive (`text_delta`, `partial_structured`, `usage`, `provider_note`) |
| `T-A3-07` terminal flag exactly once per sequence | Contract | Terminal flag appears exactly once per chunk sequence |

### Edge Cases

- Which field names count as *provider-shaped*: the guard treats any name drawn from common provider wire formats (e.g. `messages`, `completion`, `n`, `frequency_penalty`, `top_p`, `logprobs`) as provider-shaped and rejects it from upstream types. A field present in the canonical table (§5.3) by its canonical name is never rejected.
- Unknown chunk kind: a chunk whose `kind` is not one of the four must be rejected; the canonical stream chunk type is a closed set (§5.3).
- Zero-terminal sequences: a sequence of zero chunks must be rejected by the exactly-one-terminal invariant (§5.3 terminal flag; §5.5 rule 4).
- Multiple-terminal sequences: a sequence with the terminal flag on more than one chunk must be rejected (§5.5 rule 4 — one terminal event, never inferred from silence).
- Reserved-but-unused fields: the canonical request lists "tool/function declarations (reserved for future)" (§5.3); A3 defines the placeholder shape but wires no behaviour — wiring belongs to later bands.
- This slice emits no platform error codes: it is a contract-only slice with no request handler, so no §5.4 code is produced by A3. The canonical error element's `taxonomy code` field accepts only codes A2 freezes; an unrecognized value is rejected by the type, mirroring A2's "unrecognised code → `internal_error`" rule.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: An internal, provider-neutral representation MUST sit between the composer and the adapters, such that everything upstream of the adapters speaks only this representation (§5.3).
- **FR-002**: Nothing upstream of the adapters MAY contain a provider-shaped field (§5.3).
- **FR-003**: The canonical request MUST contain ordered role-tagged message parts, an output format directive (free text / JSON with schema), sampling constraints, max output tokens, stop conditions, tool/function declarations (reserved for future), a stream flag, a deadline, and correlation ids (§5.3).
- **FR-004**: The canonical stream chunk MUST contain a sequence number, a kind, a payload, and a terminal flag (§5.3).
- **FR-005**: The chunk `kind` MUST be one of `text_delta`, `partial_structured`, `usage`, `provider_note` — a closed, exhaustive set (§5.3).
- **FR-006**: The canonical result MUST contain final content, usage counters (input/output/cached tokens), the provider+model actually used, a finish reason, a provider request id, and a timing breakdown (§5.3).
- **FR-007**: The canonical error MUST contain a taxonomy code, retryability, a provider-native code and message (for diagnostics only), and whether the attempt consumed budget (§5.3).
- **FR-008**: The canonical form MUST be modelled on the common subset but owned by this platform, so most adapters stay thin while provider divergences are quarantined inside adapters (§9.10).
- **FR-009**: A contract test MUST fail if any field name in an upstream canonical type is provider-shaped (delivery plan §3.2 Done when; §3.11.1 A3).

### Key Entities *(include if feature involves data)*

This slice defines the four canonical contract *types* of §5.3: Canonical request, Canonical stream chunk, Canonical result, and Canonical error. They are in-memory/Wire representation types inside `ai-platform/`, not D1 entities — A3 writes no D1 rows and defines no persistence schema.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: A3 is an internal contract slice with no user-facing behaviour and no per-clinic data; its clinic fit is the platform-wide benefit of a stable core that lets prompts, providers, and models change without a client release (§1.1 design goal), serving clinics that cannot absorb client releases for every model change.
- **Layer Placement**: Touches only `ai-platform/` (the Cloudflare Worker) — TypeScript types and contract tests inside the gateway. It touches neither `backend/` (Supabase) nor `frontend/` (Flutter). Per §14, the gateway holds no domain logic and no business data and is an explicitly non-primary, additive, always-optional component; this slice adds nothing but representation types and respects that boundary.
- **Data Integrity & Security**: A3 defines no data store, no RLS, no write path, and no credentials. The canonical request's "correlation ids" carry the request reference and trace id established by A2, but do not introduce new identifiers or secrets.
- **Failure Handling**: A3 emits no runtime failures — it is contract types and tests. Its guard test is a build/contract-time failure that prevents provider-shape drift before later slices consume the types. No AI-availability degraded mode is relevant to a contract slice.

## Out of Scope

- Slices this one touches but does not implement: **A2** (the error taxonomy whose codes populate the canonical error's `taxonomy code` field — A2 freezes the set, A3 only holds a reference to it); **D2** (prompt composer) and **D3** (provider port/fake adapter), which will consume the canonical types; **D6** and **D9**, which will relay and validate canonical chunks. None of their behaviour is built here.
- Adapters and any provider-specific mapping: §9.10 quarantines provider divergences inside adapters; A3 defines only the upstream canonical form, never an adapter (§5.3).
- Prompt text, provider names, or model identifiers in canonical types — these would violate the provider-neutral rule (§5.3) and the prohibition R-12.
- Any mechanism from §9.14 added because it looks prudent (R-20).
- Prompt text, provider name, or model identifier anywhere in the Flutter client (R-12).
- A second round trip to the Quota Durable Object or a second R2 object per request (§7.5, §13.6).
- Journaling a guard rejection as a request, or writing a D1 row per stream chunk (§7.5).
- Per-request server-side state of any kind (§4.4, §9.7).
- Client-side assembly of a final result from chunks, or committable provisional content (§6.4, A5).
- Behaviour for the "tool/function declarations (reserved for future)" field beyond its placeholder shape.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A contract test passes proving each of the four §5.3 canonical elements round-trips without field loss or renaming (delivery plan §3.2 Done when).
- **SC-002**: A contract test fails on any provider-shaped field name introduced into an upstream canonical type (delivery plan §3.2 Done when; §3.11.1 A3).
- **SC-003**: The chunk-kind set is provably exhaustive over `{text_delta, partial_structured, usage, provider_note}` — a chunk of any other kind is rejected (§3.11.1 A3).
- **SC-004**: A contract test proves exactly one chunk per sequence carries the terminal flag, including under abort (§3.11.1 A3; §5.5 rule 4).

## Assumptions

- The canonical element field names and contents are taken verbatim from the §5.3 table; no field is added, removed, renamed, or inferred beyond that table.
- The implementer places the types in the Worker source under `ai-platform/`, consistent with the repo layout in delivery plan §7.1, rather than forcing Worker code into `backend/`.
- A2's frozen error-code set is the authoritative enumeration the canonical error's `taxonomy code` field accepts; A3 does not re-derive it.
- Chunk-kind exhaustiveness and the terminal-flag invariant are enforced as type/contract tests, since A3 defines no runtime request path that could observe them dynamically.