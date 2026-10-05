# Contract: Paid grant

**Unit**: P3.3 · **Requirements**: FR-005, FR-007, FR-008, FR-009, FR-010

Later units bind to this file for paid `grant`. Envelope field rules stay `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/grant-envelope.md`. This unit does not change `validateGrantEnvelope`, `grantEnvelopeHash`, or `verifyGrantSignature`.

## 1. Call

Class M. No Access JWT and no assertion. The argument object is `{contract_version, envelope, abo_kid, abo_signature}`. `envelope` is the object that is hashed and signed. `abo_signature` is the compact JWS. `contract_version` on the argument is checked with `negotiate(CHANNEL_VERSIONS.vendorEntrypoint, …)` before the envelope is read and before any write.

This freeze covers `envelope.source.kind` `paid`. When `source.kind` is not `paid`, the method returns `rejected` with `code` `unit_not_allowed` and `detail` empty, and writes nothing. A later unit extends this method by handling its own `source.kind` before that return. The paid results in this file stay.

## 2. Check order

The platform stops at the first failure. Nothing is written on failure, including no binding and no DO call.

1. Argument `contract_version` is supported. Then the JWS payload bytes equal `canonicalize(envelope)`. A mismatch is `rejected` `bad_signature` with `detail` empty. Then `evidence.approvals` has at least 1 element. A shorter list is `rejected` `approvals_required` with `detail` empty.
2. `abo_kid` is loaded from `service_key`. A missing row is `transient` with `detail` `unknown_kid`. `status` `revoked`, or `status` `active` when now is before `not_before` or after `not_after`, is `rejected` `bad_signature`. Expired is not a stored status. `verifyGrantSignature` then runs with that row's `public_key`. Failure is `rejected` `bad_signature`.
3. `(plan.plan_id, plan.plan_version)` has `status` `published`. Otherwise `rejected` `plan_not_published`. Then the source is `paid`, `kind` is `term`, `duration.unit` is `month`, and `duration.count` is 1, 3, or 12. Otherwise `rejected` `unit_not_allowed`. A paid `term_adjustment` is `unit_not_allowed`. Then `allowance_credits` is an integer of at least 1 and at most `max_allowance_per_month` times the month count, and `grace` is `{days <= 7, cap_rule: "proportional"}`. Otherwise `rejected` `exceeds_plan_bound`. `placement` `immediate` or `replace` is `rejected` `placement_not_supported`. `validateGrantEnvelope` must also return `{ok: true}` before the binding step. Its `placement_not_supported` code is the same refusal.

`placement` `queue` is the only placement this unit applies.

## 3. Binding

After the checks, the platform resolves the active `tenant_binding` for `envelope.org_id`, or inserts one as [data-model.md](../data-model.md) section 4 describes. The DO name is that row's `installation_id`.

## 4. Apply

The worker calls DO kind `apply_grant` with `contract_version` set to `CHANNEL_VERSIONS.platformDo`. Inside `blockConcurrencyWhile`:

| Stored `grant_id` | Result |
| --- | --- |
| Absent | `applied`. One `grant` row, one `term` row, outbox rows, and the receipt. |
| Present, same `envelope_sha256` | `already_applied` and the stored receipt. No second row, no second outbox row, no second alarm change. |
| Present, different `envelope_sha256` | `conflict` with `detail` empty. Nothing changes. |

`envelope_sha256` is `grantEnvelopeHash(envelope)`.

## 5. Placement

There is no `not_pending` refusal.

| Condition | Term |
| --- | --- |
| No `active`, `grace`, or unheld `queued` term | `state` `active`. `starts_at` = `calendar_start` = now. `ends_at` = add(`calendar_start`, `month`, count). `hot.active_term_id` is this term. |
| An `active` or unheld `queued` term exists | `state` `queued`, appended at the next `position`. Date columns stay null. |
| A `grace` term exists | The new term is `active` with `calendar_start` equal to the grace term's `ends_at`. The grace term becomes `ended` with `end_reason` `renewed` and `ended_at` now. |

`now` is `clockNowIso`. `ends_at` uses `src/coverage/calendar.ts`. `grace_cap` stores `proportional`. `grace_days` stores `grace.days`. `allowance` stores `allowance_credits`. `used_final` is null until the term ends. A new active term sets `hot.used` to 0.

`coverage_through` for the snapshot is the active `ends_at` plus each later unheld queued duration, using the same add.

The snapshot `state` is `active` when an active term exists. `reason` is `none`. `suspended` is false. `band` is `ok`. `used` is 0. `ref` is `term_id`. `grace_ends_at` on the snapshot is `""` when the term row's `grace_ends_at` is null. `queued_terms` have no date fields. `contract_version` on the snapshot is the negotiated vendor version of the grant call.

Events for that placement are in [coverage-event.md](./coverage-event.md).

## 6. Result envelope

| `result` | `code` | `detail` | `receipt` |
| --- | --- | --- | --- |
| `applied` | `""` | `""` | The receipt |
| `already_applied` | `""` | `""` | The original receipt |
| `conflict` | `""` | `""` | Absent |
| `rejected` | The named code | `""`, except where a check above sets `detail` | Absent |
| `transient` | `""` | `unknown_kid` | Absent |

`contract_version` on the result is the negotiated vendor version.
