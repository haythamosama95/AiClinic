# Contract: `listGrantsForVoid`

**Branch**: `ai/071-abo-p3-7-reversal-voids-tombstones-held-terms` | **Date**: 2026-10-06

**Spec**: [spec.md](../spec.md) FR-010

Frozen for later units. Class H on `VendorEntrypoint`. Takes `access_jwt`, `credential_id`, and `window`.

## 1. Window

`window` is `{applied_from, applied_to}`. Both fields are required. Each value is a UTC ISO-8601 timestamp ending in `Z`. They are inclusive bounds on `grant_ledger.applied_at`. `applied_from` must be less than or equal to `applied_to`. The span has no maximum.

A missing field, a value that is not that timestamp, or `applied_from` greater than `applied_to` is `rejected` with `code` `window_invalid` and `detail` empty.

## 2. Success

`credential_id` matches `operator_credential_id`, including when that credential is not `active` and when no credential row is `active`.

The result is `ok`. `code` is empty. The envelope `receipt` is absent. `detail` is the JSON text of an array of `{grant_id, origin_grant_id, org_id, installation_id, kind, source_kind, operator_credential_id, envelope_sha256, receipt, applied_at}` for the matching `grant_ledger` rows, ordered by `applied_at` ascending, then `grant_id` ascending. Each `receipt` is the §1.6 receipt object. An empty array is `ok`.

The compromise-response use of this method is to list those grants and void each one with `voidGrant`. This unit does not revoke the credential, revoke Access sessions, or rotate a machine key.
