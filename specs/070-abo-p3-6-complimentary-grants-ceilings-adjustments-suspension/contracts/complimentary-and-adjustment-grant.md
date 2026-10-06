# Contract: Complimentary and adjustment grants

**Unit**: P3.6 · **Requirements**: FR-001, FR-002, FR-004, FR-005, FR-006, FR-007, FR-009

Later units call `VendorEntrypoint.grant` for a complimentary term and for `term_adjustment`. The paid grant path and its receipt stay as they are. This file does not add envelope keys. `packages/vendor-contracts` `validateGrantEnvelope` already allows these envelopes.

## 1. Call

Class HP. The call carries `access_jwt`, `signer_credential_id`, `operation`, `assertion`, and `envelope`. `operation.params` is `{ contract_version, access_jwt, envelope }`. The assertion is over that operation. `source.kind` is `complimentary`. `source.operator_email` and `source.reason` are required. Duration unit is `month` or `day`. `placement` is `queue`.

A missing `operator_email` or `reason` is `rejected` with code `bad_request` and empty `detail`. No receipt.

## 2. Complimentary term result

A passing grant is `applied` and includes a receipt. The same `grant_id` and `envelope_sha256` return `already_applied` with that receipt. A different envelope for that `grant_id` is `conflict`.

The term is queued when the clinic already has an active, grace, or queued term. It is active when the clinic has none. A following paid grant then queues behind an active trial.

Over the ceiling, the result is `rejected` with code `exceeds_ceiling` and empty `detail`. Nothing is written.

## 3. Ceiling override

`ceiling_override` is optional. Its value is a second encoded operator assertion. The operation it signs is `{ op: "ceiling_override", params: { contract_version, access_jwt, envelope } }` with `ceiling_override` omitted from that envelope. `evidence.approvals` has two stub elements, which is the package rule. Those stub strings are not the WebAuthn check.

A valid second assertion skips the ceiling check. The grant is `applied`. The same challenge hash as the grant assertion, or a hash already stored in `assertion_used`, is `rejected` with code `assertion_used`.

## 4. `term_adjustment`

`kind` is `term_adjustment`. `adjustment` is `{ plan?, add_allowance?, extend_days? }`. A paid source is `rejected` with code `bad_request`. `placement` `immediate` is `rejected` with code `placement_not_supported`.

A positive `extend_days` moves the active term's `ends_at` later. An adjustment that would move `ends_at` earlier is `rejected` with code `bad_request` and writes nothing. A `plan` change replaces the active term's `plan_snapshot`. The next `GET /v1/capabilities` advertises that snapshot's capability ids after the alarm ships the mirror. Queued terms are unchanged.

Idempotent by `grant_id`. A repeat returns the first receipt and does not apply again. The result on first success is `applied` and includes a receipt.

## 5. Alerts

Every applied complimentary grant and every applied adjustment emits one AL-11. The captured email body is the paid AL-11 object plus `attention: true`. `operation.params` is the envelope, so `source.operator_email` and `source.reason` are in that body. Paid grants do not gain `attention`.

A valid ceiling override also emits one AL-12. The body is `{ code: "AL-12", org_id, operation: { op: "grant", params: envelope } }`. A rejected override emits neither AL-12 nor AL-11.
