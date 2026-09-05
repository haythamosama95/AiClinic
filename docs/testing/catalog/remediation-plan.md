# AI Platform Test-Catalog Remediation Plan

Consolidated decisions for every concern, unreached-code finding, and docs mismatch
recorded in the `Doc-drift observations` / `Non-automatable notes` sections of the
stage catalogs and in `registers.md` (Register 4 items R4-1…R4-85, Register 5 seams).
This file is the implementation backlog; the catalogs and registers remain the evidence.

## Table of Contents

1. [Decision Policy](#1-decision-policy)
2. [Code Changes](#2-code-changes)
   - [High Priority](#21-high-priority)
   - [Medium Priority](#22-medium-priority)
   - [Low Priority](#23-low-priority)
3. [Documentation Fixes](#3-documentation-fixes)
4. [Dead-Code and Defensive-Branch Policy](#4-dead-code-and-defensive-branch-policy)
5. [Deferred Items](#5-deferred-items)
6. [Closed / No-Action Items](#6-closed--no-action-items)
7. [Suggested Implementation Order](#7-suggested-implementation-order)
8. [Sequencing Relative to Scenario Implementation](#8-sequencing-relative-to-scenario-implementation)

---

## 1. Decision Policy

Each finding gets exactly one disposition:

| Disposition | Meaning |
|---|---|
| CODE-FIX | Change code to fix a bug or close a correctness gap |
| CODE-ADD | Add a missing endpoint/RPC the docs assume or operations need |
| CODE-REMOVE | Delete truly dead code |
| DOC-FIX | Update the orientation/stage docs to match authoritative code |
| ANNOTATE | Keep the defensive branch; add a code comment stating why it is unreachable |
| ACCEPT | Behavior is intentional; document it, no code change |
| DEFER | Blocked on a future capability (e.g. conversational/structured manifests) |

Global policies applied throughout:

1. **Code is authoritative over docs** unless the doc describes the safer/intended
   behavior and the code is clearly defective (crash, leak, fabricated response).
2. **Defensive unreachable branches in dispatch/guard/router are kept** as safety nets
   against half-finished future edits, but must be annotated (see §4). Only truly
   meaningless dead code is removed.
3. **Wire-shape changes are additive or doc-side**; no existing client-visible contract
   is narrowed without an explicit behavior-change note.
4. Register 5 (non-automatable) items already carry proposed test seams and need no
   further decision, except the few that imply production code changes — those appear
   in §2.

---

## 2. Code Changes

### 2.1 High Priority

| ID | Finding | Decision | References |
|---|---|---|---|
| C-01 | Post-accept routing / missing-policy / missing-handoff failures only push the SSE `failed` event — no `recordTerminalState`, no `ai_attempt`, no ledger entry; the request stays `Accepted` forever and cron reconciliation flags it eternally | **CODE-FIX**: in the `runFreshEventSource` catch and the missing-accept-context branch, settle the request as `Failed`/`internal_error` (journal + terminal-state persistence), mirroring the empty-chain path | R4-24, R4-37; `worker.ts:L685-L697`, `L653-L664`; S05-070/071, S10-003/015/034 |
| C-02 | Missing entitlement row escapes as uncaught `ConfigCacheMissError` → bare non-JSON runtime 500, bypassing the taxonomy envelope | **CODE-FIX**: catch the miss in the guard dispatch and return a stage-3 `internal_error` GuardFailure body | R4-32; `entitlement/index.ts:L154-L160`; S09-027 |
| C-03 | Seed default `ai.aat.lifetime_minutes = 15` (→ 900 s) exceeds the platform's 600 s `exp − iat` ceiling — a default-configured clinic mints tokens the platform always rejects | **CODE-FIX**: change the seed to 10 minutes (new backend migration updating `app_settings`) and document the 600 s platform ceiling next to the setting | R4-81; S06-043 |
| C-04 | Idempotent replay of an in-flight (`admitted`) prior state is replayed as a synthetic `completed` with canned content `"Prior request completed."` — indistinguishable from a real completion and dangerous for clinical content | **CODE-FIX**: never fabricate completion for non-terminal prior states; re-attach to the in-flight execution or emit a pending/accepted frame so the client waits for the real outcome | R4-71; `worker.ts:L623-L630`; S10-017 |

### 2.2 Medium Priority

| ID | Finding | Decision | References |
|---|---|---|---|
| C-05 | Non-string `ver` (e.g. `{"ver":2}`) throws an uncaught `TypeError` at `body.ver?.trim()` instead of `400 invalid_ver` | **CODE-FIX**: type-guard with the existing `requireNonEmptyString` helper from `control/http.ts` | R4-10; `control/token-contract.ts:L31, L86`; S01-013/017 |
| C-06 | Truthy non-string `successor_id` crashes deprecate with an unhandled TypeError → non-JSON 500 | **CODE-FIX**: real type check → `400 invalid_payload` | R4-21; `capability-lifecycle.ts`; S04-091 |
| C-07 | Purge `500 storage_error` is documented but purge has no error mapping; D1/R2 failure → non-JSON runtime 500 | **CODE-FIX**: wrap `handleInstallationPurge` in the same error mapping as `runControlBatch` (intent audit row already written first, so this is safe) | R4-13; `support-purge.ts` |
| C-08 | `500 storage_error` listed for cohort activate/promote, deprecate/retire, and routing canary/promote/rollback, but those handlers call `DB.batch` unguarded | **CODE-FIX**: route all control-plane batches through the `runControlBatch` mapping for a uniform `storage_error` contract | R4-17; `cohort.ts:L179, L382`; `capability-lifecycle.ts:L129, L203`; `routing-policy.ts:L305-L324, L370-L399, L526-L528` |
| C-09 | `quota_exhausted` never carries `period_reset` on the wire although admission computes it and `supplementaryFieldsForCode` supports it (the `errors.ts` F4 comment requires it) | **CODE-FIX**: forward `periodReset` through `runGuard`'s `fail()` and the worker preAccept path | R4-30; `pipeline/index.ts:L191-L213, L444-L449`; `worker.ts:L1087-L1096`; `admission/index.ts:L461-L482` |
| C-10 | `context_required` responses omit `missing_keys`/`shapes`/`manifest_version`; `buildContextRequiredResponse` exists but has no caller | **CODE-FIX**: wire `buildContextRequiredResponse` into the preAccept failure path for `context_required` | R4-34; `context/validator.ts:L541-L557`; `adapter.ts:L213-L229` |
| C-11 | Idempotent replay of a failed request always emits `internal_error`; the DO idempotency entry stores state but not the taxonomy code, so clients lose the real failure (and its `retry_safe` semantics) | **CODE-FIX**: persist `terminal_error_code` in the DO idempotency entry and replay the original code | R4-53; `worker.ts:L631-L634`; S11-014 |
| C-12 | Stage-10 compose failure records `Failed` but never releases the DO admission reservation; `inFlight` leaks until the 2 h abandoned sweep (stage-9 journal failure does release) | **CODE-FIX**: release the reservation on compose failure, mirroring the stage-9 path | R4-72; `pipeline/index.ts:L499-L505` vs `L519-L528` |
| C-13 | Promote has no status precondition (self-promote writes a self-referential audit pair; superseded can be re-activated); rollback of published/superseded is a silent 200 no-op | **CODE-FIX**: add state-machine preconditions — promote rejects an already-active version (409); rollback returns 409 when the addressed row is not the active version. Confirm the intended transition matrix before implementing | R4-26; S05-039/040/046/047 |
| C-14 | Purge has no delete precondition — purge on an `active` installation succeeds and is irreversible | **CODE-FIX**: require `status = deleted` before purge (409 otherwise). Behavior change — confirm with the owner whether a force-purge escape is needed | R4-16; S03-080 |
| C-15 | No `try/catch` in `scheduled()`: a flush failure aborts grace reconcile and the cron-specific job for that tick | **CODE-FIX**: wrap each cron job (flush, reconcile, retention, rollup) in its own try/catch with logging so one failure does not starve the others | R4-62; SX-004 |
| C-16 | No `set_ai_availability` write RPC exists; enroll/rotate/revoke never write `app_settings`, leaving the doc's "manual step" gap | **CODE-ADD**: backend migration adding an owner-gated `set_ai_availability` RPC; Flutter wiring is a follow-up | R4-80; S02-011 |
| C-17 | No control-plane endpoint writes `kill_switch`; arming a provider/capability kill requires direct D1 access | **CODE-ADD**: operator control route to arm/disarm kill switches (also unblocks control-driven test variants of S05-069/070) | R5-27; R4-58 (kill_switch immortality is ACCEPT — see §3) |
| C-18 | Boot registry-install failure is silently swallowed: a runtime-invalid bundled manifest leaves a possibly-empty registry, degrading every resolution to `capability_unknown` while `/health` stays 200 | **CODE-FIX**: fail closed — rethrow (abort isolate boot) when the bundled manifest fails `load()`, after a V0 log. A manifest that cannot load is a build/deploy defect; serving degraded is worse | R4-3; `worker.ts:L150-L159`; S00-007/008 |

### 2.3 Low Priority

| ID | Finding | Decision | References |
|---|---|---|---|
| C-19 | Duplicate installation ids in one cohort activate write duplicate live grant rows (benign only because readers take latest) | **CODE-FIX**: dedupe ids in the activate handler | R4-20; `cohort.ts:L119-L156`; S04-070 |
| C-20 | `cohort_name` is accepted in the canary body but never read or stored | **CODE-FIX**: persist it in the audit row `details` (or reject unknown fields — persisting chosen for backward compatibility) | R4-28; S05-023 |
| C-21 | Rejection-tally coverage is uneven: guard stages 5–7 never call `recordGuardRejection`, so `platform_counter` undercounts beyond the documented isolate-eviction lower bound | **CODE-FIX**: add tally calls to capability/context/preflight rejections | R4-74 |
| C-22 | Fresh-revoke success payload returns a new `clock_timestamp()` that can differ by microseconds from the stored `revoked_at` | **CODE-FIX**: return the stored row value on the fresh path too | R4-78; `20260902130100…sql:L55` |
| C-23 | Unknown-provider fallback scripts `terminal:provider_unavailable` while behavior is retryable — token name misleads test authors | **CODE-FIX** (cosmetic): rename the scripted token to match its retryable semantics | R4-42; `worker.ts:L358`; S10-005 |
| C-24 | Truly dead code: adapter's second parse check (`adapter.ts:L409-L413` re-parses what L390-L393 proved) and `AdapterDisconnectReason "network_drop"` (all call sites pass `"client_close"`) | **CODE-REMOVE** both | R4-68, R4-41 |

---

## 3. Documentation Fixes

All DOC-FIX items, grouped by target document. Code stays as-is for these.

| ID | Fix | References |
|---|---|---|
| D-01 | Orientation doc: state that `/health` is method-agnostic (pathname-only branch) | R4-2; S00-034 |
| D-02 | Orientation doc §3.3: document `CONFIG_CACHE_TTL_MS` parsing (unset/empty/non-numeric/negative → 30 000 ms; `"0"` disables caching) and update the §6 cache-flush guidance to recommend `CONFIG_CACHE_TTL_MS=0` for tests | R4-4 |
| D-03 | Orientation doc: document `LOG_VERBOSITY` parsing (`V0/V1/V2` aliases, case-insensitive, invalid → V0, development default V2) | R4-5 |
| D-04 | Orientation doc §4: fix migration attribution — baseline creates 12 tables; `token_contract`(+seed), `kill_switch`, `grace_admission_queue`, `idx_entitlement_installation_id` arrive in four later migrations | R4-6 |
| D-05 | Orientation doc: distinguish the two 404 shapes (null-body 404 for empty/unknown references vs plain-text `Not Found` catch-all) | R4-7; S00-017, S12-013/014/018 |
| D-06 | Orientation doc: state that the control-plane 401 `{"error":"unauthorized"}` deliberately bypasses the taxonomy envelope | R4-8 |
| D-07 | Token-contract doc §4.1/§4.2: add `400 invalid_json` to both routes and `400 invalid_ver` / `401 unauthorized` to the retire table; document whitespace-trim acceptance and the no-length/charset contract for `ver` | R4-9; S01-023/024 |
| D-08 | Orientation doc §5: add a mapping note that pipeline-internal "stage 2" = catalog Stage 9 identity guard | R4-11 |
| D-09 | All control-plane failure tables: remove unreachable `400 invalid_route` rows (dispatch pre-filters); state that suspend/resume/delete/promote/retire ignore the request body entirely (drop retire's `400 invalid_json` row) | R4-12, R4-14 |
| D-10 | Stage-3 doc: state that rotate/revoke-key are permitted on suspended installations (only `deleted` is blocked), delete has no suspend precondition, and purge preserves prior `control_audit` history and the grace queue; fix purge audit cardinality to exactly two rows | R4-15, R4-16 (doc side); stage-03 drift #7/#8 |
| D-11 | Stage-4 doc §5: add reachable `401 unauthorized` and `400 invalid_json` to the entitle failure table; §3: document the plan-scope grant dedup skip; §11.2: relabel the "Unprobeable" items that the two-version registry seam makes automatable | R4-18, R4-19, R4-22 |
| D-12 | Routing-policy doc §8: state that post-accept routing failures surface only as SSE `failed`/`internal_error` (router codes never on the wire); §6.2: complete the canary failure table (`invalid_json`, `policy_version_not_found`, absent/non-array `installation_ids`); document multi-canary coexistence, cross-version `before_pointer`, serving order, and the canary-R2-miss no-fallback behavior | R4-23, R4-27, R4-29 |
| D-13 | Guard chapters: add reachability caveats — stage-1 `internal_error` for non-object JSON unreachable via POST (adapter 422 first); stage-8 `exp` recheck unreachable; document the harness-only `input.principal` path | R4-31, R4-70 |
| D-14 | Stage-10 doc §14: correct the `ai_attempt` table — `selection_reason` is in-memory only, not a D1 column (optional schema addition deferred); §4.1/§11.4: `text_delta.data` is `{text, sequence, provisional}` — `trace_id` lives on the event wrapper | R4-38, R4-39 |
| D-15 | Stage-10 doc §10: mark the structured relay path (`createStructuredStreamBroker`, `validateAndRepair`, `progress`/`partial_structured`/reask) as **dormant — not wired** until a structured-output capability ships; note `regenerating` IS reachable via the invocation loop | R4-40 |
| D-16 | Stage-10/11 docs: note that `cancelled` on a true client drop is emitted into a dead stream and is observable only via replay | R4-43 |
| D-17 | Stage-12 doc §1: `installation_suspended` is HTTP **403**, not 401; add the missing quota-inspect route and dashboard function sections; document the reference-normalization asymmetry (support lookup trims, clinic GET does not — intentional: machine clients send exact references, operator tooling is forgiving); fix the overbroad "control/* is POST-only" claim (quota inspect dispatches GET); document the code-only branches (NULL `terminal_error_code` fallback, unknown-state 404, corrupt-envelope handling, envelope fallback key, missing-entitlement nulls) | R4-44, R4-45, R4-46, R4-47 |
| D-18 | Stage-11 doc §3: remove `jti`/`idempotencyKey` from the credit RPC field table (self-contradiction with §10.3.6); §9: state that a caller-abort during an in-flight invoke writes a `terminal_failure`/`cancelled` attempt row; briefing: `usage_event` is written by the journal (`persistPostResponseDetail`), never by the Quota DO; document the broader `record_ai_acceptance` duplicate pre-check and the visit-id provenance under `table_name 'visit_clinical_notes'` | R4-48, R4-51, R4-52, R4-54 |
| D-19 | Orientation doc §9 failed-settlement table: remove terminal `timeout` (retryable-classified; chain exhaustion settles `provider_unavailable`) | R4-50; S11-004 |
| D-20 | Doc 15: enumerate all five `GraceDropReason`s, the reconcile-time `quota_exhausted` retry-churn, and the SX-018 leak; state that TTL cannot fire on first sighting (`reconcile_first_seen_at_ms` origin) and `queued_at` age is irrelevant | R4-57, R4-59 |
| D-21 | Docs 15/16/17: document the full retention surface (`usage_rollup`, `control_audit`, `capability_grant` at 2555 d including live grants, `platform_counter` at 90 d; `kill_switch` never purged — ACCEPT); fix the trigger-URL disagreement (verify `/cdn-cgi/handler/scheduled` vs `/__scheduled` against the installed wrangler and unify); fix the compressed two-purge description; fix the doc-18 sweep-ordering nit; state that `usage_rollup` has no in-repo reader (written for external reporting — ACCEPT); state that cron passes no time injection and sweeps are lazy (no DO alarm — ACCEPT) | R4-49, R4-58, R4-60, R4-61, R4-62 |
| D-22 | Discovery doc §3/§5: add `keys`, `token_contracts`, and the lifecycle-overlay grant reads to the D1-reads table; add `403 installation_suspended` to the failure paths; document revocation semantics (reader filters `revoked_at IS NULL`; installation-scope revocation does not delist when a plan grant exists); fix cosmetics (`DEFAULT_CONFIG_CACHE_TTL_MS` naming, bare-`Bearer` log-reason distinction, role/scope non-filtering stated explicitly, ETag contains no per-installation input) | R4-63, R4-64, R4-65 |
| D-23 | Ingress docs: state there is no Content-Type check and no header length/charset bounds (non-empty-after-trim only) — code is authoritative, the mission brief overstated; fix probe 8.3.9's `user_intent` fall-through claim (the `intent` alias IS used when `user_intent` is non-string) | R4-66, R4-67 |
| D-24 | Keypair docs (Stage 2/6): rotate succeeds with an all-revoked keystore (code authoritative — this is the recovery path); `issue_ai_token` raises P0001 (PostgREST HTTP error), not an `rpc_result` envelope, and its error table gains `UNAUTHENTICATED`/`SESSION_EXPIRED`/`STAFF_NOT_FOUND`; move `SINGLE_INSTALLATION_VIOLATION` out of the envelope error tables (trigger-level only, unreachable via RPC); replace "owner" terminology with administrator/`is_bootstrap_admin`; document guard ordering (role check precedes all validation) and the alphabetical branch tie-break | R4-75, R4-76, R4-77, R4-79, R4-80 (doc side), R4-82 |
| D-25 | Stage-9 doc: document the composed-`trace_id` divergence (`correlationIds.trace_id` = AAT `jti`; journaled `ai_request.trace_id` = `x-trace-id` header) | R4-73 |

---

## 4. Dead-Code and Defensive-Branch Policy

**Remove** (truly meaningless, no reachable or future-safety value): see C-24.

**Keep and annotate** (safety nets against half-finished future edits, or reachable via
direct-invocation test seams). Add a one-line comment at each site:

| ID | Branch | References |
|---|---|---|
| A-01 | `invalid_route` rejections in all control handlers (token-contract, lifecycle, entitle, capability-lifecycle, cohort, routing-policy, purge, quota-inspect) — unreachable via HTTP because dispatch pre-filters with identical regexes; reachable via direct handler invocation in tests | R4-12 |
| A-02 | `no_matching_rule` in the router — catch-all validation runs before matching, so `rules.find` cannot miss | R4-25 |
| A-03 | Stage-5 D1 kill-switch re-checks in the ordered guard — stage 3 evaluates the same rows first; keep as defense against pipeline reordering | R4-35 |
| A-04 | Control-dispatch `default:` 404 (`control/index.ts:L194-L197`) — fires only if an action is added to the pattern without a handler | R4-84 |
| A-05 | Guard stage-8 unexpected-outcome `internal_error` (`pipeline/index.ts:L466-L469`) — safety net for future DO admission outcomes | R4-85 |
| A-06 | Worker cancelled branch's non-skipCredit sub-path (`worker.ts:L931-L945`) — effectively unreachable via client disconnect | R4-55 |
| A-07 | Latent mappings: `cancelled` → HTTP 500 fallback at preAccept; `context_requested`/`AwaitingContext` at ingress — annotate as conversational-only/latent | R4-69 |
| A-08 | Issuer defensive raises (second `UNAUTHENTICATED`, second `STAFF_NOT_FOUND`) and `discover()`'s revoked-grant skip / non-string-plan / non-string-registry guards — unreachable via production paths; annotate so no chapter invents scenarios | R4-83, R4-64 (code side) |

---

## 5. Deferred Items

| ID | Item | Unblock condition |
|---|---|---|
| F-01 | `conversation_budget_exhausted` unreachable; `context_requested` terminal unreachable; `AwaitingContext`/unpublished-capability rows only seedable (R4-33, R4-36, R5-36) | A conversational capability ships — cover in that capability's stage chapter and re-express seeds as real operations |
| F-02 | Structured relay path wiring (broker, commit-time validation, reask) — documented as dormant in D-15 (R4-40) | A structured-output (`Output.mode`) manifest ships |
| F-03 | `repair` attempt outcome unreachable for `clinic.visit_summary` (R4-56) | A manifest with `repairPolicy.allowed: true` ships |
| F-04 | `perRequestTokenCeiling` not independently trippable (9 024 − 1 024 = 8 000 = `maxInputTokens`) (R4-36 note, R4-36) | A manifest where `perRequestTokenCeiling − maxOutputTokens < maxInputTokens` ships |
| F-05 | Router-seam scenarios for legacy `@vN` refs, structured-output requirements, multi-language floors, non-hardwired cost sources (R5-26) | Such manifests ship; re-express as full-path journeys |
| F-06 | Deadline-driven invocation branches; production never sets `GuardInput.deadline` (R5-34) | Decide whether invoke deadlines become a product feature; until then unit-test territory only |
| F-07 | Heartbeat ticker injection for fast tests (R5-23) | Only if the ~16 s wall-clock heartbeat test becomes a CI burden |
| F-08 | Multi-operator audit attribution (R5-25) | Multi-operator deployments become a requirement |

---

## 6. Closed / No-Action Items

| Item | Why no action |
|---|---|
| R4-1 (Stage 6 stale guard claim vs Stage 2) | Already resolved: the 2026-09-02 guard migrations exist, Stage 2 is correct, the stale Stage 6 text was corrected at source in the registers pass |
| Register 5 seams (test-automation limits: single isolate, wall-clock horizons, PostgREST HTTP shapes, timing-safe compare, concurrency races, non-deterministic values, pgsodium availability, Content-Length control, disconnect races, DO/D1 fault injection, platform cron triggering) | Each already carries a proposed seam or an explicit "recorded, not scenarized" decision; implement the seams as written when building the test suites. Exceptions needing production changes were promoted to C-15/C-17/F-06/F-07 |
| Stage-00 confirmed-no-drift items, Stage-2 `is_bootstrap_admin` escape hatch, jti collision | Verified consistent or unreachable by construction; recorded for completeness only |

---

## 7. Suggested Implementation Order

1. **Phase 1 — correctness:** C-03 (one-line seed fix), C-01, C-02, C-04 (fabricated-completion replay).
2. **Phase 2 — contract hardening:** C-05, C-06, C-07, C-08, C-09, C-10, C-11, C-12, C-18.
3. **Phase 3 — lifecycle/state-machine decisions:** C-13, C-14 (need owner confirmation), C-15, C-16, C-17.
4. **Phase 4 — documentation sweep:** D-01…D-25 (can run in parallel with Phases 1–3; each doc edit should land with or after its related code change where one exists).
5. **Phase 5 — cleanup:** C-19…C-24, annotations A-01…A-08.

Every code change above already has catalog scenarios pinning current behavior; update or
add scenarios (S-numbers referenced per row) in the same change.

---

## 8. Sequencing Relative to Scenario Implementation

The catalog scenarios are not yet implemented — they exist only as documents. Many of
them deliberately pin the *current* (drifted or buggy) behavior, e.g. S01-013/S01-017 pin
the `TypeError` crash, S10-017 pins the fabricated `"Prior request completed."` replay,
S06-043 pins the always-rejected default-lifetime token, S05-039/S05-046 pin the 200
no-op transitions, SX-004 pins the abort-on-flush-failure tick. That creates a hard
ordering constraint:

1. **Behavior-changing code fixes go FIRST** (C-01…C-15, C-18…C-23). Implementing
   scenarios against today's behavior means writing tests that the remediation then
   immediately breaks and rewrites — double work. Instead: apply the code fix and edit
   the affected scenario *text* in the catalog in the same commit (the S-numbers are
   listed per row in §2), so the scenarios are written once, against final behavior.
2. **CODE-ADD items (C-16, C-17) are independent** of existing scenarios but cheaper
   before them: S05-069/S05-070 can then be written as control-plane-driven journeys
   instead of [SEED]-only, and the new RPC/route gets its scenarios added to the
   relevant chapter directly.
3. **Dead-code removal and annotations (C-24, A-01…A-08) can go anytime** — the removed
   branches are unreachable, so no scenario is affected.
4. **Documentation fixes (D-01…D-25) are independent of scenario implementation** (they
   target the orientation/stage docs, not the catalog), but each should land with or
   after its related code change so docs never describe an intermediate state.
5. **Deferred items (F-01…F-08)** are by definition after — they wait on future
   capabilities, not on the test suite.

Net: do Phases 1–3 of §7 *before* (or interleaved chapter-by-chapter with) scenario
implementation; never implement a chapter's scenarios before its chapter's fixes. A
chapter-by-chapter interleave is the practical path: for each stage, apply its fixes +
catalog text edits, then implement that stage's scenarios.
