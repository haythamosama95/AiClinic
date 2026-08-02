# Implementation Plan: Support lookup, retention purges, usage rollups, and journal dashboards (F3)

**Branch**: `ai/041-f3-support-retention-rollups` | **Date**: 2026-08-02 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/041-support-retention-rollups/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

F3 freezes the control-plane support lookup (operator-only resolve of a request reference to the full journal trace plus in-horizon R2 envelope in one indexed D1 lookup and one `GetObject`), the four-class retention purge policy (including per-capability diagnostic horizons and purge-by-installation-id), the scheduled `usage_rollup` production job with reconciliation for missing attempt rows / missing usage credit, and the six named journal dashboards answered by D1 query alone. It sits in Band F after C3 and B4 (`Needs: C3, B4`); without it the A13 support scenario and R-6 post-response-detail detection remain unanswerable in production operations (delivery plan §3.7).

## Technical Context

**Language/Version**: TypeScript on Cloudflare Workers (existing `ai-platform/` Vitest ~3.2 / Wrangler stack); D1 SQL for journal/ledger/rollup queries and purges; R2 for envelope GetObject/Delete.

**Primary Dependencies**: Existing Worker tree under `ai-platform/`. Consumes C3 journal/envelope/`getRequest` and A2 `normalizeRequestReference` without rewrite; Consumes B4 credit RPC evidence path and Quota DO in-object ephemeral expiry without rewrite. Operator auth reuses B2 `OperatorAuth` / `requireOperator` in `src/control/`. Capability `Governance.retentionClass` from A4/C1 manifests for per-capability diagnostic horizons. No new external packages; no Flutter/`backend/` changes.

**Storage**: Platform D1 (`ai_request`, `ai_attempt`, `usage_event`, `usage_rollup`, `platform_counter`, `control_audit`, `capability_grant`) and R2 envelopes (`request/{id}/envelope`) — shapes already from A5/C3; F3 does not redefine them. Quota DO ephemeral maps remain in-object (B4). No new D1 entities. No Supabase write path.

**Testing**: Vitest (`npx vitest run`) at delivery plan §3.11.6 row F3 — **Integration + scheduled job + query tests (spy)** — mapped to §13.5 **Pipeline tests** (fake D1/R2/DO; spy on query/GetObject/Put/Delete counts). Named cases T1–T20 under `ai-platform/test/`. Suite joins CI permanently (delivery plan §3.10).

**Target Platform**: Cloudflare Worker under `ai-platform/` (control-plane routes + Worker cron scheduled handlers). No `frontend/` or `backend/` code.

**Project Type**: Additive AI gateway ops slice — control-plane support lookup, retention purge, rollup/reconciliation scheduled work, and read-only dashboard queries. Per §14: non-primary, no domain logic, no business data, no write path into Supabase.

**Performance Goals**: Support lookup I/O budget — exactly one indexed D1 round trip and at most one R2 `GetObject` (spy). Off the inference path: no second Quota DO round trip and no second R2 object *per inference request*; no D1-per-chunk; no per-request server-side state (delivery plan §6.4; §7.5; §13.6).

**Constraints**: Operator identity only for support lookup (not clinic identity). Do not delete anything still inside its class horizon. Diagnostic horizon is per-capability via manifest `retentionClass`. Ledger remains evidence; rollups are convenience; rollup re-run is idempotent. Reconciliation flags terminal requests missing `ai_attempt` rows or missing usage credit (R-6). Dashboards query journal/rollups/`platform_counter` only — no second metrics store. Do not rewrite C3 write timings, envelope layout, or get-request; do not rewrite B4 admission/credit/ephemeral. Numeric horizon constants chosen within architecture bands (days/weeks, months, years, minutes/hours; Open Decision 4 short diagnostic default).

**Scale/Scope**: One §4 component — Control plane (§4.5). Nineteen FRs; twenty named tests; four frozen contract artifacts; modules under `ai-platform/src/` for support, retention, rollup, and dashboards plus Worker/control wiring. Roughly 20–24 tasks — under the ~25-task ceiling (delivery plan §6.3 / skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — operator
      support lookup, bounded retention, and journal-backed dashboards without a second
      metrics platform (spec Clinic Fit; constitution I; A10; §13.1).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — additive Worker control-plane routes
      and cron handlers inside the existing `ai-platform/` deployable; no new service.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated —
      F3 lives only in `ai-platform/`; no clinic-DB journal mirrors; no Flutter changes.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — F3 writes only
      platform D1/R2 (purges, rollups, control_audit); no Supabase write path; clinic
      domain integrity unchanged.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — support lookup and installation purge are
      operator-authenticated (reuse B2 boundary); installation-scoped purge preserves
      tenant isolation; platform retention hard-deletes past-horizon platform rows/objects
      per §7.7 / A10 (intentional platform purge, not clinic soft-delete bypass); operator
      mutations journaled to `control_audit` where required (FR-018).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — F3 is off the
      request path; lagging jobs do not block clinical inference; AI remains additive
      (constitution V; §14).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with
no domain logic, no business data, and no write path into Supabase. F3 operates only on
platform stores already written by C3/B4 (D1 journal/ledger, R2 envelopes, Quota DO
ephemeral in-place expiry) and adds operator-authenticated control-plane reads plus
scheduled purge/rollup jobs — never a clinic-DB write path.

## Project Structure

### Documentation (this feature)

```text
specs/041-support-retention-rollups/
├── plan.md                                    # This file
├── spec.md                                    # /ai-platform-specify (+ clarify: none open)
├── contracts/
│   ├── support-lookup.md                      # Freezes: support lookup + request-reference input
│   ├── retention-purge.md                     # Freezes: four-class retention + purge-by-installation
│   ├── usage-rollup-reconciliation.md         # Freezes: usage_rollup job + reconciliation report
│   └── journal-dashboards.md                  # Freezes: six named diagnostics; no second store
└── quickstart.md                              # Written during the implement-phase Documentation task
```

`data-model.md` is **not** produced — F3 defines no new D1 entities. `ai_request`, `ai_attempt`,
`usage_event`, `usage_rollup`, `platform_counter`, `control_audit`, and `capability_grant` already
exist from A5; F3 freezes production/purge/query behaviour over them. Entity presence remains in
A5 / C3 artifacts.

`research.md` is **not** produced — the research is `docs/architecture/17-ai-platform.md`.

`contracts/` is produced because **Freezes** entries have wire/policy shapes later slices’
**Consumes** must bind to: support-lookup request/response and I/O budget; reference input
normalisation; retention class horizons and purge-by-installation; rollup production +
reconciliation report; named dashboard query contracts.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:

- **§1 Architecture context** — F3 row of the delivery plan (§3.7) and Implements (§4.5, §8.9,
  §7.6, §7.7, §13.1, R-6, A13); what the spec delivered; what the plan scoped.
- **§2 What was implemented** — support lookup, retention purges, `usage_rollup` +
  reconciliation, six journal dashboards.
- **§3 Files to review** — this slice’s `src/support/`, `src/retention/`, `src/rollup/`,
  `src/dashboards/`, Worker/control/wrangler wiring, this slice’s test files, and
  `contracts/*` only.
- **§5 Run the automated suite** — slice-only `npx vitest run` against this slice’s test
  files; no full-suite `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — grep support-lookup route, retention/rollup cron handlers,
  dashboard query modules, focused Vitest files, frozen contracts.
- **§7 Manual validation** — optional: operator support-lookup against a seeded reference and
  inspect cron job logs when bindings are available. Omit if CI is the sole verification path.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── support/
│   │   └── index.ts                         # NEW — operator support lookup (FR-001–FR-006, FR-019)
│   ├── retention/
│   │   └── index.ts                         # NEW — class-horizon purge + purge-by-installation (FR-007–FR-010, FR-018)
│   ├── rollup/
│   │   └── index.ts                         # NEW — usage_rollup job + reconciliation (FR-011–FR-014)
│   ├── dashboards/
│   │   └── index.ts                         # NEW — six named diagnostic queries (FR-015–FR-017)
│   ├── control/
│   │   └── index.ts                         # MODIFIED — wire support-lookup + installation-purge routes; reuse OperatorAuth (FR-001, FR-005, FR-010, FR-018)
│   ├── worker.ts                            # MODIFIED — dispatch support/purge routes; scheduled handler for retention + rollup
│   ├── journal/index.ts                     # UNCHANGED — Consumes C3 write path / getRequest / Envelope
│   ├── reference.ts                         # UNCHANGED — Consumes normalizeRequestReference (A2/C3)
│   ├── credit/index.ts                      # UNCHANGED — Consumes B4 credit caller
│   ├── quota-do/index.ts                    # UNCHANGED — Consumes B4 ephemeral in-place expiry
│   └── manifest/index.ts                    # UNCHANGED — read Governance.retentionClass (A4/C1)
├── wrangler.toml                            # MODIFIED — cron triggers for retention + rollup/reconciliation
└── test/
    ├── support-lookup.test.ts               # NEW — T1–T3 (integration spy)
    ├── retention.test.ts                    # NEW — T4–T9 (integration / scheduled job)
    ├── rollup-reconciliation.test.ts        # NEW — T10–T13 (scheduled job)
    └── journal-dashboards.test.ts           # NEW — T14–T20 (query + spy)

specs/041-support-retention-rollups/
├── contracts/*.md                           # NEW — frozen Freezes artifacts (see Documentation)
└── quickstart.md                            # NEW during implement Documentation task
```

**Structure Decision**: F3 extends `ai-platform/` with focused modules for the four Freezes
surfaces (support, retention, rollup, dashboards), wired through the existing control-plane
operator auth and Worker entry (delivery plan §7.1). C3 `journal/` and B4 `quota-do/` /
`credit/` are Consumed unchanged. Spec Kit `frontend/` / `backend/` placeholders are deleted as
unused.

## Consumes Binding

F3 has `Needs: C3, B4` (delivery plan §3.7). Changing any Consumes contract is out of scope
(delivery plan §2.3).

| Consumes entry | Existing module / file / type it binds to |
| --- | --- |
| **C3 — R2 payload envelope** (`request/{id}/envelope` with `context`, `prompt`, `attempts[]`, `result`) | `ai-platform/src/journal/index.ts` (`Envelope` type, `envelopeKey` / stage-16 `PutObject`); frozen artifact `specs/027-journal-writer-get-request/contracts/journal.md` §2. F3 `GetObject`s / deletes this single object; does not split, rewrite sections, or add a second R2 object per request. |
| **C3 — journal write-path** (stage-9 row, transitions, stage-15 terminal, stage-16 attempts + one `usage_event` + envelope) | `ai-platform/src/journal/index.ts` (`createRequestRow`, `journalTransition`, `recordTerminalState`, `writePostResponseDetail`). F3 reads/purges rows and reconciles against them; does not redefine write timings or row shapes. |
| **C3 — request reference** (unique indexed support handle) | `ai_request.request_reference` + `idx_ai_request_request_reference` (A5 migration); A2/C3 `ai-platform/src/reference.ts` (`normalizeRequestReference`, `generateRequestReference`). F3 normalises input then looks up on that index; does not change generation or uniqueness. |
| **C3 — get-request endpoint** (client-facing; distinct from operator support lookup) | `getRequest` in `ai-platform/src/journal/index.ts`; `GET /v1/requests/{reference}` in `ai-platform/src/worker.ts`; contract `journal.md` §3. F3 adds a **separate** control-plane support lookup and does not change get-request semantics. |
| **B4 — separate credit RPC** (settles actual usage on the Quota DO) | `ai-platform/src/credit/index.ts`; `creditRPC` in `ai-platform/src/quota-do/index.ts`; frozen artifact `specs/024-quota-do-admission/contracts/quota-do-rpc.md`. F3 reconciliation detects missing usage credit against durable journal/`usage_event` evidence; does not rewrite credit RPC. |
| **B4 — ephemeral retention class** (`jti` / idempotency expire in place; no table to prune) | `EPHEMERAL_HORIZON_MS`, ephemeral maps + lazy sweep in `ai-platform/src/quota-do/index.ts`; contract `quota-do-rpc.md` §8. F3 proves in-place expiry (T7) and does not add a D1/R2 prune for ephemeral. |

**Transitive (already Consumed by C3/B4 — read only, not redefined):** A5 D1 entities; A4/C1
`Governance.retentionClass` on manifests (`ai-platform/src/manifest/index.ts`); A2 request-reference
alphabet/format.

No Consumes entry lacks an existing implementation. None is modified (delivery plan §2.3). Stop
condition 2 is not triggered.

## Components Touched

**One** §4 component:

1. **§4.5 Control plane** — Support lookup (A13); Operational dashboards (named §13.1
   diagnostics); operator-authenticated installation purge-by-id recovery path (§7.7); scheduled
   retention and `usage_rollup`/reconciliation jobs as Worker cron handlers attached to the same
   deployable (FR-001–FR-018; delivery plan §3.7 Done when).

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.5 Control plane | **Extended** | This slice’s deliverable (Canonical §4.5; Done when) |
| §4.3.11 Journal writer | **Not touched** | Consumes write path / envelope; retention is separate from writer (responsibility matrix: retention replaceable without touching writer) |
| §4.3.12 Telemetry emitter | **Not touched** | Dashboards query journal side; no second metrics stream |
| §4.3.3 Quota DO / admission | **Not touched** | Consumes credit + ephemeral expiry |
| §4.1 / §4.2 clinic/client | **Not touched** | Out of scope (E/F2 bands) |

Stop condition 5 (multi-component without reason) is not triggered — only §4.5. Task count stays
under ~25.

## Files

| File | FR(s) | Status |
| --- | --- | --- |
| `specs/041-support-retention-rollups/contracts/support-lookup.md` | Freezes (support lookup + reference input); FR-001–FR-006, FR-019 | NEW — frozen artifact |
| `specs/041-support-retention-rollups/contracts/retention-purge.md` | Freezes (retention policy); FR-007–FR-010, FR-018 | NEW — frozen artifact |
| `specs/041-support-retention-rollups/contracts/usage-rollup-reconciliation.md` | Freezes (rollup job + reconciliation); FR-011–FR-014 | NEW — frozen artifact |
| `specs/041-support-retention-rollups/contracts/journal-dashboards.md` | Freezes (named dashboards); FR-015–FR-017 | NEW — frozen artifact |
| `ai-platform/src/support/index.ts` | FR-001–FR-006, FR-019; T1–T3 | NEW — one indexed D1 lookup + one GetObject; operator-facing reconstruction |
| `ai-platform/src/retention/index.ts` | FR-007–FR-010, FR-018; T4–T9 | NEW — four-class purge; per-capability diagnostic; purge by installation id |
| `ai-platform/src/rollup/index.ts` | FR-011–FR-014; T10–T13 | NEW — `usage_event` → `usage_rollup`; reconciliation report; idempotent re-run |
| `ai-platform/src/dashboards/index.ts` | FR-015–FR-017; T14–T20 | NEW — six named queries; spy-friendly no second store |
| `ai-platform/src/control/index.ts` | FR-001, FR-005, FR-010, FR-018 | MODIFIED — dispatch support-lookup + installation-purge; reuse `OperatorAuth` |
| `ai-platform/src/worker.ts` | FR-001, FR-011, FR-013, FR-017 | MODIFIED — routes + `scheduled` handler for retention/rollup |
| `ai-platform/wrangler.toml` | FR-007, FR-011 | MODIFIED — cron triggers for retention purge and rollup/reconciliation |
| `ai-platform/test/support-lookup.test.ts` | FR-001–FR-006; T1–T3 | NEW |
| `ai-platform/test/retention.test.ts` | FR-007–FR-010; T4–T9 | NEW |
| `ai-platform/test/rollup-reconciliation.test.ts` | FR-011–FR-014; T10–T13 | NEW |
| `ai-platform/test/journal-dashboards.test.ts` | FR-015–FR-017; T14–T20 | NEW |
| `specs/041-support-retention-rollups/quickstart.md` | — | NEW during implement Documentation task (sections named above) |

Every file traces to an `FR-###` (or Freezes / deferred Documentation). No Consumes module is
rewritten. No second metrics store. No clinic/`frontend` files.

**Horizon constants (within architecture bands; Open Decision 4):** defaults live in
`retention/index.ts` / `contracts/retention-purge.md` — diagnostic baseline **7 days** (short by
default; override via manifest `retentionClass` e.g. `diagnostic_30d`); journal **90 days**
(months); ledger **2555 days** (~7 years); ephemeral **unchanged** — B4 `EPHEMERAL_HORIZON_MS`
(2 hours).

## Test Layout

The spec’s Test plan names twenty tests at layer **Integration + scheduled job + query tests
(spy)** (delivery plan §3.11.6 row F3). Mapped to §13.5 **Pipeline tests** (Worker handlers /
scheduled entrypoints against fake D1/R2/DO; spy on call counts). Tests join CI permanently
(delivery plan §3.10).

| # | Named test | Spec layer | Where it lives | Asserts |
| --- | --- | --- | --- | --- |
| 1 | `support_lookup_one_d1_one_getobject` | Integration (spy) | `support-lookup.test.ts` | Trace + envelope in exactly one D1 query and one `GetObject` |
| 2 | `support_lookup_expired_envelope_metadata` | Integration | `support-lookup.test.ts` | Metadata resolves; envelope body absent outside diagnostic retention |
| 3 | `support_lookup_non_operator_denied` | Integration | `support-lookup.test.ts` | Non-operator / clinic identity denied |
| 4 | `retention_expiry_diagnostic` | Integration / scheduled job | `retention.test.ts` | Diagnostic envelopes past horizon deleted; in-horizon kept |
| 5 | `retention_expiry_journal` | Integration / scheduled job | `retention.test.ts` | Journal metadata past horizon deleted; in-horizon kept |
| 6 | `retention_expiry_ledger` | Integration / scheduled job | `retention.test.ts` | Ledger rows past horizon deleted; in-horizon kept |
| 7 | `retention_expiry_ephemeral` | Integration | `retention.test.ts` | Ephemeral expires in place in Quota DO; no table prune (Consumes B4) |
| 8 | `retention_per_capability_diagnostic` | Integration / scheduled job | `retention.test.ts` | Shorter-horizon capability purged; longer kept |
| 9 | `retention_purge_by_installation_id` | Integration | `retention.test.ts` | Purge by installation id clears D1 + R2 for that installation only |
| 10 | `rollup_totals_equal_ledger` | Scheduled job | `rollup-reconciliation.test.ts` | `usage_rollup` totals equal `usage_event` sums |
| 11 | `reconciliation_missing_attempt_rows` | Scheduled job | `rollup-reconciliation.test.ts` | Flags terminal request with no `ai_attempt` rows |
| 12 | `reconciliation_missing_usage_credit` | Scheduled job | `rollup-reconciliation.test.ts` | Flags terminal request missing usage credit / `usage_event` |
| 13 | `rollup_rerun_idempotent` | Scheduled job | `rollup-reconciliation.test.ts` | Re-run does not duplicate rollup totals; report consistent |
| 14 | `dashboard_ttft_by_provider` | Query | `journal-dashboards.test.ts` | Correct TTFT by provider |
| 15 | `dashboard_validation_failure_by_prompt_version` | Query | `journal-dashboards.test.ts` | Correct validation-failure rate by prompt version |
| 16 | `dashboard_repair_rate_by_capability` | Query | `journal-dashboards.test.ts` | Correct repair rate by capability |
| 17 | `dashboard_fallback_rate_by_provider` | Query | `journal-dashboards.test.ts` | Correct fallback rate by provider |
| 18 | `dashboard_cost_per_capability_per_installation` | Query | `journal-dashboards.test.ts` | Correct cost per capability per installation |
| 19 | `dashboard_quota_rejection_rate` | Query | `journal-dashboards.test.ts` | Correct quota rejection rate from journal / `platform_counter` |
| 20 | `dashboard_no_second_metrics_store` | Query (spy) | `journal-dashboards.test.ts` | No second metrics store written |

Every named test places in a §13.5 Pipeline-tests layout — stop condition 3 not triggered.
Coverage matches §3.10 / §3.11.6 F3 (happy path, non-operator deny, four retention classes,
per-capability diagnostic, installation purge, rollup equality + idempotency, both
reconciliation flags, six dashboards + no-second-store spy). Support lookup emits no new §5.4
taxonomy code for non-operator deny (control-plane auth boundary).

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2). Within this
slice:

1. **Frozen contracts** — land `contracts/*.md` so Freezes bind to artifacts (DP-4).
2. **Support lookup (FR-001–FR-006, FR-019; T1–T3)** — `src/support/` + control/worker route;
   integration spy for one D1 + one GetObject, expired envelope metadata, non-operator deny.
3. **Retention (FR-007–FR-010, FR-018; T4–T9)** — `src/retention/` + cron + installation-purge
   control route; prove four classes, per-capability diagnostic, purge-by-id; ephemeral via B4.
4. **Rollup + reconciliation (FR-011–FR-014; T10–T13)** — `src/rollup/` + scheduled handler;
   totals equal ledger, missing attempts, missing usage credit, idempotent re-run.
5. **Dashboards (FR-015–FR-017; T14–T20)** — `src/dashboards/` read-only queries; six diagnostics
   + no-second-store spy.
6. **Wrangler cron + Worker scheduled wiring** — retention and rollup/reconciliation triggers.
7. **Documentation** — fill `quickstart.md` after implementation and verification (sections
   named above).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations. Table omitted.
