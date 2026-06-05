# Feature Specification: Billing

**Feature Branch**: `specs/007-billing`

**Created**: 2026-06-05

**Status**: Draft

**Input**: User description: "Read V1-6 from docs/architecture/12-roadmap-phases.md and produce the V1-6 Billing specification."

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

This feature delivers patient invoicing and payment recording for a multi-branch clinic after authentication, organization administration, patient registration, appointment scheduling, and clinical visit documentation exist. When a visit is **completed** (V1-5), reception or billing staff create an **invoice** that itemizes services rendered, applies optional discounts (permission-gated), records insurance coverage, and accepts one or more **payments** (cash, card, transfer, insurance settlement) until the invoice balance reaches zero. Invoices print as patient-facing receipts; payment history is auditable. Insurance providers are a small reference catalog used during invoice creation; full claims management is deferred to V3-2 (Advanced Billing).

The primary beneficiaries are **receptionists** and **billing staff** who issue invoices and record payments, **patients** who receive printed receipts, **doctors** and **administrators** who need visit financials closed before clinical workflows are considered "done from a business perspective", and **owners/administrators** who oversee discount approvals and revenue posture across branches.

V1-5 (`specs/006-visit-medical-records`) completes the clinical loop by submitting a visit and auto-completing the linked appointment, but produces no financial record. This feature introduces the billing domain: one active invoice per completed visit, itemized service lines, partial-payment workflow, discount permission gating, insurance coverage split display, branch-scoped policies, invoice status tracking, and printable receipts. Every invoice in V1-6 MUST be linked to a `completed` visit; visit-less ("ad-hoc") invoicing is explicitly out of scope. Walk-in services that need billing MUST first be recorded as a visit per V1-5. Detailed insurance claim lifecycle, automated overdue dunning, and revenue analytics dashboards remain out of scope for V1 and are owned by V3-2 and V3-1.

## Clarifications

### Session 2026-06-05

- Q: Are ad-hoc (visit-less) invoices supported in V1-6? → A: **No.** Every invoice MUST be tied to a `visit_id`; there is no ad-hoc creation path. Walk-in services that need to be billed (vaccines, dressings, consumables, certificates) MUST first be recorded as a visit per V1-5 and then billed from the completed visit. `visit_id` is a required (NOT NULL) column on `invoices`. This supersedes the earlier clarification that allowed ad-hoc invoices.
- Q: What is the source of `<branch_code>` in invoice numbers, and what happens if a branch has no code? → A: **Use the existing `branches.code` field** introduced in V1-2 (`specs/003-org-branch-management`), which is already organization-unique when set. To issue an invoice at a branch whose `code` is NULL, the system MUST reject issuance with a clear error directing an administrator to set the branch code in branch settings before invoices can be issued at that branch. No new branch schema is introduced by V1-6; the existing optional code becomes operationally required only at first invoice issue at a branch.
- Q: What monetary precision (decimal scale) is used for all billing amounts? → A: **Fixed decimal with scale 2** (two fractional digits) for every monetary column — `subtotal`, `discount_amount`, `insurance_covered_amount`, invoice item `unit_price` and `line_subtotal`, and payment `amount`. Percentage-discount intermediate math uses banker's rounding (round-half-to-even) before persisting `discount_amount` at scale 2. Multi-currency and per-currency scale variation remain out of scope (per FR-027).
- Q: How is an unwanted `draft` invoice removed before issue? → A: **Soft-delete the draft** (sets `deleted_at` + actor) by a user with `invoices.create` at the invoice's branch. The visit becomes eligible for a new invoice again. The discard is audited. No new status is added; soft-deleted drafts are excluded from operational queries. Hard delete is not used.
- Q: With V1-1 defining exactly five roles (owner, administrator, doctor, receptionist, lab_staff) and no `billing_staff`, which roles get default billing permissions in V1-6? → A: **`receptionist`** receives `invoices.view`, `invoices.create`, and `payments.record` by default. The sensitive keys `invoices.apply_discount`, `invoices.void`, `payments.refund`, and `insurance.manage` are seeded for **`owner` and `administrator` only**. `doctor` and `lab_staff` receive no billing keys by default. No new role is introduced in V1-6.
- Q: From which visit statuses can an invoice be created? → A: From **`completed`** visits only. Every invoice MUST be linked to a `completed` visit (see ad-hoc clarification above — no visit-less invoices in V1-6).
- Q: Can a visit have more than one invoice? → A: **No** for the visit-linked path (one active invoice per visit). If a previous invoice for the visit was voided, a new invoice MAY be created.
- Q: Are invoices ever editable after creation? → A: Invoice **header** (patient, branch, visit linkage) is immutable after creation. Invoice **items** are editable only while invoice status is `draft`. Once status moves to `issued`, items become immutable; corrections require **void + re-issue** by a user with `invoices.void`.
- Q: How are discounts applied? → A: Discounts can be applied at **two scopes**, but the **two scopes are mutually exclusive per invoice**: an invoice may carry EITHER (a) one or more **line-level** discounts (on individual invoice items, each percentage 0–100 or fixed amount ≤ that line's subtotal), OR (b) a single **invoice-level** discount (percentage 0–100 or fixed amount ≤ subtotal). Setting any line-level discount while an invoice-level discount exists (or vice versa) MUST be rejected; the user must first clear the existing scope before switching. Both scopes require permission `invoices.apply_discount` and are mutable only while in `draft`. Discount changes after issue require void + re-issue.
- Q: Are partial payments always allowed? → A: **No.** Partial payments are controlled by an **organization-level setting** ("Allow partial payments") in the Settings panel. The setting defaults to **disabled** (partial payments NOT allowed); when disabled, the only acceptable patient-tender payment is one whose amount equals the full current balance. When enabled, payments of any positive amount ≤ balance are accepted. The setting is mutable **only by users with role `owner` or `administrator`** (gated by a new permission key `settings.billing.manage`). Changes to the setting are audited and apply prospectively; in-flight `draft`/`issued` invoices are unaffected until the next payment attempt evaluates the current setting value.
- Q: Which payment methods does the "Allow partial payments = disabled" rule apply to? → A: **Patient-tender methods only** (`cash`, `card`, `bank_transfer`). `insurance_settlement` payments are **exempt** from the partial-payments rule and are always accepted at any positive amount ≤ current balance regardless of the setting, because their amount is determined externally by the insurer and not by clinic collection policy. Refunds (negative payments) are also exempt (already noted in FR-014a).
- Q: Where does the "Allow partial payments" toggle live in the UI? → A: Inside a new **"Billing"** subsection of the existing **organization-level Settings page** introduced in V1-2 (`specs/003-org-branch-management`). The setting is organization-scoped (applies to all branches uniformly); no branch-level override exists in V1-6. The "Billing" subsection is the canonical home for future organization-wide billing toggles.
- Q: How is the invoice balance computed? → A: `balance = subtotal − discount − insurance_covered_amount − sum(payments.amount)`. Insurance coverage is informational at V1 (entered manually during invoice creation as an estimated covered amount); actual claim settlement tracking is V3-2.
- Q: What payment methods are supported in V1? → A: `cash`, `card`, `bank_transfer`, `insurance_settlement`. Each payment records method, amount, optional reference (e.g., transaction id), and recording user. Refunds are recorded as negative payments by a user with `payments.refund`.
- Q: When is an invoice considered `paid`? → A: When `balance` reaches **zero** (after sum of payments, discount, and insurance covered amount). Overpayment (balance < 0) is rejected at payment recording with a clear error.
- Q: What happens to an invoice if its linked visit is later modified or voided? → A: V1-5 does not allow visit void. SOAP corrections do not change invoice items. If a visit must be retroactively undone, the invoice MUST be voided first.
- Q: Can payments be edited or deleted? → A: Payments are **append-only**. Mistaken payments are corrected by recording a refund (negative payment) with reason; the original payment row is never deleted or mutated. All payment events are audited.
- Q: How are concurrent invoice edits and concurrent payment recordings handled? → A: Invoice item edits in `draft` use optimistic concurrency on the invoice `updated_at`; stale edits are rejected with refresh prompt. Payment recording uses a server-side transactional check that recomputes the balance immediately before insert to prevent overpayment from concurrent payments.
- Q: Should invoice creation backend-first principle from V1-5 apply? → A: Yes. When opening an invoice, invoice list, or payment screen, the client MUST consult the backend first before rendering actionable content.
- Q: What is the print format for receipts? → A: A printable receipt view (HTML/PDF-renderable) showing organization header, branch, patient, invoice number, visit date (if linked), itemized lines, subtotal, discount, insurance covered amount, total, paid amount, balance, and per-payment line. Currency is the organization's configured currency (defaults to organization setting; assumes a single currency per organization in V1).
- Q: Are invoice numbers human-readable and unique? → A: Yes — server-assigned per branch using a monotonically increasing branch-scoped sequence with a stable prefix (e.g., `INV-<branch_code>-000123`). Branch code defaults to a short identifier from branch settings.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create an Invoice from a Completed Visit (Priority: P1)

As a receptionist or billing staff member with invoice-create permission, I can create an invoice from a **completed** visit so the clinic captures the financial record for the encounter and the patient can settle the bill.

**Why this priority**: Invoicing is the entry point for all billing; without it, payments, discounts, and receipts have no anchor.

**Independent Test**: Can be fully tested by completing a visit (per V1-5), creating an invoice linked to the visit, adding service line items, issuing the invoice, and verifying it appears in the invoice list with status `issued`, correct patient, branch, and visit linkage.

**Acceptance Scenarios**:

1. **Given** a `completed` visit at the user's branch and a user with `invoices.create`, **When** they initiate invoice creation from the visit, **Then** a `draft` invoice is created linked to the visit, patient, and branch, with no line items yet, and the user is guided to the invoice editor.
2. **Given** a `draft` invoice and `invoices.create`, **When** the user adds one or more line items (description, quantity, unit price, optional tax) and issues the invoice, **Then** status becomes `issued`, the invoice number is assigned, and items become immutable.
3. **Given** a visit that already has an active (non-voided) invoice, **When** the user attempts to create a second invoice for the same visit, **Then** creation is rejected with a clear message that one active invoice per visit is allowed.
4. **Given** a visit that has only voided invoices, **When** the user creates a new invoice from that visit, **Then** creation succeeds.
5. **Given** a user without `invoices.create`, **When** they attempt to create an invoice, **Then** the action is blocked at UI and server layers.
6. **Given** a visit at a branch outside the user's assigned branches, **When** they attempt to create an invoice from it, **Then** access is denied.
7. **Given** a user with `invoices.create`, **When** they attempt to create an invoice without selecting a `completed` visit, **Then** creation is rejected with a clear message that every invoice must be tied to a completed visit (walk-in services must be recorded as a visit first).
8. **Given** a `draft` invoice with no line items, **When** the user attempts to issue, **Then** issue is rejected with a clear message that at least one line item is required.

---

### User Story 2 - Record Partial and Full Payments (Priority: P1)

As reception or billing staff with payment-record permission, I can record one or more payments against an issued invoice using cash, card, bank transfer, or insurance settlement until the balance reaches zero, so the clinic can collect across multiple visits or payment methods. Whether partial payments are accepted depends on the organization-level "Allow partial payments" setting (default disabled).

**Why this priority**: Payment recording is the primary daily billing activity; full and partial payments are common for insurance and large bills.

**Independent Test**: Can be fully tested by (a) with "Allow partial payments" disabled, attempting a partial payment and verifying rejection then paying the full balance; and (b) enabling the setting, recording a partial payment (less than balance), verifying remaining balance, recording a second payment for the exact remaining amount, and verifying invoice status moves to `paid`.

**Acceptance Scenarios**:

1. **Given** an `issued` invoice with non-zero balance, "Allow partial payments" **enabled**, and a user with `payments.record`, **When** they record a payment with method, amount ≤ balance, and optional reference, **Then** the payment is stored, the invoice balance decreases by the payment amount, and the user sees an updated balance and a confirmation.
1a. **Given** an `issued` invoice with non-zero balance, "Allow partial payments" **disabled**, and a user with `payments.record`, **When** they record a payment whose amount is **less than** the current balance, **Then** the payment is rejected with a clear "partial payments are not allowed for this organization; please collect the full balance" error and no payment row is created. **When** the payment amount equals the full current balance, the payment is accepted and the invoice transitions to `paid`.
2. **Given** an `issued` invoice with balance `B`, **When** the user records a payment with amount > balance, **Then** the payment is rejected with a clear "amount exceeds balance" error and no payment row is created.
3. **Given** an `issued` invoice with balance `B` and "Allow partial payments" enabled, **When** payments summing to exactly `B` are recorded, **Then** the invoice status automatically transitions to `paid`.
4. **Given** a `voided` invoice, **When** the user attempts to record a payment, **Then** the action is rejected.
5. **Given** a user without `payments.record`, **When** they attempt to record a payment, **Then** the action is blocked.
6. **Given** two staff members recording payments concurrently against the same invoice, **When** the second payment would cause overpayment, **Then** the second recording is rejected by the server's transactional balance check and the staff member sees the latest balance.
7. **Given** a `paid` invoice, **When** a user with `payments.refund` records a refund (negative payment) with reason, **Then** the refund is stored, balance increases by the refund amount, status moves back to `partially_paid` (or `issued` if balance equals the original due), and the original payment row remains intact.

---

### User Story 3 - Apply a Discount to an Invoice (Priority: P2)

As a user with discount permission, I can apply a percentage or fixed-amount discount **either to one or more individual invoice items (line-level) or to the overall invoice (invoice-level), but not both on the same invoice**, so the clinic can honor item-specific promotions (e.g., a discount on one lab test) OR overall goodwill reductions, staff discounts, or promotional pricing — choosing the scope that best fits the situation under controlled authorization.

**Why this priority**: Discounting is a frequent need but financially sensitive; it MUST be permission-gated and audited but is secondary to base invoice/payment flows.

**Independent Test**: Can be fully tested by (a) creating a `draft` invoice with multiple items, applying a 10% line-level discount to one item, attempting to also apply an invoice-level discount and verifying rejection with a "discount scopes are mutually exclusive" error; (b) clearing the line-level discount, then applying a fixed-amount invoice-level discount and verifying totals update correctly; and (c) issuing the invoice and verifying the chosen scope's discount(s) appear on the printed receipt.

**Acceptance Scenarios**:

1. **Given** a `draft` invoice and a user with `invoices.apply_discount`, **When** they apply a line-level discount (percentage 0–100% or fixed amount ≤ that line's `line_subtotal`) to a specific invoice item, **Then** the line discount is stored on that item, the line's effective amount and the invoice subtotal are recomputed, and the line discount is shown distinctly on the invoice and receipt.
2. **Given** a `draft` invoice with **no existing line-level discounts** and a user with `invoices.apply_discount`, **When** they apply an invoice-level discount (percentage 0–100% or fixed amount ≤ subtotal), **Then** the invoice-level discount is stored, totals are recomputed, and the invoice-level discount is shown distinctly on the invoice and receipt.
2a. **Given** a `draft` invoice that already has at least one line-level discount set, **When** the user attempts to set an invoice-level discount, **Then** the change is rejected with a clear "discount scopes are mutually exclusive — clear all line-level discounts first" error. The same applies in reverse: attempting to set a line-level discount while an invoice-level discount exists MUST be rejected with the symmetric message.
3. **Given** a user without `invoices.apply_discount`, **When** they attempt to apply a line-level or invoice-level discount, **Then** the action is blocked at UI and server layers.
4. **Given** an invalid discount (negative, percentage > 100, line fixed amount > line subtotal, invoice fixed amount > post-line-discount subtotal), **When** the user submits, **Then** the change is rejected with a validation message and the invoice totals are unchanged.
5. **Given** an `issued` invoice, **When** any user attempts to change a line-level or invoice-level discount, **Then** the change is rejected; correction requires void + re-issue by a user with `invoices.void` and `invoices.apply_discount`.
6. **Given** a line-level or invoice-level discount is applied, changed, or removed, **When** the change is persisted, **Then** the audit log records the actor, scope (line or invoice), target line (if applicable), prior and new discount, and rationale (optional note field).

---

### User Story 4 - Record Insurance Coverage on an Invoice (Priority: P2)

As reception or billing staff, I can select an insurance provider from a small catalog and record an estimated covered amount on an invoice so the patient sees the split between insurance-covered and patient-due portions on the receipt.

**Why this priority**: Many clinic visits involve insurance; clear split display avoids billing disputes. Full claim lifecycle and settlement tracking are explicitly V3-2 scope.

**Independent Test**: Can be fully tested by creating an invoice, selecting an insurance provider, entering a covered amount, verifying the patient-due balance reflects the split, recording a patient payment for the remaining amount, and verifying the receipt shows insurance and patient amounts separately.

**Acceptance Scenarios**:

1. **Given** a `draft` invoice and an active insurance provider, **When** the user selects the provider and enters a covered amount (≥ 0, ≤ subtotal − discount), **Then** the value is stored, the patient-due balance is recomputed, and the receipt shows the split.
2. **Given** an `issued` invoice, **When** the user attempts to change insurance coverage, **Then** the change is rejected; correction requires void + re-issue.
3. **Given** an invalid insurance amount (negative or greater than subtotal − discount), **When** submitted, **Then** the value is rejected with validation.
4. **Given** an organization with no insurance providers configured, **When** the user creates an invoice, **Then** the insurance selector shows an empty state and invoices may be created without insurance.
5. **Given** an administrator with insurance management permission, **When** they create, edit (rename), or deactivate insurance providers, **Then** changes persist and only active providers appear in selectors.

---

### User Story 5 - List, Search, and View Invoices (Priority: P2)

As reception, billing staff, or administrators, I can search and filter invoices for the current branch (or assigned branches) by patient, invoice number, status, date range, or visit, so I can answer patient questions and reconcile daily billing.

**Why this priority**: Listing is the primary lookup surface for daily reconciliation; depends on invoice creation but unblocks payment and reporting workflows.

**Independent Test**: Can be fully tested by creating several invoices with different statuses and dates, searching by patient name, filtering by status `issued`, narrowing by date range, and verifying results and pagination.

**Acceptance Scenarios**:

1. **Given** invoices exist at the user's assigned branches, **When** the user opens the invoice list, **Then** the list shows invoice number, patient name, date, status, total, paid amount, and balance, sorted by date descending by default, with pagination.
2. **Given** the user filters by status `paid`, **When** results render, **Then** only `paid` invoices for branches in scope are shown.
3. **Given** the user searches by patient name fragment, **When** results render, **Then** matching invoices across the user's branch scope are shown.
4. **Given** a user with `patients.view` but without `invoices.view`, **When** they open the invoice list, **Then** access is blocked.
5. **Given** a user opens an invoice detail, **When** the detail loads, **Then** the client performs a backend-first fetch and shows the latest items, discount, insurance, payments, and computed balance.
6. **Given** invoices at multiple branches in the user's scope, **When** they filter by a specific branch, **Then** only that branch's invoices are shown.

---

### User Story 6 - Void an Invoice (Priority: P3)

As an administrator or user with void permission, I can void an `issued` invoice when it was created in error, so the financial record reflects reality and a corrected invoice can be created.

**Why this priority**: Void is a corrective workflow used less often than core flows but essential for accurate books.

**Independent Test**: Can be fully tested by issuing an invoice, voiding it with a reason, verifying status changes to `voided`, verifying it no longer counts toward outstanding balances, and verifying a new invoice can be created for the same visit.

**Acceptance Scenarios**:

1. **Given** an `issued` or `partially_paid` invoice and a user with `invoices.void`, **When** they void with a mandatory reason, **Then** the invoice status becomes `voided`, balance becomes 0 for reporting, and the invoice is locked from further mutation.
2. **Given** a `paid` invoice, **When** the user attempts to void, **Then** the operation is rejected; full refunds must be recorded first to bring the invoice back to `partially_paid` or `issued` before void is allowed. (V1 rule for simplicity.)
3. **Given** a `voided` invoice, **When** anyone attempts further mutation (items, discount, insurance, payment), **Then** the action is rejected with a clear "invoice is voided" message.
4. **Given** a user without `invoices.void`, **When** they attempt to void, **Then** the action is blocked at UI and server layers.
5. **Given** an invoice is voided, **When** an authorized user views invoice history for the visit or patient, **Then** the voided invoice remains visible with a clear "voided" indicator and reason, never silently hidden.

---

### User Story 7 - Print an Invoice Receipt (Priority: P3)

As reception or billing staff, I can open a printable receipt view of an invoice so the patient receives a clear, formatted record of charges, discounts, insurance split, payments, and balance.

**Why this priority**: Printed receipts are a daily expectation but depend on stable invoice and payment data; format polish is iterative.

**Independent Test**: Can be fully tested by issuing an invoice with items, discount, insurance, and at least one payment, opening the print preview, and verifying all fields render correctly and the print dialog opens via the standard system flow.

**Acceptance Scenarios**:

1. **Given** an `issued`, `partially_paid`, or `paid` invoice and a user with `invoices.view`, **When** they open the print preview, **Then** the preview renders organization header, branch, patient, invoice number, dates, itemized lines with quantities and unit prices, subtotal, discount, insurance covered amount, total, payments list (date, method, amount), and balance.
2. **Given** a `draft` invoice, **When** the user opens print preview, **Then** the preview shows a "DRAFT — NOT FOR PATIENT" watermark and is clearly distinguished from issued receipts.
3. **Given** a `voided` invoice, **When** the user opens print preview, **Then** the preview shows a "VOIDED" watermark with the void reason.
4. **Given** the user invokes print, **When** the system print dialog opens, **Then** the document prints or saves as a PDF using the operating system's native print pipeline.

---

### User Story 8 - Configure "Allow Partial Payments" Setting (Priority: P2)

As an owner or administrator, I can toggle an organization-level **"Allow partial payments"** setting in the Settings panel so the clinic can decide whether reception/billing staff may accept less-than-full payments against an invoice. The setting defaults to **disabled** so new organizations require full payment by default; only owners and administrators can change it.

**Why this priority**: This setting governs the daily payment flow (User Story 2) and prevents accidental partial collections in clinics that operate on a pay-in-full policy.

**Independent Test**: Can be fully tested by logging in as an owner/administrator, opening the billing Settings panel, observing the default-disabled state, toggling the setting on, attempting and successfully recording a partial payment from a receptionist account, toggling the setting back off, and verifying the receptionist's next partial payment attempt is rejected. Also verifying a receptionist account cannot see/change the toggle.

**Acceptance Scenarios**:

1. **Given** a freshly provisioned organization, **When** an owner or administrator opens the billing Settings panel, **Then** the "Allow partial payments" toggle is visible and is **off (disabled)** by default.
2. **Given** an owner or administrator on the Settings panel, **When** they toggle "Allow partial payments" on (or off) and save, **Then** the change is persisted at the organization scope, takes effect immediately for subsequent payment attempts across all branches, and is recorded in the audit log with actor, prior value, and new value.
3. **Given** a user whose role is `doctor`, `receptionist`, or `lab_staff`, **When** they open the Settings panel, **Then** the "Allow partial payments" control is either hidden or rendered in read-only mode and any attempt to mutate it server-side is rejected with a permission-denied error.
4. **Given** "Allow partial payments" is disabled, **When** any user with `payments.record` attempts a payment whose amount is less than the current invoice balance, **Then** the payment is rejected server-side regardless of UI state (defense in depth).
5. **Given** "Allow partial payments" is enabled, **When** any user with `payments.record` attempts a payment whose amount is between 0 (exclusive) and the current balance (inclusive), **Then** the payment is accepted (subject to all other validation rules).

---

### Edge Cases

- Attempt to create an invoice from a non-completed visit (e.g., `in_progress`): rejected with clear messaging that the visit must be completed first.
- Attempt to create a second active invoice for a visit that already has one: rejected.
- Attempt to issue a `draft` invoice with zero line items: rejected.
- Attempt to apply a line-level discount that exceeds the line subtotal, or an invoice-level discount that exceeds the post-line-discount subtotal: rejected with validation.
- Attempt to record a payment exceeding remaining balance: rejected.
- Attempt to record a payment less than the remaining balance while "Allow partial payments" is disabled: rejected with a clear "partial payments not allowed" message; user must collect the full balance in one payment.
- Owner/administrator changes "Allow partial payments" mid-collection: the new value takes effect on the next payment attempt only; already-recorded payments are not affected.
- Non-admin/non-owner user attempts to mutate "Allow partial payments" via direct API call: rejected by server-side permission check.
- Concurrent payment recording from two stations causing overpayment: server-side transactional balance check rejects the second one.
- Concurrent invoice item edits in `draft`: optimistic concurrency on invoice `updated_at`; stale edits rejected with refresh prompt.
- Insurance provider deactivated after invoice issued: the invoice retains the provider reference for history; the deactivated provider does not appear for new invoices.
- Currency mismatch: V1 assumes a single organization currency. Multi-currency support is explicitly out of scope.
- Visit voided or modified after invoice created: V1-5 does not allow visit void; SOAP edits do not affect invoice items. Any retroactive visit undo requires invoice void first as an operational rule.
- Printing while offline: print preview uses local rendering; OS print pipeline behavior is outside this feature's scope.
- Refund recorded that brings the balance back above zero: invoice transitions from `paid` → `partially_paid`; further payments are accepted.
- Receptionist with `invoices.create` but without `payments.record`: may create invoices but cannot record payments.
- Cross-organization invoice access: always denied in verification scenarios.
- Subscription state does not block invoice creation or payment recording (clinical and billing operations MUST remain functional locally).
- AI services are not part of this feature; AI unavailability MUST not block any billing workflow.
- Permission grant changes follow V1-2 rules: client cache updates on auth-context reload; server enforces current grants immediately.
- Backend-first fetch principle from V1-5: invoice list, invoice detail, and payment screens MUST consult the backend before rendering actionable content.
- Advanced billing flows — full insurance claim lifecycle, claim reference numbers, automated overdue detection, dunning, revenue analytics dashboards — are explicitly out of scope for V1-6 and owned by V3-2 and V3-1.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST introduce invoice records with fields aligned to architecture: `id`, `branch_id`, `patient_id`, **required (NOT NULL) `visit_id`**, `invoice_number`, `status`, `subtotal`, `discount_amount`, `discount_kind` (`percentage` | `fixed`), `discount_value`, `insurance_provider_id` (nullable), `insurance_covered_amount`, `currency`, `issued_at`, `void_reason` (nullable), `voided_at` (nullable), `voided_by` (nullable), plus standard audit columns.
- **FR-002**: The system MUST introduce invoice item records with fields: `id`, `invoice_id`, `description`, `quantity`, `unit_price`, `line_subtotal` (pre-discount: `quantity * unit_price`), `line_discount_kind` (nullable: `percentage` | `fixed`), `line_discount_value` (nullable), `line_discount_amount` (resolved amount at scale 2), `line_total` (`line_subtotal − line_discount_amount`), plus standard audit columns. Line-level tax is out of scope for V1.
- **FR-003**: The system MUST introduce payment records with fields: `id`, `invoice_id`, `branch_id`, `method` (`cash` | `card` | `bank_transfer` | `insurance_settlement`), `amount` (signed; negative for refunds), `reference` (nullable), `note` (nullable), `recorded_by`, `recorded_at`, plus standard audit columns. Payment rows MUST be append-only (no UPDATE/DELETE on existing payment rows after creation).
- **FR-004**: The system MUST introduce insurance provider records with fields: `id`, `organization_id`, `name`, `contact_info` (nullable), `is_active`, plus standard audit columns. Insurance providers are organization-scoped, not branch-scoped, and reusable across branches.
- **FR-005**: The system MUST enforce **one active (non-voided, non-soft-deleted) invoice per visit**; duplicate active invoice creation for the same visit MUST be rejected. Multiple voided or discarded invoices for the same visit are allowed historically.
- **FR-006**: The system MUST require every invoice to be linked to a `completed` visit at the user's branch. Invoice creation without a `visit_id`, or against a visit not in `completed` status, MUST be rejected. `patient_id` and `branch_id` MUST be derived server-side from the linked visit (the client does not supply them independently). Visit-less ("ad-hoc") invoicing is NOT supported in V1-6.
- **FR-007**: The system MUST set initial invoice status to `draft` on creation and support transitions: `draft` → `issued` (issue), `issued` → `partially_paid` (first valid payment with amount < balance), `issued`/`partially_paid` → `paid` (balance reaches zero), `issued`/`partially_paid` → `voided` (with reason; `paid` cannot be voided directly).
- **FR-008**: The system MUST assign `invoice_number` server-side at issue time using a branch-scoped monotonically increasing sequence with the stable prefix `INV-<branch_code>-` followed by a zero-padded sequence value (e.g., `INV-MAIN-000123`). `<branch_code>` MUST be sourced from the existing `branches.code` field defined in V1-2 (`specs/003-org-branch-management`). If the branch's `code` is NULL at issue time, the issue operation MUST be rejected with a clear error instructing an administrator to set the branch code in branch settings before issuing invoices at that branch. V1-6 introduces no schema changes to `branches`.
- **FR-009**: The system MUST allow invoice item create/update/delete only while invoice status is `draft`. Once issued, items MUST be immutable; corrections require void + re-issue.
- **FR-009a**: The system MUST allow a user with `invoices.create` at the invoice's branch to **soft-delete a `draft` invoice** (discard). Discarding a draft MUST set `deleted_at` and the actor, audit the event, and release the linked visit (if any) so a new invoice may be created. Discard MUST be rejected on any non-`draft` status (use void instead). Soft-deleted drafts MUST be excluded from operational queries and counted as "no active invoice" for the one-active-invoice-per-visit constraint.
- **FR-010**: The system MUST support **two discount scopes**, both gated by `invoices.apply_discount` and both mutable only while invoice status is `draft`. The two scopes MUST be **mutually exclusive on a given invoice** — an invoice MUST NOT simultaneously carry any line-level discount and an invoice-level discount.
  - **Line-level discount**: applied to one or more individual invoice items; kind is `percentage` (0–100) or `fixed` (0 ≤ amount ≤ that line's pre-discount `line_subtotal`); persisted on the invoice item.
  - **Invoice-level discount**: applied to the overall invoice; kind is `percentage` (0–100) or `fixed` (0 ≤ amount ≤ invoice subtotal); persisted on the invoice.
  The server MUST reject any mutation that would result in both scopes being non-zero on the same invoice (i.e., setting an invoice-level discount while any item has a non-zero line-level discount, or setting a line-level discount on any item while the invoice has a non-zero invoice-level discount). Switching scopes requires explicitly clearing the existing scope first. The active scope MUST be displayed and printed distinctly on the receipt.
- **FR-011**: The system MUST allow insurance provider selection and `insurance_covered_amount` change only while invoice status is `draft`. Coverage amount MUST satisfy `0 ≤ insurance_covered_amount ≤ (subtotal − discount_amount)`.
- **FR-012**: The system MUST compute and persist per-line `line_discount_amount` and `line_total` (from `line_discount_kind`/`line_discount_value`), `subtotal = sum(invoice_items.line_total)`, and invoice-level `discount_amount` (resolved from `discount_kind`/`discount_value`) at every item or discount change while in `draft`, and freeze all values at issue time. Because the two discount scopes are mutually exclusive (FR-010), at most one of `sum(line_discount_amount)` and invoice-level `discount_amount` is non-zero for any given invoice.
- **FR-013**: The system MUST compute invoice balance as `balance = subtotal − discount_amount − insurance_covered_amount − sum(payments.amount)` where `subtotal` already reflects line-level discounts (refunds contribute negatively to `sum(payments.amount)`, increasing balance). Balance MUST be the source of truth from server computation; clients MUST NOT rely on locally derived balances for write decisions.
- **FR-014**: The system MUST reject any payment whose amount would cause invoice balance to become negative (overpayment). The check MUST be enforced server-side inside the same transaction that inserts the payment to prevent races.
- **FR-014a**: The system MUST enforce the organization-level **"Allow partial payments"** setting at payment recording time, server-side, inside the same transaction that inserts the payment. The rule applies **only to patient-tender methods** (`cash`, `card`, `bank_transfer`); `insurance_settlement` payments and refunds (negative payments) are **exempt** and always accepted at any otherwise-valid amount regardless of the setting. When the setting is **disabled**, any positive patient-tender payment whose amount is strictly less than the current invoice balance MUST be rejected with a clear "partial payments are not allowed" error; only a positive patient-tender payment whose amount equals the full current balance is accepted. When the setting is **enabled**, all otherwise-valid positive payments ≤ balance are accepted across all methods. The setting MUST default to **disabled** on organization creation.
- **FR-015**: The system MUST automatically transition invoice status to `paid` when a payment recording brings balance to exactly zero, and back to `partially_paid` (or `issued` if no non-refunded payments remain) when a refund increases balance above zero.
- **FR-016**: The system MUST require permission `payments.refund` to record a payment with negative amount; refund recording MUST require a non-empty `note` (reason).
- **FR-017**: The system MUST allow void only on `issued` or `partially_paid` invoices, MUST require a non-empty `void_reason`, and MUST require permission `invoices.void`. After void, the invoice MUST be locked from all mutations except read.
- **FR-018**: The system MUST enforce branch-scoped isolation for invoice, invoice item, and payment reads and writes via data-layer policies limited to the user's assigned branches within their organization.
- **FR-019**: The system MUST enforce organization-scoped isolation for insurance provider reads and writes.
- **FR-020**: The system MUST enforce the following permission keys at UI and server layers:
  - `invoices.view` — required to list and read invoices.
  - `invoices.create` — required to create invoices (always from a `completed` visit) and to mutate items/insurance while in `draft`, and to discard a `draft` invoice.
  - `invoices.apply_discount` — required to set or change the invoice discount.
  - `invoices.void` — required to void an invoice.
  - `payments.record` — required to record positive payments.
  - `payments.refund` — required to record refunds (negative payments).
  - `insurance.manage` — required to create, edit, or deactivate insurance providers.
  - `settings.billing.manage` — required to view and mutate organization-level billing settings, including "Allow partial payments". This key MUST be restricted to the `owner` and `administrator` roles and MUST NOT be grantable to other roles through the role/permission management UI.
- **FR-021**: V1-6 MUST seed default role mappings against the existing V1-1 five-role catalog (owner, administrator, doctor, receptionist, lab_staff) without introducing any new role:
  - `owner` and `administrator`: all eight keys (`invoices.view`, `invoices.create`, `invoices.apply_discount`, `invoices.void`, `payments.record`, `payments.refund`, `insurance.manage`, `settings.billing.manage`).
  - `receptionist`: `invoices.view`, `invoices.create`, `payments.record` only.
  - `doctor` and `lab_staff`: no billing keys.
  - Sensitive keys (`invoices.apply_discount`, `invoices.void`, `payments.refund`, `insurance.manage`, `settings.billing.manage`) MUST NOT be granted to `receptionist`, `doctor`, or `lab_staff` by default. `settings.billing.manage` is non-delegable and MUST remain restricted to `owner`/`administrator`.
- **FR-022**: The system MUST implement invoice creation, item mutation, discount apply, insurance set, issue, void, payment recording, and refund recording through secured server-side functions with permission, branch, validation, and balance checks — not unguarded direct client writes.
- **FR-023**: The system MUST record invoice create, issue, item mutation, discount apply/change, insurance set/change, void, payment record, and refund record events in the audit log with actor, action, target, and meaningful payload (e.g., amount, prior balance, new balance, reason).
- **FR-024**: The system MUST create database indexes supporting invoice lookups by branch/date, by patient, by visit, by invoice number (unique per branch), and payment lookups by invoice.
- **FR-025**: The system MUST include backend verification utilities that validate: one-active-invoice-per-visit constraint, branch isolation, cross-organization denial, discount permission enforcement, overpayment rejection, refund-permission enforcement, void-state lock, and invoice number monotonicity per branch.
- **FR-026**: The system MUST derive requirements from the architecture documents listed under Required Architecture Docs and treat `specs/operations/billing.spec.md` as an external reference until authored.
- **FR-027**: The system MUST NOT deliver: full insurance claim lifecycle and settlement tracking, automated overdue detection or dunning, revenue analytics dashboards, multi-currency invoices, line-level taxes/discounts, prescription printing, shift management, or AI-assisted billing as part of this feature.
- **FR-028**: The system MUST NOT auto-create invoices when visits are completed; invoice creation remains an explicit user action in V1-6.
- **FR-029**: The system MUST integrate with visits (visit `completed` is the prerequisite for visit-linked invoices) and with patients/branches/organizations/staff from prior features; no behavior changes are introduced in those domains beyond surfacing invoice context.
- **FR-030**: When opening invoice list, invoice detail, or payment screens, the client MUST perform a backend-first fetch for latest persisted data before rendering actionable content; cached/local state MAY be shown only as a transient loading placeholder and MUST be reconciled with backend response.
- **FR-031**: Invoice item edits while in `draft` MUST use optimistic concurrency on the invoice `updated_at`; if the invoice changed since load, save MUST be rejected with a stale-data error and the client MUST prompt refresh before retry.
- **FR-032**: The system MUST provide a printable receipt view derived from current invoice state, including organization header, branch, patient, invoice number, visit date (if linked), itemized lines (each showing pre-discount line subtotal, any line-level discount, and post-line-discount line total), invoice subtotal (after line discounts), invoice-level discount line (if any), insurance covered line (if any), total, list of payments with method and date, and current balance. `draft` previews MUST show a "DRAFT — NOT FOR PATIENT" watermark; `voided` previews MUST show a "VOIDED" watermark with reason.
- **FR-033**: The system MUST introduce an **organization billing settings** record (one per organization) with at minimum the field `allow_partial_payments` (boolean, default `false`), plus standard audit columns. The record MUST be auto-provisioned at organization creation with `allow_partial_payments = false`. Reads MUST be allowed for any user with `invoices.view` or `payments.record` so the UI can render correct payment affordances; writes MUST require `settings.billing.manage` and MUST be audited (actor, prior value, new value, timestamp). The setting is organization-scoped (applies to all branches of the organization).

### Non-Functional Requirements

- **NFR-001**: Invoice and payment screens must use plain language suitable for reception and billing staff; financial amounts must always be displayed with the organization's configured currency symbol.
- **NFR-002**: Payment recording must feel instantaneous under normal local clinic network conditions (perceived interactive response).
- **NFR-003**: Invoice list with up to 5,000 invoices per branch must remain navigable with pagination or lazy loading.
- **NFR-004**: Receipt print preview must render within 2 seconds for invoices up to 100 line items under normal conditions.
- **NFR-005**: Permission and scope checks must follow defense in depth: client gating, server function validation, and data-layer isolation.
- **NFR-006**: Save and recording failures due to connectivity or validation errors must not leave the user believing the change was saved.
- **NFR-007**: All monetary values MUST be stored as exact decimals with a fixed scale of 2 (two fractional digits) — no floating-point types — across `subtotal`, `discount_amount`, `insurance_covered_amount`, invoice item `unit_price` and `line_subtotal`, and payment `amount`. Percentage-discount intermediate math MUST apply banker's rounding (round-half-to-even) before persisting `discount_amount` at scale 2. Server-computed balance MUST also be returned at scale 2.

### Required Architecture Docs

- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Billing`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`, `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

### External Spec Dependencies

- `specs/operations/billing.spec.md` is referenced by the roadmap but is not yet present. This specification captures invoice and payment expectations for V1-6 until that shared operations spec is authored.
- `specs/006-visit-medical-records` is a hard prerequisite: visit `completed` status drives visit-linked invoice creation.
- `specs/004-patient-management` is a hard prerequisite: patient registry must exist for invoice patient linkage.
- `specs/003-org-branch-management` and `specs/002-auth-rbac` are hard prerequisites: active branch, staff identities, permissions, and session management must exist.

### Data Model

- **Invoice**: Branch-scoped financial record **required to be linked to a completed visit** (one active invoice per visit); carries subtotal, discount, insurance coverage, status, void metadata, and audit fields.
- **Invoice Item**: Itemized service line linked to an invoice; carries optional line-level discount (kind, value, resolved amount, line total); mutable only while invoice is `draft`.
- **Organization Billing Settings**: One-per-organization configuration record holding billing toggles such as `allow_partial_payments` (default `false`); managed by owners/administrators.
- **Payment**: Append-only record of money received (or refunded) against an invoice; carries method, amount, reference, recorder identity.
- **Insurance Provider**: Organization-scoped reference catalog used to label insurance coverage on invoices.
- **Visit** (existing): Clinical encounter; `completed` visits become eligible for invoice creation.
- **Patient** (existing): Subject of billing; invoices list and patient profile billing tab anchor on patient identity.
- **Branch** (existing): Scope unit for invoice and payment isolation and for invoice number sequence.

No new core tenancy tables are required beyond invoices, invoice_items, payments, insurance_providers, organization_billing_settings, and their policies, indexes, and functions.

### RPC Functions

Exact names follow architecture; required capabilities:

- **Create invoice**: Validate `invoices.create`, `visit_id` provided, visit exists and is `completed`, visit's branch is in the user's scope, no existing active invoice for the visit; derive `patient_id` and `branch_id` from the linked visit; create invoice with `draft` status; audit log.
- **Add/update/remove invoice item**: Validate `invoices.create`, invoice in `draft`, branch scope; optimistic concurrency on invoice `updated_at`; recompute subtotal; audit log.
- **Discard draft invoice**: Validate `invoices.create`, invoice in `draft`, branch scope; soft-delete invoice and its items; audit log. Linked visit becomes eligible for a new invoice.
- **Apply line-level discount**: Validate `invoices.apply_discount`, invoice in `draft`, branch scope, target item belongs to invoice; validate discount kind/value against the line subtotal; persist on invoice item; recompute line total, invoice subtotal, and totals; audit log with line target.
- **Apply invoice-level discount**: Validate `invoices.apply_discount`, invoice in `draft`, branch scope; validate discount kind/value against post-line-discount subtotal; persist on invoice; recompute totals; audit log.
- **Get / update organization billing settings**: Read allowed for any user with `invoices.view` or `payments.record`; update (e.g., toggle `allow_partial_payments`) requires `settings.billing.manage`; audit log with prior/new values.
- **Set insurance coverage**: Validate `invoices.create`, invoice in `draft`, branch scope; validate provider is active and organization-scoped; validate covered amount range; audit log.
- **Issue invoice**: Validate `invoices.create`, invoice in `draft`, at least one item, branch has non-NULL `code`; assign invoice number from branch sequence using `branches.code` as prefix; freeze subtotal and discount; set status `issued`; audit log.
- **Record payment**: Validate `payments.record` (or `payments.refund` for negative amounts), invoice in `issued` or `partially_paid` (refunds also allowed on `paid`), branch scope; transactionally recompute balance and reject overpayment; **read the organization's `allow_partial_payments` setting and reject any positive payment whose amount is less than the current balance when the setting is disabled**; insert payment row; transition status as needed; audit log.
- **Void invoice**: Validate `invoices.void`, invoice in `issued` or `partially_paid`, non-empty reason, branch scope; set status `voided`, record reason and actor; lock further mutations; audit log.
- **Get invoice balance**: Server-computed balance and breakdown; required for client display and decisions; reads enforce branch scope.
- **Insurance provider mutations**: Validate `insurance.manage`, organization scope; create/edit/deactivate; audit log.

List/query capabilities for invoice list (with filters), invoice detail (with items, payments, insurance), patient invoice history, and visit-linked invoice lookup are required (direct read via policies or list function per planning).

### Invoice Status Rules

| From             | Allowed to                            | Trigger / Permission                                |
| ---------------- | ------------------------------------- | --------------------------------------------------- |
| `draft`          | `issued`                              | Issue action, ≥1 item, `invoices.create`            |
| `draft`          | (deletable as draft, planning detail) | Cancel-draft action by creator/`invoices.create`    |
| `issued`         | `partially_paid`                      | First valid payment with amount < balance           |
| `issued`         | `paid`                                | Payment(s) bring balance to zero                    |
| `issued`         | `voided`                              | Void action with reason, `invoices.void`            |
| `partially_paid` | `paid`                                | Payment(s) bring balance to zero                    |
| `partially_paid` | `voided`                              | Void action with reason, `invoices.void`            |
| `paid`           | `partially_paid` / `issued`           | Refund brings balance above zero, `payments.refund` |
| `paid`           | `voided`                              | Not allowed directly; refund first, then void       |
| `voided`         | (none)                                | Locked; new invoice may be created for the visit    |

### Appointment / Visit Integration Rules

| Event                                      | Visit status required | Invoice action                            |
| ------------------------------------------ | --------------------- | ----------------------------------------- |
| Create invoice from completed visit        | `completed`           | New `draft` invoice with `visit_id` set   |
| Attempt invoice with no `visit_id`         | n/a                   | Rejected (ad-hoc invoicing not supported) |
| Attempt invoice from non-`completed` visit | any other             | Rejected                                  |
| Existing voided/discarded invoice on visit | `completed`           | New invoice creation allowed              |
| Existing active invoice on visit           | any                   | Second active invoice creation rejected   |

V1-6 introduces no changes to appointment or visit state machines beyond using `completed` visits as a creation prerequisite.

### RLS Policies

Policies on billing domain tables MUST enforce:

- Authenticated access only.
- Branch isolation for invoices, invoice items, and payments: `branch_id` must be in the user's JWT `branch_ids` within their organization.
- Organization isolation for insurance providers and organization billing settings: `organization_id` must match the user's JWT `organization_id`. Updates to organization billing settings require `settings.billing.manage`.
- Exclusion of soft-deleted rows from normal operational queries (invoices and items use soft delete; payments are append-only, no soft delete).
- No cross-tenant reads or writes in verification scenarios.
- Direct INSERT/UPDATE/DELETE on domain tables denied; mutations via secured functions only. Payment rows have no UPDATE/DELETE path at all (refunds are new rows with negative amounts).

### API Contracts

- Create invoice from a `completed` visit (visit-linked only; ad-hoc not supported).
- Add / update / remove invoice item (draft only).
- Apply or change line-level discount on a specific invoice item (draft only, permission-gated).
- Apply or change invoice-level discount (draft only, permission-gated).
- Get / update organization billing settings (`allow_partial_payments`); update permission-gated to `owner`/`administrator` via `settings.billing.manage`.
- Set or change insurance provider and covered amount (draft only).
- Issue invoice.
- Record payment (positive) and record refund (negative; permission-gated).
- Void invoice (permission-gated, requires reason).
- List invoices with filters (status, branch, patient, date range, search by invoice number).
- Get invoice detail (items, discount, insurance, payments, balance).
- List patient invoice history.
- Get invoice receipt view payload (for print preview rendering).
- Insurance provider list / create / update / deactivate (permission-gated for mutations).

Multi-currency, claim submission, dunning, and analytics APIs remain out of scope.

### UI States

- **Invoice Create (from completed visit) — Visit eligible / Visit ineligible (not `completed`) / Visit already has active invoice / No `visit_id` supplied (rejected) / Permission Denied / Error**
- **Invoice Editor (`draft`) — Empty (no items) / Items present / Discount applied / Insurance set / Issuing / Stale conflict (refresh prompt) / Validation Error / Permission Denied**
- **Invoice Detail (`issued` / `partially_paid` / `paid` / `voided`) — Loading / Loaded with payments list / Print preview / Permission Denied / Error**
- **Payment Recording — Idle / Recording / Success / Overpayment Rejected / Permission Denied / Error**
- **Refund Recording — Idle / Recording / Success / Permission Denied (no `payments.refund`) / Error**
- **Discount Apply — Scope selector (Line vs Invoice) / Idle / Applying / Validation Error / Permission Denied**
- **Billing Settings (organization-level Settings page → "Billing" subsection, from V1-2) — Loading / Loaded (toggle visible & editable for owner/administrator) / Read-only (other roles) / Saving / Saved / Permission Denied / Error**
- **Insurance Set — Provider selector / Covered amount input / Empty providers state / Validation Error / Permission Denied**
- **Void Invoice — Reason prompt / Voiding / Success / Permission Denied / Error**
- **Invoice List — Loading / Results / Empty / Filter active / Pagination / Permission Denied / Error**
- **Insurance Provider Management — List / Create / Edit / Deactivate / Permission Denied**
- **Receipt Print Preview — Draft watermark / Issued layout / Voided watermark / Loading / Error**

Navigation integrates with the visit screen (create invoice action on `completed` visits), patient profile (billing tab showing invoice history), and active branch from V1-2.

### Validation Rules

- Invoice creation requires a `completed` visit at the user's branch; `patient_id` and `branch_id` are derived from the linked visit and may not be supplied independently.
- Issue requires at least one invoice item with `quantity > 0` and `unit_price ≥ 0`.
- Line-level discount percentage MUST be in `[0, 100]`; line-level fixed amount MUST satisfy `0 ≤ amount ≤ line_subtotal` for that item.
- Invoice-level discount percentage MUST be in `[0, 100]`; invoice-level fixed amount MUST satisfy `0 ≤ amount ≤ subtotal`.
- The two discount scopes MUST NOT coexist on the same invoice: setting any line-level discount on an invoice that already has a non-zero invoice-level discount (and vice versa) MUST be rejected.
- Payment amount MUST respect the organization's `allow_partial_payments` setting at recording time (see FR-014a).
- Insurance covered amount MUST satisfy `0 ≤ amount ≤ (subtotal − discount_amount)`.
- Payment amount MUST be non-zero; positive payments MUST satisfy `amount ≤ current_balance`; refund amounts (negative) MUST not exceed the absolute net paid amount (cannot refund more than received).
- Void requires non-empty reason; only `issued` and `partially_paid` are voidable.
- Invoice numbers are server-assigned, branch-unique, and monotonically increasing per branch.
- Receipt print is allowed in any non-purged status; draft and voided receipts MUST display their respective watermarks.

### AI Hooks

This feature introduces no AI-assisted workflow. Billing remains fully manual in V1. Billing agent (V2) and analytics agent (V3) must not be required for any V1-6 acceptance scenario; when AI is added later, all AI-generated billing actions require staff approval per product principles.

### Audit Requirements

- Invoice create, issue, item create/update/delete, discount apply/change, insurance set/change, discard draft (soft-delete), and void MUST write audit log entries with prior and new key values.
- Payment record and refund record MUST write audit log entries with method, amount, prior balance, new balance, and reason (for refunds).
- Insurance provider create, update, and deactivate MUST write audit log entries.
- Invoice and payment reads are not individually audited unless architecture mandates access logging later.

### Acceptance Criteria

1. User with `invoices.create` can create an invoice from a `completed` visit; visits in non-`completed` status, duplicate active invoices for a visit, cross-branch attempts, and creation attempts without a `visit_id` are all rejected.
2. Every invoice carries a non-null `visit_id`; ad-hoc (visit-less) invoice creation is rejected at UI and server layers.
3. User can add, update, and remove invoice items while in `draft`; once issued, item mutations are rejected.
4. Line-level and invoice-level discounts can be applied only by users with `invoices.apply_discount`, only while in `draft`, with valid kind/value ranges (line discount bounded by its line subtotal, invoice discount bounded by post-line-discount subtotal); audit captures changes including scope and target line.
4a. The "Allow partial payments" setting is visible and editable only to owners/administrators; it defaults to disabled; when disabled, partial payments are rejected server-side regardless of UI.
5. Insurance provider and covered amount can be set only while in `draft`, with valid ranges; deactivated providers do not appear in selection.
6. Issuing assigns a unique, monotonically increasing, branch-scoped invoice number and freezes items and totals.
7. Users with `payments.record` can record valid payments; overpayment is rejected by a server-side transactional balance check; status transitions to `partially_paid` and `paid` happen automatically.
8. Users with `payments.refund` can record refunds with a mandatory reason; status moves back from `paid` to `partially_paid` or `issued` as appropriate; original payment rows remain intact.
9. Users with `invoices.void` can void `issued` or `partially_paid` invoices with a reason; `paid` invoices require full refund before void; voided invoices reject further mutation.
10. Invoice list supports filtering by status, branch, patient, date range, and invoice number; pagination works; backend-first fetch is observed for list, detail, and payment screens.
11. Receipt print preview renders correctly for `draft` (watermark), `issued`, `partially_paid`, `paid`, and `voided` (watermark + reason) states with all required fields.
12. Backend verification utilities demonstrate one-active-invoice-per-visit, branch isolation, cross-organization denial, discount permission enforcement, overpayment rejection, refund permission enforcement, void state lock, and invoice number monotonicity per branch.
13. No advanced insurance claim lifecycle, automated overdue detection, dunning, revenue dashboards, multi-currency support, line-level taxes, or AI workflows are required to pass this feature.
14. Invoice list, invoice detail, and payment screens always start from a backend-first fetch.

### Test Cases

1. Create invoice from `completed` visit; verify linkage, branch, and `draft` status.
2. Attempt invoice from `in_progress` visit; verify rejection with clear message.
3. Attempt second active invoice for the same visit; verify rejection.
4. Attempt invoice creation with no `visit_id`; verify rejection with the "every invoice must be tied to a completed visit" message.
5. Add multiple items, edit one, remove one in `draft`; verify subtotal recomputes.
6. Apply 10% **line-level** discount to one item and a fixed-amount **invoice-level** discount as user with permission; verify per-line and invoice totals and audit (with scope/target) for both; attempt apply without permission; verify denial.
7. Apply line-level discount exceeding the line subtotal, and invoice-level discount exceeding the post-line-discount subtotal; verify both are rejected.
7a. As `owner`/`administrator`, toggle "Allow partial payments" on/off in Settings; verify persistence, audit entry, and that the change applies to the next payment attempt. As `receptionist`, verify the toggle is hidden/read-only and a direct mutate attempt is rejected.
7b. With "Allow partial payments" disabled, attempt a payment less than balance; verify rejection. Pay the full balance in one transaction; verify `paid`. Enable the setting; attempt the same partial payment on another invoice; verify acceptance.
8. Select insurance provider and enter covered amount; verify patient-due reflects split; deactivate provider afterward; verify still visible on this invoice but not in new-invoice selector.
9. Issue invoice; verify invoice number format and monotonicity; verify items become immutable.
10. Record partial payment less than balance; verify balance decrease and status `partially_paid`.
11. Record final payment equal to balance; verify status `paid`.
12. Attempt payment exceeding balance; verify rejection.
13. Simulate concurrent payments from two stations totaling more than balance; verify second is rejected by server transactional balance check.
14. Record refund as user with `payments.refund`; verify status transitions back appropriately; attempt refund without permission; verify denial.
15. Attempt void of `paid` invoice; verify rejection until refunded; refund and then void; verify success and lock.
16. Attempt mutation on `voided` invoice (item, discount, insurance, payment); verify rejection.
17. List invoices filtered by status `issued`, patient name, date range; verify results and pagination.
18. Cross-branch invoice access attempt; verify denial.
19. Cross-organization invoice and insurance provider access attempts; verify denial.
20. Open invoice detail and payment screens after external updates; verify backend-first fetch shows latest data.
21. Open receipt print preview for `draft`, `issued`, `partially_paid`, `paid`, `voided` invoices; verify correct rendering and watermarks; verify system print dialog opens.
22. Run backend verification utilities for one-active-invoice-per-visit, branch isolation, overpayment rejection, void lock, and invoice number monotonicity.

### Implementation Constraints

- MUST build on completed `specs/002-auth-rbac`, `specs/003-org-branch-management`, `specs/004-patient-management`, `specs/005-appointment-management`, and `specs/006-visit-medical-records`.
- Domain validation, balance computation, and authorization source of truth for mutations MUST live in database functions and policies — not solely in client logic.
- MUST use architecture schema conventions; invoices and invoice items use soft delete; payments are append-only with no UPDATE/DELETE paths.
- MUST NOT implement advanced insurance claim lifecycle, automated overdue dunning, revenue analytics dashboards, multi-currency, line-level taxes, prescription printing, shift management, or AI billing in this feature.
- Cloud-only deployment enhancements are out of scope unless already supported by the local deployment path from V1-0.

### Key Entities *(include if feature involves data)*

- **Invoice**: Branch-scoped financial record required to be linked to a completed visit; carries status, totals, discount, insurance coverage, and void metadata.
- **Invoice Item**: Itemized service line on an invoice; editable only while invoice is `draft`.
- **Payment**: Append-only record of money received or refunded against an invoice; method, amount, reference, recorder, timestamp.
- **Insurance Provider**: Organization-scoped reference catalog for labeling insurance coverage on invoices.
- **Visit** (existing): `completed` visits are eligible for visit-linked invoice creation.
- **Patient** (existing): Subject of billing; invoice history accessible from patient profile.
- **Branch** (existing): Isolation scope for invoices and payments and source of branch-scoped invoice number sequence.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Serves small-to-mid-size multi-branch outpatient clinics where reception or billing staff create invoices from completed visits, collect payments in multiple methods and partial amounts, apply controlled discounts, capture insurance coverage as an informational split, and print patient receipts. Every invoice is anchored to a completed clinical visit; visit-less ("ad-hoc") invoicing is intentionally not offered in V1-6. Full insurance claims management, hospital revenue cycle automation, multi-currency operations, dunning campaigns, and enterprise ERP integration are out of scope.
- **Layer Placement**: The desktop client owns invoice creation flow from completed visits, draft invoice editor with item/discount/insurance controls, payment and refund forms, void flow with reason capture, invoice list with filters, patient invoice history surface on the patient profile, receipt print preview and OS print integration, permission-aware controls, and validation messaging. The backend platform owns secured create/issue/discount/insurance/payment/refund/void functions, server-side balance computation, transactional overpayment prevention, branch-scoped invoice number sequence, and audit writes. The database layer owns billing domain schemas, branch and organization isolation policies, one-active-invoice-per-visit constraint, payment append-only enforcement, indexes, and verification utilities. The AI layer remains absent in V1-6.
- **Data Integrity & Security**: Mutations use audit conventions; row-level policies preserve branch isolation for invoices and payments and organization isolation for insurance providers; permission keys gate sensitive operations (discount, void, refund, insurance management); invoice numbers are server-assigned and monotonic per branch; payment overpayment is prevented by server-side transactional balance recomputation; payments are append-only; defense in depth applies across UI, secured functions, and database policies. Monetary precision uses an exact decimal representation to avoid floating-point drift.
- **Failure Handling**: Save and recording failures surface clear errors without false success; invoice list and detail show last known good data with connectivity messaging when degraded; concurrent payments and item edits are protected by transactional checks and optimistic concurrency; AI unavailability does not affect billing workflows; subscription state does not block invoice creation or payment recording so clinic cashflow continues during connectivity or subscription disruptions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 95% of test runs, authorized users create an invoice from a completed visit and reach the invoice editor within 15 seconds under normal local clinic network conditions.
- **SC-002**: In 100% of invoice creation test scenarios, non-completed visits, duplicate active invoices for a visit, and cross-branch attempts are rejected.
- **SC-003**: In 100% of payment recording test scenarios, valid payments persist and update balance and status correctly; overpayments and unauthorized recordings are rejected.
- **SC-004**: In 100% of permission test scenarios, users without `invoices.apply_discount` cannot apply line-level or invoice-level discounts, users without `invoices.void` cannot void invoices, users without `payments.refund` cannot record refunds, and users without `settings.billing.manage` (i.e., non-owner/non-administrator) cannot mutate the "Allow partial payments" setting.
- **SC-009**: In 100% of partial-payment-setting test scenarios, with the setting disabled the system rejects every positive payment whose amount is less than the current balance and accepts only full-balance payments; with the setting enabled, otherwise-valid partial payments are accepted.
- **SC-005**: In 100% of concurrency test scenarios, simultaneous payments from two stations that together would exceed the balance result in exactly one accepted payment and one rejection without producing a negative balance.
- **SC-006**: In 100% of receipt preview test scenarios, draft invoices display the "DRAFT — NOT FOR PATIENT" watermark, voided invoices display the "VOIDED" watermark with reason, and all required fields render correctly.
- **SC-007**: In 100% of backend verification scenarios, cross-organization invoice, payment, and insurance provider access is blocked.
- **SC-008**: Reception or billing staff can complete a full billing workflow (create from completed visit → items → optional discount → optional insurance → issue → record payment → print receipt) in under 5 minutes in usability testing with representative sample data.

## Assumptions

- `specs/002-auth-rbac`, `specs/003-org-branch-management`, `specs/004-patient-management`, `specs/005-appointment-management`, and `specs/006-visit-medical-records` are implemented.
- Permission keys `invoices.view`, `invoices.create`, `invoices.apply_discount`, `invoices.void`, `payments.record`, `payments.refund`, `insurance.manage`, and `settings.billing.manage` are seeded per FR-021 against the existing V1-1 five-role catalog. No new role is introduced; `receptionist` receives the three basic billing keys, and all sensitive keys (including the non-delegable `settings.billing.manage`) are restricted to `owner`/`administrator` by default.
- The organization-level "Allow partial payments" setting defaults to `false` on organization creation; clinics that want partial collection must opt in explicitly via an owner/administrator action.
- Each organization operates in a single currency configured at the organization level (V1 scope). Multi-currency is deferred.
- Monetary amounts use a fixed exact-decimal scale of 2 across all billing tables per NFR-007; banker's rounding is applied to percentage-discount intermediate results before persistence. The client never derives balances for write decisions.
- The invoice number prefix uses the existing `branches.code` field from V1-2 (already organization-unique when set). V1-6 introduces no new branch schema; instead, issuance is rejected when `branches.code` is NULL, prompting an administrator to populate it in branch settings before invoices can be issued at that branch.
- Insurance coverage in V1-6 is an informational split entered at invoice creation; claim submission and settlement workflows are V3-2 (Advanced Billing).
- Overdue detection, dunning, and revenue analytics dashboards are deferred to V3-1 (Analytics) and V3-2 (Advanced Billing).
- Receipt print uses the operating system's native print pipeline; PDF export beyond OS "Print to PDF" is not required in V1-6.
- AI remains optional and non-blocking for all billing flows in V1-6; the V2 billing agent is built on top of these RPCs and approval cards rather than replacing manual flows.
- `specs/operations/billing.spec.md` will be authored later; this feature spec is authoritative for V1-6 until that shared spec exists.
