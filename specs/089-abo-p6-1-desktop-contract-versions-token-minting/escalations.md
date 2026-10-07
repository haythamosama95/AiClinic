# P6.1 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Coverage codes that refresh status

**Question:** Which denial codes count as a “coverage code” that must refresh `get_ai_status` (04 §3.4, first bullet “When to read status”)?

**Assumption:** A coverage code is `allowance_exhausted`, `coverage_lapsed`, or `coverage_unknown`. An AI denial with one of those codes refreshes `get_ai_status`.

**Why:** 01 groups those three as the coverage denials, apart from safety limits and from suspension. The refresh exists so a desktop denied because coverage changed re-reads the projection (FR-64). P6.2 still owns denial display.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§3.4 first bullet “When to read status”); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P6.1 Implements).
