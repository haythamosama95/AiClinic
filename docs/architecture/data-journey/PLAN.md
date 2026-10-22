# Data Journey Documentation — Build Plan

**Audience:** the agents (and humans) who will write, verify and maintain the new data-journey docs.
**Status:** plan approved by the owner; no chapter has been written yet.
**Location of the finished docs:** `docs/architecture/data-journey/` (this folder, system-wide).

---

## 1. Purpose

The old data-journey docs (`docs/architecture/ai-platform/data-journey/` and the stub `08-ai-platform-data-journey.md`) described the AI Platform (AP) before the AI Billing Orchestrator (ABO) existed. They are obsolete. They are already reduced to "Superseded" stubs; their last full content is in git at commit `3ca0b435b^`. They are deleted as part of this work (see §11). Use them only to see the old style, never as a source of facts.

The new docs must let the owner read them all, in order, and come away understanding **every detail** of everything the ABO and the AP do, and how they interact with Flutter (the clinic desktop app) and Supabase. Length and number of files do not matter. Completeness and clarity do.

The docs are a **story**: one continuous journey told in the chronological order a clinic user would experience it, from the very first request to the last. They are **not** grouped by component.

---

## 2. Source of truth

1. **The code is the only source of truth.** Read the actual implementation: `abo/`, `ai-platform/`, `backend/supabase/` (migrations, RPCs, functions) and `frontend/lib/` (especially `core/ai`, `features/ai`, billing).
2. The architecture docs (`docs/architecture/ai-billing-orchestration/`, `docs/architecture/ai-platform/`) are **not** a source. Do not copy from them. Do not write "divergence from the design doc" notes. If a doc disagrees with the code, the code wins silently. A design doc may be read only to understand the intent behind something the code already shows.
3. Never guess. If the code does not make something clear, say what is certain, and flag the doubt in your report to the coordinator (not in the published text).

---

## 3. Hard format rules

- **No code and no line numbers.** No code snippets, no file paths, no `file:line` citations, no source-file index. Describe everything in words, tables and diagrams.
- Names that the reader needs **are** allowed and required: routes (e.g. `GET /v1/offers`), header names, JSON field names, claim names, table and column names, state and status values, error codes, HTTP statuses, cron schedules, binding and secret names, RPC names.
- **No tests.** Do not reference tests, test files, probes or a test map.
- **Plain language, metaphors everywhere.** See §5.
- **Term-first rule.** See §6.
- Diagrams: use Mermaid (sequence diagrams for message flows, state diagrams for lifecycles, flowcharts for decision paths) or simple ASCII. Keep each readable on its own.
- Tables for fields, states, and error codes.

---

## 4. The story, in order

The order is the clinic user's point of view in time. A clinic must be entitled before it can use AI, and it gets entitled by discovering and buying a plan, so purchase comes before use.

Numbering below is the intended reading order. Large chapters (for example the guard) may split into several files. Use the numbering as the file prefix (`NN-short-name.md`). Tracing may reveal chapters that are missing; add them in the right place and renumber, and report it.

### Prologue — What already exists
The stage is set before any clinic shows up: both workers are deployed, plans and capabilities are published, routing is configured, keys are pinned. Told briefly, with forward links to the chapters (Act 6) that explain each piece in full.

### Act 1 — The clinic arrives
1. The cast: desktop (Flutter), Supabase, ABO, AP, Paymob. Roles and who trusts whom.
2. The clinic's identity: organization, branch, actor, role in Supabase; what the billing and AI tokens will later claim.
3. The clinic keypair is enrolled (Supabase RPC) and the installation is registered on the AP.
4. The administrator opens the AI page for the first time: the availability flag, the status snapshot, the "not entitled yet" degraded view. *(Settle during tracing exactly where the availability flag is set and by whom, and place it correctly.)*

### Act 2 — Discovering and buying a plan
5. The desktop asks Supabase for a billing token (claims, rate limit, error versions).
6. The version header and the contract-version handshake.
7. `GET /v1/offers` — the desktop asks which plans exist. **This is the pilot chapter (see §9).**
8. The administrator reads the plans and sets the billing contact (`/v1/billing-contact`).
9. `POST /v1/checkouts` — idempotency, the Paymob intention attempt, the checkout record.
10. The user pays at Paymob (outside our control; document what we observe).
11. The desktop polls the checkout (`GET /v1/checkouts`); the pending state.
12. Paymob's webhook (`/notify/paymob`): HMAC check, intake, the ledger fact.
13. If the webhook is lost: sweeps and provider inquiry.
14. The work row, the runner, leases, the inquiry budget.
15. The ABO signs a grant to the AP: operator assertion, envelope validation, receipt.
16. The AP applies the grant: entitlement, term, coverage calendar, Durable Object quota state.
17. The coverage feed (AP to ABO) and fact export to the R2 ledger.
18. The desktop sees the active subscription (`GET /v1/subscription`, `GET /v1/payments`) and the commercial notices.

### Act 3 — Using the AI
19. The desktop mints an AI token (AAT) from Supabase.
20. Discovery: `GET /v1/capabilities`, the manifest registry, the desktop's refresh.
21. The clinician asks for something; Flutter assembles context (resolver, registration, self-heal on `context_required`).
22. `POST /v1/requests` ingress: size, JSON, adapter gates.
23. The guard, one chapter per stage: identity, entitlement, rate limit, capability, context validation, cost pre-flight, admission, journal, prompt compose.
24. Accept, route, invoke: provider choice, retry, fallback.
25. The stream: the SSE event grammar, Flutter's parser, provisional prose.
26. Settlement: usage accounting, Durable Object ledger, journal close, the quota gauge.
27. Lookup (`GET /v1/requests/{ref}`) and the support surface.
28. The clinician accepts or rejects the output (acceptance recording in Supabase).
29. Degraded and denied states: quota exhausted, coverage lapsed, kill switch, rate limit, and what the desktop shows for each.

### Act 4 — Time passes
30. Term boundaries, grace, queued and held terms, Durable Object alarms.
31. Renewal and a second purchase.
32. The AP's background jobs: fallback-admission drain, alert retry, retention, rollup.
33. The ABO's scheduled jobs and the scheduled-job state machine.
34. Reconciliation, digest, watch, alerts.

### Act 5 — When things change or go wrong
35. Refund and reversal.
36. Chargeback.
37. Key rotation: issuer keys, operator credentials, clinic keypair.
38. Installation transfer.
39. Erasure and the erasure fence.
40. Disaster recovery: Time Travel, ledger rebuild, gap fill.

### Act 6 — The operator's side
Console gate first (Cloudflare Access plus the WebAuthn ceremony, shell, browser flow). Then **one full chapter per operator action**, including at least: publish / retire / reinstate offers, plan versions, ceiling policy, complimentary grant, suspend, resume, delete installation, begin transfer, release, chargeback, void grant, release-held, recover-stranded, retry or cancel a checkout, set transaction id, payout import, finding resolution, operator-credential register and revoke, erase contact, and the AP control plane (capability lifecycle, cohort, kill switch, routing policy, token contract, installation lifecycle). The inventory (§8) is the authority on what exists; this list is a floor, not a ceiling.

### Reference shelf (lookups, not read-through)
- Every D1 table and column, for both workers, with which chapter writes it and which reads it.
- Every R2 object.
- Every Durable Object field.
- Every Supabase RPC and table involved.
- Every error code: where it arises, HTTP status, whether retry is safe, what the desktop shows.
- The cross-system wire table: every message, sender, receiver, version, signature.
- Environment variables, secrets and bindings.
- **Master glossary** (see §6) and the **Findings register** (see §7).

Expected size: roughly 60–70 chapter files plus about 7 reference files, numbered in reading order, with a shared table of contents (`00-index.md`) and previous/next links on every chapter.

---

## 5. Chapter template

Every narrative chapter uses these sections in this order. Omit a section only if it genuinely does not apply, and then say so in one line.

1. **The story in one minute** — plain-language summary plus the chapter's metaphor. Introduce a metaphor once; later chapters link back instead of redefining it. Metaphors should stay consistent across the docs (e.g. the post office, the filing cabinet, the bouncer, the vault). Pick them in the first chapters and record them in the glossary.
2. **Words you'll meet here** — new terms with a one-line definition; old terms as links to the chapter where they were first explained (cross-doc links allowed).
3. **The trigger** — what makes this happen (user action, cron, webhook, operator) and the state of the world before it.
4. **The request on the wire** — method, URL, headers, body, token or signature. A table of every field: where it came from, type, meaning, what validates it.
5. **The receiver's journey** — step by step in order: what is read and written in each store (D1 table and columns, R2 object, Durable Object state, Supabase table or RPC, Flutter provider or state), and the invariant each step protects.
6. **The response** — every success shape and every failure shape, with exact code, HTTP status and retry-safe flag.
7. **What the caller does next** — the Flutter reaction, retry and backoff, what the user sees.
8. **State after** — before/after table for every store touched.
9. **Crash, replay and race paths** — what happens if it dies halfway, is repeated, or races another request; what the recovery does.
10. **Findings** — only if a major or critical issue was found here (see §7).
11. **What happens next** — one paragraph and a link to the next chapter. The end state here must match the start state of the next chapter.

---

## 6. The term-first rule

A reader must never meet a term that has not been explained.

- Every chapter has the "Words you'll meet here" box (§5.2).
- One master glossary (reference shelf) lists every term with a one-line definition and a link to its **home chapter** (where it is first explained).
- A term may be used in a chapter only if (a) the chapter's own box defines it, (b) it is linked to its home chapter, or (c) its home chapter comes earlier in the reading order.
- Forward references are allowed only in the form "explained in chapter N; you don't need it yet".
- Cross-doc links are fine and encouraged.
- A **term lint script** (build it during the pilot, under a `tools/` or `scripts/` location the coordinator picks) scans the chapters in reading order against the glossary and reports any term used before its home chapter without a link. The lint must pass before a wave is accepted.
- Write the glossary incrementally: every wave adds the terms it introduces. Waves receive the glossary built so far.

---

## 7. Findings (major and critical only)

While tracing, you will notice things that are wrong. Record only what clears this bar:

- **Critical:** can lose or double-charge money, grant or deny entitlement wrongly, leak or corrupt data, break authentication or authorization, or leave the system stuck or unrecoverable.
- **Major:** a real defect or a significant weakness that will cause incorrect behavior, a security gap, a stuck or silently failing path, or something that clearly needs a substantial improvement.

Not included: style, naming, minor inefficiencies, speculative concerns, hypothetical misuse with no concrete path.

Rules:
- A finding is a short entry inside the chapter's **Findings** section: severity, a plain-language description of what goes wrong and under what circumstances, and why it matters.
- Every finding must be confirmed against the code by an agent other than the one who raised it before it is published. Unconfirmed concerns are reported to the coordinator, not published.
- No code, no lines. Describe the situation in words precise enough that a developer can find it.
- The **Findings register** (reference shelf) collects all published findings, sorted by severity, with a link to the chapter.
- Do not fix anything. These docs only document.

---

## 8. Inventory (build before writing)

Before any chapter is written, produce a machine-generated or carefully compiled inventory, kept in this folder (e.g. `INVENTORY.md`, removed or kept at the coordinator's discretion at the end), listing:

- every HTTP route on the ABO (billing host and ops host), the AP, and any Supabase edge function;
- every Supabase RPC, table, and trigger involved in AI or billing;
- every D1 table and column (ABO and AP), R2 prefix and object type, Durable Object state field;
- every cron schedule and scheduled job;
- every Flutter call site that talks to the ABO, the AP, or the related Supabase RPCs;
- every error code and notice code;
- every environment variable, secret and binding.

Each inventory item is assigned to the chapter(s) that must cover it. At the end, a **coverage check** proves every item is claimed by a chapter and that the chapter actually covers it. Nothing may be silently missed.

---

## 9. Method

1. **Inventory** (§8).
2. **Pilot.** Write chapter 7 (`GET /v1/offers`) together with the chapter template, the metaphor set for the first chapters, the glossary seed, and the term lint. The owner approves tone, depth and style **before** anything else is written. Do not fan out until approved.
3. **Trace, then write.** For each chapter, an agent first produces a call-by-call trace from the real code (every hop, every store touch, every branch, every error code), then writes the chapter from that trace in plain language.
4. **Waves by act.** Write act by act so the glossary and metaphors stay consistent. Each wave gets the approved template, the glossary so far, the chapter list, and the chapters already written (for continuity). Chapters within a wave can be written in parallel, but chapters that hand state to one another must agree on the state between them.
5. **Continuity pass.** After each wave, check that each chapter's end state matches the next chapter's start state, that links are correct, and that the term lint passes.
6. **Independent verification.** Fresh agents (not the authors) re-check each chapter's factual claims against the code: order of steps, field meanings and types, error codes and statuses, which store changes, cron schedules. They also confirm every published finding. Authors fix what verification rejects.
7. **Coverage check** against the inventory (§8).
8. **Cleanup** (§11).

---

## 10. Quality bar

A chapter is done when:
- a reader with no prior knowledge can follow it using only earlier chapters;
- every field, state and error that appears on the wire or in a store is explained;
- every success and failure path of the step is covered;
- no term is used before it is explained or linked;
- no code, file paths, line numbers or tests appear;
- every claim has been verified against the code;
- the term lint and continuity checks pass.

---

## 11. Cleanup when the new docs are complete

- Delete `docs/architecture/ai-platform/data-journey/` and the stub `docs/architecture/ai-platform/08-ai-platform-data-journey.md`.
- Check the other stubs in `docs/architecture/ai-platform/` (06 behavioral journey, 07 storage, 09 request/response flow) and the viewer catalog or any other place that links to the old paths; update or remove links. Ask the owner before deleting anything outside the data-journey stubs.
- Add the new docs to `docs/architecture/00-index.md`.
- Update `AGENTS.md` only if the owner asks.

---

## 12. Decisions already made by the owner

- New system-wide location: `docs/architecture/data-journey/`.
- Plain language, simple and thorough, with metaphors throughout.
- Every operator action gets its own chapter.
- No tests, no code, no line numbers.
- Chronological order from the clinic user's point of view; purchase before use.
- Code beats the architecture docs.
- Major and critical findings only.
- Terms are explained before use, or linked (including across docs).

---

## 13. Models and effort

All work uses **Sonnet 5.5**. Only the effort level changes by role. These are starting values; adjust after the pilot based on observed cost and quality.

| Role | Effort | Notes |
|---|---|---|
| Inventory agents | low | Listing and grepping into a fixed format. The coverage check catches gaps. |
| Pilot (tracer, writer, verifier) | high | Sets the voice for everything. The owner reviews it. |
| Tracers | high | A wrong or shallow trace propagates into the writer and the verifier. Never go below high. |
| Writers, normal chapters | medium | They write from a finished trace, the template and the glossary. |
| Writers, money-critical groups | high | Guard, grant, reversal, chargeback, transfer, erasure. |
| Writers, operator-action chapters | medium | Same pattern once the console-gate chapter exists. Use high for actions that move money or entitlement (void, release, transfer, chargeback, complimentary grant). |
| Verifiers | medium; high for money-critical groups | Always a different agent from the writer. |
| Second verifier | high | Money-critical groups only; works independently of the first. |
| Findings confirmation | high | A wrong "critical" costs trust. |
| Term lint, link check, coverage check | none | Scripts, not models. |

Rules: the author never verifies their own chapter. Keep each agent's scope to one chapter group so contexts stay small.

---

## 14. Agent flow

About 25 chapter groups (2–5 related chapters each, handled by the same tracer, writer and verifier). Rough split: Prologue 1, Act 1 two, Act 2 five, Act 3 six, Act 4 two, Act 5 three, Act 6 six. At most about 5 agents run concurrently.

**Phase 0 — Inventory and tooling (about 5 agents, low).** Four inventory agents in parallel (ABO, AP, Supabase, Flutter); one tooling agent builds the term-lint and coverage-check scripts. Output: `INVENTORY.md`, with each item assigned to a chapter group.

**Phase 1 — Pilot (3 agents, high, sequential).** Tracer, then writer, then independent verifier for chapter 7 (`GET /v1/offers`). The writer also produces the template, the metaphor set and the glossary seed. **Gate: the owner approves tone and depth. Nothing else starts before approval.**

**Phase 2 — Per-act pipeline (act by act).** For every group in the act:
1. Tracer writes the call-by-call trace to `traces/`.
2. Writer writes the chapters from the trace, the template and the glossary so far.
3. Verifier fact-checks against the code.
4. Second verifier (money-critical groups only).
5. Fix pass: the writer revises what the verifiers rejected.
6. Act check: continuity, links, term lint, and merge of the new glossary terms.

Groups in an act run in parallel unless one hands state to another. Tracing for the next act may start while the current act is in verification (tracing does not depend on written chapters). Acts are otherwise sequential so the glossary and metaphors stay consistent.

**Phase 3 — Findings confirmation (about 4 agents, high).** Each re-confirms candidate findings against the code without seeing the original reasoning; one builds the Findings register.

**Phase 4 — Reference shelf (about 10 agents, medium).** Seven writers (one per reference file), mostly derived from the inventory and the finished chapters; three verifiers.

**Phase 5 — Final checks and cleanup (2 agents).** Coverage check against the inventory; cleanup per §11.

Estimated total: about 115 agent runs (25 tracers, 25 writers, about 35 verifiers, the rest tooling, checks, findings and reference).

---

## 15. Resumability and incremental delivery

The work spans many sessions. Every stopping point must leave finished, readable docs behind, and any new session must be able to continue without repeating work.

- **`STATUS.md`** in this folder is the progress tracker. It lists every chapter group and its state: `not started`, `traced`, `written`, `verified`, `needs fixes`, `done`. Every agent updates it when it finishes. A new session reads it first and resumes from there.
- **`traces/`** holds the call-by-call traces so the writer and verifier do not re-derive them. It is a working folder and is removed at cleanup.
- **The glossary, the metaphor set and the chapter template live in files**, so a new session picks up the same voice by reading them.
- **A verified group is a finished piece of the story** and is kept even if the session ends mid-act. Unfinished groups are redone from their trace.
- **Suggested session split:** (1) inventory, tooling and pilot, then owner review; (2–8) one act per session, splitting the large ones (Act 2, Act 3, Act 6) in two; then a session for findings confirmation; then a session for the reference shelf and cleanup.
- **The old docs stay until the very end.** While this folder is incomplete, `00-index.md` carries a short note saying it is a work in progress.

---

## 16. Runbook — how to execute a phase

When the owner says "execute phase N", the coordinating session does exactly what this section says for that phase and nothing from later phases. **Phases are numbered from 0** (Phase 0 = inventory, Phase 1 = pilot).

### 16.1 Rules for every phase

1. **Read first, in this order:** this whole `PLAN.md`, then `STATUS.md` (if it exists), then the files the phase block lists under "Read".
2. **Check entry conditions.** If one is not met, stop and tell the owner what is missing. Do not improvise around it.
3. **The coordinator spawns agents; it does not write chapters itself.** The coordinator's job: spawn, give each agent its brief (§17), collect results, update `STATUS.md`, report.
4. **Agents are read-only on the code.** They write only inside `docs/architecture/data-journey/`. Nothing in `abo/`, `ai-platform/`, `backend/` or `frontend/` is ever modified.
5. **Never commit, push or delete outside this folder.** The owner commits.
6. **At most 5 agents run at once.**
7. **Finish whole groups.** Never stop in the middle of a group. If the session is running low, stop starting new groups and finish what is in flight.
8. **Update `STATUS.md` before ending**, and end with a short report: what was done, what failed or was rejected, any doubts needing the owner, and the exact next command ("execute phase N" or "continue phase 2, act X").
9. **Doubts and blockers** go to `traces/doubts.md` (what, where, why unsure). They never go into published chapters.
10. **Code beats docs.** Agents must not use the architecture docs as a source (§2).

### 16.2 Folder layout and file contracts

```
docs/architecture/data-journey/
  PLAN.md              this file
  STATUS.md            progress tracker (format in 16.3)
  INVENTORY.md         everything that exists, assigned to groups (16.4)
  TEMPLATE.md          the chapter template, filled out concretely (created in Phase 1)
  METAPHORS.md         the running metaphors and where each is introduced (Phase 1, grown later)
  GLOSSARY.md          master glossary (16.5)
  00-index.md          table of contents (built incrementally; carries the work-in-progress note)
  NN-short-name.md     narrative chapters, numbered in reading order
  reference/           reference shelf files (Phase 4)
  traces/              working folder: NN-group traces, doubts.md, findings-candidates.md; deleted at cleanup
  tools/               check scripts (Phase 0); deleted or kept at the owner's choice at cleanup
```

Chapter files start with a one-line title, a "Previous | Next" line, then the template sections (§5). Links between chapters use relative links.

### 16.3 `STATUS.md` format

A table, one row per group, plus a short "Next step" line at the top.

```
Next step: <exact command for the next session>

| Group | Chapters | Money-critical | Trace | Chapters written | Verified | 2nd verifier | Fixes | Done |
```

Cell values: `-`, `yes`, or `needs fixes`. A group is `Done` only when: trace exists, chapters written, verifier passed, second verifier passed (if money-critical), fixes applied, act check passed. Below the table keep a log: date, phase, what happened, one line each.

### 16.4 `INVENTORY.md` format

One section per category, each a table: `ID | Item | Kind | Source area | Assigned group | Notes`.
IDs are stable: `ABO-ROUTE-001`, `AP-D1-014`, `SB-RPC-003`, `FL-CALL-007`, `ERR-021`, `ENV-009`, and so on. Categories are those in §8. "Source area" is a folder or module name for the agent's convenience; it is **not** published. "Assigned group" is filled by the coordinator after merging (16.6, Phase 0 step 4).

### 16.5 `GLOSSARY.md` format

A table: `Term | Also written as | Home chapter | One-line definition`. Terms are added by each group's writer and merged by the act check. The lint script reads exactly this table.

### 16.6 Group table (provisional; Phase 0 may adjust it)

`G00` is the Prologue. "$" marks money-critical groups (two verifiers, high effort).

| Group | Chapters | Money-critical |
|---|---|---|
| G00 | Prologue | |
| G01 | 1–2 (cast; clinic identity) | |
| G02 | 3–4 (keypair and installation; first AI page and availability) | |
| G03 | 5–7 (billing token; version handshake; **offers — pilot is chapter 7**) | |
| G04 | 8–9 (billing contact; checkout creation) | $ |
| G05 | 10–13 (pay; polling; webhook; sweeps and inquiry) | $ |
| G06 | 14–16 (work runner; grant to AP; AP applies grant) | $ |
| G07 | 17–18 (coverage feed and ledger; subscription and payments views) | |
| G08 | 19–21 (AI token; discovery; context assembly) | |
| G09 | 22 plus guard stages for identity, entitlement, rate limit, capability | |
| G10 | guard stages for context, cost pre-flight, admission, journal, prompt compose | $ |
| G11 | 24–25 (route and invoke; stream and Flutter parser) | |
| G12 | 26–27 (settlement; lookup and support) | $ |
| G13 | 28–29 (acceptance; degraded and denied states) | |
| G14 | 30–31 (term boundaries; renewal) | |
| G15 | 32–34 (AP jobs; ABO scheduler; reconciliation, digest, watch, alerts) | |
| G16 | 35–36 (refund and reversal; chargeback) | $ |
| G17 | 37–38 (key rotation; installation transfer) | $ |
| G18 | 39–40 (erasure; disaster recovery) | $ |
| G19 | console gate; offer, plan-version, ceiling-policy actions | |
| G20 | complimentary grant, suspend, resume, delete installation, begin transfer | $ |
| G21 | release, chargeback, void grant, release-held, recover-stranded | $ |
| G22 | retry/cancel checkout, set transaction id, payout import, finding resolution, operator credentials, erase contact | |
| G23 | AP control plane: capability lifecycle, cohort, kill switch | |
| G24 | AP control plane: routing policy, token contract, installation lifecycle | |

Chapter numbers are provisional; final numbers are assigned in the order the story reads, and `00-index.md` is the authority.

### 16.7 Phase 0 — Inventory and tooling

**Entry:** `PLAN.md` exists. No other condition.
**Read:** §3, §4, §8, §16.2–16.6.
**Steps:**
1. Create `STATUS.md` (all groups `-`), `traces/` and `tools/`.
2. Spawn 4 inventory agents in parallel (effort low), each with brief 17.1: **ABO** (everything under `abo/`), **AP** (`ai-platform/`, including migrations, manifests, prompts, wrangler config), **Supabase** (`backend/supabase/` AI/billing/keystore/token migrations, RPCs, functions, tables, RLS), **Flutter** (`frontend/lib/core/ai`, `features/ai`, and anything that calls the ABO, the AP or the AI/billing RPCs). Each writes its findings to `traces/inventory-<area>.md` in the 16.4 table format with the Assigned group column empty.
3. Spawn 1 tooling agent (effort low; Python standard library only, run with `python3 -I`) to build in `tools/`:
   - `lint_terms.py` — reads `GLOSSARY.md` and the chapters in reading order (from `00-index.md`); reports every glossary term used in a chapter before its home chapter without a link to the home chapter and without being listed in that chapter's "Words you'll meet here" box.
   - `check_coverage.py` — reads `INVENTORY.md` and the chapters; reports each item whose name does not appear in any chapter of its assigned group.
   - `check_links.py` — reports broken relative links and missing Previous/Next links.
   - `check_banned.py` — reports code fences other than diagrams, file paths, `file:line` patterns, and any mention of tests.
   - A short `tools/README.md` with usage. Each script exits non-zero on any report.
4. Coordinator merges the four inventory files into `INVENTORY.md` and assigns each item to a group using §16.6. Items that fit no group are listed under "Unassigned"; the coordinator proposes a new group or chapter for them and tells the owner.
5. Create an empty `GLOSSARY.md` with the table header, and a `00-index.md` containing the work-in-progress note.
**Exit check:** `INVENTORY.md` has zero unassigned items (or the owner has approved the proposals); the four scripts run on the empty set without crashing.
**Update `STATUS.md`:** log "Phase 0 done". Next step: "execute phase 1".

### 16.8 Phase 1 — Pilot

**Entry:** Phase 0 done.
**Read:** §2, §3, §5, §6, §7, §16.2, the Phase 0 outputs.
**Steps:**
1. Spawn **tracer** (effort high, brief 17.2) for chapter 7 (`GET /v1/offers`). It writes `traces/G03-offers.trace.md`.
2. Spawn **writer** (effort high, brief 17.3) with the trace. It writes: the chapter file for offers; `TEMPLATE.md` (the §5 template made concrete, with one filled example paragraph per section); `METAPHORS.md` (the first 3–5 metaphors, each with its meaning and "introduced in chapter N"); the first rows of `GLOSSARY.md`. Chapters 5 and 6 are not written yet: the offers chapter links to them as "explained in chapter N; you don't need it yet" wherever it needs them (the billing token, the version header).
3. Spawn **verifier** (effort high, brief 17.4), a different agent from the writer.
4. Writer fixes what the verifier rejected. Run the four check scripts.
5. Report to the owner: link to the chapter, the template and the metaphor set; any doubts.
**Exit check:** the **owner reviews and explicitly approves** the tone, depth, metaphors and template. If the owner asks for changes, apply them and repeat step 4. Do not start Phase 2 without approval.
**Update `STATUS.md`:** G03 shows trace + written + verified for chapter 7 only. Log "Phase 1 awaiting/received approval". Next step: "continue phase 2, act 1".

### 16.9 Phase 2 — Per-act pipeline

**Entry:** Phase 1 approved. Run **one act per invocation** ("continue phase 2, act 2"); the large acts (2, 3, 6) may be split in two invocations. Acts run in order 1, 2, 3, 4, 5, 6 (and the Prologue G00 runs last of Act 1 because it points at the others).
**Read:** `STATUS.md`, `TEMPLATE.md`, `METAPHORS.md`, `GLOSSARY.md`, the chapter list for the act, the already-written chapters directly before the act (for continuity), and the group's inventory rows.
**Steps, for each group in the act (up to 5 groups at once):**
1. **Trace.** Spawn a tracer (effort high; brief 17.2) → `traces/<group>.trace.md`. Wait for the file.
2. **Write.** Spawn a writer (effort medium; high if money-critical; brief 17.3) with the trace, the template, the metaphors, the glossary so far, and the previous chapter. It writes the chapters, adds glossary rows and any new metaphors, and lists candidate findings in `traces/findings-candidates.md` (not in the chapter).
3. **Verify.** Spawn a verifier (effort medium; high if money-critical; brief 17.4), never the writer. It writes a verdict file `traces/<group>.verdict.md`: pass, or a numbered list of corrections.
4. **Second verify** (money-critical groups only). A second verifier (effort high; brief 17.4) works independently and does not read the first verdict.
5. **Fix.** The writer revises against all verdicts. A re-check by the verifier of just the corrected points is enough.
6. Mark the group `Done` in `STATUS.md` only after the above.
**After all groups of the act:**
7. **Act check:** run the four scripts. Fix every report. Then continuity: a single agent (effort low) reads the act's chapters in order and confirms that each chapter's end state matches the next chapter's start state, and that Previous/Next links work. It reports mismatches; the writers fix them.
8. Update `00-index.md` with the new chapters.
**Overlap allowed:** the tracers for the next act may start while the current act is in steps 3–7.
**Exit check:** every group in the act is `Done`; scripts pass.
**Next step in `STATUS.md`:** the next act, or "execute phase 3" after Act 6.

### 16.10 Phase 3 — Findings confirmation

**Entry:** Phase 2 done for all acts.
**Read:** `traces/findings-candidates.md`, the chapters, the severity rules (§7).
**Steps:**
1. Group the candidates by act (about 4 batches).
2. Spawn one confirmer per batch (effort high; brief 17.5). The confirmer is given only the candidate's one-line description and the area, **not** the original reasoning, and must re-derive the problem from the code. It returns `confirmed` / `rejected` / `downgraded to not-worth-listing`, with a plain-language explanation for each confirmed one.
3. The coordinator inserts each confirmed finding into the **Findings** section of the affected chapter (template section 10) and builds `reference/findings-register.md`, sorted critical first.
4. A final agent (effort medium) re-reads every inserted finding for the §7 bar (major or critical only) and for banned content (no code or lines).
**Exit check:** every candidate is resolved; the register links to the right chapters; scripts pass.
**Next step:** "execute phase 4".

### 16.11 Phase 4 — Reference shelf

**Entry:** Phase 3 done.
**Read:** `INVENTORY.md`, all chapters, the glossary.
**Steps:**
1. Spawn 7 writers in parallel (effort medium; brief 17.6), one per file in `reference/`: `d1-columns.md` (both workers; for each column say which chapter writes it and which reads it), `r2-and-durable-objects.md`, `supabase.md`, `error-codes.md`, `wire-contracts.md`, `environment-and-bindings.md`, and the finished `glossary.md` (a cleaned, sorted copy of `GLOSSARY.md` with links). The findings register already exists from Phase 3.
2. Spawn 3 verifiers (effort medium) over these files, split by file, to check facts against the code.
3. Fix pass; run the scripts.
**Exit check:** every inventory item appears in a chapter or a reference file; scripts pass.
**Next step:** "execute phase 5".

### 16.12 Phase 5 — Final checks and cleanup

**Entry:** Phase 4 done.
**Steps:**
1. Run `check_coverage.py` across the whole inventory. Any gap sends the coordinator back to the owning group to add the missing content (a small writer + verifier run).
2. Run all four scripts on everything. Fix reports.
3. Build the final `00-index.md` (remove the work-in-progress note).
4. Ask the owner before cleanup. On approval, follow §11: delete the old data-journey folder and stubs, fix links, update `docs/architecture/00-index.md`. Delete `traces/`. Keep or delete `tools/` and `INVENTORY.md` as the owner decides.
**Exit check:** the owner has the index and a short report: chapter count, findings count by severity, any open doubts.

---

## 17. Agent briefs

The coordinator pastes the matching brief, with the placeholders filled, as the agent's prompt. Every brief starts with the same preamble.

**Preamble (all agents):**
> You are working on the data-journey documentation for this repository. First read `docs/architecture/data-journey/PLAN.md` fully; sections 1–7 are the rules and you must follow them: the code is the only source of truth (do not use the architecture docs as a source), no code snippets, no file paths, no line numbers, no tests, plain language with metaphors, terms explained before use. You are read-only on the code. Write only inside `docs/architecture/data-journey/`. Do not commit. If you are unsure about something, write it in `traces/doubts.md` and say so in your report instead of guessing.

### 17.1 Inventory agent
> Area: `<ABO | AP | Supabase | Flutter>`. List **every** item in your area for each applicable category in PLAN §8: HTTP routes (method, path, host, auth), RPCs/tables/triggers, D1 tables and columns, R2 prefixes and object types, Durable Object fields, cron schedules and scheduled jobs, call sites, error and notice codes, env vars/secrets/bindings. Be exhaustive; completeness matters more than prose. Write `traces/inventory-<area>.md` using the table format in PLAN §16.4, one row per item, stable IDs, with "Assigned group" empty. In "Notes" write a short factual hint (what it is). Do not interpret or judge.

### 17.2 Tracer
> Group: `<Gxx>`, chapters `<list>`. Trace what really happens, from the code, for each chapter's event, from the trigger to the final state. Write `traces/<Gxx>.trace.md` with, per chapter: (1) trigger and starting state; (2) an ordered list of hops — for each hop: who acts, what is received or sent (fields and meaning), every store read or written (store, table or object, columns or fields), every branch and failure with its exact error code, HTTP status and retry-safe flag, and what the caller does next; (3) crash/replay/race behaviour and what recovers it; (4) end state of every store touched; (5) candidate terms for the glossary (term + plain meaning); (6) **candidate findings** (major/critical only per PLAN §7), each as one line plus the reasoning. Follow every branch; do not summarise. Your inventory rows: `<IDs>`; make sure the trace covers them all. Facts only.

### 17.3 Writer
> Group: `<Gxx>`, chapters `<list>`. Read the trace `traces/<Gxx>.trace.md`, `TEMPLATE.md`, `METAPHORS.md`, `GLOSSARY.md`, and the previous chapter. Write the chapters in `docs/architecture/data-journey/` using the template, in plain language with metaphors consistent with `METAPHORS.md`. Use only terms that are defined in earlier chapters or in the chapter's own "Words you'll meet here" box, or link to their home chapter. Every field, state and error in the trace must appear. Add new terms to `GLOSSARY.md` and new metaphors to `METAPHORS.md`. Put candidate findings in `traces/findings-candidates.md` (group, one line, severity guess), **not** in the chapter. Do not read the code unless the trace is unclear; if you do, note the unclear point in `traces/doubts.md`. Run `tools/lint_terms.py` and `tools/check_banned.py` on your chapters before reporting.

### 17.4 Verifier / second verifier
> Group: `<Gxx>`. You did not write these chapters. Fact-check every claim in `<chapter files>` against the **code** (not the trace, not the architecture docs): order of steps, field meanings and types, error codes and HTTP statuses, which store changes, schedules, state values, who calls whom. Also check the quality bar in PLAN §10, the template, and that no term is used before it is explained. Write `traces/<Gxx>.verdict<1|2>.md`: `PASS`, or a numbered list of corrections, each with the chapter, what is wrong, and what the code actually does (in words). Do not edit the chapters. `<Second verifier only: do not read verdict1.>`

### 17.5 Findings confirmer
> Batch: `<list of one-line candidate findings and the area>`. For each, decide from the code alone whether it is real and whether it meets the PLAN §7 bar (major or critical). Return per candidate: `confirmed`, `rejected` or `not worth listing`, and for confirmed ones a plain-language description of what goes wrong, under what circumstances, and why it matters (no code, no lines). Do not fix anything.

### 17.6 Reference writer
> File: `reference/<name>.md`. Build it from `INVENTORY.md` and the finished chapters, checking the code for any detail the chapters do not give. Use tables. For every entry give the plain meaning and a link to the chapter that explains it. Same rules as the chapters apart from the narrative template.
