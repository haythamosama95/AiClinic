# Feature Specification: Support lookup, retention purges, usage rollups, and journal dashboards

**Feature Branch**: `ai/041-f3-support-retention-rollups`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `F3` — "Support lookup, retention purges, usage rollups, and journal dashboards" (delivery plan §3.7, band F).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.7, row F3):

> §4.5, §8.9, §7.6, §7.7, §13.1, R-6, A13

### Freezes

Contracts this slice establishes for the first time:

- The **control-plane support lookup** — an operator-authenticated control-plane function
  that resolves a user-visible request reference to the full reconstructable trace and the
  R2 payload envelope: exactly one indexed D1 lookup on the request reference (returning
  the request row and its attempt detail as the full trace) and exactly one R2 `GetObject`
  for the envelope when still within diagnostic retention. The lookup is separately
  authenticated with operator identity, not clinic identity (§4.5 Support lookup; §7.6
  Support lookup by request reference; §8.9; A13; delivery plan §3.7 Done when; §3.11.6 F3).
- The **request-reference input contract for support lookup** — the fixed
  eight-symbol Crockford base32 format
  `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` (e.g. `7QK4-2B9F`), with input
  normalised before lookup: case-folded up, and `I`/`L` → `1`, `O` → `0` (§8.9; A13).
- The **retention purge policy** — each retention class expires on its own horizon;
  the diagnostic envelope's horizon is per-capability (manifest retention class); an
  installation deletion is executable as purge by installation id in both D1 and R2;
  nothing still inside its horizon is deleted (§7.7; A10 via Open Decision 4; delivery
  plan §3.7 Done when; §3.11.6 F3).
- The **`usage_rollup` production job** — a scheduled job produces `usage_rollup` from
  `usage_event` (the ledger is the evidence; rollups are the convenience), and a
  reconciliation pass reports requests that have a terminal state but missing attempt
  rows or missing usage credit; a re-run is idempotent (§7.6 Billing period close /
  Analytics; R-6; delivery plan §3.7 Done when; §3.11.6 F3).
- The **named journal dashboards** — the named diagnostics are answerable by query
  against the journal and rollups with no second metrics store: time to first token by
  provider; validation-failure rate by prompt version; repair rate by capability;
  fallback rate by provider; cost per capability per installation; quota rejection rate
  (§13.1; §7.6 Analytics and dashboards; delivery plan §3.7 Done when; §3.11.6 F3).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (C3, B4). Changing any is out of scope by
definition:

- **From C3 (journal writer, post-response detail, and get-request)**: the **R2 payload
  envelope** (`request/{id}/envelope` with sections `context`, `prompt`, `attempts[]`,
  `result`); the **journal write-path** that creates the durable `ai_request` row before
  work, journals state transitions, and writes `ai_attempt` rows plus exactly one
  `usage_event` after the terminal event; the **request reference** as the unique indexed
  support handle; and the get-request endpoint used by clients (distinct from operator
  support lookup). F3 reads and purges these stores and does not redefine write timings,
  envelope layout, or get-request semantics (C3 Freezes; §7.6; §8.9).
- **From B4 (Quota Durable Object and admission)**: the **separate credit RPC** that
  settles actual usage on the Quota DO, and the **ephemeral** retention class for `jti`
  replay and idempotency records that expire in place inside the DO with no table to prune.
  F3's reconciliation detects missing usage credit against the durable journal/ledger; it
  does not rewrite admission, credit, or DO ephemeral expiry (B4 Freezes; §7.7
  `ephemeral`; R-6).

Transitive schema and taxonomy contracts F3 relies on without redefining them (frozen by
A5 / A2 / A4 and already Consumed by C3/B4): `ai_request`, `ai_attempt`, `usage_event`,
`usage_rollup`, `platform_counter`, `control_audit`, and capability-manifest **retention
class** / Governance fields.

### Open decisions relied on

- **Open Decision 4** — *Diagnostic retention horizon for prompts, context, and
  responses*: recommended default "Short by default (days), extendable per capability;
  this is the largest and most sensitive data (A10)." F3 assumes that default for the
  `diagnostic` class horizon and honours per-capability extension via the manifest
  retention class (§15 #4; §7.7; A10).
- No other §15 decision is assumed. Quota unit/period (Open Decision 2) is read from
  existing ledger and entitlement data; soft-threshold routing (F4) is out of scope.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Support lookup, retention purges, usage rollups, and journal dashboards (Priority: P1)

As a platform operator, when a clinician reports a failed AI request by reading aloud its
user-visible request reference (A13), I resolve that reference through the control-plane
support lookup to the full journal trace and — while the diagnostic envelope is still
within its retention horizon — the R2 payload envelope, using exactly one indexed D1
lookup and one `GetObject`. Retention purges expire each retention class on its own
horizon (with the diagnostic envelope's horizon per capability), and an installation
deletion is executable as purge by installation id in both D1 and R2 without deleting
anything still inside its horizon. A scheduled job produces `usage_rollup` from
`usage_event`, a reconciliation pass flags terminal requests missing attempt rows or
missing usage credit, and the named operational diagnostics are answered by query against
the journal and rollups with no second metrics store.

**Why this priority**: F3 sits where it does because its `Needs` (C3, B4) are the point at
which the durable journal, envelope, usage ledger, and Quota DO credit path exist — the
audit backbone band F hardens into support, retention, rollups, and dashboards (delivery
plan §3.7). Without this slice, the A13 support scenario and R-6 post-response-detail risk
remain unanswerable in production operations.

**Independent Test**: An operator resolves a request reference to the full trace and the
R2 envelope through one indexed D1 lookup and one `GetObject`; each retention class
expires on its own horizon, the diagnostic envelope's horizon is per-capability, and an
installation deletion is executable as a purge by installation id in both stores; a
scheduled job produces `usage_rollup` from `usage_event` and a reconciliation pass reports
requests with a terminal state but missing attempt rows or missing usage credit; the named
diagnostics are answerable by query against the journal and rollups with no second metrics
store — time to first token by provider, validation-failure rate by prompt version, repair
rate by capability, fallback rate by provider, cost per capability per installation, quota
rejection rate (delivery plan §3.7 Done when; §3.11.6 F3).

**Acceptance Scenarios**:

1. **Given** a journaled request with a valid request reference and an in-horizon R2
   envelope, **When** an authenticated operator performs support lookup, **Then** the
   full trace (request row: installation, actor, branch, capability@version, prompt
   artifact hash, state and milestone timestamps, terminal error code, trace id; plus
   attempts: provider, model, latency, tokens, provider request ids, error codes) and the
   envelope resolve in exactly one indexed D1 query and exactly one R2 `GetObject`.
   *(support_lookup_one_d1_one_getobject — spy)*
2. **Given** a journaled request whose diagnostic envelope has expired under its retention
   horizon, **When** an authenticated operator performs support lookup, **Then** the
   journal metadata (trace) still resolves and the envelope body is absent because it is
   outside diagnostic retention. *(support_lookup_expired_envelope_metadata)*
3. **Given** clinic (non-operator) credentials, **When** support lookup is attempted,
   **Then** the caller is denied — the control plane is separately authenticated with
   operator identity, not clinic identity. *(support_lookup_non_operator_denied)*
4. **Given** diagnostic-class R2 envelopes past their horizon, **When** the retention
   purge runs, **Then** those envelopes are deleted and nothing still inside the
   diagnostic horizon is deleted. *(retention_expiry_diagnostic)*
5. **Given** journal-class `ai_request` / `ai_attempt` metadata past the journal horizon,
   **When** the retention purge runs, **Then** that metadata is deleted and nothing still
   inside the journal horizon is deleted. *(retention_expiry_journal)*
6. **Given** ledger-class `usage_event` / `usage_rollup` / `control_audit` /
   `capability_grant` rows past the ledger horizon, **When** the retention purge runs,
   **Then** those rows are deleted and nothing still inside the ledger horizon is deleted.
   *(retention_expiry_ledger)*
7. **Given** Quota DO `jti` / idempotency ephemeral entries past the ephemeral horizon,
   **When** their in-object expiry elapses, **Then** they expire in place with no table to
   prune (ephemeral class). *(retention_expiry_ephemeral)*
8. **Given** two capabilities with different diagnostic retention horizons on their
   manifests, **When** the retention purge runs at a time between those horizons, **Then**
   only the shorter-horizon capability's envelopes are purged — the per-capability
   diagnostic horizon is honoured. *(retention_per_capability_diagnostic)*
9. **Given** an installation with journal rows and R2 envelopes, **When** purge by
   installation id runs, **Then** both stores are cleared for that installation id.
   *(retention_purge_by_installation_id)*
10. **Given** seeded `usage_event` ledger rows, **When** the scheduled rollup job runs,
    **Then** `usage_rollup` totals equal the ledger sums. *(rollup_totals_equal_ledger)*
11. **Given** a request with a terminal state but no `ai_attempt` rows, **When**
    reconciliation runs, **Then** the request is flagged on the reconciliation report.
    *(reconciliation_missing_attempt_rows)*
12. **Given** a request with a terminal state but missing usage credit (no settling
    `usage_event` / credit evidence as R-6 mitigates), **When** reconciliation runs,
    **Then** the request is flagged on the reconciliation report.
    *(reconciliation_missing_usage_credit)*
13. **Given** a prior successful rollup and reconciliation run, **When** the same job is
    re-run over the same window, **Then** the outcome is idempotent (no duplicated rollup
    totals; report remains consistent). *(rollup_rerun_idempotent)*
14. **Given** a seeded journal (and rollups / `platform_counter` as required), **When**
    each named diagnostic is queried, **Then** it returns the correct value: time to first
    token by provider; validation-failure rate by prompt version; repair rate by
    capability; fallback rate by provider; cost per capability per installation; quota
    rejection rate — and no second metrics store is written (spy).
    *(dashboard_ttft_by_provider; dashboard_validation_failure_by_prompt_version;
    dashboard_repair_rate_by_capability; dashboard_fallback_rate_by_provider;
    dashboard_cost_per_capability_per_installation; dashboard_quota_rejection_rate;
    dashboard_no_second_metrics_store — spy)*

### Test plan

Layer from delivery plan §3.11.6 Band F row F3: **Integration + scheduled job + query
tests (spy)**. Named cases (floor from §3.11.6; coverage rule §3.10 applies):

| # | Test name | Layer | Asserts |
| --- | --- | --- | --- |
| 1 | `support_lookup_one_d1_one_getobject` | Integration (spy) | Reference resolves to trace + envelope in exactly one D1 query and one `GetObject` |
| 2 | `support_lookup_expired_envelope_metadata` | Integration | Expired envelope still resolves its metadata |
| 3 | `support_lookup_non_operator_denied` | Integration | Non-operator is denied |
| 4 | `retention_expiry_diagnostic` | Integration / scheduled job | Diagnostic class expiry; nothing in-horizon deleted |
| 5 | `retention_expiry_journal` | Integration / scheduled job | Journal class expiry; nothing in-horizon deleted |
| 6 | `retention_expiry_ledger` | Integration / scheduled job | Ledger class expiry; nothing in-horizon deleted |
| 7 | `retention_expiry_ephemeral` | Integration | Ephemeral class expires in place; no table prune |
| 8 | `retention_per_capability_diagnostic` | Integration / scheduled job | Per-capability diagnostic horizon honoured |
| 9 | `retention_purge_by_installation_id` | Integration | Purge by installation id clears D1 and R2 |
| 10 | `rollup_totals_equal_ledger` | Scheduled job | Rollup totals equal `usage_event` ledger sums |
| 11 | `reconciliation_missing_attempt_rows` | Scheduled job | Flags terminal request missing attempt rows |
| 12 | `reconciliation_missing_usage_credit` | Scheduled job | Flags missing usage credit |
| 13 | `rollup_rerun_idempotent` | Scheduled job | Re-run is idempotent |
| 14 | `dashboard_ttft_by_provider` | Query | Correct TTFT by provider against seeded journal |
| 15 | `dashboard_validation_failure_by_prompt_version` | Query | Correct validation-failure rate by prompt version |
| 16 | `dashboard_repair_rate_by_capability` | Query | Correct repair rate by capability |
| 17 | `dashboard_fallback_rate_by_provider` | Query | Correct fallback rate by provider |
| 18 | `dashboard_cost_per_capability_per_installation` | Query | Correct cost per capability per installation |
| 19 | `dashboard_quota_rejection_rate` | Query | Correct quota rejection rate (from journal / `platform_counter`) |
| 20 | `dashboard_no_second_metrics_store` | Query (spy) | No second metrics store is written |

---

### Edge Cases

- **Non-operator / clinic identity on support lookup**: denied — control plane uses
  operator identity, not clinic identity (§4.5). This slice introduces no new §5.4
  taxonomy code for that denial; the denial is a control-plane auth boundary.
- **Expired diagnostic envelope**: metadata (journal trace) still resolves; envelope body
  is unavailable outside diagnostic retention (§8.9 "if within diagnostic retention";
  §7.7 `diagnostic`).
- **Reference input normalisation**: case-folded up; `I`/`L` → `1`, `O` → `0` before
  lookup so speech/handwriting confusions still resolve (§8.9).
- **Reference still inside horizon vs past horizon**: purge must not delete anything
  inside its class horizon; each class uses its own default horizon — `diagnostic` days
  (short, extendable per capability), `journal` months, `ledger` years, `ephemeral`
  minutes to hours (§7.7; Open Decision 4).
- **Per-capability diagnostic horizon**: a shorter-horizon capability's envelopes expire
  while a longer-horizon capability's envelopes remain (§7.7; Open Decision 4).
- **Installation purge**: purge by installation id clears both D1 and R2 for that
  installation; other installations are untouched (§7.7).
- **Ephemeral class**: no D1/R2 table prune — entries expire in place inside the Quota DO
  (§7.7; Consumes B4).
- **Terminal request missing `ai_attempt` rows**: flagged by reconciliation (R-6;
  delivery plan §3.11.6 F3).
- **Terminal request missing usage credit**: flagged by reconciliation (delivery plan
  §3.7 Done when; R-6 mitigation against lost post-response detail).
- **Rollup re-run**: idempotent — rollup totals remain equal to ledger sums without
  duplication (delivery plan §3.11.6 F3).
- **Metrics / dashboards**: must not write a second metrics store; dimensions are queried
  from journal columns, `usage_rollup`, and `platform_counter` only (§13.1; §7.6).
- **Support lookup I/O budget**: a second D1 round trip or a second R2 object fetch for
  the same lookup violates §7.6 / Done when / §3.11.6 (spy).
- **Inherited hot-path prohibitions**: this slice is off the request path; it must not
  introduce a second Quota DO round trip or second R2 object *per inference request*,
  journal guard rejections as requests, write D1 per stream chunk, or create per-request
  server-side state (delivery plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The control plane MUST provide a Support lookup function that resolves a
  request reference to its full trace and payloads, authenticated with operator identity
  (not clinic identity). `(§4.5; A13)`
- **FR-002**: Support lookup MUST perform exactly one indexed D1 lookup on the request
  reference and exactly one R2 `GetObject` for the payload envelope (when present within
  diagnostic retention). `(§7.6; delivery plan §3.7 Done when; §3.11.6 F3)`
- **FR-003**: The single indexed D1 lookup MUST return the reconstructable trace named in
  §8.9: request row fields (installation, actor, branch, capability@version, prompt
  artifact hash, state and milestone timestamps, terminal error code, trace id) and
  attempt detail (provider, model, latency, tokens, provider request ids, error codes).
  `(§8.9; §7.6)`
- **FR-004**: When the diagnostic envelope is still within retention, support lookup MUST
  fetch it via the one `GetObject` and include prompt, context, raw responses, and result
  in the reconstruction; when outside diagnostic retention, metadata MUST still resolve
  without the envelope body. `(§8.9; §7.7; delivery plan §3.11.6 F3)`
- **FR-005**: A non-operator MUST be denied support lookup. `(§4.5; delivery plan §3.11.6 F3)`
- **FR-006**: Request-reference input for support lookup MUST accept the fixed format
  `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` and MUST normalise input before lookup
  (case-folded up; `I`/`L` → `1`, `O` → `0`). `(§8.9; A13)`
- **FR-007**: Retention MUST implement the four classes with their own horizons:
  `diagnostic` (R2 payload envelope — days to weeks, short by default and extendable per
  capability), `journal` (`ai_request` / `ai_attempt` metadata — months), `ledger`
  (`usage_event`, `usage_rollup`, `control_audit`, `capability_grant` — years),
  `ephemeral` (`jti` replay and idempotency inside the Quota DO — minutes to hours,
  expired in place with no table to prune). `(§7.7; Open Decision 4)`
- **FR-008**: The diagnostic envelope's retention horizon MUST be per-capability via the
  manifest retention class. `(§7.7; Open Decision 4; delivery plan §3.7 Done when)`
- **FR-009**: Retention purge MUST NOT delete anything still inside its class horizon.
  `(§7.7; delivery plan §3.11.6 F3)`
- **FR-010**: An installation deletion MUST be executable as purge by installation id in
  both D1 and R2. `(§7.7; delivery plan §3.7 Done when; §3.11.6 F3)`
- **FR-011**: A scheduled job MUST produce `usage_rollup` from `usage_event`; the ledger
  remains the evidence and rollups the convenience. `(§7.6; delivery plan §3.7 Done when)`
- **FR-012**: Rollup totals MUST equal `usage_event` ledger sums; a re-run of the rollup
  job MUST be idempotent. `(delivery plan §3.11.6 F3; §7.6)`
- **FR-013**: A scheduled reconciliation pass MUST report requests that have a terminal
  state but missing attempt rows. `(R-6; delivery plan §3.7 Done when; §3.11.6 F3)`
- **FR-014**: The same reconciliation pass MUST report requests with a terminal state but
  missing usage credit. `(R-6; delivery plan §3.7 Done when; §3.11.6 F3)`
- **FR-015**: Operational dashboards MUST answer the named diagnostics by query against
  `ai_request` / `ai_attempt` / `usage_rollup` / `platform_counter` in D1 (and Workers
  tracing/logs for traces only as §13.1 already separates), with no second metrics store:
  time to first token by provider; validation-failure rate by prompt version; repair rate
  by capability; fallback rate by provider; cost per capability per installation; quota
  rejection rate. `(§13.1; §7.6; delivery plan §3.7 Done when; §3.11.6 F3)`
- **FR-016**: Metrics MUST sit on the journal side of the logs-vs-journal distinction —
  every dashboard dimension is already a column on a journal or rollup/counter row, so
  querying it MUST NOT require a store of its own and MUST NOT be able to disagree with
  the audit trail. `(§13.1)`
- **FR-017**: Analytics and dashboard reads MUST be read-only and off the request path.
  `(§7.6)`
- **FR-018**: Every control-plane mutation this slice performs that changes operational
  state (including retention purges and installation purge) MUST be journaled with the
  operator identity where the control plane already requires operator-audited mutation;
  support lookup itself is a read. `(§4.5)`
- **FR-019**: The user-visible request reference remains the support handle that makes the
  brief's auditing scenario answerable without reproducing the failure (A13; §8.9).

### Key Entities

- **Support lookup result**: operator-facing reconstruction of one request from the
  indexed journal row, its attempts, and (when in horizon) the single R2 envelope —
  content shaped by §8.9; I/O shaped by §7.6.
- **Retention classes** (`diagnostic`, `journal`, `ledger`, `ephemeral`): purge/expiry
  policy over existing D1/R2/DO stores; horizons and applies-to sets fixed in §7.7;
  diagnostic horizon further bound per capability (Open Decision 4).
- **`usage_rollup`**: convenience aggregate produced from `usage_event` by the scheduled
  job; entity presence already from A5; this slice freezes production, equality-to-ledger,
  and idempotent re-run (§7.6).
- **Reconciliation report**: operational detection artifact listing terminal requests
  missing attempt rows and/or missing usage credit (R-6; delivery plan Done when).
- **Named diagnostics**: the six §13.1 dashboard questions answered by journal/rollup/
  counter queries only.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Operator support lookup, retention, and journal-backed dashboards keep
  AI operable for small-to-mid multi-branch clinics without a second metrics platform or
  enterprise observability stack. Retention bounds liability for stored clinical text
  while preserving audit metadata on longer horizons (A10; §7.7; constitution I).
- **Layer Placement**: This slice touches **`ai-platform/` (Cloudflare Worker)** — control
  plane support lookup, retention purge jobs, `usage_rollup` / reconciliation scheduled
  work, and journal/rollup dashboard queries against D1/R2. It does **not** place these
  operators tools in `frontend/` or invent clinic-DB mirrors of the journal. The §14
  acknowledgement that the gateway is a non-primary, additive component (no domain logic,
  no business data, no write path into Supabase, always optional) holds: F3 operates only
  on platform stores already written by C3/B4 and adds no Supabase write path
  (constitution II / §14).
- **Data Integrity & Security**: Support lookup is operator-authenticated and separate
  from clinic identity (§4.5). Installation-scoped purge and indexed reference lookup
  preserve tenant isolation on the platform side. Retention purges enforce explicit
  horizons rather than unbounded storage (A10; §7.7). Reconciliation detects loss of
  post-response detail without weakening the durable request-row terminal state (R-6).
- **Failure Handling**: An expired envelope still yields metadata so support is not
  blind after diagnostic expiry (§8.9). Missing attempt rows or usage credit surface on
  the reconciliation report rather than silently vanishing (R-6). Dashboard and rollup
  work is off the request path, so operational jobs must not block clinical inference;
  AI remains additive if jobs lag (constitution V).

## Out of Scope

Neighbouring slices and work this slice must not pull forward:

- **C3** — journal writer, post-response envelope writes, and client get-request endpoint
  (Consumes; do not redefine write path or get-request).
- **B4** — Quota DO admission/credit RPCs and in-object ephemeral store implementation
  (Consumes; F3 reconciles and relies on ephemeral in-place expiry, does not rewrite DO
  accounting).
- **B2** — installation lifecycle enroll/suspend/resume/rotate/delete mutations beyond
  executing the purge-by-installation-id recovery path §7.7 names when deletion is
  requested.
- **F1 / F2 / F4 / F5** — eval harness, acceptance recording RPC, soft-threshold degraded
  routing, load and cost tests.
- **Band G** — commercial usage summary endpoint, plan catalogue, billing period close
  product surface, invoice generation (§7.6 "Usage summary for a clinic" live counters
  path and band G remain out of F3's Done when).
- **A second metrics store / Analytics Engine** — explicitly rejected by §13.1; the
  condition that would reverse that choice is not this slice's to implement.
- **Client display of request references / last-N retention** — client requirements in
  §13.2 belong to E2/E4, not F3.
- **Health-based provider routing, D1 sharding, and other §9.14 mechanisms** — deferred
  with written triggers (R-20).

Prohibitions from delivery plan §6.4:

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

- **SC-001**: An authenticated operator resolves a request reference to full trace plus
  in-horizon envelope with exactly one indexed D1 query and exactly one R2 `GetObject`
  (spy-proven).
- **SC-002**: An expired diagnostic envelope still resolves journal metadata; a
  non-operator is denied support lookup.
- **SC-003**: Each of the four retention classes has a proven expiry case; per-capability
  diagnostic horizons are honoured; purge by installation id clears both stores; no
  in-horizon row or object is deleted.
- **SC-004**: Scheduled `usage_rollup` totals equal `usage_event` ledger sums; re-run is
  idempotent.
- **SC-005**: Reconciliation flags terminal requests missing attempt rows and flags
  missing usage credit.
- **SC-006**: Each of the six named §13.1 diagnostics returns correct values against a
  seeded journal; spy proves no second metrics store is written.

## Assumptions

- C3 and B4 contracts listed under Consumes are available and unchanged (delivery plan
  §3.7 Needs; §2.3 no-rework).
- D1 entities `ai_request`, `ai_attempt`, `usage_event`, `usage_rollup`,
  `platform_counter`, `control_audit`, and `capability_grant` already exist from A5
  schema; F3 does not redefine their shapes.
- Capability manifests already carry the Governance retention class field (A4/C1); F3
  reads it for per-capability diagnostic horizons.
- Open Decision 4's recommended default ("short by default (days), extendable per
  capability") is the diagnostic baseline used with §7.7's class table.
- Exact numeric day/month/year constants for horizons may be configuration chosen at
  implement/clarify time within the architecture's named bands (days/weeks, months,
  years, minutes/hours); this spec does not invent a number outside those bands.
- Operator authentication for the control plane exists as the separate operator-identity
  surface §4.5 requires (B2 control-plane mutations already assume operator credentials);
  F3 reuses that boundary for support lookup and does not invent a new identity system.
- "Missing usage credit" for reconciliation means absence of the post-response usage
  settlement evidence the architecture requires (usage ledger / credit path from C3/B4),
  detected against requests that already have a durable terminal state (R-6).
