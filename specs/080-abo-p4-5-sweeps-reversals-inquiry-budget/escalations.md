# P4.5 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. FM-01 callback crash sweep

**Question:** Section 5 D1 assigns FM-01, FM-02, FM-03, and FM-18 to P4.5. The P4.5 E2E list names FM-02 (E2E-P4.5-01), FM-03, and FM-18 (E2E-P4.5-02) only. FM-01 (ABO crashes after receiving a callback: the callback was answered with 5xx or the work row is open, and the sweep inquires within 2–20 minutes) has no E2E id. Specify cannot add an E2E id. Which existing E2E-P4.5 scenario covers FM-01, or which new scenario id should the delivery plan add?

**Assumption:** No existing P4.5 scenario covers FM-01. E2E-P4.5-12 is the scenario. ABO crashes after receiving a callback, the callback was answered with 5xx or the work row is open, and the sweep inquires within 2–20 minutes. §5 D1 names that scenario as `FM-01 P4.5-12`.

**Why:** E2E-P4.5-01 is a blocked callback (FM-02 / A3) found by the +2 min sweep. E2E-P4.5-02 is HMAC failure on every callback (FM-03 / FM-18 / A23). Neither states a crash after a received callback, a 5xx answer, or an open work row. The next free id on the P4.5 list is E2E-P4.5-12, and the 05 §4 owner cell names a scenario the same way `P4.4-04` is named: `P4.5-12`. The FM-01 row in 05 §4 already states that recovery and does not carry E2E ids.

**Amended:** `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P4.5 E2E list; §5 D1 owner row for 05 §4).

## 2. Full versus partial, and the reversal dedupe key

**Question:** For a provider refund, when is the reversal full (`is_full`, effects `tombstone`, `end_current`, `remove_queued`, or `none`) rather than partial (`review_partial`), and what dedupe key makes a parent-flag notification and a child-transaction notification of the same refund a single `reversal`? 03 §2.7 names `cumulative_reversed_minor` and `is_full` but gives no comparison. 03 §5.5 selects the effect from "Full" and "Partial" but does not define them. The P4.5 line for E2E-P4.5-05 requires that dedupe key and does not name its parts.

**Assumption:** A reversal is full when `cumulative_reversed_minor` is at least the payment's `amount_minor`, and partial when `cumulative_reversed_minor` is below that amount. The reversal's own `amount_minor` is not the test. The dedupe key is the SR-02 state-change key with the transaction part fixed as the parent: `provider`, the parent transaction (the reference inside `payment_id`, never the child transaction id), normalized state `reversal`, and `cumulative_reversed_minor`. A child notification is rewritten onto that parent before the key is formed, so both notifications of the same refund insert one `reversal`.

**Why:** §2.6 already stores the payment's `amount_minor`, and §2.7 already stores `cumulative_reversed_minor` beside `is_full`. §7 already names the state-change key as provider, transaction, normalized state, and cumulative reversed amount (SR-02; 01 §3.3), and 01 §3.6 already says the adapter folds a parent-flag resend and a child transaction into one reversal against the parent payment. 04 §5.3 already takes the cumulative from the inquiry. The missing sentences were only the comparison and the rule that the key's transaction is the parent. E2E-P4.5-05 keeps the words "the dedupe key"; those four parts now live in §2.7, which P4.5 already reads.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§2.7 reversal identity and `is_full`; §5.5 effect rule).

## 3. Per-minute provider-inquiry budget

**Question:** What integer is the shared per-minute provider-inquiry budget (FR-010, 05 §1 budget sentence, E2E-P4.5-10)? The cited sentence only says the cap is set from Paymob's rate limit. P4.3 R-2 recorded that Paymob's numeric inquiry limit was not observed, and this unit's Spikes cell is None, so the plan cannot measure or invent that cap.

**Assumption:** The shared per-minute provider-inquiry budget is 2. Sweeps and work rows share that one cap. When more than 2 provider inquiries are due, confirmation and grant work rows are served first, and every inquiry that does not fit stays due.

**Why:** 05 §1 sets the cap from Paymob's rate limit and does not state an integer. P4.3 R-2 records that Paymob's numeric inquiry limit was not observed, and this unit's Spikes cell is None. 05 §7's worked example is under 2 reversal inquiries a minute before checkout sweeps, so 2 is the smallest integer that covers that steady reversal rate. E2E-P4.5-10 proves the rule by scheduling more than 2 due provider inquiries, including confirm and grant work rows: those rows are served first and none are dropped. No spike, config surface, or second cap is added.

**Amended:** `specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/spec.md` (Clarifications; User Story 4; E2E-P4.5-10; FR-010; Assumptions).
