# P4.8 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Transfer `grant_id` index n

**Question:** In the transfer `grant_id` (03 §7), what is `n` in SHA-256 over `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n? The cited formula does not define its meaning, its domain, or how many `grant_request` rows one transfer records.

**Assumption:** `n` is the 0-based index of that element in the transfer `package` (§3.2), written as decimal digits with no leading zeros. The package is a JSON array ordered by `position`, one object per term that has not ended, so `n` runs through the integers 0 … k−1 where k is that count. One transfer records one `grant_request` per such term (k rows, and none when the package is empty).

**Why:** 03 §3.2 already stores the package as one object per not-ended term, ordered by `position`, and §5.3 recreates those moved terms as transfer grants. The `n` suffix exists so each of those terms has its own deterministic `grant_id`; a single id per `transfer_id` would not. P4.8 records transfer grant requests (plural), one per package element. The index in that position order is stable across retries, which is what the §7 idempotency note requires.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§7 `grant_id` transfer form).
