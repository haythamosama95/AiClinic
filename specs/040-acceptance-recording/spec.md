# Feature Specification: Acceptance recording RPC and client accept path

**Feature Branch**: `ai/040-f2-acceptance-recording`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `F2` — "Acceptance recording RPC and client accept path" (delivery plan §3.7, band F).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.7, row F2):

> §4.2, §4.2.2, §4.1, A5

### Freezes

Contracts this slice establishes for the first time:

- The **`public.record_ai_acceptance` RPC contract** — signature
  `(p_request_reference text, p_target_key text, p_target_args jsonb) RETURNS public.rpc_result`,
  following the established `public` wrapper → `auth_internal.record_ai_acceptance`
  `SECURITY DEFINER` pattern (F4). On success, `rpc_result.data` carries
  `{"acceptance_id", "table_name", "record_id", "audit_log_id"}` merged with the
  delegated RPC's own `data`. On failure it returns the delegated RPC's `error_code` and
  `error_message` unchanged — acceptance adds **no new error vocabulary** (§4.2.2; §4.2;
  delivery plan §3.7 Done when).
- The **allow-list registry** `ai_internal.acceptance_targets(target_key, domain_function,
  table_name)` as the only source of which existing `public` domain RPC a `p_target_key`
  may invoke. A function name is never client-supplied; registering a target is a
  migration; an unregistered `p_target_key` is rejected before anything is written
  (§4.2.2; delivery plan §3.11.6 F2).
- The **`public.ai_accepted_output` table** with the named columns, types, constraints,
  uniqueness on `(table_name, record_id, ai_request_reference)`, and indexes on
  `ai_request_reference` and `(table_name, record_id)` fixed in §4.2.2 — storing the AI
  request reference as `text` (not a foreign key to D1), and deliberately omitting
  capability id, model, provider, prompt, token counts, cost, and request state (§4.2.2;
  §4.2 boundary note).
- The **atomic acceptance transaction**: the delegated domain write, the
  `ai_accepted_output` row, and one `audit_log` entry with `action = 'ai.acceptance_record'`
  (with `new_data_json` carrying `{"ai_request_reference", "acceptance_id"}` and
  `ai_accepted_output.audit_log_id` pointing back) are one function call and therefore one
  transaction — "domain change and request reference together or not at all" is a property
  of the RPC. Provenance resolves in both directions between the domain row and the
  reference (§4.2.2; delivery plan §3.7 Done when; §3.11.6 F2).
- The **registered demonstration target** `visit_clinical_notes` →
  `public.save_visit_documentation` (writing `public.visit_clinical_notes`), exercised by
  SQL and Flutter tests for atomicity, provenance, and the discard path. That target is an
  ordinary domain RPC — a `public` wrapper delegating to
  `auth_internal.save_visit_documentation` (`SECURITY DEFINER`), which asserts
  `visits.edit_soap`, enforces branch scope and optimistic concurrency, and writes the
  visit's clinical note row. Registering that target grants no product capability the right
  to write; that right comes only from a manifest declaring acceptance mode
  `human_accept_required` (Open Decision 1 / §5.1). Until then, the E4 surface's
  `advisory_display` accept remains non-writing (§4.2.2; delivery plan §3.7 Done when; §7).
- The **single shared clinical acceptance path** for every capability (including later
  conversational acceptance under Open Decision 14): one RPC, registry-driven targets, no
  second acceptance path by construction (§4.2.2; Open Decision 14; A5).
- The **client clinical accept path** as a tested library under
  `frontend/lib/features/ai/acceptance/` (port / client / controller), exercised by
  harness and automated tests: after terminal success, an explicit human accept for a
  clinical-content capability invokes `public.record_ai_acceptance`; discard writes
  nothing; unaccepted content is never persisted; no auto-commit of AI output. F2 ships
  that library, not a production Feature Surface wiring — Open Decision 1 keeps the first
  capability on `advisory_display`; production UI integration awaits the first
  `human_accept_required` capability (§4.1 AI Feature Surfaces; A5; delivery plan
  §3.11.6 F2).

Later slices may extend these and may not rewrite them (delivery plan §2.3). Required
before any capability may write to a clinical record (delivery plan §3.7 Done when).
These Freezes are what Open Decision 14 later Consumes.

### Consumes

Contracts frozen by the slices in `Needs` (E4, C3). Changing any is out of scope by
definition:

- **From E4 (first AI feature surface and degraded mode)**: the **AI Feature Surfaces**
  component — provisional/draft styling, no commit control before terminal success,
  explicit accept/discard affordances, request-reference display on failure, and the rule
  that provisional content is never persisted or exported (§4.1 Freezes in E4). F2 ships
  the clinical accept library beside those surfaces and proves it against the
  demonstration target in harness/tests; it does not wire a production clinical-accept
  surface, and does not redefine provisional styling, degraded-mode UX, or the first
  capability's `advisory_display` accept behaviour that deliberately does not write a
  clinical record (Open Decision 1; E4; §4.2.2).
- **From C3 (journal writer, post-response detail, and get-request)**: the **request
  reference** as the join key between platform journal and clinic acceptance, and the
  **get-request / terminal validated result** contract a completed request exposes to the
  client (C3 Freezes). F2 stores that reference on `public.ai_accepted_output.ai_request_reference`
  at human accept; it does not write D1, invent a second journal of acceptance on the
  platform, or change get-request semantics. The platform journals that a terminal result
  was delivered, not that a human accepted it (A5; §4.2 boundary note; §4.2.2).

### Open decisions relied on

- **Open Decision 1** (which capability is built first, and which are
  `human_accept_required` versus display-only): recommended default is one
  non-clinical-record capability with acceptance mode `advisory_display`, so F2 is not a
  prerequisite for CP3. F2 freezes the mechanism against the registered demonstration
  target; only a manifest declaring `human_accept_required` promotes a capability to
  writing (§4.2.2; delivery plan §7).
- **Open Decision 14** (may chat output be moved into a clinical record, and through which
  acceptance path?): recommended default is only through the same human acceptance RPC —
  `public.record_ai_acceptance` with a registered acceptance target, no chat-specific path
  (A5; §4.2.2). F2 freezes that shared RPC; later conversational acceptance Consumes it
  rather than inventing a second path.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Acceptance recording RPC and client accept path (Priority: P1)

As clinic staff on the Flutter desktop app, after a validated AI result is available on an
AI Feature Surface (E4) and the platform has journaled that result under a request
reference (C3), I explicitly accept AI-generated content into a clinical record through
`public.record_ai_acceptance`: the RPC resolves an allow-listed `p_target_key` to an
existing domain RPC, and in one transaction writes the domain change, the
`ai_accepted_output` row carrying the AI request reference, and the `audit_log` entry
(`action = 'ai.acceptance_record'`) that joins them bidirectionally — so a field's
provenance is explainable. If I discard instead, nothing is written; unaccepted content is
never persisted; an unregistered `target_key` is rejected before any write. The mechanism
is proved against the registered demonstration target `visit_clinical_notes` →
`public.save_visit_documentation` (table `public.visit_clinical_notes`) and promotes no
product capability to clinical writing (A5; §4.2; §4.2.2; §4.1).

**Why this priority**: F2 sits where it does because its `Needs` (E4, C3) are the point at
which a surface can offer accept/discard against a terminal validated result and a durable
request reference exists to store alongside the domain write. Without those, acceptance
could not close the audit loop A5 requires. Band F places this before any capability may
write to a clinical record; it is not a prerequisite for CP3 when the first capability
uses `advisory_display` (delivery plan §3.7 Useful to know; Open Decision 1; §4.2.2).

**Independent Test**: `public.record_ai_acceptance` delegates to an allow-listed existing
domain RPC and writes the domain change, the `ai_accepted_output` row carrying the AI
request reference, and the `audit_log` entry that joins them in one transaction, so the
clinic audit log can explain a field's provenance. Proved against the registered
demonstration target `visit_clinical_notes` → `public.save_visit_documentation` (§4.2.2),
which promotes no capability to clinical writing. Required before any capability may write
to a clinical record (delivery plan §3.7 Done when). Provable by SQL + Flutter automated
tests (DP-3; §3.11.6 row F2).

**Acceptance Scenarios**:

1. **Given** a completed AI request with a validated terminal payload and its request
   reference, and the registered demonstration target `visit_clinical_notes` resolving to
   `public.save_visit_documentation` (writing `public.visit_clinical_notes`), **When** the
   caller invokes `public.record_ai_acceptance` with that reference,
   `p_target_key = 'visit_clinical_notes'`, and valid `p_target_args`, **Then** the domain
   change, the `ai_accepted_output` row, and the `audit_log` entry are written together or
   not at all. *(Acceptance writes the domain change and the request reference together or
   not at all)*
2. **Given** a successful acceptance write, **When** the clinic `audit_log` and
   `ai_accepted_output` are inspected, **Then** an `audit_log` entry with
   `action = 'ai.acceptance_record'` is present and provenance resolves in both directions
   between the domain row `(table_name, record_id)` and the AI request reference
   (§4.2.2). *(The clinic `audit_log` entry is present and resolves in both directions
   between the domain row and the reference)*
3. **Given** validated (or still-visible draft) AI content on the surface, **When** the
   user discards, **Then** the discard path writes nothing — no domain change, no
   `ai_accepted_output` row, and no acceptance `audit_log` entry. *(The discard path
   writes nothing)*
4. **Given** AI content that the user has not accepted into a clinical record
   (provisional, discarded, or merely displayed), **When** durable clinic storage and
   clinical records are inspected, **Then** that unaccepted content is never persisted as
   a clinical write. *(Unaccepted content is never persisted)*
5. **Given** a call to `public.record_ai_acceptance` with a `p_target_key` that is not a
   row in `ai_internal.acceptance_targets`, **When** the RPC runs, **Then** the call is
   rejected before anything is written — no domain change, no `ai_accepted_output` row,
   and no `audit_log` entry. *(A `target_key` outside the registry is rejected)*

### Test plan

Layer: **SQL + Flutter** (delivery plan §3.11.6, row F2). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `acceptance_writes_domain_change_and_request_reference_together` | SQL + Flutter | Acceptance writes the domain change and the request reference together or not at all via `record_ai_acceptance` against `visit_clinical_notes` → `public.save_visit_documentation` (§3.11.6 F2; §4.2.2; Done when) |
| T2 | `acceptance_audit_log_bidirectional_provenance` | SQL | The clinic `audit_log` entry (`action = 'ai.acceptance_record'`) is present and resolves in both directions between the domain row and the reference (§3.11.6 F2; §4.2.2) |
| T3 | `discard_path_writes_nothing` | SQL + Flutter | The discard path writes nothing — no domain change, no `ai_accepted_output`, no acceptance audit (§3.11.6 F2; §4.1) |
| T4 | `unaccepted_content_never_persisted` | SQL + Flutter | Unaccepted content is never persisted as a clinical write (§3.11.6 F2; §4.1 Must not; A5) |
| T5 | `unregistered_target_key_rejected` | SQL | A `target_key` outside `ai_internal.acceptance_targets` is rejected before anything is written (§3.11.6 F2; §4.2.2) |

Coverage rule additions (delivery plan §3.10) inherited by this slice:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T6 | `acceptance_rpc_does_not_store_ai_request_state` | SQL (spy) | Clinic DB gains the acceptance fact only — no prompts, providers, quotas, or AI request state beyond `ai_accepted_output` columns named in §4.2.2 (§4.2 boundary note; §4.2.2; §3.10) |
| T7 | `clinical_accept_never_auto_commits` | Flutter (spy) | No path auto-commits AI output into a clinical record without the explicit human accept action (A5; §4.1 Must not; delivery plan §6.4) |
| T8 | `advisory_display_accept_unchanged` | Flutter (spy) | First-capability `advisory_display` accept from E4 still does not invoke the clinical acceptance recording write (Open Decision 1; §4.2.2; Consumes E4) |
| T9 | `delegated_rpc_errors_pass_through_unchanged` | SQL | On delegated domain RPC failure, `record_ai_acceptance` returns that RPC's `error_code` / `error_message` unchanged and writes nothing (no new error vocabulary) (§4.2.2) |
| T10 | `demonstration_target_does_not_promote_capability` | SQL + contract | Registry row `visit_clinical_notes` → `public.save_visit_documentation` (table `public.visit_clinical_notes`) exists for proof only; no product capability gains `human_accept_required` writing from this slice (§4.2.2; Open Decision 1; Done when) |

### Edge Cases

- **Partial write failure**: if the domain change cannot be committed with the
  `ai_accepted_output` row and `audit_log` entry in the same transaction, none of the
  three persist (together or not at all) (§4.2.2; §3.11.6 F2; Done when).
- **Unregistered `p_target_key`**: rejected before anything is written; no domain change,
  no `ai_accepted_output`, no `audit_log` (§4.2.2; §3.11.6 F2).
- **Delegated domain RPC failure**: acceptance returns the delegated RPC's `error_code`
  and `error_message` unchanged; acceptance adds no new clinic-side error vocabulary and
  no entry in the platform error taxonomy (§4.2.2).
- **Discard after terminal success**: discard clears the surface path and writes no domain
  row, no `ai_accepted_output`, and no acceptance-linked audit entry (§4.1; §3.11.6 F2).
- **Unaccepted provisional or display-only content**: never enters a clinical record and
  is never persisted as accepted output (§4.1 Must not; A5; §3.11.6 F2).
- **Auto-commit attempts**: no client or RPC path may auto-commit AI output into a
  clinical record; clinical-content acceptance requires the explicit human accept recorded
  with the request reference (A5; §4.1 Must not).
- **Client-supplied function names**: forbidden — only `p_target_key` is accepted; the
  registry alone maps key → domain function (§4.2.2).
- **Platform vs clinic audit split**: the acceptance recording RPC does not journal
  acceptance into D1 and does not require the gateway to learn clinic schema; the clinic
  holds acceptance (`audit_log` + domain row + `ai_accepted_output`) and stores only the
  request reference as the AI-shaped join key (§4.2 boundary note; §4.2.2; Consumes C3).
- **Error codes**: this slice introduces no new AI-platform taxonomy error codes and no
  new clinic acceptance error vocabulary; failures of the delegated write use that RPC's
  existing codes; unregistered-key rejection is a pre-write reject without inventing a
  platform taxonomy entry (§4.2.2).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The clinic backend MUST provide `public.record_ai_acceptance(p_request_reference text, p_target_key text, p_target_args jsonb) RETURNS public.rpc_result` as the single shared AI acceptance recording RPC. `(§4.2.2; §4.2)`
- **FR-002**: The RPC MUST follow the established `public` wrapper → `auth_internal.record_ai_acceptance` `SECURITY DEFINER` pattern, where the definer half writes `ai_accepted_output` and the append-only `audit_log`, and the clinical write is delegated to an allow-listed existing domain RPC that keeps its own authorization. `(§4.2.2; §4.2)`
- **FR-003**: `p_target_key` MUST resolve in allow-list registry `ai_internal.acceptance_targets(target_key, domain_function, table_name)` to exactly one existing `public` domain RPC; a function name MUST never be client-supplied; registering a target MUST be a migration. `(§4.2.2)`
- **FR-004**: An unregistered `p_target_key` MUST be rejected before anything is written. `(§4.2.2; delivery plan §3.11.6 F2)`
- **FR-005**: On success, `rpc_result.data` MUST carry `{"acceptance_id", "table_name", "record_id", "audit_log_id"}` merged with the delegated RPC's own `data`; on failure the RPC MUST return the delegated RPC's `error_code` and `error_message` unchanged — acceptance MUST add no new error vocabulary. `(§4.2.2)`
- **FR-006**: The RPC MUST persist the request reference on additive table `public.ai_accepted_output` with columns `id` (uuid PK), `organization_id` (uuid NOT NULL → organizations), `branch_id` (uuid NULL → branches), `table_name` (text NOT NULL), `record_id` (uuid NOT NULL), `ai_request_reference` (text NOT NULL with the §8.9-format CHECK named in §4.2.2), `accepted_by` (uuid NOT NULL → auth.users), `accepted_at` (timestamptz NOT NULL DEFAULT now()), and `audit_log_id` (uuid NOT NULL → audit_log); unique on `(table_name, record_id, ai_request_reference)`; indexed on `ai_request_reference` and on `(table_name, record_id)`. `(§4.2.2)`
- **FR-007**: Deliberately absent from `ai_accepted_output`: capability id, model, provider, prompt, token counts, cost, and request state — the clinic stores the handle, not the request. `(§4.2.2; §4.2 boundary note)`
- **FR-008**: In the same transaction as the delegated domain write and the `ai_accepted_output` row, the RPC MUST write one `audit_log` entry with `action = 'ai.acceptance_record'`, `table_name` and `record_id` set to the domain row just written, and `new_data_json` carrying `{"ai_request_reference", "acceptance_id"}`; `ai_accepted_output.audit_log_id` MUST point back at that entry. `(§4.2.2)`
- **FR-009**: Accepting AI content into a clinical record MUST write the domain change, the `ai_accepted_output` row, and the `audit_log` entry together or not at all — a property of the RPC transaction, not a discipline asked of callers. `(§4.2.2; delivery plan §3.7 Done when; §3.11.6 F2)`
- **FR-010**: Provenance MUST resolve in both directions: from the field via `audit_log` by `(table_name, record_id)` to the reference, and from a reference via `ai_accepted_output` to the field and its audit entry. `(§4.2.2; delivery plan §3.11.6 F2)`
- **FR-011**: The mechanism MUST be proved against registered demonstration target `visit_clinical_notes` → `public.save_visit_documentation` (writing `public.visit_clinical_notes`); registering that target MUST NOT promote any product capability to clinical writing — that right comes only from a capability declaring acceptance mode `human_accept_required` in its manifest. `(§4.2.2; Open Decision 1; delivery plan §3.7 Done when)`
- **FR-012**: Every clinical-content capability MUST require an explicit human accept action recorded in the clinic DB with the AI request reference; AI output MUST remain advisory and MUST never auto-commit into a clinical record. `(A5)`
- **FR-013**: The clinical accept library under `frontend/lib/features/ai/acceptance/` MUST expose explicit accept and discard; accept invokes `public.record_ai_acceptance`; discard MUST write nothing; unaccepted content MUST never be persisted as a clinical write. AI Feature Surfaces that declare clinical accept (`human_accept_required`) MUST use that library — F2 ships the library and harness/tests, not a production Feature Surface. `(§4.1; A5; delivery plan §3.11.6 F2)`
- **FR-014**: AI Feature Surfaces MUST NOT persist provisional content and MUST NOT auto-commit AI output. `(§4.1; A5)`
- **FR-015**: The acceptance recording addition MUST be additive clinic-backend surface area; it MUST NOT change existing table semantics. `(§4.2)`
- **FR-016**: The clinic database MUST gain no knowledge of prompts, providers, quotas, or AI request state beyond the two AI-shaped facts named in §4.2 (token minting capability and human acceptance of AI output here). `(§4.2 boundary note)`
- **FR-017**: The Flutter clinical accept path MUST NOT embed prompt text, model names, provider names, or AI business rules — matching the §4.1 acceptance test for client-side components. `(§4.1)`
- **FR-018**: This slice MUST NOT pull clinical-record writes onto capabilities whose acceptance mode is display-only / `advisory_display` under Open Decision 1; those surfaces retain E4 behaviour and do not require F2 for CP3. `(Open Decision 1; §4.2.2; delivery plan §7; Consumes E4)`
- **FR-019**: A second acceptance path MUST be impossible by construction — enabling a new clinical capability adds a registry row, never another acceptance RPC; later conversational acceptance MUST reuse this exact RPC (Open Decision 14). `(§4.2.2; Open Decision 14)`

### Key Entities

- **`ai_internal.acceptance_targets`**: allow-list registry mapping `target_key` →
  `domain_function` + `table_name`; the only source of which domain RPC acceptance may
  invoke (§4.2.2).
- **`public.ai_accepted_output`**: clinic-side acceptance row holding
  `(table_name, record_id)`, `ai_request_reference`, `accepted_by` / `accepted_at`, and
  `audit_log_id` — the join key to the platform journal without holding a request row
  (§4.2.2; A5).
- **`audit_log` acceptance entry**: append-only clinic audit row with
  `action = 'ai.acceptance_record'` joining the domain write to the request reference in
  the same transaction (§4.2.2; A5).
- **Demonstration target `visit_clinical_notes`**: registry proof target for
  `public.save_visit_documentation` writing `public.visit_clinical_notes`; does not
  promote product capability writing (§4.2.2; Open Decision 1).

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Human-gated acceptance of advisory AI into clinical records serves
  small-to-mid multi-branch clinics without introducing hospital-scale decision engines or
  auto-commit of model output. AI remains additive; clinics can refuse accept and continue
  manual documentation (A5; constitution I, IV, V).
- **Layer Placement**: This slice touches **`backend/` (Supabase / PostgreSQL)** for
  `public.record_ai_acceptance`, `ai_internal.acceptance_targets`,
  `public.ai_accepted_output`, delegated domain write, and `audit_log`, and
  **`frontend/` (Flutter)** for the clinical accept/discard library under
  `frontend/lib/features/ai/acceptance/` (harness/tests; production Feature Surface
  wiring awaits `human_accept_required`) (§4.2; §4.2.2; §4.1). It does **not** place
  acceptance logic in `ai-platform/` (Cloudflare Worker): the gateway has no write path
  into Supabase and journals delivery, not human acceptance (§4.2 boundary note;
  §4.2.2). The §14 acknowledgement that the gateway is a non-primary, additive component
  (no domain logic, no business data, no write path into Supabase, always optional) is
  preserved — F2 reinforces that boundary by keeping clinical acceptance entirely on the
  clinic side, and by routing clinical writes through existing domain RPCs
  (constitution III / §14).
- **Data Integrity & Security**: Domain correctness stays in PostgreSQL: the delegated
  domain RPC keeps its own authorization, validation, triggers, and RLS; acceptance grants
  no privilege the clinician did not already have (§4.2.2). Atomicity of domain write +
  `ai_accepted_output` + `audit_log` is a transaction property of the RPC (constitution
  III). Acceptance is human-gated (constitution IV; A5). Tenant/branch scope is enforced
  via `organization_id` / `branch_id` on `ai_accepted_output` and existing RLS on the
  delegated write (§4.2.2).
- **Failure Handling**: If acceptance cannot complete atomically, no partial clinical
  write or orphaned reference is left (§4.2.2; §3.11.6 F2). Unregistered targets and
  delegated failures leave no write. Discard and non-accept leave clinical workflows
  unchanged. Platform unavailability does not invent an acceptance path — without a
  validated terminal result and request reference from prior slices, clinical accept is
  simply not offered; AI failure must not block non-AI clinical work (constitution V;
  Consumes E4 degraded mode without redefining it).

## Out of Scope

Neighbouring slices and work this slice must not pull forward:

- **E4** — first AI feature surface, provisional styling, degraded mode, and
  `advisory_display` accept that does not write a clinical record (Consumes; do not
  rewrite).
- **C3** — journal writer, R2 envelope, get-request endpoint, and platform-side request
  state (Consumes; do not write D1 or redefine get-request).
- **F1 / F3 / F4 / F5** — eval harness, support lookup / retention / rollups, soft-threshold
  routing, load and cost tests.
- **§4.2.1 / B1** — clinic-side signing mechanism, installation keystore, and AI token
  issuer RPC (named in §4.2 but not this slice's Done when).
- **§5.1 manifest assignment of `human_accept_required`** — remains Open Decision 1; F2
  does not promote any product capability to clinical writing (§4.2.2).
- **H3 / Open Decision 14 follow-on** — conversational chat surface wiring; F2 freezes the
  shared acceptance RPC and registry for later Consumes, not the chat UI.
- **A second acceptance RPC or chat-specific acceptance path** — forbidden by §4.2.2 and
  Open Decision 14.
- **Removed targets** — `visit_plan_details` / `public.save_visit_plan_details` are not the
  demonstration target and MUST NOT be registered or tested as such (§4.2.2 amended).

Prohibitions from delivery plan §6.4:

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

- **SC-001**: Automated SQL (+ Flutter where the accept action is driven from the client)
  tests prove acceptance against `visit_clinical_notes` writes the domain change and the AI
  request reference together or not at all (T1).
- **SC-002**: Automated SQL tests prove a successful acceptance produces an
  `audit_log` entry with `action = 'ai.acceptance_record'` that resolves bidirectionally
  between the domain row and the reference (T2).
- **SC-003**: Automated SQL + Flutter tests prove discard writes nothing (T3).
- **SC-004**: Automated SQL + Flutter tests prove unaccepted content is never persisted as
  a clinical write (T4).
- **SC-005**: Automated SQL tests prove an unregistered `target_key` is rejected before
  any write (T5).
- **SC-006**: Automated tests prove clinical accept never auto-commits, that
  `advisory_display` accept remains non-writing, that delegated errors pass through
  unchanged, and that the demonstration target promotes no product capability (T7–T10),
  satisfying A5, Open Decision 1, and §4.2.2 without pulling clinical writes onto the first
  display-only capability.

## Assumptions

- E4 and C3 are complete on `ai/master` (or equivalent integrated line) so AI Feature
  Surfaces, terminal validated payloads, and request references exist for the accept path
  to consume.
- The first shipped capability may remain `advisory_display` / non-clinical-record per Open
  Decision 1; F2 still ships `record_ai_acceptance`, the registry, `ai_accepted_output`,
  and the clinical accept library (harness/tests against the demonstration target) so a
  later `human_accept_required` capability can wire a production Feature Surface without
  redesign (delivery plan §3.7; §4.2.2).
- `public.save_visit_documentation` already exists as an ordinary domain RPC (public
  wrapper → `auth_internal.save_visit_documentation`) and is suitable as the demonstration
  target named in §4.2.2; it writes `public.visit_clinical_notes`.
- Ordinary clinic RPC/RLS patterns for domain writes are reused; acceptance grants no
  privilege the clinician did not already have (§4.2.2).
- No new AI-platform taxonomy error codes are required for acceptance; delegated failures
  reuse existing domain RPC error handling (§4.2.2).
- Chat-to-record acceptance, if ever enabled, will call this same RPC with a registered
  target (Open Decision 14) rather than a second mechanism.
