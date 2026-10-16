# P4.10 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Receipt mismatch finding kind

**Question:** E2E-P4.10-09 (AD-15) requires a finding when a stored receipt differs from `listGrants`. 05 §3.3 names ten finding kinds and does not include this check. 03 §2.10 requires `finding.kind` from 05 §3. Which kind is written, and which reconciliation check does it belong to?

**Assumption:** This case is an eleventh 05 §3.3 check, not one of the existing ten. Every ABO `grant_outcome` whose `result` is `applied` or `already_applied` must have a `receipt` equal to the `receipt` `listGrants` returns for that `grant_id` (04 §1.6, the `grant_ledger` copy). Equality is the receipt object field for field, including `signature`. A missing `listGrants` row for that `grant_id` fails the check. Failure writes `finding.kind` `receipt_mismatch` and raises AL-10, the same as every other check in that table. Void receipts and transfer receipts are outside this check: `listGrants` returns grant receipts only.

**Why:** AD-15 already says reconciliation compares stored receipts with `listGrants` and cites 05 §3.3. 04 §1.6 (SR-05) says both sides keep the grant receipt: the ABO on `grant_outcome`, the platform on `grant_ledger`, which `listGrants` returns. None of the ten rows compare those two copies. `grant_without_payment` checks that a paid platform grant has an ABO payment; `feed_divergence` compares `coverage_view` with `getCoverage`; `reversal_not_applied` checks that a full reversal has a void receipt or tombstone. A forged grant receipt from a leaked platform signing key can still verify and can still sit on a real payment, so those three stay clean. The new row is the comparison AD-15 already required.

**Amended:** `docs/architecture/ai-billing-orchestration/05-abo-operations-and-traceability.md` (§3.3 check and `finding.kind` `receipt_mismatch`); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P4.10 Implements: eleven checks; E2E-P4.10-09 names `receipt_mismatch`).
