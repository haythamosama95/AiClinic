# Contract: `releaseHeld` and `voidGrant`

**Branch**: `ai/071-abo-p3-7-reversal-voids-tombstones-held-terms` | **Date**: 2026-10-06

**Spec**: [spec.md](../spec.md) FR-007, FR-008, FR-009

Frozen for later units. Both are class HP on `VendorEntrypoint`. Both take `access_jwt`, `assertion`, `grant_id`, and `reason`. Both return a receipt. Both are idempotent by assertion challenge: the same challenge returns the original receipt as `already_applied` and does not apply again.

The assertion operation is `{op, params, actor_email, issued_at, nonce, contract_version}` with `op` `releaseHeld` or `voidGrant`. `params` is `{contract_version, access_jwt, grant_id, reason}`.

## 1. `releaseHeld`

The held term for `grant_id` becomes `queued` and is placed at the end of the queue. If no term is `active`, that term becomes `active`, with `starts_at` and `calendar_start` set to now. If a term is `active`, the released term stays `queued`.

The receipt uses `grant_id`. `ledger_seq` is the `clinic_seq` on the `term_released` event. This call does not write `grant_void` and does not write `grant-ledger/<grant_id>.void.ndjson`.

## 2. `voidGrant`

No `evidence_sha256` input. A term that has not ended becomes `ended` with `end_reason` `voided`. If it was `active`, the first `queued` term by `position` becomes `active`, with `starts_at` and `calendar_start` set to now.

`grant_void.source` is `operator`. `evidence_sha256` is the assertion challenge. The R2 object is `grant-ledger/<grant_id>.void.ndjson`, one JSON line `{grant_id, reason, source, evidence_sha256, at, receipt}`. The receipt uses `grant_id`. `ledger_seq` is the `clinic_seq` on the `grant_voided` event.
