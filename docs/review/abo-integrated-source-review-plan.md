# ABO integrated source-code review plan

Status: review complete. Prepared: 2026-10-16. Completed: 2026-10-18 (Africa/Cairo). Review completion does not approve launch or resolve findings.
Reviewer for **every review phase R1–R10: GPT-6.1 Sol at explicitly selected high or medium reasoning effort only**, in a fresh context per phase. Light/low effort and unpinned defaults are not permitted for review or synthesis.
Track execution in the [phase status table](#8-phase-status-tracker). Each agent must update its row when starting, checkpointing or completing its phase.

This plan reviews the completed implementation of [the ABO delivery plan](../architecture/ai-billing-orchestration/06-abo-delivery-plan.md) as one system. Its boundaries follow connected business flows and trust boundaries across delivery units, rather than repeating the earlier subphase reviews. Existing passing campaigns and Grok reviews are background information, not evidence that a source path is correct.

**Priority:** concentrate review effort and report prominence on critical and major findings. Other actionable findings are welcome after those risks have been investigated. Every finding must include brief, concrete implementation steps for a future lower-cost agent; the frontier reviewer owns the diagnosis and remediation design.

Only planning and repository/document inventory were performed to prepare this file. No implementation review, test review, or viewer review was performed.

The schedule is one preparation step, nine broad source-review phases, then one integrated review. Each source phase spans several delivery units and checks a connected flow across components.

| Phase | Integrated scope |
| --- | --- |
| R0 | Freeze scope, map source ownership and escalation amendments |
| R1 | Tenant identity → token issuance → clinic authorization |
| R2 | Shared contracts → service perimeter → human approval |
| R3 | Administrator checkout → provider evidence → confirmed payment |
| R4 | Confirmed payment/grant → durable coverage → term lifecycle |
| R5 | Admission, accounting and fallback | complete with findings | [Report](abo-integrated/R5-admission-accounting-fallback.md) · [Coverage](abo-integrated/R5-coverage.md) | 2026-10-17 | 0 P0, 6 P1, 5 P2; all 555 regions/10,234 final+303 deleted lines closed by explicit high lead and two medium reviewers. Outage replay policy and historical attribution decisions remain explicit; source unchanged. |
| R6 | Reversal/value reduction → transfer/deletion → delayed-work safety |
| R7 | Coverage events → backend projection → desktop-visible state |
| R8 | Operator console → configuration/control methods → audit |
| R9 | Durable facts → rebuild/reconciliation → executable operations |
| R10 | Adversarial interactions across those flows and consolidated findings |

## 1. Scope and immutable review target

### 1.1 Revisions

Pin these revisions when starting; branch names can move:

| Reference | Revision | Purpose |
| --- | --- | --- |
| Target `T` | `db9244fddfddc1905335fb8c7105328c15a0cc5e` | Current `master` squash; authoritative source to review |
| Squash parent `S` | `bd51a11e730e5340ffc742cab6033c3a58c7a11c` | Records what the squash changed on master; **not** the ABO-only baseline |
| ABO baseline `B` | `c6cf2c3809a38e2a348f373e926cf2585cfcf291` | Parent of `ed65cd2d6`, which introduced ABO v2 design and delivery docs; separates earlier platform implementation from ABO work |
| History tip `H` | `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f` | Current `ai/abo-master`; use unsquashed history to understand provenance and later fixes |

The squash contains earlier AI-platform development and unrelated changes too. Do not review `S..T` wholesale. Use `B..T` to identify candidate changes, the delivery plan/specs to establish relevance, and **final source at T** for conclusions. Review relevant deletions and replacements as well as additions. Read unchanged callers/callees when necessary to establish actual behavior, without turning that context into an audit of the old platform.

At planning time, `T` and `H` differ in `.github/workflows/ci.yml` and captured artifacts, not application source. They are not identical trees. Do not substitute the history checkout for the target or import its artifacts into scope. Recheck this comparison if the target is changed.

Include production-source fixes made after the last delivery unit, even when their commits are titled as campaign/test fixes. In particular, classify the later staff-membership/RLS migration, canonical billing/feed JWT migrations, request-fingerprint migration, and changes to payment intake, grants, and runtime decoding by their source effects. Commit subjects are not exclusion rules.

### 1.2 What is reviewed

- Production TypeScript, Dart, SQL migrations, and operational executable code implementing or affected by ABO.
- Runtime bindings, deployment configuration, dependency/export configuration and executable security guards **only where they determine production behavior**. These are supporting source artifacts, not a separate infrastructure audit.
- Final implementations of renamed or removed mechanisms: legacy identity, entitlement/period logic, availability RPCs, installation-key routines, `/control/*`, and bootstrap paths.
- Existing dependencies and callers needed to evaluate tenant isolation, clinical continuity, and regression effects of the ABO changes.

Explicitly excluded: all test cases, test design/coverage, harnesses, stubs, fixtures, golden vectors, campaign runners/reporting, test configuration, CI campaign mechanics, captured results, and the entire `ai-platform-viewer/`. Exclude `packages/vendor-contracts/src/testkit/` despite its location under `src`. Exclude generated localization implementations from manual review; review their `.arb` inputs and production usage. The runtime fact that a test-only clock or override must be inaccessible in production remains in scope; its tests do not.

Architecture docs, specifications, escalation records and runbooks are **reference material for reviewing source**, not a separate documentation-quality review. Do not re-run the acceptance campaign, conduct live provider research, operate staging/production, change code, or fix findings during these review phases. If source cannot prove an external assumption, record the limit instead of guessing or executing it.

## 2. Review authority and escalation handling

Use these documents at the pinned target:

| Reference | How reviewers use it |
| --- | --- |
| [Constitution](../../.specify/memory/constitution.md) | Highest repository governance; verify authority boundaries and approved exceptions |
| [00 Requirements](../architecture/ai-billing-orchestration/00-abo-requirements-seed.md), [01 Decisions](../architecture/ai-billing-orchestration/01-abo-design-decisions.md) | Original intent, constraints, risk assumptions and rationale |
| [02 Architecture/threat model](../architecture/ai-billing-orchestration/02-abo-architecture-and-threat-model.md) | Components, trust boundaries, credentials, adversaries and rotation |
| [03 Data/lifecycle](../architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md) | Stores, authority, immutable facts, state transitions and coverage rules |
| [04 Contracts](../architecture/ai-billing-orchestration/04-abo-contracts.md) | Producer/consumer obligations, validation, receipts, errors and channel versions |
| [05 Operations](../architecture/ai-billing-orchestration/05-abo-operations-and-traceability.md) | Scheduled work, alerts, failure recovery and traceability |
| [06 Delivery](../architecture/ai-billing-orchestration/06-abo-delivery-plan.md) | Unit-to-source provenance and scope, including the P5.2a/P5.2b split |
| `specs/061-abo-*` through `specs/098-abo-*`, including `088b` | Phase-specific requirements/clarifications; plans/tasks are navigation aids, not correctness evidence |

**Read the current amended architecture**, not an original draft. The 30 existing `escalations.md` files contain 75 numbered entries; their routing is listed in §7. Nine other delivery units currently have no escalation file; absence does not imply that one must be created.

During preparation, give every escalation entry a stable ID `<spec-number>:<entry-number>` and record its question, assumption/resolution, amended paths/sections, downstream consumers, and owning review phase(s). An entry whose only effect is a test/harness/workflow instruction is classified `reference-only / excluded effect`; do not inspect its test code. An entry changing a contract or source behavior must be traced through **both producers and consumers**, including later units that did not originate the escalation. For example, the grant-approval amendment in spec 079 also affects the shared package; spec 088 changes affect desktop consumers as well as backend code.

The previous workflow's “binding assumption” rule explains how implementation proceeded; it does not exempt that assumption from this integrated review. Check that the amended rule preserves the system invariants and that all consumers implement it consistently. Where an escalation, current architecture and spec disagree, identify the exact conflict and its source effect; do not silently choose the convenient interpretation. A lower-level escalation cannot silently amend the constitution. Do not report a design choice as a bug merely because an older document said something else.

## 3. Preparation R0 — build the review packets

R0 is a bounded inventory step, not a correctness-review phase. It must finish before R1. Use GPT-6.1 Sol if an agent performs it; do not start implementation or delegate work as part of this plan's creation.

1. Verify `B`, `T`, `H`, clean checkout state, relevant repository instructions, and the source differences between `T` and `H`. Work against a read-only target or isolated checkout; do not switch a shared working directory underneath another task.
2. Generate `git diff --name-status B T` and `git diff --numstat B T`. Classify every candidate as `primary source`, `supporting runtime artifact`, `reference`, or `excluded`, with a concrete reason. Apply the exclusions in §1.2, including test files outside test directories. Classify unrelated incidental UI edits explicitly rather than silently adding them to the ABO review.
3. Use `git log B..H -- <path>` only when needed for provenance. Map specs 061–098 plus 088b to final changed paths; include later source fixes and deleted symbols. Do not ask a reviewer to read every intermediate patch or reproduce every earlier review.
4. Produce the escalation index described in §2. Route entries by affected behavior, not just originating unit. Reference-only entries still receive a disposition, so none silently disappear.
5. Assign **every in-scope file and changed region** a primary owner R1–R9 using §5. For shared files, partition by symbols/SQL definitions and record exact line ranges at T. Identify unchanged supporting callees separately. No changed region may be left as “shared, someone else will review it.”
6. Prepare a short system map showing each store's authority, credentials, version channels and the principal flows. Prepare one packet per phase: question, bounded source manifest, relevant doc sections, escalation IDs, dependency/interface notes, and inherited open seam questions.
7. Save the packet index and inventories under `docs/review/abo-integrated/`. Record the exact target SHA in each file. These are future execution outputs; this planning task creates only this plan.
8. Update R0 in the §8 status table, linking the packet index and recording completion only after the preparation exit gate is met.

**Preparation exit gate:** complete file/region ownership, all escalation entries routed, bounded phase packets, and a declared dependency order. Missing inventory is not a clean review result.

### Context and sizing rules

- Use **one fresh GPT-6.1 Sol context per phase**. Default to sequential execution in the order below; this plan does not require parallel agents.
- Explicitly set `reasoning_effort` to `high` or `medium` on every reviewer, continuation and synthesis agent launch. Use high for phase leadership, cross-component synthesis and difficult security/concurrency reasoning; medium is allowed for bounded review assignments. Do not use light/low effort or rely on the model's default. Record actual model/effort settings in the report and coverage record. This requirement was added on 2026-10-17; earlier unpinned launches must not be retrospectively described as high/medium. R4's initial unpinned agents were interrupted and its source review must be completed by explicitly configured agents.
- Target roughly **4,000–8,000 lines of primary source** per phase, plus up to about 2,000 lines of directly relevant supporting code. Count the final functions that must be read, not just diff additions. These are packet-sizing targets, not a claim that line count proves review quality.
- Keep initial context below roughly half the available window, and reserve at least a quarter for tracing, checking hypotheses and writing the report. Load precise sections as needed; do not paste all specs, all docs or an entire repository diff.
- If sizing exceeds the target, first remove irrelevant old code and duplicate supporting reads. If it still cannot fit, use two fresh sessions for the **same coherent phase**, with named source-region ownership and a final synthesis of that phase. Do not split back into delivery units or declare a partial session complete.
- Long files require explicit coverage. At T, `vendor/entrypoint.ts` is about 5,146 lines, `quota-do/coverage.ts` about 4,315, and `abo/src/ops/index.ts` about 3,825. Partition their symbols in R0; do not load all three into a phase or rely on summaries in place of reading owned regions.
- Checkpoint before context exhaustion: save regions read, traces established, unresolved questions and exact continuation point. A successor reads that checkpoint and source, not the entire conversation.

## 4. Review phases

The unit lists below explain provenance, **not review boundaries**. Every phase follows a complete flow across the named components. The packet manifest controls exact regions and captures any extra source discovered during preparation.

### R1 — Tenant identity, token issuance and clinic authorization

**Question:** Does the current authenticated membership determine the same clinic and authority from SQL issuance through vendor authentication, including stale sessions and key changes?

**Primary source:** backend membership/tenant-scoping migrations and later staff-membership/session-RLS fix; issuer-key-custody and canonical billing/feed JWT migrations; platform `identity/` and identity/binding/key-registry sections of `vendor/entrypoint.ts`; ABO `clinic-api/auth.ts`; Dart token-minting ports and `billing_token_client.dart`. Include the actual final SQL definitions and their grants, RLS, definer ownership and search paths, following migration order and overrides.

**Read:** 02 §§2–3, 6–7; 03 §4 and identity rows in §3.2; 04 §§2.1, 3.1, 4.1–4.2. Provenance: P1, P3.2, P4.1, P5.1, P6.1 and later fixes. Escalations: 066, 076, 087, plus token-related amendments routed from other units.

**Trace together:** active-org selection → live-membership recheck → role/scope/audience claims → signing key → platform/ABO verifier → tenant binding. Include role removal, org switching, missing/legacy claims, key rotation/revocation, token lifetime and issuance limits. Review inherited tenant-scoped tables/RPCs touched by P1 as one authority surface, not merely the new billing functions. Check that no vendor service gets a Supabase credential or clinic write path.

**Handoff:** identity/authority table and exact consumers to R2, R3, R5 and R7; unresolved authorization questions remain explicitly open.

### R2 — Shared wire contracts, service perimeter and human approval

**Question:** Do callers and receivers agree on authenticated bytes, accepted versions and the authority needed for each kind of operation?

**Primary source:** production `packages/vendor-contracts/src/` exports, canonicalization, identifiers, JWS, claims, messages, receipts, WebAuthn and Access verification; vendor entrypoint dispatch/authentication/assertion/replay sections; ABO host/version middleware and console Access/passkey/operation-binding sections; relevant worker/DO version dispatch. Read consumer use at the actual verification sites, not just package implementations.

**Read:** 02 §§1.3–1.4, 2–4, 6; 04 §§1.1–1.6, 2.3, 7. Provenance: P2, P3.1–P3.3, P4.1, P4.6–P4.7, P7.2–P7.3. Escalations: 066–067, 076, 079, 081–082, 094–095.

**Trace together:** public request/service-binding call → correct version rejection order → Access identity or machine credential → operation hash and bound arguments → passkey verification → replay recording → authorized dispatch. Check ceremony freshness, actor/credential binding, delayed activation/bootstrap, exact mutation authorization, and cross-host/route bypass. Check package behavior against SQL/Dart producers and receivers without reviewing vectors or testkit. Separate receipt cryptographic validity from its business-state effect, which R4/R6 review.

**Handoff:** channel/version matrix, M/H/HP method-authority map, and proof obligations for all value-moving consumers in R4/R6/R8. R8 still owns each method's specific policy and mutation.

### R3 — Administrator checkout through confirmed payment

**Question:** Can a legitimate checkout become exactly the intended confirmed payment, without browser returns, callbacks, retries or overlapping workers creating unsupported value?

**Primary source:** ABO offers/contact/checkouts, provider port/registry and Paymob client/adapter, notification intake, confirmation and lease sections of `work/runner.ts`, inquiry-budget code; corresponding checkout/evidence/payment/work schema; Flutter offers/contact/checkout flow and the associated `abo_client.dart` operations. Include return routes and worker scheduling that connect these modules.

**Read:** 03 §§2.1–2.6, 2.9, 2.11, 5.1–5.2, 5.6; 04 §§2.2–2.3, 5; 02 TB-1 and billing boundaries; 05 relevant scheduled work/failure modes. Provenance: P4.1–P4.3, P4.5, P6.3. Escalations: 076–078, 080 inquiry budget, 091, and any later provider/source fixes.

**Trace together:** displayed offer/contact → immutable checkout snapshot and idempotency key → intention request → callback evidence → authoritative inquiry → confirmed payment and queued grant. Include same-key/different-payload retries, multiple provider successes, amount/currency/account correlation, forged/duplicate/late notifications, missing callback, lease expiry and process failure between durable writes. Verify redirects are UX signals only and do not authorize confirmation. Follow provider budget consumption across every caller.

**Handoff:** exact payment/grant eligibility boundary to R4; reversal identities and provider normalization to R6; durable-evidence obligations to R9.

### R4 — Confirmed money to durable coverage and term lifecycle

**Question:** Does each eligible payment or authorized grant produce the intended coverage once, with consistent terms, receipts and renewal behavior across ABO and the platform?

**Primary source:** ABO `work/grant.ts`, grant-related runner paths, grant request/outcome/attempt schema; platform paid/complimentary grant validation/application and plan-version snapshot sections of the entrypoint; DO grant placement, term activation/renewal/grace and calendar logic; D1/R2 grant ledger/event/mirror writes; shared grant-envelope and receipt consumer sites. R2's package review is supporting context, not a substitute for checking how values are used.

**Read:** 03 §§2.8, 3.1–3.3, 5.3–5.4, 5.7, 6.1, 6.3–6.4, 6.7–6.8, 7; 04 §§1.3–1.4, 1.6–1.7; 05 grant failure modes. Provenance: P3.3, P3.5–P3.6, P4.4 and P4.8. Escalations: 067, 068, 069, 070, 079; 083 lineage rules where relevant.

**Trace together:** confirmed payment → deterministic grant/envelope/approvals → platform validation → ledger/DO effects → signed matching receipt → ABO outcome/projection. Include lost replies, transient failure after a partial durable effect, duplicate/conflicting grants, unsupported/retired plans, queued successors, exhaustion vs expiry, end-of-month arithmetic and grace. Evaluate all relevant stores' ordering together, not a happy-path review of one method.

**Handoff:** state-transition and idempotency table, receipt-to-state linkage, and crash windows to R5/R6/R7/R9.

### R5 — Live AI admission, allowance accounting and fallback

**Question:** Does every admitted request charge the right term at most once while preserving coverage, concurrency and overshoot bounds through failures?

**Primary source:** platform `quota-do/index.ts` and admission/reservation/settlement/alarm parts of `quota-do/coverage.ts`; `admission/`, `credit/`, changed `pipeline/`, entitlement/capability/discovery readers and cache behavior; request idempotency/fingerprint handling and its migration; changed worker request, stream handoff, settlement and fallback-drain paths; relevant journal/usage/rollup changes. Include changed manifest/vocabulary/routing/threshold dependencies.

**Read:** 03 §§3.1–3.2, 5.4, 5.7, 6.2–6.7; 04 §§4.2, 6.1; 05 fallback/settlement failure modes. Provenance: P3.2–P3.5, P3.9–P3.11 and later request-fingerprint fixes. Escalations: relevant 066–069, 073, 075, 095.

**Trace together:** issuer principal → fresh coverage check → reserve → actual provider/stream outcome → settlement/journal → release/retry, and DO-unreachable → mirror/fallback admission → later drain. Include request-ID reuse with changed payload, replay, cancellation, late completion, term changes while work is active, concurrent requests, and duplicate settlement. Check removal of old period/tier paths and that denied or replayed calls do not create unintended writes. Read only ABO-affected invocation/stream/provider context; do not reopen the entire old AI engine.

**Handoff:** accounting invariants, fallback bounds and remaining recovery questions to R6/R7/R9.

### R6 — Reversals, operator value changes, transfer and deletion

**Question:** Can coverage be reduced, moved or removed safely despite delayed grants, stale bindings, duplicate evidence and interrupted multi-store operations?

**Primary source:** ABO `work/reversal.ts`, sweep recovery paths, reversal/provider normalization, transfer work and related console relays; platform void/tombstone/held-term/release/adjustment/suspension/deletion methods, `coverage/transfer.ts` and corresponding DO sections; grant-void/transfer/binding schema and receipts. Include operator-action construction for these operations, not just platform receivers.

**Read:** 03 §§2.7–2.9, 3.1–3.3, 5.5, 6.1–6.4, 7–8; 04 relevant value-changing methods in §1.3, validation/receipts; 05 §3.2 and corresponding failure modes. Provenance: P3.6–P3.8, P4.5, P4.7–P4.8. Escalations: 070–072, 080, 082–083.

**Trace together:** full/partial refund or chargeback → reversal identity → void/tombstone → held/reserved coverage; and asserted transfer → source freeze/export → destination import → binding-epoch changes → status/feed. Include reversal-before-grant, repeated/pending reversals, stale async messages after transfer/deletion, origin-grant lineage, source/destination retries, and suspension/resume interaction with running requests. Check conservation of value across terms/clinics and immutable audit lineage. Include contact erasure and retained commercial facts where deletion connects to them.

**Handoff:** reversal/transfer failure-state map and consumer invalidation obligations to R7/R8/R9.

### R7 — Coverage feed, backend projection and desktop-visible state

**Question:** Does authoritative platform state reach the correct user's desktop with correct ordering, freshness, notices and role restrictions, without blocking clinical work?

**Primary source:** platform feed/coverage-read methods and event/mirror producers; backend coverage-feed-puller/status and read-time-notice migrations, including later overrides; ABO coverage view, billing reads and corresponding work updates; Flutter availability/status providers, host/degraded/AI pages, subscription/payment/notices, app routing/settings entry points and relevant RPC/HTTP/SSE adapters. Review the relevant `abo_client.dart` read/parse behavior and `.arb` inputs.

**Read:** 03 §4, §5.7 and event ordering/epochs; 04 §§1.7, 2.2, 3, 4.1–4.2; 05 FM-06/FM-10/FM-11 and §5.4. Provenance: P3.9, P4.2/P4.4–P4.5, P5.2a/P5.2b, P6.1–P6.4. Escalations: 073, 079, 088, 088b, 089, 091–092.

**Trace together:** grant/usage/reversal/transfer event → paginated feed → cursor/epoch/version checks → SQL projection → read-time status → role-specific desktop action and presentation. Include out-of-order/repeated pages, cursor recovery, stale responses, grace/lapse at read time, refreshing after denials, cached credentials and org/role changes. Check staff cannot obtain administrator commercial details, missing/unknown states fail safely, and subscriptions/checkout/payment history remain consistent with authoritative state. AI denial must preserve ordinary clinical workflows.

**Handoff:** producer-to-display field mapping, stale/error semantics and unresolved contract seams to R9/R10.

### R8 — Operator control plane, configuration and privileged workflows

**Question:** Do the final console and platform methods enforce the same operator intent, policy and audit guarantees throughout configuration and support operations?

**Primary source:** remaining ABO `ops/index.ts` sections; platform remaining vendor entrypoint method implementations; retained `control/*` handlers for routing, cohort, capability lifecycle, kill switches and token contracts; support/installation-lifecycle routes and audit writes; registry/bootstrap/plan-version/ceiling configuration policies and removed bootstrap script. R2 owns common cryptographic/perimeter machinery; R4/R6 own coverage mutations; this phase owns method-specific validation, dispatch and cross-action interactions.

**Read:** 02 §§3.3, 4, 6; 03 relevant registry/configuration/audit rows; 04 §1.3 and changed/removed control paths; 05 §§3.1–3.2. Provenance: P3.1–P3.3, P3.6, P3.10, P4.6–P4.9, P7.1. Escalations: 066–067, 070, 074, 081–083, 093.

**Trace together:** operator lookup/form → displayed target and operation args → policy/class checks → final service-binding method → durable audit/result. Include issuer/service/operator-key lifecycle, bootstrap and second credential, ceiling and plan changes, support data visibility, kill-switch propagation, and routing/capability configuration. Check absence of legacy `/control/*` entry routes and bearer-token backdoors in production code; retained internal `control/` filenames alone are not a defect. Review cross-action consistency and every remaining public method, not merely the console happy path.

**Handoff:** complete method coverage, configuration lifecycle/audit map and outstanding security seams to R9/R10.

### R9 — Durable records, recovery, reconciliation and executable operations

**Question:** Can the system detect divergence and recover durable truth without issuing duplicate value, losing audit evidence or exposing production-only bypasses?

**Primary source:** ABO record append/export, rebuild and rebuild script, reconciliation/payout import/finding resolution, alert/lock/digest/watch/housekeeping modules; platform alert, retention, rebuild entrypoint/DO sections and related rollup/support changes; worker cron wiring; all remaining runtime D1 migration constraints/triggers and final schema consistency; operational `launch-check.mjs`, `audit-watcher.mjs`, `heartbeat-monitor.mjs`; worker/backend runtime config and executable source-boundary/residue guards. Consult runbooks only to establish what these programs claim to do.

**Read:** 02 §§1.4, 4–6; 03 §§1, 2.1, 2.10, 3, 8; 05 §§1–7 and non-code launch conditions as limits. Provenance: P3.1/P3.8/P3.11, P4.1/P4.10–P4.11, P7.1, P8.1/P8.3. Escalations: 075–076, 081, 085–086, 093; 097 as reference-only workflow context.

**Trace together:** immutable fact → D1/R2 ordering → export/lock → projection/rebuild → resumed work/re-inquiry → reconciliation and alert. Include failure after each durable side effect, replay with existing IDs, gap handling, tampered/missing/mismatched receipts, payout correlation, alert failure/deduplication, retention and missed cron execution. Check deployment bindings, inaccessible test overrides/clocks, environment separation, public exposure, and whether operational programs check live authoritative state or merely trust supplied snapshots. Record source limits explicitly; static review cannot attest actual production account settings, key ceremonies or external monitor uptime.

**Handoff:** durability/recovery matrix, all remaining source-region coverage, and unresolved operational-source assumptions to R10.

### R10 — Integrated adversarial seam review and final synthesis

**Question:** Do the separately reviewed flows still compose correctly when identity, payment, coverage and recovery events overlap?

Use a fresh GPT-6.1 Sol context. Inputs are the compact system map, coverage and escalation indexes, R1–R9 reports, and **selected actual source at the seams**. This is a bounded integration review, not a report-only summary or a second full repository pass. Plan roughly 3,000–5,000 lines of targeted source plus the compact reports; expand only named unresolved seams.

Trace these combined narratives statically, without reading or executing tests:

1. Checkout creation → callback duplication → confirmed payment → platform applies grant but reply is lost → retry → coverage feed/status update → first AI settlement.
2. Org/role change or membership removal while cached tokens, checkout polling, status refresh and administrator views are active.
3. Full reversal before/after grant application, concurrent AI reservation/settlement, and delayed callback/work replay.
4. Term exhaustion/expiry/renewal at the same time as DO failure, fallback admission, queued-term activation and projection staleness.
5. Operator/service/issuer-key rotation or revocation during a value-moving request, retry and transfer; assertion replay with altered target/arguments.
6. Transfer/deletion followed by late grants, voids, feed pages and cached bindings; verify epoch and lineage decisions across both clinics.
7. D1/R2 partial failure or rebuild followed by work replay, projection reset, reconciliation and alert delivery.
8. Version disagreement at a producer/consumer boundary during ordinary requests, privileged operations and asynchronous work; verify safe failure and no partial mutation.

For each narrative, identify the invariant, entry points, durable-state ordering, retry identity, eventual result and visible failure behavior. Resolve contradictory phase assumptions and duplicate findings. Check escalation propagation and legacy path removal across components. Revisit only the source needed to establish the seam; summaries cannot prove behavior.

**Exit:** a consolidated source-review report with supported findings, residual uncertainties, source coverage, and explicit exclusions. If a seam is too large or unresolved, assign a bounded continuation with exact source/contract ownership; do not declare completion merely because the context budget is nearly exhausted.

## 5. Source ownership and overlap rules

R0 expands this map to an exhaustive file/region manifest. `Primary` means a full correctness review of owned changed regions; other phases read those regions only as supporting context unless they own a different concern.

| Source family | Primary ownership |
| --- | --- |
| Backend membership, tenant scoping, issuer custody, session-RLS and canonical JWT migrations | R1; R7 owns projection/status SQL; R9 checks migration ordering/configuration as a whole |
| Package production source | R2; R4/R6 verify grant/receipt business use; R7 verifies snapshot/event consumption |
| Platform vendor entrypoint | R1 identity/registries and binding; R2 common auth/version/assertions; R4 grant/plan snapshots and lifecycle; R6 value reduction/transfer/deletion; R7 feed/read methods; R8 remaining configuration/support/method policies; R9 rebuild/operational methods |
| Platform DO coverage and gateway RPC dispatch | R4 placement/term lifecycle; R5 admission/reservation/settlement/fallback/alarm dispatch; R6 void/held terms/transfer/delete; R9 rebuild/durable recovery |
| Platform worker | R2 common route/version perimeter; R5 live request/handoff/fallback; R7 feed/coverage route wiring; R8 removed control dispatch; R9 scheduled/recovery wiring |
| Platform identity/cache | R1 identity and tenant binding; R5 coverage cache/admission implications |
| Platform capability/entitlement/pipeline/admission/credit, changed adapter/router/errors/discovery/manifest/vocabulary/threshold/journal | R5; R7 owns resulting client-facing field/denial mapping |
| Platform `coverage/transfer.ts`, `coverage/calendar.ts`, coverage read, alert, retention/rollup/support | R6 transfer; R4 calendar; R7 coverage read; R9 alert/retention/rollup; R8 support authorization/lookup, R9 support retention |
| Deleted platform identity/control/plan/entitlement/period/usage modules and bootstrap script | R1 old identity; R5 old period/usage; R8 old control/bootstrap; verify replacement and reachability, not historical style |
| ABO clinic API | R1 auth; R2 common host/version gates; R3 offers/contact/checkout/rate; R7 billing reads |
| ABO provider/notify/work | R3 provider/notify/confirmation/leases/inquiry budget; R4 grant; R6 reversal/sweep/transfer; R9 scheduler recovery; explicitly partition `runner.ts` and provider reversal sections |
| ABO `ops/index.ts` | R2 ceremonies/perimeter; R6 coverage mutation and transfer relays; R8 remaining operator UI/policy/methods; R9 payout import/finding resolution; R3 any payment re-inquiry dispatch |
| ABO records/coverage view/rebuild/reconciliation/alert/digest/watch/housekeeping/worker | R9 durability and scheduling; R7 coverage view/read updates; R2 worker exposure; R3 request/return wiring |
| Runtime D1 schemas and migrations | Colocate table/constraint review with R1/R4/R5/R6/R8 by behavior; R3 owns checkout/payment/work schema; R9 owns append-only/export/reconciliation and full migration consistency |
| Flutter token ports/RPC invoker | R1 minting/auth; R2 contract/version propagation; R7 status consumers |
| Flutter billing screens and `abo_client.dart` | R3 offer/contact/checkout writes and polling; R7 subscription/payments/notices and read parsing; R2 shared request/version/error encoding |
| Flutter status/availability/host/degraded/presentation/surface/app/settings wiring, HTTP/SSE/discovery/usage adapters and localization inputs | R7 behavior and clinical continuity; R5 request/accounting protocol use; R2 version handling |
| Worker/package/TypeScript dependency and export config, Supabase runtime config, operational scripts, source import/residue guards | R9 production effects; R2 package export/perimeter security; R8 removed bootstrap behavior |
| Other candidate source, including incidental shared Flutter UI edits | R0 records ABO relevance. Relevant regions go to R7 or their flow owner; unrelated regions receive an explicit exclusion reason. No blanket review of unrelated product changes |

Whole-file completion is allowed only after all assigned regions have been read. Splitting a large file across phases must account for shared helpers, dispatch, error handling and schema setup as well as named business methods. A helper cannot be excluded because it predates ABO when its behavior determines an owned invariant.

## 6. Execution, reporting and completion

### Sequence and handoffs

Run `R0 → R1 → R2 → R3 → R4 → R5 → R6 → R7 → R8 → R9 → R10`. Reports can contain open questions for later phases, but they must name an owner and the concrete source/contract involved. Later phases may update an earlier conclusion through an explicit addendum. Carry compact interface/invariant notes forward instead of entire transcripts. No phase is limited to the originating unit's old “Read only” or “Do not read” lists; those lists served implementation scheduling, not this integrated review.

Do not change the target during R1–R10. Keep remediation separate from diagnosis. If fixes are later authorized, record a new target and review each changed region plus affected seams; do not mix different revisions into a single completion claim.

### Finding priorities and risk areas

Spend most investigation, source-tracing and report space on **critical and major risks**, and present those findings first. Investigate high-impact failure paths before polishing lower-impact observations. Do not manufacture severe findings or inflate severity to meet this emphasis: rank by demonstrated consequence, credible trigger, affected scope and recoverability, with likelihood and assumptions stated.

| Severity | Meaning for this review |
| --- | --- |
| **Critical / P0** | An exploitable or realistically triggered failure with catastrophic impact, such as broad tenant-data exposure, widespread irreversible corruption, or uncontrolled value creation. State the conditions that justify this severity. |
| **Major / P1** | A substantial correctness, security, reliability or architectural defect: broken core flow, unauthorized action, incorrect payment/coverage, failed recovery, or a demonstrated structural barrier to supported evolution. It merits priority remediation even if some users or uncommon failure paths are affected. |
| Moderate / P2 | A concrete but more limited defect or meaningful maintainability/extensibility weakness with bounded impact. Include it without displacing investigation of P0/P1 risks. |
| Minor / P3 | A small actionable improvement supported by source evidence. Optional; keep it brief and separate from the principal findings. Pure style preferences remain excluded. |

Apply this emphasis throughout R1–R10, including these non-exhaustive risk areas:

- **Behavior and financial correctness:** broken business flows, incorrect charges or coverage, lost or duplicated grants/settlements, invalid state transitions and mismatched authority between stores.
- **Security and privacy:** tenant isolation, authentication/authorization bypass, credential exposure, replay, forged evidence, privileged action binding and unintended access to clinical or commercial data.
- **Concurrency and recovery:** races, broken idempotency, partial writes, stale messages, retry exhaustion, unrecoverable intermediate states and rebuilds that lose facts or recreate value.
- **Data integrity and auditability:** missing constraints, unsafe migration/override order, loss or mutation of authoritative records, incomplete lineage and inability to establish what happened.
- **Clinical continuity and operational reliability:** AI billing failures that block clinical work, silent job failures, ineffective alerts and misleading status that causes incorrect operator or administrator actions.
- **Compatibility and safe evolution:** producer/consumer drift, unsafe version transitions, incompatible schema or deployment changes and inconsistent handling of new or unknown values.
- **Extensibility and architectural boundaries:** hardcoded provider/plan assumptions outside their intended boundary, duplicated business rules that must change together, or coupling that makes a supported extension unsafe or forces unrelated rewrites. Demonstrate the affected extension and concrete blocked change, such as adding a provider through the existing port or evolving a versioned message. Do not recommend speculative abstraction or enterprise-scale infrastructure contrary to the constitution.
- **Resource and cost bounds:** unbounded scans, retries, fan-out or retained state that can cause material latency, service exhaustion or spend under credible clinic-scale load or hostile input. Ground the impact in the actual source path rather than hypothetical scale.

### Required fix instructions for every finding

The GPT-6.1 Sol reviewer must resolve the important design choices and give a future lower-cost implementation agent a bounded recipe. A finding is not implementation-ready if its remedy only says “fix validation,” “refactor,” “handle the race,” or “investigate.” Do not apply the fix during review.

Attach a **Fix steps** block to every finding, including optional lower-severity findings. Aim for 3–7 short numbered steps, fewer for a simple change, containing:

1. **Exact edit targets:** source paths and function/method/SQL object names, the specific faulty behavior, and the replacement behavior. Give the required predicate, field mapping, state transition or short pseudocode when prose would leave a decision to the implementer.
2. **Implementation order and consistency rules:** specify transaction/lease/idempotency boundaries, migration ordering or compatibility handling where applicable. Name all affected callers, producers, consumers and configuration copies that must change together; identify the existing helper or contract to reuse.
3. **Completion checks:** state the source-visible postconditions and the original failure scenario's expected outcome, plus a relevant boundary/retry/role case where needed. These are future implementation acceptance criteria; do not inspect or run tests as part of this review. Cite an established validation command only if verified from allowed reference material; do not invent one.

Choose one recommended remedy and explain any material tradeoff briefly. Keep the scope small and list prerequisites or dependencies on other finding IDs so the future agent can implement in order. For a cross-phase finding, maintain one canonical fix recipe and cross-reference it elsewhere. Size the report around the evidence and instructions rather than omitting necessary steps to meet the word target.

If a safe remedy depends on an unresolved architecture/contract decision or missing external fact, mark the finding **not implementation-ready**, state the exact decision needed, and assign it to the frontier reviewer or decision owner. Supply the known steps and explicit stop point; do not make a lower-cost agent infer the decision or present a guessed remedy as certain. Track this limitation in the final report until resolved.

### Required phase report

Save future reports as `docs/review/abo-integrated/R<N>-<slug>.md` with:

- Exact target SHA, reviewer model and explicitly configured high/medium effort for each reviewer/synthesis context, scope/regions actually read, supporting source read and unresolved coverage.
- The important invariants and complete cross-component traces established from source.
- Actionable findings, critical/P0 and major/P1 first, followed by moderate/P2 and optional minor/P3 observations; exclude cosmetic preferences and speculative concerns. Each finding includes the violated requirement/invariant, realistic trigger, concrete consequence, severity rationale, verified source path/line references at T, and the causal path across components. Label confidence/uncertainty and distinguish a source defect from a design conflict or an external operational assumption. Do not invent a runtime reproduction or test result for static reasoning.
- A brief, ordered **Fix steps** block for every finding, following the requirements above: exact edit targets, chosen replacement behavior, sequencing/dependencies and completion checks. State whether the recipe is implementation-ready and name any unresolved decision explicitly.
- Escalation IDs checked, affected consumers and any unresolved propagation conflict.
- Open seam questions with named future owner and a precise checkpoint if incomplete. A question without established evidence remains a question; an established finding requires the fix instructions above, without applying a patch.
- Explicit phase result: `complete`, `complete with findings`, or `incomplete`; “no findings” is not “no defects” and does not waive unread regions.
- Update the corresponding row in this plan's §8 status table to match the saved report, including its link, completion date and any continuation note.

Keep each report compact enough for R10: target about 1,000–1,500 words plus findings and a linked coverage manifest. If a finding spans phases, one finding ID owns it and other reports cross-reference it. Do not raise missing tests or viewer behavior as findings.

### Reusable future reviewer prompt

```text
Review phase R<N> of docs/review/abo-integrated-source-review-plan.md.
Model: GPT-6.1 Sol. This is static source-code review only.
Reasoning effort: explicitly set high or medium; never light/low or an unpinned
default. Apply this to every delegated reviewer/continuation/synthesis context
and record the actual model/effort settings in the report and coverage record.
Target: <pinned T>; baseline: <pinned B>; historical provenance: <pinned H>.
Read repository instructions, the R0 packet, this phase's architecture sections,
its escalation entries and its owned source regions. Use final source at T.
Follow each flow across its real callers, stores and receivers; consult unchanged
supporting source where necessary. Do not stop at the delivery-unit boundary.
Do not review tests, testkit, fixtures, harnesses, campaign tooling or the viewer.
Do not run tests/builds/lint, change source, apply fixes, deploy, or operate services.
Prioritize critical/P0 and major/P1 risks: correctness, security, financial/data
integrity, concurrency/recovery, continuity, compatibility, extensibility and
resource bounds. Other actionable findings are welcome after these priorities.
Use section 6's severity rules and report format; do not inflate severity.
For EVERY finding, write brief ordered Fix steps naming exact files/symbols,
the chosen replacement behavior, sequencing/dependencies and completion checks.
Resolve remediation design choices here so a lower-cost agent can follow the
recipe. If a decision cannot be resolved, mark the finding not implementation-ready
and name the decision owner and stop point; do not leave implicit design work.
If evidence or context is insufficient, save exact unread regions and questions;
never infer completion from passing campaigns or earlier agent reviews.
Write the phase report and coverage/checkpoint updates under
docs/review/abo-integrated/. Also update this plan's section 8 status row when
starting, checkpointing and completing the phase; link the saved report and date.
Do not change other plan content except the overall execution status as instructed
in section 8. Forward cross-phase questions by owner in the report.
```

### Final completion gate

R10 may call the **review complete** only when all of the following hold:

1. Every in-scope file/changed region has completed R1–R9 primary ownership, including deletions, SQL overrides, shared helpers and later source fixes. Every excluded candidate has a recorded reason.
2. All 75 currently indexed escalation entries have a disposition; every source/contract amendment has been checked at its affected producers and consumers. Reconcile counts if the target changes.
3. Every required R10 narrative has source-backed reasoning or an explicitly recorded unresolved limit; no unowned seam or hidden continuation remains.
4. Findings have been deduplicated and ranked with critical/major risks first. Every finding has brief, concrete fix steps and completion checks; unresolved remediation decisions have an explicit owner and are marked not implementation-ready. Uncertainties/external operational limits are visible. Serious findings may remain open: completing a review does not mean the code is approved or launch-ready.
5. The final report states the exact target, source-only scope and exclusions, and makes no claim to have reviewed tests/viewer or verified live staging/production.

## 7. Escalation routing register

This is a planning-level file register, not a resolution audit. R0 expands its numbered entries into the authoritative routing index. The phase list identifies initial consumers; add another phase if the amended behavior crosses its boundary.

| Spec / escalation record | Entries | Initial review phases |
| --- | ---: | --- |
| [066](../../specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/escalations.md) | 10 | R1, R2, R5, R8 |
| [067](../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md) | 12 | R1, R2, R4, R7, R8, R9 |
| [068](../../specs/068-abo-p3-4-admission-settlement-against-terms/escalations.md) | 1 | R4, R5 |
| [069](../../specs/069-abo-p3-5-term-boundaries-grace-renewal/escalations.md) | 1 | R4 (reference-only test-clock effect) |
| [070](../../specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/escalations.md) | 1 | R4, R6, R8 |
| [071](../../specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/escalations.md) | 3 | R2, R6, R9 |
| [072](../../specs/072-abo-p3-8-transfer-deletion-with-coverage-left/escalations.md) | 1 | R6, R7 |
| [073](../../specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/escalations.md) | 2 | R5, R7 |
| [074](../../specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/escalations.md) | 2 | R8 (reference-only test-scope effects) |
| [075](../../specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/escalations.md) | 2 | R9; workflow-only entry excluded |
| [076](../../specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/escalations.md) | 2 | R1, R2, R3, R9 |
| [077](../../specs/077-abo-p4-2-checkout-paymob-intention/escalations.md) | 2 | R2, R3; external provider assumption recorded |
| [078](../../specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/escalations.md) | 1 | R3, R9 |
| [079](../../specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/escalations.md) | 6 | R2, R4, R7, R9 |
| [080](../../specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/escalations.md) | 3 | R3, R6 |
| [081](../../specs/081-abo-p4-6-operator-console-access-perimeter-lookup/escalations.md) | 3 | R2, R8, R9 |
| [082](../../specs/082-abo-p4-7-console-passkey-ceremony-abo-side-hp/escalations.md) | 1 | R2, R6, R8 |
| [083](../../specs/083-abo-p4-8-console-relays-complimentary-grants-adjustments/escalations.md) | 1 | R4, R6 |
| [085](../../specs/085-abo-p4-10-reconciliation-payout-import-findings/escalations.md) | 1 | R9 |
| [086](../../specs/086-abo-p4-11-daily-digest-platform-watch-housekeeping/escalations.md) | 2 | R9 |
| [087](../../specs/087-abo-p5-1-issuer-key-custody-token-issuance/escalations.md) | 2 | R1, R8; test-harness-only effect excluded |
| [088](../../specs/088-abo-p5-2-coverage-feed-puller-status-projection/escalations.md) | 7 | R2, R7, R9; delivery split retained as provenance |
| [088b](../../specs/088b-abo-p5-2b-read-time-status-notices/escalations.md) | 1 | R7 |
| [089](../../specs/089-abo-p6-1-desktop-contract-versions-token-minting/escalations.md) | 1 | R7 |
| [091](../../specs/091-abo-p6-3-administrator-billing-offers-contact-checkout/escalations.md) | 1 | R3, R7 |
| [092](../../specs/092-abo-p6-4-administrator-subscription-payment-history-notices/escalations.md) | 1 | R7 (reference-only harness effects) |
| [093](../../specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/escalations.md) | 1 | R8, R9; viewer/test scan effects excluded |
| [094](../../specs/094-abo-p7-2-cross-system-security-isolation-suite/escalations.md) | 1 | R2 (reference-only story grouping) |
| [095](../../specs/095-abo-p7-3-contract-version-matrix/escalations.md) | 2 | R2, R5, R7 |
| [097](../../specs/097-abo-p8-2-staging-acceptance-a1-a36/escalations.md) | 1 | R9 (reference-only workflow effect) |

When a register row says “reference-only,” that disposition applies to the named effect, not automatically to every fact mentioned in its text. Confirm the entry's actual amendment during R0 before excluding its effects. The absence of escalation records for specs 061–065, 084, 090, 096 and 098 does not remove their production source from phase ownership.

## 8. Phase status tracker

This table is the shared execution record. All rows below refer to target `T` pinned in §1.1. No review phase has started when this tracker is created.

| Phase | Scope | Status | Report / packet index | Completed on | Notes / continuation |
| --- | --- | --- | --- | --- | --- |
| R0 | Preparation and review packets | complete | [Packet index](abo-integrated/packet-index.md) | 2026-10-16 | Exit gate passed: candidates/regions, 75 escalations, phase packets and dependency order. |
| R1 | Tenant identity and clinic authorization | complete with findings | [Report](abo-integrated/R1-tenant-identity-authorization.md) · [Coverage](abo-integrated/R1-coverage.md) | 2026-10-16 | 0 P0, 5 P1, 4 P2; primary/inherited closure complete. SQL02 per-org data repair requires maintainer/clinic administrator mapping; source unchanged. |
| R2 | Contracts, perimeter and human approval | complete with findings | [Report](abo-integrated/R2-contracts-perimeter-human-approval.md) · [Coverage](abo-integrated/R2-coverage.md) | 2026-10-16 | 0 P0, 4 P1, 3 P2; primary/caller coverage closed. P4 browser bootstrap contract needs maintainer/architecture decision before routing changes; source unchanged. |
| R3 | Checkout through confirmed payment | complete with findings | [Report](abo-integrated/R3-checkout-confirmed-payment.md) · [Coverage](abo-integrated/R3-coverage.md) | 2026-10-16 | 0 P0, 7 P1, 6 P2; primary coverage closed. C2/C4 provider recovery/discovery contracts need maintainer/provider owner decisions; source unchanged. |
| R4 | Grants, coverage and term lifecycle | complete with findings | [Report](abo-integrated/R4-grants-coverage-term-lifecycle.md) · [Coverage](abo-integrated/R4-coverage.md) | 2026-10-17 | 0 P0, 8 P1, 3 P2; all 148 primary regions closed by explicitly GPT-6.1 Sol/high reviewers and synthesis. Historical ambiguous-data adjudication remains a fail-closed limit; source unchanged. |
| R5 | Admission, accounting and fallback | complete with findings | [Report](abo-integrated/R5-admission-accounting-fallback.md) · [Coverage](abo-integrated/R5-coverage.md) | 2026-10-17 | 0 P0, 6 P1, 5 P2; all 555 regions/10,234 final+303 deleted lines closed by explicit high lead and two medium reviewers. Outage replay policy and historical attribution decisions remain explicit; source unchanged. |
| R6 | Reversals, transfer and deletion | complete with findings | [Report](abo-integrated/R6-reversals-transfer-deletion.md) · [Coverage](abo-integrated/R6-coverage.md) · [Checkpoint](abo-integrated/R6-checkpoint.md) | 2026-10-17 | 0 P0, 10 P1, 3 P2; all 230 regions/6,044 lines closed by explicit Sol/high lead and three Sol/medium reviewers. Provider cumulative and historical-data adjudication limits explicit; source unchanged. |
| R7 | Feed, projection and desktop state | complete with findings | [Report](abo-integrated/R7-feed-projection-desktop-state.md) · [Coverage](abo-integrated/R7-coverage.md) · [Checkpoint](abo-integrated/R7-checkpoint.md) | 2026-10-17 | 0 P0, 1 P1, 10 P2, 1 optional P3; all 204 tuples/7,969 lines and 27 escalations closed by explicit Sol/high lead + three Sol/medium slices. Pinned T read via git source; later workspace HEAD a2545299 source excluded; application unchanged. |
| R8 | Operator control and configuration | complete with findings | [Report](abo-integrated/R8-operator-control-configuration.md) · [Coverage](abo-integrated/R8-coverage.md) · [Checkpoint](abo-integrated/R8-checkpoint.md) | 2026-10-17 | 0 P0, 3 P1, 11 P2; all 239 tuples/4,469 final+1,951 deleted lines and 24 escalations closed by Sol/high lead + three Sol/medium slices. Pinned T/B source; later workspace HEAD excluded; application unchanged. Historical evidence stops explicit. |
| R9 | Durability, recovery and operations | complete with findings | [Report](abo-integrated/R9-durability-recovery-operations.md) · [Coverage](abo-integrated/R9-coverage.md) · [Checkpoint](abo-integrated/R9-checkpoint.md) | 2026-10-18 | 0 P0, 13 P1, 7 P2, 1 optional P3; all457 tuples accounted:7,529 actual primary lines+252 excluded embedded-fixture lines;13,800 supporting lines separated as actual/parsed metadata,135 operational expansion lines;37 escalations closed by Sol/high lead+three Sol/medium slices. Historical/external adapter decisions explicit; pinned T source, newer HEAD unchanged. |
| R10 | Integrated review and final synthesis | complete with findings | [Final report](abo-integrated/R10-integrated-final-review.md) · [Coverage](abo-integrated/R10-coverage.md) · [Global closure](abo-integrated/R10-global-closure.json) | 2026-10-18 | All eight narratives source-backed; 4,805 unique selected T lines; 2,540 regions and all 75 escalation routes reconciled with zero gaps. No new findings; 111 canonical inherited IDs (0 P0/57 P1/52 P2/2 optional P3). Explicit high lead + two medium reviewers; source unchanged. Review complete, no launch approval. |

**Agent update rules:**

1. On starting a phase, set its status to `in progress`. Change the document's overall status at the top to `review in progress` when execution first starts.
2. Before ending the phase's work, save the report or checkpoint, link it in the row, and set status to `complete`, `complete with findings`, or `incomplete`, matching the report. R0 links its packet index and uses `complete` only after its preparation exit gate passes. Leave unstarted rows as `not started`.
3. Use `complete` only when all owned review work is finished with no findings; use `complete with findings` when all owned review work is finished and findings remain. Findings do not have to be fixed to complete a review phase. Missing source coverage or unfinished investigation requires `incomplete`, with the exact remaining work or a checkpoint link in the notes.
4. Record `Completed on` as `YYYY-MM-DD` in Africa/Cairo when a phase reaches either completion status. Leave it as `—` for an unfinished phase. Notes may summarize critical/major findings, unresolved remediation decisions or the next owner; keep detailed evidence in the report.
5. Update only your phase's row and the overall execution status. If a completed phase is reopened, record why in its notes, set `in progress` and clear its completion date until the additional review is finished. Preserve prior report evidence. If target T changes, preserve this tracker and start a separately identified review record for the new target.
6. R10 changes the overall document status to `review complete` only after R0–R10 all have a completion status and §6's final completion gate passes. This records completion of the review, not approval of the code, remediation of findings or launch readiness.
