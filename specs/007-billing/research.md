# Research: Billing (V1-6)

Phase 0 research consolidates decisions for ambiguities and best practices identified during planning. All NEEDS CLARIFICATION items from the plan's Technical Context are resolved here; remaining open items would block Phase 1.

## Decisions

### D1. Monetary precision and rounding

- **Decision**: All monetary columns use PostgreSQL `numeric(14,2)` (fixed scale 2). Percentage-discount intermediate math uses banker's rounding (round-half-to-even) before persisting `discount_amount`/`line_discount_amount` at scale 2. Server-computed balance is also returned at scale 2.
- **Rationale**: NFR-007 mandates exact decimal scale 2 and banker's rounding; `numeric(14,2)` accommodates clinic-scale invoice totals (max ~999,999,999,999.99) without overflow risk.
- **Alternatives considered**: `bigint` cents (extra translation layer in client); `numeric` without scale (allows drift); `double precision` (rejected outright — floating-point unsafe for money).

### D2. Invoice number sequence per branch

- **Decision**: A dedicated table `invoice_number_sequences(branch_id PK, last_value bigint, updated_at)`; `assign_invoice_number(branch_id)` opens a row-level lock (`SELECT ... FOR UPDATE`), increments, and returns the new value. Format `INV-<branch_code>-<padded6>`. Issuance MUST abort with a clear error if `branches.code IS NULL`.
- **Rationale**: PostgreSQL `SEQUENCE` per branch would explode in branch count and offers no transactional gap-freeness; a single counter table with row lock gives strict monotonicity within a branch (gaps allowed across rollbacks, which is acceptable per FR-008 — monotonicity only, not gap-free).
- **Alternatives considered**: One global sequence with branch prefix (no branch-scoped monotonicity); per-branch `bigserial` columns (rigid schema); `advisory_lock` on branch id (works but more opaque).

### D3. Mutual exclusion of line-level vs invoice-level discounts

- **Decision**: Enforce in three layers: (1) RPC pre-check (`assert_discount_scope_exclusive`); (2) deferred CHECK via trigger `AFTER INSERT OR UPDATE` on `invoice_items` and `invoices` that raises if `EXISTS (line discount on invoice) AND invoice.discount_amount > 0`; (3) UI guard component disables the inactive scope's inputs while the other is non-zero.
- **Rationale**: Clarifications Q3 set this as a hard rule. Defense in depth ensures no concurrent edit path can produce a forbidden combined state.
- **Alternatives considered**: Single `discount_scope` enum column on invoice (less flexible if we ever want both — but we explicitly do not, so reconsidered; trigger approach was chosen for future-proofing without losing exclusivity guarantee today).

### D4. Partial-payment policy enforcement point

- **Decision**: `record_payment` RPC reads `organization_billing_settings.allow_partial_payments` inside the same transaction that locks the invoice row, then enforces: if `allow_partial_payments = false` AND `payment_method IN ('cash','card','bank_transfer')` AND `amount > 0` AND `amount < current_balance` → raise `partial_payments_disabled`. `insurance_settlement` and refunds are unconditionally exempt.
- **Rationale**: Clarifications Q1+Q2 set this rule. Reading the setting inside the transaction avoids race with an in-flight settings toggle. Patient-tender-only scope matches real-world insurance settlement semantics.
- **Alternatives considered**: Frontend-only gate (rejected; defense in depth requires server enforcement); per-branch setting (rejected; spec is organization-scoped); blocking all methods (rejected; insurance settlements arrive in non-balance amounts by nature).

### D5. Append-only payments enforcement

- **Decision**: `REVOKE UPDATE, DELETE ON public.payments FROM authenticated, anon`. All payment mutations go through `record_payment` (positive) or `record_refund` (negative). Refunds are NEW rows with negative `amount`, never edits to prior rows.
- **Rationale**: FR-003 and audit requirements mandate immutability of payment history.
- **Alternatives considered**: Trigger-based `BEFORE UPDATE/DELETE RAISE` (works but GRANT-level is simpler and more discoverable in `\dp` output).

### D6. Overpayment race prevention

- **Decision**: `record_payment` opens `SELECT ... FOR UPDATE` on the target `invoices` row, recomputes balance from current items + discount + insurance + sum(payments), validates `new_payment + current_paid ≤ subtotal − discount − insurance_covered`, and inserts the payment row inside the same transaction. Status transitions (`issued`→`partially_paid`/`paid` or `paid`→`partially_paid`/`issued`) are computed within the same transaction.
- **Rationale**: SC-005 requires exactly one acceptance under racing concurrent payments. Row-level locking serializes the balance check.
- **Alternatives considered**: Serializable transaction isolation (more expensive and surface-wide); advisory locks keyed by invoice id (equivalent guarantee but less idiomatic than `FOR UPDATE`).

### D7. Draft optimistic concurrency

- **Decision**: Every draft-mutating RPC (`add_invoice_item`, `update_invoice_item`, `remove_invoice_item`, `apply_line_discount`, `apply_invoice_discount`, `set_insurance_coverage`) accepts an `expected_updated_at` parameter and compares to `invoices.updated_at` under row lock; mismatch raises `stale_invoice` and the client refreshes.
- **Rationale**: FR-031 mandates optimistic concurrency on draft edits; consistent with V1-5 SOAP pattern.

### D8. Settings auto-provisioning

- **Decision**: A trigger on `organizations` INSERT creates a `organization_billing_settings` row with `allow_partial_payments=false`. A backfill migration step ensures every existing organization has a row before the partial-payment check goes live.
- **Rationale**: Guarantees the `record_payment` RPC can always read the setting without nullability fallback logic.

### D9. Receipt print pipeline

- **Decision**: Reuse the existing `printing` package pattern from any prior feature if present, otherwise generate a PDF in Flutter from a render tree and hand off to `Printing.layoutPdf` which invokes the OS native print dialog. No backend PDF rendering.
- **Rationale**: NFR-004 (≤2s for ≤100 items) is well within client rendering capability; avoids backend complexity; aligns with Principle V (operational continuity even when backend is degraded — receipts of locally cached data still render).
- **Alternatives considered**: Backend PDF service (rejected — no custom backend service per Principle II); HTML print via `webview` (rejected — heavier dependency).

### D10. Permission seeding and non-delegable `settings.billing.manage`

- **Decision**: `settings.billing.manage` is seeded only on `owner` and `administrator` and flagged in the V1-2 role-permission UI as non-grantable to other roles (a UI-level guard plus a server-side reject when role-permission RPC receives a grant of this key to `receptionist`/`doctor`/`lab_staff`).
- **Rationale**: FR-020/FR-021 explicitly restrict this key; preventing accidental delegation safeguards the partial-payment policy.
- **Alternatives considered**: Hardcode role check in `update_billing_settings` RPC (still done as belt-and-suspenders); rely solely on permission key without role hardcoding (chosen approach plus role check).

## Open Questions

None. All ambiguities surfaced during `/speckit-clarify` (partial-payment scope, settings location, discount scope exclusivity) are answered in `spec.md` Clarifications section and integrated above.

## References

- Spec: `specs/007-billing/spec.md`
- Constitution: `.specify/memory/constitution.md`
- V1-2 settings page conventions: `specs/003-org-branch-management`
- V1-5 RPC + RLS pattern: `specs/006-visit-medical-records/data-model.md`, `contracts/visit-mutations.md`
- Architecture: `docs/architecture/04-backend.md`, `05-database.md`, `09-security-rbac.md`
