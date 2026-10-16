# P4.6 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Class-H ABO `control_audit` write

**Question:** Class-H ABO actions (retry parked work, cancel an open checkout) must write `control_audit` on the platform with the Access email as actor (05 §3.2, sentence after the action table). That sentence does not name a platform method, argument, or other write path. Cancel is verified by the ABO and does not otherwise call the platform. Which existing frozen call writes that audit row, or where is the write specified?

**Assumption:** No frozen `VendorEntrypoint` call writes `control_audit` for an ABO-verified action. After the ABO commits `operator_action`, it calls class-H `recordOperatorAction` with `access_jwt`, `action`, `subject`, and `action_id` copied from that row. The call inserts one `control_audit` row and leaves every other platform table unchanged: `actor` and `operator_id` are the Access email, `action` is the `action` argument, `target` is the `action_id`, and `assertion_sha256` is null. The same `action_id` again is `ok` and inserts no second row. `ok` has an empty `code`, an empty `detail`, and no `receipt`. A missing, expired, or wrong-`aud` Access JWT is `rejected` with code `unauthenticated` and inserts no row. Retry parked work and cancel an open checkout use this call. Cancel an open checkout has this call as its only platform call. A platform-verified action still writes `control_audit` inside its own class-H or class-HP call.

**Why:** 04 §1.3 has no method whose effect is an audit row for an ABO-local action. `grant` is class M and does not record the Access email. `inspectCoverage` is a lookup, and cancel does not call it. `operator_action` is the ABO table, so it cannot be the platform row. `recordOperatorAction` is one class-H insert, idempotent on `action_id`, using the `control_audit` columns the H/HP entrypoint audit already fills.

**Amended:** `docs/architecture/ai-billing-orchestration/05-abo-operations-and-traceability.md` (§3.2, sentence after the action table).

## 2. Which unit implements and freezes `recordOperatorAction`

**Question:** The amended 05 §3.2 sentence makes ABO-verified actions call class-H `recordOperatorAction` on `VendorEntrypoint`. No frozen call provides it. P4.6’s delivery-plan row is codebase `abo`, names no wiring exception, and freezes nothing. Rule S7 allows the ABO to call only methods a platform unit has already frozen, on the real platform worker. Which unit implements `recordOperatorAction` and freezes it?

**Assumption:** P4.6 implements class-H `recordOperatorAction` on the real platform `VendorEntrypoint` and freezes it. The P4.6 row names the wiring exception (codebase abo plus thin wiring in `ai-platform`) and lists the method under Outputs / freezes. This unit calls that frozen method after it commits `operator_action`. No earlier unit froze the method, and no later unit implements it.

**Why:** P3.1 froze dispatch and the class table, not this method. P4.7 and later have not started, so the work cannot move to them. S7 lets the ABO call a method only after a unit has frozen it on the real platform worker. The wiring exception is that freeze: P4.6 adds the method, then calls it.

**Amended:** `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (rule S3 wiring-exception list; rule S7 freeze sentence; rule S10 concurrency exception; P4.6 codebase, Implements, Outputs / freezes; D1 04 §1.3).

## 3. `inspectCoverage` relay keeps the frozen actor check

**Question:** E2E-P4.6-07 and FR-003 require the platform to audit the actor email when the console relays `inspectCoverage`. Frozen `VendorEntrypoint.inspectCoverage` (P3.6) verifies the Access JWT and returns terms, grants, and reservations. It does not write `control_audit` or any other actor-email record. Recording that audit would change the consumed method. Spec §5 says this unit calls `inspectCoverage` and does not change it, `suspend`, or `resume`.

**Assumption:** The relay adds no platform write. E2E-P4.6-07 observes the frozen call. The ABO forwards the operator's Access JWT as `access_jwt`. `inspectCoverage` already verifies that JWT, including its `email` claim, and on success returns `ok` with `detail` JSON `{ terms, grants, reservations }`. That `email` claim is the actor identity the call already accepts. The result does not echo the email. The call inserts no `control_audit` row and no other actor-email record. A missing Access JWT stays `rejected` with `unauthenticated` and still writes nothing. The clinic page shows the returned terms, grants, and reservations.

**Why:** P3.6 froze `inspectCoverage` as a class-H lookup. Input beyond `contract_version` and `access_jwt` is `org_id`, and `detail` is `{ terms, grants, reservations }`. Verification already requires `payload.email` to be a string and returns `{ ok: true, email }` from that claim. The method uses that result only as the accept or reject gate. It does not write `control_audit`. A new actor-email record would change the consumed method. The relayed JWT and that existing email-claim check are the observable outcome of FR-73 on this read.

**Amended:** `specs/081-abo-p4-6-operator-console-access-perimeter-lookup/spec.md` (Clarifications; §2.1 narrative and acceptance scenario 4; E2E-P4.6-07; FR-003).
