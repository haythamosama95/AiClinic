# P3.3 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Worker → DO contract-version scenarios

**Question:** Which scenario line shows the Platform Worker → per-clinic DO RPC accepting and echoing the current contract version, and which scenario line refuses a missing or unsupported version before authentication and before any write?

**Assumption:** E2E-P3.3-11 is the accept-and-echo line: a Platform Worker → per-clinic DO RPC that carries the current contract version is accepted, and the DO answer echoes that same `contract_version`. E2E-P3.3-12 is the refusal line: a call whose `contract_version` is missing or unsupported (2 at launch, because every channel is version 1) is `rejected` with `contract_version_unsupported` and `accepted_versions`. That check runs before authentication and before any write, so nothing changes. The DO still accepts N and N−1 and answers in the version the call used. The Worker still maps that refusal to `coverage_unknown` for the clinic; that mapping stays on the later clinic-path lines E2E-P3.4-12 and E2E-P7.3-05.

**Why:** 04 §7.2 already accepts N and N−1, answers in the request's version, and refuses a missing version or one outside N and N−1 with `contract_version_unsupported` and `accepted_versions` before authentication and before any write. The §7.1 Worker → DO row already returns `rejected` and has the Worker map that refusal to `coverage_unknown`. Rule V5 requires this unit's own channel to show both the current-version echo and the before-auth refusal, and P3.1 already uses "missing or 2" for that launch refusal. N and N−1 across a deploy stay with P7.3. The P3.3 list had no line for either case.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§7.1 row “Platform Worker → per-clinic DO RPC”); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P3.3 E2E-P3.3-11, E2E-P3.3-12).

## 2. Service-key status, validity, and envelope

**Question:** What are the stored `service_key.status` values, where is validity stored, what is the stored form of `public_key`, what `result` / `code` / `detail` do `registerServiceKey`, `revokeServiceKey`, and `listServiceKeys` return, and what happens when the same `kid` is registered again with a different `public_key`?

**Assumption:** `status` is `active` or `revoked`. There is no `retiring` status, and expired is not a stored status. Validity is the UTC ISO-8601 columns `not_before` and `not_after`. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. These methods do not record a grant or a reversal. A successful call is `ok`, with `code` empty and `receipt` absent. `registerServiceKey` takes `kid`, `public_key`, `not_before`, and `not_after`. It inserts `status` `active`, sets `service` to `abo`, stores `public_key` unchanged, sets `registered_by` to the Access email, and sets `assertion_sha256` to the assertion challenge hash. `detail` is the JSON text of the `service_key` row. The same `kid` with the same `public_key` is `ok` again and does not insert another row or change `status` or the stored validity. The same `kid` with a different `public_key` is `conflict` with code `public_key_mismatch` and `detail` empty. A `public_key` that is not that encoding is `rejected` with code `public_key_invalid` and `detail` empty. `revokeServiceKey` takes `kid`. It sets `status` to `revoked`, and it is `ok` when the row is already `revoked`. It is the only writer of `revoked`. A missing `kid` is `rejected` with code `kid_not_found` and `detail` empty. On `ok`, `detail` is the JSON text of the row. `listServiceKeys` returns every row, including `revoked`, as a JSON array of `{kid, status, not_before, not_after}` in `detail`. On `grant`, an unknown `kid` is `transient` with `detail` `unknown_kid`. A `kid` with `status` `revoked`, or a `kid` with `status` `active` whose now is before `not_before` or after `not_after`, is `rejected` with `bad_signature`. Routine rotation revokes the old key with `revokeServiceKey`. The ABO treats its signing `kid` as usable only when the list shows it `active` and not expired.

**Why:** `registerIssuerKey` and `revokeIssuerKey` already use this envelope, this `public_key` encoding, `not_before` / `not_after`, `public_key_mismatch`, `public_key_invalid`, and `kid_not_found`. Service keys have no retire method, and validation step 2 accepts only an unknown `kid` as `transient`; a revoked or expired `kid` is `bad_signature`. K-4's routine "retire" is that revoke, done after the secret has switched. The list includes every row so a revoked `kid` is visible as not active.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§3.2 row `service_key`); `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.2, §1.3 rows `registerServiceKey`, `revokeServiceKey`, `listServiceKeys`, §1.4 validation step 2); `docs/architecture/ai-billing-orchestration/02-abo-architecture-and-threat-model.md` (§6 row K-4).

## 3. Plan-version publish and retire

**Question:** What `result` / `code` / `detail` do `publishPlanVersion` and `retirePlanVersion` return, and what happens when the same `(plan_id, version)` is published again with different fields?

**Assumption:** Both succeed as `ok`, with `code` empty, `receipt` absent, and `detail` the JSON text of the `plan_version` row. `publishPlanVersion` takes `plan_id`, `version`, `display_name`, `capabilities`, `max_cost_class`, `concurrency_limit`, and `max_allowance_per_month`. It inserts `status` `published`, sets `published_by` to the Access email, and sets `assertion_sha256` to the assertion challenge hash. The same `(plan_id, version)` with the same values in those content fields is `ok` again and does not insert another row or change `status` or those fields. The same pair with a different value in any of those fields is `conflict` with code `plan_version_mismatch` and `detail` empty, and the stored row is unchanged. `retirePlanVersion` takes `plan_id` and `version`. It sets `status` from `published` to `retired`, and it is `ok` when the row is already `retired`. It is the only writer of `retired`. A missing `(plan_id, version)` is `rejected` with code `plan_version_not_found` and `detail` empty. Content fields stay immutable once published.

**Why:** Issuer-key register and retire already return `ok` with the row in `detail`, replay the same material without rewriting it, and answer `conflict` with a named mismatch code when the stored material differs. A missing issuer `kid` is `kid_not_found`; a missing plan version uses the same shape, `plan_version_not_found`. `retireIssuerKey` is `ok` when the row is already in the target status and is the only writer of that status.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.2, §1.3 rows `publishPlanVersion`, `retirePlanVersion`); `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§3.2 row `plan_version`).

## 4. getCoverage queued and recent terms

**Question:** What fields do the queued terms and the recent terms on `getCoverage` carry, how many terms are "recent", and how does that payload sit in the result envelope?

**Assumption:** A successful call is `ok`, with `code` empty and `receipt` absent. `detail` is the JSON text of `{snapshot, queued_terms, recent_terms}`. `snapshot` is the §1.7 object. `queued_terms` are the unheld terms in state `queued`, in ascending `position`. Each is `{plan_id, plan_version, plan_display_name, duration_unit, duration_count}` and has no dates. `recent_terms` are at most the last 12 terms whose state is `active`, `grace`, or `ended`, highest `position` first. Each is `{term_id, state, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used}`. `used` is `hot.used` when the term is `hot.active_term_id`, and `used_final` otherwise. Fewer than 12 returns those that exist.

**Why:** The result envelope has no key besides `contract_version`, `result`, `code`, `detail`, and an optional `receipt`, and `detail` is a string, so the lists travel as JSON text on an `ok` read. `GET /v1/coverage` already names queued terms as plan and duration, and the last 12 terms with usage. Queued terms store a duration, not dates. The current term's live usage is `hot.used`; an ended term's usage is `used_final`.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.3 row `getCoverage`, §1.7).

## 5. listGrants window and success envelope

**Question:** What are the argument names for `listGrants`' time window, and what `result` / `code` / `detail` does a successful call return?

**Assumption:** The filter arguments are `org_id`, `source_kind`, `credential_id`, `applied_from`, and `applied_to`. `credential_id` matches `operator_credential_id`. `applied_from` and `applied_to` are inclusive UTC ISO-8601 bounds on `applied_at`. An omitted filter does not constrain that column. A successful call is `ok`, with `code` empty and the envelope `receipt` absent. `detail` is the JSON text of the matching `grant_ledger` rows, ordered by `applied_at` then `grant_id` ascending. Each row is `{grant_id, origin_grant_id, org_id, installation_id, kind, source_kind, operator_credential_id, envelope_sha256, receipt, applied_at}`, and `receipt` is the §1.6 object.

**Why:** The ledger is indexed on `(org_id, applied_at)` and `(operator_credential_id, applied_at)`, so the window is two bounds on `applied_at`. A read uses the same `ok` / empty `code` / JSON `detail` envelope as `listIssuerKeys`. SR-25 lists by credential and window, so each filter is optional.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.2, §1.3 row `listGrants`); `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§3.2 row `grant_ledger`).

## 6. R2 grant-ledger object

**Question:** What is the R2 object key under `grant-ledger/`, and what NDJSON fields does each object contain besides the receipt?

**Assumption:** One grant is the object `grant-ledger/<grant_id>.ndjson`: a single JSON line `{grant_id, origin_grant_id, org_id, installation_id, kind, source_kind, operator_credential_id, envelope_sha256, applied_at, receipt}`. `receipt` is the §1.6 object. The other fields are the `grant_ledger` columns. A rebuild copies that line into `grant_ledger`. A void is a different object, `grant-ledger/<grant_id>.void.ndjson`: one JSON line `{grant_id, reason, source, evidence_sha256, at, receipt}` and it does not replace the grant object.

**Why:** The prefix is already `grant-ledger/`, one object per grant, and that object is the rebuild source for `grant_ledger`. The line is the ledger row plus the receipt the section already requires. The void suffix keeps the per-void object in the same prefix from overwriting the grant object.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§3.3).

## 7. coverage_event.kind

**Question:** What stored values does `coverage_event.kind` take?

**Assumption:** `kind` is one of `grant_applied`, `grant_voided`, `term_activated`, `term_ended`, `term_held`, `term_released`, `grace_started`, `band_crossed`, `suspension_changed`, or `transfer`. `band_crossed` is both the 75 % crossing and the 90 % crossing; the snapshot carries the band. A paid grant emits `grant_applied`, plus `term_activated` when placement leaves the new term `active`, plus `term_ended` when placement ends the grace term. A grant that only queues emits `grant_applied` alone. Those events are written in the order `term_ended`, `term_activated`, `grant_applied`, skipping any the grant does not emit.

**Why:** §6.7 already names those changes and no others. One token per change matches the closed `kind` lists on `offer_event` and `checkout_event`. The paid-grant subset is the placement this unit performs; the other tokens are the same column for the later changes in that list. The feed event's `kind` is that stored value.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§3.2 row `coverage_event`, §6.7); `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§4.1 event object).

## 8. Receipt signature and ledger_seq

**Question:** How is the receipt `signature` encoded, and which counter is `ledger_seq`?

**Assumption:** `signature` is a compact JWS (RFC 7515): base64url header, payload, and signature joined by `.`. The header is `{alg: "EdDSA", kid}` for the platform signing key. The payload is the RFC 8785 canonical receipt with the `signature` member omitted. The third segment is the base64url Ed25519 signature. `ledger_seq` is the integer `clinic_seq` on the coverage event for this grant (`kind` `grant_applied`) or void (`kind` `grant_voided`). It is not a `grant_ledger` column.

**Why:** §1.1 already serialises Ed25519 signatures, including K-3, as compact JWS over the canonical bytes. The receipt is known when the DO applies the grant, which is when it assigns `clinic_seq`; `feed_seq` is the D1 autoincrement assigned later, when the alarm inserts the row. The receipt is stored inside `grant_ledger.receipt`, so `ledger_seq` does not need its own column.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.6); `docs/architecture/ai-billing-orchestration/02-abo-architecture-and-threat-model.md` (§6 row K-3).

## 9. Plan capabilities shape

**Question:** What is the stored shape of `plan_version.capabilities` and of `term.plan_snapshot.capabilities`?

**Assumption:** `plan_version.capabilities` is a JSON array of capability id strings. `term.plan_snapshot` is a JSON object `{plan_id, version, display_name, capabilities, max_cost_class, concurrency_limit}`. Its `capabilities` member is that published array, copied unchanged.

**Why:** The replaced plan catalogue stored capabilities as a JSON array of capability id strings, and admission plus `/v1/capabilities` test membership in the term's plan. The snapshot's other members are the plan fields §3.1 already says it copies.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§3.1 `term` row, §3.2 row `plan_version`).

## 10. readCoverageEvents limit above 200

**Question:** What is the result when `readCoverageEvents` is called with `limit` greater than 200?

**Assumption:** A `limit` greater than 200 is outside 1 through 200. The result is `rejected` with code `limit_invalid` and `detail` empty. `receipt` is absent. No events are returned. A missing `limit`, or a `limit` below 1, is the same refusal. A `limit` of 200 is accepted.

**Why:** The input bound is `limit` ≤ 200, and this design refuses a broken bound with a named `rejected` code rather than changing the caller's number. `public_key_invalid` is the same shape: the value does not meet the stated form, `detail` is empty, and nothing is written.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.3 row `readCoverageEvents`).

## 11. Approvals minimum on every grant

**Question:** `evidence.approvals` has a policy minimum of 1, and the ordered `grant` validation steps name no check and no code for a short `approvals` list. Which grants does the minimum bind, and what is the failure result?

**Assumption:** The minimum of 1 binds every grant: `paid`, `complimentary`, and `transfer`. It is checked in validation step 1 and does not renumber steps 2–5. A shorter `evidence.approvals` list is `rejected` with code `approvals_required` and `detail` empty. `receipt` is absent.

**Why:** X-09 already sets the policy minimum at 1 on grant evidence, and the evidence field is on every grant. `assertion_required` is the existing code for a missing approval. Putting the check in step 1 leaves the cited step numbers 2–5 as they are.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.4 evidence row and validation step 1).

## 12. Spec sentences that still contradict the amended spans

**Question:** `spec.md` still transcribes the pre-amendment design, after the design assumptions in entries 2 through 11 were written into the cited sections. Those questions stay closed. Re-transcribe only the sentences that contradict the amended spans: FR-004 and the `service_key` entity; FR-005; FR-006 and the `plan_version` entity; FR-007 step 1 and FR-009; FR-011, FR-012, and the `coverage_event` and R2 entities; FR-014; FR-016; and the edge cases and Failure Handling that cite 04 §1.3, 04 §1.4, 04 §1.6, 03 §3.3, and 03 §6.7.

**Assumption:** Entries 2 through 11 stay closed. Clarify, on continuation, re-transcribes only the contradicting sentences named in this escalation from the amended spans, then finishes. Stop condition 3 does not fire again for those sentences. A fresh clarify run still stops on a real contradiction.

**Why:** Entries 2 through 11 already wrote those contract answers into 02, 03, and 04. The spec still quotes the earlier sentences of the same sections, so the contradiction is a stale transcription, not an open design question. Re-transcription belongs to clarify: it copies only the named sentences from those amended spans and does not decide a new fact. Stop condition 3 firing again would send the same closed facts back to the resolver. The waiver names only those sentences, and only when the prompt continues after this amendment. Any other contradiction, including on a fresh clarify run, still stops.

**Amended:** `.cursor/skills/abo-clarify/SKILL.md`
