# P4.7 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Refusal code when the credential id is absent from the active list

**Question:** `listOperatorCredentials` returns only active `{credential_id, public_key_cose, alg}` rows. FR-002 and the edge cases require `credential_revoked` when a credential is revoked and `credential_not_active` when it is not active. Which refusal code does an ABO-side HP check use when the credential id is absent from that list?

**Assumption:** `credential_not_active`. The ABO-side HP check looks up the assertion's `credential_id` in that active-only array. An id that is absent is `rejected` with `credential_not_active`. A still-`pending` row, a `revoked` row, and an unknown id are all omitted, so they all use that code. `credential_revoked` stays the platform's code when its own credential read sees `status` `revoked` (04 §1.5). This unit does not call another platform method to learn that status. After a revoke, the next HP check loads the list again and refuses with `credential_not_active`.

**Why:** 04 §1.3 returns only active `{credential_id, public_key_cose, alg}` rows, and that array is what the ABO uses to verify its own HP actions. The list has no status, so the ABO cannot tell a revoked row from a pending row or an unknown id. 04 §1.5 assigns `credential_revoked` only when a credential read sees `status` `revoked`, which is the platform's own HP path. Using `credential_revoked` on the ABO would claim a status the list does not show and would need a new platform method. E2E-P4.7-07 requires refusal after refresh, and `credential_not_active` is that refusal.

**Amended:** `specs/082-abo-p4-7-console-passkey-ceremony-abo-side-hp/spec.md` (Clarifications; User Story 1 acceptance scenario 2; E2E-P4.7-07; §2.5 edge cases; FR-002; FR-004; §4.1 Failure Handling).
